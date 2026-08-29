//+------------------------------------------------------------------+
//|                                          SSR_ReplayController.mqh |
//|                                SS Replay - Replay Controller(L2) |
//|                                                                  |
//|  The engine. Owns the state machine and the pump loop, and       |
//|  nothing else - data comes through CSSRDataSource, output goes   |
//|  through CSSRReplaySink, and neither is created here.            |
//|                                                                  |
//|  IT DOES NOT SLEEP AND IT DOES NOT READ A CLOCK.                 |
//|  Pump(wall_delta_ms) is called by whoever owns the thread: the   |
//|  Service in production, a test loop with fixed deltas in a unit  |
//|  test. That single decision is what makes the engine both        |
//|  deterministic and testable without MetaTrader.                  |
//+------------------------------------------------------------------+
#ifndef SSR_REPLAY_CONTROLLER_MQH
#define SSR_REPLAY_CONTROLLER_MQH

#include "../Common/SSR_Types.mqh"
#include "../Common/SSR_Time.mqh"
#include "../Common/SSR_Log.mqh"
#include "SSR_ReplayState.mqh"
#include "SSR_ReplayClock.mqh"
#include "SSR_ReplayTimeline.mqh"
#include "SSR_ReplayCursor.mqh"
#include "SSR_FutureGuard.mqh"
#include "SSR_Snapshot.mqh"
#include "SSR_IDataSource.mqh"
#include "SSR_IReplaySink.mqh"
#include "SSR_TickSynthesizer.mqh"
#include "SSR_Metrics.mqh"
#include "SSR_PumpBudget.mqh"
#include "SSR_FidelityPolicy.mqh"
#include "SSR_SnapshotStore.mqh"
#include "SSR_PositionFile.mqh"
#include "SSR_ITickObserver.mqh"

//--- The per-pump ceiling is no longer a constant. CSSRPumpBudget
//--- derives it from measured cost per tick; this only bounds the
//--- reserved read buffer so a single read cannot allocate wildly.
#define SSR_BAR_READ_CEILING    8192

//+------------------------------------------------------------------+
class CSSRReplayController
  {
private:
   SSRReplayState      m_state;
   SSRReplayClock      m_clock;
   SSRReplayTimeline   m_timeline;
   SSRReplayCursor     m_cursor;
   CSSRFutureGuard     m_guard;
   CSSRTickSynthesizer m_synth;
   CSSRMetrics         m_metrics;
   CSSRPumpBudget      m_budget;
   CSSRFidelityPolicy  m_fidelity;
   CSSRSnapshotStore   m_snaps;
   CSSRPositionFile    m_posfile;

   //--- whoever is watching the stream. Core knows only that they are
   //--- observers - not that one of them keeps a trading account.
   CSSRTickObserver   *m_obs[8];
   int                 m_obs_count;

   CSSRDataSource     *m_source;      // not owned
   CSSRReplaySink     *m_sink;        // not owned
   CSSRLog            *m_log;         // not owned; may be NULL

   //--- reusable buffers; never reallocated inside the pump loop
   MqlRates            m_bars[];
   MqlTick             m_ticks[];

   int                 m_digits;
   double              m_point;
   //--- per-pump accumulators, read and cleared by Pump()
   double              m_pump_emit_us;
   bool                m_pump_deferred;
   long                m_warmup_bars;

   //--- state machine -----------------------------------------------
   bool                Transition(const ENUM_SSR_STATE to)
     {
      ENUM_SSR_STATE from = m_state.status;
      if(!SSRCanTransition(from, to))
        {
         SetError(SSR_ERR_INVALID_STATE,
                  StringFormat("illegal transition %s -> %s",
                               SSRStateName(from), SSRStateName(to)));
         return false;
        }
      if(from == to)
         return true;

      m_state.status = to;
      if(m_log != NULL && m_log.IsDebug())
         m_log.Debug(StringFormat("state %s -> %s", SSRStateName(from), SSRStateName(to)));
      if(m_sink != NULL)
         m_sink.OnStateChanged(from, to);
      return true;
     }

   void                SetError(const ENUM_SSR_ERR e, const string text)
     {
      m_state.last_error      = e;
      m_state.last_error_text = text;
      if(e != SSR_OK && m_log != NULL && m_log.IsError())
         m_log.Error(StringFormat("%s: %s", SSRErrName(e), text));
     }

   void                ClearError(void)
     {
      m_state.last_error      = SSR_OK;
      m_state.last_error_text = "";
     }

   //--- keep the published state in step with the internal parts
   void                Publish(void)
     {
      m_state.current_msc    = m_clock.now_msc;
      m_state.start_msc      = m_timeline.start_msc;
      m_state.end_msc        = m_timeline.end_msc;
      m_state.data_first_msc = m_timeline.data_first_msc;
      m_state.data_last_msc  = m_timeline.data_last_msc;
      m_state.speed_x100     = m_clock.speed_x100;
      m_state.ticks_emitted  = m_cursor.tick_count;
      m_state.bars_consumed  = m_cursor.bar_count;
     }


   //--- publishing. Deliberately trivial: an observer that is slow
   //--- slows the replay, and that is the observer's problem to solve.
   void                PublishBar(const MqlRates &bar, const bool synthetic)
     {
      for(int i = 0; i < m_obs_count; i++)
         if(m_obs[i] != NULL)
            m_obs[i].OnBarContext(bar, synthetic);
     }

   void                PublishTicks(const MqlTick &ticks[], const int count)
     {
      for(int i = 0; i < m_obs_count; i++)
         if(m_obs[i] != NULL)
            m_obs[i].OnTicks(ticks, count);
     }

   void                PublishRewind(const long msc)
     {
      for(int i = 0; i < m_obs_count; i++)
         if(m_obs[i] != NULL)
            m_obs[i].OnRewind(msc);
     }

   //+------------------------------------------------------------------+
   //| Keep only ticks inside [lo, hi].                                 |
   //|                                                                  |
   //| The upper bound is the guard's job, but the LOWER bound is just  |
   //| as load-bearing: a synthesised bar always spans its whole minute,|
   //| so when a pump ends mid-bar the next pump re-synthesises the same|
   //| bar from its open. Without this trim those early ticks would be  |
   //| emitted twice and MetaTrader would rebuild a corrupt candle.     |
   //+------------------------------------------------------------------+
   int                 TrimWindow(MqlTick &ticks[], const int count,
                                  const long lo, const long hi)
     {
      int keep = 0;
      for(int i = 0; i < count; i++)
        {
         if(ticks[i].time_msc >= lo && ticks[i].time_msc <= hi)
           {
            if(keep != i)
               ticks[keep] = ticks[i];
            keep++;
           }
        }
      return keep;
     }

   //+------------------------------------------------------------------+
   //| Emit everything owed for the window (from_msc, to_msc].          |
   //| Returns ticks emitted, or -1 on failure.                         |
   //+------------------------------------------------------------------+
   int                 EmitWindow(const long from_msc, const long to_msc)
     {
      if(m_source == NULL) { SetError(SSR_ERR_NO_SOURCE, "no data source"); return -1; }
      if(m_sink   == NULL) { SetError(SSR_ERR_NO_SINK,   "no sink");        return -1; }

      long lo = from_msc;
      long hi = to_msc;

      //--- guard layer 1: clamp before we even ask the data layer
      if(!m_guard.ClampRange(lo, hi))
         return 0;                         // nothing legal to read; not an error

      int emitted = 0;

      //--- the fidelity for THIS window, which may differ from the one
      //--- the user asked for; the policy records why and the panel says so
      ENUM_SSR_FIDELITY fid = m_fidelity.Decide(hi - lo);

      if(fid == SSR_FIDELITY_FULL_TICK)
        {
         CSSRTickProvider *tp = m_source.Ticks();
         if(tp == NULL)
           {
            //--- the source cannot honour this fidelity. Degrade rather
            //--- than fail, and say so - silently pretending would be the
            //--- dishonest option.
            if(m_log != NULL && m_log.IsWarn())
               m_log.Warn("source has no tick provider; falling back to SYNTHETIC_TICK");
            m_fidelity.SetTicksAvailable(false);
            fid = m_fidelity.Decide(hi - lo);
           }
         else
           {
            int n = tp.ReadTicks(m_state.symbol, lo - 1, hi, m_ticks);
            if(n < 0)
              {
               SetError(tp.LastError(), "tick read failed: " + tp.LastErrorText());
               return -1;
              }
            //--- guard layer 2 already ran inside the provider; this is
            //--- the belt-and-braces pass over what came back
            n = m_guard.FilterTicks(m_ticks, n);
            ulong t_emit_ft = GetMicrosecondCount();
            if(n > 0 && !m_sink.EmitTicks(m_ticks, n))
              {
               SetError(SSR_ERR_SINK_FAILED, "sink rejected ticks: " + m_sink.LastErrorText());
               return -1;
              }
            m_pump_emit_us += (double)(GetMicrosecondCount() - t_emit_ft);
            if(n > 0)
               PublishTicks(m_ticks, n);
            emitted = n;
            m_cursor.Advance(hi, emitted, 0);
            return emitted;
           }
        }

      //--- bar-driven fidelities -------------------------------------
      CSSRBarProvider *bp = m_source.Bars();
      if(bp == NULL) { SetError(SSR_ERR_NO_DATA, "source has no bar provider"); return -1; }

      //--- read whole M1 bars overlapping the window. A bar is consumed
      //--- when its OPEN time falls inside the window, so alignment is
      //--- done on bar boundaries rather than on the raw instants.
      long bar_lo = SSRBarOpenMsc(lo, PERIOD_M1);
      long bar_hi = SSRBarOpenMsc(hi, PERIOD_M1);

      int nb = bp.ReadBars(m_state.symbol, bar_lo, bar_hi, m_bars);
      if(nb < 0)
        {
         SetError(bp.LastError(), "bar read failed: " + bp.LastErrorText());
         return -1;
        }
      nb = m_guard.FilterRates(m_bars, nb);
      if(nb <= 0)
        {
         m_cursor.Advance(hi, 0, 0);
         return 0;
        }

      //--- the ceiling comes from what a tick actually costs on this
      //--- machine, not from a constant. Anything above it stays owed.
      int cap = m_budget.MaxBars(m_synth.TicksForBar(fid));
      if(nb > cap)
        {
         nb = cap;
         m_budget.NoteDeferral();
         m_pump_deferred = true;
        }

      //--- skip bars already consumed, so a pump never re-emits
      int first = 0;
      while(first < nb && SSRToMsc(m_bars[first].time) < bar_lo)
         first++;

      int per_bar = m_synth.TicksForBar(fid);
      int need    = (nb - first) * per_bar;
      if(need <= 0)
        {
         m_cursor.Advance(hi, 0, 0);
         return 0;
        }
      if(ArraySize(m_ticks) < need && ArrayResize(m_ticks, need) < need)
        {
         SetError(SSR_ERR_INTERNAL, "tick buffer allocation failed");
         return -1;
        }

      int written = 0;
      int bars_used = 0;
      for(int i = first; i < nb; i++)
        {
         //--- the bar reaches observers BEFORE the ticks made from it.
         //--- With synthesised ticks the order of prices inside the bar
         //--- is our assumption, so an observer must be able to see the
         //--- whole range before acting on any single tick.
         PublishBar(m_bars[i], fid != SSR_FIDELITY_FULL_TICK);

         int w = (fid == SSR_FIDELITY_BAR)
                 ? m_synth.SynthesizeClose(m_bars[i], m_ticks, written)
                 : m_synth.Synthesize(m_bars[i], m_ticks, written);
         if(w <= 0)
            break;
         written += w;
         bars_used++;
         m_cursor.NoteBar(SSRToMsc(m_bars[i].time));
        }

      //--- trim to the window on BOTH ends: the guard would only remove
      //--- the future tail, and the head is where duplicates come from
      written = TrimWindow(m_ticks, written, lo, hi);
      written = m_guard.FilterTicks(m_ticks, written);

      ulong t_emit = GetMicrosecondCount();
      if(written > 0 && !m_sink.EmitTicks(m_ticks, written))
        {
         SetError(SSR_ERR_SINK_FAILED, "sink rejected ticks: " + m_sink.LastErrorText());
         return -1;
        }
      m_pump_emit_us += (double)(GetMicrosecondCount() - t_emit);
      if(written > 0)
         PublishTicks(m_ticks, written);

      emitted = written;

      //--- when the per-pump cap bit, the cursor must stop at the end of
      //--- the last bar actually consumed. Advancing it to `hi` anyway
      //--- would silently drop every bar above the cap; stopping short
      //--- leaves them owed, and the next pump picks them up.
      long consumed_to = hi;
      if(bars_used > 0 && (first + bars_used) < nb)
        {
         long last_bar = SSRToMsc(m_bars[first + bars_used - 1].time);
         consumed_to = last_bar + SSR_MSC_PER_MIN - 1;
         if(consumed_to > hi)
            consumed_to = hi;
        }
      m_cursor.Advance(consumed_to, emitted, bars_used);
      return emitted;
     }

public:
                     CSSRReplayController(void)
     : m_source(NULL), m_sink(NULL), m_log(NULL),
       m_digits(5), m_point(0.00001), m_pump_emit_us(0.0),
       m_pump_deferred(false), m_warmup_bars(0)
     {
      m_state.Init();
      m_clock.Init();
      m_timeline.Init();
      m_cursor.Init();
      ArrayResize(m_bars, 1024);
      ArrayResize(m_ticks, 8192);
      m_budget.Attach(GetPointer(m_metrics));
      m_obs_count = 0;
      for(int i = 0; i < 8; i++)
         m_obs[i] = NULL;
     }

                    ~CSSRReplayController(void)
     {
      //--- the guard dies with this object, so nothing may still point
      //--- at it. Closes the dangling-pointer TODO from Phase 1.
      if(m_source != NULL)
         m_source.DetachGuard();
     }

   //--- wiring ------------------------------------------------------
   void              SetLog(CSSRLog *l) { m_log = l; }

   void              Attach(CSSRDataSource *source, CSSRReplaySink *sink)
     {
      //--- a source being swapped out must not keep pointing at our guard
      if(m_source != NULL && m_source != source)
         m_source.DetachGuard();
      m_source = source;
      m_sink   = sink;
      if(m_source != NULL)
         m_source.SetGuard(GetPointer(m_guard));
     }

   //+------------------------------------------------------------------+
   //| Register something that watches the stream.                      |
   //|                                                                  |
   //| Core never learns what an observer does with what it sees. That  |
   //| is what keeps the trading engine, and later the statistics and   |
   //| strategy layers, out of the replay core entirely.                |
   //+------------------------------------------------------------------+
   bool              AddObserver(CSSRTickObserver *o)
     {
      if(o == NULL || m_obs_count >= 8)
         return false;
      for(int i = 0; i < m_obs_count; i++)
         if(m_obs[i] == o)
            return true;
      m_obs[m_obs_count++] = o;
      return true;
     }

   void              ClearObservers(void)
     {
      for(int i = 0; i < 8; i++)
         m_obs[i] = NULL;
      m_obs_count = 0;
     }

   int               ObserverCount(void) { return m_obs_count; }

   CSSRDataSource   *Source(void) { return m_source; }
   CSSRReplaySink   *Sink(void)   { return m_sink; }

   //--- read-only views for the UI and for tests
   SSRReplayState    State(void)     { return m_state; }

   //--- direct accessors: MQL5 is unreliable about reading a member off a
   //--- struct returned by value, so callers never have to
   ENUM_SSR_ERR      LastError(void)     { return m_state.last_error; }
   string            LastErrorText(void) { return m_state.last_error_text; }
   string            Symbol(void)        { return m_state.symbol; }
   ENUM_SSR_FIDELITY Fidelity(void)      { return m_state.fidelity; }
   long              SpeedX100(void)     { return m_state.speed_x100; }
   long              TicksEmitted(void)  { return m_cursor.tick_count; }
   long              BarsConsumed(void)  { return m_cursor.bar_count; }
   long              StartMsc(void)      { return m_timeline.start_msc; }
   long              EndMsc(void)        { return m_timeline.end_msc; }
   bool              TimelineValid(void) { return m_timeline.IsValid(); }
   string            TimelineText(void)  { return m_timeline.ToString(); }
   ENUM_SSR_STATE    Status(void)    { return m_state.status; }
   long              Now(void)       { return m_clock.now_msc; }
   double            Progress(void)  { return m_clock.Progress(); }
   long              Violations(void){ return m_guard.Violations(); }
   SSRReplayTimeline Timeline(void)  { return m_timeline; }
   SSRReplayCursor   Cursor(void)    { return m_cursor; }

   //--- settings ----------------------------------------------------
   void              SetSymbolSpec(const int digits, const double point)
     {
      m_digits = digits;
      m_point  = point;
      m_synth.Configure(digits, point);
     }

   void              SetSpreadPoints(const double p) { m_synth.SetSpreadPoints(p); }
   void              SetTicksPerBar(const int n)     { m_synth.SetTicksPerBar(n); }
   void              SetWarmupBars(const long n)     { m_warmup_bars = (n < 0 ? 0 : n); }

   bool              SetSpeedX100(const long s)
     {
      m_clock.SetSpeedX100(s);
      m_state.speed_x100 = m_clock.speed_x100;
      return true;
     }

   bool              SetFidelity(const ENUM_SSR_FIDELITY f)
     {
      m_state.fidelity = f;
      m_fidelity.SetRequested(f);
      return true;
     }

   //--- a user who pins fidelity gets it, bulk moment or not
   void              LockFidelity(const bool on) { m_fidelity.SetLocked(on); }
   bool              FidelityLocked(void)        { return m_fidelity.IsLocked(); }
   ENUM_SSR_FIDELITY EffectiveFidelity(void)     { return m_fidelity.Effective(); }
   bool              FidelityDegraded(void)      { return m_fidelity.IsDegraded(); }
   string            FidelityReason(void)        { return m_fidelity.ReasonText(); }

   //--- measurement, exposed so the UI can show real numbers and the
   //--- catalogue can quote the next session from this one
   void              PerfInto(SSRPerfSnapshot &out) { m_metrics.Snapshot(out); }
   double            SeedBarsPerSec(void)           { return m_metrics.SeedBarsPerSec(); }
   bool              PerfCalibrated(void)           { return m_metrics.IsCalibrated(); }
   void              SetPumpBudgetMs(const double ms) { m_budget.SetBudgetMs(ms); }
   string            BudgetText(void)               { return m_budget.ToString(); }

   void              SetDataMode(const ENUM_SSR_DATA_MODE m) { m_state.data_mode = m; }

   //+------------------------------------------------------------------+
   //| Configure and load. IDLE -> LOADING -> READY.                    |
   //| `end_msc <= 0` means replay to the end of the available data.    |
   //+------------------------------------------------------------------+
   bool              Load(const string symbol, const long start_msc, const long end_msc)
     {
      ClearError();

      if(m_source == NULL) { SetError(SSR_ERR_NO_SOURCE, "attach a data source first"); Transition(SSR_STATE_ERROR); return false; }
      if(m_sink   == NULL) { SetError(SSR_ERR_NO_SINK,   "attach a sink first");        Transition(SSR_STATE_ERROR); return false; }
      if(symbol == "")     { SetError(SSR_ERR_INVALID_ARG, "empty symbol");             return false; }
      if(start_msc <= 0)   { SetError(SSR_ERR_INVALID_ARG, "invalid start time");       return false; }

      if(!Transition(SSR_STATE_LOADING))
         return false;

      m_state.symbol         = symbol;
      m_state.base_timeframe = PERIOD_M1;

      if(!m_source.IsOpen() && !m_source.Open(symbol))
        {
         SetError(SSR_ERR_LOAD_FAILED, "data source could not open " + symbol);
         Transition(SSR_STATE_ERROR);
         return false;
        }

      //--- discover what exists before deciding what to replay
      CSSRHistoryProvider *hp = m_source.History();
      if(hp == NULL) { SetError(SSR_ERR_NO_DATA, "source has no history provider"); Transition(SSR_STATE_ERROR); return false; }

      SSRDataRange range;
      range.Init();
      //--- discovery must see the real extent of the data, so the guard
      //--- steps aside for it and is re-armed immediately afterwards
      m_guard.Disarm();
      bool ok = hp.Discover(symbol, range);
      if(!ok || !range.available)
        {
         SetError(SSR_ERR_NO_DATA, "no data available for " + symbol);
         Transition(SSR_STATE_ERROR);
         return false;
        }

      m_timeline.Init();
      m_timeline.SetDataBounds(range.first_msc, range.last_msc);
      if(!m_timeline.SetWindow(start_msc, end_msc))
        {
         SetError(SSR_ERR_OUT_OF_RANGE,
                  StringFormat("requested window is outside the data (%s..%s)",
                               SSRFormatMsc(range.first_msc), SSRFormatMsc(range.last_msc)));
         Transition(SSR_STATE_ERROR);
         return false;
        }
      m_timeline.SetWarmupBars(m_warmup_bars);

      //--- tell the source what it is about to serve, so anything it
      //--- buffers can be sized from the session instead of a constant
      m_source.OnSessionPlanned((m_timeline.end_msc - m_timeline.start_msc) / SSR_MSC_PER_MIN);

      if(!hp.Ensure(symbol, (m_timeline.warmup_first_msc > 0 ? m_timeline.warmup_first_msc
                                                             : m_timeline.start_msc),
                    m_timeline.end_msc))
        {
         SetError(SSR_ERR_LOAD_FAILED, "history could not be prepared");
         Transition(SSR_STATE_ERROR);
         return false;
        }

      if(!m_clock.Configure(m_timeline.start_msc, m_timeline.end_msc))
        {
         SetError(SSR_ERR_INTERNAL, "clock configuration failed");
         Transition(SSR_STATE_ERROR);
         return false;
        }
      m_clock.SetSpeedX100(m_state.speed_x100);
      m_fidelity.SetRequested(m_state.fidelity);
      m_fidelity.SetTicksAvailable(range.has_ticks);
      m_metrics.Reset();

      //--- The sink may be able to reuse a warmup it seeded previously,
      //--- but only if it knows which range this session needs BEFORE it
      //--- prepares - preparing is what would destroy those very bars.
      //--- Announced through the generic lifecycle hook so Core stays
      //--- unaware that any particular sink caches anything.
      m_sink.OnWarmupPlanned(m_timeline.warmup_first_msc > 0
                             ? m_timeline.warmup_first_msc : m_timeline.start_msc,
                             m_timeline.start_msc - 1);

      if(!m_sink.Prepare(symbol, m_digits, m_point))
        {
         SetError(SSR_ERR_SINK_FAILED, "sink preparation failed: " + m_sink.LastErrorText());
         Transition(SSR_STATE_ERROR);
         return false;
        }

      //--- seed the warmup window, then arm the guard on the start
      if(!SeedWarmup())
         return false;

      m_cursor.Init();
      m_cursor.RewindTo(m_timeline.start_msc);
      m_guard.ResetCounters();
      m_guard.Arm(m_timeline.start_msc);
      m_snaps.Clear();

      for(int i = 0; i < m_obs_count; i++)
         if(m_obs[i] != NULL)
            m_obs[i].OnSessionStart(symbol, m_digits, m_point, m_timeline.start_msc);

      Publish();
      if(!Transition(SSR_STATE_READY))
         return false;

      if(m_log != NULL && m_log.IsInfo())
         m_log.Info("loaded " + m_timeline.ToString());
      return true;
     }

   //+------------------------------------------------------------------+
   //| Push warmup history to the sink in one bulk operation.           |
   //| The guard is armed on the replay START for this, so the warmup   |
   //| itself can never carry a bar from beyond it.                     |
   //+------------------------------------------------------------------+
   bool              SeedWarmup(void)
     {
      if(m_warmup_bars <= 0 || m_timeline.warmup_first_msc <= 0)
         return true;

      long lo_plan = m_timeline.warmup_first_msc;
      long hi_plan = m_timeline.start_msc - 1;

      //--- ask before reading. The read is the expensive part, so a sink
      //--- that already holds this range must be able to stop it.
      if(!m_sink.NeedsWarmup(lo_plan, hi_plan))
        {
         if(m_log != NULL && m_log.IsInfo())
            m_log.Info("warmup already present in the sink; skipping the read");
         return true;
        }

      CSSRBarProvider *bp = m_source.Bars();
      if(bp == NULL)
        {
         SetError(SSR_ERR_NO_DATA, "source has no bar provider");
         Transition(SSR_STATE_ERROR);
         return false;
        }

      m_guard.Arm(m_timeline.start_msc - 1);   // strictly before the start

      long lo = m_timeline.warmup_first_msc;
      long hi = m_timeline.start_msc - 1;

      MqlRates seed[];
      ulong t_seed = GetMicrosecondCount();
      int n = bp.ReadBars(m_state.symbol, lo, hi, seed);
      if(n < 0)
        {
         SetError(bp.LastError(), "warmup read failed: " + bp.LastErrorText());
         Transition(SSR_STATE_ERROR);
         return false;
        }
      n = m_guard.FilterRates(seed, n);
      if(n > 0 && !m_sink.SeedBars(seed, n))
        {
         SetError(SSR_ERR_SINK_FAILED, "sink rejected warmup: " + m_sink.LastErrorText());
         Transition(SSR_STATE_ERROR);
         return false;
        }

      //--- the seed measures itself, so the next session is quoted from
      //--- this machine rather than from a constant
      m_metrics.RecordSeed(n, (double)(GetMicrosecondCount() - t_seed) / 1000.0);

      if(m_log != NULL && m_log.IsInfo())
         m_log.Info(StringFormat("warmup seeded: %d bars up to %s at %.0f bars/s",
                                 n, SSRFormatMsc(hi), m_metrics.SeedBarsPerSec()));
      return true;
     }

   //--- transport ---------------------------------------------------
   bool              Play(void)
     {
      ClearError();
      if(m_state.status == SSR_STATE_COMPLETED)
        {
         SetError(SSR_ERR_INVALID_STATE, "replay already completed; seek or reset first");
         return false;
        }
      return Transition(SSR_STATE_PLAYING);
     }

   bool              Pause(void)
     {
      ClearError();
      if(m_state.status != SSR_STATE_PLAYING)
         return true;                    // pausing an idle replay is a no-op
      return Transition(SSR_STATE_PAUSED);
     }

   //+------------------------------------------------------------------+
   //| The pump. Advances the clock by `wall_delta_ms` of real time and |
   //| emits everything that became due. Returns ticks emitted, or -1.  |
   //|                                                                  |
   //| Deterministic: identical delta sequences produce identical output|
   //+------------------------------------------------------------------+
   int               Pump(const ulong wall_delta_ms)
     {
      if(m_state.status != SSR_STATE_PLAYING)
         return 0;

      ulong t_pump   = GetMicrosecondCount();
      m_pump_emit_us  = 0.0;
      m_pump_deferred = false;

      long before = m_clock.now_msc;
      long now    = m_clock.Advance(wall_delta_ms);

      //--- move the horizon with the clock BEFORE any read happens
      m_guard.SetHorizon(now);

      int emitted = 0;
      if(now > before)
        {
         long lo, hi;
         if(m_cursor.PendingRange(now, lo, hi))
           {
            emitted = EmitWindow(lo, hi);
            if(emitted < 0)
              {
               Transition(SSR_STATE_ERROR);
               Publish();
               return -1;
              }
           }
        }

      for(int i = 0; i < m_obs_count; i++)
         if(m_obs[i] != NULL)
            m_obs[i].OnClock(m_clock.now_msc);

      Publish();

      m_metrics.RecordPump((double)(GetMicrosecondCount() - t_pump),
                           m_pump_emit_us, emitted,
                           (int)m_cursor.bar_count, m_pump_deferred);

      //--- checkpoint on a replay-time interval, so a later step back
      //--- restores state instead of reconstructing it
      if(m_snaps.IsDue(m_clock.now_msc))
        {
         SSRSnapshot cp;
         TakeSnapshot(cp, "auto");
         m_snaps.Checkpoint(cp);
        }

      if(m_clock.IsCompleted())
        {
         Transition(SSR_STATE_COMPLETED);
         if(m_log != NULL && m_log.IsInfo())
            m_log.Info("replay completed at " + SSRFormatMsc(m_clock.now_msc));
        }
      return emitted;
     }

   //+------------------------------------------------------------------+
   //| Advance by whole M1 bars without waiting for real time.          |
   //| Phase 8 builds Step Forward on this.                             |
   //+------------------------------------------------------------------+
   int               StepBars(const int bars)
     {
      ClearError();
      if(bars <= 0)
         return 0;
      if(m_state.status != SSR_STATE_PAUSED && m_state.status != SSR_STATE_READY &&
         m_state.status != SSR_STATE_PLAYING)
        {
         SetError(SSR_ERR_INVALID_STATE, "cannot step from " + SSRStateName(m_state.status));
         return -1;
        }

      long target = SSRNextBarOpenMsc(m_clock.now_msc, PERIOD_M1)
                    + (long)(bars - 1) * SSR_MSC_PER_MIN - 1;
      if(target > m_timeline.end_msc)
         target = m_timeline.end_msc;

      long before = m_clock.now_msc;
      m_clock.SeekTo(target);
      m_guard.SetHorizon(m_clock.now_msc);

      int emitted = 0;
      if(m_clock.now_msc > before)
        {
         long lo, hi;
         if(m_cursor.PendingRange(m_clock.now_msc, lo, hi))
           {
            emitted = EmitWindow(lo, hi);
            if(emitted < 0)
              {
               Transition(SSR_STATE_ERROR);
               Publish();
               return -1;
              }
           }
        }

      Publish();
      if(m_clock.IsCompleted())
         Transition(SSR_STATE_COMPLETED);
      else if(m_state.status == SSR_STATE_READY)
         Transition(SSR_STATE_PAUSED);
      return emitted;
     }

   //+------------------------------------------------------------------+
   //| Move to an arbitrary instant.                                    |
   //|                                                                  |
   //| Backwards seeks truncate the sink from the target, because the   |
   //| data after it must genuinely cease to exist - hiding it would    |
   //| reintroduce exactly the leak this product exists to prevent.     |
   //+------------------------------------------------------------------+
   bool              SeekTo(const long target_msc)
     {
      ClearError();
      if(!m_clock.IsConfigured())
        {
         SetError(SSR_ERR_INVALID_STATE, "seek before load");
         return false;
        }
      if(m_sink == NULL)
        {
         SetError(SSR_ERR_NO_SINK, "no sink");
         return false;
        }

      long clamped  = SSRClampMsc(target_msc, m_timeline.start_msc, m_timeline.end_msc);
      bool backward = (clamped < m_clock.now_msc);

      if(backward)
        {
         long actual = m_sink.TruncateFrom(clamped);
         if(actual < 0)
           {
            SetError(SSR_ERR_SINK_FAILED, "truncate failed: " + m_sink.LastErrorText());
            return false;
           }
         //--- follow the SINK, not the request. It may only have been
         //--- able to cut at a coarser boundary, and the cursor must
         //--- agree with what actually survives out there.
         m_cursor.RewindTo(actual);

         //--- anything holding state must drop what happened after this
         //--- instant, or a rewind leaves trades in a deleted future
         PublishRewind(actual);
        }

      m_clock.SeekTo(clamped);
      m_guard.SetHorizon(clamped);
      m_sink.OnSeek(clamped);

      //--- Both directions may owe the sink data now. Forward obviously
      //--- skipped over some; backward may have cut further than asked,
      //--- leaving a hole between the cut and the clock. Emitting here
      //--- keeps a seek atomic instead of leaving a visible gap until
      //--- the next pump happens to fill it.
      long lo, hi;
      if(m_cursor.PendingRange(clamped, lo, hi))
         if(EmitWindow(lo, hi) < 0)
           {
            Transition(SSR_STATE_ERROR);
            Publish();
            return false;
           }

      Publish();
      if(m_state.status == SSR_STATE_COMPLETED && clamped < m_timeline.end_msc)
         Transition(SSR_STATE_PAUSED);
      return true;
     }

   //--- back to the start, with the sink cleared
   bool              Reset(void)
     {
      ClearError();
      if(!Transition(SSR_STATE_RESETTING))
         return false;

      long cut = m_timeline.start_msc;
      if(m_sink != NULL)
        {
         long actual = m_sink.TruncateFrom(m_timeline.start_msc);
         if(actual >= 0)
            cut = actual;
         m_sink.OnReset();
        }

      m_clock.Rewind();
      m_cursor.Init();
      m_cursor.RewindTo(cut);
      PublishRewind(cut);
      m_guard.ResetCounters();
      m_guard.Arm(m_timeline.start_msc);
      //--- checkpoints describe a playback that no longer happened;
      //--- bookmarks are the user's and belong to the session, not to
      //--- the position within it
      m_snaps.ClearCheckpoints();

      //--- warmup is history, not replay: it survives a reset
      Publish();
      return Transition(m_clock.IsConfigured() ? SSR_STATE_READY : SSR_STATE_IDLE);
     }

   //--- tear down without destroying the object
   void              Release(void)
     {
      if(m_sink != NULL)
         m_sink.Release();
      if(m_source != NULL)
        {
         m_source.Close();
         m_source.DetachGuard();
        }
      m_guard.Disarm();
      m_state.Init();
      m_clock.Init();
      m_timeline.Init();
      m_cursor.Init();
     }

   //+------------------------------------------------------------------+
   //|                        NAVIGATION                                |
   //+------------------------------------------------------------------+

   //+------------------------------------------------------------------+
   //| Jump forward in bulk.                                            |
   //|                                                                  |
   //| Phase 7's arithmetic showed why this is the real fast-forward:    |
   //| even 50x replays a trading day in 29 minutes, so covering ground  |
   //| by injecting ticks is not covering ground. Bars are written       |
   //| straight into the sink instead - no live formation, no chart      |
   //| broadcast per tick.                                               |
   //|                                                                  |
   //| The bar CONTAINING the target is excluded from the bulk write and |
   //| emitted as ticks trimmed to the target, because writing it whole  |
   //| would put the rest of that minute - the future - into the chart.  |
   //+------------------------------------------------------------------+
   int               JumpForward(const long target_msc)
     {
      ClearError();
      if(m_source == NULL || m_sink == NULL)
        {
         SetError(SSR_ERR_NO_SOURCE, "not attached");
         return -1;
        }
      //--- clamping against an unconfigured timeline would land the
      //--- clock on nonsense rather than reporting the real problem
      if(!m_clock.IsConfigured() || !m_timeline.IsValid())
        {
         SetError(SSR_ERR_INVALID_STATE, "jump before load");
         return -1;
        }

      long target = SSRClampMsc(target_msc, m_timeline.start_msc, m_timeline.end_msc);
      if(target <= m_clock.now_msc)
         return 0;

      CSSRBarProvider *bp = m_source.Bars();
      if(bp == NULL)
        {
         SetError(SSR_ERR_NO_DATA, "source has no bar provider");
         return -1;
        }

      //--- the guard must move BEFORE anything is read
      m_guard.SetHorizon(target);

      long lo      = m_cursor.emitted_msc + 1;
      long bar_lo  = SSRBarOpenMsc(lo, PERIOD_M1);
      long last_bar = SSRBarOpenMsc(target, PERIOD_M1);

      int written = 0;

      //--- everything strictly before the target's own bar goes in bulk
      if(last_bar > bar_lo)
        {
         MqlRates bulk[];
         int n = bp.ReadBars(m_state.symbol, bar_lo, last_bar - 1, bulk);
         if(n < 0)
           {
            SetError(bp.LastError(), "bulk read failed: " + bp.LastErrorText());
            return -1;
           }
         n = m_guard.FilterRates(bulk, n);
         if(n > 0)
           {
            ulong t0 = GetMicrosecondCount();
            if(!m_sink.SeedBars(bulk, n))
              {
               SetError(SSR_ERR_SINK_FAILED, "bulk write failed: " + m_sink.LastErrorText());
               return -1;
              }
            m_metrics.RecordSeed(n, (double)(GetMicrosecondCount() - t0) / 1000.0);
            written += n;
            m_cursor.Advance(last_bar - 1, 0, n);
           }
        }

      //--- and the partial bar arrives as ticks, so it forms correctly
      m_clock.SeekTo(target);
      long tlo, thi;
      if(m_cursor.PendingRange(target, tlo, thi))
         if(EmitWindow(tlo, thi) < 0)
           {
            Transition(SSR_STATE_ERROR);
            Publish();
            return -1;
           }

      m_sink.OnSeek(target);
      Publish();

      if(m_clock.IsCompleted())
         Transition(SSR_STATE_COMPLETED);

      if(m_log != NULL && m_log.IsInfo())
         m_log.Info(StringFormat("jumped to %s (%d bars in bulk)",
                                 SSRFormatMsc(target), written));
      return written;
     }

   //+------------------------------------------------------------------+
   //| Move backwards by whole M1 bars.                                 |
   //|                                                                  |
   //| Restores the nearest checkpoint at or before the target and then |
   //| replays forward to it. Seeking alone would also move the chart,  |
   //| but it RECONSTRUCTS the engine's counters from nothing rather    |
   //| than restoring them - so a step back would zero the session's    |
   //| statistics, and once trades exist, would leave them stranded in  |
   //| a future that no longer happened.                                |
   //+------------------------------------------------------------------+
   bool              StepBackward(const int bars)
     {
      ClearError();
      if(bars <= 0)
         return true;
      if(!m_clock.IsConfigured())
        {
         SetError(SSR_ERR_INVALID_STATE, "step back before load");
         return false;
        }

      long here   = SSRBarOpenMsc(m_clock.now_msc, PERIOD_M1);
      long target = here - (long)bars * SSR_MSC_PER_MIN;
      if(target < m_timeline.start_msc)
         target = m_timeline.start_msc;
      if(target >= m_clock.now_msc)
         return true;

      SSRSnapshot cp;
      if(m_snaps.NearestAtOrBefore(target, cp))
        {
         if(!RestoreSnapshot(cp))
            return false;
         m_snaps.NoteRestore();
         //--- and forward from the checkpoint to exactly where asked
         if(target > m_clock.now_msc)
            if(JumpForward(target) < 0)
               return false;
        }
      else
        {
         //--- no checkpoint reaches back that far: fall back to a plain
         //--- seek. Correct on the chart, but the counters restart -
         //--- which is precisely what checkpoints exist to prevent, so
         //--- it is reported rather than passed off as equivalent.
         if(m_log != NULL && m_log.IsWarn())
            m_log.Warn("no checkpoint before " + SSRFormatMsc(target) +
                       "; counters will restart");
         if(!SeekTo(target))
            return false;
        }

      //--- checkpoints describing the discarded future must go with it
      m_snaps.DropFrom(m_clock.now_msc + 1);

      if(m_state.status == SSR_STATE_COMPLETED || m_state.status == SSR_STATE_READY)
         Transition(SSR_STATE_PAUSED);
      Publish();
      return true;
     }

   //--- unified entry point: the panel and the dialog both call this
   bool              JumpTo(const long target_msc)
     {
      ClearError();
      if(!m_clock.IsConfigured())
        {
         SetError(SSR_ERR_INVALID_STATE, "jump before load");
         return false;
        }
      long target = SSRClampMsc(target_msc, m_timeline.start_msc, m_timeline.end_msc);

      if(target < m_clock.now_msc)
        {
         long bars = (m_clock.now_msc - target) / SSR_MSC_PER_MIN + 1;
         return StepBackward((int)MathMin(bars, 2147483000));
        }
      if(target == m_clock.now_msc)
         return true;
      return (JumpForward(target) >= 0);
     }

   //--- back to the start and ready to run again
   bool              Restart(void)
     {
      //--- Reset already drops the checkpoints; the user's bookmarks
      //--- survive, because restarting is still the same session
      return Reset();
     }

   //--- bookmarks and saved positions ---------------------------------
   bool              Bookmark(const string label)
     {
      SSRSnapshot s;
      TakeSnapshot(s, label);
      return m_snaps.Mark(s, label);
     }

   bool              GotoBookmark(const int index)
     {
      SSRSnapshot s;
      if(!m_snaps.GetMark(index, s))
        {
         SetError(SSR_ERR_INVALID_ARG, "no such bookmark");
         return false;
        }
      return JumpTo(s.taken_at_msc);
     }

   string            BookmarkLabel(const int i) { return m_snaps.MarkLabel(i); }
   int               BookmarkCount(void)        { return m_snaps.Bookmarks(); }

   bool              SavePosition(const string key = "")
     {
      SSRSnapshot s;
      TakeSnapshot(s, "saved");
      string k = (key == "" ? m_state.symbol : key);
      if(!m_posfile.Save(k, s))
        {
         SetError(SSR_ERR_INTERNAL, m_posfile.LastError());
         return false;
        }
      return true;
     }

   //--- the position on disk describes WHERE, not what is loaded; the
   //--- caller loads the session first and then lands on it
   bool              PeekPosition(const string key, SSRSnapshot &out)
     { return m_posfile.Load(key, out); }

   bool              ResumePosition(const string key = "")
     {
      SSRSnapshot s;
      string k = (key == "" ? m_state.symbol : key);
      if(!m_posfile.Load(k, s))
        {
         SetError(SSR_ERR_NO_DATA, m_posfile.LastError());
         return false;
        }
      if(!m_clock.IsConfigured())
        {
         SetError(SSR_ERR_INVALID_STATE, "load the session before resuming into it");
         return false;
        }
      return JumpTo(s.taken_at_msc);
     }

   bool              HasSavedPosition(const string key = "")
     { return m_posfile.Exists(key == "" ? m_state.symbol : key); }

   CSSRSnapshotStore *Snapshots(void) { return GetPointer(m_snaps); }
   string            SnapshotText(void) { return m_snaps.ToString(); }

   //--- snapshots ---------------------------------------------------
   void              TakeSnapshot(SSRSnapshot &out, const string label = "")
     {
      out.Init();
      out.version      = SSR_VERSION;
      out.taken_at_msc = m_clock.now_msc;
      out.label        = label;
      out.state        = m_state;
      out.clock        = m_clock;
      out.cursor       = m_cursor;
      out.timeline     = m_timeline;
     }

   //+------------------------------------------------------------------+
   //| Restore a snapshot. The sink is truncated to the snapshot time   |
   //| first, so restoring is a real rollback and not a cosmetic one.   |
   //+------------------------------------------------------------------+
   bool              RestoreSnapshot(SSRSnapshot &snap)
     {
      ClearError();
      if(!snap.IsValid())
        {
         SetError(SSR_ERR_INVALID_ARG, "invalid snapshot");
         return false;
        }
      if(m_sink == NULL)
        {
         SetError(SSR_ERR_NO_SINK, "no sink");
         return false;
        }
      long actual = m_sink.TruncateFrom(snap.taken_at_msc);
      if(actual < 0)
        {
         SetError(SSR_ERR_SINK_FAILED, "truncate failed: " + m_sink.LastErrorText());
         return false;
        }

      m_state    = snap.state;
      m_clock    = snap.clock;
      m_cursor   = snap.cursor;
      m_timeline = snap.timeline;

      //--- if the sink cut further back than the snapshot, the restored
      //--- cursor would claim data that no longer exists out there
      if(actual < m_cursor.emitted_msc)
         m_cursor.RewindTo(actual);

      //--- and anything holding its own state must be told too. Without
      //--- this a rewind through a checkpoint - the normal path - left
      //--- the trading account holding positions opened in a future the
      //--- chart had just deleted.
      PublishRewind(actual);

      m_guard.Arm(m_clock.now_msc);
      m_sink.OnSeek(m_clock.now_msc);
      Publish();

      //--- a restored engine is never left running
      if(m_state.status == SSR_STATE_PLAYING)
         m_state.status = SSR_STATE_PAUSED;
      return true;
     }

   string            ToString(void)
     {
      return StringFormat("%s | %s | %s", m_state.ToString(),
                          m_cursor.ToString(), m_guard.ToString());
     }
  };

#endif // SSR_REPLAY_CONTROLLER_MQH
//+------------------------------------------------------------------+

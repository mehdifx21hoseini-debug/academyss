//+------------------------------------------------------------------+
//|                                         SSR_CustomSymbolSink.mqh |
//|                    SS Replay - Custom Symbol Replay Sink (MT5)   |
//|                                                                  |
//|  THE ADAPTER. Everything above believes it is talking to the      |
//|  abstract CSSRReplaySink from Phase 1; everything below is        |
//|  MetaTrader's Custom* API.                                        |
//|                                                                  |
//|  Two rules the whole product rests on are enforced here:          |
//|                                                                  |
//|  1. WARMUP GOES IN AS BARS, REPLAY GOES IN AS TICKS.              |
//|     Seeding a hundred thousand warmup bars through tick injection |
//|     would take minutes and broadcast a hundred thousand chart     |
//|     updates nobody watches. Conversely, advancing replay by       |
//|     writing bars would skip the live candle formation that is the |
//|     entire point. Different jobs, different API.                  |
//|                                                                  |
//|  2. TRUNCATION IS DELETION, NEVER HIDING.                         |
//|     Rewind removes the bars and ticks from MetaTrader's own       |
//|     storage. A hidden-but-present future is the failure mode this |
//|     product exists to avoid.                                      |
//+------------------------------------------------------------------+
#ifndef SSR_CUSTOM_SYMBOL_SINK_MQH
#define SSR_CUSTOM_SYMBOL_SINK_MQH

#include "../Common/SSR_Types.mqh"
#include "../Common/SSR_Time.mqh"
#include "../Common/SSR_Platform.mqh"
#include "../Core/SSR_IReplaySink.mqh"
#include "SSR_CustomSymbolManager.mqh"
#include "SSR_SeedCache.mqh"

//+------------------------------------------------------------------+
class CSSRCustomSymbolSink : public CSSRReplaySink
  {
private:
   CSSRCustomSymbolManager m_mgr;
   CSSRSeedCache           m_cache;
   int                     m_slot;
   bool                    m_anonymous;

   //--- the exact symbol to adopt, when the caller already knows it.
   //--- Empty means "work it out from the origin and the slot".
   string                  m_adopt_name;
   long                    m_warmup_from_msc;   // range the cache is asked about
   long                    m_warmup_to_msc;
   bool                    m_reused_seed;
   bool                    m_prepared;
   bool                    m_adopt_existing;
   bool                    m_own_symbol;   // did we create it, or adopt one?

   //--- instrumentation for Phase 7
   long                    m_emit_calls;
   long                    m_emit_ticks;
   long                    m_seed_bars;
   long                    m_truncates;
   long                    m_emit_time_ms;
   long                    m_last_emit_msc;

public:
                     CSSRCustomSymbolSink(void)
     : m_slot(1), m_anonymous(false), m_adopt_name(""),
       m_warmup_from_msc(SSR_INVALID_TIME),
       m_warmup_to_msc(SSR_INVALID_TIME), m_reused_seed(false),
       m_prepared(false), m_adopt_existing(false), m_own_symbol(true),
       m_emit_calls(0), m_emit_ticks(0), m_seed_bars(0), m_truncates(0),
       m_emit_time_ms(0), m_last_emit_msc(SSR_INVALID_TIME) {}

                    ~CSSRCustomSymbolSink(void)
     {
      //--- a session that ends without an explicit Release must not
      //--- leave an orphan symbol behind in the Market Watch tree
      if(m_own_symbol && m_mgr.IsCreated())
         m_mgr.Destroy();
     }

   virtual string    Name(void) override { return "mt5-custom-symbol"; }

   void              SetSlot(const int slot) { m_slot = slot; }
   //--- Blind Mode. Set before the session opens; the symbol name
   //--- is decided once, when the symbol is created.
   void              SetAnonymous(const bool on)
     { m_anonymous = on; m_mgr.SetAnonymous(on); }
   int               Slot(void)              { return m_slot; }

   //--- the controller tells the sink which warmup it is about to seed,
   //--- so the cache can be consulted before the symbol is touched
   void              SetWarmupRange(const long from_msc, const long to_msc)
     { m_warmup_from_msc = from_msc; m_warmup_to_msc = to_msc; }

   void              SetCacheEnabled(const bool on) { m_cache.SetEnabled(on); }

   //+------------------------------------------------------------------+
   //| ADOPT THE REPLAY SYMBOL INSTEAD OF REBUILDING IT.                |
   //|                                                                  |
   //| Creating a replay symbol deletes any symbol of that name first,  |
   //| and MetaTrader refuses to delete a symbol a CHART IS OPEN ON.    |
   //| That matters now that the host puts its own chart on the replay  |
   //| symbol so the panel, the keyboard and the mouse all live in one  |
   //| window: on the second pass the chart is already there, so Create |
   //| would fail and take the session with it.                         |
   //|                                                                  |
   //| Adopting keeps the symbol and clears its history, which reaches  |
   //| the same state - an empty symbol ready to be seeded - without    |
   //| the deletion MetaTrader will not allow. Deleting RATES is fine;  |
   //| only deleting the SYMBOL is blocked.                             |
   //|                                                                  |
   //| Explicit rather than inferred from the seed cache: the cache is  |
   //| a heuristic about whether reuse is WORTH it, and this is a fact  |
   //| about whether recreation is POSSIBLE. Two different questions.   |
   //+------------------------------------------------------------------+
   void              SetAdoptExisting(const bool on) { m_adopt_existing = on; }

   //+------------------------------------------------------------------+
   //| ADOPT THIS EXACT SYMBOL, because the caller can see it.          |
   //|                                                                  |
   //| The second pass of the one-window handover runs ON the replay     |
   //| chart, so _Symbol already IS the replay symbol - and recomputing  |
   //| the name instead means two passes have to agree about every input |
   //| that feeds the calculation. They disagreed once, over blind mode, |
   //| and the session died with SINK_FAILED on a symbol that had never  |
   //| existed. A name that is READ cannot disagree with one that is     |
   //| read; only two that are computed can.                             |
   //+------------------------------------------------------------------+
   void              SetAdoptName(const string name) { m_adopt_name = name; }
   bool              ReusedSeed(void)               { return m_reused_seed; }
   string            CacheReason(void)              { return m_cache.LastReason(); }
   CSSRSeedCache    *Cache(void)                    { return GetPointer(m_cache); }

   //--- the replay symbol, which is NOT the symbol the engine was given
   string            ReplaySymbol(void) { return m_mgr.Symbol(); }
   CSSRCustomSymbolManager *Manager(void) { return GetPointer(m_mgr); }

   //+------------------------------------------------------------------+
   //| The controller hands us the ORIGIN symbol. We create a distinct  |
   //| replay symbol cloned from it, so the real instrument is never    |
   //| written to and the user's live chart is never touched.           |
   //+------------------------------------------------------------------+
   virtual bool      Prepare(const string symbol, const int digits, const double point) override
     {
      m_prepared = false;

      //--- Ask the cache BEFORE creating, because creating destroys the
      //--- symbol and with it the very bars we might have reused.
      m_reused_seed = false;
      string replay_name = SSRReplaySymbolNameFor(symbol, m_slot, m_anonymous);

      //--- and when the caller handed us the real one, say so loudly if
      //--- it is not what we would have computed. That difference is a
      //--- bug somewhere upstream, and it used to surface as a dead
      //--- session rather than as a sentence.
      if(m_adopt_existing && m_adopt_name != "" && SSRIsReplaySymbol(m_adopt_name))
        {
         if(m_adopt_name != replay_name)
            PrintFormat("[sink] the chart is showing %s but this pass would "
                        "have computed %s - adopting what is actually there. "
                        "Something upstream disagrees about blind mode or the "
                        "slot.", m_adopt_name, replay_name);
         replay_name = m_adopt_name;
        }
      if(m_warmup_from_msc > 0 && m_warmup_to_msc > m_warmup_from_msc)
         m_reused_seed = m_cache.CanReuse(symbol, replay_name,
                                          m_warmup_from_msc, m_warmup_to_msc);

      if(m_reused_seed)
        {
         //--- adopt the existing symbol instead of rebuilding it
         if(!m_mgr.Adopt(replay_name, symbol))
           {
            m_reused_seed = false;
            m_cache.Invalidate(replay_name);
           }
        }

      if(!m_reused_seed && m_adopt_existing)
        {
         //--- a chart of ours is sitting on it; take it over as it is
         if(!m_mgr.Adopt(replay_name, symbol))
           {
            Fail(SSR_ERR_INTERNAL,
                 "could not adopt the existing replay symbol " + replay_name +
                 " - it is what this chart is showing, so it cannot be "
                 "recreated either");
            return false;
           }
         m_mgr.ClearAll();
        }
      else
      if(!m_reused_seed)
        {
         if(!m_mgr.Create(symbol, m_slot))
           {
            Fail(m_mgr.LastError(), m_mgr.LastErrorText());
            return false;
           }
         //--- start from an empty history: a previous session's data
         //--- would otherwise appear as the future of this one
         m_mgr.ClearAll();
        }
      else
        {
         //--- reuse is only safe once everything at or after the replay
         //--- start is gone. A cached warmup that still carries the last
         //--- session's replay would BE the future of this one.
         if(m_warmup_to_msc > 0)
            m_mgr.Truncate(m_warmup_to_msc + 1);
        }

      m_emit_calls    = 0;
      m_emit_ticks    = 0;
      m_seed_bars     = 0;
      m_truncates     = 0;
      m_emit_time_ms  = 0;
      m_last_emit_msc = SSR_INVALID_TIME;
      m_prepared      = true;
      return true;
     }

   //+------------------------------------------------------------------+
   //| Warmup history, in bulk. Bars, not ticks - see the header note.  |
   //+------------------------------------------------------------------+
   virtual bool      SeedBars(const MqlRates &bars[], const int count) override
     {
      if(!m_prepared)
        {
         Fail(SSR_ERR_INVALID_STATE, "sink not prepared");
         return false;
        }
      if(count <= 0)
         return true;

      //+------------------------------------------------------------------+
      //| THE CACHE SKIPS THE WARMUP. IT MUST NOT SKIP EVERYTHING ELSE.    |
      //|                                                                  |
      //| m_reused_seed says "the warmup bars are already in this symbol,  |
      //| do not write them again". It used to make this method return     |
      //| true for EVERY bulk write for the rest of the session - and      |
      //| SeedBars is also how a JUMP writes its bars.                     |
      //|                                                                  |
      //| So a jump reported "5918 bars in bulk" and put ONE bar in the    |
      //| symbol. It reported success. Nothing failed. The user's chart    |
      //| held a thousand warmup candles, then a gap of six days, then a   |
      //| single candle - and every layer above said the jump had worked.  |
      //| Measured from two of their logs: the engine said 5918, the       |
      //| symbol said 1001, and 1000 of those were the warmup.             |
      //|                                                                  |
      //| The cache can only speak for what it cached: bars at or before   |
      //| the warmup end. One bar past that and this is a real write.      |
      //+------------------------------------------------------------------+
      bool is_warmup = (m_warmup_to_msc > 0 &&
                        SSRToMsc(bars[count - 1].time) <= m_warmup_to_msc);

      if(m_reused_seed && is_warmup)
        {
         m_seed_bars += count;
         return true;
        }

      if(!m_mgr.WriteBars(bars, count))
        {
         Fail(m_mgr.LastError(), m_mgr.LastErrorText());
         return false;
        }
      m_seed_bars += count;

      //--- record what is now in the symbol, so the next session can
      //--- skip it. Written after the bars, never before - and only for
      //--- the warmup itself. A jump's bars are replay, not cache: they
      //--- are truncated away the next time this symbol is adopted, and
      //--- counting them here would describe a cache that does not exist.
      if(is_warmup && m_warmup_from_msc > 0 && m_warmup_to_msc > m_warmup_from_msc)
        {
         SSRSeedManifest man;
         man.Init();
         man.origin          = m_mgr.Origin();
         man.replay_symbol   = m_mgr.Symbol();
         man.warmup_from_msc = m_warmup_from_msc;
         man.warmup_to_msc   = m_warmup_to_msc;
         man.bar_count       = m_seed_bars;
         m_cache.Save(man);
        }
      return true;
     }

   //+------------------------------------------------------------------+
   //| The replay stream. This is what makes the candle form live.      |
   //+------------------------------------------------------------------+
   virtual bool      EmitTicks(const MqlTick &ticks[], const int count) override
     {
      if(!m_prepared)
        {
         Fail(SSR_ERR_INVALID_STATE, "sink not prepared");
         return false;
        }
      if(count <= 0)
         return true;

      //--- MetaTrader will accept a tick stamped before one it already
      //--- holds and quietly corrupt the bar being built. The engine is
      //--- supposed to guarantee monotonicity; refusing here rather than
      //--- trusting it keeps a future regression from becoming a wrong
      //--- candle that nobody notices until Phase 16.
      if(m_last_emit_msc != SSR_INVALID_TIME && ticks[0].time_msc < m_last_emit_msc)
        {
         Fail(SSR_ERR_INTERNAL,
              StringFormat("out-of-order emit: %s before %s",
                           SSRFormatMscMs(ticks[0].time_msc),
                           SSRFormatMscMs(m_last_emit_msc)));
         return false;
        }

      ulong t0 = SSRMicros();
      if(!m_mgr.AddTicks(ticks, count))
        {
         Fail(m_mgr.LastError(), m_mgr.LastErrorText());
         return false;
        }
      m_emit_time_ms  += (long)SSRElapsedMs(t0);
      m_emit_calls++;
      m_emit_ticks    += count;
      m_last_emit_msc  = ticks[count - 1].time_msc;
      return true;
     }

   //+------------------------------------------------------------------+
   //| Delete, do not hide. Returns where the cut actually landed.      |
   //+------------------------------------------------------------------+
   virtual long      TruncateFrom(const long from_msc) override
     {
      if(!m_prepared)
        {
         Fail(SSR_ERR_INVALID_STATE, "sink not prepared");
         return -1;
        }

      long actual = m_mgr.Truncate(from_msc);
      if(actual < 0)
        {
         Fail(m_mgr.LastError(), m_mgr.LastErrorText());
         return -1;
        }
      m_truncates++;

      //--- a cut that reaches into the warmup makes the manifest a lie
      if(m_warmup_to_msc > 0 && actual <= m_warmup_to_msc)
         m_cache.Invalidate(m_mgr.Symbol());

      //--- the emit watermark must fall back with the data, or the very
      //--- next emit would be rejected as out of order
      m_last_emit_msc = (actual > 0 ? actual - 1 : SSR_INVALID_TIME);
      return actual;
     }

   virtual void      OnWarmupPlanned(const long from_msc, const long to_msc) override
     { SetWarmupRange(from_msc, to_msc); }

   //--- the whole payoff of the cache: when the bars are already in the
   //--- custom symbol, the data layer is never asked for them
   virtual bool      NeedsWarmup(const long from_msc, const long to_msc) override
     { return !m_reused_seed; }


   virtual void      OnReset(void) override
     {
      m_last_emit_msc = SSR_INVALID_TIME;
     }

   //+------------------------------------------------------------------+
   //| Release the symbol. Called on teardown; safe to call twice.      |
   //+------------------------------------------------------------------+
   virtual void      Release(void) override
     {
      if(m_own_symbol && m_mgr.IsCreated())
        {
         //--- destroying the symbol destroys the bars the manifest
         //--- describes; leaving it would promise a cache that is gone
         m_cache.Invalidate(m_mgr.Symbol());
         m_mgr.Destroy();
        }
      m_prepared      = false;
      m_last_emit_msc = SSR_INVALID_TIME;
     }

   //+------------------------------------------------------------------+
   //| Keep the replay symbol alive after Release.                      |
   //|                                                                  |
   //| Phase 12 (Save / Resume Session) needs the symbol and its        |
   //| history to survive an engine teardown so a session can be        |
   //| reopened without reseeding from scratch.                         |
   //+------------------------------------------------------------------+
   void              SetOwnsSymbol(const bool own) { m_own_symbol = own; }
   bool              OwnsSymbol(void)              { return m_own_symbol; }

   //--- diagnostics --------------------------------------------------
   long              EmitCalls(void)   { return m_emit_calls; }
   long              EmitTicks(void)   { return m_emit_ticks; }
   long              SeededBars(void)  { return m_seed_bars; }
   long              Truncations(void) { return m_truncates; }
   long              EmitTimeMs(void)  { return m_emit_time_ms; }
   long              LastEmitMsc(void) { return m_last_emit_msc; }
   bool              IsPrepared(void)  { return m_prepared; }

   double            TicksPerSecond(void)
     {
      return (m_emit_time_ms > 0 ? (double)m_emit_ticks / ((double)m_emit_time_ms / 1000.0) : 0.0);
     }

   //--- what MetaTrader itself believes the time is on the replay
   //--- symbol. Phase 0 spike C4 asserts this equals the last tick.
   long              SymbolClockMsc(void) { return m_mgr.SymbolTimeMsc(); }

   string            ToString(void)
     {
      return StringFormat("sink[%s emits=%d ticks=%d seeded=%d cuts=%d %.0f t/s]",
                          m_mgr.Symbol(), (int)m_emit_calls, (int)m_emit_ticks,
                          (int)m_seed_bars, (int)m_truncates, TicksPerSecond());
     }
  };

#endif // SSR_CUSTOM_SYMBOL_SINK_MQH
//+------------------------------------------------------------------+

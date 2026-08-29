//+------------------------------------------------------------------+
//|                                             SSR_T1_CoreEngine.mq5 |
//|                          SS Replay - Phase 1 Core Engine Tests   |
//|                                                                  |
//|  Runs entirely against the in-memory data source and recording   |
//|  sink, so it needs no broker, no downloaded history and no       |
//|  custom symbol. Attach to any chart and run.                     |
//|                                                                  |
//|  This is the Definition of Done for Phase 1 in executable form.  |
//+------------------------------------------------------------------+
#property script_show_inputs

#include <SSReplay/Common/SSR_Types.mqh>
#include <SSReplay/Common/SSR_Time.mqh>
#include <SSReplay/Common/SSR_Log.mqh>
#include <SSReplay/Core/SSR_ReplayController.mqh>
#include <SSReplay/Core/Sources/SSR_MemoryDataSource.mqh>
#include <SSReplay/Core/Sinks/SSR_RecordingSink.mqh>

input datetime InpStart   = D'2024.01.08 00:00';   // Dataset start
input int      InpBars    = 1440;                  // M1 bars (1 day)
input double   InpBase    = 38000.0;               // Base price
input int      InpWarmup  = 120;                   // Warmup bars

int g_pass = 0;
int g_fail = 0;

//+------------------------------------------------------------------+
void Check(const string name, const bool ok, const string detail = "")
  {
   if(ok) { g_pass++; PrintFormat("  PASS  %s", name); }
   else   { g_fail++; PrintFormat("  FAIL  %s  %s", name, detail); }
  }

void CheckEq(const string name, const long expected, const long actual)
  {
   Check(name, expected == actual,
         StringFormat("expected=%I64d actual=%I64d", expected, actual));
  }

void Section(const string title)
  {
   PrintFormat("--- %s", title);
  }

//+------------------------------------------------------------------+
//| Deterministic dataset, generated in-process.                     |
//+------------------------------------------------------------------+
void BuildBars(MqlRates &out[], const datetime start, const int count,
               const double base, const int digits, const double point)
  {
   ArrayResize(out, count);
   ulong s = 20260829;
   double price = base;
   for(int i = 0; i < count; i++)
     {
      s ^= (s << 13); s ^= (s >> 7); s ^= (s << 17);
      double u1 = (double)(s % 1000000007) / 1000000007.0;
      s ^= (s << 13); s ^= (s >> 7); s ^= (s << 17);
      double u2 = (double)(s % 1000000007) / 1000000007.0;
      if(u1 < 1e-12) u1 = 1e-12;
      double z = MathSqrt(-2.0 * MathLog(u1)) * MathCos(2.0 * M_PI * u2);

      double o = price;
      double c = o + z * 20.0 * point;
      double h = MathMax(o, c) + MathAbs(z) * 8.0 * point;
      double l = MathMin(o, c) - MathAbs(z) * 8.0 * point;

      out[i].time        = start + i * 60;
      out[i].open        = NormalizeDouble(o, digits);
      out[i].high        = NormalizeDouble(h, digits);
      out[i].low         = NormalizeDouble(l, digits);
      out[i].close       = NormalizeDouble(c, digits);
      out[i].tick_volume = 10 + (long)(i % 90);
      out[i].spread      = 2;
      out[i].real_volume = 0;
      if(out[i].high < MathMax(out[i].open, out[i].close))
         out[i].high = MathMax(out[i].open, out[i].close);
      if(out[i].low > MathMin(out[i].open, out[i].close))
         out[i].low = MathMin(out[i].open, out[i].close);
      price = out[i].close;
     }
  }

//+------------------------------------------------------------------+
//| Wire a fresh engine over a fresh dataset.                        |
//+------------------------------------------------------------------+
bool Wire(CSSRReplayController &ctrl, CSSRMemoryDataSource &src,
          CSSRRecordingSink &sink, const int digits, const double point)
  {
   MqlRates bars[];
   BuildBars(bars, InpStart, InpBars, InpBase, digits, point);
   if(!src.LoadBars(bars, ArraySize(bars)))
      return false;

   sink.Clear();
   ctrl.SetSymbolSpec(digits, point);
   ctrl.SetSpreadPoints(20);
   ctrl.SetTicksPerBar(8);
   ctrl.SetWarmupBars(InpWarmup);
   ctrl.SetDataMode(SSR_DATA_MEMORY);
   ctrl.SetFidelity(SSR_FIDELITY_SYNTHETIC_TICK);
   ctrl.Attach(GetPointer(src), GetPointer(sink));
   return true;
  }

//+------------------------------------------------------------------+
void OnStart()
  {
   int    digits = 2;
   double point  = 0.01;

   //--- replay window: skip the warmup, replay the following 4 hours
   long ds_first = SSRToMsc(InpStart);
   long start    = ds_first + (long)InpWarmup * SSR_MSC_PER_MIN;
   long endt     = start + 240 * SSR_MSC_PER_MIN;

   g_ssr_log.SetLevel(SSR_LOG_WARN);
   Print("=== SSR Phase 1 - Core Engine Tests ===");

   //================================================================
   Section("T1.1  clock determinism (integer speed arithmetic)");
   {
      SSRReplayClock a, b;
      a.Init(); b.Init();
      a.Configure(start, endt);
      b.Configure(start, endt);
      a.SetSpeedX100(SSR_SPEED_025);
      b.SetSpeedX100(SSR_SPEED_025);

      //--- 0.25x with a 7ms delta is the case naive float maths loses
      for(int i = 0; i < 5000; i++) { a.Advance(7); b.Advance(7); }
      CheckEq("two clocks agree exactly", a.now_msc, b.now_msc);

      //--- 4000 x 7ms at 0.25x must equal exactly 7000ms of replay time
      SSRReplayClock c; c.Init(); c.Configure(start, endt);
      c.SetSpeedX100(SSR_SPEED_025);
      for(int i = 0; i < 4000; i++) c.Advance(7);
      CheckEq("no drift over 4000 advances", start + 7000, c.now_msc);

      //--- 1x must be exactly one-to-one
      SSRReplayClock d; d.Init(); d.Configure(start, endt);
      d.SetSpeedX100(SSR_SPEED_1);
      for(int i = 0; i < 1000; i++) d.Advance(13);
      CheckEq("1x is one-to-one", start + 13000, d.now_msc);

      //--- the clock must never run past the end of the timeline
      SSRReplayClock e; e.Init(); e.Configure(start, start + 1000);
      e.SetSpeedX100(SSR_SPEED_50);
      for(int i = 0; i < 100; i++) e.Advance(100);
      CheckEq("clamped at end", start + 1000, e.now_msc);
      Check("reports completed", e.IsCompleted());
   }

   //================================================================
   Section("T1.2  state machine legality");
   {
      Check("IDLE -> LOADING",           SSRCanTransition(SSR_STATE_IDLE, SSR_STATE_LOADING));
      Check("IDLE -> PLAYING refused",  !SSRCanTransition(SSR_STATE_IDLE, SSR_STATE_PLAYING));
      Check("READY -> PLAYING",          SSRCanTransition(SSR_STATE_READY, SSR_STATE_PLAYING));
      Check("PLAYING -> PAUSED",         SSRCanTransition(SSR_STATE_PLAYING, SSR_STATE_PAUSED));
      Check("PAUSED -> PLAYING",         SSRCanTransition(SSR_STATE_PAUSED, SSR_STATE_PLAYING));
      Check("COMPLETED -> PLAYING refused",
            !SSRCanTransition(SSR_STATE_COMPLETED, SSR_STATE_PLAYING));
      Check("ERROR -> READY refused",   !SSRCanTransition(SSR_STATE_ERROR, SSR_STATE_READY));
      Check("ERROR -> RESETTING",        SSRCanTransition(SSR_STATE_ERROR, SSR_STATE_RESETTING));
      Check("anything -> ERROR",         SSRCanTransition(SSR_STATE_PLAYING, SSR_STATE_ERROR));
   }

   //================================================================
   Section("T1.3  load, warmup and initial position");
   {
      CSSRMemoryDataSource src;
      CSSRRecordingSink    sink;
      CSSRReplayController ctrl;
      if(!Wire(ctrl, src, sink, digits, point))
        { Check("dataset wired", false); }
      else
        {
         bool ok = ctrl.Load("TEST", start, endt);
         Check("load succeeded", ok, ctrl.LastErrorText());
         Check("state is READY", ctrl.Status() == SSR_STATE_READY, SSRStateName(ctrl.Status()));
         Check("sink prepared", sink.IsPrepared());
         CheckEq("warmup bars seeded", InpWarmup, sink.SeedBarCount());
         CheckEq("clock at start", start, ctrl.Now());
         CheckEq("no ticks before play", 0, sink.TickCount());
         Check("timeline valid", ctrl.TimelineValid(), ctrl.TimelineText());
        }
   }

   //================================================================
   Section("T1.4  playback emits an ordered, non-duplicated stream");
   {
      CSSRMemoryDataSource src;
      CSSRRecordingSink    sink;
      CSSRReplayController ctrl;
      Wire(ctrl, src, sink, digits, point);
      ctrl.Load("TEST", start, endt);
      ctrl.SetSpeedX100(SSR_SPEED_1);
      ctrl.Play();

      //--- 60 pumps of 1000ms == 60s of replay == 1 M1 bar
      for(int i = 0; i < 60; i++)
         ctrl.Pump(1000);

      Check("ticks were emitted", sink.TickCount() > 0,
            IntegerToString(sink.TickCount()));
      CheckEq("stream is ordered", 0, sink.OrderViolations());

      //--- the exact-count assertion is the one that proves no tick was
      //--- emitted twice and none was skipped. 8 ticks per bar spread
      //--- over the minute, plus the first tick of the next bar, which
      //--- lands exactly on the 60s boundary the pumps stop at.
      CheckEq("exact tick count over one bar", 9, sink.TickCount());
      CheckEq("no duplicate stamps in a synthetic stream", 0, sink.DuplicateStamps());
      CheckEq("clock advanced 60s", start + 60000, ctrl.Now());
      CheckEq("no guard violations", 0, ctrl.Violations());

      //--- nothing may carry a stamp beyond the clock
      CheckEq("no tick beyond replay time", 0, sink.CountAfter(ctrl.Now()));
   }

   //================================================================
   Section("T1.5  determinism of the whole engine");
   {
      ulong fp[2];
      for(int run = 0; run < 2; run++)
        {
         CSSRMemoryDataSource src;
         CSSRRecordingSink    sink;
         CSSRReplayController ctrl;
         Wire(ctrl, src, sink, digits, point);
         ctrl.Load("TEST", start, endt);
         ctrl.SetSpeedX100(SSR_SPEED_2);
         ctrl.Play();
         for(int i = 0; i < 300; i++)
            ctrl.Pump(97);              // deliberately awkward delta
         fp[run] = sink.Fingerprint();
        }
      Check("identical stream across runs", fp[0] == fp[1],
            StringFormat("%I64u vs %I64u", fp[0], fp[1]));
   }

   //================================================================
   Section("T1.6  future data guard");
   {
      CSSRMemoryDataSource src;
      CSSRRecordingSink    sink;
      CSSRReplayController ctrl;
      Wire(ctrl, src, sink, digits, point);
      ctrl.Load("TEST", start, endt);
      ctrl.Play();
      for(int i = 0; i < 30; i++)
         ctrl.Pump(1000);

      long now = ctrl.Now();
      CheckEq("no emitted tick is in the future", 0, sink.CountAfter(now));

      //--- ask the data layer directly for the future; it must refuse
      CSSRBarProvider *bp = src.Bars();
      MqlRates future[];
      int n = bp.ReadBars("TEST", now + SSR_MSC_PER_MIN, now + 100 * SSR_MSC_PER_MIN, future);
      CheckEq("provider refuses future bars", 0, n);
      Check("guard counted the violation", ctrl.Violations() > 0,
            IntegerToString((int)ctrl.Violations()));

      //--- and the past must still be readable, so the guard is not
      //--- simply refusing everything
      MqlRates past[];
      int m = bp.ReadBars("TEST", start, now, past);
      Check("past is still readable", m > 0, IntegerToString(m));
   }

   //================================================================
   Section("T1.7  step, seek and rewind");
   {
      CSSRMemoryDataSource src;
      CSSRRecordingSink    sink;
      CSSRReplayController ctrl;
      Wire(ctrl, src, sink, digits, point);
      ctrl.Load("TEST", start, endt);

      int e1 = ctrl.StepBars(1);
      Check("step forward emitted ticks", e1 > 0, IntegerToString(e1));
      Check("state became PAUSED", ctrl.Status() == SSR_STATE_PAUSED,
            SSRStateName(ctrl.Status()));

      for(int i = 0; i < 9; i++)
         ctrl.StepBars(1);
      long after10 = ctrl.Now();
      int  ticks10 = sink.TickCount();
      Check("10 steps advanced the clock", after10 > start);

      //--- forward seek
      long target = after10 + 30 * SSR_MSC_PER_MIN;
      Check("forward seek", ctrl.SeekTo(target));
      CheckEq("clock at seek target", target, ctrl.Now());
      Check("forward seek emitted the skipped data", sink.TickCount() > ticks10);

      //--- backward seek must truncate, not hide
      Check("backward seek", ctrl.SeekTo(after10));
      CheckEq("clock back at the earlier time", after10, ctrl.Now());
      Check("sink was truncated", sink.Truncations() > 0);
      CheckEq("no tick survives past the rewind point", 0, sink.CountAfter(after10));
   }

   //================================================================
   Section("T1.8  snapshot and restore");
   {
      CSSRMemoryDataSource src;
      CSSRRecordingSink    sink;
      CSSRReplayController ctrl;
      Wire(ctrl, src, sink, digits, point);
      ctrl.Load("TEST", start, endt);
      ctrl.Play();
      for(int i = 0; i < 20; i++)
         ctrl.Pump(1000);

      SSRSnapshot snap;
      ctrl.TakeSnapshot(snap, "mark");
      long snap_time  = ctrl.Now();
      int  snap_ticks = sink.TickCount();
      Check("snapshot is valid", snap.IsValid(), snap.ToString());

      for(int i = 0; i < 40; i++)
         ctrl.Pump(1000);
      Check("engine moved on after the snapshot", ctrl.Now() > snap_time);

      Check("restore succeeded", ctrl.RestoreSnapshot(snap), ctrl.LastErrorText());
      CheckEq("clock restored exactly", snap_time, ctrl.Now());
      Check("restored engine is not playing", ctrl.Status() != SSR_STATE_PLAYING,
            SSRStateName(ctrl.Status()));
      CheckEq("stream rolled back too", 0, sink.CountAfter(snap_time));
      Check("tick count shrank to the snapshot", sink.TickCount() <= snap_ticks,
            StringFormat("%d <= %d", sink.TickCount(), snap_ticks));
   }

   //================================================================
   Section("T1.9  reset");
   {
      CSSRMemoryDataSource src;
      CSSRRecordingSink    sink;
      CSSRReplayController ctrl;
      Wire(ctrl, src, sink, digits, point);
      ctrl.Load("TEST", start, endt);
      ctrl.Play();
      for(int i = 0; i < 30; i++)
         ctrl.Pump(1000);

      int seeded = sink.SeedBarCount();
      Check("reset succeeded", ctrl.Reset());
      CheckEq("clock back at start", start, ctrl.Now());
      Check("state is READY", ctrl.Status() == SSR_STATE_READY, SSRStateName(ctrl.Status()));
      CheckEq("replay stream cleared", 0, sink.CountAfter(start));
      CheckEq("warmup survived the reset", seeded, sink.SeedBarCount());
      CheckEq("cursor counters cleared", 0, ctrl.TicksEmitted());
   }

   //================================================================
   Section("T1.10  fidelity routing");
   {
      long counts[3];
      ENUM_SSR_FIDELITY modes[3] = {SSR_FIDELITY_FULL_TICK,
                                    SSR_FIDELITY_SYNTHETIC_TICK,
                                    SSR_FIDELITY_BAR};
      for(int f = 0; f < 3; f++)
        {
         CSSRMemoryDataSource src;
         CSSRRecordingSink    sink;
         CSSRReplayController ctrl;
         Wire(ctrl, src, sink, digits, point);
         ctrl.SetFidelity(modes[f]);
         ctrl.Load("TEST", start, endt);
         ctrl.Play();
         //--- LONG ENOUGH FOR A BAR TO CLOSE. BAR fidelity emits once
         //--- per bar close and a bar is sixty seconds, so ten pumps of
         //--- one second could never produce a single tick. The
         //--- assertion below was right; the setup never gave it a
         //--- chance to be true.
         for(int i = 0; i < 180; i++)
            ctrl.Pump(1000);
         counts[f] = sink.TickCount();
        }

      //--- the memory source carries no ticks, so FULL_TICK must
      //--- degrade to SYNTHETIC rather than emit nothing
      CheckEq("FULL_TICK degraded to SYNTHETIC", counts[1], counts[0]);
      Check("SYNTHETIC emits more than BAR", counts[1] > counts[2],
            StringFormat("synthetic=%I64d bar=%I64d", counts[1], counts[2]));
      Check("BAR still emits something", counts[2] > 0);
   }

   //================================================================
   Section("T1.11  error handling");
   {
      CSSRReplayController bare;
      Check("load without a source fails", !bare.Load("TEST", start, endt));
      Check("error state entered", bare.Status() == SSR_STATE_ERROR,
            SSRStateName(bare.Status()));
      Check("error code recorded", bare.LastError() != SSR_OK,
            SSRErrName(bare.LastError()));

      CSSRMemoryDataSource src;
      CSSRRecordingSink    sink;
      CSSRReplayController ctrl;
      Wire(ctrl, src, sink, digits, point);
      Check("out-of-range window rejected",
            !ctrl.Load("TEST", SSRToMsc(D'2010.01.01 00:00'), SSRToMsc(D'2010.01.02 00:00')));

      CSSRMemoryDataSource src2;
      CSSRRecordingSink    sink2;
      CSSRReplayController ctrl2;
      Wire(ctrl2, src2, sink2, digits, point);
      Check("pump before load emits nothing", ctrl2.Pump(1000) == 0);
   }

   //================================================================
   PrintFormat("=== Phase 1: PASS=%d  FAIL=%d  ===> %s",
               g_pass, g_fail, (g_fail == 0 ? "GREEN" : "RED"));
  }
//+------------------------------------------------------------------+

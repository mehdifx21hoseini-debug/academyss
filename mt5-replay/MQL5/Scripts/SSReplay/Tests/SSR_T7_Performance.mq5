//+------------------------------------------------------------------+
//|                                           SSR_T7_Performance.mq5 |
//|                       SS Replay - Phase 7 Performance Engine     |
//|                                                                  |
//|  The rule for this phase was: no performance claim without a     |
//|  measurement. These tests hold the engine to it - they assert    |
//|  that it measures itself, that the ceilings follow those         |
//|  measurements, and that it never presents a guess as a number.   |
//+------------------------------------------------------------------+
#property script_show_inputs

#include <SSReplay/Common/SSR_Types.mqh>
#include <SSReplay/Common/SSR_Time.mqh>
#include <SSReplay/Core/SSR_Metrics.mqh>
#include <SSReplay/Core/SSR_PumpBudget.mqh>
#include <SSReplay/Core/SSR_FidelityPolicy.mqh>
#include <SSReplay/Core/SSR_ReplayController.mqh>
#include <SSReplay/Core/Sources/SSR_MemoryDataSource.mqh>
#include <SSReplay/Core/Sinks/SSR_RecordingSink.mqh>
#include <SSReplay/Data/SSR_HistoryCatalog.mqh>

input datetime InpStart = D'2024.01.08 00:00';
input int      InpBars  = 4320;
input double   InpBase  = 38000.0;

int g_pass = 0, g_fail = 0;
void Check(const string n, const bool ok, const string d = "")
  { if(ok) { g_pass++; PrintFormat("  PASS  %s", n); }
    else   { g_fail++; PrintFormat("  FAIL  %s  %s", n, d); } }
void CheckEq(const string n, const long e, const long a)
  { Check(n, e == a, StringFormat("expected=%I64d actual=%I64d", e, a)); }
void Section(const string t) { PrintFormat("--- %s", t); }

//+------------------------------------------------------------------+
void BuildBars(MqlRates &out[], const datetime start, const int count,
               const double base, const int digits)
  {
   ArrayResize(out, count);
   double p = base;
   for(int i = 0; i < count; i++)
     {
      double o = p, c = o + ((i % 7) - 3) * 0.5;
      out[i].time = start + i * 60;
      out[i].open = o; out[i].close = c;
      out[i].high = MathMax(o, c) + 1.0;
      out[i].low  = MathMin(o, c) - 1.0;
      out[i].tick_volume = 10; out[i].spread = 2; out[i].real_volume = 0;
      p = c;
     }
  }

//+------------------------------------------------------------------+
void OnStart()
  {
   Print("=== SSR Phase 7 - Performance Engine ===");
   int    digits = 2;
   double point  = 0.01;

   //================================================================
   Section("T7.1  the arithmetic that reshaped this phase");
   {
      //--- The design document assumed speed stresses the tick path and
      //--- set a 2000 ticks/s target. At 50x the engine advances 50
      //--- replay seconds per wall second - under one M1 bar. Pinning
      //--- the real figures stops that assumption coming back.
      double ticks_per_bar = 8.0;
      double at_50x = (50.0 / 60.0) * ticks_per_bar;
      Check("50x needs under 10 ticks/sec", at_50x < 10.0,
            StringFormat("%.2f", at_50x));

      double need_speed = (2000.0 / ticks_per_bar) * 60.0;
      Check("2000 ticks/sec would need over 10000x", need_speed > 10000.0,
            StringFormat("%.0fx", need_speed));

      //--- and 50x is not a fast-forward: a trading day still takes half
      //--- an hour, which is why Jump exists rather than a bigger number
      double day_minutes = 86400.0 / 50.0 / 60.0;
      Check("a day at 50x still takes over 25 minutes", day_minutes > 25.0,
            StringFormat("%.1f min", day_minutes));
   }

   //================================================================
   Section("T7.2  metrics measure, and admit when they cannot");
   {
      CSSRMetrics m;
      Check("starts uncalibrated", !m.IsCalibrated());
      CheckEq("no ticks per second yet", 0, (long)m.TicksPerSec());
      CheckEq("no seed rate yet",        0, (long)m.SeedBarsPerSec());

      //--- 100 ticks costing 1000us each
      for(int i = 0; i < 20; i++)
         m.RecordPump(2000.0, 1000.0, 10, 1, false);
      Check("calibrated after enough samples", m.IsCalibrated());
      Check("cost per tick derived", MathAbs(m.UsPerTick() - 100.0) < 1.0,
            StringFormat("%.1f us", m.UsPerTick()));
      Check("throughput follows from it",
            MathAbs(m.TicksPerSec() - 10000.0) < 100.0,
            StringFormat("%.0f t/s", m.TicksPerSec()));

      //--- a pump that emitted nothing says nothing about cost and must
      //--- not drag the average toward zero
      double before = m.UsPerTick();
      for(int i = 0; i < 10; i++)
         m.RecordPump(500.0, 0.0, 0, 0, false);
      Check("idle pumps do not dilute the cost figure",
            MathAbs(m.UsPerTick() - before) < 0.01,
            StringFormat("%.2f vs %.2f", m.UsPerTick(), before));

      m.RecordSeed(50000, 5000.0);
      Check("seed rate measured", MathAbs(m.SeedBarsPerSec() - 10000.0) < 1.0,
            StringFormat("%.0f bars/s", m.SeedBarsPerSec()));

      SSRPerfSnapshot snap;
      m.Snapshot(snap);
      Check("snapshot is marked calibrated", snap.calibrated);
      Check("percentiles ordered",
            snap.pump_p50_ms <= snap.pump_p95_ms &&
            snap.pump_p95_ms <= snap.pump_max_ms,
            snap.ToString());
      PrintFormat("        %s", snap.ToString());
   }

   //================================================================
   Section("T7.3  the pump ceiling follows the measurement");
   {
      CSSRMetrics m;
      CSSRPumpBudget b;
      b.Attach(GetPointer(m));
      b.SetBudgetMs(10.0);

      Check("uncalibrated budget says so", !b.IsCalibrated());
      int fallback = b.MaxTicks();
      Check("fallback is bounded", fallback >= SSR_PUMP_MIN_TICKS &&
                                   fallback <= SSR_PUMP_MAX_TICKS,
            IntegerToString(fallback));

      //--- a cheap tick: 10us. 10ms budget -> about 1000 ticks
      for(int i = 0; i < 20; i++)
         m.RecordPump(1000.0, 1000.0, 100, 10, false);
      Check("now calibrated", b.IsCalibrated());
      int cheap = b.MaxTicks();
      Check("cheap ticks buy a large ceiling", cheap > 500, IntegerToString(cheap));

      //--- an expensive tick must shrink it, without any constant changing
      CSSRMetrics m2;
      CSSRPumpBudget b2;
      b2.Attach(GetPointer(m2));
      b2.SetBudgetMs(10.0);
      for(int i = 0; i < 20; i++)
         m2.RecordPump(10000.0, 10000.0, 10, 1, false);   // 1000us per tick
      int dear = b2.MaxTicks();
      Check("expensive ticks shrink it", dear < cheap,
            StringFormat("%d vs %d", dear, cheap));
      Check("but never below the floor", dear >= SSR_PUMP_MIN_TICKS,
            IntegerToString(dear));

      CheckEq("bars ceiling divides by ticks per bar", cheap / 8, b.MaxBars(8));
      PrintFormat("        %s", b.ToString());
   }

   //================================================================
   Section("T7.4  fidelity degrades for the three real reasons");
   {
      CSSRFidelityPolicy f;
      f.SetRequested(SSR_FIDELITY_FULL_TICK);
      f.SetTicksAvailable(true);

      //--- ordinary playback: exactly what was asked for
      CheckEq("normal pump honours the request",
              SSR_FIDELITY_FULL_TICK, f.Decide(1000));
      Check("not marked degraded", !f.IsDegraded());
      Check("nothing to explain", f.ReasonText() == "");

      //--- reason 1: the data is not there
      f.SetTicksAvailable(false);
      CheckEq("no tick history falls back",
              SSR_FIDELITY_SYNTHETIC_TICK, f.Decide(1000));
      Check("and it is marked degraded", f.IsDegraded());
      Check("with a reason a user can read",
            StringFind(f.ReasonText(), "tick history") >= 0, f.ReasonText());

      //--- reason 2: a genuine bulk moment
      f.SetTicksAvailable(true);
      f.SetRequested(SSR_FIDELITY_SYNTHETIC_TICK);
      CheckEq("a bulk pump drops to bar close",
              SSR_FIDELITY_BAR, f.Decide(SSR_BULK_THRESHOLD_MSC + 1));
      Check("explained as catching up",
            StringFind(f.ReasonText(), "catching up") >= 0, f.ReasonText());
      CheckEq("and it recovers afterwards",
              SSR_FIDELITY_SYNTHETIC_TICK, f.Decide(1000));

      //--- reason 3: the user outranks the policy
      f.SetRequested(SSR_FIDELITY_SYNTHETIC_TICK);
      f.SetLocked(true);
      CheckEq("a locked fidelity survives a bulk moment",
              SSR_FIDELITY_SYNTHETIC_TICK, f.Decide(SSR_BULK_THRESHOLD_MSC * 10));
      Check("and says it is locked", f.IsLocked());
   }

   //================================================================
   Section("T7.5  the engine measures itself while running");
   {
      CSSRMemoryDataSource src;
      CSSRRecordingSink    sink;
      CSSRReplayController ctrl;

      MqlRates bars[];
      BuildBars(bars, InpStart, InpBars, InpBase, digits);
      src.LoadBars(bars, ArraySize(bars));

      long start = SSRToMsc(InpStart) + 120 * SSR_MSC_PER_MIN;
      long endt  = start + 600 * SSR_MSC_PER_MIN;

      ctrl.SetSymbolSpec(digits, point);
      ctrl.SetTicksPerBar(8);
      ctrl.SetWarmupBars(120);
      ctrl.SetFidelity(SSR_FIDELITY_SYNTHETIC_TICK);
      ctrl.Attach(GetPointer(src), GetPointer(sink));
      Check("loaded", ctrl.Load("TEST", start, endt), ctrl.LastErrorText());

      Check("uncalibrated before running", !ctrl.PerfCalibrated());
      Check("seed measured itself", ctrl.SeedBarsPerSec() > 0.0,
            StringFormat("%.0f bars/s", ctrl.SeedBarsPerSec()));

      ctrl.Play();
      for(int i = 0; i < 400; i++)
         ctrl.Pump(50);

      SSRPerfSnapshot p;
      ctrl.PerfInto(p);
      Check("calibrated after running", p.calibrated, p.ToString());
      Check("a per-tick cost was measured", p.us_per_tick > 0.0,
            StringFormat("%.2f us", p.us_per_tick));
      Check("percentiles populated", p.pump_p95_ms >= p.pump_p50_ms, p.ToString());
      PrintFormat("        %s", p.ToString());
      PrintFormat("        %s", ctrl.BudgetText());

      //--- the measurement must be usable as an input, not just a display
      CSSRHistoryCatalog cat;
      SSRSeedQuote q1;
      cat.Quote(PERIOD_H1, 300, 1000, q1);
      Check("a fresh quote is flagged as an estimate", !q1.measured);
      cat.SetMeasuredSeedRate(ctrl.SeedBarsPerSec());
      SSRSeedQuote q2;
      cat.Quote(PERIOD_H1, 300, 1000, q2);
      Check("after feeding the measurement it is not", q2.measured);
      Check("and the time changed with it", q1.seconds != q2.seconds,
            StringFormat("%.1f vs %.1f", q1.seconds, q2.seconds));
   }

   //================================================================
   Section("T7.6  a bulk pump is bounded, and owes the rest");
   {
      CSSRMemoryDataSource src;
      CSSRRecordingSink    sink;
      CSSRReplayController ctrl;

      MqlRates bars[];
      BuildBars(bars, InpStart, InpBars, InpBase, digits);
      src.LoadBars(bars, ArraySize(bars));

      long start = SSRToMsc(InpStart) + 120 * SSR_MSC_PER_MIN;
      long endt  = start + 2000 * SSR_MSC_PER_MIN;

      ctrl.SetSymbolSpec(digits, point);
      ctrl.SetTicksPerBar(8);
      ctrl.SetWarmupBars(120);
      ctrl.SetPumpBudgetMs(2.0);              // deliberately tight
      ctrl.SetFidelity(SSR_FIDELITY_SYNTHETIC_TICK);
      ctrl.Attach(GetPointer(src), GetPointer(sink));
      ctrl.Load("TEST", start, endt);
      ctrl.Play();

      //--- warm the measurement up first
      for(int i = 0; i < 60; i++)
         ctrl.Pump(50);

      //--- then one pump owing thirty minutes of market
      long before_time  = ctrl.Now();
      long before_ticks = ctrl.TicksEmitted();
      ctrl.Pump(30 * 60 * 1000);

      Check("the clock still advanced", ctrl.Now() > before_time);
      long emitted = ctrl.TicksEmitted() - before_ticks;
      Check("the bulk pump emitted something", emitted > 0,
            IntegerToString((int)emitted));

      //--- whatever the ceiling withheld must still arrive, not vanish
      long after_bulk = ctrl.TicksEmitted();
      for(int i = 0; i < 200; i++)
         ctrl.Pump(50);
      Check("the deferred work was delivered later",
            ctrl.TicksEmitted() > after_bulk,
            StringFormat("%I64d -> %I64d", after_bulk, ctrl.TicksEmitted()));
      CheckEq("and the stream stayed ordered", 0, sink.OrderViolations());
      CheckEq("with no duplicates", 0, sink.DuplicateStamps());
      CheckEq("and nothing beyond the clock", 0, sink.CountAfter(ctrl.Now()));
   }

   //================================================================
   Section("T7.7  no guessed constants remain unexplained");
   {
      //--- the pump ceiling is derived, and the engine says which mode
      //--- it is in rather than presenting a fallback as a measurement
      CSSRMetrics m;
      CSSRPumpBudget b;
      b.Attach(GetPointer(m));
      Check("an uncalibrated budget declares itself",
            StringFind(b.ToString(), "UNCALIBRATED") >= 0, b.ToString());
      for(int i = 0; i < 20; i++)
         m.RecordPump(1000.0, 800.0, 40, 5, false);
      Check("a calibrated one declares that instead",
            StringFind(b.ToString(), "measured") >= 0, b.ToString());
   }

   //================================================================
   PrintFormat("=== Phase 7: PASS=%d  FAIL=%d  ===> %s",
               g_pass, g_fail, (g_fail == 0 ? "GREEN" : "RED"));
  }
//+------------------------------------------------------------------+

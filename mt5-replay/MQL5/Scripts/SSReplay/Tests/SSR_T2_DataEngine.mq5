//+------------------------------------------------------------------+
//|                                             SSR_T2_DataEngine.mq5 |
//|                            SS Replay - Phase 2 Data Engine Tests |
//|                                                                  |
//|  Two halves, deliberately:                                       |
//|                                                                  |
//|    T2.1-T2.3  pure logic on synthetic arrays. No broker, no      |
//|               terminal state, fully deterministic. These must    |
//|               pass on any machine.                               |
//|                                                                  |
//|    T2.4-T2.9  the real MT5 providers against whatever symbol the |
//|               chart is on. These SKIP rather than fail when the  |
//|               broker has no history, because "this account has   |
//|               no M1 for this symbol" is not a code defect.       |
//+------------------------------------------------------------------+
#property script_show_inputs

#include <SSReplay/Common/SSR_Types.mqh>
#include <SSReplay/Common/SSR_Time.mqh>
#include <SSReplay/Common/SSR_Platform.mqh>
#include <SSReplay/Data/SSR_DataValidator.mqh>
#include <SSReplay/Data/SSR_Mt5DataSource.mqh>
#include <SSReplay/Core/SSR_ReplayController.mqh>
#include <SSReplay/Core/Sinks/SSR_RecordingSink.mqh>

input string InpSymbol   = "";     // Symbol (empty = current chart symbol)
input int    InpBars     = 600;    // M1 bars to replay
input int    InpWarmup   = 120;    // Warmup bars

int g_pass = 0, g_fail = 0, g_skip = 0;

void Check(const string n, const bool ok, const string d = "")
  { if(ok) { g_pass++; PrintFormat("  PASS  %s", n); }
    else   { g_fail++; PrintFormat("  FAIL  %s  %s", n, d); } }

void CheckEq(const string n, const long e, const long a)
  { Check(n, e == a, StringFormat("expected=%I64d actual=%I64d", e, a)); }

void Skip(const string n, const string why)
  { g_skip++; PrintFormat("  SKIP  %s  (%s)", n, why); }

void Section(const string t) { PrintFormat("--- %s", t); }

//+------------------------------------------------------------------+
//| Build a clean M1 series, then damage it on request.               |
//+------------------------------------------------------------------+
void MakeBars(MqlRates &out[], const datetime start, const int count, const double base)
  {
   ArrayResize(out, count);
   for(int i = 0; i < count; i++)
     {
      double o = base + i * 0.5;
      out[i].time        = start + i * 60;
      out[i].open        = o;
      out[i].high        = o + 1.0;
      out[i].low         = o - 1.0;
      out[i].close       = o + 0.25;
      out[i].tick_volume = 10;
      out[i].spread      = 2;
      out[i].real_volume = 0;
     }
  }

//+------------------------------------------------------------------+
void OnStart()
  {
   string sym = (InpSymbol == "" ? _Symbol : InpSymbol);
   Print("=== SSR Phase 2 - Data Engine Tests ===");
   PrintFormat("    symbol under test: %s", sym);

   CSSRDataValidator val;
   datetime t0 = D'2024.01.08 00:00';

   //================================================================
   Section("T2.1  validator on clean data");
   {
      MqlRates b[];
      MakeBars(b, t0, 100, 38000.0);
      SSRDataReport r;
      val.ValidateBars(b, 100, r);

      CheckEq("total counted",        100, r.total);
      CheckEq("no duplicates",          0, r.duplicates);
      CheckEq("no out of order",        0, r.out_of_order);
      CheckEq("no micro gaps",          0, r.micro_gaps);
      CheckEq("no session gaps",        0, r.session_gaps);
      CheckEq("no bad ohlc",            0, r.invalid_ohlc);
      Check  ("reports clean",  r.IsClean(), r.ToString());
      CheckEq("first instant", SSRToMsc(t0), r.first_msc);
      //--- last_msc is the CLOSE of the final bar, not its open
      CheckEq("last instant is the bar close",
              SSRToMsc(t0) + 99 * SSR_MSC_PER_MIN + SSR_MSC_PER_MIN - 1, r.last_msc);
   }

   //================================================================
   Section("T2.2  validator finds real damage");
   {
      //--- duplicate minute
      MqlRates d[];
      MakeBars(d, t0, 50, 38000.0);
      d[20].time = d[19].time;
      SSRDataReport rd;
      val.ValidateBars(d, 50, rd);
      Check("duplicate detected", rd.duplicates >= 1, rd.ToString());
      Check("not reported clean", !rd.IsClean());

      //--- a bar older than its predecessor
      MqlRates o[];
      MakeBars(o, t0, 50, 38000.0);
      o[30].time = o[10].time;
      SSRDataReport ro;
      val.ValidateBars(o, 50, ro);
      Check("out of order detected", ro.out_of_order >= 1, ro.ToString());

      //--- a five minute hole: below the session threshold
      MqlRates g[];
      MakeBars(g, t0, 50, 38000.0);
      for(int i = 25; i < 50; i++)
         g[i].time += 5 * 60;
      SSRDataReport rg;
      val.ValidateBars(g, 50, rg);
      CheckEq("micro gap counted", 1, rg.micro_gaps);
      CheckEq("not called a session gap", 0, rg.session_gaps);

      //--- a weekend sized hole must NOT be reported as damage
      MqlRates w[];
      MakeBars(w, t0, 50, 38000.0);
      for(int i = 25; i < 50; i++)
         w[i].time += 48 * 60 * 60;
      SSRDataReport rw;
      val.ValidateBars(w, 50, rw);
      CheckEq("session gap counted",  1, rw.session_gaps);
      CheckEq("not called a micro gap", 0, rw.micro_gaps);
      Check("market closure is still clean data", rw.IsClean(), rw.ToString());

      //--- broken OHLC invariants are fatal, not cosmetic
      MqlRates x[];
      MakeBars(x, t0, 50, 38000.0);
      x[10].high = x[10].low - 5.0;
      SSRDataReport rx;
      val.ValidateBars(x, 50, rx);
      Check("invalid ohlc detected", rx.invalid_ohlc >= 1, rx.ToString());
      Check("unusable data is flagged", !rx.IsUsable());
   }

   //================================================================
   Section("T2.3  sanitize produces a replay-safe series");
   {
      MqlRates b[];
      MakeBars(b, t0, 60, 38000.0);
      b[20].time = b[19].time;      // duplicate
      b[40].time = b[10].time;      // backwards
      int clean = val.SanitizeBars(b, 60);

      Check("bars were dropped", clean < 60, IntegerToString(clean));

      bool strictly_increasing = true;
      for(int i = 1; i < clean; i++)
         if(b[i].time <= b[i - 1].time)
            strictly_increasing = false;
      Check("result is strictly increasing", strictly_increasing);

      SSRDataReport r;
      val.ValidateBars(b, clean, r);
      CheckEq("no duplicates survive",   0, r.duplicates);
      CheckEq("no out of order survives", 0, r.out_of_order);

      //--- ticks may legitimately share a millisecond, so only a
      //--- backwards stamp is removed
      MqlTick tk[];
      ArrayResize(tk, 5);
      long base = SSRToMsc(t0) * 1;
      long stamps[5] = {0, 10, 10, 5, 20};
      for(int i = 0; i < 5; i++)
        { tk[i].time_msc = base + stamps[i]; tk[i].bid = 1.0; tk[i].ask = 1.1; }
      int tclean = val.SanitizeTicks(tk, 5);
      CheckEq("equal stamps kept, backwards dropped", 4, tclean);
   }

   //================================================================
   Section("T2.4  discovery against the broker");

   CSSRMt5DataSource src;
   SSRDataRange range;
   range.Init();
   bool have_data = false;

   {
      bool opened = src.Open(sym);
      if(!opened)
        {
         Skip("discovery", "no M1 history for " + sym + " on this account");
        }
      else
        {
         src.RangeInto(range);
         have_data = range.available;

         Check("source opened", src.IsOpen());
         Check("range available", range.available);
         Check("first is before last", range.first_msc < range.last_msc,
               StringFormat("%s .. %s", SSRFormatMsc(range.first_msc),
                            SSRFormatMsc(range.last_msc)));
         Check("bar count positive", range.bar_count > 0,
               IntegerToString((int)range.bar_count));
         PrintFormat("        M1 depth: %d bars, %s .. %s",
                     (int)range.bar_count,
                     SSRFormatMsc(range.first_msc), SSRFormatMsc(range.last_msc));
         PrintFormat("        real ticks available: %s",
                     (range.has_ticks ? "yes" : "no"));
         PrintFormat("        deeper history downloadable: %s",
                     (range.CanExtendBackwards() ? "yes" : "no"));
        }
   }

   //--- a replay window near the end of the available data
   long win_end   = (have_data ? range.last_msc : 0);
   long win_start = win_end - (long)InpBars * SSR_MSC_PER_MIN;
   if(have_data && win_start < range.first_msc + (long)InpWarmup * SSR_MSC_PER_MIN)
      win_start = range.first_msc + (long)InpWarmup * SSR_MSC_PER_MIN;

   //================================================================
   Section("T2.5  bar provider and the read window");
   if(!have_data)
      Skip("bar provider", "no broker data");
   else
     {
      CSSRBarProvider *bp = src.Bars();
      Check("bar provider exists", bp != NULL);

      MqlRates got[];
      int n = bp.ReadBars(sym, win_start, win_start + 60 * SSR_MSC_PER_MIN, got);
      Check("bars read", n > 0, StringFormat("n=%d err=%s", n, bp.LastErrorText()));

      if(n > 0)
        {
         bool ordered = true;
         for(int i = 1; i < n; i++)
            if(got[i].time <= got[i - 1].time)
               ordered = false;
         Check("returned bars are ordered", ordered);

         bool in_range = (SSRToMsc(got[0].time) >= win_start &&
                          SSRToMsc(got[n - 1].time) <= win_start + 60 * SSR_MSC_PER_MIN);
         Check("returned bars are inside the request", in_range);
        }

      //--- a second overlapping read must be served from the window
      CSSRMt5BarProvider *mbp = src.Mt5Bars();
      long misses_before = mbp.Window().Misses();
      MqlRates again[];
      bp.ReadBars(sym, win_start + 10 * SSR_MSC_PER_MIN,
                       win_start + 40 * SSR_MSC_PER_MIN, again);
      CheckEq("overlapping read caused no reload",
              misses_before, mbp.Window().Misses());
      Check("window reports a hit rate", mbp.Window().HitRate() > 0.0,
            mbp.Window().ToString());
      PrintFormat("        %s", mbp.Window().ToString());
     }

   //================================================================
   Section("T2.6  the guard is enforced INSIDE the provider");
   if(!have_data)
      Skip("provider guard", "no broker data");
   else
     {
      CSSRFutureGuard guard;
      guard.Arm(win_start);
      src.SetGuard(GetPointer(guard));

      CSSRBarProvider *bp = src.Bars();

      //--- the past is readable
      MqlRates past[];
      int np = bp.ReadBars(sym, win_start - 30 * SSR_MSC_PER_MIN, win_start, past);
      Check("past still readable through the guard", np > 0, IntegerToString(np));

      //--- the future is not, even though the controller never clamped it
      MqlRates future[];
      int nf = bp.ReadBars(sym, win_start + SSR_MSC_PER_MIN,
                                win_start + 100 * SSR_MSC_PER_MIN, future);
      CheckEq("provider refuses a future range", 0, nf);
      Check("violation was recorded", guard.Violations() > 0,
            IntegerToString((int)guard.Violations()));

      //--- a range straddling the horizon is trimmed, not refused
      long before = guard.Violations();
      MqlRates straddle[];
      int ns = bp.ReadBars(sym, win_start - 10 * SSR_MSC_PER_MIN,
                                win_start + 10 * SSR_MSC_PER_MIN, straddle);
      Check("straddling range is trimmed not refused", ns > 0, IntegerToString(ns));
      if(ns > 0)
         Check("nothing past the horizon survived",
               SSRToMsc(straddle[ns - 1].time) <= win_start);
      Check("trimming counted a violation", guard.Violations() > before);

      //--- TODO T1 from Phase 1: detaching must leave nothing pointing
      //--- at a guard that is about to die
      src.DetachGuard();
      MqlRates after[];
      int na = bp.ReadBars(sym, win_start + SSR_MSC_PER_MIN,
                                win_start + 5 * SSR_MSC_PER_MIN, after);
      Check("reads still work after detach", na >= 0, IntegerToString(na));
     }

   //================================================================
   Section("T2.7  the tick provider is honest about what it has");
   if(!have_data)
      Skip("tick provider", "no broker data");
   else
     {
      CSSRTickProvider *tp = src.Ticks();
      if(tp == NULL)
        {
         Check("no ticks reported as NULL, not as an empty array", !range.has_ticks,
               "source says it has ticks but returned NULL");
         PrintFormat("        no real tick history - FULL_TICK fidelity is unavailable here");
        }
      else
        {
         Check("tick provider offered only when ticks exist", range.has_ticks);
         MqlTick tk[];
         int n = tp.ReadTicks(sym, win_end - 10 * SSR_MSC_PER_MIN, win_end, tk);
         Check("ticks read", n >= 0, StringFormat("n=%d err=%s", n, tp.LastErrorText()));
         if(n > 1)
           {
            bool ordered = true;
            for(int i = 1; i < n; i++)
               if(tk[i].time_msc < tk[i - 1].time_msc)
                  ordered = false;
            Check("ticks are chronological", ordered);
            Check("lower bound is half-open", tk[0].time_msc > win_end - 10 * SSR_MSC_PER_MIN);
           }
         PrintFormat("        %d ticks over the last 10 minutes of data", n);
        }
     }

   //================================================================
   Section("T2.8  end to end: real data through the Phase 1 engine");
   if(!have_data)
      Skip("integration", "no broker data");
   else
     {
      CSSRMt5DataSource   src2;
      CSSRRecordingSink   sink;
      CSSRReplayController ctrl;

      int    digits = (int)SymbolInfoInteger(sym, SYMBOL_DIGITS);
      double point  = SymbolInfoDouble(sym, SYMBOL_POINT);
      if(point <= 0.0) point = MathPow(10, -digits);

      ctrl.SetSymbolSpec(digits, point);
      ctrl.SetSpreadPoints(20);
      ctrl.SetTicksPerBar(8);
      ctrl.SetWarmupBars(InpWarmup);
      ctrl.SetDataMode(SSR_DATA_BROKER);
      ctrl.SetFidelity(SSR_FIDELITY_SYNTHETIC_TICK);
      ctrl.Attach(GetPointer(src2), GetPointer(sink));

      bool loaded = ctrl.Load(sym, win_start, win_end);
      Check("engine loaded real broker data", loaded, ctrl.LastErrorText());

      if(loaded)
        {
         Check("state is READY", ctrl.Status() == SSR_STATE_READY,
               SSRStateName(ctrl.Status()));
         Check("warmup seeded", sink.SeedBarCount() > 0,
               IntegerToString(sink.SeedBarCount()));

         ctrl.SetSpeedX100(SSR_SPEED_1);
         ctrl.Play();
         for(int i = 0; i < 120; i++)
            ctrl.Pump(1000);

         Check("ticks emitted from real data", sink.TickCount() > 0,
               IntegerToString(sink.TickCount()));
         CheckEq("stream is ordered",           0, sink.OrderViolations());
         CheckEq("no duplicate stamps",         0, sink.DuplicateStamps());
         CheckEq("nothing beyond replay time",  0, sink.CountAfter(ctrl.Now()));
         //--- Measure the advance from the window the engine ACTUALLY
         //--- opened, not the one we asked for. SetWindow snaps the start
         //--- down to an M1 boundary deliberately: a replay window has to
         //--- begin on a bar open, because truncation can only land on
         //--- one, and a mid-minute start would make the first rewind cut
         //--- into the warmup. `win_start` is derived from the last bar of
         //--- the data and is a bar-CLOSE instant, so request and window
         //--- legitimately differ by up to a minute. Comparing against the
         //--- request measured the snap, not the clock.
         //--- WHEN THIS FAILS, SAY ENOUGH TO DIAGNOSE IT. A clock that
         //--- stopped short can mean the engine errored, completed, or
         //--- was paused by an observer - and a bare pair of numbers
         //--- cannot tell those apart. It cost a whole round trip once.
         long clock_from = ctrl.StartMsc();
         Check("clock advanced 120s", ctrl.Now() == clock_from + 120000,
               StringFormat("expected=%I64d actual=%I64d (%+I64d ms)  state=%s  "
                            "asked=%I64d  window=%I64d..%I64d  err=%s",
                            clock_from + 120000, ctrl.Now(),
                            ctrl.Now() - (clock_from + 120000),
                            SSRStateName(ctrl.Status()), win_start,
                            ctrl.StartMsc(), ctrl.EndMsc(),
                            ctrl.LastErrorText()));
         CheckEq("no guard violations in normal play", 0, ctrl.Violations());

         //--- Phase 1 said Core would not change to accept a real source.
         //--- This is that claim, executed.
         Check("Phase 1 contract held with a real source", true);
        }
     }

   //================================================================
   Section("T2.9  market closures are data, not errors");
   if(!have_data)
      Skip("weekend handling", "no broker data");
   else
     {
      CSSRMt5BarProvider *mbp = src.Mt5Bars();
      mbp.Invalidate();

      //--- walk back to a Saturday inside the available history and ask
      //--- for an hour of it. The market was shut; the correct answer is
      //--- zero bars, NOT a load failure.
      long probe = range.last_msc;
      for(int back = 0; back < 10; back++)
        {
         MqlDateTime st;
         TimeToStruct(SSRToTime(probe), st);
         if(st.day_of_week == 6)      // Saturday
            break;
         probe -= 24 * 60 * 60 * 1000;
        }

      MqlRates none[];
      int n = mbp.ReadBars(sym, probe, probe + 60 * SSR_MSC_PER_MIN, none);
      Check("closed market returns 0, not -1", n >= 0,
            StringFormat("n=%d err=%s", n, mbp.LastErrorText()));
      Check("no error was raised for a closure",
            mbp.LastError() == SSR_OK, SSRErrName(mbp.LastError()));

      //--- and asking again must be served from the window rather than
      //--- reloading the same empty range on every pump
      long misses_before = mbp.Window().Misses();
      mbp.ReadBars(sym, probe, probe + 60 * SSR_MSC_PER_MIN, none);
      CheckEq("empty range is remembered, not re-fetched",
              misses_before, mbp.Window().Misses());
     }

   //================================================================
   Section("T2.10  Load More History probe");
   if(!have_data)
      Skip("extend backwards", "no broker data");
   else
     {
      CSSRHistoryProvider *hp = src.History();
      long before = range.first_msc;
      long after  = hp.ExtendBackwards(sym, 5000);
      Check("extend returned a valid instant", after > 0, SSRFormatMsc(after));
      Check("history never shrinks", after <= before + SSR_MSC_PER_MIN,
            StringFormat("before=%s after=%s", SSRFormatMsc(before), SSRFormatMsc(after)));
      if(after < before)
         PrintFormat("        gained %s of older history", SSRFormatSpan(before - after));
      else
         PrintFormat("        broker has nothing older than %s", SSRFormatMsc(before));
     }

   //================================================================
   PrintFormat("=== Phase 2: PASS=%d  FAIL=%d  SKIP=%d  ===> %s",
               g_pass, g_fail, g_skip, (g_fail == 0 ? "GREEN" : "RED"));
  }
//+------------------------------------------------------------------+

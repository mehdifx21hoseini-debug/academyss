//+------------------------------------------------------------------+
//|                                               SSR_T9_Trading.mq5 |
//|                     SS Replay - Phase 9 Virtual Trading Engine   |
//|                                                                  |
//|  The centrepiece here is the stop-and-target ambiguity, risk R11 |
//|  of the design document. A backtester that resolves a coin flip  |
//|  in the trader's favour manufactures winning strategies, so the  |
//|  tests below pin the pessimistic behaviour and the flag that     |
//|  makes it visible.                                               |
//+------------------------------------------------------------------+
#property script_show_inputs

#include <SSReplay/Common/SSR_Types.mqh>
#include <SSReplay/Common/SSR_Time.mqh>
#include <SSReplay/Core/SSR_ReplayController.mqh>
#include <SSReplay/Core/Sources/SSR_MemoryDataSource.mqh>
#include <SSReplay/Core/Sinks/SSR_RecordingSink.mqh>
#include <SSReplay/Trading/SSR_TradingEngine.mqh>

input datetime InpStart  = D'2024.01.08 00:00';
input int      InpBars   = 2000;
input double   InpBase   = 1000.0;
input int      InpWarmup = 60;

int g_pass = 0, g_fail = 0;
void Check(const string n, const bool ok, const string d = "")
  { if(ok) { g_pass++; PrintFormat("  PASS  %s", n); }
    else   { g_fail++; PrintFormat("  FAIL  %s  %s", n, d); } }
void CheckEq(const string n, const long e, const long a)
  { Check(n, e == a, StringFormat("expected=%I64d actual=%I64d", e, a)); }
void CheckNear(const string n, const double e, const double a, const double tol)
  { Check(n, MathAbs(e - a) <= tol, StringFormat("expected=%.4f actual=%.4f", e, a)); }
void Section(const string t) { PrintFormat("--- %s", t); }

//--- a flat, predictable market: every bar opens and closes at base,
//--- so a test can place a stop and a target by hand and know exactly
//--- which bars reach them
void BuildBars(MqlRates &out[], const datetime start, const int count,
               const double base, const double range)
  {
   ArrayResize(out, count);
   for(int i = 0; i < count; i++)
     {
      out[i].time  = start + i * 60;
      out[i].open  = base;
      out[i].close = base;
      out[i].high  = base + range;
      out[i].low   = base - range;
      out[i].tick_volume = 10; out[i].spread = 2; out[i].real_volume = 0;
     }
  }

//+------------------------------------------------------------------+
void OnStart()
  {
   Print("=== SSR Phase 9 - Virtual Trading Engine ===");
   int    digits = 2;
   double point  = 0.01;

   //================================================================
   Section("T9.1  position sizing from risk, rounded the safe way");
   {
      CSSRRiskEngine r;
      //--- 1 unit of price = 1 currency per lot, min 0.01, step 0.01
      r.Configure(1.0, 1.0, 0.01, 100.0, 0.01, 2);

      //--- risk 100 on a 10-point stop -> 10 lots
      CheckNear("straightforward size", 10.0,
                r.LotForRisk(10000.0, 1.0, 1000.0, 990.0), 0.001);

      //--- and the money it actually risks matches what was asked
      CheckNear("risked amount matches", 100.0,
                r.RiskOf(10.0, 10.0), 0.001);
      CheckNear("expressed as a percentage", 1.0,
                r.RiskPercentOf(10000.0, 10.0, 1000.0, 990.0), 0.001);

      //--- rounding must go DOWN: a "1%" that is sometimes 1.3% is a bug
      double lot = r.LotForRisk(10000.0, 1.0, 1000.0, 993.0);   // 14.28 lots
      Check("rounded down to the step", lot <= 14.28 + 1e-9,
            StringFormat("%.4f", lot));
      Check("and never above the asked risk",
            r.RiskOf(lot, 7.0) <= 100.0 + 1e-6,
            StringFormat("%.4f", r.RiskOf(lot, 7.0)));

      //--- too small to trade must be REFUSED, not silently oversized
      CheckNear("below the minimum lot is refused", 0.0,
                r.LotForRisk(10.0, 0.1, 1000.0, 990.0), 1e-9);
      Check("and it says why", StringLen(r.LastReason()) > 0, r.LastReason());

      CheckNear("a stop at the entry is refused", 0.0,
                r.LotForRisk(10000.0, 1.0, 1000.0, 1000.0), 1e-9);
   }

   //--- shared session wiring -------------------------------------
   long start = SSRToMsc(InpStart) + (long)InpWarmup * SSR_MSC_PER_MIN;
   long endt  = start + 600 * SSR_MSC_PER_MIN;

   //================================================================
   Section("T9.2  the engine trades on the replay stream");

   CSSRMemoryDataSource src;
   CSSRRecordingSink    sink;
   CSSRReplayController ctrl;
   CSSRTradingEngine    acct;

   {
      MqlRates bars[];
      BuildBars(bars, InpStart, InpBars, InpBase, 5.0);
      src.LoadBars(bars, ArraySize(bars));

      acct.SetBalance(10000.0);
      acct.Risk().Configure(1.0, 1.0, 0.01, 100.0, 0.01, digits);

      ctrl.SetSymbolSpec(digits, point);
      ctrl.SetSpreadPoints(0);            // clean prices for exact assertions
      ctrl.SetTicksPerBar(8);
      ctrl.SetWarmupBars(InpWarmup);
      ctrl.SetFidelity(SSR_FIDELITY_SYNTHETIC_TICK);
      ctrl.Attach(GetPointer(src), GetPointer(sink));
      Check("observer registered", ctrl.AddObserver(GetPointer(acct)));
      CheckEq("one observer", 1, ctrl.ObserverCount());
      Check("loaded", ctrl.Load("TEST", start, endt), ctrl.LastErrorText());

      Check("session start reached the account", acct.Balance() == 10000.0,
            DoubleToString(acct.Balance(), 2));

      ctrl.Play();
      for(int i = 0; i < 120; i++)
         ctrl.Pump(1000);

      Check("the account sees prices", acct.Bid() > 0.0,
            DoubleToString(acct.Bid(), 2));
   }

   //================================================================
   Section("T9.3  open, modify and close");
   {
      long t = acct.Open(SSR_ORDER_BUY, 1.0, 990.0, 1010.0, 0.0, "manual");
      Check("opened", t > 0, acct.LastError());
      CheckEq("one open position", 1, acct.OpenCount());

      SSRVirtualPosition p;
      Check("readable by ticket", acct.ByTicket(t, p));
      Check("it is long", p.IsLong());
      CheckNear("stop stored", 990.0, p.sl, 0.001);

      Check("modified", acct.Modify(t, 995.0, 1005.0));
      acct.ByTicket(t, p);
      CheckNear("stop moved", 995.0, p.sl, 0.001);

      Check("break even", acct.BreakEven(t));
      acct.ByTicket(t, p);
      CheckNear("stop is at the entry", p.open_price, p.sl, 0.001);

      Check("closed", acct.Close(t));
      CheckEq("no open positions", 0, acct.OpenCount());
      CheckEq("one closed", 1, acct.ClosedCount());
      acct.ByTicket(t, p);
      Check("closed manually", p.reason == SSR_CLOSE_MANUAL,
            SSRCloseReasonName(p.reason));
      Check("not ambiguous - it was closed by hand", !p.ambiguous);
   }

   //================================================================
   Section("T9.4  THE HONEST CASE: a bar holding both stop and target");
   {
      //--- every bar in this dataset spans base +/- 5, so a stop at
      //--- base-3 and a target at base+3 both fall inside EVERY bar.
      //--- On synthesised ticks we cannot know which came first.
      CSSRMemoryDataSource s2;
      CSSRRecordingSink    k2;
      CSSRReplayController c2;
      CSSRTradingEngine    a2;

      MqlRates bars[];
      BuildBars(bars, InpStart, InpBars, InpBase, 5.0);
      s2.LoadBars(bars, ArraySize(bars));

      a2.SetBalance(10000.0);
      a2.Risk().Configure(1.0, 1.0, 0.01, 100.0, 0.01, digits);
      c2.SetSymbolSpec(digits, point);
      c2.SetSpreadPoints(0);
      c2.SetTicksPerBar(8);
      c2.SetWarmupBars(InpWarmup);
      c2.SetFidelity(SSR_FIDELITY_SYNTHETIC_TICK);
      c2.Attach(GetPointer(s2), GetPointer(k2));
      c2.AddObserver(GetPointer(a2));
      c2.Load("TEST", start, endt);
      c2.Play();
      for(int i = 0; i < 30; i++)
         c2.Pump(1000);

      long t = a2.Open(SSR_ORDER_BUY, 1.0, InpBase - 3.0, InpBase + 3.0, 0.0, "coinflip");
      Check("opened inside an ambiguous range", t > 0, a2.LastError());

      for(int i = 0; i < 180; i++)
         c2.Pump(1000);

      SSRVirtualPosition p;
      a2.ByTicket(t, p);
      Check("it closed", p.IsClosed(), SSRCloseReasonName(p.reason));

      //--- the two assertions this whole phase turns on
      Check("the LOSS was taken, not the win",
            p.reason == SSR_CLOSE_SL, SSRCloseReasonName(p.reason));
      Check("and the trade is flagged as an assumption",
            p.ambiguous, "an unflagged coin flip is a manufactured edge");

      Check("the account counts it", a2.AmbiguousCount() >= 1,
            IntegerToString((int)a2.AmbiguousCount()));
      Check("and reports the proportion", a2.AmbiguousPercent() > 0.0,
            StringFormat("%.0f%%", a2.AmbiguousPercent()));
      PrintFormat("        %s", a2.ToString());
   }

   //================================================================
   Section("T9.5  an unambiguous stop is not flagged");
   {
      CSSRMemoryDataSource s3;
      CSSRRecordingSink    k3;
      CSSRReplayController c3;
      CSSRTradingEngine    a3;

      MqlRates bars[];
      BuildBars(bars, InpStart, InpBars, InpBase, 5.0);
      s3.LoadBars(bars, ArraySize(bars));

      a3.SetBalance(10000.0);
      a3.Risk().Configure(1.0, 1.0, 0.01, 100.0, 0.01, digits);
      c3.SetSymbolSpec(digits, point);
      c3.SetSpreadPoints(0);
      c3.SetTicksPerBar(8);
      c3.SetWarmupBars(InpWarmup);
      c3.SetFidelity(SSR_FIDELITY_SYNTHETIC_TICK);
      c3.Attach(GetPointer(s3), GetPointer(k3));
      c3.AddObserver(GetPointer(a3));
      c3.Load("TEST", start, endt);
      c3.Play();
      for(int i = 0; i < 30; i++)
         c3.Pump(1000);

      //--- stop inside the bar, target far outside it: only one can be
      //--- reached, so there is nothing to assume
      long t = a3.Open(SSR_ORDER_BUY, 1.0, InpBase - 3.0, InpBase + 500.0);
      for(int i = 0; i < 180; i++)
         c3.Pump(1000);

      SSRVirtualPosition p;
      a3.ByTicket(t, p);
      Check("stopped out", p.reason == SSR_CLOSE_SL, SSRCloseReasonName(p.reason));
      Check("NOT flagged, because nothing was assumed", !p.ambiguous);
      CheckEq("nothing counted as ambiguous", 0, a3.AmbiguousCount());
   }

   //================================================================
   Section("T9.6  pendings, partials and trailing");
   {
      CSSRMemoryDataSource s4;
      CSSRRecordingSink    k4;
      CSSRReplayController c4;
      CSSRTradingEngine    a4;

      MqlRates bars[];
      BuildBars(bars, InpStart, InpBars, InpBase, 5.0);
      s4.LoadBars(bars, ArraySize(bars));

      a4.SetBalance(10000.0);
      a4.Risk().Configure(1.0, 1.0, 0.01, 100.0, 0.01, digits);
      c4.SetSymbolSpec(digits, point);
      c4.SetSpreadPoints(0);
      c4.SetTicksPerBar(8);
      c4.SetWarmupBars(InpWarmup);
      c4.Attach(GetPointer(s4), GetPointer(k4));
      c4.AddObserver(GetPointer(a4));
      c4.Load("TEST", start, endt);
      c4.Play();
      for(int i = 0; i < 30; i++)
         c4.Pump(1000);

      //--- a buy limit below the market, which every bar reaches
      long pend = a4.Open(SSR_ORDER_BUY_LIMIT, 1.0, 0.0, 0.0, InpBase - 4.0);
      Check("pending placed", pend > 0, a4.LastError());
      CheckEq("counted as pending", 1, a4.PendingCount());

      for(int i = 0; i < 90; i++)
         c4.Pump(1000);
      CheckEq("it filled", 0, a4.PendingCount());
      Check("and is now open", a4.OpenCount() >= 1, IntegerToString(a4.OpenCount()));

      //--- a partial exit must not fabricate a second trade
      long t = a4.Open(SSR_ORDER_BUY, 2.0);
      int closed_before = a4.ClosedCount();
      Check("partial close", a4.ClosePartial(t, 1.0), a4.LastError());
      SSRVirtualPosition p;
      a4.ByTicket(t, p);
      CheckNear("half the volume remains", 1.0, p.volume, 0.001);
      Check("still one position, still open", p.IsOpen());
      CheckEq("no extra closed trade appeared", closed_before, a4.ClosedCount());

      //--- trailing only ever moves the stop in the good direction
      Check("trailing set", a4.SetTrailing(t, 200));
      for(int i = 0; i < 60; i++)
         c4.Pump(1000);
      a4.ByTicket(t, p);
      Check("a stop now exists", p.sl > 0.0, DoubleToString(p.sl, 2));

      double first = p.sl;
      for(int i = 0; i < 60; i++)
         c4.Pump(1000);
      a4.ByTicket(t, p);
      Check("and it never moved backwards", p.sl >= first - 1e-9,
            StringFormat("%.2f -> %.2f", first, p.sl));

      Check("close all", a4.CloseAll() > 0);
      CheckEq("nothing open", 0, a4.OpenCount());
   }

   //================================================================
   Section("T9.7  a rewind un-happens the trades");
   {
      CSSRMemoryDataSource s5;
      CSSRRecordingSink    k5;
      CSSRReplayController c5;
      CSSRTradingEngine    a5;

      MqlRates bars[];
      BuildBars(bars, InpStart, InpBars, InpBase, 5.0);
      s5.LoadBars(bars, ArraySize(bars));

      a5.SetBalance(10000.0);
      a5.Risk().Configure(1.0, 1.0, 0.01, 100.0, 0.01, digits);
      c5.SetSymbolSpec(digits, point);
      c5.SetSpreadPoints(0);
      c5.SetTicksPerBar(8);
      c5.SetWarmupBars(InpWarmup);
      c5.Attach(GetPointer(s5), GetPointer(k5));
      c5.AddObserver(GetPointer(a5));
      c5.Load("TEST", start, endt);
      c5.Play();
      for(int i = 0; i < 200; i++)
         c5.Pump(1000);

      long before_time = c5.Now();
      int  before_open = a5.OpenCount();

      //--- a trade taken AFTER the mark
      for(int i = 0; i < 60; i++)
         c5.Pump(1000);
      long t = a5.Open(SSR_ORDER_BUY, 1.0);
      Check("a trade was taken later", t > 0);
      Check("it is open", a5.OpenCount() == before_open + 1,
            IntegerToString(a5.OpenCount()));

      //--- now rewind past it
      long back = (c5.Now() - before_time) / SSR_MSC_PER_MIN + 2;
      Check("stepped back", c5.StepBackward((int)back), c5.LastErrorText());

      //--- the assertion that matters: a trade opened in a future that
      //--- was deleted must not survive as a balance nobody can explain
      SSRVirtualPosition gone;
      Check("the trade ceased to have existed", !a5.ByTicket(t, gone));
      CheckEq("open count is back", before_open, a5.OpenCount());

      //--- and specifically through the CHECKPOINT path, which is the
      //--- one a real rewind takes once checkpoints exist. The plain
      //--- seek fallback published correctly all along; the snapshot
      //--- path did not, so it gets its own assertion.
      Check("checkpoints were in play", c5.Snapshots().Count() > 0,
            c5.SnapshotText());

      for(int i = 0; i < 120; i++)
         c5.Pump(1000);
      long mark2 = c5.Now();
      for(int i = 0; i < 120; i++)
         c5.Pump(1000);
      long t2 = a5.Open(SSR_ORDER_BUY, 1.0, 0.0, 0.0, 0.0, "after-mark");
      Check("another trade taken after the mark", t2 > 0);

      long back2 = (c5.Now() - mark2) / SSR_MSC_PER_MIN + 2;
      c5.StepBackward((int)back2);
      SSRVirtualPosition gone2;
      Check("it did not survive the snapshot-path rewind either",
            !a5.ByTicket(t2, gone2));
   }

   //================================================================
   Section("T9.8  execution costs are charged, never in your favour");
   {
      CSSRMemoryDataSource s6;
      CSSRRecordingSink    k6;
      CSSRReplayController c6;
      CSSRTradingEngine    a6;

      MqlRates bars[];
      BuildBars(bars, InpStart, InpBars, InpBase, 5.0);
      s6.LoadBars(bars, ArraySize(bars));

      SSRExecutionModel ex;
      ex.Init();
      ex.commission_per_lot = 7.0;
      ex.slippage_points    = 10.0;
      a6.SetExecution(ex);
      a6.SetBalance(10000.0);
      a6.Risk().Configure(1.0, 1.0, 0.01, 100.0, 0.01, digits);

      c6.SetSymbolSpec(digits, point);
      c6.SetSpreadPoints(20);
      c6.SetTicksPerBar(8);
      c6.SetWarmupBars(InpWarmup);
      c6.Attach(GetPointer(s6), GetPointer(k6));
      c6.AddObserver(GetPointer(a6));
      c6.Load("TEST", start, endt);
      c6.Play();
      for(int i = 0; i < 60; i++)
         c6.Pump(1000);

      double bal0 = a6.Balance();
      long   t    = a6.Open(SSR_ORDER_BUY, 1.0);
      CheckNear("commission charged on entry", bal0 - 7.0, a6.Balance(), 0.001);

      SSRVirtualPosition p;
      a6.ByTicket(t, p);
      //--- a buy fills at the ask, plus slippage. Never at the bid.
      Check("filled the wrong side of the spread, plus slippage",
            p.open_price >= a6.Ask() - 1e-9,
            StringFormat("fill=%.2f ask=%.2f", p.open_price, a6.Ask()));

      double bal1 = a6.Balance();
      a6.Close(t);
      a6.ByTicket(t, p);
      CheckNear("commission charged again on exit",
                14.0, p.commission, 0.001);
      Check("a round trip at a flat price loses money",
            a6.Balance() < bal1 + 1e-9,
            DoubleToString(a6.Balance(), 2));
   }

   //================================================================
   PrintFormat("=== Phase 9: PASS=%d  FAIL=%d  ===> %s",
               g_pass, g_fail, (g_fail == 0 ? "GREEN" : "RED"));
  }
//+------------------------------------------------------------------+

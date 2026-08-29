//+------------------------------------------------------------------+
//|                                            SSR_T10_Statistics.mq5 |
//|                  SS Replay - Phase 10 Trade & Statistics Engine   |
//|                                                                   |
//|  WHAT THIS FILE IS ACTUALLY GUARDING                              |
//|                                                                   |
//|  Every metric here is a number a trader will use to decide        |
//|  whether a strategy works. Three ways that goes wrong, and one    |
//|  test each:                                                       |
//|                                                                   |
//|  1. R measured against the loss that HAPPENED instead of the risk |
//|     TAKEN. Every loss becomes exactly -1R and a trader with no    |
//|     discipline scores as one with perfect discipline. T10.4.      |
//|  2. R invented as zero for trades that never had a stop, then     |
//|     averaged in with everyone else's. T10.4, T10.6.               |
//|  3. Results that rest on a guessed tick order reported as though  |
//|     they were observed. T10.3, T10.6.                             |
//|                                                                   |
//|  The tests drive the observers directly rather than through the   |
//|  controller: statistics are arithmetic over a known set of        |
//|  trades, and a test that cannot state the expected profit factor  |
//|  to the cent is not testing the profit factor.                    |
//+------------------------------------------------------------------+
#property script_show_inputs

#include <SSReplay/Common/SSR_Types.mqh>
#include <SSReplay/Common/SSR_Time.mqh>
#include <SSReplay/Trading/SSR_TradingEngine.mqh>
#include <SSReplay/Trading/SSR_Statistics.mqh>
#include <SSReplay/Trading/SSR_Journal.mqh>

input datetime InpStart = D'2024.01.08 00:00';

int g_pass = 0, g_fail = 0;
void Check(const string n, const bool ok, const string d = "")
  { if(ok) { g_pass++; PrintFormat("  PASS  %s", n); }
    else   { g_fail++; PrintFormat("  FAIL  %s  %s", n, d); } }
void CheckEq(const string n, const long e, const long a)
  { Check(n, e == a, StringFormat("expected=%I64d actual=%I64d", e, a)); }
void CheckNear(const string n, const double e, const double a, const double tol)
  { Check(n, MathAbs(e - a) <= tol, StringFormat("expected=%.5f actual=%.5f", e, a)); }
void Section(const string t) { PrintFormat("--- %s", t); }

//--- millisecond clock the scenarios advance by hand
long g_msc = 0;

//+------------------------------------------------------------------+
//| Start a clean account and statistics engine on a known           |
//| instrument: 1 currency unit of price = 1 unit of money per lot,  |
//| no spread, no slippage, no commission unless a test asks.        |
//+------------------------------------------------------------------+
void Begin(CSSRTradingEngine &a, CSSRStatsEngine &s, const double balance = 10000.0)
  {
   SSRExecutionModel e;
   e.Init();
   e.use_real_spread = true;
   a.SetExecution(e);
   a.SetBalance(balance);

   g_msc = SSRToMsc(InpStart);
   a.OnSessionStart("TEST", 2, 0.01, g_msc);
   s.Attach(GetPointer(a));
   s.OnSessionStart("TEST", 2, 0.01, g_msc);

   //--- set AFTER OnSessionStart, which reconfigures risk from the
   //--- symbol. One price unit, one money unit, per lot.
   a.Risk().Configure(1.0, 1.0, 0.01, 100.0, 0.01, 2);
  }

//--- one tick at `price`, `step_sec` after the previous one
void Tick(CSSRTradingEngine &a, CSSRStatsEngine &s,
          const double price, const int step_sec = 60)
  {
   g_msc += (long)step_sec * SSR_MSC_PER_SEC;
   MqlTick t[];
   ArrayResize(t, 1);
   t[0].time        = SSRToTime(g_msc);
   t[0].time_msc    = g_msc;
   t[0].bid         = price;
   t[0].ask         = price;
   t[0].last        = price;
   t[0].volume      = 1;
   t[0].volume_real = 0.0;
   t[0].flags       = 0;
   a.OnTicks(t, 1);
   s.OnTicks(t, 1);
  }

//--- the bar the next ticks are supposed to have come from
void BarCtx(CSSRTradingEngine &a, const double o, const double h,
            const double l, const double c, const bool synthetic)
  {
   MqlRates r;
   r.time = SSRToTime(g_msc); r.open = o; r.high = h; r.low = l; r.close = c;
   r.tick_volume = 10; r.spread = 0; r.real_volume = 0;
   a.OnBarContext(r, synthetic);
  }

//--- open and immediately close at the same price: a breakeven trade,
//--- used only to move the denominator of a percentage
void Breakeven(CSSRTradingEngine &a)
  {
   long t = a.Open(SSR_ORDER_BUY, 1.0);
   a.Close(t);
  }

//+------------------------------------------------------------------+
void OnStart()
  {
   Print("=== SSR Phase 10 - Trade & Statistics Engine ===");

   //================================================================
   Section("T10.1  an empty account reports nothing, and says so");
   {
      CSSRTradingEngine a; CSSRStatsEngine s;
      Begin(a, s);

      SSRStatistics st;
      s.Compute(st);
      CheckEq("no trades",            0, st.trades);
      CheckNear("no profit factor",   0.0, st.profit_factor, 1e-9);
      CheckNear("no drawdown",        0.0, st.max_drawdown, 1e-9);
      Check("not trustworthy with nothing in it", !st.IsTrustworthy());
      Check("and the caveat says why",
            StringFind(st.Caveat(), "no closed trades") >= 0, st.Caveat());
   }

   //================================================================
   Section("T10.2  the arithmetic, against four trades computed by hand");
   {
      CSSRTradingEngine a; CSSRStatsEngine s;
      Begin(a, s);

      //--- A: BUY 1 @1000, stop 900. Dips to 980, runs to 1300, closed
      //---    by hand there.                   +300, risk 100, R = +3
      Tick(a, s, 1000.0);
      long ta = a.Open(SSR_ORDER_BUY, 1.0, 900.0);
      Tick(a, s,  980.0);
      Tick(a, s, 1300.0);
      a.Close(ta);

      //--- C: SELL 1 @1300, stop 1350. Ticks to 1320, then 1250.
      //---                                       +50, risk 50, R = +1
      long tc = a.Open(SSR_ORDER_SELL, 1.0, 1350.0);
      Tick(a, s, 1320.0);
      Tick(a, s, 1250.0);
      a.Close(tc);

      //--- B: BUY 1 @1250, stop 1100 (never hit). Falls to 1120, comes
      //---    back to 1150, closed by hand.
      //---                     -100, risk 150, R = -0.6667, NOT -1
      long tb = a.Open(SSR_ORDER_BUY, 1.0, 1100.0);
      Tick(a, s, 1120.0);
      Tick(a, s, 1150.0);
      a.Close(tb);

      //--- D: BUY 1 @1150, no stop, closed at once.  0, R undefined
      long td = a.Open(SSR_ORDER_BUY, 1.0);
      a.Close(td);

      SSRStatistics st;
      s.Compute(st);

      CheckEq("four closed trades", 4, st.trades);
      CheckEq("two wins",           2, st.wins);
      CheckEq("one loss",           1, st.losses);
      CheckEq("one breakeven",      1, st.breakeven);
      CheckEq("nothing left open",  0, st.open_now);

      CheckNear("gross profit",  350.0, st.gross_profit, 1e-6);
      CheckNear("gross loss",    100.0, st.gross_loss,   1e-6);
      CheckNear("net profit",    250.0, st.net_profit,   1e-6);
      CheckNear("win rate",       50.0, st.win_rate,     1e-6);
      CheckNear("loss rate",      25.0, st.loss_rate,    1e-6);
      CheckNear("profit factor",   3.5, st.profit_factor, 1e-6);
      CheckNear("expectancy",     62.5, st.expectancy,   1e-6);
      CheckNear("average win",   175.0, st.average_win,  1e-6);
      CheckNear("average loss",  100.0, st.average_loss, 1e-6);
      CheckNear("largest win",   300.0, st.largest_win,  1e-6);
      CheckNear("largest loss",  100.0, st.largest_loss, 1e-6);

      //--- a breakeven trade breaks neither streak and starts neither
      CheckEq("win streak",  2, st.win_streak);
      CheckEq("loss streak", 1, st.loss_streak);

      //--- THE POINT OF THIS SECTION. If R were measured against the
      //--- loss that happened, B would be exactly -1R. It is -0.667,
      //--- because the trader risked 150 to lose 100.
      CheckEq("R covers three of four trades", 3, st.r_trades);
      CheckEq("and names the one it cannot",   1, st.trades_without_stop);
      CheckNear("total R", 3.0 + 1.0 - 100.0 / 150.0, st.total_r, 1e-6);
      CheckNear("average R", (3.0 + 1.0 - 100.0 / 150.0) / 3.0, st.average_r, 1e-6);
      Check("the loser is not -1R",
            MathAbs(st.total_r - 3.0) > 1e-6,
            StringFormat("total_r=%.5f", st.total_r));

      //--- excursions, from the ticks each position actually saw
      CheckNear("average MAE", (-20.0 - 20.0 - 130.0 + 0.0) / 4.0, st.avg_mae, 1e-6);
      CheckNear("average MFE", (300.0 + 50.0 + 0.0 + 0.0) / 4.0,   st.avg_mfe, 1e-6);

      //--- drawdown: the balance curve never fell more than 100, but
      //--- the trader sat through 130 of floating loss on B. Reporting
      //--- only the closed figure understates what was survived.
      CheckNear("closed drawdown", 100.0, st.max_drawdown_closed, 1e-6);
      CheckNear("equity drawdown", 130.0, st.max_drawdown, 1e-6);
      Check("equity drawdown includes the floating loss",
            st.max_drawdown > st.max_drawdown_closed + 1e-9,
            StringFormat("eq=%.2f closed=%.2f",
                         st.max_drawdown, st.max_drawdown_closed));
      CheckNear("drawdown percent", 130.0 / 10350.0 * 100.0,
                st.max_drawdown_pct, 1e-6);

      CheckNear("balance ended where the trades put it",
                10250.0, a.Balance(), 1e-6);
      Check("equity samples were taken", s.EquitySamples() > 0,
            IntegerToString(s.EquitySamples()));
   }

   //================================================================
   Section("T10.3  an assumed outcome is counted, not quietly absorbed");
   {
      CSSRTradingEngine a; CSSRStatsEngine s;
      Begin(a, s);

      Tick(a, s, 1000.0);
      long t = a.Open(SSR_ORDER_BUY, 1.0, 990.0, 1010.0);

      //--- a synthesised bar whose range holds BOTH levels
      BarCtx(a, 1000.0, 1015.0, 985.0, 1012.0, true);
      Tick(a, s, 1012.0);                       // the tick reaches TP...

      SSRVirtualPosition p;
      a.ByTicket(t, p);
      Check("closed", p.IsClosed());
      CheckEq("...but the loss is taken, not the win",
              (long)SSR_CLOSE_SL, (long)p.reason);
      CheckNear("at the stop", 990.0, p.close_price, 1e-6);
      Check("and the trade is flagged as assumed", p.ambiguous);

      //--- three clean trades alongside it: 1 of 4 is 25%
      Breakeven(a); Breakeven(a); Breakeven(a);

      SSRStatistics st;
      s.Compute(st);
      CheckEq("one ambiguous trade", 1, st.ambiguous_trades);
      CheckNear("a quarter of the results", 25.0, st.ambiguous_pct, 1e-6);
      Check("a quarter is too much to quote unqualified", !st.IsTrustworthy());
      Check("and the caveat says what is assumed",
            StringFind(st.Caveat(), "assume") >= 0, st.Caveat());
      Check("the caveat also names the unmodelled margin",
            StringFind(st.Caveat(), "Margin is not modelled") >= 0, st.Caveat());

      //--- dilute it to 1 in 20 and the numbers can stand alone
      for(int i = 0; i < 16; i++)
         Breakeven(a);
      s.Compute(st);
      CheckEq("twenty trades now", 20, st.trades);
      CheckNear("one in twenty", 5.0, st.ambiguous_pct, 1e-6);
      Check("five percent is quotable", st.IsTrustworthy());
   }

   //================================================================
   Section("T10.3b  real ticks are never called ambiguous");
   {
      CSSRTradingEngine a; CSSRStatsEngine s;
      Begin(a, s);

      Tick(a, s, 1000.0);
      long t = a.Open(SSR_ORDER_BUY, 1.0, 990.0, 1010.0);

      //--- same bar, same range - but the ticks are real, so their
      //--- order is data and there is nothing to assume
      BarCtx(a, 1000.0, 1015.0, 985.0, 1012.0, false);
      Tick(a, s, 1012.0);

      SSRVirtualPosition p;
      a.ByTicket(t, p);
      CheckEq("the target that was actually reached is honoured",
              (long)SSR_CLOSE_TP, (long)p.reason);
      Check("not flagged", !p.ambiguous);
      CheckEq("nothing assumed", 0, (int)a.AmbiguousCount());
   }

   //================================================================
   Section("T10.4  R is undefined, never zero, never invented");
   {
      CSSRTradingEngine a; CSSRStatsEngine s;
      Begin(a, s);

      //--- a big winner taken with no stop at all
      Tick(a, s, 1000.0);
      long t1 = a.Open(SSR_ORDER_BUY, 1.0);
      Tick(a, s, 2000.0);
      a.Close(t1);                              // +1000, R undefined

      //--- a modest winner that risked 100 to make 100
      long t2 = a.Open(SSR_ORDER_BUY, 1.0, 1900.0);
      Tick(a, s, 2100.0);
      a.Close(t2);                              // +100, risk 100, R = +1

      SSRStatistics st;
      s.Compute(st);
      CheckEq("two trades",            2, st.trades);
      CheckEq("R exists for only one", 1, st.r_trades);
      CheckEq("the other is named",    1, st.trades_without_stop);

      //--- averaged over 2 it would be 0.5; treated as 10R it would be
      //--- 5.5. It is 1.0, over the one trade where R exists.
      CheckNear("average R is over the trades that have one",
                1.0, st.average_r, 1e-6);
      Check("the caveat says how many trades R covers",
            StringFind(st.Caveat(), "R covers 1 of 2") >= 0, st.Caveat());

      //--- profit factor with no losses at all is undefined, not
      //--- infinity and not the gross profit
      CheckNear("no profit factor without a loss", 0.0, st.profit_factor, 1e-9);
      CheckNear("net profit is still reported", 1100.0, st.net_profit, 1e-6);
   }

   //================================================================
   Section("T10.5  swap accrues per replay day, once, and unwinds");
   {
      CSSRTradingEngine a; CSSRStatsEngine s;
      SSRExecutionModel e;
      e.Init();
      e.swap_long_per_lot = -5.0;
      Begin(a, s);
      a.SetExecution(e);
      a.Risk().Configure(1.0, 1.0, 0.01, 100.0, 0.01, 2);

      Tick(a, s, 1000.0);
      double bal0 = a.Balance();
      long   t    = a.Open(SSR_ORDER_BUY, 1.0);

      //--- three replay days pass, in many ticks
      for(int d = 0; d < 3; d++)
         for(int k = 0; k < 4; k++)
            Tick(a, s, 1000.0, 6 * 3600);

      SSRVirtualPosition p;
      a.ByTicket(t, p);
      CheckNear("three days of swap, charged once each", -15.0, p.swap, 1e-6);
      CheckNear("and taken out of the balance exactly once",
                bal0 - 15.0, a.Balance(), 1e-6);

      //--- more ticks on the same day must not charge again
      Tick(a, s, 1000.0, 60);
      Tick(a, s, 1000.0, 60);
      a.ByTicket(t, p);
      CheckNear("idempotent within the day", -15.0, p.swap, 1e-6);

      //--- close it: the balance must move by the price result only,
      //--- because the swap is already in there
      double bal1 = a.Balance();
      a.Close(t);
      CheckNear("closing does not pay the swap a second time",
                bal1, a.Balance(), 1e-6);

      SSRStatistics st;
      s.Compute(st);
      CheckNear("swap reported", -15.0, st.swap, 1e-6);
      CheckNear("and counted against the trade", -15.0, st.net_profit, 1e-6);
      CheckEq("a swap-only loss is a loss", 1, st.losses);
   }

   //================================================================
   Section("T10.5b  a rewind refunds the days that did not happen");
   {
      CSSRTradingEngine a; CSSRStatsEngine s;
      SSRExecutionModel e;
      e.Init();
      e.swap_long_per_lot = -5.0;
      Begin(a, s);
      a.SetExecution(e);
      a.Risk().Configure(1.0, 1.0, 0.01, 100.0, 0.01, 2);

      Tick(a, s, 1000.0);
      double bal0 = a.Balance();
      long   open_msc = g_msc;
      long   t = a.Open(SSR_ORDER_BUY, 1.0);

      for(int d = 0; d < 4; d++)
         Tick(a, s, 1000.0, 86400);

      SSRVirtualPosition p;
      a.ByTicket(t, p);
      CheckNear("four days owed", -20.0, p.swap, 1e-6);

      //--- rewind to one day after the open
      a.OnRewind(open_msc + SSR_MSC_PER_DAY);
      s.OnRewind(open_msc + SSR_MSC_PER_DAY);
      g_msc = open_msc + SSR_MSC_PER_DAY;   // the clock rewinds too
      a.ByTicket(t, p);
      CheckNear("one day owed after the rewind", -5.0, p.swap, 1e-6);
      CheckNear("and the balance refunded the rest", bal0 - 5.0, a.Balance(), 1e-6);

      //--- and replaying the same days charges them once, not twice
      for(int d = 0; d < 3; d++)
         Tick(a, s, 1000.0, 86400);
      a.ByTicket(t, p);
      CheckNear("replaying does not double-charge", -20.0, p.swap, 1e-6);
      CheckNear("balance matches", bal0 - 20.0, a.Balance(), 1e-6);
   }

   //================================================================
   Section("T10.5c  a rewind does not leave a third commission behind");
   {
      CSSRTradingEngine a; CSSRStatsEngine s;
      SSRExecutionModel e;
      e.Init();
      e.commission_per_lot = 7.0;
      Begin(a, s);
      a.SetExecution(e);
      a.Risk().Configure(1.0, 1.0, 0.01, 100.0, 0.01, 2);

      Tick(a, s, 1000.0);
      long open_msc = g_msc;
      long t = a.Open(SSR_ORDER_BUY, 1.0);
      Tick(a, s, 1100.0);
      a.Close(t);

      SSRVirtualPosition p;
      a.ByTicket(t, p);
      CheckNear("two sides charged", 14.0, p.commission, 1e-6);

      a.OnRewind(open_msc + SSR_MSC_PER_MIN / 2);
      a.ByTicket(t, p);
      Check("reopened", p.IsOpen());
      CheckNear("back to one side", 7.0, p.commission, 1e-6);

      Tick(a, s, 1100.0);
      a.Close(t);
      a.ByTicket(t, p);
      CheckNear("and closing again charges the second, not a third",
                14.0, p.commission, 1e-6);
   }

   //================================================================
   Section("T10.6  margin and stop out are modelled, or declared absent");
   {
      CSSRTradingEngine a; CSSRStatsEngine s;
      Begin(a, s);

      SSRStatistics st;
      Tick(a, s, 1000.0);
      Breakeven(a);
      s.Compute(st);
      Check("margin not modelled by default", !st.margin_modelled);
      Check("and the caveat says so",
            StringFind(st.Caveat(), "Margin is not modelled") >= 0, st.Caveat());
      CheckNear("no margin level to report", 0.0, a.MarginLevel(), 1e-9);

      //--- now declare it: 1000 per lot, stop out at 50%
      a.SetMarginPerLot(1000.0);
      a.SetStopoutLevel(50.0);
      Check("modelled once declared", a.MarginModelled());

      long t = a.Open(SSR_ORDER_BUY, 10.0);       // uses the whole account
      CheckNear("used margin",  10000.0, a.UsedMargin(), 1e-6);
      CheckNear("margin level", 100.0,   a.MarginLevel(), 1e-6);
      CheckNear("free margin",  0.0,     a.FreeMargin(), 1e-6);

      Tick(a, s, 940.0);                          // -600 floating, 94%
      CheckNear("level falls with equity", 94.0, a.MarginLevel(), 1e-6);
      CheckEq("not yet a stop out", 1, a.OpenCount());

      Tick(a, s, 500.0);                          // -5000 floating, 50%
      CheckEq("stopped out", 0, a.OpenCount());

      SSRVirtualPosition p;
      a.ByTicket(t, p);
      CheckEq("and the reason is recorded",
              (long)SSR_CLOSE_STOPOUT, (long)p.reason);

      s.Compute(st);
      CheckEq("counted", 1, st.stopouts);
      Check("margin now modelled", st.margin_modelled);
      Check("so the caveat drops that line",
            StringFind(st.Caveat(), "Margin is not modelled") < 0, st.Caveat());
   }

   //================================================================
   Section("T10.7  the equity curve honours a rewind");
   {
      CSSRTradingEngine a; CSSRStatsEngine s;
      Begin(a, s);

      Tick(a, s, 1000.0);
      long cut = g_msc;
      for(int i = 0; i < 10; i++)
         Tick(a, s, 1000.0 + i);

      int before = s.EquitySamples();
      Check("samples accumulated", before >= 10, IntegerToString(before));

      s.OnRewind(cut);
      int after = s.EquitySamples();
      Check("the deleted future is dropped from the curve",
            after < before && after >= 1,
            StringFormat("before=%d after=%d", before, after));

      //--- and a sample taken right after the cut is accepted rather
      //--- than swallowed by a stale interval guard
      g_msc = cut;
      Tick(a, s, 1000.0);
      CheckEq("sampling resumes from the cut", after + 1, s.EquitySamples());
   }

   //================================================================
   Section("T10.8  the journal carries the caveat into the file");
   {
      CSSRTradingEngine a; CSSRStatsEngine s; CSSRJournal j;
      Begin(a, s);
      j.Attach(GetPointer(a), GetPointer(s));

      //--- one ambiguous loser, one clean winner with a stop, one
      //--- winner with no stop at all
      Tick(a, s, 1000.0);
      long t1 = a.Open(SSR_ORDER_BUY, 1.0, 990.0, 1010.0, 0.0, "amb");
      BarCtx(a, 1000.0, 1015.0, 985.0, 1012.0, true);
      Tick(a, s, 1012.0);
      Check("the ambiguous trade closed", a.ClosedCount() == 1 && t1 > 0);

      long t2 = a.Open(SSR_ORDER_BUY, 1.0, 900.0, 0.0, 0.0, "with stop");
      Tick(a, s, 1100.0);
      a.Close(t2);

      long t3 = a.Open(SSR_ORDER_BUY, 1.0, 0.0, 0.0, 0.0, "no stop");
      Tick(a, s, 1200.0);
      a.Close(t3);

      CheckEq("three closed trades", 3, j.Count());
      Check("export succeeded", j.ExportCsv("t10", 2), j.LastError());

      //--- read it back and check the three things that matter
      int h = FileOpen(j.LastPath(), FILE_READ | FILE_TXT | FILE_ANSI);
      Check("file exists", h != INVALID_HANDLE, j.LastPath());
      if(h != INVALID_HANDLE)
        {
         bool   caveat_line = false, header_line = false;
         int    rows = 0, assumed = 0, observed = 0, empty_r = 0, zero_r = 0;
         string r_of_t3 = "?";

         while(!FileIsEnding(h))
           {
            string line = FileReadString(h);
            if(StringLen(line) == 0)
               continue;
            if(StringGetCharacter(line, 0) == StringGetCharacter("#", 0))
              {
               if(StringFind(line, "# CAVEAT") == 0)
                  caveat_line = true;
               continue;
              }
            if(StringFind(line, "ticket,type,tag") == 0)
              { header_line = true; continue; }

            rows++;
            string f[];
            int n = StringSplit(line, StringGetCharacter(",", 0), f);
            if(n < 17)              // a trailing empty note may or
               continue;            // may not survive the split

            if(f[16] == "ASSUMED")  assumed++;
            if(f[16] == "observed") observed++;
            if(f[12] == "")         empty_r++;
            if(f[12] == "0.000")    zero_r++;
            if(f[2] == "no stop")   r_of_t3 = f[12];
           }
         FileClose(h);

         Check("the header row is there", header_line);
         CheckEq("one row per closed trade", 3, rows);

         //--- THE POINT OF THIS SECTION. A spreadsheet is exactly where
         //--- a caveat gets lost, so it travels inside the file.
         Check("the caveat is written into the file", caveat_line);

         CheckEq("the assumed trade is labelled",  1, assumed);
         CheckEq("the observed ones are too",      2, observed);

         //--- an empty R, never a zero: a zero would be averaged in by
         //--- whatever opens this next
         CheckEq("R is left empty where it does not exist", 1, empty_r);
         CheckEq("and never written as zero",               0, zero_r);
         Check("specifically for the trade taken without a stop",
               r_of_t3 == "", "r='" + r_of_t3 + "'");
        }

      //--- and the panel summary says it too
      string sum = j.Summary();
      Check("the summary carries the caveat",
            StringFind(sum, "assume") >= 0, sum);
   }

   //================================================================
   Section("T10.9  a rewind undoes exits, fills and cancellations");
   {
      //--- SCALING OUT. Before the leg ledger this was the quiet one:
      //--- the rewind restored the close but kept the partial exit, so
      //--- the trader came back holding half a position they had not
      //--- yet decided to take off, with its profit already banked.
      CSSRTradingEngine a; CSSRStatsEngine s;
      Begin(a, s);

      Tick(a, s, 1000.0);
      long cut = g_msc;
      long t   = a.Open(SSR_ORDER_BUY, 2.0);

      Tick(a, s, 1100.0);
      Check("scaled out of half", a.ClosePartial(t, 1.0), a.LastError());
      Tick(a, s, 1200.0);
      a.Close(t);

      SSRVirtualPosition p;
      a.ByTicket(t, p);
      CheckNear("both exits booked",  300.0,   p.profit,    1e-6);
      CheckNear("balance reflects it", 10300.0, a.Balance(), 1e-6);

      a.OnRewind(cut);
      a.ByTicket(t, p);
      Check("open again", p.IsOpen());
      CheckNear("at the size it actually had", 2.0, p.volume, 1e-9);
      CheckNear("with nothing booked",         0.0, p.profit, 1e-6);
      CheckNear("and the money given back", 10000.0, a.Balance(), 1e-6);
      CheckEq("one position open", 1, a.OpenCount());
      CheckEq("and none closed",   0, a.ClosedCount());
   }
   {
      //--- A PENDING ORDER FILLED IN THE DELETED FUTURE has to become
      //--- an order again, at the price and type it was placed with -
      //--- both of which the fill overwrote.
      CSSRTradingEngine a; CSSRStatsEngine s;
      Begin(a, s);

      Tick(a, s, 1000.0);
      long cut = g_msc;
      long t   = a.Open(SSR_ORDER_BUY_STOP, 1.0, 0.0, 0.0, 1050.0, "stop entry");
      Check("placed", t > 0, a.LastError());
      CheckEq("pending", 1, a.PendingCount());

      Tick(a, s, 1060.0);
      CheckEq("filled",           1, a.OpenCount());
      CheckEq("no longer pending", 0, a.PendingCount());

      a.OnRewind(cut);
      SSRVirtualPosition p;
      a.ByTicket(t, p);
      CheckEq("pending again",     1, a.PendingCount());
      CheckEq("and not open",      0, a.OpenCount());
      CheckEq("as the type it was placed with",
              (long)SSR_ORDER_BUY_STOP, (long)p.type);
      CheckNear("at the price it was placed at", 1050.0, p.request_price, 1e-6);
      CheckNear("with no fill price",            0.0,    p.open_price,    1e-6);

      //--- and it fills again when price gets there a second time
      Tick(a, s, 1060.0);
      CheckEq("fills again on the replay", 1, a.OpenCount());
   }
   {
      //--- A CANCELLATION IS AN EVENT WITH A TIME, so a rewind past it
      //--- puts the order back on the book.
      CSSRTradingEngine a; CSSRStatsEngine s;
      Begin(a, s);

      Tick(a, s, 1000.0);
      long cut = g_msc;
      long t   = a.Open(SSR_ORDER_BUY_LIMIT, 1.0, 0.0, 0.0, 900.0);
      Tick(a, s, 1000.0);
      a.Close(t);
      CheckEq("cancelled", 0, a.PendingCount());

      a.OnRewind(cut);
      CheckEq("on the book again", 1, a.PendingCount());
   }
   {
      //--- AND AN ORDER PLACED AFTER THE CUT SIMPLY NEVER EXISTED
      CSSRTradingEngine a; CSSRStatsEngine s;
      Begin(a, s);

      Tick(a, s, 1000.0);
      long cut = g_msc;
      Tick(a, s, 1000.0);
      a.Open(SSR_ORDER_BUY, 1.0);
      CheckEq("one position", 1, a.Total());

      a.OnRewind(cut);
      CheckEq("erased outright", 0, a.Total());
   }
   {
      //--- THE LEDGER HAS A CEILING, and the honest response to
      //--- reaching it is to refuse the exit - not to take one that a
      //--- rewind could never undo. The final close keeps its slot.
      CSSRTradingEngine a; CSSRStatsEngine s;
      Begin(a, s);

      Tick(a, s, 1000.0);
      long t = a.Open(SSR_ORDER_BUY, 10.0);
      int  taken = 0;
      for(int i = 0; i < 10; i++)
         if(a.ClosePartial(t, 1.0))
            taken++;

      CheckEq("scaled out up to the ceiling", SSR_MAX_TRADE_LEGS - 1, taken);
      Check("and said why it stopped",
            StringFind(a.LastError(), "too many") >= 0, a.LastError());

      //--- the close is never refused
      Check("closing still works", a.Close(t), a.LastError());
      CheckEq("nothing left open", 0, a.OpenCount());
   }

   //================================================================
   PrintFormat("=== Phase 10: PASS=%d  FAIL=%d  ===> %s",
               g_pass, g_fail, (g_fail == 0 ? "GREEN" : "RED"));
  }
//+------------------------------------------------------------------+

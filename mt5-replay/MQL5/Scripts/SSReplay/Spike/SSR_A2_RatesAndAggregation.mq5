//+------------------------------------------------------------------+
//|                                   SSR_A2_RatesAndAggregation.mq5 |
//|  SPIKE A2 - CustomRatesUpdate & Native Timeframe Aggregation     |
//|  TIER A - BLOCKER  (the single most important test in Phase 0)   |
//|                                                                  |
//|  Hypothesis: if we write ONLY M1, MetaTrader builds M5/M15/M30/  |
//|  H1/H4 itself, and builds them CORRECTLY.                        |
//|                                                                  |
//|  PASS: M1 read-back bit-exact, and zero OHLC mismatches on every |
//|        higher timeframe against an independent aggregation.      |
//|  FAIL: even one mismatch. Tolerance is zero by design - this     |
//|        test exists to catch the subtle aggregation bug.          |
//+------------------------------------------------------------------+
#property script_show_inputs

#include <SSReplay/Spike/SSR_SpikeKit.mqh>

input string   InpOrigin    = "US30Cash";           // Origin symbol
input string   InpTest      = "SSRA2";              // Test symbol
input datetime InpStart     = D'2024.01.08 00:00';  // Golden dataset start (a Monday)
input int      InpBars      = 4320;                 // M1 bars (4320 = 3 days)
input double   InpBase      = 38000.0;              // Base price
input bool     InpTestNonM1 = true;                 // Also probe writing non-M1 rates

//+------------------------------------------------------------------+
void CheckTimeframe(const string sym, const MqlRates &m1[], const ENUM_TIMEFRAMES tf,
                    const string tfname, const int digits)
  {
   //--- our independent reference aggregation
   MqlRates ref[];
   int nref = SSR_AggregateM1(m1, tf, ref);
   if(nref <= 2)
     {
      SSR_Metric("agg_" + tfname, "reference_bars", (double)nref, "count", "too few bars to judge");
      return;
     }

   //--- what the terminal built by itself
   double wait_ms = SSR_WaitSeries(sym, tf, 15000);
   SSR_Metric("agg_" + tfname, "series_build_wait", wait_ms, "ms");

   MqlRates got[];
   ArraySetAsSeries(got, false);
   int ngot = CopyRates(sym, tf, ref[0].time, ref[nref - 1].time, got);
   if(ngot <= 0)
     {
      SSR_Verdict("agg_" + tfname + "_readable", false, ">0 bars",
                  IntegerToString(ngot), "err=" + IntegerToString(GetLastError()));
      return;
     }

   SSR_Metric("agg_" + tfname, "reference_bars", (double)nref, "count");
   SSR_Metric("agg_" + tfname, "terminal_bars",  (double)ngot, "count");

   //--- the LAST bar is legitimately still forming, so compare all but the last
   int compare_n = MathMin(nref, ngot) - 1;
   if(compare_n < 1)
     {
      SSR_Verdict("agg_" + tfname + "_count", false, ">1 comparable bar",
                  IntegerToString(compare_n), "");
      return;
     }

   MqlRates a[], b[];
   ArrayResize(a, compare_n);
   ArrayResize(b, compare_n);
   for(int i = 0; i < compare_n; i++)
     {
      a[i] = ref[i];
      b[i] = got[i];
     }

   int vol_bad = 0;
   string detail = "";
   int bad = SSR_CompareRates(a, b, digits, vol_bad, detail);

   SSR_Metric("agg_" + tfname, "bars_compared",    (double)compare_n, "count");
   SSR_Metric("agg_" + tfname, "ohlc_mismatch",    (double)bad,       "count");
   SSR_Metric("agg_" + tfname, "volume_mismatch",  (double)vol_bad,   "count");

   SSR_Verdict("agg_" + tfname + "_ohlc_exact", bad == 0, "0 mismatches",
               IntegerToString(bad), detail);
   //--- volume is reported but not a blocker: a volume-only diff must not
   //--- mask or be masked by a price diff
   SSR_Verdict("agg_" + tfname + "_volume_exact", vol_bad == 0, "0 mismatches",
               IntegerToString(vol_bad), "informational, not a blocker");
  }

//+------------------------------------------------------------------+
void OnStart()
  {
   SSR_Begin("A2_RatesAndAggregation");

   if(!SymbolSelect(InpOrigin, true))
     {
      SSR_Verdict("origin_available", false, "selectable", "failed", InpOrigin);
      SSR_End();
      return;
     }

   if(!SSR_MakeSymbol(InpTest, InpOrigin))
     {
      SSR_Verdict("symbol_ready", false, "created", "failed", "");
      SSR_End();
      return;
     }
   SSR_Verdict("symbol_ready", true, "created", "ok", InpTest);

   int    digits = (int)SymbolInfoInteger(InpTest, SYMBOL_DIGITS);
   double point  = SymbolInfoDouble(InpTest, SYMBOL_POINT);
   if(point <= 0.0) point = MathPow(10, -digits);

   //--- 1. build the golden dataset (deterministic, broker independent)
   MqlRates m1[];
   ulong t0 = SSR_Now();
   int n = SSR_GenM1(m1, InpStart, InpBars, InpBase, point, digits);
   SSR_Metric("golden", "generate", SSR_ElapsedMs(t0), "ms", "seed=20260829");
   SSR_Metric("golden", "bars_generated", (double)n, "count");

   //--- 2. write it
   t0 = SSR_Now();
   ResetLastError();
   int written = CustomRatesUpdate(InpTest, m1);
   double t_write = SSR_ElapsedMs(t0);
   int err_write = GetLastError();

   SSR_Metric("write_m1", "elapsed",   t_write, "ms");
   SSR_Metric("write_m1", "bars_written", (double)written, "count");
   SSR_Metric("write_m1", "bars_per_sec", (t_write > 0 ? (double)written / (t_write / 1000.0) : 0), "bars/s");
   SSR_Verdict("rates_written", written == n, IntegerToString(n),
               IntegerToString(written), "err=" + IntegerToString(err_write));

   //--- force the terminal to build the series
   SymbolSelect(InpTest, true);
   double wait_m1 = SSR_WaitSeries(InpTest, PERIOD_M1, 20000);
   SSR_Metric("write_m1", "series_sync_wait", wait_m1, "ms");

   //--- 3. M1 must come back bit-exact
   MqlRates back[];
   ArraySetAsSeries(back, false);
   t0 = SSR_Now();
   int nback = CopyRates(InpTest, PERIOD_M1, m1[0].time, m1[n - 1].time, back);
   SSR_Metric("readback_m1", "elapsed", SSR_ElapsedMs(t0), "ms");
   SSR_Metric("readback_m1", "bars_read", (double)nback, "count");

   if(nback > 0)
     {
      int cmp_n = MathMin(n, nback);
      MqlRates a[], b[];
      ArrayResize(a, cmp_n);
      ArrayResize(b, cmp_n);
      for(int i = 0; i < cmp_n; i++) { a[i] = m1[i]; b[i] = back[i]; }

      int vol_bad = 0;
      string detail = "";
      int bad = SSR_CompareRates(a, b, digits, vol_bad, detail);

      SSR_Metric("readback_m1", "ohlc_mismatch",   (double)bad,     "count");
      SSR_Metric("readback_m1", "volume_mismatch", (double)vol_bad, "count");
      SSR_Verdict("m1_bit_exact", bad == 0, "0 mismatches", IntegerToString(bad), detail);
     }
   else
      SSR_Verdict("m1_bit_exact", false, ">0 bars read", IntegerToString(nback),
                  "err=" + IntegerToString(GetLastError()));

   //--- 4. THE CORE CLAIM: does the terminal aggregate correctly?
   CheckTimeframe(InpTest, m1, PERIOD_M5,  "M5",  digits);
   CheckTimeframe(InpTest, m1, PERIOD_M15, "M15", digits);
   CheckTimeframe(InpTest, m1, PERIOD_M30, "M30", digits);
   CheckTimeframe(InpTest, m1, PERIOD_H1,  "H1",  digits);
   CheckTimeframe(InpTest, m1, PERIOD_H4,  "H4",  digits);

   //--- D1 is informational only: real terminals may key D1 to the trading day
   //--- rather than to UTC midnight, so a mismatch here is not a blocker.
   {
      MqlRates refd[];
      int nrefd = SSR_AggregateM1(m1, PERIOD_D1, refd);
      MqlRates gotd[];
      ArraySetAsSeries(gotd, false);
      int ngotd = CopyRates(InpTest, PERIOD_D1, InpStart, InpStart + InpBars * 60, gotd);
      SSR_Metric("agg_D1", "reference_bars", (double)nrefd, "count", "informational only");
      SSR_Metric("agg_D1", "terminal_bars",  (double)ngotd, "count", "informational only");
   }

   //--- 5. what happens if we write NON-M1 rates? Document the behaviour.
   if(InpTestNonM1)
     {
      string sym2 = InpTest + "N";
      if(SSR_MakeSymbol(sym2, InpOrigin))
        {
         MqlRates m5[];
         int n5 = SSR_AggregateM1(m1, PERIOD_M5, m5);

         ResetLastError();
         int w5 = CustomRatesUpdate(sym2, m5);
         int e5 = GetLastError();
         SymbolSelect(sym2, true);
         SSR_WaitSeries(sym2, PERIOD_M1, 10000);

         int bars_m1 = Bars(sym2, PERIOD_M1);
         int bars_m5 = Bars(sym2, PERIOD_M5);

         SSR_Metric("nonM1", "m5_bars_sent",      (double)n5,      "count");
         SSR_Metric("nonM1", "update_return",     (double)w5,      "count", "err=" + IntegerToString(e5));
         SSR_Metric("nonM1", "resulting_M1_bars", (double)bars_m1, "count");
         SSR_Metric("nonM1", "resulting_M5_bars", (double)bars_m5, "count");
         SSR_Verdict("nonM1_behaviour_documented", true, "recorded",
                     StringFormat("sent=%d ret=%d m1=%d m5=%d", n5, w5, bars_m1, bars_m5),
                     "confirms whether M1 really is the only storage base");
         SSR_DropSymbol(sym2);
        }
     }

   SSR_DropSymbol(InpTest);
   SSR_End();
  }
//+------------------------------------------------------------------+

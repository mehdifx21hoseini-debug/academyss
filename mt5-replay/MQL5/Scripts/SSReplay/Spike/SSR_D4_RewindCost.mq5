//+------------------------------------------------------------------+
//|                                           SSR_D4_RewindCost.mq5  |
//|  SPIKE D4 - Rewind Cost                                          |
//|  TIER D - MEDIUM                                                 |
//|                                                                  |
//|  Decides whether "Previous Candle" can be an interactive button  |
//|  or has to become an explicit "Rewind to point" operation.       |
//|                                                                  |
//|  Compares three strategies at a realistic seed depth, with and   |
//|  without indicators on the chart, because indicator recalc is    |
//|  the cost that is easy to forget and impossible to ignore.       |
//|                                                                  |
//|  Attach MA, RSI and Bollinger to the test chart before running   |
//|  the indicators pass.                                            |
//+------------------------------------------------------------------+
#property script_show_inputs

#include <SSReplay/Spike/SSR_SpikeKit.mqh>

input string   InpOrigin = "";                 // Origin symbol (blank = this chart's symbol)

input string   InpTest   = "SSRD4";              // Test symbol
input datetime InpStart  = D'2023.01.02 00:00';  // Seed start
input double   InpBase   = 34000.0;              // Base price
input int      InpDepth  = 100000;               // Seed depth (M1 bars)
input int      InpTrials = 20;                   // Trials per strategy
input bool     InpOpenChart = true;              // Open a chart during the test

string g_origin = "";   //--- resolved from InpOrigin at the top of OnStart

//+------------------------------------------------------------------+
void Seed(const MqlRates &m1[], const int count)
  {
   for(int off = 0; off < count; off += 10000)
     {
      int cnt = MathMin(10000, count - off);
      MqlRates part[];
      ArrayResize(part, cnt);
      for(int i = 0; i < cnt; i++) part[i] = m1[off + i];
      CustomRatesUpdate(InpTest, part);
     }
  }

//+------------------------------------------------------------------+
void OnStart()
  {
   SSR_Begin("D4_RewindCost");

   g_origin = SSR_Origin(InpOrigin);
   if(!SSR_MakeSymbol(InpTest, g_origin))
     {
      SSR_Verdict("symbol_ready", false, "created", "failed", "");
      SSR_End();
      return;
     }

   int    digits = (int)SymbolInfoInteger(InpTest, SYMBOL_DIGITS);
   double point  = SymbolInfoDouble(InpTest, SYMBOL_POINT);
   if(point <= 0.0) point = MathPow(10, -digits);

   MqlRates m1[];
   SSR_GenM1(m1, InpStart, InpDepth, InpBase, point, digits);

   ulong t0 = SSR_Now();
   Seed(m1, InpDepth);
   SymbolSelect(InpTest, true);
   SSR_WaitSeries(InpTest, PERIOD_M1, 60000);
   double t_full_seed = SSR_ElapsedMs(t0);
   SSR_Metric("baseline", "full_seed_time", t_full_seed, "ms",
              StringFormat("%d bars", InpDepth));

   long cid = 0;
   if(InpOpenChart)
     {
      cid = ChartOpen(InpTest, PERIOD_M5);
      Sleep(2000);
      SSR_Metric("baseline", "indicators_on_chart",
                 (double)ChartIndicatorsTotal(cid, 0), "count",
                 "attach MA/RSI/Bollinger manually for the loaded pass");
     }

   //--- strategy 1: delete the tail of a single bar
   double sum1 = 0, worst1 = 0;
   for(int i = 0; i < InpTrials; i++)
     {
      datetime cut = m1[InpDepth - 1 - i].time;
      ulong t = SSR_Now();
      CustomRatesDelete(InpTest, cut, D'2038.01.01 00:00');
      CustomTicksDelete(InpTest, (long)cut * 1000, LONG_MAX);
      SSR_WaitSeries(InpTest, PERIOD_M5, 15000);
      double e = SSR_ElapsedMs(t);
      sum1 += e;
      if(e > worst1) worst1 = e;
     }
   SSR_Metric("tail_1bar", "avg",   sum1 / InpTrials, "ms");
   SSR_Metric("tail_1bar", "worst", worst1,           "ms");

   //--- restore, then strategy 2: delete a 100-bar tail
   SSR_DropSymbol(InpTest);
   SSR_MakeSymbol(InpTest, g_origin);
   Seed(m1, InpDepth);
   SymbolSelect(InpTest, true);
   SSR_WaitSeries(InpTest, PERIOD_M1, 60000);

   double sum2 = 0, worst2 = 0;
   int trials2 = MathMax(1, InpTrials / 2);
   for(int i = 0; i < trials2; i++)
     {
      datetime cut = m1[InpDepth - 1 - (i + 1) * 100].time;
      ulong t = SSR_Now();
      CustomRatesDelete(InpTest, cut, D'2038.01.01 00:00');
      CustomTicksDelete(InpTest, (long)cut * 1000, LONG_MAX);
      SSR_WaitSeries(InpTest, PERIOD_M5, 15000);
      double e = SSR_ElapsedMs(t);
      sum2 += e;
      if(e > worst2) worst2 = e;
     }
   SSR_Metric("tail_100bar", "avg",   sum2 / trials2, "ms");
   SSR_Metric("tail_100bar", "worst", worst2,         "ms");

   //--- strategy 3: full rebuild, the pessimistic fallback
   double sum3 = 0;
   int trials3 = 3;
   for(int i = 0; i < trials3; i++)
     {
      ulong t = SSR_Now();
      SSR_DropSymbol(InpTest);
      SSR_MakeSymbol(InpTest, g_origin);
      Seed(m1, InpDepth - 1 - i);
      SymbolSelect(InpTest, true);
      SSR_WaitSeries(InpTest, PERIOD_M1, 60000);
      sum3 += SSR_ElapsedMs(t);
     }
   double avg3 = sum3 / trials3;
   SSR_Metric("full_rebuild", "avg", avg3, "ms");

   double avg1  = sum1 / InpTrials;
   double ratio = (avg1 > 0 ? avg3 / avg1 : 0);
   SSR_Metric("comparison", "rebuild_over_tail_ratio", ratio, "x",
              "how much cheaper the tail delete is");

   SSR_Verdict("step_back_interactive", avg1 <= 500.0, "<=500ms",
               StringFormat("%.0fms", avg1),
               "gate for Previous Candle as a real button");
   SSR_Verdict("step_back_usable", avg1 <= 3000.0, "<=3000ms",
               StringFormat("%.0fms", avg1),
               "above this it becomes Rewind-to-point with a progress bar");
   SSR_Verdict("tail_beats_rebuild", ratio >= 5.0, ">=5x",
               StringFormat("%.1fx", ratio), "");

   if(cid != 0) ChartClose(cid);
   Sleep(500);
   SSR_DropSymbol(InpTest);
   SSR_End();
  }
//+------------------------------------------------------------------+

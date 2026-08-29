//+------------------------------------------------------------------+
//|                                      SSR_D1_SeedPerformance.mq5  |
//|  SPIKE D1 - Large History Seed Performance                       |
//|  TIER D - MEDIUM                                                 |
//|                                                                  |
//|  The heaviest operation in the product. 200 D1 candles need      |
//|  288,000 M1 bars behind them, so seed cost decides how deep a    |
//|  user's higher-timeframe context can go.                         |
//|                                                                  |
//|  Also finds the optimal chunk size to lock into HistoryLoader.   |
//|  Run SSR_Probe_UIJitter on another chart: a seed that blocks     |
//|  the terminal for 10s is a failure even if it is "fast".         |
//+------------------------------------------------------------------+
#property script_show_inputs

#include <SSReplay/Spike/SSR_SpikeKit.mqh>

input string   InpOrigin = "US30Cash";           // Origin symbol
input string   InpTest   = "SSRD1";              // Test symbol
input datetime InpStart  = D'2020.01.06 00:00';  // Seed start
input double   InpBase   = 30000.0;              // Base price
input bool     InpBig    = false;                // Include 250k and 500k cases

int g_sizes[5]  = {10000, 50000, 100000, 250000, 500000};
int g_chunks[5] = {1000, 5000, 10000, 50000, 0};   // 0 = single call

//+------------------------------------------------------------------+
void SeedCase(const int total, const int chunk, const int digits, const double point)
  {
   if(!SSR_MakeSymbol(InpTest, InpOrigin))
      return;

   MqlRates m1[];
   ulong tg = SSR_Now();
   SSR_GenM1(m1, InpStart, total, InpBase, point, digits);
   double t_gen = SSR_ElapsedMs(tg);

   long mem0 = SSR_MemTerminal();
   int  step = (chunk <= 0 ? total : chunk);

   ulong t0 = SSR_Now();
   int written = 0;
   for(int off = 0; off < total; off += step)
     {
      int cnt = MathMin(step, total - off);
      MqlRates part[];
      ArrayResize(part, cnt);
      for(int i = 0; i < cnt; i++)
         part[i] = m1[off + i];
      int w = CustomRatesUpdate(InpTest, part);
      if(w > 0) written += w;
     }
   double t_write = SSR_ElapsedMs(t0);

   SymbolSelect(InpTest, true);
   double t_sync = SSR_WaitSeries(InpTest, PERIOD_M1, 60000);

   string c = StringFormat("seed_%dk_chunk%d", total / 1000, (chunk <= 0 ? total : chunk));
   SSR_Metric(c, "bars_target",   (double)total,   "count");
   SSR_Metric(c, "bars_written",  (double)written, "count");
   SSR_Metric(c, "generate_time", t_gen,           "ms");
   SSR_Metric(c, "write_time",    t_write,         "ms");
   SSR_Metric(c, "sync_wait",     t_sync,          "ms");
   SSR_Metric(c, "total_time",    (t_write + MathMax(t_sync, 0)) / 1000.0, "s");
   SSR_Metric(c, "bars_per_sec",  (t_write > 0 ? total / (t_write / 1000.0) : 0), "bars/s");
   SSR_Metric(c, "mem_terminal_delta", (double)(SSR_MemTerminal() - mem0), "MB");

   //--- how many higher-timeframe candles did this depth actually buy?
   SSR_Metric(c, "resulting_H1_bars", (double)Bars(InpTest, PERIOD_H1), "count");
   SSR_Metric(c, "resulting_H4_bars", (double)Bars(InpTest, PERIOD_H4), "count");
   SSR_Metric(c, "resulting_D1_bars", (double)Bars(InpTest, PERIOD_D1), "count");

   PrintFormat("[D1] %-24s write=%8.0fms sync=%6.0fms %9.0f bars/s  D1=%d",
               c, t_write, t_sync,
               (t_write > 0 ? total / (t_write / 1000.0) : 0),
               Bars(InpTest, PERIOD_D1));

   SSR_DropSymbol(InpTest);
   Sleep(300);
  }

//+------------------------------------------------------------------+
void OnStart()
  {
   SSR_Begin("D1_SeedPerformance");

   if(!SSR_MakeSymbol(InpTest, InpOrigin))
     {
      SSR_Verdict("symbol_ready", false, "created", "failed", "");
      SSR_End();
      return;
     }
   int    digits = (int)SymbolInfoInteger(InpTest, SYMBOL_DIGITS);
   double point  = SymbolInfoDouble(InpTest, SYMBOL_POINT);
   if(point <= 0.0) point = MathPow(10, -digits);
   SSR_DropSymbol(InpTest);

   //--- 1. chunk-size sweep at a fixed depth
   for(int ci = 0; ci < 5; ci++)
      SeedCase(100000, g_chunks[ci], digits, point);

   //--- 2. depth sweep at a reasonable chunk size
   int nsizes = (InpBig ? 5 : 3);
   for(int si = 0; si < nsizes; si++)
      SeedCase(g_sizes[si], 10000, digits, point);

   Print("[D1] PASS gate: 100k bars in <= 20s, 500k in <= 120s,");
   Print("[D1] and ui_jitter_p95 <= 500ms from the UIJitter probe.");
   Print("[D1] Record bases\\Custom folder size manually before and after.");

   SSR_End();
  }
//+------------------------------------------------------------------+

//+------------------------------------------------------------------+
//|                                        SSR_B2_TickThroughput.mq5 |
//|  SPIKE B2 - Tick Injection Throughput                            |
//|  TIER B - CRITICAL                                               |
//|                                                                  |
//|  This test produces the number that fills in the whole Adaptive  |
//|  Fidelity table: how many ticks per second can we actually push, |
//|  and how does that collapse as charts and indicators are added?  |
//|                                                                  |
//|  Run SSR_Probe_UIJitter on a SEPARATE chart at the same time.    |
//|  Throughput without a responsiveness number is meaningless -     |
//|  a terminal can accept ticks fast while being frozen to a user.  |
//+------------------------------------------------------------------+
#property script_show_inputs

#include <SSReplay/Spike/SSR_SpikeKit.mqh>

input string   InpOrigin    = "US30Cash";           // Origin symbol
input string   InpTest      = "SSRB2";              // Test symbol
input datetime InpStart     = D'2024.01.08 00:00';  // Start time
input double   InpBase      = 38000.0;              // Base price
input int      InpCharts    = 1;                    // Charts to open (0,1,4)
input int      InpTotalTicks = 200000;              // Ticks per batch-size case
input string   InpLabel     = "charts1_ind0";       // Label for the results rows

int g_batch[6] = {100, 500, 1000, 5000, 10000, 50000};

//+------------------------------------------------------------------+
long OpenCharts(const string sym, const int howmany, long &ids[])
  {
   ArrayResize(ids, 0);
   ENUM_TIMEFRAMES tfs[4] = {PERIOD_M1, PERIOD_M5, PERIOD_M15, PERIOD_H1};
   int n = MathMin(howmany, 4);
   for(int i = 0; i < n; i++)
     {
      long id = ChartOpen(sym, tfs[i]);
      if(id != 0)
        {
         int k = ArraySize(ids);
         ArrayResize(ids, k + 1);
         ids[k] = id;
        }
      Sleep(300);
     }
   return ArraySize(ids);
  }

//+------------------------------------------------------------------+
void OnStart()
  {
   SSR_Begin("B2_TickThroughput");

   if(!SSR_MakeSymbol(InpTest, InpOrigin))
     {
      SSR_Verdict("symbol_ready", false, "created", "failed", "");
      SSR_End();
      return;
     }

   int    digits = (int)SymbolInfoInteger(InpTest, SYMBOL_DIGITS);
   double point  = SymbolInfoDouble(InpTest, SYMBOL_POINT);
   if(point <= 0.0) point = MathPow(10, -digits);
   double spread = 20 * point;

   //--- seed enough history that charts have context
   MqlRates seed[];
   int nseed = SSR_GenM1(seed, InpStart - 2000 * 60, 2000, InpBase, point, digits);
   CustomRatesUpdate(InpTest, seed);
   SymbolSelect(InpTest, true);
   SSR_WaitSeries(InpTest, PERIOD_M1, 15000);

   long ids[];
   long nch = OpenCharts(InpTest, InpCharts, ids);
   SSR_Metric(InpLabel, "charts_open", (double)nch, "count");
   Sleep(1500);

   double best_rate  = 0;
   int    best_batch = 0;

   for(int bi = 0; bi < 6; bi++)
     {
      int bsize = g_batch[bi];
      int rounds = MathMax(1, InpTotalTicks / bsize);

      //--- build the tick stream up front: we measure injection, not generation
      MqlTick buf[];
      ArrayResize(buf, bsize);
      SSR_Rng rng;
      rng.Seed(90210 + bi);
      double p = InpBase;
      long   t_msc = (long)InpStart * 1000;

      long mem0 = SSR_MemTerminal();
      long mql0 = SSR_MemMql();

      double total_us  = 0;
      long   sent      = 0;
      long   accepted  = 0;

      for(int r = 0; r < rounds; r++)
        {
         for(int i = 0; i < bsize; i++)
           {
            p += rng.Normal() * point * 2.0;
            t_msc += 10;                       // 10 ms between ticks
            buf[i].time        = (datetime)(t_msc / 1000);
            buf[i].time_msc    = t_msc;
            buf[i].bid         = NormalizeDouble(p, digits);
            buf[i].ask         = NormalizeDouble(p + spread, digits);
            buf[i].last        = buf[i].bid;
            buf[i].volume      = 1;
            buf[i].volume_real = 1.0;
            buf[i].flags       = TICK_FLAG_BID | TICK_FLAG_ASK;
           }

         ulong t0 = SSR_Now();
         int acc = CustomTicksAdd(InpTest, buf);
         total_us += SSR_ElapsedUs(t0);

         sent     += bsize;
         accepted += MathMax(acc, 0);
        }

      double secs = total_us / 1000000.0;
      double rate = (secs > 0 ? (double)sent / secs : 0);

      string c = StringFormat("%s_batch%d", InpLabel, bsize);
      SSR_Metric(c, "batch_size",     (double)bsize,     "ticks");
      SSR_Metric(c, "ticks_sent",     (double)sent,      "count");
      SSR_Metric(c, "ticks_accepted", (double)accepted,  "count");
      SSR_Metric(c, "inject_time",    secs,              "s");
      SSR_Metric(c, "ticks_per_sec",  rate,              "ticks/s");
      SSR_Metric(c, "us_per_tick",    total_us / MathMax(sent, 1), "us");
      SSR_Metric(c, "mem_terminal_delta", (double)(SSR_MemTerminal() - mem0), "MB");
      SSR_Metric(c, "mem_mql_delta",      (double)(SSR_MemMql() - mql0),      "MB");

      if(accepted < sent)
         SSR_Metric(c, "rejected", (double)(sent - accepted), "count",
                    "per-call cap or session rejection");

      if(rate > best_rate)
        {
         best_rate  = rate;
         best_batch = bsize;
        }

      PrintFormat("[B2] batch=%-6d rate=%10.0f ticks/s  accepted=%d/%d",
                  bsize, rate, (int)accepted, (int)sent);
      Sleep(500);
     }

   SSR_Metric(InpLabel, "best_ticks_per_sec", best_rate,          "ticks/s");
   SSR_Metric(InpLabel, "optimal_batch_size", (double)best_batch, "ticks",
              "lock this into Feeder");

   //--- PASS gate from the spike plan
   SSR_Verdict("throughput_target", best_rate >= 2000.0, ">=2000 ticks/s",
               StringFormat("%.0f", best_rate),
               "target for F2 at 1 chart");
   SSR_Verdict("throughput_floor", best_rate >= 500.0, ">=500 ticks/s",
               StringFormat("%.0f", best_rate),
               "below this, Plan B: F3 + bulk write becomes the main path");

   for(int i = 0; i < ArraySize(ids); i++)
      ChartClose(ids[i]);
   Sleep(500);
   SSR_DropSymbol(InpTest);
   SSR_End();

   Print("[B2] NOTE: read ui_jitter_p95 from the UIJitter probe for the same window.");
   Print("[B2] NOTE: record CPU% manually from Task Manager at peak throughput.");
  }
//+------------------------------------------------------------------+

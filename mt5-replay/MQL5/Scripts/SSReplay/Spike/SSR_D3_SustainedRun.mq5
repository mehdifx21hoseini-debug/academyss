//+------------------------------------------------------------------+
//|                                        SSR_D3_SustainedRun.mq5   |
//|  SPIKE D3 - Sustained Replay: Memory & Responsiveness            |
//|  TIER D - MEDIUM                                                 |
//|                                                                  |
//|  Short tests never reveal a leak. This one runs the feed for     |
//|  hours and samples memory and throughput every 10 seconds, so    |
//|  a slow drift shows up as a slope rather than a surprise.        |
//|                                                                  |
//|  Run SSR_Probe_UIJitter on another chart for the whole window.   |
//|  Record CPU% manually at minute 10, 60 and 120.                  |
//+------------------------------------------------------------------+
#property script_show_inputs

#include <SSReplay/Spike/SSR_SpikeKit.mqh>

input string   InpOrigin = "";                 // Origin symbol (blank = this chart's symbol)

input string   InpTest     = "SSRD3";              // Test symbol
input datetime InpStart    = D'2024.01.08 00:00';  // Start time
input double   InpBase     = 38000.0;              // Base price
input int      InpMinutes  = 120;                  // Run duration (minutes)
input int      InpBatch    = 1000;                 // Ticks per injection
input int      InpSampleSec = 10;                  // Sampling interval (seconds)
input int      InpCharts   = 1;                    // Charts to keep open

string g_origin = "";   //--- resolved from InpOrigin at the top of OnStart

//+------------------------------------------------------------------+
void OnStart()
  {
   SSR_Begin("D3_SustainedRun");

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
   double spread = 20 * point;

   MqlRates seed[];
   SSR_GenM1(seed, InpStart - 5000 * 60, 5000, InpBase, point, digits);
   CustomRatesUpdate(InpTest, seed);
   SymbolSelect(InpTest, true);
   SSR_WaitSeries(InpTest, PERIOD_M1, 30000);

   long cids[];
   ArrayResize(cids, 0);
   for(int i = 0; i < InpCharts && i < 4; i++)
     {
      long id = ChartOpen(InpTest, PERIOD_M1);
      if(id != 0)
        {
         int k = ArraySize(cids);
         ArrayResize(cids, k + 1);
         cids[k] = id;
        }
      Sleep(300);
     }

   FolderCreate(SSR_DIR);
   int fh = FileOpen("SSR_Spike\\d3_timeseries.csv", FILE_WRITE | FILE_TXT | FILE_ANSI);
   if(fh != INVALID_HANDLE)
      FileWriteString(fh, "minute,ticks_total,ticks_per_sec,mem_mql_mb,mem_terminal_mb\r\n");

   SSR_Rng rng;
   rng.Seed(555000);
   double p = InpBase;
   long   t_msc = (long)InpStart * 1000;

   MqlTick buf[];
   ArrayResize(buf, InpBatch);

   ulong  t_run     = SSR_Now();
   ulong  t_sample  = t_run;
   ulong  t_window  = t_run;
   long   total     = 0;
   long   window    = 0;

   long   mem_first = -1, mem_last = 0;
   double rate_first = -1, rate_last = 0;
   double limit_s = InpMinutes * 60.0;

   while(SSR_ElapsedSec(t_run) < limit_s && !IsStopped())
     {
      for(int i = 0; i < InpBatch; i++)
        {
         p += rng.Normal() * point * 2.0;
         t_msc += 10;
         buf[i].time        = (datetime)(t_msc / 1000);
         buf[i].time_msc    = t_msc;
         buf[i].bid         = NormalizeDouble(p, digits);
         buf[i].ask         = NormalizeDouble(p + spread, digits);
         buf[i].last        = buf[i].bid;
         buf[i].volume      = 1;
         buf[i].volume_real = 1.0;
         buf[i].flags       = TICK_FLAG_BID | TICK_FLAG_ASK;
        }
      CustomTicksAdd(InpTest, buf);
      total  += InpBatch;
      window += InpBatch;

      if(SSR_ElapsedSec(t_sample) >= (double)InpSampleSec)
        {
         double wsec = SSR_ElapsedSec(t_window);
         double rate = (wsec > 0 ? (double)window / wsec : 0);
         double minute = SSR_ElapsedSec(t_run) / 60.0;
         long mm = SSR_MemMql();
         long mt = SSR_MemTerminal();

         if(minute >= 10.0 && mem_first < 0)
           {
            mem_first  = mt;      // baseline taken after warm-up, not at t=0
            rate_first = rate;
           }
         mem_last  = mt;
         rate_last = rate;

         if(fh != INVALID_HANDLE)
            FileWriteString(fh, StringFormat("%.2f,%d,%.0f,%d,%d\r\n",
                                             minute, (int)total, rate, (int)mm, (int)mt));

         SSR_Metric(StringFormat("t%04.0fs", SSR_ElapsedSec(t_run)),
                    "ticks_per_sec", rate, "ticks/s");
         SSR_Metric(StringFormat("t%04.0fs", SSR_ElapsedSec(t_run)),
                    "mem_terminal", (double)mt, "MB");

         PrintFormat("[D3] %6.1f min  total=%d  rate=%.0f t/s  mem=%dMB",
                     minute, (int)total, rate, (int)mt);

         t_sample = SSR_Now();
         t_window = SSR_Now();
         window   = 0;
        }
     }

   if(fh != INVALID_HANDLE)
      FileClose(fh);

   double mem_growth  = (mem_first > 0 ? 100.0 * (double)(mem_last - mem_first) / (double)mem_first : 0);
   double rate_drop   = (rate_first > 0 ? 100.0 * (rate_first - rate_last) / rate_first : 0);

   SSR_Metric("sustained", "duration",        SSR_ElapsedSec(t_run) / 60.0, "min");
   SSR_Metric("sustained", "ticks_total",     (double)total,  "count");
   SSR_Metric("sustained", "mem_at_min10",    (double)mem_first, "MB");
   SSR_Metric("sustained", "mem_at_end",      (double)mem_last,  "MB");
   SSR_Metric("sustained", "mem_growth",      mem_growth,     "%");
   SSR_Metric("sustained", "rate_at_min10",   rate_first,     "ticks/s");
   SSR_Metric("sustained", "rate_at_end",     rate_last,      "ticks/s");
   SSR_Metric("sustained", "rate_degradation", rate_drop,     "%");

   //--- A RUN TOO SHORT TO HAVE A BASELINE MUST NOT REPORT PASS.
   //--- mem_first is only taken at minute 10. Below that it stays -1,
   //--- both percentages compute as 0.0, and both verdicts came back
   //--- green having measured nothing at all. A five-minute run would
   //--- have certified "no leak" on the strength of an empty baseline -
   //--- the same lenient-assertion trap that hid the one-bar jump for
   //--- eleven phases. Say "not measured" instead, out loud.
   bool have_baseline = (mem_first > 0);

   if(!have_baseline)
     {
      string why = StringFormat("ran %.1f min - the baseline is taken at minute 10",
                                SSR_ElapsedSec(t_run) / 60.0);
      SSR_Verdict("memory_stable",     false, "a run of 10+ minutes", "not measured", why);
      SSR_Verdict("throughput_stable", false, "a run of 10+ minutes", "not measured", why);
     }
   else
     {
      SSR_Verdict("memory_stable", mem_growth <= 10.0, "<=10% growth",
                  StringFormat("%.1f%%", mem_growth), "baseline taken at minute 10");
      SSR_Verdict("throughput_stable", rate_drop <= 10.0, "<=10% drop",
                  StringFormat("%.1f%%", rate_drop), "");
     }

   for(int i = 0; i < ArraySize(cids); i++)
      ChartClose(cids[i]);
   Sleep(500);
   SSR_DropSymbol(InpTest);
   SSR_End();
   Print("[D3] time series: <DataFolder>\\MQL5\\Files\\SSR_Spike\\d3_timeseries.csv");
  }
//+------------------------------------------------------------------+

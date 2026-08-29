//+------------------------------------------------------------------+
//|                                          SSR_C4_ReplayClock.mq5  |
//|  SPIKE C4 - Replay Clock Accuracy                                |
//|  TIER C - HIGH                                                   |
//|                                                                  |
//|  The design document claims a free win: after injecting a tick,  |
//|  SYMBOL_TIME of the replay symbol equals that tick's time, so    |
//|  the user's own indicators and EAs see the correct replay time   |
//|  with no adapter code at all. That claim is tested here.         |
//|                                                                  |
//|  It also tests the counter-claim: that TimeCurrent() is NOT      |
//|  safe, because other live symbols in Market Watch move it.       |
//+------------------------------------------------------------------+
#property script_show_inputs

#include <SSReplay/Spike/SSR_SpikeKit.mqh>

input string   InpOrigin = "US30Cash";           // Origin symbol
input string   InpTest   = "SSRC4";              // Test symbol
input datetime InpStart  = D'2024.01.08 00:00';  // Replay time base (in the past)
input double   InpBase   = 38000.0;              // Base price
input int      InpTicks  = 1000;                 // Ticks to check

//+------------------------------------------------------------------+
void OnStart()
  {
   SSR_Begin("C4_ReplayClock");

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

   MqlRates seed[];
   SSR_GenM1(seed, InpStart - 240 * 60, 240, InpBase, point, digits);
   CustomRatesUpdate(InpTest, seed);
   SymbolSelect(InpTest, true);
   SSR_WaitSeries(InpTest, PERIOD_M1, 10000);

   long worst_sec = 0, worst_msc = 0;
   int  bad_sec = 0, bad_msc = 0;
   long sum_abs_msc = 0;

   for(int i = 0; i < InpTicks; i++)
     {
      long     t_msc = (long)InpStart * 1000 + (long)i * 1000;
      datetime t     = (datetime)(t_msc / 1000);

      MqlTick tk[1];
      tk[0].time        = t;
      tk[0].time_msc    = t_msc;
      tk[0].bid         = NormalizeDouble(InpBase + i * point, digits);
      tk[0].ask         = NormalizeDouble(InpBase + i * point + spread, digits);
      tk[0].last        = tk[0].bid;
      tk[0].volume      = 1;
      tk[0].volume_real = 1.0;
      tk[0].flags       = TICK_FLAG_BID | TICK_FLAG_ASK;

      CustomTicksAdd(InpTest, tk);

      long sym_t   = SymbolInfoInteger(InpTest, SYMBOL_TIME);
      long sym_msc = SymbolInfoInteger(InpTest, SYMBOL_TIME_MSC);

      long d_sec = sym_t - (long)t;
      long d_msc = sym_msc - t_msc;

      if(d_sec != 0) { bad_sec++; if(MathAbs(d_sec) > MathAbs(worst_sec)) worst_sec = d_sec; }
      if(d_msc != 0) { bad_msc++; if(MathAbs(d_msc) > MathAbs(worst_msc)) worst_msc = d_msc; }
      sum_abs_msc += (long)MathAbs(d_msc);
     }

   SSR_Metric("clock", "ticks_checked",   (double)InpTicks,  "count");
   SSR_Metric("clock", "sec_mismatches",  (double)bad_sec,   "count");
   SSR_Metric("clock", "msc_mismatches",  (double)bad_msc,   "count");
   SSR_Metric("clock", "worst_delta_sec", (double)worst_sec, "s");
   SSR_Metric("clock", "worst_delta_msc", (double)worst_msc, "ms");
   SSR_Metric("clock", "avg_abs_delta_msc",
              (double)sum_abs_msc / MathMax(InpTicks, 1), "ms");

   SSR_Verdict("symbol_time_equals_injected", bad_sec == 0, "0 mismatches",
               IntegerToString(bad_sec),
               "SYMBOL_TIME is the engine's official clock source");
   SSR_Verdict("symbol_time_msc_exact", bad_msc == 0, "0 mismatches",
               IntegerToString(bad_msc), "millisecond resolution");

   //--- is the replay symbol's clock in the past, while TimeCurrent is not?
   long     sym_t = SymbolInfoInteger(InpTest, SYMBOL_TIME);
   datetime tc    = TimeCurrent();
   SSR_Metric("timecurrent", "symbol_time",       (double)sym_t, "unixtime",
              TimeToString((datetime)sym_t));
   SSR_Metric("timecurrent", "timecurrent",       (double)tc,    "unixtime",
              TimeToString(tc));
   SSR_Metric("timecurrent", "divergence",
              (double)((long)tc - sym_t) / 86400.0, "days",
              "how far TimeCurrent is from the replay clock");

   //--- how many other symbols could be moving TimeCurrent right now
   int live = 0;
   int total_mw = SymbolsTotal(true);
   for(int i = 0; i < total_mw; i++)
     {
      string s = SymbolName(i, true);
      if(s == InpTest) continue;
      if(SymbolInfoInteger(s, SYMBOL_TIME) > sym_t) live++;
     }
   SSR_Metric("timecurrent", "market_watch_symbols", (double)total_mw, "count");
   SSR_Metric("timecurrent", "symbols_ahead_of_replay", (double)live, "count",
              "each one can drag TimeCurrent forward");
   SSR_Verdict("timecurrent_is_unsafe", (long)tc != sym_t, "differs from replay clock",
               StringFormat("tc=%s sym=%s", TimeToString(tc), TimeToString((datetime)sym_t)),
               "confirms the rule: never use TimeCurrent in replay logic");

   SSR_DropSymbol(InpTest);
   SSR_End();
  }
//+------------------------------------------------------------------+

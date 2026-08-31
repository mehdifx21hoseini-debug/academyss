//+------------------------------------------------------------------+
//|                                                    SSR_Z_Gaps.mq5 |
//|              SS Replay - Where the broker's M1 history has holes |
//|                                                                  |
//|  A replay can only show minutes the broker actually stored. When |
//|  the clock advances and no candle appears, there are exactly two |
//|  explanations - the engine emitted nothing, or there was nothing |
//|  to emit - and only one of them is a defect.                     |
//|                                                                  |
//|  A black box recording showed the clock running from 11:05:39 to |
//|  11:08:03 with no ticks and no new bars. This says which of the  |
//|  two that was, in about a second, instead of asking someone to   |
//|  eyeball a chart and report back.                                |
//+------------------------------------------------------------------+
#property script_show_inputs
#property strict

#include <SSReplay/Common/SSR_Build.mqh>

input string   InpSymbol = "";                       // Symbol (empty = this chart)
input datetime InpFrom   = D'2026.08.21 11:00';      // From
input datetime InpTo     = D'2026.08.21 12:00';      // To
input int      InpMinRun = 1;                        // Report holes of at least this many minutes

//+------------------------------------------------------------------+
void OnStart()
  {
   string sym = (InpSymbol == "" ? _Symbol : InpSymbol);
   PrintFormat("=== SS Replay M1 gap scan === build %s", SSR_BUILD);
   PrintFormat("symbol %s   %s .. %s", sym,
               TimeToString(InpFrom, TIME_DATE | TIME_MINUTES),
               TimeToString(InpTo,   TIME_DATE | TIME_MINUTES));

   if(InpTo <= InpFrom)
     {
      Print("  the range is empty - set 'To' after 'From'.");
      return;
     }

   MqlRates r[];
   int n = CopyRates(sym, PERIOD_M1, InpFrom, InpTo, r);
   if(n <= 0)
     {
      PrintFormat("  NO BARS AT ALL in that range (err %d). Either the "
                  "history is not downloaded, or the market was closed. "
                  "Open an M1 chart of %s and press Home to fetch it.",
                  GetLastError(), sym);
      return;
     }

   //--- how many minutes the range spans, against how many bars exist
   int span = (int)((InpTo - InpFrom) / 60);
   PrintFormat("  %d bars across %d minutes (%.1f%% present)",
               n, span, span > 0 ? 100.0 * n / span : 0.0);
   PrintFormat("  first %s   last %s",
               TimeToString(r[0].time, TIME_DATE | TIME_MINUTES),
               TimeToString(r[n - 1].time, TIME_DATE | TIME_MINUTES));

   int holes = 0, missing = 0;
   for(int i = 1; i < n && !IsStopped(); i++)
     {
      int gap = (int)((r[i].time - r[i - 1].time) / 60) - 1;
      if(gap < InpMinRun)
         continue;
      holes++;
      missing += gap;
      //--- the first twenty are enough to see the shape of it
      if(holes <= 20)
         PrintFormat("  HOLE  %d minute(s) missing after %s  (next bar %s)",
                     gap, TimeToString(r[i - 1].time, TIME_DATE | TIME_MINUTES),
                     TimeToString(r[i].time, TIME_DATE | TIME_MINUTES));
     }
   if(holes > 20)
      PrintFormat("  ... and %d more holes", holes - 20);

   if(holes == 0)
     {
      Print("  NO HOLES. Every minute in this range has a bar, so a replay "
            "that stalls here is the engine's doing, not the data's.");
      return;
     }
   PrintFormat("  %d hole(s), %d missing minute(s) in total.", holes, missing);
   Print("  A replay crossing these will show the clock moving with no new "
         "candle. That is the broker's history, not a fault in the tool.");
  }
//+------------------------------------------------------------------+

//+------------------------------------------------------------------+
//|                                       SSR_B3_SessionBehavior.mq5 |
//|  SPIKE B3 - Session Behaviour & Tick Acceptance                  |
//|  TIER B - HIGH                                                   |
//|                                                                  |
//|  Hypothesis: without configured sessions the terminal SILENTLY   |
//|  drops ticks outside market hours - a quiet bug that would show  |
//|  up as missing candles much later. Setting 24/7 sessions fixes   |
//|  it. Both halves are measured, not assumed.                      |
//|                                                                  |
//|  168 probe points: one per hour of a full week, twice.           |
//+------------------------------------------------------------------+
#property script_show_inputs

#include <SSReplay/Spike/SSR_SpikeKit.mqh>

input string   InpOrigin = "US30Cash";           // Origin symbol
input datetime InpMonday = D'2024.01.08 00:00';  // A Monday 00:00
input double   InpBase   = 38000.0;              // Base price

//+------------------------------------------------------------------+
//| Inject one tick per hour of a week, then read them all back.     |
//| Acceptance = what survives the round trip, not what the return   |
//| value claims.                                                    |
//+------------------------------------------------------------------+
void RunCase(const string sym, const bool with_sessions, const string label)
  {
   if(!SSR_MakeSymbol(sym, InpOrigin, with_sessions))
     {
      SSR_Verdict(label + "_symbol", false, "created", "failed", "");
      return;
     }

   int    digits = (int)SymbolInfoInteger(sym, SYMBOL_DIGITS);
   double point  = SymbolInfoDouble(sym, SYMBOL_POINT);
   if(point <= 0.0) point = MathPow(10, -digits);
   double spread = 20 * point;

   //--- a base bar so the symbol is not empty
   MqlRates seed[];
   SSR_GenM1(seed, InpMonday - 60 * 60, 60, InpBase, point, digits);
   CustomRatesUpdate(sym, seed);
   SymbolSelect(sym, true);
   SSR_WaitSeries(sym, PERIOD_M1, 10000);

   int sent = 0, ret_ok = 0;
   int per_day_sent[7], per_day_back[7];
   ArrayInitialize(per_day_sent, 0);
   ArrayInitialize(per_day_back, 0);

   for(int h = 0; h < 168; h++)
     {
      datetime t = InpMonday + h * 3600;
      MqlDateTime st;
      TimeToStruct(t, st);
      int dow = st.day_of_week;

      MqlTick tk[1];
      tk[0].time        = t;
      tk[0].time_msc    = (long)t * 1000;
      tk[0].bid         = NormalizeDouble(InpBase + h * point, digits);
      tk[0].ask         = NormalizeDouble(InpBase + h * point + spread, digits);
      tk[0].last        = tk[0].bid;
      tk[0].volume      = 1;
      tk[0].volume_real = 1.0;
      tk[0].flags       = TICK_FLAG_BID | TICK_FLAG_ASK;

      ResetLastError();
      int acc = CustomTicksAdd(sym, tk);
      sent++;
      per_day_sent[dow]++;
      if(acc == 1) ret_ok++;
     }

   Sleep(1000);

   //--- ground truth: what can actually be read back
   MqlTick back[];
   int nback = CopyTicksRange(sym, back, COPY_TICKS_ALL,
                              (long)InpMonday * 1000,
                              (long)(InpMonday + 168 * 3600) * 1000);

   int matched = 0;
   for(int h = 0; h < 168; h++)
     {
      datetime t = InpMonday + h * 3600;
      MqlDateTime st;
      TimeToStruct(t, st);
      for(int i = 0; i < nback; i++)
         if(back[i].time_msc == (long)t * 1000)
           {
            matched++;
            per_day_back[st.day_of_week]++;
            break;
           }
     }

   double accept_rate = (sent > 0 ? 100.0 * matched / sent : 0);

   SSR_Metric(label, "ticks_sent",           (double)sent,    "count");
   SSR_Metric(label, "ticksadd_returned_ok", (double)ret_ok,  "count");
   SSR_Metric(label, "ticks_readable",       (double)matched, "count");
   SSR_Metric(label, "acceptance_rate",      accept_rate,     "%");

   string dayname[7] = {"Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"};
   for(int d = 0; d < 7; d++)
      SSR_Metric(label + "_" + dayname[d], "readable_of_sent",
                 (per_day_sent[d] > 0 ? 100.0 * per_day_back[d] / per_day_sent[d] : 0), "%",
                 StringFormat("%d/%d", per_day_back[d], per_day_sent[d]));

   //--- a return value that claims success while the tick is unreadable
   //--- is the silent-drop signature we are hunting for
   if(ret_ok > matched)
      SSR_Metric(label, "silent_drops", (double)(ret_ok - matched), "count",
                 "CustomTicksAdd reported success but the tick is not readable");

   SSR_DropSymbol(sym);
  }

//+------------------------------------------------------------------+
void OnStart()
  {
   SSR_Begin("B3_SessionBehavior");

   RunCase("SSRB3A", false, "no_sessions");
   RunCase("SSRB3B", true,  "sessions_247");

   Print("[B3] Compare acceptance_rate between no_sessions and sessions_247.");
   Print("[B3] PASS requires sessions_247 acceptance_rate == 100%.");

   SSR_End();
  }
//+------------------------------------------------------------------+

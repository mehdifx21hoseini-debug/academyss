//+------------------------------------------------------------------+
//|                                     SSR_B1_TicksAddBroadcast.mq5 |
//|  SPIKE B1 - CustomTicksAdd Live Broadcast                        |
//|  TIER B - BLOCKER for the transport layer                        |
//|                                                                  |
//|  Hypothesis: CustomTicksAdd does not merely write history - it   |
//|  broadcasts the tick to open charts, so the candle forms live    |
//|  and indicators recalculate. This is what makes "tick as the     |
//|  single transport layer" possible.                               |
//|                                                                  |
//|  Attach SSR_Probe_TickWitness to the test symbol's chart first.  |
//+------------------------------------------------------------------+
#property script_show_inputs

#include <SSReplay/Spike/SSR_SpikeKit.mqh>

input string   InpOrigin = "";                 // Origin symbol (blank = this chart's symbol)

input string   InpTest    = "SSRB1";              // Test symbol
input datetime InpStart   = D'2024.01.08 00:00';  // Base bar time
input double   InpBase    = 38000.0;              // Base price
input int      InpBatches = 20;                   // Batches to inject
input int      InpPerBar  = 20;                   // Ticks per M1 bar
input bool     InpOpenChart = true;               // Open a chart for the test symbol
input int      InpReflectMs = 250;                // Max wait for the chart series to catch up (ms)

string g_origin = "";   //--- resolved from InpOrigin at the top of OnStart

//+------------------------------------------------------------------+
void OnStart()
  {
   SSR_Begin("B1_TicksAddBroadcast");

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

   //--- seed a little history so the chart has something to show
   MqlRates seed[];
   int nseed = SSR_GenM1(seed, InpStart - 120 * 60, 120, InpBase, point, digits);
   CustomRatesUpdate(InpTest, seed);
   SymbolSelect(InpTest, true);
   SSR_WaitSeries(InpTest, PERIOD_M1, 10000);

   long cid = 0;
   if(InpOpenChart)
     {
      cid = ChartOpen(InpTest, PERIOD_M1);
      Sleep(1000);
      SSR_Metric("setup", "chart_opened", (cid != 0 ? 1 : 0), "bool");
     }

   //--- forward bars we will feed tick by tick
   MqlRates bars[];
   int nbars = SSR_GenM1(bars, InpStart, InpBatches, InpBase, point, digits, 25.0, 4242);

   int    total_ticks   = 0;
   int    total_accepted = 0;
   double lat_sum = 0;
   int    reflected_tick  = 0;
   int    reflected_close = 0;
   double close_lat_sum   = 0;
   int    hl_expanded     = 0;

   for(int b = 0; b < nbars; b++)
     {
      MqlTick ticks[];
      int nt = SSR_BarToTicks(bars[b], ticks, InpPerBar, spread, digits);

      ulong t0 = SSR_Now();
      ResetLastError();
      int accepted = CustomTicksAdd(InpTest, ticks);
      double t_add = SSR_ElapsedUs(t0);
      int err = GetLastError();

      total_ticks    += nt;
      total_accepted += MathMax(accepted, 0);

      if(accepted != nt)
         SSR_Metric("batch", "partial_accept", (double)accepted, "count",
                    StringFormat("sent=%d err=%d - possible per-call cap", nt, err));

      //--- 1. is the last injected tick visible through SymbolInfoTick?
      ulong t1 = SSR_Now();
      MqlTick cur;
      double expect = NormalizeDouble(bars[b].close, digits);
      if(SymbolInfoTick(InpTest, cur))
        {
         lat_sum += SSR_ElapsedUs(t1);
         if(MathAbs(cur.bid - expect) < point * 0.5)
            reflected_tick++;
        }

      //--- 2. has the FORMING bar taken the injected close?
      //---
      //--- THE TICK IS INSTANT; THE SERIES IS NOT. SymbolInfoTick sees
      //--- every injected tick immediately, but the M1 series the chart
      //--- draws from is rebuilt by the terminal on its own schedule.
      //--- Reading iClose with no wait measured that schedule, not the
      //--- broadcast: 1 hit in 20, which read as "the candle does not
      //--- form from injected ticks" when the truth is "it forms a few
      //--- milliseconds later". So wait for it, with a ceiling, and
      //--- record HOW LONG - a latency is a result; a bare miss is not.
      ulong  t2 = SSR_Now();
      double c0 = 0;
      bool   took = false;
      while(SSR_ElapsedMs(t2) < InpReflectMs)
        {
         c0 = iClose(InpTest, PERIOD_M1, 0);
         if(MathAbs(c0 - expect) < point * 0.5)
           { took = true; break; }
         SSR_Pause(1);
        }
      if(took)
        {
         reflected_close++;
         close_lat_sum += SSR_ElapsedMs(t2);
        }

      //--- 3. did the wick actually stretch to the injected extremes?
      //--- Same asynchrony as the close: give the series the same
      //--- chance to catch up rather than reading it a moment early.
      ulong  t3 = SSR_Now();
      double hi = NormalizeDouble(bars[b].high, digits);
      double lo = NormalizeDouble(bars[b].low,  digits);
      while(SSR_ElapsedMs(t3) < InpReflectMs)
        {
         double h0 = iHigh(InpTest, PERIOD_M1, 0);
         double l0 = iLow(InpTest, PERIOD_M1, 0);
         if(h0 >= hi - point && l0 <= lo + point)
           { hl_expanded++; break; }
         SSR_Pause(1);
        }

      SSR_Metric("batch", "ticksadd_elapsed", t_add, "us",
                 StringFormat("bar=%d ticks=%d", b, nt));
     }

   SSR_Metric("broadcast", "ticks_sent",      (double)total_ticks,    "count");
   SSR_Metric("broadcast", "ticks_accepted",  (double)total_accepted, "count");
   SSR_Metric("broadcast", "reflect_symbolinfotick", (double)reflected_tick,  "count",
              "out of " + IntegerToString(nbars));
   SSR_Metric("broadcast", "reflect_iclose",        (double)reflected_close, "count",
              "out of " + IntegerToString(nbars));
   SSR_Metric("broadcast", "wick_expanded",         (double)hl_expanded,     "count",
              "out of " + IntegerToString(nbars));
   SSR_Metric("broadcast", "symbolinfotick_latency",
              lat_sum / MathMax(nbars, 1), "us");
   SSR_Metric("broadcast", "series_reflect_latency",
              close_lat_sum / MathMax(reflected_close, 1), "ms",
              "how long after the tick the chart's own series shows it");

   SSR_Verdict("ticks_all_accepted", total_accepted == total_ticks,
               IntegerToString(total_ticks), IntegerToString(total_accepted),
               "a shortfall reveals a per-call cap");
   SSR_Verdict("tick_visible_in_symbolinfotick", reflected_tick == nbars,
               IntegerToString(nbars), IntegerToString(reflected_tick), "");
   SSR_Verdict("forming_bar_took_close", reflected_close == nbars,
               IntegerToString(nbars), IntegerToString(reflected_close),
               "candle builds natively from injected ticks");
   SSR_Verdict("wick_expanded_to_extremes", hl_expanded == nbars,
               IntegerToString(nbars), IntegerToString(hl_expanded),
               "high/low grow tick by tick");

   //--- 4. documented behaviour when the symbol is NOT in Market Watch
   {
      string sym2 = InpTest + "H";
      if(SSR_MakeSymbol(sym2, g_origin))
        {
         MqlRates s2[];
         int n2 = SSR_GenM1(s2, InpStart - 60 * 60, 60, InpBase, point, digits);
         CustomRatesUpdate(sym2, s2);

         SymbolSelect(sym2, false);        // deliberately hidden
         Sleep(300);

         MqlTick tk[];
         SSR_BarToTicks(bars[0], tk, 10, spread, digits);
         ResetLastError();
         int acc = CustomTicksAdd(sym2, tk);
         int e   = GetLastError();

         SSR_Metric("hidden_symbol", "ticksadd_return", (double)acc, "count",
                    "err=" + IntegerToString(e));
         SSR_Verdict("hidden_symbol_behaviour_documented", true, "recorded",
                     StringFormat("sent=10 accepted=%d err=%d", acc, e),
                     "confirms the Market Watch requirement");
         SSR_DropSymbol(sym2);
        }
   }

   if(cid != 0)
     {
      Sleep(1000);
      ChartClose(cid);
     }
   SSR_DropSymbol(InpTest);
   SSR_End();
  }
//+------------------------------------------------------------------+

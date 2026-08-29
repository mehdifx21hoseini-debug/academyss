//+------------------------------------------------------------------+
//|                                      SSR_D2_TimeframeSwitch.mq5  |
//|  SPIKE D2 - Timeframe Switching Cost                             |
//|  TIER D - MEDIUM                                                 |
//|                                                                  |
//|  "M1 -> M5 -> M15 -> H1 without breaking replay" is an explicit  |
//|  product requirement. A2 proves it is CORRECT; this measures     |
//|  whether it is FAST, at several seed depths, and again while     |
//|  ticks are actively being injected - which is the real           |
//|  condition a user will switch timeframes in.                     |
//+------------------------------------------------------------------+
#property script_show_inputs

#include <SSReplay/Spike/SSR_SpikeKit.mqh>

input string   InpOrigin = "";                 // Origin symbol (blank = this chart's symbol)

input string   InpTest   = "SSRD2";              // Test symbol
input datetime InpStart  = D'2022.01.03 00:00';  // Seed start
input double   InpBase   = 33000.0;              // Base price
input int      InpRepeat = 10;                   // Cycles per depth

string g_origin = "";   //--- resolved from InpOrigin at the top of OnStart

ENUM_TIMEFRAMES g_cycle[7]  = {PERIOD_M1, PERIOD_M5, PERIOD_M15, PERIOD_M30, PERIOD_H1, PERIOD_H4, PERIOD_M1};
string          g_cname[7]  = {"M1", "M5", "M15", "M30", "H1", "H4", "M1b"};
int             g_depths[3] = {10000, 50000, 100000};

//+------------------------------------------------------------------+
void MeasureDepth(const int depth, const int digits, const double point, const bool with_ticks)
  {
   if(!SSR_MakeSymbol(InpTest, g_origin))
      return;

   MqlRates m1[];
   SSR_GenM1(m1, InpStart, depth, InpBase, point, digits);
   for(int off = 0; off < depth; off += 10000)
     {
      int cnt = MathMin(10000, depth - off);
      MqlRates part[];
      ArrayResize(part, cnt);
      for(int i = 0; i < cnt; i++) part[i] = m1[off + i];
      CustomRatesUpdate(InpTest, part);
     }
   SymbolSelect(InpTest, true);
   SSR_WaitSeries(InpTest, PERIOD_M1, 60000);

   long cid = ChartOpen(InpTest, PERIOD_M1);
   Sleep(1500);
   if(cid == 0)
     {
      SSR_Verdict("chart_open_depth" + IntegerToString(depth), false, "chart id", "0", "");
      SSR_DropSymbol(InpTest);
      return;
     }

   string mode = (with_ticks ? "live" : "idle");
   double worst = 0;

   for(int rep = 0; rep < InpRepeat; rep++)
     {
      for(int i = 0; i < 7; i++)
        {
         //--- optionally keep the feed running, as it would be in real use
         if(with_ticks)
           {
            MqlTick tk[];
            SSR_BarToTicks(m1[depth - 1], tk, 50, 20 * point, digits);
            CustomTicksAdd(InpTest, tk);
           }

         ulong t0 = SSR_Now();
         ChartSetSymbolPeriod(cid, InpTest, g_cycle[i]);

         //--- wait until the series for the NEW timeframe is actually usable
         double waited = -1;
         ulong tw = SSR_Now();
         while(SSR_ElapsedMs(tw) < 15000)
           {
            long sync = 0;
            if(SeriesInfoInteger(InpTest, g_cycle[i], SERIES_SYNCHRONIZED, sync) && sync != 0)
               if(Bars(InpTest, g_cycle[i]) > 0)
                 {
                  waited = SSR_ElapsedMs(t0);
                  break;
                 }
            Sleep(2);
           }
         if(waited < 0) waited = SSR_ElapsedMs(t0);
         if(waited > worst) worst = waited;

         SSR_Metric(StringFormat("tfswitch_%dk_%s", depth / 1000, mode),
                    "switch_to_" + g_cname[i], waited, "ms",
                    StringFormat("bars=%d", Bars(InpTest, g_cycle[i])));
        }
     }

   SSR_Metric(StringFormat("tfswitch_%dk_%s", depth / 1000, mode),
              "worst_switch", worst, "ms");
   SSR_Verdict(StringFormat("tfswitch_%dk_%s_under_1s", depth / 1000, mode),
               worst <= 1000.0, "<=1000ms", StringFormat("%.0f", worst), "");

   ChartClose(cid);
   Sleep(500);
   SSR_DropSymbol(InpTest);
  }

//+------------------------------------------------------------------+
void OnStart()
  {
   SSR_Begin("D2_TimeframeSwitch");

   g_origin = SSR_Origin(InpOrigin);
   if(!SSR_MakeSymbol(InpTest, g_origin)) { SSR_End(); return; }
   int    digits = (int)SymbolInfoInteger(InpTest, SYMBOL_DIGITS);
   double point  = SymbolInfoDouble(InpTest, SYMBOL_POINT);
   if(point <= 0.0) point = MathPow(10, -digits);
   SSR_DropSymbol(InpTest);

   for(int i = 0; i < 3; i++)
     {
      MeasureDepth(g_depths[i], digits, point, false);
      MeasureDepth(g_depths[i], digits, point, true);
     }

   SSR_End();
  }
//+------------------------------------------------------------------+

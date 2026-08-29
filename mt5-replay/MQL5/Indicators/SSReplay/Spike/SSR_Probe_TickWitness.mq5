//+------------------------------------------------------------------+
//|                                          SSR_Probe_TickWitness.mq5 |
//|  PROBE - proves CustomTicksAdd really reaches the chart.         |
//|                                                                  |
//|  A tick landing in history is not the same as a tick reaching    |
//|  the chart. Only an indicator running on that chart can testify  |
//|  that OnCalculate fired and that the forming bar moved.          |
//|                                                                  |
//|  Attach to the chart of the symbol UNDER TEST, then run A2/B1.   |
//+------------------------------------------------------------------+
#property indicator_chart_window
#property indicator_buffers 0
#property indicator_plots 0

#include <SSReplay/Spike/SSR_SpikeKit.mqh>

input int InpReportSec = 5;   // Report interval (seconds)

long   g_calls   = 0;
long   g_ticks   = 0;
double g_lastc   = 0;
ulong  g_report  = 0;
ulong  g_t0      = 0;

//+------------------------------------------------------------------+
int OnInit()
  {
   g_calls  = 0;
   g_ticks  = 0;
   g_lastc  = 0;
   g_t0     = GetMicrosecondCount();
   g_report = g_t0;
   SSR_Begin("Probe_TickWitness");
   Comment("SSR Tick Witness attached to ", _Symbol, " ", EnumToString(_Period));
   return INIT_SUCCEEDED;
  }

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   Comment("");
   Report();
   SSR_End();
  }

//+------------------------------------------------------------------+
void Report()
  {
   double secs = SSR_ElapsedSec(g_t0);
   SSR_Metric(_Symbol + "_" + EnumToString(_Period), "oncalculate_calls", (double)g_calls, "count");
   SSR_Metric(_Symbol + "_" + EnumToString(_Period), "observed_price_changes", (double)g_ticks, "count");
   SSR_Metric(_Symbol + "_" + EnumToString(_Period), "elapsed", secs, "s");
   SSR_Metric(_Symbol + "_" + EnumToString(_Period), "calls_per_sec",
              (secs > 0 ? (double)g_calls / secs : 0), "calls/s");
   //--- a chart that never recalculates is the FAIL signal for spike B1
   SSR_Verdict("chart_received_ticks", g_calls > 1, ">1 OnCalculate",
               IntegerToString((int)g_calls), "witness on " + _Symbol);
  }

//+------------------------------------------------------------------+
int OnCalculate(const int rates_total, const int prev_calculated,
                const datetime &time[], const double &open[], const double &high[],
                const double &low[], const double &close[], const long &tick_volume[],
                const long &volume[], const int &spread[])
  {
   g_calls++;
   if(rates_total > 0)
     {
      double c = close[rates_total - 1];
      if(c != g_lastc)
        {
         g_ticks++;
         g_lastc = c;
        }
     }

   ulong now = GetMicrosecondCount();
   if((double)(now - g_report) / 1000000.0 >= (double)InpReportSec)
     {
      g_report = now;
      Comment(StringFormat("SSR Tick Witness  calls=%d  price_changes=%d  last=%.5f",
                           (int)g_calls, (int)g_ticks, g_lastc));
     }
   return rates_total;
  }
//+------------------------------------------------------------------+

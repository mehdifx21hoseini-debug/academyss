//+------------------------------------------------------------------+
//|                                            SSR_Probe_UIJitter.mq5 |
//|  PROBE - terminal responsiveness, measured properly.             |
//|                                                                  |
//|  MQL5 exposes no CPU-usage API, and "the terminal felt slow" is  |
//|  not a measurement. This probe measures what actually matters:   |
//|  a timer that should fire every InpPeriodMs is checked against   |
//|  when it really fired. The gap is thread starvation - exactly    |
//|  what a user experiences as a freeze.                            |
//|                                                                  |
//|  Attach to any chart OTHER than the one under test, then run a   |
//|  spike. Reports p50 / p95 / max jitter to SSR_Spike\results.csv. |
//+------------------------------------------------------------------+
#property indicator_chart_window
#property indicator_buffers 0
#property indicator_plots 0

#include <SSReplay/Spike/SSR_SpikeKit.mqh>

input int    InpPeriodMs  = 50;        // Timer period (ms)
input int    InpWindow    = 2000;      // Samples kept for percentiles
input int    InpReportSec = 10;        // Report interval (seconds)
input string InpLabel     = "idle";    // Label recorded with the numbers

ulong  g_last   = 0;
double g_samp[];
int    g_count  = 0;
int    g_head   = 0;
ulong  g_report = 0;

//+------------------------------------------------------------------+
int OnInit()
  {
   ArrayResize(g_samp, InpWindow);
   ArrayInitialize(g_samp, 0.0);
   g_count  = 0;
   g_head   = 0;
   g_last   = GetMicrosecondCount();
   g_report = GetMicrosecondCount();

   SSR_Begin("Probe_UIJitter");
   EventSetMillisecondTimer(InpPeriodMs);
   Comment("SSR UI Jitter probe running - label=", InpLabel);
   return INIT_SUCCEEDED;
  }

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   EventKillTimer();
   Comment("");
   Report("final");
   SSR_End();
  }

//+------------------------------------------------------------------+
void OnTimer()
  {
   ulong now = GetMicrosecondCount();
   double actual_ms   = (double)(now - g_last) / 1000.0;
   double jitter_ms   = actual_ms - (double)InpPeriodMs;
   if(jitter_ms < 0) jitter_ms = 0;
   g_last = now;

   g_samp[g_head] = jitter_ms;
   g_head = (g_head + 1) % InpWindow;
   if(g_count < InpWindow) g_count++;

   if((double)(now - g_report) / 1000000.0 >= (double)InpReportSec)
     {
      g_report = now;
      Report("periodic");
     }
  }

//+------------------------------------------------------------------+
void Report(const string kind)
  {
   if(g_count < 5) return;

   double s[];
   ArrayResize(s, g_count);
   for(int i = 0; i < g_count; i++)
      s[i] = g_samp[i];
   ArraySort(s);

   double p50 = s[(int)(g_count * 0.50)];
   double p95 = s[(int)MathMin(g_count - 1, (int)(g_count * 0.95))];
   double mx  = s[g_count - 1];

   string c = InpLabel + "_" + kind;
   SSR_Metric(c, "ui_jitter_p50", p50, "ms");
   SSR_Metric(c, "ui_jitter_p95", p95, "ms");
   SSR_Metric(c, "ui_jitter_max", mx,  "ms");
   SSR_Metric(c, "mem_terminal",  (double)SSR_MemTerminal(), "MB");

   Comment(StringFormat("SSR UI Jitter [%s]  p50=%.1fms  p95=%.1fms  max=%.1fms",
                        InpLabel, p50, p95, mx));
  }

//+------------------------------------------------------------------+
int OnCalculate(const int rates_total, const int prev_calculated,
                const datetime &time[], const double &open[], const double &high[],
                const double &low[], const double &close[], const long &tick_volume[],
                const long &volume[], const int &spread[])
  {
   return rates_total;
  }
//+------------------------------------------------------------------+

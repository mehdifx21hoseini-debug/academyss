//+------------------------------------------------------------------+
//|                                               SSR_PumpBudget.mqh |
//|                      SS Replay - Per-Pump Work Ceiling (L2)      |
//|                                                                  |
//|  Replaces SSR_MAX_BARS_PER_PUMP, which was a number somebody      |
//|  typed, with a number the machine reports.                        |
//|                                                                  |
//|  WHY A CEILING EXISTS AT ALL                                      |
//|  Steady replay is cheap - even 50x needs only single-digit ticks  |
//|  per second, so throughput was never the problem the design       |
//|  document assumed. The ceiling is for the BULK moment: a pump     |
//|  arriving after the terminal stalled, or a jump covering hours.    |
//|  Those are the only times one pump can try to do minutes of work  |
//|  in one call, and they are what makes a terminal appear frozen.    |
//+------------------------------------------------------------------+
#ifndef SSR_PUMP_BUDGET_MQH
#define SSR_PUMP_BUDGET_MQH

#include "../Common/SSR_Types.mqh"
#include "SSR_Metrics.mqh"

//--- how long one pump may spend inside the sink. Chosen against human
//--- perception rather than throughput: below roughly 16ms a stall is
//--- invisible, above 50ms it reads as a stutter.
#define SSR_PUMP_BUDGET_MS_DEFAULT   12.0

//--- until the engine has measured itself, these bound the guess
#define SSR_PUMP_MIN_TICKS   32
#define SSR_PUMP_MAX_TICKS   32768

//+------------------------------------------------------------------+
class CSSRPumpBudget
  {
private:
   CSSRMetrics      *m_metrics;    // not owned
   double            m_budget_ms;
   int               m_fallback_ticks;   // used only before calibration
   long              m_deferrals;

public:
                     CSSRPumpBudget(void)
     : m_metrics(NULL), m_budget_ms(SSR_PUMP_BUDGET_MS_DEFAULT),
       m_fallback_ticks(4096), m_deferrals(0) {}

   void              Attach(CSSRMetrics *m) { m_metrics = m; }
   void              SetBudgetMs(const double ms)
     { m_budget_ms = (ms < 1.0 ? 1.0 : ms); }
   double            BudgetMs(void)  { return m_budget_ms; }
   long              Deferrals(void) { return m_deferrals; }

   //+------------------------------------------------------------------+
   //| How many ticks this pump may emit.                               |
   //|                                                                  |
   //| Once calibrated this is budget divided by the measured cost of a |
   //| tick. Before that it is an explicitly bounded fallback, and      |
   //| IsCalibrated() lets the caller say which is in force rather than |
   //| presenting a guess as a measurement.                             |
   //+------------------------------------------------------------------+
   int               MaxTicks(void)
     {
      if(m_metrics == NULL || !m_metrics.IsCalibrated())
         return m_fallback_ticks;

      double us = m_metrics.UsPerTick();
      if(us <= 0.0)
         return m_fallback_ticks;

      double n = (m_budget_ms * 1000.0) / us;
      if(n < SSR_PUMP_MIN_TICKS) n = SSR_PUMP_MIN_TICKS;
      if(n > SSR_PUMP_MAX_TICKS) n = SSR_PUMP_MAX_TICKS;
      return (int)n;
     }

   //--- the same ceiling expressed in M1 bars, for the bar-driven path
   int               MaxBars(const int ticks_per_bar)
     {
      int tpb = (ticks_per_bar < 1 ? 1 : ticks_per_bar);
      int n = MaxTicks() / tpb;
      return (n < 1 ? 1 : n);
     }

   bool              IsCalibrated(void)
     { return (m_metrics != NULL && m_metrics.IsCalibrated()); }

   void              NoteDeferral(void) { m_deferrals++; }

   string            ToString(void)
     {
      return StringFormat("budget[%.0fms -> %d ticks %s deferred=%d]",
                          m_budget_ms, MaxTicks(),
                          (IsCalibrated() ? "measured" : "UNCALIBRATED"),
                          (int)m_deferrals);
     }
  };

#endif // SSR_PUMP_BUDGET_MQH
//+------------------------------------------------------------------+

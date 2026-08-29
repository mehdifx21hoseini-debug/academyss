//+------------------------------------------------------------------+
//|                                                  SSR_Metrics.mqh |
//|                     SS Replay - Engine Self-Measurement (L2)     |
//|                                                                  |
//|  NO PERFORMANCE CLAIM WITHOUT A MEASUREMENT.                     |
//|                                                                  |
//|  Every tuning constant this engine used to carry was a guess: how |
//|  many bars a pump may consume, how large a tick batch should be,  |
//|  how fast a seed runs. This class replaces guessing with the only |
//|  authority that matters - what the machine actually does, on the  |
//|  data actually loaded, while the user is actually watching.       |
//|                                                                  |
//|  Kept deliberately cheap: a ring buffer and a few counters. A     |
//|  measurement system that costs what it measures is worthless.     |
//+------------------------------------------------------------------+
#ifndef SSR_METRICS_MQH
#define SSR_METRICS_MQH

#include "../Common/SSR_Types.mqh"

//--- rolling window for the percentiles. 256 pumps is a few seconds of
//--- playback: long enough that one slow frame does not move p95, short
//--- enough that the figures still describe what is happening NOW.
#define SSR_METRIC_SAMPLES   256

//+------------------------------------------------------------------+
struct SSRPerfSnapshot
  {
   long              pumps;
   long              ticks;
   long              bars;
   double            us_per_tick;
   double            ticks_per_sec;     // sustained, over the sample window
   double            pump_p50_ms;
   double            pump_p95_ms;
   double            pump_max_ms;
   double            seed_bars_per_sec;
   long              deferred_pumps;    // pumps that hit the budget ceiling
   bool              calibrated;

   void              Init(void)
     {
      pumps = 0; ticks = 0; bars = 0;
      us_per_tick = 0.0; ticks_per_sec = 0.0;
      pump_p50_ms = 0.0; pump_p95_ms = 0.0; pump_max_ms = 0.0;
      seed_bars_per_sec = 0.0;
      deferred_pumps = 0;
      calibrated = false;
     }

   string            ToString(void)
     {
      if(!calibrated)
         return "perf[uncalibrated]";
      return StringFormat("perf[%.1f us/tick  p50=%.1fms p95=%.1fms max=%.1fms  "
                          "seed=%.0f bars/s  deferred=%d]",
                          us_per_tick, pump_p50_ms, pump_p95_ms, pump_max_ms,
                          seed_bars_per_sec, (int)deferred_pumps);
     }
  };

//+------------------------------------------------------------------+
class CSSRMetrics
  {
private:
   double            m_pump_ms[SSR_METRIC_SAMPLES];
   int               m_head;
   int               m_filled;

   long              m_pumps;
   long              m_ticks;
   long              m_bars;
   double            m_emit_us_total;      // time spent emitting, not idling
   long              m_emit_ticks_total;   // ticks emitted in that time
   long              m_deferred;

   double            m_seed_bars;
   double            m_seed_ms;

   //--- pumps that emitted nothing say nothing about cost, so they are
   //--- excluded from the per-tick figure rather than diluting it
   bool              HasCost(void) { return (m_emit_ticks_total > 0 && m_emit_us_total > 0.0); }

public:
                     CSSRMetrics(void) { Reset(); }

   void              Reset(void)
     {
      for(int i = 0; i < SSR_METRIC_SAMPLES; i++)
         m_pump_ms[i] = 0.0;
      m_head = 0; m_filled = 0;
      m_pumps = 0; m_ticks = 0; m_bars = 0;
      m_emit_us_total = 0.0; m_emit_ticks_total = 0;
      m_deferred = 0;
      m_seed_bars = 0.0; m_seed_ms = 0.0;
     }

   //+------------------------------------------------------------------+
   //| One pump completed. `emit_us` is the time inside the sink, which |
   //| is the only part the engine can actually influence.              |
   //+------------------------------------------------------------------+
   void              RecordPump(const double total_us, const double emit_us,
                                const int ticks, const int bars,
                                const bool deferred)
     {
      m_pumps++;
      m_ticks += ticks;
      m_bars  += bars;
      if(deferred)
         m_deferred++;

      if(ticks > 0)
        {
         m_emit_us_total    += emit_us;
         m_emit_ticks_total += ticks;
        }

      m_pump_ms[m_head] = total_us / 1000.0;
      m_head = (m_head + 1) % SSR_METRIC_SAMPLES;
      if(m_filled < SSR_METRIC_SAMPLES)
         m_filled++;
     }

   void              RecordSeed(const long bars, const double ms)
     {
      if(bars <= 0 || ms <= 0.0)
         return;
      m_seed_bars += (double)bars;
      m_seed_ms   += ms;
     }

   //--- microseconds one tick costs to push into the sink
   double            UsPerTick(void)
     {
      if(!HasCost())
         return 0.0;
      return m_emit_us_total / (double)m_emit_ticks_total;
     }

   //--- what the sink could sustain if fed continuously
   double            TicksPerSec(void)
     {
      double u = UsPerTick();
      return (u > 0.0 ? 1000000.0 / u : 0.0);
     }

   //+------------------------------------------------------------------+
   //| Measured seed throughput. Feeds the catalogue's cost quote, so   |
   //| the second session a user starts is quoted from the first one    |
   //| rather than from a constant somebody typed.                      |
   //+------------------------------------------------------------------+
   double            SeedBarsPerSec(void)
     {
      if(m_seed_ms <= 0.0)
         return 0.0;
      return m_seed_bars / (m_seed_ms / 1000.0);
     }

   //--- enough samples to be worth believing
   bool              IsCalibrated(void) { return (m_filled >= 16 && HasCost()); }

   double            Percentile(const double p)
     {
      if(m_filled <= 0)
         return 0.0;
      double s[];
      ArrayResize(s, m_filled);
      for(int i = 0; i < m_filled; i++)
         s[i] = m_pump_ms[i];
      ArraySort(s);
      int idx = (int)((double)(m_filled - 1) * p);
      if(idx < 0) idx = 0;
      if(idx >= m_filled) idx = m_filled - 1;
      return s[idx];
     }

   void              Snapshot(SSRPerfSnapshot &out)
     {
      out.Init();
      out.pumps             = m_pumps;
      out.ticks             = m_ticks;
      out.bars              = m_bars;
      out.us_per_tick       = UsPerTick();
      out.ticks_per_sec     = TicksPerSec();
      out.pump_p50_ms       = Percentile(0.50);
      out.pump_p95_ms       = Percentile(0.95);
      out.pump_max_ms       = Percentile(1.00);
      out.seed_bars_per_sec = SeedBarsPerSec();
      out.deferred_pumps    = m_deferred;
      out.calibrated        = IsCalibrated();
     }

   long              Pumps(void)    { return m_pumps; }
   long              Ticks(void)    { return m_ticks; }
   long              Deferred(void) { return m_deferred; }
  };

#endif // SSR_METRICS_MQH
//+------------------------------------------------------------------+

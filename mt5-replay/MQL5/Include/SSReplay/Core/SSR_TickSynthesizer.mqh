//+------------------------------------------------------------------+
//|                                           SSR_TickSynthesizer.mqh |
//|                            SS Replay - Bar to Tick Synthesis(L2) |
//|                                                                  |
//|  Turns one M1 bar into a plausible intrabar path.                |
//|                                                                  |
//|  THE PATH MODEL IS AN ASSUMPTION, AND IT IS DECLARED             |
//|    bullish (close >= open): open -> low  -> high -> close        |
//|    bearish (close <  open): open -> high -> low  -> close        |
//|                                                                  |
//|  The OHLC of the resulting bar is exact - only the ORDER inside  |
//|  the minute is invented. That order decides which of a stop and  |
//|  a target is hit first when a bar touches both, so the trading   |
//|  engine of Phase 9 must treat such trades as ambiguous rather    |
//|  than quietly picking the favourable one.                        |
//|                                                                  |
//|  Adaptive selection between fidelities is Phase 7. This class    |
//|  only synthesises when asked.                                    |
//+------------------------------------------------------------------+
#ifndef SSR_TICK_SYNTHESIZER_MQH
#define SSR_TICK_SYNTHESIZER_MQH

#include "../Common/SSR_Types.mqh"
#include "../Common/SSR_Time.mqh"

//+------------------------------------------------------------------+
class CSSRTickSynthesizer
  {
private:
   int               m_digits;
   double            m_point;
   double            m_spread_abs;
   int               m_ticks_per_bar;

   double            Norm(const double v) { return NormalizeDouble(v, m_digits); }

public:
                     CSSRTickSynthesizer(void)
     : m_digits(5), m_point(0.00001), m_spread_abs(0.0), m_ticks_per_bar(8) {}

   void              Configure(const int digits, const double point)
     {
      m_digits = digits;
      m_point  = (point > 0.0 ? point : MathPow(10, -digits));
     }

   void              SetSpreadPoints(const double points) { m_spread_abs = points * m_point; }
   void              SetSpreadAbs(const double abs)       { m_spread_abs = abs; }

   //--- 4 is the minimum that can express O/H/L/C without losing an extreme
   void              SetTicksPerBar(const int n) { m_ticks_per_bar = (n < 4 ? 4 : n); }
   int               TicksPerBar(void)           { return m_ticks_per_bar; }

   //+------------------------------------------------------------------+
   //| Synthesise the path of one bar, appending into `out` starting at |
   //| `offset`. Returns the number of ticks written.                   |
   //|                                                                  |
   //| `out` must already be sized by the caller - allocating inside a  |
   //| per-bar call is the kind of thing that quietly costs a third of  |
   //| the throughput budget at high speeds.                            |
   //+------------------------------------------------------------------+
   int               Synthesize(const MqlRates &bar, MqlTick &out[], const int offset)
     {
      int n = m_ticks_per_bar;
      if(ArraySize(out) < offset + n)
         return 0;

      double k0 = bar.open;
      double k1, k2;
      if(bar.close >= bar.open) { k1 = bar.low;  k2 = bar.high; }
      else                      { k1 = bar.high; k2 = bar.low;  }
      double k3 = bar.close;

      long base_msc = SSRToMsc(bar.time);
      long span_msc = SSR_MSC_PER_MIN - 1;   // stay inside the minute

      for(int i = 0; i < n; i++)
        {
         //--- position along the three-segment path
         double u = (n == 1 ? 0.0 : (double)i * 3.0 / (double)(n - 1));
         int seg  = (int)MathFloor(u);
         if(seg > 2) seg = 2;
         double f = u - (double)seg;

         double a = (seg == 0 ? k0 : (seg == 1 ? k1 : k2));
         double b = (seg == 0 ? k1 : (seg == 1 ? k2 : k3));
         double p = a + (b - a) * f;

         int idx = offset + i;
         out[idx].time_msc    = base_msc + (long)((double)i * (double)span_msc / (double)MathMax(n - 1, 1));
         out[idx].time        = SSRToTime(out[idx].time_msc);
         out[idx].bid         = Norm(p);
         out[idx].ask         = Norm(p + m_spread_abs);
         out[idx].last        = out[idx].bid;
         out[idx].volume      = 1;
         out[idx].volume_real = 1.0;
         out[idx].flags       = TICK_FLAG_BID | TICK_FLAG_ASK;
        }

      //--- the last tick must land exactly on the close, otherwise the
      //--- replayed bar would not match the source bar
      int last = offset + n - 1;
      out[last].bid  = Norm(bar.close);
      out[last].ask  = Norm(bar.close + m_spread_abs);
      out[last].last = out[last].bid;
      return n;
     }

   //+------------------------------------------------------------------+
   //| SSR_FIDELITY_BAR: one tick, at the bar's close price, stamped    |
   //| at the last instant of the bar.                                  |
   //+------------------------------------------------------------------+
   int               SynthesizeClose(const MqlRates &bar, MqlTick &out[], const int offset)
     {
      if(ArraySize(out) < offset + 1)
         return 0;
      out[offset].time_msc    = SSRToMsc(bar.time) + SSR_MSC_PER_MIN - 1;
      out[offset].time        = SSRToTime(out[offset].time_msc);
      out[offset].bid         = Norm(bar.close);
      out[offset].ask         = Norm(bar.close + m_spread_abs);
      out[offset].last        = out[offset].bid;
      out[offset].volume      = 1;
      out[offset].volume_real = 1.0;
      out[offset].flags       = TICK_FLAG_BID | TICK_FLAG_ASK;
      return 1;
     }

   //--- ticks a given fidelity will produce for one bar; used to size buffers
   int               TicksForBar(const ENUM_SSR_FIDELITY f)
     {
      if(f == SSR_FIDELITY_BAR)
         return 1;
      return m_ticks_per_bar;
     }
  };

#endif // SSR_TICK_SYNTHESIZER_MQH
//+------------------------------------------------------------------+

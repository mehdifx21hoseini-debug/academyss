//+------------------------------------------------------------------+
//|                                              SSR_RiskEngine.mqh  |
//|                        SS Replay - Position Sizing (L2/Trading)  |
//|                                                                  |
//|  Turns "risk 1% with the stop there" into a lot size, using the   |
//|  instrument's own tick value rather than a pip formula that       |
//|  happens to work on EURUSD and quietly lies on an index.          |
//+------------------------------------------------------------------+
#ifndef SSR_RISK_ENGINE_MQH
#define SSR_RISK_ENGINE_MQH

#include "../Common/SSR_Types.mqh"

//+------------------------------------------------------------------+
class CSSRRiskEngine
  {
private:
   double            m_tick_value;   // account currency per tick, per lot
   double            m_tick_size;    // price movement of one tick
   double            m_point;
   double            m_vol_min;
   double            m_vol_max;
   double            m_vol_step;
   int               m_digits;
   string            m_last_reason;

   double            RoundToStep(const double v)
     {
      if(m_vol_step <= 0.0)
         return v;
      return MathFloor(v / m_vol_step + 1e-9) * m_vol_step;
     }

public:
                     CSSRRiskEngine(void)
     : m_tick_value(1.0), m_tick_size(0.00001), m_point(0.00001),
       m_vol_min(0.01), m_vol_max(100.0), m_vol_step(0.01),
       m_digits(5), m_last_reason("") {}

   //--- read the instrument rather than assume it
   void              ConfigureFromSymbol(const string symbol)
     {
      m_digits     = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);
      m_point      = SymbolInfoDouble(symbol, SYMBOL_POINT);
      m_tick_value = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_VALUE);
      m_tick_size  = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_SIZE);
      m_vol_min    = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
      m_vol_max    = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MAX);
      m_vol_step   = SymbolInfoDouble(symbol, SYMBOL_VOLUME_STEP);

      if(m_point <= 0.0)     m_point     = MathPow(10, -m_digits);
      if(m_tick_size <= 0.0) m_tick_size = m_point;
      if(m_tick_value <= 0.0) m_tick_value = 1.0;
      if(m_vol_min <= 0.0)   m_vol_min   = 0.01;
      if(m_vol_max <= 0.0)   m_vol_max   = 100.0;
      if(m_vol_step <= 0.0)  m_vol_step  = 0.01;
     }

   void              Configure(const double tick_value, const double tick_size,
                               const double vol_min, const double vol_max,
                               const double vol_step, const int digits)
     {
      m_tick_value = (tick_value > 0.0 ? tick_value : 1.0);
      m_tick_size  = (tick_size  > 0.0 ? tick_size  : MathPow(10, -digits));
      m_vol_min    = (vol_min    > 0.0 ? vol_min    : 0.01);
      m_vol_max    = (vol_max    > 0.0 ? vol_max    : 100.0);
      m_vol_step   = (vol_step   > 0.0 ? vol_step   : 0.01);
      m_digits     = digits;
      m_point      = MathPow(10, -digits);
     }

   string            LastReason(void) { return m_last_reason; }
   double            VolMin(void)     { return m_vol_min; }
   double            VolMax(void)     { return m_vol_max; }

   //+------------------------------------------------------------------+
   //| Money lost if `volume` moves `price_distance` against you.       |
   //+------------------------------------------------------------------+
   double            RiskOf(const double volume, const double price_distance)
     {
      if(m_tick_size <= 0.0)
         return 0.0;
      double ticks = MathAbs(price_distance) / m_tick_size;
      return ticks * m_tick_value * volume;
     }

   //+------------------------------------------------------------------+
   //| Lot size for a percentage of an account, given the stop.         |
   //|                                                                  |
   //| Rounds DOWN to the volume step. Rounding up would quietly risk   |
   //| more than asked, and "1%" that is sometimes 1.3% is not a risk   |
   //| model - it is a bug with a friendly name.                        |
   //+------------------------------------------------------------------+
   double            LotForRisk(const double balance, const double risk_percent,
                                const double entry, const double stop)
     {
      m_last_reason = "";
      double dist = MathAbs(entry - stop);
      if(dist <= 0.0)
        {
         m_last_reason = "stop is at the entry price";
         return 0.0;
        }
      if(balance <= 0.0 || risk_percent <= 0.0)
        {
         m_last_reason = "no balance or no risk to spend";
         return 0.0;
        }

      double money       = balance * risk_percent / 100.0;
      double per_lot     = RiskOf(1.0, dist);
      if(per_lot <= 0.0)
        {
         m_last_reason = "instrument tick value is unusable";
         return 0.0;
        }

      double lot = RoundToStep(money / per_lot);

      if(lot < m_vol_min)
        {
         //--- refuse rather than silently trade a size that risks more
         //--- than the user allowed
         m_last_reason = StringFormat(
            "%.2f%% of %.2f is %.2f, below the minimum lot (%.2f would risk %.2f)",
            risk_percent, balance, money, m_vol_min, RiskOf(m_vol_min, dist));
         return 0.0;
        }
      if(lot > m_vol_max)
        {
         lot = m_vol_max;
         m_last_reason = "capped at the maximum lot";
        }
      return lot;
     }

   //--- what fraction of the account a given trade actually risks
   double            RiskPercentOf(const double balance, const double volume,
                                   const double entry, const double stop)
     {
      if(balance <= 0.0)
         return 0.0;
      return RiskOf(volume, MathAbs(entry - stop)) / balance * 100.0;
     }

   //--- money value of a price move, used for P/L and for R multiples
   double            MoneyOf(const double volume, const double price_move)
     { return RiskOf(volume, price_move) * (price_move < 0.0 ? -1.0 : 1.0); }
  };

#endif // SSR_RISK_ENGINE_MQH
//+------------------------------------------------------------------+

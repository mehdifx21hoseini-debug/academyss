//+------------------------------------------------------------------+
//|                                            SSR_RefStrategy.mqh   |
//|                  SS Replay - A Reference Strategy (L3)           |
//|                                                                  |
//|  NOT A TRADING RECOMMENDATION. A break of the last N bars' range |
//|  is the simplest rule that exercises every part of the contract, |
//|  which is the only reason it is the one written here. The        |
//|  academy's own methods go beside it; this exists so that when    |
//|  they are written, the shape they must take is already shown.    |
//|                                                                  |
//|  WHAT IT DEMONSTRATES, and every line of it is the point:        |
//|                                                                  |
//|   - decisions on OnBar, so nothing is decided on a bar that is    |
//|     still moving                                                 |
//|   - shift 1, never shift 0, because shift 0 is not finished       |
//|   - Available() checked BEFORE reading, and a refusal ends the    |
//|     bar rather than being treated as a zero                       |
//|   - size from risk, through the same engine the manual trader     |
//|     uses, so two sizing formulas cannot drift apart               |
//|   - MyOpenCount(), so it manages what it opened and nothing else  |
//|   - ctx.IsSynthetic() consulted, and the answer written into the  |
//|     status line rather than ignored                               |
//+------------------------------------------------------------------+
#ifndef SSR_REF_STRATEGY_MQH
#define SSR_REF_STRATEGY_MQH

#include "SSR_IStrategy.mqh"

//+------------------------------------------------------------------+
class CSSRRefBreakout : public CSSRStrategy
  {
private:
   ENUM_TIMEFRAMES   m_tf;
   int               m_lookback;
   double            m_risk_percent;
   double            m_stop_buffer;    // in points, beyond the opposite side

   long              m_signals;
   long              m_skipped_no_data;
   string            m_state;

public:
                     CSSRRefBreakout(void)
     : m_tf(PERIOD_M15), m_lookback(20), m_risk_percent(0.5),
       m_stop_buffer(0.0), m_signals(0), m_skipped_no_data(0),
       m_state("waiting") {}

   virtual string    Name(void) override { return "ref-breakout"; }

   void              Configure(const ENUM_TIMEFRAMES tf, const int lookback,
                               const double risk_percent,
                               const double stop_buffer_points = 0.0)
     {
      m_tf           = tf;
      m_lookback     = (lookback < 2 ? 2 : lookback);
      m_risk_percent = risk_percent;
      m_stop_buffer  = stop_buffer_points;
     }

   long              Signals(void)      { return m_signals; }
   long              SkippedNoData(void){ return m_skipped_no_data; }

   virtual void      OnStart(void) override
     {
      m_signals         = 0;
      m_skipped_no_data = 0;
      m_state           = "waiting";
     }

   //+------------------------------------------------------------------+
   //| One decision per closed bar.                                     |
   //+------------------------------------------------------------------+
   virtual void      OnBar(void) override
     {
      if(ctx == NULL || ctx.market == NULL || ctx.broker == NULL)
         return;

      //--- one position at a time, and only ever MY position
      if(ctx.broker.MyOpenCount() > 0)
        { m_state = "in a trade"; return; }

      //--- ASK FIRST. The lookback plus the bar we act on: if the view
      //--- cannot serve all of it, this bar is skipped. A range from
      //--- eleven bars when twenty were asked for is a different
      //--- number wearing the same name.
      if(ctx.market.Available(m_tf) < m_lookback + 2)
        {
         m_skipped_no_data++;
         m_state = "not enough history yet";
         return;
        }

      //--- shift 1 is the bar that just CLOSED. Shift 0 is still moving
      //--- and acting on it is look-ahead by another name.
      MqlRates last;
      if(!ctx.market.Bar(m_tf, 1, last))
        { m_skipped_no_data++; m_state = "view refused the closed bar"; return; }

      //--- and the range BEFORE it, so the bar that broke out is not
      //--- part of the range it broke
      double hi = 0.0, lo = 0.0;
      if(!ctx.market.HighestHigh(m_tf, 2, m_lookback, hi) ||
         !ctx.market.LowestLow(m_tf, 2, m_lookback, lo))
        { m_skipped_no_data++; m_state = "view refused the range"; return; }
      if(hi <= lo)
        { m_state = "flat range"; return; }

      double buf = m_stop_buffer * ctx.market.Point();

      if(last.close > hi)
        {
         //--- the stop goes on the far side of the range that was
         //--- broken, which is what makes the risk figure meaningful
         double sl = lo - buf;
         if(sl <= 0.0 || sl >= ctx.market.Bid())
           { m_state = "stop would be the wrong side of price"; return; }
         if(ctx.broker.BuyRisk(m_risk_percent, sl) > 0)
           { m_signals++; m_state = "long on a break of " + DoubleToString(hi, 5); }
         else
            m_state = "long refused: " + ctx.broker.LastError();
         return;
        }

      if(last.close < lo)
        {
         double sl = hi + buf;
         if(sl <= ctx.market.Ask())
           { m_state = "stop would be the wrong side of price"; return; }
         if(ctx.broker.SellRisk(m_risk_percent, sl) > 0)
           { m_signals++; m_state = "short on a break of " + DoubleToString(lo, 5); }
         else
            m_state = "short refused: " + ctx.broker.LastError();
         return;
        }

      m_state = "inside the range";
     }

   //--- a rewind un-happens trades this strategy may have counted
   virtual void      OnRewind(const long msc) override
     { m_state = "rewound"; }

   //+------------------------------------------------------------------+
   //| What it is thinking - AND what its data is worth.                |
   //|                                                                  |
   //| The second half is not decoration. This strategy acts on bar     |
   //| closes, which are exact whether the ticks were real or invented, |
   //| but its STOPS are resolved intrabar - and on synthetic ticks the |
   //| order those prices arrived in is an assumption.                  |
   //+------------------------------------------------------------------+
   virtual string    Status(void) override
     {
      string s = m_state;
      if(ctx != NULL && ctx.IsSynthetic())
         s += "  [intrabar order assumed]";
      return s;
     }
  };

#endif // SSR_REF_STRATEGY_MQH
//+------------------------------------------------------------------+

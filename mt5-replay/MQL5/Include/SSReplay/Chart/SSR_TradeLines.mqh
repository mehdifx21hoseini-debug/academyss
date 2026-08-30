//+------------------------------------------------------------------+
//|                                              SSR_TradeLines.mqh  |
//|                        SS Replay - the stop and target, as lines |
//|                                                                  |
//|  A trader draws a stop. They do not count points into a stepper. |
//|  Reaching 200 points through a +5 button costs twenty-five       |
//|  clicks, and at the end of it the number still is not a place on |
//|  the chart - which is the only form a stop actually has.         |
//|                                                                  |
//|  THE EVENT PROBLEM, AND WHY THIS POLLS.                          |
//|                                                                  |
//|  MetaTrader delivers OnChartEvent only to the chart a program is |
//|  attached to. These lines live on the REPLAY chart; the engine    |
//|  lives on the host chart. No drag event will ever reach it.       |
//|                                                                  |
//|  So this does not listen. It reads. Once per timer tick it asks  |
//|  each line where it is now, and if the user has moved one, the   |
//|  answer is different. A dragged object updates its own price      |
//|  whether anyone was listening or not, which makes polling here    |
//|  the correct mechanism rather than a workaround for a missing     |
//|  one.                                                            |
//|                                                                  |
//|  The distance is recomputed against the live replay price every  |
//|  poll, so the lot size follows the market as well as the line.   |
//|  A stop is a PLACE, and its distance is a consequence.           |
//+------------------------------------------------------------------+
#ifndef SSR_TRADE_LINES_MQH
#define SSR_TRADE_LINES_MQH

#include "../Common/SSR_Types.mqh"

//+------------------------------------------------------------------+
class CSSRTradeLines
  {
private:
   long              m_chart;
   int               m_digits;
   double            m_point;
   bool              m_armed;

   string            m_sl_name;
   string            m_tp_name;
   double            m_sl_price;
   double            m_tp_price;
   color             m_sl_col;
   color             m_tp_col;
   color             m_long_col;
   color             m_short_col;
   long              m_seen[];       // tickets drawn in the current sweep

   //--- a plain price level; positions are not draggable, they are a
   //--- record of what happened
   void              Level(const string n, const double price, const color col,
                           const int style, const int width, const string tip)
     {
      if(ObjectFind(m_chart, n) < 0)
        {
         if(!ObjectCreate(m_chart, n, OBJ_HLINE, 0, 0, price))
            return;
         ObjectSetInteger(m_chart, n, OBJPROP_SELECTABLE, false);
         ObjectSetInteger(m_chart, n, OBJPROP_HIDDEN,     true);
         ObjectSetInteger(m_chart, n, OBJPROP_BACK,       true);
        }
      ObjectSetInteger(m_chart, n, OBJPROP_COLOR,   col);
      ObjectSetInteger(m_chart, n, OBJPROP_STYLE,   style);
      ObjectSetInteger(m_chart, n, OBJPROP_WIDTH,   width);
      ObjectSetString (m_chart, n, OBJPROP_TOOLTIP, tip);
      ObjectSetDouble (m_chart, n, OBJPROP_PRICE,   price);
     }

   //--- draggable means SELECTABLE. Everything else about these lines
   //--- is defensive: they sit behind the candles, they never join a
   //--- template, and they are named so a leak scan can find them.
   bool              Ensure(const string n, const double price,
                            const color col, const string tip)
     {
      if(m_chart == 0 || price <= 0.0)
         return false;

      if(ObjectFind(m_chart, n) < 0)
        {
         if(!ObjectCreate(m_chart, n, OBJ_HLINE, 0, 0, price))
            return false;
         ObjectSetInteger(m_chart, n, OBJPROP_WIDTH,      1);
         ObjectSetInteger(m_chart, n, OBJPROP_BACK,       false);
         ObjectSetInteger(m_chart, n, OBJPROP_SELECTABLE, true);
         ObjectSetInteger(m_chart, n, OBJPROP_SELECTED,   false);
         ObjectSetInteger(m_chart, n, OBJPROP_HIDDEN,     true);
         ObjectSetInteger(m_chart, n, OBJPROP_ZORDER,     0);
        }
      ObjectSetInteger(m_chart, n, OBJPROP_COLOR,   col);
      ObjectSetInteger(m_chart, n, OBJPROP_STYLE,   STYLE_DASHDOT);
      ObjectSetString (m_chart, n, OBJPROP_TOOLTIP, tip);
      ObjectSetDouble (m_chart, n, OBJPROP_PRICE,   price);
      return true;
     }

   double            Read(const string n)
     {
      if(m_chart == 0 || ObjectFind(m_chart, n) < 0)
         return 0.0;
      return ObjectGetDouble(m_chart, n, OBJPROP_PRICE);
     }

public:
                     CSSRTradeLines(void)
     : m_chart(0), m_digits(0), m_point(0.0), m_armed(false),
       m_sl_name("SSR_LINE_SL"), m_tp_name("SSR_LINE_TP"),
       m_sl_price(0.0), m_tp_price(0.0),
       m_sl_col(clrTomato), m_tp_col(clrMediumSeaGreen),
       m_long_col(clrDodgerBlue), m_short_col(clrOrange) {}

                    ~CSSRTradeLines(void) { Clear(); }

   void              Attach(const long chart_id, const int digits,
                            const double point,
                            const color sl_col, const color tp_col)
     {
      m_chart  = chart_id;
      m_digits = digits;
      m_point  = (point > 0.0 ? point : 1.0);
      m_sl_col = sl_col;
      m_tp_col = tp_col;
     }

   bool              IsArmed(void)  { return m_armed; }
   double            SlPrice(void)  { return m_sl_price; }
   double            TpPrice(void)  { return m_tp_price; }

   //+------------------------------------------------------------------+
   //| Put both lines somewhere a trader would actually start from.     |
   //|                                                                  |
   //| Not zero, which arms nothing, and not five points, which is      |
   //| inside the spread on most instruments. `stop_points` is a real   |
   //| distance and the target follows it by `rr`.                      |
   //+------------------------------------------------------------------+
   bool              Arm(const double price, const double stop_points,
                         const double rr)
     {
      return ArmSide(price, stop_points, rr, true);
     }

   //--- the same thing for a short: stop ABOVE, target BELOW. Flip is a
   //--- real re-place rather than a repaint, because the two prices are
   //--- what the trade is sized and filled from.
   bool              ArmSide(const double price, const double stop_points,
                             const double rr, const bool is_long)
     {
      if(m_chart == 0 || price <= 0.0 || stop_points <= 0.0)
         return false;

      double dist = stop_points * m_point;
      double  rew = dist * (rr > 0.0 ? rr : 1.0);
      m_sl_price  = NormalizeDouble(is_long ? price - dist : price + dist, m_digits);
      m_tp_price  = NormalizeDouble(is_long ? price + rew  : price - rew,  m_digits);

      bool a = Ensure(m_sl_name, m_sl_price, m_sl_col, "STOP - drag me");
      bool b = Ensure(m_tp_name, m_tp_price, m_tp_col, "TARGET - drag me");
      m_armed = (a && b);
      if(m_armed)
         ChartRedraw(m_chart);
      return m_armed;
     }

   //--- the +/- buttons still work; they move the line rather than
   //--- edit a number that has nothing to do with the chart
   bool              SetStopPoints(const double price, const double points)
     {
      if(!m_armed || price <= 0.0 || points <= 0.0)
         return false;
      double keep_rr = RewardRatio(price);
      m_sl_price = NormalizeDouble(price - points * m_point, m_digits);
      m_tp_price = NormalizeDouble(price + points * m_point *
                                   (keep_rr > 0.0 ? keep_rr : 1.0), m_digits);
      Ensure(m_sl_name, m_sl_price, m_sl_col, "STOP - drag me");
      Ensure(m_tp_name, m_tp_price, m_tp_col, "TARGET - drag me");
      ChartRedraw(m_chart);
      return true;
     }

   //+------------------------------------------------------------------+
   //| Ask the lines where they are. Returns true when one has moved.   |
   //+------------------------------------------------------------------+
   bool              Poll(void)
     {
      if(!m_armed)
         return false;

      double sl = Read(m_sl_name);
      double tp = Read(m_tp_name);

      //--- a line the user deleted is not a line at zero: re-place it
      //--- where it was rather than silently disarming the stop
      if(sl <= 0.0 || tp <= 0.0)
        {
         Ensure(m_sl_name, m_sl_price, m_sl_col, "STOP - drag me");
         Ensure(m_tp_name, m_tp_price, m_tp_col, "TARGET - drag me");
         return false;
        }

      bool moved = (MathAbs(sl - m_sl_price) > m_point * 0.5 ||
                    MathAbs(tp - m_tp_price) > m_point * 0.5);
      m_sl_price = sl;
      m_tp_price = tp;
      return moved;
     }

   //--- how far the stop is from here, in points. The number the risk
   //--- engine needs, derived from the place the user chose.
   double            StopPointsFrom(const double price)
     {
      if(!m_armed || price <= 0.0 || m_sl_price <= 0.0)
         return 0.0;
      return MathAbs(price - m_sl_price) / m_point;
     }

   double            RewardRatio(const double price)
     {
      double risk = MathAbs(price - m_sl_price);
      if(risk <= 0.0)
         return 0.0;
      return MathAbs(m_tp_price - price) / risk;
     }

   //--- which side the stop sits on, so the panel can say what the
   //--- lines currently describe rather than leaving the user to guess
   bool              IsLongSetup(const double price)
     { return (m_armed && m_sl_price > 0.0 && m_sl_price < price); }

   //+------------------------------------------------------------------+
   //| OPEN POSITIONS, DRAWN THE WAY THE PLATFORM DRAWS REAL ONES.      |
   //|                                                                  |
   //| A virtual trade that exists only as a number in a panel asks the |
   //| user to hold the whole position in their head. The point of      |
   //| practising on a chart is to read it off the chart.               |
   //|                                                                  |
   //| Deliberately NOT typed against the trading layer: this file is   |
   //| in Chart, which depends on Common and nothing else. It takes     |
   //| prices and a ticket number, and the host - which knows both      |
   //| sides - does the walking.                                        |
   //|                                                                  |
   //| Begin / Draw* / End is a sweep: anything not redrawn this pass   |
   //| was closed, and its lines go with it.                            |
   //+------------------------------------------------------------------+
   void              BeginPositions(void)
     {
      ArrayResize(m_seen, 0);
     }

   bool              DrawPosition(const long ticket, const double entry,
                                  const double sl, const double tp,
                                  const bool is_long, const double volume)
     {
      if(m_chart == 0 || entry <= 0.0)
         return false;

      int k = ArraySize(m_seen);
      ArrayResize(m_seen, k + 1);
      m_seen[k] = ticket;

      string base = "SSR_POS_" + IntegerToString((int)ticket);
      string side = (is_long ? "BUY" : "SELL");
      string tip  = StringFormat("%s %.2f @ %s", side, volume,
                                 DoubleToString(entry, m_digits));

      Level(base + "_E", entry, (is_long ? m_long_col : m_short_col),
            STYLE_SOLID, 2, tip);

      if(sl > 0.0)
         Level(base + "_S", sl, m_sl_col, STYLE_DOT, 1,
               "stop of " + IntegerToString((int)ticket));
      else
         ObjectDelete(m_chart, base + "_S");

      if(tp > 0.0)
         Level(base + "_T", tp, m_tp_col, STYLE_DOT, 1,
               "target of " + IntegerToString((int)ticket));
      else
         ObjectDelete(m_chart, base + "_T");

      return true;
     }

   void              EndPositions(void)
     {
      if(m_chart == 0)
         return;

      //--- sweep: an object for a ticket nobody drew this pass belongs
      //--- to a position that has closed
      int total = ObjectsTotal(m_chart, 0, OBJ_HLINE);
      for(int i = total - 1; i >= 0; i--)
        {
         string n = ObjectName(m_chart, i, 0, OBJ_HLINE);
         if(StringFind(n, "SSR_POS_") != 0)
            continue;

         //--- SSR_POS_<ticket>_X
         string rest = StringSubstr(n, 8);
         int    us   = StringFind(rest, "_");
         if(us <= 0)
            continue;
         long tk = StringToInteger(StringSubstr(rest, 0, us));

         bool alive = false;
         for(int j = 0; j < ArraySize(m_seen); j++)
            if(m_seen[j] == tk)
              { alive = true; break; }

         if(!alive)
            ObjectDelete(m_chart, n);
        }
      ChartRedraw(m_chart);
     }

   void              Clear(void)
     {
      if(m_chart == 0)
         return;
      ObjectDelete(m_chart, m_sl_name);
      ObjectDelete(m_chart, m_tp_name);
      ArrayResize(m_seen, 0);
      EndPositions();
      m_armed = false;
     }
  };

#endif // SSR_TRADE_LINES_MQH
//+------------------------------------------------------------------+

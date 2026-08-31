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
                           const int style, const int width, const string tip,
                           const string label = "")
     {
      if(ObjectFind(m_chart, n) < 0)
        {
         if(!ObjectCreate(m_chart, n, OBJ_HLINE, 0, 0, price))
            return;
         ObjectSetInteger(m_chart, n, OBJPROP_SELECTABLE, false);
         ObjectSetInteger(m_chart, n, OBJPROP_HIDDEN,     true);
         //--- MetaTrader draws trade levels OVER the candles, not behind
         //--- them. Behind, a level crossing a dense area disappears
         //--- into it - which is exactly where a stop matters most.
         ObjectSetInteger(m_chart, n, OBJPROP_BACK,       false);
        }
      ObjectSetInteger(m_chart, n, OBJPROP_COLOR,   col);
      ObjectSetInteger(m_chart, n, OBJPROP_STYLE,   style);
      ObjectSetInteger(m_chart, n, OBJPROP_WIDTH,   width);
      ObjectSetString (m_chart, n, OBJPROP_TOOLTIP, tip);
      //--- the text MetaTrader prints beside its own position lines. It
      //--- only shows while the chart is set to draw descriptions, which
      //--- Attach turns on, so a level is readable without hovering it.
      ObjectSetString (m_chart, n, OBJPROP_TEXT, label == "" ? tip : label);
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
         ObjectSetInteger(m_chart, n, OBJPROP_HIDDEN,     true);
         ObjectSetInteger(m_chart, n, OBJPROP_ZORDER,     0);
        }
      ObjectSetInteger(m_chart, n, OBJPROP_COLOR,   col);
      ObjectSetInteger(m_chart, n, OBJPROP_STYLE,   STYLE_DASHDOT);
      ObjectSetString (m_chart, n, OBJPROP_TOOLTIP, tip);
      //+------------------------------------------------------------------+
      //| SELECTED, SO THE FIRST TOUCH DRAGS IT.                           |
      //|                                                                  |
      //| A MetaTrader object has to be selected before it can be moved,   |
      //| so an unselected stop line costs a click to arm and a second     |
      //| drag to use - and in between, the click lands on the chart and    |
      //| does nothing visible. On a real trade level MetaTrader asks for   |
      //| neither: you grab it and it moves.                                |
      //|                                                                  |
      //| These two lines exist ONLY to be dragged, so there is nothing     |
      //| for selection to disambiguate. Selected is their resting state.   |
      //+------------------------------------------------------------------+
      ObjectSetInteger(m_chart, n, OBJPROP_SELECTED, true);
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
      //--- without this the descriptions exist and nothing shows them,
      //--- which is the same as not having written them
      ChartSetInteger(m_chart, CHART_SHOW_OBJECT_DESCR, true);
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
      //+------------------------------------------------------------------+
      //| WHICH SIDE THE LINES ARE ALREADY ON DECIDES WHERE THEY GO.       |
      //|                                                                  |
      //| This was hardcoded long: stop below, target above, every time.   |
      //| The host read the stop distance off the chart and fed it back    |
      //| here on every pump, so a stop dragged ABOVE the price was pushed  |
      //| back below it within forty milliseconds - and a short setup was  |
      //| impossible to build with a mouse. The user's recording shows     |
      //| them arming the lines nine times and never once reaching the     |
      //| Open button.                                                     |
      //|                                                                  |
      //| Flip did not rescue it either: it re-placed the lines short, and |
      //| the very next pump dragged them back.                            |
      //+------------------------------------------------------------------+
      bool   is_long = (m_sl_price > 0.0 ? (m_sl_price < price) : true);
      double keep_rr = RewardRatio(price);
      double dist    = points * m_point;
      double rew     = dist * (keep_rr > 0.0 ? keep_rr : 1.0);
      m_sl_price = NormalizeDouble(is_long ? price - dist : price + dist, m_digits);
      m_tp_price = NormalizeDouble(is_long ? price + rew  : price - rew,  m_digits);
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

      //--- and keep them selected. Clicking anywhere else on the chart
      //--- clears the selection, and a line that silently stops being
      //--- draggable after one stray click is the same defect arriving
      //--- a minute later.
      if(!ObjectGetInteger(m_chart, m_sl_name, OBJPROP_SELECTED))
         ObjectSetInteger(m_chart, m_sl_name, OBJPROP_SELECTED, true);
      if(!ObjectGetInteger(m_chart, m_tp_name, OBJPROP_SELECTED))
         ObjectSetInteger(m_chart, m_tp_name, OBJPROP_SELECTED, true);

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

      //+------------------------------------------------------------------+
      //| WORDED, STYLED AND COLOURED THE WAY THE PLATFORM DOES IT.        |
      //|                                                                  |
      //| Side by side with a real MetaTrader position, ours read as a     |
      //| different product: "#12 buy 0.21 4438.48" against MetaTrader's   |
      //| "BUY 0.2 at 53226", solid against dash-dot, our palette against  |
      //| the one the user chose in the platform's own settings.           |
      //|                                                                  |
      //| CHART_COLOR_STOP_LEVEL is that setting - it is documented as the |
      //| colour of the Stop Loss and Take Profit levels - so asking the   |
      //| chart for it means these levels match every other trade level    |
      //| the user has ever seen, on whatever scheme they run.             |
      //+------------------------------------------------------------------+
      string base = "SSR_POS_" + IntegerToString((int)ticket);
      string side = (is_long ? "BUY" : "SELL");
      string tip  = StringFormat("%s %s at %s", side,
                                 DoubleToString(volume, 2),
                                 DoubleToString(entry, m_digits));

      color stop_col = (color)ChartGetInteger(m_chart, CHART_COLOR_STOP_LEVEL);
      if(stop_col == clrNONE || stop_col == (color)ChartGetInteger(m_chart, CHART_COLOR_BACKGROUND))
         stop_col = m_sl_col;      // an invisible level is not a level

      Level(base + "_E", entry, (is_long ? m_long_col : m_short_col),
            STYLE_DASHDOT, 1, tip, tip);

      if(sl > 0.0)
         Level(base + "_S", sl, stop_col, STYLE_DASHDOT, 1,
               StringFormat("stop of %s %s at %s", side,
                            DoubleToString(volume, 2),
                            DoubleToString(sl, m_digits)),
               "SL");
      else
         ObjectDelete(m_chart, base + "_S");

      if(tp > 0.0)
         Level(base + "_T", tp, stop_col, STYLE_DASHDOT, 1,
               StringFormat("target of %s %s at %s", side,
                            DoubleToString(volume, 2),
                            DoubleToString(tp, m_digits)),
               "TP");
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

   //+------------------------------------------------------------------+
   //| TAKE THE PLANNING LINES AWAY AND LEAVE THE TRADE ALONE.          |
   //|                                                                  |
   //| Opening from the lines used to call Clear(), which also swept    |
   //| every position line off the chart - and because the host only    |
   //| drew positions while the planning lines were armed, and Clear    |
   //| disarms, the stop and target of the trade just opened were never |
   //| drawn again. The user pressed a button and watched the whole     |
   //| trade disappear from the chart it was placed on.                 |
   //|                                                                  |
   //| Once the order is placed, the two draggable lines have done      |
   //| their job. The position's own levels take over: they are a       |
   //| record, not a proposal, which is why they are not draggable.     |
   //+------------------------------------------------------------------+
   //+------------------------------------------------------------------+
   //| A CLOSED TRADE STAYS ON THE CHART.                               |
   //|                                                                  |
   //| MetaTrader draws a finished deal as two arrows joined by a line,  |
   //| and that is not decoration: it is how a trader reviews what they  |
   //| did. A replay whose trades vanish the moment they close makes the |
   //| user reconstruct the session from a table afterwards, which is    |
   //| exactly the work practising on a chart is supposed to replace.    |
   //|                                                                  |
   //| The exit arrow points the opposite way to the entry, because the  |
   //| closing deal genuinely is the opposite side.                      |
   //|                                                                  |
   //| Drawn once and left alone: history does not change, so a redraw   |
   //| every pass would be work with nothing to show for it.             |
   //+------------------------------------------------------------------+
   bool              DrawClosed(const long ticket,
                                const datetime open_time, const double open_price,
                                const datetime close_time, const double close_price,
                                const bool is_long, const double volume,
                                const double net)
     {
      if(m_chart == 0 || open_price <= 0.0 || close_price <= 0.0)
         return false;
      if(open_time <= 0 || close_time <= 0)
         return false;

      string base = "SSR_HIST_" + IntegerToString((int)ticket);
      if(ObjectFind(m_chart, base + "_L") >= 0)
         return true;                       // already on the chart

      color won = (net >= 0.0 ? clrMediumSeaGreen : clrTomato);

      //+------------------------------------------------------------------+
      //| BIG ENOUGH TO SEE.                                               |
      //|                                                                  |
      //| A screen recording settled this: the arrows were drawn, correctly |
      //| placed and the right colours - and at their default size they     |
      //| read as two specks on a candle. Six pixels of orange is not a     |
      //| record of a trade, it is a smudge, and "it draws" was true while  |
      //| "you can see it" was not.                                          |
      //|                                                                  |
      //| Width 3 on the arrows and 2 on the line between them, because     |
      //| when entry and exit fall inside one bar - which is most trades on |
      //| a higher timeframe - that line is all there is to join them.       |
      //+------------------------------------------------------------------+
      string a = base + "_A";
      if(ObjectCreate(m_chart, a, (is_long ? OBJ_ARROW_BUY : OBJ_ARROW_SELL),
                      0, open_time, open_price))
        {
         ObjectSetInteger(m_chart, a, OBJPROP_COLOR, (is_long ? m_long_col : m_short_col));
         ObjectSetInteger(m_chart, a, OBJPROP_WIDTH, 3);
         ObjectSetInteger(m_chart, a, OBJPROP_ANCHOR, ANCHOR_TOP);
         ObjectSetInteger(m_chart, a, OBJPROP_SELECTABLE, false);
         ObjectSetInteger(m_chart, a, OBJPROP_HIDDEN, true);
         ObjectSetString (m_chart, a, OBJPROP_TOOLTIP,
                          StringFormat("#%d %s %s in at %s", (int)ticket,
                                       (is_long ? "buy" : "sell"),
                                       DoubleToString(volume, 2),
                                       DoubleToString(open_price, m_digits)));
        }

      string b = base + "_B";
      if(ObjectCreate(m_chart, b, (is_long ? OBJ_ARROW_SELL : OBJ_ARROW_BUY),
                      0, close_time, close_price))
        {
         ObjectSetInteger(m_chart, b, OBJPROP_COLOR, won);
         ObjectSetInteger(m_chart, b, OBJPROP_WIDTH, 3);
         ObjectSetInteger(m_chart, b, OBJPROP_ANCHOR, ANCHOR_TOP);
         ObjectSetInteger(m_chart, b, OBJPROP_SELECTABLE, false);
         ObjectSetInteger(m_chart, b, OBJPROP_HIDDEN, true);
         ObjectSetString (m_chart, b, OBJPROP_TOOLTIP,
                          StringFormat("#%d out at %s   %s%.2f", (int)ticket,
                                       DoubleToString(close_price, m_digits),
                                       (net >= 0.0 ? "+" : ""), net));
        }

      string l = base + "_L";
      if(ObjectCreate(m_chart, l, OBJ_TREND, 0,
                      open_time, open_price, close_time, close_price))
        {
         ObjectSetInteger(m_chart, l, OBJPROP_COLOR,      won);
         ObjectSetInteger(m_chart, l, OBJPROP_STYLE,      STYLE_SOLID);
         ObjectSetInteger(m_chart, l, OBJPROP_WIDTH,      2);
         ObjectSetInteger(m_chart, l, OBJPROP_RAY_RIGHT,  false);
         ObjectSetInteger(m_chart, l, OBJPROP_RAY_LEFT,   false);
         //--- in front, like every other trade level here. Behind, a
         //--- trade that happened inside one candle is hidden by it.
         ObjectSetInteger(m_chart, l, OBJPROP_BACK,       false);
         ObjectSetInteger(m_chart, l, OBJPROP_SELECTABLE, false);
         ObjectSetInteger(m_chart, l, OBJPROP_HIDDEN,     true);
        }
      return true;
     }

   //--- history belongs to the session, so it goes when the session does
   void              ClearHistory(void)
     {
      if(m_chart == 0)
         return;
      for(int i = ObjectsTotal(m_chart, -1, -1) - 1; i >= 0; i--)
        {
         string n = ObjectName(m_chart, i, -1, -1);
         if(StringFind(n, "SSR_HIST_") == 0)
            ObjectDelete(m_chart, n);
        }
     }

   void              Disarm(void)
     {
      if(m_chart == 0)
         return;
      ObjectDelete(m_chart, m_sl_name);
      ObjectDelete(m_chart, m_tp_name);
      m_armed = false;
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
      ClearHistory();
      m_armed = false;
     }
  };

#endif // SSR_TRADE_LINES_MQH
//+------------------------------------------------------------------+

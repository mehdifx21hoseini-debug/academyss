//+------------------------------------------------------------------+
//|                                            SSR_CalendarLines.mqh |
//|                    SS Replay - The News, On The Chart (L3/Chart) |
//|                                                                  |
//|  One vertical line per scheduled release, drawn ONCE. They do not |
//|  move, so nothing here polls: the sweep returns immediately for   |
//|  every line that already exists, and the whole class costs one    |
//|  ObjectFind per event per call.                                   |
//|                                                                  |
//|  THE FUTURE IS DRAWN ON PURPOSE. A replay that only revealed a    |
//|  release once the clock reached it would be teaching the opposite |
//|  of the skill: a real trader knows the calendar days ahead, and   |
//|  deciding not to be in a trade at 15:30 is most of what the       |
//|  calendar is for.                                                 |
//|                                                                  |
//|  BLIND MODE IS THE EXCEPTION and the host enforces it. A line     |
//|  labelled "USD Non-Farm Payrolls" on a date the mode exists to    |
//|  hide would give away the whole session in one object.            |
//+------------------------------------------------------------------+
#ifndef SSR_CALENDAR_LINES_MQH
#define SSR_CALENDAR_LINES_MQH

#include "../Common/SSR_Types.mqh"
#include "../Data/SSR_Calendar.mqh"

#define SSR_CAL_PREFIX  "SSR_NEWS_"

//+------------------------------------------------------------------+
class CSSRCalendarLines
  {
private:
   long              m_chart;
   int               m_drawn;

   //--- importance decides weight, not hue alone: a line a colour-blind
   //--- reader cannot tell from its neighbour is a line that says
   //--- nothing, and there are only three of them to tell apart
   color             Colour(const int importance)
     {
      if(importance >= (int)CALENDAR_IMPORTANCE_HIGH)
         return C'196,74,64';
      if(importance >= (int)CALENDAR_IMPORTANCE_MODERATE)
         return C'176,140,60';
      return C'110,120,130';
     }

   int               Width(const int importance)
     { return (importance >= (int)CALENDAR_IMPORTANCE_HIGH ? 2 : 1); }

   int               Style(const int importance)
     {
      return (importance >= (int)CALENDAR_IMPORTANCE_HIGH
              ? STYLE_SOLID : STYLE_DOT);
     }

public:
                     CSSRCalendarLines(void) : m_chart(0), m_drawn(0) {}

   void              Attach(const long chart_id) { m_chart = chart_id; }
   int               Drawn(void)                 { return m_drawn; }

   //+------------------------------------------------------------------+
   //| Draw whatever the feed holds. Idempotent: a line that is already |
   //| there is left exactly as it is, so this can be called from the   |
   //| timer without rewriting the chart sixty times a second.          |
   //+------------------------------------------------------------------+
   int               Draw(CSSRCalendar *cal)
     {
      if(m_chart == 0 || cal == NULL)
         return 0;

      int made = 0;
      for(int i = 0; i < cal.Count(); i++)
        {
         SSRCalendarItem it;
         if(!cal.At(i, it) || it.msc <= 0)
            continue;

         string n = SSR_CAL_PREFIX + IntegerToString(i);
         if(ObjectFind(m_chart, n) >= 0)
            continue;
         if(!ObjectCreate(m_chart, n, OBJ_VLINE, 0,
                          (datetime)(it.msc / 1000), 0))
            continue;

         ObjectSetInteger(m_chart, n, OBJPROP_COLOR,      Colour(it.importance));
         ObjectSetInteger(m_chart, n, OBJPROP_WIDTH,      Width(it.importance));
         ObjectSetInteger(m_chart, n, OBJPROP_STYLE,      Style(it.importance));
         //--- BEHIND the candles. A release line drawn over the bar it
         //--- refers to hides the one thing the user came to look at.
         ObjectSetInteger(m_chart, n, OBJPROP_BACK,       true);
         ObjectSetInteger(m_chart, n, OBJPROP_SELECTABLE, false);
         ObjectSetInteger(m_chart, n, OBJPROP_SELECTED,   false);
         ObjectSetInteger(m_chart, n, OBJPROP_HIDDEN,     true);
         ObjectSetString (m_chart, n, OBJPROP_TEXT,       it.Label());
         ObjectSetString (m_chart, n, OBJPROP_TOOLTIP,    it.Label());
         made++;
         m_drawn++;
        }
      if(made > 0)
         ChartRedraw(m_chart);
      return made;
     }

   //--- every object carrying the prefix, including any a previous
   //--- instance left behind by dying without cleaning up
   int               Clear(void)
     {
      if(m_chart == 0)
         return 0;
      m_drawn = 0;
      int n = ObjectsDeleteAll(m_chart, SSR_CAL_PREFIX, 0);
      if(n > 0)
         ChartRedraw(m_chart);
      return n;
     }
  };

#endif // SSR_CALENDAR_LINES_MQH
//+------------------------------------------------------------------+

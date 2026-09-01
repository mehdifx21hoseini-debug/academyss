//+------------------------------------------------------------------+
//|                                                 SSR_Calendar.mqh |
//|                    SS Replay - The Economic Calendar (L1/Data)   |
//|                                                                  |
//|  The one capability every competing replay tool has and this one  |
//|  did not. MetaTrader 5 carries its own calendar and MQL5 can read |
//|  it, so a replay over real historical dates can show the news     |
//|  that was actually scheduled while those candles were forming.    |
//|                                                                  |
//|  IT READS, IT DOES NOT DRAW. Lines on a chart are somebody else's |
//|  job (CSSRCalendarLines); this holds the answer to "what is       |
//|  happening, and when". The pause lives here because "we are two   |
//|  minutes from a high-impact release" is a question about exactly  |
//|  that and nothing else.                                          |
//|                                                                  |
//|  TWO THINGS THIS CANNOT PROMISE, and says so rather than          |
//|  pretending:                                                     |
//|                                                                  |
//|  1. The calendar may simply not be there. Some servers do not     |
//|     publish it, and CalendarValueHistory then returns nothing.    |
//|     That is reported as "no calendar", never as "no news".        |
//|                                                                  |
//|  2. The times come from MetaTrader in the terminal's own calendar |
//|     timezone, which is not guaranteed to be the same clock the    |
//|     chart's bars are stamped in. A fixed offset is the usual      |
//|     difference, so there is an input for it - measured once by    |
//|     the user against a release they can see in the candles, which |
//|     is the only place that answer actually exists.                |
//+------------------------------------------------------------------+
#ifndef SSR_CALENDAR_MQH
#define SSR_CALENDAR_MQH

#include "../Common/SSR_Types.mqh"
#include "../Common/SSR_Time.mqh"
#include "../Core/SSR_ITickObserver.mqh"

//--- a week of two currencies at moderate and above is a few dozen.
//--- The ceiling is here so a five-year window cannot try to draw
//--- twenty thousand vertical lines on one chart.
#define SSR_CAL_MAX   300

//--- MetaTrader cuts an object's text at 63 characters; v66 measured
//--- the cut landing mid-word on a hint that was 72. Event names are
//--- routinely longer than that once a currency is prefixed.
#define SSR_CAL_TEXT_MAX  63

//+------------------------------------------------------------------+
//| How much of the calendar to show. One enum rather than a number,  |
//| because "importance 2" is not a thing a person chooses.           |
//+------------------------------------------------------------------+
enum ENUM_SSR_NEWS
  {
   SSR_NEWS_OFF      = 0,   // Off
   SSR_NEWS_HIGH     = 1,   // High impact only
   SSR_NEWS_MODERATE = 2,   // Moderate impact and above
   SSR_NEWS_ALL      = 3    // Everything the calendar has
  };

int SSRNewsFloor(const ENUM_SSR_NEWS n)
  {
   if(n == SSR_NEWS_HIGH)     return (int)CALENDAR_IMPORTANCE_HIGH;
   if(n == SSR_NEWS_MODERATE) return (int)CALENDAR_IMPORTANCE_MODERATE;
   return (int)CALENDAR_IMPORTANCE_LOW;
  }

string SSRNewsName(const ENUM_SSR_NEWS n)
  {
   if(n == SSR_NEWS_HIGH)     return "high impact only";
   if(n == SSR_NEWS_MODERATE) return "moderate and above";
   if(n == SSR_NEWS_ALL)      return "everything";
   return "off";
  }

//+------------------------------------------------------------------+
struct SSRCalendarItem
  {
   long              msc;          // when, on the replay's own clock
   string            currency;
   string            name;
   int               importance;   // ENUM_CALENDAR_EVENT_IMPORTANCE

   void              Init(void)
     { msc = 0; currency = ""; name = ""; importance = 0; }

   //--- what goes on the line. Clipped, because the platform clips it
   //--- anyway and a label that ends mid-word looks like a fault.
   string            Label(void)
     {
      string s = (currency == "" ? name : currency + "  " + name);
      if(StringLen(s) > SSR_CAL_TEXT_MAX)
         s = StringSubstr(s, 0, SSR_CAL_TEXT_MAX - 1) + "~";
      return s;
     }
  };

//+------------------------------------------------------------------+
class CSSRCalendar : public CSSRTickObserver
  {
private:
   SSRCalendarItem   m_items[];
   int               m_count;

   bool              m_available;    // the terminal answered at all
   string            m_note;         // why it is empty, when it is
   long              m_shift_msc;    // the user's timezone correction
   int               m_pause_min;    // 0 = never pause

   bool              m_announced[];
   bool              m_want;
   string            m_reason;
   long              m_raised;

   void              Raise(const string why)
     {
      if(m_want)
         return;
      m_want   = true;
      m_reason = why;
      m_raised++;
     }

   //--- one currency's worth, appended. Called once per currency so
   //--- the platform does the filtering rather than this walking every
   //--- event on earth and throwing most of them away.
   int               Pull(const string currency, const datetime from,
                          const datetime to, const int min_importance)
     {
      //--- branched rather than a ternary: NULL and a string in one
      //--- conditional expression is the sort of thing that either
      //--- compiles or does not, depending on the build, and there is
      //--- no compiler on this side of the wire to ask
      MqlCalendarValue vals[];
      int n = 0;
      if(currency == "")
         n = CalendarValueHistory(vals, from, to);
      else
         n = CalendarValueHistory(vals, from, to, NULL, currency);
      if(n <= 0)
         return 0;

      int added = 0;
      for(int i = 0; i < n && m_count < SSR_CAL_MAX; i++)
        {
         MqlCalendarEvent ev;
         if(!CalendarEventById(vals[i].event_id, ev))
            continue;
         if((int)ev.importance < min_importance)
            continue;

         m_items[m_count].Init();
         m_items[m_count].msc        = (long)vals[i].time * 1000 + m_shift_msc;
         m_items[m_count].currency   = currency;
         m_items[m_count].name       = ev.name;
         m_items[m_count].importance = (int)ev.importance;
         m_count++;
         added++;
        }
      return added;
     }

public:
                     CSSRCalendar(void)
     : m_count(0), m_available(false), m_note("not loaded"),
       m_shift_msc(0), m_pause_min(0), m_want(false), m_reason(""),
       m_raised(0) {}

   virtual string    Name(void) override { return "calendar"; }

   void              SetShiftMinutes(const int m)
     { m_shift_msc = (long)m * SSR_MSC_PER_MIN; }
   void              SetPauseMinutes(const int m)
     { m_pause_min = (m < 0 ? 0 : m); }

   int               Count(void)      { return m_count; }
   bool              Available(void)  { return m_available; }
   string            Note(void)       { return m_note; }
   long              Raised(void)     { return m_raised; }

   bool              At(const int i, SSRCalendarItem &out)
     {
      if(i < 0 || i >= m_count)
        { out.Init(); return false; }
      out = m_items[i];
      return true;
     }

   //+------------------------------------------------------------------+
   //| LOAD THE WINDOW THE REPLAY WILL ACTUALLY CROSS.                  |
   //|                                                                  |
   //| The currencies come from the SYMBOL, asked of MetaTrader - never |
   //| parsed out of its name. A tool that decided "the first three     |
   //| letters are the base currency" would be wrong on the first index |
   //| or metal it met, and this project does not put symbol rules in   |
   //| its own code.                                                    |
   //|                                                                  |
   //| A symbol that reports no currencies is not an error: the whole   |
   //| calendar is loaded instead, and the note says that is what       |
   //| happened so nobody wonders why an index chart shows JPY news.    |
   //+------------------------------------------------------------------+
   bool              Load(const string origin_symbol, const long from_msc,
                          const long to_msc, const int min_importance)
     {
      m_count     = 0;
      m_available = false;
      m_note      = "";
      ArrayResize(m_items, SSR_CAL_MAX);
      ArrayResize(m_announced, SSR_CAL_MAX);
      for(int i = 0; i < SSR_CAL_MAX; i++)
         m_announced[i] = false;

      if(from_msc <= 0 || to_msc <= from_msc)
        { m_note = "no replay window to load a calendar for"; return false; }

      //--- widen by a day at each end: an event just outside the window
      //--- still belongs on the chart, because the user can see the
      //--- candles running up to it
      datetime from = (datetime)((from_msc / 1000) - 86400);
      datetime to   = (datetime)((to_msc   / 1000) + 86400);

      string base   = SymbolInfoString(origin_symbol, SYMBOL_CURRENCY_BASE);
      string profit = SymbolInfoString(origin_symbol, SYMBOL_CURRENCY_PROFIT);

      int got = 0;
      if(base == "" && profit == "")
        {
         got += Pull("", from, to, min_importance);
         m_note = StringFormat("%s reports no base or profit currency, so "
                               "every country's events are shown",
                               origin_symbol);
        }
      else
        {
         if(base != "")
            got += Pull(base, from, to, min_importance);
         if(profit != "" && profit != base)
            got += Pull(profit, from, to, min_importance);
        }

      //+------------------------------------------------------------------+
      //| NOTHING FOUND IS TWO DIFFERENT ANSWERS, and they must not look   |
      //| the same. A terminal with no calendar and a quiet week both      |
      //| produce zero events; only one of them is a missing feature.      |
      //+------------------------------------------------------------------+
      MqlCalendarValue probe[];
      int any = CalendarValueHistory(probe, from, to);
      m_available = (any > 0);

      if(!m_available)
        {
         m_note = StringFormat("this terminal returned no calendar at all for "
                               "%s..%s (error %d) - some servers do not publish "
                               "one. This is not the same as a quiet week.",
                               TimeToString(from, TIME_DATE),
                               TimeToString(to, TIME_DATE), GetLastError());
         return false;
        }
      if(m_count == 0 && m_note == "")
         m_note = "the calendar is there, and holds nothing at this "
                  "importance for these currencies in this window";
      if(m_count >= SSR_CAL_MAX)
         m_note = StringFormat("%d events is the ceiling - the window holds "
                               "more. Raise the importance filter to see the "
                               "ones that matter.", SSR_CAL_MAX);
      return (m_count > 0);
     }

   //+------------------------------------------------------------------+
   //| "You are two minutes from a high-impact release."                |
   //|                                                                  |
   //| HIGH only, deliberately. Pausing for every moderate print would  |
   //| stop the replay so often that the user would switch the whole    |
   //| feature off, and then it would not warn them about the one that  |
   //| mattered either.                                                 |
   //+------------------------------------------------------------------+
   virtual void      OnClock(const long now_msc) override
     {
      if(m_pause_min <= 0 || m_count == 0)
         return;
      long warn = (long)m_pause_min * SSR_MSC_PER_MIN;

      for(int i = 0; i < m_count; i++)
        {
         if(m_announced[i])
            continue;
         if(m_items[i].importance < (int)CALENDAR_IMPORTANCE_HIGH)
            continue;

         //--- past it already: mark it seen without stopping. A pause
         //--- AFTER the news is a pause for nothing, and leaving it
         //--- unannounced would fire it on the next rewind.
         if(now_msc > m_items[i].msc)
           { m_announced[i] = true; continue; }

         if(now_msc >= m_items[i].msc - warn)
           {
            m_announced[i] = true;
            long left = (m_items[i].msc - now_msc) / SSR_MSC_PER_MIN;
            Raise(StringFormat("%d min to %s", (int)left,
                               m_items[i].Label()));
           }
        }
     }

   virtual bool      PauseRequested(string &reason) override
     {
      if(!m_want)
         return false;
      reason   = m_reason;
      m_want   = false;
      m_reason = "";
      return true;
     }

   //--- a rewind un-happens the announcements it stepped back over, or
   //--- replaying the same hour would run straight through the release
   //--- the user rewound in order to watch again
   virtual void      OnRewind(const long msc) override
     {
      m_want   = false;
      m_reason = "";
      for(int i = 0; i < m_count; i++)
         if(m_items[i].msc >= msc)
            m_announced[i] = false;
     }
  };

#endif // SSR_CALENDAR_MQH
//+------------------------------------------------------------------+

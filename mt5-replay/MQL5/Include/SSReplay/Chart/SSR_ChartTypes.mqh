//+------------------------------------------------------------------+
//|                                               SSR_ChartTypes.mqh |
//|                    SS Replay - Chart Layer Vocabulary (L3/Chart) |
//|                                                                  |
//|  The chart layer never talks to the replay engine. It publishes  |
//|  events and the owner - the Service in production - decides what |
//|  they mean. That is what keeps "change the timeframe" from being |
//|  something the engine has to know about.                         |
//+------------------------------------------------------------------+
#ifndef SSR_CHART_TYPES_MQH
#define SSR_CHART_TYPES_MQH

#include "../Common/SSR_Types.mqh"

//--- Minimum gap between our own repaints. Chosen against HUMAN
//--- PERCEPTION, not throughput: ten frames a second is past the point
//--- where a moving label reads as continuous, and MetaTrader already
//--- repaints price on every injected tick, so this only governs
//--- overlay objects. That makes it a justified figure rather than a
//--- number waiting to be measured.
#define SSR_REDRAW_MIN_INTERVAL_MS   100

//--- how far the view may drift from the right edge before we conclude
//--- the user scrolled deliberately rather than a bar simply arriving
#define SSR_SCROLL_DETACH_BARS       3

//--- consecutive syncs the drift must persist for before we believe it.
//--- A bulk write can spike the offset for one frame before MetaTrader
//--- repaints; one sample would read that as the user scrolling.
#define SSR_SCROLL_DETACH_VOTES      2

//--- ceiling on managed charts; well above any sane multi-chart layout
#define SSR_MAX_CHARTS               16

//+------------------------------------------------------------------+
//| What the chart layer knows about one chart it manages.           |
//+------------------------------------------------------------------+
struct SSRChartInfo
  {
   long              id;
   string            symbol;
   ENUM_TIMEFRAMES   period;
   bool              follow;            // our intent: keep it at the right edge
   bool              user_detached;     // the user scrolled away deliberately
   long              last_offset;       // bars between the view and the end
   int               detach_votes;      // consecutive syncs seen drifting
   long              tf_changes;        // how often this chart changed timeframe
   bool              alive;

   void              Init(void)
     {
      id = 0; symbol = ""; period = PERIOD_CURRENT;
      follow = true; user_detached = false;
      last_offset = 0; detach_votes = 0; tf_changes = 0; alive = false;
     }
  };

//+------------------------------------------------------------------+
//| Chart events. The owner reacts; the chart layer never does.      |
//+------------------------------------------------------------------+
class CSSRChartObserver
  {
public:
   virtual          ~CSSRChartObserver(void) {}

   virtual void      OnChartOpened(const long chart_id) {}
   virtual void      OnChartClosed(const long chart_id) {}

   //--- fires AFTER MetaTrader has already rebuilt the series. The
   //--- replay state is untouched by this; the notification exists so
   //--- the panel can redraw and the policy can be re-applied.
   virtual void      OnTimeframeChanged(const long chart_id,
                                        const ENUM_TIMEFRAMES from,
                                        const ENUM_TIMEFRAMES to) {}

   virtual void      OnUserScrolled(const long chart_id) {}
   virtual void      OnUserFollowed(const long chart_id) {}
  };

//+------------------------------------------------------------------+
//| A leak is a way the user can see the future. Some are structural |
//| and already impossible; these are the ones that are not.         |
//+------------------------------------------------------------------+
enum ENUM_SSR_LEAK
  {
   SSR_LEAK_NONE = 0,
   SSR_LEAK_ORIGIN_IN_MARKET_WATCH,   // live price of the real instrument
   SSR_LEAK_ORIGIN_CHART_OPEN,        // a chart showing the real instrument
   SSR_LEAK_OTHER_SYMBOL_CHART        // any other live symbol on screen
  };

struct SSRLeakReport
  {
   bool              origin_in_watch;
   int               origin_charts;
   int               other_live_charts;
   int               replay_charts;

   void              Init(void)
     {
      origin_in_watch = false;
      origin_charts = 0; other_live_charts = 0; replay_charts = 0;
     }

   bool              IsClean(void)
     {
      return (!origin_in_watch && origin_charts == 0);
     }

   //--- the honest summary the panel shows. Never silent when dirty:
   //--- a backtesting tool that says nothing while the user can see
   //--- the real price is lying to them.
   string            ToString(void)
     {
      if(IsClean())
         return "no leak";
      string s = "";
      if(origin_charts > 0)
         s += StringFormat("%d chart(s) on the live symbol; ", origin_charts);
      if(origin_in_watch)
         s += "live symbol in Market Watch; ";
      return s;
     }
  };

#endif // SSR_CHART_TYPES_MQH
//+------------------------------------------------------------------+

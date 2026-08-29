//+------------------------------------------------------------------+
//|                                           SSR_SessionWatcher.mqh |
//|                   SS Replay - Pause On A New Session (L2/Data)   |
//|                                                                  |
//|  "Stop when a new session starts" without hardcoding when        |
//|  sessions start.                                                 |
//|                                                                  |
//|  Writing `if(hour == 0)` here would be the third anti-pattern on |
//|  the list: broker logic baked into the tool. It would also be    |
//|  wrong on any instrument whose day does not begin at midnight     |
//|  server time - which is most of them once you leave FX.          |
//|                                                                  |
//|  So a session boundary is READ, two ways, and the user picks:    |
//|                                                                  |
//|   BY GAP - the data went quiet for longer than this symbol's own |
//|            shortest declared break. That IS the market closing   |
//|            and reopening, whatever the clock says.               |
//|   BY DAY - the replay clock crossed a calendar day. Cruder, but  |
//|            it is what a trader means by "next day" and it works  |
//|            on a symbol that declares no sessions at all.         |
//+------------------------------------------------------------------+
#ifndef SSR_SESSION_WATCHER_MQH
#define SSR_SESSION_WATCHER_MQH

#include "../Common/SSR_Types.mqh"
#include "../Common/SSR_Time.mqh"
#include "../Core/SSR_ITickObserver.mqh"
#include "SSR_DataValidator.mqh"

enum ENUM_SSR_SESSION_MODE
  {
   SSR_SESSION_OFF = 0,
   SSR_SESSION_BY_GAP,     // a silence longer than the symbol's own break
   SSR_SESSION_BY_DAY      // a calendar day boundary in server time
  };

//+------------------------------------------------------------------+
class CSSRSessionWatcher : public CSSRTickObserver
  {
private:
   ENUM_SSR_SESSION_MODE m_mode;
   long              m_threshold_msc;   // for BY_GAP
   string            m_symbol;

   long              m_last_tick_msc;
   long              m_last_day;

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

public:
                     CSSRSessionWatcher(void)
     : m_mode(SSR_SESSION_OFF), m_threshold_msc(SSR_SESSION_GAP_MSC),
       m_symbol(""), m_last_tick_msc(SSR_INVALID_TIME), m_last_day(-1),
       m_want(false), m_reason(""), m_raised(0) {}

   virtual string    Name(void) override { return "session-watch"; }

   void              SetMode(const ENUM_SSR_SESSION_MODE m) { m_mode = m; }
   ENUM_SSR_SESSION_MODE Mode(void)                         { return m_mode; }
   void              SetThresholdMsc(const long msc)
     { if(msc > 0) m_threshold_msc = msc; }
   long              ThresholdMsc(void) { return m_threshold_msc; }
   long              Raised(void)       { return m_raised; }

   //--- ask the instrument rather than assume it
   void              LearnFrom(const string symbol)
     {
      m_symbol        = symbol;
      m_threshold_msc = SSRSymbolSessionBreak(symbol);
     }

   virtual void      OnSessionStart(const string symbol, const int digits,
                                    const double point, const long start_msc) override
     {
      m_symbol        = symbol;
      m_last_tick_msc = SSR_INVALID_TIME;
      m_last_day      = (start_msc > 0 ? start_msc / SSR_MSC_PER_DAY : -1);
      m_want          = false;
      m_reason        = "";
     }

   virtual void      OnTicks(const MqlTick &ticks[], const int count) override
     {
      if(m_mode == SSR_SESSION_OFF)
        {
         //--- still tracked, so switching the mode on mid-replay does
         //--- not fire on the accumulated silence since it was off
         if(count > 0)
           {
            m_last_tick_msc = ticks[count - 1].time_msc;
            m_last_day      = m_last_tick_msc / SSR_MSC_PER_DAY;
           }
         return;
        }

      for(int i = 0; i < count; i++)
        {
         long t = ticks[i].time_msc;

         if(m_mode == SSR_SESSION_BY_GAP && m_last_tick_msc > 0)
           {
            long gap = t - m_last_tick_msc;
            if(gap >= m_threshold_msc)
               Raise(StringFormat("new session - %s of silence before %s",
                                  SSRFormatSpan(gap), SSRFormatMsc(t)));
           }

         if(m_mode == SSR_SESSION_BY_DAY)
           {
            long day = t / SSR_MSC_PER_DAY;
            if(m_last_day >= 0 && day > m_last_day)
               Raise("new day - " + SSRFormatMsc(t));
            m_last_day = day;
           }

         m_last_tick_msc = t;
        }

      if(m_mode != SSR_SESSION_BY_DAY && count > 0)
         m_last_day = ticks[count - 1].time_msc / SSR_MSC_PER_DAY;
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

   //--- a rewind moves the clock back across boundaries this already
   //--- announced. Announcing them again on the way forward is correct;
   //--- announcing the one we are standing on is not.
   virtual void      OnRewind(const long msc) override
     {
      m_want          = false;
      m_reason        = "";
      m_last_tick_msc = msc;
      m_last_day      = (msc > 0 ? msc / SSR_MSC_PER_DAY : -1);
     }

   string            ToString(void)
     {
      string m = "off";
      if(m_mode == SSR_SESSION_BY_GAP) m = "gap>" + SSRFormatSpan(m_threshold_msc);
      if(m_mode == SSR_SESSION_BY_DAY) m = "day";
      return StringFormat("session-watch[%s raised=%I64d]", m, m_raised);
     }
  };

#endif // SSR_SESSION_WATCHER_MQH
//+------------------------------------------------------------------+

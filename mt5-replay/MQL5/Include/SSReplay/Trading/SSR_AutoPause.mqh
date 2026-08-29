//+------------------------------------------------------------------+
//|                                                SSR_AutoPause.mqh |
//|                  SS Replay - Pause On Trade Events (L2/Trading)  |
//|                                                                  |
//|  "Stop the replay when my stop is hit" is the feature. Where it  |
//|  lives is the design.                                            |
//|                                                                  |
//|  It does NOT live in the engine. The replay core has no idea     |
//|  that trades exist, and teaching it would be the single change   |
//|  that makes every later layer harder to keep separate. Instead   |
//|  Core asks each observer one question after every pump - "do you |
//|  want to stop here?" - and this class is the observer that       |
//|  answers yes, with a sentence Core repeats without understanding.|
//|                                                                  |
//|  HOW IT KNOWS                                                    |
//|  By watching, not by being told. It keeps the last state it saw  |
//|  for each position and compares. That way the trading engine     |
//|  needs no callbacks, no event list and no knowledge that anyone  |
//|  is watching - and there is no second path through which a trade |
//|  can be recorded and forgotten.                                  |
//+------------------------------------------------------------------+
#ifndef SSR_AUTO_PAUSE_MQH
#define SSR_AUTO_PAUSE_MQH

#include "../Common/SSR_Types.mqh"
#include "../Common/SSR_Time.mqh"
#include "../Core/SSR_ITickObserver.mqh"
#include "SSR_TradingEngine.mqh"

//--- what to stop for, as flags so the user can pick any combination
#define SSR_PAUSE_ON_ENTRY     0x01   // a market or pending order filled
#define SSR_PAUSE_ON_SL        0x02
#define SSR_PAUSE_ON_TP        0x04
#define SSR_PAUSE_ON_STOPOUT   0x08
#define SSR_PAUSE_ON_ANY_CLOSE 0x10   // including a manual one
#define SSR_PAUSE_ON_NONE      0x00

//--- a sensible default: the two moments a trader actually wants to
//--- look at. Entry is deliberately off - you were there when you
//--- clicked it.
#define SSR_PAUSE_DEFAULT   (SSR_PAUSE_ON_SL | SSR_PAUSE_ON_TP | SSR_PAUSE_ON_STOPOUT)

//+------------------------------------------------------------------+
class CSSRTradeAutoPause : public CSSRTickObserver
  {
private:
   CSSRTradingEngine *m_acct;         // not owned
   int                m_flags;

   //--- the last state seen for each position slot, so a change is a
   //--- comparison rather than a notification
   uchar              m_seen[SSR_MAX_POSITIONS];
   int                m_seen_count;

   //--- the pending request. Consumed by PauseRequested, exactly once.
   bool               m_want;
   string             m_reason;
   long               m_raised;

   bool               Wants(const int flag) { return ((m_flags & flag) != 0); }

   void               Raise(const string why)
     {
      if(m_want)
         return;                       // the first reason is the true one
      m_want   = true;
      m_reason = why;
      m_raised++;
     }

   //+------------------------------------------------------------------+
   //| Compare every position against what was last seen, and decide.   |
   //+------------------------------------------------------------------+
   void               Scan(void)
     {
      if(m_acct == NULL || m_flags == SSR_PAUSE_ON_NONE)
         return;

      int total = m_acct.Total();
      if(total > SSR_MAX_POSITIONS)
         total = SSR_MAX_POSITIONS;

      for(int i = 0; i < total; i++)
        {
         SSRVirtualPosition p;
         if(!m_acct.At(i, p))
            continue;

         uchar now  = (uchar)p.state;
         uchar was  = (i < m_seen_count ? m_seen[i] : (uchar)255);
         m_seen[i]  = now;

         if(was == now)
            continue;

         //--- a slot we had never seen before is not a transition; it
         //--- is the first sight of an order that may already be open
         bool is_new = (was == 255);

         if(now == SSR_POS_OPEN)
           {
            //--- new and open, or pending that just filled: an ENTRY
            if(Wants(SSR_PAUSE_ON_ENTRY))
               Raise(StringFormat("entry filled - %s %.2f @ %s",
                                  SSROrderName(p.type), p.volume_initial,
                                  DoubleToString(p.open_price, 5)));
            continue;
           }

         if(now != SSR_POS_CLOSED || is_new)
            continue;

         switch(p.reason)
           {
            case SSR_CLOSE_SL:
               if(Wants(SSR_PAUSE_ON_SL))
                  Raise(StringFormat("stop loss hit%s",
                                     (p.ambiguous ? " (assumed - both levels in one bar)" : "")));
               break;
            case SSR_CLOSE_TP:
               if(Wants(SSR_PAUSE_ON_TP))
                  Raise("take profit hit");
               break;
            case SSR_CLOSE_STOPOUT:
               if(Wants(SSR_PAUSE_ON_STOPOUT))
                  Raise("stop out - margin level fell through the floor");
               break;
            default:
               break;
           }

         if(Wants(SSR_PAUSE_ON_ANY_CLOSE))
            Raise("position closed - " + SSRCloseReasonName(p.reason));
        }

      m_seen_count = total;
     }

public:
                     CSSRTradeAutoPause(void)
     : m_acct(NULL), m_flags(SSR_PAUSE_DEFAULT), m_seen_count(0),
       m_want(false), m_reason(""), m_raised(0) {}

   virtual string    Name(void) override { return "auto-pause"; }

   void              Attach(CSSRTradingEngine *a) { m_acct = a; }
   void              SetFlags(const int f)        { m_flags = f; }
   int               Flags(void)                  { return m_flags; }
   long              Raised(void)                 { return m_raised; }

   void              Enable(const int flag, const bool on)
     { if(on) m_flags |= flag; else m_flags &= ~flag; }

   //+------------------------------------------------------------------+
   //| The observer contract.                                           |
   //|                                                                  |
   //| Order matters: this must be registered AFTER the trading engine, |
   //| so that by the time this sees the tick the engine has already    |
   //| filled orders and hit stops for it.                              |
   //+------------------------------------------------------------------+
   virtual void      OnTicks(const MqlTick &ticks[], const int count) override
     { Scan(); }

   //--- Consumed here, and only here. An observer that kept answering
   //--- yes would pin the replay in a pause the user cannot leave.
   virtual bool      PauseRequested(string &reason) override
     {
      if(!m_want)
         return false;
      reason   = m_reason;
      m_want   = false;
      m_reason = "";
      return true;
     }

   //+------------------------------------------------------------------+
   //| A rewind un-happens the very transitions this watches.           |
   //|                                                                  |
   //| Without this, stepping back over a stop and replaying it would   |
   //| either fire twice or not at all, depending on which way the      |
   //| stale memory happened to fall. So the memory is dropped and      |
   //| rebuilt from what the account actually holds now - and any       |
   //| request raised for a deleted future is dropped with it.          |
   //+------------------------------------------------------------------+
   virtual void      OnRewind(const long msc) override
     {
      m_want   = false;
      m_reason = "";
      Reseed();
     }

   virtual void      OnSessionStart(const string symbol, const int digits,
                                    const double point, const long start_msc) override
     {
      m_want   = false;
      m_reason = "";
      m_seen_count = 0;
     }

   //--- adopt the account's current state WITHOUT raising anything:
   //--- what is already true is not an event
   void              Reseed(void)
     {
      m_seen_count = 0;
      if(m_acct == NULL)
         return;
      int total = m_acct.Total();
      if(total > SSR_MAX_POSITIONS)
         total = SSR_MAX_POSITIONS;
      for(int i = 0; i < total; i++)
        {
         SSRVirtualPosition p;
         if(m_acct.At(i, p))
            m_seen[i] = (uchar)p.state;
        }
      m_seen_count = total;
     }

   string            FlagsText(void)
     {
      if(m_flags == SSR_PAUSE_ON_NONE)
         return "off";
      string s = "";
      if(Wants(SSR_PAUSE_ON_ENTRY))     s += "entry ";
      if(Wants(SSR_PAUSE_ON_SL))        s += "SL ";
      if(Wants(SSR_PAUSE_ON_TP))        s += "TP ";
      if(Wants(SSR_PAUSE_ON_STOPOUT))   s += "stopout ";
      if(Wants(SSR_PAUSE_ON_ANY_CLOSE)) s += "any-close ";
      StringTrimRight(s);
      return s;
     }
  };

#endif // SSR_AUTO_PAUSE_MQH
//+------------------------------------------------------------------+

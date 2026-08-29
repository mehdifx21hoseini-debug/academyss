//+------------------------------------------------------------------+
//|                                                SSR_FutureGuard.mqh|
//|                                 SS Replay - Future Data Guard(L2)|
//|                                                                  |
//|  The product's reason to exist, expressed as one small object.   |
//|                                                                  |
//|  The guard holds a HORIZON: the current replay time. Any read    |
//|  whose range extends past the horizon is either clamped or       |
//|  refused, and every refusal is counted so a leak can never be    |
//|  silent.                                                         |
//|                                                                  |
//|  DEFENCE IN DEPTH - the guard is applied twice, on purpose:      |
//|    1. the controller clamps every range before requesting it     |
//|    2. every provider re-checks against the same guard            |
//|  One layer is a convention that a future phase can forget. Two   |
//|  layers, where the second is inside the data layer itself, is a  |
//|  structural guarantee.                                           |
//+------------------------------------------------------------------+
#ifndef SSR_FUTURE_GUARD_MQH
#define SSR_FUTURE_GUARD_MQH

#include "../Common/SSR_Types.mqh"
#include "../Common/SSR_Time.mqh"

//+------------------------------------------------------------------+
class CSSRFutureGuard
  {
private:
   long              m_horizon_msc;   // nothing at or beyond this may be read
   bool              m_armed;
   long              m_violations;    // attempts that were clamped or refused
   long              m_last_violation_msc;

public:
                     CSSRFutureGuard(void)
     : m_horizon_msc(SSR_INVALID_TIME), m_armed(false),
       m_violations(0), m_last_violation_msc(SSR_INVALID_TIME) {}

   //--- lifecycle ---------------------------------------------------
   void              Arm(const long horizon_msc)
     {
      m_horizon_msc = horizon_msc;
      m_armed       = true;
     }

   void              Disarm(void) { m_armed = false; }

   void              SetHorizon(const long horizon_msc)
     {
      //--- the horizon may move forward freely; moving it BACKWARD is
      //--- legitimate too (a rewind), so no monotonic check here
      m_horizon_msc = horizon_msc;
     }

   void              ResetCounters(void)
     {
      m_violations         = 0;
      m_last_violation_msc = SSR_INVALID_TIME;
     }

   //--- queries -----------------------------------------------------
   bool              IsArmed(void)      { return m_armed; }
   long              Horizon(void)      { return m_horizon_msc; }
   long              Violations(void)   { return m_violations; }
   long              LastViolation(void){ return m_last_violation_msc; }

   //+------------------------------------------------------------------+
   //| Is this instant readable right now?                              |
   //| Inclusive of the horizon: at replay time T the tick stamped      |
   //| exactly T has just happened and is legitimately visible.         |
   //+------------------------------------------------------------------+
   bool              Allows(const long msc)
     {
      if(!m_armed || m_horizon_msc <= 0)
         return true;
      return (msc <= m_horizon_msc);
     }

   //--- record a refusal without throwing; the caller decides policy
   void              Violation(const long msc)
     {
      m_violations++;
      m_last_violation_msc = msc;
     }

   //+------------------------------------------------------------------+
   //| Clamp a requested range into what may legally be read.           |
   //| Returns false when nothing at all is readable.                   |
   //+------------------------------------------------------------------+
   bool              ClampRange(long &from_msc, long &to_msc)
     {
      if(!m_armed || m_horizon_msc <= 0)
         return (from_msc <= to_msc);

      if(from_msc > m_horizon_msc)
        {
         Violation(from_msc);
         return false;                   // the whole range is in the future
        }
      if(to_msc > m_horizon_msc)
        {
         Violation(to_msc);
         to_msc = m_horizon_msc;         // trim the future tail off
        }
      return (from_msc <= to_msc);
     }

   //--- drop any bar/tick beyond the horizon from an already-read set
   int               FilterTicks(MqlTick &ticks[], const int count)
     {
      if(!m_armed || m_horizon_msc <= 0)
         return count;
      int keep = 0;
      for(int i = 0; i < count; i++)
        {
         if(ticks[i].time_msc <= m_horizon_msc)
           {
            if(keep != i)
               ticks[keep] = ticks[i];
            keep++;
           }
         else
            Violation(ticks[i].time_msc);
        }
      return keep;
     }

   int               FilterRates(MqlRates &rates[], const int count)
     {
      if(!m_armed || m_horizon_msc <= 0)
         return count;
      int keep = 0;
      for(int i = 0; i < count; i++)
        {
         if(SSRToMsc(rates[i].time) <= m_horizon_msc)
           {
            if(keep != i)
               rates[keep] = rates[i];
            keep++;
           }
         else
            Violation(SSRToMsc(rates[i].time));
        }
      return keep;
     }

   string            ToString(void)
     {
      return StringFormat("guard[%s horizon=%s violations=%d]",
                          (m_armed ? "armed" : "off"),
                          SSRFormatMsc(m_horizon_msc), (int)m_violations);
     }
  };

#endif // SSR_FUTURE_GUARD_MQH
//+------------------------------------------------------------------+

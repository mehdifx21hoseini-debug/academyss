//+------------------------------------------------------------------+
//|                                           SSR_FidelityPolicy.mqh |
//|                        SS Replay - Adaptive Fidelity (L2)        |
//|                                                                  |
//|  WHAT THE DESIGN DOCUMENT GOT WRONG, AND WHY THIS IS DIFFERENT   |
//|                                                                  |
//|  The plan was a speed-to-fidelity table: full ticks below 2x,    |
//|  synthetic to 10x, bar close above. Working the arithmetic shows |
//|  the premise does not hold. At 50x the engine advances 50 replay |
//|  seconds per wall second - under one M1 bar, about seven ticks.  |
//|  Reaching the 2000 ticks/second the plan worried about would     |
//|  take roughly 15,000x. Speed is simply not what stresses the     |
//|  tick path.                                                      |
//|                                                                  |
//|  So fidelity degrades for the three reasons that are real:       |
//|                                                                  |
//|    1. THE DATA IS NOT THERE. Most brokers hold little or no tick |
//|       history for CFDs, and pretending otherwise renders a       |
//|       frozen market.                                             |
//|    2. A BULK MOMENT. A pump after a stall, or a jump covering    |
//|       hours, genuinely can ask for minutes of work at once.      |
//|    3. THE USER ASKED. Their choice outranks the policy's.        |
//|                                                                  |
//|  And whatever it decides is always visible. A tool that silently |
//|  approximates is lying about its own output.                     |
//+------------------------------------------------------------------+
#ifndef SSR_FIDELITY_POLICY_MQH
#define SSR_FIDELITY_POLICY_MQH

#include "../Common/SSR_Types.mqh"
#include "SSR_Metrics.mqh"

//--- a pump owing more replay time than this is a bulk moment, not
//--- ordinary playback. Ten minutes of market in one call.
#define SSR_BULK_THRESHOLD_MSC   (10 * 60 * 1000)

enum ENUM_SSR_FIDELITY_REASON
  {
   SSR_FR_USER = 0,        // exactly what was asked for
   SSR_FR_NO_TICK_DATA,    // the broker has none
   SSR_FR_BULK,            // catching up over a large span
   SSR_FR_LOCKED           // user pinned it; the policy stands aside
  };

string SSRFidelityReasonText(const ENUM_SSR_FIDELITY_REASON r)
  {
   switch(r)
     {
      case SSR_FR_USER:         return "";
      case SSR_FR_NO_TICK_DATA: return "no tick history - using synthetic ticks";
      case SSR_FR_BULK:         return "catching up - reduced fidelity";
      case SSR_FR_LOCKED:       return "fidelity locked";
     }
   return "";
  }

//+------------------------------------------------------------------+
class CSSRFidelityPolicy
  {
private:
   ENUM_SSR_FIDELITY        m_requested;   // what the user chose
   ENUM_SSR_FIDELITY        m_effective;   // what is actually running
   ENUM_SSR_FIDELITY_REASON m_reason;
   bool                     m_locked;
   bool                     m_ticks_available;
   long                     m_degradations;

public:
                     CSSRFidelityPolicy(void)
     : m_requested(SSR_FIDELITY_SYNTHETIC_TICK),
       m_effective(SSR_FIDELITY_SYNTHETIC_TICK),
       m_reason(SSR_FR_USER), m_locked(false),
       m_ticks_available(false), m_degradations(0) {}

   void              SetRequested(const ENUM_SSR_FIDELITY f)
     {
      m_requested = f;
      m_effective = f;
      m_reason    = (m_locked ? SSR_FR_LOCKED : SSR_FR_USER);
     }

   //--- a user who pins fidelity gets exactly that, bulk or not. It is
   //--- their backtest; the policy is a convenience, not an authority.
   void              SetLocked(const bool on)
     { m_locked = on; if(on) m_reason = SSR_FR_LOCKED; }

   void              SetTicksAvailable(const bool on) { m_ticks_available = on; }

   ENUM_SSR_FIDELITY        Requested(void)  { return m_requested; }
   ENUM_SSR_FIDELITY        Effective(void)  { return m_effective; }
   ENUM_SSR_FIDELITY_REASON Reason(void)     { return m_reason; }
   bool                     IsLocked(void)   { return m_locked; }
   bool                     IsDegraded(void) { return (m_effective != m_requested); }
   long                     Degradations(void) { return m_degradations; }
   string                   ReasonText(void) { return SSRFidelityReasonText(m_reason); }

   //+------------------------------------------------------------------+
   //| Decide the fidelity for the window about to be emitted.          |
   //| `owed_msc` is how much replay time this pump has to cover.       |
   //+------------------------------------------------------------------+
   ENUM_SSR_FIDELITY Decide(const long owed_msc)
     {
      ENUM_SSR_FIDELITY before = m_effective;

      if(m_locked)
        {
         m_effective = m_requested;
         m_reason    = SSR_FR_LOCKED;
         return m_effective;
        }

      //--- reason 1 outranks everything: asking for real ticks that do
      //--- not exist would emit nothing at all
      if(m_requested == SSR_FIDELITY_FULL_TICK && !m_ticks_available)
        {
         m_effective = SSR_FIDELITY_SYNTHETIC_TICK;
         m_reason    = SSR_FR_NO_TICK_DATA;
        }
      //--- reason 2: a genuine bulk moment
      else if(owed_msc >= SSR_BULK_THRESHOLD_MSC)
        {
         m_effective = SSR_FIDELITY_BAR;
         m_reason    = SSR_FR_BULK;
        }
      else
        {
         m_effective = m_requested;
         m_reason    = SSR_FR_USER;
        }

      if(m_effective != before && m_effective != m_requested)
         m_degradations++;
      return m_effective;
     }

   string            ToString(void)
     {
      return StringFormat("fidelity[req=%s eff=%s %s]",
                          SSRFidelityName(m_requested),
                          SSRFidelityName(m_effective),
                          (m_locked ? "LOCKED" : SSRFidelityReasonText(m_reason)));
     }
  };

#endif // SSR_FIDELITY_POLICY_MQH
//+------------------------------------------------------------------+

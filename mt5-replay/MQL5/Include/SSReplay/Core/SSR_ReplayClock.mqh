//+------------------------------------------------------------------+
//|                                               SSR_ReplayClock.mqh |
//|                              SS Replay - Deterministic Clock (L2)|
//|                                                                  |
//|  THE ONLY SOURCE OF TIME IN THE ENGINE.                          |
//|  No module may call TimeCurrent() or TimeLocal() for replay      |
//|  logic. Violating that rule is the most common way a replay tool |
//|  leaks the future without anyone noticing.                       |
//|                                                                  |
//|  DETERMINISM                                                     |
//|  The clock never reads a wall clock itself - it is advanced by   |
//|  a caller that hands it an elapsed-milliseconds delta. That      |
//|  makes it a pure function of its inputs, so a test can feed      |
//|  fixed deltas and get bit-identical output every run.            |
//|                                                                  |
//|  Speed is held as an INTEGER hundredth (1x = 100), and the       |
//|  advance is computed with integer arithmetic plus a carried      |
//|  remainder. Multiplying a delta by a double 0.25 and truncating  |
//|  would drift by a millisecond here and there; over an hour of    |
//|  replay that drift becomes a visibly wrong candle. Integers and  |
//|  a residue do not drift at all.                                  |
//+------------------------------------------------------------------+
#ifndef SSR_REPLAY_CLOCK_MQH
#define SSR_REPLAY_CLOCK_MQH

#include "../Common/SSR_Types.mqh"
#include "../Common/SSR_Time.mqh"

//+------------------------------------------------------------------+
struct SSRReplayClock
  {
   //--- bounds and position, all in epoch milliseconds
   long              start_msc;
   long              now_msc;
   long              end_msc;

   //--- speed as an integer hundredth: 100 == 1.00x
   long              speed_x100;

   //--- sub-millisecond carry, so repeated advances never drift
   long              residue;

   //--- how many times Advance() has been called; part of the
   //--- snapshot so a restored session is provably identical
   ulong             steps;

   //--- lifecycle ---------------------------------------------------
   void              Init(void)
     {
      start_msc  = SSR_INVALID_TIME;
      now_msc    = SSR_INVALID_TIME;
      end_msc    = SSR_INVALID_TIME;
      speed_x100 = SSR_SPEED_1;
      residue    = 0;
      steps      = 0;
     }

   bool              Configure(const long a_start_msc, const long a_end_msc)
     {
      if(a_start_msc <= 0 || a_end_msc <= 0 || a_end_msc <= a_start_msc)
         return false;
      start_msc = a_start_msc;
      end_msc   = a_end_msc;
      now_msc   = a_start_msc;
      residue   = 0;
      steps     = 0;
      return true;
     }

   bool              IsConfigured(void)
     {
      return (start_msc > 0 && end_msc > start_msc && now_msc >= start_msc);
     }

   //--- speed -------------------------------------------------------
   void              SetSpeedX100(const long s)
     {
      speed_x100 = (s < 1 ? 1 : s);
      residue    = 0;             // a speed change starts a fresh accumulation
     }

   void              SetSpeed(const double s)
     {
      SetSpeedX100((long)MathRound(s * 100.0));
     }

   double            Speed(void) { return SSRSpeedToDouble(speed_x100); }

   //+------------------------------------------------------------------+
   //| Advance replay time by `wall_delta_ms` of real elapsed time.     |
   //| Returns the new replay time. Pure integer maths - given the same |
   //| sequence of deltas and speeds, the output is always identical.   |
   //+------------------------------------------------------------------+
   long              Advance(const ulong wall_delta_ms)
     {
      if(!IsConfigured())
         return now_msc;

      long scaled = (long)wall_delta_ms * speed_x100 + residue;
      long adv    = scaled / 100;
      residue     = scaled % 100;

      now_msc += adv;
      if(now_msc > end_msc)
        {
         now_msc = end_msc;
         residue = 0;
        }
      steps++;
      return now_msc;
     }

   //+------------------------------------------------------------------+
   //| Advance to an EXACT instant, forward only.                       |
   //|                                                                  |
   //| This is how several streams stay on one clock. Advance() scales  |
   //| a wall delta and so accumulates its own residue per stream; two  |
   //| streams fed the same deltas would stay together only as long as  |
   //| nothing ever changed speed mid-pump. Told a target instead, they |
   //| cannot drift apart at all - there is nothing to drift.           |
   //|                                                                  |
   //| Forward only, because going backward is a SEEK: it deletes a      |
   //| future that observers were told about, and that has to travel     |
   //| the rewind path rather than look like ordinary progress.          |
   //+------------------------------------------------------------------+
   long              AdvanceTo(const long target_msc)
     {
      if(!IsConfigured())
         return now_msc;
      long t = target_msc;
      if(t > end_msc)
         t = end_msc;
      if(t <= now_msc)
         return now_msc;               // never backward, never a no-op step
      now_msc = t;
      residue = 0;                     // an exact target owes no fraction
      steps++;
      return now_msc;
     }

   //--- jump straight to a time, clamped into the timeline
   bool              SeekTo(const long target_msc)
     {
      if(!IsConfigured())
         return false;
      now_msc = SSRClampMsc(target_msc, start_msc, end_msc);
      residue = 0;
      steps++;
      return true;
     }

   //--- move by a signed amount of replay time
   long              Shift(const long delta_msc)
     {
      SeekTo(now_msc + delta_msc);
      return now_msc;
     }

   void              Rewind(void)
     {
      now_msc = start_msc;
      residue = 0;
      steps   = 0;
     }

   //--- queries -----------------------------------------------------
   bool              IsCompleted(void) { return (IsConfigured() && now_msc >= end_msc); }
   long              Remaining(void)   { return (IsConfigured() ? end_msc - now_msc : 0); }
   long              Elapsed(void)     { return (IsConfigured() ? now_msc - start_msc : 0); }

   double            Progress(void)
     {
      if(!IsConfigured())
         return 0.0;
      long span = end_msc - start_msc;
      if(span <= 0)
         return 1.0;
      return (double)(now_msc - start_msc) / (double)span;
     }

   string            ToString(void)
     {
      return StringFormat("clock[now=%s speed=%s progress=%.1f%% steps=%I64u]",
                          SSRFormatMscMs(now_msc), SSRSpeedName(speed_x100),
                          Progress() * 100.0, steps);
     }
  };

#endif // SSR_REPLAY_CLOCK_MQH
//+------------------------------------------------------------------+

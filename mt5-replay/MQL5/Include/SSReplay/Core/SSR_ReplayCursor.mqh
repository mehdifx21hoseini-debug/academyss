//+------------------------------------------------------------------+
//|                                              SSR_ReplayCursor.mqh |
//|                                    SS Replay - Replay Cursor(L2) |
//|                                                                  |
//|  Tracks HOW FAR THE STREAM HAS BEEN CONSUMED, which is not the   |
//|  same as where the clock is.                                     |
//|                                                                  |
//|  The clock says "replay time is now 10:37:04.500".               |
//|  The cursor says "everything up to and including 10:37:04.500    |
//|  has already been emitted to the sink".                          |
//|                                                                  |
//|  Keeping them apart is what makes the emit range half-open -     |
//|  (emitted, now] - so no tick is ever emitted twice and none is   |
//|  skipped when a pump delivers a zero-length delta.               |
//+------------------------------------------------------------------+
#ifndef SSR_REPLAY_CURSOR_MQH
#define SSR_REPLAY_CURSOR_MQH

#include "../Common/SSR_Types.mqh"
#include "../Common/SSR_Time.mqh"

//+------------------------------------------------------------------+
struct SSRReplayCursor
  {
   long              emitted_msc;    // last instant handed to the sink
   long              bar_msc;        // open time of the last consumed M1 bar
   long              tick_count;     // ticks emitted since the last reset
   long              bar_count;      // bars consumed since the last reset

   void              Init(void)
     {
      emitted_msc = SSR_INVALID_TIME;
      bar_msc     = SSR_INVALID_TIME;
      tick_count  = 0;
      bar_count   = 0;
     }

   //--- position the cursor just BEFORE `msc`, so the first pump
   //--- emits the instant `msc` itself rather than skipping it
   void              RewindTo(const long msc)
     {
      emitted_msc = msc - 1;
      bar_msc     = SSR_INVALID_TIME;
      tick_count  = 0;
      bar_count   = 0;
     }

   bool              IsPositioned(void) { return (emitted_msc != SSR_INVALID_TIME); }

   //--- the half-open window still owed to the sink, given a clock time
   bool              PendingRange(const long now_msc, long &from_msc, long &to_msc)
     {
      if(!IsPositioned())
         return false;
      from_msc = emitted_msc + 1;
      to_msc   = now_msc;
      return (from_msc <= to_msc);
     }

   void              Advance(const long to_msc, const int ticks, const int bars)
     {
      if(to_msc > emitted_msc)
         emitted_msc = to_msc;
      tick_count += ticks;
      bar_count  += bars;
     }

   void              NoteBar(const long a_bar_msc)
     {
      bar_msc = a_bar_msc;
     }

   string            ToString(void)
     {
      return StringFormat("cursor[emitted=%s ticks=%d bars=%d]",
                          SSRFormatMscMs(emitted_msc), (int)tick_count, (int)bar_count);
     }
  };

#endif // SSR_REPLAY_CURSOR_MQH
//+------------------------------------------------------------------+

//+------------------------------------------------------------------+
//|                                              SSR_MasterClock.mqh |
//|                    SS Replay - The Master Replay Clock (L2/Core) |
//|                                                                  |
//|  ONE CLOCK, N STREAMS.                                           |
//|                                                                  |
//|  Replaying EURUSD and XAUUSD side by side is only worth anything |
//|  if 10:31 on one chart is 10:31 on the other. The obvious way -  |
//|  hand both controllers the same elapsed milliseconds and trust   |
//|  them - does not hold: each scales the delta by its own speed    |
//|  and carries its own residue, so a speed change lands on them a  |
//|  pump apart and they separate by a few milliseconds that never   |
//|  come back.                                                      |
//|                                                                  |
//|  So no stream keeps time. This clock does, and every stream is   |
//|  told the INSTANT to advance to. There is nothing left to drift. |
//|                                                                  |
//|  WHAT THIS DOES NOT DO                                           |
//|  It does not own the controllers, load them, or know what        |
//|  symbols they carry. The host builds each stream and hands it    |
//|  over. This object only decides when.                            |
//+------------------------------------------------------------------+
#ifndef SSR_MASTER_CLOCK_MQH
#define SSR_MASTER_CLOCK_MQH

#include "../Common/SSR_Types.mqh"
#include "../Common/SSR_Time.mqh"
#include "SSR_ReplayClock.mqh"
#include "SSR_ReplayController.mqh"

//--- streams on one clock. Four instruments is already an unusual
//--- amount to watch at once; the ceiling exists so the array is fixed
//--- and the memory is knowable, not because five would be wrong.
#define SSR_MAX_STREAMS   4

//+------------------------------------------------------------------+
class CSSRReplayGroup
  {
private:
   CSSRReplayController *m_member[SSR_MAX_STREAMS];   // not owned
   int                   m_count;

   SSRReplayClock        m_master;
   bool                  m_aligned;
   string                m_last_error;
   string                m_pause_reason;
   long                  m_pumps;
   long                  m_group_pauses;

   void              Fail(const string why) { m_last_error = why; }

public:
                     CSSRReplayGroup(void)
     : m_count(0), m_aligned(false), m_last_error(""), m_pause_reason(""),
       m_pumps(0), m_group_pauses(0)
     {
      m_master.Init();
      for(int i = 0; i < SSR_MAX_STREAMS; i++)
         m_member[i] = NULL;
     }

   //--- membership ---------------------------------------------------
   bool              Add(CSSRReplayController *c)
     {
      if(c == NULL)
        { Fail("null stream"); return false; }
      if(m_count >= SSR_MAX_STREAMS)
        { Fail("too many streams"); return false; }
      for(int i = 0; i < m_count; i++)
         if(m_member[i] == c)
            return true;                  // already in

      m_member[m_count++] = c;
      m_aligned = false;                  // the common window changed
      return true;
     }

   void              Clear(void)
     {
      for(int i = 0; i < SSR_MAX_STREAMS; i++)
         m_member[i] = NULL;
      m_count   = 0;
      m_aligned = false;
      m_master.Init();
     }

   int               Count(void) { return m_count; }
   CSSRReplayController *At(const int i)
     { return (i >= 0 && i < m_count ? m_member[i] : NULL); }

   string            LastError(void)   { return m_last_error; }
   bool              IsAligned(void)   { return m_aligned; }
   long              Pumps(void)       { return m_pumps; }
   long              GroupPauses(void) { return m_group_pauses; }

   //+------------------------------------------------------------------+
   //| Find the window every stream can actually replay, and put them   |
   //| all at the start of it.                                          |
   //|                                                                  |
   //| The window is the INTERSECTION, not the union. Replaying a       |
   //| stretch one instrument has no data for would show that chart     |
   //| frozen while the others move - which reads as a bug, and is at   |
   //| best a silent claim that the market was flat.                    |
   //+------------------------------------------------------------------+
   bool              Align(void)
     {
      m_last_error = "";
      m_aligned    = false;
      if(m_count == 0)
        { Fail("no streams"); return false; }

      long lo = 0, hi = 0;
      for(int i = 0; i < m_count; i++)
        {
         if(!m_member[i].TimelineValid())
           {
            Fail(StringFormat("stream %d (%s) has no timeline - load it first",
                              i, m_member[i].Symbol()));
            return false;
           }
         long s = m_member[i].StartMsc();
         long e = m_member[i].EndMsc();
         if(i == 0)
           { lo = s; hi = e; }
         else
           {
            if(s > lo) lo = s;
            if(e < hi) hi = e;
           }
        }

      if(hi <= lo)
        {
         Fail("these instruments share no common period - "
              "the streams do not overlap in time");
         return false;
        }

      if(!m_master.Configure(lo, hi))
        { Fail("master clock rejected the common window"); return false; }

      //--- and every stream starts where the common window does, and
      //--- ENDS where it does. Without the second half, a stream whose
      //--- own history runs past the common window would never report
      //--- itself finished, and the board would wait forever for it.
      for(int i = 0; i < m_count; i++)
        {
         m_member[i].SetSpeedX100(m_master.speed_x100);
         if(m_member[i].EndMsc() > hi)
            m_member[i].NarrowEndTo(hi);
         if(m_member[i].Now() != lo && !m_member[i].JumpTo(lo))
           {
            Fail(StringFormat("stream %d (%s) could not start at %s: %s",
                              i, m_member[i].Symbol(), SSRFormatMsc(lo),
                              m_member[i].LastErrorText()));
            return false;
           }
        }

      m_aligned = true;
      return true;
     }

   //--- the common window -------------------------------------------
   long              StartMsc(void)    { return m_master.start_msc; }
   long              EndMsc(void)      { return m_master.end_msc; }
   long              Now(void)         { return m_master.now_msc; }
   double            Progress(void)    { return m_master.Progress(); }
   long              SpeedX100(void)   { return m_master.speed_x100; }
   bool              IsCompleted(void) { return m_master.IsCompleted(); }

   //+------------------------------------------------------------------+
   //| One pump for the whole board.                                    |
   //|                                                                  |
   //| The master takes the wall delta; every stream is told the        |
   //| instant, never the delta.                                        |
   //+------------------------------------------------------------------+
   int               Pump(const ulong wall_delta_ms)
     {
      if(!m_aligned)
         return 0;

      long target  = m_master.Advance(wall_delta_ms);
      int  emitted = 0;
      m_pumps++;

      for(int i = 0; i < m_count; i++)
        {
         int n = m_member[i].PumpTo(target);
         if(n > 0)
            emitted += n;
        }

      //--- IF ONE STREAM STOPS, THE BOARD STOPS. A stop hit on gold
      //--- while the euro chart runs on is exactly the moment the user
      //--- asked to be shown, so it must not scroll off the others.
      PropagatePause();
      return emitted;
     }

   //--- a stream that paused itself pauses everyone
   void              PropagatePause(void)
     {
      int paused_by = -1;
      for(int i = 0; i < m_count; i++)
         if(m_member[i].Status() == SSR_STATE_PAUSED &&
            m_member[i].PauseReason() != "")
           { paused_by = i; break; }

      if(paused_by < 0)
         return;

      m_pause_reason = StringFormat("%s: %s",
                                    m_member[paused_by].Symbol(),
                                    m_member[paused_by].PauseReason());
      m_group_pauses++;
      for(int i = 0; i < m_count; i++)
         if(m_member[i].Status() == SSR_STATE_PLAYING)
            m_member[i].Pause();
     }

   string            PauseReason(void) { return m_pause_reason; }
   void              ClearPauseReason(void)
     {
      m_pause_reason = "";
      for(int i = 0; i < m_count; i++)
         m_member[i].ClearPauseReason();
     }

   //--- transport, fanned out ----------------------------------------
   bool              Play(void)
     {
      if(!m_aligned)
        { Fail("align the group first"); return false; }
      ClearPauseReason();
      bool any = false;
      for(int i = 0; i < m_count; i++)
         if(m_member[i].Play())
            any = true;
      if(!any)
         Fail("no stream could start");
      return any;
     }

   bool              Pause(void)
     {
      bool any = false;
      for(int i = 0; i < m_count; i++)
         if(m_member[i].Status() == SSR_STATE_PLAYING && m_member[i].Pause())
            any = true;
      return any;
     }

   void              SetSpeedX100(const long s)
     {
      m_master.SetSpeedX100(s);
      //--- the streams are told too, so one detached from the group
      //--- later still runs at the speed the user chose
      for(int i = 0; i < m_count; i++)
         m_member[i].SetSpeedX100(m_master.speed_x100);
     }

   //+------------------------------------------------------------------+
   //| Every navigation verb moves the MASTER first, then takes every   |
   //| stream to exactly that instant. Letting each stream work out its |
   //| own destination is how "step back 10 bars" ends with two charts  |
   //| a bar apart.                                                     |
   //+------------------------------------------------------------------+
   bool              SeekAllTo(const long target_msc)
     {
      if(!m_aligned)
        { Fail("align the group first"); return false; }
      if(!m_master.SeekTo(target_msc))
        { Fail("master clock refused that instant"); return false; }

      long t  = m_master.now_msc;
      bool ok = true;
      for(int i = 0; i < m_count; i++)
         if(!m_member[i].JumpTo(t))
           {
            Fail(StringFormat("%s could not reach %s: %s",
                              m_member[i].Symbol(), SSRFormatMsc(t),
                              m_member[i].LastErrorText()));
            ok = false;
           }

      //--- THE MASTER FOLLOWS THE STREAMS BACK, not the other way round.
      //--- A backward jump is bar-granular - a stream lands on the M1
      //--- boundary at or below what was asked, because that is where a
      //--- replay can honestly stand. Leaving the master on the exact
      //--- instant the user typed would make it disagree with every
      //--- chart on the board while reporting perfect alignment.
      if(m_count > 0)
         m_master.SeekTo(m_member[0].Now());
      return ok;
     }

   bool              JumpTo(const long target_msc) { return SeekAllTo(target_msc); }

   bool              StepBars(const int bars)
     {
      if(!m_aligned || bars <= 0)
         return false;
      long target = SSRNextBarOpenMsc(m_master.now_msc, PERIOD_M1)
                    + (long)(bars - 1) * SSR_MSC_PER_MIN - 1;
      if(target > m_master.end_msc)
         target = m_master.end_msc;

      m_master.SeekTo(target);
      long t = m_master.now_msc;
      for(int i = 0; i < m_count; i++)
        {
         //--- forward is a PUMP, not a seek: the bars in between are
         //--- data the observers are entitled to see
         bool was_playing = (m_member[i].Status() == SSR_STATE_PLAYING);
         if(!was_playing)
            m_member[i].Play();
         m_member[i].PumpTo(t);
         if(!was_playing)
            m_member[i].Pause();
        }
      return true;
     }

   bool              StepBackward(const int bars)
     {
      if(!m_aligned || bars <= 0)
         return false;
      long target = SSRBarOpenMsc(m_master.now_msc, PERIOD_M1)
                    - (long)bars * SSR_MSC_PER_MIN;
      return SeekAllTo(target);
     }

   bool              Restart(void)
     {
      if(!m_aligned)
         return false;
      return SeekAllTo(m_master.start_msc);
     }

   //--- queries ------------------------------------------------------
   bool              AnyPlaying(void)
     {
      for(int i = 0; i < m_count; i++)
         if(m_member[i].Status() == SSR_STATE_PLAYING)
            return true;
      return false;
     }

   bool              AllCompleted(void)
     {
      if(m_count == 0)
         return false;
      for(int i = 0; i < m_count; i++)
         if(m_member[i].Status() != SSR_STATE_COMPLETED)
            return false;
      return true;
     }

   //+------------------------------------------------------------------+
   //| The largest gap between any two LIVE streams. Zero is the        |
   //| contract, and this is how a test proves it rather than assuming. |
   //|                                                                  |
   //| A stream that has COMPLETED is excluded on purpose. Its data ran |
   //| out; it is behind because there is nothing left to show, not     |
   //| because the clock failed. Counting it would raise a drift alarm  |
   //| every time one instrument's history ends before another's, and   |
   //| an alarm that cries wolf is worse than no alarm.                 |
   //+------------------------------------------------------------------+
   long              MaxSkewMsc(void)
     {
      long lo = 0, hi = 0;
      int  live = 0;
      for(int i = 0; i < m_count; i++)
        {
         if(m_member[i].Status() == SSR_STATE_COMPLETED)
            continue;
         long n = m_member[i].Now();
         if(live == 0)
           { lo = n; hi = n; }
         else
           {
            if(n < lo) lo = n;
            if(n > hi) hi = n;
           }
         live++;
        }
      return (live < 2 ? 0 : hi - lo);
     }

   //--- how many streams still have data to show
   int               LiveCount(void)
     {
      int n = 0;
      for(int i = 0; i < m_count; i++)
         if(m_member[i].Status() != SSR_STATE_COMPLETED)
            n++;
      return n;
     }

   string            ToString(void)
     {
      return StringFormat("group[%d streams  %s  %s  skew=%I64dms  pumps=%I64d]",
                          m_count, SSRFormatMsc(m_master.now_msc),
                          SSRSpeedName(m_master.speed_x100),
                          MaxSkewMsc(), m_pumps);
     }
  };

#endif // SSR_MASTER_CLOCK_MQH
//+------------------------------------------------------------------+

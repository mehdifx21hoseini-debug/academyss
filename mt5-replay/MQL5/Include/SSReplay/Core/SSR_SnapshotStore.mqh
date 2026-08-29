//+------------------------------------------------------------------+
//|                                            SSR_SnapshotStore.mqh |
//|                    SS Replay - Checkpoints and Bookmarks (L2)    |
//|                                                                  |
//|  WHY REWIND NEEDS THIS AND A PLAIN SEEK DOES NOT DO              |
//|                                                                  |
//|  Seeking backwards already truncates the sink correctly, so for a |
//|  moment it looks as though snapshots are ceremony. They are not,  |
//|  for a reason that is visible today and becomes severe later.     |
//|                                                                  |
//|  A rewind resets the cursor, and the cursor carries the session's |
//|  counters. Seek them back by hand and the tick count restarts     |
//|  from zero rather than returning to what it was at that instant - |
//|  so a user who steps back one bar loses the whole session's       |
//|  statistics. Once Phase 9 puts a virtual account behind the same  |
//|  cursor, that stops being a cosmetic wrong number and becomes     |
//|  trades that happened in a future which no longer exists.         |
//|                                                                  |
//|  So: restore state, never reconstruct it.                         |
//|                                                                  |
//|  Checkpoints are taken automatically on a replay-time interval,   |
//|  which keeps a step back O(one interval) instead of O(session).   |
//+------------------------------------------------------------------+
#ifndef SSR_SNAPSHOT_STORE_MQH
#define SSR_SNAPSHOT_STORE_MQH

#include "../Common/SSR_Types.mqh"
#include "../Common/SSR_Time.mqh"
#include "SSR_Snapshot.mqh"

//--- automatic checkpoints, in REPLAY time. Five minutes means a step
//--- back never replays more than five minutes of market to get exact.
#define SSR_CHECKPOINT_INTERVAL_MSC   (5 * 60 * 1000)
//--- ring depth. 64 x 5 minutes is over five hours of rewindable
//--- history at full precision, which outlasts any single session.
#define SSR_CHECKPOINT_RING           64
#define SSR_BOOKMARK_MAX              16

//+------------------------------------------------------------------+
class CSSRSnapshotStore
  {
private:
   SSRSnapshot       m_ring[SSR_CHECKPOINT_RING];
   int               m_count;      // filled slots, up to the ring size
   int               m_head;       // next slot to write
   long              m_interval;
   long              m_last_msc;   // replay time of the newest checkpoint

   SSRSnapshot       m_marks[SSR_BOOKMARK_MAX];
   int               m_mark_count;

   long              m_taken;
   long              m_restores;

public:
                     CSSRSnapshotStore(void) { Clear(); }

   //+------------------------------------------------------------------+
   //| Drop the playback machinery but keep the user's marks.           |
   //|                                                                  |
   //| A checkpoint is ours; a bookmark is theirs - a moment they chose |
   //| to come back to. Restarting the same session must not throw the  |
   //| second away with the first.                                      |
   //+------------------------------------------------------------------+
   void              ClearCheckpoints(void)
     {
      for(int i = 0; i < SSR_CHECKPOINT_RING; i++)
         m_ring[i].Init();
      m_count = 0; m_head = 0;
      m_last_msc = SSR_INVALID_TIME;
      m_taken = 0; m_restores = 0;
     }

   //--- everything, for a genuinely new session
   void              Clear(void)
     {
      ClearCheckpoints();
      for(int i = 0; i < SSR_BOOKMARK_MAX; i++)
         m_marks[i].Init();
      m_interval   = SSR_CHECKPOINT_INTERVAL_MSC;
      m_mark_count = 0;
     }

   void              SetInterval(const long msc)
     { m_interval = (msc < 1000 ? 1000 : msc); }
   long              Interval(void)   { return m_interval; }
   int               Count(void)      { return m_count; }
   int               Bookmarks(void)  { return m_mark_count; }
   long              Taken(void)      { return m_taken; }
   long              Restores(void)   { return m_restores; }

   //--- is a checkpoint due at this replay time?
   bool              IsDue(const long now_msc)
     {
      if(m_last_msc == SSR_INVALID_TIME)
         return true;
      return (now_msc - m_last_msc >= m_interval);
     }

   //+------------------------------------------------------------------+
   void              Checkpoint(SSRSnapshot &snap)
     {
      if(!snap.IsValid())
         return;
      m_ring[m_head] = snap;
      m_head = (m_head + 1) % SSR_CHECKPOINT_RING;
      if(m_count < SSR_CHECKPOINT_RING)
         m_count++;
      m_last_msc = snap.taken_at_msc;
      m_taken++;
     }

   //+------------------------------------------------------------------+
   //| The newest checkpoint at or before `msc`.                        |
   //|                                                                  |
   //| "At or before" matters: restoring to a point AFTER the target    |
   //| would leave data the caller is trying to remove.                 |
   //+------------------------------------------------------------------+
   bool              NearestAtOrBefore(const long msc, SSRSnapshot &out)
     {
      bool found = false;
      long best  = SSR_INVALID_TIME;
      for(int i = 0; i < m_count; i++)
        {
         long t = m_ring[i].taken_at_msc;
         if(t <= 0 || t > msc)
            continue;
         if(!found || t > best)
           {
            best  = t;
            out   = m_ring[i];
            found = true;
           }
        }
      return found;
     }

   //--- everything at or after `msc` describes a future that was just
   //--- discarded, so it must go with it
   int               DropFrom(const long msc)
     {
      int dropped = 0;
      for(int i = 0; i < m_count; i++)
        {
         if(m_ring[i].taken_at_msc >= msc)
           {
            m_ring[i].Init();
            dropped++;
           }
        }
      //--- recompute the newest surviving checkpoint
      m_last_msc = SSR_INVALID_TIME;
      for(int i = 0; i < m_count; i++)
        {
         long t = m_ring[i].taken_at_msc;
         if(t > 0 && (m_last_msc == SSR_INVALID_TIME || t > m_last_msc))
            m_last_msc = t;
        }
      return dropped;
     }

   void              NoteRestore(void) { m_restores++; }

   //--- bookmarks -----------------------------------------------------
   bool              Mark(SSRSnapshot &snap, const string label)
     {
      if(m_mark_count >= SSR_BOOKMARK_MAX || !snap.IsValid())
         return false;
      m_marks[m_mark_count] = snap;
      m_marks[m_mark_count].label = label;
      m_mark_count++;
      return true;
     }

   bool              GetMark(const int i, SSRSnapshot &out)
     {
      if(i < 0 || i >= m_mark_count)
         return false;
      out = m_marks[i];
      return true;
     }

   string            MarkLabel(const int i)
     {
      if(i < 0 || i >= m_mark_count)
         return "";
      return StringFormat("%s  %s", m_marks[i].label,
                          SSRFormatMsc(m_marks[i].taken_at_msc));
     }

   void              ClearMarks(void) { m_mark_count = 0; }

   string            ToString(void)
     {
      return StringFormat("snapshots[%d/%d every %s  marks=%d  taken=%d restored=%d]",
                          m_count, SSR_CHECKPOINT_RING,
                          SSRFormatSpan(m_interval), m_mark_count,
                          (int)m_taken, (int)m_restores);
     }
  };

#endif // SSR_SNAPSHOT_STORE_MQH
//+------------------------------------------------------------------+

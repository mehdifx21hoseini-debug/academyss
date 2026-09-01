//+------------------------------------------------------------------+
//|                                                 SSR_ShotBook.mqh |
//|                SS Replay - A Picture Of Every Trade (L2/Trading) |
//|                                                                  |
//|  What a student sends their coach afterwards is a number. What    |
//|  they should be sending is the chart they were looking at when    |
//|  they pressed the button, and the chart when it ended. The        |
//|  platform has had ChartScreenShot all along.                      |
//|                                                                  |
//|  HOW IT KNOWS a trade opened: by WATCHING, exactly the way        |
//|  CSSRTradeAutoPause does. The trading engine gets no callback     |
//|  list and no knowledge that anyone is looking, so there is no     |
//|  second path through which a trade can be recorded and forgotten. |
//|                                                                  |
//|  WHY IT LIVES IN Trading/ rather than Chart/: it knows one long   |
//|  and calls one built-in, while the journal - which has to print   |
//|  the pictures - lives here. A Chart/ header would buy nothing and |
//|  cost Trading a dependency on a layer above it.                   |
//|                                                                  |
//|  THE SHOT IS DEFERRED BY ONE PASS, and that is the whole trick.   |
//|  A screenshot taken inside OnTicks is taken before MetaTrader has |
//|  repainted the candle the trade happened on - the picture would   |
//|  show the bar before the entry, which is worse than no picture    |
//|  because it looks right. So a transition only QUEUES a shot; the  |
//|  host flushes the queue at the top of its next timer pass, by     |
//|  which time the redraw that put the new bar on screen has run.    |
//+------------------------------------------------------------------+
#ifndef SSR_SHOTBOOK_MQH
#define SSR_SHOTBOOK_MQH

#include "../Common/SSR_Types.mqh"
#include "../Common/SSR_Time.mqh"
#include "../Core/SSR_ITickObserver.mqh"
#include "SSR_TradingEngine.mqh"

//--- under the journal, so a statement can reach its own pictures with
//--- a relative path and the pair survives being copied somewhere else
#define SSR_SHOT_DIR      "SSReplay\\journal\\shots"

//--- a ceiling, because this writes PNGs to the user's disk. Five
//--- hundred is more trades than any practice session, and a runaway
//--- that would otherwise fill a drive stops and says so instead.
#define SSR_SHOT_MAX      500

//--- the chart's own size is used, so the picture is what the user saw.
//--- Bounded at both ends: a 4K chart would write megabytes per trade,
//--- and a chart that has not been measured yet reports zero.
#define SSR_SHOT_W_MAX    1600
#define SSR_SHOT_H_MAX     900
#define SSR_SHOT_W_MIN     800
#define SSR_SHOT_H_MIN     450

#define SSR_SHOT_ENTRY    0
#define SSR_SHOT_EXIT     1

//--- one name, in one place. The journal prints these paths and the
//--- book writes them; two spellings of the same convention is how a
//--- statement comes to link pictures that are not there.
string SSRShotFile(const long ticket, const bool entry)
  { return StringFormat("t%d-%s.png", (int)ticket, (entry ? "in" : "out")); }

//+------------------------------------------------------------------+
class CSSRShotBook : public CSSRTickObserver
  {
private:
   CSSRTradingEngine *m_acct;         // not owned
   long               m_chart;
   bool               m_on;

   //+------------------------------------------------------------------+
   //| A FOLDER PER RUN, and it is not tidiness.                        |
   //|                                                                  |
   //| Tickets restart at 1 with every session. Without a run folder,   |
   //| session two's statement would link session one's pictures for    |
   //| the same ticket numbers - a statement showing the wrong chart     |
   //| beside the right numbers, which is worse than showing none.       |
   //+------------------------------------------------------------------+
   string             m_run;

   uchar              m_seen[];       // last state per slot, as AutoPause
   int                m_seen_count;

   long               m_q_ticket[];
   uchar              m_q_kind[];
   int                m_queued;

   int                m_taken;
   int                m_failed;
   bool               m_capped;
   string             m_last_error;

   string             RunFolder(void)
     { return SSR_SHOT_DIR + "\\" + m_run; }

   void               Queue(const long ticket, const uchar kind)
     {
      if(m_queued >= ArraySize(m_q_ticket) &&
         ArrayResize(m_q_ticket, m_queued + 16) != m_queued + 16)
         return;
      if(ArraySize(m_q_kind) < ArraySize(m_q_ticket) &&
         ArrayResize(m_q_kind, ArraySize(m_q_ticket)) != ArraySize(m_q_ticket))
         return;
      m_q_ticket[m_queued] = ticket;
      m_q_kind[m_queued]   = kind;
      m_queued++;
     }

   //--- the same comparison AutoPause makes, for the same reason: a
   //--- position that opens and closes between two looks is a scalp,
   //--- not an exotic case, and first sight of a closed slot is an
   //--- event rather than an adoption
   void               Scan(void)
     {
      if(!m_on || m_acct == NULL || m_chart == 0 || m_capped)
         return;

      int total = m_acct.Total();
      if(total > SSR_MAX_POSITIONS)
         total = SSR_MAX_POSITIONS;
      if(ArraySize(m_seen) < total && ArrayResize(m_seen, total) != total)
         return;

      for(int i = 0; i < total; i++)
        {
         SSRVirtualPosition p;
         if(!m_acct.At(i, p))
            continue;

         uchar now = (uchar)p.state;
         uchar was = (i < m_seen_count ? m_seen[i] : (uchar)255);
         m_seen[i] = now;
         if(was == now)
            continue;

         if(now == SSR_POS_OPEN)
            Queue(p.ticket, SSR_SHOT_ENTRY);
         else
            if(now == SSR_POS_CLOSED)
              {
               //--- a slot never seen open, now closed, opened and closed
               //--- between two looks. Both pictures are owed.
               if(was != (uchar)SSR_POS_OPEN)
                  Queue(p.ticket, SSR_SHOT_ENTRY);
               Queue(p.ticket, SSR_SHOT_EXIT);
              }
        }
      m_seen_count = total;
     }

   bool               Shoot(const long ticket, const bool entry)
     {
      int w = (int)ChartGetInteger(m_chart, CHART_WIDTH_IN_PIXELS);
      int h = (int)ChartGetInteger(m_chart, CHART_HEIGHT_IN_PIXELS);
      if(w < SSR_SHOT_W_MIN) w = SSR_SHOT_W_MIN;
      if(h < SSR_SHOT_H_MIN) h = SSR_SHOT_H_MIN;
      if(w > SSR_SHOT_W_MAX) w = SSR_SHOT_W_MAX;
      if(h > SSR_SHOT_H_MAX) h = SSR_SHOT_H_MAX;

      //--- created on the FIRST shot, not at session start: a session
      //--- where nobody traded leaves nothing behind on the disk
      FolderCreate(RunFolder());

      string path = RunFolder() + "\\" + SSRShotFile(ticket, entry);
      if(!ChartScreenShot(m_chart, path, w, h, ALIGN_RIGHT))
        {
         m_failed++;
         m_last_error = StringFormat("ChartScreenShot refused %s (err %d)",
                                     path, GetLastError());
         return false;
        }
      m_taken++;
      return true;
     }

public:
                     CSSRShotBook(void)
     : m_acct(NULL), m_chart(0), m_on(false), m_run(""), m_seen_count(0),
       m_queued(0), m_taken(0), m_failed(0), m_capped(false),
       m_last_error("") {}

   virtual string    Name(void) override { return "screenshots"; }

   void              Attach(CSSRTradingEngine *a) { m_acct = a; }
   void              SetChart(const long id)      { m_chart = id; }
   void              Enable(const bool on)        { m_on = on; }
   bool              IsOn(void)                   { return m_on; }
   int               Taken(void)                  { return m_taken; }
   int               Failed(void)                 { return m_failed; }
   int               Pending(void)                { return m_queued; }
   string            Run(void)                    { return m_run; }
   string            LastError(void)              { return m_last_error; }

   //--- a fresh run id, so this session's pictures cannot be confused
   //--- with the last one's. Seconds are in it because two runs in the
   //--- same minute is a thing people do while testing.
   void              NewRun(void)
     {
      string s = TimeToString(TimeLocal(), TIME_DATE | TIME_SECONDS);
      StringReplace(s, ".", "");
      StringReplace(s, ":", "");
      StringReplace(s, " ", "-");
      m_run    = s;
      m_taken  = 0;
      m_failed = 0;
      m_capped = false;
     }

   //+------------------------------------------------------------------+
   //| WHERE THE STATEMENT SHOULD LOOK, or an empty string.             |
   //|                                                                  |
   //| Relative to the journal folder the statement is written into, so |
   //| the page and its pictures travel together. It checks the file is |
   //| really there rather than trusting the count: a broken image icon |
   //| in a document a student hands in is worse than no column at all. |
   //+------------------------------------------------------------------+
   string            RelPath(const long ticket, const bool entry)
     {
      if(m_run == "")
         return "";
      string file = SSRShotFile(ticket, entry);
      if(!FileIsExist(RunFolder() + "\\" + file))
         return "";
      return "shots/" + m_run + "/" + file;
     }

   //+------------------------------------------------------------------+
   //| Take what is owed. Called by the host at the TOP of a timer pass,|
   //| so a full interval - and the redraw inside it - has gone by      |
   //| since the transition that queued the shot.                       |
   //+------------------------------------------------------------------+
   int               Flush(void)
     {
      if(m_queued <= 0)
         return 0;
      if(!m_on || m_chart == 0)
        { m_queued = 0; return 0; }
      if(m_run == "")
         NewRun();

      int done = 0;
      for(int i = 0; i < m_queued; i++)
        {
         if(m_taken >= SSR_SHOT_MAX)
           {
            if(!m_capped)
              {
               m_capped = true;
               PrintFormat("[shots] %d taken - that is the ceiling for one "
                           "run. No more will be written; the trades are "
                           "still recorded.", SSR_SHOT_MAX);
              }
            break;
           }
         if(Shoot(m_q_ticket[i], m_q_kind[i] == SSR_SHOT_ENTRY))
            done++;
        }
      m_queued = 0;
      return done;
     }

   //--- the observer contract. Registered AFTER the trading engine, so
   //--- by the time this looks the engine has filled and stopped out.
   virtual void      OnTicks(const MqlTick &ticks[], const int count) override
     { Scan(); }

   //+------------------------------------------------------------------+
   //| A rewind deletes the future these pictures were taken in.        |
   //|                                                                  |
   //| The PNG files are deliberately LEFT ALONE. Replaying the same    |
   //| minute writes the same ticket's file again and the new picture   |
   //| replaces the old one; deleting on rewind would instead mean a    |
   //| step back and forward over a trade left the statement with a     |
   //| missing image and no way to tell that from a failed shot.        |
   //+------------------------------------------------------------------+
   virtual void      OnRewind(const long msc) override
     {
      m_queued = 0;
      Reseed();
     }

   virtual void      OnSessionStart(const string symbol, const int digits,
                                    const double point, const long start_msc) override
     {
      m_queued = 0;
      NewRun();
      Reseed();
     }

   //--- adopt what is already true without owing a picture for it
   void              Reseed(void)
     {
      m_seen_count = 0;
      if(m_acct == NULL)
         return;
      int total = m_acct.Total();
      if(total > SSR_MAX_POSITIONS)
         total = SSR_MAX_POSITIONS;
      if(ArraySize(m_seen) < total && ArrayResize(m_seen, total) != total)
         return;
      for(int i = 0; i < total; i++)
        {
         SSRVirtualPosition p;
         if(m_acct.At(i, p))
            m_seen[i] = (uchar)p.state;
        }
      m_seen_count = total;
     }
  };

#endif // SSR_SHOTBOOK_MQH
//+------------------------------------------------------------------+

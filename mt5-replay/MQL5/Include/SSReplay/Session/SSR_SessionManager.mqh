//+------------------------------------------------------------------+
//|                                           SSR_SessionManager.mqh |
//|                    SS Replay - Save And Resume A Session (L5)    |
//|                                                                  |
//|  A NEW LAYER, and it is above everything.                        |
//|                                                                  |
//|  Saving a session touches the engine, the account, the           |
//|  statistics and the chart settings. Something has to know all    |
//|  four, and the one rule that has held since Phase 1 is that no    |
//|  lower layer learns about a higher one. So this object sits at    |
//|  the top beside Ui and depends downward on everything, and        |
//|  NOTHING depends on it.                                          |
//|                                                                  |
//|  WHAT A SESSION FILE CONTAINS, AND WHAT IT DELIBERATELY DOES NOT |
//|                                                                  |
//|  Stored: the window, the instant reached, every stream's cursor, |
//|  the virtual account in full - open and closed trades, their     |
//|  partial exits, the execution assumptions they were priced       |
//|  under - the equity curve, the bookmarks, and the settings.      |
//|                                                                  |
//|  Not stored: the price data, and every statistic that can be     |
//|  derived from the trades. The data is re-read from the broker,   |
//|  which is why a fingerprint travels with the file. The derived   |
//|  statistics are recomputed, because a stored copy that disagreed |
//|  with the trades would be believed over the trades.              |
//|                                                                  |
//|  Not stored, and this one matters: ANYTHING BEYOND THE INSTANT   |
//|  REACHED. A session file records where the trader got to. There  |
//|  is nothing in it that a resume could use to see further.        |
//+------------------------------------------------------------------+
#ifndef SSR_SESSION_MANAGER_MQH
#define SSR_SESSION_MANAGER_MQH

#include "../Common/SSR_Types.mqh"
#include "../Common/SSR_Time.mqh"
#include "../Common/SSR_SessionFile.mqh"
#include "../Common/SSR_Fingerprint.mqh"
#include "../Core/SSR_MasterClock.mqh"
#include "../Trading/SSR_TradingEngine.mqh"
#include "../Trading/SSR_Statistics.mqh"
#include "../Chart/SSR_BlindMode.mqh"

#define SSR_SESSION_DIR   "SSReplay\\sessions"
#define SSR_SESSION_EXT   ".ssr"

//+------------------------------------------------------------------+
//| Everything about a session that is a CHOICE rather than a state. |
//| Kept as one struct so the host writes and reads it in one place  |
//| and cannot forget a field.                                       |
//+------------------------------------------------------------------+
struct SSRSessionSettings
  {
   ulong             seed;             // 0 when the session was not random
   int               blind;            // ENUM_SSR_BLIND
   int               pause_flags;      // trade auto-pause
   int               session_mode;     // ENUM_SSR_SESSION_MODE
   int               slot;
   int               ticks_per_bar;
   double            spread_points;
   ENUM_TIMEFRAMES   chart_tf;

   void              Init(void)
     {
      seed = 0; blind = 0; pause_flags = 0; session_mode = 0;
      slot = 1; ticks_per_bar = 8; spread_points = 0.0;
      chart_tf = PERIOD_M5;
     }
  };

//+------------------------------------------------------------------+
class CSSRSessionManager
  {
private:
   CSSRReplayGroup   *m_group;      // not owned
   CSSRTradingEngine *m_acct;       // not owned; may be NULL
   CSSRStatsEngine   *m_stats;      // not owned; may be NULL

   string             m_last_error;
   string             m_warnings;    // things the user must be told
   string             m_last_path;
   int                m_streams_restored;

   void               Fail(const string why) { m_last_error = why; }

   void               Warn(const string text)
     {
      if(text == "")
         return;
      m_warnings += (m_warnings == "" ? "" : "\n") + text;
     }

   string             Path(const string name)
     {
      string safe = name;
      StringReplace(safe, "\\", "_");
      StringReplace(safe, "/",  "_");
      StringReplace(safe, ":",  "_");
      return SSR_SESSION_DIR + "\\" + safe + SSR_SESSION_EXT;
     }

public:
                     CSSRSessionManager(void)
     : m_group(NULL), m_acct(NULL), m_stats(NULL), m_last_error(""),
       m_warnings(""), m_last_path(""), m_streams_restored(0) {}

   void              Attach(CSSRReplayGroup *g, CSSRTradingEngine *a = NULL,
                            CSSRStatsEngine *s = NULL)
     { m_group = g; m_acct = a; m_stats = s; }

   string            LastError(void)  { return m_last_error; }
   string            Warnings(void)   { return m_warnings; }
   bool              HadWarnings(void){ return (m_warnings != ""); }
   string            LastPath(void)   { return m_last_path; }
   int               StreamsRestored(void) { return m_streams_restored; }

   bool              Exists(const string name)
     { return FileIsExist(Path(name)); }

   //+------------------------------------------------------------------+
   //| What sessions exist on disk.                                     |
   //|                                                                  |
   //| So the user PICKS from what is there rather than typing a name   |
   //| and finding out it was not the one they meant. Newest first is   |
   //| not offered, because FileFindNext gives no order and sorting by  |
   //| a time this API does not expose would be inventing one.          |
   //+------------------------------------------------------------------+
   int               List(string &out[], const int max_names = 64)
     {
      ArrayResize(out, 0);
      string found = "";
      long h = FileFindFirst(SSR_SESSION_DIR + "\\*" + SSR_SESSION_EXT, found);
      if(h == INVALID_HANDLE)
         return 0;

      int n = 0;
      do
        {
         if(n >= max_names)
            break;
         //--- the name the user gave, without our extension
         string name = found;
         int    dot  = StringFind(name, SSR_SESSION_EXT);
         if(dot > 0)
            name = StringSubstr(name, 0, dot);
         if(name == "")
            continue;
         ArrayResize(out, n + 1);
         out[n++] = name;
        }
      while(FileFindNext(h, found));
      FileFindClose(h);
      return n;
     }

   //================================================================
   //  SAVE
   //================================================================
   bool              Save(const string name, SSRSessionSettings &settings)
     {
      m_last_error = "";
      m_warnings   = "";
      if(m_group == NULL || m_group.Count() == 0)
        { Fail("no streams to save"); return false; }

      FolderCreate(SSR_SESSION_DIR);
      CSSRSessionFile f;
      if(!f.Create(Path(name)))
        { Fail(f.LastError()); return false; }
      m_last_path = f.Path();

      f.Section("session");
      f.Set("name",      name);
      f.Set("product",   SSR_VERSION);
      f.Set("written",   TimeToString(TimeLocal(), TIME_DATE | TIME_SECONDS));
      f.SetInt("streams", m_group.Count());
      f.SetLong("master_now",   m_group.Now());
      f.SetLong("master_start", m_group.StartMsc());
      f.SetLong("master_end",   m_group.EndMsc());
      f.SetLong("speed",        m_group.SpeedX100());

      f.Section("settings");
      //--- the seed is written even when it was not used, so a session
      //--- that was random can be recognised as such months later
      f.SetLong("seed",          (long)settings.seed);
      f.SetInt("blind",          settings.blind);
      f.SetInt("pause_flags",    settings.pause_flags);
      f.SetInt("session_mode",   settings.session_mode);
      f.SetInt("slot",           settings.slot);
      f.SetInt("ticks_per_bar",  settings.ticks_per_bar);
      f.SetDouble("spread_points", settings.spread_points, 4);
      f.SetInt("chart_tf",       (int)settings.chart_tf);

      //--- one [stream] + [bookmarks] pair per stream, in order
      for(int i = 0; i < m_group.Count(); i++)
         m_group.At(i).SaveInto(f);

      if(m_acct != NULL)
         m_acct.SaveInto(f);
      if(m_stats != NULL)
         m_stats.SaveInto(f);

      f.Close();
      return true;
     }

   //+------------------------------------------------------------------+
   //| Read the header WITHOUT restoring anything.                      |
   //|                                                                  |
   //| So the host can show the user what a file holds - which symbols, |
   //| which period, how far in - and let them decide, rather than       |
   //| finding out by opening it.                                        |
   //+------------------------------------------------------------------+
   bool              Peek(const string name, string &summary)
     {
      m_last_error = "";
      summary      = "";
      CSSRSessionFile f;
      if(!f.Load(Path(name)))
        { Fail(f.LastError()); return false; }
      if(!f.Select("session"))
        { Fail("not a session file: no [session] section"); return false; }

      int  streams = f.GetInt("streams", 0);
      long now     = f.GetLong("master_now", SSR_INVALID_TIME);
      long start   = f.GetLong("master_start", SSR_INVALID_TIME);
      long end     = f.GetLong("master_end", SSR_INVALID_TIME);
      string when  = f.Get("written", "?");

      string syms = "";
      for(int i = 0; i < streams; i++)
         if(f.Select("stream", i))
            syms += (syms == "" ? "" : ", ") + f.Get("origin", "?");

      double pct = 0.0;
      if(end > start && now >= start)
         pct = (double)(now - start) / (double)(end - start) * 100.0;

      summary = StringFormat("%s  |  %s  |  at %s (%.0f%% of %s..%s)  |  saved %s",
                             name, syms, SSRFormatMsc(now), pct,
                             SSRFormatMsc(start), SSRFormatMsc(end), when);
      return true;
     }

   bool              ReadSettings(const string name, SSRSessionSettings &out)
     {
      out.Init();
      CSSRSessionFile f;
      if(!f.Load(Path(name)))
        { Fail(f.LastError()); return false; }
      if(!f.Select("settings"))
         return false;
      out.seed          = (ulong)f.GetLong("seed", 0);
      out.blind         = f.GetInt("blind", 0);
      out.pause_flags   = f.GetInt("pause_flags", 0);
      out.session_mode  = f.GetInt("session_mode", 0);
      out.slot          = f.GetInt("slot", 1);
      out.ticks_per_bar = f.GetInt("ticks_per_bar", 8);
      out.spread_points = f.GetDouble("spread_points", 0.0);
      out.chart_tf      = (ENUM_TIMEFRAMES)f.GetInt("chart_tf", PERIOD_M5);
      return true;
     }

   //--- which symbols a file wants, so the host can build the right
   //--- streams BEFORE asking for them to be restored into
   int               ReadSymbols(const string name, string &out[])
     {
      ArrayResize(out, 0);
      CSSRSessionFile f;
      if(!f.Load(Path(name)))
        { Fail(f.LastError()); return 0; }
      int streams = f.SectionCount("stream");
      for(int i = 0; i < streams; i++)
        {
         if(!f.Select("stream", i))
            continue;
         int k = ArraySize(out);
         ArrayResize(out, k + 1);
         out[k] = f.Get("origin", "");
        }
      return ArraySize(out);
     }

   //--- and the window each stream was loaded over
   bool              ReadWindow(const string name, const int nth,
                                long &start_msc, long &end_msc)
     {
      start_msc = SSR_INVALID_TIME;
      end_msc   = SSR_INVALID_TIME;
      CSSRSessionFile f;
      if(!f.Load(Path(name)) || !f.Select("stream", nth))
         return false;
      start_msc = f.GetLong("start", SSR_INVALID_TIME);
      end_msc   = f.GetLong("end", SSR_INVALID_TIME);
      return (start_msc > 0 && end_msc > start_msc);
     }

   //================================================================
   //  RESTORE
   //
   //  The caller must have already built and Load()ed every stream
   //  over the same window - use ReadSymbols and ReadWindow for that.
   //  This puts the POSITION, the account and the curve back.
   //================================================================
   bool              Restore(const string name)
     {
      m_last_error       = "";
      m_warnings         = "";
      m_streams_restored = 0;
      if(m_group == NULL || m_group.Count() == 0)
        { Fail("no streams to restore into"); return false; }

      CSSRSessionFile f;
      if(!f.Load(Path(name)))
        { Fail(f.LastError()); return false; }
      if(!f.Select("session"))
        { Fail("not a session file: no [session] section"); return false; }

      int saved_streams = f.GetInt("streams", 0);
      if(saved_streams != m_group.Count())
         Warn(StringFormat("the session had %d stream(s); %d were rebuilt - "
                           "the rest could not be opened",
                           saved_streams, m_group.Count()));

      //--- THE STREAMS FIRST, AND THE ACCOUNT AFTER. Restoring the
      //--- account first looks tidier and is wrong: winding a stream
      //--- forward re-emits the ticks of the stretch being crossed,
      //--- and an account already holding the session's positions
      //--- would run its stops against them at prices from BEFORE
      //--- those positions were opened - closing trades that, in the
      //--- session being restored, were still running.
      //---
      //--- With the account empty there is nothing for those ticks to
      //--- act on, and the log is put back afterwards exactly as saved.
      for(int i = 0; i < m_group.Count(); i++)
        {
         string w = "";
         if(!m_group.At(i).RestoreFrom(f, i, w))
           {
            Fail(StringFormat("stream %d (%s): %s", i,
                              m_group.At(i).Symbol(),
                              m_group.At(i).LastErrorText()));
            return false;
           }
         Warn(w);
         m_streams_restored++;
        }

      //--- the master follows the streams, never the file: they have
      //--- just told us where they could actually land
      long now = m_group.At(0).Now();
      m_group.SeekAllTo(now);

      //--- back to [session] first. The stream restores moved the
      //--- cursor, and "speed" exists in a [stream] section too - so
      //--- reading it from wherever the cursor happened to land would
      //--- take the last stream's speed and call it the group's.
      f.Select("session");
      m_group.SetSpeedX100(f.GetLong("speed", SSR_SPEED_1));

      if(m_group.MaxSkewMsc() != 0)
         Warn(StringFormat("the streams came back %I64dms apart - one of "
                           "them could not reach the saved instant",
                           m_group.MaxSkewMsc()));

      //--- now the account, over the top of whatever the wind-forward
      //--- left behind
      if(m_acct != NULL)
        {
         string w = "";
         if(!m_acct.RestoreFrom(f, w))
           { Fail("account: " + m_acct.LastError()); return false; }
         Warn(w);
        }
      if(m_stats != NULL)
         m_stats.RestoreFrom(f);

      //--- and every observer is told its picture was replaced, or the
      //--- auto-pause watcher would announce each restored position as
      //--- an entry that just happened
      for(int i = 0; i < m_group.Count(); i++)
         m_group.At(i).NotifyRestored();
      return true;
     }

   //+------------------------------------------------------------------+
   //| The sentence the user sees after a resume.                       |
   //+------------------------------------------------------------------+
   string            ResumeReport(void)
     {
      if(m_warnings == "")
         return StringFormat("resumed %d stream(s) at %s",
                             m_streams_restored,
                             (m_group != NULL ? SSRFormatMsc(m_group.Now()) : "?"));
      return StringFormat("resumed %d stream(s) at %s - BUT:\n%s",
                          m_streams_restored,
                          (m_group != NULL ? SSRFormatMsc(m_group.Now()) : "?"),
                          m_warnings);
     }

   //--- deleting is the user's call, and it is theirs to undo by not
   //--- doing it: there is no recycle bin here, so it is never
   //--- something this class decides on its own
   bool              Delete(const string name)
     {
      m_last_error = "";
      if(!FileIsExist(Path(name)))
        { Fail("no such session: " + name); return false; }
      if(!FileDelete(Path(name)))
        { Fail("could not delete " + Path(name)); return false; }
      return true;
     }
  };

#endif // SSR_SESSION_MANAGER_MQH
//+------------------------------------------------------------------+

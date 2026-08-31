//+------------------------------------------------------------------+
//|                                             SSR_ChartManager.mqh |
//|                  SS Replay - Native Chart Integration (L3/Chart) |
//|                                                                  |
//|  WHAT THIS DOES NOT DO                                           |
//|  It does not make timeframe switching work. That already works,  |
//|  and it works for an architectural reason rather than a coded    |
//|  one: the engine lives outside the chart, the data lives in a    |
//|  custom symbol, and MetaTrader derives every higher timeframe    |
//|  from the M1 base itself. Nothing here is load-bearing for the   |
//|  "M5 -> M15 -> H1 -> M5 keeps 10:37" requirement.                |
//|                                                                  |
//|  WHAT IT DOES                                                    |
//|  Keeps the EXPERIENCE intact around that: following the right    |
//|  edge without fighting a user who scrolled back, noticing when   |
//|  a chart changes timeframe so the panel can catch up, throttling |
//|  repaints, and never touching a chart the user did not open for  |
//|  replay.                                                         |
//|                                                                  |
//|  It holds no pointer to the engine and asks it nothing.          |
//+------------------------------------------------------------------+
#ifndef SSR_CHART_MANAGER_MQH
#define SSR_CHART_MANAGER_MQH

#include "../Common/SSR_Types.mqh"
#include "../Common/SSR_Time.mqh"
#include "../Common/SSR_Platform.mqh"
#include "../Common/SSR_SymbolNaming.mqh"
#include "SSR_ChartTypes.mqh"
#include "SSR_LeakGuard.mqh"

//+------------------------------------------------------------------+
class CSSRChartManager
  {
private:
   string             m_symbol;          // the REPLAY symbol, never the origin
   SSRChartInfo       m_charts[];
   int                m_count;
   CSSRChartObserver *m_observer;        // not owned
   CSSRLeakGuard      m_leak;

   long               m_untracked;       // charts beyond SSR_MAX_CHARTS
   ulong              m_last_redraw_us;
   long               m_snaps;            // views dragged back to the newest bar
   long               m_last_bar_time;    // newest M1 bar we have already snapped to
   long               m_redraws;
   long               m_redraws_skipped;
   long               m_syncs;

   //--- charts we opened ourselves, and may therefore close again
   long               m_owned[];
   int                m_owned_count;
   long               m_host_left_open;   // the chart we stood on and spared

   int                Find(const long id)
     {
      for(int i = 0; i < m_count; i++)
         if(m_charts[i].id == id)
            return i;
      return -1;
     }

   bool               IsOwned(const long id)
     {
      for(int i = 0; i < m_owned_count; i++)
         if(m_owned[i] == id)
            return true;
      return false;
     }

   void               NoteOwned(const long id)
     {
      if(IsOwned(id))
         return;
      if(ArrayResize(m_owned, m_owned_count + 1) < m_owned_count + 1)
         return;
      m_owned[m_owned_count++] = id;
     }

   int                Add(const long id)
     {
      if(m_count >= SSR_MAX_CHARTS)
         return -1;
      if(ArrayResize(m_charts, m_count + 1) < m_count + 1)
         return -1;
      int i = m_count++;
      m_charts[i].Init();
      m_charts[i].id     = id;
      m_charts[i].symbol = ChartSymbol(id);
      m_charts[i].period = ChartPeriod(id);
      m_charts[i].alive  = true;
      m_charts[i].follow = true;
      m_charts[i].detach_votes = 0;
      m_charts[i].last_offset = ViewOffset(id);
      return i;
     }

   void               Remove(const int i)
     {
      if(i < 0 || i >= m_count)
         return;
      for(int k = i; k < m_count - 1; k++)
         m_charts[k] = m_charts[k + 1];
      m_count--;
      ArrayResize(m_charts, m_count);
     }

   //+------------------------------------------------------------------+
   //| How many bars the view sits behind the newest bar.               |
   //|                                                                  |
   //| MetaTrader indexes bars from the right, so at the right edge the |
   //| leftmost visible bar is (visible_bars - 1). Anything larger is   |
   //| distance from the end - and that stays true whether the gap came |
   //| from the user dragging or from a new bar arriving while the view |
   //| stayed put. One number covers both, which is why it is the one   |
   //| the detach test uses.                                            |
   //+------------------------------------------------------------------+
   long               ViewOffset(const long id)
     {
      long first   = ChartGetInteger(id, CHART_FIRST_VISIBLE_BAR);
      long visible = ChartGetInteger(id, CHART_VISIBLE_BARS);
      if(visible <= 0)
         return 0;
      long off = first - (visible - 1);
      return (off < 0 ? 0 : off);
     }

public:
                     CSSRChartManager(void)
     : m_symbol(""), m_count(0), m_observer(NULL),
       m_untracked(0), m_last_redraw_us(0), m_snaps(0), m_last_bar_time(0),
       m_redraws(0), m_redraws_skipped(0), m_syncs(0),
       m_owned_count(0), m_host_left_open(0)
     {
      ArrayResize(m_charts, 0);
      ArrayResize(m_owned, 0);
     }

                    ~CSSRChartManager(void) {}

   void               SetObserver(CSSRChartObserver *o) { m_observer = o; }

   void               Configure(const string replay_symbol, const string origin_symbol)
     {
      m_symbol = replay_symbol;
      m_leak.Configure(origin_symbol, replay_symbol);
      m_last_bar_time = 0;
      m_count = 0;
      ArrayResize(m_charts, 0);
     }

   string             Symbol(void) { return m_symbol; }
   int                Count(void)  { return m_count; }
   long               IdAt(const int i)
     { return (i >= 0 && i < m_count ? m_charts[i].id : 0); }

   //+------------------------------------------------------------------+
   //| Put a visible mark at a moment, on every replay chart.            |
   //|                                                                   |
   //| A bookmark that only exists in a counter is a bookmark the user    |
   //| has to take on trust. The whole point of marking a moment is to    |
   //| find it again by eye.                                              |
   //+------------------------------------------------------------------+
   //--- the colour comes from the caller: this layer has no theme, and
   //--- reaching up into Ui for one would invert the dependency
   int                MarkTime(const datetime when, const string label,
                               const color col)
     {
      int drawn = 0;
      string base = "SSR_MARK_" + IntegerToString((int)when);
      for(int i = 0; i < m_count; i++)
        {
         long id = m_charts[i].id;
         if(id == 0)
            continue;
         string n = base + "_" + IntegerToString(i);
         if(ObjectFind(id, n) < 0 && !ObjectCreate(id, n, OBJ_VLINE, 0, when, 0))
            continue;
         ObjectSetInteger(id, n, OBJPROP_COLOR,      col);
         ObjectSetInteger(id, n, OBJPROP_STYLE,      STYLE_DASH);
         ObjectSetInteger(id, n, OBJPROP_WIDTH,      1);
         ObjectSetInteger(id, n, OBJPROP_BACK,       true);
         ObjectSetInteger(id, n, OBJPROP_SELECTABLE, false);
         ObjectSetInteger(id, n, OBJPROP_HIDDEN,     true);
         ObjectSetString (id, n, OBJPROP_TOOLTIP,    label);
         ChartRedraw(id);
         drawn++;
        }
      return drawn;
     }
   CSSRLeakGuard     *Leak(void)   { return GetPointer(m_leak); }

   bool               InfoAt(const int i, SSRChartInfo &out)
     {
      if(i < 0 || i >= m_count)
         return false;
      out = m_charts[i];
      return true;
     }

   //+------------------------------------------------------------------+
   //| Open a replay chart and remember that we own it.                 |
   //+------------------------------------------------------------------+
   long               OpenChart(const ENUM_TIMEFRAMES tf)
     {
      if(m_symbol == "")
         return 0;
      long id = ChartOpen(m_symbol, tf);
      if(id == 0)
         return 0;
      NoteOwned(id);
      ApplyPolicy(id);
      Sync();
      return id;
     }

   //+------------------------------------------------------------------+
   //| Open several charts of the same replay symbol at once.           |
   //|                                                                  |
   //| Multi-timeframe costs nothing here and that is the point of the  |
   //| architecture: the engine writes M1 into a custom symbol and      |
   //| MetaTrader derives every higher timeframe itself. An H1 chart of |
   //| a replay is not a feature this layer implements - it is a chart. |
   //|                                                                  |
   //| Returns how many opened. A partial result is reported, not       |
   //| rolled back: three charts out of four is still a usable desk,    |
   //| and closing them again would be the tool overruling the user.    |
   //+------------------------------------------------------------------+
   int                OpenLayout(const ENUM_TIMEFRAMES &tfs[], const int count)
     {
      int opened = 0;
      for(int i = 0; i < count; i++)
        {
         if(m_count + opened >= SSR_MAX_CHARTS)
            break;                        // the ceiling, honoured quietly
         if(!SSRIsSupportedTimeframe(tfs[i]))
            continue;                     // W1/MN1 are not ours to reason about
         if(OpenChart(tfs[i]) != 0)
            opened++;
        }
      return opened;
     }

   //--- the ids of the charts we own, for a caller that needs to touch
   //--- them directly - applying Blind Mode, for instance
   int                OwnedIds(long &out[])
     {
      ArrayResize(out, m_owned_count);
      for(int i = 0; i < m_owned_count; i++)
         out[i] = m_owned[i];
      return m_owned_count;
     }

   //+------------------------------------------------------------------+
   //| Close only charts WE opened.                                     |
   //|                                                                  |
   //| A chart the user opened is theirs. Closing it on teardown would  |
   //| be the tool deciding it knows better, and it is the sort of      |
   //| thing that is remembered.                                        |
   //+------------------------------------------------------------------+
   //+------------------------------------------------------------------+
   //| NEVER CLOSE THE CHART WE ARE STANDING ON.                        |
   //|                                                                  |
   //| A script or EA dies the instant its own chart closes - silently, |
   //| mid-statement. If teardown closes the host chart, everything     |
   //| after that line never runs: the custom symbol is not deleted,    |
   //| the leftover stays in Market Watch, and the NEXT session fails   |
   //| to start with error 5304. One line of tidying costs the user     |
   //| their next run.                                                  |
   //|                                                                  |
   //| A test run showed exactly this shape: Phase 4 stopped without    |
   //| printing its summary, at the section that closes charts, and     |
   //| every later test ran on a different chart than it started on.    |
   //|                                                                  |
   //| So the host chart is left open and REPORTED, not closed. The     |
   //| caller can close it last, after it has nothing left to do.       |
   //+------------------------------------------------------------------+
   int                CloseOwned(void)
     {
      long here = ChartID();
      int  closed = 0;
      m_host_left_open = 0;
      for(int i = 0; i < m_owned_count; i++)
        {
         if(ChartSymbol(m_owned[i]) != m_symbol)
            continue;
         if(m_owned[i] == here)
           {
            m_host_left_open = here;      // ours, but we are standing on it
            continue;
           }
         ChartClose(m_owned[i]);
         closed++;
        }
      ArrayResize(m_owned, 0);
      m_owned_count = 0;
      //--- an unclosed host is still ours; keep owning it so a later
      //--- caller that CAN close it still knows to
      if(m_host_left_open != 0 && ArrayResize(m_owned, 1) == 1)
        {
         m_owned[0]    = m_host_left_open;
         m_owned_count = 1;
        }
      Sync();
      return closed;
     }

   //--- the chart CloseOwned refused to close because we were on it
   long               HostLeftOpen(void) { return m_host_left_open; }

   //--- chart settings we impose; deliberately few
   void               ApplyPolicy(const long id)
     {
      ChartSetInteger(id, CHART_AUTOSCROLL, true);
      ChartSetInteger(id, CHART_SHIFT, true);

      //--- The replay charts are for LOOKING at. MetaTrader only
      //--- delivers key events to the chart a program runs on, so a key
      //--- pressed here reaches nothing - and with quick navigation on,
      //--- SPACE opens a text box in the corner instead, which reads as
      //--- the whole product freezing. Nothing here can act on a key,
      //--- so nothing here should appear to.
      ChartSetInteger(id, CHART_QUICK_NAVIGATION, false);
     }

   //+------------------------------------------------------------------+
   //| Reconcile the registry with reality.                             |
   //|                                                                  |
   //| Called from the owner's timer. Detects charts opened and closed  |
   //| by the user, timeframe changes, and manual scrolling.            |
   //+------------------------------------------------------------------+
   void               Sync(void)
     {
      m_syncs++;
      if(m_symbol == "")
         return;

      for(int i = 0; i < m_count; i++)
         m_charts[i].alive = false;

      long id = ChartFirst();
      while(id >= 0)
        {
         if(ChartSymbol(id) == m_symbol)
           {
            int i = Find(id);
            if(i < 0)
              {
               i = Add(id);
               if(i >= 0)
                 {
                  //+------------------------------------------------------------------+
                  //| A CHART WE DID NOT OPEN STILL NEEDS THE POLICY.                  |
                  //|                                                                  |
                  //| ApplyPolicy - which turns AUTOSCROLL on - was only reached from  |
                  //| OpenChart. In one-window mode the host does not open a chart at  |
                  //| all; it hands its OWN chart to the replay symbol, so the policy  |
                  //| never ran. Bars were written, the chart held them, and the view  |
                  //| never followed to the right-hand edge: candles appearing off     |
                  //| screen, and a user reporting "the candles do not move" about an  |
                  //| engine that a smoke test had just proved was writing them.       |
                  //|                                                                  |
                  //| Applied on DISCOVERY only. Re-applying every pass would undo     |
                  //| DetectScroll, which deliberately releases autoscroll the moment  |
                  //| the user scrolls back to look at something.                      |
                  //+------------------------------------------------------------------+
                  ApplyPolicy(id);
                  if(m_observer != NULL)
                     m_observer.OnChartOpened(id);
                 }
               else
                  //--- over the registry ceiling. Counted rather than
                  //--- ignored: an untracked replay chart still shows the
                  //--- user data, it just gets no follow policy.
                  m_untracked++;
              }
            else
              {
               m_charts[i].alive = true;

               //--- timeframe change. MetaTrader has already rebuilt the
               //--- series from the same M1 base, so replay state is
               //--- untouched; this only tells the owner to catch up.
               ENUM_TIMEFRAMES now = ChartPeriod(id);
               if(now != m_charts[i].period)
                 {
                  ENUM_TIMEFRAMES was = m_charts[i].period;
                  m_charts[i].period = now;
                  m_charts[i].tf_changes++;

                  //--- a timeframe change re-anchors the view, so an
                  //--- earlier manual detach no longer describes it
                  m_charts[i].user_detached = false;
                  m_charts[i].detach_votes  = 0;
                  m_charts[i].last_offset   = ViewOffset(id);
                  if(m_charts[i].follow)
                     ApplyPolicy(id);

                  if(m_observer != NULL)
                     m_observer.OnTimeframeChanged(id, was, now);
                 }
               else
                  DetectScroll(i);
              }
            if(i >= 0)
               m_charts[i].alive = true;
           }
         id = ChartNext(id);
        }

      //--- charts that vanished
      for(int i = m_count - 1; i >= 0; i--)
        {
         if(!m_charts[i].alive)
           {
            long gone = m_charts[i].id;
            Remove(i);
            if(m_observer != NULL)
               m_observer.OnChartClosed(gone);
           }
        }
     }

   //+------------------------------------------------------------------+
   //| Notice a user who scrolled back, and stop fighting them.         |
   //|                                                                  |
   //| MetaTrader's autoscroll drags the view back to the newest bar on |
   //| every tick. During replay that is dozens of times a second, so a |
   //| user trying to look at earlier price gets yanked forward and the |
   //| tool feels broken. Releasing autoscroll the moment they scroll,  |
   //| and offering an explicit way back, is the whole feature.         |
   //+------------------------------------------------------------------+
   void               DetectScroll(const int i)
     {
      if(i < 0 || i >= m_count)
         return;
      long off = ViewOffset(m_charts[i].id);

      //+------------------------------------------------------------------+
      //| ONE VOTE IS ENOUGH NOW, AND HAS TO BE.                           |
      //|                                                                  |
      //| Redraw drags every following view back to the newest bar on      |
      //| every pass that produced a bar. A user who scrolls back has      |
      //| their scroll undone about five times a second, so a rule that    |
      //| waits for two consecutive observations would never collect the   |
      //| second one - the offset is reset to zero in between.             |
      //|                                                                  |
      //| Waiting was there to avoid mistaking new bars for a drag. It no  |
      //| longer can: the snap zeroes the offset each pass, so anything    |
      //| past the threshold within one pass is a hand on the chart.       |
      //+------------------------------------------------------------------+
      int votes_needed = (m_last_bar_time > 0 ? 1 : SSR_SCROLL_DETACH_VOTES);

      if(m_charts[i].follow && !m_charts[i].user_detached &&
         off > SSR_SCROLL_DETACH_BARS)
        {
         m_charts[i].detach_votes++;
         if(m_charts[i].detach_votes >= votes_needed)
           {
            m_charts[i].user_detached = true;
            m_charts[i].follow        = false;
            m_charts[i].detach_votes  = 0;
            ChartSetInteger(m_charts[i].id, CHART_AUTOSCROLL, false);
            if(m_observer != NULL)
               m_observer.OnUserScrolled(m_charts[i].id);
           }
        }
      else
         m_charts[i].detach_votes = 0;

      m_charts[i].last_offset = off;
     }

   //--- re-engage following on one chart, or on all of them
   bool               Follow(const long id)
     {
      int i = Find(id);
      if(i < 0)
         return false;
      m_charts[i].follow        = true;
      m_charts[i].user_detached = false;
      m_charts[i].detach_votes  = 0;
      ChartSetInteger(id, CHART_AUTOSCROLL, true);
      ChartNavigate(id, CHART_END, 0);
      m_charts[i].last_offset = 0;
      if(m_observer != NULL)
         m_observer.OnUserFollowed(id);
      return true;
     }

   int                FollowAll(void)
     {
      int n = 0;
      for(int i = 0; i < m_count; i++)
         if(Follow(m_charts[i].id))
            n++;
      return n;
     }

   int                DetachedCount(void)
     {
      int n = 0;
      for(int i = 0; i < m_count; i++)
         if(m_charts[i].user_detached)
            n++;
      return n;
     }

   //+------------------------------------------------------------------+
   //| Throttled repaint, and the thing that actually moves the view.   |
   //|                                                                  |
   //| This used to say "price already repaints natively on each        |
   //| injected tick, so this exists only for overlay objects". That    |
   //| was an assumption, and it was wrong in the case that mattered.   |
   //| CHART_AUTOSCROLL is MetaTrader's own promise to keep the newest  |
   //| bar in view, and on a custom symbol being written from an EA it  |
   //| does not reliably keep it: bars appear in the series, the chart  |
   //| holds them, and the visible window stays exactly where it was.   |
   //| The user sees a still picture of a replay that is running - the  |
   //| single most-reported defect in this project, over three          |
   //| releases, each time diagnosed as something else.                 |
   //|                                                                  |
   //| So the view is moved explicitly. ChartNavigate(CHART_END) is not |
   //| a promise, it is an instruction, and it does not depend on a     |
   //| tick arriving to be honoured.                                    |
   //|                                                                  |
   //| Only when the newest M1 bar has actually changed: snapping a     |
   //| view that has nothing new to show would fight a user who is      |
   //| simply looking around a paused replay.                           |
   //+------------------------------------------------------------------+
   bool               Redraw(const bool force = false)
     {
      ulong now = SSRMicros();
      if(!force && m_last_redraw_us != 0 &&
         (double)(now - m_last_redraw_us) / 1000.0 < SSR_REDRAW_MIN_INTERVAL_MS)
        {
         m_redraws_skipped++;
         return false;
        }
      m_last_redraw_us = now;

      //--- has anything new arrived since the last time we looked?
      long newest = 0;
      if(m_symbol != "")
         newest = (long)SeriesInfoInteger(m_symbol, PERIOD_M1, SERIES_LASTBAR_DATE);
      bool advanced = (newest > 0 && newest != m_last_bar_time);
      if(advanced)
         m_last_bar_time = newest;

      for(int i = 0; i < m_count; i++)
        {
         //--- a chart the user scrolled back is theirs until they ask
         //--- for it back. DetectScroll runs in Sync, which the owner
         //--- calls immediately before this, so follow is current.
         if(advanced && m_charts[i].follow && !m_charts[i].user_detached)
           {
            ChartNavigate(m_charts[i].id, CHART_END, 0);
            m_charts[i].last_offset = 0;
            m_snaps++;
           }
         ChartRedraw(m_charts[i].id);
        }
      m_redraws++;
      return true;
     }

   //--- how many times a view has been dragged back to the newest bar.
   //--- Zero while a replay is running means the candles are not moving.
   long               Snaps(void)          { return m_snaps; }
   long               LastBarTime(void)    { return m_last_bar_time; }

   //--- set every managed chart to one timeframe (Phase 11 sync uses this)
   int                SetPeriodAll(const ENUM_TIMEFRAMES tf)
     {
      int n = 0;
      for(int i = 0; i < m_count; i++)
         if(ChartSetSymbolPeriod(m_charts[i].id, m_symbol, tf))
            n++;
      Sync();
      return n;
     }

   //--- leak scanning is cheap; the owner calls it on its slow timer
   void               ScanLeaks(void)          { m_leak.Scan(); }
   bool               LeaksClean(void)         { return m_leak.IsClean(); }
   string             LeakAdvice(void)         { return m_leak.Advice(); }

   //--- diagnostics --------------------------------------------------
   long               Redraws(void)        { return m_redraws; }
   long               RedrawsSkipped(void) { return m_redraws_skipped; }
   long               Syncs(void)          { return m_syncs; }
   long               Untracked(void)      { return m_untracked; }

   long               TimeframeChanges(void)
     {
      long n = 0;
      for(int i = 0; i < m_count; i++)
         n += m_charts[i].tf_changes;
      return n;
     }

   string             ToString(void)
     {
      return StringFormat("charts[%s n=%d detached=%d tf_changes=%d redraw=%d/%d snaps=%d]",
                          m_symbol, m_count, DetachedCount(),
                          (int)TimeframeChanges(), (int)m_redraws,
                          (int)(m_redraws + m_redraws_skipped), (int)m_snaps);
     }
  };

#endif // SSR_CHART_MANAGER_MQH
//+------------------------------------------------------------------+

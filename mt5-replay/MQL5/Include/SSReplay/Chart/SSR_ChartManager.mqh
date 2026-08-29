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
   long               m_redraws;
   long               m_redraws_skipped;
   long               m_syncs;

   //--- charts we opened ourselves, and may therefore close again
   long               m_owned[];
   int                m_owned_count;

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
       m_untracked(0), m_last_redraw_us(0), m_redraws(0), m_redraws_skipped(0), m_syncs(0),
       m_owned_count(0)
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
      m_count = 0;
      ArrayResize(m_charts, 0);
     }

   string             Symbol(void) { return m_symbol; }
   int                Count(void)  { return m_count; }
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
   int                CloseOwned(void)
     {
      int closed = 0;
      for(int i = 0; i < m_owned_count; i++)
        {
         if(ChartSymbol(m_owned[i]) == m_symbol)
           {
            ChartClose(m_owned[i]);
            closed++;
           }
        }
      ArrayResize(m_owned, 0);
      m_owned_count = 0;
      Sync();
      return closed;
     }

   //--- chart settings we impose; deliberately few
   void               ApplyPolicy(const long id)
     {
      ChartSetInteger(id, CHART_AUTOSCROLL, true);
      ChartSetInteger(id, CHART_SHIFT, true);
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

      if(m_charts[i].follow && !m_charts[i].user_detached &&
         off > SSR_SCROLL_DETACH_BARS)
        {
         m_charts[i].detach_votes++;
         if(m_charts[i].detach_votes >= SSR_SCROLL_DETACH_VOTES)
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
      m_charts[i].last_offset = ViewOffset(id);
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
   //| Throttled repaint.                                               |
   //|                                                                  |
   //| Price already repaints natively on each injected tick, so this   |
   //| exists only for overlay objects. Returns true when it actually   |
   //| painted, so a caller can see how often it is being denied.       |
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
      for(int i = 0; i < m_count; i++)
         ChartRedraw(m_charts[i].id);
      m_redraws++;
      return true;
     }

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
      return StringFormat("charts[%s n=%d detached=%d tf_changes=%d redraw=%d/%d]",
                          m_symbol, m_count, DetachedCount(),
                          (int)TimeframeChanges(), (int)m_redraws,
                          (int)(m_redraws + m_redraws_skipped));
     }
  };

#endif // SSR_CHART_MANAGER_MQH
//+------------------------------------------------------------------+

//+------------------------------------------------------------------+
//|                                                    SSR_Panel.mqh |
//|                             SS Replay - The Replay Panel (UI)    |
//|                                                                  |
//|  A view over SSRUiState and a sender of commands. That is all.   |
//|  It never touches the controller, never reads the clock, never   |
//|  decides what a state means - it renders what the port hands it  |
//|  and forwards what the user pressed.                             |
//|                                                                  |
//|  THE SHAPE, AND WHY                                              |
//|  A classic Windows dialog: caption, a clock and transport that   |
//|  are ALWAYS visible, a speed trackbar, a tab strip, a column of  |
//|  always-reachable buttons beside the sheet, and a status strip.  |
//|                                                                  |
//|  What is always visible is not a style choice. The clock, the    |
//|  transport and the speed are the three things a person touches   |
//|  every few seconds; putting any of them behind a tab means the   |
//|  tool is only usable on one page. Everything that is consulted   |
//|  rather than operated - positions, statistics, the session -     |
//|  lives on a tab.                                                 |
//|                                                                  |
//|  WHAT WAS TAKEN OUT                                              |
//|  Templates, Presets and a chart-layout button were drawn in an   |
//|  earlier design with nothing behind them. A control that does    |
//|  nothing is worse than a missing one: it teaches the user that   |
//|  pressing things here may or may not work. Every control on this |
//|  panel reaches something the engine actually implements.         |
//|                                                                  |
//|  It runs on the host's timer, so it must stay cheap: rendering   |
//|  only touches objects whose text or position actually changed,   |
//|  because rewriting forty labels sixty times a second is how a    |
//|  panel makes a terminal feel slow.                               |
//+------------------------------------------------------------------+
#ifndef SSR_PANEL_MQH
#define SSR_PANEL_MQH

#include "../Common/SSR_Types.mqh"
#include "../Common/SSR_Time.mqh"
#include "../Common/SSR_FlightRecorder.mqh"
#include "SSR_Theme.mqh"
#include "SSR_Widgets.mqh"
#include "SSR_ReplayPort.mqh"
#include "SSR_Keys.mqh"

#define SSR_SLOTS 64

//+------------------------------------------------------------------+
class CSSRPanel
  {
private:
   long              m_chart;
   CSSRWidgets       m_w;
   CSSRReplayPort   *m_port;        // not owned
   //--- the black box, if the host started one. Not owned, and never
   //--- required: every call site checks for NULL, because a panel that
   //--- only works while a recorder exists would be a panel that only
   //--- works while someone is watching.
   CSSRFlightRecorder *m_flight;
   //--- the last button that fired, and when. A held mouse re-latches
   //--- OBJPROP_STATE on every pass, so without this a press becomes a
   //--- burst - measured at four play/pause toggles in 350ms and three
   //--- step-forwards in 100ms, none of them asked for.
   string            m_last_btn;
   uint              m_last_btn_ms;
   string            m_prefix;

   int               m_x, m_y;

   //--- What the chart looked like before the panel touched it.
   long              m_saved_mouse_move;
   long              m_saved_mouse_scroll;
   long              m_saved_quick_nav;
   long              m_saved_key_control;
   bool              m_saved;

   bool              m_collapsed;
   bool              m_closed;      // hidden entirely; one button brings it back
   bool              m_compact;     // the chart is too short for the full panel
   bool              m_dragging;
   int               m_drag_dx, m_drag_dy;

   //--- the speed trackbar, which is dragged rather than clicked
   bool              m_track_drag;
   int               m_track_x, m_track_y, m_track_w;
   uint              m_last_drag_paint;
   int               m_corner;      // 0 TL, 1 TR, 2 BR, 3 BL

   int               m_tab;
   string            m_tag_sent;    // the last text handed to the port

   SSRUiState        m_state;

   //+------------------------------------------------------------------+
   //| Write only when something actually changed - and POSITION is     |
   //| something.                                                       |
   //|                                                                  |
   //| This cache was keyed on the text alone. Dragging the panel moves |
   //| x and y while every label's text stays the same, so every one of |
   //| them took the early return and stayed where it was. The buttons  |
   //| have no cache, so they moved. The panel tore in half: labels     |
   //| stranded over the candles, controls somewhere else.              |
   //|                                                                  |
   //| Skipping a write is only safe when NOTHING about the write would |
   //| differ - the text, and where it goes.                            |
   //+------------------------------------------------------------------+
   string            m_cache[SSR_SLOTS];
   int               m_cache_x[SSR_SLOTS];
   int               m_cache_y[SSR_SLOTS];
   int               m_renders;
   int               m_writes;

   void              Text(const int slot, const string id, const int x, const int y,
                          const string text, const color col,
                          const int size = SSR_FS_BODY, const string font = SSR_FONT)
     {
      if(slot >= 0 && slot < SSR_SLOTS && m_cache[slot] == text &&
         m_cache_x[slot] == x && m_cache_y[slot] == y && m_w.Exists(id))
        {
         ObjectSetInteger(m_chart, m_w.N(id), OBJPROP_COLOR, col);
         return;
        }
      m_w.Label(id, x, y, text, col, size, font);
      m_writes++;
      if(slot >= 0 && slot < SSR_SLOTS)
        {
         m_cache[slot]   = text;
         m_cache_x[slot] = x;
         m_cache_y[slot] = y;
        }
     }

   void              ClearCache(void)
     {
      for(int i = 0; i < SSR_SLOTS; i++)
        {
         m_cache[i]   = "\x01";   // a value no label can legitimately hold
         m_cache_x[i] = -32000;   // ...and a place none can legitimately sit
         m_cache_y[i] = -32000;
        }
     }

   //--- money and prices, formatted once so every row agrees
   string            Money(const double v, const bool sign = false)
     {
      //--- the sign is always written on a signed number, so the column
      //--- does not change width the moment a loss appears
      if(sign)
         return StringFormat("%s%.2f", (v < 0.0 ? "-" : "+"), MathAbs(v));
      return StringFormat("%.2f", v);
     }

   string            Price(const double v)
     {
      int d = m_state.price_digits;
      if(d < 0 || d > 8) d = 2;
      return DoubleToString(v, d);
     }

public:
                     CSSRPanel(void)
     : m_chart(0), m_port(NULL), m_flight(NULL),
       m_last_btn(""), m_last_btn_ms(0), m_prefix("SSRP_"),
       m_x(12), m_y(24), m_saved_mouse_move(0), m_saved_mouse_scroll(1),
       m_saved_quick_nav(1), m_saved_key_control(1),
       m_saved(false), m_collapsed(false), m_closed(false), m_compact(false),
       m_dragging(false),
       m_drag_dx(0), m_drag_dy(0),
       m_track_drag(false), m_track_x(0), m_track_y(0), m_track_w(0),
       m_last_drag_paint(0), m_corner(0),
       m_tab(SSR_TAB_TRADE), m_tag_sent(""), m_renders(0), m_writes(0)
     { m_state.Init(); ClearCache(); }

                    ~CSSRPanel(void) { Destroy(); }

   //--- the host hands its black box down so button presses land in the
   //--- same file as the samples. Optional by design; NULL is normal.
   void              SetFlightRecorder(CSSRFlightRecorder *f) { m_flight = f; }

   //+------------------------------------------------------------------+
   void              Create(const long chart_id, CSSRReplayPort *port,
                            const string prefix = "SSRP_")
     {
      m_chart  = chart_id;
      m_port   = port;
      m_prefix = prefix;
      m_w.Attach(chart_id, prefix);

      //--- a previous instance that died without cleaning up would
      //--- otherwise leave its objects underneath ours
      m_w.RemoveAll();
      ClearCache();

      //--- remember what the user had, so removing the panel gives the
      //--- chart back exactly as it was found
      if(!m_saved)
        {
         m_saved_mouse_move   = ChartGetInteger(m_chart, CHART_EVENT_MOUSE_MOVE);
         m_saved_mouse_scroll = ChartGetInteger(m_chart, CHART_MOUSE_SCROLL);
         m_saved_quick_nav    = ChartGetInteger(m_chart, CHART_QUICK_NAVIGATION);
         m_saved_key_control  = ChartGetInteger(m_chart, CHART_KEYBOARD_CONTROL);
         m_saved = true;
        }
      ChartSetInteger(m_chart, CHART_EVENT_MOUSE_MOVE, true);

      //+------------------------------------------------------------------+
      //| THE TWO LINES THAT MAKE THE KEYBOARD EXIST.                      |
      //|                                                                  |
      //| MetaTrader opens its quick-navigation bar when SPACE or ENTER is |
      //| pressed on a chart. SPACE is this product's play/pause key, so   |
      //| the first thing a user ever presses opens a text box in the      |
      //| corner and every key after it is typed into that box instead of  |
      //| reaching OnChartEvent. The replay stops responding and looks     |
      //| frozen. It is not frozen - it is not being spoken to.            |
      //|                                                                  |
      //| CHART_KEYBOARD_CONTROL is the second half: left on, the arrows,  |
      //| PgUp/PgDn and +/- ALSO scroll and zoom the chart underneath our  |
      //| own meaning for them, so every step command moved the view too.  |
      //|                                                                  |
      //| Both are saved above and restored in Destroy, because a chart    |
      //| the user gets back must be the chart they had.                   |
      //+------------------------------------------------------------------+
      ChartSetInteger(m_chart, CHART_QUICK_NAVIGATION, false);
      ChartSetInteger(m_chart, CHART_KEYBOARD_CONTROL, false);

      Render();
     }

   void              Destroy(void)
     {
      if(m_chart == 0)
         return;
      m_w.RemoveAll();
      //--- a panel destroyed mid-drag would otherwise leave chart
      //--- scrolling switched off for good
      if(m_saved)
        {
         ChartSetInteger(m_chart, CHART_EVENT_MOUSE_MOVE, m_saved_mouse_move);
         ChartSetInteger(m_chart, CHART_MOUSE_SCROLL,     m_saved_mouse_scroll);
         ChartSetInteger(m_chart, CHART_QUICK_NAVIGATION, m_saved_quick_nav);
         ChartSetInteger(m_chart, CHART_KEYBOARD_CONTROL, m_saved_key_control);
         m_saved = false;
        }
      m_dragging   = false;
      m_track_drag = false;
     }

   //--- the panel sits in a corner, not at a coordinate: ClampToChart
   //--- recomputes x and y every frame, so a caller setting them
   //--- directly would be overruled on the next repaint and would
   //--- rightly call that a bug
   void              SetCorner(const int c) { m_corner = (c & 3); Render(); }
   int               Corner(void)           { return m_corner; }

   //+------------------------------------------------------------------+
   //| A DRAG DOES NOT NEED A FULL REPAINT PER EVENT.                   |
   //|                                                                  |
   //| Render() re-reads the whole engine state and rewrites every       |
   //| object. Doing that for each mouse move puts sixty of them a       |
   //| second on the same thread that is pumping ticks. The bridge now   |
   //| thins the moves; this thins what each one costs. Thirty           |
   //| milliseconds is still smoother than a hand can move a window.     |
   //+------------------------------------------------------------------+
   //+------------------------------------------------------------------+
   //| KEEP THE PANEL ON THE CHART, AND NOTHING MORE.                   |
   //|                                                                  |
   //| This used to force the panel into a corner on EVERY frame, which |
   //| made dragging impossible: the mouse moved it and the next repaint|
   //| put it straight back. Position is the user's now; this only stops |
   //| a resized terminal from stranding the panel off the edge, where   |
   //| there is no way to get it back.                                   |
   //+------------------------------------------------------------------+
   void              ClampToChart(const int W, const int H)
     {
      int cw = (int)ChartGetInteger(m_chart, CHART_WIDTH_IN_PIXELS);
      int ch = (int)ChartGetInteger(m_chart, CHART_HEIGHT_IN_PIXELS);
      if(cw <= 0 || ch <= 0)
         return;                       // not measured yet; leave it alone
      //--- always leave the caption reachable, so a panel pushed off the
      //--- bottom can still be grabbed and dragged back
      if(m_x > cw - 60)        m_x = cw - 60;
      if(m_y > ch - SSR_HEADER_H - 4) m_y = ch - SSR_HEADER_H - 4;
      if(m_x < 0) m_x = 0;
      if(m_y < 0) m_y = 0;
     }

   //--- the Move button steps through the corners: a shortcut for
   //--- "get out of the way", not a replacement for dragging
   void              SnapToCorner(void)
     {
      m_corner = (m_corner + 1) % 4;
      int W = SSR_PANEL_W;
      int H = m_collapsed ? SSR_HEADER_H + 2 : SSR_PANEL_H;
      int cw = (int)ChartGetInteger(m_chart, CHART_WIDTH_IN_PIXELS);
      int ch = (int)ChartGetInteger(m_chart, CHART_HEIGHT_IN_PIXELS);
      if(cw < W + 24) cw = W + 24;
      if(ch < H + 40) ch = H + 40;
      int left = 12, right = cw - W - 12, top = 24, bottom = ch - H - 16;
      switch(m_corner)
        {
         case 1: m_x = right; m_y = top;    break;
         case 2: m_x = right; m_y = bottom; break;
         case 3: m_x = left;  m_y = bottom; break;
         default: m_x = left; m_y = top;    break;
        }
     }

   void              RenderDragging(void)
     {
      uint now = GetTickCount();
      if(now - m_last_drag_paint < 30)
         return;
      m_last_drag_paint = now;
      Render();
     }
   bool              IsCollapsed(void) { return m_collapsed; }
   int               Renders(void)     { return m_renders; }
   int               Writes(void)      { return m_writes; }
   int               ObjectCount(void) { return m_w.CountOwned(); }

   //+------------------------------------------------------------------+
   //| Pull state and repaint. Called from the host's timer.            |
   //+------------------------------------------------------------------+
   void              Render(void)
     {
      m_renders++;

      if(m_port != NULL)
         m_port.ReadState(m_state);
      else
         m_state.Init();

      //+------------------------------------------------------------------+
      //| CLOSED MEANS CLOSED - BUT NOT UNREACHABLE.                       |
      //|                                                                  |
      //| The X takes the whole panel off the chart. What it leaves is one |
      //| small button, because a control that removes its own only way    |
      //| back is a trap: the alternative would be detaching and           |
      //| reattaching the tool, which restarts the entire session.         |
      //+------------------------------------------------------------------+
      if(m_closed)
        {
         HideBody(true);
         m_w.Hide("bg", true);
         m_w.Hide("hdr", true);
         m_w.Hide("title", true);
         m_w.Hide("capinfo", true);
         m_w.Hide("collapse", true);
         m_w.Hide("move", true);
         m_w.Hide("close", true);
         m_w.Button("reopen", m_x, m_y, 76, SSR_HEADER_H, "SS Replay");
         ChartRedraw(m_chart);
         return;
        }
      //--- coming back from closed: the caption was hidden by hand, so
      //--- it has to be shown by hand. HideBody does not own these.
      m_w.Remove("reopen");
      string cap[] = {"bg","hdr","title","capinfo","collapse","move","close"};
      for(int ci = 0; ci < ArraySize(cap); ci++)
         m_w.Hide(cap[ci], false);

      //+------------------------------------------------------------------+
      //| A PANEL TALLER THAN ITS CHART IS AN INVISIBLE PANEL.             |
      //|                                                                  |
      //| The user's terminal had the Toolbox open to three quarters of    |
      //| the screen: a ninety-pixel chart, and of a 368-pixel panel only  |
      //| the caption drew. From their side that is a tool that did not     |
      //| start - and the smoke test had just proved the engine ran        |
      //| perfectly underneath it.                                          |
      //|                                                                  |
      //| So the panel measures the chart and, when it will not fit,       |
      //| keeps what is OPERATED - clock, transport, speed, status - and   |
      //| drops what is only CONSULTED. The tabs come back the moment      |
      //| there is room; nothing is lost, only deferred.                    |
      //+------------------------------------------------------------------+
      int W = SSR_PANEL_W;
      int chart_h = (int)ChartGetInteger(m_chart, CHART_HEIGHT_IN_PIXELS);
      bool was_compact = m_compact;
      m_compact = (chart_h > 0 && chart_h < SSR_PANEL_H + 24);
      if(m_compact != was_compact)
        {
         HideSheetArea(m_compact);
         PrintFormat("[panel] %s mode - the chart is %d pixels tall%s",
                     (m_compact ? "compact" : "full"), chart_h,
                     (m_compact ? "; press Ctrl+T to close the Toolbox and get "
                                  "the tabs back" : ""));
        }

      int H = m_collapsed ? SSR_HEADER_H + 2
                          : (m_compact ? SSR_PANEL_COMPACT_H : SSR_PANEL_H);
      ClampToChart(W, H);
      int x = m_x, y = m_y;

      m_w.Rect("bg",  x, y, W, H, SSR_C_PANEL, SSR_C_PANEL_EDGE);
      DrawCaption(x, y, W);

      if(m_collapsed)
        {
         HideBody(true);
         ChartRedraw(m_chart);
         return;
        }
      HideBody(false);

      int cy = y + SSR_HEADER_H + 3;
      cy = DrawClock(x, cy, W);
      cy = DrawTransport(x, cy, W);
      cy = DrawSpeed(x, cy, W);
      if(!m_compact)
        {
         cy = DrawTabs(x, cy, W);
         DrawSide(x + SSR_PAD, cy + 4);
         DrawSheet(x + SSR_PAD + SSR_SIDE_W + SSR_GAP, cy + 4,
                   W - 2 * SSR_PAD - SSR_SIDE_W - SSR_GAP);
        }
      DrawStatus(x, y + H - SSR_STATUS_H - 1, W);

      //+------------------------------------------------------------------+
      //| CREATING AN OBJECT IS NOT SHOWING IT.                            |
      //| On a chart with no incoming ticks - a weekend, a closed market,  |
      //| a paused replay - MetaTrader does not repaint by itself, so the  |
      //| panel exists and is invisible. One call, every frame, ends a      |
      //| whole class of "it did nothing" reports.                          |
      //+------------------------------------------------------------------+
      ChartRedraw(m_chart);
     }

private:
   //================================================================
   //  CAPTION
   //================================================================
   void              DrawCaption(const int x, const int y, const int W)
     {
      m_w.Rect("hdr", x + 1, y + 1, W - 2, SSR_HEADER_H, SSR_C_HEADER, SSR_C_HEADER);
      Text(0, "title", x + SSR_PAD, y + 4, "SS Replay", SSR_C_ACCENT, SSR_FS_TITLE);

      //--- the caption says WHAT IS RUNNING, in one line: state, symbol,
      //--- and whether the identity is hidden. It is the first thing a
      //--- screenshot has to answer.
      string right = SSRStateName(m_state.status);
      if(m_state.trade_symbol != "")
         right += "   " + m_state.trade_symbol;
      if(m_state.blind)
         right += "   [BLIND]";
      Text(1, "capinfo", x + 92, y + 5, right,
           SSRStateColor(m_state.status), SSR_FS_SMALL);

      m_w.Button("move", x + W - 62, y + 3, 18, SSR_HEADER_H - 5, "[]");
      m_w.Button("collapse", x + W - 42, y + 3, 18, SSR_HEADER_H - 5,
                 m_collapsed ? "+" : "-");
      m_w.ButtonC("close", x + W - 22, y + 3, 18, SSR_HEADER_H - 5, "X",
                  SSR_C_BTN, SSR_C_BTN_EDGE, SSR_C_STOP, SSR_FS_BODY);
     }

   //================================================================
   //  CLOCK + PROGRESS - always visible
   //================================================================
   int               DrawClock(const int x, const int y, const int W)
     {
      //--- the panel never formats the clock itself: Blind Mode has to
      //--- reach the text, and a second place that knows about blind
      //--- mode is the one that gets forgotten
      Text(2, "clock", x + SSR_PAD, y, m_state.clock_text,
           SSR_C_TEXT, SSR_FS_CLOCK);

      string pct = StringFormat("%d%%", (int)MathRound(m_state.progress * 100.0));
      if(m_state.pause_reason != "")
         pct += "   " + m_state.pause_reason;
      Text(3, "prog", x + W - SSR_PAD - 160, y + 6, pct,
           SSR_C_TEXT_DIM, SSR_FS_SMALL);

      m_w.Progress("bar", x + SSR_PAD, y + 22, W - 2 * SSR_PAD, 6,
                   m_state.progress, SSRStateColor(m_state.status));
      return y + 32;
     }

   //================================================================
   //  TRANSPORT - always visible
   //================================================================
   int               DrawTransport(const int x, const int y, const int W)
     {
      int n  = 7;
      int gp = 4;
      int bw = (W - 2 * SSR_PAD - (n - 1) * gp) / n;
      int bx = x + SSR_PAD;

      m_w.Button("restart", bx, y, bw, SSR_BTN_H, "|<",
                 false, m_state.connected);                       bx += bw + gp;
      m_w.Button("back10",  bx, y, bw, SSR_BTN_H, "<<",
                 false, m_state.CanStep());                       bx += bw + gp;
      m_w.Button("back",    bx, y, bw, SSR_BTN_H, "<",
                 false, m_state.CanStep());                       bx += bw + gp;
      m_w.Button("toggle",  bx, y, bw, SSR_BTN_H,
                 m_state.IsRunning() ? "Pause" : "Play",
                 m_state.IsRunning(),
                 m_state.CanPlay() || m_state.IsRunning());        bx += bw + gp;
      m_w.Button("step",    bx, y, bw, SSR_BTN_H, ">",
                 false, m_state.CanStep());                       bx += bw + gp;
      m_w.Button("step10",  bx, y, bw, SSR_BTN_H, ">>",
                 false, m_state.CanStep());                       bx += bw + gp;
      m_w.Button("reset",   bx, y, bw, SSR_BTN_H, "Reset",
                 false, m_state.connected);
      return y + SSR_BTN_H + SSR_GAP;
     }

   //================================================================
   //  SPEED - a real trackbar, always visible
   //================================================================
   int               DrawSpeed(const int x, const int y, const int W)
     {
      Text(4, "spdlbl", x + SSR_PAD, y + 3, "Speed", SSR_C_TEXT_DIM, SSR_FS_SMALL);

      int bx = x + SSR_PAD + 34;
      m_w.Button("spdn", bx, y, 18, SSR_ROW_H, "-");
      //--- the readout is a sunken field, not floating text: it is a
      //--- VALUE, and a value in a dialog sits in a box
      m_w.Rect("spdbox", bx + 20, y, 46, SSR_ROW_H, SSR_C_WELL, SSR_C_WELL_EDGE);
      Text(5, "spdval", bx + 24, y + 4, SSRSpeedName(m_state.speed_x100),
           SSR_C_TEXT, SSR_FS_BODY);
      m_w.Button("spup", bx + 68, y, 18, SSR_ROW_H, "+");

      //--- the bar. Twenty cells, each one clickable, because a click is
      //--- the only input a chart we are not attached to can give us.
      m_track_x = bx + 92;
      m_track_y = y + 2;
      m_track_w = (x + W - SSR_PAD) - m_track_x;
      m_w.TrackSegments("spdseg", m_track_x, m_track_y, m_track_w, 14,
                        SSRSpeedLadderIndex(m_state.speed_x100),
                        SSR_SPEED_LADDER_SIZE);

      //--- "5x" is a number. "1h in 12m" is something you can plan an
      //--- afternoon around, so the panel says both.
      Text(6, "spdmean", x + W - SSR_PAD - 96, y + SSR_ROW_H + 1,
           SSRSpeedMeaning(m_state.speed_x100), SSR_C_TEXT_DIM, SSR_FS_SMALL);
      return y + SSR_ROW_H + 14;
     }

   //================================================================
   //  TABS
   //================================================================
   string            TabName(const int i)
     {
      switch(i)
        {
         case SSR_TAB_TRADE:     return "Trade";
         case SSR_TAB_POSITIONS:
            return (m_state.open_positions > 0
                    ? "Positions " + IntegerToString(m_state.open_positions)
                    : "Positions");
         case SSR_TAB_STATS:     return "Stats";
         case SSR_TAB_SESSION:   return "Session";
        }
      return "";
     }

   int               DrawTabs(const int x, const int y, const int W)
     {
      int tw = 74, tx = x + SSR_PAD;
      for(int i = 0; i < SSR_TAB_COUNT; i++)
        {
         bool on = (i == m_tab);
         m_w.ButtonC("tab" + IntegerToString(i), tx, y, tw, SSR_TAB_H,
                     TabName(i),
                     on ? SSR_C_TAB_ON : SSR_C_TAB,
                     SSR_C_TAB_EDGE,
                     on ? SSR_C_TEXT : SSR_C_TEXT_DIM);
         tx += tw + 2;
        }
      //--- the sheet edge under the strip, so the tabs read as tabs
      m_w.Rect("tabline", x + SSR_PAD, y + SSR_TAB_H, W - 2 * SSR_PAD, 1,
               SSR_C_TAB_EDGE, SSR_C_TAB_EDGE);
      return y + SSR_TAB_H;
     }

   //================================================================
   //  THE ALWAYS-REACHABLE COLUMN
   //
   //  Beside the sheet, not inside it. Something you may want at any
   //  moment must not be behind a tab - and every one of these six
   //  reaches an engine feature that exists.
   //================================================================
   void              DrawSide(const int x, const int y)
     {
      int h = SSR_BTN_H, gp = 3, cy = y;

      m_w.Button("follow", x, cy, SSR_SIDE_W, h,
                 (m_state.charts_detached > 0
                  ? "Follow " + IntegerToString(m_state.charts_detached) + "  F"
                  : "Follow  F"),
                 m_state.charts_detached > 0,
                 m_state.charts_detached > 0);                  cy += h + gp;
      m_w.Button("lines", x, cy, SSR_SIDE_W, h,
                 m_state.lines_armed ? "Lines on  L" : "SL / TP  L",
                 m_state.lines_armed, m_state.can_trade);       cy += h + gp;
      m_w.Button("bookmark", x, cy, SSR_SIDE_W, h, "Bookmark  B",
                 false, m_state.connected);                     cy += h + gp;
      m_w.Button("jump", x, cy, SSR_SIDE_W, h, "Jump...  J",
                 false, m_state.connected);                     cy += h + gp;
      m_w.Button("sessions", x, cy, SSR_SIDE_W, h, "Sessions...  S",
                 false, m_state.connected);                     cy += h + gp;
      m_w.Button("fidelity", x, cy, SSR_SIDE_W, h, "Fidelity  D",
                 false, m_state.connected);
     }

   //================================================================
   //  THE SHEET
   //================================================================
   void              DrawSheet(const int x, const int y, const int w)
     {
      HideSheets();
      switch(m_tab)
        {
         case SSR_TAB_TRADE:     SheetTrade(x, y, w);     break;
         case SSR_TAB_POSITIONS: SheetPositions(x, y, w); break;
         case SSR_TAB_STATS:     SheetStats(x, y, w);     break;
         case SSR_TAB_SESSION:   SheetSession(x, y, w);   break;
        }
     }

   //--- every sheet's controls, so switching tabs cannot leave a button
   //--- from the previous one floating over the new one. Listed once,
   //--- because two lists drift.
   void              HideSheets(void)
     {
      //+------------------------------------------------------------------+
      //| THE SETUP BOX IS HIDDEN, NEVER DELETED.                          |
      //|                                                                  |
      //| Everything else on a sheet is redrawn from state, so deleting it |
      //| costs nothing. The box is the one control whose contents belong  |
      //| to the USER, and this runs at the top of every repaint: deleting |
      //| it would destroy and rebuild the object twenty-five times a      |
      //| second, which does not merely lose the text - it makes the box   |
      //| impossible to type in at all.                                    |
      //|                                                                  |
      //| Read on the way out, so leaving the tab keeps what was typed.    |
      //+------------------------------------------------------------------+
      ReadTag();
      m_w.Hide("tagbox", true);

      string ids[] = {"riskdn","riskup","armbtn","flipbtn","clrbtn","openln",
                      "buy","sell","be","flat",
                      "g1_fr","g1_lb","g1_lg","g2_fr","g2_lb","g2_lg",
                      "risklbl","riskval","riskmon","slrow","tprow","rrrow",
                      "sizerow","hintrow","setuprow","posempty","posmore",
                      "taglbl","poshint","trlbl","trdn","trup","troff",
                      "st1","st2","st3","st4","st5","st6","stmt",
                      "pv0","pv1","pv2","pvbg","pvfg","pvrst",
                      "g3_fr","g3_lb","g3_lg",
                      "ses1","ses2","ses3","ses4","ses5",
                      "ses6","keyhint","spreadrow","traderr"};
      for(int i = 0; i < ArraySize(ids); i++)
         m_w.Remove(ids[i]);
      for(int r = 0; r < 5; r++)
        {
         string t = IntegerToString(r);
         m_w.Remove("pr" + t);
         m_w.Remove("pl" + t);
         m_w.Remove("ph" + t);
         m_w.Remove("pb" + t);
         m_w.Remove("px" + t);
        }
     }

   //----------------------------------------------------------------
   //  TRADE
   //----------------------------------------------------------------
   void              SheetTrade(const int x, const int y, const int w)
     {
      //--- risk
      m_w.Group("g1", x, y, w, 40, "Risk");
      Text(10, "risklbl", x + 8, y + 14, "Risk per trade", SSR_C_TEXT_DIM);
      //--- the money answers "how much is that", and it sits with the
      //--- label rather than between the steppers, where it used to run
      //--- underneath the + button
      Text(19, "riskmon", x + 88, y + 14,
           Money(m_state.balance * m_state.risk_percent / 100.0), SSR_C_TEXT_DIM);
      m_w.Button("riskdn", x + w - 84, y + 11, 16, 16, "-");
      Text(11, "riskval", x + w - 62, y + 14,
           StringFormat("%.2f %%", m_state.risk_percent), SSR_C_TEXT);
      m_w.Button("riskup", x + w - 18, y + 11, 16, 16, "+");

      //+------------------------------------------------------------------+
      //| WHICH SETUP IS THIS?                                             |
      //|                                                                  |
      //| The engine has carried a tag on every position since Phase 9 and |
      //| nothing has ever set it, so the statement's Tag column has always |
      //| been blank. Typed here, it turns a session from "how did I do"    |
      //| into "which of my setups actually works" - the statistics engine  |
      //| already computes per tag, it just had nothing to group by.        |
      //|                                                                  |
      //| Read on the way into a trade, not on edit: the same one-read      |
      //| rule the setup panel follows, for the same reason.                |
      //+------------------------------------------------------------------+
      m_w.Label("taglbl", x + 8, y + 46, "Setup", SSR_C_TEXT_DIM, SSR_FS_SMALL);
      m_w.Edit("tagbox", x + 48, y + 42, w - 56, 18, m_state.trade_tag, false);
      m_w.Hide("tagbox", false);

      //+------------------------------------------------------------------+
      //| STOP AND TARGET ARE LINES.                                       |
      //|                                                                  |
      //| There is no points box here and there will not be one. A stop    |
      //| typed in points is chosen by arithmetic; a stop dragged on the   |
      //| chart is chosen by structure, and structure is the entire        |
      //| reason a person practises on a replay.                           |
      //+------------------------------------------------------------------+
      int gy = y + 66;
      m_w.Group("g2", x, gy, w, 106, "Stop & target");

      if(!m_state.lines_armed)
        {
         m_w.Button("armbtn", x + 8, gy + 14, w - 16, SSR_BTN_H,
                    "Place SL / TP lines on the chart", false, m_state.can_trade);
         Text(12, "hintrow", x + 8, gy + 42,
              m_state.can_trade
              ? "Then drag them. Buy / Sell would open with no stop until you do."
              : "Waiting for the first price.",
              SSR_C_TEXT_DIM, SSR_FS_SMALL);
        }
      else
        {
         //--- the side is read from the geometry, never asked for
         Text(12, "setuprow", x + 8, gy + 13,
              m_state.line_long ? "LONG setup - stop below, target above"
                                : "SHORT setup - stop above, target below",
              m_state.line_long ? SSR_C_RUN : SSR_C_STOP, SSR_FS_SMALL);

         Text(13, "slrow", x + 8, gy + 26,
              StringFormat("Stop      %s      %s",
                           Price(m_state.sl_price),
                           Money(-m_state.risk_money, true)), SSR_C_TEXT);
         Text(14, "tprow", x + 8, gy + 39,
              StringFormat("Target    %s      %s",
                           Price(m_state.tp_price),
                           Money(m_state.reward_money, true)), SSR_C_TEXT);
         Text(15, "rrrow", x + w - 96, gy + 26,
              m_state.rr > 0.0 ? StringFormat("%.2f R", m_state.rr) : "- R",
              SSR_C_TEXT_DIM);
         Text(16, "sizerow", x + w - 96, gy + 39,
              m_state.lot_from_risk > 0.0
              ? StringFormat("%.2f lot", m_state.lot_from_risk)
              : "no size",
              m_state.lot_from_risk > 0.0 ? SSR_C_TEXT_DIM : SSR_C_STOP);

         //--- ONE press opens what the lines describe. The side is not
         //--- asked for: it is already drawn on the chart.
         m_w.ButtonC("openln", x + 8, gy + 52, w - 16, 22,
                     m_state.lot_from_risk > 0.0
                     ? StringFormat("Open %s  %.2f lot",
                                    (m_state.line_long ? "LONG" : "SHORT"),
                                    m_state.lot_from_risk)
                     : "Open - no size at this stop",
                     m_state.lot_from_risk <= 0.0 ? SSR_C_DEAL_DIM
                     : (m_state.line_long ? SSR_C_BUY : SSR_C_SELL),
                     m_state.lot_from_risk <= 0.0 ? SSR_C_DEAL_DIM
                     : (m_state.line_long ? SSR_C_BUY_EDGE : SSR_C_SELL_EDGE),
                     SSR_C_DEAL_TEXT, SSR_FS_TITLE);
         m_w.Button("flipbtn", x + 8, gy + 78, (w - 22) / 2, 18, "Flip  X");
         m_w.Button("clrbtn",  x + 14 + (w - 22) / 2, gy + 78, (w - 22) / 2, 18,
                    "Remove lines");
        }

      //--- the deal buttons. The side the lines did not draw is dimmed,
      //--- so the chart and the dialog cannot disagree.
      int dy = gy + 112;
      int dw = (w - SSR_GAP) / 2;
      bool dim_buy  = !m_state.can_trade ||
                      (m_state.lines_armed && !m_state.line_long);
      bool dim_sell = !m_state.can_trade ||
                      (m_state.lines_armed &&  m_state.line_long);

      m_w.ButtonC("buy", x, dy, dw, 26,
                  StringFormat("Buy  %s", Price(m_state.ask)),
                  dim_buy ? SSR_C_DEAL_DIM : SSR_C_BUY,
                  dim_buy ? SSR_C_DEAL_DIM : SSR_C_BUY_EDGE,
                  SSR_C_DEAL_TEXT, SSR_FS_TITLE);
      m_w.ButtonC("sell", x + dw + SSR_GAP, dy, dw, 26,
                  StringFormat("Sell  %s", Price(m_state.bid)),
                  dim_sell ? SSR_C_DEAL_DIM : SSR_C_SELL,
                  dim_sell ? SSR_C_DEAL_DIM : SSR_C_SELL_EDGE,
                  SSR_C_DEAL_TEXT, SSR_FS_TITLE);

      Text(17, "spreadrow", x, dy + 30,
           StringFormat("Spread %.1f pt", m_state.spread_points),
           SSR_C_TEXT_DIM, SSR_FS_SMALL);

      //--- a refused order says why, where the order was refused
      if(m_port != NULL && m_port.TradeError() != "")
         Text(18, "traderr", x + 84, dy + 30, m_port.TradeError(),
              SSR_C_STOP, SSR_FS_SMALL);
     }

   //----------------------------------------------------------------
   //  POSITIONS
   //----------------------------------------------------------------
   void              SheetPositions(const int x, const int y, const int w)
     {
      m_w.Group("g1", x, y, w, 138, "Open positions");

      if(m_state.pos_rows <= 0)
        {
         Text(20, "posempty", x + 8, y + 16,
              "Nothing open. Place the lines (L), drag the stop, press Open.",
              SSR_C_TEXT_DIM, SSR_FS_SMALL);
        }
      else
        {
         //--- one row per position: side and size, its P/L in money,
         //--- and its own close button. Managed from the panel, not by
         //--- hunting the chart for the right dashed line.
         for(int r = 0; r < m_state.pos_rows; r++)
           {
            int ry = y + 14 + r * 20;
            string t = IntegerToString(r);
            Text(20 + r, "pr" + t, x + 8, ry + 3, m_state.pos_text[r],
                 SSR_C_TEXT);
            Text(25 + r, "pl" + t, x + w - 140, ry + 3,
                 Money(m_state.pos_pl[r], true),
                 m_state.pos_pl[r] >= 0.0 ? SSR_C_RUN : SSR_C_STOP);

            //+------------------------------------------------------------------+
            //| SCALE OUT AND PROTECT, on the row of the trade they act on.      |
            //|                                                                  |
            //| Both worked in the engine and had no button, so the tool modelled |
            //| the five seconds of entering a trade and none of the hour of      |
            //| managing it - which is the part being practised.                   |
            //+------------------------------------------------------------------+
            m_w.ButtonC("ph" + t, x + w - 68, ry, 18, 17, "H",
                        SSR_C_BTN, SSR_C_BTN_EDGE, SSR_C_TEXT, SSR_FS_SMALL);
            m_w.ButtonC("pb" + t, x + w - 47, ry, 18, 17, "B",
                        SSR_C_BTN, SSR_C_BTN_EDGE, SSR_C_RUN, SSR_FS_SMALL);
            m_w.ButtonC("px" + t, x + w - 26, ry, 18, 17, "X",
                        SSR_C_BTN, SSR_C_BTN_EDGE, SSR_C_STOP, SSR_FS_SMALL);
           }
         //--- the cap is a display cap; when it hides trades, say so
         if(m_state.open_positions > m_state.pos_rows)
            Text(30, "posmore", x + 8, y + 118,
                 StringFormat("+%d more - Close all still closes everything",
                              m_state.open_positions - m_state.pos_rows),
                 SSR_C_HOLD, SSR_FS_SMALL);
        }

      //--- the hint's line is also where a refusal goes. The Trade sheet
      //--- has its own error row and these three buttons are not on it,
      //--- so "too small to split at this lot step" would otherwise only
      //--- reach the log - and a button that does nothing visible is a
      //--- button the user reports as broken.
      if(m_port != NULL && m_port.TradeError() != "")
         Text(31, "poshint", x + 8, y + 132, m_port.TradeError(),
              SSR_C_STOP, SSR_FS_SMALL);
      else
         Text(31, "poshint", x + 8, y + 132,
              "H halves the position   B moves its stop to entry   X closes it",
              SSR_C_TEXT_DIM, SSR_FS_SMALL);

      int by = y + 144;
      int bw = (w - SSR_GAP) / 2;
      m_w.Button("be",   x, by, bw, SSR_BTN_H, "Break-even all",
                 false, m_state.open_positions > 0);
      m_w.Button("flat", x + bw + SSR_GAP, by, bw, SSR_BTN_H, "Close all",
                 false, m_state.open_positions > 0);

      //--- the trailing distance, in points, applied to what is open now
      //--- AND to whatever opens next
      int ty = by + SSR_BTN_H + 8;
      Text(32, "trlbl", x + 8, ty + 3,
           StringFormat("Trailing stop   %s",
                        m_state.trail_points > 0.0
                        ? StringFormat("%.0f pt", m_state.trail_points)
                        : "off"),
           m_state.trail_points > 0.0 ? SSR_C_RUN : SSR_C_TEXT_DIM);
      m_w.Button("trdn", x + w - 86, ty, 18, SSR_ROW_H, "-");
      m_w.Button("trup", x + w - 64, ty, 18, SSR_ROW_H, "+");
      m_w.Button("troff", x + w - 42, ty, 42, SSR_ROW_H, "off");
     }

   //----------------------------------------------------------------
   //  STATS
   //----------------------------------------------------------------
   void              SheetStats(const int x, const int y, const int w)
     {
      m_w.Group("g1", x, y, w, 68, "Account");
      Text(30, "st1", x + 8, y + 14,
           StringFormat("Balance      %s", Money(m_state.balance)), SSR_C_TEXT);
      Text(31, "st2", x + 8, y + 28,
           StringFormat("Equity       %s", Money(m_state.equity)), SSR_C_TEXT);
      Text(32, "st3", x + 8, y + 42,
           StringFormat("Floating     %s", Money(m_state.floating, true)),
           m_state.floating >= 0.0 ? SSR_C_RUN : SSR_C_STOP);

      m_w.Group("g2", x, y + 72, w, 68, "This run");
      Text(33, "st4", x + 8, y + 86,
           StringFormat("Bars         %d", (int)m_state.bars_consumed),
           SSR_C_TEXT_DIM);
      Text(34, "st5", x + 8, y + 100,
           StringFormat("Ticks        %d", (int)m_state.ticks_emitted),
           SSR_C_TEXT_DIM);
      //--- rejected ticks are shown even when zero. A counter that only
      //--- appears when it is non-zero teaches nobody what it counts.
      Text(35, "st6", x + 8, y + 114,
           StringFormat("Rejected     %d      guard %d",
                        (int)m_state.ticks_rejected,
                        (int)m_state.guard_violations),
           m_state.ticks_rejected > 0 ? SSR_C_HOLD : SSR_C_TEXT_DIM);

      //--- the statement. On the Stats sheet because that is where a
      //--- person is already looking at what the session did.
      m_w.Button("stmt", x, y + 146, w, SSR_BTN_H,
                 "Save HTML statement", false, m_state.can_trade);

      //+------------------------------------------------------------------+
      //| THE EVALUATION.                                                  |
      //|                                                                  |
      //| Drawn only when one is running, because a panel that shows an    |
      //| empty scoreboard to everyone who is not being scored is a panel  |
      //| asking a question nobody put to it.                              |
      //|                                                                  |
      //| The bar is the profit target. The line under it is the floor -   |
      //| the equity at which the run ends - because a target without the  |
      //| price of missing it is only half the rule.                       |
      //+------------------------------------------------------------------+
      if(!m_state.prop_on)
        {
         m_w.Hide("pv0", true);   m_w.Hide("pv1", true);
         m_w.Hide("pv2", true);   m_w.Hide("pvbg", true);
         m_w.Hide("pvfg", true);  m_w.Hide("pvrst", true);
         return;
        }

      int py = y + 146 + SSR_BTN_H + 10;
      m_w.Group("g3", x, py, w, 84, "Evaluation");

      color verdict = SSR_C_TEXT;
      if(m_state.prop_state == 2) verdict = SSR_C_RUN;    // PASSED
      if(m_state.prop_state == 3) verdict = SSR_C_STOP;   // FAILED
      if(m_state.prop_state == 4) verdict = SSR_C_HOLD;   // VOID

      //--- through Text, not Label, so an unchanged verdict is not
      //--- rewritten ten times a second onto a chart that is already
      //--- repainting itself with ticks
      Text(54, "pv0", x + 8, py + 14, m_state.prop_state_name,
           verdict, SSR_FS_BODY, SSR_FONT);
      Text(55, "pv1", x + 8, py + 30, m_state.prop_rules,
           SSR_C_TEXT_DIM, SSR_FS_SMALL, SSR_FONT);

      //--- the target bar. Width is the fraction, floored at one pixel
      //--- so "started" and "nothing yet" do not look identical.
      int bw = w - 16;
      int fw = (int)(bw * (m_state.prop_progress < 0.0 ? 0.0
                           : (m_state.prop_progress > 1.0 ? 1.0
                              : m_state.prop_progress)));
      if(m_state.prop_progress > 0.0 && fw < 1)
         fw = 1;
      m_w.Rect("pvbg", x + 8, py + 46, bw, 8, SSR_C_WELL, SSR_C_WELL_EDGE);
      if(fw > 0)
         m_w.Rect("pvfg", x + 8, py + 46, fw, 8, SSR_C_RUN, SSR_C_RUN);
      else
         m_w.Hide("pvfg", true);

      Text(56, "pv2", x + 8, py + 58, m_state.prop_headline,
           verdict, SSR_FS_SMALL, SSR_FONT);

      //--- Reset is offered only once the run is over. Offering it mid
      //--- run would be a button whose only use is to erase a bad day.
      if(m_state.prop_state >= 2)
         m_w.Button("pvrst", x + 8, py + 74, bw, SSR_BTN_H - 4,
                    "Reset evaluation", false, true);
      else
         m_w.Hide("pvrst", true);
     }

   //----------------------------------------------------------------
   //  SESSION
   //----------------------------------------------------------------
   void              SheetSession(const int x, const int y, const int w)
     {
      m_w.Group("g1", x, y, w, 68, "Session");
      Text(40, "ses1", x + 8, y + 14,
           StringFormat("Bookmarks    %d", m_state.bookmarks), SSR_C_TEXT_DIM);
      Text(41, "ses2", x + 8, y + 28,
           StringFormat("Streams      %d      skew %d ms",
                        m_state.streams, (int)m_state.skew_msc),
           m_state.skew_msc == 0 ? SSR_C_TEXT_DIM : SSR_C_STOP);
      Text(42, "ses3", x + 8, y + 42,
           m_state.leak_clean ? "Charts       clean"
                              : "Charts       " + m_state.leak_advice,
           m_state.leak_clean ? SSR_C_TEXT_DIM : SSR_C_HOLD);

      m_w.Group("g2", x, y + 72, w, 68, "Keyboard");
      Text(43, "ses4", x + 8, y + 86,
           "Space play/pause    < > step    PgUp/PgDn x10",
           SSR_C_TEXT_DIM, SSR_FS_SMALL);
      Text(44, "keyhint", x + 8, y + 99,
           "+ - speed    R reset    J jump    B bookmark",
           SSR_C_TEXT_DIM, SSR_FS_SMALL);
      Text(45, "ses5", x + 8, y + 112,
           "S sessions   F follow   D fidelity   L lines   X flip",
           SSR_C_TEXT_DIM, SSR_FS_SMALL);
      Text(46, "ses6", x + 8, y + 125,
           "caption:  [] corner    -  collapse    X  close",
           SSR_C_TEXT_DIM, SSR_FS_SMALL);
     }

   //================================================================
   //  STATUS STRIP
   //================================================================
   void              DrawStatus(const int x, const int y, const int W)
     {
      m_w.Rect("status", x + 1, y, W - 2, SSR_STATUS_H,
               SSR_C_STATUS, SSR_C_GROUP_EDGE);

      Text(50, "stbal", x + SSR_PAD, y + 4,
           StringFormat("Balance %s", Money(m_state.balance)), SSR_C_TEXT_DIM,
           SSR_FS_SMALL);
      Text(51, "stflt", x + 132, y + 4,
           StringFormat("Floating %s", Money(m_state.floating, true)),
           m_state.floating >= 0.0 ? SSR_C_RUN : SSR_C_STOP, SSR_FS_SMALL);
      Text(52, "stopen", x + 244, y + 4,
           StringFormat("%d open", m_state.open_positions),
           SSR_C_TEXT_DIM, SSR_FS_SMALL);

      //--- SHOW WHAT IS RUNNING, NOT WHAT WAS ASKED FOR. A tool that
      //--- displays the request while emitting something else is the
      //--- quiet dishonesty this whole product exists to avoid.
      bool degraded = (m_state.fidelity_effective != m_state.fidelity);
      Text(53, "stfid", x + 306, y + 4,
           SSRFidelityName(m_state.fidelity_effective) + (degraded ? " !" : ""),
           degraded ? SSR_C_HOLD : SSRFidelityColor(m_state.fidelity_effective),
           SSR_FS_SMALL);
     }

   //--- the tab strip, the side column and the sheet: everything the
   //--- compact panel does without. Listed here rather than inline so
   //--- compact mode and collapse cannot disagree about what they hide.
   void              HideSheetArea(const bool hidden)
     {
      string ids[] = {"tab0","tab1","tab2","tab3","tabline",
                      "follow","lines","bookmark","jump","sessions","fidelity"};
      for(int i = 0; i < ArraySize(ids); i++)
         m_w.Hide(ids[i], hidden);
      if(hidden)
         HideSheets();
     }

   //--- everything below the caption, hidden when collapsed
   void              HideBody(const bool hidden)
     {
      string ids[] = {"clock","prog","bar_bg","bar_fill",
                      "restart","back10","back","toggle","step","step10","reset",
                      "spdlbl","spdn","spdbox","spdval","spup","spdmean",
                      "tab0","tab1","tab2","tab3","tabline",
                      "follow","lines","bookmark","jump","sessions","fidelity",
                      "status","stbal","stflt","stopen","stfid"};
      for(int i = 0; i < ArraySize(ids); i++)
         m_w.Hide(ids[i], hidden);
      for(int t = 0; t < SSR_SPEED_LADDER_SIZE; t++)
         m_w.Hide("spdseg" + IntegerToString(t), hidden);
      if(hidden)
         HideSheets();
     }

public:
   //+------------------------------------------------------------------+
   //| The trade controls. Every one goes through the port, so the      |
   //| panel still knows nothing about accounts - only about buttons.   |
   //+------------------------------------------------------------------+
   bool              TradeButton(const string id)
     {
      if(m_port == NULL)
         return false;

      if(id == "buy")   return m_port.Buy();
      if(id == "sell")  return m_port.Sell();
      if(id == "flat")  return m_port.CloseAll();
      if(id == "be")    return m_port.BreakEvenAll();

      //--- risk moves in steps a person actually uses. Not a text box:
      //--- typing into a chart object is worse than two buttons, and
      //--- a mistyped 10 where 1 was meant is a real loss to learn from
      //--- in the wrong way.
      if(id == "riskdn") return m_port.SetRiskPercent(StepRisk(-1));
      if(id == "riskup") return m_port.SetRiskPercent(StepRisk(+1));
      return false;
     }

   //--- 0 / 50 / 100 / 150 / 200 / 300 / 500 points. Off is a rung, so
   //--- "-" walks all the way back to it instead of sticking at 50.
   double            StepTrail(const int dir)
     {
      double ladder[] = {0.0, 50.0, 100.0, 150.0, 200.0, 300.0, 500.0};
      int    n = ArraySize(ladder), at = 0;
      for(int i = 0; i < n; i++)
         if(MathAbs(ladder[i] - m_state.trail_points) < 0.5)
           { at = i; break; }
      at += dir;
      if(at < 0)      at = 0;
      if(at >= n)     at = n - 1;
      return ladder[at];
     }

   //--- 0.10 / 0.25 / 0.50 / 1.00 / 2.00 - the sizes people trade,
   //--- rather than a linear ramp through numbers nobody chooses
   double            StepRisk(const int dir)
     {
      double ladder[] = {0.10, 0.25, 0.50, 1.00, 2.00, 3.00, 5.00};
      int    n = ArraySize(ladder), at = 2;
      for(int i = 0; i < n; i++)
         if(MathAbs(ladder[i] - m_state.risk_percent) < 0.001)
           { at = i; break; }
      at += dir;
      if(at < 0)      at = 0;
      if(at >= n)     at = n - 1;
      return ladder[at];
     }

   //+------------------------------------------------------------------+
   //| Which commands are THIS layer's to run.                          |
   //|                                                                  |
   //| One list, so the answer cannot drift from what Execute actually  |
   //| implements. Everything else belongs to the host, which owns the  |
   //| dialogs and the objects they need, and it only gets the event if |
   //| the panel lets it past.                                          |
   //+------------------------------------------------------------------+
   bool              Owns(const ENUM_SSR_CMD c)
     {
      switch(c)
        {
         case SSR_CMD_NONE:
         case SSR_CMD_SESSIONS:          // the host owns the session list
         case SSR_CMD_JUMP:              // ...and the range dialog
         case SSR_CMD_REPLAY_FROM_HERE:  // ...and this one is not bound yet
            return false;
        }
      return true;
     }

   //--- EVERY COMMAND SAYS WHAT IT DID.
   //--- A bookmark that is stored and shows nothing looks exactly like
   //--- a bookmark that was never stored. One line per command settles
   //--- that in one run instead of three.
   bool              Execute(const ENUM_SSR_CMD cmd)
     {
      bool ok = ExecuteInner(cmd);
      if(cmd != SSR_CMD_NONE)
        {
         //--- "refused" on its own sends the user back here to ask why.
         //--- The port already knows; print it.
         string why = "";
         if(!ok && m_port != NULL && m_port.TradeError() != "")
            why = "  (" + m_port.TradeError() + ")";
         PrintFormat("[panel] %s -> %s%s", SSRCmdName(cmd),
                     (ok ? "ok" : "refused"), why);
         //--- and into the black box, in the same stream as the samples,
         //--- so a fault can be read as "he pressed this, and then this
         //--- number stopped moving" rather than guessed at
         if(m_flight != NULL)
            m_flight.Event(StringFormat("panel %s -> %s%s", SSRCmdName(cmd),
                                        (ok ? "ok" : "refused"), why));
        }
      return ok;
     }

   bool              ExecuteInner(const ENUM_SSR_CMD cmd)
     {
      if(m_port == NULL)
         return false;

      switch(cmd)
        {
         case SSR_CMD_TOGGLE:
            return (m_state.IsRunning() ? m_port.Pause() : m_port.Play());
         case SSR_CMD_PLAY:      return m_port.Play();
         case SSR_CMD_PAUSE:     return m_port.Pause();
         case SSR_CMD_RESET:     return m_port.Reset();
         case SSR_CMD_STEP_FWD:    return m_port.StepBars(1);
         case SSR_CMD_STEP_FWD_10: return m_port.StepBars(10);
         case SSR_CMD_STEP_BACK:   return m_port.StepBack(1);
         case SSR_CMD_STEP_BACK_10: return m_port.StepBack(10);
         case SSR_CMD_RESTART:     return m_port.Restart();
         case SSR_CMD_BOOKMARK:
            return m_port.Bookmark(SSRFormatMsc(m_state.now_msc));
         case SSR_CMD_FOLLOW:    return m_port.FollowCharts();

         case SSR_CMD_LINES_TOGGLE:
            return (m_state.lines_armed ? m_port.ClearLines() : m_port.ArmLines());
         case SSR_CMD_LINES_FLIP:
            return m_port.FlipLines();

         case SSR_CMD_SPEED_UP:
           {
            int i = SSRSpeedLadderIndex(m_state.speed_x100);
            if(i < SSR_SPEED_LADDER_SIZE - 1) i++;
            return m_port.SetSpeedX100(SSRSpeedLadder(i));
           }
         case SSR_CMD_SPEED_DOWN:
           {
            int i = SSRSpeedLadderIndex(m_state.speed_x100);
            if(i > 0) i--;
            return m_port.SetSpeedX100(SSRSpeedLadder(i));
           }
         case SSR_CMD_FIDELITY_CYCLE:
           {
            int f = ((int)m_state.fidelity + 1) % 3;
            return m_port.SetFidelity((ENUM_SSR_FIDELITY)f);
           }
         case SSR_CMD_COLLAPSE:
            m_collapsed = !m_collapsed;
            Render();
            return true;
        }
      return false;
     }

   //+------------------------------------------------------------------+
   //| Turn a pixel on the groove into a speed.                         |
   //|                                                                  |
   //| Clicking the groove jumps there; dragging the thumb follows the  |
   //| mouse. Both go through here, so a click and a drag cannot land   |
   //| on different stops for the same pixel.                           |
   //+------------------------------------------------------------------+
   bool              SpeedFromPixel(const int mx)
     {
      if(m_port == NULL || m_track_w <= 1)
         return false;
      double f = (double)(mx - m_track_x) / (double)(m_track_w - 1);
      return m_port.SetSpeedX100(SSRSpeedAtFraction(f));
     }

   bool              OnTrack(const int mx, const int my)
     {
      return (mx >= m_track_x - 6 && mx <= m_track_x + m_track_w + 6 &&
              my >= m_track_y - 2 && my <= m_track_y + SSR_TRACK_H);
     }

   //+------------------------------------------------------------------+
   //| ASK THE BUTTONS, DO NOT WAIT TO BE TOLD.                         |
   //|                                                                  |
   //| MetaTrader delivers OnChartEvent only to the chart a program is  |
   //| attached to. The panel now lives on the replay chart and this    |
   //| program does not, so no click will ever be delivered here. Two   |
   //| attempts were made to route them across and the second one is    |
   //| why this exists: an indicator created with iCustom and shown by  |
   //| ChartIndicatorAdd keeps the CREATOR's chart context, so it       |
   //| received the host's events, not the replay chart's, and its own  |
   //| log line said so - "chart X -> host X", the same number twice.   |
   //|                                                                  |
   //| But a click leaves a mark. MetaTrader latches OBJ_BUTTON down    |
   //| when it is pressed, and OBJPROP_STATE can be read from ANY       |
   //| chart. So the panel asks, once a tick, which of its buttons is   |
   //| held - and clears it, which is both how the press is consumed    |
   //| and how the button pops back up.                                 |
   //|                                                                  |
   //| This is not a workaround invented here. It is the same reasoning |
   //| already written for the stop and target lines one layer over:    |
   //| a dragged object updates itself whether anyone was listening or  |
   //| not, so asking needs no events at all. The lines have worked      |
   //| that way since the day they were built.                          |
   //|                                                                  |
   //| It walks the chart's object list rather than a list of names,    |
   //| so a button added to a sheet later cannot be forgotten here.     |
   //|                                                                  |
   //| Returns a command the HOST must run (the dialogs it owns), or    |
   //| SSR_CMD_NONE. Everything this layer owns is already done.        |
   //+------------------------------------------------------------------+
   ENUM_SSR_CMD      PollClicks(void)
     {
      if(m_chart == 0)
         return SSR_CMD_NONE;

      ENUM_SSR_CMD  for_host = SSR_CMD_NONE;
      bool          acted    = false;
      int           total    = ObjectsTotal(m_chart, -1, OBJ_BUTTON);

      for(int i = total - 1; i >= 0; i--)
        {
         string name = ObjectName(m_chart, i, -1, OBJ_BUTTON);
         if(StringFind(name, m_prefix) != 0)
            continue;
         if(!ObjectGetInteger(m_chart, name, OBJPROP_STATE))
            continue;

         //--- consume it first. If anything below throws the frame away,
         //--- the button must still come back up rather than stay held
         //--- and fire again on the next tick.
         ObjectSetInteger(m_chart, name, OBJPROP_STATE, false);

         //+------------------------------------------------------------------+
         //| ONE PRESS IS ONE COMMAND.                                        |
         //|                                                                  |
         //| Consuming the state is not enough: MetaTrader re-latches it for  |
         //| as long as the mouse is down, so this poll ran the same command  |
         //| twenty-five times a second. A recording caught play/pause firing |
         //| four times in 350ms and step-forward three times in 100ms - the  |
         //| user pressed each of them once.                                  |
         //|                                                                  |
         //| A floor of 200ms kills hold-to-repeat and still allows five      |
         //| deliberate presses a second, which is faster than anyone steps   |
         //| through a replay on purpose.                                     |
         //+------------------------------------------------------------------+
         uint now_ms = GetTickCount();
         if(name == m_last_btn && (now_ms - m_last_btn_ms) < 200)
           {
            acted = true;          // repaint, so the button visibly lifts
            continue;
           }
         m_last_btn    = name;
         m_last_btn_ms = now_ms;

         ENUM_SSR_CMD c = Dispatch(StringSubstr(name, StringLen(m_prefix)));
         acted = true;
         if(c != SSR_CMD_NONE)
            for_host = c;
        }

      if(acted)
         Render();
      return for_host;
     }

   //+------------------------------------------------------------------+
   //| THE SETUP BOX HAS NO EVENT.                                      |
   //|                                                                  |
   //| An OBJ_EDIT on a chart this program is not attached to never     |
   //| reaches OnChartEvent, so nothing tells the panel the user typed. |
   //| It is read instead - once, on the way into whatever they pressed |
   //| next - which is exactly when the tag matters and never before.   |
   //|                                                                  |
   //| The Exists check is not decoration: EditText answers "" for a    |
   //| box that is not on screen, and "" is also a real answer from a   |
   //| box the user cleared. Without it, opening the Positions tab      |
   //| would silently wipe the tag.                                     |
   //+------------------------------------------------------------------+
   void              ReadTag(void)
     {
      if(m_port == NULL || !m_w.Exists("tagbox"))
         return;
      string t = m_w.EditText("tagbox");

      //+------------------------------------------------------------------+
      //| COMPARED AGAINST WHAT WAS SENT, not against what came back.      |
      //|                                                                  |
      //| The port cleans a tag on the way in - it trims it and takes the  |
      //| commas out, because the journal is a CSV too - so a box holding  |
      //| " a, b " never equals the stored "a b", and a comparison against |
      //| the stored value would resend it on every single repaint.        |
      //|                                                                  |
      //| That is not merely wasteful. Every port verb clears the last     |
      //| trade error as its first act, so a refusal from the Positions    |
      //| sheet - "too small to split at this lot step" - would be wiped   |
      //| by this call in the very repaint that was meant to display it,   |
      //| and the button would look like it did nothing at all.            |
      //+------------------------------------------------------------------+
      if(t == m_tag_sent)
         return;
      m_tag_sent = t;
      m_port.SetTradeTag(t);
     }

   //--- one place that turns an object name into an action, shared by
   //--- the poll and by the event path, so the two cannot drift
   ENUM_SSR_CMD      Dispatch(const string what)
     {
      ReadTag();
      //--- the tab strip is not a command: it changes nothing in the
      //--- engine, only which sheet is on top
      if(StringLen(what) == 4 && StringSubstr(what, 0, 3) == "tab")
        {
         m_tab = (int)StringToInteger(StringSubstr(what, 3));
         return SSR_CMD_NONE;
        }

      //--- a speed cell. Twenty of them make the groove, so clicking
      //--- anywhere along the bar lands on that stop.
      if(StringLen(what) > 6 && StringSubstr(what, 0, 6) == "spdseg")
        {
         if(m_port != NULL)
            m_port.SetSpeedX100(SSRSpeedLadder((int)StringToInteger(
                                   StringSubstr(what, 6))));
         return SSR_CMD_NONE;
        }

      //--- the panel has no mouse events on a chart it is not attached
      //--- to, so it cannot be dragged. It steps between the corners
      //--- instead, which is what dragging a fixed-size panel is for.
      if(what == "move")
        {
         SnapToCorner();
         return SSR_CMD_NONE;
        }
      if(what == "stmt")
        {
         if(m_port != NULL)
           {
            string where = "";
            if(m_port.ExportStatement(where))
               PrintFormat("[panel] statement saved -> MQL5\\Files\\%s", where);
            else
               PrintFormat("[panel] statement -> refused (%s)",
                           m_port.TradeError());
           }
         return SSR_CMD_NONE;
        }
      if(what == "pvrst")
        {
         if(m_port != NULL)
            PrintFormat("[panel] reset evaluation -> %s",
                        m_port.ResetEvaluation() ? "ok"
                        : "refused (" + m_port.TradeError() + ")");
         return SSR_CMD_NONE;
        }
      if(what == "close")  { m_closed = true;  return SSR_CMD_NONE; }
      if(what == "reopen") { m_closed = false; return SSR_CMD_NONE; }

      //+------------------------------------------------------------------+
      //| THE THREE ROW BUTTONS.                                           |
      //|                                                                  |
      //| px halves nothing and closes everything, ph halves, pb protects. |
      //| All three name a ROW, not a ticket: the row is what the user      |
      //| aimed at, and the ticket it was showing is read at the moment of  |
      //| the press. A row that has scrolled away since is out of range and |
      //| does nothing, which is the right answer - it is better to miss a  |
      //| click than to close a position the user was not looking at.       |
      //+------------------------------------------------------------------+
      if(StringLen(what) == 3 && StringSubstr(what, 0, 1) == "p" &&
         (StringSubstr(what, 1, 1) == "x" || StringSubstr(what, 1, 1) == "h" ||
          StringSubstr(what, 1, 1) == "b"))
        {
         string act = StringSubstr(what, 1, 1);
         int    r   = (int)StringToInteger(StringSubstr(what, 2));
         if(m_port == NULL || r < 0 || r >= m_state.pos_rows)
            return SSR_CMD_NONE;

         long   tk = m_state.pos_ticket[r];
         bool   ok = false;
         string verb = "";
         if(act == "x")      { verb = "close";      ok = m_port.ClosePosition(tk); }
         else if(act == "h") { verb = "half";       ok = m_port.ClosePartial(tk, 0.5); }
         else                { verb = "break-even"; ok = m_port.BreakEven(tk); }

         string line = StringFormat("%s #%d -> %s", verb, (int)tk,
                                    ok ? "ok"
                                    : "refused (" + m_port.TradeError() + ")");
         PrintFormat("[panel] %s", line);
         if(m_flight != NULL)
            m_flight.Event("panel " + line);
         return SSR_CMD_NONE;
        }

      //--- the trailing distance. One ladder, so "+" from off lands on a
      //--- distance somebody would actually use rather than on 1 point.
      if(what == "trdn" || what == "trup" || what == "troff")
        {
         if(m_port == NULL)
            return SSR_CMD_NONE;
         double pts = (what == "troff") ? 0.0
                      : StepTrail(what == "trup" ? +1 : -1);
         bool ok = m_port.SetTrailing(pts);
         string line = StringFormat("trailing %s -> %s",
                                    pts > 0.0 ? StringFormat("%.0f pt", pts) : "off",
                                    ok ? "ok"
                                    : "refused (" + m_port.TradeError() + ")");
         PrintFormat("[panel] %s", line);
         if(m_flight != NULL)
            m_flight.Event("panel " + line);
         return SSR_CMD_NONE;
        }

      ENUM_SSR_CMD c = SSR_CMD_NONE;
      if(what == "toggle")        c = SSR_CMD_TOGGLE;
      else if(what == "step")     c = SSR_CMD_STEP_FWD;
      else if(what == "step10")   c = SSR_CMD_STEP_FWD_10;
      else if(what == "back")     c = SSR_CMD_STEP_BACK;
      else if(what == "back10")   c = SSR_CMD_STEP_BACK_10;
      else if(what == "reset")    c = SSR_CMD_RESET;
      else if(what == "restart")  c = SSR_CMD_RESTART;
      else if(what == "follow")   c = SSR_CMD_FOLLOW;
      else if(what == "bookmark") c = SSR_CMD_BOOKMARK;
      else if(what == "fidelity") c = SSR_CMD_FIDELITY_CYCLE;
      else if(what == "jump")     c = SSR_CMD_JUMP;
      else if(what == "sessions") c = SSR_CMD_SESSIONS;
      else if(what == "lines")    c = SSR_CMD_LINES_TOGGLE;
      else if(what == "armbtn")   c = SSR_CMD_LINES_TOGGLE;
      else if(what == "clrbtn")   { if(m_port != NULL) m_port.ClearLines();
                                    return SSR_CMD_NONE; }
      else if(what == "flipbtn")  c = SSR_CMD_LINES_FLIP;
      else if(what == "spup")     c = SSR_CMD_SPEED_UP;
      else if(what == "spdn")     c = SSR_CMD_SPEED_DOWN;
      else if(what == "collapse") c = SSR_CMD_COLLAPSE;

      if(what == "openln")
        {
         if(m_port != NULL)
            PrintFormat("[panel] open from lines -> %s",
                        (m_port.OpenFromLines() ? "ok" : "refused"));
         return SSR_CMD_NONE;
        }

      if(c == SSR_CMD_NONE)
        {
         //--- the trade controls have no keyboard equivalent, so they
         //--- are not commands: they are buttons, handled here
         TradeButton(what);
         return SSR_CMD_NONE;
        }
      if(!Owns(c))
         return c;              // the host's dialog; it runs it
      Execute(c);
      return SSR_CMD_NONE;
     }

   //+------------------------------------------------------------------+
   //| Chart events. The host forwards them verbatim.                   |
   //+------------------------------------------------------------------+
   bool              OnEvent(const int id, const long &lparam,
                             const double &dparam, const string &sparam)
     {
      if(id == CHARTEVENT_KEYDOWN)
        {
         ENUM_SSR_CMD c = SSRKeyToCommand(lparam);
         if(c == SSR_CMD_NONE)
            return false;

         //+------------------------------------------------------------------+
         //| CLAIMING AN EVENT YOU CANNOT ACT ON IS HOW A KEY DIES.           |
         //|                                                                  |
         //| This returned true for EVERY mapped key, including the ones the  |
         //| panel does not implement. The host checks the panel first and    |
         //| returns when it says "handled", so S and J were swallowed here   |
         //| and the two dialogs they open were never reached. The keys were  |
         //| not broken and the dialogs were not broken - the panel was       |
         //| answering mail addressed to someone else.                        |
         //+------------------------------------------------------------------+
         if(!Owns(c))
            return false;

         Execute(c);
         Render();
         return true;
        }

      //--- CHARTEVENT_OBJECT_CLICK is deliberately not handled here.
      //--- PollClicks is the ONE mechanism, so that a panel on the
      //--- replay chart and a panel on this one behave identically
      //--- rather than through two paths, one of which stops being
      //--- maintained.

      //--- dragging: the panel by its caption, the thumb along its groove
      if(id == CHARTEVENT_MOUSE_MOVE)
        {
         int mx = (int)lparam;
         int my = (int)dparam;
         //--- sparam carries mouse buttons AND the modifier keys, so a
         //--- bare non-zero test starts a drag whenever Shift is held.
         //--- Bit 1 is the left button; nothing else counts.
         bool down = ((StringToInteger(sparam) & 1) != 0);

         //--- the trackbar first: it sits inside the panel body, so the
         //--- caption test below must not get the chance to claim it
         if(down && !m_track_drag && !m_dragging && !m_collapsed &&
            OnTrack(mx, my))
           {
            m_track_drag = true;
            ChartSetInteger(m_chart, CHART_MOUSE_SCROLL, false);
            SpeedFromPixel(mx);
            Render();
            return true;
           }
         if(m_track_drag && down)
           {
            SpeedFromPixel(mx);
            RenderDragging();
            return true;
           }
         if(m_track_drag && !down)
           {
            m_track_drag = false;
            ChartSetInteger(m_chart, CHART_MOUSE_SCROLL, m_saved_mouse_scroll);
            Render();          // never thinned: this is the resting frame
            return true;
           }

         if(down && !m_dragging &&
            mx >= m_x && mx <= m_x + SSR_PANEL_W &&
            my >= m_y && my <= m_y + SSR_HEADER_H)
           {
            m_dragging = true;
            m_drag_dx  = mx - m_x;
            m_drag_dy  = my - m_y;
            //--- suspend chart scrolling so dragging the panel does not
            //--- drag the price behind it
            ChartSetInteger(m_chart, CHART_MOUSE_SCROLL, false);
            return true;
           }
         if(m_dragging && down)
           {
            m_x = mx - m_drag_dx;
            m_y = my - m_drag_dy;
            if(m_x < 0) m_x = 0;
            if(m_y < 0) m_y = 0;
            RenderDragging();
            return true;
           }
         if(m_dragging && !down)
           {
            m_dragging = false;
            ChartSetInteger(m_chart, CHART_MOUSE_SCROLL, m_saved_mouse_scroll);
            Render();          // never thinned: this is the resting frame
            return true;
           }
        }
      return false;
     }

   void              StateInto(SSRUiState &out) { out = m_state; }
  };

#endif // SSR_PANEL_MQH
//+------------------------------------------------------------------+

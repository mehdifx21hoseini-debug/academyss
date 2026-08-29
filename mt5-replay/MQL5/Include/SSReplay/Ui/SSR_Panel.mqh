//+------------------------------------------------------------------+
//|                                                    SSR_Panel.mqh |
//|                             SS Replay - The Replay Panel (UI)    |
//|                                                                  |
//|  A view over SSRUiState and a sender of commands. That is all.   |
//|  It never touches the controller, never reads the clock, never   |
//|  decides what a state means - it renders what the port hands it  |
//|  and forwards what the user pressed.                             |
//|                                                                  |
//|  It runs inside an indicator, so it may not sleep and must stay  |
//|  cheap: rendering only touches objects whose text actually       |
//|  changed, because rewriting twenty labels sixty times a second   |
//|  is how a panel makes a terminal feel slow.                      |
//+------------------------------------------------------------------+
#ifndef SSR_PANEL_MQH
#define SSR_PANEL_MQH

#include "../Common/SSR_Types.mqh"
#include "../Common/SSR_Time.mqh"
#include "SSR_Theme.mqh"
#include "SSR_Widgets.mqh"
#include "SSR_ReplayPort.mqh"
#include "SSR_Keys.mqh"

//+------------------------------------------------------------------+
class CSSRPanel
  {
private:
   long              m_chart;
   CSSRWidgets       m_w;
   CSSRReplayPort   *m_port;        // not owned
   string            m_prefix;

   int               m_x, m_y;
   bool              m_collapsed;
   bool              m_dragging;
   int               m_drag_dx, m_drag_dy;

   SSRUiState        m_state;
   string            m_cache[32];   // last text written per slot
   int               m_renders;
   int               m_writes;

   //--- write only when the text actually changed
   void              Text(const int slot, const string id, const int x, const int y,
                          const string text, const color col,
                          const int size = SSR_FS_BODY, const string font = SSR_FONT)
     {
      if(slot >= 0 && slot < 32 && m_cache[slot] == text && m_w.Exists(id))
        {
         ObjectSetInteger(m_chart, m_w.N(id), OBJPROP_COLOR, col);
         return;
        }
      m_w.Label(id, x, y, text, col, size, font);
      m_writes++;
      if(slot >= 0 && slot < 32)
         m_cache[slot] = text;
     }

   void              ClearCache(void)
     {
      for(int i = 0; i < 32; i++)
         m_cache[i] = "\x01";     // a value no label can legitimately hold
     }

public:
                     CSSRPanel(void)
     : m_chart(0), m_port(NULL), m_prefix("SSRP_"),
       m_x(12), m_y(24), m_saved_mouse_move(0), m_saved_mouse_scroll(1),
       m_saved(false), m_collapsed(false), m_dragging(false),
       m_drag_dx(0), m_drag_dy(0), m_renders(0), m_writes(0)
     { m_state.Init(); ClearCache(); }

                    ~CSSRPanel(void) { Destroy(); }

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
         m_saved = true;
        }
      ChartSetInteger(m_chart, CHART_EVENT_MOUSE_MOVE, true);
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
         m_saved = false;
        }
      m_dragging = false;
     }

   void              SetPosition(const int x, const int y) { m_x = x; m_y = y; Render(); }
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

      int W = SSR_PANEL_W;
      int H = m_collapsed ? SSR_HEADER_H + 2 : SSR_PANEL_H;
      int x = m_x, y = m_y;

      m_w.Rect("bg", x, y, W, H, SSR_C_PANEL, SSR_C_PANEL_EDGE);
      m_w.Rect("hdr", x + 1, y + 1, W - 2, SSR_HEADER_H, SSR_C_HEADER, SSR_C_HEADER);
      Text(0, "title", x + SSR_PAD, y + 5, "SS REPLAY", SSR_C_ACCENT, SSR_FS_TITLE);
      m_w.Button("collapse", x + W - 24, y + 3, 18, SSR_HEADER_H - 5,
                 m_collapsed ? "+" : "-");

      if(m_collapsed)
        {
         HideBody(true);
         return;
        }
      HideBody(false);

      int cy = y + SSR_HEADER_H + SSR_GAP;

      //--- identity and status ---------------------------------------
      Text(1, "sym", x + SSR_PAD, cy,
           (m_state.symbol == "" ? "no session" : m_state.symbol),
           SSR_C_TEXT_DIM, SSR_FS_SMALL, SSR_FONT_MONO);
      Text(2, "status", x + W - SSR_PAD - 62, cy,
           SSRStateName(m_state.status), SSRStateColor(m_state.status), SSR_FS_SMALL);
      //--- BLIND is a badge, not a silence. A trader who forgot they
      //--- turned it on would read the masked clock as a broken one.
      Text(20, "blind", x + W - SSR_PAD - 120, cy,
           (m_state.blind ? "BLIND" : ""), SSR_C_ACCENT, SSR_FS_SMALL);
      cy += SSR_ROW_H - 4;

      //--- the clock: the single most-read thing on the panel.
      //---
      //--- THE TEXT COMES FROM THE PORT, already masked if the session
      //--- is blind. A panel formatting the instant itself would be a
      //--- second place that has to know about blind mode - and the
      //--- one that gets forgotten, printing the date the mode exists
      //--- to hide in the largest font on the screen.
      Text(3, "clock", x + SSR_PAD, cy,
           (m_state.clock_text == "" ? "--" : m_state.clock_text),
           (m_state.blind ? SSR_C_ACCENT : SSR_C_TEXT),
           SSR_FS_CLOCK, SSR_FONT_MONO);
      cy += 26;

      //--- progress ---------------------------------------------------
      m_w.Progress("prog", x + SSR_PAD, cy, W - 2 * SSR_PAD, 6,
                   m_state.progress, SSRStateColor(m_state.status));
      cy += 12;
      Text(4, "progtxt", x + SSR_PAD, cy,
           StringFormat("%.1f%%   %s left", m_state.progress * 100.0,
                        SSRFormatSpan(m_state.end_msc > m_state.now_msc
                                      ? m_state.end_msc - m_state.now_msc : 0)),
           SSR_C_TEXT_FAINT, SSR_FS_SMALL, SSR_FONT_MONO);
      cy += SSR_ROW_H;

      //--- transport ---------------------------------------------------
      int bw = (W - 2 * SSR_PAD - 4 * 3) / 5;
      int bx = x + SSR_PAD;
      m_w.Button("back",  bx, cy, bw, SSR_BTN_H, "|<", false, m_state.CanStep());
      bx += bw + 3;
      m_w.Button("play",  bx, cy, bw, SSR_BTN_H, "PLAY",
                 m_state.IsRunning(), m_state.CanPlay() || m_state.IsRunning());
      bx += bw + 3;
      m_w.Button("pause", bx, cy, bw, SSR_BTN_H, "II", false, m_state.IsRunning());
      bx += bw + 3;
      m_w.Button("step",  bx, cy, bw, SSR_BTN_H, ">|", false, m_state.CanStep());
      bx += bw + 3;
      m_w.Button("reset", bx, cy, bw, SSR_BTN_H, "RST");
      cy += SSR_BTN_H + SSR_GAP;

      //--- speed --------------------------------------------------------
      Text(5, "speedlbl", x + SSR_PAD, cy + 5, "SPEED", SSR_C_TEXT_DIM, SSR_FS_SMALL);
      m_w.Button("spdn", x + W - SSR_PAD - 92, cy, 22, SSR_ROW_H, "-");
      Text(6, "speedval", x + W - SSR_PAD - 62, cy + 4,
           SSRSpeedName(m_state.speed_x100), SSR_C_TEXT, SSR_FS_BODY, SSR_FONT_MONO);
      m_w.Button("spup", x + W - SSR_PAD - 22, cy, 22, SSR_ROW_H, "+");
      m_w.Button("follow", x + SSR_PAD + 46, cy, 40, SSR_ROW_H, "FOL");
      cy += SSR_ROW_H + 4;

      //--- fidelity. Colour-coded because the user must be able to see
      //--- at a glance that they are watching approximated ticks.
      Text(7, "fidlbl", x + SSR_PAD, cy, "FIDELITY", SSR_C_TEXT_DIM, SSR_FS_SMALL);
      //--- show what is RUNNING, not what was asked for. A tool that
      //--- displays the request while emitting something else is the
      //--- quiet dishonesty this whole product exists to avoid.
      bool degraded = (m_state.fidelity_effective != m_state.fidelity);
      Text(8, "fidval", x + W - SSR_PAD - 92, cy,
           SSRFidelityName(m_state.fidelity_effective) + (degraded ? " *" : ""),
           SSRFidelityColor(m_state.fidelity_effective), SSR_FS_SMALL);
      cy += SSR_ROW_H - 4;

      Text(9, "datalbl", x + SSR_PAD, cy, "DATA", SSR_C_TEXT_DIM, SSR_FS_SMALL);
      Text(10, "dataval", x + W - SSR_PAD - 92, cy,
           SSRDataModeName(m_state.data_mode), SSR_C_TEXT_DIM, SSR_FS_SMALL);
      cy += SSR_ROW_H - 4;

      Text(11, "tickslbl", x + SSR_PAD, cy, "TICKS", SSR_C_TEXT_DIM, SSR_FS_SMALL);
      Text(12, "ticksval", x + W - SSR_PAD - 92, cy,
           //--- an uncalibrated engine says so rather than showing a zero
           //--- that looks like a measurement
           (m_state.perf_calibrated
            ? StringFormat("%d  %.0fus/tk", (int)m_state.ticks_emitted,
                           m_state.us_per_tick)
            : IntegerToString(m_state.ticks_emitted)),
           SSR_C_TEXT_DIM, SSR_FS_SMALL, SSR_FONT_MONO);
      cy += SSR_ROW_H - 2;

      //--- warnings. The panel is loud when something is wrong and
      //--- silent when nothing is, which is the only honest split.
      string warn = "";
      color  wcol = SSR_C_STOP;
      if(m_state.last_error != SSR_OK)
         warn = SSRErrName(m_state.last_error);
      //--- WHY IT STOPPED, ahead of everything except an outright
      //--- error. A tool that pauses itself and says nothing is
      //--- indistinguishable from one that froze.
      else if(m_state.pause_reason != "")
        {
         warn = m_state.pause_reason;
         wcol = SSR_C_HOLD;
        }
      //--- and a board that has drifted must never look aligned
      else if(m_state.skew_msc != 0)
         warn = StringFormat("streams %I64dms apart", m_state.skew_msc);
      else if(!m_state.leak_clean)
         warn = m_state.leak_advice;
      else if(m_state.ticks_rejected > 0)
        {
         warn = StringFormat("%d ticks refused by terminal", (int)m_state.ticks_rejected);
         wcol = SSR_C_HOLD;
        }
      else if(m_state.fidelity_note != "")
        {
         warn = m_state.fidelity_note;
         wcol = SSR_C_HOLD;
        }
      else if(m_state.guard_violations > 0)
        {
         warn = StringFormat("%d future reads blocked", (int)m_state.guard_violations);
         wcol = SSR_C_HOLD;
        }
      Text(13, "warn", x + SSR_PAD, cy, warn, wcol, SSR_FS_SMALL);
      cy += SSR_ROW_H - 4;

      //================================================================
      //  TRADING
      //
      //  Risk and stop first, buttons second. That order is the point:
      //  the size follows from the two numbers above it, and a trader
      //  who has not set them gets a refusal with a reason rather than
      //  a trade at some default nobody chose.
      //================================================================
      Text(21, "acct", x + SSR_PAD, cy,
           (m_state.can_trade
            ? StringFormat("%.2f  %s%.2f  %d open",
                           m_state.balance,
                           (m_state.floating >= 0.0 ? "+" : ""),
                           m_state.floating, m_state.open_positions)
            : "no account"),
           (m_state.floating < 0.0 ? SSR_C_STOP : SSR_C_TEXT_DIM),
           SSR_FS_SMALL, SSR_FONT_MONO);
      cy += SSR_ROW_H - 6;

      //--- which instrument the buttons act on. On a multi-symbol
      //--- board the account follows the primary stream only, and
      //--- saying so is the difference between a limitation and a trap.
      Text(22, "tsym", x + SSR_PAD, cy,
           (m_state.streams > 1 && m_state.trade_symbol != ""
            ? "trades: " + m_state.trade_symbol
            : ""),
           SSR_C_TEXT_FAINT, SSR_FS_SMALL, SSR_FONT_MONO);
      cy += (m_state.streams > 1 ? SSR_ROW_H - 6 : 0);

      Text(23, "risklbl", x + SSR_PAD, cy + 4,
           StringFormat("RISK %.2f%%", m_state.risk_percent),
           SSR_C_TEXT_DIM, SSR_FS_SMALL);
      m_w.Button("riskdn", x + W - SSR_PAD - 46, cy, 20, SSR_ROW_H - 2, "-");
      m_w.Button("riskup", x + W - SSR_PAD - 22, cy, 20, SSR_ROW_H - 2, "+");
      cy += SSR_ROW_H - 2;

      Text(24, "stoplbl", x + SSR_PAD, cy + 4,
           //--- a stop of zero is not a stop, and the panel says so
           //--- in the label rather than only when a button is pressed
           (m_state.stop_points > 0.0
            ? StringFormat("STOP %.0f pts", m_state.stop_points)
            : "STOP not set"),
           (m_state.stop_points > 0.0 ? SSR_C_TEXT_DIM : SSR_C_HOLD),
           SSR_FS_SMALL);
      m_w.Button("stopdn", x + W - SSR_PAD - 46, cy, 20, SSR_ROW_H - 2, "-");
      m_w.Button("stopup", x + W - SSR_PAD - 22, cy, 20, SSR_ROW_H - 2, "+");
      cy += SSR_ROW_H;

      bool armed = (m_state.can_trade && m_state.stop_points > 0.0);
      int  tw = (W - 2 * SSR_PAD - 3 * 3) / 4;
      int  tx = x + SSR_PAD;
      m_w.Button("buy",  tx, cy, tw, SSR_BTN_H, "BUY",  false, armed);
      tx += tw + 3;
      m_w.Button("sell", tx, cy, tw, SSR_BTN_H, "SELL", false, armed);
      tx += tw + 3;
      m_w.Button("be",   tx, cy, tw, SSR_BTN_H, "B/E",  false,
                 m_state.open_positions > 0);
      tx += tw + 3;
      m_w.Button("flat", tx, cy, tw, SSR_BTN_H, "FLAT", false,
                 m_state.open_positions > 0);
      cy += SSR_BTN_H + 2;

      //--- what the last trade attempt said. Loud, because a refused
      //--- order that says nothing looks like a broken button.
      Text(25, "traderr", x + SSR_PAD, cy,
           (m_port != NULL ? m_port.TradeError() : ""),
           SSR_C_HOLD, SSR_FS_SMALL);
      cy += SSR_ROW_H - 6;

      //--- and what the strategies are doing, if any are
      Text(26, "strat", x + SSR_PAD, cy, m_state.strategy_text,
           SSR_C_TEXT_FAINT, SSR_FS_SMALL);
      cy += (m_state.strategy_text == "" ? 0 : SSR_ROW_H - 6);

      Text(14, "keys", x + SSR_PAD, cy, "SPACE  <->  PgUp/Dn  J  B  +/-",
           SSR_C_TEXT_FAINT, SSR_FS_SMALL, SSR_FONT_MONO);
     }

   void              HideBody(const bool hidden)
     {
      string ids[] = {"sym","status","clock","prog_bg","prog_fill","progtxt",
                      "play","pause","step","follow","reset",
                      "speedlbl","spdn","speedval","spup",
                      "fidlbl","fidval","datalbl","dataval",
                      "tickslbl","ticksval","warn","keys",
                      "blind","acct","tsym","risklbl","riskdn","riskup",
                      "stoplbl","stopdn","stopup",
                      "buy","sell","be","flat","traderr","strat"};
      for(int i = 0; i < ArraySize(ids); i++)
         m_w.Hide(ids[i], hidden);
     }

   //+------------------------------------------------------------------+
   //| One path for both a click and a key press.                       |
   //+------------------------------------------------------------------+
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
      if(id == "stopdn") return m_port.SetStopPoints(StepStop(-1));
      if(id == "stopup") return m_port.SetStopPoints(StepStop(+1));
      return false;
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

   double            StepStop(const int dir)
     {
      double s = m_state.stop_points;
      //--- coarser as it grows, so 10 -> 20 costs one press and
      //--- 500 -> 600 does not cost fifty
      double step = (s < 50.0 ? 5.0 : (s < 200.0 ? 10.0 : 50.0));
      s += dir * step;
      if(s < 0.0)
         s = 0.0;
      return s;
     }

   bool              Execute(const ENUM_SSR_CMD cmd)
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
         Execute(c);
         Render();
         return true;
        }

      if(id == CHARTEVENT_OBJECT_CLICK)
        {
         if(StringFind(sparam, m_prefix) != 0)
            return false;
         string what = StringSubstr(sparam, StringLen(m_prefix));

         ENUM_SSR_CMD c = SSR_CMD_NONE;
         if(what == "play")          c = SSR_CMD_PLAY;
         else if(what == "pause")    c = SSR_CMD_PAUSE;
         else if(what == "step")     c = SSR_CMD_STEP_FWD;
         else if(what == "back")     c = SSR_CMD_STEP_BACK;
         else if(what == "reset")    c = SSR_CMD_RESET;
         else if(what == "follow")   c = SSR_CMD_FOLLOW;
         else if(what == "spup")     c = SSR_CMD_SPEED_UP;
         else if(what == "spdn")     c = SSR_CMD_SPEED_DOWN;
         else if(what == "collapse") c = SSR_CMD_COLLAPSE;

         if(c != SSR_CMD_NONE)
            Execute(c);
         else
            //--- the trade controls have no keyboard equivalent, so
            //--- they are not commands: they are buttons, handled here
            TradeButton(what);

         //--- MetaTrader latches the button down; release it either way
         ObjectSetInteger(m_chart, sparam, OBJPROP_STATE, false);
         Render();
         return true;
        }

      //--- dragging by the header strip
      if(id == CHARTEVENT_MOUSE_MOVE)
        {
         int mx = (int)lparam;
         int my = (int)dparam;
         //--- sparam carries mouse buttons AND the modifier keys, so a
         //--- bare non-zero test starts a drag whenever Shift is held.
         //--- Bit 1 is the left button; nothing else counts.
         bool down = ((StringToInteger(sparam) & 1) != 0);

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
            Render();
            return true;
           }
         if(m_dragging && !down)
           {
            m_dragging = false;
            ChartSetInteger(m_chart, CHART_MOUSE_SCROLL, m_saved_mouse_scroll);
            return true;
           }
        }
      return false;
     }

   void              StateInto(SSRUiState &out) { out = m_state; }
  };

#endif // SSR_PANEL_MQH
//+------------------------------------------------------------------+

//+------------------------------------------------------------------+
//|                                               SSR_RevealCard.mqh |
//|                      SS Replay - the end of a blind session       |
//|                                                                  |
//|  WHY A CARD AND NOT A RESTORE                                    |
//|                                                                  |
//|  Blind mode hides the instrument, the dates, and optionally the   |
//|  price level, so a trader practises reading structure instead of  |
//|  reading a label. It has worked since Phase 8 and it has always   |
//|  ended the same way: the chart was restored when the expert was   |
//|  REMOVED. Nothing marked the moment.                             |
//|                                                                  |
//|  That is a training feature with no feedback loop. Practice       |
//|  without a reveal is practice you cannot check, and a trader who  |
//|  wants to know what they were actually looking at has to end the  |
//|  whole session to find out - by which point the chart, the        |
//|  positions and the reasoning have all gone.                      |
//|                                                                  |
//|  So the session finishes, the market STAYS hidden, and a card     |
//|  says so with the one button that lifts it. The reveal is a       |
//|  deliberate act, at a moment the trader chose.                    |
//|                                                                  |
//|  IT IS NOT A TRAP. OnDeinit still restores every chart whatever   |
//|  happened here - a user who closes the terminal mid-card gets     |
//|  their settings back exactly as before. This card decides WHEN    |
//|  the reveal happens, never WHETHER.                              |
//+------------------------------------------------------------------+
#ifndef SSR_REVEAL_CARD_MQH
#define SSR_REVEAL_CARD_MQH

#include "SSR_Theme.mqh"
#include "SSR_Strings.mqh"
#include "SSR_Widgets.mqh"

#define SSR_REVEAL_W  360
#define SSR_REVEAL_H  132

class CSSRRevealCard
  {
private:
   CSSRWidgets       m_w;
   long              m_chart;
   bool              m_up;
   string            m_headline;

public:
                     CSSRRevealCard(void)
     : m_chart(0), m_up(false), m_headline("") {}
                    ~CSSRRevealCard(void) { Hide(); }

   bool              IsUp(void) { return m_up; }

   //+------------------------------------------------------------------+
   //| `headline` is whatever the session can honestly say about itself  |
   //| at this point - trades and net, typically. It is passed IN rather |
   //| than computed here, because a card that reached into the          |
   //| statistics would be a second place that decides what a session    |
   //| result means.                                                     |
   //+------------------------------------------------------------------+
   bool              Show(const long chart_id, const string headline)
     {
      if(chart_id == 0)
         return false;
      m_chart    = chart_id;
      m_headline = headline;
      m_w.Attach(chart_id, "SSRV_");
      m_w.RemoveAll();
      m_up = true;
      Render();
      return true;
     }

   void              Render(void)
     {
      if(!m_up || m_chart == 0)
         return;

      int cw = (int)ChartGetInteger(m_chart, CHART_WIDTH_IN_PIXELS);
      int ch = (int)ChartGetInteger(m_chart, CHART_HEIGHT_IN_PIXELS);
      int x  = (cw > SSR_REVEAL_W ? (cw - SSR_REVEAL_W) / 2 : 8);
      int y  = (ch > SSR_REVEAL_H * 2 ? ch / 3 : 12);

      m_w.Rect("bg", x, y, SSR_REVEAL_W, SSR_REVEAL_H,
               SSR_C_PANEL, SSR_C_PANEL_EDGE);
      m_w.Rect("hdr", x + 1, y + 1, SSR_REVEAL_W - 2, SSR_HEADER_H,
               SSR_C_HEADER, SSR_C_GROUP_EDGE);
      m_w.Label("title", x + 12, y + 5, T(SSR_S_SESSION_COMPLETE),
                SSR_C_TEXT, SSR_FS_TITLE);
      m_w.Chip("chip", x + SSR_REVEAL_W - 58, y + 4, T(SSR_S_BLIND),
               SSR_C_HOLD, SSR_C_WELL);

      m_w.Label("l1", x + 12, y + 34,
                T(SSR_S_STILL_HIDDEN), SSR_C_TEXT, SSR_FS_BODY);

      //--- what the session did, in the words of whoever counted it
      if(m_headline != "")
         m_w.Label("l2", x + 12, y + 52, m_headline,
                   SSR_C_TEXT_DIM, SSR_FS_BODY);
      else
         m_w.Remove("l2");

      m_w.Label("l3", x + 12, y + 72,
                T(SSR_S_REVEAL_EXPLAIN_1),
                SSR_C_TEXT_DIM, SSR_FS_SMALL);
      m_w.Label("l4", x + 12, y + 84,
                T(SSR_S_REVEAL_EXPLAIN_2),
                SSR_C_TEXT_DIM, SSR_FS_SMALL);

      m_w.ButtonC("reveal", x + 12, y + SSR_REVEAL_H - 34,
                  SSR_REVEAL_W - 24, 26, T(SSR_S_REVEAL_BUTTON),
                  SSR_C_PRIMARY, SSR_C_PRIMARY_EDGE, SSR_C_PRIMARY_TEXT,
                  SSR_FS_TITLE);

      ChartRedraw(m_chart);
     }

   //--- true once, on the press. The caller does the revealing: this
   //--- class draws a question and never answers it itself.
   bool              Poll(void)
     {
      if(!m_up)
         return false;
      if(!m_w.Pressed("reveal"))
         return false;
      Hide();
      return true;
     }

   void              Hide(void)
     {
      if(!m_up)
         return;
      m_w.RemoveAll();
      m_up = false;
      if(m_chart != 0)
         ChartRedraw(m_chart);
     }
  };

#endif // SSR_REVEAL_CARD_MQH
//+------------------------------------------------------------------+

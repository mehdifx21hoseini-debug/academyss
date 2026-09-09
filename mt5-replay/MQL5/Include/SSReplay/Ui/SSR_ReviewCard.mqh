//+------------------------------------------------------------------+
//|                                               SSR_ReviewCard.mqh |
//|                     SS Replay - the session, after the session    |
//|                                                                  |
//|  A MODAL, BECAUSE THIS IS CONSULTED AND NOT OPERATED.            |
//|                                                                  |
//|  The rule this product settled on in v98: the panel holds what    |
//|  you OPERATE, a modal holds what you CONSULT. Forty-three         |
//|  measures are the definition of consulted, and they will not fit  |
//|  in a 186 px sheet at any density worth reading.                  |
//|                                                                  |
//|  PAGED, BECAUSE MQL5 CANNOT CLIP.                                |
//|                                                                  |
//|  There is no scrollbar and no clipping rectangle. A list that     |
//|  drew all its rows would paint the surplus over the chart, so it  |
//|  draws a WINDOW onto them and this card pages it - which is       |
//|  exactly what the List primitive from Phase 2 was built for.      |
//|                                                                  |
//|  IT COMPUTES NOTHING AND INTERPRETS NOTHING. Rows and sentences   |
//|  arrive from SSR_Review.mqh, which got them from the statistics   |
//|  engine. This file decides where they sit.                        |
//+------------------------------------------------------------------+
#ifndef SSR_REVIEW_CARD_MQH
#define SSR_REVIEW_CARD_MQH

#include "SSR_Theme.mqh"
#include "SSR_Widgets.mqh"
#include "SSR_Review.mqh"
#include "SSR_Keys.mqh"

#define SSR_RV_W      520
#define SSR_RV_ROW_H  17
#define SSR_RV_SHOWN  12

class CSSRReviewCard
  {
private:
   CSSRWidgets       m_w;
   long              m_chart;
   bool              m_up;

   SSRReviewRow      m_rows[];
   int               m_n;
   int               m_first;
   string            m_obs[];
   int               m_obs_n;
   SSRStatistics     m_st;

   int               m_x, m_y;

public:
                     CSSRReviewCard(void)
     : m_chart(0), m_up(false), m_n(0), m_first(0), m_obs_n(0),
       m_x(0), m_y(0) {}
                    ~CSSRReviewCard(void) { Hide(); }

   bool              IsUp(void)    { return m_up; }
   int               Rows(void)    { return m_n; }
   int               Observations(void) { return m_obs_n; }
   int               First(void)   { return m_first; }

   //--- read-only seam: the smoke test cannot read a chart label, but
   //--- it can ask what the card believes it is showing
   string            RowAt(const int i)
     {
      if(i < 0 || i >= m_n)
         return "";
      return SSRReviewLine(m_rows[i]);
     }
   string            ObservationAt(const int i)
     {
      if(i < 0 || i >= m_obs_n)
         return "";
      return m_obs[i];
     }

   bool              Show(const long chart_id, const SSRStatistics &st)
     {
      if(chart_id == 0)
         return false;
      m_chart = chart_id;
      m_st    = st;
      m_w.Attach(chart_id, "SSRR2_");
      m_w.RemoveAll();

      m_n     = SSRReviewRows(m_st, m_rows);
      m_obs_n = SSRReviewObservations(m_st, m_obs);
      m_first = 0;
      m_up    = true;
      Render();
      return true;
     }

   void              Page(const int delta)
     {
      m_first += delta * SSR_RV_SHOWN;
      if(m_first > m_n - SSR_RV_SHOWN) m_first = m_n - SSR_RV_SHOWN;
      if(m_first < 0)                  m_first = 0;
     }

   void              Render(void)
     {
      if(!m_up || m_chart == 0)
         return;

      int obs_h = (m_obs_n > 0 ? 18 + m_obs_n * 14 : 0);
      int h     = 26 + 46 + SSR_RV_SHOWN * SSR_RV_ROW_H + 10 + obs_h + 34;

      int cw = (int)ChartGetInteger(m_chart, CHART_WIDTH_IN_PIXELS);
      int ch = (int)ChartGetInteger(m_chart, CHART_HEIGHT_IN_PIXELS);
      m_x = (cw > SSR_RV_W ? (cw - SSR_RV_W) / 2 : 8);
      m_y = (ch > h + 40 ? (ch - h) / 2 : 8);

      m_w.Rect("bg", m_x, m_y, SSR_RV_W, h, SSR_C_PANEL, SSR_C_PANEL_EDGE);
      m_w.Rect("hdr", m_x + 1, m_y + 1, SSR_RV_W - 2, SSR_HEADER_H,
               SSR_C_HEADER, SSR_C_GROUP_EDGE);
      m_w.Label("title", m_x + 12, m_y + 5, "SESSION REVIEW",
                SSR_C_TEXT, SSR_FS_TITLE);

      //+------------------------------------------------------------------+
      //| THE HEADLINE. Four numbers, because a trader who reads nothing   |
      //| else on this card should still leave with the shape of the       |
      //| session. Net is coloured; the rest are not, so the one that       |
      //| carries a verdict is the only one that looks like it does.        |
      //+------------------------------------------------------------------+
      int hy = m_y + 30;
      m_w.Label("h1", m_x + 12, hy,
                StringFormat("%.2f R", m_st.total_r),
                (m_st.total_r >= 0.0 ? SSR_C_RUN : SSR_C_STOP), SSR_FS_CLOCK);
      m_w.Label("h2", m_x + 120, hy + 4,
                StringFormat("%d trades", m_st.trades),
                SSR_C_TEXT, SSR_FS_BODY);
      m_w.Label("h3", m_x + 210, hy + 4,
                StringFormat("%.0f%% won", m_st.win_rate),
                SSR_C_TEXT, SSR_FS_BODY);
      m_w.Label("h4", m_x + 300, hy + 4,
                StringFormat("max DD %.2f", m_st.max_drawdown),
                SSR_C_TEXT_DIM, SSR_FS_BODY);
      m_w.Label("h5", m_x + 420, hy + 4,
                StringFormat("net %.2f", m_st.net_profit),
                (m_st.net_profit >= 0.0 ? SSR_C_RUN : SSR_C_STOP),
                SSR_FS_BODY);

      //--- every measure, a page at a time
      string lines[];
      ArrayResize(lines, m_n);
      string group = "";
      for(int i = 0; i < m_n; i++)
        {
         //--- the group name rides on its first row rather than taking a
         //--- row of its own: a heading costs one of twelve visible lines
         string pre = "";
         if(m_rows[i].group != group)
           { group = m_rows[i].group; pre = "· "; }
         else
            pre = "  ";
         lines[i] = pre + SSRReviewLine(m_rows[i]);
        }

      int ly = m_y + 60;
      m_w.List("m", m_x + 12, ly, SSR_RV_W - 24, SSR_RV_ROW_H,
               lines, m_first, SSR_RV_SHOWN, -1);

      int py = ly + SSR_RV_SHOWN * SSR_RV_ROW_H + 6;
      m_w.Button("up",   m_x + SSR_RV_W - 96, py, 36, 18, "Up");
      m_w.Button("down", m_x + SSR_RV_W - 56, py, 36, 18, "Down");
      m_w.Label("count", m_x + 12, py + 3,
                StringFormat("%d - %d of %d measured",
                             m_first + 1,
                             (m_first + SSR_RV_SHOWN < m_n
                              ? m_first + SSR_RV_SHOWN : m_n), m_n),
                SSR_C_TEXT_FAINT, SSR_FS_SMALL);

      //+------------------------------------------------------------------+
      //| OBSERVATIONS, when there are any. A line absent because it had   |
      //| no samples is the point: "0 revenge trades" out of one trade is  |
      //| a sample size, not a clean sheet.                                 |
      //+------------------------------------------------------------------+
      int oy = py + 24;
      if(m_obs_n > 0)
        {
         m_w.Label("ohd", m_x + 12, oy, "WHAT WAS COUNTED",
                   SSR_C_TEXT_FAINT, SSR_FS_SMALL);
         for(int i = 0; i < 8; i++)
           {
            string oid = "o" + IntegerToString(i);
            if(i >= m_obs_n)
              { m_w.Remove(oid); continue; }
            m_w.Label(oid, m_x + 12, oy + 16 + i * 14, m_obs[i],
                      SSR_C_TEXT_DIM, SSR_FS_SMALL);
           }
         oy += 18 + m_obs_n * 14;
        }
      else
        {
         m_w.Remove("ohd");
         for(int i = 0; i < 8; i++)
            m_w.Remove("o" + IntegerToString(i));
        }

      m_w.Button("stmt",  m_x + 12, m_y + h - 28, 150, 20,
                 "Export the full statement");
      m_w.ButtonC("close", m_x + SSR_RV_W - 92, m_y + h - 28, 80, 20, "Close",
                  SSR_C_PRIMARY, SSR_C_PRIMARY_EDGE, SSR_C_PRIMARY_TEXT,
                  SSR_FS_BODY);

      ChartRedraw(m_chart);
     }

   //--- "" when nothing was pressed, else "close" or "stmt". Paging is
   //--- handled here because it changes nothing outside this card.
   string            Poll(void)
     {
      if(!m_up)
         return "";
      if(m_w.Pressed("up"))    { Page(-1); Render(); return ""; }
      if(m_w.Pressed("down"))  { Page(+1); Render(); return ""; }
      if(m_w.Pressed("stmt"))  { return "stmt"; }
      if(m_w.Pressed("close")) { Hide(); return "close"; }
      return "";
     }

   //+------------------------------------------------------------------+
   //| A MODAL EATS THE KEYBOARD, INCLUDING THE KEYS IT DOES NOT USE.   |
   //|                                                                  |
   //| Esc closes and the arrows page. Everything else returns true as   |
   //| well - swallowed, not forwarded - because a card that let Space   |
   //| through would start the replay running behind the thing the user  |
   //| is reading, and they would have no idea why the numbers on it     |
   //| had stopped matching the chart.                                   |
   //+------------------------------------------------------------------+
   bool              OnKey(const long key)
     {
      if(!m_up)
         return false;
      if(key == SSR_VK_ESCAPE) { Hide();             return true; }
      if(key == SSR_VK_UP)     { Page(-1); Render(); return true; }
      if(key == SSR_VK_DOWN)   { Page(+1); Render(); return true; }
      return true;
     }

   void              Hide(void)
     {
      if(!m_up)
         return;
      m_w.ListClear("m", SSR_RV_SHOWN);
      m_w.RemoveAll();
      m_up = false;
      if(m_chart != 0)
         ChartRedraw(m_chart);
     }
  };

#endif // SSR_REVIEW_CARD_MQH
//+------------------------------------------------------------------+

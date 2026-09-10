//+------------------------------------------------------------------+
//|                                                  SSR_Palette.mqh |
//|                        SS Replay - the one place to find anything |
//|                                                                  |
//|  HOW A COMMAND PALETTE IS POSSIBLE IN MQL5                       |
//|                                                                  |
//|  There is no overlay, no focus system and no key stream. There    |
//|  are three facts that add up to one anyway:                      |
//|                                                                  |
//|  1. OBJ_EDIT is a real text field. MetaTrader handles the typing; |
//|     we read what it holds. We cannot see keystrokes, so the query |
//|     is POLLED on the paint tick and re-filtered when it changes.  |
//|     At ten frames a second that is indistinguishable from live.   |
//|                                                                  |
//|  2. Creation order is z-order. Drawing the palette LAST on every  |
//|     frame is what puts it over the panel - the same mechanism the |
//|     v101 dropdowns and the key card already use.                  |
//|                                                                  |
//|  3. Buttons report their own presses. The result rows are buttons |
//|     and are polled exactly like every other control here.          |
//|                                                                  |
//|  WHAT IT DELIBERATELY DOES NOT DO                                |
//|                                                                  |
//|  It does not execute anything. It returns the chosen command to   |
//|  its owner, which dispatches it down a path that already existed  |
//|  before the palette did. A palette that ran commands itself would |
//|  be a second place where "close every position" is implemented,   |
//|  and the second place is the one that gets forgotten.             |
//+------------------------------------------------------------------+
#ifndef SSR_PALETTE_MQH
#define SSR_PALETTE_MQH

#include "SSR_Theme.mqh"
#include "SSR_Strings.mqh"
#include "SSR_Widgets.mqh"
#include "SSR_Command.mqh"

#define SSR_PAL_W        330
#define SSR_PAL_ROW_H    20
#define SSR_PAL_SHOWN    8      // rows on screen; the rest are paged

class CSSRPalette
  {
private:
   CSSRWidgets       m_w;
   long              m_chart;
   bool              m_up;
   int               m_x, m_y;

   SSRCommand        m_all[];
   int               m_hit[];         // indices into m_all that match
   int               m_n;             // how many matched
   int               m_first;         // top visible row
   int               m_sel;           // selected index INTO m_hit
   string            m_query;         // what the box held last paint

   string            QueryId(void)   { return "q"; }

public:
                     CSSRPalette(void)
     : m_chart(0), m_up(false), m_x(0), m_y(0), m_n(0), m_first(0),
       m_sel(0), m_query("") {}
                    ~CSSRPalette(void) { Hide(); }

   bool              IsUp(void)   { return m_up; }
   string            Query(void)  { return m_query; }
   int               Matches(void){ return m_n; }

   //--- read-only seams for the smoke test, which cannot type
   string            SelectedLabel(void)
     {
      if(m_sel < 0 || m_sel >= m_n)
         return "";
      return m_all[m_hit[m_sel]].label;
     }

   //+------------------------------------------------------------------+
   //| Open centred on the chart, because it is modal in intent even    |
   //| though MQL5 has no modality: while it is up, its owner stops     |
   //| handing keys to anything else.                                    |
   //+------------------------------------------------------------------+
   bool              Show(const long chart_id)
     {
      if(chart_id == 0)
         return false;
      m_chart = chart_id;
      m_w.Attach(chart_id, "SSRX_");
      m_w.RemoveAll();

      SSRCommands(m_all);
      m_query = "";
      m_first = 0;
      m_sel   = 0;
      Refilter();

      int cw = (int)ChartGetInteger(chart_id, CHART_WIDTH_IN_PIXELS);
      int ch = (int)ChartGetInteger(chart_id, CHART_HEIGHT_IN_PIXELS);
      m_x = (cw > SSR_PAL_W ? (cw - SSR_PAL_W) / 2 : 8);
      //--- a third of the way down, not centred: the rows grow
      //--- downwards and a centred box walks off the bottom as it fills
      m_y = (ch > 300 ? ch / 5 : 12);

      m_up = true;
      Render();
      return true;
     }

   void              Hide(void)
     {
      if(!m_up)
         return;
      m_w.ListClear("r", SSR_PAL_SHOWN);
      m_w.RemoveAll();
      m_up = false;
      if(m_chart != 0)
         ChartRedraw(m_chart);
     }

   bool              Toggle(const long chart_id)
     {
      if(m_up)
        { Hide(); return false; }
      return Show(chart_id);
     }

   //+------------------------------------------------------------------+
   //| Re-run the filter and keep the selection somewhere real.         |
   //+------------------------------------------------------------------+
   void              Refilter(void)
     {
      m_n = SSRCommandFilter(m_all, m_query, m_hit);
      if(m_sel >= m_n)   m_sel = m_n - 1;
      if(m_sel < 0)      m_sel = 0;
      if(m_first > m_sel)                  m_first = m_sel;
      if(m_sel >= m_first + SSR_PAL_SHOWN) m_first = m_sel - SSR_PAL_SHOWN + 1;
      if(m_first < 0)    m_first = 0;
     }

   //--- move the selection, paging the window with it
   void              Move(const int delta)
     {
      if(m_n <= 0)
         return;
      m_sel += delta;
      if(m_sel < 0)      m_sel = 0;
      if(m_sel >= m_n)   m_sel = m_n - 1;
      if(m_sel < m_first)                  m_first = m_sel;
      if(m_sel >= m_first + SSR_PAL_SHOWN) m_first = m_sel - SSR_PAL_SHOWN + 1;
     }

   //+------------------------------------------------------------------+
   //| Draw. Called LAST in the owner's paint, which is what puts it    |
   //| on top - creation order is the only z-order there is here.       |
   //+------------------------------------------------------------------+
   void              Render(void)
     {
      if(!m_up || m_chart == 0)
         return;

      //--- the query box first, so the field keeps the position it was
      //--- clicked at even as the list below it grows and shrinks
      m_w.Rect("bg", m_x - 6, m_y - 6, SSR_PAL_W + 12, 40,
               SSR_C_PANEL, SSR_C_PRIMARY_EDGE);
      m_w.Label("cap", m_x, m_y - 2, T(SSR_S_PAL_TITLE),
                SSR_C_TEXT_FAINT, SSR_FS_SMALL);
      m_w.Edit(QueryId(), m_x, m_y + 12, SSR_PAL_W, 20, m_query, false);

      //--- rows, drawn through the Phase 2 List primitive: a WINDOW on
      //--- the matches, because MQL5 cannot clip and the surplus would
      //--- otherwise be painted over the chart
      string rows[];
      int k = (m_n < SSR_PAL_SHOWN ? m_n : SSR_PAL_SHOWN);
      ArrayResize(rows, m_n);
      for(int i = 0; i < m_n; i++)
        {
         string key = SSRCommandKey(m_all[m_hit[i]]);
         rows[i] = m_all[m_hit[i]].label + (key == "" ? "" : "        " + key);
        }

      if(m_n > 0)
         m_w.List("r", m_x, m_y + 38, SSR_PAL_W, SSR_PAL_ROW_H,
                  rows, m_first, SSR_PAL_SHOWN, m_sel);
      else
        {
         //--- an empty state that teaches the next action rather than
         //--- saying "no results" and stopping
         m_w.ListClear("r", SSR_PAL_SHOWN);
         m_w.Rect("none_bg", m_x - 2, m_y + 36, SSR_PAL_W + 4, 24,
                  SSR_C_WELL, SSR_C_WELL_EDGE);
         m_w.Label("none", m_x + 8, m_y + 42,
                   T(SSR_S_PAL_NOTHING),
                   SSR_C_TEXT_DIM, SSR_FS_SMALL);
        }
      if(m_n > 0)
        { m_w.Remove("none_bg"); m_w.Remove("none"); }

      //--- the footer says how to drive it, because a palette nobody
      //--- knows how to leave is a modal nobody opens twice
      int fy = m_y + 38 + (m_n > 0 ? k * SSR_PAL_ROW_H : 24) + 4;
      string more = (m_n > SSR_PAL_SHOWN
                     ? StringFormat(T(SSR_S_PAL_OF), k, m_n) : "");
      m_w.Label("foot", m_x, fy,
                T(SSR_S_PAL_HINT) + more,
                SSR_C_TEXT_FAINT, SSR_FS_SMALL);

      ChartRedraw(m_chart);
     }

   //+------------------------------------------------------------------+
   //| Poll. Returns true when the caller should read Chosen().         |
   //|                                                                  |
   //| The query is polled rather than typed into us: MetaTrader owns   |
   //| the edit box and we cannot see the keystrokes. Comparing what it |
   //| holds against what it held is how the list keeps up.             |
   //+------------------------------------------------------------------+
   bool              Poll(void)
     {
      if(!m_up)
         return false;

      string now = m_w.EditText(QueryId());
      if(now != m_query)
        {
         m_query = now;
         m_first = 0;
         m_sel   = 0;
         Refilter();
         Render();
        }

      for(int i = 0; i < SSR_PAL_SHOWN; i++)
         if(m_w.Pressed("r" + IntegerToString(i)))
           {
            m_sel = m_first + i;
            if(m_sel >= m_n) m_sel = m_n - 1;
            return (m_sel >= 0);
           }
      return false;
     }

   //--- what was chosen. Exactly one of cmd/action is meaningful, and
   //--- both go down a path that existed before this file did.
   bool              Chosen(SSRCommand &out)
     {
      if(m_sel < 0 || m_sel >= m_n)
         return false;
      out = m_all[m_hit[m_sel]];
      return true;
     }

   //+------------------------------------------------------------------+
   //| Keys, while it is up. Returns true when the key was consumed.    |
   //| `run` is set when Enter chose something.                          |
   //+------------------------------------------------------------------+
   bool              OnKey(const long key, bool &run)
     {
      run = false;
      if(!m_up)
         return false;

      if(key == SSR_VK_ESCAPE)
        { Hide(); return true; }
      if(key == SSR_VK_ENTER)
        { run = (m_n > 0 && m_sel >= 0); if(!run) Hide(); return true; }
      if(key == SSR_VK_UP)
        { Move(-1); Render(); return true; }
      if(key == SSR_VK_DOWN)
        { Move(+1); Render(); return true; }
      return false;
     }
  };

#endif // SSR_PALETTE_MQH
//+------------------------------------------------------------------+

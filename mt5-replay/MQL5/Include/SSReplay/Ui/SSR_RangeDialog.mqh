//+------------------------------------------------------------------+
//|                                             SSR_RangeDialog.mqh  |
//|                    SS Replay - Session Range Selection (UI)      |
//|                                                                  |
//|  Where the user says WHEN, and is told what it will cost before  |
//|  anything is written.                                            |
//|                                                                  |
//|  The quote is the reason this exists. A user who picks daily     |
//|  context and then waits four minutes with no explanation decides |
//|  the tool is broken; the same wait, quoted and accepted, is just |
//|  a load. So the panel recomputes the estimate on every change and |
//|  the START button refuses a range the broker cannot serve.       |
//+------------------------------------------------------------------+
#ifndef SSR_RANGE_DIALOG_MQH
#define SSR_RANGE_DIALOG_MQH

#include "../Common/SSR_Types.mqh"
#include "../Common/SSR_Time.mqh"
#include "../Data/SSR_HistoryCatalog.mqh"
#include "../Data/SSR_SessionRange.mqh"
#include "SSR_Theme.mqh"
#include "SSR_Widgets.mqh"

#define SSR_DLG_W   248
#define SSR_DLG_H   214

//--- the timeframes offered as "deepest context I want"
#define SSR_DLG_TF_COUNT 4

//+------------------------------------------------------------------+
class CSSRRangeDialog
  {
private:
   long                m_chart;
   CSSRWidgets         m_w;
   string              m_prefix;
   bool                m_open;
   int                 m_x, m_y;

   SSRSessionRange     m_req;
   SSRSeedQuote        m_quote;
   string              m_problem;
   CSSRHistoryCatalog *m_cat;      // not owned
   bool                m_confirmed;

   ENUM_TIMEFRAMES     TfAt(const int i)
     {
      switch(i)
        {
         case 0: return PERIOD_M15;
         case 1: return PERIOD_H1;
         case 2: return PERIOD_H4;
         case 3: return PERIOD_D1;
        }
      return PERIOD_H1;
     }
   string              TfName(const int i)
     {
      switch(i)
        {
         case 0: return "M15";
         case 1: return "H1";
         case 2: return "H4";
         case 3: return "D1";
        }
      return "H1";
     }

public:
                     CSSRRangeDialog(void)
     : m_chart(0), m_prefix("SSRD_"), m_open(false),
       m_x(260), m_y(24), m_cat(NULL), m_confirmed(false)
     { m_req.Init(); m_quote.Init(); m_problem = ""; }

                    ~CSSRRangeDialog(void) { Destroy(); }

   void              Create(const long chart_id, CSSRHistoryCatalog *cat,
                            const string prefix = "SSRD_")
     {
      m_chart  = chart_id;
      m_cat    = cat;
      m_prefix = prefix;
      m_w.Attach(chart_id, prefix);
      m_w.RemoveAll();
     }

   void              Destroy(void) { if(m_chart != 0) m_w.RemoveAll(); }

   bool              IsOpen(void)      { return m_open; }
   bool              IsConfirmed(void) { return m_confirmed; }
   void              RequestInto(SSRSessionRange &out) { out = m_req; }
   void              QuoteInto(SSRSeedQuote &out)      { out = m_quote; }
   string            Problem(void)     { return m_problem; }

   //+------------------------------------------------------------------+
   void              Open(SSRSessionRange &seed)
     {
      m_req       = seed;
      m_confirmed = false;
      m_open      = true;

      //--- a sensible default beats an empty field: land near the end of
      //--- what the broker holds, with room for the warmup
      if(m_req.start_msc <= 0 && m_cat != NULL && m_cat.Available())
        {
         long latest = m_cat.LatestStart(m_req.WarmupBars(), 1440);
         m_req.start_msc = (latest > 0 ? latest : m_cat.EarliestStart(m_req.WarmupBars()));
         m_req.end_msc   = m_cat.LastMsc();
        }
      Recompute();
      Render();
     }

   void              Close(void)
     {
      m_open = false;
      m_w.RemoveAll();
     }

   //+------------------------------------------------------------------+
   void              Recompute(void)
     {
      m_problem = "";
      m_quote.Init();
      if(m_cat == NULL)
        {
         m_problem = "no catalog";
         return;
        }
      m_cat.Quote(m_req.max_tf, m_req.visible_bars, m_req.ReplayMinutes(), m_quote);
      m_problem = SSRValidateRange(m_req, m_cat);
     }

   //--- the request is servable; a warning is not a refusal
   bool              CanStart(void)
     {
      return (m_req.IsComplete() && m_quote.IsFeasible() &&
              (m_problem == "" || StringFind(m_problem, "warning") == 0));
     }

   //+------------------------------------------------------------------+
   void              Render(void)
     {
      if(!m_open)
         return;

      int x = m_x, y = m_y, W = SSR_DLG_W;
      m_w.Rect("bg", x, y, W, SSR_DLG_H, SSR_C_PANEL, SSR_C_PANEL_EDGE);
      m_w.Rect("hdr", x + 1, y + 1, W - 2, SSR_HEADER_H, SSR_C_HEADER, SSR_C_HEADER);
      m_w.Label("title", x + SSR_PAD, y + 5, "NEW SESSION", SSR_C_ACCENT, SSR_FS_TITLE);
      m_w.Button("close", x + W - 24, y + 3, 18, SSR_HEADER_H - 5, "x");

      int cy = y + SSR_HEADER_H + SSR_GAP;

      //--- what the broker actually has, stated plainly
      if(m_cat != NULL && m_cat.Available())
         m_w.Label("avail", x + SSR_PAD, cy,
                   StringFormat("%s .. %s",
                                SSRFormatMsc(m_cat.FirstMsc()),
                                SSRFormatMsc(m_cat.LastMsc())),
                   SSR_C_TEXT_FAINT, SSR_FS_SMALL, SSR_FONT_MONO);
      cy += SSR_ROW_H - 4;

      //--- start, typed as text: MetaTrader has no date picker
      m_w.Label("startlbl", x + SSR_PAD, cy + 4, "START", SSR_C_TEXT_DIM, SSR_FS_SMALL);
      string n = m_prefix + "start";
      if(ObjectFind(m_chart, n) < 0)
        {
         ObjectCreate(m_chart, n, OBJ_EDIT, 0, 0, 0);
         ObjectSetInteger(m_chart, n, OBJPROP_CORNER, CORNER_LEFT_UPPER);
         ObjectSetInteger(m_chart, n, OBJPROP_SELECTABLE, false);
         ObjectSetInteger(m_chart, n, OBJPROP_ALIGN, ALIGN_LEFT);
         ObjectSetString (m_chart, n, OBJPROP_FONT, SSR_FONT_MONO);
         ObjectSetString (m_chart, n, OBJPROP_TEXT,
                          TimeToString(SSRToTime(m_req.start_msc),
                                       TIME_DATE | TIME_MINUTES));
        }
      ObjectSetInteger(m_chart, n, OBJPROP_XDISTANCE, x + W - SSR_PAD - 122);
      ObjectSetInteger(m_chart, n, OBJPROP_YDISTANCE, cy);
      ObjectSetInteger(m_chart, n, OBJPROP_XSIZE,     122);
      ObjectSetInteger(m_chart, n, OBJPROP_YSIZE,     SSR_ROW_H);
      ObjectSetInteger(m_chart, n, OBJPROP_BGCOLOR,   SSR_C_WELL);
      ObjectSetInteger(m_chart, n, OBJPROP_COLOR,     SSR_C_TEXT);
      ObjectSetInteger(m_chart, n, OBJPROP_FONTSIZE,  SSR_FS_BODY);
      cy += SSR_ROW_H + 4;

      //--- deepest timeframe wanted; this is what drives the warmup cost
      m_w.Label("tflbl", x + SSR_PAD, cy + 4, "CONTEXT", SSR_C_TEXT_DIM, SSR_FS_SMALL);
      int bw = 30, bx = x + W - SSR_PAD - (bw * SSR_DLG_TF_COUNT + 9);
      for(int i = 0; i < SSR_DLG_TF_COUNT; i++)
        {
         m_w.Button("tf" + IntegerToString(i), bx, cy, bw, SSR_ROW_H,
                    TfName(i), TfAt(i) == m_req.max_tf);
         bx += bw + 3;
        }
      cy += SSR_ROW_H + SSR_GAP;

      //--- THE QUOTE
      m_w.Rect("qbg", x + SSR_PAD, cy, W - 2 * SSR_PAD, 44, SSR_C_WELL, SSR_C_PANEL_EDGE);
      m_w.Label("q1", x + SSR_PAD + 6, cy + 5,
                StringFormat("warmup %d bars  +  replay %d bars",
                             (int)m_quote.warmup_bars, (int)m_quote.replay_bars),
                SSR_C_TEXT_DIM, SSR_FS_SMALL, SSR_FONT_MONO);
      m_w.Label("q2", x + SSR_PAD + 6, cy + 22,
                (m_quote.IsFeasible()
                 ? StringFormat("~%.0fs to load,  %.1f MB",
                                m_quote.seconds, m_quote.megabytes)
                 : "not enough history"),
                (m_quote.IsFeasible() ? SSR_C_TEXT : SSR_C_STOP),
                SSR_FS_SMALL, SSR_FONT_MONO);
      cy += 44 + SSR_GAP;

      //--- problems, in words the user can act on
      color pc = (StringFind(m_problem, "warning") == 0) ? SSR_C_HOLD : SSR_C_STOP;
      m_w.Label("problem", x + SSR_PAD, cy, m_problem, pc, SSR_FS_SMALL);
      cy += SSR_ROW_H - 2;

      m_w.Button("more", x + SSR_PAD, cy, 96, SSR_BTN_H, "LOAD MORE");
      m_w.Button("start", x + W - SSR_PAD - 96, cy, 96, SSR_BTN_H, "START",
                 false, CanStart());
     }

   //+------------------------------------------------------------------+
   bool              OnEvent(const int id, const long &lparam,
                             const double &dparam, const string &sparam)
     {
      if(!m_open)
         return false;

      if(id == CHARTEVENT_OBJECT_ENDEDIT && StringFind(sparam, m_prefix) == 0)
        {
         if(StringSubstr(sparam, StringLen(m_prefix)) == "start")
           {
            string txt = ObjectGetString(m_chart, sparam, OBJPROP_TEXT);
            datetime t = StringToTime(txt);
            //--- a typo must not silently become 1970
            if(t > 0)
               m_req.start_msc = SSRToMsc(t);
            else
               m_problem = "could not read that date - use YYYY.MM.DD HH:MM";
            Recompute();
            Render();
            return true;
           }
        }

      if(id != CHARTEVENT_OBJECT_CLICK || StringFind(sparam, m_prefix) != 0)
         return false;

      string what = StringSubstr(sparam, StringLen(m_prefix));
      ObjectSetInteger(m_chart, sparam, OBJPROP_STATE, false);

      if(what == "close") { Close(); return true; }

      if(StringFind(what, "tf") == 0)
        {
         int i = (int)StringToInteger(StringSubstr(what, 2));
         if(i >= 0 && i < SSR_DLG_TF_COUNT)
            m_req.max_tf = TfAt(i);
         Recompute();
         Render();
         return true;
        }

      if(what == "more")
        {
         if(m_cat != NULL)
           {
            long gained = m_cat.LoadMore(m_quote.warmup_bars);
            m_problem = (gained > 0
                         ? StringFormat("gained %d more bars", (int)gained)
                         : "the broker has nothing older");
            Recompute();
            Render();
           }
         return true;
        }

      if(what == "start" && CanStart())
        {
         m_confirmed = true;
         Close();
         return true;
        }
      return true;
     }
  };

#endif // SSR_RANGE_DIALOG_MQH
//+------------------------------------------------------------------+

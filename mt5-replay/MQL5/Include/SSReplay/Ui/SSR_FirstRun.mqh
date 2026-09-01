//+------------------------------------------------------------------+
//|                                                SSR_FirstRun.mqh  |
//|                    SS Replay - What To Do Next (L5/Ui)           |
//|                                                                  |
//|  The first thirty seconds decide whether anyone comes back. A     |
//|  person who drops this on a chart and sees a still picture and a  |
//|  panel of thirty controls has not been given a tool; they have    |
//|  been given a puzzle.                                            |
//|                                                                  |
//|  Two things fix that, and this is the second one. The first is    |
//|  that the replay now starts moving by itself. The second is a     |
//|  card, on the chart, that says what the three things worth doing  |
//|  next actually are.                                              |
//|                                                                  |
//|  ONCE, EVER - not once per session. It leaves a marker file       |
//|  behind, so the person who runs this twenty times a day sees it   |
//|  the first time and never again. That also carries it across the  |
//|  one-window handover, which restarts this program: a card keyed   |
//|  to a variable would show on the pass that has no replay chart    |
//|  and be gone on the pass that does.                              |
//|                                                                  |
//|  IT SAYS WHAT THE KEYS ACTUALLY ARE. B is bookmark and S is       |
//|  sessions - not buy and sell, which are buttons. A card that      |
//|  taught the wrong keys would be worse than no card, because the   |
//|  user would blame themselves for the first thing that did not     |
//|  work.                                                            |
//+------------------------------------------------------------------+
#ifndef SSR_FIRST_RUN_MQH
#define SSR_FIRST_RUN_MQH

#include "../Common/SSR_Types.mqh"
#include "SSR_Theme.mqh"
#include "SSR_Widgets.mqh"

//--- the marker. Delete it to be a beginner again.
#define SSR_SEEN_FILE   "SSReplay\\seen.txt"

//--- long enough to read four lines twice, short enough that nobody
//--- has to go looking for a way to dismiss it
#define SSR_FIRST_MS    25000

//+------------------------------------------------------------------+
class CSSRFirstRun
  {
private:
   long              m_chart;
   CSSRWidgets       m_w;
   bool              m_up;
   uint              m_shown_ms;

public:
                     CSSRFirstRun(void)
     : m_chart(0), m_up(false), m_shown_ms(0) {}

   bool              IsUp(void) { return m_up; }

   //--- has this installation ever been told? Not "this session" and
   //--- not "this chart": a file, because the handover restarts the
   //--- program and a variable would not survive it.
   static bool       AlreadySeen(void)
     { return FileIsExist(SSR_SEEN_FILE); }

   static bool       MarkSeen(void)
     {
      FolderCreate("SSReplay");
      int h = FileOpen(SSR_SEEN_FILE, FILE_WRITE | FILE_TXT | FILE_ANSI);
      if(h == INVALID_HANDLE)
         return false;
      FileWriteString(h,
         "SS Replay has shown its first-run card on this installation.\r\n"
         "Delete this file to see it again.\r\n");
      FileClose(h);
      return true;
     }

   //+------------------------------------------------------------------+
   //| Put it up. Below the panel's own home corner, so a first run -   |
   //| where the panel has not been moved yet - cannot cover it.        |
   //+------------------------------------------------------------------+
   bool              Show(const long chart_id)
     {
      if(chart_id == 0)
         return false;
      m_chart = chart_id;
      m_w.Attach(chart_id, "SSRF_");
      m_w.RemoveAll();

      int x = 14, y = SSR_PANEL_H + 40, w = 396, h = 104;
      m_w.Rect("bg", x, y, w, h, SSR_C_PANEL, SSR_C_PANEL_EDGE);
      m_w.Label("t", x + 12, y + 10, "SS REPLAY  -  WHAT NOW?",
                SSR_C_HOLD, SSR_FS_BODY);

      //--- every one of these is under MetaTrader's 63-character cut.
      //--- A14 measures them: it used to watch only ObjectSetString,
      //--- which nothing in this tree calls any more, so it was green
      //--- over this card until it was taught to read the widgets - and
      //--- the first thing it then found was the line below, at 64.
      m_w.Label("l1", x + 12, y + 32,
                "Playing. SPACE pauses, arrows step one candle, R restarts.",
                SSR_C_TEXT, SSR_FS_SMALL);
      m_w.Label("l2", x + 12, y + 48,
                "Press L to put stop and target lines on the chart, drag them.",
                SSR_C_TEXT, SSR_FS_SMALL);
      m_w.Label("l3", x + 12, y + 64,
                "Then Buy or Sell on the panel. All virtual - never a broker.",
                SSR_C_TEXT, SSR_FS_SMALL);
      m_w.Label("l4", x + 12, y + 84,
                "Shown once. Delete MQL5/Files/SSReplay/seen.txt for it again.",
                SSR_C_TEXT_DIM, SSR_FS_SMALL);

      ChartRedraw(m_chart);
      m_up       = true;
      m_shown_ms = GetTickCount();
      return true;
     }

   //--- called from the timer. Takes itself away; there is no button to
   //--- dismiss it, because a card with a close button is a card the
   //--- user has to deal with rather than read.
   void              Tick(void)
     {
      if(!m_up)
         return;
      if(GetTickCount() - m_shown_ms < SSR_FIRST_MS)
         return;
      Clear();
     }

   void              Clear(void)
     {
      if(!m_up)
         return;
      m_w.RemoveAll();
      if(m_chart != 0)
         ChartRedraw(m_chart);
      m_up = false;
     }
  };

#endif // SSR_FIRST_RUN_MQH
//+------------------------------------------------------------------+

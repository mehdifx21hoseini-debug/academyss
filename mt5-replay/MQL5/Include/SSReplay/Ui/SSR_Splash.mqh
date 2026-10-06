//+------------------------------------------------------------------+
//|                                                   SSR_Splash.mqh |
//|                    SS Replay - the host chart IS the nameplate   |
//|                                                                  |
//|  WHY THIS EXISTS                                                 |
//|  A person attaches the expert and the chart looks exactly as it   |
//|  did a second earlier. Nothing announces that a product started,  |
//|  nothing says which chart is now load-bearing, and nothing warns  |
//|  that closing this chart ends the replay running on the other     |
//|  one.                                                            |
//|                                                                  |
//|  NO CARD. NO BORDER. THE PAGE ITSELF.                            |
//|  This used to draw a bordered plate in the corner, and a plate on |
//|  a chart is a thing somebody put ON a chart. What the reference    |
//|  does - and what was asked for here - is to make the host chart   |
//|  a blank white page and write on it: the mark, the name, and the  |
//|  two lines that matter, set directly on the paper with nothing    |
//|  boxing them in.                                                  |
//|                                                                  |
//|  SO IT TAKES THE CHART OVER, and says so in the one place that    |
//|  can be checked: it records what the chart looked like and puts   |
//|  every one of those properties back on Destroy. A tool that       |
//|  repaints somebody's chart and cannot undo it is a tool they      |
//|  stop trusting the second time.                                   |
//|                                                                  |
//|  THE MARK IS A RESOURCE, NOT A FILE BESIDE THE EXPERT.           |
//|  #resource compiles the bitmap INTO the .ex5, so there is no      |
//|  second file to install, to lose, or to get out of step. If it is |
//|  missing the object simply does not draw and every word on the    |
//|  page is still there - the page does not depend on the picture.   |
//|                                                                  |
//|  IT IS ALSO THE ONE PLACE THE SAFETY GUARANTEE IS WRITTEN WHERE  |
//|  A BEGINNER WILL ACTUALLY READ IT.                               |
//|  "Virtual trades only" belongs on screen at the moment somebody   |
//|  first wonders whether this thing can touch their money - which   |
//|  is the moment they attach it to a live account's chart, not      |
//|  page nine of a manual.                                          |
//|                                                                  |
//|  DRAWN AFTER THE SETUP PANEL, ALWAYS.                            |
//|  CSSRSetupPanel::Create sweeps every object whose name starts     |
//|  with "SSR" except the picker line. A page painted before that    |
//|  call is a page that is not there afterwards, and the symptom -   |
//|  "it flashed and vanished" - reads as a crash.                   |
//+------------------------------------------------------------------+
#ifndef SSR_SPLASH_MQH
#define SSR_SPLASH_MQH

#include "SSR_Theme.mqh"
#include "SSR_Widgets.mqh"
#include "SSR_Strings.mqh"
#include "../Common/SSR_Build.mqh"

//--- where the page's ink sits. The mark is 128x150 at its own size,
//--- so the text column starts clear of it.
#define SSR_SPLASH_X     36      // left margin for the mark
#define SSR_SPLASH_Y     34
#define SSR_LOGO_W      128
#define SSR_LOGO_H      150
#define SSR_SPLASH_TX   (SSR_SPLASH_X + SSR_LOGO_W + 34)   // the text column
//--- the widest line the text column draws, so the Home dialog can be
//--- put beside it instead of on top of it
#define SSR_SPLASH_TEXT_W 320
#define SSR_SPLASH_W    (SSR_SPLASH_TX + SSR_SPLASH_TEXT_W)
#define SSR_SPLASH_H    (SSR_LOGO_H + 20)

//--- the compiled-in mark. The expert declares the #resource; this is
//--- the name MetaTrader knows it by.
#define SSR_LOGO_RES    "::Images\\ssr-logo.bmp"

//+------------------------------------------------------------------+
class CSSRSplash
  {
private:
   long              m_chart;
   CSSRWidgets       m_w;
   bool              m_open;
   string            m_status;
   color             m_status_col;

   //--- what the chart looked like before this page took it
   bool              m_took;
   long              m_was_col[12];
   long              m_was_grid, m_was_ohlc, m_was_price, m_was_date;

   //+------------------------------------------------------------------+
   //| THE ACCOUNT LINE IS A FACT ABOUT THE TERMINAL, not about the     |
   //| replay - which is the whole point of printing it. A person who   |
   //| attached this to a live account should see the word "real" on    |
   //| screen next to the sentence that says nothing is sent anywhere.  |
   //+------------------------------------------------------------------+
   string            AccountLine(void)
     {
      long   login = AccountInfoInteger(ACCOUNT_LOGIN);
      long   mode  = AccountInfoInteger(ACCOUNT_TRADE_MODE);
      string kind  = (mode == ACCOUNT_TRADE_MODE_REAL    ? "real"
                      : (mode == ACCOUNT_TRADE_MODE_DEMO ? "demo" : "contest"));
      if(login <= 0)
         return T(SSR_S_SP_NO_ACCOUNT);
      //--- trimmed on purpose: a broker name can be forty characters and
      //--- MetaTrader draws sixty-three of a label before it stops.
      string broker = AccountInfoString(ACCOUNT_COMPANY);
      if(StringLen(broker) > 22)
         broker = StringSubstr(broker, 0, 21) + ".";
      return StringFormat("#%d  %s  %s", (int)login, kind, broker);
     }

public:
                     CSSRSplash(void)
     : m_chart(0), m_open(false), m_status(""), m_status_col(SSR_C_TEXT_DIM),
       m_took(false), m_was_grid(0), m_was_ohlc(0), m_was_price(0),
       m_was_date(0) { ArrayInitialize(m_was_col, 0); }

                    ~CSSRSplash(void) { Destroy(); }

   bool              IsOpen(void) { return m_open; }

   void              Create(const long chart_id)
     {
      m_chart = chart_id;
      m_w.Attach(chart_id, "SSRSP_");
      m_w.RemoveAll();
      m_open = true;
      Render();
     }

   //+------------------------------------------------------------------+
   //| THE CHART IS GIVEN BACK BEFORE ANY OTHER TEST.                   |
   //|                                                                  |
   //| It used to be behind "if not open, return". That is fine until a  |
   //| path exists where the page took the chart and then closed itself  |
   //| some other way - and the cost of being wrong is a user staring at |
   //| an all-white chart whose candles are painted white, which reads   |
   //| as a dead tool and is the single worst thing this file can do.    |
   //| GiveChartBack already no-ops when it has nothing to restore.      |
   //+------------------------------------------------------------------+
   void              Destroy(void)
     {
      if(m_chart == 0)
         return;
      GiveChartBack();
      if(!m_open)
         return;
      m_w.RemoveAll();
      m_open = false;
     }

   //+------------------------------------------------------------------+
   //| The one line that changes. Everything else on the nameplate is   |
   //| constant for the life of the program, so only this repaints.     |
   //+------------------------------------------------------------------+
   void              Status(const string text, const color col = SSR_C_TEXT_DIM)
     {
      if(text == m_status && col == m_status_col)
         return;
      m_status     = text;
      m_status_col = col;
      if(!m_open)
         return;
      m_w.Label("stat", SSR_SPLASH_TX, SSR_SPLASH_Y + 190,
                m_status, m_status_col, SSR_FS_TITLE);
      ChartRedraw(m_chart);
     }

   //+------------------------------------------------------------------+
   //| TAKE THE CHART, AND WRITE DOWN HOW TO GIVE IT BACK.              |
   //|                                                                  |
   //| Every property it changes is read first and restored on Destroy. |
   //| A tool that repaints somebody's chart and cannot undo it is a    |
   //| tool they stop trusting the second time they open it.            |
   //+------------------------------------------------------------------+
   //--- every chart colour this page blanks, and the order is the order
   //--- they are saved and put back in
   static int        ChartColourCount(void) { return 12; }
   int               ColourProp(const int i)
     {
      switch(i)
        {
         case 0:  return CHART_COLOR_BACKGROUND;
         case 1:  return CHART_COLOR_FOREGROUND;
         case 2:  return CHART_COLOR_GRID;
         case 3:  return CHART_COLOR_CHART_UP;
         case 4:  return CHART_COLOR_CHART_DOWN;
         case 5:  return CHART_COLOR_CHART_LINE;
         case 6:  return CHART_COLOR_CANDLE_BULL;
         case 7:  return CHART_COLOR_CANDLE_BEAR;
         case 8:  return CHART_COLOR_VOLUME;
         case 9:  return CHART_COLOR_BID;
         case 10: return CHART_COLOR_ASK;
         default: return CHART_COLOR_LAST;
        }
     }

   //+------------------------------------------------------------------+
   //| A BLANK PAGE MEANS BLANK. THE CANDLES GO TOO.                    |
   //|                                                                  |
   //| The first version set only the background and the foreground, so  |
   //| what the user got was their own candles on a white field - the    |
   //| chart's colours against a background chosen for a different one.  |
   //| They were right to call it a mess, and right that the reference    |
   //| looks "as if the whole thing is a picture": its host chart draws   |
   //| no price at all. Sampled from the frame, every pixel of it is      |
   //| 255,255,255.                                                      |
   //|                                                                  |
   //| So every colour that can put ink on this chart goes to the page    |
   //| colour, and every one of them is read first and put back in        |
   //| GiveChartBack. Twelve properties, one loop, no list to forget.     |
   //+------------------------------------------------------------------+
   void              TakeChart(void)
     {
      if(m_took)
         return;
      for(int i = 0; i < ChartColourCount(); i++)
         m_was_col[i] = ChartGetInteger(m_chart, (ENUM_CHART_PROPERTY_INTEGER)ColourProp(i));
      m_was_grid  = ChartGetInteger(m_chart, CHART_SHOW_GRID);
      m_was_ohlc  = ChartGetInteger(m_chart, CHART_SHOW_OHLC);
      m_was_price = ChartGetInteger(m_chart, CHART_SHOW_PRICE_SCALE);
      m_was_date  = ChartGetInteger(m_chart, CHART_SHOW_DATE_SCALE);
      m_took = true;

      for(int i = 0; i < ChartColourCount(); i++)
         ChartSetInteger(m_chart, (ENUM_CHART_PROPERTY_INTEGER)ColourProp(i),
                         SSR_C_PAGE);
      ChartSetInteger(m_chart, CHART_SHOW_GRID,        false);
      ChartSetInteger(m_chart, CHART_SHOW_OHLC,        false);
      ChartSetInteger(m_chart, CHART_SHOW_PRICE_SCALE, false);
      ChartSetInteger(m_chart, CHART_SHOW_DATE_SCALE,  false);
      ChartRedraw(m_chart);
     }

   void              GiveChartBack(void)
     {
      if(!m_took)
         return;
      for(int i = 0; i < ChartColourCount(); i++)
         ChartSetInteger(m_chart, (ENUM_CHART_PROPERTY_INTEGER)ColourProp(i),
                         m_was_col[i]);
      ChartSetInteger(m_chart, CHART_SHOW_GRID,        m_was_grid);
      ChartSetInteger(m_chart, CHART_SHOW_OHLC,        m_was_ohlc);
      ChartSetInteger(m_chart, CHART_SHOW_PRICE_SCALE, m_was_price);
      ChartSetInteger(m_chart, CHART_SHOW_DATE_SCALE,  m_was_date);
      m_took = false;
      ChartRedraw(m_chart);
     }

   //+------------------------------------------------------------------+
   //| THE PAGE STEPS ASIDE WHEN THE CHART IS NEEDED.                   |
   //|                                                                  |
   //| A blank white chart is the right background for a Home dialog and |
   //| exactly the wrong one for choosing WHERE to start: that is done   |
   //| by dragging a line across the candles, and there are no candles    |
   //| on a blank page.                                                  |
   //|                                                                  |
   //| The reference never has this problem because it picks its start    |
   //| by typing a date. Rather than take the dragging away - it is the   |
   //| better way to choose, and the whole reason this tool exists - the  |
   //| page simply gets out of the way for that one step and comes back   |
   //| afterwards.                                                        |
   //+------------------------------------------------------------------+
   void              Suspend(void)
     {
      if(!m_open)
         return;
      m_w.RemoveAll();
      GiveChartBack();
     }

   void              Resume(void)
     {
      if(!m_open)
         return;
      Render();
     }

   //+------------------------------------------------------------------+
   void              Render(void)
     {
      if(!m_open || m_chart == 0)
         return;

      TakeChart();

      int x  = SSR_SPLASH_X, y = SSR_SPLASH_Y;
      int tx = SSR_SPLASH_TX;

      //--- THE MARK. If the resource is missing this draws nothing and
      //--- every word below is still on the page, which is the right
      //--- failure: a missing picture must not take the warning with it.
      m_w.Bitmap("logo", x, y, SSR_LOGO_W, SSR_LOGO_H, SSR_LOGO_RES);

      //--- the name, set straight on the paper
      m_w.Label("name", tx, y + 8, T(SSR_S_SP_NAME),
                SSR_C_TEXT, SSR_FS_PAGE);
      m_w.Label("tag",  tx, y + 40, T(SSR_S_SP_TAGLINE),
                SSR_C_TEXT_DIM, SSR_FS_TITLE);

      //--- the two lines the reference prints in green, and for the same
      //--- reason: this chart is load-bearing and closing it ends the run
      m_w.Label("keep", tx, y + 76, T(SSR_S_SP_KEEP_OPEN),
                SSR_C_RUN, SSR_FS_TITLE);
      m_w.Label("runs", tx, y + 98, T(SSR_S_SP_RUNS_HERE),
                SSR_C_RUN, SSR_FS_TITLE);

      //--- the account, and the guarantee, quieter than the warning
      m_w.Label("acc",  tx, y + 128, AccountLine(),
                SSR_C_TEXT_FAINT, SSR_FS_BODY);
      m_w.Label("safe", tx, y + 148, T(SSR_S_SP_VIRTUAL),
                SSR_C_TEXT_FAINT, SSR_FS_BODY);

      m_w.Label("build", tx, y + 168, SSR_BUILD_SHORT,
                SSR_C_TEXT_FAINT, SSR_FS_SMALL);

      if(m_status != "")
         m_w.Label("stat", tx, y + 190, m_status, m_status_col, SSR_FS_TITLE);

      ChartRedraw(m_chart);
     }

   //--- the nameplate owns no controls, so it has no Poll: a surface
   //--- that cannot be clicked should not pretend to consume clicks.
  };

#endif // SSR_SPLASH_MQH
//+------------------------------------------------------------------+

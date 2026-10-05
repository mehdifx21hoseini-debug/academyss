//+------------------------------------------------------------------+
//|                                                   SSR_Splash.mqh |
//|                    SS Replay - the host chart says what it is    |
//|                                                                  |
//|  WHY THIS EXISTS                                                 |
//|  A person attaches the expert and the chart looks exactly as it   |
//|  did a second earlier. Nothing announces that a product started,  |
//|  nothing says which chart is now load-bearing, and nothing warns  |
//|  that closing this chart ends the replay running on the other     |
//|  one. Every mature simulator on the market puts a nameplate on    |
//|  its host window for precisely that reason.                      |
//|                                                                  |
//|  SO THIS IS A NAMEPLATE, NOT A SPLASH SCREEN.                    |
//|  It does not cover the chart, it does not animate, and it never   |
//|  has to be dismissed. It states four things and then gets out of  |
//|  the way: what this is, which account it is attached to, that     |
//|  nothing here reaches the broker, and that the chart must stay    |
//|  open.                                                           |
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
//|  with "SSR" except the picker line. A nameplate painted before    |
//|  that call is a nameplate that is not there afterwards, and the   |
//|  symptom - "it flashed and vanished" - reads as a crash.         |
//+------------------------------------------------------------------+
#ifndef SSR_SPLASH_MQH
#define SSR_SPLASH_MQH

#include "SSR_Theme.mqh"
#include "SSR_Widgets.mqh"
#include "SSR_Strings.mqh"
#include "../Common/SSR_Build.mqh"

#define SSR_SPLASH_W   296
#define SSR_SPLASH_X   14
#define SSR_SPLASH_Y   14
#define SSR_SPLASH_H   112

//+------------------------------------------------------------------+
class CSSRSplash
  {
private:
   long              m_chart;
   CSSRWidgets       m_w;
   bool              m_open;
   string            m_status;
   color             m_status_col;

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
     : m_chart(0), m_open(false), m_status(""), m_status_col(SSR_C_TEXT_DIM) {}

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

   void              Destroy(void)
     {
      if(m_chart == 0 || !m_open)
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
      m_w.Label("stat", SSR_SPLASH_X + 34, SSR_SPLASH_Y + 86,
                m_status, m_status_col, SSR_FS_SMALL);
      ChartRedraw(m_chart);
     }

   //+------------------------------------------------------------------+
   void              Render(void)
     {
      if(!m_open || m_chart == 0)
         return;

      int x = SSR_SPLASH_X, y = SSR_SPLASH_Y;

      m_w.Rect("bg", x, y, SSR_SPLASH_W, SSR_SPLASH_H,
               SSR_C_PANEL, SSR_C_PANEL_EDGE);

      //--- THE MARK. A filled square with the product's initials is the
      //--- whole logo: MetaTrader can draw a bitmap, but a bitmap is a
      //--- file that has to ship, be found, and survive a move, and a
      //--- nameplate that fails to a blank box is worse than one drawn
      //--- from two rectangles that cannot fail at all.
      m_w.Rect("markbg", x + 10, y + 10, 22, 22, SSR_C_ACCENT, SSR_C_ACCENT);
      m_w.Label("mark", x + 15, y + 15, SSR_BRAND_MARK,
                SSR_C_PRIMARY_TEXT, SSR_FS_BODY);

      m_w.Label("name", x + 40, y + 10, T(SSR_S_SP_NAME),
                SSR_C_TEXT, SSR_FS_CLOCK);
      m_w.Label("tag",  x + 40, y + 29, T(SSR_S_SP_TAGLINE),
                SSR_C_TEXT_DIM, SSR_FS_SMALL);

      m_w.Rect("rule", x + 10, y + 46, SSR_SPLASH_W - 20, 1,
               SSR_C_GROUP_EDGE, SSR_C_GROUP_EDGE);

      m_w.Label("acc", x + 10, y + 52, AccountLine(),
                SSR_C_TEXT_DIM, SSR_FS_SMALL);

      //--- THE GUARANTEE, in the accent colour, because it is the one
      //--- sentence on this chart a person needs to believe.
      m_w.Label("safe", x + 10, y + 66, T(SSR_S_SP_VIRTUAL),
                SSR_C_RUN, SSR_FS_SMALL);

      //--- the warning the video's product puts in green on a blank
      //--- chart: this window is load-bearing, minimise it, do not
      //--- close it.
      m_w.Label("keepi", x + 10, y + 86, "!", SSR_C_HOLD, SSR_FS_BODY);
      m_w.Label("keep",  x + 20, y + 86, T(SSR_S_SP_KEEP_OPEN),
                SSR_C_HOLD, SSR_FS_SMALL);

      m_w.Label("build", x + SSR_SPLASH_W - 86, y + 14, SSR_BUILD_SHORT,
                SSR_C_TEXT_FAINT, SSR_FS_SMALL);

      if(m_status != "")
         m_w.Label("stat", x + 34, y + 86, m_status, m_status_col, SSR_FS_SMALL);

      ChartRedraw(m_chart);
     }

   //--- the nameplate owns no controls, so it has no Poll: a surface
   //--- that cannot be clicked should not pretend to consume clicks.
  };

#endif // SSR_SPLASH_MQH
//+------------------------------------------------------------------+

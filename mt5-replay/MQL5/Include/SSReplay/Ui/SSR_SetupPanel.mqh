//+------------------------------------------------------------------+
//|                                               SSR_SetupPanel.mqh |
//|                    SS Replay - Setup, on the chart (L5/Ui)       |
//|                                                                  |
//|  WHY THIS EXISTS                                                 |
//|  Everything about a session used to be set in MetaTrader's own   |
//|  inputs dialog: a grid of thirty rows the user has to open,      |
//|  scroll, read and close before the tool does anything. It is     |
//|  the single biggest reason a person tries a replay tool once     |
//|  and does not come back.                                         |
//|                                                                  |
//|  So the settings sit on the chart, beside the line that chooses  |
//|  where to begin, and the same button that starts the replay is   |
//|  the one that reads them.                                        |
//|                                                                  |
//|  THE INPUTS ARE STILL THE TRUTH - as DEFAULTS.                   |
//|  This panel opens showing what the inputs say, and what the user |
//|  last used overrides that. Nothing here removes a way of working |
//|  that already worked: a person who sets everything in the inputs |
//|  dialog and never touches this panel gets exactly the session    |
//|  they asked for.                                                 |
//|                                                                  |
//|  IT READS ONCE, AT START.                                        |
//|  Not on every edit. MetaTrader delivers OBJECT_ENDEDIT only to   |
//|  the chart a program is attached to, and this project has spent  |
//|  three architectures on that lesson. One read, at the moment the |
//|  answer is needed, is a design with nothing to keep in sync.     |
//+------------------------------------------------------------------+
#ifndef SSR_SETUP_PANEL_MQH
#define SSR_SETUP_PANEL_MQH

#include "../Common/SSR_Types.mqh"
#include "SSR_Theme.mqh"
#include "SSR_Widgets.mqh"
#include "../Chart/SSR_BlindMode.mqh"
#include "../Common/SSR_SessionFile.mqh"

//--- where the panel remembers what the user last chose. Also how the
//--- values cross the handover: the replay chart restarts this program,
//--- and a chart object cannot carry them (MetaTrader cuts object text
//--- at 63 characters, which this is comfortably past).
#define SSR_SETUP_FILE  "SSReplay\\setup.ini"

#define SSR_SETUP_W        304
#define SSR_SETUP_ROW      24
#define SSR_SETUP_FIELD_W  84

//+------------------------------------------------------------------+
//| Everything the panel can set. Filled from the inputs, edited by   |
//| the user, read back at Start.                                     |
//+------------------------------------------------------------------+
struct SSRSetupValues
  {
   double            balance;
   double            risk_percent;
   double            spread_points;
   double            speed;
   ENUM_TIMEFRAMES   chart_tf;
   string            extra_tfs;
   ENUM_SSR_BLIND    blind;
   string            session_name;

   bool              prop_on;
   double            prop_target;
   double            prop_daily;
   double            prop_total;

   void              Init(void)
     {
      balance = 10000.0; risk_percent = 0.5; spread_points = 20.0;
      speed = 30.0; chart_tf = PERIOD_M5; extra_tfs = ""; blind = SSR_BLIND_OFF;
      session_name = "";
      prop_on = false; prop_target = 8.0; prop_daily = 5.0; prop_total = 10.0;
     }
  };

//--- the timeframes the chart button cycles through, in the order a
//--- person actually steps between them
const ENUM_TIMEFRAMES SSR_SETUP_TFS[] =
  {PERIOD_M1, PERIOD_M5, PERIOD_M15, PERIOD_M30, PERIOD_H1, PERIOD_H4};

string SSRSetupTfName(const ENUM_TIMEFRAMES tf)
  {
   switch(tf)
     {
      case PERIOD_M1:  return "M1";
      case PERIOD_M5:  return "M5";
      case PERIOD_M15: return "M15";
      case PERIOD_M30: return "M30";
      case PERIOD_H1:  return "H1";
      case PERIOD_H4:  return "H4";
      case PERIOD_D1:  return "D1";
     }
   return "M5";
  }

string SSRSetupBlindName(const ENUM_SSR_BLIND b)
  {
   if(b == SSR_BLIND_STANDARD) return "standard";
   if(b == SSR_BLIND_FULL)     return "full";
   return "off";
  }

//+------------------------------------------------------------------+
class CSSRSetupPanel
  {
private:
   long              m_chart;
   CSSRWidgets       m_w;
   SSRSetupValues    m_v;
   bool              m_open;
   int               m_x, m_y;
   string            m_start_text;

   //--- the two values a button cycles rather than a box accepts
   int               m_tf_i;

   void              Row(const string id, const int r, const string label,
                         const string value, const bool boxed)
     {
      int ry = m_y + 30 + r * SSR_SETUP_ROW;
      m_w.Label("l" + id, m_x + 12, ry + 5, label, SSR_C_TEXT, SSR_FS_BODY);
      if(boxed)
         m_w.Edit("e" + id, m_x + SSR_SETUP_W - SSR_SETUP_FIELD_W - 12, ry,
                  SSR_SETUP_FIELD_W, SSR_SETUP_ROW - 4, value, m_first_paint);
      else
         m_w.Button("b" + id, m_x + SSR_SETUP_W - SSR_SETUP_FIELD_W - 12, ry,
                    SSR_SETUP_FIELD_W, SSR_SETUP_ROW - 4, value);
     }

   bool              m_first_paint;

   double            Num(const string id, const double fallback)
     {
      string t = m_w.EditText("e" + id);
      if(t == "")
         return fallback;                 // the box is gone; keep what we had
      StringTrimLeft(t); StringTrimRight(t);
      StringReplace(t, ",", ".");
      if(t == "")
         return fallback;
      double v = StringToDouble(t);
      //--- "abc" parses as zero, and a zero balance is not a setting a
      //--- person meant. Anything unreadable keeps the previous value.
      if(v == 0.0 && StringGetCharacter(t, 0) != '0')
         return fallback;
      return v;
     }

   string            Str(const string id, const string fallback)
     {
      string t = m_w.EditText("e" + id);
      if(t == "")
         return "";                       // an emptied box IS a choice here
      StringTrimLeft(t); StringTrimRight(t);
      return t;
     }

public:
                     CSSRSetupPanel(void)
     : m_chart(0), m_open(false), m_x(14), m_y(28),
       m_start_text(""), m_tf_i(1), m_first_paint(true)
     { m_v.Init(); }

                    ~CSSRSetupPanel(void) { Destroy(); }

   bool              IsOpen(void)   { return m_open; }
   void              Values(SSRSetupValues &out) { out = m_v; }

   //--- called once, with what the inputs said
   void              Create(const long chart_id, SSRSetupValues &defaults)
     {
      m_chart = chart_id;
      m_v     = defaults;
      m_w.Attach(chart_id, "SSRS_");
      m_w.RemoveAll();
      m_first_paint = true;

      m_tf_i = 1;
      for(int i = 0; i < ArraySize(SSR_SETUP_TFS); i++)
         if(SSR_SETUP_TFS[i] == m_v.chart_tf)
            m_tf_i = i;

      m_open = true;
      Render();
      m_first_paint = false;
     }

   void              SetStartText(const string t)
     {
      if(t == m_start_text)
         return;
      m_start_text = t;
      if(m_open)
         m_w.Label("startlbl", m_x + 12, m_y + 30 + 15 * SSR_SETUP_ROW + 40,
                   t, SSR_C_HOLD, SSR_FS_SMALL);
     }

   void              Destroy(void)
     {
      if(!m_open)
         return;
      m_w.RemoveAll();
      m_open = false;
     }

   //+------------------------------------------------------------------+
   //| Paint. Edit boxes keep their text after the first pass, because  |
   //| rewriting them would delete what the user is halfway through     |
   //| typing - the classic way a settings form loses an answer.        |
   //+------------------------------------------------------------------+
   void              Render(void)
     {
      if(!m_open || m_chart == 0)
         return;

      int rows = 16;
      int h    = 30 + rows * SSR_SETUP_ROW + 76;
      m_w.Rect("frame", m_x, m_y, SSR_SETUP_W, h, SSR_C_PANEL, SSR_C_PANEL_EDGE);
      m_w.Label("title", m_x + 12, m_y + 9, "SS REPLAY  -  SETUP",
                SSR_C_TEXT, SSR_FS_BODY);

      int r = 0;
      m_w.Label("h1", m_x + 12, m_y + 30 + r * SSR_SETUP_ROW + 5, "ACCOUNT",
                SSR_C_TEXT_DIM, SSR_FS_SMALL); r++;
      Row("bal",  r++, "Balance",          DoubleToString(m_v.balance, 2),      true);
      Row("risk", r++, "Risk per trade %", DoubleToString(m_v.risk_percent, 2), true);
      Row("spr",  r++, "Spread, points",   DoubleToString(m_v.spread_points, 1),true);

      m_w.Label("h2", m_x + 12, m_y + 30 + r * SSR_SETUP_ROW + 5, "REPLAY",
                SSR_C_TEXT_DIM, SSR_FS_SMALL); r++;
      Row("spd",  r++, "Speed",            DoubleToString(m_v.speed, 0),        true);
      Row("tf",   r++, "Chart timeframe",  SSRSetupTfName(m_v.chart_tf),        false);
      Row("xtf",  r++, "Extra timeframes", m_v.extra_tfs,                       true);
      Row("bl",   r++, "Blind mode",       SSRSetupBlindName(m_v.blind),        false);

      m_w.Label("h3", m_x + 12, m_y + 30 + r * SSR_SETUP_ROW + 5, "EVALUATION",
                SSR_C_TEXT_DIM, SSR_FS_SMALL); r++;
      Row("pon",  r++, "Prop evaluation",  m_v.prop_on ? "on" : "off",          false);
      Row("ptg",  r++, "Profit target %",  DoubleToString(m_v.prop_target, 1),  true);
      Row("pdl",  r++, "Max daily loss %", DoubleToString(m_v.prop_daily, 1),   true);
      Row("ptl",  r++, "Max drawdown %",   DoubleToString(m_v.prop_total, 1),   true);

      m_w.Label("h4", m_x + 12, m_y + 30 + r * SSR_SETUP_ROW + 5, "SESSION",
                SSR_C_TEXT_DIM, SSR_FS_SMALL); r++;
      Row("ses",  r++, "Save as",          m_v.session_name,                    true);

      //--- the two buttons, and the line the whole panel is about
      int by = m_y + 30 + r * SSR_SETUP_ROW + 8;
      m_w.ButtonC("go", m_x + 12, by, SSR_SETUP_W - 24, 26,
                  "START REPLAY HERE", SSR_C_BUY, SSR_C_BUY_EDGE,
                  SSR_C_DEAL_TEXT, SSR_FS_BODY);
      m_w.Button("here", m_x + 12, by + 30, SSR_SETUP_W - 24, 22,
                 "Bring the line to this view");
      m_w.Label("startlbl", m_x + 12, by + 58,
                (m_start_text == "" ? "Drag the orange line" : m_start_text),
                SSR_C_HOLD, SSR_FS_SMALL);
     }

   //+------------------------------------------------------------------+
   //| Poll. Returns "go", "here" or "" - the same latch-consuming      |
   //| shape the main panel uses, for the same reason: a button pressed |
   //| on a chart this program may not own leaves no event behind.      |
   //+------------------------------------------------------------------+
   string            Poll(void)
     {
      if(!m_open)
         return "";

      if(m_w.Pressed("go"))    { ReadAll(); return "go";   }
      if(m_w.Pressed("here"))  { return "here"; }

      //--- the cycling buttons act immediately, because the value they
      //--- show IS the setting; nothing to confirm
      if(m_w.Pressed("btf"))
        {
         m_tf_i = (m_tf_i + 1) % ArraySize(SSR_SETUP_TFS);
         m_v.chart_tf = SSR_SETUP_TFS[m_tf_i];
         Render();
        }
      if(m_w.Pressed("bbl"))
        {
         if(m_v.blind == SSR_BLIND_OFF)           m_v.blind = SSR_BLIND_STANDARD;
         else if(m_v.blind == SSR_BLIND_STANDARD) m_v.blind = SSR_BLIND_FULL;
         else                                     m_v.blind = SSR_BLIND_OFF;
         Render();
        }
      if(m_w.Pressed("bpon"))
        {
         m_v.prop_on = !m_v.prop_on;
         Render();
        }
      return "";
     }

   //+------------------------------------------------------------------+
   //| One read, at the moment the answer is needed.                    |
   //+------------------------------------------------------------------+
   void              ReadAll(void)
     {
      m_v.balance       = Num("bal",  m_v.balance);
      m_v.risk_percent  = Num("risk", m_v.risk_percent);
      m_v.spread_points = Num("spr",  m_v.spread_points);
      m_v.speed         = Num("spd",  m_v.speed);
      m_v.extra_tfs     = Str("xtf",  m_v.extra_tfs);
      m_v.session_name  = Str("ses",  m_v.session_name);
      m_v.prop_target   = Num("ptg",  m_v.prop_target);
      m_v.prop_daily    = Num("pdl",  m_v.prop_daily);
      m_v.prop_total    = Num("ptl",  m_v.prop_total);

      //--- refuse the impossible rather than pass it down. A balance of
      //--- zero produces a risk engine that can size nothing, and the
      //--- error it eventually raises names a layer the user never saw.
      if(m_v.balance      <= 0.0)   m_v.balance      = 10000.0;
      if(m_v.risk_percent <= 0.0)   m_v.risk_percent = 0.5;
      if(m_v.risk_percent >  100.0) m_v.risk_percent = 100.0;
      if(m_v.spread_points < 0.0)   m_v.spread_points = 0.0;
      if(m_v.speed        <= 0.0)   m_v.speed        = 1.0;
      if(m_v.speed        > 10000.0)m_v.speed        = 10000.0;
     }

   //+------------------------------------------------------------------+
   //| REMEMBERED BETWEEN RUNS, AND ACROSS THE HANDOVER.                |
   //|                                                                  |
   //| Two jobs, one file. A user should not retype their balance every |
   //| session; and the second pass of the one-window handover is a     |
   //| fresh program that would otherwise fall back to the inputs and   |
   //| silently discard everything just typed - the same shape as the   |
   //| picked start that v55 had to rescue.                              |
   //+------------------------------------------------------------------+
   static bool       Save(SSRSetupValues &v)
     {
      FolderCreate("SSReplay");
      CSSRSessionFile f;
      if(!f.Create(SSR_SETUP_FILE))
         return false;
      f.Section("setup");
      f.SetDouble("balance",   v.balance,       2);
      f.SetDouble("risk",      v.risk_percent,  4);
      f.SetDouble("spread",    v.spread_points, 2);
      f.SetDouble("speed",     v.speed,         2);
      f.SetInt   ("chart_tf",  (int)v.chart_tf);
      f.Set      ("extra_tfs", v.extra_tfs);
      f.SetInt   ("blind",     (int)v.blind);
      f.Set      ("session",   v.session_name);
      f.SetInt   ("prop_on",   v.prop_on ? 1 : 0);
      f.SetDouble("prop_tgt",  v.prop_target,   4);
      f.SetDouble("prop_dly",  v.prop_daily,    4);
      f.SetDouble("prop_tot",  v.prop_total,    4);
      f.Close();
      return true;
     }

   //--- returns false when there is nothing saved, which is not a
   //--- failure: it is a first run, and the caller keeps its defaults
   static bool       Restore(SSRSetupValues &v)
     {
      if(!FileIsExist(SSR_SETUP_FILE))
         return false;
      CSSRSessionFile f;
      if(!f.Load(SSR_SETUP_FILE) || !f.Select("setup"))
         return false;
      v.balance       = f.GetDouble("balance",   v.balance);
      v.risk_percent  = f.GetDouble("risk",      v.risk_percent);
      v.spread_points = f.GetDouble("spread",    v.spread_points);
      v.speed         = f.GetDouble("speed",     v.speed);
      v.chart_tf      = (ENUM_TIMEFRAMES)f.GetInt("chart_tf", (int)v.chart_tf);
      v.extra_tfs     = f.Get("extra_tfs", v.extra_tfs);
      v.blind         = (ENUM_SSR_BLIND)f.GetInt("blind", (int)v.blind);
      v.session_name  = f.Get("session", v.session_name);
      v.prop_on       = (f.GetInt("prop_on", v.prop_on ? 1 : 0) != 0);
      v.prop_target   = f.GetDouble("prop_tgt", v.prop_target);
      v.prop_daily    = f.GetDouble("prop_dly", v.prop_daily);
      v.prop_total    = f.GetDouble("prop_tot", v.prop_total);
      return true;
     }

   string            Summary(void)
     {
      return StringFormat("balance %.2f  risk %.2f%%  spread %.1f  speed %.0fx"
                          "  tf %s  extra [%s]  blind %s  eval %s"
                          "  session [%s]",
                          m_v.balance, m_v.risk_percent, m_v.spread_points,
                          m_v.speed, SSRSetupTfName(m_v.chart_tf),
                          m_v.extra_tfs, SSRSetupBlindName(m_v.blind),
                          (m_v.prop_on ? "on" : "off"), m_v.session_name);
     }
  };

#endif // SSR_SETUP_PANEL_MQH
//+------------------------------------------------------------------+

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
#include "SSR_Strings.mqh"
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

//--- the tallest step (settings, seventeen rows). Centring on THIS
//--- rather than on the step being drawn is what stops the panel
//--- jumping under the hand that is pressing Next.
#define SSR_SETUP_H_MAX    (30 + 17 * SSR_SETUP_ROW + 44)
#define SSR_SETUP_FIELD_W  84

//--- where the presets live. A FILE, not a table baked into the code:
//--- these are somebody else's business terms, they change without
//--- telling us, and the person who knows the right numbers is the one
//--- holding the account. Editable, one line each.
#define SSR_PRESET_FILE "SSReplay\\presets.ini"

//+------------------------------------------------------------------+
//| One row of the Preset button.                                    |
//|                                                                  |
//| It fills the three evaluation numbers and the on/off, and NOTHING |
//| else. A preset that also set values the panel does not show would |
//| change the session in ways the user cannot see - which is a worse |
//| failure than making them type three numbers.                      |
//+------------------------------------------------------------------+
struct SSRPropPreset
  {
   string            name;
   bool              on;
   double            target;
   double            daily;
   double            total;

   void              Set(const string n, const bool o, const double tg,
                         const double dl, const double tl)
     { name = n; on = o; target = tg; daily = dl; total = tl; }
  };

//+------------------------------------------------------------------+
//| WHAT SHIPS, AND WHY IT IS NAMED BY SHAPE.                        |
//|                                                                  |
//| Every one of these is a starting point, not a contract. Firms     |
//| publish their own numbers and change them; naming a preset after  |
//| a company would put a claim about that company's current terms    |
//| into a tool that has no way to check it, and would be wrong the   |
//| first time they moved a limit.                                    |
//|                                                                  |
//| So the built-ins are named after the SHAPE of the challenge, and  |
//| the file they are written to is there to be renamed and corrected |
//| by the person who can actually see their own dashboard.           |
//+------------------------------------------------------------------+
int SSRDefaultPresets(SSRPropPreset &out[])
  {
   ArrayResize(out, 4);
   out[0].Set("Practice",  false, 8.0,  5.0, 10.0);
   out[1].Set("2-step P1", true,  8.0,  5.0, 10.0);
   out[2].Set("2-step P2", true,  5.0,  5.0, 10.0);
   out[3].Set("1-step",    true, 10.0,  5.0,  6.0);
   return ArraySize(out);
  }

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

   //+------------------------------------------------------------------+
   //| RANDOM AND ITS SEED.                                             |
   //|                                                                  |
   //| Both existed as expert inputs and neither had any UI, which made |
   //| the most differentiating training feature in this product        |
   //| reachable only by opening MetaTrader's own inputs dialog.        |
   //|                                                                  |
   //| The seed is what makes a random session REPEATABLE - the same    |
   //| seed and the same symbol give the same window, which is the      |
   //| whole basis of coaching, of the class report, and of testing a   |
   //| change against the session that exposed it. A random session you |
   //| cannot return to is one nobody can learn from.                   |
   //+------------------------------------------------------------------+
   bool              random_start;
   string            seed;

   void              Init(void)
     {
      balance = 10000.0; risk_percent = 0.5; spread_points = 20.0;
      speed = 30.0; chart_tf = PERIOD_M5; extra_tfs = ""; blind = SSR_BLIND_OFF;
      session_name = "";
      prop_on = false; prop_target = 8.0; prop_daily = 5.0; prop_total = 10.0;
      random_start = false; seed = "";
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
   bool              m_placed;      // the user chose this position, not us
   CSSRWidgets       m_w;
   SSRSetupValues    m_v;
   bool              m_open;
   int               m_x, m_y;
   string            m_start_text;

   //--- the two values a button cycles rather than a box accepts
   int               m_tf_i;

   //--- the preset list, and which one the button is showing. Slot 0 is
   //--- always "My last", so the cycle always has a way home.
   SSRPropPreset     m_presets[];
   int               m_preset_i;

   //--- forces the three evaluation boxes to be rewritten for one paint.
   //--- Only those three: forcing every box would delete whatever the
   //--- user was halfway through typing in the ones a preset does not
   //--- touch, which is the classic way a settings form loses an answer.
   bool              m_force_prop;

   //+------------------------------------------------------------------+
   //| WHERE THE START LINE'S CAPTION GOES - computed once, in Render,  |
   //| and remembered.                                                  |
   //|                                                                  |
   //| SetStartText used to work this out for itself, from a row count  |
   //| written into the expression by hand. Render walks the rows and    |
   //| gets a different answer, so the two disagreed by fifty pixels     |
   //| and the caption jumped between the buttons and its proper place   |
   //| depending on which one had run last. Adding the Preset row made   |
   //| the gap seventy-four. Two lists drift; one does not.              |
   //+------------------------------------------------------------------+
   int               m_start_y;

   void              Row(const string id, const int r, const string label,
                         const string value, const bool boxed,
                         const bool force = false)
     {
      int ry = m_y + 30 + r * SSR_SETUP_ROW;
      if(id == m_menu)
         m_menu_y = ry;                 // where this field's list drops from
      m_w.Label("l" + id, m_x + 12, ry + 5, label, SSR_C_TEXT, SSR_FS_BODY);
      if(boxed)
         m_w.Edit("e" + id, m_x + SSR_SETUP_W - SSR_SETUP_FIELD_W - 12, ry,
                  SSR_SETUP_FIELD_W, SSR_SETUP_ROW - 4, value,
                  m_first_paint || force);
      else
         m_w.Button("b" + id, m_x + SSR_SETUP_W - SSR_SETUP_FIELD_W - 12, ry,
                    SSR_SETUP_FIELD_W, SSR_SETUP_ROW - 4, value);
     }

   bool              m_first_paint;

   //+------------------------------------------------------------------+
   //| TWO STEPS, NOT ONE LONG FORM.                                    |
   //|                                                                  |
   //| Seventeen rows and the START button in the same breath asked a   |
   //| person to check every number and choose the moment to begin in   |
   //| one glance, with the one irreversible control sitting under the  |
   //| last text box they were typing in. The form was also 566 px tall |
   //| and printed a note in the log when the chart could not hold it.  |
   //|                                                                  |
   //| Step 1 is settings and nothing else - it cannot start anything.  |
   //| Step 2 shows back what was chosen, and only there is the orange  |
   //| line and the button that begins the session.                     |
   //+------------------------------------------------------------------+
   //+------------------------------------------------------------------+
   //| FOUR STEPS, AND THE FIRST ONE IS USUALLY THE LAST.                |
   //|                                                                  |
   //|   0  QUICK    two clicks and a drag, for the session you have    |
   //|                already had a hundred times                        |
   //|   1  SETTINGS the seventeen rows, for when they matter            |
   //|   2  MODE     what KIND of practice this is                       |
   //|   3  START    read back what was chosen, and begin                |
   //|                                                                  |
   //| An expert who runs the same configuration daily should not walk  |
   //| a wizard to do it, and a beginner should not meet seventeen rows |
   //| before they have seen a candle move.                              |
   //+------------------------------------------------------------------+
   int               m_step;

   //+------------------------------------------------------------------+
   //| A LIST YOU CAN SEE BEATS A BUTTON YOU CLICK UNTIL IT AGREES.     |
   //|                                                                  |
   //| Timeframe, blind mode and the prop presets were cycling buttons:  |
   //| press, read what it says now, press again. Reaching M30 from M1   |
   //| took five presses and five labels, and nowhere on the screen was  |
   //| there a list of what the choices even were.                       |
   //|                                                                  |
   //| MetaTrader has no combo box, so this is one built from what it    |
   //| does have: the field opens a column of buttons drawn LAST, which  |
   //| is what puts them on top - creation order is the only z-order     |
   //| there is here.                                                    |
   //+------------------------------------------------------------------+
   string            m_menu;            // which field is open, "" = none
   int               m_menu_y;          // where its list drops from

   //--- dragging the panel by its caption, the way a window moves
   bool              m_drag;
   int               m_drag_dx, m_drag_dy;

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


   //+------------------------------------------------------------------+
   //| THE PRESETS, loaded once when the panel opens.                   |
   //|                                                                  |
   //| Slot 0 is always "My last" - whatever this panel was handed, so  |
   //| cycling all the way round gets the user back to what they had    |
   //| rather than stranding them on somebody else's numbers.           |
   //+------------------------------------------------------------------+
   void              LoadPresets(void)
     {
      ArrayResize(m_presets, 1);
      m_presets[0].Set("My last", m_v.prop_on, m_v.prop_target,
                       m_v.prop_daily, m_v.prop_total);
      m_preset_i = 0;

      SSRPropPreset from_file[];
      int  n = 0;
      bool had_file = FileIsExist(SSR_PRESET_FILE);

      CSSRSessionFile f;
      if(had_file && f.Load(SSR_PRESET_FILE) && f.Select("presets"))
        {
         int rows = f.Count("p");
         ArrayResize(from_file, rows);
         for(int i = 0; i < rows; i++)
           {
            string c[];
            if(SSRUnpack(f.GetNth("p", i), c) < 5)
               continue;
            //--- a preset with no name is a button with no label, and a
            //--- target of zero is an evaluation that passes instantly
            string nm = SSRField(c, 0, "");
            double tg = SSRFieldDouble(c, 2, 0.0);
            if(nm == "" || (SSRFieldLong(c, 1, 0) != 0 && tg <= 0.0))
               continue;
            from_file[n].Set(nm, SSRFieldLong(c, 1, 0) != 0, tg,
                             SSRFieldDouble(c, 3, 5.0),
                             SSRFieldDouble(c, 4, 10.0));
            n++;
           }
        }

      //--- FIRST RUN WRITES THE FILE, so the very first thing a user
      //--- who wants their own firm's numbers finds is a file with the
      //--- right shape already in it, not a blank page and a guess.
      if(n == 0)
        {
         n = SSRDefaultPresets(from_file);
         //--- WRITTEN ONLY IF THERE WAS NO FILE. A file that exists and
         //--- parses to nothing is an edit somebody made and got wrong,
         //--- and overwriting it would delete their work to fix a
         //--- problem they can see and I cannot.
         if(!had_file)
            SavePresets(from_file, n);
         else
            Print("[setup] presets.ini has no readable rows - using the "
                  "built-in list. Your file has been left exactly as it is; "
                  "each line is name|on|target|daily|drawdown.");
        }

      ArrayResize(m_presets, 1 + n);
      for(int i = 0; i < n; i++)
         m_presets[1 + i] = from_file[i];
     }

   static bool       SavePresets(SSRPropPreset &p[], const int n)
     {
      FolderCreate("SSReplay");
      CSSRSessionFile f;
      if(!f.Create(SSR_PRESET_FILE))
         return false;
      f.Section("presets");
      f.Comment("One preset per line:  name|on|target%|daily loss%|max "
                "drawdown%");
      f.Comment("These are STARTING POINTS, not anybody's contract. Firms "
                "publish their own numbers and change them - put yours here,");
      f.Comment("renamed to whatever you call it. Keep names short: the "
                "button is narrow. Delete this file to get the defaults back.");
      for(int i = 0; i < n; i++)
        {
         string row = "";
         row = SSRPackAdd(row, p[i].name);
         row = SSRPackAdd(row, (p[i].on ? "1" : "0"));
         row = SSRPackAdd(row, DoubleToString(p[i].target, 2));
         row = SSRPackAdd(row, DoubleToString(p[i].daily,  2));
         row = SSRPackAdd(row, DoubleToString(p[i].total,  2));
         f.Set("p", row);
        }
      f.Close();
      return true;
     }

   //--- step to the next preset and PUT ITS NUMBERS IN THE BOXES. The
   //--- three rows below the button are the only proof the user gets
   //--- that the click did anything, so they are forced to repaint.
   void              CyclePreset(void)
     {
      int n = ArraySize(m_presets);
      if(n <= 1)
         return;
      m_preset_i = (m_preset_i + 1) % n;

      m_v.prop_on     = m_presets[m_preset_i].on;
      m_v.prop_target = m_presets[m_preset_i].target;
      m_v.prop_daily  = m_presets[m_preset_i].daily;
      m_v.prop_total  = m_presets[m_preset_i].total;

      PrintFormat("[setup] preset %s -> %s target %.1f%%  daily %.1f%%  "
                  "drawdown %.1f%%", m_presets[m_preset_i].name,
                  (m_v.prop_on ? "on" : "off"), m_v.prop_target,
                  m_v.prop_daily, m_v.prop_total);

      m_force_prop = true;
      Render();
      m_force_prop = false;
     }

   int               PresetNames(string &out[])
     {
      int n = ArraySize(m_presets);
      ArrayResize(out, n);
      for(int i = 0; i < n; i++)
         out[i] = m_presets[i].name;
      return n;
     }

   //--- apply a preset by index, which is what a list needs; CyclePreset
   //--- is now just "the next one" expressed through it
   void              ApplyPreset(const int i)
     {
      if(i < 0 || i >= ArraySize(m_presets))
         return;
      m_preset_i = i;
      m_v.prop_on     = m_presets[i].on;
      m_v.prop_target = m_presets[i].target;
      m_v.prop_daily  = m_presets[i].daily;
      m_v.prop_total  = m_presets[i].total;
      m_force_prop = true;
      Render();
      m_force_prop = false;
     }

   string            PresetName(void)
     {
      if(m_preset_i < 0 || m_preset_i >= ArraySize(m_presets))
         return "-";
      return m_presets[m_preset_i].name;
     }

public:
                     CSSRSetupPanel(void)
     //+------------------------------------------------------------------+
     //| 14,28 PUT IT UNDER METATRADER'S OWN ONE-CLICK TRADING PANEL.     |
     //|                                                                  |
     //| That widget lives at the top-left of every chart that has it     |
     //| switched on, and it is drawn by the terminal, so it always wins. |
     //| Our first two rows - Balance and its box - came up underneath it |
     //| and could be neither read nor typed in.                          |
     //|                                                                  |
     //| Below it, and inset, where nothing of MetaTrader's own lives.    |
     //+------------------------------------------------------------------+
     : m_chart(0), m_open(false), m_placed(false), m_x(18), m_y(84),
       m_start_text(""), m_tf_i(1), m_preset_i(0), m_force_prop(false),
       m_start_y(0), m_first_paint(true), m_step(0), m_menu(""),
       m_menu_y(0), m_drag(false), m_drag_dx(0), m_drag_dy(0)
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
      //--- SWEEP EVERY PREFIX, not just this panel's. Each part of this
      //--- product draws under its own - SSRP_, SSRK_, SSRF_, SSR_LINE_ -
      //--- so clearing SSRS_ left every OTHER part's leftovers exactly
      //--- where they were. That is why "something from before is still
      //--- there" survived two builds that both claimed to have fixed it.
      SSRPurgeChart(chart_id, SSR_PICK_LINE);
      LoadPlace();
      //--- PURGE FIRST. A previous run - or a previous BUILD, which is
      //--- worse because it laid things out differently - leaves its
      //--- objects on this chart under the same names, and a stale one
      //--- at coordinates this build never uses reads as a control that
      //--- has fallen out of the panel.
      m_w.RemoveAll();
      m_first_paint = true;
      m_step        = 0;

      m_tf_i = 1;
      for(int i = 0; i < ArraySize(SSR_SETUP_TFS); i++)
         if(SSR_SETUP_TFS[i] == m_v.chart_tf)
            m_tf_i = i;

      LoadPresets();

      //--- A PANEL TALLER THAN THE CHART IS A PANEL WITH ITS START
      //--- BUTTON OFF THE BOTTOM, and nothing on screen says why.
      int need = 28 + 30 + 17 * SSR_SETUP_ROW + 44 + 16;
      int have = (int)ChartGetInteger(chart_id, CHART_HEIGHT_IN_PIXELS);
      if(have > 0 && have < need)
         PrintFormat("[setup] this chart is %d pixels tall and the setup "
                     "panel needs %d - the START button is below the bottom "
                     "edge. Press Ctrl+T to close the Toolbox.", have, need);

      //+------------------------------------------------------------------+
      //| IN THE MIDDLE OF THE CHART, NOT IN THE CORNER.                   |
      //|                                                                  |
      //| It opened at a hard-coded 18,84 - top left, over the oldest       |
      //| candles, which is exactly where a person is NOT looking when they |
      //| are about to choose where a replay starts.                        |
      //|                                                                  |
      //| Centred on the TALLEST step, not on the one being drawn, so that  |
      //| stepping through the wizard does not make the panel jump under    |
      //| the hand pressing Next. A dragged position still wins: this only  |
      //| decides where it starts.                                          |
      //+------------------------------------------------------------------+
      if(!m_placed)
        {
         int cw2 = (int)ChartGetInteger(chart_id, CHART_WIDTH_IN_PIXELS);
         int ch2 = (int)ChartGetInteger(chart_id, CHART_HEIGHT_IN_PIXELS);
         if(cw2 > 0)
            m_x = (cw2 > SSR_SETUP_W + 16 ? (cw2 - SSR_SETUP_W) / 2 : 8);
         if(ch2 > 0)
            m_y = (ch2 > SSR_SETUP_H_MAX + 16 ? (ch2 - SSR_SETUP_H_MAX) / 2 : 8);
         if(m_x < 0) m_x = 0;
         if(m_y < 0) m_y = 0;
        }

      m_open = true;
      Render();
      m_first_paint = false;
     }

   void              SetStartText(const string t)
     {
      if(t == m_start_text)
         return;
      m_start_text = t;
      //--- before the first paint there is no layout to put it in, and
      //--- the paint that follows draws it anyway
      if(m_open && m_start_y > 0)
         m_w.Label("startlbl", m_x + 12, m_start_y, t, SSR_C_HOLD, SSR_FS_SMALL);
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
   //--- a read-only row on the confirm step: what step 1 was told
   void              Recap(const string id, const int r, const string label,
                          const string value, const color c = SSR_C_TEXT)
     {
      int ry = m_y + 30 + r * SSR_SETUP_ROW;
      m_w.Label("l" + id, m_x + 12, ry + 5, label, SSR_C_TEXT_DIM, SSR_FS_BODY);
      m_w.Label("v" + id, m_x + SSR_SETUP_W - SSR_SETUP_FIELD_W - 12, ry + 5,
                value, c, SSR_FS_BODY);
     }

   int               MenuOptions(const string id, string &out[])
     {
      if(id == "tf")
        {
         ArrayResize(out, ArraySize(SSR_SETUP_TFS));
         for(int i = 0; i < ArraySize(SSR_SETUP_TFS); i++)
            out[i] = SSRSetupTfName(SSR_SETUP_TFS[i]);
         return ArraySize(out);
        }
      if(id == "bl")
        {
         ArrayResize(out, 3);
         out[0] = SSRSetupBlindName(SSR_BLIND_OFF);
         out[1] = SSRSetupBlindName(SSR_BLIND_STANDARD);
         out[2] = SSRSetupBlindName(SSR_BLIND_FULL);
         return 3;
        }
      if(id == "pon")
        {
         ArrayResize(out, 2);
         out[0] = "off"; out[1] = "on";
         return 2;
        }
      if(id == "pre")
         return PresetNames(out);
      ArrayResize(out, 0);
      return 0;
     }

   void              MenuClear(void)
     {
      m_w.Remove("mbg");
      for(int i = 0; i < 32; i++)
         m_w.Remove("m" + IntegerToString(i));
     }

   void              DrawMenu(void)
     {
      if(m_menu == "")
         return;
      string opts[];
      int n = MenuOptions(m_menu, opts);
      if(n <= 0)
        { m_menu = ""; return; }

      int fx = m_x + SSR_SETUP_W - SSR_SETUP_FIELD_W - 12;
      int ih = SSR_SETUP_ROW - 4;
      int fy = m_menu_y + ih + 1;

      //--- a list that runs off the bottom has choices on it nobody can
      //--- reach, so it opens upwards instead
      int ch = (int)ChartGetInteger(m_chart, CHART_HEIGHT_IN_PIXELS);
      if(ch > 0 && fy + n * ih + 4 > ch)
         fy = m_menu_y - n * ih - 3;

      m_w.Rect("mbg", fx - 2, fy - 2, SSR_SETUP_FIELD_W + 4, n * ih + 4,
               SSR_C_WELL, SSR_C_PRIMARY_EDGE);
      for(int i = 0; i < n; i++)
         m_w.Button("m" + IntegerToString(i), fx, fy + i * ih,
                    SSR_SETUP_FIELD_W, ih, opts[i]);
     }

   //+------------------------------------------------------------------+
   //| A STEP CHANGE REPAINTS FROM SCRATCH, AND MUST DECLARE ITSELF A   |
   //| FIRST PAINT.                                                     |
   //|                                                                  |
   //| Edit boxes write their text only on a first pass - precisely so  |
   //| a repaint cannot delete what somebody is halfway through typing. |
   //| A step arriving at a cleared chart therefore comes back with     |
   //| EMPTY boxes unless it says it is a first paint.                   |
   //|                                                                  |
   //| That was written out three times in Poll() and is now written    |
   //| once, because the fourth copy is the one that forgets.            |
   //+------------------------------------------------------------------+
   void              Repaint(void)
     {
      m_w.RemoveAll();
      m_first_paint = true;
      Render();
      m_first_paint = false;
     }

   void              Render(void)
     {
      if(!m_open || m_chart == 0)
         return;
      MenuClear();
      if(m_step == 0)      RenderQuick();
      else if(m_step == 1) RenderSettings();
      else if(m_step == 2) RenderMode();
      else                 RenderStart();
      DrawMenu();                       // last, because last is on top

      //+------------------------------------------------------------------+
      //| THE BUTTONS WERE NOT SLOW. THE SCREEN WAS NOT BEING TOLD.        |
      //|                                                                  |
      //| Reported as "pressing its buttons works very slowly". It was not  |
      //| slow at all: Poll consumed the press, Repaint tore every object   |
      //| down and built it again - and nothing asked MetaTrader to draw    |
      //| the result. On a chart with no ticks arriving there is nothing    |
      //| else to force a redraw, so the new panel sat there unseen until   |
      //| the terminal repainted for its own reasons.                       |
      //|                                                                  |
      //| Every other surface in this product does this - the panel, both   |
      //| cards, both dialogs, the palette, the key card. This file had ONE |
      //| ChartRedraw and it was inside the DRAG handler, which is why      |
      //| dragging the panel always felt instant and pressing a button did  |
      //| not. That asymmetry was the whole clue, and no test had it,       |
      //| because a test can read an object's properties without ever       |
      //| asking whether the screen is showing them.                        |
      //|                                                                  |
      //| Here, at the end of the ONE function every path goes through, so  |
      //| a future step or menu cannot forget it.                           |
      //+------------------------------------------------------------------+
      ChartRedraw(m_chart);
     }

   //+------------------------------------------------------------------+
   //| STEP 0 - QUICK START.                                            |
   //|                                                                  |
   //| Three actions and a way past them. The wizard is still there and |
   //| still complete; it is simply no longer the only door.            |
   //|                                                                  |
   //| "Same as last time" is offered only when there IS a last time -  |
   //| setup.ini exists - and it says what it will do rather than       |
   //| promising it: the symbol, timeframe, balance and risk are read   |
   //| back and printed, so pressing it is a confirmation.               |
   //+------------------------------------------------------------------+
   void              RenderQuick(void)
     {
      bool have_last    = FileIsExist(SSR_SETUP_FILE);
      bool have_session = (m_v.session_name != "" &&
                           FileIsExist("SSReplay\\sessions\\" +
                                       m_v.session_name + ".ssr"));

      int rows = (have_last ? 1 : 0) + (have_session ? 1 : 0) + 1;
      int h    = 34 + rows * 46 + 40;
      m_w.Rect("frame", m_x, m_y, SSR_SETUP_W, h, SSR_C_PANEL, SSR_C_PANEL_EDGE);
      m_w.Label("title", m_x + 12, m_y + 9, T(SSR_S_SU_NEW_REPLAY),
                SSR_C_TEXT, SSR_FS_BODY);

      int by = m_y + 34;
      if(have_last)
        {
         m_w.ButtonC("qlast", m_x + 12, by, SSR_SETUP_W - 24, 26,
                     T(SSR_S_SU_SAME_AS_LAST),
                     SSR_C_PRIMARY, SSR_C_PRIMARY_EDGE,
                     SSR_C_PRIMARY_TEXT, SSR_FS_BODY);
         m_w.Label("qlastd", m_x + 14, by + 29,
                   StringFormat(T(SSR_S_SU_SUMMARY),
                                SSRSetupTfName(m_v.chart_tf),
                                SSRSetupBlindName(m_v.blind),
                                DoubleToString(m_v.balance, 2),
                                m_v.risk_percent),
                   SSR_C_TEXT_DIM, SSR_FS_SMALL);
         by += 46;
        }
      else
        { m_w.Remove("qlast"); m_w.Remove("qlastd"); }

      if(have_session)
        {
         m_w.Button("qcont", m_x + 12, by, SSR_SETUP_W - 24, 26,
                    T(SSR_S_SU_CONTINUE) + m_v.session_name + "\"");
         m_w.Label("qcontd", m_x + 14, by + 29,
                   T(SSR_S_SU_CONTINUE_WHY),
                   SSR_C_TEXT_DIM, SSR_FS_SMALL);
         by += 46;
        }
      else
        { m_w.Remove("qcont"); m_w.Remove("qcontd"); }

      m_w.Button("qrand", m_x + 12, by, SSR_SETUP_W - 24, 26,
                 T(SSR_S_SU_RANDOM));
      m_w.Label("qrandd", m_x + 14, by + 29,
                T(SSR_S_SU_RANDOM_WHY),
                SSR_C_TEXT_DIM, SSR_FS_SMALL);
      by += 46;

      m_w.Button("qcust", m_x + 12, by + 4, SSR_SETUP_W - 24, 22,
                 T(SSR_S_SU_CUSTOMISE));
     }

   void              RenderSettings(void)
     {
      int rows = 17;
      int h    = 30 + rows * SSR_SETUP_ROW + 44;
      m_w.Rect("frame", m_x, m_y, SSR_SETUP_W, h, SSR_C_PANEL, SSR_C_PANEL_EDGE);
      m_w.Label("title", m_x + 12, m_y + 9, T(SSR_S_SU_SETTINGS),
                SSR_C_TEXT, SSR_FS_BODY);
      m_w.Label("stepn", m_x + SSR_SETUP_W - 52, m_y + 10, StringFormat(T(SSR_S_SU_STEP), 1),
                SSR_C_TEXT_FAINT, SSR_FS_SMALL);

      int r = 0;
      m_w.Label("h1", m_x + 12, m_y + 30 + r * SSR_SETUP_ROW + 5, T(SSR_S_SU_ACCOUNT),
                SSR_C_TEXT_DIM, SSR_FS_SMALL); r++;
      Row("bal",  r++, "Balance",          DoubleToString(m_v.balance, 2),      true);
      Row("risk", r++, "Risk per trade %", DoubleToString(m_v.risk_percent, 2), true);
      Row("spr",  r++, "Spread, points",   DoubleToString(m_v.spread_points, 1),true);

      m_w.Label("h2", m_x + 12, m_y + 30 + r * SSR_SETUP_ROW + 5, T(SSR_S_SU_REPLAY),
                SSR_C_TEXT_DIM, SSR_FS_SMALL); r++;
      Row("spd",  r++, "Speed",            DoubleToString(m_v.speed, 0),        true);
      Row("tf",   r++, "Chart timeframe",  SSRSetupTfName(m_v.chart_tf),        false);
      Row("xtf",  r++, "Extra timeframes", m_v.extra_tfs,                       true);
      Row("bl",   r++, "Blind mode",       SSRSetupBlindName(m_v.blind),        false);

      m_w.Label("h3", m_x + 12, m_y + 30 + r * SSR_SETUP_ROW + 5, T(SSR_S_SU_EVALUATION),
                SSR_C_TEXT_DIM, SSR_FS_SMALL); r++;
      //--- ONE CLICK INSTEAD OF THREE NUMBERS. Nobody remembers what a
      //--- given firm's daily loss limit is, and nobody should have to.
      Row("pre",  r++, "Preset",           PresetName(),                        false);
      Row("pon",  r++, "Prop evaluation",  m_v.prop_on ? "on" : "off",          false);
      Row("ptg",  r++, "Profit target %",  DoubleToString(m_v.prop_target, 1),  true,
          m_force_prop);
      Row("pdl",  r++, "Max daily loss %", DoubleToString(m_v.prop_daily, 1),   true,
          m_force_prop);
      Row("ptl",  r++, "Max drawdown %",   DoubleToString(m_v.prop_total, 1),   true,
          m_force_prop);

      m_w.Label("h4", m_x + 12, m_y + 30 + r * SSR_SETUP_ROW + 5, T(SSR_S_SU_SESSION),
                SSR_C_TEXT_DIM, SSR_FS_SMALL); r++;
      Row("ses",  r++, "Save as",          m_v.session_name,                    true);

      //--- NOTHING ON THIS STEP CAN START A REPLAY. That is the point.
      int by = m_y + 30 + r * SSR_SETUP_ROW + 8;
      m_w.ButtonC("next", m_x + 12, by, SSR_SETUP_W - 24, 26,
                  T(SSR_S_SU_NEXT_MODE),
                  SSR_C_PRIMARY, SSR_C_PRIMARY_EDGE,
                  SSR_C_PRIMARY_TEXT, SSR_FS_BODY);
      m_w.Button("back", m_x + 12, by + 30, SSR_SETUP_W - 24, 20, T(SSR_S_SU_BACK));
     }

   //+------------------------------------------------------------------+
   //| STEP 2 - MODE.                                                   |
   //|                                                                  |
   //| The single biggest progressive-disclosure lever in the product:  |
   //| what is chosen here decides which sheets the session gets. A     |
   //| Standard session never draws a prop meter, and never has to      |
   //| explain one.                                                      |
   //|                                                                  |
   //| Each one says what it DOES, not what it is called. "Blind" means |
   //| nothing to somebody who has not used one.                         |
   //+------------------------------------------------------------------+
   void              RenderMode(void)
     {
      int h = 34 + 4 * 48 + 62;
      m_w.Rect("frame", m_x, m_y, SSR_SETUP_W, h, SSR_C_PANEL, SSR_C_PANEL_EDGE);
      m_w.Label("title", m_x + 12, m_y + 9, T(SSR_S_SU_MODE),
                SSR_C_TEXT, SSR_FS_BODY);
      m_w.Label("stepn", m_x + SSR_SETUP_W - 52, m_y + 10, StringFormat(T(SSR_S_SU_STEP), 2),
                SSR_C_TEXT_FAINT, SSR_FS_SMALL);

      string names[] = {"Standard", "Blind", "Prop challenge", "Random practice"};
      string what[]  = {"practise normally",
                        "the future stays hidden until you finish",
                        "rules enforced, progress shown",
                        "a start you have not seen, with a seed"};
      int now = ModeNow();

      for(int i = 0; i < 4; i++)
        {
         string id = "md" + IntegerToString(i);
         int    ry = m_y + 34 + i * 48;
         if(i == now)
            m_w.ButtonC(id, m_x + 12, ry, SSR_SETUP_W - 24, 26, names[i],
                        SSR_C_PRIMARY, SSR_C_PRIMARY_EDGE,
                        SSR_C_PRIMARY_TEXT, SSR_FS_BODY);
         else
            m_w.Button(id, m_x + 12, ry, SSR_SETUP_W - 24, 26, names[i]);
         m_w.Label(id + "d", m_x + 14, ry + 29, what[i],
                   SSR_C_TEXT_DIM, SSR_FS_SMALL);
        }

      int by = m_y + 34 + 4 * 48 + 6;
      m_w.ButtonC("next", m_x + 12, by, SSR_SETUP_W - 24, 26,
                  T(SSR_S_SU_NEXT_START),
                  SSR_C_PRIMARY, SSR_C_PRIMARY_EDGE,
                  SSR_C_PRIMARY_TEXT, SSR_FS_BODY);
      m_w.Button("back", m_x + 12, by + 30, SSR_SETUP_W - 24, 20, T(SSR_S_SU_BACK));
     }

   void              RenderStart(void)
     {
      int rows = 10 + (m_v.random_start ? 2 : 0);
      int h    = 30 + rows * SSR_SETUP_ROW + 92;
      m_w.Rect("frame", m_x, m_y, SSR_SETUP_W, h, SSR_C_PANEL, SSR_C_PANEL_EDGE);
      m_w.Label("title", m_x + 12, m_y + 9, T(SSR_S_SU_WHERE),
                SSR_C_TEXT, SSR_FS_BODY);
      m_w.Label("stepn", m_x + SSR_SETUP_W - 52, m_y + 10, StringFormat(T(SSR_S_SU_STEP), 3),
                SSR_C_TEXT_FAINT, SSR_FS_SMALL);

      //--- read back what step 1 was told, so the confirmation is one
      //--- and not a press into the dark
      int r = 0;
      m_w.Label("h1", m_x + 12, m_y + 30 + r * SSR_SETUP_ROW + 5, T(SSR_S_SU_YOU_CHOSE),
                SSR_C_TEXT_DIM, SSR_FS_SMALL); r++;
      Recap("bal2",  r++, "Balance",   DoubleToString(m_v.balance, 2));
      Recap("risk2", r++, "Risk",      StringFormat("%.2f %%", m_v.risk_percent));
      Recap("spd2",  r++, "Speed",     StringFormat("%.0fx", m_v.speed));
      Recap("tf2",   r++, "Timeframe", SSRSetupTfName(m_v.chart_tf) +
                                       (m_v.extra_tfs != "" ? " +" + m_v.extra_tfs : ""));
      Recap("bl2",   r++, "Blind mode", SSRSetupBlindName(m_v.blind),
            m_v.blind ? SSR_C_HOLD : SSR_C_TEXT_DIM);
      Recap("pon2",  r++, "Evaluation",
            m_v.prop_on ? StringFormat("%.1f / %.1f / %.1f %%", m_v.prop_target,
                                       m_v.prop_daily, m_v.prop_total)
                        : "off",
            m_v.prop_on ? SSR_C_RUN : SSR_C_TEXT_DIM);
      Recap("rnd2",  r++, "Random start",
            m_v.random_start ? (m_v.seed == "" ? "yes, new seed"
                                               : "yes, seed " + m_v.seed)
                             : "no",
            m_v.random_start ? SSR_C_HOLD : SSR_C_TEXT_DIM);
      Recap("ses2",  r++, "Save as",
            m_v.session_name == "" ? "not saved" : m_v.session_name,
            m_v.session_name == "" ? SSR_C_TEXT_DIM : SSR_C_TEXT);

      //+------------------------------------------------------------------+
      //| THE SEED, WHERE IT CAN BE COPIED.                                |
      //|                                                                  |
      //| An OBJ_EDIT rather than a label, because the point of a seed is  |
      //| to leave this machine: to a student, into a lesson plan, into a  |
      //| bug report that says "this is the session that broke it". A      |
      //| label cannot be selected, and a seed nobody can copy is a        |
      //| reproducibility feature nobody can use.                          |
      //|                                                                  |
      //| Blank means "pick a new one and tell me what it was" - the       |
      //| expert prints it, and it comes back here next time.               |
      //+------------------------------------------------------------------+
      if(m_v.random_start)
        {
         m_w.Label("h3", m_x + 12, m_y + 30 + r * SSR_SETUP_ROW + 5,
                   T(SSR_S_SU_SEED),
                   SSR_C_TEXT_DIM, SSR_FS_SMALL); r++;
         int sy = m_y + 30 + r * SSR_SETUP_ROW;
         m_w.Edit("eseed", m_x + 12, sy, SSR_SETUP_W - 24, SSR_SETUP_ROW - 4,
                  m_v.seed, m_first_paint);
         m_w.Hide("eseed", false);
         r++;
        }
      else
        { m_w.Remove("h3"); m_w.Remove("eseed"); }

      m_w.Label("h2", m_x + 12, m_y + 30 + r * SSR_SETUP_ROW + 5,
                T(SSR_S_SU_ORANGE_LINE),
                SSR_C_TEXT_DIM, SSR_FS_SMALL); r++;

      int by = m_y + 30 + r * SSR_SETUP_ROW + 4;
      m_w.Button("here", m_x + 12, by, SSR_SETUP_W - 24, 22,
                 T(SSR_S_SU_BRING_LINE));
      m_start_y = by + 26;
      m_w.Label("startlbl", m_x + 12, m_start_y,
                (m_start_text == "" ? T(SSR_S_SU_DRAG_LINE) : m_start_text),
                SSR_C_HOLD, SSR_FS_SMALL);

      //--- the irreversible one, on its own, with the way back beside it
      int gy = by + 42;
      m_w.Button("back", m_x + 12, gy, 74, 26, T(SSR_S_SU_BACK));
      m_w.ButtonC("go", m_x + 92, gy, SSR_SETUP_W - 104, 26,
                  T(SSR_S_SU_START_HERE), SSR_C_BUY, SSR_C_BUY_EDGE,
                  SSR_C_DEAL_TEXT, SSR_FS_BODY);
     }

   //+------------------------------------------------------------------+
   //| DRAG IT BY ITS CAPTION, the way every other window on the screen |
   //| moves. The main panel has done this since v40; this one had no   |
   //| way to be moved at all, so a setup form that landed over the     |
   //| candles you were trying to read stayed there.                    |
   //|                                                                  |
   //| Chart scrolling is suspended for the duration, or the price      |
   //| behind the panel travels with it.                                |
   //+------------------------------------------------------------------+
   bool              OnChartEvent(const int id, const long lparam,
                                  const double dparam, const string sparam)
     {
      if(!m_open || id != CHARTEVENT_MOUSE_MOVE)
         return false;

      int  mx   = (int)lparam;
      int  my   = (int)dparam;
      bool down = (StringToInteger(sparam) & 1) != 0;

      if(!down)
        {
         if(m_drag)
           {
            m_drag = false;
            ChartSetInteger(m_chart, CHART_MOUSE_SCROLL, true);
            SavePlace();
           }
         return false;
        }

      if(!m_drag &&
         mx >= m_x && mx <= m_x + SSR_SETUP_W &&
         my >= m_y && my <= m_y + 26)
        {
         m_drag    = true;
         m_drag_dx = mx - m_x;
         m_drag_dy = my - m_y;
         ChartSetInteger(m_chart, CHART_MOUSE_SCROLL, false);
         return true;
        }

      if(m_drag)
        {
         m_x = mx - m_drag_dx;
         m_y = my - m_drag_dy;
         if(m_x < 0) m_x = 0;
         if(m_y < 0) m_y = 0;
         //--- always leave the caption reachable
         int cw = (int)ChartGetInteger(m_chart, CHART_WIDTH_IN_PIXELS);
         int ch = (int)ChartGetInteger(m_chart, CHART_HEIGHT_IN_PIXELS);
         if(cw > 0 && m_x > cw - 80) m_x = cw - 80;
         if(ch > 0 && m_y > ch - 30) m_y = ch - 30;
         Render();
         ChartRedraw(m_chart);
         return true;
        }
      return false;
     }

   //--- where the user left it, so it opens there next time
   void              SavePlace(void)
     {
      GlobalVariableSet("SSR_SETUP_X", (double)m_x);
      GlobalVariableSet("SSR_SETUP_Y", (double)m_y);
      m_placed = true;
     }
   void              LoadPlace(void)
     {
      //--- a position the USER chose outranks the centre. m_placed is
      //--- what tells Open the difference between "never moved" and
      //--- "moved back to roughly the middle" - not the same thing.
      if(GlobalVariableCheck("SSR_SETUP_X"))
        { m_x = (int)GlobalVariableGet("SSR_SETUP_X"); m_placed = true; }
      if(GlobalVariableCheck("SSR_SETUP_Y"))
        { m_y = (int)GlobalVariableGet("SSR_SETUP_Y"); m_placed = true; }
      if(m_x < 0) m_x = 0;
      if(m_y < 0) m_y = 0;
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

      //--- STEP CHANGES REPAINT FROM SCRATCH. The edit boxes only get
      //--- their text written on a first paint - otherwise a repaint
      //--- would delete what somebody is halfway through typing - so a
      //--- step that comes back to a cleared chart has to be told that
      //--- this paint IS a first one, or the boxes come back empty.
      //--- QUICK START. Each of these lands on the step it makes sense
      //--- to land on, which for two of them is the last one.
      if(m_w.Pressed("qlast"))
        { m_step = 3; Repaint(); return ""; }
      if(m_w.Pressed("qcont"))
        { m_step = 3; Repaint(); return ""; }
      if(m_w.Pressed("qrand"))
        {
         ApplyMode(3);                    // random, with a fresh seed
         m_v.seed = "";
         m_step = 3; Repaint(); return "";
        }
      if(m_w.Pressed("qcust"))
        { m_step = 1; Repaint(); return ""; }

      //--- MODE. Applied immediately, because the value it shows IS the
      //--- setting - the same rule the cycling fields have always used.
      for(int mi = 0; mi < 4; mi++)
         if(m_w.Pressed("md" + IntegerToString(mi)))
           { ApplyMode(mi); Repaint(); return ""; }

      if(m_w.Pressed("next"))
        {
         ReadAll();
         m_step++;
         Repaint();
         return "";
        }
      if(m_w.Pressed("back"))
        {
         m_step--;
         if(m_step < 0) m_step = 0;
         Repaint();
         return "";
        }

      if(m_w.Pressed("go"))    { ReadAll(); return "go";   }
      if(m_w.Pressed("here"))  { return "here"; }

      //--- the cycling buttons act immediately, because the value they
      //--- show IS the setting; nothing to confirm
      //--- a chosen option, if a list is open. Checked BEFORE the fields
      //--- so a click that lands on a list item is not also read as a
      //--- click on whatever the list is covering.
      if(m_menu != "")
        {
         string opts[];
         int n = MenuOptions(m_menu, opts);
         for(int i = 0; i < n; i++)
            if(m_w.Pressed("m" + IntegerToString(i)))
              {
               Choose(m_menu, i);
               m_menu = "";
               Render();
               return "";
              }
        }

      //--- the fields. Pressing the open one closes it, which is what a
      //--- second click on a combo box does everywhere else.
      if(m_w.Pressed("btf"))  { m_menu = (m_menu == "tf"  ? "" : "tf");  Render(); }
      if(m_w.Pressed("bbl"))  { m_menu = (m_menu == "bl"  ? "" : "bl");  Render(); }
      if(m_w.Pressed("bpre")) { m_menu = (m_menu == "pre" ? "" : "pre"); Render(); }
      if(m_w.Pressed("bpon")) { m_menu = (m_menu == "pon" ? "" : "pon"); Render(); }
      return "";
     }

   //+------------------------------------------------------------------+
   //| MODE IS A SHORTCUT, NOT A SETTING.                               |
   //|                                                                  |
   //| Choosing one writes the settings that already exist - blind,     |
   //| prop_on, random_start - and nothing else. There is no `mode`     |
   //| field, because a fifth source of truth that has to agree with    |
   //| four others is the thing that eventually disagrees.               |
   //|                                                                  |
   //| Which also means the modes are not exclusive by decree: a Prop   |
   //| challenge run blind is a real thing to practise, and the panel    |
   //| shows both chips because both settings are on.                    |
   //+------------------------------------------------------------------+
   void              ApplyMode(const int m)
     {
      switch(m)
        {
         case 0:                        // Standard
            m_v.blind = SSR_BLIND_OFF; m_v.prop_on = false;
            m_v.random_start = false;   break;
         case 1:                        // Blind
            m_v.blind = SSR_BLIND_STANDARD; m_v.prop_on = false;
            m_v.random_start = false;   break;
         case 2:                        // Prop
            m_v.blind = SSR_BLIND_OFF; m_v.prop_on = true;
            m_v.random_start = false;   break;
         case 3:                        // Random practice
            m_v.blind = SSR_BLIND_OFF; m_v.prop_on = false;
            m_v.random_start = true;    break;
        }
     }

   //--- which mode the CURRENT settings add up to, so the step opens on
   //--- what is true rather than on what was last clicked
   int               ModeNow(void)
     {
      if(m_v.random_start)              return 3;
      if(m_v.prop_on)                   return 2;
      if(m_v.blind != SSR_BLIND_OFF)    return 1;
      return 0;
     }

   //--- one place that turns "the third item" into a setting
   void              Choose(const string id, const int i)
     {
      if(id == "tf" && i >= 0 && i < ArraySize(SSR_SETUP_TFS))
        { m_tf_i = i; m_v.chart_tf = SSR_SETUP_TFS[i]; return; }
      if(id == "bl")
        {
         m_v.blind = (i == 1 ? SSR_BLIND_STANDARD
                             : (i == 2 ? SSR_BLIND_FULL : SSR_BLIND_OFF));
         return;
        }
      if(id == "pon")
        { m_v.prop_on = (i == 1); return; }
      if(id == "pre")
         ApplyPreset(i);
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

      //--- the seed box only exists on the start step in random mode, and
      //--- EditText returns "" for a box that is not there - which would
      //--- silently wipe a seed the user typed and then stepped back from.
      //--- Read only when it is on screen.
      if(m_v.random_start && m_w.Exists("eseed"))
        {
         string sd = m_w.EditText("eseed");
         StringTrimLeft(sd); StringTrimRight(sd);
         m_v.seed = sd;
        }

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
      f.SetInt   ("random",    v.random_start ? 1 : 0);
      f.Set      ("seed",      v.seed);
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
      v.random_start  = (f.GetInt("random", v.random_start ? 1 : 0) != 0);
      v.seed          = f.Get("seed", v.seed);
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

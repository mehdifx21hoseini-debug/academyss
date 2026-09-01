//+------------------------------------------------------------------+
//|                                            SSR_QA_FontProbe.mq5  |
//|                    SS Replay - which font does WINDOWS give us?  |
//|                                                                  |
//|  The panel draws with OBJ_LABEL + OBJPROP_FONT. We hand Windows  |
//|  a font NAME; Windows decides what to render. If the name is not |
//|  installed it substitutes another face and returns no error at   |
//|  all - the label just quietly comes out in something else.       |
//|                                                                  |
//|  That is the exact class of bug this project keeps paying for:   |
//|  work that did not happen must SAY it did not happen. So before  |
//|  a single font name is written into SSR_Theme.mqh, this script   |
//|  answers three questions ON THE MACHINE THAT WILL RUN IT:        |
//|                                                                  |
//|    1. Is the font actually installed, or silently substituted?   |
//|    2. What does it LOOK like at the panel's real sizes?          |
//|    3. Do the panel's real strings still FIT?                     |
//|                                                                  |
//|  HOW SUBSTITUTION IS DETECTED, and what it cannot prove:         |
//|  A deliberately impossible font name is measured first. Windows  |
//|  substitutes it, so its metrics ARE the fallback's metrics. Any  |
//|  candidate whose metrics match that fingerprint exactly is       |
//|  either not installed, or IS the fallback face. The script says  |
//|  exactly that instead of guessing which - see CANNOT PROVE.      |
//|                                                                  |
//|  It cleans up after itself: every object it draws is removed.    |
//+------------------------------------------------------------------+
#property script_show_inputs
#property description "Shows the candidate panel fonts at their real sizes and reports which are truly installed."

#include <SSReplay/Common/SSR_Build.mqh>

input string InpFonts    = "Segoe UI,Tahoma,Verdana,Microsoft Sans Serif,Consolas,Lucida Console,Courier New"; // Fonts to probe (comma separated)
input int    InpHoldSec  = 90;    // Seconds to leave the sample on the chart (0 = draw and exit)
input bool   InpDraw     = true;  // Draw the visual sample (off = report only)

#define PFX      "SSRFP_"
#define IMPOSSIBLE "ZZ_SSR_No_Such_Face_4711"   // no machine has this

//--- the panel's real point sizes, from SSR_Theme.mqh
#define FS_SMALL  7
#define FS_BODY   8
#define FS_TITLE  9
#define FS_CLOCK 14
//--- fingerprints are taken large, where faces differ most
#define FS_PRINT 24

int    g_objs = 0;

//+------------------------------------------------------------------+
//| Measure one string in one font at one POINT size.                |
//|                                                                  |
//| Negative size means tenths of a point and follows the OS font    |
//| scaling - which is what OBJPROP_FONTSIZE does. Measuring in      |
//| pixels instead would give numbers that are right on a 100%       |
//| display and wrong on every other one.                            |
//+------------------------------------------------------------------+
bool MeasurePt(const string font, const int pt, const string text,
               uint &w, uint &h)
  {
   w = 0; h = 0;
   if(!TextSetFont(font, -pt * 10, 0, 0))
      return false;
   return TextGetSize(text, w, h);
  }

//+------------------------------------------------------------------+
//| A metric fingerprint: several strings chosen because different   |
//| faces disagree about them the most - wide caps, narrow lowercase,|
//| digits, and a real panel label.                                  |
//+------------------------------------------------------------------+
string Fingerprint(const string font, uint &mono_wide, uint &mono_narrow)
  {
   string probes[5] = {"MMMMMMMMMM", "iiiiiiiiii", "0123456789",
                       "Close all",  "WWWggg"};
   string fp = "";
   mono_wide = 0; mono_narrow = 0;
   for(int i = 0; i < 5; i++)
     {
      uint w = 0, h = 0;
      if(!MeasurePt(font, FS_PRINT, probes[i], w, h))
         return "MEASURE_FAILED";
      fp += IntegerToString((int)w) + "x" + IntegerToString((int)h) + " ";
      if(i == 0) mono_wide   = w;
      if(i == 1) mono_narrow = w;
     }
   return fp;
  }

//+------------------------------------------------------------------+
//| Drawing helpers. Nothing here is selectable - the sample must    |
//| not become something the user has to clean up by hand.           |
//+------------------------------------------------------------------+
void Rect(const string id, const int x, const int y, const int w, const int h,
          const color bg, const color border)
  {
   string n = PFX + id;
   if(ObjectCreate(0, n, OBJ_RECTANGLE_LABEL, 0, 0, 0)) g_objs++;
   ObjectSetInteger(0, n, OBJPROP_CORNER,      CORNER_LEFT_UPPER);
   ObjectSetInteger(0, n, OBJPROP_XDISTANCE,   x);
   ObjectSetInteger(0, n, OBJPROP_YDISTANCE,   y);
   ObjectSetInteger(0, n, OBJPROP_XSIZE,       w);
   ObjectSetInteger(0, n, OBJPROP_YSIZE,       h);
   ObjectSetInteger(0, n, OBJPROP_BGCOLOR,     bg);
   ObjectSetInteger(0, n, OBJPROP_BORDER_TYPE, BORDER_FLAT);
   ObjectSetInteger(0, n, OBJPROP_COLOR,       border);
   ObjectSetInteger(0, n, OBJPROP_BACK,        false);
   ObjectSetInteger(0, n, OBJPROP_SELECTABLE,  false);
   ObjectSetInteger(0, n, OBJPROP_HIDDEN,      true);
  }

void Lbl(const string id, const int x, const int y, const string text,
         const string font, const int pt, const color col)
  {
   string n = PFX + id;
   if(ObjectCreate(0, n, OBJ_LABEL, 0, 0, 0)) g_objs++;
   ObjectSetInteger(0, n, OBJPROP_CORNER,     CORNER_LEFT_UPPER);
   ObjectSetInteger(0, n, OBJPROP_ANCHOR,     ANCHOR_LEFT_UPPER);
   ObjectSetInteger(0, n, OBJPROP_XDISTANCE,  x);
   ObjectSetInteger(0, n, OBJPROP_YDISTANCE,  y);
   ObjectSetInteger(0, n, OBJPROP_COLOR,      col);
   ObjectSetInteger(0, n, OBJPROP_FONTSIZE,   pt);
   ObjectSetString (0, n, OBJPROP_FONT,       font);
   ObjectSetString (0, n, OBJPROP_TEXT,       text);
   ObjectSetInteger(0, n, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, n, OBJPROP_HIDDEN,     true);
  }

void Cleanup(void)
  {
   ObjectsDeleteAll(0, PFX);
   ChartRedraw(0);
  }

//+------------------------------------------------------------------+
//| One sample block, drawn on the panel's own light background so   |
//| the contrast is the contrast the panel will really have.         |
//+------------------------------------------------------------------+
void DrawBlock(const int idx, const string font, const int x, const int y,
               const int w, const int h, const string verdict)
  {
   string t = IntegerToString(idx);
   Rect("bg" + t, x, y, w, h, C'240,240,240', C'111,114,118');
   int cy = y + 6;
   Lbl("f" + t, x + 8, cy, font + "   [" + verdict + "]",
       font, FS_TITLE, C'0,0,0');                       cy += 19;
   Lbl("a" + t, x + 8, cy, "Risk per trade   Stop   Target   Close all",
       font, FS_BODY, C'26,26,26');                     cy += 16;
   Lbl("b" + t, x + 8, cy, "38% - 1d 09:20 left - Ambiguous fills 2",
       font, FS_SMALL, C'85,85,85');                    cy += 16;
   Lbl("c" + t, x + 8, cy, "2026.08.27  14:35:00",
       font, FS_CLOCK, C'0,0,0');                       cy += 26;
   Lbl("d" + t, x + 8, cy, "53 671.4   -186.20   +1.4 R   0.04 lot",
       font, FS_BODY, C'34,34,34');
  }

//+------------------------------------------------------------------+
//| Do this font's DIGITS all have the same width?                   |
//|                                                                  |
//| This decides whether the panel needs a monospaced font for       |
//| numbers at all. A value that changes in place - the clock, the   |
//| price, floating P/L - jitters only if its digits are different   |
//| widths. Most classic screen faces (Tahoma, Segoe UI, Verdana)    |
//| draw every digit on the same advance width on purpose, exactly   |
//| so tables line up. If that holds here, the second font is not    |
//| buying us anything and one face is both simpler AND better.      |
//|                                                                  |
//| Measured, not assumed. I have been wrong about this class of     |
//| thing often enough to stop guessing.                             |
//+------------------------------------------------------------------+
void DigitReport(const string font)
  {
   uint wmin = 0xFFFFFFFF, wmax = 0, w = 0, h = 0;
   int  bad = -1;
   for(int d = 0; d < 10; d++)
     {
      if(!MeasurePt(font, FS_PRINT, IntegerToString(d), w, h))
        { Print("      digits: measure failed"); return; }
      if(w < wmin) wmin = w;
      if(w > wmax) { wmax = w; bad = d; }
     }

   //--- the practical test: two prices the panel really shows. If these
   //--- differ, the number moves sideways every time it updates.
   uint p1 = 0, p2 = 0;
   MeasurePt(font, FS_BODY, "53 671.4", p1, h);
   MeasurePt(font, FS_BODY, "53 999.9", p2, h);

   if(wmin == wmax)
      PrintFormat("      digits: TABULAR (all 10 are %dpx at %dpt) - "
                  "numbers will not jitter. A mono font is not needed here.",
                  (int)wmax, FS_PRINT);
   else
      PrintFormat("      digits: PROPORTIONAL (%d..%dpx, widest is '%d') - "
                  "a changing number WILL shift sideways.",
                  (int)wmin, (int)wmax, bad);

   PrintFormat("      price width \"53 671.4\"=%dpx vs \"53 999.9\"=%dpx  -> %s",
               (int)p1, (int)p2,
               (p1 == p2 ? "stable" : "JITTERS"));
  }

//+------------------------------------------------------------------+
//| Widths of strings the panel really draws, against the space it   |
//| really has. A font that reads beautifully and overflows the      |
//| button is not a better font.                                     |
//+------------------------------------------------------------------+
void FitReport(const string font)
  {
   string s[6];  int    pt[6];  int budget[6];
   s[0] = "FOL 2";                                   pt[0] = FS_BODY;  budget[0] = 40;
   s[1] = "PLAY";                                    pt[1] = FS_BODY;  budget[1] = 40;
   s[2] = "Risk per trade";                          pt[2] = FS_BODY;  budget[2] = 120;
   s[3] = "2026.08.27  14:35:00";                    pt[3] = FS_CLOCK; budget[3] = 404;
   s[4] = "38% - 1d 09:20 left";                     pt[4] = FS_SMALL; budget[4] = 204;
   s[5] = "Ambiguous fills 2 (5.4 %)";               pt[5] = FS_SMALL; budget[5] = 204;

   string line = "";
   int    over = 0;
   for(int i = 0; i < 6; i++)
     {
      uint w = 0, h = 0;
      if(!MeasurePt(font, pt[i], s[i], w, h))
        { line += " [measure failed]"; continue; }
      bool bad = ((int)w > budget[i]);
      if(bad) over++;
      line += StringFormat("  %s=%dpx/%d%s", s[i], (int)w, budget[i],
                           (bad ? " OVER" : ""));
     }
   PrintFormat("      fit:%s", line);
   if(over > 0)
      PrintFormat("      ^^ %d string(s) do NOT fit the space the panel gives them", over);
  }

//+------------------------------------------------------------------+
void OnStart()
  {
   //--- clear anything a previous run left behind. This is also what
   //--- makes "run again with InpDraw=false" a real way to clean up.
   ObjectsDeleteAll(0, PFX);

   PrintFormat("=== SS Replay - Font Probe === build %s", SSR_BUILD);
   PrintFormat("terminal dpi=%d  chart=%dx%d",
               (int)TerminalInfoInteger(TERMINAL_SCREEN_DPI),
               (int)ChartGetInteger(0, CHART_WIDTH_IN_PIXELS),
               (int)ChartGetInteger(0, CHART_HEIGHT_IN_PIXELS));

   //--- the fallback's own fingerprint, measured from a name that
   //--- cannot exist. Everything below is compared against this.
   uint dummy_a = 0, dummy_b = 0;
   string base_fp = Fingerprint(IMPOSSIBLE, dummy_a, dummy_b);
   PrintFormat("fallback fingerprint (from \"%s\"): %s", IMPOSSIBLE, base_fp);
   if(base_fp == "MEASURE_FAILED")
     {
      Print("STOPPED - TextGetSize failed on this terminal. Nothing was measured.");
      return;
     }

   string names[];
   int n = StringSplit(InpFonts, StringGetCharacter(",", 0), names);
   if(n <= 0)
     {
      Print("STOPPED - InpFonts is empty. Nothing was measured.");
      return;
     }

   string fps[];       ArrayResize(fps, n);
   string verdicts[];  ArrayResize(verdicts, n);
   int    installed = 0, unproven = 0;

   Print("--- fonts ---");
   for(int i = 0; i < n; i++)
     {
      StringTrimLeft(names[i]);
      StringTrimRight(names[i]);
      if(names[i] == "") { fps[i] = ""; verdicts[i] = "EMPTY"; continue; }

      uint wide = 0, narrow = 0;
      fps[i] = Fingerprint(names[i], wide, narrow);

      if(fps[i] == "MEASURE_FAILED")
         verdicts[i] = "MEASURE FAILED";
      else
         if(fps[i] == base_fp)
           { verdicts[i] = "CANNOT PROVE"; unproven++; }
         else
           { verdicts[i] = "INSTALLED";    installed++; }

      string kind = (wide > 0 && wide == narrow) ? "monospaced" : "proportional";
      PrintFormat("  %-24s %-14s %s   [%s]",
                  names[i], verdicts[i], fps[i], kind);
      if(verdicts[i] == "CANNOT PROVE")
         Print("      ^^ identical to the fallback: either NOT installed, "
               "or it IS the face Windows falls back to. This probe cannot tell which.");
      if(verdicts[i] != "MEASURE FAILED" && verdicts[i] != "EMPTY")
        {
         DigitReport(names[i]);
         FitReport(names[i]);
        }
     }

   //--- two different names that measure identically mean at least
   //--- one of them is not the face we asked for.
   for(int i = 0; i < n; i++)
      for(int j = i + 1; j < n; j++)
         if(fps[i] != "" && fps[i] != "MEASURE_FAILED" && fps[i] == fps[j])
            PrintFormat("  COLLISION: \"%s\" and \"%s\" measure identically - "
                        "at least one is being substituted.", names[i], names[j]);

   PrintFormat("--- %d installed, %d cannot prove, of %d asked ---",
               installed, unproven, n);

   if(!InpDraw)
     {
      ChartRedraw(0);
      Print("InpDraw=false - nothing was drawn, and any earlier sample was removed. "
            "Metrics above are still real.");
      return;
     }

   //--- draw ----------------------------------------------------------
   int bw = 340, bh = 106, gap = 8, per_col = 4;
   for(int i = 0; i < n; i++)
     {
      if(verdicts[i] == "EMPTY") continue;
      int col = i / per_col, row = i % per_col;
      DrawBlock(i, names[i], 14 + col * (bw + gap), 24 + row * (bh + gap),
                bw, bh, verdicts[i]);
     }
   ChartRedraw(0);
   PrintFormat("drew %d objects. TAKE A SCREENSHOT NOW.", g_objs);

   if(InpHoldSec <= 0)
     {
      Print("InpHoldSec=0 - the sample was LEFT ON THE CHART. "
            "Run this script again with InpDraw=false to remove it.");
      return;
     }

   PrintFormat("holding %d seconds, then removing. Press the stop button to remove now.",
               InpHoldSec);
   for(int waited = 0; waited < InpHoldSec * 1000 && !IsStopped(); waited += 250)
      Sleep(250);

   Cleanup();
   Print("sample removed. Chart is clean.");
  }
//+------------------------------------------------------------------+

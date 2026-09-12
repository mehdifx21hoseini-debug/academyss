//+------------------------------------------------------------------+
//|                                                  SSR_Widgets.mqh |
//|                       SS Replay - Chart Object Widgets (UI)      |
//|                                                                  |
//|  Thin wrappers over MetaTrader's graphical objects. Every widget |
//|  carries the panel's prefix so teardown can remove all of them   |
//|  by name - an orphaned label left on a user's chart after the    |
//|  panel is gone is the sort of thing they have to clean by hand.  |
//|                                                                  |
//|  All widgets are non-selectable and pinned to a chart corner, so |
//|  a stray drag can never leave a control floating in the price.   |
//+------------------------------------------------------------------+
#ifndef SSR_WIDGETS_MQH
#define SSR_WIDGETS_MQH

#include "SSR_Theme.mqh"

//+------------------------------------------------------------------+
class CSSRWidgets
  {
private:
   long              m_chart;
   string            m_prefix;
   int               m_created;

   //+------------------------------------------------------------------+
   //| DO NOT WRITE WHAT IS ALREADY THERE.                              |
   //|                                                                  |
   //| Phase 11 built the counter and refused to optimise against it,    |
   //| because nothing had been measured slow. The user's run measured   |
   //| it: 561 object properties written per STILL frame, and a mean     |
   //| repaint of 39.05 ms - against an engine that pumps every 40. One  |
   //| repaint was eating a whole pump interval, which is exactly what   |
   //| "the buttons work slowly" feels like from the outside.            |
   //|                                                                  |
   //| So each object remembers what was last written to it, and a call  |
   //| that would write the same thing returns instead. On a frame where |
   //| nothing changed that is 561 writes turned into 77 lookups.        |
   //|                                                                  |
   //| NO HASH, AND THEREFORE NO COLLISION. The numbers are mixed into   |
   //| one long, but the TEXT is kept and compared as a string. A hash   |
   //| collision here would silently leave the wrong word on a button    |
   //| on a trading panel, and "vanishingly unlikely" is not a property  |
   //| worth having in that sentence.                                    |
   //|                                                                  |
   //| THE DANGEROUS CASE IS DELETION, not drawing: an object removed    |
   //| behind the cache's back would never be recreated, because the     |
   //| cache would say "already correct". So Remove, RemoveAll and Hide  |
   //| all invalidate, and every draw checks ObjectFind as well - the    |
   //| early return needs BOTH "unchanged" and "still there".            |
   //+------------------------------------------------------------------+
   //--- open addressing, power of two, so the index is a mask not a mod
   #define SSR_W_SLOTS 512
   string            m_ck[SSR_W_SLOTS];    // object name, "" when free
   long              m_cn[SSR_W_SLOTS];    // the numbers, mixed
   string            m_ct[SSR_W_SLOTS];    // the text, kept whole

   int               Slot(const string name)
     {
      //--- FNV-1a over the name. Only used to CHOOSE a slot; the name
      //--- itself is compared before anything is trusted.
      ulong h = 1469598103934665603;
      int   n = StringLen(name);
      for(int i = 0; i < n; i++)
        {
         h ^= (ulong)StringGetCharacter(name, i);
         h *= 1099511628211;
        }
      int at = (int)(h & (SSR_W_SLOTS - 1));
      for(int probe = 0; probe < 8; probe++)
        {
         int k = (at + probe) & (SSR_W_SLOTS - 1);
         if(m_ck[k] == "" || m_ck[k] == name)
            return k;
        }
      return -1;                      // full run of probes: never cache
     }

   //--- true when this object already holds exactly this, and exists
   bool              Same(const string name, const long nums, const string text)
     {
      int k = Slot(name);
      if(k < 0 || m_ck[k] != name)
         return false;
      if(m_cn[k] != nums || m_ct[k] != text)
         return false;
      //--- the object could have been deleted by something that did not
      //--- go through Remove. Cheaper than nine writes, and the one
      //--- check that makes the whole cache safe.
      return (ObjectFind(m_chart, name) >= 0);
     }

   void              Keep(const string name, const long nums, const string text)
     {
      int k = Slot(name);
      if(k < 0)
         return;
      m_ck[k] = name;
      m_cn[k] = nums;
      m_ct[k] = text;
     }

   void              Forget(const string name)
     {
      int k = Slot(name);
      if(k >= 0 && m_ck[k] == name)
        { m_ck[k] = ""; m_cn[k] = 0; m_ct[k] = ""; }
     }

   void              ForgetAll(void)
     {
      for(int i = 0; i < SSR_W_SLOTS; i++)
        { m_ck[i] = ""; m_cn[i] = 0; m_ct[i] = ""; }
     }

   long              Mix(const long a, const long b) { return a * 1000003 + b; }

   //+------------------------------------------------------------------+
   //| WHAT THE PAINT ACTUALLY COSTS, COUNTED.                          |
   //|                                                                  |
   //| Phase 11's rule is that the paint budget may not grow, and until |
   //| now there was no number to compare against. "It feels the same"  |
   //| is not a measurement, and this panel gained a fifth tab, four    |
   //| meters, seven more position rows and 176 string lookups over     |
   //| Phases 2-10 without anyone being able to say what that cost.     |
   //|                                                                  |
   //| One counter, incremented where the writes actually happen, so a  |
   //| test can render a frame and report the exact figure on the       |
   //| user's own machine rather than on an assumption about it.         |
   //|                                                                  |
   //| NOTE WHAT THIS IS NOT: it is not an optimisation. Nothing here   |
   //| has been made faster, because nothing has been measured slow -   |
   //| and changing the paint on a hunch is the thing this project      |
   //| refuses to do. This is the instrument that would justify one.     |
   //+------------------------------------------------------------------+
   int               m_writes;

   void              Common(const string name)
     {
      ObjectSetInteger(m_chart, name, OBJPROP_CORNER,     CORNER_LEFT_UPPER);
      ObjectSetInteger(m_chart, name, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(m_chart, name, OBJPROP_SELECTED,   false);
      ObjectSetInteger(m_chart, name, OBJPROP_HIDDEN,     true);
      ObjectSetInteger(m_chart, name, OBJPROP_ZORDER,     100);
     }

public:
                     CSSRWidgets(void) : m_chart(0), m_prefix("SSR_"), m_created(0),
                                        m_writes(0) {}

   void              Attach(const long chart_id, const string prefix)
     {
      //--- a cache from another chart would answer for objects that are
      //--- not on this one
      if(m_chart != chart_id || m_prefix != prefix)
         ForgetAll();
      m_chart = chart_id;
      m_prefix = prefix;
     }

   string            Prefix(void)  { return m_prefix; }
   int               Created(void) { return m_created; }
   int               Writes(void)  { return m_writes; }
   void              ResetWrites(void) { m_writes = 0; }
   string            N(const string id) { return m_prefix + id; }

   bool              Exists(const string id) { return (ObjectFind(m_chart, N(id)) >= 0); }

   //--- panels and wells -------------------------------------------
   bool              Rect(const string id, const int x, const int y,
                          const int w, const int h,
                          const color bg, const color edge)
     {
      string n = N(id);
      long   fp = Mix(Mix(Mix(Mix(Mix(x, y), w), h), (long)bg), (long)edge);
      if(Same(n, fp, ""))
         return true;
      if(ObjectFind(m_chart, n) < 0)
        {
         if(!ObjectCreate(m_chart, n, OBJ_RECTANGLE_LABEL, 0, 0, 0))
            return false;
         m_created++;
         Common(n);
        }
      ObjectSetInteger(m_chart, n, OBJPROP_XDISTANCE,   x);
      ObjectSetInteger(m_chart, n, OBJPROP_YDISTANCE,   y);
      ObjectSetInteger(m_chart, n, OBJPROP_XSIZE,       w);
      ObjectSetInteger(m_chart, n, OBJPROP_YSIZE,       h);
      ObjectSetInteger(m_chart, n, OBJPROP_BGCOLOR,     bg);
      ObjectSetInteger(m_chart, n, OBJPROP_BORDER_TYPE, BORDER_FLAT);
      ObjectSetInteger(m_chart, n, OBJPROP_COLOR,       edge);
      ObjectSetInteger(m_chart, n, OBJPROP_WIDTH,       1);
      ObjectSetInteger(m_chart, n, OBJPROP_BACK,        false);
      m_writes += 9;
      Keep(n, fp, "");
      return true;
     }

   //--- text --------------------------------------------------------
   bool              Label(const string id, const int x, const int y,
                           const string text, const color col,
                           const int size = SSR_FS_BODY,
                           const string font = SSR_FONT)
     {
      string n = N(id);
      long   fp = Mix(Mix(Mix(Mix(x, y), (long)col), size),
                      (long)StringLen(font));
      if(Same(n, fp, text))
         return true;
      if(ObjectFind(m_chart, n) < 0)
        {
         if(!ObjectCreate(m_chart, n, OBJ_LABEL, 0, 0, 0))
            return false;
         m_created++;
         Common(n);
         ObjectSetInteger(m_chart, n, OBJPROP_ANCHOR, ANCHOR_LEFT_UPPER);
        }
      ObjectSetInteger(m_chart, n, OBJPROP_XDISTANCE, x);
      ObjectSetInteger(m_chart, n, OBJPROP_YDISTANCE, y);
      ObjectSetInteger(m_chart, n, OBJPROP_COLOR,     col);
      ObjectSetInteger(m_chart, n, OBJPROP_FONTSIZE,  size);
      ObjectSetString (m_chart, n, OBJPROP_FONT,      font);
      ObjectSetString (m_chart, n, OBJPROP_TEXT,      text);
      m_writes += 6;
      Keep(n, fp, text);
      return true;
     }

   //--- clickable ----------------------------------------------------
   //--- Colours are ARGUMENTS with theme defaults, not constants baked
   //--- into the widget. The tab strip, the Buy/Sell pair and the plain
   //--- dialog buttons are the same control wearing three palettes; a
   //--- widget that hard-codes one of them forces the other two to be
   //--- re-implemented somewhere else.
   bool              Button(const string id, const int x, const int y,
                            const int w, const int h, const string text,
                            const bool engaged = false,
                            const bool enabled = true)
     {
      return ButtonC(id, x, y, w, h, text,
                     engaged ? SSR_C_BTN_ON      : SSR_C_BTN,
                     engaged ? SSR_C_BTN_ON_EDGE : SSR_C_BTN_EDGE,
                     enabled ? (engaged ? SSR_C_BTN_ON_TEXT : SSR_C_BTN_TEXT)
                             : SSR_C_TEXT_FAINT,
                     SSR_FS_BODY);
     }

   //+------------------------------------------------------------------+
   //| A TYPED FIELD.                                                   |
   //|                                                                  |
   //| MetaTrader's own inputs dialog is a grid of rows a user has to   |
   //| find, read and close before anything happens. A setup that sits  |
   //| on the chart next to the thing being set up is a different       |
   //| product, and this is the control it needs.                       |
   //|                                                                  |
   //| Deliberately NOT event-driven. CHARTEVENT_OBJECT_ENDEDIT only    |
   //| fires on the chart the program is attached to, and this project  |
   //| has already spent three architectures learning what that costs.  |
   //| The value is READ when the user presses Start - one moment, one  |
   //| read, nothing to keep in sync.                                   |
   //+------------------------------------------------------------------+
   bool              Edit(const string id, const int x, const int y,
                          const int w, const int h, const string text,
                          const bool set_text = true)
     {
      string n = N(id);
      bool   fresh = false;
      if(ObjectFind(m_chart, n) < 0)
        {
         if(!ObjectCreate(m_chart, n, OBJ_EDIT, 0, 0, 0))
            return false;
         fresh = true;
         m_created++;
         Common(n);
         ObjectSetInteger(m_chart, n, OBJPROP_ALIGN, ALIGN_LEFT);
         ObjectSetString (m_chart, n, OBJPROP_FONT,  SSR_FONT);
        }
      ObjectSetInteger(m_chart, n, OBJPROP_XDISTANCE, x);
      ObjectSetInteger(m_chart, n, OBJPROP_YDISTANCE, y);
      ObjectSetInteger(m_chart, n, OBJPROP_XSIZE,     w);
      ObjectSetInteger(m_chart, n, OBJPROP_YSIZE,     h);
      ObjectSetInteger(m_chart, n, OBJPROP_BGCOLOR,   SSR_C_WELL);
      ObjectSetInteger(m_chart, n, OBJPROP_COLOR,     SSR_C_TEXT);
      ObjectSetInteger(m_chart, n, OBJPROP_BORDER_COLOR, SSR_C_WELL_EDGE);
      ObjectSetInteger(m_chart, n, OBJPROP_FONTSIZE,  SSR_FS_BODY);
      ObjectSetInteger(m_chart, n, OBJPROP_READONLY,  false);
      //--- ON CREATION, or on an explicit reset. Writing the text every
      //--- repaint would delete whatever the user was typing - but a box
      //--- that came back EMPTY after being rebuilt would lose the value
      //--- just as completely, and silently, so a fresh object always
      //--- gets the caller's text whatever the caller asked for.
      m_writes += 9;
      if(set_text || fresh)
        {
         ObjectSetString(m_chart, n, OBJPROP_TEXT, text);
         m_writes++;
        }
      return true;
     }

   //+------------------------------------------------------------------+
   //| Was this button pressed since the last look?                     |
   //|                                                                  |
   //| Consuming the latch is the whole method. MetaTrader leaves a     |
   //| pressed button pressed, so a reader that only asks would fire    |
   //| the same command on every pass; and the state must be cleared    |
   //| BEFORE the caller acts, so a caller that throws its frame away   |
   //| still leaves the button up rather than held down and repeating.  |
   //+------------------------------------------------------------------+
   bool              Pressed(const string id)
     {
      string n = N(id);
      if(ObjectFind(m_chart, n) < 0)
         return false;
      if(!ObjectGetInteger(m_chart, n, OBJPROP_STATE))
         return false;
      ObjectSetInteger(m_chart, n, OBJPROP_STATE, false);
      return true;
     }

   //--- what the user left in the box. Empty when the box is gone,
   //--- which the caller must treat as "unchanged", never as zero.
   string            EditText(const string id)
     {
      string n = N(id);
      if(ObjectFind(m_chart, n) < 0)
         return "";
      return ObjectGetString(m_chart, n, OBJPROP_TEXT);
     }

   bool              ButtonC(const string id, const int x, const int y,
                             const int w, const int h, const string text,
                             const color bg, const color edge,
                             const color fg, const int size = SSR_FS_BODY)
     {
      string n = N(id);
      long   fp = Mix(Mix(Mix(Mix(Mix(Mix(Mix(x, y), w), h),
                                  (long)bg), (long)edge), (long)fg), size);
      if(Same(n, fp, text))
         return true;
      if(ObjectFind(m_chart, n) < 0)
        {
         if(!ObjectCreate(m_chart, n, OBJ_BUTTON, 0, 0, 0))
            return false;
         m_created++;
         Common(n);
         ObjectSetString(m_chart, n, OBJPROP_FONT, SSR_FONT);
        }
      ObjectSetInteger(m_chart, n, OBJPROP_XDISTANCE,    x);
      ObjectSetInteger(m_chart, n, OBJPROP_YDISTANCE,    y);
      ObjectSetInteger(m_chart, n, OBJPROP_XSIZE,        w);
      ObjectSetInteger(m_chart, n, OBJPROP_YSIZE,        h);
      ObjectSetInteger(m_chart, n, OBJPROP_BGCOLOR,      bg);
      ObjectSetInteger(m_chart, n, OBJPROP_BORDER_COLOR, edge);
      ObjectSetInteger(m_chart, n, OBJPROP_COLOR,        fg);
      ObjectSetInteger(m_chart, n, OBJPROP_FONTSIZE,     size);
      ObjectSetString (m_chart, n, OBJPROP_TEXT,         text);
      m_writes += 9;
      Keep(n, fp, text);
      //--- THE PRESSED STATE IS NOT CLEARED HERE ANY MORE.
      //--- MetaTrader latches a button down when it is clicked, and
      //--- that latch is now how the panel LEARNS about the click -
      //--- it polls OBJPROP_STATE, because it lives on a chart whose
      //--- events it cannot receive. Clearing the latch during a
      //--- repaint would erase presses that landed in the moment
      //--- between one poll and the next. The poll clears it.
      return true;
     }

   //--- a filled track. Two rectangles, because MetaTrader has no bar.
   bool              Progress(const string id, const int x, const int y,
                              const int w, const int h, const double fraction,
                              const color fill)
     {
      double f = fraction;
      if(f < 0.0) f = 0.0;
      if(f > 1.0) f = 1.0;
      if(!Rect(id + "_bg", x, y, w, h, SSR_C_WELL, SSR_C_WELL_EDGE))
         return false;
      int fw = (int)MathRound((w - 2) * f);
      //--- a zero-width rectangle is rejected, so a fresh replay would
      //--- lose its track entirely at 0%
      if(fw < 1) fw = 1;
      return Rect(id + "_fill", x + 1, y + 1, fw, h - 2, fill, fill);
     }

   //+------------------------------------------------------------------+
   //| A SEGMENTED TRACKBAR.                                            |
   //|                                                                  |
   //| It was a groove with a draggable thumb. Dragging needs mouse-move|
   //| events, and the panel now lives on a chart that sends this        |
   //| program none - so the thumb was a control that looked like it     |
   //| worked and did not.                                               |
   //|                                                                   |
   //| Every stop is its own button instead. Clicking anywhere along the |
   //| bar lands on that speed, which is most of what dragging bought,   |
   //| and it works through the one input we actually have. The cells    |
   //| left of the current one are filled, so it still reads as a level  |
   //| at a glance; the current one is darker, so it reads as the handle.|
   //|                                                                   |
   //| Cells are laid out by rounding both edges from the same division, |
   //| so they tile the full width exactly instead of leaving a ragged   |
   //| remainder at the right-hand end.                                  |
   //+------------------------------------------------------------------+
   //+------------------------------------------------------------------+
   //| A SLIDER THAT IS STILL TWENTY BUTTONS.                           |
   //|                                                                  |
   //| It had to stay twenty buttons. The panel lives on a chart this   |
   //| program is NOT attached to, so it never receives a mouse          |
   //| coordinate - the only input it ever gets is "an object was        |
   //| clicked", which is exactly why the groove was built out of        |
   //| clickable cells in the first place. Replacing them with one       |
   //| rectangle would have produced a control that looks right and      |
   //| cannot be used, which is the worst of the three outcomes.         |
   //|                                                                  |
   //| So the cells stay and the SEAMS go. Each cell's border is set to  |
   //| its own fill and the one-pixel gap between them is removed, so    |
   //| twenty buttons draw one unbroken groove. The outline comes from   |
   //| a frame drawn BEHIND them, and the thumb is a thin rectangle      |
   //| drawn ON TOP. Same hit targets, same handler, no squares.         |
   //|                                                                  |
   //| Creation order is the only z-order MQL5 has, so the order here    |
   //| is the drawing: frame, then cells, then thumb. Moving the thumb   |
   //| later only writes its X, so the order survives every repaint.     |
   //|                                                                  |
   //| The thumb is a rectangle label, so a click landing exactly on it  |
   //| is swallowed rather than reaching a cell. Four pixels out of a    |
   //| hundred and eighty, and the value it would have set is the value  |
   //| it is already on.                                                 |
   //+------------------------------------------------------------------+
   bool              Slider(const string id, const int x, const int y,
                            const int w, const int h,
                            const int at, const int stops)
     {
      if(stops < 2 || w < stops)
         return false;

      //--- the groove: one pixel proud of the cells on every side, so
      //--- the outline is the frame's and not twenty separate borders
      if(!Rect(id + "_tk", x - 1, y - 1, w + 2, h + 2,
               SSR_C_TRACK, SSR_C_TRACK_EDGE))
         return false;

      for(int i = 0; i < stops; i++)
        {
         int x0 = x + (int)MathRound((double)i       * w / (double)stops);
         int x1 = x + (int)MathRound((double)(i + 1) * w / (double)stops);
         int cw = x1 - x0;
         if(cw < 1) cw = 1;
         //--- border == fill is what removes the seam. The text colour
         //--- goes the same way: these cells carry no text, and a
         //--- foreground that cannot be seen cannot be wrong.
         color c = (i <= at ? SSR_C_TRACK_FILL : SSR_C_TRACK);
         if(!ButtonC(id + IntegerToString(i), x0, y, cw, h, "",
                     c, c, c, SSR_FS_SMALL))
            return false;
        }

      //--- the thumb, last and therefore on top, at the end of the fill
      int tx = x + (int)MathRound((double)(at + 1) * w / (double)stops) - 2;
      if(tx < x)          tx = x;
      if(tx > x + w - 4)  tx = x + w - 4;
      return Rect(id + "_th", tx, y - 3, 4, h + 6,
                  SSR_C_THUMB, SSR_C_TRACK_EDGE);
     }

   //+------------------------------------------------------------------+
   //| A group box: a hairline frame with its legend punched into the   |
   //| top edge, the way a Windows dialog draws one.                    |
   //+------------------------------------------------------------------+
   bool              Group(const string id, const int x, const int y,
                           const int w, const int h, const string legend)
     {
      if(!Rect(id + "_fr", x, y + 5, w, h - 5, SSR_C_PANEL, SSR_C_GROUP_EDGE))
         return false;
      //--- the legend sits ON the frame line, so the line has to be
      //--- broken behind it or the text is struck through
      int lw = 7 + StringLen(legend) * 5;
      Rect(id + "_lb", x + 6, y + 1, lw, 9, SSR_C_PANEL, SSR_C_PANEL);
      return Label(id + "_lg", x + 9, y, legend, SSR_C_TEXT_DIM, SSR_FS_SMALL);
     }

   //+------------------------------------------------------------------+
   //| PHASE 2 PRIMITIVES                                               |
   //|                                                                  |
   //| Four shapes the new architecture needs and this set could not     |
   //| draw. All additive: no existing primitive changed signature, so   |
   //| every screen built on the old eight still compiles and measures   |
   //| the same in the layout test.                                      |
   //+------------------------------------------------------------------+

   //--- A CHIP: a mode that is TRUE right now and must stay visible -
   //--- BLIND, RANDOM, PROP, the fidelity actually running. Text on a
   //--- tinted plate, because a mode carried by colour alone is a mode
   //--- a colour-blind trader cannot read.
   int               Chip(const string id, const int x, const int y,
                          const string text, const color fg,
                          const color bg, const int fs = SSR_FS_SMALL)
     {
      int w = 10 + StringLen(text) * 6;
      Rect(id + "_bg", x, y, w, 14, bg, fg);
      Label(id, x + 5, y + 2, text, fg, fs);
      return w;                          // so a row of chips can lay itself out
     }

   //--- A METER: a value against a LIMIT. Not a progress bar - progress
   //--- ends at 100% and that is good; a meter can pass its line and
   //--- that is bad. Prop rules, drawdown, days used. The limit mark is
   //--- drawn even when the fill is nowhere near it, because the
   //--- distance to it is the number actually being managed.
   void              Meter(const string id, const int x, const int y,
                           const int w, const int h,
                           const double value, const double limit,
                           const color fill, const bool over_is_bad = true)
     {
      Rect(id + "_bg", x, y, w, h, SSR_C_WELL, SSR_C_WELL_EDGE);
      double frac = (limit > 0.0 ? value / limit : 0.0);
      if(frac < 0.0) frac = 0.0;
      if(frac > 1.0) frac = 1.0;
      int fw = (int)MathRound((w - 2) * frac);
      if(fw > 0)
        {
         bool breached = (over_is_bad && value >= limit);
         color c = (breached ? SSR_C_STOP : fill);
         Rect(id + "_fill", x + 1, y + 1, fw, h - 2, c, c);
        }
      else
         Remove(id + "_fill");
      Rect(id + "_lim", x + w - 2, y, 2, h, SSR_C_TEXT_DIM, SSR_C_TEXT_DIM);
     }

   //--- A LIST: rows that can be chosen - the command palette, sessions,
   //--- trades, statistics. MQL5 has no scrollbar and no clipping, so a
   //--- list draws a WINDOW onto its data and the caller pages it. A
   //--- list that drew every row would draw the surplus over the chart.
   void              List(const string id, const int x, const int y,
                          const int w, const int row_h,
                          const string &rows[], const int first,
                          const int shown, const int selected)
     {
      int n = ArraySize(rows);
      int k = n - first;
      if(k > shown) k = shown;
      if(k < 0)     k = 0;
      Rect(id + "_bg", x - 2, y - 2, w + 4, k * row_h + 4,
           SSR_C_WELL, SSR_C_PRIMARY_EDGE);
      for(int i = 0; i < shown; i++)
        {
         string rid = id + IntegerToString(i);
         if(i >= k)
           { Remove(rid); continue; }
         int idx = first + i;
         if(idx == selected)
            ButtonC(rid, x, y + i * row_h, w, row_h, rows[idx],
                    SSR_C_BTN_ON, SSR_C_BTN_ON_EDGE, SSR_C_BTN_ON_TEXT,
                    SSR_FS_BODY);
         else
            Button(rid, x, y + i * row_h, w, row_h, rows[idx]);
        }
     }

   //--- called before the next paint: a shorter list would otherwise
   //--- leave its old tail on the chart
   void              ListClear(const string id, const int shown)
     {
      Remove(id + "_bg");
      for(int i = 0; i < shown; i++)
         Remove(id + IntegerToString(i));
     }

   //--- A TOAST: something that HAPPENED, which must not evict the
   //--- status strip. The strip carries standing state and the one
   //--- armed-destructive question; a fill confirmation is neither.
   //--- The caller owns the clock - this only draws.
   void              Toast(const string id, const int x, const int y,
                           const int w, const string text, const color accent)
     {
      Rect(id + "_bg", x, y, w, 20, SSR_C_HEADER, accent);
      Rect(id + "_ac", x, y, 3, 20, accent, accent);
      Label(id, x + 9, y + 4, text, SSR_C_TEXT, SSR_FS_SMALL);
     }

   void              ToastClear(const string id)
     { Remove(id + "_bg"); Remove(id + "_ac"); Remove(id); }

   //--- teardown -----------------------------------------------------
   void              Hide(const string id, const bool hidden)
     {
      string n = N(id);
      if(ObjectFind(m_chart, n) >= 0)
         ObjectSetInteger(m_chart, n, OBJPROP_TIMEFRAMES,
                          hidden ? OBJ_NO_PERIODS : OBJ_ALL_PERIODS);
      //--- visibility is not in the fingerprint, so the next draw must
      //--- not be allowed to skip itself on a hidden object
      Forget(n);
     }

   void              Remove(const string id)
     {
      string n = N(id);
      if(ObjectFind(m_chart, n) >= 0)
         ObjectDelete(m_chart, n);
      Forget(n);
     }

   //--- removes EVERY object carrying the prefix, including any left
   //--- behind by a previous instance that died without cleaning up
   int               RemoveAll(void)
     {
      int n = ObjectsDeleteAll(m_chart, m_prefix, 0);
      m_created = 0;
      ForgetAll();
      return n;
     }

   //+------------------------------------------------------------------+
   //| Purge is not the same as "purge MY objects".                     |
   //|                                                                  |
   //| Every part of this product draws under its own prefix - SSRS_ for |
   //| setup, SSRP_ for the panel, SSRK_ for the key card, SSRF_ for the |
   //| first-run card, SSR_LINE_ and SSR_CAL_ on the chart itself. A     |
   //| panel clearing SSRS_ therefore leaves every OTHER part's leftovers|
   //| exactly where they were, which is why "there is something         |
   //| underneath from before" survived two builds that both claimed to  |
   //| have fixed it: I purged one prefix and the ghost belonged to      |
   //| another.                                                          |
   //|                                                                  |
   //| Everything we have ever drawn begins with SSR. One sweep, and one |
   //| name kept out of it - the start line belongs to the user's        |
   //| choice, not to a previous run.                                    |
   //+------------------------------------------------------------------+
   int               CountOwned(void)
     {
      int n = 0;
      int total = ObjectsTotal(m_chart, 0);
      for(int i = 0; i < total; i++)
         if(StringFind(ObjectName(m_chart, i, 0), m_prefix) == 0)
            n++;
      return n;
     }
  };

//+------------------------------------------------------------------+
//| Free, because it is not any one widget set's business: it removes |
//| what EVERY prefix left behind on a chart.                         |
//+------------------------------------------------------------------+
int SSRPurgeChart(const long chart, const string keep = "")
  {
   int removed = 0;
   int total   = ObjectsTotal(chart, -1, -1);
   for(int i = total - 1; i >= 0; i--)
     {
      string nm = ObjectName(chart, i, -1, -1);
      if(StringFind(nm, "SSR") != 0)
         continue;
      if(keep != "" && nm == keep)
         continue;
      if(ObjectDelete(chart, nm))
         removed++;
     }
   if(removed > 0)
      PrintFormat("[ui] swept %d object(s) a previous run left on this chart",
                  removed);
   return removed;
  }

#endif // SSR_WIDGETS_MQH
//+------------------------------------------------------------------+

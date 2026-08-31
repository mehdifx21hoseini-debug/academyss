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

   void              Common(const string name)
     {
      ObjectSetInteger(m_chart, name, OBJPROP_CORNER,     CORNER_LEFT_UPPER);
      ObjectSetInteger(m_chart, name, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(m_chart, name, OBJPROP_SELECTED,   false);
      ObjectSetInteger(m_chart, name, OBJPROP_HIDDEN,     true);
      ObjectSetInteger(m_chart, name, OBJPROP_ZORDER,     100);
     }

public:
                     CSSRWidgets(void) : m_chart(0), m_prefix("SSR_"), m_created(0) {}

   void              Attach(const long chart_id, const string prefix)
     { m_chart = chart_id; m_prefix = prefix; }

   string            Prefix(void)  { return m_prefix; }
   int               Created(void) { return m_created; }
   string            N(const string id) { return m_prefix + id; }

   bool              Exists(const string id) { return (ObjectFind(m_chart, N(id)) >= 0); }

   //--- panels and wells -------------------------------------------
   bool              Rect(const string id, const int x, const int y,
                          const int w, const int h,
                          const color bg, const color edge)
     {
      string n = N(id);
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
      return true;
     }

   //--- text --------------------------------------------------------
   bool              Label(const string id, const int x, const int y,
                           const string text, const color col,
                           const int size = SSR_FS_BODY,
                           const string font = SSR_FONT)
     {
      string n = N(id);
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
      if(ObjectFind(m_chart, n) < 0)
        {
         if(!ObjectCreate(m_chart, n, OBJ_EDIT, 0, 0, 0))
            return false;
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
      //--- only on creation, or on an explicit reset. Writing the text
      //--- every repaint would delete whatever the user was typing.
      if(set_text)
         ObjectSetString(m_chart, n, OBJPROP_TEXT, text);
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
   bool              TrackSegments(const string id, const int x, const int y,
                                   const int w, const int h,
                                   const int at, const int stops)
     {
      if(stops < 2 || w < stops)
         return false;
      for(int i = 0; i < stops; i++)
        {
         int x0 = x + (int)MathRound((double)i       * w / (double)stops);
         int x1 = x + (int)MathRound((double)(i + 1) * w / (double)stops);
         int cw = x1 - x0 - 1;
         if(cw < 1) cw = 1;

         color bg   = (i <  at ? SSR_C_TRACK_FILL : SSR_C_TRACK);
         color edge = SSR_C_TRACK_EDGE;
         if(i == at)
           {
            bg   = SSR_C_THUMB;
            edge = SSR_C_BTN_ON_EDGE;
           }
         if(!ButtonC(id + IntegerToString(i), x0, y, cw, h, "",
                     bg, edge, SSR_C_TEXT, SSR_FS_SMALL))
            return false;
        }
      return true;
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

   //--- teardown -----------------------------------------------------
   void              Hide(const string id, const bool hidden)
     {
      string n = N(id);
      if(ObjectFind(m_chart, n) >= 0)
         ObjectSetInteger(m_chart, n, OBJPROP_TIMEFRAMES,
                          hidden ? OBJ_NO_PERIODS : OBJ_ALL_PERIODS);
     }

   void              Remove(const string id)
     {
      string n = N(id);
      if(ObjectFind(m_chart, n) >= 0)
         ObjectDelete(m_chart, n);
     }

   //--- removes EVERY object carrying the prefix, including any left
   //--- behind by a previous instance that died without cleaning up
   int               RemoveAll(void)
     {
      int n = ObjectsDeleteAll(m_chart, m_prefix, 0);
      m_created = 0;
      return n;
     }

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

#endif // SSR_WIDGETS_MQH
//+------------------------------------------------------------------+

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
      //--- MetaTrader latches a button down after a click; the panel
      //--- would otherwise show every control it ever pressed as held
      ObjectSetInteger(m_chart, n, OBJPROP_STATE,        false);
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
   //| A TRACKBAR: groove, fill, tick row, and a thumb you can drag.    |
   //|                                                                  |
   //| MetaTrader has no slider, so this is four rectangles and a row   |
   //| of one-pixel ticks. The thumb is a BUTTON rather than a          |
   //| rectangle for one reason: a rectangle label does not report      |
   //| clicks, and a control you can only move by dragging - never by   |
   //| clicking beside it - is a control people think is broken.        |
   //|                                                                  |
   //| Hit-testing lives in the panel, because only the panel knows     |
   //| where the trackbar was drawn this frame.                         |
   //+------------------------------------------------------------------+
   bool              Track(const string id, const int x, const int y,
                           const int w, const double fraction,
                           const int stops, const bool dragging)
     {
      double f = fraction;
      if(f < 0.0) f = 0.0;
      if(f > 1.0) f = 1.0;

      //--- groove
      if(!Rect(id + "_gr", x, y + 4, w, 6, SSR_C_TRACK, SSR_C_TRACK_EDGE))
         return false;
      int fw = (int)MathRound((w - 2) * f);
      if(fw < 1) fw = 1;
      Rect(id + "_fl", x + 1, y + 5, fw, 4, SSR_C_TRACK_FILL, SSR_C_TRACK_FILL);

      //--- ticks, one per stop. Capped so a longer ladder cannot turn
      //--- the groove into a solid grey bar.
      int drawn = (stops > 1 && stops <= 24) ? stops : 0;
      for(int i = 0; i < 24; i++)
        {
         string tn = id + "_t" + IntegerToString(i);
         if(i >= drawn)
           { Remove(tn); continue; }
         int tx = x + (int)MathRound((double)i * (w - 1) / (double)(drawn - 1));
         Rect(tn, tx, y + 12, 1, 3, SSR_C_TICK, SSR_C_TICK);
        }

      //--- the thumb, centred on the stop
      int tw = 9, th = 15;
      int cx = x + (int)MathRound(f * (w - 1)) - tw / 2;
      if(cx < x)          cx = x;
      if(cx > x + w - tw) cx = x + w - tw;
      return ButtonC(id + "_th", cx, y, tw, th, "",
                     dragging ? SSR_C_BTN_ON : SSR_C_THUMB,
                     dragging ? SSR_C_BTN_ON_EDGE : SSR_C_THUMB_EDGE,
                     SSR_C_TEXT, SSR_FS_SMALL);
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

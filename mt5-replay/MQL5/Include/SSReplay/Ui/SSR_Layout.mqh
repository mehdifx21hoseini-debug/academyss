//+------------------------------------------------------------------+
//|                                                   SSR_Layout.mqh |
//|                      SS Replay - the one place that knows WHERE   |
//|                                                                  |
//|  WHY THIS EXISTS, AND WHY IT EXISTS NOW                          |
//|                                                                  |
//|  MetaTrader draws an OBJ_LABEL left-to-right from its anchor and  |
//|  offers no bidi layout, no text measurement and no clipping. So   |
//|  a right-to-left panel cannot be a text-direction setting: it     |
//|  can only be a MIRRORED COORDINATE SYSTEM, where every x becomes  |
//|  (frame_width - x - width) and every right-aligned column becomes |
//|  a left-aligned one.                                             |
//|                                                                  |
//|  That is affordable exactly once: while the number of draw sites  |
//|  is small. It is not affordable after five more phases of new UI  |
//|  have each written their own arithmetic inline. The localization  |
//|  plan therefore places one constraint on every phase after this   |
//|  one - position through here, never by hand - and this file is    |
//|  that promise made concrete.                                     |
//|                                                                  |
//|  It is deliberately NOT a layout engine. There are no rows, no    |
//|  stacks, no constraints. It answers four questions - where does   |
//|  this start, how wide is it, where does the next one begin, and   |
//|  which edge is the far one - and nothing else. A layout engine    |
//|  here would be a second thing to learn on top of MQL5's absolute  |
//|  pixels, for no gain the panel can measure.                       |
//|                                                                  |
//|  STATUS: mirroring is IMPLEMENTED and OFF. Nothing calls it with  |
//|  rtl=true yet, because no string has been translated. Phase 10    |
//|  turns it on. Until then this is an identity transform with a     |
//|  seam in it, which is the whole point of building it early.       |
//+------------------------------------------------------------------+
#ifndef SSR_LAYOUT_MQH
#define SSR_LAYOUT_MQH

#include "SSR_Theme.mqh"

//+------------------------------------------------------------------+
//| A frame is a box that things are positioned INSIDE.               |
//|                                                                  |
//| Panels, sheets, group boxes and dialogs are all frames. A frame   |
//| knows its own origin and width, and whether it is mirrored - so   |
//| a caller says "this control is 84 wide and sits at the trailing   |
//| edge" and never has to know which edge that is.                   |
//+------------------------------------------------------------------+
struct SSRFrame
  {
   int               x;        // left edge, in chart pixels
   int               y;        // top edge
   int               w;        // width
   int               pad;      // inner margin on both sides
   bool              rtl;      // mirror the horizontal axis

   void              Init(const int fx, const int fy, const int fw,
                          const int fpad = SSR_PAD, const bool mirror = false)
     { x = fx; y = fy; w = fw; pad = fpad; rtl = mirror; }
  };

//+------------------------------------------------------------------+
//| LEADING: where reading starts. Left in LTR, right in RTL.         |
//|                                                                  |
//| `off` is the distance ALONG the reading direction, not along the  |
//| screen - which is the entire trick. A label at leading offset 0   |
//| is the first thing read in both layouts without the caller        |
//| knowing which layout it is in.                                    |
//+------------------------------------------------------------------+
int SSRLead(const SSRFrame &f, const int off, const int width)
  {
   if(!f.rtl)
      return f.x + f.pad + off;
   return f.x + f.w - f.pad - off - width;
  }

//--- TRAILING: the far edge. Values, steppers, close buttons.
int SSRTrail(const SSRFrame &f, const int off, const int width)
  {
   if(!f.rtl)
      return f.x + f.w - f.pad - off - width;
   return f.x + f.pad + off;
  }

//--- CENTRED, which is the same in both and is here so that callers
//--- never mix a helper with raw arithmetic in one row.
int SSRCentre(const SSRFrame &f, const int width)
  { return f.x + (f.w - width) / 2; }

//--- the usable width inside the padding
int SSRInner(const SSRFrame &f)
  { return f.w - 2 * f.pad; }

//+------------------------------------------------------------------+
//| A ROW: vertical position advances the same way in every layout,   |
//| so this is about not writing `y + 30 + r * 24` in sixty places -  |
//| the arithmetic that put v69's two new rows outside their frame.   |
//+------------------------------------------------------------------+
struct SSRRows
  {
   int               y;        // where the next row starts
   int               h;        // row pitch
   int               gap;      // extra space added by Skip

   void              Init(const int top, const int pitch,
                          const int spacing = SSR_GAP)
     { y = top; h = pitch; gap = spacing; }

   //--- take the next row and advance. The caller draws at the value
   //--- returned, never at `y` - so a forgotten advance is a compile
   //--- error's worth of obvious rather than two rows on top of one.
   int               Next(void)
     { int at = y; y += h; return at; }

   int               Next(const int height)
     { int at = y; y += height; return at; }

   void              Skip(const int extra = -1)
     { y += (extra < 0 ? gap : extra); }

   //--- how tall everything laid out so far actually is, measured from
   //--- a start the caller remembers. This is what a frame height must
   //--- be built from: added up by the compiler, never typed twice.
   int               HeightFrom(const int top) const
     { return y - top; }
  };

//+------------------------------------------------------------------+
//| Divide a width into n equal columns with gaps, the way three      |
//| buttons across a sheet or two deal buttons side by side do.       |
//| Returns the column width; `SSRColX` gives each one's position.    |
//+------------------------------------------------------------------+
int SSRColW(const SSRFrame &f, const int n, const int gap = SSR_GAP)
  {
   if(n <= 0)
      return 0;
   return (SSRInner(f) - (n - 1) * gap) / n;
  }

int SSRColX(const SSRFrame &f, const int i, const int n,
            const int gap = SSR_GAP)
  {
   int cw = SSRColW(f, n, gap);
   return SSRLead(f, i * (cw + gap), cw);
  }

#endif // SSR_LAYOUT_MQH
//+------------------------------------------------------------------+

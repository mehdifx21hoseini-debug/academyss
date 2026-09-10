//+------------------------------------------------------------------+
//|                                                 SSR_KeyCard.mqh  |
//|                    SS Replay - The List Of Keys (L5/Ui)          |
//|                                                                  |
//|  Every shortcut, on the chart, from the same table the keyboard  |
//|  itself reads.                                                   |
//|                                                                  |
//|  NOT A HAND-WRITTEN LIST. That is the whole point of this file.  |
//|  A guide typed out beside the key map drifts the first time a    |
//|  binding moves, and the drift is silent, and the person reading  |
//|  the stale line blames themselves when the key does nothing. R   |
//|  moved from reset to the stop-and-target lines in this very      |
//|  build; a second list would already be wrong.                    |
//|                                                                  |
//|  SO IT IS GENERATED. SSRKeyBindings() is the one place a key is  |
//|  declared, and this walks it. A binding that is added appears    |
//|  here without anyone remembering to add it, and one that is      |
//|  removed disappears the same way.                                |
//|                                                                  |
//|  It toggles. A card that only ever appears on a timer is a card  |
//|  the user cannot consult at the moment they need it, which is    |
//|  the moment they have forgotten a key.                           |
//+------------------------------------------------------------------+
#ifndef SSR_KEY_CARD_MQH
#define SSR_KEY_CARD_MQH

#include "../Common/SSR_Types.mqh"
#include "SSR_Strings.mqh"
#include "SSR_Theme.mqh"
#include "SSR_Widgets.mqh"
#include "SSR_Keys.mqh"

#define SSR_KEYCARD_W    372
#define SSR_KEYCARD_ROW   16

//+------------------------------------------------------------------+
class CSSRKeyCard
  {
private:
   long              m_chart;
   CSSRWidgets       m_w;
   bool              m_up;

public:
                     CSSRKeyCard(void) : m_chart(0), m_up(false) {}

   bool              IsUp(void) { return m_up; }

   //+------------------------------------------------------------------+
   //| Draw it, from the bindings themselves.                           |
   //|                                                                  |
   //| The height is COUNTED rather than chosen, so a binding added     |
   //| tomorrow cannot fall off the bottom edge of a frame sized today. |
   //+------------------------------------------------------------------+
   bool              Show(const long chart_id)
     {
      if(chart_id == 0)
         return false;

      SSRKeyBinding b[];
      int n = SSRKeyBindings(b);

      int rows = 0;
      for(int i = 0; i < n; i++)
         if(b[i].listed)
            rows++;
      if(rows <= 0)
         return false;

      m_chart = chart_id;
      m_w.Attach(chart_id, "SSRK_");
      m_w.RemoveAll();

      int x = 14;
      int y = 40;
      int h = 34 + rows * SSR_KEYCARD_ROW + 26;

      m_w.Rect("bg", x, y, SSR_KEYCARD_W, h, SSR_C_PANEL, SSR_C_PANEL_EDGE);
      m_w.Label("t", x + 12, y + 9, T(SSR_S_KEYCARD_TITLE), SSR_C_HOLD, SSR_FS_BODY);
      m_w.Label("t2", x + 62, y + 10, T(SSR_S_KEYCARD_CLOSE),
                SSR_C_TEXT_DIM, SSR_FS_SMALL);

      int ry = y + 32;
      for(int i = 0; i < n; i++)
        {
         if(!b[i].listed)
            continue;
         string id = "k" + IntegerToString(i);
         //--- the key itself in the accent colour: a list where the keys
         //--- and the descriptions read the same weight is a paragraph,
         //--- and nobody scans a paragraph for one key
         m_w.Label(id + "a", x + 12, ry, b[i].label, SSR_C_HOLD, SSR_FS_SMALL);
         m_w.Label(id + "b", x + 86, ry, b[i].what, SSR_C_TEXT, SSR_FS_SMALL);
         ry += SSR_KEYCARD_ROW;
        }

      m_w.Label("foot", x + 12, ry + 6,
                T(SSR_S_ALL_VIRTUAL),
                SSR_C_TEXT_DIM, SSR_FS_SMALL);

      ChartRedraw(m_chart);
      m_up = true;
      return true;
     }

   void              Hide(void)
     {
      if(!m_up)
         return;
      m_w.RemoveAll();
      if(m_chart != 0)
         ChartRedraw(m_chart);
      m_up = false;
     }

   //--- one verb for the key and the button, so the two cannot get
   //--- out of step about whether the card is up
   bool              Toggle(const long chart_id)
     {
      if(m_up)
        {
         Hide();
         return false;
        }
      return Show(chart_id);
     }

   void              Destroy(void) { Hide(); }
  };

#endif // SSR_KEY_CARD_MQH
//+------------------------------------------------------------------+

//+------------------------------------------------------------------+
//|                                                    SSR_Theme.mqh |
//|                          SS Replay - Panel Theme & Metrics (UI)  |
//|                                                                  |
//|  A trading terminal, not a web app. Dark, dense, quiet: the      |
//|  chart is the subject and the panel is instrumentation beside    |
//|  it. Nothing animates, nothing gradients, nothing rounds.        |
//|                                                                  |
//|  Colour carries meaning and nothing else - green means running,  |
//|  amber means degraded, red means stopped or leaking. Decoration  |
//|  never borrows those three.                                      |
//+------------------------------------------------------------------+
#ifndef SSR_THEME_MQH
#define SSR_THEME_MQH

#include "../Common/SSR_Types.mqh"

//--- surfaces
#define SSR_C_PANEL        C'22,24,28'      // panel ground
#define SSR_C_PANEL_EDGE   C'52,56,64'      // 1px border
#define SSR_C_HEADER       C'30,33,38'      // title strip
#define SSR_C_WELL         C'16,18,21'      // sunken areas: progress track

//--- text
#define SSR_C_TEXT         C'214,218,224'   // primary
#define SSR_C_TEXT_DIM     C'132,140,152'   // labels, units
#define SSR_C_TEXT_FAINT   C'92,99,110'     // disabled

//--- controls
#define SSR_C_BTN          C'38,42,48'
#define SSR_C_BTN_EDGE     C'62,68,78'
#define SSR_C_BTN_TEXT     C'214,218,224'
#define SSR_C_BTN_ON       C'46,74,62'      // engaged toggle
#define SSR_C_BTN_ON_TEXT  C'126,214,168'

//--- semantic. Separate from the accent on purpose: state must never
//--- be confusable with styling.
#define SSR_C_RUN          C'110,200,150'   // PLAYING
#define SSR_C_HOLD         C'196,158,72'    // PAUSED / degraded
#define SSR_C_STOP         C'198,104,100'   // ERROR / leak
#define SSR_C_IDLE         C'132,140,152'   // IDLE / READY

//--- the one accent, used sparingly
#define SSR_C_ACCENT       C'198,152,62'

//--- type
#define SSR_FONT           "Segoe UI"
#define SSR_FONT_MONO      "Consolas"
#define SSR_FS_TITLE       9
#define SSR_FS_BODY        8
#define SSR_FS_CLOCK       14
#define SSR_FS_SMALL       7

//--- metrics, in pixels
#define SSR_PANEL_W        228
#define SSR_PANEL_H        250
#define SSR_PAD            10
#define SSR_ROW_H          20
#define SSR_HEADER_H       22
#define SSR_BTN_H          24
#define SSR_GAP            6

//+------------------------------------------------------------------+
//| One colour per replay state. The panel never invents its own.    |
//+------------------------------------------------------------------+
color SSRStateColor(const ENUM_SSR_STATE s)
  {
   switch(s)
     {
      case SSR_STATE_PLAYING:   return SSR_C_RUN;
      case SSR_STATE_PAUSED:    return SSR_C_HOLD;
      case SSR_STATE_LOADING:
      case SSR_STATE_RESETTING: return SSR_C_ACCENT;
      case SSR_STATE_ERROR:     return SSR_C_STOP;
      case SSR_STATE_COMPLETED: return SSR_C_ACCENT;
     }
   return SSR_C_IDLE;
  }

//+------------------------------------------------------------------+
//| Fidelity is coloured by how much of it is real.                  |
//|                                                                  |
//| The user must be able to tell at a glance that they are watching |
//| approximated ticks. Colouring all three the same would be the    |
//| quiet dishonesty this product exists to avoid.                   |
//+------------------------------------------------------------------+
color SSRFidelityColor(const ENUM_SSR_FIDELITY f)
  {
   switch(f)
     {
      case SSR_FIDELITY_FULL_TICK:      return SSR_C_RUN;
      case SSR_FIDELITY_SYNTHETIC_TICK: return SSR_C_TEXT_DIM;
      case SSR_FIDELITY_BAR:            return SSR_C_HOLD;
     }
   return SSR_C_TEXT_FAINT;
  }

#endif // SSR_THEME_MQH
//+------------------------------------------------------------------+

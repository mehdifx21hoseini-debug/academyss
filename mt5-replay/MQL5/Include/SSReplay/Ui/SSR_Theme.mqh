//+------------------------------------------------------------------+
//|                                                    SSR_Theme.mqh |
//|                          SS Replay - Panel Theme & Metrics (UI)  |
//|                                                                  |
//|  A CLASSIC WINDOWS DIALOG, not a web app and not a terminal.     |
//|  Light face, framed group boxes, square corners, no gradients,   |
//|  no animation. The chart is the subject; this is the instrument  |
//|  panel bolted beside it.                                         |
//|                                                                  |
//|  WHY LIGHT, AND WHY NOT PURE WHITE                               |
//|  The user's chart is DARK. A pure-white panel on a dark chart    |
//|  glares: the eye keeps re-adapting every time it moves between   |
//|  the two, and after an hour of replay that is a headache rather  |
//|  than a preference. So the face is a warm-grey 236 rather than   |
//|  255, the wells are 246 rather than white, and the panel carries |
//|  a dark outer border so it reads as a WINDOW sitting on the      |
//|  chart instead of a hole burned through it.                      |
//|                                                                  |
//|  ONE TYPEFACE                                                    |
//|  There used to be two: Segoe UI for text and Consolas for        |
//|  numbers. The second existed to stop changing digits jittering.  |
//|  Tahoma draws all ten digits on the same advance width, so       |
//|  right-aligned columns and fixed decimal places do that job and  |
//|  the panel speaks in one voice. SSR_FONT_MONO is kept as a       |
//|  separate name pointing at the same face, so if a terminal ever  |
//|  proves otherwise it is one line to split them again.            |
//|                                                                  |
//|  Colour carries meaning and nothing else - green means running   |
//|  or long, amber means degraded, red means stopped or short.      |
//|  Decoration never borrows those three.                           |
//+------------------------------------------------------------------+
#ifndef SSR_THEME_MQH
#define SSR_THEME_MQH

#include "../Common/SSR_Types.mqh"

//--- surfaces
#define SSR_C_PANEL        C'236,236,236'   // dialog face
#define SSR_C_PANEL_EDGE   C'88,92,98'      // outer frame, dark on a dark chart
#define SSR_C_HEADER       C'222,224,227'   // caption strip
#define SSR_C_WELL         C'246,246,246'   // sunken areas: lists, tracks
#define SSR_C_WELL_EDGE    C'150,154,160'
#define SSR_C_GROUP_EDGE   C'196,196,196'   // group-box hairline
#define SSR_C_STATUS       C'228,228,228'   // status strip

//--- text
#define SSR_C_TEXT         C'16,16,16'      // primary
#define SSR_C_TEXT_DIM     C'82,86,92'      // labels, units
#define SSR_C_TEXT_FAINT   C'146,150,156'   // disabled

//--- controls
#define SSR_C_BTN          C'225,225,225'
#define SSR_C_BTN_EDGE     C'173,173,173'
#define SSR_C_BTN_TEXT     C'16,16,16'
#define SSR_C_BTN_ON       C'204,228,247'   // engaged toggle - the Windows blue
#define SSR_C_BTN_ON_TEXT  C'0,60,110'
#define SSR_C_BTN_ON_EDGE  C'0,84,153'

//--- tabs
#define SSR_C_TAB          C'220,220,220'
#define SSR_C_TAB_ON       C'236,236,236'   // same as the face: the sheet
#define SSR_C_TAB_EDGE     C'168,172,178'

//--- semantic. Separate from the accent on purpose: state must never
//--- be confusable with styling.
#define SSR_C_RUN          C'28,122,69'     // PLAYING / LONG
#define SSR_C_HOLD         C'163,90,0'      // PAUSED / degraded
#define SSR_C_STOP         C'176,58,46'     // ERROR / leak / SHORT
#define SSR_C_IDLE         C'110,114,120'   // IDLE / READY

//--- the deal buttons, which are the only saturated things here
#define SSR_C_BUY          C'46,139,87'
#define SSR_C_BUY_EDGE     C'34,105,65'
#define SSR_C_SELL         C'192,57,43'
#define SSR_C_SELL_EDGE    C'148,41,30'
#define SSR_C_DEAL_TEXT    C'255,255,255'
#define SSR_C_DEAL_DIM     C'182,186,190'   // the side the lines did not draw

//--- the trackbar
#define SSR_C_TRACK        C'228,230,233'
#define SSR_C_TRACK_EDGE   C'138,143,149'
#define SSR_C_TRACK_FILL   C'27,116,187'
#define SSR_C_THUMB        C'246,246,248'
#define SSR_C_THUMB_EDGE   C'111,114,118'
#define SSR_C_TICK         C'168,173,179'

//--- the one accent, used sparingly
#define SSR_C_ACCENT       C'20,64,120'

//--- the SL/TP lines on the chart
#define SSR_C_LINE_SL      C'192,57,43'
#define SSR_C_LINE_TP      C'46,139,87'

//--- type. ONE face - see the header.
#define SSR_FONT           "Tahoma"
#define SSR_FONT_MONO      "Tahoma"
#define SSR_FS_TITLE       9
#define SSR_FS_BODY        8
#define SSR_FS_CLOCK       13
#define SSR_FS_SMALL       7

//+------------------------------------------------------------------+
//| Metrics, in pixels.                                              |
//|                                                                  |
//| Added up rather than guessed, so a row added later has to change |
//| a number here instead of quietly overflowing the frame. Walked    |
//| from the top of Render, in the order the rows are drawn:          |
//|   caption 23 + clock+progress 32 + transport 27 + speed 33        |
//| + tabs 21 + sheet 200 + status 18 + margin 14 = 368               |
//| The sheet is sized by the tallest one - Trade: risk 40, gap 4,    |
//| stop & target 106, gap 6, deal buttons 26, spread 14 = 196.       |
//+------------------------------------------------------------------+
#define SSR_PANEL_W        420
#define SSR_PANEL_H        368
#define SSR_PAD            8
#define SSR_ROW_H          19
#define SSR_HEADER_H       20
#define SSR_BTN_H          22
#define SSR_GAP            5

#define SSR_SIDE_W         104     // the always-visible button column
#define SSR_TAB_H          21
#define SSR_SHEET_H        200
#define SSR_STATUS_H       18
#define SSR_TRACK_H        16      // the speed groove and its thumb

//--- how many tabs, and which sheet each index is
#define SSR_TAB_TRADE      0
#define SSR_TAB_POSITIONS  1
#define SSR_TAB_STATS      2
#define SSR_TAB_SESSION    3
#define SSR_TAB_COUNT      4

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

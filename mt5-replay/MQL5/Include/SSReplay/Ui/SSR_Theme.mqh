//+------------------------------------------------------------------+
//|                                                    SSR_Theme.mqh |
//|                          SS Replay - Panel Theme & Metrics (UI)  |
//|                                                                  |
//|  AN INSTRUMENT THAT BELONGS TO THE CHART IT SITS ON.             |
//|                                                                  |
//|  This was a light Windows dialog for ninety builds. The argument |
//|  written here for it was sound and aimed at the wrong target: a  |
//|  PURE WHITE panel on a dark chart glares, the eye re-adapts on   |
//|  every glance, and an hour of replay becomes a headache. All     |
//|  true. The conclusion - therefore make it warm grey 236 - solved |
//|  the glare by making the panel a foreign object instead, a       |
//|  Windows 95 dialog taped to a black chart.                       |
//|                                                                  |
//|  Dark answers the same complaint properly. Nothing glares, and   |
//|  the panel reads as part of the instrument rather than a window  |
//|  somebody left open on top of it.                                |
//|                                                                  |
//|  ELEVATION, NOT BORDERS. The face is lifted off the chart, the   |
//|  caption is lifted off the face, and wells are sunk below it.    |
//|  Three steps, each about eight points of luminance - enough to   |
//|  read as depth, not enough to look striped.                      |
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
//|  COLOUR CARRIES MEANING AND NOTHING ELSE - green means running   |
//|  or long, amber means degraded, red means stopped or short. On a |
//|  dark face those three had to be lifted well above their print   |
//|  values to stay legible; they are still the only saturated       |
//|  things here apart from the deal buttons, and decoration never   |
//|  borrows them. There is exactly one accent and it is not any of  |
//|  them.                                                           |
//+------------------------------------------------------------------+
#ifndef SSR_THEME_MQH
#define SSR_THEME_MQH

#include "../Common/SSR_Types.mqh"

//--- surfaces. Three steps of elevation: chart, face, caption; wells
//--- go the other way, below the face, because they are holes.
//--- The first dark build put the face at 26,29,35. On this user's
//--- chart - which is pure black, as most replay charts are - that is
//--- four points of luminance above the background: the panel stopped
//--- reading as a surface at all, and a collapsed one looked like two
//--- buttons floating on the chart with nothing behind them.
//--- Twelve points higher, with an edge bright enough to close it.
#define SSR_C_PANEL        C'38,42,51'      // the face, lifted off the chart
#define SSR_C_PANEL_EDGE   C'92,100,116'    // outer frame
#define SSR_C_HEADER       C'50,55,67'      // caption strip, lifted again
#define SSR_C_WELL         C'24,27,33'      // sunken areas: lists, tracks
#define SSR_C_WELL_EDGE    C'70,77,90'
#define SSR_C_GROUP_EDGE   C'62,68,81'      // group-box hairline
#define SSR_C_STATUS       C'31,34,42'      // status strip

//--- text
#define SSR_C_TEXT         C'233,236,242'   // primary
#define SSR_C_TEXT_DIM     C'149,157,171'   // labels, units
#define SSR_C_TEXT_FAINT   C'95,102,115'    // disabled

//--- controls
#define SSR_C_BTN          C'58,64,77'
#define SSR_C_BTN_EDGE     C'86,94,110'
#define SSR_C_BTN_TEXT     C'226,231,239'
#define SSR_C_BTN_ON       C'29,66,108'     // engaged toggle, accent-tinted
#define SSR_C_BTN_ON_TEXT  C'166,206,252'
#define SSR_C_BTN_ON_EDGE  C'58,126,198'

//--- tabs
#define SSR_C_TAB          C'44,49,60'
#define SSR_C_TAB_ON       C'38,42,51'      // same as the face: the sheet
#define SSR_C_TAB_EDGE     C'70,77,90'

//--- semantic. Separate from the accent on purpose: state must never
//--- be confusable with styling. Lifted for a dark face - the print
//--- values these started from read as mud at 26,29,35.
#define SSR_C_RUN          C'63,191,122'    // PLAYING / LONG
#define SSR_C_HOLD         C'227,164,60'    // PAUSED / degraded
#define SSR_C_STOP         C'233,92,82'     // ERROR / leak / SHORT
#define SSR_C_IDLE         C'126,134,147'   // IDLE / READY

//--- the deal buttons, which are the loudest things here and should be
#define SSR_C_BUY          C'33,148,93'
#define SSR_C_BUY_EDGE     C'48,188,118'
#define SSR_C_SELL         C'197,57,53'
#define SSR_C_SELL_EDGE    C'237,87,79'
#define SSR_C_DEAL_TEXT    C'255,255,255'
#define SSR_C_DEAL_DIM     C'52,57,67'      // the side the lines did not draw

//--- the trackbar
#define SSR_C_TRACK        C'24,27,33'
#define SSR_C_TRACK_EDGE   C'70,77,90'
#define SSR_C_TRACK_FILL   C'58,126,198'
#define SSR_C_THUMB        C'216,222,232'
#define SSR_C_THUMB_EDGE   C'118,126,141'
#define SSR_C_TICK         C'70,77,90'

//--- the one accent, used sparingly
#define SSR_C_ACCENT       C'88,158,236'

//--- THE PRIMARY ACTION. Exactly one control on this panel earns it:
//--- Play/Pause, which is pressed hundreds of times in a session while
//--- everything beside it is pressed once or twice. Seven identical
//--- buttons in a row told the hand nothing about which was which.
#define SSR_C_PRIMARY      C'40,102,174'
#define SSR_C_PRIMARY_EDGE C'88,158,236'
#define SSR_C_PRIMARY_TEXT C'240,247,255'

//+------------------------------------------------------------------+
//| CHART-SIDE COLOUR. These sit on the CHART, not on the panel, so  |
//| they answer to the candles rather than to the face - but they    |
//| are still tokens, and they still live here.                       |
//|                                                                  |
//| They were not, until Phase 2. Sixteen colours were written at     |
//| their draw sites across four files, and one of them is why the    |
//| "bring the line to this view" button stayed WHITE for three       |
//| builds after the panel went dark: it was styled in the expert,    |
//| where the theme could not reach it. A design system that any      |
//| file may opt out of is a suggestion, not a system.                |
//+------------------------------------------------------------------+
#define SSR_C_LINE_SL      C'233,92,82'
#define SSR_C_LINE_TP      C'63,191,122'
#define SSR_C_LINE_ENTRY   C'214,168,60'    // the pending entry line
#define SSR_C_LINE_LONG    C'88,158,236'    // a long position's own level
#define SSR_C_LINE_SHORT   C'227,164,60'    // a short's
#define SSR_C_TRADE_WIN    C'63,191,122'    // closed-trade history on the chart
#define SSR_C_TRADE_LOSS   C'233,92,82'

//--- the start line the setup panel is about, and its two buttons
#define SSR_C_PICK_LINE    C'227,164,60'
#define SSR_C_PICK_INFO    C'227,164,60'

//--- calendar lines, by impact. Severity, so it answers to the
//--- semantic set rather than inventing a third palette.
#define SSR_C_NEWS_HIGH    C'233,92,82'
#define SSR_C_NEWS_MED     C'227,164,60'
#define SSR_C_NEWS_LOW     C'126,134,147'

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
//| + tabs 21 + sheet 222 + status 18 + margin 14 = 390               |
//| The sheet is sized by the tallest one - Trade: risk 40, gap 4,    |
//| setup box 22, stop & target 106, gap 6, deal buttons 26,          |
//| spread 14 = 218, rounded to 222.                                  |
//|                                                                   |
//| v69 added the setup box to Trade and a trailing row to Positions. |
//| Both fitted "fine" on screen and neither was inside the frame:    |
//| the sheet is a fixed height and a row past its end is drawn over  |
//| the status bar, where it looks like a rendering fault rather than |
//| a number nobody updated. Positions now ends at 193, Trade at 218. |
//+------------------------------------------------------------------+
#define SSR_SHEET_H        186
#define SSR_PANEL_W        420
//--- ADDED UP BY THE COMPILER, not by me. The sum above was a comment
//--- for eleven builds and the two rows v69 added went straight past
//--- the end of it; written this way, a taller sheet moves the frame
//--- with it and there is no second number to forget.
#define SSR_PANEL_H        (23 + 32 + 27 + 21 + 21 + SSR_SHEET_H + 18 + 8)
//--- CAPTION 23 + CLOCK/PROGRESS 32 + TRANSPORT 27 + SPEED 21
//--- + STATUS 18 + MARGIN 7. Everything a person touches while the
//--- replay runs, and nothing they only consult.
#define SSR_PANEL_COMPACT_H 128
//--- the orange line the setup panel is about. Named here rather than
//--- in the expert so a chart sweep can keep it while removing
//--- everything else this product drew.
#define SSR_PICK_LINE      "SSR_PICK_LINE"

#define SSR_PAD            8
#define SSR_ROW_H          19
#define SSR_HEADER_H       20
#define SSR_BTN_H          22
#define SSR_GAP            5

#define SSR_SIDE_W         104     // the always-visible button column
#define SSR_TAB_H          21
#define SSR_STATUS_H       18

//--- how long a destructive button stays armed after its first press.
//--- Long enough to read the line that appeared, short enough that it
//--- cannot still be armed when the user comes back to the keyboard.
#define SSR_CONFIRM_MS     4000
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

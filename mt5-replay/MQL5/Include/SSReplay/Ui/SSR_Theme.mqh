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
#define SSR_C_PANEL_EDGE   C'108,116,130'   // outer frame - see A18
#define SSR_C_HEADER       C'33,36,44'      // caption strip, RECESSED - see below
#define SSR_C_WELL         C'24,27,33'      // sunken areas: lists, tracks
#define SSR_C_WELL_EDGE    C'70,77,90'
#define SSR_C_GROUP_EDGE   C'62,68,81'      // group-box hairline
#define SSR_C_STATUS       C'31,34,42'      // status strip

//+------------------------------------------------------------------+
//| EVERY ONE OF THESE WAS MEASURED, AND ELEVEN OF THEM FAILED.      |
//|                                                                  |
//| Phase 9 computed the WCAG contrast ratio of every foreground     |
//| this panel draws against every surface it draws it on. Eleven of |
//| thirty-eight pairs were below 4.5:1 - the threshold for text     |
//| this small - and the worst was the build tag at 2.06:1, which is |
//| the one label a user is asked to read off a screenshot.          |
//|                                                                  |
//| THE CAPTION WAS THE PROBLEM SURFACE. Five of the eleven were     |
//| "on the header": it was the lightest thing in the panel, so      |
//| every colour on it had the least room. It is RECESSED now, like  |
//| the status strip at the other end, and the body is the lifted    |
//| part between them - which fixed five failures without changing   |
//| a single foreground colour.                                      |
//|                                                                  |
//| THERE IS ROOM FOR TWO READABLE GREYS BELOW WHITE, NOT THREE.     |
//|                                                                  |
//| Solved numerically: the dimmest grey that clears 4.5:1 on this   |
//| panel is about 149, and TEXT_DIM was already 149. A third tier   |
//| below TEXT_DIM is, by definition, below the readable floor. So   |
//| the ramp was re-spread rather than extended - 233 / 186 / 149,   |
//| three visibly distinct steps, all of them readable, instead of   |
//| four steps of which the last was decoration.                     |
//|                                                                  |
//| THE PAIRS ARE DECLARED HERE, BESIDE THE TOKENS, and audit A18    |
//| reads these lines. There is no way to derive which colour is     |
//| drawn on which surface without a layout engine, so the list is   |
//| kept by hand - and it is kept HERE, where changing a token and   |
//| forgetting the pair means editing two lines that touch.          |
//|                                                                  |
//| `text` is held to 4.5:1 (WCAG AA, small text). `ui` is held to   |
//| 3.0:1 (WCAG 1.4.11, non-text components: borders and fills that  |
//| carry meaning rather than words).                                |
//+------------------------------------------------------------------+
//--- SSR_CONTRAST: SSR_C_TEXT on SSR_C_PANEL text
//--- SSR_CONTRAST: SSR_C_TEXT on SSR_C_HEADER text
//--- SSR_CONTRAST: SSR_C_TEXT on SSR_C_STATUS text
//--- SSR_CONTRAST: SSR_C_TEXT on SSR_C_WELL text
//--- SSR_CONTRAST: SSR_C_TEXT on SSR_C_TAB text
//--- SSR_CONTRAST: SSR_C_TEXT on SSR_C_TAB_ON text
//--- SSR_CONTRAST: SSR_C_TEXT_DIM on SSR_C_PANEL text
//--- SSR_CONTRAST: SSR_C_TEXT_DIM on SSR_C_HEADER text
//--- SSR_CONTRAST: SSR_C_TEXT_DIM on SSR_C_STATUS text
//--- SSR_CONTRAST: SSR_C_TEXT_DIM on SSR_C_WELL text
//--- SSR_CONTRAST: SSR_C_TEXT_DIM on SSR_C_TAB text
//--- SSR_CONTRAST: SSR_C_TEXT_DIM on SSR_C_TAB_ON text
//--- SSR_CONTRAST: SSR_C_TEXT_FAINT on SSR_C_PANEL text
//--- SSR_CONTRAST: SSR_C_TEXT_FAINT on SSR_C_HEADER text
//--- SSR_CONTRAST: SSR_C_TEXT_FAINT on SSR_C_STATUS text
//--- SSR_CONTRAST: SSR_C_TEXT_FAINT on SSR_C_WELL text
//--- SSR_CONTRAST: SSR_C_TEXT_FAINT on SSR_C_TAB text
//--- SSR_CONTRAST: SSR_C_IDLE on SSR_C_PANEL text
//--- SSR_CONTRAST: SSR_C_IDLE on SSR_C_HEADER text
//--- SSR_CONTRAST: SSR_C_IDLE on SSR_C_STATUS text
//--- SSR_CONTRAST: SSR_C_RUN on SSR_C_PANEL text
//--- SSR_CONTRAST: SSR_C_RUN on SSR_C_HEADER text
//--- SSR_CONTRAST: SSR_C_RUN on SSR_C_STATUS text
//--- SSR_CONTRAST: SSR_C_RUN on SSR_C_WELL text
//--- SSR_CONTRAST: SSR_C_HOLD on SSR_C_PANEL text
//--- SSR_CONTRAST: SSR_C_HOLD on SSR_C_HEADER text
//--- SSR_CONTRAST: SSR_C_HOLD on SSR_C_STATUS text
//--- SSR_CONTRAST: SSR_C_HOLD on SSR_C_WELL text
//--- SSR_CONTRAST: SSR_C_STOP on SSR_C_PANEL text
//--- SSR_CONTRAST: SSR_C_STOP on SSR_C_HEADER text
//--- SSR_CONTRAST: SSR_C_STOP on SSR_C_STATUS text
//--- SSR_CONTRAST: SSR_C_STOP on SSR_C_WELL text
//--- SSR_CONTRAST: SSR_C_STOP on SSR_C_TAB text
//--- SSR_CONTRAST: SSR_C_ACCENT on SSR_C_PANEL text
//--- SSR_CONTRAST: SSR_C_ACCENT on SSR_C_HEADER text
//--- SSR_CONTRAST: SSR_C_ACCENT on SSR_C_WELL text
//--- SSR_CONTRAST: SSR_C_BTN_TEXT on SSR_C_BTN text
//--- SSR_CONTRAST: SSR_C_BTN_ON_TEXT on SSR_C_BTN_ON text
//--- SSR_CONTRAST: SSR_C_PRIMARY_TEXT on SSR_C_PRIMARY text
//--- SSR_CONTRAST: SSR_C_DEAL_TEXT on SSR_C_BUY text
//--- SSR_CONTRAST: SSR_C_DEAL_TEXT on SSR_C_SELL text
//--- SSR_CONTRAST: SSR_C_DEAL_TEXT on SSR_C_DEAL_DIM text
//--- the edges that carry a STATE rather than a shape: armed, primary,
//--- and the frame that says where the panel ends.
//---
//--- PANEL_EDGE is measured against the FACE, not against the chart,
//--- because the chart's background belongs to the user and cannot be
//--- audited. It is the line that closes the surface - the v100 lesson
//--- was that a face barely above the chart stops reading as a surface
//--- at all - so the pair that matters is the one this file owns. At
//--- 2.42:1 it was a frame that only worked because the chart behind it
//--- happened to be darker.
//--- SSR_CONTRAST: SSR_C_BTN_ON_EDGE on SSR_C_PANEL ui
//--- SSR_CONTRAST: SSR_C_PRIMARY_EDGE on SSR_C_PANEL ui
//--- SSR_CONTRAST: SSR_C_PANEL_EDGE on SSR_C_PANEL ui
//--- SSR_CONTRAST: SSR_C_THUMB on SSR_C_TRACK ui
//--- SSR_CONTRAST: SSR_C_TRACK_FILL on SSR_C_TRACK ui

//--- text
#define SSR_C_TEXT         C'233,236,242'   // primary
#define SSR_C_TEXT_DIM     C'186,193,205'   // labels, units
#define SSR_C_TEXT_FAINT   C'149,154,162'   // disabled - the READABLE floor

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
#define SSR_C_STOP         C'237,118,110'   // ERROR / leak / SHORT
#define SSR_C_IDLE         C'148,154,165'   // IDLE / READY

//--- the deal buttons, which are the loudest things here and should be
#define SSR_C_BUY          C'30,133,84'
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
#define SSR_C_LINE_SL      C'237,118,110'
#define SSR_C_LINE_TP      C'63,191,122'
#define SSR_C_LINE_ENTRY   C'214,168,60'    // the pending entry line
#define SSR_C_LINE_LONG    C'88,158,236'    // a long position's own level
#define SSR_C_LINE_SHORT   C'227,164,60'    // a short's
#define SSR_C_TRADE_WIN    C'63,191,122'    // closed-trade history on the chart
#define SSR_C_TRADE_LOSS   C'237,118,110'

//--- the start line the setup panel is about, and its two buttons
#define SSR_C_PICK_LINE    C'227,164,60'
#define SSR_C_PICK_INFO    C'227,164,60'

//--- calendar lines, by impact. Severity, so it answers to the
//--- semantic set rather than inventing a third palette.
#define SSR_C_NEWS_HIGH    C'237,118,110'
#define SSR_C_NEWS_MED     C'227,164,60'
#define SSR_C_NEWS_LOW     C'148,154,165'

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

//+------------------------------------------------------------------+
//| THE TALL SHEET.                                                  |
//|                                                                  |
//| Seven more rows of the Positions list, at SSR_ROW_H + 1 each -   |
//| the one sheet that was actually running out of room. It is not   |
//| automatic: compact is a DEGRADATION forced by a chart with no    |
//| space, and taking space is the opposite kind of decision, so it  |
//| is asked for and remembered.                                     |
//|                                                                  |
//| Written as an offset rather than a second total, because a       |
//| second total is a number that has to be kept in step by hand     |
//| with the first - and this file has lost that argument before.    |
//+------------------------------------------------------------------+
#define SSR_SHEET_GROW     140
#define SSR_SHEET_H_TALL   (SSR_SHEET_H + SSR_SHEET_GROW)
#define SSR_PANEL_W        420
//--- ADDED UP BY THE COMPILER, not by me. The sum above was a comment
//--- for eleven builds and the two rows v69 added went straight past
//--- the end of it; written this way, a taller sheet moves the frame
//--- with it and there is no second number to forget.
#define SSR_PANEL_H        (23 + 32 + 27 + 21 + 21 + SSR_SHEET_H + 18 + 8)
#define SSR_PANEL_TALL_H   (SSR_PANEL_H + SSR_SHEET_GROW)
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

//+------------------------------------------------------------------+
//| WHICH SHEET EACH INDEX IS, AND HOW MANY THERE ARE RIGHT NOW.     |
//|                                                                  |
//| SSR_TAB_COUNT is the tabs EVERY session has. Prop is a fifth one |
//| that exists only while an evaluation is configured - a panel     |
//| that shows an empty scoreboard to everyone who is not being      |
//| scored is a panel asking a question nobody put to it.            |
//|                                                                  |
//| So the count is a question the panel asks its state, not a       |
//| constant, and SSR_TAB_MAX is only ever used for sweeping objects |
//| that a shrinking strip has to leave behind.                      |
//+------------------------------------------------------------------+
#define SSR_TAB_TRADE      0
#define SSR_TAB_POSITIONS  1
#define SSR_TAB_STATS      2
#define SSR_TAB_SESSION    3
#define SSR_TAB_COUNT      4
#define SSR_TAB_PROP       4
#define SSR_TAB_MAX        5

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

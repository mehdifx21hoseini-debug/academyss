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
//+------------------------------------------------------------------+
//| ONE LINE CHANGES THE WHOLE PANEL.                                |
//|                                                                  |
//| Comment SSR_THEME_LIGHT out and the dark palette below is built  |
//| instead. Both are kept, in full, because the dark one was asked   |
//| for once and may be asked for again - and a palette that only     |
//| exists in git history is a palette nobody can switch back to.     |
//|                                                                  |
//| BOTH CLEAR THE SAME BAR. Audit A18 reads whichever block is       |
//| active and holds it to WCAG AA, so the light theme could not      |
//| ship until it was solved the same way the dark one was: the       |
//| palette recovered from before v98 failed 24 of its pairs -        |
//| including WHITE text on a 182-grey disabled button at 1.95:1,     |
//| and a speed thumb at 1.16:1 that was simply invisible.            |
//|                                                                  |
//| The grey ramp landed on the same shape from the other end:        |
//| 16 / 58 / 93, three steps, and 93 is the darkest grey that still  |
//| separates from the face. There is room for two readable greys     |
//| below the primary text and not three - which is exactly what the  |
//| dark ramp found at 233 / 186 / 149.                               |
//+------------------------------------------------------------------+
#define SSR_THEME_RAIL
//#define SSR_THEME_LIGHT
//#define SSR_THEME_DARK

//--- exactly one of the three is defined above. Flat blocks rather
//--- than nested #else so each palette is a column you can read.

#ifdef SSR_THEME_RAIL
//--- surfaces: the face lifted off a dark chart, the caption and
//--- the wells sunk below it. Same three steps as the dark palette,
//--- a little warmer and a little closer together.
#define SSR_C_PANEL        C'34,37,43'
#define SSR_C_PANEL_EDGE   C'103,111,125'
#define SSR_C_HEADER       C'27,30,35'
#define SSR_C_WELL         C'21,24,28'
#define SSR_C_WELL_EDGE    C'103,111,125'
#define SSR_C_GROUP_EDGE   C'103,111,125'
#define SSR_C_STATUS       C'27,30,35'
#define SSR_C_TEXT         C'230,233,238'
#define SSR_C_TEXT_DIM     C'176,182,192'
#define SSR_C_TEXT_FAINT   C'138,144,153'
#define SSR_C_BTN          C'44,48,55'
#define SSR_C_BTN_EDGE     C'103,111,124'
#define SSR_C_BTN_TEXT     C'230,233,238'
#define SSR_C_BTN_ON       C'224,134,58'
#define SSR_C_BTN_ON_TEXT  C'27,30,35'
#define SSR_C_BTN_ON_EDGE  C'224,134,58'
#define SSR_C_TAB          C'27,30,35'
#define SSR_C_TAB_ON       C'34,37,43'
#define SSR_C_TAB_EDGE     C'103,111,125'
#define SSR_C_RUN          C'79,190,134'
#define SSR_C_HOLD         C'227,164,60'
#define SSR_C_STOP         C'237,118,110'
#define SSR_C_IDLE         C'148,154,165'
#define SSR_C_BUY          C'41,134,88'
#define SSR_C_BUY_EDGE     C'48,188,118'
#define SSR_C_SELL         C'194,74,59'
#define SSR_C_SELL_EDGE    C'237,87,79'
#define SSR_C_DEAL_TEXT    C'255,255,255'
#define SSR_C_DEAL_DIM     C'52,57,67'
#define SSR_C_TRACK        C'21,24,28'
#define SSR_C_TRACK_EDGE   C'103,111,125'
#define SSR_C_TRACK_FILL   C'201,109,32'
#define SSR_C_THUMB        C'230,233,238'
#define SSR_C_THUMB_EDGE   C'118,126,141'
#define SSR_C_TICK         C'70,77,90'
#define SSR_C_ACCENT       C'224,134,58'
#define SSR_C_PRIMARY      C'224,134,58'
#define SSR_C_PRIMARY_EDGE C'224,134,58'
#define SSR_C_PRIMARY_TEXT C'27,30,35'
#define SSR_C_LINE_SL      C'237,118,110'
#define SSR_C_LINE_TP      C'63,191,122'
#define SSR_C_LINE_ENTRY   C'214,168,60'
#define SSR_C_LINE_LONG    C'88,158,236'
#define SSR_C_LINE_SHORT   C'227,164,60'
#define SSR_C_TRADE_WIN    C'63,191,122'
#define SSR_C_TRADE_LOSS   C'237,118,110'
#define SSR_C_PICK_LINE    C'227,164,60'
#define SSR_C_PICK_INFO    C'227,164,60'
#define SSR_C_NEWS_HIGH    C'237,118,110'
#define SSR_C_NEWS_MED     C'227,164,60'
#define SSR_C_NEWS_LOW     C'148,154,165'
#endif

#ifdef SSR_THEME_LIGHT
#define SSR_C_PANEL        C'236,236,236'   // the dialog face
#define SSR_C_PANEL_EDGE   C'88,92,98'      // outer frame, dark on any chart
#define SSR_C_HEADER       C'230,231,234'   // caption strip
#define SSR_C_WELL         C'246,246,246'   // sunken areas: lists, tracks
#define SSR_C_WELL_EDGE    C'150,154,160'
#define SSR_C_GROUP_EDGE   C'178,181,186'   // group-box hairline
#define SSR_C_STATUS       C'230,231,234'   // status strip

//--- text. THREE STEPS, AND 93 IS THE FLOOR - the same lesson the dark
//--- ramp learned, arrived at from the other end: the DARKEST grey that
//--- still separates from the face is about 93, so a fourth step below
//--- TEXT_DIM would be below the readable floor. 16 / 58 / 93.
#define SSR_C_TEXT         C'16,16,16'      // primary
#define SSR_C_TEXT_DIM     C'58,62,68'      // labels, units
#define SSR_C_TEXT_FAINT   C'93,96,100'     // disabled - the READABLE floor

#define SSR_C_BTN          C'225,225,225'
#define SSR_C_BTN_EDGE     C'160,163,168'
#define SSR_C_BTN_TEXT     C'16,16,16'
#define SSR_C_BTN_ON       C'198,224,246'   // engaged toggle
#define SSR_C_BTN_ON_TEXT  C'0,52,96'
#define SSR_C_BTN_ON_EDGE  C'0,84,153'
#define SSR_C_TAB          C'228,228,228'
#define SSR_C_TAB_ON       C'236,236,236'   // the face: the selected tab IS the sheet
#define SSR_C_TAB_EDGE     C'160,164,170'

#define SSR_C_RUN          C'25,109,62'     // PLAYING / LONG
#define SSR_C_HOLD         C'144,79,0'      // PAUSED / degraded
#define SSR_C_STOP         C'170,56,45'     // ERROR / leak / SHORT
#define SSR_C_IDLE         C'93,96,101'     // IDLE / READY

#define SSR_C_BUY          C'44,132,83'
#define SSR_C_BUY_EDGE     C'28,92,58'
#define SSR_C_SELL         C'178,50,38'
#define SSR_C_SELL_EDGE    C'132,36,26'
#define SSR_C_DEAL_TEXT    C'255,255,255'
//--- the disabled deal button. It was 182 grey with WHITE text on it -
//--- 1.95:1, which is not a dimmed button, it is an unreadable one.
#define SSR_C_DEAL_DIM     C'115,117,120'

#define SSR_C_TRACK        C'228,230,233'
#define SSR_C_TRACK_EDGE   C'138,143,149'
#define SSR_C_TRACK_FILL   C'24,103,166'
//--- the speed thumb was 246 on a 228 track: 1.16:1, invisible. On a
//--- light theme the thumb is the DARK part.
#define SSR_C_THUMB        C'20,23,27'
#define SSR_C_THUMB_EDGE   C'80,82,86'
#define SSR_C_TICK         C'150,154,160'

#define SSR_C_ACCENT       C'20,64,120'     // identity; used sparingly
#define SSR_C_PRIMARY      C'0,84,153'      // the one primary action
#define SSR_C_PRIMARY_EDGE C'0,52,96'
#define SSR_C_PRIMARY_TEXT C'255,255,255'

//--- CHART SIDE. These are drawn on the user's CHART, not on the panel,
//--- and the chart's background is theirs and not ours - so they are
//--- picked to read on a dark chart and a light one alike, and they do
//--- not change with the panel theme.
#define SSR_C_LINE_SL      C'192,57,43'
#define SSR_C_LINE_TP      C'46,139,87'
#define SSR_C_LINE_ENTRY   C'214,168,60'
#define SSR_C_LINE_LONG    C'40,102,174'
#define SSR_C_LINE_SHORT   C'214,120,40'
#define SSR_C_TRADE_WIN    C'46,139,87'
#define SSR_C_TRADE_LOSS   C'192,57,43'
#define SSR_C_PICK_LINE    C'214,120,40'
#define SSR_C_PICK_INFO    C'214,120,40'
#define SSR_C_NEWS_HIGH    C'192,57,43'
#define SSR_C_NEWS_MED     C'214,140,40'
#define SSR_C_NEWS_LOW     C'120,124,130'
#endif

#ifdef SSR_THEME_DARK
#define SSR_C_PANEL        C'38,42,51'      // the face, lifted off the chart
#define SSR_C_PANEL_EDGE   C'108,116,130'   // outer frame - see A18
#define SSR_C_HEADER       C'33,36,44'      // caption strip, RECESSED - see below
#define SSR_C_WELL         C'24,27,33'      // sunken areas: lists, tracks
#define SSR_C_WELL_EDGE    C'70,77,90'
#define SSR_C_GROUP_EDGE   C'62,68,81'      // group-box hairline
#define SSR_C_STATUS       C'31,34,42'      // status strip


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
#endif

//+------------------------------------------------------------------+
//| THE CONTRAST TABLE. IT BELONGS TO BOTH PALETTES.                 |
//|                                                                  |
//| It sits AFTER the #endif on purpose. Both blocks above define    |
//| the same token names, so one list holds whichever palette is     |
//| built to the same bar - and neither can ship until it clears.    |
//| Inside a branch it would have audited one theme and blessed the  |
//| other by silence, which is how a light build shipped at 1.95:1   |
//| the first time.                                                  |
//|                                                                  |
//| EVERY ONE OF THESE WAS MEASURED, AND THEY BOTH FAILED FIRST.     |
//|                                                                  |
//| Phase 9 computed the WCAG contrast ratio of every foreground     |
//| this panel draws against every surface it draws it on. On the    |
//| dark palette eleven of thirty-eight pairs were below 4.5:1 -     |
//| the threshold for text this small - and the worst was the build  |
//| tag at 2.06:1, the one label a user is asked to read off a       |
//| screenshot. On the light palette recovered from before v98,      |
//| twenty-four failed: WHITE text on a 182-grey disabled deal       |
//| button at 1.95:1, and a speed thumb at 1.16:1 that was simply    |
//| invisible.                                                       |
//|                                                                  |
//| THE CAPTION WAS THE DARK PALETTE'S PROBLEM SURFACE. Five of the  |
//| eleven were "on the header": it was the lightest thing in the    |
//| panel, so every colour on it had the least room. It is RECESSED  |
//| now, like the status strip at the other end, and the body is     |
//| the lifted part between them - which fixed five failures without |
//| changing a single foreground colour.                             |
//|                                                                  |
//| THERE IS ROOM FOR TWO READABLE GREYS BELOW THE PRIMARY, NOT      |
//| THREE - and both palettes found that independently, from         |
//| opposite ends. Dark: the dimmest grey that clears 4.5:1 on that  |
//| face is about 149, so the ramp was re-spread to 233 / 186 / 149  |
//| rather than extended. Light: the darkest grey that still         |
//| separates from a 236 face is about 93, giving 16 / 58 / 93.      |
//| Three visibly distinct steps, all readable, instead of four of   |
//| which the last was decoration.                                   |
//|                                                                  |
//| There is no way to derive which colour is drawn on which         |
//| surface without a layout engine, so the list is kept by hand -   |
//| and it is kept HERE, in the same file as the tokens, where       |
//| changing one and forgetting the other means editing two things   |
//| that touch.                                                      |
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
//--- THE THUMB SITS ON THE FILL NOW.
//---
//--- It did not before: the segmented track made the thumb a whole cell
//--- with its own border, so it was only ever measured against the
//--- groove. A thumb that slides ALONG the fill has to clear it too -
//--- and the light palette's thumb was 1.67:1 on its own fill, which is
//--- a marker you cannot see in the half of the track that matters.
//--- Solved by moving the thumb, not the fill: near-black clears the
//--- light groove, the fill and the panel face at once.
//--- SSR_CONTRAST: SSR_C_THUMB on SSR_C_TRACK ui
//--- SSR_CONTRAST: SSR_C_THUMB on SSR_C_TRACK_FILL ui
//--- SSR_CONTRAST: SSR_C_THUMB on SSR_C_PANEL ui
//--- SSR_CONTRAST: SSR_C_TRACK_FILL on SSR_C_TRACK ui

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
//+------------------------------------------------------------------+
//| THE LAYOUT SWITCH, and it is separate from the palette on purpose.|
//|                                                                  |
//| SSR_LAYOUT_RAIL is design 08: a 310 px panel with the four tabs   |
//| standing in a rail down the left of the sheet, and the six        |
//| always-reachable actions in a strip where the tab row used to be. |
//| Comment it out and the 420 px panel with its horizontal tabs and  |
//| its 104 px side column comes back, unchanged.                     |
//|                                                                  |
//| It is a switch for the same reason the palette is one: this is a  |
//| large change to a layout that works, on a terminal I cannot run,  |
//| and one commented line has to be able to undo it.                 |
//|                                                                  |
//| 310, NOT 300. The mockup was 300 with a 36 px rail carrying        |
//| "TRD / POS / STA / SES". Real tab names in two languages need 44,  |
//| and the sheet must not lose the ten pixels to pay for it - at 245  |
//| it is already fifty narrower than the one that ships today.        |
//+------------------------------------------------------------------+
#define SSR_LAYOUT_RAIL

#ifdef SSR_LAYOUT_RAIL
#define SSR_PANEL_W        310
#define SSR_RAIL_W         44      // the vertical tab rail
#define SSR_ACT_H          21      // the action strip that replaced the tabs
#else
#define SSR_PANEL_W        420
#define SSR_RAIL_W         0
#define SSR_ACT_H          0
#endif
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

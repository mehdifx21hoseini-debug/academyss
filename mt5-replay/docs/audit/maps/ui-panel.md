# ARCHITECTURE MAP - subsystem `ui-panel`

Primary file: `/home/user/academyss/mt5-replay/MQL5/Include/SSReplay/Ui/SSR_Panel.mqh` (3049 lines, one class).
Build v125. Layout switch `SSR_LAYOUT_RAIL` is **defined** (`SSR_Theme.mqh:484`), so every
number below is the 310 px rail layout unless the 420 px fallback is named.

---

## 1. The one class

### `CSSRPanel` (`SSR_Panel.mqh:67`)
**Responsibility.** A *view* over `SSRUiState` and a *sender* of commands. It never touches the
controller, the clock or the account; it renders what `CSSRReplayPort::ReadState` hands it and
forwards what the user pressed. It owns no engine state and computes no engine value
(the Prop sheet in particular divides nothing - every fraction arrives pre-clamped).

**Composition (owned by value):**
| member | type | role |
|---|---|---|
| `m_w` | `CSSRWidgets` | every chart object, prefix `m_prefix` (default `SSRP_`) |
| `m_keys` | `CSSRKeyCard` | shortcut list, own prefix `SSRK_` |
| `m_palette` | `CSSRPalette` | Ctrl+K command palette, own prefix `SSRX_` |
| `m_state` | `SSRUiState` | the last frame's state snapshot, flat, pointer-free |

**Not owned (raw pointers, NULL-checked at every call site):**
`m_port` (`CSSRReplayPort*`), `m_flight` (`CSSRFlightRecorder*`).

---

## 2. Public surface (what callers may use)

### Lifecycle
| method | line | notes |
|---|---|---|
| `Create(chart_id, port, prefix="SSRP_")` | 301 | `m_w.RemoveAll()`, saves 4 chart properties, forces `CHART_EVENT_MOUSE_MOVE=true`, `CHART_QUICK_NAVIGATION=false`, `CHART_KEYBOARD_CONTROL=false`, `RestorePlace()`, then one `Render()` |
| `Destroy()` | 359 | key card down, palette hidden, `m_w.RemoveAll()`, restores the 4 chart properties |
| `SetFlightRecorder(f)` | 298 | optional; NULL is normal |

### Per-frame
| method | line | notes |
|---|---|---|
| `Render()` | 631 | pulls state, repaints, always ends in `ChartRedraw` (audit A20) |
| `RenderDragging()` | 615 | 30 ms-thinned `Render()` for drag events |
| `PollClicks() -> ENUM_SSR_CMD` | 2445 | the **only** click mechanism; returns the command the *host* must run |

### Input
| method | line | notes |
|---|---|---|
| `OnEvent(id,lparam,dparam,sparam) -> bool` | 2783 | `CHARTEVENT_KEYDOWN`, `CHARTEVENT_OBJECT_ENDEDIT`, `CHARTEVENT_MOUSE_MOVE`. **`CHARTEVENT_OBJECT_CLICK` is deliberately not handled** (2878) |
| `Dispatch(action_string) -> ENUM_SSR_CMD` | 2564 | object-name -> verb; shared by the poll, the palette and the tests |
| `Execute(cmd) -> bool` / `ExecuteInner(cmd)` | 2183 / 2281 | logs every command to `Print` and the flight recorder |
| `Owns(cmd) -> bool` | 2165 | false only for `NONE, SESSIONS, JUMP, REVIEW, REPLAY_FROM_HERE` |
| `RunChosen()` | 2423 | drains a palette choice down the existing key/button paths |
| `TradeButton(id)`, `StepRisk(dir)`, `StepTrail(dir)` | 2108 / 2144 / 2129 | risk ladder `0.10 .25 .50 1 2 3 5`; trail ladder `0 50 100 150 200 300 500` |
| `SpeedFromPixel(mx)`, `OnTrack(mx,my)` | 2370 / 2378 | groove drag maths |

### Reset confirmation
`ResetWithConfirm()` 2233, `DisarmReset()` 2260, `ResetArmed()` 2269, `ResetIsArmed()` 2978,
`ResetWarningText()` 2979. Two presses inside `SSR_CONFIRM_MS` (4000 ms); **skipped entirely when
`closed_trades + open_positions == 0`**; *any other command* disarms it (2190).

### Read-only seams (for tests and vitals)
`X() Y() Tab() Corner() IsCollapsed() IsCompact() IsPro() IsTall() RowCap() PanelH()
Renders() Writes() ObjectCount() PaintWrites() ResetPaintWrites() FrameOverflowRight()
FrameOverflowBottom() StateInto(out)`.
`SetCorner(c)` 384 and `SnapToCorner()` 596 exist but no object sends `"move"` any more (932, 2603).

---

## 3. Who calls it

Only `MQL5/Experts/SSReplay/SSReplayStandalone.mq5`:
* `1463  g_panel_chart = ChartID();`  ← **the panel is on the EA's own chart**, which after the
  one-window handover *is* the replay chart. Events therefore do arrive (see Invariant I1).
* `1467  g_panel.Create(g_panel_chart, GetPointer(g_gport));`
* `1559  g_panel.SetFlightRecorder(...)`
* `3057  ENUM_SSR_CMD host_cmd = g_panel.PollClicks();`  (only when `!modal`)
* `3063  if(!modal && now_ms - g_panel_paint >= 100) { ...; g_panel.Render(); }` ← **10 fps**
* `3228  if(g_panel.OnEvent(id,lparam,dparam,sparam)) return;` - after the session dialog, the
  range dialog, the flight-recorder key log and the review/reveal cards.
* `2118  g_panel.Destroy();`
Host-owned commands come back through `RunHostCommand` (SESSIONS / JUMP / REVIEW).
Tests: `Scripts/SSReplay/Tests/SSR_T5_Ui.mq5`, `Scripts/SSReplay/QA/SSR_QA_Smoke.mq5`
(stages 18/38/42 - prefix `SSRM_`, `SSRT_`, `SSRL_`).

---

## 4. Render pipeline, in order

```
Render()                                                 631
  m_renders++ ; m_w.ResetExtent()
  m_port.ReadState(m_state)            (or m_state.Init() when no port)
  if(m_closed)  -> HideBody(true); HideCaption(true); Button "reopen"; ChartRedraw; RETURN   649
  m_w.Remove("reopen"); HideCaption(false)                                                  659
  m_compact = (chart_h > 0 && chart_h < SSR_PANEL_H+24)        i.e. < 360 px                 679
     on change -> HideSheetArea(m_compact) + Print                                           682
  m_tall = (m_pro && !m_compact && chart_h >= SSR_PANEL_TALL_H+24)  i.e. >= 500 px           702
     on change -> HideSheets() + Print                                                       711
  H = BodyH() ; ClampToChart(W,H)                                                            716
  Rect "bg" (x,y,310,H)                                                                      720
  DrawCaption(x,y,W)                                                                         721
  if(m_collapsed) -> HideBody(true); ChartRedraw; RETURN                                      723
  HideBody(false)                                                                            729
  cy = y+HEADER_H+3 (=y+23)
  cy = DrawClock(x,cy,W)        -> +32   (y+55)                                              732
  cy = DrawTransport(x,cy,W)    -> +27   (y+82)                                              733
  cy = DrawSpeed(x,cy,W)        -> +21   (y+103)                                             734
  if(!m_compact) {
      if(m_tab >= TabCount()) m_tab = SSR_TAB_STATS                                          745
      RAIL:      cy = DrawActions(x,cy,W) -> +21 (y+124)                                     750
                 DrawRail(x+8, cy+4)                                                         751
                 DrawSheet(x+8+44+5, cy+4, W-16-44-5 = 245)                                  752
      FALLBACK:  cy = DrawTabs(...);  DrawSide(x+8,cy+4);  DrawSheet(x+8+104+5, cy+4, 293)   755
  }
  DrawStatus(x, y+H-STATUS_H-1, W)                                                           764
  CheckFrame(x,y,W,H)                                                                        765
  if(m_keys.IsUp())  m_keys.Show(m_chart)          // z-order: cards must be drawn last      776
  new-ticket scan -> m_toast_text / m_toast_until (+4000 ms)                                 787
  Toast "fill" at y+H-STATUS_H-24  /  ToastClear                                             803
  if(m_palette.IsUp()) m_palette.Render()                                                    816
  ChartRedraw(m_chart)                                                                       826
```

### Geometry actually produced (rail, standard sheet)
`SSR_PANEL_W 310`, `SSR_PANEL_H 336` (=23+32+27+21+21+186+18+8), `SSR_PANEL_TALL_H 476`,
`SSR_PANEL_COMPACT_H 128`, `SSR_PAD 8`, `SSR_GAP 5`, `SSR_ROW_H 19`, `SSR_BTN_H 22`,
`SSR_HEADER_H 20`, `SSR_STATUS_H 18`, `SSR_RAIL_W 44`, `SSR_ACT_H 21`, `SSR_SHEET_H 186`,
`SSR_SHEET_GROW 140`, `SSR_TRACK_H 16`, `SSR_CONFIRM_MS 4000`, `SSR_POS_MAX 12`,
`SSR_TAB_COUNT 4`, `SSR_TAB_PROP 4`, `SSR_TAB_MAX 5`, `SSR_SPEED_LADDER_SIZE 20`.

* sheet width **245** (`310 - 2*8 - 44 - 5`); sheet top `y+128`, bottom `y+314`; status `y+317..y+335`.
* transport: `pw = 294 - (24 + 4*24 + 58 + 5*3 + 10) = 91`; last control (`reset`, 58 wide) ends `x+302`.
* speed: `m_track_x = x+120`, `m_track_y = y+87`, `m_track_w = 130` (6.5 px per stop, 20 stops).
* `PosGroupH() = 134` standard / `274` tall; `PosCap() = (PosGroupH()-22)/(19+1)` = **5** / **12** (capped at `SSR_POS_MAX`).
* rail: 5 cells of 22 px + 3 gap = 122 px inside the 186 px sheet.

### Three modes, three flags
| flag | set by | meaning |
|---|---|---|
| `m_closed` | `Dispatch("close"/"reopen")` | whole panel off the chart, one `reopen` button left. **Not persisted** |
| `m_collapsed` | `SSR_CMD_COLLAPSE` | caption only, `BodyH() = 22`. Persisted |
| `m_compact` | measured from `CHART_HEIGHT_IN_PIXELS` each frame | drops tabs+sheet, `BodyH() = 128`. Never persisted, never user-chosen |
| `m_pro` / `m_tall` | `SSR_CMD_PANEL_SIZE` (P) / recomputed each frame | the *wish* is persisted, the *fact* is not; `m_pro_why` carries the refusal to the status strip |

---

## 5. State owned by the panel (nothing else holds it)

Placement: `m_x m_y m_corner m_collapsed m_pro m_tab` (persisted), `m_place_loaded`.
Chart properties saved for restore: `m_saved_mouse_move m_saved_mouse_scroll m_saved_quick_nav
m_saved_key_control m_saved`.
Interaction: `m_dragging m_drag_dx m_drag_dy m_track_drag m_track_x m_track_y m_track_w`
`m_last_btn m_last_btn_ms` (200 ms per-name debounce) `m_tag_focus m_tag_sent m_tag_x/y/w/h`.
Transient UI: `m_reset_armed_ms m_reset_warning m_pending_cmd m_last_ticket m_toast_text
m_toast_until m_pro_said m_pro_why m_last_drag_paint`.
Instruments: `m_renders m_writes m_over_r m_over_b` (+ `m_w.Writes()`, `m_w.MaxRight/MaxBottom`).
Label cache: `m_cache[128] m_cache_x[128] m_cache_y[128]`, sentinel `"\x01"` / `-32000`.

### Label slot map (`SSR_SLOTS 128`) - authoritative
```
  0 title      1 capinfo   2 clock     3 prog      4 spdlbl   5 spdval   6 spdmean  55 build
 10 risklbl   11 riskval  12 setuprow(side)  13 slrow  14 tprow  15 rrrow  16 sizerow
 17 setuprow(order_why)   18 hintrow  19 riskmon   20 posempty
 30 posmore | st1         31 poshint | st2         32 trlbl | st3
 33 st4      34 st5       35 st6      36 st7
 40 ses1     41 ses2      42 ses3     43 ses4     44 keyhint  45 ses5   46 ses6
 50 stbal    51 stflt     52 stopen   53 stfid    54 stspread
 60 pp_state 61 pp_rules  62..69 PropRow pairs (slot, slot+1)  70 pp_dl  71 pp_head
 80+r pr<r>  92+r pl<r>  104+r pn<r>   (r < SSR_POS_MAX = 12  ->  80..91, 92..103, 104..115)
```
Slots 30/31/32 are shared by two *different* ids (Positions vs Stats). Safe only because the two
sheets are mutually exclusive **and** their texts always differ; `Text()`'s `m_w.Exists(id)` guard
is what makes it safe rather than the slot numbering. **Slot 12 and slot 17 are two caches for the
same object `setuprow` at the same coordinates** - see finding ui-panel-5.

---

## 6. Object-name inventory (prefix `SSRP_`)

| group | names |
|---|---|
| frame / caption | `bg hdr title build capinfo chfid chfid_bg chblind chblind_bg chprop chprop_bg collapse close` |
| removed every frame | `palette keys move` (v125 removals, 932-934) |
| closed state | `reopen` |
| clock | `clock prog bar_bg bar_fill` |
| transport | `restart back10 back toggle step step10 reset` |
| speed | `spdlbl spdn spdbox spdval spup spdseg_tk spdseg0..spdseg19 spdseg_th spdmean` |
| tabs / rail | `tab0..tab4 tabline` |
| actions (rail) / side column (fallback) | `lines sessions fidelity`; removed: `follow bookmark jump` |
| Trade sheet | `g1_fr g1_lb g1_lg risklbl riskmon riskdn riskval riskup taglbl tagbox g2_fr g2_lb g2_lg armbtn hintrow setuprow slrow tprow rrrow sizerow openln flipbtn enbtn clrbtn buy sell` |
| Positions sheet | `g1_* posempty pr0..N pn0..N pl0..N ph0..N pb0..N px0..N poshint posmore be flat trlbl trdn trup troff` |
| Stats sheet | `g1_* st1 st2 st3 g2_* st4 st5 st6 stmt st7` |
| Prop sheet | `pp_state pp_rules m0_l m0_v m0_bg m0_fill m0_lim .. m3_* pp_dl pp_head pp_reset` |
| Session sheet | `g1_* ses1 ses2 ses3 g2_* ses4 keyhint ses5 ses6` |
| status | `status stbal stflt stopen stspread stfid` |
| toast | `fill fill_bg fill_ac` |

Three hide/remove lists exist and they do **not** agree:
* `HideSheets()` 1284 - 70 named ids (with `spreadrow`/`traderr` listed twice, and dead entries
  `g3_fr g3_lb g3_lg pp_g`) + 4x3 meter parts + 12x6 position-row parts = **154 `Remove()` calls**,
  plus `ReadTag()` and `Hide("tagbox", true)`. Called from `DrawSheet` **every frame**.
* `HideSheetArea(bool)` 2042 - `tab0 tab1 tab2 tab3 tabline lines sessions fidelity` (**no `tab4`**),
  then `HideSheets()` when hiding. Called only on a compact transition.
* `HideBody(bool)` 2077 - 30 ids + `tab0..tab4` + `spdseg0..19` + `spdseg_tk` + `spdseg_th`,
  then `HideSheets()` when hiding. Called **every frame** (`false` at 729) and on
  collapse/close (`true`).
* `HideCaption(bool)` 2067 - 13 ids, one list used in both directions.

---

## 7. Click dispatch

MetaTrader delivers `OnChartEvent` only to the chart the program is attached to, so the panel does
not wait to be told: `PollClicks()` walks `ObjectsTotal(m_chart,-1,OBJ_BUTTON)` **backwards**,
skips names that do not start with `m_prefix`, reads `OBJPROP_STATE`, **clears it first**, then
debounces (`name == m_last_btn && now-m_last_btn_ms < 200` -> repaint only), then `Dispatch()`.
The palette is polled *first and alone* (2466) so one click is never read twice. A pending
palette command chosen with ENTER waits one pump in `m_pending_cmd` (2459).

`Dispatch()` order of tests (2564):
1. `ReadTag()` (always, on the way in)
2. `tabN` - `StringLen==4 && prefix "tab"` -> `m_tab`, clears `m_tag_focus`, `SavePlace()`
3. `spdseg<digits>` - `AllDigits` guard rejects `_tk` / `_th`
4. `move` (dead), `stmt`, `pp_reset`, `close`, `reopen`
5. `p{x|h|b}<digits>` - row buttons, bounds-checked against `min(pos_rows, PosCap())`; the row
   number is parsed with `AllDigits` (so `px10`/`px11` work)
6. `trdn` / `trup` / `troff`
7. the command table (`toggle step step10 back back10 reset restart follow bookmark fidelity
   jump sessions lines armbtn flipbtn spup spdn collapse keys`), plus inline handlers for
   `clrbtn enbtn palette openln`
8. fall-through: `DisarmReset()` then `TradeButton(what)` (`buy sell flat be riskdn riskup`)
9. `Owns(c) ? Execute(c) : return c` (the host runs it)

## 8. Keyboard routing (`OnEvent`)
```
KEYDOWN && m_palette.IsUp()          -> palette owns it, always returns true        2814
KEYDOWN && K && CONTROL held         -> m_palette.Toggle()                          2828
KEYDOWN && m_tag_focus               -> only ESC/ENTER act (leave the box); true    2835
OBJECT_ENDEDIT on prefix+"tagbox"    -> ReadTag(); m_tag_focus=false                2847
KEYDOWN                              -> SSRKeyToCommand; NONE -> false;
                                        !Owns(c) -> false (host gets S/J/A);
                                        else Execute + Render + true                2854
MOUSE_MOVE                           -> tag-box focus, then track drag,
                                        then caption drag; SavePlace on release     2885
```
`m_tag_focus` is set **only** from `CHARTEVENT_MOUSE_MOVE` hit-testing, and only while
`m_tab == SSR_TAB_TRADE && !m_collapsed && m_tag_w > 0`.
Key table (`SSR_Keys.mqh:125`): every command the table binds is implemented by `ExecuteInner`
or handed to the host - there is no dead key in v125.

## 9. Status ladder (`DrawStatus` 1915) - highest first
1. `ResetArmed()` -> `m_reset_warning` (English literal, 2253)
2. `m_port.TradeError() != ""` -> the refusal
3. `m_pro_why != "" && GetTickCount()-m_pro_said < 4000` -> the tall-panel refusal
4. `TooNarrow()` (chart width < 310) -> standing condition
5. the five numbers: `stbal x+8`, `stflt x+116`, `stopen x+218`, `stspread x+268`, `stfid x+330`
Levels 1-4 all write slot 50 / id `stbal` and `Hide()` the other four.

## 10. What it writes outside itself
* **Disk:** `MQL5\Files\SSReplay\panel.ini` (`SSR_PANEL_FILE`, 64) via `CSSRSessionFile`, section
  `[panel]`, keys `x y corner collapsed tab pro`. Written by `SavePlace()` from: `SetCorner`,
  `SSR_CMD_COLLAPSE`, `SSR_CMD_PANEL_SIZE`, a tab change, and drag release. Gated on
  `m_place_loaded` so a save can never precede the first load. `FolderCreate("SSReplay")` first.
  Restored by `RestorePlace()` with a `0..8000` sanity bound and `tab < SSR_TAB_MAX`.
* **Chart properties:** `CHART_EVENT_MOUSE_MOVE`, `CHART_QUICK_NAVIGATION`,
  `CHART_KEYBOARD_CONTROL`, `CHART_MOUSE_SCROLL` (toggled off during a drag, restored on release
  from `m_saved_mouse_scroll`). All four restored in `Destroy()`.
* **Chart objects:** everything in section 6, plus `SSRK_*` (key card) and `SSRX_*` (palette).
* **Log / flight recorder:** one line per command (`Execute` 2201/2207), per row button (2684),
  per trailing change (2703), per mode change (683, 712), and the overflow report (3030).

## 11. Invariants the code relies on
* **I1** `g_panel_chart == ChartID()` (expert 1463). The panel's own comments repeatedly state it
  "never receives a mouse coordinate" (929, 437-443 in `SSR_Widgets.mqh`) - that premise is false
  as wired: mouse and key events *do* reach it, which is why the drag and the trackbar drag work.
  Any redesign must decide which of the two statements is the contract.
* **I2** Creation order is the only z-order. Cards are re-`Show()`n after the panel every frame
  (776) precisely to stay on top; `CSSRKeyCard::Show` achieves that by deleting and recreating.
* **I3** `ObjectCreate` refuses an existing name -> one id per object, ever. The `pn`/`px`
  collision (1546-1552) is the documented scar.
* **I4** MetaTrader draws 63 characters of `OBJPROP_TEXT`; `Clip()` (242) caps at **62** and marks
  the cut with `~`. Only 5 call sites clip (`prog`, `pp_rules`, `pp_head`, `ses3`) - every other
  label is unbounded.
* **I5** `Text()` may skip a write only when text **and** x **and** y are unchanged **and** the
  object still exists (194). Position is part of the key because a drag moves labels without
  changing their text.
* **I6** `CSSRWidgets::Hide()` and `Remove()` both `Forget()` the widget property cache
  unconditionally (`SSR_Widgets.mqh:624, 632`).
* **I7** A sheet the strip no longer has must be **removed**, not merely undrawn - the panel
  repaints from state and never clears the chart (1164-1168, 919-923).
* **I8** `PosCap()` is derived from `PosGroupH()`, and `HideSheets` sweeps `SSR_POS_MAX` rows, not
  the current cap, because the cap has already changed by the time it runs (1328-1331).
* **I9** The Prop tab exists only while `m_state.prop_on`; `TabCount()` is asked, never assumed,
  and `m_tab` is clamped to `SSR_TAB_STATS` on the first frame that knows (745).
* **I10** `CheckFrame` only sees **sized** objects (`Rect/Button/Edit` call `Extent`). A label that
  runs long or is anchored outside the frame is invisible to the instrument
  (`SSR_Widgets.mqh:125-128`). Nothing in the codebase ever reads `FrameOverflowRight/Bottom`.
* **I11** The tag box is hidden, never deleted, because deleting it 25x/s "makes the box
  impossible to type in at all" (1286-1297).
* **I12** `Owns()` and `ExecuteInner` must stay in step, or a key is claimed and dies (2860-2869).

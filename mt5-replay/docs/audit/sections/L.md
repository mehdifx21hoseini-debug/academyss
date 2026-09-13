## L. CURRENT UI/UX AUDIT

*Scope: every user-facing surface the product draws — `MQL5/Include/SSReplay/Ui/` (10 files),
`CSSRFirstRun`, the chart-side objects that carry words (`SSR_TradeLines.mqh`), and the host
wiring in `SSReplayStandalone.mq5` that decides which of them a person ever sees. Build v125,
`SSR_LAYOUT_RAIL` and `SSR_THEME_RAIL` both active. Every pixel number below was re-derived from
the constants in `SSR_Theme.mqh`, not taken from a comment — four of the six numbers in the
metrics comment that a designer is meant to size a new row against are stale
(`ui-plumbing-11`, CONFIRMED).*

---

### L.1 The surfaces, and how input reaches each one

| Surface | Class / file | Prefix | Size | Input path | Translated |
|---|---|---|---|---|---|
| Main panel | `CSSRPanel` (`SSR_Panel.mqh`, 3049 lines) | `SSRP_` | 310 x 336 (476 tall, 128 compact, 22 collapsed) | `PollClicks()` latch poll + `OnEvent` keys/mouse | yes, except 3 strings |
| Key card | `CSSRKeyCard` | `SSRK_` | 372 x 348 at (14,40) | opened by `H` / `SSR_CMD_KEYS` only | **no** (`ui-plumbing-1`) |
| Command palette | `CSSRPalette` | `SSRX_` | 330 wide, 8 rows | `Ctrl+K` only | yes |
| Setup wizard | `CSSRSetupPanel` | `SSRS_` | 304 x up to 482 | `Poll()` latch poll | yes |
| Range / "jump" dialog | `CSSRRangeDialog` | `SSRD_` | 248 x 214 | `CHARTEVENT_OBJECT_CLICK` | yes |
| Session picker | `CSSRSessionDialog` | `SSRSD_` | 420 x 260 | `CHARTEVENT_OBJECT_CLICK` | yes |
| Review card | `CSSRReviewCard` | `SSRR2_` | 520 x 320+ | latch poll + `OnKey` | rows yes, observations **no** |
| Reveal card | `CSSRRevealCard` | `SSRV_` | 360 x 132 | latch poll | yes |
| First-run card | `CSSRFirstRun` | `SSRF_` | 396 x 104 at (14,376) | none — 25 s timer | yes |
| Fill toast | inside `CSSRPanel` | `SSRP_fill*` | panel width x 20 | none (notification) | **no** (see L.8) |
| Planning lines, position/trade levels | `CSSRTradeLines` | `SSR_L_*` | chart-wide | dragged on the chart | **no** (`chart-12`) |

[CONFIRMED FROM CODE] Eleven distinct drawn surfaces, nine object-name prefixes, and **three
different input mechanisms** (latch polling, `CHARTEVENT_OBJECT_CLICK`, and `CHARTEVENT_KEYDOWN`
/`MOUSE_MOVE`). The panel deliberately refuses the click event and uses only the latch poll
(`SSR_Panel.mqh:2878`, "CHARTEVENT_OBJECT_CLICK is deliberately not handled here"), while the two
dialogs use only the click event. That split is defensible — the panel must work from a chart the
program may not own — but it is the root of `host-expert-7` (CONFIRMED, MEDIUM): the session and
range dialogs return `false` for every non-click event, so keys fall through both dialog blocks
into `g_panel.OnEvent` at `SSReplayStandalone.mq5:3228`. **Space starts the replay, `Tab` opens a
virtual trade, and `0` arms the session reset while the user is reading a modal dialog**, and the
panel's `Render()` then recreates every panel object on top of that dialog, because creation order
is the only z-order MetaTrader has.

---

### L.2 Information architecture

#### L.2.1 The vertical grammar of the panel

[CONFIRMED FROM CODE] `SSR_Panel.mqh:631-826`, with the heights from `SSR_Theme.mqh:499`:

```
y+0    caption 23      identity, build tag, run state, mode chips, [-] [X]
y+23   clock   32      masked clock + progress bar
y+55   transport 27    |<  <<  <  [PLAY/PAUSE 91px]  >  >>   ··· Reset 58
y+82   speed   21      label, -, value box, +, 20-cell slider (130px), meaning
y+103  actions 21      Lines | Saved | Detail          (rail layout only)
y+124  ── hairline
y+128  rail 44 x sheet 245                             186 px tall
y+317  status  18      balance | float | n open | spread | fidelity
y+336  end
```

The split is stated in the code and it is a good one: **"keeps what is OPERATED — clock,
transport, speed, status — and drops what is only CONSULTED"** (`SSR_Panel.mqh:670-674`). The
caption is explicitly a status line, not a title bar (`:853-866`), and modes are drawn as chips
with *text on a tinted plate* rather than as colour alone, "because a mode carried by colour alone
is a mode a colour-blind trader cannot read" (`:860-862`). [RECOMMENDATION] Preserve both
decisions verbatim in any redesign; they are the strongest accessibility reasoning in the product.

#### L.2.2 The four sheets, plus a conditional fifth

[CONFIRMED FROM CODE] `TabCount()` (`SSR_Panel.mqh:1103`) returns 5 when `m_state.prop_on`, 4
otherwise, and `m_tab` is re-clamped to `SSR_TAB_STATS` on the frame the answer changes
(`:745-746`) — so a user standing on the Prop tab when `Reset` turns the evaluation off is moved
rather than shown four meters reading zero. This is asked, never assumed, and it is correct.

| Tab | Sheet function | Verdict |
|---|---|---|
| **Trade** (0) | risk ladder, setup tag box, SL/TP/RR/size read-back, arm/flip/clear, BUY/SELL | the only sheet that *does* something; densest, and carries the one control the user types into |
| **Positions** (1) | 5 rows (12 in tall mode), per-row H/B/X, Break-even all / Close all, trailing ladder | the management surface; its row arithmetic is broken in this layout (L.3.2) |
| **Stats** (2) | 7 measures + statement export (`stmt`) | consult-only, fine |
| **Session** (3) | bookmark count, streams+skew, chart-leak advice, **and the four keyboard-hint lines** | a junk drawer (L.2.3) |
| **Prop** (4) | state, rules, 4 meters, headline, reset | conditional, correctly gated |

#### L.2.3 The Session tab is carrying the keyboard guide, and the guide is wrong

[CONFIRMED FROM CODE] `SheetSession` (`SSR_Panel.mqh:1875-1908`) draws four lines,
`T(SSR_S_KEYS_1..4)`, as labels `ses4`, `keyhint`, `ses5`, `ses6`. These four lines are **the only
keyboard guidance anywhere inside the panel**, and they sit behind a tab labelled "Sess" whose
other three rows are bookmark counts and chart-leak diagnostics. Three of the four are now
factually wrong:

* `keys.2` = `"+ - speed    R reset    J jump    B bookmark"` (`SSR_Strings.mqh:500`). `R` is bound
  to `SSR_CMD_LINES_TOGGLE` (`SSR_Keys.mqh:162`) and reset is bound to `0` (`:200`). The actual
  reset key is named nowhere on the panel. Faithfully mistranslated as well:
  `fa.txt:216` reads `R شروع دوباره` ("R start over"). — `ui-plumbing-2` (CONFIRMED).
* `keys.4` = `"caption:  [] corner    -  collapse    X  close"` (`SSR_Strings.mqh:504`;
  `fa.txt:218`). **The `[]` button was deleted in v125** (`SSR_Panel.mqh:934`,
  `m_w.Remove("move")`). The panel's own help text still teaches a control that no longer exists.
  [CONFIRMED FROM CODE] — this is a new consequence of the removal, not in the findings set.
* `keys.3` names `F follow`, which still answers its key but has no button and no other surface
  (L.4.3).

[CONFIRMED FROM CODE] There is a fourth, independent, hand-written key list: `SSRKeyHint()`
(`SSR_Keys.mqh:271`), printed to the Experts log at `SSReplayStandalone.mq5:1694`. It also says
"R reset" and omits `Tab`, `X`, `L`, `0`, `A`, `P` and `H` — `ui-plumbing-3` (CONFIRMED). So the
product ships **three** key lists that can drift (`SSR_S_KEYS_1..4`, `SSRKeyHint()`, and the
literals baked into `SSR_S_FOLLOW`/`SSR_S_JUMP`/`SSR_S_ROW_HINT`/`SSR_S_NOTHING_OPEN`) plus one
generated list (the key card), and the audits cross-check none of them
(`ui-plumbing.md` §10.6).

---

### L.3 The 310 x 336 rail, and the 420 fallback

#### L.3.1 The two layouts

[CONFIRMED FROM CODE] `SSR_Theme.mqh:484-494`. `SSR_LAYOUT_RAIL` defined ⇒ `SSR_PANEL_W 310`,
`SSR_RAIL_W 44`, `SSR_ACT_H 21`; commented out ⇒ `420 / 0 / 0`. The switch is deliberate and the
reasoning is sound ("this is a large change to a layout that works, on a terminal I cannot run,
and one commented line has to be able to undo it", `:477-479`).

| | rail (shipping) | fallback |
|---|---|---|
| panel width | 310 | 420 |
| tab geometry | vertical rail, 5 cells of 44 x 22 | horizontal strip, `(W-16-2(n-1))/n` |
| always-reachable actions | 3-button strip, `bw = (310-16-6)/3 = 96` | 104 px side column |
| **sheet width** | `310-16-44-5 = ` **245** | `420-16-104-5 = ` **295** |

[CONFIRMED FROM CODE] `SSR_PANEL_H` is the literal sum `(23+32+27+21+21+186+18+8) = 336`
(`SSR_Theme.mqh:499`) in **both** layouts — the `21` for the action/tab row is a bare number, not
`SSR_ACT_H` or `SSR_TAB_H`. Changing either constant silently desynchronises the frame height from
its contents. [RECOMMENDATION] Make the 21 symbolic; this is the same failure mode the comment
directly above it congratulates itself for having fixed ("ADDED UP BY THE COMPILER, not by me").

#### L.3.2 The 50 px the sheet lost, and what it broke

The row and column arithmetic in the sheets was written for the **295 px** fallback sheet and was
never re-derived for 245. The code says so itself: `SSR_Panel.mqh:1563-1574` shows its working for
"a 295 px sheet".

* `ui-panel-7` (CONFIRMED, MEDIUM) — the position row's note column is anchored at `x+120` while
  the money column is anchored at `x+w-116 = x+129`. Nine pixels for the nine characters of
  `"  no stop"`. The two things a trader reads on that row are printed over each other, and the
  same applies to `"  sp 20.0"`.
* [INFERENCE] The same 50 px moves `posmore` — the `"+%d not shown"` overflow counter — to
  `x+w-92 = x+153` (`SSR_Panel.mqh:1641`), on the same baseline as `poshint`, which draws
  `"H halves   B stop to entry   X closes"` (37 characters) from `x+8` (`:1628`). At `SSR_FS_SMALL`
  (7 pt Tahoma, ≈4.5 px/char) the hint reaches ≈`x+175`. The comment at `:1633-1639` claims the
  counter now sits "at the far end, where nothing else is" — that was true at 295.
  **[POTENTIAL_RISK]**, and it can never be better than that from source: it depends on glyph metrics
  MQL5 will not report. Registered as `new-19` in D.2, which is the register of defects read from
  source that did **not** go through the refuter process — it is weaker evidence than any
  `verified.json` CONFIRMED and must always be labelled POTENTIAL_RISK.
* `ui-panel-6` (CONFIRMED, MEDIUM) — the status strip's fidelity readout is anchored at `x+330`
  in a 310 px panel. The anchor alone is 20 px past the frame; `"SYNTHETIC TICK !"` adds ~70-80 px
  more. **~90 px of text sits on the candles on every frame of every session**, and the
  `Extent()`/`CheckFrame()` instrument cannot see it because labels are excluded from `Extent` by
  design (`SSR_Widgets.mqh:125-128`, invariant I10).
* `ui-panel-8` (CONFIRMED, LOW) — the speed "meaning" text is drawn into a 52 px reserve
  (`mw = 52` in the rail branch, `SSR_Panel.mqh:1053`); at `SSR_SPEED_MAX` the text is the
  21-character `"as fast as ticks feed"`, unclipped, running onto the price.
* `ui-panel-13` (CONFIRMED, LOW) — the caption chip row (`chfid` + `BLIND` + `PROP`) ends at
  `x+274` when fidelity is degraded, and the collapse button starts at `x+W-42 = x+268`. Six pixels
  of overrun, and no margin even in the good case.

[INFERENCE] Taken together, four of the five confirmed layout defects on this panel are the same
defect: *the 420 layout's pixel arithmetic survived a 310 px re-skin untested.* The 63-character
draw cut and the absence of clipping mean MQL5 gives no feedback when this happens — `Clip()`
exists (`SSR_Panel.mqh:242`) and is applied at exactly **four** call sites (`:960 prog`,
`:1760 pp_rules`, `:1840 pp_head`, `:1892 ses3`). Every other label in a 3049-line panel is
unbounded.

#### L.3.3 The rail cells

[CONFIRMED FROM CODE] `DrawRail` (`SSR_Panel.mqh:1210-1227`) draws `n` cells of 44 x 22 with a
3 px gap — 122 px inside a 186 px sheet. Names come from the short forms
`SSR_S_RTAB_*` (`SSR_Strings.mqh:342-347`): `"Trade"`, `"Pos"`/`"Pos %d"`, `"Stats"`, `"Sess"`,
`"Prop"`. The width was chosen deliberately: "The mockup was 300 with a 36 px rail… Real tab names
in two languages need 44" (`SSR_Theme.mqh:481-483`).

[INFERENCE] POTENTIAL_RISK for the second language. `fa.txt:236-241` gives
`rtab.positions = پوزیشن` (6 glyphs), `rtab.prop = ارزیابی` (7 glyphs), and `rtab.positions.n`
adds a Latin digit to an RTL string. MQL5 has no bidi and no clipping; a mixed-direction
`"پوزیشن 3"` in a 44 px button is a rendering outcome that cannot be determined from source and
has never been seen on a terminal.

#### L.3.4 The speed control: twenty 6.5 px targets

[CONFIRMED FROM CODE] `m_track_w = (x + W - SSR_PAD - mw) - m_track_x` = 130 px in the rail
layout, divided into `SSR_SPEED_LADDER_SIZE = 20` cells by `CSSRWidgets::Slider` — **6.5 px per
stop**. The code names its own limit: "Below about five the cells stop being clickable and the
slider becomes a picture of a control" (`SSR_Panel.mqh:1047-1050`). The design is honest about the
constraint (a click is the only input a chart the program may not own can give), and the groove
drag (`OnTrack`/`SpeedFromPixel`, `:2370-2378`) is the mitigation — but the drag depends on mouse
events, which is the contested contract of L.4.2. If the mouse path is unavailable, the speed
control is twenty 6.5 px targets and two ±1-stop buttons.

#### L.3.5 Compact, tall, collapsed, closed — four responsive modes, one of them broken

[CONFIRMED FROM CODE] Four independent state flags with clean semantics
(`SSR_Panel.mqh:679-714`): `m_compact` is **measured** (chart < 360 px) and never user-chosen;
`m_tall` is a **wish** (`P`, persisted) whose **fact** is recomputed each frame, with the refusal
surfaced on the status strip and both numbers named rather than "not enough room" (`:1979-1987`);
`m_collapsed` is persisted; `m_closed` is not, and leaves one `reopen` button because "a control
that removes its own only way back is a trap" (`:641-647`). This is careful, correct thinking.

Compact mode nevertheless does not work:

* `ui-panel-3` (CONFIRMED, **HIGH**) — `HideSheetArea(true)` at `:682` is undone by
  `HideBody(false)` at `:729` **inside the same `Render()`**. On a chart that shrinks below 360 px
  the five rail tabs, the `tabline` and the three action buttons stay visible at their full-layout
  coordinates — up to 122 px of still-clickable buttons painted on the candles below a 128 px
  panel. *This is precisely the failure compact mode exists to prevent.*
* `ui-panel-4` (CONFIRMED, LOW) — `HideSheetArea`'s id list stops at `tab3`
  (`SSR_Panel.mqh:2044`), so even after `ui-panel-3` is fixed the fifth (Prop) tab is stranded.
* `ui-panel-10` (CONFIRMED, MEDIUM) — in compact mode the fill toast is placed at
  `y + 128 - 18 - 24 = y+86`, height 20, directly on top of the speed row (`y+82..y+101`) and its
  groove, for four seconds per fill, and *above* it in creation order. Compact mode is the mode in
  which the speed control is one of only four things left.

[CONFIRMED FROM CODE] There is no equivalent degradation for a chart that is too **narrow**, and
the code says why: "there is no width at which they all still clear each other… the thing that
would have to be dropped is half of every row" (`SSR_Panel.mqh:484-497`). `TooNarrow()` reports the
condition on the status strip instead. That is the right call for a product with no layout engine.

[CONFIRMED FROM CODE] One gap in the closed state: the `m_closed` branch at `:649-655` returns
**before** `ClampToChart` runs at `:716`. A chart resized while the panel is closed can leave the
76 x 20 `reopen` button — the only way back — outside the visible area, with no recovery short of
reattaching the EA. Severity LOW (the position was clamped on the last open frame), but it
defeats the stated "closed means closed, but not unreachable" contract.

---

### L.4 What v125 removed, and what it cost

Commit `08daaf8`, "six buttons removed on request — and removed, not just undrawn". The removals
are executed correctly: each id is `Remove()`d on the frame that no longer draws it
(`SSR_Panel.mqh:932-934`, `:1192-1195`, `:1238-1241`), which is the only right answer for a panel
that repaints from state and never clears the chart (invariant I7). The **method** is not in
question. The **consequences** are.

| Removed | Was | Still reachable by |
|---|---|---|
| `?` (caption) | opened the key card | `H` only |
| `K` (caption) | opened the command palette | `Ctrl+K` only |
| `[]` (caption) | `SnapToCorner()` — stepped the panel between corners | the palette's `move` entry only |
| `Follow` (action strip / side column) | `SSR_CMD_FOLLOW`, **and carried the detached-chart count** | `F` only |
| `Mark` | `SSR_CMD_BOOKMARK` | `B` only |
| `Jump` | `SSR_CMD_JUMP` | `J` only |

#### L.4.1 The palette is reachable, and documented as unreachable

[CONFIRMED FROM CODE] `SSR_Panel.mqh:2827-2832` opens the palette on `Ctrl+K`, tested *before* the
key table so nothing can shadow it:

```cpp
if(id == CHARTEVENT_KEYDOWN && (int)lparam == SSR_VK_K &&
   TerminalInfoInteger(TERMINAL_KEYSTATE_CONTROL) < 0)
  { m_palette.Toggle(m_chart); return true; }
```

The registry behind it is fully wired: 31 commands in four groups (`SSR_Command.mqh`), and
`RunChosen()` (`:2423`) dispatches both `cmd` and `action` entries down the two paths that already
existed. So the palette works. What is broken is its **discoverability and its documentation**:
`SSR_VK_K` is not in `SSRKeyBindings()`, so `SSRKeyToCommand(75)` returns `SSR_CMD_NONE` and the
generated key card — the product's only key list — cannot mention it; and the code comment three
hundred lines away states the opposite outcome: *"K the command palette had no key and is now
unreachable"* (`SSR_Panel.mqh:929`). — `ui-plumbing-15` (CONFIRMED, LOW).

[INFERENCE] The practical position is worse than "unreachable" would be: a reachable feature that
nobody can find, that the team's own record says was lost, and that is now **the only surviving way
to move the panel** (the palette's `move` entry still runs `SnapToCorner(); SavePlace();` at
`:2603-2610`).

#### L.4.2 "The panel can no longer be moved" — a contract the code contradicts

This is the one place where the stated architecture and the wiring disagree, and it must be
resolved before any redesign, because a great deal depends on which is true.

[CONFIRMED FROM CODE] As wired today:

* `SSReplayStandalone.mq5:1463` — `g_panel_chart = ChartID();` the panel is created on the chart
  the EA is attached to.
* `SSR_Panel.mqh:325` — `Create()` executes `ChartSetInteger(m_chart, CHART_EVENT_MOUSE_MOVE, true);`
* `SSR_Panel.mqh:2885-2966` — `OnEvent` handles `CHARTEVENT_MOUSE_MOVE` in full: tag-box focus
  hit-testing, groove drag, and caption drag with `SavePlace()` on release.
* `SSReplayStandalone.mq5:3228` forwards every chart event to it.

[CONFIRMED FROM CODE] The removal rationale says the opposite: *"the panel cannot be dragged — it
never receives a mouse coordinate on a chart this program is not attached to"*
(`SSR_Panel.mqh:929-931` and the commit body). The same premise is asserted at
`SSR_Widgets.mqh:437-443`. The architecture map records the conflict as unresolved
(`ui-panel.md`, invariant I1: *"that premise is false as wired… Any redesign must decide which of
the two statements is the contract"*).

[INFERENCE] Only one of two states is real, and both are bad in different ways:

1. **Mouse events do arrive** (what the wiring says). Then the caption drag and the groove drag
   both work, the `[]` button was removed for a reason that does not hold, `ui-panel-11`
   (POTENTIAL_RISK: the tag box hidden and re-shown 10x/s while it may hold the keyboard) is live,
   and the drag path is completely untested because nobody believes it exists.
2. **Mouse events do not arrive.** Then the panel truly cannot be moved by any means except the
   invisible palette entry; `m_dragging`, `m_drag_dx/dy`, `m_track_drag`, `OnTrack`,
   `SpeedFromPixel`, `m_tag_focus` and the four `CHART_MOUSE_SCROLL` save/restore calls are all
   dead code; `m_tag_focus` is never set, so the Trade tab's setup-name box **can never take
   focus** and the hotkey-suppression logic at `:2835` never engages; and the speed control
   degrades to twenty 6.5 px click targets.

[RECOMMENDATION] Settle this on a terminal before anything else in the UI is touched. It decides
whether the panel is drag-positionable, whether the setup tag box is usable at all, and whether
the speed slider is a slider or a row of very small buttons. Until then, treat both the drag and
the tag box as unvalidated. The author has never run this build on MT5.

#### L.4.3 `Follow` took the only detached-chart signal with it

[CONFIRMED FROM CODE] The removed `Follow` button carried the count in its own label
(`StringFormat(T(SSR_S_FOLLOW_N), m_state.charts_detached)`, and it lit when non-zero — see the
v124 code in the diff of `08daaf8`). The commit body names this cost explicitly: *"One signal went
with Follow that is worth naming… Nothing else on the panel says that now."*

[CONFIRMED FROM CODE] Nothing else says it anywhere. `chart-10` (CONFIRMED, LOW): the observer
seam `CSSRChartManager::SetObserver` has no production caller, and `charts_detached` is written on
the wire by `CSSRGroupPort` and **read by no draw site** — a grep over `SSR_Panel.mqh` matches only
the struct declaration, its `Init()` and the assignment. The user-visible result: *the replay
advances, the candles stop moving, and the interface says nothing at all.* The recovery is `F`,
which is now a key with no button, named on one line of a hint block behind the Session tab
(`keys.3`).

[INFERENCE] This is the single most damaging consequence of the removal set, because it is the
only one that removes *information* rather than *a shortcut*. Bookmark and Jump lost buttons;
Follow lost a readout.

#### L.4.4 The key card now has no in-product discovery path

[CONFIRMED FROM CODE] After the `?` button was removed, the key card opens only on `H`. The string
that teaches `H` is `SSR_S_FIRSTRUN_3`, `"H lists every key. All virtual - nothing reaches a
broker."` (`SSR_Strings.mqh:583`), drawn only by `CSSRFirstRun`. `host-expert-4` (CONFIRMED):
with the default `InpFirstCard=true, InpOneChart=true`, the first-run card is shown on **neither**
pass of the one-window handover, because the guard at `SSReplayStandalone.mq5:1736` tests
`!one_chart_ok`. And `ui-dialogs-14` (CONFIRMED): even where the guard lets it through, `Show()`
reports success without checking that its fixed position `y=376..480` fits the chart, so on a
chart under ~480 px the card is drawn off-screen, `seen.txt` is written anyway, and the one piece
of onboarding this product has is consumed unread.

[CONFIRMED FROM CODE] The only other `H` printed anywhere on screen is `SSR_S_ROW_HINT`,
`"H halves   B stop to entry   X closes"` (`SSR_Strings.mqh:394`) — which names three *row
buttons*, not keys. `ui-plumbing-14` (CONFIRMED): a user who reads that line as a key legend and
presses the keys gets the key card, a bookmark, and a flip of their planning lines — three
unrelated actions, one of which changes trade state.

[INFERENCE] Net: in the default configuration the product's complete keyboard documentation is
behind a key that the product never names, and the `?` that used to stand in for it is gone.

#### L.4.5 Orphans left behind

[CONFIRMED FROM CODE] Eight catalogue entries now have **no draw site anywhere in the tree**
(verified by grep over all `.mqh`/`.mq5` excluding `SSR_Strings.mqh`): `SSR_S_FOLLOW`,
`SSR_S_FOLLOW_N`, `SSR_S_BOOKMARK`, `SSR_S_JUMP`, `SSR_S_ACT_FOLLOW`, `SSR_S_ACT_FOLLOW_N`,
`SSR_S_ACT_BOOKMARK`, `SSR_S_ACT_JUMP`. They remain part of the 190-string contract and are still
translated in `fa.txt:242-247`, so `SSRTranslated()` reports 190/190 for a catalogue in which 8
strings are unreachable.

[CONFIRMED FROM CODE] Nine `m_w.Remove()` calls now run on **every frame, forever** — three in
`DrawCaption` (`:932-934`), three in `DrawActions` (`:1238-1241`), three in `DrawSide`
(`:1192-1195`) — to clean up objects that only a v124 installation can have. Correct on the
upgrade frame; permanent thereafter.

[CONFIRMED FROM CODE] Two stale strings name removed controls: `SSR_S_KEYS_4` (L.2.3) and the
startup log line *"no saved position - starting at %d,%d (drag it by the title bar, or press
Move)"* at `SSR_Panel.mqh:354`.

---

### L.5 The setup wizard

[CONFIRMED FROM CODE] `CSSRSetupPanel` is a 4-step wizard (QUICK → SETTINGS → MODE → START),
304 px wide, centred on the **tallest** step (`SSR_SETUP_H_MAX = 482`) so it does not jump under
the hand pressing Next (`:527-541`), and it warns to the log when the chart is shorter than the
526 px it needs (`:511-517`). The design intent is good. Its execution has the largest single
defect in the UI subsystem:

* `ui-dialogs-1` (CONFIRMED, **HIGH**) — `ReadAll()` runs on steps that contain no `OBJ_EDIT`, and
  `EditText()` returns `""` both for an empty box and an absent one (`SSR_Widgets.mqh:350-356`).
  Walking the wizard normally therefore **silently clears `session_name` and `extra_tfs`**; step 3
  recaps "Save as: not saved", `CfgSession()` is `""`, and `OnDeinit`'s `if(CfgSession() != "")`
  never runs — **the whole session is never written to disk and cannot be resumed.**
* `ui-dialogs-2` (CONFIRMED, MEDIUM) — an open pseudo-combo survives a step change and is redrawn
  last (i.e. on top) over the START step, so the click aimed at "START REPLAY HERE" applies a
  preset instead.
* `ui-dialogs-9` (CONFIRMED, LOW) — `ReadAll` clamps balance/risk/spread/speed and **not** the
  three prop numbers, so a typed `0` silently deletes a prop rule while the panel keeps drawing
  the chips and meters. The panel's own preset *file* loader refuses exactly this shape
  (`:342`); the keyboard is not validated.
* `ui-dialogs-8` (POTENTIAL_RISK, LOW) — `Num()` replaces `,` with `.`, so `"10,000"` becomes
  `10.0` and passes the `<= 0` guard: a session that starts with a balance of 10.
* `ui-dialogs-13` / `ui-dialogs-15` (CONFIRMED, LOW) — the orange-line caption is drawn at the
  START step's stale `m_start_y` while another step is on screen; `MenuClear` sweeps 32 menu items
  against an unbounded `presets.ini`, orphaning live preset buttons on the chart.
* `ui-dialogs-6` / `host-expert-14` (CONFIRMED, LOW) — the wizard's caption drag **cannot fire**:
  nothing enables `CHART_EVENT_MOUSE_MOVE` before `CSSRPanel::Create` exists, so during the
  picking phase every branch of `OnChartEvent` is unreachable, `SavePlace()` never runs,
  `SSR_SETUP_X/Y` never exist and the window re-centres on every run — sitting over the candles the
  user must now drag the start line onto.

[INFERENCE] The wizard covers 14 of the expert's 61 inputs. That is a documented limitation rather
than a defect, but it interacts with `host-expert-10` (CONFIRMED): the extra streams and the saved
settings block bypass the `Cfg*()` accessors, so a spread or timeframe chosen in the form applies
to the primary instrument only.

---

### L.6 Dialogs and cards

**Range / "jump" dialog** (`CSSRRangeDialog`, 248 x 214). The design idea — *quote what it will
cost before anything is written* — is one of the best in the product. Three confirmed defects
undo it:
* `ui-dialogs-3` (MEDIUM) — `Recompute()` unconditionally resets `m_problem` (`:127`) on the line
  after the two places that set it, so **a bad date produces no error at all** (START stays enabled
  against the previous instant) and LOAD MORE is mute. The comment at the site — *"a typo must not
  silently become 1970"* — describes the exact failure the code produces.
* `ui-dialogs-5` (MEDIUM) — the refusal message is drawn unbounded into one label; the "start too
  early" text is 77-78 characters and MetaTrader draws 63, so the user reads a sentence that looks
  complete and names a year instead of the instant. The refusal is the dialog's whole purpose.
* `ui-dialogs-7` (MEDIUM) — the dialog validates against **broker** history and its only caller can
  only jump inside the **already-loaded session window**, so a valid-looking START silently does
  nothing but print to the log. The title "NEW SESSION" and the button "START" reinforce the wrong
  expectation.

**Session picker** (`CSSRSessionDialog`, 420 x 260, 8 rows, `up`/`down` paging).
* `ui-dialogs-11` (LOW) — **DELETE is drawn enabled, looks live, deletes nothing**, and explains
  itself in an 86-character message that draws to 63. A control that claims a destructive action,
  performs none, and half-explains why.
* `ui-dialogs-12` (LOW) — `RequestSave()` and the whole overwrite-confirm mode have no caller, so
  the header's promise "IT ASKS BEFORE IT OVERWRITES" is not a behaviour the shipped tool has;
  sessions are overwritten silently by the host's `OnDeinit`.
* `ui-port-session-7`, `ui-port-session-8` (CONFIRMED) — the per-row summary is roughly twice what
  the row can draw, and resume warnings are newline-joined into a single 63-character label.
* `ui-port-session-12` (CONFIRMED, LOW) — every visible row re-parses its whole session file on
  every render.

**Review card** (`CSSRReviewCard`, 520 wide, 43 measures paged 12 at a time, ≤6 observations).
The paging discipline is correct and `OnKey` returns `true` for every key while up so Space cannot
start the replay behind it (`ui-dialogs.md` §4) — exactly the guard the *dialogs* lack
(`host-expert-7`).
* `ui-dialogs-4` (MEDIUM) — two observation sentences exceed 63 characters for **every possible
  value**. The ambiguous-bar line renders as "…reached both the stop and the t", which reads as a
  plain stop-out and loses the fact that the bar hit the target too — the single most important
  caveat this product reports about a fill.
* `ui-dialogs-16` (IMPROVEMENT) — the 12 measure rows are `OBJ_BUTTON`s whose latch nothing
  consumes, so a clicked statistic stays drawn pressed until the user pages. A false affordance on
  a card whose whole purpose is to be read.

**Reveal card** (`CSSRRevealCard`) is clean: one button, keys dropped entirely while up ("the one
button is the way out"), and it decides *when* the reveal happens but never *whether*. Note
`chart-3` (CONFIRMED, MEDIUM): the reveal it triggers is undone within ~200 ms by the host
re-applying blind mode.

---

### L.7 Keyboard, status ladder, and discoverability

[CONFIRMED FROM CODE] The key table (`SSR_Keys.mqh:125-218`) is a single generated source of
truth: 22 bindings, all 22 vk values distinct, 18 marked `listed`, and the key card's height is
*counted* from the table rather than chosen (`SSR_KeyCard.mqh`). Five enum commands have no key
(`PLAY`, `PAUSE`, `RESTART`, `REPLAY_FROM_HERE`, `COLLAPSE`) and every one of those has a button or
is host-owned. `Owns()`/`ExecuteInner` are kept in step so a key cannot be claimed and die
(invariant I12). **This is the strongest piece of UI engineering in the product** and should be
extended, not replaced.

Two things sit outside it: `Ctrl+K` (L.4.1) and the three hand-written key lists (L.2.3).

[CONFIRMED FROM CODE] The status ladder (`DrawStatus`, `SSR_Panel.mqh:1915-2035`) is a genuine
priority design, written down at the site with the reason the order was corrected: *"A message the
user cannot get rid of must sit below every message that is about what they just did."* Order:
armed reset → refused order → refused panel size → too-narrow chart → the five numbers. Levels 1-4
all write slot 50 / id `stbal` and hide the other four labels, which is the correct way to give one
message the whole strip.

Three defects on the ladder:
* `ui-panel-14` (CONFIRMED, LOW) — level 1, the **one destructive question in the product**, is a
  hardcoded English literal (`:2253`) in an otherwise fully translated panel.
* [CONFIRMED FROM CODE] Levels 2 and 3 (`m_port.TradeError()`, `m_pro_why`) are drawn unclipped
  from `x+8`. `TradeError()` strings originate in the trading engine and are not length-bounded.
* `ui-panel-6` (above) — level 5's fifth number is off the panel entirely.

[CONFIRMED FROM CODE] The fill **toast** is the only push notification the panel has, is announced
only for rows the panel can see (honest, and the code says why at `:779-785`), and is destroyed by
compact mode (`ui-panel-10`).

---

### L.8 Internationalisation: 190/190, and five surfaces outside it

[CONFIRMED FROM CODE] The catalogue is disciplined: 190 enum ids, 190 `SSRAddString` calls, no
duplicates or gaps; keys matched by **name**, never by index; UTF-8 read as binary with BOM
handling rather than `FILE_TXT|FILE_ANSI` (the bug that produced mojibake in v117); unknown keys
counted and skipped, never fatal; no English string over 63 characters. `fa.txt` is 190/190 with
zero unknown keys and zero printf-specifier mismatches.

Everything that escapes it:

| Surface | Where | Finding |
|---|---|---|
| Key card body — 36 cells, 18 rows | `SSR_Keys.mqh:131-218` literals drawn at `SSR_KeyCard.mqh:92` | `ui-plumbing-1` (CONFIRMED) |
| Reset confirmation (highest status-ladder line) | `SSR_Panel.mqh:2253` | `ui-panel-14` (CONFIRMED) |
| **Fill toast** — `"   spread %.1f pt"` and `"   NO STOP"` | `SSR_Panel.mqh:795, 799` | [CONFIRMED FROM CODE] — new. Translated equivalents `SSR_S_SPREAD_SHORT` and `SSR_S_NO_STOP` exist and are used on the Positions row 700 lines away |
| Review-card observations (up to 6 sentences) | `SSR_Review.mqh` `StringFormat` literals | `ui-dialogs-4` (CONFIRMED) |
| Every word the chart layer draws: `"STOP - drag me"`, `"TARGET - drag me"`, `"ENTRY - drag me"`, `BUY`/`SELL`/`SL`/`TP`, closed-trade captions, and the leak advice that reaches the Session tab | `SSR_TradeLines.mqh:134` etc. | `chart-12` (CONFIRMED) |

[INFERENCE] The pattern is consistent: **anything generated at runtime, and anything drawn outside
`/Ui/`, escaped the discipline** — and audit A19's literal check skips every path without `/Ui/`
in it, so nothing reports any of it. A Persian user gets a translated panel with English labels on
the only objects they are asked to drag, an English fill notification, and an English list of keys.

[INFERENCE] RTL is not implemented and, at present, cannot be. `SSR_Layout.mqh` exists to enable a
mirrored coordinate system and **no production file calls any of its functions** — `ui-plumbing-5`
(CONFIRMED, IMPROVEMENT). `SSRCentre` and `SSRInner` have zero call sites anywhere. Flipping
`SSRFrame.rtl` changes nothing on screen; mirroring the panel still means rewriting inline pixel
arithmetic in eight files by hand.

[POTENTIAL_RISK] `ui-plumbing-13` — `SSR_Strings.mqh` is UTF-8 **without a BOM** and carries six
raw `·` (U+00B7) characters inside drawn literals (`:472, 474, 544`). If MetaEditor decodes the
file as the system ANSI codepage, the palette footer and the setup summary draw `Â·`. The compile
succeeds either way.

---

### L.9 Register: clipped, overflowing, unreachable, orphaned

**Clipped or overflowing (drawn outside its frame, or cut by MetaTrader's 63 characters)**
`ui-panel-6` status fidelity at `x+330` in a 310 px panel · `ui-panel-7` note over P/L ·
`ui-panel-8` speed meaning at MAX · `ui-panel-13` PROP chip under the collapse button ·
`ui-dialogs-4` two review observations, always · `ui-dialogs-5` range-dialog refusal ·
`ui-dialogs-11` session-dialog DELETE message · `ui-port-session-7` session summary ·
`ui-port-session-8` joined resume warnings · `ui-panel-3`/`ui-panel-4` compact-mode strays ·
`ui-panel-10` toast over the speed control · `ui-dialogs-2` dropdown over START ·
`ui-dialogs-13` orange-line caption on the candles · `chart-11` (POTENTIAL_RISK) planning lines
painted across the panel. [CONFIRMED FROM CODE] The instrument built to catch this class —
`ResetExtent()`/`CheckFrame()` — measures only **sized** objects; labels are excluded by design
(`SSR_Widgets.mqh:125-128`), it is used by `SSR_Panel.mqh` alone, and nothing in the codebase ever
reads `FrameOverflowRight/Bottom`. Every entry above except the strays is a label.

**Unreachable**
The command palette in practice (`ui-plumbing-15`) · `SnapToCorner`/`m_corner`/`SetCorner`, whose
only caller is that palette entry · `CSSRSessionDialog::RequestSave` and the whole
`SSR_SD_CONFIRM_SAVE` mode (`ui-dialogs-12`) · the session dialog's DELETE (`ui-dialogs-11`) ·
the first-run card in the default configuration (`host-expert-4`) and on a short chart
(`ui-dialogs-14`) · the setup wizard's caption drag (`ui-dialogs-6`, `host-expert-14`) ·
`SSR_Layout.mqh` in its entirety (`ui-plumbing-5`) · `SSR_C_THUMB_EDGE` and `SSR_C_TICK`, declared
in all three palettes and drawn by nothing (`ui-plumbing-9`) · `data_mode` on the wire, written by
nobody and read by nobody (`ui-port-session-16`) · and — depending on L.4.2 — the entire mouse path.

**Orphaned**
Eight `SSR_S_*FOLLOW/BOOKMARK/JUMP` strings (L.4.5) · `charts_detached`, `pending_count`,
`stop_points`, `tp_points`, `checkpoints`, `has_saved_position`, `perf_calibrated`, `us_per_tick`,
`pump_p95_ms`, `prop_floor` — all filled by `CSSRGroupPort` and read by no draw site
(`ui-port-session.md` §2.2) · dead ids in `HideSheets()` (`g3_fr`, `g3_lb`, `g3_lg`, `pp_g`, and
`spreadrow`/`traderr` listed twice) · `SSR_S_KEYS_4`'s `[]` and the startup log's "press Move".

---

### L.10 What is sound, and must survive a redesign

[RECOMMENDATION] Do not replace the following. Each is a correct answer to a real MQL5 constraint
and was paid for once already:

1. **Latch polling as the one click mechanism** (`PollClicks`, `SSR_Panel.mqh:2445`) — clears the
   latch *before* acting, debounces 200 ms per name, polls the palette first and alone so one click
   is never read twice.
2. **The single generated key table** driving both `SSRKeyToCommand` and the key card (L.7).
3. **The status ladder's priority order** and its written-down rationale (L.7).
4. **"Removed, not merely undrawn"** (invariant I7) — the panel repaints from state and never
   clears the chart, so an id nobody draws is an id that lives forever. v125 got this right.
5. **Modes as chips, not colours** (`SSR_Panel.mqh:860-862`).
6. **Operated vs consulted** as the compact-mode rule (`:670-674`).
7. **The wish/fact split** for tall mode, with the refusal surfaced and both numbers named.
8. **`TabCount()` as a question, not a constant**, with `m_tab` re-clamped when the answer changes.
9. **`Clip()`, `SSR_REVIEW_ROW_MAX 60` and the 63-character discipline** — the idea is right; the
   problem is that it is applied at four sites out of hundreds.
10. **The 310-vs-420 layout switch and the three-palette switch** — one commented line must be able
    to undo a large change on a terminal the author cannot run.

### L.11 Priorities

[RECOMMENDATION] In order, by user-visible damage:

1. **Settle L.4.2 on a real terminal.** Whether `CHARTEVENT_MOUSE_MOVE` reaches the panel decides
   the drag, the tag box, and the speed slider. Nothing else in the UI should be redesigned first.
2. `ui-dialogs-1` (HIGH) — the wizard silently discards the session name; sessions cannot be
   resumed. Distinguish "empty box" from "absent box" at `SSR_Widgets.mqh:350`.
3. `ui-panel-3` + `ui-panel-4` (HIGH/LOW) — compact mode leaves clickable buttons on the candles.
   Order `HideSheetArea` after `HideBody`, and add `tab4` to the list.
4. `ui-panel-6` and `ui-panel-7` — re-derive the sheet and status arithmetic for a 245 px sheet
   and a 310 px frame. These are visible on **every frame of every session**.
5. Restore a detached-chart signal (L.4.3). It is the only removal that cost information.
6. Give the key card a discovery path that does not depend on the first-run card
   (`host-expert-4`), and put `Ctrl+K` in the key table so the card can show it
   (`ui-plumbing-15`).
7. Correct `keys.2` and `keys.4`, `SSRKeyHint()`, and the "press Move" log line; then collapse the
   three hand-written key lists into the generated one.
8. `host-expert-7` — withhold keys while a dialog is open, the way the review card already does.
9. i18n: route the toast, the reset confirmation, the key-card body, the review observations and
   the chart-line captions through `T()`, and widen audit A19 beyond `/Ui/`.

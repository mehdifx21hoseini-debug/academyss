# ARCHITECTURE MAP — subsystem `ui-dialogs` (SS Replay v125)

Scope: the seven files below. Everything here was read line by line; line numbers are
from the working tree at build v125.

| File | Lines | Class / free functions |
|---|---:|---|
| `MQL5/Include/SSReplay/Ui/SSR_SetupPanel.mqh` | 1275 | `CSSRSetupPanel`, `SSRSetupValues`, `SSRPropPreset`, `SSRDefaultPresets`, `SSRSetupTfName`, `SSRSetupBlindName`, `SSR_SETUP_TFS[]` |
| `MQL5/Include/SSReplay/Ui/SSR_RangeDialog.mqh` | 324 | `CSSRRangeDialog` |
| `MQL5/Include/SSReplay/Ui/SSR_SessionDialog.mqh` | 327 | `CSSRSessionDialog`, `ENUM_SSR_SD_MODE` |
| `MQL5/Include/SSReplay/Ui/SSR_ReviewCard.mqh` | 256 | `CSSRReviewCard` |
| `MQL5/Include/SSReplay/Ui/SSR_Review.mqh` | 224 | `SSRReviewRow`, `SSRAddRow`, `SSRReviewLine`, `SSRReviewRows`, `SSRReviewObservations` |
| `MQL5/Include/SSReplay/Ui/SSR_RevealCard.mqh` | 141 | `CSSRRevealCard` |
| `MQL5/Include/SSReplay/Ui/SSR_FirstRun.mqh` | 148 | `CSSRFirstRun` |

Every one of the seven draws through `CSSRWidgets` (`SSR_Widgets.mqh`) and **only**
through it, except `CSSRRangeDialog`, which hand-rolls one `OBJ_EDIT`
(`SSR_RangeDialog.mqh:185-203`).

---

## 0. Platform invariants this subsystem is built on

1. **`ObjectsDeleteAll(chart, prefix, 0)` is the teardown primitive.**
   `CSSRWidgets::RemoveAll()` (`SSR_Widgets.mqh:637`) deletes by *prefix*, not by an
   internal registry. That is why the range dialog's hand-made `SSRD_start` edit is
   still cleaned up, and why every one of these classes needs a unique prefix.
2. **Creation order is the only z-order.** Each `Render()` relies on drawing overlays
   last (`SetupPanel::Render` → `DrawMenu()` at :673; `ReviewCard` list rows).
   A repaint that does *not* recreate an object does **not** move it in z-order,
   because `ButtonC`/`Rect`/`Label` only rewrite properties when the fingerprint
   changed (`Same()`, `SSR_Widgets.mqh:80-91`).
3. **MetaTrader draws 63 characters of `OBJPROP_TEXT`** and errors on nothing.
   `SSR_Review.mqh` is the only file in the subsystem that defends against this
   (`SSR_REVIEW_ROW_MAX 60` + `SSR_REVIEW_PREFIX 2`, :57-58, enforced in
   `SSRReviewLine` :91-93). Static audit A14 measures only *literal-only* text
   arguments at the widget call site (`tools/ssr_audit.py:895-950`), so any text
   assembled at runtime is unmeasured.
4. **Button presses are read by latch polling, not events.** `Pressed()`
   (`SSR_Widgets.mqh:337`) reads and clears `OBJPROP_STATE`; `ButtonC` deliberately
   does *not* clear it on repaint. `CSSRSetupPanel`, `CSSRReviewCard`,
   `CSSRRevealCard` use this. `CSSRRangeDialog` and `CSSRSessionDialog` instead
   consume `CHARTEVENT_OBJECT_CLICK` through `OnEvent()`.
5. **Edit boxes are written on creation or on explicit request only**
   (`Edit(..., set_text)`, `SSR_Widgets.mqh:288-326`) so a repaint cannot delete
   half-typed text. Corollary the whole setup panel is shaped around: after a
   `RemoveAll()` the next paint **must** declare itself a first paint, or boxes come
   back empty (`CSSRSetupPanel::Repaint`, :656).
6. **`EditText()` returns `""` both for an empty box and for an absent box**
   (`SSR_Widgets.mqh:350-356`). The caller must distinguish them. This is the root of
   finding `ui-dialogs-1`.
7. **No clipping, no scrollbar.** Long lists are *windowed* (`CSSRWidgets::List`
   +`ListClear`) and the caller pages them (`CSSRReviewCard::Page`,
   `CSSRSessionDialog` `m_top`).
8. **Only one chart is involved.** The host sets `g_panel_chart = ChartID()`
   (`SSReplayStandalone.mq5:1463`), so every class here draws on, and receives events
   from, the chart the EA is attached to. The setup panel is created with
   `ChartID()` too (:2069).

---

## 1. `CSSRSetupPanel` — the 4-step setup wizard (`SSR_SetupPanel.mqh`)

### Responsibility
Collect a session configuration on the chart, beside the orange start line, instead of
in MetaTrader's inputs dialog. Reads its edit boxes **once**, at the moment the answer
is needed (`ReadAll`), never on edit events.

### Owns / state
| Member | Meaning |
|---|---|
| `m_chart` | always `ChartID()` in the shipped host |
| `m_w` | widgets, prefix `SSRS_` |
| `m_v` (`SSRSetupValues`) | the 14 settings it can produce |
| `m_open`, `m_x`, `m_y`, `m_placed` | window state; `m_placed` = "the user positioned it" |
| `m_step` | 0 QUICK, 1 SETTINGS, 2 MODE, 3 START |
| `m_first_paint` | gates `Edit(set_text)` |
| `m_tf_i` | index into `SSR_SETUP_TFS` (advisory only; `m_v.chart_tf` is the truth) |
| `m_presets[]`, `m_preset_i` | slot 0 is always "My last" |
| `m_force_prop` | forces the three prop boxes to be rewritten for exactly one paint |
| `m_menu`, `m_menu_y` | which pseudo-combo is open and where it drops from |
| `m_drag`, `m_drag_dx/dy` | caption drag (see finding `ui-dialogs-6`) |
| `m_start_text`, `m_start_y` | the orange-line caption, and where `RenderStart` put it |

### `SSRSetupValues` — 14 of the expert's 61 inputs
`balance, risk_percent, spread_points, speed, chart_tf, extra_tfs, blind,
session_name, prop_on, prop_target, prop_daily, prop_total, random_start, seed`.
Mapped to `Inp*` by the host's `Cfg*()` accessors (`SSReplayStandalone.mq5:224-241`),
which prefer the panel only when `g_setup_ready`. The other 47 inputs
(`InpTicksPerBar`, `InpSlippage`, `InpCommission`, `InpSwap*`, `InpMarginLot`,
`InpStopout`, `InpAlsoSymbols`, `InpPause*`, `InpNews*`, `InpProp{Trail,MinDays,MaxDays}`,
`InpStrat*`, `InpPublish/AllowControl/AllowTrade`, `InpWarmupBars`, `InpReplayBars`,
`InpHistoryBars`, `InpSlot`, `InpPumpMs`, `InpSpreadMode`, `InpFidelity`-equivalents,
`InpLanguage`, …) have **no** control here — documented limitation, not a defect.

### Public surface
`Create(chart_id, SSRSetupValues &defaults)`, `Destroy()`, `IsOpen()`,
`Values(SSRSetupValues &out)`, `SetStartText(string)`, `Poll() → "" | "go" | "here"`,
`OnChartEvent(id,lparam,dparam,sparam) → bool`, `Summary()`,
`static Save(SSRSetupValues&)`, `static Restore(SSRSetupValues&)`.
Also public (effectively internal, but reachable): `Render`, `Repaint`, `Recap`, `Row`
(private), `MenuOptions`, `MenuClear`, `DrawMenu`, `ApplyMode`, `ModeNow`, `Choose`,
`ReadAll`, `SavePlace`, `LoadPlace`.

### Callers
`SSReplayStandalone.mq5` only:
`:2053-2069` build defaults from inputs, `Restore()` over them, `Create(ChartID(), sv)`;
`:2490` `SetStartText` every 200 ms timer beat while picking;
`:2495` `Poll()`; `:2518-2522` `Values` → `g_setup` → `Save` → `Summary` → `Destroy`;
`:2111` `Destroy` in `OnDeinit`; `:3117` `OnChartEvent`;
`:1948` `Restore` on the replay pass (handover);
`:2067` `Restore` for the panel's own defaults.

### Layout arithmetic (invariants a redesign must keep)
* `SSR_SETUP_W 304`, `SSR_SETUP_ROW 24`, `SSR_SETUP_FIELD_W 84`.
* `SSR_SETUP_H_MAX = 30 + 17*24 + 44 = 482` — the **settings** step, the tallest one.
  Centring uses this constant so the window does not jump between steps (:531-541).
* Step 1 really is 17 rows (4 group headings + 13 fields), verified by walking `r`.
* A row: label at `m_x+12, ry+5`; field at `m_x+304-84-12 = m_x+208`, `84 x 20`.
* Menu: `fx = m_x+208`, item height 20, opens at `m_menu_y+21`, flips upward when it
  would pass `CHART_HEIGHT_IN_PIXELS` (:633-635).
* `Create` prints a warning when the chart is shorter than `28+30+17*24+44+16 = 526`.

### Disk
* `SSReplay\setup.ini` — `SSR_SETUP_FILE`, written by `Save()` (:1211), read by
  `Restore()` (:1238). Section `[setup]`, 14 keys. Two jobs: remember the last
  session **and** carry the values across the one-window handover (a chart object
  cannot, because of the 63-char cut).
* `SSReplay\presets.ini` — `SSR_PRESET_FILE`, written by `SavePresets()` **only when
  the file did not exist** (:361), read by `LoadPresets()` (:317). Section
  `[presets]`, N rows keyed `p`, packed `name|on|target|daily|drawdown`. Rows with an
  empty name, or `on!=0 && target<=0`, are skipped (:342). An existing-but-unreadable
  file is left alone and reported to the log (:364).
* Reads `FileIsExist("SSReplay\sessions\<name>.ssr")` directly (:713) — the only place
  in the subsystem that builds a session path itself instead of asking
  `CSSRSessionManager::Path()`.
* Chart globals `SSR_SETUP_X` / `SSR_SETUP_Y` via `SavePlace`/`LoadPlace` (:1006-1023).

### Chart objects
Prefix `SSRS_`. `Create` first calls `SSRPurgeChart(chart, SSR_PICK_LINE)`, which
deletes **every** object whose name starts with `SSR` except the pick line — i.e. it
sweeps the panel, key card, first-run card and calendar lines too, by design.

### Step behaviour
* **0 QUICK** (`RenderQuick` :710) — `qlast` (only when `setup.ini` exists),
  `qcont` (only when the named session file exists), `qrand`, `qcust`.
  `qlast`/`qcont` jump straight to step 3; `qrand` applies mode 3 and clears the seed.
* **1 SETTINGS** (`RenderSettings` :765) — 13 fields, 4 of them pseudo-combos
  (`tf`, `bl`, `pre`, `pon`), 9 edit boxes. Cannot start anything.
* **2 MODE** (`RenderMode` :826) — 4 shortcut buttons writing `blind`/`prop_on`/
  `random_start`; `ModeNow()` derives the highlighted one, so there is no fifth
  source of truth. Modes are not exclusive by decree.
* **3 START** (`RenderStart` :864) — read-back `Recap` rows, the seed `OBJ_EDIT`
  (only in random mode), "bring the line here", the drag caption, `back`, `go`.

### Poll order (matters — first match wins)
`qlast, qcont, qrand, qcust` → `md0..md3` → `next` → `back` → `go` → `here` →
open-menu items `m0..mN` → field buttons `btf, bbl, bpre, bpon`.

---

## 2. `CSSRRangeDialog` — "where do I jump to", with a quote (`SSR_RangeDialog.mqh`)

### Responsibility
Ask for a start instant and a "deepest context" timeframe, **quote what it will cost**
(bars, seconds, megabytes) before anything is written, and refuse a range the broker
cannot serve.

### Owns
`m_chart`, `m_w` (prefix from ctor, default `SSRD_`), `m_prefix`, `m_open`,
`m_x/m_y`, `m_req` (`SSRSessionRange`), `m_quote` (`SSRSeedQuote`), `m_problem`,
`m_cat` (`CSSRHistoryCatalog*`, **not owned**), `m_confirmed`.

### Public surface
`Create(chart, CSSRHistoryCatalog*, prefix="SSRD_")`, `Destroy()`, `IsOpen()`,
`IsConfirmed()`, `RequestInto(SSRSessionRange&)`, `QuoteInto(SSRSeedQuote&)`,
`Problem()`, `Open(SSRSessionRange &seed)`, `Close()`, `Recompute()`, `CanStart()`,
`Render()`, `OnEvent(...) → bool`.

### Callers
`SSReplayStandalone.mq5:1465` `Create(g_panel_chart, &g_catalog)`;
`:3102` `Open(r)` from `RunHostCommand(SSR_CMD_JUMP)` (key `J`, panel button, palette);
`:3177-3192` `OnEvent`, then on `IsConfirmed()` the host calls `g_group.JumpTo()`
**only if** `start_msc` lies inside `[g_group.StartMsc(), g_group.EndMsc())`;
`:2117`,`:2150` `Destroy` in `OnDeinit`.

### Controls
`close` (x), `tf0..tf3` (M15/H1/H4/D1 — `SSR_DLG_TF_COUNT 4`), `more` (LOAD MORE),
`start` (enabled from `CanStart()`), plus one hand-made `OBJ_EDIT` named
`<prefix>start` that holds the date as `TIME_DATE|TIME_MINUTES` text and is parsed on
`CHARTEVENT_OBJECT_ENDEDIT`. There is no control for `end_msc`, `visible_bars`,
`fidelity` or `slot`; those come from the seed the caller passes.

### Geometry
`SSR_DLG_W 248 x SSR_DLG_H 214`, recentred on every `Render()` from
`CHART_WIDTH/HEIGHT_IN_PIXELS`. Rows: avail(15) → start(23) → tf(24) → quote well(44+5)
→ problem(17) → button row(22). Bottom of the button row is `y+175`, i.e. 39 px spare.

### Invariants relied on
* `m_cat` may be `NULL` → `Recompute` reports `"no catalog"` and returns.
* `CanStart()` = request complete **and** quote feasible **and** (`m_problem` empty or
  starting with `"warning"`). "warning" is the one prefix that is not a refusal — it
  is also how `Render` picks the message colour (:233).
* Every mutation is followed by `Recompute(); Render();` — and `Recompute()` resets
  `m_problem` unconditionally (:127), which is why two ad-hoc messages never appear
  (finding `ui-dialogs-3`).
* Writes nothing to disk. Only `m_cat.LoadMore()` has an external side effect
  (broker history download).

---

## 3. `CSSRSessionDialog` — pick a saved session (`SSR_SessionDialog.mqh`)

### Responsibility
Show what session files exist, with the symbol/instant each holds, and load one.
Second, unreachable, responsibility: confirm before overwriting on save.

### Owns
`m_chart`, `m_w` (prefix `SSRSD_`), `m_port` (`CSSRReplayPort*`, **not owned**),
`m_mode` (`SSR_SD_CLOSED | SSR_SD_PICK | SSR_SD_CONFIRM_SAVE`), `m_count`, `m_top`,
`m_selected`, `m_pending`, `m_message`, `m_x/m_y`.

### Public surface
`Create(chart, CSSRReplayPort*, prefix="SSRSD_")`, `Destroy()`, `IsOpen()`,
`Message()`, `Selected()`, `Open()`, `Close()`, `Render()`, `OnEvent(...) → bool`,
`RequestSave(string name)`.

### Callers
`SSReplayStandalone.mq5:1466` `Create(g_panel_chart, &g_gport)`;
`:3091` `Open()` from `RunHostCommand(SSR_CMD_SESSIONS)` (key `S`, panel, palette);
`:3167-3172` `OnEvent`; `:2116` `Destroy`.
**`RequestSave()` has no caller anywhere in the tree** (verified by grep over
`MQL5/**`), therefore `SSR_SD_CONFIRM_SAVE`, `m_pending`, and the port's
`SaveSession()` are all unreachable in the shipped product. Named sessions are saved
by the host directly, in `OnDeinit`, via `g_session_mgr.Save(CfgSession(), set)`
(`SSReplayStandalone.mq5:2135-2143`).

### Port methods used
`SessionCount()`, `SessionName(i)`, `SessionSummary(i)`, `LoadSession(name)`,
`SaveSession(name)` (dead), `SessionError()`. Implemented by `CSSRGroupPort`
(`SSR_GroupPort.mqh:923-975`). `SessionCount()` re-lists the folder each call and
refills `m_names`, so `SessionName(i)` is only valid after a `SessionCount()`.

### Geometry / paging
`SSR_SD_W 420 x SSR_SD_H 260`, recentred each `Render()`. `SSR_SD_ROWS 8` visible
rows of `SSR_ROW_H-2 = 17`; `m_top` is the scroll offset, `up`/`down` step it by one.
Rows beyond `m_count` are hidden with `Hide(id,true)` (`OBJPROP_TIMEFRAMES =
OBJ_NO_PERIODS`) rather than deleted, and `empty1..3` explain an empty list.

### Invariants
* `Open()` refreshes `m_count`, resets `m_top`, selects row 0, and **overwrites
  `m_message`** with `""` or `"no saved sessions yet"` (:94).
* `load` reports a *successful* load's warnings (`"... BUT: <warn>"`) — the
  fingerprint mismatch path is deliberately not swallowed.
* `del` is a no-op that prints a sentence (:288-297).
* Writes nothing to disk itself; `SaveSession`/`LoadSession` go through the port.

---

## 4. `CSSRReviewCard` — the session, after the session (`SSR_ReviewCard.mqh`)

### Responsibility
A modal card that *consults*: 43 measures, paged 12 at a time, plus up to 6
observation sentences, plus a 5-figure headline. It computes and interprets nothing.

### Owns
`m_w` (prefix `SSRR2_`), `m_chart`, `m_up`, `m_rows[]`/`m_n`, `m_first`,
`m_obs[]`/`m_obs_n`, `m_st` (a **copy** of `SSRStatistics`), `m_x/m_y`.

### Public surface
`Show(chart, const SSRStatistics&) → bool`, `Render()`, `Page(delta)`,
`Poll() → "" | "stmt" | "close"`, `OnKey(long) → bool`, `Hide()`, `IsUp()`,
`Rows()`, `Observations()`, `First()`, `RowAt(i)`, `ObservationAt(i)`.
`RowAt`/`ObservationAt` exist as a read-only seam for `SSR_QA_Smoke` / `T15`.

### Callers
`SSReplayStandalone.mq5:977` `Show(g_panel_chart, st)` from the single `OpenReview()`;
reached from the reveal press (:3025), a finished prop challenge (:3031) and
`SSR_CMD_REVIEW` (key `A`, palette). `:3038-3050` `Poll()`, where `"stmt"` triggers
`g_journal.ExportHtml("SSReplay-session", 2)`. `:3219-3222` `OnKey`. `IsUp()` is one
of the four terms of the host's `modal` flag (:3052), which suspends both panel
repaint and panel click polling.

### Geometry
`SSR_RV_W 520`; `h = 26+46+12*17+10+obs_h+34` = 320 + `obs_h`, where
`obs_h = 18+obs_n*14` (0 when there are none). Recentred every `Render()`; falls back
to `x=8,y=8` on a chart smaller than the card. `SSR_RV_SHOWN 12`, `SSR_RV_ROW_H 17`.
List id `m` → objects `SSRR2_m_bg`, `SSRR2_m0..m11`.

### Invariants
* `m_n` is **always 43** (`SSRReviewRows` is unconditional), so `Page()`'s
  `m_first > m_n - SSR_RV_SHOWN` clamp is always meaningful and `m_first ∈ [0,31]`.
* `m_obs_n ≤ 6` (six `if` blocks in `SSRReviewObservations`), which is why the card's
  `for(i=0;i<8;i++)` observation loop is sufficient.
* The group name rides on a group's first row as a `"· "` prefix, `"  "` otherwise —
  this is the 2 characters `SSR_REVIEW_PREFIX` accounts for.
* `OnKey` returns `true` for **every** key while up (Esc closes, Up/Down page,
  everything else is swallowed) so Space cannot start the replay behind the card.
* Writes nothing to disk. The statement export is the host's, not the card's.

---

## 5. `SSR_Review.mqh` — rows and sentences (no class)

* `SSRReviewRow { group, label, value }`.
* `SSRAddRow(out, i, group, label, value)` grows `out` in 16-row steps.
* `SSRReviewLine(r)` pads `label` to 34 characters then appends `value`, and truncates
  to `SSR_REVIEW_ROW_MAX 60` with a trailing `~`. 60+2 prefix = 62 ≤ 63.
* `SSRReviewRows(st, out)` → **43** rows in 9 groups: Result 10, Rates 8, R 4,
  Drawdown 4, Streaks 3, Excursion 2, Time 2, Discipline 4, Execution 6.
  Nothing is filtered for being zero.
* `SSRReviewObservations(st, out)` → 0..6 sentences. Returns 0 outright when
  `st.trades < 3` ("a session of one or two trades cannot support a statement").
  Each remaining line needs samples *and* something to report. The sentences are
  English literals built with `StringFormat` — they do **not** go through `T(SSR_S_*)`
  and are not length-guarded (finding `ui-dialogs-4`).
* Reads `SSRStatistics` only; writes nothing.

---

## 6. `CSSRRevealCard` — the end of a blind session (`SSR_RevealCard.mqh`)

* Prefix `SSRV_`. State: `m_chart`, `m_up`, `m_headline`.
* Surface: `Show(chart, headline) → bool`, `Render()`, `Poll() → bool` (true exactly
  once, on the press, and it hides itself), `Hide()`, `IsUp()`.
* Callers: `SSReplayStandalone.mq5:3006-3016` shows it when
  `!g_revealed && g_blind.IsApplied() && !IsUp() && status == COMPLETED`, with a
  headline the *host* computed; `:3018-3027` on `Poll()` the host latches
  `g_revealed`, calls `g_blind.RestoreAll()`, re-renders the panel, latches
  `g_reviewed` and opens the review card. `IsUp()` feeds the `modal` flag; while up,
  `CHARTEVENT_KEYDOWN` is dropped entirely (`:3224`) — "the one button is the way out".
* Geometry `SSR_REVEAL_W 360 x SSR_REVEAL_H 132`, `x` centred, `y = ch/3` (or 12).
  One `Chip("chip", …)` at `x+W-58`, a single `reveal` button spanning the card.
* Decides **when** the reveal happens, never whether: `OnDeinit` restores charts
  regardless. Writes nothing to disk.

---

## 7. `CSSRFirstRun` — the once-ever card (`SSR_FirstRun.mqh`)

* Prefix `SSRF_`. State: `m_chart`, `m_up`, `m_shown_ms` (`uint`, from `GetTickCount()`).
* Surface: `static AlreadySeen()`, `static MarkSeen()`, `Show(chart) → bool`,
  `Tick()`, `Clear()`, `IsUp()`.
* Marker file `SSReplay\seen.txt` (`SSR_SEEN_FILE`) — once per *installation*, not per
  session, because the handover restarts the program. Written with
  `FILE_WRITE|FILE_TXT|FILE_ANSI|FILE_SHARE_READ`.
* Lifetime: no close button by design; `Tick()` removes it after
  `SSR_FIRST_MS 25000` ms. `uint` wrap-around arithmetic is correct.
* Fixed position `x=14, y=SSR_PANEL_H+40 = 376, w=396, h=104` → needs a chart at
  least ~480 px tall. Four `T(SSR_S_FIRSTRUN_*)` lines, all inside the 63-char cut
  (A14 covers them because they are literal-only arguments).
* Callers: `SSReplayStandalone.mq5:1736-1745` — shown only when
  `InpFirstCard && !one_chart_ok && g_panel_chart != 0` and `!AlreadySeen()`; the host
  calls `MarkSeen()` **iff `Show()` returned true**. `:2732` `Tick()` from the timer;
  `:2119` `Clear()` in `OnDeinit`.

---

## 8. Ownership / data-flow summary

```
OnInit (picking phase, origin chart)
  └─ CSSRSetupPanel.Create(ChartID(), inputs ← setup.ini)
       ├─ presets.ini            (read, and written on first run only)
       ├─ Poll() → "here"        host moves the orange line to mid-view
       └─ Poll() → "go"          Values() → g_setup → Save(setup.ini) → Destroy()
                                            └→ BuildSession()

BuildSession (same chart)
  ├─ g_panel_chart = ChartID()
  ├─ CSSRRangeDialog.Create(chart, &g_catalog)        prefix SSRD_
  ├─ CSSRSessionDialog.Create(chart, &g_gport)        prefix SSRSD_
  ├─ CSSRPanel.Create(chart, &g_gport)                prefix SSRP_
  └─ CSSRFirstRun.Show(chart) → seen.txt              prefix SSRF_

OnTimer
  ├─ g_first.Tick()
  ├─ reveal: CSSRRevealCard.Show/Poll                 prefix SSRV_
  ├─ review: CSSRReviewCard.Show/Poll                 prefix SSRR2_
  └─ modal = session_dlg.IsOpen() || dialog.IsOpen() || reveal.IsUp() || review.IsUp()
        └─ gates BOTH panel click polling and panel repaint

OnChartEvent → setup_ui.OnChartEvent (mouse) → RouteEvent
  └─ session_dlg.OnEvent → dialog.OnEvent → review.OnKey/reveal → panel.OnEvent → keys
```

Files written by this subsystem: `SSReplay\setup.ini`, `SSReplay\presets.ini`,
`SSReplay\seen.txt`. Chart globals: `SSR_SETUP_X`, `SSR_SETUP_Y`.
Nothing here touches the trading engine, the replay controller or the custom symbol
except through `CSSRReplayPort` (session load/save) and `CSSRHistoryCatalog`
(quote / load-more).

---

## 9. Instrumentation coverage

`m_w.ResetExtent()` / `MaxRight()` / `MaxBottom()` and `CheckFrame()` — the v124
layout-overflow detector — are used **only** by `SSR_Panel.mqh:634,765,3019`.
None of the seven files in this subsystem measures its own frame, and
`CSSRWidgets::Label` does not feed `Extent()` at all (only sized objects do), so a
label drawn outside a card's frame is invisible to every instrument in the product.

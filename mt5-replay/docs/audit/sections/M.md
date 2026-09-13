## M. NEW PREMIUM INFORMATION ARCHITECTURE

*Basis: the constraints-first proposal (`M-proposal-constraints-first.md`), which won on plumbing
and on the one trainee failure that precedes all the others — in the default configuration nobody
is ever told a single key. Ten grafts from the two runners-up are folded in below, four of which
correct factual errors in the winner. Build v125, `SSR_LAYOUT_RAIL` and `SSR_THEME_RAIL` active.*

*This proposal is written for the pessimistic branch of L.4.2 — **no mouse coordinates arrive**.
That matches this audit's ground truth (the panel is drawn on the replay chart, which the EA is
not attached to; it receives `CHARTEVENT_OBJECT_CLICK` and nothing else). It is deliberately the
harder assumption: an architecture that is correct without the mouse stays correct with it, and
the reverse is not true. Where the code itself disagrees — `ui-panel.md` §11/I1 records that
`g_panel_chart == ChartID()` (`SSReplayStandalone.mq5:1463`) and that key and mouse events
therefore do reach the panel as wired — the disagreement is named at M.10 rather than resolved,
because it cannot be resolved without a terminal.*

---

### M.0 The position, in one page

The brief proposes HOME / REPLAY / TRADE / POSITIONS / PERFORMANCE / CHALLENGE / JOURNAL /
SETTINGS. **Eight cannot be drawn.** The arithmetic, not taste, is what kills it:

[CONFIRMED FROM CODE] `DrawRail` (`SSR_Panel.mqh:1209-1225`) draws cells of `h = 22` with `gp = 3`:

```
   void DrawRail(const int x, const int y)
     {
      int n = TabCount(), h = 22, gp = 3, cy = y;
```

so `n` destinations need `25n - 3` px, against `SSR_SHEET_H 186`:

```
n = 5   122 px    ships today
n = 6   147 px    fits, 39 px spare
n = 7   172 px    fits, 14 px spare      <- the ceiling in Standard
n = 8   197 px    DOES NOT FIT           <- the brief's model
```

The horizontal fallback is worse: `DrawTabs` (`:1145`) computes `tw = (W - 2*SSR_PAD - (n-1)*2)/n`,
which at `W = 310`, `n = 8` gives **35 px a tab** — about seven characters of Tahoma 8 pt, for names
that must also survive Persian (`rtab.prop = ارزیابی`, 7 glyphs). MetaTrader centres button text,
does not clip it, and has no bidi.

**The answer is six destinations, one of them conditional, and one cell of headroom left unspent.**
But the destination list is not the valuable part of this document. Five structural rules are, and
they make every destination in every one of the three proposals cheaper:

1. **Navigation is the only thing allowed to delete.** [CONFIRMED FROM CODE] `DrawSheet`'s first
   statement is unconditional — `void DrawSheet(...) { HideSheets(); switch(m_tab) ...`
   (`SSR_Panel.mqh:1267-1269`) — and `HideBody(false)` runs unconditionally at `:729`. Between them
   (`ui-panel-1` and `ui-panel-2`, both CONFIRMED HIGH) they restore the full 561-write repaint the
   512-slot cache was built to eliminate.
2. **An overlay costs a rebuild per frame; a destination costs a rebuild per click.**
3. **Every destination owns its teardown list**, declared beside its draw function
   (`ui-panel-4`, CONFIRMED: three hand-kept lists that disagree).
4. **Every row declares a character budget and goes through `Clip()`.**
5. **Nothing that adds a clickable control ships before keys are withheld while a modal is open**
   (`host-expert-7`, CONFIRMED MEDIUM).

Fix those and the new information architecture arrives almost as a side effect, because
destinations stop being expensive.

---

### M.1 The constraint set, priced

#### M.1.1 What input exists

[CONFIRMED FROM CODE] The only input the drawn surface may rely on is a **latched button**.
`CSSRWidgets::Pressed` (`SSR_Widgets.mqh:337-347`) reads `OBJPROP_STATE` and clears it;
`CSSRPanel::PollClicks` (`SSR_Panel.mqh:2445`) walks `ObjectsTotal(m_chart,-1,OBJ_BUTTON)`
backwards, clears the latch **before** acting, and debounces 200 ms per name.
`CHARTEVENT_OBJECT_CLICK` is deliberately not handled (`:2878`).

| Not available | Consequence for this IA |
|---|---|
| hover | no tooltips, no reveal-on-hover, no disclosure triangles. Every affordance is permanently drawn or absent |
| focus / tab order | no keyboard navigation *inside* a destination. [CONFIRMED FROM CODE] `m_tag_focus` is assigned only inside the `CHARTEVENT_MOUSE_MOVE` handler (`SSR_Panel.mqh:2903-2907`) and nowhere else, so it is dead in the pessimistic branch |
| scroll | no long lists. Explicit paging, or nothing |
| clipping | overflow is not merely ugly — it lands on the candles and stays there |
| drag | no repositioning, no resize handles, no slider thumb to grab |
| a combo box | the wizard's pseudo-combo is a stack of buttons that outlives its step (`ui-dialogs-2`, CONFIRMED). Do not build a second one |
| text measurement | [CONFIRMED FROM CODE] `Extent()` covers sized objects only and excludes labels **by design** (`SSR_Widgets.mqh:120-128`, invariant I10): *"A label's width depends on the glyphs the font chose and MQL5 will not say."* Every text overflow in L.9 is invisible to the instrument |

One exception survives: `OBJ_EDIT`. MetaTrader owns the caret, and `Edit()` writes `OBJPROP_TEXT`
only on creation or an explicit reset (`SSR_Widgets.mqh:316-324`), so a repaint cannot erase what is
being typed. That is the only typed input this architecture may use, and it must be **read at a
moment**, never polled.

#### M.1.2 What a frame costs, measured

[CONFIRMED FROM CODE] Write counts are literal `m_writes +=` statements; warm cost is the `Same()`
early return, which ends in `ObjectFind`.

| primitive | site | cold | warm |
|---|---|---|---|
| `Rect` | `SSR_Widgets.mqh:195` | 9 writes | 0 writes, 1 `ObjectFind` |
| `Label` | `:226` | 6 | 0, 1 find |
| `ButtonC` | `:358` | 9 | 0, 1 find |
| `Edit` | `:288` | 9 (+1 with text) | **never cached** |
| `Group` | `:500` | 24 | 3 finds |
| `Chip` | `:525` | 15 | 2 finds |
| `Meter` | `:540` | 27 | 3 finds |
| `Slider(20)` | `:460` | **198** | 22 finds |
| `Hide(id,b)` | `:616` | 1 find + 1 write + **`Forget`** | invalidates the cache in *both* directions |
| `Remove(id)` | `:627` | 1 find + `ObjectDelete` + `Forget` | — |
| panel `Text()` hit | `SSR_Panel.mqh:191-198` | — | 1 find + **1 `ObjectSetInteger(COLOR)`** |

The anchor is the project's own measurement at `SSR_Widgets.mqh:31-38`: *"561 object properties
written per STILL frame, and a mean repaint of 39.05 ms — against an engine that pumps every 40."*
≈ **0.07 ms per property write**. That number is the currency of this document.

[INFERENCE, from two CONFIRMED findings plus the arithmetic above] **a still frame today:**

```
DrawSheet -> HideSheets()      154 Remove()  = 154 find + ~25 delete + 154 Forget
SheetTrade rebuild, all cold   ~190 writes
HideBody(false) at :729         57 Hide()    = 57 find + 57 write + 57 Forget
   ...~44 of them SIZED and immediately redrawn cold   ~396 writes
-------------------------------------------------------------------------------
                               ~586 property writes + ~211 ObjectFind on a frame
                               where NOTHING CHANGED
```

At 10 fps (`SSReplayStandalone.mq5:3063`) that is ≈ 0.41 s of repaint per second of wall clock, on
the thread that pumps ticks. **a still frame under this proposal:** no `Remove`, no `Hide`, every
object takes the `Same()` early return — ~95 `ObjectFind` and ~30 colour writes, ≈ 2 ms; navigation
costs one teardown (~25 `Remove`) plus one cold draw (~190 writes), **once**.

#### M.1.3 What geometry allows

[CONFIRMED FROM CODE] `SSR_Theme.mqh:484-499`: `SSR_PANEL_W 310`, `SSR_RAIL_W 44`, `SSR_ACT_H 21`,
`SSR_SHEET_H 186`, `SSR_SHEET_GROW 140`, `SSR_SHEET_H_TALL 326`, `SSR_PANEL_H 336`,
`SSR_PANEL_TALL_H 476`, `SSR_PANEL_COMPACT_H 128`, `SSR_STATUS_H 18`, `SSR_PAD 8`, `SSR_GAP 5`.

| region | budget | capacity |
|---|---|---|
| rail, Standard | 186 px | **7 cells** (`25n-3 ≤ 186`) |
| rail, Expanded | 326 px | 13 cells |
| sheet width | `310 - 16 - 44 - 5` = **245 px** | a row from `x+8` has **237 px** |
| sheet height, Standard | 186 px | 9 rows of `SSR_ROW_H 19` + 15, or 6 rows + two 45 px Groups |
| sheet height, Expanded | 326 px | 17 rows of 19 |
| status strip | 294 px | **4 readouts, not five** (`ui-panel-6`) |
| action strip | `bw = (310-16-6)/3` = 96 px | **3 buttons, and there is no fourth** |
| speed groove | 130 px | M.1.6 |

[CONFIRMED FROM CODE] `SSR_PANEL_H` is the literal sum `(23+32+27+21+21+186+18+8)` in both layouts,
and the `21` for the action row is a bare number rather than `SSR_ACT_H` (`SSR_Theme.mqh:499`).
Anything below that changes a row height must make that `21` symbolic first. `ui-plumbing-11`
(CONFIRMED, IMPROVEMENT) records that four of the six numbers in the metrics comment a designer is
meant to size a new row against are already stale.

#### M.1.4 What text allows

Ground truth: MetaTrader draws exactly 63 characters of `OBJPROP_TEXT`, stores the rest, and errors
on nothing. [CONFIRMED FROM CODE] `Clip()` (`SSR_Panel.mqh:242`) caps at 62 and marks the cut with
`~`, and is applied at **exactly four** sites in a 3049-line file — `:960` (`prog`), `:1760`
(`pp_rules`), `:1840` (`pp_head`), `:1892` (`ses3`).

But 63 is not the binding limit inside the sheet. [INFERENCE — MQL5 exposes no text metrics, so
px/char figures are estimates, not measurements] at Tahoma 8 pt (`SSR_FS_BODY`) ≈ 5.1 px/char and
7 pt (`SSR_FS_SMALL`) ≈ 4.5:

```
sheet row from x+8, 237 px:   ~46 chars at FS_BODY    ~52 at FS_SMALL
status slot, ~70 px:          ~13 chars at FS_SMALL
rail cell, 44 px:             ~8  chars at FS_BODY
action button, 96 px:         ~18 chars at FS_BODY
```

**The sheet's real budget is 46 characters, not 63.** Every confirmed overflow in L.9 is a row
written against 63 (or against the old 295 px sheet) and drawn into 237.

#### M.1.5 Z-order: why overlays are structurally expensive

Ground truth: creation order is the only z-order; `ObjectCreate` refuses an existing name; the panel
repaints from state and never clears the chart (invariant I7).

[CONFIRMED FROM CODE] The consequence is written in the file (`SSR_Panel.mqh:767-777`): anything
opened *over* the panel goes back under it on the next repaint, so the panel re-`Show()`s the key
card every frame. `CSSRKeyCard::Show` begins with `m_w.RemoveAll()` (`SSR_KeyCard.mqh:72`) and then
recreates ~41 objects — `ui-panel-12` (CONFIRMED, MEDIUM) prices it at ~41 deletes + 41 creates +
~450 writes **per frame while the card is up**.

> **An overlay costs a full rebuild every 100 ms for as long as it is open.
> A destination costs a rebuild once, when it is selected.**

Anything read for more than a second belongs in the sheet.

#### M.1.6 The speed groove, priced honestly — *with the graft the winner got wrong*

[CONFIRMED FROM CODE] `SSR_SPEED_LADDER_SIZE 20` is an **engine** constant
(`Common/SSR_Types.mqh:302`, used by `SSRSpeedLadder` at `:318`, `:332`, `:341`), not a UI one. The
panel draws one cell per ladder stop into `m_track_w = 130`, i.e. **6.5 px a target**, and says so at
`SSR_Panel.mqh:1048-1053`: *"Below about five the cells stop being clickable and the slider becomes
a picture of a control."*

[RECOMMENDATION] Decouple the drawn cell count from the ladder size: 10 cells of 13 px, each
selecting ladder index `2i`, with `-` / `+` keeping every one of the 20 speeds reachable. The engine
constant is untouched and the slider's cold cost falls from **198 writes to 108**.

**[CONFIRMED FROM CODE — correction to the winner's M.1.6].** The winner claims `HideBody` *"keeps
sweeping all 20 ids (correct by the same reasoning as invariant I8)"*. It does not sweep them in the
sense required. The loop **Hides**, it does not Remove (`SSR_Panel.mqh:2093-2094`):

```
      for(int t = 0; t < SSR_SPEED_LADDER_SIZE; t++)
         m_w.Hide("spdseg" + IntegerToString(t), hidden);
```

so on an upgrade from a build that drew twenty cells, `spdseg10..spdseg19` still exist on the chart
and the next `Hide(false)` **un-hides them**, leaving ten orphan cells over the groove. Invariant I7
(*"removed, not merely undrawn"*) requires a one-shot `Remove` in `Create()`.

[RECOMMENDATION] **One upgrade sweep, one flag.** Fold that Remove together with the nine permanent
v124 `Remove()` calls that run on **every frame** today —

```
SSR_Panel.mqh:932-934     m_w.Remove("palette"); m_w.Remove("keys"); m_w.Remove("move");
SSR_Panel.mqh:1189-1191   m_w.Remove("follow");  m_w.Remove("bookmark"); m_w.Remove("jump");
SSR_Panel.mqh:1241-1243   m_w.Remove("follow");  m_w.Remove("bookmark"); m_w.Remove("jump");
```

— into a single `UpgradeSweep()` called once from `Create()`, guarded by a `m_swept` flag. Under R1
those nine per-frame `Remove()` calls are pure waste (9 finds + 9 `Forget()` on every still frame);
once swept they cost nothing, ever again. This is the cheapest line item in the document.

---

### M.2 The five rules the constraints dictate

**R1 — Navigation is the only thing allowed to delete.**
`HideSheets()` and `HideBody(false)` become **transition-driven**: they run on the frame where
`m_tab`, `m_compact`, `m_tall`, `m_collapsed` or `m_closed` differs from the value the last render
used, and on no other frame. [CONFIRMED FROM CODE] The file already shows the pattern at `:679-687`,
where `HideSheetArea` is called only inside `if(m_compact != was_compact)`. This is the single
highest-value change in the document; it fixes `ui-panel-1`, `ui-panel-2` and (by ordering)
`ui-panel-3`.

> [INFERENCE — the coupling warning that must travel with R1] Under the latch, slot 12 and slot 17
> both take the `Same()` early return and `setuprow` keeps whatever was written last. R1 therefore
> does **not** fix `ui-panel-5` (CONFIRMED, MEDIUM) — it changes its shape from "visible for one
> frame" to "whichever of the two wrote last, permanently". Giving `order_why` its own object id
> (M.4.1) must land in the **same change**, not after it.

**R2 — Everything OPERATED is chrome; everything CONSULTED is a destination.**
[CONFIRMED FROM CODE] The rule already exists and is correct (`SSR_Panel.mqh:670-674`: *"keeps what
is OPERATED — clock, transport, speed, status — and drops what is only CONSULTED"*). It is why the
brief's HOME and REPLAY are rejected.

**R3 — An overlay is a per-frame rebuild; a destination is a per-click rebuild.**
A surface stays an overlay only if it is (a) a modal decision about the chart underneath it, (b) a
moment rather than a reference, or (c) a search field that must float.

**R4 — Every destination owns its teardown list, declared beside its draw function.**
[CONFIRMED FROM CODE] Today three lists disagree: `HideSheets()` (`:1284`) 70 named ids with
`spreadrow`/`traderr` listed twice and four dead entries (`g3_fr g3_lb g3_lg pp_g`) plus 4×3 meter
parts and 12×6 row parts = **154 `Remove()` calls**; `HideSheetArea()` (`:2042`) stopping at `tab3`
(`ui-panel-4`); `HideBody()` (`:2077`) 30 ids plus three loops. One list per destination, iterated
only for the destination being **left**, is both cheaper (≈25 `Remove`) and cannot drift.

**R5 — Every row declares a character budget and goes through `Clip()`.**
46 at `FS_BODY`, 52 at `FS_SMALL`, split at column boundaries for two-column rows. Add audit
**A22**: every `Text(` / `Label(` call site under `/Ui/` either passes a `Clip(...)` expression or
carries an explicit `// unbounded:` justification. ~200 mechanical edits, and it retires the whole
first paragraph of L.9. A22 is the only instrument that can see this class of defect, because I10
guarantees `CheckFrame()` never will.

---

### M.3 The navigation model

#### M.3.1 Three bands, one swapped region

```
  +--------------------------------------------------------------+  <- CHROME, never navigates
  | SS Replay  v125   PAUSED      [TICK] [BLIND] [PROP]    -  X  |     caption      23
  | 09:41:07                                          62%        |     clock+bar    32
  | |<  <<  <  [    PAUSE    ]  >  >>          Reset             |     transport    27
  | Speed  -  [ 4x ]  +  ====|.........   4 bars a second        |     speed        21
  +--------------------------------------------------------------+
  | Lines        Sessions        Fidelity                        |     actions      21
  +------+-------------------------------------------------------+     hairline
  |Trade!|                                                       |
  |Pos  3|                                                       |
  | Perf |            THE SHEET - the one swapped region          |     186 / 326
  | Sess |                      245 px wide                       |
  | Keys |                                                       |
  | Eval!|                                                       |
  +------+-------------------------------------------------------+
  | 10,412.55   +38.20   3 open   2 adrift F                     |     status       18
  +--------------------------------------------------------------+
```

[CONFIRMED FROM CODE] This is the existing grammar (`SSR_Panel.mqh:631-826`), unchanged in
structure. The proposal does not invent a layout; it fixes what the bands contain and makes the swap
cheap.

**Why exactly one swapped region.** Two swapped regions need two teardown lists, two transition
latches and a combinatorial z-order, on a toolkit whose only ordering is creation order. One region,
one latch, one list per destination is the cheapest correct model — and it is already the one in the
file.

#### M.3.2 The brief's eight, judged against the code

| Brief's destination | Verdict | Reason, from source |
|---|---|---|
| **HOME** | **REJECT** | Everything a home would show is already permanent chrome: state and modes in the caption (`DrawCaption:833-940`), clock and progress (`DrawClock:945`), balance / float / open in the status strip (`DrawStatus:1915`). A HOME destination is the chrome drawn twice, at the cost of a rail cell and a click. The chrome *is* home |
| **REPLAY** | **REJECT as a destination** | Transport (`y+55`) and speed (`y+82`) are operated controls and stay permanent under R2. Putting PLAY behind a click is the one change that would make this product worse. The *consulted* replay data — bars, ticks, rejected, guard violations, streams, skew, leak advice, checkpoints — has a home already: **SESSION** |
| **TRADE** | **ACCEPT** | Exists: `SheetTrade` (`:1346`). The only sheet that acts, the densest, and the one with the typed field |
| **POSITIONS** | **ACCEPT** | Exists: `SheetPositions` (`:1509`). `PosCap()` 5 → 12 in Expanded (`:432`) |
| **PERFORMANCE** | **ACCEPT, re-homed** | The content exists and is excellent — 43 measures in 9 groups, `SSRReviewRows()` (`SSR_Review.mqh:104-161`). Today it is reachable only as a 520 px overlay on `A`. The current Stats sheet (`:1671`) is 3 numbers duplicated from the status strip, 3 run counters, and a button |
| **CHALLENGE** | **ACCEPT as EVAL** | Exists: `SheetProp` (`:1749`), four meters, conditional on `prop_on`, `TabCount()` asked rather than assumed (`:1103`). [RECOMMENDATION] Do not rename the ids or the string keys; the display text is a one-line change in `SSR_Strings.mqh` and `fa.txt` if the author prefers "Challenge" |
| **JOURNAL** | **REJECT for v1** | `CSSRJournal` is an **exporter**, not a browser: `ExportCsv`/`ExportHtml` write files and `Line(index, digits)` is an O(n) walk (`trading-analytics.md` §4). Eight rows on screen costs O(8n) per frame. It also rests on `ui-port-session-2` and `ui-port-session-3` (both CONFIRMED HIGH) for persistence and on an unsettled mouse question for a typed note. Keep JOURNAL as the `stmt` action on PERFORMANCE. [FUTURE FEATURE] a real journal destination needs an indexed accessor first |
| **SETTINGS** | **REJECT** | There is no body of mid-session settings. Speed is chrome; risk is on TRADE; trailing is on POSITIONS; fidelity and lines are action buttons; panel size and collapse are keys. The 61 expert inputs are pre-session and belong to `CSSRSetupPanel`. The command palette (31 entries, 4 groups, `SSR_Command.mqh`) is already the settings surface and costs one `Edit` and eight rows |

Eight becomes five. Add **KEYS** — which the brief does not list and the code needs more than
anything else in it — and the rail is six.

#### M.3.3 The proposed rail

| # | id | name (EN) | drawn | conditional |
|---|---|---|---|---|
| 0 | `tab0` | Trade | `Trade` / `Trade !` | no |
| 1 | `tab1` | Positions | `Pos` / `Pos %d` | no |
| 2 | `tab2` | Performance | `Perf` / `Perf !` | no |
| 3 | `tab3` | Session | `Sess` | no |
| 4 | `tab4` | Keys | `Keys` | no |
| 5 | `tab5` | Evaluation | `Eval` / `Eval !` / `PASS` / `FAIL` | **yes** (`prop_on`) |

`25×6 - 3 = 147 px` of a 186 px rail. 39 px spare — one more cell plus 14 px — **left unspent on
purpose.** A rail at capacity is a rail that cannot absorb a feature.

[CONFIRMED FROM CODE] Constraints this respects:

* **The conditional destination stays last.** `TabCount()` is `return (m_state.prop_on ?
  SSR_TAB_MAX : SSR_TAB_COUNT);` (`:1103-1104`) and the re-clamp is `if(m_tab >= TabCount()) m_tab =
  SSR_TAB_STATS;` (`:745-746`). The question can only ever hide the **final** cell, so any layout
  that puts a conditional destination at an interior index silently deletes every cell after it in a
  non-prop session. (This is why coach-first's rail order — with CHALL conditional at index 3 and
  JRNL at 4 — could not ship as written.)
* **Dispatch is untouched.** The `tabN` arm tests `StringLen == 4 && prefix "tab"` (`ui-panel.md`
  §7.2); `tab0`..`tab5` are all length 4. *"A click on `tab2` still selects sheet 2 whichever layout
  is built"* (`:1205-1206`) survives verbatim.
* **Names stay inside ~8 characters at 44 px.** [POTENTIAL_RISK] Persian remains unverifiable —
  `rtab.positions = پوزیشن` with a Latin digit appended is a mixed-direction string in a bidi-less
  renderer (L.3.3). Unchanged by this proposal, and unclosable without a terminal.

**Cost of going from five cells to six**, booked explicitly rather than claimed free:
[CONFIRMED FROM CODE] `SSR_Theme.mqh:542` is `#define SSR_TAB_COUNT 4` and `:544` is
`#define SSR_TAB_MAX 5`. The change is `SSR_TAB_COUNT 4 → 5`, `SSR_TAB_MAX 5 → 6`, `SSR_TAB_PROP
4 → 5`, one new enum value, three short strings plus their `fa.txt` rows. The clamp target
`SSR_TAB_STATS` is index 2, which under the new map is **Performance** — a sensible default, but the
constant's *name* now reads wrong and should be renamed with the destination.

[INFERENCE] `RestorePlace()`'s sanity bound is `if(tab >= 0 && tab < SSR_TAB_MAX) m_tab = tab;`
(`SSR_Panel.mqh:585-586`), so a v125 `panel.ini` holding `tab=4` (Prop) selects **Keys** on the first
run of the new build. Harmless, but it must be named in the release note, and it argues for renaming
the `[panel]` key from `tab` to `dest` so an old value is simply not found.

#### M.3.4 Notice without navigation: a rail cell can raise its hand

The winner has no notice-without-navigation mechanism at all, and that is its largest pedagogical
gap: a trainee 85% through today's loss allowance is told only if they happen to click EVAL. Both
runners-up propose a fix; they disagree on the mechanism, and the disagreement matters.

**Intent, adopted from coach-first M.3.1 [RECOMMENDATION]:** a destination that holds a crossed
condition says so in its rail cell, and it says so with a **glyph, not a colour**. The product's own
rule is stated at `SSR_Panel.mqh:858-862`:

```
      //| Modes are CHIPS - text on a tinted plate - because a mode         |
      //| carried by colour alone is a mode a colour-blind trader cannot    |
      //| read.
```

A coloured dot in a rail cell is exactly the thing that comment forbids. `!` / `!!` at the cell's
text carries the signal; colour only carries the speed.

**Mechanism, corrected — the mark is text inside the cell, not an object over it.**
Coach-first draws five new label ids (`tabf0..tabf4`) inside the `DrawRail` loop. That is five new
objects, five new cache slots, and — the reason to reject it — an object drawn on top of the one
control the user must always be able to hit. [CONFIRMED FROM CODE] the file records that exact
failure mode about the slider thumb (`SSR_Widgets.mqh:455-458`):

```
   //| The thumb is a rectangle label, so a click landing exactly on it  |
   //| is swallowed rather than reaching a cell. Four pixels out of a    |
   //| hundred and eighty, and the value it would have set is the value  |
   //| it is already on.
```

Four pixels of a slider whose click is idempotent is an acceptable loss. Six pixels of a 44 px
navigation cell is not, because the click that is swallowed is the click that would have taken the
user to the warning.

[CONFIRMED FROM CODE] **`TabName()` already interpolates state.** `SSR_Panel.mqh:1108-1121`:

```
         case SSR_TAB_POSITIONS:
            return (m_state.open_positions > 0
                    ? StringFormat(T(SSR_S_RTAB_POSITIONS_N), m_state.open_positions)
                    : T(SSR_S_RTAB_POSITIONS));
         case SSR_TAB_STATS:     return T(SSR_S_RTAB_STATS);
         case SSR_TAB_SESSION:   return T(SSR_S_RTAB_SESSION);
         case SSR_TAB_PROP:
            return (m_state.prop_state == 3 ? T(SSR_S_TAB_PROP_FAIL)
                    : (m_state.prop_state == 2 ? T(SSR_S_TAB_PROP_OK)
                                               : T(SSR_S_RTAB_PROP)));
```

`Pos %d` and the PASS/FAIL verdict are already condition marks in the cell's own text. Appending
` !` is the same move: **zero new objects, zero new slots, zero new geometry**, and it inherits the
existing `for(int i = n; i < SSR_TAB_MAX; i++) m_w.Remove("tab"+...)` sweep at `:1222-1224` for
free.

**Conditions, all from wire fields that exist on day one:**

| Cell | Condition | Source | Mark |
|---|---|---|---|
| Trade | `lines_armed && order_why != ""` | `order_why` | `!` (`SSR_C_HOLD` text) |
| Trade | `lines_armed && sl_price == 0` | `sl_price` | `!!` (`SSR_C_STOP`) |
| Positions | `open_positions > pos_rows` | both on the wire | the count is already the mark |
| Eval | `prop_daily_used >= 0.8 \|\| prop_total_used >= 0.8` | existing | `!` |
| Eval | `prop_state >= 3` | existing | already `FAIL` |
| Performance | discipline crossed | **held** until M.4.3's throttled statistics exist | `!` |

**Budget, and it is the whole cost of the mechanism.** The cell is 44 px ≈ 8 characters at
`FS_BODY`. `Trade !` is 7, `Eval !` is 6, `Pos 12` is 6, `Perf !` is 6. The mark is appended only
where the base name is ≤ 6 characters, and the composed string is `Clip()`ed at 8 under R5 —
MetaTrader centres button text and will not clip it itself.

**What is given up, stated honestly.** [INFERENCE] The cell's text colour is already carrying
selected-vs-unselected (`on ? SSR_C_TEXT : SSR_C_TEXT_DIM`, `:1216`). Colouring the mark means
either re-using that channel or drawing the whole cell's text in the alarm colour. The recommendation
is the latter — an alarmed cell draws its text in `SSR_C_HOLD`/`SSR_C_STOP` whether or not it is
selected — which loses one bit of selection contrast on the alarmed cell and keeps the selected
cell's *plate* colour (`SSR_C_TAB_ON`) as the selection signal. That is a real, named trade; the `!`
is what makes it safe to make.

**Sequencing.** This lands **after** R1. [CONFIRMED FROM CODE] with `ui-panel-3` (CONFIRMED, HIGH)
unfixed — `HideBody(false)` at `:729` undoing `HideSheetArea(true)` at `:682` inside the same
`Render()` — a compact chart leaves the rail on the candles, and marks would put warnings on the
candles too.

*[Adjudication: this is the one place the two runners-up were graft-incompatible. The intent is
coach-first's and is non-negotiable; the mechanism is the correction the third judge raised, and it
is taken because it is cited from the file's own comment and costs strictly less.]*

#### M.3.5 Navigation inside a destination: pages, never scroll — and a read-only row

[CONFIRMED FROM CODE] The product already has exactly one correct answer to "more rows than fit",
and it is the review card: `SSR_RV_SHOWN 12`, `m_first`, explicit `up`/`down`
(`SSR_ReviewCard.mqh:32-34`), header comment *"PAGED, BECAUSE MQL5 CANNOT CLIP"* (`:12`).
`CSSRWidgets::List` (`SSR_Widgets.mqh:565`) is the primitive, and `CSSRPalette` and
`CSSRSessionDialog` both use it.

**Rule:** a destination that overflows **pages**. The pager is two 30 px buttons and one
`"%d-%d of %d"` label in the sheet's last 19 px. Never a scrollbar, never a "show more" that grows
the frame.

**[RECOMMENDATION — a graft the winner needs twice and specified once] Add `ListRO`.**
The winner's M.4.3 correctly says PERFORMANCE rows must be *"a `Label` on a `Rect`, not buttons"*,
and its M.5 then maps the destination onto `CSSRWidgets::List`. Those are not the same thing.
[CONFIRMED FROM CODE] `List` draws `ButtonC`/`Button` rows (`SSR_Widgets.mqh:571-587`):

```
         if(idx == selected)
            ButtonC(rid, x, y + i * row_h, w, row_h, rows[idx], ...);
         else
            Button(rid, x, y + i * row_h, w, row_h, rows[idx]);
```

Add a `ListRO` sibling — one `Rect` well plus a cached `Label` per row, the same
`first`/`shown`/`Remove`-the-tail contract — and use it for **PERFORMANCE** and **KEYS**, whose rows
are read, never chosen. **6 writes a row instead of 9**, and no false affordance.

It also retires `ui-dialogs-16` (CONFIRMED, IMPROVEMENT): the review card's 12 measure rows are
`OBJ_BUTTON`s whose latch nothing consumes, so a clicked statistic stays drawn pressed. Same
primitive, same fix, one place.

#### M.3.6 What stays an overlay, and why

| Surface | Stays? | Reason under R3 |
|---|---|---|
| Command palette (`SSRX_`) | **overlay** | a search field that must float over what it searches. Drawn last of all (`:816`) |
| Session picker (`SSRSD_`) | **overlay** | a modal decision that replaces the whole session. 420 px; cannot fit a 245 px sheet |
| Range / jump dialog (`SSRD_`) | **overlay** | a modal decision about an instant, quoting its cost before anything is written |
| Review card (`SSRR2_`) | **overlay** | a *moment* — the end-of-session verdict with ≤6 observations. Its 43-measure table is now also a destination; both read one generator, so there is no second list to drift |
| Reveal card (`SSRV_`) | **overlay** | one button, keys dropped while up. The cleanest surface in the product |
| **Key card (`SSRK_`)** | **BECOMES A DESTINATION** | 18 listed rows read for minutes, rebuilt destructively at 10 Hz (`ui-panel-12`). The exact case R3 exists to catch |
| **First-run card (`SSRF_`)** | **REMOVED** | M.4.5 |

Net: nine object-name prefixes become **seven**; two classes and one `seen.txt` side effect go away.

#### M.3.7 One navigation mechanic examined and rejected

User-first proposes promoting the status-strip readouts to buttons — `stopen` → POSITIONS,
`stbal` → PERFORMANCE — as zero-pixel navigation that also works in Compact. It is rejected, on four
grounds, three of them confirmed from source:

1. [CONFIRMED FROM CODE] **It collides with the status ladder.** Four of the five ladder levels
   write **slot 50 / id `stbal`** and hide the other four readouts — `SSR_Panel.mqh:1929` (the reset
   warning), `:1947` (`m_port.TradeError()`), `:1988` (`m_pro_why`), `:2001` (`TooNarrow()`), and
   `:2015` is the number itself. The one **destructive question in the product** would be drawn on a
   button that navigates.
2. [CONFIRMED FROM CODE] **It does not work in Compact anyway.** `DrawStatus` is reached, but a
   Compact panel has no sheet to navigate to: `if(!m_compact)` at `SSR_Panel.mqh:740` guards
   `DrawActions`, `DrawRail` **and** `DrawSheet` together (`:750-752`).
3. [CONFIRMED FROM CODE] **`stfid` cannot be a button where it is.** It is drawn at `Text(53,
   "stfid", x + 330, ...)` (`:2033`) in a 310 px panel.
4. [INFERENCE] A latch-polled button drawn to look identical to the label it replaces is
   undiscoverable to the novice this whole architecture is for.

**What survives from the idea:** [RECOMMENDATION] user-first's observation that promoting a label to
a sized object is what would finally make it visible to `Extent()`/`CheckFrame()` — which is exactly
why `ui-panel-6` went unreported for so long (invariant I10). That argues for **A22**, the static
audit, not for buttons. And [RECOMMENDATION] the ladder's warning lines deserve their own id
(`stmsg`) rather than borrowing slot 50 — not because it is a live defect (the ladder hides the
other four, so it is exclusive by construction) but because slot-sharing between two unrelated texts
at one coordinate is precisely the shape of `ui-panel-5`. Hygiene, IMPROVEMENT, one id.

---

### M.4 What each destination holds

Notation: `slot` is the panel's 128-entry label cache (`SSR_SLOTS 128`, `SSR_Panel.mqh:51`);
`budget` is the R5 character budget; **new** marks a row drawn nowhere today.

#### M.4.0 The chrome, and the status strip

| Band | Content | Change |
|---|---|---|
| caption 23 | identity, build tag, run state, mode chips (`chfid`/`chblind`/`chprop`), `-`, `X` | **none structurally.** `ui-panel-13` (CONFIRMED, LOW): the chip row ends at `x+274` and `collapse` starts at `x+268`. Move the chip origin `x+140` → `x+134` and cap the fidelity chip at 6 characters. Modes-as-chips (`:858-862`) is preserved verbatim |
| clock 32 | masked clock, `%d%%` + pause reason (`Clip` 24), progress bar | none |
| transport 27 | `\|< << < [PLAY/PAUSE 91px] > >>` ··· `Reset 58` | none. The 91 px primary against 24 px steps is how primary-vs-secondary is carried. (`ui-plumbing-10`, which claimed the primary and an engaged toggle share a colour, is **NOT_A_BUG** in `verified.json` — no part of this architecture may act on it) |
| speed 21 | label, `-`, value box, `+`, groove, meaning | 20 cells → **10 drawn cells** (M.1.6), plus the one-shot `Remove` of `spdseg10..19`. Meaning text `Clip(..., 11)` — fixes `ui-panel-8` |
| actions 21 | `Lines` \| `Sessions` \| `Fidelity` | none. Three at 96 px, **and there is no fourth 96 px cell in 310 px** — which is why `CSSRAutoPause` stays [FUTURE FEATURE] |
| status 18 | **four** readouts, not five | below |

**The status strip: five numbers into four slots.**
[CONFIRMED FROM CODE] `ui-panel-6` (CONFIRMED, **HIGH**) — `SSR_Panel.mqh:2033`:

```
      Text(53, "stfid", x + 330, y + 4,
           SSRFidelityName(m_state.fidelity_effective) + (degraded ? " !" : ""), ...
```

The anchor alone is 20 px past a 310 px frame, and `"SYNTHETIC TICK !"` adds 70-80 px more, on every
frame of every session.

**The fix is deletion, not relocation.** [CONFIRMED FROM CODE] fidelity is already a caption chip
(`chfid`, `DrawCaption:886`), drawn from the same `SSRFidelityShort()` with a `!` when degraded — the
strip was printing it twice, and the caption's own comment (`:858-864`) says why the caption is where
it belongs: *"Fidelity MOVED here for exactly that reason… it is a mode, not a measurement."*

That frees **slot 53**, and it is spent on the one piece of information v125's removals cost:

```
x+8     balance        Clip 14      stbal     slot 50
x+106   floating       Clip 12      stflt     slot 51
x+196   N open (+P)    Clip  9      stopen    slot 52
x+252   sp N.N         Clip  8      stspread  slot 54
        ...replaced, while charts_detached > 0, by:
x+252   N adrift  F    Clip  8      chartsn   slot 53
```

[CONFIRMED FROM CODE] `m_state.charts_detached` is filled by `CSSRGroupPort`
(`SSR_GroupPort.mqh:122`: `out.charts_detached = (m_charts != NULL ? m_charts.DetachedCount() : 0);`)
and matches **zero times** in `SSR_Panel.mqh`. `chart-10` (CONFIRMED, MEDIUM): *the replay advances,
the candles stop moving, and the interface says nothing at all.* Spread is the right thing to yield
the slot — it also appears on the Trade sheet and in the fill toast.

**[RECOMMENDATION — the accounting discipline grafted from user-first].** Whichever form ships,
**name its cost in the caption comment block the way v125 recorded what each removed button cost.**
That record is the only reason `chart-10` was findable at all. If a future build prefers
`charts_detached` as a caption chip rather than a strip slot, then user-first's payment rule
applies: the chip row already overruns by 6 px (`ui-panel-13`), so a new chip is funded by dropping
the `PROP` chip whenever the Eval rail cell is visible — the cell already says an evaluation is
configured and is the larger signal. **This proposal adds no caption chip and therefore owes no
payment**; the rule is recorded so that the next one does.

[RECOMMENDATION] Preserve the ladder's priority order and its written rationale (`:1915-2035`)
exactly. `charts_detached` is a *standing condition*, so if the author prefers it as a ladder line
rather than a slot, it belongs at **level 5** — below `TooNarrow()`, above the numbers — by the
ladder's own rule. It does **not** belong at levels 1-4, because those commandeer `stbal` and a
standing diagnostic must never sit in the row a coach reads for money.

#### M.4.1 TRADE — *what I am about to do*

Reuses `SheetTrade` (`SSR_Panel.mqh:1346`). It is the densest and best sheet in the product.

| row | content | source | slot | budget |
|---|---|---|---|---|
| Group | "Risk" | — | — | — |
| **verdict** | `0.50 % · 25.00 · 2.0 R · 0.42 lot` **new placement** | `risk_percent`, `risk_money`, `rr`, `lot_from_risk` | 22 | 40 |
| risk ladder | `- [ 1.00% ] +`, monitor | `risk_percent` | 10, 11, 19 | 20 |
| setup tag | `OBJ_EDIT` `tagbox` | `trade_tag` | — | — |
| Group | "Order" | — | — | — |
| side / order kind | `LONG setup` \| `order_name` | `line_long`, `order_name` | 12 | 30 |
| **why refused** | `order_why`, **its own object id** | `order_why` | 17 | 44 |
| SL \| TP (with money) | `slrow` \| `tprow` | `sl_price`+`risk_money`, `tp_price`+`reward_money` | 13, 14 | 22 each |
| RR \| size | `rrrow` \| `sizerow` | `rr`, `lot_from_risk` | 15, 16 | 22 each |
| **allowance** | `this stop would use n% of today's allowance` **new** | `prop_daily_room_after` | 23 | 46 |
| arm / flip / clear | three buttons | `lines_armed` | — | — |
| BUY \| SELL | the primary pair | `can_trade` | — | — |

**[CONFIRMED FROM CODE — correction to the winner's M.4.1].** The winner lists `risk_money` and
`reward_money` as **new** rows to be added at slots 20 and 21. Both are already drawn, inside the
existing stop and target rows (`SSR_Panel.mqh:1407-1414`):

```
         Text(13, "slrow", x + 8, gy + 24,
              StringFormat(T(SSR_S_STOP_ROW), Price(m_state.sl_price),
                           Money(-m_state.risk_money, true)), SSR_C_TEXT);
         Text(14, "tprow", x + 8, gy + 36,
              StringFormat(T(SSR_S_TARGET_ROW), Price(m_state.tp_price),
                           Money(m_state.reward_money, true)), SSR_C_TEXT);
```

The rows are struck. Independently, **slot 20 is not free** — it is `posempty` on the Positions sheet
(`:1519`), and the 128-slot cache is global across sheets. Slot assignment comes from the verified
free list at M.7, never from a guess.

**The verdict line [RECOMMENDATION, grafted from coach-first M.4.1].** A trainee currently reads
legality by assembling four numbers spread over 92 px of group box: risk % on row 1, stop price on
row 4, R on row 4-right, lot on row 5-right. Put the result **first**, as one legible line, coloured
by the **worst** of three tests — no stop → `SSR_C_STOP`; `order_why != ""` → `SSR_C_HOLD`;
otherwise `SSR_C_TEXT`. Every operand is already on the wire and every one was computed by the owner
that will execute the order — `PreviewLot` is *the same call the order uses, never a second formula*
(`ui-port-session.md` §3.3). The panel still computes nothing.

**`order_why` gets its own object id, and it must land with R1.** [CONFIRMED FROM CODE]
`ui-panel-5` (CONFIRMED, MEDIUM) — slots 12 and 17 write the **same object `setuprow` at the same
coordinates**, so the refusal is visible for one frame and then gone. See the coupling warning at R2
above: under the transition latch the defect changes shape rather than disappearing, so the id split
is part of change #1, not a follow-up.

**`DailyRoomAfter()` [RECOMMENDATION, grafted from coach-first].** The question a coach asks more
than any other — *"if that stop gets hit, how much of today is gone?"* — is not answerable on any
screen in this product. Both operands are on the wire, but the arithmetic must **not** happen in the
panel. `SheetProp`'s own comment says why (`SSR_Panel.mqh:1732-1740`):

```
   //| THIS SHEET COMPUTES NOTHING. Every fraction arrived from the      |
   //| evaluation, which is the one place that knows what these rules    |
   //| mean and the same place that decides whether the run is over.
```

So it becomes **one accessor on `CSSRPropEvaluation` (`DailyRoomAfter(double loss)`) and one
pre-clamped wire field** — drawn on TRADE as a percentage sentence and on EVAL as the same number in
money. One owner, two readers, no second formula. Gated on `prop_on`; the row is absent, not zero,
when no evaluation is configured.

**Refused for this destination:** a stop/target stepper, a lot-size box, an order-type selector. All
three are decisions the chart lines already make from geometry, and each needs a control MQL5 cannot
draw.

#### M.4.2 POSITIONS — *what is open, and what just closed*

Reuses `SheetPositions` (`:1509`) with re-derived arithmetic and one new page.

**The row arithmetic must be re-derived for 245 px.** [CONFIRMED FROM CODE] `ui-panel-7`
(CONFIRMED, MEDIUM) — the note is anchored at `x+120` (`:1576`) and the money at `x + w - 116`
= `x+129` (`:1582`, `:1585`) — **nine pixels for the nine characters of `"  no stop"`**, and the same
for `"  sp 20.0"`. The two things a trader reads on that row are printed over each other. The row's
own comment block at `:1563-1575` documents the *previous* version of this same collision, which is
how a fix that re-introduced it went unnoticed.

Proposed columns in 237 px, three row buttons at the right taking 60:

```
x+0    text   "BUY 1.00 @ 53513"       Clip 18      ~92 px
x+96   note   "! no stop" / "sp 20.0"  Clip  8      ~40 px
x+140  money  "+38.20"                 Clip  8      ~40 px
x+180  H B X  three 18 px buttons                    60 px
```

[RECOMMENDATION, grafted from coach-first M.4.2] the no-stop flag leads the note with `!` — as a
**prefix character of the existing `pn<r>` text**, not a new gutter object, so it costs no id and no
slot and inherits the colour the note already carries (`m_state.pos_no_stop[r] ? SSR_C_STOP :
SSR_C_TEXT_FAINT`, `:1577-1578`).

[INFERENCE] `posmore` at `x+w-92 = x+153` currently shares a baseline with the 37-character
`poshint` drawn from `x+8`, which reaches ≈ `x+175`. Put `posmore` on its own baseline.

**Removed:** the three row-button captions `H`, `B`, `X`, which are the same letters as three
**global keys with three unrelated meanings** (`ui-plumbing-14`, CONFIRMED, LOW: `H` opens the key
card, `B` bookmarks, `X` flips the planning lines). [RECOMMENDATION] relabel to `½` / `BE` / `✕` and
let the hint line name the actions rather than the letters. Cost: three strings.

**New — the Closed page [graft from user-first M.4.2, the one trainee idea neither other proposal
has].** [CONFIRMED FROM CODE] a trainee cannot see the trade they just closed. The wire's position
arrays are open-and-pending only (`SSRUiState.pos_*`, six parallel arrays of `SSR_POS_MAX 12`,
filled by `CSSRGroupPort::ReadState`); closed trades exist only in the exported CSV/HTML
(`CSSRJournal`) and as 43 *aggregate* measures on the review card. **Between the four-second fill
toast (`SSR_Panel.mqh:787-803`) and the end-of-session card, the record of an individual trade is
unreachable.** For a training product that is the wrong gap to have.

An Open / Closed toggle reuses the row grammar exactly: ticket-or-tag, side, size, and the closed net
in place of the floating P/L, newest first, `PosCap()` rows, the same `posmore` overflow story.

Cost, itemised and gated:

* **The walk must be gated.** [CONFIRMED FROM CODE] `At(i, SSRVirtualPosition&)` is a full struct
  copy, ~660 B plus two strings (`trading-analytics.md` preamble), and finding the newest 12 closed
  trades is O(`Total()`) copies **per `ReadState`, i.e. 10 times a second**. [RECOMMENDATION] add one
  setter, `CSSRGroupPort::WantClosed(bool)`, called by the panel on a destination change — the same
  shape as the existing host-only setters (`SetTpPoints`, `NoteLineDistances`), so it costs no new
  pattern. The fill runs only while the Closed page is up.
* **Wire growth.** Six more parallel arrays of 12, or a `pos_closed[]` flag plus a
  `closed_rows` count. The wire is flat and pointer-free by design, so this is additive — but
  `SSRUiState::Init()` clears every field in one loop (`SSR_ReplayPort.mqh:238`) and that loop grows.
* **Layout — take option (a).** Positions uses 183 of 186 px today. Make the existing two-button row
  three: `Open/Closed` · `BE all` · `Close all`, `bw = (245 - 2*5)/3 = 78 px`. That costs no height.
  The alternative — taking 19 px from the position group — drops `PosCap()` from 5 to 4 in Standard,
  and one fewer visible position is a real regression for the moment this destination exists to
  serve. [RECOMMENDATION] **shorten the two catalogue strings rather than clipping at the draw
  site**; the Persian catalogue is the tighter case and the strings are the shortest-lived part of
  the design.
* **Sequencing.** After R1, and after `ui-panel-7` is re-derived — or the Closed page inherits the
  collision and the defect is built twice.

#### M.4.3 PERFORMANCE — *what I have done*

This is the destination that gains the most, and the winner priced it wrong.

**The plumbing, which the winner got right.** [CONFIRMED FROM CODE] `SSRReviewRows(const
SSRStatistics &st, SSRReviewRow &out[])` (`SSR_Review.mqh:104`) produces **43 rows in nine groups** —
Result (10), Rates (8), R (4), Drawdown (4), Streaks (3), Excursion (2), Time (2), Discipline (4),
Execution (6) — and `SSRReviewLine()` formats one to `SSR_REVIEW_ROW_MAX 60`, *"60, not 63, because
the card puts a two-character group marker in"* (`:50`). One generator, two consumers: this sheet and
the end-of-session card. There is no second list to drift.

**[CONFIRMED FROM CODE — the winner's factual error].** Constraints-first claims PERFORMANCE costs
*"zero new measures, zero new port fields, zero new statistics code."* It cannot. `SSRReviewRows`
takes an `SSRStatistics`, and **no such struct exists anywhere in the port or the panel**: `grep -c
SSRStatistics SSR_ReplayPort.mqh` returns **0**, and it matches zero times in `SSR_Panel.mqh`. Today
the struct reaches a UI surface exactly twice, and both times the **host** computes it at the moment
of opening and hands it in:

```
SSReplayStandalone.mq5:976-977    g_stats.Compute(st);
                                  g_review.Show(g_panel_chart, st);
SSReplayStandalone.mq5:3009-3010  SSRStatistics st;
                                  g_stats.Compute(st);
SSR_ReviewCard.mqh:78             bool Show(const long chart_id, const SSRStatistics &st)
SSR_ReviewCard.mqh:87             m_n = SSRReviewRows(m_st, m_rows);
```

A destination repaints; a card does not. Something must own the struct on the panel's side, and it
cannot be computed per frame: [CONFIRMED FROM CODE] `ComputeFor` is *"up to 3 passes over `Total()`
slots with a struct copy each + O(4096) drawdown walk"* (`trading-analytics.md` §3) against up to
`SSR_MAX_POSITIONS 512` slots, on the thread that pumps ticks. At 10 Hz it is unaffordable, and the
winner's cost ledger currently hides that.

**The throttle, grafted from user-first M.4.3 and coach-first M.4.3 (they agree).**
[CONFIRMED FROM CODE] `CSSRGroupPort` already holds the pointer — `CSSRStatsEngine *m_stats;`
(`SSR_GroupPort.mqh:49`) and `void AttachStats(CSSRStatsEngine *s) { m_stats = s; }` (`:91`) — so
only the *read* is new. And the change-detector is **already computed on the wire**:

```
SSR_GroupPort.mqh:241    out.closed_trades  = m_acct.ClosedCount();
```

So: **recompute when `m_acct.ClosedCount()` changes, or every 2000 ms, whichever comes first, and
cache one `SSRStatistics` in `CSSRGroupPort`.** `ClosedCount()` is O(1) and a closed-trade count that
has not moved cannot change any measure except drawdown. This is consistent with the winner's own R3
— compute on entering the destination, not on the frame — and it needs neither a new collaborator nor
a new call.

**The disclosure, grafted from coach-first, and it must be written at the site.** The pattern numbers
may lag the account by up to two seconds; the live numbers on the status strip do not. For a pattern
read over twelve trades two seconds is nothing; beside a live P/L it would be a lie. **That split is
the design, not a compromise** — result numbers a trainee reads live (balance, floating, open count)
stay on the status strip, computed per frame from the account; pattern numbers live here, throttled.

**The first page is curated; the remaining 43 page behind it.** 43 rows in generator order is a
table, not teaching. Page 1 is fixed and answers the four things a learner must be told:

```
   ┌ RESULT ────────────────────────────────────┐
     12 trades      58 % win       PF 1.42
     net  +412.80        expectancy +0.31 R (11 of 12)
   └────────────────────────────────────────────┘
   ┌ DISCIPLINE ────────────────────────────────┐
     risk varied     18 %  over 11 trades
     back in after a loss   2
     no stop                1
     ambiguous bars         2  (17 %)
   └────────────────────────────────────────────┘
   numbers may lag the account by up to 2 s
   <  1-8 of 43  >                    [ Save statement ]
```

| region | content |
|---|---|
| page 1 | curated Result + Discipline, fixed |
| pages 2-n | the generator's remaining rows, group header + `"%d-%d of 43"`, **`ListRO`** (M.3.5) |
| rows | 8-9 per page (Standard) / 17 (Expanded) |
| pager | `<` `>` two 30 px buttons |
| footer | `Save statement` (`stmt`, the existing action) |
| footnote | `st.Caveat()` when `!IsTrustworthy()`, `Clip(..., 52)`, `SSR_C_HOLD` |

**Two semantics that must not be flattened — both runners-up insist, and they are right.**

[CONFIRMED FROM CODE] `SSR_Statistics.mqh:526-530`:

```
      //--- profit factor is undefined without a loss; reporting it as
      //--- infinity or as the gross profit both mislead, so it stays 0
      //--- and the caller reads trades/losses to know why
      if(out.gross_loss > 0.0)
         out.profit_factor = out.gross_profit / out.gross_loss;
```

**Draw `-`, never `0.00`, when `losses == 0`.** `trading-analytics-6` (CONFIRMED, LOW) shows the
0.00 lie already propagating through the KPI grid, the by-setup table, the CSV header and
`Summary()`. A sheet that tells a flawless trainee their profit factor is zero is worse than the
telemetry it replaced.

[CONFIRMED FROM CODE] `average_r` is computed only over trades with `risk_at_entry > 0`
(`SSR_Statistics.mqh:532-536`, `if(out.r_trades > 0)`), which is why `r_trades` exists. **Always
print the R sample as "a of b".** "+0.31 R" drawn from three of nineteen trades is the exact harm the
trust caveat exists to prevent, and it is a harm a coach repeats out loud.

[CONFIRMED FROM CODE] `IsTrustworthy()` = `trades > 0 && ambiguous_pct <= 10`, and `Caveat()` builds
the sentence. Put the caveat on this sheet, not only in the HTML.

**Removed:** the Stats sheet's `st1`/`st2`/`st3` — balance, equity, floating — which duplicate
`stbal` and `stflt` in the status strip 200 px below; and `st7`, the pointer reading *"see the Prop
tab"*, because the Eval cell is now permanently in the rail. **Moved to SESSION:** `st4`/`st5`/`st6`
(bars, ticks, rejected, guard violations) — they describe what the *machine* did, not what the
*trainee* did. [CONFIRMED FROM CODE] `core-engine-5` (CONFIRMED, MEDIUM) adds a reason to move them
rather than merely re-home them: `bars_consumed` counts a bar once per pump that touches it, so the
figure is wrong by 10-1500×, and it must not sit beside trading measures where it reads as one.

**What this does not fix:** `ui-dialogs-4` (CONFIRMED, MEDIUM) — two review *observation* sentences
exceed 63 characters for every possible value, and the ambiguous-bar line renders as *"…reached both
the stop and the t"*, losing the single most important caveat this product reports about a fill.
Observations live in `SSR_Review.mqh` `StringFormat` literals, outside `T()`. They need their own fix
and should get it whether or not this proposal lands.

**Cost, honestly:** ~80 lines of sheet + `ListRO` + one throttle and one cached struct in
`CSSRGroupPort`. Not the "zero" the winner booked, but far less than the runners-up's twelve new wire
fields — because the generator is reused whole and the struct is cached rather than flattened onto
the wire.

#### M.4.4 SESSION — *what the machine is doing, and where I can go*

[CONFIRMED FROM CODE] The current Session sheet is a junk drawer: three diagnostics plus **four
keyboard hint lines**, three of them factually wrong (`ui-plumbing-2`, CONFIRMED — `keys.2` says
"R reset" while `R` is `SSR_CMD_LINES_TOGGLE` (`SSR_Keys.mqh:162`) and reset is `0` (`:200`); `keys.4`
still teaches the `[]` caption button deleted in v125 at `SSR_Panel.mqh:934`).

**Removed:** all four hint lines (`ses4`, `keyhint`, `ses5`, `ses6`, i.e. `SSR_S_KEYS_1..4`). They move
to KEYS, where they are *generated* rather than written by hand, and the four catalogue strings retire
with them. This frees 72 px.

| Group | rows | source | new? |
|---|---|---|---|
| **Where** | `[ Jump… ]` `[ Sessions… ]` `[ Mark here ]` | `SSR_CMD_JUMP`, `SSR_CMD_SESSIONS`, `SSR_CMD_BOOKMARK` | restored affordance |
| | bookmarks | `bookmarks` | exists |
| | `[ Save position ]` `[ Resume position ]` + checkpoints | `has_saved_position`, `checkpoints` | **new** |
| **This run** | bars / ticks / rejected / guard | moved from Stats | moved |
| | pump p95, µs/tick, gated on `perf_calibrated` | `pump_p95_ms`, `us_per_tick` | **new** |
| **This session** | streams / skew | exists | — |
| | charts: `leak_clean` / `leak_advice`, `Clip(..., 52)` | exists | — |
| | **charts adrift** | `charts_detached` + `F` | **new** |
| | strategies | `strategy_text`, `Clip(..., 52)` | **new** |

[CONFIRMED FROM CODE] **Eleven wire fields the panel never draws.** A grep for `m_state.<field>` over
`SSR_Panel.mqh` returns 0 for `strategy_text`, `pending_count`, `checkpoints`, `has_saved_position`,
`perf_calibrated`, `us_per_tick`, `pump_p95_ms`, `charts_detached`, `stop_points`, `tp_points`,
`prop_floor` — while `CSSRGroupPort` fills every one (`SSR_GroupPort.mqh:122, 123, 132-134, 147, 148,
214, 243, 372, 395`). **That is the cheapest new information in the product**: no port change, no
engine change, no new observer. `ui-port-session.md` §2.2 lists them as orphans; this is where they
stop being orphans. (`stop_points` and `tp_points` stay deliberately undrawn — a stop in points is
the thing the lines design replaced.)

**Save / Resume get a surface for the first time [CONFIRMED FROM CODE, graft agreed by both
runners-up].** `CSSRGroupPort::SavePosition` and `ResumePosition` are real implemented overrides:

```
SSR_GroupPort.mqh:495    virtual bool SavePosition(void) override
SSR_GroupPort.mqh:506    virtual bool ResumePosition(void) override
```

and a grep over `MQL5/` outside `Tests/` and `QA/` finds **no UI caller** — no panel button, no
`Dispatch` arm, no key in `SSRKeyBindings()`, no palette entry. The host calls the controller
directly (`SSReplayStandalone.mq5:2145: g_ctrl.SavePosition();`). The wire already carries
`has_saved_position` and `checkpoints`. **Two buttons and two `Dispatch` arms** turn two orphan
fields from visible into operable.

> [POTENTIAL_RISK — carried verbatim from user-first] **Neither verb has ever been exercised from a
> UI, and nothing in this audit has run on a terminal.** `ResumePosition` calls
> `m_group.SeekAllTo(c.Now())` (`:512`) across every stream. Ship the buttons behind the same
> confirmation discipline as Reset, and treat the first terminal run as the test.

**The bookmark list is staged, not shipped.** [CONFIRMED FROM CODE] the port has no verb for "list
bookmarks" or "go to bookmark i" — `Bookmark(label)` writes one (`SSR_GroupPort.mqh:490`, which also
draws the chart mark via `MarkTime`). That needs two new port verbs and wire rows for the labels.
Ship the count and the two buttons first. [FUTURE FEATURE] the list.

**Gate — and it is not optional.** [CONFIRMED FROM CODE] `host-expert-7` (CONFIRMED, MEDIUM): keys
are not withheld while the Sessions or Jump dialog is open, so **Space starts the replay, `Tab`
opens a virtual trade and `0` arms the session reset while the trainee reads a modal**, and the
panel's `Render()` then repaints over it. Promoting `Jump…` and `Sessions…` to a destination makes
those two dialogs the *normal* way into this moment rather than a key nobody presses, which
multiplies the exposure. `CSSRReviewCard::OnKey` already shows the fix — it returns `true` for every
key while up. Copy it before these buttons ship.

#### M.4.5 KEYS — *how to drive it*

This is why constraints-first won. [CONFIRMED FROM CODE] the guard at `SSReplayStandalone.mq5:1736`
is

```
   if(InpFirstCard && !one_chart_ok && g_panel_chart != 0)
```

so in the default configuration the first-run card shows on **neither** pass of the one-window
handover (`host-expert-4`, CONFIRMED); and where the guard does let it through, `Show()` reports
success without checking its fixed `y = 376..480` fits the chart, so on a short chart it is drawn
off-screen, `seen.txt` is written anyway, and the product's only onboarding is consumed unread
(`ui-dialogs-14`, CONFIRMED). The only key list is `CSSRKeyCard` on `H`, and the only string that
teaches `H` is on the card that never shows. **A trainee in the default configuration is never told a
single key.** No other failure in this document precedes that one.

[CONFIRMED FROM CODE] `SSRKeyBindings()` (`SSR_Keys.mqh:125-218`) is 22 bindings, all 22 vk values
distinct, 18 marked `listed`, and the key card's height is *counted from the table* rather than
chosen. L.7 is right that this is the strongest piece of UI engineering in the product. **Extend it;
do not replace it.**

| region | content |
|---|---|
| header | `All virtual — nothing reaches a broker.` (`SSR_S_ALL_VIRTUAL`) |
| rows | 9 per page (Standard) / **all 18** (Expanded), `label` at `x+0`, `what` at `x+74`, `Clip` 16 / 36, drawn with **`ListRO`** |
| pager | `<` `>` + `"%d-%d of 18"` |

**What this destination fixes at once:**

* `ui-panel-12` (CONFIRMED, MEDIUM) — ~41 deletes + 41 creates + ~450 writes **per frame** become
  ~20 objects drawn once per navigation.
* `host-expert-4` + `ui-dialogs-14` — a permanently visible rail cell is a discovery path that
  cannot be missed and cannot be consumed unseen.
* `ui-plumbing-1` (CONFIRMED, MEDIUM) — the card's row text is English literals inside
  `SSRKeyBindings()`, making it the one user-facing surface outside `T()`. Moving the rows into a
  sheet is the moment to add `ENUM_SSR_STR` ids for the 18 `what` strings: 18 catalogue entries + 18
  `fa.txt` rows, catalogue 190 → 208.
* `ui-plumbing-15` (CONFIRMED, LOW) — `Ctrl+K` is not in the key table, so `SSRKeyToCommand(75)`
  returns `SSR_CMD_NONE` and the generated list cannot mention the palette. Add the binding with
  `listed = true`; the destination then teaches the one feature a code comment at `:929` wrongly
  records as lost.
* `ui-plumbing-3` (CONFIRMED, LOW) — `SSRKeyHint()` is a third hand-written list, also saying "R
  reset". Generate it from `SSRKeyBindings()`. **Then the product ships one key list instead of
  four**, and A22's sibling audit can assert that no drawn string names a key letter the table does
  not bind.

**Removed: `CSSRFirstRun` entirely** (`SSR_FirstRun.mqh`, 148 lines, prefix `SSRF_`, plus its
`seen.txt`). [RECOMMENDATION] Replace it with **one branch in `RestorePlace()`**. The branch is
already there, waiting (`SSR_Panel.mqh:555-557`):

```
      m_place_loaded = true;
      if(!FileIsExist(SSR_PANEL_FILE))
         return false;
```

**No `panel.ini` → the opening destination is KEYS.** One `if`, no new class, no new file, no fixed
coordinate to be wrong about, and it cannot be consumed unseen because the rail cell stays there
afterwards.

#### M.4.6 EVAL — *whether I am passing*

Reuses `SheetProp` (`:1749`) **unchanged in structure**. It is correct: four meters, every meter with
its number beside it, the sheet computes nothing, and the reasoning is written down.

Three small changes only:
* `pp_rules` is clipped at 62 (`:1760`); at 237 px the real budget is **52**.
* `pp_head` is clipped at 44 (`:1840`); keep.
* **new:** one row for `DailyRoomAfter()` in money (M.4.1's accessor, second reader).

**New in Expanded: nothing.** The sheet's worst case is a finished run with a deadline at 178 of
186 px (`:1765-1775`); Expanded gives it 140 px more and it should stay **empty**. A fifth meter for
a rule most challenges do not set would teach nobody what it counts — the sheet says exactly that
about the deadline. Whitespace is the premium choice here, and it is free.

---

### M.5 Mapping onto what exists

| Proposed | Existing class / function | Reused | New | Removed |
|---|---|---|---|---|
| chrome: caption | `DrawCaption:833` | all | — | chip origin `x+140` → `x+134`; the three per-frame `Remove` at `:932-934` become a one-shot sweep |
| chrome: clock | `DrawClock:945` | all | — | — |
| chrome: transport | `DrawTransport:975` | all | — | — |
| chrome: speed | `DrawSpeed:1045` | all | 10 drawn cells over 20 stops | `spdseg10..19` **removed once** in `Create()`, not left to `HideBody`'s Hide loop |
| chrome: actions | `DrawActions:1235` | all | — | per-frame `Remove` at `:1189-1191`, `:1241-1243` → one-shot sweep |
| chrome: status | `DrawStatus:1915` | ladder + 4 slots | `charts_detached` readout (slot 53); optional `stmsg` id for ladder warnings | **`stfid`** (`ui-panel-6`) |
| rail | `DrawRail:1209` | all | 6th cell; condition mark **inside `TabName()`** | — |
| swap | `DrawSheet:1268` | the dispatch switch | **transition latch** | unconditional `HideSheets()` |
| TRADE | `SheetTrade:1346` | ~all | verdict line; `order_why` own id; `DailyRoomAfter` row | slot-17-over-slot-12 collision |
| POSITIONS | `SheetPositions:1509` | ~all, `PosCap()`, `PosGroupH()`, `StepTrail()`, the `p{x\|h\|b}<digits>` arms | re-derived columns; `!` note prefix; Open/Closed toggle; `WantClosed(bool)` on `CSSRGroupPort` | `H`/`B`/`X` letter captions |
| PERFORMANCE | `SSRReviewRows` (`SSR_Review.mqh:104`) + new `ListRO` | the generator verbatim, `stmt` | curated page 1; pager; group header; throttled `SSRStatistics` cached in `CSSRGroupPort` | `SheetStats` `st1 st2 st3 st7` |
| SESSION | `SheetSession:1877` | `ses1 ses2 ses3` | 9 rows from orphan wire fields; Jump / Sessions / Mark buttons; Save / Resume buttons + 2 `Dispatch` arms | `ses4 keyhint ses5 ses6` and `SSR_S_KEYS_1..4` |
| KEYS | `SSRKeyBindings` (`SSR_Keys.mqh:125`) | the table verbatim | sheet renderer, pager, 18 `T()` ids, `Ctrl+K` binding, generated `SSRKeyHint()` | **`CSSRKeyCard`** (132 lines, prefix `SSRK_`) |
| EVAL | `SheetProp:1749` | all | `DailyRoomAfter` row; `DailyRoomAfter()` accessor on `CSSRPropEvaluation` + 1 pre-clamped wire field | — |
| onboarding | `RestorePlace:553` | the existing `FileIsExist` branch at `:556` | one `if`: no ini → KEYS | **`CSSRFirstRun`** (148 lines, `SSRF_`, `seen.txt`) |
| teardown | `HideSheets:1284`, `HideSheetArea:2042`, `HideBody:2077` | the *idea* of I7 | one list per destination + `UpgradeSweep()` | three drifting lists, `spreadrow`/`traderr` duplicates, dead `g3_*`/`pp_g`, missing `tab4` |
| clipping | `Clip:242` | verbatim | R5 budgets at every sheet site + audit A22 | — |

**Untouched, deliberately** — every item of L.10 survives: latch polling as the one click mechanism
(`PollClicks:2445`, palette polled first and alone, 200 ms debounce); the `tabN` dispatch parse; the
single generated key table; `TabCount()` as a question and the re-clamp at `:745`; the status
ladder's priority order and its rationale; "removed, not merely undrawn" (I7); modes as chips;
operated-vs-consulted; the wish/fact split for tall mode with both numbers named; the `Clip`/63-char
discipline; `SheetProp` computing nothing; and the two compile-time switches (`SSR_LAYOUT_RAIL`,
`SSR_THEME_*`) that let one commented line undo a large change on a terminal the author cannot run.

**Terminology preserved.** Sheet, rail, chip, ladder, latch, wish/fact, operated vs consulted, Trade
/ Positions / Performance / Session / Keys / Evaluation. The only new word is **destination**, and it
renames nothing — it is what the code already calls a tab plus the sheet behind it. *(Coach-first's
wholesale rename and reorder — Trade→RISK, Positions→OPEN, Prop→CHALL — is rejected as catalogue
churn in two languages that changes nothing a trainee reads. REVIEW→Performance is the one rename
that earns itself, and it is the name the brief already uses.)*

---

### M.6 Compact / Standard / Expanded

[CONFIRMED FROM CODE] The product's existing mode flags map onto the brief's three words exactly and
should not be renamed. `SSR_Panel.mqh:676-714`: `m_compact` is **measured**
(`m_compact = (chart_h > 0 && chart_h < SSR_PANEL_H + 24)`, i.e. < 360 px) and never user-chosen;
`m_tall` is a **wish** (`P`, persisted) whose **fact** is recomputed every frame against
`SSR_PANEL_TALL_H + 24` = 500 px, with the refusal surfaced on the status strip and both numbers
named.

| | Compact | Standard | Expanded |
|---|---|---|---|
| trigger | chart < 360 px, measured | default | `P` **and** chart ≥ 500 px |
| `BodyH()` | 128 | 336 | 476 |
| sheet | **none** | 186 px | 326 px |
| rail | **none** | 6 cells, 147 px | 6 cells, 147 px (identical) |
| chrome | caption, clock, transport, speed, status | same | same |
| TRADE | — | verdict + 11 rows | + strategy line + spare |
| POSITIONS | — | `PosCap() = 5`, Open/Closed | `PosCap() = 12` (existing, `:432`) |
| PERFORMANCE | — | curated page + 5 paged | curated page + 3 paged (17/page) |
| SESSION | — | 7 rows + 1 Group | 12 rows + 2 Groups |
| KEYS | — | 9 rows/page, 2 pages | **all 18, no pager** |
| EVAL | — | 4 meters + allowance, 178 of 186 px | same; 140 px left empty |
| condition marks | not drawn (no rail) | in the cell text | in the cell text |
| destination memory | remembered, not drawn | — | — |

**The rail is deliberately mode-independent.** Six cells fit in 186 and in 326, so the selector's
geometry never changes with height. That is robustness, not taste: a rail whose cell count varied
with mode would need `PosCap()`-style arithmetic in the one control the user must always be able to
hit.

**Compact is where this proposal fixes the most.** [CONFIRMED FROM CODE] `ui-panel-3` (CONFIRMED,
**HIGH**): `HideSheetArea(true)` at `:682` is undone by `HideBody(false)` at `:729` **inside the same
`Render()`**, so on a chart that shrinks below 360 px the rail, the `tabline` and the three action
buttons stay visible at full-layout coordinates — up to 122 px of still-clickable buttons painted on
the candles below a 128 px panel. `ui-panel-4` (CONFIRMED, MEDIUM) adds that `HideSheetArea`'s list
stops at `tab3`, stranding the fifth cell even after that is fixed — and the proposed rail has a
sixth.

Under R1 both disappear structurally: `HideBody` and the destination teardown are **transition
functions**, so nothing undoes anything inside one frame, and the teardown list is generated from the
same place that creates the ids, so `tab4`/`tab5` cannot be forgotten.

`ui-panel-10` (CONFIRMED, MEDIUM) also resolves: in Compact the fill toast is placed at
`y + 128 - 18 - 24 = y+86`, directly on the speed row (`y+82..y+101`) and above it in creation order,
for four seconds per fill — in the mode where the speed control is one of only four things left.
[RECOMMENDATION] in Compact the toast **replaces the status strip line** rather than floating above
it: same information, zero occlusion, and the strip is the lowest-priority band by the ladder's own
ordering.

**Compact has no navigation, and this proposal does not give it any.** That is a deliberate,
named loss. The alternative on offer — promoting status-strip labels to buttons — is rejected at
M.3.7 for reasons 1-4 there, the second of which is that it would not work in Compact anyway
(`if(!m_compact)` guards `DrawRail` and `DrawSheet` together at `:740-752`). [RECOMMENDATION] the
honest Compact answer is the **command palette**, which already works in every mode, is one `Edit`
plus eight rows, and reaches all 31 commands — and which the KEYS destination will finally teach,
once `Ctrl+K` is in the key table (`ui-plumbing-15`).

**Closed and Collapsed are not modes of this architecture; they are states of the frame.** Both are
preserved verbatim, including the `reopen` button and its rationale (*"a control that removes its own
only way back is a trap"*, `:641-647`). [CONFIRMED FROM CODE] one correction: the `m_closed` branch at
`:649-655` returns **before** `ClampToChart` at `:716`, so a chart resized while closed can strand
the 76×20 `reopen` button off-screen with no recovery short of reattaching the EA. Clamp before the
early return.

---

### M.7 Slot and id budget

[CONFIRMED FROM CODE] The label cache is 128 entries (`SSR_SLOTS 128`, `SSR_Panel.mqh:51`) and is
**global across sheets** — slots 30/31/32 are already shared by two different ids (Positions vs
Stats), safe only because the two sheets are mutually exclusive *and* their texts always differ.
Slot 12 and slot 17 sharing one object is how `ui-panel-5` happened. **Every new row takes its slot
from a checked list, never from a guess.**

Enumerating every literal `Text(<n>,` in `SSR_Panel.mqh` plus the three dynamic families:

```
USED   0-6   10-20   30-36   40-46   50-55   60-61   70-71
       80+r  (pr<r>)   92+r (pl<r>)   104+r (pn<r>)   r < SSR_POS_MAX 12
       -> 80..91, 92..103, 104..115
FREE   7-9   21-29   37-39   47-49   56-59   62-69*  72-79   116-127
```

*62-69 are consumed at runtime by `PropRow`'s (slot, slot+1) pairs — treat them as **taken**.
Verified free and safe to assign: **7-9, 21-29, 37-39, 47-49, 56-59, 72-79, 116-127** — 44 slots.

Assignments made by this proposal:

| slot | id | destination |
|---|---|---|
| 22 | `verdict` | TRADE |
| 23 | `alwrow` | TRADE (`DailyRoomAfter`) |
| 53 | `chartsn` | status strip (freed by deleting `stfid`) |
| 24-29 | SESSION's six new rows | SESSION |
| 37-39, 47-49 | PERFORMANCE curated page | PERFORMANCE |
| 116-127 | paged rows (`ListRO` caches its own) | PERFORMANCE / KEYS |
| — | `stmsg` (optional, M.3.7) | status strip |

**The rail condition marks consume no slot**, because they are text inside `TabName()` and `ButtonC`
has its own widget cache (M.3.4). That is the single largest reason to prefer that mechanism.

---

### M.8 The cost ledger, and the build order

#### M.8.1 Per change

| # | Change | ~lines | Risk | Fixes | Cost if wrong |
|---|---|---|---|---|---|
| 1 | Transition latch: `HideSheets`/`HideBody` on change only | 40 | **high** — it inverts when teardown happens | `ui-panel-1`, `ui-panel-2`, `ui-panel-3` | a stale object from the previous destination, permanently on the chart (I7). **Must land with #2 and #3** |
| 2 | Destination register: one id list per destination | 150 | medium | `ui-panel-4`, list drift | as #1 |
| 3 | `order_why` its own object id | 5 | low | `ui-panel-5` | **must land with #1** — see R1's coupling warning |
| 4 | `UpgradeSweep()`: one-shot Remove of the nine v124 ids + `spdseg10..19` | 20 | low | nine wasted `Remove` per frame; orphan speed cells on upgrade | an orphan object survives one more build |
| 5 | Status strip: drop `stfid`, add `charts_detached` | 25 | low | `ui-panel-6`, `chart-10` (UI half) | fidelity signal lives only in the caption chip |
| 6 | Position-row columns re-derived for 245 px, `!` note prefix | 30 | low | `ui-panel-7` | pure arithmetic; `CheckFrame` sees only the buttons |
| 7 | R5: character budgets + `Clip()` at every sheet site | ~200 mechanical | low | `ui-panel-8` and L.9's label class | a `~` where a designer wanted a word |
| 8 | 10 drawn speed cells over 20 stops | 20 | low | the 6.5 px target | a speed reached by `+`/`-` instead of one click |
| 9 | Rail 5 → 6; `SSR_TAB_COUNT` 4→5, `SSR_TAB_MAX` 5→6, `SSR_TAB_PROP` 4→5 | 30 + 4 strings | low | — | an old `panel.ini` selects the wrong destination once (M.3.3) |
| 10 | KEYS destination + `ListRO`; delete `CSSRKeyCard` | +160 / −132 | medium | `ui-panel-12`, `ui-plumbing-1`, `ui-plumbing-3`, `ui-plumbing-15`, `ui-dialogs-16` | the key list is no longer visible *while* on another destination |
| 11 | Delete `CSSRFirstRun`; no ini → KEYS | +3 / −148 | low | `ui-dialogs-14`, `host-expert-4` (surface half) | onboarding is quieter: a cell, not an announcement |
| 12 | Rail condition marks inside `TabName()` | 25 | low | notice-without-navigation | one bit of selection contrast on an alarmed cell (M.3.4) |
| 13 | PERFORMANCE: curated page + pager + throttled `SSRStatistics` in `CSSRGroupPort` | 110 | medium | L.2.2's thin Stats sheet; `trading-analytics-6` on this surface | a ≤2 s lag, disclosed on the sheet |
| 14 | TRADE verdict line + `DailyRoomAfter()` accessor + 1 wire field | 40 | low | the four-numbers-in-four-places read | one more number to keep pre-clamped at its owner |
| 15 | SESSION rehome + 9 orphan fields + Jump/Sessions/Mark + Save/Resume | 70 + 8 strings | medium | L.2.3, 9 of 11 orphans | two verbs exercised from a UI for the first time ever |
| 16 | POSITIONS Closed page + `WantClosed(bool)` | 90 | medium | the unreachable individual trade | an O(`Total()`) walk if the gate is wrong |
| 17 | Audit A22 (clip discipline) + generated `SSRKeyHint()` | 60 (Python + MQL5) | low | `ui-plumbing-3`, and it is the only instrument that can see I10's blind spot | — |
| | **total** | **≈ +1,000 / −290 in one file, two classes deleted** | | | |

#### M.8.2 The build order, and the gate

1. **#1 + #2 + #3 together.** They are one change. Nothing else in this document is worth doing on a
   panel that spends its whole paint budget rebuilding itself, and #3 cannot be deferred past #1
   without turning a one-frame defect into a permanent one.
2. **#4, #5, #6, #7, #8.** Pure arithmetic, clipping and sweeps. Visible on every frame of every
   session, cheap, independently testable, and they touch navigation not at all.
3. **#9 + #10 + #11.** The rail grows, two classes die, and the trainee is finally told a key. This
   is the point of no return for the `panel.ini` contract.
4. **#12.** Condition marks — after R1, never before (`ui-panel-3`).
5. **#13 + #14 + #15 + #16.** The four destinations that add information.
6. **#17.** Instrumentation last, because A22 must be written against the finished call sites.

**Two CONFIRMED defects outside every proposal gate the SESSION moment**, and nothing that adds a
clickable control ships before them:

* **`ui-dialogs-1` (CONFIRMED, HIGH)** — `ReadAll()` wipes `session_name` and `extra_tfs` whenever it
  runs on a step with no edit boxes (`SSR_SetupPanel.mqh:300`), so sessions are never written and
  cannot be resumed. Promoting `Sessions…` to a destination points a permanent control at a list
  that is empty for a reason nobody can see from the panel.
* **`host-expert-7` (CONFIRMED, MEDIUM)** — keys are not withheld while a modal dialog is open.
  `CSSRReviewCard::OnKey` already shows the fix. This gates **every** new clickable control in this
  document, not only SESSION's.

---

### M.9 Visual direction, in tokens that already exist

Dark, premium, minimal, professional, dense, hierarchical — `SSR_THEME_RAIL` is already all of those,
and the failure in L.9 is arithmetic, not colour. **No new colour tokens are proposed.** The palette
has 51 `SSR_C_*` tokens, each defined identically in all three palettes, and adding one means adding
three and a contrast-table line.

| Instrument | Tokens | Rule |
|---|---|---|
| three surfaces | `SSR_C_PANEL`, `SSR_C_HEADER`, `SSR_C_WELL` | a **value** sits in a well; a **band** sits on the header; everything else sits on the panel. Already how `spdbox` works (`:1063`) |
| one hairline | `SSR_C_GROUP_EDGE` / `SSR_C_TAB_EDGE` | 1 px, used by `Group` and `tabline`. Never two adjacent, never decorative |
| three text weights | `SSR_C_TEXT`, `_TEXT_DIM`, `_TEXT_FAINT` | measurement / label / provenance. The build tag is FAINT; that is the correct use |
| one primary | `SSR_C_PRIMARY` + `_EDGE` + `_TEXT` | **exactly one primary control per band.** Today: `toggle` in transport, `BUY`/`SELL` on TRADE. Nothing else may be blue |
| semantic four | `SSR_C_RUN`, `HOLD`, `STOP`, `IDLE` | state only, never decoration, and **never alone** — the rail mark is `!` first and coloured second, by `:858-862` |
| deal pair | `SSR_C_BUY`, `SSR_C_SELL` + edges | the trade pair only |
| four type sizes | `SSR_FS_CLOCK 13`, `TITLE 9`, `BODY 8`, `SMALL 7`, one face | 13 for the clock alone; 9 for identity and the primary; 8 for rows; 7 for provenance. **Do not add a fifth** |

[CONFIRMED FROM CODE] Two tokens are declared in all three palettes and drawn by nothing —
`SSR_C_THUMB_EDGE` and `SSR_C_TICK` (`ui-plumbing-9`, CONFIRMED, LOW). Spend them on the speed
groove's thumb and tick marks under M.1.6 rather than deleting them; the slider gets its outline back
at zero cost to the palette.

What the constraints forbid, which happens to match the brief: **no gradients** (MQL5 fills a
rectangle with one colour), **no glow** (no alpha, no blur), **no rounded corners** (`BORDER_FLAT` is
what `Rect` writes at `SSR_Widgets.mqh:216`), **no icons** (a glyph is a font the user may not have;
the product deliberately uses one face). Restraint here is not taste — it is the only thing that can
be drawn.

The one genuinely premium move available: **`Clip()` everywhere, and whitespace where there is
nothing to say.** A panel whose every row ends where it means to, on a terminal that will never warn
you, is the whole difference between this product and a mockup.

---

### M.10 What this architecture refuses to do, and what it does not fix

**Refuses:**

* It will not put an operated control behind a click. No HOME, no REPLAY destination.
* It will not add a destination without data. SETTINGS and JOURNAL are rejected on that ground, and
  JOURNAL names its exact blockers (`Line(index)` is O(n); `ui-port-session-2` and `-3`, both
  CONFIRMED HIGH, for persistence; an unsettled mouse question for a typed note).
* It will not add a seventh rail cell, even though seven fit. The spare cell is the budget for
  whatever the product learns next.
* It will not invent a control MQL5 cannot draw. No combo, no scrollbar, no tree, no tooltip, no
  modal shade, no drag.
* It will not draw an object on top of a navigation cell (M.3.4).
* It will not rename a sound term.
* It will not claim a runtime behaviour.

**Does not fix, and says so:**

* **L.4.2 is still unsettled**, and the code disagrees with itself about it. `ui-panel.md` §11/I1
  records that `g_panel_chart == ChartID()` (`SSReplayStandalone.mq5:1463`) so key and mouse events
  *do* reach the panel as wired, while the panel's own comments repeatedly state it "never receives a
  mouse coordinate" (`SSR_Panel.mqh:929`, `SSR_Widgets.mqh:437-443`). This audit's ground truth takes
  the pessimistic side. Everything above is designed to be correct there: no drag, no hover, no focus,
  no thumb. If mouse events do arrive, all of it still works and the drag is a bonus.
* **`ui-panel-11` remains POTENTIAL_RISK, not a defect** — the tag box hidden and re-shown 10×/s
  while it may hold the keyboard. R1 is its **strongest available mitigation**: under the transition
  latch the box is not touched on a still frame at all. But `m_tag_focus` is assigned only inside the
  mouse-move handler (`:2903-2907`), so in the pessimistic branch the typed setup tag has no focus
  path and the **setup-tag fallback is the correct contingency**. Nothing here closes it.
* **`ui-dialogs-4` (CONFIRMED, MEDIUM)** — two review observation sentences exceed 63 characters for
  every possible value. Outside `T()`, outside this document, and it should be fixed anyway.
* **`chart-7` (CONFIRMED, MEDIUM)** — `LeakGuard::Advice` is written far longer than the ~49
  characters its only consumer can display. `Clip()` makes the cut honest; shortening the advice at
  source makes it useful. Fix both.
* **`chart-12` (CONFIRMED, LOW)** — every word the chart layer draws (`"STOP - drag me"`, `BUY`/
  `SELL`/`SL`/`TP`, closed-trade captions) is an English literal outside `T()`. A Persian user gets
  English labels on the only objects they are asked to drag.
* **`core-engine-5` (CONFIRMED, MEDIUM)** — `bars_consumed` is wrong by 10-1500×. SESSION draws it;
  SESSION does not fix it, and the row must not be read as a trading measure.
* **`CSSRAutoPause` is [FUTURE FEATURE].** Coach-first is right that it is the missing coaching
  instrument, and right about why it cannot ship: the action strip is three 96 px cells in 310 px
  (`bw = (310-16-6)/3`) and there is no fourth.
* **`ui-plumbing-10` is NOT_A_BUG** in `verified.json`. No part of this architecture acts on it, and
  the transport's 91 px primary against 24 px steps is preserved exactly as it is.
* **Nothing here has been run on MT5.** Every pixel number is derived from a constant or a literal in
  the source; every px/char figure is an estimate MQL5 will not confirm; `CheckFrame()` can only ever
  see sized objects, never labels (I10). The rail's Persian names remain a POTENTIAL_RISK that no
  amount of source reading can close.

---

### M.11 Where the three proposals disagreed, and how each was settled

| Question | Settled | Why |
|---|---|---|
| Rail condition signal: separate glyph objects, or text in the cell? | **text inside `TabName()`** | coach-first's intent is non-negotiable; its mechanism draws an object over the one control the user must be able to hit, and `SSR_Widgets.mqh:455-458` records that exact swallow. Zero objects, zero slots, inherits the `:1222-1224` sweep |
| Status strip as navigation? | **rejected** | four cited reasons at M.3.7; the strongest is that ladder levels 1-4 write slot 50 / `stbal` (`:1929, 1947, 1988, 2001`), so the product's one destructive question would sit on a button that navigates. The compact-navigation need it raised is real and is answered by the palette instead |
| Closed trades on POSITIONS or in JRNL? | **POSITIONS** | JRNL is rejected as a v1 destination on four independent grounds (M.3.2). The `WantClosed(bool)` gate both proposals demanded travels with it |
| PERFORMANCE "zero new statistics code"? | **corrected** | `SSRReviewRows` needs an `SSRStatistics` and no such struct exists in the port or panel. Throttle on `ClosedCount()` change or 2000 ms, cache one struct in `CSSRGroupPort` (`m_stats`/`AttachStats` already exist), disclose the ≤2 s lag |
| `risk_money` / `reward_money` as new TRADE rows? | **struck** | already drawn at `:1410` and `:1414`. Slot 20 is `posempty`, not free |
| Speed cells: rely on `HideBody`'s sweep? | **corrected** | that loop Hides, it does not Remove (`:2093-2094`). One-shot `Remove` in `Create()`, folded with the nine v124 per-frame `Remove` calls into one `UpgradeSweep()` |
| Rail rename and reorder? | **rejected** | catalogue churn in two languages against the preserve-terminology rule; and a conditional destination at an interior index silently deletes every cell after it, because `TabCount()` can only hide the final cell |
| New caption chips (TRUST, detached, skew)? | **none in v1** | the chip row already overruns by 6 px (`ui-panel-13`). `charts_detached` takes the status slot freed by deleting `stfid`; the caveat goes on the PERFORMANCE sheet. user-first's payment rule (drop PROP when the Eval cell is visible) is recorded for whoever adds the next chip |

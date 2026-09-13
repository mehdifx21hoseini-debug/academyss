## M. A PREMIUM INFORMATION ARCHITECTURE, DERIVED FROM THE CONSTRAINTS

*Angle: constraints-first. Nothing below is proposed because it would look good in a mockup.
Every destination, every row and every control in this document is chosen because the MQL5
object model can draw it cheaply and answer a click on it reliably on a chart the program may
not own. Where two arrangements are equally expressive, the one that writes fewer object
properties per frame wins. Build v125, `SSR_LAYOUT_RAIL` and `SSR_THEME_RAIL` active.*

*This proposal assumes the pessimistic branch of L.4.2 — **no mouse coordinates ever arrive**.
That is deliberate. An architecture that is correct without the mouse is correct with it; the
reverse is not true, and L.4.2 cannot be settled without a terminal the author does not have.*

---

### M.0 Summary of the position

The brief proposes HOME / REPLAY / TRADE / POSITIONS / PERFORMANCE / CHALLENGE / JOURNAL /
SETTINGS. **Two of those eight cannot be drawn at all in the shipping layout, three have no data
behind them, and two are already permanently on screen as chrome.** The measured constraint that
kills the eight-destination model is arithmetic, not taste:

[CONFIRMED FROM CODE] `DrawRail` (`SSR_Panel.mqh:1209-1225`) draws cells of `h = 22` with
`gp = 3`, so `n` destinations need `25n - 3` px. `SSR_SHEET_H` is `186` (`SSR_Theme.mqh`).

```
n = 5   122 px    ships today
n = 6   147 px    fits, 39 px spare
n = 7   172 px    fits, 14 px spare        <-- the ceiling in Standard
n = 8   197 px    DOES NOT FIT             <-- the brief's model
```

The horizontal fallback is no better: `DrawTabs` (`:1145`) uses `tw = (W - 2*SSR_PAD - (n-1)*2)/n`,
which at `W = 310` and `n = 8` gives **35 px per tab** — about seven characters of Tahoma 8 pt,
for names that must also survive Persian (`rtab.prop = ارزیابی`, 7 glyphs). MQL5 centres button
text, does not clip it, and has no bidi.

So the ceiling is seven, and the honest answer is **six destinations, one of them conditional**,
with one cell of headroom deliberately left unspent.

The proposal's real content is not the destination list. It is three structural rules that make
navigation nearly free, and they are worth more than any rearrangement of tabs:

1. **Navigation is the only thing allowed to delete.** Today the panel tears down and rebuilds
   its entire sheet ten times a second (`ui-panel-1`, CONFIRMED HIGH) and invalidates the property
   cache for ~44 sized objects on every frame (`ui-panel-2`, CONFIRMED HIGH). Between them they
   restore the full 561-write repaint that the 512-slot cache was built to eliminate.
2. **An overlay costs a rebuild per frame; a destination costs a rebuild per click.** Creation
   order is the only z-order, so anything drawn over a panel that repaints at 10 fps must be
   redrawn at 10 fps. The key card does exactly that, destructively (`ui-panel-12`, CONFIRMED).
3. **Every destination owns its own teardown list.** Three hand-kept hide/remove lists exist and
   they disagree (`ui-panel-4`, CONFIRMED; `ui-panel.md` §6).

Fix those three and the panel gets a new information architecture almost as a side effect,
because destinations stop being expensive.

---

### M.1 The constraint set, priced

#### M.1.1 What input exists

[CONFIRMED FROM CODE] The only input the drawn surface can rely on is a **latched button**.
`CSSRWidgets::Pressed` (`SSR_Widgets.mqh:337-347`) reads `OBJPROP_STATE` and clears it;
`CSSRPanel::PollClicks` (`SSR_Panel.mqh:2445`) walks `ObjectsTotal(m_chart,-1,OBJ_BUTTON)`
backwards, clears the latch **before** acting, and debounces 200 ms per name.
`CHARTEVENT_OBJECT_CLICK` is deliberately not handled (`:2878`).

What that forbids, and therefore what this architecture may never contain:

| Not available | Consequence for the IA |
|---|---|
| hover | no tooltips, no reveal-on-hover, no disclosure triangles. Every affordance is permanently drawn or absent |
| focus / tab order | no keyboard navigation *within* a destination. `m_tag_focus` is set only from `CHARTEVENT_MOUSE_MOVE` (`:2885`) and is therefore dead in the pessimistic branch |
| scroll | no long lists. Paging with explicit buttons, or nothing |
| clipping | no overflow that is merely ugly — overflow lands on the candles and stays there |
| drag | no repositioning, no sliders, no resize handles |
| a combo box | the setup wizard's "pseudo-combo" is a stack of buttons that outlives its step (`ui-dialogs-2`, CONFIRMED). Do not build a second one |
| measurement of text | `Extent()` covers sized objects only and excludes labels by design (`SSR_Widgets.mqh:125-128`, invariant I10). Every text overflow in L.9 is invisible to the instrument |

One exception survives: `OBJ_EDIT`. MetaTrader owns the caret, so a typed field works without any
event reaching the program — and `Edit()` writes `OBJPROP_TEXT` only on creation or an explicit
reset (`SSR_Widgets.mqh:316-324`) so a repaint cannot erase what is being typed. That is the only
typed input this architecture may use, and it must be **read at a moment**, never polled.

#### M.1.2 What a frame costs, measured

[CONFIRMED FROM CODE] Write counts are literal `m_writes +=` statements. Warm cost is the
`Same()` early return, which ends in `ObjectFind` (`SSR_Widgets.mqh:80`, invariant 3).

| primitive | site | cold | warm | notes |
|---|---|---|---|---|
| `Rect` | `:195` | 9 writes | 0 writes, 1 `ObjectFind` | |
| `Label` | `:226` | 6 | 0, 1 `ObjectFind` | |
| `ButtonC` | `:358` | 9 | 0, 1 `ObjectFind` | |
| `Edit` | `:288` | 9 (+1 with text) | **never cached** | no `Same()` call at all |
| `Group` | `:500` | 24 (Rect+Rect+Label) | 3 finds | |
| `Chip` | `:525` | 15 (Rect+Label) | 2 finds | |
| `Meter` | `:540` | 27 (three Rects) | 3 finds | |
| `Progress` | `:399` | 18 | 2 finds | |
| `Toast` | `:604` | 24 | 3 finds | |
| `Slider(20)` | `:460` | **198** (Rect + 20×ButtonC + Rect) | 22 finds | |
| `Hide(id,b)` | `:616` | 1 find + 1 write + **`Forget`** | — | invalidates the cache in *both* directions |
| `Remove(id)` | `:627` | 1 find + `ObjectDelete` + `Forget` | — | |
| panel `Text()` hit | `SSR_Panel.mqh:191-198` | — | 1 `ObjectFind` + **1 `ObjectSetInteger(COLOR)`** | a cached label is 1 write, not 0 |

The anchor is the project's own measurement, quoted at `SSR_Widgets.mqh:31-38`:

> *"561 object properties written per STILL frame, and a mean repaint of 39.05 ms — against an
> engine that pumps every 40. One repaint was eating a whole pump interval… On a frame where
> nothing changed that is 561 writes turned into 77 lookups."*

≈ **0.07 ms per property write.** That number is the currency of this entire document.

**What a still frame actually costs today** [INFERENCE, from two CONFIRMED findings plus the
arithmetic above]:

```
DrawSheet -> HideSheets()          154 Remove()   (70 named + 4x3 meters + 12x6 rows)
                                                  = 154 ObjectFind + ~25 ObjectDelete + 154 Forget
SheetTrade rebuild, all cold       ~190 writes    (2 Groups, ~10 Labels, ~8 Buttons, 1 Edit)
HideBody(false) at :729             57 Hide()     = 57 find + 57 write + 57 Forget
   ...of which ~44 are SIZED and immediately redrawn cold
                                   ~396 writes    (44 x 9)
-----------------------------------------------------------------------------------
                                   ~586 property writes + ~211 ObjectFind, per frame,
                                   on a frame where NOTHING CHANGED
```

At 10 fps (`SSReplayStandalone.mq5:3063`) that is ≈ 0.41 s of repaint per second of wall clock,
on the thread that pumps ticks. `ui-panel-1` and `ui-panel-2` are not two bugs; they are the
reason the panel has no paint budget left to spend on an information architecture.

**What a still frame costs under this proposal:**

```
no Remove, no Hide on a still frame -> every object takes the Same() early return
Standard / TRADE:  ~95 objects on screen
   caption 13 + clock 4 + transport 7 + speed 25 + rail 6 + actions 4 + sheet ~25 + status 6
cost = ~95 ObjectFind + ~30 ObjectSetInteger (the Text() colour write)
     = ~30 writes, ~2 ms
navigation click = one teardown (~25 Remove) + one cold draw (~190 writes), ONCE
```

**~586 writes × 10/s becomes ~30 writes × 10/s plus ~190 writes per tab click.** That is the whole
argument for the architecture below: destinations are cheap once navigation is the only deleter.

#### M.1.3 What geometry allows

[CONFIRMED FROM CODE] `SSR_Theme.mqh:484-499`. Rail layout: `SSR_PANEL_W 310`, `SSR_RAIL_W 44`,
`SSR_ACT_H 21`, `SSR_SHEET_H 186`, `SSR_SHEET_GROW 140`, `SSR_SHEET_H_TALL 326`,
`SSR_PANEL_H 336`, `SSR_PANEL_TALL_H 476`, `SSR_PANEL_COMPACT_H 128`, `SSR_STATUS_H 18`,
`SSR_PAD 8`, `SSR_GAP 5`.

Derived budgets, all of them hard:

| region | budget | capacity |
|---|---|---|
| rail, Standard | 186 px | **7 cells** (`25n-3 ≤ 186`) |
| rail, Expanded | 326 px | 13 cells |
| sheet width | `310 - 16 - 44 - 5` = **245 px** | a row from `x+8` has **237 px** |
| sheet height, Standard | 186 px | 9 rows of `SSR_ROW_H 19` + 15 px, or 6 rows + two 45 px Groups |
| sheet height, Expanded | 326 px | 17 rows of 19 |
| status strip | `310 - 16` = 294 px | **4 readouts**, not five (see `ui-panel-6`) |
| action strip | `bw = (310-16-6)/3` = 96 px | 3 buttons |
| speed groove | 130 px | see M.1.6 |

[CONFIRMED FROM CODE] `SSR_PANEL_H` is the literal sum `(23+32+27+21+21+186+18+8)` in **both**
layouts, and the `21` for the action row is a bare number rather than `SSR_ACT_H` or `SSR_TAB_H`
(`SSR_Theme.mqh:499`). Any change below that touches a row height must make that `21` symbolic
first, or the frame silently desynchronises from its contents. `ui-plumbing-11` (CONFIRMED,
IMPROVEMENT) records that four of the six numbers in the metrics comment a designer is meant to
size a new row against are already stale.

#### M.1.4 What text allows

Ground truth: MetaTrader draws exactly 63 characters of `OBJPROP_TEXT`, stores the rest, and
errors on nothing. `Clip()` (`SSR_Panel.mqh:242`) caps at 62 and marks the cut with `~`, and is
applied at **four** sites in a 3049-line panel (`:960`, `:1760`, `:1840`, `:1892`).

But 63 is not the binding limit inside the sheet. [INFERENCE — MQL5 exposes no text metrics, so
the px/char figures are estimates, not measurements] at Tahoma 8 pt (`SSR_FS_BODY`) ≈ 5.1 px per
character and 7 pt (`SSR_FS_SMALL`) ≈ 4.5:

```
sheet row from x+8, 237 px usable:   ~46 chars at FS_BODY      ~52 chars at FS_SMALL
status slot, ~70 px:                 ~13 chars at FS_SMALL
rail cell, 44 px:                    ~8  chars at FS_BODY
action button, 96 px:                ~18 chars at FS_BODY
```

**The sheet's real budget is 46 characters, not 63.** Every confirmed text-overflow defect in L.9
is a row written against 63 (or against the old 295 px sheet) and drawn into 237: `ui-panel-7`
(note column over the P/L column, nine pixels for nine characters), `ui-panel-8` (21-character
speed meaning in a 52 px reserve), `ui-panel-6` (fidelity anchored at `x+330` in a 310 px panel).

This gives the architecture its most boring and most valuable rule: **a destination is a set of
rows, and every row declares its character budget next to its draw call.**

#### M.1.5 Z-order: why overlays are structurally expensive

Ground truth: creation order is the only z-order, and `ObjectCreate` refuses an existing name.
The panel repaints from state and never clears the chart (invariant I7).

[CONFIRMED FROM CODE] The consequence is stated in the code itself (`SSR_Panel.mqh:767-775`):
anything opened *over* the panel goes straight back under it on the next repaint, so the panel
re-`Show()`s the key card every frame (`:776-777`). `CSSRKeyCard::Show` begins with
`m_w.RemoveAll()` (`SSR_KeyCard.mqh:72`) — `ObjectsDeleteAll` + `ForgetAll` — and then recreates
~41 objects. `ui-panel-12` (CONFIRMED, MEDIUM) prices it at ~41 `ObjectDelete` + 41
`ObjectCreate` + ~450 property writes **per frame while the card is up**.

So the rule is not aesthetic:

> **An overlay costs a full rebuild every 100 ms for as long as it is open.
> A destination costs a rebuild once, when it is selected.**

Anything a user reads for more than a second belongs in the sheet.

#### M.1.6 The speed groove, priced honestly

[CONFIRMED FROM CODE] `SSR_SPEED_LADDER_SIZE 20` lives in `Common/SSR_Types.mqh:302` — it is an
**engine** constant (`SSRSpeedLadder`, `:318`, `:332`, `:341`), not a UI one. The panel draws one
cell per ladder stop into `m_track_w = 130` px, i.e. **6.5 px per target**, and says so at
`SSR_Panel.mqh:1048-1053`: *"Below about five the cells stop being clickable and the slider
becomes a picture of a control."*

[RECOMMENDATION] Decouple the **drawn cell count** from the ladder size. Draw 10 cells of 13 px,
each selecting ladder index `2i`; keep `-` / `+` for ±1 stop so every one of the 20 speeds stays
reachable. The engine constant is untouched, `HideBody` keeps sweeping all 20 ids (correct by the
same reasoning as invariant I8), and the slider's cold cost falls from **198 writes to 108**.
Cost: `DrawSpeed` plus the `spdseg<digits>` branch of `Dispatch` (`:2564`), ~20 lines.

---

### M.2 Five rules the constraints dictate

**R1 — Navigation is the only thing allowed to delete.**
`HideSheets()` runs as the unconditional first statement of `DrawSheet` (`SSR_Panel.mqh:1268`)
and `HideBody(false)` runs unconditionally at `:729`. Both must become **transition-driven**: they
run on the frame where `m_tab`, `m_compact`, `m_tall`, `m_collapsed` or `m_closed` differs from the
value the last render used, and on no other frame. This is the single highest-value change in the
document and it fixes `ui-panel-1`, `ui-panel-2` and (by ordering) `ui-panel-3`.

**R2 — Everything OPERATED is chrome; everything CONSULTED is a destination.**
This rule already exists and is correct — `SSR_Panel.mqh:670-674`, *"keeps what is OPERATED —
clock, transport, speed, status — and drops what is only CONSULTED."* It is the reason the brief's
HOME and REPLAY destinations are rejected: they would move permanently-visible operated controls
behind a click.

**R3 — An overlay is a per-frame rebuild; a destination is a per-click rebuild.**
Therefore: a surface is an overlay only if it is (a) a modal decision about the chart underneath
it, (b) a moment rather than a reference, or (c) a search field that must float. Everything else
is a destination.

**R4 — Every destination owns its teardown list, declared beside its draw function.**
The current state is three hand-kept lists that disagree: `HideSheets()` 70 ids with `spreadrow`
and `traderr` listed twice and four dead entries (`g3_fr`, `g3_lb`, `g3_lg`, `pp_g`);
`HideSheetArea()` stopping at `tab3` (`ui-panel-4`, CONFIRMED); `HideBody()` 30 ids plus three
loops. One list per destination, iterated only for the destination being left, is both cheaper
(≈25 `Remove` instead of 154) and cannot drift, because it sits in the same function that creates
the ids.

**R5 — Every row declares a character budget and goes through `Clip()`.**
46 at `FS_BODY`, 52 at `FS_SMALL`, split at column boundaries for two-column rows. Add audit
**A22**: every `Text(` / `Label(` call site in `/Ui/` either passes a `Clip(...)` expression or
carries an explicit `// unbounded:` justification. This is mechanical, ~200 edits, and it retires
the whole first paragraph of L.9.

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
  |TRADE |                                                       |
  | Pos 3|                                                       |
  | Perf |              THE SHEET - the one swapped region        |     186 / 326
  | Sess |                       245 px wide                     |
  | Keys |                                                       |
  | Eval |                                                       |
  +------+-------------------------------------------------------+
  | 10,412.55   +38.20   3 open   sp 1.2                         |     status       18
  +--------------------------------------------------------------+
```

[CONFIRMED FROM CODE] This is the existing grammar (`SSR_Panel.mqh:631-826`), unchanged in
structure. The proposal does not invent a layout; it fixes what the bands contain and makes the
swap cheap.

**Why exactly one swapped region.** Two swapped regions would need two teardown lists, two
transition latches and a combinatorial z-order (creation order is the only ordering MQL5 has). One
region, one latch, one list per destination — this is the cheapest correct model, and it is the
one already in the file.

#### M.3.2 The brief's eight, judged against the code

| Brief's destination | Verdict | Reason, from source |
|---|---|---|
| **HOME** | **REJECT** | Everything a home would show is already permanent chrome: state and modes in the caption (`DrawCaption:833-940`), clock and progress (`DrawClock:945`), balance/float/open/spread in the status strip (`DrawStatus:1915`). A HOME destination is the chrome drawn a second time, at the cost of a rail cell and a click. The chrome *is* home |
| **REPLAY** | **REJECT as a destination** | Transport (`y+55`) and speed (`y+82`) are operated controls and must stay permanent under R2. Putting PLAY behind a click is the one change that would make this product worse. The *consulted* replay data — bars, ticks, rejected, guard violations, streams, skew, fidelity note, leak advice, checkpoints — has a home already: **SESSION** |
| **TRADE** | **ACCEPT** | Exists: `SheetTrade` (`:1346`). The only sheet that acts, the densest, and the one with the typed field |
| **POSITIONS** | **ACCEPT** | Exists: `SheetPositions` (`:1509`). `PosCap()` 5 → 12 in Expanded (`:432`) |
| **PERFORMANCE** | **ACCEPT, re-homed** | The content exists and is excellent — **43 measures in 9 groups**, `SSRReviewRows()` (`SSR_Review.mqh:97-161`). Today it is reachable only as a 520 px overlay on `A`. The current Stats sheet (`:1671`) is 3 numbers duplicated from the status strip, 3 run counters, and a button |
| **CHALLENGE** | **ACCEPT as PROP** | Exists: `SheetProp` (`:1749`), four meters, conditional on `m_state.prop_on`, `TabCount()` asked rather than assumed (`:1103`). [RECOMMENDATION] Do not rename the *ids* or the string keys; the display text is a one-line change in `SSR_Strings.mqh` and `fa.txt` if the author prefers "Challenge" |
| **JOURNAL** | **REJECT for v1** | `CSSRJournal` is an **exporter**, not a browser: `ExportCsv`/`ExportHtml` write files, and `Line(index, digits)` is an O(n) walk (`trading-analytics.md` §4). Eight rows on screen costs O(8n) per frame, every frame. Keep JOURNAL as the `stmt` action on PERFORMANCE. [FUTURE FEATURE] A real journal destination needs an indexed accessor first |
| **SETTINGS** | **REJECT** | There is no body of mid-session settings. Speed is chrome; risk is on TRADE; trailing is on POSITIONS; fidelity and lines are action buttons; panel size and collapse are keys. The 61 expert inputs are pre-session and belong to `CSSRSetupPanel`. The command palette (31 entries, 4 groups, `SSR_Command.mqh`) is already the settings surface and costs one `Edit` and eight rows |

Eight becomes five. Add **KEYS** — which the brief does not list and the code needs badly — and the
rail is six.

#### M.3.3 The proposed rail

| # | id | name (EN) | short | conditional |
|---|---|---|---|---|
| 0 | `tab0` | Trade | `Trade` | no |
| 1 | `tab1` | Positions | `Pos` / `Pos %d` | no |
| 2 | `tab2` | Performance | `Perf` | no |
| 3 | `tab3` | Session | `Sess` | no |
| 4 | `tab4` | Keys | `Keys` | no |
| 5 | `tab5` | Evaluation | `Eval` / `PASS` / `FAIL` | **yes** (`prop_on`) |

`25×6 - 3 = 147 px` of a 186 px rail. 39 px spare, which is one more cell plus 14 px — **left
unspent on purpose**. A rail at capacity is a rail that cannot absorb a feature.

Constraints this respects:
* The conditional destination stays **last**, so `TabCount()` remains the existing
  `prop_on ? SSR_TAB_MAX : SSR_TAB_COUNT` question (`:1103`) and the re-clamp at `:745` still
  works unchanged. Invariant I9 survives verbatim.
* Names stay inside ~8 characters at 44 px. `Pos %d` already does; `Perf`, `Sess`, `Keys`, `Eval`
  do. [POTENTIAL_RISK] Persian remains unverifiable — `rtab.positions = پوزیشن` with a Latin digit
  appended is a mixed-direction string in a bidi-less renderer (L.3.3). Unchanged by this
  proposal, and unverifiable without a terminal.

**Cost of going from 5 to 6:** `SSR_TAB_MAX 5 → 6`, `SSR_TAB_PROP 4 → 5`, one new `ENUM` value,
three new short strings plus their `fa.txt` rows. [INFERENCE] `RestorePlace()`'s sanity bound is
`tab < SSR_TAB_MAX` (`ui-panel.md` §10), so a v125 `panel.ini` holding `tab=4` (Prop) will select
**Keys** on the first run of the new build. Harmless, but it must be named in the release note, and
it argues for bumping the `[panel]` section key from `tab` to `dest` so an old value is simply
not found.

#### M.3.4 Navigation inside a destination: pages, never scroll

[CONFIRMED FROM CODE] The product already has exactly one correct answer to "more rows than fit",
and it is the review card: `SSR_RV_SHOWN 12`, `m_first`, explicit `up`/`down` buttons
(`SSR_ReviewCard.mqh:32-34`), with the header comment *"PAGED, BECAUSE MQL5 CANNOT CLIP"* (`:12`).
`CSSRWidgets::List` (`SSR_Widgets.mqh:565`) is the primitive, and `CSSRPalette` and
`CSSRSessionDialog` both use it.

**Rule:** a destination that overflows pages. The pager is two 30 px buttons and one
`"%d-%d of %d"` label in the sheet's last 19 px. Never a scrollbar, never a "show more" that grows
the frame.

[CONFIRMED FROM CODE] One thing to fix while adopting it: `ui-dialogs-16` (CONFIRMED,
IMPROVEMENT) — the review card's 12 measure rows are `OBJ_BUTTON`s whose latch nothing consumes,
so a clicked statistic stays drawn pressed. A read-only row must be a `Label` on a `Rect`, not a
button. That is 6 writes instead of 9, and it removes a false affordance.

#### M.3.5 What stays an overlay, and why

| Surface | Stays? | Reason under R3 |
|---|---|---|
| Command palette (`SSRX_`) | **overlay** | A search field that must float over whatever it is searching. Already drawn last of all (`:816`). Cost is one `Edit` + 8 `List` rows |
| Session picker (`SSRSD_`) | **overlay** | A modal decision that replaces the whole session. 420 px wide; cannot fit a 245 px sheet |
| Range / jump dialog (`SSRD_`) | **overlay** | A modal decision about an instant, quoting its cost before anything is written. 248 px |
| Review card (`SSRR2_`) | **overlay** | A *moment* — the end-of-session verdict, with ≤6 observations. Its 43-measure table is now also a destination; the card and the destination share one generator (`SSRReviewRows`), so there is no second list to drift |
| Reveal card (`SSRV_`) | **overlay** | One button, keys dropped while up. The cleanest surface in the product; do not touch it |
| **Key card (`SSRK_`)** | **BECOMES A DESTINATION** | 18 listed rows read for minutes at a time, rebuilt destructively at 10 Hz (`ui-panel-12`). The exact case R3 exists to catch |
| **First-run card (`SSRF_`)** | **REMOVED** | See M.4.5 |

Net: nine object-name prefixes become **seven**. Two classes and two `seen.txt`-style side effects
go away.

---

### M.4 What each destination holds

Notation: `slot` is the panel's 128-entry label cache (`SSR_SLOTS`, `ui-panel.md` §5); `budget` is
the R5 character budget; **new** marks a row drawn nowhere today.

#### M.4.0 The chrome (unchanged in structure, corrected in content)

| Band | Content | Change |
|---|---|---|
| caption 23 | identity, build tag, run state, mode chips (`chfid`/`chblind`/`chprop`), `-`, `X` | **none structurally.** `ui-panel-13` (CONFIRMED, LOW): the chip row ends at `x+274` and `collapse` starts at `x+268`. Move the chip origin from `x+140` to `x+134` and cap the fidelity chip text at 6 characters. Modes-as-chips (`:860-862`) is preserved verbatim — it is the strongest accessibility reasoning in the product |
| clock 32 | masked clock, `%d%%` + pause reason (clipped at 24), progress bar | none |
| transport 27 | `\|< << < [PLAY/PAUSE 91px] > >>` ··· `Reset 58` | none. The 91 px primary against 24 px steps is how primary-vs-secondary is carried, and it is correct. (`ui-plumbing-10`, which claimed the primary and an engaged toggle share a colour, is **NOT_A_BUG** — do not act on it) |
| speed 21 | label, `-`, value box, `+`, groove, meaning | 20 cells → **10 drawn cells** (M.1.6). Meaning text `Clip(..., 11)` — fixes `ui-panel-8` |
| actions 21 | `Lines` \| `Sessions` \| `Fidelity` | none. Three at 96 px each |
| status 18 | **four** readouts, not five | see below |

**The status strip: five numbers into four slots.**
[CONFIRMED FROM CODE] `ui-panel-6` (CONFIRMED, HIGH): `stfid` is anchored at `x+330` in a 310 px
panel — the anchor alone is 20 px past the frame, and `"SYNTHETIC TICK !"` adds 70-80 px more, on
**every frame of every session**.

The fix is deletion, not relocation: **fidelity is already a caption chip** (`chfid`,
`DrawCaption:886`), drawn with the same `SSRFidelityShort()` and a `!` when degraded. The strip was
printing it twice. Remove `stfid` from the strip; the caption keeps it, which is where it belongs
by the caption's own rule (*"it is a mode, not a measurement"*, `:860`).

That frees slot 53, and it is spent on the one piece of **information** v125's removals cost
(L.4.3):

```
x+8     balance        Clip 14      stbal   slot 50
x+106   floating       Clip 12      stflt   slot 51
x+196   N open (+P)    Clip  9      stopen  slot 52
x+252   sp N.N         Clip  8      stspread slot 54
        ...replaced, when charts_detached > 0, by:
x+252   N adrift  F    Clip  8      chartsn slot 53
```

[CONFIRMED FROM CODE] `m_state.charts_detached` is filled by `CSSRGroupPort` (`SSR_GroupPort.mqh:122`)
and matched **zero times** in `SSR_Panel.mqh` outside the struct. `chart-10` (CONFIRMED, MEDIUM):
*the replay advances, the candles stop moving, and the interface says nothing at all.* Spread is the
right thing to yield the slot: it also appears on the Trade sheet and in the fill toast.

[RECOMMENDATION] Preserve the status ladder's priority order and its written rationale
(`:1915-2035`) exactly. `charts_detached` is a **standing condition**, so if the author prefers it
as a ladder line rather than a slot, it belongs at level 5 — below `TooNarrow()`, above the
numbers — by the ladder's own rule.

#### M.4.1 TRADE — *what I am about to do*

Reuses `SheetTrade` (`SSR_Panel.mqh:1346`) essentially as-is. It is the densest and best sheet in
the product.

| row | content | source | slot | budget |
|---|---|---|---|---|
| Group | "Risk" | — | — | — |
| risk ladder | `- [ 1.00% ] +`, monitor | `risk_percent` | 10, 11, 19 | 20 |
| setup tag | `OBJ_EDIT` `tagbox` | `trade_tag` | — | — |
| Group | "Order" | — | — | — |
| side / order kind | `LONG setup` \| `order_name` | `line_long`, `order_name` | 12 | 30 |
| **why refused** | `order_why`, **its own object id** | `order_why` | 17 | 44 |
| SL \| TP | two columns | `sl_price`, `tp_price` | 13, 14 | 22 each |
| RR \| size | two columns | `rr`, `lot_from_risk` | 15, 16 | 22 each |
| risk \| reward | two columns **new** | `risk_money`, `reward_money` | 20, 21 | 22 each |
| arm / flip / clear | three buttons | `lines_armed` | — | — |
| BUY \| SELL | the primary pair | `can_trade` | — | — |

**New:** `risk_money` / `reward_money` printed as money (both are on the wire and drawn nowhere
today). `stop_points` and `tp_points` stay undrawn deliberately — a stop in points is the thing the
lines design deliberately replaced (`SSR_ReplayPort.mqh`, *"a stop typed in points is a stop chosen
by arithmetic"*).

**Fixes as a consequence:** `ui-panel-5` (CONFIRMED, MEDIUM) — slots 12 and 17 currently write the
**same object `setuprow` at the same coordinates**, so `order_why` is visible for one frame and
then gone for good. Giving `order_why` its own id is the fix.

> [INFERENCE — important interaction] R1 alone does **not** fix `ui-panel-5`; it changes its shape.
> Today `HideSheets()` deletes `setuprow` every frame, so `Text(12)` always writes and `Text(17)`
> always takes the early return. With the transition latch, both take their early returns and the
> object keeps whatever was last written. The two changes must land together.

**Refused for this destination:** a stop/target stepper, a lot-size box, an order-type selector.
All three are decisions the chart lines already make from geometry, and each would need a control
MQL5 cannot draw.

#### M.4.2 POSITIONS — *what is open*

Reuses `SheetPositions` (`:1509`) with re-derived arithmetic.

| row | content | budget |
|---|---|---|
| n rows | `pr<r>` plate, `pn<r>` note, `pl<r>` money, `ph`/`pb`/`px` buttons | see below |
| overflow | `+%d not shown` | 14 |
| hint | `H halves   B stop to entry   X closes` | 37 |
| Break-even all \| Close all | two buttons | 18 each |
| trailing | `- [ 150 pt ] +  Off` | 20 |

**The row arithmetic must be re-derived for 245 px.** [CONFIRMED FROM CODE] `ui-panel-7`
(CONFIRMED, MEDIUM): the note column is anchored at `x+120` and the money column at
`x+w-116 = x+129` — **nine pixels for the nine characters of `"  no stop"`**, and the same for
`"  sp 20.0"`. The two things a trader reads on that row are printed over each other.

Proposed columns in 237 px, three buttons at the right taking 60:

```
x+0    text   "BUY 1.00 @ 53513"       Clip 18      ~92 px
x+96   note   "no stop" / "sp 20.0"    Clip  8      ~40 px
x+140  money  "+38.20"                 Clip  8      ~40 px
x+180  H B X  three 18 px buttons                    60 px
```

[INFERENCE] `ui-panel-7`'s sibling risk also resolves: `posmore` is currently at `x+w-92 = x+153`
on the same baseline as the 37-character `poshint` drawn from `x+8`, which reaches ≈`x+175`.
Put `posmore` on its own baseline.

**Removed:** the three row-button captions `H`, `B`, `X` are the same letters as three **global
keys** with three unrelated meanings (`ui-plumbing-14`, CONFIRMED, LOW: `H` opens the key card,
`B` bookmarks, `X` flips the planning lines). [RECOMMENDATION] Relabel the row buttons to
`½` / `BE` / `✕` and let the hint line name the actions rather than the letters. Cost: three
strings.

#### M.4.3 PERFORMANCE — *what I have done*

**This is the destination that gains the most and costs the least**, because its content already
exists, is already grouped, and is already length-disciplined.

[CONFIRMED FROM CODE] `SSRReviewRows(st, out[])` (`SSR_Review.mqh:97-161`) produces **43 rows in
nine groups** — Result (10), Rates (8), R (4), Drawdown (4), Streaks (3), Excursion (2), Time (2),
Discipline (4), Execution (6) — and `SSRReviewLine()` formats one to `SSR_REVIEW_ROW_MAX 60`
*"60, not 63, because the card puts a two-character group marker in"* (`:50`).

| region | content |
|---|---|
| header | group name + `"%d-%d of 43"` |
| rows | 9 per page (Standard) / 17 (Expanded), `Label` on a `Rect`, **not** buttons |
| pager | `<` `>` two 30 px buttons |
| footer | `Save statement` (`stmt`, the existing action) |
| footnote | `st.Caveat()` when `!IsTrustworthy()`, `Clip(..., 52)` |

Standard: 43 rows ÷ 9 = **5 pages**. Expanded: 43 ÷ 17 = **3 pages**.

**Removed:** the old Stats sheet's `st1`/`st2`/`st3` — balance, equity, floating — which duplicate
`stbal` and `stflt` in the status strip 200 px below. **Removed:** `st7`, the pointer that reads
*"see the Prop tab"*, because the Eval cell is now permanently in the rail.
**Moved to SESSION:** `st4`/`st5`/`st6` (bars, ticks, rejected, guard violations) — those describe
what the *machine* did, not what the *trader* did.

**Cost:** ~80 lines, and — importantly — **zero new measures, zero new port fields, zero new
statistics code.** One generator, two consumers (this sheet and the end-of-session card).

**What this does not fix:** `ui-dialogs-4` (CONFIRMED, MEDIUM) — two review *observation*
sentences exceed 63 characters for every possible value, and the ambiguous-bar line renders as
*"…reached both the stop and the t"*, losing the single most important caveat this product
reports about a fill. Observations live in `SSR_Review.mqh`'s `StringFormat` literals and are
outside `T()`. They need their own fix, and they should get it whether or not this proposal lands.

#### M.4.4 SESSION — *what the machine is doing*

The current Session sheet is a junk drawer (L.2.3): three diagnostics plus **four keyboard hint
lines**, three of which are factually wrong (`ui-plumbing-2`, CONFIRMED — `keys.2` says "R reset"
and `R` is bound to `SSR_CMD_LINES_TOGGLE` while reset is `0`; `keys.4` still teaches the `[]`
button deleted in v125 at `SSR_Panel.mqh:934`).

**Removed:** all four hint lines (`ses4`, `keyhint`, `ses5`, `ses6`). They move to KEYS, where they
are *generated* rather than written by hand.

| Group | rows | source | new? |
|---|---|---|---|
| **This run** | bars consumed | `bars_consumed` | moved from Stats |
| | ticks emitted | `ticks_emitted` | moved |
| | rejected / guard | `ticks_rejected`, `guard_violations` | moved |
| | pump p95, µs/tick | `pump_p95_ms`, `us_per_tick`, gated on `perf_calibrated` | **new** |
| **This session** | bookmarks | `bookmarks` | exists |
| | checkpoints | `checkpoints` | **new** |
| | saved position | `has_saved_position` | **new** |
| | streams / skew | `streams`, `skew_msc` | exists |
| | charts | `leak_clean` / `leak_advice`, `Clip(..., 52)` | exists |
| | **charts adrift** | `charts_detached` + `F` | **new** |
| | strategies | `strategy_text`, `Clip(..., 52)` | **new** |

[CONFIRMED FROM CODE] **Eleven wire fields the panel never draws.** A grep for `m_state.<field>`
over `SSR_Panel.mqh` returns 0 for: `strategy_text`, `pending_count`, `checkpoints`,
`has_saved_position`, `perf_calibrated`, `us_per_tick`, `pump_p95_ms`, `charts_detached`,
`stop_points`, `tp_points`, `prop_floor` — while `CSSRGroupPort` fills every one of them
(`SSR_GroupPort.mqh:122, 123, 132-134, 147, 148, 214, 243, 372, 395`).

**That is the cheapest new information in this product**: no port change, no engine change, no new
observer — nine `Text()` calls against fields that are already computed and already on the wire
every frame. `ui-port-session.md` §2.2 lists them as orphans; this destination is where they stop
being orphans.

[CONFIRMED FROM CODE] `chart-7` (CONFIRMED, MEDIUM) must be fixed alongside: `LeakGuard::Advice`
is written far longer than the ~49 characters its only consumer can display. `Clip()` makes the cut
honest; shortening the advice at source makes it useful.

#### M.4.5 KEYS — *how to drive it*

[CONFIRMED FROM CODE] `SSRKeyBindings()` (`SSR_Keys.mqh:125-218`) is **22 bindings, all 22 vk
values distinct, 18 marked `listed`**, and the key card's height is counted from the table rather
than chosen. L.7 is right that this is the strongest piece of UI engineering in the product. It
should be extended, not replaced.

| region | content |
|---|---|
| header | `All virtual — nothing reaches a broker.` (`SSR_S_ALL_VIRTUAL`) |
| rows | 9 per page (Standard) / **all 18** (Expanded), `label` at `x+0`, `what` at `x+74`, `Clip` 16 / 36 |
| pager | `<` `>` + `"%d-%d of 18"` |

Standard: 18 rows ÷ 9 = **2 pages**. Expanded: one page, no pager drawn.

**What this destination fixes, all at once:**

* `ui-panel-12` (CONFIRMED, MEDIUM) — ~41 deletes + 41 creates + ~450 writes **per frame** become
  ~20 objects drawn once per navigation.
* L.4.4 — the key card currently opens on `H` only, and the string that teaches `H` is drawn only
  by `CSSRFirstRun`, which in the default configuration is shown on **neither** pass of the
  one-window handover (`host-expert-4`, CONFIRMED). A permanently-visible rail cell is a discovery
  path that cannot be missed.
* `ui-plumbing-1` (CONFIRMED, MEDIUM) — the card's row text is English literals inside
  `SSRKeyBindings()`, making it the one user-facing surface outside `T()`. Moving the rows into a
  sheet is the moment to add `ENUM_SSR_STR` ids for the 18 `what` strings. Cost: 18 catalogue
  entries + 18 `fa.txt` rows; the catalogue grows 190 → 208.
* `ui-plumbing-15` (CONFIRMED, LOW) — `Ctrl+K` is not in the key table, so `SSRKeyToCommand(75)`
  returns `SSR_CMD_NONE` and the generated list cannot mention the palette. Add the binding with
  `listed = true`; the destination then teaches the one feature the code comment at `:929` wrongly
  records as lost.
* `ui-plumbing-3` (CONFIRMED, LOW) — `SSRKeyHint()` is a third hand-written list, also saying "R
  reset". Rewrite it to *generate* from `SSRKeyBindings()`. Then there is one list, and A22's
  sibling audit can assert that no drawn string contains a bare key letter that the table does not
  bind.

**Removed: `CSSRFirstRun` entirely** (`SSR_FirstRun.mqh`, 148 lines, prefix `SSRF_`).
[CONFIRMED FROM CODE] It is unreachable in the default configuration (`host-expert-4`), and where
the guard does let it through, `Show()` reports success without checking that its fixed position
`y = 376..480` fits the chart, so on a chart under ~480 px it is drawn off-screen, `seen.txt` is
written anyway, and the product's only onboarding is consumed unread (`ui-dialogs-14`, CONFIRMED).

[RECOMMENDATION] Replace it with one branch in `RestorePlace()`: **when no `panel.ini` exists,
the opening destination is KEYS.** One `if`, no new class, no new file, no fixed coordinate to be
wrong about, and it cannot be consumed unseen because the rail cell stays there afterwards.

#### M.4.6 EVAL — *whether I am passing*

Reuses `SheetProp` (`:1749`) **unchanged**. It is correct: four meters, every meter with its
number beside it, the sheet computes nothing, and the reasoning is written down
(*"a meter worked out here could read 'safe' in the frame the evaluation reads 'failed'"*).

Two small corrections only:
* `pp_rules` is already clipped at 62 (`:1760`); at 237 px the real budget is **52**.
* `pp_head` is clipped at 44 (`:1840`); keep.

**New in Expanded:** nothing. The sheet's worst case is a finished run with a deadline at 178 of
186 px (`:1765-1775`); Expanded gives it 140 px more and it should stay **empty**. A fifth meter
for a rule most challenges do not set would teach nobody what it counts — the sheet says so
itself about the deadline. Whitespace is the premium choice here, and it is also free.

---

### M.5 Mapping onto what exists

| Proposed | Existing class / function | Reused | New | Removed |
|---|---|---|---|---|
| chrome: caption | `DrawCaption:833` | all | — | chip origin `x+140` → `x+134` |
| chrome: clock | `DrawClock:945` | all | — | — |
| chrome: transport | `DrawTransport:975` | all | — | — |
| chrome: speed | `DrawSpeed:1045` | all | 10 drawn cells over 20 stops | `spdseg10..19` from the draw (still swept) |
| chrome: actions | `DrawActions:1235` | all | — | — |
| chrome: status | `DrawStatus:1915` | ladder + 4 slots | `charts_detached` readout | **`stfid`** (`ui-panel-6`) |
| rail | `DrawRail:1209` | all | 6th cell | — |
| swap | `DrawSheet:1268` | dispatch switch | **transition latch** | unconditional `HideSheets()` |
| TRADE | `SheetTrade:1346` | ~all | `risk_money`/`reward_money`; `order_why` own id | slot-17-over-slot-12 collision |
| POSITIONS | `SheetPositions:1509` | ~all | re-derived columns | `H`/`B`/`X` letter captions |
| PERFORMANCE | `SSRReviewRows` (`SSR_Review.mqh:97`) + `CSSRWidgets::List` | generator, `stmt` | pager, group header | `SheetStats` `st1`,`st2`,`st3`,`st7` |
| SESSION | `SheetSession:1877` | `ses1`,`ses2`,`ses3` | 9 rows from orphan wire fields | `ses4`,`keyhint`,`ses5`,`ses6` |
| KEYS | `SSRKeyBindings` (`SSR_Keys.mqh:125`) | the table, verbatim | sheet renderer, pager, 18 `T()` ids | **`CSSRKeyCard`** (132 lines, prefix `SSRK_`) |
| EVAL | `SheetProp:1749` | all | — | — |
| onboarding | `RestorePlace:` | — | one `if`: no ini → KEYS | **`CSSRFirstRun`** (148 lines, prefix `SSRF_`, `seen.txt`) |
| teardown | `HideSheets:1284`, `HideSheetArea:2042`, `HideBody:2077` | the *idea* of I7 | one list per destination | three drifting lists, `spreadrow`/`traderr` dupes, dead `g3_*`/`pp_g`, missing `tab4` |
| clipping | `Clip:242` | verbatim | R5 budgets at every sheet site + audit A22 | — |

**Untouched, deliberately** — every item of L.10 survives: latch polling as the one click
mechanism; the single generated key table; the status ladder's priority order and its rationale;
"removed, not merely undrawn" (I7); modes as chips; operated-vs-consulted; the wish/fact split for
tall mode with both numbers named; `TabCount()` as a question; the `Clip`/63-character discipline;
and the two compile-time switches (`SSR_LAYOUT_RAIL`, `SSR_THEME_*`) that let one commented line
undo a large change on a terminal the author cannot run.

---

### M.6 Compact / Standard / Expanded

The product's existing mode flags map onto the brief's three words exactly, and they should not be
renamed. [CONFIRMED FROM CODE] `SSR_Panel.mqh:679-714`: `m_compact` is **measured** (chart height
< `SSR_PANEL_H + 24` = 360 px) and never user-chosen; `m_tall` is a **wish** (`P`, persisted)
whose **fact** is recomputed every frame against `SSR_PANEL_TALL_H + 24` = 500 px, with the
refusal surfaced on the status strip and both numbers named.

| | Compact | Standard | Expanded |
|---|---|---|---|
| trigger | chart < 360 px, measured | default | `P` **and** chart ≥ 500 px |
| `BodyH()` | 128 | 336 | 476 |
| sheet | **none** | 186 px | 326 px |
| rail | **none** | 6 cells, 147 px | 6 cells, 147 px (identical) |
| chrome | caption, clock, transport, speed, status | same | same |
| TRADE | — | 11 rows | 11 rows + strategy line + spare |
| POSITIONS | — | `PosCap() = 5` | `PosCap() = 12` (existing, `:432`) |
| PERFORMANCE | — | 9 rows/page, 5 pages | 17 rows/page, 3 pages |
| SESSION | — | 6 rows + 1 Group | 11 rows + 2 Groups |
| KEYS | — | 9 rows/page, 2 pages | **all 18, no pager** |
| EVAL | — | 4 meters, 178 of 186 px | 4 meters, 140 px left empty |
| destination memory | remembered, not drawn | — | — |

**The rail is deliberately mode-independent.** 6 cells fit in 186 and in 326, so the selector's
geometry never changes with height. That is a robustness decision, not a visual one: a rail whose
cell count varied with mode would need `PosCap()`-style arithmetic in the one control the user
must always be able to hit.

**Compact is where this proposal fixes the most.** [CONFIRMED FROM CODE] `ui-panel-3` (CONFIRMED,
**HIGH**): `HideSheetArea(true)` at `:682` is undone by `HideBody(false)` at `:729` **inside the
same `Render()`**, so on a chart that shrinks below 360 px the rail, the `tabline` and the three
action buttons stay visible at full-layout coordinates — up to 122 px of still-clickable buttons
painted on the candles below a 128 px panel. `ui-panel-4` (CONFIRMED, LOW) adds that
`HideSheetArea`'s list stops at `tab3`, stranding the fifth tab even after that is fixed.

Under R1 both disappear structurally: `HideBody` and the destination teardown are **transition
functions**, so nothing undoes anything inside one frame, and the teardown list is per-destination
and generated from the same place that creates the ids — `tab4`/`tab5` cannot be forgotten.

`ui-panel-10` (CONFIRMED, MEDIUM) also resolves: in Compact the fill toast is placed at
`y + 128 - 18 - 24 = y+86`, directly on the speed row (`y+82..y+101`) and above it in creation
order, for four seconds per fill — in the mode where the speed control is one of only four things
left. [RECOMMENDATION] In Compact the toast replaces the **status strip** line rather than floating
above it: same information, zero occlusion, and the strip is the lowest-priority band by the
ladder's own ordering.

**Closed and Collapsed are not modes of this architecture; they are states of the frame.** Both
are preserved verbatim, including the `reopen` button and its rationale (*"a control that removes
its own only way back is a trap"*, `:641-647`). One correction: the `m_closed` branch at `:649-655`
returns **before** `ClampToChart` at `:716`, so a chart resized while closed can strand the 76×20
`reopen` button off-screen with no recovery short of reattaching the EA. Clamp before the early
return.

---

### M.7 The honest cost

#### M.7.1 Per change

| # | Change | ~lines | Risk | Fixes | Cost if wrong |
|---|---|---|---|---|---|
| 1 | Transition latch: `HideSheets`/`HideBody` on change only | 40 | **high** — it inverts when teardown happens | `ui-panel-1`, `ui-panel-2`, `ui-panel-3` | a stale object from the previous destination, permanently on the chart (I7). Must land with #2 |
| 2 | Destination register: one id list per destination | 150 | medium | `ui-panel-4`, list drift | same as #1 |
| 3 | `order_why` its own object id | 5 | low | `ui-panel-5` | **must land with #1** — see M.4.1 |
| 4 | Status strip: drop `stfid`, add `charts_detached` | 25 | low | `ui-panel-6`, `chart-10` (UI half) | a fidelity signal that now exists only in the caption chip |
| 5 | Position-row columns re-derived for 245 px | 30 | low | `ui-panel-7` | pure arithmetic, checkable by `CheckFrame` for the buttons only |
| 6 | 10 drawn speed cells over 20 stops | 20 | low | the 6.5 px target | a speed the user must reach with `+`/`-` instead of one click |
| 7 | Rail 5 → 6, `SSR_TAB_MAX` 5 → 6 | 30 + 4 strings | low | — | an old `panel.ini` selects the wrong destination once (M.3.3) |
| 8 | KEYS destination; delete `CSSRKeyCard` | +120 / −132 | medium | `ui-panel-12`, `ui-plumbing-1`, `ui-plumbing-15`, L.4.4 | the key list is no longer visible *while* on another destination |
| 9 | Delete `CSSRFirstRun`; first-run opens KEYS | +3 / −148 | low | `ui-dialogs-14`, `host-expert-4` (surface) | onboarding is quieter — a cell, not an announcement |
| 10 | PERFORMANCE destination over `SSRReviewRows` | 80 | low | L.2.2's thin Stats sheet | none structural; one generator, two consumers |
| 11 | SESSION rehome + 9 orphan wire fields | 50 + 8 strings | low | L.2.3, 9 of 11 orphans | rows whose values have never been seen on a terminal |
| 12 | R5: character budgets + `Clip()` at every sheet site | ~200 mechanical | low | `ui-panel-8` and L.9's label class | a `~` where a designer wanted a word |
| 13 | Audit A22 (clip discipline) + generated `SSRKeyHint()` | 60 (Python + MQL5) | low | `ui-plumbing-3` | — |
| | **total** | **≈ +700 / −280 in one file, two classes deleted** | | | |

#### M.7.2 The build order, and why

1. **#1 + #2 + #3 together.** They are one change. Nothing else in this document is worth doing on
   a panel that spends its whole paint budget rebuilding itself.
2. **#4, #5, #12.** Pure arithmetic and clipping. Visible on every frame of every session, cheap,
   independently testable, and they do not touch navigation at all.
3. **#7 + #8 + #9.** The rail grows and two classes die. This is the point of no return for the
   `panel.ini` contract.
4. **#10 + #11.** The two destinations that add information. Entirely additive.
5. **#6 + #13.** Polish and instrumentation.

#### M.7.3 What this proposal does NOT fix, and will not claim to

* **L.4.2 is still unsettled.** This architecture is designed to be correct without mouse events,
  which is why it contains no drag, no hover, no slider thumb and no focus. If mouse events *do*
  arrive, everything here still works and the drag is a bonus. But `ui-panel-11` (POTENTIAL_RISK:
  the tag box hidden and re-shown 10×/s while it may hold the keyboard) remains live either way,
  and R1 helps it — under the transition latch the tag box is no longer touched on a still frame at
  all, which is the strongest mitigation available without a terminal.
* **`ui-dialogs-1` (CONFIRMED, HIGH)** — the setup wizard silently clears `session_name` and
  `extra_tfs`, so sessions are never written and cannot be resumed. That is upstream of every
  destination here and is L.11's second priority. Nothing in this document touches it.
* **`host-expert-7` (CONFIRMED, MEDIUM)** — keys are not withheld while the Sessions or Jump dialog
  is open, so Space starts the replay and Tab opens a virtual trade while the user reads a modal.
  The review card already solves this by returning `true` for every key while up
  (`ui-dialogs.md` §4); the two dialogs must copy it. Out of scope here, but it gates any claim
  that the overlays are safe.
* **`chart-12` (CONFIRMED, LOW)** — every word the chart layer draws (`"STOP - drag me"`,
  `"TARGET - drag me"`, `BUY`/`SELL`/`SL`/`TP`, closed-trade captions) is an English literal outside
  `T()`. A Persian user still gets English labels on the only objects they are asked to drag.
* **Nothing here has been run on MT5.** Every pixel number is derived from constants in the source;
  every px/char figure is an estimate MQL5 will not confirm; `CheckFrame()` can only ever see the
  sized objects, never the labels (invariant I10). The rail's Persian names remain a
  POTENTIAL_RISK that no amount of source reading can close.

---

### M.8 Visual direction, in tokens that already exist

Dark, premium, minimal, professional, dense, hierarchical — the `SSR_THEME_RAIL` palette is
already all of those, and the failure in L.9 is arithmetic, not colour. **No new colour tokens are
proposed.** The palette has 51 `SSR_C_*` tokens, each defined identically in all three palettes
(`ui-plumbing.md` §3), and adding one means adding three and a contrast-table line.

The instruments available for hierarchy, and the rule for each:

| Instrument | Tokens | Rule |
|---|---|---|
| three surfaces | `SSR_C_PANEL`, `SSR_C_HEADER`, `SSR_C_WELL` | a **value** sits in a well; a **band** sits on the header; everything else sits on the panel. Already how `spdbox` works (`:1063`, *"a value in a dialog sits in a box"*) |
| one hairline | `SSR_C_GROUP_EDGE` / `SSR_C_TAB_EDGE` | 1 px, used by `Group` and `tabline`. Never two hairlines adjacent, never a hairline as decoration |
| three text weights | `SSR_C_TEXT`, `SSR_C_TEXT_DIM`, `SSR_C_TEXT_FAINT` | measurement / label / provenance. The build tag is FAINT; that is the correct use |
| one primary | `SSR_C_PRIMARY` + `_EDGE` + `_TEXT` | **exactly one primary control per band.** Today: `toggle` in transport (91 px vs 24 px steps), `BUY`/`SELL` on TRADE. Nothing else may be blue |
| semantic four | `SSR_C_RUN`, `HOLD`, `STOP`, `IDLE` | state only, never decoration, and **never alone** — modes are chips with text (`:860-862`) |
| deal pair | `SSR_C_BUY`, `SSR_C_SELL` + edges | the trade pair only |
| four type sizes | `SSR_FS_CLOCK 13`, `TITLE 9`, `BODY 8`, `SMALL 7`, one face (Tahoma) | 13 for the clock alone; 9 for identity and the primary; 8 for rows; 7 for provenance and hints. **Do not add a fifth** |

Two tokens are declared in all three palettes and drawn by nothing — `SSR_C_THUMB_EDGE` and
`SSR_C_TICK` (`ui-plumbing-9`, CONFIRMED, LOW). Spend them on the speed groove's thumb and tick
marks under M.1.6 rather than deleting them, and the slider gets its outline back at zero cost to
the palette.

What the constraints forbid, which happens to match the brief: **no gradients** (MQL5 fills a
rectangle with one colour), **no glow** (no alpha, no blur), **no rounded corners**
(`BORDER_FLAT` is what `Rect` writes at `SSR_Widgets.mqh:216`), **no icons** (a glyph is a font
the user may not have; the product deliberately uses one face for both text and "mono",
`SSR_Theme.mqh`). Restraint here is not taste — it is the only thing that can be drawn.

The one genuinely premium move available: **`Clip()` everywhere, and whitespace where there is
nothing to say.** A panel whose every row ends where it means to, on a terminal that will never
warn you, is the whole difference between this product and a mockup.

---

### M.9 What this architecture refuses to do

* **It will not put an operated control behind a click.** No HOME, no REPLAY destination.
* **It will not add a destination without data.** SETTINGS and JOURNAL are rejected on that
  ground, and JOURNAL names the exact blocker (`Line(index)` is O(n), `trading-analytics.md` §4).
* **It will not add a seventh rail cell**, even though seven fit. The spare cell is the budget for
  whatever the product learns next.
* **It will not invent a control MQL5 cannot draw.** No combo, no scrollbar, no tree, no tooltip,
  no modal shade, no drag.
* **It will not rename a sound term.** Sheet, rail, chip, ladder, latch, wish/fact, operated vs
  consulted, "removed, not merely undrawn" — all preserved. The only new word in this document is
  **destination**, and it is a rename of nothing: it is what the code already calls a tab plus the
  sheet behind it.
* **It will not claim a runtime behaviour.** Every number above is derived from a constant or a
  literal in the source. The author has never run this build on MT5, and neither has this document.

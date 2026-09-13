## M. PREMIUM INFORMATION ARCHITECTURE — PROPOSAL 2: COACH-FIRST

*Angle: derive the navigation from what a **coach** needs while standing behind a student mid-session,
and from what the same coach needs an hour later with the student gone. Four questions, in the order
a coach actually asks them: **is the risk legal · is the exposure survivable · is the challenge still
alive · what did they actually do**. Everything else is chrome or is afterwards.*

*Build v125, `SSR_LAYOUT_RAIL` and `SSR_THEME_RAIL` active. Every geometry number below is re-derived
from `SSR_Theme.mqh` and `SSR_Panel.mqh`, not from a comment. Read after section L.*

---

### M.0 The precondition, restated without softening

[RECOMMENDATION] Nothing in this proposal should be built before **L.4.2 is settled on a real
terminal**: whether `CHARTEVENT_MOUSE_MOVE` reaches `CSSRPanel`. The wiring says it does
(`SSReplayStandalone.mq5:1463` `g_panel_chart = ChartID()`; `SSR_Panel.mqh:325` sets
`CHART_EVENT_MOUSE_MOVE`; `:2885-2966` handles it in full); the removal rationale at
`SSR_Panel.mqh:929-931` says it does not. For a coach-first IA the stake is specific and large:

* **The typed note dies with the mouse.** `m_tag_focus` is set **only** from the mouse-move
  hit-test (`SSR_Panel.mqh:2885+`, and the `m_tag_focus` guard at `:2835`). If mouse events do not
  arrive, the one `OBJ_EDIT` on the panel can never take focus, and a JOURNAL destination cannot
  accept a word from anybody. That is the difference between a journal and a list of timestamps.
* The speed groove becomes twenty 6.5 px click targets (`m_track_w` = 130 / `SSR_SPEED_LADDER_SIZE`
  20, `SSR_Panel.mqh:1047-1050`).
* `ui-panel-11` (POTENTIAL_RISK) is either live or moot.

[INFERENCE] Everything else in this proposal survives either answer. The journal note is the only
piece that is contingent, and M.4.5 states the fallback rather than hiding it.

---

### M.1 The method: what a coach is actually doing

[RECOMMENDATION] A coach is not a second trader. A coach is a **referee plus a historian**, and the
two roles want opposite things from a screen:

| Moment | The coach's question | What must be visible without any navigation | What may live one click away |
|---|---|---|---|
| Before the click | "Is this size legal, and is there a stop?" | risk %, stop present/absent, R, money at risk | the ladder, the tag |
| During | "How bad can this get, and is the challenge still alive?" | floating, open count, distance to the daily floor | per-position management |
| At the close | "Was that the plan, or was that a feeling?" | nothing — the tape should stop | the trade's own numbers |
| Afterwards | "What is the pattern?" | nothing | discipline measures, marks, the statement |

[CONFIRMED FROM CODE] Three of those four moments are already served by machinery the coach never
sees:

1. **The pause-and-talk instrument exists and has no UI at all.** `CSSRAutoPause`
   (`Trading/SSR_AutoPause.mqh:31-41`) defines `SSR_PAUSE_ON_ENTRY / _SL / _TP / _STOPOUT /
   _ANY_CLOSE`, defaults to `SL|TP|STOPOUT`, and raises a reason string the controller consumes as
   an auto-pause. This is *the* coaching mechanism — the tape stops on the event worth discussing —
   and its flags come from an expert input, are drawn nowhere, and are named nowhere on the panel.
2. **The behaviour measures exist and are locked behind a modal card.** `SSR_Review.mqh:148-161`
   already groups four measures under the literal heading **`"Discipline"`** — `risk_spread_pct`,
   `risk_samples`, `"Straight back in after a loss"` (`revenge_trades`), `trades_without_stop` —
   and six under **`"Execution"`** — average/worst spread, `wide_spread_trades`,
   `ambiguous_trades`, `ambiguous_pct`. `SSRReviewObservations` (`SSR_Review.mqh:179-217`) already
   turns them into up to six coach sentences. None of it reaches the panel: the review card opens
   only from `A`, from `RunHostCommand`, or automatically once at the end of a prop run
   (`SSReplayStandalone.mq5:3025-3035`).
3. **A labelled-moment primitive exists and the panel shows only its count.**
   `CSSRReplayController::Bookmark(label)` `:1531`, `GotoBookmark(index)` `:1538`,
   `BookmarkLabel(i)` `:1549`, `BookmarkCount()` `:1550`. The panel draws
   `"Bookmarks  %d"` on the Session sheet (`SSR_Panel.mqh:1880-1882`) and nothing else; the port
   exposes only `Bookmark(label)`. A journal already exists in the engine and has no reader.

[INFERENCE] The coach-first IA is therefore mostly **routing, not invention**. Three of its five
destinations are built from values that are already computed by a single owner; the expensive part
is one throttled statistics read (M.4.3) and one set of bookmark accessors (M.4.5).

---

### M.2 Why the brief's eight destinations are not the answer here

[RECOMMENDATION] Take four of the eight, reject four, and say why for each.

**Rejected — HOME and REPLAY.** [CONFIRMED FROM CODE] These are not destinations in this product;
they are the permanent chrome, and the code already argues the point better than the brief does.
`SSR_Panel.mqh:670-674` states the split the panel is built on — *"keeps what is OPERATED — clock,
transport, speed, status — and drops what is only CONSULTED"* — and compact mode is the enforcement
of it. Caption (23) + clock (32) + transport (27) + speed (21) + status (18) are drawn on **every**
frame in every mode above `m_collapsed`. Turning the transport into a destination would mean a coach
has to navigate to reach *pause*. Reject.

**Rejected — SETTINGS.** [CONFIRMED FROM CODE] The settings surface is `CSSRSetupPanel`, a 4-step
pre-session wizard covering 14 of the expert's 61 inputs (L.5). A live SETTINGS tab would be a
second writer of the same configuration, and `host-expert-10` (CONFIRMED) already documents what
happens when a second path bypasses the `Cfg*()` accessors: extra streams and the saved settings
block record the inputs rather than the values the session ran with. Adding a third writer, mid-run,
to a config that `host-expert-6` (CONFIRMED, HIGH) shows is already restored unconditionally across
a handover, is how a coach ends up teaching from a session that misdescribes itself. The handful of
live toggles that genuinely belong in-session (tick detail, trailing, auto-pause flags) belong to
the destination that owns them, not to a settings drawer.

**Rejected as a top-level destination — SESSION.** It is the junk drawer (L.2.3) and the audit is
right about it. Its three live rows relocate in M.4.6.

**The hard ceiling, stated as a number.** [CONFIRMED FROM CODE] `DrawRail` (`SSR_Panel.mqh:1209-1225`)
draws `n` cells of `SSR_RAIL_W` × 22 with a 3 px gap, inside a sheet of `SSR_SHEET_H` = 186
(`SSR_Theme.mqh:449`). The code states its own arithmetic at `:1207`: *"Five cells at 22 + 3 is 122 px
inside a 186 px sheet."* Extending it:

| cells | rail height | fits 186 px sheet |
|---:|---:|---|
| 5 | 5·22 + 4·3 = **122** | yes (64 spare) |
| 6 | 6·22 + 5·3 = **147** | yes (39 spare) |
| 7 | 7·22 + 6·3 = **172** | yes (14 spare) |
| **8** | 8·22 + 7·3 = **197** | **no — 11 px over** |

**Eight top-level destinations do not physically fit the shipping layout.** Six is comfortable, seven
is the ceiling, and seven leaves 14 px — less than one 19 px row of spare. This is not a preference.

[INFERENCE] So the coach-first model takes **five destinations, one of them conditional**, which is
exactly the cell count the rail already draws and exactly the `SSR_TAB_MAX` (5, `SSR_Theme.mqh:544`)
the sweep loops already use. **Zero new geometry, zero new constants, zero change to
`HideSheetArea`'s length.** That is the single strongest argument for this model over the brief's.

---

### M.3 The navigation model

```
   caption   23   identity · build · run state · [FID] [BLIND] [CHALLENGE] [TRUST] · − ×
   clock     32   masked clock + progress
   transport 27   |<  <<  <  [ PLAY / PAUSE ]  >  >>   ···  Reset
   speed     21   −  [ 1.0x ]  +   ▭▭▭▭▭▭▭▭▭▭▭▭▭▭▭▭▭▭▭▭   meaning
   actions   21   Lines │ Saved │ Detail
   ───────────────────────────────────────────────────────────────
   rail 44 │ sheet 245                                        186
     RISK  │   the destination
     OPEN  │
    REVIEW │
    CHALL* │   * only while an evaluation is configured
     JRNL  │
   ───────────────────────────────────────────────────────────────
   status    18   balance │ float │ n open │ spread │ fidelity
```

Five destinations, in the coach's own order of urgency, top to bottom:

| # | Rail cell | Replaces | The one question it answers |
|---|---|---|---|
| 0 | **RISK** | Trade | *Is the next click legal?* |
| 1 | **OPEN** | Positions | *How bad can what is already on get?* |
| 2 | **REVIEW** | Stats | *What is the pattern in what they have done?* |
| 3 | **CHALL** | Prop (conditional) | *Is the challenge still alive?* |
| 4 | **JRNL** | — (new) | *What did we mark, and what leaves the room with them?* |

[RECOMMENDATION] The order is not alphabetical and not the current order. It is the order of the
coach's questions, and the two destinations a coach looks at *while a trade is live* (RISK, OPEN) are
the two at the top of the rail, nearest the transport their hand is already on.

#### M.3.1 The one new mechanic: a rail cell can raise its hand

[RECOMMENDATION] The defining need of coach-first is **notice without navigation**. A coach should
not have to click through five sheets to discover that the student is 85% through today's loss
allowance. So: a rail cell may draw a **single coloured glyph** in its right edge when the
destination behind it holds a condition.

```
  RISK !      <- lines armed and the order is refused (order_why != "")
  OPEN        <- nothing
 REVIEW !     <- a discipline measure has crossed
  CHALL !!    <- daily allowance >= 80%  (!! and SSR_C_STOP when the run is over)
   JRNL       <- never; a journal is never an alarm
```

Rules, all from fields already on the wire (`SSR_ReplayPort.mqh` §2.2):

| Cell | Condition | Source field | Colour |
|---|---|---|---|
| RISK | `lines_armed && order_why != ""` | `order_why` | `SSR_C_HOLD` |
| RISK | `lines_armed && sl_price == 0` | `sl_price` | `SSR_C_STOP` |
| OPEN | `open_positions > pos_rows` | both on the wire | `SSR_C_HOLD` |
| REVIEW | `revenge_trades > 0 \|\| trades_without_stop > 0` | new (M.4.3) | `SSR_C_HOLD` |
| CHALL | `prop_daily_used >= 0.8 \|\| prop_total_used >= 0.8` | existing | `SSR_C_HOLD` |
| CHALL | `prop_state >= 3` (FAILED / VOID) | existing | `SSR_C_STOP` |

[RECOMMENDATION] It must be a **glyph**, not a dot. `SSR_Panel.mqh:860-862` states the product's own
rule — *"a mode carried by colour alone is a mode a colour-blind trader cannot read"* — and a
coloured dot is exactly that. `!` and `!!` at `SSR_FS_SMALL` carry the signal without the colour;
the colour only carries the speed.

[CONFIRMED FROM CODE] Cost: five new object ids (`tabf0..tabf4`), five `Text()` calls (the panel's cached-label helper) inside the
existing `DrawRail` loop, five cache slots, and **five `m_w.Remove()` calls in the same sweep loop
that already runs at `:1223-1224`** — invariant I7 (*"a tab the rail no longer has is REMOVED"*)
already has the loop; the flags join it. No new geometry, no new strings, no new colours. This is
the cheapest high-value item in the proposal.

#### M.3.2 What does not change, deliberately

[RECOMMENDATION] All ten items in L.10 survive verbatim. Specifically for this proposal:

* `PollClicks()` stays the one click mechanism, latch-cleared-before-acting, 200 ms per-name
  debounce, palette polled first and alone (`SSR_Panel.mqh:2445-2466`).
* `Dispatch()`'s `tabN` branch (`StringLen == 4 && prefix "tab"`) is untouched — renaming Stats to
  REVIEW changes `TabName(i)` and nothing else. **A click on `tab2` still selects sheet 2 whichever
  layout is built**, which is what `:1205-1206` already promises.
* `TabCount()` stays a question, not a constant, and `m_tab` stays re-clamped when the answer
  changes (`:745-746`, invariant I9).
* The status ladder keeps its priority order and its rationale (`:1915-2035`).
* Modes stay chips on tinted plates.
* The generated key table stays the single source of truth for keys; the three hand-written lists
  die (M.4.6).

---

### M.4 The destinations

#### M.4.1 RISK — "is the next click legal?"

**Maps onto:** `CSSRPanel::SheetTrade` (`SSR_Panel.mqh:1346-1508`), unchanged in purpose, reordered
and given one new row. Same ids: `risklbl riskmon riskdn riskval riskup taglbl tagbox armbtn hintrow
setuprow slrow tprow rrrow sizerow openln flipbtn enbtn clrbtn buy sell`.

**The change: a verdict line at the top.** [RECOMMENDATION] Today a coach reads legality by
assembling four numbers spread over 92 px of group box: risk % on row 1, stop price on row 4, R on
row 4-right, lot on row 5-right. Put the verdict first, in one line, at `SSR_FS_BODY`:

```
   0.50 %  ·  25.00     ·  2.0 R  ·  0.42 lot
   ^risk      ^at risk     ^reward   ^size
```
coloured by the **worst** of the three tests — no stop → `SSR_C_STOP`; `order_why != ""` →
`SSR_C_HOLD`; otherwise `SSR_C_TEXT`. Every value is already on the wire (`risk_percent`,
`risk_money`, `rr`, `lot_from_risk`) and every one is already computed by the owner that will
execute the order — `PreviewLot` is *the same call the order uses, never a second formula*
(`ui-port-session.md` §3.3). The panel still computes nothing.

**The one new number: what a stop-out costs the challenge.** [RECOMMENDATION] The question a coach
asks more than any other — *"if that stop gets hit, how much of today is gone?"* — is not answerable
on any screen in this product. Both operands are on the wire (`risk_money`, `prop_daily_floor`,
`equity`) but the arithmetic must **not** be done in the panel: `SheetProp`'s own comment
(`SSR_Panel.mqh:1732-1736`) states why — *"a meter worked out here could read 'safe' in the frame the
evaluation reads 'failed', and the trader would believe the bar."* So it becomes one accessor on
`CSSRPropEvaluation` (`DailyRoomAfter(double loss)`) and one pre-clamped fraction on the wire,
drawn on RISK as one `SSR_FS_SMALL` line:

```
   this stop would use 34 % of today's allowance
```
and drawn on CHALL as the same number in money. One owner, two readers, no second formula.

**Fixed in passing:** `ui-panel-5` (CONFIRMED, MEDIUM) — cache slots 12 and 17 write the same object
`setuprow` at the same coordinates, so `order_why` is visible for one frame only. The verdict line
gives `order_why` its own slot and its own row, which is the fix and also where a coach looks for it.

**Cost:** 1 new evaluation accessor, 1 wire field, 1 cache slot, ~3 new strings, one re-derivation of
the group-box arithmetic for a 245 px sheet. **Low.** No new objects beyond one label.

#### M.4.2 OPEN — "how bad can this get?"

**Maps onto:** `CSSRPanel::SheetPositions` (`SSR_Panel.mqh:1509-1665`), same ids
(`pr/pn/pl/ph/pb/px` × 12, `posempty poshint posmore be flat trlbl trdn trup troff`), same
`PosCap()` derivation (5 standard / 12 tall), same `SSR_POS_MAX` sweep.

**The change: the stop flag leaves the note column.** [CONFIRMED FROM CODE] `ui-panel-7` (CONFIRMED,
MEDIUM) is a coach-visible defect on every frame: the note column is anchored at `x+120`, the money
column at `x + w - 116 = x + 129`, so nine pixels hold the nine characters of `"  no stop"` and the
two things a coach reads on that row — *does it have a stop* and *what is it losing* — are printed
over each other. Coach-first makes "no stop" the single most important per-row fact, so it cannot
live in a colliding column. Move it to a **one-character left gutter** before `pr<n>`:

```
   ·  BUY 0.42        -18.40
   !  SELL 0.10       +6.20        <- no stop
   ·  BUY 0.25 pend    waiting
```
`!` in `SSR_C_STOP` when `sl == 0`, `·` in `SSR_C_TEXT_FAINT` otherwise. That frees the note column
for the spread note alone and re-derives the row for 245 px. [INFERENCE] It also resolves the
overlap half of `ui-panel-7` without needing a longer sheet.

**Kept exactly:** the H/B/X per-row buttons and the reasoning at `:1596-1600` for withholding H and B
on a pending (*"a button that always refuses teaches the user to distrust the row it sits on"*). The
error-into-`poshint` routing at `:1619-1628` stays; it is the right place for a refusal.

**Not fixed here, named honestly:** `ui-plumbing-14` (CONFIRMED, LOW) — H, B and X are printed as row
captions while the same three letters are global hotkeys for the key card, a bookmark and a line
flip. Coach-first makes this worse, because a coach reading over a shoulder will say *"press X on
that one"*. [RECOMMENDATION] Either the row buttons lose their letters (they have 18 px, so a glyph
fits) or the hint line stops reading like a key legend. This is a decision, not a defect I can fix
from the IA.

**Cost:** one column re-derivation, one new gutter object per row (12 ids, 12 slots — the slot map
has room: 80-115 are used, 116-127 are free). **Low-to-medium**; 12 more objects on a sheet that
`ui-panel-1` (CONFIRMED, HIGH) already deletes and recreates every repaint, so fix `ui-panel-1`
first or the cost multiplies.

#### M.4.3 REVIEW — "what is the pattern?" (the biggest change in this proposal)

**What Stats holds today** (`SheetStats`, `SSR_Panel.mqh:1671-1723`): balance, equity, floating — all
three of which are **already on the status strip on every frame** (`stbal`, `stflt`,
`SSR_Panel.mqh:1996+`) — plus bars consumed, ticks emitted, rejected/guard-violations, plus the
statement button. [INFERENCE] For a coach, four of those six numbers are engine diagnostics and two
are duplicates. `core-engine-5` (CONFIRMED, MEDIUM) makes it worse: `bars_consumed` counts a bar once
per pump that touches it, so the "Bars" figure a coach might quote is wrong by 10-1500×.

**What REVIEW holds instead.** The Discipline and Execution groups that `SSRStatistics` already
computes and that today reach only the modal card and the exported HTML:

```
   ┌ RESULT ─────────────────────────────────┐
     12 trades      58 % win       1.42 PF
     +0.31 R expectancy over 11 measured
   └─────────────────────────────────────────┘
   ┌ DISCIPLINE ─────────────────────────────┐
     risk varied        18 %  over 11 trades
     back in after loss    2
     no stop               1
   └─────────────────────────────────────────┘
     entered wide          3 of 12
     ambiguous bars        2  (17 %)          <- trust caveat
   [ Save statement ]
```

**Mapping.** Every row is an existing field of `SSRStatistics` (`SSR_Statistics.mqh:46-114`) and
every heading is an existing literal in `SSR_Review.mqh:148-161`. `profit_factor` must be drawn as
*undefined*, not `0.00`, when `gross_loss == 0` — `trading-analytics-6` (CONFIRMED, LOW) shows the
0.00 lie propagating through the KPI grid, the by-setup table, the CSV header and `Summary()`; a
coach quoting "PF 0.00" about a student with no losing trades is the exact harm.

**The honest cost, stated plainly.** [CONFIRMED FROM CODE] The panel has no access to
`CSSRStatsEngine` today. `CSSRGroupPort::ReadState` fills account numbers from `m_acct` and never
calls `Compute` — the map records it: *"The panel Stats tab does **not** use it"*
(`trading-analytics.md` §3). And `ComputeFor` is *"up to 3 passes over `Total()` slots with a struct
copy each"* — `SSRVirtualPosition` is ~660 B plus two strings — *"+ O(4096) drawdown walk"*. At the
panel's 10 fps (`SSReplayStandalone.mq5:3063`) that is not affordable.

[RECOMMENDATION] The mitigation, and it must be written down at the site: **compute on change, not
on frame.** `CSSRGroupPort` recomputes only when `m_acct.ClosedCount()` changes or 2000 ms have
passed, and caches into ~12 new `SSRUiState` fields. The consequence is real and must be stated on
the sheet's own terms: **the behaviour numbers can lag the account by up to two seconds.** For a
coach reading a pattern over twelve trades, two seconds is nothing; for a number beside a live P/L it
would be a lie. That is precisely why the *result* numbers a coach reads live (balance, equity,
floating, open count) stay on the status strip, computed per frame from the account, and the
*pattern* numbers live here, throttled. The split is the design, not a compromise.

**Trust, where it belongs.** [RECOMMENDATION] `SSRStatistics::IsTrustworthy()` (`trades > 0 &&
ambiguous_pct <= 10`) and `Caveat()` already exist and `CSSRJournal`'s HTML already opens with a
caveat box. Put the same caveat here, above the statement button, and put a `TRUST` chip in the
caption when it is false. A coach who draws a conclusion from an untrustworthy run is the failure
`CSSRClassReport` warns about in its own comments (`:22-23`, `:470-472`: *"a table ranking people who
did not run the same session is not a comparison, it is a mistake with a heading on it"*). The same
sentence applies to one student's numbers on one sheet.

**Cost:** ~12 wire fields, one throttle in `ReadState`, ~12 new catalogue strings, one new caption
chip, one sheet rewritten. **This is the expensive destination — call it medium-high** — and it is
the one that makes the proposal coach-first rather than trader-first. Everything else is routing.

#### M.4.4 CHALL — "is the challenge still alive?"

**Maps onto:** `CSSRPanel::SheetProp` (`SSR_Panel.mqh:1749-1856`), **unchanged**. Four meters, a
number beside every bar, the deadline row only when there is one, the reason and the Reset button
only once the run is over, conditional on `m_state.prop_on` through `TabCount()`.

[RECOMMENDATION] Do not touch this sheet. Its comment block (`:1727-1748`) is the best design
reasoning in the product — *"A rule with no picture is a rule you find out about afterwards"*,
*"This sheet computes nothing"*, *"Every meter has its number beside it… a bar is unreadable to a
colour-blind trader"* — and all three of those are coach-first arguments already. Two additions
only:

1. The `DailyRoomAfter` number from M.4.1, in money, under the daily meter.
2. **R, not just percent.** A coach speaks in R. `prop_daily_floor` minus `equity` divided by
   `risk_money` is "you have 3.2 more stop-outs today". Both operands are on the wire; the division
   belongs to the evaluation, not the panel, for the reason the sheet already states.

**Two confirmed defects that a coach-facing CHALL makes much more visible, and that must be fixed or
labelled before it ships:**

* `trading-analytics-2` (CONFIRMED, MEDIUM) — prop evaluation state is **not persisted**; a resumed
  or reset run re-bases every rule on current equity. A coach and student who resume tomorrow get
  four meters that are confidently wrong.
* `trading-analytics-1` (CONFIRMED, HIGH) — resuming a saved session **voids** a running evaluation
  on startup. The CHALL tab then shows `VOID` for a session the student believes is live.
* `trading-analytics-12` (CONFIRMED, LOW) — a jump forward never runs the evaluation, so a jump that
  completes the window leaves it reading IN PROGRESS.

[INFERENCE] A conditional tab is easy to ignore when it is one of five. Promoted to a coach's primary
verdict surface, these three become the product's most damaging defects. Fix them, or draw the state
as `UNKNOWN AFTER RESUME` rather than as a verdict.

**Cost:** 2 new accessors, 2 wire fields, 2 strings. **Low** — plus the three engine fixes above,
which are not free and are not mine to size.

#### M.4.5 JRNL — "what did we mark, and what leaves the room?"

**The new destination, and it is mostly wiring.**

**Built from:** `CSSRReplayController::BookmarkCount()` `:1550`, `BookmarkLabel(i)` `:1549`,
`GotoBookmark(index)` `:1538`, `Bookmark(label)` `:1531`; `CSSRJournal::ExportCsv/ExportHtml`
(`SSR_Journal.mqh`, already reachable through the port's `ExportStatement`); `CSSRShotBook::RelPath`
(`SSR_ShotBook.mqh`, entry/exit PNG per ticket); `SSRReviewObservations` (`SSR_Review.mqh:179`).
`CSSRWidgets::List` (`SSR_Widgets.mqh:565`) already exists and is already used by the palette and
the session dialog, so the list primitive is not new either.

```
   ┌ MARKED MOMENTS ─────────────────────── 4 ┐
     09:41:12   london open                  →
     10:02:55   second entry, no stop        →
     10:17:30   revenge?                     →
     11:04:08   09:41 bookmark               →
   └──────────────────────────────────────────┘
     "2 of 12 trades opened within two minutes of a loss."
   [ Mark here ]   [ Save statement ]
```

**What is genuinely new:** four port verbs. Follow the precedent the session dialog already
established rather than putting a variable-length list on the wire: `CSSRSessionDialog` reads
`SessionCount()` then `SessionName(i)` / `SessionSummary(i)` per visible row
(`ui-port-session.md` §3.6). So: `BookmarkCount()`, `BookmarkLabelAt(i)`, `BookmarkTimeAt(i)`,
`GotoBookmarkAt(i)` on `CSSRReplayPort`, defaulted to refusal exactly as the other 30 optional verbs
are. `SSRUiState` gains nothing but the existing `bookmarks` count.

[CONFIRMED FROM CODE] **Warning inherited from the precedent:** `ui-port-session-12` (CONFIRMED, LOW)
— the session dialog re-parses every session file on every render. Bookmarks are in memory
(`m_snaps`), not on disk, so this list does **not** inherit the cost — but the pattern's per-row
accessor must not be allowed to grow a file read later.

**The note, and its honest limit.** [CONFIRMED FROM CODE] The label a bookmark carries today is the
timestamp: the panel calls `Bookmark(SSRFormatMsc(now))` (`ui-port-session.md` §6). Nobody types
anything. To make it a journal:

* **If mouse events reach the panel** (L.4.2 outcome 1): reuse the existing `tagbox` `OBJ_EDIT` as
  the mark label while JRNL is up. One Edit object, already created, already read on the way in by
  `ReadTag()` at the top of `Dispatch()` (`:2564`). `ui-panel-11` (POTENTIAL_RISK) applies and must
  be fixed first — the box is hidden, re-shown and rewritten 10×/s while the user may be typing in
  it.
* **If they do not** (outcome 2): there is no typed note in this product, on any surface, and saying
  otherwise would be a lie. The fallback is that a mark inherits the **setup tag** last set — which
  the coach and student choose together before the trade anyway, and which the statistics engine
  already groups by (`ComputeFor(tag)`). A journal of *"breakout · 10:02"* is worth having.

**Cost:** 4 port verbs (+4 default refusals on the base class), 1 sheet, ~6 strings, one `List`
usage, one `Dispatch` branch for the per-row `→` buttons following the existing `p{x|h|b}<digits>`
bounds-checked parse at `:2620+`. **Medium.** The note is contingent on L.4.2 and costs nothing extra
if the answer is yes.

#### M.4.6 What SESSION's contents become

[RECOMMENDATION] The Session sheet is deleted. Its four content blocks go four different places, and
one of them dies:

| Today (`SheetSession`, `:1877-1908`) | Becomes |
|---|---|
| `ses1` `"Bookmarks  %d"` | the JRNL rail cell and the JRNL list header |
| `ses2` streams + skew | a caption chip when `skew_msc != 0`; silent otherwise. It is a fault, not a statistic |
| `ses3` chart-leak advice | **status ladder, new level between "too narrow" and the five numbers.** It is a standing condition, which is what that part of the ladder is for. Requires `chart-7` (CONFIRMED, MEDIUM) fixed first: the advice is written far longer than the ~49 characters its consumer can draw |
| `ses4/keyhint/ses5/ses6` — the four keyboard-hint lines | **deleted** |

[CONFIRMED FROM CODE] Deleting the key hints is a correction, not a loss. Three of the four lines are
wrong: `keys.2` says *"R reset"* while `R` is `SSR_CMD_LINES_TOGGLE` (`SSR_Keys.mqh:162`) and reset
is `0` (`:200`) — `ui-plumbing-2` (CONFIRMED, MEDIUM), faithfully mistranslated at `fa.txt:216`;
`keys.4` teaches the `[]` corner button that v125 deleted (`SSR_Panel.mqh:934`); `keys.3` names
`F follow`, a key with no button and no readout. The generated key table is the single source of
truth (L.7) and the key card is generated from it. [RECOMMENDATION] Delete `SSR_S_KEYS_1..4`, fix
`SSRKeyHint()` (`ui-plumbing-3`), put `Ctrl+K` into the table so the card can show it
(`ui-plumbing-15`), and the product then ships **one** key list instead of four.

#### M.4.7 The signal v125 lost, restored in a coach-first place

[CONFIRMED FROM CODE] `charts_detached` is written on the wire by `CSSRGroupPort` and read by **no**
draw site (`chart-10`, CONFIRMED, MEDIUM). The removed `Follow` button carried it in its own label,
and the commit body says so: *"Nothing else on the panel says that now."* The user-visible result is
the worst possible one for a coach: **the replay advances, the candles stop moving, and the interface
says nothing at all.**

[RECOMMENDATION] It does not come back as a button. It comes back as a **caption chip** — the caption
already draws chips on tinted plates (`chfid`, `chblind`, `chprop`, `SSR_Panel.mqh:853-866`) and that
is exactly the right grammar for "a standing fact about this run". `⟲ 2` in `SSR_C_HOLD` when
`charts_detached > 0`, absent otherwise, with `F` still doing the work.

[CONFIRMED FROM CODE] `ui-panel-13` (CONFIRMED, LOW) must be fixed first: the chip row already ends at
`x+274` against a collapse button starting at `x+268` when fidelity is degraded — six pixels of
overrun with no margin in the good case. A fifth chip needs the row re-derived for 310 px, with a
measured budget rather than an assumed one.

---

### M.5 New, changed, removed — the ledger

**New**
* JRNL destination + 4 port verbs (`BookmarkCount/LabelAt/TimeAt/GotoAt`).
* Rail condition glyphs (5 ids, 5 slots, inside the existing loop).
* REVIEW's discipline/execution block + ~12 throttled wire fields.
* `DailyRoomAfter()` on `CSSRPropEvaluation` + 1-2 wire fields.
* RISK's verdict line; OPEN's stop-flag gutter.
* Caption chips: `TRUST` (untrustworthy statistics), `⟲ n` (detached charts), skew.
* One new status-ladder level for the chart-leak advice.

**Changed, not replaced**
* Stats → REVIEW (content replaced, ids and slot ranges 30-36 reused).
* Session → deleted, contents redistributed (M.4.6).
* Trade → RISK, Positions → OPEN, Prop → CHALL: **rail labels and order only.** `TabName(i)` changes;
  `Dispatch`'s `tabN` parse, `TabCount()`, `m_tab` persistence in `panel.ini` and the `HideSheets`
  sweep are all untouched.

**Removed**
* `SSR_S_KEYS_1..4` and the Session sheet's ids `ses1..ses6`, `keyhint`.
* `st4 st5 st6` (bars / ticks / rejected) from the panel — they remain in the log and the flight
  recorder, which is where engine diagnostics belong.
* The eight orphaned `SSR_S_*FOLLOW/BOOKMARK/JUMP` strings (L.4.5) — `FOLLOW`/`FOLLOW_N` are
  **un-orphaned** by the caption chip; `BOOKMARK` is un-orphaned by JRNL's "Mark here"; `JUMP` stays
  orphaned and should be deleted, taking `SSRTranslated()` from a false 190/190 to an honest count.
* The nine permanent `m_w.Remove()` calls for v124 ids (L.4.5) — they belong in a one-shot upgrade
  sweep at `Create()`, not on every frame forever.

---

### M.6 Compact / Standard / Expanded

[CONFIRMED FROM CODE] The three modes are already measured, wished and persisted correctly
(`SSR_Panel.mqh:679-714`): `m_compact` is measured from `CHART_HEIGHT_IN_PIXELS` and never chosen;
`m_tall` is a wish (`P`, persisted) whose fact is recomputed each frame with the refusal surfaced and
both numbers named. Keep all of it.

**Compact (chart < 360 px → `SSR_PANEL_COMPACT_H` 128).**
Destinations do not exist: the sheet and the rail are gone by definition, which is the correct
application of operated-vs-consulted. Two things this proposal requires:

1. **`ui-panel-3` (CONFIRMED, HIGH) must be fixed first.** `HideSheetArea(true)` at `:682` is undone
   by `HideBody(false)` at `:729` inside the same `Render()`, so today compact mode leaves the rail
   and action strip clickable on the candles. Adding condition glyphs to the rail would leave
   *warnings* on the candles. Order `HideSheetArea` after `HideBody`; add `tab4` to its list
   (`ui-panel-4`) and the five new `tabf*` ids with it.
2. **One escalated line.** A coach with a 300 px chart still needs the worst fact. Add exactly one
   status-ladder level — below the reset confirmation, the refused order and the refused panel size,
   above the five numbers — carrying the highest-priority rail condition as a sentence
   (*"challenge: 85% of today's allowance used"*). The ladder machinery exists; levels 1-4 already
   write slot 50 / id `stbal` and hide the other four, which is the correct way to give one message
   the whole strip.
3. **`ui-panel-10` (CONFIRMED, MEDIUM)** — the fill toast lands on the speed groove in compact mode,
   above it in creation order, for four seconds per fill. In compact, the toast should go to the
   status strip, not over the one control left.

**Standard (336 px panel, 186 px sheet, 5 position rows).** The model above, complete. Rail at
122-147 px inside 186. Nothing is cut.

**Expanded (`m_tall`, chart ≥ 500 px, `SSR_SHEET_H_TALL` = 326).** `SSR_SHEET_GROW` 140 px of extra
sheet. Coach-first spends it destination by destination, and each is additive — no layout reflows:

| Destination | The extra 140 px buys |
|---|---|
| RISK | the risk ladder drawn as seven labelled stops instead of a stepper + number; the setup tag's last five values as pickable chips (the statistics engine already groups by tag) |
| OPEN | 12 rows instead of 5 — **existing behaviour**, `PosCap() = (PosGroupH()-22)/20` |
| REVIEW | the observation block: up to 6 sentences from `SSRReviewObservations`. **Blocked on `ui-dialogs-4`** (CONFIRMED, MEDIUM): two of those sentences exceed MetaTrader's 63-character draw for *every possible value*, and the ambiguous-bar one renders as *"…reached both the stop and the t"*, which reads as a plain stop-out and loses the caveat. Shorten at the source in `SSR_Review.mqh`, then they can be drawn in two places |
| CHALL | the deadline row and the reason row unconditionally instead of only when present, plus the R-denominated room |
| JRNL | 12 marks instead of 5, and the per-mark screenshot indicator from `CSSRShotBook::RelPath` |

[INFERENCE] Note what expanded does **not** do: it never adds a destination. The rail count is a
function of `TabCount()` — `m_state.prop_on` — and nothing else, in all three modes. A coach who
learns the rail on a laptop finds the same rail on a 4K monitor.

---

### M.7 The visual system

[CONFIRMED FROM CODE] The active palette is already dark and already premium: `SSR_C_PANEL`
C'34,37,43', `SSR_C_HEADER`/`SSR_C_STATUS` C'27,30,35', `SSR_C_WELL` C'21,24,28', text C'230,233,238'
over dim C'176,182,192' over faint C'138,144,153', hairlines C'103,111,125', **one** accent
C'224,134,58' (`SSR_C_ACCENT == SSR_C_PRIMARY == SSR_C_PRIMARY_EDGE == SSR_C_BTN_ON`, with one
darker sibling `SSR_C_TRACK_FILL` C'201,109,32' for the speed groove), and a
three-colour state set `SSR_C_RUN` / `SSR_C_HOLD` / `SSR_C_STOP` (`SSR_Theme.mqh:86-136`). There is
nothing to redesign. There is something to **enforce**:

1. **One accent, and it means "the primary action here".** Today `armbtn`, `stmt`, `flat`, `be` and
   the two deal buttons all draw through the same `m_w.Button` default. [RECOMMENDATION] Exactly one
   filled control per sheet (BUY/SELL are one pair and are correctly two); everything else outlined
   on `SSR_C_BTN` with `SSR_C_BTN_EDGE`. The hierarchy is currently flat and that is the single
   biggest "premium" gap, not the colours.
2. **The state trio is for state only.** Green/amber/red never decorate. A coach scanning for red
   must find a rule, never a heading.
3. **Four type sizes exist and four is enough.** TITLE 9 / BODY 8 / SMALL 7 / CLOCK 13
   (`SSR_Theme.mqh:426-429`), one face, Tahoma. Rule: one TITLE per sheet; numbers a coach reads at a
   glance at BODY; labels and units at SMALL on `SSR_C_TEXT_DIM`. Add no size.
4. **Fewer boxes.** `m_w.Group()` draws a titled hairline box; Stats today spends two of them on six
   numbers. A coach sheet is one group plus a rule line, or it is clutter.
5. **Gradients and glow are not a taste question.** [CONFIRMED FROM CODE] `OBJ_RECTANGLE_LABEL` is a
   flat fill plus a one-pixel border; `CSSRWidgets` has `Rect`, `Label`, `Button`, `Edit`, `ButtonC`,
   `Progress`, `Slider`, `Group`, `Meter`, `List`, `Toast` (`SSR_Widgets.mqh:195-612`) and nothing
   that could draw a gradient. The constraint already enforces the aesthetic.
6. **The 63-character discipline becomes a rule, not four call sites.** `Clip()` exists
   (`SSR_Panel.mqh:242`, caps at 62 and marks the cut with `~`) and is used at four sites in a 3049-
   line panel (invariant I4). [RECOMMENDATION] Every new label in this proposal is clipped at
   creation, and `Text()` gains a max-width parameter so the rule is structural. Nine of the register
   entries in L.9 are labels running past their frame, and the `Extent()`/`CheckFrame()` instrument
   cannot see any of them by design (`SSR_Widgets.mqh:125-128`, invariant I10).
7. **Fix `ui-panel-6` before anything else visual.** The status strip's fidelity readout is anchored
   at `x+330` in a 310 px panel: the anchor alone is 20 px past the frame, and `"SYNTHETIC TICK !"`
   adds 70-80 px more. **Roughly 90 px of text sits on the candles on every frame of every session.**
   No amount of palette work reads as premium next to that.

---

### M.8 The cost ledger, honestly

| Item | New code | Risk | Cost |
|---|---|---|---|
| Rail condition glyphs | 5 ids, 5 slots, ~15 lines inside `DrawRail` | none; joins the existing remove-sweep | **XS** |
| Rail rename + reorder | `TabName()` only | `panel.ini` stores `tab` as an index, so an upgrade lands a user on a different sheet **once** | **XS** |
| Delete Session sheet | remove 7 ids, 4 strings, 1 sheet case | frees slots 40-46 | **XS** |
| RISK verdict line | 1 label, 1 slot, 3 strings | re-derive g1/g2 for 245 px | **S** |
| OPEN stop-flag gutter | 12 ids, 12 slots, column re-derivation | multiplies against `ui-panel-1` if that is not fixed first | **S-M** |
| `DailyRoomAfter` + R-room | 2 accessors, 2 wire fields, 2 strings | must live in `CSSRPropEvaluation`, never the panel | **S** |
| Caption chips (TRUST / detached / skew) | 3 chip pairs | **blocked** on `ui-panel-13`: the row already overruns by 6 px | **S** |
| Leak advice → status ladder | 1 ladder level | **blocked** on `chart-7`: the advice is written ~2× what fits | **S** |
| JRNL destination | 4 port verbs + 4 base refusals, 1 sheet, 1 `List`, 1 dispatch branch, ~6 strings | the typed note is contingent on L.4.2 and on `ui-panel-11` | **M** |
| REVIEW rebuild | ~12 wire fields, 1 throttle in `ReadState`, 1 sheet, ~12 strings | **the only real performance decision in the proposal**; behaviour numbers lag ≤2 s | **M-L** |
| i18n for all of the above | ~30 enum ids + 30 `SSRAddString` + 30 `fa.txt` lines; delete 8 orphans, 4 key-hint strings | the catalogue is disciplined and matched by name, so this is mechanical | **M** |

**Prerequisites that are not this proposal's cost but gate it** (all CONFIRMED): L.4.2 settled ·
`ui-panel-3`+`ui-panel-4` (compact strays) · `ui-panel-6` (status off-panel) · `ui-panel-1`
(sheet rebuilt every repaint) · `ui-panel-13` (chip row overrun) · `chart-7` (leak advice length) ·
`ui-dialogs-4` (observation sentences over 63 chars) · `trading-analytics-1`/`-2` (evaluation not
persisted, voided on resume).

[RECOMMENDATION] Build order, cheapest-first and each independently shippable:
**(1)** rail glyphs + rename, **(2)** Session deletion + key-list collapse, **(3)** RISK verdict line
+ OPEN gutter, **(4)** caption chips incl. the detached-chart signal, **(5)** JRNL, **(6)** REVIEW.
Only (6) requires a performance decision, and it is the last thing built.

---

### M.9 What this proposal does not do, and says so

[RECOMMENDATION] Stated so nobody discovers it in a review:

1. **A coach cannot annotate a chart.** `CSSRTradeLines` draws the planning lines and every word it
   draws is a hardcoded English literal (`chart-12`, CONFIRMED). There is no text tool, and adding
   one means a second drag contract on a chart whose first drag contract is unresolved.
2. **There is no second screen.** A coach watching over a student is on the student's terminal. The
   multi-student artefact is `CSSRClassReport`, which is an offline HTML page built from dropped CSV
   files — and it declares UTF-8 while being written `FILE_ANSI`
   (`strategy-integration-report-8`, CONFIRMED, MEDIUM), so a Persian student's name is mojibake in
   the coach's own report.
3. **Auto-pause is still invisible.** M.1 names it as the coaching instrument and this IA does not
   give it a control, because every candidate home is wrong: it is per-session configuration, and the
   configuration surface is pre-session by design (M.2). [FUTURE FEATURE] The honest place is a fifth
   action-strip button, and the action strip has three 96 px cells in 310 px. It does not fit today.
4. **The journal is not persisted.** Bookmarks live in `m_snaps` and the session file writes a
   `[bookmarks]` section per stream — but `ui-port-session-2` (CONFIRMED, HIGH) truncates the previous
   good session before writing the new one, and `ui-port-session-3` (CONFIRMED, HIGH) never checks
   that the streams reached the saved instant. A journal a coach relies on across two days rests on
   both.
5. **Nothing here has been seen on a terminal.** The author has never run this build on MT5. Every
   pixel number is arithmetic over constants, every behaviour claim is source-read, and the glyph
   metrics that decide whether a 44 px rail cell can hold `پوزیشن ۳` (L.3.3) cannot be determined
   from source at all.

---

### M.10 The argument in one paragraph

[INFERENCE] The brief's eight destinations do not fit the rail — eight cells is 197 px inside a
186 px sheet — and two of them (HOME, REPLAY) are the chrome this panel already draws on every
frame, while a third (SETTINGS) would be a third writer to a configuration that two confirmed
findings already show being written behind its own accessors. What a coach needs instead is five
destinations in the order they ask their questions — **RISK · OPEN · REVIEW · CHALLENGE · JOURNAL** —
which is exactly the cell count the rail draws today and exactly `SSR_TAB_MAX`. Four of the five are
the existing sheets, renamed and reordered; one is new and is mostly wiring over bookmark accessors
that already exist. The real work is not the navigation: it is that the four discipline measures and
six behaviour observations this product already computes are locked behind a modal card and an
exported HTML file, and that the rail cannot currently raise its hand when one of them crosses. Fix
those two things and the panel becomes a coaching instrument without gaining a single pixel.

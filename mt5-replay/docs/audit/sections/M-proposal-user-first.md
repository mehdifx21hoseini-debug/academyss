## M. PREMIUM INFORMATION ARCHITECTURE — PROPOSAL 1: USER-FIRST

*Angle: derive navigation from the moments a trainee lives through — setting up, hunting,
in a trade, reviewing — and let the code say which of those moments it can actually serve.
Build v125, `SSR_LAYOUT_RAIL` and `SSR_THEME_RAIL` active. Every pixel figure below is
re-derived from `SSR_Theme.mqh` and the draw sites, not from comments. This proposal keeps
the ten things section L.10 says must survive, and it names its own costs.*

---

### M.0 The one thing that must be settled before any of this is built

[RECOMMENDATION] L.4.2 is a precondition, not a section of this proposal. Whether
`CHARTEVENT_MOUSE_MOVE` reaches `CSSRPanel::OnEvent` decides three of the controls below
(the speed groove drag, the setup tag box, and whether the panel can be dragged at all).
The wiring says it does — `SSR_Panel.mqh:325` executes
`ChartSetInteger(m_chart, CHART_EVENT_MOUSE_MOVE, true)`, `SSReplayStandalone.mq5:3228`
forwards every event, and `SSR_Panel.mqh:2885-2966` handles `CHARTEVENT_MOUSE_MOVE` in full.
The comment at `SSR_Panel.mqh:929-931` says it does not. **This proposal assumes only the
click path**, because that is the assumption that degrades safely: every control described
below is reachable by a click on a named object and by a key, and nothing in it requires a
mouse coordinate. If the mouse path turns out to be live, everything here gains a drag; if it
does not, nothing here stops working.

---

### M.1 The method: four moments, and what the code already believes about them

A trainee's session has four moments. They are not equally long, they are not equally dense,
and — this is the point the current IA misses — **they do not each deserve a destination.**

| Moment | How long it lasts | What the trainee is looking at | What they need from the panel |
|---|---|---|---|
| **Setting up** | once, ~60 s | the wizard, then the orange start line | a decision surface; the chart is not moving yet |
| **Hunting** | 80-95 % of the session | **the candles** | the clock, the transport, the speed — and nothing else |
| **In a trade** | seconds to minutes, repeatedly | the candles *and* their own lines | arm, size, fire, then manage — one continuous act |
| **Reviewing** | once, at the end | the panel and the statement | aggregates, and the reason a trade ended the way it did |

[CONFIRMED FROM CODE] The panel already encodes the single most important consequence of
this table, and says so at `SSR_Panel.mqh:670-674`: compact mode "keeps what is OPERATED —
clock, transport, speed, status — and drops what is only CONSULTED". That sentence is the
whole navigation model. It means the *hunting* moment is served by the permanently visible
band and by nothing else, and that a destination named for hunting would be a destination
nobody ever opens.

[CONFIRMED FROM CODE] The current rail is a **noun taxonomy**, not a moment taxonomy:
`SSR_TAB_TRADE 0, SSR_TAB_POSITIONS 1, SSR_TAB_STATS 2, SSR_TAB_SESSION 3, SSR_TAB_PROP 4`
(`SSR_Theme.mqh`, listed in `ui-plumbing.md` §3). Mapped onto the moments, it misallocates
in three places:

1. **Trade and Positions are one moment split across two destinations.** Arming a trade and
   managing it are the same act, seconds apart, and the trainee must find and click a 44 x 22
   rail cell in between — at the exact moment their eyes are on the candles.
2. **Stats is not about the trainee's performance.** [CONFIRMED FROM CODE] `SheetStats`
   (`SSR_Panel.mqh:1671-1748`) draws seven things: balance, equity, floating, bars consumed,
   ticks emitted, rejected/guard counts, and the statement button. Three of those are
   account readouts that the status strip already carries (`stbal`, `stflt` at
   `SSR_Panel.mqh:1915-2035`); three are **engine telemetry**. Not one trading statistic —
   no win rate, no expectancy, no drawdown — appears on the destination named "Stats". The
   trading-analytics map states the reason plainly: "The panel Stats tab does **not** use
   [`CSSRStatsEngine`] (it reads balance/equity/floating from the port model)"
   (`trading-analytics.md` §3, Callers).
3. **Session is a junk drawer.** [CONFIRMED FROM CODE] `SheetSession`
   (`SSR_Panel.mqh:1877-1908`) draws a bookmark count, a streams/skew line, the chart-leak
   advice, and then **four lines of keyboard help** (`ses4`, `keyhint`, `ses5`, `ses6`).
   Three of the four are factually wrong (L.2.3, `ui-plumbing-2` CONFIRMED). A keyboard guide
   is not a session control, and the sheet uses only 140 of its 186 px to hold both.

[INFERENCE] So the redesign is not a re-count of tabs. It is: give the *in a trade* moment
one continuous surface, give *reviewing* a destination that actually reviews, empty the junk
drawer, and leave *hunting* exactly where it is — in the band that never goes away.

---

### M.2 Why not the brief's eight destinations

The brief proposes HOME / REPLAY / TRADE / POSITIONS / PERFORMANCE / CHALLENGE / JOURNAL /
SETTINGS and asks for reasoning either way. Four of the eight survive. Four do not, and two
of the refusals are arithmetic rather than taste.

**The rail cannot hold eight.** [CONFIRMED FROM CODE] `DrawRail` (`SSR_Panel.mqh:1209-1225`)
draws `n` cells of `h = 22` with `gp = 3`, i.e. `n*22 + (n-1)*3` px, inside the sheet band of
`SSR_SHEET_H 186`:

```
n = 5   5*22 + 4*3 = 122      shipping today, 64 px spare
n = 7   7*22 + 6*3 = 172      fits, 14 px spare
n = 8   8*22 + 7*3 = 197      overflows the sheet by 11 px, onto the status strip
```

Seven is the hard ceiling of the 310 px rail layout; eight does not fit at all. And
[CONFIRMED FROM CODE] the rail is drawn at `DrawRail(x+8, cy+4)` with the sheet beside it at
`DrawSheet(x+8+44+5, cy+4, 245)` (`SSR_Panel.mqh:751-752`), so an over-long rail does not
push anything — it simply paints two cells on top of the status strip, and
`CheckFrame()` would see it (rail cells are `ButtonC`, i.e. sized objects, so unlike the
label overflows of L.9 this one *is* visible to the instrument — `SSR_Widgets.mqh:125-128`,
invariant I10).

**HOME is already on screen and never leaves it.** [CONFIRMED FROM CODE] The caption
(identity, build tag, run state, mode chips), the clock + progress bar, the transport row,
the speed row and the status strip are drawn on **every** frame, above the rail, and survive
compact mode by design (`SSR_Panel.mqh:679-765`). A HOME destination would duplicate the one
part of the panel that cannot be navigated away from. Reject.

**REPLAY is the same objection.** Transport and speed are the band. What genuinely has no
home is a small set of *replay actions* whose buttons v125 removed — Jump, Bookmark, Follow
— plus two port verbs that never had one (§M.5.4). Those are five controls, not a
destination; they belong on SESSION, where a trainee already goes to change where they are
in history.

**SETTINGS cannot be built.** [CONFIRMED FROM CODE] `SSRSetupValues` covers **14** of the
expert's 61 inputs (`ui-dialogs.md` §1), the wizard that edits them exists only in the
picking phase before `BuildSession`, and the 14 are read once through the host's `Cfg*()`
accessors at session construction (`SSReplayStandalone.mq5:224-241`). Changing any of them
mid-session means rebuilding the session. The settings that *are* live mid-session are risk %
(Trade sheet), trailing points (Positions sheet), speed (band), and fidelity (action strip) —
four controls that each sit in the moment that uses them, which is where a user-first model
wants them anyway. A SETTINGS destination would be two live controls and forty-seven
read-only strings. Reject; keep each control in its moment.

**JOURNAL has no drawable form.** [CONFIRMED FROM CODE] `CSSRJournal` produces a CSV and an
HTML statement on disk (`trading-analytics.md` §4). MQL5 draws four object types and has no
table, no scrollbar and no clipping; the widest list primitive in the product is
`CSSRWidgets::List` — a windowed 8-row list the caller pages (`ui-plumbing.md` §2), which is
what `CSSRSessionDialog` and `CSSRPalette` use. That is enough for a bookmark list; it is not
a journal. Reject as a destination, and instead (a) keep the statement export where the
moment is — on PERFORMANCE, which is `SheetStats`' existing `stmt` button
(`SSR_Panel.mqh:1702`), and (b) add the one journal-shaped thing that is genuinely missing
and genuinely drawable: the **closed trades** the trainee just took (§M.5.2).

**TRADE, POSITIONS, PERFORMANCE, CHALLENGE survive.** They are the brief's four that map
onto real moments and real code. The proposal keeps all four and adds SESSION back — not as
the junk drawer it is, but as the "move me somewhere else in history" destination, which is
the *setting up* moment recurring mid-session.

[INFERENCE] Net: the brief's instinct is right and its count is wrong. The information
architecture problem in this product is not that there are too few destinations. It is that
two destinations hold one moment, one destination holds no statistics, and one holds a
keyboard guide.

---

### M.3 The navigation model

Three layers, and the names are the ones the code already uses.

```
┌─ THE BAND ─────────────────────────────────── always drawn, never navigable ─┐
│  caption   23   identity · build · run state · mode chips · [-] [X]          │
│  clock     32   masked clock · progress · pause reason                        │
│  transport 27   |<  <<  <  [ PLAY/PAUSE 91 ]  >  >>      ···  Reset 58        │
│  speed     21   label  -  value  +  [20-cell groove 130]  meaning             │
├─ THE ACTION STRIP ── 21 ── three always-reachable verbs ──────────────────────┤
│  Lines          Sessions          Fidelity                                    │
├─ THE RAIL ── 44 ──┬─ THE SHEET ── 245 x 186 (326 expanded) ───────────────────┤
│  Trade            │                                                            │
│  Pos n            │   one destination at a time                                │
│  Perf             │                                                            │
│  Sess             │                                                            │
│  Prop*            │   * only while an evaluation is configured                 │
├───────────────────┴────────────────────────────────────────────────────────────┤
│  STATUS  18   balance │ float │ n open │ spread │ fidelity   ← becomes NAVIGATION│
└────────────────────────────────────────────────────────────────────────────────┘
        overlays, drawn last, creation order is z-order:
        key card (H) · palette (Ctrl+K) · range dialog (J) · session dialog (S)
        · review card (A) · reveal card · fill toast
```

Five destinations, four permanent. That is `TabCount()` unchanged
(`SSR_Panel.mqh:1103`: 5 when `m_state.prop_on`, 4 otherwise) — **no new rail cell, no new
rail string, no change to the 122 px the rail occupies, and no change to `SSR_TAB_MAX`.**
The IA change is in what three of the five hold, and in one new navigation mechanic.

#### M.3.1 The new mechanic: the status strip is the navigation

[CONFIRMED FROM CODE] `DrawStatus` (`SSR_Panel.mqh:1915-2035`) already draws, permanently,
the five numbers a trainee glances at: `stbal` at `x+8`, `stflt` at `x+116`, `stopen` at
`x+218`, `stspread` at `x+268`, `stfid` at `x+330`. Three of them are the *headline* of a
destination: balance/float → PERFORMANCE, `n open` → POSITIONS, fidelity → the Fidelity
action.

[RECOMMENDATION] Draw `stbal`, `stopen` and `stfid` as flat `ButtonC`s with
`SSR_C_STATUS` as both background and edge — visually identical to the labels they replace,
because the status strip's own plate is that colour — and dispatch them:

```
Dispatch("stopen") -> m_tab = SSR_TAB_POSITIONS ; SavePlace()
Dispatch("stbal")  -> m_tab = SSR_TAB_PERF      ; SavePlace()
Dispatch("stfid")  -> SSR_CMD_FIDELITY_CYCLE           (the verb already exists)
```

Cost and benefit, honestly:

* **Zero new pixels and zero new rows.** This is the only navigation in the proposal that
  costs no layout.
* [CONFIRMED FROM CODE] It fixes the *in a trade* discontinuity: a trainee who has just
  fired an order sees `n open` change in the strip and can reach the management surface by
  clicking the number that changed, without hunting for a rail cell.
* [CONFIRMED FROM CODE] **It makes the status strip visible to the overflow instrument.**
  `Extent()` covers sized objects only and excludes labels by design
  (`SSR_Widgets.mqh:125-128`, invariant I10) — which is exactly why nothing has ever reported
  `ui-panel-6`, the fidelity readout anchored at `x+330` in a 310 px panel. As a `ButtonC`
  it enters `m_max_r`, and `CheckFrame(x,y,W,H)` (`SSR_Panel.mqh:765`) reports it on the
  first frame.
* **Cost: paint budget.** `ButtonC` is 9 property writes against `Label`'s 6
  (`ui-plumbing.md` §10.3), so three promoted readouts cost +9 writes per *changed* frame.
  The widget cache elides unchanged frames, but `stbal` and `stflt` change on every tick of
  a live position, so this is a real +9 on the frames that already write the most.
* **Cost: latch discipline.** `PollClicks()` walks every `OBJ_BUTTON` with the prefix
  (`SSR_Panel.mqh:2445`); three more buttons is three more names per poll, and each needs a
  `Dispatch` arm before the fall-through at step 8 that hands unknown names to
  `TradeButton()`. Miss that and a click on the balance becomes a trade button lookup.
* **Cost: the ladder.** Status levels 1-4 write slot 50 / id `stbal` and hide the other four
  (`SSR_Panel.mqh` §9). If `stbal` is a button, the reset confirmation and the trade refusal
  are drawn *on a clickable control*. [RECOMMENDATION] Levels 1-4 must `Remove("stbal")` and
  draw the message into a separate label id (`stmsg`), not reuse the button's id — otherwise
  the one destructive question in the product is a button that navigates.

[INFERENCE] This last cost is the reason to treat the mechanic as a small, separately
testable change rather than a free win. It is still the best value in this proposal: one
existing row, no new pixels, and it retires the blind spot that hid `ui-panel-6`.

#### M.3.2 What does *not* change

[RECOMMENDATION] Preserve verbatim, for the reasons L.10 gives: latch polling as the one
click mechanism; the single generated key table; the status ladder's priority order; "removed,
not merely undrawn" (I7); modes as chips rather than colours; operated-vs-consulted as the
compact rule; the wish/fact split for tall mode; `TabCount()` as a question; `Clip()` and the
63-character discipline; and the 310-vs-420 and three-palette compile switches. Nothing in
this proposal touches any of them.

---

### M.4 The destinations, one by one

#### M.4.1 TRADE — "I am about to be in a trade"

**Holds** (unchanged from `SheetTrade`, `SSR_Panel.mqh:1346-1508`): the risk ladder with its
money read-back, the setup tag box, the stop/target group with side / stop / target / RR /
size read-back and the `order_why` refusal, the one primary button that *says what it will
do*, `Flip` / `Entry line` / `Remove`, and the two deal buttons with the wrong side dimmed.

**Maps onto**: `SheetTrade` entirely. `TradeButton()` (`:2108`), `StepRisk()` (`:2144`),
`Dispatch` arms `armbtn/flipbtn/enbtn/clrbtn/openln/buy/sell/riskdn/riskup`.

**Vertical budget today** [CONFIRMED FROM CODE]: risk group 36 (`y..y+36`), tag row
`y+38..y+56`, stop/target group at `gy = y+60` height 92 (`..y+152`), deal buttons at
`dy = gy+96 = y+156` height 24 (`..y+180`). **180 of 186 — six pixels spare.** There is no
room on this sheet for anything new, and the proposal adds nothing to it.

**New**: nothing. **Removed**: nothing.

**Cost**: zero. This is the one sheet in the product that already serves its moment, and the
comment at `SSR_Panel.mqh:1380-1385` ("a stop typed in points is chosen by arithmetic; a stop
dragged on the chart is chosen by structure, and structure is the entire reason a person
practises on a replay") is the strongest product reasoning in the codebase. Do not touch it.

[POTENTIAL_RISK] `ui-panel-11` — the tag box is hidden and re-shown at `SSR_Panel.mqh:1376`
ten times a second while it may hold the keyboard. Unresolved, and it depends on M.0.

#### M.4.2 POSITIONS — "I am in a trade"

**Holds today** (`SheetPositions`, `SSR_Panel.mqh:1509-1670`): 5 rows standard / 12 expanded,
each with per-row `H` (halve) / `B` (break-even) / `X` (close), the `poshint` legend, the
`posmore` overflow counter, `Break-even all` / `Close all`, and the trailing ladder.

**Maps onto**: `SheetPositions`, `PosCap()`, `PosGroupH()`, `StepTrail()`, `Dispatch`'s
`p{x|h|b}<digits>` / `trdn` / `trup` / `troff` / `be` / `flat` arms — all unchanged.

**New — the one genuinely new surface in this proposal: a Closed page.**

[CONFIRMED FROM CODE] A trainee cannot see the trade they just closed. The wire's position
rows are open and pending only (`SSRUiState.pos_*`, six parallel arrays of `SSR_POS_MAX 12`,
filled by `CSSRGroupPort::ReadState` from `m_acct`, `ui-port-session.md` §2.2/§3.3). Closed
trades exist only in the exported CSV/HTML (`CSSRJournal`) and as 43 *aggregate* measures on
the review card (`SSRReviewRows` returns 43 rows, `ui-dialogs.md` §5). Between the fill toast
(4 s, `SSR_Panel.mqh:787-803`) and the end-of-session review card, **the record of an
individual trade is unreachable**. For a training product that is the wrong gap to have.

[RECOMMENDATION] Add an Open / Closed toggle to the Positions sheet, reusing the row grammar
exactly: ticket-or-tag, side, size, and the closed net in place of the floating P/L, newest
first, `PosCap()` rows, same paging story as `posmore`.

Honest cost, itemised:

* **Wire growth.** Six more parallel arrays of 12 on `SSRUiState`, or a `pos_closed[]` flag
  plus a second `closed_rows` count. The wire is deliberately flat and pointer-free
  (`ui-port-session.md` §2.2) so this is additive and cheap to fill, but it is not free:
  `SSRUiState::Init()` clears every field in one loop (`SSR_ReplayPort.mqh:238`) and that
  loop grows.
* **Fill cost.** `CSSRGroupPort` must walk closed positions. [CONFIRMED FROM CODE] the
  engine stores positions in slot order and `At(i, SSRVirtualPosition&)` is "a full struct
  copy, ~660 B + two strings per call" (`trading-analytics.md` preamble). Walking to find the
  newest 12 closed trades is O(Total()) struct copies **per `ReadState`, i.e. 10 times a
  second**. That is the single largest runtime cost in this proposal and it must be capped
  — cheapest correct answer: fill the closed rows only when `m_tab == SSR_TAB_POSITIONS`,
  which the port cannot know. [RECOMMENDATION] Add one setter, `CSSRGroupPort::WantClosed(bool)`,
  called by the panel on a tab change — the same shape as the existing `SetTpPoints` /
  `NoteLineDistances` host-only setters, so it costs no new pattern.
* **Layout.** The toggle needs 19 px the sheet does not have. Positions uses 183 of 186
  today (group 134 → `y+134`; `be`/`flat` at `by = y+138` height 22 → `y+160`; trailing row
  at `ty = y+164` height 19 → `y+183`). Two options, both with a price:
  - **(a)** make the existing two-button row three: `Open/Closed` · `BE all` · `Close all`,
    `bw = (245-2*5)/3 = 78 px`. Costs no height. Risk: `T(SSR_S_BREAK_EVEN_ALL)` in 78 px is
    unclipped and MetaTrader draws 63 characters with no clipping (invariant I4) — and the
    Persian catalogue is already the tighter case (`fa.txt`, `ui-plumbing.md` §9). This
    trades a layout defect for a typography one.
  - **(b)** take 19 px from the position group, `PosGroupH() 134 → 115`, which drops
    `PosCap()` from `(134-22)/20 = 5` to `(115-22)/20 = 4` in Standard and from 12 to 11 in
    Expanded. **One fewer visible position in Standard** is a real regression for the moment
    this destination exists to serve.
  [RECOMMENDATION] Prefer (a), and shorten the two labels in the catalogue rather than
  clipping at the draw site — the strings are already the shortest-lived part of the design.
* **The `posmore` collision.** [INFERENCE, POTENTIAL_RISK] Adding a Closed page does not fix
  the overflow counter's position; `posmore` at `x+w-92 = x+153` still shares a baseline with
  `poshint` drawn from `x+8` (L.3.2). Re-derive both for 245 px as part of this work or the
  new page inherits the defect.

**Removed**: nothing. **Precondition**: `ui-panel-7` (CONFIRMED, MEDIUM) — the note column at
`x+120` and the money column at `x+w-116 = x+129` give nine pixels to a nine-character note.
The Closed page reuses that row; fix the row first or build the defect twice.

#### M.4.3 PERFORMANCE — "how did I actually do"

**Holds today** (`SheetStats`): balance, equity, floating, bars, ticks, rejected/guard,
`stmt`, and a pointer to the Prop tab.

**Holds in this proposal**: the measures a trainee can act on, read from the engine that
already computes them —

```
Group "Result"      trades  n          win rate  nn %        net  ±nnnn.nn
Group "Risk"        expectancy  ±n.nn R           max drawdown  nnnn.nn (nn.n %)
                    profit factor  n.nn  /  "-"   R trades  a of b
[ Save statement ]                                [ Full review ]
```

**Maps onto**: `SSRStatistics` and `CSSRStatsEngine::Compute` (`SSR_Statistics.mqh:209-717`),
already computed for the review card and the journal; the `stmt` button
(`SSR_Panel.mqh:1702`) unchanged; `Full review` is `SSR_CMD_REVIEW`, which already exists,
is bound to `A`, and is host-owned (`Owns()` returns false for `REVIEW`,
`SSR_Panel.mqh:2165`) so the button simply returns the command from `PollClicks()` like
`SESSIONS` and `JUMP` do — **no new dispatch path**.

**New**: eight wire fields on `SSRUiState`, filled by `CSSRGroupPort::ReadState` from the
stats engine it does not yet hold.

Honest cost, itemised:

* **A new attachment.** `CSSRGroupPort` already holds `m_stats` — [CONFIRMED FROM CODE]
  `AttachStats` exists (`ui-port-session.md` §3.2) and `m_stats` is listed among its
  non-owned collaborators. So the pointer is there; only the read is new. That is a genuinely
  cheap start.
* **The compute cost is not cheap.** [CONFIRMED FROM CODE] `ComputeFor` is "up to 3 passes
  over `Total()` slots with a struct copy each + O(4096) drawdown walk"
  (`trading-analytics.md` §3, Cost). `ReadState` runs once per repaint, ≥100 ms apart
  (`ui-panel.md` §3), i.e. up to 10 Hz. Running a three-pass statistics computation at 10 Hz
  against up to `SSR_MAX_POSITIONS 512` slots, while the replay is pumping ticks, is the
  largest new load this proposal creates. [RECOMMENDATION] Compute on a change-count trigger
  — `m_acct.ClosedCount()` is O(1) and a closed-trade count that has not moved cannot change
  any of the eight measures except drawdown. Recompute when `ClosedCount()` changes or every
  2 s, whichever comes first, and cache the struct in the port.
* **Two semantics that must not be flattened.** [CONFIRMED FROM CODE] `profit_factor`
  "stays 0.0 when `gross_loss == 0`" — undefined, and "caller must read `losses`"
  (`SSR_Statistics.mqh:529-530`). And `average_r` is computed only over trades with
  `risk_at_entry > 0`, which is why `r_trades` is reported as "a of b"
  (`trading-analytics.md` §1). A sheet that prints `PF 0.00` for a flawless session, or
  `expectancy +1.2R` from three of nineteen trades, is worse than the telemetry it replaced.
  Draw `-` for undefined PF and always print the `a of b`.
* [CONFIRMED FROM CODE] `IsTrustworthy()` = `trades > 0 && ambiguous_pct <= 10`, and
  `Caveat()` builds the sentence. An untrustworthy set of numbers must carry its caveat on
  this sheet, not only in the HTML. One `Clip()`ed line at the foot, `SSR_C_HOLD`.

**Removed**: `st1`/`st2`/`st3` (balance, equity, floating) — [CONFIRMED FROM CODE] balance and
floating are already on the status strip at `stbal` and `stflt`, permanently, in every mode
including compact. Equity is derivable and less useful than the drawdown it feeds.
The telemetry rows `st4`/`st5`/`st6` (bars, ticks, rejected/guard) move to SESSION §M.4.4 —
they are session-health diagnostics, and that is where the other three
(`streams`, `skew`, `leak`) already live.

**Vertical budget**: two groups of 68 with a 4 px gap = 140, plus a 22 px button row at
`y+146` = 168, plus a caveat line at `y+170` ≈ 180 of 186. Same shape as today's Stats
sheet, six pixels spare. In Expanded (326) a third group fits with room for by-setup rows,
which `CSSRStatsEngine::ComputeFor(tag, out)` already supports — [FUTURE FEATURE], not part
of this proposal's cost.

#### M.4.4 SESSION — "put me somewhere else, and tell me the session is healthy"

**Holds today**: bookmark count, streams/skew, leak advice, four wrong keyboard lines. Uses
140 of 186 px.

**Holds in this proposal**:

```
Group "Where"       [ Jump… ]     [ Sessions… ]     [ Mark here ]
                    bookmarks   n            list of the last 4 (8 in Expanded)
                    [ Save position ]   [ Resume position ]
Group "Health"      streams  n    skew  n ms       charts  clean | <advice>
                    bars  n       ticks  n         rejected  n   guard  n
```

**Maps onto**: `SheetSession` rewritten; `SSR_CMD_JUMP` and `SSR_CMD_SESSIONS` are host-owned
commands that already exist and already have palette entries (`SSR_Command.mqh`, Session
group); `SSR_CMD_BOOKMARK` exists and is bound to `B`; `CSSRWidgets::List` provides the
windowed, paged bookmark list with the same `first`/`shown`/`selected` contract the session
dialog uses (`ui-plumbing.md` §2).

**New**:

* **`Jump…` and `Mark here` get buttons back.** [CONFIRMED FROM CODE] v125 removed the
  `jump` and `bookmark` buttons from the action strip and they are `Remove()`d on every frame
  at `SSR_Panel.mqh:1241-1243`; the commands survive on `J` and `B`. Putting them on SESSION
  restores the affordance **without** re-adding a button to the always-visible band — which
  is what the removal was for. The eight orphan strings of L.4.5 (`SSR_S_BOOKMARK`,
  `SSR_S_JUMP`, `SSR_S_ACT_BOOKMARK`, `SSR_S_ACT_JUMP` …) get draw sites again, or are
  retired; either way `SSRTranslated()` stops reporting 190/190 for a catalogue with eight
  unreachable strings.
* **Save / Resume position get a surface for the first time.** [CONFIRMED FROM CODE]
  `CSSRGroupPort::SavePosition` and `ResumePosition` are implemented overrides
  (`SSR_GroupPort.mqh:495, 506`) and a grep over `MQL5/` outside `Tests/` and `QA/` finds
  **no UI caller** — no panel button, no `Dispatch` arm, no key in `SSRKeyBindings()`, no
  entry in `SSRCommands()`. The host calls `g_ctrl.SavePosition()` directly at
  `SSReplayStandalone.mq5:2145`. The wire carries `has_saved_position` and `checkpoints` and
  [CONFIRMED FROM CODE] both are listed among the fields "written by `CSSRGroupPort` but read
  by no consumer" (`ui-port-session.md` §2.2). Two working verbs and two wire fields become
  a two-button row: `Resume position` enabled from `has_saved_position`, and the checkpoint
  count beside it. Cost: two `Dispatch` arms and two `Button` calls.
* **The bookmark list.** Today the panel draws only `bookmarks n`. A trainee who marked six
  moments cannot see or return to any of them. [POTENTIAL_RISK / cost] The port has no verb
  for "list bookmarks" or "go to bookmark i" — `Bookmark(label)` writes one
  (`SSR_GroupPort.mqh:490`, which also draws the chart mark via `MarkTime`). So the list
  needs **two new port verbs** and wire rows for the labels. That is the second-largest cost
  in this proposal and the most deferrable: ship the two buttons and the count first, add the
  list when the verbs exist. [RECOMMENDATION] Stage it.

**Removed**:

* **All four keyboard lines** — `ses4`, `keyhint`, `ses5`, `ses6`, i.e. `T(SSR_S_KEYS_1..4)`.
  [CONFIRMED FROM CODE] three of the four are wrong: `keys.2` says "R reset" while `R` is
  `SSR_CMD_LINES_TOGGLE` (`SSR_Keys.mqh:162`) and reset is `0` (`:200`) — `ui-plumbing-2`;
  `keys.4` teaches the `[]` caption button that was deleted at `SSR_Panel.mqh:934`;
  `keys.3` names `F follow`, which has no other surface. The product already has **one
  generated key list** whose height is counted from the table rather than chosen
  (`CSSRKeyCard`, `ui-plumbing.md` §8) and which "cannot drift from the handler". Deleting
  the four hand-written lines and pointing at the card is the whole fix. Retire
  `SSR_S_KEYS_1..4` from the catalogue and `fa.txt` with them.
* This frees **72 px** on the sheet (the `g2` group at `y+72`, height 68, plus its 4 px gap),
  taking SESSION from 140 px of 186 used to 68 — enough for everything above without
  touching Expanded.

**Precondition, and it is not optional.** [CONFIRMED FROM CODE] `host-expert-7` (CONFIRMED,
MEDIUM): `CSSRRangeDialog::OnEvent` and `CSSRSessionDialog::OnEvent` return `false` for every
non-click event, so keys fall through both dialog blocks into `g_panel.OnEvent` at
`SSReplayStandalone.mq5:3228` — **Space starts the replay, `Tab` opens a virtual trade and
`0` arms the session reset while the user is reading a modal dialog**, and the panel's
`Render()` then repaints over it. Promoting `Jump…` and `Sessions…` to a destination makes
those two dialogs the *normal* way into this moment rather than a key nobody presses.
`CSSRReviewCard::OnKey` already shows the fix — it returns `true` for every key while up
(`ui-dialogs.md` §4). Copy it, or this destination increases exposure to a confirmed defect.

#### M.4.5 PROP — "am I still in the challenge"

**Holds**: unchanged. Verdict line, the clipped rules recap, four meters with their numbers
beside them, the optional deadline line, the headline and the conditional reset.

**Maps onto**: `SheetProp` (`SSR_Panel.mqh:1749-1854`, with `PropRow` at `:1858-1872`) and the sixteen pre-clamped `prop_*`
wire fields, verbatim.

**New**: nothing. **Removed**: nothing.

[RECOMMENDATION] Keep it exactly as written, including the reasoning at `:1732-1748`
("THIS SHEET COMPUTES NOTHING… A meter worked out here could read 'safe' in the frame the
evaluation reads 'failed', and the trader would believe the bar") and the rule that every
meter carries its number in text because "a bar is unreadable to a colour-blind trader,
illegible in a screenshot". These are the two best sentences in the product's UI and they are
also the two rules the rest of this proposal is measured against.

[CONFIRMED FROM CODE] Its worst case is 178 of 186 px (four rows at 25, plus deadline 14,
plus headline 16, plus reset) — the tightest sheet in the panel. Nothing may be added to it.

[INFERENCE] The brief's CHALLENGE is this destination, already built and already correct.
Renaming it would cost fourteen catalogue strings and gain nothing; the code's word is
*evaluation* and the rail's short form is `Prop`. Preserve both.

---

### M.5 What is new, what is removed, consolidated

**New (six items, ordered by value per unit of cost):**

| # | New | Cost |
|---|---|---|
| 1 | Status-strip readouts become navigation (`stbal` → PERF, `stopen` → POS, `stfid` → fidelity) | 0 px; +9 writes/changed frame; 3 `Dispatch` arms; ladder levels 1-4 must stop reusing the `stbal` id |
| 2 | A caption chip for detached charts (§M.6) | ~34 px in a chip row that already overruns by 6 (`ui-panel-13`) |
| 3 | `Jump…`, `Mark here`, `Save/Resume position` on SESSION | 4 buttons, 4 `Dispatch` arms; 72 px freed by the keyboard lines pays for all of them |
| 4 | PERFORMANCE reads real statistics | 8 wire fields; a throttled `Compute` in the port; two semantics that must not be flattened |
| 5 | A Closed page on POSITIONS | 6 wire arrays; an O(Total()) fill that must be gated by a `WantClosed` setter; 19 px or one position row |
| 6 | A bookmark list on SESSION | 2 new port verbs + wire rows. Defer; ship the count and the buttons first |

**Removed (five items):**

1. `SheetSession`'s four keyboard lines and `SSR_S_KEYS_1..4` — the key card is the one list.
2. `SheetStats`' balance/equity/floating rows — duplicated by the permanently visible strip.
3. The eight orphan `SSR_S_*FOLLOW/BOOKMARK/JUMP` strings (L.4.5) — three regain draw sites,
   five are retired.
4. `data_mode` from the wire (`ui-port-session-16`, CONFIRMED) — written by nobody, read by
   nobody.
5. Nine permanent `m_w.Remove()` calls for v124 ids (`SSR_Panel.mqh:932-934`, `:1189-1191`,
   `:1241-1243`) — correct on the upgrade frame, dead weight on every frame since. Move them
   behind a one-shot flag set in `Create()`.

**Unchanged and deliberately so:** the band, the action strip, `TabCount()`, the rail
geometry, `SheetTrade`, `SheetProp`, the key table, the latch poll, the palette, the four
responsive modes, and both compile switches.

---

### M.6 The one piece of information v125 lost, and how it comes back

[CONFIRMED FROM CODE] `chart-10` (CONFIRMED, LOW): `charts_detached` is written on the wire
by `CSSRGroupPort` from `CSSRChartManager::DetachedCount()` (`SSR_GroupPort.mqh:122`) and
read by **no draw site** — a grep over `SSR_Panel.mqh` matches only the struct declaration,
`Init()` and the assignment. The removed `Follow` button carried the count in its own label
and lit when non-zero, and the commit body names the loss: *"Nothing else on the panel says
that now."* The user-visible outcome is the worst kind: **the replay advances, the candles
stop moving, and the interface says nothing at all.** The recovery is `F`, a key with no
button, named on one line of a hint block this proposal deletes.

[RECOMMENDATION] Bring it back as a **caption chip**, not a button. The caption already lays
chips out left to right from `cx = x + 140`, each reporting the width it took so that "adding
a mode later moves the next chip instead of landing on top of it"
(`SSR_Panel.mqh:887-906`) — the mechanism is built and the chips are already the product's
answer to "a mode carried by colour alone is a mode a colour-blind trader cannot read"
(`:860-862`). A `chfollow` chip drawn only when `charts_detached > 0`, in `SSR_C_HOLD`,
reading `"DETACHED n"`, is one line of code in an existing loop.

**Honest cost**: [CONFIRMED FROM CODE] `ui-panel-13` — the chip row already ends at `x+274`
when fidelity is degraded, and `collapse` starts at `x+W-42 = x+268`. A fourth chip makes a
6 px overrun worse, in the worst case by its full width. It cannot simply be added. Two ways
to pay, neither free:

* Drop the `PROP` chip when the Prop rail cell is visible — [INFERENCE] the rail cell already
  says an evaluation is configured, and it is a bigger, more legible signal. This is the
  cheaper trade and it removes a redundancy.
* Or move `collapse`/`close` into the rail's spare 64 px, which is a larger change and moves
  two controls users already know.

[RECOMMENDATION] Take the first, and note it in the caption comment block the way v125 noted
what each removed button cost — that record is the reason this loss was findable at all.

---

### M.7 Compact / Standard / Expanded

The product has **four** responsive modes, not three, and one of them is a trap that must be
fixed before any of this ships. [CONFIRMED FROM CODE] `SSR_Panel.mqh:679-714`: `m_compact` is
*measured* (chart < 360 px) and never chosen; `m_tall` is a *wish* (`P`, persisted) whose
*fact* is recomputed each frame with the refusal surfaced and both numbers named;
`m_collapsed` is persisted; `m_closed` is not and leaves one `reopen` button "because a
control that removes its own only way back is a trap" (`:641-647`).

| | **Compact** (`m_compact`, chart < 360) | **Standard** (336 px) | **Expanded** (`m_tall`, chart ≥ 500) |
|---|---|---|---|
| height | 128 | 336 | 476 |
| sheet | none | 245 x 186 | 245 x 326 |
| band | caption · clock · transport · speed · status | same | same |
| rail | hidden | 5 cells, 122 px | 5 cells, 122 px (64 px spare) |
| **TRADE** | — | full, 180/186 | full + room for a second setup read-back row [FUTURE] |
| **POSITIONS** | — | `PosCap() = 5` (or 4 with the toggle) | `PosCap() = 12` (11 with the toggle) |
| **PERFORMANCE** | — | 2 groups + buttons + caveat | 3 groups; by-setup rows fit [FUTURE] |
| **SESSION** | — | Where + Health; bookmark list shows 4 | bookmark list shows 8 |
| **PROP** | — | 178/186 worst case | unchanged; the spare is slack, not content |
| navigation | **the status strip is the only navigation** | rail + status strip | rail + status strip |
| overlays | all still available (key card, palette, dialogs) | same | same |

Two things this table depends on, and both are defects to fix first:

* [CONFIRMED FROM CODE] `ui-panel-3` (CONFIRMED, **HIGH**) — `HideSheetArea(true)` at `:682`
  is undone by `HideBody(false)` at `:729` **inside the same `Render()`**, so compact mode
  leaves up to 122 px of still-clickable rail and the three action buttons painted on the
  candles below a 128 px panel. Making the status strip the compact-mode navigation is only
  honest if compact mode actually drops the rail. Fix order, then add `tab4` to the id list
  (`ui-panel-4`, CONFIRMED, LOW).
* [CONFIRMED FROM CODE] `ui-panel-10` (CONFIRMED, MEDIUM) — in compact the fill toast is
  placed at `y + 128 - 18 - 24 = y+86`, height 20, directly on the speed row
  (`y+82..y+101`) and *above* it in creation order, for four seconds per fill. Compact is the
  mode in which the speed control is one of four things left.

[CONFIRMED FROM CODE] There is deliberately **no** narrow-width degradation, and the reason is
written at `SSR_Panel.mqh:484-499`: "there is no width at which they all still clear each
other… the thing that would have to be dropped is half of every row." `TooNarrow()` reports
the condition on the status strip instead. [RECOMMENDATION] Keep that. A product with no
layout engine that tries to reflow will reflow wrongly and silently.

[CONFIRMED FROM CODE] One gap this proposal does not close: the `m_closed` branch at
`:649-655` returns **before** `ClampToChart` runs at `:716`, so a chart resized while the
panel is closed can leave the 76 x 20 `reopen` button — the only way back — outside the
visible area. Low severity, but it defeats the stated contract and is two lines.

---

### M.8 The visual system

Dark, premium, minimal, dense. The tokens for this already exist and the discipline around
them is real: [CONFIRMED FROM CODE] `SSR_Theme.mqh` is the only file allowed to contain a
colour (audit A17), the three palettes define exactly the same 51 `SSR_C_*` tokens, and 49
machine-readable `//--- SSR_CONTRAST:` lines hold whichever palette is built to 4.5:1 for text
and 3.0:1 for UI (`ui-plumbing.md` §3). Do not add a token. Two are already drawn by nothing
(`SSR_C_THUMB_EDGE`, `SSR_C_TICK` — `ui-plumbing-9`, CONFIRMED, IMPROVEMENT); spend those
before minting more.

**Hierarchy — one primary per surface.** [CONFIRMED FROM CODE] The transport row already
states the rule and the reason: "the primary action is five times the width of a step and the
only blue thing in the row… and Reset is pushed off to the right across a gap four times wider
than the others" (`SSR_Panel.mqh:978-990`; `sepw = 10` at `:998` against `gp = 3`).
[RECOMMENDATION] Extend it verbatim, one sheet at a time:

| Surface | Primary (exactly one) | Secondary | Destructive — never primary, always separated |
|---|---|---|---|
| band | `toggle` (PLAY/PAUSE, 91 px) | steps | `reset` (58 px, behind a 10 px gap, armed twice) |
| TRADE | `openln` — and it says what it will do | `flipbtn` `enbtn` `clrbtn`, `riskdn/up` | `buy` `sell` are deal-coloured, not primary |
| POSITIONS | none — management is not a primary act | row `H` `B`, `be`, the trailing ladder | `flat` (Close all), `X` per row |
| PERFORMANCE | `stmt` | `Full review` | none |
| SESSION | none | `Jump…` `Sessions…` `Mark here` `Save/Resume` | none |
| PROP | none | — | `pp_reset`, offered only once the run is over |

[CONFIRMED FROM CODE] Two sheets have no primary and that is correct: `SheetProp`'s reset is
"offered only once the run is over. Offering it mid-run would be a button whose only use is
to erase a bad day" (`SSR_Panel.mqh:1841-1846`).

**Typography — four sizes, one face, and a padding bug.** [CONFIRMED FROM CODE]
`SSR_FS_TITLE 9`, `SSR_FS_BODY 8`, `SSR_FS_CLOCK 13`, `SSR_FS_SMALL 7`, and
`SSR_FONT "Tahoma"` with `SSR_FONT_MONO "Tahoma"` deliberately the same face
(`SSR_Theme.mqh:424-425`). [RECOMMENDATION] Add no fifth size. But the two-column look of
several sheets is built on space padding into a proportional face:

```
SSR_Panel.mqh:1675  StringFormat("%-12s %s", T(SSR_S_BALANCE),  Money(...))
SSR_Panel.mqh:1678  StringFormat("%-12s %s", T(SSR_S_EQUITY),   ...)
SSR_Panel.mqh:1681  StringFormat("%-12s %s", T(SSR_S_FLOATING), ...)
SSR_Panel.mqh:1687  StringFormat("%-12s %d", T(SSR_S_BARS),  ...)
SSR_Panel.mqh:1690  StringFormat("%-12s %d", T(SSR_S_TICKS), ...)
SSR_Panel.mqh:1881  StringFormat("%-12s %d", T(SSR_S_BOOKMARKS), ...)
SSR_Panel.mqh:1892  Clip(StringFormat("%-12s %s", T(SSR_S_CHARTS), ...), 62)
SSR_Strings.mqh:513 "%-12s %d      guard %d"
SSR_Strings.mqh:515 "%-12s %d      skew %d ms"
```

[CONFIRMED FROM CODE] Nine sites pad a **translated** label to 12 characters and rely on the
result lining up. Tahoma is proportional; there is no monospaced face in the theme, and the
padded label is `T(...)`, so the pad count is fixed while the glyph widths are not — in
English and doubly so in Persian. [INFERENCE — never seen on a terminal, and MQL5 reports no
text metrics] the columns do not align. The fix is the one the panel already uses elsewhere:
two labels at fixed x. `riskmon` is drawn at `x+88` beside `risklbl` at `x+8`
(`SSR_Panel.mqh:1350-1355`), and `PropRow` draws `_l` at `x` and `_v` at `x+96`
(`:1866-1867`). **Cost**: one extra `Label` per row — 6 property writes and one of the 128
cache slots each, nine rows, and the removals in §M.5 free more slots than this consumes.

[CONFIRMED FROM CODE] The same class of defect sits on the product's most-read consult
surface: `SSRReviewLine` "pads `label` to 34 characters then appends `value`"
(`ui-dialogs.md` §5) across all 43 review rows. Same fix, same reason; out of scope here but
it is the same decision.

**Borders and surfaces.** [RECOMMENDATION] Keep the existing grammar exactly: `Group()` =
frame + legend plate + legend text (`_fr`/`_lb`/`_lg`), a 1 px `tabline` hairline under the
action strip, `SSR_C_WELL` plates behind chips, and no fills that are not a meter or a
progress bar. That *is* the subtle-border, elegant-card look the brief asks for, and it is
already built. The proposal adds no new container primitive.

**What to avoid, stated against this code.** No gradients and no glow: MQL5 has neither, and
faking either with stacked rectangles costs 9 writes each against a 561-writes-per-frame
budget (`ui-plumbing.md` §2). No large buttons: the 91 px PLAY is the largest control in the
product and it is large *because* it is pressed hundreds of times a session. No new colours:
51 tokens, 49 contrast assertions, one file. Density is achieved by the label cache and the
63-character discipline, not by shrinking type below `SSR_FS_SMALL 7`.

---

### M.9 Discoverability — the moment this product currently fails hardest

[CONFIRMED FROM CODE] In the default configuration a trainee is never told a single key.
`InpFirstCard=true, InpOneChart=true` and the guard at `SSReplayStandalone.mq5:1736` tests
`!one_chart_ok`, so `CSSRFirstRun` is shown on **neither** pass (`host-expert-4`, CONFIRMED);
even where the guard lets it through, `Show()` reports success without checking that its fixed
`y=376..480` fits the chart, so on a chart under ~480 px it is drawn off-screen, `seen.txt` is
written anyway, and the onboarding is consumed unread (`ui-dialogs-14`, CONFIRMED). The key
card opens only on `H`, and the only string that teaches `H` is on that card. The `?` button
that used to stand in for it was removed in v125.

This proposal deletes the four keyboard lines from SESSION, so it *must* pay for them:

1. [RECOMMENDATION] Put `Ctrl+K` in the key table. [CONFIRMED FROM CODE] `ui-plumbing-15`:
   `SSR_VK_K` is not in `SSRKeyBindings()`, so `SSRKeyToCommand(75)` returns `SSR_CMD_NONE`
   and the generated key card — the product's only key list — cannot mention the palette; and
   the comment at `SSR_Panel.mqh:929` records the opposite outcome, *"K the command palette
   had no key and is now unreachable"*, when `SSR_Panel.mqh:2827-2832` opens it on `Ctrl+K`
   before the key table so nothing can shadow it. One table row makes a working feature
   findable and corrects the record.
2. [RECOMMENDATION] Give SESSION's `Health` group one `Keys — H` line in `SSR_C_TEXT_FAINT`.
   One line, generated from the table (`SSRKeyBindings()` entry 21), replacing four
   hand-written ones that drifted.
3. [RECOMMENDATION] Fix `host-expert-4`'s guard so the first-run card appears, and make
   `CSSRFirstRun::Show` refuse rather than report success when the card does not fit.
4. [CONFIRMED FROM CODE] `ui-plumbing-14` — `SSR_S_ROW_HINT` prints "H halves   B stop to
   entry   X closes" as a legend for three *row buttons*, while `H`, `B` and `X` are globally
   bound to the key card, bookmark and line flip. A user who reads that line as a key legend
   and presses the keys gets three unrelated actions, one of which changes trade state. The
   Closed page of §M.4.2 reuses this row. Re-letter the row buttons or re-word the hint
   before building on it.

[INFERENCE] After these four, the product has **one** key list (generated), **one** command
list (the palette, reachable and documented), and **one** onboarding card that either shows or
says it could not. Today it has three hand-written lists that disagree, a palette its own
comments call unreachable, and a card that marks itself seen without being seen.

---

### M.10 The cost ledger, honestly

Ordered by cost, cheapest first. "Files" counts production files that change.

| Change | Files | New wire fields | New port verbs | Runtime cost | Risk |
|---|---|---|---|---|---|
| Delete the four keyboard lines; retire `SSR_S_KEYS_1..4` | 2 | 0 | 0 | −4 labels/frame on SESSION | none |
| `Ctrl+K` into the key table | 1 | 0 | 0 | none | none — key card grows one row, height is counted |
| Detached-chart caption chip (+ drop the PROP chip) | 1 | 0 | 0 | +1 chip = 2 objects, conditional | worsens `ui-panel-13` unless the PROP chip goes |
| Status strip → navigation | 1 | 0 | 0 | +9 writes/changed frame | ladder levels 1-4 must stop writing the `stbal` id |
| Two-label columns replacing `%-12s` | 2 | 0 | 0 | +6 writes × 9 rows | consumes 9 cache slots; the removals free more |
| `Jump…` / `Mark here` on SESSION | 1 | 0 | 0 | +2 buttons | raises exposure to `host-expert-7` until keys are withheld |
| `Save` / `Resume position` on SESSION | 1 | 0 | 0 | +2 buttons | the verbs are untested in production — no caller has ever run them |
| PERFORMANCE reads real statistics | 3 | ~8 | 0 | a throttled 3-pass `Compute` | PF-undefined and R-sample semantics must not be flattened |
| Closed page on POSITIONS | 3 | ~6 arrays × 12 | 1 setter | O(`Total()`) struct copies, gated | inherits `ui-panel-7` unless the row is re-derived first |
| Bookmark list on SESSION | 3 | rows + labels | 2 | a list render per frame | defer — largest cost, smallest moment |

**Preconditions that are not part of this proposal and must land first**, in order:

1. Settle L.4.2 on a terminal (decides the drag, the tag box, and whether the speed groove is
   a slider or twenty 6.5 px buttons).
2. `ui-panel-3` + `ui-panel-4` — compact mode must actually drop the rail, or its
   status-strip-only navigation is a lie told over 122 px of live buttons.
3. `ui-panel-6` and `ui-panel-7` — the status strip and the position row must be re-derived
   for a 310 px frame and a 245 px sheet. Both are visible on every frame of every session,
   and both are reused by this proposal.
4. `host-expert-7` — withhold keys while a dialog is open, the way `CSSRReviewCard::OnKey`
   already does.
5. `ui-dialogs-1` (HIGH) — the wizard silently clears `session_name`, so sessions cannot be
   resumed. SESSION's whole "put me somewhere else" moment rests on saved sessions existing.

[INFERENCE] Items 2-5 are four confirmed defects that this proposal *builds on top of*. None
of them is caused by it, and all four make it worse if left. A redesign shipped over them
would be judged for their symptoms.

---

### M.11 What this proposal does not fix, and says so

* [CONFIRMED FROM CODE] `ui-plumbing-5` — RTL remains impossible. `SSR_Layout.mqh` exists to
  provide a mirrored coordinate system and **no production file calls any of its functions**;
  `SSRCentre` and `SSRInner` have zero call sites anywhere. Flipping `SSRFrame.rtl` changes
  nothing on screen. Adopting it would mean rewriting inline pixel arithmetic in eight files
  by hand — a larger job than this whole proposal, and it would have to happen *before* the
  arithmetic is re-derived for 245 px, not after.
* [CONFIRMED FROM CODE] Five surfaces stay outside `T()`: the key card body
  (`ui-plumbing-1`), the reset confirmation (`ui-panel-14`), the fill toast's
  `"   spread %.1f pt"` / `"   NO STOP"` (`SSR_Panel.mqh:795, 799`, while translated
  equivalents exist 700 lines away), the review observations (`ui-dialogs-4`), and every word
  the chart layer draws — `"STOP - drag me"`, `"TARGET - drag me"`, `BUY`/`SELL`/`SL`/`TP`
  (`chart-12`). This proposal touches none of them, and audit A19 still skips every path
  without `/Ui/` in it.
* [CONFIRMED FROM CODE] `strategy_text` joins the orphan list: a grep over `MQL5/` finds it
  declared at `SSR_ReplayPort.mqh:103`, cleared at `:274`, assigned at
  `SSR_GroupPort.mqh:395` from `StrategyLine()` — and **read by no draw site**. Whatever the
  strategy layer is saying, no destination in this proposal shows it. That is a deliberate
  omission: there is no moment in the four that asks for it, and inventing a sixth
  destination to give an orphan field a home is how the Session junk drawer happened.
* [CONFIRMED FROM CODE] `ui-panel-1` and `ui-panel-2` — `DrawSheet` calls `HideSheets()` on
  every repaint (154 `Remove()` calls) and `HideBody(false)` runs every frame and `Forget()`s
  the property cache for ~44 sized objects. Every destination in this proposal repaints
  through that path. The IA is not what makes it expensive and changing the IA will not make
  it cheap.

---

### M.12 Summary of the argument

The moments are four; the destinations are five; the brief's eight do not fit the rail and
three of them name things that are either permanently visible or unbuildable in MQL5. The
work is not adding destinations — it is **giving the *in a trade* moment a continuous path
(the status strip becomes navigation), giving *reviewing* a destination that contains
statistics, emptying the junk drawer into the key card that was already generated, and
putting back the one readout v125's removals actually cost.** Four of those five are cheap.
The fifth — real statistics on the wire — is the only one that buys a new runtime cost, and
it buys the thing a training product exists for.

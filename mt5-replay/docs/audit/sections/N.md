## N. PAGE-BY-PAGE REDESIGN

*Every destination in the M architecture, drawn to the pixel. M decided **which** surfaces exist and
why; this section decides **what each one holds, where each row sits, and what it costs**. Build
v125, `SSR_LAYOUT_RAIL` and `SSR_THEME_RAIL` active. Nothing below has run on MT5.*

*The brief's eight pages are all covered here, but four of them are not destinations: M.3.2 rejected
HOME, REPLAY, JOURNAL and SETTINGS on evidence, and N honours that by showing, item by item, where
every row of those four actually lands. A rejected page still owes its content a home.*

---

### N.0 How to read this section

#### N.0.1 The two frames every page is drawn into

[CONFIRMED FROM CODE] `Render()` hands the sheet its origin and width at `SSR_Panel.mqh:752-753`:

```
         DrawSheet(x + SSR_PAD + SSR_RAIL_W + SSR_GAP, cy + 4,
                   W - 2 * SSR_PAD - SSR_RAIL_W - SSR_GAP);
```

so with `SSR_PANEL_W 310`, `SSR_PAD 8`, `SSR_RAIL_W 44`, `SSR_GAP 5` (`SSR_Theme.mqh:487-514`) every
page in this section is drawn into:

| | Standard | Expanded |
|---|---|---|
| sheet width `w` | **245 px** | 245 px (**width never changes**) |
| sheet height | `SSR_SHEET_H` = **186 px** | `SSR_SHEET_H_TALL` = 186 + `SSR_SHEET_GROW 140` = **326 px** |
| row origin | `x + 8` → **237 px of row** | identical |
| trigger | default | `P` **and** chart ≥ 500 px (`m_tall` wish/fact, `:676-714`) |
| Compact | **no sheet at all** — `if(!m_compact)` guards `DrawRail`/`DrawSheet` together (`:740-752`) | — |

> **Expanded buys rows, never columns.** Every four-column overflow in L.3.2 is a *width* problem and
> `SSR_SHEET_GROW` is height. Any page that only fits "in tall mode" does not fit.

#### N.0.2 The budget card each page carries

Each page below is priced with the same five numbers, so two designs can be compared without
re-deriving anything:

* **rows** — id, slot, primitive, source field on `SSRUiState`, R5 character budget.
* **px, Standard** — every row's `y` and `h`, adding to ≤ 186, with the spare stated.
* **px, Expanded** — the same, to ≤ 326.
* **objects / cold writes** — from M.1.2's measured table: `Rect` 9, `Label` 6, `ButtonC` 9,
  `Button` 9 [INFERENCE — `Button` (`SSR_Widgets.mqh:261`) writes the same property set as `ButtonC`
  (`:358`), which M.1.2 measured at 9], `Edit` 9 (+1 with text), `Group` 24, `Chip` 15, `Meter` 27,
  `Slider(20)` 198.
* **warm cost** — one `ObjectFind` per object via the `Same()` early return, plus one
  `ObjectSetInteger(COLOR)` per panel `Text()` hit (`SSR_Panel.mqh:191-198`).

Currency, from the project's own measurement (`SSR_Widgets.mqh:31-38`): **≈ 0.07 ms per property
write.**

[INFERENCE — MQL5 exposes no text metrics; every px/char figure is an estimate] Tahoma 8 pt
(`SSR_FS_BODY`) ≈ 5.1 px/char, 7 pt (`SSR_FS_SMALL`) ≈ 4.5 px/char. A 237 px row is **~46 chars at
BODY, ~52 at SMALL** — the R5 budget, not MetaTrader's 63.

#### N.0.3 The frame signature — R1, generalised, because pages have sub-states

[RECOMMENDATION — extension to M's R1, required before any page below can ship] M.2's transition
latch lists `m_tab`, `m_compact`, `m_tall`, `m_collapsed`, `m_closed`. That set is **not sufficient
for a page-level design**, because four pages below change *which objects they draw* without any of
those five changing:

| Page | sub-state | what appears / disappears |
|---|---|---|
| TRADE | `m_state.lines_armed` | `armbtn`+`hintrow` ⟷ six rows, `openln`, the trio, `buy`/`sell` |
| TRADE / EVAL | `m_state.prop_on` | the allowance row; the whole EVAL cell |
| EVAL | `m_state.prop_state >= 2` | `pp_dl`, `pp_head`, `pp_reset` |
| POSITIONS | `m_open_page` (new), `m_state.pos_rows` | the row tail, the three per-row buttons |
| PERFORMANCE / KEYS | `m_page` (new) | every `ListRO` row |

So the latch is a **frame signature**: a small struct compared whole against the last rendered frame,
holding `m_tab`, `m_compact`, `m_tall`, `m_collapsed`, `m_closed`, `lines_armed`, `prop_on`,
`prop_state`, `pos_rows`, `pending` mask, `m_open_page`, `m_page`. Teardown runs when the signature
differs and on no other frame. [CONFIRMED FROM CODE] this is the pattern the file already uses at
`:679-687`, where `HideSheetArea` runs only inside `if(m_compact != was_compact)` — generalised from
one field to twelve. Lands in a new `bool Signature(SSRFrameSig &out)` + `bool SigChanged()` beside
`Render()` (`SSR_Panel.mqh:718`).

Without it, M's change #1 makes every page below **stale rather than expensive**, which is worse.

---

### N.1 HOME — refused as a page, delivered as chrome

**Evolves from:** nothing. It is `DrawCaption` (`:833`), `DrawClock` (`:945`) and `DrawStatus`
(`:1915`) doing the job they already do, with one deletion and one addition (M.4.0).

M.3.2 rejected HOME because *"the chrome is home"*, and R2 (`:670-674`) is the rule behind it. This
section's obligation is different: to prove, item by item, that the brief's HOME row list is
**readable without a click**, and to name honestly the items that are not.

#### N.1.1 The brief's HOME, item by item

| HOME item | Where it is read | id / slot | Clicks | Evidence |
|---|---|---|---|---|
| **status** | caption, right of identity, in the state colour | `capinfo` / 1 | **0** | `:868-870`, `SSRStateColor` (`SSR_Theme.mqh:547`) |
| **replay date/time** | clock, 13 pt, the largest type on the panel | `clock` / 2 | **0** | `:950`, `clock_text` — masked by the port when blind (`SSR_ReplayPort.mqh:84`) |
| **progress** | `%d%%` + pause reason, `Clip(...,24)`, and the 6 px bar | `prog` / 3, `bar` | **0** | `:957-967` |
| **balance** | status strip, slot 1 of 4 | `stbal` / 50 | **0** | `:2015` |
| **open positions** | status strip, slot 3 of 4 **and** the rail cell `Pos 3` | `stopen` / 52 | **0** | `:2022`, `TabName()` `:1108-1112` |
| **session P/L** | strip: **floating**, live, per frame | `stflt` / 51 | **0** | `:2018` |
| **equity** | *derived and dropped* — `balance` + `floating` are both on the strip | — | — | N.1.3 |
| **current risk** | TRADE, ladder **and** the new verdict line | `riskval` / 11, `verdict` / 22 | **1** | N.3 |
| **drawdown** | EVAL meters when `prop_on`; PERFORMANCE's Drawdown group otherwise | — | **1** | N.8, N.5 |
| **symbol** | *deliberately not drawn* | — | — | N.1.3 |
| **timeframe** | *not on the wire* | — | — | N.1.3 |

**Nine of eleven at zero clicks, on a band that is 73 px tall and never navigates.** That is the
HOME page, and it is already built.

#### N.1.2 The five-second read, in reading order

```
  SS Replay v125   PAUSED    [TICK][BLIND][PROP]              -  X     <- what, and under what modes
  09:41:07                                       62%  waiting data     <- where in the session
  |======================================                        |     <- how far
  ... transport / speed ...                                            <- the controls
  10,412.55    +38.20    3 open    2 adrift F                          <- the money
```

[RECOMMENDATION] Preserve that order exactly. It is *state → time → progress → controls → money*,
and the one change N makes to it (N.1.3) removes a duplicate rather than adding a row.

#### N.1.3 The three items with no home, answered honestly

**Symbol — refused, and the refusal is already written down.** [CONFIRMED FROM CODE]
`SSR_Panel.mqh:870-882`:

```
      //| THE SYMBOL IS NOT REPEATED HERE.                                 |
      //| MetaTrader already writes it in the chart's own corner...        |
      //| It is also the RIGHT one for Blind mode, which exists precisely  |
      //| to hide the instrument: a panel announcing the symbol the chart  |
      //| was told to conceal would defeat the feature it sits beside.      |
```

A HOME page carrying `m_state.symbol` would print the instrument that Blind mode exists to hide.
**Not drawn, on any page, in any mode.** (`trade_symbol` is a separate field and is equally refused.)

**Timeframe — no source exists.** [CONFIRMED FROM CODE] `SSRUiState` (`SSR_ReplayPort.mqh:38-235`)
carries no period field; a grep for `PERIOD_`/`timeframe` over the panel returns nothing but the
wizard's `extra_tfs` string. Drawing it needs a new wire field, a new `CSSRGroupPort` fill, and a
strip or caption slot that M.4.0 has already spent. [RECOMMENDATION] **Not added.** MetaTrader draws
the period on its own toolbar and in the chart corner, next to the symbol, for free.

**Equity — dropped, and the cost named.** [CONFIRMED FROM CODE] `SheetStats` draws balance, equity
and floating as `st1`/`st2`/`st3` (`:1673-1684`) 200 px above a strip that already draws balance and
floating. M.4.3 deletes those three rows. Equity is then the only one of the three with no draw
site — and it is `balance + floating` for a virtual account with no swap/commission accrual between
frames. [RECOMMENDATION] Accept the loss: two live numbers plus a sum is three numbers where two
would do, and the strip has four slots for five candidates. If a future build wants equity back, it
is funded by `stspread`, exactly as `chartsn` is (M.4.0), never by a fifth slot.

#### N.1.4 The one HOME change, priced

| Change | Site | Δ writes | Δ objects |
|---|---|---|---|
| delete `stfid` (`ui-panel-6`, CONFIRMED MEDIUM — anchored `x+330` in a 310 px panel) | `DrawStatus:2032-2036` | −6 cold, −1 find/frame | −1 |
| add `chartsn` on slot 53 while `charts_detached > 0` (`chart-10`) | `DrawStatus`, after `stspread` | +6 cold, conditional | +1, exclusive with `stspread` |
| re-column: `stflt` 116→106, `stopen` 218→196, `stspread` 268→252 | `:2018-2030` | 0 | 0 |

[INFERENCE] the re-columned strip, at FS_SMALL ≈ 4.5 px/char against the inner right edge `x+302`:
`bal` 14 ch → x+8..71 · `flt` 12 ch → x+106..160 · `open` 9 ch → x+196..237 · `sp`/`adrift` 8 ch →
x+252..288. **Four columns that clear each other by ≥ 35 px, with 14 px of right margin.** Today's
fifth column starts 28 px past the frame.

---

### N.2 REPLAY — refused as a page; the operated half is chrome, the consulted half is SESSION

**Evolves from:** `DrawCaption:833`, `DrawClock:945`, `DrawTransport:975`, `DrawSpeed:1045`,
`DrawActions:1235` — 124 px of permanent bands. M.3.2: *"Putting PLAY behind a click is the one
change that would make this product worse."*

#### N.2.1 The brief's REPLAY, item by item

| REPLAY item | Lands | id | Clicks | Change in N |
|---|---|---|---|---|
| **play / pause, primary** | transport, 91 px of a 294 px band | `toggle` | **0** | none. The 91-vs-24 px ratio *is* the primary/secondary signal (`ui-plumbing-10` is **NOT_A_BUG**; nothing here acts on it) |
| **step forward / back** | transport, `<` `>` 24 px; `<<` `>>` = ten | `back`,`step`,`back10`,`step10` | **0** | none |
| **restart** | transport, `\|<` | `restart` | **0** | none |
| **speed** | speed band: `-` `[ 4x ]` `+` + groove + meaning | `spdn`,`spdup`,`spdseg*` | **0** | **10 drawn cells, not 20** (N.2.2) |
| **timeline / progress** | clock band: `%`, pause reason, 294 px `Progress` | `prog`, `bar` | **0** | none |
| **date / time** | clock, 13 pt | `clock` | **0** | none |
| **tick fidelity** | caption **chip** (a mode) + `Fidelity` action button (the verb) | `chfid`, `fidelity` | **0** / 1 | chip capped at 6 chars; strip duplicate deleted (N.1.4) |
| **blind mode** | caption chip | `chblind` | **0** | none |
| **bookmark** | SESSION `[ Mark here ]`, and `B` | `bookmark` | 1 | affordance restored (L.4, `SSR_S_ACT_BOOKMARK` un-orphaned) |
| **jump** | SESSION `[ Jump… ]`, and `J` | `jump` | 1 | affordance restored |
| **session controls** | action strip `Sessions`; SESSION `[ Save position ]` `[ Resume position ]` | `sessions`, `savepos`, `respos` | 0 / 1 | two implemented port verbs get a UI for the first time (N.6) |
| **random mode** | **nothing carries it** | — | — | N.2.3 |
| **reset** | transport right, 58 px, arms then asks on the strip | `reset` | **0** | none |

#### N.2.2 The speed band, re-drawn — the one chrome row N changes

[CONFIRMED FROM CODE] `m_track_w = (x + W - SSR_PAD - mw) - m_track_x` = **130 px**
(`SSR_Panel.mqh:1084`) divided into `SSR_SPEED_LADDER_SIZE 20` cells — 6.5 px a target — and the file
names its own limit at `:1047-1050`.

```
  y+82  Speed   [-] [  4x  ] [+]   |##########|..........|   4 bars/s
        x+8     x+52 x+72    x+114  x+136 ......... x+266   x+270
        FS_SMALL  18   vw     18     10 cells of 13 px       mw 52, Clip 11
```

| | today | N |
|---|---|---|
| drawn cells | 20 × 6.5 px | **10 × 13 px**, cell *i* selects ladder index `2i` |
| every speed reachable | yes (click) | yes (`-` / `+`, one stop each) |
| `Slider` cold cost | **198 writes** | **108 writes** |
| `spdseg10..19` | drawn | **`Remove`d once** in `Create()` via `UpgradeSweep()` — M.1.6's correction: the `HideBody` loop at `:2093-2094` *Hides*, it does not Remove |
| meaning text | unbounded into 52 px (`ui-panel-8`) | `Clip(..., 11)` |
| thumb / ticks | `SSR_C_THUMB_EDGE`, `SSR_C_TICK` declared and drawn by nothing (`ui-plumbing-9`) | spent here, at zero cost to the palette |

`Dispatch`'s `spdseg` arm (`:2589-2600`) needs one line — `SSRSpeedLadder(2 * index)` — and the
`AllDigits(tail)` guard that protects `spdseg_tk`/`spdseg_th` is untouched.

#### N.2.3 Random mode has no wire field, and that is the finding

[CONFIRMED FROM CODE] A grep for `random`/`seed` over `SSR_ReplayPort.mqh` and `SSR_Panel.mqh`
returns **zero matches**. The concept exists only pre-session, in the wizard's value struct —
`bool random_start;` and `string seed;` (`SSR_SetupPanel.mqh:137`, cleared at `:146`, recapped at
`:891-895`, applied by `ApplyMode(3)` at `:1048`). **Once the session starts, nothing on screen says
it was randomly placed or what seed produced it** — and a random session is the one session a trainee
cannot reconstruct without the seed.

[RECOMMENDATION] One new wire field `string seed_text` (empty when the start was chosen), filled
beside the existing `strategy_text` fill in `CSSRGroupPort::ReadState` (`SSR_GroupPort.mqh:395`), and
**one SESSION row** (N.6): `random start · seed 4417`. Not a caption chip — the chip row already
overruns by 6 px (`ui-panel-13`), and M.4.0's payment rule says a new chip must drop an old one.
Not a HOME item: the seed is consulted once, not watched.

---

### N.3 TRADE — *what I am about to do*

**Evolves from:** `SheetTrade` (`SSR_Panel.mqh:1346-1509`) — the densest and best sheet in the
product, and the only one that acts. Structure preserved; three rows added, one pair of buttons
moved, one object-id collision split.

#### N.3.1 Rows, armed state (the worst case)

| # | y | h | primitive | id | slot | content | source | budget |
|---|---|---|---|---|---|---|---|---|
| 1 | +0 | 34 | `Group` | `g1` | — | "Risk" | — | 12 |
| 1a | +13 | 12 | `Label` | `risklbl` | 10 | "Risk per trade" | — | 16 |
| 1b | +13 | 12 | `Label` @x+88 | `riskmon` | 19 | `25.00` | `balance`·`risk_percent` | 10 |
| 1c | +10 | 16 | `Button`×2 + `Label` | `riskdn`/`riskval`/`riskup` | 11 | `- [ 1.00 % ] +` | `risk_percent` | 8 |
| 2 | **+36** | 13 | `Label` | **`verdict`** | **22** | `0.50 % · 25.00 · 2.0 R · 0.42 lot` | `risk_percent`,`risk_money`,`rr`,`lot_from_risk` | **40** |
| 3 | +50 | 18 | `Label`+`Edit` | `taglbl`/`tagbox` | — | setup name, read at a moment only | `trade_tag` | — |
| 4 | +72 | 114 | `Group` | `g2` | — | "Order" | — | 14 |
| 4a | +84 | 12 | `Label` | `setuprow` | 12 | `LONG setup` / `order_name` | `line_long`,`order_name` | 30 |
| 4b | +96 | 12 | `Label` | **`whyrow`** | **17** | why it is refused — **its own object** | `order_why` | 44 |
| 4c | +108 | 12 | `Label`×2 | `slrow` \| `rrrow` | 13, 15 | `Stop 53410 (-25.00)` \| `2.00 R` | `sl_price`,`risk_money`,`rr` | 22 \| 8 |
| 4d | +120 | 12 | `Label`×2 | `tprow` \| `sizerow` | 14, 16 | `Target 53610 (+50.00)` \| `0.42 lot` | `tp_price`,`reward_money`,`lot_from_risk` | 22 \| 8 |
| 4e | +132 | 12 | `Label` | **`alwrow`** | **23** | `this stop uses 14% of today's allowance` | `prop_daily_room_after` **(new)** | **46** |
| 4f | +146 | 22 | `ButtonC` | `openln` | — | **the primary** — `Open LONG 0.42` / `Place BUY STOP 0.42` | `entry_armed`,`order_name` | 18 |
| 4g | +168 | 18 | `Button`×3 | `flipbtn`/`enbtn`/`clrbtn` | — | Flip · At market \| Entry line · Remove | — | 10 each |

**Standard budget: 0 + 34 · gap 2 · 36 + 13 · 50 + 18 · 72 + 114 = 186 of 186, exactly.**
Without an evaluation the allowance row is absent, `g2` is 102, and the page ends at **y+174 with
12 px spare**.

#### N.3.2 Rows, unarmed state

| y | h | id | content |
|---|---|---|---|
| +0 | 34 | `g1` | Risk group, identical |
| +36 | 13 | `verdict` | `0.50 % · 25.00 · place the lines` (the two operands that exist) |
| +50 | 18 | `tagbox` | identical |
| +72 | 62 | `g2` | `armbtn` (w−16 × 22) at gy+13; `hintrow` at gy+40 |
| +138 | 24 | `buy` \| `sell` | the market pair, `dw = (w-5)/2` = 120 px each |

**Total 162 of 186 — 24 px deliberately empty** (M.9: whitespace is the premium move available).

#### N.3.3 The one structural change: the deal pair belongs to the unarmed state

[CONFIRMED FROM CODE] Today both are drawn in both states (`:1466-1485`), and in the armed state one
of `buy`/`sell` is dimmed by construction:

```
      bool dim_buy  = !m_state.can_trade ||
                      (m_state.lines_armed && !m_state.line_long);
```

so the armed sheet carries **two deal-coloured primaries** — `openln` and a live half of the pair —
against M.9's rule of *exactly one primary control per band*. It is also the 28 px the three new rows
need.

[RECOMMENDATION] **Armed ⇒ `openln` is the primary and `buy`/`sell` are `Remove`d; unarmed ⇒ the pair
returns and `openln` is absent.** Cost, named: a market order on the side the lines do **not**
describe now costs `Flip` then the primary — two clicks, or the `X` key
(`SSR_CMD_LINES_FLIP`, `SSR_Keys.mqh:167`). Nothing else changes; `Tab` still takes the trade the
lines describe.

This is exactly why N.0.3 exists: `buy`/`sell` must be **removed on the transition**, not left to a
per-frame redraw, or invariant I7 leaves two deal buttons on the chart forever.

#### N.3.4 The verdict line, and what it is allowed to do

[RECOMMENDATION, from M.4.1] `0.50 % · 25.00 · 2.0 R · 0.42 lot`, coloured by the **worst** of three
tests — `sl_price == 0` → `SSR_C_STOP`; `order_why != ""` → `SSR_C_HOLD`; else `SSR_C_TEXT`.

**Every operand is already on the wire and the panel computes none of them.** `lot_from_risk` is what
`PreviewLot` returned — *the same call the order uses, never a second formula*
(`ui-port-session.md` §3.3). The line is a *reordering* of four numbers a trainee currently assembles
from 92 px of group box, not a new measurement.

**`whyrow` is not optional and cannot be deferred.** [CONFIRMED FROM CODE] `ui-panel-5` (CONFIRMED,
MEDIUM) — slots 12 and 17 write the **same object at the same coordinates** (`:1405`, `:1432`), and
the site's own comment explains the slot split while leaving the id shared. Under M's R1 the defect
changes from *"visible for one frame"* to *"whichever wrote last, permanently"*. Split the id in the
same change (M.8.1 #3 with #1).

#### N.3.5 `DailyRoomAfter()` — one accessor, two readers, no second formula

[CONFIRMED FROM CODE] The arithmetic must not live in the panel; `SheetProp`'s own comment says why
(`:1732-1740`: *"THIS SHEET COMPUTES NOTHING"*). `CSSRPropEvaluation` already owns the operands —
`DailyUsed()` (`SSR_PropEvaluation.mqh:237`), `DailyFloor()` (`:295`).

* **new accessor:** `double CSSRPropEvaluation::DailyRoomAfter(const double loss)`
* **new wire field:** `double prop_daily_room_after` — pre-clamped 0..1, filled beside the other prop
  fractions in `CSSRGroupPort::ReadState`
* **readers:** TRADE `alwrow` as a percentage sentence; EVAL as the same number in money (N.8)
* **gate:** `prop_on`. The row is **absent**, not zero — a rule that does not exist is not a rule
  with room left (`SSR_ReplayPort.mqh:160-163` makes exactly this argument about `prop_daily_pct`).

#### N.3.6 Cost

| | objects | cold writes | warm |
|---|---|---|---|
| armed, today | 20 | ~185 | 20 finds |
| armed, N | 20 | ~185 | 20 finds + ≤3 colour writes |
| unarmed, N | 12 | ~140 | 12 finds |

**The three new rows are paid for by the two deal buttons the armed state no longer needs.** New
slots: 22, 23 — both on M.7's verified free list. `order_why` takes slot 17, which it already had;
only the *object id* is new.

**Refused for this page** (M.4.1, restated because they are the three things every trader asks for):
a stop/target stepper, a lot box, an order-type selector. All three are decisions the chart lines
already make from geometry (`:1377-1384`), and each needs a control MQL5 cannot draw.

---

### N.4 POSITIONS — *what is open, and what just closed*

**Evolves from:** `SheetPositions` (`:1509-1671`), `PosCap()` (`:434`), `PosGroupH()` (`:442`),
`StepTrail()`, and the `p{x|h|b}<digits>` dispatch arm (`:2659-2680`).

#### N.4.1 The row arithmetic, re-derived — and the column that has to go

[CONFIRMED FROM CODE] `ui-panel-7` (CONFIRMED, MEDIUM): the note is anchored `x+120` (`:1576`) and
the money at `x + w - 116` = **x+129** (`:1582`) — nine pixels for nine characters. The comment above
it (`:1563-1574`) shows its working *for a 295 px sheet*.

Re-derive for 245, with the three row buttons keeping today's right-anchored positions
(`x+w-68`, `-47`, `-26`, 18 px each → right edge **x+237**):

```
  demand:  "BUY 1.00 @ 53513"  16 ch @BODY  ~82 px
         + "! no stop"          9 ch @SMALL ~41 px
         + "+1,234.56"          9 ch @BODY  ~46 px
         + three buttons                     60 px
         + three gutters                    ~18 px
         ------------------------------------------
                                            247 px   into 237.  It does not fit.
```

[RECOMMENDATION] **Three columns, not four. The entry-spread note is cut; the no-stop flag becomes a
one-character prefix on the position text.**

```
x+8    text    "! BUY 1.00 @ 53513"   Clip 20   ~102 px   pr<r>  slot 80+r
x+120  money   "+1,234.56" / "waiting" Clip  9   ~46 px    pl<r>  slot 92+r
x+177  H B X   three 18 px buttons               60 px
                                                 -> right edge x+237, 8 px margin
```

* the `!` prefix inherits the colour the note already carried (`m_state.pos_no_stop[r] ?
  SSR_C_STOP : ...`, `:1577`) and costs **no id, no slot, no object** — the graft M.4.2 asked for,
  taken to its conclusion.
* **the `pn<r>` family (slots 104-115) is deleted**: −6 cold writes and −1 object per row, −12
  objects at `PosCap() 12`.
* **what the spread loses, and where it still lives:** the fill toast prints it at the moment of
  fill (`:795`), `avg_spread_points` / `worst_spread_points` / `wide_spread_trades` are three rows of
  PERFORMANCE's Execution group (`SSR_Review.mqh:155-160`), and the CSV carries it per trade. The
  *row* loses it; the *product* does not.
* this retires `ui-panel-7` outright instead of re-deriving a 9 px collision into a 5 px one.

[CONFIRMED FROM CODE] `posmore` at `x+w-92` shares a baseline with the 37-character `poshint`
(`:1637` vs `:1628`). [RECOMMENDATION] `poshint` `Clip(..., 30)` and `posmore` on its own baseline at
`hy - 13`; at `PosCap()` rows the group has the room because the note column is gone.

#### N.4.2 Rows and pixel budget

| y | h | element | Standard | Expanded |
|---|---|---|---|---|
| +0 | `PosGroupH()` | `Group` "Open positions" | **134** | **274** (`134 + SSR_SHEET_GROW`) |
| +14 | 20 × cap | position rows, pitch `SSR_ROW_H + 1` | `PosCap()` = **5** | **12** (`SSR_POS_MAX`) |
| +gh−15 | 12 | `poshint` / `TradeError()` \| `posmore` | y+119 | y+259 |
| +gh+4 | 22 | **three** buttons, `bw = (245-10)/3 = 78` | y+138 | y+278 |
| +gh+30 | 19 | trailing: label + `-` `+` `Off` | y+164..183 | y+304..323 |

**Standard 183 of 186 · Expanded 323 of 326.** Unchanged from today — the third button costs no
height, which is why M.4.2 chose option (a).

#### N.4.3 The Open / Closed toggle

| | Open page | Closed page |
|---|---|---|
| col 1 | `! BUY 1.00 @ 53513` Clip 20 | `BUY 1.00 @ 53513` Clip 20 |
| col 2 | floating P/L, or `waiting` for a pending | **closed net** |
| col 3 | `H` `B` `X` | **nothing** — 60 px yields to col 1 (Clip 20 → 32) and the setup tag |
| order | wire order | **newest first** |
| overflow | `posmore` | `posmore`, same string |

**Wire growth, minimised:** `int closed_rows` + `string closed_text[SSR_POS_MAX]` +
`double closed_pl[SSR_POS_MAX]` + `string closed_tag[SSR_POS_MAX]` — three arrays and a counter, not
six. `SSRUiState::Init()` clears every field in one loop (`SSR_ReplayPort.mqh:238`) and that loop
grows by four lines.

**The walk must be gated, and the gate is the whole cost.** [CONFIRMED FROM CODE] `CSSRJournal::Line`
(`SSR_Journal.mqh:141-157`) is the shape to avoid: a full `At(i, SSRVirtualPosition&)` struct copy
per slot until the *n*-th closed trade is found. Filling twelve closed rows that way is
O(`Total()`)×12 **per `ReadState`, ten times a second**. [RECOMMENDATION] one setter —
`void CSSRGroupPort::WantClosed(const bool on)` — called from `Dispatch`'s new `posmode` arm, the
same shape as the existing host-only setters (`SetTpPoints`, `NoteLineDistances`). The fill runs only
while the Closed page is up, and one backward walk fills all twelve.

#### N.4.4 The three letters

[CONFIRMED FROM CODE] `ui-plumbing-14` (CONFIRMED, LOW): `H`, `B` and `X` on a row are the same
letters as three **global keys with three unrelated meanings** — `H` opens the key list, `B`
bookmarks, `X` flips the planning lines (`SSR_Keys.mqh:167`, `:180`, `:216`) — and `SSR_S_ROW_HINT`
prints them as a legend (`SSR_Strings.mqh:394`).

[RECOMMENDATION] relabel to `½` / `BE` / `✕` (ids unchanged, so the dispatch arm at `:2659` is
untouched) and rewrite the hint to name the **actions**: `half · break even · close`. Three catalogue
strings, two languages. [POTENTIAL_RISK] `½` and `✕` are non-ASCII in a file that is UTF-8 **without
a BOM** and already carries six raw `·` characters (`ui-plumbing-13`); if MetaEditor decodes as ANSI
they draw as mojibake. Safe fallback: `1/2` / `BE` / `X` in ASCII, which still breaks the false key
legend.

#### N.4.5 Cost

| | objects | cold writes |
|---|---|---|
| today, 5 rows | 5×4 + 9 = 29 | ~312 |
| N, 5 rows Open | 5×3 + 10 = 25 | ~291 |
| N, 5 rows Closed | 5×2 + 10 = 20 | ~237 |
| N, 12 rows Expanded | 12×3 + 10 = 46 | ~507 cold, **once per navigation** |

---

### N.5 PERFORMANCE — *what I have done*

**Evolves from:** `SheetStats` (`:1671-1749`) — 3 duplicated account numbers, 3 run counters and a
button — replaced by the generator the product already has: `SSRReviewRows()`
(`SSR_Review.mqh:104-166`), **43 measures in nine groups**, formatted by `SSRReviewLine()` to
`SSR_REVIEW_ROW_MAX 60` (`:85-93`).

#### N.5.1 The brief's seven themes, mapped onto the nine groups

The brief asks for Performance, Risk, Behaviour, Consistency, Drawdown, Trade Quality and Session
Analysis — *"built on hierarchy, not dozens of equal numbers"*. The hierarchy is: **one headline per
theme on the curated page; the rest paged behind it.**

| Brief theme | Generator group(s) | Rows | Headline on page 1 | Evidence |
|---|---|---|---|---|
| **Performance** | Result (10), Rates (8) | 18 | `12 trades · 58 % win · PF 1.42` and `net +412.80` | `SSR_Review.mqh:108-127` |
| **Risk** | R (4) | 4 | `expectancy +0.31 R (11 of 12)` | `:128-131` |
| **Consistency** | Discipline: `risk_spread_pct`, `risk_samples` | 2 | `risk varied 18 % over 11 trades` | `:150-152` |
| **Behaviour** | Discipline: `revenge_trades`, `trades_without_stop` | 2 | `back in after a loss 2` · `no stop 1` | `:153-156` |
| **Drawdown** | Drawdown (4) | 4 | *paged* — the headline belongs to EVAL while `prop_on` | `:132-135` |
| **Trade Quality** | Execution (6), Excursion (2), Streaks (3) | 11 | `ambiguous bars 2 (17 %)` | `:141-148`, `:157-162` |
| **Session Analysis** | Time (2) only | 2 | *paged* | `:146-148` |

[CONFIRMED FROM CODE] **Session Analysis has no data behind it.** `SSRStatistics` carries
`avg_hold_sec` and `time_in_market_pct` (`SSR_Statistics.mqh:95-96`) and **no time-of-day, no
session-window and no per-instrument bucket**; the only grouping the engine performs is per setup
tag, and it exists in the HTML/CSV exporter, not in the review generator. [FUTURE FEATURE] a real
Session Analysis needs hour buckets in `CSSRStatsEngine::Compute` first; until they exist the theme
is **two rows on a paged screen**, and saying so is better than four empty ones.

#### N.5.2 Page 1 — curated, fixed, and the only page a trainee must read

```
   +- RESULT ------------------------------------+   y+0   Group   h44
   |  12 trades      58 % win       PF 1.42      |   y+14  slot 37
   |  net  +412.80        expectancy +0.31 R (11 of 12)         y+28  slot 38
   +---------------------------------------------+
   +- DISCIPLINE --------------------------------+   y+48  Group   h72
   |  risk varied     18 %  over 11 trades       |   y+62  slot 39
   |  back in after a loss   2                   |   y+76  slot 47
   |  no stop                1                   |   y+90  slot 48
   |  ambiguous bars         2  (17 %)           |   y+104 slot 49
   +---------------------------------------------+
   numbers may lag the account by up to 2 s          y+124  Clip 52, FS_SMALL, HOLD
   <   1-8 of 43   >                                 y+140  two 30 px buttons + label
   [ Save statement ]                                y+163  h22  -> y+185
```

**185 of 186.** Budgets: row 1 ≤ 44 ch, row 2 ≤ 46, discipline rows ≤ 40, caveat ≤ 52 (FS_SMALL).

**Two semantics that must not be flattened** (M.4.3, both CONFIRMED):

* [CONFIRMED FROM CODE] `profit_factor` stays 0 when there is no loss, deliberately
  (`SSR_Statistics.mqh:526-530`). **Draw `-`, never `0.00`.** `trading-analytics-6` (CONFIRMED, LOW)
  shows the 0.00 lie already propagating through four other surfaces; this page must not be the
  fifth.
* [CONFIRMED FROM CODE] `average_r` is computed only over trades with `risk_at_entry > 0`
  (`:532-536`), which is why `r_trades` exists. **Always print `(a of b)`.**
* [CONFIRMED FROM CODE] the caveat row draws `st.Caveat()` whenever `!IsTrustworthy()`
  (`trades > 0 && ambiguous_pct <= 10`) — on this sheet, not only in the exported HTML.

#### N.5.3 Pages 2-n — the generator's rows, through `ListRO`

| y | h | element | Standard | Expanded |
|---|---|---|---|---|
| +0 | 13 | group header (`"Rates"`, `"Drawdown"`, …) | 1 row | 1 row |
| +14 | 15 × n | **`ListRO`**: one `Rect` well + one `Label` per row | **8 rows** (120 px) | **17 rows** (255 px) |
| +140 / +280 | 19 | pager `<` `>` + `"%d-%d of 43"` | | |
| +163 / +303 | 22 | `stmt` — `Save statement` | | |

43 rows ⇒ **6 paged screens in Standard, 3 in Expanded**, after the curated page.

[RECOMMENDATION — `ListRO`, the primitive M.3.5 specified and the winner conflated with `List`]
[CONFIRMED FROM CODE] `CSSRWidgets::List` (`SSR_Widgets.mqh:565-589`) draws `Button`/`ButtonC` rows;
a read-only table drawn with it is a table of false affordances — which is exactly `ui-dialogs-16`
(CONFIRMED, IMPROVEMENT), the review card's clicked statistic that stays drawn pressed. `ListRO` is
one `Rect` + cached `Label`s with the same `first`/`shown`/`Remove`-the-tail contract:

| | `List` (9 rows) | `ListRO` (9 rows) |
|---|---|---|
| cold | 9 + 9×9 = **90** | 9 + 9×6 = **63** |
| warm | 10 finds | 10 finds |
| affordance | clickable | **none** |

It is written once and used by PERFORMANCE and KEYS.

#### N.5.4 The struct this page needs, and the throttle

[CONFIRMED FROM CODE — the correction M.4.3 makes to the winner] `SSRReviewRows` takes an
`SSRStatistics`, and **no such struct exists in the port or the panel**: the host computes it at the
moment of opening and hands it in (`SSReplayStandalone.mq5:976-977`, `:3009-3010`;
`SSR_ReviewCard.mqh:78`, `:87`). A card does that once; **a page repaints**.

`ComputeFor` is *"up to 3 passes over `Total()` slots with a struct copy each + O(4096) drawdown
walk"* (`trading-analytics.md` §3) against up to `SSR_MAX_POSITIONS 512`, on the thread that pumps
ticks. At 10 Hz it is unaffordable.

[RECOMMENDATION] **Cache one `SSRStatistics` in `CSSRGroupPort`, recomputed when
`m_acct.ClosedCount()` changes or every 2000 ms, whichever comes first.** Both halves already exist:
`CSSRStatsEngine *m_stats` and `AttachStats()` (`SSR_GroupPort.mqh:49`, `:91`), and the change
detector is already on the wire (`:241`: `out.closed_trades = m_acct.ClosedCount();`). `ClosedCount()`
is O(1), and a closed-trade count that has not moved can change no measure but drawdown.

**The 2 s lag is disclosed on the page, and the split is the design:** live numbers a trainee reads
mid-trade (balance, floating, open count) stay on the status strip, computed per frame; *pattern*
numbers live here, throttled. Beside a live P/L an undisclosed two-second lag would be a lie.

#### N.5.5 What is deleted, and what only moves

| | Fate | Why |
|---|---|---|
| `st1` `st2` `st3` (balance/equity/floating, `:1673-1684`) | **deleted** | duplicated by `stbal`/`stflt` 200 px below (N.1.3) |
| `st7` (*"see the Prop tab"*, `:1744`) | **deleted** | the Eval cell is permanently in the rail |
| `st4` `st5` `st6` (bars/ticks/rejected/guard) | **moved to SESSION** | they describe what the *machine* did. And `core-engine-5` (CONFIRMED, MEDIUM): `bars_consumed` counts a bar once per pump that touches it — **wrong by 10-1500×** — so it must not sit beside trading measures where it reads as one |
| `stmt` (`:1703`, dispatch arm `:2613`) | **kept, verbatim** | it is the JOURNAL (N.9) |

#### N.5.6 Cost

| | objects | cold writes | warm |
|---|---|---|---|
| page 1 | 13 | ~123 | 13 finds |
| a paged screen | 13 | ~102 | 13 finds |
| today's `SheetStats` | 9 | ~105 | 9 finds |
| per frame, either | — | **0** (under R1) | — |
| per 2 s | — | one `ComputeFor` off the draw path | — |

New slots: 37-39, 47-49 (curated page); `ListRO` owns its own widget-cache entries and takes no panel
slot. Both ranges are on M.7's verified free list.

---

### N.6 SESSION — *what the machine is doing, and where I can go*

**Evolves from:** `SheetSession` (`:1877-1913`) — today three diagnostics and **four keyboard hint
lines, three of them factually wrong** (`ui-plumbing-2`, CONFIRMED). This is the page that absorbs
the *consulted* half of the brief's REPLAY, and the one that turns nine orphan wire fields into
information.

#### N.6.1 Standard — 2 Groups, 7 text rows, 5 buttons

| y | h | element | id | slot | source | budget |
|---|---|---|---|---|---|---|
| +0 | 78 | `Group` "Where" | `g1` | — | — | — |
| +14 | 22 | `Button`×3, `bw = 78` | `jump` \| `sessions` \| `bookmark` | — | `SSR_CMD_JUMP`/`_SESSIONS`/`_BOOKMARK` | 10 each |
| +40 | 22 | `Button`×2, `bw = 118` | **`savepos`** \| **`respos`** | — | new dispatch arms | 16 each |
| +66 | 12 | `Label` | `ses1` | 40 | `bookmarks` · `checkpoints` · saved? | `bookmarks`,`checkpoints`,`has_saved_position` | 46 |
| +82 | 62 | `Group` "This session" | `g2` | — | — | — |
| +96 | 12 | `Label` | `ses3` | 42 | `charts: clean` / `leak_advice` | `leak_clean`,`leak_advice` | **52** |
| +110 | 12 | `Label` | **`sesdet`** | 24 | `2 adrift — press F to bring them back` | `charts_detached` | 46 |
| +124 | 12 | `Label` | `ses2` | 41 | `streams 2 · skew 0 ms` | `streams`,`skew_msc` | 40 |
| +148 | 12 | `Label` | **`sesrun`** | 25 | `bars 4,182 · ticks 91,340` | `bars_consumed`,`ticks_emitted` | 46 |
| +162 | 12 | `Label` | **`sesrej`** | 26 | `rejected 0 · guard 0` + p95 when calibrated | `ticks_rejected`,`guard_violations`,`pump_p95_ms`,`perf_calibrated` | 46 |

**174 of 186, 12 px spare.** (M.6's shorthand *"7 rows + 1 Group"* is the row count; this is how the
same 186 px is actually spent.)

#### N.6.2 Expanded — the run gets its own group, and two more orphans surface

| y | h | element | adds |
|---|---|---|---|
| +0..78 | | "Where", identical | — |
| +82..158 | 76 | `Group` "This run": bars · ticks · rejected · guard on four rows | `us_per_tick`, `pump_p95_ms` gated on `perf_calibrated` |
| +162..238 | 76 | `Group` "This session": charts · adrift · streams/skew · **strategies** | `strategy_text`, `Clip(..., 52)` |
| +242 | 12 | `Label` `sesseed` — `random start · seed 4417` | **`seed_text`** (N.2.3), row absent when empty |
| | | **256 of 326 — 70 px deliberately empty** | |

#### N.6.3 Eleven orphan wire fields, nine of which stop being orphans here

[CONFIRMED FROM CODE] `CSSRGroupPort` fills all eleven (`SSR_GroupPort.mqh:122, 123, 132-134, 147,
148, 214, 243, 372, 395`) and a grep for `m_state.<field>` over `SSR_Panel.mqh` returns **0** for
every one of `strategy_text`, `pending_count`, `checkpoints`, `has_saved_position`,
`perf_calibrated`, `us_per_tick`, `pump_p95_ms`, `charts_detached`, `stop_points`, `tp_points`,
`prop_floor`.

| Field | Where N draws it |
|---|---|
| `charts_detached` | status strip `chartsn` (N.1.4) **and** SESSION `sesdet` — the only removal that cost *information* (L.4.3) |
| `checkpoints`, `has_saved_position` | `ses1`, beside the two new buttons that act on them |
| `bars_consumed`, `ticks_emitted`, `ticks_rejected`, `guard_violations` | `sesrun` / `sesrej` (moved off PERFORMANCE) |
| `perf_calibrated`, `us_per_tick`, `pump_p95_ms` | Expanded "This run" |
| `strategy_text` | Expanded "This session"; also TRADE's Expanded context line (M.6) — **one field, two readers, no second formula** |
| `pending_count` | *not drawn* — the rows already show `waiting` per pending (`:1580`) |
| `stop_points`, `tp_points` | *deliberately not drawn* — a stop in points is what the lines design replaced (`:1377-1384`) |
| `prop_floor` | superseded by `prop_daily_floor` / `prop_total_floor`, which EVAL already draws |

**No port change, no engine change, no new observer.** That is the cheapest new information in the
product.

#### N.6.4 Save / Resume — two implemented verbs that have never had a caller

[CONFIRMED FROM CODE] `CSSRGroupPort::SavePosition` (`SSR_GroupPort.mqh:495`) and `ResumePosition`
(`:506`) are real overrides; a grep over `MQL5/` outside `Tests/` and `QA/` finds **no UI caller** —
no button, no `Dispatch` arm, no key. The host calls the controller directly
(`SSReplayStandalone.mq5:2145`).

Two buttons, two `Dispatch` arms (`savepos`, `respos`), and the wire already carries
`has_saved_position` and `checkpoints`.

> [POTENTIAL_RISK] **Neither verb has ever been exercised from a UI, and nothing in this audit has
> run on a terminal.** `ResumePosition` calls `m_group.SeekAllTo(c.Now())` (`:512`) across every
> stream. [RECOMMENDATION] `respos` follows the Reset discipline — arm, then ask on the status strip
> (`ResetArmed()`, `SSR_CONFIRM_MS 4000`) — because a mis-seek costs the session.

#### N.6.5 The gate, restated because it is not optional

[CONFIRMED FROM CODE] `host-expert-7` (CONFIRMED, MEDIUM): the session and range dialogs return
`false` for every non-click event, so keys fall through into `g_panel.OnEvent`
(`SSReplayStandalone.mq5:3228`) — **Space starts the replay, `Tab` opens a virtual trade and `0` arms
the reset while the trainee reads a modal**, and `Render()` then repaints over it. Promoting `Jump…`
and `Sessions…` to permanent buttons makes those dialogs the *normal* way into this moment and
multiplies the exposure. `CSSRReviewCard::OnKey` already shows the fix (it returns `true` for every
key while up). **Copy it before these five buttons ship.**

And `ui-dialogs-1` (CONFIRMED, HIGH) gates `Sessions…` specifically: `ReadAll()` wipes
`session_name` on any step with no edit box (`SSR_SetupPanel.mqh:300`), so a permanent control would
point at a list that is empty for a reason nobody can see from the panel.

#### N.6.6 Deleted here

`ses4`, `keyhint`, `ses5`, `ses6` (`:1885-1912`) and the four catalogue strings `SSR_S_KEYS_1..4`.
[CONFIRMED FROM CODE] `keys.2` says *"R reset"* while `R` is `SSR_CMD_LINES_TOGGLE`
(`SSR_Keys.mqh:162`) and reset is `0` (`:200`); `keys.4` still teaches the `[]` button deleted in
v125 at `SSR_Panel.mqh:934`. They move to KEYS, where they are **generated**. This frees 72 px —
which is exactly what the five new buttons and four new rows above cost.

#### N.6.7 Cost

| | objects | cold writes |
|---|---|---|
| today | 8 | ~102 |
| N, Standard | 17 | ~171 |
| N, Expanded | 22 | ~228 |

New slots: 24-26 (Standard), 27-29 (Expanded rows) — M.7's free list.

---

### N.7 KEYS — *how to drive it*

**Evolves from:** `CSSRKeyCard` (`SSR_KeyCard.mqh`, 372×348 overlay on `H`) — **deleted** — and the
table that already generates it: `SSRKeyBindings()` (`SSR_Keys.mqh:125-218`), 22 bindings, all 22 vk
values distinct, **18 marked `listed`**, the card's height *counted* from the table rather than
chosen.

> **Why this page exists at all.** [CONFIRMED FROM CODE] the first-run guard is
> `if(InpFirstCard && !one_chart_ok && g_panel_chart != 0)` (`SSReplayStandalone.mq5:1736`), so in the
> default configuration the card shows on **neither** pass of the one-window handover
> (`host-expert-4`); where it does show, `Show()` never checks that its fixed `y = 376..480` fits the
> chart, so it is drawn off-screen, `seen.txt` is written anyway, and the only onboarding is consumed
> unread (`ui-dialogs-14`). The only key list is on `H`, and the only string that teaches `H` is on
> that card. **A trainee in the default configuration is never told a single key.**

#### N.7.1 Rows and budget

| y | h | element | Standard | Expanded |
|---|---|---|---|---|
| +0 | 13 | header: `All virtual — nothing reaches a broker.` (`SSR_S_ALL_VIRTUAL`) | Clip 46 | Clip 46 |
| +16 | 15 × n | **`ListRO`**, two columns: `label` at x+8 **Clip 16**, `what` at x+82 **Clip 34** | **9 rows** | **all 18 rows** |
| +154 | 19 | pager `<` `>` + `"%d-%d of 18"` | 2 pages | **absent** |
| | | **173 of 186** | | **299 of 326** |

[INFERENCE] the two columns: `label` ≈ 16 ch @BODY ≈ 82 px from x+8 → x+90; `what` from x+82 is
inside that by 8 px, so the split is **x+8 / x+96**, `what` Clip 30 (≈ 153 px → x+249)… which
overruns. Corrected: `label` Clip 10 (≈ 51 px, and the longest label in the table is `"Num +"`, 5
chars), `what` from **x+66**, Clip 33 (≈ 168 px → x+234). The longest `what` is
`"taller panel: 12 open positions instead of 5"` (43 chars, `SSR_Keys.mqh:213`) — **it must be
shortened at source, not clipped**, to `"taller panel: 12 positions"` (26).

#### N.7.2 What this page fixes the moment it exists

| Finding | How |
|---|---|
| `ui-panel-12` (CONFIRMED, LOW) | `CSSRKeyCard::Show` begins `m_w.RemoveAll()` (`SSR_KeyCard.mqh:72`) and recreates ~41 objects **per frame while up** (~41 deletes + 41 creates + ~450 writes). A page costs **~147 cold writes once per navigation** |
| `host-expert-4` + `ui-dialogs-14` | a permanently drawn rail cell cannot be missed and cannot be consumed unseen |
| `ui-plumbing-1` (CONFIRMED, LOW) | the card's rows are English literals inside `SSRKeyBindings()`. Moving them into a sheet is the moment to add 18 `ENUM_SSR_STR` ids: catalogue **190 → 208**, plus 18 `fa.txt` rows |
| `ui-plumbing-15` (CONFIRMED, LOW) | `Ctrl+K` is not in the table, so `SSRKeyToCommand(75)` returns `SSR_CMD_NONE` and no generated list can name the palette. Add the binding with `listed = true` — the page then teaches the feature a comment at `:929` wrongly records as lost |
| `ui-plumbing-3` (CONFIRMED, LOW) | `SSRKeyHint()` (`SSR_Keys.mqh:271`) is a third hand-written list, also saying *"R reset"*. Generate it from the table. **The product then ships one key list instead of four** |
| `ui-dialogs-16` (IMPROVEMENT) | `ListRO` retires the false affordance here and on PERFORMANCE at the same time |

#### N.7.3 Onboarding: one `if`, not a class

[CONFIRMED FROM CODE] the branch is already there, waiting (`SSR_Panel.mqh:555-557`):

```
      m_place_loaded = true;
      if(!FileIsExist(SSR_PANEL_FILE))
         return false;
```

[RECOMMENDATION] **No `panel.ini` ⇒ the opening destination is KEYS.** One `if` in `RestorePlace()`;
no new class, no new file, no fixed coordinate to be wrong about. **`CSSRFirstRun` is deleted**
(148 lines, prefix `SSRF_`, plus its `seen.txt`).

#### N.7.4 Cost

| | objects | cold writes | per frame |
|---|---|---|---|
| key card today | ~41 | ~450 | **every frame while open** |
| KEYS page, Standard | 20 | ~147 | 0 |
| KEYS page, Expanded | 38 | ~255 | 0 |

---

### N.8 EVAL — *whether I am passing* (the brief's CHALLENGE)

**Evolves from:** `SheetProp` (`:1749-1856`) and `PropRow` (`:1858-1875`) — **unchanged in
structure**. It is the best-reasoned sheet in the product: four meters, every meter with its number
beside it, and *"THIS SHEET COMPUTES NOTHING"* written at the site (`:1732-1740`).

[RECOMMENDATION] Do **not** rename ids or string keys. If the author prefers the word "Challenge", it
is a one-line change in `SSR_Strings.mqh` and one row in `fa.txt`; `SSR_TAB_PROP`, `pp_*` and
`prop_*` stay as they are.

#### N.8.1 The two mutually exclusive cases, and why the new row fits

[CONFIRMED FROM CODE] `ry = y + 30; rh = 25;` (`:1773-1774`), four `PropRow`s, then the deadline
(`+14`, only when `prop_days_max > 0`), the headline (`+16`) and `pp_reset` (`SSR_BTN_H - 4` = 18) —
**only when `prop_state >= 2`** (`:1838-1850`). The sheet's own comment prices the worst case at
**178 of 186** (`:1765-1771`).

The allowance row matters **mid-run**; the headline and Reset exist **only after the run ends**. They
can never coincide:

| | live (`prop_state < 2`) | ended (`prop_state >= 2`) |
|---|---|---|
| `pp_state` + `pp_rules` | y+0 .. y+28, `pp_rules` **`Clip 52`** (was 62; the real budget at 237 px) | same |
| 4 × `PropRow` (label + value + `Meter`) | y+30 .. y+130 | y+30 .. y+130 |
| `pp_dl` deadline, when set | y+130 .. y+144 | y+130 .. y+144 |
| **`pp_room` — allowance in money** (new) | **y+148 .. y+162** | **absent** |
| `pp_head` (`Clip 44`, keep) | absent | y+144 .. y+160 |
| `pp_reset` | absent | y+160 .. y+178 |
| **total** | **162 of 186** | **178 of 186** |

`pp_room` is the second reader of `DailyRoomAfter()` (N.3.5) — *"if that stop gets hit, 320.00 of
today's 500.00 allowance is gone"* — the same pre-clamped wire field TRADE draws as a percentage.
**One owner, two readers, no second formula.**

#### N.8.2 Expanded: nothing, on purpose

`SSR_SHEET_GROW` gives this sheet 140 px more and it should stay **empty**. A fifth meter for a rule
most challenges do not set would teach nobody what it counts — the sheet already argues exactly that
about the deadline (`:1824-1827`). Whitespace is the premium choice here, and it is free.

#### N.8.3 The rail cell raises its hand

[CONFIRMED FROM CODE] `TabName()` already interpolates state (`:1108-1121`): `Pos %d`, and
PASS/FAIL from `prop_state`. Appending ` !` when `prop_daily_used >= 0.8 || prop_total_used >= 0.8`
is the same move — **zero new objects, zero slots, zero geometry** — and it inherits the
`for(int i = n; i < SSR_TAB_MAX; i++) m_w.Remove("tab"+...)` sweep at `:1222-1224` for free. `Eval !`
is 6 characters against a 44 px cell (~8 at BODY), `Clip`ped at 8 under R5.

#### N.8.4 Cost

| | objects | cold writes |
|---|---|---|
| today, live | 15 | ~180 |
| N, live | 16 | ~186 |
| N, ended | 18 | ~201 |

---

### N.9 JOURNAL — not a page in v1, and the exact page it would be

**Where its content lives today, after N:**

| What a journal is for | Where N puts it | Clicks |
|---|---|---|
| the trade I just closed | **POSITIONS → Closed** (N.4.3) | 2 |
| the fill I just got | the four-second toast (`:787-803`) | 0 |
| the whole session, per trade | `stmt` → `ExportCsv` / `ExportHtml` (`SSR_Journal.mqh:165`, `:246`), on PERFORMANCE's footer | 1 |
| what the session *means* | PERFORMANCE's 43 measures + the review card's ≤6 observations | 1 |

**Why not a page.** [CONFIRMED FROM CODE] `CSSRJournal` is an **exporter**. Its only row accessor is

```
   string            Line(const int index, const int digits = 5)     // SSR_Journal.mqh:141
     {
      int seen = 0;
      int total = m_acct.Total();
      for(int i = 0; i < total; i++)
        { SSRVirtualPosition p; if(!m_acct.At(i, p) || !p.IsClosed()) continue; ... }
```

— an O(`Total()`) walk with a **full ~660 B struct copy per slot** (`trading-analytics.md`
preamble), against up to `SSR_MAX_POSITIONS 512`. Eight rows on screen is O(8n) **per frame**. It
also rests on `ui-port-session-2` and `ui-port-session-3` (both CONFIRMED, **HIGH**) for persistence,
and a typed note needs the `OBJ_EDIT` focus path that L.4.2 leaves unsettled.

**[FUTURE FEATURE] The page, specified now so it can be built when the accessor exists.** Its one
prerequisite is `bool CSSRJournal::At(const int index, SSRJournalRow &out)` — an indexed accessor
over a built index, not a walk.

| y | h | element | Standard |
|---|---|---|---|
| +0 | 13 | filter row: `All` · `Wins` · `Losses` · `No stop` — four 58 px `ButtonC` | 1 row |
| +16 | 15 × 8 | `ListRO`, three columns: time Clip 8 · `BUY 0.42 53513` Clip 18 · net Clip 9 | 8 rows |
| +140 | 19 | pager `<` `>` + `"%d-%d of %d"` | |
| +163 | 22 | `[ Save statement ]` — the same `stmt` arm | |

**186 of 186.** Object cost ~120 cold writes, identical in shape to PERFORMANCE's paged screens —
which is the point: when the accessor lands, the page is `ListRO` plus a filter.

**Rail budget:** M.3.3 leaves **39 px — one cell plus 14 px — unspent on purpose**. This is what it
is for.

---

### N.10 SETTINGS — not a page, and the inventory that proves it

**The test:** what would a mid-session SETTINGS page hold that is not already an operated control?

| Candidate | Where it actually lives | Why not a settings row |
|---|---|---|
| speed | chrome, speed band (`DrawSpeed:1045`) | operated every few seconds (R2) |
| risk % | TRADE's ladder + verdict (`:1352-1358`) | it is the decision, not a preference |
| trailing distance | POSITIONS (`:1656-1668`) | it acts on what is open **now** |
| tick fidelity | action strip `Fidelity` + caption chip | a mode, with a verb |
| planning lines on/off | action strip `Lines`, and `R` | operated |
| panel height | `P` — a **wish** whose fact is recomputed per frame (`:676-714`) | not a stored preference |
| panel corner | `SnapToCorner()` via the palette's `move` entry (`:2603-2610`) | one command |
| blind mode | decided pre-session; the chip reports it | changing it mid-session defeats it |
| the other 61 expert inputs | `CSSRSetupPanel`, 4 steps, pre-session | not mid-session settings |

**The inventory is empty.** [CONFIRMED FROM CODE] What remains — 31 commands in four groups
(`SSR_Command.mqh`), dispatched by `RunChosen()` (`:2423`) down the two paths that already exist —
**is** the settings surface, and it costs one `Edit` plus eight `List` rows. It opens on `Ctrl+K`,
tested *before* the key table so nothing can shadow it (`:2827-2832`).

Two changes, both already owed:

1. [CONFIRMED FROM CODE] `ui-plumbing-15` — `SSR_VK_K` is not in `SSRKeyBindings()`, so the generated
   list cannot mention the palette, and the comment at `:929` records it as *"unreachable"* while the
   handler works. **Add the binding, `listed = true`.** KEYS then teaches it (N.7.2).
2. [RECOMMENDATION] The palette is also **the only navigation Compact has** (M.6): `if(!m_compact)`
   guards `DrawRail` and `DrawSheet` together (`:740-752`), and N adds no buttons to Compact. That is
   a named loss with a working answer, not an oversight.

---

### N.11 The whole-panel ledger

#### N.11.1 Per page

| Page | evolves from | objects | cold writes | new slots | new ids |
|---|---|---|---|---|---|
| chrome (HOME + operated REPLAY) | `DrawCaption`/`Clock`/`Transport`/`Speed`/`Actions`/`Status` | ~46 | ~430 (incl. `Slider(10)` 108) | 53 re-used | `chartsn`, optional `stmsg` |
| TRADE | `SheetTrade:1346` | 20 / 12 | ~185 / ~140 | 22, 23 | `verdict`, `whyrow`, `alwrow` |
| POSITIONS | `SheetPositions:1509` | 25 (5 rows) | ~291 | — | `posmode`; `pn<r>` **deleted** |
| PERFORMANCE | `SSRReviewRows` + new `ListRO` | 13 | ~123 / ~102 | 37-39, 47-49 | `perf*`, `pgup`/`pgdn` |
| SESSION | `SheetSession:1877` | 17 | ~171 | 24-29 | `savepos`, `respos`, `sesdet`, `sesrun`, `sesrej`, `sesseed` |
| KEYS | `SSRKeyBindings:125` + `ListRO` | 20 | ~147 | — | `keyhdr`, `ListRO` ids |
| EVAL | `SheetProp:1749` | 16 / 18 | ~186 / ~201 | — | `pp_room` |

#### N.11.2 Per frame, which is the number that matters

| | today | N |
|---|---|---|
| still frame | ~586 property writes + ~211 `ObjectFind` (M.1.2 — an **[INFERENCE]** derived for the rail layout, not section E's measured 561; E.1 and M.1.2 both carry the reconciliation) | **~95 finds + ~30 colour writes ≈ 2 ms** |
| at 10 fps (`SSReplayStandalone.mq5:3063`) | ≈ **0.41 s of repaint per second of wall clock** | ≈ 0.02 s |
| a navigation click | — | one teardown (~25 `Remove`) + one cold draw (~190) ≈ **15 ms, once** |
| key card open | +~450 writes **per frame** | it is a page; 0 |

#### N.11.3 Where each change lands

| Change | File · function | Lines touched |
|---|---|---|
| frame signature + transition teardown (N.0.3) | `SSR_Panel.mqh` · `Render()`, new `Signature()`/`SigChanged()`, `DrawSheet()`, `HideBody()` | ~60 |
| one teardown list per destination (R4) | `SSR_Panel.mqh` · replaces `HideSheets:1284`, `HideSheetArea:2042`, `HideBody:2077` | ~150 |
| `UpgradeSweep()` one-shot (nine v124 `Remove` + `spdseg10..19`) | `SSR_Panel.mqh` · `Create()`, removing `:932-934`, `:1189-1191`, `:1241-1243` | ~20 |
| strip: drop `stfid`, add `chartsn`, re-column | `DrawStatus:1915-2036` | ~25 |
| speed: 10 cells over 20 stops, `Clip` the meaning | `DrawSpeed:1045`, `Dispatch`'s `spdseg` arm `:2589` | ~20 |
| TRADE: verdict, `whyrow`, `alwrow`, deal pair by sub-state | `SheetTrade:1346` | ~50 |
| `DailyRoomAfter()` + one wire field | `CSSRPropEvaluation` (`SSR_PropEvaluation.mqh`, beside `DailyFloor():295`); `SSRUiState`; `CSSRGroupPort::ReadState` | ~20 |
| POSITIONS: three columns, `!` prefix, Open/Closed, `WantClosed` | `SheetPositions:1509`, `PosCap():434`, `Dispatch:2659`, `CSSRGroupPort` | ~120 |
| PERFORMANCE page + `ListRO` + throttled `SSRStatistics` | new `SheetPerformance` replacing `SheetStats:1671`; `CSSRWidgets::ListRO` beside `List:565`; `CSSRGroupPort` (`m_stats:49`, `AttachStats:91`) | ~190 |
| SESSION rehome + 9 orphans + 5 buttons | `SheetSession:1877`, `Dispatch` | ~90 |
| KEYS page; delete `CSSRKeyCard`, `CSSRFirstRun` | new `SheetKeys`; `SSR_Keys.mqh:125-218` (+`Ctrl+K`, generated `SSRKeyHint():271`); `RestorePlace:553` | +170 / −280 |
| rail 5 → 6 cells + condition marks | `SSR_Theme.mqh:542-546`, `TabCount():1103`, `TabName():1108`, `DrawRail:1209` | ~35 |
| R5 budgets + `Clip()` at every sheet site, audit A22 | every `Text(`/`Label(` under `/Ui/` | ~200 mechanical |

Terminology and mechanisms preserved exactly: latch polling as the one click mechanism
(`PollClicks:2445`, palette polled first and alone, 200 ms debounce), the `tabN` dispatch parse
(`:2569`), `TabCount()` as a question with the re-clamp at `:745`, the status ladder's priority order
and its rationale, *removed-not-undrawn* (I7), modes as chips, operated-vs-consulted, the wish/fact
split, `SheetProp` computing nothing, and both compile-time switches.

---

### N.12 What these pages do not fix, and what could still be wrong

* **Every pixel here is derived, never measured.** [POTENTIAL_RISK] `Extent()`/`CheckFrame()` sees
  **sized objects only** and excludes labels by design (`SSR_Widgets.mqh:120-128`, invariant I10), so
  no instrument in the product can confirm a single character budget in this section. Audit **A22**
  (M.2 R5) is the only thing that can, and it checks *call sites*, not glyphs.
* **Persian is unverifiable.** [POTENTIAL_RISK] `rtab.prop = ارزیابی` (7 glyphs) plus an appended
  ` !`, and `rtab.positions` plus a Latin digit, are mixed-direction strings in a renderer with no
  bidi and no clipping (L.3.3). Every character budget above is a Latin estimate.
* **L.4.2 is still unsettled.** These pages are designed for the pessimistic branch — no drag, no
  hover, no focus, no thumb. The one place it bites is TRADE's `tagbox`: `m_tag_focus` is assigned
  only inside the mouse-move handler (`:2903-2907`), so if mouse events do not arrive the setup tag
  has no focus path (`ui-panel-11`, POTENTIAL_RISK). N changes nothing there; the transition latch is
  its strongest available mitigation, because a still frame no longer touches the box at all.
* **`ui-dialogs-4` (CONFIRMED, MEDIUM)** — two review *observation* sentences exceed 63 characters
  for every possible value, and the ambiguous-bar line renders as *"…reached both the stop and the
  t"*. They live in `SSR_Review.mqh` `StringFormat` literals, outside `T()` and outside every page
  here. PERFORMANCE reads the same generator and does **not** fix them.
* **`core-engine-5` (CONFIRMED, MEDIUM)** — `bars_consumed` is wrong by 10-1500×. SESSION draws it;
  SESSION does not fix it, which is precisely why it must not sit beside trading measures.
* **`chart-7` (CONFIRMED, LOW)** — `LeakGuard::Advice` is written far longer than the ~49
  characters its consumer can show. `Clip 52` makes the cut honest; shortening it at source makes it
  useful. Do both.
* **`chart-12` (CONFIRMED, LOW)** — every word the chart layer draws (`"STOP - drag me"`, `BUY`/
  `SELL`/`SL`/`TP`) is an English literal outside `T()`. No page here can reach it.
* **Nothing in this section has been run on MT5**, and the author never has. Every `y`, every `h` and
  every character budget above is arithmetic over a constant or a literal in the source, waiting for
  one terminal to confirm or refute it.

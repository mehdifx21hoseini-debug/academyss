## R. COACHING / SESSION REVIEW

*Scope: `CSSRStatsEngine` and `SSRStatistics` (`Trading/SSR_Statistics.mqh`, 720 l), the row and
sentence generator `SSR_Review.mqh` (224 l), `CSSRReviewCard` (`Ui/SSR_ReviewCard.mqh`, 256 l), and
the record they all rest on — `SSRVirtualPosition` (`Trading/SSR_TradeTypes.mqh:178-291`) and
`CSSRJournal`'s exported row (`Trading/SSR_Journal.mqh:68-90`). Build v125. This section is written
against the information architecture of M and the page specifications of N: PERFORMANCE is a
destination (N.5), the review card stays an overlay (M.3.6), JOURNAL is not a page in v1 (N.9), and
the `SSRStatistics` struct is cached and throttled in `CSSRGroupPort` (N.5.4).*

---

### R.0 The position, in one page

The product already knows more about how a session was traded than any screen shows. Forty-three
measures exist, and six of them sit in a struct block `SSR_Statistics.mqh` calls DISCIPLINE and
introduces as *"What a coach reads before the profit… the part a student can fix, and the part that
decides whether the profit repeats"* (`:87-94`, fields at `:95-100`). One of the six is provably
wrong (`revenge_trades`, `trading-analytics-7`), one measures something other than what its name
implies (`risk_spread_pct`, R.4.9), one inherits a drawdown figure that shrinks as a long session
runs (`recovery_factor`, `trading-analytics-9`), and **none of the six is reachable from any panel
screen at all** — only from a 520 px modal and an exported HTML file (L.2.2).

**The one defect.** [CONFIRMED FROM CODE] Every consumer reaches the account through
`CSSRTradingEngine::At(i, SSRVirtualPosition&)`, and *"positions are stored in slot order =
creation (ticket) order; `At(i)` walks slots, never a close-time order"* (`trading-analytics.md`
preamble). Two CONFIRMED findings are instances of it:

* `trading-analytics-3` (CONFIRMED, **MEDIUM**) — `ClosedDrawdownFor` walks the balance curve in
  open order, so `max_drawdown_closed` is wrong whenever positions overlap
  (`SSR_Statistics.mqh:695-716`).
* `trading-analytics-7` (CONFIRMED, LOW) — revenge detection compares each trade with the
  **previous slot**, not the most recent loss (`:497-500`), so an interleaved winner hides the
  revenge entry that follows a loss one minute later.

Everything this section asks for — a chronological timeline, overtrading in a rolling window,
repeated loss patterns, best and worst decision, a correct revenge count — needs trades in **time
order**. That is one function, built once per recompute, and it is R.2.

**What must never happen.** [CONFIRMED FROM CODE] `SSR_Review.mqh:24-31` states the product's rule:

```
   //|  AND IT NEVER COACHES.                                           |
   //|                                                                  |
   //|  An observation states what was counted and stops: "1 of 2 trades |
   //|  opened within two minutes of a loss". It does not say that was   |
   //|  revenge trading, that it was bad, or what to do instead. The     |
   //|  trader knows what happened in that session and this program does |
   //|  not - inventing the interpretation is how a measurement tool     |
   //|  turns into a horoscope.
```

Every metric below obeys that rule, and R.1 makes it a contract with three parts rather than a
sentiment.

**The shape of the work.**

| | |
|---|---|
| new struct fields on `SSRVirtualPosition` | **9**, all appended at the tail of the `pos` record (R.3) |
| new fields on `SSRStatistics` | **17**, in one new `BEHAVIOUR` block beside `DISCIPLINE` |
| new generators | `SSRTimeline()` (chronological rows) and `SSRVerdictRows()` (the twelve-line session review) |
| existing generator | `SSRReviewRows()` grows 43 → **53**; nothing is renamed or removed |
| `CSSRReviewCard` | gains a three-way view switch, `ListRO`, and a timeline; loses `ui-dialogs-16` |
| CONFIRMED findings closed | `trading-analytics-3`, `trading-analytics-7`, `ui-dialogs-16`, `ui-dialogs-4` (by clipping the sentences this section rewrites) |
| findings this section must NOT hide | `trading-analytics-10` (R excludes commission), `trading-analytics-9` (equity ring), `trading-analytics-6` (PF 0.00), `trading-analytics-8` (MAE/MFE in price units) |

---

### R.1 The rule this section is bound by: measurement, not interpretation

#### R.1.1 This product cannot detect emotion, and must never say it can

[RECOMMENDATION — stated here so it can be quoted in a review, a release note and a refusal.]

**Nothing in this codebase observes a trader.** It observes an account. There is no camera, no
keystroke timing, no heart rate, no self-report field, and there is no path by which one could
exist: the only inputs are `CHARTEVENT_OBJECT_CLICK` latches (`SSR_Panel.mqh:2445`), a key table of
22 bindings (`SSR_Keys.mqh:125-218`), and the virtual account's own state transitions. A claim of
*tilt*, *fear*, *greed*, *confidence*, *impatience* or *discipline as a trait* is not a measurement
this product can make, and printing one would be a lie with a number beside it.

What it can do is count actions, exactly, and name the count. The file already says so, at the one
place a behavioural number is computed (`SSR_Statistics.mqh:489-495`):

```
         //| REVENGE, defined narrowly enough to be checkable.                |
         //|                                                                  |
         //| Not "traded a lot after a bad run" - that is a judgement. This   |
         //| is one fact: the trade before this one closed at a loss, and     |
         //| this one was opened inside two replay minutes of it. Anyone can  |
         //| verify it against the trade list, which is the only kind of      |
         //| coaching number worth printing.
```

**"Revenge trade" is therefore a label for a counted action, not a diagnosis of a state of mind,
and every surface that prints it must be able to show the two trades it came from.** The same
applies to every name in this section: *overtrading*, *late entry*, *oversized*, *risk violation*
are column headings over counts, and the count's definition travels with it.

#### R.1.2 The three-part contract every behavioural metric must satisfy

[RECOMMENDATION] No behavioural measure ships unless all three parts are drawn or exportable:

1. **The action counted.** A state transition or a field comparison, expressible as one sentence a
   user can check against the trade list.
2. **The threshold, and where it came from.** Either a named constant in the source
   (`SSR_REVENGE_WINDOW_MSC` = 120 000 ms, `SSR_Statistics.mqh:40`), or a value the **user
   themselves declared** (the risk % on TRADE, the prop rules). Never a number chosen because it
   looked right in one session.
3. **The sample it rests on.** `a of b`, always — the pattern `r_trades` already establishes
   (`SSR_Statistics.mqh:70-71`, and `SSRStatistics::Caveat()` at `:144-156`).

#### R.1.3 Absent, not zero — and the existing gate stays

[CONFIRMED FROM CODE] `SSR_Review.mqh:33-37`: *"'0 revenge trades' out of one trade is not a clean
sheet, it is a sample size of one."* `SSRReviewObservations()` enforces it with a hard floor —
`if(st.trades < 3) { ArrayResize(out, 0); return 0; }` (`:187-191`).

[RECOMMENDATION] Every new observation and every new verdict line in this section passes through
the same gate, and three of them need a **higher** floor because their denominator is smaller than
`trades`:

| Line | Floor | Why |
|---|---|---|
| any observation | `trades >= 3` | existing (`:187`) |
| risk consistency | `risk_samples >= 3` | existing precedent (`:197`) |
| overtrading | `trades >= 5` **and** session span ≥ 60 replay minutes | a rate over four trades in twenty minutes is a sample, not a rate |
| repeated loss pattern | `losses >= 3` | two losses in a row is a pair, not a pattern |
| best / worst decision | at least one trade on **each** side of the rule test | otherwise the line ranks a set of one against nothing |

#### R.1.4 What the wording may and may not do

| May be drawn | May never be drawn |
|---|---|
| `2 of 12 trades opened within 2 min of a loss` | `you were tilting` |
| `risk varied 41 % over 9 trades` | `poor discipline` |
| `3 trades risked more than the 1.0 % you set` | `you were overconfident` |
| `largest loss among trades that broke a rule: -180.20 (no stop)` | `your biggest mistake was greed` |
| `highest R inside your own rules: +2.4 R` | `your best decision` *(unqualified)* |
| `no stop 1` | `always use a stop` |

The right-hand column is not a style preference. It is the difference between a document a coach can
hand a student and a document a student can dismiss.

---

### R.2 The prerequisite everything else needs: chronological order

#### R.2.1 The problem, cited

[CONFIRMED FROM CODE] `CSSRStatsEngine::ComputeFor` iterates `for(int i = 0; i < total; i++)` over
`m_acct.At(i, p)` (`SSR_Statistics.mqh:406-408`) and carries two rolling variables that assume the
loop is in time order:

```
      long   prev_close    = SSR_INVALID_TIME;   // of the trade before, in open order
      bool   prev_was_loss = false;
```

Slot order is allocation order. [CONFIRMED FROM CODE] a slot is allocated in `Open()` at
`int i = m_count++` (`SSR_TradingEngine.mqh:719`), which for a **pending order** happens at
`request_msc` and not at `open_msc` — so even with strictly non-overlapping trades, slot order and
open order differ (this is the nuance `verified.json` adds to `trading-analytics-7`). Close order
differs from both.

#### R.2.2 The fix: two index arrays, built once

[RECOMMENDATION] Add to `CSSRStatsEngine`, private:

```
   int               m_by_open[];    // slot indices, ascending open_msc
   int               m_by_close[];   // slot indices, ascending close_msc
   int               m_ord_n;        // closed trades in both
   bool              BuildOrder(const string tag);
```

`BuildOrder` walks `Total()` once, collects the slots that are closed and match `tag`, and
insertion-sorts two `int` arrays. **It copies no `SSRVirtualPosition`** — the index is `int`, and
the `~660 B` struct copy (`trading-analytics.md` preamble) happens only when a pass dereferences a
slot it has already decided to visit.

| | today | with `BuildOrder` |
|---|---|---|
| passes over `Total()` | up to 3, each copying every struct | 1 index build (no copy) + the same up-to-3 passes |
| sort cost | — | insertion sort over `n` **closed** trades, not `SSR_MAX_POSITIONS 512` |
| where it runs | inside `ComputeFor`, on the tick thread | unchanged — and under N.5.4 `ComputeFor` runs at most every 2000 ms, off the draw path |

[INFERENCE] Insertion sort is the honest size of the problem here, and the file already uses one
for the same reason: *"a handful of tags at most; an insertion sort is the honest size of the
problem"* (`SSR_Journal.mqh:525-527`). A session with 512 closed trades would cost ~130 000
comparisons of a `long`, once per two seconds — measured against the panel's own currency of
0.07 ms per property write (`SSR_Widgets.mqh:31-38`), that is well under one repaint.

#### R.2.3 What it fixes and what it unlocks

| | |
|---|---|
| **fixes** `trading-analytics-3` | `ClosedDrawdownFor` walks `m_by_close[]`; the balance curve is then the balance curve |
| **fixes** `trading-analytics-7` | revenge compares against the most recent **close that was a loss**, walking `m_by_close[]` and `m_by_open[]` together (R.4.2) |
| **unlocks** | the timeline (R.7), overtrading windows (R.4.1), loss clusters (R.4.8), best/worst decision (R.6), and the "largest measured deviation" rank (R.6.3) |
| **does not change** | `win_streak` / `loss_streak`. `verified.json` corrects `trading-analytics-3` on exactly this point: *"counting streaks by entry order is a defensible convention"*. [RECOMMENDATION] leave them on `m_by_open[]` and say which order the row means, in the row |

**Sequencing.** `BuildOrder` lands **first**. Every other change in this section is written against
it, and building the timeline on slot order would ship a screen that disagrees with the chart.

---

### R.3 What is recorded today, and the nine fields that must be added

#### R.3.1 The record, field by field

[CONFIRMED FROM CODE] `SSRVirtualPosition` (`SSR_TradeTypes.mqh:178-291`) and what `CSSRJournal`
exports from it (`SSR_Journal.mqh:68-90`, the `Row()` formatter, 18 columns):

| Field | Line | In the CSV? | Column |
|---|---|---|---|
| `ticket`, `type`, `tag`, `note` | `:180-181`, `:246-247` | yes | `ticket` `type` `tag` `note` |
| `volume`, `volume_initial` | `:184-185` | `volume_initial` only | `volume` |
| `request_price`, `request_msc`, `request_type` | `:189-191` | **no** | — |
| `open_price`, `open_msc` | `:193-194` | yes | `open_price` `open_time` |
| `sl`, `tp` | `:195-196` | **no** | — |
| `trail_points`, `trail_peak` | `:197-198` | **no** | — |
| `close_price`, `close_msc`, `reason` | `:200-202` | yes | `close_price` `close_time` `reason` |
| `commission`, `swap`, `profit` | `:204-206` | yes | three columns |
| `mae`, `mfe` | `:209-210` | yes | `mae` `mfe` (`%.5f`, price units) |
| `spread_at_entry`, `spread_at_exit` | `:221-222` | **no** | — |
| `ambiguous` | `:226` | yes | `resolution` = `ASSUMED\|observed` |
| `risk_at_entry` | `:244` | derived only | `r` = `RMultiple()`, empty when undefined |
| `legs[]`, `leg_count` | `:236-237` | **no** | — |

Two consequences that matter for coaching, both [CONFIRMED FROM CODE]:

* **The current `sl` is the only stop the record has.** `Modify()` writes `m_pos[i].sl = Norm(sl)`
  (`SSR_TradingEngine.mqh:850`), `BreakEven()` writes `m_pos[i].sl = m_pos[i].open_price`
  (`:925`), and `ApplyTrailing()` writes it on any tick that advances the peak (`:313`, `:321`).
  **None of them records that it happened, or what the value was before.** A trade whose stop was
  widened twice and a trade that ran to its original stop are indistinguishable in the file.
* **`risk_at_entry` is money, not percent** — `m_risk.RiskOf(volume, |open_price - sl|)`
  (`SSR_TradingEngine.mqh:749-751`), and `RiskOf` returns `ticks * tick_value * volume`
  (`SSR_RiskEngine.mqh:79-85`). The account it was a percentage *of* is not recorded.

#### R.3.2 The nine fields, and the rule for adding them

[CONFIRMED FROM CODE] The file states its own extension rule at the position record's comment
(`SSR_TradingEngine.mqh:1073-1077`):

```
                //--- APPENDED, never inserted: a reader that predates
                //--- these two fields stops at `note` and is unharmed,
                //--- and a file that predates them restores as zero
                "spread_at_entry|spread_at_exit");
```

and the reader is tail-tolerant by construction — `SSRFieldDouble(f, i, def)` returns `def` when
the field is absent (`SSR_SessionFile.mqh:409-413`). **Every field below is appended after
`spread_at_exit`, in this order, and the `f.Comment(...)` string at `:1067-1077` grows with it.**

| # | Field | Type | Set where | Answers |
|---|---|---|---|---|
| 1 | `risk_pct_at_entry` | `double` | `Open()` **and** `CheckPendings()` (R.4.3) | oversized positions; risk consistency **in percent** |
| 2 | `sl_initial` | `double` | `Open()`, `= Norm(sl)` | was the stop moved at all, and which way |
| 3 | `tp_initial` | `double` | `Open()`, `= Norm(tp)` | was the target cut |
| 4 | `sl_moves` | `int` | `Modify()`, `BreakEven()` — **not** `ApplyTrailing()` | how many operator decisions touched the stop |
| 5 | `sl_widened` | `int` | `Modify()`, when the new stop increases `\|open_price - sl\|` | the only stop move that increases risk |
| 6 | `tp_moves` | `int` | `Modify()` | how many operator decisions touched the target |
| 7 | `plan_price` | `double` | handed to `Open()` by `CSSRGroupPort` at the click | late entry: distance from the price the plan was drawn at |
| 8 | `plan_msc` | `long` | as above | hesitation: how long between arming the lines and pressing |
| 9 | `risk_pct_declared` | `double` | handed in beside `plan_price`; `CSSRGroupPort::m_risk_percent` | risk violations — the referent without which "violation" means nothing |

> **[CONFIRMED FROM CODE] The trap that will swallow half the samples if it is missed.**
> **There are two entry points, not one.** `Open()` fills `risk_at_entry` and `spread_at_entry` at
> `SSR_TradingEngine.mqh:749-752`, and **`CheckPendings()` fills them again at `:350-354`** when a
> pending order is hit:
>
> ```
>          if(m_pos[i].sl > 0.0)
>             m_pos[i].risk_at_entry =
>                m_risk.RiskOf(m_pos[i].volume,
>                              MathAbs(m_pos[i].open_price - m_pos[i].sl));
>          m_pos[i].spread_at_entry = SpreadPoints();
> ```
>
> A pending order's real entry - its price, its spread, its equity, its instant - exists only here;
> `Open()` returned at `:738` before any of it was known. **Every "at entry" field in R.3.2 must be
> written in both places**, and `risk_pct_at_entry` must be computed against `Equity()` at the
> **fill**, not at the placement. Miss it and every pending order silently drops out of the
> risk-violation, oversized and risk-consistency denominators - with no symptom other than numbers
> that look reasonable and were computed over half the session.

**Why `sl_moves` excludes trailing.** [CONFIRMED FROM CODE] `ApplyTrailing` runs inside `CheckStops`
on every tick (`SSR_TradingEngine.mqh:521`) and advances the stop whenever the peak advances.
Counting those would make a trailing stop read as several hundred stop moves and drown the one
move a coach cares about. The trailing decision is counted once instead, where the operator makes
it: `SetTrailing()` (`:855-863`) sets a new `bool trail_armed` — which is field 4's sibling and is
folded into `sl_moves == 0 && trail_armed` rather than taking a ninth slot.

**Why `plan_price` / `plan_msc` come from the port, not the engine.** [CONFIRMED FROM CODE] The
engine knows nothing about lines. `CSSRGroupPort::OpenFromLines` (`SSR_GroupPort.mqh:715-756`)
already holds `m_lines.SlPrice()` / `TpPrice()` / `EntryPrice()` and passes the dragged prices
verbatim — *"the exact prices the user dragged to - not a distance recomputed from the bid"*
(`:748-750`). The port is therefore the one place that knows when the plan was drawn. It stamps
`m_plan_msc` / `m_plan_bid` when `CSSRTradeLines` arms, and hands both to the engine at the click,
exactly as it already hands `sl` and `tp`.

#### R.3.3 What the journal must then export

[RECOMMENDATION] `CSSRJournal::Row()` (`SSR_Journal.mqh:68-90`) grows from 18 columns to 25, in the
same append-only spirit — the class report splits on `,` and reads by header name
(`SSR_ClassReport.mqh:224`, `:259-266`), so appended columns are ignored by an old reader:

```
   ...,resolution,note,risk_pct,risk_pct_set,sl_initial,sl_moves,sl_widened,tp_moves,plan_gap_r
```

and the `#` header block (`:186-208`) gains seven behaviour keys so a coach comparing twenty
students can see who is revenge trading, not only who made money:

```
   # revenge_trades,2
   # risk_violations,3 of 12
   # oversized_trades,1
   # stop_widened_trades,2
   # late_entries,4 of 11
   # max_trades_per_hour,7
   # risk_spread_pct_of_equity,18.4
```

[FUTURE FEATURE] `SSRStudent` (`SSR_ClassReport.mqh:41-70`) gaining the same seven fields turns the
class report into a behaviour comparison. It is a separate change with a separate risk, and it is
named here only so the CSV header is designed for it now rather than re-cut later.

---

### R.4 The behavioural metrics, one at a time

Format for each: **what is counted**, the **threshold and its source**, the **data needed**,
whether **`CSSRJournal` records it today**, the **field to add**, **where the code lands**, and
**what it must never say**.

#### R.4.1 Overtrading

| | |
|---|---|
| **Counted** | entries opened inside a rolling 60-replay-minute window; the maximum such count over the session, and the session rate `trades / hours` |
| **Threshold** | **none is invented.** The number is reported; no line calls it "too many". The only comparison drawn is against the trader's own session: `most in any hour: 7 · session average 2.4` |
| **Data** | `open_msc` of every closed trade, in open order |
| **Journal today** | **yes** — `open_time` is column 5 of `Row()` (`SSR_Journal.mqh:72`). No new field |
| **Needs** | `m_by_open[]` (R.2). Two new `SSRStatistics` fields: `max_trades_per_hour` (int), `trades_per_hour` (double) |
| **Lands in** | `CSSRStatsEngine::ComputeFor`, a two-pointer sweep over `m_by_open[]` after the main pass — O(n), no second struct copy |
| **Never says** | "you overtraded". It says how many, in what window, against the session's own average |

[INFERENCE] The window must be **replay** minutes, not wall-clock minutes, and it must be said on
the row. At `SSR_SPEED_MAX` an hour of chart time passes in seconds; a rate quoted in wall-clock
time would measure the speed slider, not the trader.

#### R.4.2 Revenge trading — the existing measure, corrected

| | |
|---|---|
| **Counted** | a trade opened within `SSR_REVENGE_WINDOW_MSC` (120 000 ms, `SSR_Statistics.mqh:40`) of the **most recent losing close**, whichever slot that loss occupies |
| **Threshold** | the existing named constant, with its existing justification at `:35-39`: *"long enough that a planned re-entry at the level that just stopped out still qualifies, short enough that a setup genuinely waited for does not"* |
| **Data** | `open_msc`, `close_msc`, and net (`profit + swap - commission`) of every closed trade, in **both** orders |
| **Journal today** | **yes** — `open_time`, `close_time`, `profit`, `commission`, `swap` are all columns. No new field |
| **Needs** | `m_by_open[]` + `m_by_close[]`. One new field: `revenge_first_msc` (long), so the first instance can be pointed at |
| **Lands in** | `CSSRStatsEngine::ComputeFor`, replacing `:497-500` and deleting the `prev_close` / `prev_was_loss` rolling pair at `:401-402`, `:511-512` |
| **Never says** | "revenge". It says *"opened within two minutes of a loss"* — which is what `SSR_Review.mqh:193-195` already prints, and what the timeline mark expands to in the legend (R.7.3) |

[CONFIRMED FROM CODE] This closes `trading-analytics-7`. The corrected algorithm, stated so it can
be checked: walk `m_by_open[]`; maintain `last_loss_close_msc` as the largest `close_msc` among
losing trades whose close is **at or before** the candidate's `open_msc`, obtained by advancing a
second pointer through `m_by_close[]`. Both pointers move forward only, so the pass stays O(n).

> [INFERENCE — the honest limit of this measure.] A trade opened 121 seconds after a loss is not
> counted, and a planned re-entry opened 90 seconds after one is. The threshold is a line drawn in
> a continuum, and the row must therefore always print the window it used. The alternative — a
> smooth "revenge score" — would be a number nobody can verify against the trade list, which is the
> thing `:489-495` forbids.

#### R.4.3 Risk violations — against the risk the trader declared

| | |
|---|---|
| **Counted** | closed trades whose `risk_pct_at_entry` exceeded the risk percentage in force when the order was placed, by more than a tolerance |
| **Threshold** | the **user's own** `risk_percent` (`CSSRGroupPort::m_risk_percent`, on the wire at `SSR_GroupPort.mqh:242`), plus a tolerance of **one volume step's worth** — because `LotForRisk` rounds *down* to the step (`SSR_RiskEngine.mqh:118-128`), a correctly sized trade can only ever risk **less** than asked. Any excess is therefore an operator choice, not rounding |
| **Data** | risk in money at entry, the account it was a fraction of, and the declared percentage |
| **Journal today** | **partly.** `r` (the R multiple) is exported, and `risk_at_entry` is derivable from it, but **the declared percentage and the account balance at entry are recorded nowhere.** A 50-money risk is 0.5 % of 10 000 and 5 % of 1 000, and the file cannot tell which |
| **Needs** | fields 1 and 9 — `risk_pct_at_entry` and `risk_pct_declared`. Without the declared figure "violation" has no referent and the measure degrades into "bigger than the others", which is R.4.4's job and not this one's |
| **Lands in** | `CSSRTradingEngine::Open` (`:749-752`) and `CheckPendings` (`:326-360`) for the recording — `m_risk.RiskPercentOf(Equity(), volume, open_price, sl)`, an accessor that **already exists at `SSR_RiskEngine.mqh:137-143` and has no production caller** (a grep over `MQL5/` finds only `SSR_T9_Trading.mq5:75`). The counting lands in `ComputeFor` |
| **Never says** | "you broke your rules". It says *"3 of 12 trades risked more than the 1.0 % set at the time"* |

#### R.4.4 Oversized positions

| | |
|---|---|
| **Counted** | closed trades whose `risk_pct_at_entry` is at least **twice** the median `risk_pct_at_entry` of the session |
| **Threshold** | the **session's own median**, and the multiple is the same `2.0` the product already uses for `wide_spread_trades` (`SSR_Statistics.mqh:576`), whose comment explains exactly why a session-relative threshold is the honest one: *"'Wide' has no absolute meaning… so it is defined against THIS session's own average"* (`:562-568`) |
| **Data** | `risk_pct_at_entry` for every closed trade |
| **Journal today** | **no.** The CSV has no risk column at all; `r` is the *outcome* in R, not the *size* of the risk |
| **Needs** | field 1 `risk_pct_at_entry`, exported as the new `risk_pct` column |
| **Lands in** | `ComputeFor`, in the same second pass that already exists for `wide_spread_trades` (`:570-583`) — the median needs the first pass to have finished, exactly as the spread average does. New fields: `oversized_trades` (int), `median_risk_pct` (double) |
| **Never says** | "you overleveraged". It says *"1 trade was sized at 2.4 %, against a session median of 0.9 %"* |

[RECOMMENDATION] Median, not mean. One 5 % trade drags a mean far enough that the next three
ordinary trades stop qualifying, and the measure then hides the second instance of the thing it
exists to find.

#### R.4.5 Late entries

This is the measure with the weakest data and the most ways to get it wrong, so the rejected
options are recorded beside the accepted one.

**[CONFIRMED FROM CODE] Rejected: anything derived from `m_bar`.** The trading engine caches the
bar at `OnBarContext` (`SSR_TradingEngine.mqh:593-598`), and the observer contract states that the
bar arrives **before** the ticks made from it, *"so an observer can see the bar's full range and
know that both levels fall inside it BEFORE deciding which was hit first"*
(`SSR_ITickObserver.mqh:13-19`). `m_bar.high` and `m_bar.low` therefore describe a part of the bar
the replay has **not played yet**. A "you entered 1.4 R above the bar's low" metric computed from
it is lookahead, and would tell a trainee they were late using information they could not have had.

**Rejected: pending-order slippage.** `request_price` vs `open_price` is already recorded on the
struct (`SSR_TradeTypes.mqh:189-194`) and is a real measure — but it is fill displacement, not
lateness, and it exists only for pendings.

| | |
|---|---|
| **Counted** | for a trade taken from the planning lines: the distance between the bid **at the moment the lines were armed** and the fill price, expressed in the trade's own R, signed so that "the price ran in my direction while I waited" is positive. Plus the wait itself, `open_msc - plan_msc`, in seconds |
| **Threshold** | reported, not judged. A trade is counted as a *late entry* when the signed gap is **≥ 0.5 R** — half the trade's own declared risk given away before the entry. The unit is the trader's own stop, not a fixed pip count, for the same reason `wide_spread_trades` is session-relative |
| **Data** | the bid and the instant at which the plan was drawn; the fill price; `risk_at_entry` |
| **Journal today** | **no.** Nothing records that a plan existed before the click. The lines are chart objects (`CSSRTradeLines`), and `OpenFromLines` consumes them and disarms (`SSR_GroupPort.mqh:752-755`) |
| **Needs** | fields 7 and 8 — `plan_price` (the bid at arming) and `plan_msc`. Exported as one derived column, `plan_gap_r` |
| **Lands in** | `CSSRGroupPort` stamps `m_plan_msc` / `m_plan_bid` where the lines arm (beside `ToggleEntryLine`, `:687-713`, and wherever `CSSRTradeLines::Arm` is called); `CSSRTradingEngine::Open` stores them; `ComputeFor` counts. New fields: `late_entries` (int), `late_samples` (int), `avg_plan_gap_r` (double), `avg_plan_wait_sec` (double) |
| **Never says** | "you chased". It says *"4 of 11 planned entries were taken after the price had moved 0.5 R or more in the trade's direction"* |

> [POTENTIAL_RISK] The denominator is **trades taken from armed lines**, not all trades. A trade
> opened with the bare `BUY` / `SELL` buttons (`CSSRGroupPort::MarketAt` via `:1087-1102`) has no
> plan and no `plan_msc`, and must be excluded rather than counted as on time. `late_samples` is
> what makes that visible, and the row prints `a of b` for exactly this reason.

#### R.4.6 Moving the stop

| | |
|---|---|
| **Counted** | (a) operator stop moves, `sl_moves`; (b) of those, the ones that **increased** risk, `sl_widened`; (c) trades that ended with a stop different from the one they started with, `sl != sl_initial` |
| **Threshold** | none. All three are counts. A stop that moved **toward** the entry reduces risk and is reported separately from one that moved away — the product must not collapse "moved to break even" and "widened to avoid being stopped out" into one number |
| **Data** | the stop as placed, the stop now, and how many operator decisions separated them |
| **Journal today** | **no.** `sl` is not a CSV column at all, and no field records the original value or any change. `Modify()` overwrites it (`SSR_TradingEngine.mqh:844-853`) and `BreakEven()` overwrites it (`:920-928`), neither recording anything |
| **Needs** | fields 2, 4, 5 — `sl_initial`, `sl_moves`, `sl_widened`, plus the `trail_armed` flag folded into field 4 (R.3.2) |
| **Lands in** | the three verbs that write `sl`: `Modify` (`:850`), `BreakEven` (`:925`), `SetTrailing` (`:855-863`). `ApplyTrailing` (`:302-323`) deliberately records **nothing** |
| **Never says** | "you moved your stop out of fear". It says *"2 trades had their stop widened after entry, adding 84.00 to the risk"* |

[CONFIRMED FROM CODE] **Two facts that must be stated wherever this metric is drawn.**

1. `Modify(ticket, sl, tp)` **has no UI caller.** A grep over `MQL5/` outside the engine finds it
   only at `SSR_IStrategy.mqh:111` — a strategy seam. The panel's row buttons reach
   `BreakEven` (`SSR_Panel.mqh:2679` → `SSR_GroupPort.mqh:867`) and the trailing ladder reaches
   `SetTrailing` (`SSR_Panel.mqh:2698` → `:811-826`), and nothing else. **In the shipped UI a human
   cannot widen a stop at all.** Position levels are drawn non-selectable
   (`SSR_TradeLines.mqh:543`, `:559`, `:579`); only the pre-trade planning lines are draggable
   (`:112`).
2. Therefore, on v125 as shipped, `sl_widened` can only be non-zero for a strategy-driven account —
   and the metric's real job today is to make the **break-even and trailing** decisions countable,
   which they currently are not.

[RECOMMENDATION] Record the fields anyway, and ship the measure. The moment a draggable position
stop exists — which is the obvious next chart feature — the measure is already there, already
persisted, and already in the statement. Recording a field costs one `SSRPackAdd` line; adding it
retroactively costs a session-file migration.

#### R.4.7 Moving the target

| | |
|---|---|
| **Counted** | `tp_moves`, and separately the count of trades where the target was moved **closer** to the entry (`\|tp_initial - open_price\| > \|tp - open_price\|`) — cutting a winner short |
| **Threshold** | none; counts only |
| **Data** | the target as placed, the target now |
| **Journal today** | **no.** `tp` is not a CSV column and no original is kept |
| **Needs** | fields 3 and 6 — `tp_initial`, `tp_moves` |
| **Lands in** | `Modify()` only. Nothing else writes `tp` after `Open()` |
| **Never says** | "you took profit too early out of fear". It says *"1 target was moved closer to the entry after the trade was open"* |

[INFERENCE] The same caller gap applies: with no UI path to `Modify`, `tp_moves` is zero for every
human session on v125. The honest presentation is therefore **absent, not zero** (R.1.3) — a row
reading `targets moved 0` teaches a trainee that the product watched for something it cannot yet
see. Under the `SSRReviewObservations` gate this happens for free; the paged measure table must
apply the same rule, which is a change from its current *"Nothing is filtered out for being zero"*
(`SSR_Review.mqh:99-102`) and is argued at R.9.2.

#### R.4.8 Repeated loss patterns

Four things a trainee means by "the same mistake twice", all computable, none of them a diagnosis:

| Pattern | Counted | Data | Journal today | Needs |
|---|---|---|---|---|
| **consecutive losses** | `loss_streak` | exists (`SSR_Statistics.mqh:76`) | header `# loss_streak` (`SSR_Journal.mqh:202`) | nothing — but state the order it counts in (R.2.3) |
| **loss cluster** | the largest number of losses inside one rolling 60-replay-minute window | `close_msc` + net | `close_time`, `profit`, `commission`, `swap` | `m_by_close[]`; new field `worst_loss_cluster` (int) |
| **same setup, repeated loss** | per-tag: losses, and the longest losing run within the tag | `tag`, net, close order | `tag` is column 3 | `CollectTags` already exists (`SSR_Journal.mqh:496-538`); new fields `worst_setup` (string), `worst_setup_net` (double), `worst_setup_losses` (int) |
| **same hour, repeated loss** | per-hour buckets, worst by net | `open_msc` hour, net | `open_time` | `ByHour` already exists (`SSR_Statistics.mqh:694`); new fields `worst_hour` (int), `worst_hour_net` (double) |

**Floor:** `losses >= 3` for every line above (R.1.3). Two losses in a row is a pair.

**Never says** "you keep making the same mistake". It says *"fades: 4 trades, 0 wins, -212.40"* —
which is the sentence `SSR_Journal.mqh:332-336` already argues for: *"a 44% win rate across a
session says nothing a trader can act on, while 'breakouts 61%, fades 22%' says stop trading
fades."*

#### R.4.9 Risk consistency — and the artefact that currently corrupts it

| | |
|---|---|
| **Counted today** | `risk_spread_pct` = population coefficient of variation of `risk_at_entry`, over `risk_samples` trades (`SSR_Statistics.mqh:585-593`) |
| **Data** | `risk_at_entry`, which is **money** (`SSR_TradingEngine.mqh:749-751` → `SSR_RiskEngine.mqh:79-85`) |
| **Journal today** | derivable from `r` and the profit columns, but not exported as such |
| **Needs** | field 1 `risk_pct_at_entry`, and one new struct field `risk_spread_pct_of_equity` |
| **Lands in** | `ComputeFor`, `:585-593` — the same variance block, run a second time over the percentage series |
| **Never says** | "you are inconsistent". It says *"risk varied 18 % across 11 trades (measured as a percentage of the account at each entry)"* |

> **[INFERENCE — a measurement artefact, stated as such because it cannot be confirmed without a
> run.]** `risk_at_entry` is money, and `LotForRisk` sizes from `Equity()` (`OpenWithRisk`,
> `SSR_TradingEngine.mqh:759-772`). A trader who never changes the risk slider, on an account that
> grows 20 % over a session, therefore produces a **rising** series of money risks and a non-zero
> `risk_spread_pct` — the measure reports variation that is in fact perfect consistency. The
> converse is worse: a trader who **reduces** the percentage after a drawdown, which is the
> behaviour a coach wants, can show a *lower* money spread than one who did nothing. The fix is not
> to replace the existing measure — money risk dispersion is a real thing — but to report **both**,
> label each, and put the percentage one on the curated page. Left uncorrected, this is the one
> behavioural number in the product most likely to be quoted at a student who did nothing wrong.

#### R.4.10 Session, time-of-day and setup performance

**[CONFIRMED FROM CODE] There is no London/New York in this product, and there must not be.**
`CSSRSessionWatcher` refuses exactly this: *"Writing `if(hour == 0)` here would be the third
anti-pattern on the list: broker logic baked into the tool. It would also be wrong on any
instrument whose day does not begin at midnight server time"*
(`SSR_SessionWatcher.mqh:7-11`). A named-session breakdown would be that anti-pattern with a
coaching label on it.

What the word "session" means here, and what each one can report:

| Meaning | Where it lives | What it can say | New? |
|---|---|---|---|
| **the replay window** — one sitting | `SessionKey()` = `symbol\|start\|end\|seed` (`SSR_Journal.mqh:125-129`) | everything in this section, for one run. Cross-run comparison is `CSSRClassReport`, which *"refuses to rank people who ran different sessions"* (`SSR_ClassReport.mqh:19-23`) | no |
| **a market day** | `CSSRSessionWatcher`, by gap or by day (`:30-34`) | per-day results, once the watcher's boundaries reach the statistics engine | [FUTURE FEATURE] — the watcher is a pause source, not an observer the stats engine reads |
| **hour of the day, server time** | `CSSRStatsEngine::ByHour` (`SSR_Statistics.mqh:694`) | the honest time-of-day answer, and the file already argues for it: *"'I lose money on Monday mornings' is a decision a person can change"* (`:660-670`) | **the table exists; no screen shows it** |
| **setup** | `CollectTags` (`SSR_Journal.mqh:496`) + `ComputeFor(tag, …)` | per-setup trades / win rate / PF / expectancy / R / net — already built, HTML only | **exists; no screen shows it** |

[CONFIRMED FROM CODE] `ByWeekday`, `ByHour` and the per-tag `ComputeFor` reach **only** the exported
HTML (`SSR_Journal.mqh:916`, `:968`, `:356`) and the smoke test
(`SSR_QA_Smoke.mq5:1451-1452`, `:1514-1515`). N.5.1 records the consequence and defers it:
*"Session Analysis has no data behind it… [FUTURE FEATURE] a real Session Analysis needs hour
buckets in `CSSRStatsEngine::Compute` first."* **This is that change, and it is small.**

[RECOMMENDATION] Do **not** widen `SSRReviewRows`'s signature to take bucket arrays. Fold six
summary numbers into `SSRStatistics`, computed by the engine from its own buckets, and leave the
full tables in the HTML statement where there is room for them:

```
   int      best_hour, worst_hour;        // -1 when fewer than 2 hours were traded
   double   best_hour_net, worst_hour_net;
   string   best_setup, worst_setup;      // "" when fewer than 2 tags
   double   best_setup_net, worst_setup_net;
   int      setups_traded, hours_traded;
```

One generator, one struct, two consumers (R.9). `SSRReviewRows` gains six rows and its signature is
untouched.

---

### R.5 `CSSRStatsEngine`, expanded

#### R.5.1 The new struct block

[RECOMMENDATION] Add one block to `SSRStatistics`, immediately after `DISCIPLINE`
(`SSR_Statistics.mqh:87-100`), written with the same comment discipline the file uses everywhere
else:

```
   //+------------------------------------------------------------------+
   //| BEHAVIOUR. Actions, counted. Not states of mind.                 |
   //|                                                                  |
   //| Nothing here observes a person. Every number below is a count of |
   //| something the account DID, against a threshold that is either a  |
   //| named constant in this file or a figure the trader themselves    |
   //| declared. A measure that needed a guess about why is not here,   |
   //| and there is no place in this product where it could go.         |
   //+------------------------------------------------------------------+
   int      max_trades_per_hour;      // busiest rolling 60 replay minutes
   double   trades_per_hour;          // over the span first entry -> last exit
   long     revenge_first_msc;        // when the first one was opened
   int      risk_violations;          // risked more than the declared percentage
   int      risk_declared_samples;    // trades that declared a percentage at all
   double   median_risk_pct;
   int      oversized_trades;         // >= 2x the session median risk %
   double   risk_spread_pct_of_equity;
   int      late_entries;             // plan gap >= 0.5 R
   int      late_samples;             // trades that had a plan to be late against
   double   avg_plan_gap_r;
   double   avg_plan_wait_sec;
   int      stop_moved_trades;
   int      stop_widened_trades;
   double   stop_widened_money;       // risk added after entry
   int      target_cut_trades;
   int      worst_loss_cluster;       // most losses in one rolling hour
```

plus the six session/setup summary fields of R.4.10, and three identity fields for R.6:

```
   long     best_ticket,  worst_ticket;     // by net
   long     best_rule_ticket, worst_rule_ticket;  // by R, inside / outside the rules
```

`Init()` (`:115-131`) zeroes every one; `best_hour` / `worst_hour` initialise to `-1` and the two
setup strings to `""`, because zero is a valid hour and the absent case must be distinguishable.

#### R.5.2 The new generators

Two free functions, in the same file and the same style as `SSRReviewRows` — *"THIS FILE COMPUTES
NOTHING"* (`SSR_Review.mqh:15-22`) applies to both:

```
   int SSRTimeline   (const SSRTimelineRow &src[], const int n, SSRReviewRow &out[]);
   int SSRVerdictRows(const SSRStatistics &st, SSRReviewRow &out[]);
```

and one new value struct, produced by the engine because only the engine may walk the account:

```
   struct SSRTimelineRow
     {
      long     ticket;
      long     open_msc;
      bool     is_long;
      double   volume;
      double   r;          bool has_r;     // never 0.0 for "no stop"
      double   net;
      string   tag;
      int      marks;      // bitmask, R.7.3
     };

   int CSSRStatsEngine::Timeline(SSRTimelineRow &out[], const int max_rows);
```

`Timeline()` walks `m_by_open[]` (R.2), copies each struct **once**, fills the row, and sets the
mark bits from the same tests `ComputeFor` used — **not from a second set of rules.** [RECOMMENDATION]
Implement the mark tests as small private predicates on the engine (`IsRevenge(i)`,
`IsOversized(i, median)`, `IsLate(i)`) called by **both** `ComputeFor` and `Timeline`, so the count
on the summary row and the marks on the timeline cannot disagree. Two places that both decide what
a revenge trade is, is how the count and the list come to contradict each other in front of a
student.

#### R.5.3 Cost, and where it runs

| | |
|---|---|
| `BuildOrder` | one index pass, no struct copy; insertion sort over closed trades only |
| `ComputeFor` | one extra rolling-window sweep (overtrading, clusters) + one extra second-pass predicate (oversized median). The second pass **already exists** for `wide_spread_trades` (`:570-583`) and is reused, not duplicated |
| `Timeline` | one pass, `min(n, max_rows)` struct copies. Called on **opening the card**, never per frame |
| throttle | N.5.4 stands unchanged: one `SSRStatistics` cached in `CSSRGroupPort`, recomputed when `m_acct.ClosedCount()` changes (`SSR_GroupPort.mqh:241`) or every 2000 ms. `CSSRStatsEngine *m_stats` and `AttachStats()` already exist (`:49`, `:91`) |
| disclosure | the ≤ 2 s lag is drawn on the PERFORMANCE sheet (N.5.2). The **card** does not need it: the host computes fresh at the moment of opening (`SSReplayStandalone.mq5:976-977`) |

[INFERENCE] `Timeline` is capped at `max_rows` because the card pages 12 at a time and a 512-trade
session would otherwise copy 512 structs to draw twelve. [RECOMMENDATION] cap at **200** and print
`showing the last 200 of N` when it bites — the same honesty the position sheet's `posmore` counter
already practises.

---

### R.6 The Session Review — the twelve lines the brief asks for

One generator, `SSRVerdictRows()`, producing at most twelve `SSRReviewRow`s. It is the card's first
view and, curated, the PERFORMANCE destination's page 1.

| # | Line | Source | Exists today? | New work |
|---|---|---|---|---|
| 1 | **totals** — `12 trades · 8 won · 4 lost · 0 flat` | `trades`, `wins`, `losses`, `breakeven` | **yes**, `SSR_Statistics.mqh:46-49` | format only |
| 2 | **net P/L** — `+412.80` | `net_profit` (`:54`) | **yes** | format only |
| 3 | **average R** — `+0.31 R (11 of 12)` | `average_r`, `r_trades` (`:67-70`) | **yes** | **must print the sample** — `:532-536` computes it only over `HasR()` trades |
| 4 | **max DD** — `-186.40 (3.1 %)` | `max_drawdown`, `max_drawdown_pct` (`:74-75`) | **yes** | carry `trading-analytics-9`'s caveat when the equity ring wrapped (R.10) |
| 5 | **win rate** — `58.3 %` | `win_rate` (`:59`) | **yes** | format only |
| 6 | **risk consistency** — `varied 18 % of equity, over 11 trades` | `risk_spread_pct_of_equity`, `risk_samples` | **partly** — the money version exists (`:98-99`) | field 1 + R.4.9 |
| 7 | **revenge trades** — `2, first at 10:15` | `revenge_trades`, `revenge_first_msc` | **yes, but wrong** (`trading-analytics-7`) | R.2 + R.4.2 |
| 8 | **best trade** — `#4 SELL +2.4 R (+218.60) at 11:42` | `best_ticket` + the timeline row | **no** — only `largest_win`, a magnitude with no identity (`:64`) | `best_ticket`; the rest from `Timeline()` |
| 9 | **worst trade** — `#7 BUY -1.0 R (-70.00) at 13:05` | `worst_ticket` | **no** — only `largest_loss` (`:65`) | `worst_ticket` |
| 10 | **largest measured deviation** | R.6.3 | **no** | R.6.3 |
| 11 | **best decision** | R.6.2 | **no** | R.6.2 |
| 12 | **worst decision** | R.6.2 | **no** | R.6.2 |

#### R.6.1 Best trade is not best decision, and the review must say four things, not two

[RECOMMENDATION] The distinction is the whole pedagogical value of the screen and must survive into
the string catalogue:

* **best / worst trade** = pure outcome. The largest win and the largest loss, by net. A trade can
  be the best of the session and still have broken every rule the trader set.
* **best / worst decision** = outcome **inside** or **outside** the trader's own declared
  constraints. This is the only place the product is allowed to use the word "decision", and only
  because the constraint being tested is one the *user* declared, not one this program invented.

#### R.6.2 How a "decision" is ranked, without inventing a score

**The rule test.** A closed trade **broke a declared rule** when any of the following is true —
each one a field comparison, each one checkable against the trade list:

| Test | Field | The rule, and whose it is |
|---|---|---|
| no stop | `risk_at_entry <= 0.0` | the product's own, stated at `SSR_Statistics.mqh:15-20`: R is undefined without one |
| risked more than declared | `risk_pct_at_entry > risk_pct_declared + step_tolerance` | the trader's, set on the TRADE sheet |
| stop widened after entry | `sl_widened > 0` | the trader's, implied by having placed a stop |
| opened within the revenge window | the R.4.2 predicate | the product's named constant, `:40` |
| sized at ≥ 2× the session median | `risk_pct_at_entry >= 2 × median_risk_pct` | the session's own, `:562-568` |

Then:

```
   best decision  = the highest R among trades that broke NO test
   worst decision = the lowest  R among trades that broke AT LEAST ONE test
```

and the drawn line **names the test**, never a verdict:

```
   best inside your rules     #4  SELL  +2.4 R   11:42
   worst outside them         #7  BUY   -1.0 R   13:05   no stop
```

[RECOMMENDATION] **Refused: a weighted mistake score.** Assigning "no stop = 3 points, revenge = 2"
produces a number that ranks incomparable things, that nobody can verify, and that would become the
headline of the screen. R is the only common unit in this product that the engine already computes,
and it is the one used here. Where R is undefined — a trade with no stop, by construction — the
trade is **eligible for worst decision and ineligible for best**, ranked by **net money** among the
R-less, and the row says `no R` rather than printing a zero. That is the same rule `CSSRJournal`
already applies to its `r` column: *"R is left EMPTY, never zero, when it does not exist: a zero
would be averaged in by whatever reads this next"* (`SSR_Journal.mqh:79-81`).

**Both lines are absent when their set is empty** (R.1.3). A session in which every trade broke a
rule has no best decision, and saying so by omission is more honest than promoting the least bad
one.

#### R.6.3 The largest measured deviation

The brief's "largest mistake", renamed to what it is.

```
   largest measured deviation:  #7  -180.20   no stop, and 2.4 % risked against 1.0 % set
```

**Definition:** among trades that broke at least one test, the one with the **largest loss in
money**. The line then prints every test that trade broke, in the order of the table above,
`Clip`ped to the row budget.

[RECOMMENDATION] Money, not R, for this one line — because a trade with no stop has no R, and the
whole point of the line is that no-stop trades are eligible for it. Money is the unit every trade
has. The line is absent when no trade broke a test, and absent when no such trade lost.

#### R.6.4 Where the twelve lines are drawn

| Surface | What it shows | Why |
|---|---|---|
| review card, view 1 | all twelve, `ListRO`, one screen | 520 px wide, no paging needed for 12 rows of 17 px |
| PERFORMANCE page 1 | **six** of them — the curated Result + Discipline block specified at N.5.2 — unchanged in shape | 186 px, and N.5.2 already spends 185 of it |
| HTML statement | all twelve, in the existing caveat/KPI region | it is the document a student hands in |
| CSV header | the seven behaviour keys of R.3.3 | it is what the class report reads |

---

### R.7 The chronological timeline

#### R.7.1 What it is

The brief's line — `09:32 BUY +1.8R / 10:11 SELL -1R / 10:15 SELL -1R - Revenge / 11:42 BUY +2.4R`
— is the single most valuable screen in this section, because it is the only one from which a
trainee can **check every other number on the card**. It is also the one surface where the
chronological order of R.2 is visible, which is why it cannot ship before it.

#### R.7.2 The row, to the character

Ground truth: MetaTrader draws exactly 63 characters of `OBJPROP_TEXT`; the card prepends a
two-character group marker, so the budget is `SSR_REVIEW_ROW_MAX 60`
(`SSR_Review.mqh:57-58`, and the reasoning at `:44-56`). The timeline reuses that constant rather
than declaring a second one.

```
   col  0   time       5    "09:32"        server time, HH:MM
   col  7   side       4    "BUY " "SELL"
   col 11   volume     5    " 0.42"
   col 17   R          7    "  +1.8R"  "   -1.0R"  "     --"
   col 25   net        9    "  +126.40"
   col 35   tag       12    Clip(tag, 12)
   col 47   marks     12    at most two tokens, then "+n"
   ------------------------------------------------------------
                      59    of 60
```

Rendered:

```
   09:32  BUY   0.42   +1.8R    +126.40  breakout
   10:11  SELL  0.42   -1.0R     -70.00  fade
   10:15  SELL  0.42   -1.0R     -70.00  fade         REV
   11:42  BUY   0.84   +2.4R    +218.60  breakout     BIG
```

**Rules the row obeys, each already the product's:**

* **`--`, never `0.00`, when R is undefined.** `SSR_Journal.mqh:79-81`, and the same reasoning that
  keeps `profit_factor` at zero rather than infinite (`SSR_Statistics.mqh:526-530`).
* **Digits line up because Tahoma advances all ten identically** — the reason `SSRReviewLine` can
  pad with spaces (`SSR_Review.mqh:82-84`). The columns above are space-padded for the same reason
  and for no other.
* **The tag is `Clip`ped at the draw site**, under M's rule R5. A setup name is user text and has
  no length contract.

#### R.7.3 Marks, and why they are words rather than colours

[CONFIRMED FROM CODE] The product's rule is written at `SSR_Panel.mqh:858-862`: *"Modes are CHIPS -
text on a tinted plate - because a mode carried by colour alone is a mode a colour-blind trader
cannot read."* A timeline whose revenge trades were merely red would be that failure on the one
screen a coach screenshots.

| Bit | Token | Means | Predicate |
|---|---|---|---|
| `0x01` | `REV` | opened within 2 min of a loss | R.4.2 |
| `0x02` | `NS` | no stop — R undefined | `risk_at_entry <= 0` |
| `0x04` | `BIG` | ≥ 2× the session median risk % | R.4.4 |
| `0x08` | `OVER` | risked more than the declared % | R.4.3 |
| `0x10` | `LATE` | plan gap ≥ 0.5 R | R.4.5 |
| `0x20` | `SL+` | stop widened after entry | R.4.6 |
| `0x40` | `TP-` | target moved closer after entry | R.4.7 |
| `0x80` | `WIDE` | entered at ≥ 2× the session average spread | existing, `:576-582` |
| `0x100` | `?` | ambiguous bar — the outcome was assumed | existing, `:226` |

At most **two** tokens fit the 12-character column; they are emitted in the bit order above (the
order is deliberate: the ones that describe what the trader *did* come before the ones that
describe what the *data* could not resolve), and a third becomes `+1`.

**A legend row is mandatory**, drawn once under the list, because a three-letter token with no
expansion is a colour by another name:

```
   REV within 2 min of a loss   NS no stop   BIG 2x median risk   ? outcome assumed
```

[RECOMMENDATION] The legend prints **only the tokens in use** on the current page. A legend that
explains marks nobody has is four lines of noise on a card that is already 520 × 320+.

[CONFIRMED FROM CODE] Colour may be added **on top** of the token, never instead of it, and only
from the existing semantic four (`SSR_C_RUN`, `HOLD`, `STOP`, `IDLE`) — M.9 forbids new tokens, and
the palette has 51 already defined identically in all three palettes.

#### R.7.4 Paging

The card already has the right answer and it is not reinvented: `SSR_RV_SHOWN 12`, `m_first`,
explicit `up` / `down`, header comment *"PAGED, BECAUSE MQL5 CANNOT CLIP"*
(`SSR_ReviewCard.mqh:12-17`, `:32-34`, `Page()` at `:95-100`). The timeline reuses `m_first` and
`Page()` verbatim; only the row source changes with the view.

---

### R.8 `CSSRReviewCard`, expanded

#### R.8.1 Three views, one list

[RECOMMENDATION] The card gains `int m_view` — `0 REVIEW`, `1 TIMELINE`, `2 MEASURES` — and three
`ButtonC`s in the header band. Everything else about the card is preserved: it stays an overlay
under M.3.6 (*"a moment rather than a reference"*), it keeps its modal keyboard
(`OnKey` returning `true` for every key, `:224-241`), and it keeps its read-only test seams.

| Element | Change | Line today |
|---|---|---|
| `Show(chart_id, st)` | unchanged signature | `:78` |
| **new** `Timeline(const SSRTimelineRow &rows[], const int n)` | element-wise copy into `m_tl[]`; called by the host immediately before `Show` | — |
| `m_n = SSRReviewRows(m_st, m_rows)` | unchanged; 43 → 53 rows arrive for free | `:87` |
| **new** `m_vn = SSRVerdictRows(m_st, m_vrows)` | the twelve lines of R.6 | — |
| **new** `m_tn = SSRTimeline(m_tl, m_tl_n, m_trows)` | the formatted timeline rows | — |
| `m_obs_n = SSRReviewObservations(...)` | unchanged, but the sentences are re-cut (R.8.3) | `:88` |
| `Render()` headline `h1..h5` | unchanged — four numbers and the coloured net (`:121-143`) | `:127-143` |
| `m_w.List("m", …)` | **becomes `ListRO`** | `:162` |
| `Page()` | unchanged; bounds against the **current view's** row count | `:95-100` |
| `Poll()` | three new arms: `v0` / `v1` / `v2` set `m_view`, reset `m_first`, `Render()` | `:213-222` |
| `OnKey` | `SSR_VK_LEFT` / `RIGHT` cycle the view; everything still returns `true` | `:233-241` |
| `Hide()` | `ListClear` for the RO list, then `RemoveAll()` | `:243-252` |
| **new** `TimelineAt(i)` | the same read-only seam as `RowAt` / `ObservationAt` (`:63-76`) — *"the smoke test cannot read a chart label, but it can ask what the card believes it is showing"* | — |

**Host change, two lines, in one function.** [CONFIRMED FROM CODE] `OpenReview()`
(`SSReplayStandalone.mq5:970-978`) is the single entry point, and the file says why:
*"ONE PLACE OPENS THE REVIEW… if each built its own the three would eventually disagree about what
a review shows"* (`:955-962`). It becomes:

```
   SSRStatistics st;   g_stats.Compute(st);
   SSRTimelineRow tl[]; int n = g_stats.Timeline(tl, 200);
   g_review.Timeline(tl, n);
   g_review.Show(g_panel_chart, st);
```

All three callers — `A` (`SSR_Keys.mqh:206-208`), the finished evaluation
(`SSReplayStandalone.mq5:3031`), and the palette's `"Session review"` entry
(`SSR_Command.mqh:101`) — are unchanged.

[INFERENCE] The copy into `m_tl[]` is an element-wise loop, not `ArrayCopy`: `SSRTimelineRow`
carries a `string tag`, and the card's existing row plumbing already assigns per element for the
same reason (`SSRAddRow`, `SSR_Review.mqh:71-80`).

#### R.8.2 `ListRO`, and the false affordance it retires

[CONFIRMED FROM CODE] `CSSRWidgets::List` draws `Button` / `ButtonC` rows
(`SSR_Widgets.mqh:565-589`). `ui-dialogs-16` (CONFIRMED, IMPROVEMENT) is the consequence on this
exact card: *"the 12 measure rows are `OBJ_BUTTON`s whose latch nothing consumes, so a clicked
statistic stays drawn pressed"* — on a card *"whose whole purpose is to be read"*.

M.3.5 and N.5.3 specify `ListRO`: one `Rect` well plus a cached `Label` per row, same
`first` / `shown` / `Remove`-the-tail contract, **6 writes a row instead of 9**. Section R is the
second consumer and adds no new requirement — but it is the consumer that closes the finding,
because the review card is where the finding was found.

| | `List`, 12 rows | `ListRO`, 12 rows |
|---|---|---|
| cold | 9 + 12×9 = **117** | 9 + 12×6 = **81** |
| warm | 13 finds | 13 finds |
| latch left set | **yes** (`ui-dialogs-16`) | none to set |

#### R.8.3 The observations, re-cut

[CONFIRMED FROM CODE] `ui-dialogs-4` (CONFIRMED, MEDIUM) — two of the six observation sentences
exceed 63 characters **for every possible value**, and the worse one loses the product's most
important caveat:

```
   SSR_Review.mqh:210-213
      "%d trade(s) closed on a bar that reached both the stop and the target."
                                    -> drawn as "...reached both the stop and the t"
```

[RECOMMENDATION] Three changes, and they belong in this section because this section adds four more
sentences to the same array:

1. **Shorten at source.** `"%d trade(s) hit stop and target in one bar - outcome assumed."` = 59
   at `%d = 1`, and it keeps the word `assumed`, which is the one that matters.
   `"%d of %d entered at over twice the session's average spread."` = 57.
2. **Clip at the draw site anyway.** `m_w.Label(oid, …, m_obs[i], …)` (`SSR_ReviewCard.mqh:190-191`) becomes
   `Clip(m_obs[i], 60)`. A sentence that is correct today and 64 characters after translation is a
   defect nobody will notice until a Persian user reports it.
3. **Cap the array.** `ArrayResize(out, 8)` (`:182`) with six emitters today and four proposed is
   an overflow waiting for the eleventh sentence. Make it 16, and make `Render`'s twin loops
   `for(int i = 0; i < 8; i++)` (`SSR_ReviewCard.mqh:185`, `:198`) iterate the same named constant.

**The four new observations**, each gated per R.1.3:

```
   %d of %d trades risked more than the %.1f%% set at the time.
   Busiest hour held %d entries; the session averaged %.1f.
   %d of %d planned entries were taken %.1f R after the plan.
   %s: %d trades, %d won, %.2f.                      <- worst setup, >= 2 setups
```

[CONFIRMED FROM CODE] All four are English literals inside `SSR_Review.mqh`, **outside `T()`** —
which is `ui-plumbing-1`'s class of defect and is called out at L.8 as *"anything generated at
runtime, and anything drawn outside `/Ui/`, escaped the discipline"*. `SSR_Review.mqh` **is** under
`/Ui/`, so audit A19's literal check should already see them; that it does not is worth a line in
A19's own review. [RECOMMENDATION] route all ten observations through `T()` in the same change:
10 catalogue ids + 10 `fa.txt` rows, catalogue 190 → 200 (`SSRAddString` count today: **190**,
`SSR_Strings.mqh`).

#### R.8.4 The card's height, re-derived

[CONFIRMED FROM CODE] `SSR_ReviewCard.mqh:107-108`:

```
      int obs_h = (m_obs_n > 0 ? 18 + m_obs_n * 14 : 0);
      int h     = 26 + 46 + SSR_RV_SHOWN * SSR_RV_ROW_H + 10 + obs_h + 34;
```

With `SSR_RV_SHOWN 12` and `SSR_RV_ROW_H 17`, the fixed part is `26+46+204+10+34 = 320`, plus
`18 + 14n` of observations. At ten observations that is `320 + 158 = 478` px.

| Change | Height cost |
|---|---|
| three view buttons in the header band | **0** — the band is 46 px and holds five labels at `hy+4` (`:127-143`); the buttons sit at `m_y + 30`, right-aligned, in the 260 px the headline does not use |
| the timeline legend row | **+16**, and **only in view 1** |
| four more observations | up to **+56**, in view 0 and 2 |

> [POTENTIAL_RISK] `Render` already centres with `m_y = (ch > h + 40 ? (ch - h) / 2 : 8)`
> (`:113`) — a card taller than the chart is pinned to `y = 8` and **overflows the bottom** rather
> than being refused, and MQL5 will not clip it. At ten observations the card is 494 px and any
> chart under ~534 px shows a truncated card. [RECOMMENDATION] this is the same failure
> `ui-dialogs-14` records for `CSSRFirstRun` — *"Show() reports success without checking its fixed
> position fits the chart"*. The fix is the one N.5 uses everywhere: when `h` exceeds the chart,
> **reduce `SSR_RV_SHOWN` for that render** rather than draw off the bottom, and say so in the
> pager count. It is four lines and it must land with the observation expansion, not after it.

---

### R.9 Where this lands on the panel

#### R.9.1 PERFORMANCE (N.5) absorbs the measures; the card keeps the timeline

| | PERFORMANCE destination | review card |
|---|---|---|
| curated verdict | six of R.6's twelve, N.5.2's layout unchanged | all twelve, view 0 |
| the 53 measures | pages 2-n via `ListRO`, 8 per page Standard / 17 Expanded | view 2, 12 per page |
| the timeline | **no** | **view 1** |
| observations | no | yes, foot of views 0 and 2 |
| `stmt` | footer button, existing arm (`SSR_Panel.mqh:1702`, dispatch `:2611-2620`) | footer button, existing (`SSR_ReviewCard.mqh:202`) |

**Why the timeline is not a destination.** [CONFIRMED FROM CODE] the sheet is
`310 - 16 - 44 - 5 = 245` px wide and a row from `x+8` has **237 px** (M.1.3), which at
`SSR_FS_BODY` ≈ 5.1 px/char is **~46 characters** — not 60. The timeline row specified at R.7.2 is
59 characters and would lose its marks column, which is the column that makes it a coaching screen
rather than a list of fills. It fits the card's 496 px and it does not fit the sheet, and building
a truncated second version for the panel would be the second list that drifts.

[RECOMMENDATION] The panel's answer to *"what did I just do"* is already specified and is better
suited to 245 px: **POSITIONS → Closed** (M.4.2, N.4.3), newest first, with the `!` no-stop prefix
on the note column. The card's timeline is the *session*; the Closed page is the *last few trades*.
Two surfaces, two questions, one generator behind neither — the Closed page reads the wire, the
timeline reads the engine.

#### R.9.2 One rule the measure table must change

[CONFIRMED FROM CODE] `SSR_Review.mqh:99-102` states: *"Nothing is filtered out for being zero. A
measure that is zero because nothing happened is a fact about the session."* That is right for
`revenge_trades` and wrong for `target_cut_trades`, because — R.4.7 — **v125 has no UI path that
can move a target**, so the row is not reporting a clean session, it is reporting a feature that
does not exist.

[RECOMMENDATION] Narrow the rule rather than abandon it: a measure is drawn at zero when the action
it counts is **reachable**; a measure whose action has no reachable path is absent. Two rows
qualify today (`target_cut_trades`, `stop_widened_trades`) and both become reachable the day a
position stop is draggable. Encode it as one `bool` beside the row, not as a special case at the
draw site.

#### R.9.3 What each change touches

| Change | Class / function | File |
|---|---|---|
| chronological index | `CSSRStatsEngine::BuildOrder`, `m_by_open[]`, `m_by_close[]` | `SSR_Statistics.mqh` |
| closed-drawdown fix | `CSSRStatsEngine::ClosedDrawdownFor` (`:695-716`) | `SSR_Statistics.mqh` |
| revenge fix | `CSSRStatsEngine::ComputeFor` (`:489-512`) | `SSR_Statistics.mqh` |
| behaviour block | `SSRStatistics` (after `:100`), `Init()` (`:115-131`) | `SSR_Statistics.mqh` |
| overtrading, clusters, oversized, late, stop/target moves | `CSSRStatsEngine::ComputeFor`, predicates shared with `Timeline` | `SSR_Statistics.mqh` |
| hour / setup summaries | `CSSRStatsEngine::ByHour` (`:694`), `ComputeFor`, new summary fields | `SSR_Statistics.mqh` |
| timeline producer | `CSSRStatsEngine::Timeline`, `SSRTimelineRow` | `SSR_Statistics.mqh` |
| timeline formatter | `SSRTimeline()` | `SSR_Review.mqh` |
| verdict formatter | `SSRVerdictRows()` | `SSR_Review.mqh` |
| 43 → 53 rows | `SSRReviewRows()` (`:104-165`) | `SSR_Review.mqh` |
| observations re-cut + `T()` | `SSRReviewObservations()` (`:179-221`) | `SSR_Review.mqh` |
| three views, `ListRO`, legend, seam | `CSSRReviewCard::Show/Render/Poll/OnKey/Hide`, new `Timeline()`, `TimelineAt()` | `SSR_ReviewCard.mqh` |
| `ListRO` primitive | `CSSRWidgets::ListRO` (M.3.5, N.5.3) | `SSR_Widgets.mqh` |
| nine new position fields | `SSRVirtualPosition` (`:178-291`), `Init()` (`:249-264`) | `SSR_TradeTypes.mqh` |
| recording | `CSSRTradingEngine::Open` (`:705-757`), `CheckPendings` (`:326-360`), `Modify` (`:844`), `BreakEven` (`:920`), `SetTrailing` (`:855`) | `SSR_TradingEngine.mqh` |
| persistence | `CSSRTradingEngine::SaveInto` (`:1067-1108`) / `RestoreFrom` (`:1140+`) | `SSR_TradingEngine.mqh` |
| plan stamp | `CSSRGroupPort`, beside `ToggleEntryLine` (`:687-713`) and `OpenFromLines` (`:715-756`) | `SSR_GroupPort.mqh` |
| risk % at entry | `CSSRRiskEngine::RiskPercentOf` (`:137-143`) — **its first production caller** | `SSR_RiskEngine.mqh` |
| CSV columns + header keys | `CSSRJournal::Row` (`:68-90`), `ExportCsv` (`:186-208`) | `SSR_Journal.mqh` |
| 10 new catalogue ids | `SSR_Strings.mqh` + `fa.txt` | both |

---

### R.10 What this must never claim, and what it does not fix

**Never claims:**

* **No emotion, ever** (R.1.1). Not tilt, not fear, not greed, not confidence. There is no input by
  which this product could observe a person, and every word in the UI must be a label over a count.
* **No advice.** The product reports; the coach teaches. `SSR_Review.mqh:24-31` is the contract and
  this section does not amend it.
* **No invented thresholds.** Every threshold is either a named constant in the source with its
  reasoning beside it, or a number the trader declared.
* **No score.** No mistake score, no discipline grade, no percentile. Ranking incomparable things
  with weights produces a headline nobody can check.
* **No cross-session ranking without a matching session key.** `CSSRClassReport` already refuses
  this (`:19-23`) and nothing here weakens it.

**Does not fix, and says so:**

* **`trading-analytics-10` (CONFIRMED, LOW)** — `RMultiple()` is `(profit + swap) / risk_at_entry`
  (`SSR_TradeTypes.mqh:269-270`), **commission excluded**, while every money measure includes it.
  The timeline row (R.7.2) prints R and net **side by side**, which is where the contradiction
  becomes visible: a scalping session can show `+0.06R` beside `-7.00`. [RECOMMENDATION] fix it at
  source — one term in one expression — or the timeline is the screen that finally embarrasses it.
  `verified.json` adds that `SSRBucket`'s own R block (`SSR_Statistics.mqh:255-259`) carries the same split, so
  the hour summaries of R.4.10 inherit it.
* **`trading-analytics-9` (CONFIRMED, LOW)** — the equity ring drops its oldest half
  (`:268-284`), so `max_drawdown` can **shrink** as a long session runs. Line 4 of the session
  review prints that number. [RECOMMENDATION] the engine knows when it wrapped; expose one `bool
  equity_truncated` and let the review line carry `(earliest samples dropped)` rather than a
  silently smaller number.
* **`trading-analytics-6` (CONFIRMED, LOW)** — profit factor prints `0.00` when undefined on four
  surfaces. N.5.2 already rules that the PERFORMANCE page draws `-`; the **card** must do the same,
  and `SSRReviewRows:121` is currently a bare `%.2f`. One line, same change.
* **`trading-analytics-8` (CONFIRMED, LOW)** — `avg_mae` / `avg_mfe` are price units printed at two
  decimals, which is `-0.00` on a 5-digit FX pair. `verified.json` names `SSR_Review.mqh:142` as a
  third printer. The measures page shows them; this section does not fix the unit, and the row
  should print points (`value / point`) with the unit named.
* **`trading-analytics-5` (CONFIRMED, LOW)** — a day on which only a pending order was placed
  counts as a trading day. The behaviour measures count **closed trades**, so they do not inherit
  it; the EVAL destination does, and it is not this section's to fix.
* **`ui-port-session-3` (CONFIRMED, HIGH)** — a restored session can install a saved account over a
  chart that never rewound. Every behaviour number is computed from that account. [POTENTIAL_RISK]
  a resumed session's timeline can therefore show trades at instants the replay is not at, and
  nothing on the card says so. This section adds no protection and must not be read as adding one.
* **Nothing here has run on MT5.** Every character budget in R.7.2 is arithmetic over
  `SSR_REVIEW_ROW_MAX 60` and the ground truth that MetaTrader draws 63; every px/char figure is an
  estimate MQL5 will not confirm (invariant I10, `SSR_Widgets.mqh:124-127`); and the card's
  overflow at ten observations (R.8.4) is derived from a formula, not observed. The Persian
  rendering of a mixed-direction timeline row — Latin digits and a Persian tag in one string, in a
  renderer with no bidi — is a **POTENTIAL_RISK no amount of source reading can close**, and it is
  the same risk L.3.3 records for the rail's Persian names.

---

### R.11 Cost ledger and build order

#### R.11.1 Per change

| # | Change | ~lines | Risk | Fixes | Cost if wrong |
|---|---|---|---|---|---|
| 1 | `BuildOrder()` + `ClosedDrawdownFor` and revenge onto it | 70 | **medium** — it changes two shipped numbers | `trading-analytics-3`, `trading-analytics-7` | a drawdown or a revenge count that disagrees with the previous build, with no release note saying why |
| 2 | Nine position fields + `Init()` + `SaveInto`/`RestoreFrom` tail | 60 | low | — | a session file that predates them restores as zero, which is the designed behaviour (`:1073-1077`) |
| 3 | Recording in `Open` / `Modify` / `BreakEven` / `SetTrailing`; `RiskPercentOf`'s first caller | 40 | low | — | a field recorded but never read, which is the cheapest possible failure |
| 4 | `plan_msc` / `plan_price` stamp in `CSSRGroupPort` | 30 | medium | — | late-entry numbers computed against the wrong instant. Gate on `plan_msc > 0` and count `late_samples` separately |
| 5 | `SSRStatistics` behaviour block + the counting in `ComputeFor` | 140 | medium | the whole of R.4 | a measure that is wrong in a way only a terminal shows |
| 6 | Hour / setup summaries into the struct | 40 | low | N.5.1's *"Session Analysis has no data behind it"* | — |
| 7 | `SSRTimelineRow` + `CSSRStatsEngine::Timeline` + shared predicates | 90 | low | — | the count and the marks disagree, which is why the predicates are shared |
| 8 | `SSRTimeline()` + `SSRVerdictRows()` + 43 → 53 rows | 120 | low | — | a row over 60 characters, cut with `~` |
| 9 | Observations: shorten, `Clip`, cap, `T()`, four new | 60 + 10 strings | low | `ui-dialogs-4` | a sentence that is 64 characters after translation |
| 10 | `CSSRReviewCard`: three views, `ListRO`, legend, `TimelineAt` | 130 | medium | `ui-dialogs-16` | a view switch that leaves the previous view's labels on the chart (invariant I7) |
| 11 | Card height guard (reduce `SSR_RV_SHOWN` rather than overflow) | 15 | low | the `ui-dialogs-14` failure mode, on this card | — |
| 12 | CSV columns + seven header keys | 30 | low | — | an old class report ignores them, by design |
| | **total** | **≈ +825, across 7 files, 0 classes deleted** | | | |

#### R.11.2 Build order, and the gates

1. **#1 alone, and released with a note.** It changes `max_drawdown_closed` and `revenge_trades` on
   existing sessions. Nothing else in this section may land before it, because everything else
   assumes time order.
2. **#2 + #3 + #4 together.** Recording without reading. Zero user-visible change, and the session
   file grows by six fields that a previous build tolerates.
3. **#5 + #6.** The measures appear in the exported statement first — the surface with the most
   room and the least layout risk — before any of them reaches a 63-character label.
4. **#7 + #8.** The generators. `SSRReviewRows` grows to 53 and the existing card pages it with no
   other change, which is a free integration test of the new fields.
5. **#9 + #10 + #11.** The card. `ListRO` (M.3.5) must exist first; it is shared with the KEYS
   destination and PERFORMANCE, and section R is not where it is written.
6. **#12.** The CSV last, once the header keys have stopped moving.

**Two gates outside this section.** Nothing here ships before them, for reasons that are already
recorded:

* **`ListRO` exists** (M.3.5, N.5.3). Drawing 53 measures and a 200-row timeline through `List`
  would multiply `ui-dialogs-16` rather than retire it.
* **`host-expert-7` (CONFIRMED, MEDIUM)** — keys are not withheld while a modal is open. The review
  card is the one surface that **already** does this correctly (`OnKey` returns `true` for every
  key, `:224-241`), so this section adds no exposure — but the three new view buttons are three new
  clickable controls on a modal, and M.2's rule R5 gates every one of them behind the fix.

**One measurement gate, and it is the honest one.** Every number in R.4 is a claim about what a
trainee did, drawn on a screen a coach will read aloud. [RECOMMENDATION] before any behaviour row
reaches the card, run one session on a terminal and check each count against the exported CSV by
hand. That is what `R.1.2`'s third clause is for: a metric whose sample a person can re-derive from
the trade list is a metric that survives being wrong once.

## B. CURRENT ARCHITECTURE ASSESSMENT

### B.0 Method, and the verdict in one page

Every claim below is tagged. `[CONFIRMED FROM CODE]` means the fact was read out of the v125
tree at the file and line cited, or measured from it mechanically. `[INFERENCE]` means the fact
is confirmed but the consequence drawn from it is judgement. `[RECOMMENDATION]` is a proposal,
not an observation. `[FUTURE FEATURE]` is work that does not exist. Findings are cited by their
`verified.json` id; the 30 `POTENTIAL_RISK` ids are always labelled as such, and the 21
`NOT_A_BUG` ids are never presented as defects anywhere in this section.

**The verdict.** The layering of this product is the strongest thing about it and the single
biggest reason it can be repaired rather than rewritten. Twelve include directories, 84 headers
and 31,439 lines of library code (measured) sit under one 3,255-line Expert, and the
include-direction matrix is almost exactly the dependency order the headers claim it is: one
true cycle (`Ui ↔ Chart`), one benign upward edge (`Trading → Report`), and nothing else out of
place. **[CONFIRMED FROM CODE]** Time is `long` epoch milliseconds in every layer; there is no
`OrderSend`, `CTrade` or `PositionClose` anywhere in the tree; no layer below `Ui` draws a chart
object; no layer below `Mt5` touches a custom symbol. Those four disciplines were held for 125
builds and they are what make the 227 non-refuted findings *local* — almost every one of them is
a defect inside a class rather than a defect between classes.

What is fragile is not the map but three seams that carry more than they were designed to:
the **two-pass window handover** in the host, the **bulk-write path** that reaches the custom
symbol without passing the observers, and the **rewind contract** between the controller and the
trading engine. All three are where the two `CRITICAL` and five of the fourteen `HIGH` findings
live. **[CONFIRMED FROM CODE]**

What is over-coupled is `CSSRGroupPort` (1,110 lines, eleven non-owned collaborators drawn from
seven layers) and the host itself (35 top-level global objects, 61 inputs, zero classes, an
815-line `BuildSession`). **[CONFIRMED FROM CODE]**

What is missing is a verification layer that can be believed. 71 of the 227 non-refuted
findings — 31% — are in `Scripts/`, `Services/`, `Indicators/` and `tools/`, and none of them is
`CRITICAL` or `HIGH`, because none of them can hurt a user. **[CONFIRMED FROM CODE]** They hurt
something else: at least 20 of the 71 are assertions that cannot fail, verdicts that are printed
rather than asserted, or gates that are tautologies. **[CONFIRMED FROM CODE]** On a product
whose author has never run it on a MetaTrader terminal, that is the finding that reframes all
the others.

---

### B.1 The layer map as actually built

Measured, not recalled. File counts and line counts are `find`+`wc` over the v125 tree; the
edge counts are every `#include "..."` resolved to its owning directory. **[CONFIRMED FROM CODE]**

| Layer | Files | Lines | Depends on (edge count) |
|---|---:|---:|---|
| `Common` | 10 | 1,673 | — (only itself) |
| `Core` | 19 | 5,051 | Common 34 |
| `Data` | 9 | 2,352 | Common 20, Core 5 |
| `Mt5` | 3 | 1,461 | Common 9, Core 1 |
| `Chart` | 6 | 1,881 | Common 11, Data 1, **Ui 2** |
| `Trading` | 8 | 4,774 | Common 17, Core 5, **Report 1** |
| `Strategy` | 4 | 1,158 | Common 7, Core 2, Trading 3 |
| `Integration` | 3 | 896 | Common 2, Core 1, Trading 1 |
| `Report` | 2 | 825 | Common 2 |
| `Session` | 1 | 415 | Common 4, Core 1, Trading 2, Chart 1 |
| `Ui` | 18 | 10,312 | Common 16, Core 1, Data 2, Mt5 1, Chart 4, Trading 5, Strategy 1, Session 1 |
| `Spike` | 1 | 641 | Common 1 (not product code) |
| **Expert host** | 1 | 3,255 | all of the above |

Two observations follow immediately.

1. **The direction is right.** `Common` depends on nothing. `Core` depends only on `Common` —
   the replay engine has no knowledge of MetaTrader's history API, of custom symbols, of charts,
   of the panel, or of trading. The three provider contracts it consumes are declared in
   `Core/SSR_IDataSource.mqh` and implemented in `Data`; the sink contract is declared in
   `Core/SSR_IReplaySink.mqh` and implemented in `Mt5`. **[CONFIRMED FROM CODE]** That is textbook
   dependency inversion, executed in a language with no interfaces, no namespaces and no package
   system, and it held for 125 builds.
2. **`Ui` is 10,312 lines — a third of the library — and reaches into eight other layers.**
   **[CONFIRMED FROM CODE]** That is the shape of the coupling problem, and §B.8 and §B.14 deal
   with it.

The one genuine cycle is `Ui ↔ Chart`: `Chart/SSR_TradeLines.mqh:34` and
`Chart/SSR_CalendarLines.mqh:27-28` include `Ui/SSR_Theme.mqh`, while `Ui/SSR_GroupPort.mqh:27-29`
includes `Chart/SSR_ChartManager.mqh`, `SSR_TradeLines.mqh` and `SSR_BlindMode.mqh`.
**[CONFIRMED FROM CODE]** It compiles because `SSR_Theme.mqh` is a leaf that includes only
`Common/SSR_Types.mqh`, so no file-level cycle exists — but at the layer level the cycle is real,
and it exists for one honest reason: colour is one system and a stop-loss line on the candles must
be the same red as the stop-loss row on the panel. **[INFERENCE]**

---

### B.2 `Core` — the replay engine

**What it is.** 19 files, 5,051 lines. One clock (`SSRReplayClock`), one window
(`SSRReplayTimeline`), one cursor (`SSRReplayCursor`), one published state (`SSRReplayState`),
a 1,876-line controller that owns ten sub-objects by value, and a group
(`CSSRReplayGroup`, `SSR_MasterClock.mqh`) that sits above up to four controllers and owns the
only clock that advances from wall time. **[CONFIRMED FROM CODE]**

**What is sound, and is the best engineering in the repository:**

- **One wall-clock-driven clock; streams are told an *instant*, never a delta.** The host always
  calls `g_group.Pump(delta)`; the group calls `m_master.Advance(delta)` once and then
  `ctrl.PumpTo(target)` on every member (`SSR_MasterClock.mqh:179-226`). `ctrl.Pump(wall_ms)`
  exists but no production path uses it. **[CONFIRMED FROM CODE]** This is why `MaxSkewMsc()` is
  zero by construction and multi-symbol replay cannot drift.
- **Integer speed arithmetic with a residue carry** — `scaled = wall*speed + residue;
  adv = scaled/100; residue = scaled%100` (`SSR_ReplayClock.mqh`). **[CONFIRMED FROM CODE]** No
  floating-point drift over a six-hour session; the same delta sequence produces bit-identical
  instants.
- **The emit window is half-open `(cursor.emitted, clock.now]`**, and the cursor — not the clock —
  is the single truth for what the sink already holds (`SSRReplayCursor::PendingRange`).
  **[CONFIRMED FROM CODE]** This is what stops a second pump into the same minute re-sending the
  first pump's ticks.
- **`TruncateFrom`'s return value is the truth, not the request.** The MT5 sink cuts on an M1
  open; the controller re-seats the cursor from what came back. **[CONFIRMED FROM CODE]**
- **Two-layer future guard.** The controller clamps before asking (`ClampRange`), and every
  provider re-checks on the way out (`GuardRange`, `FilterTicks`, `FilterRates`). One layer is an
  assertion; two layers survive a new data source. **[CONFIRMED FROM CODE]**
- **`ClipBar` clips the *bar* to `hi` while the ticks are trimmed to `[lo,hi]`** — two different
  rules on purpose (`SSR_ReplayController.mqh:269-310`). **[CONFIRMED FROM CODE]** Merging them
  corrupts either the candle or the observer's view.

**What is fragile.** Five of the fourteen `HIGH` findings are here, and they share one root:
**work that reaches the sink without reaching the observers, or work the cursor claims without
doing.**

- `core-engine-1` (HIGH, CONFIRMED, `SSR_ReplayController.mqh:524`) — the per-pump budget cap
  overwrites `nb` with `cap`, so the "stop short and stay owed" branch below it can never fire,
  and the cursor advances past bars that were never read. The comment at 519-522 documents the
  opposite intent.
- `core-engine-3` (HIGH, CONFIRMED, `:1383`) — `JumpForward` feeds bulk bars to the sink via
  `SeedBars` and publishes none of them. `StepBackward` routes through `JumpForward`, so every
  step back replays up to five minutes blind to the trading engine.
- `core-sync-1` (HIGH, CONFIRMED, `SSR_MasterClock.mqh:208`) — the group's idle gap-skip fires
  mid-bar at human speeds (25 pumps × 40 ms = 1 s of idle is reached inside every minute at 1×,
  because synthetic tick stamps are ~8.6 s of replay time apart) and bulk-writes the unfinished
  bar down the same blind path.
- `core-engine-2` (HIGH, CONFIRMED, `:1169`) — `StepBars(n)` from a bar end advances `n-1` bars;
  `StepBars(1)` is a no-op after the first step.
- `core-engine-4` (HIGH, CONFIRMED, `:349`) — a `FULL_TICK` window that returns zero ticks is
  consumed silently; `n == 0` has no branch, and tick availability is never re-evaluated per
  window.

The bulk-write hole is not a bug in one function; it is an **invariant the codebase wrote down
and then relied on in places where it does not hold**. `core-sync` §11.5 states it plainly:
"Bulk writes bypass observers. Anything that reaches the sink via `SeedBars` (warmup, jump, gap
skip, rewind-forward) is invisible to the trading engine." **[CONFIRMED FROM CODE]** That single
sentence is the parent of `core-engine-3`, `core-sync-1`, and — one layer up — of
`strategy-integration-report-1` (HIGH, the market view frozen in `FULL_TICK`) and of the
trading engine's rewind exposure. **[INFERENCE]**

**Counters that are wrong by construction.** `bars_consumed` counts (pump × bar) synthesis events,
not bars: `bars_used++` runs unconditionally per bar per pump (`core-engine-5`, MEDIUM), and the
same cumulative figure is handed to `CSSRMetrics` as if it were a per-pump count, so `m_bars`
grows quadratically (`core-engine-9`, `core-sync-4`, both LOW). **[CONFIRMED FROM CODE]** The
number is drawn on the panel, summed by `GroupPort`, written into `.pos` and session files, and
used by `RestoreFrom` as the fallback consistency check for fingerprint-less files. Any redesign
that treats it as a bar count inherits the error.

---

### B.3 `Mt5` — the custom-symbol boundary

**What it is.** Three files, 1,461 lines: the manager (the MetaTrader side of one replay symbol),
the sink (the adapter the engine talks to, implementing `CSSRReplaySink`), and the on-disk seed
cache. **[CONFIRMED FROM CODE]**

**What is sound.**

- **Two write rules, stated in the header and held everywhere: warmup goes in as BARS
  (`CustomRatesUpdate`), replay goes in as TICKS (`CustomTicksAdd`); truncation is deletion.**
  **[CONFIRMED FROM CODE]** This is the reason a 60,000-bar warmup is tolerable.
- **`SYMBOL_CHART_MODE = BID` forced on creation and read back** (`SSR_CustomSymbolManager.mqh:383-395`),
  paired with `TICK_FLAG_LAST` on every synthetic tick (`SSR_TickSynthesizer.mqh:174, 203`).
  **[CONFIRMED FROM CODE]** The header records the measured failure this pair fixes: "60 calls
  offered ticks, the terminal took 481, refused 0, and the M1 series stayed at 139 bars."
- **24/7 quote and trade sessions, verified by read-back, not by return value**
  (`Apply247Sessions`, `:165-216`). **[CONFIRMED FROM CODE]** Outside a session the terminal
  accepts ticks and builds no bar — the same silent failure by a different route.
- **The seed cache never trusts its manifest alone**: `SERIES_BARS_COUNT`, `SERIES_FIRSTDATE` and
  `SERIES_LASTBAR_DATE` from the terminal must agree before a reuse is allowed
  (`SSR_SeedCache.mqh:165-205`). **[CONFIRMED FROM CODE]** The asymmetry is chosen correctly: a
  false negative costs a reseed, a false positive puts the previous session's future on this
  session's chart.
- **Teardown order is charts → Market Watch → delete**, because the terminal refuses to delete a
  symbol a chart is open on. **[CONFIRMED FROM CODE]**

**What is fragile.** Ownership across the handover. `CSSRCustomSymbolSink`'s destructor tears the
symbol down whenever the object dies with `m_own_symbol && IsCreated()`
(`SSR_CustomSymbolSink.mqh:69-75`); `SetOwnsSymbol(false)` exists but is called only by test T6,
never by the EA, and the symbol is *supposed* to survive `REASON_CHARTCHANGE` so that pass 2 can
adopt it (`mt5-symbol-5`, MEDIUM, **POTENTIAL_RISK**). **[CONFIRMED FROM CODE for the wiring;
the runtime consequence depends on whether MQL5 destructs globals on a chart-symbol change,
which the author has not measured.]**

Two more structural cracks:

- `mt5-symbol-1` (HIGH, CONFIRMED, `SSR_CustomSymbolSink.mqh:265`) — `RepairWarmupIfLost` is
  silently skipped whenever the seed was reused, because `m_reused_seed` is set once in `Prepare`
  and never cleared, so it cannot distinguish "the cache already delivered this" from "the
  terminal has since discarded it".
- `mt5-symbol-3` (MEDIUM, CONFIRMED, `:338`) — `Create()`'s leftover-adopt fallback uses the
  `SYMBOL_DIGITS > 0` existence test that `Adopt()`'s own comment (434-450) documents as wrong for
  whole-point instruments. The same wrong test gates a whole QA section (`qa-smoke-3`, MEDIUM,
  **POTENTIAL_RISK**).

`Destroy()` reports `SSR_OK` and marks the symbol gone even when `CustomSymbolDelete` fails
(`mt5-symbol-8`, LOW, CONFIRMED) — a small thing that matters because a stuck symbol is exactly
what breaks the *next* session.

---

### B.4 `Data` — the only MetaTrader history implementation

**What it is.** Nine files, 2,352 lines. Three concrete providers over one in-memory
`CSSRBarWindow`, plus four planning helpers that read no prices at all: the history catalogue,
the session range, the random picker, and two observers (session watcher, calendar) whose only
power is to ask for a pause. Nothing in this layer writes to disk or draws on a chart.
**[CONFIRMED FROM CODE]**

**What is sound.**

- **M1 only, everywhere.** Every read in the layer is `PERIOD_M1`. **[CONFIRMED FROM CODE]**
- **"Zero bars is data, not failure."** `CSSRBarWindow` records an empty range as covered so the
  next pump across a weekend is a cache hit, and `CSSRMt5BarProvider::ReadBars` returns 0 rather
  than -1 for `SSR_ERR_NO_DATA`. **[CONFIRMED FROM CODE]**
- **`SSRCanBlock()` gates every retry loop** — an indicator gets one attempt and an honest
  failure instead of a frozen terminal. **[CONFIRMED FROM CODE]**
- **No symbol-name parsing anywhere.** Session breaks come from `SymbolInfoSessionQuote`,
  currencies from `SYMBOL_CURRENCY_BASE/PROFIT`, digits and point from the symbol.
  **[CONFIRMED FROM CODE]** This is a discipline most MQL5 codebases fail.
- **`NextBarOpen` is deliberately unguarded and reads times only** (`CopyTime`), with the
  justification written down: a timestamp is the exchange's schedule, not a price.
  **[CONFIRMED FROM CODE]**

**What is fragile.** One flag, probed over one window, decides how every session runs.
`SSRDataRange.has_ticks` is set by a single `CopyTicksRange` over the **last 24 hours of held
history** (`SSR_Mt5Providers.mqh:133-139`), and it is what the host uses to choose `FULL_TICK`
for a replay window that may be years earlier (`SSReplayStandalone.mq5:1153`), and what the
controller feeds to the only policy that can degrade back to synthetic
(`SSR_FidelityPolicy.mqh:114-118`). The range-aware question already exists —
`CSSRMt5TickProvider::HasTicks(symbol, from, to)` at `SSR_Mt5Providers.mqh:379` — and a repo-wide
grep shows it has no caller. `data-1` (HIGH, CONFIRMED). **[CONFIRMED FROM CODE]**

- `data-2` (HIGH, **POTENTIAL_RISK**, `SSR_BarWindow.mqh:218`) — one invalid-OHLC or non-positive
  bar voids the entire loaded window (up to 60,000 bars), and the provider reports that as zero
  bars *with success*, so the clock runs and nothing is shown. The repair step above it
  (`SanitizeBars`) only enforces increasing open times and never inspects prices.
- `data-4` (MEDIUM, CONFIRMED, `SSR_HistoryCatalog.mqh:150`) — `warmup_bars` is used both as a
  count of M1 bars and as a span of wall-clock minutes. They are equal only on an instrument that
  quotes every minute of every day. The same conflation appears in `SSR_ReplayTimeline.mqh:80`
  (`core-engine-6`, MEDIUM): a Monday-morning start seeds almost no warmup, and the higher-
  timeframe chart opens empty.
- `data-5` (LOW, **POTENTIAL_RISK**) — `Ensure` has no `SERIES_SYNCHRONIZED` early-out, so a range
  that legitimately holds zero bars blocks the terminal for 20 seconds and then fails the load.
  The early-out exists 90 lines away in `CSSRBarWindow::LoadRange`. **[CONFIRMED FROM CODE]**

**What is missing, and it is the same thing everywhere in this layer.** `data-11` (IMPROVEMENT,
CONFIRMED): duplicates, out-of-order bars, micro versus session gaps, largest gap, dropped bars,
window hit rate, tick pages and tick read time are all computed on the hot path and then
discarded. The only route by which the window's `dropped=` figure could reach a human is
`CSSRMt5DataSource::ToString()`, which has no caller anywhere in the repository.
**[CONFIRMED FROM CODE]** On a terminal the author cannot run, that is the difference between a
diagnosable fault and "it just showed nothing." **[INFERENCE]**

---

### B.5 `Trading` — the virtual account

**What it is.** Eight files, 4,774 lines: trade vocabulary, risk engine, the 1,278-line trading
engine, auto-pause, statistics, journal, shot book, prop evaluation. **[CONFIRMED FROM CODE]**

**What is sound, and is load-bearing for the product's central safety claim.**

- **There is no `OrderSend`, `CTrade`, `PositionClose`, `ObjectCreate`, `ObjectSet*`,
  `ChartRedraw`, `FileOpen` or `Print` in any of the four execution files.** Measured: across
  `Include/` and `Experts/` the strings `OrderSend`, `CTrade` and `PositionClose` occur seven
  times in total, and all seven are header comments asserting their own absence
  (`SSR_TradingEngine.mqh:6`, `SSR_TradeTypes.mqh:5`, `SSR_IStrategy.mqh:8` and `:18`,
  `SSR_Publisher.mqh:19`, `SSR_ReplayPort.mqh:341`, `SSReplayStandalone.mq5:305`).
  **[CONFIRMED FROM CODE]** The only disk output is indirect,
  through `SaveInto(CSSRSessionFile&)`. The only terminal reads are `SymbolInfo*` on the **custom
  replay symbol**, whose `SYMBOL_TRADE_MODE` is forced to `DISABLED` at creation. Section G treats
  this in full; architecturally the point is that the guarantee is **structural**, not a runtime
  check that can be forgotten.
- **The log is the account.** `m_balance` must equal `initial + Σ(profit + swap − commission)`
  over the position log; `RestoreFrom` recomputes it and `balance_check` verifies it.
  **[CONFIRMED FROM CODE]**
- **One sizing formula, used by the preview and the order.** `PreviewLot` and `OpenWithRisk`
  funnel into the same `LotForRisk`, and `GroupPort` never writes a second formula.
  **[CONFIRMED FROM CODE]** The panel's risk preview therefore cannot disagree with the fill.
- **The engine is registered first among observers** (`SSReplayStandalone.mq5:1176`), so every
  other observer sees an account that has already acted on the tick. **[CONFIRMED FROM CODE]**
- **Statistics own exactly one thing that cannot be recomputed** — the equity curve — and that is
  the one statistic persisted into the session file. **[CONFIRMED FROM CODE]** That is the right
  line to draw.

**What is fragile.** The rewind contract, and it holds the only `CRITICAL` finding outside the
host.

- `trading-exec-1` (**CRITICAL**, CONFIRMED, `SSR_TradingEngine.mqh:640`) — `OnRewind` drops
  positions placed after the cut with a bare `continue`, never reversing the commission charged
  at `Open()`, the realised P/L booked at `BookExit`, or the swap accrued. The only reversal code
  sits *after* the `continue` and runs for kept positions only. Nothing else recomputes
  `m_balance` from the log. T9.7 asserts only that the ticket is gone, with an OPEN trade and
  zero commission, so the leak is invisible to the suite.
- `trading-exec-2` (HIGH, CONFIRMED, `:263`) — `SSRTradeLeg` records volume, price, time, money
  and three swap fields; it does **not** record `sl`, `tp`, `trail_peak`, `mae`, `mfe` or
  `spread_at_exit`. A trailed stop is therefore never lowered again after a rewind, and
  `CheckStops` compares the current bid against a stop the future moved.
- The engine's stated invariant — "every rewind that matters is followed by re-delivery of the
  ticks between the cut and the new now" — does not hold on the checkpoint path, because
  `JumpForward` bulk-seeds bars without publishing them (`core-engine-3`, HIGH). This is the one
  invariant the trading engine relies on that `Core` does not provide.
  **[CONFIRMED FROM CODE for the mechanism; the account-level consequence is INFERENCE from it.]**

Two more that matter for any redesign of execution: `trading-exec-5` (MEDIUM) — the ambiguity
test uses the whole bar range, so a target hit after a mid-bar entry is booked as a stop loss if
the bar's earlier low was below the stop; and `trading-exec-6` (MEDIUM) — no margin check on
entry when margin is modelled, so an unaffordable order is accepted, charged, then stopped out.

**The analytics half is sound in shape and inconsistent in detail.** Three definitions of "the
result of a trade" coexist: the statement's net (`profit + swap − commission`), the CSV's raw
`profit` column with commission and swap beside it (`trading-analytics-4`, MEDIUM), and
`RMultiple()`, which excludes commission while every money measure includes it
(`trading-analytics-10`, LOW). **[CONFIRMED FROM CODE]** Closed-only drawdown walks trades in
slot (open) order rather than close order (`trading-analytics-3`, MEDIUM), and the equity ring
drops its oldest half when full, so the live maximum drawdown can *shrink*
(`trading-analytics-9`, LOW).

**The prop evaluation is the one observer with no persistence.** It has no `SaveInto`/`RestoreFrom`
at all; the session manager stores the account and the equity curve and nothing else
(`trading-analytics-2`, MEDIUM). Worse, resuming a saved session voids a running evaluation at
startup, because `NotifyRestored` publishes an `OnRewind(now)` to every observer and the
evaluation's only guard is `m_state != RUNNING` (`trading-analytics-1`, HIGH, CONFIRMED).
**[CONFIRMED FROM CODE]** Architecturally this is a layer that was added as an observer without
being given the observer's two obligations: rewind semantics and persistence. **[INFERENCE]**

---

### B.6 `Chart` — the layer that holds no pointer to the engine

**What it is.** Six files, 1,881 lines: a registry of charts showing one replay symbol, the
draggable planning lines, the calendar lines, blind mode, the leak guard, and the chart
vocabulary. **[CONFIRMED FROM CODE]**

**What is sound.**

- **The layer asks the engine nothing.** It publishes events through `CSSRChartObserver` and lets
  the host decide what they mean (`SSR_ChartManager.mqh:20`). **[CONFIRMED FROM CODE]**
- **It never trusts `CHART_AUTOSCROLL`** — following is an explicit `ChartNavigate(id, CHART_END, 0)`
  (`:509-530`), because no mouse event reaches the replay chart. **[CONFIRMED FROM CODE]**
- **The draggable lines are polled, never listened for** (`SSR_TradeLines.mqh:286`), and the host
  may only *read* them during a session (`NoteLineDistances`, not `SetStopPoints`) — the removed
  round trip that used to flip short setups is documented at `:253-270`. **[CONFIRMED FROM CODE]**
- **`CloseOwned` never closes `ChartID()`.** A program dies the instant its own chart closes,
  mid-statement, and the leftover custom symbol then breaks the next session with error 5304
  (`:261-303`). **[CONFIRMED FROM CODE]**
- **Blind mode saves the user's original chart settings once per chart** and refuses to blind a
  chart it cannot remember, rather than blinding it and losing the way back (`:152-165`).
  **[CONFIRMED FROM CODE]**

**What is fragile.** Blind mode's memory is instance-only and is never persisted, so it does not
survive a deinit/reinit — and the next `Apply` then records the *blinded* state as the original
(`chart-4`, MEDIUM, CONFIRMED). The reveal is undone within about 200 ms, because `RestoreAll`
clears `m_applied` but leaves `m_policy` on and the host re-applies on `IsOn()` every fifth pump
(`chart-3`, MEDIUM, CONFIRMED). And `Blind FULL` claims the price level is hidden while the entry
line's label and the panel's deal buttons print the absolute price (`chart-5`, MEDIUM, CONFIRMED).
**[CONFIRMED FROM CODE]** For a feature whose entire value is that the user cannot cheat, three
confirmed holes in one class is the weakest area of the layer.

**What is dead.** `CSSRChartObserver` is never wired in production — `SetObserver` is called only
by test T4, so `m_observer` is always `NULL` and every chart event is a no-op
(`chart-10`, LOW, CONFIRMED). `SetPeriodAll` has no caller anywhere.
**[CONFIRMED FROM CODE]** A published-events design that nothing subscribes to is not a seam; it
is a comment with a vtable. **[INFERENCE]**

**What leaks.** `SSR_MARK_*` bookmark lines are created by `MarkTime` and deleted by nothing
(`chart-6`, LOW, CONFIRMED), and the object name embeds the registry index, so bookmarks
duplicate after a chart closes (`chart-17`, LOW, CONFIRMED). In one-chart mode the chart is
handed back to the origin symbol at deinit rather than closed, so whatever is not deleted stays
on a chart the user keeps. **[CONFIRMED FROM CODE]**

---

### B.7 `Ui` — the largest layer, and the one carrying the platform's constraints

**What it is.** 18 files, 10,312 lines — a third of the library. `SSR_Panel.mqh` alone is 3,049
lines and one class. **[CONFIRMED FROM CODE]**

**What is sound, and was paid for once already:**

- **`CSSRWidgets` is the only place in the product that calls `ObjectCreate`/`ObjectSet*` for
  panel chrome**, and it wraps exactly four MQL5 object types into ten primitives.
  **[CONFIRMED FROM CODE]**
- **The write-elision cache's early return requires BOTH "unchanged" AND "still there"** —
  `Same()` ends with `ObjectFind`, because deletion, not drawing, is the dangerous case.
  **[CONFIRMED FROM CODE]**
- **`OBJPROP_STATE` is never written by a draw.** The latch is how the panel learns about a click;
  clearing it during a repaint would erase presses. **[CONFIRMED FROM CODE]**
- **Clicks are read by latch polling, not by `CHARTEVENT_OBJECT_CLICK`.** `PollClicks` walks the
  buttons backwards, clears the latch *before* acting, debounces 200 ms per name, and polls the
  palette first and alone so one click is never read twice; `SSR_Panel.mqh:2878` deliberately does
  not handle `CHARTEVENT_OBJECT_CLICK`. **[CONFIRMED FROM CODE]** This is the click-only constraint
  expressed in its most robust form: it behaves identically whether the panel is on the EA's chart
  or on a chart the EA is not attached to.
- **Creation order is the only z-order, and every composite primitive depends on it** — slider
  (frame → cells → thumb), chip and toast (plate before text), meter (`_bg` → `_fill` → `_lim`).
  **[CONFIRMED FROM CODE]**
- **One generated key table drives both `SSRKeyToCommand` and the key card**, so the card cannot
  drift from the handler. **[CONFIRMED FROM CODE]**
- **`SSR_Theme.mqh` is the only file allowed to contain a colour, enforced by audit A17**, and all
  three palettes define exactly the same 51 tokens (verified: the symmetric difference is empty).
  **[CONFIRMED FROM CODE]**
- **Strings are matched by name, never by enum index**, the language file is read as raw bytes and
  converted with `CP_UTF8` rather than through `FILE_TXT|FILE_ANSI`, and `fa.txt` carries 190/190
  keys with zero unknown keys and zero printf-specifier mismatches. **[CONFIRMED FROM CODE]**
- **`SSRUiState` is a flat, pointer-free wire of 89 declared members** (measured), so an IPC port
  could fill it from numbers alone. **[CONFIRMED FROM CODE]**
- **"Removed, not merely undrawn"** — the panel repaints from state and never clears the chart, so
  a sheet the strip no longer has must be `Remove()`d. **[CONFIRMED FROM CODE]**

**What is fragile.** Two caches sit on top of each other — the panel's 128-slot label cache above
the widget layer's 512-slot property cache — and the frame path defeats both every single frame:

- `ui-panel-1` (MEDIUM, CONFIRMED, `:1270`) — `DrawSheet` deletes and recreates the entire visible
  sheet on every repaint.
- `ui-panel-2` (MEDIUM, CONFIRMED, `:729`) — `HideBody(false)` runs every frame and `Forget()`s
  the property cache for about 44 sized objects, which are then rewritten in full.
- `ui-plumbing-6` (LOW, CONFIRMED, `SSR_Widgets.mqh:103`) — the property cache has no tombstones,
  so `Forget()` can silently clear nothing and `Keep()` then writes a duplicate, leaking slots
  until the cache stops working.

Section E prices this; architecturally the point is that the cache is correct and the *caller* is
wrong, which is a good problem to have. **[INFERENCE]**

**One architectural contradiction the tree has not settled.** The widget layer is built on the
premise that the panel "never receives a mouse coordinate" (comments at `SSR_Widgets.mqh:437-443`
and `SSR_Panel.mqh:929`), and that premise is what makes latch polling correct. But the host sets
`g_panel_chart = ChartID()` (`SSReplayStandalone.mq5:1463`), `CSSRPanel::Create` forces
`CHART_EVENT_MOUSE_MOVE = true` (`:301`), and `OnEvent` handles `CHARTEVENT_MOUSE_MOVE` at `:2885`
for the caption drag and the speed-groove drag. **[CONFIRMED FROM CODE]** In one-chart mode — the
default — the panel's chart *is* the replay chart, so mouse and key events do arrive. Two
statements in the tree describe the same surface and only one can be the contract.
**[INFERENCE]** A redesign must choose: either click-only is the contract and the two drags are
a two-window-mode-only affordance that must degrade, or mouse input is the contract and the
click-only discipline is an optimisation. Today both are assumed in different files.

**Where the geometry has run out.** `ui-panel-6` (MEDIUM, CONFIRMED) — the status strip draws the
fidelity readout at `x+330` in a 310 px panel, permanently outside the frame and on the candles.
`ui-panel-7` (MEDIUM) — the position-row note column has 9 px for a 9-character note.
`ui-panel-13` (LOW) — the caption chip row overruns the collapse button by 6 px. The instrument
built to catch exactly this (`Extent()`/`CheckFrame()`) is blind to labels by design, because
MQL5 offers no text measurement, and nothing in the codebase ever reads
`FrameOverflowRight/Bottom`. **[CONFIRMED FROM CODE]**

**The 63-character limit is understood and applied at five sites out of hundreds.** `Clip()`
caps at 62 and marks the cut; `SSR_Review.mqh` is the only dialog file that defends itself
(`SSR_REVIEW_ROW_MAX 60`). Audit A14 measures only literal-only arguments at the widget call
site, so anything assembled at runtime is unmeasured, and A14 omits four of the eight
text-drawing helpers that A19 already knows about (`spikes-audits-28`, LOW, CONFIRMED).
**[CONFIRMED FROM CODE]**

**`SSR_Layout.mqh` is dead in production** (`ui-plumbing-5`, IMPROVEMENT, CONFIRMED): 145 lines
whose stated purpose is "the one place that knows WHERE" and the enabler of a future RTL layout;
no production file calls any of its functions, and `rtl = true` is passed exactly once, in the QA
smoke test. **[CONFIRMED FROM CODE]** For a product localised to Persian, that is a plan with no
backing.

---

### B.8 `Session` — 415 lines at the top of the dependency order

**What it is.** One file. `CSSRSessionManager` orchestrates save and restore over
`CSSRSessionFile` (which lives in `Common`). Nothing in the tree depends on it except
`Ui/SSR_GroupPort.mqh` and the host. **[CONFIRMED FROM CODE]**

**What is sound.**

- **Streams first, account after**, with the reason written down: winding a stream re-emits ticks,
  and an account already holding the session's positions would run stops against pre-entry prices.
  **[CONFIRMED FROM CODE]**
- **"The master follows the streams, never the file."** After restoring each stream the manager
  takes `now` from stream 0 and calls `SeekAllTo(now)`. **[CONFIRMED FROM CODE]**
- **No price data is stored.** Bars are re-read from the broker and a fingerprint reports — never
  blocks — a change. The digest folds integer-scaled prices rather than double bit patterns
  precisely so a round-tripped bar does not cry wolf, and it travels as a signed long because
  `%I64u` would exceed what `StringToInteger` can read back for about half of all digests.
  **[CONFIRMED FROM CODE]** This is the most carefully reasoned piece of file-format work in the
  repository.
- **Packed rows append, never insert**, so adding a field is backward-compatible in both
  directions without bumping the format number. **[CONFIRMED FROM CODE]**
- **The balance is replayed from the trade log, never read.** `balance_check` only produces a
  warning. **[CONFIRMED FROM CODE]**

**What is fragile.** The mid-session save/load path reached from the panel is the one the
invariants were not written for. `ui-port-session-3` (HIGH, CONFIRMED, `:350`): `Restore` never
checks that the streams reached the saved instant and cannot rewind to it — `master_now` is
written and only ever read by `Peek`, and `RestoreFrom` moves forward only. Save at 10:00, play on
to 10:30, press Load, and the resume report prints wherever the streams happen to be.
**[CONFIRMED FROM CODE]**

`ui-port-session-2` (MEDIUM, CONFIRMED, `SSR_SessionFile.mqh:138`): saving truncates the previous
good session before writing the new one. `ui-port-session-13` and `-15` (LOW, **POTENTIAL_RISK**):
restoring an account is O(entries × rows) because every packed row is fetched by linear scan, and
the file is written in the terminal's ANSI codepage, so non-ASCII trade tags do not survive.

**A whole block of the format is write-only.** `SSRSessionSettings` is written by the host's
`CollectSettings()` and `ReadSettings` has exactly one caller in the tree — the T12 test
(`host-expert-10`, LOW, CONFIRMED). **[CONFIRMED FROM CODE]** The settings block records the raw
inputs rather than the values the session actually ran with, so a saved session misdescribes
itself; the impact is bounded only because nothing reads it back.

---

### B.9 `Strategy` — a correct contract over a stream that does not always deliver

**What it is.** Four files, 1,158 lines: the strategy contract and broker facade, the
lookahead-free market view, a reference breakout strategy, and the host that turns the replay
stream into "a bar closed" and "a tick arrived". **[CONFIRMED FROM CODE]**

**What is sound.**

- **Tags are identity.** Every order a strategy places carries its `Name()` as the position tag,
  which is what makes per-strategy statistics possible without a second bookkeeping path.
  **[CONFIRMED FROM CODE]**
- **The broker is a facade, not a subclass** — a strategy is given a narrowed surface over the
  same trading engine, and sizing goes through the engine's own formula, never a second one.
  **[CONFIRMED FROM CODE]**
- **Registration order is enforced and documented**: `Attach` → `SetSeed` → `Add`, and each
  strategy's RNG stream is seeded `m_seed ^ NameHash(name)`, so the order strategies are added in
  cannot change results. **[CONFIRMED FROM CODE]**
- **Accessors return `bool` plus an out-parameter, never `0.0` for "unavailable"**, and refusals
  are counted. **[CONFIRMED FROM CODE]** The reference strategy treats a refusal as "end the bar",
  never as zero.
- **The view is registered before the host**, so by the time a hook runs the bar is already there.
  **[CONFIRMED FROM CODE]**

**What is fragile, and it is inherited rather than local.**

- `strategy-integration-report-1` (HIGH, CONFIRMED, `SSR_MarketView.mqh:173`) — in `FULL_TICK`
  fidelity the controller publishes ticks and never a bar context, so the view's bar buffer only
  ever changes through `Prime()`, and a strategy reads a snapshot frozen at the first pump while
  `Now()`, `Bid()` and `Ask()` keep advancing. That is the worst possible failure shape: live
  scalars over dead bars.
- `strategy-integration-report-2` (MEDIUM) — `OnBar` is detected from the last tick of a published
  *batch*, so the firing point and the resulting fill price are functions of wall-clock pump
  boundaries.
- `strategy-integration-report-3` (LOW) — `OnTick` fires once per batch, not once per tick, so the
  documented intrabar-management use is unreachable.
- `strategy-integration-report-4` (LOW) — the per-strategy RNG is seeded once at registration and
  is never rewound, so a strategy that draws from it is not reproducible across a step back.
- `strategy-integration-report-5` (LOW) — `IsSynthetic()` can never return false, so the honesty
  instrument it exists to be is dead.

The pattern: the contract is written for a tick stream with bar context, and the engine delivers
that in two of its three fidelities. **[INFERENCE]**

---

### B.10 `Integration` — the best-isolated layer in the product

**What it is.** Three files, 896 lines: a self-contained wire contract, the replay-side publisher,
and a portable client. `SSR_Contract.mqh` includes nothing, so a third product can copy it plus
`SSR_Client.mqh` and be integrated. **[CONFIRMED FROM CODE]**

**What is sound, and should be the model for the rest:**

- **Frozen wire numbers.** Internal enums may be renumbered; the wire may not, and the mapping is
  written as switches, never casts. **[CONFIRMED FROM CODE]**
- **A heartbeat, not a flag**, because terminal global variables outlive the program that wrote
  them. The heartbeat is written **last** in `Publish()`, so a client that reads it first never
  sees a fresh beat beside stale values. **[CONFIRMED FROM CODE]**
- **`cmd.rc` is written before `cmd.ack`**, for the same reason in the other direction.
  **[CONFIRMED FROM CODE]**
- **Permissions are enforced on the replay side only**; the client's check is an explicit courtesy
  for error messages. **[CONFIRMED FROM CODE]**
- **Nothing forward-looking is published.** There is deliberately no verb that reads data at a
  time — a client that could ask for a bar could ask for a future one — and the only
  forward-looking datum on the wire is `end_msc`, the window boundary. **[CONFIRMED FROM CODE]**
  This is the future guard restated at the product boundary, and it is exactly right.

**What is fragile.** `strategy-integration-report-7` (LOW, CONFIRMED) — the publisher rejects a
command whose sequence equals the last one it executed, so a restarted client has one command
silently dropped and reported as a timeout. `strategy-integration-report-12` (LOW) — `SetSlot` is
unbounded while `Discover` only scans 1..`SSR_MAX_SLOTS`, so extra-stream publishers can be
invisible or collide with a second session. Both are small; the layer is 896 lines and carries
three findings.

---

### B.11 `Report` — two documents, one skin

**What it is.** Two files, 825 lines: a shared HTML head/CSS/theme-toggle used by both the trade
statement and the class report, and the class report itself. **[CONFIRMED FROM CODE]**

**What is sound.** One skin for two documents, with a complete light palette on `:root`, the same
tokens redefined under `prefers-color-scheme: dark` guarded as `:root:not([data-theme="light"])`,
and again under `:root[data-theme="dark"]`. **[CONFIRMED FROM CODE]** The class report refuses to
*claim* comparability across sessions: `session_key` is what two identical runs share, and the
report names students who ran a different session rather than quietly averaging them.
**[CONFIRMED FROM CODE]**

**What is fragile.** The refusal is stated and then not held: the class KPI row, the ranking sort
and the bar scale all include students on a different key (`strategy-integration-report-9`,
MEDIUM, CONFIRMED). And the document declares UTF-8 while being written with `FILE_ANSI`, so
non-ASCII student, symbol and session names come out as mojibake
(`strategy-integration-report-8`, MEDIUM, CONFIRMED) — the same encoding mismatch as
`trading-analytics-13` (LOW, **POTENTIAL_RISK**) in the journal exports, on a product localised
to Persian. **[CONFIRMED FROM CODE]**

**The structural note.** `Trading → Report` is the one upward include edge in the tree
(`SSR_Journal.mqh` includes `SSR_ReportStyle.mqh`). **[CONFIRMED FROM CODE]** It is benign —
`SSR_ReportStyle.mqh` is a leaf that knows nothing about trades — but it is the reason `Report`
cannot be described as sitting above `Trading`, and a later reader should not "fix" it by moving
the file into `Trading`, which would put HTML in the trading layer. **[RECOMMENDATION]**

---

### B.12 `Common` — the base, and a drawer

**What it is.** Ten files, 1,673 lines: types and enums, the msc↔datetime seam, platform facts,
symbol naming, the RNG, the fingerprint, the logger, the flight recorder, the session file format,
and the build stamp. Nothing includes upward out of it. **[CONFIRMED FROM CODE]**

**What is sound.**

- **`SSR_Time.mqh` is the only msc↔datetime seam**, and `SSRBarOpenMsc` documents that it is wrong
  for W1/MN1 by design, with every caller checking `SSRIsSupportedTimeframe` first.
  **[CONFIRMED FROM CODE]** Naming the limitation and guarding at the call sites is better
  engineering than a helper that silently refuses.
- **`SSRPickSeed()` is the one place a wall clock may be read**, and it exists to print a number
  back at the user; everything downstream is a pure function of it. **[CONFIRMED FROM CODE]**
- **`SSR_SymbolNaming.mqh` is pure string logic in `Common`** specifically so the `Chart` layer can
  recognise a replay symbol without depending on `Mt5`. **[CONFIRMED FROM CODE]** That is a
  deliberate, correct placement.
- **The flight recorder flushes every line**, so a killed terminal still yields the file.
  **[CONFIRMED FROM CODE]**

**What is wrong with it as a *layer*.** `Common` has become the place things go when they belong
to no one. `SSR_SessionFile.mqh` (416 lines) is a file format owned by `Session`;
`SSR_FlightRecorder.mqh` (276 lines) is diagnostics owned by nobody and audited under `Chart`;
`SSR_Log.mqh`'s `SetFile()` has no caller anywhere, so the file sink is unexercised code and in
production the logger is `Print`-only. **[CONFIRMED FROM CODE]** None of this is harmful today —
they are all leaves — but "base layer" and "drawer" are different things, and the next person to
add a shared helper will follow whichever precedent is nearer. **[INFERENCE]**

Two small scars worth naming: the flight recorder truncates `chart_id` to 32 bits, corrupting the
column that identifies which chart a fault happened on (`chart-13`, LOW, CONFIRMED), and its CSV
is written to `MQL5/Files/SSReplay-flight-*.csv` rather than under `MQL5/Files/SSReplay/` like
every other artefact. **[CONFIRMED FROM CODE]**

---

### B.13 The Expert host

**What it is.** One translation unit, 3,255 lines, **zero classes**, 61 `input`s, 35 top-level
global `CSSR*` objects, and an 815-line `BuildSession()` (971-1786) whose step order is
load-bearing and documented step by step. **[CONFIRMED FROM CODE]**

**What is sound.** More than the shape suggests.

- **The build order is written down and justified at each step** — blind policy decided once and
  only here (because it decides the replay symbol's *name*, so both passes must agree); observers
  registered in a fixed order with the rationale at 1162, 1188 and 1214; the flight recorder
  opened before the first pump. **[CONFIRMED FROM CODE]**
- **The `Cfg*()` accessor layer** exists precisely so that "one place knows which of the two wins —
  rather than thirty call sites each remembering, and one of them forgetting" (comment 206-213).
  **[CONFIRMED FROM CODE]**
- **The window start is counted in *bars*, never in minutes** — `CopyRates(origin, M1, 0,
  InpReplayBars)` — which is the weekend-gap lesson encoded. **[CONFIRMED FROM CODE]**
- **`OnTick` is deliberately empty**; the engine runs on `OnTimer` only. **[CONFIRMED FROM CODE]**
- **`FlightGuard` prints one line per distinct reason the timer turned back**, and the watchdog
  tests "the timer has never *entered*" rather than "no pumps happened". **[CONFIRMED FROM CODE]**
  Both are the right instrument for a program the author cannot attach a debugger to.
- **The event precedence ladder is explicit** and `CSSRPanel::Owns` decides which commands the
  panel executes and which the host must run. **[CONFIRMED FROM CODE]**

**What is fragile: the two-pass handover.** In the default `InpOneChart` mode the EA turns its own
chart into the replay chart with `ChartSetSymbolPeriod`, dies with `REASON_CHARTCHANGE`, and comes
back on the replay symbol. Seven invariants (I1–I7 in the host map) hold it together, of which I1
is "chart objects survive `ChartSetSymbolPeriod`, so `SSR_ORIGIN_HANDOFF` is the transport for the
origin symbol name." **[CONFIRMED FROM CODE]**

`host-expert-1` (**CRITICAL**, CONFIRMED, `:1806`) breaks I1 outright: `OnInit`'s second statement
is an unconditional `SSRPurgeChart(0, SSR_PICK_LINE)`, which deletes every object on chart 0 whose
name starts with `"SSR"` except the one `keep`. Both handover objects are named `SSR_ORIGIN_HANDOFF`
and `SSR_PICK_HANDOFF`. The stash is deleted before it is read. **[CONFIRMED FROM CODE]**

Four more host findings are the *same class of mistake* — a guard that tests the wrong one of two
similar flags:

- `host-expert-3` (MEDIUM) — auto-play is suppressed on the pass that actually owns the replay
  chart, because the guard tests `one_chart_ok` instead of "am I about to hand over".
- `host-expert-4` (LOW) — the first-run card can never appear in one-window mode, same wrong guard.
- `host-expert-13` (LOW) — the picker path rebuilds with `InpOneChart`, discarding the
  `one_chart_ok` poison `OnInit` had just read.
- `host-expert-5` (MEDIUM) — a random session does not survive the handover: pass 2 either re-rolls
  a new seed or drops randomness, and can replay a different instrument under pass 1's symbol name.

**[CONFIRMED FROM CODE]** Five findings, one root cause: *the host carries two nearly-identical
booleans about the same situation and no single function answers the question.* **[INFERENCE]**

**What is over-coupled.** 35 globals with no ownership structure; six of them are cleared in
`OnInit` deliberately "because the code does not know whether globals survive the
`REASON_CHARTCHANGE` reload" (comment 1808-1834), and the rest are not. **[CONFIRMED FROM CODE]**
The comment is honest and the uncertainty is real — but an architecture that cannot answer
"does my state survive a reinit?" has to answer it for *every* variable, not six.
**[RECOMMENDATION]**

`host-expert-8` (MEDIUM, CONFIRMED) — replay and extra-timeframe chart windows are leaked on every
re-init that is not a user removal, because `CloseOwned()` runs only under
`REASON_REMOVE|PROGRAM|CLOSE`. **[CONFIRMED FROM CODE]**

**The stated end state is unbuilt.** The header comment (lines 5-27) describes engine in a
Service, panel in an indicator, joined by IPC, with `CSSRReplayPort`/`CSSRGroupPort` as the seam
that makes it a wiring change. **[CONFIRMED FROM CODE]** The seam exists and is genuinely good —
but there is exactly one implementation of `CSSRReplayPort`, and the "Ipc" port its own header
names does not exist. **[CONFIRMED FROM CODE]** The spikes that were supposed to decide
Service-versus-EA (C1, C2) are two of the ones whose verdicts cannot fail (`spikes-audits-21`,
MEDIUM; `spikes-audits-22`, LOW). **[CONFIRMED FROM CODE]**

---

### B.14 The relationships: five seams that carry the system

Layers are easy to judge; the seams between them are where this product will succeed or fail. Five
matter.

#### Seam 1 — `Core ↔ Data` / `Core ↔ Mt5`: three contracts, cleanly inverted. **Sound.**

`Core` declares `CSSRHistoryProvider`, `CSSRBarProvider`, `CSSRTickProvider` (in
`SSR_IDataSource.mqh`), `CSSRReplaySink` (in `SSR_IReplaySink.mqh`) and `CSSRTickObserver` (in
`SSR_ITickObserver.mqh`), and depends on nothing but `Common`. `Data` and `Mt5` implement them.
**[CONFIRMED FROM CODE]** There are two source implementations (`CSSRMemoryDataSource` for tests,
`CSSRMt5DataSource` for production) and one sink, which is exactly enough to prove the abstraction
is real rather than aspirational. This seam should not be touched. **[RECOMMENDATION]**

One asymmetry to know before extending it: the base `CSSRDataSource::SetGuard`/`DetachGuard` walk
through `Ticks()`, which returns `NULL` while no ticks are loaded, so a naive source leaves its
tick provider unguarded. `CSSRMt5DataSource` overrides both to reach all three providers directly
and says so in a comment. **[CONFIRMED FROM CODE]** A third source must do the same.

#### Seam 2 — `Core → observers`: the one seam with a hole in it. **Fragile.**

Nine observers are registered in a fixed, documented order: account → stats → [prop] → autopause →
shots → calendar → session watcher → market view → strategies. **[CONFIRMED FROM CODE]** The order
is right and the reasons are written down. The hole is that **the observer channel is fed only from
`EmitWindow`**, via `PublishBar`/`PublishTicks`/`PublishSegment`, while four other paths write to
the sink directly: warmup seeding, `JumpForward`'s bulk bars, the group's idle gap skip, and the
rewind-then-forward path inside `StepBackward`. **[CONFIRMED FROM CODE]**

This is the single most consequential structural crack in the product, because it is a *silent
divergence between the chart and the account*. The candles advance; the stops do not get checked.
It is the parent of `core-engine-3` (HIGH), `core-sync-1` (HIGH),
`strategy-integration-report-1` (HIGH) and the checkpoint half of the rewind problem.
**[INFERENCE]**

[RECOMMENDATION] Whatever the fix, it belongs at the seam and not in the callers: one function that
"delivers to the sink and to the observers" and no other route to the sink. The alternative — every
future navigation verb remembering to publish — is what produced four instances of the same defect.

#### Seam 3 — `Ui → everything`, through `CSSRGroupPort`. **Sound in shape, over-coupled in fact.**

The port is the product's best structural idea: the panel holds a `CSSRReplayPort*`, reads one
flat pointer-free struct, and calls verbs. A read-only port needs no code because every verb
except the thirteen pure-virtual ones defaults to refusal. **[CONFIRMED FROM CODE]**

The implementation is where it strains. `CSSRGroupPort` is 1,110 lines and holds **eleven** non-owned
collaborators — `m_group`, `m_sink`, `m_charts`, `m_blind`, `m_acct`, `m_stats`, `m_strategies`,
`m_sessions`, `m_lines`, `m_journal`, `m_prop` — drawn from `Core`, `Mt5`, `Chart`, `Trading`,
`Strategy` and `Session`, wired by nine separate `Attach*` calls from the host.
**[CONFIRMED FROM CODE]** Every one of them may be `NULL` and is checked at each call site.

That is not a wire; it is an assembly. **[INFERENCE]** The consequence shows up as findings that
are really *ownership* questions: `ui-port-session-10` (LOW) — a save made from the panel records
settings that are not the session's, because `SaveSession(name)` builds a **default**
`SSRSessionSettings` and sets only `slot`; `ui-port-session-9` (MEDIUM) — pending orders occupy
wire rows that no total on the wire accounts for, because `pos_rows` and `open_positions` were
defined before pendings were rows. **[CONFIRMED FROM CODE]**

[RECOMMENDATION] Keep the port and the wire exactly as they are. Split the *implementation* along
the lines the wire already implies — transport, account, session, chart — rather than growing a
twelfth `Attach`.

#### Seam 4 — the two-pass handover. **The most fragile thing in the product.**

Three transports carry state across a deliberate program death: two chart objects
(`SSR_ORIGIN_HANDOFF`, `SSR_PICK_HANDOFF`), one `.ini` file (`setup.ini`), and one custom symbol
plus its manifest that must survive because pass 2 adopts rather than recreates.
**[CONFIRMED FROM CODE]** Each transport has a confirmed defect: the chart objects are swept before
they are read (`host-expert-1`, CRITICAL); `setup.ini` is restored unconditionally on pass 2, so a
run that never opened the setup form inherits an unrelated earlier run's balance, prop rules and
session name (`host-expert-6`, MEDIUM); and nothing switches the sink's `m_own_symbol` off for the
transition the symbol is supposed to survive (`mt5-symbol-5`, MEDIUM, **POTENTIAL_RISK**).

[INFERENCE] The design is sound in intent — one chart is what a trader wants, and MetaTrader gives
no other way to put a replay symbol on the chart the EA is attached to. The fragility is that the
protocol has no single owner: the origin name, the picked start, fourteen settings, the symbol, the
manifest and six globals are each handled by different code with different lifetimes, and no
function answers "am I pass 1 or pass 2" except `SSRIsReplaySymbol(_Symbol)` at `:1863`.

#### Seam 5 — `Journal → ClassReport`, a contract made of CSV. **Sound, and correctly documented.**

The class report parses the journal's own CSV: the `# SS Replay journal` marker, `# window_start`
and `# window_end` in milliseconds, `# session_key`, `# ambiguous_trades,%d (%.1f%%)`, an 18-column
row header, `open_time` written by `SSRFormatMsc`, and `r` written *empty* rather than zero when
the trade had no stop. **[CONFIRMED FROM CODE]** Both sides open `FILE_TXT|FILE_ANSI`, so the
encodings match — which is also why both are wrong together for non-ASCII names
(`strategy-integration-report-8`). The coupling is written down in both files, which is the right
way to have a file-format dependency between two layers that must not include each other.
**[INFERENCE]**

---

### B.15 The central architectural bet, judged on its merits

**The bet.** Write **M1 bars and ticks only** into a custom symbol, and let MetaTrader derive
M5…D1, build the series, draw the candles, and run the user's own indicators, templates and
objects on them.

**What the code actually does.** Exactly two write APIs are called in the whole product:
`CustomRatesUpdate` (warmup and bulk jumps) and `CustomTicksAdd` (the live replay stretch), both in
`SSR_CustomSymbolManager.mqh:619` and `:678`, and nothing else writes market data anywhere.
**[CONFIRMED FROM CODE]** Higher timeframes reach the user one way only:
`CSSRChartManager::OpenLayout` opens a chart on the replay symbol at each requested timeframe and
refuses W1/MN1 (`SSR_ChartManager.mqh:229-243`). **[CONFIRMED FROM CODE]**

**In favour of the bet — and these are large.**

1. **It is the only way the user's own chart survives.** Every indicator, template, drawing tool,
   object and chart setting the trader already owns works on a replay symbol for free, because it
   *is* a symbol. **[INFERENCE, from the platform constraint set]** No amount of MQL5 work buys
   that any other way.
2. **The alternative is not affordable.** Drawing candles as chart objects costs, at the measured
   rate of 561 property writes per 39.05 ms (≈0.07 ms per write), about 18 writes per candle for a
   body and a wick — roughly 5,400 writes and ~376 ms for a 300-bar view, against a 40 ms pump.
   **[INFERENCE, arithmetic over the measured figure]** It is an order of magnitude over budget
   before a single indicator is drawn, and MQL5 has no clipping to keep it inside a frame.
3. **It collapses the write path to one rule pair.** Warmup as bars, replay as ticks; truncation is
   deletion at one M1-aligned instant in both stores. **[CONFIRMED FROM CODE]** Every rewind,
   reset, jump and checkpoint restore reduces to "cut here", which is why the cursor/sink contract
   can be four lines long.
4. **It keeps the engine free of MetaTrader.** `Core` compiles against `Common` alone; M1-only is
   what makes that possible, because a multi-timeframe engine would need the terminal's alignment
   rules inside it. **[CONFIRMED FROM CODE]**
5. **It is guarded correctly.** `SSRBarOpenMsc` is epoch-floored and documented as wrong for
   W1/MN1, and every caller checks `SSRIsSupportedTimeframe` first. **[CONFIRMED FROM CODE]** The
   bet's boundary is named rather than assumed.

**Against the bet — three real costs, one of which is serious.**

1. **The half that production depends on is the half that was not measured.** Spike A2 is the right
   test and is well designed: golden M1 dataset, independent reference aggregation, zero tolerance,
   "even one mismatch is a FAIL", verdicts `agg_<tf>_ohlc_exact` per timeframe
   (`SSR_A2_RatesAndAggregation.mq5:29-90`). **[CONFIRMED FROM CODE]** But A2 writes M1 with
   `CustomRatesUpdate` and then checks aggregation. Production's replay stretch does not write
   bars: it writes **ticks**, and the terminal builds M1 from them before building anything higher.
   The spike for *that* path is B1, and B1 carries two confirmed defects: its
   `wick_expanded_to_extremes` verdict fails deterministically no matter how MetaTrader behaves
   (`spikes-audits-2`, MEDIUM), and no spike anywhere forces `SYMBOL_CHART_MODE = BID` or sets
   `TICK_FLAG_LAST` — the exact pair the product itself found load-bearing and documented at
   `SSR_TickSynthesizer.mqh:157-175` (`spikes-audits-3`, MEDIUM). **[CONFIRMED FROM CODE]** So the
   tick→M1→HTF chain, which is the chain every live session uses, is verified by a spike that
   cannot pass and that is missing the two settings without which the transport is known to fail.
   And `SSR_BarToTicks` in the spike kit — "the same assumption the engine will make, tested here
   first" — never emits a tick at the bar's high or low unless `(n-1)` is divisible by 3, and the
   engine's own synthesizer is the identical formula with a default of 8 ticks per bar, the worst
   case measured (`spikes-audits-1`, HIGH). **[CONFIRMED FROM CODE]**
2. **The bet is made twice, in two different code paths, and nothing reconciles them.** MetaTrader
   aggregates M1 → H1 for the chart. `CSSRMarketView::Group()` aggregates M1 → H1 in process, with
   its own walk, for strategies (`SSR_MarketView.mqh:80-145`). **[CONFIRMED FROM CODE]** They are
   not the same code and they do not fail the same way: `Group()` returns shift 0 with a wrong open
   and an un-aggregated spread when the group began before the buffer did
   (`strategy-integration-report-13`, LOW), and in `FULL_TICK` fidelity the view is never fed bars
   at all (`strategy-integration-report-1`, HIGH). A strategy and the human looking at the chart
   therefore do not necessarily see the same H1 candle. That is a cost of the bet, not of the
   strategy layer: the moment higher timeframes are derived rather than stored, every consumer needs
   its own derivation, and the product now has two. **[INFERENCE]**
3. **Laziness and warmup arithmetic are inherited costs.** The first `Bars()` read on an untouched
   timeframe returns 0, so every non-M1 read needs priming — audit A21 exists for nothing else, and
   it is blind to a timeframe argument that is not a bare identifier (`tests-a-10`, LOW,
   **POTENTIAL_RISK**). **[CONFIRMED FROM CODE]** And "enough context for a D1 chart" becomes
   `WarmupFor(D1, 200) == 288,000` M1 bars, while `warmup_bars` is simultaneously treated as a
   count of bars and a span of minutes (`data-4`, MEDIUM; `core-engine-6`, MEDIUM). The bet pushes
   the whole cost of higher-timeframe context into the M1 seed, and the seed arithmetic is wrong on
   any instrument that does not quote every minute. **[CONFIRMED FROM CODE]**

**Is it reversible?** Effectively no. A2's `InpTestNonM1` section sends M5 rates to a custom symbol
and records the outcome with `SSR_Verdict("nonM1_behaviour_documented", true, "recorded", ...)` —
it asserts nothing, by design. **[CONFIRMED FROM CODE]** So the project has no measured position on
what MetaTrader does when given non-M1 rates, and the fallback plan is unwritten.

**Verdict.** [RECOMMENDATION] **The bet is correct and must stand.** It is the only choice that
keeps the trader's own chart, and the only alternative — drawing the market as chart objects —
is an order of magnitude over the measured paint budget in a language with no clipping. Do not
revisit it. But it is currently a *belief* rather than a *measurement* in the one mode that ships,
and it has silently acquired a second implementation. Three obligations follow, and none of them
is a redesign:

- **B15-O1.** Repair B1 before trusting the tick path: force `SYMBOL_CHART_MODE = BID`, set
  `TICK_FLAG_LAST`, and give `wick_expanded_to_extremes` a tolerance the model can meet (or fix
  `SSR_BarToTicks` to hit the extremes, which also fixes the engine's synthesizer). Then run A2 and
  B1 on a real terminal and record the numbers. **[RECOMMENDATION]**
- **B15-O2.** Declare one canonical derivation. Either `CSSRMarketView` reads its higher
  timeframes from the terminal's own series on the replay symbol (which makes strategy and human
  agree by construction and deletes `Group()`), or `Group()` stays and the product states that a
  strategy's H1 is its own aggregation and may differ at the edges. Both are defensible; having
  neither written down is not. **[RECOMMENDATION]**
- **B15-O3.** Fix the warmup unit before adding any feature that depends on higher-timeframe
  context. One name, `warmup_bars`, must mean one thing. **[RECOMMENDATION]**

---

### B.16 What is missing — absent, rather than defective

These are not findings. Nothing here is broken; it does not exist. **[CONFIRMED FROM CODE]** in
each case that the surface is declared and unimplemented, or implied and absent.

1. **A second `CSSRReplayPort`.** The header names an "Ipc" port; the tree has one implementation.
   The Service/indicator split the host's own opening comment describes is therefore still a plan.
2. **Two of four declared data modes.** `ENUM_SSR_DATA_MODE` declares `MEMORY`, `BROKER`, `CSV`,
   `EXTERNAL_TICK`; only the first two have a source. Section K owns this.
3. **Persistence for the prop evaluation.** No `SaveInto`/`RestoreFrom` exists on
   `CSSRPropEvaluation` at all.
4. **A diagnostic channel to the user.** Every data-quality number is measured and discarded
   (`data-11`); the leak guard's advice is written far longer than the ~49 characters its only
   consumer can draw (`chart-7`, LOW); resume warnings are newline-joined into a single 63-character
   label (`ui-port-session-8`, MEDIUM). The product measures itself well and can tell the user
   almost none of it.
5. **A layout system.** `SSR_Layout.mqh` exists and is dead (`ui-plumbing-5`), so the RTL plan for a
   Persian-localised product has no backing.
6. **Any subscriber to `CSSRChartObserver`.** Five events, no listener in production (`chart-10`).
7. **A test runner.** Fifteen test scripts, each re-declaring its own `Check`/`CheckEq`/`Section`
   harness by copy; no aggregation, no exit code, no machine-readable verdict. `tools/ssr_compile.sh`
   compiles all 39 programs, which says nothing about assertions.
8. **Coverage for a whole tier of classes.** No test in the tree asserts anything about
   `CSSRPropEvaluation`, `CSSRShotBook`, `CSSRFlightRecorder`, `CSSRCalendarLines`,
   `CSSRTradeLines`, `CSSRChartManager`, `CSSRSetupPanel`, `CSSRKeyCard`, `CSSRRevealCard`,
   `CSSRReviewCard`, `CSSRFirstRun`, the string loader, or the 63-character draw limit. There is no
   multi-symbol (`CSSRReplayGroup`) coverage in T1–T8 at all.
9. **A range-aware tick question at session load.** `CSSRMt5TickProvider::HasTicks(symbol, from, to)`
   is written, correct, and has no caller.

Items 1, 2, 5 and 7 are the four that later sections spend real money on, and all four are
**[FUTURE FEATURE]** rather than repair: the IPC split (Section N onward), the import pipeline
(Section K), an RTL-capable layout (Sections L and M), and a test runner. Items 3, 4, 6, 8 and 9
are cheap and should be closed before any of them, because each one is a gap in the product's
ability to tell the truth about itself. **[RECOMMENDATION]**

---

### B.17 Where the 227 non-refuted findings land, and what that says

Measured over `verified.json`, excluding the 21 `NOT_A_BUG` ids. **[CONFIRMED FROM CODE]**

| Location | Total | CRIT | HIGH | MED | LOW | IMP | per kLOC |
|---|---:|---:|---:|---:|---:|---:|---:|
| `Scripts/`, `Services/`, `Indicators/`, `tools/` | 71 | 0 | 0 | 21 | 43 | 7 | — |
| `Ui` | 44 | 0 | 2 | 13 | 23 | 6 | 4.3 |
| `Trading` | 24 | 1 | 2 | 7 | 12 | 2 | 5.0 |
| `Core` | 17 | 0 | 5 | 3 | 7 | 2 | 3.4 |
| Expert host | 15 | 1 | 0 | 6 | 8 | 0 | 4.6 |
| `Chart` | 13 | 0 | 0 | 5 | 8 | 0 | 6.9 |
| `Data` | 10 | 0 | 2 | 1 | 6 | 1 | 4.3 |
| `Mt5` | 8 | 0 | 1 | 5 | 2 | 0 | 5.5 |
| `Strategy` | 7 | 0 | 1 | 1 | 5 | 0 | 6.0 |
| `Common` | 5 | 0 | 0 | 1 | 3 | 1 | 3.0 |
| `Session` | 4 | 0 | 1 | 1 | 2 | 0 | 9.6 |
| `Integration` | 3 | 0 | 0 | 0 | 2 | 1 | 3.3 |
| `Report` | 3 | 0 | 0 | 2 | 1 | 0 | 3.6 |
| `Spike` (kit) | 3 | 0 | 1 | 1 | 1 | 0 | 4.7 |

Three readings, in order of importance.

1. **Density is flat; severity is not.** Every production layer sits between 3.0 and 6.9 findings
   per thousand lines — a remarkably even distribution that says the same author applied the same
   care everywhere. **[INFERENCE]** What is *not* even is severity: `Core` holds 5 of the 14 `HIGH`
   findings in 5,051 lines, and `Trading` plus the host hold both `CRITICAL`s. The dangerous code
   is where the state machines are, exactly as one would expect, and it is a small, well-bounded
   set of functions: `EmitWindow`, `JumpForward`, `StepBars`, `OnRewind`, the group's gap skip, and
   `OnInit`'s sweep.
2. **The verification layer is the largest defect cluster in the repository, and its defects are of
   a special kind.** 71 of 227 findings, and *zero* of them `CRITICAL` or `HIGH` — because a broken
   test cannot hurt a user. **[CONFIRMED FROM CODE]** At least 20 are assertions that cannot fail:
   `Check(..., true)` with no condition (`tests-a-11`), a PASS criterion *printed* instead of
   asserted (`spikes-audits-12`, `spikes-audits-13`), a tautology (`tests-a-14`, `tests-b-3`,
   `tests-b-14`, `spikes-audits-15`), a test that re-implements the production expression it is
   checking (`qa-smoke-8`), a verdict that cannot pass (`tests-a-1`), one that cannot fail
   (`tests-b-4`), a race test run sequentially in one thread (`spikes-audits-14`), and a pass count
   incremented with nothing tested (`qa-smoke-7`). A further group fails for a different reason —
   asserting against constants the product moved past: four sections of T5 and two of T15 assert an
   8-stop speed ladder and `R` bound to reset, against a 20-stop ladder and `R` bound to the
   planning lines (`tests-a-2`, `-3`, `-4`, `tests-b-1`, `tests-b-2`, `ui-plumbing-2`, `-3`).
   **[CONFIRMED FROM CODE]**
3. **Combined with "the author has never run this on a terminal", 2 reframes everything else.**
   **[INFERENCE]** The 197 `CONFIRMED` findings are confirmed *from source*, which is the strongest
   evidence available in this environment and genuinely strong. But the project's own instruments —
   15 test scripts, 5 QA scripts, 17 spikes, 21 static audits — are the only things that could
   convert source-level confidence into terminal-level confidence, and a measurable share of them
   report success unconditionally. The audits are the healthiest of the four
   (`tools/ssr_audit.py` carries its own written rules: "an audit that has never been seen to fire
   is not evidence", "an audit that cries wolf is worse than none", and explicit vacuous-pass
   guards in A18 and A19) — and even there, A19's language-file check never runs because the path
   contains `MQL5` twice (`spikes-audits-26`, LOW), and A14 and A20 have no vacuous-pass guard at
   all. **[CONFIRMED FROM CODE]**

[RECOMMENDATION] Before any feature in Sections M–S is built, the verification layer is the
cheapest high-value repair available: a shared harness, a machine-readable verdict, and a pass over
the 20 assertions that cannot fail. It costs nothing architecturally and it is the only thing that
turns this audit's 197 confirmations into evidence about a running terminal.

---

### B.18 WHAT MUST REMAIN UNCHANGED

This is the itemised list. Each item is an architectural invariant — a decision whose violation
re-creates a defect this project has already paid for, or removes the reason the product is
repairable. Section F.2 holds the finer-grained engine list, L.10 the UI list, K.15 the data-import
list; this list is the layer-spanning one and does not repeat them.

**Structure and dependency direction**

1. **`Core` depends on `Common` only.** The replay engine must never include `Data`, `Mt5`,
   `Chart`, `Ui`, `Trading` or `Session`. It is what makes the engine testable with
   `CSSRMemoryDataSource` and `CSSRRecordingSink`, and what would let it move into a Service
   without touching a line. **[CONFIRMED FROM CODE: the edge matrix in B.1 shows `Core → Common 34`
   and nothing else.]**
2. **The five contracts stay in `Core`**: `CSSRHistoryProvider`, `CSSRBarProvider`,
   `CSSRTickProvider`, `CSSRReplaySink`, `CSSRTickObserver`. A new data source or a new sink is a
   new implementation, never a new dependency in `Core`. **[CONFIRMED FROM CODE]**
3. **`Common` contains no MetaTrader API call except in `SSR_Platform.mqh`.** That file is the one
   place terminal facts are read, which is why `SSRCanBlock()` can gate every retry loop in the
   product. **[CONFIRMED FROM CODE]**
4. **`SSR_SymbolNaming.mqh` stays in `Common`.** It is there specifically so `Chart` can recognise a
   replay symbol without depending on `Mt5`, and `SSRIsReplaySymbol` is the pass-1/pass-2
   discriminator, the leak guard's filter and the duplicate-slot scan's test.
   **[CONFIRMED FROM CODE]**
5. **`Trading → Report` is intentional and must not be "fixed".** `SSR_ReportStyle.mqh` is a leaf
   that knows nothing about trades and is shared by the statement and the class report; moving it
   into `Trading` would put HTML in the trading layer. **[CONFIRMED FROM CODE / RECOMMENDATION]**

**The engine's contracts with the world**

6. **M1 is the only base timeframe, and the only two write APIs are `CustomRatesUpdate` and
   `CustomTicksAdd`.** See B.15. Higher timeframes are derived, never written.
   **[CONFIRMED FROM CODE]**
7. **Warmup goes in as bars; the replay stretch goes in as ticks; truncation is deletion at one
   M1-aligned instant in both stores, and `TruncateFrom`'s *return* is the truth.**
   **[CONFIRMED FROM CODE]**
8. **`SYMBOL_CHART_MODE = BID`, read back — and `TICK_FLAG_LAST` on every synthetic tick. Keep
   both.** The belt and the braces fixed one measured failure together; neither has been shown to
   be sufficient alone. **[CONFIRMED FROM CODE]**
9. **24/7 quote and trade sessions, verified by read-back rather than by return value.**
   **[CONFIRMED FROM CODE]**
10. **One wall-clock-driven clock (the group's master). Streams are told an instant, never a
    delta.** `ctrl.Pump(wall_ms)` must stay unused in production. This is why `MaxSkewMsc()` is zero
    by construction. **[CONFIRMED FROM CODE]**
11. **Integer speed arithmetic with a residue carry.** No floating-point time anywhere.
    **[CONFIRMED FROM CODE]**
12. **Time is `long` epoch milliseconds in every layer; `datetime` appears only at API and human
    boundaries, and `SSR_Time.mqh` is the only seam.** **[CONFIRMED FROM CODE]**
13. **The future guard has two layers**: the controller clamps before asking, every provider
    re-checks on the way out. Do not collapse them into one. **[CONFIRMED FROM CODE]**
14. **`NextBarOpen` reads timestamps only and is deliberately unguarded.** A schedule is not a
    price. Do not "unify" it with the guarded reads, and do not unify the base class's
    millisecond spans with the MT5 provider's second spans — both are correct in their own
    context. **[CONFIRMED FROM CODE]**
15. **Zero bars is data, not failure.** `CSSRBarWindow` caches an empty range; `ReadBars` returns 0
    rather than −1 for `SSR_ERR_NO_DATA`. Only `LOAD_FAILED`/`INTERNAL` are errors.
    **[CONFIRMED FROM CODE]**
16. **The seed cache never trusts its manifest alone**; terminal `SERIES_*` evidence must agree.
    Keep the asymmetry (a false negative costs a reseed; a false positive shows the future).
    **[CONFIRMED FROM CODE]**
17. **The observer registration order** — account first, market view before the strategy host — and
    the rule that observers see an account that has already priced the tick. **[CONFIRMED FROM CODE]**

**Trading and safety**

18. **No `OrderSend`, `CTrade`, `PositionClose` or any order API, in any layer, ever.** The
    guarantee is structural today and must stay structural: the account is a log in memory, and the
    replay symbol's `SYMBOL_TRADE_MODE` is forced to `DISABLED` at creation.
    **[CONFIRMED FROM CODE]**
19. **The log is the account.** `balance == initial + Σ(profit + swap − commission)` over the log,
    recomputed by `RestoreFrom` and checked by `balance_check`. Any new money movement must be
    reversible from the log. **[CONFIRMED FROM CODE]**
20. **One sizing formula.** The preview and the order must call the same `LotForRisk` on the same
    fill price. No second formula in the port, the panel or a strategy.
    **[CONFIRMED FROM CODE]**
21. **The equity curve is the only derived statistic that is persisted**, because it is the only one
    that cannot be recomputed. Do not start storing computed statistics in the session file.
    **[CONFIRMED FROM CODE]**
22. **Strategy identity is the position tag.** Per-strategy statistics, `MyOpenCount`,
    `MyPosition` and `CloseAllMine` all rest on it; client trades are tagged `"external"`.
    **[CONFIRMED FROM CODE]**

**The UI/engine seam**

23. **`CSSRReplayPort` + `SSRUiState` stay as they are**: a flat, pointer-free wire of 89 fields,
    verbs that default to refusal, no engine internals, and the clock text already masked by the
    time the panel sees it. This is the seam that makes an IPC split a wiring change.
    **[CONFIRMED FROM CODE]**
24. **Every `prop_*` fraction on the wire is pre-clamped and computed by one owner**, so a meter
    cannot disagree with the verdict; and `0` means "the rule does not exist", not "no room left".
    **[CONFIRMED FROM CODE]**
25. **Latch polling is the click mechanism.** Clear the latch before acting; never write
    `OBJPROP_STATE` from a draw; poll the palette first and alone; debounce per name. It is the one
    input design that behaves identically whether or not the EA is attached to the chart being
    drawn on. **[CONFIRMED FROM CODE]**
26. **`CSSRWidgets` is the only caller of `ObjectCreate`/`ObjectSet*` for panel chrome**, creation
    order is the only z-order, and the cache's early return requires both "unchanged" and "still
    there". **[CONFIRMED FROM CODE]**
27. **`SSR_Theme.mqh` is the only file that may contain a colour**, all palettes define the same
    token set, and audit A17 enforces it. **[CONFIRMED FROM CODE]**
28. **Strings are matched by name, not by enum index**, and the language file is read as raw bytes
    and converted with `CP_UTF8` — never through `FILE_TXT|FILE_ANSI`. **[CONFIRMED FROM CODE]**
29. **"Removed, not merely undrawn."** The panel repaints from state and never clears the chart, so
    a surface the state no longer has must be deleted. **[CONFIRMED FROM CODE]**
30. **The two compile-time switches stay**: `SSR_LAYOUT_RAIL` (310 px rail vs 420 px fallback) and
    the three-palette switch. One commented line must be able to undo a large visual change on a
    terminal the author cannot run. **[CONFIRMED FROM CODE]**

**Session, integration and diagnostics**

31. **Session restore order: streams first, account after, then statistics, then
    `NotifyRestored`** — and the master follows the streams, never the file.
    **[CONFIRMED FROM CODE]**
32. **No price data in the session file.** Bars are re-read and the fingerprint *reports* a change;
    it never blocks a resume. Keep the integer-scaled digest and the signed-long packing.
    **[CONFIRMED FROM CODE]**
33. **Packed rows append, never insert**, so the format number does not need bumping for a new
    field. **[CONFIRMED FROM CODE]**
34. **The wire numbers in `SSR_Contract.mqh` are frozen**, the mapping is written as switches rather
    than casts, `SSR_Contract.mqh` includes nothing, and a heartbeat — not a flag — decides whether
    a session is alive. **[CONFIRMED FROM CODE]**
35. **Nothing forward-looking is ever published to a client.** No verb that reads data at a time;
    `end_msc` is the only forward datum. **[CONFIRMED FROM CODE]**
36. **The flight recorder flushes every line**, and `PrintVitals` and `RecordFlight` render the same
    facts two ways. On a platform with no debugger, this is the product's only black box.
    **[CONFIRMED FROM CODE]**
37. **`CloseOwned` never closes `ChartID()`.** A program dies mid-statement when its own chart
    closes, and the orphaned custom symbol then breaks the next session.
    **[CONFIRMED FROM CODE]**
38. **Teardown order: charts → Market Watch → `CustomSymbolDelete`.** The terminal refuses
    otherwise. **[CONFIRMED FROM CODE]**
39. **No symbol-name parsing, anywhere.** Sessions come from `SymbolInfoSessionQuote`, currencies
    from `SYMBOL_CURRENCY_BASE/PROFIT`, precision from the symbol. **[CONFIRMED FROM CODE]**
40. **`SSRPickSeed()` is the only wall-clock read in the determinism path**, and it exists to be
    printed back at the user. Everything downstream is a pure function of the seed.
    **[CONFIRMED FROM CODE]**

Two things that read as odd and are right, recorded here so nobody "tidies" them: `Restart()` is
`Reset()` and keeps bookmarks while dropping checkpoints — restarting is still the same session;
and **fidelity is per stream, not per group** — forcing `FULL_TICK` across a board would claim a
fidelity that does not exist on every instrument in it. **[CONFIRMED FROM CODE]**

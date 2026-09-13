## K. DATA IMPORT ARCHITECTURE

External historical data — Data Source Manager, Import, Validation, Normalization,
Symbol Mapping, Timezone handling, Duplicate detection, Missing data detection,
Data quality score, Data cache, Data source indicator.

---

### K.0 Where this actually stands at v125

**There is no import.** [CONFIRMED FROM CODE] A repo-wide grep for `FileOpen` finds
seventeen files; every one of them *writes* (journal CSV export, session file,
position file, flight recorder, seed manifest, spike telemetry) or reads back
something this product itself wrote. Nothing reads a third-party price file. The
only `CSSRDataSource` implementations in the tree are `CSSRMt5DataSource`
(`MQL5/Include/SSReplay/Data/SSR_Mt5DataSource.mqh`) and `CSSRMemoryDataSource`
(`MQL5/Include/SSReplay/Core/Sources/SSR_MemoryDataSource.mqh`).

**But the seam is already cut, and cut correctly.** [CONFIRMED FROM CODE]
`SSR_IDataSource.mqh:6-7` states the intent in the file header:

```
//|  The seam between the engine and wherever the bytes come from.   |
//|  Phase 2 implements these against MT5 broker history; Phase 6    |
//|  adds CSV and external tick datasets. The engine never changes.  |
```

and `SSR_Types.mqh:105-111` already carries the vocabulary:

```
enum ENUM_SSR_DATA_MODE
  {
   SSR_DATA_MEMORY = 0,    // in-memory dataset (tests, generators)
   SSR_DATA_BROKER,        // MT5 broker history          - Phase 2
   SSR_DATA_CSV,           // imported CSV bars or ticks  - Phase 6
   SSR_DATA_EXTERNAL_TICK  // external tick dataset       - Phase 6
  };
```

Two of those four enumerators have no implementation behind them. That is the
whole of Section K's subject matter. [CONFIRMED FROM CODE]

**What the seam buys.** [CONFIRMED FROM CODE] `CSSRDataSource`
(`SSR_IDataSource.mqh:192-254`) is a pure interface over three providers —
`CSSRHistoryProvider` (Discover / Ensure / ExtendBackwards),
`CSSRBarProvider` (ReadBars / ReadBarAt / NextBarOpen / BarCount) and
`CSSRTickProvider` (HasTicks / ReadTicks) — all of them descended from
`CSSRProviderBase`, which owns nothing but the future guard and an error pair
(`SSR_IDataSource.mqh:60-97`). Composition rather than multiple inheritance is
explained at `SSR_IDataSource.mqh:9-14`, and the reason given is exactly the
import case: *"a CSV of daily bars genuinely has no tick provider, and the engine
must be able to ask rather than guess."* An import source is therefore a new
`CSSRDataSource` subclass and **zero engine change**. Preserve that. [RECOMMENDATION]

**What the seam does not buy.** [INFERENCE] `CSSRProviderBase` gives a new source
the guard and the error channel and nothing else. Everything in K.3 through K.10 —
validation, normalization, quality scoring — lives in `Data/`, not in the base
class, and is today written against MetaTrader's return shapes. It is reusable but
not yet reused; K.4 says how.

---

### K.1 Data Source Manager

**Today.** [CONFIRMED FROM CODE] There is no manager. The host instantiates one
concrete source directly: `SSReplayStandalone.mq5` holds `g_src` and the controller
is handed it. The one place that records which kind of source is running is
`CSSRReplayController::SetDataMode` (`SSR_ReplayController.mqh:693`), called from
`SSReplayStandalone.mq5:1150` (`g_ctrl.SetDataMode(SSR_DATA_BROKER)`) and
`:499` for extra streams. `CSSRDataSource::Mode()` — the source's *own* answer to
the same question, set to `SSR_DATA_BROKER` in `CSSRMt5DataSource`'s member init —
**has no caller anywhere in the repo**. [CONFIRMED FROM CODE] The mode the session
records is asserted by the host, not read from the source that is actually running.

That is harmless with one source. With three it is a liar waiting to happen.
[INFERENCE]

**Proposed shape.** [RECOMMENDATION] A `CSSRDataSourceManager` in
`MQL5/Include/SSReplay/Data/SSR_DataSourceManager.mqh`:

- owns a small fixed array of `CSSRDataSource*` (an array, not a list — MQL5 has no
  generic container the rest of this codebase uses, and every other registry here
  is a fixed slot array);
- `Register(CSSRDataSource*)`, `Count()`, `At(i)`, `Find(name)` where `name` is the
  existing `CSSRDataSource::Name()` (`"mt5-broker"`, `"mt5-custom-symbol"` for the
  sink, and new `"csv-bars"` / `"csv-ticks"`);
- `Resolve(symbol) -> CSSRDataSource*` applying a declared precedence, not a
  guess;
- a single accessor the host and the controller both read for the mode, replacing
  the hand-asserted `SetDataMode(SSR_DATA_BROKER)` call at
  `SSReplayStandalone.mq5:1150` with `SetDataMode(src.Mode())`. [RECOMMENDATION]

**Precedence must be explicit and displayed, never inferred.** [RECOMMENDATION]
The moment a symbol can be served from two places, "which one did I just watch"
becomes the question the whole product exists to answer honestly. Suggested rule,
stated in one place and shown in the UI (K.11): *an imported dataset wins for the
range it covers; the broker serves everything outside it; a range spanning both is
refused, not stitched.* Stitching two feeds into one continuous replay creates a
price series that no venue ever printed, which is the synthetic-data problem of
K.12 in a different coat.

**Ownership.** [RECOMMENDATION] Follow `CSSRMt5DataSource`'s existing discipline:
it `new`s its three providers in the ctor and `delete`s them in the dtor *after*
`DetachGuard()` (`SSR_Mt5DataSource.mqh`), because the guard is a member of the
controller and may already be gone. Any manager must not duplicate that ownership —
it holds `CSSRDataSource*` it does not own, the way `CSSRHistoryCatalog` holds an
unowned `CSSRHistoryProvider*` and `CSSRRandomPicker` holds an unowned
`CSSRHistoryCatalog*`.

---

### K.2 Import

**What an import source must implement.** [RECOMMENDATION] Exactly the three
contracts, no more:

| Contract | CSV-bars source | External-tick source |
|---|---|---|
| `Discover(symbol, SSRDataRange&)` | first/last/count from the parsed index | same, plus `has_ticks = true` |
| `Ensure(symbol, from, to)` | true if the range is inside the file | same |
| `ExtendBackwards(symbol, bars)` | returns unchanged `first_msc` — a file cannot grow | same |
| `ReadBars` / `ReadBarAt` | from the in-memory M1 array | from ticks aggregated to M1 |
| `NextBarOpen` | **inherit the base** (`SSR_IDataSource.mqh:150-165`) | inherit |
| `HasTicks` / `ReadTicks` | `Ticks()` returns `NULL` | the real implementation |

`CSSRMemoryDataSource` is already the reference for most of this: its
`ExtendBackwards` returns the unchanged `FirstMsc()` with the comment *"an
in-memory dataset cannot grow; report the unchanged bound"*
(`SSR_MemoryDataSource.mqh:99-104`), which is precisely the CSV answer.
[CONFIRMED FROM CODE] Build the CSV source as a `CSSRMemoryStore` filled from disk
rather than as a new parallel hierarchy. [RECOMMENDATION]

**Inherit `NextBarOpen`, do not override it.** [RECOMMENDATION] `CSSRMt5BarProvider`
overrides it with a times-only `CopyTime` walk because the generic version reads
through the guarded `ReadBars` and is therefore useless inside a gap — that is
`core-sync-3` [CONFIRMED], which additionally notes it raises up to four
"future access" violations per call. A file-backed provider has the whole index in
memory; it should override `NextBarOpen` with a direct index lookup, which is both
correct and free of the guard-violation noise `core-sync-3` describes.

**The parser is the dangerous part, and MQL5 gives no help.** [CONFIRMED FROM CODE]
`FileReadString` + `StringSplit` is the whole toolkit; `SSR_SeedCache.mqh:82-88`
shows the house pattern (`Field(line,key)` returning `""` for a non-match, which
also makes an empty legitimate value indistinguishable from absence — acceptable for
a manifest, **not** acceptable for a price column). [INFERENCE] An import parser
must distinguish "field absent", "field empty" and "field zero", because a zero
price is exactly what `SSRDataReport.nonpositive` exists to catch
(`SSR_DataValidator.mqh:34`).

**Import must be an explicit, cancellable, reported operation, not a side effect of
opening a session.** [RECOMMENDATION] Two reasons from this codebase: (a)
`SSRCanBlock()` gates every retry loop in `Data/` precisely so an indicator gets one
attempt instead of a frozen terminal — an import of a million rows in `OnInit` has
no such escape; (b) `data-5` [POTENTIAL_RISK] already documents a 20-second
terminal block on a load path that spins a timeout it cannot satisfy, and the fix
pattern there (believe a definite answer instead of retrying) is the same discipline
an importer needs.

---

### K.3 Validation

**Reuse `CSSRDataValidator`. It is the right class and it is already the only
sanitiser in the product.** [CONFIRMED FROM CODE] `SSR_DataValidator.mqh` gives:

- `SSRDataReport` with `total duplicates out_of_order micro_gaps session_gaps
  largest_gap_msc invalid_ohlc nonpositive first_msc last_msc` (`:27-36`);
- `ValidateBars` — read-only inspection, assumes nothing about ordering;
- `SanitizeBars` — in-place compaction keeping strictly increasing open times;
- `SanitizeTicks` — drops only `time_msc < prev`, deliberately preserving equal
  stamps because *"two ticks MAY share a millisecond legitimately"*;
- `ValidateTicks` — **which has no caller anywhere in the repo, tests included**.

An external-tick import is the first caller `ValidateTicks` has ever had, and it
should be wired at import time, not at read time. [RECOMMENDATION]

**Three defects in the validation path must be settled before it carries imported
data, because import makes all three worse.** [RECOMMENDATION]

1. **`data-2` [POTENTIAL_RISK, HIGH] — one bad bar voids the whole window.**
   `SSR_BarWindow.mqh:218`:
   ```
   if(!m_last_report.IsUsable())
     {
      Fail(SSR_ERR_NO_DATA, "range failed validation: " + m_last_report.ToString());
      Invalidate();
      return false;
     }
   ```
   `IsUsable()` is `total > 0 && invalid_ohlc == 0 && nonpositive == 0`
   (`SSR_DataValidator.mqh:54-57`), and `SanitizeBars` never inspects prices — so a
   single `high < low` bar rejects the entire 5,000–60,000-bar window, and
   `CSSRMt5BarProvider::ReadBars` converts that `SSR_ERR_NO_DATA` into
   `Succeed(); return 0;`. Broker history is occasionally dirty; **a hand-assembled
   CSV is reliably dirty**, so an import path that inherits this rule will look
   like an import that silently did nothing. [INFERENCE] The repair, consistent with
   the file's own stated intent at `SSR_BarWindow.mqh:207` (*"broker history is not
   guaranteed clean; make it replay-safe"*), is for `SanitizeBars` to **drop**
   price-invalid bars into the existing `m_dropped` counter rather than for the
   window to refuse the range. [RECOMMENDATION]

2. **`data-11` [CONFIRMED, IMPROVEMENT] — every quality number is computed and
   thrown away.** `ReportInto`, `Dropped()`, `HitRate()` and
   `CSSRMt5DataSource::ToString()` have no caller in the shipped EA or UI; the only
   live consumer of the window's `ToString()` is a test
   (`SSR_T2_DataEngine.mq5:256-258`). An import feature whose whole value
   proposition is *"tell me whether this file is any good"* cannot ship on top of a
   telemetry chain that is dead at both ends. K.9 turns this into the quality score.

3. **`ValidateTicks` is untested by use.** [CONFIRMED FROM CODE] It counts
   duplicates without condemning them and measures gaps only at or above
   `m_session_gap_msc`. Its threshold comes from `LearnFrom(symbol)`, which
   `CSSRMt5TickProvider` never calls — harmless today because only `SanitizeTicks`
   is used, and a live bug the moment `ValidateTicks` is wired. [INFERENCE]

**What must NOT change.** [RECOMMENDATION] `SanitizeBars` never sorts — the header's
reason is *"sorting would invent an ordering the feed never had"*. That rule is
more important for imports, not less: a CSV whose rows are out of order is a file
the user must be told about, not a file the tool quietly reorders into something
plausible.

---

### K.4 Normalization

Normalization is the step with no existing home, and it is where a careless
implementation manufactures fiction. [INFERENCE]

**What must be normalized, and to what.** [RECOMMENDATION] The invariants the whole
`Data/` subsystem leans on (map §12) define the target exactly:

| Invariant | Source | Import obligation |
|---|---|---|
| **M1 only** | every read in `Data/` is `PERIOD_M1` | a file of M5/H1 bars is **rejected**, not upsampled — see below |
| **time is `long` milliseconds**, `SSR_INVALID_TIME` is `-1` not `0` | `SSR_Time.mqh` | parse to msc once, at import |
| bars **strictly ascending, duplicate-free** | `SanitizeBars` guarantee | enforce at import, report what was dropped |
| ticks **ascending, equal stamps legal** | `SanitizeTicks` | same |
| prices at symbol `digits` / `point` | `SSRDigestBar` scales by `10^digits` | round once, at import |
| `spread` per bar is meaningful or absent | `CSSRTickSynthesizer::SpreadFor` treats `spread == 0` as *"the terminal did not store one"*, not as zero spread (`SSR_TickSynthesizer.mqh:44-67`) | a CSV with no spread column must import spread as **0 meaning absent**, so the existing fallback and its `m_bars_fixed` counter keep working |

**Never upsample a coarser timeframe into M1.** [RECOMMENDATION] Turning one H1 bar
into sixty M1 bars is the `CSSRTickSynthesizer` problem multiplied by sixty, and
the synthesizer is scrupulous about declaring its assumption
(`SSR_TickSynthesizer.mqh:7-15`: *"THE PATH MODEL IS AN ASSUMPTION, AND IT IS
DECLARED … the OHLC of the resulting bar is exact — only the ORDER inside the
minute is invented"*). Upsampling has no such guarantee: it invents the OHLC too.
If coarse-timeframe import is ever wanted, it is a separate, separately labelled
data mode, and every bar it produces must be provenance-marked under K.12.
[FUTURE FEATURE]

**Downsampling ticks to M1 is legitimate and already has a template.**
[RECOMMENDATION] An external-tick source aggregating its own ticks to M1 for
`ReadBars` produces exact OHLC from real prints; that is arithmetic, not
invention. The one trap is the bar-close convention: `CSSRMemoryStore::LastMsc()`
returns `SSRToMsc(bars[n-1].time) + SSR_MSC_PER_MIN - 1` with the comment
*"the last instant COVERED by the data, i.e. the close of the final bar, not its
open. Getting this wrong shortens every replay window by one bar"*
(`SSR_MemoryDataSource.mqh:42-51`). Copy that, exactly.

**Volume.** [INFERENCE] `SSRDigestBar` folds only time and O/H/L/C
(`SSR_Fingerprint.mqh:98-115`) — *"Volume and spread are not folded in."* So a
normalization pass that invents or rescales volume will not be caught by the
resume fingerprint. Volume should be imported verbatim or imported as zero, never
derived.

---

### K.5 Symbol Mapping

**The existing naming layer is the right foundation and needs one extension.**
[CONFIRMED FROM CODE] `Common/SSR_SymbolNaming.mqh` is pure string logic, no MT5
API, by design (`:10-12`). It gives:

- `SSR_SYMBOL_SUFFIX ".SSR"`, `SSR_SYMBOL_NAME_MAX 31`, `SSR_SYMBOL_PATH "SSReplay"`;
- `SSRReplaySymbolName(origin, slot)` — `"US30Cash"` slot 1 → `"US30Cash.SSR1"`,
  and *"a very long origin loses its TAIL, not the suffix, so the result is always
  recognisable as a replay symbol"* (`:29-46`);
- `SSRAnonSymbolName(slot)` → `"Chart.SSR1"` for Blind Mode, which still ends in the
  suffix so *"cleanup and the leak guard recognise it exactly as before. Anonymous
  to the trader, not to the tool"* (`:48-63`);
- `SSRIsReplaySymbol(name)` — used by cleanup and the leak guard.

**The mapping problem import introduces.** [INFERENCE] An imported file says
`EURUSD`; the broker calls it `EURUSD.pro`; the money properties
(`SYMBOL_TRADE_TICK_SIZE`, `TICK_VALUE`, `CONTRACT_SIZE`, `VOLUME_MIN/MAX/STEP`)
come from the broker symbol via `CSSRCustomSymbolManager::CloneMoneyProperties`
(`SSR_CustomSymbolManager.mqh:271-290`), whose header warns that *"every money
figure in this product divides a price distance by TICK SIZE and multiplies by
TICK VALUE — never by point. A replay symbol carrying the wrong tick size reports
the wrong profit on every trade taken on it, quietly."* So an import needs a
**mapping from file-symbol to broker-symbol**, and a mapping that resolves to
nothing must refuse the import rather than default. [RECOMMENDATION]

**Do not parse instrument identity out of names.** [RECOMMENDATION] Map §12
invariant 9 is categorical: *"Symbol rules never live in this code. Session breaks
come from `SymbolInfoSessionQuote`, currencies from `SYMBOL_CURRENCY_BASE/PROFIT`
… No name parsing anywhere."* `CSSRCalendar::Load` honours it by reading
`SYMBOL_CURRENCY_BASE/PROFIT` rather than slicing `"EURUSD"` in half. A mapping
table is a *user-supplied or explicitly-confirmed* association, never a string
heuristic. Fuzzy-matching `EURUSD` to `EURUSD.pro` is a convenience that becomes
a wrong-tick-size trade report the first time it matches `EURUSDm` instead.

**Proposed carrier.** [RECOMMENDATION] Extend the naming module with a mapping
suffix, e.g. an imported dataset for origin `EURUSD` in slot 1 producing
`"EURUSD.SSRI1"` — still matched by `SSRIsReplaySymbol` (which tests only for
`".SSR"` as a substring, `:74-77`), still inside `SSR_SYMBOL_NAME_MAX`, and
**visibly different in MetaTrader's own chart caption from a broker-backed replay**.
That last property is the cheapest provenance display in the product (K.11), because
MetaTrader prints the symbol name whether or not the panel is open.

**One existing hazard to check before reusing the adopt path.** [CONFIRMED]
`mt5-symbol-3` — `Create()`'s leftover-adopt fallback uses a `SYMBOL_DIGITS > 0`
existence test that `Adopt()` itself documents as wrong for whole-point instruments;
`mt5-symbol-2` [POTENTIAL_RISK] — `Adopt()` does not force
`SYMBOL_CHART_MODE_BID`, so an adopted LAST-mode symbol builds no candles from the
engine's ticks. Import adds *more* symbols in the `SSReplay` group for adopt to trip
over, so both should be settled first.

---

### K.6 Timezone handling

**What exists.** [CONFIRMED FROM CODE] Almost nothing, and deliberately so.

- Every clock in this tool is **server time**. `SSR_Statistics.mqh:687`:
  *"Server time, like every other clock in this tool"*; the journal's chart caption
  says the same (`SSR_Journal.mqh:998`). `CSSRSessionWatcher`'s `SSR_SESSION_BY_DAY`
  is *"a calendar day boundary in server time"* (`SSR_SessionWatcher.mqh:34`),
  because bar stamps are server seconds.
- The **only** timezone control in the product is `InpNewsShift` →
  `CSSRCalendar::SetShiftMinutes` → `m_shift_msc`, applied to calendar *item stamps
  only*, never to the query window, which is widened by ±1 day so any shift under
  24 h is absorbed (`SSR_Calendar.mqh:105`, `:200-265`). Its own header
  (`:24`) says the terminal reports the calendar *"in ITS timezone, which is not
  guaranteed to be the same clock"*, echoed at `SSReplayStandalone.mq5:151`.
- `SSRPickSeed()` is described as *"the ONE place a wall clock may be read"*
  (`Common/SSR_Random.mqh`), and it reads a clock only to print a number back.

**The import consequence.** [INFERENCE] A downloaded dataset is typically stamped
UTC or exchange-local; the broker's M1 is stamped broker-server. Importing without
a declared offset shifts every bar relative to every other clock in the product —
the session watcher's day boundary, the calendar lines, the journal's time buckets,
`SSRSymbolSessionGap`'s weekly projection. A one-hour DST error moves the London
open by one candle and nothing in the product will say so.

**Proposed handling.** [RECOMMENDATION]

1. **One offset, declared at import, stored with the dataset, never re-derived.**
   The `CSSRCalendar` precedent is the right shape: a single
   `SetShiftMinutes(int)` applied once, at a single point, rather than a timezone
   engine. MQL5 has no tz database; anything more ambitious than a fixed offset is
   guesswork wearing a library's clothes.
2. **Refuse to infer it.** A DST-aware import would need the dataset's rule *and*
   the broker's, and the broker's is not queryable. State the offset, show it, and
   let the user correct it — exactly what `InpNewsShift` does.
3. **Carry it in the provenance record (K.12)** so a session replayed from an
   imported file reports the offset it was normalized with, and a fingerprint
   mismatch on resume can distinguish "the data changed" from "the offset changed".
   Note that `SSRFingerprint` folds `bar.time` (`SSR_Fingerprint.mqh:98-115`), so an
   offset change *will* be detected — it will just be reported as
   *"the prices in them changed — the broker revised this history"*, which is the
   wrong diagnosis. [INFERENCE]
4. Warn that a wrong offset also breaks the *warmup* arithmetic already known to be
   fragile: `core-engine-6` [CONFIRMED, MEDIUM] shows warmup "bars" are treated as
   calendar minutes so a Monday-morning start seeds almost no warmup, and `data-4`
   [CONFIRMED, MEDIUM] shows `warmup_bars` is read both as a bar count and as a span
   of wall-clock minutes.

---

### K.7 Duplicate detection

**Already solved for bars, half-solved for ticks, and the asymmetry is correct.**
[CONFIRMED FROM CODE]

- `SSRDataReport.duplicates` — *"same open time seen twice"* (`SSR_DataValidator.mqh:28`).
- `SanitizeBars` compacts in place keeping **strictly increasing** open times, so a
  duplicate bar is dropped and counted into `CSSRBarWindow::m_dropped`.
- `SanitizeTicks` drops only `time_msc < prev` and **keeps equal stamps**, because
  two ticks may legitimately share a millisecond (`:284-288`).
- `IsUsable()` deliberately tolerates duplicates: `duplicates` and `out_of_order` do
  **not** make a range unusable; only `invalid_ohlc` and `nonpositive` do
  (`:54-57`).

**What import must add.** [RECOMMENDATION]

1. **Report duplicates, do not merely absorb them.** A duplicated bar in broker
   history is a terminal artefact; a duplicated bar in a user's CSV usually means
   two files were concatenated, and the user needs to know that before they trade
   three hundred sessions on it. The counter already exists and is already
   populated — it just never reaches a human (`data-11` [CONFIRMED]).
2. **Distinguish "same stamp, same prices" from "same stamp, different prices".**
   `SSRDataReport` does not currently separate them, and only the second is a
   contradiction in the file. A fold of the existing `SSRDigestBar`
   (`SSR_Fingerprint.mqh:98-115`) over the two candidates answers it exactly, using
   the same integer-scaled comparison the fingerprint uses to avoid double-bit
   sensitivity. [RECOMMENDATION]
3. **Do not extend the bar rule to ticks.** The equal-millisecond case is real, and
   `data-12` [POTENTIAL_RISK] documents the cost of getting the boundary wrong in
   the other direction: `ReadTicks` resumes a truncated page at `last+1` ms, so
   ticks sharing the truncation-boundary millisecond are dropped. A tick importer
   that de-duplicates by timestamp alone would reproduce that loss on every burst.

---

### K.8 Missing data detection

**The distinction this codebase already draws is the one that matters.**
[CONFIRMED FROM CODE] `SSRDataReport` splits gaps in two:

```
   int               micro_gaps;      // missing minutes, below the session threshold
   int               session_gaps;    // gaps long enough to be a market closure
   long              largest_gap_msc;
```

and `IsClean()` explicitly excludes `session_gaps` — *"session gaps are expected, so
they do not make data dirty"* (`:47-52`). The threshold is not hardcoded: it comes
from `SSRSymbolSessionGap(symbol)` (`:79-127`), the **widest** silence in the
week, computed by walking `SymbolInfoSessionQuote` over seven days × eight session
indices and projecting them onto one weekly timeline; `CSSRDataValidator::LearnFrom`
installs it, and `CSSRBarWindow` calls `LearnFrom` on every symbol change.
Its sibling `SSRSymbolSessionBreak` (`:143-185`) returns the **narrowest** positive
break and feeds `CSSRSessionWatcher`.

**This is the single most reusable piece of machinery in the subsystem for import,
and it is currently unreachable for imported data.** [INFERENCE] The threshold is
learned from the *broker symbol*, which is exactly right: the question "is this
silence a closure or a hole" is a property of the instrument, not of the file. So
an import validator should call `LearnFrom(mapped_broker_symbol)` — which makes the
symbol mapping of K.5 a hard prerequisite for missing-data detection, not an
independent feature.

**Two additions import needs.** [RECOMMENDATION]

1. **Where, not just how many.** `micro_gaps` is a count and `largest_gap_msc` a
   duration; neither says *when*. For import, the first N gap locations (bounded the
   way `CSSRCalendar` bounds itself at `SSR_CAL_MAX 300` so *"a five-year window
   cannot try to draw twenty thousand vertical lines"*) are what let a user decide
   whether the hole is in the week they care about.
2. **Coverage, expressed against the instrument's own schedule.** "97% of expected
   minutes present" is only meaningful if "expected" comes from
   `SymbolInfoSessionQuote`, not from a 24×7 assumption. That is precisely the
   conflation `data-4` [CONFIRMED, MEDIUM] identifies in `CSSRHistoryCatalog`:
   `warmup_bars` is compared against `SERIES_BARS_COUNT` (bars that exist) in
   `Quote()` while `EarliestStart`/`LatestStart` multiply the same number by
   `SSR_MSC_PER_MIN` (minutes elapsed), and *"those are only equal for an instrument
   that quotes every minute of every day."* A coverage metric built the same way
   would report a healthy stock CFD as 27% complete. Do not repeat it.

---

### K.9 Data quality score

**The measurements already exist. The score does not, and neither does any route to
a human.** [CONFIRMED]

`data-11` [CONFIRMED, IMPROVEMENT] is the finding this feature turns into value:
every number — `duplicates`, `out_of_order`, `micro_gaps`, `session_gaps`,
`largest_gap_msc`, `invalid_ohlc`, `nonpositive`, `CSSRBarWindow::m_dropped`,
`Hits/Misses/HitRate`, `CSSRMt5TickProvider::Pages/TicksRead/ReadTimeMs` — is
computed on the hot path and discarded. Its verifier correction narrows the claim
usefully: the window's own `ToString()` *is* reached by `SSR_T2_DataEngine.mq5:256-258`;
what is unreachable is `CSSRMt5DataSource::ToString` and **every host-side route**,
so a live user's gappy range produces no diagnostic line at all.

**Proposed score.** [RECOMMENDATION] An `SSRDataQuality` struct next to
`SSRDataReport`, computed once per imported dataset (not per read), carrying:

| Component | Source, already present |
|---|---|
| completeness | expected-vs-present minutes against `SSRSymbolSessionGap`'s schedule |
| integrity | `invalid_ohlc + nonpositive`, the two fields `IsUsable()` already treats as fatal |
| ordering | `out_of_order`, `duplicates` |
| continuity | `micro_gaps`, `largest_gap_msc` |
| tick depth | `SSRDataRange.has_ticks` **measured over the dataset's own range**, not over a fixed recent window — see below |
| provenance | broker / imported / synthetic, from K.12 |

**Two rules for the score itself.** [RECOMMENDATION]

1. **A score is a summary, never a gate.** `SSRValidateRange`
   (`SSR_SessionRange.mqh:69-99`) already models this well: it returns `""` for
   servable, a reason otherwise, and its last clause is a *warning* about the
   terminal's Max-bars setting that `CSSRRangeDialog::CanStart()` accepts by
   prefix-matching `"warning"` (`SSR_RangeDialog.mqh:140-143`). Import should refuse
   on the two conditions `IsUsable()` already treats as fatal and *warn, with
   numbers* on everything else.
2. **Never compress the fatal into the average.** A dataset that is 99% complete
   with three zero-price bars is not "99%". `IsUsable()` already encodes that
   judgement (`total > 0 && invalid_ohlc == 0 && nonpositive == 0`) and the score
   must not soften it.

**Surface it in three places, all of which already exist.** [RECOMMENDATION]
`CSSRFlightRecorder::Preamble` (`SSR_FlightRecorder.mqh:165-168`) already takes
`origin, replay_symbol, window_bars, one_chart, reused_seed, picked_msc` — the
natural home for a quality line; the session file's `[stream]` section
(`SSR_ReplayController.mqh:1706-1737`), which already persists `data_mode` and the
`fingerprint`; and the panel chip row (K.11). Spike `SSR_B4_BrokerDataAudit.mq5` is
the existing precedent for the *report* form — it emits
`m1_bars_local`, `m1_first_local_days_ago`, `m1_downloadable_more`,
`tick_history_depth` per symbol, and its header states the decision rule outright:
*"If tick history is near zero for US30Cash, F1 is fiction and CSV import moves
forward in the roadmap"* (`:8-9`). B4 is the measurement Section K's whole existence
is contingent on. [CONFIRMED FROM CODE]

---

### K.10 Data cache

**`CSSRSeedCache` is a manifest cache, not a data cache, and that distinction is
load-bearing.** [CONFIRMED FROM CODE] Its header (`SSR_SeedCache.mqh:5-20`) draws
the line itself:

```
//    Bar Window (Phase 2)  in memory, one range, one symbol, dies
//                          with the session...
//    Seed Cache (here)     on disk, survives restarts. Stops the
//                          WARMUP from being written again.
//
//  Re-downloading is not the expensive part - MetaTrader already
//  keeps broker history on disk. The expensive part is pushing a
//  hundred thousand bars into the custom symbol...
```

It stores no prices — only `version origin replay_symbol warmup_from_msc
warmup_to_msc bar_count written_at` — and `CanReuse` verifies the claim against the
symbol's actual `SERIES_BARS_COUNT` / `SERIES_FIRSTDATE` / `SERIES_LASTBAR_DATE`
before honouring it (`:165-205`): *"A manifest is a claim; the bars are the
evidence."*

**Import changes the economics and therefore the design.** [INFERENCE] For broker
data, re-reading is cheap because MetaTrader already holds it. For an imported
file, re-parsing a multi-hundred-megabyte CSV on every session **is** the expensive
part. So an import cache is genuinely a different object: a parsed binary sidecar
keyed by (file path, file size, modification time, normalization offset), with the
same "verify before trusting" discipline.

**Three constraints inherited from what is already there.** [RECOMMENDATION]

1. **Keep the evidence rule.** `CanReuse`'s four-way agreement plus a symbol probe
   is the pattern; an import cache must re-check the source file's identity, not
   just its own manifest.
2. **Fix the version guard first.** `mt5-symbol-7` [CONFIRMED, LOW]: the manifest's
   `version` is `SSR_VERSION`, `"0.1.0"` in all 169 commits, while the stamp that
   actually moves is `SSR_BUILD` (v125) and is not in the manifest — so the guard
   *"written by another version"* has never rejected anything. An import cache
   keyed on a constant repeats a defect that is already known and already cheap to
   fix (put `SSR_BUILD` in the manifest).
3. **Cache reuse must not skip repair steps.** `mt5-symbol-1` [CONFIRMED, HIGH]:
   warmup repair after a jump is silently skipped whenever the seed was reused from
   the cache. Any new cache hit path must be audited for the same class of skip —
   a cache that bypasses validation is a cache that launders a bad import into a
   clean-looking session. [INFERENCE]

---

### K.11 Data source indicator

**Today there is none, and the field that should carry it is dead.**
[CONFIRMED FROM CODE] Three separate facts:

1. `SSRDataModeName()` (`SSR_Types.mqh:204-214`), which renders `"MEMORY"`,
   `"BROKER"`, `"CSV"`, `"EXTERNAL TICK"`, **has no caller anywhere in the repo** —
   grep returns only its own definition.
2. `SSRReplayVitals.data_mode` (`SSR_ReplayPort.mqh:54`) is declared and initialised
   to `SSR_DATA_MEMORY` (`:250`) and **is never assigned** — a repo-wide grep for
   `.data_mode` finds only the controller's own field, the position file, and that
   `Init()`. The panel reads vitals; the vitals never learn the mode.
3. `CSSRDataSource::Mode()` — the source's own answer — has no caller either; the
   host asserts the mode by hand at `SSReplayStandalone.mq5:1150`.

So the session file faithfully records `data_mode` (`SSR_ReplayController.mqh:1728`)
and the user never sees it. [CONFIRMED FROM CODE]

**The slot for it already exists, and the code says so.** [CONFIRMED FROM CODE]
`SSR_Panel.mqh:885-895` lays out the caption chip row with this comment:

```
      //--- chips, laid out left to right from a fixed start. Each one
      //--- reports the width it took, so adding a mode later moves the
      //--- next chip instead of landing on top of it.
```

The fidelity chip is placed there deliberately — *"it is a mode, not a
measurement"* (`:864-866`) — and the blind chip beside it. A data-source chip is
the same kind of thing and belongs in the same row. [RECOMMENDATION]

**Design rules for the indicator.** [RECOMMENDATION]

1. **Chip, not colour.** The panel's own rule: *"a mode carried by colour alone is
   a mode a colour-blind trader cannot read"* (`SSR_Panel.mqh:880-882`).
2. **Show what is running, not what was requested.** The status strip already does
   this for spread and fidelity: *"A tool that displays the request while emitting
   something else is the quiet dishonesty this whole product exists to avoid"*
   (`SSR_Panel.mqh:2025-2027`). The chip must read `src.Mode()`, not an input.
3. **Wire the three dead links in one change**: `SetDataMode(src.Mode())` at the
   host, `vitals.data_mode = ctrl.DataMode()` in the port, `SSRDataModeName()` in
   the chip. All three targets exist; none is called.
4. **Budget the characters.** MetaTrader draws exactly 63 chars of `OBJPROP_TEXT`;
   `"EXTERNAL TICK"` is 13 and the chip row already carries fidelity plus blind. A
   short form (`BRK` / `CSV` / `XTK` / `MEM`) matching the existing
   `SSRFidelityShort` pattern is the safe choice, with the long form in the sheet.
5. **Blind Mode must not be defeated by it.** The caption deliberately omits the
   symbol because *"a panel announcing the symbol the chart was told to conceal
   would defeat the feature it sits beside"* (`SSR_Panel.mqh:872-877`). A source
   chip naming a *file* would leak the instrument the same way; under
   `SSRAnonSymbolName`, show the mode only, never the path.

---

### K.12 Provenance: synthetic data must never be presented as real broker ticks

This is the section's hardest requirement, and the current code fails it *at the
data level* while succeeding *at the display level*. [CONFIRMED FROM CODE]

**Where synthetic data comes from today.** `CSSRTickSynthesizer` turns one M1 bar
into an intrabar path, with the assumption declared in its header
(`SSR_TickSynthesizer.mqh:7-15`) and the bar's OHLC preserved exactly. The engine
uses it whenever effective fidelity is `SSR_FIDELITY_SYNTHETIC_TICK` or
`SSR_FIDELITY_BAR`.

**The synthetic tick is byte-indistinguishable from a real one.** [CONFIRMED FROM CODE]
`SSR_TickSynthesizer.mqh:152-174` and `:199-203`:

```
         out[idx].volume      = 1;
         out[idx].volume_real = 1.0;
         out[idx].flags       = TICK_FLAG_BID | TICK_FLAG_ASK | TICK_FLAG_LAST;
```

Real broker ticks read via `COPY_TICKS_INFO` pass through `CSSRMt5TickProvider` and
into `CustomTicksAdd` unmodified. Once both are in the replay symbol's tick history,
**`MqlTick` carries no field that distinguishes them.** The `TICK_FLAG_LAST` is
there for a real and well-documented reason — without it a `CHART_MODE_LAST` symbol
builds no bars at all, and the comment records the measurement:
*"60 calls offered ticks, the terminal took 481, refused 0, and the M1 series stayed
at 139 bars"* — so it cannot simply be dropped. [CONFIRMED FROM CODE]

**Where provenance *is* carried today, and carried well.** [CONFIRMED FROM CODE]

| Carrier | Mechanism |
|---|---|
| symbol name | `.SSR<slot>` suffix; `SSRIsReplaySymbol` recognises it even under Blind Mode (`SSR_SymbolNaming.mqh:56-58`) |
| chart | trading is disabled on the replay symbol — `SYMBOL_TRADE_MODE_DISABLED` (`SSR_CustomSymbolManager.mqh:353`) |
| panel | the fidelity chip shows **effective**, with `" !"` and a `SSR_C_HOLD` colour when degraded (`SSR_Panel.mqh:889-895`) |
| policy | `CSSRFidelityPolicy` records a *reason* (`SSR_FR_NO_TICK_DATA` → *"no tick history - using synthetic ticks"*) and counts degradations; its header is explicit: *"whatever it decides is always visible. A tool that silently approximates is lying about its own output"* (`SSR_FidelityPolicy.mqh:24-25`) |
| trade record | `SSRTradeResult`'s honesty flag — *"THE HONESTY FLAG. True when this outcome rests on an assumed tick order"* (`SSR_TradeTypes.mqh:224`) — surfaced by the journal as *"23% of these outcomes rest on an assumed tick order"* (`SSR_Journal.mqh:243`) |

**That honesty flag is the pattern to generalise.** [RECOMMENDATION] It is
per-record, it travels into the report, and it is stated as a percentage rather
than a badge. Provenance for imported and synthetic data should work the same way:
carried per-bar, aggregated per-session, reported as a proportion.

**Where the chain breaks today.** [CONFIRMED]

- `data-1` [CONFIRMED, HIGH]: `has_ticks` is probed over the **last 24 hours** of
  history (`SSR_Mt5Providers.mqh:133-139`, hardcoded
  `from_msc = to_msc - 24*60*60*1000`) and then selects `FULL_TICK` for a replay
  window that may be years earlier. The panel says `FULL TICK`; `ReadTicks` returns
  0; `EmitWindow` advances the cursor with nothing emitted. The verifier correction
  makes it worse, not better: `Decide()` still falls to `SSR_FIDELITY_BAR` on bulk
  pumps, so bars *do* flow at high speed and after jumps while 1× playback emits
  nothing — an intermittent symptom on top of a false fidelity claim. The
  range-aware question already exists —
  `CSSRMt5TickProvider::HasTicks(symbol, from, to)`, `SSR_Mt5Providers.mqh:379` —
  and has no caller.
- `core-engine-4` [CONFIRMED, HIGH]: the same silence from the engine's side —
  a `FULL_TICK` window with zero broker ticks is consumed silently and tick
  availability is never re-evaluated per window.

So the product's strongest provenance guarantee — *the fidelity chip tells the
truth* — is currently defeated by a capability probe that answers for the wrong
range. **An import feature that adds a third possible origin for every tick must not
be built on top of that.** [RECOMMENDATION]

**Proposed provenance model.** [RECOMMENDATION]

1. **Three origins, named once, in `ENUM_SSR_DATA_MODE`'s existing vocabulary:**
   broker-real, imported-real, synthesized. Synthesized is orthogonal to the other
   two — an imported bar file also gets synthetic ticks — so provenance is a
   *pair* (data mode, fidelity), and the existing two chips already display exactly
   that pair once K.11 is wired.
2. **Per-window, not per-session.** The lesson of `data-1` is that a session-level
   capability answer is a lie for most of the session. Provenance should be
   recomputed for each emitted window — which is also what fixes `core-engine-4`,
   and which `HasTicks(symbol, from, to)` already exists to serve.
3. **Count, do not just flag.** `CSSRFidelityPolicy::m_degradations` and
   `CSSRTickSynthesizer::m_bars_recorded / m_bars_fixed` are the precedent: the
   session should be able to state *"41% of this replay was synthesized"*. Note
   `core-sync-2` [CONFIRMED, MEDIUM] before reusing those counters — spread
   statistics count synthesis *calls*, not bars, because the bar containing the
   clock is re-synthesised every pump, so `BarsWithRecordedSpread` /
   `BarsWithFixedSpread` inflate by roughly pumps-per-bar. A provenance percentage
   built on the same counters would inherit the same inflation.
4. **Persist it.** The session file already has the slot (`data_mode`,
   `SSR_ReplayController.mqh:1728`) and the position file already writes
   `datamode=` (`SSR_PositionFile.mqh:79`). Add the normalization offset (K.6) and
   the dataset identity, so a resumed session can say what it was replaying.
5. **A per-tick provenance bit is not available.** [INFERENCE] `MqlTick` has no
   spare field, `flags` is load-bearing for bar construction, and `volume` is
   already fixed at 1 by the synthesizer. Provenance therefore lives beside the
   data (session record, quality report, panel chip), not inside it. Any future
   proposal to encode it in `volume_real` or a flag bit should be rejected: it would
   corrupt the one thing the synthesizer currently guarantees, that the replayed
   bar's OHLC matches the source bar exactly.
6. **Never present an imported dataset as broker history in the report.**
   `CSSRClassReport` and `CSSRJournal` are read by third parties (students,
   evaluators). A report generated from an imported dataset must say so on its face,
   the way the journal already says what proportion of outcomes rest on an assumed
   tick order.

---

### K.13 Build order

[RECOMMENDATION] The dependencies above are not symmetric; this is the order they
impose.

| # | Step | Blocked by |
|---|---|---|
| 0 | Run spike `SSR_B4_BrokerDataAudit.mq5` on the target terminal | nothing — and its result decides whether import is needed at all |
| 1 | Wire the data-source indicator (K.11): `Mode()` → `SetDataMode` → vitals → chip | nothing; three dead links, one change |
| 2 | Surface the existing quality telemetry (`data-11`) | step 1 gives it a home |
| 3 | Settle `data-2` (whole-window rejection) and `data-1` / `core-engine-4` (range-blind tick probe) | — these are the defects import would amplify |
| 4 | Symbol mapping (K.5) | step 3; also `mt5-symbol-2`, `mt5-symbol-3` |
| 5 | Import + normalization (K.2, K.4) on the `CSSRMemoryStore` pattern | step 4 (money properties, session schedule) |
| 6 | Quality score (K.9) and missing-data detection (K.8) | steps 2, 4 |
| 7 | Import cache (K.10) | step 5; also `mt5-symbol-7`, `mt5-symbol-1` |
| 8 | Data Source Manager and precedence (K.1) | step 5 — a manager with one source is ceremony |

---

### K.14 Risk register for this section

| Risk | Severity | Tag |
|---|---|---|
| `data-1` — range-blind tick probe selects a fidelity the window cannot honour | HIGH | [CONFIRMED] |
| `core-engine-4` — zero-tick `FULL_TICK` window consumed silently, availability never re-evaluated | HIGH | [CONFIRMED] |
| `data-2` — one bad bar voids up to 60,000, reported as success with zero bars | HIGH | [POTENTIAL_RISK] |
| `mt5-symbol-1` — cache reuse skips warmup repair after a jump | HIGH | [CONFIRMED] |
| `data-4` — `warmup_bars` read as both bar count and calendar minutes | MEDIUM | [CONFIRMED] |
| `core-engine-6` — warmup "bars" are calendar minutes; Monday-morning starts seed almost nothing | MEDIUM | [CONFIRMED] |
| `core-sync-2` — spread statistics count synthesis calls, not bars | MEDIUM | [CONFIRMED] |
| `mt5-symbol-2` / `mt5-symbol-3` — adopt path does not force BID mode; wrong existence test | MEDIUM | [POTENTIAL_RISK] / [CONFIRMED] |
| `data-11` — all data-quality telemetry computed then discarded | IMPROVEMENT | [CONFIRMED] |
| `data-12` — ticks sharing a truncation-boundary millisecond dropped | LOW | [POTENTIAL_RISK] |
| `data-5` — no `SERIES_SYNCHRONIZED` early-out; 20 s block then hard failure | LOW | [POTENTIAL_RISK] |
| `data-7` — `Discover()` discards the last complete M1 bar when the market is closed | LOW | [CONFIRMED] |
| `data-3` — random picker samples candidate symbols with replacement | LOW | [CONFIRMED] |
| `mt5-symbol-7` — seed-cache version guard compares a constant that never changes | LOW | [CONFIRMED] |
| `core-sync-3` — generic `NextBarOpen` raises up to four guard violations per call | LOW | [CONFIRMED] |
| No per-tick provenance field exists in `MqlTick` | — | [INFERENCE] |
| MQL5 has no timezone database; only a fixed declared offset is honest | — | [INFERENCE] |

`data-6` and `data-10` appear in the verified set as **NOT_A_BUG** and are not
defects; `data-8` and `data-9` concern the calendar rather than price import and are
noted here only because a shifted import offset interacts with `InpNewsShift`.

---

### K.15 What must not be redesigned

[RECOMMENDATION] Four things in the existing data layer are load-bearing and sound;
an import feature should extend them, not replace them.

1. **The three-provider composition** (`SSR_IDataSource.mqh:9-14`). A CSV of daily
   bars genuinely has no tick provider, and `Ticks()` returning `NULL` is how the
   engine learns that honestly.
2. **Zero bars is data, not failure** (map §12.3). `CSSRBarWindow` records an empty
   range as covered; `ReadBars` returns 0 rather than −1. An importer must keep the
   same convention or every weekend becomes an error.
3. **The guard applies on the way out, never on the way in** (map §12.5), with
   `NextBarOpen` the one deliberate exception because a timestamp is schedule, not
   price.
4. **No symbol rules in the data code** (map §12.9). Session schedules come from
   `SymbolInfoSessionQuote`, currencies from `SYMBOL_CURRENCY_BASE/PROFIT`, digits
   and point from the symbol. Import is exactly where a name-parsing shortcut would
   be tempting, and exactly where it would be most expensive.

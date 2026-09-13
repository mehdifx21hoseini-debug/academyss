# SS Replay — ARCHITECTURE MAP: `data` subsystem (build v125)

Scope: `MQL5/Include/SSReplay/Data/*.mqh` (9 files) plus
`Common/SSR_Random.mqh` and `Common/SSR_Fingerprint.mqh`.
Everything below was read from source, not recalled. Line numbers are
from the files as they stand at v125.

---

## 0. One-paragraph shape of the subsystem

The engine (Core) never touches MetaTrader's history API. It talks to three
abstract provider contracts declared in `Core/SSR_IDataSource.mqh`
(`CSSRHistoryProvider`, `CSSRBarProvider`, `CSSRTickProvider`) owned by a
`CSSRDataSource`. **This subsystem is the only MT5 implementation of those
contracts.** `CSSRMt5DataSource` composes the three concrete providers;
`CSSRMt5BarProvider` serves M1 bars out of one in-memory `CSSRBarWindow`;
`CSSRDataValidator` sanitises what the broker hands back. Around that sit four
planning/decision helpers that do **not** read prices: `CSSRHistoryCatalog`
(what exists and what it costs), `SSRSessionRange` (the user's request),
`CSSRRandomPicker` (a reproducible random start), and two tick observers,
`CSSRSessionWatcher` and `CSSRCalendar`, that only ask to *pause*.

Nothing in this subsystem writes to disk. Nothing in this subsystem draws on a
chart. `CSSRCalendar` is the one class that reads a terminal facility other than
price history (the economic calendar); `CSSRCalendarLines` (Chart layer) draws it.

```
                    ┌─────────────────────────────────────────┐
  Expert            │ SSReplayStandalone.mq5                  │
  (host)            │  g_src  g_catalog  g_picker             │
                    │  g_session (watcher)  g_cal             │
                    └───┬──────────┬─────────┬────────────────┘
                        │          │         │ observers registered
                        ▼          ▼         ▼   with the controller
        CSSRMt5DataSource   CSSRHistoryCatalog   CSSRSessionWatcher
              │                   │                 CSSRCalendar
   ┌──────────┼──────────┐        │ Attach(CSSRHistoryProvider*)
   ▼          ▼          ▼        ▼
 Mt5History  Mt5Bar    Mt5Tick   CSSRRandomPicker ── SSRRandom (Common)
 Provider    Provider  Provider        │
               │                       └─► SSRSessionRange / SSRValidateRange
               ▼
        CSSRBarWindow ──► CSSRDataValidator ──► SSRDataReport
               │
        CopyRates / CopyTicksRange / SeriesInfoInteger / CopyTime
```

---

## 1. `SSR_BarWindow.mqh` — `CSSRBarWindow`

**Responsibility.** Hold exactly ONE contiguous range of M1 bars for ONE symbol
in memory so the pump does not make a terminal round trip per replay tick. The
header is explicit that this is *not* a cache: no persistence, no multi-symbol,
thrown away when the cursor walks out.

**State it owns.**
| Member | Meaning |
|---|---|
| `m_bars[]`, `m_count` | the loaded, sanitised, strictly-ascending M1 bars |
| `m_valid` | "a loaded range, even one holding no bars" (L45) |
| `m_symbol` | which symbol the range belongs to. **Not cleared by `Invalidate()`** |
| `m_from_msc`, `m_to_msc` | the range declared COVERED — deliberately wider than the bars present (L241-246) |
| `m_window_bars` | forward extent of a reload; default `SSR_WINDOW_BARS_DEFAULT` = 20000, floored at 256 by `SetWindowBars` |
| `m_validator`, `m_last_report` | one validator per window; the report of the LAST load only |
| `m_hits/m_misses/m_loads/m_bars_loaded/m_load_time_ms/m_dropped` | instrumentation |
| `m_last_error`, `m_last_error_text` | `ENUM_SSR_ERR` + text |

**Constants.** `SSR_WINDOW_BARS_DEFAULT 20000`, `SSR_WINDOW_LOAD_TIMEOUT_MS 15000`,
`SSR_WINDOW_RETRY_SLEEP_MS 50`.

**Public surface.**
- `SetWindowBars(int)` / `WindowBars()`
- `Invalidate()` — clears bars + coverage, **keeps `m_symbol`**
- `Covers(symbol, from, to)` → `m_valid && symbol==m_symbol && from>=m_from_msc && to<=m_to_msc`
- `Ensure(symbol, from, to)` → bool. The only loader.
- `Read(from, to, MqlRates &out[])` → count, or -1 on resize failure. Binary search + linear scan; **bars whose OPEN lies in the inclusive range**. Never touches the terminal. `out` is only grown, never shrunk — the return value is the only valid length.
- `ReadAt(msc, MqlRates &out)` → exact-open match for the M1 bar containing `msc`.
- Accessors: `Count FromMsc ToMsc Symbol LastError LastErrorText Hits Misses Loads BarsLoaded LoadTimeMs Dropped HitRate ReportInto ToString`

**`LoadRange` (L71-109), the async-retry primitive.** Loops up to 15 s calling
`CopyRates(symbol, PERIOD_M1, from_dt, to_dt, out)`.
- `got > 0` → done.
- `got == 0` → **early-out** if `SeriesInfoInteger(..., SERIES_SYNCHRONIZED)` is
  non-zero: "zero bars means the range genuinely holds none — a weekend, a
  holiday" (L88-92). This early-out exists **only here**, not in
  `CSSRMt5HistoryProvider::Ensure`.
- `!SSRCanBlock()` (i.e. an indicator) → one attempt only, honest failure.
- `SSRPause(50)` == `Sleep(50)` for EAs/scripts.

**`Ensure` (L151-251) — the load algorithm, exactly.**
1. reject `from > to` → `SSR_ERR_INVALID_ARG`
2. `Covers()` → `m_hits++`, return true
3. `m_misses++`
4. `span_bars = (to-from)/60000 + 1`; `want_bars = max(span_bars, m_window_bars)`
5. `lo = SSRBarOpenMsc(from, M1)`; `hi = lo + want_bars*60000` — **extends FORWARD only**, because replay walks forward
6. `if(hi < to) hi = SSRBarOpenMsc(to,M1) + 60000`
7. **if `symbol != m_symbol`** → `m_validator.LearnFrom(symbol)`
8. `LoadRange(symbol, lo, hi, tmp)`; `m_loads++`
9. `got < 0` → `SSR_ERR_LOAD_FAILED` + `Invalidate()` + false
10. `got == 0` → **success with zero bars**: coverage recorded as `[lo,hi]`, `m_valid = true`, so the next pump across a weekend is a hit, not a reload
11. `ValidateBars(tmp, got, m_last_report)` then `SanitizeBars(tmp, got)` → `clean`; `m_dropped += got-clean`
12. `clean <= 0` → `SSR_ERR_NO_DATA` + `Invalidate()` + false
13. **`!m_last_report.IsUsable()` → `SSR_ERR_NO_DATA` + `Invalidate()` + false** ← see finding data-1
14. copy `clean` bars into `m_bars`; `m_from_msc = bars[0].time`, `m_to_msc = bars[clean-1].time + 59_999`
15. **widen coverage back out to the REQUESTED range** (L245-246): `if(lo < m_from_msc) m_from_msc = lo; if(hi > m_to_msc) m_to_msc = hi;` — "we asked, the terminal answered, and re-asking would return the same thing"

**Invariants the code relies on.**
- `m_bars` is strictly ascending by open time and duplicate-free (guaranteed by `SanitizeBars`), which is what makes `Read`/`ReadAt`'s binary search legal.
- coverage `[m_from_msc, m_to_msc]` ⊇ the last requested range, and is *wider* than the bars actually held. A "covered" instant with no bar is a legitimate answer.
- `m_window_bars >= 256`.
- Because step 5 extends forward by ≥ `m_window_bars` minutes, **the window routinely holds bars later than the replay's future-guard horizon.** The guard is applied on the way *out* (`GuardRange` in `ReadBars`, `m_guard.Allows` in `ReadBarAt`), never on the way *in*.

**Writes to disk/chart:** none.

---

## 2. `SSR_DataValidator.mqh`

### `SSRDataReport` (struct, L25-67)
Counters: `total duplicates out_of_order micro_gaps session_gaps largest_gap_msc
invalid_ohlc nonpositive first_msc last_msc`.
- `IsClean()` = `duplicates==0 && out_of_order==0 && invalid_ohlc==0 && nonpositive==0` (session gaps are expected and do **not** make data dirty).
- `IsUsable()` = `total>0 && invalid_ohlc==0 && nonpositive==0` — **duplicates and out-of-order do not make it unusable; a single bad OHLC bar does.**
- `ToString()` for logs.

### Free functions
- **`SSRSymbolSessionGap(symbol)` (L79-127)** → the WIDEST silence in the week, used as "how long may the data be silent before something is actually wrong". Walks `d = 0..6` (`ENUM_DAY_OF_WEEK`, Sunday = 0) × `idx = 0..7` calling `SymbolInfoSessionQuote`; projects each session onto one weekly timeline as `d*86_400_000 + seconds_from_midnight*1000`; breaks the inner loop at the first failing index. Falls back to `SSR_SESSION_GAP_MSC` when the symbol declares **no** sessions. Measures `opens[i] - closes[i-1]` plus the week wrap `(opens[0]+WEEK) - closes[n-1]`. Floored at one hour.
- **`SSRSymbolSessionBreak(symbol)` (L143-185)** → the NARROWEST positive break, used as "how long a silence means the market closed and reopened". Same collection code, duplicated. Returns `SSR_SESSION_GAP_MSC` when `n < 2`. Skips `gap <= 0` ("touching sessions are one session"). Floored at one hour.
- `#define SSR_SESSION_GAP_MSC (60*60*1000)`.

### `CSSRDataValidator`
State: `m_session_gap_msc` only.
- `SetSessionGap(long)`, `LearnFrom(symbol)` → `SSRSymbolSessionGap`, `SessionGap()`
- `ValidateBars(const MqlRates&[], count, SSRDataReport&)` — read-only inspection. Assumes nothing about ordering. `prev` advances only on `t > prev`, so a backwards bar does not poison the gap measurement of its successor. `rep.last_msc` is taken from `bars[count-1]`, which is **wrong if the series is out of order** (reported, not fatal).
  - bad OHLC test: `hi < lo || hi < MathMax(op,cl) || lo > MathMin(op,cl)`
  - nonpositive test: any of O/H/L/C `<= 0.0`
- `SanitizeBars(MqlRates &bars[], count)` → `keep`. In-place compaction keeping **strictly increasing** open times. Drops duplicates and out-of-order bars. **Does NOT drop invalid-OHLC or nonpositive bars.** Never sorts ("sorting would invent an ordering the feed never had").
- `SanitizeTicks(MqlTick &ticks[], count)` → `keep`. Drops only `time_msc < prev`; equal stamps are legal for ticks.
- `ValidateTicks(...)` — **no caller anywhere in the repo, tests included.** Duplicates counted, not condemned; `nonpositive` = `bid <= 0 && last <= 0`; gaps only counted when `>= m_session_gap_msc`.

**Who calls it.** `CSSRBarWindow` (one instance, `LearnFrom` on symbol change);
`CSSRMt5TickProvider` (one instance, `SanitizeTicks` per page, never `LearnFrom`,
so its gap threshold stays at the 1-hour default — it only uses `SanitizeTicks`,
so that is harmless today).

**Writes to disk/chart:** none.

---

## 3. `SSR_HistoryCatalog.mqh`

### `SSRSeedQuote` (struct)
`warmup_bars replay_bars total_bars seconds megabytes exceeds_history
exceeds_maxbars available_bars measured`. `IsFeasible()` = `!exceeds_history &&
total_bars>0`. `ToString()` prefixes "about " when `!measured`.
Note the field-declaration oddity: `measured` is declared at L60, *after* the
`Init()` that assigns it (legal in MQL5).

### `CSSRHistoryCatalog`
State: `m_hist` (a `CSSRHistoryProvider*`, **not owned**), `m_range`
(`SSRDataRange`), `m_symbol`, `m_bars_per_sec`, `m_measured`.

Constants: `SSR_SEED_BARS_PER_SEC_DEFAULT 6000.0` (deliberately conservative; the
first real measurement on terminal build 6090 was 35,159 bars/s),
`SSR_SEED_BYTES_PER_BAR 60`.

Public surface:
- `Attach(CSSRHistoryProvider*)`, `SetMeasuredSeedRate(double)` (ignores `<= 0`), `SeedRate()`, `RateMeasured()`
- `Scan(symbol)` → `m_hist.Discover(symbol, m_range)`; resets `m_range` first
- `RangeInto Available FirstMsc LastMsc BarCount HasTicks CanExtend`
- **`static WarmupFor(tf, visible)`** = `visible` when `PeriodSeconds(tf) <= 60`, else `visible * (PeriodSeconds(tf)/60)`. This is "the 288,000-bar arithmetic": `WarmupFor(D1, 200) == 288000`.
- `Quote(max_tf, visible_bars, replay_minutes, SSRSeedQuote&)` — `total = WarmupFor(...) + replay_minutes`; `seconds = total/m_bars_per_sec`; `megabytes = total*60/1048576`; `exceeds_history = m_range.available && total > m_range.bar_count`; `exceeds_maxbars = maxbars>0 && total>maxbars` where `maxbars = TERMINAL_MAXBARS` (0 = unlimited)
- `LatestStart(warmup_bars, replay_minutes)` = `last_msc - replay*60000`, or `SSR_INVALID_TIME` if that is below `first_msc + warmup*60000`
- `EarliestStart(warmup_bars)` = `first_msc + warmup_bars*60000`
- `CanStartAt(start, warmup)` = `available && start>0 && start >= EarliestStart(warmup) && start < last_msc` — **does not check that `replay_minutes` fit after `start`**
- `LoadMore(bars)` → `m_hist.ExtendBackwards`, then re-`Discover`, returns `(before-after)/60000` (i.e. **minutes**, documented as "bars gained")
- **`static SuggestWindowBars(replay_minutes)`** = `clamp(replay_minutes/4, 5000, 60000)`
- `ToString()`

**Key invariant the rest of the code leans on and that this class does not hold:**
`warmup_bars` is used interchangeably as *a count of M1 bars* (`Quote`'s
comparison against `m_range.bar_count`) and as *a span of wall-clock minutes*
(`EarliestStart`/`LatestStart` multiply it by `SSR_MSC_PER_MIN`). Those are only
equal for an instrument that quotes every minute of every day. See finding data-3.

**Who calls it.** `SSReplayStandalone.mq5` (`g_catalog`: `Attach` L1018/L1438,
`Scan` L1439, `SetMeasuredSeedRate` L2849, `Available` L3105),
`CSSRRandomPicker` (`Scan/EarliestStart/LatestStart/BarCount/LastMsc`),
`CSSRRangeDialog` (`Quote` L134, `LoadMore` L303, `LatestStart`/`EarliestStart`/
`LastMsc` L107-109), `SSRValidateRange`, `CSSRMt5DataSource::OnSessionPlanned`
(the static `SuggestWindowBars`), `SSRSessionRange::WarmupBars` (the static
`WarmupFor`).

**Writes to disk/chart:** none.

---

## 4. `SSR_Mt5Providers.mqh`

Constants: `SSR_SYNC_TIMEOUT_MS 20000`, `SSR_TICK_TIMEOUT_MS 15000`,
`SSR_TICK_PAGE_GUARD 64`.

### `CSSRMt5HistoryProvider : CSSRHistoryProvider`
State: `m_sync_wait_ms`, `m_ensure_calls`.

- `WaitForSeries(symbol, timeout)` (private, L50-72) — `CopyRates(symbol, M1, 0, 2, warm)` to nudge, then poll `SERIES_SYNCHRONIZED` every 50 ms, re-nudging each pass. Returns false on timeout; callers treat that as non-fatal.
- **`Discover(symbol, SSRDataRange &out)`** (L81-143)
  1. `SymbolSelect(symbol,true)` or `SSR_ERR_NO_DATA`
  2. `WaitForSeries(symbol, 20000)` — failure ignored on purpose
  3. read `SERIES_FIRSTDATE`, `SERIES_SERVER_FIRSTDATE`, `SERIES_BARS_COUNT`, `SERIES_LASTBAR_DATE`
  4. `bars<=0 || first<=0 || lastbar<=0` → `SSR_ERR_NO_DATA`
  5. `out.first_msc = first*1000`
  6. **forming-bar exclusion**: `last_quote = SymbolInfoInteger(symbol, SYMBOL_TIME_MSC)`; if `last_quote > 0 && last_quote <= lastbar_open+59_999` then `out.last_msc = lastbar_open - 1`, else `out.last_msc = lastbar_open + 59_999`
  7. `out.server_first_msc = server_first*1000` or `out.first_msc`
  8. `out.bar_count = bars`
  9. tick probe (L133-139): `CopyTicksRange(symbol, probe, COPY_TICKS_INFO, max(last_msc - 86_400_000, 0), last_msc)` → `out.has_ticks = (got > 0)` (**hardcoded `COPY_TICKS_INFO`, not `m_flags`**)

  **`out.has_ticks` is load-bearing far outside this class.** The host reads it as
  `g_ctrl.SetFidelity(range.has_ticks ? SSR_FIDELITY_FULL_TICK : SSR_FIDELITY_SYNTHETIC_TICK)`
  (`SSReplayStandalone.mq5:1153`), and the controller feeds the same flag to the
  fidelity policy (`SSR_ReplayController.mqh:806`
  `m_fidelity.SetTicksAvailable(range.has_ticks)`), which is the ONLY thing that
  can degrade FULL_TICK back to synthetic (`SSR_FidelityPolicy.mqh:114-118`).
  The probe window is the last 24 h of history; the replay window is wherever the
  user went. See finding data-1.
- **`Ensure(symbol, from, to)`** (L146-180) — `CopyRates(from_dt,to_dt)` in a loop for up to 20 s; **only `got > 0` succeeds**, so a range that legitimately holds zero bars burns the whole timeout and then fails. No `SERIES_SYNCHRONIZED` early-out (contrast `CSSRBarWindow::LoadRange`).
- **`ExtendBackwards(symbol, bars)`** (L187-234) — returns the new `first_msc` in msc, never an error for "the broker has nothing older". `want_from = first - bars*60` seconds, clamped up to `server_first`. Loops `CopyRates(want_from, first)` + re-read `SERIES_FIRSTDATE` every 100 ms until `now_first < first` or 20 s.

### `CSSRMt5BarProvider : CSSRBarProvider`
State: one `CSSRBarWindow m_window`.
- `Window()` → `GetPointer(m_window)`; `SetWindowBars(int)`; `Invalidate()`
- **`ReadBars`** — `GuardRange(lo,hi)` (guard layer 2; returns 0 when nothing legal) → `m_window.Ensure` → `m_window.Read`. **On `Ensure` failure it returns 0 (not -1) whenever `m_window.LastError() == SSR_ERR_NO_DATA`**, on the reasoning that "no data in range is not an error".
- **`NextBarOpen`** — deliberately NOT guarded, and overrides the base's `ReadBars`-based implementation. Uses `CopyTime` (times only) over widening windows of **seconds** `{3600, 86400, 691200, 3456000}` from `after_msc/1000 + 1`, returning the first stamp `> after_msc`. Justification in the header comment: a timestamp is the exchange's schedule, not a price. (The base class's spans at `SSR_IDataSource.mqh:155-158` are in **milliseconds** — the two units are correct in their own contexts; do not "unify" them.) A negative `CopyTime` return is silently treated as "nothing here".
- `ReadBarAt` — explicit `m_guard.Allows(open)` + `m_guard.Violation(open)` on refusal → `SSR_ERR_FUTURE_ACCESS`; then `Ensure(open, open+59_999)` + `ReadAt`.
- `BarCount(symbol)` = `SERIES_BARS_COUNT` for M1.

### `CSSRMt5TickProvider : CSSRTickProvider`
State: `m_validator` (only `SanitizeTicks` is used), `m_pages`, `m_ticks_read`,
`m_read_time_ms`, `m_flags` (default `COPY_TICKS_INFO`).
- `SetFlags(uint)`, `Pages()`, `TicksRead()`, `ReadTimeMs()`
- `HasTicks(symbol, from, to)` — one `CopyTicksRange`, **not guard-clamped**. **No caller anywhere in the repo** — this is the range-aware question nothing asks.
- **`ReadTicks(symbol, from, to, out[])`** — contract is half-open at the bottom, `(from, to]`.
  `GuardRange` → `cursor = (lo<0 ? 0 : lo+1)` (the clamp exists because
  `(ulong)negative` wraps to a colossal timestamp) → page loop bounded by
  `SSR_TICK_PAGE_GUARD` (64 pages) with a **separate** retry budget (`retries < 200`,
  15 s) so async retries cannot consume the page budget. Per page:
  `SanitizeTicks`, append, `m_pages++`, then `cursor = last+1`; stops on
  `last >= hi` or `last < cursor` (no forward progress). `out` is grown, never
  shrunk — the return value is the only valid length.

**Writes to disk/chart:** none.

---

## 5. `SSR_Mt5DataSource.mqh` — `CSSRMt5DataSource : CSSRDataSource`

**Responsibility.** Compose the three providers into the `CSSRDataSource` the
engine expects, and own their lifetime.

State: `m_hist/m_bars/m_ticks` (all `new`ed in the ctor, `delete`d in the dtor
after `DetachGuard()`), `m_symbol`, `m_has_ticks`, `m_allow_ticks`, `m_range`.
Inherited: `m_mode = SSR_DATA_BROKER`, `m_open`, `m_guard`.

- `Name()` → `"mt5-broker"`
- `Open(symbol)` — `SymbolSelect` → `m_hist.Discover` → `m_has_ticks = m_range.has_ticks` → `m_bars.Invalidate()` → `m_open = true`. Discovery happens here so "a caller that cannot even see the symbol finds out here rather than three layers deeper".
- `Close()` — invalidate the window, `m_open = false`
- `History()`, `Bars()`
- **`Ticks()`** — returns `NULL` unless `m_allow_ticks && m_has_ticks`, so the engine degrades to `SYNTHETIC_TICK` **and announces it** rather than running FULL_TICK against an empty tick history.
- **`SetGuard(g)` / `DetachGuard()`** — override the base walk (which goes through `Ticks()` and would therefore never arm the tick provider) and reach all three providers directly. `DetachGuard` in the destructor closes Phase 1 TODO T1: the guard belongs to the controller and may already be gone.
- **`OnSessionPlanned(replay_minutes)`** — `m_bars.SetWindowBars(CSSRHistoryCatalog::SuggestWindowBars(replay_minutes))`; ignores `<= 0`. Called from `CSSRReplayController::Load` (`SSR_ReplayController.mqh:787`).
- `SetAllowTicks(bool)`, `SetWindowBars(int)`, `SetTickFlags(uint)`
- `HasTicks()`, `SymbolName()`, `RangeInto(SSRDataRange&)`, `Mt5History()`, `Mt5Bars()`, `Mt5Ticks()`
- `ToString()` — **dead code: no caller anywhere in the repo** (`grep -rn "src.ToString\|source.ToString"` → nothing). It is the only thing that would surface `m_window.ToString()`'s `dropped=` and `hit=` figures.
- `SetAllowTicks` and `SetTickFlags` also have **no caller**, so playback always uses `COPY_TICKS_INFO` and the probe's flags and the reader's flags agree today.

**Writes to disk/chart:** none.

---

## 6. `SSR_RandomPicker.mqh` — `CSSRRandomPicker`

**Responsibility.** Choose a symbol + start instant that the broker can actually
serve, reproducibly from a reported seed.

Constants: `SSR_MAX_RANDOM_SYMBOLS 32`, `SSR_PICK_ATTEMPTS 8`.

State: `m_cat` (`CSSRHistoryCatalog*`, **not owned**), `m_rng` (`SSRRandom`,
seeded to 1 in the ctor), `m_seed`, `m_pool[32]` + `m_pool_count`,
`m_last_error`, `m_skipped`, and the result triple `m_symbol/m_start_msc/m_end_msc`.

Public surface:
- `Attach(CSSRHistoryCatalog*)`
- `SetSeed(ulong s)` — **`s == 0` means "pick one for me"**: `m_seed = SSRPickSeed()`; then `m_rng.Seed(m_seed)`
- `Seed()`, `SeedText()`
- `AddSymbol(s)` — rejects `""` and a full pool; **returns `true` for a duplicate without adding it**
- `AddSymbolList(csv)` — splits on `,`, trims, returns the number of `AddSymbol` successes (so duplicates inflate the count)
- `ClearSymbols`, `SymbolCount`, `SymbolAt`, `LastError`, `SkippedText`
- `PickedSymbol`, `PickedStart`, `PickedEnd`, `HasPick()` (= `m_start_msc > 0`)
- **`Pick(warmup_bars, replay_minutes, fallback="")`**
  1. clear the result; require `m_cat`; `if(m_seed==0) SetSeed(0)` so a seed is always reported
  2. empty pool → add `fallback`, or fail "no symbols to choose from"
  3. `attempts = min(m_pool_count, 8)`; loop:
     - `sym = m_pool[m_rng.Index(m_pool_count)]` — **sampling WITH replacement**
     - `!m_cat.Scan(sym)` → append "`sym` (no history) " to `m_skipped`, continue
     - `lo = EarliestStart(warmup)`, `hi = LatestStart(warmup, replay)`; `lo<=0 || hi<=0 || hi<=lo` → record by name with the arithmetic, continue
     - `pick = SSRBarOpenMsc(m_rng.InRange(lo,hi), M1)`; if the floor took it below `lo`, bump to `SSRBarOpenMsc(lo)+60000`
     - `m_end_msc = pick + replay*60000`, clamped to `m_cat.LastMsc()`; return true
  4. `Fail("no candidate had enough history: " + m_skipped)`
- `Ticket()` → `"seed <text>"` — the line the user writes down
- `ToString()`

**Who calls it.** Only `SSReplayStandalone.mq5` L1016-1046, and only when
`CfgRandom()`. The pool is `InpAlsoSymbols` (**the same input the master clock
uses for extra streams**) plus the origin. On success the picker may change the
origin symbol, and the host re-`Open`s the data source. The seed is also handed to
the strategy host (`g_strategies.SetSeed`, L1237) and to the integration port
(L1356) as `IntegerToString((long)Seed())`.

**Writes to disk/chart:** none.

---

## 7. `SSR_SessionRange.mqh`

### `SSRSessionRange` (struct, L18-64)
`origin start_msc end_msc max_tf visible_bars fidelity slot`.
`Init()` defaults: `max_tf = PERIOD_H1`, `visible_bars = 300`,
`fidelity = SSR_FIDELITY_SYNTHETIC_TICK`, `slot = 1`, times `SSR_INVALID_TIME`.
- `WarmupBars()` → `CSSRHistoryCatalog::WarmupFor(max_tf, visible_bars)`
- `ReplayMinutes()` → `(end-start)/60000`, or 0 when the range is not positive
- `IsComplete()` → `origin != "" && start>0 && end>start`
- `Describe()`

### `SSRValidateRange(SSRSessionRange&, CSSRHistoryCatalog&) -> string`  (L69-99)
Returns `""` when servable, a user-readable reason otherwise, in this order:
1. `"pick a symbol"` — no origin
2. `"no M1 history for <origin>"` — `!cat.Available()`
3. `"pick a start date"` — `start <= 0`
4. `"the end must come after the start"`
5. `"start too early - <tf> context needs history back to <t>"` — `start < cat.EarliestStart(WarmupBars())`
6. `"start is beyond the available history"` — `start >= cat.LastMsc()`
7. `"not enough history: <quote>"` — `q.exceeds_history`
8. `"warning: exceeds the terminal's Max bars in chart setting"` — a **warning**, not a refusal; `CSSRRangeDialog::CanStart()` accepts any message beginning "warning"

**It never compares `end_msc` against `cat.LastMsc()`** (the chain ends at L98 `return "";`).

**Who calls it.** `CSSRRangeDialog::Recompute` (`SSR_RangeDialog.mqh:135`) and
`SSR_T6_History.mq5`. The dialog today defaults `end_msc = cat.LastMsc()` and only
ever edits `start_msc` (L272), and the host uses a confirmed range only as a JUMP
inside the already-loaded session (`SSReplayStandalone.mq5:3183-3192`), which is
why the missing end check is latent rather than live.

**Writes to disk/chart:** none.

---

## 8. `SSR_SessionWatcher.mqh` — `CSSRSessionWatcher : CSSRTickObserver`

**Responsibility.** Ask for a pause when a new trading session starts, without
hardcoding when sessions start.

`enum ENUM_SSR_SESSION_MODE { SSR_SESSION_OFF, SSR_SESSION_BY_GAP, SSR_SESSION_BY_DAY }`
(this enum is the type of the expert input `InpPauseSession`).

State: `m_mode`, `m_threshold_msc` (default `SSR_SESSION_GAP_MSC`), `m_symbol`,
`m_last_tick_msc`, `m_last_day`, `m_want`, `m_reason`, `m_raised`.

- `Name()` → `"session-watch"`
- `SetMode/Mode/SetThresholdMsc(>0 only)/ThresholdMsc/Raised`
- **`LearnFrom(symbol)`** → `m_threshold_msc = SSRSymbolSessionBreak(symbol)` — the NARROWEST declared break, not the widest
- `OnSessionStart(symbol, digits, point, start_msc)` — resets `m_last_tick_msc` to `SSR_INVALID_TIME` (so the first gap is never measured), `m_last_day = start_msc/86_400_000`, clears the pending pause. Note it overwrites `m_symbol` with the **replay** symbol while `m_threshold_msc` was learned from the **origin**; `m_symbol` is otherwise unused.
- `OnTicks(ticks[], count)` — when `OFF`, still tracks the last tick and day "so switching the mode on mid-replay does not fire on the accumulated silence". `BY_GAP`: `t - m_last_tick_msc >= m_threshold_msc` (only once `m_last_tick_msc > 0`). `BY_DAY`: `t/86_400_000 > m_last_day` (server-time day, because bar stamps are server seconds).
- `PauseRequested(string &reason)` — one-shot: consumes `m_want`
- `OnRewind(msc)` — clears the pending pause and re-bases `m_last_tick_msc`/`m_last_day` to `msc`, so "announcing the one we are standing on" does not happen but boundaries crossed again on the way forward do
- `ToString()`

`Raise()` is idempotent while a pause is already pending (`if(m_want) return;`).

**Who calls it.** `SSReplayStandalone.mq5` L1228-1229 (`SetMode(InpPauseSession)`,
`LearnFrom(origin)`) and then it is registered as a controller observer;
`CSSRReplayController` drives `OnTicks`/`OnRewind`/`PauseRequested`
(`SSR_ReplayController.mqh:156, 237`).

**Writes to disk/chart:** none.

---

## 9. `SSR_Calendar.mqh` — `CSSRCalendar : CSSRTickObserver`

**Responsibility.** Read MetaTrader's economic calendar for the replay window and
answer "what is happening, and when". **It reads; it does not draw.**

Constants: `SSR_CAL_MAX 300` (a ceiling so a five-year window cannot try to draw
twenty thousand vertical lines), `SSR_CAL_TEXT_MAX 63` (MetaTrader's `OBJPROP_TEXT`
draw limit).

`enum ENUM_SSR_NEWS { OFF=0, HIGH=1, MODERATE=2, ALL=3 }` (the type of `InpNews`).
`SSRNewsFloor(n)` (L59-64) → `CALENDAR_IMPORTANCE_HIGH` / `_MODERATE` / else `_LOW` —
so `SSR_NEWS_ALL` floors at LOW and excludes `CALENDAR_IMPORTANCE_NONE`.
`SSRNewsName(n)` → "high impact only" / "moderate and above" / "everything" / "off".

`SSRCalendarItem` (struct): `msc` (**on the replay's clock, i.e. already shifted**),
`currency`, `name`, `importance`. `Label()` = `currency + "  " + name`, truncated to
62 chars + `"~"` when it would exceed 63.

State: `m_items[]` + `m_count`, `m_available`, `m_note`, `m_shift_msc`,
`m_pause_min`, `m_announced[]`, `m_want`, `m_reason`, `m_raised`.

- `Name()` → `"calendar"`
- `SetShiftMinutes(int)` → `m_shift_msc = m*60000` (the user's one-off timezone correction, `InpNewsShift`)
- `SetPauseMinutes(int)` → `m_pause_min` (`< 0` becomes 0; 0 = never pause)
- `Count`, `Available`, `Note`, `Raised`, `At(i, SSRCalendarItem&)`
- **`Pull(currency, from, to, min_importance)`** (private, L125-159) — `CalendarValueHistory(vals, from, to)` when `currency == ""`, else `CalendarValueHistory(vals, from, to, NULL, currency)` (branched rather than a ternary on purpose: `NULL` and a string in one conditional is build-dependent and there is no compiler on this side of the wire). For each value: `CalendarEventById` for the name and importance, drop below `min_importance`, else append with `msc = vals[i].time*1000 + m_shift_msc`.
- **`Load(origin_symbol, from_msc, to_msc, min_importance)`** (L200-265)
  1. reset; `ArrayResize(m_items, 300)`; `ArrayResize(m_announced, 300)`; clear announced
  2. reject a non-positive window
  3. **widen by one day at each end** (`±86400` s) so an event just outside still lands on the chart
  4. currencies come from `SYMBOL_CURRENCY_BASE` / `SYMBOL_CURRENCY_PROFIT` — **never parsed out of the symbol name**. Both empty → `Pull("")` (every country) and a note saying so. Otherwise `Pull(base)` and `Pull(profit)` when `profit != base`.
  5. **availability probe** (L244-246): a THIRD, unfiltered `CalendarValueHistory(probe, from, to)`; `m_available = (any > 0)`. `!m_available` → the "this terminal returned no calendar at all" note + `return false`.
  6. otherwise set the "quiet window" or the "ceiling reached" note
  7. return `m_count > 0`
  The window query is **not** shifted, only the item stamps are; the ±1-day
  widening absorbs any `InpNewsShift` under 24 h.
  Items are appended per currency, so **`m_items` is not sorted by time.**
- **`OnClock(now_msc)`** (L275-302) — the news pause. Returns immediately when
  `m_pause_min <= 0 || m_count == 0`. For each un-announced item of importance
  `>= CALENDAR_IMPORTANCE_HIGH` (**HIGH only, deliberately**): already past →
  mark announced silently; within `m_pause_min` → mark announced and
  `Raise("<n> min to <Label>")`.
- `PauseRequested(string&)` — one-shot
- `OnRewind(msc)` — clears the pending pause and un-announces every item at or
  after `msc`, "or replaying the same hour would run straight through the release
  the user rewound in order to watch again"

**Who calls it.** `SSReplayStandalone.mq5::LoadCalendar` (L921-954), which is
called once at L1282 with `(origin, win_start, win_end)` — **the whole replay
window**. `LoadCalendar` refuses to run when `InpNews == SSR_NEWS_OFF`, when blind
mode is on (an event name plus its date would give away the session), or when
`g_replay_chart == 0`. `SetShiftMinutes`/`SetPauseMinutes` are set earlier at
L1222-1223, so the shift is in place before `Load`. The only consumer of the item
list is `CSSRCalendarLines::Draw` (`Chart/SSR_CalendarLines.mqh:71`), which creates
one `OBJ_VLINE` per item, `OBJPROP_BACK=true`, `OBJPROP_HIDDEN=true`, text and
tooltip = `Label()`, **all of them at load time**.

**Writes to disk:** none. **Writes to chart:** none directly — `CSSRCalendarLines`
does, on the replay chart, with the `SSR_CAL_PREFIX` object prefix.

---

## 10. `Common/SSR_Random.mqh`

### `SSRRandom` (struct) — xorshift64*
`ulong state`.
- `Seed(s)` — `state = (s == 0 ? 0x9E3779B97F4A7C15 : s)`; zero is the one state xorshift cannot leave
- `Next()` — `state ^= state>>12; state ^= state<<25; state ^= state>>27; return state * 2685821657736338717` (MQL5 `>>` on `ulong` is a logical shift, so this is the real xorshift64*)
- `InRange(lo, hi)` — `[lo, hi)`; returns `lo` when the range is empty; `lo + Next() % (ulong)(hi-lo)`
- `Index(count)` — `[0, count)`; returns 0 when `count <= 0`
- `Chance(percent)`

### Free functions
- **`SSRPickSeed()`** — `(TimeLocal()*1000003) ^ (GetMicrosecondCount()*2654435761)`, never 0. **"This is the ONE place a wall clock may be read"** — it picks a number to print back at the user; everything downstream is a pure function of it.
- `SSRSeedText(ulong)` → `IntegerToString((long)seed)` — a seed above `LONG_MAX` therefore prints **negative**
- `SSRSeedFromText(string)` → trims; `""` → 0 (which every caller reads as "pick one"); otherwise `(ulong)StringToInteger(t)`. Negative text round-trips through two's complement, which is what makes the negative display safe.

**Who calls it.** `CSSRRandomPicker`, `g_strategies.SetSeed`, the integration port,
and `CfgSeed()`/`InpSeed` in the host.

---

## 11. `Common/SSR_Fingerprint.mqh`

**Responsibility.** A session file holds no price data, so on resume the bars are
re-read from the broker. This detects that the broker's history for the replayed
range changed, and **reports** it — it never blocks the resume. Explicitly not a
cryptographic hash: it must catch accidental change, not adversarial change.

### `SSRFingerprint` (struct, L38-87)
`bars first_msc last_msc digest`.
- `Init()`, `IsValid()` (= `bars > 0`), `Equals(o)` (all four fields)
- **`DiffText(o)`** — the differences in words, in priority order: `!o.IsValid()`
  → "the broker has no history for this range any more"; `bars != o.bars` →
  "`N` bars then, `M` now (`+K`) — the broker's history for this range changed";
  ends moved → "the range moved: …"; else → "same bar count and range, but the
  prices in them changed — the broker revised this history"
- `ToString()`

### Free functions
- **`SSRDigestBar(ulong &digest, const MqlRates &bar, int digits)`** (L98-115) — folds
  `time` and `MathRound(O/H/L/C * 10^digits)` as **integers** through FNV-1a
  mixing (`digest ^= part; digest *= 0x100000001B3`). Prices are scaled to
  integers on purpose: a double's bit pattern would make the digest depend on
  how the value was arrived at, so a bar that round-tripped through the session
  file would differ from the same bar read fresh and every resume would cry wolf.
  Volume and spread are **not** folded in.
- `SSRFingerprintBars(bars[], count, digits, out)` (L118-130) — seeds `digest` with the
  FNV-1a offset basis `0xCBF29CE484222325`, folds every bar, then records
  `bars/first_msc/last_msc`. No-op for `count <= 0`.
- **`SSRFingerprintPack(f)`** (L141-145) → `"bars;first;last;(long)digest"` with `%I64d`.
  The digest travels as a **signed** long deliberately: `%I64u` would exceed what
  `StringToInteger` can read back for about half of all digests, and every such
  session would report a false mismatch. The two's-complement bit pattern round
  trips exactly.
- `SSRFingerprintUnpack(s, out)` (L147-158) — splits on `;`, needs ≥ 4 parts,
  `digest = (ulong)(long)StringToInteger(p[3])`

**Who calls it.** `CSSRReplayController::FingerprintUpTo` (`SSR_ReplayController.mqh:1677-1695`)
fingerprints `[m_timeline.start_msc, min(to_msc, m_clock.now_msc)]` — never past
the clock, "reading past the clock to fingerprint a wider range would be the tool
doing exactly what it exists to prevent, for the sake of a checksum". It reads via
`bp.ReadBars` (so through `CSSRBarWindow`) and passes `m_digits`, which is set once
per session by `SetPrecision`. `SaveInto` writes `f.Set("fingerprint", ...)` only
when `FingerprintUpTo` succeeded; the load path (L1845-1866) unpacks, compares, and
sets a `warning` string, falling back to a bar-count comparison for older files
with no fingerprint.

---

## 12. Cross-cutting invariants a later designer must preserve

1. **M1 only.** Every read in this subsystem is `PERIOD_M1`. Higher timeframes are
   MetaTrader's problem, derived from the custom symbol.
2. **Time is `long` milliseconds everywhere**; `SSR_INVALID_TIME` is `-1`, not 0.
   `SSRToMsc/SSRToTime/SSRBarOpenMsc` are the only conversions
   (`SSRBarOpenMsc` truncates toward zero, which is only correct for positive msc).
3. **Zero bars is data, not failure.** `CSSRBarWindow` records an empty range as
   covered; `CSSRMt5BarProvider::ReadBars` returns 0 rather than -1 for
   `SSR_ERR_NO_DATA`. Only `SSR_ERR_LOAD_FAILED`/`SSR_ERR_INTERNAL` are errors.
4. **`SSRCanBlock()` gates every retry loop.** An indicator gets one attempt and an
   honest failure instead of a frozen terminal; an EA/script gets `Sleep`.
5. **The future guard is applied on the way OUT of the data layer**
   (`GuardRange`, `m_guard.Allows`), never on the way in. `NextBarOpen` is the one
   deliberate exception, and only because it returns timestamps, not prices.
6. **Ordering.** `m_bars` in the window is strictly ascending and duplicate-free;
   tick pages are ascending and may repeat a millisecond; `m_items` in the calendar
   is **not** time-ordered.
7. **Array returns are counts, not `ArraySize`.** `Read`, `ReadBars`, `ReadTicks`
   grow their output array but never shrink it.
8. **The seed is the only wall-clock read**, and it exists to be printed.
9. **Symbol rules never live in this code.** Session breaks come from
   `SymbolInfoSessionQuote`, currencies from `SYMBOL_CURRENCY_BASE/PROFIT`,
   digits/point from the symbol. No name parsing anywhere.
10. **Nothing here persists or draws.** All disk and chart work belongs to
    Session, Report, Mt5 and Chart.

---

## 13. Dead / unreachable surface in this subsystem (verified by repo-wide grep)

| Symbol | File | Status |
|---|---|---|
| `CSSRDataValidator::ValidateTicks` | SSR_DataValidator.mqh:307 | no caller at all, tests included |
| `CSSRDataValidator::SetSessionGap` | SSR_DataValidator.mqh:196 | tests only (`SSR_T6_History.mq5`) |
| `SSRDataReport::IsClean` | SSR_DataValidator.mqh:48 | tests only |
| `CSSRBarWindow::ReportInto` | SSR_BarWindow.mqh:329 | no caller |
| `CSSRBarWindow::Dropped/HitRate/Loads/BarsLoaded/LoadTimeMs` | SSR_BarWindow.mqh:316-327 | `Misses/HitRate/ToString` in `SSR_T2_DataEngine.mq5` only |
| `CSSRMt5DataSource::ToString` | SSR_Mt5DataSource.mqh:146 | no caller — and the only route by which the window's `dropped=` figure could reach a human |
| `CSSRMt5DataSource::SetAllowTicks`, `SetTickFlags` | SSR_Mt5DataSource.mqh:133,135 | no caller |
| `CSSRMt5TickProvider::HasTicks(symbol,from,to)` | SSR_Mt5Providers.mqh:379 | no caller — the range-aware tick question nothing asks |
| `CSSRMt5TickProvider::Pages/TicksRead/ReadTimeMs` | SSR_Mt5Providers.mqh:375-377 | no caller |
| `CSSRHistoryCatalog::CanStartAt` | SSR_HistoryCatalog.mqh:178 | no caller |
| `CSSRRandomPicker::SkippedText` | SSR_RandomPicker.mqh:108 | no caller (the same text is folded into `LastError()`, which the host does print) |
| `SSRFingerprint::ToString` | SSR_Fingerprint.mqh:79 | no caller |

**Net effect:** every number this subsystem measures about data quality —
duplicates, out-of-order bars, micro vs session gaps, largest gap, dropped bars,
window hit rate, tick pages, tick read time — is computed on the hot path and then
discarded. On a terminal the author cannot run, that is the difference between a
diagnosable fault and "it just showed nothing".

## 14. Cross-subsystem couplings worth knowing before redesigning anything here

1. `SSRDataRange.has_ticks` (set by one 24-hour probe) chooses the replay's
   **fidelity** two layers up. Changing the probe changes how every session runs.
2. `SSRDataRange.last_msc` becomes the host's `win_end` (`SSReplayStandalone.mq5:1075`),
   so the forming-bar exclusion at `SSR_Mt5Providers.mqh:125-128` shortens every
   default window by one minute.
3. `CSSRHistoryCatalog::SuggestWindowBars` is reached through
   `CSSRDataSource::OnSessionPlanned`, so the read window is sized by the *engine's*
   session length, not by the catalogue's caller.
4. `InpAlsoSymbols` is read twice for two different purposes: as the random picker's
   candidate pool (`SSReplayStandalone.mq5:1021`) and as the master clock's extra
   streams. A symbol added for multi-symbol practice becomes a candidate to replace
   the origin.
5. `CSSRRandomPicker::Seed()` also seeds the strategy host (`:1237`) and is published
   to other products (`:1356`), so the RNG's reproducibility contract is wider than
   the start-pick.
6. The calendar's items reach the chart only through `CSSRCalendarLines`, which has no
   clock and draws everything `CSSRCalendar` holds.

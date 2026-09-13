# Subsystem map — `tests-a` (T1…T8 executable test suite)

Build v125. Files (all under
`/home/user/academyss/mt5-replay/MQL5/Scripts/SSReplay/Tests/`):

| File | Lines | Phase claim | Needs a broker? | Needs a terminal? |
|---|---:|---|---|---|
| `SSR_T1_CoreEngine.mq5` | 421 | Phase 1 DoD: replay engine | no | no (script host only) |
| `SSR_T2_DataEngine.mq5` | 469 | Phase 2: data engine | T2.4–T2.10 yes | yes |
| `SSR_T3_CustomSymbol.mq5` | 458 | Phase 3: `Custom*` API | T3.2–T3.8 yes | yes |
| `SSR_T4_ChartIntegration.mq5` | 376 | Phase 4: native charts | yes (all-or-skip) | yes |
| `SSR_T5_Ui.mq5` | 331 | Phase 5: panel / keys | no | yes (draws objects) |
| `SSR_T6_History.mq5` | 309 | Phase 6: history + seed cache | T6.2–T6.4, T6.7–T6.8 yes | yes |
| `SSR_T7_Performance.mq5` | 320 | Phase 7: metrics / budget | no | no |
| `SSR_T8_Navigation.mq5` | 335 | Phase 8: rewind / jump | no | yes (writes a file) |

There is **no test runner and no harness**. Each file is a standalone
`#property script_show_inputs` script with `OnStart()`. There is no exit
code, no assert-abort, and no aggregation across files: the only signal is
`Print`ed text ending in `GREEN` or `RED`. A human reads the Experts log.

---

## 1. The shared idiom (copied, not shared, in all eight files)

Every file re-declares, at file scope, its own copy of:

```
int g_pass = 0, g_fail = 0;              // T2,T3,T4,T6 add: int g_skip = 0;
void Check  (const string n, const bool ok, const string d = "");
void CheckEq(const string n, const long e, const long a);
void Skip   (const string n, const string w);      // T2,T3,T4,T6 only
void Section(const string t);
```

* `Check` — increments `g_pass` / `g_fail` and prints `  PASS  <name>` or
  `  FAIL  <name>  <detail>`. **Never aborts.** A failing assertion is
  followed by the next statement, which is why several sections keep
  dereferencing a pointer they just asserted non-NULL.
* `CheckEq` — `Check(n, e == a, "expected=%I64d actual=%I64d")`. Both
  parameters are `long`, so every float assertion is written by hand with
  `MathAbs(...) < eps` instead.
* `Skip` — counted separately; a skip is **not** a failure and does not
  turn the run RED. This is the deliberate "no M1 history on this account
  is not a code defect" policy stated in T2's header.
* The `detail` argument is **eagerly evaluated**, including on the pass
  path (e.g. `ctrl.LastErrorText()`, `snap.ToString()`, `lg.Advice()`).

There is no `CheckNear`, no `CheckStr`, no `CheckGT`, and no "expected
failure" form. `Check(name, a > b)` loses both numbers unless the author
formats a `detail` by hand, which roughly half the call sites do not.

Deterministic-data generators, also duplicated per file:

| Helper | File | Shape |
|---|---|---|
| `BuildBars(out[], start, count, base, digits, point)` | T1:49 | xorshift + Box-Muller random walk, seed `20260829`, re-clamps H/L to O/C |
| `MakeBars(out[], start, count, base)` | T2:47 | strictly rising ramp, `o+1/-1/+0.25` |
| `BuildBars(out[], start, count, base, digits)` | T7:35 | sawtooth `((i%7)-3)*0.5` |
| `BuildBars(out[], start, count, base)` | T8:32 | sawtooth `((i%11)-5)*0.5` |
| inline loops | T3:159, T3:213 | ramp, 300 and 60 bars |

`Wire(...)` exists in T1:88 (returns `bool`, does **not** Load) and T8:50
(returns `bool`, **does** Load). Same name, different contract.

---

## 2. Per-file structure

### T1 — `SSR_T1_CoreEngine.mq5`
Inputs: `InpStart=2024.01.08 00:00`, `InpBars=1440`, `InpBase=38000.0`,
`InpWarmup=120`. Window: `start = dataset_first + 120 min`,
`end = start + 240 min`.

Collaborators: `SSRReplayClock` (value type, used directly),
`SSRCanTransition`, `CSSRMemoryDataSource`, `CSSRRecordingSink`,
`CSSRReplayController`, `CSSRBarProvider*` via `src.Bars()`, `SSRSnapshot`.

| § | Claim | What it actually reads |
|---|---|---|
| T1.1 | clock determinism | four `SSRReplayClock`s; `now_msc` after N×`Advance(ms)`; `IsCompleted()` |
| T1.2 | state machine legality | 9 × `SSRCanTransition(a,b)` — a pure table |
| T1.3 | load / warmup / initial position | `Status()`, `sink.IsPrepared()`, `sink.SeedBarCount()==120`, `Now()==start`, `sink.TickCount()==0`, `TimelineValid()` |
| T1.4 | ordered, non-duplicated stream | exact `sink.TickCount()==9` after 60×`Pump(1000)` at 1x; `OrderViolations()==0`; `DuplicateStamps()==0`; `Now()==start+60000`; `Violations()==0`; `CountAfter(Now())==0` |
| T1.5 | engine determinism | two runs, 300×`Pump(97)` at 2x, `sink.Fingerprint()` equality |
| T1.6 | future data guard | `CountAfter(now)==0`; direct `bp.ReadBars(future)==0`; `ctrl.Violations()>0` (the guard object is shared — `Attach`/`Load` calls `m_source.SetGuard(GetPointer(m_guard))`, controller line 573); past still readable |
| T1.7 | step / seek / rewind | `StepBars(1)` return, `Status()==PAUSED`, `SeekTo` forward and backward, `sink.Truncations()>0`, `CountAfter(after10)==0` |
| T1.8 | snapshot / restore | `TakeSnapshot`, `snap.IsValid()`, `RestoreSnapshot`, `Now()` restored exactly, `Status()!=PLAYING`, `TickCount() <= snap_ticks` |
| T1.9 | reset | `Reset()`, `Now()==start`, `Status()==READY`, `CountAfter(start)==0`, `SeedBarCount()` unchanged, `TicksEmitted()==0` |
| T1.10 | fidelity routing | 3 runs × 180×`Pump(1000)`; `FULL==SYNTHETIC` (memory source has no ticks), `SYNTHETIC>BAR`, `BAR>0` |
| T1.11 | error handling | load with no source → `ERROR` + `LastError()!=SSR_OK`; 2010 window rejected; `Pump` before load returns 0 |

Writes to disk/chart: **nothing**.

### T2 — `SSR_T2_DataEngine.mq5`
Inputs: `InpSymbol=""` (→ `_Symbol`), `InpBars=600`, `InpWarmup=120`.
Two halves by design: T2.1–T2.3 pure, T2.4–T2.10 broker-dependent and
skipped when `src.Open(sym)` fails.

Collaborators: `CSSRDataValidator`, `CSSRMt5DataSource` (+ `Bars()`,
`Mt5Bars()`, `Ticks()`, `History()`), `CSSRFutureGuard`,
`CSSRReplayController`, `CSSRRecordingSink`.

Shared state across sections (declared at `OnStart` scope, **not** per
section): `CSSRMt5DataSource src`, `SSRDataRange range`, `bool have_data`,
`long win_start`, `long win_end`. Every section from T2.5 down reuses the
same `src` and therefore the same `CSSRBarWindow` cache, so miss/hit
counters carry across sections.

| § | Claim | Notes |
|---|---|---|
| T2.1 | validator on clean data | asserts `last_msc` is the **close** of the final bar (`+ SSR_MSC_PER_MIN - 1`) |
| T2.2 | validator finds damage | duplicate, out-of-order, 5-min micro gap, 48-h session gap (must stay `IsClean()`), broken OHLC (must make `!IsUsable()`) |
| T2.3 | sanitize | strictly-increasing bars; ticks: equal stamps kept, backwards dropped (`4` of `5`) |
| T2.4 | discovery | `src.Open`, `RangeInto`, `IsOpen`, `available`, `first<last`, `bar_count>0` |
| T2.5 | bar provider + window | `ReadBars` ordered and inside the request; overlapping read adds no `Window().Misses()`; `HitRate()>0` |
| T2.6 | guard enforced inside the provider | arms a **stack-local** `CSSRFutureGuard`, `src.SetGuard`, past readable, future refused, straddling range trimmed, `src.DetachGuard()` then a read still works |
| T2.7 | tick provider honesty | `Ticks()` is NULL iff `!range.has_ticks`; ticks chronological; lower bound strictly half-open (matches `CSSRMt5TickProvider::ReadTicks`, which uses `cursor = lo + 1`) |
| T2.8 | end to end through Phase 1 | second `CSSRMt5DataSource src2` + `CSSRRecordingSink`; 120×`Pump(1000)`; compares clock against `ctrl.StartMsc()`, **not** the requested `win_start`, because `SetWindow` snaps the start down to an M1 open |
| T2.9 | closures are data | walks back ≤10 days for `day_of_week == 6`; `ReadBars >= 0`, `LastError()==SSR_OK`, empty range cached (`CSSRBarWindow::Ensure` sets `m_valid=true` on `got==0`) |
| T2.10 | Load-More-History probe | `hp.ExtendBackwards(sym, 5000)`; only asserts the bound never moves forward |

Writes to disk/chart: **nothing of its own**; `ExtendBackwards` asks the
terminal to download history.

### T3 — `SSR_T3_CustomSymbol.mq5`
Inputs: `InpSymbol=""`, `InpSlot=9`, `InpBars=400`, `InpWarmup=200`.

Owns a local helper that encodes ground truth #7:

```
long SeriesBars(const string sym, const ENUM_TIMEFRAMES tf)   // T3:48
  { read SERIES_BARS_COUNT; if 0 → up to 10 × (CopyRates(...,0,1) + reread + Sleep(100)) }
```

Collaborators: `SSRReplaySymbolName`, `SSRIsReplaySymbol`,
`SSRIsNameUsable`, `SSR_SYMBOL_NAME_MAX`, `CSSRCustomSymbolManager`,
`CSSRCustomSymbolSink`, `CSSRMt5DataSource`, `CSSRReplayController`,
`SSRBarOpenMsc`, `SSRPause`.

Long-lived state: one `CSSRCustomSymbolManager mgr` declared at
`OnStart` scope (T3:96) and a `bool created`. **Every section from T3.2
to T3.8 targets the same symbol name** `SSRReplaySymbolName(origin, 9)`,
because slot 9 is hard-wired through `mgr`, the T3.5 sink, the T3.6 sink
and the T3.7 pair.

| § | Claim | Notes |
|---|---|---|
| T3.1 | naming rules | `US30Cash.SSR1`; long origin loses its tail, keeps `.SSR2`; distinct slots |
| T3.2 | symbol lifecycle | digits / point / tick size / contract size cloned; `TRADE_MODE_DISABLED`; `SPREAD_FLOAT`; `START_TIME==0`; `EXPIRATION_TIME==0` |
| T3.3 | write + truncate | 300 synthetic M1 bars; M1>0; **M5>0 and H1>0 via `mgr.BarCount(tf)` which primes internally**; `Truncate(mid-bar)` lands on `SSRBarOpenMsc` |
| T3.4 | tick injection | 20 ticks at 1 s spacing; `st.ticks_added>0`; `mgr.SymbolTimeMsc()` within 1 s of the last tick |
| T3.5 | sink refuses out-of-order | fresh `CSSRCustomSymbolSink` on slot 9 → `Prepare` → `Create` + `ClearAll` (wipes T3.4's data and resets `m_last_emit_msc`); forward emit accepted, backward refused, `TruncateFrom` lowers the watermark, backward emit then accepted; `sink.Release()` destroys the symbol (`m_own_symbol` defaults `true`) |
| T3.6 | end to end into MT5 | 180×`Pump(1000)`; no replay data before play; `sink.EmitTicks()>0`; `SeriesBars()` for M1/M5/H1; `CopyRates` sweep over 5 timeframes for future leakage; backward `SeekTo` deletes bars; `ctrl.Release()` |
| T3.7 | leftover is adopted | `a.Create` (never torn down) then `second.Create` over it; same symbol; `ClearAll` → `BarCount(M1)==0`; **`second.Destroy()`** |
| T3.8 | teardown | `mgr.Destroy()`; `SymbolInfoInteger(name, SYMBOL_DIGITS)` must error or return 0; `mgr.OpenChartCount()==0` |

Writes to disk/chart: creates and deletes custom symbol
`<origin>.SSR9` under `SSRReplaySymbolPath()`, its M1 history and ticks;
`sink.Release()` also calls `m_cache.Invalidate(sym)`, removing
`SSReplay\cache\<sym>.manifest`.

### T4 — `SSR_T4_ChartIntegration.mq5`
Inputs: `InpSymbol=""`, `InpSlot=8`, `InpBars=400`, `InpWarmup=400`.
**All-or-nothing**: two early `return`s (lines 100, 126) skip the whole
file when the broker has no M1 or the load fails; both print the summary
first.

Owns two helpers:

```
class CTestObserver : public CSSRChartObserver      // T4:40
   int opened, closed, tf_changed, scrolled, followed;
   ENUM_TIMEFRAMES last_from, last_to;
   overrides: OnChartOpened / OnChartClosed / OnTimeframeChanged /
              OnUserScrolled / OnUserFollowed  — all pure counters

int FutureBars(const string sym, const long now_msc)  // T4:62
   CopyRates over {M1,M5,M15,M30,H1,H4} from now+60s to now+7d; sums n>0
```

Collaborators: `CSSRChartManager` (`Configure`, `OpenChart`, `Sync`,
`Count`, `InfoAt`, `Follow`, `Redraw`, `Redraws`, `RedrawsSkipped`,
`ScanLeaks`, `Leak`, `CloseOwned`, `SetObserver`, `ToString`),
`SSRChartInfo` (`symbol`, `follow`, `user_detached`, `last_offset`),
`CSSRLeakGuard` (`ReplayCharts`, `OriginInWatch`, `OriginCharts`,
`IsClean`, `Advice`, `ToString`), plus the T3 cast of engine classes.

Long-lived state at `OnStart` scope: `src`, `sink`, `ctrl`, `charts`,
`obs`, `rsym`, and `long cid` (the one chart the manager opens, T4:142).
Sections T4.2–T4.4 all `Skip` on `cid == 0`.

| § | Claim |
|---|---|
| T4.1 | registry: `Count()==1`, `obs.opened>=1`, `InfoAt(0)` on `rsym`, `follow` true by default |
| T4.2 | **the headline**: cycle M15→H1→M5→M15; replay time, state and `TicksEmitted()` unchanged; each timeframe has bars; `FutureBars()==0`; `obs.tf_changed>=4`; replay continues afterwards |
| T4.3 | partial H1 candle: `iTime(rsym,H1,0)` opened ≤ now, not yet closed; H1 high/low equal the M1 bars so far within `point*2` |
| T4.4 | auto-scroll: `Follow`, `CHART_AUTOSCROLL` on; `ChartNavigate(CHART_END,-50)` + **two** `Sync()`s → `user_detached`, `!follow`, autoscroll released, `obs.scrolled>=1`; `Follow` re-engages |
| T4.5 | repaint throttling: 50 × `Redraw()` → `>40` skipped; `Redraw(true)` always paints |
| T4.6 | leak guard: `ReplayCharts()>=1`; origin reachable; advice non-empty when dirty |
| T4.7 | close only what we opened: a hand-opened `ChartOpen(rsym, M15)` survives `CloseOwned()`; **the host chart survives** (`ChartSymbol(ChartID()) != ""`) |

Writes to disk/chart: creates custom symbol `<origin>.SSR8`, opens and
closes real charts on it, destroys the symbol at `ctrl.Release()` (T4:370)
via `sink.Release()`.

### T5 — `SSR_T5_Ui.mq5`
No broker. Draws real objects on **the script's own chart**.

Owns the only test double in the suite:

```
class CFakePort : public CSSRReplayPort            // T5:31
   SSRUiState state;                               // the test sets this directly
   counters: play pause reset step seek speed fidelity follow hide
             back restart jump
   captures: last_step_bars last_back_bars last_jump_msc last_speed last_fidelity
   void Clear();                                   // zeroes counters, not `state`
   overrides exactly the 13 pure virtuals of CSSRReplayPort:
     Name IsConnected ReadState Play Pause Reset StepBars SeekTo
     StepBack JumpTo Restart SetSpeedX100 SetFidelity
   Play/Pause/Reset also mutate state.status; SetSpeedX100/SetFidelity
   also mutate state.speed_x100 / state.fidelity
```

`CSSRReplayPort` (Ui/SSR_ReplayPort.mqh:304) has 13 pure virtuals and ~30
defaulted ones (trading, lines, sessions, statement export). `CFakePort`
implements **none** of the defaulted ones, so every trading, lines,
session and export verb the panel can reach returns `false` here.

Panel surface exercised: `Create(cid, port, "SSRT5_")`, `Render()`,
`Execute(cmd)`, `OnEvent(id, lparam&, dparam&, sparam&)`, `Writes()`,
`ObjectCount()` (→ `m_w.CountOwned()`, a real `ObjectsTotal`/`ObjectName`
prefix scan, Ui/SSR_Widgets.mqh:661), `IsCollapsed()`, `Destroy()`.
Two panels are created: `panel` with prefix `SSRT5_` (destroyed at T5:271)
and `panel59` with prefix `SSRT59_` (destroyed at T5:323).

| § | Claim |
|---|---|
| T5.1 | key→command table, 11 assertions |
| T5.2 | the speed ladder: size, ends, index of 1x, ascending, names render |
| T5.3 | "the panel holds no logic of its own": play/pause/reset/step/step10/follow reach the port |
| T5.4 | toggle reads `state.status` rather than remembering |
| T5.5 | speed up/down clamp at both ends; fidelity cycles FULL→SYNTH→BAR→FULL |
| T5.6 | "a click and a key take the same path" + foreign objects ignored |
| T5.7 | 20 identical `Render()`s cost `<= 2` label writes; a changed `clock_text` costs more |
| T5.8 | collapse toggles; `ObjectCount()>0`; `Destroy()` → `0` |
| T5.9 (first, line 276) | state colours distinct; FULL vs SYNTHETIC colours differ |
| T5.9 (second, line 289) | LEFT / PgUp reach `StepBack`; `JumpTo` / `Restart` "reach the port" |

Writes to disk/chart: chart objects under prefixes `SSRT5_` and
`SSRT59_`, both removed. No files (the panel's `SavePlace()` only fires on
a mouse drag, which no test triggers).

### T6 — `SSR_T6_History.mq5`
Inputs: `InpSymbol=""`, `InpSlot=7`.

Collaborators: `CSSRHistoryCatalog` (static `WarmupFor`,
`SuggestWindowBars`; instance `Attach`, `Scan`, `Available`, `BarCount`,
`FirstMsc`, `LastMsc`, `EarliestStart`, `Quote`, `SeedRate`,
`SetMeasuredSeedRate`, `ToString`), `SSRSeedQuote`, `SSRSessionRange` +
`SSRValidateRange`, `CSSRSeedCache` (`Save`, `Load`, `CanReuse`,
`Invalidate`, `SetEnabled`, `LastReason`), `SSRSeedManifest`,
`SSRSymbolSessionGap`, `CSSRDataValidator::LearnFrom`,
`CSSRCustomSymbolSink::SetOwnsSymbol/ReusedSeed/CacheReason`,
`SSRMicros`/`SSRElapsedMs`.

Long-lived state: `CSSRMt5DataSource src`, `CSSRHistoryCatalog cat`,
`bool have`.

| § | Claim |
|---|---|
| T6.1 | warmup arithmetic (`D1×200=288000`, `H4×500=120000`, `H1×500=30000`, `M15×500=7500`, `M1` 1:1); window scales, floor `>=5000`, ceiling `<=60000` |
| T6.2 | catalog scan; last available instant not in the future |
| T6.3 | `Quote(H1,300,2000)` → 18000/2000/20000; time and size estimated; oversized ask flagged; `SetMeasuredSeedRate` takes effect |
| T6.4 | range validation: empty rejected; a start with no warmup room refused **and the message contains the literal `"too early"`**; a workable range passes; `ReplayMinutes()==500` |
| T6.5 | manifest round trip; a manifest without bars is not reusable; `Invalidate` |
| T6.6 | cache rejects: different origin, wider request, reason recorded, disabled cache |
| T6.7 | end to end — run 1 seeds (`SetOwnsSymbol(false)` so the symbol survives), run 2 reuses; reused symbol carries no replay data; `second_ms <= first_ms * 1.5` |
| T6.8 | session gap learned from the symbol and adopted by the validator |

Writes to disk/chart: `SSReplay\cache\TESTORIGIN.SSR7.manifest` and
`SSReplay\cache\A.SSR7.manifest` (both `Invalidate`d); custom symbol
`<origin>.SSR7` created in T6.7 and destroyed when `k2.SetOwnsSymbol(true)`
precedes `c2.Release()`.

### T7 — `SSR_T7_Performance.mq5`
Inputs: `InpStart`, `InpBars=4320`, `InpBase=38000.0`. No broker.

Collaborators: `CSSRMetrics` (`IsCalibrated`, `TicksPerSec`,
`SeedBarsPerSec`, `RecordPump(total_us, emit_us, ticks, bars, deferred)`,
`RecordSeed(bars, ms)`, `UsPerTick`, `Snapshot`), `SSRPerfSnapshot`
(`calibrated`, `us_per_tick`, `pump_p50_ms`, `pump_p95_ms`,
`pump_max_ms`), `CSSRPumpBudget` (`Attach`, `SetBudgetMs`, `MaxTicks`,
`MaxBars`, `IsCalibrated`, `ToString`), `SSR_PUMP_MIN_TICKS`,
`SSR_PUMP_MAX_TICKS`, `CSSRFidelityPolicy` (`SetRequested`,
`SetTicksAvailable`, `SetLocked`, `Decide(delta_msc)`, `IsDegraded`,
`IsLocked`, `ReasonText`), `SSR_BULK_THRESHOLD_MSC`,
`CSSRHistoryCatalog::Quote`, plus the memory engine.

| § | Claim | Reads production code? |
|---|---|---|
| T7.1 | "the arithmetic that reshaped this phase" | **no** — three `Check`s over locals `8.0`, `50.0`, `60.0`, `2000.0`, `86400.0` |
| T7.2 | metrics measure and admit when they cannot | yes |
| T7.3 | the pump ceiling follows the measurement | yes; `MaxBars(8) == MaxTicks()/8` |
| T7.4 | fidelity degrades for three reasons: no tick history, bulk pump, user lock; reason strings contain `"tick history"` / `"catching up"` | yes |
| T7.5 | engine measures itself: uncalibrated before running, seed rate measured, calibrated after 400×`Pump(50)`, quote flips from estimate to measured | yes |
| T7.6 | a bulk pump is bounded and owes the rest: one `Pump(30*60*1000)` then 200×`Pump(50)`; ordered, no duplicates, nothing beyond the clock | yes |
| T7.7 | `budget.ToString()` says `UNCALIBRATED` then `measured` | yes |

Writes to disk/chart: **nothing**.

### T8 — `SSR_T8_Navigation.mq5`
Inputs: `InpStart`, `InpBars=4320`, `InpBase=38000.0`, `InpWarmup=120`.
File-scope `g_start`, `g_end`; `Wire(c, s, k)` loads as well as attaches.

Collaborators: `SSRKeyToCommand` + the `SSR_VK_*` / `SSR_CMD_*` tables,
`CSSRSnapshotStore` (`SetInterval`, `IsDue`, `Checkpoint`, `Count`,
`NearestAtOrBefore`, `DropFrom`), `SSRSnapshot` (`version`,
`taken_at_msc`, `state.symbol`, `state.status`, `clock`),
`CSSRReplayController` navigation surface (`StepBackward`, `JumpForward`,
`JumpTo`, `Bookmark`, `BookmarkCount`, `BookmarkLabel`, `GotoBookmark`,
`SavePosition`, `HasSavedPosition`, `PeekPosition`, `ResumePosition`,
`Restart`, `Snapshots`, `SnapshotText`), `CSSRPositionFile::Remove`,
`SSRBarOpenMsc`.

| § | Claim |
|---|---|
| T8.1 | LEFT / PgUp / J / B bound; RIGHT unchanged |
| T8.2 | checkpoint ring: 10 held, `NearestAtOrBefore` exact, nothing before the first, `DropFrom` drops exactly 3, newest survivor found |
| T8.3 | **the point**: `StepBackward` restores `TicksEmitted()` rather than zeroing it; nothing survives past the rewind point; stream ordered |
| T8.4 | forward jump goes through the bulk path: `JumpForward` returns bars>0, clock lands exactly, `SeedBarCount()` delta `>500`, tick delta `<` bar delta, nothing beyond the target, replay resumes |
| T8.5 | `JumpTo` picks the right direction; clamped past the end; not ERROR |
| T8.6 | bookmarks: one stored, label carries the time, `GotoBookmark` lands on the marked bar, index 5 refused; `JumpTo` before load → `SSR_ERR_INVALID_STATE` |
| T8.7 | save / resume: `PeekPosition` round-trips time, symbol and a non-PLAYING status; a fresh engine resumes onto the same bar |
| T8.8 | restart: clock back at start, READY, stream cleared, warmup survives, checkpoints cleared, **the user's bookmark survives**; a re-`Wire` clears bookmarks |

Writes to disk/chart: `SSReplay\positions\T8TEST.*` (see
`SSR_POSITION_DIR`), removed at T8:299.

---

## 3. Invariants the suite relies on

1. **`Check` never aborts.** Every section must therefore be safe to
   execute after its own precondition failed. Several are not (they
   dereference a just-asserted pointer).
2. **`CSSRRecordingSink` counters** (Core/Sinks/SSR_RecordingSink.mqh):
   `m_seed_bars` is `+=` only and `TruncateFrom` trims **ticks only**, so
   `SeedBarCount()` is a cumulative write counter, not a live bar count.
   `m_order_violations` counts strictly-backwards stamps;
   `m_duplicate_stamps` counts *equal* consecutive stamps (deliberately
   separate — real broker ticks share a millisecond).
   `TruncateFrom` returns `from_msc` verbatim (an in-memory sink can cut
   at an exact instant; the MT5 sink cannot).
3. **`SetDataMode` is decorative.** `CSSRReplayController::SetDataMode`
   (line 693) only writes `m_state.data_mode`; nothing reads it. T1's
   `SSR_DATA_MEMORY` and T2.8's `SSR_DATA_BROKER` change no behaviour, and
   T7/T8 omit the call entirely.
4. **One guard, shared.** `ctrl.Violations()` is `m_guard.Violations()`;
   `Attach`/`Load` push `GetPointer(m_guard)` into the source, so a direct
   `src.Bars().ReadBars(future)` bumps the controller's counter (T1.6
   depends on this).
5. **Slot numbers are the isolation mechanism.** T3=9, T4=8, T6=7 keep the
   three terminal-touching files off each other's custom symbol. Within a
   file the slot is shared by every section.
6. **`CSSRCustomSymbolManager::Create` calls `Destroy()` first** and
   `CSSRCustomSymbolSink::Prepare` calls `ClearAll()` after creating, so
   re-preparing the same slot silently wipes whatever an earlier section
   left there. `Prepare` also resets `m_last_emit_msc`.
7. **`CSSRCustomSymbolSink::Release` destroys the symbol** unless
   `SetOwnsSymbol(false)` was called (default `m_own_symbol = true`), and
   also `Invalidate`s the seed-cache manifest.
8. **Higher-timeframe bar counts must be primed** (ground truth #7).
   T3 honours this with its own `SeriesBars()` helper and with
   `mgr.BarCount()`; T4.2 reads `SERIES_BARS_COUNT` directly.
9. **`CSSRPanel::OnEvent` handles `CHARTEVENT_KEYDOWN`,
   `CHARTEVENT_OBJECT_ENDEDIT` and `CHARTEVENT_MOUSE_MOVE` only.**
   Object clicks are polled, not evented: `PollClicks()`
   (Ui/SSR_Panel.mqh:2445) scans `ObjectsTotal(m_chart, -1, OBJ_BUTTON)`
   for a prefix match with `OBJPROP_STATE` set, consumes the state, and
   applies a 200 ms repeat floor. The only mention of
   `CHARTEVENT_OBJECT_CLICK` in the panel is the comment at line 2878
   saying it is deliberately not handled.
10. **`CSSRPanel::Execute(SSR_CMD_RESET)` routes through
    `ResetWithConfirm()`**, which short-circuits straight to
    `m_port.Reset()` when `m_state.closed_trades + m_state.open_positions
    <= 0`. With a freshly `Init()`ed `SSRUiState` that is always the case.
11. **`SSRSpeedLadder` has 20 stops** (`SSR_SPEED_LADDER_SIZE 20`,
    Common/SSR_Types.mqh:275-303) and `SSR_SPEED_DEFAULT_IX` is 4 (=1x).
    `SSRSpeedLadderIndex` returns the **nearest** stop, never a default.
12. **`SSR_VK_R` is bound to `SSR_CMD_LINES_TOGGLE`** and reset lives on
    `SSR_VK_0` (Ui/SSR_Keys.mqh:162, 200).
13. **`CanReuse` short-circuits in order**: enabled → manifest → version →
    origin → coverage → bars exist. T6.5/T6.6 each reach the branch they
    name, so those assertions are not vacuous.
14. **`CSSRBarWindow` caches an empty range** (`got == 0` sets
    `m_valid = true`, Data/SSR_BarWindow.mqh:192-200), which is what T2.9's
    "empty range is remembered" depends on.
15. **`CSSRMt5TickProvider::ReadTicks` is half-open at the bottom**
    (`cursor = lo + 1`), which is what T2.7's strict `>` assertion
    depends on.

## 4. What the suite does not own

No shared runner, no shared assertion library, no fixture teardown
registry, no randomised/property testing, no negative test for a
half-written file, no multi-symbol (`CSSRReplayGroup`) coverage, no theme
or string-length coverage, no `Extent()`/`CheckFrame()` overflow
assertion, no 63-character `OBJPROP_TEXT` assertion, no `PollClicks`
coverage, no `SYMBOL_CHART_MODE` assertion. Those live (if anywhere) in
`tools/ssr_audit.py` A17–A21, in `Scripts/SSReplay/QA/`, or in the 17
measurement spikes — not here.

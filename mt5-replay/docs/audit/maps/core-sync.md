# core-sync — Architecture Map (SS Replay v125)

Subsystem: multi-symbol master clock, tick synthesis, future guard, snapshots / rewind,
position file, metrics, sink / source / observer contracts, recording sink, memory source.
All paths under `MQL5/Include/SSReplay/Core/`. Line numbers are from the v125 tree.

Legend for claims: **[CODE]** verified from source · **[INFER]** inference · **[DOC]** what a
comment claims about itself.

---

## 0. How the pieces fit (one paragraph)

`CSSRReplayController` (SSR_ReplayController.mqh, NOT in this audit's file set but the owner of
almost everything here) embeds one of each: `CSSRFutureGuard m_guard`, `CSSRTickSynthesizer
m_synth`, `CSSRMetrics m_metrics`, `CSSRSnapshotStore m_snaps`, `CSSRPositionFile m_posfile`
(controller lines 64-70). It holds non-owned pointers to a `CSSRDataSource` and a
`CSSRReplaySink`, and an array of up to 16 non-owned `CSSRTickObserver*`. `CSSRReplayGroup`
(SSR_MasterClock.mqh) sits ABOVE up to four controllers and owns the only clock that advances
from wall time; each controller is told the instant to reach via `PumpTo(target)`. The EA
(`SSReplayStandalone.mq5`) always drives the group, never a controller directly, even with one
symbol (EA line 1320 `g_group.Add(GetPointer(g_ctrl))`, line 2788 `g_group.Pump(delta)`).

Time everywhere is `long` epoch milliseconds ("msc"). `SSR_INVALID_TIME == -1`.
`SSR_MSC_PER_MIN == 60000L`. Bars are M1 only. A bar's open is minute-aligned; its last
instant is `open + 59999`.

---

## 1. CSSRReplayGroup — SSR_MasterClock.mqh (457 lines)

**Responsibility.** Keep N controllers on one replay clock. It does not own, load, or know
the symbols of its members [DOC lines 18-21, CODE line 40 `CSSRReplayController *m_member[4]; // not owned`].

**State it owns.**
| field | meaning |
|---|---|
| `m_member[SSR_MAX_STREAMS=4]`, `m_count` | non-owned controller pointers |
| `SSRReplayClock m_master` | THE clock: start/now/end/speed_x100/residue/steps |
| `m_aligned` | false until `Align()` succeeds; `Pump/Play/SeekAllTo/StepBars/StepBackward/Restart` refuse while false |
| `m_last_error`, `m_pause_reason` | text |
| `m_pumps`, `m_idle_pumps`(int), `m_group_pauses` | counters |

Writes nothing to disk or chart.

**Public surface and exact semantics.**
- `Add(c)` (64): refuses NULL / >4 / accepts duplicates silently; sets `m_aligned=false`.
- `Clear()` (79): drops members, `m_master.Init()`. Does NOT reset `m_pause_reason`/`m_idle_pumps`.
- `Align()` (106-163): window = INTERSECTION of member `[StartMsc,EndMsc]`; fails if any member
  `!TimelineValid()` or `hi<=lo`; `m_master.Configure(lo,hi)` (resets master now=lo, residue,
  steps; keeps speed); for each member: `SetSpeedX100(master.speed)`, `NarrowEndTo(hi)` if its
  end is later (permanent, never widened — controller 707-720), and `JumpTo(lo)` if
  `Now()!=lo`. Called at session start (EA 1328), after group Reset (GroupPort 435), in tests.
- `Pump(wall_delta_ms)` (179-226): `target = m_master.Advance(delta)` (integer speed math with
  residue, clamped at end); every member gets `PumpTo(target)`; sums emitted.
  **Idle gap skip** (206-219): if `emitted==0` and `AnyPlaying()` for 25 consecutive pumps,
  ask `NextBarAcross(master.now)`; if that bar is `> now + 2 min`, `PrintFormat("[SSR] market
  closed ...")` and `SeekAllTo(nb - 1)`. Then `PropagatePause()`.
- `PropagatePause()` (229-247): first member that is `PAUSED` with a non-empty `PauseReason()`
  pauses every PLAYING member; sets `m_pause_reason = "SYMBOL: reason"`; `m_group_pauses++`.
- `Play()` (258): `ClearPauseReason()` on all, then `Play()` each; true if any started.
- `Pause()` (272): pauses only PLAYING members.
- `SetSpeedX100(s)` (281): master then every member (so a detached stream keeps the speed).
- `SeekAllTo(t)` (296-323): `m_master.SeekTo(t)` (clamped) → every member `JumpTo(master.now)`
  → then **master follows member[0]**: `m_master.SeekTo(m_member[0].Now())` because a backward
  jump lands bar-granular. Returns false if any member failed but still moves the rest.
- `JumpTo(t)` == `SeekAllTo(t)`.
- `NextBarAcross(after)` (329): min over members of `NextTimelineBarOpen(after)`; INVALID if none.
- `StepBars(n)` (341-369): base = next M1 open after master.now, or the next EXISTING bar if
  later; `target = base + (n-1)*60000 - 1` clamped to end; master `SeekTo(target)`; each
  member: `Play()` if not playing, `PumpTo(t)`, `Pause()` if it was not playing. Forward is a
  pump (observers see the bars). Note `PumpTo` honours the pump budget cap, so a step can leave
  work "owed" (cursor behind clock) that the next pump delivers.
- `StepBackward(n)` (371): `SeekAllTo(BarOpen(master.now) - n*60000)`.
- `Restart()` (380): `SeekAllTo(start)`. (GroupPort.Reset instead calls each controller's
  `Reset()` then `Align()`; the group's own `Restart` is what the panel's Restart verb uses.)
- Queries: `AnyPlaying`, `AllCompleted` (false when empty), `MaxSkewMsc` (max−min `Now()` over
  members not COMPLETED; 0 if <2 live), `LiveCount`, `ToString`.

**Invariants relied on.**
1. Every member's `Now()` equals `master.now_msc` after any verb — the "zero skew" contract
   (T11.2 asserts `MaxSkewMsc()==0` after pumps, speed changes, jumps, steps, restart) [CODE].
2. Member ends are narrowed to the common `hi` so all complete on the same pump [CODE 150-151].
3. `PumpTo` is forward-only (`SSRReplayClock::AdvanceTo` refuses `t<=now`) so a member can
   never be pushed backward by a pump [CODE ReplayClock 126-139].
4. The idle skip assumes "the pause between two live ticks is never more than a minute of bar
   time" [DOC 202-204] — but the 2-minute test is measured from `master.now`, which is
   mid-bar whenever ticks are sparse (see finding core-sync-1).

**Callers.** EA (`g_group` global: Add/Align/Play/Pump/JumpTo/AnyPlaying/Now/StartMsc/EndMsc/
Clear), `CSSRGroupPort` (all transport verbs, MaxSkew, PauseReason), `CSSRSessionManager`
(Count/At/Now/StartMsc/EndMsc/SpeedX100/SeekAllTo/SetSpeedX100/MaxSkewMsc), `CSSRPublisher`.

---

## 2. CSSRTickSynthesizer — SSR_TickSynthesizer.mqh (217 lines)

**Responsibility.** One M1 bar → N ticks with a declared path: `close>=open`: O→L→H→C;
else O→H→L→C [CODE 127-128; header 8-9 agrees]. OHLC exact, order invented [DOC 11-15].

**State.** `m_digits`, `m_point`, `m_spread_abs` (absolute price), `m_ticks_per_bar` (min 4),
`m_spread_mode` (`SSR_SPREAD_RECORDED` default), and four spread statistics:
`m_bars_recorded`, `m_bars_fixed`, `m_spread_sum_pts`, `m_spread_max_pts`.

**Surface.** `Configure(digits, point)` (point<=0 → 10^-digits), `SetSpreadPoints/Abs`,
`SetSpreadMode`, `SetTicksPerBar(n>=4)`, `TicksForBar(fidelity)` (1 for BAR else N),
`Synthesize(bar, out[], offset)` → N, `SynthesizeClose(bar, out[], offset)` → 1, the four
`*Spread*` getters, `ResetSpreadCounters()`.

**Tick construction (Synthesize, 117-184).** Buffer must be pre-sized (returns 0 otherwise;
controller sizes `m_ticks` to `(nb-first)*per_bar` before the loop). Position along the
3-segment path `u = i*3/(n-1)`, `seg = floor(u)` capped at 2, linear interpolation. Stamps:
`time_msc = open_msc + i*59999/(n-1)` → strictly increasing for any n ≤ 59999, first tick
exactly at the open, last at `open+59999`; `time = msc/1000`. `bid = Norm(p)`, `ask =
Norm(p+spread)`, `last = bid`, `volume = 1`, `volume_real = 1.0`, `flags =
TICK_FLAG_BID|TICK_FLAG_ASK|TICK_FLAG_LAST` (the LAST flag is the belt to the BID-chart-mode
braces — DOC 154-173). The last tick is overwritten to land exactly on `close` (179-182).
`SynthesizeClose` = one tick at `open+59999` at close price, same flags.

**Spread source (SpreadFor, 54-67).** RECORDED and `bar.spread>0` → `bar.spread*point`, counted
in `m_bars_recorded`, sum/max updated; otherwise `m_spread_abs`, counted in `m_bars_fixed`.
`SpreadFor` runs once per `Synthesize`/`SynthesizeClose` call — i.e. once per (pump × bar), NOT
once per bar, because `EmitWindow` re-reads and re-synthesises the bar containing the clock on
every pump that advances (controller 380-442, ticks then trimmed to the window at 461-470). See
finding core-sync-2.

**Callers.** Only the controller (`m_synth`): `EmitWindow` 398/411/441-442, setters 648-661,
getters 653-660 (surfaced to the EA's `ReportSpreadOnce`, EA 2239-2300, and QA smoke 2985-3001).

---

## 3. CSSRFutureGuard — SSR_FutureGuard.mqh (156 lines)

**Responsibility.** Hold the horizon (= current replay time) and clamp/refuse/count any read
past it. Applied twice: controller clamps before asking, every provider re-checks [DOC].

**State.** `m_horizon_msc`, `m_armed`, `m_violations`, `m_last_violation_msc`.

**Surface.** `Arm(h)` (sets armed), `Disarm()`, `SetHorizon(h)` (no monotonic check; rewinds are
legitimate), `ResetCounters()`, `IsArmed/Horizon/Violations/LastViolation`,
`Allows(msc)` = `!armed || horizon<=0 || msc<=horizon` (INCLUSIVE), `Violation(msc)` (count),
`ClampRange(&from,&to)` (from>horizon → count + false; to>horizon → count + trim; returns
from<=to; disarmed → from<=to), `FilterTicks(ticks,count)` / `FilterRates(rates,count)`
(compact in place, count each dropped element; rates compared by OPEN time, so the bar that
contains the horizon PASSES — the controller's `ClipBar` handles the partial bar for observers,
and tick trimming handles it for the sink), `ToString`.

**Lifecycle in the controller [CODE].** `Load`: `Disarm()` for `Discover` (764), `Arm(start-1)`
for warmup seed (878), `Arm(start)` after (832). `Pump/PumpTo/StepBars`: `SetHorizon(now)`
BEFORE any read (1009/1084/1175). `SeekTo`: `SetHorizon(clamped)`. `JumpForward`:
`SetHorizon(target)` before the bulk read (1361). `RestoreSnapshot`: `Arm(clock.now)`.
`Reset`: `ResetCounters + Arm(start)`. `Release`: `Disarm`. If `Load` fails after 764 the guard
stays disarmed with the old horizon (state is ERROR; nothing reads).

**Who holds a pointer.** Every `CSSRProviderBase` (`m_guard`, not owned) and `CSSRDataSource`
(`m_guard`), pushed by `CSSRDataSource::SetGuard` and cleared by `DetachGuard` (controller
`Attach`, destructor, `Release`).

**Consumers of `Violations()`.** GroupPort sums them into `guard_violations` (UI vitals);
T1.4 asserts 0 after pumps; T1.6 asserts >0 after a deliberate future read.

---

## 4. SSRSnapshot — SSR_Snapshot.mqh (77 lines)

Plain struct, no pointers: `version` (string), `taken_at_msc`, `label`, `SSRReplayState state`,
`SSRReplayClock clock`, `SSRReplayCursor cursor`, `SSRReplayTimeline timeline`, and four
reserved trading fields (`open_positions`, `closed_trades`, `virtual_balance`,
`virtual_equity`) that NOTHING in the tree fills [CODE: only `Init()` touches them].
`IsValid()` = `taken_at_msc>0 && state.symbol!="" && clock.IsConfigured()`.

Produced by controller `TakeSnapshot` (1594-1604): copies the four structs as-is, so
`cursor.emitted_msc` may legitimately lag `clock.now_msc` when the pump budget deferred work.
Consumed by `RestoreSnapshot` (1610-1654): sink `TruncateFrom(taken_at)`, then the four structs
are assigned back, cursor rewound further if the sink cut earlier, `PublishRewind(actual)`,
`Arm(now)`, `OnSeek`, never left PLAYING.

---

## 5. CSSRSnapshotStore — SSR_SnapshotStore.mqh (203 lines)

**Responsibility.** 64-slot ring of automatic checkpoints (every `m_interval`, default 5 min
of REPLAY time, min 1 s) + up to 16 user bookmarks. Pure memory; writes nothing.

**State.** `m_ring[64]`, `m_count` (filled slots, never decremented), `m_head`, `m_interval`,
`m_last_msc` (newest checkpoint time), `m_marks[16]`, `m_mark_count`, `m_taken`, `m_restores`.

**Surface.** `ClearCheckpoints()` (keeps marks; used by controller `Reset`), `Clear()` (all;
`Load`), `SetInterval`, `IsDue(now)` (true if none yet, else `now-last>=interval`),
`Checkpoint(snap)` (ignores invalid; overwrite at head; `m_last_msc = taken_at`),
`NearestAtOrBefore(msc, out)` (linear scan over `m_count` slots, skips `taken_at<=0`),
`DropFrom(msc)` (Init() every slot with `taken_at>=msc`, recompute `m_last_msc`; does NOT
touch `m_count`/`m_head` — see core-sync-7), `NoteRestore`, `Mark(snap,label)`,
`GetMark(i,out)`, `MarkLabel(i)` = `"label  yyyy.mm.dd hh:mm:ss"`, `ClearMarks`, `ToString`.

**Who calls.** Controller: `IsDue/Checkpoint` after every `Pump`/`PumpTo` (1039-1044,
1112-1117; NOT in `StepBars`/`JumpForward`/`SeekTo`); `NearestAtOrBefore/NoteRestore/DropFrom`
in `StepBackward` (1451-1475); `Mark/GetMark/MarkLabel/Bookmarks` for bookmarks and session
save/restore (1531-1550, 1744-1754, 1815-1819); `Snapshots()` exposes the store to GroupPort
(`checkpoints = c.Snapshots().Count()`).

**Rewind algorithm the store enables [CODE controller 1432-1481].** target = bar-open − n bars,
clamped to start. If a checkpoint ≤ target exists: `RestoreSnapshot(cp)` then `JumpForward
(target)` (bulk bars, observers NOT told about those bars). Else plain `SeekTo(target)` with a
warning that counters restart. Then `DropFrom(now+1)`.

---

## 6. CSSRPositionFile — SSR_PositionFile.mqh (146 lines)

**Responsibility.** One `SSRSnapshot` on disk as key=value text so a session can resume where
it stopped. Directory `MQL5\Files\SSReplay\positions\`, file `<key>.pos` where key has
`\ / : .` replaced by `_` (nothing else sanitised). Key defaults to the ORIGIN SYMBOL
(controller 1556, 1573, 1588) — not slot- or session-qualified, so two slots replaying the same
symbol share one file [INFER from key choice].

**Format written (Save, 328-362)** with `FILE_WRITE|FILE_TXT|FILE_ANSI|FILE_SHARE_READ`, CRLF
lines: `version, label, symbol, taken, start, end, warmup, dfirst, dlast, now, speed, emitted,
ticks, bars, fidelity, datamode`. Refuses an invalid snapshot.

**Read (Load, 364-418).** `out.Init()`, `FileIsExist`, `FILE_READ|FILE_TXT|FILE_ANSI`,
line-by-line prefix match via `Field()` (`StringFind(line, k+"=")==0`), rebuilds
`clock.start/end`, `state.start/end/current`, forces `state.status = PAUSED`, validates with
`IsValid()`. `version` is read but never checked. `Exists`, `Remove`.

**Who calls.** Controller `SavePosition` (snapshot label "saved"), `PeekPosition`,
`ResumePosition` (→ `JumpTo(s.taken_at_msc)` only; counters in the file are NOT restored —
`Load` is "WHERE, not what"), `HasSavedPosition`. GroupPort `SavePosition` saves every stream;
`ResumePosition` resumes the primary then `SeekAllTo(c.Now())`. EA startup (1520-1540) peeks
the primary's file, resumes through the group only if ≥50 M1 bars remain ahead.

---

## 7. CSSRMetrics / SSRPerfSnapshot — SSR_Metrics.mqh (199 lines)

**Responsibility.** Self-measurement: 256-sample ring of pump wall time (ms), cumulative
pumps/ticks/bars, emit-only microseconds and ticks (for `UsPerTick`), deferred count, seed
throughput. Writes nothing.

**Surface.** `Reset`, `RecordPump(total_us, emit_us, ticks, bars, deferred)` (documented as
"one pump completed"; only pumps with `ticks>0` contribute to the cost figure), `RecordSeed
(bars, ms)`, `UsPerTick`, `TicksPerSec`, `SeedBarsPerSec`, `IsCalibrated` (≥16 samples and
some cost), `Percentile(p)` (copies + `ArraySort`s the ring on every call), `Snapshot(out)`
(three `Percentile` calls), `Pumps/Ticks/Deferred`.

**Who feeds it.** Controller `Pump`/`PumpTo` (1033, 1108) — NOTE they pass
`(int)m_cursor.bar_count`, the CUMULATIVE bar counter, as the per-pump `bars` argument (see
core-sync-5); `SeedWarmup` and `JumpForward` call `RecordSeed`. `CSSRPumpBudget` (not in this
set) reads `IsCalibrated/UsPerTick` to size the per-pump tick ceiling (12 ms budget, 32..32768
ticks; 4096 before calibration).

**Who reads it.** GroupPort (`calibrated`, `us_per_tick`, `pump_p95_ms` only), controller
`SeedBarsPerSec/PerfCalibrated`, T7. `SSRPerfSnapshot.bars` has no consumer.

---

## 8. Contracts — SSR_IDataSource.mqh (257), SSR_IReplaySink.mqh (111), SSR_ITickObserver.mqh (78)

### 8.1 Data source side
- `SSRDataRange {available, first_msc, last_msc, server_first_msc, bar_count, has_ticks}`;
  `CanExtendBackwards()`.
- `CSSRProviderBase`: `m_guard` (not owned), `Fail/Succeed`, `GuardRange(&from,&to)` (no guard →
  `from<=to`), `SetGuard/Guard/LastError/LastErrorText`.
- `CSSRHistoryProvider`: `Discover`, `Ensure(from,to)`, `ExtendBackwards(bars)`.
- `CSSRBarProvider`: `ReadBars(sym, from, to, out[])` = bars whose OPEN ∈ [from,to], ascending,
  count or −1; `ReadBarAt`; `BarCount`; **`NextBarOpen(sym, after)`** default implementation
  (150-165) = widening `ReadBars(after+1, after+span)` over 1h/1d/8d/40d — it goes THROUGH the
  guard, so from inside a gap it answers INVALID and (because `from>horizon`) counts a
  violation per span [CODE + FutureGuard 312-316]. The comment tells providers to override with
  a times-only read; `CSSRMt5BarProvider` does (Mt5Providers 302-321, `CopyTime` on the origin
  symbol, no guard). The memory provider does NOT override.
- `CSSRTickProvider`: `HasTicks`, `ReadTicks(sym, from, to, out[])` = ticks in (from, to]
  (half-open lower bound; the controller passes `lo-1`).
- `CSSRDataSource`: `Name/Open/Close`, `OnSessionPlanned(minutes)`, `History()/Bars()/Ticks()`
  (Ticks may be NULL), `Mode/IsOpen`, `DetachGuard()` and `SetGuard(g)` — both iterate through
  the three accessor calls, so a source whose `Ticks()` returns NULL at that moment leaves its
  tick provider untouched (core-sync-6).

### 8.2 Sink side (`CSSRReplaySink`)
`Prepare(symbol,digits,point)`, `SeedBars(bars[],n)` (bulk history — also how JUMPS write),
`EmitTicks(ticks[],n)` (n may be 0), `TruncateFrom(from)` → the instant actually cut (may be
coarser: the MT5 sink cuts on a bar open; caller must trust the return), `OnWarmupPlanned`,
`NeedsWarmup` (default true), `OldestMsc` (default −1 = "cannot know"), `OnStateChanged`,
`OnSeek`, `OnReset`, `Release`, `LastError*`. Invariant the MT5 sink enforces: a tick stamped
BEFORE the last emitted one is refused (`CustomSymbolSink` 313-320 `ticks[0].time_msc <
m_last_emit_msc` → fail); equal stamps are allowed; `TruncateFrom` moves the watermark to
`actual-1`.

### 8.3 Observer side (`CSSRTickObserver`)
`OnBarContext(bar, synthetic)` BEFORE that bar's `OnTicks` (controller publishes per-bar
segments in order, 501-513; the bar handed over is CLIPPED to what has happened, 269-310);
`OnTicks(ticks,n)` (in order, never repeated); `OnClock(now)` after every Pump/PumpTo (not
after StepBars/JumpForward/SeekTo); `OnRewind(msc)` (everything ≥ msc did not happen —
called from `SeekTo` backward, `Reset`, `RestoreSnapshot`, `NotifyRestored`);
`OnSessionStart(symbol,digits,point,start)`; `PauseRequested(&reason)` asked once per pump
after publish, must self-consume. Bulk-written stretches (`JumpForward`, the idle gap skip,
rewind-then-forward) are NOT published to observers [CODE 1369-1392].

---

## 9. CSSRRecordingSink — Sinks/SSR_RecordingSink.mqh (177 lines)

Test sink. Appends every emitted tick into `m_ticks[]` (`ArrayResize` to exact size on every
call, no reserve), counts seed bars, truncations, seeks, resets, state changes, and enforces
the two stream invariants: `time_msc < last` → `m_order_violations++`; `==` →
`m_duplicate_stamps++` (judged per fidelity by the test). `TruncateFrom` keeps `time_msc <
from` and returns `from` exactly. Assertion getters, `TickAt`, `CountAfter(msc)`,
`Fingerprint()` (FNV-1a over `time_msc` and `bid*1e5`). Used by T1, T7, T8, T9, T11, T12,
T13, T14, T15 and QA smoke.

## 10. CSSRMemoryDataSource — Sources/SSR_MemoryDataSource.mqh (303 lines)

`CSSRMemoryStore` (public `bars[]`, `ticks[]`, `symbol`; `FirstMsc`, `LastMsc` = last open +
59999, `LowerBound(msc)` binary search on open time — assumes sorted, never verified).
Three providers over one store: history (`Discover` fills the range, `server_first =
first`; `Ensure` true if any bars; `ExtendBackwards` returns the unchanged first),
bars (`ReadBars` guard-clamped, binary-searched, contiguous copy; `ReadBarAt` exact-open match
with `Allows` check; `BarCount`; inherits the generic `NextBarOpen`), ticks (`HasTicks` ignores
the range; `ReadTicks` guard-clamped, two LINEAR passes over the whole tick store per call).
`CSSRMemoryDataSource` owns the store by value and the providers by `new`/`delete`; `Open`
succeeds only if bars are loaded; `Ticks()` returns NULL while `TickCount()==0` ("degrade,
don't pretend"); `LoadBars/LoadTicks` copy in; `Store()` exposes the store. Mode
`SSR_DATA_MEMORY`. No test in the tree calls `LoadTicks` (grep), so FULL_TICK through this
source is exercised only as a degradation to SYNTHETIC.

---

## 11. Cross-cutting invariants later designers must keep

1. **Emit range is half-open `(cursor.emitted, clock.now]`**; the cursor may lag the clock
   (deferred work) but never lead it. Both are copied verbatim into snapshots.
2. **Tick stamps are non-decreasing across the whole session** in the sink's eyes; the MT5
   sink hard-fails on a regression and resets its watermark only through `TruncateFrom`.
3. **`TruncateFrom`'s RETURN value is the truth**, not the request (bar-granular on MT5).
4. **A bar's open time never changes** when it is republished partially (ClipBar keeps
   `bar.time`), which is how observers recognise "same bar growing".
5. **Bulk writes bypass observers.** Anything that reaches the sink via `SeedBars` (warmup,
   jump, gap skip, rewind-forward) is invisible to the trading engine.
6. **`bar_count` / `BarsConsumed()` counts (pump × bar) synthesis events, not bars** (controller
   `bars_used++` per bar per pump, 472; cursor `bar_count += bars`, 255). It is displayed by the
   panel ("BARS"), summed by GroupPort, persisted in `.pos` files and session files, and used
   by `RestoreFrom` as the fallback consistency check for fingerprint-less files (1858-1863).
   Any design that treats it as a bar count inherits that error.
7. **The group's master follows member[0]** after a backward seek; other members may differ
   only through their sinks' truncation granularity, and `MaxSkewMsc` is the alarm.
8. **The spread statistics are per-synthesis, not per-bar** (see 2 and core-sync-2).

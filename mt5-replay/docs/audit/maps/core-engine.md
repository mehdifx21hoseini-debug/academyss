# core-engine — Architecture Map (SS Replay v125)

Scope: `MQL5/Include/SSReplay/Core/` — `SSR_ReplayController.mqh`, `SSR_ReplayClock.mqh`,
`SSR_ReplayTimeline.mqh`, `SSR_ReplayCursor.mqh`, `SSR_ReplayState.mqh`, `SSR_PumpBudget.mqh`,
`SSR_FidelityPolicy.mqh`. Cross-referenced (not audited here): `SSR_FutureGuard.mqh`,
`SSR_TickSynthesizer.mqh`, `SSR_Metrics.mqh`, `SSR_Snapshot(Store).mqh`, `SSR_IDataSource.mqh`,
`SSR_IReplaySink.mqh`, `SSR_MasterClock.mqh`, `Mt5/SSR_CustomSymbolSink.mqh`.

All times are epoch **milliseconds** (`long`). `SSR_INVALID_TIME == -1`. `SSR_MSC_PER_MIN == 60000`.
Every helper (`SSRBarOpenMsc`, `SSRNextBarOpenMsc`, `SSRClampMsc`, `SSRToMsc`) lives in `Common/SSR_Time.mqh`.

## 0. Who drives the engine (call graph, production)

```
SSReplayStandalone.mq5 (OnTimer, InpPumpMs=40)
  delta = wall ms since last timer, capped at max(4*InpPumpMs,100)      [host 2760]
  g_group.Pump(delta)                 CSSRReplayGroup (SSR_MasterClock.mqh)
     m_master.Advance(delta)  -> target instant
     for each stream: ctrl.PumpTo(target)                               [ctrl 1072]
     idle>=25 pumps & AnyPlaying -> NextBarAcross -> SeekAllTo(nb-1)    (weekend skip)
     PropagatePause()
  UI (SSR_Panel -> SSR_GroupPort -> CSSRReplayGroup):
     StepBars(n)     -> group: master.SeekTo(target); per stream Play();PumpTo(t);Pause()
     StepBackward(n) -> group.SeekAllTo -> ctrl.JumpTo(t)  -> ctrl.StepBackward
     JumpTo(msc)     -> group.SeekAllTo -> ctrl.JumpTo(t)  -> JumpForward | StepBackward
     Restart()       -> group.SeekAllTo(master.start)      (NOT ctrl.Reset)
     Bookmark / ResumePosition / SavePosition -> ctrl directly
  SessionManager: ctrl.SaveInto(f) / ctrl.RestoreFrom(f, nth, warn) / ctrl.NotifyRestored()
  Publisher (IPC): group.StepBars / StepBackward / JumpTo / SetSpeedX100
Tests (T1, T7, T8, T9) call ctrl.Pump(delta), StepBars, SeekTo, StepBackward directly.
```
`ctrl.Pump()` (wall-delta form) is **not** used by the host; production always goes through `PumpTo(target)`.
The stream's own `m_clock.speed_x100` is therefore irrelevant to playback speed in production (the master
clock scales the delta); it is still persisted per stream and shown nowhere (GroupPort reads `m_group.SpeedX100()`).

## 1. `SSRReplayClock` (struct, plain data) — the only source of time

State: `start_msc, now_msc, end_msc, speed_x100 (100 == 1x), residue (0..99), steps`.
- `Configure(start,end)`: requires `0 < start < end`; sets now=start, residue=0, steps=0.
- `IsConfigured()`: `start>0 && end>start && now>=start`.
- `SetSpeedX100(s)`: clamps to >=1, **resets residue**.
- `Advance(wall_ms)`: `scaled = wall*speed+residue; adv=scaled/100; residue=scaled%100; now+=adv`, clamp to end (residue=0 at end), `steps++`. Pure integer.
- `AdvanceTo(t)`: forward-only; `t<=now` is a no-op that does NOT bump steps; clamps to end; residue=0.
- `SeekTo(t)`: clamps into [start,end] either direction; residue=0; steps++.
- `Shift(d)`, `Rewind()` (now=start, steps=0), `IsCompleted()` (`now>=end`), `Remaining/Elapsed/Progress`.
Invariants relied on: `now` is monotone within a pump; `end` may be lowered later by `NarrowEndTo` (controller writes `m_clock.end_msc` directly).
Snapshotted whole (speed included) by `TakeSnapshot`; restored whole by `RestoreSnapshot`.

## 2. `SSRReplayTimeline` (struct)

State: `data_first_msc, data_last_msc` (what the source holds), `warmup_first_msc`, `start_msc, end_msc` (replay window).
- `SetDataBounds(first,last)`.
- `SetWindow(a_start, a_end)`: **snaps start DOWN to an M1 open** (`SSRBarOpenMsc`), clamps into data bounds; `a_end<=0` means data_last; `end` clamped to `[start, data_last]`; returns `end>start`.
- `SetWarmupBars(bars)`: `warmup_first = start - bars*60000` (**calendar minutes, not bars**), floored at data_first.
- `WarmupBarsFor(tf, visible)` static: `visible * PeriodSeconds(tf)/60` (also calendar).
- `IsValid()`: `start>0 && end>start && data_first>0 && data_last>=end`.
- `Contains`, `Span`, `WarmupSpan`, `ToString`.
Invariant relied on everywhere: `start_msc` is M1-aligned (so a rewind to start never cuts into warmup).

## 3. `SSRReplayCursor` (struct) — how far the sink has been fed

State: `emitted_msc` (last instant handed to the sink, inclusive), `bar_msc` (last consumed M1 open), `tick_count`, `bar_count`.
- `RewindTo(msc)`: `emitted = msc-1` (so the next pump emits `msc` itself), counters zeroed.
- `IsPositioned()`: `emitted != -1` (note: `RewindTo(0)` would un-position the cursor).
- `PendingRange(now, &from, &to)`: `from=emitted+1, to=now`, true iff `from<=to`. The emit window is **(emitted, now]**.
- `Advance(to, ticks, bars)`: `emitted = max(emitted,to)`; counters += .
- `NoteBar(open)`.
Contract with the sink: sink `TruncateFrom(x)` deletes **[x, ∞)** and returns the actual cut `a` (MT5 sink floors to the M1 open); the controller must then `RewindTo(a)` so the cursor claims exactly what survives. `SeekTo`/`Reset` do this; `RestoreSnapshot` only does it when `a < emitted` (see finding core-engine-7).

## 4. `SSRReplayState` (struct) + `SSRCanTransition`

Published/persisted copy of the engine: `symbol, base_timeframe(M1), start/current/end, data_first/last, status, speed_x100, data_mode, fidelity, last_error(+text), ticks_emitted, bars_consumed`. Refreshed by `Controller::Publish()` from clock/timeline/cursor. Copied whole into snapshots and restored whole (so `status`, `fidelity`, `speed_x100`, `last_error` all travel with a checkpoint).

State machine (`SSRCanTransition`): same->same OK; any -> RESETTING OK; any -> ERROR OK.
IDLE->LOADING; LOADING->READY|IDLE; READY->PLAYING|PAUSED|LOADING|COMPLETED; PLAYING->PAUSED|COMPLETED|READY;
PAUSED->PLAYING|READY|COMPLETED|LOADING; RESETTING->IDLE|READY|LOADING; COMPLETED->PAUSED|READY|LOADING; ERROR->(only RESETTING).
`Controller::Transition` logs, notifies `sink.OnStateChanged(from,to)` (only the test RecordingSink overrides it), and records `SSR_ERR_INVALID_STATE` on refusal. `RestoreSnapshot` bypasses `Transition` (assigns `m_state` and forces PLAYING->PAUSED by direct write).

## 5. `CSSRPumpBudget` — per-pump work ceiling

Owns: `m_metrics*` (not owned), `m_budget_ms` (default 12.0, min 1.0), `m_fallback_ticks=4096`, `m_deferrals`.
- `MaxTicks()`: uncalibrated (metrics NULL, `<16` pumps, or no emit cost yet) -> 4096; else `budget_ms*1000/us_per_tick` clamped to [32, 32768].
- `MaxBars(tpb)`: `MaxTicks()/tpb`, min 1.
- `NoteDeferral()`, `IsCalibrated()`, `ToString()` ("measured"/"UNCALIBRATED").
Used only in `EmitWindow` bar path. The host never calls `SetPumpBudgetMs` (12 ms in production). The ceiling is derived from wall-clock measurement -> the cap value is non-deterministic across machines.

## 6. `CSSRFidelityPolicy` — requested vs effective fidelity

State: `m_requested, m_effective, m_reason (USER|NO_TICK_DATA|BULK|LOCKED), m_locked, m_ticks_available, m_degradations`.
- `SetRequested(f)`: sets both requested and effective.
- `SetLocked(on)`, `SetTicksAvailable(on)`.
- `Decide(owed_msc)` (called once per `EmitWindow`): locked -> requested; else FULL_TICK && !ticks_available -> SYNTHETIC (reason NO_TICK_DATA, **bulk check skipped**); else `owed >= 600000` (10 min) -> BAR (BULK); else requested. `m_degradations++` on a change away from requested.
`m_ticks_available` is set once at `Load` from `range.has_ticks` (MT5 Discover probes only the LAST 24 h of held data) and to false if `source.Ticks()==NULL`. Nothing ever sets it per window. `LockFidelity` is not called by the host.

## 7. `CSSRReplayController` — the engine

Owns (by value): `m_state, m_clock, m_timeline, m_cursor, m_guard (CSSRFutureGuard), m_synth (CSSRTickSynthesizer), m_metrics, m_budget, m_fidelity, m_snaps (CSSRSnapshotStore: 64 checkpoints every 5 replay-min + 16 bookmarks), m_posfile (CSSRPositionFile -> MQL5/Files/SSReplay/positions/)`.
Not owned: `m_source (CSSRDataSource*)`, `m_sink (CSSRReplaySink*)`, `m_log`, `m_obs[16] (CSSRTickObserver*)`.
Buffers: `m_bars[]` (1024 reserved), `m_ticks[]` (8192 reserved), `m_seg[]`.
Other: `m_digits, m_point, m_auto_pause(true), m_pause_reason, m_auto_pauses, m_pump_emit_us, m_pump_deferred, m_warmup_bars`.
Writes to disk: only via `m_posfile.Save` (SavePosition) and `SaveInto(CSSRSessionFile&)` (session file, written by SessionManager). Writes nothing to any chart. All market output goes through `m_sink` (Prepare/SeedBars/EmitTicks/TruncateFrom/OnSeek/OnReset/Release).

### Public surface (grouped)
Wiring: `SetLog, Attach(source,sink)` (pushes `&m_guard` into the source's providers; `DetachGuard` on swap/destroy), `AddObserver` (max 16, refuses loudly), `ClearObservers`.
Settings: `SetSymbolSpec, SetSpreadPoints, SetSpreadMode, SetTicksPerBar (min 4), SetWarmupBars, SetSpeedX100, SetFidelity, LockFidelity, SetPumpBudgetMs, SetDataMode, SetAutoPause, NarrowEndTo(end)` (narrow only; edits timeline+clock end directly).
Lifecycle: `Load(symbol,start,end)`, `SeedWarmup()`, `RepairWarmupIfLost()`, `Reset()`, `Restart()` (=Reset), `Release()`.
Transport: `Play, Pause, Pump(wall_ms), PumpTo(target)`.
Navigation: `StepBars(n)`, `SeekTo(msc)`, `JumpForward(msc)`, `StepBackward(n)`, `JumpTo(msc)` (unified: backward -> StepBackward(ceil bars), forward -> JumpForward), `NextTimelineBarOpen(after)`.
Snapshots: `Bookmark, GotoBookmark, BookmarkLabel/Count, SavePosition, PeekPosition, ResumePosition, HasSavedPosition, TakeSnapshot, RestoreSnapshot, NotifyRestored, Snapshots()`.
Persistence: `SaveInto(f)`, `RestoreFrom(f,nth,warning)`, `FingerprintUpTo(to,fp)`.
Read-only: `State(), Status, Now, Progress, StartMsc, EndMsc, TimelineValid, Timeline, Cursor, TicksEmitted, BarsConsumed, Violations, Fidelity (m_state.fidelity), EffectiveFidelity, FidelityDegraded/Reason, SpeedX100, PerfInto, PerfCalibrated, SeedBarsPerSec, BudgetText, Spread* (from synth), PauseReason, AutoPauses`.

### `Load(symbol, start, end)` — IDLE/READY/PAUSED/COMPLETED -> LOADING -> READY
1. requires source+sink; `Transition(LOADING)`; `source.Open(symbol)` if not open.
2. `m_guard.Disarm()`; `hp.Discover(symbol, range)` (must see the full extent). **Guard stays disarmed if any later step fails** (state ERROR).
3. `timeline.Init/SetDataBounds/SetWindow(start,end)`; `SetWarmupBars(m_warmup_bars)`; `source.OnSessionPlanned(minutes)`.
4. `hp.Ensure(symbol, warmup_first|start, end)` (guard disarmed, deliberate).
5. `clock.Configure(start,end)`; `clock.SetSpeedX100(m_state.speed_x100)`; `fidelity.SetRequested(m_state.fidelity)`; `fidelity.SetTicksAvailable(range.has_ticks)`; `metrics.Reset()`.
6. `sink.OnWarmupPlanned(warmup_first|start, start-1)`; `sink.Prepare(symbol,digits,point)`.
7. `SeedWarmup()`: skip if `m_warmup_bars<=0` or `!sink.NeedsWarmup`; else `guard.Arm(start-1)`, `ReadBars[warmup_first, start-1]`, `FilterRates`, `sink.SeedBars`, `metrics.RecordSeed`.
8. `cursor.Init(); cursor.RewindTo(start)`; `guard.ResetCounters(); guard.Arm(start)`; `snaps.Clear()` (bookmarks too); observers `OnSessionStart(symbol,digits,point,start)`; `Publish(); Transition(READY)`.

### `Pump(wall_ms)` / `PumpTo(target)` — only when PLAYING
`before=now; now=clock.Advance(wall)|AdvanceTo(target); guard.SetHorizon(now)`; if `now>before` and `cursor.PendingRange(now,lo,hi)` -> `EmitWindow(lo,hi)` (-1 -> ERROR). Then observers `OnClock(now)`; `Publish()`; `metrics.RecordPump(total_us, m_pump_emit_us, emitted, (int)cursor.bar_count, deferred)`; checkpoint if `snaps.IsDue(now)` (first pump after Load/Reset always; then every 5 replay-min); `CheckObserverPause()` (any observer `PauseRequested` -> PAUSED, reason kept); `clock.IsCompleted()` -> COMPLETED.

### `EmitWindow(from, to)` — the emit kernel; returns ticks emitted or -1
1. `guard.ClampRange(lo,hi)`; `fid = fidelity.Decide(hi-lo)`.
2. FULL_TICK: `tp=source.Ticks()`; NULL -> `SetTicksAvailable(false)`, re-Decide; else `ReadTicks(sym, lo-1, hi)` ((lo-1,hi] == [lo,hi]), `guard.FilterTicks`, `sink.EmitTicks` (timed into `m_pump_emit_us`), `PublishTicks`, `cursor.Advance(hi, n, 0)`, return. **No budget cap, no PublishBar, no NoteBar, and n==0 is silently consumed.**
3. Bar path: `bar_lo=floor(lo), bar_hi=floor(hi)`; `nb=ReadBars(sym,bar_lo,bar_hi)` (whole M1 bars whose open is in range — the bar containing `hi` arrives whole); `FilterRates`; `nb==0` -> `cursor.Advance(hi,0,0)`, return 0.
4. `cap = budget.MaxBars(TicksForBar(fid))`; `if nb>cap: nb=cap; NoteDeferral; m_pump_deferred=true` (**overwrites nb, so the later "stop short" test can never fire — finding core-engine-1**).
5. `first` = index of first bar with open >= bar_lo (always 0 by provider contract). `need=(nb-first)*per_bar`; resize `m_ticks`.
6. For each bar i: `Synthesize`/`SynthesizeClose` at `base=written`; `shown=ClipBar(bar, base, w, hi)` (rebuild O/H/L/C from synthesised ticks `<= hi`, ignoring `lo`, so the forming bar never shows its future H/L/C; whole bar returned when `hi >= open+59999`); trim ticks to `[lo,hi]` in place (`keep`); `bars_used++` **unconditionally** (finding core-engine-5); `cursor.NoteBar`; if `keep>0` record segment `(base, keep, shown)`; `written+=keep`.
7. `guard.FilterTicks(m_ticks, written)` (second layer; if it drops anything the interleaved publish is abandoned); `sink.EmitTicks(m_ticks, written)` (timed); observers get, per segment, `OnBarContext(shown, synthetic=true)` then `OnTicks(segment)`; else flat `PublishTicks`.
8. `consumed_to = hi`; `if bars_used>0 && first+bars_used < nb` -> `consumed_to = last consumed bar open + 59999` (dead: see step 4); `cursor.Advance(consumed_to, written, bars_used)`.
Synthetic tick stamps for a bar: `open + i*59999/(n-1)`, i=0..n-1 (n=8 default: 0, 8571, 17142, 25714, 34285, 42856, 51427, 59999 ms); BAR fidelity: one tick at `open+59999`.

### `StepBars(n)` — READY/PAUSED/PLAYING
`base = SSRNextBarOpenMsc(now)` (open of the bar after the one containing `now`); `nb = NextTimelineBarOpen(now)` (first existing bar strictly after now, INVALID past end); `base = max(base, nb)`; `target = base + (n-1)*60000 - 1` clamped to end; `clock.SeekTo(target); guard.SetHorizon`; `EmitWindow(PendingRange)`; READY -> PAUSED; end -> COMPLETED. Lands on `xx:59.999`. (finding core-engine-2: from `xx:59.999` the formula yields `target == now`.) The group's `StepBars` uses the identical formula on the master clock and then `Play();PumpTo(t);Pause()` per stream.

### `SeekTo(target)` (tests/StepBackward fallback only)
Clamp into window; backward -> `actual=sink.TruncateFrom(clamped)`, `cursor.RewindTo(actual)`, `PublishRewind(actual)`; `clock.SeekTo(clamped); guard.SetHorizon; sink.OnSeek`; `EmitWindow(PendingRange(clamped))` (fills the hole between the coarse cut and the target, or the skipped-forward stretch, with ticks); COMPLETED && clamped<end -> PAUSED.

### `JumpForward(target)` — bulk fast-forward (used by JumpTo, StepBackward, RestoreFrom, group Align/SeekAllTo/weekend skip)
Requires clock configured + timeline valid; `target<=now` -> 0. `guard.SetHorizon(target)`; `lo=emitted+1; bar_lo=floor(lo); last_bar=floor(target)`; if `last_bar>bar_lo`: `ReadBars[bar_lo, last_bar-1]` -> `FilterRates` -> **`sink.SeedBars(bulk)`** (`metrics.RecordSeed`), `cursor.Advance(last_bar-1, 0, n)`. Then `clock.SeekTo(target)`; `EmitWindow(last_bar, target)` for the partial bar (ticks trimmed to target); `sink.OnSeek(target)`; `RepairWarmupIfLost()` (re-seeds warmup if `sink.OldestMsc() > warmup_first`); COMPLETED if at end. **Observers receive nothing for the bulk bars** (only the partial bar's segment) — finding core-engine-3. Does not check `status` (works in READY/PAUSED/PLAYING/COMPLETED/ERROR).

### `StepBackward(n)`
`here=floor(now); target=max(here-n*60000, start)`; `target>=now` -> true. If `snaps.NearestAtOrBefore(target, cp)`: `RestoreSnapshot(cp)` then `JumpForward(target)` if `target>now`. Else warn "counters will restart" and `SeekTo(target)`. `snaps.DropFrom(now+1)`; COMPLETED|READY -> PAUSED. Backward navigation is therefore **bar-granular** (lands on an M1 open) and, via the checkpoint path, replays up to 5 min of bars **in bulk**.

### `RestoreSnapshot(snap)`
`actual = sink.TruncateFrom(snap.taken_at_msc)`; assigns `m_state, m_clock, m_cursor, m_timeline` from the snapshot; `if actual < cursor.emitted -> RewindTo(actual)`; `PublishRewind(actual)`; `guard.Arm(clock.now)`; `sink.OnSeek`; `Publish`; PLAYING -> PAUSED (direct write). Not restored: `m_fidelity` policy object, `m_synth` counters, `m_metrics`, `m_auto_pause`, observers' own state (they get `OnRewind`).

### `Reset()` (host uses it only via GroupPort "new session" path; panel Restart goes through the group)
RESETTING; `sink.TruncateFrom(start)` -> cut; `sink.OnReset`; `clock.Rewind`; `cursor.Init/RewindTo(cut)`; `PublishRewind(cut)`; `guard.ResetCounters/Arm(start)`; `snaps.ClearCheckpoints` (bookmarks kept); READY|IDLE. No EmitWindow.

### `SaveInto` / `RestoreFrom`
Saves window, warmup, `now`, `speed`, cursor (`emitted, ticks, bars`), fidelity, data_mode, status, auto_pause, a bar fingerprint of `[start, now]` (`FingerprintUpTo`: reads bars whose open <= now, i.e. includes the forming bar whole), and bookmarks (`taken_at|label`).
Restore (caller must have `Load`ed the same window first): checks `origin` and that `now` is inside the window; `SetSpeedX100`, `SetFidelity`, `m_auto_pause`; re-adds bookmarks as places; **`JumpTo(want_now)`** (bulk forward); then re-fingerprints and returns a warning text on mismatch (or, for files without a fingerprint, compares `bars` with `cursor.bar_count`). The cursor fields in the file are NOT read back (the comment saying otherwise is stale).

## 8. Invariants the code relies on (and where they are enforced)
- Guard horizon == `clock.now` at every read; moved before every read in Pump/PumpTo/StepBars/SeekTo/JumpForward; `Arm` only at Load/Reset/RestoreSnapshot.
- The sink never receives a tick stamped `> now` (ClipBar + trim + FilterTicks) and never a tick out of order (MT5 sink refuses `ticks[0].time_msc < m_last_emit_msc`).
- The cursor is the single truth for "what the sink holds up to"; after any truncate it is re-seated from the sink's returned cut.
- `timeline.start_msc` M1-aligned; sink cuts land on M1 opens; `StepBackward` lands on M1 opens.
- Observers see `OnBarContext(bar)` immediately before that bar's own ticks (segments), never a later bar's context first; the bar handed over is clipped to what has happened.
- Determinism: given identical target/delta sequences the emitted stream is identical — **except** that the per-pump cap comes from wall-clock measurement (`CSSRMetrics`).
- One checkpoint per 5 replay-minutes, taken after emission (so `snap.cursor.emitted == snap.taken_at_msc`).

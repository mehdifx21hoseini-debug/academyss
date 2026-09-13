# Subsystem map: mt5-symbol (custom symbol lifecycle, seed cache, naming, time, shared types)

Build v125. Files (all under `MQL5/Include/SSReplay/`):
`Mt5/SSR_CustomSymbolManager.mqh` (812 lines), `Mt5/SSR_CustomSymbolSink.mqh` (433), `Mt5/SSR_SeedCache.mqh` (216),
`Common/SSR_SymbolNaming.mqh` (90), `Common/SSR_Time.mqh` (99), `Common/SSR_Types.mqh` (366), `Common/SSR_Platform.mqh` (47).
Line numbers below are exact as of v125.

Dependency direction: Types <- Time/Platform/SymbolNaming (Common, no MT5 API except Platform) <- SeedCache <- CustomSymbolManager <- CustomSymbolSink (implements `CSSRReplaySink` from `Core/SSR_IReplaySink.mqh`).

---------------------------------------------------------------------------------------------------
## 1. SSR_Types.mqh - vocabulary (no dependencies except SSR_Build.mqh)

Constants: `SSR_MSC_PER_SEC/MIN/HOUR/DAY` (all `((long)N)` - cast at definition after an int-overflow defect), `SSR_INVALID_TIME (-1)`, `SSR_VERSION "0.1.0"` (NEVER bumped in 169 commits - only commit dc87fa3 touches it; the build stamp lives separately in `SSR_Build.mqh` as `SSR_BUILD "v125 2026-09-12  fewer"`).

Time convention (documented): all internal time is `long` milliseconds since epoch (`MqlTick.time_msc` basis); `datetime` only at API/human boundaries.

Enums: `ENUM_SSR_STATE` (IDLE, LOADING, READY, PLAYING, PAUSED, RESETTING, COMPLETED, ERROR), `ENUM_SSR_FIDELITY` (FULL_TICK, SYNTHETIC_TICK, BAR), `ENUM_SSR_SPREAD` (RECORDED, FIXED), `ENUM_SSR_DATA_MODE` (MEMORY, BROKER, CSV, EXTERNAL_TICK), `ENUM_SSR_SPEED` (values = speed*100: 25,50,100,200,500,1000,2500,5000, MAX=100000 - NOTE 2500 and 5000 are NOT on the 20-stop ladder; only SSR_SPEED_10/50 are used outside this file, by tests T1/T11/T5), `ENUM_SSR_ERR` (OK, INVALID_ARG, INVALID_STATE, NO_SOURCE, NO_SINK, NO_DATA, OUT_OF_RANGE, FUTURE_ACCESS, LOAD_FAILED, SINK_FAILED, NOT_SUPPORTED, INTERNAL).

Name helpers: `SSRStateName`, `SSRFidelityName`, `SSRFidelityShort` (chip: FULL/SYNTH/BAR), `SSRDataModeName`, `SSRErrName`, `SSRSpreadModeName` (user-facing words are English literals; A19 exempts these because they are not drawn directly).

Speed ladder (lines 275-342): `SSRSpeedLadder(i)` 20 stops {10,25,50,75,100,150,200,300,400,500,700,1000,1500,2000,3000,5000,7500,10000,20000,MAX}; `SSR_SPEED_LADDER_SIZE 20`, `SSR_SPEED_DEFAULT_IX 4` (1x). `SSRSpeedLadderIndex(x100)` = NEAREST stop (strict `<` so ties resolve to the lower index; 2500 -> index 13 = 2000). `SSRSpeedFraction` / `SSRSpeedAtFraction` map index <-> 0..1 for the panel's 20-button groove (`SSR_Panel.mqh:1086,2319,2325,2375`). `SSRSpeedName` ("MAX", "%dx", or "%.2f" trimmed + "x"), `SSRSpeedMeaning` ("1h in Nm").

Callers: everything. Invariants relied upon: MSC constants are long; `SSR_INVALID_TIME` compares as -1 against long fields; ladder ascends strictly.

---------------------------------------------------------------------------------------------------
## 2. SSR_Time.mqh - the only msc<->datetime seam

`SSRToMsc(datetime)` = t*1000; `SSRToTime(long)` = msc/1000 (truncation toward zero; negative -> 0); `SSRSecOf`.
`SSRBarOpenMsc(msc, tf)` = floor to `PeriodSeconds(tf)*1000` multiple (epoch-aligned; correct for M1..H12 and D1; WRONG for W1/MN1 by design - the doc says so and every caller (StrategyHost:112, MarketView:91/287/358, ChartManager:236) checks `SSRIsSupportedTimeframe` first; the helper itself does not refuse). `PeriodSeconds<=0` returns msc unchanged.
`SSRNextBarOpenMsc`, `SSRIsSupportedTimeframe` (M1..H12, D1 true; W1/MN1 false), `SSRFormatMsc` ("--" for <=0, else TimeToString DATE|MINUTES|SECONDS), `SSRFormatMscMs` (+ ".%03d"), `SSRFormatSpan` (d h:m:s), `SSRClampMsc`.

Key users in this subsystem: `Truncate()` floors the cut to M1 open with `SSRBarOpenMsc(from_msc, PERIOD_M1)` (Manager:720); Timeline snaps `start_msc` the same way (ReplayTimeline:63), so `start_msc` is always M1-aligned and `warmup_to = start_msc - 1` is the last ms of the previous minute.

---------------------------------------------------------------------------------------------------
## 3. SSR_Platform.mqh - terminal facts

`SSRCanBlock()` = program type != INDICATOR; `SSRPause(ms)` = Sleep unless indicator (no-op there). `SSRMicros()`, `SSRElapsedMs(t0)` (GetMicrosecondCount based), `SSRMemMql`, `SSRMemTerminal`, `SSRMaxBarsInChart` (TERMINAL_MAXBARS).
Used by Manager for the two teardown pauses (50 ms after ChartClose, 120 ms after a successful CustomSymbolDelete) and for timing stats. NOTE `Manager::BarCount()` calls raw `Sleep(100)` (line 798), not `SSRPause` - only test callers (T3) use BarCount.

---------------------------------------------------------------------------------------------------
## 4. SSR_SymbolNaming.mqh - pure string logic (Common, so Chart layer can recognise names without the Mt5 layer)

`SSR_SYMBOL_NAME_MAX 31` (spike A1 measures the real cap by growing a name until CustomSymbolCreate refuses; constant still says "conservative until spike A1 reports"), `SSR_SYMBOL_PATH "SSReplay"` (Market Watch group), `SSR_SYMBOL_SUFFIX ".SSR"`.
- `SSRReplaySymbolName(origin, slot)` -> origin head (cut to 31-len(".SSR"+slot) = 26 chars for 1-digit slots) + ".SSR<slot>". Suffix is never cut.
- `SSRAnonSymbolName(slot)` -> "Chart.SSR<slot>" (Blind mode; all origins share it per slot - the seed cache's origin check is what keeps a GBPUSD warmup from being reused for XAUUSD).
- `SSRReplaySymbolNameFor(origin, slot, anonymous)` - the one entry point (Manager:308, Sink:146, EA:1006).
- `SSRIsReplaySymbol(name)` = `StringFind(name, ".SSR") >= 0` (SUBSTRING, not suffix). Used by: Manager Create-fallback:341 and Adopt:465, Sink:152, LeakGuard:59 (any chart on a ".SSR"-containing symbol is not counted as "other live"), EA:1609 (duplicate-slot scan, which additionally checks the suffix) and EA:1863 (`on_replay = SSRIsReplaySymbol(_Symbol)` - THE pass-1/pass-2 discriminator of the one-window handover).
- `SSRIsNameUsable(name)` 1..31 chars; `SSRReplaySymbolPath()`.

---------------------------------------------------------------------------------------------------
## 5. SSR_SeedCache.mqh - on-disk manifest saying "this replay symbol already holds warmup [from,to]"

`SSR_CACHE_DIR "SSReplay\cache"`; file per replay symbol: `SSReplay\cache\<symbol with \ / : -> _>.manifest`, FILE_TXT|FILE_ANSI, lines `version= origin= symbol= from= to= bars= written=` (CRLF).
`SSRSeedManifest {version, origin, replay_symbol, warmup_from_msc, warmup_to_msc, bar_count, written_at}`; `IsValid()` = symbol non-empty, from>0, to>from, bars>0 (origin NOT required).

`CSSRSeedCache` (owned by value inside the sink, `m_cache`): state `m_enabled` (default true; only `Sink::SetCacheEnabled` changes it and NOTHING calls that - grep: no callers), `m_hits/m_misses/m_bars_saved/m_last_reason`.
- `Save(m)` (Sink:292 after every WARMUP write incl. RepairWarmupIfLost; `bar_count` = sink's cumulative `m_seed_bars`, which after a jump includes jump bars).
- `Load(symbol, out)`; `Invalidate(symbol)` = FileDelete (Sink: Adopt-failure 171, warmup-reaching truncate 358, Release 389).
- `CanReuse(origin, replay_symbol, from, to)` (lines 165-205) - four checks in order: enabled; manifest loads and `IsValid`; `m.version == SSR_VERSION` (inert: constant never changes); `m.origin == origin`; cached range COVERS request (`m.from <= from && m.to >= to`); then EVIDENCE from the terminal: `SeriesInfoInteger(replay, PERIOD_M1, SERIES_BARS_COUNT) > 0`, `SERIES_FIRSTDATE*1000 <= from`, `SERIES_LASTBAR_DATE*1000 + 59999 >= to`. Every failure sets `m_last_reason` (surfaced as `Sink::CacheReason()`, printed by the EA at 1556 area and by T6).
Invariant relied upon: M1 `SeriesInfoInteger` on a custom symbol answers without priming (audit A21 only requires priming for non-M1). If the terminal answers 0 for an untouched M1 series, the result is a MISS (reseed), never a false hit.

Who actually gets a hit in the product: pass 2 of the one-window handover (symbol + manifest survive REASON_CHARTCHANGE because `Release()` runs only on REASON_REMOVE/PROGRAM/CLOSE, EA:2152-2204), and T6.

---------------------------------------------------------------------------------------------------
## 6. SSR_CustomSymbolManager.mqh - `CSSRCustomSymbolManager` (the MetaTrader side of one replay symbol)

Constants: `SSR_RATES_CHUNK 10000` (CustomRatesUpdate slice), `SSR_TICKS_CHUNK 4096` (CustomTicksAdd slice; safety bound, not throughput knob), `SSR_FAR_FUTURE D'2038.01.01'` (upper edge for CustomRatesDelete).
`SSRSymbolStats {bars_written, ticks_added, ticks_rejected, rates_calls, ticks_calls, rates_deleted, ticks_deleted, write_time_ms}` - exposed via `StatsInto()` (GroupPort:156, QA Smoke).

State: `m_origin, m_symbol, m_slot (set only by Create, NOT by Adopt), m_anonymous, m_created, m_selected, m_digits, m_point, m_stats, m_last_error(+text), m_chart_mode_ok (set only by Create; read by NOBODY - grep confirms), m_session_days, m_session_note`.

Public surface and what each writes to the terminal:
- `SetAnonymous(on)` must precede Create (name fixed at creation).
- `Create(origin, slot)` (304-422): name via `SSRReplaySymbolNameFor`; `SSRIsNameUsable`; **`Destroy()` first** (unconditional teardown of any same-named symbol: closes EVERY chart on it, deselects, CustomSymbolDelete); `SymbolSelect(origin,true)` (puts the ORIGIN into Market Watch - the leak the LeakGuard later reports and offers to hide); `CustomSymbolCreate(name, "SSReplay", origin)`; on failure, fallback-adopt if `SymbolInfoInteger(name, SYMBOL_DIGITS) > 0 && GetLastError()==0 && SSRIsReplaySymbol(name)` (338-347 - the DIGITS>0 test that Adopt's comment 434-450 says is wrong for whole-point instruments); then overrides: `SYMBOL_SPREAD_FLOAT=true`, `SYMBOL_TRADE_MODE=DISABLED`, **`SYMBOL_CHART_MODE=BID` + read-back into `m_chart_mode_ok`** (383-395, added v120 commit 9235491), `Apply247Sessions()`, `CloneMoneyProperties(origin)`, `SymbolSelect(replay,true)` (required: CustomTicksAdd only broadcasts to charts for Market Watch symbols), digits/point read back.
- `Adopt(replay_symbol, origin)` (431-497): existence via `SYMBOL_EXIST`, ownership via `SYMBOL_CUSTOM` and `SSRIsReplaySymbol`; sets origin/symbol/created; re-applies SPREAD_FLOAT, TRADE_MODE, `Apply247Sessions`, `CloneMoneyProperties`; SymbolSelect. **Does NOT set SYMBOL_CHART_MODE and does NOT set m_chart_mode_ok** (stays constructor false). Does not touch history.
- `Apply247Sessions()` (165-216): per day 0..6: overwrite session 0 with 0..86399 (quote+trade); if `DayIsCovered` (SymbolInfoSessionQuote session 0 spans >= 86399 s) is false: delete session 0 up to 8 times, re-add; if still not covered, add again; counts `m_session_days`, builds `m_session_note` when < 7. Read-back, not return value, is the truth.
- `CloneMoneyProperties(origin)` (271-290): START_TIME/EXPIRATION_TIME := 0; clones TICK_SIZE, TICK_VALUE, TICK_VALUE_PROFIT/LOSS, CONTRACT_SIZE, VOLUME_MIN/MAX/STEP when origin value > 0.
- `CloseCharts()` (505-522): `ChartClose` on every chart whose `ChartSymbol == m_symbol` - INCLUDING `ChartID()` (the program's own chart) if it currently reports the replay symbol. `OpenChartCount()`.
- `Destroy()` (544-586): if name set: CloseCharts, `SSRPause(50)`, `SymbolSelect(false)`, `CustomSymbolDelete`, `m_created=false` regardless, `SSRPause(120)` on success, `Succeed()` ALWAYS (a failed delete leaves LastError = OK; return bool is the only signal and every caller ignores it).
- `WriteBars(bars, count)` (593-636): slices of 10000 copied element-wise into a local array, `CustomRatesUpdate`; `w<0` -> SINK_FAILED; counts. Used for warmup seed, jump bulk, warmup repair.
- `AddTicks(ticks, count)` (646-697): requires created AND selected; slices of 4096; `CustomTicksAdd`; `added<0` -> fail; `added<n` counted as `ticks_rejected` but NOT a failure.
- `Truncate(from_msc)` (712-744): `bar_open = SSRBarOpenMsc(from, M1)`; `CustomRatesDelete(sym, bar_open, 2038-01-01)` then `CustomTicksDelete(sym, bar_open_msc, LONG_MAX)`; returns `bar_open` (the ACTUAL cut) or -1. Invariant: both stores cut at the same M1 open, because deleting ticks does not un-build the bar they contributed to.
- `ClearAll()` (747-756): both deletes from 0; return values discarded; always true.
- `SymbolTimeMsc()` = SYMBOL_TIME_MSC (spike C4 asserts == last emitted tick).
- `BarCount(tf)` (783-801): SERIES_BARS_COUNT, else up to 10x {CopyRates 1 bar; re-read; Sleep(100)} - the lazy-series priming pattern (A21).

Teardown-order invariant (header): charts -> Market Watch -> CustomSymbolDelete; the terminal refuses deletion while a chart shows the symbol or it is selected.

---------------------------------------------------------------------------------------------------
## 7. SSR_CustomSymbolSink.mqh - `CSSRCustomSymbolSink : CSSRReplaySink` (the adapter the engine talks to)

Owns by value: `m_mgr` (manager), `m_cache` (seed cache). State: `m_slot, m_anonymous, m_adopt_name, m_warmup_from_msc/to_msc, m_reused_seed, m_prepared, m_adopt_existing, m_own_symbol (default TRUE)`, counters `m_emit_calls/m_emit_ticks/m_seed_bars/m_truncates/m_emit_time_ms`, watermark `m_last_emit_msc`.

Two rules (header): warmup goes in as BARS (`WriteBars`), replay goes in as TICKS (`AddTicks`); truncation is DELETION.

Lifecycle as driven by `CSSRReplayController::Load` (ReplayController:814-827):
1. `OnWarmupPlanned(warmup_first or start, start-1)` -> `SetWarmupRange`.
2. `Prepare(origin, digits, point)` (139-217):
   - `replay_name = SSRReplaySymbolNameFor(origin, slot, anonymous)`; if `m_adopt_existing && m_adopt_name` is a replay name, the READ name wins (prints when it differs).
   - `m_reused_seed = m_cache.CanReuse(origin, replay_name, from, to)` when a warmup range is set.
   - reused -> `m_mgr.Adopt`; on failure reused=false + Invalidate.
   - `!reused && m_adopt_existing` -> `Adopt` (Fail on error) + `ClearAll()`.
   - `!reused` (fresh) -> `Create` (Fail on error) + `ClearAll()`.
   - reused -> `m_mgr.Truncate(warmup_to + 1)` = cut at start_msc (return value IGNORED).
   - counters reset, `m_prepared = true`.
3. `NeedsWarmup()` = `!m_reused_seed` (controller skips the data-layer read entirely on a hit).
4. `SeedBars(bars, n)` (234-295): `is_warmup = warmup_to>0 && last bar time*1000 <= warmup_to`; **if `m_reused_seed && is_warmup` -> count and return true WITHOUT writing** (the cache's contract: warmup bars are already there); else `WriteBars`; if `is_warmup` and a warmup range exists -> `m_cache.Save(manifest{origin, symbol, from, to, bar_count=m_seed_bars})`. Callers: SeedWarmup (893), RepairWarmupIfLost (960 - re-writes the WARMUP range after a jump when `OldestMsc() > warmup_first`), JumpTo bulk (1383, bars > start so never is_warmup).
5. `EmitTicks(ticks, n)` (300-335): rejects `ticks[0].time_msc < m_last_emit_msc` (strict; equal allowed) as SSR_ERR_INTERNAL "out-of-order emit"; `AddTicks`; watermark = last tick. Callers: controller Pump (359) and EmitWindow (494).
6. `TruncateFrom(from)` (340-364): `m_mgr.Truncate`; `m_truncates++`; if `actual <= warmup_to` -> Invalidate manifest; `m_last_emit_msc = actual-1`. Callers: SeekTo backward (1227), Reset (1277, at start_msc -> actual == start > warmup_to so manifest survives), RestoreSnapshot (1623).
7. `OldestMsc()` = `SeriesInfoInteger(sym, M1, SERIES_FIRSTDATE)*1000` or -1 (controller then does nothing).
8. `OnReset()` clears watermark. `Release()` (383-394): if `m_own_symbol && created` -> Invalidate manifest, `Destroy()`; `m_prepared=false`.
9. **Destructor** (69-75): `if(m_own_symbol && m_mgr.IsCreated()) m_mgr.Destroy();` - fires whenever the object dies with an owned, created symbol. `SetOwnsSymbol(false)` exists (403) but is called ONLY by test T6 (238, 256); the EA never calls it. The EA holds `CSSRCustomSymbolSink g_sink;` and `g_sink2[SSR_EXTRA_STREAMS]` as globals (EA:190, 299).

Host wiring (EA): `SetAnonymous(blind)` 1003, `SetSlot(InpSlot)` 1143, `SetAdoptExisting(on_replay)` + `SetAdoptName(on_replay ? _Symbol : "")` 1961-1962 (extra streams always `SetAdoptExisting(false)`), `ReplaySymbol()` feeds ChartManager/Publisher/duplicate-slot scan, `ReusedSeed()` printed at 1556, `EmitTicks()` counter into vitals/flight recorder. `Manager()` and `Cache()` pointers exposed for QA/GroupPort.

Diagnostics: `EmitCalls/EmitTicks/SeededBars/Truncations/EmitTimeMs/TicksPerSecond/SymbolClockMsc/ToString`.

---------------------------------------------------------------------------------------------------
## 8. Cross-cutting invariants the code relies on (and where each is enforced)

1. `start_msc` is M1-aligned (Timeline:63) so `Truncate(start)` never reaches into warmup and Reset never invalidates the manifest.
2. The engine emits monotonic ticks; the sink re-checks (strict <) and rolls the watermark back on truncate.
3. Replay symbol is BID chart mode and ticks carry BID|ASK|LAST flags (TickSynthesizer:174,203) - belt and braces; the BID force exists only in `Create`.
4. Quote/trade sessions are 24/7 (else ticks are accepted and build nothing); enforced by read-back in both Create and Adopt.
5. The seed cache never trusts the manifest alone: SERIES_* evidence must agree; a false negative only costs a reseed.
6. `Release()` runs only on user removal (EA:2152); the symbol and manifest are meant to survive REASON_CHARTCHANGE so pass 2 adopts them - but nothing in the sink switches `m_own_symbol` off for that transition.
7. The one truth about deletion success is the `bool` from `Destroy()` (LastError is reset to OK inside it); Prepare's `ClearAll()`/`Truncate()` results are not inspected.

Disk: `MQL5\Files\SSReplay\cache\<replay>.manifest` (only artefact this subsystem writes). Chart: nothing drawn; `CloseCharts` closes windows. Terminal: custom symbols under group `SSReplay`, Market Watch selection of both origin and replay symbol.

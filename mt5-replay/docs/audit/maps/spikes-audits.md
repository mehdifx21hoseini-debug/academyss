# ARCHITECTURE MAP — subsystem `spikes-audits`

Build v125. Everything below was read from source; line numbers are from the
files as they stand. Nothing here is recalled.

Scope:
* 13 spike **scripts** — `MQL5/Scripts/SSReplay/Spike/*.mq5`
* 2 spike **services** — `MQL5/Services/SSReplay/Spike/*.mq5`
* 2 spike **indicators (probes)** — `MQL5/Indicators/SSReplay/Spike/*.mq5`
* 1 shared **harness** — `MQL5/Include/SSReplay/Spike/SSR_SpikeKit.mqh` (641 lines)
* 1 **static-audit runner** — `tools/ssr_audit.py` (1638 lines, audits A1..A21)
* 1 **baseline generator** — `tools/ssr_known_calls.py` → `tools/ssr_known_calls.txt` (A13's allowlist)

The spikes are **not product code**. `SSR_SpikeKit.mqh:6` states it: *"NOT
product code. Nothing here survives into the engine."* The one thing shared
with the product is the build stamp (`Include/SSReplay/Common/SSR_Build.mqh`,
`#define SSR_BUILD "v125 2026-09-12  fewer"`).

---

## 1. `SSR_SpikeKit.mqh` — the measurement harness

Not a class hierarchy: one class (`SSR_Rng`) plus ~20 free functions and 5
macros. Every spike includes it with `#include <SSReplay/Spike/SSR_SpikeKit.mqh>`.

### 1.1 State it owns (file-scope globals, one set per running program)

| Global | Line | Meaning |
|---|---|---|
| `g_ssr_spike` | 26 | spike name, stamped into every CSV row |
| `g_ssr_run`   | 27 | run id — `TimeToString(TimeGMT(),TIME_DATE)` with `.` removed + `GetTickCount()%100000` |
| `g_ssr_pass` / `g_ssr_fail` | 28-29 | assertion counters; **the only thing that decides "SPIKE PASS"** |
| `g_ssr_t_start` | 30 | `GetMicrosecondCount()` at `SSR_Begin` |

### 1.2 What it writes to disk

All paths relative to `<Terminal Data Folder>\MQL5\Files`, folder created by
`FolderCreate(SSR_DIR)`:

| Macro | Path | Header (written only when the file did not exist) |
|---|---|---|
| `SSR_DIR` | `SSR_Spike` | — |
| `SSR_F_ENV` | `SSR_Spike\env.csv` | `run_id,utc,spike,terminal,build,company,server,cpu_cores,mem_physical_mb,mem_total_mb,mem_used_mb,max_bars,ssr_build` |
| `SSR_F_RESULTS` | `SSR_Spike\results.csv` | `run_id,utc,spike,case,metric,value,unit,notes` |
| `SSR_F_VERDICTS` | `SSR_Spike\verdicts.csv` | `run_id,utc,spike,assertion,verdict,expected,actual,notes` |

`ssr_build` is deliberately the **last** env column (kit:139-140) so an older
`env.csv` still parses.

Spike-owned extra files: `SSR_Spike\d3_timeseries.csv` (D3:68),
`SSR_Spike\c2_heartbeat.csv` (C2:63), `SSR_Spike\c1_service_probe.txt` (C1:140).

### 1.3 Public surface

**`class SSR_Rng`** (kit:36-63) — deterministic xorshift64, chosen over
`MathRand()` because that is 15-bit and shares global state (kit:34).
`Seed(ulong)` (0 → 88172645463325252), `Next()`, `Uniform()` → `[0,1)` via
`Next()%1000000007`, `Range(lo,hi)`, `Int(lo,hi)`, `Normal()` (Box-Muller,
`u1` floored at 1e-12).

**Timing** — `SSR_Now()`, `SSR_ElapsedUs/Ms/Sec(t0)`; all on
`GetMicrosecondCount()`.

**Memory** — `SSR_MemMql()` = `MQL_MEMORY_USED`, `SSR_MemTerminal()` =
`TERMINAL_MEMORY_USED`. Both MB.

**CSV** — `SSR_Csv(s)` replaces `,`→`;` and newlines→space (no quote
escaping). `SSR_Utc()` = `TimeToString(TimeGMT(),TIME_DATE|TIME_SECONDS)`.
`SSR_Append(file,header,line)` (93-108): `FolderCreate`, `FileIsExist` →
`fresh`, `FileOpen(FILE_READ|FILE_WRITE|FILE_TXT|FILE_ANSI|FILE_SHARE_READ)`,
`FileSeek(END)`, write header if fresh, write line, close. **No
`FILE_SHARE_WRITE`** — see finding 21.

**Run lifecycle**
* `SSR_Begin(spike)` (113-150) — resets counters, builds `g_ssr_run`, appends
  one `env.csv` row, prints `=== [name] BEGIN ssr=… run=… mt5=… ===`.
* `SSR_Metric(case,metric,value,unit,notes="")` (153-163) — one `results.csv`
  row, `%.6f` value, plus a `PrintFormat`. Comment: *"record a measured
  number. NEVER record an opinion."*
* `SSR_Verdict(assertion,ok,expected,actual,notes="")` (166-179) — one
  `verdicts.csv` row, increments pass/fail, prints only on FAIL, returns `ok`.
* `SSR_End()` (181-191) — emits `_run/total_runtime`, `_run/assertions_pass`,
  `_run/assertions_fail`; prints `SPIKE PASS` iff `g_ssr_fail == 0`.
  **Invariant the whole suite rests on: a spike with no `SSR_Verdict` call at
  all reports SPIKE PASS.**

**Program-type guard** — `SSR_Pause(ms)` (199-204): returns immediately when
`MQL_PROGRAM_TYPE == PROGRAM_INDICATOR` (Sleep is illegal there), else
`Sleep(ms)`. Every wait loop in the kit routes through it, so the two indicator
probes can share the header. Consequence: inside an indicator every kit wait
loop becomes a busy-spin.

**Custom-symbol helpers**
* `SSR_DropSymbol(sym)` (209-248) — closes every chart whose `ChartSymbol()`
  is `sym` (so a caller's chart id becomes stale), then
  `SymbolSelect(sym,false)` → **`SSR_Pause(200)`** → `CustomSymbolDelete`, one
  retry after `SSR_Pause(800)`, then names the symbol in the log. The comment
  at 225-234 declares the order **and the pause** load-bearing: without the
  beat the delete fails, the next `CustomSymbolCreate` fails 5304, "and the
  spike dies on its first line".
* `SSR_Set247Sessions(sym)` (251-259) — `CustomSymbolSetSessionQuote` and
  `...SessionTrade` for days 0..6, 0..86399. Return values ignored.
* `SSR_Origin(requested)` (276-300) — blank ⇒ `Symbol()`; if that is empty (a
  service) ⇒ `SymbolName(0,true)`; a non-blank name that `SymbolSelect`
  accepts wins; otherwise fall back to the chart **and print the
  substitution**. Rationale at 262-275: a typed default symbol is a guess
  about someone else's Market Watch.
* `SSR_MakeSymbol(sym,origin,sessions_247=true)` (303-335) — `SSR_DropSymbol`,
  `CustomSymbolCreate(sym,"SSReplay\Spike",origin)`, then
  `SYMBOL_SPREAD_FLOAT=true`, `SYMBOL_TRADE_MODE=DISABLED`,
  `SYMBOL_START_TIME=0`, `SYMBOL_EXPIRATION_TIME=0` (A1 measures whether a
  futures clone inherits a lifetime; this clears it so it cannot confound
  anyone else), optional 24/7 sessions, `SymbolSelect(sym,true)`.
  **It does NOT set `SYMBOL_CHART_MODE`** — see finding 3.

**Wait primitives** — four, and which one a spike picks is the single biggest
source of bad numbers in this subsystem:
* `SSR_WaitSeries(sym,tf,timeout=10000)` (338-349) — polls
  `SeriesInfoInteger(SERIES_SYNCHRONIZED)`. The kit's own comment (390-417)
  says this flag "has been observed at 0.002ms, at 9,200ms, and never", is
  size-independent, and is therefore **"a timer, not work"**.
* `SSR_WaitLastBar(sym,tf,expected,timeout=30000)` (418-430) — polls
  `CopyRates(...,0,1)` until `r[0].time == expected`. The seed-side
  "ask the data, not the flag" primitive.
* `SSR_WaitLastBarBefore(sym,tf,cut,timeout=30000)` (433-445) — same, until
  `r[0].time < cut`. The delete-side primitive.
* `SSR_WaitReadable(sym,tf,last_bar,timeout=30000)` (448-461) — polls
  `CopyRates(sym,tf,last_bar,1)` until the exact bar answers.
All four return **ms waited, or `-1.0` on timeout**.

**Throughput guard** — `SSR_Rate(sent,accepted,seconds)` (365-372) returns
`-1.0` if `sent<=0 || accepted<sent || seconds<=0`, else `accepted/seconds`.
`SSR_RateMetric(case,metric,sent,accepted,seconds,notes)` (375-388) records
either the rate or `0.0 ticks/s` with a `NOT MEASURED - sent=… accepted=…`
note. The banner at 351-364 is the suite's central lesson: B2 once published
**10.5 billion ticks/second** by dividing ticks *sent* by the microseconds a
total rejection took, then recommended that batch size. **Unit is hardcoded
`"ticks/s"`, so bar-rate metrics cannot be routed through this guard** — and
they are not (A2:133, D1:101-104).

**Golden dataset** — `SSR_GenM1(out[],start,count,base,point,digits,
vol_points=25.0,seed=20260829)` (467-509): a random walk, `close = open +
N(0,1)*vol_points*point`, wicks `|N|*vol_points*0.6*point` beyond the body,
`tick_volume` in `[8,400]`, `spread` in `[1,6]`, `real_volume=0`, times
`start + i*60`, all normalised to `digits` and repaired so
`high>=max(o,c)`/`low<=min(o,c)`. Broker-independent by design.

**Reference aggregation** — `SSR_AggregateM1(m1[],tf,out[])` (516-554):
independent M1→TF roll-up, slot = `(time/PeriodSeconds(tf))*PeriodSeconds(tf)`
(UTC-epoch aligned), open from the first M1 in the slot, high/low extended,
close from the last, tick/real volume summed, spread from the first bar only.
This is what the terminal's own aggregation is checked against in A2.
`ArrayResize` is called **once per output bar** (line 533).

**Bar→tick model** — `SSR_BarToTicks(bar,out[],n,spread_abs,digits)`
(562-599): `cnt = MathMax(n,4)`; keypoints `k = {O, L, H, C}` for a bullish
bar and `{O, H, L, C}` for a bearish one; for each `i`,
`u = i*3/(cnt-1)`, `seg = floor(u)`, `p = k[seg] + (k[seg+1]-k[seg])*(u-seg)`;
`time = bar.time + i*59/(cnt-1)`, `time_msc = bar.time*1000 + i*59000/(cnt-1)`;
`flags = TICK_FLAG_BID|TICK_FLAG_ASK` (**no `TICK_FLAG_LAST`**); the last tick
is forced onto `bar.close`. Header comment: *"The same assumption the engine
will make, tested here first."* The engine's own
`CSSRTickSynthesizer::Synthesize` (`Include/SSReplay/Core/SSR_TickSynthesizer.mqh:117-183`)
is the same interpolation — but it **does** set `TICK_FLAG_LAST` (line 175)
and the engine forces `SYMBOL_CHART_MODE_BID`
(`Include/SSReplay/Mt5/SSR_CustomSymbolManager.mqh:383`).

**Comparator** — `SSR_CompareRates(a[],b[],digits,&vol_mismatch,&first_detail)`
(606-640): compares `min(size)` bars, tolerance `10^-digits * 0.5`, returns
OHLC/time mismatch count; volume counted separately "so a volume-only
difference does not mask a price difference"; `first_detail` is a formatted
description of the first mismatch only.

---

## 2. The 17 spikes

Every script carries `#property script_show_inputs` and `input string
InpOrigin = ""` (blank = the chart it was dropped on). Every one that makes a
symbol uses `SSR_MakeSymbol` and drops it at the end.

| ID | File | Tier | Question | Symbols made | Verdicts it records |
|---|---|---|---|---|---|
| A1 | `Scripts/.../SSR_A1_SymbolLifecycle.mq5` | A blocker | does `CustomSymbolCreate(name,path,origin)` clone the specs, and does delete leave no residue? | `SSRA1`, plus `AAAA…` probes under `SSReplay\Spike\len` | origin_available, symbol_created, symbol_selected, 12 × `prop_*`, lifetime_clearable (conditional), set_spread_float, set_trade_disabled, set_sessions_247, name_len_usable, symbol_deleted, no_residue_after_delete |
| A2 | `SSR_A2_RatesAndAggregation.mq5` | A blocker ("the single most important test in Phase 0") | write M1 only — does MetaTrader build M5/M15/M30/H1/H4 correctly? | `SSRA2`, `SSRA2N` | symbol_ready, rates_written, m1_bit_exact, `agg_<TF>_ohlc_exact` ×5, `agg_<TF>_volume_exact` ×5, nonM1_behaviour_documented |
| A3 | `SSR_A3_FutureIsolation.mq5` | A blocker ("the product's reason to exist") | after writing history only up to T, is anything beyond T visible on any of 7 TFs via any of 4 read paths? | `SSRA3` | symbol_ready, `leak_*` (only ever on failure), zero_future_leaks |
| B1 | `SSR_B1_TicksAddBroadcast.mq5` | B blocker | does `CustomTicksAdd` broadcast to open charts, not just write history? | `SSRB1`, `SSRB1H` (deliberately hidden) | symbol_ready, ticks_all_accepted, tick_visible_in_symbolinfotick, forming_bar_took_close, wick_expanded_to_extremes, hidden_symbol_behaviour_documented |
| B2 | `SSR_B2_TickThroughput.mq5` | B critical | ticks/s vs batch size (100…50 000) and vs chart count | `SSRB2` | symbol_ready, throughput_target (≥2000 t/s), throughput_floor (≥500 t/s) |
| B3 | `SSR_B3_SessionBehavior.mq5` | B high | does the terminal silently drop ticks outside configured sessions? 168 hourly probes × {no sessions, 24/7} | `SSRB3A`, `SSRB3B` (hardcoded, no input) | **only** `<label>_symbol` on creation failure |
| B4 | `SSR_B4_BrokerDataAudit.mq5` | B high (an audit) | how much M1 and tick history does *this* broker have? | none (reads live symbols) | audit_completed (always true) |
| C1 | `Services/.../SSR_C1_ServiceApiAccess.mq5` | C critical (Core = Service vs EA) | can a chartless service drive every Custom* API? | `SSRC1` | `service_can_<op>` ×12 via `Op()` |
| C2 | `Services/.../SSR_C2_ServicePersistence.mq5` | C critical | does a service survive TF change / chart close / profile switch? 500 ms heartbeat for 360 s while the operator performs a scripted manual procedure | none | no_restart, no_long_gaps, survived_full_run |
| C3 | `Scripts/.../SSR_C3_IpcChannel.mq5` | C high | is the GlobalVariable channel lossless, fast and race-free? | none (GVs `SSR.c3.*`) | datetime_lossless, ipc_fast_enough (≥10 000 ops/s), seq_last_protocol_safe, gv_name_len_usable |
| C4 | `SSR_C4_ReplayClock.mq5` | C high | does `SYMBOL_TIME` equal the last injected tick's time (the engine's official clock)? | `SSRC4` | symbol_ready, symbol_time_equals_injected, symbol_time_msc_exact, timecurrent_is_unsafe |
| D1 | `SSR_D1_SeedPerformance.mq5` | D medium | seed cost vs chunk size (1k…single call) and vs depth (10k…500k) | `SSRD1` | **only** symbol_ready |
| D2 | `SSR_D2_TimeframeSwitch.mq5` | D medium | cost of M1→M5→M15→M30→H1→H4→M1, idle and "live", at 3 depths | `SSRD2` | chart_open_depth*, `tfswitch_<d>k_<mode>_under_1s` ×6 |
| D3 | `SSR_D3_SustainedRun.mq5` | D medium | memory and throughput drift over 120 min of injection | `SSRD3` | symbol_ready, memory_stable, throughput_stable (both explicitly "not measured" below 10 min) |
| D4 | `SSR_D4_RewindCost.mq5` | D medium | 1-bar tail delete vs 100-bar tail delete vs full rebuild | `SSRD4` | symbol_ready, step_back_interactive (≤500 ms), step_back_usable (≤3000 ms), tail_beats_rebuild (≥5×) |
| P1 | `Indicators/.../SSR_Probe_TickWitness.mq5` | probe | only an indicator on the chart can testify that `OnCalculate` fired | none | chart_received_ticks (`g_calls > 1`) |
| P2 | `Indicators/.../SSR_Probe_UIJitter.mq5` | probe | timer jitter as a proxy for "the terminal felt slow" | none | none |

### 2.1 Per-spike detail that later work will need

**A1** — `CompareLong/CompareDouble/CompareString(sym,origin,prop,name)` each
emit one verdict and return 0/1. The 12 properties are DIGITS, POINT,
TRADE_TICK_SIZE, TRADE_TICK_VALUE, TRADE_CONTRACT_SIZE, VOLUME_MIN/MAX/STEP,
MARGIN_INITIAL, CURRENCY_BASE/PROFIT/MARGIN. Double comparison tolerance is
`1e-12`. Section 2b measures whether a clone inherits
`SYMBOL_START_TIME`/`SYMBOL_EXPIRATION_TIME` and, if so, whether it can be
cleared. Section 4 grows a name `"AAAA"`…64 chars until
`CustomSymbolCreate` refuses, and publishes the last success as
`max_symbol_name_length` — the number that "drives the `<SRC>.SSR<slot>`
naming convention". Section 6 opens a chart and measures
`delete_with_open_chart` as a bool.

**A2** — `CheckTimeframe(sym,m1[],tf,tfname,digits)`: reference aggregation
first, skip if `nref<=2`, `SSR_WaitSeries(...,15000)`, `CopyRates(sym,tf,
ref[0].time, ref[nref-1].time, got)` with `ArraySetAsSeries(got,false)`,
compare `min(nref,ngot)-1` bars (the last is legitimately still forming).
D1 (the daily timeframe) is informational only — real terminals may key D1 to
the trading day rather than UTC midnight (A2:177-178). Section 5 writes
**M5** rates into a second symbol and records what results, touching M5 with
`CopyRates(...,0,1,touch)` first because "an unasked-for series answers zero"
(A2:204-207).

**A3** — `AuditCut(sym,T,&checks)` runs 4 read paths × 7 TFs:
`CopyRates(sym,tf,T+1,far)`, `iTime(sym,tf,0)`, `Bars(sym,tf,T+1,far)`,
`SeriesInfoInteger(SERIES_LASTBAR_DATE)`; `far = T + 30 days`. The loop
rebuilds history 100 times: `CustomRatesDelete(0..2038)`,
`CustomTicksDelete(0..LONG_MAX)`, write `slice[0..cut]`,
`SSR_WaitSeries(M1,10000)`, and accumulates `t_reset_sum`, published as
`avg_rebuild_time` "cost of a full history rebuild - feeds the Reset budget".
Cut points come from `SSR_Rng` seeded **777001**, in the middle 80 %.

**B1** — seeds 120 M1 bars before `InpStart`, opens a chart, then for each of
20 forward bars: `SSR_BarToTicks(bar,ticks,InpPerBar=20,20*point,digits)`,
`CustomTicksAdd`, then three checks — `SymbolInfoTick` bid vs bar close
(tolerance `point*0.5`), `iClose(...,0)` polled for up to `InpReflectMs=250`
ms, and `iHigh/iLow` polled for up to 250 ms against `hi-point`/`lo+point`.
The comment at 103-112 records why the poll exists: reading `iClose` with no
wait measured "1 hit in 20" and was misread as "the candle does not form".

**B2** — `g_batch[6] = {100,500,1000,5000,10000,50000}`, `rounds =
max(1, InpTotalTicks/bsize)`, one **forward-only** `t_msc` base for the whole
run (10 ms per tick) because `CustomTicksAdd` refuses a stamp the symbol
already holds (B2:84-92 — the origin of the 10.5-billion figure). Per case it
records batch_size, ticks_sent, ticks_accepted, inject_time,
ticks_per_sec (through `SSR_RateMetric`), us_per_tick, mem deltas, rejected;
then `best_ticks_per_sec` and `optimal_batch_size` ("lock this into Feeder").
`OpenCharts(sym,howmany,&ids)` opens up to 4 charts on M1/M5/M15/H1.

**B3** — `RunCase(sym,with_sessions,label)` makes the symbol with or without
24/7 sessions, seeds 60 bars, injects one tick per hour for 168 hours (one
`CustomTicksAdd` call each), sleeps 1 s, then reads ground truth with
`CopyTicksRange(COPY_TICKS_ALL)` over the whole week and matches on exact
`time_msc`. Publishes ticks_sent, ticksadd_returned_ok, ticks_readable,
acceptance_rate, per-day percentages, and `silent_drops` when
`ret_ok > matched`.

**B4** — `AuditSymbol(sym)`: warm `CopyRates(0,10)`,
`SSR_WaitSeries(M1,30000)`, then SERIES_FIRSTDATE / SERIES_SERVER_FIRSTDATE /
SERIES_BARS_COUNT; a doubling walk `d = 1,2,…,2048` days sampling **one hour**
with `CopyTicksRange(COPY_TICKS_INFO)` and tolerating
`InpEmptyTolerance = 4` empty samples before breaking; a single
`CopyTicksRange(COPY_TICKS_ALL)` over the last week published as
`copyticksrange_week_return` ("sets the page size for TickSource"); and a
`CopyRates` over the last week timed per bar. Blank `InpSymbols` ⇒ this chart
plus up to `InpMaxAuto=6` Market Watch symbols.

**C1** — `Op(name,ok,err,elapsed_us)` records one metric and one verdict
requiring `ok && err == 0`. Twelve operations in order: CustomSymbolCreate,
CustomSymbolSetInteger, CustomSymbolSetSessionQuote, SymbolSelect,
CustomRatesUpdate, Sleep, CopyRates, CustomTicksAdd, CopyTicksRange,
CustomRatesDelete, CustomTicksDelete, FileIO, GlobalVariables,
CustomSymbolDelete. Also records `context/chart_id` ("a Service is expected to
report 0").

**C2** — heartbeat loop, `InpBeatMs=500`, `InpRunSec=360`. Per beat: uptime,
gap, `CountCharts()` (ChartFirst/ChartNext), terminal memory → CSV row; and
`GlobalVariableSet("SSR.c2.seq"/"SSR.c2.uptime")` as a live IPC smoke test.
Restart detection is `GlobalVariableGet("SSR.c2.launches") + 1`, published as
`launch_count` "must stay 1 for the whole procedure"; line 127 tells the
operator to delete that GV by hand before the next run.

**C3** — four sections: (1) 10 000 `datetime → double → datetime` round trips
through a GV; (2) raw GV write/read throughput; (3) 10 000 "writer then
reader" cycles over `SSR.c3.cmd.a1/a2/a3/seq` checking for torn reads;
(4) GV name length walk 8…128. Cleans up its six GVs at the end.

**C4** — 1000 one-second-apart ticks, each followed by
`SymbolInfoInteger(SYMBOL_TIME)` and `(SYMBOL_TIME_MSC)`; then a snapshot
comparison of `TimeCurrent()` against the replay clock and a count of Market
Watch symbols whose `SYMBOL_TIME` is ahead of it.

**D1** — `SeedCase(total,chunk,digits,point)`: records `symbol_recreated`,
generates, writes in chunks, then **both** waits —
`SSR_WaitReadable(M1,last,60000)` ("the cost a user pays") and
`SSR_WaitSeries(M1,3000)` ("a flag, not a cost", capped hard because one run
"spent 300 of its 315 seconds waiting for a flag that was never going to be
set"). Publishes bars_target/written, generate_time, write_time,
readable_wait, sync_wait, total_time, `bars_per_sec` ("the number the user
waits for"), `write_call_bars_per_sec` ("WRITE CEILING ONLY"), mem delta, and
H1/H4/D1 bar counts **after touching each series with `CopyRates(...,0,1)`**
(D1:108-120 — the A21 lesson applied). Sweeps chunk ∈ {1000,5000,10000,50000,
single call} at 100 000 bars, then depth ∈ {10k,50k,100k(,250k,500k)} at chunk
10 000.

**D2** — `MeasureDepth(depth,digits,point,with_ticks)`: seed in 10 000-bar
chunks, `SSR_WaitSeries(M1,60000)`, `ChartOpen(M1)`, then
`InpRepeat=10` × 7 `ChartSetSymbolPeriod` switches through
`g_cycle = {M1,M5,M15,M30,H1,H4,M1}`, each timed until
`SERIES_SYNCHRONIZED && Bars(...)>0` or 15 s. In the `with_ticks` pass it
calls `SSR_BarToTicks(m1[depth-1], tk, 50, …)` + `CustomTicksAdd` before each
switch. Gate: worst switch ≤ 1000 ms.

**D4** — full seed (`Seed()` in 10 000-bar chunks) timed with
`SSR_WaitLastBar`; chart opened on **M5**; strategy 1 = 20 successive 1-bar
tail deletes; symbol dropped and re-seeded; strategy 2 = 10 deletes at
100-bar strides; strategy 3 = 3 full drop/create/re-seed cycles. Published
ratio `full_rebuild.avg / tail_1bar.avg`. Comment 64-70 records that every
timing here used to include `SERIES_SYNCHRONIZED` and that the published
"317× cheaper" was "mostly a measurement of a flag".

**P1 TickWitness** — `OnInit` calls `SSR_Begin` and `Comment(...)`;
`OnCalculate` increments `g_calls`, and increments `g_ticks` when
`close[rates_total-1]` differs from the previous value; `Comment` refreshed
every `InpReportSec=5`; `OnDeinit` calls `Report()` then `SSR_End()`.
`Report()` emits oncalculate_calls, observed_price_changes, elapsed,
calls_per_sec and the verdict `chart_received_ticks = (g_calls > 1)`,
described at line 55 as "the FAIL signal for spike B1".

**P2 UIJitter** — `EventSetMillisecondTimer(InpPeriodMs=50)`; `OnTimer`
computes `actual - InpPeriodMs`, clamps negatives to 0, stores into a ring of
`InpWindow=2000`; `Report(kind)` needs `g_count>=5`, copies, `ArraySort`, and
publishes ui_jitter_p50/p95/max and terminal memory under
`"<InpLabel>_<kind>"`. `OnCalculate` does nothing but return `rates_total`.

### 2.2 Invariants the spikes rely on

1. `SSR_End` reports PASS iff no `SSR_Verdict(…, false, …)` was recorded —
   so a spike with no verdicts is indistinguishable from a spike that passed.
2. `CustomTicksAdd` appends only: a stamp the symbol already holds is refused
   in full (B2:84-92).
3. A series is built lazily — the first read of an untouched timeframe answers
   zero (A2:204-207, D1:108-120, audit A21).
4. `SERIES_SYNCHRONIZED` is a timer, not work (kit:390-417, D1:74-77,
   D4:64-70).
5. A symbol must be deselected **and given ~200 ms** before it can be deleted
   (kit:225-234).
6. A rate is only a rate if the work happened (kit:351-364).
7. An empty tick sample is a closed market, not an absent history (B4:53-68).
8. `Sleep` is illegal in an indicator (kit:196-204).

### 2.3 Chart-side effects

The spikes open and close real charts: A1 (one, M1), B1 (one, M1), B2 (up to
4: M1/M5/M15/H1), D2 (one, M1, then `ChartSetSymbolPeriod` 70 times per
depth), D3 (up to 4, M1), D4 (one, M5). `SSR_DropSymbol` closes **any** chart
showing the symbol, which silently invalidates a caller's saved chart id.
Nothing in the subsystem draws a graphical object.

---

## 3. `tools/ssr_audit.py` — the 21 static audits

One flat script. `ROOT = argv[1]` or `<repo>/MQL5` (absolute). `sources()`
walks `ROOT` for `*.mq5`/`*.mqh` — **123 files** today. Three views of every
file are built once at import:

| Dict | Built by | Meaning |
|---|---|---|
| `FILES` | raw read, `errors="replace"` | exactly what is on disk |
| `CLEAN` | `strip_comments` | comments **and string literals** blanked, length and line count preserved |
| `KEEPSTR` | `blank_comments_keep_strings` | comments blanked; each literal becomes `"____"` of identical length |

`_decomment` (1281) is a fourth view built per-audit: comments out, **strings
kept whole** — A19/A20/A21 use it. `report(audit,path,line,msg)` appends to
`findings`; at the end a non-empty list prints and exits 1, otherwise
`"all audits silent across N source files"` and exit 0. Verified today:
silent, 123 files, exit 0.

Shared parsing helpers: `class_bodies`, `declared_in`, `DECL_LINE`,
`DECL_METHOD` (pointer-tolerant: `\s*[\*&]?\s*`), `NOT_A_RETURN_TYPE`,
`CALL_ON_GLOBAL`/`CALL_ON_MEMBER`/`LOCAL_DECL`, `GLOBAL_DECL`/`MEMBER_DECL`,
`CLASS_BODY`, `class_methods()`, `method_arities()`, `balanced_args`,
`split_args`, `param_range`, `_args`, `_split_args`, `type_sizes`,
`_active_branches` (a small `#ifdef`/`#else`/`#endif` evaluator that blanks
dead branches while keeping structural directives, so line numbers survive;
`#if`/`#elif` are deliberately **not** evaluated and left active).

### 3.1 What each audit checks — and what it structurally cannot

| # | Rule | Reads | Cannot catch |
|---|---|---|---|
| A1 | a class uses `m_x` that neither it nor its bases declare | CLEAN | `struct` bodies (only `^\s*class`); multiple inheritance; a declaration not on its own line ending in `;` |
| A2 | a macro used above its `#define` | CLEAN | use inside another `#` directive (skipped); second `#define` of the same name |
| A3 | `#property version` not `\d+\.\d\d` | FILES | other malformed properties |
| A4 | a literal passed to a `&` parameter, only for names with exactly one signature tree-wide | CLEAN | string literals (CLEAN blanks them); overloaded names; calls not ending in `;` |
| A5 | a struct/class ≥ 64 KB inline (2 MB local-section cap) | CLEAN | a type whose array length it cannot resolve (`ok=False`, silently unsized); unions; alignment |
| A6 | `g_x.Method()` where `Method` is declared nowhere | CLEAN | a method declared on the wrong class (that is A11) |
| A7 | same for `m_x.` and local `CSSRThing name;` receivers | CLEAN | pointer receivers; receivers named otherwise |
| A8 | `override` with no `virtual` of that name anywhere | CLEAN | wrong signature; `virtual` on a wrong class |
| A9 | the same `(name,args)` defined twice in one class | CLEAN | **pointer-returning methods** — `METHOD_DEF` demands `\s+` after `[\*&]?`, so `CSSRFoo *Get(void)` never matches (finding 26); a default argument containing `)` |
| A10 | a write to a parameter declared `const`, definitions only | CLEAN | writes through a reference/pointer; bodies > 900 lines; writes after a same-named local declaration (loop breaks) |
| A11 | `g_x.Method()` where that class has no such method (single inheritance folded) | CLEAN | pointers, locals, members |
| A12 | argument-count mismatch for `g_`/`m_` receivers of known class, when every declaration of that name on that class agrees | KEEPSTR | pointer receivers; ambiguous arities (skipped by design) |
| A13 | a call to a name nothing in the tree declares and that is not in `tools/ssr_known_calls.txt` | CLEAN | anything already in the baseline — including a real function later deleted; names starting `m_`/`g_`/`s_` (skipped as data) |
| A14 | object text > 63 chars, for `ObjectSetString(...OBJPROP_TEXT,"literal")` and for `.Label/.Button/.ButtonC/.Edit` at fixed argument indices 3/5/5/5 | **FILES (raw — comments included)** | `Chip`/`Group`/`Toast`/`Text` (finding 25); any runtime-built string; no vacuous-pass guard |
| A15 | `#define <…MS…> <big bare int>` that overflows one multiplication (`MSC_INT_MIN = 1_000_000`) | FILES | a constant whose name does not say MS/MSC; a value written as an expression |
| A16 | a string literal followed on the same line by a word or digit (an unescaped inner quote) | FILES | across lines (deliberately) |
| A17 | `C'r,g,b'` or `clrXxx` outside `SSR_Theme.mqh` / `SSR_QA_FontProbe.mq5`; `clrNONE` exempt | FILES with hand-rolled comment stripping (so single quotes survive) | hex `C'0xFF,0x00,0x00'`; a raw `uint`/`ColorToARGB`; one report per line only |
| A18 | WCAG contrast of hand-declared `SSR_CONTRAST: <fg> on <bg> <text|ui>` pairs in the **built** palette (4.5:1 text, 3.0:1 ui); plus token completeness across the unbuilt palette; plus a vacuous-pass guard at `< 20` pairs | FILES + `_active_branches` | a pair nobody declared; colour actually composited at runtime |
| A19 | (a) an enum value with no `SSRAddString` line; (b) any `SSRAddString` English text > 63; (c) **every `MQL5/Files/SSReplay/lang/*.txt` value > 63** — *this path never resolves, finding 23*; (d) a literal in the text argument of `Label/ButtonC/Button/Chip/Group/Toast/Edit/Text`, **files under `/Ui/` only**, with a vacuous-pass guard at `< 100` resolved `T(SSR_S_` calls | FILES + `_decomment` | draw calls outside `/Ui/` (the Expert has 7 `ObjectSetString(OBJPROP_TEXT)`, Chart/SSR_TradeLines 2); text with fewer than two consecutive letters |
| A20 | a `Render`/`Repaint` body in a `/Ui/` file with no `ChartRedraw` (a `Render()` call counts) | FILES + `_decomment` | anything not matching `^   void (Render\|Repaint)\(void\)$` — exactly 3 spaces, no `const`, no arguments; `SSR_FirstRun::Show` and `SSR_KeyCard::Show` draw and are invisible to it (finding 24) |
| A21 | `Bars(sym,tf,…)` / `SeriesInfoInteger(sym,tf,SERIES_BARS_COUNT)` on a non-M1 timeframe with no `CopyRates/CopyTime/CopyClose/iTime/iOpen/iHigh/iLow/iClose/iBars/SSR_WaitSeries` naming the same timeframe within 12 lines either side | FILES + `_decomment` | a timeframe argument that is not a bare identifier or `Foo()` — `g_cycle[i]`, `(ENUM_TIMEFRAMES)x` are invisible; `iTime` etc. as the read itself |

### 3.2 The three failure modes this file is explicitly written against

Stated in its own comments and worth preserving: *an audit that has never been
seen to fire is not evidence* (line 8); *an audit that cries wolf is worse
than none* (A12, 643-644); *the vacuous pass* — A18 and A19 both carry an
explicit guard against passing by having nothing to check (1262-1267,
1486-1496). A14 and A20 have no such guard, and A19's language-file half is
currently a vacuous pass in the literal sense (finding 23).

### 3.3 Companion tools (not audits)

* `tools/ssr_known_calls.py` — imports `ssr_audit` as a module and rewrites
  `ssr_known_calls.txt` from `called - declared`. Must only be run when the
  tree compiles; anything it writes is permanently allowed by A13.
* `tools/ssr_check_order.py` — explicitly "NOT wired into ssr_audit.py and
  should not be".

---

## 4. Where this subsystem's conclusions feed the product

| Spike metric | Product decision it is said to drive |
|---|---|
| A1 `max_symbol_name_length` | the `<SRC>.SSR<slot>` naming convention |
| A1 `properties_mismatch` | "PLAN B: manual property map required" |
| A2 `agg_*_ohlc_exact` | the central bet: write M1 only |
| A3 `avg_rebuild_time` | "feeds the Reset budget" |
| B2 `optimal_batch_size` | "lock this into Feeder" |
| B2 `best_ticks_per_sec` | the Adaptive Fidelity table; F2 vs F3 + bulk write |
| B4 `copyticksrange_week_return` | "sets the page size for TickSource" |
| B4 `tick_history_depth` | whether fidelity F1 (full tick) is real at all |
| C1 `service_can_*` | Core = Service vs Core = EA |
| C2 `no_restart` | same |
| C4 `symbol_time_equals_injected` | `SYMBOL_TIME` as the engine's official clock |
| D1 `bars_per_sec` | how deep higher-timeframe context can go; HistoryLoader chunk size |
| D2 `worst_switch` | "change timeframe without breaking replay" |
| D4 `step_back_interactive` | whether "Previous Candle" is a button or a "Rewind to point" operation |

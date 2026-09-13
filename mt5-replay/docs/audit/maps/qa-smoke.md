# Subsystem map — QA harness (`MQL5/Scripts/SSReplay/QA/`)

Build v125. Five **scripts** (`OnStart`, no classes of their own — every one is a
procedural driver over the product's classes). None is an EA, none has a timer,
none runs `OnTick`. All five are `#property script_show_inputs`.

| File | Lines | Role |
|---|---:|---|
| `SSR_QA_Preflight.mq5` | 716 | "can this terminal run SS Replay at all" — 6 sections, OK/LIMIT/BLOCKER, verdict GO / GO-WITH-LIMITS / NO GO |
| `SSR_QA_Smoke.mq5` | 5512 | the whole product assembled headless, ~250 PASS/FAIL lines across stages 1–43 |
| `SSR_QA_FontProbe.mq5` | 348 | glyph/width probe for the panel's font (separate agent scope; listed for completeness) |
| `SSR_Z_Cleanup.mq5` | 145 | removes spike + replay symbols, their charts, `SSR.` globals, optionally spike result files |
| `SSR_Z_Gaps.mq5` | 86 | reports holes in the broker's M1 history for a date range |

---

## 1. `SSR_QA_Smoke.mq5`

### 1.1 Inputs and module state
```
InpSymbol     ""   -> origin = (InpSymbol=="" ? _Symbol : InpSymbol)
InpReplayBars 400  window, in M1 bars
InpWarmupBars 200
InpSlot       9    "keeps it away from real sessions"
```
Globals: `g_pass`, `g_fail` (counters); `g_fh` (result-file handle),
`g_out_n` (lines logged), `g_path` (file actually written), `g_t0`/`g_tlast`
(tick counts for the elapsed + SLOW instrumentation).

### 1.2 Reporting surface (the only "framework" in the file)
Free functions, declared as prototypes at lines 68–74 because MQL5 needs the
prototype before the call.

| Function | Line | Effect |
|---|---:|---|
| `LogOpen()` | 152 | `FolderCreate("SSReplay")`, opens `SSReplay\qa-result.txt` `FILE_WRITE|FILE_TXT|FILE_ANSI|FILE_SHARE_READ`. On failure retries as `qa-result-<local-stamp>.txt` and announces the fallback via `Print` + `Comment`. |
| `Log(line)` | 198 | `Print` + `g_out_n++` + `Comment(...)` (build, line no., elapsed s, the line) + optional `SLOW` note when the gap since the previous line > 3000 ms + `FileWriteString` + `FileFlush` per line. **SLOW lines go to the file only, never to `Print`, and are not counted in `g_out_n`.** |
| `Ok(what,detail)` / `No(...)` | 225 / 228 | `g_pass++` / `g_fail++` and a `PASS`/`FAIL` line, `%-34s` |
| `Check(what,cond,detail)` | 256 | `cond ? Ok : No`; **returns cond** so stages gate on it. Documented invariant: never put a mutating call in the `cond` argument — MQL5 builds `detail` first (v90 produced six PASS lines with lying evidence). |
| `Note(what,detail)` | 262 | a `NOTE` line; **does not touch either counter** — the file's way of saying "this went unmeasured" |
| `Step(where)` | 278 | a `..` breadcrumb between two checks, so a freeze localises to one call |
| `Done()` | 5485 | totals line, closes `g_fh`, prints `--> SEND THIS ONE FILE: MQL5\Files\<g_path> (<g_out_n> lines)`, repeats it in `Comment` |

Helpers:
- `TickVerdict(CSSRCustomSymbolSink&)` (290) — reads `mgr.StatsInto(SSRSymbolStats)` and turns
  calls/added/rejected into the three distinguishable stories; the phrase
  "accepted every tick and built no bar … a swallowed write" is emitted when
  `rejected==0 && added>0`. Appended to the detail of every bar-count check that failed.
- `QVisible(chart,name)` (312) — `ObjectFind >= 0 && OBJPROP_TIMEFRAMES != OBJ_NO_PERIODS`.
  Encodes the panel's hide mechanism (hide == `OBJPROP_TIMEFRAMES`).
- `OpenChart(sym,tf,why)` (5255) — `ChartOpen`, and on 0 a **600 ms busy-wait spin**
  (`while(GetTickCount() < until && !IsStopped()) ;` — no `Sleep`) then one retry,
  because `ChartClose` is asynchronous. Fills `why` with both error codes and `ChartCount()`.
- `ChartCount()` (5280) — walks `ChartFirst/ChartNext`, capped at 512.
- `LabelBox(chart,name,x,y,w,h)` (5308) — real pixel box of an `OBJ_LABEL`:
  `TextSetFont(font, -fontsize*10, 0, 0)` + `TextGetSize`. Returns false for a
  non-label, an empty text, or a missing font/size. **Does not test visibility.**
- `LabelOverlaps(chart,prefix,worst)` (5346) — O(n²) pairwise intersection of all
  prefixed labels, 1 px tolerance, skips `<prefix>fill*` (the toast is an
  overlay by design). Returns the pair count, names the deepest.
- `PropCase(...)` (5405) — one evaluation, one equity curve, one verdict; builds a
  `CSSRTradingEngine` + `SSRPropRules` + `CSSRPropEvaluation`, walks `days`
  server days (tick → trade → `SetBalance` → `OnClock`), stops on `IsOver()`.
- `Stash(path)` / `Unstash(path)` (85 / 93) — `FileMove(path,0,path+".qabak",FILE_REWRITE)`
  and back. Used for `SSR_SETUP_FILE`, `SSR_PANEL_FILE`, `SSR_PRESET_FILE`, `SSR_SEEN_FILE`.
- `Cleanup(rsym)` (5466) — closes every chart whose `ChartSymbol()==rsym`,
  deselects, `CustomSymbolDelete`; a refusal is a `NOTE` naming `SSR_Z_Cleanup`, not a FAIL.

### 1.3 Assembly order in `OnStart` (this is the product's real order)
```
LogOpen
leftover sweep for tail = SSR_SYMBOL_SUFFIX + InpSlot   (charts, then symbols)
1  Bars(origin, PERIOD_M1) >= replay+warmup             -> abort if short
2  CopyRates(origin,M1,0,InpReplayBars) -> win_start/win_end (msc)
3  CSSRMt5DataSource.Open(origin)                       -> abort
4  CSSRCustomSymbolSink.SetSlot; rsym = SSRReplaySymbolName(origin,slot)
5  CSSRReplayController.Attach(src,sink); SetWarmupBars; Load(origin,win)  -> abort
   SYMBOL_EXIST / SYMBOL_CUSTOM / SYMBOL_CHART_MODE==BID / 7-day quote session
   CSSRTickSynthesizer: every synthesised tick carries TICK_FLAG_LAST
   CSSRTradingEngine acct (+SSRExecutionModel) registered as ctrl observer
6  Play + 60 x Pump(1000) at 60x -> clock advanced, candles appeared
7  chart follow (CSSRChartManager Sync/Redraw/Snaps)
8  StepBars(10)      9  JumpTo(+1h)      10 CSSRFlightRecorder
11 trading + CSSRJournal.ExportHtml   12 CSSRTradeLines   13 managed-vs-owned,
   OpenLayout, CSSRBlindMode   14 CSSRSessionManager   15 CSSRPropEvaluation
16 CSSRSetupPanel save/restore (+modes)   17 CSSRGroupPort manage/tags/stats/
   buckets/equity curve/statement   18 panel frame overflow, every sheet
19 panel position round trip   20 CSSRShotBook   21 presets   22 calendar
23 CSSRFirstRun   24 CSSRClassReport   25 pending orders   26 execution honesty
27 spread from the bar   28 reset confirmation   29 keys + CSSRKeyCard
30 the result file is readable while held   31 the same symbol replays twice
32 CSSRWidgets + SSRFrame/SSRRows layout   33 CSSRPalette   35 row transparency
36 CSSRRevealCard   37 CSSRReviewCard   38 prop meters + prop sheet
39 tall panel   40 label overlap measurement + right-edge clamp + line names
41 CSSRStrings + Persian   42 paint budget   43 close/reopen leaves nothing
ctrl.Release(); Cleanup(rsym); Done()
```
There is **no stage 34** (its numbers were folded into 16) and no stage 30b.

### 1.4 Invariants the file relies on
1. `Check`'s `cond` must be pre-computed into a bool when the call mutates.
2. `Bars()` answers from a cache — every bar-count comparison on `rsym` is
   preceded by a `CopyRates(rsym,M1,0,1,poke)` poke loop (20 × 50 ms) or a `Sleep(250/300)`.
3. Hiding is `OBJPROP_TIMEFRAMES == OBJ_NO_PERIODS`, never `ObjectDelete` (stages 18, 43, `QVisible`).
4. `SSRQ_bg` / `SSRE_bg` / `SSRT_bg` is the frame: the overflow test reads the
   frame off the background rectangle rather than from a layout constant.
5. An `OBJ_LABEL` reports `OBJPROP_YSIZE == 0`; the frame tests substitute 12 px.
6. MetaTrader draws 63 characters of `OBJPROP_TEXT`; asserted in stages 22a, 29,
   37 (`+ SSR_REVIEW_PREFIX`), 38 and 41.
7. `ChartOpen` can refuse right after a `ChartClose` (async) — hence `OpenChart`'s retry.
8. A stage that could not be exercised emits `Note`, which moves neither counter.
9. A precondition is asserted before the stage that depends on it ("the test
   checks its own eyes first" — stages 28, 35, 38, 39, 40).
10. `CSSRGroupPort.ReadState` returns false with no primary controller, so every
    port-driven stage first builds a `CSSRReplayGroup` and `Add(GetPointer(ctrl))`.

### 1.5 Disk and chart side effects
Writes: `SSReplay\qa-result.txt` (or `qa-result-<stamp>.txt`) — kept.
Writes and then deletes: the flight-recorder file, `SSReplay-smoke-statement*.html`,
`SSReplay-smoke-tags*.html`, the session file, `SSReplay\class-smoke.html`,
`SSReplay\class\class-{alice,bob,carol,notajournal}.csv` + `FolderDelete(SSReplay\class)`,
four PNGs under `SSReplay\journal\shots\<run>` + `FolderDelete`.
Moved aside and back: `setup.ini` (stage 16), `panel.ini` (stages 17–19 and 40 only),
`presets.ini` (21), `seen.txt` (23).
Chart: ~22 charts opened and closed; `Comment()` rewritten on every logged line
and once more in `Done()`. Creates and deletes the custom symbol
`<origin>.SSR<slot>` and closes any chart on it.

---

## 2. `SSR_QA_Preflight.mq5`

Inputs: `InpSymbol ""`, `InpWantBars 20000`, `InpTestCharts true`, `InpBenchBars 50000`.
State: `g_blockers`, `g_limits`, `g_ok`, `g_notes`. Reporting: `Ok` / `Limit` /
`Blocker` / `Head` (lines 31–40) — `Limit` and `Blocker` also append to `g_notes`,
which is reprinted in the summary. Verdict (707–713): any blocker → `NO GO`,
else any limit → `GO, WITH THE LIMITS ABOVE`, else `GO`.

| Section | Lines | What it establishes |
|---|---:|---|
| 1 the terminal | 57–99 | `TERMINAL_BUILD` (<1730 blocker, <2085 limit), `TERMINAL_MAXBARS` (<100000 limit), memory (<256 MB), disk (<200 MB), DLLs (only reported when *disabled*), `MQL_TESTER` → blocker |
| 2 the instrument | 101–146 | `SymbolSelect`, digits/point/tick value/tick size, point≠tick size stated, one lot one point in account currency, `SymbolInfoSessionQuote(MONDAY,0)` |
| 3 history depth | 148–260 | `SeriesInfoInteger` BARS_COUNT / FIRSTDATE / SERVER_FIRSTDATE, `CopyRates` **asked twice** (up to 30 × 500 ms) because a cold symbol answers −1; <2000 blocker, < asked limit; 200-day D1 = 288 000 M1 bars stated against what is loaded; `CopyTicksRange` over 3 days decides fidelity |
| 4 custom symbols | 262–440 | deselect → `Sleep(120)` → delete → `CustomSymbolCreate("SSRPreflight.SSR9", SSRReplaySymbolPath(), sym)`; on failure **adopts** an existing one; `SYMBOL_TRADE_MODE_DISABLED`; select; 500-bar `CustomRatesUpdate` + read back + M5 derived; 100 `CustomTicksAdd`; a real chart opened for 700 ms; deselect → `Sleep(100)` → delete |
| 5 write rate | 442–665 | second symbol `SSRPreflight.SSRB`; 3 passes of `InpBenchBars`, forward and disjoint (`cursor += InpBenchBars*60`); the clock stops when the **last bar becomes readable** (poll `CopyRates(bs,M1,b[n-1].time,1)`, 15 s deadline), not when the call returns; quotes the **slowest** pass; then 500 single-bar appends for the streaming rate and the bulk/stream ratio; states plainly whether 288 000 is measured or extrapolated |
| 6 write targets | 667–698 | `SSReplay\preflight.txt` written, read-shared, deleted; a `SSR.preflight` global set, read back, deleted |

Disk/chart: creates and deletes two custom symbols, opens and closes one chart,
writes and deletes one file, sets and deletes one global variable. Nothing is kept.

---

## 3. `SSR_Z_Cleanup.mq5`

Input `InpDeleteResults=false`. Module array `g_syms[15]` — the Phase-0 spike
symbol names (`SSRA1 … SSRD4`). Order is load-bearing and mirrors
`CSSRCustomSymbolManager::Destroy`: **close charts → deselect → wait → delete**,
because a symbol selected in Market Watch cannot be deleted (5306).
1. closes every chart whose symbol `StringFind(s,"SSR")==0 || StringFind(s,".SSR")>=0`, `Sleep(500)`
2. walks `SymbolsTotal(false)` backwards, deletes every name containing `.SSR`
   (deselect + `Sleep(120)` each); refusals are collected by name with their error
3. deletes the 15 spike symbols (deselect + `Sleep(60)`)
4. `CustomSymbolDelete` for the A1 length probes — "A"×4 … "A"×64
5. `GlobalVariablesDeleteAll("SSR.")`
6. optional `FileDelete` of `SSR_F_RESULTS`, `SSR_F_VERDICTS`, `SSR_F_ENV`,
   `c2_heartbeat.csv`, `d3_timeseries.csv`, `c1_service_probe.txt`
7. reports to the log **and to `Comment()`**, naming every stuck symbol and the remedy
8. states that leftover history under `bases\Custom` must be removed by hand

## 4. `SSR_Z_Gaps.mq5`

Inputs `InpSymbol ""`, `InpFrom`, `InpTo`, `InpMinRun 1`. Pure read-only: refuses
an empty range, `CopyRates(sym, PERIOD_M1, InpFrom, InpTo, r)`, reports
`n` bars over `span=(InpTo-InpFrom)/60` minutes as a percentage, first/last bar,
then every inter-bar gap `((r[i].time-r[i-1].time)/60)-1 >= InpMinRun` — first
20 printed, the rest summarised. "NO HOLES" is stated as "a replay that stalls
here is the engine's doing". Writes nothing, opens nothing.

## 5. `SSR_QA_FontProbe.mq5`
Measures the panel font's glyph coverage/widths (`TextSetFont`/`TextGetSize`) and
the 63-character draw limit. No product class is assembled. (Detailed in the
UI-font agent's scope.)

---

## 6. Cross-file contract
- `Preflight` is the gate; `Smoke` assumes it passed (it never re-checks terminal
  build, disk, memory or `MQL_TESTER`).
- `Smoke` sweeps only its own slot tail at start and calls `Cleanup(rsym)` at the
  end; anything it cannot delete is a `NOTE` that names `SSR_Z_Cleanup`, which is
  the only script that sweeps *all* slots and the spike symbols.
- `Z_Gaps` answers the one question `Smoke`'s "new CANDLES appeared" cannot:
  whether the broker had the minutes at all.

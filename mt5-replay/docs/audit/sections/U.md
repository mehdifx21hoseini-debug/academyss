## U. REAL MT5 TEST PLAN

### U.0 Why this section exists, and what it is allowed to claim

[CONFIRMED FROM CODE] The author has never run this product on a MetaTrader 5 terminal. The
codebase says so itself, repeatedly and in its own words: `SSR_QA_Smoke.mq5:6-7` — *"Eleven
releases have been shipped without a compiler or a terminal on this side, and the report coming
back has been 'it does not work'"*; `SSR_Widgets.mqh:122-123` — *"I cannot run this terminal - so
the panel measures itself instead of being trusted"*; `SSReplayStandalone.mq5:1940-1944` — *"This
project has assumed both answers about that at different times and measured neither."*

[INFERENCE] Everything downstream of that fact is the same shape of risk. Build v125 compiles;
audits A1–A21 pass (`tools/ssr_audit.py`, `audit_a1()` at :133 through `audit_a21()` at :1556);
sixteen test scripts exist under `MQL5/Scripts/SSReplay/Tests/`. **None of that touches the
runtime.** A compiler proves that names resolve. An audit proves that a pattern is absent from the
text. A headless test proves that objects compose. The failures this product has actually shipped
— a symbol that accepted every tick and built no candle, a chart handed over and never handed
back, a panel drawn ninety pixels onto the price, a timer turned back at the door forever — are
all runtime failures on a real terminal against a real broker's data, and not one of them is
reachable from the build environment.

[RECOMMENDATION] So this section is not a test suite. It is the **first contact protocol**: the
ordered list of things to put in front of a real terminal, in the order that fails fastest and
cheapest, with the exact evidence each one must produce. The ordering rule is the one the rest of
this audit uses — CRITICAL and HIGH first — with one exception stated immediately below.

#### U.0.1 The exception: three of the instruments are themselves broken

[CONFIRMED FROM CODE] Before any test can clear a finding, the instruments must be able to
report. Three cannot:

| Finding | Instrument | What it does instead |
|---|---|---|
| `qa-smoke-1` (MEDIUM, CONFIRMED) | `SSR_QA_Smoke.mq5:396` | Aborts the entire 43-stage run on an unprimed M1 series — and the priming call is the next line. Dropped on an M5/H1/D1 chart it reports `0 passed, 1 FAILED` from a terminal on which everything works. |
| `qa-smoke-2` (MEDIUM, CONFIRMED) | `SSR_QA_Preflight.mq5:397` | Counts tick *acceptance* and never asks whether a bar was built. On a LAST-mode instrument it prints `OK custom ticks 100 accepted` and `VERDICT: GO` on a terminal where the replay will produce no candle at all. |
| `qa-smoke-3` (MEDIUM, POTENTIAL_RISK) | `SSR_QA_Preflight.mq5:311` | Gates the whole custom-symbol round trip on `SYMBOL_DIGITS > 0`, so a zero-digit instrument skips create, write, read-back, M5 derivation, ticks, chart *and cleanup* — and still says GO. |

[RECOMMENDATION] **U-01, U-02 and U-03 are therefore tier 0 and run before everything else.** A
GO verdict from an uncorrected preflight on an index or a whole-point instrument is not evidence
of anything, and using one as the gate for the rest of this plan would repeat the exact mistake
the preflight header (`:8-11`) was written to prevent.

#### U.0.2 The bench

[RECOMMENDATION] Minimum viable bench, because the defects are *symbol-class* defects and one
broker will not show them:

| Slot | What | Why it is on the list |
|---|---|---|
| **T-FX** | Any forex pair, BID-quoted, 5 digits, e.g. EURUSD | The only class the code has been reasoned about exhaustively |
| **T-IDX** | An index CFD quoting LAST, ideally `SYMBOL_DIGITS == 0` (US30, DE40) | `mt5-symbol-2`, `mt5-symbol-3`, `qa-smoke-2`, `qa-smoke-3`, `spikes-audits-3` all live here |
| **T-FUT** | An exchange futures CFD with a session calendar (not 24/5) | `core-sync-1`, `data-4`, `core-engine-6`, `Apply247Sessions` (`SSR_CustomSymbolManager.mqh:399-401`) |
| **T-XAU** | A metal: 2–3 digits, large contract size, tick_size ≠ point | `SSR_QA_Preflight.mq5:317-322` prints the point-vs-tick-size divergence explicitly |
| **T-THIN** | Anything with real M1 holes — an exotic cross, or a CFD over a weekend edge | `data-2`, `data-4`, `core-sync-1`, `SSR_Z_Gaps.mq5` |
| **B2** | A *second broker* for T-FX | Tick-history depth, session declarations and M1 completeness are broker facts, not code facts |

[RECOMMENDATION] Terminal build ≥ 2085 for the main pass (`SSR_QA_Preflight.mq5:62-68` treats
1730–2084 as a LIMIT because `CustomTicksAdd` was still settling), and one pass on the oldest
build the audience actually runs. One screen at 100% DPI and one at 125% or 150% — every panel
coordinate in this product is a raw pixel, and `SSR_QA_FontProbe.mq5:54-57` is the only thing in
the tree that has ever thought about font scaling.

#### U.0.3 What counts as proof

[RECOMMENDATION] A test in this plan is not passed by someone saying it worked. Every test below
names its evidence, and the evidence is one of exactly four kinds:

1. **A log line**, quoted verbatim from the Experts tab, with the `[host]` / `[panel]` / `[i18n]`
   / `[symbol]` / `[vitals]` / `[spread]` prefix intact. The tree emits 100 `[host]` lines, 13
   `[panel]`, 6 `[spread]`, 5 `[news]`, 4 `[i18n]`, 3 `[shots]`, 3 `[setup]`, 2 `[vitals]`, 2
   `[symbol]`, and one each of `[ui]`, `[sink]`, `[port]`. Nearly every state transition worth
   testing already prints one.
2. **A file**: `MQL5\Files\SSReplay\qa-result.txt` (`SSR_QA_Smoke.mq5:112`), a black-box CSV
   `MQL5\Files\SSReplay-flight-<tag>-<stamp>.csv` (`SSR_FlightRecorder.mqh:140`), a session file
   under `MQL5\Files\SSReplay\sessions\*.ssr` (`SSR_SessionManager.mqh:43-44`), a journal CSV, or
   a statement.
3. **A number read back out of the product**, not off a screenshot — `PaintWrites()`
   (`SSR_Panel.mqh:3041`), `FrameOverflowRight()/Bottom()` (`:3037-3038`), `StatsInto()` tick
   counts, `Bars()` on the replay symbol.
4. **A screenshot or a frame strip**, and *only* for the things that are genuinely visual: where
   something sits on screen, what a glyph looks like, whether a candle moved. `tools/ssr_frames.py`
   exists for exactly this and says so in its own header (*"The black box CSV is still the better
   instrument for anything mechanical - it carries numbers, not pixels"*).

[CONFIRMED FROM CODE] The black box is the single highest-value instrument on this list and it is
**on by default** (`InpFlightRec = true`, `SSReplayStandalone.mq5:136`). Its preamble
(`SSR_FlightRecorder.mqh:157-190`) already records build, terminal, terminal build, broker,
origin, replay symbol, window, window bars, `one_chart`, `reused_seed`, `picked_start`,
`start_speed`, `pump_ms` and the origin's M1 bar count — which is most of a bug report before a
single row is written. Rows are `kind=S` samples every 500 ms and `kind=E` events, flushed per
line so they survive a hang or a kill (`:104-110`). `tools/ssr_flight.py` reads one and names the
first stuck layer.

[RECOMMENDATION] **Every test in this plan runs with `InpFlightRec=true` and `InpVitals=true`, and
the CSV is part of the evidence pack whether the test passed or failed.** A passing run's recording
is the baseline that makes the next failing one readable.

[CONFIRMED FROM CODE] One known defect in that instrument: `chart-13` (LOW, CONFIRMED) — the
recorder truncates `chart_id` to 32 bits at `SSR_FlightRecorder.mqh:256`, so the column that says
*which chart* a fault happened on is corrupt. Read the `chart_sym` column instead until it is
fixed.

#### U.0.4 Hygiene between runs

[CONFIRMED FROM CODE] `SSR_Z_Cleanup.mq5` removes spike symbols, their charts, global variables
and result files, and the engine itself prints its name when a replay symbol will not delete
(`SSR_Z_Cleanup.mq5:22-25`). `SSR_Z_Gaps.mq5` answers the one question that otherwise costs a
round trip — *the clock advanced and no candle appeared: was there nothing to emit, or did the
engine emit nothing?* — in about a second.

[RECOMMENDATION] Between tiers: run `SSR_Z_Cleanup`, confirm Market Watch holds no `*.SSR*`
symbol, and confirm `MQL5\Files\SSReplay\sessions\` holds only sessions you meant to keep. A
leftover replay symbol is not a neutral condition — it is precisely the input that puts the
product down the `Adopt()` path (`mt5-symbol-2`, `mt5-symbol-3`) instead of the `Create()` path,
and a run that accidentally takes that path will produce results attributed to the wrong code.

---

## TIER 0 — MAKE THE INSTRUMENTS TELL THE TRUTH

### U-01 — Preflight must be able to fail on a LAST-mode instrument
**Clears:** `qa-smoke-2` (MEDIUM, CONFIRMED) · **Depends on:** nothing
**Bench:** T-IDX, T-FUT

[RECOMMENDATION] The preflight is the gate for this entire plan, and on the symbol class where
this product's longest-lived defect lives, it cannot fail. Fix it first, then use it.

1. Patch `SSR_QA_Preflight.mq5` section 4 so that after `CustomSymbolCreate` succeeds it does what
   `CSSRCustomSymbolManager::Create` does at `SSR_CustomSymbolManager.mqh:383-395`: force
   `SYMBOL_CHART_MODE_BID`, read the property back, and report a BLOCKER if it did not take.
2. Patch the tick block at `:387-402` to set `TICK_FLAG_LAST` alongside `TICK_FLAG_BID|TICK_FLAG_ASK`
   (as the engine's own comment at `SSR_CustomSymbolManager.mqh:380-381` says the shipped ticks do).
3. After `CustomTicksAdd` returns, read `SeriesInfoInteger(test, PERIOD_M1, SERIES_BARS_COUNT)`
   and `SeriesInfoInteger(test, PERIOD_M1, SERIES_LASTBAR_DATE)` and assert the bar count grew or
   the last bar moved. Report `Blocker` if it did not.
4. Run the patched preflight on T-IDX. Run it again on T-FX.

**Expected:** T-FX prints `OK` for the new *bar was built* check. T-IDX prints either `OK` (the
chart-mode force worked and bars build) or a `BLOCKER` naming the chart mode — **never** a bare
`OK custom ticks 100 accepted` followed by `GO`.

**Proof:** the Experts tab. A new line of the form
`  OK       custom ticks built a bar               ...` or
`  BLOCKER  custom symbol chart mode               reads <n>, not BID`, and the summary count in
the verdict block.

**Clears/confirms:** clears `qa-smoke-2`. If step 3 fails on T-IDX *after* step 1 forced BID, that
is a new and much larger finding and the run stops here — it would mean
`SYMBOL_CHART_MODE_BID` does not take on this terminal, which is the assumption the whole
custom-symbol transport rests on.

---

### U-02 — Preflight must not skip itself on a zero-digit instrument
**Clears:** `qa-smoke-3` (MEDIUM, POTENTIAL_RISK) · **Bench:** T-IDX with `SYMBOL_DIGITS == 0`

1. Run the *unpatched* preflight once on a whole-point instrument and keep the log. (This is the
   only run in this plan that deliberately uses an uncorrected instrument, and its purpose is to
   confirm the finding.)
2. Read the log: confirm section 4 prints a create line and then **nothing** — no select, no
   500-bar write, no read-back, no M5 derivation, no ticks, no chart, no cleanup.
3. Check Market Watch for a leftover `SSRPreflight.SSR9`.
4. Replace the `SYMBOL_DIGITS > 0` existence test at `:311` (and the identical one at `:294`) with
   a test that cannot be fooled by zero digits — `SymbolInfoString(test, SYMBOL_PATH) != ""` under
   `ResetLastError()`, or `SymbolSelect(test, true)` returning true.
5. Re-run. Confirm the whole section executes and the test symbol is gone afterwards.

**Expected:** before the patch, section 4 is silent after create and `SSRPreflight.SSR9` is left
in Market Watch, selected, while the verdict still reads GO. After the patch, all seven checks
report and cleanup runs.

**Proof:** the two Experts logs side by side, and the Market Watch symbol list between them.

**Clears/confirms:** confirms `qa-smoke-3` at step 3 (a POTENTIAL_RISK becomes an observed fact);
clears it at step 5. [INFERENCE] The same `DIGITS > 0` test is used in production at
`SSR_CustomSymbolManager.mqh:338` (`mt5-symbol-3`, MEDIUM, CONFIRMED) and at
`SSReplayStandalone.mq5:2612` in the handover guard — a leftover-symbol test on a zero-digit
instrument is wrong in all three places, so patching the preflight does not clear the other two;
U-22 does.

---

### U-03 — The smoke harness must survive being dropped on a non-M1 chart
**Clears:** `qa-smoke-1` (MEDIUM, CONFIRMED) · **Bench:** T-FX

1. Open a fresh terminal session. Open an **H1** chart of T-FX and do not touch M1 anywhere.
2. Drop `SSR_QA_Smoke` on it with defaults.
3. Observe the result: a single FAIL at stage 1 and `0 passed, 1 FAILED`.
4. Move the priming call above the `Bars(origin, PERIOD_M1)` read at `:396`, or re-read after
   priming with the retry loop the preflight already uses at `SSR_QA_Preflight.mq5:191-197`.
5. Re-run from a fresh terminal session on the same H1 chart.

**Expected:** after the fix the harness runs all 43 stages from a cold, non-M1 chart.

**Proof:** `MQL5\Files\SSReplay\qa-result.txt` — before: one `FAIL` line and
`=== 0 passed, 1 FAILED ===` (written at `SSR_QA_Smoke.mq5:5487`). After: the full ladder of
`PASS`/`FAIL`/`NOTE` lines through stage 43 (`Step("43 closing the panel")`, `:5127`).

**Clears/confirms:** clears `qa-smoke-1`.

[RECOMMENDATION] While the file is open, note the `SLOW` markers the logger inserts when a step
took over 3 s (`:218-221`). The smoke log is a profile as well as a report and the slow stages on
a real terminal are information nobody in this project has ever had.

---

### U-04 — Baseline preflight on every bench symbol
**Confirms:** the bench itself · **References:** `SSR_QA_Preflight.mq5` in full
**Bench:** all six slots, both terminals

1. Run the patched preflight (U-01, U-02) on T-FX, T-IDX, T-FUT, T-XAU, T-THIN on terminal A, and
   on T-FX on terminal B.
2. For each, record from the log: terminal build (`:60-68`), `TERMINAL_MAXBARS` (`:70-76`), the
   `symbol specs` line (digits, point, tick_value, tick_size, `:299-303`), the
   `one lot, one point = ...` line (`:325-327`), `declared sessions` present or absent
   (`:331-337`), local M1 bars and `SERVER_FIRSTDATE` (`:346-372`), the
   `tick history / N ticks in the last 3 days` line (`:400-407`), and the write-rate figure from
   section 5.
3. Tabulate. This table is the reference every later test reads its expectations from.

**Expected:** GO on at least T-FX and one LAST-mode instrument. A NO GO is a finding about the
bench, not the product, and must be resolved before tier 1.

**Proof:** six Experts logs, and the table built from them.

**Clears/confirms:** nothing directly. [INFERENCE] It establishes the two facts that decide half
this plan: **how far back the broker's ticks actually go** (which is what `data-1` turns on), and
**which bench symbols quote LAST** (which is what `mt5-symbol-2` and `spikes-audits-3` turn on).

---

## TIER 1 — THE TWO CRITICALS

### U-05 — The handover stash is swept before it is read
**Clears:** `host-expert-1` (CRITICAL, CONFIRMED) · **Bench:** T-FX
**Configuration:** shipped defaults — `InpOneChart=true`, `InpSymbol=""`

[CONFIRMED FROM CODE] This is the highest-severity finding in the audit and it fires on the
shipped default configuration. Pass 1 stashes the origin symbol in a chart object named
`SSR_ORIGIN_HANDOFF` (`SSReplayStandalone.mq5:536`, written at `:546`) and hands the chart to the
replay symbol. Pass 2's `OnInit` calls `SSRPurgeChart(0, SSR_PICK_LINE)` at `:1806` — 63 lines
before it reads the stash at `:1869` — so `stashed == ""`, `origin == ""`, the
`on_replay && origin == ""` branch fires at `:1911` and `FailInit()` returns `INIT_FAILED`. And
because `g_origin` is `""`, `FailInit`'s chart-restore branch (`:825`,
`if(g_on_replay_chart && g_origin != "")`) does nothing, so the user is left on a chart showing a
custom replay symbol with no expert attached and no automatic way back.

1. Fresh terminal. Open a T-FX M5 chart. Note the chart's symbol and template.
2. Attach `SSReplayStandalone` with defaults. Pick a start line when asked, press Start.
3. Watch the Experts tab from the moment the chart goes blank.
4. Record what the second `[host] SS Replay build ... pass=... chart=... origin=...` line says.
5. Note whether the expert is still on the chart (a smiley / the EA name in the corner), and what
   symbol the chart is showing.
6. Detach, and try to get back to the original chart without editing anything by hand.

**Expected under the finding:** the second line reads
`[host] SS Replay build v125   pass=2 (on the replay chart)  chart=<T-FX>.SSR1  origin=<UNKNOWN>`
(the `<UNKNOWN>` substitution is at `:1910`), immediately followed by
`[host] this chart is already a replay symbol and I do not know which instrument it came from.
Attach SS Replay to a normal chart, or set InpSymbol to the origin, and try again.` (`:1915-1918`),
and the expert unloads. The chart stays on the replay symbol.

**Expected after the fix:** the same line reads `origin=<T-FX>`, no refusal is printed, and the
session builds — `[host] SESSION READY: window ... | ... bars | panel on ...` (`:1666`).

**Proof:**
- Experts tab: the `pass=2` line with `origin=` either `<UNKNOWN>` or the real symbol. This one
  line is the whole test.
- Black box: two CSV files will exist for the run (one per pass, since `Open()` is per attach,
  `SSR_FlightRecorder.mqh:127-141`). Pass 2's file will have a preamble and no `kind=S` rows.
- Screenshot of the chart after the EA unloads, showing the replay symbol and no expert.

**Clears/confirms:** clears `host-expert-1`. [RECOMMENDATION] Run this **first** among the
behavioural tests. Every other one-window test in this plan is downstream of it: if pass 2 never
initialises, `host-expert-3`, `host-expert-5`, `host-expert-6` and `mt5-symbol-1` cannot be
observed at all, and a tester will report them as "not reproducible".

[INFERENCE] Run the same test once with `InpOneChart=false` as a control. Two-window mode never
performs the handover (the stash is written only inside `if(one_chart_ok && !g_on_replay_chart)`,
`:1897`), so the session must build normally. A failure in *both* modes is a different fault and
this test does not diagnose it.

---

### U-06 — Rewind must not leave money in the balance
**Clears:** `trading-exec-1` (CRITICAL, CONFIRMED) · **Bench:** T-FX
**Configuration:** `InpCommission=7`, `InpBalance=10000`, `InpPauseSL=true`

[CONFIRMED FROM CODE] `SSR_TradingEngine.mqh:640` — rewind drops positions placed after the cut
without reversing their P/L, commission or swap from `m_balance`. Every downstream number is then
computed on a corrupted figure: Equity, statistics, the prop evaluation's daily-loss and target
tests, and `LotForRisk` (which sizes off `Equity()`).

1. Build a session on T-FX. Note the opening balance from the panel's Account sheet and from the
   `[host] ready ...` block.
2. Play to a quiet stretch. Open a BUY with the lines (R to arm, Tab to take).
3. Let it close — either by stop (auto-pause will announce it, `InpPauseSL=true`) or close it by
   hand. Record the realised P/L and the commission from the Positions/Journal sheet.
4. Read the balance now. It must be `10000 + realised − commission`.
5. Press `←` (StepBackward) enough times, or `J` and jump, to land **before** the entry.
6. Read the balance again, and the trade count.
7. Now press `0` (Reset) and confirm. Read the balance and the trade log again.

**Expected (correct behaviour):** at step 6 the trade is gone from the log **and** the balance is
back to 10000.00. At step 7 the balance is 10000.00 and the log is empty.

**Expected under the finding:** at step 6 the trade vanishes from the log and the balance still
reads `10000 + realised − commission`. At step 7 the log is empty and the whole session's realised
P/L is still in the balance — an empty trade list against a balance that is not the starting one.

**Proof:**
- Panel Account sheet, screenshotted at steps 4, 6 and 7. The balance figure is the evidence.
- Journal export (`InpSession` set, then the journal CSV from `[host] journal -> ...`, `:2170`) —
  the trade list and the balance disagree.
- Save the session at step 7 and re-open it: `ui-port-session-*` restore prints a
  *balance replayed from the trades* reconciliation line, which will not match.

**Clears/confirms:** clears `trading-exec-1`.

[RECOMMENDATION] Run U-07 in the same session immediately afterwards, because it is the same key
press with a different observable and separating them wastes a setup.

---

## TIER 2 — THE HIGH FINDINGS

### U-07 — Stops and targets must be rewound with the position
**Clears:** `trading-exec-2` (HIGH, CONFIRMED) · **Bench:** T-FX

[CONFIRMED FROM CODE] `SSR_TradingEngine.mqh:263` — SL/TP changes, trailing movement, break-even
and MAE/MFE are not versioned, so they survive a rewind. A trade that was +20 pips at the rewind
target gets closed on the first re-emitted tick by a stop that had not been moved there yet.

1. Same session as U-06. Set a trail distance from the panel so `SetTrailing` is applied to new
   trades (`SSR_GroupPort.mqh:1062-1063`).
2. Open a long. Let price run far enough that the trail has visibly moved the stop — watch the
   stop line on the chart move up.
3. Record the current stop price and the current time.
4. Press `←` repeatedly to step back to a minute when price was *below* the trailed stop but above
   the original stop.
5. Read the stop line's price. Let one more tick through.

**Expected (correct):** at step 5 the stop is back where it was at that instant, and the trade
survives.

**Expected under the finding:** the stop line is still at the trailed price, the first re-emitted
tick trips it, auto-pause announces `stop loss hit`, and a trade that was in profit at that moment
is closed at a loss.

**Proof:** chart screenshot at steps 3 and 5 showing the stop line's price label at the same
position on a different bar; the Journal row for the closed trade with reason `SL` and an exit
timestamp *earlier* than the trail movement that set that stop. `tools/ssr_frames.py` on a screen
recording is the clean version of this if the stop moves faster than a hand can screenshot.

**Clears/confirms:** clears `trading-exec-2`. [INFERENCE] Also exercises `core-engine-3`: the
`←` key routes through `StepBackward` → `JumpForward`, which bulk-writes bars to the sink and
publishes nothing to observers, so up to five replay-minutes pass with the trading engine blind.
U-08 isolates that.

---

### U-08 — Step back must not replay minutes blind to the trading engine
**Clears:** `core-engine-3` (HIGH, CONFIRMED) · **Bench:** T-FX

[CONFIRMED FROM CODE] `SSR_ReplayController.mqh:1383` — the bulk range `[bar_lo, last_bar-1]` is
written with `SeedBars` only; no `PublishBar`/`PublishTicks` exists on that path. `StepBackward`
(`:1451-1459`) restores the nearest checkpoint (≤ 5 replay-minutes earlier) then calls
`JumpForward(target)`.

1. Build a session. Open a long at 10:40 with a stop that will be hit around 10:45:40 — pick the
   levels off the chart so you know when it triggers.
2. Play forward past the stop-out to about 10:47:30. Confirm the trade is closed.
3. Press `←` once (target 10:46:00).
4. Read the position list and the trade log.

**Expected (correct):** the position is closed, because the stop at 10:45:40 is before the rewind
target of 10:46:00 and must be re-evaluated on the way forward.

**Expected under the finding:** the checkpoint at 10:45:00 is restored, `OnRewind(10:45:00)`
un-does the stop-out and the position is **open again**, `JumpForward(10:46:00)` bulk-writes bar
10:45 without publishing it, and the position is still open at 10:46 despite price having gone
through the stop.

**Proof:** black box CSV. `tools/ssr_flight.py` on the file; then read the `kind=S` rows around
the rewind — `clock` goes backwards, `seed_bars` jumps, `emit_ticks` does not. The position count
in the panel at step 4 is the human-readable half.

**Clears/confirms:** clears `core-engine-3`.

---

### U-09 — The step key must actually step
**Clears:** `core-engine-2` (HIGH, CONFIRMED) · **Bench:** T-FX

[CONFIRMED FROM CODE] `SSR_ReplayController.mqh:1169` — every `StepBars` lands the clock on
`xx:59.999`, and from there `target == now` for `bars == 1`, so the second `→` does nothing and
PgDn advances 9 bars instead of 10. `SSR_MasterClock.mqh:347-351` uses the identical formula.

1. Build a session with `InpAutoPlay=false`. Note the clock in the panel header.
2. Press `→`. Record the clock and the M1 bar count (the panel's `Bars` figure, or `Bars(rsym, PERIOD_M1)`).
3. Press `→` again. Record both.
4. Press `→` eight more times, recording after each.
5. Press Space to play, Space to pause. Press `→` once. Record.
6. Press PgDn. Record the bar count delta.

**Expected (correct):** each `→` advances the clock by one M1 bar; ten presses advance ten bars;
PgDn advances ten.

**Expected under the finding:** the first `→` advances one bar and lands on `HH:MM:59.999`; the
second through tenth do nothing at all (clock unchanged, bar count unchanged); after the
play/pause cycle the next `→` works once again; PgDn advances 9.

**Proof:** the clock readout in the panel caption, photographed or recorded across the ten
presses; and the black box, where ten `kind=E` command events are followed by one clock change.
[RECOMMENDATION] This is the cleanest single test in the plan to run on video — ten identical key
presses with one visible effect is unmistakable at 1 fps.

**Clears/confirms:** clears `core-engine-2`. [INFERENCE] This finding is also why `tests-a-17`
(`T8.3`'s headline assertion admits any tick count from 1 upward) passes today; the headless test
cannot see it.

---

### U-10 — FULL_TICK over a window with no broker ticks must not run silently
**Clears:** `data-1` (HIGH, CONFIRMED), `core-engine-4` (HIGH, CONFIRMED)
**Bench:** T-FX, and the broker whose tick depth U-04 measured

[CONFIRMED FROM CODE] `SSR_Mt5Providers.mqh:136` probes `has_ticks` over the **last 24 hours** of
held history, and the host then selects fidelity from it for a window that may be years earlier
(`SSReplayStandalone.mq5:1153`; `SSR_ReplayController.mqh:806`). `EmitWindow`'s FULL_TICK branch
then does `emitted = 0; m_cursor.Advance(hi, 0, 0); return emitted;` — the clock runs, the chart
does not move, the trading engine receives nothing, and nothing is reported.

1. From U-04, take the broker's actual tick depth for T-FX (the `tick history` line, and
   `SSR_B4_BrokerDataAudit` if a finer figure is wanted — noting `spikes-audits-19` and
   `spikes-audits-20`, both CONFIRMED, which make B4's depth walk and its page-size claim
   unreliable).
2. Configure a replay window **well inside** tick depth. Set fidelity to FULL_TICK (`D` cycles it).
   Play. Confirm candles form and the trading engine sees ticks.
3. Now configure a window **well outside** tick depth — months or years back, where M1 bars exist
   and ticks certainly do not. Use `InpStart` so there is no ambiguity about where it starts.
4. Read the panel's fidelity readout. Read the status ladder. Play.
5. Watch for 60 seconds at 30x.

**Expected (correct):** the product notices that this window has no ticks, degrades to SYNTHETIC,
says so on screen, and plays.

**Expected under the finding:** the fidelity readout says `FULL TICK` with no degradation marker
(`m_state.fidelity_effective == m_state.fidelity`, so the `!` at `SSR_Panel.mqh:891` and `:2034`
never appears), the clock advances, `[vitals]` shows `playing=1` and a rising clock with
`ticks=0`, and **no candle appears**. The replay reaches the end of the window having shown
nothing.

**Proof:**
- `[vitals]` line (`SSReplayStandalone.mq5:2352`): `clock=` advancing, `m1=` constant, `ticks=0`.
  This one line separates "the engine is stuck" from "the engine is running and emitting nothing",
  which is the distinction the whole finding is about.
- Black box: `kind=S` rows with rising `clock`, flat `m1`, flat `emit_ticks`, flat `last`.
  `tools/ssr_flight.py` should name this; if it does not, that is a gap in the tool worth fixing
  while the terminal is in front of you.
- `SSR_Z_Gaps` over the same window, to prove the M1 bars *are* there and this is not a data hole.

**Clears/confirms:** clears `data-1` and `core-engine-4` together — they are the probe and the
consumer of the same wrong boolean. [RECOMMENDATION] Also run step 3 with fidelity forced to BAR
as a control: if candles appear at BAR and not at FULL_TICK over the identical window, the
diagnosis is complete and needs no further argument.

---

### U-11 — The per-pump budget must defer bars, not drop them
**Clears:** `core-engine-1` (HIGH, CONFIRMED) · **Bench:** T-FX, on the slowest machine available

[CONFIRMED FROM CODE] `SSR_ReplayController.mqh:524` — when `EmitWindow` reads more M1 bars than
the budget allows, the bars above the cap are never emitted and the cursor is advanced to `hi`
anyway. The UI reports the pump as *deferred* while the bars are gone.

1. Make the budget bite. Either run on a slow machine / a chart loaded with heavy indicators
   (which is what the `[vitals] LATE` warning at `:2367-2372` is written for), or set a high
   `InpStartSpeed` and a short `InpPumpMs`.
2. Play at the highest speed the slider offers. Watch for the `[vitals] LATE` line.
3. When it appears, pause and press PgDn several times.
4. Compare the replay symbol's M1 bar count against the number of minutes the clock advanced.
5. Scroll the chart back over the region just played.

**Expected (correct):** bar count and elapsed minutes match; the chart has no holes.

**Expected under the finding:** the chart shows minute-scale holes; bar count is below elapsed
minutes; any SL/TP inside the dropped bars was never evaluated.

**Proof:** black box `kind=S` rows — `clock` advancing faster than `m1` grows, in a run where
`emit_calls` is also rising (so the engine is working, not idle). Plus a chart screenshot with a
visible gap, and `SSR_Z_Gaps` over the same origin range proving the origin has no hole there.

**Clears/confirms:** clears `core-engine-1`. [POTENTIAL_RISK] Whether the budget bites at all on a
given machine is a runtime fact nobody has measured; if it never bites on the bench hardware, this
test cannot clear the finding and must be reported as **not exercised**, not as passed.

---

### U-12 — Idle gap-skip must not bulk-write a bar the observers are still inside
**Clears:** `core-sync-1` (HIGH, CONFIRMED) · **Bench:** T-THIN, T-FUT

[CONFIRMED FROM CODE] `SSR_MasterClock.mqh:208` — at 8 synthetic ticks/bar and human speeds, after
25 pumps with no tick (1 s of wall time, while the next synthetic tick is 8.57 s away),
`NextBarAcross` returns a bar three minutes ahead, the `> now + 2 min` test passes, `SeekAllTo`
runs `JumpForward` on every stream, and the current bar is written in **bulk** — so observers
never receive the rest of it.

1. Use `SSR_Z_Gaps` on T-THIN to find a stretch where the origin's M1 history has two or more
   consecutive missing minutes. Record the exact time.
2. Build a session whose window contains that stretch. Defaults: `InpTicksPerBar=8`, SYNTHETIC
   fidelity, speed 1x–8x (the speeds a trainee actually uses).
3. Open a position with a stop that would be touched *inside* the bar immediately before the hole.
4. Play through the hole at 4x.

**Expected (correct):** the stop is evaluated against every synthetic tick of that bar before the
clock skips the hole.

**Expected under the finding:** the bar before the hole is bulk-written, the position's stop is
never tested against its remaining ticks, and the trade survives a bar it should not have.

**Proof:** black box around the skip — a `kind=S` row where `clock` jumps by minutes,
`seed_bars` increments, and `emit_ticks` does not. Journal shows no exit. The `SSR_Z_Gaps` output
from step 1 proves the hole is real history and not an engine fault.

**Clears/confirms:** clears `core-sync-1`. [INFERENCE] Index and futures CFDs hit this at every
daily close, so T-FUT will reproduce it without hunting for a hole — run it there too.

---

### U-13 — Auto-play must start on the pass that owns the chart
**Clears:** `host-expert-3` (MEDIUM, CONFIRMED) · **Depends on:** U-05
**Bench:** T-FX · **Configuration:** shipped defaults (`InpOneChart=true`, `InpAutoPlay=true`)

[CONFIRMED FROM CODE] `SSReplayStandalone.mq5:1710` — the guard tests `one_chart_ok` instead of
"am I about to hand over". Pass 2 runs with `on_replay=true` and `one_chart_ok=true`, so `Play()`
is never called and the log prints *auto-play waits for the handover* on the pass that **is** the
final one.

1. With U-05 fixed, run the defaults end to end.
2. After the handover completes and the panel appears, do not touch anything for 30 s.
3. Read the Experts tab.

**Expected (correct):** `[host] PLAYING at <speed> - press SPACE to pause. ...` (`:1713`) and
candles moving.

**Expected under the finding:** `[host] auto-play waits for the handover - this pass has no chart
to play on for more than a moment` (`:1721`) and a motionless chart with a live-looking panel.

**Proof:** the Experts line, and 30 s of black box with `playing=0` and a flat `clock`.

**Clears/confirms:** clears `host-expert-3`. [RECOMMENDATION] Run the control with
`InpOneChart=false`: auto-play is expected to work there, which localises the fault to the guard
and not to `Play()`.

---

### U-14 — Pass 2 must not read a stale `setup.ini`
**Clears:** `host-expert-6` (MEDIUM, CONFIRMED) · **Depends on:** U-05 · **Bench:** T-FX

[CONFIRMED FROM CODE] `SSReplayStandalone.mq5:1948` — pass 2 restores `setup.ini` unconditionally.
Any run that skips the start picker (`InpPickStart=false`, `InpStart>0`, `CfgRandom()`, or a
resumable session — the four conditions at `:2025`) never writes `setup.ini` on pass 1, so pass 2
reads whatever is on disk from an earlier run and every `Cfg*()` switches to it.

1. Run once through the setup wizard with deliberately memorable values: balance **10000**,
   prop **ON** with target 8%, session name **"stale"**. Let it write `setup.ini`. Detach.
2. Confirm `MQL5\Files\SSReplay\setup.ini` exists and holds those values.
3. Now attach with `InpPickStart=false`, `InpStart=<an explicit datetime>`, `InpBalance=25000`,
   `InpProp=false`, `InpSession=""`.
4. After the handover, read the panel's Account balance, look for the PROP chip in the caption
   row, and read the `[host] ready ...` line.
5. Detach and look in `MQL5\Files\SSReplay\sessions\`.

**Expected (correct):** balance 25000, no prop evaluation, no session file written.

**Expected under the finding:** `[host] carrying the setup across the handover` (`:1950`) on a run
that never opened the setup form; balance **10000**; a prop evaluation running and able to fail the
user; and a session file named `stale.ssr` that is both unexpected and liable to overwrite the
earlier one.

**Proof:** the `[host] carrying the setup across the handover` line is the direct evidence — it
should not be printed on this run at all. Plus the panel balance, the PROP chip, and the directory
listing at step 5.

**Clears/confirms:** clears `host-expert-6`. [INFERENCE] `ui-port-session-2` (MEDIUM, CONFIRMED —
saving truncates the previous good session before writing) makes step 5 worse than it looks: an
unexpected save to `stale.ssr` destroys the earlier `stale.ssr` before it writes. U-25 tests that
directly.

---

### U-15 — A random session must survive the handover
**Clears:** `host-expert-5` (MEDIUM, CONFIRMED) · **Depends on:** U-05
**Bench:** T-FX plus two extras in `InpAlsoSymbols`

[CONFIRMED FROM CODE] `SSReplayStandalone.mq5:1020` — with `InpRandom=true`, `InpSeed=""`,
`InpOneChart=true`, pass 2 either re-rolls a new seed (no `setup.ini` → `SSRSeedFromText("") == 0`
→ `SetSeed(0)` substitutes `SSRPickSeed()`) or drops randomness entirely — and with a non-empty
`InpAlsoSymbols` the new pick can be a *different instrument*, replayed under pass 1's symbol name.

1. `InpRandom=true`, `InpSeed=""`, `InpAlsoSymbols="<two other symbols>"`, `InpOneChart=true`.
2. Attach. **Copy the `[host] random session - <ticket>` line from pass 1 verbatim** (`:1041`).
3. Let the handover complete.
4. Read pass 2's `[host] random session` line, and the `[host] ready <origin> -> <replay symbol>
   <from> .. <to>` line (`:1593`).
5. Compare: same seed? same instrument? same window?

**Expected (correct):** pass 2 announces the same ticket, the same origin and the same window as
pass 1.

**Expected under the finding:** pass 2 announces a **different** seed and a different window, and
possibly a different origin instrument, while the replay symbol name (built from pass 1's pick)
stays the same. The seed printed on pass 1 reproduces nothing.

**Proof:** the two `[host] random session` lines side by side; the black box preamble
`# origin,...` and `# window,...` from each pass's CSV — two files, two different windows, one
run.

**Clears/confirms:** clears `host-expert-5`. [INFERENCE] This is also the precondition for U-33
(seed reproducibility): a seed that does not survive the handover cannot be tested for
reproducibility in the default configuration at all.

---

### U-16 — Warmup repair after a jump must actually write bars back
**Clears:** `mt5-symbol-1` (HIGH, CONFIRMED) · **Depends on:** U-05 · **Bench:** T-FX

[CONFIRMED FROM CODE] `SSR_CustomSymbolSink.mqh:265` — when the seed was reused from the cache
(`m_reused_seed == true`, which is exactly pass 2 of the one-window handover), `RepairWarmupIfLost`
returns true without calling `WriteBars`, while the controller logs *the sink dropped the warmup
... N bars written back* (`SSR_ReplayController.mqh:963-967`). The log asserts a repair that did
not happen.

1. Run the defaults through the handover so pass 2 has `reused_seed=1` (confirm from the black box
   preamble line `# reused_seed,1`).
2. Switch the replay chart to H1 or H4 so the warmup is visible as context to the left of the
   replay window.
3. Press `J` and jump forward a few hours.
4. Read the Experts tab for the warmup-repair line.
5. Scroll the chart left, past the current replay position.

**Expected (correct):** the warmup context is intact to the left of the current bar.

**Expected under the finding:** the log says N bars were written back, and the chart holds only
post-jump bars — the HTF context is gone and the log says it is not.

**Proof:** the controller's warmup-repair line, alongside a chart screenshot showing the missing
context; and `Bars(rsym, PERIOD_M1)` before and after the jump, which will not have grown by the
claimed N.

**Clears/confirms:** clears `mt5-symbol-1`. [INFERENCE] `core-engine-6` (MEDIUM, CONFIRMED —
warmup "bars" are calendar minutes) compounds this on a Monday-morning start; U-27 covers that.

---

### U-17 — Secondary charts must repaint
**Clears:** `chart-2` (MEDIUM, CONFIRMED) · **Bench:** T-FX primary, two extras
**Configuration:** `InpAlsoSymbols` with two symbols, `InpExtraTfs="M15,H1"`

[CONFIRMED FROM CODE] `SSR_ChartManager.mqh:574` — the explicit view-snap and `ChartRedraw` exist
only for the primary stream. The host calls `g_charts2[i].Sync()` (`SSReplayStandalone.mq5:2830`)
but never `Redraw()`, so secondary charts depend entirely on `CHART_AUTOSCROLL`, which this same
file documents at `:509-521` as not reliably honoured on a custom symbol written from an EA — and
at BAR fidelity no tick arrives to repaint them either.

1. Build a multi-symbol session. Confirm `[host] stream N: <sym> -> <replay sym>` (`:518`) for each
   and `[host] opened %d extra chart(s)` (`:1307`).
2. Arrange all charts visible. Play at 30x for two minutes.
3. Watch the primary and the secondaries.
4. Press `F` (Follow — *bring the charts back to now*).
5. Switch fidelity to BAR with `D` and play another two minutes.

**Expected (correct):** every chart advances together and every chart snaps back on `F`.

**Expected under the finding:** the primary advances and snaps; the secondaries lag, stop
following after the first manual scroll, or do not advance visibly at BAR fidelity at all.

**Proof:** a single screenshot of all charts at the same instant, with each chart's last bar time
readable — the clock disagreement is the evidence. Black box `first_visible` / `view_offset` /
`following` columns carry it for the primary only, which is itself part of the finding.

**Clears/confirms:** clears `chart-2`. [POTENTIAL_RISK] `chart-1` (MEDIUM, POTENTIAL_RISK) —
`DetectScroll` cannot tell bar arrival from a drag at high speed, and one false positive kills
following for the rest of the session. Step 2 at 30x is the condition that would trigger it: if
`F` is needed more than once without anyone touching a chart, report it against `chart-1`. Label it
POTENTIAL_RISK in the report; it depends on terminal scroll behaviour nobody here has measured.

---

### U-18 — A session save must not destroy the previous good save
**Clears:** `ui-port-session-2` (MEDIUM, CONFIRMED) · **Bench:** T-FX

[CONFIRMED FROM CODE] `SSR_SessionFile.mqh:138` — the destination is opened for writing directly,
with no temp-then-replace, so the previous save ceases to exist the moment `Create()` succeeds.

1. Build a session with `InpSession="probe"`. Trade a little. Detach cleanly so it saves. Confirm
   `[host] session saved -> ...` (`:2140`) and copy `probe.ssr` aside.
2. Re-attach, resume, trade more, and save again from the panel (`S` → save).
3. Now force an interruption mid-save: the honest version is to make the write fail — set the
   `sessions` folder read-only, or fill the volume — and attempt a save.
4. Inspect `MQL5\Files\SSReplay\sessions\probe.ssr`.

**Expected (correct):** the old file is intact, or a complete new one is in place. Never neither.

**Expected under the finding:** `probe.ssr` is zero-length or truncated, and the copy from step 1
is the only surviving session.

**Proof:** file size and content of `probe.ssr` before and after; `[host] session NOT saved: ...`
(`:2142`) in the log if the manager noticed at all.

**Clears/confirms:** clears `ui-port-session-2`. [RECOMMENDATION] The read-only-folder method is
the only one available without a debugger and it is a fair proxy: it exercises the same
"Create succeeded / Close never happened" window the finding describes.

---

### U-18B — A session name typed into the wizard must survive the next step
**Clears:** `ui-dialogs-1` (HIGH, CONFIRMED) · **Bench:** T-FX · **Depends on:** nothing

[CONFIRMED FROM CODE] `Ui/SSR_SetupPanel.mqh:300` — `Str()` returns `""` for an **absent** edit box
and treats it as a deliberate emptying (`:302` comment, *"an emptied box IS a choice here"*), while
`CSSRWidgets::EditText` cannot distinguish the two cases (`Ui/SSR_Widgets.mqh:350-356`:
`if(ObjectFind(m_chart, n) < 0) return ""`). `ReadAll()` reads `xtf` and `ses` unguarded at
`:1174-1175`, on every `next` (`:1061-1067`) and on `go` (`:1076`) — including steps that contain no
`OBJ_EDIT` at all, because `Repaint()` calls `m_w.RemoveAll()` (`:658`). The seed read two lines
below defends against exactly this with `m_w.Exists("eseed")` and a comment naming the hazard
(`:1180-1189`); the two string reads do not. The verified record adds that `go` exists only on the
START step, which never carries the `ses`/`xtf` boxes, so the wipe is on **every** start path, not
only after a MODE-step Next.

[INFERENCE] Consequence on the host side: `CfgSession()` (`SSReplayStandalone.mq5:231`) returns
`""`, and `OnDeinit`'s save is gated on `if(CfgSession() != "")` (`:2135`) — so no session is
written at all. That is why this test exists: **the audit has no evidence that any session has ever
been saved with a name set from the panel.** This is the fourteenth CONFIRMED HIGH and the only one
that had no test in the first draft of this plan.

1. Attach with `InpSession=""` so the only source of a session name is the wizard. Open the setup
   wizard.
2. On step 1, type `probe18b` into **Save as** and `H1,H4` into **Extra timeframes**.
3. Press **Next** into the MODE step. Press **Next** again (this is the press that calls
   `ReadAll()` on a step with no edit boxes). Then press **Back** twice to return to step 1.
4. Read the two boxes on screen, then advance to the recap step and read the **Save as** line.
5. Press **go**. Trade briefly, then detach cleanly.
6. Open `MQL5\Files\SSReplay\setup.ini` and read the `session=` key. Read the Experts tab for
   `[host] session saved -> ...` (`:2139`) or `[host] session NOT saved: ...` (`:2141`).
7. Repeat once by the quick path: `qlast` → recap → `go`, with a name already in `setup.ini`.

**Expected (correct):** `probe18b` and `H1,H4` are still in the boxes at step 1, the recap reads
`Save as: probe18b`, `setup.ini` holds `session=probe18b`, `[host] session saved -> ...` appears,
and `MQL5\Files\SSReplay\sessions\probe18b.ssr` exists on disk.

**Expected under the finding:** both boxes are empty on return, the recap reads `Save as: not
saved`, `setup.ini` holds `session=`, **no** save line appears in the Experts tab, and no `.ssr`
file is written. On the quick path, a session name that was already in `setup.ini` is overwritten
with empty. The extra timeframes set in the panel also never take effect — check the chart
timeframes actually opened against `H1,H4`.

**Proof:** a screenshot of step 1 after the return, the recap line, the `session=` line of
`setup.ini`, the presence or absence of the save line in the Experts tab, and a directory listing of
`MQL5\Files\SSReplay\sessions\`.

**Clears/confirms:** clears `ui-dialogs-1`. [RECOMMENDATION] This test also gates U-18 and U-19: a
save that never happens cannot be observed to truncate a previous save or to restore into the wrong
instant. Run U-18B **before** U-18 if the wizard is the path used to set the session name; U-18 and
U-19 as written set it through `InpSession`, which bypasses the defect, so run them that way until
0C.11 lands.

---

### U-19 — Restore must not install an account the streams have not reached
**Clears:** `ui-port-session-3` (HIGH, CONFIRMED) · **Bench:** T-FX

[CONFIRMED FROM CODE] `SSR_SessionManager.mqh:350` — Restore never checks that the streams reached
the saved instant, and cannot rewind to it. When the engine is already past it, the trade log is
rewound to T1 while the market stands at T2, and `ResumeReport` announces T2 as the resumed
instant with no warning.

1. Build a session `InpSession="resume1"`, play to T1, trade, save, detach.
2. Re-attach with a configuration whose window makes the engine start **after** T1 — e.g. a later
   `InpStart`, or let the auto window move.
3. Read `[host] ` + `ResumeReport()` (`:1486`) and `[host] resumed at <t>` (`:1535`).
4. Compare the announced instant against the clock in the panel and against the trade log's last
   timestamp.

**Expected (correct):** either the engine rewinds to T1, or the resume is refused with a reason.

**Expected under the finding:** the resume report announces T2, the account is the one saved at
T1, and nothing says the two do not correspond.

**Proof:** the `ResumeReport` text, the `[host] resumed at ...` line, and the panel clock — three
timestamps that should agree and do not.

**Clears/confirms:** clears `ui-port-session-3`. [INFERENCE] Also watch for
`ui-port-session-8` (MEDIUM, CONFIRMED): resume warnings are newline-joined into a **single
63-character label**, so whatever the report says on screen is truncated at 63 characters and any
newline is drawn as nothing. The Experts log is the only place the full text exists — which is the
finding.

---

### U-20 — Resuming must not void a running prop evaluation
**Clears:** `trading-analytics-1` (HIGH, CONFIRMED) · **Bench:** T-FX

[CONFIRMED FROM CODE] `SSR_PropEvaluation.mqh:443` — with `InpProp=true` and `InpResume=true`
against an existing session file, the evaluation is VOID before the first candle is played, the
replay auto-pauses, and the only way out is Reset, which restarts day counting from zero
(`trading-analytics-2`, MEDIUM, CONFIRMED — prop state is not persisted at all).

1. `InpProp=true`, `InpSession="prop1"`, `InpResume=true`. Build, trade across two replay days,
   save, detach.
2. Re-attach with the same inputs.
3. Read the Experts tab and the panel's Prop tab before touching anything.

**Expected (correct):** the evaluation resumes with its day count and its floors intact.

**Expected under the finding:** the status ladder announces `evaluation VOID - the clock was moved
backwards at <now>`, the replay is paused, and the Prop tab shows a voided run on a session that
was never rewound by the user.

**Proof:** the auto-pause announcement in the status strip (screenshot), the `[host] EVALUATION:
...` line (`:1201`) and the deliberate-rewind note at `:1202`, and the Prop tab's day counter
reading 0 after a Reset.

**Clears/confirms:** clears `trading-analytics-1`, and observes `trading-analytics-2` in the same
run. [INFERENCE] `ui-port-session-6` is classified **NOT_A_BUG** and must not be reported as a
defect even though it names the same area.

---

### U-21 — The panel must not draw on the candles
**Clears:** `ui-panel-6` (MEDIUM, CONFIRMED), `ui-panel-3` (HIGH, CONFIRMED), `ui-panel-13` (LOW,
CONFIRMED) · **Bench:** any · **Both layouts, all three palettes** (see U-35, U-36)

[CONFIRMED FROM CODE] `SSR_Panel.mqh:2033` — the status strip anchors the fidelity readout at
`x+330` inside a 310 px frame (`SSR_PANEL_W`, `SSR_Theme.mqh:487`): 20 px outside before a glyph
is drawn, and `SYNTHETIC TICK` at `SSR_FS_SMALL` runs another 70–80 px past that. **The layout
overflow instrument cannot report it**, because `CSSRWidgets::Extent` covers sized objects only
and a label's width depends on glyphs MQL5 will not disclose (`SSR_Widgets.mqh:126-128`).

1. Attach with defaults on a chart ≥ 400 px tall. Let the panel draw.
2. Screenshot the panel's right edge at 1:1. Measure where the fidelity text ends relative to the
   frame.
3. Degrade fidelity (press `D`) so the readout becomes `SYNTHETIC TICK !`. Screenshot again.
4. Enable BLIND (`InpBlind`) and PROP together so both caption chips are shown, and screenshot the
   caption row (`ui-panel-13`: chips overrun the collapse button by 6 px).
5. Now shrink the chart below `SSR_PANEL_H + 24` — open the Toolbox — to force compact mode.
   Screenshot the whole panel and the 130 px of chart below it.
6. Click where the tab rail *was*, below the compact body.

**Expected (correct):** nothing is drawn outside the frame in any mode; compact mode hides the tab
rail and the action strip.

**Expected under the finding:** ~90 px of `SYNTHETIC TICK` text sits on the price on every frame;
the caption chips overlap the collapse button; and in compact mode `tab0..tab4`, the `tabline` and
the three action buttons stay visible at full-layout coordinates — up to 122 px of stray,
**still-clickable** tab buttons painted on the candles (`ui-panel-3`: `HideBody(false)` at `:729`
undoes `HideSheetArea(true)` at `:682` inside the same `Render()`), and clicking one at step 6
changes the sheet.

**Proof:** screenshots at 1:1, with the frame edge marked. Plus `FrameOverflowRight()` /
`FrameOverflowBottom()` read from the panel — **which will read 0**, and that zero is itself part
of the evidence for `ui-panel-6`: an overflow the instrument cannot see.

**Clears/confirms:** clears `ui-panel-6`, `ui-panel-3`, `ui-panel-13`.
[RECOMMENDATION] Repeat step 5 on all three palettes and both layouts — U-35 and U-36 fold this in
rather than repeating the setup.

---

### U-22 — The handover guard must refuse safely, including on a zero-digit instrument
**Clears:** `mt5-symbol-3` (MEDIUM, CONFIRMED) · **Confirms:** the guard at
`SSReplayStandalone.mq5:2606-2670` · **Bench:** T-FX, T-IDX (`DIGITS == 0`)

[CONFIRMED FROM CODE] The guard asks three cheap questions before taking the user's chart — the
replay symbol *exists*, is *in Market Watch*, and *has bars* — and leaves the chart alone with a
named reason if any fails (`:2606-2622`), then opens a separate window instead so the replay is
not invisible (`:2648-2670`). [INFERENCE] This is one of the best-designed pieces of defensive
code in the product and it has never been executed. It also uses the same `SYMBOL_DIGITS > 0`
existence test that `mt5-symbol-3` identifies as wrong for whole-point instruments, at `:2611`.

1. **Happy path, T-FX:** run defaults. Confirm `[host] handing this chart over to <rsym> - SS
   Replay will restart once on it. This is expected.` (`:2675`) and the `Comment()` block
   explaining the blank second (`:2696-2701`).
2. **Forced refusal:** make the replay symbol fail one of the three tests — the cleanest is to
   remove it from Market Watch between creation and the handover, or run with a slot whose symbol
   cannot be selected. Confirm the refusal line at `:2614-2620` names *which* of the three checks
   failed, and that the chart is untouched.
3. Confirm a separate window opened on the replay symbol and the log says
   `[host] opened a separate window on <rsym> instead. Your chart is untouched.` (`:2662`).
4. Confirm the black box carries `handover refused: <rsym> exists=.. shown=.. m1bars=.. tf=..`
   as a `kind=E` row (`:2625-2630`).
5. **Zero-digit path, T-IDX:** leave a replay symbol behind (kill the terminal mid-session, or open
   a chart on it so `Destroy()` cannot remove it), then start a new session on the same slot.

**Expected (correct):** at step 5 the leftover is **adopted**, the session builds, and the log says
so — the behaviour `SSR_CustomSymbolManager.mqh:332-336` intends.

**Expected under `mt5-symbol-3`:** on the zero-digit instrument the fallback evaluates
`exists = false` because `DIGITS` is 0, `Create()` returns `SSR_ERR_INTERNAL
"CustomSymbolCreate(...) failed"`, and the session dies with `SINK_FAILED` — where the same
sequence on T-FX adopts and continues.

**Proof:** the `[host] NOT handing this chart over: ...` line with its three named states; the
black box `handover refused` event; and for step 5, the `SINK_FAILED` error text on T-IDX against
a clean adoption on T-FX. `T3.7` ("a leftover symbol is adopted, not fatal") passes today only
because it runs on digits > 0.

**Clears/confirms:** clears `mt5-symbol-3` and gives the handover guard its first real execution.

---

## TIER 3 — SYMBOL CLASSES, DIGITS, CONTRACT SIZES, SESSIONS

### U-23 — LAST-mode instruments: the defect that outlived every other
**Clears:** `mt5-symbol-2` (MEDIUM, POTENTIAL_RISK), `spikes-audits-3` (MEDIUM, CONFIRMED)
**Bench:** T-IDX, T-FUT

[CONFIRMED FROM CODE] `SSR_CustomSymbolManager.mqh:383-395` forces `SYMBOL_CHART_MODE_BID` on
`Create()` **and reads it back**, printing `[symbol] <sym> did NOT take SYMBOL_CHART_MODE_BID (it
reads <n>). Its bars are built from the LAST price, and the engine's ticks will be accepted and
build nothing.` if it did not take. [POTENTIAL_RISK] `Adopt()` at `:476` does **not** force it, and
`m_chart_mode_ok` stays false — so a replay symbol entered through adoption (a leftover chart, a
seed-cache hit) keeps whatever mode it had.

1. Create path, T-IDX: fresh terminal, no leftovers, build a session. Read the Experts tab for a
   `[symbol]` line. Play 60 s.
2. Adopt path, T-IDX: leave the replay symbol behind (open a chart on it, detach the EA), then
   start a session on the same slot so `Adopt()` runs. Play 60 s.
3. In both, read `SymbolInfoInteger(<rsym>, SYMBOL_CHART_MODE)` — the smoke test's stage 4 does
   this, or read it with a one-line script.
4. In both, compare `Bars(<rsym>, PERIOD_M1)` before and after the 60 s of play, and the sink's
   `ticks_calls` / accepted / refused counts (`TickVerdict`, `SSR_QA_Smoke.mq5:284-297`).

**Expected (correct):** both paths report `SYMBOL_CHART_MODE_BID`; candles form in both.

**Expected under `mt5-symbol-2`:** the Create path forms candles and the **Adopt path does not** —
every tick accepted, zero refused, and no bar built. This is the exact signature the
`TickVerdict` helper exists to name: *"the engine offered ticks, the terminal took them and built
nothing"*.

**Proof:** the `[symbol]` line (or its absence), the chart-mode readback, and the
accepted-vs-bars-built pair. [RECOMMENDATION] That pair — **ticks accepted > 0 and bars built ==
0** — is the single most valuable assertion missing from the whole QA layer, and U-01 adds it to
the preflight. Add it to the smoke test's stage 4 as well while you are here.

**Clears/confirms:** clears `mt5-symbol-2` (promoting it from POTENTIAL_RISK to a decided
outcome either way) and, via the spike kit, `spikes-audits-3` — `SSR_MakeSymbol`
(`SSR_SpikeKit.mqh:314`) never sets `SYMBOL_CHART_MODE` and the kit's generator never sets
`TICK_FLAG_LAST` (`:592`), so B1 on an index origin will report the transport broken when it is
not. Run `SSR_B1_TicksAddBroadcast` on T-IDX before and after patching the kit to prove it.

---

### U-24 — Digits, point, tick size and contract size must all reach the money
**Clears:** nothing directly · **Confirms:** the risk model on non-forex instruments
**Bench:** T-FX (5 digits), T-XAU (2–3 digits, large contract), T-IDX (0–1 digits)

[CONFIRMED FROM CODE] The preflight already draws the line that matters: *"POINT IS NOT TICK SIZE,
and code that assumes it is will be wrong by exactly the ratio between them. Every money figure in
this product goes through `CSSRRiskEngine`, which divides by tick_size and never by point"*
(`SSR_QA_Preflight.mq5:311-316`), and it prints `one lot, one point = <x> <currency>` at `:325-327`.

1. Run the patched preflight on each of the three and record the `symbol specs` line and the
   `one lot, one point` figure.
2. For each, build a session and open a 1.00-lot position with a stop exactly 100 points away.
3. Read the panel's risk preview **before** the fill: the money-at-risk figure.
4. Take the trade, let the stop hit, and read the realised loss from the Journal.
5. Compare (3) and (4) against `100 × one-lot-one-point` from step 1.

**Expected:** all three agree to within commission and slippage on all three instruments. A
divergence by exactly the point/tick-size ratio on T-XAU or T-IDX is a risk-engine defect and a
new finding.

**Proof:** the preflight `one lot, one point` line, a screenshot of the risk preview, and the
Journal row. Three numbers that must reconcile.

**Clears/confirms:** [INFERENCE] This is a *gap-finding* test, not a finding-clearing one. No
confirmed finding covers contract size on non-forex instruments — because it cannot be reasoned
about from source without a broker's actual specs — so this is where a new one would come from.
Anything found here is a new finding and must be recorded as such, not attributed to an existing id.

---

### U-25 — Instruments that do not quote 24/5
**Clears:** `data-4` (MEDIUM, CONFIRMED), `core-engine-6` (MEDIUM, CONFIRMED)
**Confirms:** `Apply247Sessions` · **Bench:** T-FUT, T-IDX

[CONFIRMED FROM CODE] `SSR_HistoryCatalog.mqh:150` — `warmup_bars` is used both as a **count of M1
bars** and as a **span of wall-clock minutes**, so on any instrument that does not quote every
minute the two disagree. `SSR_ReplayTimeline.mqh:80` — warmup "bars" are calendar minutes, so a
Monday-morning start seeds almost no warmup and the HTF chart opens empty. And
`SSR_CustomSymbolManager.mqh:399-401` applies 24/7 sessions to the replay symbol precisely because
*"A symbol that quotes for six hours a day replays six hours of candles and swallows the rest"*,
printing `[symbol] <session note>` when the origin declares fewer than 7 session days.

1. Preflight T-FUT. Record whether `declared sessions` is `present` or the fallback LIMIT
   (`SSR_QA_Preflight.mq5:331-337`).
2. Build a session on T-FUT with `InpWarmupBars=1000` and `InpChartTf=H1`. Read the `[symbol]`
   session-note line.
3. Look at the replay chart's H1 context to the left of the start. Count the H1 candles.
4. Repeat with a start at the **Monday open** of T-FX (a 1000-minute warmup that lands in the
   weekend).
5. Repeat with a start at the T-FUT session open.

**Expected (correct):** ~16 H1 candles of context in all cases (1000 minutes ≈ 16.7 hours of
*trading* minutes).

**Expected under the findings:** at step 4 and step 5 the context is almost empty, because 1000
calendar minutes back from a session open is mostly closed market, and nothing says so.

**Proof:** chart screenshots with the context candle count visible; the
`[host] SHORT ON HISTORY: asked for %d replay + %d warmup ...` line (`:1111`) if it fires; the
`[symbol]` session note.

**Clears/confirms:** clears `data-4` and `core-engine-6`, and gives `Apply247Sessions` its first
execution on an instrument that actually needs it.

---

### U-26 — Missing data: the clock advanced and no candle appeared
**Clears:** `data-2` (HIGH, POTENTIAL_RISK) · **Bench:** T-THIN

[CONFIRMED FROM CODE, POTENTIAL_RISK] `SSR_BarWindow.mqh:218` — one invalid-OHLC or non-positive
M1 bar voids the **entire** read window (up to 60,000 bars), and the provider reports that as zero
bars. Whether any real broker ships such a bar is a runtime fact.

1. Run `SSR_Z_Gaps` over a wide range of T-THIN with `InpMinRun=1`. Record every hole.
2. Build a session spanning the largest hole. Play through it.
3. If the session builds with **zero** bars where the catalogue said bars exist, that is `data-2`
   firing — a single bad bar voided the window.
4. If it builds and plays, confirm the clock crosses the hole and the chart simply has no candles
   there, and that `SSR_Z_Gaps` proves the hole is in the origin.

**Expected:** a hole in the origin produces a hole in the replay and nothing else. A window that
reads zero bars while the catalogue says otherwise is `data-2`.

**Proof:** `SSR_Z_Gaps` output; the `[host] %d M1 bars inside the replay window` line (`:1655` or
`:1660`) versus the `[host] WARNING: only %d bars inside the replay window` line (`:1644`); the
black box `m1` column across the hole.

**Clears/confirms:** decides `data-2` — either it fires on a real broker's data (promote to
CONFIRMED with the offending bar's timestamp) or it does not on this bench (it stays
POTENTIAL_RISK, and the report says which brokers were tried). **It must not be reported as
confirmed on the strength of this test unless a voided window is actually observed.**

[RECOMMENDATION] Also watch for `data-7` (LOW, CONFIRMED — `Discover()` discards the last complete
M1 bar whenever the market is closed): run the same discovery over a weekend and compare the
reported range end against the true last bar. One minute, every time, and easy to see in the
`[host] ready ... <from> .. <to>` line.

---

### U-27 — Large history: the download, the ceiling and the wait
**Clears:** `host-expert-11` (LOW, CONFIRMED) · **Confirms:** `EnsureHistory`
**Bench:** T-FX on a broker with deep history

[CONFIRMED FROM CODE] `EnsureHistory` prints its whole progress (`:639`, `:644`, `:662`, `:683`,
`:693`, `:698`), has a 60-second budget, and **computes that budget with a `ulong` subtraction of a
32-bit tick count**, so it breaks at the `GetTickCount` wrap (`host-expert-11`, `:651`).
`TERMINAL_MAXBARS` is checked by the preflight at `SSR_QA_Preflight.mq5:70-76`.

1. Fresh terminal, cold history. Set `InpAutoHistory=true`, `InpHistoryBars=60000` (the default,
   ~6 weeks).
2. Attach and time the wait. Record every `[host] history:` line.
3. Repeat with `InpHistoryBars` at a value beyond what the server offers, and confirm
   `[host] history: the broker's earliest M1 bar is <t> - ...` (`:662`) rather than a silent stall.
4. Set `TERMINAL_MAXBARS` below the warmup requirement (Tools → Options → Charts) and repeat;
   confirm the preflight's LIMIT and observe what the warmup actually does.
5. [RECOMMENDATION] The `GetTickCount` wrap occurs 49.7 days after boot and cannot be provoked on a
   bench. Fix `:651` to use `GetTickCount64()` and record it as fixed-not-tested.

**Expected:** the download completes or stops with a named reason within the budget; the chart
warmup reflects `TERMINAL_MAXBARS`; nothing hangs silently.

**Proof:** the full `[host] history:` sequence with wall-clock timestamps from the Experts tab, and
the preflight's `max bars in chart` line from U-04.

**Clears/confirms:** clears `host-expert-11` by inspection-and-fix (not by observation — say so).
Confirms the history path end to end, which nothing else in this plan does.

---

## TIER 4 — THE THREE FIDELITY MODES

### U-28 — FULL_TICK
**References:** U-10 (the silent-void case) · **Bench:** T-FX inside tick depth

1. Window inside tick depth, confirmed from U-04.
2. `D` until the readout reads `FULL TICK` with no `!`.
3. Play at 1x for 60 s, then 30x for 60 s.
4. Record from the black box: `emit_calls`, `emit_ticks`, `m1`, `pumps`, `delta_ms`.
5. Open a position with a tight stop inside a single bar and confirm it is evaluated intrabar.

**Expected:** `emit_ticks` ≫ `emit_calls`; candles form tick by tick; an intrabar stop fires at the
tick that touched it, not at a bar boundary.

**Proof:** black box columns; the Journal exit timestamp with sub-minute resolution.

**Clears/confirms:** [INFERENCE] Exercises `strategy-integration-report-1` (HIGH, CONFIRMED — in
FULL_TICK the market view is never fed bars, so a strategy reads a snapshot frozen at the first
pump). Run with `InpRefStrategy=true` and confirm from `[host] strategy: ...` (`:1242`) and the
strategy report (`:2165`) whether it traded at all. A strategy that produces zero decisions across
a full session at FULL_TICK, and decisions at SYNTHETIC over the identical window, is the
observation that clears it.

---

### U-29 — SYNTHETIC_TICK
**Clears:** `spikes-audits-1` (HIGH, CONFIRMED), `core-sync-2` (MEDIUM, CONFIRMED)
**Bench:** T-FX

[CONFIRMED FROM CODE] `SSR_SpikeKit.mqh:579` — `SSR_BarToTicks` never emits a tick at the bar's
high or low unless `(n-1)` is divisible by 3. `SSR_TickSynthesizer.mqh:54` — spread statistics
count synthesis *calls*, not bars, because the bar containing the clock is re-synthesised every
pump.

1. `InpTicksPerBar=8` (default). SYNTHETIC fidelity. Play 200 bars.
2. Place a stop exactly at a bar's high and another exactly at a bar's low, chosen from bars ahead
   in the origin's data.
3. Confirm whether they fill.
4. Read the `[spread]` diagnostic block (`:2268-2300`). Record the
   `[spread] from the data on %d of the first %d bars: average %.1f, ...` line (`:2296`).
5. Compare the reported bar count against the number of bars actually replayed.

**Expected (correct):** extremes are always touched; the spread statistic counts bars.

**Expected under the findings:** stops at the extreme do not fill for most `InpTicksPerBar`
values; and the spread block's denominator is inflated because the current bar is re-synthesised
on every pump.

**Proof:** the two unfilled stops (Journal shows no entry, chart shows price through the level);
the `[spread]` lines with their counts. [CONFIRMED FROM CODE] `host-expert-9` (LOW, CONFIRMED) —
the one-shot spread diagnostic is **consumed by the start-picker phase and then permanently
suppressed for the real session** (`:2260`), so with `InpPickStart=true` this block may never
appear at all. Run with `InpPickStart=false` to see it, and record that as the confirmation of
`host-expert-9`.

---

### U-30 — BAR
**Bench:** T-FX, T-FUT · **Clears:** nothing alone; feeds U-17 and U-12

1. `D` to BAR. Play 200 bars at 8x and at 60x.
2. Confirm candles advance on the primary chart, and on the secondaries from U-17.
3. Confirm the trading engine still evaluates stops — at BAR the only prices it sees are the bar's
   own, so an intrabar stop resolves at the bar, not inside it.
4. Read the fidelity readout and check whether the degradation `!` is shown when BAR was chosen by
   the engine rather than by the user.

**Expected:** BAR plays; secondaries advance (or do not — which is `chart-2`); the panel
distinguishes *user chose BAR* from *engine degraded to BAR*.

**Proof:** black box `m1` rising with `emit_ticks` flat or minimal; panel screenshot of the
fidelity readout in both cases.

**Clears/confirms:** [INFERENCE] `core-engine-11` (IMPROVEMENT, CONFIRMED) notes a degraded
FULL_TICK path among its items; this test is where the distinction becomes visible or does not.

---

## TIER 5 — MULTI-SYMBOL, REWIND, RESUME

### U-31 — Multi-symbol alignment and the settings that do not reach the extras
**Clears:** `host-expert-10` (LOW, CONFIRMED), `chart-14` (LOW, CONFIRMED)
**Bench:** T-FX primary + 2 extras

[CONFIRMED FROM CODE] `SSReplayStandalone.mq5:495` and `:511` — extra streams are configured with
the **raw inputs** (`InpSpreadPoints`, `InpChartTf`) while the primary goes through `CfgSpread()`
(`:218`) and `CfgChartTf()` (`:221`), the accessors that exist precisely so *"there is one place
that knows which of the two wins"* (`:206-213`). `CollectSettings` has the same bypass at
`:419-425`, so a saved session's settings block records the inputs rather than what ran.
`SSR_ChartManager.mqh:234` — `OpenLayout` counts each chart twice against `SSR_MAX_CHARTS`.

1. Use the setup wizard to set spread **8** and chart timeframe **M15**, with
   `InpSpreadPoints=20` and `InpChartTf=M5` as the raw inputs, and `InpAlsoSymbols` holding two
   symbols.
2. After the session builds, read each chart's timeframe from its title bar.
3. Read the spread each stream is applying (the `[spread]` block, or the panel on each).
4. Save the session and read the settings block out of the `.ssr` file.
5. Add `InpExtraTfs="M15,H1"` and count how many charts open before the cap refuses.

**Expected (correct):** all three charts on M15, all three at spread 8, the settings block records
8 and M15, and the chart cap counts each chart once.

**Expected under the findings:** the primary is M15/spread 8; the extras are M5/spread 20 — three
charts on one clock disagreeing about the execution assumption and the timeframe, with nothing in
the log saying so. The `.ssr` settings block records 20 and M5. The chart cap refuses at half the
documented count.

**Proof:** chart title bars in one screenshot; the `.ssr` settings block as text; the
`[host] opened %d extra chart(s)` line (`:1307`) against the actual window count.

**Clears/confirms:** clears `host-expert-10` and `chart-14`. Also the setup for U-17.

---

### U-31B — The user changes the chart timeframe in the middle of a run
**Decides:** nothing in `verified.json` — **this is a probe for an area no finding covers.**
**[POTENTIAL_RISK]** · **Bench:** T-FX · **Depends on:** U-05

[CONFIRMED FROM CODE] The path exists and is deliberate: the registry sweep compares `ChartPeriod(id)`
against the recorded period and, on a change, records it (`tf_changes++`), clears the scroll-detach
state that no longer describes the view (`user_detached = false`, `detach_votes = 0`,
`last_offset = ViewOffset(id)`), re-applies the follow policy when the chart was following, and calls
`OnTimeframeChanged` — all at `Chart/SSR_ChartManager.mqh:384-400`, under a comment (`:381-383`)
stating the reasoning: *"MetaTrader has already rebuilt the series from the same M1 base, so replay
state is untouched."* **No defect is filed against it and none is invented here.** Two things the
source cannot settle are why this test exists.

[CONFIRMED FROM CODE] **(a)** `OnTimeframeChanged` is declared on the observer interface
(`Chart/SSR_ChartTypes.mqh:72`) and implemented by exactly one caller in the whole tree — the T4 test
(`Tests/SSR_T4_ChartIntegration.mq5:52`). The EA host does not implement it. That is consistent with
the manager doing the catching-up itself, so it is a dormant seam, not a defect.
**[POTENTIAL_RISK] (b)** Whether the newly selected timeframe's series is *already built* at the
instant of the switch is the same lazy-build question as `qa-smoke-1` — ground truth: the first
`Bars()` read on an untouched timeframe returns 0 — and whether the three chart properties
`CSSRBlindMode::Apply` sets (`Chart/SSR_BlindMode.mqh:168-172`: `CHART_SHOW_DATE_SCALE`,
`CHART_SHOW_OHLC`, `CHART_SHOW_PRICE_SCALE`) survive a period switch is terminal behaviour nobody has
measured. `spikes-audits-6` (D2) exists to measure timeframe-switch cost and is itself defective, so
it cannot answer this either.

1. Start a run on T-FX with `InpChartTf=PERIOD_M1`, `InpBlind` set to a level that hides the scales,
   and let it play for **forty minutes of replay time** so the window is well past its warmup.
2. With the replay **running**, switch the replay chart from M1 to M15 using the terminal's own
   timeframe control.
3. Immediately read: the candle count on screen, the panel's clock and bar counters, and whether the
   chart is still following (the status strip's follow indicator).
4. Read the Experts log for anything the chart manager printed in the same second.
5. Check whether the date scale, OHLC line and price scale are still hidden.
6. Switch back to M1 and repeat steps 3–5.
7. Repeat the whole sequence at 200× rather than 1×, because at speed the follow re-anchor and the
   scroll detector interact (`chart-1`).

**Expected (correct):** the M15 series is populated from the same M1 base, the clock and bar counters
are unchanged, following continues, blind mode is still in force, and nothing in the log complains.

**Expected under the lazy-build risk:** the M15 chart is empty or short for some interval after the
switch; and/or the scales reappear because a period switch reset the chart properties.

**Proof:** screenshots immediately before and after each switch, the panel's bar counter either side,
and the log excerpt.

**Records:** [RECOMMENDATION] A finding **only** if an emptiness or a scale reappearance is actually
observed, filed against `SSR_ChartManager.mqh:384-400` or `SSR_BlindMode.mqh:168-172` respectively.
If neither happens, record "checked, no defect" against this test id — that is the correct and
complete outcome, and D's coverage statement already carries the source half of it.

---

### U-32 — Rewind, end to end
**Clears:** consolidates U-06, U-07, U-08 · **Bench:** T-FX

[RECOMMENDATION] Rewind is where four confirmed findings intersect (`trading-exec-1`,
`trading-exec-2`, `core-engine-3`, `core-engine-8`) and the single most valuable artifact this
tier can produce is **one black box recording that contains them all**, so the fixes can be
verified against one file rather than four sessions.

1. One session. Trade three times: one winner closed manually, one stopped out, one still open
   with a trailed stop.
2. Bookmark (`B`) before each.
3. `←` back over all three. Record balance, trade count, open-position stop price and the panel
   clock after each press.
4. `J` and jump forward past all three again. Record the same four.
5. `0` and Reset. Record the same four.
6. Read `RestoreSnapshot`'s effect on the settings: `core-engine-8` (LOW, CONFIRMED) says the
   checkpoint's fidelity, speed, status and last_error overwrite the live ones at
   `SSR_ReplayController.mqh:1630`. Check whether speed and fidelity changed under you.
7. Check the bookmarks: `chart-6` (LOW, CONFIRMED) — bookmark vertical lines are never deleted
   and survive on the user's own chart after the session (`SSR_ChartManager.mqh:170`). Detach and
   look at the origin chart.

**Expected:** balance reconciles at every step; stops rewind with their positions; speed and
fidelity are untouched by a rewind; no bookmark lines remain after detach.

**Proof:** one black box CSV covering the whole sequence, plus a table of the four recorded values
at each of the seven steps. The origin chart screenshot after detach for step 7.

**Clears/confirms:** confirms `core-engine-8` and `chart-6` in passing; consolidates the tier-1 and
tier-2 rewind evidence.

---

### U-33 — Resume, end to end
**Clears:** consolidates U-19, U-20 · **Adds:** `ui-port-session-11`, `ui-port-session-10`
**Bench:** T-FX

1. Save a session whose name contains a dot and the literal text `.ssr` — e.g. `eu.ssr.monday` —
   and confirm what the session list shows. `ui-port-session-11` (LOW, CONFIRMED,
   `SSR_SessionManager.mqh:142`): `List()` strips the extension by **first match**, so the name is
   listed wrong.
2. Save from the panel (not on detach) and read the settings block. `ui-port-session-10` (LOW,
   CONFIRMED, `SSR_GroupPort.mqh:949`): a save made from the panel records settings that are not
   the session's.
3. Save a session with a non-ASCII name and a non-ASCII trade tag. `ui-port-session-15` (LOW,
   POTENTIAL_RISK, `SSR_SessionFile.mqh:212`): the file is written in the terminal's ANSI codepage,
   so non-ASCII does not survive. Re-open and read the tag back.
4. Build a session with ~200 trades, save, and time the restore. `ui-port-session-13` (LOW,
   POTENTIAL_RISK, `:331`): restoring is O(entries × rows) because every packed row is fetched by
   linear scan.
5. Open the session dialog and press DELETE. `ui-dialogs-11` (LOW, CONFIRMED,
   `SSR_SessionDialog.mqh:288`): the button is enabled, looks live, and deletes nothing.

**Expected:** names round-trip; the settings block matches the run; non-ASCII survives; restore is
sub-second; DELETE deletes.

**Proof:** the session list screenshot; the `.ssr` files as text; a stopwatch on step 4 and the
`SLOW` marker if the smoke harness is used; the directory listing before and after step 5.

**Clears/confirms:** clears `ui-port-session-11`, `ui-port-session-10`, `ui-dialogs-11`; **decides**
`ui-port-session-15` and `ui-port-session-13` (both POTENTIAL_RISK — report the measured outcome,
and keep the POTENTIAL_RISK label if they do not fire on this terminal).

[CONFIRMED FROM CODE] `ui-dialogs-12` (LOW, CONFIRMED) — `RequestSave` and the whole
overwrite-confirm mode are unreachable, and would discard their own outcome message if reached
(`SSR_SessionDialog.mqh:318`). There is no runtime test for unreachable code; record it as
cleared by inspection, not by observation.

---

## TIER 6 — PROP CHALLENGE, RANDOM MODE, SEED

### U-34 — The prop challenge over a full evaluation
**Clears:** `trading-analytics-12` (MEDIUM), `trading-analytics-5` (LOW), `trading-analytics-2`
(MEDIUM) — all CONFIRMED · **Depends on:** U-20 · **Bench:** T-FX
**Configuration:** `InpProp=true`, target 8%, daily 5%, total 10%, `InpPropMinDays=3`,
`InpPropMaxDays=30`

[RECOMMENDATION] `SSR_QA_Smoke.mq5` already covers the rule *arithmetic* headlessly:
`PropCase(...)` at `:1189-1204` runs five cases — target reached after enough days, target reached
too early, daily loss ends it, overall drawdown ends it with the daily limit far away, and the
deadline ends it. **Do not re-test the arithmetic on a terminal.** This test covers only what the
smoke test cannot reach: the ordering, the day boundary, persistence, and the jump interaction.

1. Play across four replay days. Trade on days 1, 2 and 4; on day 3 place a pending order and
   **cancel it without filling**.
2. Read the trading-day count. `trading-analytics-5` (`SSR_PropEvaluation.mqh:383`): a day on which
   only a pending order was placed — even if cancelled — counts as a trading day.
3. Hit the profit target on day 4. Confirm the state.
4. In a second run, use `J` to jump forward past the point where the target would be reached.
   `trading-analytics-12` (`:358`): a jump forward never runs the evaluation, and a jump that
   completes the window leaves it IN PROGRESS.
5. In a third run, save mid-challenge and resume. `trading-analytics-2` (`:366`): prop state is not
   persisted; a resumed or reset run re-bases every rule on current equity.
6. Read the headline floor with the daily rule switched **off**. `trading-analytics-11` is
   classified **NOT_A_BUG** — do not report it as a defect.

**Expected (correct):** 3 trading days; the target evaluated at the moment it is crossed however
the clock got there; the challenge surviving a save/resume with its floors and day count.

**Expected under the findings:** 4 trading days at step 2; IN PROGRESS after the jump at step 4;
re-based floors at step 5.

**Proof:** panel Prop tab screenshots at each step with the day counter and floors visible; the
`[host] EVALUATION: <prop.ToString()>` line (`:1201`); the `.ssr` file showing no prop section.

**Clears/confirms:** clears the three listed. [INFERENCE] Section I's register is the authority on
which prop findings are which; this test covers the ones that need a clock, and nothing else.

---

### U-35 — Random mode and seed reproducibility
**Clears:** `data-3` (LOW, CONFIRMED), `tests-b-3` (LOW, CONFIRMED)
**Depends on:** U-15 · **Bench:** T-FX + 3 extras in `InpAlsoSymbols`

[CONFIRMED FROM CODE] `SSR_RandomPicker.mqh:149` — candidates are drawn **with replacement**, so a
symbol that has enough history can be skipped entirely and the picker can fail while a valid
choice existed. `SSR_T13_Strategy.mq5:539` — `T13.8` claims seed reproducibility and asserts three
tautologies instead, so the headless suite does **not** cover this.
`strategy-integration-report-4` (LOW, CONFIRMED, `SSR_StrategyHost.mqh:141`) — the per-strategy
RNG stream is seeded once at registration and never re-seeded or rewound.

1. `InpRandom=true`, `InpSeed=""`. Run 20 times with the same four-symbol pool, recording the
   `[host] random session - <ticket>` line (`:1041`) each time.
2. Tally which symbols were picked. A symbol never picked across 20 draws from a pool of four is
   `data-3`.
3. Take one ticket. Set `InpSeed` to it and run **three** times, with `InpOneChart=false` so
   U-15's handover defect is out of the way.
4. For each of the three, record: origin symbol, window start, window end, and — with
   `InpRefStrategy=true` — the strategy's trade list from `[host] <strategies.Report>` (`:2165`).
5. Diff the three journals.

**Expected (correct):** three byte-identical windows and three identical trade lists.

**Expected under the findings:** the windows match (the seed does decide the window) but the trade
lists do not, because the strategy RNG and the tick layer are outside the seed —
[INFERENCE] which is exactly what section J.2.2 and J.2.3 describe as the five environment terms
and the tick layer the seed does not capture.

**Proof:** the 20 `random session` ticket lines; three black box preambles showing
`# origin`, `# window`, `# picked_start`; three journal CSVs diffed.

**Clears/confirms:** clears `data-3` and `tests-b-3`. [RECOMMENDATION] Re-run step 3 with
`InpOneChart=true` **after** `host-expert-5` is fixed, as the regression test for that fix. Before
the fix it will produce three different windows and prove nothing about the seed.

---

## TIER 7 — THE UI: PERSIAN, BOTH LAYOUTS, ALL THREE PALETTES, THE INSTRUMENT

### U-36 — Persian, end to end
**Clears:** `ui-plumbing-13` (LOW, POTENTIAL_RISK), `ui-plumbing-1`, `ui-panel-14`,
`ui-dialogs-4`, `chart-12` (all CONFIRMED) · **Bench:** T-FX, Windows with Persian fonts installed

[CONFIRMED FROM CODE] The catalogue is 190/190 with `fa.txt` present at
`MQL5\Files\SSReplay\lang\fa.txt`, read as **bytes decoded CP_UTF8 with BOM handling**
(`SSR_Strings.mqh:664-685`) — not `FILE_TXT|FILE_ANSI`, which is the bug that produced mojibake in
v117 and *hid for a whole build because the QA log is written with the same encoding*
(`:645-655`). [INFERENCE] That last sentence is the single most important warning in this whole
section: **a screenshot of the QA log is not evidence about Persian rendering.** Only the chart is.

1. Run `SSR_QA_FontProbe` first, with the Persian faces added to `InpFonts` (Tahoma is the usual
   Windows Persian fallback). Record which candidates are genuinely installed versus silently
   substituted — the script detects this by fingerprinting a deliberately impossible face name
   (`:20-24`) and reporting metric matches, and it says outright what it *cannot* prove.
2. Attach with `InpLanguage="fa"`. Read the `[i18n]` line at `:719`:
   `[i18n] fa: <n> of 190 strings translated`. Confirm `n == 190` and no unknown-key note.
3. **Screenshot the panel.** Every tab, every sheet, the caption chips, the status ladder.
4. Screenshot the setup wizard, all steps.
5. Arm the trade lines (`R`) and screenshot the chart. `chart-12` (CONFIRMED): every word the chart
   layer draws — `"STOP - drag me"`, `"TARGET - drag me"`, `"ENTRY - drag me"`, `BUY`/`SELL`/`SL`/`TP`
   and the closed-trade captions — is an English literal outside the catalogue.
6. Take a trade and screenshot the fill toast. `SSR_Panel.mqh:795, 799` draw `"   spread %.1f pt"`
   and `"   NO STOP"` as literals, while translated equivalents `SSR_S_SPREAD_SHORT` and
   `SSR_S_NO_STOP` exist and are used on the Positions row 700 lines away.
7. Open the key card. `ui-plumbing-1` (CONFIRMED): 36 cells of `SSR_Keys.mqh:131-218` literals,
   drawn at `SSR_KeyCard.mqh:92`, all English.
8. Press `0` and screenshot the reset confirmation. `ui-panel-14` (CONFIRMED,
   `SSR_Panel.mqh:2253`): English literal on the highest line of the status ladder.
9. Open the review card. `ui-dialogs-4` (CONFIRMED, `SSR_Review.mqh:205`): two observation
   sentences exceed the 63-character draw limit **for every possible value**, so they are cut on
   screen in every language.
10. Check the palette footer and the setup summary for `Â·`. `ui-plumbing-13` (POTENTIAL_RISK): six
    raw U+00B7 characters in `SSR_Strings.mqh:472, 474, 544` in a file with no BOM — if MetaEditor
    decoded it as system ANSI, they draw as `Â·` and the compile succeeded anyway.

**Expected:** `190 of 190`; Persian glyphs render (not boxes, not `?`); no `Â·`; the English
surfaces at steps 5–8 are visibly English and are recorded as such.

**Proof:** the `[i18n]` line; the font probe report; and the screenshot set. [RECOMMENDATION] Name
the screenshots after the surface, not the step, and keep them — they are the only baseline that
will exist for the next translation.

**Clears/confirms:** clears the four CONFIRMED i18n escapes by demonstrating them on screen, and
**decides** `ui-plumbing-13`.

[CONFIRMED FROM CODE] RTL cannot be tested because it is not implemented: `SSR_Layout.mqh` exists
to enable a mirrored coordinate system and **no production file calls any of its functions**
(`ui-plumbing-5`, IMPROVEMENT, CONFIRMED, `:67`); `SSRCentre` and `SSRInner` have zero call sites
anywhere. Flipping `SSRFrame.rtl` changes nothing on screen. Do not write an RTL test; write the
finding down and move on.

---

### U-36B — The ten keys MetaTrader also owns
**Decides:** nothing in `verified.json` — **this is a probe for an area no finding covers.**
**[POTENTIAL_RISK]** · **Bench:** T-FX · **Depends on:** V's optional `InpLogEvents` edit

[CONFIRMED FROM CODE] The product binds 22 distinct virtual-key codes (`Ui/SSR_Keys.mqh:46-75`) and
**ten of them are keys MetaTrader itself binds on a chart**: `SSR_VK_LEFT` 37, `SSR_VK_RIGHT` 39,
`SSR_VK_UP` 38, `SSR_VK_DOWN` 40 (scroll), `SSR_VK_PGUP` 33, `SSR_VK_PGDN` 34 (page),
`SSR_VK_PLUS` 187 / `SSR_VK_NUMPLUS` 107 and `SSR_VK_MINUS` 189 / `SSR_VK_NUMMIN` 109 (zoom). They
reach the product only through `CHARTEVENT_KEYDOWN` on the chart the EA is attached to
(`SSReplayStandalone.mq5:3217`, `:3232`), which is also where the panel is created
(`g_panel_chart = ChartID()`, `:1463`); the host distinguishes the case where that chart is also the
replay chart from the case where it is not (`:1669`). **[INFERENCE] Nothing in the tree says whether
the terminal acts on those ten keys in addition to delivering them**, and `ui-plumbing-2`, `-3`,
`-14` and `-15` cover only the conflict *internal* to the product (documentation of the key table,
whose 22 `vk` values are all distinct — O.md's own audit). This is therefore a probe, and **no
finding may be filed from it without running it**.

1. Enable the `InpLogEvents` probe from section V (log `lparam` on `CHARTEVENT_KEYDOWN`).
2. With the EA's chart focused, press each of the ten keys once, slowly, with the replay **paused**.
3. For each key record three things: (a) whether the probe logged it, (b) what the product did, and
   (c) **whether the chart also scrolled, paged or zoomed**.
4. Repeat with the replay running at 1× and at 200×, because the follow policy re-anchors the view
   (`Chart/SSR_ChartManager.mqh:452` region) and a terminal-side scroll is exactly what `chart-1`
   mistakes for a user drag — so a terminal that *also* acts on the arrows makes `chart-1` reachable
   by a keypress rather than only by speed.
5. Repeat once more with a **separate** replay chart focused instead of the EA's chart, and record
   whether any panel key works at all from there.

**Expected (no conflict):** the probe logs each key, the product acts, and the chart does not move.

**Expected under a conflict:** the chart scrolls or zooms as well as the product acting — in which
case every arrow press is also a scroll-detect input; or nothing reaches the product from the replay
chart, in which case the documented key bindings are unreachable in the two-window bench.

**Proof:** the probe log, and a before/after screenshot of the chart's first visible bar index for
each of the ten keys.

**Records:** a new finding, if and only if the chart moved. **[RECOMMENDATION]** File it against the
key table with the observed key list, and cross-reference `chart-1`: a terminal-side scroll on an
arrow key is a second mechanism for the same false detach.

---

### U-37 — Both layouts
**Clears:** completes `ui-panel-7` (MEDIUM, CONFIRMED) · **Bench:** any

[CONFIRMED FROM CODE] `SSR_Theme.mqh:484-486` — `SSR_LAYOUT_RAIL` is design 08, a 310 px panel
with the four tabs on a rail; commenting it out selects the 420 px fallback.
`SSR_Panel.mqh:1576` — the position-row note column collides with the P/L column **in the rail
layout**: 9 px of room for a 9-character note.

1. Build with `SSR_LAYOUT_RAIL` defined (shipped). Screenshot every sheet, with position rows
   populated and a long note on at least one.
2. Read `PaintWrites()` on a still frame (the smoke test's stage 42 does this,
   `Step("42 the paint budget")`, `:5012`).
3. Read `FrameOverflowRight()` and `FrameOverflowBottom()`.
4. Comment out `SSR_LAYOUT_RAIL`, rebuild, repeat 1–3.
5. Diff the two screenshot sets.

**Expected:** neither layout draws outside its frame; the note column is legible in both.

**Expected under `ui-panel-7`:** in the rail layout the note and the P/L overlap.

**Proof:** the two screenshot sets; the two overflow figures; the two paint-write counts.

**Clears/confirms:** clears `ui-panel-7`. [RECOMMENDATION] The 420 layout is a fallback nobody has
run either; treat a defect found only there as a real finding, not as dead code.

---

### U-38 — All three palettes
**Clears:** `ui-plumbing-9` (IMPROVEMENT, CONFIRMED) · **Confirms:** `ui-plumbing-10` is NOT_A_BUG
**Bench:** any

[CONFIRMED FROM CODE] `SSR_Theme.mqh:75-77` — `SSR_THEME_RAIL` is active, `SSR_THEME_LIGHT` and
`SSR_THEME_DARK` are commented out. `ui-plumbing-9` (`SSR_Widgets.mqh:492`) — `SSR_C_THUMB_EDGE`
and `SSR_C_TICK` are declared in all three palettes and drawn by nothing.

1. Build and screenshot the full panel under each of the three defines, on a light chart background
   and a dark one — six screenshots per sheet.
2. For each, check contrast on: the primary action button, an engaged toggle, a disabled control,
   the status ladder's highest line, and the speed groove's twenty cells.
3. Confirm `SSR_C_THUMB_EDGE` and `SSR_C_TICK` appear nowhere on screen in any palette.
4. Press `Ctrl+K` to open the palette. `ui-plumbing-15` (LOW, CONFIRMED, `SSR_Keys.mqh:71`): the
   palette's only live entry point is not in the key table, so the generated key card cannot show
   it. Confirm it opens, and confirm the key card does not mention it.

**Expected:** all three palettes legible on both chart backgrounds; the two dead colours absent;
`Ctrl+K` works and is undocumented in-product.

**Proof:** the screenshot matrix; the key card screenshot next to a working `Ctrl+K`.

**Clears/confirms:** clears `ui-plumbing-9` and `ui-plumbing-15`. **`ui-plumbing-10` is classified
NOT_A_BUG** — the claim that the primary action and an engaged toggle share a colour in the RAIL
palette was refuted, and it must not be reported as a defect on the strength of a screenshot that
looks like it.

---

### U-39 — The layout-overflow instrument: does it fire, and what can it not see
**Clears:** nothing alone · **Confirms:** the instrument's stated blind spot
**Bench:** any · **Depends on:** U-21, U-37

[CONFIRMED FROM CODE] `CSSRPanel::CheckFrame` (`SSR_Panel.mqh:3019-3034`) compares
`m_w.MaxRight()`/`MaxBottom()` against the frame and prints, **once per offence and not once per
frame**, `[panel] LAYOUT OVERFLOW: something is drawn N px past the right edge and M px past the
bottom. The frame is WxH. This is a layout bug, not a chart size problem.` The figures are kept for
the status strip and the flight recorder (`FrameOverflowRight()`, `:3037`). `CSSRWidgets::Extent`
(`SSR_Widgets.mqh:129-133`) covers **sized objects only** — *"A label's width depends on the glyphs
the font chose and MQL5 will not say, so guessing at it here would produce a warning nobody could
act on"* (`:125-128`).

1. Force a real overflow of a **sized** object: shrink the chart width below the panel width, or
   temporarily widen one `Rect` by 40 px in a scratch build.
2. Confirm exactly one `[panel] LAYOUT OVERFLOW` line appears, with the correct pixel figures and
   the correct frame size — not one per frame.
3. Confirm a second, larger overflow raises the figures and prints again; a smaller one does not.
4. Confirm `FrameOverflowRight()` matches.
5. Now run the `ui-panel-6` case from U-21 (the fidelity **label** at `x+330` in a 310 px frame).
   Confirm the instrument prints **nothing**.

**Expected:** steps 1–4 pass; step 5 prints nothing, and that silence is correct behaviour for an
instrument that measures sized objects only.

**Proof:** the Experts tab — one line, then a second on a worse offence, then silence during
step 5. Screenshot from U-21 showing the text on the candles while the log is silent.

**Clears/confirms:** [RECOMMENDATION] This is the test that turns `ui-panel-6` from *a label is in
the wrong place* into *the instrument cannot see labels at all*, which is the finding worth acting
on. A label-extent estimate — even a crude `chars × size × 0.6` — would have caught it, and
`SSR_QA_FontProbe` already measures real string widths with `TextGetSize`, so the measurement this
needs exists in the tree and is not wired to the panel.

---

### U-40 — The chart-handover guard, standing alone
**Clears:** consolidates U-05, U-22, U-13 · **Bench:** T-FX, T-IDX

[RECOMMENDATION] The handover is the single riskiest sequence in the product — it destroys and
rebuilds the user's chart — and four confirmed findings live inside it (`host-expert-1` CRITICAL,
`host-expert-3`, `host-expert-5`, `host-expert-6` MEDIUM). After the fixes land, run the whole
sequence as one matrix rather than four separate tests.

| Case | `InpOneChart` | Other | Must end with |
|---|---|---|---|
| A | true | defaults, picker used | pass 2 builds, `origin=<real>`, auto-play running |
| B | true | `InpPickStart=false`, `InpStart` set | pass 2 builds, **inputs win over any `setup.ini`** |
| C | true | `InpRandom=true`, seed noted | pass 2 announces the **same** ticket and window |
| D | true | replay symbol forced to fail the guard | chart untouched, reason named, separate window opened |
| E | true | T-IDX, leftover replay symbol present | adopted, chart mode BID, candles build |
| F | false | defaults | two windows, no handover, no stash written |
| G | true | second pass fails deliberately | `!` poison prefix read, `[host] one-window mode is OFF for this run: ...` (`:1899`), two windows |

1. Run each case from a fresh terminal with a clean Market Watch.
2. For every case, capture: both `[host] SS Replay build ... pass=...` lines, the black box CSV(s),
   and a screenshot of the final chart state.
3. For case G, confirm the poison prefix mechanism works: pass 1 writes `!`-prefixed stash, the
   next `OnInit` reads it once, clears it, and refuses one-window mode for that run (`:1893-1902`).

**Expected:** all seven end in a state the user can work in or recover from. **None** ends with the
user on a replay chart with no expert and no way back.

**Proof:** the matrix, filled in, with a log line and a CSV per row.

**Clears/confirms:** the regression gate for the entire one-window feature. [RECOMMENDATION] Nothing
should ship on `InpOneChart=true` until this matrix is green, because it is the default.

---

### U.9 The evidence pack

[RECOMMENDATION] Every run in this plan produces the same bundle, and the bundle is what gets sent
back — not a sentence about it:

1. **The Experts tab, in full**, saved as text. Not a screenshot of it: the `[i18n]` mojibake
   lesson (`SSR_Strings.mqh:645-655`) is that a log read in the same encoding it was written in
   can agree with itself and be wrong.
2. **The black box CSV(s)** from `MQL5\Files\` — one per EA attach, so a handover run has two.
3. **`MQL5\Files\SSReplay\qa-result.txt`** when the smoke test was part of the run.
4. **The `.ssr` session file** when the run saved one.
5. **The journal CSV and the statement** when the run traded.
6. **Screenshots** only for the visual claims, named after the surface.
7. **A filled-in header**: terminal build, broker, symbol, digits, tick_size, DPI, the six inputs
   that differ from defaults, and the git revision built.

[RECOMMENDATION] Run `tools/ssr_flight.py` on every CSV before sending it and paste its verdict at
the top. The tool's own doctrine applies: *"Verdicts are ordered. The first stuck layer is the only
one worth acting on; everything below it is a consequence, and fixing a consequence is how this
project has repeatedly broken something else."*

---

### U.10 Coverage: which test decides which finding

[CONFIRMED FROM CODE] Ids, classifications and severities are the `id`, `classification` and
**`final_severity`** fields of `docs/audit/verified.json`. Six rows deliberately clear **no** finding
and say so with a dash: U-04 establishes the bench, U-24 goes looking for a gap, U-39 proves the
layout instrument's blind spot, U-40 is the regression gate, and **U-31B** and **U-36B** are probes
for two areas that `verified.json` covers with **no finding at all** (see U.11).
Key: `C` = CONFIRMED, `PR` = POTENTIAL_RISK, `MED`/`IMPR` = MEDIUM/IMPROVEMENT.

| Test | Findings it clears | Class |
|---|---|---|
| U-01 | `qa-smoke-2` | MED C |
| U-02 | `qa-smoke-3` | MED PR |
| U-03 | `qa-smoke-1` | MED C |
| U-04 | — (establishes the bench) | — |
| **U-05** | **`host-expert-1`** | **CRIT C** |
| **U-06** | **`trading-exec-1`** | **CRIT C** |
| U-07 | `trading-exec-2` | HIGH C |
| U-08 | `core-engine-3` | HIGH C |
| U-09 | `core-engine-2` | HIGH C |
| U-10 | `data-1`, `core-engine-4` | HIGH C ×2 |
| U-11 | `core-engine-1` | HIGH C |
| U-12 | `core-sync-1` | HIGH C |
| U-13 | `host-expert-3` | MED C |
| U-14 | `host-expert-6` | MED C |
| U-15 | `host-expert-5` | MED C |
| U-16 | `mt5-symbol-1` | HIGH C |
| U-17 | `chart-2`; observes `chart-1` | MED C; MED PR |
| U-18 | `ui-port-session-2` | MED C |
| **U-18B** | **`ui-dialogs-1`** | **HIGH C** |
| U-19 | `ui-port-session-3`; observes `ui-port-session-8` | HIGH C; MED C |
| U-20 | `trading-analytics-1`; observes `trading-analytics-2` | HIGH C; MED C |
| U-21 | `ui-panel-6`, `ui-panel-3`, `ui-panel-13` | MED C, HIGH C, LOW C |
| U-22 | `mt5-symbol-3` | MED C |
| U-23 | `mt5-symbol-2`, `spikes-audits-3` | MED PR, MED C |
| U-24 | — (gap-finding on contract size) | — |
| U-25 | `data-4`, `core-engine-6` | MED C ×2 |
| U-26 | decides `data-2`; observes `data-7` | HIGH PR; LOW C |
| U-27 | `host-expert-11` (by fix, not observation) | LOW C |
| U-28 | observes `strategy-integration-report-1` | HIGH C |
| U-29 | `spikes-audits-1`, `core-sync-2`, `host-expert-9` | HIGH C, MED C, LOW C |
| U-30 | observes `core-engine-11` | IMPR C |
| U-31 | `host-expert-10`, `chart-14` | LOW C ×2 |
| U-31B | — (probe: mid-run timeframe switch; **no finding covers this area**) | — |
| U-32 | `core-engine-8`, `chart-6` | LOW C ×2 |
| U-33 | `ui-port-session-11`, `ui-port-session-10`, `ui-dialogs-11`; decides `ui-port-session-15`, `ui-port-session-13` | LOW C ×3; LOW PR ×2 |
| U-34 | `trading-analytics-12`, `trading-analytics-5`, `trading-analytics-2` | MED C, LOW C, MED C |
| U-35 | `data-3`, `tests-b-3` | LOW C ×2 |
| U-36 | `ui-plumbing-1`, `ui-panel-14`, `ui-dialogs-4`, `chart-12`; decides `ui-plumbing-13` | LOW C ×3, MED C; LOW PR |
| U-36B | — (probe: the ten keys MetaTrader also binds; **no finding covers this area**) | — |
| U-37 | `ui-panel-7` | MED C |
| U-38 | `ui-plumbing-9`, `ui-plumbing-15` | IMPR C, LOW C |
| U-39 | — (proves the instrument's blind spot) | — |
| U-40 | regression gate for U-05/13/14/15/22 | — |

**[CONFIRMED FROM CODE] Severity convention.** Every class cell above is the **`final_severity`**
and **`classification`** field of `docs/audit/verified.json` — the verdict after the three refuters
and two confirmers — not the `severity` field the subsystem reader filed. The two disagree for 105
of the 248 findings. Nowhere in this section, or in any other, is the filed severity quoted.

[CONFIRMED FROM CODE] **Coverage against the confirmed top tier: 2 of 2 CRITICAL and 14 of 14
CONFIRMED HIGH.** The fourteen are `core-sync-1` (U-12), `core-engine-1` (U-11), `-2` (U-09), `-3`
(U-08), `-4` (U-10), `data-1` (U-10), `mt5-symbol-1` (U-16), `ui-port-session-3` (U-19),
`spikes-audits-1` (U-29), `strategy-integration-report-1` (U-28), `trading-analytics-1` (U-20),
`trading-exec-2` (U-07), `ui-panel-3` (U-21) and `ui-dialogs-1` (U-18B). `ui-dialogs-1` had no test
in the first draft of this plan; U-18B exists because of that gap, and its assertion is the one
T.6.3 item 0C.11 already specifies. The one HIGH **POTENTIAL_RISK**, `data-2`, is decided by U-26.

[CONFIRMED FROM CODE] **What is deliberately not on the list, and why.** The test- and spike-layer
findings — `tests-a-1`, `-2`, `-3`, `tests-b-1`, `-2` (all **MEDIUM**, CONFIRMED),
`spikes-audits-2`, `-4`, `-7`, `-8`, `-10`, `-12` (all **MEDIUM**, CONFIRMED) and
`spikes-audits-14` (**LOW**, CONFIRMED) — are not HIGH and are not scheduled here, for a reason
that is about their kind rather than their rank: every one of them is an assertion that is false,
tautological, or unreachable **in code**, and they are cleared by reading and fixing the assertion,
not by running it. Running a test whose assertion cannot fail produces a PASS and teaches nothing.
Fix those in the editor and record them as cleared by inspection. [INFERENCE] The three
instruments in U.0.1 are the exception: their defects change what a terminal run *reports*, so they
are repaired first and then run (U-01, U-02, U-03).

---

### U.11 What this plan cannot prove

[INFERENCE] Stated plainly, because a test plan that implies more coverage than it has is the same
class of instrument failure as a spike that prints its criterion instead of asserting it
(`spikes-audits-12`, `spikes-audits-13`, both CONFIRMED):

- **It cannot prove the absence of a defect on brokers it did not touch.** Tick depth, session
  declarations, M1 completeness and symbol specs are broker facts. A GO on two brokers is two data
  points.
- **It cannot exercise `host-expert-11`.** The `GetTickCount` wrap is 49.7 days after boot. Fix it
  to `GetTickCount64()` and record it as fixed-not-tested.
- **It cannot test RTL**, because RTL does not exist (`ui-plumbing-5`, CONFIRMED).
- **It cannot decide the budget-cap findings on fast hardware.** `core-engine-1` needs the budget
  to bite; if it never bites, the correct report is *not exercised*, never *passed*.
- **It cannot see label overflow**, by construction (U-39). Any test that says the panel is inside
  its frame is saying that its *sized objects* are.
- **It proves nothing about MQL5 behaviours the code assumes and no spike measured honestly.**
  `spikes-audits-2` (B1's verdict fails deterministically), `spikes-audits-7` (D2's live pass
  re-sends identical timestamps so 69 of 70 injections are refused), `spikes-audits-8` (D4 skips
  the series rebuild on 16 of 20 trials), `spikes-audits-14` (C3 runs writer and reader
  sequentially in one thread so "race-free" cannot fail) — all CONFIRMED. **Those spikes must be
  repaired before their subjects can be claimed as measured**, and until they are, every
  performance and transport number in the project's own documentation carries their error.
- **Two of its tests are not clearing a finding at all, and that is deliberate.** [CONFIRMED FROM
  CODE] **U-31B** (a mid-run chart-timeframe change) and **U-36B** (the ten key codes MetaTrader
  itself binds) cover areas for which `verified.json` holds **no finding** — not because the areas
  are clean, but because source cannot settle them. D's coverage statement carries the source half
  of each and files nothing. If either probe observes the failure it is looking for, **that is a new
  finding and must be recorded as one**, not attributed to an existing id. If neither does, "checked,
  no defect found" is the correct and complete outcome.
- **It cannot substitute for the author running this.** [RECOMMENDATION] The highest-value single
  action available is not any test on this list: it is one hour with a real terminal, the defaults,
  and the black box on — because `host-expert-1` is CRITICAL, fires on the shipped configuration,
  and would announce itself in the first ninety seconds.

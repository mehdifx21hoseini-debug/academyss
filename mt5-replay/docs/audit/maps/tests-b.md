# Subsystem map: tests-b  (T9 - T15 test scripts)

Build v125. Files mapped (all under
`/home/user/academyss/mt5-replay/MQL5/Scripts/SSReplay/Tests/`):

| File | Lines | Sections | Assertion calls* | Phase name |
|---|---:|---:|---:|---|
| `SSR_T9_Trading.mq5`         | 442 | 8  | ~59  | Virtual Trading Engine |
| `SSR_T10_Statistics.mq5`     | 717 | 12 | ~129 | Trade & Statistics Engine |
| `SSR_T11_AdvancedReplay.mq5` | 634 | 10 | ~130 | Advanced Replay |
| `SSR_T12_Session.mq5`        | 662 | 8  | ~137 | Session System |
| `SSR_T13_Strategy.mq5`       | 548 | 8  | ~85  | SS Strategy Layer |
| `SSR_T14_Integration.mq5`    | 402 | 8  | ~95  | SSProX Integration Layer |
| `SSR_T15_Ux.mq5`             | 512 | 10 | ~75  | Professional UX |

\* counted as call sites of `Check/CheckEq/CheckNear/CheckStr/CheckExact`
minus the calls the helpers make internally.

---

## 1. Shape common to all seven files

There is no test framework and no shared header. **Every file re-declares
the same harness by copy**, which is a deliberate property of the design
(a test script must compile alone), and the single largest duplication in
the subsystem.

Per-file harness (identical bodies, per-file set):

```
#property script_show_inputs
int g_pass = 0, g_fail = 0;
void Check    (const string n, const bool ok, const string d = "")
void CheckEq  (const string n, const long e,   const long a)          // ==
void CheckNear(const string n, const double e, const double a, const double tol)
void CheckStr (const string n, const string e, const string a)        // T12, T15 only
void CheckExact(const string n, const double e, const double a)        // T12 only
void Section  (const string t)                                        // prints "--- <t>"
```

* `Check` PrintFormats `  PASS  <name>` or `  FAIL  <name>  <detail>` and
  increments `g_pass`/`g_fail`. **Nothing aborts on failure**; a section
  keeps running after a failed precondition.
* Entry point is always `void OnStart()`; the last line of every file is
  `PrintFormat("=== Phase N: PASS=%d FAIL=%d ===> %s", ..., g_fail==0 ? "GREEN" : "RED")`.
* Verdict is **stdout only**. No exit code, no file, no global variable, so
  nothing outside the terminal Experts log can consume a result. There is no
  runner that executes T1..T15 in sequence; `tools/ssr_compile.sh` only
  compiles every `.mq5` (all 39 programs, tests included), so a green
  compile says nothing about assertions.
* Inputs are `input` variables (`InpStart`, `InpBars`, `InpBase`,
  `InpWarmup`, plus `InpSlot` in T14). They are declared `script_show_inputs`,
  so a run can be reparameterised, but every expectation in the files is
  written against the **defaults** (e.g. T10's hand-computed profit factor,
  T13's `bar_calls >= 8 && <= 16`). Changing an input silently invalidates
  the assertions rather than skipping them.

### Fixture builders (per file, near-identical, not shared)

| Helper | Files | What it makes |
|---|---|---|
| `BuildBars(out[], start, count, base, range)` | T9, T11, T12 | flat market: `open=close=base`, `high=base+range`, `low=base-range`, `spread=2`, `tick_volume=10`, one bar per 60 s |
| `BuildBars(out[], start, count, base)`        | T14, T15 | same with `range` fixed at 5.0 and `spread=0` |
| `BuildRamp(out[], start, count, base)`        | T13 | `p = base + i`; `open=close=p`, `high=p+0.5`, `low=p-0.5` - every aggregation has a stateable answer |
| `Wire(ctrl, src, sink, ...)`                  | T11, T12, T15 | loads bars into `CSSRMemoryDataSource`, `k.Clear()`, `SetSymbolSpec(2,0.01)`, `SetTicksPerBar(8)`, `SetSpreadPoints(0)`, `SetWarmupBars(InpWarmup)`, `SetFidelity(SYNTHETIC_TICK)`, `Attach`, then `Load(name, g_start, g_end)` |
| `Begin(a, s, balance)` / `Tick(...)` / `BarCtx(...)` / `Breakeven(a)` | T10 only | drives the observers **directly**, with no controller and a hand-advanced `g_msc` clock |

Two different `Wire` conventions exist and they are not interchangeable:
T11's `Wire` builds bars starting at `start_msc - InpWarmup` minutes and
takes the window as arguments; T12's and T15's build from `InpStart` and
close over the file-scope `g_start`/`g_end`.

### State owned at file scope
`g_pass`, `g_fail` (every file); `g_start`, `g_end` (T11-T15); `g_msc`
(T10 only - the hand-advanced replay clock the `Tick()` helper bumps).

---

## 2. What each file touches outside itself

### Classes under test (by file)

* **T9** - `CSSRRiskEngine` (directly), `CSSRTradingEngine`,
  `CSSRReplayController` + `CSSRMemoryDataSource` + `CSSRRecordingSink`,
  `SSRVirtualPosition`, `SSRExecutionModel`, `CSSRSnapshotStore` (read only,
  via `ctrl.Snapshots()`).
* **T10** - `CSSRTradingEngine`, `CSSRStatsEngine`, `SSRStatistics`,
  `CSSRJournal`. **No controller**: ticks and bar context are injected by hand.
* **T11** - `SSRRandom`, `SSRSeedText/SSRSeedFromText`, `CSSRReplayGroup`
  (`SSR_MasterClock.mqh`), `CSSRTradeAutoPause`, `CSSRSessionWatcher`,
  `SSRBlindPolicy` + `CSSRBlindMode`, `SSRReplayClock`, `SSRAnonSymbolName`
  /`SSRIsReplaySymbol`/`SSRIsNameUsable`/`SSRReplaySymbolNameFor`.
* **T12** - `CSSRSessionFile` (+`SSRPack/SSRUnpack/SSRField/SSRFieldLong`),
  `SSRFingerprint` (+`SSRFingerprintBars/Pack/Unpack`),
  `CSSRTradingEngine.SaveInto/RestoreFrom`, `CSSRStatsEngine.SaveInto/RestoreFrom`,
  `CSSRSessionManager`, `SSRSessionSettings`, `CSSRReplayGroup`,
  `CSSRTradeAutoPause`.
* **T13** - `CSSRMarketView`, `CSSRStrategyHost`, `CSSRStrategyBroker`,
  `CSSRRefBreakout`, plus a local probe class `CSSRCheater : CSSRStrategy`.
* **T14** - `SSR_Contract.mqh` wire constants, `SSRGvName`, `SSRSymbolHash`,
  `SSRPublicState`, `CSSRPublisher`, `CSSRClient`.
* **T15** - `CSSRGroupPort` + `SSRUiState`, `CSSRPanel`, `SSR_Keys.mqh`
  (`SSRKeyToCommand`, `SSRKeyHint`), `CSSRBlindMode`, `CSSRSessionManager`,
  `CSSRStrategyHost`/`CSSRRefBreakout`.

### Side effects on disk, chart and terminal

| File | Writes | Cleaned up? |
|---|---|---|
| T9  | nothing | - |
| T10 | `MQL5\Files\SSReplay\journal\t10.csv` (`j.ExportCsv("t10", 2)`, line 533); `FolderCreate(SSR_JOURNAL_DIR)` | **no** - left beside the trader's real journals |
| T11 | nothing (`b.Apply(0)` and the off-policy `Apply(12345)` are both refused, so no chart property is written) | - |
| T12 | `SSReplay\test_fmt.ssr`, `test_future.ssr`, `test_junk.ssr`, `test_acct.ssr`, `test_bad.ssr`, `test_eq.ssr`; sessions `t12`, `t12b`, `t12c` | yes - `FileDelete`/`mgr.Delete` for each |
| T13 | nothing | - |
| T14 | terminal **global variables** `SSR.7.*` (all 23 contract fields), incl. hand-written `SSR.7.perm`, `SSR.7.v`, `SSR.7.hb` | yes - `pub.Withdraw()` (deletes all 23) + explicit `GlobalVariableDel` in T14.7 |
| T15 | chart objects `T15_kbd_*`, `T15_move_*`, `T15_own_*` on `ChartID()`; `CHART_EVENT_MOUSE_MOVE`/`CHART_MOUSE_SCROLL`/`CHART_QUICK_NAVIGATION`/`CHART_KEYBOARD_CONTROL` on that chart; **`MQL5\Files\SSReplay\panel.ini`** via `SetCorner`->`SavePlace`; session `t15` | objects/properties yes (`panel.Destroy()`); session yes (`mgr.Delete("t15")`); **`panel.ini` no** |

T14 is the only file that can collide with a *running* product: it uses
`InpSlot = 7` ("a slot no real session would use") and wipes that slot
before asserting. T15 is the only file that draws on a real chart, and it
does so on whatever chart the script is dropped on.

---

## 3. Section-by-section inventory

### T9 - Virtual Trading Engine (`SSR_T9_Trading.mq5`)
Shared wiring for T9.2-T9.3 lives at function scope (`src`, `sink`, `ctrl`,
`acct`); T9.4-T9.8 each build their own quadruple.

| Section | Claim | What is actually asserted |
|---|---|---|
| T9.1 (61) | position sizing rounds DOWN, refuses what it cannot size | `LotForRisk` = 10.0 exactly; `RiskOf`/`RiskPercentOf`; `lot <= 14.28` and `RiskOf(lot,7) <= 100` (one-sided, see finding); refusal returns 0.0 with a non-empty `LastReason()`; stop-at-entry returns 0.0 |
| T9.2 (99) | the engine trades on the replay stream | `AddObserver` true, `ObserverCount()==1`, `Load` true, `Balance()==10000` (vacuous), `Bid() > 0` after 120 pumps |
| T9.3 (136) | open / modify / break-even / close | ticket > 0, `OpenCount`, `ByTicket`, `IsLong`, `sl` stored then moved, `sl == open_price` after `BreakEven`, `ClosedCount==1`, `reason == SSR_CLOSE_MANUAL`, `!ambiguous` |
| T9.4 (165) | a bar holding stop AND target resolves against the trader and is flagged | `reason == SSR_CLOSE_SL`, `p.ambiguous`, `AmbiguousCount() >= 1`, `AmbiguousPercent() > 0` |
| T9.5 (217) | an unambiguous stop is not flagged | `reason == SSR_CLOSE_SL`, `!ambiguous`, `AmbiguousCount()==0` |
| T9.6 (256) | pendings, partials, trailing | pending counted then filled; `ClosePartial` leaves one open position at half volume and adds no closed trade; trailing sets a stop that never decreases; `CloseAll() > 0` |
| T9.7 (319) | a rewind un-happens trades, including through the checkpoint path | ticket gone after `StepBackward`, `OpenCount` restored, `Snapshots().Count() > 0`, second trade gone after a second `StepBackward` |
| T9.8 (387) | execution costs are charged, never in the user's favour | commission on entry (`bal0-7`), fill `>= Ask()`, `commission == 14` after exit, `Balance() < bal1 + 1e-9` (weak) |

Invariants T9 relies on: `SSR_MSC_PER_MIN` arithmetic for `StepBackward`
counts; a flat +/-5 market so a stop 3 away is reached inside *every* bar;
`SetSpreadPoints(0)` for exact price assertions (T9.8 uses 20);
`SSR_FIDELITY_SYNTHETIC_TICK` so intrabar ambiguity exists at all.

### T10 - Statistics (`SSR_T10_Statistics.mq5`)
Drives `CSSRTradingEngine` + `CSSRStatsEngine` with no controller:
`Begin()` calls `OnSessionStart` on both, then re-`Configure`s the risk
engine **after** it (1 price unit = 1 money unit per lot), which is the
correct order (T9 does not do this).

Sections: T10.1 empty account (+`Caveat()` says "no closed trades");
T10.2 four hand-computed trades - counts, gross/net, win/loss rate, PF 3.5,
expectancy 62.5, averages, largest, streaks, `r_trades==3`,
`trades_without_stop==1`, `total_r == 3+1-100/150`, MAE/MFE averages,
`max_drawdown_closed==100` vs `max_drawdown==130`, `max_drawdown_pct`,
balance 10250; T10.3 ambiguity counted + `ambiguous_pct` + `IsTrustworthy`
crossing 10% (25% -> false, 5% -> true); T10.3b real ticks are never
ambiguous (`SSR_CLOSE_TP` honoured); T10.4 R is undefined not zero, PF with
no losses is 0.0; T10.5 swap once per replay day, idempotent, not re-paid on
close; T10.5b rewind refunds swap and replay does not double-charge;
T10.5c rewind un-charges the exit commission; T10.6 margin/stop-out
(`UsedMargin`, `MarginLevel`, `FreeMargin`, `SSR_CLOSE_STOPOUT`,
`st.stopouts`, caveat line appears/disappears); T10.7 equity curve honours
a rewind and resumes sampling at the cut; T10.8 journal CSV round trip;
T10.9 five separate rewind scenarios (partial exit, filled pending, cancelled
pending, order after the cut, leg-ledger ceiling).

Column contract T10.8 hard-codes (must match `CSSRJournal::ExportCsv`
header, `SSR_Journal.mqh:218`): `0 ticket, 1 type, 2 tag, 3 volume,
4 open_time, 5 open_price, 6 close_time, 7 close_price, 8 reason, 9 profit,
10 commission, 11 swap, 12 r, 13 duration, 14 mae, 15 mfe,
16 resolution, 17 note`; `f[16] in {"ASSUMED","observed"}`; `f[12]` empty
(never `"0.000"`) when the trade had no stop; `# CAVEAT` line present.
Reader and writer agree on `FILE_TXT|FILE_ANSI`, so the UTF-8 trap does not
apply here.

Ledger invariant asserted: `SSR_MAX_TRADE_LEGS` (= 8, `SSR_TradeTypes.mqh:173`)
allows exactly `SSR_MAX_TRADE_LEGS - 1` = 7 partial exits out of 10 attempts,
and the final `Close` is never refused.

### T11 - Advanced Replay (`SSR_T11_AdvancedReplay.mq5`)
T11.1 RNG: same seed -> same 500 draws; different seed -> >490 differ; zero
seed does not stick; `InRange` half-open, degenerate and inverted ranges
return `lo`; 10 buckets x 10000 draws each within 700..1300; seed text round
trip. T11.2 the master clock: `Align()`, common window, and
`MaxSkewMsc() == 0` asserted **exactly** after 40 pumps, across two speed
changes with non-dividing deltas (37 ms, 17 ms), after a forward jump, after
a backward jump that must land at or before the asked instant, after
`StepBars(10)`, after `StepBackward(5)` and after `Restart()`. T11.3
non-overlapping streams: `Align` false with "no common period", `Play` false,
`Pump` returns 0. T11.4 auto-pause fires once on SL, names "stop loss", and
releases (`Play` then 20 pumps stays playing, `AutoPauses()` still 1).
T11.5 auto-pause switch off + a rewind must not re-fire; flag text round
trip ("off", contains "TP"). T11.6 `CSSRSessionWatcher` by gap (1 h
threshold), off, by day (midnight), and silent right after a rewind.
T11.7 blind mode policy/mask/leaks/anonymous naming, and the refusals
(`Apply(0)` false, `RestoreAll()==0`, off-policy applies nothing and lists
no leaks). T11.8 `SSRReplayClock.AdvanceTo` monotonic and clamped, residue 0.
T11.9 a group of one behaves like one stream. T11.10 a short stream narrows
the common window **and the long stream's own end**, and the board reaches
`AllCompleted()` with `LiveCount()==0` and zero skew.

### T12 - Session System (`SSR_T12_Session.mq5`)
T12.1 file format: repeated sections (`SectionCount("alpha")==2`,
`Select(name, idx)`), `long` past 2^53, exact double, bools, defaults,
repeated keys (`Count("r")`, `GetNth`), pack/unpack incl. pipe
neutralisation (`"a|b"` -> `"a/b"`), refusal of a newer `format` line
("newer build") and of a file with no format line ("no format line").
T12.2 fingerprint: equality, one revised print ("revised"), 11 extra bars
("+11"), a moved range ("moved"), pack/unpack round trip including a digest
past the signed maximum. T12.3 account round trip: counts, balance
(tolerance 0.005 despite the "compared exactly" comment), per-position
profit/commission/swap/MAE/`risk_at_entry`/tag/reason, **leg ledger**
(`leg_count`, leg volume and `realised`, last leg `closing`), stops on the
runner, a pending restored as its `request_type`/`request_price` with no
fill price, execution model travelled, margin still modelled, and finally a
rewind of the restored account over its own partial exit. T12.4 a
`balance_check` no trade supports still loads, balance comes from the log,
and the disagreement is in `warn` with both figures. T12.5 the equity curve
is stored and the derived statistics are not (`!r.Select("statistics")` -
see finding). T12.6 whole-session save -> fresh objects -> `Restore`:
instant, balance, open trades, equity samples, bookmark, settings
(seed/blind/pause flags/slot), `ReadSymbols`, `ReadWindow`, `Peek` summary,
no phantom auto-pause entry after the resync, play continues, step back
works, `Delete` then `!Exists`. T12.7 resume against revised bars warns
("revised", `ResumeReport()` contains "BUT"). T12.8 refusals: unknown
session, empty group (checked before the file - `SSR_SessionManager.mqh:309`),
and the wrong instrument (error names both "OTHER" and "TEST").

### T13 - Strategy layer (`SSR_T13_Strategy.mq5`)
Local probe `CSSRCheater : public CSSRStrategy` counts `bar_calls`,
`closed_reads`, `tried_future`, `got_future`, `forming_seen_closed` and is
the only place in the subsystem where a test subclasses production code.
T13.1 M1->M5/M15 aggregation on a ramp, oldest group withheld
(`Available(PERIOD_M5)==11` for 60 M1 bars), stamping, `HighestHigh`/
`LowestLow`, W1 refused, and a **fast-vs-slow `Extremes()` cross-check**
over shift 0..4 x count 1..4 (20 cases, all must agree). T13.2 the view
cannot show the future: negative and absurd shifts refused, out-parameters
cleared to 0.0, refusals counted, a span past the buffer refused entirely,
`Prime(hist, 100, cut)` takes 41 of 100 bars. T13.3 rewind drops bars; a
re-published bar updates in place. T13.4 `OnBar` only after a close, via the
cheater (8..16 calls over ~66 replay minutes at the default 1x speed;
`got_future == 0`; `forming_seen_closed == 0`; `view.Refusals() >= tried_future`).
T13.5 the reference strategy trades, every position is tagged
`"ref-breakout"`, never two at once, a manual trade is excluded from
`StatsFor`. T13.6 duplicate name refused ("told apart"), NULL refused,
unsupported timeframe refused. T13.7 `CSSRStrategyBroker`: refused before a
price (counted), then places a tagged trade, `MyOpenCount`/`MyPosition`/
`CloseAllMine` see only its own. T13.8 claims seed reproducibility
(see finding - asserts nothing about the seed).

### T14 - Integration (`SSR_T14_Integration.mq5`)
T14.1 frozen wire numbers asserted as literals (states 0-7, fidelity 0-2,
permissions 0x01/0x02/0x04, `SSR_CMD_PLAY/PAUSE/CLOSE_ALL` = 1/2/9),
`SSRGvName(3,"now") == "SSR.3.now"`, symbol hash stable, distinct and
< 2^31. T14.2 no session: `Refresh` false, empty banner, commands refused
with `SSR_RC_NO_SESSION`, `Discover()==0` - preceded by a wipe of slot 7.
T14.3 a live session read by a client: contract version, state, window,
streams, balance, `synthetic`, fidelity, `IsMySymbol`, banner contains
"REPLAY" and "synthetic", then 40 pumps with `pub.Publish()` per pump and
`st.now_msc == grp.Now()`. T14.4 (nested) read-only refuses pause and buy
with `SSR_RC_NOT_PERMITTED`, and **writing the permission GV by hand does
not help**: the publisher refuses the command anyway and counts it.
T14.5 (nested) with permission: pause, no re-execution on a second poll,
step, speed 500, a buy tagged `"external"`, and `SSR_RC_UNKNOWN_CMD` for
verb 4242. T14.6 (nested) heartbeat staleness
(`SSR_HEARTBEAT_STALE_MS`), revival, and `Withdraw` removing the variables.
T14.7 a client older than the publisher refuses to read and names both
versions plus "update". T14.8 contract-shape assertions: the read-verb
enumeration (see finding), `SSRPublicState.Progress()` bounds, `Can()`
masking, and the banner carrying "32% of results assumed".

### T15 - UX (`SSR_T15_Ux.mq5`)
T15.1 blind mode reaches the panel through `CSSRGroupPort::ReadState`:
`clock_text` carries "2024" when not blind, no date and an elapsed form when
blind, `symbol == "(blind)"`, and `now_msc` is still raw. T15.2 the trade
buttons refuse rather than invent a size: no price -> "no price"; no stop ->
"stop"; with risk 1% and stop 200 points it trades, the stop is below the
entry, `HasR()`, and `risk_at_entry` is 1% of `InitialBalance()` within 2%;
negative/over-100 risk and negative stop refused; `BreakEvenAll`;
`CloseAll`; then `BreakEvenAll` false. T15.3 a two-stream board reports
`streams==2`, `trade_symbol=="PRIMARY"`, a `"+1"` marker in `symbol`, zero
skew. T15.4 save/list/load through the port, then a load on revised bars
that succeeds **with** a "revised" message, plus unknown-name and empty-name
refusals. T15.5 a bare port: `ReadState` false and every action refused with
a reason; sessions unavailable. T15.6 `StrategyLine()` names one strategy
and its status, duplicate refused, empty host -> empty line. T15.7 key map
(see finding). T15.8 the panel takes `CHART_QUICK_NAVIGATION` and
`CHART_KEYBOARD_CONTROL` and gives them back (see finding). T15.9 the panel
moves its labels with it, exercised through `SetCorner` (see finding).
T15.10 the panel passes S and J to the host and claims SPACE.

---

## 4. Invariants this subsystem depends on (all verified in the sources)

1. `CSSRReplayController::Load` broadcasts `OnSessionStart` to every
   registered observer (`SSR_ReplayController.mqh:835-837`), and
   `CSSRTradingEngine::OnSessionStart` resets `m_balance = m_balance_initial`,
   `m_count = 0`, `m_next_ticket = 1` **and calls
   `m_risk.ConfigureFromSymbol(symbol)`** (`SSR_TradingEngine.mqh:570-591`).
   Therefore any `Risk().Configure(...)` made before `Load` is discarded, and
   observers added after `Load` never get a session start (T12.3 documents
   this and adds its observer first; T9 does not).
2. `CSSRTradingEngine::SetBalance` sets both `m_balance_initial` and
   `m_balance`, and the **constructor default is already 10000.0**
   (`SSR_TradingEngine.mqh:552, 562-563`).
3. `SSRStatistics::IsTrustworthy()` is exactly `trades > 0 && ambiguous_pct <= 10.0`
   (`SSR_Statistics.mqh:143-144`) - no minimum sample size, so T10.3's
   25%-vs-5% pair is a clean test of the threshold.
4. `CSSRStatsEngine::SaveInto` writes only `f.Section("equity")`
   (`SSR_Statistics.mqh:623-625`); no code anywhere writes a section named
   `"statistics"`.
5. Checkpoints: interval 5 replay minutes and the first one is due
   immediately (`SSR_SnapshotStore.mqh:33, 93-98`), so the snapshot branch
   of `StepBackward` (`SSR_ReplayController.mqh:1450-1460`) is normally
   taken; `Snapshots().Restores()` (`SSR_SnapshotStore.mqh:90`) is the
   observable that would prove it.
6. `CSSRStrategyHost::Add` guard order is: NULL, capacity, **timeframe**,
   empty name, duplicate name (`SSR_StrategyHost.mqh` `Add`), and each
   strategy's stream is `rng.Seed(m_seed ^ NameHash(s.Name()))` - order of
   registration independent by construction.
7. Default replay speed is `SSR_SPEED_1` (`SSR_ReplayClock.mqh:53`,
   `SSR_ReplayState.mqh:54`), i.e. one `Pump(1000)` is ~1 s of replay time.
   Every "N pumps" figure in T9-T15 is calibrated to that.
8. `CSSRWidgets::Common` always writes `OBJPROP_CORNER = CORNER_LEFT_UPPER`
   (`SSR_Widgets.mqh:160`) and `CSSRPanel::Render` never reads `m_corner`;
   only the (now removed) `SnapToCorner` recomputes `m_x/m_y`.
9. `CSSRPanel::RestorePlace` sets `m_place_loaded = true` unconditionally on
   its first line, so any later `SavePlace` writes `SSReplay\panel.ini`.
10. `SSR_Keys.mqh` maps `SSR_VK_R -> SSR_CMD_LINES_TOGGLE` and
    `SSR_VK_0 -> SSR_CMD_RESET`; `SSRKeyHint()` is a hand-written literal
    that still says "R reset".
11. Contract commands occupy exactly 0..11 (`SSR_Contract.mqh:92-108`).
12. `CSSRPublisher::Begin` only needs a non-NULL group (so T14.2's wipe
    works on an empty group) and `Withdraw` deletes all 23 slot variables.

## 5. Gaps in the subsystem's own surface

* No shared harness, so a fix to `Check` must be made seven times.
* No aggregate runner and no machine-readable verdict.
* No file asserts anything about `CSSRPropEvaluation`, `CSSRShotBook`,
  `CSSRFlightRecorder`, `CSSRCalendarLines`, `CSSRTradeLines`,
  `CSSRChartManager`, `CSSRSetupPanel`, `CSSRKeyCard`, `CSSRRevealCard`,
  `CSSRReviewCard`, `CSSRFirstRun`, `SSR_Strings`/the `fa.txt` loader, or
  the 63-character draw limit (T15 is the only UI file and it never renders
  a string near the limit).

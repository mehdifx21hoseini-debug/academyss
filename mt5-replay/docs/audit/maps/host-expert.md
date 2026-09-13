# ARCHITECTURE MAP — subsystem `host-expert`
**File:** `/home/user/academyss/mt5-replay/MQL5/Experts/SSReplay/SSReplayStandalone.mq5` (3,255 lines, build v125)
Single translation unit. **No classes are declared here** — the host is a flat set of
global objects + free functions + MT5 event entry points. Everything below is
file:line exact against v125.

---

## 1. What this program is

The one EA of the product. It is attached to *some* chart and it:
1. opens the broker M1 history for an origin symbol (`CSSRMt5DataSource`),
2. builds a custom replay symbol from it (`CSSRCustomSymbolSink`),
3. drives `CSSRReplayController` (via `CSSRReplayGroup`) from `OnTimer`,
4. draws the panel/dialogs on **the chart it is attached to** (`g_panel_chart = ChartID()`, line 1449),
5. and — in the default `InpOneChart=true` mode — **turns its own chart into the
   replay chart**, which deinitialises and reinitialises this same EA once
   (the "two-pass handover").

Comment block lines 5–27 states the intended end state: engine in a Service,
panel in an indicator, joined by IPC. `CSSRReplayPort`/`CSSRGroupPort` is the seam
that makes that a wiring change.

---

## 2. Includes / layers it reaches into (lines 32–67)

Common (Types, Time, Log, FlightRecorder) · Core (ReplayController, MasterClock)
· Data (Mt5DataSource, HistoryCatalog, Calendar, SessionWatcher, RandomPicker)
· Mt5 (CustomSymbolSink) · Chart (ChartManager, TradeLines, CalendarLines, BlindMode)
· Ui (Strings, Panel, RevealCard, ReviewCard, SetupPanel, RangeDialog, FirstRun,
GroupPort, SessionDialog) · Trading (TradingEngine, Statistics, Journal, AutoPause,
ShotBook, PropEvaluation) · Session (SessionManager) · Strategy (MarketView,
StrategyHost, RefStrategy) · Integration (Publisher).

---

## 3. The 61 inputs (lines 69–187) and who consumes them

Verified: `grep -c "^input "` = **61**. No input is unused (every name appears at
least once besides its declaration). **No input is range-checked anywhere in this
file.** Downstream clamps that do exist: `SetTicksPerBar` clamps `<4` to 4
(`Core/SSR_TickSynthesizer.mqh:106`), `SetWarmupBars` clamps `<0` to 0
(`Core/SSR_ReplayController.mqh:662`). `InpPumpMs` is clamped nowhere and is used
raw at 1574, 2754 (`MathMax(4*InpPumpMs,100)`) and 3149.

| Group | Inputs (default) | Consumed at |
|---|---|---|
| Session | `InpSymbol("")` 1871, 2911; `InpStart(0)` 1108, 2024, 1364; `InpReplayBars(2000)` 1101-1113, 2036-2040, 1128; `InpWarmupBars(1000)` 495-499, 1110, 1128, 2033; `InpChartTf(M5)` via `CfgChartTf()` **except** 511; `InpSlot(1)` 489, 1140, 1382-1395, 1604, 422; `InpTicksPerBar(8)` 498, 1147, 423; `InpSpreadPoints(20)` via `CfgSpread()` **except** 495, 424; `InpSpreadMode(RECORDED)` 496, 1148; `InpPumpMs(40)` above; `InpStartSpeed(30)` via `CfgSpeed()` | |
| Virtual account | `InpBalance` via `CfgBalance()`; `InpCommission`,`InpSlippage`,`InpSwapLong`,`InpSwapShort` 1168-1172; `InpMarginLot` 1177; `InpStopout` 1178 | `SSRExecutionModel` 1166-1178 |
| Practice | `InpAlsoSymbols` 455, 1023, 443-457; `InpExtraTfs` via `CfgExtraTfs()`; `InpRandom` via `CfgRandom()`; `InpSeed` via `CfgSeed()`; `InpBlind` via `CfgBlind()` **except** 419; `InpPauseEntry/SL/TP` 1208-1211; `InpPauseSession` 1226, 421 | |
| Persistence | `InpSession` via `CfgSession()`; `InpResume` 1063, 2015 | |
| Strategy | `InpRefStrategy` 1239; `InpStratTf` 1241-1243; `InpStratLookback`,`InpStratRisk` 1241 | |
| Integration | `InpPublish` 1375; `InpAllowControl`,`InpAllowTrade` 1379, 1391 | |
| UX | `InpRiskPercent` via `CfgRisk()`; `InpAutoHistory` 1978; `InpHistoryBars` 1980; `InpPickStart` 2025; `InpOneChart` 1893, 2555; `InpTradeLines` 1294, 1367, 2662, 2740; `InpStopPoints`,`InpRR` 1361-1365; `InpVitals` 1578, 2835; `InpFlightRec` 1544; `InpTradeHistory` 2779; `InpShots` 1284-1291, 1216; `InpAutoPlay` 1710; `InpFirstCard` 1736 | |
| News | `InpNews` 917, 940; `InpNewsPause` 941, 1222; `InpNewsShift` 947, 1221 | |
| Prop | `InpProp` via `CfgProp()`; `InpPropTarget/Daily/Total` via `CfgPropTgt/Dly/Tot()`; `InpPropTrail`,`InpPropMinDays`,`InpPropMaxDays` 1195-1197 | |
| Language | `InpLanguage` 1805 (`SSRLoadLanguage`, before anything is drawn) | |

### 3.1 The `Cfg*()` override layer (lines 214–241)
`SSRSetupValues g_setup` + `bool g_setup_ready`. Rule, stated at 208–213: *the
inputs are the default; the setup panel is what the user last said*. Fourteen
accessors: `CfgBalance, CfgRisk, CfgSpread, CfgSpeed, CfgChartTf, CfgExtraTfs,
CfgBlind, CfgSession, CfgProp, CfgRandom, CfgSeed, CfgPropTgt, CfgPropDly,
CfgPropTot`. `g_setup_ready` becomes true in exactly two places:
- 2518–2519 — the picker's START button (`g_setup_ui.Values(g_setup)`, then `CSSRSetupPanel::Save`),
- 1948 — **pass 2 only**: `g_setup_ready = CSSRSetupPanel::Restore(g_setup)` reading
  `MQL5/Files/SSReplay/setup.ini`, seeded first from the inputs at 1936–1947
  (note: `random_start` and `seed` are **not** seeded from `InpRandom`/`InpSeed`).

Known bypasses of this layer (raw `Inp*` where a `Cfg*()` exists): 419, 424, 425
(`CollectSettings`), 495, 511 (`OpenExtraStreams`).

---

## 4. Global state it owns

### 4.1 Owned objects (lines 189–290)
Primary stream: `g_src` (`CSSRMt5DataSource`), `g_sink` (`CSSRCustomSymbolSink`),
`g_ctrl` (`CSSRReplayController`), `g_charts` (`CSSRChartManager`).
Extra streams (`SSR_EXTRA_STREAMS = SSR_MAX_STREAMS-1`, `#define` at 261):
`g_src2[]`, `g_sink2[]`, `g_ctrl2[]`, `g_charts2[]`, count in `g_extra`.
UI: `g_panel`, `g_dialog` (range/jump), `g_session_dlg`, `g_setup_ui`, `g_first`,
`g_reveal`, `g_review`, `g_lines`, `g_cal_lines`.
Engine-adjacent: `g_group` (`CSSRReplayGroup` — one clock over all streams),
`g_gport` (`CSSRGroupPort` — the only thing the panel talks to), `g_blind`,
`g_picker`, `g_session` (session watcher), `g_autopause`, `g_shots`, `g_cal`,
`g_prop`, `g_view` + `g_strategies` + `g_ref_strategy`, `g_acct`, `g_stats`,
`g_journal`, `g_session_mgr`, `g_catalog`, `g_publisher` + `g_publisher2[]`,
`g_flight`.

### 4.2 Scalar state (lines 295–345)
| Name | Meaning | Written | Reset in OnInit? |
|---|---|---|---|
| `g_origin` | broker symbol being replayed | 1004, 1030, 1873 | no (reassigned) |
| `g_replay_chart` | chart id showing the replay (0 = none yet) | 1275, 2634 | no |
| `g_panel_chart` | chart the panel/dialogs live on = `ChartID()` | 1449 | no |
| `g_panel_paint` | last panel repaint (`GetTickCount`) | 2896 | no |
| `g_on_replay_chart` | is `_Symbol` a replay symbol | 1866 | yes (1866) |
| `g_switching` | handover asked for, EA about to die | 2668, 2696 | **yes** 1841 |
| `g_picking` | waiting for the start line | 2073, 2527 | **yes** 1843 |
| `g_pick_msc` | chosen start (msc) | 1886, 2530 | no — rides in a chart object |
| `g_switch_to` | replay symbol to hand the chart to | 1782, 2576 | **yes** 1842 |
| `g_last_pump_us` | `GetMicrosecondCount` of last pump | 1575, 2749 | no |
| `g_slow_tick` | timer-tick counter for cadences | 2806 | **yes** 1846 |
| `g_ready` | session built, engine may be pumped | 1580, 2210 | **yes** 1844 |
| `g_was_playing` | play-edge detector | 2775 | no |
| `g_vitals_left` | forced vitals lines (10) | 1576, 2838 | no |
| `g_pumps` | pumps performed | 2782 | **yes** 1845 |
| `g_init_note` | what OnInit inherited (into the black box) | 1836 | yes |
| `g_timer_ticks` | OnTimer entries, guards or not | 2450, 1577 | no (reset in BuildSession) |
| `g_starved` | pumps that lost time | 2757 | no |
| `g_ready_at_ms` | when the session became ready (watchdog) | 1577 | no |
| `g_watch_wanted` | observers asked for (866) | 1182 | no |
| `g_spread_reported` | one-shot spread diagnostic latch (2222) | 2263 | **no** |
| `g_guard_said` | last FlightGuard reason (2432) | 2440 | no |
| `g_revealed`, `g_reviewed`, `g_resumed` | one-shot latches | 2861/2872/1500 | no |

Lines 1815–1846 clear six of these *deliberately*, because the code does not know
whether globals survive the `REASON_CHARTCHANGE` reload (comment 1808–1834: "This
project has assumed both answers about that at different times and measured
neither"). The rest of the table is not cleared.

---

## 5. Free functions (public surface of this file)

| Function | Line | Responsibility | Callers |
|---|---|---|---|
| `ParseTimeframes(csv,out[])` | 350 | "M15,H1" → `ENUM_TIMEFRAMES[]`. Accepts only M1,M5,M15,M30,H1,H4,D1; anything else silently dropped | 1300, 508 (via arg) |
| `PrimeView()` | 382 | refill `g_view` with M1 bars a jump skipped; bounded by `g_view.Capacity()` and by `g_ctrl.Now()` | OnTimer 2798 |
| `CollectSettings(out)` | 415 | the settings block a session file carries | OnDeinit 2135 |
| `OpenExtraStreams(win_start,win_end,extra_tfs,n_tfs,from_session,n_session)` | 436 | build ≤ `SSR_EXTRA_STREAMS` further streams over the SAME window; a session file's symbol list wins over `InpAlsoSymbols`; each gets slot `InpSlot+1+i`; failures are skipped, not fatal | BuildSession 1327 |
| `StashOrigin(origin)` / `ReadStashedOrigin()` | 538 / 549 | carry the origin symbol name across the handover in a hidden `OBJ_LABEL` **named `SSR_ORIGIN_HANDOFF`** on chart 0. A leading `"!"` = "last second pass failed, do not try one-window again" | 1780, 826 / 1869 |
| `SeriesInfoIntegerOrZero(sym)` | 559 | M1 `SERIES_FIRSTDATE` as a value | 687 |
| `ReplayBarsReady(sym,display_tf)` | 596 | the handover guard: `CopyRates` M1 then `SERIES_BARS_COUNT`, ≤10×100 ms, then *primes* the display TF and ignores its answer (lazy-series lesson) | 2609 |
| `EnsureHistory(sym,want_bars)` | 623 | synchronous-ish async M1 download loop: 60 s cap, `Sleep(300)`, 6 dead passes = give up, `SERIES_SERVER_FIRSTDATE` as the floor | OnInit 1980 |
| `MiddleOfView()` | 699 | msc at the centre of the current view, or `SSR_INVALID_TIME` | 2035, 2503 |
| `ShowPicker(sym,default_msc)` / `RemovePicker()` | 725 / 800 | the orange `OBJ_VLINE` (`SSR_PICK_LINE`) + `START REPLAY HERE` / `LINE TO VIEW` buttons + info label | 2045 / 2528, 2114 |
| `FailInit()` | 822 | on a failed **second** pass: poison the stash (`"!"+origin`), put the chart back on the origin, return `INIT_FAILED` | 1882, 1932, 1987, 2079 |
| `Watch(o)` / `CheckObservers()` | 866 / 895 | register a tick observer and *report refusals*; then compare asked-for vs accepted | BuildSession 1183-1246 / 1247 |
| `LoadCalendar(origin,ws,we)` | 916 | load + draw news lines on `g_replay_chart`; off when `InpNews==OFF`, off in blind mode, skipped when there is no replay chart yet | 1283 |
| `OpenReview()` | 962 | the one place that opens the review card (does **not** set `g_reviewed`) | 2869, 2879, 2906 |
| `BuildSession(origin,on_replay,one_chart_ok)` | 971 | **the whole build.** Called from OnInit (2080) and from OnTimer's picker (2555) | see §6 |
| `ReportSpreadOnce()` | 2224 | one-shot "did the recorded spread exist" diagnostic | OnTimer 2455 |
| `PrintVitals()` | 2311 | one `[vitals]` line: state, clock, playing, speed, m1 bars, last bar, emit ticks, snaps, per-chart first/vis/off; plus the LATE line when `g_starved>0` | OnTimer 2839 |
| `RecordFlight(delta_ms)` | 2364 | the same facts as a `SSRFlightSample` | OnTimer 2792 |
| `FlightGuard(which)` | 2437 | one line per distinct reason OnTimer was turned back | 2470, 2578, 2708 |
| `RunHostCommand(cmd)` | 2900 | the three commands the host owns: REVIEW, SESSIONS, JUMP | OnTimer 2891, RouteEvent 3237 |
| `RouteEvent(id,l,d,s)` | 3162 | event precedence ladder (§8) | OnChartEvent 3160 |
| `OnInit/OnDeinit/OnTimer/OnChartEvent/OnTick` | 1789 / 2085 / 2447 / 3106 / 3254 | MT5 entry points. `OnTick` is deliberately empty | terminal |

---

## 6. `BuildSession` — the ordered build (971–1786)

The order is load-bearing; each step's rationale is in the comments cited.

1. **Blind policy decided here and only here** (988–999) — `CfgBlind()` →
   `g_blind.SetPolicy` → `g_sink.SetAnonymous`. It decides the replay symbol NAME
   (`EURUSD@.SSR1` vs `Chart.SSR1`), so both passes must agree (they do, because
   pass 2 adopts, §7).
2. **Range** `g_src.RangeInto(range)` (1001).
3. **Random pick** (1016–1046) if `CfgRandom()`: catalogue → picker → seed
   (`SSRSeedFromText(CfgSeed())`; `0` ⇒ `SSRPickSeed()`, i.e. a *fresh* seed) →
   may replace `origin`/`g_origin` and reopen `g_src`.
4. **Resume decision** (1063–1070): `CfgSession()!="" && InpResume && Exists()`,
   window read with `g_session_mgr.ReadWindow`.
5. **Window** (1099–1122): `win_end = range.last_msc`; start = *bars* counted back
   with `CopyRates(origin,M1,0,InpReplayBars)` (never minutes — the weekend-gap
   lesson), then `random_start | InpStart | g_pick_msc | auto_start`, floored at
   `range.first_msc + InpWarmupBars`; a resumed session overrides both (1124).
   `win_start >= win_end` ⇒ return false.
6. **Engine spec** (1139–1157): digits/point, spread, spread mode, ticks/bar,
   warmup, `SSR_DATA_BROKER`, fidelity = FULL_TICK iff `range.has_ticks`, `Attach`.
7. **Execution model + account** (1166–1178). `exec.use_real_spread = true` always.
8. **Observers, in a fixed order** (1182–1247): account → stats → [prop] →
   autopause → shots → calendar → session watcher → market view → strategies,
   then `CheckObservers()`. Order rationale at 1162, 1188, 1214.
9. `g_ctrl.Load(origin, win_start, win_end)` (1251) — seeds the custom symbol.
10. **Which chart shows the replay** (1259–1275):
    `g_replay_chart = g_on_replay_chart ? ChartID() : (one_chart_ok ? 0 : g_charts.OpenChart(CfgChartTf()))`.
    The test is `one_chart_ok`, *not* `InpOneChart` — they differ only when the
    stash was poisoned (comment 1262–1274).
11. Shots chart, calendar lines, trade lines (1277–1296); extra TF layout
    (1298–1305) only when `g_replay_chart != 0`; `ScanLeaks`.
12. **Multi-symbol** (1320–1333): `g_group.Add(primary)` (return ignored),
    symbols from the session file when resuming else `InpAlsoSymbols`,
    `g_group.Align()` (failure ⇒ return false).
13. **Port wiring** (1341–1372): `g_gport.Attach(group, sink, charts)` then
    `AttachBlind/Account/Prop/Stats/Strategies/Sessions/Lines/Journal`,
    `SetRiskPercent(CfgRisk())`, stop/TP defaults from `InpStopPoints`/`InpRR`.
14. **Publishers** (1375–1396): one for the primary (with the account), one per
    extra stream (no account, control permission only).
15. Blind applied to every *managed* chart after `Sync()` (1420–1435).
16. `g_catalog.Attach/Scan` (1439).
17. **UI creation, in z-order** (1449–1453): `g_panel_chart = ChartID()`, then
    `g_dialog.Create`, `g_session_dlg.Create`, `g_panel.Create`. `Comment("")`
    clears the handover notice (1460).
18. **Session restore** (1464–1476) then **saved-position resume** (1490–1519),
    which is skipped whenever the start was explicitly chosen
    (`random_start>0 || InpStart>0 || g_pick_msc!=INVALID`) and requires ≥50 bars
    ahead of the saved point.
19. **Flight recorder opened before the first pump** (1544–1562).
20. `EventSetMillisecondTimer(InpPumpMs)`, `g_last_pump_us`, `g_vitals_left=10`,
    `g_timer_ticks=0`, `g_ready_at_ms=GetTickCount()` (1574–1577); speed via
    `g_gport.SetSpeedX100(CfgSpeed()*100)`; **`g_ready = true` (1580)**.
21. Diagnostics: ready line, slot-collision scan over `SymbolsTotal` (1604–1636),
    bars-inside-window warning (1640–1661), SESSION READY line, chart-height
    warning, which chart owns the keyboard, `SSRKeyHint()`.
22. **Auto-play** (1710) and **first-run card** (1736), both gated on
    `!one_chart_ok`.
23. **Handover armed** (1778–1785): when `one_chart_ok && !g_on_replay_chart`,
    `StashOrigin(origin)` and `g_switch_to = g_sink.ReplaySymbol()`. The switch
    itself happens on the first timer tick (comment 1763–1771: calling
    `ChartSetSymbolPeriod` from inside OnInit would tear down a program that has
    not finished starting).

---

## 7. The two-pass handover protocol (the core invariant of this file)

```
pass 1 (origin chart)                         pass 2 (replay chart)
  OnInit: SSRPurgeChart(0, SSR_PICK_LINE)       OnInit: SSRPurgeChart(0, SSR_PICK_LINE)
          on_replay = false                             on_replay = true
          origin = InpSymbol|_Symbol                    origin = ReadStashedOrigin()
          [picker? -> timer -> BuildSession]            g_setup_ready = SetupPanel::Restore
          BuildSession(..., one_chart_ok)               g_sink.SetAdoptExisting(true)
            g_replay_chart = 0                          g_sink.SetAdoptName(_Symbol)
            StashOrigin(origin)                         BuildSession(..., true, ...)
            g_switch_to = replay symbol                   g_replay_chart = ChartID()
  OnTimer #1: guards -> SymbolSelect ->               OnTimer: pumps the engine
            exists/shown/ReplayBarsReady ->
            g_switching = true; Comment(...);
            ChartSetSymbolPeriod(ChartID(), rs, CfgChartTf())
  OnDeinit(REASON_CHARTCHANGE): keep symbol,
            save session + position, destroy UI
```
Invariants the code relies on:
- **I1** chart objects survive `ChartSetSymbolPeriod`, so `SSR_ORIGIN_HANDOFF`
  (536) and `SSR_PICK_HANDOFF` (556) are the transport for the origin name and the
  picked start. (Both names begin with `"SSR"` — see finding host-expert-1.)
- **I2** on pass 2 the replay symbol name is **read, never recomputed**
  (`SetAdoptName(_Symbol)`, 1963–1964); `Mt5/SSR_CustomSymbolSink.mqh:152-166`
  prints a warning and adopts if the two disagree, and `ClearAll()`s the history.
- **I3** MetaTrader will not delete a symbol a chart is open on — hence adoption on
  pass 2, and hence "give the chart back before the symbol goes" in OnDeinit (2186).
- **I4** the pass that is about to hand over must not pump, must not open charts,
  must not auto-play, must not show the first-run card (it is ~50 ms from death).
- **I5** a failed pass 2 must put the chart back and poison the stash (`FailInit`).
- **I6** `g_switching` must be false at the start of every pass (1841), because
  `OnTimer`'s second guard is `if(g_switching) return;` — a surviving `true` would
  turn the engine back at the door forever.
- **I7** the handover is refused unless the replay symbol *exists*, is *in Market
  Watch* and *has M1 bars* (2607–2612); a refusal must still leave the user a
  chart, so a separate window is opened then (2631–2656).

---

## 8. `OnTimer` — the guard ladder and the cadences (2447–2897)

```
g_timer_ticks++                       (always, first statement; proof of life)
ReportSpreadOnce()                    (runs even while picking / not ready)
if(g_picking)  { picker UI, START -> BuildSession } return
if(g_switching) { FlightGuard } return
if(g_switch_to != "") { handover or refusal } return
if(!g_ready)   { FlightGuard } return
g_shots.Flush(); g_first.Tick()
delta = (GetMicrosecondCount()-g_last_pump_us)/1000, capped at max(4*InpPumpMs,100)
        -> over the cap counts g_starved and DROPS the time (never repays it)
play edge: !was_playing && playing -> g_charts.FollowAll() (+ extras)
if(playing) g_group.Pump(delta); g_pumps++
RecordFlight(delta)
strategies && view empty && clock moved -> PrimeView()
g_publisher.Poll() (+ extras)          every pump
g_slow_tick++
  %5   : publishers Publish, g_charts.Sync, blind re-apply, Redraw, extras Sync
  %5   : trade-line position sweep (open/pending/closed) + EndPositions
  %25 playing / %250 paused : PrintVitals (or while g_vitals_left>0)
  %50  : g_charts.ScanLeaks, feed measured seed rate to the catalogue
lines: if armed -> Poll + NoteLineDistances (every pump)
reveal (blind + COMPLETED) -> Show; Poll -> RestoreAll + review
prop COMPLETED -> OpenReview once
review Poll -> "stmt" exports the HTML statement
modal = session_dlg || range dlg || reveal || review
if(!modal) RunHostCommand(g_panel.PollClicks())
if(!modal && GetTickCount()-g_panel_paint >= 100) g_panel.Render()   // 10 fps
```

## 9. `OnChartEvent` / `RouteEvent` precedence (3106–3251)

1. `g_setup_ui.OnChartEvent` first, **before** the `g_ready` gate (it only exists
   while the session is *not* ready). It handles `CHARTEVENT_MOUSE_MOVE` only.
2. `if(!g_ready) return;`
3. **Watchdog** (3145–3157): once, if `g_timer_ticks == 0` && !switching && !picking
   && >1500 ms since ready ⇒ `EventSetMillisecondTimer(InpPumpMs)` + flight event.
   The test is "the timer has never *entered*", deliberately not `g_pumps == 0`.
4. `RouteEvent`: session dialog → range dialog (confirm ⇒ in-window
   `g_group.JumpTo`, else "needs a fresh session") → flight-record every KEYDOWN →
   review owns keys / reveal swallows keys → `g_panel.OnEvent` → S/J/A via
   `SSRKeyToCommand` ⇒ `RunHostCommand`.
   `CHARTEVENT_OBJECT_CLICK` on panel objects is deliberately *not* routed: the
   panel is polled (`PollClicks`) so that a panel on either chart behaves the same.
   Key ownership split is enforced by `CSSRPanel::Owns` (`Ui/SSR_Panel.mqh:2163-2176`),
   which returns false for SESSIONS/JUMP/REVIEW/REPLAY_FROM_HERE so the host sees them.

## 10. `OnDeinit(reason)` — the reason matrix (2085–2212)

Always: `EventKillTimer`; flight `Event("deinit reason=...")` + `Close`;
`g_publisher.Withdraw()` + extras; `g_setup_ui.Destroy`; `RemovePicker`;
`g_session_dlg.Destroy`; `g_dialog.Destroy` (twice: 2112 and 2150); `g_panel.Destroy`;
`g_first.Clear`; `g_cal_lines.Clear`; `g_ready = false`.
`REASON_REMOVE|PROGRAM|CLOSE` only: delete `SSR_PICK_HANDOFF`; journal summary +
strategy report + `ExportCsv`; `g_blind.RestoreAll()`; put the chart back on the
origin and delete `SSR_ORIGIN_HANDOFF`; `g_charts.CloseOwned()`; `g_ctrl.Release()`;
extras closed/released; `g_group.Clear()`; `g_extra = 0`.
`if(g_ready)` (any reason): save the named session (`CollectSettings`) and
`g_ctrl.SavePosition()` for every stream.
**Not** destroyed on any reason: `g_reveal`, `g_review`, `g_lines` objects
(the next `OnInit`'s `SSRPurgeChart` sweeps them off chart 0 only).

## 11. What it writes to disk / chart

| Target | Written by | When |
|---|---|---|
| `MQL5/Files/SSReplay/setup.ini` | `CSSRSetupPanel::Save` (2520) | picker START |
| `MQL5/Files/SSReplay/sessions/<name>.ssr` | `g_session_mgr.Save` (2137) | OnDeinit when `g_ready && CfgSession()!=""` |
| `MQL5/Files/SSReplay/positions/…` | `g_ctrl.SavePosition()` (2146) | OnDeinit when `g_ready` |
| `MQL5/Files/SSReplay/journal/*.csv` | `g_journal.ExportCsv` (2174) | user removed |
| journal HTML statement | `g_journal.ExportHtml` (2885) | review card "stmt" |
| `MQL5/Files/SSReplay/journal/shots/*.png` | `g_shots` | per entry/exit |
| black box file | `g_flight` (1545) | whole session |
| `MQL5/Files/SSReplay/seen.txt` | `CSSRFirstRun::MarkSeen` (1741) | first-run card shown |
| chart 0 objects | `SSR_ORIGIN_HANDOFF`, `SSR_PICK_HANDOFF`, `SSR_PICK_LINE`, `SSR_PICK_GO`, `SSR_PICK_INFO`, `SSR_PICK_HERE`, `Comment()` | see above |
| custom symbol | via `g_sink`/`g_ctrl` only | seed + playback |

## 12. Diagnostics the host is the sole owner of
`[host]` log lines (≈60), `[vitals]` (once a second, plus the first 10 whatever the
input says), `[spread]` one-shot, `[news]`, `[shots]`, `FlightGuard` one line per
distinct turned-back reason, `CheckObservers` asked-vs-accepted, the slot-collision
scan, the window-bar-count warning, and the chart-height warning.

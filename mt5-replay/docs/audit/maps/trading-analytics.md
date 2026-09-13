# SS Replay — trading-analytics subsystem map (v125)

Files (all under `MQL5/Include/SSReplay/Trading/`):
`SSR_Statistics.mqh` (720 l), `SSR_Journal.mqh` (1254 l), `SSR_ShotBook.mqh` (311 l), `SSR_PropEvaluation.mqh` (481 l).

All four read the virtual account **only** through `CSSRTradingEngine::Total()` / `At(i, SSRVirtualPosition&)` (a full struct copy, ~660 B + two strings per call), `Equity()`, `InitialBalance()`, `MarginModelled()`, `Stopouts()`, `OpenCount()`, `ClosedCount()`. Positions are stored in **slot order = creation (ticket) order**; `At(i)` walks slots, never a close-time order. Nothing here calls the broker.

Shared contract: `CSSRTickObserver` (`Core/SSR_ITickObserver.mqh`): `OnBarContext`, `OnTicks(ticks[],count)`, `OnClock(now_msc)`, `OnRewind(msc)`, `OnSessionStart(symbol,digits,point,start_msc)`, `PauseRequested(string&)` (must self-consume).
Dispatch facts (`Core/SSR_ReplayController.mqh`): `OnTicks` per bar segment (l.198-231); `OnClock` **once per Pump/PumpTo, after all ticks of that pass** (l.1027-1029, 1102-1104); `JumpForward` (l.1333-1420) publishes **no** `OnClock`; `Pump` returns 0 unless PLAYING (l.998); `OnRewind` from step-back/jump-back (l.1240, 1286, 1644) **and from `NotifyRestored()` on a session resume** (l.1668-1669, called by `Session/SSR_SessionManager.mqh:381`).
Host registration order (`Experts/SSReplay/SSReplayStandalone.mq5` l.1176-1247): account → stats → prop (only if `CfgProp()`) → autopause → shots → calendar → session → view → strategies. Observers therefore see the account state *after* the engine acted on the same tick.

---

## 1. `SSRStatistics` (struct) — `SSR_Statistics.mqh:43-171`
Plain value object; every field listed at l.46-114. `Init()` zeroes all. Semantics that later code relies on:
- `trades` = closed positions only (cancelled pendings and open positions excluded); `open_now` separate.
- **net per trade = `profit + swap - commission`** (l.431). `wins`/`losses`/`breakeven` decided on that net. `net_profit = gross_profit - gross_loss`.
- `profit_factor` **stays 0.0 when `gross_loss == 0`** (l.529-530) — "undefined", caller must read `losses`.
- `average_r`/`total_r`/`r_trades`: only over `p.HasR()` trades (risk_at_entry > 0). `expectancy_r == average_r`. NB `SSRVirtualPosition::RMultiple()` (`SSR_TradeTypes.mqh:270`) is `(profit + swap) / risk_at_entry` — **commission excluded**, unlike net.
- `max_drawdown`/`max_drawdown_pct`: from the equity ring (see engine). `max_drawdown_closed`: balance walk over closed trades **in slot order**.
- `win_streak`/`loss_streak`, `revenge_trades`: computed in slot order.
- `risk_spread_pct` = population CV of `risk_at_entry` (%), needs `risk_samples > 1`.
- `avg_spread_points`/`worst_spread_points`/`spread_samples`/`wide_spread_trades` (≥ 2× session average, second pass).
- `avg_mae`/`avg_mfe` are **in price units** (engine `SSR_TradingEngine.mqh:296-299`), mae ≤ 0.
- `ambiguous_*`, `margin_modelled`, `trades_without_stop` = data-quality block. `IsTrustworthy()` = trades>0 && ambiguous_pct ≤ 10. `Caveat()` builds the sentence; `ToString()` the one-line summary (prints PF as `%.2f`).

## 2. `SSRBucket` — `SSR_Statistics.mqh:182-198`
`trades, wins, net, total_r, r_trades`; `WinRate()`, `AverageR()`. Filled by `CSSRStatsEngine::Bucket` by **entry time**, server time (`TimeToStruct(open_msc/1000)`), weekday (0=Sunday) or hour.

## 3. `CSSRStatsEngine : CSSRTickObserver` — `SSR_Statistics.mqh:209-717`
Responsibility: compute `SSRStatistics` on demand; own the **equity curve** (the only non-derivable statistic).
State owned: `m_acct*` (not owned), `m_eq_msc[]`/`m_eq_val[]` heap ring of `SSR_EQUITY_SAMPLES=4096`, `m_eq_count`, `m_eq_last_msc`.
Public surface: `Attach(acct)`, `Name()="statistics"`, `EquitySamples()`, `EquityAt(i,msc&,val&)`, `OnSessionStart` (clears curve), `OnTicks` (samples at last tick's `time_msc`), `OnClock` (samples), `OnRewind(msc)` (keeps samples ≤ msc), `EquityDrawdown(money&,pct&)`, `Compute(out)`, `ComputeFor(tag,out)`, `SaveInto(CSSRSessionFile&)` / `RestoreFrom` (section `equity`, key `e` = `"msc|val"`), `OpenCountFor(tag)`, `ByWeekday(out[])`, `ByHour(out[])`, `ClosedDrawdown()`, `ClosedDrawdownFor(tag)`.
Invariants relied on: sampling interval 60 000 ms replay (l.34); when the ring is full the **oldest half is dropped** (l.272-284); the engine has already processed the batch when `Sample` runs (registration order); a tag filter applies to every closed-trade measure **except** drawdown, which is always the whole account's (documented l.373-377); `ComputeFor` returns after `Init()` with everything zero when no closed trade matches.
Callers: host `OpenReview()` (l.976) and reveal card (l.3010); `CSSRJournal` (CSV/HTML/Summary); `CSSRStrategyHost::Report/StatsFor`; `CSSRSessionManager` Save/Restore; `SSR_Review.mqh` consumes the struct. The panel Stats tab does **not** use it (it reads balance/equity/floating from the port model).
Writes: nothing to disk itself; the session file section via `SaveInto`.
Cost: `ComputeFor` = up to 3 passes over `Total()` slots with a struct copy each + O(4096) drawdown walk; `RestoreFrom` is O(n_samples × n_entries) because `CSSRSessionFile::GetNth` is a linear scan (`SSR_SessionFile.mqh:331-344`).

## 4. `CSSRJournal` — `SSR_Journal.mqh:26-1251`
Responsibility: the exported record — CSV for spreadsheets, HTML statement for people, one-line `Summary()` for the log.
State owned: `m_acct*`, `m_stats*` (may be NULL), `m_prop*`, `m_shots*` (may be NULL), `m_last_error`, `m_last_path`, session identity `m_sess_name/symbol/start/end/seed` (set by host l.1355 from `CfgSession()`, origin, window, seed).
Public surface: `Attach(acct, stats)`, `AttachProp`, `AttachShots`, `SetSession(...)`, `SessionKey()` = `"symbol|start|end|seed"` (grouping key for the class report), `LastError/LastPath`, `Count()` (=ClosedCount), `Line(index,digits)` (O(n) walk), `ExportCsv(name,digits)`, `ExportHtml(name,digits)`, `Summary()`. Everything else (`WriteEquity`, `WriteWeekday`, `WriteHours`, `WriteAllMeasures`, `WriteShotCell`, `HasAnyShot`, `CollectTags`, `Html`, `Csv`, `Signed`, `Cls`, `HoldText`, `PeakAbs`, `DayName`, `Measure`, `MeasureHead`) is public in the class but only used internally.
Writes to disk (`MQL5/Files/`): `SSReplay\journal\<name>.csv` and `SSReplay\journal\<name>.html`, both `FILE_WRITE|FILE_TXT|FILE_ANSI|FILE_SHARE_READ`, CRLF, `FolderCreate(SSR_JOURNAL_DIR)` first. `name` is used verbatim (host passes `g_origin + "_" + yyyymmdd` on deinit, `"SSReplay-session"` from the review card / port).
CSV layout: `#`-prefixed header lines (`exported, session, symbol, window_start, window_end, seed, session_key`, then if stats attached `trades, win_rate, profit_factor(%.4f), net_profit, expectancy, average_r, r_trades "a of b", max_drawdown, max_drawdown_pct, win_streak, loss_streak, ambiguous_trades "n (p%)", margin_modelled, CAVEAT`), then column header `ticket,type,tag,volume,open_time,open_price,close_time,close_price,reason,profit,commission,swap,r,duration,mae,mfe,resolution,note` and one row per **closed** position in slot order. `profit` column is raw `p.profit` (commission and swap are separate columns); `r` empty when undefined; `mae/mfe` `%.5f`; `resolution` = `ASSUMED|observed`. Escaping `Csv()`: `,`→`;`, CR/LF→space, nothing else (no quoting).
Consumer of the CSV: `Report/SSR_ClassReport.mqh::ReadOne` (splits on `,`, reads `# key,value` lines, `open_time`, `profit` (won = profit > 0), `r` empty = no stop).
HTML layout: head from `SSRWriteReportHead` (declares `<meta charset="utf-8">`), caveat box, evaluation box (if prop on: `StateName`, `Report()`, `Reason()`), 9-KPI grid, equity SVG (min/max decimation to ≤1400 pts, hover script), weekday table, hour bars, by-setup table (≥2 tags), trades table (net per row, optional Chart column with `<img src="shots/<run>/t<ticket>-in|out.png">`), "Every measure" table, theme toggle. `Html()` escapes `& < > "`.
Invariants relied on: every HTML number comes from one `SSRStatistics` computed once at the top (`st`); shot paths are relative to the journal folder and only emitted when `FileIsExist` said so; prop verdict text is whatever `CSSRPropEvaluation` says at export time.

## 5. `CSSRShotBook : CSSRTickObserver` — `SSR_ShotBook.mqh:63-308`
Responsibility: one PNG at entry and one at exit for every position, taken **one timer pass late**.
State owned: `m_acct*`, `m_chart` (replay chart id, set by host l.1281/2655), `m_on` (`InpShots`), `m_run` (folder id `yyyymmdd-hhmmss` from `TimeLocal`), `m_seen[]`/`m_seen_count` (last state per slot), queue `m_q_ticket[]`/`m_q_kind[]`/`m_queued`, counters `m_taken/m_failed`, `m_capped` (500 per run), `m_last_error`.
Public surface: `Attach`, `SetChart`, `Enable`, `IsOn`, `Taken`, `Failed`, `Pending`, `Run`, `LastError`, `NewRun()`, `RelPath(ticket, entry)` → `"shots/<run>/t<ticket>-in.png"` or `""` if the file is absent, `Flush()` (host calls at the top of every timer pass, l.2731), `OnTicks` → `Scan()`, `OnRewind` (drop queue, `Reseed`), `OnSessionStart` (new run, `Reseed`), `Reseed()` (adopt current states without owing pictures). Free function `SSRShotFile(ticket, entry)` = `"t%d-in|out.png"` shared with the journal.
Transition rules (`Scan`, l.112-148): slot state changed to OPEN → entry shot; to CLOSED → exit shot, plus an entry shot if the slot was never seen OPEN. PENDING/CANCELLED transitions produce nothing. Partial closes (state stays OPEN) produce nothing.
Writes to disk: `MQL5/Files/SSReplay\journal\shots\<run>\t<ticket>-in.png|-out.png` via `ChartScreenShot(m_chart, path, w, h, ALIGN_RIGHT)`; `FolderCreate(RunFolder())` on every shot; size = chart pixel size clamped to 800..1600 × 450..900.
Invariants relied on: registered after the engine; ticket numbers restart per session, hence the per-run folder; a re-shot after rewind overwrites the same file; nothing is ever deleted.

## 6. `SSRPropRules` (struct) — `SSR_PropEvaluation.mqh:68-102`
`enabled, start_balance, profit_target_pct, max_daily_loss_pct, max_total_loss_pct, trailing, min_trading_days, max_days (0 = none)`; `Init()` defaults 8/5/10/static/3/30; `ToString()` one line for the statement. Filled by the host l.1185-1194 from `CfgProp/CfgBalance/CfgPropTgt/CfgPropDly/CfgPropTot/InpPropTrail/InpPropMinDays/InpPropMaxDays`.

## 7. `CSSRPropEvaluation : CSSRTickObserver` — `SSR_PropEvaluation.mqh:105-478`
Responsibility: judge the virtual account against the rules, **once per `OnClock`**; a rewind voids the run.
State owned: `m_acct*`, `m_rules`, `m_state` (`OFF|RUNNING|PASSED|FAILED|VOID`), `m_reason`, `m_first_day`/`m_day` (server-day index = `msc / 86 400 000`), `m_day_open_eq`, `m_day_low_eq`, `m_day_traded`, `m_peak_eq`, `m_low_eq`, `m_trading_days`, `m_total_days`, `m_last_positions` (last seen `m_acct.Total()`), `m_pause_pending`, `m_started`. **No SaveInto/RestoreFrom exists**; the session manager persists only the account and the equity curve.
Public surface: `Attach`, `SetRules`, `Rules(out)`, `State`, `StateName`, `Reason`, `IsOn`, `IsOver`, `TradingDays()` (= counter + open day if traded), `TotalDays`, `PeakEquity`, meters 0..1 `TargetProgress`, `DailyUsed`, `TotalUsed`, `DaysProgress`, `DeadlineUsed`, `ProfitPct`, floors `DailyFloor` (= day-open equity − start×daily%), `TotalFloor` (start or peak − start×total%), `Floor()` (the higher of the two), `Headline()`, `Reset()` (RUNNING if enabled; adopts `Positions()`), `OnSessionStart` (Reset + first day from `start_msc`), `OnClock` (the rules), `OnRewind` (RUNNING → VOID + pause), `PauseRequested`, `Report()`.
`OnClock` order (l.358-438): first call only establishes the day/peak (returns); then update peak/low/day-low; day-traded if `Total()` rose; **rule 1** daily: `eq <= DailyFloor()` (checked against the day still open, before the roll); **rule 2** total: `eq <= TotalFloor()`; **rule 3** roll day if `now/DAY > m_day` (`RollDay`: count traded day, `m_total_days = to_day − first_day + 1`, new `day_open_eq = Equity()`); **rule 4** deadline `m_total_days > max_days`; **rule 5** target `eq >= start×(1+target%)` only if `trading_days + open day >= min_trading_days`.
Consumers: `Ui/SSR_GroupPort.mqh` l.204-232 copies every accessor into the panel model and exposes `Reset()` via the port (l.768-770); `CSSRJournal` prints `StateName/Report/Reason` into the statement; `PauseRequested` reason goes to the controller's auto-pause.
Invariants relied on: "day" = server-time midnight (UTC arithmetic on server-stamped msc); daily and total allowances are sized from **start balance**, daily measured from the day's opening **equity**, total from start or the **equity** peak; `Positions()` = `m_acct.Total()` which counts pending orders as well as fills; the evaluation is only judged where `OnClock` is published.

## Cross-file data flow summary
```
engine.m_pos[] (slot order) ──At()──► StatsEngine.ComputeFor ──► SSRStatistics ──► Journal (CSV/HTML/Summary), Review card, StrategyHost
engine.Equity() ──OnTicks/OnClock──► StatsEngine ring ──► max_drawdown, HTML SVG, session file [equity]
engine.Equity()/Total() ──OnClock──► PropEvaluation ──► GroupPort model (Prop tab), Journal statement, auto-pause
engine state transitions ──OnTicks──► ShotBook queue ──Flush (timer)──► PNG files ──RelPath──► Journal HTML <img>
```

## C. CONFIRMED BUGS

Every finding in this section carries `classification: CONFIRMED` in `/home/user/academyss/mt5-replay/docs/audit/verified.json`: it survived three adversarial refuters, two of whom re-derived it from source. **197 entries, all of them, nothing omitted.** [CONFIRMED FROM CODE]

How to read an entry:

- **Failure scenario** is the state and the inputs that turn into the wrong outcome. Where the verifiers filed a `corrected_claim` (177 of 197 entries), the scenario below is *theirs*, not the finder's - the finder's headline is sometimes broader than what the code actually does, and the narrowed version is the one to fix against. The one-line title in the tables of contents is the finder's original wording, kept so ids stay searchable against `verified.json`; where a title overstates the defect, the entry says so.

- **Why** is the mechanism: the line, the missing guard, the wrong operand.

- **Verifiers** is the three refuters' agreed reasoning compressed to one line.

- **Fix** is a sketch that fits the code as it stands - same call sites, same naming, same MQL5 constraints (click-only panel, 63-char `OBJPROP_TEXT`, creation-order z-order, no clipping or scrolling, `ObjectSet*` at ~0.07 ms a write). Every fix is tagged [RECOMMENDATION]; none of them has been compiled or run, because the author has never had an MT5 terminal (build v125).

Nothing in this section is a runtime observation. Line numbers are build v125. The 30 POTENTIAL_RISK findings are **not** here - they are in section D; the 21 NOT_A_BUG findings appear nowhere as defects.

### C.1 Counts

| Severity | Confirmed | What it means here |
|---|---:|---|
| CRITICAL | 2 | Loses money the user thinks they have, or strands the product unusable, on a default configuration. |
| HIGH | 14 | Silently wrong numbers or a core feature that does not do what its name says. |
| MEDIUM | 58 | Wrong output or dead behaviour a user will meet in normal use. |
| LOW | 105 | Bounded wrongness, a dead branch, a cosmetic overrun, or a test that cannot fail. |
| IMPROVEMENT | 18 | Not wrong output; dead code, stale comments, or an instrument that cannot report. |
| **Total** | **197** | |

Distribution by subsystem - the fix-a-file-at-a-time view:

| Subsystem | CRIT | HIGH | MED | LOW | IMPR | Total |
|---|---:|---:|---:|---:|---:|---:|
| Host expert | 1 | 0 | 5 | 7 | 0 | **13** |
| Core engine | 0 | 5 | 3 | 5 | 2 | **15** |
| Data layer | 0 | 1 | 1 | 3 | 1 | **6** |
| MT5 bridge | 0 | 1 | 1 | 2 | 0 | **4** |
| Chart layer | 0 | 0 | 4 | 6 | 0 | **10** |
| Trading and risk | 1 | 2 | 7 | 10 | 1 | **21** |
| UI layer | 0 | 2 | 12 | 21 | 6 | **41** |
| Session | 0 | 1 | 1 | 2 | 0 | **4** |
| Strategy | 0 | 1 | 1 | 5 | 0 | **7** |
| Report | 0 | 0 | 2 | 1 | 0 | **3** |
| Integration | 0 | 0 | 0 | 2 | 1 | **3** |
| Spike kit | 0 | 1 | 1 | 1 | 0 | **3** |
| Common | 0 | 0 | 1 | 1 | 0 | **2** |
| Test harness | 0 | 0 | 6 | 18 | 5 | **29** |
| QA scripts | 0 | 0 | 2 | 7 | 2 | **11** |
| Spike and probe programs | 0 | 0 | 11 | 10 | 0 | **21** |
| Tooling | 0 | 0 | 0 | 4 | 0 | **4** |
| **Total** | **2** | **14** | **58** | **105** | **18** | **197** |

Read the shape of that table before the entries. Two thirds of the confirmed defects (41 UI + 29 tests + 21 spikes + 11 QA = 102) are in the presentation layer and in the programs that are supposed to police it; the engines that move money (Core 15, Trading 21) hold 36 between them, but both CRITICALs and 7 of the 14 HIGHs live there. [INFERENCE] The test harness and the spike programs are not incidental: 29 + 21 + 11 = 61 entries are assertions that cannot fail, gates that print instead of asserting, and probes that measure a flag instead of the work - which is why a v125 that has never run on a terminal still reports green. [INFERENCE]

### C.2 Table of contents by subsystem

Ordered within each subsystem by severity. Ids are the `verified.json` ids; cite them as-is. [CONFIRMED FROM CODE]

#### Host expert - SSReplayStandalone.mq5 (13)

| id | sev | line | defect |
|---|---|---|---|
| `host-expert-1` | CRITICAL | `SSReplayStandalone.mq5:1806` | OnInit's object sweep deletes the handover stash before it is read, so the second pass of one-window mode can never find its origin symbol |
| `host-expert-5` | MEDIUM | `SSReplayStandalone.mq5:1020` | A random session does not survive the handover: pass 2 either re-rolls a new seed or drops randomness entirely, and can replay a different instrument under pass 1's symbol name |
| `host-expert-3` | MEDIUM | `SSReplayStandalone.mq5:1710` | Auto-play is suppressed on the pass that actually owns the replay chart: the guard tests one_chart_ok instead of "am I about to hand over" |
| `host-expert-6` | MEDIUM | `SSReplayStandalone.mq5:1948` | Pass 2 restores setup.ini unconditionally, so a run that never opened the setup form inherits an unrelated earlier run's balance, prop rules and session name and they overrule this run's inputs |
| `host-expert-8` | MEDIUM | `SSReplayStandalone.mq5:2203` | Replay and extra-timeframe chart windows are leaked on every re-init that is not a user removal |
| `host-expert-7` | MEDIUM | `SSReplayStandalone.mq5:3167` | Keys are not withheld while the Sessions or Jump dialog is open: Space, Tab and the arrows drive the replay behind the dialog and the panel reprints over it |
| `host-expert-10` | LOW | `SSReplayStandalone.mq5:495` | Extra streams and the session-settings block bypass the Cfg*() accessors, so the setup panel's spread and chart timeframe apply to the primary instrument only |
| `host-expert-11` | LOW | `SSReplayStandalone.mq5:651` | EnsureHistory's 60-second budget is computed with a ulong subtraction of a 32-bit tick count and breaks at the GetTickCount wrap |
| `host-expert-4` | LOW | `SSReplayStandalone.mq5:1736` | The first-run card can never appear in one-window mode - same wrong guard as auto-play |
| `host-expert-2` | LOW | `SSReplayStandalone.mq5:1903` | On the replay chart InpSymbol is ignored, so the recovery the failure message tells the user to perform cannot work |
| `host-expert-14` | LOW | `SSReplayStandalone.mq5:2069` | The setup panel's drag handler can never fire, because mouse-move events are not enabled until the main panel is created |
| `host-expert-9` | LOW | `SSReplayStandalone.mq5:2260` | The one-shot spread diagnostic is consumed by the start-picker phase and then permanently suppressed for the real session |
| `host-expert-13` | LOW | `SSReplayStandalone.mq5:2555` | The picker path rebuilds with InpOneChart, discarding the one_chart_ok poison OnInit had just read |

#### Core engine - Include/SSReplay/Core (15)

| id | sev | line | defect |
|---|---|---|---|
| `core-sync-1` | HIGH | `SSR_MasterClock.mqh:208` | Group idle gap-skip fires mid-bar at human speeds and bulk-writes the unfinished bar, so observers (trading engine) never receive the rest of that bar's ticks |
| `core-engine-4` | HIGH | `SSR_ReplayController.mqh:349` | FULL_TICK window with zero broker ticks is consumed silently; tick availability is never re-evaluated per window |
| `core-engine-1` | HIGH | `SSR_ReplayController.mqh:524` | Per-pump budget cap silently DROPS bars instead of deferring them (dead 'stop short' branch) |
| `core-engine-2` | HIGH | `SSR_ReplayController.mqh:1169` | StepBars(n) from a bar end advances n-1 bars; StepBars(1) is a no-op after the first step |
| `core-engine-3` | HIGH | `SSR_ReplayController.mqh:1383` | JumpForward feeds bulk bars to the sink but never to observers; StepBackward routes through it, so every step back replays up to 5 minutes blind to the trading engine |
| `core-engine-5` | MEDIUM | `SSR_ReplayController.mqh:472` | bars_consumed counts a bar once per pump that touches it, not once; the panel 'Bars' figure and the legacy resume check are wrong by 10-1500x |
| `core-engine-6` | MEDIUM | `SSR_ReplayTimeline.mqh:80` | Warmup 'bars' are calendar minutes: a Monday-morning start seeds almost no warmup and the HTF chart opens empty |
| `core-sync-2` | MEDIUM | `SSR_TickSynthesizer.mqh:54` | Spread statistics count synthesis calls, not bars: the bar containing the clock is re-synthesised every pump so BarsWithRecordedSpread/BarsWithFixedSpread inflate by ~pumps-per-bar |
| `core-sync-3` | LOW | `SSR_IDataSource.mqh:160` | Generic CSSRBarProvider::NextBarOpen reads through the guarded ReadBars: it is useless inside a gap and raises up to four 'future access' violations per call |
| `core-sync-4` | LOW | `SSR_Metrics.mqh:108` | CSSRMetrics accumulates the controller's cumulative bar counter as if it were per-pump, so m_bars / SSRPerfSnapshot.bars grow quadratically |
| `core-engine-9` | LOW | `SSR_ReplayController.mqh:1035` | RecordPump is handed the cumulative bar_count as the per-pump bar figure, so CSSRMetrics.m_bars grows quadratically |
| `core-engine-8` | LOW | `SSR_ReplayController.mqh:1630` | RestoreSnapshot overwrites live settings (fidelity, speed, status, last_error) with the checkpoint's copy, desynchronising m_state from the policy object |
| `core-engine-7` | LOW | `SSR_ReplayController.mqh:1637` | RestoreSnapshot re-seats the cursor only when the sink cut strictly before the checkpoint; a checkpoint on an M1 open loses that bar's open tick |
| `core-engine-11` | IMPROVEMENT | `SSR_ReplayController.mqh:1707` | Improvements: stale cursor comment in SaveInto, dead SSR_BAR_READ_CEILING, bulk threshold off by 1 ms for PgDn, degraded FULL_TICK skips the bulk rule |
| `core-sync-6` | IMPROVEMENT | `SSR_SnapshotStore.mqh:140` | SnapshotStore::DropFrom leaves holes in the ring without adjusting m_count/m_head, so Count() over-reports and the next checkpoints overwrite the oldest survivors instead of refilling the holes |

#### Data layer - Include/SSReplay/Data (6)

| id | sev | line | defect |
|---|---|---|---|
| `data-1` | HIGH | `SSR_Mt5Providers.mqh:136` | has_ticks is probed over the last 24 hours of history but then selects FULL_TICK fidelity for a replay window that may be years earlier — the replay emits nothing, the clock runs to the end, and nothing reports it |
| `data-4` | MEDIUM | `SSR_HistoryCatalog.mqh:150` | warmup_bars is used both as a count of M1 bars and as a span of wall-clock minutes; on any instrument that does not quote every minute this produces false "not enough history" refusals and silently short warmup context |
| `data-9` | LOW | `SSR_Calendar.mqh:59` | SSR_NEWS_ALL ("Everything the calendar has") floors importance at LOW, silently excluding CALENDAR_IMPORTANCE_NONE events such as bank holidays |
| `data-7` | LOW | `SSR_Mt5Providers.mqh:125` | Discover() discards the last COMPLETE M1 bar whenever the market is closed, shortening every available range by one minute |
| `data-3` | LOW | `SSR_RandomPicker.mqh:149` | CSSRRandomPicker draws candidate symbols WITH REPLACEMENT, so a symbol that has enough history can be skipped entirely and the pick reported as impossible |
| `data-11` | IMPROVEMENT | `SSR_Mt5DataSource.mqh:146` | Every data-quality number this subsystem measures is computed on the hot path and then discarded; the only route to a human is a ToString() with no caller |

#### MT5 bridge - Include/SSReplay/Mt5 (4)

| id | sev | line | defect |
|---|---|---|---|
| `mt5-symbol-1` | HIGH | `SSR_CustomSymbolSink.mqh:265` | Warmup repair after a jump is silently skipped whenever the seed was reused from the cache |
| `mt5-symbol-3` | MEDIUM | `SSR_CustomSymbolManager.mqh:338` | Create()'s leftover-adopt fallback uses the SYMBOL_DIGITS>0 existence test that Adopt() documents as wrong for whole-point instruments |
| `mt5-symbol-8` | LOW | `SSR_CustomSymbolManager.mqh:557` | Destroy() reports SSR_OK and marks the symbol gone even when CustomSymbolDelete fails |
| `mt5-symbol-7` | LOW | `SSR_SeedCache.mqh:176` | Seed-cache version guard compares against a constant that has never changed, so it never rejects a manifest |

#### Chart layer - Include/SSReplay/Chart (10)

| id | sev | line | defect |
|---|---|---|---|
| `chart-4` | MEDIUM | `SSR_BlindMode.mqh:152` | Blind mode's record of the user's original chart settings does not survive a reinit, and the next Apply saves the blinded state as the original |
| `chart-3` | MEDIUM | `SSR_BlindMode.mqh:203` | The blind-mode reveal is undone within ~200ms: RestoreAll leaves the policy on and the host re-applies on IsOn() |
| `chart-5` | MEDIUM | `SSR_BlindMode.mqh:243` | Blind FULL claims the price level is hidden while the entry-line label and the panel's deal buttons print the absolute price |
| `chart-2` | MEDIUM | `SSR_ChartManager.mqh:574` | Secondary-symbol charts never get Redraw(): the explicit view-snap and ChartRedraw exist only for the primary stream |
| `chart-6` | LOW | `SSR_ChartManager.mqh:170` | Bookmark vertical lines are never deleted and survive on the user's own chart after the session |
| `chart-17` | LOW | `SSR_ChartManager.mqh:176` | MarkTime puts the registry index in the object name, so bookmarks duplicate after a chart closes |
| `chart-14` | LOW | `SSR_ChartManager.mqh:234` | OpenLayout counts each chart twice against SSR_MAX_CHARTS |
| `chart-10` | LOW | `SSR_ChartManager.mqh:464` | A detached chart has no user-visible surface: the observer is never wired and charts_detached is never rendered |
| `chart-7` | LOW | `SSR_LeakGuard.mqh:93` | LeakGuard::Advice is written far longer than the 49 characters its only consumer can display, so the actionable half never reaches the user |
| `chart-12` | LOW | `SSR_TradeLines.mqh:134` | Every word the Chart layer draws or hands to the panel is a hardcoded English literal, outside audit A19's reach |

#### Trading and risk - Include/SSReplay/Trading (21)

| id | sev | line | defect |
|---|---|---|---|
| `trading-exec-1` | CRITICAL | `SSR_TradingEngine.mqh:640` | Rewind drops positions placed after the cut without reversing their P/L, commission and swap from the balance |
| `trading-analytics-1` | HIGH | `SSR_PropEvaluation.mqh:443` | Resuming a saved session voids a running prop evaluation on startup |
| `trading-exec-2` | HIGH | `SSR_TradingEngine.mqh:263` | SL/TP changes, trailing-stop movement, break-even and MAE/MFE are not versioned, so they survive a rewind |
| `trading-analytics-4` | MEDIUM | `SSR_Journal.mqh:82` | Class report and CSV consumers see a different per-trade result than the statement (raw profit vs net) |
| `trading-analytics-12` | MEDIUM | `SSR_PropEvaluation.mqh:358` | A jump forward never runs the evaluation; a jump that completes the window leaves it IN PROGRESS |
| `trading-analytics-2` | MEDIUM | `SSR_PropEvaluation.mqh:366` | Prop evaluation state is not persisted; a resumed or reset run re-bases every rule on current equity |
| `trading-analytics-3` | MEDIUM | `SSR_Statistics.mqh:703` | Closed-only drawdown walks trades in open order, not close order |
| `trading-exec-5` | MEDIUM | `SSR_TradingEngine.mqh:164` | Ambiguity test uses the whole bar range, so a target hit after a mid-bar entry is booked as a stop loss when the bar's earlier low was below the stop |
| `trading-exec-6` | MEDIUM | `SSR_TradingEngine.mqh:741` | No margin check on entry when margin is modelled: an unaffordable order is accepted, charged, then stopped out on the next tick |
| `trading-exec-8` | MEDIUM | `SSR_TradingEngine.mqh:920` | BreakEven/Modify accept a stop on the wrong side of the market and the engine then closes the trade instead of rejecting the change |
| `trading-analytics-6` | LOW | `SSR_Journal.mqh:304` | Undefined profit factor is printed as 0.00 in the KPI grid, by-setup table, CSV header and Summary |
| `trading-analytics-8` | LOW | `SSR_Journal.mqh:1142` | Average MAE/MFE printed at two decimals in price units and compared with money |
| `trading-analytics-5` | LOW | `SSR_PropEvaluation.mqh:383` | A day on which only a pending order was placed (even if cancelled) counts as a trading day |
| `trading-analytics-9` | LOW | `SSR_Statistics.mqh:272` | Equity ring drops its oldest half, so the live max drawdown can shrink and the peak be lost |
| `trading-analytics-10` | LOW | `SSR_Statistics.mqh:455` | R multiple excludes commission while every money measure includes it |
| `trading-analytics-7` | LOW | `SSR_Statistics.mqh:497` | Revenge detection compares only with the previously OPENED trade, not the most recent loss |
| `trading-exec-10` | LOW | `SSR_TradeTypes.mqh:120` | SSRPendingFor classifies a long entry inside the spread as BUY_STOP, which fills on the next tick like a market order |
| `trading-exec-9` | LOW | `SSR_TradingEngine.mqh:345` | Limit-order entries receive adverse slippage and can fill worse than their limit price |
| `trading-exec-12` | LOW | `SSR_TradingEngine.mqh:714` | Open() accepts any positive volume from the external path without step/min/max validation |
| `trading-exec-11` | LOW | `SSR_TradingEngine.mqh:999` | AmbiguousPercent divides ambiguous fills of still-open positions by the closed count |
| `trading-exec-13` | IMPROVEMENT | `SSR_AutoPause.mqh:124` | Auto-pause reasons are English literals with a hard-coded 5-digit price format |

#### UI layer - Include/SSReplay/Ui (41)

| id | sev | line | defect |
|---|---|---|---|
| `ui-panel-3` | HIGH | `SSR_Panel.mqh:682` | HideBody(false) at line 729 undoes HideSheetArea(true) at line 682 inside the same Render(), so compact mode leaves the tab rail and action strip on the candles |
| `ui-dialogs-1` | HIGH | `SSR_SetupPanel.mqh:300` | ReadAll() wipes session_name and extra_tfs whenever it runs on a step that has no edit boxes |
| `ui-port-session-9` | MEDIUM | `SSR_GroupPort.mqh:372` | Pending orders occupy wire rows that no total on the wire accounts for |
| `ui-panel-2` | MEDIUM | `SSR_Panel.mqh:729` | HideBody(false) runs every frame and Forget()s the property cache for ~44 sized objects, which are then rewritten in full |
| `ui-panel-10` | MEDIUM | `SSR_Panel.mqh:804` | In compact mode the fill toast is drawn on top of the speed trackbar and blocks it for four seconds |
| `ui-panel-1` | MEDIUM | `SSR_Panel.mqh:1270` | DrawSheet deletes and recreates the entire visible sheet on every repaint, defeating both caches |
| `ui-panel-5` | MEDIUM | `SSR_Panel.mqh:1432` | Two cache slots (12 and 17) write the same object 'setuprow' at the same coordinates, so order_why is visible for one frame only |
| `ui-panel-7` | MEDIUM | `SSR_Panel.mqh:1576` | Position-row note column collides with the P/L column in the rail layout: 9 px of room for a 9-character note |
| `ui-panel-6` | MEDIUM | `SSR_Panel.mqh:2033` | Status strip draws the fidelity readout at x+330 in a 310 px panel - permanently outside the frame, on the candles |
| `ui-dialogs-7` | MEDIUM | `SSR_RangeDialog.mqh:139` | The range dialog enables START for any date the broker can serve, but its only caller can only jump inside the already-loaded window |
| `ui-dialogs-5` | MEDIUM | `SSR_RangeDialog.mqh:233` | The range dialog draws an unbounded validator message into one label, so the 'start too early' refusal loses the date it is about |
| `ui-dialogs-3` | MEDIUM | `SSR_RangeDialog.mqh:268` | Recompute() erases the two messages the range dialog sets just before calling it, so a bad date and Load-more's result are never shown |
| `ui-dialogs-4` | MEDIUM | `SSR_Review.mqh:205` | Two review-card observation sentences exceed MetaTrader's 63-character draw limit for every possible value |
| `ui-dialogs-2` | MEDIUM | `SSR_SetupPanel.mqh:1061` | An open dropdown survives a step change and is redrawn on top of the START button |
| `ui-dialogs-14` | LOW | `SSR_FirstRun.mqh:89` | CSSRFirstRun::Show reports success without checking the card fits, so the once-ever card is consumed unseen on a short chart |
| `ui-port-session-12` | LOW | `SSR_GroupPort.mqh:937` | The session list re-reads and fully parses every file on every dialog render |
| `ui-port-session-10` | LOW | `SSR_GroupPort.mqh:949` | A save made from the panel records settings that are not the session's |
| `ui-plumbing-1` | LOW | `SSR_KeyCard.mqh:92` | The key card - the product's primary discovery surface - is the one user-facing screen that is never translated |
| `ui-plumbing-15` | LOW | `SSR_Keys.mqh:71` | The palette's only live entry point, Ctrl+K, is not in the single key table, so the generated key card cannot show it and the code comments say it does not exist |
| `ui-plumbing-3` | LOW | `SSR_Keys.mqh:271` | SSRKeyHint() is a third hand-written key list, also naming R as reset, and the test that guards it cannot see the error |
| `ui-panel-12` | LOW | `SSR_Panel.mqh:776` | The key card is torn down and rebuilt from scratch by the panel ten times a second while it is up |
| `ui-panel-13` | LOW | `SSR_Panel.mqh:887` | Caption chip row overruns the collapse button by 6 px when fidelity is degraded and both BLIND and PROP chips are shown |
| `ui-panel-8` | LOW | `SSR_Panel.mqh:1091` | Speed 'meaning' text at MAX is 21 unclipped characters drawn into a 56 px reserve at the panel's right edge |
| `ui-panel-4` | LOW | `SSR_Panel.mqh:2044` | HideSheetArea's id list stops at tab3, so the fifth (Prop) tab is never hidden |
| `ui-panel-14` | LOW | `SSR_Panel.mqh:2253` | The reset confirmation - the one destructive question on the panel - is a hardcoded English literal |
| `ui-dialogs-11` | LOW | `SSR_SessionDialog.mqh:288` | The session dialog's DELETE button is enabled, looks live, and deletes nothing |
| `ui-dialogs-12` | LOW | `SSR_SessionDialog.mqh:318` | RequestSave and the whole overwrite-confirm mode are unreachable, and would discard their own outcome message if reached |
| `ui-dialogs-13` | LOW | `SSR_SetupPanel.mqh:548` | SetStartText draws the orange-line caption at the START step's coordinates while another step is on screen |
| `ui-dialogs-15` | LOW | `SSR_SetupPanel.mqh:611` | MenuClear only sweeps 32 menu items while presets.ini is unbounded, so a longer preset file orphans buttons on the chart |
| `ui-dialogs-10` | LOW | `SSR_SetupPanel.mqh:712` | The quick step builds the session path itself and skips the session manager's sanitiser, so 'Continue' disappears for names containing a slash or colon |
| `ui-dialogs-6` | LOW | `SSR_SetupPanel.mqh:955` | The setup panel's drag handler can never fire: nothing enables CHART_EVENT_MOUSE_MOVE on the chart it lives on |
| `ui-dialogs-9` | LOW | `SSR_SetupPanel.mqh:1194` | ReadAll clamps balance, risk, spread and speed but not the three prop numbers, so a typed 0 silently deletes a prop rule |
| `ui-plumbing-14` | LOW | `SSR_Strings.mqh:393` | H, B and X are printed as clickable row captions on the Positions sheet while the same three letters are global hotkeys for unrelated commands |
| `ui-plumbing-2` | LOW | `SSR_Strings.mqh:500` | The panel's on-screen keyboard hint says "R reset"; R is bound to the SL/TP lines and reset is bound to 0 |
| `ui-plumbing-6` | LOW | `SSR_Widgets.mqh:103` | The property cache has no tombstones: Forget() can silently clear nothing and Keep() then writes a duplicate, leaking slots until the cache stops working |
| `ui-plumbing-5` | IMPROVEMENT | `SSR_Layout.mqh:67` | SSR_Layout.mqh is dead in production: nothing outside the QA smoke test positions anything through it, so the RTL plan it exists to enable has no backing |
| `ui-port-session-16` | IMPROVEMENT | `SSR_ReplayPort.mqh:54` | data_mode is on the wire, set by nobody and read by nobody |
| `ui-dialogs-16` | IMPROVEMENT | `SSR_ReviewCard.mqh:162` | Review-card measure rows are OBJ_BUTTONs whose latch nothing consumes, so a clicked statistic stays visually pressed |
| `ui-plumbing-11` | IMPROVEMENT | `SSR_Theme.mqh:437` | The metrics comment a later designer must read to size a new row is stale in four of its six numbers |
| `ui-plumbing-8` | IMPROVEMENT | `SSR_Widgets.mqh:232` | Label()'s fingerprint identifies the font by the LENGTH of its name, so a font change to an equal-length face is skipped |
| `ui-plumbing-9` | IMPROVEMENT | `SSR_Widgets.mqh:492` | SSR_C_THUMB_EDGE and SSR_C_TICK are declared in all three palettes and drawn by nothing; the slider outlines its thumb with SSR_C_TRACK_EDGE instead |

#### Session - Include/SSReplay/Session (4)

| id | sev | line | defect |
|---|---|---|---|
| `ui-port-session-3` | HIGH | `SSR_SessionManager.mqh:350` | Restore never checks that the streams reached the saved instant, and cannot rewind to it |
| `ui-port-session-8` | MEDIUM | `SSR_SessionManager.mqh:89` | Resume warnings are newline-joined and end up in a single 63-character label |
| `ui-port-session-11` | LOW | `SSR_SessionManager.mqh:142` | List() strips the extension by first match, so a name containing ".ssr" is listed wrong |
| `ui-port-session-7` | LOW | `SSR_SessionManager.mqh:238` | Peek's session summary is roughly twice what its only consumer can draw |

#### Strategy - Include/SSReplay/Strategy (7)

| id | sev | line | defect |
|---|---|---|---|
| `strategy-integration-report-1` | HIGH | `SSR_MarketView.mqh:173` | In FULL_TICK fidelity the market view is never fed bars, so a strategy reads a snapshot frozen at the first pump |
| `strategy-integration-report-2` | MEDIUM | `SSR_StrategyHost.mqh:184` | OnBar is detected from the last tick of a published batch, so its firing point and the resulting fill price are functions of wall-clock pump boundaries |
| `strategy-integration-report-3` | LOW | `SSR_IStrategy.mqh:266` | OnTick fires once per published batch, not once per tick, so the documented intrabar-management use is unreachable and TickCalls() under-reports |
| `strategy-integration-report-13` | LOW | `SSR_MarketView.mqh:136` | Group() returns shift 0 with a wrong open and an un-aggregated spread when the group began before the buffer did |
| `strategy-integration-report-6` | LOW | `SSR_MarketView.mqh:398` | Prime() and OnRewind() trim on bar-open granularity, so the newest retained bar can hold prices from after the clock |
| `strategy-integration-report-5` | LOW | `SSR_MarketView.mqh:427` | CSSRMarketView::IsSynthetic() can never return false, so the honesty instrument it exists to be is dead |
| `strategy-integration-report-4` | LOW | `SSR_StrategyHost.mqh:141` | The per-strategy RNG stream is seeded once at registration and is never re-seeded or rewound, so a strategy that uses it is not reproducible across a step-back |

#### Report - Include/SSReplay/Report (3)

| id | sev | line | defect |
|---|---|---|---|
| `strategy-integration-report-8` | MEDIUM | `SSR_ClassReport.mqh:439` | The class report declares UTF-8 and is written with FILE_ANSI, so non-ASCII student, symbol and session names come out as mojibake |
| `strategy-integration-report-9` | MEDIUM | `SSR_ClassReport.mqh:493` | The class KPI row, the ranking sort and the bar scale all include students who ran a different session, which is the comparison the file says it refuses to make |
| `strategy-integration-report-10` | LOW | `SSR_ClassReport.mqh:279` | A pre-v76 export keeps parsed=true, so its recorded reason is never rendered and the caveat points the coach at marks that are never drawn |

#### Integration - Include/SSReplay/Integration (3)

| id | sev | line | defect |
|---|---|---|---|
| `strategy-integration-report-12` | LOW | `SSR_Publisher.mqh:121` | SetSlot is unbounded while Discover only scans 1..SSR_MAX_SLOTS, so extra-stream publishers can be invisible to clients or collide with a second session |
| `strategy-integration-report-7` | LOW | `SSR_Publisher.mqh:229` | The publisher rejects a command whose sequence equals the last one it executed, so a restarted client has one command silently dropped and reported as a timeout |
| `strategy-integration-report-15` | IMPROVEMENT | `SSR_Publisher.mqh:283` | SSR_CMD_SPEED reports success for a value the clock silently rewrote |

#### Spike kit - Include/SSReplay/Spike (3)

| id | sev | line | defect |
|---|---|---|---|
| `spikes-audits-1` | HIGH | `SSR_SpikeKit.mqh:579` | SSR_BarToTicks never emits a tick at the bar's high or low unless (n-1) is divisible by 3 |
| `spikes-audits-3` | MEDIUM | `SSR_SpikeKit.mqh:314` | No spike forces SYMBOL_CHART_MODE_BID or sets TICK_FLAG_LAST, so B1 reports the transport broken on an index or futures origin |
| `spikes-audits-25` | LOW | `SSR_SpikeKit.mqh:97` | The spike CSVs are opened without FILE_SHARE_WRITE while three spikes require a concurrent probe writing the same file |

#### Common - Include/SSReplay/Common (2)

| id | sev | line | defect |
|---|---|---|---|
| `ui-port-session-2` | MEDIUM | `SSR_SessionFile.mqh:138` | Saving truncates the previous good session before writing the new one |
| `chart-13` | LOW | `SSR_FlightRecorder.mqh:256` | The flight recorder truncates chart_id to 32 bits, corrupting the column that identifies which chart a fault happened on |

#### Test harness - Scripts/SSReplay/Tests (29)

| id | sev | line | defect |
|---|---|---|---|
| `tests-b-1` | MEDIUM | `SSR_T15_Ux.mq5:402` | T15.7 asserts R still means RESET; the key table maps R to LINES_TOGGLE, so the assertion is false at runtime |
| `tests-b-2` | MEDIUM | `SSR_T15_Ux.mq5:460` | T15.9's premise is false: SetCorner does not move the panel, so both of its assertions fail |
| `tests-a-4` | MEDIUM | `SSR_T5_Ui.mq5:89` | T5.1 asserts R maps to reset; R has been rebound to the SL/TP lines |
| `tests-a-2` | MEDIUM | `SSR_T5_Ui.mq5:109` | T5.2 asserts an 8-stop speed ladder against a 20-stop ladder: four assertions fail |
| `tests-a-3` | MEDIUM | `SSR_T5_Ui.mq5:174` | T5.5's three speed-clamp assertions fail against the 20-stop ladder |
| `tests-a-1` | MEDIUM | `SSR_T5_Ui.mq5:208` | T5.6's click assertion cannot pass: the panel does not handle CHARTEVENT_OBJECT_CLICK at all |
| `tests-b-3` | LOW | `SSR_T13_Strategy.mq5:539` | T13.8 claims seed reproducibility and asserts three tautologies instead |
| `tests-b-4` | LOW | `SSR_T14_Integration.mq5:355` | T14.8's "the command set is exactly the documented ones" is unfalsifiable by construction |
| `tests-b-5` | LOW | `SSR_T15_Ux.mq5:421` | T15.8 never establishes its precondition, so all four keyboard-takeover assertions pass on a chart where quick navigation is already off |
| `tests-a-8` | LOW | `SSR_T1_CoreEngine.mq5:355` | "warmup survived the reset" is measured with a write counter that a wipe cannot decrement |
| `tests-a-9` | LOW | `SSR_T2_DataEngine.mq5:297` | T2.6's stated dangling-guard test never lets the guard die |
| `tests-a-11` | LOW | `SSR_T2_DataEngine.mq5:406` | T2.8 closes with an unconditional `Check(..., true)` |
| `tests-a-7` | LOW | `SSR_T3_CustomSymbol.mq5:441` | T3.8 "teardown leaves nothing behind" runs against a symbol T3.7 already deleted |
| `tests-a-5` | LOW | `SSR_T5_Ui.mq5:221` | T5.6's "foreign objects ignored" is now a vacuous pass - every object click is ignored |
| `tests-a-6` | LOW | `SSR_T5_Ui.mq5:318` | T5.9 (second) asserts on the test double instead of the panel for JumpTo and Restart |
| `tests-a-14` | LOW | `SSR_T6_History.mq5:300` | T6.8's closing assertion is a tautology given the two above it |
| `tests-a-12` | LOW | `SSR_T7_Performance.mq5:66` | T7.1 asserts arithmetic over its own literals and reads no production code |
| `tests-a-17` | LOW | `SSR_T8_Navigation.mq5:148` | T8.3's headline assertion admits any tick count from 1 upward |
| `tests-a-13` | LOW | `SSR_T8_Navigation.mq5:223` | T8.5's clamp and no-op assertions read only a return value, and one of them is a hardcoded true |
| `tests-b-11` | LOW | `SSR_T9_Trading.mq5:79` | T9.1's rounding assertions are one-sided and pass when LotForRisk refuses the trade outright |
| `tests-b-6` | LOW | `SSR_T9_Trading.mq5:112` | Every Risk().Configure in T9 is discarded by Load; T9's sections silently run on the unknown-symbol fallback specs |
| `tests-b-8` | LOW | `SSR_T9_Trading.mq5:124` | T9.2's "session start reached the account" holds whether or not OnSessionStart ever arrives |
| `tests-b-7` | LOW | `SSR_T9_Trading.mq5:368` | T9.7's checkpoint-path claim is not asserted; a silent fall back to the plain seek would keep the section green |
| `tests-b-12` | LOW | `SSR_T9_Trading.mq5:433` | T9.8's "a round trip at a flat price loses money" is satisfied by losing nothing |
| `tests-b-16` | IMPROVEMENT | `SSR_T10_Statistics.mq5:533` | T10.8 leaves its exported CSV in the trader's journal folder |
| `tests-b-9` | IMPROVEMENT | `SSR_T12_Session.mq5:445` | T12.5's guard against storing derived statistics can never fail - no code writes a section named "statistics" |
| `tests-b-15` | IMPROVEMENT | `SSR_T13_Strategy.mq5:459` | T13.6's unsupported-timeframe assertion passes only because Add checks the timeframe before the duplicate name |
| `tests-b-14` | IMPROVEMENT | `SSR_T15_Ux.mq5:336` | T15.5's "cannot trade" assertion is a tautology: ReadState Init()s the struct before refusing |
| `tests-a-16` | IMPROVEMENT | `SSR_T5_Ui.mq5:289` | Two different sections in T5 are both labelled T5.9 |

#### QA scripts - Scripts/SSReplay/QA (11)

| id | sev | line | defect |
|---|---|---|---|
| `qa-smoke-2` | MEDIUM | `SSR_QA_Preflight.mq5:397` | Preflight's only tick check counts acceptance and never asks whether a bar was built - the exact signal the project measured as meaningless |
| `qa-smoke-1` | MEDIUM | `SSR_QA_Smoke.mq5:396` | The smoke harness aborts the entire run on an unprimed M1 series, and the priming call is the very next line |
| `qa-smoke-7` | LOW | `SSR_QA_Smoke.mq5:724` | Stage 7 increments the pass count with no condition tested |
| `qa-smoke-5` | LOW | `SSR_QA_Smoke.mq5:1144` | The blind-mode restore check cannot see a chart left with no price scale, and goes vacuous entirely when the template has OHLC off |
| `qa-smoke-13` | LOW | `SSR_QA_Smoke.mq5:1783` | Stage 18's compact assertion checks tab0 and tabline only, and can never reach the fifth tab that the panel's hide list omits |
| `qa-smoke-4` | LOW | `SSR_QA_Smoke.mq5:2316` | Stage 22d reports two PASSes for calendar lines that were never drawn |
| `qa-smoke-9` | LOW | `SSR_QA_Smoke.mq5:4194` | Three stages drive real panels outside the panel.ini stash window, so a smoke run still eats the user's saved tab |
| `qa-smoke-10` | LOW | `SSR_Z_Cleanup.mq5:44` | SSR_Z_Cleanup closes the chart of any broker symbol whose name starts with SSR |
| `qa-smoke-12` | LOW | `SSR_Z_Gaps.mq5:52` | SSR_Z_Gaps can report more than 100% of minutes present, and InpMinRun=0 turns every bar into a hole |
| `qa-smoke-15` | IMPROVEMENT | `SSR_QA_Smoke.mq5:1073` | Stage 12's closed-trade prices are in whole units, the mistake the comment six lines above says was fixed |
| `qa-smoke-8` | IMPROVEMENT | `SSR_QA_Smoke.mq5:1667` | The compact-mode assertion in stage 18 re-implements the production expression, so it cannot fail |

#### Spike and probe programs (21)

| id | sev | line | defect |
|---|---|---|---|
| `spikes-audits-4` | MEDIUM | `SSR_A3_FutureIsolation.mq5:48` | A3 has no positive control: on M5..D1 an unbuilt series gives the same answer as 'no future data' |
| `spikes-audits-5` | MEDIUM | `SSR_A3_FutureIsolation.mq5:141` | A3's avg_rebuild_time times the SERIES_SYNCHRONIZED flag, then declares it the Reset budget |
| `spikes-audits-2` | MEDIUM | `SSR_B1_TicksAddBroadcast.mq5:139` | B1's wick_expanded_to_extremes verdict fails deterministically no matter how MetaTrader behaves |
| `spikes-audits-12` | MEDIUM | `SSR_B3_SessionBehavior.mq5:132` | B3 prints its PASS criterion instead of asserting it, so the session-behaviour spike always reports SPIKE PASS |
| `spikes-audits-10` | MEDIUM | `SSR_D1_SeedPerformance.mq5:90` | D1 turns a readable-wait timeout into a zero wait and publishes the flattering write-only rate as 'the number the user waits for' |
| `spikes-audits-7` | MEDIUM | `SSR_D2_TimeframeSwitch.mq5:68` | D2's 'live' pass re-sends identical tick timestamps, so 69 of its 70 injections are refused and live == idle |
| `spikes-audits-6` | MEDIUM | `SSR_D2_TimeframeSwitch.mq5:81` | D2 measures timeframe-switch cost by polling SERIES_SYNCHRONIZED, so its under-1s gate fails on a flag |
| `spikes-audits-23` | MEDIUM | `SSR_D3_SustainedRun.mq5:216` | D3's throughput_stable gate still uses the minute-10 baseline that the same file documents as hiding the finding |
| `spikes-audits-8` | MEDIUM | `SSR_D4_RewindCost.mq5:97` | D4's 1-bar tail-delete timing skips the series rebuild on 16 of 20 trials, inflating the rewind ratio |
| `spikes-audits-9` | MEDIUM | `SSR_D4_RewindCost.mq5:106` | D4 loses its chart at the strategy-2 restore, so the three rewind strategies are not measured under the same conditions |
| `spikes-audits-21` | MEDIUM | `SSR_C2_ServicePersistence.mq5:58` | C2's restart detector false-fails on every run after the first, and the event it hunts destroys its own evidence file |
| `spikes-audits-30` | LOW | `SSR_Probe_UIJitter.mq5:66` | The UIJitter probe divides by its window-size input with no validation |
| `spikes-audits-17` | LOW | `SSR_A1_SymbolLifecycle.mq5:164` | A1's max_symbol_name_length attributes any CustomSymbolCreate refusal to name length and leaves residue behind on failure |
| `spikes-audits-18` | LOW | `SSR_B4_BrokerDataAudit.mq5:41` | B4 turns a missing series into '20,700 days of history' and inverts its Load-More-History conclusion |
| `spikes-audits-19` | LOW | `SSR_B4_BrokerDataAudit.mq5:72` | B4's tick-depth walk samples the same hour of the day at every depth, so a symbol closed in that hour reports zero tick history |
| `spikes-audits-20` | LOW | `SSR_B4_BrokerDataAudit.mq5:93` | B4 reports the number of ticks in a week as a call ceiling and a page size |
| `spikes-audits-14` | LOW | `SSR_C3_IpcChannel.mq5:82` | C3's torn-read test runs the writer and the reader sequentially in one thread, so 'race-free' cannot fail |
| `spikes-audits-15` | LOW | `SSR_C4_ReplayClock.mq5:120` | C4's timecurrent_is_unsafe verdict is a tautology, and C4 never checks that its ticks were accepted |
| `spikes-audits-11` | LOW | `SSR_D1_SeedPerformance.mq5:101` | D1 computes seed throughput from bars requested, not bars accepted, and never asserts they are equal |
| `spikes-audits-13` | LOW | `SSR_D1_SeedPerformance.mq5:161` | D1 also prints its PASS gate rather than asserting it |
| `spikes-audits-22` | LOW | `SSR_C2_ServicePersistence.mq5:121` | C2's documented manual procedure stops the service 60 seconds before its own run-length gate is satisfied |

#### Tooling - tools/ (4)

| id | sev | line | defect |
|---|---|---|---|
| `spikes-audits-29` | LOW | `ssr_audit.py:425` | Audit A9 cannot see a duplicated pointer-returning method, the exact shape DECL_METHOD was fixed for |
| `spikes-audits-28` | LOW | `ssr_audit.py:894` | Audit A14 omits four of the eight text-drawing widget helpers that A19 already knows about |
| `spikes-audits-26` | LOW | `ssr_audit.py:1429` | Audit A19's translation-length check never runs: the language directory path contains MQL5 twice |
| `spikes-audits-27` | LOW | `ssr_audit.py:1518` | Audit A20's regex matches only one exact function shape, leaving two drawing Ui surfaces unchecked |

### C.3 CRITICAL (2)

Two defects reach the bar of "loses money the user believes he has, or leaves the product unusable, on the shipped defaults". One is in the host's init handshake, one in the trading engine's rewind. [CONFIRMED FROM CODE]

#### C.3.1 Host expert - `MQL5/Experts/SSReplay/SSReplayStandalone.mq5`

##### `host-expert-1` — CRITICAL — OnInit's object sweep deletes the handover stash 63 lines before it reads it

**File:** `MQL5/Experts/SSReplay/SSReplayStandalone.mq5:1806` · **Category:** session-resume

```mql5
   SSRPurgeChart(0, SSR_PICK_LINE);                 // line 1806, 2nd statement of OnInit
...
   string stashed = ReadStashedOrigin();            // line 1869
...
   if(ObjectFind(0, SSR_PICK_STASH) >= 0)           // line 1884
```

**Failure scenario** [CONFIRMED FROM CODE] — Shipped defaults, `InpOneChart=true`. Pass 1 stashes the origin symbol in the chart object `SSR_ORIGIN_HANDOFF` and hands chart 0 to the replay symbol. Pass 2's `OnInit` sweeps that object away at 1806, then reads it at 1869: `stashed==""`, so `origin==""` at 1903, the `on_replay && origin==""` branch fires at 1911, and `FailInit()` returns `INIT_FAILED`. `FailInit`'s chart-restore branch is gated on `if(g_on_replay_chart && g_origin != "")` (825), and `g_origin` is `""`, so it restores nothing. The user is left staring at a custom replay symbol with no expert attached and no automatic way back — the precise outcome the `FailInit` comment at 810-821 exists to prevent. The picked start (`SSR_PICK_HANDOFF`) and the failed-pass poison (`"!"+origin`) die in the same sweep, so the recovery path and the picked window cannot survive the handover either, and the `"!"`-poison branch at 1894-1900 is dead code.

**Why** [CONFIRMED FROM CODE] — `SSRPurgeChart` (`Ui/SSR_Widgets.mqh:676-694`) enumerates `ObjectsTotal(chart,-1,-1)` and deletes every name where `StringFind(nm,"SSR")==0` unless it equals the single `keep` argument, which here is `SSR_PICK_LINE` (`Ui/SSR_Theme.mqh:508`). Both handover objects match that prefix — `SSR_HANDOFF "SSR_ORIGIN_HANDOFF"` (536), `SSR_PICK_STASH "SSR_PICK_HANDOFF"` (556) — and both are created on chart 0 (540, 2536), the same chart the sweep runs on. `git log -S` dates the move of the sweep into `OnInit` to commit `f3f7ddb` (v102), after the stash mechanism it breaks (v55): a regression, not an original design.

**Verifiers** — Delete and read are in one pass of one function, so no assumption about whether chart objects survive `ChartSetSymbolPeriod` can rescue it; all three refuters failed to find a guard.

**Fix** [RECOMMENDATION] — Read before you sweep. Hoist the three reads (`ReadStashedOrigin()`, the `SSR_PICK_STASH` read at 1884, the poison test) above line 1806 into locals, then purge; or give the sweep a keep-list instead of one name — change `SSRPurgeChart(const long chart, const string keep)` to take a second and third optional keep name, and call `SSRPurgeChart(0, SSR_PICK_LINE, SSR_HANDOFF, SSR_PICK_STASH)`, deleting the two handover objects explicitly once consumed. The keep-list variant is preferable because it also protects any future handover object by construction. Add a one-line assertion in the QA smoke (stage 1) that `ObjectFind(0, SSR_HANDOFF) >= 0` immediately after a simulated pass-1 stash plus a purge, so the regression cannot return unnoticed.

#### C.3.2 Trading and risk - `MQL5/Include/SSReplay/Trading/SSR_TradingEngine.mqh`

##### `trading-exec-1` — CRITICAL — rewind drops post-cut positions without reversing their money

**File:** `MQL5/Include/SSReplay/Trading/SSR_TradingEngine.mqh:640` · **Category:** event-handling

```mql5
long placed = (m_pos[i].request_msc > 0 ? m_pos[i].request_msc
                                        : m_pos[i].open_msc);
if(placed > msc)
   continue;                                   // line 643

//--- every exit taken in the deleted future, newest first
UnwindLegsAfter(i, msc);                       // line 646 - never reached for those
```

**Failure scenario** [CONFIRMED FROM CODE] — A BUY opens 10:05 and closes 10:10 with realised +50 (or -30 on a stop), commission 7/lot charged at entry and at exit. The user steps back to 10:00 (`OnRewind(10:00)`) or presses Reset (`0` → `GroupPort.Reset` → `controller.Reset` → `PublishRewind(start_msc)`). The position vanishes from the log, but `m_balance` keeps the +50, the -14 commission and any accrued swap. After a Reset the account shows an empty trade log with the whole session's realised P/L still sitting in the balance. Equity, every statistic, the prop evaluation's daily-loss and target tests, and the next `LotForRisk` (sized off `Equity()`) are all computed on the corrupted figure. A later Save/Restore then prints the "balance replayed from the trades is X, but the file recorded Y" warning, because `RestoreFrom` is the only code that recomputes balance from the log.

**Why** [CONFIRMED FROM CODE] — The `continue` at 643 skips the position before the two reversal mechanisms: `UnwindLegsAfter` (263-291) at 646 and the un-fill refund branch (660-690). Money was moved at `Open()` 754 (`m_balance -= commission`), `CheckPendings` 356, `BookExit` 222 (`m_balance += realised - fee`) and `AccrueSwap` 427. The skipped position is never copied to `m_pos[keep]`, so the trailing `AccrueSwap()` restatement at 701 cannot refund its swap either. `grep m_balance` yields only 222, 273, 356, 427, 563, 579, 664, 754, 1167, 1221 — nothing outside `RestoreFrom` recomputes it. The Reset route is first-class: Panel 2241/2248 → `GroupPort.Reset` (425-436) → `CSSRReplayController::Reset` (1268-1293), which calls only `PublishRewind(cut)` at 1286 and never re-runs `OnSessionStart`, the sole place `m_balance = m_balance_initial` (579).

**Verifiers** — Both reversal paths sit after the `continue`, the Reset button reaches it end to end, and `T9.7` (340-361) asserts only that the ticket is gone, on an OPEN trade with commission 0, so the leak is invisible to the test.

**Fix** [RECOMMENDATION] — Reverse before dropping. Immediately before the `continue`, run the money back out:

```mql5
if(placed > msc)
  {
   UnwindLegsAfter(i, msc);                    // all legs are > msc by construction
   m_balance += m_pos[i].commission - m_pos[i].swap;
   continue;
  }
```

`UnwindLegsAfter` already reverses each leg's `realised - fee` and restores `prev_swap_locked`, so the only residue is the entry commission and the accrued swap. Then strengthen `T9.7`: open a trade, close it at a profit with a non-zero commission, rewind past the open, and assert `Balance() == balance_before_open` to the cent — the assertion the current test is one line away from making.

### C.4 HIGH (14)

Fourteen defects where the output is silently wrong, or a named feature does not do what its name says. Seven are in the two engines; the rest are split between data capability probing, the panel, the setup wizard and session restore. [CONFIRMED FROM CODE]

#### C.4.1 Core engine - `MQL5/Include/SSReplay/Core`

##### `core-sync-1` — HIGH — the idle gap-skip fires mid-bar and bulk-writes the unfinished bar past the observers

**File:** `MQL5/Include/SSReplay/Core/SSR_MasterClock.mqh:208` · **Category:** sl-tp-execution

```mql5
      else if(AnyPlaying() && ++m_idle_pumps >= 25)
        {
         m_idle_pumps = 0;
         long nb = NextBarAcross(m_master.now_msc);
         if(nb != SSR_INVALID_TIME && nb > m_master.now_msc + 2 * SSR_MSC_PER_MIN)
           { ... SeekAllTo(nb - 1); }
```

**Failure scenario** (verifiers' corrected version) [CONFIRMED FROM CODE] — 8 synthetic ticks/bar (default), any speed up to ~8x, 40 ms pumps, the clock inside bar B whose first tick has just been emitted, and at least two consecutive M1 bars missing immediately after B — the last bar of every index or futures CFD session, every weekend edge, any two-minute hole in thin forex. After 25 tickless pumps (1 s of wall time; the next synthetic tick is 8.57 s of bar time away) the skip fires and `SeekAllTo(nb-1)` runs `JumpForward` on every stream. Bar B is still **drawn correctly** on the replay chart — `SeedBars` writes it whole — but no `OnBarContext` and no `OnTicks` for bar B reach the trading or statistics engines. A stop or target inside B's range is never evaluated; the engine's next price is bar `nb`'s first tick, i.e. a gap price. At BAR fidelity the bar's only tick vanishes entirely, so the whole bar is invisible to the account. The printed "market closed from &lt;mid-bar time&gt;" message names an instant inside a bar that is still trading.

**Why** [CONFIRMED FROM CODE] — The threshold is measured from the mid-bar clock, not from the end of the current bar, while the comment at 202-204 assumes "the pause between two live ticks - never more than a minute of bar time - is left untouched". Synthetic stamps are `open + i*59999/(n-1)` (`SSR_TickSynthesizer.mqh:147`), so at 8 ticks/bar consecutive ticks are 8571 ms apart and 25 × `InpPumpMs`(40) = 1 s of idle is reached inside almost every minute. `NextBarAcross` → `CSSRMt5BarProvider::NextBarOpen` (`SSR_Mt5Providers.mqh:302-321`) returns the first **existing** open strictly after the clock, so `nb > now + 120000` holds exactly when two bars are missing. In `JumpForward`, `bar_lo = SSRBarOpenMsc(emitted+1)` is B's own open while `last_bar = nb - 60000` is greater, so `if(last_bar > bar_lo)` (1370) is true and B goes out through `SeedBars` (1383); `m_cursor.Advance(last_bar-1, 0, n)` (1390) steps past it. `JumpForward` (1333-1420) calls no `PublishBar`/`PublishTicks`/`OnClock` at all.

**Verifiers** — Every arithmetic link re-derived (tick spacing, pump count, `nb` filter, `bar_lo < last_bar`); the only correction is that the chart is fine and it is the observer stream that loses the bar.

**Fix** [RECOMMENDATION] — Measure the gap from the end of the bar the clock is in, not from the clock: replace the test with `nb > SSRBarOpenMsc(m_master.now_msc) + SSR_MSC_PER_MIN + 2 * SSR_MSC_PER_MIN`, and gate the skip on the current bar being finished — `m_member[0].EmittedMsc() >= SSRBarOpenMsc(now) + 59999`. Either alone removes the mid-bar case; both together also make the "market closed from …" text name a bar boundary, which is what a reader expects. See `core-engine-3` for the second half of the problem: `JumpForward` publishing nothing is itself a defect, and fixing that makes this one far less damaging.

##### `core-engine-4` — HIGH — a FULL_TICK window with zero broker ticks is consumed silently

**File:** `MQL5/Include/SSReplay/Core/SSR_ReplayController.mqh:349` · **Category:** zero-empty

```mql5
            int n = tp.ReadTicks(m_state.symbol, lo - 1, hi, m_ticks);
            ...
            n = m_guard.FilterTicks(m_ticks, n);
            ...
            emitted = n;
            m_cursor.Advance(hi, emitted, 0);
            return emitted;
```

**Failure scenario** (verifiers' qualification folded in) [CONFIRMED FROM CODE] — Broker holds one month of ticks but years of M1. The user starts a replay three months back (`InpStart`, the picker, or a random start). `Load` sets `m_ticks_available = range.has_ticks`, which `Discover` computed by probing only the last 24 h (`SSR_Mt5Providers.mqh:133-139`), so it is true, and the host requests FULL_TICK (`SSReplayStandalone.mq5:1153`). Every 1x pump reads `(lo-1, hi]`, gets 0 ticks, and advances the cursor to `hi` with no ticks, no bar context, no fallback and no log line. The clock runs, Progress advances, the panel says "FULL TICK", and the market is frozen. It is intermittent rather than total: `Decide()` falls to `SSR_FIDELITY_BAR` on any bulk pump (`owed_msc >= SSR_BULK_THRESHOLD_MSC`, `SSR_FidelityPolicy.mqh:119-123`), so bars do flow at high speed and after jumps — which makes the user's diagnosis *harder*, not easier. The group's weekend-skip does not rescue it, because `NextBarOpen` finds an M1 bar one minute ahead.

**Why** [CONFIRMED FROM CODE] — Lines 349-369 contain no `n == 0` branch; the only degradation trigger on the whole path is `tp == NULL` (337-346), and `CSSRMt5DataSource::Ticks()` returns the provider whenever `m_has_ticks` is set. `m_ticks_available` is written in exactly two places (344 and 806) and never re-evaluated per window. The range-aware question already exists — `CSSRTickProvider::HasTicks(symbol, from, to)` (`SSR_IDataSource.mqh:179`) — and a repo-wide grep shows it has no caller.

**Verifiers** — Confirmed with one qualification: a broker that answers a tickless range with `-1` rather than `0` would surface `SSR_ERR_LOAD_FAILED` instead of freezing; the silent variant needs `CopyTicksRange` to return 0, which is the ordinary MT5 answer for held-but-empty tick history but cannot be proven from this repo.

**Fix** [RECOMMENDATION] — Two lines, one call. At `Load`, replace the capability flag with the range-aware question that already exists: `m_fidelity.SetTicksAvailable(tp != NULL && tp.HasTicks(sym, m_timeline.warmup_first_msc, m_timeline.end_msc))`. Then make the per-window case self-healing: in the FULL_TICK branch, if `n == 0` and the window covers at least one existing M1 bar, call `m_fidelity.SetTicksAvailable(false)`, log once through `SetError`-style plumbing ("no broker ticks in this window; continuing at synthetic-tick fidelity"), and fall through to the synthetic path for that window rather than advancing the cursor. The panel's fidelity readout already renders "degraded" (see `core-engine-11`), so the user is told.

##### `core-engine-1` — HIGH — the per-pump budget cap drops bars instead of deferring them

**File:** `MQL5/Include/SSReplay/Core/SSR_ReplayController.mqh:524` · **Category:** future-data-leakage

```mql5
      int cap = m_budget.MaxBars(m_synth.TicksForBar(fid));
      if(nb > cap)
        {
         nb = cap;                                   // line ~400: original count destroyed
...
      long consumed_to = hi;
      if(bars_used > 0 && (first + bars_used) < nb)  // line 524: unconditionally false
```

**Failure scenario** (verifiers' corrected version) [CONFIRMED FROM CODE] — On a machine whose calibrated µs/tick is high enough to clamp `MaxTicks` to 32 (cap = 4 bars at 8 ticks/bar), or at BAR fidelity where cap == MaxTicks, any pump owing more bars than the cap discards the excess: they are neither written to the custom symbol nor published to the trading engine, and the cursor is advanced past them. Press PgDn (`StepBars(10)`) or resume after a stall at high speed, and the chart shows a multi-minute hole while any SL/TP inside those minutes is never evaluated. The drop is **entirely unreported**: `m_pump_deferred` reaches only `CSSRMetrics` (`perf.deferred_pumps`) and `CSSRPumpBudget::Deferrals()`, `SSRUiState` carries no deferral field, and `BudgetText()` has exactly one consumer, `SSR_T7_Performance.mq5:236`. Because the cap derives from a wall-clock measurement, which bars get dropped is machine-dependent — the determinism claim fails with it.

**Why** [CONFIRMED FROM CODE] — Line ~400 overwrites `nb = cap`, destroying the original count, so the "stop short" test at 524 compares `first + bars_used` against the **already truncated** `nb`. The loop at 437 runs `i = first..nb-1` and increments `bars_used` every iteration; its only escape, `if(w <= 0) break` (442), cannot fire because `m_ticks` was resized to `need = (nb-first)*per_bar` **after** the cap (406-418), so `Synthesize`'s `ArraySize(out) < offset + n` guard (`SSR_TickSynthesizer.mqh:117`) is unreachable. Hence `first + bars_used == nb` exactly when the cap bit, `consumed_to` stays `hi`, and line 531 advances the cursor past unread bars. The comment at 519-522 documents the opposite intent: "Anything above it stays owed."

**Verifiers** — The dead branch is provable from the allocation order alone; `T7.6` cannot catch it because it only asserts `TicksEmitted` keeps rising, which the following bars satisfy.

**Fix** [RECOMMENDATION] — Keep the pre-cap count. Introduce `int nb_wanted = nb;` before the clamp, and set `consumed_to` from what was actually emitted rather than from the clock:

```mql5
      int nb_wanted = nb;
      if(nb > cap) { nb = cap; m_budget.NoteDeferral(); m_pump_deferred = true; }
...
      long consumed_to = (nb < nb_wanted)
                         ? SSRBarOpenMsc(bar_time[first + bars_used - 1]) + 59999
                         : hi;
```

The next pump's `PendingRange` then starts at `consumed_to + 1` and the owed bars are genuinely owed, as the comment always claimed. Add a `T7` assertion that sets a deliberately tiny budget, steps 10 bars, and asserts the emitted bar count equals 10 across however many pumps it takes.

##### `core-engine-2` — HIGH — `StepBars(n)` advances n-1 bars; `StepBars(1)` is a no-op after the first step

**File:** `MQL5/Include/SSReplay/Core/SSR_ReplayController.mqh:1169` · **Category:** boundary

```mql5
      long base = SSRNextBarOpenMsc(m_clock.now_msc, PERIOD_M1);
      long nb   = NextTimelineBarOpen(m_clock.now_msc);
      if(nb != SSR_INVALID_TIME && nb > base)
         base = nb;
      long target = base + (long)(bars - 1) * SSR_MSC_PER_MIN - 1;
```

**Failure scenario** (verifiers' corrected version) [CONFIRMED FROM CODE] — `StepBars` always leaves the clock at `last emitted bar's open + 59999`. From that resting point the formula re-derives the same instant for `bars == 1`, so the right-arrow key is a **no-op on every press after the first**, and PgDn moves 9 bars instead of 10, until something else moves the clock (Play, a jump, a backward step). Fresh Load at 10:00:00.000 → `StepBars(1)` → base 10:01:00.000, target 10:00:59.999, one bar emitted. Press `→` again: base 10:01:00.000, `nb` = 10:01:00.000 (dense data, cannot raise base), target = 10:00:59.999 == now, `m_clock.now_msc > before` is false, nothing emitted, returns 0 — while `CSSRMasterClock::StepBars` returns **true**, so the group path reports success with nothing moved.

**Why** [CONFIRMED FROM CODE] — `SSRNextBarOpenMsc(msc) = SSRBarOpenMsc(msc) + 60000` (`SSR_Time.mqh:37-43`). For `now = open+59999`, `SSRBarOpenMsc` floors to `open`, so `base = open+60000` and `target = base + 0 - 1 = now`. `nb` is the first bar strictly after `now`, which equals `base` in dense data and so fails `nb > base`. The production path is identical, not merely analogous: `SSR_MasterClock.mqh:347-351` uses the same formula on the master clock, and `Panel:2293 → GroupPort:439-440 → group.StepBars → PumpTo(t)` with `t <= now` returns without advancing.

**Verifiers** — Integer arithmetic re-derived twice; `T1.7` (`SSR_T1_CoreEngine.mq5:283-291`) calls `StepBars(1)` ten times but asserts only `after10 > start`, which the first step alone satisfies.

**Fix** [RECOMMENDATION] — Derive the target from bar count, not from a subtracted millisecond. Compute the base as the open of the bar **after** the one the clock is resting in, and land on its last millisecond:

```mql5
      long cur  = SSRBarOpenMsc(m_clock.now_msc, PERIOD_M1);
      long base = cur + SSR_MSC_PER_MIN;            // always strictly ahead
      long nb   = NextTimelineBarOpen(m_clock.now_msc);
      if(nb != SSR_INVALID_TIME && nb > base) base = nb;
      long target = base + (long)(bars - 1) * SSR_MSC_PER_MIN + SSR_MSC_PER_MIN - 1;
```

Apply the identical change in `CSSRMasterClock::StepBars` (347-351) — the two copies must stay in step, and the duplication is itself worth removing by having the master delegate to stream 0. Replace `T1.7`'s assertion with `after10 == start + 10*60000 - 1`.

##### `core-engine-3` — HIGH — `JumpForward` feeds bulk bars to the sink but never to observers

**File:** `MQL5/Include/SSReplay/Core/SSR_ReplayController.mqh:1383` · **Category:** sl-tp-execution

```mql5
            if(!m_sink.SeedBars(bulk, n))
              {
               SetError(SSR_ERR_SINK_FAILED, "bulk write failed: " + m_sink.LastErrorText());
               return -1;
              }
            m_metrics.RecordSeed(n, (double)(GetMicrosecondCount() - t0) / 1000.0);
            written += n;
            m_cursor.Advance(last_bar - 1, 0, n);
```

**Failure scenario** (verifiers' corrected version) [CONFIRMED FROM CODE] — A long opens at 10:40 with SL 1.1000; the stop is hit at 10:45:40; at 10:47:30 the user presses `←` (`StepBackward(1)`, target 10:46:00). Checkpoint 10:45:00 is restored, `OnRewind(10:45:00)` un-does the stop-out so the position is open again, `JumpForward(10:46:00)` bulk-writes bar 10:45 and publishes nothing, then emits only the 10:46:00.000 open tick. The position is now open at 10:46 although the chart shows the stop being taken inside bar 10:45; on the next tick `CheckStops` fires at whatever price is current, or never if price recovered. Because `JumpForward` also never calls the observers' `OnClock` (unlike `Pump`/`PumpTo` at 1023-1025 and 1098-1100), the engine's `m_now_msc` does not move across the bulk span either: swap accrual and every time-based rule skip it too. The window is bounded by the checkpoint interval (`SSR_CHECKPOINT_INTERVAL_MSC` = 5 replay minutes, `SSR_SnapshotStore.mqh:32`) for a step back, but **unbounded** for a forward J-jump or a session resume through `JumpTo`.

**Why** [CONFIRMED FROM CODE] — Observers are reached only through `PublishBar`/`PublishTicks`/`PublishSegment` (191-231), whose only callers are inside `EmitWindow` (366, 506-515). `JumpForward`'s bulk leg (1370-1392) calls `SeedBars` + `RecordSeed` + `Advance` and nothing else; `EmitWindow` runs only for the bar containing the target (1397-1398). `CSSRTradingEngine::OnTicks` (599-614) is the only place `CheckStops`/`CheckPendings`/`CheckStopout` run; `OnBarContext` merely caches. The host comment at ~2795 acknowledges the behaviour for the strategy view ("A JUMP WRITES ITS BARS IN BULK and publishes none of them") — nothing compensates for the account.

**Verifiers** — Publish surface and consumer both traced; the design rationale (avoid tick injection for fast-forward) is sound for the sink and does not require observers to be skipped.

**Fix** [RECOMMENDATION] — Publish a summary of the bulk span rather than nothing. After the `SeedBars` call, walk the same `bulk[]` array and, per bar, issue `PublishBar(bulk[k])` followed by `PublishTicks` of the four OHLC-ordered synthetic ticks `m_synth` already knows how to build (`TicksForBar(SSR_FIDELITY_BAR)` is the cheap case), then `PublishClock(bar_close_msc)`. That costs no `CustomTicksAdd` — the expensive half — and gives the trading engine an evaluable price path for every skipped minute, which is what stops, targets and swap accrual need. If the cost is unacceptable for very long jumps, gate the tick publication on `n <= some_bars` and, above it, publish a single `PublishRewind`-style "the account was fast-forwarded across N bars without price evaluation" notice that the panel and the journal can show, so the silence is at least declared.

#### C.4.2 Data layer - `MQL5/Include/SSReplay/Data`

##### `data-1` — HIGH — `has_ticks` is probed over the newest 24 hours and then applied to a window years earlier

**File:** `MQL5/Include/SSReplay/Data/SSR_Mt5Providers.mqh:136` · **Category:** capability probe (finder's "future-data-leakage" is the wrong category — verifiers' correction)

```mql5
      long to_msc   = out.last_msc;
      long from_msc = to_msc - 24 * 60 * 60 * 1000;
      int  got = CopyTicksRange(symbol, probe, COPY_TICKS_INFO,
                                (ulong)MathMax(from_msc, 0), (ulong)to_msc);
      out.has_ticks = (got > 0);
```

**Failure scenario** (verifiers' corrected version) [CONFIRMED FROM CODE] — Broker keeps 30 days of EURUSD ticks and 5 years of M1. The user replays 2021.03.01-15. `Discover()` probes *today*, finds ticks, sets `has_ticks=true`; the host pins FULL_TICK (`SSReplayStandalone.mq5:1153`) and the controller sets `m_fidelity.SetTicksAvailable(true)` (`SSR_ReplayController.mqh:806`). Every 1x pump reads March 2021, `CopyTicksRange` returns 0, and `EmitWindow` consumes the window with nothing emitted. The clock walks to `end_msc` and the session reaches COMPLETED with no error, no warning and no degradation — while the one diagnostic that does fire says the opposite: 2267 prints "this session is replaying the broker's REAL ticks, so the spread on every one of them is the broker's own". Not total: `Decide()` degrades to BAR on any bulk pump, so bars flow at high speed and after jumps while 1x emits nothing, which makes the symptom intermittent and the misdiagnosis worse.

**Why** [CONFIRMED FROM CODE] — The probe range is hardcoded to the newest day and is the only writer of `out.has_ticks`; `CSSRMt5DataSource::Ticks()` (91-96) returns the provider whenever that flag is true, so the engine's only fallback (`if(tp == NULL)`, 337-345) never fires. The range-aware `HasTicks(symbol, from_msc, to_msc)` exists at `SSR_Mt5Providers.mqh:379` with **no caller** anywhere in the repo. The contract this breaks is written in the file it breaks: `SSR_Mt5DataSource.mqh:86-89` — "Returning it unconditionally would let the engine run at FULL_TICK fidelity against an empty tick history and emit nothing - a replay that silently shows a frozen market."

**Verifiers** — Chain confirmed link by link; severity held at HIGH rather than CRITICAL because the session visibly fails to play rather than producing wrong results, and no price or trade data is corrupted.

**Fix** [RECOMMENDATION] — Probe the window you are going to replay. `Discover()` does not know it yet, so move the decision: keep `out.has_ticks` as a coarse "this symbol has some tick history" hint for the picker, and at `Load` (806) replace the flag with `m_fidelity.SetTicksAvailable(tp != NULL && tp.HasTicks(sym, warmup_first_msc, end_msc))` — the call that already exists and is dead. Pair it with `core-engine-4`'s per-window fallback so a partially covered range degrades mid-session instead of freezing, and gate the 2267 "real ticks" diagnostic on the same answer so it can never contradict the engine.

#### C.4.3 MT5 bridge - `MQL5/Include/SSReplay/Mt5`

##### `mt5-symbol-1` — HIGH — warmup repair after a jump is silently skipped whenever the seed came from the cache

**File:** `MQL5/Include/SSReplay/Mt5/SSR_CustomSymbolSink.mqh:265` · **Category:** session-resume

```mql5
bool is_warmup = (m_warmup_to_msc > 0 &&
                  SSRToMsc(bars[count - 1].time) <= m_warmup_to_msc);

if(m_reused_seed && is_warmup)
  {
   m_seed_bars += count;
   return true;                       // WriteBars never called
  }
```

**Failure scenario** (verifiers' corrected version) [CONFIRMED FROM CODE] — This is the **default** path, not an edge case: the one-window handover only fires after pass 1 has seeded the warmup and written the manifest, so `CanReuse()` returns true on pass 2 of every shipped run and `m_reused_seed` is set. The user jumps forward; the terminal drops the tickless warmup bars (measured behaviour, documented at `SSR_IReplaySink.mqh:84-90` and `SSR_ReplayController.mqh:913-918`). `RepairWarmupIfLost` (934-968) notices `OldestMsc() > warmup_first`, re-reads the warmup and calls `SeedBars`. Those bars end at `start-1`, so `is_warmup` is unconditionally true, the early return fires, nothing is written back — and the controller logs "the sink dropped the warmup … N bars written back" (963-967). The chart keeps only the post-jump tail for the rest of the session, and every later jump repeats the same silent no-op.

**Why** [CONFIRMED FROM CODE] — `m_reused_seed` is written in exactly three places, all inside `Prepare` (145 clear, 162 set from `CanReuse`, 170 re-clear if `Adopt` fails) and never cleared for the life of the session. `m_warmup_to_msc` is `start_msc - 1` (`OnWarmupPlanned`, controller 814-816 → sink 366-367), and `RepairWarmupIfLost` reads exactly `warmup_first_msc .. start_msc-1`, so the payload can never fail the `is_warmup` test. The early return keys only on the flag and the range, so it cannot tell the initial delivery (which the cache legitimately covers) from a later repair of bars the terminal has since discarded — and `SeedBars` reports success either way, so the controller cannot tell either.

**Verifiers** — Three separate refutation attempts (range arithmetic, flag lifetime, reachability) all failed; the next session self-heals only because `CanReuse`'s `SERIES_FIRSTDATE` evidence check misses.

**Fix** [RECOMMENDATION] — Distinguish "the cache already holds this" from "the terminal threw it away". Add a one-shot latch: `bool m_seed_delivered;` set true the first time the early return is taken, and change the guard to `if(m_reused_seed && is_warmup && !m_seed_delivered)`. A repair call, by definition the second warmup-range `SeedBars` of the session, then falls through to `WriteBars`. Cheaper still and more honest: give the sink an explicit entry point — `bool RepairBars(const MqlRates &bars[], int count)` that always writes — and have `RepairWarmupIfLost` call that instead of `SeedBars`, so the two intents are not sharing one function. Either way, make the controller's log line report the sink's actual written count rather than the count it handed over.

#### C.4.4 Trading and risk - `MQL5/Include/SSReplay/Trading`

##### `trading-analytics-1` — HIGH (verifiers: MEDIUM) — resuming a saved session voids a running prop evaluation before the first candle

**File:** `MQL5/Include/SSReplay/Trading/SSR_PropEvaluation.mqh:443` · **Category:** session-resume

```mql5
virtual void      OnRewind(const long msc) override
     {
      if(!m_rules.enabled || m_state != SSR_PROP_RUNNING)
         return;
      m_state  = SSR_PROP_VOID;
      m_reason = "the clock was moved backwards at " + SSRFormatMsc(msc) +
```

**Failure scenario** (verifiers' corrected version) [CONFIRMED FROM CODE] — `InpProp=true`, `InpResume=true`, an existing session file: the evaluation is VOID before a single candle plays, the replay auto-pauses with "evaluation VOID - the clock was moved backwards at &lt;now&gt;", and the only way on is Reset — which restarts day counting from zero (see `trading-analytics-2`). The failure is safe and visible — it never produces a false *pass* — so the verifiers trim severity to MEDIUM; the defect that remains is that a restore-to-now notification is indistinguishable from a real rewind, which makes the reason text factually false: nothing moved backwards.

**Why** [CONFIRMED FROM CODE] — Host 1197 `g_prop.Reset()` (state RUNNING when enabled) and 1200 `Watch(g_prop)` (= `g_ctrl.AddObserver`, 869-877); `g_ctrl` is in `g_group` (1320); `g_ctrl.Load` (1252) fires `OnSessionStart` → `Reset()` again, still RUNNING; then 1483 `g_session_mgr.Restore()` → `SSR_SessionManager.mqh:381` `NotifyRestored()` → `SSR_ReplayController.mqh:1669` `PublishRewind(m_clock.now_msc)` → every observer's `OnRewind`. The only guard is `m_state != RUNNING`, which does not hold. The rewind target is *now*, so the clock is where it always was.

**Verifiers** — Chain unconditional and re-traced twice; mechanism and reachability accurate, severity dissent noted above.

**Fix** [RECOMMENDATION] — Give the observer contract a way to say "this is a restore, not a rewind". Add `virtual void OnRestored(const long msc) {}` to the observer interface with a default body that does nothing, have `NotifyRestored` call `PublishRestored(m_clock.now_msc)` instead of `PublishRewind`, and let the two observers that genuinely need to re-base (the trading engine, statistics) override it by delegating to their own `OnRewind`. `CSSRPropEvaluation` then simply does not override it and stays RUNNING. The cheap interim fix, if the interface change is too broad for one release, is a guard inside `OnRewind`: `if(msc >= m_last_seen_msc) return;` — a "rewind" to the current instant is not a rewind. Fix the reason text either way, because a VOID that names an event that did not happen teaches the trainee to distrust the instrument.

##### `trading-exec-2` — HIGH — stops, targets, trailing state and MAE/MFE are not versioned, so they survive a rewind

**File:** `MQL5/Include/SSReplay/Trading/SSR_TradingEngine.mqh:263` · **Category:** event-handling

```mql5
void              UnwindLegsAfter(const int i, const long msc)
  {
   while(m_pos[i].leg_count > 0 &&
         m_pos[i].legs[m_pos[i].leg_count - 1].msc > msc)
     {
      int e = --m_pos[i].leg_count;
```

**Failure scenario** [CONFIRMED FROM CODE] — A long at 1.1000 with `trail_points=200` — armed automatically on every risk-sized trade whenever a trail distance is set (`SSR_GroupPort.mqh:1061-1063`), so the precondition is one panel setting. Price runs to 1.1100, `ApplyTrailing` moves `sl` to 1.1080 and `trail_peak` to 1.1100. The user steps back to the minute when price was 1.1020. `OnRewind` keeps the position (placed before the cut) but leaves `sl=1.1080` and `trail_peak=1.1100`. The first re-emitted tick has bid 1.1020 ≤ sl, so `CheckStops` closes at `StopFill` with reason SL and AutoPause announces "stop loss hit" — at a moment when the stop was really at 1.1000 and the trade was +20 pips. The same applies to a manual `Modify()` or `BreakEven()` performed in the deleted future, and to `mae`/`mfe`/`spread_at_exit`, which keep values from a future that no longer exists.

**Why** [CONFIRMED FROM CODE] — `SSRTradeLeg` (`SSR_TradeTypes.mqh:143-169`) records volume, price, msc, realised, fee, closing, `prev_swap_locked`, `prev_swap_from_msc`, `prev_ambiguous` — and nothing about `sl`, `tp`, `trail_peak`, `mae` or `mfe`, so there is no snapshot for a rewind to restore. `OnRewind` (634-702) resets those fields only inside the pending un-fill branch (676-679); a position already open at the cut is copied forward untouched (692-694). `ApplyTrailing` (302-323) ratchets one way only (`if(want > m_pos[i].sl)` for a long), so a stop trailed up in the deleted future is never lowered again, and `CheckStops` 526-527 compares the re-emitted bid against it.

**Verifiers** — Struct and rewind path both read; the trigger is a user setting, not an exotic path.

**Fix** [RECOMMENDATION] — Version the mutable protective state the same way exits are versioned. Extend `SSRTradeLeg` with the five fields that a rewind must undo — `prev_sl`, `prev_tp`, `prev_trail_peak`, `prev_mae`, `prev_mfe` — and push a leg of a new kind (`SSR_LEG_PROTECT`, volume 0, no money moved) from `ApplyTrailing`, `Modify` and `BreakEven` whenever any of them changes. `UnwindLegsAfter` already walks legs newest-first past the cut; restoring five scalars per leg is the same loop. Legs are already bounded per position, and a protective leg carries no money, so `BookExit`, the balance arithmetic and the ambiguity counters are untouched. If leg-array growth is a concern, coalesce: only push a protective leg when the previous one in the same bar has a different `msc`.

#### C.4.5 UI layer - `MQL5/Include/SSReplay/Ui`

##### `ui-panel-3` — HIGH — `HideBody(false)` un-hides the tab rail 47 lines after compact mode hid it

**File:** `MQL5/Include/SSReplay/Ui/SSR_Panel.mqh:682` · **Category:** object-lifecycle

```mql5
      if(m_compact != was_compact)
        {
         HideSheetArea(m_compact);              // line 682
...
      HideBody(false);                          // line 729, same Render()
...
      if(!m_compact) { DrawActions(); DrawRail(); DrawSheet(); }   // line 735
```

**Failure scenario** (verifiers' corrected version) [CONFIRMED FROM CODE] — The panel has already painted a full frame on a chart taller than 360 px; the user opens the Toolbox and the chart shrinks below `SSR_PANEL_H+24`. Compact mode engages — and the rail tabs `tab0..tab4`, the `tabline` hairline and the three action buttons (`lines`, `sessions`, `fidelity`) stay **visible at their full-layout coordinates**. The compact body is 128 px tall (status strip at y+109..y+127) while the rail cells sit at y+128, y+153, y+178, y+203, y+228: up to 122 px of stray, still-clickable tab buttons painted on the candles below the panel, plus the action strip at y+103..y+124 overlapping the compact status strip. This is exactly the failure compact mode was built to prevent. It does not happen when the panel starts compact — `HideSheetArea` and `HideBody` then act on objects that do not exist yet.

**Why** [CONFIRMED FROM CODE] — `HideSheetArea` (2042-2050) hides those ids, but `HideBody(false)` at 729 runs on every non-collapsed frame and its id list (2079-2098) contains `tabline`, `lines`, `sessions`, `fidelity` plus `for(int t = 0; t < SSR_TAB_MAX; t++) m_w.Hide("tab" + IntegerToString(t), hidden);`. With `hidden==false`, `CSSRWidgets::Hide` writes `OBJPROP_TIMEFRAMES = OBJ_ALL_PERIODS` (`SSR_Widgets.mqh:620-621`), making every one of them visible again in the same call; the `if(!m_compact)` guard at 735 then skips the three draw calls, so nothing removes or repositions them. Geometry checks out: `SSR_PANEL_H = 23+32+27+21+21+186+18+8 = 336`. `HideSheetArea` is not a total no-op — its `HideSheets()` (2049) genuinely removes the sheet contents; it is a no-op only for the eight ids in its own list.

**Verifiers** — `HideSheetArea` has exactly one call site (682); the un-hide is 47 lines later in the same function.

**Fix** [RECOMMENDATION] — `HideBody` must not contradict compact mode. Pass the mode through: change the call at 729 to `HideBody(false, m_compact)` and, inside, skip the eight compact-hidden ids when the second argument is true — or, more simply, replace the unconditional `HideBody(false)` with `HideBody(false); if(m_compact) HideSheetArea(true);` so the last writer is the one that knows the mode. Then remove the transition guard at 682 entirely and call `HideSheetArea(m_compact)` every frame: it is eight `Hide` calls, ~8 `ObjectSet*` writes at ~0.07 ms each, against a repaint that already costs 39 ms for 561 writes. Add a QA smoke assertion that after a full→compact transition `ObjectGetInteger(0,"tab4",OBJPROP_TIMEFRAMES) == OBJ_NO_PERIODS` — see `qa-smoke-13`, whose current assertion checks `tab0` and `tabline` only and could never have caught this.

##### `ui-dialogs-1` — HIGH — `ReadAll()` wipes session name and extra timeframes on every start path

**File:** `MQL5/Include/SSReplay/Ui/SSR_SetupPanel.mqh:300` · **Category:** input-validation

```mql5
   string            Str(const string id, const string fallback)
     {
      string t = m_w.EditText("e" + id);
      if(t == "")
         return "";                       // an emptied box IS a choice here
      StringTrimLeft(t); StringTrimRight(t);
```

**Failure scenario** (verifiers' corrected version — broader than the finder's) [CONFIRMED FROM CODE] — Because `go` exists only on the START step, which never contains the `xtf`/`ses` boxes, `extra_tfs` and `session_name` are wiped on **every** start path, wizard and quick alike — not merely after a MODE-step Next. So: panel-set extra timeframes never take effect; session saving never happens (`Save()` writes `session=` empty, `CfgSession()` is `""`, and `OnDeinit`'s `if(CfgSession() != "")` never runs, so the account, trades and position are never written to disk and cannot be resumed); and a session name previously stored in `setup.ini` is overwritten with empty. Step 3 duly recaps "Save as: not saved", which is the only honest thing on the screen.

**Why** [CONFIRMED FROM CODE] — `CSSRWidgets::EditText` returns `""` both for an empty box and for an **absent** one (`SSR_Widgets.mqh:350-356`: `if(ObjectFind(m_chart,n) < 0) return ""`), and `Str()` discards its `fallback` parameter in that case — the parameter is dead. Its two siblings defend correctly: `Num()` returns its fallback (285-287) and the seed read is wrapped in `m_w.Exists("eseed")` with a comment naming this exact hazard (1180-1189). `ReadAll` calls `Str()` unguarded at 1174-1175 and runs on every `next` (1061-1067) and every `go` (1076); `Repaint()`'s `m_w.RemoveAll()` (658 → `ObjectsDeleteAll` by prefix) guarantees the objects are gone on steps 0/2/3, and only `RenderSettings` ever creates them (786, 804).

**Verifiers** — Traced end to end; worse than the finder claimed, because the quick path is affected too.

**Fix** [RECOMMENDATION] — Make `Str()` behave like `Num()` — distinguish absent from emptied, which the widget layer can already answer:

```mql5
   string            Str(const string id, const string fallback)
     {
      if(!m_w.Exists("e" + id))
         return fallback;                 // the box is not on this step
      string t = m_w.EditText("e" + id);
      if(t == "") return "";              // an emptied box IS a choice
      StringTrimLeft(t); StringTrimRight(t);
```

That is the same shape as the seed read three lines away, and it revives the dead `fallback` parameter rather than adding a concept. Then add a `T15`/QA assertion that walks step 1 → 2 → 3 with a typed session name and asserts `Values().session_name` still holds it at `go` — the wizard's most valuable single regression test, since without it the product's save feature is inert.

#### C.4.6 Session - `MQL5/Include/SSReplay/Session`

##### `ui-port-session-3` — HIGH — Restore never checks the streams reached the saved instant, and cannot rewind to it

**File:** `MQL5/Include/SSReplay/Session/SSR_SessionManager.mqh:350` · **Category:** session-resume

```mql5
      long now = m_group.At(0).Now();
      m_group.SeekAllTo(now);
```

**Failure scenario** (verifiers' corrected version) [CONFIRMED FROM CODE] — Save session "A" at 10:00, play on to 10:30, open the Session dialog and press Load on "A" (`CSSRGroupPort::LoadSession`, 960-972, has no guard of any kind). The streams stay at 10:30 and the 10:00 account is installed over them. The restored account is **not** fed the 10:00-10:30 ticks at all — `JumpForward` bulk-seeds those bars to the sink only, and the wind-forward is skipped entirely on this path — so stops and targets crossed in that half hour are not "evaluated late", they are **never evaluated**. Restored open positions simply resume at 10:30+ prices with an unrecorded hole in MAE/MFE and stops that should already have fired still standing, while the panel and `ResumeReport` announce "resumed 1 stream(s) at 10:30" with no warning.

**Why** [CONFIRMED FROM CODE] — `master_now` is written at 176 and read only by `Peek` (224); `Restore` never reads it, so it has nothing to compare against. The stream restore moves forward only: `CSSRReplayController::RestoreFrom` does `if(want_now > m_clock.now_msc && !JumpTo(want_now))` (1826), even though `JumpTo` handles backwards jumps through `StepBackward` (1494-1515). `SeekAllTo(now)` is then a no-op (the master is already there) and its result is discarded. Nothing else warns: the out-of-window check (1786-1795) only rejects instants outside the timeline; the fingerprint is taken at the **current** clock (`FingerprintUpTo(m_clock.now_msc)`), so it compares the wrong range and typically matches; `MaxSkewMsc` (`SSR_MasterClock.mqh:416-430`) compares streams against each other and is 0 for a single stream.

**Verifiers** — No guard anywhere on the path; the dialog Load route reaches it unprotected.

**Fix** [RECOMMENDATION] — Compare, then choose. `Restore` already has `master_now` in hand from the file:

```mql5
      long want = m_hdr.master_now;
      long now  = m_group.At(0).Now();
      if(want < now)
        {
         if(!m_group.SeekAllTo(want))         // JumpTo already handles backwards
            m_warn += "could not rewind to the saved instant; ";
        }
      else if(want > now)
         m_group.SeekAllTo(want);
      now = m_group.At(0).Now();
```

`SeekAllTo` → `JumpTo` → `StepBackward` is the path that already exists for the `←` key, so backward restore needs no new machinery. Report the outcome honestly: `ResumeReport` should print the **file's** instant and, when the streams could not be moved there, the BUT clause it currently never emits. Note that a backward restore then inherits `core-engine-3`'s blind wind-forward, so the two should be fixed together.

#### C.4.7 Strategy - `MQL5/Include/SSReplay/Strategy`

##### `strategy-integration-report-1` — HIGH — in FULL_TICK fidelity the market view is never fed bars

**File:** `MQL5/Include/SSReplay/Strategy/SSR_MarketView.mqh:173` · **Category:** stale state

```mql5
   virtual void      OnBarContext(const MqlRates &bar, const bool synthetic) override
     {
      m_synthetic = synthetic;
      Grow();
```

**Failure scenario** (verifiers' corrected version) [CONFIRMED FROM CODE] — `InpRefStrategy=true` (default false) on a symbol whose history carries ticks, so the host selects FULL_TICK at 1153. `PrimeView` fires once on the first pump, fills the buffer with M1 bars ending at that instant, and never refreshes. An hour into the replay `CSSRRefBreakout::OnBar` still reads `Bar(tf,1)` and `HighestHigh`/`LowestLow` from bars an hour old while comparing them against a live `ctx.market.Bid()`: it either refuses every bar with "stop would be the wrong side of price" or opens a risk-sized trade whose stop is hundreds of points from the market. Not absolute — any pump owing ≥ `SSR_BULK_THRESHOLD_MSC` (10 minutes, e.g. after a timer stall) degrades to BAR fidelity in `Decide` and does refresh the view — but in steady FULL_TICK playback, the normal case, no bar is ever published.

**Why** [CONFIRMED FROM CODE] — `CSSRMarketView`'s only bar inputs are `OnBarContext` and `Prime`. `OnBarContext` has exactly one caller, `PublishBar` (`SSR_ReplayController.mqh:191-196`), which has exactly one call site, line 506 — inside the bar-driven branch the FULL_TICK path has already returned from at 369 (it calls `PublishTicks` at 366). `Prime` has one caller, `PrimeView` (`SSReplayStandalone.mq5:403`), which `OnTimer` gates on `g_view.M1Count() == 0` (2797) — false forever after the first successful prime. The view's `m_now_msc`, `m_bid` and `m_ask` keep advancing through `OnTicks`/`OnClock`, so `Now()`/`Bid()`/`Ask()` stay live while every bar accessor is frozen, and `Available()` still reports the stale groups, leaving the strategy no way to detect the divergence.

**Verifiers** — Starvation path provable by grep: two bar inputs, one caller each, both dead in steady FULL_TICK.

**Fix** [RECOMMENDATION] — Publish the bar in the FULL_TICK branch too. `EmitWindow` already holds the M1 bar it read for the clip; before `return emitted` at 369, call `PublishBar(m_bars[first], false)` once per bar boundary crossed (track the last published open in a member so the same bar is not republished on every pump — the same guard `core-sync-2` needs). Observers that only want ticks ignore it. Failing that, relax the prime gate at 2797 from `M1Count() == 0` to "the newest view bar is older than the clock's bar", which re-primes at most once a minute and costs one `CopyRates`.

#### C.4.8 Spike kit - `MQL5/Include/SSReplay/Spike`

##### `spikes-audits-1` — HIGH — the bar-to-ticks curve never reaches the bar's high or low unless `(n-1) % 3 == 0`

**File:** `MQL5/Include/SSReplay/Spike/SSR_SpikeKit.mqh:579` · **Category:** sl-tp-execution

```mql5
double u   = (cnt == 1) ? 0.0 : (double)i * 3.0 / (double)(cnt - 1);
int    seg = (int)MathFloor(u);
if(seg > 2) seg = 2;
double f   = u - (double)seg;
double p   = k[seg] + (k[seg + 1] - k[seg]) * f;
```

**Failure scenario** (verifiers' corrected version — broader than the title) [CONFIRMED FROM CODE] — The keypoints `k[1]` and `k[2]` (the two extremes) are reproduced exactly only when some `i` gives `u == 1.0` and `u == 2.0`, i.e. when `(cnt-1) % 3 == 0`. With `cnt = 20` (B1's `InpPerBar`) `u` steps by 3/19, the nearest samples are 1.8947/2.0526, and the stream reaches at most `H - 0.0526*(H-C)`. **The same formula is the shipping engine's**: `CSSRTickSynthesizer::Synthesize` (`SSR_TickSynthesizer.mqh:134-144`) at its default 8 ticks/bar falls ~14.3 % of the adjacent leg short of each extreme. Because `CheckStops` evaluates SL/TP off the tick price alone, a stop or target placed within that band of a bar's high or low is silently never hit — while the synthesizer's own header (line 13) claims "The OHLC of the resulting bar is exact".

**Why** [CONFIRMED FROM CODE] — `u` lands on an integer keypoint only when `(cnt-1)` is a multiple of 3; replaying the formula gives exact extremes for `cnt` in {4,7,10,16} and shortfalls of 1.43, 0.53, 0.20 price units for {8,20,50} on an O=100/H=140/L=90/C=130 bar. `cnt = MathMax(n,4)` (kit:565) and the forced final write (kit:595-597) fixes the close only, never the extremes. The kit header at 560 calls this "the same assumption the engine will make, tested here first" — which it is.

**Verifiers** — Arithmetic replayed independently; the defect reaches the product at the shipped `InpTicksPerBar=8`, the worst measured case.

**Fix** [RECOMMENDATION] — Pin the extremes instead of hoping the sampling grid hits them. Keep the piecewise walk for shape, but force the two keypoint indices: compute `i_hi = (int)MathRound((cnt-1)/3.0)` and `i_lo = (int)MathRound(2.0*(cnt-1)/3.0)` and write `k[1]`/`k[2]` verbatim at those indices before the loop fills the rest by interpolation — the same trick the code already uses for the close at 595-597. Apply the identical change to `CSSRTickSynthesizer::Synthesize`; it is three lines and makes the header's "OHLC is exact" true. Add a `T1`/QA assertion that for every `n` in 4..32 the synthesised stream's max equals the bar high and its min equals the bar low to the tick — the check nothing currently performs.

### C.5 MEDIUM (58)

Wrong output or dead behaviour a user meets in normal use. Grouped by file so a maintainer can work through one at a time. [CONFIRMED FROM CODE]

#### C.5.1 Host expert - `MQL5/Experts/SSReplay/SSReplayStandalone.mq5`

##### `host-expert-5` — MEDIUM — a random session does not survive the handover

**File:** `SSReplayStandalone.mq5:1020` · **Category:** session-resume

```mql5
      g_picker.SetSeed(SSRSeedFromText(CfgSeed()));
      g_picker.AddSymbolList(InpAlsoSymbols);
      g_picker.AddSymbol(origin);
      if(g_picker.Pick(InpWarmupBars, InpReplayBars, origin))
```

**Failure scenario** (verifiers' corrected version) [CONFIRMED FROM CODE] — `InpRandom=true`, `InpSeed=""`, `InpOneChart=true`. Pass 1 picks a window (possibly a symbol out of `InpAlsoSymbols`), prints the seed, seeds the custom symbol and hands over. Pass 2 re-runs `BuildSession` with two wrong outcomes: (a) no `setup.ini`, so `CfgSeed()` is `""`, `SSRSeedFromText("")` is 0, and `SetSeed(0)` substitutes a brand-new `SSRPickSeed()` — a different window, and the seed printed on pass 1 reproduces nothing; with a non-empty `InpAlsoSymbols` the new pick can be a **different instrument**, replayed into the symbol adopted from pass 1, so a chart named `EURUSD@.SSR1` carries XAUUSD prices. (b) a stale `setup.ini` whose `random=0` or missing key switches randomness off silently and `win_start` falls back to the most recent `InpReplayBars` bars. Both are latent behind `host-expert-1`, which kills pass 2 first.

**Why** [CONFIRMED FROM CODE] — `SetSeed` is `m_seed = (s == 0 ? SSRPickSeed() : s)` (`SSR_RandomPicker.mqh:68-69`) and `SSRSeedFromText("")` returns 0 (`SSR_Random.mqh:99-100`). The pass-2 block at 1933-1948 assigns twelve fields from inputs and omits `random_start` and `seed`, whose `Init()` defaults are `false` and `""`. The symbol mismatch is reachable because `BuildSession` reassigns `origin`/`g_origin` from `g_picker.PickedSymbol()` (1027-1035) while the sink is pinned by `SetAdoptName(_Symbol)` (1964), and `CSSRCustomSymbolSink::Prepare` prints a warning and adopts anyway (152-166). `CSSRSetupPanel::Restore` does read `random`/`seed` (1258-1259), which is why case (b) needs a file lacking them — the common case, since the setup form's defaults (2044-2068) never seed `random_start`/`seed` from `InpRandom`/`InpSeed` either.

**Verifiers** — Both mechanisms provable; case (b) narrower than the finder stated, both latent behind `host-expert-1`.

**Fix** [RECOMMENDATION] — Carry the resolved session across the handover instead of re-deriving it. Pass 1 already knows the answer: stash `picked_symbol|win_start|win_end|seed` in the same handover object that carries the origin (one `OBJPROP_TEXT`, and note the 63-char draw limit does not apply to stored text), and have pass 2 take the window verbatim, skipping `g_picker` entirely. That also removes the seed-reroll and the symbol mismatch by construction. Interim, if the stash is not extended: resolve the seed once in pass 1 (`ulong seed = SSRSeedFromText(CfgSeed()); if(seed == 0) seed = SSRPickSeed();`), print *that*, and add `random_start`/`seed` to the twelve fields copied at 1933-1948.

##### `host-expert-3` — MEDIUM — auto-play is suppressed on the pass that owns the replay chart

**File:** `SSReplayStandalone.mq5:1710` · **Category:** session-resume

```mql5
   if(InpAutoPlay && !one_chart_ok)
     {
      if(g_group.Play())
...
      if(InpAutoPlay)
         Print("[host] auto-play waits for the handover - this pass has no "
               "chart to play on for more than a moment.");
```

**Failure scenario** (verifiers' corrected version) [CONFIRMED FROM CODE] — Default configuration (`InpOneChart=true`, `InpAutoPlay=true`): the replay never starts by itself. Pass 2 enters `BuildSession` with `on_replay=true` **and** `one_chart_ok=true` (1893 sets `one_chart_ok = InpOneChart`; only the poison branch clears it), so `!one_chart_ok` is false, `Play()` is never called, and the log prints "auto-play waits for the handover - this pass has no chart to play on for more than a moment" on the pass that *is* final and *does* hold the replay chart. The user watches a motionless chart — the failure the comment block at 1696-1709 ("DROP IT AND IT WORKS") was written to remove. Auto-play still works with `InpOneChart=false`. Currently unreachable behind `host-expert-1`; it becomes live the moment that is fixed. Motionless chart plus a false log line, no data loss.

**Why** [CONFIRMED FROM CODE] — The intended predicate is "this pass is about to hand its chart over", which is `one_chart_ok && !g_on_replay_chart` — expressed correctly twice elsewhere in the same file (1275, 1689-1694). `!one_chart_ok` also excludes pass 2, where `g_replay_chart == ChartID()` and `g_ready` is true. `g_group.Play()` at 1712 is the file's only `Play()` call site.

**Verifiers** — Guard traced; the correct predicate already exists twice in the file.

**Fix** [RECOMMENDATION] — `if(InpAutoPlay && !(one_chart_ok && !g_on_replay_chart))` — and take the same expression out into a local `bool will_hand_over = (one_chart_ok && !g_on_replay_chart);` computed once near 1689 and used by all three sites, so the three copies cannot drift again. `host-expert-4` is the same wrong guard on the first-run card and is fixed by the same local.

##### `host-expert-6` — MEDIUM — pass 2 restores `setup.ini` unconditionally

**File:** `SSReplayStandalone.mq5:1948` · **Category:** session-resume

```mql5
      g_setup_ready = CSSRSetupPanel::Restore(g_setup);
      if(g_setup_ready)
         Print("[host] carrying the setup across the handover");
```

**Failure scenario** (verifiers' corrected version) [CONFIRMED FROM CODE] — Any configuration that skips the start picker still performs the handover (`InpPickStart=false`, or `InpStart>0`, or `CfgRandom()`, or a resumable session — the four conditions at 2025). On those runs pass 1 never opens the setup form and never writes `setup.ini`, so pass 1 builds from the inputs. Pass 2 then reads whatever `setup.ini` an earlier run left, and every `Cfg*()` switches to it. A user with `InpBalance=25000`, `InpProp=false`, `InpSession=""` and a month-old file holding `balance=10000, prop_on=1, session="demo"` gets a 10,000 balance, a prop evaluation that can fail them, and a session file named "demo" that is both resumed (1063-1070, 1124) and overwritten in `OnDeinit` (2130-2141). Blind mode and the chart timeframe come from the same stale file. The only log line calls it "carrying the setup across the handover". Latent behind `host-expert-1` and requires a stale file.

**Why** [CONFIRMED FROM CODE] — `CSSRSetupPanel::Restore` (`SSR_SetupPanel.mqh:1238-1260`) checks only `FileIsExist(SSR_SETUP_FILE)` and overwrites every field it finds; it carries no run identity, timestamp or origin symbol. Its only writer is the picker's START button (2520), on a path the four skip conditions bypass. The file's own comment at 1926-1931 states the rule in the other direction — "A first pass reading the file would overrule inputs a user had deliberately set for THIS run" — and the second pass doing exactly that is the same defect mirrored.

**Verifiers** — Handover arming (`one_chart_ok && !g_on_replay_chart`, 1786) is independent of whether the picker ran.

**Fix** [RECOMMENDATION] — Make the file self-identifying and let pass 2 accept it only if pass 1 wrote it. Have `Save()` stamp `run_id=` with a value pass 1 also stashes in the handover object (`GetTickCount()` plus the chart id is enough), and have the pass-2 restore read it: `g_setup_ready = CSSRSetupPanel::Restore(g_setup) && g_setup.run_id == stashed_run_id;`. If extending the stash is not wanted, gate on the cheaper proxy already to hand — only restore when pass 1 actually opened the picker, which pass 1 can record in the same handover text as a single leading flag character.

##### `host-expert-8` — MEDIUM — replay and extra-timeframe windows are leaked on every non-removal re-init

**File:** `SSReplayStandalone.mq5:2203` · **Category:** object-lifecycle

```mql5
   bool user_removed = (reason == REASON_REMOVE || reason == REASON_PROGRAM ||
                        reason == REASON_CLOSE);
   if(user_removed)
     {
...
      g_charts.CloseOwned();
```

**Failure scenario** [CONFIRMED FROM CODE] — The header claims a timeframe change on the host chart "rebuilds the session from scratch. The replay chart is unaffected". It is worse than unaffected: `OnDeinit` closes no chart unless the user removed the EA, and `OpenChart` always calls `ChartOpen` with no reuse, so the rebuild opens a fresh set of windows and orphans the old ones. Two-window mode: each period change leaks one replay window plus one per entry in `InpExtraTfs`. One-window mode: pass 2 opens the `InpExtraTfs` layout (1300-1305) and every later `REASON_CHARTCHANGE`/`REASON_PARAMETERS` opens it again. Three period changes with `InpExtraTfs="M15,H1"` leave six stale windows nothing will ever close; past `SSR_MAX_CHARTS` the newest also lose the follow policy (`Sync`, `m_untracked`). The same path leaks a window when `BuildSession` fails after opening the replay chart, since `INIT_FAILED` deinits with a reason outside the set.

**Why** [CONFIRMED FROM CODE] — The only close site in the entire Chart tree is `CloseOwned` (`SSR_ChartManager.mqh:292`; `grep ChartClose` finds no other), called only inside `if(user_removed)` (2202-2206). `OpenChart` (204-215) is an unconditional `ChartOpen` + `NoteOwned` with no search for an existing chart on that symbol/period. The next pass's `g_charts` is a freshly constructed object, so the previous ids are no longer owned, and `CSSRLeakGuard` only counts charts (44-63) — it never closes one.

**Verifiers** — Confirmed by trace; the deliberate keep-the-symbol behaviour at 2115-2122 was never extended to the windows.

**Fix** [RECOMMENDATION] — Make `OpenChart` idempotent and let re-init adopt rather than re-open: before `ChartOpen`, walk `ChartFirst()`/`ChartNext()` for a chart whose `ChartSymbol()` equals `m_symbol` and `ChartPeriod()` equals `tf`, and `NoteOwned` that id instead. That single change fixes both the leak and the lost follow policy, and it costs one enumeration per opened chart at init. Additionally close owned windows on `REASON_INITFAILED`, which is unambiguously not a user action: `if(user_removed || reason == REASON_INITFAILED) g_charts.CloseOwned();`.

##### `host-expert-7` — MEDIUM — keys are not withheld while the Sessions or Jump dialog is open

**File:** `SSReplayStandalone.mq5:3167` · **Category:** event-handling

```mql5
   if(g_session_dlg.IsOpen())
     {
      if(g_session_dlg.OnEvent(id, lparam, dparam, sparam))
        { g_panel.Render(); return; }
     }
...
   if(g_panel.OnEvent(id, lparam, dparam, sparam))   // line 3228
```

**Failure scenario** (verifiers' corrected version) [CONFIRMED FROM CODE] — The user presses `S` to open the saved-sessions list, then presses Space (or Tab, or an arrow). `CSSRSessionDialog::OnEvent` returns false for anything that is not `CHARTEVENT_OBJECT_CLICK`, so the key falls through both dialog blocks, past the reveal/review guard (which covers only those two cards), into `g_panel.OnEvent` at 3228, which executes the command and repaints. **The replay starts running, or Tab opens a virtual trade, underneath a dialog the user is reading**; pressing `0` arms the session reset the same way. The z-order half of the finder's claim is overstated: widget primitives create only when `ObjectFind < 0` and `OBJPROP_ZORDER=100` governs click priority, not paint order, so objects created before the dialog stay behind it. What can land on top is the subset `Render()` actively removes and recreates — the per-position rows and tab-dependent controls (`SSR_Panel.mqh:659, 900-906, 932-934, 1168-1243, 1318-1339, 1603-1645, 1721, 1835-1852`) — which includes the rows for the trade Tab just opened.

**Why** [CONFIRMED FROM CODE] — `SSR_SessionDialog.mqh:227-228`: `if(m_mode == SSR_SD_CLOSED || id != CHARTEVENT_OBJECT_CLICK) return false;`. The range dialog block at 3177 behaves identically. The panel acts on any key it owns (`SSR_Panel.mqh:2854-2876`), returning false only for the four commands `Owns()` excludes. The exactly correct predicate already exists one screen away, at 2888: `bool modal = (g_session_dlg.IsOpen() || g_dialog.IsOpen() || g_reveal.IsUp() || g_review.IsUp());` — used to gate `PollClicks` and `Render`, but not the keydown guard at 3217-3226, which lists only the two cards.

**Verifiers** — Verified end to end; only the z-order consequence needed narrowing.

**Fix** [RECOMMENDATION] — Reuse the predicate that is already written. Hoist `modal` out of the timer into a small helper `bool SSRModalUp()` and put it at the top of the keydown guard: `if(id == CHARTEVENT_KEYDOWN && SSRModalUp()) return;` — placed before 3228 and after the two dialogs have had their chance to claim clicks. Escape should stay live, so exempt it explicitly. Nothing else changes, and the dialogs keep their click-only event surface, which is all MQL5 gives the replay chart anyway.

#### C.5.2 Core engine - `MQL5/Include/SSReplay/Core`

##### `core-engine-5` — MEDIUM — `bars_consumed` counts a bar once per pump that touches it

**File:** `SSR_ReplayController.mqh:472` · **Category:** boundary

```mql5
         bars_used++;
         m_cursor.NoteBar(SSRToMsc(m_bars[i].time));

         if(keep > 0)
           {
```

**Failure scenario** (verifiers' corrected version) [CONFIRMED FROM CODE] — `EmitWindow` re-reads and re-synthesises the M1 bar containing `now` on every pump (it must, for `ClipBar`), and `bars_used++` runs unconditionally for every bar read. At 1x with `InpPumpMs=40` (~25 pumps/s) one replay minute adds ~1500 to `bars_consumed`; at 100x each bar is counted ~15 times. The Stats tab's "Bars" line (`SSR_Panel.mqh:1687`, via `GroupPort.BarsConsumed()`) is therefore meaningless, and `SpreadBarsRecorded`/`SpreadBarsFixed` inflate identically. Two refinements: the legacy bar-count warning at 1858-1863 fires only for session files written without a fingerprint — `SaveInto` always emits one when `FingerprintUpTo` succeeds — so it is a compatibility path, not the normal resume; and `SpreadAverage()` is not scaled but becomes a pump-count-weighted mean instead of a plain one.

**Why** [CONFIRMED FROM CODE] — Per pump `lo = emitted+1`, `hi = now`, so at 40 ms both `bar_lo` and `bar_hi` floor to the same current M1 open; `ReadBars` returns `nb==1`, the skip loop at 388-389 leaves `first==0` (the bar's time equals `bar_lo`, not `<`), and the loop at 437 runs once. `bars_used++` at 472 sits **before** the `if(keep > 0)` block, so it increments even on a pump whose ticks were all already emitted. Line 531 `Advance(consumed_to, emitted, bars_used)` does `bar_count += bars`, and `Publish()` copies it into `m_state.bars_consumed` (185).

**Verifiers** — Reproduced by hand from the cursor arithmetic.

**Fix** [RECOMMENDATION] — Count a bar when it is finished, not when it is touched. `m_cursor.NoteBar(open_msc)` already receives the bar's open — give the cursor a `long m_last_noted_open;` and increment `bar_count` inside `NoteBar` only when the open differs from the last one noted. That fixes this finding, `core-sync-2` and `core-sync-4`'s downstream inflation in one place, and leaves `bars_used` free to keep meaning "bars touched this pump" for the budget arithmetic that legitimately needs it.

##### `core-engine-6` — MEDIUM — warmup "bars" are calendar minutes

**File:** `SSR_ReplayTimeline.mqh:80` · **Category:** boundary

```mql5
      long want = start_msc - bars * SSR_MSC_PER_MIN;
      if(data_first_msc > 0 && want < data_first_msc)
         want = data_first_msc;
      warmup_first_msc = want;
```

**Failure scenario** (verifiers' corrected version) [CONFIRMED FROM CODE] — `SetWarmupBars(1000)` subtracts 1000 calendar minutes (16h40m) rather than walking back 1000 existing M1 bars. A Monday 02:00 start on forex reaches back to Sunday 09:20, where no bars exist, so the seeded warmup is ~240 bars instead of 1000 (~390 on a 6.5 h/day CFD): a factor of 2-4 less indicator context than asked for. The finder's "H4 chart opens empty" is overstated — 1000 M1 bars is only 16h40m even when every minute exists, so an H4 chart gets ~4 candles either way. It is not fully silent either: `SeedWarmup` logs "warmup seeded: N bars" at Info level (`SSR_ReplayController.mqh:902-904`).

**Why** [CONFIRMED FROM CODE] — Line 80 is pure time arithmetic on `start_msc`; `SeedWarmup` (880-885) then reads bars whose open lies in `[warmup_first, start-1]`, so every non-quoting minute in that span yields nothing. `WarmupBarsFor` (94-100) and `CSSRHistoryCatalog::WarmupFor` (126-132) share the arithmetic, so the setup panel's quoted cost is in minutes too. No caller converts a bar count through the data — the host passes `InpWarmupBars` straight in at 498 and 1149 — even though it already counts the *replay* window in real bars via `CopyRates` (1078-1085) for exactly this reason.

**Verifiers** — Same unit conflation as `data-4`, one layer down.

**Fix** [RECOMMENDATION] — Ask the data, as the replay window already does. Add `long SSRBarsBackMsc(const string sym, const long from_msc, const int bars)` next to the existing `CopyRates` helper in the host, implemented as one `CopyRates(sym, PERIOD_M1, from_time, bars, rates)` and returning `rates[0].time`; call it in `SetWarmupBars` when a provider is available, keeping the current arithmetic as the fallback when it is not. Do the same in `WarmupFor` so the setup panel's estimate matches what is seeded, and keep the Info log line — it becomes a genuine check rather than the only clue.

##### `core-sync-2` — MEDIUM — spread statistics count synthesis calls, not bars

**File:** `SSR_TickSynthesizer.mqh:54` · **Category:** spread

```mql5
   double            SpreadFor(const MqlRates &bar)
     {
      if(m_spread_mode == SSR_SPREAD_RECORDED && bar.spread > 0)
        {
         double pts = (double)bar.spread;
         m_bars_recorded++;
```

**Failure scenario** (verifiers' corrected version) [CONFIRMED FROM CODE] — At SYNTHETIC or BAR fidelity, 1x, 40 ms pumps, every pump re-synthesises the current bar, so a single M1 bar increments `m_bars_recorded` or `m_bars_fixed` ~1500 times. `ReportSpreadOnce` (`SSReplayStandalone.mq5:2239-2300`) waits for "total ≥ 120 bars", reaches it inside the **first** bar after ~5 s, and then prints "from the data on N of the first M bars" with N and M in the thousands for a handful of bars. The author tells users to send that exact line as the diagnostic for whether their history carries a spread. `AverageRecordedSpread` becomes pump-weighted — bars stepped through or replayed slowly weigh hundreds of times more than bars replayed at 30x — while `WidestRecordedSpread`, being a running maximum, is undistorted.

**Why** [CONFIRMED FROM CODE] — `SpreadFor` is unconditional inside `Synthesize` (123) and `SynthesizeClose` (197) and counts a call. The controller re-reads the clock's own bar every pump (`bar_lo = SSRBarOpenMsc(emitted+1)`, 380; the skip loop's `< bar_lo` does not exclude it, 408) and trims ticks to `(lo, hi]` afterwards. The only test of these counters (QA smoke 2985-3001) calls `Synthesize` directly three times and cannot see the inflation.

**Verifiers** — Same root cause as `core-engine-5`; only `WidestRecordedSpread` survives.

**Fix** [RECOMMENDATION] — Count once per distinct bar: keep `long m_last_spread_open;` in the synthesizer and increment `m_bars_recorded`/`m_bars_fixed` and accumulate `m_spread_sum_pts` only when `SSRToMsc(bar.time) != m_last_spread_open`. One `long` compare on a path that already does floating-point work. Reset it in the same place the counters are reset. The panel and the host diagnostic then report what their wording promises, and `AverageRecordedSpread` becomes a plain per-bar mean.

#### C.5.3 Data layer - `MQL5/Include/SSReplay/Data`

##### `data-4` — MEDIUM — `warmup_bars` is used as both a bar count and a span of minutes

**File:** `SSR_HistoryCatalog.mqh:150` · **Category:** boundary

```mql5
      q.available_bars  = m_range.bar_count;
      q.exceeds_history = (m_range.available && q.total_bars > m_range.bar_count);
```

**Failure scenario** (verifiers' corrected version) [CONFIRMED FROM CODE] — The conflation produces a **false "not enough history" refusal** in the range dialog for deep-timeframe context on instruments that do not quote 24 h, plus an over-conservative earliest-start floor. Take an index CFD quoting ~6.5 h/day (~1,950 M1 bars/week) for which the broker holds 2 years ≈ 203,000 bars, and a D1 request with `visible_bars=200`: `WarmupFor(PERIOD_D1,200) = 200 * 1440 = 288,000`, `exceeds_history` is true, and `SSRValidateRange` returns "not enough history: needs 290000 M1 bars, broker has 203000" — refusing a start that 500 trading days of history comfortably supports. `CSSRRandomPicker` skips the same symbol via `LatestStart`/`EarliestStart`. It does **not** shorten the seeded warmup in the shipped host, which takes `InpWarmupBars` through `SSR_ReplayTimeline` instead (that is `core-engine-6`), and the default H1/300 request never trips the refusal.

**Why** [CONFIRMED FROM CODE] — `WarmupFor` (126-132) returns `visible * (secs/60)`, the number of **minutes** those candles span on a 24 h clock. `Quote` compares it against `m_range.bar_count`, which `Discover` fills from `SERIES_BARS_COUNT` (`SSR_Mt5Providers.mqh:99, 131`) — bars that exist, not minutes elapsed. `EarliestStart`/`LatestStart` (161-175) multiply the same number by `SSR_MSC_PER_MIN`, treating it as elapsed time. The two readings coincide only for an instrument quoting every minute of every day, and the code has no notion of quote density anywhere. `SSR_T6_History.mq5:39-47` asserts only the arithmetic of `WarmupFor` itself, never that the result is usable as either unit.

**Verifiers** — Provable unit conflation; the coverage gap is in the test's premise, not its arithmetic.

**Fix** [RECOMMENDATION] — Introduce the missing factor once and use it in both directions. `Discover` already has `bar_count`, `first_msc` and `last_msc`, so compute `double density = bar_count / ((last_msc - first_msc) / 60000.0)` (bars per calendar minute, clamped to `(0,1]`) and store it on the range. `Quote` then compares `total_bars` against `bar_count` as a bar count, and `EarliestStart` spans `warmup_minutes / density` calendar minutes. That turns both a false refusal and a silent shortfall into one honest number, and it is measured from the broker's own history rather than assumed. Extend `T6` to assert that a range with density 0.27 (a 6.5 h/day instrument) accepts a D1/200 request that the current code refuses.

#### C.5.4 MT5 bridge - `MQL5/Include/SSReplay/Mt5`

##### `mt5-symbol-3` — MEDIUM — `Create()`'s adopt fallback uses the existence test `Adopt()` documents as wrong

**File:** `SSR_CustomSymbolManager.mqh:338` · **Category:** broker-symbol

```mql5
ResetLastError();
bool exists = (SymbolInfoInteger(m_symbol, SYMBOL_DIGITS) > 0 &&
               GetLastError() == 0);

if(!exists || !SSRIsReplaySymbol(m_symbol))
  {
```

**Failure scenario** (verifiers' corrected version) [CONFIRMED FROM CODE] — Origin is a whole-point instrument (`SYMBOL_DIGITS == 0` — the US30 case the `Adopt` comment at 434-450 records). `Destroy()` at 318 fails to remove a leftover replay symbol (a chart still open on it, or the `ChartClose` race the header describes), `CustomSymbolCreate` then fails because the name exists, and the fallback evaluates `exists=false` because DIGITS is 0. `Create` returns `SSR_ERR_INTERNAL "CustomSymbolCreate(...) failed"` and the session dies with `SINK_FAILED` instead of adopting and clearing the leftover as the comment at 332-336 intends. The finder's coverage claim is wrong in the *worse* direction: `T3.7` does not exercise this fallback on **any** instrument, because with no chart open the `CustomSymbolDelete` normally succeeds and the second `Create` takes the ordinary path — the fallback is untested everywhere.

**Why** [CONFIRMED FROM CODE] — The `Adopt()` comment 100 lines later explicitly records that "≤ 0 digits" was misread as "no such symbol" and replaced the test with `SYMBOL_EXIST` plus `SYMBOL_CUSTOM`; the old test survived unchanged in `Create`'s fallback. The fallback also omits the `SYMBOL_CUSTOM` check, so it is simultaneously stricter (digits) and looser (ownership) than `Adopt`.

**Verifiers** — Both paths read in one file; the fix is already written 100 lines below.

**Fix** [RECOMMENDATION] — Call the code that got it right. Replace the three lines with the same pair `Adopt()` uses — `bool exists = ((bool)SymbolInfoInteger(m_symbol, SYMBOL_EXIST) && (bool)SymbolInfoInteger(m_symbol, SYMBOL_CUSTOM));` — or better, have the fallback simply `return Adopt();` so there is one existence test in the class rather than two. Then give `T3.7` the precondition it lacks: open a chart on the leftover symbol before the second `Create` so `Destroy` genuinely fails and the fallback runs.

#### C.5.5 Chart layer - `MQL5/Include/SSReplay/Chart`

##### `chart-4` — MEDIUM — blind mode's record of the user's original chart settings does not survive a re-init

**File:** `SSR_BlindMode.mqh:152` · **Category:** session-resume

```mql5
      if(Find(chart_id) < 0)
        {
         if(m_saved >= SSR_BLIND_MAX_CHARTS)
            return false;
         int i = m_saved++;
         m_had_dates[i]  = (bool)ChartGetInteger(chart_id, CHART_SHOW_DATE_SCALE);
```

**Failure scenario** (verifiers' corrected version) [CONFIRMED FROM CODE] — One-chart mode, `InpBlind=FULL`, chart correctly blinded and correctly recorded on pass 2. The user then changes the timeframe — the product's headline feature — or an input, or the EA recompiles: `REASON_CHARTCHANGE`/`REASON_PARAMETERS`/`REASON_RECOMPILE`, and `OnDeinit` calls `RestoreAll()` only inside `if(user_removed)` (2152, 2176). The chart stays blind while the instance, and with it `m_id`/`m_had_*`, is destroyed. The rebuilt instance starts with `m_saved=0`, `Apply()` finds the chart absent and records the **already hidden** properties as the originals. From then on `Restore()` writes `false` back, so when the user finally removes the tool their chart keeps no date scale, no OHLC line and no price scale, and they must re-enable three chart properties by hand — precisely the trap the class header (22-24) exists to avoid. There is a second path to the same place: if the rebuilt instance never calls `BuildSession`, `m_policy` is never set, `RestoreAll()` is a no-op over an empty registry, and the chart stays blind with no record at all.

**Why** [CONFIRMED FROM CODE] — The save-once guard is keyed on `Find(chart_id)` within the live instance only, and nothing persists `m_had_dates`/`m_had_ohlc`/`m_had_price` — a repo-wide grep for `CHART_SHOW_DATE_SCALE` matches only this file and the QA smoke. The chart properties are terminal state and outlive the program, so after a re-init the "before" state is unrecoverable. One-chart mode guarantees at least one re-init per session (the handover); that first one is harmless only because pass 1 has no chart on the replay symbol yet.

**Verifiers** — Every link present in source, plus the second (no-record) path.

**Fix** [RECOMMENDATION] — Persist the three booleans where they survive the program: `GlobalVariableSet("SSR_BLIND_" + IntegerToString(chart_id) + "_D/O/P", …)` written at first `Apply` and deleted at `Restore`. They are terminal globals, which is exactly the lifetime needed, and three per chart is trivial. On `Apply`, if a global exists for this chart, adopt it instead of reading the current (blinded) state — that closes the poisoning path. Additionally call `RestoreAll()` on every deinit reason **except** the handover pass, which is identifiable by the same `will_hand_over` local proposed in `host-expert-3`; that closes the second path and means a crash or recompile never leaves a user's chart blinded.

##### `chart-3` — MEDIUM — the blind-mode reveal is undone within ~200 ms

**File:** `SSR_BlindMode.mqh:203` · **Category:** session-resume

```mql5
      while(m_saved > 0)
         if(Restore(m_id[0]))
            n++;
         else
            break;
      m_applied = false;                 // m_policy untouched
```

**Failure scenario** [CONFIRMED FROM CODE] — `InpBlind=STANDARD` or `FULL`, the session reaches `SSR_STATE_COMPLETED`, the user presses the reveal card. `Expert:3021` calls `RestoreAll()`, which puts the date scale (and in FULL the price scale and OHLC) back and clears `m_applied` — but not `m_policy`. The housekeeping block runs unconditionally every 5th timer tick (2807-2808, outside the `if(playing)` guard) and tests `IsOn()`, not `IsApplied()`: `if(g_blind.IsOn()) for(...) g_blind.Apply(g_charts.IdAt(bi));`. `Apply()` re-hides everything on the next pass. The scales come back for at most one 200 ms frame and vanish again, so the payoff of a blind session — reviewing the chart you just traded, with its dates restored — never happens. The chart only truly returns when the EA is removed.

**Why** [CONFIRMED FROM CODE] — `IsOn()` returns `m_policy.AnyOn()` (136) and nothing in the class's public surface can clear `m_policy`: there is no `Off()`/`ClearPolicy()`, and `SetPolicy` is called once, in `BuildSession` (1002). `Apply()` is idempotent by design (152-165) and re-saves the freshly restored state as the new "original", so the record stays correct while the visible state flips back to blind. The reveal block and the housekeeping block are in the same timer pass — no function boundary or bare `return` separates 2715 from 3070.

**Verifiers** — Control flow verified within the single timer pass.

**Fix** [RECOMMENDATION] — Make the reveal a state, not a one-off call. Add `void Reveal() { RestoreAll(); m_revealed = true; }` and `bool IsRevealed() const { return m_revealed; }`, set the flag from the reveal card, and change the housekeeping test at 2822 to `if(g_blind.IsOn() && !g_blind.IsRevealed())`. `SetPolicy` clears `m_revealed`, so a new session blinds again. One member, one guard — and it keeps `Apply`'s idempotence, which the rest of the housekeeping relies on.

##### `chart-5` — MEDIUM — blind FULL omits the price level from its own disclosure while the price is always on screen

**File:** `SSR_BlindMode.mqh:243` · **Category:** incomplete disclosure (not future-data-leakage — verifiers' correction)

```mql5
      if(m_policy.hide_dates)
         s += "the date under the crosshair and in the Data Window; ";
      if(!m_policy.hide_price_scale)
         s += "the price level, which identifies the period on an "
              "instrument you know well; ";
```

**Failure scenario** (verifiers' corrected version) [CONFIRMED FROM CODE] — `InpBlind=SSR_BLIND_FULL` sets `hide_price_scale=true`, so `Leaks()` omits the price clause — under the class's own stated ethic (list every leak it cannot close, 233-237) that understates what remains visible. The absolute price is shown on the panel's Buy/Sell buttons at all times (`SSR_Panel.mqh:1479-1484`, `Price(ask)`/`Price(bid)`, unconditional) and permanently on each position's entry line once a trade is taken: `SSR_TradeLines.mqh:413-422` writes "BUY 0.20 at 4438.48" as the object description, with `CHART_SHOW_OBJECT_DESCR` forced on by `Attach` (183). A trader who chose FULL precisely because they would recognise the period from its price levels reads an exact price the moment they glance at the deal buttons. `Leaks()` does not *assert* the price is hidden — it simply says nothing, which is the failure for a disclosure instrument.

**Why** [CONFIRMED FROM CODE] — `CSSRTradeLines` has no knowledge of blind mode: it takes prices and formats them with `m_digits`. The panel's price formatting is not routed through `MaskTime`/`MaskSymbol` either — `GroupPort:180-184` masks only the clock text and the symbol name.

**Verifiers** — All three code sites read; the category, not the fact, needed correcting.

**Fix** [RECOMMENDATION] — Two halves. Honesty: drop the `!hide_price_scale` gate and always append a price clause, worded for each case ("the price scale is hidden, but the deal buttons and any entry line still print the exact price"). Substance: give `CSSRTradeLines` and the panel a masking hook — `GroupPort` already owns `MaskTime`/`MaskSymbol`, so add `MaskPrice(double)` returning `"·····"` under FULL and route the deal-button text and the `tip` string through it. Prices on the buttons are the only ones a trader must act on, so an optional `InpBlindShowDealPrice` is a reasonable escape hatch; the entry-line description has no such excuse.

##### `chart-2` — MEDIUM — secondary-symbol charts are never redrawn

**File:** `SSR_ChartManager.mqh:574` · **Category:** multi-symbol

```mql5
if(advanced && m_charts[i].follow && !m_charts[i].user_detached &&
   ViewOffset(m_charts[i].id) > 0)
  {
   ChartNavigate(m_charts[i].id, CHART_END, 0);
   m_charts[i].last_offset = 0;
   m_snaps++;
  }
```

**Failure scenario** (verifiers' corrected version) [CONFIRMED FROM CODE] — With `InpAlsoSymbols` set, each extra stream gets its own `CSSRChartManager`, and the host calls `g_charts2[i].Sync()` (2830) but never `Redraw()` — an exhaustive grep of `g_charts2` finds Configure, OpenChart, OpenLayout, IdAt, CloseOwned, FollowAll and Sync, and nothing else. So no explicit `ChartNavigate(CHART_END)` and no `ChartRedraw` ever reaches a secondary chart, and their per-instance bar tracking (`m_last_bar_time`, `m_snaps`) is never updated. The consequence the verifiers could prove from source is the worse one: with `m_last_bar_time` untouched the offset on those charts is never zeroed, so their own `DetectScroll` eventually detaches them and turns `CHART_AUTOSCROLL` **off** — a possible drift becomes a guaranteed frozen view. The view otherwise depends entirely on `CHART_AUTOSCROLL`, which this file documents (509-521) as not reliably honoured on an EA-written custom symbol, and at BAR fidelity no tick arrives to repaint — the host's own comment at 2825-2827 says `Redraw` "is the only thing that moves the chart at bar fidelity".

**Why** [CONFIRMED FROM CODE] — `Redraw()` is per-instance state and per-instance work; nothing inside the class reaches other instances, and the primary manager is the only one the host redraws — at 2825, immediately above the `g_charts2` Sync loop. Secondary charts do get one `ChartNavigate` per play press via `FollowAll()` (2780), so they snap once per Play and drift thereafter. `Snaps()`/vitals report `g_charts` only, so nothing measures it.

**Verifiers** — Asymmetry provable by grep; the freeze via `DetectScroll` is the source-provable half.

**Fix** [RECOMMENDATION] — One line at 2830: `for(int i = 0; i < g_streams2; i++) { g_charts2[i].Sync(); g_charts2[i].Redraw(); }`. `Redraw` is already rate-limited internally by `m_last_redraw_us`, so the cost is bounded and identical to the primary path. Then widen the instrument: have the host sum `Snaps()` across `g_charts` and `g_charts2` for vitals, so a future asymmetry shows up as a number rather than as a still picture.

#### C.5.6 Trading and risk - `MQL5/Include/SSReplay/Trading`

##### `trading-analytics-4` — MEDIUM — the class report classifies wins from the CSV's raw profit column

**File:** `SSR_Journal.mqh:82` · **Category:** commission

```mql5
p.profit, p.commission, p.swap,
         //--- R is left EMPTY, never zero, when it does not exist:
```

**Failure scenario** (verifiers' corrected version) [CONFIRMED FROM CODE] — The three-column CSV layout (profit / commission / swap) is defensible — MT5's own statement uses it. The defect is that its only consumer classifies with the wrong column: `SSR_ClassReport.mqh:259-266` derives won/lost from raw `profit`, while the journal and `SSR_Statistics` define a result as `profit + swap - commission`. With `InpCommission=3` and a 1-lot trade that made +2, the statement counts a loss (net -4 after both sides) while the class report marks it **won**, and the CSV's `# net_profit` header no longer equals the sum of its own `profit` column — the exact contradiction the comment at `SSR_Statistics.mqh:405-427` records being fixed for the HTML (394) and not for the CSV. With the default commission 0 and swap 0 all three agree, which is why no test catches it.

**Why** [CONFIRMED FROM CODE] — `Row()` writes `p.profit` raw with no net column; `ExportHtml` computes `net = p.profit + p.swap - p.commission` (394) and `ComputeFor` uses the same net for wins and losses (`SSR_Statistics.mqh:429-448`). `ClassReport::ReadOne` locates only `open_time`, `profit` and `r` (243-245). Commission really is charged twice per round trip (Open 753, closing leg 203/218).

**Verifiers** — Layout exonerated, consumer convicted.

**Fix** [RECOMMENDATION] — Cheapest correct change: teach `ReadOne` to find the `commission` and `swap` columns it already has in front of it and compute `pnl = profit + swap - commission` before `out.won = (pnl > 0.0)`. If the reader must stay single-column, add a `net` column to `Row()` and the header and have `ReadOne` prefer it when present — but then also keep reading old exports correctly, which the combine-three-columns version does for free.

##### `trading-analytics-12` — MEDIUM — a jump forward never runs the prop evaluation

**File:** `SSR_PropEvaluation.mqh:358` · **Category:** prop-rules

```mql5
virtual void      OnClock(const long now_msc) override
     {
      if(!m_rules.enabled || m_state != SSR_PROP_RUNNING || m_acct == NULL)
         return;
```

**Failure scenario** (verifiers' corrected version) [CONFIRMED FROM CODE] — Evaluation running with `max_days=30` on day 20; the user jumps to the end of the window 15 replay days later. `JumpForward` bulk-writes the bars, transitions to COMPLETED and never publishes `OnClock`; `Pump()` returns 0 once the status is not PLAYING, so no `OnClock` ever fires again and the verdict stays **IN PROGRESS** — visible in the HTML statement (`SSR_Journal.mqh:286-297`) and on the panel's prop sheet (not on the review card, which carries no prop fields). When the forward jump does *not* complete the replay the next pump does judge, because `RollDay` recomputes `m_total_days` from the new day index — so the deadline fires late rather than never; what is permanently lost either way is **any breach or target reached inside the skipped span**, since equity is sampled only at the jump's end. During normal play the rules are judged once per pump, after all its ticks, not per tick.

**Why** [CONFIRMED FROM CODE] — A full grep finds exactly two `OnClock` fan-out sites, `SSR_ReplayController.mqh:1027-1029` (Pump) and 1102-1104 (PumpTo). `JumpForward` (1333-1419) does `SeedBars`, `EmitWindow` for the partial bar, `OnSeek`, `RepairWarmupIfLost`, `Publish` and `Transition(COMPLETED)` with no observer `OnClock` loop and no `CheckObserverPause`. The evaluation overrides only `OnClock`/`OnRewind`/`OnSessionStart`, so published ticks do not reach it at all. `JumpTo` is the documented "unified entry point: the panel and the dialog both call this".

**Verifiers** — Provable; the two refinements above are theirs.

**Fix** [RECOMMENDATION] — Publish a clock at the end of every jump. In `JumpForward`, after the final `EmitWindow` and before `Transition`, add the same fan-out `Pump` uses: `for(int i = 0; i < m_obs_count; i++) m_obs[i].OnClock(m_clock.now_msc);` followed by `CheckObserverPause()`. That judges the deadline and any equity breach standing at the jump's end and lets an observer pause the jump's completion. It does not recover a breach that occurred *inside* the skipped span — that needs `core-engine-3`'s per-bar publication, which is the proper fix for the whole family.

##### `trading-analytics-2` — MEDIUM — prop evaluation state is not persisted

**File:** `SSR_PropEvaluation.mqh:366` · **Category:** session-resume

```mql5
if(!m_started)
        {
         m_started     = true;
         m_first_day   = now_msc / SSR_PROP_DAY_MSC;
         m_day         = m_first_day;
         m_day_open_eq = eq;
         m_peak_eq     = eq;
```

**Failure scenario** (verifiers' corrected version) [CONFIRMED FROM CODE] — Trailing rules, start 10000, trader at 9400 after two sittings, 25 of 30 days used. After a resume — and the Reset that `trading-analytics-1` forces — the first `OnClock` sets `m_peak_eq=9400`, `m_total_days=1`, `m_trading_days=0`, `m_day_open_eq=9400`. `TotalFloor` becomes 8400 instead of 9000, the deadline restarts at day 1 of 30, the minimum-days count restarts at 0, and the daily floor is measured from the resumed equity. The verdict then differs from what the same trades produce in one sitting. Sequencing matters: immediately after a resume the evaluation is already VOID, so `OnClock` early-returns at 360 and the re-basing takes effect only once the user presses Reset. The omission is an acknowledged design gap (`docs/audit/maps/ui-port-session.md:247-248`, "Not stored: … the prop evaluation"), not an accident; the wrong verdict is real either way.

**Why** [CONFIRMED FROM CODE] — The class has no `SaveInto`/`RestoreFrom` (grep of the file). `SSR_SessionManager.mqh:195-200` and 367-375 save and restore only `m_acct` and `m_stats`. `Reset()` (327-341) and the first-clock branch (366-377) initialise every counter from `m_rules.start_balance` or current `Equity()`. The account and the equity curve *are* restored, so the account carries its history while the judge forgets it.

**Verifiers** — Traced; the design-decision note is theirs.

**Fix** [RECOMMENDATION] — Give the class the two methods every other stateful observer has. `SaveInto(CSSRSessionFile &f)` writing one `[prop]` section — `started, first_day, day, day_open_eq, peak_eq, low_eq, trading_days, total_days, state, reason` — and `RestoreFrom` reading it back, with `m_started` gating the first-clock re-base. `CSSRSessionManager` then calls them beside `m_acct`/`m_stats` at 195-200 and 367-375. Ten scalars and one string; the session file already carries far more. With `trading-analytics-1` fixed so a resume does not VOID the evaluation, this makes a multi-sitting challenge behave like a single one, which is the entire point of the feature.

##### `trading-analytics-3` — MEDIUM — closed-only drawdown walks trades in open order

**File:** `SSR_Statistics.mqh:703` · **Category:** drawdown-calc

```mql5
for(int i = 0; i < total; i++)
        {
         SSRVirtualPosition p;
         if(!m_acct.At(i, p) || !p.IsClosed())
            continue;
         bal += p.profit + p.swap - p.commission;
```

**Failure scenario** (verifiers' corrected version) [CONFIRMED FROM CODE] — Three overlapping trades in slot order A (net -100, opened first, closed last), B (+1000), C (-500). The real balance path 10000 → 11000 → 10500 → 10400 has a closed drawdown of 600; the loop visits A, B, C and computes 9900 → 10900 → 10400, reporting **500**. The statement's "Max drawdown, closed only" — and the gap it asks the reader to compare against the equity drawdown — is wrong whenever positions overlap. The finder's secondary remark about `win_streak`/`loss_streak` is weaker: counting streaks by entry order is a defensible convention, so only the balance-curve drawdown (and `trading-analytics-7`'s revenge detection) is provably wrong.

**Why** [CONFIRMED FROM CODE] — `At(i)` is a straight slot read (`SSR_TradingEngine.mqh:1004-1011`) with slots appended in `Open()` order (719) and never sorted or compacted — the engine contains no `ArraySort` or compaction. Nothing orders by `p.close_msc`, and slot order is not even open order for pendings, whose `open_msc` is stamped at request time (734). `T10.2` (`SSR_T10_Statistics.mq5:204`) checks only a sequential, non-overlapping case.

**Verifiers** — Confirmed for `max_drawdown_closed`; streak claim trimmed.

**Fix** [RECOMMENDATION] — Sort by close time before walking. Build a local index array of closed slots, insertion-sort it on `close_msc` (positions are bounded by the engine's capacity, so an O(n²) sort is free at these sizes and avoids adding a dependency), then accumulate `bal`, `peak` and `worst` in that order. Extend `T10.2` with exactly the three-overlapping-trades case above and assert 600 — the test that would have caught it.

##### `trading-exec-5` — MEDIUM — the ambiguity test charges pre-entry excursion to the position

**File:** `SSR_TradingEngine.mqh:164` · **Category:** sl-tp-execution

```mql5
if(p.IsLong())
  {
   sl_in = (m_bar.low  <= p.sl);
   tp_in = (m_bar.high >= p.tp);
  }
...
return (sl_in && tp_in);
```

**Failure scenario** (verifiers' corrected version) [CONFIRMED FROM CODE] — `BarIsAmbiguousFor` (164-174) tests the whole cached M1 range, which includes price printed **before** a mid-bar entry. Buy the breakout at tick 3 with a tight stop 10 points under the entry while tick 2 has already printed a low 30 points lower, and put the target inside the bar's high: `CheckStops` 537-541 books `SSR_CLOSE_SL` at `StopFill` and flags the trade ambiguous, although every tick from the entry onward was above the stop. Note the finder's own illustration ("SL 5 points below that bar's low") does **not** trigger it — with `sl` below the bar low, `sl_in` is false. The same whole-bar test at 371-384 flags a pending fill against a low printed before the fill.

**Why** [CONFIRMED FROM CODE] — `m_bar` is the bar cached by `OnBarContext` (593-598); `ClipBar` trims it only to the pump window's end (controller 446-459), so within one emitted segment it is the full minute including the part an earlier pump already emitted. `BarIsAmbiguousFor` (141-175) never compares `open_msc` against the ticks already seen, and never uses `mae` (293-300), which already records the worst move **since entry**. The pessimism policy the design comment (9-20) describes does not claim to apply to price that occurred before the position existed.

**Verifiers** — Mechanism provable; trigger shape corrected.

**Fix** [RECOMMENDATION] — Use the excursion you already track. For an open position, replace `m_bar.low`/`m_bar.high` with the post-entry extremes: `double lo = (p.open_msc > SSRToMsc(m_bar.time)) ? p.open_price - p.mae_price_move : m_bar.low;` — or more simply, give the engine two members `m_bar_lo_since`, `m_bar_hi_since` updated per tick in `OnTicks` and reset at each `OnBarContext`, and have `BarIsAmbiguousFor` prefer them for any position whose `open_msc` falls inside the current bar. The fill-time flag at 371-384 takes the same treatment with the pending's fill instant. Pessimism is preserved for everything that happened while the position was live, which is the honest version of the policy.

##### `trading-exec-6` — MEDIUM — no margin check on entry when margin is modelled

**File:** `SSR_TradingEngine.mqh:741` · **Category:** margin

```mql5
bool is_long = SSRIsLong(type);
m_pos[i].state        = SSR_POS_OPEN;
m_pos[i].open_price   = FillPrice(is_long, true);
...
m_pos[i].commission = m_exec.commission_per_lot * volume;
m_balance          -= m_pos[i].commission;
```

**Failure scenario** (verifiers' corrected version) [CONFIRMED FROM CODE] — `InpMarginLot=1000`, `InpStopout=50`, balance 10000, commission 7/lot, slippage 10. `Open(BUY, 50.0)` — reachable via the Publisher's external trade path or a large risk percent — is accepted, 350 of commission is charged, `UsedMargin` is 50000 and the margin level 19 % < 50, so `CheckStopout` liquidates on the very next tick with another 350 of commission and 50 lots × 10 points of slippage: several hundred lost plus spread for an order a real terminal rejects with "not enough money" at zero cost. The stopout counter and the auto-pause "stop out" fire for a trade that should never have existed. Opt-in: both `InpMarginLot` and `InpStopout` default to 0, so this is a fidelity gap in the margin model rather than a default-path defect.

**Why** [CONFIRMED FROM CODE] — `Open()` (705-756) checks capacity, `Reserve`, `volume > 0`, `m_bid > 0` and, for pendings, `price > 0` — nothing else — then fills and debits commission at 753-754. `OpenWithRisk`/`OpenPendingWithRisk` (759-801) add only lot-sizing checks. `FreeMargin()` (946) and `MarginLevel()` (949) exist and no caller in the engine, `GroupPort`, the Publisher or the strategy host gates an entry on them. `CheckStopout` (436-470) runs from `OnTicks` 613 — after the fill.

**Verifiers** — Confirmed; scope narrowed to the opt-in configuration.

**Fix** [RECOMMENDATION] — Reject before booking, using the two accessors already written. In `Open()`, immediately after the volume check:

```mql5
   if(m_exec.margin_per_lot > 0.0 &&
      volume * m_exec.margin_per_lot > FreeMargin())
     { m_last_error = "not enough money"; return 0; }
```

Return the same falsy ticket the other refusals return, so every caller's existing error path handles it, and surface `m_last_error` on the panel the way the other refusals already are. That matches the terminal's behaviour, costs one multiply, and makes `FreeMargin()` a live instrument instead of a dead one.

##### `trading-exec-8` — MEDIUM — break-even writes a stop the next tick immediately triggers

**File:** `SSR_TradingEngine.mqh:920` · **Category:** sl-tp-execution

```mql5
bool              BreakEven(const long ticket)
  {
   int i = Find(ticket);
   if(i < 0 || m_pos[i].state != SSR_POS_OPEN)
     { m_last_error = "no open position"; return false; }
   m_pos[i].sl = m_pos[i].open_price;
```

**Failure scenario** (verifiers' corrected version) [CONFIRMED FROM CODE] — `BreakEven` sets a long's stop to its **ask-side** fill price while `CheckStops` tests it against the **bid**, so `px <= sl` is already satisfied the moment the stop is written. Press `be` before price has advanced past the entry spread and the trade closes on the very next tick as an SL at `StopFill = bid - slip`: a guaranteed loss of spread plus slippage, counted as a losing trade, with auto-pause announcing "stop loss hit". This holds even with zero spread and zero slippage, where `sl == open_price == bid` triggers on equality and produces a flat "stop loss" in the statistics. A real terminal rejects an SL above the bid with "invalid stops" and leaves the position running. `Modify(ticket, sl, tp)` (844-853) has the same missing wrong-side check, and neither path marks the close as a rejected modification.

**Why** [CONFIRMED FROM CODE] — For a long, `open_price = FillPrice(true,true) = ask + slip` (743), above the bid by the whole spread plus slippage. `CheckStops` 526-527 evaluates `px <= sl` with `px = m_bid`; with `tp == 0`, `BarIsAmbiguousFor` returns false at 160-161, so 543 closes at `StopFill = min(sl, bid) - slip`. Neither `BreakEven` nor `Modify` compares against `m_bid`/`m_ask`, and `GroupPort.BreakEven`/`BreakEvenAll` (867-915) add no price check either.

**Verifiers** — Traced end to end with no guard anywhere; triggers even at zero spread.

**Fix** [RECOMMENDATION] — Add the side check both methods lack, in one shared private helper:

```mql5
   bool ValidStops(const int i, const double sl, const double tp)
     {
      bool lng = m_pos[i].IsLong();
      if(sl > 0.0 && ((lng && sl >= m_bid) || (!lng && sl <= m_ask))) return false;
      if(tp > 0.0 && ((lng && tp <= m_bid) || (!lng && tp >= m_ask))) return false;
      return true;
     }
```

`BreakEven` and `Modify` both call it and set `m_last_error = "invalid stops"` on failure, returning false — which the panel already renders. For `be` specifically, the useful behaviour is to refuse until the position is at least the spread in profit, which this check gives for free.

#### C.5.7 UI layer - `MQL5/Include/SSReplay/Ui`

##### `ui-port-session-9` — MEDIUM — pending orders occupy wire rows no total accounts for

**File:** `SSR_GroupPort.mqh:372` · **Category:** boundary

```mql5
               out.pending_count++;
```

**Failure scenario** (verifiers' corrected version) [CONFIRMED FROM CODE] — `pos_rows` counts open **and** pending rows while `open_positions` counts opens only, and `pending_count` is written here and read nowhere — so the panel's only "hidden rows" indicator is computed from the wrong pair. With 2 open positions and 4 pendings: `pos_rows` 6, `shown` 5, `open_positions` 2; `2 > 5` is false, no "+N more" is drawn, and one pending order is simply absent — the exact failure the "PENDING ORDERS ARE ROWS TOO / an order you cannot see is an order you forget you left there" comment (346-353) exists to prevent. With 20 opens and 4 pendings the line misreports: `pos_rows` is capped at `SSR_POS_MAX=12`, so 12 rows are collected, 5 shown, the line says "15 not shown" while 19 items are actually absent.

**Why** [CONFIRMED FROM CODE] — 354-356 admits pendings into the row array; 240 sets `out.open_positions = m_acct.OpenCount()`, which counts only `SSR_POS_OPEN` (a separate `PendingCount()` exists at `SSR_TradingEngine.mqh:981` and is unused here). `out.pending_count` appears only at its declaration (`SSR_ReplayPort.mqh:124`), its clear (261) and this increment. The panel computes `shown` from `pos_rows` (`SSR_Panel.mqh:1513`) and gates the indicator on `open_positions > shown` (1640-1642), with `PosCap()` = 5 on the normal panel.

**Verifiers** — Every cited number verified; only the "24 rows" arithmetic needed the `SSR_POS_MAX` cap applied.

**Fix** [RECOMMENDATION] — Compare like with like. Add `out.total_rows_wanted` (opens + pendings, uncapped) beside `pos_rows` on the wire, or simply have the panel use `m_state.open_positions + m_state.pending_count` — the field is already populated and merely unread. Then `if(total > shown) … total - shown`. One line in `SSR_Panel.mqh:1640-1642`, and `pending_count` stops being dead wire.

##### `ui-panel-2` — MEDIUM — `HideBody(false)` forgets the property cache for ~44 objects every frame

**File:** `SSR_Panel.mqh:729` · **Category:** redraw

```mql5
      HideBody(false);

      int cy = y + SSR_HEADER_H + 3;
      cy = DrawClock(x, cy, W);
      cy = DrawTransport(x, cy, W);
      cy = DrawSpeed(x, cy, W);
```

**Failure scenario** (verifiers' corrected version) [CONFIRMED FROM CODE] — On a still frame the transport row (7 buttons), the speed row, the whole 20-cell slider plus groove and thumb (22 objects), the status rect, the tabline, the three action buttons and up to 5 tab buttons are rewritten with 9 `ObjectSet*` calls each: **~390 property writes per frame** that the 512-slot cache exists to eliminate (the slider alone is 22 × 9 = 198). The labels in `HideBody`'s list still take `Text()`'s early return, so the count is ~390 rather than ~400. The millisecond consequence is an extrapolation from the comment at `SSR_Widgets.mqh:31-38` (561 writes = 39.05 ms) and is unvalidated on a terminal — hence a provable cache regression of known write count and an unproven latency figure.

**Why** [CONFIRMED FROM CODE] — `CSSRWidgets::Hide` (616-625) writes `OBJPROP_TIMEFRAMES` when the object exists and then calls `Forget(n)` **unconditionally**; the comment at 622-624 explains why (visibility is not in the fingerprint). Line 729 is on the hot path every non-collapsed frame, and 732-734 and 750-751 redraw exactly those objects, so `Same()` misses and `ButtonC`/`Rect` execute all nine writes each.

**Verifiers** — Write count re-derived object by object.

**Fix** [RECOMMENDATION] — Only forget when visibility actually changed. Inside `Hide`, read the current `OBJPROP_TIMEFRAMES` first and return early when it already equals the requested value — one `ObjectGetInteger` against nine `ObjectSet*` plus a lost cache slot. That preserves the fingerprint reasoning exactly (the cache is still dropped whenever visibility flips) and turns the still-frame cost of line 729 from ~390 writes into ~44 reads. Complementary: hoist the `HideBody(false)` call so it runs only when `m_collapsed`/`m_closed` changed, as `HideSheetArea` already does at 682 — but do the `Hide` fix regardless, because every other caller benefits.

##### `ui-panel-10` — MEDIUM — in compact mode the fill toast covers the speed trackbar for four seconds

**File:** `SSR_Panel.mqh:804` · **Category:** z-order

```mql5
         m_w.Toast("fill", x + SSR_PAD, y + H - SSR_STATUS_H - 24,
                   W - 2 * SSR_PAD, m_toast_text,
```

**Failure scenario** (verifiers' corrected version) [CONFIRMED FROM CODE] — On a chart roughly 128-360 px tall the panel is compact (`BodyH()` = `SSR_PANEL_COMPACT_H` = 128) and the toast lands at `y + 128 - 18 - 24 = y+86`, 20 px tall, so `y+86..y+105`. The speed row occupies `y+82..y+100`, with the groove at `y+86..y+96` and the thumb at `y+84..y+98`. Every fill therefore covers the entire speed control for the 4000 ms toast window — in the mode where the speed control is one of only four things left on the panel. In the full layout the same expression gives `y+294`, clear of everything. The finder's claim that the toast also *swallows clicks* on the groove rests on the same MT5 z-order/hit-test assumption the project itself records at `SSR_Widgets.mqh:455-458`: the visual occlusion is provable from source, the click-blocking is unvalidated runtime behaviour. [POTENTIAL_RISK for the click half.]

**Why** [CONFIRMED FROM CODE] — The toast `y` is computed from `H` (804), and `H = BodyH()` (716) returns the compact height (427). The toast block at 802-806 sits **outside** the `if(!m_compact)` guard at 735, so it is unconditional.

**Verifiers** — Arithmetic checks out to the pixel; two pixel details corrected.

**Fix** [RECOMMENDATION] — Place the toast where the compact layout has room: `int toast_y = m_compact ? (y + SSR_HEADER_H + 3) : (y + H - SSR_STATUS_H - 24);` — directly under the caption, above the clock row, which compact mode leaves at its full height. If a compact toast is judged not worth the space at all, the alternative that costs nothing is to fold the fill message into the status strip text for the same four seconds, since the strip is already drawn in both modes and is one label rather than three objects.

##### `ui-panel-1` — MEDIUM — `DrawSheet` deletes and recreates the whole visible sheet every repaint

**File:** `SSR_Panel.mqh:1270` · **Category:** redraw

```mql5
   void              DrawSheet(const int x, const int y, const int w)
     {
      HideSheets();
      switch(m_tab)
        {
         case SSR_TAB_TRADE:     SheetTrade(x, y, w);     break;
```

**Failure scenario** (verifiers' corrected version) [CONFIRMED FROM CODE] — On the Trade tab with lines armed, with nothing changed between two frames, `Render()` deletes every object of the sheet on screen and recreates it. The panel's label cache (`Text()`, 194) requires `m_w.Exists(id)` and the widget property cache (`Same()`) requires `ObjectFind >= 0` — both false because `HideSheets()` just deleted the object. So `Writes()` is never zero on a still frame, and the documented invariant at 2994-2998 ("On a frame where nothing changed this must be ZERO") plus the assertions in `SSR_T5_Ui.mq5:236` (`spent <= 2`) and `SSR_QA_Smoke.mq5:5045` (`cached_labels == 0`) cannot hold. Per frame: 70 named `Remove()` + 4×3 meter removes + 12×6 row removes = 154 `ObjectFind`+`Forget`, plus ~20-25 `ObjectCreate` and their full property writes. The verifiers add a further hazard that source cannot settle: the sheet's `OBJ_BUTTON`s (`buy`, `sell`, `openln`, `px0…`, `flat`, `be`, `stmt`) are deleted and recreated ten times a second while the panel learns about clicks by polling the latched `OBJPROP_STATE` (`SSR_Widgets.mqh:338-347`), so a press that latches during `Render()` is destroyed with the object. [POTENTIAL_RISK for the lost-click half — it depends on terminal timing.]

**Why** [CONFIRMED FROM CODE] — `HideSheets()` is the unconditional first statement of `DrawSheet`, and its id list (1301-1316) names the objects of **every** sheet including the one about to be drawn. `CSSRWidgets::Remove` (627-633) does `ObjectDelete` then `Forget`. `DrawSheet` runs from `Render()` at 752/757 on every frame, i.e. every 100 ms.

**Verifiers** — Confirmed; the 39.05 ms figure is quoted from a comment, not measured on this path.

**Fix** [RECOMMENDATION] — Hide the sheets you are leaving, not the one you are drawing. Give `HideSheets(const int except_tab)` the current tab and skip that tab's id block; call it only when `m_tab != m_last_drawn_tab` (a new member), so a still frame on a stable tab performs zero removes and both caches do their job. The row objects need the same treatment: remove only rows above the current `shown` count instead of all 12. That restores the "zero writes on a still frame" invariant the tests already assert, and it removes the delete/recreate window that endangers latched clicks — the fix for both halves is the same.

##### `ui-panel-5` — MEDIUM — two cache slots write the same object, so `order_why` shows for one frame

**File:** `SSR_Panel.mqh:1432` · **Category:** redraw

```mql5
         if(m_state.order_why != "")
            Text(17, "setuprow", x + 8, gy + 12, m_state.order_why,
                 SSR_C_STOP, SSR_FS_SMALL);
```

**Failure scenario** [CONFIRMED FROM CODE] — With lines armed and an illegal geometry (`order_why` = "drag the stop below the price"), the reason is drawn on the frame the string first changes and is overwritten by "LONG setup"/"SHORT setup" on every subsequent frame — at 10 fps it is on screen for ~100 ms and then gone for good. The user is told only "cannot place" on the `openln` button and never why, which is the opposite of what the comment at 1424-1430 claims the slot split achieved.

**Why** [CONFIRMED FROM CODE] — `Text(12, "setuprow", x+8, gy+12, …)` at 1402 and `Text(17, "setuprow", x+8, gy+12, …)` at 1432 target the **same object id at the same coordinates**. `Text()` (194-207) keys its early return on `(slot, text, x, y, Exists(id))`. Because `HideSheets()` deletes `setuprow` at the top of every `DrawSheet` (id listed at 1306), `Text(12)` always finds `Exists==false` and writes the side text; `Text(17)` then finds the object present with `m_cache[17] == order_why` and `x,y` unchanged, takes the early return, and leaves the side text in place. Only on the frame where `order_why` changes does the second call actually write. Slot 17 is used nowhere else, so `m_cache[17]` holds the string persistently.

**Verifiers** — Both calls traced; slot numbers grepped.

**Fix** [RECOMMENDATION] — Two rows, two objects. Draw the reason into its own id — `Text(17, "setupwhy", x + 8, gy + 26, m_state.order_why, SSR_C_STOP, SSR_FS_SMALL)` — add `setupwhy` to `HideSheets`' id list, and reserve the 14 px below `setuprow` in the sheet's layout (the group box has the room; `CheckFrame()` will say if it does not). If the vertical space genuinely is not there, make it one object and one slot: build the string first (`string row = (m_state.order_why != "" ? m_state.order_why : side_text);`) and issue a single `Text(12, "setuprow", …, row, …)` with the colour chosen by the same condition. Either way `order_why` stops being a one-frame message.

##### `ui-panel-7` — MEDIUM — the position-row note column collides with the P/L column

**File:** `SSR_Panel.mqh:1576` · **Category:** boundary

```mql5
            Text(104 + r, "pn" + t, x + 120, ry + 3, note,
                 (m_state.pos_no_stop[r] ? SSR_C_STOP : SSR_C_TEXT_FAINT),
                 SSR_FS_SMALL);
```

**Failure scenario** (verifiers' corrected version — understated by the finder) [CONFIRMED FROM CODE] — The collision is the **normal state of the sheet**, not the no-stop case only: the note is also set whenever `!pos_pending[r] && pos_spread[r] > 0.0` (1570-1573), i.e. for essentially every filled row, so "  sp 20.0" lands on the P/L figure on ordinary rows too. In the rail layout the sheet is 245 px wide (310 − 2×8 − 44 − 5), the note is anchored at `x+120` and the money column at `x + w − 116 = x+129`: nine characters get nine pixels. The two things a trader reads on that row overprint each other. The comment at 1563-1574 claims "The row now has four columns that do not touch" and shows its arithmetic for a 295 px sheet; the rail sheet is 50 px narrower.

**Why** [CONFIRMED FROM CODE] — `DrawSheet` is called with `w = W − 2*SSR_PAD − SSR_RAIL_W − SSR_GAP` = 245 (752-753). `note` is `T(SSR_S_NO_STOP)` = "  no stop" (`SSR_Strings.mqh:391`) or `"  " + T(SSR_S_SPREAD_SHORT)` = "  sp %.1f" (495) — nine characters either way, which at `SSR_FS_SMALL` (7 pt) occupies roughly 30 px. The Persian "no stop" is longer still (`fa.txt:61`). Both are `OBJ_LABEL`s with transparent backgrounds, so they interleave rather than mask.

**Verifiers** — Widths and string lengths re-derived; exact glyph overlap is font-metric dependent, the impossibility of 9 chars in 9 px is not.

**Fix** [RECOMMENDATION] — The rail sheet has no room for four columns, so drop to three: move the note to the **left** of the P/L as a suffix on the volume column (`"0.20 sp 20.0"`, anchored at `x+56`, which has ~60 px of slack), or shorten the note to a one-glyph marker (`!` for no stop, `~` for wide spread) drawn at `x+112` with the full text in the object's tooltip — tooltips cost nothing and are not subject to the 63-char draw limit. Whichever is chosen, add the row to `CheckFrame()`'s reach by drawing the note as a zero-border `Rect`-backed widget so `Extent()` sees it, which is the only way the existing overflow instrument can catch the next one (see `ui-panel-6`).

##### `ui-panel-6` — MEDIUM — the status strip draws the fidelity readout outside the panel

**File:** `SSR_Panel.mqh:2033` · **Category:** boundary

```mql5
      Text(53, "stfid", x + 330, y + 4,
           SSRFidelityName(m_state.fidelity_effective) + (degraded ? " !" : ""),
           degraded ? SSR_C_HOLD : SSRFidelityColor(m_state.fidelity_effective),
           SSR_FS_SMALL);
```

**Failure scenario** (verifiers' corrected version) [CONFIRMED FROM CODE] — In the shipping rail layout the panel frame is `x..x+310`, and the label's **anchor** is at `x+330` — 20 px past the right edge before a glyph is drawn. The text is "SYNTHETIC TICK" (14 chars, 16 when degraded), so ~90 px of readout sits on the price on every frame of every session. Qualification: the panel's `x` is clamped to `cw − 310` when the chart is at least 310 px wide (466-469), so on a wide chart it lands on the candles to the right of the panel as described, while with the panel pushed to the right edge part or all of it falls outside the chart window and is simply not drawn. Cosmetic but permanent.

**Why** [CONFIRMED FROM CODE] — The `x` offsets in `DrawStatus` (2015-2036: `x+8, x+116, x+218, x+268, x+330`) carry no `#ifdef SSR_LAYOUT_RAIL`, unlike `DrawClock` (956-965), `DrawTransport` (990-1008), `DrawSpeed` (1047-1056) and `TabName` (1112-1140), all of which were given rail variants; `x+330` fits the 420 px fallback and not the 310 px rail. The overflow instrument cannot report it: `CheckFrame` (3019-3034) compares `m_w.MaxRight()` against `x+W`, and `MaxRight` only sees objects that call `Extent()` — `Rect`, `Button`/`ButtonC` and `Edit` — while `Label` does not, as the comment at `SSR_Widgets.mqh:125-128` states.

**Verifiers** — `#ifdef SSR_LAYOUT_RAIL` sites grepped: 747, 956, 990, 1047, 1112 — `DrawStatus` is the one draw function without a rail variant.

**Fix** [RECOMMENDATION] — Give `DrawStatus` the rail variant its four siblings already have. In the 310 px layout the strip has four fields to place, not five with a 22 px overrun: `x+8` (state), `x+96` (speed), `x+176` (progress), `x+246` (fidelity, abbreviated to `SSRFidelityShort()` — "TICK"/"SYN"/"BAR", 3-4 chars, which fits the 56 px remaining). Add the short-name helper beside `SSRFidelityName` in `SSR_Types.mqh`. Separately, and more valuable than this one fix: have `Label()` call `Extent()` like its siblings so `CheckFrame` can see text at all — that converts this whole class of defect from invisible to a log line.

##### `ui-dialogs-7` — MEDIUM — the range dialog validates against the broker, its caller can only jump inside the session

**File:** `SSR_RangeDialog.mqh:139` · **Category:** boundary

```mql5
   bool              CanStart(void)
     {
      return (m_req.IsComplete() && m_quote.IsFeasible() &&
              (m_problem == "" || StringFind(m_problem, "warning") == 0));
     }
```

**Failure scenario** [CONFIRMED FROM CODE] — Press J, type a date three months before the replay window but well inside broker history, press START. Every check passes (the catalogue has that history), `m_confirmed` is set, the dialog closes — and nothing happens on screen. The host jumps only when the date lies inside `[g_group.StartMsc(), g_group.EndMsc())` and otherwise prints "that range needs a fresh session" to the Experts log. The dialog refuses what the **broker** cannot serve and accepts what the **session** cannot serve, which is the opposite of what its only use needs; the title "NEW SESSION" and the button "START" reinforce the wrong expectation. `Close()` runs before the host's check, so no surface remains on which to report the refusal.

**Why** [CONFIRMED FROM CODE] — `g_dialog.Open()` is reached only from `RunHostCommand(SSR_CMD_JUMP)` (`SSReplayStandalone.mq5:3093-3106`), which seeds `start = g_group.Now()`, `end = g_group.EndMsc()`. Because `start_msc > 0` the catalogue-default branch (105-110) is skipped, so the typed start is validated only by `SSRValidateRange` (135), which measures against `cat.EarliestStart(warm)` and `cat.LastMsc()` (`SSR_SessionRange.mqh:82-87`) and knows nothing about the loaded window. The confirm handler at 3181-3192 does the real test after the dialog is gone.

**Verifiers** — Traced end to end; `Open()` has exactly one caller.

**Fix** [RECOMMENDATION] — Tell the dialog what its caller can actually do. Add `void SetJumpWindow(const long lo, const long hi)`, called from `RunHostCommand` with the group's start and end, and extend `Recompute()` with a session-scope verdict — `if(m_jump_hi > 0 && (m_req.start_msc < m_jump_lo || m_req.start_msc >= m_jump_hi)) m_problem = "outside this session - stop and start a new one from " + SSRFormatMsc(m_jump_lo);` — so `CanStart()` refuses it and the user reads why, in the dialog, before it closes. Retitle the dialog "JUMP TO" and the button "GO" while you are there: the words promise a capability the code does not have.

##### `ui-dialogs-5` — MEDIUM — the range dialog draws an unbounded validator message into one label

**File:** `SSR_RangeDialog.mqh:233` · **Category:** string-length

```mql5
      color pc = (StringFind(m_problem, "warning") == 0) ? SSR_C_HOLD : SSR_C_STOP;
      m_w.Label("problem", x + SSR_PAD, cy, m_problem, pc, SSR_FS_SMALL);
```

**Failure scenario** (verifiers' corrected version) [CONFIRMED FROM CODE] — Press J and pick D1 context on a broker with limited M1 history. `SSRValidateRange` returns "start too early - PERIOD_D1 context needs history back to 2019.01.03 00:00:00" — **77 characters** (78 for `PERIOD_M15`). MetaTrader draws 63, so the user reads "…needs history back to 2019." — a sentence that looks complete and names a year instead of the instant, while the real requirement is invisible. The refusal is the dialog's whole purpose and it is the one message that cannot be read. And the cut is not the only problem: the dialog is `SSR_DLG_W = 248` px wide and the label is drawn at `x+SSR_PAD` with no width budget, so even a 63-character string overruns the box.

**Why** [CONFIRMED FROM CODE] — Built at `SSR_SessionRange.mqh:84-85` as `StringFormat("start too early - %s context needs history back to %s", EnumToString(r.max_tf), SSRFormatMsc(earliest))`: 49 literal characters, 9-10 for the enum, 19 for the timestamp. It reaches `OBJPROP_TEXT` completely unguarded — `CSSRWidgets::Label` performs no clipping or truncation, unlike `SSRReviewLine` which clamps to 60 (`SSR_Review.mqh:91-93`). Audit A14 cannot measure it because the argument is a variable (`tools/ssr_audit.py:944-947`).

**Verifiers** — Length arithmetic re-derived; 49 not 48, and the box-width overrun is theirs.

**Fix** [RECOMMENDATION] — Make the message fit the two constraints that exist. At the source, shorten the format to "start too early - %s needs data from %s" (37 literal + 10 + 19 = 66) and drop `SSRFormatMsc` to `TIME_DATE` only (10 chars) for a 57-character worst case. At the sink, wrap rather than truncate: the dialog has vertical room, so draw `m_problem` into two labels of ≤ 40 characters split at the last space before the limit — a six-line helper next to `SSRReviewLine`, reusable by every dialog that draws a validator verdict. Do both: the source fix makes the common case fit, the sink fix makes the next long message survivable.

##### `ui-dialogs-3` — MEDIUM — `Recompute()` erases the two messages set just before it

**File:** `SSR_RangeDialog.mqh:268` · **Category:** event-handling

```mql5
            string txt = ObjectGetString(m_chart, sparam, OBJPROP_TEXT);
            datetime t = StringToTime(txt);
            //--- a typo must not silently become 1970
            if(t > 0)
               m_req.start_msc = SSRToMsc(t);
            else
               m_problem = "could not read that date - use YYYY.MM.DD HH:MM";
            Recompute();
```

**Failure scenario** [CONFIRMED FROM CODE] — Press J, type "march 5" into the start box, press Enter. `StringToTime` returns 0, the refusal is assigned to `m_problem`, and `Recompute()` on the very next line does `m_problem = ""` and replaces it with `SSRValidateRange`'s verdict on the **unchanged old date**, which is usually empty. The user sees no error at all, the field keeps the text they typed, and START stays enabled against the previous instant — exactly the "a typo must not silently become 1970" failure the comment claims to prevent. The identical pattern mutes LOAD MORE: `m_problem = "gained %d more bars"` / `"the broker has nothing older"` (304-306) is discarded by the `Recompute()` on 307.

**Why** [CONFIRMED FROM CODE] — `Recompute()` begins with `m_problem = "";` (127) and ends with `m_problem = SSRValidateRange(m_req, m_cat);` (135); its only early return is the `m_cat == NULL` branch, and `m_cat` is non-NULL at both call sites. `Render()` draws only `m_problem` into the "problem" label (234) — the dialog has no toast and prints nothing to the log, so there is no other channel.

**Verifiers** — Both call sites are dead-store patterns, provable by ordering alone.

**Fix** [RECOMMENDATION] — Separate the two kinds of message. Add `string m_notice;` for input and action feedback that `Recompute()` must not touch, render it on its own line under `m_problem`, and clear it only in the handlers that set it (a successful `ENDEDIT`, a new dialog `Open`). Then the typo path becomes `m_notice = "could not read that date - use YYYY.MM.DD HH:MM"; Recompute();` and LOAD MORE's result survives. Bonus correctness: on an unreadable date, also leave `CanStart()` false by clearing `m_req.start_msc`, so START cannot fire against a date the user did not intend.

##### `ui-dialogs-4` — MEDIUM — two review-card observations exceed the 63-character draw limit for every value

**File:** `SSR_Review.mqh:205` · **Category:** string-length

```mql5
   if(st.spread_samples >= 3 && st.wide_spread_trades > 0)
      out[n++] = StringFormat("%d of %d trades were entered at a spread "
                              "wider than this session's average.",
                              st.wide_spread_trades, st.spread_samples);
```

**Failure scenario** (verifiers' corrected version) [CONFIRMED FROM CODE] — Any session with ≥ 3 spread samples and one wide-spread entry produces a **73-79** character sentence drawn into one `OBJ_LABEL`; MetaTrader shows 63, so the user reads "3 of 12 trades were entered at a spread wider than this session" and the words that say what the comparison *is* are cut off. The ambiguous-bar line at 210-213 is worse: "1 trade(s) closed on a bar that reached both the stop and the target." is 69 characters and renders as "…reached both the stop and the t", which reads as a plain stop-out and loses the fact that the bar hit the target too — the single most important caveat this product reports about a fill.

**Why** [CONFIRMED FROM CODE] — Both are passed verbatim to `m_w.Label(oid, m_x+12, oy+16+i*14, m_obs[i], …)` (`SSR_ReviewCard.mqh:190`) with no truncation; `SSRReviewLine` clamps measure **rows** to `SSR_REVIEW_ROW_MAX` 60 (91-93) but nothing clamps observations. Audit A14 cannot see them twice over: it measures only literal-only arguments at the call site (`ssr_audit.py:938-948`) and the argument here is `m_obs[i]`, and the source literals are split across two lines so a per-literal scan sees two short pieces. These sentences also bypass the `T(SSR_S_*)` rule, so they are untranslated as well.

**Verifiers** — Both literals measured; 73 not 71 at minimum, which strengthens the finding.

**Fix** [RECOMMENDATION] — Shorten at the source and clamp at the sink. Rewrite as "%d of %d entries paid a wider spread than average." (≤ 55) and "%d trade(s) hit stop and target in one bar." (≤ 48), move both into `SSR_Strings.mqh` as `T(SSR_S_OBS_WIDE_SPREAD)`/`T(SSR_S_OBS_AMBIGUOUS)` so they are translatable and so A19's length check covers them, and route every observation through `SSRReviewLine`'s existing 60-char clamp on the way into `m_obs[]`. The clamp is the part that protects the next sentence someone adds — and the Persian strings, which are longer.

##### `ui-dialogs-2` — MEDIUM — an open dropdown survives a step change and is redrawn over START

**File:** `SSR_SetupPanel.mqh:1061` · **Category:** z-order

```mql5
      if(m_w.Pressed("next"))
        {
         ReadAll();
         m_step++;
         Repaint();
         return "";
        }
```

**Failure scenario** (verifiers' corrected version) [CONFIRMED FROM CODE] — On step 1 click the Preset field to open its list, then — without choosing — click Next, Next. `m_menu` is still `"pre"` and `m_menu_y` still holds the settings-step row position, so `Render()` ends with `DrawMenu()` and paints the five preset buttons at `m_y+291..m_y+391` over the MODE step and then over the START step, where `back`/`go` sit at `m_y+316..m_y+342`. Which object consumes a click in the overlap is the one part source cannot settle: menu items and `go` both carry `OBJPROP_ZORDER` 100 from `CSSRWidgets::Common`, and MQL5's tie-break between equal z-orders is runtime behaviour. If the later-created menu item wins, the press applies a preset and the replay does not start; if `go` wins, the replay starts with a stray list on screen. The stray menu itself is a confirmed paint defect either way. [POTENTIAL_RISK for which one wins.]

**Why** [CONFIRMED FROM CODE] — `m_menu` is cleared only in `DrawMenu` when the option list is empty (625), after a choice (1092) and by the four field toggles (1100-1103); for `"pre"`, `MenuOptions` always returns at least one entry, so it never self-clears. Neither `Repaint()` (656-662) nor the next/back handlers reset `m_menu` or `m_menu_y`; `m_menu_y` is written only by `Row()` (221-222), which runs from `RenderSettings` alone; and `Render()` calls `DrawMenu` last on every step (673, "last, because last is on top"). `Poll` checks `next` before the menu block, so the Next press is honoured.

**Verifiers** — Reproducible from source; only the click-arbitration outcome is runtime.

**Fix** [RECOMMENDATION] — Close the menu whenever the step changes: `m_menu = ""; m_menu_y = 0;` at the top of both the `next` and `back` handlers — two lines, and it makes `DrawMenu`'s "last is on top" contract safe because the menu can only exist on the step that opened it. Belt and braces for the general case: have `Repaint()` clear it too, since every caller of `Repaint` is changing what is on screen.

#### C.5.8 Session - `MQL5/Include/SSReplay/Session`

##### `ui-port-session-8` — MEDIUM — resume warnings are newline-joined into one 63-character label

**File:** `SSR_SessionManager.mqh:89` · **Category:** string-length

```mql5
      m_warnings += (m_warnings == "" ? "" : "\n") + text;
```

**Failure scenario** (verifiers' corrected version) [CONFIRMED FROM CODE] — On the dialog's Load path the whole warning block is rendered as one `OBJ_LABEL`, so about **40 characters of the first warning** are drawn (after the 23-character `resumed "name"  BUT: ` prefix) and every warning after the first `\n` is unreachable. The fingerprint mismatch — the entire reason the session format carries a fingerprint — is delivered this way. The user is still alerted (warning colour, "BUT:" prefix) and the leading 40 characters of each `DiffText` variant carry the gist, but on this path there is no log line or other surface where the full text can be read; only the host's startup path prints it (`SSReplayStandalone.mq5:1486`).

**Why** [CONFIRMED FROM CODE] — `Restore` can raise several warnings (stream count 320-322, per-stream fingerprint and bar count `SSR_ReplayController.mqh:1836-1856`, skew 361-363, balance-replay and orphan-leg `SSR_TradingEngine.mqh:1252-1262`). `CSSRGroupPort::LoadSession` copies the whole block into `m_session_error` (969-970) and returns true; `SSR_SessionDialog.mqh:280-281` concatenates it into `m_message`, drawn by one `m_w.Label("msg", …)` at 214. `CSSRWidgets` has no wrapping, ellipsis or length handling anywhere.

**Verifiers** — Traced end to end; every warning producer enumerated.

**Fix** [RECOMMENDATION] — Keep the warnings as a list, not a blob. Store them in a bounded `string m_warn[8]` with `int m_warn_count`, expose `Count()`/`At(i)`, and have the dialog draw up to three of them on consecutive lines (`"msg0".."msg2"`, 14 px apart — the dialog has the room) with a "+N more, see the Experts log" line when there are more. Then `Print()` the full block on the dialog path as well, so the complete text always exists somewhere the user can reach. `Warnings()` can stay as a joined convenience for the startup path that already prints it.

#### C.5.9 Strategy - `MQL5/Include/SSReplay/Strategy`

##### `strategy-integration-report-2` — MEDIUM — `OnBar` is detected from the last tick of a batch

**File:** `SSR_StrategyHost.mqh:184` · **Category:** tick-ordering

```mql5
      long now = ticks[count - 1].time_msc;
...
         long bar_open = SSRBarOpenMsc(now, m_tf[i]);
...
         else if(bar_open > m_last_bar[i])
           { m_last_bar[i] = bar_open; m_bar_calls++; m_strat[i].OnBar(); }
```

**Failure scenario** (verifiers' corrected version) [CONFIRMED FROM CODE] — `SSR_IStrategy.mqh:20-24` promises "the same session replays to the same trades"; it does not hold. The replay clock advances by the wall delta, so the instant a pump ends at depends on CPU load, and because the host inspects only the batch's last tick, the moment inside the new bar at which `OnBar` fires — and therefore the `Bid()`/`Ask()` the strategy sees and the price the engine fills at — moves with that boundary. Replay the same window twice on a loaded machine and `CSSRRefBreakout` takes different entries, with its `sl >= Bid()` gate flipping on borderline cases. In FULL_TICK the same collapse **skips bar closes outright**: `PublishTicks` is called once per window, so a batch spanning two boundaries fires `OnBar` once. The finder's arithmetic is wrong though: `InpPumpMs=40` caps a starved pump at `4*40 = 160` ms of wall time, so at the ladder's top (1000×) one batch covers ≤ ~160 s of replay — enough to contain two or three M1 boundaries, not two M15 boundaries; skipping an M15 close additionally needs a larger `InpPumpMs` (e.g. 250 ms).

**Why** [CONFIRMED FROM CODE] — Every tick before the last in the batch is invisible to the bar-close test, and `m_last_bar` can jump several boundaries in one step (202-207); `OnTick` likewise fires once per batch, not per tick. Contrast `CSSRTradingEngine::OnTicks`, which loops all `count` ticks updating `m_bid`/`m_ask`/`m_now_msc` and calling `CheckStops` per tick — the account is batch-size independent and deterministic, the strategy layer is not.

**Verifiers** — Both halves check out; only the worked example needed correcting.

**Fix** [RECOMMENDATION] — Walk the batch. Replace the single `now` with a loop over `ticks[0..count-1]` that, per timeframe, compares `SSRBarOpenMsc(ticks[k].time_msc, m_tf[i])` against `m_last_bar[i]` and fires `OnBar()` on each crossing, setting the market view's bid/ask to that tick first so the strategy reads the price at the boundary rather than at the batch end. That is the same loop the trading engine already runs, and it makes the strategy layer as batch-independent as the account. `OnTick` should move inside the same loop if the documented "once per tick" contract is to hold (see `strategy-integration-report-3`).

#### C.5.10 Report - `MQL5/Include/SSReplay/Report`

##### `strategy-integration-report-8` — MEDIUM — the class report declares UTF-8 and is written `FILE_ANSI`

**File:** `SSR_ClassReport.mqh:439` · **Category:** utf8

```mql5
      int h = FileOpen(out_path, FILE_WRITE | FILE_TXT | FILE_ANSI | FILE_SHARE_READ);
```

**Failure scenario** (verifiers' corrected version) [CONFIRMED FROM CODE] — `SSRWriteReportHead` emits `<meta charset="utf-8">` into this same handle (`SSR_ReportStyle.mqh:21`), but `FILE_ANSI` transcodes every `FileWriteString` from UTF-16 to the system codepage. A Persian student name — the expected case for an academy that ships a full `fa.txt` — is written as Windows-1256 bytes or `?` placeholders, and the browser, told the file is UTF-8, renders replacement characters. The coach opens `class-report.html` and cannot tell which row is which student. Student names are the clearest case because they come from `FileFindFirst` as genuine Unicode (311-315). The symbol/session fields take a different route to the same place: `SSR_Journal.mqh:173/254` also writes the CSV `FILE_ANSI` and `ReadOne` reopens it `FILE_ANSI` (150), so those bytes round-trip through the codepage and land in the HTML as codepage bytes — still mojibake under a UTF-8 declaration, but the loss happened at journal-export time.

**Why** [CONFIRMED FROM CODE] — `grep CP_UTF8` over the Report layer returns nothing; the only use in the repo is on the **read** side, at `SSR_Strings.mqh:686`, where the language file is correctly read with `FILE_BIN` + `CharArrayToString(..., CP_UTF8)`. The names reach the page at 561, 618, 650 and 521.

**Verifiers** — Encoding contradiction provable in one file; the CSV half is a second mechanism, not a second bug in this writer.

**Fix** [RECOMMENDATION] — Write the bytes the header promises. Open with `FILE_WRITE|FILE_BIN` and push each line through the inverse of the routine already in `SSR_Strings.mqh`: `uchar buf[]; int n = StringToCharArray(s, buf, 0, -1, CP_UTF8); FileWriteArray(h, buf, 0, n-1);` — one small `WriteUtf8(h, s)` helper used by every `FileWriteString` call in `Write()`. Give `SSR_Journal.mqh`'s CSV writer and `ReadOne` the same treatment so the round trip is UTF-8 end to end; until then, the report is only as clean as the CSV it reads.

##### `strategy-integration-report-9` — MEDIUM — the class KPIs, ranking and bar scale include students who ran a different session

**File:** `SSR_ClassReport.mqh:493` · **Category:** aggregate scope (not drawdown-calc — verifiers' correction)

```mql5
      for(int i = 0; i < m_count; i++)
        {
         if(!m_s[i].parsed)
            continue;
         total_trades += m_s[i].trades;
         if(!have || m_s[i].net_profit > best)  best  = m_s[i].net_profit;
```

**Failure scenario** [CONFIRMED FROM CODE] — Twenty students run session key K and one file from last week's easier window lands in the folder with net +5000. The page reports "Best +5000.00" in the KPI row, shifts "Median result" and "Trades between them" by that file, scales every diverging bar in the league table against `peak = 5000` so the twenty comparable students' bars shrink, and places the outsider at the top of a table sorted purely on `net_profit` — with only a small "(different session)" label beside the name. The header at 19-23 states the report "REFUSES TO RANK PEOPLE WHO RAN DIFFERENT SESSIONS" because "a league table across two different windows is not a comparison, it is a mistake with a heading on it". The label is the only thing implementing that refusal, and it reaches no aggregate.

**Why** [CONFIRMED FROM CODE] — The filter in this loop is `!m_s[i].parsed`, never a key test, so `best`, `worst` and `total_trades` span every readable file. `MedianNet()` (373-396) filters on parsed only; `peak` (597-600) filters on parsed only; `Rank()` (350) returns `net_profit` with no key term and the insertion sort (337-344) orders on `Rank` alone. `m_key`/`m_key_agree` (324-334) are used at exactly four places — the caveat (475-481), the `odd_row` label (558-564), the "(different session)" span (619) and `Axis()` (406-412) — never to exclude a row from an aggregate.

**Verifiers** — Every aggregate checked for a key filter; there is none.

**Fix** [RECOMMENDATION] — Make the key a first-class filter, not a label. Add `bool InKey(const int i) const { return (m_s[i].parsed && (!m_key_agree || m_s[i].key == m_key)); }` and use it in the KPI loop, `MedianNet`, the `peak` scan and `Rank` (returning `-1e18` for out-of-key rows so they sort to the bottom). Keep the odd rows visible in the table — the caveat and the "(different session)" span are good — but below a divider, out of the ranking and out of every number. That is what the header already promises the reader.

#### C.5.11 Spike kit - `MQL5/Include/SSReplay/Spike`

##### `spikes-audits-3` — MEDIUM — no spike forces BID chart mode or sets `TICK_FLAG_LAST`

**File:** `SSR_SpikeKit.mqh:314` · **Category:** broker-symbol

```mql5
CustomSymbolSetInteger(sym, SYMBOL_SPREAD_FLOAT, true);
CustomSymbolSetInteger(sym, SYMBOL_TRADE_MODE, SYMBOL_TRADE_MODE_DISABLED);
...
CustomSymbolSetInteger(sym, SYMBOL_START_TIME, 0);
CustomSymbolSetInteger(sym, SYMBOL_EXPIRATION_TIME, 0);
```

**Failure scenario** (verifiers' corrected version) [CONFIRMED FROM CODE] — `SSR_MakeSymbol` clones the origin and overrides four properties but never `SYMBOL_CHART_MODE`, and the kit's tick generator sets `flags = TICK_FLAG_BID|TICK_FLAG_ASK` with no `TICK_FLAG_LAST` (592). Drop B1 on an index or futures CFD — which is what `InpOrigin=""` means, and what this project's own example symbol `US30.U26` is — and the clone inherits `SYMBOL_CHART_MODE_LAST`. Every injected tick is accepted and **no bar is built**, so `forming_bar_took_close` and `wick_expanded_to_extremes` both report 0 of 20 and B1 concludes that `CustomTicksAdd` does not broadcast. Impact is bounded to spike measurement validity; the shipping engine is correct.

**Why** [CONFIRMED FROM CODE] — `grep -rn SYMBOL_CHART_MODE` over `MQL5/` hits only `Mt5/SSR_CustomSymbolManager.mqh:383` (the product, which forces BID) and `QA/SSR_QA_Smoke.mq5:473` (which asserts it) — nothing under any Spike directory. `Core/SSR_TickSynthesizer.mqh:157-175` documents the measured failure in exactly this shape ("60 calls offered ticks, the terminal took 481, refused 0, and the M1 series stayed at 139 bars") and fixes it with both `TICK_FLAG_LAST` and forced BID mode, calling that "the belt to that braces". B2, B3, C4 and D3 repeat the same flag pair inline (D2 does not build ticks inline — the finder's list was over-broad).

**Verifiers** — Confirmed by grep on both sides.

**Fix** [RECOMMENDATION] — Move the product's two lines into the kit, which is where the kit's own header says the engine's assumptions get tested first: add `CustomSymbolSetInteger(sym, SYMBOL_CHART_MODE, SYMBOL_CHART_MODE_BID);` to `SSR_MakeSymbol` and `TICK_FLAG_LAST` to `SSR_BarToTicks`' flag word, then replace the inline flag pairs in B2/B3/C4/D3 with a single `SSR_TICK_FLAGS` constant from the kit so the next spike cannot get it wrong. A spike that measures the transport must set the transport up the way the product does, or it is measuring something else.

#### C.5.12 Common - `MQL5/Include/SSReplay/Common`

##### `ui-port-session-2` — MEDIUM — saving truncates the previous good session before writing the new one

**File:** `SSR_SessionFile.mqh:138` · **Category:** session-resume

```mql5
      m_handle = FileOpen(path, FILE_WRITE | FILE_TXT | FILE_ANSI | FILE_SHARE_READ);
```

**Failure scenario** (verifiers' corrected version) [CONFIRMED FROM CODE] — `FILE_WRITE` without `FILE_READ` truncates on open and `Save` passes the final path straight in (`SSR_SessionManager.mqh:167`), so the moment `Create()` succeeds the previous save no longer exists. A trader with a 40-trade session in "friday" changes the chart timeframe; the EA is torn down and re-initialised, the autosave opens `friday.ssr` (old content gone), and if the terminal is closed or the write fails part-way the whole session is lost. Severity is MEDIUM rather than HIGH because the actual loss needs an interruption source cannot establish; the guaranteed part is that **the previous good save ceases to exist before the new one is complete**. The exposure is routine, not exotic: the host writes `CfgSession()` on every `OnDeinit` reason including `REASON_CHARTCHANGE` (2130-2142), and the dialog's Replace branch overwrites in place (`SSR_SessionDialog.mqh:242`) after telling the user there is no undo.

**Why** [CONFIRMED FROM CODE] — There is no staging path, rename or write verification anywhere in the class. The project's own convention confirms the truncation reading: every file it means to preserve is opened `FILE_READ|FILE_WRITE` (`SSR_Log.mqh:44`, `SSR_SpikeKit.mqh:97`).

**Verifiers** — Atomicity defect confirmed; severity trimmed for the unprovable half.

**Fix** [RECOMMENDATION] — Temp, then replace, the way every other durable writer does it. `Create(path)` writes to `path + ".tmp"`; `Close()` closes the handle, verifies the file is non-empty and parses its header, then `FileDelete(path); FileMove(path + ".tmp", 0, path, FILE_REWRITE);`. On failure the `.tmp` is deleted and the original is untouched. Roughly fifteen lines confined to `CSSRSessionFile`, invisible to every caller, and it converts "the save destroys the old one first" into "the save either lands or changes nothing".

#### C.5.13 Test harness - `MQL5/Scripts/SSReplay/Tests`

##### `tests-b-1` — MEDIUM — T15.7 asserts R still means RESET

**File:** `SSR_T15_Ux.mq5:402` · **Category:** stale assertion

```mql5
      Check("and the other keys still mean what they did",
            SSRKeyToCommand(SSR_VK_SPACE) == SSR_CMD_TOGGLE &&
            SSRKeyToCommand(SSR_VK_J)     == SSR_CMD_JUMP &&
            SSRKeyToCommand(SSR_VK_B)     == SSR_CMD_BOOKMARK &&
            SSRKeyToCommand(SSR_VK_R)     == SSR_CMD_RESET);
```

**Failure scenario** [CONFIRMED FROM CODE] — Run T15 on a terminal: `SSRKeyToCommand(SSR_VK_R)` returns `SSR_CMD_LINES_TOGGLE`, so the conjunction is false and `Check` records a FAIL. Phase 15 can never print GREEN, and because the harness never aborts, the failure reads as a **product regression** rather than a stale assertion — the worst possible shape for a false alarm in a suite nobody has run on a terminal.

**Why** [CONFIRMED FROM CODE] — `SSR_Keys.mqh:162-164` binds R to `SSR_CMD_LINES_TOGGLE` and 200-202 binds reset to `SSR_VK_0`, under the comment "RESET MOVED OFF R, and off every letter" (192-199). `SSRKeyToCommand` (224-232) is a first-match linear scan over that single table and R appears exactly once. The test was not updated when reset moved; `SSRKeyHint()`'s trailing "R reset" literal in the same file shows the same stale belief, which is why the mistake reads as plausible (see `ui-plumbing-2`, `ui-plumbing-3`).

**Verifiers** — Provable from the two files; the whole `Check` is false.

**Fix** [RECOMMENDATION] — Change the last conjunct to `SSRKeyToCommand(SSR_VK_0) == SSR_CMD_RESET && SSRKeyToCommand(SSR_VK_R) == SSR_CMD_LINES_TOGGLE`. Better, since three copies of the key list have now drifted apart: make the test assert against the table rather than a memorised copy — loop `SSRKeyBindings` and assert every entry's `vk` round-trips through `SSRKeyToCommand`, plus one explicit assertion that no letter maps to `SSR_CMD_RESET`, which is the invariant the comment at 192-199 actually states.

##### `tests-b-2` — MEDIUM — T15.9's premise is false: `SetCorner` does not move the panel

**File:** `SSR_T15_Ux.mq5:460` · **Category:** redraw

```mql5
      panel2.SetCorner(0);                       // top-left
      long x_before = ObjectGetInteger(ChartID(), "T15_move_stbal", OBJPROP_XDISTANCE);
      panel2.SetCorner(1);                       // top-right
      long x_after  = ObjectGetInteger(ChartID(), "T15_move_stbal", OBJPROP_XDISTANCE);
```

**Failure scenario** (verifiers' corrected version) [CONFIRMED FROM CODE] — On a terminal `x_after == x_before` (both are `m_x + SSR_PAD`, unchanged by the corner), so "the label moved with the panel" and "and it moved to the right, with the panel" both FAIL. Phase 15 reports RED for a panel behaving exactly as designed — and the position-keyed text-cache regression the section exists to guard is left unexercised by any assertion, since a real test would have to call the palette's move action (`SnapToCorner`).

**Why** [CONFIRMED FROM CODE] — `CSSRPanel::SetCorner` is `{ m_corner = (c & 3); SavePlace(); Render(); }` (384-385), and `m_corner` appears nowhere in `Render` or in any layout computation — grep returns only the constructor, a `PrintFormat`, `SavePlace`/`RestorePlace` and `SnapToCorner` (596), the one function that recomputes `m_x`/`m_y` from the corner and is reachable only from the Move button v125 removed. Every object is drawn through `CSSRWidgets`, whose `Common()` hard-writes `OBJPROP_CORNER = CORNER_LEFT_UPPER` (160), so `XDISTANCE` is always measured from the same chart corner.

**Verifiers** — Path traced; the lost coverage is the real cost.

**Fix** [RECOMMENDATION] — Test the function that moves the panel: replace both `SetCorner` calls with `panel2.SnapToCorner(0)` / `SnapToCorner(1)` and keep the two assertions as they are — they then test what the section's title claims. If `SnapToCorner` is genuinely unreachable in v125 (the Move button is gone), either delete T15.9 or drive the move through the palette command so the test exercises a path a user can reach.

##### `tests-a-4` — MEDIUM — T5.1 asserts R maps to reset

**File:** `SSR_T5_Ui.mq5:89` · **Category:** event-handling

```mql5
      CheckEq("R resets",           SSR_CMD_RESET,          SSRKeyToCommand(SSR_VK_R));
```

**Failure scenario** (verifiers' corrected version) [CONFIRMED FROM CODE] — Fails on every run: `SSRKeyToCommand(82)` returns `SSR_CMD_LINES_TOGGLE`. Nothing in T1..T8 asserts the current binding of `R` or of `0`, so the rebinding the production code went out of its way to document is verified by no test at all. The user-visible half is limited to one startup log line (`SSReplayStandalone.mq5:1694` prints `SSRKeyHint()`), which advertises a reset key that no longer resets and omits the real one; the on-screen key list is table-generated and correct, so nothing destructive is mis-triggered.

**Why** [CONFIRMED FROM CODE] — `SSR_Keys.mqh:162-164` binds `SSR_VK_R` to `SSR_CMD_LINES_TOGGLE`; the boxed comment at 192-199 ("RESET MOVED OFF R, and off every letter") is immediately followed by the `SSR_VK_0` → `SSR_CMD_RESET` binding at 200. `SSRKeyToCommand` is a first-match scan of that one table. In `ENUM_SSR_CMD`, RESET is ordinal 4 and LINES_TOGGLE is 20 — no accidental aliasing.

**Verifiers** — Same stale belief as `tests-b-1`, `ui-plumbing-2` and `ui-plumbing-3`: four copies of the key list, one table.

**Fix** [RECOMMENDATION] — `CheckEq("R toggles the lines", SSR_CMD_LINES_TOGGLE, SSRKeyToCommand(SSR_VK_R));` plus `CheckEq("0 resets", SSR_CMD_RESET, SSRKeyToCommand(SSR_VK_0));`. Then fix the real defect behind all four findings: delete `SSRKeyHint()`'s hand-written literal and generate it from `SSRKeyBindings` (see `ui-plumbing-3`), so there is exactly one list and this class of drift ends.

##### `tests-a-2` — MEDIUM — T5.2 asserts an 8-stop speed ladder against a 20-stop ladder

**File:** `SSR_T5_Ui.mq5:109` · **Category:** boundary

```mql5
      CheckEq("ladder has eight steps", 8, SSR_SPEED_LADDER_SIZE);
      CheckEq("slowest is 0.25x", SSR_SPEED_025, SSRSpeedLadder(0));
      CheckEq("fastest is 50x",   SSR_SPEED_50,  SSRSpeedLadder(7));
      CheckEq("1x sits at index 2", 2, SSRSpeedLadderIndex(SSR_SPEED_1));
```

**Failure scenario** [CONFIRMED FROM CODE] — All four fail on any run: 8 vs 20, 25 vs 10, 5000 vs 300, 2 vs 4. T5 can therefore never report GREEN, which removes the file's value as a gate — a reader who has learned that T5 is always red will not notice `tests-a-1` or `tests-a-4` when they appear beside it. Test-gate only; no product behaviour is affected.

**Why** [CONFIRMED FROM CODE] — `SSR_Types.mqh:302` is `#define SSR_SPEED_LADDER_SIZE 20`; `SSRSpeedLadder(0)` is 10 (0.1×), `SSRSpeedLadder(7)` is 300, 5000 is index 15 and `SSR_SPEED_MAX` is index 19; `SSR_SPEED_DEFAULT_IX` is 4 and `SSRSpeedLadder(4) == SSR_SPEED_1`, so the index lookup returns 4. The header comment at 257-274 says outright "Twenty stops, not eight, because the panel now has a trackbar" — the production change is documented and the test was never brought up to it. It still compiles because `ENUM_SSR_SPEED` kept its eight named values; only the ladder grew.

**Verifiers** — All four failures re-derived from the ladder table.

**Fix** [RECOMMENDATION] — Assert the ladder's *properties*, not a memorised copy of it, so the next resize does not break the test: `CheckEq("ladder is the declared size", SSR_SPEED_LADDER_SIZE, SSR_SPEED_LADDER_SIZE)` is worthless, so instead assert (a) `SSRSpeedLadder(i) < SSRSpeedLadder(i+1)` for every `i` — strict monotonicity, which the trackbar depends on; (b) `SSRSpeedLadderIndex(SSRSpeedLadder(i)) == i` for every `i` — round-trip; (c) `SSRSpeedLadder(SSR_SPEED_DEFAULT_IX) == SSR_SPEED_1` — the one anchor that matters. Three loops, no literals, and they would have caught the real defects in `tests-a-3`.

##### `tests-a-3` — MEDIUM (verifiers: LOW) — T5.5's three speed-clamp assertions fail

**File:** `SSR_T5_Ui.mq5:174` · **Category:** boundary

```mql5
      CheckEq("one step faster", SSR_SPEED_2, port.last_speed);
...
      CheckEq("cannot exceed the top", SSR_SPEED_50, port.last_speed);
...
      CheckEq("cannot go below the bottom", SSR_SPEED_025, port.last_speed);
```

**Failure scenario** [CONFIRMED FROM CODE] — Three more guaranteed failures in the same file: from 1× (100) SPEED_UP yields 150, not 200; from 50× (5000) it yields 7500 instead of clamping; from 0.25× (25) SPEED_DOWN yields 10, not 25. Worse than the count: the middle assertion no longer tests a clamp at all, because 50× is index 15 of 20 — **the real clamps at index 19 and index 0 are completely uncovered**. Production clamping is correct at both ends, so the cost is lost coverage plus a permanently red file; the verifiers put it at LOW for that reason.

**Why** [CONFIRMED FROM CODE] — `ExecuteInner` case `SSR_CMD_SPEED_UP` (2317-2322) is `i = SSRSpeedLadderIndex(m_state.speed_x100); if(i < SSR_SPEED_LADDER_SIZE - 1) i++; return m_port.SetSpeedX100(SSRSpeedLadder(i));`, mirrored by SPEED_DOWN with `if(i > 0) i--`. `CFakePort::SetSpeedX100` records the argument verbatim and each `Execute` is preceded by `panel.Render()`, so `m_state.speed_x100` is the value the test just set.

**Verifiers** — Traced end to end; severity dissent noted.

**Fix** [RECOMMENDATION] — Test the boundaries that exist: set the speed to `SSRSpeedLadder(SSR_SPEED_LADDER_SIZE-1)`, press SPEED_UP, assert the value is unchanged; set it to `SSRSpeedLadder(0)`, press SPEED_DOWN, assert unchanged; and for the step assertion use `SSRSpeedLadder(SSR_SPEED_DEFAULT_IX + 1)` rather than a literal. Written that way the section survives every future ladder edit and actually covers the two clamps.

##### `tests-a-1` — MEDIUM — T5.6's click assertion cannot pass

**File:** `SSR_T5_Ui.mq5:208` · **Category:** event-handling

```mql5
      string s = "SSRT5_play";
      panel.OnEvent(CHARTEVENT_OBJECT_CLICK, l, d, s);
      CheckEq("click reached the port", 1, port.play);
```

**Failure scenario** (verifiers' corrected version) [CONFIRMED FROM CODE] — Every run prints `FAIL click reached the port expected=1 actual=0`. `CSSRPanel::OnEvent` has no `CHARTEVENT_OBJECT_CLICK` branch, so the call is a no-op. The section titled "a click and a key take the same path" — the file header's second of three stated purposes — asserts nothing about clicks and is permanently red. The panel's behaviour is deliberate and correct; the defect is entirely in the test.

**Why** [CONFIRMED FROM CODE] — `grep CHARTEVENT_OBJECT_CLICK SSR_Panel.mqh` returns exactly one hit, the comment at 2878: "CHARTEVENT_OBJECT_CLICK is deliberately not handled here. PollClicks is the ONE mechanism". `OnEvent`'s branches are `CHARTEVENT_KEYDOWN` (palette, Ctrl+K, tag box, key table), `CHARTEVENT_OBJECT_ENDEDIT` and `CHARTEVENT_MOUSE_MOVE`; every other id falls through to `return false` at 2971. Clicks are consumed by `PollClicks()` (2445), which scans `ObjectsTotal(m_chart, -1, OBJ_BUTTON)` for prefixed names whose `OBJPROP_STATE` is latched.

**Verifiers** — `OnEvent` read in full; the panel is right and the test is wrong.

**Fix** [RECOMMENDATION] — Drive the mechanism the panel actually uses:

```mql5
      ObjectSetInteger(ChartID(), "SSRT5_play", OBJPROP_STATE, true);
      panel.PollClicks();
      CheckEq("click reached the port", 1, port.play);
```

That is the click path in production, it needs no new plumbing, and it makes the section's title true. Worth an added assertion that the latch is cleared afterwards — the un-latch is the half of `PollClicks` nothing currently tests.

#### C.5.14 QA scripts - `MQL5/Scripts/SSReplay/QA`

##### `qa-smoke-2` — MEDIUM — preflight's only tick check counts acceptance and never asks whether a bar was built

**File:** `SSR_QA_Preflight.mq5:397` · **Category:** zero-empty

```mql5
         int nadd = CustomTicksAdd(test, add);
         if(nadd == ArraySize(add))
            Ok("custom ticks", StringFormat("%d accepted", nadd));
         else
            Limit("custom ticks", ...
```

**Failure scenario** (verifiers' corrected version) [CONFIRMED FROM CODE] — Run the preflight on an index or futures CFD (`SYMBOL_CHART_MODE_LAST`). `CustomSymbolCreate` clones that chart mode onto the test symbol, the preflight never overrides it, and its 100 ticks carry `TICK_FLAG_BID|TICK_FLAG_ASK` only. MetaTrader accepts all 100, the script prints "OK custom ticks 100 accepted", and the run ends "VERDICT: GO" — on a terminal and symbol class where the replay will advance its clock, emit its ticks and produce no candle at all. The one script whose purpose is "fail in ninety seconds instead of after two hours of debugging" cannot see the failure that took longest to find. The section does still prove the bar path independently (500-bar `CustomRatesUpdate` + read-back + M5 derivation, 320-379), so only the **tick-to-bar** path is blind.

**Why** [CONFIRMED FROM CODE] — The check reads the return count and nothing else; there is no `CopyRates`, `Bars()`, `SeriesInfoInteger` or `CopyTicks` after the `CustomTicksAdd` anywhere in section 4 (383-438), and no `CustomSymbolSetInteger(test, SYMBOL_CHART_MODE, …)` anywhere in the file. The product guards it (`SSR_CustomSymbolManager.mqh:383` forces BID and reads it back) and the smoke asserts it (`SSR_QA_Smoke.mq5:473-481`); the preflight, which runs first and gates everything, asserts neither.

**Verifiers** — Whole section traced; the gap is the tick-to-bar link only.

**Fix** [RECOMMENDATION] — Two additions, both a few lines. Set the mode the product sets — `CustomSymbolSetInteger(test, SYMBOL_CHART_MODE, SYMBOL_CHART_MODE_BID)` — and add `TICK_FLAG_LAST` to the injected ticks, matching `SSR_TickSynthesizer`'s belt and braces. Then assert the consequence rather than the acceptance: after the `CustomTicksAdd`, `CopyRates(test, PERIOD_M1, tick_minute, 1, r)` and `Ok`/`Stop` on `r[0].close` matching the last injected bid. That converts the preflight from "the terminal took my ticks" to "the terminal built a candle from my ticks", which is what the gate is for.

##### `qa-smoke-1` — MEDIUM — the smoke harness aborts on an unprimed M1 series, and the priming call is nine lines below

**File:** `SSR_QA_Smoke.mq5:396` · **Category:** boundary

```mql5
   int have = Bars(origin, PERIOD_M1);
   if(!Check("M1 history present", have >= InpReplayBars + InpWarmupBars,
             StringFormat("%d bars local, %d needed",
                          have, InpReplayBars + InpWarmupBars)))
     {
      ... Done(); return;
```

**Failure scenario** (verifiers' corrected version) [CONFIRMED FROM CODE] — Drop `SSR_QA_Smoke` on an M5 (or H1, or D1) chart of a symbol whose M1 series has not been touched in this terminal session. `Bars(origin, PERIOD_M1)` returns 0 on that first read whether or not the bars exist, the Check fails, `Done()` runs and returns, and the harness reports "0 passed, 1 FAILED / 0 bars local, 600 needed" from a terminal on which the whole product works. Two qualifications: the abort needs the origin's M1 series to be genuinely untouched (a script dropped on an M1 chart of the same symbol, or any prior M1 read, primes it), and the damage is confined to the harness — it does not affect the product.

**Why** [CONFIRMED FROM CODE] — Nothing between `LogOpen` (316) and 396 touches the origin's M1 series, so this is the first read of that timeseries. The priming read exists nine lines later (409, `CopyRates(origin, PERIOD_M1, 0, InpReplayBars, back)`) and is unreachable because the Check aborts first. This is the project's own documented trap (overview lesson 7: "the first read always returns zero, and zero there means 'no series yet' … This cost an entire build"). `ssr_audit.py`'s A21 exempts `PERIOD_M1` with the stated reason "M1 is exempt because M1 is what this program WRITES" — true of the replay symbol, **not** of `origin`, which this program only reads. `SSR_QA_Preflight.mq5:191-201` handles exactly this case for the same symbol with an ask-twice loop and a 15-second wait, so the two harnesses disagree about a known hazard.

**Verifiers** — Traced from `OnStart`; the abort precedes the prime.

**Fix** [RECOMMENDATION] — Prime, then measure. Move the `CopyRates` at 409 above the Check and re-read: `CopyRates(origin, PERIOD_M1, 0, 1, probe); int have = Bars(origin, PERIOD_M1); if(have == 0) { Sleep(500); have = Bars(origin, PERIOD_M1); }` — the preflight's ask-twice pattern, borrowed verbatim. Then narrow A21's exemption to the replay symbol so the auditor catches the next read of a broker timeframe the program has not touched, which is the rule the exemption's own comment describes.

#### C.5.15 Spike and probe programs

##### `spikes-audits-4` — MEDIUM — A3 has no positive control

**File:** `SSR_A3_FutureIsolation.mq5:48` · **Category:** measurement validity

```mql5
int got = CopyRates(sym, tf, T + 1, far, r);
checks++;
if(got > 0)
  {
   leaks++;
```

**Failure scenario** (verifiers' corrected version) [CONFIRMED FROM CODE] — All four read paths record a verdict only when they find something beyond T (`got>0`, `it>T`, `nb>0`, `lastbar>T`), and every one of those is false when the underlying value is 0 — which is also what an unbuilt series answers. Nothing in A3 asserts that data **below** T exists on each of the seven timeframes. So an unknown subset of the 2800 assertions is vacuously true: at minimum the first pass over each of the six timeframes A3 never primes, plus every pass where a higher-timeframe series has not caught up with the rewrite at 139 (only M1 is waited on, at 141). A3 publishes "zero_future_leaks PASS across 2800 assertions" — the strongest claim in the suite — from a test with no assertion that would notice. The finder's stronger form ("a terminal that never builds M5..D1") overstates it, because path 1's `CopyRates` is itself a request that starts the series building.

**Why** [CONFIRMED FROM CODE] — The lazy-series ambiguity is the documented reason audit A21 exists (`ssr_audit.py:1556-1583`) and is handled explicitly by A2 ("an unasked-for series answers zero, and this metric is the whole point of the experiment", 208-209) and by D1 ("TOUCH EACH SERIES BEFORE COUNTING IT", 117-120). A3 primes only `PERIOD_M1` and never touches the other six with a non-future read.

**Verifiers** — `AuditCut` and `OnStart` read in full; the vacuity is bounded but real.

**Fix** [RECOMMENDATION] — Add the control the other spikes already have. Before the leak loop, for each of the seven timeframes, read the range **below** T (`CopyRates(sym, tf, T - far_span, T, r)`), wait with `SSR_WaitSeries`, and `SSR_Verdict("series_present_" + EnumToString(tf), got > 0, …)`. Then a zero on the future-side read means "no future data" rather than "no series", and the headline claim is worth its 2800 assertions. Cheap corollary: record `checks` per timeframe in the metrics so a reader can see which ones actually ran.

##### `spikes-audits-5` — MEDIUM — A3's `avg_rebuild_time` times the `SERIES_SYNCHRONIZED` flag

**File:** `SSR_A3_FutureIsolation.mq5:141` · **Category:** timer

```mql5
SSR_WaitSeries(InpTest, PERIOD_M1, 10000);
t_reset_sum += SSR_ElapsedMs(t0);
...
SSR_Metric("audit", "avg_rebuild_time",  t_reset_sum / MathMax(InpCuts, 1), "ms",
           "cost of a full history rebuild - feeds the Reset budget");
```

**Failure scenario** (verifiers' corrected version) [CONFIRMED FROM CODE] — The timed region (from `t0` at 131) spans `CustomRatesDelete` + `CustomTicksDelete` + `CustomRatesUpdate` + a `SERIES_SYNCHRONIZED` poll with a 10 s ceiling. The kit's own measurement says that flag takes about nine seconds after a custom-symbol rewrite "for 10,000 bars and for 100,000 bars alike — size-independent, so it is a timer, not work", while `CopyRates` returns the fresh bars in tens of milliseconds. So `avg_rebuild_time` reports ~9,000-10,000 ms per rebuild for work that takes tens of ms — and that number is explicitly labelled as feeding the product's **Reset budget**. Two refinements: on timeout `SSR_WaitSeries` returns `-1.0`, which A3 sums as −1 ms rather than flagging the sample unmeasured, so a terminal where the flag never sets produces an artificially **low** average; and the magnitude depends on which of the flag's three observed behaviours the terminal shows. Side effect: 100 cuts × up to 10 s makes A3's own runtime up to ~17 minutes.

**Why** [CONFIRMED FROM CODE] — `SSR_WaitSeries` (`SSR_SpikeKit.mqh:338-349`) polls nothing but `SERIES_SYNCHRONIZED`. The kit supplies `SSR_WaitLastBarBefore` for the tail-delete case and `SSR_WaitLastBar` for the re-seed case; A3 uses neither.

**Verifiers** — Mechanism confirmed; both refinements theirs.

**Fix** [RECOMMENDATION] — Wait on evidence, not on a flag: replace `SSR_WaitSeries` with `SSR_WaitLastBar(InpTest, PERIOD_M1, expected_last, 10000)`, which the kit already provides for exactly this case and which returns when the data is readable. Then treat a negative return as unmeasured — accumulate into a separate `t_reset_timeouts` counter and publish `avg_rebuild_time` over the measured samples only, with the timeout count beside it. D1 and D4 have both been converted this way already; A3 and D2 are what remain.

##### `spikes-audits-2` — MEDIUM — B1's `wick_expanded_to_extremes` verdict fails deterministically

**File:** `SSR_B1_TicksAddBroadcast.mq5:139` · **Category:** boundary

```mql5
if(h0 >= hi - point && l0 <= lo + point)
  { hl_expanded++; break; }
...
SSR_Verdict("wick_expanded_to_extremes", hl_expanded == nbars,
            IntegerToString(nbars), IntegerToString(hl_expanded),
            "high/low grow tick by tick");
```

**Failure scenario** (verifiers' corrected — arithmetic re-derived) [CONFIRMED FROM CODE] — The verdict fails deterministically with the defaults, but **by one bar, not seven**. Replaying the generators gives `hl_expanded = 19/20` for digits 1-5: the injected stream falls `0.0526 ×` the extreme-to-close leg short of each extreme (see `spikes-audits-1`), and `NormalizeDouble`'s rounding onto the point grid means a wick must exceed ~28.5 points to break the one-point tolerance. With this seed exactly one bar (index 17, a 39-point up wick, 2.05-point shortfall) does — so `hl_expanded == nbars` can never hold, and B1, a Tier-B blocker, records **SPIKE FAIL against the claim "candle builds natively from injected ticks" on a terminal whose broadcast is perfect**.

**Why** [CONFIRMED FROM CODE] — The chart high can never exceed the highest injected bid, and `SSR_BarToTicks` samples a three-segment path at `u = 3i/(cnt-1)`, which for `cnt=20` never lands on `u=1` or `u=2`. The one-point tolerance at 139 is therefore what decides the verdict, and it is tighter than the model's own shortfall.

**Verifiers** — Generators replayed exactly (xorshift64, seed 4242, base 38000, vol 25); the finder's 13/20 was wrong, 19/20 is right.

**Fix** [RECOMMENDATION] — Fix the generator, not the tolerance: with `spikes-audits-1`'s keypoint pinning applied to `SSR_BarToTicks`, the injected stream reaches both extremes exactly and `hl_expanded == nbars` becomes a true statement about the terminal rather than about the sampling grid. If the kit fix is deferred, make the tolerance model-aware — `double tol = MathMax(point, 0.06 * (hi - lo))` — and say so in the verdict's note, so the number B1 reports is about broadcast rather than about interpolation.

##### `spikes-audits-12` — MEDIUM — B3 prints its PASS criterion instead of asserting it

**File:** `SSR_B3_SessionBehavior.mq5:132` · **Category:** measurement validity

```mql5
Print("[B3] Compare acceptance_rate between no_sessions and sessions_247.");
Print("[B3] PASS requires sessions_247 acceptance_rate == 100%.");

SSR_End();
```

**Failure scenario** [CONFIRMED FROM CODE] — B3's only `SSR_Verdict` is the creation-failure path at 33. With both symbols created, `g_ssr_fail` stays 0 and `SSR_End` prints **SPIKE PASS** — even at 0 % acceptance, i.e. when the terminal silently drops every tick, which is the exact defect the spike exists to detect. A reader of `verdicts.csv` sees no B3 row at all; a reader of the log sees PASS. The printed summary does read "PASS=0 FAIL=0", the only hint that no assertion ran. Spike harness, not product code.

**Why** [CONFIRMED FROM CODE] — `accept_rate` is computed at 101 and recorded as a metric at 106; `silent_drops` at 116-118, likewise metric-only. The no-sessions vs sessions_247 comparison the hypothesis rests on (6-9) is left as English prose at 132-133. `SSR_Verdict` is the sole place `g_ssr_fail` is incremented (`SSR_SpikeKit.mqh:169`), and `SSR_End` prints `g_ssr_fail == 0 ? "SPIKE PASS" : "SPIKE FAIL"` (187-189).

**Verifiers** — Fully provable; the summary line is the only tell.

**Fix** [RECOMMENDATION] — Turn the two `Print`s into the assertions they describe: `SSR_Verdict("sessions_247_accepts_all", accept_247 >= 99.9, "100", DoubleToString(accept_247,1), "24/7 sessions accept every tick")` and a second comparing the two cases. Then make the harness incapable of this shape: have `SSR_End` print `SPIKE INCONCLUSIVE` when `g_ssr_pass + g_ssr_fail == 0` — one condition in the kit that retroactively protects every spike (`spikes-audits-13` is the same defect in D1).

##### `spikes-audits-10` — MEDIUM — D1 turns a readable-wait timeout into a zero wait

**File:** `SSR_D1_SeedPerformance.mq5:90` · **Category:** timer

```mql5
double t_total = (t_write + MathMax(t_read, 0)) / 1000.0;
SSR_Metric(c, "total_time", t_total, "s");
...
SSR_Metric(c, "bars_per_sec", (t_total > 0 ? total / t_total : 0), "bars/s",
           "write + readable - this is the number the user waits for");
```

**Failure scenario** [CONFIRMED FROM CODE] — `SSR_WaitReadable` returns `-1.0` on timeout; `MathMax(t_read, 0)` converts "the seed never became readable within 60 seconds" into "the seed became readable instantly". `total_time` collapses to the write-call time and `bars_per_sec` reports the highest number of the whole run **for the case that failed hardest** — published with the note that it is the number a user waits for. This is precisely the regression the surrounding comment says was already fixed once: D1:93-105 records that "dividing by write_time alone reported 5.5 MILLION bars/second on a seed that took 9.2 seconds to become usable - a number 500x too flattering". On the failure case the headline row and the explicitly-labelled "WRITE CEILING ONLY" row are numerically equal.

**Why** [CONFIRMED FROM CODE] — `SSR_SpikeKit.mqh:448-461`: the loop runs while `SSR_ElapsedMs(t0) < timeout_ms` and falls through to `return -1.0`. `readable_wait` does record −1 in the same row, so the evidence is present — but the derived headline metric is wrong and no verdict exists to catch it.

**Verifiers** — Traced exactly; the two rows collapse onto each other.

**Fix** [RECOMMENDATION] — Do not average an unmeasured sample into a measured one:

```mql5
   if(t_read < 0.0)
     { SSR_Metric(c, "total_time", -1, "s", "readable wait timed out - not measured");
       SSR_Verdict("seed_became_readable", false, "<60s", "timeout", "seed usable"); }
   else
     { ... existing arithmetic ... }
```

Add the `seed_became_readable` verdict unconditionally so a timeout is a FAIL rather than a flattering number, and apply the same `t_read < 0` guard anywhere else the kit's sentinel is consumed (`grep MathMax(t_read` finds the family).

##### `spikes-audits-7` — MEDIUM — D2's "live" pass re-sends identical tick timestamps

**File:** `SSR_D2_TimeframeSwitch.mq5:68` · **Category:** tick-ordering

```mql5
MqlTick tk[];
SSR_BarToTicks(m1[depth - 1], tk, 50, 20 * point, digits);
CustomTicksAdd(InpTest, tk);
```

**Failure scenario** (verifiers' corrected version) [CONFIRMED FROM CODE] — `m1[depth-1]` is a fixed bar, so `SSR_BarToTicks` produces the same 50 `time_msc` stamps on every one of the 70 iterations (10 repeats × 7 switches) of a `MeasureDepth` pass, and `CustomTicksAdd`'s return is never inspected. The `with_ticks=true` pass therefore cannot be distinguished from the idle pass, defeating the spike's headline condition — "again while ticks are actively being injected, which is the real condition a user will switch timeframes in" is not measured at all. That 69 of the 70 calls are refused outright rests on the project's own B2 measurement of duplicate-stamp refusal (`SSR_B2_TickThroughput.mq5:84-92`), which is observed runtime behaviour rather than a spec guarantee.

**Why** [CONFIRMED FROM CODE] — `SSR_BarToTicks` sets `time_msc = bar.time*1000 + i*59000/(cnt-1)` (`SSR_SpikeKit.mqh:586`), a pure function of the bar, and the bar index never changes inside `MeasureDepth`. B2 states the rule and fixed itself by carrying one forward-only `t_msc` base; D2 did not. Nothing in D2 records accepted counts, so the rejection is invisible in the results file.

**Verifiers** — `MeasureDepth` traced; stamps are byte-identical across the pass.

**Fix** [RECOMMENDATION] — Carry a forward-only base, as B2 does: keep `long t_base = m1[depth-1].time * 1000;` outside the loop, add `t_base += 60000;` each iteration, and pass it to a `SSR_BarToTicksAt(bar, tk, cnt, spread, digits, t_base)` overload. Then record the acceptance: `int acc = CustomTicksAdd(InpTest, tk); injected += acc;` and `SSR_Metric(c, "ticks_accepted", injected, …)` so a future regression to duplicate stamps shows up as a number rather than as a silently idle "live" pass.

##### `spikes-audits-6` — MEDIUM — D2 measures switch cost by polling `SERIES_SYNCHRONIZED`

**File:** `SSR_D2_TimeframeSwitch.mq5:81` · **Category:** timer

```mql5
if(SeriesInfoInteger(InpTest, g_cycle[i], SERIES_SYNCHRONIZED, sync) && sync != 0)
   if(Bars(InpTest, g_cycle[i]) > 0)
     {
      waited = SSR_ElapsedMs(t0);
      break;
     }
```

**Failure scenario** (verifiers' corrected version) [CONFIRMED FROM CODE] — Every `switch_to_<TF>` number, and the `worst_switch` that gates `tfswitch_<d>k_<mode>_under_1s`, is the time until `SERIES_SYNCHRONIZED` is set for the new timeframe, capped at 15 s and then **recorded as the elapsed time anyway on timeout** (89). On a terminal where the flag takes ~9 s after a custom-symbol rewrite, or is never set, D2 publishes 9,000-15,000 ms per switch and FAILS the 1 s gate on an explicit product requirement ("M1 → M5 → M15 → H1 without breaking replay") while the chart is in fact usable in tens of milliseconds. Because the timeout is recorded rather than marked unmeasured, a terminal where the flag never sets publishes a flat ~15,000 ms per switch as though it were measured work — silent in the results file as well as wrong.

**Why** [CONFIRMED FROM CODE] — The exit condition requires the flag to be non-zero before `Bars()` is even consulted, so the flag gates all 3 depths × 2 modes × 10 repeats × 7 switches = 420 timed waits. The kit documents the flag as size-independent, "a timer, not work", "observed at 0.002 ms, at 9,200 ms, and never" (390-417); D1 capped its own flag wait at 3 s because "this run spent 300 of its 315 seconds waiting for a flag that was never going to be set", and D4 records that the flag "sat on BOTH sides of this spike's headline ratio". D2 was never converted.

**Verifiers** — 72-101 traced; 420 waits all gated on the flag.

**Fix** [RECOMMENDATION] — Measure readability, not synchronisation: drop the `SERIES_SYNCHRONIZED` test and break as soon as `CopyRates(InpTest, g_cycle[i], 0, 1, r) > 0` returns the expected newest bar — `SSR_WaitLastBar` already implements exactly that. Record a timeout as `waited = -1` and exclude it from `worst`, publishing a `switch_timeouts` count beside the metric so the gate reports "not measured" instead of a fabricated 15 seconds. Same conversion as `spikes-audits-5`; the kit already has the helper.

##### `spikes-audits-23` — MEDIUM — D3's `throughput_stable` gate uses the baseline the file says hides the finding

**File:** `SSR_D3_SustainedRun.mq5:216` · **Category:** measurement validity

```mql5
SSR_Verdict("throughput_stable", rate_drop <= 10.0, "<=10% drop",
            StringFormat("%.1f%%", rate_drop), "");
```

**Failure scenario** [CONFIRMED FROM CODE] — `rate_drop` is computed from `rate_first`, which is assigned only once `minute >= 10` (125-129). On the run the file itself describes — 12,000 ticks/s falling to about 780 **before** minute 10 — `rate_first` and `rate_last` are both ~780, `rate_drop` is near zero, and `throughput_stable` PASSES on a run that lost 94 % of its throughput. The remedy actually applied was to add `rate_peak`, `rate_at_min1`, `decay_peak_to_end` and `decay_min1_to_end` as *metrics*; the gate that produces the PASS/FAIL line and the `verdicts.csv` row was left on the window the comment (176-182) says hides the problem.

**Why** [CONFIRMED FROM CODE] — `rate_first` is initialised to −1 at 88 and set only inside `if(minute >= 10.0 && mem_first < 0)`; `rate_drop` at 160 is `100*(rate_first-rate_last)/rate_first`; the else-branch verdict at 216-217 consumes exactly that. `decay_peak_to_end` is recorded at 187-190 and **no verdict reads it**.

**Verifiers** — Traced end to end; the diagnosis is in the file's own comment.

**Fix** [RECOMMENDATION] — Gate on the number the file already computes: `SSR_Verdict("throughput_stable", decay_peak_to_end <= 10.0, "<=10% from peak", …)`, keeping `rate_drop` as a secondary metric. One identifier changed, and the verdict then reports the decay the author went to the trouble of measuring.

##### `spikes-audits-8` — MEDIUM — D4's 1-bar tail-delete timing skips the rebuild on 16 of 20 trials

**File:** `SSR_D4_RewindCost.mq5:97` · **Category:** timer

```mql5
datetime cut = m1[InpDepth - 1 - i].time;
ulong t = SSR_Now();
CustomRatesDelete(InpTest, cut, D'2038.01.01 00:00');
CustomTicksDelete(InpTest, (long)cut * 1000, LONG_MAX);
SSR_WaitLastBarBefore(InpTest, PERIOD_M5, cut, 15000);
double e = SSR_ElapsedMs(t);
```

**Failure scenario** (verifiers' corrected version) [CONFIRMED FROM CODE] — `SSR_WaitLastBarBefore` returns as soon as the last **M5** bar's open is `< cut`. In strategy 1 the cut is the currently-last M1 bar, so the enclosing M5 bar's open is already strictly below it whenever that minute index is not a multiple of five — 16 of the 20 trials with the shipped `InpStart`/`InpDepth`. Those trials return on the first `CopyRates`, before the delete has propagated, so `tail_1bar.avg` times only the synchronous delete calls and omits the series-rebuild cost. That average gates `step_back_interactive` (≤500 ms), `step_back_usable` (≤3000 ms) and the published `rebuild_over_tail_ratio`, whose other half (strategy 3) *does* wait properly on exact M1 equality — inflating the ratio and letting the gates pass on an incomplete measurement. Spike/measurement code, not product runtime; the delete calls' own cost is still real.

**Why** [CONFIRMED FROM CODE] — `SSR_GenM1` sets `out[i].time = start + i*60` and `InpStart = D'2023.01.02 00:00'` = 1672617600, exactly divisible by 300, so the M5 grid is aligned to the seed; for `cut = m1[k].time` with `k % 5 != 0` the predicate holds before and after the delete. For `k` in 99999..99980 only four indices are multiples of 5. Strategy 2 (cut 100 bars below the last) is unaffected.

**Verifiers** — Arithmetic re-derived; the file's own comment records that its previous timing "was mostly a measurement of a flag" — the data-based replacement is vacuous here for a different reason.

**Fix** [RECOMMENDATION] — Wait on the timeframe the cut is expressed in: `SSR_WaitLastBarBefore(InpTest, PERIOD_M1, cut, 15000)`. M1 is the series being deleted, so the predicate is not pre-satisfied. Keep an M5 wait as a second, separately-reported number if the propagation to derived timeframes is interesting — but do not let it stand in for the M1 rebuild the ratio is about.

##### `spikes-audits-9` — MEDIUM — D4 loses its chart at the strategy-2 restore

**File:** `SSR_D4_RewindCost.mq5:106` · **Category:** object-lifecycle

```mql5
//--- restore, then strategy 2: delete a 100-bar tail
SSR_DropSymbol(InpTest);
SSR_MakeSymbol(InpTest, g_origin);
```

**Failure scenario** (verifiers' corrected version) [CONFIRMED FROM CODE] — `SSR_DropSymbol` closes every chart showing the symbol, so the M5 chart opened at 82 is destroyed here and never reopened: strategy 1 is measured **with** a chart attached, strategies 2 and 3 with none. `rebuild_over_tail_ratio` therefore compares a with-chart tail delete against a no-chart full rebuild, and `cid` becomes a stale id that 158 still passes to `ChartClose`. The resulting bias is conservative — it lowers the ratio and raises `avg1`, making the gates harder to pass — so the substantive defect is the header instructing an indicator-attach step the script structurally prevents: it promises "with and without indicators on the chart, because indicator recalc is the cost that is easy to forget" and says "Attach MA, RSI and Bollinger to the test chart before running the indicators pass", while the chart is created by the script at 82 and `ChartIndicatorsTotal(cid,0)` is read two seconds later, with no input, pause or second pass that would allow it.

**Why** [CONFIRMED FROM CODE] — `SSR_DropSymbol` (`SSR_SpikeKit.mqh:209-224`) walks `ChartFirst`/`ChartNext` and closes every matching chart, and `SSR_MakeSymbol` itself begins with `SSR_DropSymbol` and never opens a chart. Strategy 3 calls `SSR_DropSymbol` again at 134 on every trial.

**Verifiers** — Confirmed; bias direction is theirs.

**Fix** [RECOMMENDATION] — Re-open the chart after each restore: extract the 82-85 block into `long OpenTestChart()` and call it after every `SSR_MakeSymbol`, storing the fresh id in `cid`. For the promised indicators pass, add `input bool InpIndicatorPass = false;` and, when set, `Print("attach MA/RSI/Bollinger to chart %I64d, then re-run with InpIndicatorPass") ; return;` after opening the chart — an honest two-run procedure instead of a header that describes something the script cannot do.

##### `spikes-audits-21` — MEDIUM — C2's restart detector false-fails after the first run, and the event it hunts destroys its evidence

**File:** `SSR_C2_ServicePersistence.mq5:58` · **Category:** session-resume

```mql5
double prev_marker = GlobalVariableGet("SSR.c2.launches");
GlobalVariableSet("SSR.c2.launches", prev_marker + 1);
...
SSR_Verdict("no_restart", GlobalVariableGet("SSR.c2.launches") <= 1.0, "1",
            DoubleToString(GlobalVariableGet("SSR.c2.launches"), 0),
            "more than 1 means the service was restarted");
```

**Failure scenario** (verifiers' corrected version) [CONFIRMED FROM CODE] — MT5 global variables persist on disk between runs and C2 never deletes this one, so run 2 onward starts from a non-zero marker and `no_restart` FAILs although the service never restarted: the verdict measures "has this spike been run before", not "did the service restart". Line 127 asks the operator to delete the GV by hand, making a correct result depend on a manual step. Separately, the heartbeat CSV is opened `FILE_WRITE` (63), which truncates, so an actual mid-run restart erases every pre-restart row — destroying the record the header names as the PASS criterion ("heartbeat counter never resets and no gap exceeds 3000 ms"). A truncated CSV starting again at `seq=1` with a low uptime is itself circumstantial evidence of a relaunch; what is irrecoverably lost is the pre-restart row history and gap statistics.

**Why** [CONFIRMED FROM CODE] — No `GlobalVariableDel("SSR.c2.launches")` exists anywhere in the file, while sibling spikes C1 (157) and C3 (127-132) delete their own GVs — so this is an oversight, not a convention. `seq` is a local initialised to 0, so the GV is the only cross-restart evidence.

**Verifiers** — Both halves verified by grep and by reading the siblings.

**Fix** [RECOMMENDATION] — Scope the marker to the run: delete the GV in `OnStart` before reading it and re-create it, using a second GV (`SSR.c2.run_id`, set to `TimeLocal()`) to distinguish "this run" from "a previous run" — the shape C3 already uses. Open the CSV `FILE_READ|FILE_WRITE` and `FileSeek(h, 0, SEEK_END)` so a restart appends rather than truncates, writing the launch marker as the first column of each row; the counter reset is then visible **in the file**, which is what the PASS criterion needs.

### C.6 LOW (105)

Bounded wrongness, dead branches, cosmetic overruns and assertions that cannot fail. Several are latent behind a CRITICAL or HIGH above and become live when it is fixed — each says so. [CONFIRMED FROM CODE]

#### C.6.1 Host expert - `MQL5/Experts/SSReplay/SSReplayStandalone.mq5`

##### `host-expert-10` — LOW — extra streams and the settings block bypass the `Cfg*()` accessors

**File:** `SSReplayStandalone.mq5:495` · **Category:** input-validation

```mql5
      g_ctrl2[built].SetSpreadPoints(InpSpreadPoints);      // 495
      g_charts2[built].OpenChart(InpChartTf);               // 511
      out.spread_points = InpSpreadPoints;                  // 424
      out.chart_tf      = InpChartTf;                       // 425
```

**Failure scenario** (verifiers' corrected version — the finder's list was too long) [CONFIRMED FROM CODE] — A user sets spread 8 and chart timeframe M15 in the setup form and runs with `InpAlsoSymbols="XAUUSD,GBPUSD"`. The primary stream gets `CfgSpread()=8` and an M15 chart (1145, 1275) while both extra instruments load with `InpSpreadPoints` and open on `InpChartTf`: three charts on one clock disagreeing about the execution assumption and the timeframe, with nothing in the log saying so. `CollectSettings` has the same bypass for `blind`, `spread` and `chart_tf`. Of the six fields the finder named, only those three have an accessor to bypass — pause mode, slot and ticks per bar have no setup-panel field and no accessor, so recording the input is all they could record. The extra streams' only bypasses are 495 and 511: extra timeframes do come through `CfgExtraTfs()` (1288) and anonymity through `g_blind.Anonymous()` (491).

**Why** [CONFIRMED FROM CODE] — `CfgSpread()` (218) and `CfgChartTf()` (221) exist precisely so "every reader goes through these, so there is one place that knows which of the two wins" (206-213). Impact is bounded because nothing reads the session file's settings block at resume: the host reads only `ReadWindow` and `ReadSymbols` (1066, 1325), and `ReadSettings` has a single caller, `SSR_T12_Session.mq5:497`.

**Verifiers** — Exact lines confirmed; field list narrowed.

**Fix** [RECOMMENDATION] — Three substitutions: `CfgSpread()` at 495, `CfgChartTf()` at 511, and `CfgBlind()`/`CfgSpread()`/`CfgChartTf()` at 419-425. Then make the rule enforceable rather than remembered: add an audit rule alongside A19/A20 in `ssr_audit.py` that flags any use of `InpSpreadPoints`, `InpChartTf`, `InpBlind`, `InpSession`, `InpSeed` or `InpRandom` outside the accessor bodies themselves. The comment at 206-213 already states the invariant; the auditor can hold it.

##### `host-expert-11` — LOW — `EnsureHistory`'s 60-second budget breaks at the `GetTickCount` wrap

**File:** `SSReplayStandalone.mq5:651` · **Category:** boundary

```mql5
   ulong t0 = GetTickCount();
   int   stalls = 0;
   while(have < want_bars && (GetTickCount() - t0) < 60000 && !IsStopped())
```

**Failure scenario** (verifiers' corrected framing) [CONFIRMED FROM CODE] — `t0` is a `ulong` while `GetTickCount()` returns a `uint`, so the fresh value is **widened rather than wrapped** and any iteration after the 49.7-day wrap computes a 64-bit underflow near 2^64, which is ≥ 60000 and ends the loop. The realistic effect is an early exit part-way through a download (`EnsureHistory` falls out and prints its normal tail line), not a systematic no-op: the wrap must fall inside the loop's own lifetime, roughly a 60 s window in each 49.7 days.

**Why** [CONFIRMED FROM CODE] — The same pattern is wrap-safe elsewhere in the file because both operands are `uint`: 2894 (`uint now_ms = GetTickCount()`) and 3145 (`g_ready_at_ms` declared `uint` at 345). Only `t0` at 651 is widened. `GetTickCount64()` is the wrap-free primitive and is not used here.

**Verifiers** — Arithmetic provable; probability framing corrected.

**Fix** [RECOMMENDATION] — `ulong t0 = GetTickCount64();` and compare with `GetTickCount64() - t0`. One word, no wrap, and it matches the intent of a `ulong` local. Worth a sweep: `grep -n "GetTickCount()" MQL5/` and convert any other site that stores the result in something wider than `uint`.

##### `host-expert-4` — LOW — the first-run card can never appear in one-window mode

**File:** `SSReplayStandalone.mq5:1736` · **Category:** session-resume

```mql5
   if(InpFirstCard && !one_chart_ok && g_panel_chart != 0)
```

**Failure scenario** (verifiers' corrected version) [CONFIRMED FROM CODE] — With `InpFirstCard=true` and `InpOneChart=true` (both defaults) the onboarding card shows on neither pass: pass 1 is excluded because `one_chart_ok` is true, pass 2 by the same test because `OnInit` re-reads `one_chart_ok = InpOneChart` (1893). `seen.txt` is never written either, so the card is not "used up" — it simply never exists for any user of the default mode. The comment at 1728-1735 says the marker exists so the card cannot "show on the pass with no replay chart and be gone on the pass that has one"; the guard beside it produces the second half of exactly that outcome. Latent behind `host-expert-1`; the loss is an onboarding card.

**Why** [CONFIRMED FROM CODE] — Identical mechanism to `host-expert-3`: `!one_chart_ok` is false on both passes. `g_panel_chart` is non-zero on pass 2 (set at 1449/1463), so that clause is not what blocks it.

**Verifiers** — Verified independently of `host-expert-3`.

**Fix** [RECOMMENDATION] — Use the same `will_hand_over` local proposed in `host-expert-3`: `if(InpFirstCard && !will_hand_over && g_panel_chart != 0)`. Both findings then close with one expression, which is the point of extracting it.

##### `host-expert-2` — LOW — on the replay chart `InpSymbol` is ignored, so the advised recovery cannot work

**File:** `SSReplayStandalone.mq5:1903` · **Category:** input-validation

```mql5
   string origin = (on_replay ? stashed
                              : (InpSymbol == "" ? _Symbol : InpSymbol));
...
      Print("[host] this chart is already a replay symbol and I do not know "
            "which instrument it came from. Attach SS Replay to a normal "
            "chart, or set InpSymbol to the origin, and try again.");
```

**Failure scenario** (verifiers' corrected version) [CONFIRMED FROM CODE] — A user whose second pass lost the stash (every one-window run today — `host-expert-1`) reads the advice, sets `InpSymbol="EURUSD"` and re-attaches to the replay chart. The ternary takes the `on_replay` branch, `InpSymbol` is never consulted, `origin` is `""` again, and `OnInit` fails with the identical message. Only one of the two offered remedies is impossible — attaching to a normal chart works, and the chart can be switched back by hand — so the harm is a misleading log line plus a lost workaround for the CRITICAL above, not a dead end.

**Why** [CONFIRMED FROM CODE] — `InpSymbol` appears only in the else branch; the guard at 1911 tests `origin == ""` after that assignment and the message at 1915-1917 names `InpSymbol` as a remedy.

**Verifiers** — Confirmed from source; a re-attach with `InpSymbol` set fails identically.

**Fix** [RECOMMENDATION] — `string origin = (on_replay ? (stashed != "" ? stashed : InpSymbol) : (InpSymbol == "" ? _Symbol : InpSymbol));` — one line that makes the printed advice true and hands `host-expert-1` a manual escape hatch in the meantime.

##### `host-expert-14` — LOW — the setup panel's drag handler can never fire

**File:** `SSReplayStandalone.mq5:2069` · **Category:** event-handling

```mql5
         g_setup_ui.Create(ChartID(), sv);
         g_picking = true;
         EventSetMillisecondTimer(200);
         return INIT_SUCCEEDED;
```

**Failure scenario** [CONFIRMED FROM CODE] — The setup window that accompanies the start picker is written to be dragged by its caption, and that is its only event-driven behaviour — but during the picking phase nothing has turned `CHART_EVENT_MOUSE_MOVE` on. `CSSRSetupPanel::OnChartEvent` returns immediately for every id except `CHARTEVENT_MOUSE_MOVE`, so the host's forwarding call at 3110 always returns false and the window cannot be moved. Its buttons still work because the timer polls `OBJPROP_STATE`, so the failure is silent: a window that looks draggable and is not.

**Why** [CONFIRMED FROM CODE] — The only writer of that chart property in the whole Include tree is the main panel (`SSR_Panel.mqh:318` save, `324` set inside `Create`, `370` restore), and `Create` is called at 1453/1467 — after the picker has returned. `CSSRSetupPanel::Create` touches only `CHART_MOUSE_SCROLL`. The panel's restore at 370 means a previous session does not leave it enabled either.

**Verifiers** — Both halves traced; grep finds three writes, all in the panel. Same root cause as `ui-dialogs-6`.

**Fix** [RECOMMENDATION] — Have the setup panel own the property it needs: in `CSSRSetupPanel::Create`, save the current value and `ChartSetInteger(m_chart, CHART_EVENT_MOUSE_MOVE, true)`; restore it in `Destroy`, exactly as `CSSRPanel` does. Two small blocks copied from a working neighbour, and the drag the class was written for starts working.

##### `host-expert-9` — LOW — the one-shot spread diagnostic is consumed by the picker phase

**File:** `SSReplayStandalone.mq5:2260` · **Category:** spread

```mql5
   if(total < 120 && g_timer_ticks < 500)
      return;

   g_spread_reported = true;
```

**Failure scenario** [CONFIRMED FROM CODE] — `ReportSpreadOnce()` is called as the second statement of `OnTimer` (2455/2458), **before** the `g_picking` guard, and the picker runs the timer at 200 ms. A user who spends more than 100 seconds choosing a start — which is the picker's entire purpose — reaches `g_timer_ticks == 500` with the controller not yet loaded, so `total == 0`, the latch is set, and the log gets "no bar has been replayed yet - press Play, or raise the speed, and this line will answer itself". `BuildSession` resets `g_timer_ticks` (1577) but never `g_spread_reported`, so the line the comment at 2213-2222 calls "the one that says whether this history can show you a release at all" is never printed for that session.

**Why** [CONFIRMED FROM CODE] — `g_spread_reported` is assigned only at 2263 and never reset (two occurrences in the file). Before `Load`, `SpreadBarsRecorded`/`SpreadBarsFixed` are 0 and `EffectiveFidelity()` defaults to SYNTHETIC_TICK, so the "no bar yet" branch is the one taken. 500 × 200 ms = 100 s; the comment beside the condition reasons about "twenty seconds" at the 40 ms engine interval and did not account for the picker's slower timer.

**Verifiers** — Trace holds; `g_timer_ticks++` is the first statement of `OnTimer`, so it counts picker ticks.

**Fix** [RECOMMENDATION] — Do not run the diagnostic before there is a session: move the call below the `g_picking` early-return, and reset `g_spread_reported = false;` in `BuildSession` beside the `g_timer_ticks` reset. Either alone fixes it; both together also make the tick-count reasoning in the comment true again.

##### `host-expert-13` — LOW — the picker path rebuilds with `InpOneChart`, discarding the poison

**File:** `SSReplayStandalone.mq5:2555` · **Category:** session-resume

```mql5
         if(!BuildSession(g_origin, false, InpOneChart))
```

**Failure scenario** (verifiers' corrected version) [CONFIRMED FROM CODE] — `OnInit` computes `one_chart_ok` as a local (1893-1901), starting from `InpOneChart` and forced false by the `"!"` poison a failed second pass writes. When the picker is active `OnInit` returns `INIT_SUCCEEDED` and the build happens later in `OnTimer`, where the poison is gone and `InpOneChart` is passed instead — so a run that was told not to attempt the handover attempts it again. Doubly latent: in the shipped build the poison can never be written at all, because `FailInit` stashes `"!"+g_origin` only when `g_on_replay_chart && g_origin != ""`, and today's pass-2 failure happens precisely with `g_origin == ""` (`host-expert-1`). The discarded flag never differs until that is fixed.

**Why** [CONFIRMED FROM CODE] — `one_chart_ok` is a function-local never stored in a global, and 2555 has no access to it. The comment at 1262-1274 explains that testing the input instead of the flag at the other call site left a recovery run with no replay chart at all.

**Verifiers** — Confirmed; reachability is narrower than the finder allowed.

**Fix** [RECOMMENDATION] — Promote it: `bool g_one_chart_ok = false;` beside the other globals, assigned in `OnInit` where the local is computed, and passed at 2555 and 2080. That also makes the flag visible to the vitals line, which is where a reader would look to ask why the handover was skipped.

#### C.6.2 Core engine - `MQL5/Include/SSReplay/Core`

##### `core-sync-3` — LOW — the generic `NextBarOpen` reads through the future guard

**File:** `SSR_IDataSource.mqh:160` · **Category:** future-guard

```mql5
      for(int i = 0; i < 4; i++)
        {
         int n = ReadBars(symbol, after_msc + 1, after_msc + spans[i], tmp);
         if(n > 0)
            return SSRToMsc(tmp[0].time);
        }
```

**Failure scenario** (verifiers' corrected version — **test-harness only**) [CONFIRMED FROM CODE] — For any provider that does not override `NextBarOpen` (the memory provider, and any future CSV or external source) with the guard armed at `horizon == now`, every one of the four spans passes `from_msc = now + 1 > horizon`, so `ClampRange` records a `Violation` and returns false. The answer is always `SSR_INVALID_TIME` from inside a gap — so gap-skipping silently never works with such a source — and the guard's violation counter, the product's leak alarm, climbs by 4 per step forward and 4 per second of idle playback, indistinguishable from a real leak. Blast radius is the test and QA harness only: `CSSRMt5BarProvider` overrides with a times-only `CopyTime` walk (302+), and `CSSRMemoryDataSource` is referenced only by `Scripts/SSReplay/Tests/*`. The functional half is masked in tests too, because `StepBars` falls back to `SSRNextBarOpenMsc(now, PERIOD_M1)` (1165), so dense in-memory data still advances. A design smell and a latent trap for a future non-MT5 source.

**Why** [CONFIRMED FROM CODE] — `SSR_FutureGuard.mqh:90-106`: `if(from_msc > m_horizon_msc) { Violation(from_msc); return false; }`; the memory provider's `ReadBars` calls `GuardRange` first. The comment at 143-148 acknowledges the INVALID answer ("correctly, and uselessly") but not the violation count. `T1.4` asserts `Violations()==0` after pumps only — adding one `StepBars` would fail it.

**Verifiers** — Mechanism provable; line citation and blast radius corrected.

**Fix** [RECOMMENDATION] — Make the generic implementation a times-only walk that does not go through the guard, the same argument the MT5 override already makes: a bar's *open time* is schedule, not price. Add a protected `virtual int ReadBarTimes(symbol, from, to, datetime &out[])` defaulting to the guarded `ReadBars` for sources that cannot separate the two, and have `NextBarOpen` call it with the guard temporarily disarmed (or with a `Violation`-free query method on the guard). Then add a `StepBars` to `T1.4` so the counter's meaning is defended.

##### `core-sync-4` / `core-engine-9` — LOW — `RecordPump` is handed the cumulative bar count

**File:** `SSR_Metrics.mqh:108` and `SSR_ReplayController.mqh:1035` · **Category:** cpu/diagnostics — *two findings, one defect; they are listed separately in `verified.json` and fixed by one change*

```mql5
      m_pumps++;
      m_ticks += ticks;
      m_bars  += bars;                       // SSR_Metrics.mqh:108
...
      m_metrics.RecordPump((double)(GetMicrosecondCount() - t_pump),
                           m_pump_emit_us, emitted,
                           (int)m_cursor.bar_count, m_pump_deferred);   // controller 1035, 1110
```

**Failure scenario** (verifiers' corrected version) [CONFIRMED FROM CODE] — `RecordPump` is documented "one pump completed" and sums `bars`, but both call sites pass `(int)m_cursor.bar_count` — the cursor's **running total**, itself already inflated by `core-engine-5` — while `emitted` in the same argument list is correctly per-pump. After P pumps `m_bars` is the sum of prefix totals, i.e. quadratic in pump count. It is invisible today: `SSRPerfSnapshot.bars` has no reader anywhere in the tree and is not printed by `ToString`, and `m_bars` is a `long`, so there is no overflow. A latent inconsistency that becomes a wrong number the moment someone displays it.

**Why** [CONFIRMED FROM CODE] — `SSRReplayCursor::Advance` does `bar_count += bars` (`SSR_ReplayCursor.mqh:65`); `CSSRMetrics::RecordPump` does `m_bars += bars`; `Snapshot` copies it to `out.bars` (182) and `PerfInto` exposes it.

**Verifiers** — Both call sites confirmed; the finder's line citations for `SSR_Metrics.mqh` were wrong (108, not 476) and are corrected here.

**Fix** [RECOMMENDATION] — Pass the per-pump figure: hold `int bars_this_pump` from `EmitWindow`'s return path (or take the delta `m_cursor.bar_count - bar_count_before`) and pass that at 1035 and 1110. Fix `core-engine-5` at the same time so the delta counts distinct bars, and the two findings close together with `SSRPerfSnapshot.bars` finally meaning what its name says.

##### `core-engine-8` — LOW — `RestoreSnapshot` overwrites live settings with the checkpoint's copy

**File:** `SSR_ReplayController.mqh:1630` · **Category:** session-resume

```mql5
      m_state    = snap.state;
      m_clock    = snap.clock;
      m_cursor   = snap.cursor;
      m_timeline = snap.timeline;
```

**Failure scenario** (verifiers' corrected version) [CONFIRMED FROM CODE] — The user starts at SYNTHETIC, switches the panel to BAR (`SetFidelity` writes both `m_state.fidelity` and `m_fidelity.SetRequested`), then presses `←`. `RestoreSnapshot` puts `m_state.fidelity` back to SYNTHETIC while `m_fidelity.Requested()` stays BAR, so `GroupPort:110` (`c.Fidelity()`) and `:111` (`EffectiveFidelity()`) disagree and the panel shows requested SYNTHETIC / effective BAR as if the policy had degraded — and `SaveInto` persists the stale value. `ClearError()` at 1612 is undone by the copy of `last_error`/`last_error_text`. The clock **is** restored (1631), so speed is not desynchronised; the speed issue is only that a per-stream speed the user has since changed is reverted and then saved. Also on these lines: `status` is assigned directly at 1630/1650-1651 rather than through `Transition()`, so `CSSRReplaySink::OnStateChanged` never fires for a restore.

**Why** [CONFIRMED FROM CODE] — `TakeSnapshot` copies the whole `SSRReplayState` struct (1600) including `fidelity`, `speed_x100`, `status`, `last_error`, `last_error_text` (`SSR_ReplayState.mqh:32-39`), and `RestoreSnapshot` restores `m_state` without restoring `m_fidelity`.

**Verifiers** — Verified field by field; the clock correction is theirs.

**Fix** [RECOMMENDATION] — Restore position, not preferences. Copy the snapshot's state field by field and keep the live values for the four that are settings rather than position:

```mql5
      ENUM_SSR_FIDELITY keep_fid = m_state.fidelity;
      int keep_speed = m_state.speed_x100;
      m_state = snap.state;
      m_state.fidelity = keep_fid; m_state.speed_x100 = keep_speed;
      m_state.last_error = SSR_OK; m_state.last_error_text = "";
      Transition(snap.state.status);          // instead of the direct assignment
```

`Transition` also restores the sink notification the direct assignment skips.

##### `core-engine-7` — LOW — `RestoreSnapshot` re-seats the cursor only on a strict inequality

**File:** `SSR_ReplayController.mqh:1637` · **Category:** boundary

```mql5
      long actual = m_sink.TruncateFrom(snap.taken_at_msc);
      ...
      m_cursor   = snap.cursor;
      ...
      if(actual < m_cursor.emitted_msc)
         m_cursor.RewindTo(actual);
```

**Failure scenario** (verifiers' corrected version) [CONFIRMED FROM CODE] — The sink contract deletes everything **at or after** the returned cut, while the cursor claims everything up to and **including** `emitted_msc` was delivered. A checkpoint is taken after emission, so `snap.cursor.emitted == snap.taken_at`; when the MT5 sink's cut (floored to the M1 open) equals `taken_at` — the checkpoint fell exactly on a bar open — `actual == emitted`, the cursor is not rewound, and the tick stamped at that instant (the synthesised open tick) is deleted from the custom symbol and never re-emitted. The rebuilt M1 bar then opens at the second synthetic tick's price. The test should be `actual <= m_cursor.emitted_msc`. But the simple fix collides with a second defect on the same line: `RewindTo` also zeroes `tick_count` and `bar_count` (`SSR_ReplayCursor.mqh:41-47`), so in the **common** mid-minute case, where the branch does fire, `RestoreSnapshot` already discards the session counters the store exists to preserve (`SSR_SnapshotStore.mqh:5-19`). The rare boundary case preserves the counters and loses the open tick; the common case does the reverse.

**Why** [CONFIRMED FROM CODE] — `Truncate` floors to the M1 open, deletes from there inclusive, and returns `bar_open` (`SSR_CustomSymbolManager.mqh:712-744`), matching the contract at `SSR_IReplaySink.mqh:46-59`. `Pump` advances the cursor to `now` before `TakeSnapshot` sets `taken_at_msc = m_clock.now_msc`. `SeekTo` (1236) and `Reset` (1285) use `RewindTo(actual)` unconditionally and are correct.

**Verifiers** — Both halves provable; the counter-reset is the larger of the two.

**Fix** [RECOMMENDATION] — Split the two jobs. Add `void SeatAt(const long msc)` to `SSRReplayCursor` that sets `emitted_msc = msc - 1` and leaves `tick_count`/`bar_count` alone, then in `RestoreSnapshot` write `if(actual <= m_cursor.emitted_msc) m_cursor.SeatAt(actual);`. `RewindTo` keeps its counter-zeroing semantics for `Reset`, where zeroing is right. One new method, both defects closed.

#### C.6.3 Data layer - `MQL5/Include/SSReplay/Data`

##### `data-9` — LOW — `SSR_NEWS_ALL` still filters at LOW importance

**File:** `SSR_Calendar.mqh:59` · **Category:** boundary

```mql5
int SSRNewsFloor(const ENUM_SSR_NEWS n)
  {
   if(n == SSR_NEWS_HIGH)     return (int)CALENDAR_IMPORTANCE_HIGH;
   if(n == SSR_NEWS_MODERATE) return (int)CALENDAR_IMPORTANCE_MODERATE;
   return (int)CALENDAR_IMPORTANCE_LOW;
  }
```

**Failure scenario** (verifiers' corrected version) [CONFIRMED FROM CODE] — There is no `SSR_NEWS_ALL` branch: the fall-through returns LOW, so the widest setting the UI offers — labelled "Everything the calendar has" — is still a filter, and every entry published at `CALENDAR_IMPORTANCE_NONE` is dropped by `Pull`'s `if((int)ev.importance < min_importance) continue;`. `Note()` then says "the calendar is there, and holds nothing at this importance for these currencies in this window", attributing the absence to a filter the user just set to maximum. That the excluded class is specifically bank holidays and other non-scheduled entries depends on how MetaTrader publishes them, which this repository cannot settle; the label/behaviour mismatch is source-provable. [POTENTIAL_RISK for the holiday specifics.]

**Why** [CONFIRMED FROM CODE] — `ENUM_CALENDAR_EVENT_IMPORTANCE` orders NONE(0) < LOW(1) < MODERATE(2) < HIGH(3), the code relies on that ordering throughout, and `Pull`'s filter is the single insertion point into `m_items`.

**Verifiers** — Confirmed; the enum's own label is what makes it a defect rather than a choice.

**Fix** [RECOMMENDATION] — One token: `if(n == SSR_NEWS_ALL) return (int)CALENDAR_IMPORTANCE_NONE;` before the fall-through, leaving the fall-through as the LOW case for any future value. Then `Note()`'s message becomes true at every setting.

##### `data-7` — LOW — `Discover()` discards the last complete M1 bar whenever quoting has stopped

**File:** `SSR_Mt5Providers.mqh:125` · **Category:** boundary

```mql5
      if(last_quote > 0 && last_quote <= lastbar_close)
         out.last_msc = lastbar_open - 1;      // the forming bar is not data yet
      else
         out.last_msc = lastbar_close;
```

**Failure scenario** (verifiers' corrected version — broader than the weekend case) [CONFIRMED FROM CODE] — The test fires for **any** `last_quote` at or before the final bar's close, which includes a stale quote predating the last bar entirely (a symbol whose M1 was downloaded from the server while it is not being quoted). Since the last M1 bar exists because a tick landed in it, a symbol that has stopped quoting **necessarily** satisfies `lastbar_open <= last_quote <= lastbar_close` — so the shortfall is deterministic, not runtime-contingent. Start a session on a Saturday: the Friday 23:59 bar is complete and can never receive another tick, yet `out.last_msc` becomes 23:58:59.999 and it is excluded. The host uses this directly as `win_end` (`SSReplayStandalone.mq5:1075`), so the replay stops one minute early, and `CSSRHistoryCatalog::LatestStart`/`CanStartAt` inherit the shortfall. The else branch is taken only when the quote feed is **ahead** of the M1 series.

**Why** [CONFIRMED FROM CODE] — The test asks "does the last quote fall inside the last bar?" as a proxy for "is that bar still forming", and the two differ precisely when quoting has stopped. Nothing checks `SymbolInfoSessionQuote`, `SYMBOL_TRADE_MODE`, or how far behind wall time the last quote is — any of which would separate the cases.

**Verifiers** — Deterministic, not probabilistic; consumer chain confirmed.

**Fix** [RECOMMENDATION] — Ask whether the bar can still change, not where the quote is: `bool forming = (last_quote > 0 && last_quote >= lastbar_open && (TimeCurrent() * 1000L) < lastbar_close);` — i.e. the bar is still forming only if wall-clock time has not passed its close. Keep the existing test as a secondary condition if desired, but the wall-clock comparison is what distinguishes "still filling" from "market shut". Cost is one M1 bar today, but every other class in the subsystem trusts this bound.

##### `data-3` — LOW — the random picker draws candidates with replacement

**File:** `SSR_RandomPicker.mqh:149` · **Category:** input-validation

```mql5
      int attempts = (m_pool_count < SSR_PICK_ATTEMPTS
                      ? m_pool_count : SSR_PICK_ATTEMPTS);
      for(int a = 0; a < attempts; a++)
        {
         string sym = m_pool[m_rng.Index(m_pool_count)];
```

**Failure scenario** (verifiers' corrected version) [CONFIRMED FROM CODE] — `InpRandom=true` with `InpAlsoSymbols="XAUUSD,US30"` on origin EURUSD gives a pool of 3 and `attempts=3`, drawn independently — so XAUUSD can be drawn all three times. If it lacks the depth while the other two have it, `Pick()` returns false with "no candidate had enough history: XAUUSD … XAUUSD … XAUUSD" and the host falls back to a non-random window. With one qualifying symbol in three the feature fails (2/3)³ ≈ 30 % of the time with the answer sitting in the pool. Reachable only with `InpRandom` plus a mixed-depth `InpAlsoSymbols`; the consequence is a logged degradation, not wrong data. Secondary: `AddSymbol` returns true for a duplicate without adding it (78-82), inflating `AddSymbolList`'s "added" count and the duplicate entries in `m_skipped`.

**Why** [CONFIRMED FROM CODE] — `m_rng.Index(m_pool_count)` samples uniformly over the whole pool every iteration; nothing removes or marks a rejected candidate, and both failure arms only append to `m_skipped` and continue. `attempts` is capped at `min(pool, 8)`, so for a pool of n the loop makes at most n draws from n with replacement and by construction cannot cover it. The bound's own comment (31-34) shows the intent was to try each candidate.

**Verifiers** — `Pick()` traced; probability arithmetic confirmed.

**Fix** [RECOMMENDATION] — Draw without replacement: shuffle an index array once (Fisher-Yates over `m_pool_count` using the same `m_rng`) and walk the first `attempts` entries. Identical randomness, guaranteed coverage of the pool when `attempts == m_pool_count`, and the error message stops repeating one name. Make `AddSymbol` return false for a duplicate while you are there, so the counts mean what they say.

#### C.6.4 MT5 bridge - `MQL5/Include/SSReplay/Mt5`

##### `mt5-symbol-8` — LOW — `Destroy()` reports OK when `CustomSymbolDelete` fails

**File:** `SSR_CustomSymbolManager.mqh:557` · **Category:** object-lifecycle

```mql5
bool ok = CustomSymbolDelete(m_symbol);
m_created = false;
...
//--- a symbol that was never there is not a failure
Succeed();
return ok;
```

**Failure scenario** (verifiers' corrected version) [CONFIRMED FROM CODE] — A chart remains open on the replay symbol (or the pause was not long enough for the terminal to release it). `CustomSymbolDelete` returns false, `m_created` goes false anyway, the `SSRPause(120)` is skipped, and `Succeed()` clears the error before the result is known — so `LastError()` reports OK and `IsCreated()` says the symbol is gone while it still sits in the terminal. Both callers (`Release()`, the destructor, and `Create()`'s pre-emptive `Destroy()`) ignore the bool, so nothing is logged; the extra-stream sinks have no host-side log for this at all, only the on-replay path prints at 2197. Accumulation is bounded in practice — the next `Create()`'s retry or adopt fallback reclaims the slot and the seed manifest is invalidated beforehand — so this is a **lost diagnostic**, not unbounded orphan growth.

**Why** [CONFIRMED FROM CODE] — `Succeed()` is unconditional at 584 although the comment justifies it only for the never-existed case, and the `GetLastError()` that `ResetLastError()` at 556 set up is never read.

**Verifiers** — Confirmed line by line; the header's "forty dead symbols" warning is the failure mode this masks.

**Fix** [RECOMMENDATION] — Report what happened: `if(!ok) { Fail(SSR_ERR_INTERNAL, "CustomSymbolDelete(" + m_symbol + ") refused: " + IntegerToString(GetLastError())); return false; } m_created = false; SSRPause(120); Succeed(); return true;` — keeping the "never existed" case on the success path by testing existence first. Then have `Release()` and the host log the false return, so the orphan is visible the moment it happens rather than at the fortieth one.

##### `mt5-symbol-7` — LOW — the seed-cache version guard compares a constant that never changes

**File:** `SSR_SeedCache.mqh:176` · **Category:** session-resume

```mql5
if(m.version != SSR_VERSION)
  { m_last_reason = "written by another version"; m_misses++; return false; }
```

**Failure scenario** (verifiers' corrected version) [CONFIRMED FROM CODE] — `SSR_VERSION` is `"0.1.0"` in every one of the 169 commits, while the stamp that actually changes (`SSR_BUILD`, v125) lives in `SSR_Build.mqh` and never enters the manifest — so the guard can never fire across builds and `CanReuse` accepts any earlier build's manifest once origin and range agree. The bite is on the adopt path: `Adopt()` re-applies the other symbol overrides but **not** `SYMBOL_CHART_MODE`, so a leftover pre-fix LAST-mode replay symbol is reused by v125 and then builds no candles from the engine's ticks.

**Why** [CONFIRMED FROM CODE] — `git log -S'#define SSR_VERSION'` returns only the initial commit `dc87fa3`; `SSRSeedManifest::Init` copies `SSR_VERSION` (43) and `Save` writes it (112).

**Verifiers** — Verified by grep and git; the chart-mode consequence is theirs.

**Fix** [RECOMMENDATION] — Two small changes. Put the build stamp in the manifest — `m.build = SSR_BUILD;` — and compare that instead, so the guard fires whenever the writer differs. And make `Adopt()` re-assert `SYMBOL_CHART_MODE_BID` with the same read-back check `Create()` performs, so a reused symbol cannot carry a pre-fix mode forward. The second is the one that prevents a silent no-candle session.

#### C.6.5 Chart layer - `MQL5/Include/SSReplay/Chart`

##### `chart-6` — LOW — bookmark lines are never deleted and survive on the user's own chart

**File:** `SSR_ChartManager.mqh:170` · **Category:** object-lifecycle

```mql5
      string base = "SSR_MARK_" + IntegerToString((int)when);
```

**Failure scenario** [CONFIRMED FROM CODE] — One-chart mode (default), the user presses `B` a few times during a session, then removes the EA. `CSSRChartManager` offers no `ClearMarks()`; `grep SSR_MARK_` finds exactly one hit in the tree — the creation site — and `ObjectsDeleteAll` is called only for `SSR_NEWS_` and the widget prefix. At teardown the host does not close this chart, it hands it back to the origin symbol (2194), and chart objects survive a symbol change and are saved with the chart. Dashed vertical lines at the bookmarked timestamps therefore stay on the user's live origin chart indefinitely, one set per session, removable only by hand — and because they are created with `OBJPROP_HIDDEN=true` (184) they do not even appear in the terminal's object list where a user would look for them.

**Why** [CONFIRMED FROM CODE] — No deletion path exists in this class or any caller; `OnDeinit` deletes the panel, the calendar lines and the trade lines, but nothing named `SSR_MARK_`. The only `ClearMarks()` in the tree is `CSSRSnapshotStore::ClearMarks`, which clears a counter.

**Verifiers** — Confirmed by grep and by the teardown path.

**Fix** [RECOMMENDATION] — Add the missing method and call it: `void ClearMarks() { for(int i = 0; i < m_count; i++) if(m_charts[i].id != 0) ObjectsDeleteAll(m_charts[i].id, "SSR_MARK_", -1, OBJ_VLINE); }`, invoked from `CloseOwned()` and from the host's `OnDeinit` beside `g_cal_lines.Clear()`. Also drop `OBJPROP_HIDDEN` to false so the user can find and delete any that predate the fix — hidden objects a tool leaves behind are worse than visible ones.

##### `chart-17` — LOW — `MarkTime` puts the registry index in the object name

**File:** `SSR_ChartManager.mqh:176` · **Category:** object-lifecycle

```mql5
         string n = base + "_" + IntegerToString(i);
         if(ObjectFind(id, n) < 0 && !ObjectCreate(id, n, OBJ_VLINE, 0, when, 0))
            continue;
```

**Failure scenario** (verifiers' corrected version) [CONFIRMED FROM CODE] — The name suffix comes from the registry loop index, which `Remove()` reassigns when a chart closes by copying entries down (102-105). Two charts marked at time t: chart A holds `SSR_MARK_t_0`, chart B `SSR_MARK_t_1`. Close chart A and B becomes index 0; re-mark t and the `ObjectFind` guard misses under the new index, creating a second `OBJ_VLINE` on a chart that already carries one. Both sit at the identical datetime with identical style, so they render exactly coincident and are **not visually distinguishable** — the cost is duplicate, undeletable chart objects and a name that is not a stable per-chart identity, not two visible lines. Combined with `chart-6`, they accumulate permanently.

**Why** [CONFIRMED FROM CODE] — The name is rebuilt from the live loop index on every call, and the index is not a chart identity.

**Verifiers** — Mechanism provable; the visible outcome is the part that needed narrowing.

**Fix** [RECOMMENDATION] — Key the name by something stable: `string n = base + "_" + IntegerToString((int)id);` — the chart id, which is exactly the per-chart identity the suffix was reaching for. Then `ObjectFind` is meaningful, re-marking is idempotent, and `chart-6`'s `ObjectsDeleteAll` by prefix still catches everything.

##### `chart-14` — LOW — `OpenLayout` counts each chart twice against the ceiling

**File:** `SSR_ChartManager.mqh:234` · **Category:** boundary

```mql5
         if(m_count + opened >= SSR_MAX_CHARTS)
            break;                        // the ceiling, honoured quietly
```

**Failure scenario** (verifiers' corrected version) [CONFIRMED FROM CODE] — `OpenChart()` ends with `Sync()` (213), whose discovery branch registers the chart just opened, so `m_count` already includes it and `opened` counts it again: the sum grows by 2 per chart and the effective ceiling is ~8 opens rather than 16. With `InpExtraTfs` listing many timeframes, charts the user asked for are silently not opened — the comment calls it "honoured quietly". The double count holds regardless of how synchronously `ChartOpen` publishes the chart: if the new chart is visible to its own `Sync`, `m_count = 1 + opened`; if it lags a pass, `m_count = opened`. Either way `m_count` grows in step with `opened`, so the finder's runtime hedge was unnecessary. `Add()` is the real ceiling, so nothing is corrupted.

**Why** [CONFIRMED FROM CODE] — `Sync`'s discovery branch (344-350) adds any chart carrying `m_symbol` and increments `m_count`; `OpenLayout`'s guard adds `opened` on top of that.

**Verifiers** — Confirmed and strengthened.

**Fix** [RECOMMENDATION] — Test one counter: `if(m_count >= SSR_MAX_CHARTS) break;` — `Sync()` has already made `m_count` authoritative by the time the guard is next evaluated. And make the refusal audible: `Print("[charts] ceiling reached at %d - not opening %s", m_count, EnumToString(tf));` so a user who asked for six timeframes and got four learns why.

##### `chart-10` — LOW — a detached chart has no user-visible state indicator

**File:** `SSR_ChartManager.mqh:464` · **Category:** event-handling

```mql5
            ChartSetInteger(m_charts[i].id, CHART_AUTOSCROLL, false);
            if(m_observer != NULL)
               m_observer.OnUserScrolled(m_charts[i].id);
```

**Failure scenario** (verifiers' corrected version) [CONFIRMED FROM CODE] — When a chart detaches, both reporting channels are dead: `SetObserver` has exactly one caller in the tree and it is a test (`SSR_T4_ChartIntegration.mq5`), so `m_observer` is NULL in the EA and every observer call is a no-op; and `charts_detached` is written once (`SSR_GroupPort.mqh:122`) and read nowhere — grep finds only the declaration, its `Init` and that assignment. The replay advances, the candles stop moving, and the interface shows no **state**. The key hint is not missing — the Session tab prints "F follow" via `SSR_S_KEYS_3` — so the defect is the absent detached-state readout, which matters chiefly if a detach ever happens without the user causing it. The deliberate `CHART_AUTOSCROLL=false` at 463 means the terminal will not recover on its own either.

**Why** [CONFIRMED FROM CODE] — Confirmed by absence of callers for both channels; the Follow button that would have carried the count was removed from both layouts.

**Verifiers** — Both channels verified dead; the key-hint claim corrected.

**Fix** [RECOMMENDATION] — Render the field that is already on the wire. In `DrawStatus` (or the Session sheet, which has the room), when `m_state.charts_detached > 0` draw "detached ×N - F follows" in `SSR_C_HOLD`. One `Text()` call against a field `GroupPort` already publishes, and it turns a silent freeze into a labelled state. The observer interface can stay unwired until something needs it.

##### `chart-7` — LOW — `LeakGuard::Advice` is longer than its only consumer can display

**File:** `SSR_LeakGuard.mqh:93` · **Category:** string-length

```mql5
      if(m_report.origin_charts > 0)
         return StringFormat("%s is open on %d chart(s) - close it or your backtest is not blind",
                             m_origin, m_report.origin_charts);
      return StringFormat("%s is in Market Watch - its live price is visible", m_origin);
```

**Failure scenario** (verifiers' corrected version) [CONFIRMED FROM CODE] — The chart variant is 69 characters and the Market-Watch variant 53, against 48 usable after the 13-character "Charts" prefix and `Clip`'s 62-character cap — so both are truncated with a trailing `~`: "Charts       EURUSD is open on 1 chart(s) - close it or your ~" and "Charts       EURUSD is in Market Watch - its live price is vi~". The cut falls after "close it or your", so the actionable verb survives and the rationale is lost — a cosmetically truncated sentence rather than an unreachable instruction. The class's stated contract ("a backtesting tool that says nothing while the user can see the real price is lying to them") degrades to a fragment, and there is no second channel: nothing renders `other_live_charts`, and `Leaks()`/`ToString()` only go to the log.

**Why** [CONFIRMED FROM CODE] — Arithmetic on the format strings plus the 62-character `Clip` at `SSR_Panel.mqh:242-248`. The panel's own comment (1888-1891) records that this line "has been ending '- close it or your' on the chart, mid-sentence" and clips it deliberately; clipping stopped the ragged cut, it did not make the sentence fit.

**Verifiers** — Both lengths re-measured (69 and 53, not 68 and 54).

**Fix** [RECOMMENDATION] — Author the message to the budget it has, here where the wording lives: `"%s open on %d chart(s) - close it"` (≤ 36) and `"%s in Market Watch - price visible"` (≤ 40). Both fit inside 48 with room for a long symbol name. Move them into `SSR_Strings.mqh` so they are translatable and so A19's length rule covers them — the Persian versions will be longer, and this is exactly the case that rule exists for.

##### `chart-12` — LOW — every word the Chart layer draws is a hardcoded English literal

**File:** `SSR_TradeLines.mqh:134` · **Category:** i18n

```mql5
      ObjectSetString (m_chart, n, OBJPROP_TEXT, tip);
```

**Failure scenario** (verifiers' corrected version) [CONFIRMED FROM CODE] — With `InpLanguage="fa"` and the Persian file complete at 190/190, the planning lines still print "STOP - drag me", "TARGET - drag me" and "ENTRY - drag me" (200, 243-244, 277-278, 298-299, 315) with `CHART_SHOW_OBJECT_DESCR` forced on at 183; position levels print "BUY"/"SELL"/"SL"/"TP" and "stop of BUY 0.20 at …" (411-438); closed trades print "#12 buy 0.21 in at …" (546-564); and the leak advice reaches the panel itself in English. A Persian user gets a translated panel with English labels on **the only objects they are asked to interact with**. A19 misses it for two reasons, not one: the `/Ui/` path filter (`ssr_audit.py:1458`), and more fundamentally that A19 inspects widget draw calls by argument position (1449) and never raw `ObjectSetString(OBJPROP_TEXT)` writes.

**Why** [CONFIRMED FROM CODE] — `SSR_Strings.mqh` has no entries for any of these, and this file includes only Common plus `Ui/SSR_Theme.mqh`, so `T()` is not even in scope. A19's vacuous-pass guard (≥ 100 resolved `T()` calls) is satisfied by the Ui files alone.

**Verifiers** — Every literal confirmed at the cited lines; the audit mechanism explanation extended.

**Fix** [RECOMMENDATION] — Bring the Chart layer inside the string system: include `Ui/SSR_Strings.mqh`, add `SSR_S_LINE_STOP`, `SSR_S_LINE_TARGET`, `SSR_S_LINE_ENTRY`, `SSR_S_SIDE_BUY`, `SSR_S_SIDE_SELL` and the two tooltip formats, and wrap each literal in `T()`. Then widen A19 on both axes: drop the `/Ui/` filter and add `ObjectSetString(..., OBJPROP_TEXT, <literal>)` to the patterns it scans — without the second change the rule will keep passing on files that draw text without a widget.

#### C.6.6 Trading and risk - `MQL5/Include/SSReplay/Trading`

##### `trading-analytics-6` — LOW — undefined profit factor prints as 0.00

**File:** `SSR_Journal.mqh:304` · **Category:** zero-empty

```mql5
FileWriteString(h, StringFormat("<div><span>Profit factor</span><b>%.2f</b></div>\r\n", st.profit_factor));
```

**Failure scenario** (verifiers' corrected version) [CONFIRMED FROM CODE] — Five winners and no loser: the headline KPI reads "Profit factor 0.00", the by-setup row reads 0.00, the CSV header writes `# profit_factor,0.0000`, and `Summary()`/`ToString` prints "PF 0.00" — the worst possible reading for the best possible session — while the "Every measure" table on the same page correctly says "undefined". The class report ingests the 0 but does **not** misprint it: it renders "-" when `profit_factor <= 0`. So four printers are wrong, not five.

**Why** [CONFIRMED FROM CODE] — `SSR_Statistics.mqh:527-530` deliberately leaves `profit_factor` at 0.0 when `gross_loss == 0` ("it stays 0 and the caller reads trades/losses to know why"); only `WriteAllMeasures` honours that contract, the other four format the raw double.

**Verifiers** — Provable; the class-report printer exonerated.

**Fix** [RECOMMENDATION] — Give the contract one implementation: add `string SSRFormatPF(const double pf) { return (pf > 0.0 ? DoubleToString(pf, 2) : "undefined"); }` next to the struct and call it from all four printers (the CSV can write an empty field, which the reader already treats as absent — the same convention the R column uses at `SSR_Journal.mqh:82`). Then "undefined" appears everywhere it is true, and the page stops contradicting itself.

##### `trading-analytics-8` — LOW — average MAE/MFE printed at two decimals in price units

**File:** `SSR_Journal.mqh:1142` · **Category:** boundary

```mql5
Measure(h, "Average MAE", DoubleToString(st.avg_mae, 2),
              "maximum adverse excursion: how far the average trade went the wrong "
              "way before it ended");
      Measure(h, "Average MFE", DoubleToString(st.avg_mfe, 2),
```

**Failure scenario** (verifiers' corrected version) [CONFIRMED FROM CODE] — A EURUSD session with an average MAE of 15 pips (−0.00150) prints "Average MAE −0.00" and "Average MFE 0.00"; and on any instrument the caption "Much larger than the average win means profit was given back" compares a **price distance** with a **money** figure. A third printer has the same truncation: `SSR_Review.mqh:142` formats `st.avg_mae` with `%.2f`.

**Why** [CONFIRMED FROM CODE] — `UpdateExcursions` records `move = price - open_price`, a price distance (`SSR_TradeTypes.mqh:209` documents the field as "worst adverse move, in price"); `ComputeFor` sums and averages them unchanged and no `MoneyFor`/`RiskOf` conversion touches them anywhere. The CSV prints the per-trade values at `%.5f` (87), so the two exports disagree in readability as well.

**Verifiers** — Provable end to end; third printer theirs.

**Fix** [RECOMMENDATION] — Convert once, at the point of display. Both statistics already have the lot size and the engine has `MoneyFor(price_move, volume)`: add `avg_mae_money`/`avg_mfe_money` to `SSRStatistics`, filled in `ComputeFor` with the same conversion the money columns use, and print those in the two HTML measures and the review card — keeping the price-unit value in the CSV where five decimals make it readable. Then the caption's comparison with the average win is apples to apples.

##### `trading-analytics-5` — LOW — a day with only a (even cancelled) pending order counts as a trading day

**File:** `SSR_PropEvaluation.mqh:383` · **Category:** prop-rules

```mql5
int pos = Positions();
      if(pos > m_last_positions)
        {
         m_last_positions = pos;
         m_day_traded     = true;
        }
```

**Failure scenario** (verifiers' corrected version) [CONFIRMED FROM CODE] — With `min_trading_days=3`, placing a buy-limit far from price on each of three days and cancelling it satisfies the minimum with **zero fills**, so a target hit on day 1 passes on day 3 with no trade. Conversely a pending placed on day 1 and filled on day 2 credits day 1, contradicting the comment "a trade was OPENED that day". Reachability nuance: the count is re-read only inside `OnClock`, so an order placed and cancelled while the replay is PAUSED is attributed to whatever day is open at the next pump.

**Why** [CONFIRMED FROM CODE] — `Positions()` returns `m_acct.Total()` = `m_count`, and `Open()` does `int i = m_count++;` **before** the pending branch, which returns with state `SSR_POS_PENDING` and no fill; cancellation only sets `SSR_POS_CANCELLED` and never decrements `m_count`. The evaluation compares the count alone and never inspects state.

**Verifiers** — Provable; the paused-placement nuance is theirs.

**Fix** [RECOMMENDATION] — Count fills, not slots. Expose `int FillCount()` on the engine (a counter incremented in the two places a position reaches `SSR_POS_OPEN` — `Open()`'s market branch and `CheckPendings`' fill) and have `OnClock` compare that instead. It is also the honest basis for `m_last_positions`, which currently drifts for the same reason.

##### `trading-analytics-9` — LOW — the equity ring drops its oldest half, losing the peak

**File:** `SSR_Statistics.mqh:272` · **Category:** drawdown-calc

```mql5
if(m_eq_count >= SSR_EQUITY_SAMPLES)
        {
         int keep = SSR_EQUITY_SAMPLES / 2;
         for(int i = 0; i < keep; i++)
           {
            m_eq_msc[i] = m_eq_msc[i + keep];
```

**Failure scenario** (verifiers' corrected version) [CONFIRMED FROM CODE] — Reachable only when the replay span exceeds 4096 sampled minutes (the default 2000 M1 bars does not). With a peak at minute 100 and a trough at minute 3000, the drop keeps samples [2048..4095], so the **trough survives and the peak is discarded**: the statement's SVG and its drawdown number stay mutually consistent, but both silently lose the earlier peak and the reported max drawdown **shrinks as the session runs on**.

**Why** [CONFIRMED FROM CODE] — `EquityDrawdown` (347-364) seeds `peak = m_eq_val[0]` of whatever survived, and there is no persisted running maximum — `out.max_drawdown` is recomputed from the live ring on every `ComputeFor` (596). `SaveInto`/`RestoreFrom` cap at 4096 too. The comment admits the halving, but the half it discards is the one that can hold the peak.

**Verifiers** — `Sample()` traced; the peak/trough roles corrected.

**Fix** [RECOMMENDATION] — Keep the extremum, not just the samples. Add `double m_dd_peak_seen, m_dd_max_seen;` updated on every `Sample()` and never reset by the ring drop, and have `EquityDrawdown` return `MathMax(live_ring_dd, m_dd_max_seen)`. The curve can then be decimated as aggressively as you like without the headline number moving backwards. Cheaper alternative if the SVG must stay faithful: decimate by keeping every second sample across the whole span rather than dropping the oldest half — same memory, no lost history, half the resolution.

##### `trading-analytics-10` — LOW — R multiple excludes commission while every money measure includes it

**File:** `SSR_Statistics.mqh:455` · **Category:** r-multiple

```mql5
if(p.HasR())
           {
            out.total_r += p.RMultiple();
            out.r_trades++;
           }
```

**Failure scenario** (verifiers' corrected version) [CONFIRMED FROM CODE] — Commission 5/lot, 1 lot, risk 50, trade closes +3 before fees: net = 3 − 10 = −7 (counted in losses and gross_loss) while R = +0.06 (positive). Over a scalping session `average_r` can be positive while expectancy in money is negative, and the statement prints both side by side as if they measured the same trades. The same defect reaches `SSRBucket` (221-225), so the per-weekday and per-hour `AverageR()` rows carry commission-free R beside a net column that does not.

**Why** [CONFIRMED FROM CODE] — `RMultiple()` is `(profit + swap)/risk_at_entry` (`SSR_TradeTypes.mqh:269-270`) with no commission term, while `ComputeFor`'s net (431), `Bucket()` (252) and `ClosedDrawdownFor` (706) all subtract it. The file's own header defines R as the result over the risk taken, and commission is part of the result per 415-430. It is charged twice per round trip.

**Verifiers** — Both halves verified; bucket extension theirs.

**Fix** [RECOMMENDATION] — Make the numerator the same money everywhere: `double RMultiple() const { return (risk_at_entry > 0.0 ? (profit + swap - commission) / risk_at_entry : 0.0); }`. One line in `SSR_TradeTypes.mqh`, and every consumer — statement, buckets, CSV, class report — inherits it. Note in the statement's R caption that R is net of costs, since a trader comparing with a broker platform will want to know which convention is in use.

##### `trading-analytics-7` — LOW — revenge detection compares with the previously *opened* trade

**File:** `SSR_Statistics.mqh:497` · **Category:** behaviour analytics

```mql5
if(prev_was_loss && prev_close != SSR_INVALID_TIME &&
            p.open_msc >= prev_close &&
            (p.open_msc - prev_close) <= SSR_REVENGE_WINDOW_MSC)
            out.revenge_trades++;
```

**Failure scenario** (verifiers' corrected version) [CONFIRMED FROM CODE] — A opens 10:00 and is stopped out at 10:30 (loss); B opens 10:01 and closes 10:02 for a win; C opens 10:31. C is a textbook revenge entry one minute after A's loss, but `prev` for C is B in slot order, `prev_was_loss` is false, and `revenge_trades` stays 0 — while the statement text (1196-1198) promises "opened within two replay minutes of the previous trade closing at a loss", which C satisfies. It also drifts for pending orders, whose slot is allocated at placement rather than at fill, so "previous in slot order" can differ from "previously opened" even with strictly non-overlapping trades.

**Why** [CONFIRMED FROM CODE] — `prev_close`/`prev_was_loss` are overwritten unconditionally at the tail of every closed-trade iteration (511-512), so "previous" means previous in creation order; `At(i)` is a slot read with no sort anywhere. The QA smoke only asserts `revenge_trades >= 1` in a sequential scenario.

**Verifiers** — Scenario replayed through the loop by hand.

**Fix** [RECOMMENDATION] — Track the most recent losing **close** rather than the previous slot: keep `long last_loss_close = SSR_INVALID_TIME;` updated to `MathMax(last_loss_close, p.close_msc)` whenever a closed trade's net is negative, and test `p.open_msc - last_loss_close <= SSR_REVENGE_WINDOW_MSC` against that. Because the walk is in slot order, a correct implementation needs two passes (collect losing closes, then test opens) — which is also what `trading-analytics-3` needs, so sort once by close time and do both in one pass.

##### `trading-exec-10` — LOW — a long entry inside the spread is classified `BUY_STOP`

**File:** `SSR_TradeTypes.mqh:120` · **Category:** input-validation

```mql5
bool is_long = (stop < entry);
if(is_long)
   out = (entry < bid ? SSR_ORDER_BUY_LIMIT : SSR_ORDER_BUY_STOP);
else
   out = (entry > bid ? SSR_ORDER_SELL_LIMIT : SSR_ORDER_SELL_STOP);
```

**Failure scenario** (verifiers' corrected version) [CONFIRMED FROM CODE] — For longs both the limit/stop decision and the "entry is on the price" guard use **bid**, while `CheckPendings` triggers `BUY_STOP` on **ask** — so any long entry in `(bid + min_dist, ask]`, a window up to 18 points wide at `min_dist` 2 and a 20-point spread, is accepted as a pending and fills at `ask + slippage` on the very next tick. The user placed a "pending" that behaves as a market order at a worse price than the line they drew, which is what the refusal text at 113-118 says it prevents. Because the size came from the entry line but the fill is at ask, the position also carries slightly more money at risk than the requested percent — though `risk_at_entry` is recomputed from the fill, so the reporting stays honest. The short side is unaffected.

**Why** [CONFIRMED FROM CODE] — The long pending's trigger in `CheckPendings` (337) is `m_ask >= request_price`; the only caller passes `min_dist = pt * 2.0` (`SSR_GroupPort.mqh:1010`), and neither `Open` nor `OpenPendingWithRisk` imposes any minimum distance from the market.

**Verifiers** — Traced end to end; the window's width is theirs.

**Fix** [RECOMMENDATION] — Measure each side against the price that triggers it: for a long, compare `entry` with `ask` (and for a short, with `bid`, which it already does). `out = (entry < ask ? SSR_ORDER_BUY_LIMIT : SSR_ORDER_BUY_STOP);` plus the on-the-price guard against `ask` closes the window entirely, and the classification then matches the trigger by construction.

##### `trading-exec-9` — LOW — limit entries receive adverse slippage

**File:** `SSR_TradingEngine.mqh:345` · **Category:** slippage

```mql5
bool is_long = m_pos[i].IsLong();
m_pos[i].type       = (is_long ? SSR_ORDER_BUY : SSR_ORDER_SELL);
m_pos[i].open_price = FillPrice(is_long, true);
```

**Failure scenario** (verifiers' corrected version) [CONFIRMED FROM CODE] — With `InpSlippage=10` (default 0), a `BUY_LIMIT` at 1.10000 triggered by an ask of 1.10000 fills at 1.10010 — **above** its limit price. A limit fills at its price or better by definition, and the file's own comment at 486-490 makes exactly that argument for take-profit and fills TP at its level (544); entry limits are treated inconsistently and are penalised by the slippage input on every fill. `risk_at_entry` is **not** affected (recomputed from the real open price at 350-353); the residual inaccuracy is the lot size, sized off the request price in `OpenPendingWithRisk` (797).

**Why** [CONFIRMED FROM CODE] — `FillPrice` (120-126) adds `slippage_points` unconditionally on the opening side and `CheckPendings` uses it for all four pending types, including the two whose triggers are `m_ask <= request_price` / `m_bid >= request_price`.

**Verifiers** — Confirmed; scope narrowed to `InpSlippage > 0`.

**Fix** [RECOMMENDATION] — Apply slippage only where it is adverse *and* possible. In the fill branch, clamp to the limit for the two limit types: `double px = FillPrice(is_long, true); if(m_pos[i].type_was_limit) px = (is_long ? MathMin(px, m_pos[i].request_price) : MathMax(px, m_pos[i].request_price));` — the same "at its price or better" rule the TP path already implements. Stops keep their slippage, which is the realistic model for them.

##### `trading-exec-12` — LOW — `Open()` accepts any positive volume from the external path

**File:** `SSR_TradingEngine.mqh:714` · **Category:** input-validation

```mql5
if(volume <= 0.0)
  { m_last_error = "volume must be positive"; return 0; }
```

**Failure scenario** (verifiers' corrected version) [CONFIRMED FROM CODE] — With `InpAllowTrade=true` (default false) an external client sends BUY with volume 0.003 or 7.777 (`SSR_Publisher.mqh:301/307` passes the wire value straight in; `CSSRStrategy::Send` likewise passes a strategy's volume unrounded). The position is booked at that size, the journal, statistics, R and margin all carry a size no venue would accept, and `GroupPort.ClosePartial` later refuses it as "too small to split". All panel paths are already rounded by `LotForRisk`, and the account arithmetic stays self-consistent at any positive volume, so the effect is presentational fidelity rather than incorrect money.

**Why** [CONFIRMED FROM CODE] — `Open()` validates only `volume > 0` and never consults the lot step, min or max, although the engine owns them: `CSSRRiskEngine` reads `SYMBOL_VOLUME_MIN/MAX/STEP` (49-56), exposes `VolMin`/`VolMax` (73-74) and has a step-rounding helper (29-31) used by `LotForRisk` only.

**Verifiers** — Both raw callers confirmed real and unguarded.

**Fix** [RECOMMENDATION] — Validate at the boundary the engine already owns: after the positive check, `double v = m_risk.RoundLots(volume); if(v <= 0.0 || v < m_risk.VolMin() || v > m_risk.VolMax()) { m_last_error = "invalid volume"; return 0; } volume = v;`. Panel paths are unaffected (they already pass rounded values), the Publisher and strategies get the terminal's behaviour, and `ClosePartial` stops meeting sizes it cannot split.

##### `trading-exec-11` — LOW — `AmbiguousPercent` divides open-position fills by the closed count

**File:** `SSR_TradingEngine.mqh:999` · **Category:** zero-empty

```mql5
double            AmbiguousPercent(void)
  {
   int closed = ClosedCount();
   return (closed > 0 ? 100.0 * (double)m_ambiguous_count / (double)closed : 0.0);
  }
```

**Failure scenario** (verifiers' corrected version) [CONFIRMED FROM CODE] — One trade closed unambiguously plus one pending filled on a synthetic tick in a minute that also reaches its stop (still open) gives `m_ambiguous_count = 1`, `ClosedCount = 1`, and the honesty figure reports **100 %** of results resting on assumed tick order when the only closed result was not assumed; two such open fills report 200 %, and ambiguous fills with zero closes report 0 %. The blast radius is limited: it affects only `ToString()`'s log line and the `SSR_GV_AMBIGUOUS` global export (`SSR_Publisher.mqh:206`). The statement, CSV and HTML honesty figure is computed independently in `SSR_Statistics.mqh` over closed trades only and is correct.

**Why** [CONFIRMED FROM CODE] — `m_ambiguous_count` is incremented both for still-OPEN positions at fill time (381-382) and for closes (236-240), while the denominator counts only `state == SSR_POS_CLOSED` (988-994).

**Verifiers** — Populations confirmed different; user-facing reports exonerated.

**Fix** [RECOMMENDATION] — Count two things separately: keep `m_ambiguous_closed` (incremented in `BookExit`) and `m_ambiguous_fills` (incremented in `CheckPendings`), and have `AmbiguousPercent` use the first over `ClosedCount()`. Export the fill count as its own global if external clients want it; conflating the two is what made the figure exceed 100 %.

#### C.6.7 UI layer - `MQL5/Include/SSReplay/Ui`

##### `ui-dialogs-14` — LOW — `Show()` reports success without checking the card fits

**File:** `SSR_FirstRun.mqh:89` · **Category:** boundary

```mql5
      int x = 14, y = SSR_PANEL_H + 40, w = 396, h = 104;
      m_w.Rect("bg", x, y, w, h, SSR_C_PANEL, SSR_C_PANEL_EDGE);
```

**Failure scenario** (verifiers' corrected version) [CONFIRMED FROM CODE] — The card occupies y 376..480 (`SSR_PANEL_H` = 336 + 40). `Show()` reads no chart dimension, its only false path is `chart_id == 0`, and it returns true unconditionally — and the host writes the once-ever `seen.txt` on that return (1742-1743). So on a short chart the product's single piece of onboarding is spent unread, recoverable only by knowing to delete `MQL5/Files/SSReplay/seen.txt`. Two narrowings: the card is fully off-screen only below ~376 px — the 356..376 band the host's own height warning (fires below 356) misses — and between 376 and 480 px it is merely clipped; and it is reached only in two-window mode, because the host guards the block with `InpFirstCard && !one_chart_ok` (1736), so with the default `InpOneChart=true` neither the card nor the marker write ever happens (`host-expert-4`).

**Why** [CONFIRMED FROM CODE] — Arithmetic on `SSR_PANEL_H` plus an unconditional `return true`.

**Verifiers** — Both scope corrections theirs; they are what keep this at LOW.

**Fix** [RECOMMENDATION] — Let `Show()` answer honestly: `long ch = ChartGetInteger(chart_id, CHART_HEIGHT_IN_PIXELS); if(ch < y + h + 8) return false;` before drawing. The host's existing `if(g_first.Show(...)) MarkSeen();` then keeps the card for a session where it fits, with no change at the call site — which is exactly why the return value was plumbed through in the first place.

##### `ui-port-session-12` — LOW — the session list fully parses every file on every render

**File:** `SSR_GroupPort.mqh:937` · **Category:** cpu

```mql5
      if(!m_sessions.Peek(m_names[i], summary))
```

**Failure scenario** (verifiers' corrected version) [CONFIRMED FROM CODE] — `Peek` constructs a local `CSSRSessionFile` and calls `Load()`, which reads the file line by line to EOF, growing three arrays for every entry — every `pos`, `leg` and `e` row — before reading its five keys out of `[session]`. The dialog calls it once per visible row (`SSR_SD_ROWS = 8`) on every `Render()`, which runs on `Open()` and on every up, down, row and load click. With 8 visible sessions of 400 trades each that is roughly 8 × 9,000 parsed entries **per click**, on a modal drawn over the replay chart while the pump timer is still firing. Bounded by `SSR_SF_MAX_ENTRIES` = 16384 and `SSR_SF_MAX_SECTIONS` = 1024, so the worst case is ~8 × 16k entries per click rather than unbounded.

**Why** [CONFIRMED FROM CODE] — No cache and no header-only read mode anywhere on the path.

**Verifiers** — Trace confirms; the cap is theirs.

**Fix** [RECOMMENDATION] — Two independent improvements, either sufficient. Add a header-only mode to `CSSRSessionFile::Load(path, bool header_only)` that stops at the first section after `[session]` — the five keys `Peek` wants are all in the first block, so the read becomes a few dozen lines. And cache in the port: `string m_peek_name[8]; string m_peek_text[8];` invalidated when the name list changes, so a repaint with no selection change costs nothing. The header-only mode is the one that also speeds up `List()`.

##### `ui-port-session-10` — LOW — a save made from the panel records settings that are not the session's

**File:** `SSR_GroupPort.mqh:949` · **Category:** session-resume

```mql5
      SSRSessionSettings set;
      set.Init();
      set.slot = (m_sink != NULL ? m_sink.Slot() : 1);
      if(!m_sessions.Save(name, set))
```

**Failure scenario** [CONFIRMED FROM CODE] — Every session saved from the Session dialog writes **default** settings into `[settings]`: the file claims the session was not random, not blind, ran 8 ticks per bar with zero spread on M5 — whatever it actually was. The host's own save path uses the real values (`CollectSettings`, 2137-2139), so two saves of the same running session disagree depending on which button produced them, under a comment (182-183) claiming the seed is written "so a session that was random can be recognised as such months later" — which a panel-made save cannot do. The port's own comment at 947-950 states the limitation outright ("the panel knows none of the settings; the host owns them"), so this is a knowingly accepted gap whose only defect is that the written file is **indistinguishable from a truthful one**. Nothing in the product calls `ReadSettings` yet, so the wrong values are stored and never read.

**Why** [CONFIRMED FROM CODE] — `Init()` fixes seed 0, blind 0, pause_flags 0, session_mode 0, slot 1, ticks_per_bar 8, spread 0.0, chart_tf M5, and `Save` writes all eight verbatim.

**Verifiers** — Verified on both sides.

**Fix** [RECOMMENDATION] — Let the host supply what only the host knows: give `CSSRGroupPort` a `SetSettingsSource(SSRSessionSettings &s)` (or a small function-pointer/callback the host registers once at init pointing at `CollectSettings`), and have `SaveSession` use it. Until that exists, the honest interim is to write a `settings_known=0` flag alongside so a reader can tell a defaulted block from a real one — a file that lies silently is worse than one that admits ignorance.

##### `ui-plumbing-1` — LOW — the key card is the one user-facing screen never translated

**File:** `SSR_KeyCard.mqh:92` · **Category:** i18n

```mql5
         m_w.Label(id + "a", x + 12, ry, b[i].label, SSR_C_HOLD, SSR_FS_SMALL);
         m_w.Label(id + "b", x + 86, ry, b[i].what, SSR_C_TEXT, SSR_FS_SMALL);
```

**Failure scenario** (verifiers' corrected version) [CONFIRMED FROM CODE] — With `InpLanguage="fa"` the card's title, close hint and footer come through `T()` and draw in Persian while all 36 body cells (18 listed rows × label + what) draw in English, because `SSRKeyBindings()` stores raw English literals in `.label`/`.what` with no catalogue ids. A Persian user pressing `H` — the key `SSR_S_FIRSTRUN_3` tells them to press to learn the product — gets an English list under a translated title. Effect is confined to help text: the key labels themselves are language-neutral and every shortcut still works. A19 cannot see it, because the drawing argument is a variable (`ssr_audit.py:1450-1470` matches literals appearing directly as a draw call's text argument).

**Why** [CONFIRMED FROM CODE] — The catalogue holds only `keycard.title`, `keycard.close` and `all-virtual` for this card; no `ENUM_SSR_STR` id exists for any body row.

**Verifiers** — Verified directly; 18 rows counted.

**Fix** [RECOMMENDATION] — Put the id in the binding, not the English: add `ENUM_SSR_STR label_id; ENUM_SSR_STR what_id;` to `SSRKeyBinding`, fill them in `SSRAddKey`, and draw `T(b[i].what_id)` with the existing literal kept as the fallback `T()` already returns when a key is missing. That is 18 catalogue entries plus two struct fields, and it makes the card translatable without touching the card's layout. Then widen A19 to follow `.what`/`.label` assignments, or at minimum add a rule that every `SSRAddKey` call must pass a non-zero `what_id`.

##### `ui-plumbing-15` — LOW — Ctrl+K is not in the single key table

**File:** `SSR_Keys.mqh:71` · **Category:** key-table

```mql5
#define SSR_VK_K        75
```

**Failure scenario** (verifiers' corrected version) [CONFIRMED FROM CODE] — `SSR_Panel.mqh:2828-2832` opens the command palette on Ctrl+K, checked before the key-table dispatch so nothing can shadow it, and the registry is fully wired (`RunChosen` at 2423 dispatches both `cmd` and `action` entries; `move` still runs `SnapToCorner` at 2605, making the palette the only surviving way to move the panel). But `SSR_VK_K` is never added in `SSRKeyBindings()`, so `SSRKeyToCommand(75)` returns `SSR_CMD_NONE` and the `H` key card — generated from that table, and the product's only key list — never mentions it. Meanwhile `SSR_Panel.mqh:929` records "K the command palette had no key and is now unreachable", and the technical overview repeats it: **a reachable feature is documented as removed**. One nuance: `SSR_VK_A` and `SSR_VK_P` sit under the same "not commands: the two ways out of a text box" comment yet *are* in the table, so that comment is simply stale for three defines rather than an assertion about K.

**Why** [CONFIRMED FROM CODE] — `SSRKeyBindings` (125-222) never references `SSR_VK_K`; its single use is the live Ctrl+K branch.

**Verifiers** — Every link verified.

**Fix** [RECOMMENDATION] — Add the row, with a modifier field the table currently lacks: extend `SSRKeyBinding` with `bool ctrl;` (default false), add `SSRAddKey(out, i, SSR_VK_K, "Ctrl+K", SSR_CMD_PALETTE, "the command palette", true)` with `ctrl=true`, and have `SSRKeyToCommand` ignore ctrl-flagged rows (the panel's explicit branch keeps handling the dispatch) while the key card prints them. Then delete the stale comment at `SSR_Panel.mqh:929` and fix the overview. One table, one truth — which is what the table is for.

##### `ui-plumbing-3` — LOW — `SSRKeyHint()` is a third hand-written key list, also naming R as reset

**File:** `SSR_Keys.mqh:271` · **Category:** key-table

```mql5
string SSRKeyHint(void)
  {
   return "SPACE play  <- -> step  PgUp/PgDn x10  J jump  B mark  "
          "S sessions  +/- speed  F follow  D fidelity  R reset";
  }
```

**Failure scenario** (verifiers' corrected version — the drift is wider than one list) [CONFIRMED FROM CODE] — On start-up the host prints this line into the Experts log (1694), where R is `SSR_CMD_LINES_TOGGLE`, and it omits every key added since: Tab (take the trade), X (flip), L, 0 (reset), A (review), P (panel size), H (the key card) — so a user following the log's advice cannot find reset at all. And `SSR_S_KEYS_2` (`SSR_Strings.mqh:500-501`, "+ - speed    R reset    J jump    B bookmark"), drawn **on the panel** via `T(SSR_S_KEYS_2)` at `SSR_Panel.mqh:1900-1902`, also still says "R reset". Two user-facing hand-written lists contradict the generated table, while only the `H` key card is built from it. The only test on the hint asserts `StringFind(SSRKeyHint(), "S sessions") >= 0` — a substring that is still correct — so the suite blesses the drift.

**Why** [CONFIRMED FROM CODE] — The literal sits 70 lines below the table it contradicts, under the very comment ("RESET MOVED OFF R") that it ignores.

**Verifiers** — Confirmed; the `SSR_S_KEYS_2` sibling is theirs.

**Fix** [RECOMMENDATION] — Generate both. Replace `SSRKeyHint()`'s body with a loop over `SSRKeyBindings()` that concatenates `label + " " + what` for the first N `listed` rows up to a length budget, and replace the `SSR_S_KEYS_2`/`_3` panel hints with the same generated text clipped to the sheet width. Then the test that matters is "the hint contains the reset key's label", which `SSRKeyToCommand(SSR_VK_0)` can supply — an assertion that cannot go stale.

##### `ui-panel-12` — LOW — the key card is rebuilt from scratch ten times a second

**File:** `SSR_Panel.mqh:776` · **Category:** cpu

```mql5
      if(m_keys.IsUp())
         m_keys.Show(m_chart);
```

**Failure scenario** (verifiers' corrected arithmetic) [CONFIRMED FROM CODE] — Press `H` and the panel calls `Show()` on every repaint, i.e. every 100 ms, on the same `OnTimer` as the 40 ms engine pump. `Show()` begins with `m_w.RemoveAll()` (`ObjectsDeleteAll` over the `SSRK_` prefix) and rebuilds the binding array and every object, so nothing can be cached between frames **by construction**. The real per-frame cost is 1 `OBJ_RECTANGLE_LABEL` + 39 `OBJ_LABEL`s = 40 objects: one `ObjectsDeleteAll`, ~40 `ObjectCreate`, and 9 + 39×6 = **243 property writes** — not the ~450 the finder estimated, but still against a project measurement of 561 writes ≈ 39 ms.

**Why** [CONFIRMED FROM CODE] — `SSRKeyBindings` does `ArrayResize(out,0)` and rebuilds the whole table per call; `RemoveAll` is `ObjectsDeleteAll` + `ForgetAll`. The comment at 767-775 explains why the redraw is needed for z-order — the redraw is right, the destructive implementation is the cost.

**Verifiers** — Cadence and object count both re-derived (18 listed bindings of 22).

**Fix** [RECOMMENDATION] — Make `Show()` idempotent: drop the `RemoveAll()` and let the widget primitives' create-if-absent plus the `Same()` cache handle a repeat call, so a still frame costs ~40 `ObjectFind`s and zero writes. Keep a `RemoveAll()` in `Hide()` where teardown belongs. If the z-order refresh genuinely needs recreation, gate it: recreate only when `m_last_z_frame != panel_frame_counter`, which the panel can bump when it creates anything new.

##### `ui-panel-13` — LOW — the caption chip row overruns the collapse button by 6 px

**File:** `SSR_Panel.mqh:887` · **Category:** boundary

```mql5
      int cx = x + 140;
      bool degraded = (m_state.fidelity_effective != m_state.fidelity);
      cx += m_w.Chip("chfid", cx, y + 4,
                     SSRFidelityShort(m_state.fidelity_effective) +
                     (degraded ? " !" : ""),
```

**Failure scenario** (verifiers' corrected version) [CONFIRMED FROM CODE] — With blind on, prop on, and the fidelity degraded, the row lays out `chfid "SYNTH !"` at x+140..x+192, `chblind "BLIND"` x+196..x+236, `chprop "PROP"` x+240..x+274, while the collapse button starts at `x + W - 42 = x+268` — so the last 6 px of the PROP plate and the tail of its text sit under the collapse button, which on a mode indicator reads as a rendering fault. Without the degradation marker the row ends at x+262, clearing by 6 px: no margin. **English-specific**: in Persian, blind is 3 chars (28 px) and prop 4 chars (34 px), giving 262 < 268; and it needs the 5-character "SYNTH" — a degraded "BAR !" or "FULL !" also clears.

**Why** [CONFIRMED FROM CODE] — `Chip` returns `w = 10 + StringLen(text) * 6` and each caller adds 4. The chips' plates are `Rect`s so `CheckFrame` sees them, but they end **inside** the 310 px frame and the instrument reports overflow past the frame, not collisions inside it.

**Verifiers** — Every input verified; the chips also overlap the button vertically (y+4..y+17 against y+3..y+18).

**Fix** [RECOMMENDATION] — Give the row a budget and drop chips that do not fit, highest-priority last: compute `int limit = x + W - 46;` and before each `Chip` test `if(cx + 10 + StringLen(t)*6 > limit) break;`. Fidelity and blind are the two a trainee must see, so order them first and let PROP fall out — it is also rendered on its own tab. A single `break` guard is proof against every future translation, which the arithmetic above is not.

##### `ui-panel-8` — LOW — the speed "meaning" text at MAX is 21 unclipped characters in a 56 px reserve

**File:** `SSR_Panel.mqh:1091` · **Category:** string-length

```mql5
      Text(6, "spdmean", x + W - SSR_PAD - mw + 4, y + 5,
           SSRSpeedMeaning(m_state.speed_x100), SSR_C_TEXT_DIM, SSR_FS_SMALL);
```

**Failure scenario** (verifiers' corrected version) [CONFIRMED FROM CODE] — Press `+` to `SSR_SPEED_MAX` (a real rung of the 20-stop ladder, also reachable by clicking the last groove cell) and `SSRSpeedMeaning` returns the 21-character "as fast as ticks feed", drawn unclipped from x+254 with 56 px to the panel edge — it runs onto the candles for as long as MAX is selected. The exact overflow is a font-metric estimate; that 21 glyphs cannot fit 56 px at 7 pt is not. And MAX is not the only long rung: the lowest (0.1×) yields "1h in 10.0h" at 11 characters, already borderline in 56 px.

**Why** [CONFIRMED FROM CODE] — `mw = 52` in the rail branch (1053), so the anchor is x+254. No `Clip()` is applied here, unlike `prog` (960), `pp_rules` (1760), `pp_head` (1840) and `ses3` (1892), and being a label it is invisible to `CheckFrame`. The fallback layout reserves 92 px, still short of 21 characters.

**Verifiers** — Ladder rung confirmed reachable two ways; the 0.1× case is theirs.

**Fix** [RECOMMENDATION] — Two lines. Shorten the string at its source: `SSRSpeedMeaning` returns "max" (or "ticks as fed") for the top rung — the slider position already says the speed, and the meaning column exists to translate a multiplier into replay time, which "as fast as ticks feed" does not do anyway. And wrap the draw in `Clip(..., 9)` like its four neighbours, so the next long value is truncated rather than painted on the price.

##### `ui-panel-4` — LOW — `HideSheetArea`'s id list stops at `tab3`

**File:** `SSR_Panel.mqh:2044` · **Category:** object-lifecycle

```mql5
      string ids[] = {"tab0","tab1","tab2","tab3","tabline",
                      "lines","sessions","fidelity"};
      for(int i = 0; i < ArraySize(ids); i++)
         m_w.Hide(ids[i], hidden);
```

**Failure scenario** (verifiers' corrected version) [CONFIRMED FROM CODE] — With `InpProp=true` the rail draws five tabs (`TabCount()` returns `SSR_TAB_MAX` = 5), and `tab4` — the Prop/PASSED/FAILED button — is not in this list, so compact mode leaves it on the chart. Currently latent and unobservable, because `HideBody(false)` at 729 re-shows all five tabs every frame anyway (`ui-panel-3`): in the shipping build `HideSheetArea` is a no-op for every id it names, so `tab4` is not stranded any more specifically than `tab0..tab3`. It becomes a live bug the moment `ui-panel-3` is fixed. It is the exact bug `HideBody` already had and fixed, documented at 2088-2090: "SSR_TAB_MAX, not four written out. This list said tab0..tab3 and Phase 8 added a fifth tab, so closing the panel left a lone 'Prop' button sitting on the candles."

**Why** [CONFIRMED FROM CODE] — The list was not updated with its sibling.

**Verifiers** — Omission real; no independently observable effect today.

**Fix** [RECOMMENDATION] — Copy `HideBody`'s loop: drop `tab0..tab3` from the array and add `for(int t = 0; t < SSR_TAB_MAX; t++) m_w.Hide("tab" + IntegerToString(t), hidden);`. Fix it in the same commit as `ui-panel-3`, or the fix for that one strands this tab.

##### `ui-panel-14` — LOW — the reset confirmation is a hardcoded English literal

**File:** `SSR_Panel.mqh:2253` · **Category:** i18n

```mql5
      m_reset_warning  = StringFormat(
                            "Reset deletes %d closed and %d open - press again",
                            m_state.closed_trades, m_state.open_positions);
```

**Failure scenario** (verifiers' corrected version) [CONFIRMED FROM CODE] — A Persian-language user who presses Reset or `0` with trades on the books gets the highest-priority line of the status strip — the line that decides whether they destroy their session — in English, inside an otherwise fully translated panel (`fa.txt` has 190/190 entries and does carry `reset` and `reset.ask`, but no key for this sentence). It is **not** the only such string: the fill toast is built the same way (791-800 assembles `m_toast_text` from `StringFormat("   spread %.1f pt", …)` and appends "   NO STOP", drawn at 803-806) and is equally invisible to A19 for the same reason.

**Why** [CONFIRMED FROM CODE] — A19 only inspects literals appearing in the text argument at the draw call (`ssr_audit.py:1449-1482`); here the literal is assigned to a member at 2253 and drawn from that member at 1929.

**Verifiers** — Confirmed at source; the toast sibling is theirs.

**Fix** [RECOMMENDATION] — Add `SSR_S_RESET_WARN` ("Reset deletes %d closed and %d open - press again") and `SSR_S_TOAST_SPREAD`/`SSR_S_TOAST_NOSTOP` to the catalogue and build both strings with `StringFormat(T(...), …)`. Then close the audit hole that let them through: extend A19 to follow assignments into members that are later drawn — or, much cheaper and nearly as effective, flag any `StringFormat` whose format string is a literal containing a lowercase word inside `SSR_Panel.mqh`, `SSR_SetupPanel.mqh` and the dialogs. A rule that catches these two would have caught both.

##### `ui-dialogs-11` — LOW — the session dialog's DELETE button deletes nothing

**File:** `SSR_SessionDialog.mqh:288` · **Category:** event-handling

```mql5
      if(what == "del")
        {
         m_message = "deleting is done from the session folder - this "
                     "dialog does not remove files";
         Render();
         return true;
        }
```

**Failure scenario** (verifiers' corrected version) [CONFIRMED FROM CODE] — The DELETE button is drawn enabled whenever a session is selected (210-211, `enabled = m_selected >= 0`, and `Open()` sets the selection to 0 whenever `m_count > 0`), is fully reachable from the host (3089-3092 opens the dialog, 3167-3169 routes clicks), and its handler performs no deletion — only a message line. `CSSRSessionManager::Delete` exists at 403 and is never reached; `CSSRReplayPort` exposes no delete method at all. The explanatory message is 76 characters, so MetaTrader's 63-char limit cuts it to "deleting is done from the session folder - this dialog does not", losing the operative clause. The comment above the handler argues about **confirmation** for a deletion that does not happen.

**Why** [CONFIRMED FROM CODE] — The control is enabled and labelled for a destructive action the code does not implement, and the half-sentence that explains why is itself truncated.

**Verifiers** — Fully reachable and fully inert; length re-measured.

**Fix** [RECOMMENDATION] — Either implement it or disable it, and the first is nearly as cheap: add `bool DeleteSession(const string name)` to `CSSRReplayPort`/`CSSRGroupPort` forwarding to `m_sessions.Delete(name)`, and make the handler a two-press confirm reusing the panel's existing "press again" pattern (`m_pending_del = name;` then delete on the second press), with the message "press DELETE again to remove \"name\"" (≤ 63 with any reasonable name). If deletion is deliberately out of scope, create the button with `enabled=false` and label it `T(SSR_S_SD_DELETE)` + " (folder)" — a disabled control tells the truth; an enabled one that does nothing does not.

##### `ui-dialogs-12` — LOW — `RequestSave` and the overwrite-confirm mode are unreachable

**File:** `SSR_SessionDialog.mqh:318` · **Category:** session-resume

```mql5
      bool ok = m_port.SaveSession(name);
      m_message = (ok ? "saved \"" + name + "\""
                      : "could not save: " + m_port.SessionError());
      m_pending = "";
      Open();
```

**Failure scenario** (verifiers' corrected version) [CONFIRMED FROM CODE] — `grep RequestSave` returns exactly one hit — its definition at 304 — and `m_mode` is set to `SSR_SD_CONFIRM_SAVE` only inside it, so the entire overwrite-confirm mode is unreachable and the header's promise "IT ASKS BEFORE IT OVERWRITES" (12-13) is not a shipped behaviour. If a caller were wired up, the outcome would be invisible: `Open()` on the next line sets `m_message = (m_count == 0 ? "no saved sessions yet" : "")`, destroying both "saved …" and "could not save: …" before `Render()` draws them; and the early `return` at 153 means the CONFIRM render never hides the list rows while the PICK render never removes `q1/q2/yes/no`, so the two screens would be drawn over each other. Every runtime consequence is therefore unobservable today — the live defect is documentary. The host's `OnDeinit` write of `CfgSession()` is the intended resume autosave, not a silent overwrite defect.

**Why** [CONFIRMED FROM CODE] — One definition, no callers; `Open()` clears the message it was just given.

**Verifiers** — Every limb checked; classified IMPROVEMENT in substance, kept at LOW by `final_severity`.

**Fix** [RECOMMENDATION] — Decide and act. Either wire it (add a SAVE button to the dialog that calls `RequestSave(name)`, move the `m_message` assignment **after** `Open()`, and have the CONFIRM branch call `HideAll()` before drawing) or delete `RequestSave`, `SSR_SD_CONFIRM_SAVE`, the `yes`/`no` handlers and the header sentence. Dead code that promises a safety property is worse than no code, because a reader trusts the header.

##### `ui-dialogs-13` — LOW — `SetStartText` draws at the START step's coordinates from another step

**File:** `SSR_SetupPanel.mqh:548` · **Category:** object-lifecycle

```mql5
   void              SetStartText(const string t)
     {
      if(t == m_start_text)
         return;
      m_start_text = t;
      if(m_open && m_start_y > 0)
         m_w.Label("startlbl", m_x + 12, m_start_y, t, SSR_C_HOLD, SSR_FS_SMALL);
```

**Failure scenario** (verifiers' corrected version) [CONFIRMED FROM CODE] — Reach step 3 once (so `m_start_y` is set), press Back to step 2, then drag the orange line: the host calls `SetStartText` on the next 200 ms beat, `m_start_y` is still the step-3 position, and an amber "Start: 2024.03.05 14:00" label appears **below** the MODE step's 288 px frame, floating on the candles, until the next button press repaints. On step 1 the 482 px frame means it lands inside the panel instead and overprints an evaluation-row label. `m_start_y` is never invalidated on a step change.

**Why** [CONFIRMED FROM CODE] — `m_start_y` is written only in `RenderStart` (933) and never cleared by `Repaint` or the step handlers; `SetStartText`'s only guards are `m_open` and `m_start_y > 0`. The host calls it on every beat while picking, regardless of step (2489-2491). Only `Repaint()`'s `RemoveAll` clears the stray, and the overflow instrument cannot see it because `Label` never calls `Extent()` and the setup panel never calls `CheckFrame` at all.

**Verifiers** — Geometry checked for both steps.

**Fix** [RECOMMENDATION] — Invalidate it where the step changes: `m_start_y = 0;` at the top of `Repaint()` (which every step change already goes through) and let `RenderStart` re-establish it. `SetStartText`'s existing `m_start_y > 0` guard then does exactly what it was written to do, with no new condition.

##### `ui-dialogs-15` — LOW — `MenuClear` sweeps 32 items while `presets.ini` is unbounded

**File:** `SSR_SetupPanel.mqh:611` · **Category:** object-lifecycle

```mql5
   void              MenuClear(void)
     {
      m_w.Remove("mbg");
      for(int i = 0; i < 32; i++)
         m_w.Remove("m" + IntegerToString(i));
     }
```

**Failure scenario** (verifiers' corrected version) [CONFIRMED FROM CODE] — `presets.ini` is user-editable with no row limit, so a desk listing 40 firms gives 41 options; opening the Preset list creates `m0..m40` and `MenuClear` deletes only `m0..m31`, leaving `m32..m40` on the chart as stale, latched-looking buttons that persist across paints until a step change (`Repaint`/`RemoveAll`) or `Destroy`. They are **inert** rather than still applying presets, because `Poll` only checks menu items within the currently open field's option range. The list is also drawn 820 px tall with no paging, and `DrawMenu`'s only off-screen defence is a single flip-upwards test, which cannot help a list taller than the chart.

**Why** [CONFIRMED FROM CODE] — `LoadPresets` applies no cap (`rows = f.Count("p")`; the session file caps only at 16384 entries), `PresetNames` returns all of them, `DrawMenu` creates one button per option, and `Render()` calls `MenuClear`, not `RemoveAll` (668).

**Verifiers** — Count mismatch real; the "still applying a preset" consequence corrected.

**Fix** [RECOMMENDATION] — Sweep what you created: keep `int m_menu_items;` set by `DrawMenu` and have `MenuClear` loop to that count (with a `MathMax` against the previous value so a shrinking list is fully cleared). And cap the list so it fits a chart: `int cap = MathMin(rows, 12);` with a "more in presets.ini" footer row — no paging machinery, and the 820 px overflow disappears with it.

##### `ui-dialogs-10` — LOW — the quick step builds the session path by hand and skips the sanitiser

**File:** `SSR_SetupPanel.mqh:712` · **Category:** input-validation

```mql5
      bool have_last    = FileIsExist(SSR_SETUP_FILE);
      bool have_session = (m_v.session_name != "" &&
                           FileIsExist("SSReplay\\sessions\\" +
                                       m_v.session_name + ".ssr"));
```

**Failure scenario** [CONFIRMED FROM CODE] — Name a session "eu/us open" or "NY:2024-03-05". `CSSRSessionManager` stores it as `sessions\eu_us open.ssr` (it replaces `\`, `/` and `:` with `_`), but the quick step tests for `sessions\eu/us open.ssr`, which cannot exist — so the "Continue …" button is never offered and the user concludes the session was not saved. The same unsanitised name is what the panel writes to `setup.ini` and hands to the host.

**Why** [CONFIRMED FROM CODE] — `CSSRSessionManager::Path` (92-99) sanitises before building the path and both `Save` (167) and `Exists` (117) go through it; this is the only place in the subsystem that concatenates a session path by hand, and `Str("ses", …)` applies no character validation or length limit.

**Verifiers** — Both sides verified.

**Fix** [RECOMMENDATION] — Do not build the path here. Expose the sanitiser — make `CSSRSessionManager::Path(const string name)` a `static` (it uses no instance state) or add `static string SSRSessionPath(const string name)` beside it — and call `FileIsExist(SSRSessionPath(m_v.session_name))`. Then also filter at the keyboard: in `ReadAll`, replace `\ / : * ? " < > |` with `_` in `session_name` before storing it, so what the user sees in the recap matches the file that will be written.

##### `ui-dialogs-6` — LOW — the setup panel's drag handler is unreachable

**File:** `SSR_SetupPanel.mqh:955` · **Category:** event-handling

```mql5
   bool              OnChartEvent(const int id, const long lparam,
                                  const double dparam, const string sparam)
     {
      if(!m_open || id != CHARTEVENT_MOUSE_MOVE)
         return false;
```

**Failure scenario** (verifiers' corrected version) [CONFIRMED FROM CODE] — Dead code rather than a malfunction. The setup window opens centred over the candles the user must now drag the orange start line onto, and it cannot be moved: MQL5 delivers `CHARTEVENT_MOUSE_MOVE` only to programs on a chart whose `CHART_EVENT_MOUSE_MOVE` property is on, and nothing switches it on while this panel exists. So every branch of `OnChartEvent` is unreachable, `SavePlace()` is never called, `SSR_SETUP_X/Y` never exist, `m_placed` is always false, and the panel re-centres on every run — the "DRAG IT BY ITS CAPTION" behaviour described at 946-953 does not exist on a real terminal. The picking workflow still works, because the vertical pick line is grabbable outside the panel's footprint. Secondary: the drag exit writes `CHART_MOUSE_SCROLL = true` unconditionally (970) instead of restoring what the chart had, unlike `SSR_Panel.mqh:371`.

**Why** [CONFIRMED FROM CODE] — The only writer of that property in the tree is `CSSRPanel::Create` (324), restored by `Destroy` (370); the setup panel's lifetime (2069 → 2522) does not overlap `g_panel.Create()` (1467). Same root cause as `host-expert-14`, seen from the widget side.

**Verifiers** — Unreachability provable by grep; lifetimes confirmed disjoint.

**Fix** [RECOMMENDATION] — As in `host-expert-14`: save and set `CHART_EVENT_MOUSE_MOVE` in `CSSRSetupPanel::Create`, restore it in `Destroy`, and while you are in there save and restore `CHART_MOUSE_SCROLL` instead of forcing it true. The class already has `SavePlace`/`m_placed` waiting on the other side.

##### `ui-dialogs-9` — LOW — `ReadAll` clamps four numbers but not the three prop numbers

**File:** `SSR_SetupPanel.mqh:1194` · **Category:** prop-rules

```mql5
      if(m_v.balance      <= 0.0)   m_v.balance      = 10000.0;
      if(m_v.risk_percent <= 0.0)   m_v.risk_percent = 0.5;
      if(m_v.risk_percent >  100.0) m_v.risk_percent = 100.0;
      if(m_v.spread_points < 0.0)   m_v.spread_points = 0.0;
      if(m_v.speed        <= 0.0)   m_v.speed        = 1.0;
      if(m_v.speed        > 10000.0)m_v.speed        = 10000.0;
```

**Failure scenario** (verifiers' corrected version) [CONFIRMED FROM CODE] — A 0 or negative typed into a prop box passes through untouched and the corresponding rule, gated on `> 0.0`, is dropped: clear "Max daily loss" and the evaluation runs with no daily limit while the panel still shows prop chips and meters; type 0 into "Profit target %" and the challenge can never be passed (`TargetProgress` returns 0 forever) — an unpassable challenge that the panel's own `presets.ini` loader explicitly rejects (`nm == "" || (on != 0 && tg <= 0.0) -> continue`, 342). So the file is validated and the keyboard is not. Narrowing: the numbers are not hidden (the step-3 recap prints them, as does the host's `prop.ToString()` log), and 0 meaning "no limit" matches the `max_days` convention — so the defect is the missing keyboard-side validation, not a silent deletion.

**Why** [CONFIRMED FROM CODE] — `ReadAll` assigns the three from `Num()` (1176-1178) and the clamp block never mentions them; `Num()` returns 0.0 for a typed "0" because its unreadable-guard only rejects a zero whose first character is not '0'. The host copies them into the rules with no validation.

**Verifiers** — Asymmetry provable; the `presets.ini` precedent is the argument for the fix.

**Fix** [RECOMMENDATION] — Apply the loader's own rule at the keyboard: in the clamp block, `if(m_v.prop_daily < 0.0) m_v.prop_daily = 0.0; if(m_v.prop_total < 0.0) m_v.prop_total = 0.0; if(m_v.prop_on && m_v.prop_target <= 0.0) m_v.prop_target = 8.0;` (the default the presets use). Then say so on the recap row when a rule is off — "no daily limit" rather than a blank — so a deliberate 0 reads as a choice and an accidental one is visible.

##### `ui-plumbing-14` — LOW — H, B and X are printed as row captions while being global hotkeys

**File:** `SSR_Strings.mqh:393` · **Category:** key-table

```mql5
   SSRAddString(out, n, SSR_S_ROW_HINT,        "row.hint",
                "H halves   B stop to entry   X closes");
```

**Failure scenario** (verifiers' corrected version) [CONFIRMED FROM CODE] — Open the Positions tab with a filled position: `SSR_Panel.mqh:1620-1629` draws "H halves   B stop to entry   X closes" under the rows and 1607-1613 creates the three per-row buttons captioned "H", "B", "X" — with nothing on the line saying these are click targets. A user who reads it as a key legend and presses the keys gets `SSR_CMD_KEYS` (the key card covers the panel), `SSR_CMD_BOOKMARK`, and `SSR_CMD_LINES_FLIP`, which flips the **planning** stop/target lines long↔short — it changes the pending setup rather than any open position or order, so the finder's "changes trade state" is an overstatement. Three unrelated actions, none touching the position. The convention is what makes it a trap: every other key letter the panel prints (F, L, B, J, S, D, X in the various hint strings) **is** the global hotkey for the control it is printed on, which is precisely what teaches the user that a letter on this panel means a key.

**Why** [CONFIRMED FROM CODE] — `SSR_Keys.mqh` binds H→KEYS (216-218), B→BOOKMARK (179-181), X→LINES_FLIP (168-170); keys do reach these commands from anywhere on the panel.

**Verifiers** — All three legs verified; the X consequence narrowed.

**Fix** [RECOMMENDATION] — Say they are buttons and stop reusing letters. Change the string to `T(SSR_S_ROW_HINT)` = "click  ½ half   ≡ stop to entry   ✕ close" and caption the per-row buttons with the same three glyphs instead of letters — glyphs cannot be mistaken for hotkeys, they are language-neutral (which also fixes a translation cost), and they fit the same 12 px cells. If glyph rendering in `OBJ_BUTTON` is a risk on some terminals, use "1/2", "BE", "X" with the prefix word "click" — the prefix alone removes the ambiguity.

##### `ui-plumbing-2` — LOW — the panel's on-screen hint says "R reset"

**File:** `SSR_Strings.mqh:500` · **Category:** key-table

```mql5
   SSRAddString(out, n, SSR_S_KEYS_2, "keys.2",
                "+ - speed    R reset    J jump    B bookmark");
```

**Failure scenario** (verifiers' corrected version) [CONFIRMED FROM CODE] — Open the Session tab: `SSR_Panel.mqh:1899-1901` draws this as the `keyhint` label, telling the user R is reset. R is bound to `SSR_CMD_LINES_TOGGLE` and reset to `0`, so pressing R puts the stop and target lines on the chart, and the real reset key is named **nowhere** on the panel — these four `SSR_S_KEYS_*` lines are the panel's only keyboard guide. The error is faithfully translated: `fa.txt` carries `keys.2 = + - سرعت    R شروع دوباره …` ("R start over"), so it is wrong in both languages. The wrong hint fails safe (R draws lines, it does not reset) and the authoritative `H` card is still correct because it is generated from the table; the defect is the hand-written hint contradicting it.

**Why** [CONFIRMED FROM CODE] — `SSR_Keys.mqh`'s own header (79-88) states the reason the table exists — "Two lists drift - always, and silently, and the one that drifts is the one the user is reading" — and `SSR_KeyCard.mqh`'s header names this exact case: "R moved from reset to the stop-and-target lines in this very build; a second list would already be wrong."

**Verifiers** — Straight contradiction between two lists, both read.

**Fix** [RECOMMENDATION] — Generate the hint lines from the table, as proposed in `ui-plumbing-3`, and delete `keys.1`-`keys.4` from the catalogue (and from `fa.txt`) so there is nothing left to drift. If a hand-written line must stay for layout reasons, add an audit rule: any catalogue string whose value matches `\b[A-Z0-9]\s+\w+` must name a key/command pair that `SSRKeyToCommand` agrees with — mechanical, and it would have caught all four copies.

##### `ui-plumbing-6` — LOW — the property cache has no tombstones

**File:** `SSR_Widgets.mqh:103` · **Category:** memory

```mql5
   void              Forget(const string name)
     {
      int k = Slot(name);
      if(k >= 0 && m_ck[k] == name)
        { m_ck[k] = ""; m_cn[k] = 0; m_ct[k] = ""; }
     }
```

**Failure scenario** (verifiers' corrected version — two of the finder's claims are wrong, one new hazard found) [CONFIRMED FROM CODE] — `Slot()` stops at the first slot that is either free **or** matching, so after a `Remove()` frees an earlier slot in a probe chain, `Forget()` for a name stored later in that chain resolves to the free slot, finds `m_ck[k] != name`, and clears **nothing**; `Keep()` then stores a duplicate at the earlier slot and the off-home entry is orphaned for the life of the cache. Corrections: (1) the leak is **self-limiting**, not one slot per `Hide` at 10 Hz — once the orphan exists it occupies its slot and removes the free-slot precondition for that chain, so steady state is a small constant number of orphans per colliding chain and the "cache switches off" end-state is not established by this code. (2) Contrary to the finder's own evidence, the shadowed duplicate is **not always harmless**: if another name later occupies the earlier slot, `Slot()` resolves the name onto the orphan tuple and `Same()` compares the request against a state the object no longer holds — a matching comparison then skips the write and leaves the wrong colour or text. That path is neutralised for every `Remove()`-invalidated name (the object is gone, so `Same()`'s `ObjectFind` check fails) and is live only for `Hide()`-invalidated names, which are never deleted.

**Why** [CONFIRMED FROM CODE] — `Slot()` (58-77) first-free-or-matching; `Forget()` guards on an exact key match; `Keep()` (91-99) writes wherever `Slot()` points; only `ForgetAll()` (from `Attach`/`RemoveAll`) reclaims anything. Home-slot collisions are certain at this load: hashing the panel's ~264 `SSRP_` names into 512 slots with the file's own FNV-1a yields 53 colliding home slots.

**Verifiers** — Mechanism exactly as coded; both corrections and the new hazard theirs.

**Fix** [RECOMMENDATION] — Give the table a tombstone. Reserve a sentinel key (`m_ck[k] == "\x01"`) written by `Forget` instead of `""`; `Slot()` treats a tombstone as occupied-but-reusable — it keeps probing for an exact match and remembers the first tombstone as the insert position, so a later `Keep` reuses it rather than shadowing. That is the textbook open-addressing fix, about eight lines, and it closes the orphan, the wrong-colour path and the unbounded-probe worry together. Cheaper interim if that is too invasive: make `Forget` scan the whole probe chain (up to the 8-slot bound) for an exact match rather than trusting `Slot()`.

#### C.6.8 Session - `MQL5/Include/SSReplay/Session`

##### `ui-port-session-11` — LOW — `List()` strips the extension by first match

**File:** `SSR_SessionManager.mqh:142` · **Category:** boundary

```mql5
         int    dot  = StringFind(name, SSR_SESSION_EXT);
         if(dot > 0)
            name = StringSubstr(name, 0, dot);
```

**Failure scenario** (verifiers' corrected version) [CONFIRMED FROM CODE] — `StringFind` returns the **first** occurrence, so `monday.ssr.ssr` — the file produced when a user types "monday.ssr" into the name box — is listed as "monday": the dialog shows "monday", `SessionSummary` calls `Peek("monday")` which fails with "cannot read …\monday.ssr", and pressing Load calls `Restore("monday")`, which fails or silently loads a genuinely different session called "monday". A file named exactly `.ssr` survives the `dot > 0` guard and is listed as ".ssr", whose `Path()` is `…\.ssr.ssr`. Narrowing: the dialog's "del" button deletes nothing (`ui-dialogs-11`), so only `Peek` and `Restore` mis-address the file.

**Why** [CONFIRMED FROM CODE] — Nothing sanitises the name on the way in: `Path()` strips only `\ / :`, `SaveSession` rejects only `""`, and `Str()` only trims.

**Verifiers** — Confirmed; deletion path exonerated because it is inert.

**Fix** [RECOMMENDATION] — Trim from the end: `int ext = StringLen(SSR_SESSION_EXT); if(StringLen(name) > ext && StringSubstr(name, StringLen(name) - ext) == SSR_SESSION_EXT) name = StringSubstr(name, 0, StringLen(name) - ext);`. Pair it with the keyboard-side filter proposed in `ui-dialogs-10` so a name cannot contain the extension in the first place.

##### `ui-port-session-7` — LOW — `Peek`'s summary is roughly twice what its consumer can draw

**File:** `SSR_SessionManager.mqh:238` · **Category:** string-length

```mql5
      summary = StringFormat("%s  |  %s  |  at %s (%.0f%% of %s..%s)  |  saved %s",
                             name, syms, SSRFormatMsc(now), pct,
                             SSRFormatMsc(start), SSRFormatMsc(end), when);
```

**Failure scenario** (verifiers' corrected version) [CONFIRMED FROM CODE] — The summary is ~112 fixed characters before the name and symbols (three 19-character timestamps plus a 19-character saved-at plus 34 of literals), and its only consumer draws it as one button caption with no truncation, so MetaTrader shows 63: `friday  |  US30.U26  |  at 2026.08.24 19:06:00 (48% of 2026`. What is **always** cut is the window start/end and the saved-at timestamp; the name, the symbols, the instant reached and the percentage do fit — so the loss is smaller than "never sees what distinguishes two files", which is why this is LOW. The unreadable-file fallback (`name + " (unreadable: …)"`) is cut the same way.

**Why** [CONFIRMED FROM CODE] — `SSRFormatMsc` is `TIME_DATE|TIME_MINUTES|TIME_SECONDS` (19 chars) and `written` is `TIME_DATE|TIME_SECONDS` (19); `CSSRWidgets` has no wrapping or ellipsis anywhere. A19 cannot see it because the string is assembled at runtime.

**Verifiers** — Arithmetic re-derived.

**Fix** [RECOMMENDATION] — Budget the row to 63 and put the rest on a second line the dialog already has room for. Line 1: `"%s | %s | %d%%"` (name, symbols, percent) ≈ 30. Line 2 (a second `Button`/`Label` per row, or a `Label` under the selected row only): `"at %s  saved %s"` with `SSRFormatMsc` reduced to `TIME_DATE|TIME_MINUTES` (16 chars) = ~40. Drawing the detail only for the selected row keeps the object count where it is and makes the two facts that distinguish similar files readable.

#### C.6.9 Strategy - `MQL5/Include/SSReplay/Strategy`

##### `strategy-integration-report-3` — LOW — `OnTick` fires once per batch, not once per tick

**File:** `SSR_IStrategy.mqh:266` · **Category:** tick-ordering

```mql5
   //--- every tick, for strategies that manage intrabar. Whatever this
   //--- does on synthetic ticks rests on an invented order of prices,
   //--- and ctx.IsSynthetic() is how it can know.
   virtual void      OnTick(void) {}
```

**Failure scenario** (verifiers' corrected version) [CONFIRMED FROM CODE] — Whenever a published batch carries more than one tick — MAX or very high speed, catch-up after a stall, or a candle step — `CSSRMarketView` retains only the last tick's bid/ask, so the parameterless `OnTick` cannot see the intrabar excursion in that batch, and `TickCalls()` counts **batches** while its name and `ToString()` ("ticks=%I64d") present it as a tick count. At ordinary speeds each batch holds one tick, so the per-tick hook does fire per synthetic tick and the intrabar prices are visible — the finder's "exactly one OnTick per M1 bar at the default" is wrong.

**Why** [CONFIRMED FROM CODE] — The hook takes no parameters, so the only tick data reachable is `CSSRMarketView`'s `m_bid`/`m_ask`, set from `ticks[count-1]` alone (191-198); `CSSRStrategyHost::OnTicks` calls `OnTick()` once per invocation and increments `m_tick_calls` once.

**Verifiers** — Mechanism real, frequency corrected.

**Fix** [RECOMMENDATION] — Pass the tick: change the hook to `virtual void OnTick(const MqlTick &t) {}` (the host has the array) and call it per tick inside the loop that `strategy-integration-report-2` also needs, setting the view's bid/ask to that tick first. Increment `m_tick_calls` per tick so the counter matches its name. Existing strategies need only a signature change; none reads the parameter today.

##### `strategy-integration-report-13` — LOW — `Group()` returns a half-built shift-0 group unrefused

**File:** `SSR_MarketView.mqh:136` · **Category:** boundary

```mql5
      if(seen == shift && open_set)
        {
         if(shift == 0)
            return true;                // forming, and known to be so
         m_refusals++;
         return false;
        }
```

**Failure scenario** (verifiers' corrected version — narrower trigger, more wrong fields) [CONFIRMED FROM CODE] — Line 136 is reached only when the backward walk never leaves group 0, i.e. **every** bar in the buffer belongs to the requested shift-0 group: early in a session, or just after a rewind that trimmed almost everything. (Not via `MakeRoom`, which keeps 2048 M1 bars ≈ 34 hours and therefore always spans several H4 groups, so the early return at 104 fires first.) In that state `out.open` was last overwritten from `m_m1[0]` — the oldest bar the buffer happens to hold — the `shift==0` branch returns true, and neither `m_refusals++` nor the refusal the `shift>0` case gets is applied. And `high`/`low` are **not** right either: they are folded only over the minutes present, so the group's true extreme can be in the missing part. Only `close` is certainly correct. `out.spread` being the newest minute's value is arguably the intended reading of a forming bar's spread. Every other partial group in the class is refused outright for exactly this reason (132-135), and `Available()` counts such a group, so a strategy checking availability first is not protected.

**Why** [CONFIRMED FROM CODE] — `out.open` is overwritten on every backward step inside the group (125), so termination by buffer exhaustion leaves the wrong open.

**Verifiers** — Trigger narrowed, field list widened.

**Fix** [RECOMMENDATION] — Refuse what you cannot build. Track whether the walk ended at the buffer's edge (`bool ran_out = (i < 0);`) and in the `shift == 0` branch return true only when `!ran_out`; otherwise `m_refusals++; return false;` — the same treatment `shift > 0` gets, and consistent with the class's stated policy. If a forming group must still be returned, add `out.partial = true` and have `Available()` exclude it, so a strategy can tell "still growing" from "beginning missing".

##### `strategy-integration-report-6` — LOW — `Prime()`/`OnRewind()` trim on bar-open granularity

**File:** `SSR_MarketView.mqh:398` · **Category:** future-data

```mql5
         //--- strictly at or before the clock. Never past it.
         if(SSRToMsc(bars[i].time) > now_msc)
            break;
```

**Failure scenario** (verifiers' corrected version) [CONFIRMED FROM CODE] — The test is on the bar's **open** time, so when `now_msc` falls inside a minute the whole M1 bar for that minute is admitted — high, low and close included: up to 60 seconds of prices the replay has not reached, in a method whose header claims it "TRIMS to" `now_msc`. After a jump that bar is shift 0 on M1 and part of the shift-0 group on any higher timeframe, so `Extremes(tf,0,n)` and `Bar(tf,0)` return future-contaminated extremes. `OnRewind` has the identical property. Contamination is confined to the newest M1 bar, hence to shift 0, and the shipped `CSSRRefBreakout` reads shift 1 and above and is therefore not exposed. In the bar-driven fidelities the next pump republishes that minute clipped and `OnBarContext`'s time-match branch overwrites it in place before the next strategy hook, so the exposure is really confined to FULL_TICK — where no `OnBarContext` ever arrives to correct it (`strategy-integration-report-1`) and the contaminated bar stays newest for the rest of the session.

**Why** [CONFIRMED FROM CODE] — The supply side does not pre-clip either: `CSSRMt5BarProvider::ReadBars` delegates to `CSSRBarWindow::Read`, which admits every bar with open ≤ `to_msc` verbatim. `MqlRates` carries no intrabar detail, so the minute cannot be clipped here as `ClipBar` does on the live path.

**Verifiers** — Both tests confirmed on open granularity; the FULL_TICK confinement is theirs.

**Fix** [RECOMMENDATION] — Drop the bar the clock is inside rather than admitting it whole: `if(SSRToMsc(bars[i].time) + 60000 - 1 > now_msc) break;` — i.e. keep only bars that have closed at or before the clock. The strategy then sees one fewer minute of context and zero future prices, which is the correct trade for a tool whose whole premise is that the future is not visible. Where a forming bar is genuinely wanted, feed it through `OnBarContext` with the clipped copy the controller already builds, which is what `strategy-integration-report-1`'s fix supplies.

##### `strategy-integration-report-5` — LOW — `IsSynthetic()` can never return false

**File:** `SSR_MarketView.mqh:427` · **Category:** honesty instrument

```mql5
   bool              IsSynthetic(void) { return m_synthetic; }
```

**Failure scenario** (verifiers' corrected version) [CONFIRMED FROM CODE] — `m_synthetic` is initialised true and can only ever be assigned true, so `ctx.IsSynthetic()` is a constant: `CSSRRefBreakout::Status()` always appends "  [intrabar order assumed]", including on a FULL_TICK session replaying the broker's real ticks, and any strategy branching on it takes the pessimistic branch unconditionally. The fault direction is safe — it never claims real ticks it does not have — but the documented distinction (419-426) is not being reported. One narrow exception the finder missed, which does not rescue the code: if fidelity were **locked** with FULL_TICK requested and the source had no tick provider, `Decide` returns FULL_TICK unchanged, execution falls through to the bar-driven path, and `PublishBar` would pass `synthetic=false` over synthesised ticks — a lie in the **unsafe** direction. Unreachable in production: `LockFidelity` (679) has no caller anywhere.

**Why** [CONFIRMED FROM CODE] — The only assignment's only caller is `PublishBar` at 506 with `fid != SSR_FIDELITY_FULL_TICK`, and 506 is reachable only after the FULL_TICK branch returned or was demoted — so the argument is always true. `OnSessionStart` does not reset it either.

**Verifiers** — Constant confirmed; the locked-fidelity hole is theirs.

**Fix** [RECOMMENDATION] — Report the fidelity, not a derived boolean. Have the controller pass the effective fidelity into the view (`OnBarContext(bar, fid)` or a separate `SetFidelity(fid)` on publish) and implement `IsSynthetic()` as `m_fid != SSR_FIDELITY_FULL_TICK`. Then also publish ticks through a call that sets it on the FULL_TICK path, so a real-tick session reports honestly — and the locked-fidelity lie becomes impossible because the value is derived from what actually ran.

##### `strategy-integration-report-4` — LOW — the per-strategy RNG stream is never re-seeded or rewound

**File:** `SSR_StrategyHost.mqh:141` · **Category:** session-resume

```mql5
      m_ctx[k].rng.Seed(m_seed ^ NameHash(s.Name()));
```

**Failure scenario** (verifiers' corrected version) [CONFIRMED FROM CODE] — `SSR_IStrategy.mqh:20-24` states the host provides the randomness specifically so "the same session replays to the same trades", but the stream is mutated by every draw and never restored: a step back, a bookmark jump or a snapshot restore replays the same minutes with the stream already advanced, so a strategy that draws from it takes different decisions the second time. Two overstatements corrected: the strategy is not wholly powerless — `rng` is a public member of the context (`SSR_IStrategy.mqh:202`), so it can re-seed deterministically from replay state in its own `OnRewind`; what it cannot obtain is the host's `m_seed`, so it cannot restore the host-derived stream. And no shipped strategy draws from `ctx.rng`, so this is a latent gap in the facility rather than a live reproducibility failure.

**Why** [CONFIRMED FROM CODE] — Line 141 is the only `Seed()` call in the host and runs inside `Add()`; `OnSessionStart` (160-169) resets `m_last_bar` and re-attaches brokers, `OnRewind` (214-222) resets `m_last_bar` and forwards the hook — neither touches the stream. `m_seed` is private with no accessor.

**Verifiers** — Code property exactly as described; both narrowings theirs.

**Fix** [RECOMMENDATION] — Re-derive the stream from the replay instant, so it is a function of position rather than of history: in `OnRewind(msc)` and `OnSessionStart`, `m_ctx[i].rng.Seed(m_seed ^ NameHash(name) ^ (ulong)msc);`. A step back to the same instant then reproduces the same draws, which is the reproducibility the header promises, and it needs no snapshot plumbing. Expose `ulong Seed() const` on the context as well, so a strategy that wants its own scheme can build one.

#### C.6.10 Report - `MQL5/Include/SSReplay/Report`

##### `strategy-integration-report-10` — LOW — a pre-v76 export keeps `parsed=true` and its reason is never rendered

**File:** `SSR_ClassReport.mqh:279` · **Category:** zero-empty

```mql5
      if(out.key == "")
         out.problem = "exported before v76, so it cannot be checked "
                       "against the others";
      out.parsed = true;
```

**Failure scenario** [CONFIRMED FROM CODE] — A coach collects twenty journals exported before v76 (none carries `session_key`). Every file parses, so `m_key` stays `""` and `m_key_agree` stays 0. The page prints "Ran this session 0" in the KPI row and the caveat "0 of the 20 readable files ran the same session. The rest are marked below and are NOT comparable with the others" — but `odd_row` (558) and `odd` (606) are both conditioned on `m_key != ""`, so **nothing is marked anywhere**, and the one string that explains why is written to `out.problem` and never rendered, because `problem` is printed only in the unreadable-files table guarded by `!parsed`. The coach is told to look for markings that do not exist. The companion script has the same gap: `SSR_ClassReport.mq5` prints `s.problem` only in its `if(!s.parsed)` branch, so the reason does not even reach the Experts log. Severity LOW because no number on the page is wrong in this state — with no keys at all there is no cross-session mixing — so the defect is a self-contradicting caveat plus a diagnostic with no render path.

**Why** [CONFIRMED FROM CODE] — `parsed` is set true on the line after `problem`, so the file counts toward `readable`; the caveat fires whenever `m_key_agree < readable`.

**Verifiers** — Traced end to end; severity lowered.

**Fix** [RECOMMENDATION] — Make the caveat case-aware and render the reason. When `m_key == ""` print instead "none of these %d files carries a session key (exported before v76), so they cannot be checked against each other", and when `m_key != ""` keep the existing wording. Then show `problem` for parsed files too — a small italic note beside the name in the league table — so a file's own explanation reaches the page it is about.

#### C.6.11 Integration - `MQL5/Include/SSReplay/Integration`

##### `strategy-integration-report-12` — LOW — `SetSlot` is unbounded while `Discover` scans 1..8

**File:** `SSR_Publisher.mqh:121` · **Category:** boundary

```mql5
   void              SetSlot(const int slot)     { m_slot = slot; }
```

**Failure scenario** (verifiers' corrected magnitudes) [CONFIRMED FROM CODE] — The host gives each extra stream its own publisher on `InpSlot+1+i` (1396). Extra streams are capped at 3, so the highest slot a session can occupy is `InpSlot+3` and a stream becomes undiscoverable when `InpSlot >= 6` (not merely at 8): those sessions publish to names no conforming client will look at, while `Withdraw`/`Begin` still work, so nothing reports it. Conversely `InpSlot=1` with three extra symbols occupies slots 1..4, so a second replay started at `InpSlot=2` overwrites the first session's stream-2 variables — two sessions fighting over one namespace, which is what `SSR_Contract.mqh:47-49` says slots exist to prevent. Partially detected: the host scans existing replay symbols for its own `.SSR<slot>` suffix and prints "NOTE: … is OPEN and also on replay slot N … set Replay slot to N+1 on one of them" (1604-1628) — but that is a `Print`, not a refusal, and it covers only the custom-symbol namespace; nothing checks the publisher's global-variable namespace or an existing heartbeat.

**Why** [CONFIRMED FROM CODE] — `SetSlot` takes any int with no clamp and no error path; `SSRGvName` concatenates whatever it is given; `CSSRClient::Discover` loops `s = 1..SSR_MAX_SLOTS` with `SSR_MAX_SLOTS` 8; `InpSlot` is an unvalidated input copied into the session file and never range-checked anywhere.

**Verifiers** — Every cited fact holds; magnitudes corrected.

**Fix** [RECOMMENDATION] — Clamp where the value enters and reserve the range the session needs. `SetSlot` should refuse out-of-range values (`if(slot < 1 || slot > SSR_MAX_SLOTS) { m_slot = 1; return false; }`, returning bool so the host can log), and the host should validate `InpSlot + SSR_EXTRA_STREAMS <= SSR_MAX_SLOTS` at init and refuse to start otherwise — the message it already prints for the symbol collision is the model. Then extend the collision check to the GV namespace: `Begin()` can read the slot's heartbeat and refuse a slot whose heartbeat is fresh, which is the one check that makes two sessions safe by construction.

##### `strategy-integration-report-7` — LOW — a command whose sequence equals the last executed one is dropped and reported as a timeout

**File:** `SSR_Publisher.mqh:229` · **Category:** input-validation

```mql5
      long seq = (long)Get(SSR_GV_CMD_SEQ, 0.0);
      if(seq == 0 || seq == m_last_seq)
         return false;                  // nothing new
```

**Failure scenario** (verifiers' corrected version — the finder's scenario is wrong) [CONFIRMED FROM CODE] — The guard is a plain equality against the last **executed** sequence, not a monotonic test and not a comparison against the published `cmd.ack`, and on the early return nothing is written to `cmd.ack` or `cmd.rc` — so `CSSRClient::Send`'s wait loop can only exit through the timeout branch and reports `SSR_RC_REFUSED` with "the replay session did not answer within 500ms": a duplicate rejection diagnosed as a dead session. But `m_last_seq` advances to each executed sequence (243), so a restarted client loses **at most one** command, not the third: in the finder's own example (previous client reached seq 3, restart sends 1,2,3) nothing is dropped, because 1 ≠ 3. The reachable cases are a restarted client whose first command is seq 1 while the publisher's last executed sequence was 1, and two clients sharing one slot whose independent counters momentarily coincide.

**Why** [CONFIRMED FROM CODE] — `m_last_seq` is reset only by `Begin()`, which runs on the replay side; `CSSRClient` initialises `m_seq` to 0 and never reads `cmd.ack`, so a fresh client cannot learn where the publisher's counter is.

**Verifiers** — Mechanism real, scenario corrected, severity lowered.

**Fix** [RECOMMENDATION] — Two independent halves. Make the test monotonic: `if(seq == 0 || seq <= m_last_seq) return false;` removes the ambiguity for a monotonic client and makes a restart's low sequences ignored rather than half-executed — and have the client learn where to start by reading `cmd.ack` in `Refresh()` and setting `m_seq = MathMax(m_seq, ack)`. Second half, independent of the first: on any early return, write `cmd.rc = SSR_RC_DUPLICATE` and `cmd.ack = seq` so the client gets a real answer instead of a timeout. The wrong diagnosis is the part that costs a user an afternoon.

#### C.6.12 Spike kit - `MQL5/Include/SSReplay/Spike`

##### `spikes-audits-25` — LOW — spike CSVs are opened without `FILE_SHARE_WRITE`

**File:** `SSR_SpikeKit.mqh:97` · **Category:** measurement validity

```mql5
int h = FileOpen(file, FILE_READ | FILE_WRITE | FILE_TXT | FILE_ANSI | FILE_SHARE_READ);
if(h == INVALID_HANDLE)
  {
   PrintFormat("[SSR] cannot open %s err=%d", file, GetLastError());
   return;
  }
```

**Failure scenario** (verifiers' corrected version) [CONFIRMED FROM CODE] — `SSR_Append` is the single writer for `env.csv`, `results.csv` and `verdicts.csv`, and it requests write access while granting others read only. B2, D1 and D3 each instruct the operator to run `SSR_Probe_UIJitter` concurrently, and that probe appends four metric rows to the same `results.csv` every 10 seconds for the whole window — so whenever two opens overlap, one gets `INVALID_HANDLE` and the row is dropped with nothing but a `Print`: the jitter series B2 and D1 declare their results meaningless without is the part most likely to develop silent holes. Exposure is narrow, though: each open holds the file for well under a millisecond and the probe writes four rows per 10 s, so collisions are rare per run and accumulate mainly in D3's hours-long window. Phase-0 measurement harness only; no product path uses `SSR_Append`.

**Why** [CONFIRMED FROM CODE] — `FILE_SHARE_WRITE` is absent from the flag set, and the failure is a `Print`, not a verdict, so a dropped row leaves no trace in the artefacts.

**Verifiers** — Every fact checks out; exposure narrowed.

**Fix** [RECOMMENDATION] — Add `FILE_SHARE_WRITE` to the flag set and retry briefly on failure: `for(int a = 0; a < 5 && h == INVALID_HANDLE; a++) { Sleep(20); h = FileOpen(...); }`. Then make a dropped row visible rather than silent — increment a `g_ssr_append_fails` counter and emit it as a metric in `SSR_End`, so an artefact with holes says so.

#### C.6.13 Common - `MQL5/Include/SSReplay/Common`

##### `chart-13` — LOW — the flight recorder truncates `chart_id` to 32 bits

**File:** `SSR_FlightRecorder.mqh:256` · **Category:** boundary

```mql5
              s.chart_count, (int)s.chart_id,
```

**Failure scenario** (verifiers' corrected version) [CONFIRMED FROM CODE] — `SSRFlightSample.chart_id` is a `long` filled from a real chart id (`Standalone.mq5:2408-2409`), and `Write` formats it as `(int)s.chart_id` against `%d`, so any id above 2^31−1 is written wrapped — frequently negative — into the `chart_id` column of the one artefact the author relies on for remote diagnosis, since they cannot run the product themselves. That real MT5 chart ids exceed 32 bits is an inference about MT5's id scheme rather than evidence from this tree, but the cast is lossy for any such id regardless. The `emit_ticks`/`emit_calls` half of the finding is far weaker: those would need to exceed 2.1 billion in one recording (over 268 million bars at 8 ticks/bar) before wrapping, so in practice `chart_id` is the only column that truncates. [POTENTIAL_RISK for whether ids exceed 2^31 on a given terminal.]

**Why** [CONFIRMED FROM CODE] — The `%d` specifier forces a 32-bit argument, so the cast is the symptom of the format, not an independent choice.

**Verifiers** — Truncation plainly in source; the other columns exonerated.

**Fix** [RECOMMENDATION] — Change the specifier and drop the cast: `%I64d` with `s.chart_id`, or `IntegerToString(s.chart_id)` concatenated, which is immune to specifier mistakes. Worth a sweep of the recorder's format string for any other `%d` paired with a `long` — the same mistake in a diagnostic file is expensive precisely because nobody can reproduce the run.

#### C.6.14 Test harness - `MQL5/Scripts/SSReplay/Tests`

The entries in this group are assertions that cannot fail, or that assert something other than their title. None of them indicates a product defect; together they are why a build that has never run reports green. Each fix is a test edit. [CONFIRMED FROM CODE]

##### `tests-b-3` — LOW — T13.8 claims seed reproducibility and asserts three tautologies

**File:** `SSR_T13_Strategy.mq5:539` · **Category:** test strength

```mql5
      Check("both hosts registered it", s1 != NULL && s2 != NULL);
      Check("under the same name", s1.Name() == s2.Name(), s1.Name());
      CheckEq("and the second host took both", 2, h2.Count());
```

**Failure scenario** [CONFIRMED FROM CODE] — Delete `SetSeed`'s body, or seed each context with the registration index instead of `m_seed ^ NameHash(name)`, and T13.8 still passes all three assertions; two hosts with **different** seeds also pass. The section named "the same seed gives the same strategy" cannot detect a non-reproducible or order-dependent RNG stream — the per-strategy stream mixing is simply unverified.

**Why** [CONFIRMED FROM CODE] — The section draws no random number and never touches a context. `s1.Name()` and `s2.Name()` are two instances of `CSSRRefBreakout`, whose `Name()` returns the constant "ref-breakout", so the comparison is a literal against itself; `h2.Count()` counts registrations, not streams. `SetSeed` only stores `m_seed`; the seeding under test is at `SSR_StrategyHost.mqh:141`.

**Verifiers** — Traced in full; a coverage gap, not a product fault.

**Fix** [RECOMMENDATION] — The facility is observable: `rng` is a public member of the public context, and the file's own `CSSRCheater` already reads `ctx.market`. Add a probe strategy that records `ctx.rng.Next()` in `OnBar`, run two hosts with the same seed and assert the two sequences are identical, then run one with a different seed and assert they differ. Three assertions that can actually fail, replacing three that cannot.

##### `tests-b-4` — LOW — T14.8's "the command set is exactly the documented ones" is unfalsifiable

**File:** `SSR_T14_Integration.mq5:355` · **Category:** boundary

```mql5
      for(int cmd = 0; cmd <= 11; cmd++)
        {
         if(cmd == SSR_CMD_PLAY || cmd == SSR_CMD_PAUSE ||
            ... || cmd == SSR_CMD_BUY_RISK || cmd == SSR_CMD_SELL_RISK)
            continue;
         read_verbs++;
        }
      CheckEq("the command set is exactly the documented ones", 0, read_verbs);
```

**Failure scenario** [CONFIRMED FROM CODE] — `SSR_Contract.mqh` defines exactly twelve verbs at 0..11 and the `if` enumerates all twelve, so every iteration hits `continue`, `read_verbs++` is unreachable, and the assertion is a literal `0 == 0`. Add `#define SSR_CMD_PRICE_AT 12` — precisely the read verb the section exists to forbid — and it still passes, because the loop's bound is a hardcoded 11. The section's stated purpose ("a future edit that adds one of these verbs should have to delete a test that says why it must not") is not served. Nothing in the product misbehaves.

**Why** [CONFIRMED FROM CODE] — There is no `SSR_CMD_COUNT`/`SSR_CMD_MAX` in the contract and no assertion on the enum's size.

**Verifiers** — Verified against the enum.

**Fix** [RECOMMENDATION] — Give the contract a count — `#define SSR_CMD_COUNT 12` next to the verbs, with `CheckEq("the contract still has twelve verbs", 12, SSR_CMD_COUNT)` — and loop `cmd = 0; cmd < SSR_CMD_COUNT`. A thirteenth verb then fails the count assertion immediately, which is the tripwire the comment describes; the loop keeps its role for anything added inside the range.

##### `tests-b-5` — LOW — T15.8 never establishes its precondition

**File:** `SSR_T15_Ux.mq5:421` · **Category:** event-handling

```mql5
      long was_nav = ChartGetInteger(chart, CHART_QUICK_NAVIGATION);
      long was_key = ChartGetInteger(chart, CHART_KEYBOARD_CONTROL);
      ...
      CheckEq("quick navigation is off while the panel lives",
              0, ChartGetInteger(chart, CHART_QUICK_NAVIGATION));
```

**Failure scenario** (verifiers' corrected version) [CONFIRMED FROM CODE] — The section is **not** unconditionally vacuous: on a default chart (both properties on) all four assertions bite. The defect is the missing precondition — it never asserts or forces `was_nav`/`was_key == 1`, so on any chart where they are already off (a user who turned them off, or a chart left that way by an earlier T15.8 run that died between `Create` and `Destroy`) all four pass even with the two `ChartSetInteger` lines deleted from `CSSRPanel::Create`. The "given back" pair is weaker still: with `was_nav == 0` it compares 0 against 0 and cannot distinguish "restored the saved value" from "wrote the same constant twice". This is exactly the regression class the section was added for ("Fifteen phases and 1,159 assertions never saw it"), so a guard that can silently stop guarding matters.

**Why** [CONFIRMED FROM CODE] — No `ChartSetInteger(..., true)` anywhere in the section before `Create`.

**Verifiers** — Provable from source; the "unconditionally vacuous" framing corrected.

**Fix** [RECOMMENDATION] — Force the precondition and assert it: `ChartSetInteger(chart, CHART_QUICK_NAVIGATION, true); ChartSetInteger(chart, CHART_KEYBOARD_CONTROL, true); CheckEq("precondition: quick nav on", 1, ChartGetInteger(chart, CHART_QUICK_NAVIGATION));` before `panel.Create`. Four lines, and the section becomes a real guard on every chart.

##### `tests-a-8` — LOW — "warmup survived the reset" is measured with a write counter

**File:** `SSR_T1_CoreEngine.mq5:355` · **Category:** test strength (not future-data-leakage — verifiers' correction)

```mql5
      int seeded = sink.SeedBarCount();
      Check("reset succeeded", ctrl.Reset());
...
      CheckEq("warmup survived the reset", seeded, sink.SeedBarCount());
```

**Failure scenario** [CONFIRMED FROM CODE] — `SeedBarCount()` is a monotonically increasing count of bars **ever written** and `TruncateFrom` never touches it, so if `Reset()` deleted the warmup the number would not move and the test would pass; it can only fail on the opposite fault (extra re-seeding). The risk that matters on a terminal — Reset truncating into the warmup and leaving the higher timeframes empty — is uncovered, and `T8.8:320` repeats the pattern for Restart. Scope: the in-memory recording sink stores no bars at all, so the uncovered risk is specific to the MT5 custom-symbol sink path, which this test does not exercise.

**Why** [CONFIRMED FROM CODE] — `m_seed_bars += count` is the only write outside `Clear()`; the sink exposes no live bar count, so no assertion in the current sink API could distinguish a surviving warmup from a deleted one.

**Verifiers** — Sink and controller traced; category corrected.

**Fix** [RECOMMENDATION] — Give the sink the fact the test needs: add `long OldestBarMsc()` (the recording sink can track the lowest seeded bar time; the MT5 sink can answer from `SeriesInfoInteger(..., SERIES_FIRSTDATE)`), and assert `CheckEq("warmup survived the reset", warmup_first, sink.OldestBarMsc())`. That also gives `RepairWarmupIfLost` (`mt5-symbol-1`) something testable.

##### `tests-a-9` — LOW — T2.6's dangling-guard test never lets the guard die

**File:** `SSR_T2_DataEngine.mq5:297` · **Category:** object-lifecycle

```mql5
      src.DetachGuard();
      MqlRates after[];
      int na = bp.ReadBars(sym, win_start + SSR_MSC_PER_MIN,
                                win_start + 5 * SSR_MSC_PER_MIN, after);
      Check("reads still work after detach", na >= 0, IntegerToString(na));
```

**Failure scenario** (verifiers' corrected version) [CONFIRMED FROM CODE] — `CSSRFutureGuard guard` is a stack object declared at 267 inside the same `else` block and still alive at 301, so no dangling pointer can be dereferenced: the use-after-free the comment names is unreachable. The assertion is also insensitive to the behaviour it names — guard refusal returns **0** (`SSR_Mt5Providers.mqh:259-263`), so `na >= 0` holds whether or not `DetachGuard()` cleared the pointer. The lifetime the section claims to cover (source outliving the guard) is traversed unasserted in T2.9 after the guard's scope closes, and `CSSRMt5DataSource`'s destructor calls `DetachGuard()` for exactly that reason — untested.

**Why** [CONFIRMED FROM CODE] — Object lifetimes are the wrong way round for the stated test.

**Verifiers** — Lifetimes traced; the return-value insensitivity is theirs.

**Fix** [RECOMMENDATION] — Two changes. Assert the observable effect: `na > 0` after the detach (a still-armed guard would refuse the future window and return 0), or compare `guard.Violations()` before and after. And make the lifetime real: allocate the guard with `new`/`delete` (or put it in a tighter inner scope) so it is destroyed **before** the post-detach read — which is the scenario the destructor's `DetachGuard()` exists for.

##### `tests-a-11` — LOW — T2.8 closes with an unconditional `Check(..., true)`

**File:** `SSR_T2_DataEngine.mq5:406` · **Category:** test strength

```mql5
         Check("Phase 1 contract held with a real source", true);
```

**Failure scenario** [CONFIRMED FROM CODE] — A literal `true` bumps `g_pass` and prints "PASS Phase 1 contract held with a real source", a sentence a reader takes as a verified architectural claim; it verifies nothing, and the `g_fail` branch is unreachable. `grep 'Check("[^"]*", *true)'` matches this line and only this line across the whole suite. The claim it names **is** in fact demonstrated by the block it sits in (the unmodified controller compiling and replaying through the real source), so the cost is one false positive in the count.

**Why** [CONFIRMED FROM CODE] — Nothing between 402 and 406 computes a consulted value.

**Verifiers** — Uniqueness claim verified; classified IMPROVEMENT in substance.

**Fix** [RECOMMENDATION] — Delete the line and put its sentence in a comment above the block that proves it. If a visible assertion is wanted, assert the thing that would break if the contract did not hold: `CheckEq("the same controller class reached READY", SSR_STATE_READY, ctrl.Status())` — already true here, and it fails if a future edit makes the real source need a different controller.

##### `tests-a-7` — LOW — T3.8 runs against a symbol T3.7 already deleted

**File:** `SSR_T3_CustomSymbol.mq5:441` · **Category:** object-lifecycle

```mql5
      mgr.Destroy();
      SSRPause(300);
      string sym = SSRReplaySymbolName(origin, InpSlot);
      ResetLastError();
      long d = SymbolInfoInteger(sym, SYMBOL_DIGITS);
```

**Failure scenario** (verifiers' corrected version) [CONFIRMED FROM CODE] — `mgr`, `a` and `second` all name the identical symbol (T3:427 asserts it), and T3.7's last statement is `second.Destroy()`, which reaches `CustomSymbolDelete`. So the symbol is already gone when T3.8 begins and `mgr.Destroy()` is a silent no-op (`Destroy` treats deleting an absent symbol as success by design). The phase's final assertion — that teardown removes the custom symbol — is structurally incapable of failing: if `Destroy` regressed to a no-op, T3.8 would print two PASSes and the user would discover it as a leftover symbol blocking the next session. One caveat the finder omits: if `a.Create` at 418 fails, the Skip branch runs, `second.Destroy()` never executes, and `mgr`'s symbol is still present — so T3.8 is meaningful only in the failure path it was not written for.

**Why** [CONFIRMED FROM CODE] — `SetAnonymous` is never called in this file, so all three managers derive the same name.

**Verifiers** — Naming and lifecycle traced.

**Fix** [RECOMMENDATION] — Give T3.8 its own symbol: `CSSRCustomSymbolManager t38; t38.Create(origin, InpSlot + 1);` then assert the symbol exists, `t38.Destroy()`, and assert it is gone. Slot+1 keeps it clear of the earlier sections, and the assertion then fails if `Destroy` ever stops deleting.

##### `tests-a-5` — LOW — T5.6's "foreign objects ignored" is a vacuous pass

**File:** `SSR_T5_Ui.mq5:221` · **Category:** event-handling

```mql5
      Check("foreign objects ignored",
            !panel.OnEvent(CHARTEVENT_OBJECT_CLICK, l, d, foreign));
      CheckEq("nothing was sent", 0, port.play + port.pause + port.reset);
```

**Failure scenario** [CONFIRMED FROM CODE] — Since `OnEvent` has no `CHARTEVENT_OBJECT_CLICK` branch it returns false for **every** object click, the panel's own buttons included, so "foreign objects ignored" proves only that object clicks are universally ignored. If someone later added a click branch that dispatched on any `sparam` without a prefix check, this green assertion would stay green. It is the quieter half of the same hole as `tests-a-1`: one line shouts, this one lies quietly. The prefix filter it means to exercise lives in `PollClicks` (`if(StringFind(name, m_prefix) != 0) continue;`), which the test never calls.

**Why** [CONFIRMED FROM CODE] — Same trace as `tests-a-1`; the trailing `return false` at 2971 is the only path an object-click event can take.

**Verifiers** — Both assertions vacuous; cost is a coverage illusion.

**Fix** [RECOMMENDATION] — Drive `PollClicks` with both kinds of object: latch `OBJPROP_STATE` on a foreign-named button and assert nothing was sent **and** the latch was left alone (the panel must not un-latch objects it does not own), then latch `SSRT5_play` and assert it was sent and un-latched. That tests the prefix filter in both directions, which nothing currently does.

##### `tests-a-6` — LOW — T5.9 asserts on the test double instead of the panel

**File:** `SSR_T5_Ui.mq5:318` · **Category:** event-handling

```mql5
      Check("the port can be jumped", p59.JumpTo(123456789));
      CheckEq("which was recorded",   123456789, p59.last_jump_msc);
      Check("and restarted", p59.Restart());
      CheckEq("counted", 1, p59.restart);
```

**Failure scenario** (verifiers' corrected version) [CONFIRMED FROM CODE] — All four call `CFakePort`'s own two-line bodies (declared at T5:67-69), so nothing traverses `panel59` and all four can only pass, under a section header that says "the navigation verbs reach the port". Their actual documented purpose (T5:291-295) is a **compile/link-time** guard that `CFakePort` still implements the Phase 8 port verbs — which is legitimate, so the assertions are mislabelled rather than useless. The real gap is that the panel-side paths have no test at all: `SSR_CMD_RESTART` is reachable only via the "restart" button in `PollClicks` (2716) and appears in no `SSRAddKey` call, and `SSR_CMD_JUMP` is excluded by `Owns()` and handled by the host.

**Why** [CONFIRMED FROM CODE] — The two assertions immediately above (310-316, LEFT and PgUp) *do* go through `panel59.OnEvent` and are sound — the contrast is inside one block.

**Verifiers** — Factual core holds; purpose clarified.

**Fix** [RECOMMENDATION] — Retitle the four as "the port interface still compiles" (a comment is enough) and add the missing panel-side coverage where it is reachable: latch `SSRT5_restart`, call `panel59.PollClicks()`, and assert `p59.restart == 1`. `SSR_CMD_JUMP` belongs to the host, so assert instead that `panel.Owns(SSR_CMD_JUMP)` is false — the invariant that makes the host responsible.

##### `tests-a-14` — LOW — T6.8's closing assertion is a tautology

**File:** `SSR_T6_History.mq5:300` · **Category:** test strength

```mql5
      Check("and it differs from the flat default or matches deliberately",
            v.SessionGap() >= before);
```

**Failure scenario** (verifiers' corrected version) [CONFIRMED FROM CODE] — The name asserts "A or not-A" and the condition is unconditional: `before` is the default-constructed validator's gap, which is exactly `SSR_SESSION_GAP_MSC`, and `SSRSymbolSessionGap` ends with `if(widest < SSR_SESSION_GAP_MSC) widest = SSR_SESSION_GAP_MSC;` while also returning that constant when the symbol declares no sessions — so its result is unconditionally ≥ `before`. Stronger than the finder said: the **preceding** assertion at 290 (`gap >= SSR_SESSION_GAP_MSC`) is incapable of failing for the same reason, so both lines are tautologies. The question the section exists to answer — does a 24/5 forex symbol learn a *different* gap from a session-broken index — is never asked.

**Why** [CONFIRMED FROM CODE] — The floor inside `SSRSymbolSessionGap` makes every comparison against that constant true.

**Verifiers** — Confirmed and strengthened.

**Fix** [RECOMMENDATION] — Assert the distinction, not the floor: learn from two symbols (the origin and a deliberately session-broken one, or a synthetic `CSSRDataValidator` fed a session table) and assert the two gaps differ, plus `CheckEq` the known value for one of them. If only one symbol is available at test time, at least assert `v.SessionGap() == SSRSymbolSessionGap(origin)` and print both, so a reader can see whether the floor was hit.

##### `tests-a-12` — LOW — T7.1 asserts arithmetic over its own literals

**File:** `SSR_T7_Performance.mq5:66` · **Category:** test strength

```mql5
      double ticks_per_bar = 8.0;
      double at_50x = (50.0 / 60.0) * ticks_per_bar;
      Check("50x needs under 10 ticks/sec", at_50x < 10.0,
            StringFormat("%.2f", at_50x));
```

**Failure scenario** (verifiers' corrected version) [CONFIRMED FROM CODE] — Three of T7's assertions are built entirely from local literals — 8.0, 50.0, 60.0, 2000.0, 86400.0 — none from a symbol the product defines, so they cannot fail and cannot detect a change: if `InpTicksPerBar`'s default moved from 8 to 32, or the ladder top changed, the reasoning these lines pin would be wrong and all three would still pass. The staleness is already real and larger than the finder said: index 18 is 200× and index 19 is `SSR_SPEED_MAX` = 1000×, so "a day at 50x still takes over 25 minutes, which is why Jump exists rather than a bigger number" is stale by a factor of **twenty**, not four.

**Why** [CONFIRMED FROM CODE] — No `SSR_*` macro, enum or function appears in any of the three conditions.

**Verifiers** — Both halves verified; the ladder-top correction is theirs.

**Fix** [RECOMMENDATION] — Substitute the real constants: `double ticks_per_bar = 8.0;` becomes a reference to the input's documented default (or better, the test's own `SetTicksPerBar` value read back), and `50.0` becomes `SSRSpeedLadder(SSR_SPEED_LADDER_SIZE-1) / 100.0`. Written that way the same three lines would have caught the ladder change that `tests-a-2` and `tests-a-3` missed, and the narrative comment would have had to be updated with it.

##### `tests-a-17` — LOW — T8.3's headline assertion admits any tick count from 1 upward

**File:** `SSR_T8_Navigation.mq5:148` · **Category:** test strength

```mql5
      Check("the tick count came BACK, not to zero",
            ctrl.TicksEmitted() > 0,
...
      Check("and it is near where it was",
            ctrl.TicksEmitted() <= mark_ticks,
```

**Failure scenario** (verifiers' corrected version) [CONFIRMED FROM CODE] — The rewind assertions bound the restored counter only by `> 0` and `<= mark_ticks`, so any shortfall from a partial snapshot restore passes — including a restore to the very first checkpoint. The section is titled "rewind restores counters, does not reset them", the claim is "near where it was", and nothing quantifies "near"; the one bug it does catch is a plain seek that zeroes the cursor, while the failure a snapshot ring actually risks is a partial restore. The finder's magnitude is wrong: `Wire()` sets 8 ticks per bar and `SSR_SPEED_1` is 1×, so 900 × `Pump(1000)` advances 900 s = 15 M1 bars and `mark_ticks` is on the order of 120 ticks — the admitted window is [1, ~120], not [1, ~7000].

**Why** [CONFIRMED FROM CODE] — The rewind is an exact-distance `StepBackward`, so the deterministic expectation is that the counter returns to `mark_ticks` exactly, within one checkpoint interval.

**Verifiers** — Weak assertion confirmed, magnitude corrected.

**Fix** [RECOMMENDATION] — Quantify it: the test already sets the snapshot interval in T8.2, so compute the worst legitimate shortfall as `ticks_per_bar * (interval_msc / 60000)` and assert `mark_ticks - ctrl.TicksEmitted() <= that`. A partial restore then fails, which is the section's own stated purpose.

##### `tests-a-13` — LOW — T8.5's clamp and no-op assertions read only a return value

**File:** `SSR_T8_Navigation.mq5:223` · **Category:** boundary

```mql5
      Check("jumping to now is a no-op", ctrl.JumpTo(ctrl.Now()));

      //--- out of range must be clamped, not refused into an error
      Check("clamped past the end", ctrl.JumpTo(g_end + 999999999));
```

**Failure scenario** [CONFIRMED FROM CODE] — "Jumping to now is a no-op" can never fail: `JumpTo` clamps to the same value, fails the backward test, and hits `if(target == m_clock.now_msc) return true;` — an unconditional true for any loaded controller (the backward path has the same shape at `if(delta <= 0) return true;`). "Clamped past the end" never reads `ctrl.Now()` afterwards, so it cannot tell a correct clamp to `end_msc` from a clamp to `start_msc` or a landing one bar short — either would pass while silently rewinding the user's whole session. The section is titled "JumpTo picks the right direction" and the out-of-range case is the one place the landing point is never checked; every other jump in T8.5 does assert `ctrl.Now()`.

**Why** [CONFIRMED FROM CODE] — The only follow-up for the over-range case is `Status() != SSR_STATE_ERROR`.

**Verifiers** — `JumpTo` traced; both tautologies confirmed.

**Fix** [RECOMMENDATION] — Add the two missing reads: `CheckEq("landed on the end", g_end, ctrl.Now())` after the over-range jump (or the bar-open form used at 220), and for the no-op case capture `long before = ctrl.Now(); long ticks = ctrl.TicksEmitted();` and assert both are unchanged afterwards — a no-op that emits ticks is the regression worth catching.

##### `tests-b-11` — LOW — T9.1's rounding assertions are one-sided

**File:** `SSR_T9_Trading.mq5:79` · **Category:** r-multiple

```mql5
      double lot = r.LotForRisk(10000.0, 1.0, 1000.0, 993.0);   // 14.28 lots
      Check("rounded down to the step", lot <= 14.28 + 1e-9, ...);
      Check("and never above the asked risk", r.RiskOf(lot, 7.0) <= 100.0 + 1e-6, ...);
```

**Failure scenario** (verifiers' corrected version) [CONFIRMED FROM CODE] — Both predicates are **upper bounds**, satisfied by every value in [0, 14.28]. So the pair proves "never risks more than asked" but not "rounds down to the step": a regression that floors 14.2857 to 14.00 or 10.00 — i.e. under-sizes — passes. A blanket 0.0 refusal would still be caught, but by the different-input `CheckNear` at 68, not by this pair. The unguarded direction is conservative, so nothing in the risk guarantee is weakened.

**Why** [CONFIRMED FROM CODE] — The true answer is 14.28 (`RoundToStep(14.2857)` floors on a 0.01 step) — a figure the test writes in a comment and never asserts; `LotForRisk` has four separate 0.0 refusal paths.

**Verifiers** — Arithmetic re-derived from `SSR_RiskEngine.mqh:94-131`.

**Fix** [RECOMMENDATION] — Assert the value: `CheckNear("rounded down to the step", 14.28, lot, 0.001)` replaces the first line and keeps the second as the risk guarantee. Add one more input whose exact rounding differs (e.g. a 0.1-step symbol) so the step, not just the arithmetic, is covered.

##### `tests-b-6` — LOW — every `Risk().Configure` in T9 is discarded by `Load`

**File:** `SSR_T9_Trading.mq5:112` · **Category:** input-validation

```mql5
      acct.SetBalance(10000.0);
      acct.Risk().Configure(1.0, 1.0, 0.01, 100.0, 0.01, digits);
      ...
      Check("loaded", ctrl.Load("TEST", start, endt), ctrl.LastErrorText());
```

**Failure scenario** (verifiers' corrected version) [CONFIRMED FROM CODE] — `Load` broadcasts `OnSessionStart`, whose last act is `m_risk.ConfigureFromSymbol(symbol)` — a wholesale overwrite of the six fields `Configure()` just set — and the symbol is "TEST", which no terminal resolves, so the sections run on `ConfigureFromSymbol`'s zero-fallbacks (digits 0, point 1.0, tick_size 1.0, tick_value 1.0). Those happen to give the same `RiskOf()` answers, so nothing fails today: the six `Configure` calls (112, 180, 229, 268, 331, 404) are **dead setup**. Any T9 assertion added later about lot sizing, `risk_at_entry` or R would be measuring the fallback path, and if a broker ever resolves a symbol literally named TEST the specs change under the section with no assertion to notice. T10 documents the correct order and does the opposite: "set AFTER OnSessionStart, which reconfigures risk from the symbol" (`SSR_T10_Statistics.mq5:65-67`).

**Why** [CONFIRMED FROM CODE] — `Configure` before `Load` cannot survive `Load`.

**Verifiers** — Chain verified; impact is test hygiene only, so LOW rather than MEDIUM.

**Fix** [RECOMMENDATION] — Move every `Risk().Configure(...)` to **after** `ctrl.Load(...)`, as T10 already does, and add one assertion that the specs are what the section intends: `CheckNear("tick value as configured", 1.0, acct.Risk().TickValue(), 1e-9)`. That also documents the ordering hazard where the next reader will meet it.

##### `tests-b-8` — LOW — T9.2's "session start reached the account" is a tautology

**File:** `SSR_T9_Trading.mq5:124` · **Category:** zero-empty

```mql5
      Check("session start reached the account", acct.Balance() == 10000.0,
            DoubleToString(acct.Balance(), 2));
```

**Failure scenario** [CONFIRMED FROM CODE] — Remove the observer registration, or stop broadcasting `OnSessionStart` entirely, and the assertion still passes: `SetBalance` on the line above sets both `m_balance` and `m_balance_initial`, 10000.0 is also the constructor default, and `OnSessionStart`'s only balance action is `m_balance = m_balance_initial` — an identity for this fixture. The only thing it proves is that nothing has traded yet. Registration is already covered by 120-121.

**Why** [CONFIRMED FROM CODE] — The observables `OnSessionStart` uniquely installs — `m_symbol`, `m_digits`, `m_point`, `m_now_msc`, `m_count=0`, `m_next_ticket=1` — are never read.

**Verifiers** — Traced; the name overstates what it proves.

**Fix** [RECOMMENDATION] — Assert something only the broadcast can produce: `CheckEq("session start reached the account", 1, acct.NextTicket())` or a getter for the engine's symbol/point. If no such accessor exists, add `string Symbol() const` to the engine — one line, and it makes every future `OnSessionStart` assertion possible.

##### `tests-b-7` — LOW — T9.7's checkpoint-path claim is not asserted

**File:** `SSR_T9_Trading.mq5:368` · **Category:** session-resume

```mql5
      Check("checkpoints were in play", c5.Snapshots().Count() > 0,
            c5.SnapshotText());
```

**Failure scenario** [CONFIRMED FROM CODE] — Make `NearestAtOrBefore` stop finding a usable checkpoint (a ring-clear regression, a changed interval, a comparison flipped to strict) and `StepBackward` silently takes the `SeekTo` fallback for both of T9.7's rewinds: `Count() > 0` still holds, the trades are still gone — both branches call `PublishRewind`, and it is `OnRewind` that deletes positions after the cut — and T9.7 reports PASS with the snapshot-restore path it exists to cover untested. The path is probably taken today (the first checkpoint is due immediately because `m_last_msc` starts INVALID), which is exactly why the omission is invisible.

**Why** [CONFIRMED FROM CODE] — `Count()` reports how many checkpoints the ring holds, not that one was restored; the discriminating observable is `CSSRSnapshotStore::Restores()` (`SSR_SnapshotStore.mqh:90`), incremented only by `NoteRestore` on the snapshot branch — and unused by the test.

**Verifiers** — `StepBackward`'s two branches traced.

**Fix** [RECOMMENDATION] — One line: capture `int r0 = c5.Snapshots().Restores();` before the rewind and assert `c5.Snapshots().Restores() > r0` after it. That is the assertion the section's own comment describes ("the snapshot path did not, so it gets its own assertion").

##### `tests-b-12` — LOW — T9.8's "a round trip at a flat price loses money" is satisfied by losing nothing

**File:** `SSR_T9_Trading.mq5:433` · **Category:** commission

```mql5
      Check("a round trip at a flat price loses money",
            a6.Balance() < bal1 + 1e-9,
            DoubleToString(a6.Balance(), 2));
```

**Failure scenario** (verifiers' corrected version) [CONFIRMED FROM CODE] — `bal1` is read after the entry commission was charged and the predicate is true when `Balance() == bal1`, so it is a **non-increase** test: the spread and the 10-point slippage contributions to the round trip are never bounded below, and a favourable-fill regression is caught only if its gain exceeds the 7.0 exit commission that the preceding `CheckNear` does pin. The finder's stronger claim — that a zero-charging `Close()` would slip through — is wrong: that fails the `p.commission == 14.0` assertion one line above.

**Why** [CONFIRMED FROM CODE] — The only lower-bounded cost in the section is the commission.

**Verifiers** — Traced; scope narrowed.

**Fix** [RECOMMENDATION] — Bound the whole cost: `Check("a round trip at a flat price loses money", a6.Balance() <= bal1 - 7.0 - slip_cost + 1e-9, …)` where `slip_cost` is computed from the configured slippage and volume the section already knows. Then the assertion measures what its name says, and a favourable-fill regression of any size fails.

#### C.6.15 QA scripts - `MQL5/Scripts/SSReplay/QA`

##### `qa-smoke-7` — LOW — stage 7 increments the pass count with no condition tested

**File:** `SSR_QA_Smoke.mq5:724` · **Category:** zero-empty

```mql5
      Ok("manager redraws on demand", "Redraw(force) returned");
```

**Failure scenario** [CONFIRMED FROM CODE] — `Ok()` does `g_pass++` with no predicate, so reaching the line is the whole of its evidence — which control flow already implies. The headline "=== N passed, 0 FAILED ===" overstates what was measured by one, and a reader scanning the report sees a named property ("the manager redraws on demand") that no code checked. `grep '^\s*Ok('` returns two hits in 5512 lines — this one and 2207, which *is* guarded; every other assertion goes through `Check(what, cond, detail)`, and the file's own idiom for an unmeasurable property is `Note()`, which moves neither counter.

**Why** [CONFIRMED FROM CODE] — Unconditional inside an already-passing block.

**Verifiers** — Confirmed, including that the material for a real assertion is two lines above.

**Fix** [RECOMMENDATION] — `Redraw` returns a bool and `Snaps()` is already read nearby: `Check("manager redraws on demand", mgr.Redraw(true), StringFormat("snaps=%d", mgr.Snaps()))`. If the return value is not meaningful, use `Note()` so the property is reported without inflating the count.

##### `qa-smoke-5` — LOW — the blind-mode restore check covers one of two properties

**File:** `SSR_QA_Smoke.mq5:1144` · **Category:** object-lifecycle

```mql5
      Check("blind mode hides what the chart announces",
            !(bool)ChartGetInteger(probe2, CHART_SHOW_OHLC) &&
            !(bool)ChartGetInteger(probe2, CHART_SHOW_PRICE_SCALE), ...
      blind.RestoreAll();
      Check("and puts the chart back the way it was",
            (bool)ChartGetInteger(probe2, CHART_SHOW_OHLC) == had_ohlc, ...
```

**Failure scenario** (verifiers' corrected version) [CONFIRMED FROM CODE] — Apply asserts two properties; restore asserts one. The price scale's pre-state is never captured and never re-compared, so a future regression in the price-scale restore would be reported as PASS — and on a terminal whose template has the OHLC line off (a common preference), `had_ohlc` is false and the restore assertion is `false == false`, holding whatever `RestoreAll` did to anything. Stage 36 repeats the asymmetry at 3700-3702. The finder's stated consequence is **not** correct: `CSSRBlindMode::Restore` writes all three properties back from `m_had_*` unconditionally and `RestoreAll` drains every saved chart, so today's code leaves no chart without a price axis; and `probe2` is a chart the suite itself opened and closes, never the user's.

**Why** [CONFIRMED FROM CODE] — Only `had_ohlc` is captured at 1130; no `had_scale` exists.

**Verifiers** — Asymmetry confirmed; the trap consequence refuted.

**Fix** [RECOMMENDATION] — Capture and compare both: `bool had_scale = (bool)ChartGetInteger(probe2, CHART_SHOW_PRICE_SCALE);` beside `had_ohlc`, then assert both in the restore check — and force the precondition (`ChartSetInteger(probe2, CHART_SHOW_OHLC, true)`) so the comparison cannot go vacuous, the same fix `tests-b-5` needs. Apply it to stage 36 as well.

##### `qa-smoke-13` — LOW — stage 18's compact assertion checks two ids and cannot reach the fifth tab

**File:** `SSR_QA_Smoke.mq5:1783` · **Category:** object-lifecycle

```mql5
            Check("and dropped only what is consulted",
                  !QVisible(pchart, "SSRQ_tab0") &&
                  !QVisible(pchart, "SSRQ_tabline"), ...
```

**Failure scenario** (verifiers' corrected version) [CONFIRMED FROM CODE] — `CSSRPanel::HideSheetArea` omits `tab4` from its hand-written list (`ui-panel-4`), so a panel with an evaluation attached that goes compact would leave the Prop tab visible over the candles until the chart grows again. Stage 18 cannot see it in either direction: it asserts only `tab0` and `tabline`, and its panel is created with a NULL port, so no fifth tab is ever created and there is nothing for the missing list entry to leave behind. The regression this file's own stage 43 header documents as already paid for once — "a lone Prop tab further down" — is uncovered on the compact path. One correction: the `tabline` term is **not** vacuous, because the active rail layout draws `tabline` in `DrawActions`.

**Why** [CONFIRMED FROM CODE] — The removal loop that would sweep `tab4` lives in `DrawRail`/`DrawTabs`, and `Render` skips both under `if(!m_compact)`.

**Verifiers** — Both halves check out.

**Fix** [RECOMMENDATION] — Loop the assertion over `SSR_TAB_MAX` (`for(int t = 0; t < SSR_TAB_MAX; t++) all &= !QVisible(pchart, "SSRQ_tab" + IntegerToString(t));`) and build this stage's panel with the same port stage 38 uses, so an evaluation exists and the fifth tab is drawn. Then the QA side catches `ui-panel-4` the moment `ui-panel-3` is fixed.

##### `qa-smoke-4` — LOW — stage 22d reports two PASSes for lines that were never drawn

**File:** `SSR_QA_Smoke.mq5:2316` · **Category:** zero-empty

```mql5
         int first  = cl.Draw(GetPointer(cal));
         int second = cl.Draw(GetPointer(cal));
         Check("drawing twice draws each line once",
               second == 0 && first == cal.Count(), ...
         Check("and clearing takes them all back",
               cl.Clear() == first && ...
```

**Failure scenario** (verifiers' corrected version) [CONFIRMED FROM CODE] — 22d has no non-empty-calendar guard: the `else` block closes at 2306, so it runs whether or not `cal.Load()` succeeded. On any terminal or window where `cal.Count() == 0` (no calendar published, or a quiet window with `Available()` true) `Draw` returns 0 without creating anything and `Clear` returns 0, so both conditions reduce to `0 == 0` and two PASSes are counted for idempotence and cleanup that nothing exercised. The file holds itself to the opposite standard four lines above — "a stage that quietly passed because there was nothing to test would be the most misleading line in the report" — and 22c acts on it with a `Note`. The printed details do carry the zeros, so a careful reader can see the vacuity; the pass total cannot.

**Why** [CONFIRMED FROM CODE] — Structurally unguarded, unlike 22b and 22c.

**Verifiers** — Structure verified.

**Fix** [RECOMMENDATION] — Guard it the way 22c does: `if(cal.Count() == 0) Note("22d", "no calendar events in this window - idempotence not exercised"); else { …existing checks… }`. `Note()` exists for exactly this, and the pass count then tells the truth.

##### `qa-smoke-9` — LOW — three stages drive real panels outside the `panel.ini` stash window

**File:** `SSR_QA_Smoke.mq5:4194` · **Category:** object-lifecycle

```mql5
         pp.Dispatch("tab4");
         pp.Render();
```

**Failure scenario** (verifiers' corrected version) [CONFIRMED FROM CODE] — `Stash(SSR_PANEL_FILE)` covers 1344-1886 and 4595-4742. Outside those windows stage 38 dispatches "tab4" (4194), stage 39 dispatches "tab1" (4400) and sends `SSR_VK_P` twice (4446, 4558), and stage 42 dispatches "tab2" (5095). `Dispatch`'s tab branch calls `SavePlace()` on any tab change and `SSR_CMD_PANEL_SIZE` does the same; `SavePlace` is live because `Create()` called `RestorePlace()`. So a finished run leaves `MQL5\Files\SSReplay\panel.ini` holding `tab=2` instead of the user's chosen tab, and reports PASS throughout — breaking the rule the file opens with ("A TEST MUST NOT EAT THE USER'S SETTINGS … and told them PASS while doing it"). One more field is at risk than the finder names: 4558 sits inside the `else` taken only when the chart is tall enough, while 4446 is unconditional, so on a short chart the panel-size wish is toggled an **odd** number of times and the user's `pro` preference is persisted inverted as well.

**Why** [CONFIRMED FROM CODE] — Every one of those writes reaches the real file.

**Verifiers** — Every link verified, including the odd-toggle case.

**Fix** [RECOMMENDATION] — Stash once around the whole panel-driving range: move the `Stash(SSR_PANEL_FILE)` to just before stage 17 and the `Unstash` to after stage 42, deleting the inner pair. That is two line moves and it covers every present and future panel stage — which a per-stage stash does not.

##### `qa-smoke-10` — LOW — `SSR_Z_Cleanup` closes the chart of any broker symbol starting with SSR

**File:** `SSR_Z_Cleanup.mq5:44` · **Category:** broker-symbol

```mql5
      if(StringFind(s, "SSR") == 0 || StringFind(s, ".SSR") >= 0)
        {
         ChartClose(id);
         closed++;
        }
```

**Failure scenario** [CONFIRMED FROM CODE] — The first test matches any symbol name **beginning** with the three letters SSR, not just the fifteen spike symbols the script owns. SSRM is a live exchange ticker (SSR Mining Inc.) carried by brokers offering share CFDs; SSRT, SSRN and similar exist. A user with an SSRM chart open who runs the cleanup after a test session loses that chart with no warning, and the script counts it among its own as "charts closed=1".

**Why** [CONFIRMED FROM CODE] — Both sets are already addressable precisely: the spike symbols are enumerated in `g_syms[]` (15-17) and the product's own names are recognised by `SSRIsReplaySymbol` / the `.SSR` suffix. The two symbol-DELETE loops in the same file are correctly narrow — 71 requires `.SSR`, 85 walks `g_syms[]` by exact name — and `CustomSymbolDelete` cannot touch a broker symbol anyway, so the chart loop is the only place the script acts on a name it does not own.

**Verifiers** — Traced; the asymmetry with the delete loops is the argument.

**Fix** [RECOMMENDATION] — Make the chart loop agree with the delete loops: close a chart only when `StringFind(s, ".SSR") >= 0` **or** the symbol is a member of `g_syms[]` by exact match. Two conditions, and the script can no longer touch a name it does not own — which for a cleanup script is the whole of its contract.

##### `qa-smoke-12` — LOW — `SSR_Z_Gaps` can report more than 100 % present, and `InpMinRun=0` turns every bar into a hole

**File:** `SSR_Z_Gaps.mq5:52` · **Category:** boundary

```mql5
   int span = (int)((InpTo - InpFrom) / 60);
   PrintFormat("  %d bars across %d minutes (%.1f%% present)",
               n, span, span > 0 ? 100.0 * n / span : 0.0);
...
      if(gap < InpMinRun)
         continue;
```

**Failure scenario** [CONFIRMED FROM CODE] — `CopyRates` with a start/stop pair is inclusive of both ends (the repo relies on that inclusivity elsewhere and compensates with +1 ms), so the default 11:00..12:00 returns 61 bars against a span computed as 60 minutes and the script prints "61 bars across 60 minutes (101.7% present)". This script is the arbiter of whether missing candles are the broker's fault, and a coverage figure above 100 % undermines the one number the reader is asked to trust. Separately, `InpMinRun` is unclamped: set it to 0 and every consecutive pair has `gap == 0 >= 0`, so the script reports `n-1` "holes", prints twenty lines reading "HOLE 0 minute(s) missing after …", and concludes "A replay crossing these will show the clock moving with no new candle" about a range with no holes at all.

**Why** [CONFIRMED FROM CODE] — `span` counts intervals while `n` counts bars over an inclusive range, so `n == span + 1` on a complete range; the gap filter has no lower bound, and the input's own comment ("at least this many minutes") does not describe 0 as a value.

**Verifiers** — Both halves check out in source.

**Fix** [RECOMMENDATION] — `int span = (int)((InpTo - InpFrom) / 60) + 1;` and `int min_run = MathMax(1, InpMinRun);` at the top of `OnStart`, used in place of the input. Two lines, and both numbers the script exists to report become trustworthy.

#### C.6.16 Spike and probe programs

##### `spikes-audits-30` — LOW — the UIJitter probe uses its window input unclamped

**File:** `SSR_Probe_UIJitter.mq5:66` · **Category:** input-validation

```mql5
g_samp[g_head] = jitter_ms;
g_head = (g_head + 1) % InpWindow;
if(g_count < InpWindow) g_count++;
```

**Failure scenario** (verifiers' corrected version) [CONFIRMED FROM CODE] — `InpWindow` is used unclamped as an array size (34) and as a modulus (66). With `InpWindow=0` — a plausible slip when someone wants no history — the first `OnTimer`'s `g_samp[0]` write is an **array-out-of-range critical error** that kills the indicator before the modulus runs; with a negative value `ArrayResize` fails, the buffer stays zero-length and the same out-of-range write occurs. So there is no division by zero, contrary to the finder: the write dies first. The probe is the instrument three other spikes declare their results meaningless without, so it failing on attach is a silent loss of the responsiveness half of every throughput conclusion. Misuse-only.

**Why** [CONFIRMED FROM CODE] — `Report()`'s only guard is `g_count < 5`, downstream of the fault. Compare `CSSRTickSynthesizer::SetTicksPerBar`, where the product clamps the analogous input: `m_ticks_per_bar = (n < 4 ? 4 : n)`.

**Verifiers** — Whole path traced; failure mode corrected.

**Fix** [RECOMMENDATION] — Clamp in `OnInit` the way the product does: `int win = MathMax(10, InpWindow);` stored in a global and used for both the resize and the modulus, plus the same treatment for `InpPeriodMs` (`MathMax(10, …)`) before `EventSetMillisecondTimer`. Four lines, and the probe cannot be killed by a typo.

##### `spikes-audits-17` — LOW — A1 attributes any create refusal to name length

**File:** `SSR_A1_SymbolLifecycle.mq5:164` · **Category:** zero-empty

```mql5
for(int len = 4; len <= 64; len++)
  {
   string probe = "";
   for(int i = 0; i < len; i++)
      probe += "A";
   if(CustomSymbolCreate(probe, "SSReplay\\Spike\\len"))
```

**Failure scenario** (verifiers' corrected version) [CONFIRMED FROM CODE] — The loop breaks on the first `CustomSymbolCreate` that returns false and publishes the last success as `max_symbol_name_length` — the number said to drive the `<SRC>.SSR<slot>` naming convention. Any other refusal reason (5304 name already exists from an interrupted earlier run, a custom-symbol count ceiling, a locked bases folder) is recorded as a name-length ceiling, and `name_len_usable` can FAIL with no diagnosis: `ResetLastError()` is called at 169 and `GetLastError()` is **never read**, the else branch being a bare `break`. Residue is a lesser concern than the finder claimed: the probes are unselected and chart-free, so the unchecked delete at 173 normally succeeds, and `SSR_Z_Cleanup.mq5:95-100` sweeps them.

**Why** [CONFIRMED FROM CODE] — `SSR_DropSymbol`, which the same file uses twice, deselects, pauses, retries and logs by name — this loop has none of that.

**Verifiers** — Traced; residue claim narrowed.

**Fix** [RECOMMENDATION] — Read the error and say which it was: `int err = GetLastError(); SSR_Metric("audit", "name_len_stop_error", err, "code", "why the length probe stopped");` before the break, and skip a name that already exists (`if(err == 5304) { CustomSymbolDelete(probe); continue; }`) so a stale probe cannot masquerade as a ceiling. Use `SSR_DropSymbol` for the cleanup instead of the bare delete, since the kit already handles the retry.

##### `spikes-audits-18` — LOW — B4 turns a missing series into 20,700 days of history

**File:** `SSR_B4_BrokerDataAudit.mq5:41` · **Category:** zero-empty

```mql5
SSR_Metric(sym, "m1_first_local_days_ago",
           (double)(TimeCurrent() - (datetime)first_local) / 86400.0, "days",
           TimeToString((datetime)first_local, TIME_DATE));
...
SSR_Metric(sym, "m1_downloadable_more",
           ((datetime)first_server < (datetime)first_local ? 1 : 0), "bool",
           "Load More History would gain data");
```

**Failure scenario** (verifiers' corrected version) [CONFIRMED FROM CODE] — `first_local`/`first_server` are declared 0 and the three `SeriesInfoInteger` bool returns are all discarded, so a symbol with no local M1 history publishes `m1_first_local_days_ago` ≈ 20,700 days with the note "1970.01.01" — read as 57 years of history — and `m1_downloadable_more = 0` ("Load More History would gain data" false) because `0 < 0` is false, when the correct answer is that **everything** is downloadable. B4's whole purpose is to decide whether full-tick fidelity is fiction at this broker, so an inverted history figure changes a roadmap decision. Scope is narrower than the claim implies: it is a Tier-B audit metric read by the author, and the adjacent `m1_bars_local = 0` and `copyrates_week "NOT MEASURED"` notes partially contradict the absurd figure in the same report.

**Why** [CONFIRMED FROM CODE] — The subtraction at 42 is unguarded; the only thing upstream is an unchecked `CopyRates` plus `SSR_WaitSeries`, neither of which can manufacture history that is not there.

**Verifiers** — No guard anywhere on the path.

**Fix** [RECOMMENDATION] — Check the returns and report the absence as absence: `bool ok_local = SeriesInfoInteger(sym, PERIOD_M1, SERIES_FIRSTDATE, first_local);` and, when `!ok_local || first_local == 0`, publish `m1_first_local_days_ago = -1` with the note "no local M1 series" and `m1_downloadable_more = 1`. A sentinel a reader cannot mistake for data is the whole difference between an audit and a guess.

##### `spikes-audits-19` — LOW — B4's tick-depth walk samples the same hour of the day at every depth

**File:** `SSR_B4_BrokerDataAudit.mq5:72` · **Category:** boundary

```mql5
for(int d = 1; d <= 2048; d *= 2)
  {
   MqlTick tk[];
   datetime from = now - d * 86400;
   int got = CopyTicksRange(sym, tk, COPY_TICKS_INFO,
                            (long)from * 1000, (long)(from + 3600) * 1000);
```

**Failure scenario** (verifiers' corrected version) [CONFIRMED FROM CODE] — `from = now - d * 86400` with `d` doubling holds the **time of day fixed** for all twelve probes, and the window is only one hour, so every probe interrogates the same clock hour on twelve different days. For an instrument whose session excludes that hour — an index CFD audited at 03:00, a symbol with a daily break — every sample is empty, `misses` reaches the tolerance at `d=8`, the walk breaks with `deepest_days` still 0, and `tick_history_depth = 0` is published for a symbol that may hold years of ticks. The depth is the number that decides whether full-tick fidelity is real. Two mitigations: the consequence depends on the instrument's session actually excluding the audit hour (unverifiable from source), and the zero-depth metric already ships the note "no ticks in any sampled day - check copyticksrange_week_return before concluding". A second inconsistency compounds it: the depth walk uses `COPY_TICKS_INFO` while the ceiling probe uses `COPY_TICKS_ALL`, so the two metrics the note asks the reader to compare are not measuring the same tick population.

**Why** [CONFIRMED FROM CODE] — The author's comment (53-68) diagnoses the right cause — "An empty hour is a closed market, not an absent history" — and applies a tolerance rather than varying the sampled hour.

**Verifiers** — Sampling defect provable; consequence conditional.

**Fix** [RECOMMENDATION] — Probe a day, not an hour, and use one tick flag throughout: `CopyTicksRange(sym, tk, COPY_TICKS_ALL, (long)from*1000, (long)(from + 86400)*1000)` with an early `break` once `got > 0` — a whole day cannot be entirely outside the session for an instrument that trades at all. If the cost of a day of ticks is prohibitive at depth, sample three one-hour windows spread across the day and treat any non-empty one as presence.

##### `spikes-audits-20` — LOW — B4 reports a week's tick count as a call ceiling

**File:** `SSR_B4_BrokerDataAudit.mq5:93` · **Category:** measurement validity

```mql5
//--- practical ceiling of one CopyTicksRange call
int cap = 0;
...
   int got = CopyTicksRange(sym, tk, COPY_TICKS_ALL,
                            (long)from * 1000, (long)now * 1000);
   cap = got;
```

**Failure scenario** (verifiers' corrected version) [CONFIRMED FROM CODE] — `CopyTicksRange` returns how many ticks exist in the requested range, not the largest number it is willing to return. The code issues exactly one call over a fixed seven-day window with no comparison against a known tick count, no second call over a wider window, no truncation test and no `GetLastError()` check — so unless the call happened to be truncated (which B4 cannot detect) `cap` is a measurement of **tick density** published as "the practical ceiling of one CopyTicksRange call" and as the value that "sets the page size for TickSource": a quiet symbol dictates a small page size and a busy one a large page size, for reasons unrelated to any API limit. A failed allocation would publish `cap = -1`. Consumed only by a human reading a spike report and by no shipped code, hence LOW. Cost note: this is a `COPY_TICKS_ALL` fetch of a full week per symbol, up to six symbols, immediately after the comment explaining that fetching a single day of ticks per probe "went from seconds to looking hung".

**Why** [CONFIRMED FROM CODE] — The variable name and the metric note both assert a ceiling the code cannot distinguish from data volume.

**Verifiers** — Source supports the mislabelling; severity LOW.

**Fix** [RECOMMENDATION] — Measure a ceiling by asking for more than any plausible one and checking for truncation: request a range whose expected tick count exceeds `cap` by an order of magnitude, and publish `copyticksrange_truncated_at` only when `got` comes back suspiciously round or below the expected count with `GetLastError() == 0`. If that is not worth the runtime, rename the metric to `ticks_in_last_week` and drop the "sets the page size" note — an honest density figure is more useful than a fictional ceiling.

##### `spikes-audits-14` — LOW — C3's torn-read test runs writer and reader in one thread

**File:** `SSR_C3_IpcChannel.mq5:82` · **Category:** measurement validity (finder's "event-handling" is wrong — verifiers' correction)

```mql5
GlobalVariableSet("SSR.c3.cmd.a1", (double)(i * 7));
GlobalVariableSet("SSR.c3.cmd.a2", (double)(i * 13));
GlobalVariableSet("SSR.c3.cmd.a3", (double)(i * 29));
GlobalVariableSet("SSR.c3.cmd.seq", (double)i);   // published last
//--- reader side
double seq = GlobalVariableGet("SSR.c3.cmd.seq");
```

**Failure scenario** [CONFIRMED FROM CODE] — The whole "race" test is one `for` loop inside `OnStart`: four writes then three reads, same iteration, same thread, no `Sleep`, no second program, no timer, no indicator or service. `seq` always equals `i` and `a1/a2/a3` always equal `i*7/13/29`, so `torn++` is unreachable unless `GlobalVariableSet`/`Get` corrupts data within one thread — which section 1 of the same spike already tests separately. The verdict `seq_last_protocol_safe` therefore passes on any terminal and would pass with the seq-last discipline removed or the writes reordered. The claim it certifies — the channel is "fast, lossless and race-free", and "the seq-last protocol must never expose a half-written command" — requires a second program reading while the first writes, which the spike suite never creates (C1 and C2 each run alone). No effect on shipped code.

**Why** [CONFIRMED FROM CODE] — Sequential execution makes the predicate structurally true.

**Verifiers** — Traced in full; category corrected and severity lowered.

**Fix** [RECOMMENDATION] — Make it two programs, which the suite already has the shapes for: keep the writer in this script and move the reader into a small indicator (or reuse the C3 client side) that polls the four variables on a millisecond timer and counts inconsistencies, publishing its own verdict. Until that exists, replace the verdict with a `Note` saying the protocol is asserted single-threaded only — a spike that claims a concurrency property it cannot observe is worse than one that admits the gap.

##### `spikes-audits-15` — LOW — C4's `timecurrent_is_unsafe` verdict is a tautology

**File:** `SSR_C4_ReplayClock.mq5:120` · **Category:** timer

```mql5
SSR_Verdict("timecurrent_is_unsafe", (long)tc != sym_t, "differs from replay clock",
            StringFormat("tc=%s sym=%s", TimeToString(tc), TimeToString((datetime)sym_t)),
            "confirms the rule: never use TimeCurrent in replay logic");
```

**Failure scenario** (verifiers' corrected version) [CONFIRMED FROM CODE] — `sym_t` is the replay symbol's `SYMBOL_TIME` just stamped at `InpStart` (2024) and `tc` is the live server time, so the verdict is "two clocks read differently at one instant": it cannot fail for any realistic input and would pass in a world where `TimeCurrent` were perfectly safe. It does not test the counter-claim its header states — that other Market Watch symbols drag `TimeCurrent` forward — and the supporting metric `symbols_ahead_of_replay` counts every symbol whose `SYMBOL_TIME` exceeds the 2024 base, i.e. every symbol quoted since then, closed markets included. (Note "InpStart is required to be in the past" is only an input comment, not an enforced guard; the tautology holds anyway because `tc` would have to equal the injected second exactly.) Separately `CustomTicksAdd`'s return is discarded at 70, so a wholesale tick rejection is indistinguishable from a genuine "SYMBOL_TIME does not follow injected ticks" failure — but it does **not** produce a false green: `bad_sec` would be 1000 and `symbol_time_equals_injected` would FAIL loudly. So the cost of the missing acceptance check is diagnostic ambiguity.

**Why** [CONFIRMED FROM CODE] — `SSR_SpikeKit.mqh:351-364` makes checking acceptance the suite's first rule; line 70 is a bare call.

**Verifiers** — Both halves checked; the masked-pass claim refuted.

**Fix** [RECOMMENDATION] — Assert the mechanism, not the difference: after injecting, record `TimeCurrent()` twice a second apart while a live symbol ticks and verify it **advances** while the replay symbol's `SYMBOL_TIME` does not — that is the property the rule rests on. And capture the acceptance: `int acc = CustomTicksAdd(InpTest, tk); SSR_Verdict("ticks_accepted", acc == ArraySize(tk), …)` so a rejection names itself.

##### `spikes-audits-11` — LOW — D1 computes throughput from bars requested, not bars accepted

**File:** `SSR_D1_SeedPerformance.mq5:101` · **Category:** boundary

```mql5
SSR_Metric(c, "bars_per_sec", (t_total > 0 ? total / t_total : 0), "bars/s",
           "write + readable - this is the number the user waits for");
SSR_Metric(c, "write_call_bars_per_sec",
           (t_write > 0 ? total / (t_write / 1000.0) : 0), "bars/s",
           "WRITE CEILING ONLY - excludes the series build");
```

**Failure scenario** (verifiers' corrected version) [CONFIRMED FROM CODE] — Both rates divide `total` (bars **requested**) rather than `written` (bars **accepted**, accumulated only for chunks where `CustomRatesUpdate` returned > 0, so a −1 chunk is silently skipped), and `SeedCase` issues no verdict comparing them — so a partially-rejected seed still publishes full throughput while `bars_written` records the truth one row away. `SSR_RateMetric`'s hardcoded "ticks/s" unit means the kit's `SSR_Rate` shortfall guard cannot be reused for a bar rate. **The finder's claim that A2 has the same defect is wrong**: `SSR_A2_RatesAndAggregation.mq5` asserts it (`SSR_Verdict("rates_written", written == n, …)`) and divides `written`, not `n` — do not repeat that claim.

**Why** [CONFIRMED FROM CODE] — `SeedCase` records eleven metrics and zero verdicts.

**Verifiers** — D1 half provable; the A2 half refuted.

**Fix** [RECOMMENDATION] — Divide `written` in both rates and assert the equality once: `SSR_Verdict("bars_accepted", written == total, IntegerToString(total), IntegerToString(written), "the terminal took every bar")`. Then generalise the kit: give `SSR_RateMetric` a `unit` parameter so a bar rate can route through `SSR_Rate` and inherit its shortfall guard, which is what the guard was added for.

##### `spikes-audits-13` — LOW — D1 prints its PASS gate rather than asserting it

**File:** `SSR_D1_SeedPerformance.mq5:161` · **Category:** measurement validity

```mql5
Print("[D1] PASS gate: 100k bars in <= 20s, 500k in <= 120s,");
Print("[D1] and ui_jitter_p95 <= 500ms from the UIJitter probe.");
```

**Failure scenario** [CONFIRMED FROM CODE] — `grep -c SSR_Verdict` on the file returns **1**, and that single call is inside the `if(!SSR_MakeSymbol(...))` early-return branch — so on every successful run D1 emits **zero** verdicts. `SeedCase` has `t_total` per case in hand and records eleven metrics with no assertion; the numeric gate is only printed. `SSR_End` prints "SPIKE PASS" whenever `g_ssr_fail == 0`, so a run where every 100k seed took 60 s ends PASS=0 FAIL=0 SPIKE PASS and writes nothing to `verdicts.csv`. Combined with `spikes-audits-10`, a seed that never became readable reports both the best bars/s **and** a PASS. Every other timing spike encodes its gate (D2, D4, B2, D3), so D1 and B3 standing outside the pattern is a gap, not a style choice. Confined to developer tooling, with the gate text and per-case timings in the same log.

**Why** [CONFIRMED FROM CODE] — Zero verdicts on the success path.

**Verifiers** — Verified by count and by path.

**Fix** [RECOMMENDATION] — Assert the printed gate: inside `SeedCase`, `SSR_Verdict("seed_" + c + "_within_budget", t_total <= budget_for(total), …)` with the budget derived from the case size (20 s per 100k). Two lines per case, and D1 starts contributing rows to `verdicts.csv` like its siblings. Add `SPIKE INCONCLUSIVE` to `SSR_End` (see `spikes-audits-12`) so a zero-verdict run can never read as a pass again.

##### `spikes-audits-22` — LOW — C2's documented procedure stops the service before its own gate is satisfied

**File:** `SSR_C2_ServicePersistence.mq5:121` · **Category:** measurement validity

```mql5
SSR_Verdict("survived_full_run", uptime_s >= InpRunSec * 0.95,
            IntegerToString(InpRunSec) + "s",
            StringFormat("%.0fs", uptime_s), "");
```

**Failure scenario** [CONFIRMED FROM CODE] — The header's step-by-step procedure ends with "t+300s stop the service" while `InpRunSec` defaults to 360 and the gate requires `uptime >= 342 s`. An operator who follows the printed instructions exactly gets `IsStopped()` at 300 s, an uptime of 300 s, and a **FAILED** `survived_full_run` — so correct execution of the documented procedure guarantees a failing verdict, and the spike's result cannot be read as evidence either way. The other two verdicts are computed independently and are unaffected, which makes the failure look like a partial result rather than an instruction/default mismatch.

**Why** [CONFIRMED FROM CODE] — The loop is `while(!IsStopped())` with an internal break only at `uptime >= InpRunSec*1000`, so an operator stop exits early and `uptime_s` is the real elapsed time.

**Verifiers** — Arithmetic and control flow both check out.

**Fix** [RECOMMENDATION] — Make the two agree in the direction that keeps the gate meaningful: change the header to "t+400s stop the service" (comfortably past 360), or set `InpRunSec = 280` so a 300 s stop clears 0.95×280. Better, print the instruction from the input at start-up — `PrintFormat("[C2] run for %d s, then stop the service", InpRunSec)` — so the procedure cannot drift from the default again.

#### C.6.17 Tooling - `tools/ssr_audit.py`

##### `spikes-audits-29` — LOW — A9 cannot see a duplicated pointer-returning method

**File:** `tools/ssr_audit.py:425` · **Category:** audit coverage

```python
METHOD_DEF = re.compile(r'^\s*(?:virtual\s+|static\s+|const\s+)*'
                        r'[A-Za-z_][\w:]*\s*[\*&]?\s+'
                        r'([A-Za-z_]\w*)\s*\(([^)]*)\)')
```

**Failure scenario** (verifiers' corrected version) [CONFIRMED FROM CODE] — The mandatory `\s+` after the optional `*` means the codebase's own pointer style — `CSSRBarProvider *Bars(void)`, star hugging the name — never matches (23 such declarations exist across the tree). A method of that shape defined twice in one class produces MetaEditor's "member function already defined" and A9 stays silent: precisely the class of patch accident A9 was written to catch. The same fix was already made once in `DECL_METHOD`, whose comment records it — "the star hugs the NAME in this codebase … so whitespace after it must be optional … Three false positives said so immediately" — and `METHOD_DEF` was not updated. `METHOD_DEF`'s argument group `([^)]*)` also stops at the first `)`, so a default argument containing parentheses truncates the key. One sub-claim is **wrong**: A9's class-scope bookkeeping is unaffected — scope is tracked purely by per-line brace counting and `CLASS_HEAD`, never by `METHOD_DEF`, so duplicates of other methods after an unparsed declaration are still detected.

**Why** [CONFIRMED FROM CODE] — Verified by running the regex against both spellings.

**Verifiers** — Primary claim confirmed; the scope-corruption sub-claim refuted.

**Fix** [RECOMMENDATION] — Copy `DECL_METHOD`'s pattern: `r'[A-Za-z_][\w:]*\s*[\*&]?\s*'` (trailing `\s*`, not `\s+`), which matches both spellings. For the argument key, use a balanced scan to the matching paren (or simply count arguments by splitting on top-level commas) so a default argument with parentheses does not truncate it. Then add a self-test: assert the regex matches the 23 known pointer declarations, so the two patterns cannot diverge again.

##### `spikes-audits-28` — LOW — A14 omits four of the text-drawing helpers A19 knows about

**File:** `tools/ssr_audit.py:894` · **Category:** string-length

```python
WIDGET_TEXT = (("Label", 3), ("Button", 5), ("ButtonC", 5), ("Edit", 5))
```

**Failure scenario** (verifiers' corrected version) [CONFIRMED FROM CODE] — The two tables sit in the same file and disagree: `WIDGET_TEXT` (894) has four entries while `SSR_DRAW_TEXT_ARG` (1274) has eight. A literal over 63 characters passed as the text of `Chip()`, `Group()` or `Toast()` is therefore never measured, although the 63-character cut is the defect class this project has hit at least five times (`ui-dialogs-4`, `ui-dialogs-5`, `ui-port-session-7`, `ui-port-session-8`, `chart-7`). Two corrections: there are **12** Chip/Group/Toast call sites today (11 in `SSR_Panel.mqh`, 1 in `SSR_RevealCard.mqh`), not 2 — every one passes `T(SSR_S_...)`, so the gap is latent; and "Text" appears in A19's table but no `Text()` widget exists in `SSR_Widgets.mqh`, so only Chip, Group and Toast are real missing helpers. A14 also has no vacuous-pass guard of the kind A19 carries, so a future signature change that shifted the text index would make it read the wrong argument everywhere and report success — and it reads `raw = FILES[path]` rather than the decommented view, so it measures widget calls inside comments as if they were code.

**Why** [CONFIRMED FROM CODE] — Chip's text is argument 3, Group's legend 5, Toast's text 4; all three reach `OBJPROP_TEXT` through an internal `Label()` call whose argument is a variable and which has no `.` receiver, so A14's `r'\.%s\s*\('` pattern cannot see it at either end.

**Verifiers** — Signatures checked one by one.

**Fix** [RECOMMENDATION] — Make the two tables one: define the positions once and have both A14 and A19 import it, adding Chip/Group/Toast (and dropping the non-existent `Text`). Give A14 a vacuous-pass guard — assert it measured at least N call sites — and switch it to the decommented view. One shared table removes the whole class of drift, which is the same argument `ui-plumbing-3` makes about the key lists.

##### `spikes-audits-26` — LOW — A19's translation-length check never runs

**File:** `tools/ssr_audit.py:1429` · **Category:** string-length

```python
langdir = os.path.join(ROOT, "MQL5", "Files", "SSReplay", "lang")
if os.path.isdir(langdir):
```

**Failure scenario** [CONFIRMED FROM CODE] — `ROOT` already points at the `MQL5` directory, so `langdir` resolves to `<repo>/MQL5/MQL5/Files/SSReplay/lang`, which does not exist; `isdir` returns False and the whole loop (1430-1447) is skipped. The only check that any translated string fits MetaTrader's 63-character draw limit is dead code and passes silently — the precise vacuous pass A18 and A19's own guards were written to prevent, and line 1446 even tells the reader "this is the only place it is checked". A Persian string of 64+ characters would ship with its end invisible and no audit would say so. None of `fa.txt`'s 190 key=value pairs currently exceeds 63 characters, so the silence is accidental rather than earned — hence LOW.

**Why** [CONFIRMED FROM CODE] — Verified by computing both paths; the real directory is `<repo>/MQL5/Files/SSReplay/lang`.

**Verifiers** — Verified by computation.

**Fix** [RECOMMENDATION] — `langdir = os.path.join(ROOT, "Files", "SSReplay", "lang")`, plus the guard this class of bug needs: `else: fail("A19", "language directory not found at " + langdir)` so a wrong path reports itself instead of passing. Then extend the check to cover the strings `chart-12` and `ui-plumbing-1` add to the catalogue.

##### `spikes-audits-27` — LOW — A20's regex matches one exact function shape

**File:** `tools/ssr_audit.py:1518` · **Category:** redraw

```python
want = re.compile(r"^   void\s+(Render|Repaint)\(void\)\s*$", re.M)
```

**Failure scenario** [CONFIRMED FROM CODE] — The pattern demands exactly three leading spaces, the names Render or Repaint, a literal `(void)` list and nothing else on the line, so it matches 8 functions in 7 Ui files and **nothing** in `SSR_FirstRun.mqh` or `SSR_KeyCard.mqh`, whose drawing surfaces are `bool Show(const long chart_id)` and which each build a full card of six Rect/Label calls. A20 therefore cannot enforce its rule there; both happen to call `ChartRedraw` today, so the silence is luck — delete either call and A20 stays green while the regression it exists for (a card drawn on a paused chart that never repaints) returns. A20 is also limited to paths containing `/Ui/`, so drawing code in the Expert and the Chart layer is out of scope entirely.

**Why** [CONFIRMED FROM CODE] — The docstring states the intent the pattern narrows: "Checked per RENDER FUNCTION, not per file: a file whose Render is silent still passes a grep for ChartRedraw anywhere in it."

**Verifiers** — Pattern applied across the layer; counts confirmed.

**Fix** [RECOMMENDATION] — Widen the pattern to any method that contains widget draw calls: find every function body in a Ui file that calls `m_w.` at least twice and require a `ChartRedraw` in the same body. That is a small brace-matching walk rather than a line regex, it covers `Show()` and anything added later, and it lets the `/Ui/` restriction be lifted to the Chart layer, where `chart-2`'s missing `Redraw` would have been caught.

### C.7 IMPROVEMENT (18)

Not wrong output: dead code, stale comments, instruments that cannot report, and one-line hygiene. Each is cheap and each removes a trap for the next reader. [CONFIRMED FROM CODE]

#### C.7.1 Core engine - `MQL5/Include/SSReplay/Core`

##### `core-engine-11` — IMPROVEMENT — four separate nits in the controller

**File:** `SSR_ReplayController.mqh:1707` · **Category:** hygiene

```mql5
  //  The cursor goes too. Without it a resumed session would re-emit
  //  bars the sink already holds, or skip ones it does not.
```

**Failure scenario** (verifiers' corrected version — two of four sub-claims adjusted) [CONFIRMED FROM CODE] — **(a)** The comment at 1707-1708 misdescribes the mechanism: position is rebuilt by `JumpTo`, not by the saved cursor. (`RestoreFrom` *does* read the saved `bars` at 1856 for the no-fingerprint legacy check; it is `emitted` and `ticks`, written at 1725-1726, that no restore path consumes.) **(b)** `#define SSR_BAR_READ_CEILING 8192` (42) is referenced nowhere, and the constructor uses a bare `8192` literal instead (547). **(c)** `owed_msc = hi - lo = N*60000 - r - 2`, so from xx:59.999 a 10-bar step owes 539,999 ms, not 599,999; the 599,999 near-miss occurs on the **first** step after `Load`, where `RewindTo(start)` leaves `lo == start`. Either way `StepBars(10)` can never reach `SSR_BULK_THRESHOLD_MSC` = 600,000 while an 11-bar step almost always does — so PgDn is never a bulk moment by accident of arithmetic. **(d)** In `CSSRFidelityPolicy::Decide` the NO_TICK_DATA branch is an `if/else if`, so a FULL_TICK request that degrades to SYNTHETIC short-circuits and ignores the bulk rule for the whole session, running a large owed window at 8 ticks/bar instead of 1. The harm is narrower than claimed: a long catch-up does not traverse this path (`JumpForward` bulk-writes whole bars and hands `EmitWindow` only the target's partial minute), so it bites on a post-stall pump where `MaxBars` already bounds the work — a fidelity-priority nit, not a burst.

**Why** [CONFIRMED FROM CODE] — Each sub-claim is a separate line or expression, verified independently.

**Verifiers** — Three exactly right, the fourth's conclusion holds on corrected arithmetic.

**Fix** [RECOMMENDATION] — Four small edits, in increasing order of value. Rewrite the comment to say what is actually restored. Delete `SSR_BAR_READ_CEILING` or use it at 547. Express the bulk rule in bar counts — `if(bars_owed >= SSR_BULK_THRESHOLD_BARS)` with the threshold defined as 10 — so PgDn's status is a decision rather than an off-by-one. And make `Decide`'s branches independent: evaluate the bulk rule first, then the tick-availability demotion, so a degraded FULL_TICK still drops to BAR on a bulk pump.

##### `core-sync-6` — IMPROVEMENT — `DropFrom` leaves holes in the ring without adjusting `m_count`/`m_head`

**File:** `SSR_SnapshotStore.mqh:140` · **Category:** boundary

```mql5
   int               DropFrom(const long msc)
     {
      int dropped = 0;
      for(int i = 0; i < m_count; i++)
        {
         if(m_ring[i].taken_at_msc >= msc)
           { m_ring[i].Init(); dropped++; }
```

**Failure scenario** (verifiers' corrected version) [CONFIRMED FROM CODE] — With the ring full (64 checkpoints = 5h20m of replay) and the user stepping back through the last k, those k slots become `Init()`'d holes but `m_count` stays 64 and `m_head` keeps advancing over the oldest live slots, so the next k checkpoints overwrite the far end while the holes near the head stay empty until the head wraps. `Count()` — surfaced as the panel's "checkpoints" figure — keeps reporting 64, and rewind depth is 64−k until a full wrap. Overstated by the finder: overwriting the oldest entry is normal full-ring behaviour, so the loss versus an ideal implementation is k checkpoints of the oldest history plus the temporary depth reduction, not "5h destroyed". `NearestAtOrBefore` is unaffected (it skips `taken_at <= 0`), which is why this is an IMPROVEMENT.

**Why** [CONFIRMED FROM CODE] — `m_count` is raised only in `Checkpoint` and zeroed in `ClearCheckpoints`; `m_head` is advanced only in `Checkpoint`; `DropFrom` touches neither. `T8.2` tests `DropFrom` with 10 entries (no wrap) and asserts only the dropped count and the newest survivor.

**Verifiers** — Confirmed; magnitude corrected.

**Fix** [RECOMMENDATION] — Entries are written in time order, so the dropped ones are always the newest contiguous run behind the head: after the loop, set `m_count -= dropped;` and rewind `m_head` by `dropped` (modulo the ring size). Two lines, and `Count()` tells the truth while the next checkpoints refill the holes instead of eating the oldest history. Extend `T8.2` to wrap the ring before dropping, which is the case the current test cannot reach.

#### C.7.2 Data layer - `MQL5/Include/SSReplay/Data`

##### `data-11` — IMPROVEMENT — every data-quality number is computed and discarded

**File:** `SSR_Mt5DataSource.mqh:146` · **Category:** instrumentation

```mql5
   string            ToString(void)
     {
      return StringFormat("mt5[%s open=%s ticks=%s %s]",
                          m_symbol, (m_open ? "yes" : "no"),
                          (m_has_ticks ? "yes" : "no"),
                          m_bars.Window().ToString());
     }
```

**Failure scenario** (verifiers' corrected version) [CONFIRMED FROM CODE] — A user reports "some candles are missing in the middle of Tuesday". The information needed to answer already exists: `CSSRBarWindow` ran `ValidateBars` over the exact range (duplicates, out_of_order, micro_gaps, session_gaps, largest_gap_msc) and counted `m_dropped` for every bar `SanitizeBars` removed. None of it reaches the log, the vitals line or the flight recorder: `ReportInto` has no caller, `Dropped()` has no caller, `CSSRMt5DataSource::ToString` has no caller, and `micro_gaps`/`session_gaps`/`duplicates` appear nowhere in Experts, Ui, Common or Core outside the validator. The author, who cannot run this on a terminal, has no way to learn that bars were silently dropped or that the range was gappy — which is exactly why `data-1` and its siblings fail silently. One correction: the window's own `ToString`, the string carrying `dropped=`, **is** reachable from `SSR_T2_DataEngine.mq5:256-258`; what is unreachable is every host-side route.

**Why** [CONFIRMED FROM CODE] — `SSR_BarWindow.mqh:53` says the instrumentation exists "so Phase 7 tunes with numbers not opinions" — this is unfinished wiring, not an absent idea.

**Verifiers** — Dead at the host end, confirmed by repo-wide grep.

**Fix** [RECOMMENDATION] — Wire the report into the two surfaces that already exist. At the end of `Load`, call `m_bars.Window().ReportInto(rep)` and `Print` a single line when anything is non-zero: "[data] range had %d duplicates, %d out of order, %d micro gaps, %d dropped; widest gap %s". And add `dropped` and `largest_gap_msc` as columns to the flight recorder, which is the artefact the author actually receives. Two hooks, no new machinery, and the whole silent-failure class in this subsystem acquires a voice.

#### C.7.3 Trading and risk - `MQL5/Include/SSReplay/Trading`

##### `trading-exec-13` — IMPROVEMENT — auto-pause reasons are English literals with a hard-coded price format

**File:** `SSR_AutoPause.mqh:124` · **Category:** i18n

```mql5
Raise(StringFormat("entry filled - %s %.2f @ %s",
                   SSROrderName(p.type), p.volume_initial,
                   DoubleToString(p.open_price, 5)));
```

**Failure scenario** (verifiers' corrected version) [CONFIRMED FROM CODE] — Every `Raise()` argument in `Scan()` is an English literal with no `T()` route (124-126, 137-138, 142, 146, 153), and the text reaches the UI verbatim: auto-pause → controller pause reason → `SSR_GroupPort.mqh:127-128` → `SSR_Panel.mqh:954-955` appends it to a panel label. With `InpLanguage="fa"` an English sentence appears on a translated panel, and the default flags (SL|TP|STOPOUT) make that live out of the box. The hard-coded 5-digit price — "@ 41234.56000" on a 2-digit index — applies only to the entry-filled line and requires `SSR_PAUSE_ON_ENTRY`. A19 does not see any of it because it scans Ui files only.

**Why** [CONFIRMED FROM CODE] — `CSSRTradingEngine::Digits()` exists (1026) and is not used here.

**Verifiers** — Read as quoted; scope of the digits half narrowed.

**Fix** [RECOMMENDATION] — Add the five reasons to the catalogue as format strings (`SSR_S_PAUSE_SL`, `_TP`, `_STOPOUT`, `_ENTRY`, `_PROP`) and build each with `StringFormat(T(...), …)`; pass `m_acct.Digits()` instead of the literal 5. Then widen A19 past `/Ui/` (see `chart-12`) so the next English literal outside the UI layer is caught by the rule that exists for it.

#### C.7.4 UI layer - `MQL5/Include/SSReplay/Ui`

##### `ui-plumbing-5` — IMPROVEMENT — `SSR_Layout.mqh` is dead in production

**File:** `SSR_Layout.mqh:67` · **Category:** rtl

```mql5
int SSRLead(const SSRFrame &f, const int off, const int width)
  {
   if(!f.rtl)
      return f.x + f.pad + off;
   return f.x + f.w - f.pad - off - width;
  }
```

**Failure scenario** [CONFIRMED FROM CODE] — Flipping `SSRFrame.rtl` changes nothing on screen: a grep over every `.mqh` and `.mq5` finds `SSRLead`/`SSRTrail`/`SSRCentre`/`SSRInner`/`SSRColW`/`SSRColX`/`SSRFrame`/`SSRRows` only in `SSR_Layout.mqh` itself, in `SSR_Panel.mqh:44` (a bare `#include` that uses nothing), and in `SSR_QA_Smoke.mq5:3354-3386` (the only caller, and the only place `rtl=true` is ever passed); `SSRCentre` and `SSRInner` have no call site at all. Mirroring the panel therefore still means rewriting inline pixel arithmetic by hand in eight UI files. The file's header states the constraint it was built to impose — "position through here, never by hand - and this file is that promise made concrete" — and the constraint was never adopted: every UI file computes x positions inline (`SSR_ReviewCard.mqh:112-204` is a full page of `m_x+12` / `m_x+SSR_RV_W-96` arithmetic). Nothing misbehaves at runtime; the cost is that the RTL phase will rewrite exactly what the helpers were built to prevent.

**Why** [CONFIRMED FROM CODE] — The smoke test's own note records the file as "written and deliberately OFF", which is true of the flag but understates it: the helpers are uncalled.

**Verifiers** — Grep is decisive.

**Fix** [RECOMMENDATION] — Adopt it incrementally, starting where the win is largest and the risk smallest: convert `CSSRReviewCard` and `CSSRKeyCard` (two self-contained cards, no shared coordinates) to build an `SSRFrame` in their draw function and position through `SSRLead`/`SSRColX`. That proves the helpers against real layout, gives the RTL phase a worked example, and makes an audit rule possible ("no `m_x +` literal arithmetic in a converted file"). If RTL is off the roadmap, delete the file and the `#include` rather than leave a promise the code does not keep.

##### `ui-port-session-16` — IMPROVEMENT — `data_mode` is on the wire, set by nobody and read by nobody

**File:** `SSR_ReplayPort.mqh:54` · **Category:** zero-empty

```mql5
   ENUM_SSR_DATA_MODE data_mode;
```

**Failure scenario** [CONFIRMED FROM CODE] — `Init()` sets `data_mode = SSR_DATA_MEMORY` (250) and no `ReadState` implementation ever assigns it, while no panel or dialog reads it — so the field permanently reports in-memory. It is not merely unset but provably **inconsistent** with the engine: production calls `SetDataMode(SSR_DATA_BROKER)` at `SSReplayStandalone.mq5:499` and `:1150`, and the controller writes the real value into the session file (1728). `SSRUiState` is the IPC contract, so the first consumer to trust the field — the promised Ipc port — will describe a disk-backed session as in-memory.

**Why** [CONFIRMED FROM CODE] — Grep across the tree: engine field, `SetDataMode`, the session-file write, and in the UI layer only the declaration and the `Init`.

**Verifiers** — Every occurrence traced.

**Fix** [RECOMMENDATION] — One line beside the fidelity read: `out.data_mode = c.DataMode();` in `CSSRGroupPort::ReadState` (110-112), adding the trivial accessor if it does not exist. Or delete the field from the struct. Either is fine; leaving a wire field that is always a default is the one option that guarantees a future consumer is wrong.

##### `ui-dialogs-16` — IMPROVEMENT — review-card measure rows latch and nothing clears them

**File:** `SSR_ReviewCard.mqh:162` · **Category:** event-handling

```mql5
      m_w.List("m", m_x + 12, ly, SSR_RV_W - 24, SSR_RV_ROW_H,
               lines, m_first, SSR_RV_SHOWN, -1);
```

**Failure scenario** (verifiers' corrected version) [CONFIRMED FROM CODE] — Click any of the 12 visible measure rows: MetaTrader latches the button down, the card polls only `up`/`down`/`stmt`/`close`, and nothing clears `OBJPROP_STATE`. On a card whose whole purpose is to be read, a row that looks selected but is not is a false affordance. The finder's escape hatch is **wrong**: paging does not clear it — `Page()` + `Render()` only rewrite XDISTANCE and text through `ButtonC`, which deliberately never touches `OBJPROP_STATE` ("THE PRESSED STATE IS NOT CLEARED HERE ANY MORE", `SSR_Widgets.mqh:388-394`) — so the stale pressed look survives every repaint and every page turn for the life of the card.

**Why** [CONFIRMED FROM CODE] — Only `Pressed()` consumes a latch, and the card never asks about the rows. Nothing else can reach them either: `CSSRPanel::PollClicks` skips objects outside its own `SSRP_` prefix, and the host treats the card as modal.

**Verifiers** — Every possible clearer checked; none exists.

**Fix** [RECOMMENDATION] — Consume the latch and ignore it: in `Poll()`, loop the 12 row ids and call `m_w.Pressed("m" + IntegerToString(i))` discarding the result — `Pressed()` already clears the state, so one loop of twelve cheap reads per poll removes the false affordance. If the rows should never look pressable at all, draw them with `Label` on a `Rect` instead of `Button`, which also saves the latch machinery; the `List` widget would need a non-interactive variant, which `SSR_KeyCard` already effectively is.

##### `ui-plumbing-11` — IMPROVEMENT — the metrics comment is stale in four figures

**File:** `SSR_Theme.mqh:437` · **Category:** boundary

```mql5
//|   caption 23 + clock+progress 32 + transport 27 + speed 33        |
//| + tabs 21 + sheet 222 + status 18 + margin 14 = 390               |
```

**Failure scenario** (verifiers' corrected version) [CONFIRMED FROM CODE] — A designer adding a row reads this block and budgets against a 390 px panel with a 222 px sheet, a 33 px speed row and 14 px of margin. The constants actually built are `SSR_SHEET_H` 186 (449) and `SSR_PANEL_H = (23+32+27+21+21+SSR_SHEET_H+18+8) = 336` (499) — so **four** figures disagree (speed 33 vs 21, sheet 222 vs 186, margin 14 vs 8, total 390 vs 336) while five still match (caption 23, clock+progress 32, transport 27, tabs 21, status 18). A row sized from the comment's 222 px sheet overflows the real one by exactly 36 px, reproducing the v69 failure the same comment block warns about ("a row past its end is drawn over the status bar").

**Why** [CONFIRMED FROM CODE] — `SSR_PANEL_H` was deliberately turned into a compiler-added expression precisely because "the sum above was a comment for eleven builds and the two rows v69 added went straight past the end of it" — and the prose sum above `SSR_SHEET_H` was left at the older numbers, so the file now carries two disagreeing totals: the failure mode it was rewritten to prevent, one comment higher up.

**Verifiers** — Arithmetic verified; agreement count corrected.

**Fix** [RECOMMENDATION] — Do not maintain a second sum. Replace the prose block with the expression itself plus a one-line instruction: "the panel's height is `SSR_PANEL_H` at line 499 — read it there, and add your row's constant to that expression." If a human-readable breakdown is wanted, have the QA smoke print `SSR_PANEL_H` and each component constant once at start-up, so the numbers a designer reads are the numbers the compiler used.

##### `ui-plumbing-8` — IMPROVEMENT — `Label()`'s fingerprint identifies the font by its name length

**File:** `SSR_Widgets.mqh:232` · **Category:** memory

```mql5
      long   fp = Mix(Mix(Mix(Mix(x, y), (long)col), size),
                      (long)StringLen(font));
      if(Same(n, fp, text))
         return true;
```

**Failure scenario** (verifiers' corrected version) [CONFIRMED FROM CODE] — `font` is the one string argument folded into the numeric fingerprint instead of being stored, so two equal-length face names are indistinguishable and a font change between them would be skipped. Unreachable in the shipped build and doubly so: `SSR_FONT` and `SSR_FONT_MONO` are the same literal "Tahoma", every `Label`/`Text` call site passes one of those two macros, and no font string literal is passed anywhere (the only other font write bypasses the cache entirely). It stays unreachable even after the theme splits them unless the replacement face happens to have the same name length. A latent cache-key defect with no user-observable effect.

**Why** [CONFIRMED FROM CODE] — `SSR_FONT_MONO` exists only so the two can be split later — "if a terminal ever proves otherwise it is one line to split them again" — and that one line is this defect's trigger.

**Verifiers** — Code fact confirmed, reachability refuted.

**Fix** [RECOMMENDATION] — Store the font the way `text` is stored: add a fourth parallel array (`m_cf[]`) and compare it in `Same()`, or cheaply, fold a real hash of the string rather than its length (`for(int i=0;i<StringLen(font);i++) h = Mix(h, StringGetCharacter(font,i));`). The hash version is two lines and no extra memory, and it makes the split-the-fonts line safe.

##### `ui-plumbing-9` — IMPROVEMENT — two palette tokens are declared and drawn by nothing

**File:** `SSR_Widgets.mqh:492` · **Category:** theme hygiene

```mql5
      return Rect(id + "_th", tx, y - 3, 4, h + 6,
                  SSR_C_THUMB, SSR_C_TRACK_EDGE);
```

**Failure scenario** (verifiers' corrected version) [CONFIRMED FROM CODE] — `SSR_C_THUMB_EDGE` and `SSR_C_TICK` appear only at their three definitions each (once per palette) and are read nowhere; the thumb — the only control either names — is bordered with `SSR_C_TRACK_EDGE`, so in the LIGHT palette a near-black 4 px thumb has two of its four columns painted in the groove's 138-grey. Because no draw site references `SSR_C_THUMB_EDGE`, the contrast table declares no pair for it and A18 blesses two tokens that cannot be seen. There is no runtime defect: two of 51 tokens per palette are dead declarations, and outlining the thumb with the groove's edge colour is a defensible choice (the thumb then continues the groove's own outline). The substance is dead tokens plus an unenforced rule — "the token named for a part is the token that part draws with".

**Why** [CONFIRMED FROM CODE] — A17 forbids colours outside this file, which is satisfied; there is no audit that a declared token is used.

**Verifiers** — Verified exactly, including the 4 px/1 px geometry.

**Fix** [RECOMMENDATION] — Decide and then enforce. Either pass `SSR_C_THUMB_EDGE` at 492-493 and add its contrast pairs to the table, or delete both tokens from all three palettes. Then add the missing audit rule: every `SSR_C_*` defined in `SSR_Theme.mqh` must appear at least once outside it — a five-line check in `ssr_audit.py` that would have reported this, and reports the next one for free.

#### C.7.5 Integration - `MQL5/Include/SSReplay/Integration`

##### `strategy-integration-report-15` — IMPROVEMENT — `SSR_CMD_SPEED` reports success for a value the clock rewrote

**File:** `SSR_Publisher.mqh:283` · **Category:** input-validation

```mql5
         case SSR_CMD_SPEED:
           {
            m_group.SetSpeedX100((long)a1);
            return SSR_RC_OK;
           }
```

**Failure scenario** (verifiers' corrected version) [CONFIRMED FROM CODE] — The case returns an unconditional `SSR_RC_OK` with no bounds test, so a client sending 0 or a negative x100 is told the command succeeded while the clock has clamped the value to 1 (0.01×). The finder's upper-bound half is **wrong**: `SetSpeedX100` has no upper clamp (`SSR_ReplayClock.mqh:78` is `speed_x100 = (s < 1 ? 1 : s);`) and `SSR_SPEED_MAX` is only the UI ladder's last stop and a naming threshold, so a request above it is applied verbatim and OK is accurate. The finder's premise that "every other command reports what the engine actually did" is also refuted by the file itself: `SSR_CMD_JUMP` is documented three lines above as clamp-and-succeed, and `SeekTo` unconditionally returns true after clamping — so speed follows an established pattern and no incorrect state results.

**Why** [CONFIRMED FROM CODE] — The lower clamp is silent; the client can notice only by reading back `SSR_GV_SPEED`.

**Verifiers** — Premise refuted, lower-bound half confirmed.

**Fix** [RECOMMENDATION] — Answer with what happened, which costs one read: `m_group.SetSpeedX100((long)a1); Set(SSR_GV_SPEED, (double)m_group.SpeedX100()); return (((long)a1 >= 1) ? SSR_RC_OK : SSR_RC_CLAMPED);` — or, if adding a return code is unwelcome, keep OK and publish the effective speed on the same tick so a client that trusts the answer and one that reads back agree. Apply the same to JUMP, whose clamp is documented but equally silent.

#### C.7.6 Test harness - `MQL5/Scripts/SSReplay/Tests`

##### `tests-b-16` — IMPROVEMENT — T10.8 leaves its exported CSV in the trader's journal folder

**File:** `SSR_T10_Statistics.mq5:533` · **Category:** object-lifecycle

```mql5
      Check("export succeeded", j.ExportCsv("t10", 2), j.LastError());
```

**Failure scenario** (verifiers' corrected version) [CONFIRMED FROM CODE] — `ExportCsv` does `FolderCreate(SSR_JOURNAL_DIR)` and writes `SSReplay\journal\t10.csv` — the same folder real session journals go to — and `grep FileDelete` on the file returns nothing, so a synthetic three-trade CSV with a caveat header sits permanently beside the user's own journals. T12 deletes all six of its files and all three of its sessions; T10 deletes nothing. The finder's "any open-my-latest-journal workflow may pick it up" is speculative — no such picker exists in the source — so the concrete defect is the uncleaned artefact.

**Why** [CONFIRMED FROM CODE] — The section reads the file back, closes it, and ends.

**Verifiers** — Confirmed from both sides.

**Fix** [RECOMMENDATION] — `FileDelete(SSR_JOURNAL_DIR + "\\t10.csv");` after the read-back, matching T12's pattern. Better still, export under a name that cannot be mistaken for a user's (`"__t10_selftest"`), so a failed run that skips the delete still leaves something obviously the suite's.

##### `tests-b-9` — IMPROVEMENT — T12.5's guard can never fail

**File:** `SSR_T12_Session.mq5:445` · **Category:** session-resume

```mql5
      //--- and the file really does not contain them
      Check("no win rate was stored", !r.Select("statistics"));
```

**Failure scenario** [CONFIRMED FROM CODE] — Add `f.Section("stats"); f.SetDouble("win_rate", st.win_rate, 2);` to `CSSRStatsEngine::SaveInto` — exactly the mistake the section names — and T12.5 still passes, because it probes one section name **no writer in the codebase ever uses**: the only session sections written are account, execution, positions, equity, session, settings, stream, bookmarks, panel, presets, setup, and a repo-wide grep for the literal "statistics" yields only this assertion and the observer's `Name()`. So the assertion asserts the absence of a section name nothing writes, instead of the absence of derived keys anywhere in the file.

**Why** [CONFIRMED FROM CODE] — `CSSRStatsEngine::SaveInto` opens with `f.Section("equity")` and writes nothing else.

**Verifiers** — Provable from source; a coverage gap, not a product defect.

**Fix** [RECOMMENDATION] — Assert the absence of the **keys**, across the whole file: after loading, check `!r.HasKeyAnywhere("win_rate") && !r.HasKeyAnywhere("profit_factor") && !r.HasKeyAnywhere("average_r")` (a small helper over the entry arrays the file already holds). That pins the actual invariant — derived statistics are never stored — regardless of what section a future writer chooses.

##### `tests-b-15` — IMPROVEMENT — T13.6's unsupported-timeframe assertion is order-coupled

**File:** `SSR_T13_Strategy.mq5:459` · **Category:** input-validation

```mql5
      Check("and an unsupported timeframe too",
            !host.Add(GetPointer(b), PERIOD_W1));
      Check("named as unsupported",
            StringFind(host.LastError(), "timeframe") >= 0, host.LastError());
```

**Failure scenario** [CONFIRMED FROM CODE] — The strategy handed to the timeframe check is `b`, a second `CSSRRefBreakout` whose `Name()` is the same constant as the `a` registered eleven lines earlier — so **both** refusal reasons apply to this call and only `Add`'s guard order decides which message `LastError` carries. Reorder the guards so the name check runs first (a natural refactor, since it is the more product-specific rule) and `LastError` becomes "two strategies named ref-breakout …": the assertion fails and points at timeframe validation that is still working. Nothing is currently broken.

**Why** [CONFIRMED FROM CODE] — `Add` validates NULL, capacity, timeframe, empty name, duplicate name — in that order.

**Verifiers** — Guard order and name constant both confirmed.

**Fix** [RECOMMENDATION] — Isolate the rule: give the W1 case a fresh strategy with an unused name (a second class, or a `SetName`-able test double) so only the timeframe guard can refuse it. Then the assertion is about one rule, which is what makes it survive a refactor.

##### `tests-b-14` — IMPROVEMENT — T15.5's "cannot trade" assertion pins `Init()`, not the rule

**File:** `SSR_T15_Ux.mq5:336` · **Category:** zero-empty

```mql5
      SSRUiState st;
      Check("nothing to read", !port.ReadState(st));
      Check("cannot trade",   !st.can_trade);
```

**Failure scenario** (verifiers' corrected version) [CONFIRMED FROM CODE] — `st.can_trade` is false because `ReadState` zeroed the struct on entry and then returned early, not because the port judged itself unable to trade: the live assignment `out.can_trade = (m_acct.Bid() > 0.0)` sits inside the `if(m_acct != NULL)` block, unreachable on this path. So any regression in the `can_trade` computation is invisible here, and the panel greys its buttons from exactly this field. The assertion is **not pointless**, though: `CSSRPanel::Render` calls `ReadState` and discards the bool, so the `Init()`-on-entry guarantee is precisely what keeps a refused read from greying nothing — T15.5 pins that contract. What is missing is a separate case with an attached account and no price.

**Why** [CONFIRMED FROM CODE] — `ReadState` opens with `out.Init();` and `Init` sets `can_trade = false`.

**Verifiers** — Confirmed; the contract the assertion does pin is theirs.

**Fix** [RECOMMENDATION] — Keep the line, rename it to "a refused read leaves the struct safe", and add the missing case: attach an account with no bid and assert `ReadState` succeeds while `can_trade` is false, then set a bid and assert it flips. Two extra assertions, and the rule the panel depends on is finally covered.

##### `tests-a-16` — IMPROVEMENT — two sections in T5 are both labelled T5.9

**File:** `SSR_T5_Ui.mq5:289` · **Category:** test hygiene

```mql5
   Section("T5.9  the navigation verbs reach the port");
```

**Failure scenario** [CONFIRMED FROM CODE] — The log prints "--- T5.9 state colours are distinct where meaning differs" (276) and later "--- T5.9 the navigation verbs reach the port" (289). Anyone quoting "T5.9 passed" is ambiguous, and a reader scanning for a gap sees T5.1..T5.9 and concludes the file is complete. Note T5 is not the only offender: `SSR_T10_Statistics.mq5` duplicates T10.3 and T10.5 (outside the finder's stated scope of T1..T8, where T5 is indeed unique).

**Why** [CONFIRMED FROM CODE] — Two literal `Section()` strings with the same number.

**Verifiers** — Verified literally, plus the T10 duplicates.

**Fix** [RECOMMENDATION] — Renumber the second to T5.10 (and T10's duplicates likewise), then make it mechanical: add a check to the suite's own tail — or to `ssr_audit.py` — that the `Section("Tn.m …")` labels in each test file are unique and consecutive. Cheap, and it keeps the log usable as an index.

#### C.7.7 QA scripts - `MQL5/Scripts/SSReplay/QA`

##### `qa-smoke-15` — IMPROVEMENT — stage 12's closed-trade prices are in whole units

**File:** `SSR_QA_Smoke.mq5:1073` · **Category:** broker-symbol

```mql5
         lines.DrawClosed(777, t1 - 600, lpx, t1, lpx + 3.0, true, 0.10, 42.0);
```

**Failure scenario** (verifiers' corrected version) [CONFIRMED FROM CODE] — The exit price is the entry plus **3.0 whole units**: on a 5-digit replay price of ~1.16 that is 4.16, thousands of points off the chart's range. `DrawClosed` rejects only non-positive prices, so the arrow and the connecting line are created and "a closed trade leaves history on the chart" passes — on objects placed off-screen, so the stage cannot observe the property the class's own comment cares about ("the arrows were drawn, correctly placed and the right colours - and at their default size they read as two specks … 'it draws' was true while 'you can see it' was not"). The same block six lines above states the rule and the cost of breaking it — "OFFSETS IN POINTS, NOT IN WHOLE UNITS … three stages failed and named the product" — and duly uses `lpx - 500 * pt`; the `DrawClosed` call seven lines later was not converted, though `pt` is in scope. One naming correction: the trailing `42.0` is `DrawClosed`'s **net** parameter (used for the win/loss colour and the exit tooltip), not an R value.

**Why** [CONFIRMED FROM CODE] — Repeated at 1080.

**Verifiers** — Confirmed; parameter identified.

**Fix** [RECOMMENDATION] — `lines.DrawClosed(777, t1 - 600, lpx, t1, lpx + 300 * pt, true, 0.10, 42.0);` at both sites, and add the assertion the stage is reaching for: that the drawn objects' prices fall inside `ChartGetDouble(CHART_PRICE_MIN/MAX)`. That converts "it draws" into "you can see it", which is the lesson the comment paid for.

##### `qa-smoke-8` — IMPROVEMENT — stage 18's compact assertion re-implements the production expression

**File:** `SSR_QA_Smoke.mq5:1667` · **Category:** boundary

```mql5
         bool compact = pnl.IsCompact();
         Check("the panel picked the mode this chart can hold",
               compact == (pch > 0 && pch < SSR_PANEL_H + 24),
```

**Failure scenario** (verifiers' corrected version) [CONFIRMED FROM CODE] — `CSSRPanel` decides the mode with `m_compact = (chart_h > 0 && chart_h < SSR_PANEL_H + 24)` (679) and the check compares `IsCompact()` against a character-for-character copy of that expression over the same chart height — so whatever the panel chooses, including a wrong threshold, a wrong comparison direction or a wrong constant, the check passes, and a future change would be mirrored by whoever copies it again. One nuance: it is not literally incapable of failing — `pch` is sampled once at 1659 before `Create`/`Render` while the panel re-reads the height inside every `Render`, so a freshly opened chart that answers 0 on the first read and a real height later makes the check FAIL while the panel is correct. Either way it carries no independent content about the threshold.

**Why** [CONFIRMED FROM CODE] — Same predicate, same input, both sides.

**Verifiers** — Verified; the false-failure path is theirs.

**Fix** [RECOMMENDATION] — Assert behaviour instead of arithmetic: `CheckEq("compact body height", SSR_PANEL_COMPACT_H, pnl.PanelH())` when compact and `SSR_PANEL_H` when not, plus the full/compact tab-strip existence check the compact branch already performs for its half (1783-1787, with `qa-smoke-13`'s loop applied). Both are independent of the threshold expression, and together they would catch `ui-panel-3` — which the current assertion cannot.

---

**End of section C.** 197 confirmed defects, every one cited to a file and a line in build v125, every fix sketched against the code as it stands and none of them compiled or run. The 30 POTENTIAL_RISK findings follow in section D; the 21 NOT_A_BUG findings are recorded in `verified.json` and appear nowhere in this document as defects. [CONFIRMED FROM CODE]

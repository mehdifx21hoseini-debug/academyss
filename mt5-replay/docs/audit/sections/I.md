## I. PROP CHALLENGE REVIEW

### I.0 Scope and stance

This section reviews `CSSRPropEvaluation` (`MQL5/Include/SSReplay/Trading/SSR_PropEvaluation.mqh`, 481 lines, class at l.105-478) and everything that feeds or reads it: the host's rule assembly (`MQL5/Experts/SSReplay/SSReplayStandalone.mq5` l.1185-1201), the setup form's prop block (`MQL5/Include/SSReplay/Ui/SSR_SetupPanel.mqh` l.68-101, 119-122, 794-800, 1176-1178), the panel's Prop sheet (`MQL5/Include/SSReplay/Ui/SSR_Panel.mqh::SheetProp` l.1749-1852), the port that wires them (`MQL5/Include/SSReplay/Ui/SSR_GroupPort.mqh` l.204-234, 765-772), and the statement (`MQL5/Include/SSReplay/Trading/SSR_Journal.mqh` l.286-297).

The file is well-built. Its header already states the correct philosophy — *"the rules are INPUTS, and every choice this file makes on the user's behalf is written down in the panel and in the statement rather than buried here"* (l.16-19) — and the Prop sheet's own comment already states the correct UI law — *"THIS SHEET COMPUTES NOTHING. Every fraction arrived from the evaluation… A meter worked out here could read 'safe' in the frame the evaluation reads 'failed'"* (`SSR_Panel.mqh` l.1735-1742). **[CONFIRMED FROM CODE]** The Challenge Engine below is that philosophy carried the rest of the way, not a replacement for it. Nothing in this section proposes deleting `SSRPropRules`, `SSRPropPreset`, the four-meter sheet, the void-on-rewind doctrine, or the "one number, one meaning" accessor rule at l.184-199.

---

### I.1 What exists today — the honest inventory

**Rules the engine actually judges (5).** `OnClock` l.358-438, in this order: daily loss (l.391), total drawdown static-or-trailing (l.401), day roll (l.413-415), deadline (l.418), profit target gated on minimum trading days (l.429-437). **[CONFIRMED FROM CODE]**

**Rules named in the brief that do not exist anywhere.** Max positions, max risk per trade, max lot, news restriction, session/time-of-day restriction, consistency rules. Greps of `SSR_PropEvaluation.mqh`, `SSR_TradingEngine.mqh::Open` (l.705-756) and `CSSRGroupPort::Market` (l.1067-1106) return no volume ceiling, no open-position ceiling below the `SSR_MAX_POSITIONS 512` array bound (`SSR_TradingEngine.mqh` l.38, 710), and no per-trade risk ceiling — `SetRiskPercent` clamps only to 0..100 (`SSR_GroupPort.mqh` l.535-540). **[CONFIRMED FROM CODE]**

**Profiles: half-built, and already the right shape.** `SSRPropPreset` (`SSR_SetupPanel.mqh` l.68-79) and `SSRDefaultPresets` (l.94-101) ship four named shapes — `Practice`, `2-step P1`, `2-step P2`, `1-step` — cycled by a button (`CyclePreset` l.411-423, `ApplyPreset` l.442-448) and round-tripped through `presets.ini` with a validator that already rejects an unpassable challenge (`nm == "" || (on != 0 && tg <= 0.0) -> continue`, l.342). **[CONFIRMED FROM CODE]** This is the profile picker the brief asks for; it is simply too narrow — see I.3.

**The gap between the presets and the rules.** A preset carries exactly four values (`name, on, target, daily, total`, l.69-73), and the struct's comment defends that choice: *"A preset that also set values the panel does not show would change the session in ways the user cannot see"* (l.63-66). But the evaluation has eight rule fields (`SSRPropRules` l.68-77). **[CONFIRMED FROM CODE]**

**A genuine plumbing hole, cited from source.** The host builds the rules at l.1185-1194:

```
prop.profit_target_pct  = CfgPropTgt();        // 1189  -> setup form wins
prop.max_daily_loss_pct = CfgPropDly();        // 1190  -> setup form wins
prop.max_total_loss_pct = CfgPropTot();        // 1191  -> setup form wins
prop.trailing           = InpPropTrail;        // 1192  -> raw input, always
prop.min_trading_days   = InpPropMinDays;      // 1193  -> raw input, always
prop.max_days           = InpPropMaxDays;      // 1194  -> raw input, always
```

Three fields go through the `Cfg*()` accessors (defined l.239-241) and three bypass them. **[CONFIRMED FROM CODE]** Consequence: a trader who picks `1-step` in the setup form gets its 10/5/6 numbers but keeps `InpPropMinDays = 3` and `InpPropMaxDays = 30` from the EA inputs (l.174-175), and can never select a trailing drawdown from the form at all — `m_v` has no field for it (`SSR_SetupPanel.mqh` l.119-122). This is exactly the accessor-bypass shape that **host-expert-10 [CONFIRMED]** documents for spread and chart timeframe, in the same file, for the same reason. **[INFERENCE]**

**Dead state.** `m_day_low_eq` is written at l.157, 338, 372 and 381 and read nowhere — `Report()` prints `m_low_eq` (l.474), not the daily low. **[CONFIRMED FROM CODE]** It is the field a *"daily loss measured from the day's low"* rule variant would need, half-implemented.

**Where the verdict is consumed.** `CSSRGroupPort::ReadState` copies twenty prop fields into `SSRUiState` (l.204-234); `SheetProp` draws four meters, an optional deadline line, a headline and a Reset button (`SSR_Panel.mqh` l.1777-1849); `CSSRJournal` writes one evaluation box into the HTML statement (l.286-297); `PauseRequested` (l.455-462) carries the verdict into the controller's auto-pause; the host opens the review card when a prop run completes (`SSReplayStandalone.mq5` l.3031-3036). **[CONFIRMED FROM CODE]**

---

### I.2 The defect register — every confirmed and potential prop finding

| id | class | sev | what it is | what the Challenge Engine must do about it |
|---|---|---|---|---|
| **trading-analytics-1** | CONFIRMED | HIGH (verifier: MEDIUM) | Resuming a saved session voids a running evaluation before the first candle. `CSSRSessionManager::Restore` → `NotifyRestored()` (l.381) → `CSSRReplayController::NotifyRestored` → `PublishRewind(m_clock.now_msc)` (l.1668-1669) → `OnRewind` (l.443), whose only guard is `m_state != RUNNING`. The reason text says the clock moved backwards when it did not. | Distinguish *restored* from *rewound*. See I.6. |
| **trading-analytics-2** | CONFIRMED | MEDIUM | No `SaveInto`/`RestoreFrom` exists; the first `OnClock` after a resume re-bases `m_peak_eq`, `m_day_open_eq`, `m_total_days`, `m_trading_days` on current equity (l.366-377). Account and equity curve *are* restored, so the judge forgets what the account remembers. | Persist the evaluation. See I.6. |
| **trading-analytics-5** | CONFIRMED | LOW | `Positions()` is `m_acct.Total()` (l.134-135), which `CSSRTradingEngine::Open` increments for a *pending* order before any fill (l.710-738) and never decrements on cancel — so three placed-and-cancelled limits satisfy a three-day minimum with zero trades. | Make "what counts as a trading day" an explicit profile rule. See I.4, R7. |
| **trading-analytics-12** | CONFIRMED | LOW (verifier: MEDIUM) | `JumpForward` (`SSR_ReplayController.mqh` l.1333-1420) publishes no `OnClock`, and `Pump` returns 0 unless PLAYING (l.998) — a jump to the end of the window leaves the evaluation `IN PROGRESS` for ever, and any breach *inside* the skipped span is never seen. | Judge on jump; see I.5, and the STATUS row must be able to say `NOT JUDGED`. |
| **trading-analytics-11** | **NOT_A_BUG** | — | Unguarded `DailyFloor()`/`TotalFloor()` when the pct is 0. Refuted: the panel gates both readouts on `prop_daily_pct`/`prop_total_pct` (`SSR_Panel.mqh` l.1788, 1805) and `prop_floor` has no reader. | Do **not** "fix" this as a defect. If the dashboard adds a floor row, it must keep those gates. |
| **ui-port-session-6** | **NOT_A_BUG** | — | Same persistence gap as trading-analytics-2, refuted as a duplicate/opt-in-unimplemented. | Cite trading-analytics-2, not this, as the persistence finding. |
| **ui-dialogs-9** | CONFIRMED | LOW | `ReadAll` clamps balance, risk, spread and speed (l.1191-1199) but not `prop_target`/`prop_daily`/`prop_total` (assigned l.1176-1178), so a typed 0 drops the rule the `> 0.0` guards protect — including a profit target of 0, an unpassable challenge that the panel's own `presets.ini` loader already rejects at l.342. | The profile validator must run on the keyboard path too. See I.3. |
| **host-expert-6** | CONFIRMED | HIGH (verifier: MEDIUM) | Pass 2 calls `CSSRSetupPanel::Restore(g_setup)` unconditionally (l.1948); a run that never opened the form inherits a stale `setup.ini` — including `prop_on=1` — and every `Cfg*()` switches to it. A user with `InpProp=false` can get a judging, failing evaluation they never asked for. | The profile must carry an identity and an origin. See I.3. |
| **host-expert-10** | CONFIRMED | LOW | The accessor-bypass pattern, proven for spread/chart-tf. Named here because `InpPropTrail`/`InpPropMinDays`/`InpPropMaxDays` are the same shape (I.1). | Route all eight rule fields through `Cfg*()`. |
| **ui-panel-4** | CONFIRMED | LOW | `HideSheetArea`'s list stops at `tab3`, so the fifth (Prop) tab is outside it (`SSR_Panel.mqh` l.2044). Latent only because **ui-panel-3** re-shows everything each frame. | Any new Prop surface must be swept by a loop over `SSR_TAB_MAX`, never a written-out list. |
| **qa-smoke-13** | CONFIRMED | LOW | Stage 18's compact assertion builds its panel with a NULL port (l.1663), so no evaluation and no fifth tab ever exist — the regression it should catch is uncoverable. | The dashboard needs a QA stage with a real prop port. See I.9. |
| **ui-panel-5** | CONFIRMED | MEDIUM | Cache slots 12 and 17 both write object `setuprow` at the same coordinates, so `order_why` survives one frame (`SSR_Panel.mqh` l.1432). | **Blocking for pre-trade rules.** `m_trade_error` is the only refusal channel (`SSR_GroupPort.mqh` l.917); a rule that refuses a trade through a text that flickers for one frame is a rule the trader experiences as a dead button. |
| **ui-panel-13** | CONFIRMED | LOW | The caption chip row overruns the collapse button by 6 px when fidelity is degraded and both `BLIND` and `PROP` chips show (`SSR_Panel.mqh` l.887, chip drawn l.902-906). | A profile-named chip (`PROP·AGGR`) makes this worse, not better. See I.7. |
| **trading-exec-1** | CONFIRMED | **CRITICAL** | Rewind drops positions placed after the cut without reversing their P/L, commission and swap from the balance (`SSR_TradingEngine.mqh` l.640). | The evaluation is insulated *today* only because it voids on rewind (l.443-452). Any future "rewind no longer voids" relaxation is gated on this being fixed. Say so in the design, do not relax it. |
| **trading-analytics-9** | CONFIRMED | LOW | The equity ring drops its oldest half when full (`SSR_Statistics.mqh` l.272-284), so the *statistics* peak can be lost. | The evaluation keeps its own `m_peak_eq` (l.379) and is unaffected — but a dashboard that shows a drawdown figure must read the evaluation's peak, never the stats engine's. |
| **trading-exec-6** | CONFIRMED | MEDIUM | No margin check on entry; an unaffordable order is accepted, charged, then stopped out. | Same seam as the new exposure rules (`CSSRGroupPort::Market` l.1067). One pre-trade gate serves both. |
| **ui-port-session-3** | CONFIRMED | HIGH | `Restore` never checks the streams reached the saved instant and cannot rewind to it. | A persisted evaluation restored onto a stream that did not reach the saved instant would judge a clock it is not on. Persistence (I.6) must refuse rather than guess. |

---

### I.3 Challenge profiles

**The design already in the tree.** `SSRPropPreset` cycles by button because MQL5 has no combo box; `Row("ppr", …)` style cycling is the established idiom across the setup form (blind mode, timeframe and presets are all cycling buttons — `SSR_SetupPanel.mqh` l.266-268 says so explicitly). **[CONFIRMED FROM CODE]** The profile picker is therefore the existing Preset button widened, not a new control. **[RECOMMENDATION]**

**Widen the struct, keep the discipline.** `SSRPropPreset` becomes `SSRChallengeProfile` carrying every field of `SSRPropRules` plus the new rules of I.4 — and the struct comment's law ("a preset must not set values the panel does not show", l.63-66) is honoured by *showing them*: step 3's recap line (l.887-890) becomes a three-line rule summary, and the Prop sheet already prints `prop_rules` verbatim (`SSR_Panel.mqh` l.1760). **[RECOMMENDATION]**

**The four shipped profiles.** Keep the existing naming law verbatim — *"naming a preset after a company would put a claim about that company's current terms into a tool that has no way to check it"* (l.82-91) **[CONFIRMED FROM CODE]** — so profiles are named by shape and temperament, not by firm:

| profile | target | daily | total | basis | min days | deadline | max pos | risk/trade | notes |
|---|---|---|---|---|---|---|---|---|---|
| **Standard** | 8% | 5% | 10% static | day-open equity | 3 | 30 | 5 | 2% | today's `Init()` defaults (l.79-89), unchanged |
| **Aggressive** | 10% | 5% | 6% trailing | day-open equity | 3 | 0 | 10 | 3% | the existing `1-step` shape (l.99), plus a trailing floor |
| **Conservative** | 5% | 3% | 8% static | day-open **balance** | 10 | 60 | 3 | 1% | exercises the balance-basis switch (R3) |
| **Custom** | — | — | — | — | — | — | — | — | whatever the user typed; the only profile the form's edit boxes write into |

`Practice` (prop off, l.97) survives as the "no evaluation" row. **[RECOMMENDATION]**

**Custom is a state, not a fifth preset.** Editing any prop box while a named profile is selected must flip the profile to `Custom` — otherwise the sheet names a profile whose numbers no longer match it, which is the disagreement the whole file is built to prevent. `m_force_prop` (l.201, 421-423) already exists to push preset values into the boxes; the reverse edge is the one to add. **[RECOMMENDATION]**

**Validation, once, for both paths.** Move the preset-file validator (l.342) into a free function `SSRProfileValid(SSRChallengeProfile&, string &why)` and call it from three places: `LoadPresets` (as today), `ReadAll` (closing **ui-dialogs-9**), and the host's rule assembly before `SetRules` (l.1196). A profile that fails validation is refused with a printed reason, never silently degraded. **[RECOMMENDATION]**

**Origin, closing host-expert-6.** `SSRSetupValues` gains `profile_name` and `profile_origin` (`"form"` / `"file"` / `"inputs"`), written by `Save` (l.1226-1229) and read by `Restore` (l.1253-1256). The host logs which one won at l.1201 alongside `prop.ToString()`, and the panel's PROP chip is only drawn for an evaluation whose origin this run actually chose. **[RECOMMENDATION]**

---

### I.4 The rule set

Thirteen rules in four families. For each: where it hooks, and what it depends on.

**Family A — account shape (no judging, just the base)**

- **R1. Initial balance.** Exists: `m_rules.start_balance` from `CfgBalance()` (host l.1188). Every allowance is sized from it (l.209, 241, 254). Keep. **[CONFIRMED FROM CODE]**

**Family B — loss and target rules (judged in `OnClock`)**

- **R2. Profit target.** Exists (l.429-437). Keep, including the min-days gate, which the comment correctly calls *"the rule most people are surprised by"* (l.426-428). **[CONFIRMED FROM CODE]**
- **R3. Daily loss — and its basis.** Exists (l.391-398), measured as `m_day_open_eq - Equity()` against `start_balance × pct`. Two choices are hardcoded that firms genuinely differ on, and the file's own header (l.14-15) names the first as a known divergence: *equity vs balance* at the day's open, and *day-open equity* vs *day's low*. Add `ENUM_SSR_PROP_BASIS { SSR_BASIS_DAY_OPEN_EQUITY, SSR_BASIS_DAY_OPEN_BALANCE }` to `SSRPropRules`, and a `intraday_low` flag that finally reads the already-written `m_day_low_eq` (l.381). Both appear in `ToString()` so the recap line and the statement carry them. **[RECOMMENDATION]**
- **R4. Max total drawdown, static.** Exists (l.401-410, base `start_balance`). Keep. **[CONFIRMED FROM CODE]**
- **R5. Trailing drawdown.** Exists as a boolean (`m_rules.trailing`, l.257, 301) — correctly implemented against `m_peak_eq`, and correctly *unreachable from the setup form* (I.1). Two firm variants are missing and are worth the enum rather than a second bool: trailing that **locks** at the initial balance once the account is in profit (the most common real rule), and trailing measured on **closed balance** rather than equity peak. `ENUM_SSR_PROP_TRAIL { SSR_TRAIL_OFF, SSR_TRAIL_EQUITY_PEAK, SSR_TRAIL_LOCK_AT_START, SSR_TRAIL_BALANCE_PEAK }` replaces the bool; `SSRPropStateName`-style naming keeps it printable. **[RECOMMENDATION]**

**Family C — time rules**

- **R6. Minimum trading days.** Exists (l.432-436), with the `TradingDays()` accessor already correct about the open day (l.184-199). Keep verbatim — that comment block is the single best piece of reasoning in the file. **[CONFIRMED FROM CODE]**
- **R7. What counts as a trading day.** Broken per **trading-analytics-5**: `m_acct.Total()` rising counts a *pending order placement*. Replace the counter with an explicit enum on the profile — `SSR_DAY_COUNTS_ON_OPEN` (a position reached `SSR_POS_OPEN`) / `SSR_DAY_COUNTS_ON_CLOSE` (a position reached `SSR_POS_CLOSED`) — and detect it by walking `m_acct.At(i, p)` state transitions the way `CSSRShotBook::Scan` already does (`SSR_ShotBook.mqh` l.112-148), rather than by comparing a count. The header comment at l.131-133 already promises "a trade was OPENED that day"; this makes it true. **[RECOMMENDATION]**
- **R8. Maximum trading days / deadline.** Exists (l.418-424) as *calendar* days (`m_total_days = to_day - m_first_day + 1`, l.153), which matches how firms publish deadlines. Add a profile flag for firms that count only days the market was open, computed from day indices on which a clock tick was actually seen. **[CONFIRMED FROM CODE]** + **[RECOMMENDATION]**

**Family D — exposure rules (pre-trade gates, not post-hoc verdicts)**

These are the four new rules the brief asks for, and they belong at a different seam. A rule that *fails you after the fact* for opening a sixth position teaches nothing; a rule that *refuses the sixth position and says why* is the whole point of a practice tool. **[INFERENCE]**

- **R9. Max concurrent positions.** Gate in `CSSRGroupPort::Market` (l.1067) and `PlacePending`/`OpenFromLines` (l.715), reading `m_acct.OpenCount()`.
- **R10. Max risk per trade.** Gate on the sized risk: `Market` already computes the stop distance and calls `OpenWithRisk(type, m_risk_percent, …)` (l.1102), so the check is `m_risk_percent > profile.max_risk_pct` — refuse, with the number, before sizing.
- **R11. Max lot.** Gate on the volume `OpenWithRisk` produces; `CSSRTradingEngine::Open` validates only `volume > 0` (l.714-715).
- **R12. Cumulative risk-at-risk.** The natural companion: sum `risk_at_entry` (`SSR_TradingEngine.mqh` l.750) over open positions against a profile ceiling. Offered as **[FUTURE FEATURE]**, not required by the brief.

All four write their refusal into `m_trade_error` (l.917), which the panel draws as `order_why`. **That channel is broken by ui-panel-5 [CONFIRMED] and must be fixed first** — see I.8. Each gate is also a natural home for the missing margin check of **trading-exec-6 [CONFIRMED]**. **[RECOMMENDATION]**

**Family E — restriction rules**

- **R13. News restriction.** The infrastructure exists: `CSSRCalendar` (`MQL5/Include/SSReplay/Data/SSR_Calendar.mqh`) loads items into `SSRCalendarItem { msc, currency, name, importance }` (l.78-94), filters by importance floor (`SSRNewsFloor`, l.59), already applies a user timezone correction (`SetShiftMinutes`, l.169-170; `m_shift_msc`, l.105, applied l.151), and already knows how to raise a pause (`SetPauseMinutes`, l.171). **[CONFIRMED FROM CODE]** What is missing is a query: `bool InWindow(long now_msc, int before_min, int after_min, int min_importance)` walking `m_items[]`. The rule then has two enforcement modes, both profile-selectable: **refuse** (a pre-trade gate, Family D shape) or **flag** (a violation counted on the dashboard and named in the statement). Note **data-6** is **NOT_A_BUG** — the calendar deliberately holds the whole window — so `InWindow` must do its own "has the clock reached it" comparison rather than assuming the array is pre-filtered. **[RECOMMENDATION]**
- **R14. Session restriction.** Nothing exists. A profile carries `session_from_min`, `session_to_min` (minutes past the challenge day boundary, so it inherits R15's answer exactly) and a weekday mask. Enforcement is the same two modes. The measurement is already available — `CSSRStatsEngine::ByHour` buckets by `TimeToStruct(open_msc/1000)` in server time (`SSR_Statistics.mqh`, `SSRBucket` l.182-198) — so the statement can show where the violations clustered. **[RECOMMENDATION]**

**Family F — consistency rules**

Every consistency rule a firm publishes is a statement about the *distribution* of daily results, and nothing in the tree accumulates one: the evaluation keeps only the day currently open (`m_day_open_eq`, `m_day_low_eq`, `m_day_traded`, l.114-117) and throws it away on `RollDay` (l.149-159). **[CONFIRMED FROM CODE]**

- **R15. Best-day concentration.** "No single day may be more than X% of total profit." Needs a per-day ledger.
- **R16. Minimum-days-with-profit.** "At least N days must be profitable."
- **R17. Lot consistency.** "No trade larger than X× the median." `SSRStatistics::risk_spread_pct` already computes the population CV of `risk_at_entry` (`SSR_Statistics.mqh`, documented in the map) — the same measurement, one aggregation away. **[CONFIRMED FROM CODE]**

**The day ledger.** Add to `CSSRPropEvaluation` a fixed array `SSRPropDay m_days[SSR_PROP_MAX_DAYS]` — `{ long day_index; double open_eq; double close_eq; double low_eq; int trades; double worst_risk; int violations; }` — appended in `RollDay` (l.149) and closed out on verdict. Size it as a compile-time constant the way `SSR_MAX_POSITIONS` (l.38) and `SSR_CAL_MAX` are, not a dynamic array: 400 entries × ~48 bytes is ~19 KB, bounded, and a challenge longer than 400 days is not a challenge. This one structure serves R15, R16, R17, the persistence format of I.6, and the TRADING DAYS row of I.7. **[RECOMMENDATION]**

---

### I.5 When the rules are judged — the ordering problem

`OnClock` is published **once per `Pump`/`PumpTo`, after all the ticks of that pass** (`SSR_ReplayController.mqh` l.1027-1029, 1102-1104), and the evaluation has no `OnTicks` override. **[CONFIRMED FROM CODE]** Three consequences, in descending severity:

1. **A jump forward is never judged** — **trading-analytics-12 [CONFIRMED]**. `JumpForward` (l.1333-1420) publishes `OnSeek` and `Publish()` but no `OnClock`, and `Pump` returns 0 unless PLAYING (l.998). A jump to the end of the window leaves the verdict at `IN PROGRESS` in the statement (`SSR_Journal.mqh` l.286-297) and on the sheet.
2. **A breach inside a skipped span is invisible.** Equity is sampled only at the jump's landing point. The verifier's correction is worth quoting: when the jump does *not* complete the replay, `RollDay` recomputes `m_total_days` from the new day index, so the **deadline fires late rather than never** — but any daily-loss or drawdown breach *inside* the skip is lost permanently.
3. **The pump that straddles midnight is judged against the wrong day.** The rule order at l.390-415 is deliberate and its comment is right about the case it was written for (*"A day that ends in a breach must be judged on the breach, not on the roll"*, l.353-356) — but because `OnClock` fires once per pump, the first clock past midnight tests the **new** day's equity against `DailyFloor()` computed from the **old** day's `m_day_open_eq` (l.295-296). At 1× with small pumps this is a sub-second artefact; at high speed, with a pump spanning many minutes of replay time, it is a whole session's movement attributed to yesterday's allowance. **[CONFIRMED FROM CODE]** for the mechanism; the size of the effect is speed- and fidelity-dependent and therefore **[INFERENCE]**.

**The design.** **[RECOMMENDATION]**

- Give `CSSRPropEvaluation` an `OnTicks` override that tracks the **day index of the last tick consumed** and calls the same private `Judge(eq, now_msc)` that `OnClock` calls, so a pump that crosses a boundary rolls *at* the boundary instead of after it. `Judge` stays the only place that decides; `OnClock` remains the guaranteed heartbeat for pumps with no ticks.
- Have `JumpForward` publish `OnClock(now)` after its `Publish()` — the smallest possible change at l.1420 — and have the evaluation mark the skipped span. A verdict reached across a skip is *not* the same as one reached by playing, so add `SSR_PROP_UNJUDGED` alongside the existing five states (l.43-50) and a `m_skipped_span_msc` counter that `Report()` (l.467) and the dashboard both print. **A challenge you jumped through is not a challenge you passed, and the tool should say so** — the same doctrine as the rewind-voids-the-run rule at l.21-27, applied to the other direction of the clock.

---

### I.6 The daily boundary, the timezone, and persistence

**This is the deepest issue in the subsystem and the brief is right to single it out.**

**The boundary, as written.** `#define SSR_PROP_DAY_MSC ((long)86400000)` (l.40) and `day = now_msc / SSR_PROP_DAY_MSC` (l.369, 413). `now_msc` is server-stamped, so the boundary is **midnight in the broker's server clock, with no configurable reset hour and no DST awareness anywhere** — `SSR_Time.mqh` has no timezone helper at all (the whole file is 96 lines of conversion, bar-flooring, formatting and clamping). **[CONFIRMED FROM CODE]**

Three ways that is wrong in practice, all **[INFERENCE]** about firm behaviour, all **[CONFIRMED FROM CODE]** about the absence of a mechanism:

1. Firms publish a reset in a named timezone (commonly a fixed US Eastern 17:00 or a CE(S)T midnight). A broker server on GMT+2/+3 is *not* that boundary, and the offset is not even constant — it changes twice a year.
2. The offset drifts across a replay window: a window spanning a DST change has two different correct offsets, and a single constant gets one of them wrong.
3. The user cannot see which boundary is in force. `ToString()` (l.92-101) prints target/daily/total/trailing/min-days/deadline and says nothing about when a day starts.

**The design.** **[RECOMMENDATION]** The tree already contains the precedent — `CSSRCalendar::SetShiftMinutes` (l.169-170) and the host's `InpNewsShift` (`SSReplayStandalone.mq5` l.164), with a log line at l.950-953 that tells the user when the shift is probably wrong. Follow it exactly:

- `SSRPropRules.day_shift_min` (int, minutes), a `CfgPropShift()` accessor beside the others at l.239-241, and an `InpPropDayShift` input beside l.169-175.
- The boundary becomes `(now_msc - shift_msc) / SSR_PROP_DAY_MSC` — one expression, used at l.369 and l.413, and nowhere else. A named private helper `DayIndex(long msc)` so the two call sites cannot drift apart; that is the same "one number, one meaning" law the file already states at l.194-196.
- DST is not solved by a constant and must not pretend to be. Carry `day_shift_dst_min` and a pair of `datetime` change dates on the profile — the honest shape — and when they are unset, print the same class of warning the calendar prints at l.950-953: *"the evaluation's day starts at HH:MM server time; if your firm resets at a different hour, set InpPropDayShift."* **The warning is the deliverable.** A wrong boundary the trader knows about is a tool; a wrong boundary they do not is a lie with a progress bar.
- `ToString()` (l.92-101) gains the reset hour. Every consumer — recap line, Prop sheet (`SSR_Panel.mqh` l.1760), statement box (`SSR_Journal.mqh` l.292) — then shows it for free.

**Persistence — closing trading-analytics-2 and trading-analytics-1.** **[RECOMMENDATION]**

- Add `SaveInto(CSSRSessionFile&)` / `RestoreFrom(CSSRSessionFile&, string &warn)` to `CSSRPropEvaluation`, section `[prop]`, following `CSSRStatsEngine`'s `[equity]` shape exactly (map: section `equity`, key `e` = `"msc|val"`). Fields: rules (all of them, so a resumed run is judged by the rules it started under, not the ones now in the form), `state`, `reason`, `first_day`, `day`, `day_open_eq`, `day_low_eq`, `day_traded`, `peak_eq`, `low_eq`, `trading_days`, `total_days`, `last_positions`, `skipped_span_msc`, and the day ledger of I.4 as repeated `d` keys.
- `CSSRSessionManager` gains a fourth slot: `Attach(g, a, s, p)` (l.105-107), `p.SaveInto(f)` beside l.199, `p.RestoreFrom(f, w)` beside l.373. Note the linear-scan cost of `CSSRSessionFile::GetNth` flagged in **ui-port-session-13 [POTENTIAL_RISK]** — the day ledger is bounded at ~400 rows, so it is the same order as the account restore and no worse.
- **A restore is not a rewind.** Add `virtual void OnRestored(const long msc) { OnRewind(msc); }` to `CSSRTickObserver` (`SSR_ITickObserver.mqh` l.26-74) — defaulting to the current behaviour so every existing observer is untouched — and have `CSSRReplayController::NotifyRestored` (l.1668-1669) publish `OnRestored` instead of `PublishRewind`. `CSSRPropEvaluation::OnRestored` then verifies that the restored state matches the clock and stays `RUNNING`; if it cannot (**ui-port-session-3 [CONFIRMED]**: `Restore` never checks the streams reached the saved instant, and `MaxSkewMsc()` is already reported as a warning at l.360-363), it goes `VOID` with an *accurate* reason — *"the session came back at a different instant from the one it was saved at"* — instead of today's factually wrong *"the clock was moved backwards"* (l.448-450). **This is the single highest-value change in the section**: it closes a CONFIRMED HIGH finding, makes a second CONFIRMED finding reachable-and-correct instead of unreachable, and removes a sentence the product currently says that is not true.
- **The rewind doctrine stays.** A real rewind still voids (l.21-27). Do not relax it: **trading-exec-1 [CONFIRMED CRITICAL]** means a rewound account's balance is wrong, so a reconstructed verdict would be a believable number that means nothing — which is exactly what the header comment says at l.24-27.

---

### I.7 The Challenge Dashboard

The brief asks for six rows — TARGET, CURRENT PROFIT, DAILY LOSS, MAX DRAWDOWN, TRADING DAYS, STATUS — and five states. Four of the six already have a meter (`SheetProp`, l.1777-1820). The work is a row, a state machine, and a fit.

**The fit, honestly measured.** `SSR_SHEET_H` is 186 px (`SSR_Theme.mqh` l.449) and `SheetProp`'s own comment budgets *"178 px of the 186 this sheet has"* at worst case (l.1763-1772). **Six rows plus a status band do not fit in 186 px.** **[CONFIRMED FROM CODE]** Two mechanisms already exist and both should be used:

- **Tall mode.** `SSR_SHEET_H_TALL = SSR_SHEET_H + SSR_SHEET_GROW` = 326 px (l.464-465), selected by `m_tall` when pro mode has room (`SSR_Panel.mqh` l.700-707) and already routed through the single `SheetH()` accessor (l.421-422) that six sheets and the frame read. The full dashboard is the tall form; the current four-meter sheet is the 186 px form. No new constant, no second place to be wrong by 140 px.
- **`Extent()`/`CheckFrame()`.** The layout-overflow instrument (`SSR_Widgets.mqh` l.129, 189) is exactly the tool for proving the tall form fits rather than asserting it in a comment. The Prop sheet's comment already defers to stage 38 for this; the dashboard should too.

**The six rows.**

| row | source, already available | notes |
|---|---|---|
| TARGET | `prop_target_pct` + `prop_progress` (`SSR_GroupPort.mqh` l.213, 228) | existing meter, unchanged (l.1777-1783) |
| CURRENT PROFIT | `prop_profit_pct` (l.227), money from `equity - start_balance` | new row; must print money **and** percent — a percentage alone is unreadable against an allowance quoted in money |
| DAILY LOSS | `prop_daily_used` + `prop_daily_floor` (l.221, 225) | existing meter (l.1787-1794); add **remaining money**, which is what a trader mid-trade actually needs |
| MAX DRAWDOWN | `prop_total_used` + `prop_total_floor` (l.222, 226) | existing meter (l.1800-1809); the base must stay named — the comment at l.1796-1798 is right that a trailing floor moving under someone who thinks it is static is the most expensive surprise here |
| TRADING DAYS | `prop_days` / `prop_days_min` (l.215, 231) + deadline (l.232-233) | existing meter (l.1813-1819) + existing deadline line (l.1825-1833); merge into one row once the day ledger of I.4 exists |
| STATUS | new | see below |

**The six states.** Today there are five (`ENUM_SSR_PROP_STATE`, l.43-50) and the panel colours three of them (`SSR_C_RUN`/`SSR_C_STOP`/`SSR_C_HOLD`, l.1752-1754). The brief's ON TRACK / WARNING / AT RISK / FAILED / PASSED are **not** a replacement for that enum — `FAILED`, `PASSED` and `VOID` are *verdicts* and must keep being decided by `Finish()` (l.137-144). The three new ones are a *presentation* of `RUNNING`, derived from the meters the evaluation already publishes:

```
AT RISK  : max(DailyUsed(), TotalUsed()) >= 0.80
           or (deadline set and DeadlineUsed() >= 0.90 and target not met)
WARNING  : max(DailyUsed(), TotalUsed()) >= 0.50
           or a Family D/E rule was violated this run
ON TRACK : otherwise
```

**Derive them in `CSSRPropEvaluation`, never in the panel.** An `ENUM_SSR_PROP_POSTURE Posture(void)` accessor beside `DailyUsed()`/`TotalUsed()` (l.237-262), for the reason the sheet's own comment gives at l.1738-1742 and the port's at l.218-220: *"this port is a wire, and a wire that did arithmetic would be the second place that can be wrong about whether the run is over."* The thresholds belong on the profile so Conservative can warn earlier than Aggressive. **[RECOMMENDATION]**

`SSR_PROP_UNJUDGED` (I.5) is the sixth state and reads `NOT JUDGED — the clock was jumped past N days`.

**Three MQL5 constraints the dashboard must respect.** **[CONFIRMED FROM CODE]**

1. **63 characters.** MetaTrader draws 63 and errors on nothing. `SheetProp` already clips defensively (`Clip(m_state.prop_rules, 62)` l.1760, `Clip(m_state.prop_headline, 44)` l.1840). Every new row is audited by **A14** (`tools/ssr_audit.py` l.867) — and **spikes-audits-28 [CONFIRMED]** notes A14 misses four of the eight text-drawing helpers A19 already knows about, so a new row drawn through one of those four is *unpoliced*. Fix A14's helper list before adding rows, or the audit will bless an overflow.
2. **Every word through `T()`.** The prop strings are already registered (`SSR_Strings.mqh` l.362-364, 409-428, 459) and **A19** (l.1363) enforces it. **chart-12 [CONFIRMED]** is the counter-example to avoid.
3. **No clipping, no scrollbar, no layout engine.** Rows are absolute-positioned; the row that does not fit is the row that is not drawn. `CheckFrame()` is how you know which one.

**Two panel defects the dashboard inherits.** **ui-panel-4 [CONFIRMED]** — sweep tabs with a loop over `SSR_TAB_MAX` (l.544), never a written-out list; `HideBody` already documents why (l.2088-2090). **ui-panel-13 [CONFIRMED]** — the caption chip row already overruns by 6 px with `BLIND` + `PROP`; a profile-named chip makes that worse, so the profile name belongs on the sheet (beside `pp_rules`, l.1760), not in the chip.

**Performance.** `SheetProp` is redrawn inside `DrawSheet`, which **ui-panel-1 [CONFIRMED]** shows deletes and recreates the entire visible sheet every repaint, defeating both caches; **ui-panel-2 [CONFIRMED]** adds ~44 `Forget()`s per frame. Doubling the Prop sheet's row count without fixing those two multiplies an existing cost. **The dashboard is gated on ui-panel-1 and ui-panel-2.** **[INFERENCE]**, from the confirmed mechanism.

---

### I.8 Ordering — what must be true before what

**[RECOMMENDATION]** Nothing here is optional sequencing; each step is blocked by the one above it.

1. **`OnRestored` vs `OnRewind`** (`SSR_ITickObserver.mqh`, `SSR_ReplayController.mqh` l.1668) — closes **trading-analytics-1**, and until it lands every resumed challenge is `VOID` and no persistence work is observable.
2. **`[prop]` persistence + `CSSRSessionManager` fourth slot** — closes **trading-analytics-2**. Must refuse, not guess, when **ui-port-session-3**'s skew warning fires.
3. **Route all eight rule fields through `Cfg*()`** (host l.1192-1194) and **validate on the keyboard path** (`ReadAll`, closing **ui-dialogs-9**) — profiles are meaningless until the form can express a whole rule set.
4. **`DayIndex()` + `day_shift_min` + the honest warning** — the boundary must be right before the day ledger records days against it.
5. **Day ledger + `SSR_DAY_COUNTS_ON_OPEN|CLOSE`** — closes **trading-analytics-5**, and is the prerequisite for every consistency rule.
6. **`Judge()` on tick boundaries + `OnClock` after `JumpForward` + `SSR_PROP_UNJUDGED`** — closes **trading-analytics-12**.
7. **Fix `ui-panel-5`** (slot 12/17 `setuprow` collision), *then* add the Family D/E pre-trade gates in `CSSRGroupPort::Market` (l.1067) / `OpenFromLines` (l.715). A refusal the trader cannot read is worse than no rule. Fold **trading-exec-6**'s margin check into the same gate.
8. **Fix `ui-panel-1`/`ui-panel-2`, then the tall dashboard**, with `Posture()` on the evaluation and `CheckFrame()` proving the fit.
9. **QA**: a smoke stage that builds the panel with a *real* prop port — **qa-smoke-13** shows stage 18's NULL port (l.1663) makes the fifth tab unreachable, so the current suite cannot see the Prop sheet at all. Extend `SSR_T9_Trading`/`SSR_T10_Statistics` with day-boundary cases: a pump straddling midnight, a weekend gap, a shift of ±420 minutes, a save/restore mid-challenge, and a jump past the deadline.
10. **Fix A14's helper list** (**spikes-audits-28**) before any new drawn row.

---

### I.9 What not to change

**[RECOMMENDATION]** Preserve, verbatim, the reasoning already in this subsystem: the rewind-voids-the-run doctrine (l.21-27, 443-452) — it is correct, and **trading-exec-1 [CONFIRMED CRITICAL]** is the proof; the `TradingDays()` "one number, one meaning" accessor and its comment (l.184-199); the port's refusal to do arithmetic (`SSR_GroupPort.mqh` l.216-220); the sheet's refusal to compute a meter (`SSR_Panel.mqh` l.1735-1742); the preset naming law (`SSR_SetupPanel.mqh` l.82-91); the "a preset must not set what the panel does not show" law (l.63-66), honoured by widening the panel rather than narrowing the preset; and the clamped 0..1 meters (l.203-284) whose comment — *"a bar that can exceed its own width is a drawing bug"* — is the right instinct on a surface with no layout engine. Do not "fix" **trading-analytics-11**, **ui-port-session-5**, **ui-port-session-6** or **data-6**: all four are classified **NOT_A_BUG**, and two of them describe deliberate designs the Challenge Engine depends on.

**Unvalidated-by-author caveat.** Build v125 has never run on a real MT5 terminal. Every runtime claim here — pump granularity against wall-clock speed, the size of the midnight-straddle effect, `CheckFrame()`'s verdict on a 326 px dashboard, the cost of a 400-row `[prop]` restore through `GetNth`'s linear scan — is reasoned from source and must be measured on a terminal before it is believed. **[INFERENCE]**

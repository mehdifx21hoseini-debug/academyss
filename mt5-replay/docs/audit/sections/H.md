## H. RISK ENGINE REVIEW

### H.1 What exists today

`CSSRRiskEngine` lives in `MQL5/Include/SSReplay/Trading/SSR_RiskEngine.mqh` (152 lines, one class, no base class). It includes exactly one header, `../Common/SSR_Types.mqh` (line 12), and calls nothing but `SymbolInfoInteger/Double` and `MathFloor/MathAbs/MathPow`. There is no chart object, no file I/O, no `Print`, no `OrderSend`, and no reference to a position, a clock or an account anywhere in the file. **[CONFIRMED FROM CODE]**

Its entire state is seven instrument facts plus one string:

```
   double            m_tick_value;   // account currency per tick, per lot   (18)
   double            m_tick_size;    // price movement of one tick           (19)
   double            m_point;                                               (20)
   double            m_vol_min; m_vol_max; m_vol_step;                       (21-23)
   int               m_digits;                                              (24)
   string            m_last_reason;                                         (25)
```

Public surface, in full: `ConfigureFromSymbol` (41-57), `Configure` (59-70), `LastReason/VolMin/VolMax` (72-74), `RiskOf` (79-85), `LotForRisk` (94-135), `RiskPercentOf` (138-144), `MoneyOf` (147-148). One private helper, `RoundToStep` (27-32). **[CONFIRMED FROM CODE]**

Ownership: the engine is held **by value** inside `CSSRTradingEngine` (`CSSRRiskEngine m_risk;`, `SSR_TradingEngine.mqh:77`) and handed out as a pointer by `Risk()` (`:566`). Every production caller is inside `CSSRTradingEngine`; tests and QA reach it through `Risk()`. **[CONFIRMED FROM CODE]** — corroborated by the trading-exec map §2.

Calibration happens in exactly one place: `CSSRTradingEngine::OnSessionStart` ends with `m_risk.ConfigureFromSymbol(symbol)` (`SSR_TradingEngine.mqh:582`), and `RestoreFrom` repeats it — always with the **custom replay symbol**, whose money properties `CSSRCustomSymbolManager::CloneMoneyProperties` sets explicitly rather than trusting `CustomSymbolCreate` to carry them over (`Mt5/SSR_CustomSymbolManager.mqh:282-290`: `TRADE_TICK_SIZE`, `TRADE_TICK_VALUE`, `TRADE_TICK_VALUE_PROFIT`, `TRADE_TICK_VALUE_LOSS`, `TRADE_CONTRACT_SIZE`, `VOLUME_MIN/MAX/STEP`). **[CONFIRMED FROM CODE]**

### H.2 What is right, and must be preserved

1. **Tick value / tick size, never pips.** `RiskOf` is `|dist| / m_tick_size * m_tick_value * volume` (83-84). This is the only money formula in the product; the comment at `SSR_CustomSymbolManager.mqh:258-265` records that the clone's tick size came back wrong on build 6090 and that a test caught it. Any extension must keep going through `RiskOf` rather than reintroduce a points formula. **[CONFIRMED FROM CODE]**
2. **Rounding DOWN is a deliberate invariant**, not an oversight: `MathFloor(v / m_vol_step + 1e-9) * m_vol_step` (31), with the epsilon that `CSSRGroupPort::ClosePartial` forgot (GroupPort:856, recorded in the trading-exec map's cross-file caveat). The comment at 90-92 states the rule: *"1% that is sometimes 1.3% is not a risk model - it is a bug with a friendly name."* Keep it, and keep the epsilon. **[CONFIRMED FROM CODE]**
3. **Refusal over silent substitution.** Below `m_vol_min` it returns `0.0` and explains itself (120-128) rather than trading `m_vol_min` and calling it 1%. This is the correct default for every new rule too. **[CONFIRMED FROM CODE]**
4. **One sizing formula for preview and order.** `PreviewLot` / `PreviewPendingLot` (`SSR_TradingEngine.mqh:810-833`) call the same `LotForRisk` on the same `FillPrice`, precisely so the UI does not grow a second formula (comment at 813-826, repeated at `SSR_GroupPort.mqh:259-261`). This is the single most important structural property of the subsystem and the extension must not weaken it. **[CONFIRMED FROM CODE]**
5. **UI independence is already real.** The panel never includes `SSR_RiskEngine.mqh`; it reads `lot_from_risk`, `risk_money`, `reward_money`, `rr` out of `SSRPortState` (`Ui/SSR_ReplayPort.mqh:233-236`), which `CSSRGroupPort::Fill` populates from engine calls (`SSR_GroupPort.mqh:302-324`). The extension inherits a working consumption path; it does not have to invent one. **[CONFIRMED FROM CODE]**

### H.3 Defects and gaps in what exists

**Filed findings that bear directly on risk (cite by id):**

| id | class | sev | bearing on the risk engine |
|---|---|---|---|
| `trading-exec-1` | CONFIRMED | CRITICAL | Rewind drops post-cut positions without reversing P/L, commission and swap, so `m_balance` and therefore `Equity()` are wrong — and **every** `LotForRisk` call is sized off `Equity()` (`SSR_TradingEngine.mqh:767, 797, 810, 832`). The risk engine is arithmetically correct and still returns the wrong lot, because its input is corrupt. This must be fixed before any new rule is trusted. |
| `trading-exec-6` | CONFIRMED | MEDIUM | No margin check on entry: an unaffordable order is booked, charged, then stopped out. `FreeMargin()` (`:946`) exists and has no caller. A pre-trade gate is exactly the seam the extension needs. |
| `trading-exec-12` | CONFIRMED | LOW | `Open()` (`:705-756`) validates only `volume > 0`; `m_risk.VolMin()/VolMax()` and the step are unused on that path. The Publisher and Strategy raw paths bypass the risk engine entirely. |
| `tests-b-6` | CONFIRMED | MEDIUM | Every `Risk().Configure` in `SSR_T9_Trading.mq5` is overwritten by `Load` → `OnSessionStart` → `ConfigureFromSymbol("TEST")`, so six T9 sections run on the unknown-symbol fallback specs. The risk engine's regression cover is weaker than it looks. |
| `tests-b-11` | CONFIRMED | LOW | T9.1's rounding assertions are one-sided; a regression that made `LotForRisk` refuse outright would pass. The rounding-DOWN invariant of H.2(2) is asserted only from above. |
| `trading-analytics-2` | CONFIRMED | MEDIUM | `CSSRPropEvaluation` has no `SaveInto`/`RestoreFrom`, so a resumed run re-bases peak equity, day counters and the daily floor on current equity. Any daily/drawdown rule copied from that class inherits the defect unless persistence is built in from the start. |
| `trading-analytics-1` | CONFIRMED | HIGH | Resuming a session voids a running evaluation on startup (`NotifyRestored` → `PublishRewind(now)` → `OnRewind`). A risk policy that voids or resets on every rewind would repeat this. |
| `trading-analytics-12` | CONFIRMED | LOW | `JumpForward` publishes no `OnClock`, so an `OnClock`-only judge never runs across a jump. A daily-loss rule hung off `OnClock` alone would silently not exist during jumps. |
| `ui-dialogs-9` | CONFIRMED | LOW | `ReadAll` clamps balance, risk, spread and speed but not the three prop numbers, so a typed `0` deletes a rule silently. Every new numeric risk rule needs a clamp in the same block (`Ui/SSR_SetupPanel.mqh:1191-1199`). |
| `ui-panel-5` | CONFIRMED | MEDIUM | Cache slots 12 and 17 both write `"setuprow"`. That is the row a new "risk rule blocked this" message would naturally land in. Do not add a third writer to it. |

**Additional defects and gaps read directly from source (not in `verified.json`):**

- **The refusal reason has no path to the screen. [CONFIRMED FROM CODE] — severity MEDIUM.** `LotForRisk` sets `m_last_reason` (101, 106, 114, 124-127, 132); `OpenWithRisk` copies it into `m_last_error` (`SSR_TradingEngine.mqh:769`); `CSSRGroupPort` copies that into `m_trade_error` (`SSR_GroupPort.mqh:863, 873, 883`) and exposes `TradeError()` (`:917`). A repository-wide grep for `TradeError()` returns only `Scripts/SSReplay/Tests/SSR_T15_Ux.mq5` and `Scripts/SSReplay/QA/SSR_QA_Smoke.mq5` — **no UI caller**, and `SSRPortState` has no field for it. What the trader actually sees when sizing fails is `SSR_S_NO_SIZE` / `SSR_S_OPEN_NO_SIZE` (`Ui/SSR_Panel.mqh:1417-1422, 1453-1455`), i.e. "no size", with the explanation discarded. The extension's verdict object must be carried on `SSRPortState`, or every new rule will be as mute as this one.
- **The longest reason string cannot be drawn. [CONFIRMED FROM CODE] — severity LOW.** `StringFormat("%.2f%% of %.2f is %.2f, below the minimum lot (%.2f would risk %.2f)", ...)` (124-127) renders, for balance 10000, as a ~73-character string. MetaTrader draws exactly 63 characters of `OBJPROP_TEXT` (ground truth) and reports nothing. Reasons intended for the panel must be authored to ≤ 63 characters, or split into a short code plus a long form for the log.
- **The panel computes risk money with a second formula, on a different basis. [CONFIRMED FROM CODE] — severity LOW/MEDIUM.** `Ui/SSR_Panel.mqh:1354-1355` draws `Money(m_state.balance * m_state.risk_percent / 100.0)` while every sizing call uses `Equity()` (`SSR_TradingEngine.mqh:767`). With any open floating P/L the "riskmon" chip and the actual order disagree, which is the exact failure mode H.2(4) was designed to prevent.
- **`ConfigureFromSymbol` silently fabricates a risk model. [CONFIRMED FROM CODE] — severity MEDIUM.** Lines 51-56 substitute `m_tick_value = 1.0`, `m_tick_size = m_point`, `vol_min = 0.01`, `vol_max = 100`, `vol_step = 0.01` for any non-positive read, and nothing records that a substitution happened. On an unresolved symbol the money answers are plausible and wrong. There is no `IsCalibrated()` / health accessor to ask.
- **The `vol_max` cap is announced only to a caller that ignores it. [CONFIRMED FROM CODE] — severity MEDIUM.** Lines 129-133 clamp to `m_vol_max`, set `m_last_reason = "capped at the maximum lot"` and return a **non-zero** lot; `OpenWithRisk` tests only `if(lot <= 0.0)` (`:768`), so the order is sent at a size that risks strictly more than the user asked for, with the warning thrown away. This is the same class of error the class comment at 90-92 forbids.
- **Tick-value asymmetry is cloned but not used. [POTENTIAL_RISK] — severity LOW.** The symbol manager clones `SYMBOL_TRADE_TICK_VALUE_PROFIT` and `_LOSS` (`SSR_CustomSymbolManager.mqh:284-285`), but `ConfigureFromSymbol` reads only the generic `SYMBOL_TRADE_TICK_VALUE` (45). On instruments where a broker publishes different profit/loss tick values, the loss leg — the one risk sizing is about — is computed from the wrong constant. Broker-dependent, therefore POTENTIAL_RISK, not CONFIRMED.
- **`MoneyOf` is duplicated rather than called. [CONFIRMED FROM CODE] — severity IMPROVEMENT.** `SSR_RiskEngine.mqh:147-148` and `CSSRTradingEngine::RealisedOf` (`:128-133`) contain the same expression, `RiskOf(volume, move) * (move < 0.0 ? -1.0 : 1.0)`. Two copies of the P/L sign rule is one more than the design allows.
- **`risk_at_entry` excludes commission. [CONFIRMED FROM CODE] — severity LOW.** `:751` and `:741-742` set `risk_at_entry = RiskOf(volume, |open_price - sl|)` while `m_balance -= commission` on the same lines. A "risk 1%" trade therefore loses 1% **plus** two commission legs when stopped. This is consistent with `trading-analytics-10` (R excludes commission while money measures include it) and must be a stated, documented choice in the extension, not an accident.
- **`RoundToStep` does not `NormalizeDouble`. [CONFIRMED FROM CODE] — severity LOW.** Line 31 returns a raw product; `Open()` stores it verbatim into `volume` (`:723`). Volumes such as `14.280000000000001` then propagate into the journal CSV, the session file and `ClosePartial` comparisons.

### H.4 The extension: where each rule belongs

**Principle.** `CSSRRiskEngine` today knows an *instrument* and nothing else — no clock, no account, no position log. Six of the eleven requested rules (max daily risk, max open risk, max positions, correlated exposure, drawdown protection, daily loss protection) are **portfolio** rules: they need the position log, the equity curve and the replay clock. Folding them into `CSSRRiskEngine` would make the one class that is currently unit-testable from six numbers depend on the whole account, and would break the `Configure()`-then-assert pattern that T9 and T10 use. **[RECOMMENDATION]**

So: **three layers, not one.**

| Layer | Class | File | Knows | Owns |
|---|---|---|---|---|
| 1. Instrument arithmetic | `CSSRRiskEngine` *(extend in place)* | `Trading/SSR_RiskEngine.mqh` | tick value/size, volume step/min/max, digits | sizing modes, distance and R:R math, calibration health |
| 2. Portfolio policy | `CSSRRiskPolicy` *(new)* | `Trading/SSR_RiskPolicy.mqh` | the rule set + a non-owning `CSSRTradingEngine*` | daily/open/count/drawdown state, the verdict |
| 3. Gate | `CSSRTradingEngine` *(existing)* | `Trading/SSR_TradingEngine.mqh` | both | calls the policy before booking anything |

Layer 2 copies a pattern this codebase already proved: `CSSRPropEvaluation` (`Trading/SSR_PropEvaluation.mqh:105-478`) attaches a non-owned `m_acct`, implements `CSSRTickObserver`, keeps a server-day index `m_day = msc / SSR_MSC_PER_DAY`, a `m_day_open_eq`, a `m_peak_eq`, and publishes fractions (`DailyUsed()`, `TotalUsed()`) that the port copies verbatim — with the port comment at `SSR_GroupPort.mqh:217-220` stating the rule the policy must also obey: *"Every fraction is asked for, never worked out here: this port is a wire, and a wire that did arithmetic would be the second place that can be wrong."* **[CONFIRMED FROM CODE]** + **[RECOMMENDATION]**

**The gate is the load-bearing change.** Today `Open()` (`:705`) is the only booking path and it validates almost nothing; `OpenWithRisk` sizes and then calls `Open()`. Putting the policy check *inside* `Open()` — not inside `OpenWithRisk` — is what makes `CSSRPublisher`'s raw `m_acct.Open(SSR_ORDER_BUY, a1, a2, a3, 0.0, "external")` and the strategy paths obey the rules, and closes `trading-exec-12` and `trading-exec-6` in the same stroke. **[RECOMMENDATION]**

### H.5 Rule-by-rule specification: inputs, and where the data already is

Shared vocabulary (new, in `Trading/SSR_RiskTypes.mqh` or appended to `SSR_TradeTypes.mqh`):

```
enum ENUM_SSR_SIZING   { SSR_SIZE_RISK_PCT=0, SSR_SIZE_FIXED_LOT, SSR_SIZE_FIXED_MONEY };
enum ENUM_SSR_RISK_RULE{ SSR_RULE_NONE=0, SSR_RULE_MIN_LOT, SSR_RULE_MAX_LOT, SSR_RULE_STOP_DIST,
                         SSR_RULE_RR, SSR_RULE_DAILY_RISK, SSR_RULE_OPEN_RISK, SSR_RULE_MAX_POS,
                         SSR_RULE_CORRELATED, SSR_RULE_DRAWDOWN, SSR_RULE_DAILY_LOSS, SSR_RULE_MARGIN };
struct SSRRiskIntent { ENUM_SSR_ORDER type; double entry; double sl; double tp; double volume; string tag; };
struct SSRRiskVerdict{ bool allowed; double lot; double risk_money; double risk_pct; double rr;
                       ENUM_SSR_RISK_RULE rule; string why_short; /* <=63 chars */ string why_long; };
```

Returning a **rule id** alongside the text is what lets the panel colour and localise the refusal without string-matching, and keeps `why_short` inside MetaTrader's 63-character `OBJPROP_TEXT` draw (ground truth). **[RECOMMENDATION]**

| # | Rule | What it computes | Data it needs | Where that data already exists | Gap to close |
|---|---|---|---|---|---|
| 1 | **Risk percentage** | lot from `balance × pct / per-lot risk` | account basis, pct, entry, stop, tick value/size, vol step/min/max | `LotForRisk` (94-135) verbatim; `Equity()` (`TradingEngine:971`); pct from `CSSRGroupPort::m_risk_percent` (`:53`, set by `SetRiskPercent` `:535-540`) and `CfgRisk()` (`SSReplayStandalone.mq5:225`) | **None functionally.** Make the equity-vs-balance basis an explicit `ENUM` on the rules rather than hard-coded `Equity()` at `:767`, and fix the panel's second formula (H.3). |
| 2 | **Fixed lot** | use a typed lot, validated | lot, `m_vol_min/max/step` | `VolMin()/VolMax()` (73-74), `m_vol_step` (23), `RoundToStep` (27-32) | New `double NormalizeLot(double v, string &why)` on `CSSRRiskEngine` (floor to step, refuse `< vol_min`, cap at `vol_max` **and refuse rather than silently cap** — see H.3). Then `Open()` calls it, closing `trading-exec-12`. |
| 3 | **Fixed monetary risk** | lot from `money / per-lot risk` | money amount, entry, stop, tick value/size | `RiskOf(1.0, dist)` at line 111 is already the per-lot risk; only the numerator differs | New `double LotForMoney(double money, double entry, double stop)` — 8 lines, factored out of `LotForRisk` so both share one body and one set of refusal reasons. |
| 4 | **Stop distance** | minimum/maximum permitted entry-to-stop, in points or price | `m_point`, `m_digits`; bid/ask; the drawn stop | `m_point` (20), `Point()`/`Digits()`/`Bid()`/`Ask()` on the engine; `CSSRGroupPort::SetStopPoints` (`:544-560`) already converts points → a moved chart line; `SSRPendingFor(..., min_dist, ...)` (`SSR_TradeTypes.mqh:93-126`) is the existing precedent for a minimum-distance refusal, called with `point*2` | New `min_stop_points` / `max_stop_points` in the rules; the check belongs in the policy so it applies to strategy and external orders too. No ATR or volatility source exists anywhere in `Trading/` — an ATR-based stop is **[FUTURE FEATURE]** needing an indicator handle on the replay symbol. |
| 5 | **R:R** | `\|tp − entry\| / \|entry − sl\|`, refused below a floor | entry, sl, tp | Already computed — but **in the port**: `out.rr = rew_dist / risk_dist` (`SSR_GroupPort.mqh:319-325`) | Move the ratio into `CSSRRiskEngine::RewardRisk(entry, sl, tp)` and have the port read it, per the "wire does no arithmetic" rule. Add `min_rr`; refuse with `SSR_RULE_RR`. Note `tp == 0` must mean "no target", not "0 R" — the current port only fills `rr` when `lot > 0 && entry > 0`. |
| 6 | **Max daily risk** | Σ `risk_at_entry` of positions *opened today*, as % of day-open equity, capped | per-position `risk_at_entry` and `open_msc`; a day boundary; day-open equity; **now** | `risk_at_entry` and `open_msc` are fields of `SSRVirtualPosition` (`SSR_TradeTypes.mqh:178-291`), reachable via `Total()` + `At(i, out)`; `SSR_MSC_PER_DAY` is `Common/SSR_Types.mqh:33`; the day-roll algorithm exists in `CSSRPropEvaluation::RollDay` and `m_day_open_eq` | **The engine has no public `Now()`** — `m_now_msc` (`TradingEngine:618, 697`) has no accessor; a grep of the header finds none, and the read surface in the trading-exec map does not list one. Add `long NowMsc()`. Note `risk_at_entry` is `0.0` for any position opened without a stop, so the sum understates by exactly the positions that are least bounded — count them separately (`SSRStatistics::trades_without_stop` already names the concept). |
| 7 | **Max open risk** | Σ over OPEN positions of `RiskOf(volume, \|open_price − sl\|)`, capped as % of equity | the open log, sl, volume, tick value/size | The exact expression is already written at `TradingEngine:751` and `:741-742`; `OpenCount()` (`:974`), `At(i)` | New accessor `double OpenRisk()` on the engine (one pass over `m_pos[]`), and the cap in the policy. Positions with `sl == 0` must be treated as **unbounded**, i.e. block on count, not on money. |
| 8 | **Max positions** | refuse when open+pending ≥ N | `OpenCount()`, `PendingCount()` | Both exist: `TradingEngine:974-987` | Purely new rule state. Distinguish it clearly from `SSR_MAX_POSITIONS = 512`, which is array capacity (`Open()` `:710-711`), not a trading rule. |
| 9 | **Correlated exposure** | group instruments; cap the summed risk of a group | a **symbol per position**, a group/correlation table | **Does not exist.** `SSRVirtualPosition` has no `symbol` field (struct at `SSR_TradeTypes.mqh:178-291`); the engine has one `m_symbol`; the host has one account, `CSSRTradingEngine g_acct;` (`SSReplayStandalone.mq5:307`), attached to the primary stream only — `SSR_GroupPort.mqh` says so in `out.trade_symbol` (*"On a multi-symbol board the account follows the primary stream only"*) | **[FUTURE FEATURE].** Prerequisites, in order: (a) `symbol` on `SSRVirtualPosition` + a session-file field (the `pos=` row is 30 `\|`-separated fields today); (b) one account per stream **or** a multi-symbol account with a per-symbol `CSSRRiskEngine` calibration (tick value differs per instrument, so one `m_risk` cannot serve two symbols); (c) a static group table (e.g. `EUR`, `USD`, `METALS`) shipped as data — a live correlation matrix has no offline data source in this product. Do not ship (c) as a computed correlation; ship declared groups. |
| 10 | **Drawdown protection** | block new entries when equity is ≥ X% below peak equity | peak equity, current equity | `CSSRPropEvaluation::m_peak_eq` / `PeakEquity()` / `TotalFloor()`; `CSSRStatsEngine::EquityDrawdown(money, pct)` (`Trading/SSR_Statistics.mqh`) | Both sources are conditional: prop peak exists only when `InpProp` is on, and the stats ring holds `SSR_EQUITY_SAMPLES = 4096` with the **oldest half dropped** when full — so it is a curve for drawing, not a ledger for enforcing. The policy should keep its own two doubles (`m_peak_eq`, `m_low_eq`) updated on the same `OnTicks`/`OnClock` the engine already publishes. |
| 11 | **Daily loss protection** | block new entries once the day's equity loss exceeds X% of day-open equity (or start balance) | day-open equity, current equity, day boundary | `CSSRPropEvaluation::DailyFloor()` / `DailyUsed()` / `m_day_open_eq` (rules struct `SSRPropRules` at `:68-102`, wired from `CfgPropDly()` at `SSReplayStandalone.mq5:239-241`) | The logic exists but is **owned by the prop evaluation and only runs when a prop challenge is enabled**. Factor the day accounting down into `CSSRRiskPolicy` and let `CSSRPropEvaluation` read it, so a trader with no challenge still gets a daily stop. Doing so also gives one place to fix `trading-analytics-2` (no persistence) and `trading-analytics-12` (no judging across a jump). |

### H.6 Obligations any new stateful rule must meet

These are not style preferences; each one corresponds to a confirmed defect in the class the policy would be modelled on.

1. **`OnRewind(msc)` must unwind, not void and not ignore.** `CSSRPropEvaluation::OnRewind` voids the run, which fires on every session resume (`trading-analytics-1`). The policy's daily counters are derivable from the log (Σ `risk_at_entry` where `open_msc` is in the current day), so the correct `OnRewind` is *recompute from the log at the new now* — which is also immune to `trading-exec-1` once that is fixed. **[RECOMMENDATION]**
2. **`SaveInto` / `RestoreFrom` from day one.** `CSSRPropEvaluation` has neither (`trading-analytics-2`); `CSSRTradingEngine::SaveInto/RestoreFrom` (`:1053-1151`) and `CSSRStatsEngine` show the section/key idiom to copy. Anything not derivable from the log — peak equity, day-open equity, the count of blocked attempts — needs a section. **[RECOMMENDATION]**
3. **Do not judge on `OnClock` alone.** `JumpForward` publishes no `OnClock` (`trading-analytics-12`), and `Pump` returns 0 once the state is not PLAYING. Pre-trade checks are synchronous (called from `Open()`), so they are safe; the *monitoring* half must be driven from `OnTicks` as well, as `CSSRTradeAutoPause` is. **[RECOMMENDATION]**
4. **Clamp every new number where the others are clamped.** `SSR_SetupPanel.mqh:1191-1199` is the block that `ui-dialogs-9` shows the prop numbers were left out of. A `0` typed into "max open risk %" must not silently delete the rule. **[RECOMMENDATION]**
5. **Registration order.** If the policy observes ticks it must be registered **after** `g_acct` (`SSReplayStandalone.mq5:1176`), like `g_prop` (`:1195`) and `g_autopause` (`:1206`), so it sees the account as of the current tick. **[CONFIRMED FROM CODE]**

### H.7 What the UI consumes, and what that costs on a 310 px rail

The engine stays UI-free; the panel gains nothing but fields to read. Additions to `SSRPortState` (`Ui/SSR_ReplayPort.mqh`, alongside `lot_from_risk`/`risk_money`/`reward_money`/`rr` at 233-236), all filled in `CSSRGroupPort::Fill` by *asking*, never computing:

```
   double  open_risk_pct;      double  daily_risk_pct;      double  dd_from_peak_pct;
   double  open_risk_used;     double  daily_risk_used;     double  dd_used;   // 0..1 meters
   int     risk_rule;          // ENUM_SSR_RISK_RULE, 0 = clear
   string  risk_why;           // <= 63 chars, already short at source
   int     positions_open_cap; int     positions_open_now;
```

`risk_why` is the field whose absence today makes `LotForRisk`'s reasons invisible (H.3). **[RECOMMENDATION]**

Panel notes specific to this codebase: the meters should reuse the existing prop-meter idiom (the Prop tab already draws `prop_daily_used` / `prop_total_used` as 0..1 fractions supplied by the model); the refusal text must **not** be written into cache slot 12 or 17, which already collide (`ui-panel-5`); and any new Trade-sheet row must be measured with the `Extent()`/`CheckFrame()` layout-overflow instrument against `SSR_LAYOUT_RAIL` (310 px) before it ships, since the caption row already overruns by 6 px in one configuration (`ui-panel-13`). Because the replay chart receives only `CHARTEVENT_OBJECT_CLICK`, a risk-rule editor has to be buttons or the setup form — there is no combo box and no text field on the rail. The existing `StepRisk` ladder `{0.10, 0.25, 0.50, 1.00, 2.00, 3.00, 5.00}` (`SSR_Panel.mqh:2146`) is the pattern to extend; note it snaps to index 2 (0.50) for any value not on the ladder (`:2147-2150`), so a 0.75 typed into the setup form is silently rewritten by the first `+`/`-` click. **[CONFIRMED FROM CODE]**

### H.8 Test and audit obligations

- Fix `tests-b-6` first: set `Risk().Configure(...)` **after** `Load`, as `SSR_T10_Statistics.mq5:65-67` already documents — otherwise every new risk assertion measures the unknown-symbol fallback, not the model under test.
- Give `LotForRisk` a two-sided rounding assertion (`tests-b-11`), then mirror it for `LotForMoney` and `NormalizeLot`.
- Add a T9 section per rule that asserts the **verdict rule id**, not the string, so reasons can be reworded without breaking tests.
- Add an audit to `tools/ssr_audit.py` (A1-A21 all pass today) asserting that no file under `Ui/` includes `SSR_RiskEngine.mqh` or `SSR_RiskPolicy.mqh` — that is the mechanical form of "the engine stays independent of the UI", and it is cheap to keep true. **[RECOMMENDATION]**
- All of the above is unvalidated on a real terminal: the author has never run this build on MT5, so every `SymbolInfoDouble`-dependent behaviour in H.3 (fallback substitution, tick-value asymmetry) remains **[POTENTIAL_RISK]** until a terminal confirms it.

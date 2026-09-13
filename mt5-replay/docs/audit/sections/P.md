## P. SETTINGS REDESIGN

*Basis: build v125, `SSR_LAYOUT_RAIL` and `SSR_THEME_RAIL` active. This section is written against
section M's information architecture and does not contradict it. In particular **M.3.2 rejects a
SETTINGS destination on the replay panel, and P does not propose one.** The "Settings sheet" named
throughout is the one that already exists and is already called that: step 1 of the setup wizard,
`CSSRSetupPanel::RenderSettings()` (`SSR_SetupPanel.mqh:769`, titled `T(SSR_S_SU_SETTINGS)`). The
in-session surface stays what M.3.2 says it is — the command palette plus the operated chrome.*

---

### P.0 The position, in one page

[CONFIRMED FROM CODE] `SSReplayStandalone.mq5` declares **61 inputs** (`grep -c '^input'` = 61,
lines 69-187). Exactly **14** of them can be reached without opening MetaTrader's own inputs dialog,
and the list is not a matter of opinion — it is the `Cfg*()` block at `SSReplayStandalone.mq5:224-241`:

```
double          CfgBalance(void) { return g_setup_ready ? g_setup.balance       : InpBalance; }
double          CfgRisk(void)    { return g_setup_ready ? g_setup.risk_percent  : InpRiskPercent; }
...
double          CfgPropTot(void) { return g_setup_ready ? g_setup.prop_total    : InpPropTotal; }
```

Fourteen accessors, fourteen fields in `SSRSetupValues` (`SSR_SetupPanel.mqh:108-151`), fourteen keys
in `setup.ini` (`Save()`, `:1205-1226`). **Forty-seven inputs are reachable only through the grid the
setup panel was built to escape** — and the file says so about itself (`SSR_SetupPanel.mqh:5-12`):

```
//|  Everything about a session used to be set in MetaTrader's own   |
//|  inputs dialog: a grid of thirty rows the user has to open,      |
//|  scroll, read and close before the tool does anything. It is     |
//|  the single biggest reason a person tries a replay tool once     |
//|  and does not come back.                                         |
```

The grid is now **sixty-one** rows, and the form covers under a quarter of it. That is the open item
this section closes.

**What P proposes, in four numbers.**

| | today | after P |
|---|---|---|
| inputs | 61 | 61 (none deleted; one retired with M.8.1 #11) |
| reachable outside the inputs dialog | **14** | **51** |
| editable in-session | **2** (risk %, speed) | **10** |
| deliberately input-only, each with a written reason | 0 (they are unreachable by accident) | **10** (unreachable by decision) |

**And three structures.** A two-tier split (**BASIC 23 / ADVANCED 38**), twelve groups
(**Session, Data, Replay, Trading, Risk, Practice, Challenge, News, Strategy, Interface,
Performance, Advanced**), and one generated descriptor table that five consumers read — the same
move `SSR_Keys.mqh:125` and `SSR_Review.mqh:104` already make, for the same reason.

---

### P.1 What an MQL5 `input` is, and what that costs

Ground truth: **MQL5 inputs are read-only at runtime.** A program cannot write one, and nothing in
this product tries to. The established escape is already in the file and is correct: an accessor that
prefers a value the user chose and falls back to the input. Everything below extends that one idea
and invents nothing.

[CONFIRMED FROM CODE] **The escape has three layers today, and only the first is complete:**

| layer | mechanism | site | covers |
|---|---|---|---|
| 1. default | `input` | `:69-187` | all 61 |
| 2. chosen, pre-session | `SSRSetupValues` + `setup.ini` + `Cfg*()` | `SSR_SetupPanel.mqh:108`, `:1205`, `mq5:224` | **14** |
| 3. live, in-session | `ISSRUiPort` verb + `CSSRGroupPort` override | `SSR_ReplayPort.mqh:315-408` | **2** |

Layer 3 is the smallest and the most misread. It is not small because MQL5 is hostile; it is small
because nobody extended it. The port interface is explicitly built to be extended without breaking
anything — every optional verb carries a `{ return false; }` default:

```
SSR_ReplayPort.mqh:322    virtual bool Bookmark(const string label) { return false; }
SSR_ReplayPort.mqh:348    virtual bool SetRiskPercent(const double pct)   { return false; }
SSR_ReplayPort.mqh:349    virtual bool SetStopPoints(const double pts)    { return false; }
```

[CONFIRMED FROM CODE] and the **runtime setters a live setting would need already exist on the host
objects**, called once from `OnInit` and never again:

```
mq5:1146   g_ctrl.SetSpreadPoints(CfgSpread());
mq5:1208   g_autopause.Enable(SSR_PAUSE_ON_ENTRY,   InpPauseEntry);
mq5:1209   g_autopause.Enable(SSR_PAUSE_ON_SL,      InpPauseSL);
mq5:1210   g_autopause.Enable(SSR_PAUSE_ON_TP,      InpPauseTP);
mq5:1217   g_shots.Enable(InpShots);
mq5:1222   g_cal.SetShiftMinutes(InpNewsShift);
mq5:1223   g_cal.SetPauseMinutes(InpNewsPause);
mq5:1228   g_session.SetMode(InpPauseSession);
```

Eight setters, eight settings, one call each. **The plumbing for a live settings surface is already
built and is being used exactly once per session.**

#### P.1.1 The three storage classes, and the test that assigns them

Every input gets exactly one class, decided by a test that can be applied from source rather than
from taste:

* **IN — stays an `input`.** Either it is *bootstrap* (it is read before any surface that could set
  it exists, or it decides whether that surface opens at all), or it is *consent* (a setting a file
  written by an earlier run must not be allowed to answer). Ten inputs. Each says which, in the
  table.
* **FILE — moves to the settings file.** Reachable on the Settings sheet, carried across the
  handover, remembered between runs; applied when the session is built and not after. Forty-one
  inputs.
* **LIVE — settings file *and* a runtime verb.** FILE, plus an `ISSRUiPort` verb so it is editable
  in-session. Ten inputs.

#### P.1.2 Why LIVE is ten and not thirty

Most of the 41 FILE inputs *could* be made live — the setter exists, as P.1 shows. P declines, and
the reason is written in the source at the site (`SSReplayStandalone.mq5:1157-1159`):

```
   //--- the execution model, declared before the session opens so the
   //--- first trade is priced under the same assumptions as the last
   SSRExecutionModel exec;
```

[RECOMMENDATION] **The cost-model rule.** A setting that changes what a fill is worth — balance,
commission, slippage, swap, margin, stop-out, spread, ticks per bar, spread mode — must not change
inside a session, because a statement whose first trade and last trade were priced differently is
not a statement. `g_ctrl.SetSpreadPoints()` is a live setter and P still refuses to expose it. The
rule is the product's own; P is applying it, not adding it.

[RECOMMENDATION] **The evaluation rule.** The seven Challenge inputs are refused for the same shape
of reason and the sheet that draws them says it best (`SSR_Panel.mqh:1732-1740`): *"THIS SHEET
COMPUTES NOTHING… the evaluation is the one place that knows what these rules mean."* A rule edited
mid-run is not a rule. The in-session verb for the Challenge group already exists and is the honest
one: `ISSRUiPort::ResetEvaluation()` (`SSR_ReplayPort.mqh:395`), which voids the run and restarts it.

[CONFIRMED FROM CODE] **One refusal with a named defect behind it.** Blind mode is not made LIVE,
even though `CSSRBlindMode::Apply/RestoreAll` exist, because `chart-3` (CONFIRMED, MEDIUM) records
that the reveal is already undone within ~200 ms by the host re-applying on `IsOn()`. A live blind
toggle shipped before `chart-3` is fixed is a switch that flips itself back, which is worse than no
switch.

---

### P.2 The two tiers

**The tier rule, stated as a test rather than as taste:** a setting is **BASIC** when a
first-session trainee would notice a wrong value *and could correct it from what they can see*. It
is **ADVANCED** when the wrong value can only be evaluated against a broker statement, a profiler or
a firm's rulebook, or when it changes the *shape* of the run rather than a number in it.

[CONFIRMED FROM CODE] **And there is a hard geometric cap, which is why the tier exists at all.**
`SSR_SetupPanel.mqh:44-52`:

```
#define SSR_SETUP_W        304
#define SSR_SETUP_ROW      24
#define SSR_SETUP_H_MAX    (30 + 17 * SSR_SETUP_ROW + 44)
#define SSR_SETUP_FIELD_W  84
```

and `Create()` warns when the chart is shorter than what it needs (`:511-517`):

```
      int need = 28 + 30 + 17 * SSR_SETUP_ROW + 44 + 16;     // 526 px
      int have = (int)ChartGetInteger(chart_id, CHART_HEIGHT_IN_PIXELS);
```

**Seventeen rows is the whole budget, and step 1 already spends all seventeen** (13 `Row()` calls +
4 `Label()` headers, `:775-805`). There is no room to add a row, let alone 37. The tier and the
group together are what make 51 settings fit in a form that gets *shorter*, not taller — see P.8.3.

[INFERENCE — MQL5 exposes no text metrics, so px/char is an estimate] applying M's rule R5 to this
surface: a row's label occupies `304 - 12 - 12 - SSR_SETUP_FIELD_W` = **196 px ≈ 38 characters** at
`SSR_FS_BODY`, and the value box is 84 px ≈ **16 characters**. Those are the two budgets every row in
P.4 is written against, and both are well inside MetaTrader's 63.

**BASIC = 23. ADVANCED = 38.**

---

### P.3 The twelve groups

| group | the question it answers | inputs | BASIC | settable on the form | file section |
|---|---|---|---|---|---|
| **Session** | which window of history is this, and is it saved | 10 | 5 | 7 | `[session]` |
| **Data** | where the bars come from and how they become ticks | 5 | 1 | 5 | `[data]` |
| **Replay** | what the replay looks like while it runs | 5 | 4 | 4 | `[replay]` |
| **Trading** | what a fill costs | 7 | 1 | 7 | `[trading]` |
| **Risk** | how big the trade is | 4 | 2 | 4 | `[risk]` |
| **Practice** | what the replay hides, and when it stops for you | 5 | 4 | 5 | `[practice]` |
| **Challenge** | the rules being enforced | 7 | 4 | 7 | `[challenge]` |
| **News** | what the calendar puts on the chart | 3 | 1 | 3 | `[news]` |
| **Strategy** | the reference strategy, if it runs at all | 4 | 0 | 4 | `[strategy]` |
| **Interface** | language, and the one onboarding switch | 2 | 1 | 2 | `[interface]` |
| **Performance** | what the session spends on evidence | 5 | 0 | 3 | `[perf]` |
| **Advanced** | plumbing and consent | 4 | 0 | **0** | — |
| | | **61** | **23** | **51** | |

**Advanced is deliberately empty of settable rows**, and that is the point of having it: it is a
**read-only provenance page** drawn with the existing `Recap()` helper (`SSR_SetupPanel.mqh:573`).
It answers *"is another program allowed to trade in my account?"* without letting a form — or a
month-old file — change the answer. Four labels, no boxes, and a line naming the inputs dialog as
the only place those four can be set.

[CONFIRMED FROM CODE] **The Interface group holds two inputs, and that is itself the finding.**
Panel position, corner, collapsed state, destination and tall-mode wish are all persisted already —
but in `panel.ini` by `CSSRPanel::SavePlace/RestorePlace` (`SSR_Panel.mqh:64, 527, 553`), not as
inputs. The interface has a working settings store that the expert's inputs never touch, which is the
right answer and should stay that way. P adds nothing to `panel.ini`.

---

### P.4 The complete assignment — all 61 inputs

**Legend.** *Tier:* BASIC / ADV. *Class:* **IN** stays an `input` · **FILE** moves to the settings
file, applied at build time · **LIVE** settings file plus an in-session verb. *Key:* the settings-file
key; **bold** = one of the 14 keys `setup.ini` already writes; `—` = not stored (class IN).

| # | input | line | group | tier | class | key | consumer, and the verb if any |
|---|---|---|---|---|---|---|---|
| 1 | `InpSymbol` | 69 | Session | BASIC | **IN** | — | `:1904` origin, before any surface exists. Its UI is the chart you attach to |
| 2 | `InpStart` | 70 | Session | ADV | **IN** | — | `:2024` decides whether the picker runs. Its UI is the orange line and `CSSRRangeDialog` |
| 3 | `InpReplayBars` | 71 | Session | ADV | FILE | `replay_bars` | `:1076-1113` window length when start is auto |
| 4 | `InpWarmupBars` | 72 | Session | ADV | FILE | `warmup_bars` | `g_ctrl.SetWarmupBars()` `:1149` |
| 5 | `InpAlsoSymbols` | 98 | Session | ADV | FILE | `also_symbols` | `OpenExtraStreams()` `:455`, `:1316` |
| 6 | `InpRandom` | 100 | Session | BASIC | FILE | **`random`** | `CfgRandom()` `:237` → `g_picker` `:1016` |
| 7 | `InpSeed` | 101 | Session | BASIC | FILE | **`seed`** | `CfgSeed()` `:238` → `SSRSeedFromText` `:1020` |
| 8 | `InpSession` | 109 | Session | BASIC | FILE | **`session`** | `CfgSession()` `:231`; `OnDeinit` save `:2139` |
| 9 | `InpResume` | 110 | Session | BASIC | FILE | `resume` | `:1052`, `:2015` — **read as the raw input; it has no `Cfg` accessor today** |
| 10 | `InpPickStart` | 130 | Session | ADV | **IN** | — | `:2024`. A setting that decides whether the form opens cannot live in the form |
| 11 | `InpAutoHistory` | 128 | Data | ADV | FILE | `auto_history` | `:1977` |
| 12 | `InpHistoryBars` | 129 | Data | ADV | FILE | `history_bars` | `:1979` |
| 13 | `InpTicksPerBar` | 75 | Data | ADV | FILE | `ticks_per_bar` | `g_ctrl.SetTicksPerBar()` `:1148`; `CollectSettings` `:423` |
| 14 | `InpSpreadMode` | 77 | Data | ADV | FILE | `spread_mode` | `g_ctrl.SetSpreadMode()` `:1147` |
| 15 | `InpSpreadPoints` | 76 | Data | BASIC | FILE | **`spread`** | `CfgSpread()` `:226` → `:1146`. Setter exists; refused as LIVE by the cost-model rule (P.1.2) |
| 16 | `InpChartTf` | 73 | Replay | BASIC | FILE | **`chart_tf`** | `CfgChartTf()` `:228` → `OpenChart` `:1277` |
| 17 | `InpExtraTfs` | 99 | Replay | BASIC | FILE | **`extra_tfs`** | `CfgExtraTfs()` `:229` → `ParseTimeframes` `:1302` |
| 18 | `InpStartSpeed` | 83 | Replay | BASIC | **LIVE** | **`speed`** | `CfgSpeed()` `:227` → `SetSpeedX100` `:1586`. **Already live**: the speed control |
| 19 | `InpAutoPlay` | 159 | Replay | BASIC | FILE | `auto_play` | `:1710-1724` (see `host-expert-3`, CONFIRMED MEDIUM) |
| 20 | `InpOneChart` | 131 | Replay | ADV | **IN** | — | `:1893`, `:2555`. A setting that controls the handover cannot be carried by the handover (`host-expert-13`) |
| 21 | `InpBalance` | 89 | Trading | BASIC | FILE | **`balance`** | `CfgBalance()` `:224` → `g_acct.SetBalance()` `:1167` |
| 22 | `InpCommission` | 90 | Trading | ADV | FILE | `commission` | `exec.commission_per_lot` `:1161` |
| 23 | `InpSlippage` | 91 | Trading | ADV | FILE | `slippage` | `exec.slippage_points` `:1162` |
| 24 | `InpSwapLong` | 92 | Trading | ADV | FILE | `swap_long` | `exec.swap_long_per_lot` `:1163` |
| 25 | `InpSwapShort` | 93 | Trading | ADV | FILE | `swap_short` | `exec.swap_short_per_lot` `:1164` |
| 26 | `InpMarginLot` | 94 | Trading | ADV | FILE | `margin_lot` | `g_acct.SetMarginPerLot()` `:1168` |
| 27 | `InpStopout` | 95 | Trading | ADV | FILE | `stopout` | `g_acct.SetStopoutLevel()` `:1169` |
| 28 | `InpRiskPercent` | 127 | Risk | BASIC | **LIVE** | **`risk`** | `CfgRisk()` `:225` → `SetRiskPercent` (`SSR_ReplayPort.mqh:348`, override `SSR_GroupPort.mqh:535`). **Already live**: the TRADE risk ladder |
| 29 | `InpStopPoints` | 133 | Risk | ADV | FILE | `stop_points` | `g_gport.SetStopPoints()` `:1368`. Verb exists (`:349`); P adds no UI for it — M.4.1 refuses the stepper |
| 30 | `InpRR` | 134 | Risk | BASIC | FILE | `rr` | `g_gport.SetTpPoints(InpStopPoints * InpRR)` `:1370` |
| 31 | `InpTradeLines` | 132 | Risk | ADV | FILE | `trade_lines` | `:1294`, `:1372`, `:2863`. Default only — `SSR_CMD_LINES_TOGGLE` already toggles them in-session, but `AttachLines` runs once |
| 32 | `InpBlind` | 102 | Practice | BASIC | FILE | **`blind`** | `CfgBlind()` `:230` → `blind.Apply()` `:1001`. LIVE refused while `chart-3` stands (P.1.2) |
| 33 | `InpPauseEntry` | 103 | Practice | BASIC | **LIVE** | `pause_entry` | `g_autopause.Enable(SSR_PAUSE_ON_ENTRY,…)` `:1208` |
| 34 | `InpPauseSL` | 104 | Practice | BASIC | **LIVE** | `pause_sl` | `:1209`, and it also drives `SSR_PAUSE_ON_STOPOUT` at `:1211` |
| 35 | `InpPauseTP` | 105 | Practice | BASIC | **LIVE** | `pause_tp` | `:1210` |
| 36 | `InpPauseSession` | 106 | Practice | ADV | **LIVE** | `pause_session` | `g_session.SetMode()` `:1228` (`LearnFrom` `:1229` stays once-only) |
| 37 | `InpProp` | 169 | Challenge | BASIC | FILE | **`prop_on`** | `CfgProp()` `:232` → `prop.enabled` `:1187` |
| 38 | `InpPropTarget` | 170 | Challenge | BASIC | FILE | **`prop_tgt`** | `CfgPropTgt()` `:239` → `:1189` |
| 39 | `InpPropDaily` | 171 | Challenge | BASIC | FILE | **`prop_dly`** | `CfgPropDly()` `:240` → `:1190` |
| 40 | `InpPropTotal` | 172 | Challenge | BASIC | FILE | **`prop_tot`** | `CfgPropTot()` `:241` → `:1191` |
| 41 | `InpPropTrail` | 173 | Challenge | ADV | FILE | `prop_trail` | `prop.trailing` `:1192` — **input-only today, and not in the preset struct** |
| 42 | `InpPropMinDays` | 174 | Challenge | ADV | FILE | `prop_min_days` | `prop.min_trading_days` `:1193` |
| 43 | `InpPropMaxDays` | 175 | Challenge | ADV | FILE | `prop_max_days` | `prop.max_days` `:1194` |
| 44 | `InpNews` | 162 | News | BASIC | FILE | `news` | `LoadCalendar()` `:923`, `SSRNewsFloor()` `:940`. Load-time filter; a live change needs a reload and a redraw |
| 45 | `InpNewsPause` | 163 | News | ADV | **LIVE** | `news_pause` | `g_cal.SetPauseMinutes()` `:1223` — a pure observer value, read per tick |
| 46 | `InpNewsShift` | 164 | News | ADV | FILE | `news_shift` | `g_cal.SetShiftMinutes()` `:1222`. A calibration constant — the log at `:951-953` says to *"set InpNewsShift once and it is right for every session after"* |
| 47 | `InpRefStrategy` | 113 | Strategy | ADV | FILE | `ref_strategy` | `g_strategies.Add()` `:1240`, once, in observer order |
| 48 | `InpStratTf` | 114 | Strategy | ADV | FILE | `strat_tf` | `Configure()` `:1239`, `Add()` `:1240` |
| 49 | `InpStratLookback` | 115 | Strategy | ADV | FILE | `strat_lookback` | `Configure()` `:1239` |
| 50 | `InpStratRisk` | 116 | Strategy | ADV | FILE | `strat_risk` | `Configure()` `:1239` |
| 51 | `InpLanguage` | 187 | Interface | BASIC | FILE | `language` | `:1804`. Live reload is [FUTURE FEATURE] — every cached label in the 512-slot widget cache would have to be invalidated |
| 52 | `InpFirstCard` | 160 | Interface | ADV | FILE† | `first_card` | `:1736`. **† Retired by M.8.1 #11** (`CSSRFirstRun` deleted; no `panel.ini` → KEYS). Until #11 lands it is FILE; with #11 it has no consumer and the input is removed |
| 53 | `InpPumpMs` | 78 | Performance | ADV | **IN** | — | `EventSetMillisecondTimer()` `:1574`, re-armed `:3149`. Bootstrap: the timer exists before the panel. See `host-expert-15` |
| 54 | `InpVitals` | 135 | Performance | ADV | **LIVE** | `vitals` | `:2837`, read every 25 pumps — a bool the loop already re-reads |
| 55 | `InpFlightRec` | 136 | Performance | ADV | **IN** | — | `:1550`, `:1571`. A black box that can be switched off mid-flight is not a black box |
| 56 | `InpShots` | 144 | Performance | ADV | **LIVE** | `shots` | `g_shots.Enable()` `:1217` |
| 57 | `InpTradeHistory` | 137 | Performance | ADV | **LIVE** | `trade_history` | `:2947`, read per pass. Turning it **off** live must also sweep the drawn objects (invariant I7) |
| 58 | `InpSlot` | 74 | Advanced | ADV | **IN** | — | `g_sink.SetSlot()` `:1143` — it names the custom symbol. Two slots are two sessions; `CollectSettings` `:422` |
| 59 | `InpPublish` | 122 | Advanced | ADV | **IN** | — | `:1379`. **Consent** (see P.4.1) |
| 60 | `InpAllowControl` | 123 | Advanced | ADV | **IN** | — | `:1384`, `:1398`. **Consent** |
| 61 | `InpAllowTrade` | 124 | Advanced | ADV | **IN** | — | `:1384`. **Consent** |

**Totals: IN 10 · FILE 41 · LIVE 10 = 61.  BASIC 23 · ADVANCED 38 = 61.**
Of the 51 stored settings, **14 keys exist today and 37 are new.** Of the 10 LIVE settings, **2 are
live today** (`SetRiskPercent`, `SetSpeedX100`) and **8 are new**.

#### P.4.1 Why four of the ten IN inputs are IN — the consent rule

[CONFIRMED FROM CODE] `SSReplayStandalone.mq5:119-121` states the rule and P only enforces it:

```
//--- Read access is always published. The other two are OFF unless
//--- asked for: "another program may trade in my account" is not
//--- something to arrive at by leaving a box unticked.
```

A setting that must not be arrived at by leaving a box unticked must also not be arrived at by a
file an unrelated earlier run wrote. `InpPublish`, `InpAllowControl` and `InpAllowTrade` therefore
stay inputs, and `InpSlot` joins them because it names the custom symbol the whole session lives in.
[CONFIRMED FROM CODE] that this is not hypothetical: `host-expert-6` (CONFIRMED, **MEDIUM**) is exactly
the failure of a run inheriting an unrelated `setup.ini` — *"a prop evaluation that judges and can
fail them"*. The consent switches are the ones where that failure would be worst, so they are the
ones the file never carries.

#### P.4.2 Three inputs whose assignment is itself a finding

* **`InpResume` (#9)** — the form offers a `Continue …` quick button (`qcont`, `SSR_SetupPanel.mqh:712`),
  but the switch that decides whether resuming happens at all has **no `Cfg` accessor**: `:1052` and
  `:2015` read `InpResume` raw. [CONFIRMED FROM CODE] A user who picks "Continue" on the form and
  left `InpResume=false` in the inputs gets a fresh session and no message.
* **`InpPropTrail`, `InpPropMinDays`, `InpPropMaxDays` (#41-43)** — the preset struct carries only
  four fields (`SSRPropPreset`, `SSR_SetupPanel.mqh:68-79`), and its comment (`:60-67`) says why:
  *"A preset that also set values the panel does not show would change the session in ways the user
  cannot see."* The comment is right, and the consequence is that a preset named after a one-step
  challenge sets three numbers and leaves trailing drawdown at whatever the input says. **Showing
  these three on the ADVANCED Challenge page is what makes it legitimate to extend `SSRPropPreset`
  to seven fields** — the panel would then show everything a preset sets.
* **`InpNewsShift` (#46)** — the only input in the product whose own log line tells the user it is a
  once-per-machine calibration (`:951-953`). That is the definition of a value that belongs in a
  remembered file rather than in a per-run dialog.

---

### P.5 The settings file

[CONFIRMED FROM CODE] `CSSRSessionFile` (`Common/SSR_SessionFile.mqh:42`) already does sections and
typed keys — `Section`, `Select`, `Set`, `SetInt`, `SetDouble`, `Get`, `GetInt`, `GetDouble`,
`Comment`, `Count` — and is already the store for both `setup.ini` (`SSR_SetupPanel.mqh:1205`) and
`panel.ini` (`SSR_Panel.mqh:536`). **No new file format, no new parser, no new class.**

**One file, extended by section.** `MQL5\Files\SSReplay\setup.ini`:

```
[setup]      balance risk spread speed chart_tf extra_tfs blind session
             prop_on prop_tgt prop_dly prop_tot random seed      <- unchanged, all 14
[session]    replay_bars warmup_bars also_symbols resume
[data]       auto_history history_bars ticks_per_bar spread_mode
[replay]     auto_play
[trading]    commission slippage swap_long swap_short margin_lot stopout
[risk]       stop_points rr trade_lines
[practice]   pause_entry pause_sl pause_tp pause_session
[challenge]  prop_trail prop_min_days prop_max_days
[news]       news news_pause news_shift
[strategy]   ref_strategy strat_tf strat_lookback strat_risk
[interface]  language first_card
[perf]       vitals shots trade_history
[run]        token
```

**`[setup]` keeps its fourteen keys, spelled exactly as they are today.** A v125 file read by the new
build loses nothing, and every `Restore()` line already written keeps working
(`SSR_SetupPanel.mqh:1235-1250`). The eleven new sections are additive; `Select()` on a section a
older file does not have returns false and the caller keeps its default, which is the same "there is
nothing saved, and that is not a failure" contract `Restore()` already documents at `:1230-1231`.

#### P.5.1 `[run] token` — the fix for `host-expert-6`

[CONFIRMED FROM CODE] `host-expert-6` (CONFIRMED, **MEDIUM**): pass 2 calls
`CSSRSetupPanel::Restore(g_setup)` **unconditionally** (`mq5:1948`), so any run that never opened the
form — `InpPickStart=false`, `InpStart>0`, `CfgRandom()`, or a resumable session, the four conditions
at `:2024` — adopts a stale file and lets it overrule this run's inputs.

[RECOMMENDATION] **The fix is a token, and the mechanism already exists in the same function.** The
handover already carries a value across the restart in a chart object, because *objects belong to the
chart and survive the symbol change* (`mq5:1877-1888`, `SSR_PICK_STASH`). So:

1. `CSSRSetupPanel::Save()` writes `[run] token` = a value pass 1 also stashes on the chart when the
   user presses `go` (`Poll()`, `:1076`).
2. Pass 2's adoption becomes conditional: `g_setup_ready = (StashToken() != "" &&
   CSSRSetupPanel::Restore(g_setup) && g_setup.token == StashToken())`.
3. A run that never opened the form has no stash, so it never adopts the file, and the inputs win —
   which is what the comment above that block already promises (`:1932-1934`: *"A first pass reading
   the file would overrule inputs a user had deliberately set for THIS run"*). The promise is made
   for pass 1 and broken for pass 2; the token keeps it for both.

[INFERENCE] This removes one of `host-expert-5`'s two branches (the random session that re-rolls a
new seed across the handover) but **not the other**: pass 1 must also write the *resolved* seed back
before handing over — `g_setup.seed = IntegerToString((long)g_picker.Seed())`, the same value
`:1356` already hands the journal. Both changes are needed; neither is sufficient alone.

#### P.5.2 The write-back rule

[RECOMMENDATION] A LIVE setting changed in-session is **not** written to the file automatically. The
file records what the user *chose for a session*, not what they did during one; a speed nudged to
100x to skip a quiet hour should not become next week's default. The exception, and it is worth
naming because the current code neither does it nor decides against it: [RECOMMENDATION] write back
on `OnDeinit` only for `speed`, beside the session save at `:2135-2143`, because the starting speed
is the one setting whose right value a user discovers by using it.

---

### P.6 `SSRSettingRows()` — one table, six consumers

The 14 settings that exist today are written out by hand **five times**: as a struct field
(`SSRSetupValues:108`), as a `Row()` call (`RenderSettings:775`), as a `Num()`/`Str()` read
(`ReadAll:1170`), as a `SetDouble` (`Save:1210`), and as a `GetDouble` (`Restore:1237`) — plus a
sixth hand-written list in `Cfg*()` (`mq5:224`) and a seventh in `CollectSettings()` (`mq5:415`).
**Seven hand-kept lists that must agree.** That is precisely the shape M.2/R4 condemns for teardown
lists, and it is why the file has stayed at 14 keys: adding a setting costs seven edits in four files
and any one of them can be forgotten silently.

[RECOMMENDATION] **Add `MQL5/Include/SSReplay/Ui/SSR_Settings.mqh`**, the third generated table in the
product, alongside `SSRKeyBindings()` (`SSR_Keys.mqh:125`) and `SSRReviewRows()` (`SSR_Review.mqh:104`).
It uses their idiom exactly, including the self-growing array whose comment already explains why
(`SSR_Command.mqh:43-46`: *"a count kept by hand beside a list kept by hand will drift"*).

```
struct SSRSettingSpec
  {
   string          id;      // "bal" - the widget id; the 14 that exist keep theirs
   int             group;   // ENUM_SSR_SET_GROUP, twelve values
   int             tier;    // SSR_TIER_BASIC | SSR_TIER_ADV
   int             kind;    // NUMBER | TEXT | CHOICE | TOGGLE | READONLY
   ENUM_SSR_STR    label;   // a catalogue id, NEVER a literal
   string          section; // "setup" for the fourteen, else the P.5 section
   string          key;     // "" = class IN, not stored
   double          lo, hi;  // the clamp. ui-dialogs-9 exists because there was nowhere to put this
   bool            live;    // class LIVE
  };

int SSRSettingRows(const int group, const int tier, SSRSettingSpec &out[]);
int SSRSettingAll(SSRSettingSpec &out[]);
```

**Six consumers, each named with the function it lands in:**

| # | consumer | function | what it stops doing by hand |
|---|---|---|---|
| 1 | Settings sheet | `CSSRSetupPanel::RenderSettings()` `:769` | 13 `Row()` calls and 4 header labels |
| 2 | read-back | `CSSRSetupPanel::ReadAll()` `:1168` | 9 `Num()`/`Str()` lines and 6 hand-written clamps |
| 3 | persistence | `CSSRSetupPanel::Save()` `:1205` / `::Restore()` `:1229` | 14 `SetX` + 14 `GetX` lines |
| 4 | session record | `CollectSettings()` `mq5:415` | 9 fields, 6 of which read the **input** rather than the `Cfg` — the second half of `host-expert-10` |
| 5 | in-session surface | `SSRCommands()` `SSR_Command.mqh:60` | one palette entry per `live` row, appended in a fifth group |
| 6 | defaults | the `Cfg*()` block `mq5:224-241` | stays hand-written (MQL5 has no reflection) but becomes **auditable** — see A23 |

[RECOMMENDATION] **Audit A23 — settings-table completeness.** For every row of `SSRSettingAll()` with
a non-empty `key`: a `Cfg` accessor exists, a `Save()` write exists, a `Restore()` read exists, and
the `label` is an `ENUM_SSR_STR` and not a literal. The audits A1-A21 already pass and are the
product's chosen instrument; this is the one that can see this class of drift. (M reserves **A22** for
clip discipline; A23 is the next free number.)

[CONFIRMED FROM CODE] **And a widening, not a new audit, for i18n.** The step-1 row labels are
English literals today while the group headers go through `T()` — `SSR_SetupPanel.mqh:775-778`:

```
      m_w.Label("h1", …, T(SSR_S_SU_ACCOUNT), …); r++;
      Row("bal",  r++, "Balance",          DoubleToString(m_v.balance, 2),      true);
      Row("risk", r++, "Risk per trade %", DoubleToString(m_v.risk_percent, 2), true);
```

L.11 §9 already asks for A19 (the i18n audit) to be widened beyond its current reach. The settings
table is what makes that possible here: a spec carries a catalogue id, so a literal label becomes a
compile error of shape rather than a missed string.

---

### P.7 Wire and port: what LIVE costs

**The panel must not hold a setting.** M's rule for `SheetProp` — *"THIS SHEET COMPUTES NOTHING"* —
generalises: a surface that toggles a setting must read its current value from the wire, or the
label it draws is a guess. [RECOMMENDATION] Three new `SSRUiState` fields, flat and pointer-free the
way the wire already is:

| field | type | carries |
|---|---|---|
| `settings_flags` | `int` | six bits: pause on entry / SL / TP, vitals, shots, trade history |
| `session_pause_mode` | `int` | `ENUM_SSR_SESSION_MODE`, for the fourth Practice row |
| `news_pause_min` | `int` | minutes, for the News row |

Three fields, three lines in `SSRUiState::Init()` (`SSR_ReplayPort.mqh:238` — the loop M.4.2 already
notes will grow), three fills in `CSSRGroupPort::ReadState()`. **No new observer, no new engine call,
no per-frame cost**: each value is a member read.

**Four new port verbs**, each with the `{ return false; }` default the interface already uses
(`SSR_ReplayPort.mqh:322-324`):

```
   virtual bool SetPauseFlags(const int flags)   { return false; }   // entry / SL / TP
   virtual bool SetSessionPause(const int mode)  { return false; }
   virtual bool SetNewsPause(const int minutes)  { return false; }
   virtual bool SetDiagnostics(const int flags)  { return false; }   // vitals / shots / history
```

Four rather than eight because the host already groups three of them that way —
`g_autopause.Flags()` is read as one word at `CollectSettings:420`.

**Four new `Attach` calls on `CSSRGroupPort`**, mirroring the five it has
(`Attach`, `AttachStats`, `AttachSessions`, `AttachLines`, `AttachJournal`): `AttachAutoPause`,
`AttachShots`, `AttachCalendar`, `AttachSessionDetect`. The overrides then forward to the setters
already listed in P.1 — `g_autopause.Enable`, `g_shots.Enable`, `g_cal.SetPauseMinutes`,
`g_session.SetMode`.

[RECOMMENDATION] **One requirement that is easy to miss.** Turning `trade_history` **off** in-session
must *remove* the closed-trade objects `CSSRTradeLines::DrawClosed` created (`mq5:2947`), not stop
drawing new ones. Invariant I7 — *removed, not merely undrawn* — is the whole of the cost of that one
row, and it is the reason `InpTradeHistory` is ADVANCED rather than BASIC.

---

### P.8 `CSSRSetupPanel`: how the Settings sheet consumes the table

#### P.8.1 What must not change

[CONFIRMED FROM CODE] Three properties of this class are correct and survive P intact:

1. **One read, at the moment the answer is needed** (`SSR_SetupPanel.mqh:23-27`). `ReadAll()` is
   still called from `next` and `go` only, never per edit, never per frame.
2. **The inputs are still the truth, as defaults** (`:16-21`). P changes which values the file can
   carry, never the precedence.
3. **The form centres on its tallest step so it does not jump under the hand pressing Next**
   (`:47-49`, `:527-541`).

#### P.8.2 The five row kinds map onto widgets that already exist

| kind | widget | site |
|---|---|---|
| NUMBER | `Edit` + `Num()` | `SSR_Widgets.mqh:288`, `SSR_SetupPanel.mqh:283` |
| TEXT | `Edit` + `Str()` | `:288`, `:300` |
| CHOICE | cycling `Button` + `DrawMenu()` pseudo-combo | `:618`, `:582` |
| TOGGLE | CHOICE with two options — the existing `pon` pattern | `Choose()` `:1153` |
| READONLY | `Recap()` | `:573` |

**No new widget, and no new primitive.** That matters more than it sounds: M.1.1 records that the
wizard's pseudo-combo is the product's only combo box and warns *"do not build a second one"*.

#### P.8.3 Navigation inside the sheet: two fields, not twelve buttons

[RECOMMENDATION] Step 1 gains two cycling fields at the top, both drawn by the machinery that
already draws `tf`, `bl`, `pre` and `pon`:

```
   Group    [ Session      v ]      <- CHOICE, 12 options, new MenuOptions("grp") arm
   Show     [ Basic        v ]      <- TOGGLE, Basic | All, new Choose("tier") arm
```

and two new members on the class, `int m_group` and `int m_tier`. `RenderSettings()` then becomes a
loop:

```
   SSRSettingSpec rows[];
   int n = SSRSettingRows(m_group, m_tier, rows);
   for(int i = 0; i < n; i++)  Row(rows[i].id, r++, T(rows[i].label), Value(rows[i]), Boxed(rows[i]));
```

**Why a drop-down and not a rail or a pager.** A 12-cell rail does not fit a 304 px form, and a
`◀ name ▶` pager costs up to eleven clicks to reach the last group. The drop-down is 12 items ×
20 px = 240 px, which `DrawMenu()` already clamps against chart height (`:633`), and 12 is inside
`MenuClear`'s 32-item sweep so it does not touch `ui-dialogs-15`.

#### P.8.4 The height budget, re-derived

| | rows on the tallest settings page | page height |
|---|---|---|
| today | 13 settings + 4 headers = **17** | `30 + 17*24 + 44` = **482** |
| after P | 2 selectors + 1 header + **max 7 settings** (Trading, Challenge) = **10** | `30 + 10*24 + 44` = **314** |

[CONFIRMED FROM CODE] and therefore the *tallest step is no longer step 1*. `RenderStart()` is
`30 + rows*24 + 92` with `rows = 10 + (random ? 2 : 0)` (`:865-866`) = **410**; `RenderMode()` is
`34 + 4*48 + 62` = **288** (`:829`). So:

```
SSR_SETUP_H_MAX   482  ->  410      (the START step, not SETTINGS)
Create()'s `need` 526  ->  454
```

**The form reaches 51 settings and gets 72 px shorter.** [RECOMMENDATION] and `SSR_SETUP_H_MAX` must
stop being written as `(30 + 17 * SSR_SETUP_ROW + 44)` — a literal row count for a step that no
longer has one. This is the same class of stale metric M.1.3 books as `ui-plumbing-11`.

#### P.8.5 Defects that fall out of the rewrite, and one that must land with it

| finding | class | what the table-driven form does |
|---|---|---|
| `ui-dialogs-1` | CONFIRMED **HIGH** | `ReadAll()` walks the table and reads only ids where `m_w.Exists("e"+id)` is true. **The correct pattern is already nine lines below the broken one** — the seed read at `:1181` does exactly this. `Exists()` is `SSR_Widgets.mqh:192` |
| `ui-dialogs-9` | CONFIRMED LOW | `lo`/`hi` come from the spec, so all 51 rows are clamped, not 6. The three prop numbers stop being the exception the file's own preset loader already refuses (`:342`) |
| `ui-dialogs-8` | POTENTIAL_RISK LOW | `Num()` (`:283`) is the one place to fix the `,`→`.` rule; with the table it is also the only place a number is read. [RECOMMENDATION] strip separators before the last `,` or `.`, then parse |
| `ui-dialogs-15` | CONFIRMED LOW | `MenuClear()` (`:611`) bounds its sweep by `ArraySize(m_presets)`, not 32. Required before the group drop-down ships, because the same sweep serves it |
| `ui-dialogs-2` | CONFIRMED MEDIUM | an open pseudo-combo must be closed on every step change and on every group change. `m_menu = ""` in `Poll()`'s `next`/`back` arms and in `Choose("grp",…)`. **Must land with the group drop-down**, which makes the combo the normal way to navigate rather than a rarely-used field |
| `ui-dialogs-13` | CONFIRMED LOW | `m_start_y` is invalidated on step change (`Repaint()` `:656`), so `SetStartText` cannot draw the orange-line caption at a dead coordinate |
| `ui-dialogs-10` | CONFIRMED LOW | the `ses` row's value passes through the session manager's sanitiser before the quick step builds a path from it |
| `host-expert-10` | CONFIRMED LOW | `CollectSettings()` (consumer 4) reads the table, so the settings block written into a saved session records what the session **ran with** rather than what the inputs said |

#### P.8.6 One recap row the form gains

[RECOMMENDATION] `RenderStart()`'s recap (`:874-895`) currently names eight values. With 51
reachable settings it should also name **how many differ from their input default**, as a single row:
`Changed from defaults: 6` — one `Recap()` call, one loop over `SSRSettingAll()`, no new geometry.
It is the cheapest possible answer to *"what did I actually set?"* on a form that can now set fifty
things, and it is the row that makes `host-expert-6`'s failure mode visible if the token fix ever
regresses.

---

### P.9 In-session: the palette, not a destination

M.3.2 rejects SETTINGS as a rail destination on four grounds, the decisive one being that *"there is
no body of mid-session settings"* — and after P there still is not: **ten**. Ten settings do not earn
a 25 px rail cell against a 39 px reserve M deliberately leaves unspent, and eight of the ten are
one-bit toggles. They belong where M.6 already puts the compact-mode answer: the command palette,
which *"already works in every mode, is one `Edit` plus eight rows, and reaches all 31 commands"*.

**Eight new palette entries in a fifth group.** [CONFIRMED FROM CODE] `SSRAddCommand` takes the group
as a string and the array grows itself (`SSR_Command.mqh:43-56`), so a fifth group costs nothing
structurally; `CSSRPalette` renders through `CSSRWidgets::List` with paging already.

| label (composed at open, so it can show state) | group | action |
|---|---|---|
| `Pause when an order fills — off` | Settings | `set:pentry` |
| `Pause when a stop is hit — on` | Settings | `set:psl` |
| `Pause when a target is hit — on` | Settings | `set:ptp` |
| `Pause on a new session — off` | Settings | `set:psess` |
| `Pause before high-impact news — 0 min` | Settings | `set:npause` |
| `Diagnostic line in the log — on` | Settings | `set:vitals` |
| `Screenshot at every entry and exit — on` | Settings | `set:shots` |
| `Leave closed trades on the chart — on` | Settings | `set:thist` |

Two things this requires, both named rather than assumed:

* [RECOMMENDATION] the labels must be **composed when the palette opens**, not stored in the static
  table, because a static label cannot say `on`. That is one rebuild per open — a per-click cost, not
  a per-frame one, which is exactly what M's rule R3 permits.
* [CONFIRMED FROM CODE] the landing site is `CSSRPanel::RunChosen()` (`SSR_Panel.mqh:2423`), which
  already routes `c.action` to `Dispatch()` at `:2440`. Eight new `set:` arms in `Dispatch`, each one
  line, each calling one of the four port verbs from P.7 with a bit flipped from
  `m_state.settings_flags`. **The panel stores nothing.**

**And the gate, which is not optional.** M.8.2 states it for every new clickable control in the
architecture and it applies here unchanged: `host-expert-7` (CONFIRMED, MEDIUM) — keys are not
withheld while a modal is open. Eight palette entries that change the session's behaviour must not
ship onto a surface where Space still starts the replay behind it. `CSSRReviewCard::OnKey` is the
model.

**Refused for the in-session surface:** a numeric settings editor, a second `OBJ_EDIT` anywhere on
the replay chart, and any settings row on a destination sheet. The one typed field in the
architecture is the setup tag (M.1.1), `ui-panel-11` is still POTENTIAL_RISK against it, and a second
one would double an unclosed risk for a value that has a form.

---

### P.10 The open item, closed: 47 unreachable inputs

**Before:** 14 of 61 reachable, 47 behind MetaTrader's dialog, none of them by decision — the setup
panel simply covers what it happened to cover, which L.5 records as *"a documented limitation rather
than a defect"*.

**After:** 51 of 61 reachable on the Settings sheet; the remaining 10 are IN by a stated rule
(bootstrap or consent), each with its reason in the P.4 table. The count that matters is not 51, it
is **zero unreachable-by-accident**.

**Three supporting moves, all cheap:**

1. [RECOMMENDATION] **The `Advanced` group page names the ten.** It is a `Recap()`-only page
   (P.3), and its last row reads: *"These are set in the inputs dialog only."* A user who cannot
   find a setting on the form finds the sentence that tells them where it is — which is more than
   the product does for any of the 47 today.
2. [RECOMMENDATION] **One startup log line naming what overruled what.** `Summary()`
   (`SSR_SetupPanel.mqh:1253`) already prints the 14; extend it to print the count of file-sourced
   settings and the count of input-sourced ones. `host-expert-6` was findable precisely because
   nothing prints this.
3. [RECOMMENDATION] **Clamp the two IN inputs that have no downstream guard.** Class IN means the
   file cannot fix a bad value, so the code must: `InpPumpMs` at its two call sites (`:1574`,
   `:3149`) — `host-expert-15` (POTENTIAL_RISK, LOW) records that 0 or negative produces a session at
   READY with no pump and nothing in the log naming the cause — and `InpSlot` against
   `SSR_MAX_SLOTS` (`strategy-integration-report-12`, CONFIRMED, LOW).

---

### P.11 Cost ledger and build order

| # | change | ~lines | risk | fixes |
|---|---|---|---|---|
| P1 | `SSR_Settings.mqh`: `SSRSettingSpec`, `SSRSettingRows()`, `SSRSettingAll()`, 61 rows | 180 new file | low | the seven-hand-lists problem |
| P2 | `ReadAll()` gated on `Exists()`; clamps from the spec; `Num()` separator rule | 40 | low | `ui-dialogs-1` (HIGH), `ui-dialogs-9`, `ui-dialogs-8` |
| P3 | `Save()`/`Restore()` walk the table; 11 new sections, 37 new keys | 60 | low | 37 settings become rememberable |
| P4 | `[run] token`, stash write, conditional adoption in `OnInit` | 30 | **medium** — it changes which values a run uses | `host-expert-6` (MEDIUM); one branch of `host-expert-5` (MEDIUM) |
| P5 | `RenderSettings()` becomes a loop; `m_group`/`m_tier`; two new CHOICE arms in `MenuOptions`/`Choose`; `MenuClear` bound; combo closed on step change | 120 | medium | `ui-dialogs-2`, `ui-dialogs-15`, `ui-dialogs-13` |
| P6 | `SSR_SETUP_H_MAX` and `need` re-derived from the tallest step | 10 | low | a stale metric of the `ui-plumbing-11` class |
| P7 | `Cfg*()` extended to every stored key; `CollectSettings()` reads the table | 70 | low | `host-expert-10`; `InpResume` gains an accessor |
| P8 | 61 catalogue entries (51 labels + 8 group names + 2 tier names) + 61 `fa.txt` rows | 122 strings | low | the literal row labels; widens A19 |
| P9 | 3 wire fields, 4 port verbs, 4 `Attach`, 4 `CSSRGroupPort` overrides | 90 | medium | makes LIVE possible at all |
| P10 | 8 palette entries + 8 `Dispatch` arms + composed labels | 70 | low | 8 settings editable in-session |
| P11 | Audit A23; clamps for `InpPumpMs` and `InpSlot` | 60 | low | `host-expert-15`, `strategy-integration-report-12` |
| | **total** | **≈ +810 lines, +122 catalogue strings, one new header** | | |

**The catalogue is the largest single line item, and it should be.** 61 new `ENUM_SSR_STR` ids plus
61 `fa.txt` rows takes the catalogue from 190 to 251 (or from 208 to 269 after M.4.5's key strings).
A settings surface that is 190/190 translated in one language and English in the other is not a
settings surface for the product L.8 describes.

**Build order, and the gates.**

1. **P1 + P2 + P3 together.** They are one change: the table is worthless without the two walkers,
   and `ui-dialogs-1` (HIGH) is the reason the file has never held a session name. Nothing else here
   is worth doing while the form silently discards what it was told.
2. **P4.** On its own, because it changes which values a run uses and is the one item in P with a
   blast radius outside the UI.
3. **P5 + P6.** The visible rewrite. Gated on `ui-dialogs-2` and `ui-dialogs-15` landing in the same
   change, because the group drop-down makes both defects routine rather than rare.
4. **P7 + P8.** Accessors and strings — mechanical, independently testable, and P8 can be split by
   group if the translation lags.
5. **P9 + P10.** LIVE. **Gated on `host-expert-7`** (keys withheld while a modal is open), by M.8.2's
   rule that nothing adding a clickable control ships before it.
6. **P11.** Instrumentation last, written against the finished table.

[INFERENCE] **A release note this requires.** After P3, a `setup.ini` written by v125 still loads —
`[setup]`'s fourteen keys are unchanged — but after P4 a run that never opens the form stops
inheriting that file. For a user whose habit was to configure once through the form and then run with
`InpPickStart=false`, **the settings they were silently inheriting will stop arriving**. That is the
correct behaviour and it is still a behaviour change; it belongs in the note beside M.3.3's
`panel.ini` `tab` key note.

---

### P.12 What this settings design refuses to do

* **It will not add a SETTINGS destination.** M.3.2 rejected it for want of data; ten live settings
  do not change that answer, and the spare rail cell stays spare.
* **It will not make the cost model editable in-session.** Balance, commission, slippage, swap,
  margin, stop-out, spread, ticks per bar and spread mode are FILE, on the authority of the comment
  at `SSReplayStandalone.mq5:1157-1159`. The setters exist; P declines them.
* **It will not let a file answer a consent question.** `InpPublish`, `InpAllowControl`,
  `InpAllowTrade` and `InpSlot` stay inputs (P.4.1).
* **It will not let a settings surface edit a running evaluation.** The verb for the Challenge group
  is `ResetEvaluation()`, which voids the run, and that is the honest verb.
* **It will not grow the form.** 51 settings at a *lower* `SSR_SETUP_H_MAX` than today, or the design
  is wrong (P.8.4).
* **It will not build a second combo box, a scrollbar, a slider, a tooltip or a tree.** Five row
  kinds, all of them widgets that already ship.
* **It will not delete an input.** The inputs dialog stays a complete and working way to configure
  this product, exactly as `SSR_SetupPanel.mqh:16-21` promises. P changes what else is possible, not
  what already works.
* **It will not claim a runtime behaviour.** Every line number above is a literal or a constant read
  from source; nothing in this section has been run on MT5, and the px/char figures behind the 38-
  and 16-character row budgets are estimates MQL5 will not confirm.

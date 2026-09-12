# SS Replay — Complete Technical Overview
### A MetaTrader 5 Market Replay / Backtesting Platform
**Build v125 · 2026-09-12 · MQL5 · 123 files · 51,278 lines**

> Written to be handed to another model for analysis. Every number and
> name here was extracted from the code, not recalled. Where something
> was *measured*, it says so; where it is a claim the code makes about
> itself, it says *documented*.

---

## 1. What this is

A **manual replay / backtest platform** for MetaTrader 5, written in MQL5,
built for a trading academy. The user picks a historical window and the
platform plays it back **as if it were the live market**: candles build one
at a time, they can pause, step, change speed, and take **virtual trades**
that never reach a broker.

The difference from MetaTrader's own Strategy Tester: that tests an
algorithm; this **trains a human**.

---

## 2. Hard constraints (upheld throughout the codebase)

These are the project's stated prohibitions, and the whole architecture is
shaped around them:

| Constraint | Status |
|---|---|
| **No fake candle drawing** | Upheld — candles are written into a real **custom symbol** with `CustomRatesUpdate` / `CustomTicksAdd`, and MetaTrader itself draws them |
| **No object-based candle rendering** | Upheld — no candle is ever drawn with a graphical object |
| **No web UI** | Upheld — the entire interface is native MQL5 objects |
| **No monolithic EA** | Upheld — 12 separate layers, **74 classes** |
| **No hardcoded symbol / broker / strategy logic** | Upheld — everything comes from an input or from `SymbolInfo*` |
| **Virtual trades must never reach the broker** | **Verified**: `grep -rn "OrderSend\|CTrade\|PositionClose"` across the entire codebase returns **no call at all** — only comments stating none exists |
| **No performance claim without measurement** | Upheld — 17 measurement spikes (13 scripts + 2 services + 2 indicators) |

---

## 3. The data path, end to end

```
Broker history (M1)
      │  CSSRMt5DataSource / CSSRMt5HistoryProvider
      ▼
CSSRReplayController  ── the engine
      │  ├─ CSSRReplayClock      the virtual clock
      │  ├─ CSSRReplayTimeline   window, warmup, boundaries
      │  ├─ CSSRReplayCursor     where in the window we are
      │  ├─ CSSRTickSynthesizer  one M1 bar → N ticks
      │  ├─ CSSRPumpBudget       how many bars per timer beat
      │  └─ CSSRFidelityPolicy   full tick / synthetic / bar
      ▼
CSSRCustomSymbolSink ── writes into
      ▼
Custom Symbol  (e.g.  US30.U26  or  EURUSD.R1)
      │  CustomRatesUpdate  (the seed, in bulk)
      │  CustomTicksAdd     (live playback, tick by tick)
      ▼
MetaTrader builds the bars and draws the chart itself
      │
      ├─► CSSRChartManager    charts, follow, leak guard
      ├─► CSSRTradingEngine   the virtual account (OnTicks)
      └─► CSSRStrategyHost    optional strategy
```

**The central architectural bet:** the engine writes **M1 only**. MetaTrader
derives M5/H1/H4/D1 from that same M1. This is the product's core claim and
it is measured in spikes `SSR_A2` and `SSR_D1`.

---

## 4. Layers and size

| Layer | Files | Lines | What it does |
|---|---:|---:|---|
| **Core** | 19 | 5,051 | Replay engine, clock, cursor, tick synthesis, snapshots |
| **Ui** | 18 | 10,312 | Panel, dialogs, cards, theme, widgets, strings |
| **Trading** | 8 | 4,774 | Virtual account, risk, journal, statistics, prop eval |
| **Data** | 9 | 2,352 | Data source, history catalogue, calendar, validation |
| **Chart** | 6 | 1,881 | Chart management, trade lines, blind mode, leak guard |
| **Common** | 10 | 1,673 | Time, log, flight recorder, naming, RNG |
| **Mt5** | 3 | 1,461 | Custom symbol manager, sink, seed cache |
| **Strategy** | 4 | 1,158 | Strategy host + one reference implementation |
| **Integration** | 3 | 896 | Publish session state to other products |
| **Report** | 2 | 825 | Class report (HTML) |
| **Session** | 1 | 415 | Save / resume a session |
| **Expert** | 1 | 3,255 | `SSReplayStandalone.mq5` — the host |

---

## 5. The replay engine (Core)

### Principal classes
- **`CSSRReplayController`** — the heart. Seeds history, pumps ticks, steps
  forward and back, jumps, bookmarks, snapshots.
- **`CSSRReplayGroup`** (`SSR_MasterClock.mqh`) — keeps several symbols on one
  clock (up to 3 extra symbols).
- **`CSSRTickSynthesizer`** — turns one M1 bar into N ticks, walking
  O→H→L→C or O→L→H→C depending on the bar's shape.
- **`CSSRFutureGuard`** — guarantees no "future" candle is ever left on the chart.
- **`CSSRSnapshotStore`** — for fast rewinding.
- **`CSSRPumpBudget`** — caps the work done per timer beat (default 40 ms).

### Three tick-fidelity levels (`ENUM_SSR_FIDELITY`)
| Level | What it does | Effect |
|---|---|---|
| `FULL_TICK` | The broker's real ticks, one for one | Most realistic, slowest |
| `SYNTHETIC_TICK` | N synthesised ticks per M1 bar (`InpTicksPerBar`, default 8) | The balance |
| `BAR` | One tick at each bar close | Fastest, **no intrabar movement** |

⚠️ This setting decides **whether a stop can be hit intrabar at all.**

### The speed ladder
20 stops, from `0.1x` to `SSR_SPEED_MAX`: 0.1, 0.25, 0.5, 0.75, 1, 1.5, 2, 3,
4, 5, 7, 10, 15, 20, 30, 50, 75, 100, 200, MAX.

---

## 6. The virtual trading account (Trading)

`CSSRTradingEngine` is a `CSSRTickObserver`: it receives every tick and
updates the account. **There is no `OrderSend` anywhere — verified by grep
across the whole codebase.**

Modelled:
- Balance, equity, margin (`InpMarginLot`), stop out (`InpStopout`)
- Commission per lot per side (`InpCommission`)
- Slippage, **always adverse to the user** (`InpSlippage`)
- Overnight swap, separately for long and short
- Spread: either taken from the bar itself (`SSR_SPREAD_RECORDED`) or a fixed number
- Pending orders, SL/TP, break-even, trailing stop, partial close

### The modules around it
- **`CSSRRiskEngine`** — computes lot size from risk percent and stop distance
- **`CSSRJournal`** — writes every trade to CSV
- **`CSSRStatsEngine`** — the full statistics set (below)
- **`CSSRPropEvaluation`** — simulates a prop-firm evaluation
- **`CSSRTradeAutoPause`** — auto-pause on fill / stop / target / new session
- **`CSSRShotBook`** — automatic screenshot at every entry and exit

### Statistics computed
`trades`, `win_rate`, `loss_rate`, `profit_factor`, `expectancy`,
`gross_profit`, `gross_loss`, `average_win`, `average_loss`,
**`average_R`** and `r_trades`, `max_drawdown` (on the equity curve),
`max_drawdown_closed` (on the balance curve only), `avg_hold_sec`,
`time_in_market_pct`, `recovery_factor`, **`risk_spread_pct`** (how much the
risk per trade varied — zero means identical every time), **`revenge_trades`**
(opened straight after a loss), `avg_spread_points`, `worst_spread_points`,
`wide_spread_trades`.

The last two named are unusual and deliberate: **revenge trades** and **risk
dispersion** are coaching metrics, not performance metrics.

---

## 7. The interface layer

### The main panel — `SSR_Panel.mqh` (the largest file in the project)
Two layouts behind one compile-time switch:
- **`SSR_LAYOUT_RAIL`** (active): 310×336 px, tabs standing in a 44 px vertical rail
- Without it: 420×336, horizontal tabs, a 104 px side column

Three palettes behind another switch: `SSR_THEME_RAIL` (dark/amber, active),
`SSR_THEME_LIGHT` (white), `SSR_THEME_DARK` (dark/blue).

**Panel rows:** caption 23 → clock+progress 32 → transport 27 → speed 21 →
action strip 21 → sheet 186 → status 18.

**Tabs:** Trade / Positions / Stats / Session (+ Prop when an evaluation is on)

### Other UI components
`CSSRSetupPanel` (the setup window), `CSSRRangeDialog`, `CSSRSessionDialog`,
`CSSRKeyCard`, `CSSRRevealCard`, `CSSRReviewCard`, `CSSRFirstRun`,
`CSSRTradeLines` (draggable stop/target lines), `CSSRCalendarLines` (news
lines), `CSSRBlindMode`.

### i18n
`SSR_Strings.mqh` — **190 strings**, enum-indexed. The language file
`MQL5/Files/SSReplay/lang/fa.txt` carries **190/190 Persian translations**.
Loaded with `FILE_BIN` + `CharArrayToString(..., CP_UTF8)`.

### Keyboard shortcuts (one table drives both the handler and the printed card)
`Space` play/pause · `←/→` one candle · `PgUp/PgDn` ten candles · `+/-` speed ·
`R` SL/TP lines · `Tab` take the trade · `X` flip the lines · `J` jump ·
`B` bookmark · `S` sessions · `F` bring charts back · `D` tick detail ·
`0` reset · `A` session review · `P` tall panel · `H` key card

---

## 8. Persistence and outputs

| Path (under `MQL5/Files/`) | Contents |
|---|---|
| `SSReplay\sessions\` | Saved sessions (resume where you left off) |
| `SSReplay\journal\` | Trade CSV |
| `SSReplay\journal\shots\` | A PNG of the chart at every entry and exit |
| `SSReplay\positions\` | Open positions, for recovery |
| `SSReplay\cache\` | Seed cache (so the next session builds faster) |
| `SSReplay\class\` | HTML class report |
| `SSReplay\lang\fa.txt` | Language file |

There is also a **flight recorder** (`CSSRFlightRecorder`) writing a black-box
file for the session — for when a user reports a fault.

---

## 9. The 61 expert inputs

```
--- Session -----------------------------------------------------------
InpSymbol="", InpStart=0, InpReplayBars=2000, InpWarmupBars=1000,
InpChartTf=PERIOD_M5, InpSlot=1, InpTicksPerBar=8,
InpSpreadPoints=20, InpSpreadMode=SSR_SPREAD_RECORDED, InpPumpMs=40,
InpStartSpeed=30.0
--- Virtual account ---------------------------------------------------
InpBalance=10000, InpCommission=0, InpSlippage=0, InpSwapLong=0,
InpSwapShort=0, InpMarginLot=0, InpStopout=0
--- Practice ----------------------------------------------------------
InpAlsoSymbols="", InpExtraTfs="", InpRandom=false, InpSeed="",
InpBlind=SSR_BLIND_OFF, InpPauseEntry=false, InpPauseSL=true,
InpPauseTP=true, InpPauseSession=SSR_SESSION_OFF
--- Persistence -------------------------------------------------------
InpSession="", InpResume=true
--- Strategy (optional) -----------------------------------------------
InpRefStrategy=false, InpStratTf=PERIOD_M15, InpStratLookback=20,
InpStratRisk=0.5
--- Integration -------------------------------------------------------
InpPublish=true, InpAllowControl=false, InpAllowTrade=false
--- UX ----------------------------------------------------------------
InpRiskPercent=0.5, InpAutoHistory=true, InpHistoryBars=60000,
InpPickStart=true, InpOneChart=true, InpTradeLines=true,
InpStopPoints=0, InpRR=2.0, InpVitals=true, InpFlightRec=true,
InpTradeHistory=true, InpShots=true, InpAutoPlay=true,
InpFirstCard=true
--- News --------------------------------------------------------------
InpNews=SSR_NEWS_MODERATE, InpNewsPause=0, InpNewsShift=0
--- Prop evaluation ---------------------------------------------------
InpProp=false, InpPropTarget=8.0, InpPropDaily=5.0, InpPropTotal=10.0,
InpPropTrail=false, InpPropMinDays=3, InpPropMaxDays=30
--- Language ----------------------------------------------------------
InpLanguage=""
```

**Open item:** the setup panel surfaces only a small fraction of these 61
inputs. There is no bridge between "Settings" and the rest — they can only be
changed from MetaTrader's own Inputs dialog. Documented, not hidden.

---

## 10. The quality machinery

| Tool | Count | Purpose |
|---|---:|---|
| **Tests** (`Scripts/SSReplay/Tests/`) | 15 | T1..T15 — engine, data, custom symbol, chart, UI, history, performance, navigation, trading, statistics, advanced replay, session, strategy, integration, UX |
| **Spikes** (Scripts 13 + Services 2 + Indicators 2) | 17 | Phase 0 measurements: symbol lifecycle, bar aggregation, future isolation, tick broadcast, throughput, session behaviour, broker data audit, IPC, replay clock, seed performance, timeframe switching, sustained run, rewind cost |
| **Audits** (`tools/ssr_audit.py`) | **21** | Static, across all 123 files |
| **QA** (`Scripts/SSReplay/QA/`) | 5 | Preflight, Smoke, FontProbe, Cleanup, Gaps |

### Audits worth naming
- **A17** — no colour may be written anywhere but `SSR_Theme.mqh`
- **A18** — WCAG contrast, **computed rather than eyeballed**; 49 declared
  pairs, checked against whichever palette is being built
- **A19** — no text may be drawn from a literal (it must come through
  `T(SSR_S_*)`), and no string may exceed 63 characters (MetaTrader's draw limit)
- **A20** — every render function must call `ChartRedraw`
- **A21** — a bar count on any timeframe other than M1 must be primed first

All pass with **123 files, zero findings**, in each of the three palette
switch positions.

---

## 11. Technical lessons taken from real defects

Useful for an analyst, because these are genuine MQL5 traps:

1. **MetaTrader draws exactly 63 characters of `OBJPROP_TEXT`** and errors on
   nothing. (At least five separate defects in this project.)
2. **Creation order is the only z-order MQL5 has.**
3. **`ObjectCreate` refuses a name that already exists** — a label and a button
   sharing an id means the button is never created.
4. **`ObjectSet*` is expensive** — measured: 561 property writes = 39.05 ms per
   repaint. Solved with a property cache (512 slots, FNV-1a).
5. **`FileOpen(..., FILE_TXT|FILE_ANSI)` returns one character per byte** —
   UTF-8 Persian becomes mojibake. The correct read is `FILE_BIN` + `CP_UTF8`.
6. **`SYMBOL_CHART_MODE` decides what a symbol builds bars from.** Forex =
   `BID`; index/futures CFD = `LAST`. `CustomTicksAdd` **accepts** a tick that
   carries nothing the chart mode can use and builds no bar. (Measured: 481
   ticks accepted, 0 bars built.)
7. **MetaTrader builds a timeframe series lazily** — the first read always
   returns zero, and zero there means "no series yet", not "no bars". This cost
   an entire build.
8. **MQL5 has none of these:** combo box, scrollbar, clipping, layout engine,
   bidi text, accessibility tree.

---

## 12. Known limitations (open and documented, not hidden)

- **RTL layout** is not implemented (phase 10b) — strings are translated but
  the layout is still LTR
- **No user-facing text-size control**
- **Settings bridge**: most of the 61 inputs are unreachable from the setup panel
- **Jump** only works inside the already-loaded session; it cannot load new history
- **The panel cannot be dragged** — it lives on a chart the program is not
  attached to and receives no mouse coordinates. (The move button was removed
  at the user's request in v125, so it can no longer be moved at all.)
- **The command palette** was removed in v125 and had no key binding, so it is
  now unreachable

---

## 13. Development environment (important context for analysis)

- Development happens in a Linux container; **MetaTrader 5 is not installed
  here and cannot be** — the egress proxy refuses `download.mql5.com` and every
  MetaQuotes host with **HTTP 403** (organisational policy, measured at the gateway).
- Compilation runs **MetaEditor64.exe under Wine 9.0** (the user uploaded the
  file themselves). `tools/ssr_compile.sh` builds all 39 programs.
- **This means none of this code has ever been run on a real MetaTrader
  terminal by its author.** Only the user can test it. That is why the
  measuring instruments are built into the product itself: the flight
  recorder, the vitals line, and — since v124 — a **layout overflow detector**
  that reports if anything is drawn outside the panel's own frame.

---

## 14. Questions worth asking about it

If another model is to analyse this, these are the questions that would
produce something useful:

1. **Architecture**: is writing M1 only and letting MetaTrader derive the
   higher timeframes the right bet? What does it cost and what does it buy?
2. **Simulation accuracy**: with `SYNTHETIC_TICK` at 8 ticks per bar, how large
   is the stop-simulation error? When is `FULL_TICK` actually necessary?
3. **Teaching**: are the computed statistics — particularly `average_R`,
   `risk_spread_pct` and `revenge_trades` — enough for coaching? What is missing?
4. **UX**: a 310×336 panel with four tabs — is the information architecture right?
5. **Technical risk**: where in this codebase is failure on a real terminal most
   likely, given that the author cannot run it?
6. **Quality**: 21 static audits + 15 tests + 17 measurement spikes — what class
   of bug is still uncovered?

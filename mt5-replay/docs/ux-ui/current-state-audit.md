# SS Replay — Current State Audit

Build audited: **v103**. 44,387 lines of MQL5 across 117 source files and 39 entry
points. Nothing in this document is inferred; every claim was read out of the
source or measured on the user's terminal.

---

## 0. What this product actually is

A native MetaTrader 5 market-replay and practice platform. It reads real broker
M1 history, creates a **custom symbol**, and writes bars and ticks into it with
`CustomRatesUpdate` / `CustomTicksAdd`. MetaTrader renders those candles itself.

That single decision is the product's foundation and its main competitive fact:
because the replay symbol is a *real* symbol, every indicator, template, object
and timeframe the user already owns works on it unchanged.

**Nothing is drawn as a fake candle. Virtual trades are never sent to a broker.**

---

## 1. Architecture map

| Layer | Files | Lines | Role |
|---|---:|---:|---|
| `Common/` | 10 | 1,654 | types, time, platform, naming, flight recorder |
| `Core/` | 19 | 5,029 | replay controller, clock, tick synthesizer, seek |
| `Data/` | 9 | 2,352 | data sources, validation, calendar, future guard |
| `Mt5/` | 3 | 1,297 | custom symbol manager, sink, seed cache |
| `Chart/` | 6 | 1,856 | chart manager, trade lines, blind mode, calendar lines |
| `Trading/` | 8 | 4,691 | trading engine, risk, statistics, journal, shot book |
| `Ui/` | 12 | 6,363 | panel, setup panel, dialogs, widgets, theme, keys |
| `Session/` | 1 | 415 | save / restore |
| `Report/` | 2 | 825 | class report |
| `Strategy/` | 4 | 1,158 | reference strategy (a template, not advice) |

### The most important architectural fact for this project

`Ui/SSR_ReplayPort.mqh` defines a **port**: ~45 verbs the UI may ask of the
engine (`Play`, `Pause`, `StepBars`, `SeekTo`, `Buy`, `Sell`, `OpenFromLines`,
`ClosePartial`, `BreakEvenAll`, `SetTrailing`, `SetRiskPercent`, `ArmLines`,
`JumpTo`, `Bookmark`, `SaveSession`, `ExportStatement`, `SetFidelity`, …), plus
`ReadState()` which fills one `SSRUiState` struct.

Three implementations exist: `CSSRReplayPort`, `CSSRGroupPort` (multi-stream),
`CSSRDirectPort`.

**Consequence: the entire UI can be rebuilt against this port without touching
the replay engine, the trading engine, or the data layer.** That is what makes a
redesign of this scale safe. It is also the boundary this project must not
casually cross.

`Ui/SSR_DirectPort.mqh` is included by nothing and compiles never. Dead.

---

## 2. Current screens

There are three, and only three.

### 2.1 Setup panel — `SSR_SetupPanel.mqh` (944 lines)

Opens on the origin chart when the expert starts. Since v100 it is a two-step
wizard: **SETTINGS** (17 rows across ACCOUNT / REPLAY / EVALUATION / SESSION)
then **WHERE TO START** (recap of every choice, the orange line, `START REPLAY
HERE`, `Back`).

Draggable by its caption since v101. Position persists in a `GlobalVariable`.
Timeframe / blind / preset / prop-on are dropdown lists since v101.

### 2.2 Control panel — `SSR_Panel.mqh` (2,083 lines)

420 × 336 px. Seven stacked rows: caption, clock+progress, transport, speed,
tabs, sheet, status. Four tabs (Trade / Positions / Stats / Session) plus a
six-button side column that is always visible.

Three size states: **full** (≥360 px chart), **compact** (drops tabs and sheet,
keeps everything operated), **collapsed** (caption only). Draggable by caption;
`[]` steps between corners; position persists to `panel.ini`.

### 2.3 Modals — `SSR_SessionDialog.mqh` (310), `SSR_RangeDialog.mqh` (308)

Sessions list and jump-to-range. Genuinely modal since v102: the panel neither
polls nor repaints while one is up.

Plus two transient cards: `SSR_FirstRun` (once, ever) and `SSR_KeyCard` (`H`).

---

## 3. Feature → UI → component → risk map

| Feature | Current UI | Component | Risk of change |
|---|---|---|---|
| Playback | 7 transport buttons | `SSR_Panel::DrawTransport` | **Low** — pure view over port verbs |
| Speed | −/+/box/20-cell ladder | `SSR_Panel::DrawSpeed` | **Low** |
| Progress / clock | text + bar | `SSR_Panel::DrawClock` | **Low** |
| Risk sizing | ± stepper on Trade tab | `SheetTrade` → `SetRiskPercent` | **Low** |
| SL/TP as chart lines | draggable objects | `SSR_TradeLines` (607) | **HIGH** — drag maths, side inference |
| Pending orders | 3rd line + named button | `SSR_TradeLines` + `OpenFromLines` | **HIGH** |
| Position management | Positions tab rows | `SheetPositions` | Medium |
| Trailing / break-even | ± row, buttons | `SheetPositions` → port | Low |
| Setup tag | `OBJ_EDIT` on Trade tab | `SheetTrade` + `ReadTag` | Medium — edit-box focus rules |
| Statistics (43) | Stats tab shows ~10 | `SSR_Statistics` (engine) | **Low to surface, none to compute** |
| Statement HTML | button on Stats tab | `SSR_Journal` | Low |
| Sessions | side button → modal | `SSR_SessionDialog` | Medium |
| Bookmarks | side button | port `Bookmark` | Low |
| Jump | side button → modal | `SSR_RangeDialog` | Medium |
| Blind mode | setup row + `D`-adjacent | `SSR_BlindMode` (261) | Medium — must be reversible |
| Fidelity | side button cycles | port `SetFidelity` | Low |
| Prop evaluation | 3 setup rows + preset | `SSR_PropEvaluation` | Low to surface |
| Calendar | lines on chart | `SSR_CalendarLines` | Low |
| Screenshots | automatic | `SSR_ShotBook` | None (no UI today) |
| Random + seed | **expert inputs only** | none | None (no UI today) |
| Journal CSV | automatic on close | `SSR_Journal` | None |
| Class report | separate script | `SSR_ClassReport` | None |

---

## 4. Problems

Each: **Problem → Why it matters → Severity → Direction.**

### P1 — The panel is the product

**Problem.** Everything except the chart lives in one 420×336 box: playback,
trading, positions, statistics, session, and six side buttons. Depth is
expressed only by four tabs.
**Why it matters.** A beginner meets every feature at once. A professional
cannot get any of it out of the way. Neither is served.
**Severity: Critical.**
**Direction.** Adaptive panel modes (Compact / Standard / Pro) with real
progressive disclosure, not a single density.

### P2 — There is no analysis surface

**Problem.** The engine computes **43 statistics** including MAE/MFE, revenge
trades, risk dispersion, time in market, recovery factor, spread at entry and
"trades without a stop". The Stats tab shows about ten of them; the rest exist
only inside an exported HTML file.
**Why it matters.** This is the product's deepest asset and it is nearly
invisible. A trader closes the session and never sees why they lost.
**Severity: Critical.**
**Direction.** A dedicated Review experience after a session, and an Analysis
area during it.

### P3 — Random start and seed have no UI at all

**Problem.** `InpRandom` and `InpSeed` exist as expert inputs. Seed makes a
session **exactly reproducible** — the basis of coaching, challenges and honest
strategy testing.
**Why it matters.** The single most differentiating training feature is
unreachable without opening the inputs dialog.
**Severity: High.**
**Direction.** First-class "Random practice" mode with a visible, copyable,
shareable session seed.

### P4 — Blind mode is a settings row

**Problem.** A major training discipline is a dropdown with `off / standard /
full`, and there is no reveal-and-review moment at the end.
**Why it matters.** Blind practice without a reveal is practice without
feedback.
**Severity: High.**
**Direction.** A named mode chosen at setup, a persistent in-session indicator,
and a `REVEAL` step at completion.

### P5 — Prop evaluation has no dashboard

**Problem.** Four rules are enforced correctly and reported as one state string.
There is no view of progress toward the target, distance to the daily limit, or
days remaining.
**Why it matters.** A challenge simulator whose rules are invisible cannot
rehearse the pressure that makes challenges hard.
**Severity: High.**
**Direction.** A Prop area with progress bars against each of the four rules.

### P6 — 54 expert inputs, 13 setup fields, no bridge

**Problem.** Commission, slippage, swap, margin, stop-out, extra symbols, pause
rules, shot capture, calendar behaviour and the reference strategy are reachable
only through MetaTrader's own inputs dialog.
**Why it matters.** The realism controls that make the simulator credible are
the ones hardest to reach.
**Severity: Medium.**
**Direction.** A Settings area covering the inputs that change *behaviour*,
leaving deployment-time inputs where they are.

### P7 — No command surface

**Problem.** 20 keyboard bindings exist and are discoverable only via `H`.
Everything else is hunt-the-button.
**Why it matters.** Professional software is driven from the keyboard.
**Severity: Medium.**
**Direction.** A searchable command palette. **Feasible in MQL5** — `OBJ_EDIT`
for the query plus a filtered column of `OBJ_BUTTON` rows is exactly how the
v101 dropdowns already work.

### P8 — Strings are hard-coded in English at every draw site

**Problem.** Every label is a literal inside a draw call. The user base is
Persian-speaking; the product is aimed at global release.
**Why it matters.** Localisation later means touching every UI file.
**Severity: Medium.**
**Direction.** One string catalogue keyed by symbol, resolved at draw time.
RTL is a deeper problem — see `localization.md`.

### P9 — Accessibility is colour-only in places

**Problem.** Long/short, degraded fidelity and enabled/disabled are carried
partly by colour alone.
**Severity: Medium.**
**Direction.** Every state carries a second channel — glyph, weight or text.

### P10 — Error and empty states are inconsistent

**Problem.** Some refusals are excellent ("the entry line is on the price — drag
it away from here"). Others print to the Experts log where nobody looks.
**Severity: Medium.**
**Direction.** One status channel with a defined severity ladder.

### P11 — The setup wizard cannot be skipped

**Problem.** An expert who runs the same configuration daily still walks two
steps.
**Severity: Low.**
**Direction.** Quick-start actions: continue last session, repeat last settings,
random session.

---

## 5. Components that must NOT be casually rewritten

| Component | Why |
|---|---|
| `SSR_TradeLines.mqh` | Side inference from geometry, drag maths, the v79 bug where a stop distance flipped a short back to long. Six smoke checks guard it. |
| `SSR_TradingEngine.mqh` | Execution honesty: a touched stop is a market order, filled at the worse of level and touch price, slippage always adverse. |
| `SSR_ChartManager.mqh` | Follow/detach voting and the v103 snap rule. Both were defect fixes with measurements behind them. |
| `SSR_CustomSymbolManager.mqh` | Teardown order and the two pauses that closed a five-round hang and the works-once bug. |
| `SSR_Panel::HideSheets` | Runs 25×/s; the setup tag box is hidden, never deleted, or it cannot be typed in. |
| Widget `Edit` first-paint rule | Text is written only on a first paint, so a repaint cannot delete what is being typed. |

## 6. Components safe to redesign

`SSR_Theme.mqh` (tokens only), `SSR_Panel` draw methods (pure views over
`SSRUiState`), `SSR_SetupPanel` layout, both dialogs, `SSR_KeyCard`,
`SSR_FirstRun`, `SSR_Widgets` (additively). `SSR_DirectPort.mqh` is dead and can
be deleted.

## 7. Technical constraints (MQL5, not choices)

1. **Keyboard events reach only the chart the program is attached to.** Every
   other chart polls. This is why the panel has a Move button as well as drag.
2. **Creation order is the only z-order.** Anything drawn later is on top; a
   repainting panel climbs over modals unless explicitly suppressed (v102).
3. **`OBJPROP_TEXT` is cut at 63 characters.**
4. **No combo box, no scrollbar, no clipping, no transitions, no layout engine.**
   Every control is a rectangle, a label, a button or an edit box at absolute
   pixel coordinates.
5. **No ARIA, no focus ring, no screen-reader surface.** Accessibility must be
   delivered through contrast, redundancy and text.
6. **`Sleep` is forbidden in indicators**; all waiting goes through `SSRPause`.
7. **Chart pixel height varies** with the Toolbox; 363 px is the common case.

## 8. Testing and build reality

- **Compiler:** MetaEditor under Wine; 39 programs, currently 0 errors,
  0 warnings.
- **Smoke test:** `SSR_QA_Smoke.mq5`, 187 checks across 31 stages, run on the
  user's terminal. Writes `qa-result.txt`, flushed per line, readable while
  running.
- **Static audits:** `tools/ssr_audit.py`, 16 mechanical checks, silent across
  117 files.
- **Advisory:** `tools/ssr_check_order.py`.
- **No lint, no type checker, no UI test harness.** The layout invariant
  ("nothing drawn outside the frame the panel itself drew") is asserted by the
  smoke test and is the only automated UI test that exists.

## 9. Known open defect

Ticks not building candles on a second run of the same symbol. A mechanism was
found and fixed in v97 (`Destroy()` now waits after deleting a custom symbol)
and stage 31 replays a symbol twice to catch it. **Four runs of correlation, no
green confirmation yet.** Not to be described as solved.


---

# 8. Verdict, after Phases 0–11

Written at the end, against the problems this document opened with. Two of the
eleven were **not fixed**, and they are named as such rather than quietly
dropped.

| | Problem | Severity | Outcome |
|---|---|---|---|
| P1 | The panel is the product | Critical | **Fixed.** What is *consulted* moved to modals — the session review, the reveal card, the command palette, the key card — and what is *operated* stayed on the panel. The rule was written in v98 and every phase since has followed it. |
| P2 | No analysis surface | Critical | **Fixed, Phase 7.** All 43 measures, paged, plus observations that state what was counted and never interpret it. |
| P3 | Random start and seed have no UI | High | **Fixed.** `random_start` and `seed` are setup fields; the seed is shown so a session can be shared. |
| P4 | Blind mode is a settings row | High | **Fixed, Phase 6.** The session ends with the market still hidden and one button that lifts it — the reveal is a deliberate act at a moment the trader chose. |
| P5 | Prop evaluation has no dashboard | High | **Fixed, Phase 8.** Its own tab, one meter per rule, present only while an evaluation is configured. |
| P6 | 61 expert inputs, 14 setup fields, no bridge | Medium | **NOT FIXED — and it got slightly worse.** The count was 54/13 when this was written; it is 61/14 now. Commission, slippage, swap, margin, stop-out, extra symbols, pause rules, shot capture, calendar behaviour and the reference strategy are still reachable only through MetaTrader's own inputs dialog. A Settings area is a phase, not polish, and building one at the end of the redesign — unverifiable, on a surface nobody could look at — would have been the riskiest thing in the whole project. It is the first thing to do next. |
| P7 | No command surface | Medium | **Fixed, Phase 3.** `Ctrl+K`, 29 commands, and no command invents a verb — every entry resolves to a key or a button that already exists. |
| P8 | Strings hard-coded in English | Medium | **Fixed, Phase 10a.** 176 strings, a complete Persian translation, audit A19. |
| P9 | Accessibility is colour-only in places | Medium | **Fixed, Phase 9** — and the pass found 11 of 38 contrast pairs below WCAG AA, including the build tag at 2.06:1. Enforced by audit A18. **One gap stays open and is documented, not faked: no user text-size control.** |
| P10 | Error and empty states inconsistent | Medium | **Fixed, Phase 11.** One strip, five claimants, and the ladder is now written down — armed reset, refused order, refused panel size, standing condition, resting numbers. Writing it down is what exposed the defect: Phase 9 had put the narrow-chart line *above* trade refusals, so on a narrow chart a refused order could never be seen. |
| P11 | The setup wizard cannot be skipped | Low | **Fixed, Phase 4.** Quick-start: same as last time, continue that session, random session, or customise. |

**Also not done, and stated in `localization.md` rather than softened:** RTL
layout. The coordinate mirroring has existed since Phase 2 and is still off,
because Phases 3–9 did not route their draw sites through the layout helper —
exactly what that document warned must not happen. Flipping the flag now would
mirror a handful of sites and leave the rest, on a chart nobody here can see.

**The defect that blocked a final release was found in v120.** It was never
intermittent: `SYMBOL_CHART_MODE` was never set, so a replay symbol cloned from
an index or futures CFD inherited `CHART_MODE_LAST` and built its bars from a
`last` price the engine's ticks never flagged. `CustomTicksAdd` accepted every
one of them and built nothing. Forex symbols are `CHART_MODE_BID` and worked
from the first build, which is why four years of runs looked like luck.

Fixed by forcing `CHART_MODE_BID` on the replay symbol *and* flagging the Last
price the ticks already carried, with both read back and both asserted in the
smoke test ahead of every tick check.

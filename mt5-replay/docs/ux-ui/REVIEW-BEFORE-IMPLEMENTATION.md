# Review Before Implementation

Required by the brief before major implementation. Phases 0 and 1 are complete;
**no product code has been changed.** Phase 2 begins after this is read.

## Current experience

One 420×336 panel carries playback, trading, positions, statistics and session
behind four tabs, plus a six-button rail. A two-step wizard starts a session. Two
modals exist. 43 statistics are computed and about ten are visible. Random start
and seed have no UI at all. Blind mode is a dropdown row. Prop rules are enforced
and never shown as progress. 54 expert inputs are reachable only through
MetaTrader's own dialog.

## Proposed experience

**Seven areas** — Replay, Trade (incl. Positions), Analysis, Training, Review,
Prop, Settings — assigned to the three containers MQL5 actually has:

> **The panel holds what is OPERATED. Modals hold what is CONSULTED. The chart
> holds what is DRAGGED.**

**Three panel modes** — Compact (exists), Standard (exists), Pro (new, additive).

**A command palette** (`Ctrl+K`) as the single discovery surface, built the way
the v101 dropdowns already work.

**A quick-start** ahead of the wizard, and a **Mode** step that decides which
sheets a session gets.

**A Session Review** at the end — the largest single gain, built entirely from
numbers the engine already computes.

## Why it is better

| | Now | After |
|---|---|---|
| Time to first replay | wizard, always | 2 clicks + a drag |
| Statistics visible | ~10 of 43 | all, in one place |
| Seed / random | inputs dialog only | first-class, copyable |
| Blind | a settings row | a mode, with a reveal |
| Prop progress | one state string | four meters |
| Discovery | hunt the button | searchable palette |
| Beginner load | every feature at once | the mode decides |

## Main screens

1. Quick start · 2. Wizard (Market → Mode → Account → Start → Review)
3. Replay workspace, three modes · 4. Command palette
5. Session Review · 6. Analysis · 7. Prop dashboard · 8. Settings

## Component changes

**Safe:** `SSR_Theme` (tokens), panel draw methods, setup layout, both dialogs,
key card, first-run card, `SSR_Widgets` (additive only).
**Not touched:** `SSR_TradeLines`, `SSR_TradingEngine`, `SSR_ChartManager`,
`SSR_CustomSymbolManager`, and the engine behind the port.
**Deleted:** `SSR_DirectPort.mqh` — included by nothing, compiles never.

## Risks

| Risk | Mitigation |
|---|---|
| Palette adds key handling on the one chart that gets keys | New smoke stage; `Esc` always closes |
| Setup rework breaks the edit-box first-paint rule | Round-trip test in both directions |
| New sheets overflow the frame | The layout test already measures every tab |
| Repaint cost grows | Pump 40 ms / paint 100 ms are hard budgets; profile before and after |
| Localization retrofit | Layout helper mandatory from Phase 2 |

## Open decisions — the only ones I will not take alone

**D1 — Does Pro mode widen the panel beyond 420 px?**
A: keep 420 and put the rail inside. B: widen to ~560 on charts over 1200 px.
**Recommendation: A.** The chart is the hero, and 420 already survives every
layout test. B is a later, measured change.

**D2 — Does Session Review interrupt, or wait to be opened?**
A: opens automatically when a session ends. B: the status strip offers it.
**Recommendation: A for Blind and Prop** (the reveal *is* the point), **B for
Standard** — a trader who wants one more session should not be stopped.

**D3 — Do the 54 expert inputs move into a Settings modal?**
A: surface only the ~15 that change behaviour mid-session. B: mirror all 54.
**Recommendation: A.** B rebuilds MetaTrader's own dialog worse.

I will proceed on the recommendations above unless told otherwise. They are
reversible and none of them touch the engine.

## Not claimed

Nothing in this document is implemented. Phase 2 is next.
The candles-from-ticks defect (v97) is still **fix without proof** — four runs
of correlation, no green confirmation.

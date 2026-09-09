# SS Replay — Product Vision

## Positioning

**A professional trading practice and market-replay platform that runs inside
MetaTrader 5.**

Not "an MT5 replay tool". The replay is the mechanism; practice, evidence and
review are the product.

## What makes it credible

Three facts, all already true in the engine, none of which a competitor can
fake cheaply:

1. **Real candles.** The replay symbol is a custom MT5 symbol written with
   `CustomRatesUpdate`/`CustomTicksAdd`. Every indicator and template the trader
   owns works on it.
2. **Honest execution.** A touched stop fills as a market order at the worse of
   its level and the price that touched it, with slippage always adverse. The
   spread the broker recorded for a bar is the spread replayed on it.
3. **Measured, not asserted.** 43 statistics, MAE/MFE, the spread each trade was
   entered at, and an explicit count of trades placed *without a stop*.

The vision follows from those: **the product's job is to turn what the engine
already knows into something a trader acts on.**

## Five users

| | Needs | Must not see |
|---|---|---|
| **Beginner** | Start a replay and press Buy/Sell | Fidelity, seeds, prop rules, 54 inputs |
| **Intermediate** | Structured practice, risk sizing, review | Engine internals |
| **Professional** | Execution control, spread realism, deep statistics | Hand-holding |
| **Prop candidate** | Rules enforced with visible pressure | Anything that hides distance to a limit |
| **Educator / coach** | Repeatable sessions, class comparison | — |

## The three levels

**Level 1 — Simple.** Attach the expert, pick a start, press Start. Under 30
seconds, no documentation. Quick-start actions ("continue last", "same as last
time", "random session") make it under 10.

**Level 2 — Powerful.** Risk sizing, SL/TP by dragging, pending orders, session
save, statistics, blind practice — surfaced when relevant, never all at once.

**Level 3 — Professional.** Fidelity, spread mode, slippage, commission, swap,
stop-out, seeds, prop rules, multi-symbol, multi-timeframe. Reachable in two
actions, never in the way.

## Design tenets

1. **The chart is the hero.** The UI is an instrument beside it. If a pixel does
   not earn its place, it belongs to the chart.
2. **Progressive disclosure over density.** Depth is reached by *going
   somewhere*, not by reading a denser panel.
3. **Say what actually happened.** Show the fidelity that is *running*, not the
   one requested. Say which spread was used. Count the trades with no stop.
4. **Refusals teach.** "The entry line is on the price — drag it away from here"
   is the standard, not "invalid".
5. **Nothing irreversible without a second beat.** Reset asks and names what it
   would destroy. Start is on its own step.
6. **Never claim more than the engine delivers.** Where MQL5 prevents the ideal
   experience, document the gap; do not draw a control that lies.

## Non-goals

- No web UI, no external server.
- No gamification, badges, streaks or scores that flatter.
- No fake candles, ever.
- No real orders, ever.
- No hard-coded symbol, broker or strategy logic.

# SS Replay — User Flows

Each flow lists what happens today, what changes, and which port verbs carry it.
No flow introduces an engine call that does not already exist.

## F1 — First replay (beginner, target < 30 s)

**Today.** Attach → 17-row settings step → recap step → drag line → Start.

**Proposed.** Attach → the wizard opens on **Quick start** with three actions
and a `Customise` link:

```
NEW REPLAY
  ▸ Same as last time        XAUUSD · M5 · $10,000 · 0.5%
  ▸ Random session           a start you have not seen
  ▸ Continue last session    saved 2 hours ago
  Customise…
```

Drag the orange line, press Start. Two clicks and a drag.
*Verbs: none new. `CSSRSetupPanel::Restore` already reads the last settings;
`InpRandom`/`InpSeed` already exist in the engine.*

## F2 — Customised replay (intermediate)

`Customise…` opens the current two-step wizard, unchanged, plus a **Mode** step
between Market and Account:

```
STEP 2  MODE
  Standard        practise normally
  Blind           the future is hidden until you finish
  Prop challenge  rules enforced, progress shown
  Random          a start you have not seen, with a seed you can share
```

The mode chosen here decides which panel sheets exist for the session. **This is
the main progressive-disclosure lever in the product**: a Standard session never
draws a prop meter.

## F3 — Take a trade

**Unchanged, and deliberately so.** `R` drops SL/TP → drag them on the chart →
`Tab` takes it. Size is computed from risk % and the stop distance, rounded
down. A third line turns it into a named pending order.

*Verbs: `ArmLines`, `SetStopPoints`, `OpenFromLines`, `ToggleEntryLine`.*

## F4 — Manage a position

Positions section: per-row close, close all, break-even all, trailing ± / off.
Half-closing below the lot step is refused **with the reason**.

*Verbs: `ClosePosition`, `ClosePartial`, `BreakEvenAll`, `SetTrailing`,
`CloseAll`.*

## F5 — Session ends

**Today.** The clock stops. The status strip shows a reason. Nothing else.

**Proposed — the largest single gain in this redesign.**

```
SESSION REVIEW
  +2.8R   7 trades   57% win   max DD 1.4R

  TIMELINE   09:14 setup · 09:22 trade · 09:31 loss · 09:33 trade · 09:47 win
  Select a trade → entry, exit, SL, TP, risk, R, MAE, MFE,
                   spread at entry, slippage, screenshot

  OBSERVATIONS   from measured fields only
    · 1 of 2 trades opened within 2 minutes of a loss
    · risk varied 87% across the session
    · 0 trades were placed without a stop
```

Every number above is already computed by `SSR_Statistics`. Nothing is inferred,
nothing is coached. If a field has no samples, the line is absent — not zero.

## F6 — Blind session ends

Blind adds one step before F5:

```
SESSION COMPLETE — the market is still hidden
[ REVEAL MARKET ]
```

Reveal calls `SSR_BlindMode::Restore` (exists, and the smoke test asserts the
chart returns exactly as it was), then F5 runs normally.

## F7 — Prop challenge

Panel gains a **Prop** sheet, present only in that mode, with four meters:
profit vs target, today's loss vs daily limit, drawdown vs maximum, days used vs
minimum and deadline. A rewind voids the run — already enforced.

## F8 — Repeat a session (coach / student)

Seed is shown in the caption and copyable from Review. Same seed + same symbol =
the same session. This is the whole basis of the class-report feature, which
already checks that several students ran the *same* window and warns about the
one who did not.

## F9 — Command palette

`Ctrl+K` → type → run. Reaches every verb, including those with no button.
Shows the key beside any command that has one, so the palette teaches the
keyboard instead of replacing it.

## F10 — Something is refused

One ladder, one place: the status strip. `DANGER > REFUSAL > NOTICE > RESTING`.
Refusals say what to do, never "invalid".

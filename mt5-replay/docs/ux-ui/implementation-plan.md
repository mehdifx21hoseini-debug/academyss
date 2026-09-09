# SS Replay — UX/UI Implementation Plan

## Ground rules

1. **The engine is not touched for UI reasons.** All UI work goes through
   `CSSRReplayPort` (~45 verbs) and `SSRUiState`. If a screen needs something
   the port cannot express, the port gains a read-only accessor — never the
   engine a behaviour change.
2. **Nothing is removed.** Every feature in the audit keeps a home.
3. **Each phase ends green**: 39 programs compile with 0 errors and 0 warnings,
   16 audits silent, smoke suite run on the user's terminal.
4. **From Phase 2, all new UI positions through a layout helper**, so RTL later
   is a change to the helper and not to sixty call sites.

## Phases

### Phase 0 — Audit ✅ complete
This document set. No code changed.

### Phase 1 — UX architecture ✅ complete
`product-vision.md`, `information-architecture.md`, `user-flows.md`,
`keyboard-shortcuts.md` (with the conflict audit), `REVIEW-BEFORE-IMPLEMENTATION.md`.

### Phase 2 — Design system ✅ complete
- Split `SSR_Theme.mqh` into tokens and metrics; no literal colour survives
  outside it.
- Add audit A17: **no `C'r,g,b'` outside the theme**. Measure the false-positive
  rate before wiring it in — an audit that cries wolf is worse than none.
- Add primitives: `List`, `Meter`, `Chip`, `Toast`. Additive only.
- Introduce the layout helper (`SSRLayout`) that every new draw site uses.
- **Done.** 16 colours tokenized to zero; A17 added and silent; `List`,
  `Meter`, `Chip`, `Toast` added; `SSR_Layout.mqh` written; smoke stage 32
  measures all of it. 39 programs clean, 17 audits silent.
- **Found on the way:** `SSR_TradeLines` and `SSR_CalendarLines` used theme
  colours without including the theme — they compiled only by include-order
  luck. Both now include what they use.
- **Not yet used by any screen.** Phase 3 is the first consumer.

### Phase 3 — Replay workspace  ◧ partly done
- Panel mode **Pro** (rail + Analysis + palette entry). Compact and Standard
  unchanged.
- **Command palette** (`Ctrl+K`): `OBJ_EDIT` + filtered `List`, built the way
  the v101 dropdowns already work — drawn last, so it is on top.
- Caption becomes a status line: symbol · timeframe · fidelity · mode chips.
- **Done: the command palette.** `SSR_Command.mqh` (28 commands, one table)
  and `SSR_Palette.mqh`. `Ctrl+K` opens, `↑↓` choose, `Enter` runs, `Esc`
  closes. Smoke stage 33, thirteen checks — including that **no command
  invents a verb**, asserted over the whole table at once.
- **Done: the caption is a status line.** Identity · build · state · mode
  chips (fidelity, BLIND, PROP), plus a `K` button so the palette is
  reachable without knowing the key. Fidelity MOVED out of the status strip:
  it is a mode, not a number, and it was sitting among four numbers
  pretending to be a fifth. The symbol is no longer repeated - MetaTrader
  writes it in the chart's own corner, and repeating it would defeat Blind
  mode. New smoke check measures that the chips clear the buttons, which is
  the one row the frame test cannot police.
- **Still open: Pro panel mode.** Deliberately not started - see below.

### Phase 3b — Pro panel mode  ◻ deferred, with a reason

Compact and Standard are height-driven and tested. Pro was specified as
"Standard plus a persistent rail", but the rail is already always visible in
Standard - so that version of Pro adds nothing a user would notice.

The version worth building is a **taller sheet on a tall chart**: Positions
showing more than five rows, Stats showing more than ten of the forty-three
measures. That is a real capability gain, but it means `SSR_SHEET_H` stops
being a constant, every sheet has to ask how much room it has, and the layout
test needs a second branch to measure the tall case.

That is a phase, not a corner of one. It is scheduled after Phase 7, where
the Analysis surface will have established how a sheet asks for space.

### Phase 4 — Setup / onboarding ✅ complete
- Quick-start screen (F1) ahead of the wizard.
- **Mode** step (F2) deciding which sheets the session gets.
- Random + **seed** surfaced, copyable.
- **Done.** Four steps: QUICK → SETTINGS → MODE → START. Quick start offers
  "Same as last time" (only when there is one, and it prints what it will do),
  "Continue <session>" (only when that file exists), "Random session", and
  "Customise…". Two of the three land straight on START.
- **Mode is a shortcut, not a setting.** It writes `blind` / `prop_on` /
  `random_start` and nothing else — there is no `mode` field, because a fifth
  source of truth that must agree with four others is the one that disagrees.
  The step opens on what is TRUE, not on what was last clicked, and the modes
  are deliberately not exclusive: a prop challenge practised blind is a real
  exercise.
- **Random and its seed have a UI at last.** The seed is an `OBJ_EDIT`, not a
  label, because its whole purpose is to leave the machine. Six expert sites
  now read the form instead of the input — including the one deciding whether
  the orange line appears, since a random session has already answered that.
- **`Repaint()` written once.** The first-paint declaration was copied three
  times in `Poll()`; the fourth copy is the one that forgets.
- **Test: stage 16 extended** — twelve fields round-trip, the seed is checked
  on its own so a failure names it, and four mode combinations are asserted.
- 39 clean, 17 audits silent.

### Phase 5 — Trading / position UX ✅ complete
- **THE MERGE WAS DROPPED, and the reason is arithmetic.** Trade content is
  180 px of a 186 px sheet and Positions is 183. A "merge" that fits would be
  a section switch inside one tab — which is what a tab already is. Renaming
  two tabs into one tab with two sections is not a UX improvement, so the
  effort went where it buys something.
- **Done: execution transparency, on the row, while it can still be acted on.**
  `pos_no_stop` and `pos_spread` now travel through the port. A position with
  no stop says **"no stop"** in words on its own row — the statistics have
  counted these since Phase 9 and reported them *after* the session, which is
  the one moment nothing can be done. Otherwise the row carries the spread it
  was entered at, which decides whether a fill was realistic and has never
  been visible outside the exported statement.
- **Done: a fill toast.** A refusal has said why since v98; a success said
  nothing. The `Toast` primitive from Phase 2 gets its first consumer, and the
  status strip keeps carrying standing state instead of being evicted to
  announce a fill. Detected from a ticket the panel has not seen — no engine
  change, no event, no second place that knows about fills.
- **`SSR_TradeLines` untouched**, as promised. All six of its smoke checks
  still pass unchanged.
- **Test: stage 35** drives both facts through the port, because a field the
  engine fills and the panel reads is only proved by the thing in between.
- 39 clean, 17 audits silent.

### Phase 6 — Training ✅ complete
- **The chip shipped in v106, the seed in v107.** What was left was the
  moment.
- **Done: the reveal.** Blind mode has restored the chart when the EXPERT WAS
  REMOVED since Phase 8, so a trader who wanted to know what they had been
  reading had to end the session to find out — losing the chart, the positions
  and their own reasoning on the way. That is a training feature with no
  feedback loop.
- The session finishes, the market **stays hidden**, and a card says so with
  the one button that lifts it. `CSSRRevealCard` draws the question and never
  answers it: the host owns the blind, so one place decides what revealing
  means.
- **It decides WHEN, never WHETHER.** `OnDeinit` still restores every chart
  whatever happened, so a user who closes the terminal mid-card gets their
  settings back exactly as before.
- **Test: stage 36** asserts the market is still hidden while the card is up,
  that dismissing the card is not answering it, and that the chart comes back
  exactly as it was — the promise the whole mode rests on.
- 39 clean, 17 audits silent.

### Phase 7 — Review / journal / analytics
- **Session Review** modal (F5): headline, timeline, per-trade detail with
  screenshot, observations from measured fields only.
- Analysis surfaces all 43 statistics.
- **Risk: low to the engine, high in value.** Everything shown already exists.
- **Test: assert every observation line has a sample count behind it.**

### Phase 8 — Prop evaluation
- Prop sheet with four meters (F7), present only in that mode.
- **Risk: low.** Rules are already enforced and tested by five smoke checks.

### Phase 9 — Responsive + accessibility
- Pro mode breakpoint at 720 px.
- Contrast pass on every token against the face.
- Second channel for every colour-carried state (audit table in
  `accessibility.md`).
- **Open gap: no user text-size control.** Documented, not faked.

### Phase 10 — Localization
- `SSR_Strings.mqh` catalogue; every draw site calls `T(key)`.
- RTL as a coordinate-mirroring mode through the Phase 2 layout helper.
- **Risk: high in breadth, low in depth** — mechanical, but touches every file.

### Phase 11 — Polish and performance
- Profile the pump loop before and after. The engine pumps every 40 ms and the
  panel repaints at 100 ms; **neither budget may grow.**
- Delete `SSR_DirectPort.mqh` (dead).

## Sequencing decisions

**Phase 7 before Phase 8** even though the brief lists prop earlier: Review is
the largest gain per unit of risk, and the prop dashboard reuses the `Meter`
primitive that Review's drawdown display needs.

**Phase 10 last, but its constraint applies from Phase 2.** Retrofitting a
layout helper after five phases of new UI would cost more than the feature.

## What is explicitly out of scope

- Rewriting the replay engine, trading engine or data layer.
- Changing execution, risk, slippage, spread or prop rule semantics.
- Any UI that implies a capability MQL5 does not have.

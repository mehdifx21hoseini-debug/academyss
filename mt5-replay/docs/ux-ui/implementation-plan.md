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

### Phase 3 — Replay workspace  ◻ next
- Panel mode **Pro** (rail + Analysis + palette entry). Compact and Standard
  unchanged.
- **Command palette** (`Ctrl+K`): `OBJ_EDIT` + filtered `List`, built the way
  the v101 dropdowns already work — drawn last, so it is on top.
- Caption becomes a status line: symbol · timeframe · fidelity · mode chips.
- **Risk: medium** — the palette is new input handling on the one chart that
  receives keys.
- **Test: new smoke stage — palette opens, filters, runs a verb, closes.**

### Phase 4 — Setup / onboarding
- Quick-start screen (F1) ahead of the wizard.
- **Mode** step (F2) deciding which sheets the session gets.
- Random + **seed** surfaced, copyable.
- **Risk: medium** — `SSR_SetupPanel` is 944 lines and holds the edit-box
  first-paint rule.
- **Test: extend stage 16 — every field survives the round trip through all
  steps, in both directions.**

### Phase 5 — Trading / position UX
- Trade and Positions merge into one sheet with a section switch.
- Execution transparency row: spread at entry, slippage applied, fill type.
- **`SSR_TradeLines` is not rewritten.** Chart-side behaviour is untouched.
- **Risk: medium.** Guarded by six existing smoke checks.

### Phase 6 — Training
- Blind as a chosen mode with a persistent chip and a **REVEAL** step (F6).
- Random practice with a visible seed.
- **Risk: low** — `SSR_BlindMode::Restore` already exists and is tested.

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

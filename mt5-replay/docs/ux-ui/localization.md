# SS Replay — Localization

## Current state

Every user-facing string is an English literal at its draw site, across ~6,300
lines of UI. There is no catalogue, no locale, no RTL support.

The current user base is Persian-speaking. The product is aimed at global
release. Both facts point the same way.

## What MQL5 gives us

- `StringFormat`, UTF-16 strings, and fonts by name. Persian and Arabic glyphs
  render if the font has them (`Tahoma` does).
- **No bidi layout.** MetaTrader draws an `OBJ_LABEL` left-to-right from its
  anchor. There is no `dir="rtl"`.
- **No text measurement API.** Column widths cannot be computed from the string.
- `OBJPROP_TEXT` is cut at 63 characters regardless of script.

## Decision: catalogue now, RTL as a layout mode later

**Phase 10a — string catalogue (safe, mechanical).**
One header, `SSR_Strings.mqh`, mapping a stable key to a string, with the active
language selected once at start. Every draw site calls `T("panel.play")`.

This is worth doing before the redesign spreads new literals across new files.

**Phase 10b — RTL.** Not a translation problem, a layout problem. Because there
is no bidi engine, an RTL panel means **mirroring the coordinate system**: every
`x` becomes `panel_width - x - width`, right-aligned labels become left-aligned,
and the side rail moves to the other edge.

That is achievable only if every draw site computes `x` through one helper
rather than writing arithmetic inline. **Therefore: from Phase 2 onward, all new
UI code positions through a layout helper, so RTL later is a change to the
helper and not to sixty call sites.**

## Formatting

| Kind | Rule |
|---|---|
| Dates / times | Always the **broker's server time**, never the user's locale. A replay clock in local time is a lie about the market. |
| Numbers | Digits stay Latin. Persian digits in a price column break the tabular alignment `Tahoma` was chosen for. |
| Currency | Account currency from the terminal; never assumed. |
| Percentages | One decimal, suffix `%`. |
| Keyboard | Key *names* are localizable; key *codes* are not. |

## Never localize

Object names, file names, session keys, seeds, the flight-recorder CSV, and
statement HTML class names. These are identifiers.

## Status

**Not implemented.** No string has moved yet. This document is the plan, and the
constraint it places on Phases 2–9 (position through a helper) is binding from
now.

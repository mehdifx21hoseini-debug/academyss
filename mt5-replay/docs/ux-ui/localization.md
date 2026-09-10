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

## Status: 10a shipped, 10b deliberately not

**176 strings, every user-visible surface, and a complete Persian
translation.** Measured before starting: 214 draw-site lines carried a
literal, and 152 log lines did too.

### An enum index, not a string key

The obvious design is `T("panel.play")`. It has two costs this product
cannot pay.

The panel repaints at 10 Hz and draws about sixty labels; a string key means
sixty lookups a frame against a table of hundreds, and Phase 11's budget has
no room for it. Worse: a mistyped string key **compiles, runs, and puts
`panel.paly` on the chart in front of a user**. A mistyped enum does not
compile. That entire class of bug is removed rather than audited.

### English is compiled in and can never be missing

A translation is an **override** loaded from
`MQL5\Files\SSReplay\lang\<code>.txt`, one `name = text` line per string.
It replaces the lines it has and leaves the rest in English, so:

- a translator who has done sixty of 176 ships something usable;
- a file that is missing, unreadable or corrupt costs nothing;
- a translation written against a newer build still works on an older one —
  lines naming a string this build does not have are **skipped, not fatal**;
- **there is no state in which this panel draws blank labels.**

Set it with the `InpLanguage` input: empty is English, `fa` is Persian. No
MetaEditor, no recompile, no new build of the expert.

### What is NOT in the catalogue, and why

- **Every `Print`, `PrintFormat` and flight-recorder line — 152 of them.** A
  log in a language the person reading the bug report cannot read is not a
  localised log, it is a lost diagnostic.
- **Object names, file names, session keys, seeds.** Identifiers.
- **`SS Replay`.** A product name is not a string to translate.

### Found by measuring: an English string had been cut since it shipped

`"Then drag them. Buy / Sell would open with no stop until you do."` is 64
characters and MetaTrader draws 63. It had been losing its last character on
every chart, mid-word, which reads as a rendering fault rather than a limit.

A translation makes that worse, not better — a translator has no way to know
the limit exists, and a language that runs longer than English will hit it on
strings English cleared. **Audit A19 checks every catalogue string and every
line of every shipped translation**, and stage 41 checks whatever language is
actually loaded.

### Audit A19

Three checks, and the third is the one that matters:

1. Every enum value has a table line. A missing one draws **blank** — not
   wrong, blank — which reads as a rendering fault.
2. Nothing exceeds 63 characters, in any language.
3. **No drawing call takes a literal as its text argument.** The text
   argument's position differs per call and every one of these functions
   takes an *object name* first, so A19 looks the position up rather than
   guessing; a scan for "a literal near a draw call" would report every
   object name in the product.

A19 also fails if fewer than 100 draw calls resolve to `T(SSR_S_...)` — if a
widget signature changed, the audit would read the wrong argument everywhere
and pass by finding nothing.

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

## Phase 10b — RTL is NOT done, and here is exactly what is known

This is the honest part of the phase, so it is stated precisely rather than
softened.

### Correction, v117: the first run measured mojibake, not Persian

The v116 run reported the glyph and round-trip checks as passing. **They were
measuring the wrong string, and one number gave it away.**

The language file was opened `FILE_TXT|FILE_ANSI`, which hands back **one
character per byte**. A Persian letter is two bytes in UTF-8, so every string
arrived twice as long and completely wrong — and the panel drew that.

It hid because the QA log is written with the same encoding: the mojibake
bytes went in and came back out, so the report showed `Play -> "پخش"`
perfectly while the chart could not have. What exposed it was the
63-character check failing on **24** strings — and every one of those 24 is
inside 63 *characters* and over 63 *bytes*. **A count is harder to fool than
a screenshot.**

The file is read as bytes and decoded `CP_UTF8` now (with a BOM skip), because
`FILE_UNICODE` is UTF-16 and a translator's editor saves UTF-8.

**So the glyph-coverage and round-trip results are withdrawn, not carried
over.** They will mean something on the next run and not before.

**What stage 41 measures** (on the user's own terminal):

- Whether Tahoma reports a real width for Persian text — i.e. the glyphs
  exist. **Re-measure required.**
- Whether Persian survives the round trip into an `OBJPROP_TEXT` unchanged.
  **Re-measure required.**
- All 176 Persian strings inside the 63-character draw limit. This passed on
  bytes, so it passes on characters by a wide margin.
- Every `%d`, `%s` and `%.2f` marker surviving the translation — this one was
  never affected: it counts markers, and `%` is one byte either way.

**What cannot be measured from inside MQL5, and is therefore not claimed:**
whether MetaTrader *shapes* Arabic-script glyphs and orders them
right-to-left on screen. There is no API that answers it. Persian may render
correctly, or as disconnected letters in the wrong order — the only way to
find out is to look at a chart, and this repository has no terminal.

**Why the coordinate mirroring is still off.** `SSR_Layout.mqh` has had
`SSRLead`/`SSRTrail` mirroring since Phase 2 and it is switched OFF. Phases
3–9 did not adopt it: the panel's roughly 200 draw sites compute `x` inline,
exactly as this document warned they must not. Turning mirroring on now would
move the handful of sites that use the helper and leave every other one
where it is — a panel half-mirrored, and I cannot see the result to correct
it.

**So the constraint this document placed on Phases 2–9 was not honoured, and
saying so is more useful than a switch that half works.** RTL layout is one
piece of work: route every draw site through the layout helper, then flip one
flag. It is a phase, not a corner of one, and it needs somebody who can watch
the chart while it happens.

## What shipped

| | |
|---|---|
| Strings in the catalogue | **176** |
| Persian translated | **176 / 176** |
| Draw sites still holding a literal | **0**, except `SS Replay` |
| Log lines deliberately left English | 152 |
| Enforced by | audit A19, smoke stage 41 |
| RTL layout | **not implemented**, and not claimed |

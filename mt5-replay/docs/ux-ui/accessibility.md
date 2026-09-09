# SS Replay — Accessibility

## What is not available

MQL5 chart objects have no accessibility tree. **No ARIA, no roles, no labels,
no screen-reader surface, no OS focus ring, no tab order.** A screen reader
cannot read this panel, and no amount of UI work changes that.

Saying so plainly is the honest position. What follows is what *can* be done.

## What we commit to

### 1. No status carried by colour alone
Every state has a second channel.

| State | Colour | Second channel |
|---|---|---|
| Long / short | green / red | the words `LONG` / `SHORT` in the setup row |
| Degraded fidelity | amber | a trailing `!` beside the mode name |
| Disabled | faint text | no border highlight, and the button does not respond |
| Armed reset | red | the label becomes `Reset?` and the strip names the loss |
| Follow / detached | — | the Follow button enables only when a chart is behind |
| Evaluation meter | amber, red at the breach | the percentage used and the floor price, written beside every bar |
| Evaluation verdict | green / red / amber | the word `PASSED` / `FAILED` / `VOID`, and `Prop !` on the tab itself |
| Profit / loss, anywhere | green / red | `Money(v, true)` always writes the sign, so the column reads without colour |
| A position with no stop | red | the words `no stop` on the row, while it can still be fixed |
| Stop / target / entry lines | red / green / amber | **fixed in Phase 9** — the words `STOP`, `TARGET`, `ENTRY` are drawn on the lines. They had a tooltip and nothing else, and a tooltip is not a second channel: it is the same channel behind a delay |
| A news line's importance | red / amber / grey | the event's own label, drawn on the line |

### 2. Contrast — measured in Phase 9, and eleven pairs failed

The previous version of this section claimed the palette "was chosen against
`SSR_C_PANEL` for exactly this". **It was not true, and nobody could see that
it was not true.** Phase 9 computed the WCAG ratio of every foreground this
panel draws against every surface it draws it on: **11 of 38 pairs were below
4.5:1**, and the worst was the build tag at **2.06:1** — the one label a user
is asked to read off a screenshot.

Two greys that both look grey on a dark panel can be four times apart in
contrast, and neither of them tells you. That is exactly why this is now
computed rather than judged.

**What changed:**

- **The caption was the problem surface.** Five of the eleven failures were
  "on the header": it was the lightest thing in the panel, so every colour on
  it had the least room. It is **recessed** now, like the status strip at the
  other end, with the body the lifted part between them — which fixed five
  failures without changing a single foreground colour.
- **There is room for two readable greys below white, not three.** Solved
  numerically: the dimmest grey clearing 4.5:1 on this panel is about 149, and
  `TEXT_DIM` was already 149. A third tier below it is, by definition, below
  the readable floor. The ramp was **re-spread** rather than extended —
  233 / 186 / 149, three visibly distinct steps, all readable, instead of four
  steps of which the last was decoration.
- `IDLE`, `STOP` and `BUY` were adjusted to clear the bar; `PANEL_EDGE` was
  lifted from 2.42:1 to 3.05:1 against the face it closes.

**It is enforced, not remembered.** The pairs are declared in `SSR_Theme.mqh`
beside the tokens as `SSR_CONTRAST: <fg> on <bg> <text|ui>` lines, and **audit
A18** computes every one of them on every run. `text` is held to 4.5:1 (WCAG
AA — this panel's type is 7–9 pt, which is small); `ui` to 3.0:1 (WCAG 1.4.11,
for borders and fills that carry meaning rather than words).

A18 also fails if fewer than twenty pairs are declared, because a table that
quietly empties passes forever.

**What A18 cannot check:** which colour is actually drawn on which surface.
There is no layout engine to ask, so the pair list is kept by hand — and it is
kept *in the theme file*, where changing a token and forgetting its pair means
editing two lines that touch.

### 3. Focus is visible where focus exists
The one real focus in MQL5 is an active `OBJ_EDIT`. The panel already tracks it
(`m_tag_focus`) so that Escape and Enter release it and a repaint cannot steal
it. Any new edit field joins that mechanism.

### 4. Target size
No interactive control smaller than **16 × 16 px**; primary actions ≥ 22 px
tall. The transport steps are 30 × 22; Play is 152 × 22.

### 5. Text size — still a gap, and still not faked
Body is 8 pt and the clock is 13 pt. **There is no user text-size setting and
that is a real gap.** MQL5 sizes are per-object; a scale factor would have to
multiply every metric in `SSR_Theme.mqh` and every hand-placed column offset in
every sheet, and there is no layout engine to reflow what then no longer fits.

Phase 9 did not close it. What Phase 9 did instead is make the *consequence*
measurable: `OBJPROP_FONTSIZE` follows the OS display scaling, so the same
label is a different width at 100% and at 150%, and **stage 40 measures every
label with `TextGetSize` on the machine the user is on** and fails if any two
overlap. A user who raises their OS scaling now gets a test that can prove
whether the panel still holds together, instead of a promise that it does.

### 6. Nothing is drawn over anything else — measured

Every column in this panel was placed by arithmetic in somebody's head. The
Positions row is what that is worth: its note column sat nineteen pixels from
the money column and would have printed straight through it — invisible for
four builds only because a *second* bug stopped the note being drawn at all.

Stage 40 measures every label the panel draws, at its real face and point size,
and asserts no two overlap, on all five sheets.

### 7. Unambiguous destructive actions
Reset asks, names what would be lost, and disarms on any other action. Start is
on its own wizard step. No irreversible action shares an edge with a frequent
one — which is why Reset sits across a gap four times wider than the others.

## Status

Items 1, 3, 4, 6 and 7 are implemented today. Item 2 is **enforced
mechanically** by audit A18 on every run — it is no longer a rule someone has
to remember. Item 5 is unimplemented and openly outstanding; what shipped is
the instrument that measures its consequences, not the feature.

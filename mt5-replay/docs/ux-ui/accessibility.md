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

### 2. Contrast
Body text on the panel face, and every semantic colour on that face, must clear
**4.5:1**. The v100 palette was chosen against `SSR_C_PANEL` for exactly this;
the three semantic colours were lifted well above their print values to hold it
on a dark face. **Any new token is checked against the face before it ships.**

### 3. Focus is visible where focus exists
The one real focus in MQL5 is an active `OBJ_EDIT`. The panel already tracks it
(`m_tag_focus`) so that Escape and Enter release it and a repaint cannot steal
it. Any new edit field joins that mechanism.

### 4. Target size
No interactive control smaller than **16 × 16 px**; primary actions ≥ 22 px
tall. The transport steps are 30 × 22; Play is 152 × 22.

### 5. Text size
Body is 8 pt and the clock is 13 pt. **There is no user text-size setting and
that is a real gap** — MQL5 sizes are per-object and a scale factor would have
to multiply every metric. Recorded as future work, not claimed as done.

### 6. Unambiguous destructive actions
Reset asks, names what would be lost, and disarms on any other action. Start is
on its own wizard step. No irreversible action shares an edge with a frequent
one — which is why Reset sits across a gap four times wider than the others.

## Status

Items 1, 3, 4 and 6 are implemented today. Item 2 is a rule applied when tokens
change. Item 5 is unimplemented and openly outstanding.

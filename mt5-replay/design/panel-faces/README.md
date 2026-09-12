# Ten faces for the SS Replay panel

Ten design directions for the same panel, asked for after "I don't like
the appearance of the whole program".

**Everything here is drawable by MQL5.** Flat fills, one-pixel borders and
single-line text - an `OBJ_RECTANGLE_LABEL`, an `OBJ_BUTTON`, an
`OBJ_LABEL`, and nothing else. No rounded corners, no gradients, no
shadows, no alpha, no text wrapping: if it is in a mockup, the panel can
draw it, and if the panel cannot draw it, it is not in a mockup. The
fonts are the ones Windows already has - Tahoma, Segoe UI, Consolas,
Courier New, Georgia.

Every palette was solved to WCAG AA before any pixel was drawn.
`solve.py` walks each colour's lightness, hue and saturation held, until
its pair clears; 186 pairs measured across the ten, zero failures. The
number under each mockup is the worst pair that palette actually has.

## Files

| file | what it is |
|---|---|
| `palettes.py` | the ten palettes, before solving |
| `solve.py` | the solver and the measurement. Writes `solved.json` |
| `build.py` | the mockups and the study page |
| `shoot.py` | renders and measures the PNGs |
| `shots/` | one PNG per design at 2x, plus a contact sheet |
| `faces.html` | the study page |

`build.py` reads `solved.json`, so the colours in every mockup are the
solved ones - a palette cannot be shown at a contrast it does not have.

## Build cost, per design

Two of the ten are palette-only, because the theme file already switches
palettes (v121 put the light and dark palettes behind one `#define`).
The rest need a drawing change as well, and 08 needs a layout rework.
The cost is written under each design on the study page.

---

# Ten variations of design 08

Design 08, the compact rail, was chosen. These ten change where the hand
goes, not what the panel looks like: the palette, the content and the
font are identical in all ten, and the size under each one is measured
off the render.

| # | name | what moved |
|---|---|---|
| 01 | Baseline | - |
| 02 | Speed presets | speed: five chips replace minus/value/plus/track |
| 03 | Speed on the rail | speed: vertical, on the rail. One row back |
| 04 | Speed number-led | speed: large number between two wide bars |
| 05 | Transport on the rail | the rail carries play/step; tabs become a strip |
| 06 | Transport at the bottom | row order only |
| 07 | Big play | full-width play, six keys in one row under it |
| 08 | Deals first | BUY/SELL directly under the clock |
| 09 | Dense sheet | no group frames; two-column grid. The shortest |
| 10 | Strip, no rail | no rail, horizontal tab strip, 270 px wide |

Range: 302x290 (09) to 303x352 (07), and 272 wide for 10.

`build8.py` builds them, `shoot8.py` renders and measures them.

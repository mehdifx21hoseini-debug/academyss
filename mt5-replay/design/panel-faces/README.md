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

---

# The proposal: a two-state ticket

Asked for after "a lot of these items aren't useful to me - as a coach,
a programmer and a trader of twenty years, what would YOU build?"

**The argument.** The panel is a form, and a replay session is not a
form. A session has two states and they need different things:

- **Flat** - you are hunting. Time, price, speed, and a way to arm a
  trade with the risk already defined.
- **In a position** - you are managing. Where the stop is, how many R
  you are up or down, and the two buttons that end it.

One panel, two contents. That alone removes most of what is never
useful, because what is on screen is what is relevant now.

**The speed control.** Asked for explicitly: like Soft4FX's, showing
both ticks and seconds, not blocky, continuous from zero. I have not
seen Soft4FX's interface and did not pretend to - this is built from
the function described. Eight cells became a track, a fill and a thumb:
three rectangles at any pixel width, so it reads continuous and can be
clicked or dragged anywhere. Zero is a real position on it and means
paused. Under it, two numbers answering two different questions -
`12 ticks/s` is how alive a candle feels, `1.0 s per candle` is how fast
the session moves - and the tick detail that links them sits directly
below.

**What was removed**: four tabs (to three rail cells, two of which open
a real window), the separate "Take the trade" button, the boxed progress
bar and its percentage, three of five caption buttons, the risk readout
(risk became a control), and the standalone spread line.

**What was added**: the price, large, coloured by direction; the speed
slider above; tick detail as its own control; R as the primary unit;
and an MAE/MFE bar - how far it went against you before it worked, which
is the thing a student never remembers and a coach always asks.

**One rule made it cohere**: the accent means "you can touch this".
Anything that is only information stays grey - which is why the progress
scrub is grey and the speed slider is orange.

**One thing measured rather than assumed**: the transport glyphs
(`<`, `>`, `||`, `[]`) are WGL4 geometric characters, which Tahoma
carries on every Windows. Wingdings was tried first and did not render
at all under test - see `glyph.html`, which is the specimen that settled
it.

Sizes: flat 302x338, in-position 302x367, collapsed 302x187.

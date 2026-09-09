# SS Replay — Design System

A design system for MQL5 is not CSS. There is no cascade, no layout engine, no
transitions, no clipping. Every control is a rectangle, a label, a button or an
edit box at absolute pixel coordinates. The system therefore has three parts:
**tokens** (`SSR_Theme.mqh`), **primitives** (`SSR_Widgets.mqh`), and **rules**
that only code review and the layout test can enforce.

## 1. Tokens

Semantic, never literal. No component may name a colour that is not a token.

### Surfaces — three steps of elevation
```
SSR_C_PANEL        the face, lifted off the chart
SSR_C_HEADER       caption, lifted again
SSR_C_WELL         sunk below the face: tracks, lists, values
SSR_C_STATUS       the status strip
SSR_C_PANEL_EDGE   outer frame
SSR_C_WELL_EDGE / SSR_C_GROUP_EDGE
```
Measured lesson (v100): a face only four points of luminance above a black chart
is not a surface. The step is twelve.

### Text
```
SSR_C_TEXT   primary   SSR_C_TEXT_DIM   labels, units   SSR_C_TEXT_FAINT   disabled
```

### Semantic — never borrowed by decoration
```
SSR_C_RUN    running / long
SSR_C_HOLD   paused / degraded / warning
SSR_C_STOP   error / short / refused
SSR_C_IDLE   idle / ready
```

### Accent and primary
```
SSR_C_ACCENT    identity; used sparingly
SSR_C_PRIMARY   exactly one control earns it: Play/Pause
```

### Deal
```
SSR_C_BUY / SSR_C_SELL (+ _EDGE), SSR_C_DEAL_TEXT, SSR_C_DEAL_DIM
```

**Rule.** State colour and styling colour are disjoint sets. A trader must never
have to ask whether green means "long" or "looks nice".

## 2. Type

One face, `Tahoma`, because it draws all ten digits on the same advance width —
so right-aligned numbers do not jitter as they change. Four sizes:
`TITLE 9 · BODY 8 · SMALL 7 · CLOCK 13`.

`SSR_FONT_MONO` is a separate name pointing at the same face, so a terminal that
ever proves otherwise is a one-line fix.

## 3. Spacing and metrics

```
SSR_PAD 8 · SSR_GAP 5 · SSR_ROW_H 19 · SSR_BTN_H 22
SSR_HEADER_H 20 · SSR_STATUS_H 18 · SSR_TAB_H 21
SSR_PANEL_W 420 · SSR_SHEET_H 186
SSR_PANEL_H = sum of its rows, added by the COMPILER
```

**Rule (learned the hard way in v69).** A frame height is never a number with
the parts listed in a comment beside it. Two lists drift; one does not.

## 4. Primitives

Eight today: `Rect`, `Label`, `Button`, `ButtonC`, `Edit`, `Progress`,
`TrackSegments`, `Group`, plus `Hide`, `Remove`, `RemoveAll`, `Pressed`,
`EditText`.

### Missing, and needed by the new architecture

| Primitive | For |
|---|---|
| `List` | palette results, sessions, trades, statistics rows |
| `Meter` | prop rules — a bar with a limit marker and a label |
| `Chip` | mode indicators: BLIND, RANDOM, PROP, fidelity |
| `Sparkline` | equity curve in the panel, drawn as segments |
| `Toast` | transient confirmations that must not steal the status strip |

Additive. No existing primitive changes signature.

### Non-negotiable primitive rules

1. **`Edit` writes its text only on a first paint.** A repaint that rewrote it
   would delete what is being typed. Anything that clears and redraws must
   declare itself a first paint.
2. **Hidden, not deleted, for anything holding user text.** `HideSheets` runs
   25×/s; deleting the tag box makes it impossible to type in.
3. **`OBJPROP_TEXT` is cut at 63 characters.** Any label built from data
   clips itself first.
4. **Creation order is z-order.** Anything meant to be on top is drawn last, on
   every frame — that is how the dropdowns and the key card work.

## 5. States

Every interactive control has four, and every one must be distinguishable
without colour:

| State | Signal |
|---|---|
| Enabled | full-contrast text on the button face |
| Disabled | `SSR_C_TEXT_FAINT` **and** no border highlight |
| Engaged | `SSR_C_BTN_ON` **and** the label changes where meaningful |
| Refused | the status strip says **why**, in the words of the fix |

## 6. Status ladder

One channel, four severities, and the strip is claimed in this order:

```
1 DANGER   armed destructive action ("Reset deletes 3 closed and 1 open")
2 REFUSAL  the last action was rejected, with the reason
3 NOTICE   degraded fidelity, wide spread, rule approaching
4 RESTING  balance · floating · open · spread · fidelity
```

Higher severity takes the whole strip. Nothing else may write there.

## 7. Motion

MQL5 has no transitions. "Motion" is what changes between two repaints at
10 Hz. Permitted: a label change, an arming state, a progress bar advancing.
Forbidden: anything that repaints more often than the engine pumps, or that
delays a click. **Responsiveness outranks feedback.**

## 8. Enforcement

The compiler cannot check any of this. Two things can:

- The **layout test** in the smoke suite measures every tab against the frame
  the panel itself drew, so a row past the end fails as a test rather than
  looking like a rendering fault.
- **`tools/ssr_audit.py`**, which must gain a check that no UI file names a raw
  `C'r,g,b'` colour outside `SSR_Theme.mqh`.

# SS Replay — Responsive Strategy

## The real variable

Not screen size — **chart height in pixels**, which changes when the user opens
the Toolbox, the Navigator, or a second chart in the window. Measured on the
user's terminal: **363 px with the Toolbox open**, ~588 px with it closed. Both
on the same monitor.

Width matters far less, but not not-at-all — see **Width** below.

## Breakpoints

| Height | Mode | Panel | Rationale |
|---|---|---|---|
| < 360 px | **Compact** | 128 px: clock, transport, speed, status | Keep what is OPERATED, drop what is CONSULTED |
| 360–719 px | **Standard** | 336 px: + tabs and sheet | The default |
| ≥ 500 px, **and asked for** | **Tall** | 476 px: the Positions sheet holds 12 rows instead of 5 | Room to stop hiding things |

All three are implemented and tested (stages 18, 39).

**Pro became Tall, and it is asked for rather than automatic.** The version
this table originally described — "Standard plus a persistent rail" — was not
built: the rail is *already* always visible in Standard, so it would have added
nothing a user could notice. And the breakpoint is not a breakpoint: compact is
a **degradation** forced by a chart with no space, while taking space is the
opposite kind of decision, so `P` asks for it and `panel.ini` remembers it.
The height (500 px) is a *precondition*, not a trigger.

The wish and the fact are two separate flags. A chart too short to hold the
tall panel does not silently forget the preference — an afternoon on a laptop
would otherwise cost the setting permanently, with nothing said.

## Width

Width matters less than height, but it is not nothing.

- **When the chart can hold the whole panel, it holds the whole one.** Until
  Phase 9 the clamp only kept the *caption* reachable — a rule written for a
  panel dragged off the bottom and applied to the right edge too — so a panel
  nudged right on a wide chart stayed hanging off it with close, collapse,
  corner, `?` and `K` all past the edge.
- **A chart narrower than 420 px is a stated limit, not a bug.** MQL5 has no
  layout engine and no way to scale an object, so a 420 px panel cannot become
  a 340 px one: every sheet's columns are laid out in pixels from both edges,
  and there is no width at which they all still clear each other. Compact mode
  answers a chart that is too *short* because the answer there is to drop whole
  rows; there is no equivalent for too *narrow*, because what would have to be
  dropped is half of every row. A four-chart grid on a laptop is a real setup,
  so the status strip says so — a user whose close button is off the edge
  deserves to be told why rather than concluding the panel is broken.

## Rules

1. **The chart never yields.** The panel is bounded; the chart takes the rest.
2. **Degrade by removing surfaces, not by shrinking type.** 8 pt is already the
   floor.
3. **Never trap the panel off-screen.** On a chart with room, `ClampToChart`
   pulls the *whole* panel back on. Leaving only the caption reachable is the
   fallback for the one case that cannot be fixed: a chart smaller than the
   panel.
4. **A mode you cannot leave is a trap.** Compact restores itself the moment the
   chart grows; the panel logs which mode it is in and why.
5. **Modals size to the chart**, and a list that would run off the bottom opens
   upward instead (already true of the v101 dropdowns).

## What we will not do

- No horizontal scrolling. MQL5 has no clipping; a "scrolled" panel is objects
  drawn outside the frame, over the chart.
- No proportional scaling of the whole panel. Text does not scale with it.

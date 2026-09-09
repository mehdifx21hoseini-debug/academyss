# SS Replay — Responsive Strategy

## The real variable

Not screen size — **chart height in pixels**, which changes when the user opens
the Toolbox, the Navigator, or a second chart in the window. Measured on the
user's terminal: **363 px with the Toolbox open**, ~588 px with it closed. Both
on the same monitor.

Width matters far less: the panel is 420 px and charts are almost always wider.

## Breakpoints

| Height | Mode | Panel | Rationale |
|---|---|---|---|
| < 360 px | **Compact** | 128 px: clock, transport, speed, status | Keep what is OPERATED, drop what is CONSULTED |
| 360–719 px | **Standard** | 336 px: + tabs and sheet | The default |
| ≥ 720 px | **Pro** | Standard + persistent rail | Room to stop hiding things |

Compact is implemented and tested. Pro is planned for Phase 3.

## Rules

1. **The chart never yields.** The panel is bounded; the chart takes the rest.
2. **Degrade by removing surfaces, not by shrinking type.** 8 pt is already the
   floor.
3. **Never trap the panel off-screen.** `ClampToChart` always leaves the caption
   reachable so a panel pushed off the bottom can be dragged back.
4. **A mode you cannot leave is a trap.** Compact restores itself the moment the
   chart grows; the panel logs which mode it is in and why.
5. **Modals size to the chart**, and a list that would run off the bottom opens
   upward instead (already true of the v101 dropdowns).

## What we will not do

- No horizontal scrolling. MQL5 has no clipping; a "scrolled" panel is objects
  drawn outside the frame, over the chart.
- No proportional scaling of the whole panel. Text does not scale with it.

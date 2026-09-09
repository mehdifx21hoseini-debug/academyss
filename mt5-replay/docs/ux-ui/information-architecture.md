# SS Replay — Information Architecture

## Validating the proposed structure against the engine

The brief proposes eight areas. Checked against what exists:

| Proposed | Verdict |
|---|---|
| Replay | **Keep.** Playback, jump, bookmarks, timeframe all exist. |
| Trade | **Keep.** Market, pending, risk, SL/TP, position management all exist. |
| Positions | **Merge into Trade.** Splitting them puts one trade's life in two places. |
| Analysis | **Keep — biggest gain.** 43 statistics with almost no surface. |
| Training | **Keep.** Blind + random + seed + reference strategy. |
| Review | **Keep.** Journal, screenshots and per-trade data exist and are invisible. |
| Prop | **Keep.** Four rules enforced, no dashboard. |
| Settings | **Keep.** Bridges the 54 expert inputs. |

**Seven areas, not eight.** Positions is a section of Trade.

## Where each area lives

MQL5 has no windows, tabs-with-scroll, or drawers. There are three real
containers: the **panel**, a **modal**, and the **chart**. The architecture must
assign each area to one of those, not to an idea of a screen.

| Area | Container | Why |
|---|---|---|
| **Replay** | Panel, always visible | Operated continuously |
| **Trade** | Panel sheet (default) | Operated continuously |
| **Analysis** | Modal | Consulted, not operated; needs space |
| **Training** | Setup + a persistent chip in the caption | Chosen once, must stay visible |
| **Review** | Full-chart modal at session end | It *is* the end of the session |
| **Prop** | Panel sheet when enabled, else absent | Only exists for one mode |
| **Settings** | Modal, two levels | Rare |

**Rule: the panel holds what is OPERATED. Modals hold what is CONSULTED.**
Already proven by the v98 status-strip decision.

## Panel modes

| Mode | Height | Contains | Trigger |
|---|---|---|---|
| **Compact** | ~128 px | clock, transport, speed, status | chart < 360 px, or chosen |
| **Standard** | ~336 px | + Trade / Positions / Stats / Session | default |
| **Pro** | ~336 px + rail | + persistent side rail, Analysis and Command entry | chosen |

Compact already exists and is tested. Standard is today's panel. **Pro is the
new mode** and it is additive — no existing state is removed to build it.

## Navigation model

There is no navigation bar. There are four ways to reach anything:

1. **The panel** — what you operate now.
2. **The command palette** — everything, searchable, `Ctrl+K`.
3. **Keyboard** — 20 bindings today.
4. **The chart** — drag SL/TP, drag the start line, click a calendar line.

The palette is what makes seven areas reachable without seven tabs.

## Session lifecycle

```
SETUP → REPLAY ⇄ TRADE → (rules) → END → REVIEW → REPEAT
                    ↓                        ↓
                 ANALYSIS                 JOURNAL
```

`REPEAT` carries the seed: the same session, the same start, the same data.

## What we are NOT adding

- No dashboard home screen. The chart is the home screen.
- No notification centre. One status strip with a severity ladder.
- No settings tree mirroring the 54 inputs. Only inputs that change *behaviour
  during* a session are surfaced.

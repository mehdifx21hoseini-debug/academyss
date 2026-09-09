# SS Replay — Keyboard Shortcuts

## Constraint first

**MetaTrader delivers `CHARTEVENT_KEYDOWN` only to the chart the program is
attached to.** Keys work on the replay chart the expert runs on. Every other
chart is polled, which is why the panel also carries buttons for everything a
key can do.

Bindings live in one table in `SSR_Keys.mqh`. The key card (`H`) is generated
from that table, so the card and the behaviour cannot disagree. The smoke test
asserts: every declared key resolves to the command beside it, no key is
declared twice, and no card line exceeds MetaTrader's 63-character cut.

## Current bindings (v103, audited)

| Key | Command | Key | Command |
|---|---|---|---|
| `Space` | play / pause | `R` | stop & target lines on/off |
| `→` | one candle forward | `Tab` | **take the trade the lines describe** |
| `←` | one candle back | `X` | flip long ↔ short |
| `PgDn` | ten forward | `L` | same as `R` |
| `PgUp` | ten back | `J` | jump to a time |
| `+` / `Num +` | faster | `B` | bookmark here |
| `−` / `Num −` | slower | `S` | saved sessions |
| `0` | reset (asks first) | `F` | bring charts back to now |
| `H` | this list | `D` | fidelity |

**Why `R` and `Tab`.** The hand that is trading owns them: drop the lines, drag
them, take the trade. **Why `0` for reset:** it is not a letter, so a finger
reaching for the lines cannot destroy the session.

## Conflict audit against the brief's proposals

| Proposed | Verdict |
|---|---|
| `Space` play/pause | **Already bound, identical.** |
| `←` `→` step | **Already bound, identical.** |
| `Shift+→` fast forward | **Free.** `PgDn` already does ten; add as an alias. |
| `R` reset | **CONFLICT.** `R` is the lines key and is muscle memory. Reset stays `0`. |
| `B` bookmark | **Already bound, identical.** |
| `T` trade | **CONFLICT in spirit.** `Tab` already takes the trade. Adding `T` as a second verb for the same action is duplication the brief forbids. **Rejected.** |
| `Ctrl+K` palette | **Free.** Adopt. |

## Additions for the new architecture

| Key | Command | Status |
|---|---|---|
| `Ctrl+K` | command palette | **shipped, v105** |
| `Shift+→` / `Shift+←` | ten candles (alias of PgDn/PgUp) | planned |
| `↑` `↓` | choose, inside the palette | **shipped, v105** |
| `Enter` | run the selection | **shipped, v105** |
| `A` | Analysis | planned, Phase 7 |
| `Esc` | close the top modal | **partially exists** (releases edit focus) |

All additions go through `SSRAddKey` in the same table. Nothing is bound in two
places; the card regenerates itself.

## Rules

1. No binding is added outside `SSR_Keys.mqh`.
2. No destructive action gets a letter key.
3. Every binding appears on the `H` card, or is marked unlisted deliberately.
4. A binding that duplicates an existing verb is rejected, not added.

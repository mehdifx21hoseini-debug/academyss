## O. BUTTON-BY-BUTTON REDESIGN

*Every control the product draws, one row each: keep / change / remove / add, its label, its size,
whether it is primary or secondary, its key binding, and the reason. Build v125, `SSR_LAYOUT_RAIL`
and `SSR_THEME_RAIL` active. This section is the execution layer of M — where M decides what a
region is for, O decides what is drawn in it and what a finger does to it. Nothing here contradicts
M; where M left a control unspecified, O specifies it and says so.*

---

### O.0 How to read this section

**The five verdicts.**

| Verdict | Means |
|---|---|
| **KEEP** | the control ships unchanged. Its id, its size, its dispatch arm and its rank are correct and were paid for once already |
| **CHANGE** | the control stays and its id stays; its label, geometry, rank or condition moves |
| **REMOVE** | the object is deleted from the chart — `m_w.Remove(id)`, not merely undrawn (invariant I7) |
| **ADD** | a control drawn nowhere today |
| **RESTORE** | a control or a *function* removed in v125 that comes back, possibly by a different mechanism than the one that was removed |

**Rank.** Exactly one **primary** per band (M.9). Everything else is secondary; *destructive* is a
third rank, carried by isolation and by a two-press arm, never by colour.

**What "key binding" means here.** [CONFIRMED FROM CODE] A key binding is a row in `SSRKeyBindings()`
(`SSR_Keys.mqh:125-218`) — 22 bindings, all 22 vk values distinct, 18 marked `listed`. A control with
a key binding is reachable without the panel; a control without one is reachable only by a click.
Five commands have no key (`PLAY`, `PAUSE`, `RESTART`, `REPLAY_FROM_HERE`, `COLLAPSE`) and every one
of those has a button or is host-owned — that invariant is preserved in every table below.

**The rules every row obeys, inherited from M and not restated per row.**

* **R1** — teardown is transition-driven. No control below is drawn or hidden on a still frame.
* **R5 / A22** — every label goes through `Clip()` against a declared budget: **46 characters** at
  `SSR_FS_BODY`, **52** at `SSR_FS_SMALL` in a 237 px sheet row; **8** in a 44 px rail cell; **18**
  in a 96 px action cell (M.1.4). The 63-character draw cut is the outer limit, never the budget.
* **Click-only.** Every control below is an `OBJ_BUTTON` polled by `CSSRPanel::PollClicks`
  (`SSR_Panel.mqh:2445`) — latch cleared before acting, 200 ms debounce per name. No hover state, no
  focus ring, no drag handle, no tooltip is specified anywhere in this section, because none can be
  drawn.
* **Creation order is z-order.** Where two controls could overlap, the row says which is drawn last.

---

### O.1 The caption — `DrawCaption` (`SSR_Panel.mqh:833-940`)

[CONFIRMED FROM CODE] The caption is 23 px and holds two controls, three chips and three labels.
Its arithmetic today: `title` at `x+8`, `build` at `x+66`, `capinfo` at `x+88`, chips from `x+140`,
`collapse` at `x + W - 42 = x+268`, `close` at `x + W - 22 = x+288`.

| Control (id) | Verdict | Label | Size | Rank | Key | Reason |
|---|---|---|---|---|---|---|
| `collapse` | **KEEP** | `-` / `+` | 18 × 15 | secondary | none (`SSR_CMD_COLLAPSE` is one of the five keyless commands, and it has this button) | The toggle is honest — the glyph reports the state it will move *to*. `Dispatch` maps it at `SSR_Panel.mqh:2738` |
| `close` | **KEEP** | `X`, `SSR_C_STOP` text on `SSR_C_BTN` plate | 18 × 15 | secondary, coloured as the one caption control with a consequence | none | It leaves `reopen` behind (`:641-655`), and the comment "a control that removes its own only way back is a trap" is the strongest single line in the file. Do not touch |
| `reopen` | **CHANGE (ordering only)** | `SS Replay` | 76 × 20 | secondary | none | [CONFIRMED FROM CODE] the `m_closed` branch returns at `:649-655` **before** `ClampToChart` runs at `:716`, so a chart resized while closed can strand the only way back off-screen. Move the clamp above the early return. Nothing about the button itself changes |
| chips `chfid` / `chblind` / `chprop` | **CHANGE (origin)** | fidelity short name + ` !`, `BLIND`, `PROP` | measured, `Chip` reports its own width | not controls — they are read, never pressed | — | `ui-panel-13` (CONFIRMED, LOW): the row ends at `x+274` and `collapse` starts at `x+268`. Move the chip origin `x+140` → **`x+134`** and cap the fidelity chip at 6 characters. Modes-as-chips (`:858-862`) is preserved verbatim: a mode carried by colour alone is a mode a colour-blind trader cannot read |
| `palette` / `keys` / `move` | **REMOVE, once** | — | — | — | — | [CONFIRMED FROM CODE] the three `m_w.Remove()` calls at `:932-934` run on **every frame, for ever**, to clean up objects only a v124 installation can have. They move into `UpgradeSweep()`, called once from `Create()` behind an `m_swept` flag (M.1.6). Saves 3 `ObjectFind` + 3 `Forget()` per frame and is the cheapest line item in the redesign |

**ADD nothing to the caption, and the arithmetic is why.** [CONFIRMED FROM CODE] A third 18 px
caption button would have to start at `x+248`; the worst-case chip row already reaches `x+274`. There
is no 18 px of caption left in a 310 px panel, which is the reason the `[]` restoration in O.9 is a
**key**, not a button. [INFERENCE] That is arithmetic, not preference, and it does not change until
`SSR_PANEL_W` does.

---

### O.2 Transport — `DrawTransport` (`SSR_Panel.mqh:975-1040`)

[CONFIRMED FROM CODE] The row is 27 px and budgets itself explicitly:
`24 + 4×24 + 58 + 5×3 + 10 = 203` of 294 usable, so the primary takes the remaining **91**.

| Control (id) | Verdict | Label | Size | Rank | Key | Reason |
|---|---|---|---|---|---|---|
| `restart` | **KEEP** | `\|<` | 24 × 22 | secondary; enabled on `m_state.connected` | none (`SSR_CMD_RESTART` is keyless by design, and it has this button) | Rewind to the start is not a step and must not sit in the step ladder's rhythm; it is first because it is the leftmost point in time |
| `back10` | **KEEP** | `<<` | 24 × 22 | secondary; `m_state.CanStep()` | `PgUp` (`SSR_CMD_STEP_BACK_10`, listed) | — |
| `back` | **KEEP** | `<` | 24 × 22 | secondary; `CanStep()` | `Left` (`SSR_CMD_STEP_BACK`, listed) | — |
| `toggle` | **KEEP** | `Play` / `Pause` at `SSR_FS_TITLE` | **91 × 22**, `SSR_C_PRIMARY` | **PRIMARY — the one primary control on the panel** | `Space` (`SSR_CMD_TOGGLE`, listed) | [CONFIRMED FROM CODE] the 91 px against a 24 px step is how primary-vs-secondary is carried in this product, and the comment at `:976-989` explains the failure it fixed. `ui-plumbing-10` — which claimed the primary and an engaged toggle share a colour — is **NOT_A_BUG** in `verified.json`; **no part of this redesign acts on it** |
| `step` | **KEEP** | `>` | 24 × 22 | secondary; `CanStep()` | `Right` (`SSR_CMD_STEP_FWD`, listed) | — |
| `step10` | **KEEP** | `>>` | 24 × 22 | secondary; `CanStep()` | `PgDn` (`SSR_CMD_STEP_FWD_10`, listed) | — |
| `reset` | **KEEP** | `Reset` → `Reset?` when armed | **58 × 22**, after a **10 px separator** (other gaps are 3) | **destructive** — isolated, two-press, never blue | `0` (`SSR_CMD_RESET`, listed) | [CONFIRMED FROM CODE] the arm is the *same* button asking, not a second control appearing under a moving finger (`:1031-1033`). `Reset` is 58 rather than 46 because the Persian label is eleven characters and a button that clips its own label is a button nobody is sure about |

**One change to the row, and it is not a button.** [CONFIRMED FROM CODE] `ui-panel-14` (CONFIRMED,
LOW): the armed reset's confirmation — the product's **one destructive question** — is a hardcoded
English literal at `SSR_Panel.mqh:2253` in an otherwise fully translated panel. Route it through
`T()`. The button above is correct; the sentence it raises is not.

**Refused:** a separate PLAY and a separate PAUSE. Two buttons for one state is how a hand learns to
look before pressing, and the state is already in the label, in the caption's `capinfo`, and in the
chip colour.

---

### O.3 Speed — `DrawSpeed` (`SSR_Panel.mqh:1045-1075`)

[CONFIRMED FROM CODE] 21 px: `28` label + `18` + `40` box + `18` + **130 px groove** + `52` meaning.

| Control (id) | Verdict | Label | Size | Rank | Key | Reason |
|---|---|---|---|---|---|---|
| `spdn` | **KEEP** | `-` | 18 × 19 | secondary | `-`, `Num -` (`SSR_CMD_SPEED_DOWN`; the `-` row is `listed = false` because `+ / -` is listed as one row) | With 10 drawn cells over a 20-stop ladder, these two are the **only** way to reach an odd ladder index. They stop being a convenience and become load-bearing — see below |
| `spdbox` + `spdval` | **KEEP** | `SSRSpeedName(speed_x100)` in a sunken well | 40 × 19 | not a control | — | A value sits in a box. Already correct (`:1063`) |
| `spup` | **KEEP** | `+` | 18 × 19 | secondary | `+`, `Num +` (`SSR_CMD_SPEED_UP`, listed) | as `spdn` |
| `spdseg0..19` → **`spdseg0,2,4…18`** | **CHANGE** | none — cells carry no text | **10 cells of 13 px** in the same 130 px groove | secondary | via `+` / `-` only | [CONFIRMED FROM CODE] `SSR_SPEED_LADDER_SIZE 20` is an **engine** constant (`Common/SSR_Types.mqh:302`) and the panel draws one cell per stop into 130 px — **6.5 px a target**. The file names its own limit at `:1047-1050`: *"Below about five the cells stop being clickable and the slider becomes a picture of a control."* Ten cells of 13 px is a hittable target; `-` / `+` keep all 20 speeds reachable; the slider's cold cost falls from **198 writes to 108** |
| `spdseg_tk` / `spdseg_th` | **KEEP** | groove frame, 4 px thumb | as drawn | not controls | — | [CONFIRMED FROM CODE] `Dispatch` already guards them with `AllDigits(tail)` (`:2594-2597`) — without it a click on the outline would set the speed to the bottom of the ladder. `ui-plumbing-9` (CONFIRMED, LOW): `SSR_C_THUMB_EDGE` and `SSR_C_TICK` are declared in all three palettes and drawn by nothing. **Spend them here** — the thumb gets its outline and the groove gets tick marks at the ten cell boundaries — rather than deleting two tokens |
| `spdmean` | **CHANGE** | `SSRSpeedMeaning(...)`, **`Clip(..., 11)`** | 52 px reserve | not a control | — | `ui-panel-8` (CONFIRMED, MEDIUM): at `SSR_SPEED_MAX` the text is the 21-character `"as fast as ticks feed"`, unclipped, into a 52 px reserve — running onto the price |

**The id is the ladder stop it sets, and that is what keeps `Dispatch` untouched.**
[CONFIRMED FROM CODE] `Dispatch` parses `spdseg<digits>` and calls
`SetSpeedX100(SSRSpeedLadder((int)StringToInteger(tail)))` (`:2589-2600`). [RECOMMENDATION] Give
`CSSRWidgets::Slider` (`SSR_Widgets.mqh:460`) one optional `stride` argument, defaulting to 1: cell
`i` is created as `id + IntegerToString(i * stride)` and the fill/thumb compare against
`at / stride`. At `stride = 2` the drawn cells are named `spdseg0, spdseg2 … spdseg18` — **the
dispatch arm, the debounce key and the 200 ms latch name are all byte-identical to today**, and the
id still says which ladder stop it sets. No second formula, no mapping table.

**The one-shot sweep, and why `HideBody` cannot do it.** [CONFIRMED FROM CODE — correcting a claim
that circulated before M] the loop at `SSR_Panel.mqh:2093-2094` **Hides**, it does not Remove:

```
      for(int t = 0; t < SSR_SPEED_LADDER_SIZE; t++)
         m_w.Hide("spdseg" + IntegerToString(t), hidden);
```

so on an upgrade from a build that drew twenty cells, the ten now-unused ids still exist and the next
`Hide(false)` **un-hides them** — ten orphan cells sitting on the groove. Invariant I7 requires a
one-shot `Remove` of the odd ids in `Create()`, folded into `UpgradeSweep()` with the nine v124
caption/action removals.

---

### O.4 The action strip — `DrawActions` (`SSR_Panel.mqh:1235-1262`)

[CONFIRMED FROM CODE] `bw = (310 - 16 - 6)/3 = 96`, height `SSR_ACT_H 21`, plus the `tabline`
hairline. **Three cells, and there is no fourth 96 px cell in 310 px.**

| Control (id) | Verdict | Label | Size | Rank | Key | Reason |
|---|---|---|---|---|---|---|
| `lines` | **KEEP** | `SL/TP` off → `Lines` on (`act.lines.off` / `act.lines.on`), pressed-state when `lines_armed` | 96 × 21 | secondary, **stateful** | `R`, and `L` as an unlisted alias (`SSR_CMD_LINES_TOGGLE`) | The label names the *thing* when off and the *state* when on, which is the right way round: a trainee looking for where stops live reads "SL/TP". 5 and 5 characters against an 18-character budget |
| `sessions` | **KEEP** | `Saved` (`act.sessions`) | 96 × 21 | secondary | `S` (`SSR_CMD_SESSIONS`, listed) | **Gated:** ships only after `host-expert-7` (CONFIRMED, MEDIUM) — keys are not withheld while this dialog is open, so `Space` starts the replay and `0` arms the reset behind a modal. And after `ui-dialogs-1` (CONFIRMED, HIGH), or this button points at a list that is empty for a reason nobody can see |
| `fidelity` | **KEEP** | `Detail` (`act.fidelity`) | 96 × 21 | secondary | `D` (`SSR_CMD_FIDELITY_CYCLE`, listed) | A cycle, not a menu — MQL5 has no combo box, and the result is read back on the `chfid` caption chip, which is where a mode belongs |
| `follow` / `bookmark` / `jump` | **REMOVE, once** | — | — | — | — | The three `m_w.Remove()` calls at `:1241-1243` (and the identical three in `DrawSide` at `:1189-1191`) run on **every frame for ever**. Into `UpgradeSweep()`. Their *functions* are restored elsewhere — O.9 |
| `tabline` | **KEEP** | 1 px hairline | `W - 16 × 1` | — | — | One hairline, never two adjacent, never decorative (M.9) |

**No fourth action button, in any build of this design.** [CONFIRMED FROM CODE] `CSSRAutoPause` —
which O would otherwise want here — stays **[FUTURE FEATURE]** for exactly this arithmetic. So does a
`Follow` button: the strip cannot pay for it, and O.9 pays for it out of the SESSION sheet instead.

---

### O.5 The rail — `DrawRail` (`SSR_Panel.mqh:1209-1225`), `TabName` (`:1106-1121`)

[CONFIRMED FROM CODE] cells of `SSR_RAIL_W 44 × h 22` with `gp 3`: `n` cells need `25n - 3` px of a
186 px sheet. Six is 147, leaving 39 px **deliberately unspent**.

| Control (id) | Verdict | Label (EN) | Size | Rank | Key | Reason |
|---|---|---|---|---|---|---|
| `tab0` | **KEEP** | `Trade` / `Trade !` / `Trade !!` | 44 × 22 | secondary, selected plate `SSR_C_TAB_ON` | none | The only destination that acts |
| `tab1` | **KEEP** | `Pos` / `Pos %d` | 44 × 22 | secondary | none | [CONFIRMED FROM CODE] the count is already interpolated at `:1109-1111` — the cell has always been able to raise its hand |
| `tab2` | **CHANGE (name)** | `Perf` / `Perf !` | 44 × 22 | secondary | none | Stats → Performance. `SSR_TAB_STATS` is index 2 and stays the clamp target (`:745-746`); the **constant's name** now reads wrong and is renamed with the destination |
| `tab3` | **KEEP** | `Sess` | 44 × 22 | secondary | none | — |
| `tab4` | **ADD** | `Keys` | 44 × 22 | secondary | `H` opens it (`SSR_CMD_KEYS`, listed) — the cell and the key now reach the same surface | This is the cell that fixes `host-expert-4` + `ui-dialogs-14`: a permanently visible rail cell is a discovery path that cannot be missed and cannot be consumed unseen |
| `tab5` | **CHANGE (index)** | `Eval` / `Eval !` / `PASS` / `FAIL` | 44 × 22 | secondary, **conditional on `prop_on`** | none | [CONFIRMED FROM CODE] `TabCount()` is `prop_on ? SSR_TAB_MAX : SSR_TAB_COUNT` (`:1103`) and can only ever hide the **final** cell. A conditional destination at an interior index silently deletes every cell after it. It stays last |

**Constants:** `SSR_TAB_COUNT 4 → 5`, `SSR_TAB_MAX 5 → 6`, `SSR_TAB_PROP 4 → 5`
(`SSR_Theme.mqh:542-544`), one enum value, three short strings plus their `fa.txt` rows.

**Dispatch is untouched.** [CONFIRMED FROM CODE] the arm tests `StringLen(what) == 4 &&
StringSubstr(what,0,3) == "tab"` (`:2566`); `tab0`..`tab5` are all length 4. The sweep at `:1222-1224`
(`for(int i = n; i < SSR_TAB_MAX; i++) m_w.Remove(...)`) already removes a cell the rail no longer
has — it inherits the sixth for free.

**The condition mark is text inside `TabName()`, never an object over the cell.**
[CONFIRMED FROM CODE] The file records the exact failure mode a glyph object would reproduce, about
the slider thumb (`SSR_Widgets.mqh:455-458`): *"a click landing exactly on it is swallowed rather
than reaching a cell."* Four swallowed pixels of an idempotent slider is acceptable; six swallowed
pixels of a 44 px navigation cell is not, because the click that is swallowed is the click that would
have taken the trainee to the warning. `!` / `!!` appended inside the cell's own text costs **zero
objects, zero slots, zero geometry**.

| Cell | Condition | Wire source | Mark | Budget |
|---|---|---|---|---|
| `tab0` Trade | `lines_armed && order_why != ""` | `order_why` | ` !`, cell text in `SSR_C_HOLD` | `Trade !` = 7 of 8 |
| `tab0` Trade | `lines_armed && sl_price == 0` | `sl_price` | ` !!`, cell text in `SSR_C_STOP` | `Trade !!` = 8 of 8 |
| `tab1` Positions | `open_positions > PosCap()` | both on the wire | the count is already the mark | `Pos 12` = 6 |
| `tab5` Eval | `prop_daily_used >= 0.8 \|\| prop_total_used >= 0.8` | existing | ` !` | `Eval !` = 6 |
| `tab5` Eval | `prop_state >= 3` | existing | already `FAIL` | 4 |
| `tab2` Perf | discipline crossed | **held** until M.4.3's throttled `SSRStatistics` exists | ` !` | `Perf !` = 6 |

The composed string is `Clip()`ed at 8 under R5 — MetaTrader centres button text and will not clip it
itself. **Named cost:** an alarmed cell draws its text in the alarm colour whether or not it is
selected, so it gives up one bit of selection contrast; the selected cell's *plate* (`SSR_C_TAB_ON`)
carries selection instead. The `!` is what makes that trade safe — a mark carried by colour alone
would break the product's own rule at `:858-862`.

[POTENTIAL_RISK] The Persian cells remain unverifiable: `rtab.positions = پوزیشن` with a Latin digit
appended is a mixed-direction string in a renderer with no bidi and no clipping. Unchanged by this
redesign and unclosable without a terminal.

---

### O.6 Sheet controls, destination by destination

The sheet is **245 px wide**; a row from `x+8` has **237 px**.

#### O.6.1 TRADE — `SheetTrade` (`SSR_Panel.mqh:1346-1505`)

| Control (id) | Verdict | Label | Size | Rank | Key | Reason |
|---|---|---|---|---|---|---|
| `riskdn` / `riskup` | **KEEP** | `-` / `+` | 16 × 16 each, at `x+w-84` and `x+w-18` | secondary | none | [CONFIRMED FROM CODE] `StepRisk` walks a ladder of the sizes people trade — 0.10 / 0.25 / 0.50 / 1.00 / 2.00 / 3.00 / 5.00 (`:2146`) — not a linear ramp, and not a text box: *"a mistyped 10 where 1 was meant is a real loss to learn from in the wrong way"* (`:2118-2121`) |
| `riskval` / `riskmon` | **KEEP** | `%.2f %%`, and the money beside the label | labels | — | — | The money answers "how much is that" and sits with the label rather than between the steppers |
| **`verdict`** | **ADD** (slot 22) | `0.50 % · 25.00 · 2.0 R · 0.42 lot`, `Clip(…, 40)` | one row, first in the Risk group | not a control — it is the **answer** | — | [RECOMMENDATION] A trainee currently reads legality by assembling four numbers spread over 92 px of group box. Put the result first, coloured by the **worst** of three tests: no stop → `SSR_C_STOP`; `order_why != ""` → `SSR_C_HOLD`; else `SSR_C_TEXT`. Every operand is already on the wire, computed by the owner that will execute the order — the panel still computes nothing |
| `tagbox` (`OBJ_EDIT`) | **KEEP, with a named contingency** | `m_state.trade_tag` | `w-56 × 18` at `x+48` | secondary | `Esc` leaves the box (`:2835` path) | [CONFIRMED FROM CODE] the only typed input this architecture may use, read **at a moment** and never polled (`ReadTag`, `:2533`), with the `Exists` check that stops a tab change from wiping the tag. [POTENTIAL_RISK] `ui-panel-11`: the box is hidden and re-shown 10×/s while it may hold the keyboard. R1 is its strongest available mitigation — under the transition latch the box is not touched on a still frame at all. But `m_tag_focus` is assigned only inside the `CHARTEVENT_MOUSE_MOVE` handler (`:2903-2907`), so in this audit's ground-truth branch the typed tag has **no focus path**, and the setup-tag fallback stays the contingency |
| `armbtn` | **KEEP** | `Place the lines` (`place.lines`) | `w-16 × 22` | secondary; enabled on `can_trade` | `R` / `L` | Drawn only while `!lines_armed`. One button in the empty state is the right density |
| `hintrow` | **CHANGE** | `then drag` / `waiting for price`, `Clip(…, 46)` | label | — | — | R5. It is currently unbounded |
| `setuprow` (slot 12) | **KEEP** | `LONG setup` / `SHORT setup` | label at `x+8, gy+12` | — | — | The side is read from the geometry, never asked for |
| **`order_why` (slot 17)** | **CHANGE — its own object id** | `m_state.order_why`, `Clip(…, 44)` | label, its own row | — | — | `ui-panel-5` (CONFIRMED, MEDIUM): slots 12 and 17 write **the same object `setuprow` at the same coordinates** (`:1409` vs `:1428`), so the refusal is visible for one frame and then gone. **This must land in the same change as R1** — under the transition latch the defect changes shape from "visible for one frame" to "whichever wrote last, permanently" |
| `slrow` / `tprow` | **CHANGE (budget only)** | `Stop 1.23456  (-25.00)` / `Target …`, `Clip(…, 22)` each | labels at `x+8` | — | — | [CONFIRMED FROM CODE] `risk_money` and `reward_money` are **already drawn here** (`:1410`, `:1414`) — any proposal to add them as new rows is struck |
| `rrrow` / `sizerow` | **KEEP** | `2.00 R` / `0.42 lot`, `- R` / `no size` | labels at `x+w-96` | — | — | `no size` in `SSR_C_STOP` is the right refusal: it says what is missing, not "invalid" |
| **`alwrow`** | **ADD** (slot 23) | `this stop would use 31 % of today's allowance`, `Clip(…, 46)` | one row | not a control | — | [RECOMMENDATION] The question a coach asks more than any other is unanswerable on any screen today. **One accessor on `CSSRPropEvaluation` — `DailyRoomAfter(double loss)` — and one pre-clamped wire field.** The arithmetic must not happen in the panel: `SheetProp`'s own comment says why (`:1732-1740`). Gated on `prop_on`; the row is **absent**, not zero, when no evaluation is configured |
| `openln` — *"Take the trade"* | **KEEP** | `Open LONG  0.42 lot` / `Place Buy stop  0.42 lot` / `cannot place` / `no size` | `w-16 × 22`, `SSR_C_BUY` or `SSR_C_SELL` | **PRIMARY of the sheet** | `Tab` (`SSR_CMD_OPEN_LINES`, listed, *"TAKE THE TRADE the lines describe"*) | [CONFIRMED FROM CODE] the label changes with what it will actually do (`:1441-1461`): two lines means open at market, three means place the named order. *"A button that reads 'Open LONG' and places a buy stop is a button that lied to the person who pressed it."* Keep verbatim |
| `flipbtn` | **KEEP** | `Flip  X` | `(w-28)/3 × 18` | secondary | `X` (`SSR_CMD_LINES_FLIP`, listed) | The key letter is printed on the face and the key is real — the one place in the product where that is currently true and correct |
| `enbtn` | **KEEP** | `Entry line` / `At market` | `(w-28)/3 × 18` | secondary | none | A toggle whose label names the state it will move to |
| `clrbtn` | **KEEP** | `Remove` | `(w-28)/3 × 18` | secondary | palette entry `clrbtn` | Clears the lines without clearing the plan's risk setting |
| `buy` | **KEEP** | `Buy  1.23456` | `(w-5)/2 × 24`, `SSR_C_BUY` | **PRIMARY pair** | none — deliberately | [CONFIRMED FROM CODE] dimmed when the lines describe the other side (`:1470-1473`), so the chart and the dialog cannot disagree. **No key, on purpose:** a market order with no stop is the one action that must cost a deliberate click |
| `sell` | **KEEP** | `Sell  1.23456` | `(w-5)/2 × 24`, `SSR_C_SELL` | **PRIMARY pair** | none | as `buy` |

**Refused for this destination, and each for a reason that does not expire:** a stop/target points
box (a stop typed in points is chosen by arithmetic; a stop dragged on the chart is chosen by
structure, and structure is the entire reason a person practises on a replay — `:1385-1391`); a lot
box (the lot is the answer, not the question); an order-type selector (MQL5 has no combo box, and
the geometry already names the order).

#### O.6.2 POSITIONS — `SheetPositions` (`SSR_Panel.mqh:1509-1666`)

**The row arithmetic is re-derived for 237 px before any control below is touched.**
[CONFIRMED FROM CODE] `ui-panel-7` (CONFIRMED, MEDIUM): the note is anchored at `x+120` (`:1576`) and
the money at `x + w - 116 = x+129` (`:1582`) — **nine pixels for the nine characters of `"  no stop"`**.
The two things a trader reads on that row are printed over each other.

```
x+0    pr<r>   "BUY 1.00 @ 53513"        Clip 18      ~92 px
x+96   pn<r>   "! no stop" / "sp 20.0"   Clip  8      ~40 px
x+140  pl<r>   "+38.20"                  Clip  8      ~40 px
x+180  three row buttons, 18 px each                   60 px
```

| Control (id) | Verdict | Label | Size | Rank | Key | Reason |
|---|---|---|---|---|---|---|
| `ph<r>` | **CHANGE (label)** | `H` → **`½`** | 18 × 17 at `x+w-68` | secondary | none | `ui-plumbing-14` (CONFIRMED, LOW): `H`, `B` and `X` are the same letters as three **global keys with three unrelated meanings** — `H` opens the key list, `B` bookmarks, `X` flips the planning lines. A user who reads the row hint as a key legend and presses the keys gets three unrelated actions, one of which changes trade state. **The dispatch id stays `ph<r>`**; only the drawn glyph changes |
| `pb<r>` | **CHANGE (label)** | `B` → **`BE`** | 18 × 17 at `x+w-47` | secondary, `SSR_C_RUN` text | none | as above. `BE` is the industry word and fits 18 px at `FS_SMALL` |
| `px<r>` | **CHANGE (label)** | `X` → **`✕`** | 18 × 17 at `x+w-26` | secondary, `SSR_C_STOP` text | none | as above. [CONFIRMED FROM CODE] the comment at `:1553-1562` records that this id was once `px`-the-label colliding with `px`-the-button and *"per-row close has not worked since it shipped"* — the id discipline that fixed it is preserved exactly |
| `ph<r>` / `pb<r>` on a pending row | **KEEP (removal)** | — | — | — | — | Both are `Remove()`d on a row that has not filled (`:1601-1605`). *"A button that always refuses teaches the user to distrust the row it sits on."* `✕` stays, because it still cancels the order |
| `poshint` (slot 31) | **CHANGE** | `½ halves · BE moves the stop to entry · ✕ closes`, `Clip(…, 52)` | label at `x+8`, own baseline | — | — | The hint now names the **actions**, not the letters — which is what removes `ui-plumbing-14` at the source. It doubles as the refusal row for `m_port.TradeError()`, which is [CONFIRMED FROM CODE] drawn **unclipped** today from a length-unbounded engine string |
| `posmore` (slot 30) | **CHANGE (position)** | `+%d not shown` | label | — | — | [INFERENCE] at `x+w-92 = x+153` it shares a baseline with the 37-character `poshint` from `x+8`, which reaches ≈`x+175`. The comment at `:1625-1632` claiming it sits "where nothing else is" was true at 295 px. Give it its own baseline |
| **`postog`** | **ADD** | `Open` / `Closed` | 78 × 22 | secondary, **stateful** | none | [CONFIRMED FROM CODE] the wire's position arrays are open-and-pending only; closed trades exist only in the exported CSV/HTML and as 43 *aggregate* measures on the review card. Between the four-second fill toast (`:787-803`) and the end-of-session card, **the record of an individual trade is unreachable**. For a training product that is the wrong gap to have |
| `be` | **CHANGE (width)** | `Break-even all` | `(245-10)/3 = 78 × 22` | secondary; enabled on `open_positions > 0` | none | The existing two-button row becomes three — `Open/Closed` · `BE all` · `Close all` — **at no cost in height**. The alternative, taking 19 px from the position group, drops `PosCap()` from 5 to 4, and one fewer visible position is a real regression for the moment this destination exists to serve. [RECOMMENDATION] shorten the two catalogue strings rather than clipping at the draw site; Persian is the tighter case |
| `flat` | **CHANGE (width)** | `Close all` | 78 × 22 | secondary; enabled on `open_positions > 0` | none | as `be`. It is **not** styled destructive: it closes virtual positions and the engine can be reset |
| `trdn` / `trup` / `troff` | **KEEP** | `-` / `+` / `off` | 18, 18, 42 × 19 | secondary | none | [CONFIRMED FROM CODE] `StepTrail` walks 0 / 50 / 100 / 150 / 200 / 300 / 500 with **off as a rung** (`:2131`), so `-` walks all the way back to off instead of sticking at 50. `troff` is the shortcut, not the only way out |
| `trlbl` (slot 32) | **CHANGE** | `Trailing stop  200 pt` / `off`, `Clip(…, 46)` | label | — | — | R5 |

**The gate on the Closed page, and it is not optional.** [CONFIRMED FROM CODE] `At(i,
SSRVirtualPosition&)` is a full struct copy, ~660 B plus two strings, so finding the newest 12 closed
trades is O(`Total()`) copies **per `ReadState`, i.e. ten times a second**, against up to
`SSR_MAX_POSITIONS 512` slots. [RECOMMENDATION] one setter — `CSSRGroupPort::WantClosed(bool)`,
called by the panel on a destination change and on `postog` — in the same shape as the existing
host-only setters (`SetTpPoints`, `NoteLineDistances`), so it costs no new pattern. The fill runs
only while the Closed page is up.

#### O.6.3 PERFORMANCE — `SheetStats` (`:1671`) replaced by `SSRReviewRows` (`SSR_Review.mqh:104`)

| Control (id) | Verdict | Label | Size | Rank | Key | Reason |
|---|---|---|---|---|---|---|
| `stmt` | **KEEP** | `Save HTML statement` | `w × 22`, moved to the sheet footer | secondary; enabled on `can_trade` | palette entry | It is the journal export, and this is where somebody looking at what the session did will look first. `Dispatch`'s `stmt` arm (`:2611-2623`) is unchanged |
| **`rvup` / `rvdn`** | **ADD** | `<` / `>` | 30 × 19 each, sheet's last 19 px | secondary | none | [CONFIRMED FROM CODE] the product already has exactly one correct answer to "more rows than fit", and it is the review card: `SSR_RV_SHOWN 12`, `m_first`, explicit up/down, header comment *"PAGED, BECAUSE MQL5 CANNOT CLIP"* (`SSR_ReviewCard.mqh:12`). **A destination that overflows pages. Never a scrollbar, never a "show more" that grows the frame** |
| **page counter** | **ADD** | `1-8 of 43` | label between the pagers | — | — | The pager must say where it is, or paging is a guess |
| 43 measure rows | **ADD via `ListRO`** | generator rows, `Clip(…, 52)` | 8-9 rows/page Standard, 17 Expanded | **read-only** | none | [RECOMMENDATION] Add `ListRO` beside `CSSRWidgets::List` (`SSR_Widgets.mqh:565`). [CONFIRMED FROM CODE] `List` draws `ButtonC`/`Button` rows (`:571-587`) — a false affordance on rows that are read, never chosen — at **9 writes a row**. `ListRO` is one `Rect` well plus a cached `Label` per row: **6 writes a row**, same `first`/`shown`/`Remove`-the-tail contract. It also retires `ui-dialogs-16` (CONFIRMED, IMPROVEMENT), where the review card's 12 measure rows are `OBJ_BUTTON`s whose latch nothing consumes, so a clicked statistic stays drawn pressed |
| `st1` / `st2` / `st3` | **REMOVE** | balance / equity / floating | — | — | — | They duplicate `stbal` and `stflt` in the status strip 200 px below |
| `st4` / `st5` / `st6` | **MOVE to SESSION** | bars / ticks / rejected+guard | — | — | — | They describe what the *machine* did, not what the *trainee* did. [CONFIRMED FROM CODE] `core-engine-5` (CONFIRMED, MEDIUM) adds a second reason: `bars_consumed` counts a bar once per pump that touches it, so the figure is wrong by 10-1500× and **must not sit beside trading measures where it reads as one** |
| `st7` | **REMOVE** | `see the Prop tab` | — | — | — | The Eval cell is permanently in the rail now. A pointer to a visible tab is a row spent on nothing |

**Two semantics this sheet must not flatten.** [CONFIRMED FROM CODE] profit factor stays `0` when
`gross_loss == 0` by deliberate design (`SSR_Statistics.mqh:526-530`) — **draw `-`, never `0.00`**
(`trading-analytics-6`, CONFIRMED, LOW, shows the 0.00 lie already propagating). And `average_r` is
computed only over trades with `risk_at_entry > 0` (`:532-536`), which is why `r_trades` exists —
**always print the R sample as "a of b"**.

#### O.6.4 SESSION — `SheetSession` (`SSR_Panel.mqh:1877-1908`)

| Control (id) | Verdict | Label | Size | Rank | Key | Reason |
|---|---|---|---|---|---|---|
| **`jump`** | **RESTORE as a sheet button** | `Jump…` | 78 × 22 | secondary | `J` (`SSR_CMD_JUMP`, listed) | [CONFIRMED FROM CODE] the `Dispatch` arm `what == "jump"` is **already live** at `:2719` and the comment beside it says so: *"follow / bookmark / jump have no buttons any more. Their keys F, B and J still route here, so these are NOT dead."* Restoring the affordance costs **one `m_w.Button` call and nothing else** |
| **`sessions`** | **ADD (second site)** | `Sessions…` | 78 × 22 | secondary | `S` | Same id as the action strip's; one dispatch arm, two draw sites, no drift |
| **`bookmark`** | **RESTORE as a sheet button** | `Mark here` | 78 × 22 | secondary | `B` (`SSR_CMD_BOOKMARK`, listed) | Dispatch arm live at `:2717`. One `m_w.Button` call |
| `ses1` | **KEEP** | `Bookmarks   3` | label | — | — | [FUTURE FEATURE] the *list* needs two new port verbs — the port can write a bookmark (`SSR_GroupPort.mqh:490`) but has no verb for "list them" or "go to i". Ship the count and the buttons first |
| **`savepos` / `resumepos`** | **ADD** | `Save position` / `Resume position` | 116 × 22 each | secondary | none | [CONFIRMED FROM CODE] `CSSRGroupPort::SavePosition` (`:495`) and `ResumePosition` (`:506`) are real implemented overrides with **no UI caller anywhere** — no button, no `Dispatch` arm, no key, no palette entry — and the wire already carries `has_saved_position` and `checkpoints`. Two buttons and two `Dispatch` arms turn two orphan verbs from invisible into operable. [POTENTIAL_RISK] neither verb has ever been exercised from a UI; `ResumePosition` calls `m_group.SeekAllTo(c.Now())` across every stream. Ship them behind the same arm-and-confirm discipline as `reset`, and treat the first terminal run as the test |
| **`follow`** | **RESTORE, conditionally** | `Bring back` | 72 × 19, at the right end of the **charts adrift** row | secondary | `F` (`SSR_CMD_FOLLOW`, listed) | Dispatch arm live at `:2716`. **Drawn only while `charts_detached > 0`** and `Remove()`d otherwise — a recovery control that appears exactly when it can do something, which is the one honest way to spend an id that has no permanent home. See O.9 |
| `ses2` / `ses3` | **CHANGE (budget)** | streams + skew; `charts: clean` / `leak_advice` | labels, `Clip(…, 52)` | — | — | `ses3` is already clipped at 62 (`:1892`) — the real budget at 237 px is **52**. `chart-7` (CONFIRMED, MEDIUM): `LeakGuard::Advice` is written far longer than its only consumer can display. `Clip()` makes the cut honest; shortening the advice at source makes it useful. **Fix both** |
| `ses4` / `keyhint` / `ses5` / `ses6` | **REMOVE** | `SSR_S_KEYS_1..4` | — | — | — | `ui-plumbing-2` (CONFIRMED, MEDIUM): three of the four are factually wrong. `keys.2` says *"R reset"* while `R` is `SSR_CMD_LINES_TOGGLE` (`SSR_Keys.mqh:162`) and reset is `0` (`:200`) — and `fa.txt:216` faithfully mistranslates it as `R شروع دوباره`. `keys.4` still teaches the `[]` caption button **deleted in v125**. They move to KEYS, where they are *generated*; the four catalogue strings retire with them, freeing 72 px |
| new rows from orphan wire fields | **ADD** (slots 24-29) | bars / ticks / rejected+guard (moved), pump p95, µs/tick (gated on `perf_calibrated`), charts adrift, strategies | labels, `Clip(…, 52)` | — | — | [CONFIRMED FROM CODE] a grep for `m_state.<field>` over `SSR_Panel.mqh` returns **0** for `strategy_text`, `pending_count`, `checkpoints`, `has_saved_position`, `perf_calibrated`, `us_per_tick`, `pump_p95_ms`, `charts_detached`, `stop_points`, `tp_points`, `prop_floor` — while `CSSRGroupPort` fills every one. That is the cheapest new information in the product: no port change, no engine change, no new observer. (`stop_points` / `tp_points` stay deliberately undrawn — a stop in points is the thing the lines design replaced) |

#### O.6.5 KEYS — new sheet, rendered from `SSRKeyBindings()` (`SSR_Keys.mqh:125`)

| Control (id) | Verdict | Label | Size | Rank | Key | Reason |
|---|---|---|---|---|---|---|
| 18 listed key rows | **ADD via `ListRO`** | `label` at `x+0` (`Clip 16`), `what` at `x+74` (`Clip 36`) | 9 rows/page Standard, **all 18 in Expanded, no pager** | read-only | — | [CONFIRMED FROM CODE] the key table is a single generated source of truth and the key card's height is *counted* from it. **Extend it; do not replace it** |
| `kyup` / `kydn` | **ADD** | `<` / `>` + `1-9 of 18` | 30 × 19 | secondary | none | Paged, because MQL5 cannot clip |
| header | **ADD** | `All virtual — nothing reaches a broker.` (`SSR_S_ALL_VIRTUAL`) | label | — | — | The one sentence the removed first-run card existed to deliver, now on a surface that cannot be consumed unseen |
| **`CSSRKeyCard` (`SSRK_`, 132 lines)** | **REMOVE — the whole class** | — | — | — | `H` now selects `tab4` | `ui-panel-12` (CONFIRMED, MEDIUM): `Show()` begins with `m_w.RemoveAll()` (`SSR_KeyCard.mqh:72`) and recreates ~41 objects — **~41 deletes + 41 creates + ~450 writes per frame while the card is up**, because anything opened over the panel goes back under it on the next repaint and must be re-`Show()`n (`SSR_Panel.mqh:767-777`). This is the exact case R3 exists to catch: an overlay costs a rebuild per frame, a destination costs a rebuild per click |
| **`CSSRFirstRun` (`SSRF_`, 148 lines) + `seen.txt`** | **REMOVE — the whole class** | — | — | — | — | Replaced by **one branch in `RestorePlace()`**, which is already there waiting (`SSR_Panel.mqh:555-557`): no `panel.ini` → the opening destination is KEYS. One `if`, no new class, no fixed coordinate to be wrong about. Fixes `host-expert-4` (the card shows on **neither** pass of the default one-window handover, `SSReplayStandalone.mq5:1736`) and `ui-dialogs-14` (on a chart under ~480 px it draws off-screen and `seen.txt` is written anyway) |

**Three hand-written key lists collapse into one.** [CONFIRMED FROM CODE] `ui-plumbing-3` (CONFIRMED,
LOW): `SSRKeyHint()` (`SSR_Keys.mqh:271`), printed to the Experts log, is a third list that also says
"R reset". Generate it from `SSRKeyBindings()`. Add `ENUM_SSR_STR` ids for the 18 `what` strings —
`ui-plumbing-1` (CONFIRMED, MEDIUM), the key card's rows being the one user-facing surface outside
`T()` — catalogue 190 → 208. **Then the product ships one key list instead of four.**

#### O.6.6 EVAL — `SheetProp` (`SSR_Panel.mqh:1749-1873`)

| Control (id) | Verdict | Label | Size | Rank | Key | Reason |
|---|---|---|---|---|---|---|
| `pp_reset` | **KEEP** | `Reset evaluation` | as drawn | secondary | none | `Dispatch` arm at `:2624-2631`. It resets the *evaluation*, not the session — a different verb from the transport's `reset`, and the labels say so |
| four meters | **KEEP, unchanged in structure** | each with its number beside it | as drawn | not controls | — | [CONFIRMED FROM CODE] *"THIS SHEET COMPUTES NOTHING"* (`:1732-1740`) and *"EVERY METER HAS ITS NUMBER BESIDE IT"* — a bar is unreadable to a colour-blind trader and meaningless to anyone who has not learned which way is bad. Preserve verbatim |
| `pp_rules` (slot 61) | **CHANGE (budget)** | `Clip(…, 62)` → **`Clip(…, 52)`** | label | — | — | 62 was the 63-character limit; **52** is the 237 px sheet |
| `pp_head` | **KEEP** | `Clip(…, 44)` | label | — | — | Already correct |
| **`alwrow` (second reader)** | **ADD** | `DailyRoomAfter()` in **money** | one row | — | — | Same accessor as TRADE's percentage sentence. One owner, two readers, no second formula |
| Expanded's extra 140 px | **ADD nothing** | — | — | — | — | The sheet's worst case is a finished run with a deadline at 178 of 186 px. A fifth meter for a rule most challenges do not set would teach nobody what it counts. **Whitespace is the premium choice here, and it is free** |

---

### O.7 The status strip — `DrawStatus` (`SSR_Panel.mqh:1915-2035`)

Not buttons, and M.3.7 rejects making them buttons on four grounds — the strongest being that
[CONFIRMED FROM CODE] four of the five ladder levels write **slot 50 / id `stbal`** (`:1929`,
`:1947`, `:1988`, `:2001`), so the product's one destructive question would be drawn on a control
that navigates. They are listed here because one of them is deleted and one is added.

| Slot / id | Verdict | Content | Budget | Reason |
|---|---|---|---|---|
| 50 `stbal` | **KEEP** | balance | `Clip 14` | — |
| 51 `stflt` | **KEEP** | floating | `Clip 12` | — |
| 52 `stopen` | **KEEP** | `N open (+P)` | `Clip 9` | — |
| 54 `stspread` | **KEEP, yielding** | `sp N.N` | `Clip 8` | Replaced by `chartsn` while `charts_detached > 0`. Spread is the right thing to yield the slot — it also appears on the Trade sheet and in the fill toast |
| **53 `stfid`** | **REMOVE** | fidelity | — | `ui-panel-6` (CONFIRMED, **HIGH**): anchored at `x + 330` in a **310 px** panel (`:2033`), and `"SYNTHETIC TICK !"` adds 70-80 px more — ~90 px of text on the candles **on every frame of every session**. The fix is deletion, not relocation: fidelity is already the `chfid` caption chip from the same `SSRFidelityShort()`, and the caption's own comment says why it belongs there — *"it is a mode, not a measurement"* |
| **53 `chartsn`** | **ADD** | `N adrift  F` | `Clip 8` | The slot freed above pays for the one piece of *information* v125's removals cost. See O.9 |
| optional `stmsg` | **ADD (hygiene)** | the ladder's four warning lines | — | [RECOMMENDATION] Not a live defect — the ladder hides the other four readouts, so it is exclusive by construction — but slot-sharing between two unrelated texts at one coordinate is precisely the shape of `ui-panel-5`. One id |

**The fill toast** (`SSRP_fill*`, `:787-803`) is the panel's only push notification and stays.
`ui-panel-10` (CONFIRMED, MEDIUM): in Compact it is placed at `y + 128 - 18 - 24 = y+86`, directly on
the speed row (`y+82..y+101`) and **above it in creation order**, for four seconds per fill — in the
mode where the speed control is one of only four things left. [RECOMMENDATION] in Compact the toast
**replaces the status strip line** rather than floating above it: same information, zero occlusion,
and the strip is the lowest-priority band by the ladder's own ordering. [CONFIRMED FROM CODE] its
`"   spread %.1f pt"` and `"   NO STOP"` are English literals (`:795`, `:799`) while translated
equivalents `SSR_S_SPREAD_SHORT` and `SSR_S_NO_STOP` exist and are used on the Positions row 700
lines away. Route them through `T()`.

---

### O.8 The setup panel — `CSSRSetupPanel` (`SSR_SetupPanel.mqh`, `SSRS_`, 304 px)

Four steps: QUICK → SETTINGS → MODE → START, centred on the **tallest** step
(`SSR_SETUP_H_MAX 482`) so it does not jump under the hand pressing Next. **The structure is right
and this redesign changes none of it.** What changes is what `ReadAll()` does and what a control is
allowed to claim.

| Control (id) | Verdict | Label | Size | Rank | Key | Reason |
|---|---|---|---|---|---|---|
| `qlast` | **KEEP** | `Same as last time` + a summary line | `280 × 26`, `SSR_C_PRIMARY` | **PRIMARY of step 0** | none | The right default is the one that needs no decision, and it shows what it will do before it does it |
| `qcont` | **KEEP** | `Continue "<name>"` | 280 × 26 | secondary | none | **Blocked on `ui-dialogs-1`** — see below. Until that lands, this button is offered against a session that was never written |
| `qrand` | **KEEP** | `Random start` + why | 280 × 26 | secondary | none | — |
| `qcust` | **KEEP** | `Customise` | 280 × 22 | secondary, deliberately last and smallest | none | Progressive disclosure: the 61 expert inputs are behind the least prominent control on the step |
| `e<id>` / `b<id>` rows | **CHANGE (read contract)** | 14 fields | `SSR_SETUP_FIELD_W` | secondary | — | `ui-dialogs-1` (CONFIRMED, **HIGH**) — the largest single defect in the UI subsystem. `ReadAll()` runs on steps that contain no `OBJ_EDIT`, and `EditText()` returns `""` both for an empty box and an absent one (`SSR_Widgets.mqh:350-356`), so walking the wizard normally **silently clears `session_name` and `extra_tfs`**; step 3 recaps "Save as: not saved", `CfgSession()` is `""`, and `OnDeinit`'s `if(CfgSession() != "")` never runs — **the whole session is never written to disk and cannot be resumed**. Distinguish "empty box" from "absent box" at `SSR_Widgets.mqh:350`. **Nothing else in this section ships before this does**, because `Sessions…` becomes a permanent control pointing at that list |
| `m<i>` pseudo-combo | **CHANGE (lifetime)** | preset rows | `ih` each | secondary | none | `ui-dialogs-2` (CONFIRMED, MEDIUM): an open pseudo-combo **survives a step change and is redrawn last — i.e. on top** — over the START step, so the click aimed at "START REPLAY HERE" applies a preset instead. `MenuClear()` must run on every step transition, not only on selection. `ui-dialogs-15` (CONFIRMED, LOW) adds that `MenuClear` sweeps 32 items against an unbounded `presets.ini`, orphaning live preset buttons on the chart — sweep to the count that was drawn, not to a constant. **Do not build a second pseudo-combo anywhere** (M.1.1) |
| `next` | **KEEP** | `Next: mode` | `280 × 26`, `SSR_C_PRIMARY` | **PRIMARY of steps 1-2** | none | *"NOTHING ON THIS STEP CAN START A REPLAY. That is the point."* (`:805`) |
| `back` | **KEEP** | `Back` | 280 × 20 (74 × 26 on START) | secondary, visibly lighter | none | The way back is always beside the way forward and never the same weight |
| `eseed` (`OBJ_EDIT`) | **KEEP** | the seed | `280 × 15` | secondary | none | *"a seed nobody can copy is a reproducibility feature nobody can use"* (`:900-911`). Correct |
| `here` | **KEEP** | `Bring the line here` | 280 × 22 | secondary | none | — |
| `startlbl` | **CHANGE (anchor)** | `drag the line` / `m_start_text` | label | — | — | `ui-dialogs-13` (CONFIRMED, LOW): the orange-line caption is drawn at the START step's **stale `m_start_y`** while another step is on screen — a label from a step the user is not on, on the candles |
| `go` | **KEEP** | `START REPLAY HERE` | `200 × 26`, `SSR_C_BUY` | **PRIMARY, and the one irreversible control in the wizard** | none | Isolated from `back` by 18 px, on its own row, coloured as a deal because it commits one |
| numeric clamps | **CHANGE** | — | — | — | — | `ui-dialogs-9` (CONFIRMED, LOW): `ReadAll` clamps balance/risk/spread/speed and **not** the three prop numbers, so a typed `0` silently deletes a prop rule while the panel keeps drawing the chips and meters. The preset *file* loader already refuses exactly this shape (`:342`); the keyboard is not validated. [POTENTIAL_RISK] `ui-dialogs-8` — `Num()` replaces `,` with `.`, so `"10,000"` becomes `10.0` and passes the `<= 0` guard: a session that starts with a balance of 10 |
| caption drag | **REMOVE the claim** | — | — | — | — | `ui-dialogs-6` / `host-expert-14` (CONFIRMED): nothing enables `CHART_EVENT_MOUSE_MOVE` before `CSSRPanel::Create` exists, so during the picking phase **every branch of `OnChartEvent` is unreachable**, `SavePlace()` never runs, `SSR_SETUP_X/Y` never exist, and the window re-centres on every run — sitting over the candles the user must now drag the start line onto. [RECOMMENDATION] either enable the event in `CSSRSetupPanel::Show`, or delete the drag code and give the wizard the same corner-step verb the panel gets in O.9. **Do not ship a drag handle that cannot fire** |

---

### O.9 The six controls removed in v125 — what the redesign does with each

[CONFIRMED FROM CODE] Commit `08daaf8`, *"six buttons removed on request — and removed, not just
undrawn"*. The **method** was correct and is preserved: each id is `Remove()`d, because a panel that
repaints from state and never clears the chart leaves an undrawn object on the chart for ever
(invariant I7). Only the **consequences** are in question, and the caption's own comment block at
`SSR_Panel.mqh:915-931` is the record this section answers.

| Removed in v125 | What it did | v125 left it reachable by | **This redesign** | Restored? |
|---|---|---|---|---|
| `?` (caption, 18 px) | opened the key card | `H` only | **KEYS becomes rail cell `tab4`** (O.5, O.6.5), permanently visible in every Standard and Expanded frame; `CSSRKeyCard` deleted | **Function fully restored, and improved.** No button comes back — a permanent rail cell is strictly better than a caption button that opened a 10 Hz-rebuilt overlay |
| `K` (caption, 18 px) | opened the command palette | `Ctrl+K` only | `Ctrl+K` **added to `SSRKeyBindings()` with `listed = true`**; the KEYS destination then prints it; the code comment at `:929` is corrected | **Reachability was never lost** — see O.10. **Discoverability restored**, by a key row rather than a button |
| `[]` (caption, 18 px) | `SnapToCorner()` — stepped the panel between the four corners | the palette's `move` entry only | **`SSR_CMD_PANEL_MOVE` added to the command enum and bound to `M`** (`listed = true`); `Owns()`/`ExecuteInner` gain one arm; the palette entry changes from an `action` string to a `cmd`; `Dispatch`'s `move` arm (`:2600-2610`) stays exactly as written | **Function fully restored, by key.** The button does not come back — O.1's arithmetic shows there is no 18 px of caption left in 310 px |
| `Follow` (action strip, 96 px) | `SSR_CMD_FOLLOW`, **and carried the detached-chart count in its own label** | `F` only | **Two restorations.** (1) the *readout*: `chartsn` on the status strip in the slot freed by deleting `stfid` (O.7), plus a **charts adrift** row on SESSION; (2) the *verb*: a conditional `follow` button at the right of that row, drawn only while `charts_detached > 0` | **Both halves restored** — the information permanently, the button conditionally. No action-strip cell comes back; there is no fourth 96 px cell |
| `Mark` (action strip, 96 px) | `SSR_CMD_BOOKMARK` | `B` only | **`Mark here`, 78 px, in SESSION's "Where" group** (O.6.4) | **Restored as a button**, on the destination that is about *where you are* |
| `Jump` (action strip, 96 px) | `SSR_CMD_JUMP` | `J` only | **`Jump…`, 78 px, in SESSION's "Where" group** | **Restored as a button.** Gated on `host-expert-7` — promoting it to a permanent control makes that dialog the *normal* way into the moment, which multiplies the exposure |

**Three of the six cost only a shortcut; one cost information; two cost a contract.**
[CONFIRMED FROM CODE] Eight catalogue entries were orphaned by the removals — `SSR_S_FOLLOW`,
`SSR_S_FOLLOW_N`, `SSR_S_BOOKMARK`, `SSR_S_JUMP`, `SSR_S_ACT_FOLLOW`, `SSR_S_ACT_FOLLOW_N`,
`SSR_S_ACT_BOOKMARK`, `SSR_S_ACT_JUMP` — still translated in `fa.txt:242-247`, so `SSRTranslated()`
reports 190/190 for a catalogue in which 8 strings are unreachable. **Five of the eight come back
into use** at the new draw sites above (`SSR_S_ACT_FOLLOW_N` is superseded by the `chartsn` readout
and `SSR_S_ACT_FOLLOW` by the shorter `Bring back`); the remaining ones are retired with the
`SSR_S_KEYS_1..4` block, so the catalogue arrives back at a state where every string has a site.

---

### O.10 The two regressions, stated plainly

#### O.10.1 "The command palette is now unreachable — it had no key binding"

**That is not what the code does, and the record should be corrected rather than designed around.**

[CONFIRMED FROM CODE] `SSR_Panel.mqh:2827-2832` opens the palette on `Ctrl+K`, tested **before** the
key table so nothing can shadow it:

```cpp
if(id == CHARTEVENT_KEYDOWN && (int)lparam == SSR_VK_K &&
   TerminalInfoInteger(TERMINAL_KEYSTATE_CONTROL) < 0)
  { m_palette.Toggle(m_chart); return true; }
```

and the registry behind it is fully wired — 31 commands in four groups (`SSR_Command.mqh`), with
`RunChosen()` (`:2423`) dispatching both `cmd` and `action` entries down the two paths that already
existed. **The palette works.** What is broken is named by `ui-plumbing-15` (CONFIRMED, LOW):
`SSR_VK_K` is **not in `SSRKeyBindings()`**, so `SSRKeyToCommand(75)` returns `SSR_CMD_NONE`, the
generated key list — the product's only key list — cannot mention it, and the code comment three
hundred lines away asserts the opposite outcome: *"K the command palette had no key and is now
unreachable"* (`:929`).

[INFERENCE] The practical position is worse than "unreachable" would be: a working feature nobody can
find, which the team's own record says was lost, and which is simultaneously **the only surviving way
to move the panel**.

**What the redesign does, in order:**

1. **Add the binding.** `SSRAddKey(out, i, SSR_VK_K, "Ctrl+K", SSR_CMD_PALETTE, "every command, searchable", true)` in `SSRKeyBindings()`. The `Ctrl+K` early test at `:2827` stays exactly where it is — *checked before the key table so a future binding on K cannot shadow the palette by accident* — and the new row exists so the table can **describe** it, not so it can dispatch it.
2. **KEYS (rail cell `tab4`) prints it**, in a destination a trainee cannot miss.
3. **Correct the comment at `:929`** and the `SSR_S_KEYS_4` string that still teaches `[]`.
4. **No button is restored.** The palette stays an overlay under R3 — it is a search field that must float over what it searches — and it is the honest answer to Compact mode, which has no rail and no sheet (`if(!m_compact)` guards `DrawActions`, `DrawRail` and `DrawSheet` together at `:740-752`).

**[CONFIRMED FROM CODE] Verdict: the regression was documentation and discovery, not reachability.
The redesign closes both and adds no pixel to the caption.**

#### O.10.2 "The panel can no longer be moved at all — it cannot be dragged, because it receives no mouse coordinates"

**This one is real under this audit's ground truth, and it is the sharper of the two.**

[CONFIRMED FROM CODE] The removal rationale states the premise twice — *"the panel cannot be dragged
— it never receives a mouse coordinate on a chart this program is not attached to"*
(`SSR_Panel.mqh:929-931`, and again at `SSR_Widgets.mqh:437-443`). Under that premise, after `[]` was
deleted the **only** way to move the panel is the palette's `move` entry
(`SSR_Command.mqh:110-111` → `Dispatch`'s `move` arm at `:2600-2610`) — a control reachable only
through a surface the product never names. [INFERENCE] A panel that cannot be moved is not a cosmetic
loss: it is fixed at a saved corner over whichever candles happen to be there, on a chart the user is
being asked to drag stop and target lines onto.

**And the wiring disagrees with the premise.** [CONFIRMED FROM CODE] `SSReplayStandalone.mq5:1463` is
`g_panel_chart = ChartID();`, `Create()` executes
`ChartSetInteger(m_chart, CHART_EVENT_MOUSE_MOVE, true)` (`SSR_Panel.mqh:324`), `OnEvent` handles
`CHARTEVENT_MOUSE_MOVE` in full including caption drag with `SavePlace()` on release (`:2885-2966`),
and `SSReplayStandalone.mq5:3228` forwards every chart event to it. `ui-panel.md` invariant I1
records the conflict as unresolved. **This audit takes the pessimistic side** (M's opening premise),
and so does the fix below.

**What the redesign does:**

1. **Bind the verb to a key.** Add `SSR_CMD_PANEL_MOVE` to the command enum, bind it to **`M`** with `listed = true`, add the `Owns()`/`ExecuteInner` arm, and point it at the existing `SnapToCorner(); SavePlace();` pair. [CONFIRMED FROM CODE] `M` collides with nothing: the 22 bound vk values are Space, Left, Right, PgUp, PgDn, `+`/`-` (×2 each), `R`, `Tab`, `X`, `L`, `J`, `B`, `S`, `F`, `D`, `0`, `A`, `P`, `H`, plus `Ctrl+K` outside the table.
2. **KEYS prints it**, so the one control that repositions the panel is named on a permanently visible destination — which is exactly what `[]` never was.
3. **Change the palette entry from an `action` to a `cmd`**, so the palette, the key and the key list all read one row. The `Dispatch("move")` arm stays untouched, so putting a button back is still the one line the comment at `:2598-2601` promises.
4. **Fix the stale log line.** [CONFIRMED FROM CODE] `SSR_Panel.mqh:354` still prints *"no saved position - starting at %d,%d (drag it by the title bar, or press Move)"* — naming a drag that may not exist and a button that certainly does not.
5. **Do not restore drag, and do not restore `[]`.** Drag needs a mouse coordinate this architecture refuses to assume; `[]` needs 18 px of caption that does not exist (O.1).

**[CONFIRMED FROM CODE] Verdict: the function is fully restored — four corners, persisted by
`SavePlace()`, reachable by one key and named on one destination. Free positioning is NOT restored
and cannot be** without settling L.4.2 on a terminal. [RECOMMENDATION] Settle it first, as L.11
says: if mouse events do arrive, the caption drag already written at `:2885-2966` becomes a bonus on
top of `M`, and `ui-panel-11`'s tag-box focus path comes alive with it. If they do not, `M` is the
whole answer and the dead drag code should be deleted rather than left as a promise.

---

### O.11 The key table after this redesign

[CONFIRMED FROM CODE] 22 bindings today, all vk values distinct, 18 `listed`. This redesign adds
**two rows and no conflicts**, and the KEYS destination is generated from the result — so the table
below is not a second list to drift, it is a preview of what the destination will print.

| Key | Command | Control it reaches | listed | New? |
|---|---|---|---|---|
| `Space` | `TOGGLE` | `toggle` | yes | — |
| `Left` / `Right` | `STEP_BACK` / `STEP_FWD` | `back` / `step` | yes | — |
| `PgUp` / `PgDn` | `STEP_BACK_10` / `STEP_FWD_10` | `back10` / `step10` | yes | — |
| `+` / `-` (and Num) | `SPEED_UP` / `SPEED_DOWN` | `spup` / `spdn`, and **the only path to an odd ladder stop** | yes (one row) | — |
| `R`, `L` | `LINES_TOGGLE` | `lines`, `armbtn` | yes / no | — |
| `Tab` | `OPEN_LINES` | `openln` — *take the trade* | yes | — |
| `X` | `LINES_FLIP` | `flipbtn` | yes | — |
| `J` | `JUMP` | SESSION `Jump…` | yes | — |
| `B` | `BOOKMARK` | SESSION `Mark here` | yes | — |
| `S` | `SESSIONS` | `sessions` (action strip **and** SESSION) | yes | — |
| `F` | `FOLLOW` | SESSION `Bring back` (conditional) | yes | — |
| `D` | `FIDELITY_CYCLE` | `fidelity` | yes | — |
| `0` | `RESET` | `reset` (arms it — the same button asks) | yes | — |
| `A` | `REVIEW` | review card | yes | — |
| `P` | `PANEL_SIZE` | Expanded wish | yes | — |
| `H` | `KEYS` | **rail cell `tab4`**, no longer an overlay | yes | changed target |
| **`Ctrl+K`** | **`PALETTE`** | the command palette | **yes** | **ADD** (O.10.1) |
| **`M`** | **`PANEL_MOVE`** | `SnapToCorner()` | **yes** | **ADD** (O.10.2) |
| — | `PLAY`, `PAUSE`, `RESTART`, `REPLAY_FROM_HERE`, `COLLAPSE` | each has a button or is host-owned | — | unchanged |

[CONFIRMED FROM CODE] The invariant that makes this table safe — `Owns()`/`ExecuteInner` kept in step
so a key cannot be claimed and die (invariant I12) — is preserved: both new commands get their arm in
the same edit that adds their row.

**And one audit is added with them.** [RECOMMENDATION] **A23**, sibling to M's A22: *no drawn string
may name a key letter the table does not bind to the command the sentence describes.* That is the
only instrument that would have caught `keys.2` saying "R reset" for three builds, `keys.4` teaching
a deleted `[]`, `SSRKeyHint()` repeating both, and `SSR_S_ROW_HINT` printing `H B X` as if they were
keys.

---

### O.12 Dialogs and cards — the controls, and what each is allowed to claim

Every control below is gated on **`host-expert-7`** (CONFIRMED, MEDIUM): keys are not withheld while
a dialog is open, so `Space` starts the replay, `Tab` opens a virtual trade and `0` arms the session
reset while the user reads a modal — and the panel's `Render()` then repaints over it, because
creation order is the only z-order. [CONFIRMED FROM CODE] `CSSRReviewCard::OnKey` already shows the
fix: it returns `true` for every key while up. **Copy it into both dialogs before any new clickable
control in this section ships.**

**Range / "jump" dialog** — `CSSRRangeDialog` (`SSRD_`, 248 × 214), `CHARTEVENT_OBJECT_CLICK`.

| Control | Verdict | Label | Size | Rank | Reason |
|---|---|---|---|---|---|
| `close` | KEEP | `x` | 18 × 15 | secondary | — |
| `tf<i>` | KEEP | timeframe row | `bw × 19` | secondary | The pseudo-combo rule applies: these are buttons, not a dropdown, and they must not outlive the step |
| `more` | **CHANGE** | `Load more` | 96 × 22 | secondary | `ui-dialogs-3` (CONFIRMED, MEDIUM): `Recompute()` unconditionally resets `m_problem` (`:127`) on the line after the two places that set it, so **a bad date produces no error at all** and LOAD MORE is mute. The comment at the site — *"a typo must not silently become 1970"* — describes the exact failure the code produces |
| `start` | **CHANGE (what it claims)** | `Start` | 96 × 22 | **PRIMARY** | `ui-dialogs-7` (CONFIRMED, MEDIUM): the dialog validates against **broker** history while its only caller can jump inside the **already-loaded session window**, so a valid-looking START silently does nothing but print to the log. The title "NEW SESSION" and the word "START" reinforce the wrong expectation. Either validate against the loaded window or rename both |
| refusal label | **CHANGE (budget)** | `Clip(…, 40)` | label | — | `ui-dialogs-5` (CONFIRMED, MEDIUM): the refusal is drawn unbounded into one label; the "start too early" text is 77-78 characters and MetaTrader draws 63, so the user reads a sentence that **looks complete** and names a year instead of the instant. The refusal is the dialog's whole purpose |

**Session picker** — `CSSRSessionDialog` (`SSRSD_`, 420 × 260, 8 rows).

| Control | Verdict | Label | Size | Rank | Reason |
|---|---|---|---|---|---|
| `close` | KEEP | `x` | 18 × 15 | secondary | — |
| row buttons | **CHANGE (budget)** | per-session summary | `SSR_SD_W-12 × 16` | secondary | `ui-port-session-7` (CONFIRMED): the summary is roughly twice what the row can draw. `ui-port-session-12` (CONFIRMED, LOW): **every visible row re-parses its whole session file on every render** — cache the parse per row, keyed on the file's modification time |
| `up` / `down` | KEEP | `^` / `v` | 40 × 22 | secondary | The paging primitive `ListRO` inherits (M.3.5) |
| `load` | KEEP | `Load` | 95 × 22 | **PRIMARY** | — |
| `del` | **REMOVE or IMPLEMENT — not both halves** | `Delete` | 95 × 22 | destructive | `ui-dialogs-11` (CONFIRMED, LOW): **it is drawn enabled, looks live, deletes nothing**, and explains itself in an 86-character message that draws to 63. A control that claims a destructive action, performs none, and half-explains why is worse than no control. If it cannot be implemented this build, `Remove()` it |
| `yes` / `no` | **REMOVE (whole mode)** | `Replace` / `Keep` | 110 × 22 | — | `ui-dialogs-12` (CONFIRMED, LOW): `RequestSave()` and the entire `SSR_SD_CONFIRM_SAVE` mode **have no caller**, so the header's promise *"IT ASKS BEFORE IT OVERWRITES"* is not a behaviour the shipped tool has — sessions are overwritten silently by the host's `OnDeinit`. Either wire it or delete the mode and the promise together |
| resume warnings | **CHANGE (budget)** | `Clip` per line | labels | — | `ui-port-session-8` (CONFIRMED): warnings are newline-joined into a single 63-character label |

**Review card** — `CSSRReviewCard` (`SSRR2_`, 520 × 320+, 43 measures paged 12).

| Control | Verdict | Label | Size | Rank | Reason |
|---|---|---|---|---|---|
| 12 measure rows | **CHANGE to `ListRO`** | generator rows | as drawn | **read-only** | `ui-dialogs-16` (CONFIRMED, IMPROVEMENT): they are `OBJ_BUTTON`s whose latch nothing consumes, so a clicked statistic stays drawn **pressed** until the user pages — a false affordance on a card whose whole purpose is to be read. Same primitive as PERFORMANCE and KEYS, one fix, three surfaces |
| `up` / `down` | KEEP | `Up` / `Down` | 36 × 18 | secondary | The paging discipline is correct and is the model the destinations copy |
| `stmt` | KEEP | `Save HTML statement` | 150 × 20 | secondary | Same id and same dispatch as PERFORMANCE's footer |
| `close` | KEEP | `Close` | 80 × 20 | **PRIMARY** | — |
| observations | **CHANGE (budget)** | ≤6 sentences | labels | — | `ui-dialogs-4` (CONFIRMED, MEDIUM): two sentences exceed 63 characters for **every possible value**, and the ambiguous-bar line renders as *"…reached both the stop and the t"* — which reads as a plain stop-out and loses the single most important caveat this product reports about a fill. They live in `SSR_Review.mqh` `StringFormat` literals, outside `T()`. **Shorten at source and route through `T()`; clipping alone makes the cut honest but still loses the sentence** |

**Reveal card** — `CSSRRevealCard` (`SSRV_`, 360 × 132). `reveal`, one button, keys dropped entirely
while up. **KEEP verbatim — it is the cleanest surface in the product**, and it decides *when* the
reveal happens but never *whether*. Note `chart-3` (CONFIRMED, MEDIUM): the reveal it triggers is
undone within ~200 ms by the host re-applying blind mode — a defect in the host, not in this control.

**Command palette** — `CSSRPalette` (`SSRX_`, 330 wide, 8 rows, one `OBJ_EDIT` query). **KEEP as an
overlay**, drawn last of all (`:816`), polled first and alone so one click is never read twice
(`:2450-2457`). Its 31 entries gain one (`PANEL_MOVE` becomes a `cmd`) and lose none.

**Key card** — `CSSRKeyCard` (`SSRK_`): **deleted**, see O.6.5.
**First-run card** — `CSSRFirstRun` (`SSRF_`): **deleted**, see O.6.5.

Net: nine object-name prefixes become **seven**; two classes and one `seen.txt` side effect go away.

---

### O.13 What this redesign refuses to add, and the ledger

**Refused, each for a constraint and not for taste:**

* **No control that needs a coordinate.** No drag handle, no resize grip, no slider thumb to grab, no hover target, no tooltip, no disclosure triangle. [CONFIRMED FROM CODE] the only input the drawn surface may rely on is a latched button read by `PollClicks`.
* **No second pseudo-combo.** The wizard's is a defect (`ui-dialogs-2`), not a pattern.
* **No scrollbar and no "show more" that grows the frame.** Destinations page.
* **No object drawn over a navigation cell** (`SSR_Widgets.mqh:455-458`).
* **No fourth action button and no seventh rail cell**, even though the seventh fits. The spare 39 px is the budget for whatever the product learns next.
* **No status-strip label promoted to a button** (M.3.7): ladder levels 1-4 commandeer slot 50 / `stbal`, so the one destructive question in the product would be drawn on a control that navigates.
* **No new colour token, no gradient, no glow, no rounded corner, no icon.** `Rect` writes `BORDER_FLAT` (`SSR_Widgets.mqh:216`); a glyph is a font the user may not have.
* **No key on `buy` or `sell`.** A market order with no stop must cost a deliberate click.

**The ledger, in objects and in writes.**

| | v125 | after O |
|---|---|---|
| clickable controls, Standard frame | 2 caption + 7 transport + 2 speed + **20** groove + 3 actions + 5 rail + sheet | 2 + 7 + 2 + **10** + 3 + **6** + sheet |
| per-frame `m_w.Remove()` calls, chrome | **9** (`:932-934`, `:1189-1191`, `:1241-1243`) | **0** — one `UpgradeSweep()` behind `m_swept` |
| slider cold cost | 198 writes | **108** |
| key card while up | ~41 deletes + 41 creates + **~450 writes per frame** | one destination draw per navigation |
| object-name prefixes | 9 | **7** |
| key bindings / lists that can drift | 22 bindings + **4 lists** | 24 bindings + **1 list**, guarded by A23 |
| controls that claim an action they do not perform | `del`, `yes`/`no`, the wizard's drag, the palette's `move` | **0**, or the claim is deleted with the control |

**And the standing caveat, unchanged from M.10 and L.11.** [CONFIRMED FROM CODE] every pixel and
character count in this section is derived from a constant or a literal in the source; every px/char
figure is an estimate MQL5 will not confirm; `CheckFrame()` can only ever see **sized** objects, never
labels (invariant I10), so most of what O.6 and O.7 fix is invisible to the only instrument the
product has. The author has never run this build on a terminal. **Settle L.4.2 first** — it decides
whether `M` is the whole answer to O.10.2 or merely the reliable half of it, whether the setup tag
box can ever take focus, and whether the ten speed cells are a courtesy or the only way the groove is
usable at all.

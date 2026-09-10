# SS Replay — UX/UI Implementation Plan

## Ground rules

1. **The engine is not touched for UI reasons.** All UI work goes through
   `CSSRReplayPort` (~45 verbs) and `SSRUiState`. If a screen needs something
   the port cannot express, the port gains a read-only accessor — never the
   engine a behaviour change.
2. **Nothing is removed.** Every feature in the audit keeps a home.
3. **Each phase ends green**: 39 programs compile with 0 errors and 0 warnings,
   16 audits silent, smoke suite run on the user's terminal.
4. **From Phase 2, all new UI positions through a layout helper**, so RTL later
   is a change to the helper and not to sixty call sites.

## Phases

### Phase 0 — Audit ✅ complete
This document set. No code changed.

### Phase 1 — UX architecture ✅ complete
`product-vision.md`, `information-architecture.md`, `user-flows.md`,
`keyboard-shortcuts.md` (with the conflict audit), `REVIEW-BEFORE-IMPLEMENTATION.md`.

### Phase 2 — Design system ✅ complete
- Split `SSR_Theme.mqh` into tokens and metrics; no literal colour survives
  outside it.
- Add audit A17: **no `C'r,g,b'` outside the theme**. Measure the false-positive
  rate before wiring it in — an audit that cries wolf is worse than none.
- Add primitives: `List`, `Meter`, `Chip`, `Toast`. Additive only.
- Introduce the layout helper (`SSRLayout`) that every new draw site uses.
- **Done.** 16 colours tokenized to zero; A17 added and silent; `List`,
  `Meter`, `Chip`, `Toast` added; `SSR_Layout.mqh` written; smoke stage 32
  measures all of it. 39 programs clean, 17 audits silent.
- **Found on the way:** `SSR_TradeLines` and `SSR_CalendarLines` used theme
  colours without including the theme — they compiled only by include-order
  luck. Both now include what they use.
- **Not yet used by any screen.** Phase 3 is the first consumer.

### Phase 3 — Replay workspace ✅ complete
- Panel mode **Pro** (rail + Analysis + palette entry). Compact and Standard
  unchanged.
- **Command palette** (`Ctrl+K`): `OBJ_EDIT` + filtered `List`, built the way
  the v101 dropdowns already work — drawn last, so it is on top.
- Caption becomes a status line: symbol · timeframe · fidelity · mode chips.
- **Done: the command palette.** `SSR_Command.mqh` (28 commands, one table)
  and `SSR_Palette.mqh`. `Ctrl+K` opens, `↑↓` choose, `Enter` runs, `Esc`
  closes. Smoke stage 33, thirteen checks — including that **no command
  invents a verb**, asserted over the whole table at once.
- **Done: the caption is a status line.** Identity · build · state · mode
  chips (fidelity, BLIND, PROP), plus a `K` button so the palette is
  reachable without knowing the key. Fidelity MOVED out of the status strip:
  it is a mode, not a number, and it was sitting among four numbers
  pretending to be a fifth. The symbol is no longer repeated - MetaTrader
  writes it in the chart's own corner, and repeating it would defeat Blind
  mode. New smoke check measures that the chips clear the buttons, which is
  the one row the frame test cannot police.
- **Done: Pro panel mode.** Deliberately deferred until Phase 7 had
  established how a sheet asks for space - see Phase 3b below.

### Phase 3b — Pro panel mode ✅ complete

The version specified — "Standard plus a persistent rail" — was not built,
because the rail is **already always visible** in Standard: it would have
added nothing a user could notice. What shipped is the version the deferral
note named as worth building: **a taller sheet on a tall chart**.

- **`SSR_SHEET_H` stopped being a constant.** `SheetH()`, `BodyH()`,
  `PosGroupH()` and `PosCap()` are the only four places that answer a height
  question now; the frame, the corner snap, the drag repaint and six sheets
  all read them. Nine places working the same number out separately would be
  nine places that can be wrong by 140 pixels.
- **Positions: five rows → twelve.** That was the sheet actually running out
  of room — a trader scaling into a position runs out of rows long before
  they run out of screen. The wire carries twelve (`SSR_POS_MAX`); how many
  are *drawn* is the panel's decision and changes with its height, because a
  port that knew how tall the panel was would be a layout decision taken one
  layer below the layout.
- **The cap has never been a trading cap** and still is not: `+N not shown`
  moved onto the hint row, where it is legible — it used to be drawn three
  pixels above the hint, so on a full list the two lines were printed over
  each other, visible only in the one situation the line exists for.
- **It is asked for, not automatic.** Compact is a *degradation* forced by a
  chart with no space; taking space is the opposite kind of decision. `P`
  toggles it, the palette offers it, and `panel.ini` remembers it.
- **The wish and the fact are two flags.** `m_pro` is what the user asked
  for and survives; `m_tall` is whether this chart can hold it. Folding them
  into one would mean an afternoon on a laptop silently costing the setting.
  A chart with no room says so on the status strip for four seconds — a key
  that refuses silently is reported as a broken key.
- **The Stats half of the original idea was superseded, not skipped.** "Stats
  showing more than ten of the forty-three measures" is what Phase 7 built,
  in a modal, where all forty-three fit and page. A second copy on a sheet
  would be a second surface for the same numbers.
- **Found while building it: the per-row close button was never a button.**
  Every row drew its "no stop" note into `px<r>` and then its close button
  into `px<r>`. `ObjectCreate` refuses a name that already exists, so
  `ButtonC` found the *label*, wrote "X" over the note and moved it right.
  `PollClicks` scans `OBJ_BUTTON`, so no press on it was ever seen —
  **per-row close has not worked since it shipped**, and the entry spread
  and "no stop" notes have never been on screen. The note is `pn<r>` now.
- **Found while building it: the row dispatch matched a name of length 3.**
  `px0`..`px9` — correct at five rows, silently wrong at twelve, where the
  last two rows' buttons would have done nothing. The row number is parsed
  digit by digit now, because `StringToInteger` answers 0 for anything it
  cannot read and 0 is a valid row.
- **Test: stage 39** checks the close button's object TYPE from the chart —
  the only thing that would have caught the collision — measures the tall
  sheet against the frame the panel drew, drives `P` through the key path
  rather than calling the toggle, and asserts that shrinking sweeps the rows
  the tall sheet drew.
- 39 clean, 17 audits silent.

### Phase 4 — Setup / onboarding ✅ complete
- Quick-start screen (F1) ahead of the wizard.
- **Mode** step (F2) deciding which sheets the session gets.
- Random + **seed** surfaced, copyable.
- **Done.** Four steps: QUICK → SETTINGS → MODE → START. Quick start offers
  "Same as last time" (only when there is one, and it prints what it will do),
  "Continue <session>" (only when that file exists), "Random session", and
  "Customise…". Two of the three land straight on START.
- **Mode is a shortcut, not a setting.** It writes `blind` / `prop_on` /
  `random_start` and nothing else — there is no `mode` field, because a fifth
  source of truth that must agree with four others is the one that disagrees.
  The step opens on what is TRUE, not on what was last clicked, and the modes
  are deliberately not exclusive: a prop challenge practised blind is a real
  exercise.
- **Random and its seed have a UI at last.** The seed is an `OBJ_EDIT`, not a
  label, because its whole purpose is to leave the machine. Six expert sites
  now read the form instead of the input — including the one deciding whether
  the orange line appears, since a random session has already answered that.
- **`Repaint()` written once.** The first-paint declaration was copied three
  times in `Poll()`; the fourth copy is the one that forgets.
- **Test: stage 16 extended** — twelve fields round-trip, the seed is checked
  on its own so a failure names it, and four mode combinations are asserted.
- 39 clean, 17 audits silent.

### Phase 5 — Trading / position UX ✅ complete
- **THE MERGE WAS DROPPED, and the reason is arithmetic.** Trade content is
  180 px of a 186 px sheet and Positions is 183. A "merge" that fits would be
  a section switch inside one tab — which is what a tab already is. Renaming
  two tabs into one tab with two sections is not a UX improvement, so the
  effort went where it buys something.
- **Done: execution transparency, on the row, while it can still be acted on.**
  `pos_no_stop` and `pos_spread` now travel through the port. A position with
  no stop says **"no stop"** in words on its own row — the statistics have
  counted these since Phase 9 and reported them *after* the session, which is
  the one moment nothing can be done. Otherwise the row carries the spread it
  was entered at, which decides whether a fill was realistic and has never
  been visible outside the exported statement.
- **Done: a fill toast.** A refusal has said why since v98; a success said
  nothing. The `Toast` primitive from Phase 2 gets its first consumer, and the
  status strip keeps carrying standing state instead of being evicted to
  announce a fill. Detected from a ticket the panel has not seen — no engine
  change, no event, no second place that knows about fills.
- **`SSR_TradeLines` untouched**, as promised. All six of its smoke checks
  still pass unchanged.
- **Test: stage 35** drives both facts through the port, because a field the
  engine fills and the panel reads is only proved by the thing in between.
- 39 clean, 17 audits silent.

### Phase 6 — Training ✅ complete
- **The chip shipped in v106, the seed in v107.** What was left was the
  moment.
- **Done: the reveal.** Blind mode has restored the chart when the EXPERT WAS
  REMOVED since Phase 8, so a trader who wanted to know what they had been
  reading had to end the session to find out — losing the chart, the positions
  and their own reasoning on the way. That is a training feature with no
  feedback loop.
- The session finishes, the market **stays hidden**, and a card says so with
  the one button that lifts it. `CSSRRevealCard` draws the question and never
  answers it: the host owns the blind, so one place decides what revealing
  means.
- **It decides WHEN, never WHETHER.** `OnDeinit` still restores every chart
  whatever happened, so a user who closes the terminal mid-card gets their
  settings back exactly as before.
- **Test: stage 36** asserts the market is still hidden while the card is up,
  that dismissing the card is not answering it, and that the chart comes back
  exactly as it was — the promise the whole mode rests on.
- 39 clean, 17 audits silent.

### Phase 7 — Review / journal / analytics ✅ complete
- **The engine measured forty-three things and about ten were reachable.**
  MAE, MFE, revenge trades, risk dispersion, the spread each trade was
  entered at and the count of trades placed with **no stop** are the deepest
  thing this product knows, and a trader closed the session without seeing
  any of them — they existed only inside an exported HTML file somebody had
  to remember to produce, find and open.
- **Done: the session review.** `SSR_Review.mqh` turns an `SSRStatistics`
  into rows and sentences and stops there; `CSSRReviewCard` decides where
  they sit. Neither computes anything. A second place that derived even one
  figure would eventually disagree with the statement, and the statement is
  what gets sent to a prop firm.
- **A modal, because this is consulted and not operated** — the rule from
  v98. Forty-three measures will not fit in a 186 px sheet at any density
  worth reading.
- **Paged, because MQL5 cannot clip.** No scrollbar, no clipping rectangle: a
  list that drew all its rows would paint the surplus over the chart. It
  draws a window onto them, which is what the Phase 2 `List` primitive was
  built for.
- **It never coaches.** An observation states what was counted and stops:
  "1 of 2 trades opened within two minutes of a loss." Whether that was
  revenge trading, or a plan followed correctly, is something the trader
  knows and this program does not. Inventing the interpretation is how a
  measurement tool turns into a horoscope.
- **A line with no samples is absent, not zero.** "0 revenge trades" out of
  one trade is a sample size, not a clean sheet. Under three trades the
  card shows no sentences at all.
- **Reachable three ways, opened in one place.** `A`, the command palette
  entry, and the end of a session all call `OpenReview()`. The `g_reviewed`
  latch is set by the two *automatic* callers only — latching inside
  `OpenReview` would have meant that asking for the review mid-session
  silently cancelled the one shown at the end of it.
- **An open card owns the keyboard, including the keys it does not use.**
  Space forwarded to the panel would start the replay running behind the
  numbers being read, and every one of them would quietly stop matching the
  chart.
- **Found by writing the test: the 63-character cut.** Rows were built to fit
  in 62 and the card prefixes a two-character group marker, so the longest
  rows would have lost a digit on the chart — silently, and read as a wrong
  number rather than a missing one. `SSR_REVIEW_ROW_MAX` is 60 now, and
  stage 37 measures the string that reaches the object, marker included.
- **Test: stage 37** asserts all 43 measures arrive, that every observation
  has a count behind it, that none of them contains a coaching word, that
  two trades support no statement at all, and that risk dispersion stays
  quiet at two samples and speaks at three — the same session, one gate.
- 39 clean, 17 audits silent.

### Phase 8 — Prop evaluation ✅ complete
- **An evaluation has four rules and the panel drew one of them.** The profit
  target had a bar; the daily loss limit — the rule that ends most real
  challenges — was a number inside a sentence, `floor 9500.00`, which a
  trader mid-trade has to subtract from their own equity to use. The whole
  block was 84 px at the bottom of the Stats sheet.
- **Done: a Prop tab with one meter per rule.** Profit target, daily loss,
  drawdown (named trailing or static, because a floor that moves under a
  trader who thinks it is static is the most expensive surprise in this
  product), and trading days. The deadline is a line under them, drawn only
  when there is one.
- **The tab exists only while an evaluation does** — a panel that shows an
  empty scoreboard to everyone who is not being scored is asking a question
  nobody put to it. The strip removes the fifth tab when the evaluation goes,
  and a user standing on it is moved to Stats: four meters reading zero is
  not "no evaluation", it is "an evaluation going badly".
- **The sheet computes nothing.** Every fraction is asked of
  `CSSRPropEvaluation` — the one place that knows what these rules mean and
  the same place that decides whether the run is over. `DailyUsed`,
  `TotalUsed`, `DaysProgress` and `DeadlineUsed` sit beside `TargetProgress`,
  which already existed for exactly this reason.
- **Found while writing the meters: the day count lied.** `m_trading_days` is
  incremented on the day boundary, so a trader who traded today was not
  counted for today until tomorrow. The rule that decides the verdict adds
  the open day back in; the accessor the panel read did not — so on the third
  day of a three-day minimum the panel said **2**, and a trader reading it
  would believe they could not pass a run the evaluation would have passed.
  `TradingDays()` now returns what the rule counts, and the headline and the
  exported statement read the same accessor.
- **Found while writing the meters: a rule that does not exist is not a rule
  with room left.** `DailyFloor()` on a challenge with no daily limit returns
  the equity the day opened at — a fine number, and a catastrophic thing to
  print under the word "floor", because it tells a trader in profit that they
  are failing at this instant. Those rows say "no daily limit" now.
- **Found while writing the meters: the rules line was never fully drawn.**
  MetaTrader draws 63 characters of `OBJPROP_TEXT` and the line is seventy-odd,
  so "within 30" has not been on screen for anybody since the evaluation
  shipped. Clipped explicitly now, with the four rows below carrying every
  rule in it.
- **No rule is carried by a bar alone.** Every meter has its percentage and
  its floor price written beside it: a bar is unreadable to a colour-blind
  trader, illegible in a screenshot, and meaningless to anyone who has not
  learned which way is bad.
- **Test: stage 38.** The check the stage exists for is that **at the exact
  equity where `OnClock` ends the run, the daily meter reads 1.0** — a bar
  that says "room left" in the frame the evaluation says FAILED is worse than
  no bar. It also measures the sheet against the frame the panel drew, at its
  worst case (a finished run with a deadline), because stage 18 walks the four
  sheets every session has and cannot reach this one.
- 39 clean, 17 audits silent.

### Phase 9 — Responsive + accessibility ✅ complete

- **The contrast pass was the phase, and it failed.** This plan said "contrast
  pass on every token against the face", and `accessibility.md` already claimed
  the palette "was chosen against `SSR_C_PANEL` for exactly this". Computing it
  found **11 of 38 foreground/surface pairs below 4.5:1**, the worst being the
  build tag at **2.06:1** — the one label a user is asked to read off a
  screenshot. Nobody could see it: two greys that both look grey on a dark
  panel can be four times apart in contrast, and neither of them tells you.
- **The caption was the problem surface**, not the foregrounds. Five of the
  eleven were "on the header" — it was the lightest thing in the panel, so
  every colour on it had the least room. It is **recessed** now, like the
  status strip at the other end, which fixed five failures without changing a
  single foreground colour.
- **There is room for two readable greys below white, not three.** The dimmest
  grey that clears 4.5:1 here is about 149, and `TEXT_DIM` was already 149 — a
  third tier below it is by definition below the readable floor. The ramp was
  **re-spread** (233 / 186 / 149) rather than extended: three visibly distinct
  steps, all readable, instead of four of which the last was decoration.
- **Audit A18 enforces it on every run.** The pairs are declared in
  `SSR_Theme.mqh` beside the tokens, so changing a token and forgetting its
  pair means editing two lines that touch. A18 also fails if fewer than twenty
  pairs are declared — a table that quietly empties passes forever.
- **Second channel: two real gaps found and closed.** The stop, target and
  entry lines were a red one, a green one and an amber one with **nothing
  written on them** — which is the stop and which the target was carried by
  colour alone, and a trader who cannot separate this red from this green was
  being asked to drag one below the price and one above it. They had a
  tooltip, and a tooltip is not a second channel: it is the same channel behind
  a delay. The recorded position levels had said their name since they shipped;
  the *draggable* ones were built by a different function that only set the
  tooltip.
- **Nothing is drawn over anything else — measured.** Every column in this
  panel was placed by arithmetic in somebody's head. The Positions row is what
  that is worth: its note column sat nineteen pixels from the money column and
  would have printed straight through it, invisible for four builds only
  because a *second* bug stopped the note being drawn at all. **Stage 40**
  measures every label with `TextGetSize`, at the real face and point size on
  the machine the user is on, and fails if any two overlap — on all five
  sheets.
- **Width responsiveness.** On a chart with room the panel is now pulled fully
  back on; the old clamp kept only the *caption* reachable, a rule written for
  a panel dragged off the bottom and applied to the right edge too, so a panel
  nudged right on a wide chart hung off it with every caption control past the
  edge. A chart **narrower** than the panel is a stated limit — there is no
  width at which every sheet's columns still clear each other — and the status
  strip says so rather than letting the user conclude the panel is broken.
- **The 720 px "Pro breakpoint" was retired, not implemented.** Phase 3b
  settled that: taking space is asked for, never triggered by a measurement.
- **Open gap, still open: no user text-size control.** MQL5 sizes are
  per-object; a scale factor would have to multiply every metric and every
  hand-placed column offset, with no layout engine to reflow what no longer
  fits. Phase 9 did not close it. What it shipped is the *instrument* —
  `OBJPROP_FONTSIZE` follows the OS display scaling, so stage 40 can now prove
  whether the panel still holds together at 150%, instead of a promise that it
  does.
- 39 clean, **18** audits silent.

### Phase 10 — Localization ◧ 10a complete, 10b **not done and not claimed**

- **Measured before starting:** 214 draw-site lines carried a literal, and 152
  log lines did too. The second number is the one that decided the scope — a
  log in a language the person reading the bug report cannot read is not a
  localised log, it is a lost diagnostic.
- **Done: 176 strings, every user-visible surface, and a complete Persian
  translation.** Panel, all five sheets, both dialogs, the setup wizard, the
  review card, the reveal card, the key card, the first-run card, the command
  palette. Zero draw sites still hold a literal, except `SS Replay` — a
  product name is not a string to translate.
- **An enum index, not a string key.** `T("panel.play")` costs sixty table
  lookups a frame at 10 Hz, and a *mistyped* string key compiles, runs, and
  puts `panel.paly` on the chart in front of a user. A mistyped enum does not
  compile — that whole class of bug is removed rather than audited.
- **English is compiled in and can never be missing.** A translation is an
  override file (`InpLanguage`, no recompile, no MetaEditor): it replaces the
  lines it has and leaves the rest English, lines naming a string this build
  does not have are skipped rather than fatal, and there is no state in which
  the panel draws blank labels.
- **Found by measuring: an English string had been cut since it shipped.**
  "Then drag them. Buy / Sell would open with no stop until you do." is 64
  characters; MetaTrader draws 63. It had been losing its last character
  mid-word on every chart. A translator has no way to know that limit exists,
  so **A19 checks every catalogue string and every line of every shipped
  translation**, and stage 41 checks whatever language is loaded.
- **Audit A19** also asserts every enum value has a table line (a missing one
  draws *blank*, which reads as a rendering fault), and that no drawing call
  takes a literal as its text argument — looked up by argument *position*,
  since every one of those calls takes an object name first. It fails if
  fewer than 100 calls resolve to `T(SSR_S_...)`, so a changed widget
  signature cannot make it pass by reading the wrong argument everywhere.
- **Test: stage 41** asserts a word actually *changes* when Persian loads — a
  loader that reported success and applied nothing would pass every other
  check — and that no translation dropped a `%d` or `%s`, which
  `StringFormat` will not complain about but will print wrongly.

**10b — RTL: not implemented, and deliberately not half-implemented.**

- Measured and passing: Tahoma reports a real width for Persian, the text
  survives the `OBJPROP_TEXT` round trip unchanged, all 176 Persian strings
  are inside 63 characters.
- **Not measurable from inside MQL5, and therefore not claimed:** whether
  MetaTrader *shapes* Arabic-script glyphs and orders them right-to-left on
  screen. No API answers it.
- `SSR_Layout.mqh` has had coordinate mirroring since Phase 2 and it is still
  OFF, because Phases 3–9 did not adopt the helper: the panel's ~200 draw
  sites compute `x` inline, exactly as `localization.md` warned they must not.
  Flipping the flag now would mirror the handful of sites that use the helper
  and leave every other one in place — a half-mirrored panel, on a chart I
  cannot see. **The constraint that document placed on Phases 2–9 was not
  honoured, and saying so is more useful than a switch that half works.**
- 39 clean, **19** audits silent.

### Phase 11 — Polish and performance
- Profile the pump loop before and after. The engine pumps every 40 ms and the
  panel repaints at 100 ms; **neither budget may grow.**
- Delete `SSR_DirectPort.mqh` (dead).

## Sequencing decisions

**Phase 7 before Phase 8** even though the brief lists prop earlier: Review is
the largest gain per unit of risk, and the prop dashboard reuses the `Meter`
primitive that Review's drawdown display needs.

**Phase 10 last, but its constraint applies from Phase 2.** Retrofitting a
layout helper after five phases of new UI would cost more than the feature.

## What is explicitly out of scope

- Rewriting the replay engine, trading engine or data layer.
- Changing execution, risk, slippage, spread or prop rule semantics.
- Any UI that implies a capability MQL5 does not have.

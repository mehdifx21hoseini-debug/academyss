## A. EXECUTIVE SUMMARY

### What it is

[CONFIRMED FROM CODE] SSReplay is a standalone MetaTrader 5 Expert Advisor that turns historical
M1 data into a replayable market a person can trade against: it builds a custom symbol, feeds it
bars or real ticks under a master clock, opens a chart on it, and draws a control panel on that
chart. Trading is entirely virtual — there is no `OrderSend`, `CTrade` or `PositionClose` anywhere
in the tree — and the product adds a virtual trading engine, risk sizing, a prop-firm evaluation,
scenario/random start selection, external data import, session save/restore and a post-run review
card on top of the replay. It is 31,439 lines of library code across 84 headers in 12 include
directories under one 3,255-line Expert, at build v125.

**[STATED PREMISE — not a source fact]** The author has never run it on a real MetaTrader 5
terminal, and MT5 cannot be installed in the build environment. That single fact frames everything
below. It is **not** derivable from `MQL5/`, so it is labelled as the premise it is. What *is*
[CONFIRMED FROM CODE] is that the codebase says the same thing about itself, in three places:
`SSR_QA_Smoke.mq5:6-7` (*"Eleven releases have been shipped without a compiler or a terminal on this
side"*), `SSR_Widgets.mqh:122-123` (*"I cannot run this terminal - so the panel measures itself
instead of being trusted"*) and `SSReplayStandalone.mq5:1940-1944`. Section U.0 quotes all three.

### Genuine strengths

[CONFIRMED FROM CODE] The layering holds. Time is `long` epoch milliseconds in every layer; no
layer below `Ui` draws a chart object; no layer below `Mt5` touches a custom symbol; the
include-direction matrix has exactly one true cycle (`Ui ↔ Chart`) and one benign upward edge.
[INFERENCE] This is why the defect list is repairable rather than a rewrite: almost every finding
is local to a class, not a fault line between classes.

[CONFIRMED FROM CODE] Three further pieces of real engineering: the 512-slot widget property cache,
built after a repaint the file's own comment records as 561 writes / 39.05 ms and reduces to 77
lookups (`SSR_Widgets.mqh:31-38` — the comment is the evidence; the measurement behind it is a user's
run with no CSV and no run id, and section E.1 says so);
the single generated key table driving both dispatch and the key card; and the panel's own stated
rule that modes are drawn as text on a tinted plate "because a mode carried by colour alone is a
mode a colour-blind trader cannot read" (`SSR_Panel.mqh:860-862`). [RECOMMENDATION] Keep all three
verbatim through any redesign.

### The audit, in numbers

248 findings were verified against source. **197 CONFIRMED** — 2 CRITICAL, 14 HIGH, 58 MEDIUM,
105 LOW, 18 IMPROVEMENT. **30 POTENTIAL_RISK** — real code, but the consequence depends on runtime
or broker behaviour nobody has observed. **21 were refuted** and are recorded as NOT_A_BUG; they
appear nowhere in this report as defects. That last number is part of the result: a list that
never loses candidates is not an audit.

### How to read this report (the two conventions that make its numbers checkable)

**[CONFIRMED FROM CODE] 1. Severity always means `final_severity`.** `docs/audit/verified.json`
carries **two** severity fields per finding: `severity`, as the subsystem reader filed it, and
`final_severity`, after the three refuters and two confirmers. **They differ for 105 of the 248
findings.** Every severity word quoted anywhere in sections A–V is the **`final_severity`**, and every
classification word is the **`classification`**. Nothing quotes the filed severity. So a reader who
greps `HIGH` across the report and counts more than the fourteen CONFIRMED HIGHs has found a defect
in the report, not an extra finding — and the counts in A, C.1, B.17, T.6.3 and U.10 all reproduce
from `verified.json` with that one rule.

**[CONFIRMED FROM CODE] 2. The four tags, and where prose is legitimately untagged.**
`[CONFIRMED FROM CODE]` = re-derivable at the cited file and line. `[INFERENCE]` = a judgement built
on cited facts. `[RECOMMENDATION]` = proposed work, which by definition is not a fact about v125.
`[FUTURE FEATURE]` = outside v125's scope entirely. Two further labels appear where the standard four
would overclaim: **`[STATED PREMISE]`**, for the handful of framing facts supplied to this audit
rather than read from `MQL5/` — that the author has never run v125 on a terminal, that MT5 cannot be
installed in the build environment, and MQL5 platform behaviours such as who owns an `OBJ_EDIT`
caret; and **`[POTENTIAL_RISK]`** at the point of use, for a claim that can never be raised above
that from source. **Untagged prose is confined to three shapes**: a continuation paragraph inside an
already-tagged block, a numbered step in a test procedure (section U's forty tests — a procedure is
an instruction, not a claim), and a table row whose own cells carry the classification. Any untagged
paragraph that *asserts something about the code* is a defect in the report.

**[CONFIRMED FROM CODE] 3. `new-N` ids are not `verified.json` findings.** Eighteen further defects
were read directly from source while sections G, H, L and S were written. They are registered in
**D.2** as `new-1` … `new-19` (`new-9` duplicates `new-1`), and **none went through the refuter
process**, so none may be cited as though it were a CONFIRMED finding and none is counted in the
197. Their severities are self-assigned.

### Top confirmed defects, and what each costs

| id | Severity | What it costs the user |
|---|---|---|
| `trading-exec-1` | CRITICAL | Rewinding drops positions opened after the cut **without reversing their P/L, commission and swap**, so the balance keeps money that was never earned. Every statistic downstream — equity curve, prop meters, review card — is then wrong, silently. (`SSR_TradingEngine.mqh:640`) |
| `host-expert-1` | CRITICAL | `OnInit`'s object sweep deletes the handover stash before the second pass reads it, so one-window mode — the **default** — can never recover its origin symbol. (`SSReplayStandalone.mq5:1806`) |
| `core-engine-3` | HIGH | `JumpForward` feeds bulk bars to the sink but never to observers, and `StepBackward` routes through it: **every step back replays up to five minutes blind to the trading engine** — stops and targets in that window never trigger. (`SSR_ReplayController.mqh:1383`) |
| `trading-exec-2` | HIGH | SL/TP edits, trailing moves, break-even and MAE/MFE are not versioned, so they **survive a rewind** — the trade you rewind to is not the trade you had. (`SSR_TradingEngine.mqh:263`) |
| `core-engine-1` | HIGH | The per-pump budget cap **drops bars** rather than deferring them; the "stop short" branch is dead. Time advances over price the user never saw. (`SSR_ReplayController.mqh:524`) |
| `data-1` | HIGH | Tick availability is probed over the last 24 hours, then FULL_TICK is selected for a window that may be years earlier: **the replay emits nothing, the clock runs to the end, and nothing reports it.** (`SSR_Mt5Providers.mqh:136`) |
| `core-engine-2` | HIGH | `StepBars(1)` is a no-op after the first step; `StepBars(n)` advances n-1. The product's most-used precision control quietly under-delivers. (`SSR_ReplayController.mqh:1169`) |
| `ui-panel-3` | HIGH | `HideBody(false)` undoes `HideSheetArea(true)` **inside the same `Render()`**, so compact mode leaves the tab rail and action strip sitting on the candles. (`SSR_Panel.mqh:682`/`:729`) |

### Top risks

[CONFIRMED FROM CODE] The largest risk is not in the list above: **the verification layer cannot be
believed.** 71 of the 227 non-refuted findings live in `Scripts/`, `Services/`, `Indicators/` and
`tools/`; none is CRITICAL or HIGH because none can hurt a user directly. At least 20 of them are
assertions that cannot fail, verdicts printed rather than asserted, or gates that are tautologies.
The 5,512-line, 43-stage, 329-assertion QA harness aborts at line 397 of `OnStart` on a fresh
terminal, because it reads `Bars()` before the `CopyRates` that would make the count real
(`qa-smoke-1`, CONFIRMED). [INFERENCE] 125 builds have been produced against an instrument that
has never finished a run.

[POTENTIAL_RISK] Two more deserve naming because they would surface on first contact with a real
broker: `data-2` (HIGH) — one invalid or non-positive M1 bar voids an entire read window of up to
60,000 bars; and `mt5-symbol-2` (MEDIUM) — `Adopt()` does not force `SYMBOL_CHART_MODE_BID`, so an
adopted LAST-mode symbol builds no candles from BID/ASK ticks. Both are labelled POTENTIAL_RISK
because neither can be settled without a terminal.

### The single biggest UX problem

[CONFIRMED FROM CODE] **In the default configuration the product never tells the user a single key.**
The key card — the only keyboard documentation that exists — opens on `H` alone since the `?` button
was removed. The one string that teaches `H` is drawn only by the first-run card, and `host-expert-4`
(CONFIRMED) shows the first-run card can appear on *neither* pass of one-window mode, which is the
default. Where the guard does let it through, `ui-dialogs-14` (CONFIRMED) shows it is drawn at a
fixed `y=376..480` without checking the chart height, and `seen.txt` is written regardless — so the
product's entire onboarding is consumed unread. Meanwhile the only `H` printed on screen names a
*row button*, and a user who reads it as a key legend gets a bookmark and a flip of their planning
lines instead (`ui-plumbing-14`, CONFIRMED).

**[INFERENCE] One honest qualification on the word "biggest".** All three findings behind this
paragraph — `host-expert-4`, `ui-dialogs-14` and `ui-plumbing-14` — are **CONFIRMED but LOW**, and
`ui-panel-3` (the compact-mode leak that puts buttons on the candles) is the only HIGH near this
surface. The verification process ranked each of the three as LOW because, in isolation, each costs
one missing sentence. **The claim here is about their conjunction, not their ranks:** three separate
LOW defects on the three separate paths by which a first-time user could learn one key add up to a
product that teaches nothing, and no single finding can carry that because no single finding sees
more than one path. That is an inference over the finding set, and it is labelled as one.
Everything else in the UI audit is a refinement of a surface the trainee cannot operate in the
first place.

### The redesign thesis, in two sentences

[RECOMMENDATION] MQL5 gives no hover, no focus, no clipping, no scrolling and no mouse coordinates
on a chart the EA does not own, so the information architecture must be **constraints-first**: every
affordance is permanently drawn or absent, navigation is the only thing allowed to delete objects,
and each destination owns its teardown list and its per-row character budget. Six rail destinations
fit and eight do not — `25n-3` px against `SSR_SHEET_H 186` (`SSR_Panel.mqh:1209-1225`) — so the
design problem is choosing what to cut, not what to add.

### Recommended first step

[RECOMMENDATION] **"First Light": make the existing QA harness capable of finishing, run it once on
a real MetaTrader 5 terminal, and write down what it said.** Four small edits, three runs, one log
file; three to five days; nothing in `Core/`, `Trading/`, `Mt5/`, `Data/`, `Session/` or `Ui/` is
touched and no finding above LOW is fixed. [INFERENCE] It is the only step in the roadmap whose
output is information rather than change, and every other step — including both CRITICALs — is
priced on information this project does not yet have. Section V sets out the three branches out of
that log.

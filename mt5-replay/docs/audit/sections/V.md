## V. RECOMMENDED NEXT DEVELOPMENT STEP

This section names **one** step, and it is not a feature, not a refactor, and not either of the two
CRITICALs. Sections E through T have produced an eight-to-ten-week Phase 0, a nine-phase roadmap and
248 verified findings. V's only job is to say what to open tomorrow morning, and it is deliberately
smaller than anything else in this audit.

**Tags** as elsewhere: `[CONFIRMED FROM CODE]` — read out of the v125 tree at the cited file and
line. `[INFERENCE]` — the fact is confirmed, the consequence is judgement. `[RECOMMENDATION]` — a
proposal. `[FUTURE FEATURE]` — does not exist in the tree.

---

### V.0 The step, in one sentence

> **STEP ONE — "FIRST LIGHT": make the existing QA harness capable of finishing, then run it once on
> a real MetaTrader 5 terminal, and write down what it said.**

[RECOMMENDATION] Four small edits, three runs, one log file. Nothing in `Core/`, `Trading/`,
`Mt5/`, `Data/`, `Session/` or `Ui/` is touched. No finding above LOW is fixed. No contract changes.
No object id is added. Estimated **three to five days** for one developer who knows this tree, of
which roughly half a day is code and the rest is installing a terminal, watching, and writing down.

[INFERENCE] It is the smallest possible step, and that is the argument for it: it is the only step in
the entire roadmap whose output is *information* rather than *change*, and every other step in T is
priced on information this project does not have.

---

### V.1 Why this is first, and why nothing else can be

Four facts, each confirmed, which together leave no other candidate.

#### V.1.1 The product has a 5,512-line, 43-stage, 329-assertion measuring instrument that has never been reached past stage 1

[CONFIRMED FROM CODE] `MQL5/Scripts/SSReplay/QA/SSR_QA_Smoke.mq5` is 5,512 lines, contains 43
numbered stages and 329 `Check(...)` assertions, and writes a single result file it then tells the
operator to send (`:5486-5509`, path from `SSR_QA_RESULT_FILE` at `:157`, stamped fallback at `:167`).

[CONFIRMED FROM CODE] `OnStart()` begins at `SSR_QA_Smoke.mq5:320`. At `:396` it reads
`int have = Bars(origin, PERIOD_M1)`, and at `:397-404`, if that count is short, it calls `Done()`
and **returns out of `OnStart` — the whole run**:

```
   int have = Bars(origin, PERIOD_M1);
   if(!Check("M1 history present", have >= InpReplayBars + InpWarmupBars, ...))
     {
      Log("  -> the EA downloads this automatically; run it once, or press Home on an M1 chart.");
      Done();
      return;
     }
```

The priming call that would make that count real is eleven lines below it, at `:408`:
`int got = CopyRates(origin, PERIOD_M1, 0, InpReplayBars, back);`. This is `qa-smoke-1`
(**CONFIRMED**, MEDIUM).

[CONFIRMED FROM CODE] Ground truth for this project is that the first `Bars()` read on an untouched
timeframe returns 0 because series build lazily. [INFERENCE] Therefore on a freshly opened terminal —
which is the only state a first run can be in — the harness aborts at line 397 of 5,512. Everything
from stage 2 to stage 43 is unreachable, including the one stage that matters most below.

#### V.1.2 The measurement Phase 6 is entirely justified by already exists, is already asserted, and sits 4,600 lines downstream of that abort

[CONFIRMED FROM CODE] The property-write counter is built and shipped: `CSSRWidgets::m_writes`
(`Ui/SSR_Widgets.mqh:155`), incremented at the sites where writes actually happen (`:220`, `:250`,
`:319`, `:323`, `:386`), exposed as `Writes()` / `ResetWrites()` (`:184`, `:188`), and surfaced on the
panel as `CSSRPanel::PaintWrites()` and `ResetPaintWrites()` (`Ui/SSR_Panel.mqh:3039-3040`). Its own
header comment states its purpose exactly: *"a test can render a frame and report the exact figure on
the user's own machine rather than on an assumption about it"* (`SSR_Widgets.mqh:146-153`).

[CONFIRMED FROM CODE] Smoke **stage 42** (`SSR_QA_Smoke.mq5:4992-5105`) already consumes it, and does
the right things with it: it throws away the first frame because it creates objects (`:5034`), counts
cached label rewrites and raw property writes on an identical frame (`:5040-5043`), asserts that an
unchanged frame rewrites **zero** labels (`:5045`), reports properties-per-still-frame as a `Note`
(`:5058`), times the **mean of twenty** renders rather than one (`:5069-5074`), asserts
`per < 100.0` ms against the panel's own repaint interval (`:5083`), and then asserts the other half
of a cache by switching a tab and requiring a non-zero write count (`:5094-5101`).

[CONFIRMED FROM CODE] The interval that assertion is measured against is real: the host repaints on a
100 ms gate, `if(!modal && now_ms - g_panel_paint >= 100) { g_panel_paint = now_ms; g_panel.Render(); }`
(`SSReplayStandalone.mq5:3061-3066`).

[INFERENCE] This is the decisive argument of the section. The audit's anchor performance number — 561
writes = 39.05 ms, from which E.9 concludes that **every published performance budget in this product
is invalid as measured**, and on which Phase 6's entire justification rests (T.6.2 P7) — does not need
a new instrument, a new spike, or a new design. It needs one guarded re-read at `SSR_QA_Smoke.mq5:396`
so that control reaches line 4992. **One S-sized edit stands between 125 unobserved builds and 43
stages of measured truth.**

#### V.1.3 The gate on the gate can print GO when it has not tested anything

[CONFIRMED FROM CODE] `SSR_QA_Preflight.mq5` ends in one of three verdicts: `NO GO` (`:708`),
`GO, WITH THE LIMITS ABOVE` (`:710`), or `GO` (`:713`). Two paths let it say GO having skipped the
only thing it exists to check.

- `:311` — `if(adopted || SymbolInfoInteger(test, SYMBOL_DIGITS) > 0)` uses digits as an
  existence proxy, so a zero-digit instrument silently skips the whole custom-symbol round trip and
  leaks the test symbol (`qa-smoke-3`, POTENTIAL_RISK, MEDIUM).
- `:397` — `int nadd = CustomTicksAdd(test, add);` counts *acceptance* and never asks whether a bar
  was built from what was accepted (`qa-smoke-2`, **CONFIRMED**, MEDIUM).

[INFERENCE] A first run whose gate cannot fail is not a first run; it is a ceremony. These two are
in scope for this step for exactly that reason and no other.

#### V.1.4 Both sweeps can close the chart the run is standing on

[CONFIRMED FROM CODE] Three functions walk `ChartFirst()`/`ChartNext()` and call `ChartClose(id)`
with no `id != ChartID()` guard:

| Site | Code | Finding |
|---|---|---|
| `SSR_QA_Smoke.mq5:361` | opening leftover sweep; closes any chart whose symbol ends in the replay suffix | `qa-smoke-6` (POTENTIAL_RISK, LOW) |
| `SSR_QA_Smoke.mq5:5466-5476` (`Cleanup`) | closing sweep; `if(ChartSymbol(id) == rsym) ChartClose(id);` | `qa-smoke-6` |
| `Mt5/SSR_CustomSymbolManager.mqh:505-522` (`CloseCharts`) | product teardown, same shape | `mt5-symbol-4` (POTENTIAL_RISK, MEDIUM) |

[INFERENCE] The first two are in scope: a measuring run that kills itself mid-measurement produces a
log indistinguishable from the hang it was sent to find. The third — `mt5-symbol-4`, which can close
**the user's own chart window** — is *not* fixed in this step; it is one of the things this step is
sent to observe, which is why V.3 insists on a disposable terminal profile.

---

### V.2 Exactly what to change — four edits, four files, no library code

[RECOMMENDATION] These are T.6.1 items 0A.1, 0A.2 (harness half) and 0A.3, and nothing else from 0A.
The whole diff should be well under 60 lines.

| # | File : line | Change | Closes (class, final severity) | Risk |
|---|---|---|---|---|
| E1 | `MQL5/Scripts/SSReplay/QA/SSR_QA_Smoke.mq5:396` | Prime the series before judging it: issue the `CopyRates` that already exists at `:408` (or a bounded `SeriesInfoInteger(origin, PERIOD_M1, SERIES_SYNCHRONIZED)` wait — the harness already uses `SeriesInfoInteger` at `:782`), **then** re-read `Bars()` and only then decide. Keep the abort — an unprimeable series really is fatal — but make it fire on a primed count. | `qa-smoke-1` (CONFIRMED, MEDIUM) | low. One read becomes two; no assertion changes meaning. |
| E2 | `MQL5/Scripts/SSReplay/QA/SSR_QA_Smoke.mq5:361` and `:5470` | Guard both sweeps: `if(id != ChartID())` before every `ChartClose(id)`. If the run's own chart is a match, log it and leave it. | `qa-smoke-6` (**POTENTIAL_RISK**, LOW) | low. |
| E3 | `MQL5/Scripts/SSReplay/QA/SSR_QA_Preflight.mq5:311` | Stop using `SYMBOL_DIGITS > 0` as existence. Use `SymbolInfoInteger(test, SYMBOL_EXIST)` — the idiom `Cleanup()` already uses at `SSR_QA_Smoke.mq5:5476`. A zero-digit instrument must run the section or print NO GO; it must not skip and pass. | `qa-smoke-3` (**POTENTIAL_RISK**, MEDIUM) | low. |
| E4 | `MQL5/Scripts/SSReplay/QA/SSR_QA_Preflight.mq5:397` | After `CustomTicksAdd` reports acceptance, ask the question that matters: read `Bars(test, PERIOD_M1)` (priming it first, per E1's lesson) and require ≥ 1 bar built. Zero bars from accepted ticks is a `Blocker`, not a `Limit`. | `qa-smoke-2` (CONFIRMED, MEDIUM) | low. |

[RECOMMENDATION] **One optional fifth edit, and it is worth it.** Add a probe input to the host —
`input bool InpLogEvents = false;` — which, when true, prints `id`, chart id and `sparam` for every
event entering `OnChartEvent` (`SSReplayStandalone.mq5:3111`), before the setup-panel branch at
`:3117`. Six lines, default off. **[RECOMMENDATION] Log `lparam` too when `id` is
`CHARTEVENT_KEYDOWN`**, because the same six lines then answer a second open question at no extra
cost: D's coverage statement records that **ten of the product's 22 key bindings are keys MetaTrader
itself binds on a chart** (`Ui/SSR_Keys.mqh:46-75`: arrows 37-40, `PgUp`/`PgDn` 33/34, `+`/`-`
187/189 and their numpad twins 107/109), and **no finding covers whether the terminal also acts on
them** — it is unknowable from source. The probe turns it into one observation: press each of the ten
on the chart the EA is attached to (`g_panel_chart = ChartID()`, `:1463`) and record both the logged
`lparam` **and** whether the chart also scrolled, paged or zoomed. **[POTENTIAL_RISK]** until then. [CONFIRMED FROM CODE] The reason it earns its place in the smallest
possible step: this is probe **P6** / open question **L.4.2**, and T.6.2 states that its answer decides
three separate Phase 6 designs at once — the speed-groove drag (`O.10.2`), the setup tag box's focus
path (`ui-panel-11`, POTENTIAL_RISK), and whether ten drawn speed cells are a courtesy or the only
usable groove. [INFERENCE] It costs six lines during a run you are doing anyway. Design the
pessimistic branch regardless; this probe can only make the answer better.

**What is explicitly *not* edited in this step:** nothing under `MQL5/Include/SSReplay/`, and nothing
in `SSReplayStandalone.mq5` except the six-line logging block above. [INFERENCE] That boundary is the
point. A first run that also carries a behaviour change cannot tell you which of the two you are
looking at.

---

### V.3 The run itself — three runs, in this order, on a disposable terminal

[RECOMMENDATION]

**Before anything.** A separate MT5 installation (portable mode, or a fresh data folder), logged into
a **demo** account, with no charts open that you care about, and no other EA running.
[CONFIRMED FROM CODE] D's grep establishes zero `OrderSend`, `OrderSendAsync`, `CTrade` or
`PositionClose` anywhere under `MQL5/` — 7 hits, every one a comment asserting the absence — so no
broker order is reachable. [INFERENCE] The risk this precaution addresses is not trading; it is
`mt5-symbol-4` closing a chart you wanted, and the custom symbols and `MQL5/Files/SSReplay/` tree the
suite creates and may fail to delete.

Compile first with `tools/ssr_compile.sh` (it runs MetaEditor under Wine and needs no terminal) and
confirm A1-A21 still pass under `tools/ssr_audit.py`. [INFERENCE] Four harness edits should move
neither, and if they do you have learned something before you have spent a day.

| Run | What | Read this |
|---|---|---|
| R1 | `SSR_QA_Preflight.mq5` on a normal broker M1 chart | The verdict line (`:708-713`). `NO GO` here ends the day and is a success: it has told you what the terminal will not permit. |
| R2 | `SSR_QA_Smoke.mq5`, same chart, default inputs | Everything. `Done()` (`:5484`) prints `=== N passed, M FAILED ===` and names the one file to keep. **Stage 42's four lines are the point of the day.** |
| R3 | `SSReplayStandalone.mq5` on a chart, **`InpOneChart = false`**, `InpLogEvents = true`, one short session: play, change speed on the groove, drag the speed slider, open Compact, type in the Setup tag box, stop | The event-id log. Then the Experts tab for the two watchdog prints at `SSReplayStandalone.mq5:3084-3090` and `:3092-3095`. |

[CONFIRMED FROM CODE] **`InpOneChart = false` is not a preference, it is the route around the
CRITICAL.** The default is `true` (`SSReplayStandalone.mq5:131`), and `host-expert-1` (CRITICAL) is
that `OnInit`'s object sweep deletes the handover stash before it is read, so the second pass of
one-window mode can never find its origin symbol. Setting it false takes the two-window path and
leaves the CRITICAL untouched and unmasked for Phase 0C.1. [INFERENCE] Do not "quickly fix" the
handover to make the first run prettier; that is a week of L-sized work with **high** regression risk
(T.6.3 0C.1) and it is not what tomorrow is for.

[RECOMMENDATION] If R2 aborts before stage 43, do not repair forward past the first FAIL in the same
sitting. `Done()` already states the rule (`:5493-5494`): *"The first FAIL is the layer to fix;
everything below it is a consequence."* Write the log, then decide.

---

### V.4 The acceptance test — six lines, each binary

[RECOMMENDATION] This step is done when all six hold. Not five.

1. **Reachability.** On a terminal where no M1 series has been touched, `SSR_QA_Smoke.mq5` reaches
   stage 43 and `Done()` prints a passed-count **greater than zero**. [CONFIRMED FROM CODE] Today it
   returns at `:404`, stage 1 of 43.
2. **Self-preservation.** The run's own chart is still open when `Done()` prints, and if either sweep
   matched it, the log says so and it was not closed. Assert `id != ChartID()` is honoured at
   `:361` and `:5470`.
3. **The gate can fail.** `SSR_QA_Preflight.mq5` prints `NO GO` when pointed at a deliberately broken
   condition (deny algo trading, or point it at a zero-digit instrument) and `GO` otherwise — and in
   the GO case the custom-symbol section ran, with a bar count ≥ 1 printed after `CustomTicksAdd`.
   [INFERENCE] A preflight that has never printed NO GO has never been tested.
4. **The number exists.** Stage 42 has printed, on this machine, all four of: labels rewritten on an
   identical frame (must be **0**), object properties written per still frame, mean ms over 20
   renders, and the `per < 100.0` verdict. This replaces E's derived 561-writes / 39.05 ms figure with
   a measured one, with its numerator and denominator, as T.6.4 condition 5 requires.
5. **The event answer is written down.** From R3: the complete set of `OnChartEvent` ids observed
   arriving from the replay chart, with chart ids. Either `CHARTEVENT_OBJECT_CLICK` alone — which
   confirms the ground-truth constraint the whole of M, N and O is designed against — or more, which
   re-opens `O.10.2` and `ui-panel-11`.
6. **The log exists as an artefact.** One file under `MQL5\Files\` (the path `Done()` names at
   `:5504`), committed into the repository beside the audit, plus one page listing every
   POTENTIAL_RISK finding that R1-R3 *could* have reached, marked `FIRED` / `CLEARED` /
   `NOT REACHED`. [RECOMMENDATION] `NOT REACHED` is the honest default and stays POTENTIAL_RISK —
   T.6.2's exit rule: a finding does not become NOT_A_BUG because one session failed to provoke it.

[INFERENCE] Note what is *not* in the acceptance test: no assertion about how many stages pass. A run
that reaches stage 43 with twenty failures is a complete success for this step. The deliverable is the
log, not a green light.

---

### V.5 What NOT to do yet, and exactly why

[RECOMMENDATION] Each of these is correct work, scheduled in T, and starting it tomorrow is worse than
not starting it.

| Do not start | Why not yet |
|---|---|
| **0C.2 — the rewind epoch** (`trading-exec-1`, CRITICAL) | It is the largest single item in the roadmap: **L · multi-week**, 2-3 weeks alone, **high** regression risk, and it touches `Core/SSR_ITickObserver.mqh`, the controller, the snapshot store, the trading engine and the strategy host at once (T.6.3). Its proving test lives in `SSR_T9_Trading.mq5` — inside a suite that is red for reasons unrelated to any fix, because six of its sections assert facts that are false against v125 (`tests-a-1..-4`, `tests-b-1`, `-2`; T.6.1 0A.5). [INFERENCE] You cannot distinguish a correct unwind from a coincidence in a suite that does not yet tell the truth. And the balance *is* the account: a wrong unwind is worse than no unwind. |
| **0C.1 — the one-window handover** (`host-expert-1`, CRITICAL) | A week of L-sized work with **high** regression risk, changing which values a run uses and which pass owns the replay chart. `InpOneChart=false` (`SSReplayStandalone.mq5:131`) routes around it for the price of one input, and the first run should not be carrying a week-old change. |
| **0A.5 — the six false test sections** | M-sized, and a build-environment milestone with no terminal dependency, so it loses nothing by waiting three days. T.6.1 flags the real hazard: *the suite turns green for the first time, which is itself the risk — it must be read, not celebrated.* Read a terminal log first, then decide which assertions were wrong about the product and which were right about a defect. |
| **0A.6 — the thirteen spikes** (22 findings) | The single largest 0A item, **L**, about a week, and `SSR_BarToTicks` (`Spike/SSR_SpikeKit.mqh:579`, `spikes-audits-1`, HIGH) is shared with the synthetic tick path, so repairing it **changes replay output**. [INFERENCE] Changing what the engine emits in the same week you first observe what the engine emits destroys the only baseline you will ever get for free. |
| **P4 — `SSR_B4_BrokerDataAudit`** | It is the next thing after this step, not part of it: it decides whether Phase 8 (data import) is needed at all (T.6.2, K.13 step 0), but it depends on 0A.6 repairing `spikes-audits-18`, `-19`, `-20` first. Schedule it the week after. |
| **Phase 6 — the M/N/O information architecture** | Its whole justification is acceptance item 4. T.6.2 says it plainly: *if it is 4 ms rather than 39, RF7 stays correct but stops being urgent.* Building a rail against an unmeasured number is how you get a second redesign. |
| **Phase 7 — RTL** (`Q`) | Gated on probe P9: whether Arabic-script glyphs render, shape and fit at all. Until a photograph exists, Q's cost model is arithmetic on an assumption. |
| **Any new clickable control**, from M, N, O, P, R or S | `host-expert-7` (`SSReplayStandalone.mq5:3167`) — keys are not withheld while a modal is open — is a gate five sections independently declare on every control they add (T.6.3 0C.12). It is an S-sized fix in Phase 0C. It is not in this step, and neither is anything that depends on it. |
| **`mt5-symbol-4`'s `CloseCharts` guard** | Tempting, three lines, same shape as E2. Leave it. [INFERENCE] It is a POTENTIAL_RISK this step is sent to *observe*: if teardown closes the user's own chart on a real terminal, that observation promotes it to a Phase 0C fix regardless of its MEDIUM rating (T.6.2 P8), and a guard added beforehand hides the evidence. Guard the harness, which is the instrument; do not guard the product, which is the subject. |
| **Re-classifying anything in `verified.json`** | One session cannot clear a POTENTIAL_RISK, and the 21 `NOT_A_BUG` findings — `trading-analytics-11`, `ui-port-session-5`, `-6`, `data-6` among them — must never be presented as defects or "cleaned up" (T.1.4). The log records observations; the classification column is not edited by this step. |

---

### V.6 What this step does not settle

[INFERENCE] Stated so the log is not over-read.

- It settles **none** of the 2 CRITICAL or 14 HIGH findings. `spikes-audits-1` (HIGH) is explicitly
  deferred with 0A.6.
- It settles at most a handful of the 30 POTENTIAL_RISK findings, and only those R1-R3 actually
  reach. `data-2` (HIGH, POTENTIAL_RISK) needs probe P5 — a 60,000-bar walk through
  `SSRDataReport::IsUsable()`, per instrument — which is not in scope. `mt5-symbol-2`, `-5`, `-6` need
  the deliberate lifecycle setups of P8.
- It produces **no** new capability a trader would notice. T.6.0 already says this of the whole of
  Phase 0, and it is most true of its first three days.
- It does not validate the 15 test scripts, the 13 spikes, or the audits that cannot fail
  (`spikes-audits-26`, `-27`, `-28`, `-29`).
- A green R2 does **not** mean the product is correct. Every "CONFIRMED" in this audit means confirmed
  from source by adversarial review; a passing stage means one assertion held once on one broker on
  one machine. The two are different claims and the log should say which it is making.

---

### V.7 The three branches out of the log

[RECOMMENDATION] Decide the following morning, from the log, not from the roadmap.

1. **R1 prints NO GO.** Stop. The blocker it names (custom symbols refused, `CustomTicksAdd`
   refused, folder tree, algo-trading flag) is the new top of the roadmap, ahead of both CRITICALs.
   [CONFIRMED FROM CODE] Preflight's own words at `:399-401`: without custom symbol creation
   *"NOTHING in this product works"*.
2. **R2 reaches stage 43 with failures.** Take the **first** FAIL only and check it against
   `verified.json`. A failure the audit predicted is a confirmed finding moving to the top of its
   phase. A failure the audit did not predict is a new finding, and it is worth more than any of the
   248 — it was found by observation. Proceed to T's Phase 0A in its published order.
3. **R2 reaches stage 43 clean and stage 42's mean repaint is well under 100 ms.** Then the audit's
   most quantitative claim was pessimistic, Phase 6 keeps its designs and loses its urgency, and
   0A.6 followed by 0C.2 is the honest next fortnight. [INFERENCE] Record the number either way. It
   is the first measured figure this project will own.

---

### V.8 Why this, and not "just fix the CRITICALs"

[INFERENCE] The counter-argument deserves a straight answer, because it is the obvious plan.

Two CRITICALs and fourteen HIGHs are a strong case for starting with 0C. The reason not to is
arithmetical rather than temperamental. 0C.2 alone is 2-3 weeks against a test suite six of whose
sections are false, in a product whose only performance figure came from a different context, with a
probe (P6) unanswered that would change three designs, and 30 findings unsettleable without a
terminal. [CONFIRMED FROM CODE] 125 builds have been produced this way. [INFERENCE] The failure mode
of continuing is not that the fixes are wrong — most of them are almost certainly right — it is that
build 126 through build 140 are also unobserved, and at the end of it the same question is still open
and now has fifteen more builds of change sitting on top of it.

Three to five days buys the answer. [RECOMMENDATION] Spend them first.

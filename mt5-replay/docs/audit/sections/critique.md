## CRITIQUE — COMPLETENESS AND CONSISTENCY REVIEW OF SECTIONS A–V

*Scope: every file in `/tmp/claude-0/audit/sections/` (A.md … V.md, plus `C-generated.md` and the
three `M-proposal-*.md` drafts) checked against
`/home/user/academyss/mt5-replay/docs/audit/verified.json` (248 findings) and against the audit
brief's own checklist. Every claim below is machine-checkable: each cites a section file and line, a
finding id, or a source file and line. Where I could not settle something, I say so rather than
assert it.*

**Method.** Four mechanical passes plus a read: (1) every one of the 248 finding ids was matched
against every section file, with `prefix-N` shorthand (`` `-5` ``) resolved against the last full id
on the same line; (2) every backticked id was compared with the severity and classification word
that follows it, against `verified.json`; (3) every prose block was classified as tagged / untagged
and as carrying / not carrying a code reference; (4) the claimed counts in A, B.17, C.1, D and U.10
were recomputed from `verified.json`. The scripts are in the scratchpad; every number below is
reproducible.

**Headline.** Coverage is genuinely broad — **all 248 ids are cited somewhere, and none is
orphaned.** The defects are not gaps in *what was looked at*; they are (a) one systematic citation
error repeated 60+ times, (b) one section (U) whose coverage table and conclusion contradict the
findings file and section A, (c) a class of new-from-source defects that never went through the
audit's own quality gate and is never totalled, and (d) a small set of checklist sub-areas that are
neither found nor explicitly cleared.

---

### 1. THE SYSTEMATIC DEFECT: 60+ citations quote the *pre-verification* severity

`verified.json` carries two severity fields per finding: `severity` (as filed by the subsystem
reader) and `final_severity` (after the three refuters and two confirmers). **105 of the 248 findings
differ between the two.** A.md, C.1 and B.17 use `final_severity` and are correct. Eleven other
sections quote the filed severity as though it were the verdict.

**Verified correct (do not change):**

* **C.1** (`C.md:19-27`) — 2 / 14 / 58 / 105 / 18 = 197. Recomputed from `final_severity`: exact match.
* **C.2's subsystem table** (`C.md:31-51`) — every row and both totals reproduce exactly.
* **B.17's location table** (`B.md:952-967`) — all 14 rows reproduce exactly against `final_severity`
  over the 227 non-refuted findings (Mt5 = 8 = 4+3+1 across three files; CRIT 0 / HIGH 1 / MED 5 /
  LOW 2). Its claim *"`Core` holds 5 of the 14 `HIGH` findings"* is exactly right
  (`core-engine-1..4` + `core-sync-1`).
* **T.6.3's roster** (`T.md:315-319`) — the fourteen HIGHs it names are exactly the fourteen
  CONFIRMED HIGH ids, and it correctly demotes `ui-port-session-2` to MEDIUM at `T.md:337`.

**Wrong (60 distinct id/severity or id/classification mismatches; this is a lower bound — my matcher
stops at the next backtick, so a sentence naming two ids and one severity, e.g. `M.md:53`
*"(`ui-panel-1` and `ui-panel-2`, both CONFIRMED HIGH)"*, is not counted).** The worst, because they
contradict another delivered section rather than only the findings file:

| where | says | `verified.json` says | contradicts |
|---|---|---|---|
| `U.md:425` | `data-1` **CRITICAL** | CONFIRMED / **HIGH** | `A.md:47` lists `data-1` as HIGH in the top-defects table; `C.md` files it under HIGH |
| `U.md:692`, `S.md:44` | `ui-port-session-2` **HIGH** | CONFIRMED / **MEDIUM** | `T.md:337` explicitly calls it "(MEDIUM, and it is the same code path)" and promotes it *because* it is MEDIUM |
| `M.md:544`, `N.md:162`, `O.md:343`, `M-proposal-constraints-first.md:400` | `ui-panel-6` **HIGH** | CONFIRMED / **MEDIUM** | A.md's HIGH list does not contain it |
| `M-proposal-constraints-first.md:44-45` | `ui-panel-1`, `ui-panel-2` **CONFIRMED HIGH** | both CONFIRMED / **MEDIUM** | C.1's HIGH count of 14 |
| `U.md:34-35` | `qa-smoke-1`, `qa-smoke-2` **HIGH** | both CONFIRMED / **MEDIUM** | — |
| `U.md:532`, `:559`, `:594`, `P.md:239`, `:300` | `host-expert-3`, `-5`, `-6` **HIGH** | all CONFIRMED / **MEDIUM** | T.6.3's HIGH roster excludes all three |
| `U.md:658`, `:683` | `chart-2` HIGH, `chart-1` "HIGH, POTENTIAL_RISK" | MEDIUM, MEDIUM | — |
| `U.md:1189`, `:1192`, `:1296` | `ui-port-session-15`, `-13`, `ui-plumbing-13` **MEDIUM** | all POTENTIAL_RISK / **LOW** | — |
| `U.md:1343` | `ui-plumbing-5` **MEDIUM** | CONFIRMED / **IMPROVEMENT** | — |
| `U.md:1257`, `:1264` | `data-3`, `tests-b-3`, `strategy-integration-report-4` **MEDIUM** | all CONFIRMED / **LOW** | — |
| `H.md:41` | `tests-b-6` MEDIUM | CONFIRMED / LOW | — |
| `H.md:45`, `M-proposal-coach-first.md:376` | `trading-analytics-12` **LOW** | CONFIRMED / **MEDIUM** (the one finding *upgraded* by verification) | — |
| `M.md:184`, `N.md:731`, `O.md:308` | `ui-panel-12` MEDIUM | CONFIRMED / LOW | — |
| `M.md:572`, `N.md:967`, `M.md:1251`, `O.md:297` | `chart-10` MEDIUM, `chart-7` MEDIUM | both CONFIRMED / LOW | — |
| `M.md:949`, `N.md:733`, `O.md:314` | `ui-plumbing-1` MEDIUM | CONFIRMED / LOW | — |
| `M.md:1204`, `O.md:104`, `U.md:1377` | `ui-plumbing-9` LOW | CONFIRMED / IMPROVEMENT | — |
| `M.md:1066` | `ui-panel-4` MEDIUM | CONFIRMED / LOW | — |
| `M.md:523` | `ui-panel-5` "Hygiene, IMPROVEMENT" | CONFIRMED / **MEDIUM** | `H.md:47`, `I.md:55`, `N.md:312`, `O.md:216` all call it MEDIUM and treat it as blocking |
| `P.md:576` | `ui-dialogs-8` "POTENTIAL_RISK **MEDIUM**" | POTENTIAL_RISK / **LOW** | class right, severity is the filed one |
| `M-proposal-coach-first.md:448`, `:453`, `:463`, `:641`, `:91`, `:287` | six ids at filed severity | — | — |
| `E.md:470-472`, `:477` | table's own severity column disagrees with the id beside it in four rows | — | — |
| `A.md:76`, `:80` | `ui-dialogs-14`, `ui-plumbing-14` used as load-bearing UX evidence | both CONFIRMED / **LOW** | not a severity claim; flagged because A's "single biggest UX problem" rests on three LOWs and one MEDIUM |

**[RECOMMENDATION]** One mechanical pass: every `` `id` `` followed by a severity or classification
word is rewritten from `final_severity` / `classification`. Add one sentence to A or C stating that
`verified.json` carries both fields and that **only `final_severity` is quoted anywhere in the
report** — otherwise a reader who greps "HIGH" across the sections counts far more than fourteen.

---

### 2. SECTION U CONTRADICTS THE FINDINGS FILE AND SECTION A

U is the most-cited section after C and T (79 unique ids, 251 mentions) and is the document a
terminal operator will work from. Three defects in it are consequential.

**2.1 `ui-dialogs-1` — a CONFIRMED HIGH with no test, and a prose claim that hides it.**
[CONFIRMED FROM CODE] `ui-dialogs-1` (CONFIRMED, HIGH, `Ui/SSR_SetupPanel.mqh:300`) appears **nowhere
in U.md** — not in the U-01…U-40 tests, not in U.10's table, not in U.11's "what this plan cannot
prove". U.10's conclusion (`U.md:1543-1549`) states: *"The remaining confirmed HIGH findings are in
the test and spike layers … every one of them is an assertion that is false, tautological, or
unreachable in code."* `ui-dialogs-1` is in `Ui/`, is user-facing, and its consequence is that **no
session has ever been saved with a name** — `T.md:333` (0C.11) says exactly that. So the one
statement U makes about its own HIGH coverage is falsified by the finding it omits. `L.md:585`,
`P.md:693`, `N.md:672` and `O.md:369` all treat it as a gate; U alone does not see it.
**[RECOMMENDATION]** Add a U-test: type a session name at wizard step 1, advance to a step with no
`OBJ_EDIT`, return, assert the name survives; then assert `setup.ini` holds it and `OnDeinit`'s
`if(CfgSession() != "")` fires. T.6.3 already specifies the assertion.

**2.2 U.10's arithmetic is impossible.** `U.md:1543` claims *"**2 of 2 CRITICAL** and **19 of the
confirmed HIGH findings** reachable from a terminal."* There are **14** CONFIRMED HIGH findings in
total (C.1, B.17 and T.6.3 all agree). 19 of 14 cannot be reached. The twelve ids the same paragraph
calls *"the remaining confirmed HIGH findings"* are, per `verified.json`: `tests-a-1` MEDIUM,
`tests-a-2` MEDIUM, `tests-a-3` MEDIUM, `tests-b-1` MEDIUM, `tests-b-2` MEDIUM, `spikes-audits-2`
MEDIUM, `spikes-audits-4` MEDIUM, `spikes-audits-7` MEDIUM, `spikes-audits-8` MEDIUM,
`spikes-audits-10` MEDIUM, `spikes-audits-12` MEDIUM, `spikes-audits-14` **LOW**. **Not one of the
twelve is HIGH.** The paragraph reads as though 19 + 12 = 31 HIGH findings exist.

**2.3 U.10's class column is wrong in 13 of 40 rows** (U-01, U-03, U-10, U-13, U-14, U-15, U-17,
U-18, U-21, U-23, U-26, U-35, U-38) — all the same pre-verification-severity error as §1. Two rows
also use bare shorthand that does not resolve: `U-33` "`ui-port-session-11`, `-10`; decides `-15`,
`-13`" and `U-34` "`trading-analytics-12`, `-5`, `-2`". A coverage table is the one place an id must
be written in full.

---

### 3. SECTION D'S COVERAGE STATEMENT: AN OFF-BY-ONE AND AN UNDER-ENUMERATION

[CONFIRMED FROM CODE] `D.md:365`: *"123 `.mq5`/`.mqh` files, 51,278 lines … **91 files carry at least
one finding; 33 carry none.** Those 33 are enumerated below."*

* 91 + 33 = **124**, against a stated total of 123.
* `verified.json` contains exactly **91 distinct `file` values**, so the number that carries no
  finding is **32**, not 33.
* The enumeration below names **36 distinct file basenames**, of which five are named as *not* clean
  (`SSR_Strings.mqh` and `SSR_ReviewCard.mqh` under `ui-plumbing-13`; `SSR_RiskEngine.mqh` and
  `ssr_audit.py` in "examined but not clean"; `SSR_C1_ServiceApiAccess.mq5` explicitly "not clean").
  **31 files are actually enumerated as clean, against a claim of 33.** At least one file with no
  finding is neither enumerated nor accounted for.

This matters more than the arithmetic: the coverage statement's entire purpose (`D.md:363`) is that
*"silence is ambiguous in an audit"*. A miscount in the sentence that removes ambiguity reintroduces
it. **[RECOMMENDATION]** Recompute from `verified.json` and name the missing file, or say which of
the 123 is deliberately excluded.

**Second contradiction, D ↔ H.** `D.md:410` says *"Section H records **eight** defects and gaps read
directly from source."* `H.md:50-65` lists **nine** bullets (refusal reason has no path to screen;
longest reason string undrawable; panel's second risk-money formula; `ConfigureFromSymbol` fabricates
a model; `vol_max` cap announced to a caller that ignores it; tick-value asymmetry cloned but unused;
`MoneyOf` duplicated; `risk_at_entry` excludes commission; `RoundToStep` does not normalise).

---

### 4. CHECKLIST AREAS WITH NO FINDING **AND** NO EXPLICIT "CHECKED, NOTHING FOUND"

I resolved each of the brief's ~50 areas against both `verified.json` categories and the section
text. Most are covered — see §8 for the list I verified as covered, so that my silence there is not
read as an omission. **Five are not.**

**4.1 Race-like state transitions — no finding, no statement. [CONFIRMED FROM CODE that the term is
absent]** `verified.json` has no category for it and no finding whose claim turns on it. Across
A–V the word appears three times and never as an audit of the product: `B.md:986` and `U.md:1575`
refer to `spikes-audits-14` (a *spike's own* race test that runs writer and reader sequentially in
one thread); `D.md:98` uses "race" about `ChartSetSymbolPeriod` asynchrony inside `mt5-symbol-4`.
Nothing anywhere states the hazard class was examined and found clean. The concrete question left
open: **`OnChartEvent` arrives while `OnTimer` is mid-pump** — `SSReplayStandalone.mq5:3111` is the
event entry, `PollClicks()` + `Render()` run inside the timer at `:2897`-region cadence, and
`CSSRPanel::Dispatch` mutates panel state (`m_tab`, `m_compact`, latches) that `Render()` is reading.
MQL5 gives each program its own thread and queues chart events, so this is probably an ordering
question rather than a data race — **but no section says so.** [INFERENCE] One paragraph in D's
hazard-class list would close it: state the MQL5 threading model, name the three mutable panel
fields, and say whether the queue guarantees non-interleaving. **[RECOMMENDATION]** Add it as a
hazard class, not a finding — inventing a defect here would be worse than the gap.

**4.2 Keyboard conflicts with the terminal's own chart keys — no finding, no statement.**
[CONFIRMED FROM CODE that the term is absent] A grep for `terminal hotkey|MetaTrader's own key|
reserved key|terminal's own shortcut` returns **zero hits in all 22 sections**. What *is* covered is
the conflict class *internal* to the product: `ui-plumbing-2`, `-3`, `-14`, `-15` (wrong or missing
key documentation), and `O.md:488-527` which states *"22 bindings today, all vk values distinct, 18
`listed`"* — that is an audit of the key table against itself. The uncovered class is the panel's
single-letter bindings against MetaTrader's own chart bindings on the same chart — the arrow keys,
`Home`/`End`, `+`/`-`, and the period-switch keys. Since the panel is drawn on a chart the EA does
**not** own (ground truth), whether the EA even receives those keys, and whether the terminal also
acts on them, is unknown from source. **[RECOMMENDATION]** This is a probe, not a finding: add one
line to V's optional `InpLogEvents` probe (`V.md:135-144`) and one row to U-36/U-37 — press every
bound key on the replay chart and record whether the chart also scrolled or changed period.

**4.3 A mid-run chart-timeframe change by the user — no finding, no statement.** [CONFIRMED FROM
CODE] The configured timeframe is covered (`host-expert-10`, `P.md:247`, `U-03` for the harness
dropped on a non-M1 chart). The *runtime switch* is not: `ChartSetSymbolPeriod` appears only in
`B.md` and in `D.md`'s refutation of `chart-15` ("grep finds no caller anywhere"). Ground truth says
timeframe series build lazily and the first `Bars()` on an untouched timeframe returns 0 — which is
precisely `qa-smoke-1`'s mechanism — yet no section asks what the sink, the chart manager's
`Redraw()`/`ChartNavigate(CHART_END)` path (`E.md:170-175`) or `CSSRBlindMode`'s re-apply do when the
user switches the replay chart from M1 to M15 at minute 40 of a run. `spikes-audits-6` (D2) exists to
measure timeframe-switch cost and is itself defective. **[RECOMMENDATION]** One U-test on an existing
bench symbol; no new finding may be filed without it.

**4.4 The forced-liquidation loop — examined only as another finding's failure scenario.**
[CONFIRMED FROM CODE] `CSSRTradingEngine::CheckStopout` (`Trading/SSR_TradingEngine.mqh:436`, called
at `:613` on every tick batch) closes worst-loser-first under a `SSR_MAX_POSITIONS` guard. No
`verified.json` finding targets it. It is named in exactly two places in A–V: `C.md:1174`/`:1176`,
inside `trading-exec-6`'s scenario, and `P.md:247` as an input row. There is no statement that the
loop itself was read — whether it terminates, whether `Equity()/used` can divide by a `used` that
changes inside the loop, whether a partial close would be the broker-correct action. **A second,
unstated consequence:** `CheckStopout` returns immediately when `m_margin_per_lot <= 0.0`, and
`InpMarginLot` defaults to **0** (`G.md:629`, finding G-6), so **stop-out is dead in the shipped
configuration** — which also means `trading-exec-6`'s "accepted, charged, then stopped out" cannot
occur at defaults. G-6 says the account is "frictionless out of the box"; it does not draw this
consequence. **[RECOMMENDATION]** Either a coverage line in D, or one sentence in G/H naming the
default-gating.

**4.5 Object-name collisions across the nine prefixes — findings exist, tree-wide sweep does not.**
Findings do cover instances: `ui-panel-5` (two cache slots write the same object id `setuprow`),
`chart-17` (bookmark names carry a registry index, so they duplicate after a chart closes),
`ui-plumbing-6` (no tombstones → `Keep()` writes a duplicate slot), `tests-b-15` (duplicate-name
check masked by a timeframe check). `M.7` (`M.md:1098-1133`) is an excellent forward-looking slot
budget and enumerates every used and free label slot. **What is missing is a statement about the
current build's whole object-name space**: `E.md:405` records nine prefixes in use (`SSRP_ SSRS_
SSRD_ SSRSD_ SSRK_ SSRX_ SSRF_ SSRV_ SSRR2_`) plus the un-prefixed chart-side families (`SSR_POS_*`,
bookmark lines, calendar lines), and D's hazard-class list — which does run tree-wide sweeps for
*real-order paths*, *source encoding* and *swap modelling* — has no line for it. Given the ground
truth that **`ObjectCreate` refuses an existing name and errors on nothing**, a collision across two
prefixes is a silent stale object, which is exactly the failure `ui-panel-5` is. **[RECOMMENDATION]**
A fourth hazard-class line in D, backed by the same kind of grep the other three use.

---

### 5. NEW-FROM-SOURCE DEFECTS: NO REGISTER, NO IDS, NO REFUTER PASS

The audit's credibility rests on the process A.md:35-37 describes — *"197 CONFIRMED — survived three
adversarial refuters, two confirming from source … a list that never loses candidates is not an
audit."* At least **18 further defects are asserted in the sections, with severities, that never went
through it**:

* `G.6` (`G.md:618-632`) — **G-1 … G-6**, with file:line, severity and `[CONFIRMED FROM CODE]`. The
  only new findings anywhere that carry citable ids. G-5 (the absence of an audit for the
  no-broker-order guarantee) is asserted as MEDIUM and is the product's *central safety claim*.
* `H.3` (`H.md:50-65`) — **nine** more, each with a self-assigned severity (`— severity MEDIUM`,
  `— severity LOW`, one `[POTENTIAL_RISK]`), none with an id. D.md:410 forwards the reader here and
  miscounts them as eight (§3).
* `S.12` (`S.md:971-973`) — three rows labelled *"new, from source"* with no id and no severity.
* Scattered elsewhere: `L.md:125` (sheet arithmetic written for 295 px, never re-derived for 245),
  `S.md:600` (`[CONFIRMED FROM CODE — correction to N.9]`, a 1 px overrun in N's own filter-cell
  arithmetic), `M.md:178` (`[CONFIRMED FROM CODE — correction to the winner's M.1.6]`),
  `O.md:116` (`[CONFIRMED FROM CODE — correcting a claim that circulated before M]`).

Consequences, all checkable:

1. **They are invisible to every count.** C.1's 197 and B.17's 227 are computed from
   `verified.json`; none of these 18+ is in it. A reader totalling the audit's defects from the
   headline numbers under-counts by at least 18.
2. **Only G's are citable.** `H.3`'s nine and `S.12`'s three have no id, so no later section, test
   plan or roadmap row can reference them. They cannot be tracked to closure.
3. **They carry peer severities on a scale defined in C.1 without meeting C.1's bar.** `H.3`'s
   `ConfigureFromSymbol` fabrication is asserted MEDIUM; a MEDIUM in C.1 means "wrong output or dead
   behaviour a user will meet in normal use" — a claim the refuters would have tested.
4. **They are not scheduled.** `G-1 … G-6` appear nowhere in T.md; no T row cites a G- id.

**[RECOMMENDATION]** One consolidated register — a new subsection of D or a `C.8` — giving every
new-from-source defect an id in a distinct namespace (`new-1 …`), its file:line, its severity, and
an explicit line saying these did **not** go through the refuter process and are therefore weaker
evidence than a `verified.json` CONFIRMED. Then wire the ids into T. Do **not** merge them into the
197; that number's value is precisely that it means one specific thing.

---

### 6. THE ROADMAP DOES NOT ACCOUNT FOR WHAT IT DOES NOT SCHEDULE

[CONFIRMED FROM CODE] With shorthand resolved, `T.md` cites **183 of the 227 non-refuted findings**.
**64 are not scheduled anywhere in T**: 48 LOW, 11 IMPROVEMENT, and **5 MEDIUM**:

| id | class | file:line | what it is |
|---|---|---|---|
| `strategy-integration-report-2` | CONFIRMED | `SSR_StrategyHost.mqh:184` | `OnBar` detected from the last tick of a published batch, so its firing point and the resulting bar are wrong |
| `strategy-integration-report-9` | CONFIRMED | `SSR_ClassReport.mqh:493` | class KPI row, ranking sort and bar scale include students who ran a different session |
| `ui-port-session-9` | CONFIRMED | `SSR_GroupPort.mqh:372` | pending orders occupy wire rows no total on the wire accounts for |
| `chart-1` | POTENTIAL_RISK | `SSR_ChartManager.mqh:452` | one false scroll-detect kills follow for the session |
| `host-expert-12` | POTENTIAL_RISK | `SSReplayStandalone.mq5:681` | history download abandoned after ~1.8 s, and the log blames the broker |

`T.17` ("What is not scheduled, and why", `T.md:656-681`) is the right instrument and names eleven
refusals — but **none of the five above**. `T.18` then states *"the most likely way this roadmap is
wrong is not that an item is missing — 248 findings across 17 subsystem maps is thorough coverage."*
That sentence is unsupported while five MEDIUMs, two of which are POTENTIAL_RISKs the roadmap
elsewhere treats as branch points (`T.18` itself branches on `data-2` and `mt5-symbol-4` but not on
`chart-1`), are silently unscheduled. **[RECOMMENDATION]** Either schedule them or add them to T.17
with a reason. Then state the residue explicitly: *"X of the 227 non-refuted findings are LOW or
IMPROVEMENT and are not individually scheduled; they are swept by REFACTOR items N and M."*

---

### 7. TAGGING, AND CLAIMS NOT TRACEABLE TO CODE OR A FINDING ID

**7.1 Untagged prose is the dominant style violation.** Fraction of prose blocks (code fences,
tables, headings and list-only blocks excluded) carrying **no** tag:

```
T 10%   A 10%   V 14%   B 20%   K 24%   L 31%   O 32%   S 32%   H 38%   I 38%
R 52%   Q 54%   F 55%   P 56%   G 56%   M 58%   N 58%   C 59%   U 59%   E 62%   J 73%   D 75%
```

C and D score badly on a very small prose base (22 and 4 blocks respectively — both are catalogues,
and their entries are tagged inside the per-finding template), so their numbers are not meaningful.
**The real outliers are J, E, U, M, N, G, P, F, Q, R.** In most cases the untagged block *does*
carry a file:line, so the claim is traceable and only the tag is missing — but the brief asks for a
tag on every claim, and the tag is what separates a source fact from a judgement. Representative
untagged, un-cited, id-free, code-asserting blocks, by section and approximate line:

* `E.md` ~149, ~157, ~170, ~176 (the `CSSRTradeLines` per-call write accounting and the two stacked
  redraw throttles — all load-bearing performance claims)
* `F.md` ~108, ~121, ~143, ~175 (the synthetic-tick `u` ladder showing neither extreme is ever
  emitted — one of F's most important conclusions)
* `G.md` ~42, ~96, ~145, ~211 (the A23 deny-by-default argument, and the enumeration of where the
  "all virtual" string is and is not drawn)
* `J.md` ~28, ~142, ~168 (the reproducibility surface beyond the start-pick)
* `M.md` ~30, ~76, ~100, ~107; `N.md` ~20, ~85, ~157, ~195; `P.md` ~19, ~36, ~87, ~125, ~156;
  `Q.md` ~128, ~163, ~226, ~271; `R.md` ~66, ~73, ~86, ~205, ~220
* `U.md` ~68, ~128, ~157, ~186, ~195, ~211 (test procedures — arguably the least harmful place for
  an untagged block, since a procedure is not a claim)

**7.2 Claims tagged `[CONFIRMED FROM CODE]` that are not derivable from the source tree.** These are
the ones that actually break the tag's contract:

* `A.md:14` and `T.md:635` — *"The author has never run it on a real MetaTrader 5 terminal"* /
  *"MT5 cannot be installed in the build environment"*, both tagged **[CONFIRMED FROM CODE]**. These
  are premises supplied to the audit, not facts read from `MQL5/`. They are almost certainly true and
  they frame the whole report — which is exactly why they should be labelled as a stated premise (or
  `[INFERENCE]`), not as something a reader can check at a line number.
* `E.md:29-31` — the 561-writes / 39.05 ms / 77-lookups figures tagged **[CONFIRMED FROM CODE]** in
  a paragraph that then says *"Provenance is a user's run, recorded in prose; there is no CSV, no run
  id, and no way to re-derive it here."* What is confirmed from code is that the comment at
  `SSR_Widgets.mqh:31-38` **says** so. A.md:26 gets this right by citing the comment; E does not.
  E.9's whole thesis is that the measurement layer cannot be believed — it should not exempt the one
  measurement it inherits.
* `T.md:292` — *"[CONFIRMED FROM CODE] D's grep establishes that nothing in this product can place a
  broker order, **so every probe below is safe on a logged-in terminal**."* The grep is confirmed;
  "safe on a logged-in terminal" is an inference, and it is the one inference in the report where
  being wrong costs the reader money. The sentence's own remedy ("use a demo account anyway") is
  tagged `[RECOMMENDATION]` — the safety claim should be `[INFERENCE]`.

**7.3 One un-reconciled number.** A.md:26, B.md:832 and E.md:29 use **561** property writes per still
frame (the measurement in `SSR_Widgets.mqh:31-38`). M.md:123 and N.md:916 use **~586** as "today".
M.1.2 tags its ~586 `[INFERENCE, from two CONFIRMED findings plus the arithmetic above]` and shows
its working, so this is a derived figure rather than a contradiction — but E (the performance
section) and M/N never acknowledge each other, and a reader taking E.10's ranked list together with
N.11.2's ledger gets two baselines for the same frame. One cross-reference in E.1 closes it.

---

### 8. WHAT I CHECKED AND FOUND CLEAN — so my silence is not ambiguous

* **Orphaned findings: none.** All 248 ids are cited in at least one delivered section. Every
  CONFIRMED id appears in C.md (197/197). Every POTENTIAL_RISK appears in D.md (30/30). Every
  NOT_A_BUG appears in D's refuted table (21/21). No finding is lost.
* **NOT_A_BUG discipline: zero violations across all 22 sections.** All 21 refuted ids appear only
  (a) in D's refuted table, (b) in `T.1.4`'s do-not-fix list (`T.md:120-125`), or (c) with an
  explicit refutation label at the point of use: `G.md:553-554`, `K.md:755`, `F.md:283`,
  `I.md:48-49` and `I.md:246`, `J.md:126`, `V.md:239`, `M.md:538` and `:1262`, `N.md:183`,
  `O.md:78`, `U.md:773`, `:1377`, `:1398`. `I.md:246` and `T.1.4` go further and forbid "fixing"
  them. This is the strongest discipline in the report.
* **POTENTIAL_RISK presented as a confirmed defect: no clear instance.** Three soft cases only:
  `S.10.1` and `S.10.2` are section headings naming `trading-analytics-14` and `-13` whose bodies
  tag `[CONFIRMED FROM CODE]` and prescribe fixes without restating the classification — S.12's
  ledger (`S.md:969-971`) does label all three correctly, 80 lines later; `S.md:45` does the same for
  `trading-analytics-15`. `V.md:132-133`'s edit table lists `qa-smoke-6` and `qa-smoke-3` in a
  "Closes" column with no class, though V labels both correctly at `:99` and `:113`. Fix by
  restating the class at first use in each subsection; no finding is misclassified.
* **`C-generated.md`'s two POTENTIAL_RISK ids are not misclassifications.** `chart-1` (`:1559`) and
  `data-2` (`:3217`, `:3219`) appear inside a file titled "C. CONFIRMED BUGS", but both occurrences
  are cross-references inside *another* finding's verifier text, not entries of their own. C.md — the
  delivered version — contains exactly the 197 CONFIRMED and nothing else.
* **Checklist areas verified as covered** (each has at least one finding *and* substantive section
  treatment; I am not listing them as gaps): future-data leakage (13 findings, F.5), historical
  boundaries (40), tick ordering (6, F.3), candle construction (F.3's synthetic-tick extremes,
  `mt5-symbol-2`'s BID mode, E.5), custom-symbol sync (`mt5-symbol-1…7`, U-23), timeframe generation
  (`qa-smoke-1`, `tests-a-10`, `spikes-audits-6`), history loading (E.6, `data-5`, `host-expert-12`,
  U-27), rewind/snapshot consistency (F.8, `core-engine-7/-8`, `core-sync-6`, `trading-exec-1/-2`),
  object lifecycle (21), timers (5 + E.4), event handling (17), redraw efficiency (6 + E.3), memory
  (4 + E.8), ObjectSet/Create volume (E.1, E.2, M.1.2), CPU (6 + E), UI repaint (E.1, M.1.2, N.11.2),
  spread (3), commission (2 + S.3), swap (refuted + D's explicit tree-wide "checked" line), slippage
  (`trading-exec-9` + G), margin (`trading-exec-6` + H.3), SL/TP execution (5 + G.5), partial close
  (D's explicit "examined but not clean" line forwarding to H), trailing/break-even (`trading-exec-2`,
  `-8`, R.4, G.5), pending orders (`trading-exec-5`, `-9`, `-10`, `-11`, `trading-analytics-5`,
  `ui-port-session-9`), drawdown (3), R-multiple (3), risk calculation (H, and D's explicit line that
  `SSR_RiskEngine.mqh` carries no `verified.json` entry and is *not* a clean file), prop-rule edges
  (5 + I), session save/resume (24 + U-18/19/33), seed reproducibility (J.2/J.3, F.7, U-35), import
  validation (K.3, and K.0's honest statement that import does not exist at v125),
  FULL_TICK/SYNTHETIC/BAR consistency (F.3, U-28/29/30), multi-symbol (`chart-2`, `host-expert-10`,
  U-31), Persian/UTF-8 (8 + L.8 + Q), RTL (`ui-plumbing-5` + Q), 63-char limits (8 + R5/A22 budgets
  throughout M/N/O/Q/R/S), clipping and overflow (L.9, the `Extent()`/`CheckFrame()` instrument,
  U-39), z-order (3 + M/O), invalid inputs (19 + P), boundary conditions (40), zero/empty/null (17),
  broker-specific symbol behaviour (6 + U's bench matrix).
* **A.md, B.md and T.md are the strongest sections** on every axis I measured: highest tag density
  (10%, 20%, 10% untagged), zero uncited code-asserting blocks in B, and B.17's and T.6.3's numbers
  reproduce exactly from `verified.json`.

---

### 9. PACKAGING: STALE ARTEFACTS SITTING BESIDE THE DELIVERABLES

* **`C-generated.md` (863 KB, 3,454 lines)** duplicates C.md's structure and heading hierarchy and
  carries **zero tags of any kind** — 0 `[CONFIRMED FROM CODE]`, 0 `[INFERENCE]`,
  0 `[RECOMMENDATION]` (C.md has 401 / 2 / 197). It also cites 199 ids where C.md cites 197. If it
  ships, it violates the tagging rule end to end and puts two POTENTIAL_RISK ids inside a document
  titled "CONFIRMED BUGS". **[RECOMMENDATION]** Delete or move out of the sections directory.
* **Three superseded proposals** (`M-proposal-user-first.md`, `M-proposal-coach-first.md`,
  `M-proposal-constraints-first.md`) sit beside the chosen `M.md`. Between them they carry 12 of the
  60 severity errors in §1 and one un-labelled POTENTIAL_RISK reference
  (`M-proposal-coach-first.md:607`, `ui-panel-11`). M.11 (`M.md:1271`) already records how the three
  were settled, so the drafts are archive material, not deliverables.
* **Thinness.** `H.md` (139 lines) is the thinnest substantive section and carries the entire risk
  engine plus nine un-registered new defects; it is dense and well-cited rather than shallow, but it
  is the section a reader is most likely to under-weight relative to its content. `A.md` (100),
  `J.md` (244) and `I.md` (248) are short by design. No section is missing: A–V are all present.

---

### 10. RANKED FIX LIST

| # | Fix | Why first | Effort |
|---|---|---|---|
| 1 | Rewrite `U.10` from `verified.json`: correct the 13 class cells, delete the "19 of the confirmed HIGH" sentence, replace the "remaining HIGHs are in the test and spike layers" paragraph with the true residue, expand the `-10`/`-15`/`-13`/`-5`/`-2` shorthand | It is the operator's coverage contract and it currently over-states coverage and mis-states severity in the same table | S |
| 2 | Add a U-test for `ui-dialogs-1` (CONFIRMED HIGH, no test today); T.6.3 already writes the assertion | A CONFIRMED HIGH in production UI code with no terminal test, hidden by a false prose claim | S |
| 3 | One mechanical pass rewriting every `` `id` ``+severity from `final_severity`, plus one sentence in A or C stating the two-field convention | 60+ occurrences, at least four of them contradict another delivered section | M, mechanical |
| 4 | Fix `D.md:365`'s count (91+33=124 against 123; 31 clean files enumerated against 33 claimed) and `D.md:410`'s "eight" → nine | The coverage statement exists to remove ambiguity | S |
| 5 | Consolidated register for the 18+ new-from-source defects: ids, severities, and an explicit statement that they did not go through the refuter process | They are currently uncountable, uncitable and unschedulable | M |
| 6 | Four hazard-class / coverage lines in D: race-like transitions, object-name namespace across nine prefixes, mid-run timeframe switch, the `CheckStopout` loop (and that it is dead at default `InpMarginLot=0`) | Four checklist areas with neither a finding nor a "checked" statement | M |
| 7 | Add the five unscheduled MEDIUMs to T (schedule or refuse in T.17), and state the LOW/IMPROVEMENT residue | T.18 currently claims completeness the roadmap does not have | S |
| 8 | Retag: A.md:14 / T.md:635 (premise, not code), E.md:29 (a comment says it, not the code), T.md:292 (safety inference) | Three places where the strongest tag is on the weakest evidence | S |
| 9 | Restate the classification at first use in `S.10.1`, `S.10.2`, `S.md:45`, `V.md:132-133` | Four POTENTIAL_RISKs that read as confirmed until the reader reaches the ledger | S |
| 10 | Reconcile 561 vs ~586 with one cross-reference in E.1; move `C-generated.md` and the three M drafts out of the sections directory | Hygiene | S |

**[INFERENCE] One closing judgement.** The audit's substance is stronger than its bookkeeping. The
process that produced `verified.json` — 248 candidates, 21 refuted, 105 severities revised — is the
most credible thing in the package, and B.17, C.1 and T.6.3 use it correctly. The errors above are
almost all of one kind: sections written against the *filed* findings rather than the *verified*
ones, and never re-reconciled after verification moved 105 severities. That is a single pass to fix,
and until it is fixed a careful reader who checks one citation against `verified.json` will find a
mismatch on the first or second try — which costs the report more than any individual number in it.

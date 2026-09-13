## T. PRIORITY ROADMAP

This section turns the 248 verified findings and the thirteen design sections (E-S) into one
ordered plan. It adds no finding, and it invents no defect: every item below is either a
`verified.json` id, a change specified in an earlier section, or a scheduling judgement that is
labelled as one.

---

### T.0 How to read this section

**Tags.** `[CONFIRMED FROM CODE]` — read out of the v125 tree at the cited file and line, or
counted mechanically from it. `[INFERENCE]` — the fact is confirmed, the consequence drawn from it
is judgement. `[RECOMMENDATION]` — a proposal. `[FUTURE FEATURE]` — work that does not exist in the
tree at all. **Every effort figure, every regression-risk rating and every phase boundary in this
section is `[INFERENCE]` or `[RECOMMENDATION]`**, stated once here so the tables stay readable:
nothing in T has been built or measured, and the author has never run this product on a terminal.

**Severity is read from `final_severity`.** [CONFIRMED FROM CODE] `verified.json` carries both
`severity` (the finder's) and `final_severity` (the verifiers'); the counts this audit publishes —
2 CRITICAL, 14 HIGH, 58 MEDIUM, 105 LOW, 18 IMPROVEMENT confirmed — are the latter. Where a finder
filed HIGH and the refuters settled MEDIUM, T schedules the MEDIUM. Two exceptions are promoted
explicitly and argued for in T.6.1; nothing is promoted silently.

**Effort scale.**

| | meaning |
|---|---|
| **S** | under a day. One file, roughly ≤ 50 lines, no contract change, no new object id, no new wire field. |
| **M** | two to five days. Two to four files, roughly ≤ 250 lines. May add a struct field, a wire field, an object id, a catalogue string. |
| **L** | a week or more of focused work. A contract changes, or a file layout changes, or the change crosses three layers, or it is ≥ 250 lines. |
| **L · multi-week** | three weeks or more, and it is dishonest to plan it as anything smaller. Every item carrying this mark is collected in T.16. |

**Regression-risk scale.** *low* — the change is arithmetic, a string, or a guard on a path that
today does nothing correct. *medium* — a shipped number moves, or a new field must be filled by
every caller, or a cache key changes. *high* — the change inverts when something happens (teardown
ordering, event ordering, epoch ordering); getting it wrong leaves an object on the user's chart
permanently, or a balance that disagrees with the trade list.

**"The specific test that proves it done"** is a column, not a paragraph, and it names a real
artefact: a section id in one of the fifteen `MQL5/Scripts/SSReplay/Tests/SSR_T*.mq5` scripts, a
stage in the 5,512-line `MQL5/Scripts/SSReplay/QA/SSR_QA_Smoke.mq5`, a spike under
`MQL5/Scripts/SSReplay/Spike/` or `MQL5/Services/SSReplay/Spike/`, or a numbered audit in
`tools/ssr_audit.py`. Where the proving test does not exist yet, the column says `new:` and gives
the assertion.

**One piece of bookkeeping T has to settle, because the earlier sections collide.**
[CONFIRMED FROM CODE] Audits A1-A21 exist in `tools/ssr_audit.py` and pass today. Six sections each
proposed "the next audit", and three of them independently claimed the number **A22**, two the
number **A23**. T assigns the numbers once, here, and every reference in this section uses this
table and no other. **[RECOMMENDATION]**

| # | Audit | Proposed in | Scheduled |
|---|---|---|---|
| A22 | No `OrderSend` / `OrderSendAsync` / `CTrade` / `PositionClose` anywhere under `MQL5/` | G.1.2 | 2.1 |
| A23 | Clip discipline: every drawn string passes a character budget at its call site | M.2 R5, M.8.1 #17 | 6.3 |
| A24 | One key list: the generated table is the only one, and `SSRKeyHint()` is generated from it | O.11 | 6.4 |
| A25 | No file under `Ui/` includes `SSR_RiskEngine.mqh` | H.8 | 2.7 |
| A26 | Every stored setting has a spec row, a `Cfg*()` accessor and a catalogue string | P.11 P11 | 6.7 |
| A27 | Digit policy: no Persian/Arabic-Indic digits in a catalogue value outside an allow list | Q.10 (as its A23) | 7.7 |
| A28 | One object, one direction: no catalogue value mixes Arabic script with a `printf` marker outside the Shape-B list | Q.10 (as its A24) | 7.7 |
| A29 | Mirror coverage: no bare `+` on an integer literal in an `x` argument under `Ui/` without an `// unmirrored:` justification | Q.10 (as its A25) | 7.6 |

**The one gate.** **[STATED PREMISE — not a source fact]** Build v125 has never been run on a
MetaTrader terminal, and MT5 cannot be installed in the build environment. Neither half is derivable
from `MQL5/`; both were supplied to this audit, and A.md labels them the same way. What *is*
[CONFIRMED FROM CODE] is the codebase saying so about itself at `SSR_QA_Smoke.mq5:6-7`,
`SSR_Widgets.mqh:122-123` and `SSReplayStandalone.mq5:1940-1944` (quoted in U.0), and that every
runtime claim in this audit is derived from source. **Phase 0 is therefore not a phase of work with validation attached to it — it is the
validation, with the two CRITICALs and the fourteen HIGHs attached.** No item from Phase 1 onward
may start before Phase 0's exit gate, and the reason is arithmetical rather than procedural: 30
findings are classified POTENTIAL_RISK precisely because source cannot settle them, and at least
four of them (`data-2` HIGH, `mt5-symbol-2`, `mt5-symbol-5`, `ui-panel-11`) would change the design
of a later phase if they fire.

---

### T.1 KEEP

[RECOMMENDATION] These are not "things that work". They are decisions whose violation re-creates a
defect this project has already paid for, or removes the reason it is repairable rather than
rewritable. Every roadmap item in T.6-T.14 is written to extend them. The full lists live in B.18
(layer-spanning), F.2 (engine), L.10 (UI), K.15 (data) and E.11 (performance); this is the
roadmap-facing digest, and an item here is a veto on any change that contradicts it.

#### T.1.1 Structure

| # | Invariant | Why it is load-bearing |
|---|---|---|
| K1 | `Core` includes `Common` only — never `Data`, `Mt5`, `Chart`, `Ui`, `Trading`, `Session`. | [CONFIRMED FROM CODE] B.1's edge matrix: `Core → Common 34`, nothing else. It is what makes the engine testable with `CSSRMemoryDataSource` + `CSSRRecordingSink`, and what would let it move into a Service untouched. |
| K2 | The five contracts stay in `Core`: `CSSRHistoryProvider`, `CSSRBarProvider`, `CSSRTickProvider`, `CSSRReplaySink`, `CSSRTickObserver`. A new data source is a new implementation, never a new dependency. | [CONFIRMED FROM CODE] This is why Phase 8 (import) is additive and Phase 1's `OnBulkBars` is a one-method contract change rather than a rewrite. |
| K3 | No MetaTrader API call in `Common` except in `SSR_Platform.mqh`. | [CONFIRMED FROM CODE] One place reads terminal facts, which is why `SSRCanBlock()` can gate every retry loop in the product. |
| K4 | `Trading → Report` is deliberate. `SSR_ReportStyle.mqh` is a leaf shared by the statement and the class report. | [CONFIRMED FROM CODE] "Fixing" the upward edge would put HTML in the trading layer. |
| K5 | No `OrderSend`, `OrderSendAsync`, `CTrade` or `PositionClose` anywhere. | [CONFIRMED FROM CODE] D's grep returns 7 hits, every one a comment asserting the absence. G.1.2 turns the discipline into audit **A22**; item 2.1 schedules it. |
| K6 | Time is `long` epoch milliseconds in every layer; `datetime` only at API and human boundaries; `Common/SSR_Time.mqh` is the only seam. | [CONFIRMED FROM CODE] Every date arithmetic finding in this audit is a *use* error, never a representation error. That is the invariant paying for itself. |

#### T.1.2 The engine's contracts with the world

| # | Invariant | Why |
|---|---|---|
| K7 | M1 is the only base timeframe; the only two write APIs are `CustomRatesUpdate` and `CustomTicksAdd`; higher timeframes are derived, never written. | [CONFIRMED FROM CODE] B.15. Phase 8 must import M1 and nothing else. |
| K8 | `SYMBOL_CHART_MODE = BID`, read back — **and** `TICK_FLAG_LAST` on every synthetic tick. Both. | [CONFIRMED FROM CODE] The belt and the braces fixed one measured failure together; neither has been shown sufficient alone. `spikes-audits-3` is that no spike *forces* it, not that the rule is wrong. |
| K9 | One wall-clock-driven clock (the group's master); streams are told an instant, never a delta; `ctrl.Pump(wall_ms)` stays out of production. | [CONFIRMED FROM CODE] This is why `MaxSkewMsc()` is zero by construction, and why `core-sync-1` is a gap-skip defect rather than a drift defect. |
| K10 | Integer speed arithmetic with a residue carry. No floating-point time. | [CONFIRMED FROM CODE] |
| K11 | The future guard has two layers — the controller clamps before asking, every provider re-checks on the way out. Do not collapse them. | [CONFIRMED FROM CODE] `core-sync-3` (generic `NextBarOpen` raises up to four guard violations per call) is noise from the second layer working, not an argument to remove it. |
| K12 | Warmup goes in as bars, the replay stretch as ticks, truncation is deletion at one M1-aligned instant in both stores, and `TruncateFrom`'s **return** is the truth. | [CONFIRMED FROM CODE] `mt5-symbol-6` (POTENTIAL_RISK) is a discarded return value — the invariant names the fix. |
| K13 | Zero bars is data, not failure. `CSSRBarWindow` records an empty range as covered; `ReadBars` returns 0, not −1. | [CONFIRMED FROM CODE] K.15. An importer that breaks this makes every weekend an error. |
| K14 | No symbol rules in the data code. Sessions from `SymbolInfoSessionQuote`, currencies from `SYMBOL_CURRENCY_BASE/PROFIT`, digits and point from the symbol. | [CONFIRMED FROM CODE] Phase 8 is exactly where a name-parsing shortcut is tempting and exactly where it is most expensive. |

#### T.1.3 UI and platform

| # | Invariant | Why |
|---|---|---|
| K15 | The only input the drawn surface may rely on is a latched object click read by `PollClicks` (`Ui/SSR_Panel.mqh:2445`), palette polled first and alone, 200 ms debounce. | [CONFIRMED FROM CODE] The panel lives on a chart the EA is not attached to. Every control in M/N/O is a button because of this, and Phase 6 must not add a control that needs a coordinate until L.4.2 is settled on a terminal. |
| K16 | *Removed, not undrawn* (invariant I7): a control that must not be clickable is deleted, never merely repainted. | [CONFIRMED FROM CODE] `ui-panel-3` (HIGH) is the cost of getting the ordering wrong, not of the rule. |
| K17 | Creation order is z-order; `Rect` writes `BORDER_FLAT`; no object may be drawn over a navigation cell (`Ui/SSR_Widgets.mqh:455-458`). | [CONFIRMED FROM CODE] `ui-panel-10` and `ui-dialogs-2` are both violations of a rule the code already states. |
| K18 | The widget property cache keeps text whole and compares with `==` rather than hashing it (`SSR_Widgets.mqh:40-45`), and `Same()` ends with `ObjectFind` (`:80-88`). | [CONFIRMED FROM CODE] E.11. A hash would make `ui-plumbing-6`'s missing tombstones a silent wrong-paint instead of a leaked slot. |
| K19 | The port refuses to do arithmetic; the sheet refuses to compute a meter; meters are clamped 0..1 at their owner. | [CONFIRMED FROM CODE] I.9. Every new number in H, M, N, R and S is filled by *asking*, never by computing at the draw site. |
| K20 | The 10 fps paint gate and the poll-before-paint ordering (`SSReplayStandalone.mq5:3057-3063`). | [CONFIRMED FROM CODE] E.11. Phase 6 reduces what a frame *does*; it must not raise the rate. |

#### T.1.4 The four refuted designs a refactor would break

[CONFIRMED FROM CODE] These carry `classification: NOT_A_BUG` in `verified.json` and **must never be
presented as defects or "cleaned up"**: `trading-analytics-11`, `ui-port-session-5`,
`ui-port-session-6` and `data-6`. Two of them describe deliberate designs the Challenge Engine
depends on (I.9). `chart-15`, `chart-16`, `core-sync-5`, `trading-exec-7`, `trading-exec-14`,
`tests-a-15`, `tests-b-13`, `ui-plumbing-7`, `ui-plumbing-10`, `ui-plumbing-12`, `ui-plumbing-16`,
`strategy-integration-report-11`, `strategy-integration-report-14`, `qa-smoke-11`, `qa-smoke-14` and
`data-10` are the rest of the 21; the same rule applies to all of them.

---

### T.2 IMPROVE

[RECOMMENDATION] *The thing exists, has the right shape, and is wrong in its arithmetic, its
coverage, its wording or its persistence.* These are the cheapest findings in the audit per unit of
user-visible damage repaired, and they are why this product is repairable: 105 of the 197 confirmed
findings are LOW, and most of them are of this kind — local, single-file, no contract touched.

| Cluster | Ids | Effort | Phase |
|---|---|---|---|
| Transport arithmetic: step off-by-one, budget that drops, bulk bars invisible to observers, per-window tick check | `core-engine-1`, `-2`, `-3`, `-4` (all CONFIRMED HIGH) | M each | 0 |
| Counters that count the wrong event: bars consumed per pump not per bar; spread stats per synthesis call; metrics | `core-engine-5`, `core-engine-9`, `core-sync-2`, `core-sync-4` | S each | 1 |
| Warmup as calendar minutes vs bar count | `core-engine-6`, `data-4` | M (one shared accessor) | 1 |
| Rewind: unconditional `RewindTo(actual)`, restore position not settings, snapshot holes | `core-engine-7`, `-8`, `core-sync-6` | S each | 1 |
| Drawdown and revenge measured in open order, not close order | `trading-analytics-3`, `-7` | M | 5 |
| Raw vs net profit disagreeing between statement, CSV and class report | `trading-analytics-4`, `-6`, `-8`, `-10` | M | 5 |
| Ambiguity, margin and wrong-side-stop at execution | `trading-exec-5`, `-6`, `-8` | M each | 2 |
| The two order paths disagreeing | `trading-exec-9`, `-10`, `-11`, `-12` | S-M | 2 |
| 63-character overruns in drawn text | `ui-panel-8`, `ui-dialogs-4`, `-5`, `ui-port-session-7`, `-8`, `chart-7` | S each, ~200 mechanical together | 6 |
| Layout arithmetic derived for the wrong frame width | `ui-panel-6`, `-7`, `ui-panel-13`, `ui-plumbing-11` | S each | 6 |
| Key-table drift: three hand-written lists and one generated one | `ui-plumbing-2`, `-3`, `-14`, `-15`, `tests-a-4`, `tests-b-1` | M (collapse to one list + audit) | 0 / 6 |
| Blind mode un-reveals itself, poisons saved chart settings, misstates what it hides | `chart-3`, `-4`, `-5` | M | 4 |
| Session-file honesty: truncate-before-write, settings block that records inputs not values | `ui-port-session-2`, `-10`, `host-expert-10` | M | 1 |
| Encoding and escaping in every export | `strategy-integration-report-8` (CONFIRMED), `trading-analytics-13`, `-14`, `ui-port-session-15` (POTENTIAL_RISK) | M together | 5 |
| The measurement layer's own defects (the largest single cluster: 31 findings) | `spikes-audits-2`, `-4` … `-31`, `qa-smoke-1` … `-15` | S-M each | 0A |
| Test assertions that are false against the shipped code | `tests-a-1` … `-17`, `tests-b-1` … `-16` | S each | 0A |

Two notes that change how this table is read. **[INFERENCE]** The `spikes-audits`, `qa-smoke` and
`tests` clusters together are 78 of the 248 findings (31 + 15 + 32) — nearly a third of the audit is
the product's own instruments being wrong. That is why they are scheduled in Phase 0A and not "later with the
polish": a red suite and a vacuous audit cannot gate anything. **[CONFIRMED FROM CODE]** The
63-character cluster is invisible to every instrument the product owns, because `Extent()` /
`CheckFrame()` sees sized objects only and excludes labels by design (`SSR_Widgets.mqh:120-128`,
invariant I10). Audit A22 (clip discipline at call sites) is the only thing that can see it, which
is why Phase 6 ends with an audit rather than beginning with one.

---

### T.3 REFACTOR

[RECOMMENDATION] *The behaviour is wanted; the structure that produces it has more than one owner,
more than one formula, or the wrong owner.* Every item here is a consolidation the code itself
already argues for in a comment — which is the test for belonging on this list rather than on T.4.

| # | Refactor | The duplication today | Effort | Phase |
|---|---|---|---|---|
| RF1 | **One rewind epoch.** `long m_epoch` on the controller, incremented on every `RestoreSnapshot`, backward `SeekTo` and `Reset`; `OnRewind(msc)` becomes `OnRewind(msc, epoch)`; every observer stamps mutations `(epoch, replay_msc)` and unwinds at or after the cut. | [CONFIRMED FROM CODE] Today each observer guesses privately, which is why `trading-exec-1` (CRITICAL, `Trading/SSR_TradingEngine.mqh:640`) drops positions without reversing their P/L, `trading-exec-2` (HIGH, `:263`) lets stops survive a rewind, and `strategy-integration-report-4` never re-seeds an RNG. `SSRSnapshot`'s four unused trading fields were reaching for this. | **L · multi-week** | 0C |
| RF2 | **One transport vocabulary.** The group owns transport semantics, the controller owns emission, shared arithmetic moves to `Common/SSR_Time.mqh` (`SSRStepTargetMsc`). | [CONFIRMED FROM CODE] The verbs exist three times (controller, group, `CSSRGroupPort`) and `StepBars`' formula is duplicated with the same off-by-one — `core-engine-2` is one defect in two files. | M | 0C |
| RF3 | **One bulk-publish channel** (`OnBulkBars`) on `Core/SSR_ITickObserver.mqh`. | [CONFIRMED FROM CODE] `core-engine-3` and `core-sync-1` are the same hole seen from two callers; `strategy-integration-report-1` (HIGH) is the third. Three findings, one method. | M | 0C |
| RF4 | **One configuration accessor set.** Every reader of a setting goes through `Cfg*()`; `CollectSettings()` reads the same table. | [CONFIRMED FROM CODE] The accessors exist at `SSReplayStandalone.mq5:206-221` with a comment explaining that thirty call sites each remembering is the failure mode — and then `OpenExtraStreams` (`:495`, `:511`) and `CollectSettings` (`:419-425`) bypass them (`host-expert-10`). | M | 1 |
| RF5 | **One settings table** — `SSRSettingRows()` with 61 rows, six consumers (P1-P3, P7). | [CONFIRMED FROM CODE] P counts seven hand-maintained lists over the same inputs. | L | 6 |
| RF6 | **One key list.** Delete the three hand-written lists, keep the generated `SSRKeyBindings()`, generate `SSRKeyHint()` from it, guard with audit A23. | [CONFIRMED FROM CODE] `ui-plumbing-2`, `-3`, `-15` and the four failing test assertions `tests-a-4`, `tests-b-1` are all one drift. | M | 6 |
| RF7 | **One panel teardown register.** A destination register + a transition latch replacing `HideSheets`, `HideSheetArea` and `HideBody`; `DrawSheet` stops deleting and recreating the sheet every frame. | [CONFIRMED FROM CODE] `ui-panel-1`, `-2`, `-3`, `-4`, `-5` are five findings in three overlapping hide paths, and E.10 ranks the first two as the dominant repaint cost. | L | 6 |
| RF8 | **One trade accessor, close-ordered.** `BuildOrder()` + two index arrays built once; `ComputeFor`, `ClosedDrawdownFor`, `Bucket` and the revenge detector all read it. | [CONFIRMED FROM CODE] R.2 and S.9: three consumers each walk the array in open order, which is the shared cause of `trading-analytics-3`, `-7` and the journal's missing `At`/`IndexOfTicket`. | M | 5 |
| RF9 | **One layout seam.** `SSR_Layout.mqh` becomes the only producer of an `x` coordinate under `Ui/`, guarded by audit A25. | [CONFIRMED FROM CODE] `ui-plumbing-5`: the file exists, states the requirement at `:14-19`, and nothing outside the QA smoke test positions anything through it. Five phases forgot it. | **L · multi-week** (~200 mechanical rewrites) | 7 |
| RF10 | **One mistake-flag owner.** Flags computed once in the statistics pass; journal, class report, review card and panel all read them. | [CONFIRMED FROM CODE] S.2.3 and R.1.2: a second formula is how a coach ends up reading two different counts of the same behaviour. | M | 5 |

---

### T.4 ADD

[RECOMMENDATION] [FUTURE FEATURE] *Nothing in the tree does this.* Each item names the seam it
attaches to, because the reason this list is affordable is that none of it needs a new layer.

| # | Addition | Attaches to | Effort | Phase |
|---|---|---|---|---|
| AD1 | **Published transport result** — `SSRTransportResult{ok, requested_msc, landed_msc, bars_emitted, bars_bulk, bars_owed, served, note≤49}` returned by every group verb instead of `bool`. | The group's existing verbs; `CSSRGroupPort` stays a thin adapter. | M | 1 |
| AD2 | **Fidelity ledger** — fidelity becomes a session property with a per-window availability check, printed by the report and readable on the panel, instead of a chip showing the last window. | F.4 / F.3.6; closes the transparency half of `core-engine-4` and `data-1`. | M | 1 |
| AD3 | **Session ticket** — session identity becomes `(symbol, start, end, seed)`, not `(seed)`. | `CSSRRandomPicker` → session file `[scenario]`. | M | 4 |
| AD4 | **Risk preview before execution** — the six gaps in G.4, on top of the existing shared `LotForRisk` call. | `SSRPortState` (nine new fields, H.7) filled by asking. | L | 2 |
| AD5 | **Challenge profiles + `[prop]` persistence + `DayIndex()`/`day_shift_min`** — a prop verdict that survives a resume and a day boundary that is declared rather than assumed. | `CSSRPropEvaluation`, `CSSRSessionManager`'s fourth slot. | **L · multi-week** | 3 |
| AD6 | **Scenario engine** — `[scenario]` section, `scenarios\*.ssrs` library, `SSRApplyDifficulty` as a projection, `CSSRPickFilter`. | `CSSRRandomPicker`, `SSRSetupValues`, the session-file writer. | **L · multi-week** | 4 |
| AD7 | **Nine journal record fields + v2 CSV (18 → 36 columns) + run folders + `index.csv`**. | `SSR_TradeTypes.mqh`, `CSSRJournal`, the session-file tail. | L | 5 |
| AD8 | **Behavioural measures** — overtrading, revenge, risk violations, oversizing, late entries, stop/target movement, repeated-loss patterns, risk consistency, session/hour/setup performance — measured, never interpreted. | `CSSRStatsEngine`'s existing pass. | **L · multi-week** | 5 |
| AD9 | **Chronological timeline + Session Review's twelve lines**. | `SSRReviewRows` 43 → 53; `CSSRReviewCard` three views through `ListRO`. | L | 5 |
| AD10 | **Six-cell rail + KEYS, PERFORMANCE, SESSION, EVAL destinations; pages, never scrolling**. | `TabCount()`, `TabName()`, `DrawRail`, `Dispatch`'s `tabN` parse. | **L · multi-week** | 6 |
| AD11 | **`ListRO`** — a read-only list widget, no per-row button, no false affordance. | Beside `CSSRWidgets::List` (`SSR_Widgets.mqh:565`). | S | 5 (pulled forward; see T.11) |
| AD12 | **RTL: `g_ssr_rtl` / `SSRIsRtl()` / `InpForceLtr`, seven `SSR_Layout.mqh` additions, `TextW()` + memo, `SSRCompose`, `SSRNum`, `ClipPx`**. | Q.3-Q.7. | **L · multi-week** | 7 |
| AD13 | **Data import: source manager, importer, normaliser, symbol mapping, quality score, cache, provenance**. | The three-provider composition (`SSR_IDataSource.mqh:9-14`), `CSSRMemoryStore` pattern. | **L · multi-week** | 8 |
| AD14 | **Audits A22-A29**, numbered in T.0's table: no-broker-order, clip discipline, one key list, engine-independent-of-UI, settings completeness, digit policy, one-object-one-direction, mirror coverage. | `tools/ssr_audit.py`, which already runs 21. | M total | 2, 6, 7 |

---

### T.5 REMOVE-ONLY-WHEN-JUSTIFIED

[RECOMMENDATION] The rule, stated once: **a removal is justified only when the thing removed is
either (a) a control that claims an action it does not perform, or (b) a second implementation of
something that now has one owner.** Everything else stays, including things that look dead.

#### T.5.1 The justified removals

| # | Remove | Justification | Replaced by | Phase |
|---|---|---|---|---|
| RM1 | `CSSRKeyCard` (`Ui/SSR_KeyCard.mqh`) | [CONFIRMED FROM CODE] It is torn down and rebuilt from scratch ten times a second while it is up (`ui-panel-12`, ~450 writes/frame), it is the one user-facing screen never translated (`ui-plumbing-1`), and after `host-expert-4` it has no discovery path. It is a modal doing a page's job. | The KEYS destination, rendered from the generated `SSRKeyBindings()` through `ListRO`. | 6 |
| RM2 | `CSSRFirstRun` (`Ui/SSR_FirstRun.mqh`, 148 lines) | [CONFIRMED FROM CODE] `ui-dialogs-14`; and `host-expert-4` proves the card can never appear in one-window mode, which is the default. Onboarding that cannot fire is not onboarding. | Three lines: no `panel.ini` → open KEYS. | 6 |
| RM3 | The per-row `pn<r>` position buttons | [CONFIRMED FROM CODE] `ui-panel-7`: the note column has 9 px for 9 characters in the rail layout. A button the user cannot read the label of is a claim. | Three columns re-derived for 245 px + a `!` note prefix. | 6 |
| RM4 | `stfid` from the status strip | [CONFIRMED FROM CODE] `ui-panel-6`: it is drawn at `x+330` in a 310 px panel — permanently outside the frame, on the candles. It is not a control being removed; it is an object that was never inside the product. | The caption chip carries fidelity; `chartsn` takes the slot. | 6 |
| RM5 | `CSSRJournal::Line` | [CONFIRMED FROM CODE] S.9: it is the single row accessor that forces every consumer to walk in open order. One owner replaces it. | `BuildIndex` / `At` / `IndexOfTicket`. | 5 |
| RM6 | The wizard's drag handler and the palette's `move` | [CONFIRMED FROM CODE] `ui-dialogs-6`: nothing enables `CHART_EVENT_MOUSE_MOVE` on the chart the setup panel lives on, so the handler can never fire; and `SetCorner` does not move the panel (`tests-b-2`). Both are (a) — a control claiming an action. | Nothing, or the claim is deleted with the control. **Gated on L.4.2** (T.6.2 P6): if mouse events *do* arrive, RM6 becomes a repair, not a removal. | 6 |

#### T.5.2 The removals a tidy-up pass would make and must not

| # | Do not remove | Because |
|---|---|---|
| DR1 | `SSR_Layout.mqh`, even though nothing in production calls it | [CONFIRMED FROM CODE] `ui-plumbing-5` is classified IMPROVEMENT, and the file states the RTL requirement at `:14-19`. Deleting it deletes the specification for Phase 7. It is unused, not wrong. |
| DR2 | `ctrl.Pump(wall_ms)` on the controller | [CONFIRMED FROM CODE] K9: it is deliberately unused in production and kept for tests. Its absence from the production path is an invariant, not dead code. |
| DR3 | The second layer of the future guard | [CONFIRMED FROM CODE] K11. `core-sync-3`'s four violations per call are the guard working. |
| DR4 | `TICK_FLAG_LAST` or the `SYMBOL_CHART_MODE` read-back | [CONFIRMED FROM CODE] K8. Neither has been shown sufficient alone, and the failure they fixed together was measured. |
| DR5 | `SSRSnapshot`'s four unused trading fields | [CONFIRMED FROM CODE] F.9(C): they are the shape RF1 needs. Delete them in Phase 0 and Phase 0 has to re-invent them. |
| DR6 | The `Ticks()`-returns-`NULL` path | [CONFIRMED FROM CODE] K.15: a CSV of daily bars genuinely has no tick provider, and `NULL` is how the engine learns that honestly. Phase 8 depends on it. |
| DR7 | The 20-stop speed ladder | [CONFIRMED FROM CODE] M.1.6 / O.3 reduce the *drawn cells* from 20 to 10 while keeping 20 stops reachable by `+`/`-`. The ladder is the model; the twenty 6.5 px targets are the defect. Removing stops is a feature regression dressed as a fix. |
| DR8 | The `%-12s` column padding and the tabular number sites | [CONFIRMED FROM CODE] Q.5.6: seven sites where it never worked. The answer is `TextW()`-measured columns, not the deletion of the intent. |
| DR9 | Any CSV column, ever — including `profit`, whose name is now wrong-looking | [CONFIRMED FROM CODE] S.14: `CSSRClassReport::ReadOne` (`Report/SSR_ClassReport.mqh:243`) reads it by name. A rename silently breaks every class report a teacher has already collected. |
| DR10 | Any MQL5 `input` | [CONFIRMED FROM CODE] `Ui/SSR_SetupPanel.mqh:16-21` promises the inputs dialog stays a complete way to configure the product. P adds surfaces; it deletes no input. |

---

### T.6 PHASE 0 — the terminal, then the two CRITICALs and the fourteen HIGHs

#### T.6.0 Why nothing precedes it

[CONFIRMED FROM CODE] Three facts, together, make Phase 0 unconditional.

1. **No line of this product has been observed running.** 31,439 lines of library code under a
   3,255-line Expert, 125 builds, 15 test scripts, 13 spikes, a 5,512-line smoke harness and 21
   static audits — all of it written, none of it run. Every "CONFIRMED" in this audit means
   *confirmed from source by adversarial review*, which is a strictly weaker claim than *observed*.
2. **The instruments that would tell you what happened are themselves defective.** 31
   `spikes-audits` findings, 32 `tests` findings and 15 `qa-smoke` findings. Six test sections
   assert facts that are false against the shipped code, so the suite is red for reasons unrelated
   to any fix. At least one audit passes vacuously. The smoke harness aborts on a condition its own
   next line repairs.
3. **Four POTENTIAL_RISK findings would change a later phase's design if they fire** — `data-2`
   (HIGH), `mt5-symbol-2`, `mt5-symbol-5`, `ui-panel-11` — and one open question (L.4.2, whether
   `CHARTEVENT_MOUSE_MOVE` reaches the panel) decides three separate Phase 6 designs.

[INFERENCE] The consequence for planning is uncomfortable and should be said plainly: **Phase 0 is
the largest phase in this roadmap and the one with the least visible output.** It ends with a product
that does what v125 was supposed to do, on one terminal, with a green suite — and no new feature.

#### T.6.1 Phase 0A — repair the instruments (before the terminal, not after)

[RECOMMENDATION] This is the one place T promotes findings above their severity, and it does so on a
single stated ground: **an instrument's defect is as severe as the worst thing it can hide.** Each
promotion below names what it hides.

| # | Item | Closes | Effort | Files | Regression risk | Proving test |
|---|---|---|---|---|---|---|
| 0A.1 | The smoke harness aborts the entire run on an unprimed M1 series — and the priming call is the very next line. | `qa-smoke-1` (MEDIUM → **blocker**: it hides *everything*, because the harness cannot run) | S | `QA/SSR_QA_Smoke.mq5:396` | low | The harness runs to completion on a freshly opened terminal where no M1 series has been touched. `SSR_QA_Smoke.mq5` prints a stage count > 0. |
| 0A.2 | The opening leftover sweep can close the chart the script itself runs on; A1/C1 delete a custom symbol with no pause after deselect. | `qa-smoke-6`, `spikes-audits-16` (both POTENTIAL_RISK → **blocker**: they can kill the run that is measuring) | S | `QA/SSR_QA_Smoke.mq5:359`, `Spike/SSR_A1_SymbolLifecycle.mq5:185`, `Services/SSReplay/Spike/SSR_C1_ServiceApiAccess.mq5` | low | new: the sweep asserts `id != ChartID()` before every `ChartClose`; A1 honours the kit's own 200 ms rule and logs the wait. |
| 0A.3 | Preflight's only tick check counts acceptance and never asks whether a bar was built; `SYMBOL_DIGITS > 0` used as an existence proxy so a whole-point instrument skips the custom-symbol section and still prints GO. | `qa-smoke-2`, `qa-smoke-3` (POTENTIAL_RISK) | S | `QA/SSR_QA_Preflight.mq5:397`, `:311` | low | Run preflight on a whole-point instrument (an index, or `XAUUSD` on a broker quoting 2 digits): it must print NO-GO or run the section, never a silent GO. |
| 0A.4 | Two audits that cannot fail: A19's language path contains `MQL5` twice so the translation-length check never runs; A20's regex matches one exact function shape and leaves two drawing surfaces unchecked. A14's helper list is incomplete. | `spikes-audits-26`, `-27`, `-28`, `-29` | S | `tools/ssr_audit.py:1429`, `:1518`, `:894`, `:425` | low | Each of A14, A19 and A20 is run against a deliberately broken fixture and **fails**, then passes. A19 must report the two `fa.txt` defects Q.1.3 names. An audit that has never failed has never been tested. |
| 0A.5 | Six test sections whose assertions are false against v125: the 8-stop ladder against 20 stops, `R` asserted as RESET when it is bound to the SL/TP lines, a click assertion on a panel that does not handle `CHARTEVENT_OBJECT_CLICK`, `SetCorner` asserted to move the panel. | `tests-a-1`, `-2`, `-3`, `-4`, `tests-b-1`, `-2` | M | `Tests/SSR_T5_Ui.mq5:89,109,174,208,221`, `Tests/SSR_T15_Ux.mq5:402,460` | low — but *the suite turns green for the first time*, which is itself the risk: it must be read, not celebrated | The 15 test scripts run with 0 failures **and** a non-zero assertion count per section. A section that passes with zero assertions is a regression (`tests-a-5`, `tests-b-4`, `tests-b-5` are exactly that shape). |
| 0A.6 | Nine spikes that cannot fail or measure the wrong thing: B1's verdict fails deterministically; B3, D1 and A3 print their PASS criterion instead of asserting it; C3 runs writer and reader sequentially in one thread; D2 re-sends identical tick timestamps so 69 of 70 injections are refused; D4 skips the series rebuild on 16 of 20 trials; C2 false-fails on every run after the first. | `spikes-audits-2`, `-3`, `-4`, `-5`, `-6`, `-7`, `-8`, `-9`, `-10`, `-11`, `-12`, `-13`, `-14`, `-15`, `-17`, `-21`, `-22`, `-23`, `-24`, `-25`, `-30`, `-31` — twenty-two findings across the whole spike suite | **L** | the 13 scripts under `Spike/`, the 2 under `Services/SSReplay/Spike/`, the 2 probes, + `Spike/SSR_SpikeKit.mqh:97, 314, 579` | medium — `SSR_BarToTicks` (`spikes-audits-1`, HIGH) is shared with the synthetic tick path, so changing it changes replay output | Every spike asserts its gate instead of printing it; each prints both the numerator and the denominator of every rate; the CSVs open with `FILE_SHARE_WRITE`. A spike that reports PASS with zero accepted ticks is a failure. |
| 0A.7 | `SSR_BarToTicks` never emits a tick at the bar's high or low unless `(n-1) % 3 == 0`. | `spikes-audits-1` (**HIGH**) | S | `Spike/SSR_SpikeKit.mqh:579`; constrain ticks-per-bar to `(n-1)%3==0`, default 10 | medium — it changes synthetic fills | `SSR_T1_CoreEngine.mq5` new section: for every ticks-per-bar from 2 to 30, assert `max(tick.bid) == bar.high` and `min(tick.bid) == bar.low`. Today it fails for 20 of 29 values. |

**Exit condition for 0A.** [RECOMMENDATION] Compile clean (`tools/ssr_compile.sh`), A1-A21 green
*and A14, A19 and A20 each having failed at least once against a fixture*, 15 test scripts green with
non-zero assertion counts, and every spike asserting rather than printing. **This is a build-environment
milestone: it needs no terminal.** It is therefore the only part of Phase 0 that can start today.

#### T.6.2 Phase 0B — the first run

[RECOMMENDATION] A demo account, one broker, one machine. [CONFIRMED FROM CODE] D's grep establishes
that no `OrderSend`, `OrderSendAsync`, `CTrade` or `PositionClose` call exists anywhere under `MQL5/`
— all 7 textual hits are comments asserting their absence. **[INFERENCE]** From that it follows that
these probes cannot place a broker order, *provided* the grep is exhaustive over every path that
could reach the trade server — which is a source argument, not a runtime observation, and it is the
one inference in this report where being wrong costs the reader money. **[RECOMMENDATION] Use a demo
account. Not "anyway" — instead.** Do not run any probe in this section on an account holding real
funds, and do not treat the grep as a substitute for that.

| # | Probe | The question it settles | What it changes if it fails |
|---|---|---|---|
| P1 | `SSR_QA_Preflight.mq5` → GO | Does the terminal permit custom symbols, `CustomTicksAdd`, the folder tree, the algo-trading flag? | Everything. This is the gate on the gate. |
| P2 | `SSR_QA_Smoke.mq5`, all stages | Do the 40-odd stages the harness already contains pass on real data? | Each failing stage is a finding this audit could not see. |
| P3 | `SSR_A1`/`A2`/`A3`, `B1`/`B2`/`B3`, `C1`/`C2`/`C3`/`C4`, `D1`-`D4` | The platform contract: symbol lifecycle, aggregation, future isolation, tick broadcast, throughput, service persistence, clock safety, seed rate, timeframe-switch cost, sustained run, rewind cost. | E.9's verdict — that **every published performance budget is invalid as measured** — is either repaired or confirmed. Phase 1's budget-defer design depends on the real per-pump cost. |
| P4 | `SSR_B4_BrokerDataAudit.mq5` (after 0A.6 repairs `spikes-audits-18`, `-19`, `-20`) | How much M1 history and how much tick history does this broker actually serve, per instrument, per depth? | **It decides whether Phase 8 (data import) is needed at all.** K.13 puts this at step 0 for exactly that reason. |
| P5 | `data-2` (POTENTIAL_RISK, HIGH) trigger probe: walk 60,000 M1 bars per instrument through `SSRDataReport::IsUsable()` and count instruments with any `invalid_ohlc` or non-positive bar. | Whether one bad broker bar can void a whole window in practice. | If it fires: `data-2` becomes the highest-priority data fix, ahead of AD2, and the per-bar-reject design replaces the per-window one. |
| P6 | **L.4.2**: log every `OnChartEvent` id received by the host, with its chart id, for 60 s while the mouse is moved over the panel and the speed groove is dragged. | Whether anything other than `CHARTEVENT_OBJECT_CLICK` arrives from the replay chart. | It decides three Phase 6 designs at once: the drag (`O.10.2`), the setup tag box's focus path (`ui-panel-11`, POTENTIAL_RISK), and whether ten drawn speed cells are a courtesy or the only usable groove. **Design the pessimistic branch either way; this probe can only make it better.** |
| P7 | Repaint cost: instrument one `Render()` and record property writes and elapsed ms, on this machine, in Compact / Standard / key-card-open. | The audit's anchor measurement (561 writes = 39.05 ms) came from a different context; E.11's 10 fps gate implies ≈ 0.41 s of repaint per wall-clock second today. | Phase 6's whole justification is this number. If it is 4 ms rather than 39, RF7 stays correct but stops being urgent. |
| P8 | `mt5-symbol-2`, `-4`, `-5`, `-6`: adopt a pre-v120 LAST-mode symbol; run teardown with the user's own chart open; kill the sink object without a handover; truncate and check the return. | Four POTENTIAL_RISK symbol-lifecycle behaviours no reading can settle. | `mt5-symbol-4` in particular can **close the user's own chart window**; if it fires it is a Phase 0C fix regardless of its MEDIUM rating. |
| P9 | Persian: load `fa.txt`, run the existing `LabelBox` overlap walker (`SSR_QA_Smoke.mq5:5308-5334`) over the whole panel, and photograph four mixed-direction strings. | Whether Arabic-script glyphs render, shape, and fit at all. | Phase 7's entire cost model. Q.10 is explicit that this existing walker is *the only mechanism in the product that can see an RTL collision*, and it was built before anyone needed it. |

**Exit condition for 0B.** [RECOMMENDATION] A written probe log: for each of P1-P9, what was observed,
and for each of the 30 POTENTIAL_RISK findings, `FIRED` / `CLEARED` / `NOT REACHED`. A finding that
was not reached stays POTENTIAL_RISK; it does not become NOT_A_BUG because one session did not
provoke it.

#### T.6.3 Phase 0C — the two CRITICALs and the fourteen HIGHs

[RECOMMENDATION] Ordered by (severity × blast radius), not by size. The two CRITICALs are
`host-expert-1` and `trading-exec-1`; the fourteen HIGHs are `core-sync-1`, `core-engine-1`, `-2`,
`-3`, `-4`, `data-1`, `mt5-symbol-1`, `ui-port-session-3`, `spikes-audits-1` (done in 0A.7),
`strategy-integration-report-1`, `trading-analytics-1`, `trading-exec-2`, `ui-panel-3` and
`ui-dialogs-1`; `data-2` is the one HIGH POTENTIAL_RISK and rides on P5.

| # | Item | Closes | Effort | Files touched | Regression risk | Proving test |
|---|---|---|---|---|---|---|
| 0C.1 | **The one-window handover, as one unit.** `OnInit`'s object sweep deletes the handover stash before it is read; pass 2 restores `setup.ini` unconditionally; a random session's seed and resolved window do not survive; auto-play and the first-run card test `one_chart_ok` instead of "am I about to hand over". | `host-expert-1` (**CRITICAL**), `host-expert-6`, `-5`, `-3`, `-4` | **L** | `SSReplayStandalone.mq5:1020, 1710, 1736, 1806, 1948` | **high** — it changes which values a run uses and which pass owns the replay | `SSR_T12_Session.mq5` new section: simulate the two-pass handover with `InpOneChart=true`, assert pass 2 reads the stash (origin symbol, seed, resolved start/end), assert a run that never opened the form does **not** inherit `setup.ini`, assert auto-play fires on the pass that owns the replay chart. Today the stash read cannot succeed. |
| 0C.2 | **The rewind epoch (RF1).** `m_epoch` on the controller; `OnRewind(msc, epoch)`; the trading engine reverses P/L, commission and swap for every position dropped at the cut and unwinds SL/TP, trailing, break-even and MAE/MFE stamped at or after it. | `trading-exec-1` (**CRITICAL**), `trading-exec-2` (HIGH), `strategy-integration-report-4` | **L · multi-week** | `Core/SSR_ITickObserver.mqh`, `Core/SSR_ReplayController.mqh:1383,1637-1707`, `Core/SSR_Snapshot.mqh`, `Trading/SSR_TradingEngine.mqh:263,640`, `Strategy/SSR_StrategyHost.mqh:141` | **high** — the balance is the account; a wrong unwind is worse than no unwind | `SSR_T9_Trading.mq5` new section: open three positions after a mark, accrue commission and swap, rewind past the mark, assert `Balance()` and `Equity()` equal the pre-entry values to 0.01 **and** that `Trades()` and every stop level equal their pre-entry state. Today the balance assertion fails by the sum of the three positions' P/L. |
| 0C.3 | **The budget defers instead of dropping.** The dead "stop short" branch becomes live; bars owed are carried to the next pump and reported. | `core-engine-1` (HIGH) | S (≈ 4 lines) + M (reporting) | `Core/SSR_ReplayController.mqh:524`, `Core/SSR_PumpBudget.mqh` | medium — a slow machine now *lags* instead of *skipping*, which is visible | `SSR_T7_Performance.mq5` new section: set a budget of 1 bar/pump, pump 100 times over a 100-bar window, assert every bar was emitted exactly once and `bars_owed` reached 0. Today bars are dropped and the count is short. |
| 0C.4 | **`OnBulkBars` (RF3).** Jump-forward and step-backward stop feeding the sink without telling observers; the group's idle gap-skip stops bulk-writing an unfinished bar. | `core-engine-3` (HIGH), `core-sync-1` (HIGH), `strategy-integration-report-1` (HIGH) | M | `Core/SSR_ITickObserver.mqh`, `Core/SSR_ReplayController.mqh:1383`, `Core/SSR_MasterClock.mqh:208`, `Strategy/SSR_MarketView.mqh:173` | medium — three observers gain a method they must implement | `SSR_T8_Navigation.mq5` new section: place a position with a stop inside the jumped span, `JumpForward`, assert the stop was evaluated. `SSR_T13_Strategy.mq5`: assert `MarketView` bar count grows in FULL_TICK fidelity. Both fail today. |
| 0C.5 | **Step arithmetic (RF2).** `SSRStepTargetMsc` in `Common/SSR_Time.mqh`; controller and group both call it. | `core-engine-2` (HIGH) | M | `Common/SSR_Time.mqh`, `Core/SSR_ReplayController.mqh:1169`, the group | low | `SSR_T8_Navigation.mq5`: from a bar boundary, `StepBars(1)` advances exactly one bar and `StepBars(n)` exactly n, for n in 1..10, from both mid-bar and bar-end starts. Four of these fail today. |
| 0C.6 | **Per-window tick availability.** Probe ticks for *the window being replayed*, not the last 24 hours; re-evaluate per window; a FULL_TICK window with zero ticks is reported, not consumed silently. | `core-engine-4` (HIGH), `data-1` (HIGH) | M | `Data/SSR_Mt5Providers.mqh:136`, `Core/SSR_ReplayController.mqh:349`, `Core/SSR_FidelityPolicy.mqh` | medium — sessions that "worked" (silently emitting nothing) now refuse or downgrade | `SSR_T2_DataEngine.mq5` new section: request FULL_TICK for a window five years back, assert the chosen fidelity is not FULL_TICK **or** that a diagnostic is raised; then assert the clock does not advance over a window that produced zero ticks. Today the clock runs to the end in silence. |
| 0C.7 | **Warmup repair after a jump is not skipped when the seed came from the cache.** | `mt5-symbol-1` (HIGH) | S | `Mt5/SSR_CustomSymbolSink.mqh:265`, `Mt5/SSR_SeedCache.mqh:176` | low | `SSR_T3_CustomSymbol.mq5`: jump twice to the same instant so the second seed hits the cache, assert `Bars()` on the warmup span is identical both times. |
| 0C.8 | **Restore refuses rather than guesses.** `CSSRSessionManager::Restore` verifies the streams reached the saved instant, and says so when they did not; saving no longer truncates the previous good session before writing the new one. | `ui-port-session-3` (HIGH), `ui-port-session-2` (MEDIUM, and it is the same code path) | M | `Session/SSR_SessionManager.mqh:350`, `Common/SSR_SessionFile.mqh:138` | medium — some resumes that "worked" now refuse | `SSR_T12_Session.mq5`: save at instant X, restore into a group whose data cannot reach X, assert the restore reports a refusal and leaves no partial state. Then: kill the write midway and assert the previous session file is still readable. Both fail today. |
| 0C.9 | **A resumed prop evaluation is not voided on startup.** `OnRestored` separated from `OnRewind`. | `trading-analytics-1` (HIGH) | M | `Core/SSR_ITickObserver.mqh`, `Trading/SSR_PropEvaluation.mqh:443` | medium | `SSR_T10_Statistics.mq5`: start a challenge, save, restore, assert the state is not `VOID` and the day ledger is intact. Today it is `VOID` on every resume. |
| 0C.10 | **Compact mode stops leaving clickable buttons on the candles.** Order `HideSheetArea` after `HideBody`, and extend the id list past `tab3`. **The minimal reorder only** — RF7's latch is Phase 6. | `ui-panel-3` (HIGH), `ui-panel-4` | S | `Ui/SSR_Panel.mqh:682, 729, 2044` | low — but it is the one Phase 0 change touching teardown ordering, and K16 is the rule it must honour | `SSR_QA_Smoke.mq5` new stage: enter Compact, assert `ObjectFind` returns −1 for every rail id `tab0..tab5` and every action-strip id. Today `tab0..tab4` are all found. |
| 0C.11 | **The wizard stops discarding what it was told.** `ReadAll()` distinguishes an absent edit box from an empty one (`Exists()` gate at `Ui/SSR_Widgets.mqh:350`). | `ui-dialogs-1` (HIGH) | S | `Ui/SSR_SetupPanel.mqh:300`, `Ui/SSR_Widgets.mqh:350` | low | `SSR_T5_Ui.mq5` new section: type a session name on step 1, advance to a step with no edit boxes, return, assert the name survives. Today it is empty, which is why no session has ever been saved with a name. |
| 0C.12 | **Keys withheld while a modal is open.** `CSSRReviewCard::OnKey` already shows the fix. | `host-expert-7` (MEDIUM → promoted: **it gates every new clickable control in M, N, O, P, R and S**) | S | `SSReplayStandalone.mq5:3167` | low | `SSR_T15_Ux.mq5`: open the Sessions dialog, send Space / Tab / arrows, assert the replay state and position count are unchanged. Today the replay runs behind the dialog. |

**Two promotions, argued.** [RECOMMENDATION] `host-expert-7` (MEDIUM) is promoted because five later
sections independently declare it a gate on every clickable control they add — M.8.2, P.11 step 5,
R.11.2, S.13 and O all say so. Fixing it in Phase 0 costs S; not fixing it blocks Phases 2, 3, 5 and
6. `ui-port-session-2` (MEDIUM) is promoted because it is in the same function as `ui-port-session-3`
(HIGH) and touching that function twice is the more expensive plan.

#### T.6.4 Phase 0 exit gate

[RECOMMENDATION] All five must hold. **No Phase 1 item starts until they do.**

1. Compile clean; A1-A21 green, with A14, A19 and A20 each having failed once against a fixture.
2. 15 test scripts green, non-zero assertions per section, plus every new section and smoke stage
   named in T.6.3.
3. `SSR_QA_Preflight` prints GO and `SSR_QA_Smoke` completes every stage on a real terminal.
4. The 0B probe log exists, with a verdict line for each of the 30 POTENTIAL_RISK findings.
5. A one-page **measured** performance note replacing E's derived figures: per-frame property
   writes, `Render()` ms, seed rate, rewind cost, timeframe-switch cost — each with its numerator
   and denominator.

#### T.6.5 Honest cost

[INFERENCE] For one developer who knows this codebase: **0A ≈ 2 weeks** (0A.6 alone is a week — it is
thirteen scripts), **0B ≈ 1 week** of terminal time plus whatever the probes uncover, **0C ≈ 5-7
weeks** of which 0C.2 (the rewind epoch) is 2-3 weeks on its own and 0C.1 is a week. **Phase 0 is
eight to ten weeks and produces no new feature.** Any plan that budgets less than this is budgeting
for the audit to be wrong.

---

### T.7 PHASE 1 — engine correctness

**Entry gate:** Phase 0 exit, all five conditions. **What this phase buys:** navigation that is
legible instead of silent, counters that mean what their labels say, and a session file that
describes the session it saved. [RECOMMENDATION] It is the last phase whose output a trader cannot
see directly, and it is the foundation every later phase reads from.

| # | Item | Closes | Effort | Files touched | Regression risk | Proving test |
|---|---|---|---|---|---|---|
| 1.1 | **`SSRTransportResult` (AD1)** — every group verb returns the struct; `CSSRGroupPort` passes it through unchanged (K19). | the silent-navigation gap (F.9 B); gives `core-engine-2`'s fix a voice | M | the group, `Ui/SSR_GroupPort.mqh`, `Ui/SSR_ReplayPort.mqh` | low — additive; `bool ok` is still there | `SSR_T8_Navigation.mq5`: ask for a mid-bar instant, assert `landed_msc` is the bar open and `note` is non-empty and ≤ 49 chars. |
| 1.2 | **Fidelity ledger (AD2)** — a session property, a per-window availability record, printed by the statement. | the transparency half of `core-engine-4` / `data-1`; `data-11` (all quality telemetry computed then discarded) | M | `Core/SSR_FidelityPolicy.mqh`, `Data/SSR_Mt5DataSource.mqh:146`, `Trading/SSR_Journal.mqh` | low | `SSR_T2_DataEngine.mq5`: replay three windows with differing tick availability, assert the ledger records three entries and the exported statement prints them. |
| 1.3 | **Warmup means one thing.** One accessor: `warmup_bars` is a bar count, and the calendar-minute span is derived from it, named separately. | `core-engine-6`, `data-4` | M | `Core/SSR_ReplayTimeline.mqh:80`, `Data/SSR_HistoryCatalog.mqh:150` | medium — Monday-morning starts now seed *more* history, so load time grows | `SSR_T6_History.mq5`: start a session at 00:05 Monday, assert the warmup span contains the requested number of *bars* and the HTF chart is non-empty. Today it seeds almost nothing. |
| 1.4 | **Counters count the right event.** `bars_used` counts completed bars once; spread statistics count bars, not synthesis calls. | `core-engine-5` (wrong by 10-1500×), `core-engine-9`, `core-sync-2`, `core-sync-4` | S each | `Core/SSR_ReplayController.mqh:472,1035`, `Core/SSR_TickSynthesizer.mqh:54`, `Core/SSR_Metrics.mqh:108` | medium — the panel's "Bars" figure changes by orders of magnitude and needs a release note | `SSR_T1_CoreEngine.mq5`: replay exactly 100 bars with 7 pumps, assert `bars_used == 100`, and assert `BarsWithRecordedSpread == 100`. |
| 1.5 | **Rewind hygiene.** Unconditional `RewindTo(actual)`; restore position, not settings; `DropFrom` stops leaving holes that halve rewind depth. | `core-engine-7`, `-8`, `core-sync-6` | S each | `Core/SSR_ReplayController.mqh:1630,1637`, `Core/SSR_SnapshotStore.mqh:140` | low | `SSR_T11_AdvancedReplay.mq5`: step back 20 times, assert the snapshot depth after the twentieth equals the depth after the first. |
| 1.6 | **`Cfg*()` for every reader (RF4)**, and `CollectSettings()` reads the same table, so a saved session's `[settings]` block records the values the session *ran with*. | `host-expert-10`, `ui-port-session-10` | M | `SSReplayStandalone.mq5:206-221, 419-425, 495, 511`, `Ui/SSR_GroupPort.mqh:949` | low | `SSR_T12_Session.mq5`: run with `InpAlsoSymbols` set and a form-set spread, assert all streams report the same spread and the saved `[settings]` block matches the run, not the inputs. |
| 1.7 | **Bulk threshold in bars; idle gap-skip judged on replay time.** | `core-engine-11`, the trigger half of `core-sync-1` | S | `Core/SSR_ReplayController.mqh:1707`, `Core/SSR_MasterClock.mqh:208` | medium — the skip now fires at different moments | `SSR_T1_CoreEngine.mq5`: at 1× speed, assert no gap-skip occurs inside a bar; at 10,000×, assert it occurs only on bar boundaries. |
| 1.8 | **Random picker draws without replacement.** | `data-3` | S (3 lines) | `Data/SSR_RandomPicker.mqh:149` | low | `SSR_T6_History.mq5`: a pool of 3 symbols where only the third has history; assert it is always chosen. Today it can be skipped entirely. |
| 1.9 | **Determinism harness.** Replay one `(symbol, start, end, seed)` twice, compare `CSSRRecordingSink::Fingerprint()`. | nothing — it *proves* Phase 0C.2 and Phase 1 did not break reproducibility | M | new test section in `SSR_T12_Session.mq5`; parts already exist (`Core/Sinks/SSR_RecordingSink.mqh:163-164`, `SSRFingerprintBars` at `Core/SSR_ReplayController.mqh:1736`) | low | The harness itself is the test: two runs, one fingerprint. [CONFIRMED FROM CODE] Every part is already in the repository and currently exercised only by T12. |

**Exit gate:** 1.9 green, twice, on the same machine and once after a terminal restart.
[INFERENCE] **Phase 1 ≈ 3-4 weeks.**

---

### T.8 PHASE 2 — trading and risk

**Entry gate:** Phase 0C.2 (the epoch) landed and 0C.12 (keys withheld) landed. [CONFIRMED FROM CODE]
G.8 is explicit that nothing above the ledger can be trusted until `trading-exec-1` is fixed,
*including the risk preview* — which is why AD4 is here and not in Phase 0.

| # | Item | Closes | Effort | Files touched | Regression risk | Proving test |
|---|---|---|---|---|---|---|
| 2.1 | **Audit A22 (no broker order) — the rule becomes a build failure**, not a comment. | makes K5 enforceable; closes `new-5` (D.2) | S | `tools/ssr_audit.py` | low | Add `OrderSend(` to a scratch file under `MQL5/`; the audit must fail. Then remove it. |
| 2.2 | **Three ways the engine produces a loss the trader did not choose:** the ambiguity test uses the whole bar range so a target hit after a mid-bar entry books as a stop; no margin check on entry when margin is modelled; `BreakEven`/`Modify` accept a stop on the wrong side and the engine then *closes* the trade. | `trading-exec-5`, `-6`, `-8` (all MEDIUM) | M each | `Trading/SSR_TradingEngine.mqh:164, 741, 920` | medium — fills and rejections both change; existing sessions will not reproduce | `SSR_T9_Trading.mq5`, three sections: (a) enter mid-bar above the bar's low with a stop below it, assert the target books as a win; (b) order 50 lots on a 10,000 balance with margin on, assert rejection *before* any charge; (c) move a long's stop above market, assert the modify is **rejected** and the position is still open. |
| 2.3 | **The two order paths agree.** Market and line-drag entries share one validation, one lot-size call, one rounding rule. | `trading-exec-9`, `-10`, `-11`, `-12` | M | `Trading/SSR_TradingEngine.mqh:345, 714, 999`, `Trading/SSR_TradeTypes.mqh:120` | medium | `SSR_T9_Trading.mq5`: the same intent expressed both ways produces byte-identical `SSRTrade` records except for the entry source field. |
| 2.4 | **`Risk().Configure` after `Load`** — the test-harness ordering defect that makes every existing risk assertion measure the unknown-symbol fallback. | `tests-b-6`, `tests-b-11`, `tests-b-8`, `tests-b-12` | S | `Tests/SSR_T9_Trading.mq5:79, 112, 124, 368, 433` | low — **but every risk number in the suite changes**, which is the point | The suite's risk sections assert against the configured spec. `SSR_T10_Statistics.mq5:65-67` already documents the correct order. |
| 2.5 | **The risk preview (AD4).** Nine `SSRPortState` fields (H.7) filled by asking; `risk_why` gives `LotForRisk`'s refusals one **named field** instead of the three ad-hoc surfaces they reach today (`new-7` corrects an earlier claim that they reached none: `Ui/SSR_Panel.mqh:1624-1626`, `:1945-1947`, `:2199-2200` all draw `TradeError()`, but the `vol_max` cap path never populates it); the `(sim)` wording rule (G.3). | `new-1` … `new-4` (G.4/G.6's gaps); `new-7`, `new-8`, `new-10`, `new-11` (H.3) — all **D.2 register ids, not `verified.json` findings, so none has been through the refuter process** | **L** | `Trading/SSR_RiskEngine.mqh`, `Ui/SSR_ReplayPort.mqh:233-236`, `Ui/SSR_GroupPort.mqh`, `Ui/SSR_Panel.mqh` (TRADE sheet) | medium — a new refusal path in front of the order button | `SSR_T9_Trading.mq5`: for each refusal reason, assert `risk_rule` carries the **rule id** (not the string) and `risk_why` is non-empty and ≤ 63 chars. Plus `SSR_QA_Smoke.mq5`: `CheckFrame()` passes on the TRADE sheet at `SSR_LAYOUT_RAIL` with every field populated. |
| 2.6 | **A risk-rule editor that respects the click-only surface.** Extend the existing `StepRisk` ladder (`Ui/SSR_Panel.mqh:2146`) rather than adding a field; note it snaps any off-ladder value to 0.50, so a 0.75 typed in the form is silently rewritten by the first `+` click. | H.3's UI half — no `verified.json` id and no D.2 id: this one is a design gap, not a defect claim | M | `Ui/SSR_Panel.mqh:2146-2150` | low | `SSR_T5_Ui.mq5`: set 0.75 in the form, click `+`, assert the result is the next ladder stop **above** 0.75, not 1.00-from-0.50. |
| 2.7 | **Audit A25: no file under `Ui/` includes `SSR_RiskEngine.mqh`.** The mechanical form of "the engine stays independent of the UI". | keeps K19 true | S | `tools/ssr_audit.py` | low | A25 fails against a deliberate include, then passes. |

[INFERENCE] **Phase 2 ≈ 4-5 weeks**, of which 2.5 is half.

---

### T.9 PHASE 3 — challenge engine

**Entry gate:** 0C.9 (`OnRestored`) and 0C.8 (restore refuses rather than guesses) landed.
[CONFIRMED FROM CODE] I.8 states the internal ordering as non-optional; T reproduces it and adds the
effort and the proving test.

| # | Item | Closes | Effort | Files touched | Regression risk | Proving test |
|---|---|---|---|---|---|---|
| 3.1 | **`[prop]` persistence + `CSSRSessionManager`'s fourth slot.** Refuse, do not guess, when `ui-port-session-3`'s skew warning fires. | `trading-analytics-2` | M | `Trading/SSR_PropEvaluation.mqh:366`, `Session/SSR_SessionManager.mqh` | medium — a resumed challenge now carries state that must be right | `SSR_T10_Statistics.mq5`: mid-challenge save/restore, assert every rule's base (equity peak, day start, trading days) is the saved one, not current equity. |
| 3.2 | **All eight rule fields through `Cfg*()`, and validated on the keyboard path.** | `ui-dialogs-9`, the rest of RF4 | M | `SSReplayStandalone.mq5:1192-1194`, `Ui/SSR_SetupPanel.mqh:1194` | low | `SSR_T5_Ui.mq5`: set all eight in the form, assert the evaluation reads all eight; type a negative into each, assert each is clamped with a visible reason. |
| 3.3 | **`DayIndex()` + `day_shift_min` + an honest warning** that MQL5 has no timezone database and only a declared offset is honest. | the boundary half of `trading-analytics-5` | M | `Trading/SSR_PropEvaluation.mqh:383`, `Common/SSR_Time.mqh` | medium — which day a trade belongs to changes | `SSR_T10_Statistics.mq5`: a pump straddling midnight, a weekend gap, and a ±420-minute shift; assert the day index is stable and the day count matches a hand-derived expectation. |
| 3.4 | **Day ledger + `SSR_DAY_COUNTS_ON_OPEN\|CLOSE`.** | `trading-analytics-5` | M | `Trading/SSR_PropEvaluation.mqh` | medium | Same section: a trade opened Monday and closed Tuesday counts once, under the declared policy, and the policy is printed. |
| 3.5 | **`Judge()` on tick boundaries; `OnClock` after `JumpForward`; `SSR_PROP_UNJUDGED`.** | `trading-analytics-12` | M | `Trading/SSR_PropEvaluation.mqh:358`, `Core/SSR_ReplayController.mqh` | medium | `SSR_T10_Statistics.mq5`: jump past a deadline, assert the state is `UNJUDGED` and not silently passing. |
| 3.6 | **Challenge profiles (I.3) + the rule set (I.4)**, with the pre-trade gates in `CSSRGroupPort::Market` / `OpenFromLines` — **after** `ui-panel-5` (slot 12/17 `setuprow` collision) is fixed, because a refusal the trader cannot read is worse than no rule. | I.4's Family D/E; folds in `trading-exec-6` | **L · multi-week** | `Trading/SSR_PropEvaluation.mqh`, `Ui/SSR_GroupPort.mqh:715, 1067`, `Ui/SSR_Panel.mqh:1432`, `Ui/SSR_SetupPanel.mqh` | medium | `SSR_T9_Trading.mq5` one section per rule, asserting the **rule id** rather than the string so reasons can be reworded. |
| 3.7 | **A smoke stage that builds the panel with a real prop port.** | `qa-smoke-13` — [CONFIRMED FROM CODE] stage 18's NULL port (`QA/SSR_QA_Smoke.mq5:1783`) makes the fifth tab unreachable, so the current suite cannot see the Prop sheet at all | M | `QA/SSR_QA_Smoke.mq5` | low | The stage draws EVAL and `CheckFrame()` passes. Today the sheet is never drawn by any test. |
| 3.8 | **Fix A14's helper list** before any new drawn row. | `spikes-audits-28` | S | `tools/ssr_audit.py:894` | low | A14 fails against a drawn row that bypasses a helper. |

[INFERENCE] **Phase 3 ≈ 4 weeks.** 3.6 is the multi-week item; 3.1-3.5 are a dependency chain and
cannot be parallelised.

---

### T.10 PHASE 4 — scenario engine

**Entry gate:** 0C.1 (the handover carries seed and resolved window) and 1.8 (draw without
replacement) landed. [CONFIRMED FROM CODE] J.6 item 1: without the handover fix, Random Replay is
broken on the default configuration (`InpOneChart = true`, `SSReplayStandalone.mq5:130`) and no
scenario built on it can work.

| # | Item | Closes | Effort | Files touched | Regression risk | Proving test |
|---|---|---|---|---|---|---|
| 4.1 | **Blind mode, repaired.** The reveal is undone within ~200 ms because `RestoreAll` leaves the policy on and the host re-applies on `IsOn()`; the record of the user's original chart settings does not survive a reinit and the next Apply saves the blinded state as the original; Blind FULL claims the price level is hidden while the entry-line label and the deal buttons print the absolute price. | `chart-3`, `-4`, `-5` (all MEDIUM) | M | `Chart/SSR_BlindMode.mqh:152, 203, 243` | medium — it touches the user's own chart settings, which is the one place a bug is not confined to the product | `SSR_T4_ChartIntegration.mq5`: turn blind on, reveal, pump 10 timer beats, assert the price scale is still visible; reinit, assert the *original* settings restore; assert no drawn object contains an absolute price while Blind FULL is on. |
| 4.2 | **Blind and random stop being mutually exclusive.** `ApplyMode(3)` must not clear `blind`. | J.6 item 14 | S | `Ui/SSR_Panel.mqh` mode chips | low | `SSR_T5_Ui.mq5`: select random, assert blind survives. |
| 4.3 | **The session ticket (AD3).** Persist the *resolved* `(symbol, start_msc, end_msc, seed)`; replay loads the triple and skips `Pick()` entirely. | J.6 item 8; makes reproduction independent of how much history the broker happened to hold | M | `Data/SSR_RandomPicker.mqh`, `Common/SSR_SessionFile.mqh`, `Core/SSR_ReplayController.mqh` | medium | 1.9's determinism harness, run across a terminal restart *and* after a history download: the fingerprints must match. |
| 4.4 | **`SSRSetupValues` extended** with `symbol`, `start_msc`, `end_msc`, `pool` (separate from `also_symbols`), `max_trades`, `difficulty`, `news_policy`, `session_band` — `Save`/`Restore` extended in the same place, per the existing one-struct rule. | J.6 item 9 | M | `Ui/SSR_SetupPanel.mqh:1211-1260` | low | `SSR_T12_Session.mq5`: every new field round-trips through save/restore. |
| 4.5 | **`scenarios\*.ssrs` library + picker** modelled on `CSSRSessionManager::List/Peek/Path` and `presets.ini` — **after** `ui-dialogs-15` (`MenuClear` caps at 32 items while the backing file is unbounded, so a long library orphans buttons on the chart). | J.6 item 10 | **L · multi-week** | new `Session/` file, `Ui/SSR_SetupPanel.mqh:611`, `Ui/SSR_SessionDialog.mqh` | medium | `SSR_QA_Smoke.mq5`: a 40-entry library; assert the menu draws ≤ 32 rows, pages the rest, and leaves zero orphan objects after close (`ObjectsTotal` returns to its pre-open value). |
| 4.6 | **`SSRApplyDifficulty` as a projection; `CSSRPickFilter` for session / volatility / news / regime.** No fifth source of truth (J.5.3). | J.6 item 11 | **L** | `Data/SSR_RandomPicker.mqh`, new filter file | medium | `SSR_T6_History.mq5`: each filter, asserted against a hand-built memory store where the expected pick is known. |
| 4.7 | **Show the seed on the panel, unsigned.** | J.4 | S | `Ui/SSR_Panel.mqh` SESSION sheet (lands with Phase 6) | low | `SSR_T5_Ui.mq5`: the seed row renders and is ≤ 63 chars. |

[INFERENCE] **Phase 4 ≈ 4-5 weeks.** 4.5 and 4.6 are where the "training product" claim is actually
built, and they are the first items in this roadmap that are features rather than repairs.

---

### T.11 PHASE 5 — journal and coaching

**Entry gate:** Phase 2 (the ledger is correct, so a recorded trade is a true trade) and 0C.12.
[RECOMMENDATION] **`ListRO` (AD11) is pulled forward to the head of this phase.** R.11.2 and S.13
both gate on it and both name section M as its home — but it is a single widget method beside
`CSSRWidgets::List` (`Ui/SSR_Widgets.mqh:565`), it needs no rail change and no navigation change, and
three later items need it. Building it here is the cheapest way to unblock two phases.

| # | Item | Closes | Effort | Files touched | Regression risk | Proving test |
|---|---|---|---|---|---|---|
| 5.0 | **`ListRO`** — a read-only list, no per-row button, no false affordance. | `ui-dialogs-16` on every surface that adopts it | S | `Ui/SSR_Widgets.mqh:565` | low | `SSR_QA_Smoke.mq5`: draw a 12-row `ListRO`, assert zero `OBJ_BUTTON` objects were created. |
| 5.1 | **`BuildOrder()` + close-ordered index (RF8)**, and the closed-only drawdown and revenge detector re-pointed at it. **Released with a note:** it changes `max_drawdown_closed` and `revenge_trades` on existing sessions. | `trading-analytics-3`, `-7` | M | `Trading/SSR_Statistics.mqh:497, 703`, `Trading/SSR_Journal.mqh` | **medium** — two published numbers move | `SSR_T10_Statistics.mq5`: a hand-built trade set where open order and close order differ, with the correct drawdown computed by hand. Today it produces the open-order answer. |
| 5.2 | **Raw vs net, settled once.** A `net` column, a `# result_basis` header key, the class report preferring `net`, and the empty-not-zero law (`profit_factor`, `# losses`, KPI rows print `-`, never 0). | `trading-analytics-4`, `-6`, `-8`, `-10` | M | `Trading/SSR_Journal.mqh:51, 82, 254, 304, 1142`, `Report/SSR_ClassReport.mqh:243` | medium — the statement and the CSV stop disagreeing, so one of them changes | `SSR_T10_Statistics.mq5`: a non-zero-commission run; assert statement, CSV and class report report the same per-trade result, and that an undefined profit factor prints `-`. |
| 5.3 | **Encoding and escaping, everywhere at once.** RFC-4180 quoting in the journal **and** the class report (they are one change); UTF-8 via `FILE_BIN` + `CP_UTF8` for both exports and the class report; the session file's non-ASCII trade tag. | `strategy-integration-report-8` (CONFIRMED), `trading-analytics-13`, `-14`, `ui-port-session-15` (POTENTIAL_RISK) | M | `Trading/SSR_Journal.mqh:51, 254`, `Report/SSR_ClassReport.mqh:439`, `Common/SSR_SessionFile.mqh:212` | medium — **encoding is a terminal question**; verify by opening the CSV in Excel on the target machine | `SSR_T10_Statistics.mq5`: a session name and a trade tag containing `"`, `,`, a newline and a Persian word; assert the round trip is byte-exact and the class report parses it. |
| 5.4 | **Nine record fields + the v2 CSV (AD7):** 18 → 36 columns, `# schema,2`, run folders, `run.ini`, `index.csv`. Slippage derived, session from a declared table, mistake flags with one owner (RF10). | S.2-S.5 | **L** | `Trading/SSR_TradeTypes.mqh`, `Trading/SSR_Journal.mqh`, `Common/SSR_SessionFile.mqh`, `Trading/SSR_Statistics.mqh` | medium — three callers change their naming; a v1 reader must still open a v1 file | `SSR_T10_Statistics.mq5`: write v2, assert 36 columns and the header block; then assert `CSSRClassReport::ReadOne` still parses a v1 file from disk (a fixture committed for the purpose). |
| 5.5 | **Behavioural measures (AD8)** — the ten measures of R.4, each satisfying R.1.2's three-part contract: a definition, a sample count, and a re-derivable basis. They land **in the exported statement first**, which has the most room and the least layout risk. | R.4; `trading-analytics-9`'s label honesty | **L · multi-week** | `Trading/SSR_Statistics.mqh` (new struct block + counting in `ComputeFor`) | medium — a measure that is wrong in a way only a terminal shows | For each measure: `SSR_T10_Statistics.mq5` asserts the count against a hand-built trade set, **and** R.11.2's manual gate — one real session, every count re-derived by hand from the exported CSV. |
| 5.6 | **Timeline + the Session Review's twelve lines (AD9).** `SSRReviewRows` 43 → 53; `SSRTimelineRow`; shared predicates so the count and the marks cannot disagree; observations shortened, clipped, capped and routed through `T()`. | `ui-dialogs-4` (two observation sentences exceed 63 chars for every possible value) | **L** | `Ui/SSR_Review.mqh:205`, `Ui/SSR_ReviewCard.mqh:162`, `Trading/SSR_Statistics.mqh` | medium — a view switch that leaves the previous view's labels on the chart is invariant I7 being broken | `SSR_QA_Smoke.mq5`: draw all three card views in sequence, assert after each switch that no object from the previous view remains; assert every row is ≤ 63 chars in **both** languages. |
| 5.7 | **Screenshot coverage:** the pending-order *before* picture, the two-pass collapse around `ChartScreenShot`, and the acknowledgement that screenshots are taken on the chart the panel is drawn on. | `trading-analytics-15` (POTENTIAL_RISK) | M | `Trading/SSR_ShotBook.mqh:164` | medium — **unverifiable without a terminal**; degrade to today's behaviour on failure | Manual, on a terminal: three captures per trade, each opened and looked at. There is no automated test for whether a picture contains what it should. |
| 5.8 | **`BuildIndex`/`At`/`IndexOfTicket`; delete `Line` (RM5).** | S.9's three findings | M | `Trading/SSR_Journal.mqh` | medium-high — published numbers move again (S.9.2) | `SSR_T10_Statistics.mq5`: `At(i)` and `IndexOfTicket(t)` agree with a linear scan for 500 trades, and `ComputeFor` produces the same numbers through the index as through the old walk *except* where 5.1 intentionally changed them. |

[INFERENCE] **Phase 5 ≈ 6-8 weeks.** It is the largest phase after Phase 0, and 5.5 is the item most
likely to be underestimated: ten measures, each needing a definition a coach will read aloud, a
sample count, and a hand-checked verification run.

---

### T.12 PHASE 6 — UI information architecture

**Entry gate:** 0C.10 (compact mode), 0C.11 (the wizard keeps what it is told), 0C.12 (keys withheld
while a modal is open), **P6 from Phase 0B answered** (whether mouse events reach the panel), and P7
(the measured repaint cost). [CONFIRMED FROM CODE] M.8.2, N.11, O.13, P.11, R.11.2 and S.13 all
independently name the same first change and the same two outside gates; T is scheduling their
agreement, not adding to it.

**The internal order is not negotiable** and is M.8.2's, restated with effort and tests.

| # | Item | Closes | Effort | Files touched | Regression risk | Proving test |
|---|---|---|---|---|---|---|
| 6.1 | **The transition latch + the destination register + `order_why`'s own object id — as ONE change (RF7).** `HideSheets`/`HideBody` fire on change only; one teardown id list per destination; `DrawSheet` stops deleting and recreating the sheet every frame. | `ui-panel-1`, `-2`, `-5`; the dominant repaint cost (E.10 ranks 1 and 2) | **L** | `Ui/SSR_Panel.mqh:682, 729, 1270, 1284, 1432, 2042, 2077` | **high** — [CONFIRMED FROM CODE] M.8.1 warns it inverts *when* teardown happens; the failure mode is a stale object from the previous destination left permanently on the chart, and `order_why`'s id cannot be deferred past it without turning a one-frame defect into a permanent one | `SSR_QA_Smoke.mq5` new stage: visit all six destinations in a cycle twice, after each transition assert `ObjectsTotal` on the replay chart returns to the destination's expected count and no id from any other destination is findable. Plus the measured frame cost from P7 must fall — N.11.2 predicts ~586 writes → ~95 finds + ~30 writes. |
| 6.2 | **`UpgradeSweep()`** — one-shot removal of the nine v124 ids and `spdseg10..19`, replacing nine wasted `Remove` calls per frame. | orphan speed cells on upgrade | S | `Ui/SSR_Panel.mqh:932-934, 1189-1191, 1241-1243` | low | `SSR_QA_Smoke.mq5`: create the nine legacy ids by hand, build the panel, assert all nine are gone and that a second build performs zero `Remove`. |
| 6.3 | **Arithmetic and clipping:** status strip re-columned and `stfid` deleted (RM4); position-row columns re-derived for 245 px with a `!` note prefix (RM3); ten drawn speed cells over twenty stops (DR7); character budgets + `Clip()` at every sheet site. | `ui-panel-6`, `-7`, `-8`, `-13`, `ui-plumbing-11`, `chart-7`, `ui-dialogs-5`, `ui-port-session-7`, `-8` | M + ~200 mechanical | `Ui/SSR_Panel.mqh:887, 1045, 1091, 1576, 1915-2035`, `Ui/SSR_Theme.mqh:437`, `Chart/SSR_LeakGuard.mqh:93`, `Session/SSR_SessionManager.mqh:89, 238`, `Ui/SSR_RangeDialog.mqh:233` | low | **Audit A23** (clip discipline at call sites) — it is the only instrument that can see this class at all, because `Extent()`/`CheckFrame()` excludes labels by design (`Ui/SSR_Widgets.mqh:120-128`). Plus `CheckFrame()` passing on every sheet at 310 px. |
| 6.4 | **The rail grows to six; KEYS exists; `CSSRKeyCard` and `CSSRFirstRun` die (RM1, RM2); `Ctrl+K` enters the key table; `SSRKeyHint()` is generated (RF6).** | `ui-panel-12`, `ui-plumbing-1`, `-2`, `-3`, `-14`, `-15`, `ui-dialogs-14`, `ui-dialogs-16`, `host-expert-4` | **L** | `Ui/SSR_Panel.mqh:1103-1121, 1209-1225`, `Ui/SSR_Theme.mqh:542-546`, `Ui/SSR_Keys.mqh:71, 271`, `Ui/SSR_Strings.mqh:393, 500`, delete `Ui/SSR_KeyCard.mqh` + `Ui/SSR_FirstRun.mqh` | medium — this is the point of no return for the `panel.ini` contract; an old file selects the wrong destination once | **Audit A24:** the key table is the only key list in the tree (grep finds no second hand-written one). Plus `SSR_T15_Ux.mq5`: every binding in `SSRKeyBindings()` appears on the KEYS page and in `SSRKeyHint()`, and `Ctrl+K` is in the table. |
| 6.5 | **Rail condition marks** — a cell raises its hand without navigating. **After 6.1, never before.** | notice-without-navigation (M.3.4) | S | `Ui/SSR_Panel.mqh:1108` | low | `SSR_QA_Smoke.mq5`: force an EVAL breach, assert the rail cell's mark appears and that selection contrast is still legible on the marked cell. |
| 6.6 | **The four destinations that add information:** PERFORMANCE (curated page + pager + throttled statistics), TRADE (verdict line + `DailyRoomAfter()` + one wire field), SESSION (rehome + nine orphan wire fields + Jump/Sessions/Mark + Save/Resume — **two implemented verbs that have never had a caller**), POSITIONS (Open/Closed toggle + `WantClosed`). | L.2.2, L.2.3, nine of eleven orphan wire fields, the unreachable individual trade | **L · multi-week** | `Ui/SSR_Panel.mqh:1346, 1509, 1671, 1749, 1877`, `Ui/SSR_GroupPort.mqh`, `Ui/SSR_ReplayPort.mqh`, `Trading/SSR_PropEvaluation.mqh:295` | medium — SESSION exercises `Save`/`Resume` from a UI for the first time ever, over the code 0C.8 repaired | `SSR_QA_Smoke.mq5` per destination: `CheckFrame()` passes, every wire field has a reader, and no field is drawn that the port does not fill. Plus a round trip: Save from SESSION, restart, Resume from SESSION, assert the instant matches. |
| 6.7 | **The settings table and the form rewrite (RF5, P1-P11):** `SSRSettingRows()` with 61 rows; `ReadAll()` gated on `Exists()` with clamps from the spec; `Save`/`Restore` walk the table; `[run] token`; the render loop; 61 catalogue entries + 61 `fa.txt` rows. | `ui-dialogs-2`, `-3`, `-7`, `-8`, `-9`, `-13`, `-15`, `host-expert-6`'s remaining branch, `host-expert-15` (POTENTIAL_RISK) | **L · multi-week** | new `Ui/SSR_Settings.mqh`, `Ui/SSR_SetupPanel.mqh:289, 300, 548, 611, 955, 1061, 1194, 1211-1260`, `Ui/SSR_RangeDialog.mqh:139, 233, 268`, `Ui/SSR_Strings.mqh` | medium — **P4's `[run] token` changes which values a run uses**, and it needs a release note: a user who configured once through the form and then ran with `InpPickStart=false` stops silently inheriting those settings | **Audit A26:** every stored key has a spec row, a `Cfg*()` accessor and a catalogue string. Plus `SSR_T5_Ui.mq5`: all 61 rows round-trip; the range dialog's two erased messages survive `Recompute()`; an open dropdown does not survive a step change. |
| 6.8 | **The journal destination (S.13 items 14-15)** — list + detail, rail 6 → 7, `jrn_*` wire block, `WantTrade`, `trade-<n>.html`. | the unreachable individual trade, from the journal side | **L** | `Ui/SSR_Panel.mqh`, `Ui/SSR_GroupPort.mqh`, `Trading/SSR_Journal.mqh` | medium | `SSR_QA_Smoke.mq5`: the detail screen draws, `CheckFrame()` passes, and the `OBJ_EDIT` note box does not steal `Tab` (which opens a virtual trade). |
| 6.9 | **Restore a detached-chart signal** — [CONFIRMED FROM CODE] L.4.3: it is the only v125 removal that cost information. Secondary-symbol charts also get `Redraw()`. | `chart-10`, `chart-2` | M | `Chart/SSR_ChartManager.mqh:464, 574`, `Ui/SSR_Panel.mqh` status strip | low | `SSR_T4_ChartIntegration.mq5`: detach a chart, assert `charts_detached` is non-zero and the status strip shows it; assert a secondary chart's last bar advances. |
| 6.10 | **Leaked chart windows on re-init; bookmark lines that survive the session; planning lines that may paint over the panel.** | `host-expert-8`, `chart-6`, `chart-11` (POTENTIAL_RISK) | M | `SSReplayStandalone.mq5:2203`, `Chart/SSR_ChartManager.mqh:170`, `Chart/SSR_TradeLines.mqh:110` | medium — teardown paths, and `mt5-symbol-4` (POTENTIAL_RISK) means teardown can close the user's own window | `SSR_T3_CustomSymbol.mq5` / `SSR_Z_Cleanup.mq5`: re-init five times, assert the chart count returns to baseline each time and zero `SSR_`-prefixed objects remain on the user's own chart. |

[INFERENCE] **Phase 6 ≈ 10-12 weeks.** It is the phase a stakeholder will most want to start first
and the phase with the most prerequisites. 6.1 alone is a week of work and the highest-risk single
change in the roadmap; 6.6 and 6.7 are multi-week each.

---

### T.13 PHASE 7 — RTL

**Entry gate:** Phase 6's 6.1 (the latch), 6.3 (budgets and clipping) and 6.4 (the five English
surfaces reached by `T()`), plus P9 from Phase 0B — a photograph of Persian glyphs on a real
terminal. [CONFIRMED FROM CODE] Q.9 makes the gate explicit: five surfaces are still English and one
audit is silent; mirroring before they are closed mirrors an English panel.

| # | Item | Closes | Effort | Files touched | Regression risk | Proving test |
|---|---|---|---|---|---|---|
| 7.1 | **The gates:** the key card body, the toast, the reset confirmation, the review observations and the chart-line captions routed through `T()`; **A19 fixed** (its path contains `MQL5` twice, so the translation-length check has never run) and widened past `/Ui/`; the two `fa.txt` digit defects corrected. | `ui-plumbing-1`, `chart-12`, `spikes-audits-26` | M | `Ui/SSR_Strings.mqh`, `Chart/SSR_TradeLines.mqh:134`, `Ui/SSR_Review.mqh`, `tools/ssr_audit.py:1429`, `MQL5/Files/SSReplay/lang/fa.txt:178, 215` | low | A19 runs, fails against the two `fa.txt` rows, then passes. **An audit that has never failed has never been tested.** |
| 7.2 | **Direction, once:** `g_ssr_rtl`, `SSRIsRtl()`, `SSRLangIsRtl()`, `InpForceLtr`. | Q.2 | S | `Ui/SSR_Strings.mqh`, `SSReplayStandalone.mq5` | low | `SSR_T5_Ui.mq5`: `SSRIsRtl()` follows the loaded language and `InpForceLtr` overrides it. |
| 7.3 | **`SSR_Layout.mqh` earns its keep (RF9, DR1):** the seven additions of Q.3.2, `SSRLead`/`SSRTrail`/`SSRLeadEdge`/`SSRTrailEdge`/`SSRCentre`/`SSRColX`. | `ui-plumbing-5` | M | `Ui/SSR_Layout.mqh:14-19, 67` | low — nothing calls it yet | `SSR_QA_Smoke.mq5`: each helper asserted in both directions against hand-computed coordinates. |
| 7.4 | **`TextW()` + a 256-slot memo; `Extent()` gains labels; `FrameOverflowLeft()`.** [CONFIRMED FROM CODE] This retires invariant I10 — it is the change that lets any instrument see a label overflow at all. | the blind spot behind the whole 63-char cluster | M | `Ui/SSR_Widgets.mqh:103, 120-128` | **medium** — a graphics call (`TextGetSize`) enters the paint path; the memo is what makes it affordable, and P7's measurement is what proves it | `SSR_QA_Smoke.mq5`: run the existing `LabelBox` overlap walker (`:5308-5334`) over the whole panel and assert zero overlapping pairs — the walker already exists and already names the worst pair. |
| 7.5 | **Label/Text alignment in the cache key.** [CONFIRMED FROM CODE] Q.4.1: the anchor must enter the fingerprint or the cache returns a label at the wrong anchor. **One edit, or none.** | a latent wrong-paint in `ui-plumbing-6`'s neighbourhood | S | `Ui/SSR_Widgets.mqh` | **medium — a cache-key change** | `SSR_T5_Ui.mq5`: draw the same text at two anchors in successive frames, assert both render at their own anchor. |
| 7.6 | **The mirror, in one change, all seven bands.** [CONFIRMED FROM CODE] Q.11: a half-converted panel is the failure `localization.md` already documented once. | Q.5 | **L · multi-week** (~200 mechanical `x` rewrites) | every draw site in `Ui/SSR_Panel.mqh` | **high — it is every draw site** | **Audit A29** (no bare `+` on an integer literal in an `x` argument without an `// unmirrored:` justification), plus smoke stage 41's overlap pass run **twice** — once LTR, once with `SSRIsRtl()` forced. |
| 7.7 | **Mixed runs:** Shape A (split 30 catalogue entries into label + value), `SSRCompose`/`SSRComposeFormat` for the six live Shape-B strings, `ClipPx`, `SSRNum`'s per-role digit policy, measured decimal alignment. | Q.6, Q.7; and it improves the **English** panel's tabular alignment | **L** | `Ui/SSR_Strings.mqh`, `Ui/SSR_Widgets.mqh`, `MQL5/Files/SSReplay/lang/*.txt` | low (isolated) | **Audits A27 (digit policy) and A28 (one object, one direction)**. A28 would report 39 today and 9 after the Shape-A split. |
| 7.8 | **The terminal probe, then the switch.** Four mixed-direction strings photographed; the default corner moved to the trailing edge in RTL. | Q.10 | M | `Ui/SSR_Panel.mqh` | low | Manual and honest: the stage reports glyph coverage, the round trip, the 63-char budget and the overlap count in both directions. **It must not claim that RTL "works"** — shaping is a judgement a person makes by looking. |

[INFERENCE] **Phase 7 ≈ 6-8 weeks**, and steps 7.1-7.5 and 7.7 all improve the English build, so
the phase ships something useful at four separate points before the mirror is switched on. 7.6 is
reversible by one input (`InpForceLtr`), which is the only reason it is affordable at all.

---

### T.14 PHASE 8 — data import

**Entry gate:** **P4 from Phase 0B** — the broker data audit. [CONFIRMED FROM CODE] K.13 puts this at
step 0 with the note that *its result decides whether import is needed at all*. If the target broker
serves adequate M1 and tick history for the instruments the product teaches, Phase 8 is a
[FUTURE FEATURE] and not a phase. Also gated on `data-2` (POTENTIAL_RISK, HIGH; probe P5), because import amplifies it: an
imported file is far more likely to contain a bar with `high < low` than a broker feed is.

| # | Item | Closes | Effort | Files touched | Regression risk | Proving test |
|---|---|---|---|---|---|---|
| 8.1 | **Wire the data-source indicator** — `Mode()` → `SetDataMode` → vitals → chip. [CONFIRMED FROM CODE] K.11: three dead links, one change. | the provenance gap | S | `Data/SSR_Mt5DataSource.mqh:146`, `Ui/SSR_GroupPort.mqh`, `Ui/SSR_Panel.mqh` | low | `SSR_QA_Smoke.mq5`: the chip reads BROKER for a broker source and IMPORT for a memory store. |
| 8.2 | **Surface the existing quality telemetry.** | `data-11` (computed, then discarded) | S | `Data/SSR_Mt5DataSource.mqh:146` | low | `SSR_T2_DataEngine.mq5`: the telemetry reaches a reader. |
| 8.3 | **`data-2` settled: per-bar rejection, not per-window.** One invalid bar drops that bar (or refuses loudly), never 60,000 silently — and `Ensure()` stops re-running the full `CopyRates` + validation on every pump for as long as the bad bar sits in the window. | `data-2` (POTENTIAL_RISK HIGH) | M | `Data/SSR_BarWindow.mqh:218`, `Data/SSR_DataValidator.mqh:54-57, 247-282`, `Data/SSR_Mt5Providers.mqh:265-275` | **medium** — it changes what "usable" means, and K13 (zero bars is data, not failure) must survive it | `SSR_T2_DataEngine.mq5`: a memory store with one `high < low` bar in 10,000; assert 9,999 bars are served, the bad one is reported, and `Covers()` still holds so the window is not re-read every pump. |
| 8.4 | **Symbol mapping (K.5)** — with the `SYMBOL_DIGITS > 0` existence test replaced everywhere it appears, and `Adopt()` forcing `SYMBOL_CHART_MODE_BID`. | `mt5-symbol-3` (CONFIRMED), `mt5-symbol-2` (POTENTIAL_RISK), `mt5-symbol-8`, `qa-smoke-3` | M | `Mt5/SSR_CustomSymbolManager.mqh:338, 476, 557` | medium — adoption behaviour changes for pre-v120 leftovers | `SSR_T3_CustomSymbol.mq5`: adopt a whole-point instrument and a LAST-mode leftover; assert both are recognised and both end in BID mode, read back. |
| 8.5 | **Import + normalization on the `CSSRMemoryStore` pattern (K.2, K.4)** — M1 only (K7), money properties and session schedule from the symbol (K14), declared timezone offset only. | K.2, K.4, K.6 | **L · multi-week** | new `Data/` files; `Core/SSR_IDataSource.mqh` untouched | medium — a new provider triple, and every existing engine path must treat it identically | `SSR_T2_DataEngine.mq5`: import a CSV, replay it, and assert the recorded fingerprint equals the fingerprint of the same bars fed through `CSSRMemoryDataSource`. The two paths must be indistinguishable to the engine. |
| 8.6 | **Quality score + missing-data detection (K.9, K.8).** | K.8, K.9 | L | new `Data/` file | low | `SSR_T2_DataEngine.mq5`: a fixture with a known gap count and a known duplicate count; assert both are found. |
| 8.7 | **Import cache (K.10)** — with the seed-cache version guard that currently compares a constant that never changes. | `mt5-symbol-7`, `mt5-symbol-1`'s cache half | M | `Mt5/SSR_SeedCache.mqh:176` | medium | `SSR_T3_CustomSymbol.mq5`: bump the version, assert the cache is invalidated. Today it never is. |
| 8.8 | **Provenance: synthetic data must never be presented as real broker ticks (K.12).** | the honesty requirement | M | `Trading/SSR_Journal.mqh` header block, the panel chip, `Report/` | low | `SSR_T10_Statistics.mq5`: a statement exported from an imported session says so in its header, and one exported from synthetic ticks says which layer synthesised them. |
| 8.9 | **Data Source Manager + precedence (K.1)** — last, because [CONFIRMED FROM CODE] K.13: *a manager with one source is ceremony*. | K.1 | L | new `Data/` file | medium | `SSR_T2_DataEngine.mq5`: two sources covering overlapping ranges; assert the precedence rule is applied and logged. |

[INFERENCE] **Phase 8 ≈ 8-10 weeks if it is needed at all**, and P4 is what decides that. 8.1-8.4
are worth doing regardless of P4's answer: they are three dead links, one discarded telemetry block
and a wrong existence test, and none of them is about import.

---

### T.15 The dependency graph

[RECOMMENDATION] Read top to bottom; an arrow means *cannot start before*.

```
                        ┌──────────────────────────────────────────┐
                        │ PHASE 0A  instruments (no terminal)      │
                        │  audits that can fail · suite green      │
                        │  spikes that assert · SSR_BarToTicks     │
                        └───────────────────┬──────────────────────┘
                                            v
                        ┌──────────────────────────────────────────┐
                        │ PHASE 0B  the first run (P1..P9)         │
                        │  P4 -> decides Phase 8 exists            │
                        │  P5 -> decides 8.3's design              │
                        │  P6 -> decides three Phase 6 designs     │
                        │  P7 -> is Phase 6's justification        │
                        │  P9 -> is Phase 7's cost model           │
                        └───────────────────┬──────────────────────┘
                                            v
                        ┌──────────────────────────────────────────┐
                        │ PHASE 0C  2 CRITICAL + 14 HIGH           │
                        │  0C.2 rewind epoch  (gates 2, 5)         │
                        │  0C.1 handover      (gates 4)            │
                        │  0C.4 OnBulkBars    (gates 1)            │
                        │  0C.8 restore       (gates 3, 5)         │
                        │  0C.9 OnRestored    (gates 3)            │
                        │  0C.10/.11/.12      (gate 2,3,5,6)       │
                        └───────┬──────────────┬───────────────────┘
                                v              v
                   ┌────────────────────┐   ┌─────────────────────┐
                   │ PHASE 1  engine    │   │ PHASE 2 trading+risk│
                   │  1.9 determinism   │   │  2.1 A22            │
                   └───┬────────────┬───┘   └──────┬──────────────┘
                       v            v              v
            ┌──────────────────┐  ┌──────────────────────────────┐
            │ PHASE 4 scenario │  │ PHASE 3 challenge            │
            │  needs 0C.1, 1.8 │  │  needs 0C.8, 0C.9            │
            └──────────┬───────┘  └──────┬───────────────────────┘
                       │                 v
                       │        ┌──────────────────────────────┐
                       └───────>│ PHASE 5 journal + coaching   │
                                │  5.0 ListRO pulled forward   │
                                └──────┬───────────────────────┘
                                       v
                                ┌──────────────────────────────┐
                                │ PHASE 6 UI architecture      │
                                │  6.1 latch FIRST, always     │
                                │  needs P6 + P7 answered      │
                                └──────┬───────────────────────┘
                                       v
                                ┌──────────────────────────────┐
                                │ PHASE 7 RTL                  │
                                │  needs 6.1, 6.3, 6.4 + P9    │
                                └──────────────────────────────┘

   PHASE 8 data import  —  parallel, gated only on P4 + P5.
   8.1-8.4 may run any time after 0B. 8.5-8.9 only if P4 says the broker is not enough.
```

**The four cross-phase gates, named once.** [CONFIRMED FROM CODE] Each is declared independently by
two or more sections:

| Gate | Gates | Declared in |
|---|---|---|
| `trading-exec-1` — the ledger survives a rewind | the risk preview, every prop rule, every journal record, every behavioural measure | G.8 #1, I.9, S.12 |
| `host-expert-7` — keys withheld while a modal is open | **every new clickable control in the product** | M.8.2, O, P.11, R.11.2, S.13 |
| `ui-panel-1`/`-2`/`-3` — the transition latch | the journal destination, the rail growth, anything drawn on a sixth or seventh cell | M.8.2 #1, S.13 #14, R.11.2 |
| `ListRO` exists | PERFORMANCE, KEYS, the review card's three views, the journal list | M.3.5, N.5.3, R.11.2 |

---

### T.16 The multi-week items, named honestly

[INFERENCE] Nine items in this roadmap are three weeks or more: the eight marked `L · multi-week` in the
phase tables (6.6 and 6.7 share one row below), plus 0C.1 and 0A.6, which are marked `L` but earn the
same warning on volume alone. A plan that treats any of them as a sprint task will fail. They are
collected here so nobody has to find them in a table.

| Item | Phase | Why it is multi-week |
|---|---|---|
| **The rewind epoch (0C.2 / RF1)** | 0C | A contract change (`OnRewind` gains a parameter) plus a mutation log in every observer that keeps derived state — the trading engine's balance, commission, swap, stops, trail peaks and MAE/MFE, a strategy's RNG, the market view's buffer. It closes one CRITICAL and one HIGH and it is the single highest-value change in the audit. 2-3 weeks, and the test is arithmetic on a balance, which is unforgiving. |
| **The one-window handover (0C.1)** | 0C | Five findings in one `OnInit`, including the audit's other CRITICAL, on the product's *default* configuration. The sweep, the stash, the settings adoption, the seed, the resolved window and two wrong guards. Nothing about it is parallelisable. |
| **Repairing thirteen spikes (0A.6)** | 0A | Nineteen findings across thirteen scripts, several of which need a genuinely concurrent probe (C3) or a real series rebuild (D4). It is a week minimum and it produces no product change — only the ability to believe a measurement. |
| **Challenge profiles and rules (3.6)** | 3 | Two families of pre-trade gates, a refusal surface on a 310 px rail, one test per rule asserting rule ids rather than strings, and a UI dependency (`ui-panel-5`) that must land first. |
| **The scenario library (4.5) and the filters (4.6)** | 4 | The first genuinely new subsystem in the roadmap. A file format, a picker bounded at 32 items over an unbounded file, four orthogonal filters and a difficulty projection that must not become a fifth source of truth. |
| **Behavioural measures (5.5)** | 5 | Ten measures, each needing a definition, a sample count, an absent-not-zero rule and a hand-verified run. R.1.2's contract is what makes it slow, and dropping the contract is how a training product starts claiming it can detect emotion. |
| **The four destinations (6.6) and the settings table (6.7)** | 6 | Together roughly +1,800 lines in the two largest UI files, 122 new catalogue strings, 61 settings rows, a new `panel.ini` contract and a release note about inherited settings. |
| **The mirror (7.6)** | 7 | ~200 mechanical `x` rewrites across every draw site in the panel, which must land as one change because a half-mirrored panel is a documented past failure. |
| **Import and normalization (8.5)** | 8 | A whole new provider triple that must be indistinguishable from the broker path to every engine caller, with timezone, session schedule and money properties all coming from the symbol rather than from a filename. |

[INFERENCE] **The whole roadmap, summed:** Phase 0 ≈ 8-10 weeks, 1 ≈ 3-4, 2 ≈ 4-5, 3 ≈ 4, 4 ≈ 4-5,
5 ≈ 6-8, 6 ≈ 10-12, 7 ≈ 6-8, 8 ≈ 8-10 (conditional). **Roughly 45-56 developer-weeks without Phase 8
and 53-66 with it — a year for one person either way** — and the first eight to ten of those weeks
end with a product that looks exactly like v125 and finally works the way v125 already claims to.

---

### T.17 What is not scheduled, and why

[RECOMMENDATION] Refusing work is part of a roadmap. Each item below was considered by an earlier
section and declined, and T does not re-open it.

* **A SETTINGS destination.** M.3.2 rejected it for want of data; P.12 confirms that ten live
  settings do not change the answer. The spare rail cell stays spare.
* **A second pseudo-combo box, a scrollbar, a slider thumb, a tooltip, a tree, a hover target or a
  disclosure triangle.** [CONFIRMED FROM CODE] The panel receives object clicks only. The wizard's
  existing pseudo-combo is `ui-dialogs-2`, a defect, not a pattern to copy.
* **Making the cost model editable in-session.** Balance, commission, slippage, swap, margin,
  stop-out, spread and ticks-per-bar are FILE-tier on the authority of the comment at
  `SSReplayStandalone.mq5:1157-1159`. The setters exist; P declines them.
* **Letting a file answer a consent question.** `InpPublish`, `InpAllowControl`, `InpAllowTrade` and
  `InpSlot` stay MQL5 inputs (P.4.1).
* **A canvas or indicator-drawn price surface** replacing the custom-symbol sink (F.10).
* **Showing a picture inside the panel.** MQL5 has no PNG object and this product has no DLL import;
  a button that writes an HTML page and names it is the honest control (S.8.4).
* **Renaming or reordering any CSV column** (DR9), or deleting any input (DR10).
* **Claiming emotion detection, or interpreting a number as a state of mind.** R.1.1 is a hard
  refusal, and every behavioural measure in 5.5 is a count with a re-derivable sample.
* **`InRange`'s modulo bias** (`Common/SSR_Random.mqh:56-58`). [CONFIRMED FROM CODE] Recorded as
  IMPROVEMENT for completeness; the bias is far below anything a trader could perceive across a
  window of a few hundred thousand minutes, and the file header explicitly deprioritises statistical
  quality. **Not a defect, and not scheduled.**
* **The 21 NOT_A_BUG findings** (T.1.4).
#### T.17.1 The five MEDIUM findings this roadmap does not schedule

**[CONFIRMED FROM CODE] Counted, not glossed.** With shorthand resolved, T cites **163 of the 227
non-refuted findings**; **64 are cited nowhere in this section** — 48 LOW, 11 IMPROVEMENT and **5
MEDIUM**. The 48 LOW and 11 IMPROVEMENT are not individually scheduled by design: they are swept by
the REFACTOR items and by the phase that owns their file, and T does not claim otherwise. **The five
MEDIUMs are a different matter, and leaving them unnamed was a defect in an earlier draft of this
section.** Each is named here with its disposition.

| id | Class | File:line | What it is | Disposition |
|---|---|---|---|---|
| `strategy-integration-report-2` | **CONFIRMED**, MEDIUM | `Strategy/SSR_StrategyHost.mqh:184` | `OnBar` is detected from the last tick of a published batch, so the moment inside the new bar at which it fires — and the `Bid()`/`Ask()` the strategy then fills at — moves with wall-clock pump boundaries. `SSR_IStrategy.mqh:20-24` promises *"the same session replays to the same trades"*; it does not hold. | **Not scheduled, and it should be.** [INFERENCE] Its fix is not independent: the firing point is a function of the pump boundary, so it rides on the same clock/pump work as `core-engine-1` (0C.3, the budget that defers instead of dropping) and RF3's `OnBulkBars` (0C.4). Adding a row for it before those land would schedule a fix whose shape those two determine. **The honest statement is that Phase 0C must re-open it as an exit criterion**, not that it is refused: the strategy seam's determinism claim is false until it is closed. |
| `strategy-integration-report-9` | **CONFIRMED**, MEDIUM | `Report/SSR_ClassReport.mqh:493` | The class KPI row, the ranking sort and the diverging-bar scale all include students who ran a **different** session — the comparison the file's own header says it refuses to make. A single outsider file shifts the median, rescales every bar and takes the top of the table behind a small "(different session)" label. | **Not scheduled: it is outside every phase's file set.** [CONFIRMED FROM CODE] The class report is the one deliverable no phase of this roadmap touches — `SSR_ClassReport.mqh` appears in no Phase 0-8 row. That is a scope statement, not a judgement of the finding, and it should be said plainly rather than left to a reader's grep. [RECOMMENDATION] It is an S-effort fix (partition on the session key before the KPI pass) and belongs in whichever release owns the classroom deliverable. |
| `ui-port-session-9` | **CONFIRMED**, MEDIUM | `Ui/SSR_GroupPort.mqh:372` | `pos_rows` counts open **and** pending rows while `open_positions` counts opens only, and `pending_count` is written and read nowhere — so the panel's only "hidden rows" indicator is computed from the wrong pair and a pending order can drop off the sheet with no `"+N more"`. | **Not scheduled as its own row because the surface it is on is replaced.** [CONFIRMED FROM CODE] The `posmore` counter and the position sheet are re-specified in M, N and O for the 245 px rail sheet, and `new-19` (D.2) is a second POTENTIAL_RISK against the same object. [RECOMMENDATION] The correct pair (`pos_rows` against `open_positions + pending_count`) must be an **acceptance criterion on Phase 6's sheet work**, and it is cheaper there than as a standalone change. |
| `chart-1` | **POTENTIAL_RISK**, MEDIUM | `Chart/SSR_ChartManager.mqh:452` | `DetectScroll` cannot tell bar arrival from a drag at high speed; one false positive kills chart-following for the rest of the session. | **Not scheduled because it may not exist.** [CONFIRMED FROM CODE] It is POTENTIAL_RISK: the mechanism depends on how many chart bars land inside the 200 ms snap window and on whether MetaTrader's own autoscroll pulls the view along, neither of which is measurable from the tree. **U-17 decides it.** T.18 branches on `data-2` and `mt5-symbol-4` and should branch on this one too: if U-17 reports a false detach at 200× with hands off the mouse, `chart-1` becomes a Phase 6 row alongside 6.9. |
| `host-expert-12` | **POTENTIAL_RISK**, MEDIUM | `SSReplayStandalone.mq5:681` | The history download abandons after six 300 ms stalls (~1.8 s) and prints a sentence blaming the broker, while the terminal may still be fetching the 60,000 M1 bars `InpHistoryBars` asked for. | **Not scheduled because the threshold cannot be chosen from source.** [CONFIRMED FROM CODE] Whether 1.8 s is short is a function of link speed and broker fetch behaviour — the reason it is POTENTIAL_RISK. **U-27 measures it.** [RECOMMENDATION] The message is separable from the timeout and is worth fixing either way: a stall that ends the loop should say *"gave up after N stalls"*, not *"usually that is all the broker serves for this symbol"*, because the second sentence has been wrong every time the first was premature. |

**[RECOMMENDATION] The rule this table establishes.** A roadmap may decline a finding, but it may not
be silent about one. Any future revision that leaves a CONFIRMED MEDIUM or above out of every phase
adds a row here.

#### T.17.2 The D.2 register: what this roadmap does and does not do with it

**[CONFIRMED FROM CODE] These are not `verified.json` findings.** D.2 registers eighteen distinct
defects (`new-1` … `new-19`, with `new-9` a duplicate of `new-1`) read directly from source while
sections G, H, L and S were written. **None went through the three refuters and two confirmers**, so
none is a CONFIRMED finding on this audit's own standard, and their severities are self-assigned.
This roadmap therefore **schedules none of them as a defect fix**; it only records where each lands
so that the register can be tracked to closure.

| Register id | Where this roadmap touches it | Disposition |
|---|---|---|
| `new-5` (no A22 audit for the no-broker-order guarantee) | **Item 2.1** | **Scheduled.** It is the only one of the eighteen already carried as a numbered roadmap item, and it was scheduled on its own merits (K5 → A22) before the register existed. |
| `new-1` / `new-9` (risk money from balance, sizing from equity), `new-2` (`Market()` drops tag and trailing), `new-3` (no preview for the always-live buttons), `new-4` (dimmed button still executes), `new-7` (cap path never populates `TradeError()`), `new-8` (73-char reason into a 63-char label), `new-10` (`ConfigureFromSymbol` fabricates a model), `new-11` (`vol_max` returns a non-zero lot with the warning discarded) | **Item 2.5**, as its input set | **Carried, not scheduled.** Item 2.5 rebuilds the risk preview and the nine `SSRPortState` fields, which is the surface all eight land on. [RECOMMENDATION] Item 2.5's acceptance criteria should name these ids explicitly, so a reviewer can check each off rather than judge the surface as a whole. |
| `new-6` (every cost input defaults to 0; `CheckStopout` therefore dead at defaults) | nothing | **Not scheduled, and it is a decision, not a defect fix.** [CONFIRMED FROM CODE] T.17 already refuses to make the cost model editable in-session. Changing the **defaults** is a separate, one-line-per-input choice that only the author can make, and it changes every existing session's arithmetic. It must be made deliberately or not at all. |
| `new-12` (tick-value asymmetry cloned, never read) | nothing | **Not scheduled: POTENTIAL_RISK by construction.** It fires only on a broker that publishes different profit and loss tick values, which no one here has surveyed. Section U's bench matrix is where it is decided. |
| `new-13` (`MoneyOf` duplicated), `new-14` (`risk_at_entry` excludes commission), `new-15` (`RoundToStep` does not normalise) | nothing | **Not scheduled.** `new-14` is a *declared* choice question — it is the same class as `trading-analytics-10`, which item 5 of section S makes explicit rather than fixing. `new-13` and `new-15` are hygiene against two lines each. [RECOMMENDATION] They belong in the same commit as whatever next touches `SSR_RiskEngine.mqh`, which is item 2.5. |
| `new-16`, `new-17`, `new-18` (run id, `note` writer, and `sl`/`tp`/`risk_at_entry`/spreads never exported) | **AD7** (nine journal fields + v2 CSV + run folders) | **Carried.** All three are what AD7 exists to close; S.13's build order items 5, 7, 8 and 9 are the work. |
| `new-19` (`posmore` may collide with `poshint` at 245 px) | **Phase 6's sheet work** | **Not scheduled as a fix: POTENTIAL_RISK by construction**, because it depends on glyph metrics MQL5 will not report. It shares its surface with `ui-port-session-9` (T.17.1) and both should be acceptance criteria on the same change. |

**[RECOMMENDATION] The one thing that must happen before any of these is scheduled as a defect.**
Run the register through the same refuter process the 248 ran. Eighteen candidates is one pass. Until
then, an item that cites a `new-` id is citing a weaker claim than one that cites a `verified.json`
CONFIRMED, and no phase gate may depend on one.

* **`core-engine-5`'s number being added to any new surface.** [CONFIRMED FROM CODE] `bars_consumed`
  is wrong by 10-1500× and 1.4 fixes it; until then N.12 and S.14 both forbid drawing it next to a
  trading measure. It must not be *added* anywhere while it is wrong.

---

### T.18 The standing caveat

**[STATED PREMISE — not a source fact, see T.0's gate]** Build v125 has never run on a MetaTrader
terminal; the author has never run it; MT5 cannot be installed in the build environment.
[CONFIRMED FROM CODE] Every effort figure in this section is an estimate over a source reading. Every regression-risk rating is a judgement. Every proving test named here is a
test that does not yet pass, and eleven of them are tests that do not yet exist.

[INFERENCE] **One item is known to be missing rather than declined:** `strategy-integration-report-2`
(CONFIRMED, MEDIUM) has no row, and T.17.1 says why — its fix is determined by Phase 0C's clock work
and cannot be shaped before it. Two more (`chart-1` and `host-expert-12`, both POTENTIAL_RISK,
MEDIUM) are branch points that section U decides, and one (`strategy-integration-report-9`) is
outside every phase's file set. **So the claim is not that nothing is missing.** The claim is
narrower: the most likely way the roadmap's *order* is wrong is that **Phase 0B changes the order of
everything after it.** If `data-2` fires (POTENTIAL_RISK), Phase 8's first four items move into Phase 1. If
`mt5-symbol-4` fires (POTENTIAL_RISK),
a teardown path that can close the user's own chart becomes a Phase 0C item. If L.4.2 resolves
optimistically, three Phase 6 designs get simpler and one removal (RM6) becomes a repair. If P7
measures 4 ms per frame rather than 39, Phase 6's first change stays correct and stops being urgent,
and Phase 5 should probably precede it.

[RECOMMENDATION] Which is the argument for the shape of this roadmap rather than an objection to it:
**the first phase is the one that tells you whether the other eight are in the right order.**

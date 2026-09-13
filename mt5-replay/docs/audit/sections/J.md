## J. RANDOM / SCENARIO ENGINE

*Scope: the Random Replay feature as it exists in build v125, the determinism contract behind its seed, and what a Scenario Engine (coach-defined, savable, replayable) would have to be built on. Everything below is tagged; every defect is either a verified finding id or a quotation from source.*

---

### J.1 What exists today

The randomness subsystem is three files and one input pair. It is small, it is deliberate, and it is documented better than most of the product.

| Piece | File | What it is |
|---|---|---|
| `SSRRandom` | `MQL5/Include/SSReplay/Common/SSR_Random.mqh:29` | xorshift64\* struct — `Seed`, `Next`, `InRange`, `Index`, `Chance` |
| `SSRPickSeed()` | `SSR_Random.mqh:80` | the one sanctioned wall-clock read, `(TimeLocal()*1000003) ^ (GetMicrosecondCount()*2654435761)` |
| `SSRSeedText` / `SSRSeedFromText` | `SSR_Random.mqh:91`, `:93` | how a seed is printed and typed back |
| `CSSRRandomPicker` | `MQL5/Include/SSReplay/Data/SSR_RandomPicker.mqh:37` | picks symbol + start from the catalogue, reproducibly |
| `InpRandom` / `InpSeed` | `MQL5/Experts/SSReplay/SSReplayStandalone.mq5:100-101` | the expert inputs |
| `random_start` / `seed` | `MQL5/Include/SSReplay/Ui/SSR_SetupPanel.mqh:137-138` | the same two settings in the setup wizard |
| `[settings] seed=` | `MQL5/Include/SSReplay/Session/SSR_SessionManager.mqh:184` | the seed written into a saved session |

**[CONFIRMED FROM CODE]** The design intent is stated in the header of `SSR_Random.mqh:9-18` and is correct: *"a self-contained generator with an explicit seed, and the seed is REPORTED… the statistical quality of the stream is a distant second."* The generator carries pure integer state (`ulong state`, `SSR_Random.mqh:31`), so the sequence is identical on every machine and every build. `Seed(0)` is replaced with `0x9E3779B97F4A7C15` because zero is xorshift's absorbing state (`:38-40`). `InRange` returns `lo` on an empty or inverted range rather than faulting (`:53-60`). This is a sound L0 primitive and nothing in this section proposes replacing it.

**[CONFIRMED FROM CODE]** There is no `MathRand()` anywhere in the product — a grep across `MQL5/` returns only `SSR_Random.mqh` and its callers. `CSSRTickSynthesizer` invents the intrabar path from a declared deterministic model (`SSR_TickSynthesizer.mqh:6-9`: bullish `open→low→high→close`, bearish `open→high→low→close`), not from a random walk. The engine is therefore *already* free of hidden nondeterminism inside a fixed data environment. That is the single biggest asset the Scenario Engine has.

**[CONFIRMED FROM CODE]** The seed fans out to four consumers, not one:

```
SSReplayStandalone.mq5:1041   PrintFormat("[host] random session - %s", g_picker.Ticket());
SSReplayStandalone.mq5:1237   g_strategies.SetSeed(CfgRandom() ? g_picker.Seed() : 1);
SSReplayStandalone.mq5:1356   g_journal.SetSession(..., (CfgRandom() ? IntegerToString((long)g_picker.Seed()) : ""));
SSReplayStandalone.mq5:418    out.seed = g_picker.Seed();          // into the session file
```

So the reproducibility contract is wider than the start-pick: it also covers per-strategy RNG streams (`SSR_StrategyHost.mqh:141`) and the identity written into the journal CSV (`SSR_Journal.mqh:194`, `"# seed,"`).

---

### J.2 The determinism contract, stated precisely

This is the part the brief asks for, so it is stated as an invariant rather than as prose.

#### J.2.1 What the seed actually decides

**[CONFIRMED FROM CODE]** `CSSRRandomPicker::Pick` (`SSR_RandomPicker.mqh:122-186`) consumes the RNG exactly twice per outcome:

```mql5
for(int a = 0; a < attempts; a++)
  {
   string sym = m_pool[m_rng.Index(m_pool_count)];      // :149  — one draw per attempt
   if(!m_cat.Scan(sym)) { m_skipped += ...; continue; }
   long lo = m_cat.EarliestStart(warmup_bars);          // :157
   long hi = m_cat.LatestStart(warmup_bars, replay_minutes);
   if(lo <= 0 || hi <= 0 || hi <= lo) { ...; continue; }
   long pick = SSRBarOpenMsc(m_rng.InRange(lo, hi), PERIOD_M1);   // :171 — one draw on success
   ...
  }
```

The seed therefore decides **two integers**: an index into the pool, and an offset inside `[lo, hi)`. Nothing else. Every other property of the resulting session — how many bars of warmup arrive, which fidelity is used, what the spread is, whether news lines are drawn — is decided outside the RNG.

#### J.2.2 The five environment terms the seed does *not* capture

**[CONFIRMED FROM CODE]** For the same seed to yield the same session, all five of these must be identical between the two runs:

1. **Pool content *and order*.** The pool is built `AddSymbolList(InpAlsoSymbols)` then `AddSymbol(origin)` (`SSReplayStandalone.mq5:1021-1022`), and `Index()` maps the draw to a slot. `origin` is the chart's symbol. Attach the same EA with the same seed to a GBPUSD chart instead of a EURUSD chart and the last pool slot changes, so the same draw selects a different instrument.
2. **The number of rejected candidates.** Each rejection consumes one `Index()` draw and *shifts the stream* for every later draw (`:149`, `:152-165`). A terminal that has downloaded XAUUSD history and one that has not will consume different numbers of draws before the accepted candidate, so the accepted candidate's `InRange` draw is a different number.
3. **`m_range.first_msc` and `m_range.last_msc`.** These are the bounds of `InRange`: `EarliestStart = first_msc + warmup_bars * 60000` and `LatestStart = last_msc − replay_minutes * 60000` (`SSR_HistoryCatalog.mqh:161-175`). `first_msc` is `SERIES_FIRSTDATE` — *locally downloaded* M1 depth (`SSR_Mt5Providers.mqh:97, 110`), which differs per machine and grows as the user scrolls charts. A different `lo` with the same draw is a different start instant.
4. **`InpWarmupBars` and `InpReplayBars`.** Passed straight into `Pick(InpWarmupBars, InpReplayBars, origin)` (`SSReplayStandalone.mq5:1024`) and therefore into both bounds. Neither is carried by the seed, neither is written into the session file's `[settings]` block (`SSR_SessionManager.mqh:181-192`), and neither is a field of `SSRSetupValues` (`SSR_SetupPanel.mqh:108-147`).
5. **Whether the market was open when `Discover()` ran.** Finding **data-7** (CONFIRMED, LOW): the forming-bar test at `SSR_Mt5Providers.mqh:125` misfires on a closed market and drops the last complete M1 bar, moving `last_msc` — and therefore `hi` — by one minute. Same seed, Saturday versus Wednesday, different window.

**[INFERENCE]** Items 2 and 3 together mean the seed→window map is a function of the *local history state*, not of the seed. Two students handed "seed 8143772915" by a coach get the same session only if their terminals hold the same M1 depth for every symbol in the pool. The class-report premise stated at `SSR_ClassReport.mqh:5` (*"hand twenty people the same seed"*) and `SSR_Journal.mqh:39` (*"Twenty students can be handed the same seed and get bar-for-bar…"*) is not currently guaranteed by the code that would have to guarantee it.

#### J.2.3 The tick layer is chosen outside the seed as well

**[CONFIRMED FROM CODE]** `SSReplayStandalone.mq5:1150-1152`:

```mql5
g_ctrl.SetFidelity(range.has_ticks ? SSR_FIDELITY_FULL_TICK
                                   : SSR_FIDELITY_SYNTHETIC_TICK);
```

and `range.has_ticks` is probed over *the last 24 hours of held data* (`SSR_Mt5Providers.mqh:133-138`), not over the replay window. So identical bars can be walked by real broker ticks on one terminal and by the synthesiser's four-point path on another — different fill order, different stop-versus-target resolution, different trade outcomes from the same seed. Finding **core-engine-4** (CONFIRMED, HIGH) is the sharp end of this: a FULL_TICK window that contains zero broker ticks is consumed silently, and tick availability is never re-evaluated per window.

#### J.2.4 The statement

**[INFERENCE, grounded in the six citations above]** *A seed reproduces a scenario exactly if and only if the pool composition and order, the locally held M1 range of every pool member, `InpWarmupBars`, `InpReplayBars`, the quote-session state at discovery, the broker's bar values over the chosen window, and the fidelity selection are all identical.* Today the seed pins none of those, and `Ticket()` reports none of them:

```mql5
SSR_RandomPicker.mqh:189-194
   string Ticket(void)
     {
      if(!HasPick()) return "no pick";
      return StringFormat("seed %s", SeedText());
     }
```

**[RECOMMENDATION]** The architecturally correct fix is not to make the environment reproducible — that is not achievable against a broker's history. It is to **stop re-deriving the window on replay**. A scenario must record the *resolved* triple (symbol, `start_msc`, `end_msc`) that the seed produced, and replay must load that triple directly without running `Pick()` at all. The seed then documents *how the scenario was generated*; the resolved triple *is* the scenario. `CSSRRandomPicker` already computes and exposes exactly that triple (`PickedSymbol()/PickedStart()/PickedEnd()`, `:111-113`) and `ToString()` already formats it (`:196-204`) — it is simply never persisted. This is a small change with a large payoff and it should precede every other item in this section.

---

### J.3 Defects that break reproducibility today

| Finding | Severity | Effect on the random/scenario feature |
|---|---|---|
| **host-expert-5** | CONFIRMED, HIGH | The random session does not survive the one-window handover. With `InpSeed=""`, pass 2 calls `SetSeed(SSRSeedFromText("")) == SetSeed(0)`, which substitutes a *fresh* `SSRPickSeed()` (`SSR_RandomPicker.mqh:68-69`) — so the seed printed on pass 1 reproduces nothing and the user ends up in a different window. If `setup.ini` exists, `CfgRandom()` reads `g_setup.random_start`, which the pass-2 block never seeds from `InpRandom`, so randomness is silently switched off. With a non-empty `InpAlsoSymbols` the re-roll can also pick a *different instrument* that is then replayed into the custom symbol adopted from pass 1. **This is the single blocking defect for Random Training.** |
| **data-3** | CONFIRMED, MEDIUM | The picker draws candidates *with replacement*: `m_pool[m_rng.Index(m_pool_count)]` inside a loop bounded by `min(pool, 8)` (`:145-149`). With a pool of 3 where one qualifies, the feature reports "no candidate had enough history" ~30% of the time even though the answer existed. Both the loop bound's own comment (`:31-34`) and the class header (`:11-14`) say the intent was to try *each* candidate. |
| **strategy-integration-report-4** | CONFIRMED, MEDIUM | `m_ctx[k].rng.Seed(m_seed ^ NameHash(s.Name()))` runs once, inside `Add()` (`SSR_StrategyHost.mqh:141`). Neither `OnSessionStart` (`:160-169`) nor `OnRewind` (`:214-222`) touches it, so a strategy that draws from `ctx.rng` takes different decisions the second time through the same bars after a step-back. The seed is private with no accessor, so a strategy cannot repair this itself. |
| **data-4** | CONFIRMED, MEDIUM | `warmup_bars` is a bar count in one reading and a span of minutes in the other. `EarliestStart(288000)` adds 200 *calendar* days (`SSR_HistoryCatalog.mqh:174`). On any instrument that does not quote every minute, the picker skips symbols by name that could have served, and the accepted window's warmup is silently short. |
| **core-engine-6** | CONFIRMED, MEDIUM | The same conflation in the timeline: `want = start_msc − bars * SSR_MSC_PER_MIN` (`SSR_ReplayTimeline.mqh:80`). A random start that lands on a Monday morning seeds almost no warmup, so the trader's HTF context depends on *where in the week the seed landed* — which is exactly what a difficulty setting must not be. |
| **tests-b-3** | CONFIRMED, MEDIUM | T13.8, the section named *"the same seed gives the same strategy"*, asserts three tautologies (`SSR_T13_Strategy.mq5:539`) and would pass with `SetSeed`'s body deleted. **The reproducibility claim has no test behind it.** |
| **ui-port-session-10** | CONFIRMED, LOW | A save made from the Session dialog writes `SSRSessionSettings::Init()` defaults, so the file records `seed 0` — "this was not a random session" — for a session that was. The comment at `SSR_SessionManager.mqh:182-183` says the seed is written *"so a session that was random can be recognised as such months later"*; a panel-made save cannot do that. |
| **host-expert-10** | CONFIRMED, LOW | `CollectSettings` (`:417-426`) reads raw inputs rather than the `Cfg*()` accessors, so the `[settings]` block describes the inputs, not the session that ran. |
| **mt5-symbol-1** | CONFIRMED, HIGH | Warmup repair after a jump is a silent no-op whenever the seed was reused from the cache — i.e. on pass 2 of every one-window random session. The chart the trader studies is not the chart the seed describes. |
| **data-2** | POTENTIAL_RISK, HIGH | One invalid M1 bar voids the entire read window and is reported as zero bars with success. Depends on broker data quality; if it fires, a seed that worked yesterday replays nothing today. |

---

### J.4 Random Training — feature-by-feature gap analysis

| Requested | Backing today | Verdict |
|---|---|---|
| **Random start** | `Pick()` → `m_start_msc`, snapped to an M1 boundary (`SSR_RandomPicker.mqh:171-173`) | **[CONFIRMED FROM CODE]** exists; blocked by host-expert-5 |
| **Random symbol** | pool of ≤32 from `InpAlsoSymbols` + origin (`:29`, `:86-100`) | **[CONFIRMED FROM CODE]** exists; degraded by data-3 |
| **Random session (London / NY / Asia)** | nothing | **[CONFIRMED FROM CODE]** absent. `ENUM_SSR_SESSION_MODE` (`SSR_SessionWatcher.mqh:30-34`) is `OFF / BY_GAP / BY_DAY` — a *new-session detector for auto-pause*, not a named trading session. There is no London/NY/Tokyo clock anywhere in the build. |
| **Random volatility** | nothing | **[CONFIRMED FROM CODE]** absent. No ATR, range or realised-volatility measure over a candidate window exists in `Data/` or `Trading/`. |
| **Random news** | `CSSRCalendar` with `Pull(currency, from, to, min_importance)` (`SSR_Calendar.mqh:125-137`) and a `m_pause_min` | **[INFERENCE]** partial: the *data* to test "does this window contain a high-impact release" exists, but the calendar is a tick observer wired to pausing and drawing, not a candidate filter. Finding **data-6** (NOT_A_BUG) confirms it loads the whole window at session start. |
| **Random regime (trend/range)** | nothing | **[CONFIRMED FROM CODE]** absent. |
| **Blind mode** | `ENUM_SSR_BLIND` OFF/STANDARD/FULL, `SSRBlindPolicy` (`SSR_BlindMode.mqh:40-93`) | **[CONFIRMED FROM CODE]** exists, with three live defects: **chart-3** (the reveal is undone within ~200 ms because housekeeping tests `IsOn()` rather than `IsApplied()`), **chart-4** (the record of the user's original chart settings does not survive a reinit — and one-chart mode guarantees a reinit), **chart-5** (FULL claims the price level is hidden while the entry-line label and the Buy/Sell buttons print the absolute price). |
| **Hidden future** | `SSR_FutureGuard.mqh`; the session file explicitly stores nothing beyond the instant reached (`SSR_SessionManager.mqh:27-29`) | **[CONFIRMED FROM CODE]** exists as an architectural invariant, which is the right place for it |
| **Difficulty EASY/NORMAL/HARD/EXTREME** | nothing | **[CONFIRMED FROM CODE]** absent — no enum, no field, no input |
| **Deterministic seed** | `SSRRandom` + `InpSeed` + `Ticket()` | **[CONFIRMED FROM CODE]** exists as a primitive; **incomplete as a scenario identifier** — see J.2.4 |

Two further observations on the current random UI:

**[CONFIRMED FROM CODE]** `ApplyMode(3)` — "Random practice" — sets `m_v.blind = SSR_BLIND_OFF` (`SSR_SetupPanel.mqh:1133-1134`). So the mode shortcut for random training actively *clears* blind mode, and because `ModeNow()` returns 3 whenever `random_start` is set (`:1142`), a blind+random session displays as "Random practice" and loses its blind setting the moment the user clicks the highlighted mode again. Random-and-blind — the actual shape of Random Training — is reachable only by setting blind separately on the START step (`:787`). The comment at `:1116-1118` explicitly endorses non-exclusive modes ("a Prop challenge run blind is a real thing to practise"); `ApplyMode` does not implement that for case 3.

**[CONFIRMED FROM CODE]** The quick-start button `qrand` clears the seed unconditionally (`:1046-1051`: `ApplyMode(3); m_v.seed = "";`). There is no quick path that *replays* a seed — the user must walk the wizard to step 3 and type it into the `eseed` edit box.

**[CONFIRMED FROM CODE]** The seed never reaches the panel. Greps of `SSR_Panel.mqh`, `SSR_GroupPort.mqh` and `SSR_ReplayPort.mqh` find no occurrence of "seed". The only place a trader can read the number they are told to write down is the Experts log line at `SSReplayStandalone.mq5:1041`, plus the journal CSV header (`SSR_Journal.mqh:194`). **[RECOMMENDATION]** A seed chip in the panel caption (guarded by the 63-character `OBJPROP_TEXT` limit and the chip-row overrun already recorded as **ui-panel-13**) is a one-line change with disproportionate value.

**[CONFIRMED FROM CODE]** `SSRSeedText` is `IntegerToString((long)seed)` (`SSR_Random.mqh:91`) while `SSRPickSeed` returns a full 64-bit value, so roughly half of all auto-picked seeds print as a **negative** number. `SSRSeedFromText` is `(ulong)StringToInteger(t)` (`:93-101`), so **[INFERENCE]** the value round-trips correctly through two's complement — the defect is cosmetic, not functional, but "write down seed -6103400981285129387" is a poor instruction to give a student.

---

### J.5 The Scenario Engine — what it is, and what it must be built on

A scenario, as the brief defines it, is: *symbol, timeframe, date range, risk, max trades, max loss, target, blind, news, session, difficulty, seed* — named, saved, replayed.

#### J.5.1 What of that the codebase can already express

| Scenario field | Existing home | Status |
|---|---|---|
| symbol | — | **[CONFIRMED FROM CODE]** no field. `SSRSetupValues` (`SSR_SetupPanel.mqh:108-147`) has no symbol; `origin` comes from the chart (`SSReplayStandalone.mq5:853`). A coach-defined scenario naming an instrument has nowhere to put it. |
| timeframe | `SSRSetupValues.chart_tf`, `SSR_SETUP_TFS[]` (`:151-152`) | exists |
| date range | — | **[CONFIRMED FROM CODE]** no field. `InpStart` is an input; `g_pick_msc` is the dragged line. Not persisted in `setup.ini` (`Save`, `:1211-1233`). |
| risk | `SSRSetupValues.risk_percent` | exists |
| max trades | — | **[CONFIRMED FROM CODE]** absent everywhere (grep for `max_trades`/`MaxTrades` returns nothing across `MQL5/`) |
| max loss | `SSRPropRules.max_daily_loss_pct` / `max_total_loss_pct` (`SSR_PropEvaluation.mqh:73-74`) | exists, as a percentage of start balance, enforced by `CSSRPropEvaluation` |
| target | `SSRPropRules.profit_target_pct` (`:72`) | exists |
| blind | `SSRSetupValues.blind` | exists (defects in J.4) |
| news | `CSSRCalendar` | data only, no filter |
| session | — | absent (see J.4) |
| difficulty | — | absent |
| seed | `SSRSetupValues.seed` (string) | exists |

**[INFERENCE]** So roughly half the scenario record already exists, scattered across `SSRSetupValues` and `SSRPropRules`, and the missing half is exactly the half that would need new domain logic (session windows, volatility, regime, news filtering, difficulty).

#### J.5.2 The persistence seams that already fit

**[CONFIRMED FROM CODE]** Three patterns in the build are the right foundation and should be reused rather than reinvented:

1. **`CSSRSessionFile`** (`SSR_SessionFile.mqh:42`) — sectioned key/value text with a format number that *refuses* a future version rather than guessing (`:275-281`). A `[scenario]` section is a natural fit and costs no new format work.
2. **`presets.ini`** (`SSR_SetupPanel.mqh:54-58`, loaded at `:311-375`, saved at `:376-390`) — the existing proof that this product ships editable, coach-authorable definition files rather than tables baked into the code. The header comment at `:54-58` already states that policy. Scenarios are the same pattern, one level up.
3. **`CSSRSessionManager::Path()`** (`SSR_SessionManager.mqh:92-99`) — the name sanitiser (`\`, `/`, `:` → `_`) plus `List()`/`Peek()` (`:126`, `:213`). A scenario library needs exactly `List`, `Peek`, `Load`, `Save` over a directory, which this class already demonstrates.

**[CONFIRMED FROM CODE]** The **mode-is-derived** principle at `SSR_SetupPanel.mqh:1110-1118` — *"There is no `mode` field, because a fifth source of truth that has to agree with four others is the thing that eventually disagrees"* — is the correct architecture and a scenario must not violate it. A scenario is a **named set of the settings that already exist**, applied in one shot, with `ModeNow()`-style derivation for display. It must not become a parallel `difficulty` switch that the rest of the code then has to consult.

#### J.5.3 Difficulty, done without a fifth source of truth

**[RECOMMENDATION]** `EASY/NORMAL/HARD/EXTREME` should be a **projection onto settings that already exist**, exactly like `ApplyMode`:

| | speed floor | blind | spread | fidelity | news filter | pauses |
|---|---|---|---|---|---|---|
| EASY | any | OFF | `InpSpreadPoints` | any | avoid high-impact | SL+TP pause on |
| NORMAL | any | OFF | recorded | any | none | SL+TP pause on |
| HARD | ≥ 1× | STANDARD | recorded | prefer FULL_TICK | require ≥1 medium | entry pause only |
| EXTREME | ≥ 1× | FULL | recorded + slippage | require FULL_TICK | require ≥1 high | none |

Every column in that table is an existing field (`SSRSetupValues.speed`, `.blind`, `.spread_points`; `SSRExecutionModel`; `SSR_FidelityPolicy.mqh`; `CSSRAutoPause::Flags()`). `ENUM_SSR_DIFFICULTY` then belongs in `SSR_Types.mqh` beside `ENUM_SSR_BLIND`, and `SSRApplyDifficulty(level, SSRSetupValues&, SSRPropRules&)` belongs next to `ApplyMode` — **[INFERENCE]** derived for display, never consulted at runtime.

**[RECOMMENDATION]** `max trades` is the one genuinely new rule. It belongs in `CSSRPropEvaluation` beside `max_days` (`SSR_PropEvaluation.mqh:77`), which is already a count-based limit with a breach path (`:418`), *not* in the scenario record as an enforcement-free number.

#### J.5.4 Session / volatility / news / regime selection

**[RECOMMENDATION]** All four are *candidate filters*, and the only place in the codebase that holds both the catalogue and the RNG is `CSSRRandomPicker::Pick`'s loop (`:147-181`). The clean extension is a small predicate object the picker owns and the host configures:

```
CSSRPickFilter:  AcceptsWindow(symbol, start_msc, end_msc) -> bool, plus RejectReason()
```

with concrete filters: a session-hours filter (server-time hour band — new code, no existing backing), an ATR/range band over the candidate window (new code, but `CSSRBarWindow` can supply the bars), and a calendar filter driven by the existing `CalendarValueHistory(vals, from, to, NULL, currency)` call at `SSR_Calendar.mqh:132-137`.

**[CONFIRMED FROM CODE — determinism consequence, and it is the important part of this subsection]** Filtering means *rejection sampling*, and rejection sampling consumes RNG draws. Because `Index()` and `InRange()` advance the same shared `m_rng` state (`SSR_RandomPicker.mqh:41`), adding a filter changes the number of draws consumed before acceptance, which changes every later draw. Therefore:

- **[RECOMMENDATION]** A filtered pick must be bounded (`SSR_PICK_ATTEMPTS` already establishes the pattern at `:34`) and must report its rejections by name, as `m_skipped` already does (`:153`, `:161-164`).
- **[RECOMMENDATION]** A filtered scenario **cannot** be replayed by re-running the picker with the same seed unless the filter, the calendar contents, and the local history are all identical. MT5's economic calendar is terminal-supplied, revised, and unversioned — **[INFERENCE]** a news-filtered scenario is *not* reproducible from a seed even in principle. This is the decisive argument for J.2.4's recommendation: **persist the resolved window; the seed is provenance, not the replay mechanism.**

#### J.5.5 The pool/stream coupling that a scenario must break

**[CONFIRMED FROM CODE]** `InpAlsoSymbols` is read twice for two different purposes: as the picker's candidate pool (`SSReplayStandalone.mq5:1021`) and as the master clock's extra streams (`:455-458`). The pool cap is 32 (`SSR_MAX_RANDOM_SYMBOLS`, `SSR_RandomPicker.mqh:29`); the stream cap is 3 (`SSR_EXTRA_STREAMS = SSR_MAX_STREAMS − 1`, `SSReplayStandalone.mq5:255`, `SSR_MasterClock.mqh:34`), and the build loop silently stops at 3 (`:462`). So a coach who defines a ten-symbol random pool also gets three unrequested extra charts and seven silently ignored names. **[RECOMMENDATION]** A scenario record needs `pool` and `also_symbols` as *separate* fields; they are the same string today only by accident.

---

### J.6 Ordered recommendations

**Fix before building anything on top (each is a verified defect, not a redesign):**

1. **host-expert-5** — carry `random_start`, the resolved seed, *and the resolved window* across the one-window handover. Without this, Random Replay is broken on the default configuration (`InpOneChart = true`, `SSReplayStandalone.mq5:130`) and no scenario built on it can work. **[RECOMMENDATION]**
2. **data-3** — draw candidates without replacement (shuffle the pool with the existing RNG, then walk it). Three lines; restores the guarantee the loop bound's own comment claims. **[RECOMMENDATION]**
3. **strategy-integration-report-4** — re-seed `m_ctx[i].rng` in `OnRewind` and `OnSessionStart`, or expose the seed on `CSSRStrategyContext` so a strategy can. **[RECOMMENDATION]**
4. **tests-b-3** — replace T13.8's three tautologies with a probe strategy that reads `ctx.rng.Next()`; the finding notes `CSSRStrategyContext::rng` is public and reachable from a subclass, so the test is writable today. **[RECOMMENDATION]**
5. **chart-3 / chart-4 / chart-5** — blind mode is half of Random Training's value proposition and currently un-reveals itself, poisons the user's chart settings across a reinit, and misstates what it hides. **[RECOMMENDATION]**
6. **ui-dialogs-1** — `ReadAll()`'s `Str()` cannot distinguish an empty edit box from an absent one and wipes `session_name`. **Any scenario name typed into an edit box will be wiped by the same path**, so this is a prerequisite for savable scenarios, not an unrelated dialog bug. **[RECOMMENDATION]**
7. **ui-port-session-10 / host-expert-10** — make every save path go through `CollectSettings`, so a saved session's `[settings]` block actually records the seed it ran under. **[RECOMMENDATION]**

**Then build, in this order:**

8. Persist the **resolved** `(symbol, start_msc, end_msc, seed)` from `CSSRRandomPicker` into the session file and into a new `[scenario]` section; make replay load the triple and skip `Pick()` entirely. **[RECOMMENDATION]** **[FUTURE FEATURE]**
9. Extend `SSRSetupValues` with `symbol`, `start_msc`, `end_msc`, `pool` (separate from `also_symbols`), `max_trades`, `difficulty`, `news_policy`, `session_band` — and extend `Save`/`Restore` (`SSR_SetupPanel.mqh:1211-1260`) in the same place, per the existing "one struct so the host cannot forget a field" rule (`SSR_SessionManager.mqh:46-49`). **[FUTURE FEATURE]**
10. A `scenarios\*.ssrs` library modelled on `CSSRSessionManager::List/Peek/Path` and on `presets.ini`, with a picker built from the existing menu widget — noting **ui-dialogs-15**, which caps `MenuClear` at 32 items while the backing file is unbounded, so a long scenario library will orphan buttons on the chart unless that is fixed first. **[FUTURE FEATURE]**
11. `SSRApplyDifficulty` as a projection (J.5.3), and `CSSRPickFilter` for session/volatility/news/regime (J.5.4). **[FUTURE FEATURE]**
12. A determinism harness. **[CONFIRMED FROM CODE]** `CSSRRecordingSink::Fingerprint()` already exists *"for determinism tests"* (`SSR_RecordingSink.mqh:163-164`) and `SSRFingerprintBars` is already written per stream into the session file (`SSR_ReplayController.mqh:1736-1737`) and checked on restore (`:1841-1855`). A test that replays one scenario twice and compares sink fingerprints is buildable from parts that are already in the repository and are currently exercised only by T12. **[RECOMMENDATION]**

**Lower priority / cosmetic:**

13. **[RECOMMENDATION]** Show the seed on the panel (J.4), and consider printing it unsigned so a student is not asked to copy a negative twenty-digit number.
14. **[RECOMMENDATION]** `ApplyMode(3)` should not clear `blind` — random-and-blind is the intended shape of Random Training and the file's own comment already argues for non-exclusive modes.
15. **[IMPROVEMENT]** `InRange` uses `Next() % span` (`SSR_Random.mqh:56-58`), which is biased for spans that do not divide 2^64. The bias is far below anything a trader could perceive across a window of a few hundred thousand minutes, and the file header explicitly deprioritises statistical quality — recorded for completeness only, **not** a defect.

---

### J.7 Caveat

**[CONFIRMED FROM CONTEXT]** None of the runtime behaviour described here has been observed on a real MT5 terminal — the author has never run this build, and MT5 cannot be installed in the build environment. Every statement above is derived from source. The items most likely to differ in practice are the fidelity probe (J.2.3), the calendar's availability, and **data-2** (POTENTIAL_RISK), all of which depend on broker data that no amount of reading can settle.

## F. REPLAY ENGINE REVIEW

*Scope: `MQL5/Include/SSReplay/Core/` (controller, clock, timeline, cursor, fidelity policy,
pump budget, future guard, tick synthesizer, snapshot store, master clock), the MT5 sink under
`MQL5/Include/SSReplay/Mt5/`, and the host pump in `MQL5/Experts/SSReplay/SSReplayStandalone.mq5`.
Maps read: `core-engine.md`, `core-sync.md`, `mt5-symbol.md`, plus the cross-cutting parts of
`data.md`, `host-expert.md`, `chart.md`, `trading-exec.md`, `strategy-integration-report.md`.*

---

### F.1 Verdict

The M1 → custom symbol → MT5 chart architecture is the right architecture and should not be
replaced. **[INFERENCE]** It is the only design in MQL5 that gives the trainee a *real*
MetaTrader chart — real timeframes, real objects, real indicators, real crosshair — instead of a
canvas repaint of a chart, and the codebase has already paid the hard prices that design demands:
BID chart mode, 24/7 sessions, monotonic tick stamps, bar-granular truncation, a two-layer future
guard, and an M1-aligned timeline. Those are not incidental; they are the parts that took the
project 125 builds to get right, and every one of them is load-bearing.

What is weak is not the architecture but the **layer above it**: the transport verbs (step, jump,
rewind, bookmark), the fidelity contract, and the honesty instruments. Four confirmed defects in
that layer — `core-engine-1`, `core-engine-2`, `core-engine-3`, `core-engine-4` — mean that in
the shipped default configuration the step-forward key does nothing on its second press, a large
step can silently delete bars, every step *backward* replays up to five minutes invisibly to the
trading engine, and a FULL_TICK session over history older than the broker's tick depth runs to
completion showing nothing at all while the panel prints "FULL TICK". Those are engine-level
correctness failures, not polish.

None of this has ever run on a real terminal (build v125, author's own statement). Every
behavioural claim below is derived from source, and the claims that depend on terminal behaviour
are marked as such.

---

### F.2 What must remain unchanged

These are the invariants that the rest of the system is built on. A later designer who breaks one
of them will reintroduce a defect that took this project months to find. Each is cited so it can
be re-verified rather than trusted.

| # | Invariant | Where it lives | Why it is load-bearing |
|---|---|---|---|
| 1 | **M1 is the only base timeframe**, and `timeline.start_msc` is snapped down to an M1 open | `SSR_ReplayTimeline.mqh:63` (`SetWindow`) | Every cut the sink makes lands on an M1 open (`SSR_CustomSymbolManager.mqh:712-744`); if `start` were not M1-aligned, `Reset()`'s truncate would reach into warmup and invalidate the seed manifest. **[CONFIRMED FROM CODE]** |
| 2 | **Warmup goes in as BARS, replay goes in as TICKS** | `SSR_CustomSymbolSink.mqh` header rules; `SeedBars` 234-295, `EmitTicks` 300-335 | `CustomRatesUpdate` is ~three orders of magnitude cheaper per bar than building the same bars from ticks; the split is what makes a 60,000-bar warmup tolerable. **[INFERENCE]** |
| 3 | **`TruncateFrom`'s return value is the truth, not the request** | `SSR_IReplaySink.mqh` contract; `Truncate()` returns `SSRBarOpenMsc(from, M1)` at `SSR_CustomSymbolManager.mqh:712-744` | Deleting ticks does not un-build the bar they contributed to, so tick and bar stores must cut at the same M1 open. The cursor is then re-seated from that return. **[CONFIRMED FROM CODE]** |
| 4 | **The emit window is half-open `(cursor.emitted, clock.now]`**, and the cursor is the single truth for "what the sink holds" | `SSRReplayCursor::PendingRange`; `EmitWindow` at `SSR_ReplayController.mqh:317+` | This is what makes a second pump into the same minute not re-send the first pump's ticks — the failure that produces a corrupt candle. **[CONFIRMED FROM CODE]** |
| 5 | **Guard moves before every read; two layers** (controller `ClampRange`, then provider `GuardRange`/`FilterTicks`) | `SetHorizon` at controller 1009/1084/1175/1361; `SSR_FutureGuard.mqh` | The product's entire claim is "no future data". One layer is an assertion; two layers is a guarantee that survives a new data source. **[CONFIRMED FROM CODE]** |
| 6 | **`SYMBOL_CHART_MODE = BID` on the replay symbol, and `TICK_FLAG_LAST` on every synthetic tick** | `SSR_CustomSymbolManager.mqh:383-395`; `SSR_TickSynthesizer.mqh:174, 203` | The belt-and-braces pair that fixed "the terminal took 481 ticks, refused 0, and the M1 series stayed at 139 bars" on index/futures CFDs. Keep **both**. **[CONFIRMED FROM CODE]** |
| 7 | **24/7 quote and trade sessions, verified by read-back** | `Apply247Sessions()` `SSR_CustomSymbolManager.mqh:165-216` | Outside a session the terminal accepts ticks and builds no bar — the same silent failure as (6), reached by a different route. **[CONFIRMED FROM CODE]** |
| 8 | **One wall-clock-driven clock (the group's master); streams are told an *instant*, never a delta** | `CSSRReplayGroup::Pump` `SSR_MasterClock.mqh:179-226`; `PumpTo(target)` | This is why `MaxSkewMsc()` is 0 by construction and multi-symbol replay cannot drift. `ctrl.Pump(wall_ms)` exists but no production path uses it. **[CONFIRMED FROM CODE]** |
| 9 | **Integer speed arithmetic with a residue carry** | `SSRReplayClock::Advance` — `scaled = wall*speed + residue; adv = scaled/100; residue = scaled%100` | No floating-point drift over a six-hour session; the same delta sequence gives bit-identical instants. **[CONFIRMED FROM CODE]** |
| 10 | **`ClipBar` clips the *bar* to `hi` while the *ticks* are trimmed to `[lo,hi]`** — two different rules on purpose | `SSR_ReplayController.mqh:269-310` | The forming bar an observer sees must include the part an earlier pump already emitted (it happened, and it is in the high/low), while the ticks must not be re-sent. Merging the two rules corrupts either the candle or the observer's view. **[CONFIRMED FROM CODE]** |
| 11 | **Monotonic tick stamps; the sink hard-refuses a regression** | `SSR_CustomSymbolSink.mqh:313-320` | The only defence against a navigation bug quietly writing a scrambled symbol. **[CONFIRMED FROM CODE]** |
| 12 | **The seed cache never trusts its manifest alone** — `SERIES_*` evidence from the terminal must agree | `SSR_SeedCache.mqh:165-205` | A false negative costs a reseed; a false positive puts the *previous* session's future on this session's chart. The asymmetry is correctly chosen. **[CONFIRMED FROM CODE]** |

Two design choices that read as odd but are correct and should be kept:

- **`Restart()` is `Reset()`**, and `Reset()` keeps bookmarks while dropping checkpoints
  (`SSR_ReplayController.mqh:1520-1527`). Restarting is still the same session. **[CONFIRMED FROM CODE]**
- **Fidelity is per stream, not per group** (`SSR_GroupPort.mqh:463-478`). Forcing FULL_TICK on a
  board where one instrument has no tick history would claim a fidelity that does not exist there.
  **[CONFIRMED FROM CODE]**

---

### F.3 Fidelity: where each mode belongs

#### F.3.1 The three modes as implemented

| Mode | Ticks per M1 bar | Path | Stamp |
|---|---|---|---|
| `SSR_FIDELITY_FULL_TICK` | broker's own | real | real |
| `SSR_FIDELITY_SYNTHETIC_TICK` | `InpTicksPerBar` (default **8**, min 4) | O→L→H→C if `close>=open`, else O→H→L→C (`SSR_TickSynthesizer.mqh:127-128`) | `open + i*59999/(n-1)` (`:147`) |
| `SSR_FIDELITY_BAR` | 1 | close only | `open + 59999` |

#### F.3.2 Where FULL_TICK is *required*

**[RECOMMENDATION]** FULL_TICK is not a luxury setting; it is the only correct mode for three
classes of session, and the product should say so rather than leaving it to a cycle button:

1. **Any session where the trainee places a stop or a target.** The trading engine evaluates
   stops only inside `OnTicks` (evidence in `trading-exec-2`, CONFIRMED). With SYNTHETIC at the
   default 8 ticks/bar, an SL sitting between two path points is evaluated against 8 prices per
   minute, none of which is the bar's true extreme (F.3.4). Fill realism is the whole point of
   the exercise.
2. **Spread-sensitive work (scalping, spread-cost lessons).** `SpreadFor` returns **one** spread
   value for the whole bar (`SSR_TickSynthesizer.mqh:54-67`), so at SYNTHETIC the ask is a rigid
   parallel of the bid for 60 seconds. Spread widening — the thing a news lesson is about — cannot
   be represented at all.
3. **News minutes.** The calendar layer already draws the event (`SSR_Calendar.mqh`); the lesson
   is the path *inside* that minute, which SYNTHETIC replaces with four straight lines.

#### F.3.3 Where SYNTHETIC is acceptable

**[RECOMMENDATION]** Structure and swing practice on M5 and above, where decisions are taken at
bar closes; any window older than the broker's tick depth (which is most of history — see
`data-1`); and the whole of warmup. The last tick of every bar is forced onto the true close
(`SSR_TickSynthesizer.mqh:179-182`), so **bar closes are exact** even at SYNTHETIC — that is the
honest guarantee to advertise, and the one a close-based strategy depends on.

#### F.3.4 The defect that limits SYNTHETIC today

**[CONFIRMED FROM CODE]** The synthesised path only lands *on* the bar's high and low when
`(n-1) % 3 == 0`. `SSR_TickSynthesizer.mqh:137-145`:

```
double u = (n == 1 ? 0.0 : (double)i * 3.0 / (double)(n - 1));
int seg  = (int)MathFloor(u);
if(seg > 2) seg = 2;
double f = u - (double)seg;
double a = (seg == 0 ? k0 : (seg == 1 ? k1 : k2));
double b = (seg == 0 ? k1 : (seg == 1 ? k2 : k3));
double p = a + (b - a) * f;
```

[CONFIRMED FROM CODE — the ladder below is arithmetic over two source constants, not a measurement]
with `k1`/`k2` the two extremes (`:127-128`). The shipped default is `InpTicksPerBar = 8`
(`SSReplayStandalone.mq5:75`), so `n-1 = 7` and `u` steps by 3/7: `0, 0.43, 0.86, 1.29, 1.71,
2.14, 2.57, 3`. No `u` equals 1.0 or 2.0, therefore **neither the high nor the low is ever
emitted**. On a bullish bar the deepest price emitted is `open + 0.857*(low-open)` and the
highest is `max(low + 0.714*(high-low), high - 0.143*(high-close))`.

[CONFIRMED FROM CODE] This is the same arithmetic that `spikes-audits-1` (CONFIRMED, HIGH) verified in
`SSR_SpikeKit.mqh:579`, and the verifier for `spikes-audits-2` (CONFIRMED, MEDIUM) quantified it
for exactly this count: *"With cnt=8 it is 3 of 20"* bars that reach within one point of both
extremes.

Consequences, all **[INFERENCE]** from the above plus the invariants in F.2:

- The candle MetaTrader builds on the replay symbol from those ticks is **narrower** than the
  origin M1 bar, because the chart high can never exceed the highest injected bid.
- `ClipBar` rebuilds the forming bar's O/H/L/C *from the synthesised ticks*
  (`SSR_ReplayController.mqh:287-308`), so the observer's view of the forming bar inherits the
  same narrowing. The whole bar is returned unmodified once `hi >= open+59999` (`:278`), so
  the *observer* is corrected at the bar boundary — but the *chart* is not, because the chart was
  built from ticks.
- A region written in bulk (warmup, jump, weekend skip) shows **exact** OHLC; the region played
  through shows narrowed candles. The same session therefore contains two different renderings of
  the same data, with a visible seam at every jump.

**[RECOMMENDATION]** Two lines of fix, in this order:

1. Constrain the count: `SetTicksPerBar` (`SSR_TickSynthesizer.mqh:106`) should round *up* to the
   nearest `n` with `(n-1) % 3 == 0` — 4, 7, 10, 13, 16, … — and the host default should become
   **10** rather than 8. This makes the extremes exact for every bar at no runtime cost.
2. Independently, guarantee the extremes by construction rather than by arithmetic luck: emit
   `k1` and `k2` as explicit keypoints and distribute the remaining `n-4` ticks along the
   segments. This is the version that survives someone later changing the count.

#### F.3.5 Where BAR is appropriate — and the rule that never fires

BAR is correct for catch-up, and `CSSRFidelityPolicy` already encodes that: `owed >= 10 minutes →
BAR, reason BULK` (`SSR_FidelityPolicy.mqh:35, 120-124`).

**[CONFIRMED FROM CODE]** That rule is unreachable from every control the product exposes.
The host caps a pump delta at `max(4*InpPumpMs, 100)` = 160 ms (`SSReplayStandalone.mq5:2755-2759`),
and the fastest ladder stop is `SSR_SPEED_MAX = 100000` = 1000× (`SSR_Types.mqh:275-342`), so the
largest `owed` any playback pump can produce is 160,000 ms — under a third of the 600,000 ms
threshold. `JumpForward`'s own `EmitWindow` covers only the partial bar (≤ 59,999 ms). `StepBars`
is called with 1 and 10 only (`SSR_Panel.mqh:2293-2296`), and `StepBars(10)` owes exactly
599,999 ms — **one millisecond under the threshold**, which is `core-engine-11`(c). The only
caller that can reach BULK is the IPC publisher, which passes the client's `a1` through
unvalidated (`SSR_Publisher.mqh:278`).

So in practice: catch-up at high speed runs at SYNTHETIC, and a PgDn of ten bars hands
`EmitWindow` ten bars at once — where the pump budget then *discards* the overflow
(`core-engine-1`, CONFIRMED, HIGH).

**[RECOMMENDATION]** Express the threshold in **bars**, not milliseconds — `owed_bars >= 10` —
and evaluate it in `EmitWindow` after `nb` is known. That makes PgDn a bulk moment (which is what
the user asked for), leaves 1000× playback at SYNTHETIC (160,000 ms ≈ 2.7 bars), and removes the
off-by-one entirely.

#### F.3.6 The silent void: FULL_TICK with no ticks

[CONFIRMED FROM CODE for the code path; **[INFERENCE]** for the ranking word "most serious"]
The most serious fidelity defect in the engine is not a degradation but the *absence* of one.
`core-engine-4` (CONFIRMED, HIGH) with its data-layer cause `data-1` (CONFIRMED, HIGH):
`Discover` probes tick availability over **the last 24 hours of held history**
(`SSR_Mt5Providers.mqh:133-139`), the host then selects FULL_TICK for a window that may be years
earlier (`SSReplayStandalone.mq5:1153`), and `EmitWindow`'s FULL_TICK branch consumes a zero-tick
window without comment (`SSR_ReplayController.mqh:349-369`):

```
int n = tp.ReadTicks(m_state.symbol, lo - 1, hi, m_ticks);
...
emitted = n;
m_cursor.Advance(hi, emitted, 0);
return emitted;
```

[CONFIRMED FROM CODE] The clock advances, `Progress()` climbs, the panel chip reads `FULL` — and nothing is drawn and
nothing is published. The degradation path is gated on `tp == NULL` only (`:337-346`), which never
happens for the MT5 source. `CSSRTickProvider::HasTicks(symbol, from, to)` exists
(`SSR_IDataSource.mqh:179`) and has **no caller**.

**[RECOMMENDATION]** Three changes, each small:

1. At `Load`, call `HasTicks(symbol, warmup_first, end)` — the *replay window* — instead of
   accepting `range.has_ticks` from a 24-hour probe.
2. In `EmitWindow`, when `fid == FULL_TICK` and `n == 0`, re-read the window's bars; if bars
   exist, set `SetTicksAvailable(false)`, re-`Decide`, and fall through to the bar path for that
   window. A window with neither ticks nor bars is a genuine gap and stays silent.
3. Record the event in the fidelity ledger (F.4) so the user sees *why* the mode changed.

---

### F.4 Making fidelity transparent to the user

What exists today is honest but thin. `CSSRGroupPort` publishes three fields —
`fidelity` (requested), `fidelity_effective`, `fidelity_note` (`SSR_GroupPort.mqh:110-112`) — and
the panel draws the **effective** value with a `!` suffix when the two differ
(`SSR_Panel.mqh:888-894` chip, `2032-2035` stats line). The comment beside it states the right
principle: *"SHOW WHAT IS RUNNING, NOT WHAT WAS ASKED FOR."* **[CONFIRMED FROM CODE]**

Three gaps:

1. **It is instantaneous, not cumulative.** `Decide()` runs per window; the chip shows the last
   window's answer. A session that degraded for ninety seconds during a catch-up and recovered
   shows nothing afterwards — while `m_degradations` is counted (`SSR_FidelityPolicy.mqh:131-132`)
   and exposed nowhere. **[CONFIRMED FROM CODE]**
2. **A void window is indistinguishable from a quiet one** (F.3.6). **[CONFIRMED FROM CODE]**
3. **Bulk-written stretches are not accounted at all.** Warmup, every jump, every step backward
   through a checkpoint, and the weekend skip reach the chart via `SeedBars` — exact OHLC, zero
   ticks, no observer traffic (`core-engine-3`, `core-sync-1`). Nothing in the UI distinguishes
   "you watched this" from "this was written past you". **[CONFIRMED FROM CODE]**

**[RECOMMENDATION] — the Fidelity Ledger.** Add to `CSSRFidelityPolicy` a small accumulator that
`EmitWindow` and `JumpForward` feed, and publish it through the existing `SSRUiState`:

```
struct SSRFidelityLedger
  {
   long  ms_full_tick;      // replay time served by real ticks
   long  ms_synthetic;      // ... by synthesised ticks
   long  ms_bar;            // ... by one close tick per bar
   long  ms_bulk;           // ... written as bars, never published
   long  ms_void;           // ... consumed with nothing emitted
   long  first_void_msc;    // where the first void started
   int   degradations;
  };
```

Five numbers that already exist as facts inside the loop and are currently thrown away.
The UI cost is one extra line on the Stats sheet plus a colour rule on the existing chip
(`SSR_Panel.mqh:888`): amber when `ms_bulk > 0`, red when `ms_void > 0`. The strong version of
the honesty claim then becomes checkable by the user: *"of your 4h 12m session, 3h 58m was served
tick-by-tick, 14m was fast-forwarded."*

**[RECOMMENDATION]** Alongside it, one sentence in the session report: the effective tick model
(`n` ticks/bar, path O→L→H→C, exact closes, one spread per bar). The product's differentiator is
that it says what it did; the tick model is the biggest thing it currently does not say.

---

### F.5 Future-data leakage prevention

The architecture here is the best part of the engine and should be preserved verbatim: horizon
equals `clock.now`, moved before every read; layer 1 clamps in the controller, layer 2 re-checks
inside each provider; `FilterRates` compares by **open** time so the bar containing the horizon
passes and `ClipBar` handles the partial (`SSR_FutureGuard.mqh`; `SSR_ReplayController.mqh:269-310`).
`Violations()` is a live counter summed into the UI vitals by `SSR_GroupPort.mqh:143`. **[CONFIRMED FROM CODE]**

Known weaknesses, in severity order:

1. **`core-engine-10`** (POTENTIAL_RISK, LOW) — `Load()` disarms the guard for `Discover`
   (`SSR_ReplayController.mqh:764`) and re-arms only on the success path. Any failure between
   those two points leaves an unarmed guard still installed in the source's providers.
   **[RECOMMENDATION]** Re-arm in every failure exit of `Load`, or better, make disarming
   scope-bound: `Discover` is the only operation that needs it.
2. **`core-sync-3`** (CONFIRMED, LOW) — the generic `CSSRBarProvider::NextBarOpen`
   (`SSR_IDataSource.mqh:150-165`) probes *forward* through the guarded `ReadBars`, so it raises
   up to four violations per call and always answers `SSR_INVALID_TIME` from inside a gap. It
   pollutes the leak alarm with false positives — which is worse than a missing alarm, because a
   noisy alarm is ignored. The MT5 provider correctly overrides it with an unguarded `CopyTime`
   on the **origin** symbol (`SSR_Mt5Providers.mqh:302-321`). **[RECOMMENDATION]** Make the base
   class's default a `Fail("provider must override NextBarOpen")` rather than a guarded probe;
   "the gap skip silently never works" is not a safe default.
3. **`strategy-integration-report-6`** (CONFIRMED, LOW) — `CSSRMarketView::Prime()`/`OnRewind()`
   trim on bar-open granularity, so the newest retained bar can hold prices from after the clock.
   The guard protects the *sink*; it does not protect every derived buffer.
   **[RECOMMENDATION]** One shared helper — "trim this bar array to horizon, clipping the last
   bar" — used by the view, the report layer, and any future consumer.
4. **Calendar lines** — `data-6` was refuted (NOT_A_BUG) and is not a defect, but it is the shape
   of the risk: anything drawn from a range wider than the horizon is a leak the guard cannot see,
   because it never passes through a provider. **[RECOMMENDATION]** Any future chart layer that
   draws from future data should take the horizon as an argument, not the window.

**[RECOMMENDATION] — one structural addition.** The guard counts violations but cannot say *what*
leaked. Add `SSRGuardViolation { long requested_msc; long horizon_msc; string where; }` and keep
the last 8 in a ring. The cost is trivial and it converts "violations: 4" — currently
indistinguishable between a real leak and `core-sync-3`'s false positives — into an actionable
line in the flight recorder.

---

### F.6 Determinism

**What is deterministic today [CONFIRMED FROM CODE]:**

- Clock arithmetic is pure integer with a residue carry, so the same delta sequence yields
  identical instants on every machine (`SSRReplayClock::Advance`).
- Tick synthesis is a pure function of the bar, `n`, digits, point and spread mode
  (`SSR_TickSynthesizer.mqh:117-184`). No RNG, no time source.
- The emit window, the guard, `ClipBar` and the cursor are pure functions of `(emitted, now)` and
  the data.
- `SSRRandom` is xorshift64\* with an explicit seed and integer-only state
  (`SSR_Random.mqh:29-74`), so a seeded stream is identical across machines and runs.
- `SSRPickSeed` is documented as **the one place a wall clock may be read**
  (`SSR_Random.mqh:76-89`), and everything downstream is a pure function of its output. That
  discipline is correct and should be defended.

**What is not deterministic, and why it matters:**

1. **The pump budget is derived from wall-clock measurement.** `CSSRPumpBudget::MaxTicks()` is
   4096 until 16 pumps have been measured, then `budget_ms*1000/us_per_tick` clamped to
   [32, 32768] (`SSR_PumpBudget.mqh`). Because `core-engine-1` (CONFIRMED, HIGH) makes the cap
   *discard* bars rather than defer them (`SSR_ReplayController.mqh:398-404` overwrites `nb`,
   which makes the "stop short" branch at `:523-531` dead), **the same session on a slower machine
   loses different bars**. This is the single worst determinism defect in the engine: it turns a
   performance knob into silent data loss that varies by hardware. **[CONFIRMED FROM CODE]**
2. **The idle gap-skip is a function of wall time and pump count, not replay time.** 25 pumps
   with no tick triggers `NextBarAcross` and a bulk `SeekAllTo` (`SSR_MasterClock.mqh:206-219`).
   At the default 8 ticks/bar the synthetic tick spacing is 8,571 replay-ms, so at 1× that
   condition is met *inside every minute* — which is `core-sync-1` (CONFIRMED, HIGH). Whether the
   skip fires depends on timer jitter. **[CONFIRMED FROM CODE]**
3. **`bars_consumed` counts (pump × bar), not bars** — `bars_used++` runs unconditionally at
   `SSR_ReplayController.mqh:472` for a bar that is re-read and re-synthesised every pump
   (`core-engine-5`, CONFIRMED, MEDIUM). The figure therefore encodes the machine's pump rate.
   `core-sync-2` (CONFIRMED, MEDIUM) is the same cause in the spread statistics, and
   `core-sync-4`/`core-engine-9` (CONFIRMED, LOW) the same cause in the metrics.
4. **`RestoreFrom`'s no-fingerprint fallback compares a pump-rate-dependent counter** with a
   bulk-produced one (`SSR_ReplayController.mqh:1856-1863`), so it always warns. The fingerprint
   path (`FingerprintUpTo`) is correct and should become the only path. **[CONFIRMED FROM CODE]**

**[RECOMMENDATION] — the fix set, in order:**

- **Make the budget defer, not drop.** `EmitWindow` should keep `nb` intact and stop the *loop*
  at the cap, so the existing `consumed_to` logic at `:523-531` comes alive and the remainder is
  genuinely owed to the next pump. This is a four-line change and it removes both the data loss
  and the hardware dependence.
- **Separate "bars touched this pump" from "bars completed".** Increment `bars_used` only when
  the bar is consumed whole (`hi >= open + 59999`), and keep a separate `bars_touched` for
  diagnostics. This repairs `core-engine-5`, `core-sync-2`, `core-sync-4` and `core-engine-9` at
  one site.
- **Trigger the idle skip on replay time, not pump count**: skip when
  `now - last_emitted_tick_msc > 2 * 60000` *in replay milliseconds* and the clock sits on a bar
  boundary. This removes the mid-bar bulk write that `core-sync-1` describes.
- **[FUTURE FEATURE] A determinism ledger.** `FingerprintUpTo` already exists
  (`SSR_Fingerprint.mqh` + controller). Publish the running fingerprint as a short hex string in
  the vitals. Two students with the same seed and the same broker history can then compare one
  8-character token and know whether they replayed the same market — which is the thing a class
  report (`SSR_ClassReport.mq5:7`, *"Give everyone the same seed. Same seed, same candles"*)
  currently asserts without evidence.

---

### F.7 Random Mode reproducibility through the seed

The intent is documented well and the primitive is right: an explicit, reported seed rather than
`MathRand()`, because *"a random replay you cannot repeat is a lesson you cannot go back to"*
(`SSR_Random.mqh:5-18`). `CSSRRandomPicker` refuses to pick a start it cannot justify and records
each rejection by name (`SSR_RandomPicker.mqh:143-186`). **[CONFIRMED FROM CODE]**

The promise is nevertheless broken today, in three independent places:

1. **`host-expert-5`** (CONFIRMED, MEDIUM) — a random session does not survive the one-window
   handover. Pass 2 re-runs `BuildSession`; with `InpSeed=""`, `SSRSeedFromText("")` returns 0,
   `SetSeed(0)` substitutes `SSRPickSeed()` (`SSR_RandomPicker.mqh:68-69`), and the session the
   user ends up in is **a different window from the one pass 1 announced**. The seed printed in
   the log reproduces nothing.
2. **`data-3`** (CONFIRMED, LOW) — candidates are drawn *with replacement*
   (`SSR_RandomPicker.mqh:149`), so with a pool of three where one qualifies, 29.6% of seeds
   report "no candidate had enough history" and fall back to a non-random window.
3. **[CONFIRMED FROM CODE]** The seed is not a sufficient key even when it survives. `Pick()`
   consumes `m_rng` in an order that depends on the *pool contents* (the parsed `InpAlsoSymbols`
   text) and lands the start via `m_cat.EarliestStart/LatestStart` (`:157-158`), which depend on
   how much history the broker held **at that moment**. `Ticket()` (`:189-194`) returns only
   `"seed <n>"`. Same seed + one more week of downloaded history = a different session.

**[RECOMMENDATION] — resolve once, replay by ticket.** The seed should stay the *entropy* source
but stop being the *identity* of a session:

- Extend `Ticket()` to the resolved triple, e.g. `SSR1-<seed>-<symbol>-<start_msc>-<minutes>`, and
  make it the thing the panel shows and the user writes down.
- Persist the resolved triple in the handover stash and in `setup.ini` at the moment of the pick,
  and have pass 2 consume the triple rather than re-rolling — this closes `host-expert-5` without
  touching the picker's logic.
- Accept a ticket wherever `InpSeed` is accepted: given a ticket, the picker is bypassed entirely
  and `Load(symbol, start, end)` is called directly. Reproduction then no longer depends on the
  broker's history depth being unchanged.
- Draw candidates **without replacement** (shuffle the pool once with `m_rng`, then walk it) —
  this closes `data-3` and makes the draw a pure function of the seed and the pool.
- Note that `SSRSeedFromText` (`SSR_Random.mqh:94-102`) maps any unparseable text to 0, which
  means "pick a new one". A ticket parser must distinguish "empty" from "malformed" and refuse
  the latter loudly. **[RECOMMENDATION]**

`strategy-integration-report-4` (CONFIRMED, LOW) is the same family: a strategy's per-instance RNG
is seeded once at registration and is never re-seeded on rewind, so a randomised strategy is not
reproducible across a step backward. **[RECOMMENDATION]** Re-seed each strategy's stream from
`(session_seed, strategy_name, epoch)` on every rewind — see the epoch mechanism in F.9.

---

### F.8 Jump, rewind, bookmark, snapshot

#### F.8.1 Step forward

**`core-engine-2`** (CONFIRMED, HIGH) — every step lands the clock on `xx:59.999`, and from there
the formula at `SSR_ReplayController.mqh:1165-1170` yields `target == now`:

```
long base = SSRNextBarOpenMsc(m_clock.now_msc, PERIOD_M1);
long nb   = NextTimelineBarOpen(m_clock.now_msc);
if(nb != SSR_INVALID_TIME && nb > base)  base = nb;
long target = base + (long)(bars - 1) * SSR_MSC_PER_MIN - 1;
```

so `→` works once per play/pause cycle and PgDn advances 9 bars, not 10. The identical formula is
duplicated in `CSSRReplayGroup::StepBars` (`SSR_MasterClock.mqh:341-369`), which is the production
path, so both have it.

**[RECOMMENDATION]** One shared helper in `Common/SSR_Time.mqh`, called by both:

```
long SSRStepTargetMsc(const long now, const int bars, const long next_existing_open, const long end)
  {
   long cur   = SSRBarOpenMsc(now, PERIOD_M1);
   long first = (now >= cur + SSR_MSC_PER_MIN - 1) ? cur + SSR_MSC_PER_MIN : cur;
   if(next_existing_open != SSR_INVALID_TIME && next_existing_open > first)
      first = next_existing_open;            // land on a bar that EXISTS
   long t = first + (long)bars * SSR_MSC_PER_MIN - 1;
   return (t > end ? end : t);
  }
```

From `10:00:00.000`, `bars=1` → `10:00:59.999` (unchanged). From `10:00:59.999`, `bars=1` →
`10:01:59.999` (fixed). The duplicate-formula problem disappears with it.

#### F.8.2 Jump forward

[CONFIRMED FROM CODE] `JumpForward` (`SSR_ReplayController.mqh:1330-1400`) is structurally right: bulk-write everything
strictly before the target's own bar with `SeedBars`, then emit the partial bar as ticks trimmed
to the target so it forms correctly. Two defects sit on it:

- **`core-engine-3`** (CONFIRMED, HIGH) — the bulk range reaches the sink and **never the
  observers**. `StepBackward` routes through it, so every step back replays up to five minutes
  blind to the trading engine: stops inside those bars are never evaluated, and a position the
  rewind restored can survive a stop-out that visibly happened on the chart.
- **`mt5-symbol-1`** (CONFIRMED, HIGH) — `RepairWarmupIfLost()` is called immediately after the
  bulk write (`:1409`) precisely because the terminal drops tick-less warmup bars, but on a
  reused-seed session the sink silently returns `true` without writing
  (`SSR_CustomSymbolSink.mqh:265-270`) while the controller logs "N bars written back". Every
  jump in such a session permanently shortens the HTF context.

**[RECOMMENDATION] — the bulk-publish channel.** Add one optional method to `CSSRTickObserver`:

```
virtual void OnBulkBars(const MqlRates &bars[], const int n, const long to_msc) {}
```

and call it in `JumpForward` immediately after the successful `SeedBars`. The trading engine
implements it by walking each bar's declared path (O→L→H→C / O→H→L→C — the *same* convention
`SSR_TickSynthesizer.mqh:127-128` uses, so the two agree by construction) and evaluating stops
and targets against the extremes, marking such fills **ambiguous** (the flag `trading-exec-5`
already needs). `CSSRMarketView` implements it by appending the bars, which also removes the
host's `PrimeView` workaround at `SSReplayStandalone.mq5:2797`. This is the single highest-value
change in the engine layer: it closes `core-engine-3`, the observer half of `core-sync-1`, and
`strategy-integration-report-1` at one site, without materialising ticks and without giving up
the speed that makes bulk writing worth doing. **[RECOMMENDATION]**

#### F.8.3 Rewind

The design — 64 checkpoints every 5 replay-minutes, restore the nearest at-or-before, then
`JumpForward` to the exact target (`SSR_ReplayController.mqh:1432-1481`) — is sound and should be
kept. Four defects sit on it:

- **`core-engine-7`** (CONFIRMED, LOW) — `RestoreSnapshot` re-seats the cursor only when the sink
  cut *strictly* before the checkpoint (`:1637 if(actual < m_cursor.emitted_msc)`). A checkpoint
  landing exactly on an M1 open therefore loses that bar's open tick, and the rebuilt candle opens
  at the second path point. **[RECOMMENDATION]** Make the rewind unconditional:
  `m_cursor.RewindTo(actual);` — one line, and it is correct in both cases because `RewindTo` sets
  `emitted = actual - 1`.
- **`core-engine-8`** (CONFIRMED, LOW) — `RestoreSnapshot` assigns `m_state` whole (`:1630`), which
  drags the checkpoint's `fidelity`, `speed_x100`, `status` and `last_error` back with it while
  `m_fidelity` (the policy object) and the master clock are not restored. The panel then shows a
  degradation that did not happen. **[RECOMMENDATION]** Snapshot *position*, not *settings*:
  restore `clock.now/start/end`, `cursor`, `timeline`, and leave `fidelity`, `speed` and
  `auto_pause` alone. That is also what makes a checkpoint composable with a live settings change.
- **`core-sync-6`** (CONFIRMED, IMPROVEMENT) — `CSSRSnapshotStore::DropFrom`
  (`SSR_SnapshotStore.mqh:140`) blanks slots without adjusting `m_count`/`m_head`, so rewind depth
  silently shrinks and `Count()` over-reports. **[RECOMMENDATION]** Compact the ring, or move the
  head back to the newest surviving slot.
- **`trading-exec-1`** (CONFIRMED, **CRITICAL**) and **`trading-exec-2`** (CONFIRMED, HIGH) — the
  engine's rewind is correct; the trading engine's response to it is not. `OnRewind(msc)` hands
  over a *time* and nothing else, so positions opened after the cut vanish without their P/L,
  commission and swap being reversed from the balance, and stop/target/trail/MAE mutations made in
  the deleted future survive. This is not a replay-engine defect but it is a replay-engine
  *contract* defect: see F.9(C).

#### F.8.4 Bookmarks

**[CONFIRMED FROM CODE]** Bookmarks are **write-only in the product**. `Bookmark()` is wired
through `CSSRGroupPort::Bookmark` (`SSR_GroupPort.mqh:480-492`) and draws a chart line; but
`GotoBookmark`, `BookmarkLabel` and `BookmarkCount`
(`SSR_ReplayController.mqh:1538-1550`) have **no production caller** — grep finds only
`SSR_T8_Navigation.mq5:244-255` and `SSR_T12_Session.mq5:540`. The user can drop a mark and can
never return to it. They survive into the session file (`SaveInto`/`RestoreFrom`, `:1744-1754`,
`:1815-1819`) and are re-added on restore, still unreachable.

Supporting defects: `chart-6` (CONFIRMED, LOW) — the bookmark vertical lines are never deleted and
survive on the user's own chart after the session; `chart-17` (CONFIRMED, LOW) — `MarkTime` puts
the registry index in the object name, so bookmarks duplicate after a chart closes.

**[RECOMMENDATION]** Three additions to `CSSRReplayPort`/`CSSRGroupPort`, mirroring the existing
sessions dialog exactly (so no new UI idiom): `BookmarkCount()`, `BookmarkLabel(i)`,
`GotoBookmark(i)`. The label is already formatted for display
(`MarkLabel` → `"label  yyyy.mm.dd hh:mm:ss"`). Note the 63-character `OBJPROP_TEXT` ceiling when
drawing the list, and that `GotoBookmark` → `JumpTo` → backward → `StepBackward`, so it inherits
the bulk-publish problem until F.8.2 is fixed.

#### F.8.5 Saved position

`CSSRPositionFile` keys on the origin symbol alone (`SSR_PositionFile.mqh:28`,
`core-sync-7`, POTENTIAL_RISK, LOW), so two slots replaying the same symbol overwrite each other.
**[RECOMMENDATION]** Key on `symbol + slot + session-name`; the sanitiser is already there.
`ui-port-session-3` (CONFIRMED, HIGH) is the matching defect one layer up: `Restore` never checks
that the streams actually reached the saved instant and cannot rewind to it.

---

### F.9 A professional Market Replay Control System

This fits `CSSRReplayController` and `CSSRReplayGroup` as they stand. Nothing below replaces a
class; every item is an addition to, or a correction inside, an existing seam. **[RECOMMENDATION]**

**(A) One transport vocabulary, one implementation each.**
The verbs exist three times today (controller, group, `CSSRGroupPort`), and `StepBars`' formula is
duplicated between controller and group with the same off-by-one (`core-engine-2`). Rule: the
**group** owns transport semantics, the **controller** owns emission, shared *arithmetic* lives in
`Common/SSR_Time.mqh` (F.8.1). `CSSRGroupPort` stays a thin adapter. The controller's own
`StepBars`/`SeekTo`/`Pump(wall_ms)` remain for tests and stay out of the production path — which is
already true (`core-engine.md` §0).

**(B) A published transport result, not a bool.**
Every verb currently returns `bool`. The panel therefore cannot tell the user "you asked for
10:46:30 and landed on 10:46:00 because rewind is bar-granular", or "6 of 10 bars are still owed".
Introduce one small struct returned by the group's verbs:

```
struct SSRTransportResult
  {
   bool  ok;
   long  requested_msc;
   long  landed_msc;
   int   bars_emitted;
   int   bars_bulk;        // written, not published
   int   bars_owed;        // deferred by the budget
   ENUM_SSR_FIDELITY served;
   string note;            // one line, <= 49 chars for the panel
  };
```

The 49-character ceiling is the panel's real constraint (`chart-7` confirms the existing
`LeakGuard::Advice` overruns its only consumer), and the 63-char `OBJPROP_TEXT` limit is the hard
one. This single change is what turns silent navigation into legible navigation.

**(C) A rewind epoch, so rewind is a contract rather than a hint.** **[RECOMMENDATION]**
The controller gains `long m_epoch`, incremented on every `RestoreSnapshot`, backward `SeekTo`, and
`Reset`; `OnRewind(msc)` becomes `OnRewind(msc, epoch)`. Every observer that keeps mutable derived
state — the trading engine's balance, stops, trail peaks, MAE/MFE; a strategy's RNG stream; the
market view's buffer — stamps each mutation with `(epoch, replay_msc)` and unwinds mutations at or
after the cut. This is the mechanism that closes `trading-exec-1` (CRITICAL),
`trading-exec-2` (HIGH) and `strategy-integration-report-4` in one place instead of in each
observer's private guesswork, and it is the piece the current `SSRSnapshot`'s four unused trading
fields (`open_positions`, `closed_trades`, `virtual_balance`, `virtual_equity` — filled by nothing)
were clearly reaching for.

**(D) The bulk-publish channel** — `OnBulkBars` — exactly as specified in F.8.2. Bulk writing stays
the fast path; it stops being an invisible path.

**(E) The fidelity ledger** — exactly as specified in F.4 — plus the per-window tick-availability
check from F.3.6. Fidelity stops being a chip that shows the last window and becomes a session
property the user can read and the report can print.

**(F) A budget that defers.** F.6, item 1. Until this lands, the engine's own performance
protection is a data-loss mechanism whose behaviour depends on the machine.

**(G) A session ticket.** F.7. The identity of a replay session becomes
`(symbol, start, end, seed)` rather than `(seed)`, and reproduction stops depending on how much
history the broker happened to hold.

**(H) Navigation completeness.** Bookmarks reachable (F.8.4); jump granularity announced (B);
saved position keyed per slot (F.8.5); `Restore` verified against the instant it claims
(`ui-port-session-3`).

**Order of work** — by (defect severity × blast radius), not by size:

| # | Change | Closes | Size |
|---|---|---|---|
| 1 | Budget defers instead of dropping | `core-engine-1` (HIGH) + the worst determinism hole | ~4 lines |
| 2 | Shared `SSRStepTargetMsc` | `core-engine-2` (HIGH), the duplicated formula | ~15 lines |
| 3 | `OnBulkBars` channel | `core-engine-3` (HIGH), `core-sync-1` observer half, `strategy-integration-report-1` (HIGH) | one method + 2 implementations |
| 4 | Per-window tick check + void detection | `core-engine-4` (HIGH), `data-1` (HIGH) | ~20 lines |
| 5 | Rewind epoch on `OnRewind` | `trading-exec-1` (CRITICAL), `trading-exec-2` (HIGH) | contract change + engine work |
| 6 | Ticks-per-bar constrained to `(n-1)%3==0`, default 10 | the synthetic-path narrowing (F.3.4, `spikes-audits-1`) | ~3 lines |
| 7 | Unconditional `RewindTo(actual)`; restore position not settings | `core-engine-7`, `core-engine-8` | ~5 lines |
| 8 | `bars_used` counts completed bars only | `core-engine-5`, `core-sync-2`, `core-sync-4`, `core-engine-9` | ~5 lines |
| 9 | Bulk threshold in bars; idle skip on replay time | `core-engine-11`(c), `core-sync-1` trigger half | ~10 lines |
| 10 | Fidelity ledger + transport result + bookmark navigation | the transparency gaps (F.4, F.8.4) | new, additive |

---

### F.10 Two things not to do

**[RECOMMENDATION]** Do not replace the custom-symbol sink with a canvas or indicator-drawn
replay. Everything that makes this product worth using — the trainee's own indicators, templates,
objects, timeframe switching, crosshair measurement — exists only because the replay is a real
symbol. The costs already paid (BID mode, 24/7 sessions, monotonic stamps, bar-granular truncate,
the seed cache) are sunk and correct.

**[RECOMMENDATION]** Do not raise fidelity by raising `InpTicksPerBar` alone. At SYNTHETIC the
chart advances once per synthetic tick — 8 times per replay minute at the default — so at 1× the
chart moves about every 7.5 seconds of wall time, and `core-sync-1`'s idle detector fires inside
that silence. More ticks makes the motion smoother and the extremes no more accurate while the
count stays off the `(n-1)%3==0` lattice (F.3.4). Fix the lattice first, then the count.

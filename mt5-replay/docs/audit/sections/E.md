## E. PERFORMANCE RISKS

Scope: object writes, redraw, timer workload, tick throughput, history loading,
`CustomTicksAdd`/`CustomRatesUpdate`, snapshot cost, rewind cost, memory.

Everything in this section is either (a) a number the codebase itself records as
**measured**, (b) arithmetic derived from constants in the source, or (c) an
**unmeasured** structural cost. Each is tagged. The author has never run this on
an MT5 terminal, so no number here was reproduced during the audit.

---

### E.0 What has actually been measured

There are exactly two bodies of measurement in this project, and neither is a
clean profile of the product as it ships.

**1. One terminal run, quoted in a comment.** `MQL5/Include/SSReplay/Ui/SSR_Widgets.mqh:31-38`:

```
//| because nothing had been measured slow. The user's run measured   |
//| it: 561 object properties written per STILL frame, and a mean     |
//| repaint of 39.05 ms - against an engine that pumps every 40. One  |
//| repaint was eating a whole pump interval...
//| nothing changed that is 561 writes turned into 77 lookups.        |
```

[CONFIRMED FROM CODE] **What is confirmed from code is that the comment at
`SSR_Widgets.mqh:31-38` says so** — not that the measurement is sound. This
section's own thesis (E.9) is that the measurement layer cannot be believed, and
it does not exempt the one measurement it inherits. **[INFERENCE, resting on that
comment]** These are the only end-to-end product numbers that exist: **561
property writes per still frame**, **39.05 ms mean repaint**, and **561 writes →
77 lookups** once the widget cache elides them. Provenance is a user's run,
recorded in prose; there is no CSV, no run id, and no way to re-derive it here.
It implies roughly **0.07 ms per `ObjectSet*`** on that machine — the only unit
cost this project has. [INFERENCE] Every per-frame write count below should be
read against that unit, not against a guess.

**[INFERENCE] One reconciliation, so two sections do not hand the reader two
baselines.** Sections M.1.2 and N.11.2 use **~586** writes for "today's frame",
not 561. The two are not in conflict and neither is wrong: 561 is the figure the
`SSR_Widgets.mqh:31-38` comment records for the repaint that motivated the cache,
and ~586 is M.1.2's **derivation** for the current rail layout — it is tagged
`[INFERENCE, from two CONFIRMED findings plus the arithmetic]` there and shows its
working. Read 561 as the inherited measurement and ~586 as the current estimate;
E.10's ranked list and N.11.2's ledger are therefore about the same frame, one
measured once and one re-derived.

**2. The 17 spikes** (`MQL5/Scripts|Services|Indicators/SSReplay/Spike/*`,
harness `Spike/SSR_SpikeKit.mqh`). These were designed to produce the product's
performance budgets — B2 `optimal_batch_size` "lock this into Feeder",
B4 `copyticksrange_week_return` "sets the page size for TickSource",
A3 `avg_rebuild_time` "feeds the Reset budget", D4 `step_back_interactive`
"whether Previous Candle is a button", D1 `bars_per_sec` "HistoryLoader chunk
size" (`docs/audit/maps/spikes-audits.md` §4). **Section E.9 shows that most of
those specific numbers are invalid as published.** No spike result CSV is present
in the repository, so not one of those budgets has a value here either way.

Everything else in this section is **unmeasured**.

---

### E.1 UI repaint is the dominant cost, and the cache that was built to fix it is defeated every frame

The panel paints at 10 fps, not at pump rate. `SSReplayStandalone.mq5:3063`
gates `g_panel.Render()` on `now_ms - g_panel_paint >= 100`, and the comment at
2960-2973 explains why: at 25 fps "the two compete, the terminal goes sluggish,
and a sluggish terminal is one that answers clicks late or not at all."
[CONFIRMED FROM CODE] That decision is sound and should be preserved.

What was not fixed is what each of those 10 frames costs.

**E.1.1 `DrawSheet` deletes and recreates the whole visible sheet every frame —
finding `ui-panel-1` (MEDIUM, CONFIRMED).** `SSR_Panel.mqh:1270` begins with an
unconditional `HideSheets()`, whose id list (`:1301-1316`) contains the ids of
*every* sheet **including the one about to be drawn**. Counted from source:
70 named `Remove()` + 4×3 meter parts + `SSR_POS_MAX`(12)×6 row parts =
**154 `Remove()` calls per frame**, each an `ObjectDelete` plus a `Forget()`
(`SSR_Widgets.mqh:628-635`), followed by ~20-25 `ObjectCreate` and their full
property writes to rebuild what was just deleted. [CONFIRMED FROM CODE]

Both caches are defeated by construction: `CSSRPanel::Text()` requires
`m_w.Exists(id)` (`:194`) and `CSSRWidgets::Same()` ends in `ObjectFind >= 0`
(`SSR_Widgets.mqh:80-88`) — and the object was deleted moments earlier. At 10 fps
that is **~1,540 `ObjectDelete` + ~1,540 `Forget()` per second** before any draw
work. [INFERENCE from the counts above]

**E.1.2 `HideBody(false)` invalidates ~44 more objects every frame — finding
`ui-panel-2` (MEDIUM, CONFIRMED).** `SSR_Panel.mqh:729` runs on every
non-collapsed frame; `CSSRWidgets::Hide` writes `OBJPROP_TIMEFRAMES` and then
calls `Forget(n)` **unconditionally** (`SSR_Widgets.mqh:616-626`) because
visibility is not in the fingerprint. Lines 732-734 and 750-751 then redraw
exactly those objects, so `Same()` fails for each and `Rect`/`ButtonC` execute
all nine writes (`SSR_Widgets.mqh:211-220, 377-386`). The 20-cell speed groove
alone is **22 objects × 9 writes = 198 writes per frame**; the finding's estimate
for the whole block is **~400 property writes per frame**. [CONFIRMED FROM CODE
for the mechanism and the 9-writes-per-object constant; the 400 total is
arithmetic, unmeasured]

**E.1.3 The key card is torn down and rebuilt 10×/s while it is open — finding
`ui-panel-12` (LOW, CONFIRMED).** `SSR_Panel.mqh:776` calls `m_keys.Show(m_chart)`
on every frame while the card is up; `CSSRKeyCard::Show` (`SSR_KeyCard.mqh:55-104`)
opens with `m_w.RemoveAll()` — `ObjectsDeleteAll` + `ForgetAll` — then recreates a
rectangle and ~40 labels, and `SSRKeyBindings` re-`ArrayResize`s a 22-entry table
each time (`SSR_Keys.mqh:112-122`). ≈41 deletes + 41 creates + ~450 writes per
frame, on the same thread as the pump. The *redraw* is required (creation order is
the only z-order, invariant I2); the *destructive* implementation is the cost.
[CONFIRMED FROM CODE]

**E.1.4 The one uncached primitive is the one the user types into — finding
`ui-panel-11` (MEDIUM, POTENTIAL_RISK).** `CSSRWidgets::Edit` has no cache at all
and writes nine properties unconditionally (`SSR_Widgets.mqh:305-319`), while
`HideSheets` hides the tag box and `SheetTrade` re-shows it on every frame
(`SSR_Panel.mqh:1298-1299`, `:1375-1376`). Whether MetaTrader drops focus or
keystrokes when `OBJPROP_TIMEFRAMES` is toggled on a focused `OBJ_EDIT` cannot be
established from source — **POTENTIAL_RISK**, not a confirmed failure. The cost
itself (9 writes/frame + 2 visibility writes) is confirmed.

**E.1.5 A visible symptom of the same mechanism — finding `ui-panel-5` (MEDIUM,
CONFIRMED).** Slots 12 and 17 both write the object `setuprow` at the same
coordinates (`SSR_Panel.mqh:1402` and `:1432`). Because `HideSheets` deletes it
first, `Text(12)` always writes and `Text(17)` almost always takes its early
return, so `order_why` is on screen for one frame (~100 ms) and then gone. This is
not merely a paint-budget issue: it is a user-facing message that the repaint
strategy eats. [CONFIRMED FROM CODE]

**E.1.6 The cache can degrade permanently — finding `ui-plumbing-6` (LOW,
CONFIRMED).** `Slot()` (`SSR_Widgets.mqh:58-77`) stops at the first free-or-matching
slot with a probe run of 8; `Forget()` (`:103`) guards on `m_ck[k] == name` and
therefore clears **nothing** when an earlier deletion in the probe chain has freed
the home slot, after which `Keep()` writes a second copy and the old one is
stranded. The panel performs exactly that Hide-then-redraw pattern 10×/s on
`stflt`/`stopen`/`stspread`/`stfid` (`SSR_Panel.mqh:1937-1940`) and on 5 tabs +
20 speed cells + 2 slider parts (`:2091-2098`). With ~200-260 distinct `SSRP_`
names in a 512-slot table, a filled 8-probe run makes `Slot()` return −1, and
every object hashing into it takes its full 6 or 9 writes forever — i.e. it decays
back toward the 561-write frame the cache exists to prevent. **Unmeasured how long
that takes.**

**E.1.7 A latent cache miss — finding `ui-plumbing-8` (IMPROVEMENT, CONFIRMED).**
`Label()`'s fingerprint folds the font to `StringLen(font)` (`SSR_Widgets.mqh:232`).
Harmless today because `SSR_FONT` and `SSR_FONT_MONO` are both `"Tahoma"`
(`SSR_Theme.mqh:424-425`); it becomes a wrong-glyph bug the day someone splits
them, which `SSR_Theme.mqh:29-31` explicitly anticipates.

**E.1.8 Stale documentation that will misdirect the next optimisation.**
`SSR_Panel.mqh:2998-3000` says "Buttons and rectangles have no cache at all, so
this [`PaintWrites()`] is the real floor of the paint." That is false as written:
`Rect` (`SSR_Widgets.mqh:195-222`) and `ButtonC` (`:358-400`) both call `Same()`
and both `Keep()`. Only `Edit` is uncached. [CONFIRMED FROM CODE]
[RECOMMENDATION] Correct the comment before anyone optimises against it.

---

### E.2 Object write accounting, as the code stands

Unit costs are exact, from `SSR_Widgets.mqh` (all [CONFIRMED FROM CODE]):

| primitive | writes when it actually draws | cached? |
|---|---|---|
| `Rect` (`:195`) | 9 (+`Common()` on create) | yes |
| `ButtonC`/`Button` (`:358`) | 9 | yes |
| `Label` (`:225`) | 6 | yes (font by length only) |
| `Edit` (`:288`) | 9 (+1 for text) | **no** |
| `Slider` | `Rect` + 20×`ButtonC` + `Rect` = 22 objects | per-part |
| `Meter` | 3 `Rect` | per-part |
| `Group` | 2 `Rect` + 1 `Label` | per-part |

Chart-side objects do **not** go through `CSSRWidgets` and have no cache at all:
`CSSRTradeLines::Level` (`SSR_TradeLines.mqh:71-95`) writes **6 properties
unconditionally** per level per call, and `Ensure` (`:100-151`) writes 6 plus a
`SELECTED` re-assert. `DrawPosition` (`:383`) calls `Level` up to three times
(entry/SL/TP) per position and performs **two `ChartGetInteger` calls per
position** (`:416-418`), and the sweep runs every 5th pump. [CONFIRMED FROM CODE;
total cost unmeasured]

`CSSRTradeLines::EndPositions` (`:445-470`) is `O(HLINE objects × positions drawn
this pass)`: it walks `ObjectsTotal(m_chart, 0, OBJ_HLINE)` backwards, does
`StringSubstr`/`StringFind`/`StringToInteger` per object, then a linear scan of
`m_seen` per object. With 30 open positions (90 `SSR_POS_*` lines) that is ~90
name parses × 30 comparisons every 200 ms. [CONFIRMED FROM CODE; unmeasured]

---

### E.3 `ChartRedraw`

38 `ChartRedraw` call sites exist across `MQL5/Include` and `MQL5/Experts`.
[CONFIRMED FROM CODE] The two that matter on the hot path:

* `CSSRPanel::Render()` ends in `ChartRedraw(m_chart)` (`SSR_Panel.mqh:826`) —
  10×/s, enforced by audit A20.
* `CSSRChartManager::Redraw()` (`SSR_ChartManager.mqh:531-583`) — one
  `ChartRedraw` per managed chart, plus a conditional `ChartNavigate(CHART_END)`
  only when the newest **M1** bar changed *and* `ViewOffset > 0`.

Two throttles stack and one of them is dead. `SSR_REDRAW_MIN_INTERVAL_MS = 100`
(`SSR_ChartTypes.mqh:21`) is the manager's own floor, but the host only calls
`g_charts.Redraw()` on `g_slow_tick % 5` (`SSReplayStandalone.mq5:2828`), i.e.
every **200 ms** at the default `InpPumpMs = 40`. The 100 ms floor therefore never
fires except on `force`. [INFERENCE — arithmetic from the two constants]

**Finding `chart-2` (MEDIUM, CONFIRMED): secondary-symbol charts are never
redrawn at all.** `g_charts2[i].Redraw()` appears nowhere; the host calls only
`g_charts2[i].Sync()` (`SSReplayStandalone.mq5:2830`). At `SSR_FIDELITY_BAR` no
tick arrives to repaint them either — the host's own comment (2825-2827) says
`Redraw` "is the only thing that moves the chart at bar fidelity." A multi-symbol
board therefore shows a still picture on every instrument but the primary. This is
a *correctness* symptom of a *performance* decision (redraw is per-instance and
only the primary instance is driven).

[CONFIRMED FROM CODE for the call sites and the cadence; the cost is explicitly unmeasured]
Also on the 200 ms cadence: `g_publisher.Publish()` for every stream,
`g_charts.Sync()`, `g_charts2[i].Sync()`, and — when blind mode is on — a
`g_blind.Apply()` loop over **every managed chart, every 200 ms**
(`SSReplayStandalone.mq5:2821-2823`). The comment calls re-application free
because it is idempotent; idempotent is not free, and the cost is unmeasured.

---

### E.4 Timer workload

`EventSetMillisecondTimer(InpPumpMs)` with `InpPumpMs = 40` → **25 `OnTimer`
entries/second**. Cadences, from `SSReplayStandalone.mq5:2447-2897`
[CONFIRMED FROM CODE]:

| cadence | at 40 ms | work |
|---|---|---|
| every pump | 40 ms | `g_shots.Flush()`, `g_first.Tick()`, `g_group.Pump(delta)`, `RecordFlight`, `g_publisher.Poll()`, trade-line `Poll` + `NoteLineDistances` |
| `% 5` | 200 ms | `Publish()` ×streams, `Sync()`, blind re-apply per chart, `Redraw()`, trade-line position sweep + `EndPositions` |
| `% 25` playing / `% 250` paused | 1 s / 10 s | `PrintVitals()` |
| `% 50` | 2 s | `g_charts.ScanLeaks()` |
| ≥100 ms since last | 100 ms | `PollClicks()` then `Render()` |

**E.4.1 The starvation cap discards time rather than repaying it.** `delta` is
capped at `MathMax(4*InpPumpMs, 100)` = 160 ms (`:2754`), and anything above the
cap increments `g_starved` and is **dropped**. [CONFIRMED FROM CODE] Under UI
pressure the replay therefore silently runs slow rather than catching up — which
is the correct choice for a replay tool, but it means `g_starved` is the only
signal that the machine could not keep up. `PrintVitals` emits a LATE line when
`g_starved > 0` (`:2311`). [RECOMMENDATION] Treat a non-zero `g_starved` as the
project's standing performance alarm; nothing else in the product reports paint
cost at runtime.

**E.4.2 `InpPumpMs` has no bound — finding `host-expert-15` (LOW,
POTENTIAL_RISK).** It reaches `EventSetMillisecondTimer` raw at `:1574` and the
watchdog re-arms with the same unvalidated value at `:3149`, so a rejected
interval cannot be recovered from. Whether `EventSetMillisecondTimer(0)` is
refused or coerced to the terminal's floor is unverifiable from source; the
absence of validation is confirmed.

**E.4.3 Screenshots are taken synchronously inside the timer pass.**
`CSSRShotBook::Flush()` (`SSR_ShotBook.mqh:231-257`) is called at the top of
`OnTimer` and loops over the whole queue, taking each `ChartScreenShot` up to
1600×900 (`SSR_SHOT_W_MAX`/`H_MAX`, `:48-49`) inline. A burst — e.g. `CloseAll`
with a dozen positions — performs a dozen synchronous PNG encodes inside one
timer beat. The size bound is deliberate — the comment at `:45-47` says "a 4K
chart would write megabytes per trade" — but the *burst* is not bounded.
[CONFIRMED FROM CODE that the loop is unbounded per pass and synchronous; the
wall cost of `ChartScreenShot` is **unmeasured**.] Related:
finding `trading-analytics-15` (IMPROVEMENT, POTENTIAL_RISK) — the shots are
taken on the chart the panel is drawn on, so every PNG also contains the panel.

---

### E.5 Tick throughput, `CustomTicksAdd` and `CustomRatesUpdate`

**E.5.1 The injection rate is small — smaller than the spikes assumed.**
Arithmetic from source constants [INFERENCE, each input CONFIRMED FROM CODE]:

* `CSSRReplayClock::Advance` scales wall time by `speed_x100/100`
  (`SSR_ReplayClock.mqh:99-101`).
* Top of the speed ladder is `SSR_SPEED_MAX = 100000` = **1000×**
  (`SSR_Types.mqh:131, 298`).
* `delta` is capped at 160 ms (E.4.1), so one pump advances at most
  160 × 1000 = 160,000 replay-ms ≈ **2.67 M1 bars**.
* Default `InpTicksPerBar = 8`, floored at 4 by `SetTicksPerBar`
  (`SSR_TickSynthesizer.mqh:106`).

That is **≈21 synthetic ticks per pump, ≈535 ticks/s at maximum speed and default
fidelity** — against B2's own gates of `throughput_target ≥ 2000 t/s` and
`throughput_floor ≥ 500 t/s`. In other words, on the shipped speed ladder the
`CustomTicksAdd` path is not the bottleneck; the repaint path is. [INFERENCE]
This is the single most important framing correction in this section: B2's
`optimal_batch_size` ("lock this into Feeder") answers a question the shipped
engine does not ask, because the engine never offers a 50,000-tick batch.

**E.5.2 Write chunking is fixed and conservative.**
`SSR_RATES_CHUNK 10000` and `SSR_TICKS_CHUNK 4096`
(`SSR_CustomSymbolManager.mqh:32, 37`); `WriteBars` (`:593-636`) copies each slice
element-wise into a local array before `CustomRatesUpdate`, and `AddTicks`
(`:646-697`) slices at 4096 per `CustomTicksAdd`. The comment marks 4096 as a
"safety bound, not throughput knob". [CONFIRMED FROM CODE] The element-wise copy
per slice is an extra O(n) pass that a `ArrayCopy` would avoid;
[RECOMMENDATION] worth a look, but **no measurement exists** to say it matters.

**E.5.3 Per-pump emit work repeats on the forming bar — finding `core-engine-5`
(MEDIUM, CONFIRMED).** `EmitWindow` re-reads and re-synthesises the M1 bar
containing `now` on every pump (needed for `ClipBar`), and then trims the
synthesised ticks to `[lo, hi]` (`SSR_ReplayController.mqh:437-460`). At 1×
(40 ms windows against 8 ticks spread over 59,999 ms) **most pumps synthesise 8
ticks and keep none**. The CPU cost is small; the consequence recorded in the
finding is that `bars_consumed` and `SpreadBarsRecorded`/`SpreadBarsFixed` are
inflated by the same factor, so the panel's "Bars" figure and the session summary
are not usable as load indicators.

**E.5.4 Performance feeds back into correctness — finding `core-engine-1` (HIGH,
CONFIRMED).** `CSSRPumpBudget` derives the per-pump ceiling from *measured*
µs/tick: `MaxTicks() = budget_ms*1000/us_per_tick` clamped to `[32, 32768]`,
`budget_ms` default 12.0, uncalibrated fallback 4096
(`SSR_PumpBudget.mqh:25-79`). `MaxBars = MaxTicks/ticks_per_bar`, so **512 bars
uncalibrated** — a cap that the shipped ladder (E.5.1, ≤2.67 bars/pump) can never
reach. But if a terminal measures 400 µs/tick, `MaxTicks` clamps to 32 and
`MaxBars(8)` becomes **4**. `EmitWindow` then *overwrites* `nb` with the cap
(`SSR_ReplayController.mqh:398-404`), which makes the later "stop short" test
`(first + bars_used) < nb` (`:524`) unreachable, so the cursor advances to `hi`
anyway — the bars above the cap are **dropped, not deferred**, and the comment at
`:519-522` describes behaviour the code does not have. A slow terminal therefore
produces a chart with holes and unevaluated SL/TP, reported to the user as
"deferred". This is the one place where a performance number silently changes what
the product does.

**E.5.5 An empty range costs 20 seconds.** `CSSRMt5SeriesGate::Ensure`
(`SSR_Mt5Providers.mqh:146-180`, per `docs/audit/maps/data.md:228`) treats only
`got > 0` as success, so a range that legitimately holds zero bars (a weekend, a
holiday) burns the whole 20 s timeout and then fails, with no
`SERIES_SYNCHRONIZED` early-out. [CONFIRMED FROM CODE per the map; unmeasured in
wall time, but the timeout constant is the cost.]

---

### E.6 History loading and seeding

* `CSSRBarWindow` holds `SSR_WINDOW_BARS_DEFAULT = 20000` M1 bars in memory
  (`SSR_BarWindow.mqh:35`), with `SSR_WINDOW_LOAD_TIMEOUT_MS 15000` and
  `SSR_WINDOW_RETRY_SLEEP_MS 50`. [CONFIRMED FROM CODE]
* **The hot read path is good and should be preserved.** `CSSRBarWindow::Read`
  (`:256-286`) does a **binary search** for the first bar at or after `from_msc`,
  then a bounded copy — `O(log n + k)`, never a terminal round trip. Coverage is
  recorded as the *requested* range, not the returned span, explicitly so a sparse
  answer does not "reload on every pump" (`:240-245`). [CONFIRMED FROM CODE]
* Tick reads page with `SSR_TICK_PAGE_GUARD = 64` pages and a **separate** retry
  budget (200 retries / 15 s) so async retries cannot consume the page budget
  (`SSR_Mt5Providers.mqh:38`, map `data.md:246-249`). [CONFIRMED FROM CODE]
* Warmup seeding is bulk: `SeedWarmup` does one `ReadBars` over the whole warmup
  range and one `SeedBars` (`SSR_ReplayController.mqh:854-906`), timed into
  `m_metrics.RecordSeed` and fed back to the catalogue every 50 pumps
  (`SSReplayStandalone.mq5:2845-2849`) so the next session's cost quote comes
  from this machine. That feedback loop is the right design. [CONFIRMED FROM CODE]
* The seed cache (`SSR_SeedCache.mqh`) removes the warmup read entirely on a hit —
  `NeedsWarmup()` is `!m_reused_seed`, and the controller then skips the data-layer
  read (`map mt5-symbol.md §5, 106`). This is the largest *existing* win on the
  startup path. **Its size is unmeasured**, because D1 (the seed spike) publishes
  an invalid rate — see E.9.
* Caution: finding `mt5-symbol-1` (HIGH, CONFIRMED) — warmup repair after a jump
  is skipped whenever the seed was reused from cache. The performance win and that
  defect are on the same code path.

---

### E.7 Snapshot cost and rewind cost

**Snapshots are cheap, and that is confirmed.** `TakeSnapshot`
(`SSR_ReplayController.mqh:1594-1603`) copies five flat structs — state, clock,
cursor, timeline, label. No file I/O, no bar read, no fingerprint. It runs when
`m_snaps.IsDue()` — first pump after Load/Reset, then every 5 replay-minutes into
a 64-entry ring (`SSR_SnapshotStore.mqh:36`). [CONFIRMED FROM CODE]

The expensive sibling is **not** on that path: `FingerprintUpTo`
(`:1677-1694`) does a full `ReadBars` over `[start_msc, now]` and is called only
from session save (`:1736`) and resume verification (`:1847`). With the default
`InpReplayBars = 2000` that is a 2,000-bar read at deinit; it scales linearly with
session length. [CONFIRMED FROM CODE; wall cost unmeasured]

**Rewind is three operations, and only the middle one is bounded.**
`StepBackward` → `NearestAtOrBefore` → `RestoreSnapshot` → `sink.TruncateFrom`
→ `JumpForward(target)`:

1. `CSSRCustomSymbolManager::Truncate` (`:712-744`) — one `CustomRatesDelete` plus
   one `CustomTicksDelete`, both cutting at the same M1 open.
2. Struct restores — free.
3. `JumpForward` (`SSR_ReplayController.mqh:1333-1420`) — one `ReadBars` over the
   skipped span into a single array, `FilterRates`, then `SeedBars` → `WriteBars`
   in 10,000-bar slices; the partial bar is then re-emitted as ticks through
   `EmitWindow`. Back-navigation via a checkpoint replays **up to 5 replay-minutes
   of bars in bulk** (map `core-engine.md:147`).

[CONFIRMED FROM CODE] So a one-candle step back is: two `Custom*Delete` calls plus
a bulk re-seed of at most 5 minutes. **How long that takes is unknown**: the spike
built to answer it (D4) is invalid — see E.9 — and A3's `avg_rebuild_time`,
labelled as feeding the Reset budget, times a flag rather than the work.

[CONFIRMED FROM CODE] Finding `core-sync-6` (CONFIRMED, IMPROVEMENT) is the storage-side consequence:
`SnapshotStore::DropFrom` (`SSR_SnapshotStore.mqh:140-160`) leaves holes without
adjusting `m_count`/`m_head`, so after stepping back through *k* checkpoints the
next *k* checkpoints overwrite the **oldest survivors** instead of refilling the
holes — rewind depth silently drops to 64−*k* until a full wrap, while `Count()`
still reports 64.

---

### E.8 Memory

All [CONFIRMED FROM CODE] for the allocation sites; totals are [INFERENCE].

* `CSSRBarWindow`: 20,000 `MqlRates` ≈ **1.2 MB per stream** (`MqlRates` is 60
  bytes). With the primary plus `SSR_EXTRA_STREAMS` extras, ~4-5 MB of M1 cache.
* `CSSRReplayController::m_ticks` is a member array resized **upward only**
  (`SSR_ReplayController.mqh:416-421`); it never shrinks for the controller's
  lifetime. At the uncalibrated cap that is 4,096 `MqlTick` ≈ 240 KB per stream.
  The synthesizer's contract (`SSR_TickSynthesizer.mqh:112-115`) is that the
  caller pre-sizes, "allocating inside a per-bar call is the kind of thing that
  quietly costs a third of the throughput budget" — respected.
* Per-pump transient allocation: `EmitWindow` `ArrayResize`s **three** local
  arrays (`seg_at`, `seg_len`, `seg_bar`) on every call — 75 resizes/second at the
  default cadence (`SSR_ReplayController.mqh:424-431`). Small, but it is on the
  hot path and it is the only per-pump allocation left. [RECOMMENDATION] Promote
  to members alongside `m_ticks`; **no measurement exists** to size the gain.
* `CSSRWidgets` cache: 512 slots × (string name + long + string text) per widget
  instance, and there are nine prefixes in use (`SSRP_ SSRS_ SSRD_ SSRSD_ SSRK_
  SSRX_ SSRF_ SSRV_ SSRR2_`). Bounded and small; the risk is slot exhaustion
  (E.1.6), not bytes.
* `CSSRShotBook`: up to `SSR_SHOT_MAX = 500` PNGs at up to 1600×900 per run on
  disk (`SSR_ShotBook.mqh:43, 48-49`). Disk, not RAM, and capped with a log line.
* Calendar items are hard-bounded at 300 (`ArrayResize(m_items, 300)`, map
  `data.md:417`).
* D3 (`SSR_D3_SustainedRun.mq5`) exists to answer "does memory drift over 120
  minutes" and records `memory_stable` — **no result is present in the repo**, and
  its companion throughput gate is invalid (E.9). Memory drift is therefore
  **unmeasured**.

---

### E.9 The measurement layer itself is the biggest performance risk

Every budget this product quotes comes from a spike, and the verified findings
show most of those specific numbers cannot be trusted. This matters more than any
single hot loop: it means **an optimisation cannot currently be validated**.

| finding | severity | what it invalidates |
|---|---|---|
| `spikes-audits-5` | MEDIUM, CONFIRMED | **A3 `avg_rebuild_time`** times `SERIES_SYNCHRONIZED`, which the kit's own comment (`SSR_SpikeKit.mqh:390-404`) records as size-independent and "a timer, not work" (~9 s regardless of 10k or 100k bars). The number explicitly labelled "feeds the Reset budget" is a flag wait. |
| `spikes-audits-6` | MEDIUM, CONFIRMED | **D2 `worst_switch`** polls the same flag on 420 timed waits, so the "timeframe switch under 1 s" gate fails on a flag while the chart is usable in tens of ms. |
| `spikes-audits-8` | MEDIUM, CONFIRMED | **D4 `tail_1bar.avg`** — `SSR_WaitLastBarBefore` is already satisfied before the delete propagates on **16 of 20 trials**, so the published `rebuild_over_tail_ratio` (and `step_back_interactive ≤ 500 ms`) is mostly call-return time. |
| `spikes-audits-9` | MEDIUM, CONFIRMED | **D4's three strategies are not comparable**: `SSR_DropSymbol` closes the M5 chart at the strategy-2 restore, so strategy 1 is measured with a chart attached and strategies 2-3 without. The "with and without indicators" comparison the header promises never happens. |
| `spikes-audits-10` | MEDIUM, CONFIRMED | **D1 `bars_per_sec`** — `MathMax(t_read, 0)` turns a readable-wait *timeout* into a *zero* wait, so the case that failed hardest publishes the best throughput, under the label "the number the user waits for". |
| `spikes-audits-11` | LOW, CONFIRMED | D1 (and A2) divide bars **requested**, not bars **accepted**; the kit's `SSR_Rate` guard is bypassed because `SSR_RateMetric` hardcodes the unit `ticks/s`. |
| `spikes-audits-13` | LOW, CONFIRMED | D1 prints its gate instead of asserting it — a run where every seed takes 60 s still reports `SPIKE PASS`. |
| `spikes-audits-12` | MEDIUM, CONFIRMED | B3 likewise: its only verdict is a creation failure, so 0 % tick acceptance reports `SPIKE PASS`. |
| `spikes-audits-23` | MEDIUM, CONFIRMED | **D3 `throughput_stable`** still baselines at minute 10, which the same file's comment says hides the finding — a run that fell from ~12,000 to ~780 ticks/s before minute 10 PASSES. |
| `spikes-audits-31` | LOW, POTENTIAL_RISK | **B2 `optimal_batch_size`** is chosen from aggregate rate only; the duration of a **single** `CustomTicksAdd` — the quantity `InpPumpMs` actually constrains — is never recorded, so the recommended batch may block longer than a timer beat. |
| `spikes-audits-20` | LOW, CONFIRMED | **B4 `copyticksrange_week_return`**, published as a call ceiling and as "the page size for TickSource", is a measurement of the broker's tick density over seven days. |

The structural cause is one invariant: `SSR_End` prints `SPIKE PASS` iff
`g_ssr_fail == 0`, so **a spike with no verdict at all is indistinguishable from a
spike that passed** (`SSR_SpikeKit.mqh:181-191`, map §2.2.1). [CONFIRMED FROM CODE]

Two product-side instruments are also broken:

* Findings `core-engine-9` / `core-sync-4` (LOW, CONFIRMED) —
  `RecordPump` is handed `(int)m_cursor.bar_count`, the **cumulative** counter,
  as the per-pump bar figure (`SSR_ReplayController.mqh:1035, 1110`;
  `SSR_Metrics.mqh:108`), so `SSRPerfSnapshot.bars` grows as 1+2+…+P. No UI reads
  it today, which is the only reason this is LOW.
* Finding `ui-plumbing-6` (E.1.6) means `Writes()`/`PaintWrites()` — the panel's
  own paint-budget seam — degrade silently, and `ui-panel-1` means
  `Writes() == 0` on a still frame (asserted in `SSR_T5_Ui.mq5:236` and
  `SSR_QA_Smoke.mq5:5045`) **cannot hold**.

[RECOMMENDATION] Before any repaint optimisation is attempted, restore one honest
instrument: a still-frame `PaintWrites()` count and the `g_starved` counter. The
project already has both seams; it does not currently have a frame where they
tell the truth.

---

### E.10 Ranked performance risks

| # | risk | severity | evidence |
|---|---|---|---|
| 1 | Sheet delete/recreate every frame defeats both caches; ~154 `Remove()` + full rebuild at 10 fps | MEDIUM | `ui-panel-1` CONFIRMED |
| 2 | `HideBody(false)` re-invalidates ~44 objects/frame (~400 writes, 198 of them the slider) | MEDIUM | `ui-panel-2` CONFIRMED |
| 3 | Budget cap silently **drops** bars on a slow terminal — performance becomes correctness | HIGH | `core-engine-1` CONFIRMED |
| 4 | Every published performance budget (Reset, rewind, TF switch, seed, batch size, page size) is invalid as measured | MEDIUM | `spikes-audits-5/6/8/9/10/23/31/20` |
| 5 | Key card fully torn down and rebuilt 10×/s while open | LOW | `ui-panel-12` CONFIRMED |
| 6 | Widget cache leaks slots and can switch itself off permanently | LOW | `ui-plumbing-6` CONFIRMED |
| 7 | Session dialog re-parses every session file per row per render; `GetNth` is O(entries²) on restore | LOW | `ui-port-session-12` CONFIRMED, `ui-port-session-13` POTENTIAL_RISK |
| 8 | Secondary charts never redrawn — a board is a still picture | MEDIUM | `chart-2` CONFIRMED |
| 9 | Focused `OBJ_EDIT` hidden/re-shown and fully rewritten 10×/s | MEDIUM | `ui-panel-11` POTENTIAL_RISK |
| 10 | Screenshot bursts run synchronously inside one timer beat | — | `SSR_ShotBook.mqh:231-257` [INFERENCE], unmeasured |
| 11 | `InpPumpMs` unbounded and re-armed unvalidated by the watchdog | LOW | `host-expert-15` POTENTIAL_RISK |
| 12 | Rewind depth silently halves after a step-back (`DropFrom` holes) | IMPROVEMENT | `core-sync-6` CONFIRMED |

### E.11 What is already right and should not be "optimised"

[CONFIRMED FROM CODE] — listed so a future pass does not undo them:

* The 10 fps paint gate and the poll-before-paint ordering
  (`SSReplayStandalone.mq5:3057-3063` and the comments at 2960-2984).
* The widget property cache's design choice to keep text whole and compare with
  `==` rather than hash it (`SSR_Widgets.mqh:40-45`), and to end `Same()` with
  `ObjectFind` (`:80-88`).
* `CSSRBarWindow::Read`'s binary search and its requested-range coverage rule.
* `CSSRTickSynthesizer`'s caller-pre-sizes contract (`:112-115`).
* `CSSRChartManager::Redraw`'s "snap only when the newest M1 bar changed **and**
  `ViewOffset > 0`" rule (`:553-581`) — the comment records that firing on every
  new bar is what "the chart jumps" was.
* The seed cache, and `m_metrics.RecordSeed` feeding `SetMeasuredSeedRate` so the
  next session is quoted from this machine rather than from a constant.

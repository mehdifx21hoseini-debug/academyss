# SS Replay — ARCHITECTURE MAP: `chart` subsystem (build v125)

Scope: `MQL5/Include/SSReplay/Chart/*.mqh` (6 files, 1,881 lines) plus the two
Common diagnostics owned by this audit (`SSR_FlightRecorder.mqh`, `SSR_Log.mqh`).
Everything below was read from the source; line numbers are v125 exact.

---

## 0. The two facts the whole layer is shaped by

1. **The chart layer holds no pointer to the engine and asks it nothing**
   (`SSR_ChartManager.mqh:20`). It publishes events (`CSSRChartObserver`) and the
   host decides what they mean. Dependency direction: `Chart -> Common` only,
   except `SSR_TradeLines.mqh:34` and `SSR_CalendarLines.mqh:27-28`, which include
   `Ui/SSR_Theme.mqh` (colour is one system) and `Data/SSR_Calendar.mqh`.
2. **No mouse events reach the replay chart.** `OnChartEvent` is delivered only to
   the chart the program runs on. Consequences encoded here:
   - draggable lines are **polled**, never listened for (`SSR_TradeLines.mqh:10-25`,
     `Poll()` at 286);
   - the view is moved with an explicit `ChartNavigate`, not by trusting
     `CHART_AUTOSCROLL` (`SSR_ChartManager.mqh:509-530`).

Two window modes exist and every invariant below depends on which one is live:
- **one-chart mode** (`InpOneChart=true`, default): the host hands **its own**
  chart to the replay symbol with `ChartSetSymbolPeriod` (Expert:2702), the EA is
  torn down and rebuilt on it (`REASON_CHARTCHANGE`), and afterwards
  `g_replay_chart == ChartID() == g_panel_chart` (Expert:1276, 1463).
- **two-window mode**: `CSSRChartManager::OpenChart` opens a chart on the replay
  symbol; the panel stays on the EA's chart.

---

## 1. `SSR_ChartTypes.mqh` — the layer's vocabulary (127 lines, no behaviour)

### Constants (the tuning surface of the whole layer)
| Name | Value | Meaning / justification in code |
|---|---|---|
| `SSR_REDRAW_MIN_INTERVAL_MS` | 100 | floor between our own repaints (ln 21) |
| `SSR_SCROLL_DETACH_BARS` | 3 | drift past this = "the user scrolled" (ln 25) |
| `SSR_SCROLL_DETACH_VOTES` | 2 | consecutive drifting syncs before believing it (ln 30) |
| `SSR_MAX_CHARTS` | 16 | ceiling on the registry (ln 33) |

### `struct SSRChartInfo` (ln 38-56)
Per-chart state the manager owns: `id, symbol, period, follow, user_detached,
last_offset, detach_votes, tf_changes, alive`. `Init()` sets `follow=true`,
`user_detached=false`. `symbol` is captured once at `Add()` and never refreshed.

### `class CSSRChartObserver` (ln 61-78)
Pure virtual-ish base, all bodies empty: `OnChartOpened`, `OnChartClosed`,
`OnTimeframeChanged(id, from, to)`, `OnUserScrolled`, `OnUserFollowed`.
**Callers: none in production.** `CSSRChartManager::SetObserver` (ln 141) is
called only by `Scripts/SSReplay/Tests/SSR_T4_ChartIntegration.mq5:40`. In the
shipped EA `m_observer` is always `NULL`, so every event above is a no-op.

### `enum ENUM_SSR_LEAK` (ln 84-90) and `struct SSRLeakReport` (ln 92-124)
`SSRLeakReport` = `{origin_in_watch, origin_charts, other_live_charts,
replay_charts}`; `IsClean()` (ln 105-108) deliberately ignores
`other_live_charts`; `ToString()` (ln 113-123) likewise. The enum declares
`SSR_LEAK_OTHER_SYMBOL_CHART` but nothing maps a report onto the enum — the enum
is documentation, not code.

---

## 2. `SSR_ChartManager.mqh` — `class CSSRChartManager` (632 lines)

### Responsibility
Own a registry of the charts showing **one** replay symbol; keep them at the
right edge without fighting a user who scrolled back; notice timeframe changes
and open/closed charts; throttle repaints; own the leak guard; never touch a
chart it did not open (except applying the follow policy on discovery).

### State it owns
`m_symbol` (replay symbol only, never the origin), `m_charts[]`/`m_count`
(registry, cap 16), `m_observer` (not owned, always NULL in production),
`m_leak` (by value), `m_owned[]`/`m_owned_count` (charts we opened and may close),
`m_host_left_open`, `m_last_redraw_us`, `m_last_bar_time`, and the counters
`m_untracked, m_snaps, m_redraws, m_redraws_skipped, m_syncs`.

### Public surface (and who calls it)
| Method | Line | Production callers |
|---|---|---|
| `SetObserver` | 141 | none (T4 only) |
| `Configure(replay, origin)` | 143 | Expert:1259, Expert:511 (`g_charts2[]`) — resets `m_charts`, **not** `m_owned` |
| `Symbol/Count/IdAt` | 152-155 | Expert:1424, 2332, 2408, 2823; blind + vitals + flight |
| `MarkTime(when,label,col)` | 166 | `Ui/SSR_GroupPort.mqh:490` (bookmark) |
| `Leak()` | 191 | `GroupPort:520` (`HideOrigin`) |
| `InfoAt(i,out)` | 193 | Expert:2340 (vitals), 2421 (flight) |
| `OpenChart(tf)` | 204 | Expert:1277, 2651, 512 |
| `OpenLayout(tfs,n)` | 229 | Expert:1308, 513 |
| `OwnedIds(out[])` | 246 | QA smoke only |
| `CloseOwned()` | 278 | Expert:2203, 2207 |
| `HostLeftOpen()` | 309 | none in the EA |
| `ApplyPolicy(id)` | 312 | internal (OpenChart, Sync-on-discovery, tf change) |
| `Sync()` | 332 | Expert:1423, 2817, 2830 |
| `DetectScroll(i)` | 433 | internal, from `Sync` |
| `Follow(id)` / `FollowAll()` | 475 / 491 | `GroupPort:517` (F key), Expert:2778 (play transition) |
| `DetachedCount()` | 500 | `GroupPort:122` -> `port.charts_detached` (**never rendered by the panel**) |
| `Redraw(force=false)` | 531 | Expert:2828 (primary stream only), QA smoke |
| `Snaps/LastBarTime` | 589-590 | vitals + flight recorder |
| `SetPeriodAll(tf)` | 593 | **no caller anywhere** |
| `ScanLeaks/LeaksClean/LeakAdvice` | 604-606 | Expert:1309, 2845; `GroupPort:168-169` |
| `Redraws/RedrawsSkipped/Syncs/Untracked/TimeframeChanges/ToString` | 609-628 | tests, QA |

### What it writes to the chart
- `CHART_AUTOSCROLL=true`, `CHART_SHIFT=true`, `CHART_QUICK_NAVIGATION=false`
  (`ApplyPolicy`, ln 314-323) — on `OpenChart` and on **discovery** in `Sync`
  (ln 367) and on a timeframe change while following (ln 397).
- `CHART_AUTOSCROLL=false` when a detach is concluded (ln 463).
- `ChartNavigate(id, CHART_END, 0)` in `Follow` (484) and `Redraw` (577).
- `OBJ_VLINE` objects named `SSR_MARK_<unix_seconds>_<registry index>`
  (`MarkTime`, ln 170/176): `STYLE_DASH`, `BACK=true`, `SELECTABLE=false`,
  `HIDDEN=true`, tooltip = the bookmark label. **Nothing anywhere deletes these.**
- `ChartRedraw` per chart in `MarkTime` (186) and `Redraw` (581).
- Writes no files.

### Invariants the code relies on
1. `m_symbol` is the replay symbol; a chart qualifies iff
   `ChartSymbol(id) == m_symbol` (ln 344). A chart the user re-symbols simply
   drops out of the registry as "closed".
2. **Creation order of registry entries is meaningful** — `MarkTime` embeds the
   index `i` in the object name (ln 176), and `Remove()` (98-106) shifts entries
   down, so indices are not stable across a chart closing.
3. `ViewOffset` (118-126) = `CHART_FIRST_VISIBLE_BAR - (CHART_VISIBLE_BARS-1)`,
   clamped at 0, and the comment asserts "at the right edge the leftmost visible
   bar is `visible_bars - 1`". That claim assumes the zero bar sits **at** the
   right border, which `ApplyPolicy` deliberately prevents (`CHART_SHIFT=true`).
   One number serves both the detach test and the snap test, on purpose (ln 568).
4. `m_last_bar_time` is written **only** in `Redraw` (548) and read by
   `DetectScroll` (452) to decide `votes_needed` (1 once any bar has been seen,
   otherwise `SSR_SCROLL_DETACH_VOTES`). So the two-vote safeguard is alive only
   before the first bar of the session.
5. `Redraw` snaps only when the newest **M1** bar changed
   (`SeriesInfoInteger(m_symbol, PERIOD_M1, SERIES_LASTBAR_DATE)`, ln 545) **and**
   `follow && !user_detached && ViewOffset > 0` (574). A `user_detached` chart is
   never snapped again until `Follow()`/`FollowAll()`.
6. `CloseOwned` never closes `ChartID()` — it reports it in `m_host_left_open`
   and keeps owning it (ln 280-303). Rationale at 261-277: a program dies the
   instant its own chart closes, mid-statement, and the leftover custom symbol
   then breaks the next session with 5304.
7. The registry ceiling is honoured quietly; over the cap, `Add` returns -1 and
   `m_untracked` is incremented **once per Sync pass per untracked chart** (375),
   so it is an occurrence counter, not a chart count.

### Ordering contract with the host (Expert `OnTimer`, every 5th pump ≈ 200 ms)
`Publish -> g_charts.Sync() (2817) -> blind re-Apply (2822-2824) ->
g_charts.Redraw() (2828) -> g_charts2[i].Sync() (2830)`.
`ScanLeaks` every 50th pump (2845). `FollowAll` on every play transition (2778).
**`g_charts2[i].Redraw()` is never called anywhere.**

---

## 3. `SSR_LeakGuard.mqh` — `class CSSRLeakGuard` (109 lines)

Responsibility: detect what the engine cannot prevent — the user looking at the
real instrument. Explicitly not a fix: "MetaTrader will not let one program
forbid another chart" (ln 9-13).

State: `m_origin`, `m_replay`, `m_report` (`SSRLeakReport`).
Public surface: `Configure(origin, replay)` (34), `Scan()` (44), `ReportInto`
(65), `IsClean` (66), `OriginCharts` (67), `ReplayCharts` (68), `OriginInWatch`
(69), `HideOrigin()` (77), `Advice()` (89), `ToString()` (99).

`Scan()` reads `SymbolInfoInteger(m_origin, SYMBOL_SELECT)` and walks
`ChartFirst/ChartNext`, bucketing every chart into replay / origin / other-live
(`!SSRIsReplaySymbol(s)`, i.e. name contains `.SSR`). Writes nothing.
`HideOrigin()` refuses while `origin_charts > 0` (a symbol with an open chart
cannot be deselected) and is offered, never automatic — reached from the panel
through `GroupPort:520`.

Consumers: `CSSRChartManager` (604-606) -> `GroupPort:168-169` ->
`SSRReplayPortState.leak_clean` / `.leak_advice` -> `SSR_Panel.mqh:1892-1894`,
where it is drawn as `Clip(StringFormat("%-12s %s", T(SSR_S_CHARTS), advice), 62)`
— i.e. **about 49 characters of the advice survive**. `other_live_charts` never
reaches the UI at all.

---

## 4. `SSR_TradeLines.mqh` — `class CSSRTradeLines` (628 lines)

Responsibility: three draggable planning lines (stop / target / optional entry),
the levels of live and pending positions, and the two-arrow record of closed
trades — all as native objects on the replay chart, polled rather than
event-driven.

### State
`m_chart`, `m_digits`, `m_point` (from the **origin** symbol, Expert:1139-1141,
1295), `m_armed`, `m_sl_name="SSR_LINE_SL"`, `m_tp_name="SSR_LINE_TP"`,
`m_en_name="SSR_LINE_EN"`, `m_sl_price/m_tp_price/m_en_price`, `m_en_armed`,
the five theme colours, and `m_seen[]` (tickets drawn in the current sweep).

### Object namespace (the chart contract)
| Name | Type | Draggable | Created in |
|---|---|---|---|
| `SSR_LINE_SL` / `SSR_LINE_TP` / `SSR_LINE_EN` | OBJ_HLINE | **yes** (`SELECTABLE` + `SELECTED` true, `ZORDER 0`) | `Ensure` 100-151 |
| `SSR_POS_<ticket>_E` / `_S` / `_T` | OBJ_HLINE | no | `Level` 71-95 via `DrawPosition` |
| `SSR_HIST_<ticket>_A` / `_B` / `_L` | OBJ_ARROW_BUY/SELL, OBJ_TREND | no | `DrawClosed` 506-583 |

All of them are `BACK=false` (in front of the candles, by design, ln 81-84) and
`HIDDEN=true` (kept out of the object list). `Attach` (172) also sets
`CHART_SHOW_OBJECT_DESCR=true` so `OBJPROP_TEXT` is visible without hovering.

### Public surface / callers (all from Expert `OnTimer` unless noted)
`Attach(chart,digits,point,sl_col,tp_col)` 172 — Expert:1295, 2658.
`IsArmed/SlPrice/TpPrice/HasEntry/EntryPrice` 186-191.
`Arm(price,stop_points,rr)` 223 and `ArmSide(...,is_long)` 232 — panel R/X keys via GroupPort.
`ArmEntry(price)` 195 / `DisarmEntry()` 206 — pending-order geometry.
`SetStopPoints(price,points)` 253 — the +/- buttons; side is read off
`m_sl_price < price` (ln 271) so a short setup is not flipped back (the defect
described at 257-270).
`Poll()` 286 — once per pump (Expert:2885): reads both prices, re-creates a line
the user deleted, re-asserts `OBJPROP_SELECTED`, returns "moved".
`StopPointsFrom(price)` 340, `RewardRatio(price)` 350, `IsLongSetup(price)` 360 —
feed `GroupPort::NoteLineDistances` (Expert:2891) and therefore the lot size.
`BeginPositions/DrawPosition/EndPositions` 378/383/445 — the sweep, every 5th
pump (Expert:2915-2954). `DrawPosition` is called for OPEN and PENDING (with
`kind` naming the order type); anything not redrawn in a pass is deleted by
`EndPositions`, which parses the ticket back out of the object name
(`StringSubstr(n,8)` + first `_`, ln 460-464).
`DrawClosed(...)` 506 — draw-once (guarded by `ObjectFind(base+"_L")`, ln 518).
`ClearHistory()` 586, `Disarm()` 598, `Clear()` 611, destructor calls `Clear()` (170).

### Invariants
- `m_point` must be non-zero; `Attach` forces 1.0 when the caller passes 0 (178).
- Prices are `NormalizeDouble(..., m_digits)` on arming, but **not** after a drag:
  `Poll` stores whatever the object reports (305-306).
- "moved" tolerance is half a point (303-304, 318).
- `EndPositions` assumes every `SSR_POS_*` object is an `OBJ_HLINE` in subwindow 0
  (452-455) — true because only `Level()` creates them.
- The planning lines are *the* source of truth for stop distance and R:R; the host
  must only ever *read* them during a session (`NoteLineDistances`, not
  `SetStopPoints`) — Expert:2886-2892 and the comment at 253-270.
- Writes no files.

---

## 5. `SSR_BlindMode.mqh` (261 lines)

### `struct SSRBlindPolicy` (50-106)
Six independent flags: `hide_dates, hide_ohlc, hide_price_scale,
anonymous_symbol, mask_ui_time, mask_ui_symbol`; `Standard()` (68) hides dates +
anonymises + masks the UI; `Full()` (76) adds OHLC and the price scale;
`Apply(ENUM_SSR_BLIND)` (82) maps the one input `InpBlind`
(`OFF/STANDARD/FULL`, ln 40-45). `AnyOn()` (89) and `ToString()` (95).

### `class CSSRBlindMode` (109-258)
State: `m_policy`, `m_applied`, and three parallel arrays + `m_id[]` of
`SSR_BLIND_MAX_CHARTS = 48` remembering `CHART_SHOW_DATE_SCALE`,
`CHART_SHOW_OHLC`, `CHART_SHOW_PRICE_SCALE` per chart, plus `m_saved`.

Public surface: `SetPolicy/PolicyInto` (134-135), `IsOn()` (136 — policy, not
application), `IsApplied()` (137), `Anonymous()` (138), `Apply(chart_id)` (147),
`Restore(chart_id)` (179), `RestoreAll()` (200), `SavedCharts()` (212),
`MaskTime(msc, start_msc)` (221), `MaskSymbol(s)` (230), `Leaks()` (238),
`ToString()` (252).

Callers: Expert:1002 `SetPolicy` (decided in `BuildSession` and only there,
Expert:985-999), 491/1010 `Anonymous()` -> the sink's symbol naming,
1421-1430 first apply, **2822-2824 re-apply every 200 ms while `IsOn()`**,
2176 `RestoreAll` (only when `user_removed`), 3021 `RestoreAll` (the reveal),
3006 `IsApplied()` gates the reveal card; `GroupPort:180-184` uses
`MaskTime`/`MaskSymbol` for the panel clock and symbol.

### Invariants
- **Save once per chart**: `Apply` records the pre-existing state only if the
  chart is not already in the registry (152-165), so re-applying cannot record
  our own hidden state. The record lives **in the instance only** — nothing is
  persisted — so it does not survive a deinit/reinit of the EA.
- Refuses (returns false) rather than blinding a chart it cannot remember
  (158-159).
- `RestoreAll` clears `m_applied` but **leaves `m_policy` on**; there is no
  `Off()`/`ClearPolicy()` in the surface.
- The symbol is never hidden here — it is handled at the source by
  `SSRAnonSymbolName` ("Chart.SSR1"), ln 16-18.
- `Leaks()` (238-250) is the honesty channel: it lists the date under the
  crosshair and the Data Window, the price level **only when
  `!hide_price_scale`**, and the terminal's Market Watch / Navigator. Printed to
  the log (Expert:1433), not shown in the panel.
- Writes no objects and no files; only `ChartSetInteger` on three properties.

---

## 6. `SSR_CalendarLines.mqh` — `class CSSRCalendarLines` (124 lines)

One `OBJ_VLINE` per scheduled release, named `SSR_NEWS_<collection index>`
(`SSR_CAL_PREFIX`, ln 30, 83). Colour/width/style come from importance
(42-58, theme constants `SSR_C_NEWS_HIGH/MED/LOW`); `BACK=true` (behind the
candles, 95), `SELECTABLE=false`, `HIDDEN=true`, `OBJPROP_TEXT` **and** tooltip =
`SSRCalendarItem::Label()` (99-100).

State: `m_chart`, `m_drawn` (cumulative creations, not a live count).
Surface: `Attach(chart_id)` (63), `Drawn()` (64), `Draw(CSSRCalendar*)` (71),
`Clear()` (111 — `ObjectsDeleteAll(m_chart, "SSR_NEWS_", 0)`).

Callers: Expert `LoadCalendar` 939-940 (`Attach` + `Draw`, once per program
instance), Expert:2656 (`Attach` only, on the handover-refused fallback chart —
no `Draw`, so that chart gets no news lines), Expert:2120 `Clear()` on **every**
deinit reason.

Invariants:
- **Idempotence is by object name**: `ObjectFind(n) >= 0 -> continue` (84). The
  name carries the collection index, so it is only stable while the collection is.
- **The future is drawn on purpose** (ln 10-14) — a release ahead of the clock is
  the point of the feature.
- **Blind mode is enforced by the host, not here**: `LoadCalendar` returns early
  when `CfgBlind() != SSR_BLIND_OFF` (Expert:925-930), so `Draw` is never reached
  in a blind session.

---

## 7. `SSR_FlightRecorder.mqh` (276 lines)

`struct SSRFlightSample` (41-81): 24 fields in three groups — engine
(`state, clock_msc, playing, speed_x100`), symbol (`replay_symbol, m1_bars,
last_bar_time, emit_calls, emit_ticks, seed_bars, truncations`), chart
(`chart_count, chart_id, chart_symbol, chart_period, autoscroll, following,
first_visible, visible_bars, view_offset, snaps`) and host (`pumps,
pump_delta_ms`). Filled by the host only (`RecordFlight`, Expert:2379-2426), which
is also what feeds `PrintVitals` — one set of facts, two renderings.

`class CSSRFlightRecorder`: `m_handle, m_path, m_rows, m_last_sample_ms,
m_capped, m_failed, m_error`.
Surface: `IsOpen` (126), `Path` (127), `Rows` (128), `LastError` (129),
`Open(tag)` (135), `Preamble(...)` (165), `Event(note)` (206), `Due()` (219),
`Write(sample)` (230), `Close()` (264).

Disk: **one CSV per attach** at `MQL5/Files/SSReplay-flight-<tag>-<local
timestamp>.csv` (147) — note it is *not* under `MQL5/Files/SSReplay/`.
`FILE_WRITE|FILE_TXT|FILE_ANSI|FILE_SHARE_READ` (149); every line is
`FileFlush`ed on purpose (106-116) so a killed terminal still yields the file.
Format: `#` preamble lines, then a 26-column header (196-198); `kind=S` samples
(`Write`) and `kind=E` events (`Event`). Column counts verified during this
audit: header 26 fields; `Event` emits 26; `Write` emits 25 values + an empty
trailing note = 26. Sampling is wall-clock gated at `SSR_FLIGHT_SAMPLE_MS=500`
(`Due`, GetTickCount, wrap-safe unsigned subtraction) and capped at
`SSR_FLIGHT_MAX_ROWS=5000`, after which one `# capped` line is written and the
recorder goes quiet.

Callers: Expert:1552-1565 (`Open` + `Preamble` + first `Event`), 2093-2101
(`Event(deinit reason)` + `Close`), 2382-2425 (`Due`+`Write`), 2443 (`FlightGuard`
— one event per distinct reason the timer turned back), 2456, 3151 (watchdog),
3203 (key events).

## 8. `SSR_Log.mqh` (88 lines)

`ENUM_SSR_LOG_LEVEL` OFF..TRACE. `CSSRLog` = `{m_level, m_tag, m_file, m_to_file,
m_to_print}`; `Emit` (37-53) prints `[SSR][LVL][tag] msg` and, **if a file was
set**, opens/seeks/writes/closes the file per line. `IsError..IsTrace` exist so
call sites can skip building expensive messages. One global instance
`g_ssr_log` (85), handed to the controllers (`SetLog`, Expert:1144, 493) and
configured at Expert:1965-1966 (`tag="host"`, level `INFO`).
`SetFile()` has **no caller anywhere** — the file sink is unexercised code; in
production the logger is `Print`-only.

---

## 9. Cross-cutting: what this subsystem leaves on the user's chart

| Prefix | Created by | Deleted by |
|---|---|---|
| `SSR_LINE_*` | TradeLines::Ensure | `Disarm`, `Clear`, destructor |
| `SSR_POS_*` | TradeLines::Level | `EndPositions` sweep, `Clear` |
| `SSR_HIST_*` | TradeLines::DrawClosed | `ClearHistory`, `Clear` |
| `SSR_NEWS_*` | CalendarLines::Draw | `Clear()` — Expert:2120, every deinit |
| `SSR_MARK_*` | ChartManager::MarkTime | **nothing** |
| `SSR_*` (panel/widgets) | Ui layer | `g_panel.Destroy()` |

In one-chart mode the chart is handed back to the origin symbol at deinit
(Expert:2194) and is **not** closed, so anything not deleted above persists on a
chart the user keeps.

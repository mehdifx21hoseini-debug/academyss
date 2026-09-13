# Architecture map — subsystem `ui-port-session`

Build v125. Files covered (read completely):

| File | Lines | Layer |
|---|---:|---|
| `MQL5/Include/SSReplay/Ui/SSR_ReplayPort.mqh` | 413 | L4/Ui — the seam (interface + wire struct) |
| `MQL5/Include/SSReplay/Ui/SSR_GroupPort.mqh` | 1110 | L4/Ui — the only concrete port |
| `MQL5/Include/SSReplay/Session/SSR_SessionManager.mqh` | 415 | L5 — save/resume orchestration |
| `MQL5/Include/SSReplay/Common/SSR_SessionFile.mqh` | 416 | L0 — sectioned key/value file format |

Cross-referenced (not audited here): `Core/SSR_MasterClock.mqh` (`CSSRReplayGroup`),
`Core/SSR_ReplayController.mqh` (`SaveInto`/`RestoreFrom`/`NotifyRestored`),
`Trading/SSR_TradingEngine.mqh`, `Trading/SSR_Statistics.mqh`,
`Trading/SSR_PropEvaluation.mqh`, `Ui/SSR_Panel.mqh`, `Ui/SSR_SessionDialog.mqh`,
`Experts/SSReplay/SSReplayStandalone.mq5`.

---

## 1. The shape of the subsystem

```
            SSR_Panel / SSR_SessionDialog          (draw + click only)
                     │  reads one struct, calls verbs
                     ▼
        CSSRReplayPort  (SSR_ReplayPort.mqh)  abstract
        + struct SSRUiState                   the whole wire
                     ▲ implements
        CSSRGroupPort  (SSR_GroupPort.mqh)
          │ transport → CSSRReplayGroup (master clock)
          │ readouts  → primary CSSRReplayController + sink + charts
          │ trading   → CSSRTradingEngine (virtual; no OrderSend below it)
          │ lines     → CSSRTradeLines      prop → CSSRPropEvaluation
          │ sessions  → CSSRSessionManager  journal/stats/strategies/blind
                     ▼
        CSSRSessionManager  (SSR_SessionManager.mqh)
          │ Save: group.At(i).SaveInto, acct.SaveInto, stats.SaveInto
          │ Restore: stream(s) → SeekAllTo → speed → acct → stats → NotifyRestored
                     ▼
        CSSRSessionFile  (SSR_SessionFile.mqh)
          MQL5\Files\SSReplay\sessions\<name>.ssr   (text, `# format 1`)
```

Two independent entry points reach `CSSRSessionManager`:
* the **host** (`SSReplayStandalone.mq5`): `Restore(CfgSession())` once in `BuildSession`
  (line 1483) when `InpResume` and the file exists; `Save(CfgSession(), CollectSettings())`
  in `OnDeinit` (line 2139) on **every** deinit reason, incl. `REASON_CHARTCHANGE`.
* the **panel**, through `CSSRGroupPort::SaveSession/LoadSession`, driven by
  `CSSRSessionDialog` (`SSR_SessionDialog.mqh:242, 273, 318`). This is a *mid-session*
  save/restore path and is the one most invariants were not written for.

---

## 2. `SSR_ReplayPort.mqh`

### 2.1 `#define SSR_POS_MAX 12`
How many position rows fit **on the wire**. Explicitly not a trading cap and not a
draw cap (`CSSRPanel::PosCap()` computes 5 normally, 12 in tall mode).

### 2.2 `struct SSRUiState` — the entire UI contract
Flat, pointer-free, fixed arrays + strings, so an IPC port could fill it from numbers.
Owns no behaviour beyond:
* `Init()` (l.238) — resets **every** field; one loop clears the six parallel `pos_*` arrays.
* `IsRunning()`, `CanPlay()`, `CanStep()` — the only state-machine knowledge the panel gets.

Field groups: connection/clock (`connected, symbol, status, now_msc, start_msc, end_msc,
progress, speed_x100`), fidelity (`fidelity, fidelity_effective, fidelity_note`), perf
(`perf_calibrated, us_per_tick, pump_p95_ms`), counters (`ticks_emitted, bars_consumed,
ticks_rejected, guard_violations`), navigation (`bookmarks, has_saved_position,
checkpoints`), chart health (`leak_clean, leak_advice, charts_detached`), errors
(`last_error, last_error_text, pause_reason`), multi-stream (`streams, skew_msc`),
blind mode (`clock_text` — **already masked**, `blind`), account (`balance, equity,
floating, open_positions, closed_trades, risk_percent, stop_points, tp_points,
trade_symbol, can_trade`), strategy (`strategy_text`), order intent (`trade_tag,
trail_points, entry_armed, entry_price, order_name, order_why, pending_count`),
evaluation (16 `prop_*` fields, all pre-computed 0..1 fractions plus their plain
numbers), position rows (`pos_rows` + 6 parallel arrays of `SSR_POS_MAX`), lines
(`lines_armed, sl_price, tp_price, line_long, bid, ask, price_digits, spread_points,
lot_from_risk, risk_money, reward_money, rr`).

**Invariants the code relies on**
1. The panel never formats the clock: `clock_text` arrives masked when `blind`.
2. Every `prop_*` fraction is already clamped 0..1 and computed by one owner
   (`CSSRPropEvaluation`), so a meter cannot disagree with the verdict.
3. `0` in `prop_daily_pct` / `prop_total_pct` / `prop_days_max` means **the rule does
   not exist**, not "no room left".
4. `pos_rows ≤ SSR_POS_MAX`; `open_positions` is the engine's truth. (See finding
   ui-port-session-9: pendings break the arithmetic built on this pair.)
5. `line_long` is meaningless while `!lines_armed`.
6. Rows are **newest first**.

**Fields written by `CSSRGroupPort` but read by no consumer** (`SSR_Panel.mqh` is the
only consumer besides tests): `pending_count`, `stop_points`, `tp_points`,
`checkpoints`, `has_saved_position`, `perf_calibrated`, `us_per_tick`, `pump_p95_ms`,
`prop_floor`. **`data_mode` is written by nobody** and read by nobody.

### 2.3 `class CSSRReplayPort` — the verbs
Pure virtual: `Name, IsConnected, ReadState, Play, Pause, Reset, StepBars, StepBack,
JumpTo, Restart, SeekTo, SetSpeedX100, SetFidelity`.
Defaulted-to-refusal (so a read-only port needs no code): `Bookmark, SavePosition,
ResumePosition, FollowCharts, HideOriginSymbol, Buy, Sell, CloseAll, BreakEvenAll,
SetRiskPercent, SetStopPoints, ArmLines, ClearLines, FlipLines, OpenFromLines,
ClosePosition, ClosePartial, BreakEven, SetTrailing, SetTradeTag, ToggleEntryLine,
ExportStatement, ResetEvaluation, TradeError, SessionCount, SessionName,
SessionSummary, SaveSession, LoadSession, SessionError`.
Nothing returns engine internals; `ExportStatement` returns the path by reference.
Virtual destructor present. There is exactly one implementation today (`CSSRGroupPort`);
the "Ipc" port named in the header does not exist.

---

## 3. `SSR_GroupPort.mqh` — `class CSSRGroupPort : public CSSRReplayPort`

**Responsibility**: fan one panel command out to N streams, and flatten N streams +
the virtual account + the evaluation + the chart set into one `SSRUiState`. It is a
wire: the only arithmetic it does is spread/points conversion, P/L sign, and the
pending-order geometry classification (delegated to `SSRPendingFor`).

### 3.1 State it owns (nothing else does)
`m_risk_percent` (0.5 default), `m_stop_points` (0.0 — "no safe default"),
`m_tp_points`, `m_trade_tag`, `m_trail_points`, `m_line_long`, `m_trade_error`,
`m_session_error`, `m_names[]` (the session list as last read).
All collaborators are **not owned**: `m_group, m_sink, m_charts, m_blind, m_acct,
m_stats, m_strategies, m_sessions, m_lines, m_journal, m_prop`.

### 3.2 Public surface beyond the base class (host-only; the panel holds a base pointer)
`Attach(group, sink, charts)`, `AttachBlind/AttachAccount/AttachStats/
AttachStrategies/AttachSessions/AttachLines/AttachJournal/AttachProp`,
`NoteLineDistances(stop_pts, tp_pts, is_long)`, `SetTpPoints/TpPoints`,
`PricePoint()`, `TagOrDefault()`, `StrategyLine()`.
Private: `Primary()` = `m_group.At(0)`, `PlacePending()`, `MarketAt()`, `Market()`.

### 3.3 `ReadState` (l.100-397) — one call per panel repaint (≥100 ms apart)
Order of fill: `out.Init()` → bail if `Primary()==NULL` → status/speed/fidelity →
**clock from the group, never from a stream** → summed counters over all streams →
primary's bookmarks/checkpoints/errors → symbol from the sink (`ReplaySymbol()`)
else from the controller, suffixed `" +N"` for a board → chart leak state → **blind
masking applied here** → `trade_tag`/`trail_points` (outside the account block on
purpose) → `if(m_acct != NULL)` { prop block; balance/equity/floating/counts;
bid/ask/digits/spread; lines block; position rows } → strategy line.

Key rules encoded here:
* `can_trade = (m_acct.Bid() > 0.0)` — a tick must have arrived.
* `line_long` comes from geometry (`sl_price < bid`), overridden by `SSRPendingFor`
  when an entry line exists.
* Size/money come from `m_acct.PreviewLot` / `PreviewPendingLot` — the *same* call the
  order uses, never a second formula. `PreviewLot` returns the fill price through
  `entry_out`, which is why `entry` is 0 until it is called.
* `lot_from_risk = 0` + `order_why` when the three lines do not describe a legal order.
* Rows include **pending orders** (`pos_pending[r]`), newest first, capped at 12.
* Per-row P/L = sign(move) × `m_acct.MoneyFor(volume, |move|)` — identical in result to
  the engine's own `RealisedOf` (both funnel into `CSSRRiskEngine::RiskOf`, which
  `MathAbs`es the distance), so rows do sum to `floating`.

### 3.4 Transport verbs
`Play/Pause/StepBars/StepBack/JumpTo/SeekTo/Restart/SetSpeedX100` → the **group**.
`Reset()` is the exception: it calls `At(i).Reset()` per stream and then
`m_group.Align()` (whose bool result is dropped). `SetFidelity` is **per stream** and
returns true if *any* accepted. `Bookmark` goes to the primary and then draws a chart
mark via `m_charts.MarkTime(..., SSR_C_ACCENT)`. `SavePosition` fans out;
`ResumePosition` resumes the primary and then `SeekAllTo(primary.Now())`.

### 3.5 Trading verbs (all virtual, all route into the virtual account)
* `SetRiskPercent` — refuses ≤0 or >100.
* `SetStopPoints` — refuses <0; when the lines are armed it **moves the line**
  (`m_lines.SetStopPoints`) rather than only the number.
* `NoteLineDistances` — the poll's read-only counterpart: records the number, never
  writes back to the chart (the removed round trip that flipped short setups).
* `ArmLines` — default stop is `max(10 × spread, 10)` points, RR from
  `m_tp_points/stop_pts` else 2.0; side from `m_line_long`.
* `FlipLines` — toggles `m_line_long`; re-arms (re-prices) when armed.
* `ToggleEntryLine` — entry starts half a stop-width on the stop's side of the bid.
* `OpenFromLines` — with an entry line → `PlacePending()`; else validate the target's
  side and `MarketAt()`. On success `m_lines.Disarm()` (not `Clear`, which would sweep
  the position lines).
* `Buy/Sell` → `Market()`: refuses without `m_stop_points`; SL from
  `m_stop_points × m_acct.Point()`; TP from `m_tp_points`; tag `""`.
* `MarketAt` → `m_acct.OpenWithRisk(..., TagOrDefault())`, then applies `m_trail_points`.
* `PlacePending` → `SSRPendingFor` for the type, target validated against the **entry**,
  then `m_acct.OpenPendingWithRisk`.
* `ClosePartial` rounds the fraction down to `SYMBOL_VOLUME_STEP` (fallback 0.01) and
  refuses `< step` or `≥ volume`. `BreakEven`, `BreakEvenAll`, `ClosePosition`,
  `CloseAll`, `SetTrailing` (also applied to everything already open).
* `ExportStatement` → `m_journal.ExportHtml("SSReplay-<stamp>")`, path returned.
* `ResetEvaluation` → `m_prop.Reset()`.
* `SetTradeTag` trims and strips commas (the statement is also a CSV).
* Every verb's first act is `m_trade_error = ""` — which is why `CSSRPanel::ReadTag`
  compares against what it last *sent* rather than what came back.

### 3.6 Session verbs
`SessionCount()` → `m_sessions.List(m_names)` (refreshes the cache);
`SessionName(i)`/`SessionSummary(i)` index that cache — `SessionCount` must be called
first (the dialog does, in `Open()`); `SessionSummary` calls `Peek` per row, i.e. a
full file parse per row per render. `SaveSession(name)` builds a **default**
`SSRSessionSettings` and only sets `slot`. `LoadSession(name)` → `m_sessions.Restore`,
and on success copies `Warnings()` into `m_session_error` so a successful load can
still speak.

### 3.7 What it writes outside itself
Chart objects only indirectly: bookmark marks (`CSSRChartManager::MarkTime`), trade
lines (`CSSRTradeLines`). Files only indirectly: the HTML statement (journal), the
session file (manager). No `ObjectCreate` of its own.

---

## 4. `SSR_SessionManager.mqh`

### 4.1 `struct SSRSessionSettings`
`seed, blind, pause_flags, session_mode, slot, ticks_per_bar, spread_points, chart_tf`
with `Init()` defaults (slot 1, 8 ticks/bar, `PERIOD_M5`). Written by the host's
`CollectSettings()`; **nothing in the product ever calls `ReadSettings`** — the block
is write-only today.

### 4.2 `class CSSRSessionManager`
Owns: `m_last_error`, `m_warnings` (newline-joined), `m_last_path`,
`m_streams_restored`. Holds three non-owned pointers set by
`Attach(group, acct=NULL, stats=NULL)`. **Nothing depends on this class** — it is the
top of the dependency order and depends downward on Core, Trading, Chart.

Public surface: `Attach, LastError, Warnings, HadWarnings, LastPath, StreamsRestored,
Exists, List, Save, Peek, ReadSettings, ReadSymbols, ReadWindow, Restore,
ResumeReport, Delete`.

`Path(name)` = `SSReplay\sessions\` + name with `\`, `/`, `:` replaced by `_` + `.ssr`.
(That leaves `* ? " < > |` to `FileOpen`, which simply fails; there is no separator
left for a traversal.)

### 4.3 On-disk layout written by `Save` (in this order — order matters for truncation)
```
# SS Replay session file
# format 1
[session]   name product(SSR_VERSION="0.1.0") written streams
            master_now master_start master_end speed
[settings]  seed blind pause_flags session_mode slot ticks_per_bar
            spread_points chart_tf
[stream]    origin digits point start end warmup_first data_first data_last
            warmup_bars now speed emitted ticks bars fidelity data_mode
            status auto_pause fingerprint        (per stream, in group order)
[bookmarks] mark=<msc>|<label>                   (one section per stream, always)
[account]   balance_initial balance_check digits point next_ticket
            margin_per_lot stopout_level stopouts ambiguous
[execution] commission_per_lot slippage_points swap_long swap_short
            use_real_spread fixed_spread
[positions] pos=<30 packed fields>  leg=<10 packed fields>
[equity]    samples last_msc  e=<msc>|<value>
```
Not stored: price data (re-read from the broker, hence the fingerprint), every derived
statistic, the prop evaluation, the journal, the shot book, anything beyond the instant
reached. `status` is written and never read back.

### 4.4 `Restore(name)` — the ordering contract
1. refuse if no group / no streams;
2. load the file, require `[session]`;
3. compare `streams` with `m_group.Count()` → **warn only**;
4. **streams first, account after** (documented: winding a stream re-emits ticks, and
   an account already holding the session's positions would run stops against
   pre-entry prices). Each `At(i).RestoreFrom(f, i, w)`; any failure aborts;
5. `now = At(0).Now()`; `SeekAllTo(now)` (result ignored) — "the master follows the
   streams, never the file";
6. `f.Select("session")` again, then `SetSpeedX100(GetLong("speed"))` — because
   `speed` also exists in `[stream]` and the cursor was left there;
7. warn if `MaxSkewMsc() != 0`;
8. `m_acct.RestoreFrom(f, w)` (abort on failure), `m_stats.RestoreFrom(f)` (result ignored);
9. `At(i).NotifyRestored()` per stream → `PublishRewind(now)` so observers resync and
   the auto-pause watcher does not announce restored positions as fresh entries.

The caller must have already built and `Load()`ed every stream over the same window;
`ReadSymbols` + `ReadWindow` exist for that and the host uses both (lines 1055, 1324).

`ResumeReport()` = "resumed N stream(s) at <SSRFormatMsc(group.Now())>" plus
" - BUT:\n" + warnings.

### 4.5 Invariants relied on
* `[stream]` and `[bookmarks]` sections are written strictly one pair per stream in
  group order, so `Select("stream", nth)` / `Select("bookmarks", nth)` line up.
  A `[bookmarks]` section is emitted even when empty, which is what keeps `nth` aligned.
* The stream's own `RestoreFrom` refuses a different `origin` and an instant outside
  its window — that is the whole guard against loading a session into the wrong board.
* The balance is **replayed from the trade log**, never read; `balance_check` only
  produces a warning.
* The equity curve is the one statistic that is stored, because it cannot be recomputed.

---

## 5. `SSR_SessionFile.mqh`

### 5.1 Format constants
`SSR_SF_MAX_ENTRIES 16384`, `SSR_SF_MAX_SECTIONS 1024`, `SSR_SF_FORMAT 1`,
`SSR_SF_SEP "|"`.
Worst case actually reachable today: 4096 equity + 512 `pos` + 4096 `leg`
(`SSR_MAX_POSITIONS 512` × `SSR_MAX_TRADE_LEGS 8`) + ≈60 scalar keys ≈ **12,800**
(the header comment's "about three times the worst realistic case" omits the legs).

### 5.2 `class CSSRSessionFile`
Parsed contents are three parallel dynamic arrays (`m_ent_sec/key/val`) plus
`m_sec_name[]`, grown in blocks by `Reserve`/`ReserveSections`. Dynamic on purpose:
the object is a local inside `Save`/`Restore` and fixed arrays at the ceiling would put
~1 MB on the stack. Lookups are linear scans against `m_cursor` (the selected section).

Write side: `Create(path)` (`FILE_WRITE|FILE_TXT|FILE_ANSI|FILE_SHARE_READ`, writes the
two header comments), `Comment`, `Section` (blank line between sections),
`Set/SetLong/SetInt/SetBool/SetDouble(…, digits=8)`, `Close`. `Set` neutralises `\r`
and `\n` in values so a value cannot forge an entry. **No write is error-checked and no
entry is counted on the way out.**

Read side: `Load(path)` (`FILE_READ|FILE_TXT|FILE_ANSI`) — trims each line, skips
blanks, treats `#` at position 0 as a comment except `# format N`, `[name]` opens a
section, `key=value` splits at the first `=` and is dropped if no section is open;
sets `m_truncated` and **fails** at either ceiling; then refuses `m_format <= 0`
("no format line") and `m_format > SSR_SF_FORMAT` ("written by a newer build").
Queries: `SectionCount(name)`, `Select(name, nth)`, `Has`, `Count(key)`,
`GetNth(key, nth, def)`, `Get/GetLong/GetInt/GetDouble/GetBool`.
`Truncated()`, `EntryCount()`, `SectionTotal()` exist and are used only by test T12.

### 5.3 Packed rows (free functions)
`SSRPackAdd(row, field)` appends with `|`, replacing any `|` inside the field with `/`
so a column cannot be forged. `SSRUnpack` = `StringSplit`. `SSRField`,
`SSRFieldLong`, `SSRFieldDouble` cannot walk off a short row — which is what makes
appending fields (e.g. `spread_at_entry`, `spread_at_exit`) backward-compatible in both
directions without bumping `SSR_SF_FORMAT`. The convention "append, never insert" is
enforced only by a comment.

---

## 6. Call-in map (who calls this subsystem)

| Caller | What it calls |
|---|---|
| `SSR_Panel.mqh` | `ReadState` (once per repaint, ≥100 ms), every transport/trading verb via `CSSRReplayPort*`, `Bookmark(SSRFormatMsc(now))` |
| `SSR_SessionDialog.mqh` | `SessionCount`, `SessionName`, `SessionSummary` (per visible row, per render), `SaveSession`, `LoadSession`, `SessionError` |
| `SSReplayStandalone.mq5` | `CSSRGroupPort::Attach*`, `SetTpPoints`, `NoteLineDistances` (per poll, l.2891); `CSSRSessionManager::Exists/ReadWindow/ReadSymbols/Attach/Restore/Save/LastPath/LastError/ResumeReport` |
| Tests | T12 (session file, fingerprint, account/equity round trip, whole-session resume, refusals), T15 (port-level save/load), QA smoke |

## 7. Terminology to preserve
*port* (the UI↔engine seam), *wire* (`SSRUiState`), *stream* (one
`CSSRReplayController`), *board* (a group of streams), *primary* (stream 0), *the
instant reached*, *fingerprint*, *warning vs refusal* (a warning never blocks a
resume), *packed row*, *entry armed*, *lines* (stop/target/entry as chart objects).

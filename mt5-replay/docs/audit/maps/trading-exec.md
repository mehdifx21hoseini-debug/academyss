# trading-exec — Architecture Map (v125)

Files covered (all read completely):
- `MQL5/Include/SSReplay/Trading/SSR_TradeTypes.mqh` (317 lines)
- `MQL5/Include/SSReplay/Trading/SSR_RiskEngine.mqh` (152 lines)
- `MQL5/Include/SSReplay/Trading/SSR_TradingEngine.mqh` (1278 lines)
- `MQL5/Include/SSReplay/Trading/SSR_AutoPause.mqh` (261 lines)

Nothing in these files touches a chart object or a broker. There is no `OrderSend`, `CTrade`, `PositionClose`, `ObjectCreate`, `ObjectSet*`, `ChartRedraw`, `FileOpen` or `Print` in any of the four. The only disk output is indirect: `CSSRTradingEngine::SaveInto(CSSRSessionFile&)` fills sections of the session file that `CSSRSessionManager` writes (`SSReplay\sessions\`). The only terminal reads are `SymbolInfoInteger/Double` (risk engine, margin) on the account's symbol — which is the **custom replay symbol** (e.g. `EURUSD.R1`), not the origin.

---

## 1. `SSR_TradeTypes.mqh` — vocabulary (no class, free functions + structs)

| Item | Kind | Notes |
|---|---|---|
| `ENUM_SSR_ORDER` | enum | BUY=0, SELL, BUY_LIMIT, SELL_LIMIT, BUY_STOP, SELL_STOP. Order of values is persisted as int in session files (line 1080). |
| `ENUM_SSR_POS_STATE` | enum | PENDING=0, OPEN, CLOSED, CANCELLED. Persisted as int; AutoPause stores it in a `uchar`. |
| `ENUM_SSR_CLOSE_REASON` | enum | NONE=0, MANUAL, SL, TP, PARTIAL, STOPOUT, SESSION_END. `SESSION_END` is never assigned anywhere in these files. `PARTIAL` is passed to `BookExit` for a partial leg but is never stored on the position (only closing legs set `reason`). |
| `SSROrderName`, `SSRCloseReasonName` | free fn | English literals (used in AutoPause reasons and `ToString`). |
| `SSRIsLong(t)`, `SSRIsPending(t)` | free fn | pure. |
| `SSRPendingFor(entry, stop, bid, min_dist, out, why)` | free fn (93-126) | Decides BUY/SELL x LIMIT/STOP from three prices. Side = `stop < entry`. Limit-vs-stop compares `entry` to **bid only** for both sides (122, 124). Refuses when `|entry-stop| < min_dist` or `|entry-bid| < min_dist`. Caller: `CSSRGroupPort::PlacePending` with `min_dist = point*2`. `why` strings are English literals. |
| `SSRTradeLeg` | struct (143-169) | One exit: `volume, price, msc, realised, fee, closing, prev_swap_locked, prev_swap_from_msc, prev_ambiguous`. `Init()`. **Does NOT record sl/tp/trail_peak/mae/mfe/spread_at_exit** — see finding trading-exec-2. |
| `SSR_MAX_TRADE_LEGS` | 8 | Last slot reserved for the closing leg → at most 7 partials. |
| `SSRVirtualPosition` | struct (178-291) | ~660 bytes incl. 8 legs + 2 strings. Fields: `ticket, type, state, volume, volume_initial, request_price, request_msc, request_type, open_price, open_msc, sl, tp, trail_points, trail_peak, close_price, close_msc, reason, commission, swap, profit, mae, mfe, spread_at_entry, spread_at_exit, ambiguous, swap_locked, swap_from_msc, legs[8], leg_count, risk_at_entry, tag, note`. Methods: `Init, HasR, RMultiple = (profit+swap)/risk_at_entry` (commission excluded), `IsLong/IsOpen/IsClosed, DurationMsc, ToString`. `type` is overwritten at fill (pending→BUY/SELL); `request_type` keeps the placed type. |
| `SSRExecutionModel` | struct (296-314) | `commission_per_lot` (per side), `slippage_points` (always adverse), `swap_long_per_lot`, `swap_short_per_lot` (per replay day), `use_real_spread`, `fixed_spread_points`. The Expert always sets `use_real_spread = true` (Expert 1165); spread synthesis lives in Core. |

Invariants relied on elsewhere: `state` transitions only PENDING→OPEN→CLOSED, PENDING→CANCELLED, and back via rewind; `volume == 0` iff CLOSED; `legs[]` is chronological (newest last); `leg_count >= 1` for every CLOSED position produced by this build.

---

## 2. `CSSRRiskEngine` (`SSR_RiskEngine.mqh`)

**Responsibility:** lot sizing and money-of-a-move, from the instrument's tick value/size. Owned by value inside `CSSRTradingEngine` (`m_risk`), exposed via `Risk()` pointer (tests configure it directly).

**State:** `m_tick_value (1.0), m_tick_size (1e-5), m_point, m_vol_min (0.01), m_vol_max (100), m_vol_step (0.01), m_digits (5), m_last_reason`.

**Public surface:**
- `ConfigureFromSymbol(symbol)` (41-57): reads `SYMBOL_DIGITS, POINT, TRADE_TICK_VALUE, TRADE_TICK_SIZE, VOLUME_MIN/MAX/STEP`; **silently substitutes defaults for any non-positive value** (tick_value→1.0, tick_size→point, vol_min→0.01, vol_max→100, step→0.01). Called from `CSSRTradingEngine::OnSessionStart` and `RestoreFrom`, always with the custom symbol name. The custom-symbol manager clones tick size/value/volume props from the origin (`SSR_CustomSymbolManager.mqh` 282-289).
- `Configure(tick_value, tick_size, vol_min, vol_max, vol_step, digits)` — tests/QA only.
- `RiskOf(volume, price_distance) = |dist|/tick_size * tick_value * volume` (79-85). Used for P/L (via `RealisedOf`), `risk_at_entry`, `MoneyFor`.
- `LotForRisk(balance, risk_percent, entry, stop)` (94-135): `money = balance*pct/100; lot = RoundToStep(money / RiskOf(1, dist))`; **rounds DOWN** (`MathFloor(v/step + 1e-9)*step`, 27-32; result not `NormalizeDouble`d); `< vol_min` → returns 0 with reason; `> vol_max` → capped, reason set but non-zero so callers proceed silently. Sized off `Equity()` by every caller in the engine.
- `RiskPercentOf`, `MoneyOf`, `LastReason`, `VolMin`, `VolMax`.

**Callers:** `CSSRTradingEngine` only (plus tests/QA/strategy via `Risk()`).

---

## 3. `CSSRTradingEngine : CSSRTickObserver` (`SSR_TradingEngine.mqh`)

**Responsibility:** the entire virtual account. An append-only log of `SSRVirtualPosition` on the heap (`m_pos[]`, capacity grown 64→x2 up to `SSR_MAX_POSITIONS = 512`); balance is realised only; equity = balance + floating. Observes the replay stream (registered FIRST by the Expert, line 1176, so every other observer sees an account that has already acted on the tick).

**State owned:**
`m_pos[], m_count, m_capacity, m_next_ticket (never rewound), m_risk, m_exec, m_symbol, m_digits, m_point, m_balance_initial, m_balance, m_margin_per_lot, m_stopout_level, m_stopouts, m_bid, m_ask, m_now_msc, m_bar (MqlRates), m_bar_valid, m_bar_synthetic, m_ambiguous_count, m_last_error`.
`m_count` includes CLOSED and CANCELLED entries; it only shrinks in `OnRewind`.

**Observer contract (as implemented):**
- `OnSessionStart(symbol, digits, point, start_msc)` (570-591): resets log, ticket counter, balance, ambiguity, `m_bar_valid`; `m_risk.ConfigureFromSymbol`; reads `SYMBOL_MARGIN_INITIAL` and, if > 0, **overrides** whatever `SetMarginPerLot` set. **Does not reset `m_bid/m_ask`** (finding trading-exec-4). Called by `CSSRReplayController::Load` (controller 835-837) — also on every new session on the same object.
- `OnBarContext(bar, synthetic)` (593-598): caches the bar; `synthetic = (fidelity != FULL_TICK)` (controller 506). The bar is clipped to the pump window at pump boundaries (controller `ClipBar`) but is the whole minute inside one emitted segment.
- `OnTicks(ticks[], count)` (600-615): per tick sets `m_bid`, `m_ask` (falls back to bid if ask==0; or bid+fixed if `!use_real_spread`), `m_now_msc`; then **`AccrueSwap → CheckPendings → CheckStops → CheckStopout`** in that order, per tick.
- `OnClock(now_msc)` (617-618): moves `m_now_msc` forward only.
- `OnRewind(msc)` (634-702): for each position: **if placed after `msc` → dropped from the log with no balance adjustment** (finding trading-exec-1); else `UnwindLegsAfter(i, msc)` (legs with `msc > cut`, newest first, restoring volume/profit/commission/balance/swap_locked/swap_from/state/ambiguous), un-cancel a pending cancelled after the cut, un-fill a pending filled after the cut (refund entry commission and swap, reset `type/volume/open_price/open_msc/profit/risk_at_entry/trail_peak/mae/mfe/ambiguous`); compacts the array; `m_now_msc = msc`; `AccrueSwap()` (refunds days that no longer happened). **Never touches `sl`, `tp`, `trail_peak` (kept positions), `mae/mfe` (kept positions), `spread_at_exit`, `m_bid/m_ask`.** Called via `PublishRewind` from controller `SeekTo` (backward, with the sink's bar-aligned cut), `Reset` (cut = start), `RestoreSnapshot` (cut = checkpoint bar-open), `NotifyRestored` (cut = now).
- `PauseRequested` — not overridden (engine never pauses the replay).

**Per-tick internals:**
- `FillPrice(is_long, opening)` (120-126): open long = ask+slip, open short = bid−slip; close long = bid−slip, close short = ask+slip. Used for **all** market fills, all pending fills (including limits), manual/partial/stop-out closes.
- `CheckPendings` (326-386): BUY_LIMIT `ask <= req`, SELL_LIMIT `bid >= req`, BUY_STOP `ask >= req`, SELL_STOP `bid <= req`. Fill at `FillPrice(is_long, true)`, `type` becomes BUY/SELL, `swap_from_msc = now`, `trail_peak = bid|ask`, `risk_at_entry` from sl, `spread_at_entry`, entry commission charged. If the cached synthetic bar (same minute) also reaches the SL, the position is flagged `ambiguous` at fill (371-384, whole-bar range).
- `CheckStops` (513-546): for OPEN positions: `UpdateExcursions` (mae/mfe vs bid|ask), `ApplyTrailing` (long: peak=max(peak,bid), sl=max(sl, peak−dist); short: peak=min(peak,ask), sl=min(sl, peak+dist); creates a stop where none existed), then `px = bid (long) | ask (short)`; `sl_hit = px <= sl | px >= sl`; `tp_hit = px >= tp | px <= tp`. If `BarIsAmbiguousFor` (synthetic bar, same minute, both sl and tp inside the **whole cached bar range**) → close at `StopFill` flagged ambiguous, even when only tp was touched. Else SL → `StopFill` (worse of level and touching price, then slippage, `Norm`ed); TP → exactly `tp`.
- `AccrueSwap` (401-430): idempotent restatement: `owed = swap_locked + per_lot * volume * days`, `days = floor(now/day) − floor(from/day)` with `from = swap_from_msc | open_msc`; balance moved by the difference. Calendar day = UTC-midnight of the tick's server-time msc; no rollover hour, no triple-swap day. Skipped when both swap inputs are 0.
- `CheckStopout` (436-470): only when `m_stopout_level > 0 && m_margin_per_lot > 0`; if `Equity()/UsedMargin()*100 <= level`, closes the worst floating loser at `FillPrice`, reason STOPOUT, repeats until the level recovers. `UsedMargin = Σ open volume * margin_per_lot` (no hedging netting, no leverage).
- `BookExit` (187-243): the single exit path: `AccrueSwap()` first, then leg written with the pre-state, `profit += realised`, `commission += fee`, `volume -= v`, `balance += realised − fee`, `swap_locked = swap`, `swap_from_msc = now`; closing → `close_price/close_msc/reason/state/spread_at_exit`, ambiguity flag + counter.

**Trading verbs (public):**
`Open(type, volume, sl, tp, price, tag)` (705-756) — no validation of sl/tp side, volume step/min/max, pending price side, or free margin; refuses only `volume <= 0`, `m_bid <= 0`, capacity, pending without price. `OpenWithRisk` / `OpenPendingWithRisk` / `PreviewLot` / `PreviewPendingLot` (all size via `LotForRisk(Equity(), …)` on the same fill price the order will use). `MoneyFor`. `Modify(ticket, sl, tp)` (any state except CLOSED; no side validation). `SetTrailing(ticket, points)` (any state). `Close(ticket)` (pending → CANCELLED stamped with `close_msc`; open → market close). `ClosePartial(ticket, volume)` (`volume <= 0 || >= remaining` → full close; refuses the 8th leg). `CloseAll()`. `BreakEven(ticket)` → `sl = open_price`, no side/spread check.

**Account/margin/read surface:** `SetBalance, SetExecution, ExecutionInto, Risk(), LastError, SetMarginPerLot, SetStopoutLevel, MarginModelled, Stopouts, UsedMargin, FreeMargin (unused anywhere), MarginLevel, Balance, InitialBalance, FloatingPL, Equity, Total, OpenCount, PendingCount, ClosedCount, AmbiguousCount, AmbiguousPercent (= ambiguous / closed — numerator includes open positions flagged at fill), At(i, out) (struct copy), ByTicket, Symbol, Digits, Point, Bid, Ask, ToString`.

**Persistence:** `SaveInto(f)` writes `[account]` (balance_initial, balance_check, digits, point, next_ticket, margin_per_lot, stopout_level, stopouts, ambiguous), `[execution]` (6 fields), `[positions]` with one `pos=` row per position (30 `|`-separated fields, `tag/note` sanitised of the separator) and one `leg=` row per leg (10 fields). `RestoreFrom(f, warning)`: rebuilds the log, **replays `m_balance` from the log** (`+= profit + swap − commission` per position), matches legs by ticket, re-runs `ConfigureFromSymbol(m_symbol)` (so `Load` must precede `Restore` — `CSSRSessionManager::Restore` 324-373 does this), warns (does not fail) when the replayed balance differs from `balance_check` by > 0.01 or legs are orphaned. Not persisted/restored: `m_bid/m_ask/m_now_msc/m_bar*`, `m_symbol`.

**Callers (outside tests):** Expert `SSReplayStandalone.mq5` (config 1159-1169, `Watch` 1176, `At()` reads 2916-2919); `CSSRGroupPort` (`OpenWithRisk`, `OpenPendingWithRisk`, `SetTrailing`, `ClosePartial` (rounds fraction to `SYMBOL_VOLUME_STEP` via `MathFloor` without epsilon), `BreakEven`, `Close`, `CloseAll`, `At/Total/Bid/Ask/Point/Symbol`); `CSSRIStrategy` (OpenWithRisk/ClosePartial/Modify/BreakEven/SetTrailing); `CSSRPublisher` (raw `Open(BUY|SELL, a1, a2, a3)` and `OpenWithRisk` when `InpAllowTrade`); `CSSRSessionManager` (SaveInto/RestoreFrom); readers `CSSRStatsEngine`, `CSSRJournal`, `CSSRPropEvaluation`, `CSSRShotBook`, `CSSRTradeAutoPause`, `CSSRPublisher`.

**Key invariants the code relies on:**
1. The log is the account: `m_balance` must equal `initial + Σ(profit + swap − commission)` over the log (this is what `RestoreFrom` recomputes and what `balance_check` verifies). Violated by `OnRewind`'s drop path (finding 1).
2. `OnBarContext` for a bar arrives before that bar's ticks and describes the same minute (`BarIsAmbiguousFor` self-invalidates on the minute check).
3. Ticks arrive in order, never repeated; `OnRewind(msc)` is called before any tick at/after a deleted stretch is re-emitted.
4. `m_bid > 0` means "there is a current price" — but nothing invalidates the price on session start, reset or rewind.
5. Legs are chronological; a CLOSED position's last leg has `closing == true`.
6. Every rewind that matters is followed by re-delivery of the ticks between the cut and the new now. **Not true on the checkpoint path** (controller `JumpForward` bulk-seeds bars without observers; recorded as core-engine-3) — finding trading-exec-3.

---

## 4. `CSSRTradeAutoPause : CSSRTickObserver` (`SSR_AutoPause.mqh`)

**Responsibility:** answer Core's "do you want to stop here?" by diffing every position's `state` against the last state it saw. No callbacks from the engine.

**State:** `m_acct*` (not owned), `m_flags` (bitmask of `SSR_PAUSE_ON_ENTRY|SL|TP|STOPOUT|ANY_CLOSE`), `m_seen[]` (uchar per slot, heap, grows only), `m_seen_count`, `m_want`, `m_reason`, `m_raised`.

**Surface:** `Attach, SetFlags, Flags, Raised, Enable(flag,on), FlagsText, Reseed()`; observer: `OnTicks → Scan()`, `PauseRequested(reason)` (consumes once), `OnRewind → clear + Reseed`, `OnSessionStart → clear + Reseed`.

**Scan semantics (74-157):** slot seen for the first time counts as an event (`was = 255`); OPEN (new or filled) → entry; CLOSED → by `reason` (SL/TP/STOPOUT) and/or ANY_CLOSE; first `Raise` wins per pump. Reason strings are English literals; `open_price` is formatted with a hard-coded 5 digits. `Reseed` adopts the account without raising (used on rewind, session start, and — via `NotifyRestored → PublishRewind` — session restore).

**Callers:** Expert (1206-1212: flags from `InpPauseEntry/SL/TP`; STOPOUT tied to `InpPauseSL`; registered after the account). Core `CheckObserverPause` (controller 150-174) reads `PauseRequested` after every pump; the reason is shown as the pause text.

**Invariant:** must be registered after the engine (it is); slot index i must refer to the same position between scans — guaranteed only because every log compaction (`OnRewind`) also reaches this observer's `OnRewind`.

---

## 5. Data flow summary

```
Controller.EmitWindow ──OnBarContext(bar, synthetic)──▶ Engine.m_bar
                      ──OnTicks(segment)────────────▶ Engine: swap → pendings → stops → stopout
                                                      └▶ Stats, Prop, AutoPause.Scan (diff states), Shots, …
Controller.SeekTo/Reset/RestoreSnapshot/NotifyRestored ──OnRewind(cut)──▶ Engine (truncate+unwind), AutoPause.Reseed
GroupPort / Strategy / Publisher ──Open*/Modify/Close*/BreakEven/SetTrailing──▶ Engine (uses m_bid/m_ask of the LAST tick seen)
SessionManager.Save/Restore ──SaveInto/RestoreFrom──▶ session file [account]/[execution]/[positions]
```

Cross-file caveat noted while cross-referencing (not in scope for findings): `CSSRGroupPort::ClosePartial` computes `MathFloor(p.volume * fraction / step) * step` without an epsilon (GroupPort 856); for `volume = 0.58, fraction 0.5, step 0.01` IEEE arithmetic gives `0.28` instead of `0.29` (verified numerically). The risk engine's own `RoundToStep` does add `1e-9`.

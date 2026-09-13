# Architecture Map — subsystem `strategy-integration-report`

Build v125. Files covered (read completely):

| File | Lines | Layer |
|---|---:|---|
| `MQL5/Include/SSReplay/Strategy/SSR_IStrategy.mqh` | 278 | L3 strategy contract |
| `MQL5/Include/SSReplay/Strategy/SSR_MarketView.mqh` | 444 | L3 lookahead-free view |
| `MQL5/Include/SSReplay/Strategy/SSR_RefStrategy.mqh` | 161 | L3 reference strategy |
| `MQL5/Include/SSReplay/Strategy/SSR_StrategyHost.mqh` | 275 | L3 host / observer |
| `MQL5/Include/SSReplay/Integration/SSR_Contract.mqh` | 276 | L5 wire contract (self-contained) |
| `MQL5/Include/SSReplay/Integration/SSR_Publisher.mqh` | 359 | L5 replay side |
| `MQL5/Include/SSReplay/Integration/SSR_Client.mqh` | 261 | L5 third-party side (portable) |
| `MQL5/Include/SSReplay/Report/SSR_ReportStyle.mqh` | 160 | L4 shared HTML skin |
| `MQL5/Include/SSReplay/Report/SSR_ClassReport.mqh` | 665 | L4 class report |

---

## 1. Data flow into and out of the subsystem

```
CSSRReplayController::EmitWindow()            (Core, SSR_ReplayController.mqh)
  ├─ FULL_TICK branch  (line 334..371)
  │     PublishTicks(all ticks of the window)         <-- ONE batch, NO PublishBar
  └─ bar branch (SYNTHETIC_TICK / BAR, line 373..530)
        per M1 bar i:
           PublishBar(ClipBar(bar_i), synthetic=true)  (line 506)
           PublishSegment(bar_i's surviving ticks)     (line 507)

observer order registered by the EA (SSReplayStandalone.mq5:1176..1247):
  g_acct -> g_stats -> [g_prop] -> g_autopause -> g_shots -> g_cal
         -> g_session -> g_view (CSSRMarketView) -> g_strategies (CSSRStrategyHost)
```

Invariant the subsystem depends on: **the view is registered before the host**, so
by the time a strategy hook runs, the view already holds the bar. Also: the
**trading engine is registered first**, so by the time the strategy is asked, the
account has already priced every tick of the batch — a strategy's market order
fills at the *last tick of the batch*, not at the moment the batch began.

Publish side (host `OnTimer`, SSReplayStandalone.mq5:2786..2816):
```
if(playing) g_group.Pump(delta)                     // strategy hooks fire in here
if(g_strategies.Count()>0 && g_view.M1Count()==0 && Now()>StartMsc()) PrimeView()
g_publisher.Poll()                                  // one client command per beat
every 5th beat: g_publisher.Publish()               // heartbeat + state, ~200 ms
```

---

## 2. `CSSRStrategyBroker` (SSR_IStrategy.mqh:48-192)

**Responsibility.** The only trading surface a strategy is given. A *facade*, not a
subclass, over `CSSRTradingEngine`; every order carries the strategy's name as the
position `tag`, which is what makes per-strategy statistics possible without a
second bookkeeping path.

**State owned:** `m_acct` (not owned), `m_tag`, `m_placed`, `m_refused`,
`m_last_error`. Counters are never reset (not even by `Attach`).

**Public surface**
- `Attach(CSSRTradingEngine*, string tag)` — called by the host in `Add()` and
  again in `OnSessionStart`.
- `Tag() Placed() Refused() LastError()`
- `Buy(vol,sl,tp)` `Sell(vol,sl,tp)` `Pending(type,vol,price,sl,tp)` — all funnel
  into private `Send()` → `m_acct.Open(type,vol,sl,tp,price,m_tag)`.
- `BuyRisk(risk_pct,sl,tp)` `SellRisk(...)` → `m_acct.OpenWithRisk(...,m_tag)`;
  sizing is the trading engine's, never a second formula.
- `Close(ticket) ClosePartial(ticket,vol) Modify(ticket,sl,tp) BreakEven(ticket)
  Trail(ticket,points)` — thin, NULL-guarded, no tag check (a strategy *can*
  close somebody else's ticket if it learns the number).
- `Balance() Equity() OpenCount()` — read-only account state.
- `MyOpenCount()` / `MyPosition(nth,out)` / `CloseAllMine()` — tag-filtered scans
  over `m_acct.Total()`; `CloseAllMine` walks **backwards** on purpose.

**Invariants relied on:** `m_acct.Open` returns ticket > 0 on success and 0 with
`LastError()` set on refusal; `SSRVirtualPosition.tag` is preserved verbatim;
`At(i,p)` is stable for the life of a pump.

**Writes to disk/chart:** none.

## 3. `CSSRStrategyContext` (SSR_IStrategy.mqh:197-218)

Everything a strategy is given, in one object: `market` (`CSSRMarketView*`, not
owned), `broker` (`CSSRStrategyBroker*`, not owned), `rng` (`SSRRandom`, value
member, seeded `1` in the ctor and re-seeded once by the host in `Add()`).

- `Now()` → `market.Now()` (replay msc) or `SSR_INVALID_TIME`; `NowTime()`.
- `IsSynthetic()` → `market.IsSynthetic()`, `true` when `market == NULL`.

`rng` is **public**, so a strategy can draw from it — and could also re-seed it,
but it is never told the session seed.

## 4. `CSSRStrategy` (SSR_IStrategy.mqh:228-275)

Base class. `ctx` (not owned, set by `Bind`), `m_enabled`, `m_note`.
- `Name()` returns `""` by default; the **host refuses a nameless strategy**
  rather than relying on a pure virtual.
- `Bind(ctx) Enable(bool) IsEnabled() Note()`
- hooks: `OnStart() OnBar() OnTick() OnRewind(msc) OnStop()`, all no-ops.
- `Status()` — one line for the panel.

Documented semantics: `OnBar` fires only when a bar of the strategy's timeframe
has **closed**, so "acting on shift 1 is always safe"; `OnTick` is "every tick,
for strategies that manage intrabar".

## 5. `CSSRMarketView` (SSR_MarketView.mqh) — `CSSRTickObserver`

**Responsibility.** The past, and only the past, in a form a strategy can read.
It does not *guard* against lookahead; it is *built from what was published*.
Higher timeframes are aggregated here from the same M1 the engine published.

**State owned:** `m_m1[]` (fixed at `SSR_VIEW_M1_BARS` = 4096 `MqlRates`, ~250 KB),
`m_count`, `m_capacity`, `m_symbol/m_digits/m_point`, `m_now_msc`, `m_bid/m_ask`,
`m_synthetic`, `m_refusals`, `m_bars_seen`.

**Observer side**
- `OnSessionStart(sym,digits,point,start_msc)` — resets count, prices, counters
  (does **not** reset `m_synthetic`).
- `OnBarContext(bar, synthetic)` — sets `m_synthetic`; if `bar.time` equals the
  newest bar's time it **updates in place** (a forming bar is republished as it
  grows), otherwise appends; `MakeRoom()` drops the oldest half when full.
- `OnTicks(ticks,count)` — takes bid/ask/`time_msc` from `ticks[count-1]` only.
- `OnClock(now_msc)` — monotonic forward only.
- `OnRewind(msc)` — keeps the prefix of bars whose **open time** `<= msc`
  (relies on the buffer being in time order), sets `m_now_msc = msc`.

**Strategy side** (every accessor returns `bool` + out-param; never 0.0 for
"unavailable")
- `Bar(tf,shift,out)` → private `Group()`.
- `IsForming(tf,shift)` → `shift == 0`, unconditionally (tf ignored).
- `Open/High/Low/Close/Time(tf,shift,out)`.
- `Extremes(tf,shift,count,hi,lo)` — ONE backward walk, not `count` of them.
- `HighestHigh/LowestLow(tf,shift,count,out)`.
- `Available(tf)` — one backward pass counting group boundaries; returns
  `groups-1` when `groups>1`, `1` when `groups==1`, else 0 (the oldest group may
  have begun before the buffer did and is not counted as servable).
- `Prime(bars[],count,now_msc)` — bulk fill after a jump; resets `m_count`,
  accepts bars while `SSRToMsc(bars[i].time) <= now_msc`, returns the number
  accepted (which can exceed `M1Count()` if `MakeRoom` fired).
- `Bid() Ask() Spread() Now() Symbol() Digits() Point()`
- `IsSynthetic() Refusals() BarsSeen() M1Count() Capacity() ToString()`

**`Group()` algorithm (lines 80-145).** Walk `i = m_count-1 .. 0`. `SSRBarOpenMsc`
gives the group key. On a key change: if the group just finished was the requested
one, return it; otherwise `seen++` and, when `seen == shift`, seed `out` from the
*newest* M1 bar of the group (so `close` and `spread` come from it) and set
`out.time` to the group's open. Inside the group, moving backwards, `out.open` is
overwritten each step (the earliest bar wins), `high/low` extend, volumes sum. If
the walk runs off the oldest bar the group is refused — **except `shift == 0`,
which is returned and flagged forming even though its `open` may be wrong**.

**Counted refusals:** negative shift, empty buffer, unsupported timeframe
(W1/MN1 do not align with the epoch), span running off the buffer.

**Invariants relied on:**
1. `m_m1` is strictly ascending in `time` and contiguous in minutes.
2. A bar is published only after it is legal to see (Core's `ClipBar` clips a
   partially-elapsed minute to what has happened).
3. `SSRBarOpenMsc` floors on the epoch, which matches MT5 bar alignment for all
   timeframes `SSRIsSupportedTimeframe` admits (M1..H12, D1).

**Writes to disk/chart:** none.

## 6. `CSSRStrategyHost` (SSR_StrategyHost.mqh) — `CSSRTickObserver`

**Responsibility.** Turn the replay stream into "a bar closed" and "a tick
arrived", keep up to `SSR_MAX_STRATEGIES` = 8 strategies' trades separable.

**State owned:** parallel arrays of size 8 — `m_strat[]` (not owned),
`m_broker[]`, `m_ctx[]`, `m_tf[]`, `m_last_bar[]` — plus `m_count`, `m_view`
(not owned), `m_acct` (not owned), `m_seed`, `m_started`, `m_last_error`,
`m_bar_calls`, `m_tick_calls`.

**Public surface**
- `Attach(CSSRMarketView*, CSSRTradingEngine*)` — **must precede `Add()`**;
  `Add()` copies `m_view` into the context and the account into the broker.
- `SetSeed(ulong)` — 0 becomes 1; must precede `Add()`.
- `static NameHash(string)` — FNV-1a, never 0.
- `Add(CSSRStrategy*, ENUM_TIMEFRAMES)` — refuses NULL, >8, unsupported tf,
  empty `Name()`, duplicate `Name()`. On success: attaches the broker with the
  name as tag, points the context at the view and broker, seeds the context RNG
  with `m_seed ^ NameHash(name)` (so add-order cannot change results), binds.
- `Clear()` `Count()` `At(i)` `LastError()` `BarCalls()` `TickCalls()`
- `StatsFor(i, CSSRStatsEngine*, out)` → `stats.ComputeFor(name, out)`
- `Report(CSSRStatsEngine*)` — one line per strategy plus its caveat.
- `StopAll()` — `OnStop()` on each, clears `m_started`.
- `ToString()`

**Observer side**
- `OnSessionStart(...)` — clears `m_last_bar[]`, re-`Attach`es each broker,
  `m_started = false`. Does **not** re-seed `m_ctx[i].rng` and does not reset the
  call counters.
- `OnTicks(ticks,count)` (lines 171-212) — the whole hot path:
  - first batch of a session fires `OnStart()` on every enabled strategy;
  - `now = ticks[count-1].time_msc` (**the last tick of the batch only**);
  - per strategy: `bar_open = SSRBarOpenMsc(now, m_tf[i])`; the first bar ever
    seen is adopted silently; `bar_open > m_last_bar[i]` fires `OnBar()` once;
    then `OnTick()` unconditionally.
- `OnRewind(msc)` — `m_last_bar[i] = SSR_INVALID_TIME` (so the first bar close
  after a rewind is skipped by design) and forwards `OnRewind` to each strategy.
  Does **not** clear `m_started` and does **not** rewind `m_ctx[i].rng`.

**Writes to disk/chart:** none (`Report()` is returned as a string; the EA prints it).

## 7. `CSSRRefBreakout` (SSR_RefStrategy.mqh) — `CSSRStrategy`

Reference only, explicitly not a recommendation. `Name()` = `"ref-breakout"`.
Config: `Configure(tf, lookback>=2, risk_percent, stop_buffer_points=0)`.
State: `m_tf m_lookback m_risk_percent m_stop_buffer m_signals
m_skipped_no_data m_state`. Accessors `Signals() SkippedNoData()`.

`OnBar()`:
1. bail if `ctx`/`market`/`broker` NULL;
2. `broker.MyOpenCount() > 0` → "in a trade";
3. `market.Available(m_tf) < m_lookback + 2` → skip (this is **exactly** the
   number `Extremes` needs: proceeding requires `groups >= m_lookback+3`, which
   is what `HighestHigh(tf, 2, lookback)` must prove complete — no off-by-one);
4. `Bar(m_tf, 1, last)` — the bar that closed, never shift 0;
5. `HighestHigh(m_tf, 2, m_lookback, hi)` / `LowestLow(...)` — the range *before*
   the breakout bar; a refusal ends the bar, it is never treated as zero;
6. `last.close > hi` → `sl = lo - buf`, rejected unless `0 < sl < Bid()`, then
   `broker.BuyRisk(risk, sl)`; mirror for `last.close < lo` with `sl = hi + buf`
   rejected unless `sl > Ask()`. No target is set (`tp` defaults to 0).
`OnRewind` sets `m_state = "rewound"` only (counters are not rewound).
`Status()` appends `"  [intrabar order assumed]"` whenever `ctx.IsSynthetic()`.

## 8. `SSR_Contract.mqh` — the wire

Self-contained (includes nothing) so a third product can copy it plus
`SSR_Client.mqh` and be integrated. `SSR_CONTRACT_VERSION 1`.

- Transport: **terminal global variables** (doubles), namespaced
  `SSRGvName(slot, field)` = `"SSR." + slot + "." + field`; `SSR_MAX_SLOTS` 8.
- `SSR_HEARTBEAT_STALE_MS` 5000 — terminal globals outlive their program, so a
  heartbeat, not a flag, decides whether a session is alive.
- Frozen wire enums: states `SSR_W_STATE_IDLE..ERROR` (0..7), fidelity
  `SSR_W_FID_REAL_TICK/SYNTHETIC/BAR` (0..2), result codes `SSR_RC_OK 0`,
  `UNKNOWN_CMD -1`, `NOT_PERMITTED -2`, `REFUSED -3`, `NO_SESSION -4`.
- Permissions `SSR_PERM_READ 0x01`, `CONTROL 0x02`, `TRADE 0x04`. READ is always
  granted; the other two default off and are set by the **replay** side.
- Commands 0..11: NONE, PLAY, PAUSE, STEP(a1=bars), STEP_BACK(a1=bars),
  SPEED(a1=x100), JUMP(a1=epoch ms), BUY/SELL(a1=vol,a2=sl,a3=tp), CLOSE_ALL,
  BUY_RISK/SELL_RISK(a1=**risk percent**,a2=sl,a3=tp).
- Fields: `v hb state now start end speed fid synth perm streams sym bal eq open
  amb` and `cmd.seq cmd.id cmd.a1 cmd.a2 cmd.a3 cmd.ack cmd.rc`.
- `SSRSymbolHash(name)` — FNV-1a folded to 31 bits so a double holds it exactly
  (names do not fit in a double; a client only needs identity, not the name).
- `SSRWireStateName` / `SSRWireRcName`.
- `struct SSRPublicState` — the whole client-visible picture, plus `Init()`,
  `Can(perm)`, `IsPlaying()`, `Progress()` (clamped 0..1) and `Banner()` (the
  sentence a client must show beside replay-derived numbers).

**Deliberately absent:** any verb that reads data at a time (a client that could
ask for a bar could ask for a future one), anything that names a symbol, anything
that reaches a broker. The only forward-looking datum published at all is
`end_msc`, the window boundary — no price, no bar, no tick.

## 9. `CSSRPublisher` (SSR_Publisher.mqh) — replay side

**State owned:** `m_group` (`CSSRReplayGroup*`, not owned), `m_acct` (not owned,
may be NULL), `m_slot`, `m_permissions`, `m_enabled`, `m_symbol`, `m_last_seq`,
`m_published`, `m_executed`, `m_refused`, `m_last_command`.

**Public surface:** `Attach(group,acct=NULL)`, `SetPermissions(control,trade)`
(always ORs in READ), `SetSlot(int)`, `SetSymbol(string)`, `Permissions()`,
`Published() Executed() Refused() LastCommand() IsEnabled()`,
`Begin()`, `Withdraw()`, `Publish()`, `Poll()`, `ToString()`.
Destructor calls `Withdraw()`.

- `Begin()` — clears any command left by a previous run (`cmd.seq/ack/id/rc`),
  writes `v`, enables, publishes once.
- `Withdraw()` — `GlobalVariableDel` on all 23 field names for this slot.
- `Publish()` — needs `m_group.Count() > 0` and `At(0) != NULL`; writes version,
  state, now/start/end, speed, fidelity, `synth` (`fid != FULL_TICK`), perm,
  streams, symbol hash, and — when an account is attached — balance, equity,
  open count, `AmbiguousPercent()`. **Heartbeat written LAST**, so a client that
  reads `hb` first never sees a fresh beat beside stale values.
- `Poll()` — at most one command per call. Ignores `seq == 0` or
  `seq == m_last_seq`; reads id/a1/a2/a3; `Execute`; writes `cmd.rc` **before**
  `cmd.ack`; records `m_last_seq`.
- private `Execute(cmd,a1,a2,a3)` — the only place a request becomes an action.
  `trading = BUY|SELL|CLOSE_ALL|BUY_RISK|SELL_RISK`; `need = trading ? TRADE :
  CONTROL`; missing permission → `NOT_PERMITTED`. Then: PLAY/PAUSE/STEP/
  STEP_BACK/JUMP → `m_group.*`; SPEED → `m_group.SetSpeedX100((long)a1)` and
  always OK; BUY/SELL → `m_acct.Open(..., "external")`; CLOSE_ALL →
  `m_acct.CloseAll()`; BUY_RISK/SELL_RISK require `a2 > 0` and go through
  `m_acct.OpenWithRisk(..., "external")`. Unknown → `UNKNOWN_CMD`.
- private `WireState` / `WireFidelity` — the mapping *is* the boundary; written
  as switches, never casts.

**Writes:** terminal global variables only. Nothing to disk or chart.

**EA wiring:** slot `InpSlot`, permissions from `InpAllowControl`/`InpAllowTrade`;
extra streams get `CSSRPublisher` instances on `InpSlot+1+i` with `m_acct = NULL`
and trade permission forced off, all attached to the **same** `g_group`.

## 10. `CSSRClient` (SSR_Client.mqh) — third-party side, portable

**State owned:** `m_slot`, `m_state` (`SSRPublicState`), `m_seq` (its own command
counter, starts at 0), `m_last_rc`, `m_last_error`.

**Public surface:** `SetSlot/Slot`, `LastRc/LastError`, `Discover()`,
`Refresh()`, `StateInto(out)`, `IsActive() IsPlaying() Now() NowTime()
IsSynthetic() Banner() Can(perm)`, `IsMySymbol(symbol)`,
`Send(cmd,a1,a2,a3,timeout_ms=500)`, and the named verbs `Play Pause Step
StepBack SetSpeed JumpTo Buy Sell CloseAll BuyRisk SellRisk`, `ToString()`.

- `Discover()` — scans slots 1..`SSR_MAX_SLOTS`, returns the first active one,
  else restores the previous slot and returns 0.
- `Refresh()` — `Init()`, read `v` (absent/<=0 → false, the normal case); refuse
  a **newer** contract than this client understands; then the heartbeat decides
  (`hb <= 0 || age < 0 || age > 5000` → not active); then copy every field.
- `Send()` — refresh, then a *courtesy* permission check (the publisher's is the
  rule), then `m_seq++`, write a1/a2/a3/id and **seq last**, then spin on
  `cmd.ack == m_seq` until `GetTickCount64() > until`. `Sleep` is unavailable in
  an indicator, so the wait is a bare spin. Timeout → `SSR_RC_REFUSED`.

**Writes:** terminal global variables only.

## 11. `SSR_ReportStyle.mqh` — one skin for two documents

Two free functions, no class, no knowledge of trades.
- `SSRWriteReportHead(int handle, string title)` — writes doctype,
  `<meta charset="utf-8">`, viewport, `<title>` (interpolated **unescaped**;
  both call sites pass literals), and the whole CSS in four
  `FileWriteString` calls: a light `:root` token set, the same tokens again under
  `@media (prefers-color-scheme:dark){:root:not([data-theme="light"])}` and once
  more under `:root[data-theme="dark"]`; then body/typography, `.caveat`, `.kpi`,
  tables, `.fig/.tip/.hrs/.bar` chart primitives, `td.shot` thumbnails, the class
  report's `.srow/.sname/.strip/.smark/.saxis` strip, and a print rule. Ends by
  opening `<body><div class="w">`.
- `SSRWriteThemeToggle(int handle)` — an inline IIFE bound to `#thm` that cycles
  system → opposite-of-system → other → system, persisting in `localStorage`
  under `ssr-thm` inside try/catch.

Callers: `SSR_Journal.mqh:264` ("SS Replay statement") and
`SSR_ClassReport.mqh:447` ("SS Replay class report").

## 12. `CSSRClassReport` (SSR_ClassReport.mqh)

**Responsibility.** Read every student's exported journal CSV out of
`MQL5\Files\SSReplay\class\*.csv` and build one comparison page. The **file name
is the student's name**. It refuses to *claim* comparability across sessions:
the journal's `session_key` is what two identical runs share.

Constants: `SSR_CLASS_DIR "SSReplay\class"`, `SSR_CLASS_OUT
"SSReplay\class-report.html"`, `SSR_CLASS_MAX 64`, `SSR_CLASS_TRADES 400`.

`struct SSRStudent` — `name parsed problem session symbol key win_start win_end
trades win_rate profit_factor net_profit expectancy average_r max_dd max_dd_pct
loss_streak ambiguous_pct no_stop` plus `entry[] won[] n_entries` and `Init()`.

**State owned:** `m_s[]` (resized to 64 in `Scan`), `m_count`, `m_last_error`,
`m_last_path`, `m_key` (the key the **majority** ran), `m_key_agree`.

**Public surface**
- `ReadOne(path, student_name, out)` — `FileOpen(FILE_READ|FILE_TXT|FILE_ANSI)`.
  A `#` line starting with `# SS Replay journal` sets `header_seen`; other `#`
  lines are `key,value` pairs (values that contained commas were joined with
  semicolons by the writer, so fields 2.. are re-glued with commas). Recognised
  keys: `session symbol session_key window_start window_end trades win_rate
  profit_factor net_profit expectancy average_r max_drawdown max_drawdown_pct
  loss_streak ambiguous_trades` (the last via `InParens`). Then the first
  non-`#` line carrying both `open_time` and `profit` column names switches to
  row mode; each row contributes `entry[]` (from `ParseTime` of `open_time`) and
  `won[]` (`profit > 0`), capped at 400, and increments `no_stop` when the `r`
  column is empty. No header → `parsed = false` with a reason; no
  `session_key` → `problem` set **but `parsed = true`**.
- `Scan(dir = SSR_CLASS_DIR)` — `FileFindFirst(dir+"\\*.csv")`; up to 64 files;
  student name = file name up to the first `".csv"`; then picks `m_key` as the
  most-agreed key and insertion-sorts **best `net_profit` first** (`Rank()`
  sends unreadable files to the bottom with `-1e18`).
- `Count() LastError() LastPath() Key() Agreeing() At(i,out) Rank(s)`
- `Write(out_path = SSR_CLASS_OUT)` — the page.

**Private helpers:** `Trim`, `Split` (plain `StringSplit` on `,`), `Field`,
`LeadingNumber`, `InParens`, `ParseTime` (`StringToTime` × 1000), `Html`
(escapes `& < > "` — *not* `'`, despite the comment saying five), `Signed`,
`Cls`, `MedianNet` (own insertion sort; middle of the class, not the mean),
`Axis(from,to)` (the shared time axis: the window of the first parsed student
whose key matches `m_key`, else the min/max of all entries, else `from+1min`).

**`Write()` output order:** report head → `.top` with `<h1>` and the theme
button → file count and local time → *caveat before the league table* when
`m_key_agree < readable` → a second caveat when files could not be read → KPI
row (Students, Ran this session, Trades between them, Median, Best, Worst) →
`Session: symbol · name` → **"When each of them entered"**: one `.srow` per
parsed student with a `.smark` per entry positioned `left:<pct>%` on the shared
axis (marks outside the axis are dropped; a student on another key is named
`- other session` and the strip is dimmed) → the **Results** table (Student,
Trades, Win rate, Profit factor, Average R, Max drawdown, Worst streak, No stop,
Net, and a `.bar` diverging bar scaled to `peak` × 46%) → the "No stop"
footnote → the unreadable-files table → `SSRWriteThemeToggle` → `</body>`.

**Writes to disk:** `MQL5\Files\SSReplay\class-report.html` (via
`FileOpen(FILE_WRITE|FILE_TXT|FILE_ANSI|FILE_SHARE_READ)`), after
`FolderCreate("SSReplay")`. Reads `MQL5\Files\SSReplay\class\*.csv`. Nothing on
the chart.

**Contract with the journal** (`SSR_Journal.mqh:184-220`) — the coupling that
matters: `# SS Replay journal` marker; `# window_start,%I64d` and
`# window_end,%I64d` in **milliseconds**; `# session_key,...`;
`# ambiguous_trades,%d (%.1f%%)`; the row header
`ticket,type,tag,volume,open_time,open_price,close_time,close_price,reason,
profit,commission,swap,r,duration,mae,mfe,resolution,note`; `open_time` written
by `SSRFormatMsc` as `YYYY.MM.DD HH:MM:SS`; `r` written empty (never zero) when
the trade had no stop; writer opens `FILE_TXT|FILE_ANSI`, so the reader's
`FILE_ANSI` matches.

---

## 13. Cross-cutting invariants this subsystem leans on

1. **Observer registration order** — view before host, account before both.
2. **`OnBarContext` precedes the ticks of that bar**, per bar, in the bar-driven
   fidelities. *This does not hold in `SSR_FIDELITY_FULL_TICK`, which publishes
   no bar context at all and one tick batch per pump.*
3. **`Attach()` then `SetSeed()` then `Add()`** on the host; `Add()` snapshots
   both pointers into the per-strategy context and broker.
4. **Tags are identity.** Per-strategy statistics, `MyOpenCount`, `MyPosition`
   and `CloseAllMine` all rest on `SSRVirtualPosition.tag` being the strategy's
   `Name()`; the publisher uses the literal tag `"external"` for client trades.
5. **Permissions are enforced on the replay side only.** The client's check is a
   courtesy for error messages.
6. **A double carries every wire value exactly** — epoch milliseconds (~1.7e12),
   `GetTickCount64()`, and the 31-bit symbol hash are all < 2^53.
7. **Frozen wire numbers.** Internal enums may be renumbered; the wire may not.
8. **`session_key` is the only thing that makes two students comparable.**

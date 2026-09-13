## G. TRADING ENGINE REVIEW

*Scope: `MQL5/Include/SSReplay/Trading/` (TradeTypes, RiskEngine, TradingEngine, AutoPause,
Statistics, Journal, PropEvaluation, ShotBook), the two paths that reach it —
`CSSRGroupPort` and `CSSRPublisher` — and the Trade sheet in `CSSRPanel` that a trader
actually presses. Build v125. Every claim below is tagged; findings are cited by id from
the verified set.*

---

### G.0 The one-paragraph verdict

The virtual account is the most complete subsystem in this product and the closest to
correct. It is a self-contained double-entry ledger: an append-only log of
`SSRVirtualPosition` plus a balance that is supposed to equal
`initial + Σ(profit + swap − commission)` over that log — an invariant the code itself
states and re-derives on restore (`CSSRTradingEngine::RestoreFrom` recomputes the balance and
warns when it disagrees with `balance_check`). Two defects break exactly that invariant and
everything computed from it, and both live in the same method: `OnRewind`
(**trading-exec-1**, CRITICAL, and **trading-exec-2**, HIGH). Fix those and the engine is
sound enough to build on. The *surface* the engine presents to the trader is the weaker half:
the risk numbers stop at the geometry (risk %, stop, lot, R) and never reach the cost model
(commission, spread, slippage, margin), the deal buttons take a second, less-guarded path
than the lines, and the word "virtual" appears in two places a user sees once and never
again. [INFERENCE, from the file inventory and findings below]

---

### G.1 Zero possibility of a real broker order — what actually guarantees it today

**The guarantee is structural, not configurational.** [CONFIRMED FROM CODE]

A repository-wide grep for every MQL5 verb that can reach a broker or the terminal's own
trading state returns **no call sites at all** — only prose:

```
$ grep -rnE "OrderSend|OrderSendAsync|CTrade|PositionClose|PositionModify|
             OrderCalcMargin|OrderCalcProfit|PositionsTotal|OrdersTotal|
             PositionGetDouble|PositionSelect|HistorySelect|OnTradeTransaction|OnTrade" MQL5
MQL5/Experts/SSReplay/SSReplayStandalone.mq5:305://--- ELSE: there is no OrderSend anywhere below it, so no path exists
MQL5/Include/SSReplay/Trading/SSR_TradingEngine.mqh:6://|  It reaches no broker: there is no OrderSend anywhere in this     |
MQL5/Include/SSReplay/Trading/SSR_TradeTypes.mqh:5://|  Nothing here reaches a broker. There is no OrderSend in this     |
MQL5/Include/SSReplay/Strategy/SSR_IStrategy.mqh:8://|  OrderSend, never reads a chart, never calls TimeCurrent. It is  |
MQL5/Include/SSReplay/Integration/SSR_Publisher.mqh:19://|     There is no OrderSend below this file, on any path.          |
MQL5/Include/SSReplay/Ui/SSR_ReplayPort.mqh:341://|  routes into the virtual account, and there is no OrderSend below |
```

Six hits, all comments, zero executable statements. There is also no `#include <Trade/Trade.mqh>`
and no `OnTrade`/`OnTradeTransaction` handler anywhere in the tree. [CONFIRMED FROM CODE]

Four independent reasons the guarantee holds, in descending strength: [CONFIRMED FROM CODE]

1. **There is no callable that could send an order.** `CSSRTradingEngine` books trades by
   writing struct fields and moving a `double m_balance`. `Open()`
   (`SSR_TradingEngine.mqh:705-756`) ends in `m_pos[i].state = SSR_POS_OPEN; ... m_balance -= m_pos[i].commission;`
   — arithmetic, not I/O.
2. **The account is downstream of the replay stream, not of the terminal.** The engine is a
   `CSSRTickObserver`; its prices come from `OnTicks(ticks[], count)` fed by the replay
   controller, never from `SymbolInfoTick` on a live symbol. The only terminal reads in the
   four Trading files are `SymbolInfoInteger/Double` for instrument *specifications*
   (`CSSRRiskEngine::ConfigureFromSymbol`, `SSR_RiskEngine.mqh:41-57`, and
   `SYMBOL_MARGIN_INITIAL` at `SSR_TradingEngine.mqh:588`), and they are read against the
   **custom replay symbol** (e.g. `EURUSD.R1`), not the tradable origin.
3. **The external seam is a command allowlist with an explicit permission gate.**
   `CSSRPublisher::Execute` (`SSR_Publisher.mqh:254-267`) classifies the five trade verbs
   (`SSR_CMD_BUY`, `SSR_CMD_SELL`, `SSR_CMD_CLOSE_ALL`, `SSR_CMD_BUY_RISK`, `SSR_CMD_SELL_RISK`),
   requires `SSR_PERM_TRADE`, and dispatches each one into `m_acct.Open(...)` /
   `m_acct.OpenWithRisk(...)`. The permission bit is written by the replay side
   (`SetPermissions(InpAllowControl, InpAllowTrade)`, host `SSReplayStandalone.mq5:1384`) and
   checked on the replay side — a client cannot grant itself the bit. `SSR_PERM_TRADE` is
   documented in the contract as `// virtual trades only, always`
   (`SSR_Contract.mqh:84`).
4. **No product header is included in the other direction.** The publisher's own header
   comment states the dependency runs one way, and the contract file has no SSProX include.

**What `InpAllowTrade` is and is not.** [CONFIRMED FROM CODE] `input bool InpAllowTrade = false;
// Let them place VIRTUAL trades` (host `:124`). It gates *another product's* ability to place
virtual trades in this account. It has nothing to do with broker access — with it `true`, an
external client can move a simulated balance; with it `false`, `Execute` returns
`SSR_RC_NOT_PERMITTED`. The default is `false`. [CONFIRMED FROM CODE]

#### G.1.1 The weakness: the guarantee is documented, not enforced

**[CONFIRMED FROM CODE]** `tools/ssr_audit.py` runs 21 audits (A1-A21) across every `.mq5`/`.mqh`
in the tree, and **none of them is about broker calls**. The five comments quoted above are the
entire enforcement. Nothing stops a future contributor — or a future "just for one test"
branch — from adding `#include <Trade/Trade.mqh>` and an `OrderSend` to a strategy or to the
publisher's `Execute`, and no test, audit or review gate would notice. This product's whole
safety claim to a novice trader rests on a property that is currently checked by nobody.
[INFERENCE]

#### G.1.2 A22 — the audit rule that makes it a build failure

**[RECOMMENDATION]** Add one audit to `tools/ssr_audit.py`, written in the harness's existing
idiom (`CLEAN` is the comment- and literal-stripped mirror of each source, so the five prose
mentions above cannot trip it; `report(audit, path, line, msg)` is the existing sink; the
function is appended to the tuple at the bottom of the file):

```python
# ---------------------------------------------------------------- A22
# No path from a replay session to a live order.
#
# The product's central safety claim is that every trade is virtual. Six
# files SAY so in a comment and nothing checks it. A22 makes the claim a
# build failure: the day somebody adds OrderSend to a strategy "just to
# try it", the audit names the line instead of the user's broker.
#
# CLEAN, not FILES: the comments that state the guarantee must not be
# what breaks the build for stating it.
BROKER_CALLS = (
    "OrderSend", "OrderSendAsync", "OrderCheck", "OrderClose", "OrderModify",
    "PositionClose", "PositionCloseBy", "PositionModify", "PositionOpen",
    "PositionSelect", "PositionSelectByTicket", "PositionGetDouble",
    "PositionGetInteger", "PositionGetString", "PositionsTotal",
    "OrderSelect", "OrdersTotal", "OrderGetDouble", "OrderGetInteger",
    "HistorySelect", "HistoryDealsTotal", "HistoryOrdersTotal",
    "AccountInfoDouble", "AccountInfoInteger",
)
BROKER_INCLUDES = re.compile(r'#\s*include\s*<\s*(Trade|Expert)\s*/', re.I)
BROKER_HANDLERS = re.compile(r'\bvoid\s+OnTrade(Transaction)?\s*\(')

def audit_a22():
    call = re.compile(r'\b(%s)\s*\(' % "|".join(BROKER_CALLS))
    for path, code in CLEAN.items():
        for m in call.finditer(code):
            report("A22", path, code[:m.start()].count("\n") + 1,
                   "%s reaches the live account. Every trade in this product "
                   "is virtual and books through CSSRTradingEngine; there is "
                   "no path from a replay session to a broker and this line "
                   "would be the first one. Use the virtual account, or if "
                   "this is genuinely needed, change the product's stated "
                   "guarantee first - deliberately, in the header comments "
                   "of SSR_TradingEngine.mqh and SSR_Publisher.mqh, and in "
                   "this audit." % m.group(1))
        for m in BROKER_INCLUDES.finditer(code):
            report("A22", path, code[:m.start()].count("\n") + 1,
                   "this includes MetaTrader's trading library. Nothing in "
                   "this product may send an order; the virtual account is "
                   "the only book of record.")
        for m in BROKER_HANDLERS.finditer(code):
            report("A22", path, code[:m.start()].count("\n") + 1,
                   "OnTrade/OnTradeTransaction is the terminal telling this "
                   "EA about a REAL deal. This product places none, so an "
                   "event handler for them is either dead or a mistake.")
```

Verification, in this project's own standard ("an audit that has never been seen to fire is not
evidence"): insert `OrderSend(req, res);` into `CSSRPublisher::Execute`, run
`python3 tools/ssr_audit.py`, confirm A22 names that line and the exit code is 1; remove it and
confirm the run is silent across all 21+1 audits. [RECOMMENDATION]

**Two companion rules worth the same twenty lines** [RECOMMENDATION]:

* **A23 — the permission gate is deny-by-default.** `SSR_Publisher.mqh:262-264` decides
  "is this a trade command" from a hand-written `||` chain. A new `SSR_CMD_CLOSE`,
  `SSR_CMD_MODIFY` or `SSR_CMD_PENDING` added to `SSR_Contract.mqh` and to the `switch` but
  *not* to that chain would be executable under `SSR_PERM_CONTROL` — the replay-control bit —
  rather than `SSR_PERM_TRADE`. [CONFIRMED FROM CODE: the chain is a literal five-term
  disjunction; the switch and the chain are two lists that must agree and nothing makes them.]
  A23 should parse the `SSR_CMD_*` defines out of the contract, parse the `case` labels out of
  `Execute`, and report any command that reaches `m_acct.` inside its case body without
  appearing in the `trading` predicate. The structural fix is better still: put the
  classification in the contract (`SSRCmdIsTrading(cmd)`) so there is one list.
* **A24 — no engine file may draw or log.** The `Trading/` directory today contains no
  `ObjectCreate`, `ChartRedraw`, `FileOpen` or `Print` (confirmed by the trading-exec map's
  file-by-file read). That separation is what makes the account testable headlessly; an audit
  that pins it costs nothing while it is still true.

---

### G.2 The three zones, named and enforced

The product already has this separation; what it lacks is a place where it is written down as
a rule and a check that keeps it. [INFERENCE]

| Zone | Owns | Files | May call | May **never** call |
|---|---|---|---|---|
| **1. REPLAY** | the clock, the bars, the ticks, the custom symbol, the chart | `Core/`, `Data/`, `Mt5/`, `Chart/` | `CustomTicksAdd`, `CustomRatesUpdate`, `CopyRates`, `Object*` | any Trading class; any broker verb |
| **2. VIRTUAL TRADING** | the account, the ledger, the statistics, the verdict | `Trading/` | `SymbolInfo*` (specs only), arithmetic | `Object*`, `ChartRedraw`, `FileOpen`, `Print`, any broker verb |
| **3. OPTIONAL EXTERNAL INTEGRATION** | the contract with another product | `Integration/` (`CSSRPublisher`, `CSSRClient`, `SSR_Contract.mqh`) | Zone 2's public verbs, **behind `SSR_PERM_TRADE`**; `GlobalVariable*` | any broker verb; any Zone 1 internal |

**Direction of dependency, as built** [CONFIRMED FROM CODE]: Zone 2 observes Zone 1 through
`CSSRTickObserver` and knows nothing about it otherwise; Zone 3 holds raw pointers to a
`CSSRReplayGroup` and a `CSSRTradingEngine` and is itself referenced by nobody below it; the UI
(`CSSRGroupPort` → `CSSRReplayPort`) is a fourth, *view* zone that reaches Zone 2 through a flat,
pointer-free `SSRUiState` struct. Nothing in Zone 2 reaches up into the UI.

**Where the boundary is thinnest** [CONFIRMED FROM CODE]: Zone 3's trade verbs bypass Zone 4's
sizing discipline. `SSR_Publisher.mqh:301` calls
`m_acct.Open(SSR_ORDER_BUY, a1, a2, a3, 0.0, "external")` with a client-supplied raw volume,
while every UI path goes through `LotForRisk`, which rounds to the step and refuses below
`vol_min`. That is exactly **trading-exec-12** (CONFIRMED, LOW): `Open()` validates only
`volume > 0`. The tag `"external"` is the one thing that keeps the two provenances
distinguishable afterwards, and it is applied consistently on all four external trade verbs.

---

### G.3 Making virtual-ness unmistakable

**Where the product says it today** [CONFIRMED FROM CODE]: exactly twice, and both are
dismissible.

* `SSR_Strings.mqh:509-510` — `SSR_S_ALL_VIRTUAL`, *"Every trade here is virtual. Nothing
  reaches a broker."* Used in **one** place: `SSR_KeyCard.mqh:98`, the H-key shortcut card.
* `SSR_Strings.mqh:581-582` — `SSR_S_FIRSTRUN_3`, *"H lists every key. All virtual - nothing
  reaches a broker."* Shown **once, ever** (`InpFirstCard`; suppressed by
  `MQL5/Files/SSReplay/seen.txt`).

The Trade sheet — `SheetTrade`, `SSR_Panel.mqh:1346-1490`, the surface a trader looks at for
the whole session and where the Buy and Sell buttons live — never says it. Neither does the
status strip, the position rows, the review card or the exported HTML statement.
[CONFIRMED FROM CODE: `grep -rn "SSR_S_ALL_VIRTUAL" MQL5` returns three hits — the enum, the
table entry, and the key card.]

**Why this matters more than it looks.** The deal buttons are drawn in broker colours and
carry a live price — `SSR_Panel.mqh:1478-1486`, `StringFormat(T(SSR_S_BUY_BTN), Price(m_state.ask))`
with `SSR_C_BUY` / `SSR_C_SELL` fills. A screenshot of this panel is indistinguishable from a
screenshot of a live trading terminal, and `CSSRShotBook` takes one automatically at every entry
and exit (**trading-analytics-15**, POTENTIAL_RISK: the shots are taken on the chart the panel
is drawn on, so the panel is *in* every screenshot). [CONFIRMED FROM CODE for the button
drawing; the finding is labelled POTENTIAL_RISK because the panel's occlusion depends on the
runtime corner, which cannot be verified without a terminal.]

**[RECOMMENDATION] Five changes, ordered by how hard they are to miss:**

1. **A persistent VIRTUAL chip in the header, next to the title.** `SSR_Panel.mqh:836` draws
   `Text(0, "title", ..., "SS Replay", SSR_C_ACCENT, SSR_FS_TITLE)`. Add slot 1,
   `"vchip"`, immediately right of it: the word `VIRTUAL` in `SSR_C_TEXT_DIM` on the
   accent-dim ground, present in every layout including compact, never conditional, never
   hideable. It survives the collapse path (`reopen`, `:653`) by being part of the header, not
   the sheet. Cost: one cached label, ≈40 px of the 310 px rail header's title row. It must be
   a `T(SSR_S_*)` string (audit A19 requires it) and must be ≤63 characters (A14) — trivially
   is.
2. **The deal buttons name the book they hit.** `T(SSR_S_BUY_BTN)` is `"Buy  %s"` (`SSR_Strings.mqh:492`), so the button reads
   `Buy  1.10234`. Make it `Buy (sim)  1.10234` / `Sell (sim)  1.10229`. A trader reads the button
   they are about to press; this is the single highest-value word in the product. Budget check:
   the button is `dw = (w - SSR_GAP) / 2` ≈ 150 px at `SSR_FS_TITLE` — verify with
   `CSSRWidgets::Extent()` and `CheckFrame()` before shipping, and fall back to a `SIM` prefix
   badge if the string clips.
3. **The statement and the CSV say it in their own first line.** `CSSRJournal::ExportHtml`
   writes a header block; the `# ` comment header of `ExportCsv` writes `# session`,
   `# net_profit`, `# profit_factor`. Add `# simulated,1` and a visible banner in the HTML
   head — a statement that leaves this tool and is forwarded to a prop firm or a mentor must
   not be mistakable for a broker statement. (Note **trading-analytics-4**, CONFIRMED MEDIUM:
   the CSV `profit` column is raw while the HTML and the headline are net of commission and
   swap — fix that in the same edit, since both live in `Row()`/`ExportHtml`.)
4. **The publisher's status string already does this — copy its wording.**
   `SSR_Publisher.mqh:350-351` builds `"+control"` / `"+trade"`. Make the trade token read
   `+trade(virtual)`; it is the string another product's UI will display about this session.
   [CONFIRMED FROM CODE: the token is a bare literal today.]
5. **Do not let blind mode make it worse.** **chart-5** (CONFIRMED, MEDIUM) establishes that
   in `SSR_BLIND_FULL` the product tells the user the price level is hidden while
   `SSR_Panel.mqh:1479-1484` prints `Price(ask)` / `Price(bid)` on the deal buttons
   unconditionally and `SSR_TradeLines.mqh:413-422` writes `BUY 0.20 at 4438.48` onto the entry
   line. Whatever the fix there (mask the button price, or stop claiming the level is hidden),
   the `(sim)` token must survive it — masking the price must not be allowed to remove the only
   word that says the trade is not real.

---

### G.4 The Risk Preview before execution

#### G.4.1 What already exists — and it is most of the way there

**[CONFIRMED FROM CODE]** The Trade sheet is *already* a risk preview, and a good one. With the
lines armed, `SheetTrade` (`SSR_Panel.mqh:1400-1424`) draws:

```
Text(13, "slrow",  ... StringFormat(T(SSR_S_STOP_ROW),   Price(m_state.sl_price),
                                    Money(-m_state.risk_money, true)));
Text(14, "tprow",  ... StringFormat(T(SSR_S_TARGET_ROW), Price(m_state.tp_price),
                                    Money(m_state.reward_money, true)));
Text(15, "rrrow",  ... m_state.rr > 0.0 ? StringFormat("%.2f R", m_state.rr) : "- R");
Text(16, "sizerow",... StringFormat(T(SSR_S_LOT), m_state.lot_from_risk));
```

[CONFIRMED FROM CODE]
plus the risk percentage and its money value (`:1350-1359`) and a button whose caption *is* the
order it will place (`"openln"`, `:1444-1460`, captioned `Place BUY STOP 1.24` or
`Open LONG 1.24`). The numbers are produced once, in `CSSRGroupPort::ReadState`
(`SSR_GroupPort.mqh:289-330`), from the engine's own preview calls — `PreviewLot` /
`PreviewPendingLot` (`SSR_TradingEngine.mqh:805-833`) — on the same fill price the order will
use, with a comment that says precisely why a second formula in the UI would be the one that
drifts. **This design is correct and must be preserved.** The preview and the order already
share one lot-sizing call.

So the work below is *completion*, not replacement.

#### G.4.2 The six gaps

1. **The preview stops at geometry; the cost model is invisible.** [CONFIRMED FROM CODE]
   `risk_money = MoneyFor(lot, |entry − sl|)` and `reward_money = MoneyFor(lot, |tp − entry|)`
   (`SSR_GroupPort.mqh:321-322`). Neither includes commission
   (`m_exec.commission_per_lot × volume`, charged twice — once at `Open()`
   `SSR_TradingEngine.mqh:754` and once in `BookExit`), nor slippage
   (`InpSlippage`, always adverse, `FillPrice` `:120-126`), nor the spread already paid at
   entry. `grep -n "commission\|slippage" SSR_Panel.mqh SSR_ReplayPort.mqh` returns **nothing**:
   the execution model the user configured in the inputs dialog is never shown again.
2. **"Max loss" is not the max loss.** [CONFIRMED FROM CODE] A `Money(-risk_money)` of −$50 on
   a 1.24-lot trade with `InpCommission = 3` is really −$50 − $7.44 = −$57.44 before slippage.
   The trader sizing to 0.50% is actually risking 0.574%.
3. **The risk-money label and the sizing disagree about the account.** [CONFIRMED FROM CODE]
   `SSR_Panel.mqh:1354-1355` shows `Money(m_state.balance * m_state.risk_percent / 100.0)` —
   **balance** — while every sizing call in the engine uses **equity**:
   `SSR_TradingEngine.mqh:767`, `:797`, `:810`, `:832`, all `m_risk.LotForRisk(Equity(), ...)`.
   `out.balance = m_acct.Balance()` and `out.equity = m_acct.Equity()` are separate wire fields
   (`SSR_GroupPort.mqh:237-238`), so with $300 floating the sheet says "0.50% = $50.00" while
   the engine sizes for $51.50. New finding, not previously recorded. **Severity: MEDIUM.**
4. **Margin is never previewed.** [CONFIRMED FROM CODE] `UsedMargin()`, `FreeMargin()` and
   `MarginLevel()` exist on the engine; `FreeMargin()` has **no caller anywhere in the
   repository**. The consequence is **trading-exec-6** (CONFIRMED, MEDIUM): an unaffordable
   order is accepted, charged commission, and stopped out on the next tick — with nothing
   before the click that could have warned the trader.
5. **There is no preview at all for the market Buy/Sell buttons.** [CONFIRMED FROM CODE] The
   `risk_money` / `reward_money` / `rr` block is inside `if(m_lines != NULL && m_lines.IsArmed())`
   (`SSR_GroupPort.mqh:270`). With no lines armed, the Buy and Sell buttons still work — they
   route `Panel:2113-2114 → GroupPort:887-888 → Market()` (`:1067-1106`), sizing from the
   `m_stop_points` stepper — but the sheet shows no stop price, no risk money, no R and no lot.
   The trader presses a button whose consequences are not on screen.
6. **`Market()` and `MarketAt()` are two order paths with different guarantees.**
   [CONFIRMED FROM CODE] `MarketAt` (the lines path) passes `TagOrDefault()` and applies the
   trailing distance:
   ```
   1054:  long t = m_acct.OpenWithRisk(type, m_risk_percent, sl,
   1055:                               (tp > 0.0 ? tp : 0.0), TagOrDefault());
   1062:  if(m_trail_points > 0.0)
   1063:     m_acct.SetTrailing(t, m_trail_points);
   ```
   `Market` (the deal-button path) does neither:
   ```
   1102:  long t = m_acct.OpenWithRisk(type, m_risk_percent, sl, tp, "");
   1103:  if(t <= 0)
   1104:    { m_trade_error = m_acct.LastError(); return false; }
   1105:  return true;
   ```
   So the Setup name typed into `tagbox` and the trailing distance set on the Positions sheet
   silently do not apply to trades opened with the Buy/Sell buttons. The statement's Tag column
   — the whole point of which, per the comment at `:1050-1053`, is to answer "which of my
   setups actually works" — is blank for exactly those trades. New finding, not previously
   recorded. **Severity: MEDIUM.**

   Related, same area: the deal buttons' dimming is cosmetic only. `SSR_Panel.mqh:1472-1476`
   computes `dim_buy` / `dim_sell` and passes them as *colours*; `TradeButton`
   (`:2113-2114`) has no corresponding guard, so pressing the dimmed Sell while a long
   three-line setup is drawn opens a short sized from `m_stop_points` — a trade that
   contradicts what is on the chart. New finding. **Severity: LOW.** [CONFIRMED FROM CODE]

#### G.4.3 The specification

**Contract.** One new value type, one new engine method, four new wire fields, one changed
sheet band. The preview and the order continue to come from the same call — that rule is not
negotiable and is the reason the existing design works.

**(a) `SSRRiskPreview` — new struct in `SSR_TradeTypes.mqh`** (flat, pointer-free, like every
other struct that crosses the port):

```
struct SSRRiskPreview
  {
   bool   valid;            // false => `why` says what to drag
   string why;              // already exists as order_why; same words
   ENUM_SSR_ORDER type;     // BUY / SELL / *_LIMIT / *_STOP, from the geometry
   double entry;            // fill price the order WILL use (FillPrice or the line)
   double sl, tp;
   double sl_points;        // |entry - sl| / point   - the coach's unit
   double volume;
   double risk_pct_asked;   // what the ladder says
   double risk_pct_real;    // what it actually costs, incl. costs  <- the honest one
   double risk_money;       // |entry-sl| in money at this volume
   double reward_money;
   double commission;       // per_lot * volume * 2   (both sides)
   double spread_cost;      // (ask-bid) in money at this volume, paid at entry
   double slip_cost;        // slippage_points * 2 in money (always adverse)
   double max_loss;         // risk_money + commission + slip_cost      <- headline
   double target;           // reward_money - commission - slip_cost    <- headline
   double rr;               // target / max_loss - net, not gross
   double margin;           // volume * margin_per_lot (0 = not modelled)
   double free_margin_after;
   bool   affordable;       // margin <= FreeMargin()
  };
```

**(b) `CSSRTradingEngine::PreviewFor(...)` — one method, the single source of truth.**
It must be *the same code the order takes*, so implement it as the front half of
`OpenWithRisk` / `OpenPendingWithRisk` and have those two call it:

```
bool PreviewFor(const ENUM_SSR_ORDER type, const double risk_percent,
                const double sl, const double tp,
                const double pending_price,   // 0 = market
                SSRRiskPreview &out);
```

* `entry` = `pending_price > 0 ? pending_price : FillPrice(SSRIsLong(type), true)` — the
  existing rule, unchanged.
* `volume` = `m_risk.LotForRisk(Equity(), risk_percent, entry, sl)`; on 0, `out.valid = false`
  and `out.why = m_risk.LastReason()` — the risk engine's refusal strings are already written
  for a human ("*0.50% of 10000.00 is 50.00, below the minimum lot…*", `SSR_RiskEngine.mqh:124-126`).
* `commission` = `m_exec.commission_per_lot * volume * 2.0`;
  `slip_cost` = `m_risk.RiskOf(volume, m_exec.slippage_points * m_point * 2.0)`;
  `spread_cost` = `m_risk.RiskOf(volume, m_ask - m_bid)`.
* `risk_pct_real` = `max_loss / Equity() * 100.0` — **equity, matching the sizing**, which
  closes gap 3.
* `margin` = `volume * m_margin_per_lot`; `affordable` = `m_margin_per_lot <= 0.0 || margin <= FreeMargin()`
  — this finally gives `FreeMargin()` its caller and is the pre-trade half of the fix for
  **trading-exec-6**.
* No new risk formula: every money figure goes through `CSSRRiskEngine::RiskOf`, which is what
  `MoneyFor` already wraps. `CSSRRiskEngine` itself needs **no change at all**; it is already
  the right shape. [RECOMMENDATION]

**(c) Wire.** `SSRUiState` (`SSR_ReplayPort.mqh:226-236`) already carries `lot_from_risk`,
`risk_money`, `reward_money`, `rr`, `order_name`, `order_why`. Add six doubles and one bool —
`sl_points`, `cost_money` (commission + spread + slippage, one number), `max_loss`, `target`,
`margin`, `free_margin` and `affordable` — and clear them in `Init()` (`:284-286`). Populate them in
`CSSRGroupPort::ReadState` by calling `PreviewFor` **instead of** the current
`PreviewLot`/`PreviewPendingLot` + hand-computed `MoneyFor` pair at `:302-323`, which removes
the one place the UI still does its own arithmetic. Crucially, **lift the block out of the
`IsArmed()` branch**: when the lines are not armed but `m_stop_points > 0`, derive `sl` exactly
as `Market()` does (`sl = is_long ? Bid − dist : Ask + dist`, `:1086-1087`) and preview that —
closing gap 5.

**(d) The sheet.** Two lines, both inside the existing `g2` group, replacing `slrow`/`tprow`'s
right-hand column rather than adding height. The 63-character `OBJPROP_TEXT` limit (ground
truth) makes the single-line form in the brief impossible — *"Risk 0.50% / SL 32.4 pts /
Volume 1.24 / Max loss $50 / Target $100 / R:R 1:2"* is 77 characters and would be silently
truncated at "R:R" — so it becomes two rows of ≤48 characters each:

```
Text(20, "prev1", x + 8,  gy + 24,
     StringFormat(T(SSR_S_PREVIEW_1),          // "Risk %.2f%%  ·  SL %.1f pt  ·  %.2f lot"
                  m_state.risk_percent, m_state.sl_points, m_state.lot_from_risk),
     SSR_C_TEXT);                                            //  ~34 chars
Text(21, "prev2", x + 8,  gy + 36,
     StringFormat(T(SSR_S_PREVIEW_2),          // "Max loss %s  ·  Target %s  ·  1:%.1f R"
                  Money(-m_state.max_loss, true), Money(m_state.target, true),
                  m_state.rr),
     m_state.rr >= 1.0 ? SSR_C_TEXT : SSR_C_STOP);           //  ~42 chars
```

with a third line shown only when it has something to say (margin modelled, or costs non-zero),
so the frictionless default session gains no clutter:

```
if(m_state.margin > 0.0 || m_state.cost_money > 0.0)
   Text(22, "prev3", x + 8, gy + 48,
        StringFormat(T(SSR_S_PREVIEW_3),       // "Costs %s  ·  Margin %s of %s free"
                     Money(m_state.cost_money), Money(m_state.margin),
                     Money(m_state.free_margin)),
        m_state.affordable ? SSR_C_TEXT_DIM : SSR_C_STOP);   //  ~46 chars
```

**Layout budget — this is the constraint that decides the design** [CONFIRMED FROM CODE]:
`SSR_SHEET_H = 186` (`SSR_Theme.mqh:449`). The Trade sheet today ends at `y + 60 + 96 + 24 = y + 180`
(deal buttons at `gy + 96`, 24 px tall, `gy = y + 60`) — **6 px of slack**. Adding the optional
third row therefore requires moving `openln` from `gy + 46` to `gy + 52`, the flip/entry/clear
row from `gy + 70` to `gy + 76`, and the deal buttons from `gy + 96` to `gy + 100`, ending at
`y + 184` — 2 px of slack. Ship nothing here without running `CheckFrame()` and
`FrameOverflowBottom()` (the panel's own layout-overflow instrument); if the tall sheet is
active (`SSR_SHEET_H_TALL = 326`) there is room to show all three rows unconditionally.

**Slot numbers 20, 21, 22 must be new.** The comment at `SSR_Panel.mqh:1428-1434` records what
happens otherwise: `Text(17, "setuprow", ...)` was originally written as slot 12, the slot the
line above had just cached, "so both missed the cache on every single frame — for ever, on the
sheet a trader spends the session on." Also register the three ids in the hide-list at
`SSR_Panel.mqh:1302-1304` alongside `"slrow","tprow","rrrow"`, or they will linger when another
tab is selected. And note **ui-panel-1** (CONFIRMED, HIGH): `DrawSheet` deletes and recreates
the entire visible sheet on every repaint, defeating both caches — until that is fixed the slot
discipline buys correctness, not speed.

**(e) Confirmation before execution — what *not* to build.** MQL5 has no modal dialog that can
sit over the replay chart without stealing the click stream, and the panel receives only
`CHARTEVENT_OBJECT_CLICK` (ground truth). A confirm *dialog* would therefore be a second
object set with its own hit-testing and its own z-order problem. The product already has the
right pattern and should reuse it: **the arm-then-commit button**, exactly as
`ResetWithConfirm()` does (`SSR_Panel.mqh:2233-2269`, two presses inside `SSR_CONFIRM_MS` =
4000 ms, any other command disarms). [CONFIRMED FROM CODE] Apply it to `openln`/`buy`/`sell`
**only when the preview is adverse** — `!affordable`, or `risk_pct_real > 2 × risk_pct_asked`,
or `rr < 1.0` — so that the ordinary case stays one press (which is the whole point of a
practice tool) and the dangerous case takes two, with the second press captioned
`Confirm: max loss $57.44`. A trader who presses through it has been told.

**(f) Wording.** Every new string goes through `SSRAddString(out, n, SSR_S_PREVIEW_*, "preview.1", ...)`
in `SSR_Strings.mqh` — audit A19 scans the Ui files for literals and will fail the build
otherwise, and this product is localised (`InpLanguage`). Use `·` or two spaces as the
separator, never `|`: the session file and the journal both use `|` as a field separator
(`SaveInto` writes 30 `|`-separated fields per position and sanitises tags of it).

---

### G.5 Execution findings: what must be fixed, in order

#### G.5.1 The ledger invariant — fix these two first, before anything in G.4

**trading-exec-1 (CONFIRMED, CRITICAL)** — `SSR_TradingEngine.mqh:640`. `OnRewind` drops every
position placed after the cut *without reversing the money it moved*:

```
640:  long placed = (m_pos[i].request_msc > 0 ? m_pos[i].request_msc
                                             : m_pos[i].open_msc);
643:  if(placed > msc)
         continue;
      //--- every exit taken in the deleted future, newest first
      UnwindLegsAfter(i, msc);
```

[CONFIRMED FROM CODE] The `continue` is placed *before* the only reversal code in the class, so the position vanishes
from the log while its realised P/L (`BookExit`, `:222`), its commission (`Open`, `:754`;
`CheckPendings`, `:356`) and its accrued swap (`AccrueSwap`, `:427`) stay in `m_balance`. The
'0' key (Reset → `PublishRewind(start_msc)`) therefore leaves an **empty trade log with the
whole session's P/L still in the balance**. Everything downstream is then computed on a
corrupted figure: `Equity()`, every `LotForRisk(Equity(), …)` call, the statistics, the prop
evaluation's daily-loss and target tests, and the Risk Preview specified above. The finding
names the fix — run `UnwindLegsAfter(i, msc)` *before* the `continue`, then
`m_balance += m_pos[i].commission - m_pos[i].swap`. T9.7 misses it because it asserts only that
the ticket is gone, with an OPEN trade and commission 0.

**Why it is first:** the Risk Preview's honesty depends on `Equity()`, and `Equity()` is wrong
after any rewind. Building G.4 on top of this defect would make the preview a
confidently-formatted lie. [INFERENCE]

**trading-exec-2 (CONFIRMED, HIGH)** — `SSR_TradingEngine.mqh:263`. `SSRTradeLeg`
(`SSR_TradeTypes.mqh:143-169`) records volume, price, msc, realised, fee, closing and three
swap fields — and **not** `sl`, `tp`, `trail_peak`, `mae`, `mfe`, `spread_at_exit`. So for a
position that *survives* the cut, a stop moved by `ApplyTrailing` in the deleted future stays
moved: step back to a moment when price was 1.1020 with a trailed stop at 1.1080 and the first
re-emitted tick closes the trade at `StopFill`, reason SL, with auto-pause announcing "stop
loss hit" for a stop that had really been at 1.1000. The same applies to a manual `Modify()`
or `BreakEven()`. **This is the defect that makes step-back untrustworthy in a product whose
entire value proposition is step-back.** [INFERENCE on the last sentence; the mechanism is
CONFIRMED.]

The structural fix is to make the leg a *versioned state record* rather than an exit record:
add `prev_sl`, `prev_tp`, `prev_trail_peak`, `prev_mae`, `prev_mfe` to `SSRTradeLeg` and write a
leg (a "modification leg", `closing = false`, `volume = 0`) on every `Modify`, `BreakEven` and
`ApplyTrailing` move. `UnwindLegsAfter` then restores them in the same newest-first loop it
already runs. Cost: `SSR_MAX_TRADE_LEGS = 8` becomes too small for a trailing stop that moves
every tick — either raise it, or (better) let `ApplyTrailing` overwrite the newest
non-closing leg when it already owns one for the same rewind granularity. Persistence must
follow: `SaveInto` writes 10 fields per `leg=` row and would write 15. [RECOMMENDATION]

#### G.5.2 Execution realism — the fills

| Finding | Class / Sev | One line | Recommended resolution |
|---|---|---|---|
| **trading-exec-5** | CONFIRMED, MEDIUM | `BarIsAmbiguousFor` tests the **whole cached M1 bar**, so a target hit after a mid-bar entry is booked as a stop loss when the bar's earlier low was below the stop (`:164`) | Restrict the test to the part of the bar the position has actually existed for. The engine already has the material: `mae`/`mfe` are updated every tick from entry (`:293-300`). Test `mae <= sl_distance` rather than `m_bar.low <= p.sl`, and at fill time (`:371-384`) compare `open_msc` with the bar's open before using the bar range at all. Keep the pessimism policy — apply it only to price that occurred while the position existed. |
| **trading-exec-8** | CONFIRMED, MEDIUM | `BreakEven`/`Modify` accept a stop on the wrong side of the market; `CheckStops` then *closes* the trade at a guaranteed loss of spread + slippage, reason SL (`:920`, `:844`) | Refuse, do not execute. `BreakEven` should return false with `m_last_error = "the spread has not been covered yet - break-even would close the trade"` when `open_price >= m_bid` (long) / `<= m_ask` (short). `Modify` needs the same side check. This is the one finding in the set that turns a *user's protective action* into a loss, which is the worst possible teaching signal. |
| **trading-exec-9** | CONFIRMED, LOW | Limit entries receive adverse slippage and can fill worse than their limit price (`:345`) | `FillPrice(is_long, opening)` gains a third argument, or `CheckPendings` skips the slip term for `*_LIMIT`. The file already makes exactly this argument for take-profit at `:486-490` and fills TP at its level (`:544`); entry limits should be consistent. Only bites with `InpSlippage > 0` (default 0). |
| **trading-exec-10** | CONFIRMED, LOW | A long entry line inside the spread is classified `BUY_STOP` and fills on the next tick like a market order (`SSR_TradeTypes.mqh:120`) | `SSRPendingFor`'s limit-vs-stop decision uses `bid` for both sides while the long trigger in `CheckPendings` uses `ask`. Pass both prices in and compare the long side against `ask`; widen the on-the-price refusal to cover `(bid, ask)` entirely. With a 20-point spread and `min_dist = 2 pt` the mis-classified window is 18 points wide. |
| **trading-exec-6** | CONFIRMED, MEDIUM | No margin check on entry: an unaffordable order is accepted, charged, then stopped out on the next tick (`:741`) | Two halves. Pre-trade: `SSRRiskPreview.affordable` (G.4.3b) greys the button and names the reason. In the engine: `Open()` refuses with `m_last_error = "not enough free margin"` when `m_margin_per_lot > 0 && volume * m_margin_per_lot > FreeMargin()`. `FreeMargin()` already exists and has no caller. |
| **trading-exec-12** | CONFIRMED, LOW | `Open()` accepts any positive volume from the external path — no step/min/max (`:714`) | `Open()` normalises through the risk engine it already owns: refuse below `m_risk.VolMin()`, cap at `VolMax()`, floor to the step with the same `+1e-9` epsilon `RoundToStep` uses. Affects `CSSRPublisher` and raw strategy calls only; every UI path already rounds. |
| **trading-exec-11** | CONFIRMED, LOW | `AmbiguousPercent` divides ambiguous fills of *still-open* positions by the *closed* count, and can print 200% (`:999`) | Either count only closed positions in the numerator, or divide by `ClosedCount() + <open flagged>`. The honesty figure is the one number in the product that must not itself be wrong. |
| **trading-exec-13** | CONFIRMED, IMPROVEMENT | Auto-pause reasons are English literals with a hard-coded 5-digit price (`SSR_AutoPause.mqh:124`) | Route through `T(SSR_S_*)` and use `m_acct.Digits()`. Note the reason text reaches the panel through Core, which repeats it verbatim, so audit A19 (Ui-files-only) cannot see it — widen A19's scope to `Trading/` reason strings in the same change. |

**Refuted — do not re-raise as defects:** **trading-exec-7** (`SYMBOL_MARGIN_INITIAL` taken as
the whole per-lot margin) and **trading-exec-14** (swap on UTC-midnight calendar days, no
rollover hour or triple-swap day) were both classified **NOT_A_BUG** by the verification pass.
The swap model is consistent with its own stated contract ("per REPLAY day held"); if a
three-day Wednesday is ever wanted it is a [FUTURE FEATURE], not a fix.

#### G.5.3 Reporting and verdict — the numbers the trader is judged by

These are in `Trading/` and reach the same trader through the statement, so they belong to this
section even though they are not execution paths. [INFERENCE]

* **trading-analytics-1 (CONFIRMED, HIGH)** — resuming a saved session **voids a running prop
  evaluation on startup**, before the first candle, with the reason "the clock was moved
  backwards" when no clock moved: `NotifyRestored → PublishRewind(now) → OnRewind`, whose only
  guard is `m_state != RUNNING` (`SSR_PropEvaluation.mqh:443`). Fix by distinguishing a genuine
  backward seek from a restore-to-now — pass the reason through `PublishRewind`, or compare
  `msc` against the evaluation's own last-seen clock and ignore a rewind to the present.
* **trading-analytics-2 (CONFIRMED, MEDIUM)** — the evaluation has no `SaveInto`/`RestoreFrom`
  at all, so a resumed challenge re-bases `m_peak_eq`, `m_day_open_eq`, `m_total_days` and
  `m_trading_days` on current equity. The account *is* restored, so the trades survive and the
  judge forgets them. These two together mean a multi-sitting prop challenge cannot currently
  produce a trustworthy verdict — which is the feature's entire purpose. Fix them as one change.
* **trading-analytics-3 (CONFIRMED, MEDIUM)** — closed-only drawdown walks positions in *slot
  (creation)* order, not close order, so it is wrong whenever trades overlap (`:703`). The same
  slot-order walk drives `win_streak`, `loss_streak` and revenge detection. Sort by `close_msc`
  once and reuse the ordering.
* **trading-analytics-4 (CONFIRMED, MEDIUM)** — the CSV `profit` column is raw while the HTML
  and the headline are net of commission and swap, and `CSSRClassReport` derives won/lost from
  the raw column. Add a `net` column and make the class report read it.
* **trading-analytics-10 (CONFIRMED, LOW)** — `RMultiple()` = `(profit + swap) / risk_at_entry`
  excludes commission while every money measure includes it, so `average_r` can be positive in
  a session whose expectancy is negative. Include the commission; the header comment already
  defines R as the result over the risk taken.
* **trading-analytics-12 (CONFIRMED, LOW)** — a jump forward never runs the evaluation
  (`JumpForward` publishes no `OnClock`), so a jump that completes the window leaves the
  verdict "IN PROGRESS".
* **trading-analytics-5 / -6 / -7 / -8 / -9 (CONFIRMED, LOW)** — a cancelled pending counts as a
  trading day; undefined profit factor prints as `0.00` (the worst reading for the best
  session); revenge detection compares with the previously *opened* trade; average MAE/MFE are
  printed in price units with a money caption; the equity ring drops its oldest half, so live
  max drawdown can *shrink*. All are small, all are visible to the user, and all undermine the
  same thing: a trader's confidence that the numbers mean what they say.

#### G.5.4 Potential risks — label, do not assert

* **trading-analytics-13 (POTENTIAL_RISK)** and **ui-port-session-15 (POTENTIAL_RISK)** — the
  journal exports (`FileOpen(..., FILE_ANSI, ...)`, `SSR_Journal.mqh:173`, `:254`) and the
  session file are written in the terminal's ANSI codepage while the HTML declares
  `charset=utf-8`. Whether any non-ASCII reaches the file depends on the trader's session name
  and trade tags — and the Trade sheet's `tagbox` (`SSR_Panel.mqh:1375`) is a Persian-speaking
  user's most likely source of one. Runtime-dependent; label as such.
* **trading-analytics-14 (POTENTIAL_RISK)** — `Csv()` replaces commas and newlines but neither
  doubles nor wraps double quotes, so a tag or session name containing `"` can merge rows in
  Excel or pandas. No live path sets a quote today.
* **trading-analytics-15 (POTENTIAL_RISK)** — entry/exit screenshots are taken on the chart the
  panel is drawn on, so every PNG contains the panel and whatever card is open; whether it
  occludes the entry bar depends on the runtime corner. Relevant to G.3: it is also the reason
  the VIRTUAL chip in the header is *good* for screenshots and the `(sim)` token on the deal
  buttons costs nothing.
* **core-sync-7 (POTENTIAL_RISK)** — the saved-position file is keyed by origin symbol only, so
  two slots replaying the same symbol can overwrite each other's resume point. Broker- and
  usage-dependent.

---

### G.6 New findings recorded in this section

**[CONFIRMED FROM CODE] What these are, and what they are not.** Each is read from the source quoted
above and is **not** in `verified.json`, which means **none of them went through the three refuters
and two confirmers that produced the 197 CONFIRMED findings.** They are one reader's assertion with
a file and a line behind it — weaker evidence than any `verified.json` CONFIRMED, and the severities
below are self-assigned on C.1's scale without having been tested against C.1's bar. They are
registered in **D.2** as `new-1` … `new-6` so that a roadmap row can cite them and so that no count
of the audit's findings silently absorbs them into the 197. The `new-` column below is that register
id.

| # | Register id | File:line | Severity (self-assigned) | Claim |
|---|---|---|---|---|
| G-1 | `new-1` | `SSR_Panel.mqh:1354-1355` vs `SSR_TradingEngine.mqh:767,797,810,832` | MEDIUM | The risk-money label is computed from **balance**; every sizing call uses **equity**. With floating P/L the two disagree, and the number shown is not the number risked. [CONFIRMED FROM CODE] |
| G-2 | `new-2` | `SSR_GroupPort.mqh:1102` vs `:1054-1063` | MEDIUM | `Market()` (deal buttons) passes an empty tag and never applies `m_trail_points`; `MarketAt()` (lines) does both. The Setup name and the trailing distance silently do not apply to button-opened trades, leaving the statement's Tag column blank for them. [CONFIRMED FROM CODE] |
| G-3 | `new-3` | `SSR_GroupPort.mqh:270-330` | MEDIUM | The whole risk/reward/R/lot preview block is inside `if(m_lines.IsArmed())`, so the market Buy/Sell buttons — which are always live — have no preview at all. [CONFIRMED FROM CODE] |
| G-4 | `new-4` | `SSR_Panel.mqh:1472-1476` vs `:2113-2114` | LOW | Deal-button dimming is colour only; the dimmed button still executes, opening a trade that contradicts the lines drawn on the chart. [CONFIRMED FROM CODE] |
| G-5 | `new-5` | `tools/ssr_audit.py` (absence) | MEDIUM | The product's central safety guarantee — no broker call on any path — is stated in five comments and checked by zero of the 21 audits. See A22 in G.1.2. [CONFIRMED FROM CODE] |
| G-6 | `new-6` | host `SSReplayStandalone.mq5:90-95` | IMPROVEMENT | `InpCommission`, `InpSlippage`, `InpSwapLong/Short`, `InpMarginLot` and `InpStopout` all default to **0**: out of the box the account is frictionless apart from spread, and nothing on the panel says so. A trader who never opens the inputs dialog practises a market that cannot lose to costs. Suggest a broker-realistic default set, or a one-line status-strip note when the model is frictionless. **One consequence worth stating outright, drawn in D's coverage statement:** `CheckStopout` returns immediately when `m_stopout_level <= 0.0 \|\| m_margin_per_lot <= 0.0` (`Trading/SSR_TradingEngine.mqh:438-439`), and both come from `InpStopout` and `InpMarginLot` (installed at `:1168-1169`), so **forced liquidation is dead in the shipped configuration** — and `trading-exec-6`'s "booked, charged, then stopped out" scenario cannot be reached at defaults. [CONFIRMED FROM CODE for the defaults and the guard; the consequence is INFERENCE] |

---

### G.7 Tests and audits this section asks for

[RECOMMENDATION] Each is written so that it fails today and passes after the corresponding fix
— the project's own standard for evidence.

1. **T9.8 — the ledger invariant, directly.** After any sequence of opens, partials, closes and
   rewinds, assert `Balance() == InitialBalance() + Σ(profit + swap − commission)` over
   `At(0..Total()-1)`. This single assertion catches **trading-exec-1** and any future
   variant of it. Run it with `InpCommission != 0`, which is what T9.7 fails to do.
2. **T9.9 — rewind restores the stop.** Open with a trail, let `ApplyTrailing` move the stop,
   `OnRewind` to before the move, assert `sl` is back at its original value and the position is
   still open. Catches **trading-exec-2**.
3. **T9.10 — break-even inside the spread is refused, not executed.** Catches **trading-exec-8**.
4. **T9.11 — the preview equals the order.** Call `PreviewFor(...)`, then `OpenWithRisk(...)`
   with the same arguments on the same tick, and assert the resulting position's `volume`,
   `open_price` and `risk_at_entry` match the preview to the last decimal. This is the test
   that keeps G.4's core promise structural rather than aspirational.
5. **A22** (and optionally A23, A24) per G.1.2, each verified by breaking the code on purpose
   and confirming the audit names the line.
6. **Fix T9's own setup order first.** **tests-b-6** (CONFIRMED, MEDIUM): every
   `Risk().Configure` in T9 is discarded microseconds later by `Load`, which broadcasts
   `OnSessionStart` → `ConfigureFromSymbol("TEST")`; the six sections silently run on the
   unknown-symbol fallback specs. T10's `Begin()` documents the correct order and does the
   opposite. Any new lot-sizing assertion added to T9 before this is fixed measures the
   fallback path. **tests-b-11** (CONFIRMED, LOW) is the same file's one-sided rounding
   assertions, which pass when `LotForRisk` refuses outright.

---

### G.8 Priority

| Order | Item | Why first |
|---|---|---|
| 1 | **trading-exec-1** | The balance is the account. Nothing above it can be trusted, including the Risk Preview. CRITICAL. |
| 2 | **trading-exec-2** | Step-back is the product. A stop that survives a rewind makes it lie. HIGH. |
| 3 | **A22** (G.1.2) + G-5 | Cheap, mechanical, and it protects the one claim that would matter most if it ever failed. |
| 4 | **trading-exec-8**, **trading-exec-6**, **trading-exec-5** | Three ways the engine produces a loss the trader did not choose. |
| 5 | **G.4 Risk Preview** (G-1, G-3, G.4.3) + `(sim)` wording (G.3) | The decision-time surface. Depends on 1. |
| 6 | **trading-analytics-1 + -2** | A prop verdict that cannot survive a resume is not a verdict. |
| 7 | G-2, G-4, **trading-exec-9/-10/-11/-12**, **trading-analytics-3/-4/-10** | Consistency of the two order paths and of the reported numbers. |
| 8 | **trading-exec-13**, remaining LOW analytics, POTENTIAL_RISK encoding items | Polish, localisation, export correctness. |

**One sentence to keep:** the virtual account's design — one ledger, one lot-sizing call shared
by the preview and the order, the engine knowing nothing about charts or files — is right, and
every recommendation above is written to extend it rather than to replace it.

# Complete analysis — Soft4FX Forex Simulator 2.0.7 (the uploaded video)

> Written from the video, not from memory. The file was decoded with
> `ffmpeg` into 433 frames (one per second) and the frames were read one
> by one. Every statement below carries the second of the frame it was
> read from. Nothing I did not see is written here.
>
> File: 433.4 s (7 min 13 s), 1366×706, 30 fps, H.264, 18,141,558 bytes.

---

## 1. The startup sequence, step by step

| sec | what is on screen |
|---|---|
| 0 | ordinary MetaTrader, chart `US30.Z26, M5`, dark theme |
| 7–8 | the expert attaches. **The host chart turns white**, a product-box bitmap sits top-left, a large heading reads "Forex Simulator 2.0.7", and two green lines say "Please do not close this chart (but you can minimize it). It is required by the simulator." |
| 8–20 | a **Login** window: Demo mode / Full mode, E-mail, Activation code, Hide, "I lost my code", Save credentials, OK |
| 21–78 | the **Data Center**: Data folder + Change Folder, Data provider (Dukascopy), a symbol table with Symbol / Downloaded Range of Data / Update / Download / Clear, and Select-Deselect All, Update All Selected, Download All Selected, Clear All Selected, Close |
| 60 | one row is filled in: `DJI30 - Dow Jones 30   14/09/2021 --> 13/09/2023`. **The available range per symbol is visible before anything is started** |
| 80–147 | the **New Simulation** window — one window, three numbered boxes |
| 148 | **Start Simulation** is pressed; a `DJI30.fsim,H1` chart is created and opened |
| 149 on | the main control window plus a strip of chips on the chart |

### The New Simulation window (frames 86 and 130)

- **Step 1** — Data provider
- **Step 2** — Instrument + "Add to List" + a `Selected: 1 / 20` counter, and a
  table of `# / Symbol / Range / Pip Size [points] / Lot Size [units] / Spread [points] / Remove`,
  with one line underneath: **`Common Range: 19/09/2021 --> 13/09/2023`**
- **Step 3** — two columns.
  Left: Start of simulation, End of simulation, Start of charts (`31 days before the start`), Rewinding allowed, Time zone.
  Right: Account currency, Starting balance, Commission per lot, Leverage
- Footer: Cancel / Restore Last Settings / **Start Simulation**

Worth noting: in frame 86 the table is empty, `Start of simulation` is greyed
and `Start Simulation` is disabled. In frame 130, with one symbol added, both
come alive. **The start button does not light up until the input is valid.**

### The main window (frames 149, 232, 414)

Menu row: `Simulation | New Chart | Account | Sessions | News | Trades`

- a large **Play** button (green) that becomes **Pause** (amber) while running — frames 180 and 232
- the date and time `20.10.2021 11:47:18` and the weekday `Wednesday`
- `Speed: 5 x` over a **continuous slider**. Measured off the frames: 1x at the
  start of the groove, 5x at about 13%, 29x at about 35%, 218x at about 48% —
  **the scale is logarithmic, not linear**
- `Auto Pause`, `|< Prev`, `Next >|`
- symbol and timeframe combos, `Sync with chart`, and an offset `-00:02:42`
- left column: Lots, Visual Mode, SL pips, TP pips, Comment / Trailing Stop /
  Auto B/E (each a "Set" link), Save Order / Load Order
- right column: `Market order | Pending order` tabs, a green `Buy @` and a red
  `Sell @`, Spread, Equity with a percentage, Floating P/L, and
  `Close Winners | Close Losers | Close All`
- status bar: `Live Mode | Running | Account in USD` and a **Collapse** link
- frame 416: collapsed, only the transport rows remain and the link reads **Expand**

### The side windows

- **Orders** (frame 206) — the caption is a count: `Orders: 1  Market: 1  Pending: 0`.
  Tabs: `Market & pending | History | Closed trades | Statistics | Graph`
- **Economic News** (frames 252, 292) — a live countdown `To next event: 3 min 36 sec`,
  HIGH/MED/LOW colour coding, past rows greyed and the current event green, a currency filter
- **Sessions** (frame 272) — a 24-hour grid of four bands (Sydney / Tokyo / London /
  New York) with a red vertical "now" line labelled `Wed, 07:43:52`
- **Automatic Pause** (frame 200) — "Pause automatically on:" with SL/TP and
  execution of pending order
- **Home** (frame 430) — where it returns when a simulation ends: a green
  `Connected to account #20242426`, `Demo mode`, and four full-width buttons:
  **New simulation / Load simulation / Data Center / Exit**

---

## 2. One technical fact that has to be said plainly

Those windows are **real Windows windows**: native minimise / maximise / close
chrome, floating outside the chart area, landing on top of the terminal itself.
MQL5 cannot create an operating-system window. That product does it with a **DLL**.

For SS Replay that means:

- the "native window" *look* cannot be matched without a DLL — a Windows-only
  binary, a user who has to tick "Allow DLL imports", and something **I can
  neither compile nor test here**. I am not proposing it.
- but the *behaviour and the information architecture* can be matched exactly,
  and there is an important detail: the startup windows open on the **host
  chart** — the chart the expert is attached to. Full mouse events are available
  there. The click-only constraint applies solely to the panel on the replay chart.

In other words, what the user asked for — "from the very start when it launches,
its own windows come up" — is precisely where MQL5 is unconstrained.

---

## 3. What v127 builds

| in the video | SS Replay before | v127 |
|---|---|---|
| a branded nameplate on the host chart + "do not close this chart" | nothing | **built** — `SSR_Splash.mqh` |
| the account line ("Connected to account #…") | none | **built** — login, demo/real, broker |
| a home screen listing whole intentions | step 0 existed, no Data Centre | **reworked** |
| Data Center: every symbol's available range | **nothing at all** | **built** — `SSR_DataCenter.mqh` |
| start button disabled until the input is valid | partial | unchanged |
| continuous logarithmic speed slider | already built in v123 | unchanged |
| panel Collapse / Expand | existed, but left only the title bar | **reworked** — it keeps the controls now |
| Sessions window (24-hour grid) | nothing at all | **built** — on the SESSION tab |
| countdown to the next news event | the calendar existed, the countdown did not | **built** — on the clock row |
| the weekday beside the clock | absent | **built** |

### On branding

The request was "like this, but with our branding". So **the dark palette of
design 08 was left untouched** and no colour moved toward that product's
Windows grey. What was copied is the order of the windows and the layout of
the information, not the look.

---

## 4. A real bug this work found

The first draft of the Data Centre drew the hint line six pixels **inside**
the Stop button, straight through it. MetaTrader draws both and reports
nothing; a compiler cannot see a collision between two integers; and all
twenty-one existing audits were green — A19 checks the words, A18 the
contrast, `Extent()` only whether something falls out of the frame.

It was found by rendering the window at its own coordinates and looking at it.
Then the instrument was built: `tools/ssr_layout_check.py` reads the `#define`
constants out of the source itself and reports stacked rows that overlap. It
was tested against the bug it was written for:

```
LAYOUT  data centre: "hint" (y 277..289) runs into "buttons" (y 283) by 6 px
```

---

## 5. What I cannot claim

**This build has not been compiled.** MetaEditor is not on this machine and the
organisation's proxy refuses `download.mql5.com` and every MetaQuotes host with
HTTP 403. What has been done: the 21 static audits, brace and parenthesis
balance, 221 strings matched against the enum, the signature of every widget
call checked against the widget class, and the layout collision check.
None of that is a compiler. The first compile happens on your machine.

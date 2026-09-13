# ARCHITECTURE MAP — subsystem `ui-plumbing`

Build v125. Eight files under `/home/user/academyss/mt5-replay/MQL5/Include/SSReplay/Ui/`:
`SSR_Widgets.mqh` (697), `SSR_Theme.mqh` (582), `SSR_Layout.mqh` (145),
`SSR_Keys.mqh` (278), `SSR_Command.mqh` (177), `SSR_Palette.mqh` (274),
`SSR_KeyCard.mqh` (132), `SSR_Strings.mqh` (760).

Everything here runs on the **replay chart**, which the EA is *not* attached to.
The only input the subsystem ever receives is `CHARTEVENT_OBJECT_CLICK`
(forwarded) and `OBJPROP_STATE` polled off buttons; `CHARTEVENT_KEYDOWN` is
forwarded by the host from the chart the EA *is* on. There are no mouse
coordinates, no focus system, no clipping, no layout engine, no bidi.

---

## 1. Include graph (within the subsystem)

```
SSR_Theme.mqh ──> ../Common/SSR_Types.mqh            (ENUM_SSR_STATE, ENUM_SSR_FIDELITY)
SSR_Widgets.mqh ─> SSR_Theme.mqh
SSR_Layout.mqh ──> SSR_Theme.mqh                      (for SSR_PAD, SSR_GAP)
SSR_Keys.mqh ────> (nothing)
SSR_Command.mqh ─> SSR_Keys.mqh
SSR_Strings.mqh ─> (nothing)
SSR_KeyCard.mqh ─> ../Common/SSR_Types.mqh, SSR_Strings, SSR_Theme, SSR_Widgets, SSR_Keys
SSR_Palette.mqh ─> SSR_Theme, SSR_Strings, SSR_Widgets, SSR_Command
```

Consumers outside the subsystem: `SSR_Panel.mqh` (includes Theme, Widgets,
Layout, Keys, Palette, Strings, KeyCard indirectly), `SSR_SetupPanel.mqh`,
`SSR_RangeDialog.mqh`, `SSR_SessionDialog.mqh`, `SSR_ReviewCard.mqh`,
`SSR_RevealCard.mqh`, `SSR_FirstRun.mqh`, `SSR_GroupPort.mqh`,
`SSReplayStandalone.mq5`, `Scripts/SSReplay/QA/SSR_QA_Smoke.mq5`,
`Scripts/SSReplay/Tests/SSR_T15_Ux.mq5`.

---

## 2. `CSSRWidgets` — SSR_Widgets.mqh

**Responsibility.** The only place in the product that calls `ObjectCreate` /
`ObjectSet*` for panel chrome. Wraps four MQL5 object types
(`OBJ_RECTANGLE_LABEL`, `OBJ_LABEL`, `OBJ_BUTTON`, `OBJ_EDIT`) into ten
primitives, owns a write-elision cache, and owns a layout-overflow instrument.

### State it owns
| member | meaning |
|---|---|
| `long m_chart` | chart id every object is created on |
| `string m_prefix` | name prefix (`SSRP_`, `SSRS_`, `SSRD_`, `SSRSD_`, `SSRK_`, `SSRX_`, `SSRF_`, `SSRV_`, `SSRR2_`) |
| `int m_created` | cumulative `ObjectCreate` successes; reset only by `RemoveAll` |
| `string m_ck[512]` | cache key = full object name, `""` = free slot |
| `long m_cn[512]` | mixed numeric fingerprint |
| `string m_ct[512]` | the text, stored whole (never hashed) |
| `int m_writes` | cumulative `ObjectSet*` count, the paint-budget instrument |
| `int m_max_r, m_max_b` | far right/bottom edge of every **sized** object drawn since `ResetExtent()` |

`#define SSR_W_SLOTS 512` is declared inside the class body (line 53) but is a
preprocessor global; anyone including the header gets it.

### Public surface
```
Attach(chart_id, prefix)            // ForgetAll() if either changed
Prefix() Created() Writes() MaxRight() MaxBottom()
ResetWrites() ResetExtent()
N(id) -> prefix+id                  // the only name-composition rule
Exists(id) -> ObjectFind >= 0

Rect (id,x,y,w,h,bg,edge)                         -> bool   OBJ_RECTANGLE_LABEL, 9 writes
Label(id,x,y,text,col,size=FS_BODY,font=SSR_FONT) -> bool   OBJ_LABEL, 6 writes
Button(id,x,y,w,h,text,engaged=false,enabled=true)-> bool   -> ButtonC with theme colours
ButtonC(id,x,y,w,h,text,bg,edge,fg,size)          -> bool   OBJ_BUTTON, 9 writes
Edit (id,x,y,w,h,text,set_text=true)              -> bool   OBJ_EDIT, 9(+1) writes, NOT CACHED
Pressed(id) -> bool                 // reads OBJPROP_STATE and clears it (latch consume)
EditText(id) -> string              // "" when the object is gone

Progress(id,x,y,w,h,fraction,fill)  -> bool   = Rect(_bg) + Rect(_fill)
Slider  (id,x,y,w,h,at,stops)       -> bool   = Rect(_tk) + stops*ButtonC(<i>) + Rect(_th)
Group   (id,x,y,w,h,legend)         -> bool   = Rect(_fr) + Rect(_lb) + Label(_lg)
Chip    (id,x,y,text,fg,bg,fs)      -> int w  = Rect(_bg) + Label(id)
Meter   (id,x,y,w,h,value,limit,fill,over_is_bad=true) -> void = Rect(_bg) + Rect(_fill)|Remove + Rect(_lim)
List    (id,x,y,w,row_h,rows[],first,shown,selected)   -> void = Rect(_bg) + shown*(Button|ButtonC|Remove)
ListClear(id,shown)                 // Remove(_bg) + Remove(<i>) for i<shown
Toast   (id,x,y,w,text,accent)      -> void   = Rect(_bg) + Rect(_ac) + Label(id)
ToastClear(id)

Hide(id,hidden)                     // OBJPROP_TIMEFRAMES = OBJ_NO_PERIODS|OBJ_ALL_PERIODS, then Forget
Remove(id)                          // ObjectDelete, then Forget
RemoveAll() -> int                  // ObjectsDeleteAll(chart, prefix, 0) + ForgetAll + m_created=0
CountOwned() -> int                 // scan ObjectsTotal(chart,0), StringFind(name,prefix)==0
```
Free function: `SSRPurgeChart(chart, keep="") -> int` — deletes every object on
the chart whose name starts with `"SSR"` except `keep`, iterating backwards over
`ObjectsTotal(chart,-1,-1)`. This is the cross-prefix sweep; the per-instance
`RemoveAll()` only clears its own prefix.

### Private surface
```
Slot(name) -> int      // FNV-1a 64 over the name, mask to 512, linear probe max 8, -1 on failure
Same(name,nums,text)   // slot hit AND name equal AND nums equal AND text equal AND ObjectFind>=0
Keep(name,nums,text)   // write the slot (no-op when Slot returns -1)
Forget(name)           // clear the slot IF m_ck[k]==name
ForgetAll()
Extent(x,y,w,h)        // m_max_r/m_max_b := max(..., x+w / y+h)
Mix(a,b) -> a*1000003 + b
Common(name)           // CORNER_LEFT_UPPER, SELECTABLE=false, SELECTED=false, HIDDEN=true, ZORDER=100
```

### Invariants the code relies on
1. **Creation order is the only z-order.** All objects get `OBJPROP_ZORDER=100`,
   so ties resolve by creation order. `Slider` depends on this (frame → cells →
   thumb), `Chip`/`Toast`/`Group` depend on it (plate before text),
   `Meter` depends on it (`_bg` → `_fill` → `_lim`).
2. **`ObjectCreate` refuses an existing name**, so every primitive checks
   `ObjectFind < 0` before creating and only ever creates once.
3. **The early return needs BOTH "unchanged" AND "still there".** `Same()`
   therefore ends with `ObjectFind`. Deletion, not drawing, is the dangerous case.
4. **The text is never hashed** — `m_ct[]` holds the whole string and is compared
   with `==`. The numbers *are* folded into one `long` by `Mix`.
5. **`Extent` covers sized objects only.** Labels are excluded by design (MQL5
   offers no text measurement), so the overflow instrument is blind to a long label.
6. **`OBJPROP_STATE` is never written by a draw** (ButtonC, lines 388-394): the
   latch is how the panel learns about a click, and clearing it during a repaint
   would erase presses. Only `Pressed()` and the panel's own poll clear it.
7. `Edit` writes `OBJPROP_TEXT` only when `set_text` or when the object was just
   created, so a repaint cannot erase what the user is typing.
8. `Extent()` is called **before** the `Same()` early return in `Rect`,
   `ButtonC` and `Edit`, so the measurement is complete on a fully-cached frame.

### What it writes
Chart graphical objects only. No files. Log: nothing (only `SSRPurgeChart`
prints `[ui] swept %d object(s)...`).

### Measured numbers quoted in the file
561 property writes per still frame before the cache; 39.05 ms mean repaint
against a 40 ms pump; 561 writes → 77 lookups on an unchanged frame.

---

## 3. `SSR_Theme.mqh` — tokens, metrics, switches

**Responsibility.** The only file allowed to contain a colour (enforced by audit
A17). Also holds all pixel metrics and the two compile-time switches.

### Palette switch (lines 75-77)
```
#define SSR_THEME_RAIL      <- active
//#define SSR_THEME_LIGHT
//#define SSR_THEME_DARK
```
Each of the three blocks defines **exactly the same 51 `SSR_C_*` tokens**
(verified: symmetric difference of the three token sets is empty). Token groups:
surfaces (PANEL, PANEL_EDGE, HEADER, WELL, WELL_EDGE, GROUP_EDGE, STATUS),
text (TEXT, TEXT_DIM, TEXT_FAINT), buttons (BTN, BTN_EDGE, BTN_TEXT, BTN_ON,
BTN_ON_TEXT, BTN_ON_EDGE), tabs (TAB, TAB_ON, TAB_EDGE), semantic (RUN, HOLD,
STOP, IDLE), deal (BUY, BUY_EDGE, SELL, SELL_EDGE, DEAL_TEXT, DEAL_DIM),
trackbar (TRACK, TRACK_EDGE, TRACK_FILL, THUMB, THUMB_EDGE, TICK),
identity (ACCENT, PRIMARY, PRIMARY_EDGE, PRIMARY_TEXT), chart-side
(LINE_SL, LINE_TP, LINE_ENTRY, LINE_LONG, LINE_SHORT, TRADE_WIN, TRADE_LOSS,
PICK_LINE, PICK_INFO, NEWS_HIGH, NEWS_MED, NEWS_LOW).

`SSR_C_THUMB_EDGE` and `SSR_C_TICK` are declared in all three palettes and
referenced by **no draw site anywhere in the product**.

### Contrast table (lines 354-421)
49 machine-readable comment lines `//--- SSR_CONTRAST: <fg> on <bg> <text|ui>`,
placed *after* the `#endif` so audit A18 holds whichever palette is built to the
same bar (`text` → 4.5:1, `ui` → 3.0:1). Kept by hand; there is no way to derive
which colour is drawn on which surface without a layout engine.

### Type
```
SSR_FONT "Tahoma"   SSR_FONT_MONO "Tahoma"   (deliberately the same face)
SSR_FS_TITLE 9   SSR_FS_BODY 8   SSR_FS_CLOCK 13   SSR_FS_SMALL 7
```

### Metrics
```
SSR_SHEET_H        186
SSR_SHEET_GROW     140
SSR_SHEET_H_TALL   (186+140) = 326
SSR_LAYOUT_RAIL                       <- active
  rail:   SSR_PANEL_W 310  SSR_RAIL_W 44  SSR_ACT_H 21
  else:   SSR_PANEL_W 420  SSR_RAIL_W  0  SSR_ACT_H  0
SSR_PANEL_H        (23+32+27+21+21+SSR_SHEET_H+18+8)   = 336
SSR_PANEL_TALL_H   (SSR_PANEL_H + SSR_SHEET_GROW)      = 476
SSR_PANEL_COMPACT_H 128                (23+32+27+21+18+7)
SSR_PICK_LINE      "SSR_PICK_LINE"     (the one object a chart sweep keeps)
SSR_PAD 8   SSR_ROW_H 19   SSR_HEADER_H 20   SSR_BTN_H 22   SSR_GAP 5
SSR_SIDE_W 104 (non-rail only)   SSR_TAB_H 21   SSR_STATUS_H 18
SSR_CONFIRM_MS 4000               // how long a destructive button stays armed
SSR_TRACK_H 16
SSR_TAB_TRADE 0  SSR_TAB_POSITIONS 1  SSR_TAB_STATS 2  SSR_TAB_SESSION 3
SSR_TAB_COUNT 4  SSR_TAB_PROP 4  SSR_TAB_MAX 5
```
`SSR_TAB_PROP == SSR_TAB_COUNT` by design: Prop is the fifth sheet and exists
only while an evaluation is configured; `TabCount()` is a question, not a
constant (`SSR_Panel.mqh:1104` returns `prop_on ? SSR_TAB_MAX : SSR_TAB_COUNT`).

### Functions
```
color SSRStateColor(ENUM_SSR_STATE)        PLAYING->RUN, PAUSED->HOLD,
                                           LOADING/RESETTING/COMPLETED->ACCENT,
                                           ERROR->STOP, default IDLE
color SSRFidelityColor(ENUM_SSR_FIDELITY)  FULL_TICK->RUN, SYNTHETIC->TEXT_DIM,
                                           BAR->HOLD, default TEXT_FAINT
```

### What it writes
Nothing. Header-only definitions.

---

## 4. `SSR_Layout.mqh` — the mirrored coordinate system

**Responsibility (stated).** "The one place that knows WHERE." A future RTL
layout in MQL5 can only be a mirrored coordinate system, so every draw site was
to be positioned through these helpers.

### Public surface
```
struct SSRFrame { int x, y, w, pad; bool rtl;  Init(fx,fy,fw,fpad=SSR_PAD,mirror=false) }
int SSRLead  (f, off, width)   // LTR: f.x+f.pad+off       RTL: f.x+f.w-f.pad-off-width
int SSRTrail (f, off, width)   // the mirror of Lead
int SSRCentre(f, width)        // f.x + (f.w-width)/2
int SSRInner (f)               // f.w - 2*f.pad
struct SSRRows { int y, h, gap;  Init(top,pitch,spacing=SSR_GAP);
                 int Next(); int Next(height); void Skip(extra=-1);
                 int HeightFrom(top) const }
int SSRColW(f, n, gap=SSR_GAP) // (SSRInner(f) - (n-1)*gap) / n
int SSRColX(f, i, n, gap)      // SSRLead(f, i*(cw+gap), cw)
```

### Actual adoption (measured by grep over all `.mqh`/`.mq5`)
`SSR_Panel.mqh:44` includes the file. **No production file calls any of these
functions or instantiates either struct.** The only callers are
`Scripts/SSReplay/QA/SSR_QA_Smoke.mq5:3354-3386`. `rtl=true` is passed exactly
once, in that test. `SSRCentre` and `SSRInner` have zero call sites anywhere.

### State / writes
Stateless. Writes nothing.

---

## 5. `SSR_Keys.mqh` — commands and the one key table

### `ENUM_SSR_CMD` (25 values incl. NONE)
`NONE, TOGGLE, PLAY, PAUSE, RESET, STEP_FWD, STEP_FWD_10, STEP_BACK,
STEP_BACK_10, JUMP, BOOKMARK, RESTART, SPEED_UP, SPEED_DOWN, FOLLOW,
FIDELITY_CYCLE, REPLAY_FROM_HERE, COLLAPSE, SESSIONS, LINES_TOGGLE, LINES_FLIP,
OPEN_LINES, REVIEW, PANEL_SIZE, KEYS`

### VK defines (lines 46-75)
```
SPACE 32  LEFT 37  RIGHT 39  R 82  F 70  D 68  PLUS 187  MINUS 189
NUMPLUS 107  NUMMIN 109  PGUP 33  PGDN 34  J 74  B 66  S 83  L 76  X 88
TAB 9  H 72  0 48
--- not commands: UP 38  DOWN 40  K 75  A 65  P 80  ESCAPE 27  ENTER 13
```
(`A` and `P` *are* bound despite sitting under that comment; `K` is the palette's
Ctrl+K and `UP/DOWN/ESCAPE/ENTER` are the palette's and the edit box's.)

### `struct SSRKeyBinding { int vk; string label; ENUM_SSR_CMD cmd; string what; bool listed; }`

### `int SSRKeyBindings(SSRKeyBinding &out[])` — 22 bindings, in this order
| # | vk | label | cmd | listed |
|---|---|---|---|---|
|0|32 SPACE|`Space`|TOGGLE|yes|
|1|39 RIGHT|`Right`|STEP_FWD|yes|
|2|37 LEFT|`Left`|STEP_BACK|yes|
|3|34 PGDN|`PgDn`|STEP_FWD_10|yes|
|4|33 PGUP|`PgUp`|STEP_BACK_10|yes|
|5|187|`+ / -`|SPEED_UP|yes|
|6|189|`-`|SPEED_DOWN|no|
|7|107|`Num +`|SPEED_UP|no|
|8|109|`Num -`|SPEED_DOWN|no|
|9|82 R|`R`|LINES_TOGGLE|yes|
|10|9 TAB|`Tab`|OPEN_LINES|yes|
|11|88 X|`X`|LINES_FLIP|yes|
|12|76 L|`L`|LINES_TOGGLE|no|
|13|74 J|`J`|JUMP|yes|
|14|66 B|`B`|BOOKMARK|yes|
|15|83 S|`S`|SESSIONS|yes|
|16|70 F|`F`|FOLLOW|yes|
|17|68 D|`D`|FIDELITY_CYCLE|yes|
|18|48 `0`|`0`|RESET|yes|
|19|65 A|`A`|REVIEW|yes|
|20|80 P|`P`|PANEL_SIZE|yes|
|21|72 H|`H`|KEYS|yes|

18 are `listed` (the key card's row count). **All 22 vk values are distinct.**
Five enum commands have no key: PLAY, PAUSE, RESTART, REPLAY_FROM_HERE, COLLAPSE.

Invariants: no count is kept — `SSRAddKey` grows the array (`ArrayResize(out,
i+8)`) and `SSRKeyBindings` truncates to `i` at the end; the table is rebuilt
from scratch on every call.

### Other functions
```
ENUM_SSR_CMD SSRKeyToCommand(long key)   // rebuilds all 22 bindings, linear scan
string SSRCmdName(ENUM_SSR_CMD)          // 24-case switch, for the log
string SSRKeyHint(void)                  // ONE HAND-WRITTEN 107-char line
```
`SSRKeyHint()` is used at `SSReplayStandalone.mq5:1694` (`Print("[host] ", ...)`)
and asserted in `SSR_T15_Ux.mq5:404`. It is never drawn on a chart.

---

## 6. `SSR_Command.mqh` — the command registry

```
struct SSRCommand { string label; string group; ENUM_SSR_CMD cmd; string action; }
void SSRAddCommand(out[], &i, label, group, cmd, action="")
int  SSRCommands(SSRCommand &out[])                       // 31 entries
string SSRCommandKey(const SSRCommand &c)                 // first key table row whose cmd matches
bool SSRCommandMatches(label, query)                      // case-insensitive SUBSEQUENCE
int  SSRCommandFilter(all[], query, int &hit[])            // indices in table order
```

31 entries in four groups. Exactly one of `cmd` / `action` is meaningful.
- **Replay (11)**: TOGGLE, STEP_FWD, STEP_BACK, STEP_FWD_10, STEP_BACK_10,
  SPEED_UP, SPEED_DOWN, JUMP, RESTART, FOLLOW, FIDELITY_CYCLE.
- **Trade (10)**: actions `buy`, `sell`, `enbtn`, `clrbtn`, `be`, `flat`,
  `troff`; commands LINES_TOGGLE, OPEN_LINES, LINES_FLIP.
- **Session (5)**: BOOKMARK, SESSIONS, REVIEW, action `stmt`, RESET.
- **View (4)**: KEYS, COLLAPSE, PANEL_SIZE, action `move`.

Every `action` string resolves in `CSSRPanel`: `buy/sell/flat/be` →
`TradeButton` (SSR_Panel.mqh:2433-2438), the rest → `Dispatch` (`enbtn` 2728,
`clrbtn` 2726, `troff` 2692-2696, `stmt` 2611, `move` 2605). `move` still runs
`SnapToCorner(); SavePlace();` even though the `[]` button no longer exists, so
the palette is the only surviving way to move the panel.

Unlike `SSRKeyBindings`, `SSRCommands` does **not** `ArrayResize(out,0)` first;
it is idempotent only because it overwrites `[0..i-1]` then truncates to `i`.

---

## 7. `CSSRPalette` — SSR_Palette.mqh

**Responsibility.** A searchable list of every command. Prefix `SSRX_`, its own
`CSSRWidgets`. `#define SSR_PAL_W 330  SSR_PAL_ROW_H 20  SSR_PAL_SHOWN 8`.

### State
`m_w`, `m_chart`, `m_up`, `m_x/m_y`, `SSRCommand m_all[]`, `int m_hit[]`,
`m_n` (matches), `m_first` (top visible row), `m_sel` (index into `m_hit`),
`m_query` (what the edit box held last paint). Query id is the literal `"q"`.

### Public surface
```
IsUp() Query() Matches() SelectedLabel()
Show(chart_id) -> bool   // Attach+RemoveAll, SSRCommands(), Refilter,
                         // x = centred on CHART_WIDTH_IN_PIXELS, y = ch/5
Hide()                   // ListClear("r",8) + RemoveAll + ChartRedraw
Toggle(chart_id) -> bool
Refilter()  Move(delta)
Render()                 // bg(40 px) + cap + Edit("q",...,set_text=false)
                         // + List("r") or the empty state + footer; ends ChartRedraw
Poll() -> bool           // 1) EditText != m_query -> Refilter+Render
                         // 2) Pressed("r0".."r7") -> m_sel = m_first+i, return true
Chosen(SSRCommand &out) -> bool
OnKey(key, bool &run) -> bool   // ESC Hide; ENTER sets run; UP/DOWN Move+Render
```
Row text is `label + "        " + SSRCommandKey(...)`. `~CSSRPalette` calls `Hide()`.

### How it is reached
`CSSRPanel` owns it by value (`SSR_Panel.mqh:132`).
- `Ctrl+K` — `SSR_Panel.mqh:2827-2832`, checked **before** the key table.
- `Dispatch("palette")` — `SSR_Panel.mqh:2748`, but the `K` caption button was
  removed at `SSR_Panel.mqh:932`, so nothing emits that action any more.
- While up: `OnEvent` gives it every KEYDOWN first (2814-2823); `PollClicks`
  polls it **alone** (2466-2471) so one click is never read twice.
- `Render()` is called last in the panel paint (816-817) — creation order is z-order.

### Invariants
- It executes nothing. `RunChosen()` (SSR_Panel.mqh:2423) dispatches down the
  two paths that existed before it (a command, or a button action string).
- The query is polled, not typed into: MetaTrader owns the `OBJ_EDIT`.
- `m_first <= m_n - SSR_PAL_SHOWN` whenever `m_n >= 8` (both `Refilter` and
  `Move` maintain it), so the footer's `k` always equals the row count `List`
  actually draws.

### Writes
Chart objects under `SSRX_`. No files.

---

## 8. `CSSRKeyCard` — SSR_KeyCard.mqh

**Responsibility.** Draw every `listed` binding on the chart, generated from
`SSRKeyBindings()` so it cannot drift from the handler.
`#define SSR_KEYCARD_W 372  SSR_KEYCARD_ROW 16`. Prefix `SSRK_`.

State: `m_chart`, `CSSRWidgets m_w`, `bool m_up`.
```
IsUp()
Show(chart_id) -> bool   // counts listed rows, h = 34 + rows*16 + 26,
                         // Attach+RemoveAll, Rect("bg") at (14,40),
                         // Label "t"/"t2", then per binding Label("k<i>a") at x+12
                         // and Label("k<i>b") at x+86, then "foot" = T(SSR_S_ALL_VIRTUAL)
Hide()                   // RemoveAll + ChartRedraw
Toggle(chart_id) -> bool
Destroy()                // = Hide
```
Height is counted from the table, not chosen. With 18 listed rows
h = 34 + 288 + 26 = 348.

**The card's row text is `b[i].label` and `b[i].what`, which are English
literals inside `SSRKeyBindings()` — the card is the one user-facing surface in
the product that is not translated through `T()`.**

---

## 9. `SSR_Strings.mqh` — the catalogue

### Shape
`enum ENUM_SSR_STR` — 190 values plus `SSR_S_COUNT` last (verified: 190 enum
ids, 190 `SSRAddString` calls, no duplicates, no gaps in either direction).
Groups, in enum order: transport/furniture 13, tabs 8, trade sheet 11,
positions 10, stats 10, prop 14, session 6, review card 11, reveal card 7,
status strip 6, palette 4, trade sheet second half 19, session keyboard hints 4,
key card 3, two diagnostics, range dialog 7, session dialog 11, setup wizard 25,
first-run card 5, rail short forms 14.

```
struct SSRStringEntry { string name; string text; }
SSRStringEntry g_ssr_str[];  bool g_ssr_str_ready;  string g_ssr_lang = "en";
int g_ssr_overrides;
```

### Public surface
```
void SSRAddString(out[], &i, id, name, text)   // indexed by the ENUM, not by call order
int  SSRStringsEnglish(SSRStringEntry &out[])   // resize to COUNT, blank all, then 190 rows
int  SSRStringsMissing(void)                    // counts slots whose name == ""
bool SSRLoadLanguage(const string code)
string T(ENUM_SSR_STR id)                       // one array slot; self-loads English on first use
string SSRLanguage()  int SSRTranslated()  int SSRStringCount()
string SSRStringName(ENUM_SSR_STR id)
```

### `SSRLoadLanguage` contract
1. Always loads English first, sets `g_ssr_lang="en"`, `g_ssr_overrides=0`.
2. Logs `[i18n] %d string(s) have no English text` if `SSRStringsMissing() > 0`.
3. `""`/`"en"` → return true.
4. Path `SSReplay\lang\<code>.txt`; missing file → log and return false, English stands.
5. `FileOpen(FILE_READ|FILE_BIN|FILE_SHARE_READ|FILE_SHARE_WRITE)` — **never
   `FILE_TXT|FILE_ANSI`**, which returns one character per byte and turns UTF-8
   Persian into mojibake. `FileReadArray` into `uchar raw[]`, skip a 3-byte
   UTF-8 BOM, `CharArrayToString(raw, from, WHOLE_ARRAY, CP_UTF8)`.
6. Strip `\r`, split on `\n`; skip blank lines, `#` comments, lines with no `=`
   at index > 0, and lines whose key or value trims to empty.
7. A key is matched by **`name`**, never by index — the enum's numeric value is
   not a stable public identifier. Unknown keys are counted and skipped, never fatal.
8. Logs `[i18n] <code>: <applied> of 190 strings translated[, N line(s) name
   nothing in this build]`.

### Disk
Reads `MQL5\Files\SSReplay\lang\<code>.txt`. Writes nothing.
`fa.txt` (11767 bytes, no BOM, UTF-8) holds **190/190 keys, zero unknown keys,
zero missing keys, and zero printf-specifier mismatches against the English
rows** (verified programmatically). 24 of its values exceed 63 *bytes* while all
are inside 63 *characters* — which is the correct side of MetaTrader's limit.

### Length discipline
No English string exceeds 63 characters (verified: max is 62,
`SSR_S_TOO_NARROW` at 58 before formatting). 39 strings carry printf
specifiers, so the *formatted* length is unaudited; `CSSRPanel::Clip(s, n)`
(SSR_Panel.mqh:242) caps at `min(n,62)` and appends `~` and is applied by hand
at the draw sites that need it.

### Encoding
The header is UTF-8 **without a BOM** and contains six raw U+00B7 `·`
characters inside drawn literals (lines 472, 474, 544) plus three Persian
characters in a comment. It and `SSR_ReviewCard.mqh:155` are the only two
non-ASCII source files in the entire project.

---

## 10. Cross-subsystem contracts a designer must keep

1. **Object names.** `N(id) = prefix + id`. Suffixes reserved by the primitives:
   `_bg` (Progress, Chip, Meter, List, Toast), `_fill` (Progress, Meter),
   `_lim` (Meter), `_tk` `_th` (Slider), `_fr` `_lb` `_lg` (Group), `_ac`
   (Toast), and bare `<i>` digits (Slider cells, List rows). A `List` and a
   `Slider` must never share a base id; a `Chip` and a `Toast` must never share
   one either (the `Chip`'s label and the `Toast`'s label both use the bare id).
2. **Teardown.** `RemoveAll()` clears one prefix. `SSRPurgeChart()` clears every
   `SSR*` name on the chart and is the only thing that removes another part's
   leftovers. `SSR_PICK_LINE` is the one name that gets passed as `keep`.
3. **Paint budget.** `m_w.Writes()` is the instrument; `Rect`/`ButtonC` = 9,
   `Label` = 6, `Edit` = 9 or 10, and the panel's own `Text()` label cache
   (128 slots, `SSR_Panel.mqh:184-207`) sits *above* the widget cache.
4. **Overflow.** `ResetExtent()` at the top of the paint, `CheckFrame(x,y,W,H)`
   at the end (`SSR_Panel.mqh:3020-3035`); it reports once per worsening
   offence and is blind to labels.
5. **Clicks.** Buttons latch. The poll clears the latch *before* acting, and the
   panel throttles a repeat at 200 ms. Draws must never write `OBJPROP_STATE`.
6. **Keys.** One table drives both `SSRKeyToCommand` and the key card. Anything
   that names a key anywhere else (the three `SSR_S_KEYS_*` hint lines,
   `SSRKeyHint()`, the `SSR_S_FIRSTRUN_*` lines, `SSR_S_NOTHING_OPEN`,
   `SSR_S_ROW_HINT`, and the key letters baked into `SSR_S_FOLLOW`,
   `SSR_S_LINES_ON/OFF`, `SSR_S_BOOKMARK`, `SSR_S_JUMP`, `SSR_S_SESSIONS`,
   `SSR_S_FIDELITY`, `SSR_S_FLIP`) is a **second, hand-written list** and the
   audits do not cross-check it.

## Q. PERSIAN / RTL REDESIGN

*The catalogue is finished and the layout has not started. [CONFIRMED FROM CODE] `fa.txt` carries
**190 of 190** strings, `SSRTranslated()` reports 190, and `SSRLoadLanguage` runs at
`SSReplayStandalone.mq5:1804` — before `g_panel.Create` at `:1467` — so by the time one label is
drawn the panel is already speaking Persian. What it is not doing is speaking it in the right
direction. This section is therefore about **geometry, anchors, object decomposition and digits**,
not about words.*

*Written against M (the constraints-first information architecture), N (the page-by-pixel layout) and
O (the control ledger). Nothing here contradicts them; where a decision in M or N acquires a second
reason in Persian, that reason is named at the same place. Build v125, `SSR_LAYOUT_RAIL` and
`SSR_THEME_RAIL` active. **Nothing below has been run on MT5**, and one question in Q.6 cannot be
closed without a terminal — it is isolated behind a single switch rather than guessed at.*

---

### Q.0 The position, in one page

Four facts decide the whole design, and three of them are already written in the repository.

**1. Direction is a coordinate transform, not a text property.** [CONFIRMED FROM CODE]
`SSR_Layout.mqh:7-12` states it exactly:

```
//|  MetaTrader draws an OBJ_LABEL left-to-right from its anchor and  |
//|  offers no bidi layout, no text measurement and no clipping. So   |
//|  a right-to-left panel cannot be a text-direction setting: it     |
//|  can only be a MIRRORED COORDINATE SYSTEM, where every x becomes  |
//|  (frame_width - x - width) and every right-aligned column becomes |
//|  a left-aligned one.
```

[CONFIRMED FROM CODE] That is the right model and it is already implemented: `SSRLead`, `SSRTrail`, `SSRCentre`,
`SSRInner`, `SSRColW`, `SSRColX`, `SSRRows`, all mirroring correctly, all unit-tested
(`SSR_QA_Smoke.mq5:3354-3386`). **The problem is that nothing calls them** — `ui-plumbing-5`
(CONFIRMED, IMPROVEMENT): the only call sites anywhere in the tree are in the smoke test. The file's
own constraint (*"position through here, never by hand"*, `:17-19`) was placed on every phase after
Phase 2 and honoured by none of them, and `docs/ux-ui/localization.md` says so in its own words.

**2. There is no bidi engine, so a mixed run must be decomposed at the draw site, never composed
into one string.** This is the mechanical core of the section (Q.6). It is cheaper than it sounds:
of the 190 catalogue values, **39 carry a `printf` marker and every one of those 39 is
Arabic-script**, but **30 of the 39 place their markers at a logical edge** and split cleanly into a
label object and a value object. Only **9 have a number genuinely inside the sentence**, and one of
those nine (`follow.n`) is already an orphan string with no draw site (L.4.5). *Six live strings on
the panel need a composer.* Everything else needs a second object and an anchor.

**3. MQL5 *does* have text measurement, and two documents in this repository say it does not.**
[CONFIRMED FROM CODE] `TextSetFont` + `TextGetSize` are called in the project's own QA harness —
`SSR_QA_Smoke.mq5:5325-5327` (`LabelBox`, which measures a real `OBJ_LABEL` by reading back its font
and size), `:4604-4605` (the button-overlap stage), `:4951-4952` (the Persian glyph probe), and
throughout `SSR_QA_FontProbe.mq5:62-64`. The comment at `SSR_QA_Smoke.mq5:5300-5307` is the correct
statement of the situation:

```
//| TextGetSize answers with the real face at the real point size on  |
//| the machine the user is on, which is the only place the question  |
//| has an answer: the same label is a different width at 100% and at |
//| 150% display scaling.
```

Against that, `SSR_Widgets.mqh:125-128` (invariant I10) says *"A label's width depends on the glyphs
the font chose and MQL5 will not say"*, `SSR_Layout.mqh:8` says *"no text measurement"*, and
`docs/ux-ui/localization.md` lists *"**No text measurement API.** Column widths cannot be computed
from the string"* under "What MQL5 gives us". **All three are wrong as statements about the
language and right as statements about `ObjectGet*`.** [INFERENCE] the belief is what produced every
px/char estimate in L, M and N, and every one of the five confirmed overflow defects in L.9 that
`CheckFrame()` cannot see. Persian is where that stops being affordable: a language whose glyph
widths nobody on the team can estimate cannot be laid out by estimate.

**[INFERENCE]** The correction is not free — `TextGetSize` is a graphics round trip and the panel repaints at
10 Hz — so it arrives with a memo cache (Q.4.10), and it does not change one line of the shipped
paint budget on a still frame.

**4. The one thing that genuinely cannot be known from source: whether MetaTrader *shapes*
Arabic-script glyphs and orders them right-to-left inside a single `OBJPROP_TEXT`.** The smoke
test already says this, at `SSR_QA_Smoke.mq5:4943-4947` and again at `:4981-4985`, and it is right to
refuse to claim it. This section does not resolve it either. It isolates it behind **one compile-time
switch with two implementations and a ten-second terminal probe** (Q.6.3), which is the same
discipline `SSR_LAYOUT_RAIL` and `SSR_THEME_*` already use: *one commented line has to be able to
undo it.*

> **The deliverable, in one line.** One direction global and seven additions in `SSR_Layout.mqh`;
> an `align` argument threaded through four widget entry points and two width formulas replaced with
> measurements in `SSR_Widgets.mqh`; one frame built once in `CSSRPanel::Render` and ~200 inline `x +`
> expressions routed through it; 30 catalogue entries split into label+value pairs; one digit funnel;
> three new audits. **No new colour token, no new primitive shape, no new control MQL5 cannot draw.**

---

### Q.1 What is already true, and what is already broken

#### Q.1.1 The parts that need no work

[CONFIRMED FROM CODE] These are correct and this section changes none of them:

| | Where | Why it survives RTL untouched |
|---|---|---|
| index-keyed catalogue | `T(ENUM_SSR_STR)` (`SSR_Strings.mqh:735-747`) | one array slot, no lookup, a typo does not compile |
| name-keyed override file | `:698-712` | a translator's key is stable across enum insertions |
| UTF-8 bytes + `CP_UTF8` + BOM skip | `:663-693` | the v117 mojibake fix; the only reason Persian arrives intact at all |
| load before first paint | `SSReplayStandalone.mq5:1804`, with the reason at `:1801-1803` | a direction global set here is readable by every `Create()` |
| `InpLanguage` | `:187` | `""` = English, `fa` = Persian, no recompile |
| click dispatch by object **name** | `PollClicks:2512`, `Dispatch:2569` | **mirroring moves pixels and never touches a name.** `tab0..tab5`, `spdseg0..19`, `ph<r>`/`pb<r>/px<r>` all dispatch identically in both directions |
| `OBJ_BUTTON` text is centred | MQL5; no `OBJPROP_ALIGN` on a button | every button in the product is direction-neutral for free (Q.4.4) |

**[INFERENCE]** The last two are the reason this is a tractable phase at all: **the rail, the transport, the action
strip, the deal pair, the per-row buttons, the pager and every list row need no text-direction work
whatsoever.** They need a mirrored `x` and nothing else.

#### Q.1.2 The five surfaces that are still English, and why they gate RTL

**[INFERENCE]** A mirrored panel with English text on five of its surfaces is worse than an unmirrored one, because
each English island is also an LTR island inside an RTL frame — the exact case Q.6 exists to handle,
arriving by accident instead of by design. From L.8, with their finding ids:

| Surface | Where | Finding |
|---|---|---|
| Key card body — 18 rows, 36 cells | `SSR_Keys.mqh:131-218` literals drawn at `SSR_KeyCard.mqh:92` | `ui-plumbing-1` (CONFIRMED, LOW) |
| Reset confirmation — the one destructive question | `SSR_Panel.mqh:2253`, drawn at `:1929` | `ui-panel-14` (CONFIRMED, LOW) |
| Fill toast — `"   spread %.1f pt"`, `"   NO STOP"` | `SSR_Panel.mqh:795, 799` | recorded under `ui-panel-14`'s corrected claim |
| Review-card observations, up to 6 sentences | `SSR_Review.mqh` `StringFormat` literals | `ui-dialogs-4` (CONFIRMED, MEDIUM) |
| Every word the chart layer draws: `"STOP - drag me"`, `BUY`/`SELL`/`SL`/`TP`, closed-trade captions, leak advice | `SSR_TradeLines.mqh:134` etc. | `chart-12` (CONFIRMED, LOW) |

[CONFIRMED FROM CODE] `chart-12`'s verified evidence adds the reason none of these were caught:
audit A19 filters on `"/Ui/"` in the path (`tools/ssr_audit.py:1458`) **and** only inspects literals
that appear directly as a widget call's text argument (`:1449`) — so a literal assigned to a member
and drawn from the member, or written through `ObjectSetString(OBJPROP_TEXT)`, is invisible to it.

**These are gates, not garnish.** The chart-layer one is the worst: a Persian user is asked to *drag*
objects whose only labels are English, and those objects sit on the candles where no mirror can help
them.

#### Q.1.3 Two defects already in `fa.txt`, found by reading it

[CONFIRMED FROM CODE] The file's own header states the digit rule at `fa.txt:15-17`:

```
# Digits stay Latin on purpose: the panel uses Tahoma because it draws
# all ten digits on the same width, which is what keeps a price column
# lined up. Persian digits break that.
```

Two lines break it:

* `fa.txt:178` — `su.step = مرحلهٔ %d از ۳`. The `۳` is **U+06F3 EXTENDED ARABIC-INDIC DIGIT THREE**,
  sitting in the same string as a `%d` that will render as a Latin digit. One sentence, two digit
  systems. (It is also a hardcoded `3` where the English is `"step %d of 3"`,
  `SSR_Strings.mqh:556` — so a wizard that gains a step is wrong in two languages at once.)
* `fa.txt:215` — `keys.1 = ... PgUp/PgDn ۱۰تایی`. **U+06F1 U+06F0.**

A comment cannot enforce a rule. Audit **A23** (Q.11) makes it mechanical, and `SSRNum()` (Q.7.3)
makes it a policy instead of a convention.

#### Q.1.4 One thing the translator already got right, and it is instructive

[CONFIRMED FROM CODE] `fa.txt:61` is `no.stop = ‏  بدون حد ضرر`. The first character is
**U+200F RIGHT-TO-LEFT MARK**, and it is there for a mechanical reason: the English is
`"  no stop"` with two significant leading spaces (`SSR_Strings.mqh:391`), and the loader runs
`StringTrimLeft(val)` at `:705`. An RLM is not whitespace, so it stops the trim and the two spaces
survive behind it.

[INFERENCE] That is a translator working around a loader, in a file with no documentation of the
behaviour, and it costs one character of the 63-character budget on every frame that draws the note.
It is also the **only** bidi control character in all 190 values (the other 44 occurrences are
`U+200C ZWNJ`, all of them correct Persian orthography). Two consequences:

* [RECOMMENDATION] The indentation belongs in the **draw site**, not in the string. Under Q.6 the
  no-stop note becomes a `!` prefix on its own object at its own `x` (M.4.2, N.4.1), and both the
  leading spaces and the RLM disappear.
* The 44 ZWNJs are evidence worth naming: a translator who inserts zero-width non-joiners is
  translating for a renderer they believe performs **shaping**. That is a belief, not a measurement
  — see Q.6.3.

---

### Q.2 The direction model

#### Q.2.1 One global, set once, read everywhere

**[RECOMMENDATION]** Direction is a property of the **loaded language**, exactly as `g_ssr_lang` already is. It lands in
`SSR_Strings.mqh` beside the language, because that is the file that knows which language is loaded
and it is included by everything that draws:

```
//--- SSR_Strings.mqh, beside g_ssr_lang at :296
bool g_ssr_rtl = false;

//--- inside SSRLoadLanguage, at the two places g_ssr_lang is assigned
//--- (:623 for the English reset, :717 for a loaded override)
g_ssr_rtl = SSRLangIsRtl(code);

bool SSRLangIsRtl(const string code)
  {
   //--- a TABLE, not a test for "not English". German is LTR; a future
   //--- ar.txt or he.txt is RTL, and neither should need a code change
   //--- in the panel.
   return (code == "fa" || code == "ar" || code == "he" ||
           code == "ur" || code == "ps" || code == "fa-IR");
  }

bool SSRIsRtl(void) { return g_ssr_rtl; }
```

[RECOMMENDATION] **Why a global and not a parameter.** ~200 draw sites in eight files would each
have to carry it, and the language is already a global that every one of them reads through `T()`.
A parameter would also allow two regions of one panel to disagree about direction, which is a state
with no meaning.

[RECOMMENDATION] **One escape hatch, and only one.** `input bool InpForceLtr = false;` on the expert,
read once in `OnInit` after `SSRLoadLanguage`, forcing `g_ssr_rtl = false`. It exists so that a user
whose terminal turns out not to shape Arabic can still run the product in Persian with a Latin
layout and read the words, rather than being handed a mirrored panel of reversed glyphs with no way
back. This is the same reasoning as `SSR_LAYOUT_RAIL` and it is the difference between a switch and
a trap.

#### Q.2.2 Two axes that must never be conflated

| Axis | Values | Decided by | Affects |
|---|---|---|---|
| **mirror** | LTR / RTL | `SSRIsRtl()` | every `x`, every anchor, the rail's edge, fill directions |
| **script** | Latin / Arabic-script | the catalogue value itself | shaping, run composition, digit policy |

**[RECOMMENDATION]** A German translation is Arabic-script-free and LTR: it needs nothing in this section but the
63-character budget A19 already checks. A Persian translation is both. **The code must never infer
one axis from the other** — in particular, `SSRIsRtl()` must not be used to decide whether a *number*
is Persian (Q.7.3), and the presence of Arabic characters in a string must not be used to decide
where it is *placed*.

#### Q.2.3 Direction cannot change mid-session, and that is a design choice worth stating

`SSRLoadLanguage` runs once, in `OnInit`, before anything is created. [CONFIRMED FROM CODE] N.0.3's
frame signature (`m_tab`, `m_compact`, `m_tall`, `m_collapsed`, `m_closed`, `lines_armed`, `prop_on`,
`prop_state`, `pos_rows`, `pending`, `m_open_page`, `m_page`) therefore does **not** gain a direction
field: a value that cannot change between two frames is not a signature field, and adding it would
cost a comparison per frame for ever to detect an event that cannot happen.

[RECOMMENDATION] If a future build ever offers a live language switch, it must do exactly two things
and they are both already available: call `ClearCache()` (`SSR_Panel.mqh:210`, which writes `"\x01"`
and `-32000` into every slot so nothing can take the early return) and `m_w.RemoveAll()`
(`SSR_Widgets.mqh:637`, which also `ForgetAll()`s the 512-slot widget cache). Anything less leaves
labels at mirrored coordinates with unmirrored anchors. Write that down at the switch, not here.

---

### Q.3 `SSR_Layout.mqh` — what it needs

[CONFIRMED FROM CODE for what the file already contains; **[RECOMMENDATION]** for the seven additions]
The file is roughly eighty per cent of the answer already and its signatures do not change. Seven
things are missing, and each one exists to remove a class of hand-arithmetic rather than to add a
feature.

#### Q.3.1 What is already correct and is not touched

`SSRFrame` (`:46-57`), `SSRLead` (`:67`), `SSRTrail` (`:75`), `SSRCentre` (`:84`), `SSRInner`
(`:88`), `SSRRows` (`:96-123`), `SSRColW` (`:130`), `SSRColX` (`:137`). [CONFIRMED FROM CODE] the
smoke test already asserts the property that matters — `SSRLead(ltr,37,84) == SSRTrail(rtl,37,84)`
and the converse (`SSR_QA_Smoke.mq5:3367-3370`): *"lead and trail swap exactly - if they did not, an
RTL panel would be subtly wrong rather than obviously wrong."* That assertion is the contract this
section builds on.

#### Q.3.2 The seven additions

**(1) Frame factories, so `rtl` cannot be forgotten.** `SSRFrame::Init`'s `mirror` parameter defaults
to `false` (`:55`). With thirty `Init()` sites in a mirrored build, **a forgotten argument is a
silently LTR region inside an RTL panel** — the "subtly wrong rather than obviously wrong" outcome
the smoke test names. The fix is that no draw site ever writes `Init(..., true)`:

```
SSRFrame SSRPanelFrame(const int x, const int y);            // W = SSR_PANEL_W, pad = SSR_PAD
SSRFrame SSRSheetFrame(const SSRFrame &panel, const int y);  // the 245 px sheet
SSRFrame SSRRailFrame (const SSRFrame &panel, const int y);  // the 44 px rail
SSRFrame SSRBoxFrame  (const SSRFrame &parent, const int off, const int w, const int y);
```

Every one of them reads `SSRIsRtl()` itself. [RECOMMENDATION] Audit **A25** (Q.11) then has something
to assert: *no `SSRFrame` is `Init()`ed directly outside this file.*

**(2) Edge helpers, for anchored text.** `SSRLead`/`SSRTrail` both take a `width`, because they
position a *box*. A label whose width nobody knows needs the **edge** instead, and then an anchor
does the rest (Q.4.1):

```
int SSRLeadEdge (const SSRFrame &f, const int off);   // f.x+f.pad+off        | f.x+f.w-f.pad-off
int SSRTrailEdge(const SSRFrame &f, const int off);   // f.x+f.w-f.pad-off    | f.x+f.pad+off
```

**[RECOMMENDATION]** This is the single most-used addition in the section. Every sentence, every status-ladder warning,
every group legend and every left-hand row label is an edge plus an anchor and needs no measurement
at all.

**(3) An alignment vocabulary.**

```
enum ENUM_SSR_ALIGN { SSR_AL_LEAD, SSR_AL_TRAIL, SSR_AL_CENTRE, SSR_AL_FORCE_LTR };

ENUM_ANCHORPOINT SSRAnchorFor(const ENUM_SSR_ALIGN a)
  {
   switch(a)
     {
      case SSR_AL_LEAD:      return (SSRIsRtl() ? ANCHOR_RIGHT_UPPER : ANCHOR_LEFT_UPPER);
      case SSR_AL_TRAIL:     return (SSRIsRtl() ? ANCHOR_LEFT_UPPER  : ANCHOR_RIGHT_UPPER);
      case SSR_AL_CENTRE:    return ANCHOR_UPPER;
      case SSR_AL_FORCE_LTR: return ANCHOR_LEFT_UPPER;   // clocks, tickers, identifiers
     }
   return ANCHOR_LEFT_UPPER;
  }
```

**[RECOMMENDATION]** `SSR_AL_FORCE_LTR` is not a convenience. It is the declaration that a particular run is an
**identifier** — a symbol name, a clock, a build tag, a seed — and must be laid out as Latin
regardless of the panel's direction (Q.7.6).

**(4) `SSRSplit`, the rail/sheet division.** [CONFIRMED FROM CODE] `Render()` computes the split
inline at `SSR_Panel.mqh:751-753`:

```
         DrawRail(x + SSR_PAD, cy + 4);
         DrawSheet(x + SSR_PAD + SSR_RAIL_W + SSR_GAP, cy + 4,
                   W - 2 * SSR_PAD - SSR_RAIL_W - SSR_GAP);
```

**[RECOMMENDATION]** That is the one expression in the product where the mirror decides **which of two regions gets which
edge**, and it must not be written twice. `SSRSplit(panel, rail_w, gap, out_rail, out_sheet)` returns
both frames with their `rtl` already set; the sheet's width is `SSRInner(panel) - rail_w - gap` in
both directions, so `245` is arithmetic the compiler does, not a number anyone retypes.

**(5) `SSRRun` / `SSRCompose`, the mixed-run mechanism.** Specified in full at Q.6.3.

**(6) `SSRNum()`, the digit funnel.** Specified at Q.7.3.

**(7) `SSRPair`, a two-column row.** The commonest shape on every sheet is *label at the leading
edge, value at the trailing edge*, and it is currently written as two hand-computed `x`es at every
one of about forty sites. One helper returning both edges (and the px gap between them, so an
overflow is detectable) removes forty chances to get it wrong in one direction and eighty in two.

#### Q.3.3 What must not be added

The file's own header forbids it and it is right: *"It is deliberately NOT a layout engine. There
are no rows, no stacks, no constraints"* (`:21-26`). No flow layout, no measurement inside the
layout file (that belongs to the widget set, which owns the chart handle), and **no second direction
concept** beyond `SSRFrame.rtl`. A frame that could be RTL while its parent was LTR is a state with
no meaning on this toolkit.

---

### Q.4 `SSR_Widgets.mqh` — what it needs

#### Q.4.1 `Label()` — the anchor, and the bug waiting inside the cache

[CONFIRMED FROM CODE] `Label()` sets the anchor **only on the frame the object is created**
(`SSR_Widgets.mqh:238-243`):

```
      if(ObjectFind(m_chart, n) < 0)
        {
         if(!ObjectCreate(m_chart, n, OBJ_LABEL, 0, 0, 0))
            return false;
         m_created++;
         Common(n);
         ObjectSetInteger(m_chart, n, OBJPROP_ANCHOR, ANCHOR_LEFT_UPPER);
        }
```

and the fingerprint it caches on is `Mix(Mix(Mix(Mix(x, y), (long)col), size), (long)StringLen(font))`
(`:232-233`) — **x, y, colour, size, font length. No anchor.**

Two consequences, and the second is the dangerous one:

* An `align` argument added without touching the fingerprint would be **silently ignored on every
  object that already exists**, because `Same()` would answer true.
* The cache's own comment states the rule being broken (`:170-180`): *"Skipping a write is only safe
  when NOTHING about the write would differ - the text, and where it goes."* An anchor is where it
  goes.

[RECOMMENDATION] The change, in three parts, all of which must land together:

```
   bool Label(const string id, const int x, const int y, const string text,
              const color col, const int size = SSR_FS_BODY,
              const string font = SSR_FONT,
              const ENUM_SSR_ALIGN align = SSR_AL_LEAD)     // new, last, defaulted
     {
      ENUM_ANCHORPOINT an = SSRAnchorFor(align);
      long fp = Mix(Mix(Mix(Mix(Mix(x, y), (long)col), size),
                        (long)StringLen(font)), (long)an);   // anchor IS the fingerprint
      ...
      ObjectSetInteger(m_chart, n, OBJPROP_ANCHOR, an);      // written every time, not on create
      m_writes += 7;                                          // 6 -> 7
```

**Cost, booked honestly:** one extra property write per cold label. From M.1.2's measured table a
`Label` goes 6 → 7 writes cold and stays **0 writes warm**, because the `Same()` early return is
unchanged. At the still-frame budget M.1.2 projects (~95 `ObjectFind`, ~30 colour writes) this is
zero. On a cold destination draw of ~30 labels it is 30 writes ≈ **2.1 ms once per navigation**, at
the project's own measured 0.07 ms per write.

**Why the anchor and not measurement.** `ANCHOR_RIGHT_UPPER` makes MetaTrader do the right-alignment
with the real glyph widths of the real face at the real display scaling. Measuring the string and
subtracting is a second opinion about the same number, and the second opinion is the one that can be
wrong. Measurement is for *budgets and collisions* (Q.4.9), never for placing right-aligned text.

#### Q.4.2 `CSSRPanel::Text()` — the slot cache must carry the alignment too

[CONFIRMED FROM CODE] The panel's 128-slot label cache compares `text`, `x` and `y` only
(`SSR_Panel.mqh:191-198`) and its rationale (`:171-182`) is the same lesson learned the hard way once
already: *"Dragging the panel moves x and y while every label's text stays the same, so every one of
them took the early return and stayed where it was... The panel tore in half."*

An alignment is exactly that class of property. `Text()` gains the same trailing `align` argument and
a fourth cache array `m_cache_a[SSR_SLOTS]`. [INFERENCE] Without it, the first row on any sheet that
switches a label between lead and trail alignment — the status ladder is the live case, Q.5.4 —
keeps the previous anchor for ever.

#### Q.4.3 `Edit()` — one line, and one dependency that is not the widget's fault

[CONFIRMED FROM CODE] `ObjectSetInteger(m_chart, n, OBJPROP_ALIGN, ALIGN_LEFT)` at
`SSR_Widgets.mqh:302`, again **inside the create branch only**. In RTL it must be `ALIGN_RIGHT`, and
because `Edit()` has no fingerprint at all (it is deliberately never cached, `:297-321`) it can
simply be written unconditionally with the rest of the property block. One line, no cost.

Three things the panel must **not** try to own, stated so nobody builds them:

* **The caret, the selection and the typing direction belong to MetaTrader.** `Edit()`'s header
  already establishes the principle (`:275-286`): the box is read at a moment, never polled. Adding
  key handling to make Persian typing "work" would be a second implementation of a Windows text
  field on a chart object.
* **`m_tag_focus` is assigned only inside the `CHARTEVENT_MOUSE_MOVE` handler**
  (`SSR_Panel.mqh:2903-2907`). Under this audit's ground truth it is never set, so the tag box has no
  focus path and the hotkey suppression at `:2835` never engages — in any language. M.10 carries this
  as unresolved and RTL does not change it.
* **`ui-port-session-15` (POTENTIAL_RISK, LOW) is the real blocker.** The session file is written in
  the terminal's ANSI codepage, so a Persian trade tag does not survive a save/resume round trip.
  [RECOMMENDATION] The setup-tag box is therefore the **one RTL control with a data-loss
  dependency**, and until the session writer is UTF-8 the honest options are to keep the tag
  Latin-only by convention or to fix the writer. Do not ship an RTL tag box over an ANSI file and
  call it localised.

#### Q.4.4 `Button()` / `ButtonC()` — nothing changes, and this is the best news in the section

MQL5's `OBJ_BUTTON` centres its text and exposes no `OBJPROP_ALIGN`. [CONFIRMED FROM CODE]
`ButtonC` (`:358-397`) writes position, size, three colours, font size and text — no anchor, no
alignment — and the panel's dispatch reads the object **name**, never its geometry (`:2512`,
`:2569`). So:

* every rail cell, transport button, action cell, deal button, per-row `½`/`BE`/`✕`, pager arrow,
  speed stepper, speed-groove cell, `reopen`, `collapse` and `close` needs **only a mirrored `x`**;
* a centred single token is direction-neutral whichever script it is in;
* `TabName()`'s condition marks (M.3.4) — `Pos %d`, `Trade !`, `Eval !`, `PASS`/`FAIL` — are the one
  mixed-direction case on a button, and Q.6.2 Shape A handles it by reordering the catalogue string,
  not by adding an object.

[RECOMMENDATION] **A design rule falls straight out of this**: where a sheet row is a single token
that is read and not chosen, prefer a `Rect` + centred `Button`-style treatment over a `Label` only
when the row genuinely has one token. Do not turn read-only rows into buttons to get free centring —
`ui-dialogs-16` (CONFIRMED, IMPROVEMENT) is the record of what a false affordance costs, and M.3.5's
`ListRO` exists precisely to avoid it.

#### Q.4.5 `Chip()` and `Group()` — the two width formulas that are wrong in Persian

[CONFIRMED FROM CODE] both estimate width from a character count:

```
SSR_Widgets.mqh:529   int w  = 10 + StringLen(text)   * 6;   // Chip
SSR_Widgets.mqh:507   int lw = 7  + StringLen(legend) * 5;   // Group legend punch-out
```

`Chip` returns `w` so a row of chips can lay itself out (`:532`), and `DrawCaption` accumulates it at
`SSR_Panel.mqh:889-907` (`int cx = x + 140; cx += m_w.Chip(...) + 4;`). `Group` uses `lw` to punch a
hole in the frame line so the legend is not struck through (`:505-508`).

[INFERENCE] Six pixels per character is a Tahoma-7pt Latin estimate. Persian at the same size is not
six pixels a character, and nobody on this project can say what it is — which is precisely why
`ui-panel-13` (CONFIRMED, LOW) already has the chip row overrunning the collapse button by six
pixels **in English**. In Persian the failure mode is not six pixels; it is a plate that is the
wrong size for its own text, in both directions, with no warning.

[RECOMMENDATION] Both become measurements:

```
   int TextW(const string s, const string font, const int size);   // memoised, Q.4.10
   ...
   int w  = 10 + TextW(text, SSR_FONT, fs);
   int lw = 7  + TextW(legend, SSR_FONT, SSR_FS_SMALL);
```

and the `Group` legend moves to the **leading** edge with its punch-out rect: today `x + 6` / `x + 9`
(`:507-509`), which in RTL must be `SSRLeadEdge(f, 6)` / `SSRLeadEdge(f, 9)` with the label
`SSR_AL_LEAD`. A group legend on the wrong side is the single most visible mirroring failure on a
sheet, because every sheet has two of them.

#### Q.4.6 `List()` and `ListRO` — free, with one argument

`List` draws `ButtonC`/`Button` rows (`:571-587`), so it is direction-neutral except for its `x`,
which comes from the caller. `ListRO` (new, M.3.5 — one `Rect` well plus a cached `Label` per row,
6 writes instead of 9) is where alignment matters, because its rows are labels. It takes the align
and passes it through; **PERFORMANCE and KEYS are both two-column pages** (label column, value
column) and therefore both want `SSR_AL_LEAD` in the first column and `SSR_AL_TRAIL` in the second —
which is Q.6.2 Shape A applied to a list.

#### Q.4.7 `Toast()` — the accent bar is a leading-edge mark

[CONFIRMED FROM CODE] `Toast` (`:604-610`) draws a 3 px accent at `x` and the label at `x + 9`. The
accent bar is a *reading-start* mark, so both mirror:

```
   Rect(id + "_ac", SSRIsRtl() ? x + w - 3 : x, y, 3, 20, accent, accent);
   Label(id, SSRIsRtl() ? x + w - 9 : x + 9, y + 4, text, SSR_C_TEXT, SSR_FS_SMALL, SSR_FONT, SSR_AL_LEAD);
```

The toast's content is itself the worst mixed run in the product today —
`m_state.pos_text[pi] + "   spread %.1f pt" + "   NO STOP"` assembled at `SSR_Panel.mqh:791-800` —
and it is English (Q.1.2). It is rebuilt under Q.6.5 as three objects, which fixes the language gap
and the direction at once.

#### Q.4.8 `Meter()`, `Progress()` and `Slider()` — the three fills, and the one that must not mirror

This is the only place in the section where mirroring is a **semantic** decision rather than an
arithmetic one, so each is decided on its own and the reason is recorded.

| Primitive | Site | Mirror? | Reason |
|---|---|---|---|
| `Progress` | `:399-413`, fill at `x+1` | **yes** | it is *elapsed replay*, read along the reading axis. A progress bar that empties toward the reading start is read as "going backwards" |
| `Meter` | `:540-563`, fill at `x+1`, limit mark at `x+w-2` | **yes** | it is *how much of an allowance is used* against a limit. The limit must sit at the far end of the reading direction, or the distance-to-the-line — the number `SheetProp` exists to manage — is read from the wrong side |
| `Slider` (speed groove) | `:460-491`, cells `i = 0..stops-1` left to right, thumb after the fill | **yes** | it is a *magnitude*, slow to fast along reading order |
| **transport** (`DrawTransport:975`) | `\|<` `<<` `<` `PLAY` `>` `>>` | **NO — see Q.5.3** | it is *time*, and time is not a reading direction |

[CONFIRMED FROM CODE] `Slider` mirrors for free at the dispatch layer and this is worth stating
explicitly, because it looks like it should be a problem and is not. The cell object is
`id + IntegerToString(i)` (`:487`), and `Dispatch` parses the index out of the **name**
(`SSR_Panel.mqh:2503-2512`), guarding against `_tk` and `_th` with `AllDigits`. So mirroring the
cells' `x` while leaving the index mapping alone gives a groove where cell 0 (slowest) is drawn at
the reading start — the right end in Persian — and a click on it still calls
`SSRSpeedLadder(0)`. **Zero dispatch change.** The thumb's `tx` mirrors with the same transform, and
M.1.6's ten-drawn-cells-over-twenty-stops recommendation is orthogonal to all of it.

#### Q.4.9 `Extent()` / `CheckFrame()` — the instrument can finally see labels, and it needs a left edge

[CONFIRMED FROM CODE] `Extent` (`:129-133`) tracks `m_max_r` and `m_max_b` only, and labels are
excluded *by design* because of the belief corrected in Q.0. Two changes:

**(a) Labels enter the instrument.** With `TextW()` available, `Label()` can call
`Extent(x_of_left_edge, y, TextW(...), size_in_px)`. That is what retires invariant I10 and it is the
only mechanism that can ever see `ui-panel-6` (status fidelity anchored at `x+330` in a 310 px
panel), `ui-panel-8` (speed meaning at MAX), `ui-panel-13` (chip row under the collapse button) and
`ui-port-session-7`/`-8`. Every one of those is a label.

**(b) An RTL overflow runs off the *left*, and nothing tracks the left.** `m_max_r`/`m_max_b` have no
`m_min_l`. In a mirrored panel every overflow that today runs past the right edge instead runs past
the left, and `CheckFrame` would report a clean frame while text sat on the candles. Add `m_min_l`
(initialised to a large positive value by `ResetExtent`), `MinLeft()`, and
`FrameOverflowLeft()`. [CONFIRMED FROM CODE] this matters more than it looks: L.9 records that
*nothing in the codebase ever reads `FrameOverflowRight/Bottom`* — so the instrument must be both
completed **and** connected, and the natural consumer is the smoke test's stage 41 (Q.11), not a
runtime warning nobody sees.

#### Q.4.10 The measurement memo — what it costs, and why it is affordable

`TextSetFont` + `TextGetSize` is a graphics round trip. The panel repaints at 10 Hz and draws roughly
sixty labels, so an uncached `TextW()` per label per frame is not affordable and must not be built.

[RECOMMENDATION] Reuse the pattern the file already proved. `CSSRWidgets` gets a second open-addressed
table beside the 512-slot property cache (`:52-56`), keyed on the tuple `(text, font, size)`:

```
   #define SSR_M_SLOTS 256
   string m_mk[SSR_M_SLOTS];      // "text\x01font\x01size", "" when free
   int    m_mw[SSR_M_SLOTS];
   int    m_mh[SSR_M_SLOTS];

   int TextW(const string s, const string font, const int size);
```

with the same FNV-1a slot function, the same eight-probe run, and the same **no-hash-no-collision**
discipline (`:38-43`): the key string is compared whole before the width is trusted. A width that
came from a collision would move a column silently, which is the failure the cache's own comment
refuses to accept for text.

**Why this is cheap in practice.** The panel's strings are overwhelmingly *stable*: labels, legends,
chip texts, group names and key rows do not change from frame to frame. What changes is prices and
money — and those are **right-anchored** (Q.7.4) and therefore never measured at all. [INFERENCE] the
steady-state measurement count on a still frame is expected to be **zero**, with a burst of ~40-60 on
a cold destination draw. If a terminal ever proves otherwise, `TextW()` is one function and the
fallback is the current estimate, behind one `#define`.

**One property that must be honoured:** `TextSetFont` takes tenths of a point as a negative number
and that is what follows OS scaling, as both QA scripts document (`SSR_QA_FontProbe.mq5:52-56`,
`SSR_QA_Smoke.mq5:5306-5307`). `TextW` passes `-size * 10`, never a pixel size, or every number it
returns is right at 100 % display scaling and wrong at 150 %.

---

### Q.5 `CSSRPanel` — what it needs

#### Q.5.1 One frame, built once

[CONFIRMED FROM CODE] `Render()` establishes the origin at `SSR_Panel.mqh:716-718`:

```
      int H = BodyH();
      ClampToChart(W, H);
      int x = m_x, y = m_y;
```

and from there every band receives `(x, y, W)` and does its own arithmetic. The change is to build
one frame here and pass **frames**, not integers:

```
      SSRFrame pf = SSRPanelFrame(m_x, m_y);      // knows W, SSR_PAD and SSRIsRtl()
      ...
      cy = DrawClock(pf, cy);
      cy = DrawTransport(pf, cy);
      cy = DrawSpeed(pf, cy);
      if(!m_compact)
        {
         cy = DrawActions(pf, cy);
         SSRFrame rail, sheet;
         SSRSplit(pf, SSR_RAIL_W, SSR_GAP, cy + 4, rail, sheet);
         DrawRail(rail);
         DrawSheet(sheet);
        }
      DrawStatus(pf, m_y + H - SSR_STATUS_H - 1);
```

[RECOMMENDATION] The band signatures change from `(int x, int y, int W)` to `(const SSRFrame &f,
int y)`. That is the whole mechanical cost of the phase and it is why it has to be one change rather
than fifteen: a half-converted `DrawSpeed` that still takes `x` will keep working perfectly in
English and be wrong in Persian, which is the failure mode `localization.md` already describes about
Phases 3-9 — *"a panel half-mirrored, and I cannot see the result to correct it."*

#### Q.5.2 The rail on the right edge — and dispatch does not notice

[CONFIRMED FROM CODE] `DrawRail` (`:1209-1225`) takes `(x, y)` and draws `n` cells of
`SSR_RAIL_W × 22` with a 3 px gap, all at the same `x`. Under `SSRSplit` the rail's `x` becomes
`SSRLeadEdge(pf, 0)` minus its own width in RTL, i.e. the **right** edge of the panel's padding box,
and the sheet takes what is left. The rail's own comment already promises the property that makes
this safe (`:1203-1206`): *"Same buttons, same ids, same dispatch: only the geometry moved, so a
click on `tab2` still selects Stats whichever layout is built."* That promise now covers a third
layout.

**Geometry, derived, not typed** (`SSR_PANEL_W 310`, `SSR_PAD 8`, `SSR_RAIL_W 44`, `SSR_GAP 5`,
`SSR_Theme.mqh:487-514`):

| Region | LTR `x` | RTL `x` | width |
|---|---|---|---|
| panel frame | `m_x` | `m_x` | 310 |
| rail | `m_x + 8` | `m_x + 310 - 8 - 44` = `m_x + 258` | 44 |
| sheet | `m_x + 8 + 44 + 5` = `m_x + 57` | `m_x + 8` | **245, unchanged** |
| sheet row origin | `sheet.x + 8` | `sheet.x + 245 - 8` (trailing edge) | **237 px of row, unchanged** |

**Nothing in N or O changes.** Every page's row count, character budget and pixel ledger is computed
against a 245 px sheet and a 237 px row, and both are identical in the mirror. That is the property
`SSRLead`/`SSRTrail` were built to give and the reason N can be written once for two languages.

[CONFIRMED FROM CODE] Two one-line follow-ons:

* `ClearCache()` must run on the first frame after `Create()` in a mirrored build. It already exists
  (`:210-217`) and is already called from the constructor; the requirement is only that the *first*
  paint be cold, which it is.
* The default corner. `m_x(12), m_y(24)` in the constructor (`:277-278`) and `m_corner(0)` (`:287`,
  `0 TL`) are a left-corner default. [RECOMMENDATION] In RTL the default becomes the **trailing**
  corner — `m_corner = 1` (TR) and `m_x = chart_width - SSR_PANEL_W - 12`, applied in `RestorePlace`
  where the no-file branch already exists (`:555-557`). A Persian user should not have to move the
  panel to the side their eye starts on. `ClampToChart` (`:445-480`) needs no change: it clamps to
  both edges already, and M.6's correction (clamp before the `m_closed` early return at `:649-655`)
  applies equally in both directions.

#### Q.5.3 Band by band — and the one band that must not mirror

| Band | Mirrors | What changes | Where |
|---|---|---|---|
| caption | **yes** | `title` at the leading edge; `build` tag follows it *in reading order*; `capinfo` after that; chips accumulate along the reading axis (`cx +=` becomes an offset into `SSRLeadEdge`); `collapse`/`close` at the **trailing** edge | `:833-940`, chip row `:889-907`, buttons `:936-939` |
| clock | **yes** | `clock` at the leading edge with `SSR_AL_FORCE_LTR` (Q.7.5); `prog` at the trailing edge with `SSR_AL_TRAIL` — which also retires the hand-computed `x + W - SSR_PAD - 110` at `:957` | `:945-966` |
| progress bar | **yes** (fill direction) | `Progress` mirrors per Q.4.8 | `:968` |
| transport | **NO** | placed as a block; internal order untouched | `:975-1042` |
| speed | **yes** | label at lead, `-` `[value]` `+` in reading order, groove mirrored, meaning text at the trailing edge | `:1045-1100` |
| actions | **yes** | three equal cells through `SSRColX(f, i, 3)` — the existing `bw = (W - 2*SSR_PAD - 2*gp)/3` becomes `SSRColW(f, 3, gp)` and is identical | `:1235-1262` |
| rail + sheet | **yes** | Q.5.2 | `:751-753`, `:1209` |
| status | **yes** | four readouts, and the ladder (Q.5.4) | `:1915-2035` |

**The transport does not mirror, and this is the most important single decision in the section.**

[CONFIRMED FROM CODE] `DrawTransport` (`:975-1042`) draws `|<` `<<` `<` `[PLAY/PAUSE]` `>` `>>` and
then `Reset` across a 10 px separator. Those arrows do not mean "previous" and "next" in a text
sense; they mean **earlier** and **later**. And the thing they operate on is the chart underneath the
panel, whose time axis runs old-on-the-left to new-on-the-right — a MetaTrader property with no API
to reverse. [INFERENCE] A mirrored transport would put the button that means *forward in time*
pointing away from the direction the candles actually advance, on the one control pressed hundreds
of times a session. That is not a localisation, it is a contradiction between two surfaces the user
reads together.

So the transport is laid out as **one LTR block**, positioned by the frame and internally unmirrored.
`Reset` stays at the far end of the block with its 10 px separator intact — the isolation is what
protects it (`:986-991`: *"far enough that a finger reaching for >> does not land on it"*), and the
isolation is preserved whichever side of the panel the block sits on.

**The asymmetry between the transport and the speed groove is deliberate and must be written at both
sites.** The transport encodes **time**; the groove encodes **quantity**. Quantity is read along the
reading axis, time is not. A reader who notices one and not the other will assume a bug, so the
comment block at `:975` gains a paragraph and so does `DrawSpeed`.

[CONFIRMED FROM CODE] One consequence that is *not* an exception: `SSRSpeedMeaning()`'s text —
`"1h in 12m"`, and at maximum the 21-character `"as fast as ticks feed"` drawn into a 52 px reserve
(`ui-panel-8`, CONFIRMED, LOW) — is prose and does mirror, to `SSR_AL_TRAIL` at the trailing edge.
M.4.0's `Clip(..., 11)` becomes a **pixel** budget under Q.5.5, which is the only form of that budget
that means anything in two languages.

#### Q.5.4 The status ladder — the cleanest argument for anchors over measurement

[CONFIRMED FROM CODE] Four of the five ladder levels write slot 50 / id `stbal` at `x + SSR_PAD` and
hide the other four readouts: `:1929` (the armed reset), `:1947` (`m_port.TradeError()`), `:1988`
(`m_pro_why`), `:2001` (`TooNarrow()`), with the numbers at `:2015`. Every one of them is a
**sentence of unknown length** — `TradeError()` strings originate in the trading engine and are not
length-bounded (L.7).

In RTL each must begin at the right-hand edge of the padding box. There is no width to compute and
no measurement to take: `SSRLeadEdge(f, 0)` with `SSR_AL_LEAD`, which resolves to
`ANCHOR_RIGHT_UPPER` at that x. **One expression, correct for a sentence whose length nobody knows,
in both languages.** That is the case anchors exist for and it is why Q.4.1 chose them.

The four resting readouts are the opposite case and are handled at Q.7.4.

[RECOMMENDATION] M.3.7's `stmsg` hygiene recommendation — giving the ladder's warning lines their own
object id rather than borrowing slot 50 — becomes slightly more valuable here, because slot 50's
alignment now differs between the warning (lead, sentence) and the balance (trail, number). Under
Q.4.2's fourth cache array the two would thrash the alignment on the frame a warning appears and
again when it clears. Not a defect; one more reason to do the hygiene.

#### Q.5.5 `Clip()` must become a pixel budget, and it must not cut a Persian word

[CONFIRMED FROM CODE] `Clip(s, max_chars)` caps at 62 and appends `~` (`:242-248`), and is applied at
exactly four sites in a 3049-line file (`:960`, `:1760`, `:1840`, `:1892`). M's rule R5 extends it to
every sheet site with a character budget (46 at `FS_BODY`, 52 at `FS_SMALL`). Persian breaks the
character budget in three ways:

1. **A character budget is a proxy for a pixel budget**, and the proxy's constant is
   language-specific. 46 Latin characters and 46 Persian characters are not the same width and
   nobody can say which is wider without measuring.
2. **Cutting mid-word breaks the joining.** Persian is a cursive script; a cut inside a word leaves
   a letter in a form it should not be in. English degrades to a truncated word; Persian degrades to
   a word that looks misspelled.
3. **A cut that lands on a `U+200C ZWNJ` leaves a trailing zero-width control** with nothing to
   separate. `fa.txt` contains 44 of them.

[RECOMMENDATION] `Clip` keeps its signature for the 63-character *hard* limit and gains a sibling:

```
   string ClipPx(const string s, const int px, const int size = SSR_FS_BODY,
                 const string font = SSR_FONT);
```

which (a) returns `s` when `TextW(s,...) <= px`, (b) otherwise walks back to the last space, (c)
refuses to end on `U+200C`, (d) appends `…` (U+2026, one character where `~` was one character, and a
correct ellipsis in both scripts) and (e) still enforces the 62-character cap so MetaTrader's own
cut can never be the one that happens. The `~` marker's purpose — *"The `~` says the cut was
deliberate"* (`:238`) — is preserved; only the glyph improves.

[INFERENCE] `ClipPx` is also what makes R5 auditable. A character budget is a number a reviewer has
to believe; a pixel budget is the row's own width, which A25 can read off the frame.

#### Q.5.6 `%-12s` column padding — seven sites that never worked

[CONFIRMED FROM CODE] Seven draw sites pad a label with spaces to build a column:

```
SSR_Panel.mqh:1675, 1678, 1681   StringFormat("%-12s %s", T(SSR_S_BALANCE|EQUITY|FLOATING), Money(...))
SSR_Panel.mqh:1687, 1690         StringFormat("%-12s %d", T(SSR_S_BARS|TICKS), ...)
SSR_Panel.mqh:1881               StringFormat("%-12s %d", T(SSR_S_BOOKMARKS), m_state.bookmarks)
SSR_Panel.mqh:1892               Clip(StringFormat("%-12s %s", T(SSR_S_CHARTS), ...), 62)
```

plus two catalogue strings that carry the padding inside the translation itself —
`rejected.guard = %-12s %d      نگهبان %d` (`fa.txt:141`) and `streams.skew` (`:142`).

Space padding aligns a column only in a monospaced face. **Tahoma is proportional**, so these columns
are ragged in English today; in Persian the padding is also on the wrong visual side, and
`StringFormat` pads by *character count* on a script whose characters have no fixed width. Three
wrongs, one fix: **two objects at two `x`es** — which is Q.6.2 Shape A, which is the same change the
mixed-run rule requires anyway. The `%-12s` disappears from the seven sites and from the two
translations, and the columns become correct in both languages for the first time.

[INFERENCE] Four of those seven sites are on the Stats sheet that M.4.3 deletes and the Session sheet
that M.4.4 rebuilds, so most of this arrives free with N.5 and N.6. Do not re-introduce `%-12s` in
the new rows.

---

### Q.6 Mixed runs — the concrete workaround for having no bidi

#### Q.6.1 The rule

> **One object, one direction.**
> A drawn object whose text mixes scripts has an undefined visual order on a renderer with no bidi
> algorithm. A **row** that mixes scripts is fine, because a row is objects.

Everything below is the application of that one sentence.

#### Q.6.2 The four shapes, counted

[CONFIRMED FROM CODE] Measured over all 190 values of `fa.txt`:

| Shape | What it is | Count | Mechanism |
|---|---|---|---|
| **A** | markers sit at a logical edge — label + value | **30** | **split the catalogue entry into two ids, draw two objects** |
| **B** | a number is grammatically inside the sentence | **9** (6 live) | the composer, Q.6.3 |
| **C** | a Latin token that is an identifier, inside Persian prose | 67 values contain Latin letters; most are keys, product names and file names | give it its own column, or accept it as an LTR run at a logical edge |
| **D** | a price or money column | — | right-anchored, never composed (Q.7.4) |

**Shape A — the change that carries the section.** `bal = موجودی %s` becomes two ids: a label
`SSR_S_BAL_LBL = "موجودی"` drawn at the leading edge with `SSR_AL_LEAD`, and the number drawn at its
own `x` with `SSR_AL_TRAIL`. The `%s` leaves the catalogue. Applied to the thirty:

* it removes thirty mixed-direction strings from existence rather than rendering them;
* it fixes the ragged money columns (Q.7.4) in the same edit;
* it retires `%-12s` at seven sites (Q.5.6);
* [CONFIRMED FROM CODE] it costs **+30 catalogue entries and +30 `fa.txt` rows**, against
  `SSR_S_COUNT` currently 190 and an enum whose numeric values are explicitly *not* the public
  identifier (`SSR_Strings.mqh:281-285`) — so inserting is safe by construction;
* [INFERENCE] it costs **one extra object per affected row** — 6 writes cold, 0 warm, one
  `ObjectFind`. At ~20 such rows on a cold destination draw that is ~120 writes ≈ 8.4 ms **once per
  navigation**, and nothing on a still frame. This is the one real cost in Q and it is paid in the
  place M's R1 made cheap.

**Shape B — the six that are live on the panel.**

| id | `fa.txt` | Surface | Note |
|---|---|---|---|
| `day.of.elapsed` | `:93` | EVAL (`SheetProp`) | `روز %d از %d گذشته` |
| `too.narrow` | `:132` | status ladder level 4 | two numbers inside one sentence |
| `tall.needs` | `:133` | status ladder level 3 | two numbers inside one sentence |
| `place.order` | `:198` | TRADE `openln` **button** | `ثبت %s  %.2f لات` |
| `open.order` | `:199` | TRADE `openln` **button** | `باز کن %s  %.2f لات` |
| `su.step` | `:178` | setup wizard | also carries the U+06F3 defect (Q.1.3) |

(`follow.n` at `:26` is the seventh and is an orphan string with no draw site — L.4.5. `rd.bars` and
`rd.cost` at `:148-149` are the range dialog, which M.3.6 keeps as an overlay; they take the same
treatment.)

**Six strings.** That is the entire population the composer exists for, and two of the six are on a
centred button where the composer's output is a single token anyway.

**Shape C — identifiers.** Key names (`H`, `Space`, `PgUp`), `SS Replay`, `SEED`, `HTML`,
`seen.txt`, `InpSession`, and instrument symbols. The rule:

> An identifier never goes inside a Persian sentence. It goes in its own column, or at a logical
> edge of the string.

[CONFIRMED FROM CODE] For the biggest population — the keyboard — this is **already the design M
chose**. M.4.5 moves the key list into the KEYS destination as a generated two-column page (`label`
at the leading edge, `what` in the second column, N.7.1), and `ui-plumbing-1`'s fix adds
`ENUM_SSR_STR` ids for the 18 `what` strings. So the four hand-written hint lines that concentrate
the problem — `keys.1` through `keys.4`, `fa.txt:215-218`, each of which interleaves five Latin key
letters with Persian words in one label — are **deleted by M.4.4**, not translated better. The
mixed-run problem for the keyboard is solved by the information architecture rather than by a
composer, which is the cheapest possible answer.

The residual Shape C strings that survive are all of the form *Persian phrase + trailing Latin key
letter*: `lines.on = خطوط روشن  L`, `flip = برعکس  X`, `keycard.close = H دوباره این را می‌بندد`.
Two of those three are **button** text (centred, single object, Q.4.4) and the third is a card
footer. [RECOMMENDATION] For button labels carrying a key letter, put the letter at the **logical
end** in every language and let the composer treat it as a one-run LTR tail; for prose, move it to
its own column. Do not leave a key letter in the middle of a Persian sentence, which is what
`keys.3` does today five times in one label.

**Shape D — numbers in a column.** Never composed and never mirrored. Q.7.4.

#### Q.6.3 `SSRCompose` — specified, with its one unknown isolated

```
//--- SSR_Layout.mqh
struct SSRRun
  {
   string            text;
   bool              rtl;      // true: an Arabic-script run. false: Latin/digits/symbols
  };

//--- Emits ONE string whose characters are in VISUAL order for a renderer
//--- with no bidi algorithm. Runs are given in LOGICAL (reading) order.
string SSRCompose(const SSRRun &runs[], const bool frame_rtl);
```

The emit rule, in full:

* **`frame_rtl == false`** — return the runs concatenated in logical order. Identity. (An LTR frame
  containing an Arabic run is a case this product does not have and must not be given one.)
* **`frame_rtl == true`** — emit the runs in **reverse** order, so the logically-first run ends up
  rightmost. Each run's own characters are then handled by `SSR_RTL_SHAPES`:

```
#define SSR_RTL_SHAPES        // the renderer shapes and reverses an Arabic run itself
```

| `SSR_RTL_SHAPES` | An Arabic run is emitted | A Latin run is emitted |
|---|---|---|
| **defined** (default) | unchanged — the renderer reverses it | unchanged |
| **commented out** | **character-reversed** by `SSRCompose` | unchanged |

**That is the whole unknown, and it is one `#define`.** [POTENTIAL_RISK] Whether MetaTrader shapes
and orders Arabic glyphs inside a single `OBJPROP_TEXT` has no API that answers it —
`SSR_QA_Smoke.mq5:4943-4947` says so, `docs/ux-ui/localization.md` says so, and this audit does not
claim it either. What can be said from the repository:

* [CONFIRMED FROM CODE] The glyphs exist and the round trip is lossless — or will be, on the next
  run: stage 41 measures `TextGetSize` on a Persian string (`:4951-4952`) and asserts
  `ObjectGetString == ObjectSetString` (`:4971-4974`). `localization.md` explicitly **withdraws** the
  v116 pass of both, because it was measuring mojibake, and marks both *"Re-measure required."*
* [INFERENCE] The translator wrote 44 ZWNJs, which are meaningful only to a shaping engine. That is
  evidence of a belief, not of a behaviour.

**The probe that settles it in ten seconds**, added to stage 41 beside the two checks already there:
draw four labels on one chart and look at them.

| # | Text | If it reads correctly |
|---|---|---|
| P1 | `الف` alone | the face has the glyphs and joins them |
| P2 | `الف ب` | the renderer orders a multi-word Arabic run right-to-left |
| P3 | `الف 123 ب` | there is a bidi algorithm after all — **then `SSRCompose` is not needed for Shape B at all** and the isolate variant below is preferred |
| P4 | `SSRCompose` output for the same three runs | the manual composition is correct for this terminal |

Three of the four are pass/fail by eye and none needs a developer. Ship the stage with all four
drawn and held on screen (stage 41 already opens and closes its own chart, `:4960-4977`), and write
the answer into `docs/ux-ui/localization.md` — where the question has been open since v117.

#### Q.6.4 Why the Unicode isolates are the *second* implementation and not the first

`U+2067 RLI` / `U+2066 LRI` / `U+2069 PDI` (and the older `U+202B`/`U+202C`) are the correct way to
mark a mixed run — **for a renderer that implements the bidi algorithm.** Ground truth says there is
none, and a request to an absent engine is at best ignored.

[POTENTIAL_RISK] At worst it is not ignored: format characters are default-ignorable, but a font or
renderer that lacks them can draw `.notdef` boxes, and this product has no way to see that happen.
Against that, they are strictly better than manual composition **if** probe P3 comes back correct.

[RECOMMENDATION] So ship both, behind the same switch, and let the probe choose:

```
#define SSR_RTL_ISOLATES     // wrap each run in RLI/LRI ... PDI, emit logical order
//#define SSR_RTL_SHAPES     // manual visual composition (Q.6.3)
```

`SSRCompose` is the only function that reads either symbol. Two implementations, one call site
signature, one probe, and one commented line moves between them — the discipline
`SSR_LAYOUT_RAIL` established for exactly this situation. **Do not pick one on reasoning alone.**

#### Q.6.5 Worked example — a price inside a Persian sentence, and a price beside one

**(a) The Shape A case: the stop row, which is the densest row in the product.**

[CONFIRMED FROM CODE] Today (`SSR_Panel.mqh:1407-1410`, `fa.txt:194`):

```
   Text(13, "slrow", x + 8, gy + 24,
        StringFormat(T(SSR_S_STOP_ROW), Price(m_state.sl_price),
                     Money(-m_state.risk_money, true)), SSR_C_TEXT);
   //  fa: stop.row = حد ضرر   %s      %s
```

One object, three runs, two of them numeric, spaced by literal spaces in a proportional font.
Rebuilt as three objects in one row of the sheet frame:

| object | text | x | align | direction |
|---|---|---|---|---|
| `slrow_l` | `T(SSR_S_STOP_LBL)` → `حد ضرر` | `SSRLeadEdge(sheet, 8)` | `SSR_AL_LEAD` | RTL run, own object |
| `slrow_p` | `Price(sl_price)` | `SSRLeadEdge(sheet, 8 + 96)` | `SSR_AL_TRAIL` | `SSR_AL_FORCE_LTR` glyph order |
| `slrow_m` | `Money(-risk_money, true)` | `SSRTrailEdge(sheet, 8)` | `SSR_AL_TRAIL` | `SSR_AL_FORCE_LTR` |

In English the same three objects resolve to `x+8` / `x+104` right-aligned / `x+237` right-aligned,
and the money column is decimal-aligned for the first time (Q.7.4). **The row is better in both
languages and the panel still computes nothing** — `Price()` and `Money()` are unchanged
(`:221-224`, `:266-271`), and `PreviewLot` remains *the same call the order uses, never a second
formula*.

**(b) The Shape B case: a number that cannot leave the sentence.**

`too.narrow = چارت %d پیکسل است، پنل %d می‌خواهد - کنترل‌ها بیرون لبه‌اند` — "the chart is %d pixels,
the panel wants %d — the controls are past the edge." The numbers are inside clauses; splitting the
string would produce five objects for one sentence and a layout that breaks on any translation.

```
   SSRRun r[5];
   r[0].text = "چارت ";                r[0].rtl = true;
   r[1].text = IntegerToString(cw);    r[1].rtl = false;
   r[2].text = " پیکسل است، پنل ";      r[2].rtl = true;
   r[3].text = IntegerToString(SSR_PANEL_W); r[3].rtl = false;
   r[4].text = " می‌خواهد - کنترل‌ها بیرون لبه‌اند"; r[4].rtl = true;
   Text(50, "stbal", SSRLeadEdge(pf, SSR_PAD), y + 4,
        SSRCompose(r, SSRIsRtl()), SSR_C_HOLD, SSR_FS_SMALL, SSR_FONT, SSR_AL_LEAD);
```

[RECOMMENDATION] Six strings do not justify six hand-built run arrays at six draw sites. Give the
catalogue a **run-split convention** instead: the translator writes the value with the existing `%d`
markers and `SSRComposeFormat(T(id), args)` splits on the markers, tags each literal segment by its
first strong character and each argument as LTR, and calls `SSRCompose`. The translator's file does
not change at all; the draw site gains one function name. That is one helper against six sites and
it is the only thing in this section that touches `StringFormat`.

---

### Q.7 Digits, prices, dates and tabular alignment

#### Q.7.1 The decision already made, and it is right

[CONFIRMED FROM CODE] `fa.txt:15-17` and `docs/ux-ui/localization.md`'s Formatting table both say:
digits stay Latin, because Tahoma draws all ten on the same width and that is what keeps a price
column lined up. The FontProbe measures exactly that property — `probes[2] = "0123456789"` and the
`mono_wide`/`mono_narrow` fingerprint (`SSR_QA_FontProbe.mq5:73-80`). **Keep it as the default.**

#### Q.7.2 But it must become a policy, because a comment is not enforceable

Two lines already break it (Q.1.3). Audit **A23** (Q.11) makes it mechanical: *no value in a
`lang/*.txt` may contain a character in U+0660-U+0669 or U+06F0-U+06F9 unless its key is on an
explicit allow list.* The allow list starts empty.

#### Q.7.3 `SSRNum()` — the policy is per *role*, not per language

A Persian trainee reading a **sentence** — "day 3 of 30" — expects `۳`. The same trainee reading a
**price column** expects Latin, for the reason the file already gives. So the policy cannot be a
language flag:

```
enum ENUM_SSR_DIGITS { SSR_DIG_LATIN, SSR_DIG_NATIVE };
ENUM_SSR_DIGITS g_ssr_digits = SSR_DIG_LATIN;      // the default, and the shipped value

string SSRNum(const string s);   // maps 0-9 to U+06F0-U+06F9 when NATIVE, else identity
```

and the rule that decides who calls it:

| Role | Function | Digits |
|---|---|---|
| price | `Price()` (`SSR_Panel.mqh:266`) | **always Latin.** Never call `SSRNum` |
| money | `Money()` (`:221`) | **always Latin.** Never call `SSRNum` |
| any value in a right-anchored column | — | **always Latin** |
| a number composed into prose (Shape B) | `SSRComposeFormat` | `SSRNum`, so a future `ar.txt` can opt in |
| a count on a button (`Pos 3`) | `TabName()` (`:1108`) | **Latin** — it shares a 44 px cell with a name and must not change width |

[RECOMMENDATION] Ship with `g_ssr_digits = SSR_DIG_LATIN` and **do not expose it as an input yet**.
It exists so that the answer is one assignment rather than a search through 200 draw sites, and so
that the two `fa.txt` violations have somewhere to be fixed to. A product that has never rendered a
Persian glyph on a terminal should not also be choosing between two digit systems on the first run.

#### Q.7.4 Tabular alignment — the cheapest quality win in the section, and it is language-independent

[CONFIRMED FROM CODE] Every money and price label in the product is drawn with
`ANCHOR_LEFT_UPPER` at a fixed `x`:

```
SSR_Panel.mqh:1581-1586   Text(92 + r, "pl" + t, x + w - 116, ry + 3, Money(m_state.pos_pl[r], true), ...)
SSR_Panel.mqh:2015        Text(50, "stbal", x + SSR_PAD, y + 4, StringFormat(T(SSR_S_BAL), Money(m_state.balance)), ...)
SSR_Panel.mqh:2018        Text(51, "stflt", x + 116, y + 4, StringFormat(T(SSR_S_FLOAT), Money(..., true)), ...)
```

so `+38.20` and `+1038.20` **start** at the same pixel and **end** at different ones. The column is
ragged today, in English, on the row a trader reads for money. [CONFIRMED FROM CODE] The product
already half-knows this: `Money`'s sign argument exists *"so the column does not change width the
moment a loss appears"* (`:221-223`) — the right instinct applied to the wrong end of the number.

**The fix is `SSR_AL_TRAIL`,** i.e. `ANCHOR_RIGHT_UPPER` at the column's right edge. Then:

* the units digit lands on the same pixel in every row, in every language, at every display scaling;
* the decimal point lands on the same pixel too, because `Price()` uses **one** `price_digits` for
  the whole session (`:266-271`) and `Money()` is always `%.2f` (`:221-226`) — so every value in a
  given column has the same number of digits after the point, which is the condition decimal
  alignment needs;
* Tahoma's equal-width digits (Q.7.1) do the rest;
* and it is **one argument per call site**, with no measurement and no arithmetic.

[INFERENCE] This is the single change in Q that would be worth making even if Persian were
cancelled. It fixes `ui-panel-7`'s neighbourhood properly rather than by moving an `x`: under N.4.1's
re-derived columns the money column becomes a right edge at `SSRTrailEdge(sheet, 8 + 60)` and the
note column a left edge before it, and the two can be *proved* not to collide because
`TextW(note) <= gap` is now a question with an answer.

#### Q.7.5 Dates, times and the clock

[CONFIRMED FROM CODE] The panel does not format the clock and must not start
(`SSR_Panel.mqh:947-951`):

```
      //--- the panel never formats the clock itself: Blind Mode has to
      //--- reach the text, and a second place that knows about blind
      //--- mode is the one that gets forgotten
      Text(2, "clock", x + SSR_PAD, y, m_state.clock_text, SSR_C_TEXT, SSR_FS_CLOCK);
```

Three rules follow:

1. **Always server time**, never the user's locale — `docs/ux-ui/localization.md` states it and the
   reason is correct: *"A replay clock in local time is a lie about the market."*
2. `09:41:07` and `2024-03-11` are **single LTR runs in their own objects**. They need
   `SSR_AL_FORCE_LTR` and nothing else. A time drawn with Latin digits and colons is direction-neutral
   the moment it is not concatenated to a Persian word — and it never is, because the clock is its
   own object and Blind mode masks it in place.
3. **A Jalali (Persian) calendar is [FUTURE FEATURE], and it belongs to the owner that formats the
   clock, never to the panel.** That owner is the port/engine that fills `m_state.clock_text` and
   applies the blind mask. A conversion in the panel would be the second place that knows about
   blind mode, which is exactly what the comment above forbids. Write the constraint down now, at
   the field, so whoever adds it adds it in the right file.

`day.of.elapsed` (`fa.txt:93`) is the only date-shaped string on a sheet and it is Shape B.

#### Q.7.6 Symbols, instruments and product names

Never translated, never mirrored, always LTR, always their own object: `EURUSD`, `XAUUSD`, custom
symbol names, `SS Replay`, the build tag, seeds, and file names. [CONFIRMED FROM CODE] The caption
deliberately does **not** draw the symbol (`SSR_Panel.mqh:869-880`: MetaTrader already writes it in
the chart's corner, and *"a panel announcing the symbol the chart was told to conceal would defeat
the feature it sits beside"*), which removes the worst instance of this problem for free and should
stay removed.

`SS Replay` is drawn at `:836` as a literal and is correctly excluded from the catalogue — a product
name is not a string to translate. In RTL it sits at the **leading** (right) edge with
`SSR_AL_FORCE_LTR`: mirrored *position*, unmirrored *glyphs*. That distinction is the whole of Q.2.2
in one label, and it is a good one to put in the comment at that line.

---

### Q.8 The element ledger

Every drawn element, one row. "Mirror" is the x transform; "align" is the anchor; "runs" says whether
the object's text may contain more than one direction.

| Element | id(s) | Mirror | Align | Runs | Change |
|---|---|---|---|---|---|
| panel frame | `bg` | pos only | — | — | `SSRPanelFrame` |
| product name | `title` | yes | LEAD + FORCE_LTR | 1 LTR | anchor arg |
| build tag | `build` | yes | LEAD + FORCE_LTR | 1 LTR | anchor arg; follows `title` in reading order |
| run state | `capinfo` | yes | LEAD | 1 | anchor arg |
| mode chips | `chfid`, `chblind`, `chprop` (+`_bg`) | yes | LEAD | 1 | `Chip` width measured (Q.4.5); `cx` accumulates along the reading axis; fixes `ui-panel-13` in both directions |
| collapse / close | `collapse`, `close` | yes | centred (button) | 1 | **trailing edge** — frame furniture belongs where the frame ends |
| clock | `clock` | yes | LEAD + FORCE_LTR | 1 LTR | anchor arg |
| progress % + reason | `prog` | yes | **TRAIL** | 1 | replaces the hand-computed `x + W - SSR_PAD - 110` (`:957`); `ClipPx` |
| progress bar | `bar_bg`, `bar_fill` | yes **incl. fill** | — | — | `Progress` mirrors (Q.4.8) |
| transport block | `restart`,`back10`,`back`,`toggle`,`step`,`step10` | **block only** | centred | 1 | **internal order never mirrors** (Q.5.3) |
| reset | `reset` | with the block | centred | 1 | 10 px separator preserved |
| speed label | `spdlbl` | yes | LEAD | 1 | anchor arg |
| speed steppers | `spdn`, `spup` | yes | centred | 1 | positions swap with the reading axis |
| speed value well | `spdbox` + `spdval` | yes | centred | 1 LTR | `SSR_AL_FORCE_LTR` on the value |
| speed groove | `spdseg_tk`, `spdseg0..n`, `spdseg_th` | yes **incl. fill** | — | — | `Slider` mirrors; **dispatch unchanged** (Q.4.8) |
| speed meaning | `spdmean` | yes | TRAIL | 1 | `ClipPx`; fixes `ui-panel-8` |
| action cells | `lines`, `sessions`, `fidelity` | yes | centred | 1 | `SSRColX(f, i, 3)` |
| hairline | `tabline` | yes | — | — | spans `SSRInner` |
| rail cells | `tab0..tab5` | yes | centred | 1 | right edge (Q.5.2); condition marks are Shape A inside `TabName()` |
| group frames + legends | `g1_*`, `g2_*`, `g3_*` | yes | LEAD | 1 | legend and punch-out move to the leading edge; `lw` measured |
| sheet row label | `risklbl`, `taglbl`, `trlbl`, `ses*`, `pp_*`, `st*` | yes | LEAD | 1 | anchor arg |
| sheet row value | `riskval`, `riskmon`, `rrrow`, `sizerow`, money/price | yes | **TRAIL** | 1 LTR | Shape A split; decimal alignment (Q.7.4) |
| refusal / hint rows | `setuprow`, `order_why` (own id, M.4.1), `hintrow`, `poshint` | yes | LEAD | 1 or composed | sentence at the leading edge, `ClipPx` |
| typed field | `tagbox` | yes | `ALIGN_RIGHT` | user's | `Edit()` one line; gated on `ui-port-session-15` (Q.4.3) |
| deal pair | `buy`, `sell` | yes | centred | Shape A | `buy.btn = خرید %s` keeps its marker at the logical end |
| order button | `openln` | yes | centred | **Shape B** | `place.order` / `open.order` through `SSRComposeFormat` |
| trio | `flipbtn`, `enbtn`, `clrbtn` | yes | centred | 1 | `SSRColX(f, i, 3)` |
| position row text | `pr<r>` | yes | LEAD | 1 LTR (`BUY 1.00 @ 53513`) | `SSR_AL_FORCE_LTR` |
| position row note | `pn<r>` | yes | LEAD | 1 | `!` prefix (M.4.2); the RLM and the two spaces leave the string (Q.1.4) |
| position row money | `pl<r>` | yes | **TRAIL** | 1 LTR | Q.7.4 |
| row buttons | `ph<r>`, `pb<r>`, `px<r>` | yes | centred | 1 | O's `½`/`BE`/`✕` relabel is unaffected |
| overflow counter | `posmore` | yes | TRAIL | Shape A | own baseline (M.4.2) |
| meters | `m0..m3` + `_bg/_fill/_lim` | yes **incl. fill and limit mark** | — | — | Q.4.8 |
| status readouts | `stbal`, `stflt`, `stopen`, `stspread`, `chartsn` | yes | **TRAIL** | Shape A | four Shape-A splits; decimal alignment |
| status ladder warnings | slot 50 (or `stmsg`) | yes | LEAD | sentence / Shape B | Q.5.4 |
| toast | `fill`, `fill_bg`, `fill_ac` | yes **incl. accent** | LEAD | 3 objects | Q.4.7; also closes the English gap |
| pager | `<`, `>`, `"%d-%d of %d"` | yes | centred / centred | Shape A | arrows are *list* order, so they **do** mirror — unlike the transport, a list has no time axis |
| `ListRO` rows | per page | yes | LEAD + TRAIL | 2 columns | Q.4.6 |
| palette (`SSRX_`) | `bg`, `cap`, query `Edit`, rows, `foot` | yes | LEAD / `ALIGN_RIGHT` | rows are buttons | `SSR_Palette.mqh:162-204` |
| session picker (`SSRSD_`) | 420 px modal | yes | LEAD | Shape A | `SSR_SessionDialog.mqh` |
| range dialog (`SSRD_`) | 248 px modal | yes | LEAD | Shape B (`rd.bars`, `rd.cost`) | note `OBJPROP_ALIGN` at `SSR_RangeDialog.mqh:191` |
| review card (`SSRR2_`) | 520 px | yes | LEAD + TRAIL | observations are English (`ui-dialogs-4`) | gate |
| reveal card (`SSRV_`) | 360 px | yes | LEAD | 1 | cleanest surface; nothing but anchors |
| chart objects (`SSR_L_*`) | `"STOP - drag me"`, `BUY`/`SELL`/`SL`/`TP` | **no** | `ANCHOR_TOP` (`SSR_TradeLines.mqh:542, 558`) | 1 | **the chart is not mirrorable.** `chart-12`: translate them; place them where price puts them |

**The last row is the honest boundary of this section.** MetaTrader's price axis cannot be reversed
and the panel has no authority over it. A Persian user gets a mirrored panel over an unmirrored
chart, which is correct — the chart is a market, not a document.

---

### Q.9 What must be closed before the mirror is switched on

Ordered, each with its finding id and the reason it is a gate rather than a wish.

| # | Gate | Finding | Why it blocks |
|---|---|---|---|
| 1 | The five untranslated surfaces (Q.1.2) | `chart-12`, `ui-plumbing-1`, `ui-panel-14`, the fill toast, `ui-dialogs-4` | each is an English island that becomes an *unplanned* LTR island in a mirrored frame |
| 2 | A19's language check never runs | `spikes-audits-26` (CONFIRMED, LOW) — `tools/ssr_audit.py:1429` builds `ROOT/MQL5/MQL5/Files/...`, which does not exist | the one instrument that reads `fa.txt` has been silent since it was written. Fix the path **before** adding 30 strings to it |
| 3 | A19's `"/Ui/"` filter and its argument-position-only rule | `chart-12`'s verified evidence (`:1458`, `:1449`) | it cannot see literals drawn from a member or written via `ObjectSetString` — the exact shape of items 1 and the toast |
| 4 | Non-ASCII source with no BOM | `ui-plumbing-13` (POTENTIAL_RISK, LOW) — `SSR_Strings.mqh:472,474,544`; `SSR_ReviewCard.mqh:155` | the fix costs nothing (ASCII separators) and the project keeps all-ASCII sources, which is one fewer encoding question during an encoding-sensitive phase |
| 5 | Session file written in ANSI | `ui-port-session-15` (POTENTIAL_RISK, LOW) | a Persian setup tag does not survive save/resume, so the one RTL text-entry control has a silent data-loss path (Q.4.3) |
| 6 | M's R1 + R4 (transition latch, per-destination teardown) | `ui-panel-1`, `-2`, `-3`, `-4` | a panel that rebuilds itself 10×/s will do so with a new anchor property per label. The mirror is affordable **because** R1 lands first, not despite it |
| 7 | `host-expert-7` — keys not withheld while a modal is open | CONFIRMED, MEDIUM | already M's gate for every new control; a mirrored dialog does not change it and must not ship before it |

[RECOMMENDATION] Gates 2 and 3 are two days of Python and they are the difference between adding 30
catalogue entries with an instrument and adding them on trust.

---

### Q.10 Audits and the terminal probe

Three new static audits, numbered after M's A22.

**A23 — digit policy.** No value in `MQL5/Files/SSReplay/lang/*.txt` may contain U+0660-U+0669 or
U+06F0-U+06F9 unless its key appears in an explicit allow list in the audit source. *Currently fails
twice:* `fa.txt:178`, `fa.txt:215` (Q.1.3). ~20 lines of Python.

**A24 — one object, one direction.** No catalogue value may contain **both** an Arabic-script
character **and** a `printf` marker, unless its key is on the Shape-B list. The Shape-B list is the
six names in Q.6.2 plus the two dialog strings, and it is a *declaration*: adding a name to it is the
statement "this one goes through `SSRComposeFormat`." *Currently would report 39; after the Shape A
split, 9.* ~30 lines.

**A25 — mirror coverage, i.e. the constraint `localization.md` placed and nobody kept.** Under
`MQL5/Include/SSReplay/Ui/`, no argument to a drawing call (`Label`, `ButtonC`, `Button`, `Rect`,
`Chip`, `Group`, `Edit`, `Meter`, `Progress`, `Slider`, `Toast`, `Text`) in the `x` position may be
an expression containing a bare `+` on a raw integer literal — it must be `SSRLead`, `SSRTrail`,
`SSRLeadEdge`, `SSRTrailEdge`, `SSRCentre`, `SSRColX` or a variable derived from one, or carry an
explicit `// unmirrored:` justification (the transport block, the chart layer). This is A22's sibling
and the same shape of check: ~200 mechanical edits, then a gate that cannot be forgotten by the next
phase the way Phases 3-9 forgot it. [CONFIRMED FROM CODE] `SSR_Layout.mqh:14-19` is the requirement,
written in the file, five phases ago.

Plus **fix A19** (gates 2 and 3 above) and widen it past `/Ui/`.

**Smoke stage 41** gains the four probes of Q.6.3 (P1-P4), the label-overlap pass run **twice** —
once LTR, once with `SSRIsRtl()` forced — and the new `FrameOverflowLeft()` assertion from Q.4.9.
[CONFIRMED FROM CODE] The machinery already exists: `LabelBox` (`SSR_QA_Smoke.mq5:5308-5334`) measures
a real label with `TextGetSize`, and the overlap walker beside it already *"returns the number of
overlapping PAIRS, and names the worst one"* with a one-pixel tolerance. **The single most valuable
thing in this section is running that existing walker over a Persian panel**, because it is the only
mechanism in the product that can see an RTL collision, and it was built before anyone needed it.

What the stage must continue to refuse to claim: that RTL "works". It can report glyph coverage, the
round trip, the 63-character budget, the overlap count in both directions, and the four probe images.
Shaping is a judgement a person makes by looking.

---

### Q.11 Cost ledger and build order

| # | Change | ~lines | Risk | Fixes / enables |
|---|---|---|---|---|
| 1 | `g_ssr_rtl`, `SSRIsRtl()`, `SSRLangIsRtl()`, `InpForceLtr` | 25 | low | the whole section |
| 2 | `SSR_Layout.mqh`: seven additions (Q.3.2) | 120 | low | `ui-plumbing-5` |
| 3 | `TextW()` + 256-slot memo in `CSSRWidgets` | 70 | medium — a graphics call in the paint path | Q.4.5, Q.4.9, `ClipPx`, and it retires invariant I10 |
| 4 | `Label`/`Text` align arg + anchor in the fingerprint + `m_cache_a` | 40 | **medium — a cache-key change** | Q.4.1, Q.4.2; must land as one edit |
| 5 | `Edit` `ALIGN_RIGHT`; `Chip`/`Group` measured widths; `Group` legend to the leading edge | 30 | low | `ui-panel-13` in both languages |
| 6 | `Progress`/`Meter`/`Slider`/`Toast` mirrored fills and accents | 40 | low | Q.4.8 |
| 7 | `Extent` gains labels; `m_min_l`/`FrameOverflowLeft` | 30 | low | the only instrument that can see an RTL overflow |
| 8 | `CSSRPanel::Render` + all seven bands take frames | ~200 mechanical | **high — it is every draw site** | Q.5.1-Q.5.3 |
| 9 | Shape A: split 30 catalogue entries, rewrite ~20 rows as label+value | 90 + 60 strings | low | Q.6.2, Q.5.6, and **decimal alignment in English** |
| 10 | `SSRCompose` + `SSRComposeFormat` + the two variants behind one switch | 90 | low (isolated) | the six live Shape-B strings |
| 11 | `ClipPx` + R5 budgets restated in pixels | 40 | low | Q.5.5 |
| 12 | `SSRNum` + digit policy; fix `fa.txt:178`, `:215` | 25 | low | Q.7.2, Q.7.3 |
| 13 | Default corner / `m_x` to the trailing edge in RTL | 10 | low | Q.5.2 |
| 14 | A23, A24, A25; fix A19's path and filter; stage 41 probes | 140 (Python + MQL5) | low | Q.10 |
| | **total** | **≈ +950, of which ~200 are mechanical `x` rewrites** | | |

**Build order.**

1. **The gates** (Q.9, items 1-5). Nothing below is worth doing over five English surfaces and a
   silent audit.
2. **M's change #1+#2+#3** (transition latch, destination register, `order_why`'s own id). The mirror
   adds one property write per cold label; on a panel that repaints everything ten times a second
   that is not a cost anybody should agree to pay.
3. **#1, #2, #3, #4, #5, #6, #7** — the plumbing. Every one of these is invisible in English and
   independently testable. `SSR_LAYOUT_RAIL`-style: the build still ships LTR at the end of this step.
4. **#8** — the mirror, in one change, all bands. A half-converted panel is the failure
   `localization.md` already documented once.
5. **#9, #11, #12** — the catalogue split, the pixel budgets, the digits. These improve the English
   panel too and can be verified in English before Persian is loaded.
6. **#10** — the composer, then the terminal probe, then the switch.
7. **#14** — the audits last, written against the finished call sites, exactly as M orders A22.
8. **#13** and the release note.

**What ships at each step is a working product.** Steps 3 and 5 improve the English panel and change
nothing a user sees about direction. Step 4 is the only irreversible-feeling one, and it is reversible:
`InpForceLtr`.

---

### Q.12 What this refuses, and what it does not fix

**Refuses:**

* **It will not mirror the chart.** The price axis runs old-to-new left-to-right and MetaTrader
  offers no reversal. A Persian panel over an unmirrored chart is the correct answer, not a
  compromise.
* **It will not mirror the transport.** Time is not a reading direction (Q.5.3).
* **It will not build a bidi algorithm.** `SSRCompose` composes runs the caller has already
  classified; it does not analyse text, does not resolve embedding levels, and does not implement
  UAX #9. Six strings do not justify one, and a partial one is worse than none.
* **It will not build a text field.** The caret, the selection and the typing direction belong to
  MetaTrader (Q.4.3).
* **It will not decide the shaping question by reasoning.** Two implementations, one switch, one
  probe (Q.6.3, Q.6.4).
* **It will not add a colour, a font size, a primitive or a control.** Persian is a geometry
  problem; M.9's palette and four type sizes are unchanged.
* **It will not translate a log line.** `SSR_Strings.mqh:31-34` is right: *"A log in a language the
  person reading the bug report cannot read is not a localised log, it is a lost diagnostic."*

**Does not fix, and says so:**

* **A Persian calendar.** [FUTURE FEATURE], and it belongs to whoever formats `clock_text`, never to
  the panel (Q.7.5).
* **Persian in exported files.** `trading-analytics-13` (POTENTIAL_RISK, LOW) — exports are written
  `FILE_ANSI` while the statement declares UTF-8; `strategy-integration-report-8` (CONFIRMED, MEDIUM)
  is the same defect in the class report. A trainee whose panel is Persian and whose statement is
  mojibake has not been localised. Out of scope here, on the list.
* **`ui-port-session-15`** — the session file's encoding. Named as a gate (Q.9 #5) because it makes
  the tag box unsafe, not fixed here.
* **`ui-panel-11`** (POTENTIAL_RISK) — the tag box hidden and re-shown 10×/s while it may hold the
  keyboard. M.10 carries it; R1 is its strongest mitigation; RTL neither helps nor harms it.
* **Whether Persian renders at all.** [POTENTIAL_RISK, and it is the largest one in this document]
  `localization.md` **withdrew** the v116 glyph and round-trip results because they were measuring
  mojibake, and marks both *"Re-measure required."* No one on this project has seen a Persian glyph
  drawn by this product on a terminal. Every geometry decision above is correct whether or not the
  glyphs shape; none of them can be *seen* to be correct until somebody looks.
* **The px/char estimates in L, M and N.** They stand as written. Q gives the mechanism
  (`TextW`) that would replace them with measurements; re-deriving three sections against it is a
  separate pass and should happen after step 3 of the build order, not before.

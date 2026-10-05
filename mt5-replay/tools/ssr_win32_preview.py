#!/usr/bin/env python3
"""Draw the startup windows in the STRUCTURE the reference video uses.

WHY THIS EXISTS
---------------
The reference product's dialogs are real Win32 windows, and what makes
them read as finished is not their colour - it is their STRUCTURE:

  - a title bar carrying an icon, a name, and minimise/maximise/close
  - labelled group boxes whose legend sits ON the frame line
  - ONE right-aligned label column, every field starting at one x
  - fields that look like fields: a white well with a 1 px border, a
    drop-down chevron on a combo, a stacked spinner on a number
  - a real grid: filled header, column rules, blue link cells, and a
    grey empty area that says "this list has room"
  - a footer of equal-width buttons

All of that is reachable from MQL5 chart objects. None of it needs a
DLL. This file draws the options so the structure can be chosen before
any of it is built.

These are PREVIEWS, not the product. Colours come from the real light
palette in SSR_Theme.mqh; the face is a stand-in, as it is in
ssr_layout_preview.py, because Segoe UI is not on the build machine.

    python3 tools/ssr_win32_preview.py        # writes docs/ux-ui/v128/
"""
import os
import re

from PIL import Image, ImageDraw, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
THEME = os.path.join(ROOT, "MQL5", "Include", "SSReplay", "Ui", "SSR_Theme.mqh")
OUT = os.path.join(ROOT, "docs", "ux-ui", "v128")
os.makedirs(OUT, exist_ok=True)


def palette(name):
    src = open(THEME, encoding="utf-8").read()
    m = re.search(r"#ifdef SSR_THEME_%s\n(.*?)\n#endif" % name, src, re.S)
    out = {}
    for mm in re.finditer(r"#define SSR_C_([A-Z0-9_]+)\s+C'(\d+),(\d+),(\d+)'",
                          m.group(1)):
        out[mm.group(1)] = (int(mm.group(2)), int(mm.group(3)), int(mm.group(4)))
    return out


def sizes():
    out = {}
    for line in open(THEME, encoding="utf-8"):
        m = re.match(r"\s*#define\s+(SSR_FS_[A-Z]+)\s+(\d+)", line)
        if m:
            out[m.group(1)] = int(m.group(2))
    return out


C = palette("LIGHT")
PT = sizes()
S = 2
FR = "/usr/share/fonts/truetype/liberation/LiberationSans-Regular.ttf"
FB = "/usr/share/fonts/truetype/liberation/LiberationSans-Bold.ttf"
#--- Liberation Sans has no chevrons, no check mark and no window
#--- glyphs, so it draws tofu for every one of them. DejaVu has them
#--- all. This is a limit of the PREVIEW machine, not of the product:
#--- the chevrons and the check are WGL4, which Tahoma and Segoe UI
#--- both carry on every Windows - the same reasoning that chose the
#--- transport glyphs in SSR_Theme.mqh after Wingdings failed a test.
FG = "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf"

WHITE = (255, 255, 255)
FIELD_EDGE = C["WELL_EDGE"]
LINK = C["PRIMARY"]
EMPTY = (168, 168, 168)          # the list control's own empty area


def f(pt, bold=False, glyph=False):
    return ImageFont.truetype(FG if glyph else (FB if bold else FR),
                              int(round(pt * 4 / 3 * S)))


GLYPHS = set("\u25be\u25b4\u2713\u2715\u25a1\u2013\u25c0\u25b6")


def _isglyph(t):
    return len(t) <= 2 and any(ch in GLYPHS for ch in t)


def rect(d, x, y, w, h, bg, edge=None):
    d.rectangle([x * S, y * S, (x + w) * S - 1, (y + h) * S - 1],
                fill=bg, outline=edge or bg, width=1)


def txt(d, x, y, t, col, pt=None, bold=False):
    d.text((x * S, y * S), t, fill=col,
           font=f(pt or PT["SSR_FS_BODY"], bold, _isglyph(t)))


def txt_r(d, right, y, t, col, pt=None, bold=False):
    ft = f(pt or PT["SSR_FS_BODY"], bold)
    w = d.textlength(t, font=ft)
    d.text((right * S - w, y * S), t, fill=col, font=ft)


def txt_c(d, x, y, w, t, col, pt=None, bold=False):
    ft = f(pt or PT["SSR_FS_BODY"], bold, _isglyph(t))
    tw = d.textlength(t, font=ft)
    d.text((x * S + (w * S - tw) / 2, y * S), t, fill=col, font=ft)


#--- Win32-ish primitives -------------------------------------------
def titlebar(d, x, y, w, title, accent=False):
    """Icon, name, and the three window buttons. 24 px, like the video."""
    h = 24
    rect(d, x, y, w, h, C["ACCENT"] if accent else WHITE, C["PANEL_EDGE"])
    rect(d, x + 7, y + 6, 12, 12, C["ACCENT"] if not accent else WHITE)
    txt(d, x + 9, y + 7, "S", WHITE if not accent else C["ACCENT"],
        PT["SSR_FS_SMALL"], True)
    txt(d, x + 25, y + 6, title, WHITE if accent else C["TEXT"],
        PT["SSR_FS_BODY"], True)
    fg = WHITE if accent else C["TEXT_DIM"]
    for i, g in enumerate(("–", "□", "✕")):
        bx = x + w - 20 * (3 - i) - 4
        txt_c(d, bx, y + 6, 20, g, fg, PT["SSR_FS_SMALL"])
    return y + h


def groupbox(d, x, y, w, h, legend):
    """Legend ON the frame line, with the line broken behind it."""
    d.rectangle([x * S, (y + 5) * S, (x + w) * S - 1, (y + h) * S - 1],
                outline=C["GROUP_EDGE"], width=1)
    ft = f(PT["SSR_FS_SMALL"])
    lw = d.textlength(legend, font=ft) / S
    rect(d, x + 8, y + 1, int(lw) + 8, 10, C["PANEL"])
    txt(d, x + 12, y, legend, C["TEXT_DIM"], PT["SSR_FS_SMALL"])


def field(d, x, y, w, t, enabled=True, h=20):
    rect(d, x, y, w, h, WHITE if enabled else C["PANEL"], FIELD_EDGE)
    txt(d, x + 5, y + 4, t, C["TEXT"] if enabled else C["TEXT_FAINT"])


def combo(d, x, y, w, t, enabled=True, h=20):
    field(d, x, y, w, t, enabled, h)
    rect(d, x + w - 17, y + 1, 16, h - 2,
         C["BTN"] if enabled else C["PANEL"], C["BTN"] if enabled else C["PANEL"])
    txt_c(d, x + w - 17, y + 5, 16, "▾",
          C["TEXT"] if enabled else C["TEXT_FAINT"], PT["SSR_FS_SMALL"])


def spin(d, x, y, w, t, enabled=True, h=20):
    field(d, x, y, w, t, enabled, h)
    rect(d, x + w - 14, y + 1, 13, (h - 2) // 2, C["BTN"], FIELD_EDGE)
    rect(d, x + w - 14, y + 1 + (h - 2) // 2, 13, (h - 2) // 2, C["BTN"], FIELD_EDGE)
    txt_c(d, x + w - 14, y + 1, 13, "▴", C["TEXT"], PT["SSR_FS_SMALL"])
    txt_c(d, x + w - 14, y + 1 + (h - 2) // 2, 13, "▾", C["TEXT"],
          PT["SSR_FS_SMALL"])


def check(d, x, y, on=True):
    rect(d, x, y, 13, 13, WHITE, FIELD_EDGE)
    if on:
        txt(d, x + 2, y - 1, "✓", C["TEXT"], PT["SSR_FS_SMALL"], True)


def button(d, x, y, w, t, primary=False, focus=False, h=22):
    if primary:
        rect(d, x, y, w, h, C["PRIMARY"], C["PRIMARY_EDGE"])
        txt_c(d, x, y + 5, w, t, C["PRIMARY_TEXT"])
    else:
        rect(d, x, y, w, h, C["BTN"], C["BTN_EDGE"])
        txt_c(d, x, y + 5, w, t, C["BTN_TEXT"])
    if focus:
        d.rectangle([(x - 1) * S, (y - 1) * S, (x + w + 1) * S, (y + h + 1) * S],
                    outline=C["PRIMARY"], width=1)


def link(d, x, y, t, pt=None):
    txt(d, x, y, t, LINK, pt or PT["SSR_FS_BODY"])


def grid(d, x, y, w, rows_h, cols, rows, link_cols=(), shown=6):
    """Filled header, column rules, blue link cells, grey empty tail."""
    hx = x
    rect(d, x, y, w, 18, C["HEADER"], FIELD_EDGE)
    for cw, name in cols:
        txt(d, hx + 5, y + 4, name, C["TEXT_DIM"], PT["SSR_FS_SMALL"])
        hx += cw
        if hx < x + w:
            d.line([hx * S, y * S, hx * S, (y + 18) * S], fill=FIELD_EDGE)
    body_y = y + 18
    body_h = shown * rows_h
    rect(d, x, body_y, w, body_h, WHITE, FIELD_EDGE)
    for r, row in enumerate(rows):
        ry = body_y + r * rows_h
        cx = x
        for ci, (cw, _) in enumerate(cols):
            val = row[ci] if ci < len(row) else ""
            txt(d, cx + 5, ry + 3, val,
                LINK if ci in link_cols else C["TEXT"], PT["SSR_FS_SMALL"])
            cx += cw
        d.line([x * S, (ry + rows_h) * S, (x + w) * S, (ry + rows_h) * S],
               fill=(230, 230, 230))
    #--- the empty tail, which is what says "there is room for more"
    used = len(rows) * rows_h
    if used < body_h:
        rect(d, x + 1, body_y + used, w - 2, body_h - used - 1, EMPTY)
    cx = x
    for cw, _ in cols[:-1]:
        cx += cw
        d.line([cx * S, body_y * S, cx * S, (body_y + body_h) * S],
               fill=FIELD_EDGE)
    return body_y + body_h


def canvas(w, h, chart=True):
    im = Image.new("RGB", (w * S, h * S), (246, 246, 246) if chart else C["PANEL"])
    d = ImageDraw.Draw(im)
    if chart:
        for gx in range(0, w, 70):
            d.line([gx * S, 0, gx * S, h * S], fill=(228, 230, 233))
        for gy in range(0, h, 56):
            d.line([0, gy * S, w * S, gy * S], fill=(228, 230, 233))
    return im, d


def note(im, s):
    d = ImageDraw.Draw(im)
    d.text((12 * S, (im.size[1] / S - 14) * S), s, fill=C["TEXT_FAINT"], font=f(7))


def window(d, x, y, w, h, title, accent=False):
    rect(d, x, y, w, h, C["PANEL"], C["PANEL_EDGE"])
    return titlebar(d, x, y, w, title, accent)


#====================================================================
#  OPTION A - the reference structure, followed closely.
#  One right-aligned label column per half, group boxes numbered as
#  steps, a real grid, three equal footer buttons.
#====================================================================
def option_a(accent_title=False, name="A"):
    #--- EVERY NUMBER BELOW IS DERIVED. The first draft used guessed
    #--- offsets and the left column's fields ran under the right
    #--- column's labels, while the footer sat on top of Step 3. Both
    #--- are invisible until the thing is drawn, which is the whole
    #--- reason this file exists.
    PADG, ROW = 10, 28
    LAB_L, FLD_L, FLD_LW = 136, 144, 150        # left label/field column
    LAB_R, FLD_R, FLD_RW = 450, 458, 130        # right one
    #--- the unit labels ("USD", "%") sit after the right-hand fields and
    #--- have to be INSIDE the frame; at +22 the window ended under them
    W = FLD_R + FLD_RW + 56

    g1_h = 44
    g2_rows = 4
    g2_h = 18 + 20 + 8 + (18 + g2_rows * 17) + 8 + 14 + 10
    g3_h = 18 + 4 * ROW + 6
    body = 8 + g1_h + 8 + g2_h + 8 + g3_h + 12 + 22 + 10
    H = 24 + body

    im, d = canvas(W + 300, H + 120)
    x, y = 150, 44
    cy = window(d, x, y, W, H, "SS Replay  -  New Replay", accent_title)

    g1y = cy + 8
    groupbox(d, x + PADG, g1y, W - 2 * PADG, g1_h,
             "Step 1  -  where the data comes from")
    txt_r(d, x + LAB_L, g1y + 24, "History source:", C["TEXT"])
    combo(d, x + FLD_L, g1y + 20, 230, "this terminal's own M1 bars")

    g2y = g1y + g1_h + 8
    groupbox(d, x + PADG, g2y, W - 2 * PADG, g2_h, "Step 2  -  what to replay")
    txt_r(d, x + LAB_L, g2y + 22, "Instrument:", C["TEXT"])
    combo(d, x + FLD_L, g2y + 18, 150, "US30.Z26")
    button(d, x + FLD_L + 158, g2y + 18, 86, "Add to list")
    txt(d, x + FLD_L + 252, g2y + 22, "Selected: 1 / 8", C["TEXT_DIM"])

    cols = [(26, "#"), (104, "SYMBOL"), (186, "RANGE AVAILABLE"),
            (94, "SPREAD pts"), (72, "REMOVE")]
    gw = sum(c for c, _ in cols)
    gbot = grid(d, x + 20, g2y + 46, gw, 17, cols,
                [["1", "US30.Z26", "14.09.2021 - 03.10.2026", "variable",
                  "Remove"]], link_cols=(3, 4), shown=g2_rows)
    txt(d, x + 20, gbot + 8, "Common range:  14.09.2021  -  03.10.2026",
        C["TEXT"], PT["SSR_FS_BODY"], True)

    g3y = g2y + g2_h + 8
    groupbox(d, x + PADG, g3y, W - 2 * PADG, g3_h,
             "Step 3  -  the account and the clock")
    left = [("Start of replay:", "combo", "20.10.2021  09:00", ""),
            ("Run until:", "combo", "the end of the data", ""),
            ("Warm-up:", "spin", "31", "days before"),
            ("Rewinding allowed:", "check", True, "")]
    right = [("Account currency:", "combo", "USD", ""),
             ("Starting balance:", "spin", "10,000", "USD"),
             ("Risk per trade:", "spin", "1.00", "%"),
             ("Leverage:", "spin", "100", "")]
    for i, (lab, kind, val, unit) in enumerate(left):
        ry = g3y + 18 + i * ROW
        txt_r(d, x + LAB_L, ry + 4, lab, C["TEXT"])
        if kind == "combo":
            combo(d, x + FLD_L, ry, FLD_LW, val)
        elif kind == "spin":
            spin(d, x + FLD_L, ry, 70, val)
            txt(d, x + FLD_L + 78, ry + 4, unit, C["TEXT_DIM"])
        else:
            check(d, x + FLD_L, ry + 3, val)
    for i, (lab, kind, val, unit) in enumerate(right):
        ry = g3y + 18 + i * ROW
        txt_r(d, x + LAB_R, ry + 4, lab, C["TEXT"])
        if kind == "combo":
            combo(d, x + FLD_R, ry, FLD_RW, val)
        else:
            spin(d, x + FLD_R, ry, FLD_RW, val)
        if unit:
            txt(d, x + FLD_R + FLD_RW + 6, ry + 4, unit, C["TEXT_DIM"])

    fy = g3y + g3_h + 12
    bw = (W - 2 * 14 - 2 * 10) // 3
    button(d, x + 14, fy, bw, "Cancel")
    button(d, x + 14 + bw + 10, fy, bw, "Same as last time")
    button(d, x + 14 + 2 * (bw + 10), fy, bw, "Start replay",
           primary=not accent_title, focus=accent_title)
    note(im, "OPTION %s - the reference structure. Numbered group boxes, one "
             "right-aligned label column per half, a real grid with blue link "
             "cells, three equal footer buttons.%s"
         % (name, "  Title bar in the brand accent." if accent_title else ""))
    return im


#====================================================================
#  OPTION B - the same structure in one column, for a short chart.
#====================================================================
def option_b():
    #--- derived, like A. The first draft kept a guessed 470 and the
    #--- footer sat on "Rewinding allowed" - the same class of fault as
    #--- A's columns, and equally invisible until it was drawn.
    PADG, ROW = 10, 26
    LAB, FLD, FLDW = 132, 140, 200
    W = FLD + FLDW + 56

    rows = [("Start of replay:", "combo", "20.10.2021  09:00", ""),
            ("Run until:", "combo", "the end of the data", ""),
            ("Warm-up:", "spin", "31", "days"),
            ("Account currency:", "combo", "USD", ""),
            ("Starting balance:", "spin", "10,000", "USD"),
            ("Risk per trade:", "spin", "1.00", "%"),
            ("Rewinding allowed:", "check", True, "")]
    g2_rows = 3
    g1_h = 44
    g2_h = 18 + 20 + 8 + (18 + g2_rows * 17) + 8 + 14 + 10
    g3_h = 18 + len(rows) * ROW + 6
    H = 24 + 8 + g1_h + 8 + g2_h + 8 + g3_h + 12 + 22 + 10

    im, d = canvas(W + 420, H + 120)
    x, y = 210, 40
    cy = window(d, x, y, W, H, "SS Replay  -  New Replay")

    g1y = cy + 8
    groupbox(d, x + PADG, g1y, W - 2 * PADG, g1_h,
             "Step 1  -  where the data comes from")
    txt_r(d, x + LAB, g1y + 24, "History source:", C["TEXT"])
    combo(d, x + FLD, g1y + 20, FLDW, "this terminal's M1")

    g2y = g1y + g1_h + 8
    groupbox(d, x + PADG, g2y, W - 2 * PADG, g2_h, "Step 2  -  what to replay")
    txt_r(d, x + LAB, g2y + 22, "Instrument:", C["TEXT"])
    combo(d, x + FLD, g2y + 18, 134, "US30.Z26")
    button(d, x + FLD + 142, g2y + 18, 76, "Add")
    cols = [(24, "#"), (92, "SYMBOL"), (168, "RANGE AVAILABLE"), (72, "REMOVE")]
    gbot = grid(d, x + 20, g2y + 46, sum(c for c, _ in cols), 17, cols,
                [["1", "US30.Z26", "14.09.2021 - 03.10.2026", "Remove"]],
                link_cols=(3,), shown=g2_rows)
    txt(d, x + 20, gbot + 8, "Common range:  14.09.2021 - 03.10.2026",
        C["TEXT"], PT["SSR_FS_SMALL"], True)

    g3y = g2y + g2_h + 8
    groupbox(d, x + PADG, g3y, W - 2 * PADG, g3_h,
             "Step 3  -  the account and the clock")
    for i, (lab, kind, val, unit) in enumerate(rows):
        ry = g3y + 18 + i * ROW
        txt_r(d, x + LAB, ry + 4, lab, C["TEXT"])
        if kind == "combo":
            combo(d, x + FLD, ry, FLDW, val)
        elif kind == "spin":
            spin(d, x + FLD, ry, 90, val)
            if unit:
                txt(d, x + FLD + 98, ry + 4, unit, C["TEXT_DIM"])
        else:
            check(d, x + FLD, ry + 3, val)

    fy = g3y + g3_h + 12
    bw = (W - 2 * 14 - 2 * 10) // 3
    button(d, x + 14, fy, bw, "Cancel")
    button(d, x + 14 + bw + 10, fy, bw, "Same as last")
    button(d, x + 14 + 2 * (bw + 10), fy, bw, "Start replay", primary=True)
    note(im, "OPTION B - the same structure folded into one column, for a "
             "chart too short for A. Identical controls, nothing dropped.")
    return im


#====================================================================
#  OPTION C - the Home window, in the reference's shape.
#====================================================================
def option_c():
    im, d = canvas(840, 560)
    W, H = 330, 266
    x, y = 255, 140
    cy = window(d, x, y, W, H, "SS Replay")
    txt_c(d, x, cy + 14, W, "Connected to account #20242426", C["RUN"])
    txt_c(d, x, cy + 32, W, "Demo  -  virtual trades only", C["TEXT_DIM"],
          PT["SSR_FS_SMALL"])
    items = [("New replay", True), ("Load a saved session", False),
             ("Data Centre", False)]
    by = cy + 58
    for t, prim in items:
        button(d, x + 30, by, W - 60, t, primary=prim, focus=False, h=30)
        by += 38
    button(d, x + 30, by + 14, W - 60, "Close", h=30)
    note(im, "OPTION C - Home, in the reference's shape: a status line, then "
             "stacked full-width actions and nothing else. No settings on "
             "the first screen.")
    return im


#====================================================================
#  OPTION D - the Data Centre as a real grid.
#====================================================================
def option_d():
    im, d = canvas(840, 560)
    W, H = 520, 326
    x, y = 160, 90
    cy = window(d, x, y, W, H, "SS Replay  -  Data Centre")

    txt_r(d, x + 86, cy + 14, "Market Watch:", C["TEXT"])
    txt(d, x + 94, cy + 14, "11 symbols", C["TEXT_DIM"])
    button(d, x + W - 108, cy + 10, 96, "Read again")

    cols = [(104, "SYMBOL"), (104, "FROM"), (104, "TO"),
            (86, "M1 BARS"), (82, "TICKS")]
    rows = [["EURUSD", "02.01.2019", "03.10.2026", "1.8M", "real"],
            ["GBPUSD", "02.01.2019", "03.10.2026", "1.8M", "real"],
            ["XAUUSD", "04.03.2021", "03.10.2026", "1.4M", "real"],
            ["US30.Z26", "14.09.2021", "03.10.2026", "912k", "real"],
            ["NAS100", "14.09.2021", "03.10.2026", "910k", "built"],
            ["APPLE_CFD", "not loaded yet", "", "", ""],
            ["EURTRY", "no M1 history", "", "", ""]]
    bottom = grid(d, x + 14, cy + 40, sum(c for c, _ in cols), 17, cols,
                  rows, link_cols=(), shown=10)
    txt(d, x + 14, bottom + 10, "9 of 11 symbols have minute history here",
        C["TEXT_DIM"], PT["SSR_FS_SMALL"])
    fy = y + H - 32
    button(d, x + 14, fy, 110, "Close")
    button(d, x + W - 124, fy, 110, "Use this symbol", primary=True)
    note(im, "OPTION D - the Data Centre drawn as a real grid: filled header, "
             "column rules, and the grey tail that says the list has room.")
    return im


#====================================================================
#  THE MAIN PANEL.
#
#  THE CONSTRAINT THAT SHAPES IT, checked rather than assumed:
#  SSR_Panel drives itself through PollClicks(), which reads
#  OBJPROP_STATE off its own buttons. That works on ANY chart, and it
#  is the ONE mechanism on purpose - the comment in the file says so:
#  a panel on the replay chart and a panel on the expert's own chart
#  must behave identically rather than through two paths, one of which
#  stops being maintained.
#
#  CHARTEVENT_MOUSE_MOVE is handled too, but MetaTrader only delivers
#  it to the chart a program is attached to. So in two-window mode -
#  the default - the panel gets clicks and nothing else: no drag, no
#  hover, no sliding the speed thumb. In one-window mode it gets all
#  three.
#
#  Everything drawn below therefore works from clicks alone. The
#  slider is already built that way (cells under a slider skin), the
#  combos open a list on click, and the tabs are buttons. Hover is the
#  only thing of the reference's that cannot be had, and nothing here
#  depends on it.
#====================================================================
def menurow(d, x, y, w, items, active=None):
    bx = x + 6
    for i, t in enumerate(items):
        ft = f(PT["SSR_FS_BODY"])
        tw = int(d.textlength(t, font=ft) / S) + 16
        if i == active:
            rect(d, bx, y, tw, 20, C["TAB_ON"], C["TAB_EDGE"])
        txt_c(d, bx, y + 4, tw, t, C["TEXT"])
        bx += tw
    d.line([x * S, (y + 20) * S, (x + w) * S, (y + 20) * S], fill=C["GROUP_EDGE"])
    return y + 21


def slider(d, x, y, w, frac):
    rect(d, x, y + 4, w, 5, C["TRACK"], C["TRACK_EDGE"])
    fw = int(w * frac)
    if fw > 2:
        rect(d, x + 1, y + 5, fw - 2, 3, C["TRACK_FILL"], C["TRACK_FILL"])
    rect(d, x + fw - 4, y, 9, 13, C["THUMB"], C["THUMB_EDGE"])


def deal(d, x, y, w, h, t1, t2, buy):
    rect(d, x, y, w, h, C["BUY"] if buy else C["SELL"],
         C["BUY_EDGE"] if buy else C["SELL_EDGE"])
    txt_c(d, x, y + 5, w, t1, C["DEAL_TEXT"], PT["SSR_FS_SMALL"])
    txt_c(d, x, y + 18, w, t2, C["DEAL_TEXT"], PT["SSR_FS_BODY"], True)


def tabs(d, x, y, w, names, active):
    tw = w // len(names)
    for i, t in enumerate(names):
        on = (i == active)
        rect(d, x + i * tw, y, tw, 18,
             C["TAB_ON"] if on else C["TAB"], C["TAB_EDGE"])
        txt_c(d, x + i * tw, y + 4, tw, t,
              C["TEXT"] if on else C["TEXT_DIM"], PT["SSR_FS_SMALL"])
    return y + 18


def main_panel(collapsed=False, W=420, name="P1"):
    PADG = 8
    COL_L = 186                       # the control column
    GAP = 6
    COL_R = W - 2 * PADG - COL_L - GAP

    head_h = 24
    menu_h = 21
    tr_h = 62                         # play / clock / speed
    nav_h = 50                        # prev / symbol+tf / next
    body_h = 0 if collapsed else 168
    stat_h = 20
    H = head_h + menu_h + tr_h + nav_h + body_h + stat_h + 6

    im, d = canvas(W + 420, H + 160)
    x, y = 210, 60
    cy = window(d, x, y, W, H, "SS Replay  -  DEMO")
    cy = menurow(d, x, cy, W,
                 ["Replay", "Charts", "Account", "Market hours", "News",
                  "Trades"], 0)

    #--- transport
    ty = cy + 6
    button(d, x + PADG, ty, 76, "Pause", primary=True, h=50)
    txt(d, x + PADG + 86, ty, "20.10.2021 11:47:18", C["TEXT"],
        PT["SSR_FS_CLOCK"])
    txt_r(d, x + W - PADG - 78, ty + 4, "Wed", C["TEXT_DIM"], PT["SSR_FS_SMALL"])
    txt(d, x + PADG + 86, ty + 24, "Speed:  5 x", C["TEXT_DIM"],
        PT["SSR_FS_SMALL"])
    slider(d, x + PADG + 86, ty + 36, W - PADG * 2 - 86 - 76, 0.13)
    button(d, x + W - PADG - 70, ty, 70, "Auto pause", h=22)

    #--- navigation
    ny = ty + 56
    button(d, x + PADG, ny, 76, "|<  Prev", h=44)
    combo(d, x + PADG + 86, ny, 104, "US30.Z26")
    combo(d, x + PADG + 196, ny, 60, "M5")
    button(d, x + PADG + 86, ny + 24, 104, "Sync with chart", h=20)
    link(d, x + PADG + 196, ny + 28, "-00:02:42", PT["SSR_FS_SMALL"])
    button(d, x + W - PADG - 76, ny, 76, "Next  >|", h=44)

    by = ny + 50
    if not collapsed:
        #--- left column: what the next trade will be
        rows = [("Risk:", "spin", "1.00", "%"),
                ("Lots:", "spin", "0.10", ""),
                ("SL pips:", "spin", "0", ""),
                ("TP pips:", "spin", "0", "")]
        for i, (lab, _k, val, unit) in enumerate(rows):
            ry = by + i * 24
            txt_r(d, x + PADG + 54, ry + 4, lab, C["TEXT"], PT["SSR_FS_SMALL"])
            spin(d, x + PADG + 60, ry, 76, val)
            if unit:
                txt(d, x + PADG + 140, ry + 4, unit, C["TEXT_DIM"],
                    PT["SSR_FS_SMALL"])
        ly = by + 4 * 24 + 2
        for i, (lab, val) in enumerate((("Comment:", "Set"),
                                        ("Trailing stop:", "Set"),
                                        ("Blind mode:", "off"))):
            txt(d, x + PADG, ly + i * 16, lab, C["TEXT_DIM"], PT["SSR_FS_SMALL"])
            link(d, x + PADG + 86, ly + i * 16, val, PT["SSR_FS_SMALL"])
        ly += 3 * 16 + 4
        button(d, x + PADG, ly, 88, "Save order", h=20)
        button(d, x + PADG + 94, ly, 88, "Load order", h=20)

        #--- right pane: the ticket
        rx = x + PADG + COL_L + GAP
        ry = tabs(d, rx, by - 2, COL_R, ["Market order", "Pending"], 0)
        rect(d, rx, ry, COL_R, body_h - 18, C["PANEL"], C["TAB_EDGE"])
        txt_c(d, rx, ry + 5, COL_R, "US30.Z26", C["TEXT"], PT["SSR_FS_BODY"],
              True)
        dw = (COL_R - 14) // 2
        deal(d, rx + 5, ry + 22, dw, 34, "Buy @", "35473.6", True)
        deal(d, rx + 9 + dw, ry + 22, dw, 34, "Sell @", "35469.5", False)
        info = [("Spread", "405.2 pips", C["TEXT_DIM"]),
                ("Equity", "10009.60   +0.10%", C["RUN"]),
                ("Floating P/L", "-4.05", C["STOP"])]
        for i, (k, v, col) in enumerate(info):
            iy = ry + 62 + i * 15
            txt(d, rx + 6, iy, k, C["TEXT_DIM"], PT["SSR_FS_SMALL"])
            txt_r(d, rx + COL_R - 6, iy, v, col, PT["SSR_FS_SMALL"])
        #--- THE VERB ABOVE THE ROW, not under it. It was under, and the
        #--- pane's own bottom border was drawn straight through it -
        #--- three buttons reading "Winners  Losers  All" with no word
        #--- anywhere saying what pressing one DOES.
        txt(d, rx + 6, ry + 110, "close", C["TEXT_DIM"], PT["SSR_FS_SMALL"])
        cy2 = ry + 122
        cw = (COL_R - 16) // 3
        for i, t in enumerate(("Winners", "Losers", "All")):
            rect(d, rx + 5 + i * (cw + 3), cy2, cw, 22, C["PANEL"], C["STOP"])
            txt_c(d, rx + 5 + i * (cw + 3), cy2 + 5, cw, t, C["STOP"],
                  PT["SSR_FS_SMALL"])

    #--- status strip
    sy = y + H - stat_h - 2
    rect(d, x + 1, sy, W - 2, stat_h, C["STATUS"], C["GROUP_EDGE"])
    txt(d, x + PADG, sy + 4, "Live mode", C["TEXT"], PT["SSR_FS_SMALL"], True)
    txt(d, x + PADG + 62, sy + 4, "|   Running   |   Account in USD",
        C["TEXT_DIM"], PT["SSR_FS_SMALL"])
    txt_r(d, x + W - PADG, sy + 4, "Expand" if collapsed else "Collapse",
          LINK, PT["SSR_FS_SMALL"])

    note(im, "%s - the main panel in the reference's structure%s. Everything "
             "here is driven by clicks alone, which is what the replay chart "
             "delivers; drag is a bonus in one-window mode, never a "
             "requirement." % (name, ", collapsed" if collapsed else ""))
    return im


#====================================================================
#  P3 - THE NARROW PANEL, and why it is a different layout.
#
#  P1's two-pane body cannot be squeezed. Measured rather than
#  guessed: the control column needs 186, the ticket needs 190 for a
#  Buy and a Sell side by side with a readable price, plus a 6 px gap
#  and 16 px of frame - 398 before anything else, and the menu row
#  wants about 400 on its own. Drawn at 340 it came apart in four
#  places at once: the menu ran off the frame, the weekday landed on
#  the clock, the timeframe combo went under Next, and the close row
#  left the pane.
#
#  So a narrow panel does not get a smaller version of P1. It gets the
#  same STRUCTURE with the ticket as a TAB instead of a side pane -
#  which is what the product does today, and what the reference itself
#  does with its Orders window: put it somewhere else rather than
#  crush it.
#====================================================================
def main_panel_narrow(W=320, name="P3"):
    PADG = 8
    head_h, menu_h, stat_h = 24, 21, 20
    tr_h = 54
    nav_h = 28
    tab_h = 20
    #--- ADDED UP, not picked. 6 lead + 34 of deal buttons + four 22 px
    #--- rows + 2 + three 14 px readouts + 6 trail. It was 150, and the
    #--- status strip was drawn through Equity and Floating P/L.
    sheet_h = 6 + 34 + 4 * 22 + 2 + 3 * 14 + 6
    H = head_h + menu_h + tr_h + nav_h + tab_h + sheet_h + stat_h + 8

    im, d = canvas(W + 520, H + 160)
    x, y = 210, 60
    cy = window(d, x, y, W, H, "SS Replay  -  DEMO")
    #--- four, not six: the long names are on the menu of the wide
    #--- panel, and a row that does not fit is not a menu
    cy = menurow(d, x, cy, W, ["Replay", "Account", "Hours", "Trades"], 0)

    ty = cy + 6
    button(d, x + PADG, ty, 64, "Pause", primary=True, h=44)
    txt(d, x + PADG + 72, ty, "20.10.2021 11:47:18", C["TEXT"],
        PT["SSR_FS_CLOCK"])
    txt(d, x + PADG + 72, ty + 24, "Speed:  5 x", C["TEXT_DIM"],
        PT["SSR_FS_SMALL"])
    txt_r(d, x + W - PADG, ty + 24, "Wed", C["TEXT_DIM"], PT["SSR_FS_SMALL"])
    slider(d, x + PADG + 72, ty + 34, W - PADG * 2 - 72, 0.13)

    ny = ty + 50
    button(d, x + PADG, ny, 52, "|< Prev", h=22)
    combo(d, x + PADG + 58, ny, 96, "US30.Z26", h=22)
    combo(d, x + PADG + 158, ny, 48, "M5", h=22)
    button(d, x + W - PADG - 52, ny, 52, "Next >|", h=22)

    tabsy = tabs(d, x + PADG, ny + 28, W - 2 * PADG,
                 ["Order", "Open", "Stats", "Day"], 0)
    rect(d, x + PADG, tabsy, W - 2 * PADG, sheet_h - 2, C["PANEL"],
         C["TAB_EDGE"])

    sx = x + PADG + 6
    sw = W - 2 * PADG - 12
    dw = (sw - 6) // 2
    deal(d, sx, tabsy + 6, dw, 34, "Buy @", "35473.6", True)
    deal(d, sx + dw + 6, tabsy + 6, dw, 34, "Sell @", "35469.5", False)
    for i, (lab, val, unit) in enumerate((("Risk", "1.00", "%"),
                                          ("Lots", "0.10", ""),
                                          ("SL pips", "0", ""),
                                          ("TP pips", "0", ""))):
        ry = tabsy + 46 + i * 22
        txt(d, sx, ry + 4, lab, C["TEXT_DIM"], PT["SSR_FS_SMALL"])
        spin(d, sx + 70, ry, 76, val)
        if unit:
            txt(d, sx + 150, ry + 4, unit, C["TEXT_DIM"], PT["SSR_FS_SMALL"])
    iy = tabsy + 46 + 4 * 22 + 2
    for i, (k, v, col) in enumerate((("Spread", "405.2 pips", C["TEXT_DIM"]),
                                     ("Equity", "10009.60  +0.10%", C["RUN"]),
                                     ("Floating", "-4.05", C["STOP"]))):
        txt(d, sx, iy + i * 14, k, C["TEXT_DIM"], PT["SSR_FS_SMALL"])
        txt_r(d, sx + sw, iy + i * 14, v, col, PT["SSR_FS_SMALL"])

    sy = y + H - stat_h - 2
    rect(d, x + 1, sy, W - 2, stat_h, C["STATUS"], C["GROUP_EDGE"])
    txt(d, x + PADG, sy + 4, "Live mode", C["TEXT"], PT["SSR_FS_SMALL"], True)
    txt(d, x + PADG + 62, sy + 4, "|  Running", C["TEXT_DIM"],
        PT["SSR_FS_SMALL"])
    txt_r(d, x + W - PADG, sy + 4, "Collapse", LINK, PT["SSR_FS_SMALL"])

    note(im, "%s - the narrow panel. P1's two-pane body needs about 420 px; "
             "below that it comes apart. So the ticket becomes a TAB rather "
             "than a crushed side pane - the same structure, one column."
         % name)
    return im


if __name__ == "__main__":
    option_a(False, "A").save(os.path.join(OUT, "A-new-replay.png"), quality=95)
    option_a(True, "A2").save(os.path.join(OUT, "A2-accent-titlebar.png"))
    option_b().save(os.path.join(OUT, "B-one-column.png"))
    option_c().save(os.path.join(OUT, "C-home.png"))
    option_d().save(os.path.join(OUT, "D-data-centre.png"))
    main_panel(False, 420, "P1").save(os.path.join(OUT, "P1-main-panel.png"))
    main_panel(True, 420, "P2").save(os.path.join(OUT, "P2-collapsed.png"))
    main_panel_narrow(320, "P3").save(os.path.join(OUT, "P3-narrow.png"))
    print("wrote 8 options to", OUT)

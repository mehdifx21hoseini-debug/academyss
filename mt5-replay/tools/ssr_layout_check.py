#!/usr/bin/env python3
"""Do two things this product draws ever land on top of each other?

WHY THIS EXISTS
---------------
SSR_DataCenter shipped its first draft with the hint line six pixels
inside the Stop button, drawn straight through it. Nothing errored.
MetaTrader draws both objects and says nothing, the compiler cannot see
a collision between two integers, and every one of the twenty-one
existing audits passed: A19 checks the words, A18 checks the contrast,
Extent() checks that nothing falls OUT of the frame - and none of them
can see two things inside the frame sharing a pixel.

It was found by rendering the window at its own coordinates and looking
at it. This file is that look, automated, so the next layout change gets
it for free.

WHAT IT IS NOT
--------------
It is not a general layout engine. It reads the #define constants out of
the source - so it cannot drift from the code the way a hand-kept copy
of the numbers would - and then checks the handful of stacked rows whose
spacing is arithmetic rather than obvious. A row computed inside a loop
is checked once, at its first and last index.
"""
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
UI   = os.path.join(ROOT, "MQL5", "Include", "SSReplay", "Ui")


def defines(path, env=None):
    """Every `#define NAME <int expression>` in a file, evaluated.

    Values are resolved against the ones already read, which is why the
    file is walked in order: SSR_DC_H is written in terms of
    SSR_HEADER_H and SSR_DC_ROWS, exactly as the compiler sees it.

    ONLY THE BRANCH THAT IS COMPILED. SSR_Theme.mqh defines SSR_PANEL_W
    twice - 310 under SSR_LAYOUT_RAIL and 420 under the #else - and a
    reader that just keeps the last one measures the layout that is NOT
    built. A18 learned this the hard way on the palettes: it was
    auditing the contrast of a theme nobody was compiling, and passing.
    """
    #--- seeded with what is already known, because SSR_DC_H is written
    #--- in terms of SSR_HEADER_H from the theme - exactly as the
    #--- compiler sees it after the include.
    out = dict(env or {})
    flags = set(out.keys())
    #--- a stack of (taken_now, taken_already) for the #if nest
    stack = []
    for line in open(path, encoding="utf-8"):
        t = line.strip()

        m = re.match(r"#if(n?)def\s+([A-Za-z_][A-Za-z0-9_]*)", t)
        if m:
            on = (m.group(2) in flags)
            if m.group(1) == "n":
                on = not on
            live = on and all(a for a, _ in stack)
            stack.append((on, on))
            continue
        if t.startswith("#else"):
            if stack:
                on, ever = stack[-1]
                stack[-1] = (not ever, True)
            continue
        if t.startswith("#endif"):
            if stack:
                stack.pop()
            continue
        if not all(a for a, _ in stack):
            continue

        m = re.match(r"#define\s+([A-Za-z_][A-Za-z0-9_]*)\s*$", t)
        if m:
            flags.add(m.group(1))
            continue

        m = re.match(r"#define\s+(SSR_[A-Z0-9_]+)\s+(.+?)\s*(?://.*)?$", t)
        if not m:
            continue
        name, expr = m.group(1), m.group(2).strip()
        flags.add(name)
        if not re.fullmatch(r"[A-Za-z0-9_+\-*/() ]+", expr):
            continue
        try:
            out[name] = int(eval(expr, {"__builtins__": {}}, out))
        except Exception:
            pass
    return out


#--- Consolas advances every glyph 1126/2048 of an em. That is the
#--- font's definition, not an estimate, so the width of a monospaced
#--- label is arithmetic and can be checked here rather than guessed.
#--- Proportional text cannot be done this way and is not attempted:
#--- SSR_QA_FontProbe measures the real strings on the real terminal,
#--- which is the only honest answer for Segoe UI.
MONO_ADVANCE = 1126.0 / 2048.0

#--- A PESSIMISTIC px-per-point-per-character FOR PROPORTIONAL TEXT.
#--- Segoe UI averages nearer 0.44 of its point size per Latin character;
#--- 0.50 is deliberately over, so this guard fires BEFORE a string is
#--- actually too wide rather than after. It is an upper bound, not a
#--- measurement, and it is only ever used to reject - never to confirm
#--- that something fits. SSR_QA_FontProbe measures the real strings on
#--- the real terminal, and that is the number to believe.
PROP_PER_PT = 0.50


def prop_px(chars, pt):
    return int(round(chars * PROP_PER_PT * pt * 4.0 / 3.0))


def mono_px(chars, pt):
    return int(round(chars * MONO_ADVANCE * pt * 4.0 / 3.0))


def check(name, rows, bottom, problems):
    """rows is [(label, y, height)]. Nothing may overlap, or pass `bottom`."""
    rows = sorted(rows, key=lambda r: r[1])
    for i in range(len(rows) - 1):
        a, b = rows[i], rows[i + 1]
        if a[1] + a[2] > b[1]:
            problems.append(
                "%s: \"%s\" (y %d..%d) runs into \"%s\" (y %d) by %d px"
                % (name, a[0], a[1], a[1] + a[2], b[0], b[1],
                   a[1] + a[2] - b[1]))
    if rows and rows[-1][1] + rows[-1][2] > bottom:
        problems.append(
            "%s: \"%s\" ends at y %d, past the window bottom at %d"
            % (name, rows[-1][0], rows[-1][1] + rows[-1][2], bottom))


def main():
    problems = []

    def catalogue(key):
        src = open(os.path.join(UI, "SSR_Strings.mqh"), encoding="utf-8").read()
        m = re.search(r'SSRAddString\(out, n, SSR_S_%s,\s*"[^"]*",\s*\n?\s*"([^"]*)"'
                      % key, src)
        return m.group(1) if m else ""


    theme = defines(os.path.join(UI, "SSR_Theme.mqh"))
    #--- A LABEL'S DRAWN HEIGHT, DERIVED FROM THE THEME rather than
    #--- written here. It was 12 - correct for the 7 pt small size - and
    #--- the moment the faces changed and every size went up a point it
    #--- would have been checking the old layout against the new one and
    #--- passing. Points to pixels is 4/3 at 96 dpi, and a line box is
    #--- about a quarter taller than its glyphs: 5/3 of the point size,
    #--- rounded up, which gives 12 at 7 pt and 14 at 8 pt.
    TEXT_H = -(-theme["SSR_FS_SMALL"] * 5 // 3)
    print("checking at SSR_FS_SMALL = %d pt, line height %d px"
          % (theme["SSR_FS_SMALL"], TEXT_H))

    #------------------------------------------------------------------
    # The data centre.
    #------------------------------------------------------------------
    d = dict(theme)
    d.update(defines(os.path.join(UI, "SSR_DataCenter.mqh"), theme))
    H    = d["SSR_DC_H"]
    rows = d["SSR_DC_ROWS"]
    rh   = d["SSR_DC_ROW_H"]
    hy   = d["SSR_HEADER_H"] + 6                 # column headings
    ly   = hy + 14                               # the well
    check("data centre", [
        ("caption",   1,              d["SSR_HEADER_H"]),
        ("headings",  hy,             TEXT_H),
        ("well",      ly,             rows * rh + 4),
        ("paging",    ly + rows * rh + 10, 18),
        ("progress",  H - 66,         TEXT_H),
        ("hint",      H - 48,         TEXT_H),
        ("buttons",   H - d["SSR_BTN_H"] - 6, d["SSR_BTN_H"]),
    ], H, problems)

    #------------------------------------------------------------------
    # The nameplate.
    #------------------------------------------------------------------
    s = dict(theme)
    s.update(defines(os.path.join(UI, "SSR_Splash.mqh"), theme))
    check("nameplate", [
        ("name",     10, 18),
        ("tagline",  29, TEXT_H),
        ("rule",     46, 1),
        ("account",  52, TEXT_H),
        ("guarantee",68, TEXT_H),
        ("status",   88, TEXT_H),
    ], s["SSR_SPLASH_H"], problems)


    #------------------------------------------------------------------
    # The session sheet. Two groups inside SSR_SHEET_H, where the second
    # one carries a grid whose height is arithmetic - exactly the shape
    # that overflows silently when a row is added to it.
    #------------------------------------------------------------------
    mh = dict(theme)
    mh.update(defines(os.path.join(UI, "SSR_MarketHours.mqh"), theme))
    centres = 4
    grid = 13 + centres * mh["SSR_MH_RH"] + 14 + 13 + 13
    check("session sheet", [
        ("housekeeping group", 0,  58),
        ("market hours group", 62, 14 + grid),
    ], theme["SSR_SHEET_H"], problems)

    #--- and the grid has to fit the sheet's WIDTH beside the rail
    sheet_w = (theme["SSR_PANEL_W"] - 2 * theme["SSR_PAD"]
               - theme["SSR_RAIL_W"] - theme["SSR_GAP"])
    used = 6 + mh["SSR_MH_W"]
    if used > sheet_w:
        problems.append(
            "session sheet: the market-hours grid is %d px wide inside a "
            "%d px sheet, over by %d" % (used, sheet_w, used - sheet_w))

    print("layout: SSR_PANEL_W=%d RAIL_W=%d sheet=%d px, grid needs %d"
          % (theme["SSR_PANEL_W"], theme["SSR_RAIL_W"], sheet_w, used))

    #------------------------------------------------------------------
    # The clock. The one monospaced label on the panel, and the one that
    # broke: nineteen characters at 14 pt is 195 px, and the label to
    # its right used to start at 192. Four pixels clear in the old face,
    # eleven pixels through it in the new one, and nothing anywhere
    # reports an overlap.
    #------------------------------------------------------------------
    clock_chars = len("2026.08.27 14:35:00")
    clock_w = mono_px(clock_chars, theme["SSR_FS_CLOCK"])
    clock_end = theme["SSR_PAD"] + clock_w
    #--- what sits to its right on that line, from DrawClock
    dow_x = theme["SSR_PANEL_W"] - theme["SSR_PAD"] - 26
    print("clock: %d chars at %d pt = %d px, ends at %d; next label at %d"
          % (clock_chars, theme["SSR_FS_CLOCK"], clock_w, clock_end, dow_x))
    if clock_end > dow_x:
        problems.append(
            "panel clock: %d px of monospaced text ends at x %d, under the "
            "label starting at x %d - over by %d"
            % (clock_w, clock_end, dow_x, clock_end - dow_x))

    #------------------------------------------------------------------
    # Small labels that have to fit a known box. Upper-bound widths, so
    # a pass here is not proof - but a failure is.
    #------------------------------------------------------------------
    sheet_inner = sheet_w - 6

    #--- WHERE THE OVERLAP LABEL STARTS, read from the same table that
    #--- draws it. Hardcoding "the bands end at 22" here was wrong by
    #--- five hours and made the guard fire on a string that fits.
    mh_src = open(os.path.join(UI, "SSR_MarketHours.mqh"), encoding="utf-8").read()
    hours = [(int(a), int(b)) for a, b in
             re.findall(r"from_utc\s*=\s*(\d+);\s*out\[\d\]\.to_utc\s*=\s*(\d+)",
                        mh_src)]

    def _open(fr, to, h):
        return (fr <= h < to) if fr <= to else (h >= fr or h < to)

    ov_end = 0
    if len(hours) >= 4:
        for h in range(24):
            if _open(hours[2][0], hours[2][1], h) and \
               _open(hours[3][0], hours[3][1], h):
                ov_end = h + 1
    overlap_label_x = mh["SSR_MH_GUTTER"] + ov_end * mh["SSR_MH_CW"] + 4
    print("market hours: London/New York overlap ends at %02d:00, "
          "label starts at x %d of %d" % (ov_end, overlap_label_x, sheet_inner))
    for key, budget, where in (
            ("MH_NOTE",     sheet_inner, "market-hours caveat"),
            ("MH_NOW",      sheet_inner, "market-hours now line"),
            ("MH_OVERLAP",  sheet_inner - overlap_label_x,
             "market-hours overlap label"),
            ("DC_HINT",     theme["SSR_PANEL_W"], "data centre hint")):
        txt = catalogue(key)
        if txt == "":
            continue
        #--- a format string draws wider than it reads; the %s stands in
        #--- for real text, so it is counted as a modest twelve
        shown = len(txt.replace("%s", "x" * 12).replace("%02d", "00")
                       .replace("%+d", "+00").replace("%d", "00"))
        w_ = prop_px(shown, theme["SSR_FS_SMALL"])
        if w_ > budget:
            problems.append(
                "%s: \"%s\" is at most %d px wide in a %d px box - over by %d"
                % (where, txt[:40], w_, budget, w_ - budget))

    #------------------------------------------------------------------
    # The order ticket, now that it is two columns. Both columns and the
    # gap have to fit the sheet, and the taller of the two has to fit
    # SSR_SHEET_H - the sheet does not scroll.
    #------------------------------------------------------------------
    sheet_w2 = theme["SSR_PANEL_W"] - 2 * theme["SSR_PAD"]
    if sheet_w2 >= theme["SSR_TICKET_2COL"]:
        lw = theme["SSR_TICKET_LEFT_W"]
        rw = sheet_w2 - lw - theme["SSR_GAP"]
        left_h = 68 + 30 + 4 + 30        # risk+tag, then buy over sell
        right_h = 128                    # the stop/target group
        print("ticket: two columns, left %d + gap %d + right %d = %d of %d; "
              "tallest column %d of %d"
              % (lw, theme["SSR_GAP"], rw, lw + theme["SSR_GAP"] + rw,
                 sheet_w2, max(left_h, right_h), theme["SSR_SHEET_H"]))
        if rw < 155:
            problems.append(
                "order ticket: the right column is %d px and the stop row "
                "needs 155" % rw)
        if max(left_h, right_h) > theme["SSR_SHEET_H"]:
            problems.append(
                "order ticket: the tallest column is %d px in a %d px sheet"
                % (max(left_h, right_h), theme["SSR_SHEET_H"]))

    #------------------------------------------------------------------
    # The Home dialog, and whether it clears the host page beside it.
    #------------------------------------------------------------------
    sp = dict(theme)
    sp.update(defines(os.path.join(UI, "SSR_Splash.mqh"), theme))
    hp = dict(theme)
    hp.update(defines(os.path.join(UI, "SSR_SetupPanel.mqh"), theme))
    for n in (3, 5):
        H = (theme["SSR_HOME_TITLE"] + theme["SSR_HOME_HEAD"]
             + n * theme["SSR_HOME_BTN_H"] + (n - 1) * theme["SSR_HOME_GAP"]
             + theme["SSR_HOME_FOOT"])
        stack = [("title bar", 0, theme["SSR_HOME_TITLE"]),
                 ("account", theme["SSR_HOME_TITLE"] + 14, TEXT_H),
                 ("mode", theme["SSR_HOME_TITLE"] + 36, TEXT_H)]
        by = theme["SSR_HOME_TITLE"] + theme["SSR_HOME_HEAD"]
        for i in range(n):
            stack.append(("action %d" % (i + 1), by, theme["SSR_HOME_BTN_H"]))
            by += theme["SSR_HOME_BTN_H"] + theme["SSR_HOME_GAP"]
        check("home (%d actions)" % n, stack, H, problems)

    beside = sp["SSR_SPLASH_TX"] + sp["SSR_SPLASH_TEXT_W"] + 24
    print("home: dialog starts at x %d, page text ends at %d"
          % (beside, sp["SSR_SPLASH_TX"] + sp["SSR_SPLASH_TEXT_W"]))
    if beside < sp["SSR_SPLASH_TX"] + sp["SSR_SPLASH_TEXT_W"]:
        problems.append("home dialog starts inside the host page's text")

    #------------------------------------------------------------------
    # The title bar. Chips grow from the left, the three window buttons
    # are pinned to the right, and nothing in either reports a collision
    # - the chips are drawn by a loop that returns its own width, so a
    # longer state name just walks further right until it is under a
    # button nobody can press any more.
    #------------------------------------------------------------------
    CHIP = lambda t: 10 + len(t) * 6          # CSSRWidgets::Chip
    #--- THE REAL WORST CASES, read out of the source rather than
    #--- invented: the longest SSRStateName, the longest fidelity short
    #--- name plus the " !" it gains when degraded, and the two mode
    #--- chips from the catalogue.
    types_src = open(os.path.join(ROOT, "MQL5", "Include", "SSReplay",
                                  "Common", "SSR_Types.mqh"),
                     encoding="utf-8").read()
    states = re.findall(r'case SSR_STATE_[A-Z]+:\s*return "([A-Z]+)"', types_src)
    fids = re.findall(r'case SSR_FIDELITY_[A-Z_]+:\s*return "([A-Z]+)"', types_src)
    chips = [max(states, key=len) if states else "RESETTING",
             (max(fids, key=len) if fids else "SYNTH") + " !",
             catalogue("BLIND"), catalogue("PROP")]
    cx = 118                                   # DrawCaption's start
    for t in chips:
        cx += CHIP(t) + 4
    buttons_x = theme["SSR_PANEL_W"] - 60      # the minimise button
    print("caption: chips end at x %d, window buttons start at x %d"
          % (cx, buttons_x))
    if cx > buttons_x:
        problems.append(
            "title bar: the mode chips reach x %d and the window buttons "
            "start at x %d - over by %d" % (cx, buttons_x, cx - buttons_x))

    if problems:
        for p_ in problems:
            print("LAYOUT  " + p_)
        print("\n%d collision(s)." % len(problems))
        return 1
    print("layout clean: nothing overlaps, nothing falls out of its frame")
    return 0


if __name__ == "__main__":
    sys.exit(main())

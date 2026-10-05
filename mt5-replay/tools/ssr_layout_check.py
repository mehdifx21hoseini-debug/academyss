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
    """
    #--- seeded with what is already known, because SSR_DC_H is written
    #--- in terms of SSR_HEADER_H from the theme - exactly as the
    #--- compiler sees it after the include.
    out = dict(env or {})
    for line in open(path, encoding="utf-8"):
        m = re.match(r"\s*#define\s+(SSR_[A-Z0-9_]+)\s+(.+?)\s*(?://.*)?$", line)
        if not m:
            continue
        name, expr = m.group(1), m.group(2).strip()
        if not re.fullmatch(r"[A-Za-z0-9_+\-*/() ]+", expr):
            continue
        try:
            out[name] = int(eval(expr, {"__builtins__": {}}, out))
        except Exception:
            pass
    return out


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
    # The home screen. Its height is computed from the row count, so it
    # is checked at both ends: two actions (nothing saved yet) and four.
    #------------------------------------------------------------------
    p = dict(theme)
    p.update(defines(os.path.join(UI, "SSR_SetupPanel.mqh"), theme))
    for n in (2, 4):
        H = 34 + 22 + n * 46 + 30 + 10
        stack = [("title", 9, TEXT_H), ("rule", 28, 1), ("guarantee", 34, TEXT_H)]
        by = 34 + 22
        for i in range(n):
            stack.append(("action %d" % (i + 1), by, 26))
            stack.append(("reason %d" % (i + 1), by + 29, TEXT_H))
            by += 46
        stack.append(("customise", by + 4, 22))
        check("home (%d actions)" % n, stack, H, problems)

    if problems:
        for p_ in problems:
            print("LAYOUT  " + p_)
        print("\n%d collision(s)." % len(problems))
        return 1
    print("layout clean: nothing overlaps, nothing falls out of its frame")
    return 0


if __name__ == "__main__":
    sys.exit(main())

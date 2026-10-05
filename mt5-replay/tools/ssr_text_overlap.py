#!/usr/bin/env python3
"""Find text drawn on top of other text, across every UI surface.

READ-ONLY. It changes nothing; it reports.

HOW IT WORKS, and what that is worth
------------------------------------
Every draw call in the Ui tree is extracted with its x, y and text.
The coordinates are expressions in the drawing function's own locals -
x, y, w, W - so they are evaluated with those set to 0, 0 and the real
panel/sheet widths, which is exactly the frame each function draws in.
Text comes from a literal, from T() resolved against the catalogue, or
from a StringFormat whose placeholders are filled with plausible values.

WHAT IT CANNOT KNOW, and therefore does not claim:
  - two calls in different branches of an if never appear together, and
    this cannot see that. Those are reported as SAME-ROW, not as faults.
  - a Hide() somewhere else may be suppressing one of them.
  - proportional text width is an upper bound, never a measurement.
So a finding here is a QUESTION for a human, except where the overlap
is total - same row, and one string starts inside another's run - which
is reported separately as CONFIRMED.
"""
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
UI = os.path.join(ROOT, "MQL5", "Include", "SSReplay", "Ui")

#--- the catalogue, so T(SSR_S_X) can be given its real length
CAT = {}
src = open(os.path.join(UI, "SSR_Strings.mqh"), encoding="utf-8").read()
for m in re.finditer(r'SSRAddString\(out, n, (SSR_S_[A-Z0-9_]+),\s*"[^"]*",\s*\n?\s*"([^"]*)"', src):
    CAT[m.group(1)] = m.group(2)

#--- the theme's numbers, active branch only
DEF = {}
flags = set()
stack = []
for line in open(os.path.join(UI, "SSR_Theme.mqh"), encoding="utf-8"):
    t = line.strip()
    m = re.match(r"#if(n?)def\s+([A-Za-z_]\w*)", t)
    if m:
        on = (m.group(2) in flags)
        if m.group(1) == "n":
            on = not on
        stack.append((on, on))
        continue
    if t.startswith("#else"):
        if stack:
            o, e = stack[-1]
            stack[-1] = (not e, True)
        continue
    if t.startswith("#endif"):
        if stack:
            stack.pop()
        continue
    if not all(a for a, _ in stack):
        continue
    m = re.match(r"#define\s+([A-Za-z_]\w*)\s*$", t)
    if m:
        flags.add(m.group(1))
        continue
    m = re.match(r"#define\s+([A-Za-z_]\w*)\s+(.+?)\s*(?://.*)?$", t)
    if m and re.fullmatch(r"[A-Za-z0-9_+\-*/() ]+", m.group(2)):
        flags.add(m.group(1))
        try:
            DEF[m.group(1)] = int(eval(m.group(2), {"__builtins__": {}}, DEF))
        except Exception:
            pass

PT_SMALL = DEF.get("SSR_FS_SMALL", 8)
PT_BODY = DEF.get("SSR_FS_BODY", 9)
PT_CLOCK = DEF.get("SSR_FS_CLOCK", 14)
#--- upper bound, never a measurement; see the header
PROP = 0.50
MONO = 1126.0 / 2048.0


def px(chars, pt, mono=False):
    return int(round(chars * (MONO if mono else PROP) * pt * 4.0 / 3.0))


def split_args(s, at):
    d = 0
    cur = ""
    out = []
    i = at + 1
    while i < len(s):
        c = s[i]
        if c == '"':
            j = i + 1
            while j < len(s) and s[j] != '"':
                j += 2 if s[j] == "\\" else 1
            cur += s[i:j + 1]
            i = j + 1
            continue
        if c in "([":
            d += 1
        elif c in ")]":
            if d == 0:
                out.append(cur.strip())
                return out, i
            d -= 1
        if c == "," and d == 0:
            out.append(cur.strip())
            cur = ""
        else:
            cur += c
        i += 1
    return out, i


def text_len(expr):
    """How many characters this argument will draw. None = cannot tell."""
    e = expr.strip()
    m = re.fullmatch(r'"((?:[^"\\]|\\.)*)"', e)
    if m:
        return len(m.group(1))
    m = re.fullmatch(r"T\((SSR_S_[A-Z0-9_]+)\)", e)
    if m:
        return len(CAT.get(m.group(1), ""))
    m = re.match(r"StringFormat\(", e)
    if m:
        a, _ = split_args(e, e.index("("))
        base = text_len(a[0]) if a else None
        if base is None:
            return None
        fmt = a[0]
        mm = re.fullmatch(r'"((?:[^"\\]|\\.)*)"', fmt.strip())
        f = mm.group(1) if mm else ""
        f = f.replace("%s", "x" * 10).replace("%.2f", "00000.00")
        f = f.replace("%.1f", "0000.0").replace("%d", "00000")
        f = re.sub(r"%[0-9.+-]*[dfs]", "00000", f)
        return len(f)
    #--- real lengths, not a guess: the fallback 4 reported the brand
    #--- mark as overrunning the title it sits beside, which it does not
    if e == "SSR_BRAND_MARK":
        return 2
    if e == "SSR_BUILD_SHORT":
        return 4
    return None


def eval_coord(expr, env):
    e = expr.strip()
    e = re.sub(r"\bSSR_[A-Z0-9_]+\b", lambda m: str(DEF.get(m.group(0), 0)), e)
    if not re.fullmatch(r"[0-9xywWmh_ +\-*/().]+", e):
        return None
    try:
        return int(eval(e, {"__builtins__": {}}, env))
    except Exception:
        return None


DRAWS = {
    "Label": (1, 2, 3, 5),     # x, y, text, size-arg index
    "Text": (2, 3, 4, 6),      # CSSRPanel::Text(slot, id, x, y, text, col, size)
    "Chip": (1, 2, 3, None),
}


def scan(path, frame_w):
    out = []
    code = open(path, encoding="utf-8").read()
    # which function each call sits in, so rows are only compared inside one
    funcs = [(m.start(), m.group(1)) for m in
             re.finditer(r"^\s{3}\w[\w ]*?\s+(\w+)\(", code, re.M)]

    def fn_at(pos):
        name = "?"
        for p, n in funcs:
            if p <= pos:
                name = n
            else:
                break
        return name

    for call, (ix, iy, it, isz) in DRAWS.items():
        pat = r"(?:m_w\.|w\.|\b)" + call + r"\s*\("
        for m in re.finditer(pat, code):
            a, _ = split_args(code, m.end() - 1)
            if len(a) <= max(ix, iy, it):
                continue
            env = {"x": 0, "y": 0, "w": frame_w, "W": frame_w,
                   "m_x": 0, "m_y": 0}
            X = eval_coord(a[ix], env)
            Y = eval_coord(a[iy], env)
            n = text_len(a[it])
            if X is None or Y is None or n is None:
                continue
            pt = PT_BODY
            if isz is not None and len(a) > isz:
                s = a[isz].strip()
                if "SMALL" in s:
                    pt = PT_SMALL
                elif "CLOCK" in s:
                    pt = PT_CLOCK
                elif "TITLE" in s:
                    pt = DEF.get("SSR_FS_TITLE", 10)
            mono = any("MONO" in x for x in a)
            out.append(dict(fn=fn_at(m.start()), x=X, y=Y,
                            w=px(n, pt, mono), h=int(pt * 5 / 3),
                            txt=a[it][:46],
                            line=code[:m.start()].count("\n") + 1))
    return out


def report(path, frame_w, label):
    items = scan(path, frame_w)
    conf, same = [], []
    for i in range(len(items)):
        for j in range(i + 1, len(items)):
            A, B = items[i], items[j]
            if A["fn"] != B["fn"]:
                continue
            if not (A["y"] < B["y"] + B["h"] and B["y"] < A["y"] + A["h"]):
                continue
            ox = min(A["x"] + A["w"], B["x"] + B["w"]) - max(A["x"], B["x"])
            if ox <= 0:
                continue
            rec = (A["fn"], A["line"], B["line"], A["txt"], B["txt"], ox)
            # a start landing INSIDE the other's run is not a near miss
            if B["x"] > A["x"] and B["x"] < A["x"] + A["w"] - 2:
                conf.append(rec)
            else:
                same.append(rec)
    print("\n=== %s  (%d resolvable draws) ===" % (label, len(items)))
    if conf:
        print("  CONFIRMED - one string starts inside another's run:")
        for fn, l1, l2, t1, t2, ox in sorted(set(conf))[:40]:
            print("    %-22s L%-5d %-30s  <-- L%-5d %-30s  %d px"
                  % (fn, l1, t1, l2, t2, ox))
    else:
        print("  CONFIRMED: none")
    print("  same-row pairs needing eyes: %d" % len(set(same)))


if __name__ == "__main__":
    PW = DEF.get("SSR_PANEL_W", 420)
    SHEET = PW - 2 * DEF.get("SSR_PAD", 8) - DEF.get("SSR_SIDE_W", 104) \
        - DEF.get("SSR_GAP", 5)
    for f, w, lbl in (("SSR_Panel.mqh", SHEET, "panel sheets (w = sheet)"),
                      ("SSR_DataCenter.mqh", PW, "data centre"),
                      ("SSR_Splash.mqh", PW, "nameplate"),
                      ("SSR_SetupPanel.mqh", 304, "setup panel"),
                      ("SSR_SessionDialog.mqh", 420, "session dialog"),
                      ("SSR_RangeDialog.mqh", 420, "range dialog"),
                      ("SSR_ReviewCard.mqh", 420, "review card"),
                      ("SSR_RevealCard.mqh", 420, "reveal card"),
                      ("SSR_KeyCard.mqh", 420, "key card"),
                      ("SSR_Palette.mqh", 420, "command palette")):
        p = os.path.join(UI, f)
        if os.path.exists(p):
            report(p, w, lbl)

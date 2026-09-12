# -*- coding: utf-8 -*-
"""Ten panel faces, drawn with ONLY what MQL5 can draw.

Every mockup here is flat fills, 1px borders and single-line text - an
OBJ_RECTANGLE_LABEL, an OBJ_BUTTON, an OBJ_LABEL. No rounded corners, no
gradients, no shadows, no alpha, no wrapping: if it is on this page, the
panel can draw it, and if the panel cannot draw it, it is not on this page.
"""
import json, html, sys
sys.path.insert(0, "/tmp/claude-0/faces")
P = json.load(open("/tmp/claude-0/faces/solved.json"))

TAHOMA = "'Tahoma','DejaVu Sans',sans-serif"
MONO   = "'Consolas','Liberation Mono','DejaVu Sans Mono',monospace"
COUR   = "'Courier New','Liberation Mono',monospace"
SERIF  = "'Georgia','Bitstream Charter',serif"
SEGOE  = "'Segoe UI','Liberation Sans',sans-serif"

#--- per-variant character: face font, structure flags, size
V = {
 "v1":  dict(font=TAHOMA, w=420, group="box",   deal="fill", tabs="tabs",
             note="The instrument, tuned. Boxed groups, filled keys, 8pt Tahoma.",
             fa="ابزارِ فعلی، تمیزشده. گروه‌های کادردار، دکمه‌های تو‌پر."),
 "v2":  dict(font=TAHOMA, w=420, group="rule",  deal="outline", tabs="tabs",
             numfont=SERIF,
             note="A printed trade blotter. Hairline rules instead of boxes, "
                  "Georgia for every number, outlined keys.",
             fa="برگهٔ چاپیِ معامله. خط‌های نازک به‌جای کادر، اعداد با Georgia."),
 "v3":  dict(font=MONO,   w=420, group="none",  deal="fill", tabs="fkeys",
             upper=True,
             note="Financial terminal. Black ground, amber type, Consolas "
                  "throughout, function-key tabs. The densest of the ten.",
             fa="ترمینال مالی. زمینهٔ سیاه، حروف کهربایی، متراکم‌ترین گزینه."),
 "v4":  dict(font=TAHOMA, w=420, h=392, group="swiss", deal="outline",
             tabs="tabs", airy=True,
             note="Swiss. No boxes anywhere - a rule and a small uppercase "
                  "label carry every group. One red, used four times.",
             fa="سوئیسی. بدون هیچ کادری؛ یک خط و یک برچسب کوچک. یک قرمز."),
 "v5":  dict(font=MONO,   w=420, group="tick",  deal="fill", tabs="tabs",
             note="Blueprint. Navy ground, corner ticks on every frame, "
                  "monospace - a technical drawing of a panel.",
             fa="نقشهٔ فنی. زمینهٔ سرمه‌ای، گوشه‌های علامت‌دار، فونت تک‌عرض."),
 "v6":  dict(font=TAHOMA, w=420, group="bevel", deal="fill", tabs="tabs",
             bevel=True,
             note="Bevelled. Uses MT5's OWN raised/sunken border types, so "
                  "the depth costs nothing: keys stand up, wells sink.",
             fa="برجسته. از حالت‌های برجسته/فرورفتهٔ خودِ متاتریدر استفاده می‌کند."),
 "v7":  dict(font=SEGOE,  w=440, h=368, group="box", deal="fill", tabs="tabs3",
             big=True,
             note="Daylight. Everything one step larger - 9pt body, 26px keys, "
                  "three tabs and an overflow. For a bright chart.",
             fa="روزانه. همه‌چیز یک پله بزرگ‌تر؛ برای نمودار روشن و چشم خسته."),
 "v8":  dict(font=TAHOMA, w=300, h=430, group="box", deal="fill", tabs="rail",
             note="A rail, not a dialog. 300px wide, lives down the left edge "
                  "of the chart. Tabs become a stacked rail.",
             fa="ریل به‌جای پنجره. عرض ۳۰۰، کنار چپ نمودار می‌ایستد."),
 "v9":  dict(font=COUR,   w=420, group="none",  deal="bracket", tabs="bracket",
             upper=True,
             note="Green screen. Phosphor on black, Courier, every control "
                  "in brackets. A commitment, not a compromise.",
             fa="صفحهٔ سبز. فسفری روی سیاه، فونت Courier، همه‌چیز داخل کروشه."),
 "v10": dict(font=SEGOE,  w=420, group="box", deal="fill", tabs="tabs",
             stripe=True,
             note="Signal. A 4px stripe down the left edge IS the state - "
                  "green running, amber paused, red stopped - and repeats "
                  "on every position row.",
             fa="نوار وضعیت. نوار ۴ پیکسلی کنار پنل، خودِ وضعیت است."),
}

def esc(s): return html.escape(s, quote=False)

def panel(k):
    p, v = P[k], V[k]
    w  = v["w"]
    num = v.get("numfont", v["font"])
    up  = v.get("upper", False)
    def U(s): return s.upper() if up else s
    big = v.get("big", False)
    fs  = 12 if big else 11          # body px (8pt Tahoma ~ 11px)
    out = []
    A = out.append

    st = ("--face:%s;--cap:%s;--well:%s;--edge:%s;--text:%s;--dim:%s;"
          "--faint:%s;--accent:%s;--buy:%s;--sell:%s;--run:%s;--btn:%s;"
          "--btnedge:%s;--dealtext:%s;--font:%s;--num:%s;--fs:%dpx;width:%dpx"
          % (p["face"], p["cap"], p["well"], p["edge"], p["text"], p["dim"],
             p["faint"], p["accent"], p["buy"], p["sell"], p["run"], p["btn"],
             p["btnedge"], p["dealtext"], v["font"], num, fs, w))
    cls = "panel " + k
    for f in ("bevel", "stripe", "airy", "big"):
        if v.get(f): cls += " is-" + f
    A('<div class="%s" style="%s" dir="ltr">' % (cls, st))
    if v.get("stripe"): A('<i class="statestripe"></i>')

    #--- CAPTION -----------------------------------------------------
    A('<div class="cap">')
    A('<span class="ttl">%s</span>' % U("SS Replay"))
    A('<span class="chip">%s</span>' % U("BLIND"))
    A('<span class="capb">')
    for b in ("K", "?", "[]", "_"):
        A('<b>%s</b>' % esc(b))
    A('<b class="x">X</b>')
    A('</span></div>')

    #--- CLOCK + PROGRESS --------------------------------------------
    A('<div class="clockrow">')
    A('<span class="clock">2024.03.14&nbsp;&nbsp;09:42:15</span>')
    A('<span class="pct">37%</span>')
    A('<div class="prog"><i style="width:37%"></i></div>')
    A('</div>')

    #--- TRANSPORT ---------------------------------------------------
    brk = (v["deal"] == "bracket")
    def key(txt, c=""):
        #--- BRACKETS ONLY WHERE THERE IS ROOM. "[ - ]" in an 18px key is
        #--- not a style, it is an overflow; the single-glyph keys keep
        #--- their glyph and the labelled ones get the brackets.
        t = "[ %s ]" % txt if (brk and len(txt) > 2) else txt
        return '<b class="k %s">%s</b>' % (c, esc(t))
    A('<div class="transport">')
    for t in ("|<", "<<", "<"):
        A(key(t, "nav"))
    A(key(U("Pause"), "play"))
    for t in (">", ">>"):
        A(key(t, "nav"))
    A(key(U("Reset"), "reset"))
    A('</div>')

    #--- SPEED -------------------------------------------------------
    A('<div class="speedrow">')
    A('<span class="lbl">%s</span>' % U("Speed"))
    A(key("-", "sm")); A('<span class="well spd">5x</span>'); A(key("+", "sm"))
    A('<div class="track">')
    for i in range(8):
        A('<i class="%s"></i>' % ("on" if i < 4 else ""))
    A('</div>')
    A('<span class="mean">1h in 12m</span>')
    A('</div>')

    #--- TABS --------------------------------------------------------
    tabs = [("Trade", True), ("Positions 2", False), ("Stats", False),
            ("Session", False)]
    mode = v["tabs"]
    if mode == "tabs":
        A('<div class="tabs">')
        for t, on in tabs:
            A('<b class="%s">%s</b>' % ("on" if on else "", U(t)))
        A('</div>')
    elif mode == "tabs3":
        A('<div class="tabs">')
        for t, on in tabs[:3]:
            A('<b class="%s">%s</b>' % ("on" if on else "", t))
        A('<b class="more">&hellip;</b></div>')
    elif mode == "fkeys":
        A('<div class="tabs fkeys">')
        for i, (t, on) in enumerate(tabs, 1):
            A('<b class="%s"><s>F%d</s>%s</b>' % ("on" if on else "", i, U(t)))
        A('</div>')
    elif mode == "bracket":
        A('<div class="tabs bracket">')
        for t, on in tabs:
            A('<b class="%s">%s</b>' % ("on" if on else "",
                                        ("[%s]" % U(t)) if on else U(t)))
        A('</div>')
    elif mode == "rail":
        pass   # drawn beside the sheet below

    #--- SHEET -------------------------------------------------------
    gs = v["group"]
    def grp(title, inner, cls=""):
        t = U(title)
        if gs == "box" or gs == "bevel":
            return ('<div class="grp %s"><span class="lg">%s</span>%s</div>'
                    % (cls, esc(t), inner))
        if gs == "tick":
            return ('<div class="grp tick %s"><span class="lg">%s</span>'
                    '<u class="c1"></u><u class="c2"></u><u class="c3"></u>'
                    '<u class="c4"></u>%s</div>' % (cls, esc(t), inner))
        if gs == "rule":
            return ('<div class="grp rule %s"><span class="lg">%s</span>%s</div>'
                    % (cls, esc(t), inner))
        if gs == "swiss":
            return ('<div class="grp swiss %s"><span class="lg">%s</span>%s</div>'
                    % (cls, esc(t), inner))
        return ('<div class="grp none %s"><span class="lg">%s</span>%s</div>'
                % (cls, esc(t), inner))

    def row(a, b, c="", cc=""):
        return ('<div class="row"><span class="a">%s</span>'
                '<span class="b %s">%s</span><span class="c">%s</span></div>'
                % (esc(U(a)), cc, esc(b), esc(U(c))))

    A('<div class="sheetwrap">')
    if mode == "rail":
        A('<div class="rail">')
        for t, on in [("TRD", True), ("POS", False), ("STA", False),
                      ("SES", False)]:
            A('<b class="%s">%s</b>' % ("on" if on else "", t))
        A('</div>')
    A('<div class="sheet">')
    A(grp("Risk", row("1.0%", "= $487", "0.42 lot")))
    A('<div class="setup"><span class="lbl">%s</span>'
      '<span class="well ed">breakout retest</span></div>' % U("Setup"))
    A(grp("Stop & target",
          row("Stop", "38 412.0", "-52 pts", "neg")
          + row("Target", "38 604.0", "+140 pts", "pos")
          + row("R:R", "1 : 2.7", "")
          + '<div class="takebtn">%s</div>'
            % key(U("Take the trade   (Tab)"), "take")))
    A('<div class="deals">%s%s</div>'
      % (key(U("BUY"), "buy"), key(U("SELL"), "sell")))
    A('<div class="spread">%s</div>' % U("spread 1.4"))
    A('</div></div>')

    #--- STATUS ------------------------------------------------------
    A('<div class="status"><span class="run">%s</span>'
      '<span class="sdim">2 positions</span>'
      '<span class="pos">P&amp;L +$214</span></div>' % U("Running"))
    A('</div>')
    return "\n".join(out)

#===================================================================
# The mockup stylesheet. Flat fills, 1px borders, single-line text.
# Nothing here that an OBJ_RECTANGLE_LABEL / OBJ_BUTTON / OBJ_LABEL
# cannot produce - no radius, no gradient, no shadow, no alpha.
#===================================================================
CSS = r"""
.panel{position:relative;background:var(--face);border:1px solid var(--edge);
 font-family:var(--font);font-size:var(--fs);color:var(--text);
 line-height:1;user-select:none;font-variant-numeric:tabular-nums}
.panel *{box-sizing:border-box}
.panel b,.panel span,.panel i,.panel u,.panel s{font-style:normal;font-weight:400}

/* caption -------------------------------------------------------- */
.cap{height:22px;background:var(--cap);border-bottom:1px solid var(--edge);
 display:flex;align-items:center;gap:6px;padding:0 4px 0 7px}
.ttl{font-weight:700;font-size:calc(var(--fs) + 1px);letter-spacing:.01em}
.chip{font-size:9px;color:var(--accent);border:1px solid var(--accent);
 padding:1px 4px;line-height:1}
.capb{margin-left:auto;display:flex;gap:2px}
.capb b{width:18px;height:15px;background:var(--btn);
 border:1px solid var(--btnedge);color:var(--text);font-size:10px;
 display:flex;align-items:center;justify-content:center}
.capb b.x{color:var(--sell)}

/* clock + progress ----------------------------------------------- */
.clockrow{height:32px;padding:5px 8px 0;position:relative}
.clock{font-family:var(--num);font-size:17px;color:var(--text);letter-spacing:.01em}
.pct{position:absolute;right:8px;top:8px;font-size:11px;color:var(--dim)}
.prog{position:absolute;left:8px;right:8px;top:26px;height:6px;
 background:var(--well);border:1px solid var(--edge)}
.prog i{display:block;height:100%;background:var(--accent)}

/* rows of keys ---------------------------------------------------- */
.k{display:flex;align-items:center;justify-content:center;height:22px;
 background:var(--btn);border:1px solid var(--btnedge);color:var(--text);
 font-size:var(--fs)}
.transport{height:27px;display:flex;gap:3px;padding:0 8px;align-items:center}
.k.nav{width:30px}
.k.play{flex:1;font-weight:700}
.k.reset{width:54px;color:var(--dim)}

.speedrow{height:21px;display:flex;gap:4px;padding:0 8px;align-items:center}
.speedrow .lbl{font-size:9px;color:var(--dim);width:34px}
.k.sm{width:18px;height:19px;font-size:11px}
.well{background:var(--well);border:1px solid var(--edge)}
.spd{width:46px;height:19px;display:flex;align-items:center;
 justify-content:center;font-family:var(--num);font-size:11px}
.track{flex:1;height:14px;display:flex;gap:1px;align-items:stretch}
.track i{flex:1;background:var(--well);border:1px solid var(--edge)}
.track i.on{background:var(--accent);border-color:var(--accent)}
.mean{font-size:9px;color:var(--faint);width:62px;text-align:right}

/* tabs ------------------------------------------------------------ */
.tabs{height:21px;display:flex;gap:2px;padding:0 8px;align-items:flex-end;
 border-bottom:1px solid var(--edge)}
.tabs b{flex:1;height:19px;display:flex;align-items:center;
 justify-content:center;background:var(--cap);border:1px solid var(--edge);
 border-bottom:none;color:var(--dim);font-size:10px}
.tabs b.on{background:var(--face);color:var(--text);font-weight:700}
.tabs b.more{flex:0 0 24px}

/* the sheet ------------------------------------------------------- */
.sheetwrap{display:flex}
.sheet{flex:1;padding:8px 8px 9px}
.grp{position:relative;border:1px solid var(--edge);padding:8px 7px 4px;
 margin-bottom:4px}
.grp .lg{position:absolute;top:-6px;left:6px;background:var(--face);
 padding:0 3px;font-size:9px;color:var(--dim)}
.row{display:flex;align-items:center;height:15px;font-size:var(--fs)}
.row .a{color:var(--dim);width:54px;flex:none}
.row .b{flex:1;font-family:var(--num);color:var(--text)}
.row .c{color:var(--faint);text-align:right;font-family:var(--num)}
.row .b.pos{color:var(--buy)}
.row .b.neg{color:var(--sell)}
.setup{display:flex;align-items:center;gap:6px;margin-bottom:5px}
.setup .lbl{font-size:9px;color:var(--dim);width:34px}
.ed{flex:1;height:18px;display:flex;align-items:center;padding:0 5px;
 font-size:11px;color:var(--text)}
.takebtn{margin-top:5px}
.k.take{height:21px;font-size:10px;color:var(--accent);
 border-color:var(--accent)}
.deals{display:flex;gap:5px;margin-top:5px}
.k.buy,.k.sell{flex:1;height:24px;font-weight:700;color:var(--dealtext);
 font-size:calc(var(--fs) + 1px);letter-spacing:.04em}
.k.buy{background:var(--buy);border-color:var(--buy)}
.k.sell{background:var(--sell);border-color:var(--sell)}
.spread{margin-top:4px;font-size:9px;color:var(--faint)}

/* status ---------------------------------------------------------- */
.status{height:18px;background:var(--cap);border-top:1px solid var(--edge);
 display:flex;align-items:center;gap:12px;padding:0 8px;font-size:10px}
.status .run{color:var(--run);font-weight:700}
.status .sdim{color:var(--dim)}
.status .pos{color:var(--buy);margin-left:auto;font-family:var(--num)}

/* ================= variant structure ============================= */
/* 02 paper: rules, not boxes */
.grp.rule{border:none;padding:0 0 6px;margin-bottom:8px;
 border-top:1px solid var(--edge)}
.grp.rule .lg{position:static;display:block;background:none;padding:2px 0 4px;
 letter-spacing:.06em;text-transform:uppercase}
.v2 .k{background:var(--face)}
.v2 .k.buy,.v2 .k.sell{background:var(--face);color:var(--buy);
 border:1px solid var(--buy)}
.v2 .k.sell{color:var(--sell);border-color:var(--sell)}
.v2 .tabs b.on{border-bottom:2px solid var(--accent);height:20px}

/* 03 bloomberg + 09 green: no group frames at all */
.grp.none{border:none;padding:0 0 4px;margin-bottom:6px}
.grp.none .lg{position:static;display:block;background:none;padding:0 0 3px;
 letter-spacing:.1em}
.tabs.fkeys{border-bottom:none;gap:0}
.tabs.fkeys b{background:none;border:none;justify-content:flex-start;
 padding-left:6px;font-size:10px}
.tabs.fkeys b.on{color:var(--accent)}
.tabs.fkeys s{text-decoration:none;color:var(--faint);margin-right:5px}
.v3 .prog i,.v3 .track i.on{background:var(--text);border-color:var(--text)}
.v3 .clock{color:var(--accent)}
.v3 .k{background:#000}

/* 04 swiss: a rule and a label, one red */
.grp.swiss{border:none;padding:0;margin-bottom:11px}
.grp.swiss .lg{position:static;display:block;background:none;padding:0 0 4px;
 font-size:9px;letter-spacing:.12em;text-transform:uppercase;color:var(--text);
 border-bottom:1px solid var(--text);margin-bottom:6px}
.is-airy .row{height:19px}
.is-airy .sheet{padding:12px 10px 12px}
.v4 .k{background:#fff;border-color:#000}
.v4 .k.play{background:#000;color:#fff;border-color:#000}
.v4 .k.buy{background:#000;color:#fff;border-color:#000}
.v4 .k.sell{background:#fff;color:var(--sell);border-color:var(--sell);
 font-weight:700}
.v4 .tabs{border-bottom:1px solid #000}
.v4 .tabs b{background:#fff;border:none;color:var(--faint)}
.v4 .tabs b.on{color:#000;border-bottom:3px solid var(--accent)}
.v4 .cap{border-bottom:1px solid #000}
.v4 .prog{border-color:#000}
.v4 .prog i{background:var(--accent)}
.v4 .track i.on{background:#000;border-color:#000}

/* 05 blueprint: corner ticks */
.grp.tick u{position:absolute;width:5px;height:5px;border:0 solid var(--accent)}
.grp.tick u.c1{top:-1px;left:-1px;border-top-width:1px;border-left-width:1px}
.grp.tick u.c2{top:-1px;right:-1px;border-top-width:1px;border-right-width:1px}
.grp.tick u.c3{bottom:-1px;left:-1px;border-bottom-width:1px;border-left-width:1px}
.grp.tick u.c4{bottom:-1px;right:-1px;border-bottom-width:1px;border-right-width:1px}

/* 06 bevel: MT5's own raised / sunken border types */
.is-bevel .k,.is-bevel .capb b{border-width:1px;
 border-color:#6E6E71 #232325 #232325 #6E6E71}
.is-bevel .well,.is-bevel .prog,.is-bevel .grp,.is-bevel .track i{
 border-color:#232325 #6E6E71 #6E6E71 #232325}
.is-bevel .tabs b.on{border-color:#6E6E71 #232325 var(--face) #6E6E71}

/* 07 daylight: one step up */
.is-big .k{height:26px}
.is-big .k.buy,.is-big .k.sell{height:28px}
.is-big .row{height:18px}
.is-big .transport{height:31px}

.is-big .cap{height:24px}

/* 08 rail */
.v8 .row .a{width:46px}
.rail{width:36px;flex:none;border-right:1px solid var(--edge);
 background:var(--cap);padding-top:8px;display:flex;flex-direction:column;
 gap:3px;align-items:center}
.rail b{width:30px;height:24px;display:flex;align-items:center;
 justify-content:center;font-size:9px;letter-spacing:.06em;color:var(--dim);
 border:1px solid transparent}
.rail b.on{color:var(--text);background:var(--face);
 border-color:var(--edge);border-right-color:var(--face)}
.v8 .k.nav{width:24px}
.v8 .k.reset{width:44px;font-size:10px}
.v8 .mean{display:none}
.v8 .row .a{width:46px}

/* 09 green screen: brackets, no fills */
.v9 .k{background:none;border:none;color:var(--text);height:20px}
.v9 .k.play{color:var(--accent);font-weight:700}
.v9 .k.buy,.v9 .k.sell{background:none;border:none;color:var(--text)}
.v9 .well,.v9 .prog,.v9 .track i{background:none;border:1px solid var(--edge)}
.v9 .prog i{background:var(--text)}
.v9 .track i.on{background:var(--text)}
.v9 .tabs.bracket{border-bottom:1px solid var(--edge);gap:0}
.v9 .tabs.bracket b{background:none;border:none;color:var(--dim);
 justify-content:flex-start;padding-left:8px}
.v9 .tabs.bracket b.on{color:var(--text)}
.v9 .capb b{background:none;border:1px solid var(--edge)}
.v9 .k.nav{width:26px}
.v9 .k.play{font-size:10px}
.v9 .k.reset{width:62px;font-size:10px}
.v9 .k.take{border:none;color:var(--accent)}
.v9 .k.buy,.v9 .k.sell{letter-spacing:0}
.v9 .status{background:none;border-top:1px solid var(--edge)}

/* 10 signal stripe */
.statestripe{position:absolute;left:0;top:0;bottom:0;width:4px;
 background:var(--run)}
.is-stripe .cap,.is-stripe .clockrow,.is-stripe .transport,
.is-stripe .speedrow,.is-stripe .tabs,.is-stripe .sheetwrap,
.is-stripe .status{margin-left:4px}
.v10 .grp{border-left:3px solid var(--accent)}
.v10 .tabs b.on{border-top:2px solid var(--accent)}
"""

ORDER = ["v1","v2","v3","v4","v5","v6","v7","v8","v9","v10"]
COST = {"v1":("palette only","فقط پالت"),
        "v2":("palette + group rendering + one font","پالت + نحوهٔ کشیدن گروه‌ها + یک فونت"),
        "v3":("palette + fonts + tab row","پالت + فونت + ردیف تب‌ها"),
        "v4":("palette + group rendering + spacing","پالت + گروه‌ها + فاصله‌گذاری"),
        "v5":("palette + fonts + 4 rects per group","پالت + فونت + ۴ مستطیل برای هر گروه"),
        "v6":("palette + one border-type property","پالت + یک ویژگی نوع حاشیه"),
        "v7":("palette + metrics (sizes, heights)","پالت + اندازه‌ها و ارتفاع‌ها"),
        "v8":("layout rework: rail, width, no tabs","بازنویسی چیدمان: ریل، عرض، بدون تب"),
        "v9":("palette + fonts + flat keys","پالت + فونت + دکمه‌های بدون پُرشدگی"),
        "v10":("palette + one stripe rect per row","پالت + یک نوار برای هر ردیف")}

def worst(k):
    import importlib, palettes
    importlib.reload(palettes)
    from solve import pairs_for   # noqa
    return None

#--- measured in solve.py and carried here so the page cannot claim a
#--- number nothing computed
WORST = json.load(open("/tmp/claude-0/faces/worst.json"))

def spec(k):
    v, p = V[k], P[k]
    h = HEIGHT[k]
    font = {TAHOMA:"Tahoma", MONO:"Consolas", COUR:"Courier New",
            SEGOE:"Segoe UI"}[v["font"]]
    return "%d x %d px &middot; %s &middot; %s" % (v["w"], h, font,
                                                  WORST[k])

#--- MEASURED off the rendered panel, not added up. The arithmetic
#--- version was wrong by twelve pixels and the sheet overflowed
#--- into the status bar, which is exactly how this product's own
#--- frame got overrun in v69.
HEIGHT = {k: v[1] for k, v in json.load(
    open('/tmp/claude-0/faces/sizes.json')).items()}
WIDTH  = {k: v[0] for k, v in json.load(
    open('/tmp/claude-0/faces/sizes.json')).items()}

SHOT_BG = "#6E7377"

def write_shots(outdir):
    import os
    os.makedirs(outdir, exist_ok=True)
    for k in ORDER:
        doc = ("<!doctype html><meta charset='utf-8'><style>"
               "html,body{margin:0;background:%s}"
               "body{padding:24px;display:inline-block}%s</style>%s"
               % (SHOT_BG, CSS, panel(k)))
        open(os.path.join(outdir, "shot_%s.html" % k), "w",
             encoding="utf-8").write(doc)
    #--- and one contact sheet, five across
    cells = "".join(
        "<figure><figcaption>%02d &nbsp; %s</figcaption>%s</figure>"
        % (i + 1, P[k]["name"], panel(k)) for i, k in enumerate(ORDER))
    doc = ("<!doctype html><meta charset='utf-8'><style>"
           "html,body{margin:0;background:%s}"
           "body{padding:28px;display:grid;grid-template-columns:repeat(5,max-content);"
           "gap:34px 30px;align-items:start;width:max-content}"
           "figure{margin:0}"
           "figcaption{font:600 13px/1.4 'Liberation Sans',sans-serif;"
           "color:#fff;padding-bottom:8px;letter-spacing:.02em}%s</style>%s"
           % (SHOT_BG, CSS, cells))
    open(os.path.join(outdir, "contact.html"), "w", encoding="utf-8").write(doc)

PAGE = u"""<title>Ten Faces of SS Replay</title>
<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
<link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=Archivo:wght@500;700&family=IBM+Plex+Mono:wght@400;500&family=Vazirmatn:wght@400;500;700&display=swap">
<style>
:root{
 --paper:#EAEDEF; --card:#FFFFFF; --ink:#14181B; --ink2:#4A5157;
 --ink3:#6E767D; --rule:#D2D8DD; --accent:#1F6167; --accentink:#FFFFFF;
 --chip:#E2E7EA; --zoom:1;
 --fa:"Vazirmatn","Noto Sans Arabic",system-ui,sans-serif;
 --dis:"Archivo","Liberation Sans",sans-serif;
 --mono:"IBM Plex Mono","Liberation Mono",monospace;
}
:root:not([data-theme="light"]){@media (prefers-color-scheme:dark){
 --paper:#0E1113; --card:#171B1E; --ink:#E7EBED; --ink2:#AAB3B9;
 --ink3:#838D94; --rule:#2A3034; --accent:#68B3B9; --accentink:#0E1113;
 --chip:#232A2E;}}
:root[data-theme="dark"]{
 --paper:#0E1113; --card:#171B1E; --ink:#E7EBED; --ink2:#AAB3B9;
 --ink3:#838D94; --rule:#2A3034; --accent:#68B3B9; --accentink:#0E1113;
 --chip:#232A2E;}

*{box-sizing:border-box}
body{margin:0;background:var(--paper);color:var(--ink);font-family:var(--fa);
 font-size:15px;line-height:1.75;-webkit-font-smoothing:antialiased}
.wrap{max-width:1220px;margin:0 auto;padding-inline:20px;padding-block:0}

header{padding-block:64px 34px;border-bottom:1px solid var(--rule)}
.eyebrow{font-family:var(--mono);font-size:11px;letter-spacing:.18em;
 text-transform:uppercase;color:var(--accent);margin:0 0 14px}
h1{font-family:var(--dis);font-weight:700;font-size:clamp(30px,5.2vw,50px);
 line-height:1.15;margin:0 0 16px;text-wrap:balance;letter-spacing:-.01em}
.lede{margin:0;max-width:62ch;color:var(--ink2);font-size:16.5px}
.lede b{color:var(--ink);font-weight:500}

.rules{display:grid;grid-template-columns:repeat(auto-fit,minmax(210px,1fr));
 gap:1px;background:var(--rule);border:1px solid var(--rule);margin-block:30px 0}
.rules div{background:var(--card);padding:15px 17px}
.rules dt{font-family:var(--mono);font-size:10.5px;letter-spacing:.12em;
 text-transform:uppercase;color:var(--ink3);margin:0 0 5px}
.rules dd{margin:0;font-size:14px;color:var(--ink2)}
.rules dd b{color:var(--ink);font-weight:500}

.bar{position:sticky;top:0;z-index:5;background:var(--paper);
 border-bottom:1px solid var(--rule);padding-block:11px;
 display:flex;gap:12px;align-items:center;flex-wrap:wrap}
.bar span{font-family:var(--mono);font-size:11px;letter-spacing:.1em;
 text-transform:uppercase;color:var(--ink3)}
.zoom{display:flex;gap:0;border:1px solid var(--rule);background:var(--card)}
.zoom button{font:500 13px/1 var(--mono);padding:8px 15px;border:0;
 background:transparent;color:var(--ink2);cursor:pointer}
.zoom button+button{border-inline-start:1px solid var(--rule)}
.zoom button[aria-pressed="true"]{background:var(--accent);color:var(--accentink)}
.zoom button:focus-visible{outline:2px solid var(--accent);outline-offset:-2px}

.grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(480px,1fr));
 gap:1px;background:var(--rule);border:1px solid var(--rule);
 border-top:0;margin-bottom:70px}
.card{background:var(--card);padding:26px 24px 24px;display:flex;
 flex-direction:column;gap:16px}
.head{display:flex;align-items:baseline;gap:12px}
.num{font-family:var(--mono);font-size:12px;color:var(--accent);
 letter-spacing:.1em;flex:none}
h2{font-family:var(--dis);font-weight:500;font-size:21px;margin:0;
 letter-spacing:-.005em;direction:ltr}
.stage{overflow-x:auto;overflow-y:hidden;background:transparent;
 width:calc(var(--pw) * var(--zoom) * 1px);max-width:100%;
 height:calc(var(--ph) * var(--zoom) * 1px)}
.scaler{transform:scale(var(--zoom));transform-origin:top left;
 width:calc(var(--pw) * 1px)}
.fa{margin:0;color:var(--ink2);font-size:14.5px}
.en{margin:0;color:var(--ink3);font-size:12.5px;direction:ltr;text-align:left;
 font-family:var(--mono);line-height:1.65}
.spec{margin:auto 0 0;display:grid;grid-template-columns:1fr 1fr;gap:1px;
 background:var(--rule);border:1px solid var(--rule)}
.spec div{background:var(--card);padding:9px 11px}
.spec dt{font-family:var(--mono);font-size:9.5px;letter-spacing:.11em;
 text-transform:uppercase;color:var(--ink3);margin:0 0 3px}
.spec dd{margin:0;font-size:12.5px;color:var(--ink);line-height:1.5}
.spec dd.ltr{direction:ltr;text-align:right;font-family:var(--mono);font-size:11.5px}

footer{border-top:1px solid var(--rule);padding-block:28px 66px;
 color:var(--ink3);font-size:13.5px;max-width:70ch}
@media (max-width:520px){header{padding-block:42px 26px}.card{padding:20px 16px}}
%s
</style>

<div class="wrap">
<header>
 <p class="eyebrow">SS Replay &middot; Panel Study</p>
 <h1>ده چهره برای یک ابزار</h1>
 <p class="lede">هر ده طرح، همین پنل است با همان محتوای واقعی — ساعت، نوار پیشرفت، دکمه‌های حرکت، تب‌ها و برگهٔ معامله. <b>هیچ‌کدام عکس تزیینی نیست</b>: هر دهتا فقط با چیزهایی کشیده شده‌اند که MQL5 واقعاً می‌تواند بکشد — مستطیل، خط یک‌پیکسلی، و متن تک‌خطی.</p>
 <dl class="rules">
  <div><dt>Drawn with</dt><dd><b>فقط مستطیل، حاشیهٔ ۱ پیکسلی و متن</b><br>بدون گوشهٔ گرد، سایه، گرادیان یا شفافیت — چون MQL5 هیچ‌کدام را ندارد</dd></div>
  <div><dt>Contrast</dt><dd><b>هر ده پالت، استاندارد WCAG AA</b><br>۱۸۶ جفت رنگ اندازه‌گیری شد؛ صفر مردودی</dd></div>
  <div><dt>Fonts</dt><dd><b>فقط فونت‌های خودِ ویندوز</b><br>Tahoma · Segoe UI · Consolas · Courier New · Georgia</dd></div>
  <div><dt>Content</dt><dd><b>هر ده، یک محتوا</b><br>تا مقایسه دربارهٔ طراحی باشد، نه دربارهٔ محتوا</dd></div>
 </dl>
</header>

<div class="bar">
 <span>Zoom</span>
 <div class="zoom" role="group" aria-label="zoom">
  <button data-z="1" aria-pressed="true">1&times;</button>
  <button data-z="1.5" aria-pressed="false">1.5&times;</button>
  <button data-z="2" aria-pressed="false">2&times;</button>
 </div>
</div>

<main class="grid">
%s
</main>

<footer>
 هر کدام را پسندیدید، شمارهاش را بگویید. هزینهٔ ساخت هر طرح زیر خودش نوشته شده: پالت سفید و تیره از v121 پشت یک سوییچ در SSR_Theme.mqh هستند، پس طرح‌هایی که «فقط پالت» هستند در یک بیلد سوار می‌شوند؛ آن‌ها که چیدمان را عوض می‌کنند بیشتر طول می‌کشند. هیچ‌کدام از این ده طرح حذف نمی‌شود — مثل تم تیره، هر کدام ساخته شود کنار بقیه می‌ماند.
</footer>
</div>

<script>
(function(){
 var r=document.documentElement, btns=[].slice.call(document.querySelectorAll('.zoom button'));
 function set(z,save){
  r.style.setProperty('--zoom',z);
  btns.forEach(function(b){b.setAttribute('aria-pressed', b.dataset.z===String(z)?'true':'false');});
  if(save){try{localStorage.setItem('ssr.faces.zoom',z);}catch(e){}}
 }
 btns.forEach(function(b){b.addEventListener('click',function(){set(b.dataset.z,true);});});
 try{var s=localStorage.getItem('ssr.faces.zoom'); if(s){set(s,false);}}catch(e){}
})();
</script>
"""

def card(i, k):
    v, p = V[k], P[k]
    font = {TAHOMA:"Tahoma", MONO:"Consolas", COUR:"Courier New",
            SEGOE:"Segoe UI"}[v["font"]]
    t, u = WORST[k].replace("worst contrast ", "").split(", ")
    return ("""<article class="card" style="--pw:%d;--ph:%d">
 <div class="head"><span class="num">%02d</span><h2>%s</h2></div>
 <div class="stage"><div class="scaler">%s</div></div>
 <p class="fa">%s</p>
 <p class="en">%s</p>
 <dl class="spec">
  <div><dt>Size</dt><dd class="ltr">%d &times; %d</dd></div>
  <div><dt>Font</dt><dd class="ltr">%s</dd></div>
  <div><dt>Contrast</dt><dd class="ltr">%s</dd></div>
  <div><dt>Build cost</dt><dd>%s</dd></div>
 </dl>
</article>""" % (WIDTH[k], HEIGHT[k], i, esc(p["name"]), panel(k),
                 v["fa"], esc(v["note"]), WIDTH[k], HEIGHT[k], font,
                 t.replace(" text", ""), COST[k][1]))

def write_artifact(path):
    cards = "\n".join(card(i + 1, k) for i, k in enumerate(ORDER))
    doc = PAGE.replace("%s\n</style>", CSS + "\n</style>", 1)
    doc = doc.replace("%s\n</main>", cards + "\n</main>", 1)
    open(path, "w", encoding="utf-8").write(doc)

if __name__ == "__main__":
    write_shots("/tmp/claude-0/faces/shots")
    write_artifact("/tmp/claude-0/faces/faces.html")
    print("built: 10 shot pages, 1 contact sheet, 1 artifact page")

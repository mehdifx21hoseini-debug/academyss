# -*- coding: utf-8 -*-
"""Ten variations OF design 08 - the compact rail.

One palette, one width family, one set of content. What moves is where
the hand goes: the transport, the speed control, the deal keys, and the
rail itself. Still nothing here that MQL5 cannot draw.
"""
import json, html, sys, os
sys.path.insert(0, "/tmp/claude-0/faces")
from build import CSS, TAHOMA, esc

P8 = json.load(open("/tmp/claude-0/faces/solved.json"))["v8"]

L = {
 "a01": dict(name="Baseline", w=300, rail="left",
   order="cap clock transport speed sheet status", speed="stepper",
   note="Design 08 exactly as you saw it. The reference the other nine "
        "are changes against.",
   fa="همان ۰۸ که دیدید. مبنای مقایسهٔ نه‌تای دیگر."),

 "b01": dict(name="Slider only", w=300, rail="left",
   order="cap clock transport speed sheet status", speed="slider",
   note="Design 08 with one change: the eight cells become a track, a "
        "fill and a thumb. Same row, same height, same everything else.",
   fa="۰۸ با یک تغییر: هشت خانه می‌شود شیار، پُرشدگی و دستگیره. همان ردیف، "
      "همان ارتفاع، بقیه دست‌نخورده."),

 "b02": dict(name="Slider + readout", w=300, rail="left",
   order="cap clock transport speed sheet status", speed="sliderread",
   note="The same slider, with the two numbers you asked for folded into "
        "the empty right-hand end of the row. Still no extra row, still "
        "the same panel height.",
   fa="همان اسلایدر، با دو عددی که خواستید — در فضای خالی سمت راست همان "
      "ردیف. بدون ردیف اضافه، بدون تغییر ارتفاع پنل."),

 "b03": dict(name="Slider + full readout", w=300, rail="left",
   order="cap clock transport speed sheet status", speed="sliderline",
   note="The slider with a full readout line under it: ticks per second, "
        "seconds per candle, and what the session costs in real time. "
        "One extra row - twelve pixels.",
   fa="اسلایدر با یک سطر کامل زیرش: تیک بر ثانیه، ثانیه بر کندل، و اینکه "
      "جلسه چقدر وقت واقعی می‌برد. یک ردیف اضافه — دوازده پیکسل."),

 "c01": dict(name="v124 as built", w=310, rail="left", actions=True,
   order="cap clock transport speed actions sheet status", speed="slider",
   note="What v124 draws.",
   fa="what v124 draws"),

 "a02": dict(name="Speed presets", w=300, rail="left",
   order="cap clock transport speed sheet status", speed="chips",
   note="The minus / value / plus / track becomes five chips: 1x 2x 5x "
        "10x 50x. One press instead of four, and the whole range is "
        "visible without dragging anything.",
   fa="منفی/عدد/مثبت/نوار جای خود را به پنج تراشه می‌دهد: ۱x تا ۵۰x. "
      "یک کلیک به‌جای چهار تا، و کل بازه پیداست."),

 "a03": dict(name="Speed on the rail", w=300, rail="left+speed",
   order="cap clock transport sheet status", speed="none",
   note="The speed track turns vertical and moves onto the rail under "
        "the tabs. A whole row comes back to the sheet.",
   fa="نوار سرعت عمودی می‌شود و زیر تب‌ها روی ریل می‌رود. یک ردیف کامل "
      "به برگه برمی‌گردد."),

 "a04": dict(name="Speed number-led", w=300, rail="left",
   order="cap clock transport speed sheet status", speed="big",
   note="Speed reads like the clock does: a large number between two "
        "wide bars, with the track and its meaning on their own line.",
   fa="سرعت مثل ساعت خوانده می‌شود: عددی بزرگ بین دو نوار پهن، و خط "
      "نوار و معنی‌اش در سطر خودشان."),

 "a05": dict(name="Transport on the rail", w=300, rail="transport",
   order="cap clock striptabs speed sheet status", speed="stepper",
   note="The rail carries the hand instead of the tabs: play, step, "
        "reset - stacked where the thumb rests. Tabs become a strip.",
   fa="ریل به‌جای تب‌ها، دست را حمل می‌کند: پخش، قدم، ریست — همان‌جا که "
      "انگشت می‌نشیند. تب‌ها نواری می‌شوند."),

 "a06": dict(name="Transport at the bottom", w=300, rail="left",
   order="cap clock sheet transport speed status", speed="stepper",
   note="The chart information sits at the top and everything you press "
        "sits at the bottom, next to the status line that answers it.",
   fa="اطلاعات بالا، هرچه فشار می‌دهید پایین — کنار نوار وضعیتی که "
      "جوابش را می‌دهد."),

 "a07": dict(name="Big play", w=300, rail="left",
   order="cap clock bigplay speed sheet status", speed="stepper",
   note="Play / pause gets the full width and 28 pixels of height. The "
        "six step and reset keys share one row under it.",
   fa="پخش/توقف کل عرض و ۲۸ پیکسل ارتفاع می‌گیرد. شش کلید قدم و ریست "
      "زیرش در یک ردیف."),

 "a08": dict(name="Deals first", w=300, rail="left",
   order="cap clock deals transport speed sheet status", speed="stepper",
   nodeals=True,
   note="BUY and SELL move directly under the clock - the two keys "
        "pressed fastest end up nearest the price.",
   fa="خرید و فروش می‌آیند زیر ساعت — دو کلیدی که سریع‌ترین فشار را "
      "می‌خورند، نزدیک‌ترین به قیمت."),

 "a09": dict(name="Dense sheet", w=300, rail="left",
   order="cap clock transport speed densesheet status", speed="stepper",
   note="No group frames at all: label and value in two columns. Costs "
        "nothing in information and gives back about fifty pixels.",
   fa="بدون هیچ کادر گروهی: برچسب و مقدار در دو ستون. هیچ اطلاعاتی کم "
      "نمی‌شود و حدود پنجاه پیکسل برمی‌گردد."),

 "a10": dict(name="Strip, no rail", w=270, rail="none",
   order="cap clock striptabs transport speed sheet status",
   speed="stepper",
   note="The rail goes away and the tabs become a strip under the clock. "
        "The narrowest of all: 270 px, the least chart covered.",
   fa="ریل حذف می‌شود و تب‌ها نواری زیر ساعت می‌شوند. باریک‌ترین حالت: "
      "۲۷۰ پیکسل، کمترین پوشش نمودار."),
}
ORDER8 = ["a01","a02","a03","a04","a05","a06","a07","a08","a09","a10"]
ORDERB = ["a01","b01","b02","b03"]

def panel8(k):
    v = L[k]; p = P8
    st = ("--face:%s;--cap:%s;--well:%s;--edge:%s;--text:%s;--dim:%s;"
          "--faint:%s;--accent:%s;--buy:%s;--sell:%s;--run:%s;--btn:%s;"
          "--btnedge:%s;--dealtext:%s;--font:%s;--num:%s;--fs:11px;width:%dpx"
          % (p["face"], p["cap"], p["well"], p["edge"], p["text"], p["dim"],
             p["faint"], p["accent"], p["buy"], p["sell"], p["run"], p["btn"],
             p["btnedge"], p["dealtext"], TAHOMA, TAHOMA, v["w"]))
    B = {}

    B["cap"] = ('<div class="cap"><span class="ttl">SS Replay</span>'
                '<span class="chip">BLIND</span><span class="capb">'
                '<b>_</b><b class="x">X</b>'
                '</span></div>')

    B["clock"] = ('<div class="clockrow">'
                  '<span class="clock">2024.03.14&nbsp;&nbsp;09:42:15</span>'
                  '<span class="pct">37%</span>'
                  '<div class="prog"><i style="width:37%"></i></div></div>')

    def key(t, c=""): return '<b class="k %s">%s</b>' % (c, esc(t))

    B["transport"] = ('<div class="transport">' +
        "".join(key(t, "nav") for t in ("|<", "<<", "<")) +
        key("Pause", "play") +
        "".join(key(t, "nav") for t in (">", ">>")) +
        key("Reset", "reset") + '</div>')

    B["bigplay"] = ('<div class="bigplay">' + key("Pause", "play wide") +
                    '</div><div class="steprow">' +
                    "".join(key(t, "nav") for t in ("|<","<<","<",">",">>")) +
                    key("Reset", "reset") + '</div>')

    B["deals"] = ('<div class="topdeals">' + key("BUY", "buy") +
                  key("SELL", "sell") + '</div>')

    #--- SPEED, four ways -------------------------------------------
    track = ('<div class="track">' +
             "".join('<i class="%s"></i>' % ("on" if i < 4 else "")
                     for i in range(8)) + '</div>')
    sp = v["speed"]
    if sp == "stepper":
        B["speed"] = ('<div class="speedrow"><span class="lbl">Speed</span>'
                      + key("-", "sm")
                      + '<span class="well spd">5x</span>' + key("+", "sm")
                      + track + '<span class="mean">1h in 12m</span></div>')
    elif sp == "chips":
        B["speed"] = ('<div class="speedrow chips">'
                      '<span class="lbl">Speed</span>'
                      + "".join('<b class="k chip%s">%s</b>'
                                % (" on" if s == "5x" else "", s)
                                for s in ("1x","2x","5x","10x","50x"))
                      + '</div>')
    elif sp == "big":
        B["speed"] = ('<div class="speedbig">' + key("-", "bar")
                      + '<span class="spdnum">5x</span>' + key("+", "bar")
                      + '</div><div class="speedtrack">' + track
                      + '<span class="mean">1h in 12m</span></div>')
    elif sp.startswith("slider"):
        #--- A TRACK, A FILL AND A THUMB. Three rectangles, any pixel
        #--- width, so it reads continuous instead of stepped - and it
        #--- is still clicked and dragged exactly the way the eight
        #--- cells were, because that handler already exists.
        sl = ('<div class="sl"><i class="fill" style="width:46%"></i>'
              '<i class="thumb" style="left:46%"></i></div>')
        head = ('<div class="speedrow slid"><span class="lbl">Speed</span>'
                + key("-", "sm") + '<span class="well spd">5x</span>'
                + key("+", "sm") + sl)
        if sp == "sliderread":
            B["speed"] = (head + '<span class="rd">12 t/s <s>&middot;</s> '
                                 '1.0 s</span></div>')
        elif sp == "sliderline":
            B["speed"] = (head + '</div><div class="rdline">'
                          '<span class="v">12</span><span class="u">ticks/s</span>'
                          '<s>&middot;</s>'
                          '<span class="v">1.0</span><span class="u">s per candle</span>'
                          '<span class="pl">1 h in 60 s</span></div>')
        else:
            B["speed"] = head + '</div>'
    else:
        B["speed"] = ""

    #--- TABS, three ways -------------------------------------------
    tabs = [("Trade", True), ("Positions 2", False), ("Stats", False),
            ("Session", False)]
    B["actions"] = ('<div class="acts">' + "".join(
        '<b class="k act">%s</b>' % a
        for a in ("SL/TP", "Saved", "Detail"))
        + '</div>')

    B["striptabs"] = ('<div class="striptabs">' +
        "".join('<b class="%s">%s</b>' % ("on" if on else "", t)
                for t, on in tabs) + '</div>')

    #--- THE SHEET ---------------------------------------------------
    def row(a, b, c="", cc=""):
        return ('<div class="row"><span class="a">%s</span>'
                '<span class="b %s">%s</span><span class="c">%s</span></div>'
                % (esc(a), cc, esc(b), esc(c)))

    def grp(t, inner):
        return ('<div class="grp"><span class="lg">%s</span>%s</div>'
                % (esc(t), inner))

    deals = "" if v.get("nodeals") else (
        '<div class="deals">' + key("BUY", "buy") + key("SELL", "sell")
        + '</div>')

    sheet_std = (
        grp("Risk", row("1.0%", "= $487", "0.42 lot"))
        + '<div class="setup"><span class="lbl">Setup</span>'
          '<span class="well ed">breakout retest</span></div>'
        + grp("Stop & target",
              row("Stop", "38 412.0", "-52 pts", "neg")
              + row("Target", "38 604.0", "+140 pts", "pos")
              + row("R:R", "1 : 2.7", "")
              + '<div class="takebtn">' + key("Take the trade  (Tab)", "take")
              + '</div>')
        + deals + '<div class="spread">spread 1.4</div>')

    sheet_dense = (
        '<div class="dense">'
        + '<span class="dl">Risk</span><span class="dv">1.0%  =  $487</span>'
        + '<span class="dl">Lot</span><span class="dv">0.42</span>'
        + '<span class="dl">Setup</span><span class="dv">breakout retest</span>'
        + '<span class="dl">Stop</span><span class="dv neg">38 412.0'
          '<s>-52 pts</s></span>'
        + '<span class="dl">Target</span><span class="dv pos">38 604.0'
          '<s>+140 pts</s></span>'
        + '<span class="dl">R:R</span><span class="dv">1 : 2.7</span>'
        + '</div><div class="takebtn">' + key("Take the trade  (Tab)", "take")
        + '</div>' + deals + '<div class="spread">spread 1.4</div>')

    rail = v["rail"]
    def wrap(inner):
        out = ['<div class="sheetwrap">']
        if rail == "left" or rail == "left+speed":
            out.append('<div class="rail">')
            tags = ([("Trade",1),("Pos 2",0),("Stats",0),("Sess",0)]
                    if v.get("actions") else
                    [("TRD",1),("POS",0),("STA",0),("SES",0)])
            for t, on in tags:
                out.append('<b class="%s">%s</b>' % ("on" if on else "", t))
            if rail == "left+speed":
                out.append('<div class="vtrack">' +
                    "".join('<i class="%s"></i>' % ("on" if i >= 4 else "")
                            for i in range(8)) +
                    '</div><span class="vspd">5x</span>')
            out.append('</div>')
        elif rail == "transport":
            out.append('<div class="rail trail">')
            for t, c in [("|<","nav"),("<","nav"),("||","play"),(">","nav"),
                         (">>","nav"),("R","reset")]:
                out.append('<b class="k %s">%s</b>' % (c, esc(t)))
            out.append('</div>')
        out.append('<div class="sheet">%s</div></div>' % inner)
        return "".join(out)

    B["sheet"]      = wrap(sheet_std)
    B["densesheet"] = wrap(sheet_dense)

    B["status"] = ('<div class="status"><span class="run">Running</span>'
                   '<span class="sdim">2 positions</span>'
                   '<span class="pos">P&amp;L +$214</span></div>')

    body = "".join(B[b] for b in v["order"].split() if B.get(b) is not None)
    return '<div class="panel %s" style="%s" dir="ltr">%s</div>' % (k, st, body)

CSS8 = r"""
/* the compact rail's own adjustments, shared by all ten */
.panel .k.nav{width:24px}
.panel .k.reset{width:44px;font-size:10px}
.panel .mean{display:none}
.panel .row .a{width:46px}
.rail{width:36px;flex:none;border-right:1px solid var(--edge);
 background:var(--cap);padding-top:8px;display:flex;flex-direction:column;
 gap:3px;align-items:center}
.rail b{width:30px;height:24px;display:flex;align-items:center;
 justify-content:center;font-size:9px;letter-spacing:.06em;color:var(--dim);
 border:1px solid transparent}
.rail b.on{color:var(--text);background:var(--face);border-color:var(--edge);
 border-right-color:var(--face)}

/* v124: the action strip and the wider rail */
.acts{display:flex;gap:3px;padding:2px 8px 0}
.k.act{flex:1;height:21px;font-size:10px;color:var(--dim)}
.c01 .rail{width:44px}
.c01 .rail b{width:44px;height:22px;font-size:10px;letter-spacing:.02em}
.c01 .sheetwrap{border-top:1px solid var(--edge);margin-top:5px}

/* the continuous slider */
.speedrow.slid{gap:4px}
.speedrow.slid .lbl{width:34px}
.sl{position:relative;flex:1;height:8px;background:var(--well);
 border:1px solid var(--edge)}
.sl .fill{position:absolute;left:0;top:0;bottom:0;background:var(--accent)}
.sl .thumb{position:absolute;top:-4px;width:5px;height:14px;margin-left:-2px;
 background:var(--text);border:1px solid var(--face)}
.speedrow .rd{flex:none;width:72px;text-align:right;font-size:9px;
 color:var(--faint);font-variant-numeric:tabular-nums}
.speedrow .rd s{text-decoration:none}
.rdline{display:flex;align-items:baseline;gap:4px;padding:5px 8px 0;
 font-size:9px}
.rdline .v{color:var(--text);font-size:11px;font-variant-numeric:tabular-nums}
.rdline .u{color:var(--dim)}
.rdline s{text-decoration:none;color:var(--faint)}
.rdline .pl{margin-left:auto;color:var(--faint)}

/* 02 - speed presets */
.speedrow.chips{gap:3px}
.speedrow.chips .lbl{width:34px}
.k.chip{flex:1;height:19px;font-size:10px;padding:0}
.k.chip.on{background:var(--accent);border-color:var(--accent);
 color:#1B1E23;font-weight:700}

/* 03 - speed on the rail */
.vtrack{margin-top:8px;width:20px;flex:1;display:flex;flex-direction:column;
 gap:1px;border:1px solid var(--edge);background:var(--well);padding:1px}
.vtrack i{flex:1;background:transparent}
.vtrack i.on{background:var(--accent)}
.vspd{font-size:10px;color:var(--text);padding:4px 0 7px;
 font-variant-numeric:tabular-nums}

/* 04 - speed number-led */
.speedbig{display:flex;gap:5px;padding:2px 8px 0;align-items:center}
.k.bar{flex:1;height:22px;font-size:13px}
.spdnum{width:74px;text-align:center;font-size:17px;color:var(--text);
 font-variant-numeric:tabular-nums}
.speedtrack{display:flex;gap:6px;align-items:center;padding:4px 8px 3px}
.speedtrack .track{flex:1}
.speedtrack .mean{display:block;font-size:9px;color:var(--faint);width:58px;
 text-align:right}

/* 05 - transport on the rail */
.rail.trail{width:42px;gap:4px;padding-top:9px}
.rail.trail .k{width:34px;height:24px;font-size:11px}
.rail.trail .k.play{height:32px;font-weight:700;color:var(--accent);
 border-color:var(--accent)}
.rail.trail .k.reset{width:34px;font-size:10px;color:var(--dim)}

/* strip tabs, used by 05 and 10 */
.striptabs{display:flex;gap:2px;padding:0 8px 5px;border-bottom:1px solid var(--edge)}
.striptabs b{flex:1;height:19px;display:flex;align-items:center;
 justify-content:center;background:var(--cap);border:1px solid var(--edge);
 color:var(--dim);font-size:9px}
.striptabs b.on{background:var(--accent);border-color:var(--accent);
 color:#1B1E23;font-weight:700}

/* 07 - big play */
.bigplay{padding:2px 8px 0}
.k.play.wide{width:100%;height:28px;font-size:13px;font-weight:700;
 color:var(--accent);border-color:var(--accent)}
.steprow{display:flex;gap:3px;padding:4px 8px 2px}
.steprow .k{flex:1;height:21px}

/* 08 - deals first */
.topdeals{display:flex;gap:5px;padding:3px 8px 2px}
.topdeals .k{flex:1;height:26px;font-weight:700;font-size:12px;
 letter-spacing:.04em;color:var(--dealtext)}
.topdeals .k.buy{background:var(--buy);border-color:var(--buy)}
.topdeals .k.sell{background:var(--sell);border-color:var(--sell)}

/* 09 - dense sheet */
.dense{display:grid;grid-template-columns:52px 1fr;row-gap:3px;
 align-items:baseline;padding-bottom:3px}
.dense .dl{font-size:9px;color:var(--dim);letter-spacing:.05em;
 text-transform:uppercase}
.dense .dv{font-size:11px;color:var(--text);display:flex;
 justify-content:space-between;font-variant-numeric:tabular-nums}
.dense .dv s{text-decoration:none;color:var(--faint);font-size:10px}
.dense .dv.pos{color:var(--buy)}
.dense .dv.neg{color:var(--sell)}
.a09 .takebtn{margin-top:4px}

/* 06 - transport at the bottom needs a rule above it */
.a06 .transport{border-top:1px solid var(--edge);padding-top:4px;height:30px}

/* 10 - no rail */
.a10 .k.nav{width:21px}
.a10 .k.reset{width:40px}
.a10 .row .a{width:44px}
"""

SHOT_BG = "#6E7377"

def write8(outdir):
    os.makedirs(outdir, exist_ok=True)
    for k in ORDER8:
        doc = ("<!doctype html><meta charset='utf-8'><style>"
               "html,body{margin:0;background:%s}body{padding:24px;"
               "display:inline-block}%s%s</style>%s"
               % (SHOT_BG, CSS, CSS8, panel8(k)))
        open(os.path.join(outdir, "s8_%s.html" % k), "w",
             encoding="utf-8").write(doc)
    cells = "".join(
        "<figure><figcaption>%s &nbsp; %s</figcaption>%s</figure>"
        % (k[1:], L[k]["name"], panel8(k)) for k in ORDER8)
    doc = ("<!doctype html><meta charset='utf-8'><style>"
           "html,body{margin:0;background:%s}body{padding:28px;display:grid;"
           "grid-template-columns:repeat(5,max-content);gap:34px 26px;"
           "align-items:start;width:max-content}figure{margin:0}"
           "figcaption{font:600 13px/1.4 'Liberation Sans',sans-serif;"
           "color:#fff;padding-bottom:8px;letter-spacing:.02em}%s%s</style>%s"
           % (SHOT_BG, CSS, CSS8, cells))
    open(os.path.join(outdir, "contact8.html"), "w",
         encoding="utf-8").write(doc)


MOVED = {
 "a01": ("-", "مبنا", "-"),
 "a02": ("Speed", "سرعت", "پالت ثابت؛ یک ردیف بازنویسی می‌شود"),
 "a03": ("Speed", "سرعت", "نوار عمودی روی ریل؛ یک ردیف حذف"),
 "a04": ("Speed", "سرعت", "دو ردیف به‌جای یکی"),
 "a05": ("Transport", "دکمه‌های حرکت", "ریل و ردیف تب جابه‌جا می‌شوند"),
 "a06": ("Transport", "دکمه‌های حرکت", "فقط ترتیب ردیف‌ها"),
 "a07": ("Transport", "دکمه‌های حرکت", "یک دکمهٔ تمام‌عرض + یک ردیف"),
 "a08": ("Deal keys", "دکمه‌های خرید/فروش", "فقط جابه‌جایی دو دکمه"),
 "a09": ("Sheet", "برگهٔ معامله", "حذف کادرهای گروه، شبکهٔ دو ستونه"),
 "a10": ("Rail", "ریل", "حذف ریل، نوار تب افقی، عرض ۲۷۰"),
}

PAGE8 = u"""<title>Compact Rail Variations</title>
<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
<link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=Archivo:wght@500;700&family=IBM+Plex+Mono:wght@400;500&family=Vazirmatn:wght@400;500;700&display=swap">
<style>
:root{--paper:#EAEDEF;--card:#FFFFFF;--ink:#14181B;--ink2:#4A5157;
 --ink3:#6E767D;--rule:#D2D8DD;--accent:#8A4A12;--accentink:#FFFFFF;
 --zoom:1;--fa:"Vazirmatn","Noto Sans Arabic",system-ui,sans-serif;
 --dis:"Archivo","Liberation Sans",sans-serif;
 --mono:"IBM Plex Mono","Liberation Mono",monospace}
:root:not([data-theme="light"]){@media (prefers-color-scheme:dark){
 --paper:#0E1113;--card:#171B1E;--ink:#E7EBED;--ink2:#AAB3B9;--ink3:#838D94;
 --rule:#2A3034;--accent:#E0863A;--accentink:#1B1E23}}
:root[data-theme="dark"]{--paper:#0E1113;--card:#171B1E;--ink:#E7EBED;
 --ink2:#AAB3B9;--ink3:#838D94;--rule:#2A3034;--accent:#E0863A;
 --accentink:#1B1E23}
*{box-sizing:border-box}
body{margin:0;background:var(--paper);color:var(--ink);font-family:var(--fa);
 font-size:15px;line-height:1.75}
.wrap{max-width:1220px;margin:0 auto;padding-inline:20px;padding-block:0}
header{padding-block:60px 32px;border-bottom:1px solid var(--rule)}
.eyebrow{font-family:var(--mono);font-size:11px;letter-spacing:.18em;
 text-transform:uppercase;color:var(--accent);margin:0 0 14px}
h1{font-family:var(--dis);font-weight:700;font-size:clamp(30px,5.2vw,50px);
 line-height:1.15;margin:0 0 16px;text-wrap:balance}
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
 border-bottom:1px solid var(--rule);padding-block:11px;display:flex;gap:12px;
 align-items:center;flex-wrap:wrap}
.bar span{font-family:var(--mono);font-size:11px;letter-spacing:.1em;
 text-transform:uppercase;color:var(--ink3)}
.zoom{display:flex;border:1px solid var(--rule);background:var(--card)}
.zoom button{font:500 13px/1 var(--mono);padding:8px 15px;border:0;
 background:transparent;color:var(--ink2);cursor:pointer}
.zoom button+button{border-inline-start:1px solid var(--rule)}
.zoom button[aria-pressed="true"]{background:var(--accent);color:var(--accentink)}
.zoom button:focus-visible{outline:2px solid var(--accent);outline-offset:-2px}
.grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(360px,1fr));
 gap:1px;background:var(--rule);border:1px solid var(--rule);border-top:0;
 margin-bottom:70px}
.card{background:var(--card);padding:26px 24px 24px;display:flex;
 flex-direction:column;gap:15px}
.head{display:flex;align-items:baseline;gap:12px}
.num{font-family:var(--mono);font-size:12px;color:var(--accent);
 letter-spacing:.1em;flex:none}
h2{font-family:var(--dis);font-weight:500;font-size:20px;margin:0;direction:ltr}
.stage{overflow-x:auto;overflow-y:hidden;
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
__CSS__
</style>
<div class="wrap">
<header>
 <p class="eyebrow">SS Replay &middot; Design 08 &middot; Variations</p>
 <h1>&#1583;&#1607; &#1581;&#1575;&#1604;&#1578; &#1575;&#1586; &#1585;&#1740;&#1604; &#1601;&#1588;&#1585;&#1583;&#1607;</h1>
 <p class="lede">&#1607;&#1605;&#1575;&#1606; &#1591;&#1585;&#1581; &#1670;&#1607;&#1575;&#1585;&#1548; &#1607;&#1605;&#1575;&#1606; &#1662;&#1575;&#1604;&#1578;&#1548; &#1607;&#1605;&#1575;&#1606; &#1605;&#1581;&#1578;&#1608;&#1575;. <b>&#1601;&#1602;&#1591; &#1580;&#1575;&#1740; &#1670;&#1740;&#1586;&#1607;&#1575; &#1593;&#1608;&#1590; &#1605;&#1740;&#8204;&#1588;&#1608;&#1583;</b> &#8212; &#1583;&#1705;&#1605;&#1607;&#1607;&#1575;&#1740; &#1581;&#1585;&#1705;&#1578;&#1548; &#1588;&#1705;&#1604; &#1705;&#1606;&#1578;&#1585;&#1604; &#1587;&#1585;&#1593;&#1578;&#1548; &#1580;&#1575;&#1740; &#1582;&#1585;&#1740;&#1583; &#1608; &#1601;&#1585;&#1608;&#1588;&#1548; &#1608; &#1582;&#1608;&#1583; &#1585;&#1740;&#1604;. &#1586;&#1740;&#1585; &#1607;&#1585; &#1705;&#1583;&#1575;&#1605;&#1548; &#1670;&#1740;&#1586;&#1740; &#1705;&#1607; &#1580;&#1575;&#1576;&#1607;&#8204;&#1580;&#1575; &#1588;&#1583;&#1607; &#1608; &#1575;&#1606;&#1583;&#1575;&#1586;&#1607;&#1654; &#1608;&#1575;&#1602;&#1593;&#1740; &#1662;&#1606;&#1604; &#1606;&#1608;&#1588;&#1578;&#1607; &#1575;&#1587;&#1578;.</p>
 <dl class="rules">
  <div><dt>Constant</dt><dd><b>&#1662;&#1575;&#1604;&#1578;&#1548; &#1605;&#1581;&#1578;&#1608;&#1575;&#1548; &#1601;&#1608;&#1606;&#1578;</b><br>&#1578;&#1575; &#1605;&#1602;&#1575;&#1740;&#1587;&#1607; &#1601;&#1602;&#1591; &#1583;&#1585;&#1576;&#1575;&#1585;&#1647; &#1670;&#1740;&#1583;&#1605;&#1575;&#1606; &#1576;&#1575;&#1588;&#1583;</dd></div>
  <div><dt>What moves</dt><dd><b>&#1587;&#1585;&#1593;&#1578; (&#1779;) &#1548; &#1581;&#1585;&#1705;&#1578; (&#1779;) &#1548; &#1582;&#1585;&#1740;&#1583;/&#1601;&#1585;&#1608;&#1588; &#1548; &#1576;&#1585;&#1711;&#1607; &#1548; &#1585;&#1740;&#1604;</b></dd></div>
  <div><dt>Size</dt><dd><b>&#1575;&#1586; &#1779;&#1776;&#1779;&#215;&#1778;&#1785;&#1776; &#1578;&#1575; &#1779;&#1776;&#1779;&#215;&#1779;&#1781;&#1778;</b><br>&#1705;&#1608;&#1670;&#1705;&#8204;&#1578;&#1585;&#1740;&#1606;&#8204;&#1588;&#1575;&#1606; &#1588;&#1605;&#1575;&#1585;&#1607;&#1654; &#1785; &#1575;&#1587;&#1578;</dd></div>
  <div><dt>Drawn with</dt><dd><b>&#1607;&#1605;&#1575;&#1606; &#1670;&#1607;&#1575;&#1585; &#1670;&#1740;&#1586;</b><br>&#1605;&#1587;&#1578;&#1591;&#1740;&#1604;&#1548; &#1581;&#1575;&#1588;&#1740;&#1607;&#1654; &#1740;&#1705;&#8204;&#1662;&#1740;&#1705;&#1587;&#1604;&#1740;&#1548; &#1605;&#1578;&#1606;&#1548; &#1583;&#1705;&#1605;&#1607;</dd></div>
 </dl>
</header>
<div class="bar"><span>Zoom</span><div class="zoom" role="group" aria-label="zoom">
 <button data-z="1" aria-pressed="true">1&times;</button>
 <button data-z="1.5" aria-pressed="false">1.5&times;</button>
 <button data-z="2" aria-pressed="false">2&times;</button></div></div>
<main class="grid">
__CARDS__
</main>
<footer>&#1588;&#1605;&#1575;&#1585;&#1607;&#1654; &#1607;&#1585; &#1705;&#1583;&#1575;&#1605; &#1585;&#1575; &#1576;&#1711;&#1608;&#1740;&#1740;&#1583; &#8212; &#1740;&#1575; &#1670;&#1606;&#1583; &#1578;&#1575; &#1585;&#1575; &#1578;&#1585;&#1705;&#1740;&#1576; &#1705;&#1606;&#1740;&#1583;&#1548; &#1605;&#1579;&#1604;&#1575;&#1611; &#1587;&#1585;&#1593;&#1578;&#1647; &#1779; &#1576;&#1575; &#1583;&#1705;&#1605;&#1607;&#8204;&#1607;&#1575;&#1740;&#1647; &#1783;. &#1607;&#1740;&#1670;&#8204;&#1705;&#1583;&#1575;&#1605;&#1588;&#1575;&#1606; &#1670;&#1740;&#1586;&#1740; &#1606;&#1605;&#1740;&#8204;&#1582;&#1608;&#1575;&#1607;&#1583; &#1705;&#1607; MQL5 &#1606;&#1578;&#1608;&#1575;&#1606;&#1583; &#1576;&#1705;&#1588;&#1583;.</footer>
</div>
<script>
(function(){var r=document.documentElement,
 b=[].slice.call(document.querySelectorAll('.zoom button'));
 function set(z,s){r.style.setProperty('--zoom',z);
  b.forEach(function(x){x.setAttribute('aria-pressed',x.dataset.z===String(z)?'true':'false');});
  if(s){try{localStorage.setItem('ssr.v8.zoom',z);}catch(e){}}}
 b.forEach(function(x){x.addEventListener('click',function(){set(x.dataset.z,true);});});
 try{var v=localStorage.getItem('ssr.v8.zoom');if(v){set(v,false);}}catch(e){}})();
</script>
"""

def card8(i, k):
    v = L[k]
    sz = json.load(open("/tmp/claude-0/faces/sizes8.json"))[k]
    mv = MOVED[k]
    return ("""<article class="card" style="--pw:%d;--ph:%d">
 <div class="head"><span class="num">%02d</span><h2>%s</h2></div>
 <div class="stage"><div class="scaler">%s</div></div>
 <p class="fa">%s</p>
 <p class="en">%s</p>
 <dl class="spec">
  <div><dt>Size</dt><dd class="ltr">%d &times; %d</dd></div>
  <div><dt>What moved</dt><dd>%s</dd></div>
  <div><dt>vs baseline</dt><dd class="ltr">%s</dd></div>
  <div><dt>Build cost</dt><dd>%s</dd></div>
 </dl>
</article>""" % (sz[0], sz[1], i, esc(v["name"]), panel8(k), v["fa"],
                 esc(v["note"]), sz[0], sz[1], mv[1],
                 ("baseline" if k == "a01" else
                  "%+d px high, %+d wide" % (sz[1] - 322, sz[0] - 302)),
                 mv[2]))

def write8_page(path):
    cards = "\n".join(card8(i + 1, k) for i, k in enumerate(ORDER8))
    doc = PAGE8.replace("__CSS__", CSS + CSS8).replace("__CARDS__", cards)
    open(path, "w", encoding="utf-8").write(doc)

if __name__ == "__main__":
    write8("/tmp/claude-0/faces/shots8")
    write8_page("/tmp/claude-0/faces/faces8.html")
    print("built 10 variant pages + contact sheet + study page")

# -*- coding: utf-8 -*-
"""The proposal: a two-state ticket on the compact rail.

The argument is in the README. The rules are the same as before - flat
fills, 1px borders, single-line text - with one addition that was
VERIFIED rather than assumed: the transport glyphs are WGL4 geometric
characters, which Tahoma carries on every Windows since 2000. Wingdings
was tried first and did not render at all under test, so it is not used.
"""
import json, sys, os
sys.path.insert(0, "/tmp/claude-0/faces")
from build import esc, TAHOMA

P = json.load(open("/tmp/claude-0/faces/solved.json"))["v8"]

#--- WGL4, present in Tahoma. Rendered and eyeballed before being used.
PLAY, PAUSE = "&#9658;", "&#9612;&#9612;"
BACK, FWD   = "&#9668;", "&#9658;"
BACK10, FWD10 = "&#9668;&#9668;", "&#9658;&#9658;"
HOME, END   = "|&#9668;", "&#9658;|"
UP, DOWN    = "&#9650;", "&#9660;"
DOT         = "&#9679;"

def tokens(w=300):
    return ("--face:%s;--cap:%s;--well:%s;--edge:%s;--text:%s;--dim:%s;"
            "--faint:%s;--accent:%s;--buy:%s;--sell:%s;--run:%s;--btn:%s;"
            "--btnedge:%s;--dealtext:%s;--font:%s;--fs:11px;width:%dpx"
            % (P["face"], P["cap"], P["well"], P["edge"], P["text"], P["dim"],
               P["faint"], P["accent"], P["buy"], P["sell"], P["run"],
               P["btn"], P["btnedge"], P["dealtext"], TAHOMA, w))

def K(t, c=""):   return '<b class="k %s">%s</b>' % (c, t)

def caption():
    return ('<div class="cap"><span class="ttl">SS Replay</span>'
            '<span class="capb"><b>_</b><b class="x">&#10005;</b></span></div>')

def head(price="38 498.5", up=True):
    #--- THE PRICE IS ON THE PANEL. A replay tool whose panel does not
    #--- show the price makes you look somewhere else for the one number
    #--- every decision is about.
    return ('<div class="head">'
            '<div class="hrow"><span class="day">FRI 14 MAR</span>'
            '<span class="sess">day 1 / 20</span></div>'
            '<div class="hrow big"><span class="clk">09:42:15</span>'
            '<span class="px %s">%s</span></div>'
            '<div class="scrub"><i style="width:37%%"></i></div></div>'
            % ("up" if up else "dn", price))

def transport():
    return ('<div class="tr">' + K(HOME, "g") + K(BACK10, "g") + K(BACK, "g")
            + K(PAUSE, "g play") + K(FWD, "g") + K(FWD10, "g")
            + K("&#9632;", "g stop") + '</div>')

def speed(pos=46, ticks="12", secs="1.0", plan="1 h in 60 s", detail="12"):
    """ONE SLIDER, CONTINUOUS, ZERO AT THE LEFT.

    Not eight cells. A track, a fill and a thumb - three rectangles, any
    pixel width, so it reads as continuous and can be dragged or clicked
    anywhere. Zero is a real position on it and means paused, so the
    control that sets the speed is also the control that stops it.

    Both units are shown because they answer different questions:
    ticks per second is how alive the candle feels, seconds per candle
    is how fast the session moves. They are linked by the tick detail
    underneath, which is why that sits with them.
    """
    return ('<div class="spd">'
            '<div class="sl"><i class="fill" style="width:%d%%"></i>'
            '<i class="thumb" style="left:%d%%"></i></div>'
            '<div class="read"><span class="v">%s</span>'
            '<span class="u">ticks/s</span>'
            '<span class="sep">&middot;</span>'
            '<span class="v">%s</span><span class="u">s per candle</span>'
            '<span class="plan">%s</span></div>'
            '<div class="det"><span class="dl">DETAIL</span>%s'
            '<span class="du">ticks per candle</span></div>'
            '</div>'
            % (pos, pos, ticks, secs, plan,
               "".join('<b class="k chip%s">%s</b>'
                       % (" on" if d == detail else "", d)
                       for d in ("1", "12", "100"))))

def rail(active="TRD"):
    return ('<div class="rail">' + "".join(
        '<b class="%s">%s</b>' % ("on" if t == active else "", t)
        for t in ("TRD", "LOG", "STA")) + '</div>')

def ticket():
    """FLAT: you are hunting. Risk is a CONTROL, not a readout."""
    return ('<div class="sheet">'
            '<div class="fr"><span class="fl">RISK</span>'
            + "".join('<b class="k chip%s">%s</b>'
                      % (" on" if r == "1" else "", r)
                      for r in ("0.5", "1", "2"))
            + '<span class="fu">%</span>'
              '<span class="fv">0.42 lot</span></div>'
            '<div class="fr"><span class="fl">STOP</span>'
            '<span class="fv num">38 412.0</span>'
            '<span class="fx neg">&minus;52 pts</span></div>'
            '<div class="fr"><span class="fl">TARGET</span>'
            '<span class="fv num">38 604.0</span>'
            '<span class="fx pos">+140 pts</span></div>'
            '<div class="fr"><span class="fl">R : R</span>'
            '<span class="fv num">1 : 2.7</span>'
            '<span class="fx">$487 at risk</span></div>'
            '<div class="fr note"><span class="fl">NOTE</span>'
            '<span class="ed">breakout retest</span></div>'
            '<div class="deals">'
            + K(UP + "&nbsp; BUY", "buy") + K(DOWN + "&nbsp; SELL", "sell")
            + '</div></div>')

def position():
    """IN A POSITION: you are managing. R first, dollars second, and the
    excursion bar, because how far it went against you before it worked
    is the thing a student never remembers and a coach always asks."""
    return ('<div class="sheet">'
            '<div class="phead"><i class="pstripe"></i>'
            '<span class="pside">LONG 0.42</span>'
            '<span class="pr pos">+1.4 R</span></div>'
            '<div class="fr"><span class="fl">ENTRY</span>'
            '<span class="fv num">38 470.0</span>'
            '<span class="fx">09:31:02</span></div>'
            '<div class="fr"><span class="fl">STOP</span>'
            '<span class="fv num">38 412.0</span>'
            '<span class="fx neg">&minus;1.0 R</span></div>'
            '<div class="fr"><span class="fl">TARGET</span>'
            '<span class="fv num">38 604.0</span>'
            '<span class="fx pos">+2.7 R</span></div>'
            '<div class="fr"><span class="fl">OPEN</span>'
            '<span class="fv num pos">+$682</span>'
            '<span class="fx">peak +$780</span></div>'
            '<div class="exc"><span class="el">MAE/MFE</span>'
            '<div class="ebar">'
            '<i class="mae" style="left:34%;width:16%"></i>'
            '<i class="mfe" style="left:50%;width:28%"></i>'
            '<i class="entry" style="left:50%"></i>'
            '<i class="now" style="left:70%"></i></div>'
            '<span class="ev"><s class="neg">&minus;0.3</s>'
            '<s class="pos">+1.6</s></span></div>'
            '<div class="deals">'
            + K("BREAK EVEN", "flat2") + K("CLOSE", "close")
            + '</div></div>')

def status(flat=True):
    if flat:
        return ('<div class="status"><span class="run">RUNNING</span>'
                '<span class="sdim">flat</span>'
                '<span class="sdim">1.4</span>'
                '<span class="pos">session +2.1 R</span></div>')
    return ('<div class="status"><span class="run">RUNNING</span>'
            '<span class="sdim hot">1 open</span>'
            '<span class="sdim">1.4</span>'
            '<span class="pos">session +2.1 R</span></div>')

def panel(kind="flat", w=300):
    if kind == "flat":
        body = (caption() + head() + transport() + speed()
                + '<div class="sw">' + rail("TRD") + ticket() + '</div>'
                + status(True))
    elif kind == "pos":
        body = (caption() + head("38 538.0") + transport() + speed()
                + '<div class="sw">' + rail("TRD") + position() + '</div>'
                + status(False))
    else:   # collapsed
        body = (caption() + head() + transport()
                + speed(pos=46) + status(True))
    return '<div class="panel %s" style="%s" dir="ltr">%s</div>' % (
        kind, tokens(w), body)

CSS9 = r"""
.panel{position:relative;background:var(--face);border:1px solid var(--edge);
 font-family:var(--font);font-size:var(--fs);color:var(--text);line-height:1;
 user-select:none;font-variant-numeric:tabular-nums}
.panel *{box-sizing:border-box}
.panel b,.panel span,.panel i,.panel s{font-style:normal;font-weight:400}

.cap{height:22px;background:var(--cap);border-bottom:1px solid var(--edge);
 display:flex;align-items:center;padding:0 4px 0 8px}
.ttl{font-weight:700;font-size:12px}
.capb{margin-left:auto;display:flex;gap:2px}
.capb b{width:18px;height:15px;background:var(--btn);
 border:1px solid var(--btnedge);color:var(--dim);font-size:10px;
 display:flex;align-items:center;justify-content:center}
.capb b.x{color:var(--sell)}

/* THE HEAD: day, session position, clock, PRICE, scrub */
.head{padding:6px 8px 0}
.hrow{display:flex;align-items:baseline;justify-content:space-between}
.day{font-size:9px;letter-spacing:.14em;color:var(--dim)}
.sess{font-size:9px;letter-spacing:.08em;color:var(--faint)}
.hrow.big{margin-top:3px}
.clk{font-size:15px;color:var(--dim)}
.px{font-size:21px;color:var(--text);font-weight:700;letter-spacing:-.01em}
.px.up{color:var(--run)}
.px.dn{color:var(--sell)}
.scrub{margin-top:6px;height:2px;background:var(--well)}
.scrub i{display:block;height:2px;background:var(--dim)}

/* TRANSPORT: WGL4 glyphs, one row, the play key twice as wide */
.tr{display:flex;gap:3px;padding:7px 8px 0}
.k{display:flex;align-items:center;justify-content:center;height:23px;
 background:var(--btn);border:1px solid var(--btnedge);color:var(--text);
 font-size:11px}
.k.g{flex:1;font-size:10px;color:var(--dim)}
.k.play{flex:2;color:var(--accent);border-color:var(--accent);font-size:11px}
.k.stop{flex:1;color:var(--sell);font-size:9px}

/* THE SPEED CONTROL - a track, a fill, a thumb */
.spd{padding:9px 8px 0}
.sl{position:relative;height:8px;background:var(--well);
 border:1px solid var(--edge)}
.sl .fill{position:absolute;left:0;top:0;bottom:0;background:var(--accent)}
.sl .thumb{position:absolute;top:-4px;width:5px;height:14px;
 margin-left:-2px;background:var(--text);border:1px solid var(--face)}
.read{display:flex;align-items:baseline;gap:4px;padding-top:6px;font-size:10px}
.read .v{color:var(--text);font-size:12px}
.read .u{color:var(--dim);font-size:9px}
.read .sep{color:var(--faint)}
.read .plan{margin-left:auto;color:var(--faint);font-size:9px}
.det{display:flex;align-items:center;gap:3px;padding-top:6px}
.det .dl{font-size:9px;letter-spacing:.1em;color:var(--dim);width:42px}
.det .du{font-size:9px;color:var(--faint);margin-left:4px}
.k.chip{height:17px;min-width:28px;font-size:10px;padding:0 5px;flex:none;
 color:var(--dim)}
.k.chip.on{background:var(--accent);border-color:var(--accent);
 color:#1B1E23;font-weight:700}

/* RAIL - three, not four */
.sw{display:flex;margin-top:9px;border-top:1px solid var(--edge)}
.rail{width:34px;flex:none;border-right:1px solid var(--edge);
 background:var(--cap);padding-top:7px;display:flex;flex-direction:column;
 gap:3px;align-items:center}
.rail b{width:28px;height:22px;display:flex;align-items:center;
 justify-content:center;font-size:9px;letter-spacing:.06em;color:var(--dim);
 border:1px solid transparent}
.rail b.on{color:var(--text);background:var(--face);border-color:var(--edge);
 border-right-color:var(--face)}
.sheet{flex:1;padding:7px 8px 8px}

/* the ticket rows: label, value, and a right-hand consequence */
.fr{display:flex;align-items:center;gap:5px;height:19px}
.fr.note{height:23px}
.fl{width:46px;flex:none;font-size:9px;letter-spacing:.09em;color:var(--dim)}
.fv{font-size:12px;color:var(--text)}
.fv.num{min-width:62px}
.fu{font-size:9px;color:var(--dim);margin-left:-2px}
.fx{margin-left:auto;font-size:10px;color:var(--faint)}
.fx.pos,.fv.pos{color:var(--buy)}
.fx.neg,.fv.neg{color:var(--sell)}
.ed{flex:1;height:19px;display:flex;align-items:center;padding:0 5px;
 background:var(--well);border:1px solid var(--edge);font-size:11px}
.deals{display:flex;gap:5px;margin-top:7px}
.deals .k{flex:1;height:29px;font-weight:700;font-size:12px;
 letter-spacing:.05em;color:var(--dealtext)}
.k.buy{background:var(--buy);border-color:var(--buy)}
.k.sell{background:var(--sell);border-color:var(--sell)}
.k.flat2{background:var(--btn);border-color:var(--btnedge);color:var(--text);
 font-weight:400;letter-spacing:.08em;font-size:11px}
.k.close{background:var(--btn);border-color:var(--sell);color:var(--sell);
 letter-spacing:.08em;font-size:11px}

/* the open position */
.phead{position:relative;display:flex;align-items:center;height:24px;
 padding-left:9px;margin-bottom:4px;background:var(--well);
 border:1px solid var(--edge)}
.pstripe{position:absolute;left:0;top:0;bottom:0;width:4px;background:var(--buy)}
.pside{font-size:11px;color:var(--text);letter-spacing:.05em}
.pr{margin-left:auto;margin-right:7px;font-size:14px;font-weight:700}
.pr.pos{color:var(--buy)}
.exc{display:flex;align-items:center;gap:5px;height:22px;margin-top:2px}
.el{width:54px;flex:none;font-size:9px;letter-spacing:.04em;
 color:var(--dim);white-space:nowrap}
.ebar{position:relative;flex:1;height:9px;background:var(--well);
 border:1px solid var(--edge)}
.ebar i{position:absolute;top:0;bottom:0}
.ebar .mae{background:var(--sell)}
.ebar .mfe{background:var(--buy)}
.ebar .entry{width:1px;background:var(--faint);top:-3px;bottom:-3px}
.ebar .now{width:3px;background:var(--text);top:-2px;bottom:-2px}
.ev{display:flex;gap:6px;font-size:10px}
.ev s{text-decoration:none}
.ev .pos{color:var(--buy)}
.ev .neg{color:var(--sell)}

.status{height:19px;gap:9px;margin-top:0;background:var(--cap);
 border-top:1px solid var(--edge);display:flex;align-items:center;gap:10px;
 padding:0 8px;font-size:10px}
.status .run{color:var(--run);font-weight:700;letter-spacing:.08em}
.status .sdim{color:var(--dim)}
.status .sdim.hot{color:var(--text)}
.status .pos{color:var(--buy);margin-left:auto}
.collapsed .status{margin-top:9px}
"""

BG = "#6E7377"

def page(inner, extra=""):
    return ("<!doctype html><meta charset='utf-8'><style>"
            "html,body{margin:0;background:%s}body{padding:24px;"
            "display:inline-block}%s%s</style>%s" % (BG, CSS9, extra, inner))

def write(outdir):
    os.makedirs(outdir, exist_ok=True)
    open(os.path.join(outdir, "p_flat.html"), "w", encoding="utf-8").write(
        page(panel("flat")))
    open(os.path.join(outdir, "p_pos.html"), "w", encoding="utf-8").write(
        page(panel("pos")))
    open(os.path.join(outdir, "p_col.html"), "w", encoding="utf-8").write(
        page(panel("collapsed")))

    #--- the speed control, alone, at three positions and annotated
    rows = ""
    for lab, pos, t, s, pl in (
        ("stopped", 0, "0", "&mdash;", "paused"),
        ("study", 18, "3", "4.0", "1 h in 4 min"),
        ("session", 46, "12", "1.0", "1 h in 60 s"),
        ("scan", 88, "90", "0.13", "1 h in 8 s")):
        rows += ('<div class="demo"><div class="dlab">%s</div>'
                 '<div class="panel" style="%s">%s</div></div>'
                 % (lab, tokens(292), speed(pos, t, s, pl)))
    extra = (".demo{margin-bottom:16px}.dlab{font:600 12px/1.6 "
             "'Liberation Sans',sans-serif;color:#fff;letter-spacing:.04em;"
             "padding-bottom:5px}.panel{padding-bottom:9px}"
             "body{display:inline-block}")
    open(os.path.join(outdir, "p_speed.html"), "w", encoding="utf-8").write(
        page(rows, extra))


def write_compare(outdir):
    """08 as it was, beside 08 as I would build it. The removals are the
    argument, so they have to be visible side by side."""
    from build8 import panel8, CSS8
    from build import CSS as CSS_BASE
    inner = ('<figure><figcaption>NOW &nbsp;&mdash;&nbsp; design 08</figcaption>'
             + panel8("a01") + '</figure>'
             '<figure><figcaption>PROPOSED &nbsp;&mdash;&nbsp; flat</figcaption>'
             + panel("flat") + '</figure>'
             '<figure><figcaption>PROPOSED &nbsp;&mdash;&nbsp; in a position'
             '</figcaption>' + panel("pos") + '</figure>')
    extra = (CSS_BASE + CSS8 +
             "body{display:grid;grid-template-columns:repeat(3,max-content);"
             "gap:0 30px;align-items:start;width:max-content}figure{margin:0}"
             "figcaption{font:600 13px/1.4 'Liberation Sans',sans-serif;"
             "color:#fff;padding-bottom:9px;letter-spacing:.03em}")
    #--- CSS9 last so the proposal's rules win on the shared class names
    doc = ("<!doctype html><meta charset='utf-8'><style>"
           "html,body{margin:0;background:%s}body{padding:26px}%s%s</style>%s"
           % (BG, extra, CSS9, inner))
    open(os.path.join(outdir, "p_compare.html"), "w",
         encoding="utf-8").write(doc)

if __name__ == "__main__":
    write("/tmp/claude-0/faces/shots9")
    write_compare("/tmp/claude-0/faces/shots9")
    print("built")

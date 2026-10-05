#!/usr/bin/env python3
"""Draw the startup windows the way MetaTrader will, and look at them.

WHY THIS EXISTS
---------------
There is no compiler and no terminal on the machine this product is
written on, so the only way to see a layout before the user does is to
draw it from the same numbers the MQL5 uses. That is not a design mock:
the coordinates below are copied from the source, and when the two
disagree one of the files is wrong.

It earned its place immediately. The first Data Centre drew its hint
line six pixels inside the Stop button; nothing errored, every audit
passed, and it was obvious the moment the window was rendered.

ssr_layout_check.py is the automated half of the same idea - it reads
the #define constants and reports collisions without a human looking.
Use that in a hurry; use this when something looks wrong and you need
to see what.

    python3 tools/ssr_layout_preview.py        # writes docs/ux-ui/v127/

"""
import os
import re
from PIL import Image, ImageDraw, ImageFont

OUT = os.path.join(os.path.dirname(os.path.dirname(
    os.path.abspath(__file__))), "docs", "ux-ui", "v127")
os.makedirs(OUT, exist_ok=True)

C = dict(
    PANEL=(34,37,43), PANEL_EDGE=(103,111,125), HEADER=(27,30,35),
    WELL=(21,24,28), WELL_EDGE=(103,111,125), GROUP_EDGE=(103,111,125),
    TEXT=(230,233,238), TEXT_DIM=(176,182,192), TEXT_FAINT=(138,144,153),
    BTN=(44,48,55), BTN_EDGE=(103,111,124), BTN_TEXT=(230,233,238),
    TAB_ON=(34,37,43), RUN=(79,190,134), HOLD=(227,164,60),
    STOP=(237,118,110), ACCENT=(224,134,58), PRIMARY=(224,134,58),
    PRIMARY_TEXT=(27,30,35), LINE_LONG=(88,158,236),
)
S = 2                                   # 2x so the text is readable here

#--- THE SIZES ARE READ, NOT COPIED. A preview carrying its own idea of
#--- how big the type is stops being a preview the first time the theme
#--- changes, and does it silently.
THEME = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
                     "MQL5", "Include", "SSReplay", "Ui", "SSR_Theme.mqh")
PT = {}
FACE = {}
for _line in open(THEME, encoding="utf-8"):
    m = re.match(r"\s*#define\s+(SSR_FS_[A-Z]+)\s+(\d+)", _line)
    if m:
        PT[m.group(1)] = int(m.group(2))
    m = re.match(r'\s*#define\s+(SSR_FONT(?:_MONO)?)\s+"([^"]+)"', _line)
    if m:
        FACE[m.group(1)] = m.group(2)

#--- SEGOE UI IS NOT ON THIS MACHINE and there is no faithful free
#--- substitute for it. Liberation Sans is the closest thing installed -
#--- Arial metrics, so a little WIDER than Segoe UI, never narrower,
#--- which makes this preview pessimistic about fit rather than
#--- flattering. The image says so at the bottom; do not read letterform
#--- detail off it, only size, spacing and whether things collide.
F  = "/usr/share/fonts/truetype/liberation/LiberationSans-Regular.ttf"
FB = "/usr/share/fonts/truetype/liberation/LiberationSans-Bold.ttf"
FM = "/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf"

# MQL5 font sizes are points; at 96dpi a point is 4/3 of a pixel.
def f(pt, bold=False, mono=False):
    return ImageFont.truetype(FM if mono else (FB if bold else F),
                              int(round(pt*4/3*S)))

def rect(d,x,y,w,h,bg,edge):
    d.rectangle([x*S,y*S,(x+w)*S-1,(y+h)*S-1], fill=bg, outline=edge, width=max(1,S//2))
def label(d,x,y,t,col,pt=None,bold=False,mono=False):
    d.text((x*S,y*S), t, fill=col, font=f(pt or PT['SSR_FS_BODY'],bold,mono))
def button(d,x,y,w,h,t,bg=None,edge=None,fg=None,pt=None):
    bg=bg or C['BTN']; edge=edge or C['BTN_EDGE']; fg=fg or C['BTN_TEXT']
    rect(d,x,y,w,h,bg,edge)
    ft=f(pt or PT['SSR_FS_BODY']); tw=d.textlength(t,font=ft)
    d.text((x*S+(w*S-tw)/2, y*S+(h*S-ft.size*1.25)/2), t, fill=fg, font=ft)

def caption(im):
    d = ImageDraw.Draw(im)
    d.text((14*S, (CH-16)*S),
           "preview - sizes and spacing are the real ones (%s %dpt / %s); "
           "the FACE is Liberation Sans standing in for %s, which is not on "
           "the build machine"
           % (FACE.get('SSR_FONT','?'), PT['SSR_FS_BODY'],
              FACE.get('SSR_FONT_MONO','?'), FACE.get('SSR_FONT','?')),
           fill=(96,102,112), font=f(7))

CW, CH = 980, 560                        # a chart-sized canvas
def chart():
    im = Image.new('RGB',(CW*S,CH*S),(13,15,18))
    d = ImageDraw.Draw(im)
    for gx in range(0,CW,70): d.line([gx*S,0,gx*S,CH*S], fill=(26,29,34), width=1)
    for gy in range(0,CH,56): d.line([0,gy*S,CW*S,gy*S], fill=(26,29,34), width=1)
    return im,d

# ---------------------------------------------------------------- splash
def splash(d, status, col):
    X,Y,W,H = 14,14,296,112                      # SSR_SPLASH_*
    rect(d,X,Y,W,H,C['PANEL'],C['PANEL_EDGE'])
    rect(d,X+10,Y+10,22,22,C['ACCENT'],C['ACCENT'])
    label(d,X+15,Y+15,"SS",C['PRIMARY_TEXT'],PT['SSR_FS_BODY'],True)
    label(d,X+40,Y+10,"SS REPLAY",C['TEXT'],PT['SSR_FS_CLOCK'],True)
    label(d,X+40,Y+29,"market replay  -  manual backtesting  -  training",C['TEXT_DIM'],PT['SSR_FS_SMALL'])
    rect(d,X+10,Y+46,W-20,1,C['GROUP_EDGE'],C['GROUP_EDGE'])
    label(d,X+10,Y+52,"#20242426  demo  SS Academy Markets",C['TEXT_DIM'],PT['SSR_FS_SMALL'])
    label(d,X+10,Y+66,"Virtual trades only. Nothing is sent to your broker.",C['RUN'],PT['SSR_FS_SMALL'])
    label(d,X+W-86,Y+14,"v127",C['TEXT_FAINT'],PT['SSR_FS_SMALL'])
    label(d,X+10,Y+86,"!",C['HOLD'],PT['SSR_FS_BODY'],True)
    label(d,X+34,Y+86,status,col,PT['SSR_FS_SMALL'])

# ------------------------------------------------------------------ home
def home(d, x, y):
    W = 304                                      # SSR_SETUP_W
    rows = 4                                     # last + random + data + (no saved session)
    H = 34+22+rows*46+30+10
    rect(d,x,y,W,H,C['PANEL'],C['PANEL_EDGE'])
    label(d,x+12,y+9,"NEW REPLAY",C['TEXT'],PT['SSR_FS_BODY'],True)
    label(d,x+W-40,y+10,"v127",C['TEXT_FAINT'],PT['SSR_FS_SMALL'])
    rect(d,x+12,y+28,W-24,1,C['GROUP_EDGE'],C['GROUP_EDGE'])
    label(d,x+12,y+34,"Virtual trades only - nothing reaches your broker",C['RUN'],PT['SSR_FS_SMALL'])
    by = y+34+22
    for t,sub,prim in [
        ("Same as last time","M5  -  standard  -  10000.00  -  1.00% risk",True),
        ("Continue \"monday-open\"","picks up where that session was left",False),
        ("Random session","a start you have not seen, with a seed you can share",False),
        ("Data Centre","see which symbols you can replay, and from when",False)]:
        if prim: button(d,x+12,by,W-24,26,t,C['PRIMARY'],C['PRIMARY'],C['PRIMARY_TEXT'])
        else:    button(d,x+12,by,W-24,26,t)
        label(d,x+14,by+29,sub,C['TEXT_DIM'],PT['SSR_FS_SMALL'])
        by += 46
    button(d,x+12,by+4,W-24,22,"Customise...")
    return H

# ----------------------------------------------------------- data centre
ROWS, RH = 11, 17
DCW = 452
DCH = 20+46+ROWS*RH+76
def datacentre(d,x,y,data,sel,status,scanning=True):
    rect(d,x,y,DCW,DCH,C['PANEL'],C['PANEL_EDGE'])
    rect(d,x+1,y+1,DCW-2,20,C['HEADER'],C['GROUP_EDGE'])
    label(d,x+8,y+5,"DATA CENTRE  -  WHAT THIS TERMINAL HOLDS",C['ACCENT'],PT['SSR_FS_TITLE'],True)
    button(d,x+DCW-24,y+3,18,15,"X")
    hy=y+20+6
    for cx,t in [(10,"SYMBOL"),(104,"FROM"),(196,"TO"),(292,"M1 BARS"),(364,"TICKS")]:
        label(d,x+cx,hy,t,C['TEXT_FAINT'],PT['SSR_FS_SMALL'])
    ly=hy+14
    rect(d,x+6,ly,DCW-12,ROWS*RH+4,C['WELL'],C['WELL_EDGE'])
    for r in range(ROWS):
        ry=ly+2+r*RH
        if r>=len(data): continue
        sym,fr,to,bars,tk,state = data[r]
        if r==sel: rect(d,x+7,ry,DCW-14,RH-1,C['TAB_ON'],C['ACCENT'])
        label(d,x+12,ry+3,sym,C['TEXT'],PT['SSR_FS_SMALL'])
        col = {'ok':C['TEXT_DIM'],'none':C['STOP'],'wait':C['HOLD'],'pend':C['TEXT_FAINT']}[state]
        label(d,x+104,ry+3,fr,col,PT['SSR_FS_SMALL'])
        label(d,x+196,ry+3,to,col,PT['SSR_FS_SMALL'])
        label(d,x+292,ry+3,bars,col,PT['SSR_FS_SMALL'])
        label(d,x+364,ry+3,tk,C['RUN'] if tk=="real" else C['TEXT_FAINT'],PT['SSR_FS_SMALL'])
    by=ly+ROWS*RH+10
    button(d,x+DCW-62,by,24,18,"^"); button(d,x+DCW-34,by,24,18,"v")
    label(d,x+10,y+DCH-62,status,C['TEXT_DIM'],PT['SSR_FS_SMALL'])
    label(d,x+10,y+DCH-48,"Pick a symbol, then Use it to start a replay there.",C['TEXT_FAINT'],PT['SSR_FS_SMALL'])
    fy=y+DCH-22-6
    button(d,x+8,fy,86,22,"Stop" if scanning else "Read again")
    button(d,x+DCW-104,fy,96,22,"Use this symbol",C['PRIMARY'],C['PRIMARY'],C['PRIMARY_TEXT'])

ROWSET=[("EURUSD","02.01.2019","03.10.2026","1.8M","real","ok"),
        ("GBPUSD","02.01.2019","03.10.2026","1.8M","real","ok"),
        ("XAUUSD","04.03.2021","03.10.2026","1.4M","real","ok"),
        ("US30.Z26","14.09.2021","03.10.2026","912k","built","ok"),
        ("NAS100","14.09.2021","03.10.2026","910k","built","ok"),
        ("USDJPY","02.01.2019","03.10.2026","1.8M","real","ok"),
        ("BTCUSD","11.06.2022","03.10.2026","1.1M","real","ok"),
        ("APPLE_CFD","not loaded yet","","","","wait"),
        ("EURTRY","no M1 history","","","","none"),
        ("WTI","reading...","","","","pend"),
        ("SP500","reading...","","","","pend")]

# ---------------------------------------------------- market hours
#--- drawn from SSR_MarketHours.mqh's own constants and the same UTC
#--- windows the header there lists, so this is the sheet, not a sketch
MH = {}
for _line in open(os.path.join(os.path.dirname(os.path.dirname(
        os.path.abspath(__file__))), "MQL5", "Include", "SSReplay", "Ui",
        "SSR_MarketHours.mqh"), encoding="utf-8"):
    m = re.match(r"\s*#define\s+(SSR_MH_[A-Z]+)\s+(\d+)", _line)
    if m:
        MH[m.group(1)] = int(m.group(2))

CENTRES = [("SYD", 22, 7,  C['LINE_LONG']),
           ("TOK",  0, 9,  C['HOLD']),
           ("LON",  8, 17, C['RUN']),
           ("NY",  13, 22, C['STOP'])]

def open_at(fr, to, h):
    return (fr <= h < to) if fr <= to else (h >= fr or h < to)

def market_hours(d, x, y, now_h, now_m):
    cw, rh, gut = MH['SSR_MH_CW'], MH['SSR_MH_RH'], MH['SSR_MH_GUTTER']
    gx = x + gut
    for h in range(0, 24, 3):
        label(d, gx + h*cw - 2, y, "%02d" % h, C['TEXT_FAINT'],
              PT['SSR_FS_SMALL'])
    cy = y + 13
    top = cy
    for i, (nm, fr, to, tint) in enumerate(CENTRES):
        ry = cy + i*rh
        label(d, x, ry + 1, nm, C['TEXT_DIM'], PT['SSR_FS_SMALL'])
        run = None
        for h in range(25):
            o = h < 24 and open_at(fr, to, h)
            if o and run is None:
                run = h
            if not o and run is not None:
                rect(d, gx + run*cw, ry, (h-run)*cw, rh-2, tint, tint)
                run = None
    cy += len(CENTRES)*rh
    ov = [h for h in range(24) if open_at(8,17,h) and open_at(13,22,h)]
    rect(d, gx + ov[0]*cw, cy+1, (ov[-1]+1-ov[0])*cw, 2,
         C['ACCENT'], C['ACCENT'])
    label(d, gx + (ov[-1]+1)*cw + 4, cy-3, "overlap", C['ACCENT'],
          PT['SSR_FS_SMALL'])
    cy += 14
    nx = gx + now_h*cw + (now_m*cw)//60
    rect(d, nx, top-2, 1, len(CENTRES)*rh+2, C['TEXT'], C['TEXT'])
    label(d, x, cy, "Wed  %02d:%02d  server time (UTC+3)" % (now_h, now_m),
          C['TEXT'], PT['SSR_FS_SMALL'])
    cy += 13
    label(d, x, cy, "standard UTC hours; DST shifts them",
          C['TEXT_FAINT'], PT['SSR_FS_SMALL'])
    return cy + 13 - y

def group(d, x, y, w, h, legend):
    rect(d, x, y+5, w, h-5, C['PANEL'], C['GROUP_EDGE'])
    rect(d, x+6, y+1, 7+len(legend)*5, 9, C['PANEL'], C['PANEL'])
    label(d, x+9, y, legend, C['TEXT_DIM'], PT['SSR_FS_SMALL'])

im, d = chart()
#--- the sheet, at the width it really gets beside the rail
SHEET_W = 310 - 16 - 44 - 5
sx, sy = 60, 60
rect(d, sx-14, sy-14, SHEET_W+28, 230, C['PANEL'], C['PANEL_EDGE'])
label(d, sx-6, sy-10, "SESSION", C['ACCENT'], PT['SSR_FS_TITLE'], True)
group(d, sx, sy+12, SHEET_W, 58, "SESSION")
label(d, sx+8, sy+26, "bookmarks    3", C['TEXT_DIM'], PT['SSR_FS_SMALL'])
label(d, sx+8, sy+40, "streams      1   skew 0 ms", C['TEXT_DIM'], PT['SSR_FS_SMALL'])
label(d, sx+8, sy+54, "charts       clean", C['TEXT_DIM'], PT['SSR_FS_SMALL'])
group(d, sx, sy+74, SHEET_W, 119, "MARKET HOURS")
market_hours(d, sx+6, sy+88, 10, 28)
caption(im)
im.save(OUT + '/04-market-hours.png')

# screen 1 - what you see the second you attach it
im,d = chart()
splash(d,"Drag the line to where you want to start, then START.",C['HOLD'])
h = home(d, 340, 150)
d.line([(700*S,60*S),(700*S,520*S)], fill=C['HOLD'], width=2*S)
d.text((706*S,64*S),"START HERE",fill=C['HOLD'],font=f(PT['SSR_FS_BODY'],True))
caption(im)
im.save(OUT + '/01-start.png')

# screen 2 - the data centre over it
im,d = chart()
splash(d,"Drag the line to where you want to start, then START.",C['HOLD'])
home(d, 340, 150)
datacentre(d,(CW-DCW)//2,(CH-DCH)//2,ROWSET,3,"reading 9 of 11...")
caption(im)
im.save(OUT + '/02-datacentre.png')

# screen 3 - scan finished, running
im,d = chart()
splash(d,"Replay is running. Keep this chart open.",C['RUN'])
home(d, 340, 150)
datacentre(d,(CW-DCW)//2,(CH-DCH)//2,
           [r for r in ROWSET[:9]]+[("WTI","05.01.2020","03.10.2026","1.7M","real","ok"),
                                    ("SP500","14.09.2021","03.10.2026","908k","built","ok")],
           3,"9 of 11 symbols have minute history here",False)
caption(im)
im.save(OUT + '/03-done.png')
print("rendered")

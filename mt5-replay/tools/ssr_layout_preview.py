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
    PRIMARY_TEXT=(27,30,35),
)
S = 2                                   # 2x so the text is readable here
F = "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf"
FB = "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf"
# MQL5 font sizes are points; at 96dpi a point is 4/3 of a pixel.
def f(pt, bold=False): return ImageFont.truetype(FB if bold else F, int(round(pt*4/3*S)))

def rect(d,x,y,w,h,bg,edge):
    d.rectangle([x*S,y*S,(x+w)*S-1,(y+h)*S-1], fill=bg, outline=edge, width=max(1,S//2))
def label(d,x,y,t,col,pt=8,bold=False):
    d.text((x*S,y*S), t, fill=col, font=f(pt,bold))
def button(d,x,y,w,h,t,bg=None,edge=None,fg=None,pt=8):
    bg=bg or C['BTN']; edge=edge or C['BTN_EDGE']; fg=fg or C['BTN_TEXT']
    rect(d,x,y,w,h,bg,edge)
    ft=f(pt); tw=d.textlength(t,font=ft)
    d.text((x*S+(w*S-tw)/2, y*S+(h*S-ft.size*1.25)/2), t, fill=fg, font=ft)

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
    label(d,X+15,Y+15,"SS",C['PRIMARY_TEXT'],8,True)
    label(d,X+40,Y+10,"SS REPLAY",C['TEXT'],13,True)
    label(d,X+40,Y+29,"market replay  -  manual backtesting  -  training",C['TEXT_DIM'],7)
    rect(d,X+10,Y+46,W-20,1,C['GROUP_EDGE'],C['GROUP_EDGE'])
    label(d,X+10,Y+52,"#20242426  demo  SS Academy Markets",C['TEXT_DIM'],7)
    label(d,X+10,Y+66,"Virtual trades only. Nothing is sent to your broker.",C['RUN'],7)
    label(d,X+W-86,Y+14,"v127",C['TEXT_FAINT'],7)
    label(d,X+10,Y+86,"!",C['HOLD'],8,True)
    label(d,X+34,Y+86,status,col,7)

# ------------------------------------------------------------------ home
def home(d, x, y):
    W = 304                                      # SSR_SETUP_W
    rows = 4                                     # last + random + data + (no saved session)
    H = 34+22+rows*46+30+10
    rect(d,x,y,W,H,C['PANEL'],C['PANEL_EDGE'])
    label(d,x+12,y+9,"NEW REPLAY",C['TEXT'],8,True)
    label(d,x+W-40,y+10,"v127",C['TEXT_FAINT'],7)
    rect(d,x+12,y+28,W-24,1,C['GROUP_EDGE'],C['GROUP_EDGE'])
    label(d,x+12,y+34,"Virtual trades only - nothing reaches your broker",C['RUN'],7)
    by = y+34+22
    for t,sub,prim in [
        ("Same as last time","M5  -  standard  -  10000.00  -  1.00% risk",True),
        ("Continue \"monday-open\"","picks up where that session was left",False),
        ("Random session","a start you have not seen, with a seed you can share",False),
        ("Data Centre","see which symbols you can replay, and from when",False)]:
        if prim: button(d,x+12,by,W-24,26,t,C['PRIMARY'],C['PRIMARY'],C['PRIMARY_TEXT'])
        else:    button(d,x+12,by,W-24,26,t)
        label(d,x+14,by+29,sub,C['TEXT_DIM'],7)
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
    label(d,x+8,y+5,"DATA CENTRE  -  WHAT THIS TERMINAL HOLDS",C['ACCENT'],9,True)
    button(d,x+DCW-24,y+3,18,15,"X")
    hy=y+20+6
    for cx,t in [(10,"SYMBOL"),(104,"FROM"),(196,"TO"),(292,"M1 BARS"),(364,"TICKS")]:
        label(d,x+cx,hy,t,C['TEXT_FAINT'],7)
    ly=hy+14
    rect(d,x+6,ly,DCW-12,ROWS*RH+4,C['WELL'],C['WELL_EDGE'])
    for r in range(ROWS):
        ry=ly+2+r*RH
        if r>=len(data): continue
        sym,fr,to,bars,tk,state = data[r]
        if r==sel: rect(d,x+7,ry,DCW-14,RH-1,C['TAB_ON'],C['ACCENT'])
        label(d,x+12,ry+3,sym,C['TEXT'],7)
        col = {'ok':C['TEXT_DIM'],'none':C['STOP'],'wait':C['HOLD'],'pend':C['TEXT_FAINT']}[state]
        label(d,x+104,ry+3,fr,col,7)
        label(d,x+196,ry+3,to,col,7)
        label(d,x+292,ry+3,bars,col,7)
        label(d,x+364,ry+3,tk,C['RUN'] if tk=="real" else C['TEXT_FAINT'],7)
    by=ly+ROWS*RH+10
    button(d,x+DCW-62,by,24,18,"^"); button(d,x+DCW-34,by,24,18,"v")
    label(d,x+10,y+DCH-62,status,C['TEXT_DIM'],7)
    label(d,x+10,y+DCH-48,"Pick a symbol, then Use it to start a replay there.",C['TEXT_FAINT'],7)
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

# screen 1 - what you see the second you attach it
im,d = chart()
splash(d,"Drag the line to where you want to start, then START.",C['HOLD'])
h = home(d, 340, 150)
d.line([(700*S,60*S),(700*S,520*S)], fill=C['HOLD'], width=2*S)
d.text((706*S,64*S),"START HERE",fill=C['HOLD'],font=f(8,True))
im.save(OUT + '/01-start.png')

# screen 2 - the data centre over it
im,d = chart()
splash(d,"Drag the line to where you want to start, then START.",C['HOLD'])
home(d, 340, 150)
datacentre(d,(CW-DCW)//2,(CH-DCH)//2,ROWSET,3,"reading 9 of 11...")
im.save(OUT + '/02-datacentre.png')

# screen 3 - scan finished, running
im,d = chart()
splash(d,"Replay is running. Keep this chart open.",C['RUN'])
home(d, 340, 150)
datacentre(d,(CW-DCW)//2,(CH-DCH)//2,
           [r for r in ROWSET[:9]]+[("WTI","05.01.2020","03.10.2026","1.7M","real","ok"),
                                    ("SP500","14.09.2021","03.10.2026","908k","built","ok")],
           3,"9 of 11 symbols have minute history here",False)
im.save(OUT + '/03-done.png')
print("rendered")

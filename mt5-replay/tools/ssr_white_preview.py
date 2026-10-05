#!/usr/bin/env python3
"""The host chart as a white page: logo, name, text, no frame."""
import os, re, sys
from PIL import Image, ImageDraw, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
UI = os.path.join(ROOT, "MQL5", "Include", "SSReplay", "Ui")
OUT = os.path.join(ROOT, "docs", "ux-ui", "v129")
os.makedirs(OUT, exist_ok=True)
LOGO = os.path.join(os.path.dirname(ROOT), "assets", "logo.png")

src = open(os.path.join(UI, "SSR_Theme.mqh"), encoding="utf-8").read()
blk = re.search(r"#ifdef SSR_THEME_LIGHT\n(.*?)\n#endif", src, re.S).group(1)
C = {m.group(1): (int(m.group(2)), int(m.group(3)), int(m.group(4)))
     for m in re.finditer(r"#define SSR_C_([A-Z0-9_]+)\s+C'(\d+),(\d+),(\d+)'", blk)}
PT = {m.group(1): int(m.group(2)) for m in
      re.finditer(r"#define (SSR_FS_[A-Z]+)\s+(\d+)", src)}

S = 2
FR = "/usr/share/fonts/truetype/liberation/LiberationSans-Regular.ttf"
FB = "/usr/share/fonts/truetype/liberation/LiberationSans-Bold.ttf"
FG = "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf"
GL = set("▾▴✓✕□–")
def f(pt, bold=False, g=False):
    return ImageFont.truetype(FG if g else (FB if bold else FR), int(round(pt*4/3*S)))
def isg(t): return len(t) <= 2 and any(c in GL for c in t)
def rect(d,x,y,w,h,bg,ed=None):
    d.rectangle([x*S,y*S,(x+w)*S-1,(y+h)*S-1], fill=bg, outline=ed or bg, width=1)
def txt(d,x,y,t,col,pt=None,bold=False):
    d.text((x*S,y*S), t, fill=col, font=f(pt or PT["SSR_FS_BODY"], bold, isg(t)))
def txtc(d,x,y,w,t,col,pt=None,bold=False):
    ft=f(pt or PT["SSR_FS_BODY"], bold, isg(t)); tw=d.textlength(t,font=ft)
    d.text((x*S+(w*S-tw)/2, y*S), t, fill=col, font=ft)

CW, CH = 1040, 560
NAVY = (31, 56, 110)          # from the academy mark
GOLD = (212, 175, 112)

def page(home_w=360, btn_h=34, name="W1", gap=12, note_txt=""):
    im = Image.new("RGB", (CW*S, CH*S), (255,255,255))
    d = ImageDraw.Draw(im)

    #--- the logo, top left, where the reference puts its product shot
    lg = Image.open(LOGO).convert("RGBA")
    target_h = 150*S
    lg = lg.resize((int(lg.width*target_h/lg.height), target_h), Image.LANCZOS)
    im.paste(lg, (36*S, 34*S), lg)

    #--- the name and the lines, written ON the page. No frame, no plate.
    tx = 36 + int(lg.width/S) + 34
    #--- the offsets below are SSR_Splash::Render's own, so the picture
    #--- and the code cannot say different things
    y0 = 34
    txt(d, tx, y0+8,   "SS Replay", C["TEXT"], PT["SSR_FS_PAGE"], True)
    txt(d, tx, y0+40,  "market replay  -  manual backtesting  -  training",
        C["TEXT_DIM"], PT["SSR_FS_TITLE"])
    txt(d, tx, y0+76,  "Keep this chart open. You may minimise it.",
        C["RUN"], PT["SSR_FS_TITLE"])
    txt(d, tx, y0+98,  "The replay runs from here.", C["RUN"], PT["SSR_FS_TITLE"])
    txt(d, tx, y0+128, "#20242426  demo  SS Academy Markets",
        C["TEXT_FAINT"], PT["SSR_FS_BODY"])
    txt(d, tx, y0+148, "Virtual trades only. Nothing is sent to your broker.",
        C["TEXT_FAINT"], PT["SSR_FS_BODY"])
    txt(d, tx, y0+168, "v129", C["TEXT_FAINT"], PT["SSR_FS_SMALL"])

    #--- the Home dialog, to the reference's proportions
    W = home_w
    H = 44 + 46 + 4*(btn_h+gap) + 18
    #--- clear of the text block, the way the reference sits its dialog
    #--- to the right of and below the lines it must not cover
    x = CW - W - 190
    y = 190
    rect(d, x, y, W, H, C["PANEL"], C["PANEL_EDGE"])
    rect(d, x+1, y+1, W-2, 24, (255,255,255), C["PANEL_EDGE"])
    rect(d, x+7, y+6, 13, 13, NAVY)
    txt(d, x+9, y+7, "S", (255,255,255), PT["SSR_FS_SMALL"], True)
    txt(d, x+26, y+6, "SS Replay", (26,26,26), PT["SSR_FS_BODY"], True)
    for i,g in enumerate(("–","□","✕")):
        txtc(d, x+W-20*(3-i)-4, y+6, 20, g, (90,94,100), PT["SSR_FS_SMALL"])

    txtc(d, x, y+38, W, "Connected to account #20242426", C["RUN"], PT["SSR_FS_BODY"])
    txtc(d, x, y+56, W, "Demo  -  virtual trades only", (110,110,110), PT["SSR_FS_SMALL"])

    by = y + 84
    bw = W - 2*22                      # the reference's own side margin
    for t, prim in (("New replay", True), ("Load a saved session", False),
                    ("Data Centre", False), ("Close", False)):
        if prim:
            rect(d, x+22, by, bw, btn_h, C["PRIMARY"], C["PRIMARY_EDGE"])
            txtc(d, x+22, by+(btn_h-14)//2, bw, t, C["PRIMARY_TEXT"], PT["SSR_FS_BODY"])
        else:
            rect(d, x+22, by, bw, btn_h, C["BTN"], C["BTN_EDGE"])
            txtc(d, x+22, by+(btn_h-14)//2, bw, t, C["BTN_TEXT"], PT["SSR_FS_BODY"])
        by += btn_h + gap

    d.text((26*S,(CH-18)*S), "%s - host chart as a white page: the academy "
           "mark, the expert's name, and the notes written straight onto it. "
           "No card, no border. Home dialog %d px wide, buttons %d px tall."
           % (name, W, btn_h), fill=(150,150,150), font=f(8))
    return im

#--- 360 is the width that was chosen; the others are kept so the
#--- comparison that produced the choice can be reproduced.
page(360, 34, "v129 - shipped").save(os.path.join(OUT, "shipped-360.png"))
page(420, 38, "W2", 14).save(os.path.join(OUT, "W2-white-420.png"))
page(480, 42, "W3", 16).save(os.path.join(OUT, "W3-white-480.png"))
print("wrote 3")

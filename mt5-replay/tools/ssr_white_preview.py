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
M = {m.group(1): int(m.group(2)) for m in
     re.finditer(r"#define (SSR_HOME_[A-Z_]+|SSR_SPLASH_[A-Z_]+|SSR_LOGO_[A-Z]+)\s+(\d+)", src)}
SP = open(os.path.join(UI, "SSR_Splash.mqh"), encoding="utf-8").read()
for m in re.finditer(r"#define (SSR_SPLASH_[A-Z_]+|SSR_LOGO_[A-Z]+)\s+(\d+)", SP):
    M[m.group(1)] = int(m.group(2))
M["SSR_SPLASH_TX"] = M["SSR_SPLASH_X"] + M["SSR_LOGO_W"] + 34

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

def page(home_w=None, btn_h=None, name="v130", gap=None, note_txt=""):
    """Drawn from SSR_Splash and SSR_SetupPanel's own constants."""
    W  = home_w or M["SSR_HOME_W"]
    BH = btn_h or M["SSR_HOME_BTN_H"]
    GP = gap if gap is not None else M["SSR_HOME_GAP"]

    im = Image.new("RGB", (CW*S, CH*S), (255,255,255))
    d = ImageDraw.Draw(im)

    lg = Image.open(LOGO).convert("RGBA")
    th = M["SSR_LOGO_H"]*S
    lg = lg.resize((int(lg.width*th/lg.height), th), Image.LANCZOS)
    im.paste(lg, (M["SSR_SPLASH_X"]*S, M["SSR_SPLASH_Y"]*S), lg)

    tx = M["SSR_SPLASH_TX"]; y0 = M["SSR_SPLASH_Y"]
    txt(d, tx, y0+8,   "SS Replay", C["TEXT"], PT["SSR_FS_PAGE"], True)
    txt(d, tx, y0+40,  "market replay  -  manual backtesting  -  training",
        C["TEXT_DIM"], PT["SSR_FS_TITLE"])
    txt(d, tx, y0+76,  "Keep this chart open. You may minimise it.",
        C["RUN"], PT["SSR_FS_TITLE"])
    txt(d, tx, y0+98,  "The replay runs from here.", C["RUN"], PT["SSR_FS_TITLE"])
    txt(d, tx, y0+128, "#20242426  demo  WM Markets Ltd",
        C["TEXT_FAINT"], PT["SSR_FS_BODY"])
    txt(d, tx, y0+148, "Virtual trades only. Nothing is sent to your broker.",
        C["TEXT_FAINT"], PT["SSR_FS_BODY"])
    txt(d, tx, y0+168, "v130", C["TEXT_FAINT"], PT["SSR_FS_SMALL"])

    #--- the dialog, beside the page the way SSR_SetupPanel places it
    n = 4
    H = (M["SSR_HOME_TITLE"] + M["SSR_HOME_HEAD"] + n*BH + (n-1)*GP
         + M["SSR_HOME_FOOT"])
    x = M["SSR_SPLASH_TX"] + M["SSR_SPLASH_TEXT_W"] + 24
    y = (CH - H)//2
    rect(d, x, y, W, H, C["PANEL"], C["PANEL_EDGE"])
    rect(d, x+1, y+1, W-2, M["SSR_HOME_TITLE"]-1, C["HEADER"], C["GROUP_EDGE"])
    rect(d, x+9, y+9, 16, 16, C["ACCENT"])
    txt(d, x+12, y+11, "SS", C["PRIMARY_TEXT"], PT["SSR_FS_SMALL"], True)
    txt(d, x+32, y+10, "SS Replay", C["TEXT"], PT["SSR_FS_TITLE"], True)
    txt(d, x+W-46, y+11, "v130", C["TEXT_FAINT"], PT["SSR_FS_SMALL"])

    hy = y + M["SSR_HOME_TITLE"] + 14
    txt(d, x+24, hy, "Connected to  #20242426  demo", C["RUN"], PT["SSR_FS_BODY"])
    txt(d, x+24, hy+22, "Virtual trades only - nothing reaches your broker",
        C["TEXT_DIM"], PT["SSR_FS_SMALL"])

    bx = x + M["SSR_HOME_PAD"]; bw = W - 2*M["SSR_HOME_PAD"]
    by = y + M["SSR_HOME_TITLE"] + M["SSR_HOME_HEAD"]
    for t, prim in (("Same as last time", True), ("Customise...", False),
                    ("Random session", False), ("Data Centre", False)):
        if prim:
            rect(d, bx, by, bw, BH, C["PRIMARY"], C["PRIMARY_EDGE"])
            txtc(d, bx, by+(BH-14)//2, bw, t, C["PRIMARY_TEXT"], PT["SSR_FS_BODY"])
        else:
            rect(d, bx, by, bw, BH, C["BTN"], C["BTN_EDGE"])
            txtc(d, bx, by+(BH-14)//2, bw, t, C["BTN_TEXT"], PT["SSR_FS_BODY"])
        by += BH + GP

    d.text((26*S,(CH-18)*S),
           "%s - the host chart blanked completely (no candles), the page "
           "written on it, and the Home dialog beside the text at the "
           "measured proportions: %d wide, title %d, buttons %d, gap %d."
           % (name, W, M["SSR_HOME_TITLE"], BH, GP),
           fill=(150,150,150), font=f(8))
    return im


OUT2 = os.path.join(ROOT, "docs", "ux-ui", "v130")
os.makedirs(OUT2, exist_ok=True)
page().save(os.path.join(OUT2, "home.png"))
print("wrote", os.path.join(OUT2, "home.png"))

import subprocess, os, sys
from PIL import Image, ImageDraw, ImageFont
sys.path.insert(0,'.')
from build8 import panel8, CSS8, ORDERB, L
from build import CSS
CH="/opt/pw-browsers/chromium-1194/chrome-linux/chrome"
BG=(0x6E,0x73,0x77)
os.makedirs("shotsB", exist_ok=True)
for k in ORDERB:
    doc=("<!doctype html><meta charset='utf-8'><style>html,body{margin:0;"
         "background:#6E7377}body{padding:24px;display:inline-block}%s%s</style>%s"
         %(CSS,CSS8,panel8(k)))
    open("shotsB/s_%s.html"%k,"w",encoding="utf-8").write(doc)
    subprocess.run([CH,"--headless","--disable-gpu","--no-sandbox",
        "--hide-scrollbars","--force-device-scale-factor=2",
        "--window-size=520,640","--screenshot=shotsB/raw_%s.png"%k,
        "file:///tmp/claude-0/faces/shotsB/s_%s.html"%k],capture_output=True)
    im=Image.open("shotsB/raw_%s.png"%k).convert("RGB");w,h=im.size;px=im.load()
    mnx,mny,mxx,mxy=w,h,-1,-1
    for y in range(h):
        for x in range(0,w,3):
            if px[x,y]!=BG:
                mnx=min(mnx,x);mxx=max(mxx,x);mny=min(mny,y);mxy=max(mxy,y)
    im.crop((max(0,mnx-26),max(0,mny-26),min(w,mxx+27),min(h,mxy+27))).save("shotsB/%s.png"%k)
    os.remove("shotsB/raw_%s.png"%k)
    print("%-4s %-22s %dx%d css"%(k,L[k]["name"],(mxx-mnx+1)//2,(mxy-mny+1)//2))

#--- one sheet, four panels, captioned
import glob
FB="/usr/share/fonts/truetype/liberation/LiberationSans-Bold.ttf"
if not os.path.exists(FB):
    FB=glob.glob("/usr/share/fonts/**/DejaVuSans-Bold.ttf",recursive=True)[0]
f=ImageFont.truetype(FB,24)
caps={"a01":"NOW  -  8 squares","b01":"A  -  slider only",
      "b02":"B  -  slider + readout","b03":"C  -  slider + full line"}
ims=[(caps[k],Image.open("shotsB/%s.png"%k).convert("RGB")) for k in ORDERB]
pad,gap,top=28,24,48
W=pad*2+sum(i.width for _,i in ims)+gap*(len(ims)-1)
H=top+max(i.height for _,i in ims)+pad
out=Image.new("RGB",(W,H),BG); d=ImageDraw.Draw(out); x=pad
for t,im in ims:
    d.text((x+26,14),t,font=f,fill=(255,255,255)); out.paste(im,(x,top))
    x+=im.width+gap
out.save("shotsB/compareB.png"); print("sheet", out.size)
out.resize((out.width//2,out.height//2),Image.LANCZOS).save("shotsB/compareB_s.png")

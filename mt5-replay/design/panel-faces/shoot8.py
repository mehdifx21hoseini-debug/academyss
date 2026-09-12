import json, subprocess, os
from PIL import Image
CH="/opt/pw-browsers/chromium-1194/chrome-linux/chrome"
BG=(0x6E,0x73,0x77)
import sys; sys.path.insert(0,'.')
from build8 import ORDER8
sizes={}
for k in ORDER8:
    subprocess.run([CH,"--headless","--disable-gpu","--no-sandbox",
        "--hide-scrollbars","--force-device-scale-factor=2",
        "--window-size=520,640","--screenshot=shots8/raw_%s.png"%k,
        "file:///tmp/claude-0/faces/shots8/s8_%s.html"%k], capture_output=True)
    im=Image.open("shots8/raw_%s.png"%k).convert("RGB");w,h=im.size;px=im.load()
    mnx,mny,mxx,mxy=w,h,-1,-1
    for y in range(h):
        for x in range(0,w,3):
            if px[x,y]!=BG:
                mnx=min(mnx,x);mxx=max(mxx,x);mny=min(mny,y);mxy=max(mxy,y)
    sizes[k]=[(mxx-mnx+1)//2,(mxy-mny+1)//2]
    im.crop((max(0,mnx-26),max(0,mny-26),min(w,mxx+27),min(h,mxy+27))).save("shots8/%s.png"%k)
    os.remove("shots8/raw_%s.png"%k)
    print("%-4s %dx%d css"%(k,sizes[k][0],sizes[k][1]))
json.dump(sizes,open("sizes8.json","w"))

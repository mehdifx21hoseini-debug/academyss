import json, subprocess, os
from PIL import Image
CH="/opt/pw-browsers/chromium-1194/chrome-linux/chrome"
BG=(0x6E,0x73,0x77)
KEYS=["v1","v2","v3","v4","v5","v6","v7","v8","v9","v10"]
sizes={}
for k in KEYS:
    subprocess.run([CH,"--headless","--disable-gpu","--no-sandbox",
        "--hide-scrollbars","--force-device-scale-factor=2",
        "--window-size=620,640","--screenshot=shots/raw_%s.png"%k,
        "file:///tmp/claude-0/faces/shots/shot_%s.html"%k],
        capture_output=True)
    im=Image.open("shots/raw_%s.png"%k).convert("RGB");w,h=im.size;px=im.load()
    mnx,mny,mxx,mxy=w,h,-1,-1
    for y in range(h):
        for x in range(0,w,3):
            if px[x,y]!=BG:
                mnx=min(mnx,x);mxx=max(mxx,x);mny=min(mny,y);mxy=max(mxy,y)
    sizes[k]=[(mxx-mnx+1)//2,(mxy-mny+1)//2]
    im.crop((max(0,mnx-28),max(0,mny-28),min(w,mxx+29),min(h,mxy+29))).save("shots/%s.png"%k)
    os.remove("shots/raw_%s.png"%k)
    print("%-4s %dx%d css"%(k,sizes[k][0],sizes[k][1]))
json.dump(sizes,open("sizes.json","w"))

"""Solve each palette to WCAG, keeping its hue. Nothing is eyeballed."""
import colorsys, sys, json
sys.path.insert(0, "/tmp/claude-0/faces")
from palettes import P, rgb, lum, cr

#--- DEAL BUTTONS DIFFER BY DESIGN, so the pairs differ with them.
#--- v4 and v9 draw BUY/SELL as outlined text, not filled slabs: there
#--- the colour IS the text and must clear 4.5 on the face, while a
#--- filled slab is a surface (3.0) carrying white text (4.5).
OUTLINE_DEALS = ("v4", "v9")

def pairs_for(key):
    p = [("text","face","text"), ("text","cap","text"), ("text","well","text"),
         ("dim","face","text"),  ("dim","cap","text"),  ("dim","well","text"),
         ("faint","face","text"),("faint","cap","text"),("faint","well","text"),
         ("accent","face","text"),("accent","well","text"),
         ("run","face","text"),  ("text","btn","text"),
         ("edge","face","ui"),   ("btnedge","face","ui")]
    if key in OUTLINE_DEALS:
        p += [("buy","face","text"), ("sell","face","text")]
    else:
        p += [("buy","face","ui"), ("sell","face","ui"),
              ("dealtext","buy","text"), ("dealtext","sell","text")]
    return p

def hexof(r,g,b): return "#%02X%02X%02X" % (r,g,b)

def nudge(col, against, want, darker):
    """Walk lightness one way, hue and saturation held, until it clears."""
    r,g,b = [v/255.0 for v in rgb(col)]
    h,l,s = colorsys.rgb_to_hls(r,g,b)
    best = col
    for i in range(400):
        l = max(0.0, min(1.0, l + (-0.0025 if darker else 0.0025)))
        rr,gg,bb = colorsys.hls_to_rgb(h,l,s)
        c = hexof(round(rr*255), round(gg*255), round(bb*255))
        best = c
        if cr(c, against) >= want:
            return c
        if l <= 0.0 or l >= 1.0:
            break
    return best

changed = {}
for key, p in P.items():
    p = dict(p)
    face_dark = lum(p["face"]) < 0.35
    notes = []
    for fg, bg, kind in pairs_for(key):
        want = 4.5 if kind == "text" else 3.0
        if cr(p[fg], p[bg]) >= want:
            continue
        #--- which side moves: never the surfaces, they carry the design.
        #--- On a filled deal button the SLAB moves so its white text
        #--- clears; everywhere else the foreground moves.
        if (fg, kind) == ("dealtext", "text"):
            before = p[bg]
            p[bg] = nudge(p[bg], p[fg], want, darker=True)
            notes.append("%s %s->%s" % (bg, before, p[bg]))
        else:
            before = p[fg]
            p[fg] = nudge(p[fg], p[bg], want, darker=not face_dark)
            notes.append("%s %s->%s" % (fg, before, p[fg]))
    changed[key] = p
    #--- re-measure everything after the moves
    fails = [(f,b,round(cr(p[f],p[b]),2)) for f,b,k in pairs_for(key)
             if cr(p[f],p[b]) < (4.5 if k=="text" else 3.0)]
    wt = min((cr(p[f],p[b]), "%s/%s"%(f,b)) for f,b,k in pairs_for(key) if k=="text")
    wu = min((cr(p[f],p[b]), "%s/%s"%(f,b)) for f,b,k in pairs_for(key) if k=="ui")
    print("%-4s %-18s fails=%d  worst text %.2f (%s)  worst ui %.2f (%s)"
          % (key, p["name"], len(fails), wt[0], wt[1], wu[0], wu[1]))
    if notes:
        print("       moved: " + "; ".join(notes))
json.dump(changed, open("/tmp/claude-0/faces/solved.json","w"), indent=1)

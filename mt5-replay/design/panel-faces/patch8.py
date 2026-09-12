# -*- coding: utf-8 -*-
s = open("build8.py", encoding="utf-8").read()
entry = """
 "c01": dict(name="v124 as built", w=310, rail="left", actions=True,
   order="cap clock transport speed actions sheet status", speed="slider",
   note="What v124 draws.",
   fa="what v124 draws"),

 "a02": dict("""
s = s.replace('\n "a02": dict(', entry, 1)

acts = """    B["actions"] = ('<div class="acts">' + "".join(
        '<b class="k act">%s</b>' % a
        for a in ("Follow", "SL/TP", "Mark", "Jump", "Saved", "Detail"))
        + '</div>')

    B["striptabs"] = ("""
s = s.replace('    B["striptabs"] = (', acts, 1)

tags_old = """            for t, on in [("TRD",1),("POS",0),("STA",0),("SES",0)]:"""
tags_new = """            tags = ([("Trade",1),("Pos 2",0),("Stats",0),("Sess",0)]
                    if v.get("actions") else
                    [("TRD",1),("POS",0),("STA",0),("SES",0)])
            for t, on in tags:"""
assert tags_old in s
s = s.replace(tags_old, tags_new, 1)

css_new = """/* v124: the action strip and the wider rail */
.acts{display:flex;gap:3px;padding:2px 8px 0}
.k.act{flex:1;height:21px;font-size:10px;color:var(--dim)}
.c01 .rail{width:44px}
.c01 .rail b{width:44px;height:22px;font-size:10px;letter-spacing:.02em}
.c01 .sheetwrap{border-top:1px solid var(--edge);margin-top:5px}

/* the continuous slider */"""
assert "/* the continuous slider, in design 08's own speed row */" in s
s = s.replace("/* the continuous slider, in design 08's own speed row */",
              css_new, 1)
open("build8.py", "w", encoding="utf-8").write(s)
print("c01 added")

# The ten palettes. Every pair the panel actually draws is measured here
# BEFORE a single pixel is designed - the same rule the product ships under.
P = {
 "v1": dict(name="Slate Instrument",
   face="#262A33", cap="#21242C", well="#181B21", edge="#575E6D",
   text="#E9ECF2", dim="#BAC1CD", faint="#959AA2",
   accent="#56B6C2", buy="#2E9B63", sell="#C24A3B", run="#58C08A",
   btn="#343945", btnedge="#565D6C", dealtext="#FFFFFF"),
 "v2": dict(name="Paper Blotter",
   face="#F1EFE9", cap="#E7E3DA", well="#FAF9F5", edge="#B9B3A5",
   text="#1A1814", dim="#4A453C", faint="#6E675B",
   accent="#8C2F27", buy="#1F6B44", sell="#A1352A", run="#1F6B44",
   btn="#F1EFE9", btnedge="#9A937F", dealtext="#FFFFFF"),
 "v3": dict(name="Bloomberg Night",
   face="#000000", cap="#0B0B0B", well="#0B0B0B", edge="#4A3A14",
   text="#FFB340", dim="#D9952F", faint="#B87C24",
   accent="#FFFFFF", buy="#2FD46F", sell="#FF5A4D", run="#2FD46F",
   btn="#000000", btnedge="#8A6220", dealtext="#000000"),
 "v4": dict(name="Swiss Grid",
   face="#FFFFFF", cap="#FFFFFF", well="#FFFFFF", edge="#000000",
   text="#000000", dim="#3B3B3B", faint="#6B6B6B",
   accent="#D0021B", buy="#000000", sell="#D0021B", run="#000000",
   btn="#FFFFFF", btnedge="#000000", dealtext="#FFFFFF"),
 "v5": dict(name="Blueprint",
   face="#10192B", cap="#0C1424", well="#0B1220", edge="#2E4A73",
   text="#D6E4F7", dim="#9FB8DA", faint="#7A93B8",
   accent="#7FB2FF", buy="#3E9E74", sell="#C2564A", run="#7FB2FF",
   btn="#16223A", btnedge="#35537F", dealtext="#FFFFFF"),
 "v6": dict(name="Carbon Bevel",
   face="#3A3A3C", cap="#313133", well="#2A2A2C", edge="#5A5A5D",
   text="#EDEDEF", dim="#C2C2C6", faint="#9B9BA0",
   accent="#E3B341", buy="#8ADCAC", sell="#F59C91", run="#5FC08C",
   btn="#454547", btnedge="#606063", dealtext="#141618"),
 "v7": dict(name="Daylight Large",
   face="#FFFFFF", cap="#F1F3F6", well="#F7F8FA", edge="#9AA2AD",
   text="#111418", dim="#444B54", faint="#5E656E",
   accent="#0B5FCE", buy="#136B40", sell="#A62E22", run="#136B40",
   btn="#EDEFF3", btnedge="#8E96A2", dealtext="#FFFFFF"),
 "v8": dict(name="Compact Rail",
   face="#22252B", cap="#1B1E23", well="#15181C", edge="#4A505A",
   text="#E6E9EE", dim="#B0B6C0", faint="#8A9099",
   accent="#E0863A", buy="#2F9B66", sell="#C24A3B", run="#4FBE86",
   btn="#2C3037", btnedge="#4C525C", dealtext="#FFFFFF"),
 "v9": dict(name="Green Screen",
   face="#0B1410", cap="#0B1410", well="#08100C", edge="#1E7A3C",
   text="#35E06A", dim="#23B152", faint="#1B8C41",
   accent="#9CFFC0", buy="#35E06A", sell="#35E06A", run="#35E06A",
   btn="#0B1410", btnedge="#1E7A3C", dealtext="#35E06A"),
 "v10": dict(name="Signal Light",
   face="#E8E8E6", cap="#DEDEDB", well="#F4F4F2", edge="#A8A8A4",
   text="#16181A", dim="#45494E", faint="#63686E",
   accent="#1C7A46", buy="#1C7A46", sell="#A83A2C", run="#1C7A46",
   btn="#E0E0DD", btnedge="#9B9B97", dealtext="#FFFFFF"),
}

def rgb(h):
    h = h.lstrip("#")
    return tuple(int(h[i:i+2], 16) for i in (0, 2, 4))

def chan(v):
    v /= 255.0
    return v/12.92 if v <= 0.03928 else ((v+0.055)/1.055)**2.4

def lum(c):
    r, g, b = rgb(c)
    return 0.2126*chan(r) + 0.7152*chan(g) + 0.0722*chan(b)

def cr(a, b):
    la, lb = lum(a), lum(b)
    if la < lb: la, lb = lb, la
    return (la+0.05)/(lb+0.05)

#--- the pairs this panel actually draws, named the way the product names them
PAIRS = [
 ("text","face","text"), ("text","cap","text"), ("text","well","text"),
 ("dim","face","text"),  ("dim","cap","text"),  ("dim","well","text"),
 ("faint","face","text"),("faint","cap","text"),("faint","well","text"),
 ("accent","face","text"),("accent","well","text"),
 ("buy","face","text"),  ("sell","face","text"), ("run","face","text"),
 ("text","btn","text"),
 ("dealtext","buy","text"), ("dealtext","sell","text"),
 ("edge","face","ui"),   ("btnedge","face","ui"),
]

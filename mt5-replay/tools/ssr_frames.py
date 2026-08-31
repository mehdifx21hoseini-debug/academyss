#!/usr/bin/env python3
"""Pull frames out of a screen recording so they can be looked at.

    python3 tools/ssr_frames.py <video> [out_dir] [--every SECONDS] [--max N]

Video cannot be read directly here; still images can. So a recording is
turned into stills at a fixed interval, written as PNG, and read one by
one. Motion is what a video adds over a screenshot, and a strip of stills
keeps most of it: a button pressed, a line dragged, a candle that does or
does not advance between two frames.

The black box CSV is still the better instrument for anything mechanical -
it carries numbers, not pixels. Frames are for what only the eye can
settle: where something is on the screen, and what it looks like.
"""
import sys, os

def main(argv):
    if not argv:
        print(__doc__)
        return 2
    path = argv[0]
    out  = argv[1] if len(argv) > 1 and not argv[1].startswith("--") else "frames"
    every, cap = 2.0, 40
    for i, a in enumerate(argv):
        if a == "--every" and i + 1 < len(argv):
            every = float(argv[i + 1])
        if a == "--max" and i + 1 < len(argv):
            cap = int(argv[i + 1])

    if not os.path.isfile(path):
        print("no such file: %s" % path)
        return 2

    import imageio.v3 as iio
    os.makedirs(out, exist_ok=True)

    meta = iio.immeta(path, plugin="pyav")
    fps  = float(meta.get("fps") or 30.0)
    dur  = float(meta.get("duration") or 0.0)
    print("video: %s" % path)
    print("  %.1f fps, %.1f seconds" % (fps, dur))

    step  = max(1, int(round(fps * every)))
    wrote = 0
    for i, frame in enumerate(iio.imiter(path, plugin="pyav")):
        if i % step:
            continue
        if wrote >= cap:
            print("  stopped at the %d frame cap - raise it with --max" % cap)
            break
        name = os.path.join(out, "f%03d_%06.1fs.png" % (wrote, i / fps))
        iio.imwrite(name, frame)
        print("  %s   %dx%d" % (name, frame.shape[1], frame.shape[0]))
        wrote += 1
    print("%d frame(s) written to %s/" % (wrote, out))
    return 0

if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))

#!/usr/bin/env python3
"""Read an SS Replay black box file and say which layer is stuck.

    python3 tools/ssr_flight.py SSReplay-flight-XAUUSD-20260831-0039.csv

The recorder writes one row every 500 ms carrying the engine, the symbol,
the chart and the view at the same instant. The whole point is that those
four can be compared: five releases were spent unable to tell an engine
that is not running from an engine running into a view that is not
looking, because no single report ever held both numbers.

Verdicts are ordered. The first stuck layer is the only one worth acting
on; everything below it is a consequence, and fixing a consequence is how
this project has repeatedly broken something else.
"""
import sys, csv, io

def read(path):
    meta, rows, events, header = {}, [], [], None
    with io.open(path, "r", encoding="utf-8", errors="replace") as fh:
        for raw in fh:
            line = raw.rstrip("\r\n")
            if not line.strip():
                continue
            if line.startswith("#"):
                bits = line[1:].strip().split(",", 1)
                if len(bits) == 2:
                    meta.setdefault(bits[0].strip(), bits[1].strip())
                continue
            if header is None:
                header = next(csv.reader([line]))
                continue
            cells = next(csv.reader([line]))
            row = dict(zip(header, cells + [""] * (len(header) - len(cells))))
            (events if row.get("kind") == "E" else rows).append(row)
    return meta, rows, events, header

def num(row, key):
    try:
        return float(row.get(key, "") or 0)
    except ValueError:
        return 0.0

def span(rows, key):
    """first and last value of a numeric column, over the whole file."""
    if not rows:
        return (0.0, 0.0)
    return (num(rows[0], key), num(rows[-1], key))

def playing_rows(rows):
    return [r for r in rows if (r.get("playing") or "0").strip() == "1"]

def main(path):
    meta, rows, events, header = read(path)
    if header is None:
        print("not a black box file: no column header found")
        return 2

    print("=== SS Replay black box ===")
    for k in ("build", "terminal", "opened", "origin", "replay_symbol",
              "window", "window_bars", "one_chart", "reused_seed",
              "picked_start", "start_speed", "pump_ms", "origin_m1_bars"):
        if k in meta:
            print("  %-16s %s" % (k, meta[k]))
    print("  %-16s %d samples, %d events" % ("recorded", len(rows), len(events)))

    if events:
        print("\n--- what the user did ---")
        for e in events:
            print("  %s  %s" % (e.get("t", ""), e.get("note", "")))

    if not rows:
        #--- The first real recording landed here: 86 seconds, three
        #--- events, no samples. That said the engine was never driven,
        #--- but not why - so the recorder now names the guard, and this
        #--- reads it back rather than offering the reader a choice of
        #--- two explanations and no way to pick.
        notes = " | ".join(e.get("note", "") for e in events)
        print("\n--- verdict ---")
        print("  NO SAMPLES. The engine was never driven: OnTimer wrote "
              "nothing for the whole recording, so the clock could not "
              "advance and no candle could appear.")
        guard = [e.get("note", "") for e in events
                 if e.get("note", "").startswith("OnTimer turned back at:")]
        fired = any(e.get("note", "").startswith("OnTimer fired")
                    for e in events)
        if guard:
            print("  CAUSE: %s" % guard[0])
        elif fired:
            print("  The timer FIRED but produced no sample and named no "
                  "guard - look between the guards and RecordFlight.")
        elif "timer-entry" in meta.get("markers", ""):
            print("  The timer NEVER FIRED - this build records its first "
                  "entry and there is none. EventSetMillisecondTimer did "
                  "not take effect, or it was killed after being set.")
        else:
            print("  This recording cannot say whether the timer fired and "
                  "was turned back, or never fired at all: it was made by a "
                  "build with no timer marker. A newer recording can.")
        keys = [e for e in events if e.get("note", "").startswith("key ")]
        if keys:
            print("  Note that %d key event(s) DID arrive, so the program "
                  "was alive and OnChartEvent was running. A panel that "
                  "answers while nothing moves is this exact fault."
                  % len(keys))
        return 1

    play = playing_rows(rows)
    print("\n--- layers ---")
    findings = []

    #--- 1. was it ever playing at all?
    if not play:
        findings.append(
            "ENGINE NEVER PLAYED. Not one sample has playing=1, so Play was "
            "never accepted. The candles cannot move; nothing downstream "
            "matters until this does.")
        window = rows
    else:
        window = play
        print("  playing in %d of %d samples" % (len(play), len(rows)))

    def moved(key, label):
        a, b = span(window, key)
        ok = b > a
        print("  %-14s %-12s %s -> %s" %
              (label, "MOVED" if ok else "STUCK",
               int(a) if key != "clock" else window[0].get("clock"),
               int(b) if key != "clock" else window[-1].get("clock")))
        return ok

    clock_a = window[0].get("clock", "")
    clock_b = window[-1].get("clock", "")
    clock_ok = clock_a != clock_b
    print("  %-14s %-12s %s -> %s" %
          ("clock", "MOVED" if clock_ok else "STUCK", clock_a, clock_b))
    pumps_ok = moved("pumps", "pumps")
    ticks_ok = moved("emit_ticks", "emit_ticks")
    bars_ok  = moved("m1", "m1 bars")
    snaps_ok = moved("snaps", "snaps")

    #--- 2. the chart
    last = rows[-1]
    rsym  = (meta.get("replay_symbol") or "").strip()
    csym  = (last.get("chart_sym") or "").strip()
    charts = int(num(last, "charts"))
    print("  %-14s %s" % ("charts", charts))
    if charts:
        print("  %-14s %s %s auto=%s follow=%s first=%s vis=%s off=%s" %
              ("chart", csym, last.get("chart_tf"), last.get("auto"),
               last.get("follow"), last.get("first"), last.get("vis"),
               last.get("off")))
    off_a, off_b = span(window, "off")

    #--- ordered verdicts: the first one is the only one to act on
    if play and not pumps_ok:
        findings.append(
            "THE TIMER IS NOT DRIVING THE ENGINE. playing=1 but the pump "
            "counter never rose, so OnTimer is not reaching the pump - not "
            "the engine's fault and not the chart's.")
    elif play and not ticks_ok:
        findings.append(
            "THE ENGINE EMITS NOTHING. It is playing and being pumped, but "
            "emit_ticks never rose: no ticks are reaching the sink. Look at "
            "the cursor, the future guard, or a market-closed gap - not at "
            "the chart.")
    elif play and ticks_ok and not bars_ok:
        findings.append(
            "TICKS GO IN, BARS DO NOT COME OUT. emit_ticks rose while the "
            "symbol's bar count did not, so CustomTicksAdd is accepting the "
            "call and building nothing - stale tick times, or a symbol whose "
            "history is ahead of the replay cursor.")
    elif charts == 0:
        findings.append(
            "NO CHART IS ON THE REPLAY SYMBOL. Bars are being written where "
            "nobody is looking. Expected %s." % (rsym or "the replay symbol"))
    elif rsym and csym and csym != rsym:
        findings.append(
            "THE CHART IS ON THE WRONG SYMBOL: showing %s, replay is writing "
            "%s. The handover did not complete." % (csym, rsym))
    elif bars_ok and off_b > max(3.0, off_a):
        findings.append(
            "BARS ARE BEING WRITTEN OFF SCREEN. The bar count rises and the "
            "view's distance from the newest bar rises with it (%d -> %d). "
            "The engine is fine; the view is not following."
            % (int(off_a), int(off_b)))
    elif bars_ok and not snaps_ok and (last.get("follow") or "") == "0":
        findings.append(
            "THE VIEW IS DETACHED. New bars arrive but the chart is marked "
            "not-following, so nothing drags it forward. A scroll back was "
            "read as deliberate and never released.")

    print("\n--- verdict ---")
    if findings:
        for i, f in enumerate(findings, 1):
            print("  %d. %s" % (i, f))
        return 1
    if bars_ok and clock_ok:
        print("  Every layer moved: the clock advanced, ticks were emitted, "
              "bars appeared, and the view stayed at the newest bar.")
        print("  If the candles still looked frozen, the fault is in what is "
              "ON the screen, not in what is behind it - send a screenshot "
              "taken at the same time as this file.")
        return 0
    print("  Nothing conclusive. Send the file and the Experts tab together.")
    return 1

if __name__ == "__main__":
    if len(sys.argv) != 2:
        print(__doc__)
        sys.exit(2)
    sys.exit(main(sys.argv[1]))

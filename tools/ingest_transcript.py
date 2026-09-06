#!/usr/bin/env python3
"""RAW ingestion + quality gate for course transcripts.

    python3 tools/ingest_transcript.py FILE [--course intro] [--lesson 3] [--title "..."]

Steps, in order:
  1. copy the file into raw_sources/academy/<course>/ untouched (the raw file is
     never edited, never overwritten — a second copy gets a numeric suffix);
  2. parse SRT/VTT/plain text into cues with timestamps;
  3. score the transcript: how much of it is actual speech versus
     transcription filler ("موسیقی", "[Music]", "نامفهوم", ...);
  4. print a verdict — USABLE / PARTIAL / UNUSABLE — and write a quality report.

A transcript that fails the gate produces no knowledge objects. Inventing
lesson content from an empty transcript is the one thing this project must
never do (MET-RULE-0003).
"""
import argparse
import json
import os
import re
import shutil
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import kb_lib as K  # noqa: E402

FILLER_PATTERNS = [
    r"^موسیقی( موسیقی)*$", r"^\[?\s*موسیقی\s*\]?$", r"^آهنگ$", r"^صدای موسیقی$",
    r"^\[?\s*music\s*\]?$", r"^\(\s*music\s*\)$", r"^♪+$",
    r"^\[?\s*نامفهوم\s*\]?$", r"^\[?\s*سکوت\s*\]?$", r"^\[?\s*inaudible\s*\]?$",
    r"^\[?\s*silence\s*\]?$", r"^\.+$", r"^-+$",
]
FILLER_RE = [re.compile(p, re.IGNORECASE) for p in FILLER_PATTERNS]

TS = re.compile(r"(\d{2}):(\d{2}):(\d{2})[,.](\d{3})")


def is_filler(text):
    t = text.strip()
    return any(r.match(t) for r in FILLER_RE)


def repetition_artifacts(words, min_run=8):
    """Find stuck-token runs: the same word repeated many times in a row.

    Speech-to-text models loop like this on music, noise or long pauses. The
    words are real words, so a filler check never catches them — but the run
    carries no information and must not become knowledge.
    """
    runs, i = [], 0
    while i < len(words):
        j = i
        while j + 1 < len(words) and words[j + 1] == words[i]:
            j += 1
        run = j - i + 1
        if run >= min_run:
            runs.append({"word": words[i], "count": run})
        i = j + 1
    return runs


def to_seconds(ts):
    m = TS.match(ts)
    if not m:
        return None
    h, mi, s, ms = (int(x) for x in m.groups())
    return h * 3600 + mi * 60 + s + ms / 1000.0


def parse_srt(text):
    cues, block = [], []
    for raw in text.replace("\r\n", "\n").split("\n"):
        if raw.strip() == "":
            if block:
                cues.append(block)
                block = []
        else:
            block.append(raw)
    if block:
        cues.append(block)

    parsed = []
    for block in cues:
        idx, start, end, lines = None, None, None, []
        for line in block:
            if "-->" in line:
                left, _, right = line.partition("-->")
                start, end = to_seconds(left.strip()), to_seconds(right.strip())
            elif re.match(r"^\d+$", line.strip()) and start is None and idx is None:
                idx = int(line.strip())
            else:
                lines.append(line.strip())
        text_line = " ".join(x for x in lines if x)
        if text_line:
            parsed.append({"index": idx if idx is not None else len(parsed) + 1,
                           "start": start, "end": end, "text": text_line})
    return parsed


def parse_plain(text):
    return [{"index": i + 1, "start": None, "end": None, "text": line.strip()}
            for i, line in enumerate(text.splitlines()) if line.strip()]


def slugify(name, course, lesson):
    base = "lesson_%s" % lesson if lesson else os.path.splitext(os.path.basename(name))[0]
    base = re.sub(r"[^A-Za-z0-9_-]+", "_", base).strip("_").lower() or "part"
    return "%s_%s" % (course, base)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("file")
    ap.add_argument("--course", default="incoming",
                    help="intro | advanced | psychology | incoming (default)")
    ap.add_argument("--lesson", default="", help="شماره جلسه")
    ap.add_argument("--title", default="", help="عنوان جلسه")
    args = ap.parse_args()

    if not os.path.isfile(args.file):
        print("file not found: %s" % args.file)
        return 2

    with open(args.file, "r", encoding="utf-8", errors="replace") as fh:
        text = fh.read()

    ext = os.path.splitext(args.file)[1].lower()
    cues = parse_srt(text) if ext in (".srt", ".vtt") else parse_plain(text)

    # 1. archive the raw file, never overwriting an existing one
    raw_dir = os.path.join(K.ROOT, "raw_sources", "academy", args.course)
    os.makedirs(raw_dir, exist_ok=True)
    slug = slugify(args.file, args.course, args.lesson)
    dest = os.path.join(raw_dir, slug + ext)
    n = 1
    while os.path.exists(dest):
        dest = os.path.join(raw_dir, "%s_%02d%s" % (slug, n, ext))
        n += 1
    shutil.copy2(args.file, dest)

    # 2. score it
    total = len(cues)
    filler = sum(1 for c in cues if is_filler(c["text"]))
    speech = total - filler
    speech_cues = [c for c in cues if not is_filler(c["text"])]
    words = " ".join(c["text"] for c in speech_cues).split()
    unique_words = len(set(words))
    runs = repetition_artifacts(words)
    artifact_words = sum(r["count"] for r in runs)
    artifact_ratio = (artifact_words / len(words)) if words else 0.0
    duration = max((c["end"] or 0) for c in cues) if cues and cues[-1]["end"] else 0
    speech_ratio = (speech / total) if total else 0.0

    if speech_ratio < 0.10 or unique_words < 20:
        verdict, reason = "UNUSABLE", "متن گفتاری قابل استفاده‌ای در فایل وجود ندارد."
    elif artifact_ratio > 0.25:
        verdict, reason = "UNUSABLE", "بخش عمده‌ی فایل تکرار مصنوعی مدل تبدیل گفتار به متن است."
    elif speech_ratio < 0.60 or unique_words < 200 or artifact_ratio > 0.05:
        verdict, reason = "PARTIAL", ("محتوای واقعی وجود دارد اما کیفیت تبدیل گفتار به متن پایین است؛ "
                                      "استخراج باید محافظه‌کارانه و همراه با نقل‌قول اصلی انجام شود.")
    else:
        verdict, reason = "USABLE", "کیفیت برای پردازش کافی است."

    repeated = {}
    for c in cues:
        repeated[c["text"]] = repeated.get(c["text"], 0) + 1
    top_repeated = sorted(repeated.items(), key=lambda kv: -kv[1])[:5]

    record = {
        "ingest_type": "academy_course_transcript",
        "slug": slug,
        "course": args.course,
        "lesson": args.lesson or None,
        "title": args.title or None,
        "original_filename": os.path.basename(args.file),
        "raw_file": K.rel(dest),
        "ingested_at": K.now_iso(),
        "ingester": "tools/ingest_transcript.py",
        "metrics": {
            "cues": total,
            "filler_cues": filler,
            "speech_cues": speech,
            "speech_ratio": round(speech_ratio, 4),
            "words": len(words),
            "unique_words": unique_words,
            "repetition_artifact_words": artifact_words,
            "repetition_artifact_ratio": round(artifact_ratio, 4),
            "repetition_runs": sorted(runs, key=lambda r: -r["count"])[:10],
            "duration_seconds": round(duration, 1),
            "duration_hhmm": "%02d:%02d" % (int(duration // 3600), int((duration % 3600) // 60)),
            "top_repeated_lines": [{"text": t, "count": c} for t, c in top_repeated],
        },
        "verdict": verdict,
        "verdict_reason": reason,
        "cues": cues,
    }
    ingest_path = os.path.join(raw_dir, slug + ".ingest.json")
    n = 1
    while os.path.exists(ingest_path):
        ingest_path = os.path.join(raw_dir, "%s_%02d.ingest.json" % (slug, n))
        n += 1
    K.dump_json(ingest_path, record)

    report = dict(record)
    report.pop("cues")
    report["report_type"] = "transcript_quality"
    K.write_versioned_snapshot(K.REPORT_DIR, "transcript_quality_" + slug, report)

    print("raw archived : %s" % K.rel(dest))
    print("ingest record: %s" % K.rel(ingest_path))
    print("duration     : %s  cues: %d (گفتار %d / پرکننده %d)" %
          (record["metrics"]["duration_hhmm"], total, speech, filler))
    print("speech ratio : %.1f%%   unique words: %d" % (speech_ratio * 100, unique_words))
    print("artifacts    : %.1f%% از کلمات، %d رشته‌ی تکراری%s" % (
        artifact_ratio * 100, len(runs),
        ("  بیشترین: «%s» ×%d" % (runs[0]["word"], runs[0]["count"])) if runs else ""))
    print("VERDICT      : %s — %s" % (verdict, reason))
    if verdict == "UNUSABLE":
        print("هیچ شیء دانشی از این فایل ساخته نمی‌شود.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

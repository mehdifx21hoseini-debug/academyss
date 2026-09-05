#!/usr/bin/env python3
"""Export the validated Knowledge Base to human-readable and portable formats.

Rules honoured here:
  * exports are versioned and never silently overwritten (a re-run with
    unchanged content is a no-op, changed content gets the next vNNN);
  * every exported object keeps its provenance and approval state visible;
  * the export is self-contained: the user can keep exports/ on its own,
    without this repository.
"""
import csv
import hashlib
import io
import os
import sys

sys.path.insert(0, __file__.rsplit("/", 1)[0])
import kb_lib as K  # noqa: E402

INDEX_PATH = os.path.join(K.EXPORT_DIR, "export_index.json")

DOMAIN_DIR = {
    "academy": "academy",
    "mentor_qa": "mentor_qa",
    "metatrader": "metatrader",
    "brokers": "brokers",
    "general_trading": "general_trading",
    "psychology": "psychology",
    "meta": "reports",
}

# collections whose export location is fixed by the required export layout
COLLECTION_DIR = {
    "conflict_registry": "conflicts",
    "metatrader_mt4_core": "metatrader/mt4",
    "metatrader_mt5_core": "metatrader/mt5",
}

FA = {
    "authority_level": "سطح اعتبار", "approval_status": "وضعیت تأیید",
    "lifecycle_status": "چرخه‌ی عمر", "platform_scope": "دامنه‌ی پلتفرم",
    "object_type": "نوع", "confidence": "اطمینان",
}

LIST_FIELDS = [
    ("steps", "مراحل", True), ("conditions", "شرط‌ها", False), ("exceptions", "استثناها", False),
    ("symptoms", "نشانه‌ها", False), ("causes", "علت‌ها", False), ("resolutions", "راه‌حل‌ها", True),
    ("examples", "مثال‌ها", False), ("invalid_examples", "مثال‌های نادرست", False),
    ("common_mistakes", "اشتباهات رایج", False), ("warnings", "هشدارها", False),
    ("related_questions", "سؤال‌های مرتبط دانشجو", False),
]


def load_index():
    return K.load_json(INDEX_PATH) if os.path.exists(INDEX_PATH) else {}


def sha(text):
    return hashlib.sha256(text.encode("utf-8")).hexdigest()[:16]


def md_object(o):
    out = ["### %s  `%s`" % (o.get("title", o["id"]), o["id"])]
    src = o.get("source", {})
    meta = "**%s:** %s | **%s:** %s | **%s:** %s" % (
        FA["object_type"], o.get("object_type", "-"),
        FA["authority_level"], o.get("authority_level", "-"),
        FA["approval_status"], o.get("approval_status", "-"))
    if o.get("platform_scope") and o["platform_scope"] != "NOT_APPLICABLE":
        meta += " | **%s:** %s" % (FA["platform_scope"], o["platform_scope"])
    meta += " | **%s:** %s" % (FA["confidence"], o.get("confidence", "-"))
    out.append(meta)
    out.append("**منبع:** `%s`%s" % (
        src.get("source_ref", "-"),
        (" → " + src.get("source_location")) if src.get("source_location") else ""))
    if o.get("verification_required"):
        out.append("> ⚠️ **تأییدنشده:** %s" % o.get("verification_note", "نیازمند بازبینی انسانی."))
    out.append("")
    out.append(o.get("chunk_text", ""))
    for key, label in (("definition", "تعریف"), ("rule", "قاعده"), ("summary", "خلاصه")):
        if o.get(key) and o[key] not in o.get("chunk_text", ""):
            out.append("")
            out.append("**%s:** %s" % (label, o[key]))
    for key, label, numbered in LIST_FIELDS:
        vals = o.get(key) or []
        if vals:
            out.append("")
            out.append("**%s:**" % label)
            for i, v in enumerate(vals):
                out.append(("%d. " % (i + 1) if numbered else "- ") + v)
    if o.get("comparison"):
        out.append("")
        out.append("| پلتفرم | رفتار |")
        out.append("|---|---|")
        for k, v in o["comparison"].items():
            out.append("| %s | %s |" % (k.upper(), v))
    if o.get("keywords"):
        out.append("")
        out.append("*کلیدواژه‌ها: %s*" % "، ".join(o["keywords"]))
    out.append("")
    return "\n".join(out)


def md_mentor_qa(o):
    return "\n".join([
        "### %s  `%s`" % (o.get("question_normalized", o["id"]), o["id"]),
        "**موضوع:** %s | **%s:** %s | **%s:** %s" % (
            o.get("topic", "-"), FA["authority_level"], o.get("authority_level", "-"),
            FA["approval_status"], o.get("approval_status", "-")),
        "**منبع:** `%s` → %s" % (o.get("source", {}).get("source_ref", "-"),
                                 o.get("source", {}).get("source_location", "-")),
        "", "**پرسش دانشجو:** " + o.get("question_raw", ""),
        "", "**پاسخ ساختاریافته:** " + o.get("answer_structured", ""), ""])


def md_conflict(o):
    return "\n".join([
        "### %s  `%s`" % (o["topic"], o["id"]),
        "**وضعیت:** %s | **اولویت:** %s | **نیاز به تصمیم انسانی:** %s" % (
            o["status"], o.get("review_priority", "-"),
            "بله" if o.get("requires_human_review") else "خیر"),
        "", "**طرف الف** (`%s`، %s): %s" % (o["side_a"]["object_id_or_source"],
                                            o["side_a"]["authority_level"], o["side_a"]["statement"]),
        "", "**طرف ب** (`%s`، %s): %s" % (o["side_b"]["object_id_or_source"],
                                          o["side_b"]["authority_level"], o["side_b"]["statement"]),
        "", "**توضیح احتمالی:** " + (o.get("possible_explanation") or "-"),
        "", "**اثر بر پاسخ‌گویی:** " + (o.get("impact") or "-"), ""])


def md_review(o):
    lines = ["### %s  `%s`" % (o["title"], o["id"]),
             "**اولویت:** %s | **دامنه:** %s | **وضعیت:** %s" % (
                 o["priority"], o.get("domain", "-"), o["status"]),
             "", "**چرا مطرح شده:** " + o["reason"],
             "", "**سؤال از شما:** " + (o.get("question_for_human") or "-")]
    if o.get("options"):
        lines += ["", "**گزینه‌ها:**"] + ["- " + x for x in o["options"]]
    if o.get("recommendation"):
        lines += ["", "**پیشنهاد ما:** " + o["recommendation"]]
    lines.append("")
    return "\n".join(lines)


RENDER = {"knowledge_object": md_object, "mentor_qa": md_mentor_qa,
          "conflict_record": md_conflict, "review_item": md_review}


def render_markdown(data, kind):
    head = [
        "# %s" % data.get("title", data["collection_id"]),
        "",
        "> %s" % (data.get("description") or ""),
        "",
        "| | |", "|---|---|",
        "| شناسه‌ی مجموعه | `%s` |" % data["collection_id"],
        "| دامنه | %s |" % data.get("domain"),
        "| نسخه | %s |" % data.get("version"),
        "| مرحله‌ی پردازش | %s |" % data.get("pipeline_stage"),
        "| تعداد رکورد | %d |" % len(data.get("objects", [])),
        "| تاریخ تولید | %s |" % data.get("generated_at"),
        "| فایل‌های منبع | %s |" % "، ".join("`%s`" % s for s in data.get("source_files", [])),
        "",
    ]
    if data.get("notes"):
        head += ["**یادداشت‌ها:**"] + ["- " + n for n in data["notes"]] + [""]
    head += ["---", ""]
    body = [RENDER[kind](o) for o in data.get("objects", [])]
    return "\n".join(head) + "\n".join(body)


def write_versioned(directory, base, ext, content, index, key):
    """Write only when the content changed; never overwrite an existing version."""
    digest = sha(content)
    history = index.setdefault(key, [])
    if history and history[-1]["sha"] == digest:
        return None, history[-1]["version"]
    version = K.next_version(directory, base, ext)
    path = os.path.join(directory, "%s_%s%s" % (base, version, ext))
    K.write_text(path, content)
    history.append({"version": version, "sha": digest, "file": K.rel(path),
                    "generated_at": K.now_iso()})
    return path, version


def main():
    index = load_index()
    written = []
    csv_rows = []
    glossary_rows = []

    for path in K.iter_collection_files():
        data = K.load_json(path)
        kind = K.record_kind(path)
        domain_dir = DOMAIN_DIR.get(data.get("domain"), "reports")
        out_dir = os.path.join(K.EXPORT_DIR,
                               COLLECTION_DIR.get(data["collection_id"], domain_dir))
        base = data["collection_id"]

        md_path, md_version = write_versioned(out_dir, base, ".md",
                                              render_markdown(data, kind), index, base + ".md")
        json_text = None
        import json as _json
        json_text = _json.dumps(data, ensure_ascii=False, indent=2) + "\n"
        js_path, _ = write_versioned(out_dir, base, ".json", json_text, index, base + ".json")
        if md_path:
            written.append((K.rel(md_path), md_version))
        if js_path:
            written.append((K.rel(js_path), md_version))

        for o in data.get("objects", []):
            src = o.get("source", {})
            row = {
                "id": o.get("id"),
                "title": o.get("title") or o.get("question_normalized") or o.get("topic"),
                "domain": o.get("domain") or data.get("domain"),
                "object_type": o.get("object_type") or kind.upper(),
                "authority_level": o.get("authority_level", ""),
                "approval_status": o.get("approval_status") or o.get("status", ""),
                "lifecycle_status": o.get("lifecycle_status", ""),
                "platform_scope": o.get("platform_scope", ""),
                "confidence": o.get("confidence", ""),
                "verification_required": o.get("verification_required", ""),
                "source_ref": src.get("source_ref", ""),
                "source_location": src.get("source_location", ""),
                "keywords": "|".join(o.get("keywords", []) or []),
                "collection_file": K.rel(path),
            }
            csv_rows.append(row)
            if o.get("object_type") in ("GLOSSARY", "DEFINITION"):
                glossary_rows.append({
                    "id": o["id"], "term_fa": o.get("title", ""), "term_en": o.get("title_en", ""),
                    "definition": o.get("definition", ""), "domain": o.get("domain", ""),
                    "authority_level": o.get("authority_level", ""),
                    "approval_status": o.get("approval_status", ""),
                })

    def to_csv(rows, fields):
        buf = io.StringIO()
        w = csv.DictWriter(buf, fieldnames=fields, extrasaction="ignore")
        w.writeheader()
        w.writerows(rows)
        return buf.getvalue()

    idx_csv = to_csv(sorted(csv_rows, key=lambda r: r["id"]), list(csv_rows[0].keys()))
    p, v = write_versioned(os.path.join(K.EXPORT_DIR, "reports"), "kb_index", ".csv",
                           idx_csv, index, "kb_index.csv")
    if p:
        written.append((K.rel(p), v))

    if glossary_rows:
        g_csv = to_csv(sorted(glossary_rows, key=lambda r: r["id"]), list(glossary_rows[0].keys()))
        p, v = write_versioned(os.path.join(K.EXPORT_DIR, "glossary"), "glossary", ".csv",
                               g_csv, index, "glossary.csv")
        if p:
            written.append((K.rel(p), v))

    K.dump_json(INDEX_PATH, index)
    print("exported %d file(s)" % len(written))
    for f, v in written:
        print("  %s (%s)" % (f, v))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

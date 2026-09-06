#!/usr/bin/env python3
"""Build the master knowledge manifest: the map of the whole Knowledge Base."""
import os
import sys

sys.path.insert(0, __file__.rsplit("/", 1)[0])
import kb_lib as K  # noqa: E402


def bump(d, key):
    if key is None:
        key = "<unset>"
    d[key] = d.get(key, 0) + 1


def main():
    collections = []
    totals = {
        "objects": 0, "by_domain": {}, "by_object_type": {}, "by_authority": {},
        "by_approval": {}, "by_lifecycle": {}, "by_platform_scope": {}, "by_source_type": {},
    }
    open_conflicts = []
    open_reviews = []
    verification_pending = 0

    for path in K.iter_collection_files():
        data = K.load_json(path)
        kind = K.record_kind(path)
        objs = data.get("objects", [])
        collections.append({
            "collection_id": data.get("collection_id"),
            "title": data.get("title"),
            "domain": data.get("domain"),
            "record_kind": kind,
            "version": data.get("version"),
            "pipeline_stage": data.get("pipeline_stage"),
            "file": K.rel(path),
            "object_count": len(objs),
            "source_files": data.get("source_files", []),
        })
        for o in objs:
            totals["objects"] += 1
            bump(totals["by_domain"], o.get("domain") or data.get("domain"))
            bump(totals["by_object_type"], o.get("object_type") or kind.upper())
            bump(totals["by_authority"], o.get("authority_level"))
            bump(totals["by_approval"], o.get("approval_status"))
            bump(totals["by_lifecycle"], o.get("lifecycle_status"))
            bump(totals["by_platform_scope"], o.get("platform_scope"))
            bump(totals["by_source_type"], (o.get("source") or {}).get("source_type"))
            if o.get("verification_required"):
                verification_pending += 1
            if kind == "conflict_record" and o.get("status") == "OPEN":
                open_conflicts.append({"id": o["id"], "topic": o["topic"],
                                       "priority": o.get("review_priority")})
            if kind == "review_item" and o.get("status") == "OPEN":
                open_reviews.append({"id": o["id"], "title": o["title"],
                                     "priority": o.get("priority"), "domain": o.get("domain")})

    coverage = {
        "academy_course_material": {"state": "MISSING", "note": "هیچ ترنسکریپت یا سند دوره‌ای دریافت نشده (RQ-0001)."},
        "academy_methodology": {"state": "MISSING", "note": "سند متدولوژی رسمی وجود ندارد (RQ-0008)."},
        "academy_catalog": {"state": "PARTIAL", "note": "از سایت استخراج شد؛ نیازمند تأیید (RQ-0005)."},
        "mentor_qa": {"state": "MISSING", "note": "دیتاست گفت‌وگو دریافت نشده (RQ-0002)."},
        "metatrader_mt4": {"state": "SEED", "note": "نمونه‌ی اولیه، تأییدنشده (RQ-0007)."},
        "metatrader_mt5": {"state": "SEED", "note": "نمونه‌ی اولیه، تأییدنشده (RQ-0007)."},
        "brokers": {"state": "MISSING", "note": "بروکر مشخص نشده (RQ-0004)."},
        "psychology": {"state": "SEED", "note": "دوره‌ی روان‌شناسی آکادمی دریافت نشده (RQ-0003)."},
        "general_trading": {"state": "SEED", "note": "واژه‌نامه‌ی پایه ساخته شد؛ تأییدنشده."},
    }

    manifest = {
        "manifest_type": "mentorai_knowledge_base",
        "version": "v000",
        "generated_at": K.now_iso(),
        "generator": "tools/kb_build_manifest.py",
        "schema_versions": {"enums": K.enums()["version"]},
        "totals": totals,
        "verification_pending": verification_pending,
        "collections": collections,
        "open_conflicts": open_conflicts,
        "open_review_items": open_reviews,
        "source_coverage": coverage,
    }
    version, changed = K.write_versioned_snapshot(
        K.MANIFEST_DIR, "knowledge_manifest", manifest,
        extra_copy_dir=os.path.join(K.EXPORT_DIR, "manifests") if True else None)
    print("manifest %s (%s): collections=%d objects=%d open_conflicts=%d open_reviews=%d" %
          (version, "updated" if changed else "unchanged", len(collections),
           totals["objects"], len(open_conflicts), len(open_reviews)))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

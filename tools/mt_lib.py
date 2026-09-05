"""Shared builders for the MetaTrader domain seeds.

Everything in this domain is written offline: this container has no egress to
the MetaQuotes documentation, so each record is MODEL_DRAFT /
PENDING_VERIFICATION and carries the same explicit verification note. Menu
paths, error strings and numeric limits must be checked against the official
help and the broker's current build before anything here becomes APPROVED.
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import kb_lib as K  # noqa: E402

NOW = K.now_iso()

# set by each seed module before building, so provenance points at the real file
SOURCE = "tools/"

VERIFY = ("نوشته‌شده بر پایه‌ی دانش عمومی از پلتفرم، بدون دسترسی به مستندات رسمی MetaQuotes "
          "(شبکه‌ی خروجی در محیط پردازش مسدود بود). مسیر منوها، پیام‌های خطا و محدودیت‌ها باید "
          "با راهنمای رسمی و بیلد فعلی پلتفرم تطبیق داده شود.")

VERIFY_BROKER = ("مقدار دقیق این مورد را بروکر تعیین می‌کند و بین حساب‌ها متفاوت است. "
                 "عدد مشخص فقط پس از دریافت مستندات بروکر (RQ-0004) قابل ثبت است.")

NOTES = ["ساخته‌شده به‌صورت خودکار توسط ابزارهای tools/seed_mt_*.py — دستی ویرایش نشود.",
         "همه‌ی رکوردها PENDING_VERIFICATION هستند و باید با مستندات رسمی MetaQuotes تطبیق داده شوند."]


def obj(oid, otype, title, chunk, scope, conf, **kw):
    """One MetaTrader knowledge object with the domain's fixed provenance stance."""
    broker_dependent = scope == "BROKER_DEPENDENT"
    o = {
        "id": oid,
        "object_type": otype,
        "domain": "metatrader",
        "title": title,
        "language": "fa-en",
        "chunk_text": chunk,
        "source": {"source_type": "MODEL_DRAFT",
                   "source_ref": kw.pop("source_ref", SOURCE),
                   "source_location": oid},
        "authority_level": "GENERAL_KNOWLEDGE",
        "methodology_scope": "PLATFORM_OPERATION",
        "platform_scope": scope,
        "approval_status": "PENDING_VERIFICATION",
        "lifecycle_status": "PENDING_REVIEW",
        "verification_required": True,
        "verification_note": VERIFY + ((" " + VERIFY_BROKER) if broker_dependent else ""),
        "confidence": conf,
        "version": "v001",
        "created_at": NOW,
        "updated_at": NOW,
    }
    o.update(kw)
    return o


def write(path, cid, title, desc, objs, extra_notes=()):
    changed = K.write_collection(path, {
        "collection_id": cid, "domain": "metatrader", "title": title, "description": desc,
        "version": "v001", "generated_at": NOW, "pipeline_stage": "STRUCTURED",
        "source_files": [SOURCE],
        "notes": list(NOTES) + list(extra_notes), "objects": objs,
    })
    print("%s %s objects: %d" % ("wrote" if changed else "unchanged", K.rel(path), len(objs)))

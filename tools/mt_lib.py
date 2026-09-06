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
         "رکوردهای بدون شاهد، PENDING_VERIFICATION می‌مانند و باید با پلتفرم تطبیق داده شوند."]

# What a record verified against the owner's own terminal is allowed to become.
#
# The content is still general platform knowledge, not something the Academy
# taught — so it does not become ACADEMY_PRIMARY. But its correctness is now
# attested by the Academy owner against the broker the Academy actually uses,
# which is exactly what ACADEMY_DERIVED means, and what lets the mentor answer
# from it instead of referring the student to support.
SEEN = ("تأییدشده با ۹ اسکرین‌شات از ترمینال‌های خودِ مالک آکادمی (WM Markets Ltd، "
        "دو حساب دمو، ۶ سپتامبر ۲۰۲۶): متاتریدر ۵ — منوهای File و View و Insert، "
        "پنجره‌ی Options، Properties چارت، پنجره‌ی New Order، Specification نماد، "
        "Market Watch، Navigator، Toolbox و پوشه‌ی داده؛ متاتریدر ۴ — منوهای File و "
        "Insert، contract specification، Market Watch، نوار ابزار و پوشه‌ی داده.")


# Reviewed, as opposed to observed. The owner read the record's own text and
# said it is correct — no screenshot involved. That is a different kind of
# evidence from PLATFORM_OBSERVED and gets its own source type, so a later
# reader can tell which records were checked against a screen and which were
# checked against a person's knowledge of their own platform.
REVIEWED = ("متن این رکورد را مالک آکادمی خواند و تأیید کرد "
            "(برگه‌ی بازبینی دانش متاتریدر، ۶ سپتامبر ۲۰۲۶). "
            "برخلاف رکوردهای PLATFORM_OBSERVED، این تأیید بر پایه‌ی دانش خود مالک از "
            "پلتفرم است، نه تطبیق با اسکرین‌شات.")


def obj(oid, otype, title, chunk, scope, conf, **kw):
    """One MetaTrader knowledge object with the domain's fixed provenance stance.

    Pass verified="what the screenshot showed" for a record whose claims were
    checked against a real terminal. Everything else stays PENDING_VERIFICATION,
    which is the honest default for a domain written without the docs.
    """
    verified = kw.pop("verified", None)
    reviewed = kw.pop("reviewed", None)
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
    if reviewed and not verified:
        o["source"] = {
            "source_type": "ACADEMY_REVIEWED",
            "source_ref": "برگه‌ی بازبینی دانش متاتریدر — تأیید مالک آکادمی، ۲۰۲۶-۰۹-۰۶",
            "source_location": oid,
            "observed_at": "2026-09-06",
            "drafted_from": SOURCE,
        }
        o["authority_level"] = "ACADEMY_DERIVED"
        o["approval_status"] = "APPROVED"
        o["lifecycle_status"] = "ACTIVE"
        o["verification_required"] = False
        o["verification_note"] = REVIEWED + ("" if reviewed is True else " " + str(reviewed))
        o["confidence"] = 1.0
        o["version"] = "v002"
    if verified:
        # The source changes, not just the flag. A record I drafted cannot
        # become official by relabelling — the validator is right to refuse
        # that. What makes it official is that the claim was then OBSERVED in a
        # real terminal, so that observation becomes the source of record.
        o["source"] = {
            "source_type": "PLATFORM_OBSERVED",
            "source_ref": "اسکرین‌شات‌های ترمینال مالک آکادمی — ۲۰۲۶-۰۹-۰۶",
            "source_location": oid,
            "platform": "MetaTrader 5",
            "broker": "WM Markets Ltd (حساب دمو، نوع Hedge)",
            "observed_at": "2026-09-06",
            "drafted_from": SOURCE,
        }
        o["authority_level"] = "ACADEMY_DERIVED"
        o["approval_status"] = "APPROVED"
        o["lifecycle_status"] = "ACTIVE"
        o["verification_required"] = False
        o["verification_note"] = SEEN + " " + verified
        o["confidence"] = 1.0
        o["version"] = "v002"
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

#!/usr/bin/env python3
"""Owner-confirmed clarifications that resolve conflicts between lessons.

When two lessons say things that look contradictory, the KB keeps both and
opens a CONFLICT_RECORD. Once the project owner rules on it, the ruling is
written to MENTORAI_KB_DECISIONS.md and the single clean answer lands here, so
retrieval returns one unambiguous record instead of two competing quotes.
"""
import sys

sys.path.insert(0, __file__.rsplit("/", 1)[0])
import kb_lib as K  # noqa: E402

NOW = K.now_iso()

OBJECTS = [{
    "id": "ACA-CLR-0001",
    "object_type": "OPERATIONAL_FACT",
    "domain": "academy",
    "category": "رفع ابهام",
    "title": "آیا برای کار در فارکس فیلترشکن لازم است؟",
    "language": "fa",
    "summary": "برای سایت بروکر ممکن است لازم باشد؛ برای اتصال متاتریدر و انجام معامله لازم نیست.",
    "chunk_text": (
        "پاسخ به این پرسش دو بخش دارد و نباید با هم قاطی شود. "
        "۱) برای باز کردن وب‌سایت و کابین معاملاتی بروکر، ممکن است به فیلترشکن نیاز داشته باشید. "
        "نوع فیلترشکن اهمیتی ندارد و لازم نیست IP ثابت باشد — برخلاف چیزی که کاربران ارز دیجیتال به "
        "آن عادت دارند. "
        "۲) برای اتصال پلتفرم متاتریدر به سرور بروکر و انجام معامله، فیلترشکن لازم نیست. "
        "بنابراین جمله‌ی «برای ترید کردن باید فیلترشکن روشن باشد» درست نیست."
    ),
    "conditions": ["دسترسی به سایت بروکر به شرایط شبکه‌ی کاربر بستگی دارد و ممکن است تغییر کند."],
    "source": {
        "source_type": "ACADEMY_DOCUMENT",
        "source_ref": "MENTORAI_KB_DECISIONS.md",
        "source_location": "D-0003",
        "author": "مالک پروژه",
    },
    "authority_level": "ACADEMY_DERIVED",
    "methodology_scope": "ACADEMY_OPERATIONS",
    "platform_scope": "BOTH",
    "approval_status": "APPROVED",
    "lifecycle_status": "ACTIVE",
    "confidence": 1.0,
    "version": "v001",
    "keywords": ["فیلترشکن", "VPN", "سایت بروکر", "اتصال متاتریدر", "IP ثابت"],
    "related_concepts": ["ACA-INT-0039", "ACA-INT-0078"],
    "conflicts": ["CONF-0003"],
    "related_questions": ["برای ترید فیلترشکن لازمه؟", "سایت بروکر باز نمی‌شه چیکار کنم؟",
                          "IP ثابت لازمه؟", "با فیلترشکن معامله کنم مشکلی پیش میاد؟"],
    "created_at": NOW, "updated_at": NOW,
}]

changed = K.write_collection(K.KB_DIR + "/academy/operations/clarifications.json", {
    "collection_id": "academy_clarifications",
    "domain": "academy",
    "title": "رفع ابهام‌های تأییدشده",
    "description": ("پاسخ‌های یکپارچه به مواردی که در جلسات مختلف متفاوت بیان شده‌اند و مالک پروژه "
                    "درباره‌شان تصمیم گرفته است. این رکوردها بر نقل‌قول‌های جلسات اولویت دارند."),
    "version": "v001", "generated_at": NOW, "pipeline_stage": "VALIDATED",
    "source_files": ["MENTORAI_KB_DECISIONS.md"],
    "notes": ["هر رکورد اینجا باید به یک تصمیم ثبت‌شده در دفتر تصمیم‌ها و یک CONFLICT_RECORD وصل باشد."],
    "objects": OBJECTS,
})
print("%s academy/operations/clarifications.json objects: %d" % ("wrote" if changed else "unchanged", len(OBJECTS)))

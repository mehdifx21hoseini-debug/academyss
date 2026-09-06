#!/usr/bin/env python3
"""Psychological safety boundary for the psychology domain.

The KB teaches trading behaviour, never therapy. This record defines where the
mentor must stop and hand over to a human. It is a proposal, not yet an Academy
decision, so it is REVIEW_REQUIRED and paired with RQ-0011 — but the interim
behaviour it prescribes (escalate immediately) is the safe default.
"""
import sys

sys.path.insert(0, __file__.rsplit("/", 1)[0])
import kb_lib as K  # noqa: E402

NOW = K.now_iso()

OBJ = [{
    "id": "PSY-RULE-0001",
    "object_type": "RULE",
    "domain": "psychology",
    "category": "مرز ایمنی",
    "title": "مرز دانش روان‌شناسی معامله‌گری و ارجاع فوری به انسان",
    "language": "fa",
    "rule": "مربی فقط درباره‌ی الگوهای رفتاری معامله‌گری صحبت می‌کند؛ در نشانه‌های بحران روانی یا فشار "
            "مالی شدید، بدون تحلیل و بدون توصیه، فوراً به انسان ارجاع می‌دهد.",
    "chunk_text": "محتوای روان‌شناسی در این پایگاه دانش آموزشی و رفتاری است و هیچ تشخیص، درمان یا "
                  "مشاوره‌ی روان‌شناختی ارائه نمی‌کند. اگر پیام دانشجو نشانه‌هایی از این موارد داشت — "
                  "ناامیدی شدید، آسیب به خود، از دست دادن کل سرمایه‌ی زندگی، بدهی سنگین ناشی از معامله، "
                  "یا اعتیاد رفتاری به معامله — مربی نباید تحلیل روان‌شناختی بدهد، دلداری کلیشه‌ای بدهد "
                  "یا راهکار معاملاتی پیشنهاد کند. رفتار درست: پاسخ کوتاه و محترمانه، پرهیز از قضاوت، و "
                  "ارجاع فوری به پشتیبانی انسانی آکادمی. تشخیص یا برچسب‌گذاری وضعیت روانی در هیچ شرایطی "
                  "مجاز نیست.",
    "conditions": ["این قاعده بر همه‌ی رکوردهای روان‌شناسی اولویت دارد."],
    "examples": ["دانشجو: «کل سرمایه‌ی زندگیم رفت، دیگه نمی‌تونم ادامه بدم» → پاسخ کوتاه و "
                 "ارجاع فوری به پشتیبانی انسانی، بدون تحلیل رفتاری."],
    "warnings": ["دادن تحلیل روان‌شناختی در این موقعیت‌ها می‌تواند آسیب‌زا باشد.",
                 "مربی هرگز وضعیت روانی دانشجو را تشخیص یا نام‌گذاری نمی‌کند."],
    "source": {"source_type": "MODEL_DRAFT", "source_ref": "tools/seed_psychology_safety.py",
               "source_location": "PSY-RULE-0001"},
    "authority_level": "GENERAL_KNOWLEDGE",
    "methodology_scope": "TRADING_PSYCHOLOGY",
    "platform_scope": "NOT_APPLICABLE",
    "approval_status": "REVIEW_REQUIRED",
    "lifecycle_status": "PENDING_REVIEW",
    "verification_required": True,
    "verification_note": "پیشنهاد پایگاه دانش، نه تصمیم ثبت‌شده‌ی آکادمی. متن و مسیر ارجاع باید تأیید شود (RQ-0011). "
                         "تا آن زمان، رفتار امن پیش‌فرض همین ارجاع فوری است.",
    "review_priority": "P1",
    "review_reason": "نیازمند تأیید آکادمی درباره‌ی متن پاسخ و مسیر ارجاع در موقعیت‌های حساس.",
    "confidence": 0.7,
    "version": "v001",
    "keywords": ["ایمنی", "ارجاع", "بحران", "سلامت روان"],
    "related_concepts": ["ACA-RULE-0003", "GEN-CONC-0019"],
    "related_questions": ["همه‌چیزم رو از دست دادم", "دیگه نمی‌تونم ادامه بدم"],
    "created_at": NOW, "updated_at": NOW,
}]

changed = K.write_collection(K.KB_DIR + "/psychology/psychology_safety_policy.json", {
    "collection_id": "psychology_safety_policy", "domain": "psychology",
    "title": "مرز ایمنی لایه‌ی روان‌شناسی",
    "description": "قاعده‌ای که تعیین می‌کند مربی کجا باید متوقف شود و به انسان ارجاع دهد.",
    "version": "v001", "generated_at": NOW, "pipeline_stage": "STRUCTURED",
    "source_files": ["tools/seed_psychology_safety.py"],
    "notes": ["این قاعده بر همه‌ی رکوردهای دامنه‌ی روان‌شناسی اولویت دارد.",
              "در انتظار تأیید آکادمی (RQ-0011)؛ رفتار امن پیش‌فرض تا آن زمان، ارجاع فوری است."],
    "objects": OBJ,
})
print("%s psychology_safety_policy.json objects: %d" % ("wrote" if changed else "unchanged", len(OBJ)))

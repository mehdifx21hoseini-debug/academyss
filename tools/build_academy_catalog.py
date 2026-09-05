#!/usr/bin/env python3
"""STRUCTURED step: raw_sources/academy/site_data_v001.json -> Academy catalog collection.

Only facts present in the source are emitted. Nothing is inferred about the
Academy methodology here: the site tells us *what content exists*, not *what it
teaches*, so every object stays ACADEMY_DERIVED and never ACADEMY_PRIMARY.
"""
import sys

sys.path.insert(0, __file__.rsplit("/", 1)[0])
import kb_lib as K  # noqa: E402

NOW = K.now_iso()
RAW = K.load_json(K.ROOT + "/raw_sources/academy/site_data_v001.json")
DATA = RAW["data"]

CATEGORY_FA = {"trading": "معامله‌گری", "psychology": "روانشناسی", "analysis": "تحلیل"}


def base(oid, otype, title, chunk, location, **kw):
    obj = {
        "id": oid,
        "object_type": otype,
        "domain": "academy",
        "title": title,
        "language": "fa",
        "chunk_text": chunk,
        "source": {
            "source_type": "ACADEMY_APP_DATA",
            "source_ref": "js/data.js",
            "source_location": location,
            "author": "سبحان صمدی",
        },
        "authority_level": "ACADEMY_DERIVED",
        "methodology_scope": "ACADEMY_OPERATIONS",
        "approval_status": "PENDING_REVIEW",
        "lifecycle_status": "PENDING_REVIEW",
        "verification_required": True,
        "verification_note": (
            "برگرفته از داده‌های سایت آکادمی. صحت عنوان‌ها، مدت‌زمان‌ها و آمار "
            "باید توسط تیم آکادمی تأیید شود (احتمال محتوای نمونه/دمو)."
        ),
        "confidence": 0.6,
        "version": "v001",
        "created_at": NOW,
        "updated_at": NOW,
    }
    obj.update(kw)
    return obj


objects = []

for i, p in enumerate(DATA["podcasts"]):
    cat_fa = CATEGORY_FA.get(p["category"], p["category"])
    has_audio = bool(p.get("src"))
    chunk = (
        "پادکست «{title}» از آکادمی سبحان صمدی. موضوع: {desc}. "
        "دسته‌بندی: {cat}. مدرس/گوینده: {author}. مدت اعلام‌شده: {dur}. "
        "وضعیت فایل صوتی در سایت: {audio}."
    ).format(
        title=p["title"], desc=p["description"], cat=cat_fa,
        author=p["author"], dur=p["duration"],
        audio="بارگذاری شده" if has_audio else "بارگذاری نشده",
    )
    objects.append(base(
        "ACA-CAT-%04d" % (i + 1), "CATALOG_ITEM", "پادکست: " + p["title"], chunk,
        "window.SSAData.podcasts[%d] (id=%s)" % (i, p["id"]),
        category="پادکست", subcategory=cat_fa,
        summary="پادکست آکادمی درباره‌ی: " + p["description"],
        keywords=["پادکست", cat_fa, p["title"]],
        related_questions=[
            "آکادمی درباره‌ی {} پادکست داره؟".format(p["title"]),
            "پادکست {} چند دقیقه‌ست؟".format(p["title"]),
            "کجا می‌تونم پادکست {} رو گوش بدم؟".format(p["title"]),
        ],
        validity={"audio_available": has_audio, "declared_duration": p["duration"],
                  "declared_views": p.get("views"), "site_category": p["category"]},
    ))

for i, b in enumerate(DATA["books"]):
    has_audio = bool(b.get("src"))
    chunk = (
        "کتاب صوتی «{title}» نوشته‌ی {author} در کتابخانه‌ی آکادمی سبحان صمدی موجود است. "
        "مدت اعلام‌شده: {dur}. وضعیت فایل صوتی در سایت: {audio}."
    ).format(title=b["title"], author=b["author"], dur=b["duration"],
             audio="بارگذاری شده" if has_audio else "بارگذاری نشده")
    objects.append(base(
        "ACA-CAT-%04d" % (100 + i + 1), "CATALOG_ITEM", "کتاب صوتی: " + b["title"], chunk,
        "window.SSAData.books[%d] (id=%s)" % (i, b["id"]),
        category="کتاب صوتی",
        summary="کتاب صوتی «{}» از {} در کتابخانه‌ی آکادمی.".format(b["title"], b["author"]),
        keywords=["کتاب صوتی", b["title"], b["author"]],
        related_questions=[
            "کتاب {} رو دارید؟".format(b["title"]),
            "چه کتاب‌هایی از {} توی آکادمی هست؟".format(b["author"]),
        ],
        validity={"audio_available": has_audio, "declared_duration": b["duration"]},
    ))

# --- operational facts taken from index.html (line numbers verified) -----------
def site(oid, otype, title, chunk, location, **kw):
    obj = base(oid, otype, title, chunk, location, **kw)
    obj["source"]["source_type"] = "ACADEMY_WEBSITE"
    obj["source"]["source_ref"] = "index.html"
    return obj


objects.append(site(
    "ACA-OPS-0001", "OPERATIONAL_FACT", "معرفی آکادمی سبحان صمدی",
    "آکادمی سبحان صمدی یک آکادمی تخصصی آموزش معامله‌گری در بازارهای مالی بین‌المللی است. "
    "خدمات اعلام‌شده در سایت: پادکست‌های آموزشی، کتاب‌های صوتی و منتورینگ اختصاصی. "
    "آمار اعلام‌شده در سایت: بیش از ۵۰۰ دانشجوی فعال، بیش از ۸۰ ساعت محتوا، امتیاز کاربران ۴.۹ "
    "و بیش از ۱۰ سال تجربه‌ی سبحان صمدی به‌عنوان منتور و تحلیل‌گر ارشد.",
    "index.html:57-70,200-212",
    category="معرفی آکادمی",
    summary="آکادمی سبحان صمدی: آموزش معامله‌گری با پادکست، کتاب صوتی و منتورینگ اختصاصی.",
    keywords=["آکادمی", "سبحان صمدی", "معرفی", "خدمات"],
    related_questions=["آکادمی سبحان صمدی چیه؟", "چه خدماتی ارائه می‌دید؟", "سبحان صمدی کیه؟"],
))

objects.append(site(
    "ACA-OPS-0002", "OPERATIONAL_FACT", "منتورینگ اختصاصی آکادمی",
    "منتورینگ اختصاصی آکادمی به‌صورت یک‌به‌یک با سبحان صمدی برگزار می‌شود و طبق سایت شامل این موارد است: "
    "جلسات آنلاین اختصاصی، بررسی معاملات و پورتفولیو، دسترسی به محتوای ویژه VIP، "
    "پشتیبانی در گروه اختصاصی، و برنامه‌ی آموزشی شخصی‌سازی‌شده. "
    "وضعیت اعلام‌شده در سایت: پذیرش دانشجو فعال است. ثبت‌نام از طریق فرم تماس سایت انجام می‌شود.",
    "index.html:187-212",
    category="خدمات", subcategory="منتورینگ",
    summary="منتورینگ یک‌به‌یک با ۵ سرویس اعلام‌شده و پذیرش فعال.",
    keywords=["منتورینگ", "ثبت‌نام", "VIP", "جلسه خصوصی"],
    related_questions=["منتورینگ شامل چی می‌شه؟", "چطور توی منتورینگ ثبت‌نام کنم؟",
                       "الان دانشجو می‌پذیرید؟", "هزینه‌ی منتورینگ چقدره؟"],
    review_reason="قیمت، مدت دوره و شرایط ثبت‌نام در منابع موجود وجود ندارد و باید از آکادمی گرفته شود.",
    review_priority="P1",
))

objects.append(site(
    "ACA-OPS-0003", "PROCEDURE", "کار با پخش‌کننده‌ی صوتی سایت آکادمی",
    "پخش‌کننده‌ی سایت آکادمی این امکانات را دارد: پخش/توقف، جابه‌جایی با کلیک روی نوار پیشرفت، "
    "تغییر سرعت پخش بین ۰.۷۵ تا ۲ برابر، تکرار (Loop) یک فایل، تنظیم صدا، "
    "جلو/عقب بردن ۱۵ ثانیه‌ای و پخش‌کننده‌ی شناور در پایین صفحه.",
    "README.md:امکانات پلیر",
    category="پشتیبانی سایت",
    steps=[
        "روی پادکست یا کتاب صوتی موردنظر کلیک کنید تا در پخش‌کننده بارگذاری شود.",
        "برای پخش یا توقف از دکمه‌ی مرکزی استفاده کنید.",
        "برای جابه‌جایی در فایل، روی نوار پیشرفت کلیک کنید.",
        "برای تغییر سرعت، روی دکمه‌ی سرعت بزنید (۰.۷۵× تا ۲×).",
        "برای تکرار یک فایل، دکمه‌ی 🔁 تکرار را فعال کنید.",
        "برای جلو/عقب بردن، از دکمه‌های ±۱۵ ثانیه استفاده کنید.",
    ],
    summary="راهنمای استفاده از پخش‌کننده‌ی صوتی سایت آکادمی.",
    keywords=["پلیر", "پخش", "سرعت پخش", "تکرار"],
    related_questions=["چطور سرعت پخش رو زیاد کنم؟", "چرا صدا پخش نمی‌شه؟",
                       "چطور پادکست رو از اول گوش بدم؟"],
))
objects[-1]["source"]["source_ref"] = "README.md"

collection = {
    "collection_id": "academy_site_catalog",
    "domain": "academy",
    "title": "کاتالوگ و اطلاعات عملیاتی آکادمی سبحان صمدی",
    "description": (
        "محتوای اعلام‌شده در سایت آکادمی (پادکست‌ها، کتاب‌های صوتی، خدمات منتورینگ و پشتیبانی سایت). "
        "این مجموعه دانشِ «متدولوژی آکادمی» نیست و نباید به‌عنوان منبع آموزشی استفاده شود."
    ),
    "version": "v001",
    "generated_at": NOW,
    "pipeline_stage": "STRUCTURED",
    "source_files": ["js/data.js", "index.html", "README.md",
                     "raw_sources/academy/site_data_v001.json"],
    "notes": [
        "ساخته‌شده به‌صورت خودکار توسط tools/build_academy_catalog.py — دستی ویرایش نشود.",
        "هیچ فایل صوتی‌ای در سایت بارگذاری نشده است (src خالی)؛ آمار بازدید و مدت‌زمان‌ها تأییدنشده‌اند.",
        "نظرات کاربران (testimonials) عمداً وارد پایگاه دانش نشده‌اند: محتوای تبلیغاتی‌اند، نه دانش.",
    ],
    "objects": objects,
}

dest = K.KB_DIR + "/academy/catalog/academy_site_catalog_v001.json"
changed = K.write_collection(dest, collection)
print("%s %s objects: %d" % ("wrote" if changed else "unchanged", K.rel(dest), len(objects)))

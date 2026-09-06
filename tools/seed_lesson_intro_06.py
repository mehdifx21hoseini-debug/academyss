#!/usr/bin/env python3
"""Structured knowledge from the Academy Intro course, lesson 6 (MetaTrader 5).

Source quality: USABLE. A short lesson: MT5 is treated as MT4 with a different
look plus a few added tools, so only what differs is recorded here — the rest
points back at the MT4 lesson.

One claim is deliberately not turned into a platform-difference record: the
lesson says trade levels on the chart "did not exist in MetaTrader 4". MT4 does
offer the equivalent through Tools > Options > Charts (Show trade levels); the
real difference is how you reach it, not whether it exists. The feature itself
is recorded; the comparison claim is not asserted, and the record says why.
"""
import sys

sys.path.insert(0, __file__.rsplit("/", 1)[0])
import kb_lib as K  # noqa: E402

NOW = K.now_iso()
RAW = "raw_sources/academy/intro/intro_lesson_06.md"


def obj(oid, otype, title, chunk, section, quote, conf, scope="PLATFORM_OPERATION",
        scope_platform="MT5_ONLY", **kw):
    approval = "PENDING_REVIEW" if conf >= 0.7 else "REVIEW_REQUIRED"
    o = {
        "id": oid, "object_type": otype, "domain": "academy",
        "title": title, "language": "fa", "chunk_text": chunk,
        "source": {
            "source_type": "ACADEMY_COURSE_TRANSCRIPT", "source_ref": RAW,
            "source_location": section,
            "course": "دوره مقدماتی — معاملگری حرکات قیمت", "lesson": "۶",
            "section": section, "author": "سبحان صمدی", "verbatim_quote": quote,
        },
        "authority_level": "ACADEMY_PRIMARY",
        "methodology_scope": scope,
        "platform_scope": scope_platform,
        "approval_status": approval,
        "lifecycle_status": "PENDING_REVIEW",
        "verification_required": conf < 0.85,
        "confidence": conf,
        "version": "v001",
        "created_at": NOW, "updated_at": NOW,
    }
    if conf < 0.85:
        o["verification_note"] = "برداشت از متن درس؛ پیش از تبدیل به پاسخ رسمی، تأیید مدرس لازم است."
    if conf < 0.7:
        o["review_priority"] = "P1"
        o.setdefault("review_reason", "نیازمند تأیید مدرس.")
    o.update(kw)
    return o


OBJECTS = [
    obj("ACA-INT-0110", "CONCEPT", "نسبت متاتریدر ۵ به متاتریدر ۴ از نگاه آکادمی",
        "به گفته‌ی مدرس، متاتریدر ۵ تقریباً همان متاتریدر ۴ است: شکل و ظاهرش تفاوت دارد و چند ابزار "
        "کارآمد به آن اضافه شده است. به همین دلیل آموزش نسخه‌ی پنج کوتاه است و فقط به تفاوت‌ها "
        "می‌پردازد؛ باقی مطالب همان چیزی است که در آموزش نسخه‌ی چهار گفته شد.",
        "بخش ۳",
        "نسخه پنجم تقریباً یعنی همون نسخه چهاره، فقط شکل و شمایل تفاوت پیدا کرده و چند تا ابزار "
        "کارآمد از نگاه من بهش اضافه شده.",
        0.9, scope_platform="VERSION_DEPENDENT",
        keywords=["متاتریدر ۵", "متاتریدر ۴", "تفاوت"],
        related_concepts=["MT-CMP-0001", "MT-CMP-0002", "ACA-INT-0084"],
        related_questions=["فرق متاتریدر ۴ و ۵ چیه؟", "متاتریدر ۵ خیلی فرق داره؟"]),
    obj("ACA-INT-0111", "RULE", "توصیه‌ی آکادمی برای انتخاب بین متاتریدر ۴ و ۵",
        "توصیه‌ی مدرس این است: اول آموزش متاتریدر ۴ را کامل ببین، بعد متاتریدر ۵ را هم نصب کن و "
        "خودت ببین با کدام راحت‌تری و با کدام بهتر ارتباط می‌گیری. یعنی آکادمی هیچ‌کدام را تحمیل "
        "نمی‌کند و انتخاب نهایی با خود دانشجوست.",
        "بخش ۳",
        "از شما عزیز می‌خوام برای این که کامل آگاه بشید، نسخه چهار رو کامل آموزش ببینید و نسخه پنج "
        "رو هم نصب کنید و ببینید خودتون کدوم باهاش بیشتر راحت هستید.",
        0.9, scope="ACADEMY_METHODOLOGY", scope_platform="VERSION_DEPENDENT",
        rule="اول متاتریدر ۴ را کامل بیاموز، سپس متاتریدر ۵ را نصب کن و پلتفرم راحت‌تر را خودت انتخاب کن.",
        keywords=["انتخاب پلتفرم", "متاتریدر ۴", "متاتریدر ۵"],
        related_concepts=["ACA-RULE-0001", "MT-CMP-0011"],
        related_questions=["متاتریدر ۴ کار کنم یا ۵؟", "کدوم پلتفرم بهتره؟"]),
    obj("ACA-INT-0112", "PROCEDURE", "ورود به حساب در متاتریدر ۵",
        "مراحل اتصال متاتریدر ۵ به حساب بروکر: از منوی File گزینه‌ی Open an Account را باز کنید، "
        "سرور بروکر را انتخاب کنید، مشخص کنید حساب دمو است یا ریل، سپس شماره‌ی حساب و رمز عبور را "
        "وارد کنید. اتصال موفق با سبز شدن وضعیت در پایین صفحه معلوم می‌شود.",
        "بخش ۴",
        "تو گزینه File، تو گزینه Open an Account رو کلیک می‌کنید … سرور متاتریدر رو انتخاب می‌کنید، "
        "دمو یا ریل بروکری که هستید رو می‌زنید، و شماره حساب و پسورد رو که بزنید، در نهایت اتصال "
        "پیدا می‌کنه … ما سبز هستیم.",
        0.9, steps=["منوی File را باز کنید و Open an Account را بزنید.",
                    "سرور بروکر را انتخاب کنید.",
                    "نوع حساب (دمو یا ریل) را مشخص کنید.",
                    "شماره حساب و رمز عبور را وارد کنید.",
                    "وضعیت اتصال را در پایین صفحه بررسی کنید (سبز = متصل)."],
        keywords=["ورود", "open an account", "سرور", "متاتریدر ۵"],
        related_concepts=["MT5-PROC-0001", "ACA-INT-0080"],
        related_questions=["چطور توی متاتریدر ۵ وارد بشم؟"]),
    obj("ACA-INT-0113", "PROCEDURE", "باز کردن نمودار و کار با Market Watch در متاتریدر ۵",
        "دو راه برای باز کردن نمودار وجود دارد: از Market Watch، یا از منوی File و گزینه‌ی New Chart. "
        "پنجره‌ی Market Watch از منوی View یا با کلید Ctrl+M باز می‌شود. با Hide All فقط نمادهای "
        "انتخابی می‌مانند و با Show All همه‌ی نمادها نمایش داده می‌شوند.",
        "بخش ۵",
        "از Market Watch اقدام کنیم … تو گزینه File، New Chart رو بزنیم … یا Ctrl+M رو بزنی … "
        "Hide All می‌کنیم … Show All رو بزنیم، تمامی نمادها به ما نمایش داده می‌شه.",
        0.9, steps=["Market Watch را از View یا با Ctrl+M باز کنید.",
                    "برای پاک‌سازی فهرست، Hide All را بزنید.",
                    "برای دیدن همه‌ی نمادها، Show All را بزنید.",
                    "برای باز کردن چارت، نماد را انتخاب کنید یا از File > New Chart استفاده کنید."],
        keywords=["market watch", "new chart", "Ctrl+M", "show all", "hide all"],
        related_concepts=["MT5-PROC-0002", "MT-PROC-0021"],
        related_questions=["چطور چارت باز کنم؟", "نمادها رو چطور نشون بدم؟"]),
    obj("ACA-INT-0114", "CONCEPT", "منوهای متاتریدر ۵",
        "منوی View در متاتریدر ۵ شامل Language، Color Theme، Toolbar، Symbols، Market Watch، "
        "Data Window و Navigator است. منوی Insert همان ابزارهای تحلیلی نسخه‌ی چهار را دارد. "
        "منوی Chart تایم‌فریم‌ها، Template و گزینه‌های Auto Scroll و Chart Shift را در خود دارد. "
        "گزینه‌ی Color Theme در نسخه‌ی چهار وجود ندارد.",
        "بخش ۶",
        "تو گزینه View دقیقاً: Language، Color Theme، Toolbar … Symbols، Market Watch، Data Window، "
        "Navigator … تو قسمت Insert دقیقاً همه همونه … تو گزینه Chart … Auto Scroll، Chart Shift.",
        0.85, keywords=["منو", "view", "insert", "chart", "color theme"],
        related_concepts=["MT-PROC-0017", "ACA-INT-0107", "ACA-INT-0091"],
        related_questions=["منوهای متاتریدر ۵ چیه؟", "تم رنگی رو کجا عوض کنم؟"]),
    obj("ACA-INT-0115", "PROCEDURE", "ذخیره و بارگذاری Template در متاتریدر ۵",
        "در متاتریدر ۵ مسیر تمپلیت با نسخه‌ی چهار فرق دارد: از منوی View به Templates بروید و "
        "Save Template را بزنید تا تنظیمات فعلی با نامی دلخواه ذخیره شود؛ برای اعمال روی چارت دیگر، "
        "همان نام را از Load انتخاب کنید. همان رنگ‌بندی و تنظیماتی که در آموزش متاتریدر ۴ گفته شد، "
        "اینجا هم قابل اعمال است.",
        "بخش ۷",
        "چطور Template رو Save کنیم؟ از مسیر: View → Templates → Save Template … و اگر بخوام دوباره "
        "بیارم، Load رو می‌زنم.",
        0.85, steps=["چارت را مطابق تنظیمات دلخواه بچینید.",
                     "از منوی View گزینه‌ی Templates را باز کنید.",
                     "Save Template را بزنید و نامی انتخاب کنید.",
                     "برای اعمال روی چارت دیگر، از همان مسیر Load و نام ذخیره‌شده را انتخاب کنید."],
        keywords=["template", "قالب", "متاتریدر ۵"],
        related_concepts=["ACA-INT-0093", "MT-PROC-0006"],
        related_questions=["تمپلیت رو توی متاتریدر ۵ کجا ذخیره کنم؟"]),
    obj("ACA-INT-0116", "PROCEDURE", "Trade Level: نمایش یا پنهان کردن خطوط معامله روی چارت",
        "با راست‌کلیک روی چارت متاتریدر ۵، گزینه‌ی Trade Level در دسترس است. کارکردی که مدرس توضیح "
        "می‌دهد این است: با این گزینه می‌توان خطوط مربوط به معامله‌ی باز (نقطه‌ی ورود، حد ضرر و حد سود) "
        "را روی چارت نمایش داد یا پنهان کرد، بدون اینکه خود معامله بسته شود. فایده‌اش این است که "
        "وقتی معامله‌ای باز دارید ولی می‌خواهید همان نماد را بدون شلوغی خطوط بررسی کنید، چارت تمیز "
        "دیده می‌شود.",
        "بخش ۸",
        "وقتی راست کلیک روی صفحه بکنی … یک گزینه Trade Level داریم … بعضی وقتا شما معاملت بازه، ولی "
        "می‌خوای همون نماد رو بدون در نظر گرفتن خط و خطوطی که روی نمودار رسم می‌شه، بررسی کنی. و این "
        "Trade Level به شما این کمک رو می‌کنه.",
        0.75,
        steps=["روی چارت راست‌کلیک کنید.",
               "گزینه‌ی Trade Level را انتخاب کنید تا نمایش خطوط معامله روشن یا خاموش شود."],
        warnings=["پنهان کردن خطوط، معامله را نمی‌بندد و تأثیری بر حد ضرر و حد سود ندارد."],
        verification_note=("بیان درس در این بخش دوپهلوست («نشون می‌ده» و «بدون نمایش معامله») و "
                           "برداشت انجام‌شده، کارکرد کلیدِ روشن/خاموش کردن نمایش خطوط معامله است. "
                           "همچنین جمله‌ی «این را متاتریدر ۴ نداشت» به‌عنوان تفاوت پلتفرمی ثبت نشد، "
                           "چون متاتریدر ۴ تنظیم هم‌ارز آن را در Tools > Options > Charts دارد و "
                           "تفاوت در مسیر دسترسی است، نه در وجود قابلیت."),
        keywords=["trade level", "خطوط معامله", "چارت تمیز"],
        related_questions=["چطور خطوط معامله رو از چارت بردارم؟", "Trade Level چیه؟"]),
    obj("ACA-INT-0117", "PROCEDURE", "Trade History: نمایش معاملات گذشته روی چارت",
        "با راست‌کلیک روی چارت متاتریدر ۵ و فعال کردن Trade History، معاملات گذشته مستقیماً روی "
        "نمودار نمایش داده می‌شوند: نقطه‌ی ورود خرید یا فروش و سطوح مربوط، و با نگه داشتن نشانگر "
        "جزئیات هم دیده می‌شود. مدرس این را نسبت به روش متاتریدر ۴ ساده‌تر می‌داند، جایی که برای "
        "دیدن همان اطلاعات باید معامله را از Account History روی چارت می‌کشیدید. کاربرد اصلی‌اش "
        "بازبینی و تحلیل عملکرد گذشته است.",
        "بخش ۸",
        "توی متاتریدر ۵ شما به جای این که برید تو Account History و معامله رو انتخاب کنید و بکشید، "
        "کافیه راست کلیک کنید و Trade History رو فعال کنید … کمک می‌کنه به شما که وقتی می‌خوای خودت "
        "رو آنالیز کنی.",
        0.85, steps=["روی چارت راست‌کلیک کنید.",
                     "گزینه‌ی Trade History را فعال کنید.",
                     "نقاط ورود و خروج معاملات گذشته را روی نمودار بررسی کنید."],
        keywords=["trade history", "بازبینی معاملات", "نقطه ورود"],
        related_concepts=["MT5-PROC-0012", "ACA-INT-0104", "PSY-PAT-0010"],
        related_questions=["معاملات قبلیم رو روی چارت چطور ببینم؟", "برای بازبینی معاملات چیکار کنم؟"]),
    obj("ACA-INT-0118", "CONCEPT", "منوی Tools در متاتریدر ۵",
        "منوی Tools شامل New Order برای ثبت سفارش، Task Manager، دسترسی به MQL5 Market و Options "
        "(تنظیمات عمومی) است. معامله‌ی یک‌کلیکی هم مثل نسخه‌ی چهار با راست‌کلیک روی چارت در دسترس است.",
        "بخش ۹",
        "تو قسمت Tools بریم: New Order برای سفارش باز کردن، یا راست کلیک می‌کنی، اینجا One Click "
        "Trading Order رو داری می‌بینی … Task Manager رو داریم می‌بینیم … MQL5 Market هم که برای "
        "بحث خودشه.",
        0.8, keywords=["tools", "new order", "task manager", "MQL5 market", "options"],
        related_concepts=["MT-PROC-0017", "MT-PROC-0009", "ACA-RULE-0002"],
        related_questions=["منوی Tools چی داره؟", "MQL5 Market چیه؟"]),
    obj("ACA-INT-0119", "CONCEPT", "سرعت متاتریدر ۴ در برابر ۵ و تأثیر اینترنت",
        "بر اساس گزارش‌هایی که مدرس از دانشجویان گرفته، سرعت کار متاتریدر ۵ برای بسیاری بیشتر از "
        "نسخه‌ی چهار بوده است؛ اما او تأکید می‌کند این موضوع برای هر شخص، هر اینترنت و هر موقعیت "
        "جغرافیایی متفاوت است و برای خودش هر دو نسخه بهترین سرعت اتصال را دارند. توصیه‌اش این است "
        "که هر کس خودش هر دو را با اینترنت و سیستم خودش تست کند. آنچه در نهایت اهمیت دارد این است "
        "که معامله درست باز و درست بسته شود.",
        "بخش ۱۰",
        "سرعت کار نسبت به گزارشی که من از خیلی‌هاتون می‌گیرم، متا ۵ بیشتر از متا ۴ه. اما این نکته‌ای "
        "که دارم بهتون می‌گم برای هر شخصی و برای هر اینترنتی می‌تونه متفاوت باشه … شماها هم باید "
        "خودتون این بررسی رو داشته باشید.",
        0.8, scope_platform="VERSION_DEPENDENT",
        warnings=["این یک مقایسه‌ی تجربی است، نه اندازه‌گیری فنی؛ نتیجه به اینترنت و موقعیت کاربر بستگی دارد."],
        keywords=["سرعت", "اینترنت", "کانکشن", "انتخاب پلتفرم"],
        related_concepts=["ACA-INT-0111", "MT-TRBL-0005"],
        related_questions=["متاتریدر ۵ سریع‌تره؟", "کدوم نسخه با اینترنت من بهتره؟"]),
]

changed = K.write_collection(K.KB_DIR + "/academy/intro/lesson_06.json", {
    "collection_id": "academy_intro_lesson_06",
    "domain": "academy",
    "title": "دوره مقدماتی — جلسه ۶: آشنایی با متاتریدر ۵",
    "description": ("تفاوت‌های متاتریدر ۵ با نسخه‌ی چهار از نگاه آکادمی: ورود، باز کردن نمودار، "
                    "منوها، تمپلیت، دو گزینه‌ی Trade Level و Trade History، و انتخاب بین دو نسخه."),
    "version": "v001", "generated_at": NOW, "pipeline_stage": "STRUCTURED",
    "source_files": [RAW, "raw_sources/academy/intro/intro_lesson_06.ingest.json"],
    "notes": [
        "این جلسه فقط تفاوت‌ها را پوشش می‌دهد؛ باقی مطالب به جلسه‌ی ۵ (متاتریدر ۴) ارجاع داده شده است.",
        "جمله‌ی «Trade Level را متاتریدر ۴ نداشت» به‌عنوان تفاوت پلتفرمی ثبت نشد؛ متاتریدر ۴ تنظیم "
        "هم‌ارز آن را در Tools > Options > Charts دارد و تفاوت در مسیر دسترسی است.",
        "توصیه‌ی این جلسه (اول MT4، بعد MT5، انتخاب با دانشجو) با قاعده‌ی ACA-RULE-0001 هم‌راستاست.",
    ],
    "objects": OBJECTS,
})
print("%s intro/lesson_06.json objects: %d" % ("wrote" if changed else "unchanged", len(OBJECTS)))

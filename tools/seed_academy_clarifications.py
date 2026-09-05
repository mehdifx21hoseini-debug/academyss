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
}, {
    "id": "ACA-CLR-0002",
    "object_type": "CONCEPT",
    "domain": "academy",
    "category": "رفع ابهام",
    "title": "«سه اصل بازار» در متدولوژی آکادمی چیست",
    "language": "fa",
    "summary": "سه اصل / سه چرخه‌ی بازار: اسپایک، کانال قیمتی، تریدینگ رنج.",
    "chunk_text": (
        "پاسخ رسمی و واحد: «سه اصل بازار» یا «سه چرخه‌ی بازار» در متدولوژی آکادمی عبارت‌اند از "
        "**اسپایک (Spike)، کانال قیمتی (Channel) و تریدینگ رنج (Trading Range)**. این سه مدام در "
        "بازار تکرار می‌شوند و ترتیبشان چنین است: اسپایک شروع‌کننده‌ی روند است، کانال پس از اولین "
        "اصلاح شکل می‌گیرد و تریدینگ رنج چرخه‌ی آخر است؛ سپس دوباره از اسپایک آغاز می‌شود. "
        "روش معامله در هرکدام فرق می‌کند: در اسپایک فقط یک‌طرفه، در کانال دوطرفه اما مایل به جهت "
        "کانال، و در رنج خرید در کف و فروش در سقف. "
        "در جلسه‌ی اول دوره فهرست دیگری هم بیان شده بود (کانال قیمتی، نقدینگی، خرید و فروش در "
        "سایکل)؛ آن فهرست سه محور نگاه مدرس به بازار است و «سه اصل بازار» نیست."
    ),
    "source": {
        "source_type": "ACADEMY_DOCUMENT",
        "source_ref": "MENTORAI_KB_DECISIONS.md",
        "source_location": "D-0005",
        "author": "مالک پروژه",
    },
    "authority_level": "ACADEMY_DERIVED",
    "methodology_scope": "ACADEMY_METHODOLOGY",
    "platform_scope": "NOT_APPLICABLE",
    "approval_status": "APPROVED",
    "lifecycle_status": "ACTIVE",
    "confidence": 1.0,
    "version": "v001",
    "keywords": ["سه اصل بازار", "سه چرخه", "اسپایک", "کانال قیمتی", "تریدینگ رنج"],
    "related_concepts": ["ACA-INT-0006", "ACA-INT-0007", "ACA-INT-0191", "ACA-INT-0202"],
    "conflicts": ["CONF-0002"],
    "related_questions": ["سه اصل بازار از نظر آکادمی چیه؟", "سه چرخه‌ی بازار چیه؟",
                          "اسپایک و کانال و رنج به چه ترتیبی میان؟"],
    "created_at": NOW, "updated_at": NOW,
}, {
    "id": "ACA-CLR-0003",
    "object_type": "CONCEPT",
    "domain": "academy",
    "category": "رفع ابهام",
    "title": "بریک‌ایون و الگوی V در کدام سطح آموزش داده می‌شوند",
    "language": "fa",
    "summary": "هر دو در دوره‌ی پیشرفته تخصصی‌تر آموزش داده می‌شوند؛ مربی در سطح مقدماتی تعریف قطعی نمی‌دهد.",
    "chunk_text": (
        "«بریک‌ایون» و «الگوی V» در دوره‌ی مقدماتی فقط معرفی شده‌اند و آموزش تخصصی‌تر آن‌ها در "
        "مجموعه‌ی آموزشی پیشرفته انجام می‌شود. "
        "بنابراین مربی در سطح مقدماتی تعریف قطعی و کامل ارائه نمی‌دهد؛ آنچه می‌گوید همان چیزی است "
        "که در جلسه‌ی ۱۴ آمده — الگوی V یعنی بازگشت کامل قیمت به نقطه‌ی شروع همان حرکت — و "
        "بلافاصله اضافه می‌کند که شرح کامل این دو مفهوم در دوره‌ی پیشرفته است. "
        "همچنین توجه داشته باشید که واژه‌ی «بریک‌ایون» در ادبیات عمومی معامله‌گری به نقطه‌ی سربه‌سر "
        "معامله (سود و زیان صفر) گفته می‌شود؛ مربی این دو کاربرد را از هم جدا نگه می‌دارد و هیچ‌کدام "
        "را به‌جای دیگری معرفی نمی‌کند."
    ),
    "source": {
        "source_type": "ACADEMY_DOCUMENT",
        "source_ref": "MENTORAI_KB_DECISIONS.md",
        "source_location": "D-0009",
        "author": "مالک پروژه",
    },
    "authority_level": "ACADEMY_DERIVED",
    "methodology_scope": "ACADEMY_METHODOLOGY",
    "platform_scope": "NOT_APPLICABLE",
    "approval_status": "APPROVED",
    "lifecycle_status": "ACTIVE",
    "confidence": 1.0,
    "version": "v001",
    "keywords": ["بریک ایون", "break even", "الگوی V", "دوره پیشرفته"],
    "related_concepts": ["ACA-INT-0219", "ACA-INT-0244", "ACA-INT-0211"],
    "related_questions": ["بریک ایون یعنی چی؟", "الگوی V چیه؟",
                          "اینا رو کجا کامل یاد می‌گیرم؟"],
    "created_at": NOW, "updated_at": NOW,
}, {
    "id": "ACA-CLR-0004",
    "object_type": "PROCEDURE",
    "domain": "academy",
    "category": "رفع ابهام",
    "title": "مسیر رسمی بک‌تست و استراتژی‌نویسی آکادمی",
    "language": "fa",
    "summary": "۱۰ تا ۱۵ استراتژی، یک سال بک‌تست در سه بازه‌ی چهارماهه، سپس ارسال فایل نهایی برای تأیید.",
    "chunk_text": (
        "این تنها مسیر رسمی آکادمی است و جایگزین همه‌ی روایت‌های دیگری می‌شود که در "
        "پاسخ‌های منتورها آمده بود.\n"
        "۱) همه‌ی ویدیوهای استراتژی‌نویسی را کامل ببینید و نت‌برداری کنید.\n"
        "۲) دوباره مرور کنید و هم‌زمان تمرین‌ها را انجام دهید.\n"
        "۳) **۱۰ تا ۱۵ استراتژی** طراحی کنید و حداقل **یک سال** گذشته‌ی بازار را بک‌تست بگیرید. "
        "این یک سال به سه بازه‌ی چهارماهه تقسیم می‌شود:\n"
        "   • چهار ماه نخست — همه‌ی سشن‌ها با همه‌ی استراتژی‌ها؛ استراتژی‌های ضعیف و کم‌بازده‌ترین "
        "سشن حذف می‌شوند.\n"
        "   • چهار ماه دوم — تمرکز بر استراتژی‌ها و سشن‌های برتر؛ حذف دوباره‌ی ضعیف‌ها و انتخاب یک "
        "سشن برتر.\n"
        "   • چهار ماه پایانی — فقط یک سشن و استراتژی‌های موفق؛ افزودن فیلترهای معاملاتی و تعیین "
        "حد ضرر متناسب با دیدگاه خودتان.\n"
        "۴) فایل نهایی شامل استراتژی‌ها، نتایج بک‌تست یک‌ساله و تریدینگ پلن را برای بررسی بفرستید؛ "
        "در صورت تأیید، وارد مرحله‌ی فوروارد تست می‌شوید.\n"
        "قواعد ثبت در اکسل: هر معامله یک ردیف مستقل (تاریخ تکرار می‌شود)؛ اگر استراتژی کمتر از "
        "هدف (مثلاً TP2) بدهد در اکسل منفی ۱ ثبت می‌شود؛ و سشنی که **ورود** در آن انجام شده ثبت "
        "می‌شود، نه سشنی که تارگت در آن خورده است.\n"
        "⚠️ روایت‌های دیگری که ممکن است دانشجو شنیده باشد (سه ماه سپس یک سال؛ ۴+۴+۴ با انتخاب ۵ "
        "استراتژی؛ «حداقل ۱۰ مورد بر مبنای چرخه‌ها») خلاصه‌های ناقص همین مسیرند. مربی همیشه همین "
        "متن را می‌دهد و اگر دانشجو مسیر دیگری را شروع کرده، او را به منتور ارجاع می‌دهد تا تکلیف "
        "کار انجام‌شده روشن شود."
    ),
    "steps": [
        "همه‌ی ویدیوهای استراتژی‌نویسی را کامل ببینید و نت‌برداری کنید.",
        "ویدیوها را دوباره مرور کنید و هم‌زمان تمرین‌ها را انجام دهید.",
        "۱۰ تا ۱۵ استراتژی طراحی کنید.",
        "چهار ماه نخست: همه‌ی سشن‌ها را با همه‌ی استراتژی‌ها بک‌تست بگیرید و ضعیف‌ها و کم‌بازده‌ترین سشن را حذف کنید.",
        "چهار ماه دوم: روی استراتژی‌ها و سشن‌های برتر تمرکز کنید، ضعیف‌ها را دوباره حذف و یک سشن برتر انتخاب کنید.",
        "چهار ماه پایانی: فقط با سشن برتر و استراتژی‌های موفق کار کنید و فیلترها و حد ضرر را اضافه کنید.",
        "فایل نهایی (استراتژی‌ها + بک‌تست یک‌ساله + تریدینگ پلن) را برای بررسی بفرستید.",
    ],
    "source": {
        "source_type": "ACADEMY_DOCUMENT",
        "source_ref": "MENTORAI_KB_DECISIONS.md",
        "source_location": "D-0012",
        "author": "مالک پروژه",
    },
    "authority_level": "ACADEMY_DERIVED",
    "methodology_scope": "ACADEMY_OPERATIONS",
    "platform_scope": "NOT_APPLICABLE",
    "approval_status": "APPROVED",
    "lifecycle_status": "ACTIVE",
    "confidence": 1.0,
    "version": "v001",
    "keywords": ["بک‌تست", "استراتژی‌نویسی", "سه بازه چهارماهه", "۱۰ تا ۱۵ استراتژی",
                 "فوروارد تست", "مسیر رسمی"],
    "related_concepts": ["ACA-INT-0246", "ACA-INT-0245", "MQA-00023", "MQA-00076"],
    "conflicts": ["CONF-0006"],
    "related_questions": ["مسیر بک‌تست چیه؟", "چند تا استراتژی بنویسم؟",
                          "چند ماه بک‌تست بگیرم؟", "کی وارد فوروارد تست می‌شم؟",
                          "سشن ورود رو ثبت کنم یا سشن تارگت؟"],
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

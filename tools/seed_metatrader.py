#!/usr/bin/env python3
"""Seed the METATRADER domain (sample-first batch): MT5, MT4 and the difference engine.

Written offline (no egress to metatrader5.com / metaquotes docs in this
container), so every record is MODEL_DRAFT / PENDING_VERIFICATION with an
explicit verification note. Menu paths and limits must be checked against the
official MetaQuotes help before any of this is marked APPROVED.
"""
import sys

sys.path.insert(0, __file__.rsplit("/", 1)[0])
import kb_lib as K  # noqa: E402

NOW = K.now_iso()
VERIFY = ("نوشته‌شده بر پایه‌ی دانش عمومی از پلتفرم، بدون دسترسی به مستندات رسمی MetaQuotes "
          "(شبکه‌ی خروجی در محیط پردازش مسدود بود). مسیر منوها، پیام‌های خطا و محدودیت‌ها باید "
          "با راهنمای رسمی و بیلد فعلی پلتفرم تطبیق داده شود.")


def obj(oid, otype, title, chunk, scope, conf, **kw):
    o = {
        "id": oid,
        "object_type": otype,
        "domain": "metatrader",
        "title": title,
        "language": "fa-en",
        "chunk_text": chunk,
        "source": {"source_type": "MODEL_DRAFT", "source_ref": "tools/seed_metatrader.py",
                   "source_location": oid},
        "authority_level": "GENERAL_KNOWLEDGE",
        "methodology_scope": "PLATFORM_OPERATION",
        "platform_scope": scope,
        "approval_status": "PENDING_VERIFICATION",
        "lifecycle_status": "PENDING_REVIEW",
        "verification_required": True,
        "verification_note": VERIFY,
        "confidence": conf,
        "version": "v001",
        "created_at": NOW,
        "updated_at": NOW,
    }
    o.update(kw)
    return o


# --------------------------------------------------------------------------- MT5
mt5 = [
    obj("MT5-PROC-0001", "METATRADER_PROCEDURE", "ورود به حساب معاملاتی در متاتریدر ۵",
        "برای اتصال به حساب در متاتریدر ۵ باید شماره‌ی حساب (Login)، رمز عبور و نام دقیق سرور بروکر را داشته باشید. "
        "سرور را حتماً از فهرست سرورهای همان بروکر انتخاب کنید؛ انتخاب سرور اشتباه رایج‌ترین علت خطای اتصال است.",
        "MT5_ONLY", 0.85, category="اتصال و حساب",
        steps=["از منوی File گزینه‌ی Login to Trade Account را انتخاب کنید.",
               "نام سرور بروکر را در کادر جست‌وجو وارد و از فهرست انتخاب کنید.",
               "شماره حساب و رمز عبور (Master یا Investor) را وارد کنید.",
               "روی OK بزنید و وضعیت اتصال را در گوشه‌ی پایین-راست ترمینال بررسی کنید."],
        common_mistakes=["وارد کردن رمز سرمایه‌گذار (Investor) به‌جای رمز اصلی؛ در این حالت امکان معامله وجود ندارد.",
                         "انتخاب سرور دمو به‌جای سرور ریل یا برعکس."],
        warnings=["اگر پیام Invalid account یا No connection دیدید، ابتدا نام سرور و سپس اینترنت را بررسی کنید."],
        keywords=["login", "ورود به حساب", "server", "متاتریدر ۵"],
        related_questions=["چطور وارد حسابم بشم؟", "سرور بروکر رو کجا وارد کنم؟", "Invalid account یعنی چی؟"]),
    obj("MT5-PROC-0002", "METATRADER_PROCEDURE", "نمایش نمادهای پنهان در Market Watch (متاتریدر ۵)",
        "اگر نمادی مثل XAUUSD در Market Watch دیده نمی‌شود، معمولاً نماد پنهان است نه اینکه بروکر آن را نداشته باشد. "
        "با پنجره‌ی Symbols می‌توان نماد را نمایش داد.",
        "MT5_ONLY", 0.85, category="نمادها",
        steps=["روی پنجره‌ی Market Watch راست‌کلیک کنید و Symbols را بزنید (یا Ctrl+U).",
               "در درخت گروه‌ها یا کادر جست‌وجو نام نماد را پیدا کنید.",
               "نماد را انتخاب و روی Show بزنید، سپس پنجره را ببندید."],
        warnings=["پسوند نماد بین بروکرها فرق می‌کند (مثلاً EURUSD.m یا XAUUSD_i)؛ همیشه نام دقیق بروکر خودتان را جست‌وجو کنید."],
        keywords=["market watch", "symbols", "نماد", "XAUUSD"],
        related_questions=["چرا طلا توی متاتریدر نیست؟", "چطور نماد اضافه کنم؟", "لیست نمادها کجاست؟"]),
    obj("MT5-PROC-0003", "METATRADER_PROCEDURE", "باز کردن معامله و انواع سفارش در متاتریدر ۵",
        "پنجره‌ی New Order با کلید F9 یا دکمه‌ی New Order باز می‌شود. در متاتریدر ۵ نوع اجرا (Type) می‌تواند "
        "Market Execution یا Pending Order باشد و شش نوع سفارش معلق در دسترس است: Buy Limit، Sell Limit، "
        "Buy Stop، Sell Stop، Buy Stop Limit و Sell Stop Limit.",
        "MT5_ONLY", 0.85, category="معامله",
        steps=["نماد موردنظر را در Market Watch انتخاب کنید.",
               "کلید F9 را بزنید تا پنجره‌ی New Order باز شود.",
               "حجم (Volume) را بر اساس مدیریت ریسک خود وارد کنید.",
               "در صورت نیاز Stop Loss و Take Profit را وارد کنید.",
               "برای ورود فوری Buy/Sell را بزنید یا Type را روی Pending Order بگذارید و قیمت فعال‌سازی را وارد کنید."],
        warnings=["حجم پیش‌فرض پنجره را بدون بررسی تغییر ندهید؛ ورود با حجم اشتباه یکی از پرتکرارترین خطاهاست."],
        keywords=["new order", "F9", "pending order", "stop limit"],
        related_questions=["چطور معامله باز کنم؟", "سفارش معلق چطور بذارم؟", "Buy Stop Limit چیه؟"]),
    obj("MT5-PROC-0004", "METATRADER_PROCEDURE", "تنظیم یا تغییر حد ضرر و حد سود روی معامله‌ی باز (متاتریدر ۵)",
        "برای افزودن یا تغییر SL/TP روی یک پوزیشن باز، از تب Trade در پنجره‌ی Toolbox استفاده می‌شود.",
        "MT5_ONLY", 0.85, category="مدیریت معامله",
        steps=["پنجره‌ی Toolbox را باز کنید (Ctrl+T) و به تب Trade بروید.",
               "روی پوزیشن موردنظر راست‌کلیک و Modify or Delete Position را بزنید.",
               "مقادیر Stop Loss و Take Profit را وارد کنید.",
               "روی دکمه‌ی Modify بزنید و اعمال شدن مقادیر را در تب Trade بررسی کنید."],
        common_mistakes=["دور کردن حد ضرر هنگام ضرر؛ این کار مدیریت ریسک را از بین می‌برد."],
        keywords=["stop loss", "take profit", "modify position", "toolbox"],
        related_questions=["چطور حد ضرر بذارم؟", "چطور حد ضرر رو جابه‌جا کنم؟"]),
    obj("MT5-PROC-0005", "METATRADER_PROCEDURE", "مشاهده‌ی مشخصات نماد در متاتریدر ۵",
        "پنجره‌ی Specification اطلاعات کلیدی هر نماد را نشان می‌دهد: اندازه‌ی قرارداد، حداقل و حداکثر حجم، "
        "گام حجم، Tick Size و Tick Value، سطح استاپ (Stops Level)، نرخ سواپ، ساعات معاملاتی و نوع اجرا. "
        "این مقادیر بین بروکرها متفاوت است و مرجع پاسخ به سؤال‌های «چقدر» و «چه ساعتی» همین پنجره است.",
        "MT5_ONLY", 0.8, category="نمادها",
        steps=["در Market Watch روی نماد راست‌کلیک کنید.",
               "گزینه‌ی Specification را انتخاب کنید.",
               "مقادیر موردنیاز (Contract size، Volume limits، Stops level، Swap، Trading hours) را بخوانید."],
        keywords=["specification", "مشخصات نماد", "stops level", "tick value"],
        related_questions=["اندازه قرارداد طلا چقدره؟", "حداقل حجم چقدره؟", "ساعت معاملاتی نماد رو کجا ببینم؟"]),
    obj("MT5-PROC-0006", "METATRADER_PROCEDURE", "گزارش تاریخچه‌ی معاملات در متاتریدر ۵",
        "تاریخچه‌ی معاملات در تب History از Toolbox نمایش داده می‌شود و می‌توان از آن گزارش گرفت. "
        "در متاتریدر ۵ نمایش تاریخچه بین حالت‌های Positions، Orders و Deals قابل تغییر است.",
        "MT5_ONLY", 0.8, category="گزارش‌گیری",
        steps=["Toolbox را باز کنید (Ctrl+T) و به تب History بروید.",
               "روی ناحیه‌ی تاریخچه راست‌کلیک و بازه‌ی زمانی دلخواه را انتخاب کنید.",
               "برای گرفتن خروجی، راست‌کلیک و Report را بزنید و قالب موردنظر را انتخاب کنید."],
        keywords=["history", "report", "تاریخچه", "گزارش"],
        related_questions=["گزارش معاملاتم رو چطور بگیرم؟", "تاریخچه معاملات کجاست؟"]),
    obj("MT5-PROC-0007", "METATRADER_PROCEDURE", "فعال‌سازی AutoTrading و اجرای اکسپرت در متاتریدر ۵",
        "برای اجرای اکسپرت (EA) باید دکمه‌ی AutoTrading در نوار ابزار فعال باشد و اکسپرت روی چارت اجرا شده باشد. "
        "اگر روی چارت به‌جای صورتک لبخند علامت توقف دیده شود، معامله‌ی خودکار غیرفعال است.",
        "MT5_ONLY", 0.8, category="اکسپرت",
        steps=["فایل اکسپرت را در پوشه‌ی MQL5/Experts قرار دهید (File > Open Data Folder).",
               "در پنجره‌ی Navigator روی Expert Advisors راست‌کلیک و Refresh بزنید.",
               "اکسپرت را روی چارت بکشید و در تب Common گزینه‌ی Allow Algo Trading را تیک بزنید.",
               "دکمه‌ی AutoTrading در نوار ابزار را فعال کنید."],
        warnings=["پیش از اجرای هر اکسپرت روی حساب واقعی، آن را روی حساب دمو آزمایش کنید."],
        keywords=["expert advisor", "autotrading", "MQL5", "ربات"],
        related_questions=["چرا اکسپرتم معامله نمی‌کنه؟", "اکسپرت رو چطور نصب کنم؟"]),
    obj("MT5-CONC-0001", "CONCEPT", "نوع حساب Netting و Hedging در متاتریدر ۵",
        "متاتریدر ۵ دو سیستم حسابداری پوزیشن دارد. در حساب Netting برای هر نماد فقط یک پوزیشن وجود دارد و "
        "معامله‌ی جدید در جهت مخالف، پوزیشن موجود را کم یا خنثی می‌کند. در حساب Hedging می‌توان چند پوزیشن "
        "مستقل و حتی در دو جهت مخالف روی یک نماد داشت. نوع حساب را بروکر هنگام ساخت حساب تعیین می‌کند و "
        "کاربر نمی‌تواند آن را تغییر دهد.",
        "MT5_ONLY", 0.85, category="مفاهیم پایه",
        definition="Netting: یک پوزیشن خالص برای هر نماد. Hedging: امکان چند پوزیشن مستقل روی یک نماد.",
        keywords=["netting", "hedging", "نوع حساب"],
        related_questions=["چرا معامله دومم با اولی ادغام شد؟", "چرا نمی‌تونم همزمان خرید و فروش بزنم؟"]),
]

# --------------------------------------------------------------------------- MT4
mt4 = [
    obj("MT4-PROC-0001", "METATRADER_PROCEDURE", "ورود به حساب معاملاتی در متاتریدر ۴",
        "در متاتریدر ۴ اتصال به حساب از منوی File > Login to Trade Account انجام می‌شود و به شماره‌ی حساب، "
        "رمز عبور و سرور بروکر نیاز دارد. وضعیت اتصال در گوشه‌ی پایین-راست نمایش داده می‌شود.",
        "MT4_ONLY", 0.85, category="اتصال و حساب",
        steps=["منوی File و سپس Login to Trade Account را باز کنید.",
               "شماره حساب، رمز عبور و سرور بروکر را وارد کنید.",
               "OK را بزنید و نوار وضعیت پایین-راست را بررسی کنید."],
        warnings=["اگر سرور بروکر در فهرست نبود، فایل srv بروکر باید در پوشه‌ی config قرار بگیرد یا از نصاب اختصاصی بروکر استفاده شود."],
        keywords=["login", "ورود", "متاتریدر ۴"],
        related_questions=["چطور وارد متاتریدر ۴ بشم؟", "سرور بروکر رو پیدا نمی‌کنم"]),
    obj("MT4-PROC-0002", "METATRADER_PROCEDURE", "نمایش همه‌ی نمادها در Market Watch (متاتریدر ۴)",
        "در متاتریدر ۴ با راست‌کلیک روی Market Watch و انتخاب Show All همه‌ی نمادهای در دسترس نمایش داده می‌شوند؛ "
        "برای فهرست کامل و گروه‌بندی‌شده از پنجره‌ی Symbols استفاده کنید.",
        "MT4_ONLY", 0.85, category="نمادها",
        steps=["روی Market Watch راست‌کلیک کنید.",
               "گزینه‌ی Show All را بزنید تا همه‌ی نمادها نمایش داده شوند.",
               "برای انتخاب دقیق‌تر، Symbols را باز کنید و نماد را Show کنید."],
        keywords=["show all", "market watch", "نماد"],
        related_questions=["چرا نماد رو نمی‌بینم؟", "چطور همه نمادها رو نشون بدم؟"]),
    obj("MT4-PROC-0003", "METATRADER_PROCEDURE", "باز کردن معامله و انواع سفارش در متاتریدر ۴",
        "پنجره‌ی Order با کلید F9 باز می‌شود. متاتریدر ۴ چهار نوع سفارش معلق دارد: Buy Limit، Sell Limit، "
        "Buy Stop و Sell Stop. سفارش‌های Stop Limit فقط در متاتریدر ۵ وجود دارند.",
        "MT4_ONLY", 0.85, category="معامله",
        steps=["نماد را در Market Watch انتخاب کنید.",
               "کلید F9 را بزنید.",
               "حجم (Volume)، و در صورت نیاز Stop Loss و Take Profit را وارد کنید.",
               "برای ورود فوری Buy یا Sell را بزنید یا Type را روی Pending Order بگذارید."],
        keywords=["F9", "order", "pending", "متاتریدر ۴"],
        related_questions=["چطور توی متاتریدر ۴ معامله باز کنم؟", "متاتریدر ۴ چند نوع سفارش معلق داره؟"]),
    obj("MT4-PROC-0004", "METATRADER_PROCEDURE", "تنظیم حد ضرر و حد سود روی معامله‌ی باز (متاتریدر ۴)",
        "در متاتریدر ۴ حد ضرر و حد سود از تب Trade در پنجره‌ی Terminal تنظیم می‌شود.",
        "MT4_ONLY", 0.85, category="مدیریت معامله",
        steps=["پنجره‌ی Terminal را باز کنید (Ctrl+T) و به تب Trade بروید.",
               "روی معامله راست‌کلیک و Modify or Delete Order را بزنید.",
               "مقادیر Stop Loss و Take Profit را وارد و Modify را بزنید."],
        keywords=["stop loss", "take profit", "modify order"],
        related_questions=["چطور حد ضرر بذارم متاتریدر ۴؟"]),
    obj("MT4-PROC-0005", "METATRADER_PROCEDURE", "فعال‌سازی AutoTrading و اکسپرت در متاتریدر ۴",
        "در متاتریدر ۴ معامله‌ی خودکار با دکمه‌ی AutoTrading (در نسخه‌های قدیمی‌تر Expert Advisors) فعال می‌شود "
        "و اکسپرت باید در پوشه‌ی MQL4/Experts قرار بگیرد.",
        "MT4_ONLY", 0.8, category="اکسپرت",
        steps=["File > Open Data Folder را باز کنید و فایل را در MQL4/Experts بگذارید.",
               "در Navigator روی Expert Advisors راست‌کلیک و Refresh بزنید.",
               "اکسپرت را روی چارت بکشید و Allow live trading را تیک بزنید.",
               "دکمه‌ی AutoTrading در نوار ابزار را فعال کنید."],
        keywords=["expert advisor", "MQL4", "autotrading"],
        related_questions=["اکسپرت متاتریدر ۴ رو چطور نصب کنم؟"]),
    obj("MT4-CONC-0001", "CONCEPT", "حسابداری معاملات در متاتریدر ۴ (فقط Hedging)",
        "متاتریدر ۴ فقط سیستم Hedging دارد: هر معامله یک تیکت مستقل است و می‌توان همزمان چند معامله‌ی "
        "خرید و فروش روی یک نماد باز داشت. مفهوم «پوزیشن خالص» (Netting) در متاتریدر ۴ وجود ندارد.",
        "MT4_ONLY", 0.85, category="مفاهیم پایه",
        definition="در متاتریدر ۴ هر سفارش یک معامله‌ی مستقل با تیکت مجزاست.",
        keywords=["hedging", "ticket", "پوزیشن"],
        related_questions=["می‌تونم همزمان خرید و فروش داشته باشم؟"]),
]

# ------------------------------------------------------------------ troubleshooting
trouble = [
    obj("MT-TRBL-0001", "TROUBLESHOOTING", "خطای Invalid S/L or T/P هنگام ثبت سفارش",
        "خطای «Invalid S/L or T/P» یعنی حد ضرر یا حد سود واردشده از نظر پلتفرم یا بروکر معتبر نیست. "
        "شایع‌ترین علت‌ها: قرار دادن حد ضرر در سمت اشتباه قیمت، نزدیک‌تر بودن آن از حداقل فاصله‌ی مجاز "
        "(Stops Level) و اشتباه در تعداد ارقام اعشار قیمت.",
        "BOTH", 0.8, category="خطاها",
        symptoms=["پیام Invalid S/L or T/P هنگام ثبت یا ویرایش سفارش", "سفارش ثبت نمی‌شود"],
        causes=["حد ضرر یا حد سود در سمت اشتباه قیمت قرار گرفته است.",
                "فاصله‌ی SL/TP از قیمت کمتر از Stops Level بروکر است.",
                "قیمت با ارقام اعشار اشتباه وارد شده است.",
                "نماد در حالت Freeze Level است و ویرایش موقتاً مجاز نیست."],
        resolutions=["مشخصات نماد (Specification) را باز کنید و مقدار Stops Level را ببینید.",
                     "SL/TP را با فاصله‌ی بیشتر از حداقل مجاز وارد کنید.",
                     "درست بودن سمت SL/TP نسبت به نوع معامله (خرید یا فروش) را بررسی کنید.",
                     "در صورت ادامه‌ی خطا، مقدار دقیق Stops Level را از پشتیبانی بروکر بپرسید."],
        keywords=["invalid stops", "stops level", "خطا"],
        related_questions=["چرا حد ضررم ثبت نمی‌شه؟", "invalid sl tp یعنی چی؟"]),
    obj("MT-TRBL-0002", "TROUBLESHOOTING", "خطای Market closed",
        "پیام «Market closed» یعنی نماد در آن لحظه خارج از ساعات معاملاتی خود است. ساعات معاملاتی هر نماد "
        "در پنجره‌ی Specification و بر اساس ساعت سرور بروکر تعریف شده است، نه ساعت محلی.",
        "BOTH", 0.85, category="خطاها",
        symptoms=["پیام Market closed هنگام ثبت سفارش"],
        causes=["نماد خارج از ساعات معاملاتی است (آخر هفته، تعطیلات یا وقفه‌ی روزانه).",
                "ساعت سرور بروکر با ساعت محلی متفاوت است."],
        resolutions=["ساعات معاملاتی نماد را در Specification بررسی کنید.",
                     "ساعت سرور را از ستون زمان در Market Watch ببینید.",
                     "برای نمادهای دارای وقفه‌ی روزانه (مثل شاخص‌ها و فلزات)، زمان وقفه را در نظر بگیرید."],
        keywords=["market closed", "ساعت بازار"],
        related_questions=["چرا نمی‌تونم معامله باز کنم؟", "بازار کی باز می‌شه؟"]),
    obj("MT-TRBL-0003", "TROUBLESHOOTING", "خطای Not enough money / کمبود مارجین",
        "پیام «Not enough money» یعنی مارجین آزاد حساب برای باز کردن معامله با حجم درخواستی کافی نیست. "
        "علت معمولاً حجم بیش از حد بزرگ نسبت به موجودی، یا اشغال بودن مارجین توسط معاملات باز است.",
        "BOTH", 0.85, category="خطاها",
        symptoms=["پیام Not enough money", "سفارش رد می‌شود"],
        causes=["حجم درخواستی نسبت به موجودی و اهرم حساب بیش از حد بزرگ است.",
                "بخش زیادی از مارجین توسط معاملات باز اشغال شده است.",
                "اهرم حساب پایین‌تر از تصور کاربر است."],
        resolutions=["حجم معامله را کاهش دهید.",
                     "مقدار Free Margin را در Toolbox/Terminal بررسی کنید.",
                     "اهرم حساب را از بروکر یا مشخصات حساب بررسی کنید.",
                     "در صورت نیاز، بخشی از معاملات باز را ببندید."],
        keywords=["not enough money", "margin", "کمبود موجودی"],
        related_questions=["چرا می‌گه پول کافی نیست؟", "با ۱۰۰ دلار چه حجمی بزنم؟"]),
    obj("MT-TRBL-0004", "TROUBLESHOOTING", "خطای Trade is disabled / معامله غیرفعال است",
        "پیام «Trade is disabled» یعنی امکان معامله روی حساب یا نماد غیرفعال است. این وضعیت سمت بروکر یا "
        "به دلیل ورود با رمز Investor رخ می‌دهد و با تنظیمات پلتفرم قابل حل نیست.",
        "BOTH", 0.75, category="خطاها",
        symptoms=["پیام Trade is disabled", "دکمه‌های خرید و فروش غیرفعال هستند"],
        causes=["ورود با رمز Investor به‌جای رمز اصلی.",
                "غیرفعال بودن معامله روی حساب از سمت بروکر.",
                "نماد در حالت Close Only یا فقط مشاهده قرار دارد."],
        resolutions=["با رمز اصلی (Master) دوباره وارد شوید.",
                     "وضعیت نماد را در Specification بررسی کنید.",
                     "در صورت ادامه، با پشتیبانی بروکر تماس بگیرید."],
        keywords=["trade disabled", "investor password"],
        related_questions=["چرا دکمه خرید غیرفعاله؟", "چرا نمی‌تونم معامله کنم؟"]),
    obj("MT-TRBL-0005", "TROUBLESHOOTING", "خطای No connection / قطع اتصال به سرور",
        "نمایش «No connection» یا «Invalid account» در نوار وضعیت یعنی ترمینال به سرور بروکر وصل نیست. "
        "پیش از هر کاری باید مشخص شود مشکل از اینترنت است یا از اطلاعات ورود.",
        "BOTH", 0.8, category="خطاها",
        symptoms=["نمایش No connection در گوشه‌ی پایین-راست", "قیمت‌ها به‌روزرسانی نمی‌شوند"],
        causes=["قطع بودن اینترنت یا محدودیت شبکه.", "اشتباه بودن سرور یا اطلاعات حساب.",
                "بسته شدن حساب یا تغییر سرور توسط بروکر."],
        resolutions=["اتصال اینترنت را بررسی کنید.",
                     "دوباره با سرور و اطلاعات صحیح Login کنید.",
                     "تب Journal را برای دیدن پیام دقیق خطا باز کنید.",
                     "در صورت ادامه، سرور جایگزین را از بروکر بگیرید."],
        keywords=["no connection", "journal", "قطعی"],
        related_questions=["چرا قیمت‌ها آپدیت نمی‌شه؟", "no connection یعنی چی؟"]),
]

# --------------------------------------------------------------- MT4 vs MT5 engine
def cmp_obj(oid, title, chunk, mt4v, mt5v, conf, **kw):
    return obj(oid, "COMPARISON", title, chunk, "VERSION_DEPENDENT", conf,
               category="تفاوت متاتریدر ۴ و ۵",
               comparison={"mt4": mt4v, "mt5": mt5v}, **kw)


compare = [
    cmp_obj("MT-CMP-0001", "تفاوت انواع سفارش معلق در متاتریدر ۴ و ۵",
            "متاتریدر ۴ چهار نوع سفارش معلق دارد و متاتریدر ۵ شش نوع؛ دو نوع Stop Limit فقط در متاتریدر ۵ موجود است.",
            "Buy Limit, Sell Limit, Buy Stop, Sell Stop (۴ نوع)",
            "Buy Limit, Sell Limit, Buy Stop, Sell Stop, Buy Stop Limit, Sell Stop Limit (۶ نوع)",
            0.85, keywords=["pending order", "stop limit", "تفاوت"],
            related_questions=["فرق سفارش‌های متاتریدر ۴ و ۵ چیه؟", "Buy Stop Limit توی متاتریدر ۴ هست؟"]),
    cmp_obj("MT-CMP-0002", "تفاوت حسابداری پوزیشن (Netting / Hedging)",
            "متاتریدر ۴ فقط Hedging است، اما متاتریدر ۵ بسته به نوع حسابی که بروکر می‌سازد می‌تواند Netting یا Hedging باشد.",
            "فقط Hedging؛ هر سفارش یک تیکت مستقل.",
            "Netting یا Hedging، وابسته به نوع حساب تعیین‌شده توسط بروکر.",
            0.85, keywords=["netting", "hedging"],
            related_questions=["چرا توی متاتریدر ۵ معامله‌هام ادغام می‌شن؟"]),
    cmp_obj("MT-CMP-0003", "تفاوت تعداد تایم‌فریم‌ها",
            "متاتریدر ۵ تایم‌فریم‌های به‌مراتب بیشتری نسبت به متاتریدر ۴ ارائه می‌دهد.",
            "۹ تایم‌فریم (M1, M5, M15, M30, H1, H4, D1, W1, MN1)",
            "۲۱ تایم‌فریم، شامل M2, M3, M4, M6, M10, M12, M20, H2, H3, H6, H8, H12",
            0.8, keywords=["timeframe", "تایم فریم"],
            related_questions=["چرا تایم‌فریم H2 ندارم؟", "متاتریدر ۵ چند تایم‌فریم داره؟"]),
    cmp_obj("MT-CMP-0004", "ناسازگاری اکسپرت‌ها و اندیکاتورها (MQL4 و MQL5)",
            "زبان برنامه‌نویسی دو پلتفرم متفاوت است و فایل‌های اکسپرت یا اندیکاتور یکی روی دیگری اجرا نمی‌شوند؛ "
            "برای هر پلتفرم باید نسخه‌ی مخصوص همان پلتفرم تهیه شود.",
            "MQL4؛ فایل‌های ex4 در پوشه‌ی MQL4.",
            "MQL5؛ فایل‌های ex5 در پوشه‌ی MQL5.",
            0.9, keywords=["MQL4", "MQL5", "ex4", "ex5"],
            related_questions=["اندیکاتور متاتریدر ۴ رو توی ۵ نصب کنم؟", "چرا اکسپرتم اجرا نمی‌شه؟"]),
    cmp_obj("MT-CMP-0005", "تفاوت تستر استراتژی",
            "تستر استراتژی متاتریدر ۵ چندنمادی و چندرشته‌ای است و امکان تست با تیک‌های واقعی را دارد؛ "
            "تستر متاتریدر ۴ تک‌نمادی و تک‌رشته‌ای است.",
            "تست تک‌نمادی، بدون پردازش موازی.",
            "تست چندنمادی، پردازش موازی و بهینه‌سازی پیشرفته با تیک واقعی.",
            0.8, keywords=["strategy tester", "backtest", "optimization"],
            related_questions=["بک‌تست کدوم پلتفرم بهتره؟"]),
    cmp_obj("MT-CMP-0006", "عمق بازار و تقویم اقتصادی داخلی",
            "عمق بازار (Depth of Market) و تقویم اقتصادی داخلی از قابلیت‌های متاتریدر ۵ هستند و در متاتریدر ۴ وجود ندارند.",
            "بدون Depth of Market و بدون تقویم اقتصادی داخلی.",
            "دارای Depth of Market و تقویم اقتصادی داخلی (نمایش داده‌ها وابسته به بروکر است).",
            0.75, keywords=["depth of market", "economic calendar"],
            related_questions=["تقویم اقتصادی متاتریدر کجاست؟"]),
]


def write(path, cid, title, desc, objs, notes):
    changed = K.write_collection(path, {
        "collection_id": cid, "domain": "metatrader", "title": title, "description": desc,
        "version": "v001", "generated_at": NOW, "pipeline_stage": "STRUCTURED",
        "source_files": ["tools/seed_metatrader.py"], "notes": notes, "objects": objs,
    })
    print("%s %s objects: %d" % ("wrote" if changed else "unchanged", K.rel(path), len(objs)))


NOTES = ["نمونه‌ی اول (sample-first) — پیش از تولید انبوه باید ساختار و صحت تأیید شود.",
         "همه‌ی رکوردها PENDING_VERIFICATION هستند و باید با مستندات رسمی MetaQuotes تطبیق داده شوند."]

write(K.KB_DIR + "/metatrader/mt5/mt5_core_v001.json", "metatrader_mt5_core",
      "دانش پایه و رویه‌های متاتریدر ۵",
      "رویه‌های عملیاتی و مفاهیم پایه‌ی متاتریدر ۵ برای پاسخ به سؤال‌های اجرایی دانشجو.", mt5, NOTES)
write(K.KB_DIR + "/metatrader/mt4/mt4_core_v001.json", "metatrader_mt4_core",
      "دانش پایه و رویه‌های متاتریدر ۴",
      "رویه‌های عملیاتی و مفاهیم پایه‌ی متاتریدر ۴ برای پاسخ به سؤال‌های اجرایی دانشجو.", mt4, NOTES)
write(K.KB_DIR + "/metatrader/mt_troubleshooting_v001.json", "metatrader_troubleshooting",
      "عیب‌یابی خطاهای رایج متاتریدر",
      "خطاهای پرتکرار پلتفرم و مسیر حل آن‌ها. دامنه‌ی هر رکورد با platform_scope مشخص شده است.",
      trouble, NOTES)
write(K.KB_DIR + "/metatrader/comparison/mt4_vs_mt5_v001.json", "metatrader_mt4_vs_mt5",
      "موتور تفاوت متاتریدر ۴ و ۵",
      "تفاوت‌های تأییدشدنی بین دو پلتفرم. هیچ رویه‌ای نباید بدون تعیین دامنه‌ی پلتفرم پاسخ داده شود.",
      compare, NOTES)

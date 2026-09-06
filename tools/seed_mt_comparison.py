#!/usr/bin/env python3
"""The MT4 / MT5 difference engine.

Rule MET-RULE-0005: no MetaTrader procedure is answered without a platform
scope. These records are what lets the mentor agent say "in MT4 ... but in
MT5 ..." instead of assuming the two platforms behave alike.
"""
import sys

sys.path.insert(0, __file__.rsplit("/", 1)[0])
import mt_lib as M  # noqa: E402
import kb_lib as K  # noqa: E402

M.SOURCE = "tools/seed_mt_comparison.py"


def cmp_obj(oid, title, chunk, mt4v, mt5v, conf, **kw):
    return M.obj(oid, "COMPARISON", title, chunk, "VERSION_DEPENDENT", conf,
                 category="تفاوت متاتریدر ۴ و ۵",
                 comparison={"mt4": mt4v, "mt5": mt5v}, **kw)


COMPARE = [
    cmp_obj("MT-CMP-0001", "تفاوت انواع سفارش معلق در متاتریدر ۴ و ۵",
            "متاتریدر ۴ چهار نوع سفارش معلق دارد و متاتریدر ۵ شش نوع؛ دو نوع Stop Limit فقط در متاتریدر ۵ موجود است.",
            "Buy Limit, Sell Limit, Buy Stop, Sell Stop (۴ نوع)",
            "Buy Limit, Sell Limit, Buy Stop, Sell Stop, Buy Stop Limit, Sell Stop Limit (۶ نوع)",
            0.85, keywords=["pending order", "stop limit", "تفاوت"],
            related_concepts=["MT5-CONC-0003", "MT4-PROC-0003"],
            related_questions=["فرق سفارش‌های متاتریدر ۴ و ۵ چیه؟", "Buy Stop Limit توی متاتریدر ۴ هست؟"]),
    cmp_obj("MT-CMP-0002", "تفاوت حسابداری پوزیشن (Netting / Hedging)",
            "متاتریدر ۴ فقط Hedging است، اما متاتریدر ۵ بسته به نوع حسابی که بروکر می‌سازد می‌تواند Netting یا Hedging باشد.",
            "فقط Hedging؛ هر سفارش یک تیکت مستقل.",
            "Netting یا Hedging، وابسته به نوع حساب تعیین‌شده توسط بروکر.",
            0.85, keywords=["netting", "hedging"],
            related_concepts=["MT5-CONC-0001", "MT4-CONC-0001"],
            related_questions=["چرا توی متاتریدر ۵ معامله‌هام ادغام می‌شن؟"],
            verified="نوار عنوان متاتریدر ۵ همان بروکر «Demo Account - Hedge» را نشان می‌داد — یعنی نوع حساب در متاتریدر ۵ نمایش داده می‌شود و بروکر آن را تعیین می‌کند، دقیقاً همان چیزی که رکورد می‌گوید."),
    cmp_obj("MT-CMP-0003", "تفاوت تعداد تایم‌فریم‌ها",
            "متاتریدر ۵ تایم‌فریم‌های به‌مراتب بیشتری نسبت به متاتریدر ۴ ارائه می‌دهد.",
            "۹ تایم‌فریم (M1, M5, M15, M30, H1, H4, D1, W1, MN1)",
            "۲۱ تایم‌فریم، شامل M2, M3, M4, M6, M10, M12, M20, H2, H3, H6, H8, H12",
            0.8, keywords=["timeframe", "تایم فریم"],
            related_concepts=["MT-CONC-0012"],
            related_questions=["چرا تایم‌فریم H2 ندارم؟", "متاتریدر ۵ چند تایم‌فریم داره؟"]),
    cmp_obj("MT-CMP-0004", "ناسازگاری اکسپرت‌ها و اندیکاتورها (MQL4 و MQL5)",
            "زبان برنامه‌نویسی دو پلتفرم متفاوت است و فایل‌های اکسپرت یا اندیکاتور یکی روی دیگری اجرا نمی‌شوند؛ "
            "برای هر پلتفرم باید نسخه‌ی مخصوص همان پلتفرم تهیه شود.",
            "MQL4؛ فایل‌های ex4 در پوشه‌ی MQL4.",
            "MQL5؛ فایل‌های ex5 در پوشه‌ی MQL5.",
            0.9, keywords=["MQL4", "MQL5", "ex4", "ex5"],
            related_concepts=["MT-PROC-0018", "MT-TRBL-0008"],
            related_questions=["اندیکاتور متاتریدر ۴ رو توی ۵ نصب کنم؟", "چرا اکسپرتم اجرا نمی‌شه؟"]),
    cmp_obj("MT-CMP-0005", "تفاوت تستر استراتژی",
            "تستر استراتژی متاتریدر ۵ چندنمادی و چندرشته‌ای است و امکان تست با تیک‌های واقعی را دارد؛ "
            "تستر متاتریدر ۴ تک‌نمادی و تک‌رشته‌ای است و کیفیت آن با شاخص Modelling quality سنجیده می‌شود.",
            "تست تک‌نمادی، بدون پردازش موازی، وابسته به کیفیت داده‌ی History Center.",
            "تست چندنمادی، پردازش موازی و بهینه‌سازی پیشرفته با امکان استفاده از تیک واقعی.",
            0.8, keywords=["strategy tester", "backtest", "optimization"],
            related_concepts=["MT5-PROC-0011", "MT4-PROC-0007"],
            related_questions=["بک‌تست کدوم پلتفرم بهتره؟"]),
    cmp_obj("MT-CMP-0006", "عمق بازار و تقویم اقتصادی داخلی",
            "عمق بازار (Depth of Market) و تقویم اقتصادی داخلی از قابلیت‌های متاتریدر ۵ هستند و در متاتریدر ۴ وجود ندارند.",
            "بدون Depth of Market و بدون تقویم اقتصادی داخلی.",
            "دارای Depth of Market و تقویم اقتصادی داخلی (نمایش داده‌ها وابسته به بروکر است).",
            0.75, keywords=["depth of market", "economic calendar"],
            related_concepts=["MT5-PROC-0009", "MT5-PROC-0010"],
            related_questions=["تقویم اقتصادی متاتریدر کجاست؟"]),
    cmp_obj("MT-CMP-0007", "تفاوت مدیریت داده‌های تاریخی",
            "در متاتریدر ۴ داده‌ی تاریخی معمولاً باید دستی از History Center دانلود شود و کیفیت آن بر بک‌تست "
            "اثر مستقیم دارد؛ متاتریدر ۵ داده را به‌صورت خودکار از سرور می‌گیرد و امکان دریافت داده‌ی تیکی دارد.",
            "History Center (کلید F2)، دانلود دستی، محدود به تنظیم Max bars in history.",
            "دریافت خودکار از سرور، به‌علاوه‌ی درخواست داده‌ی کندلی و تیکی از پنجره‌ی Symbols.",
            0.75, keywords=["history center", "داده تاریخی", "ticks"],
            related_concepts=["MT4-PROC-0006", "MT5-PROC-0014", "MT-TRBL-0012"],
            related_questions=["چرا چارت متاتریدر ۴ داده کم داره؟"]),
    cmp_obj("MT-CMP-0008", "تفاوت مدل معامله: تیکت در برابر Order/Deal/Position",
            "متاتریدر ۴ همه‌چیز را به‌صورت «سفارش با تیکت» می‌بیند، اما متاتریدر ۵ سه موجودیت جدا دارد. "
            "همین تفاوت باعث می‌شود شمارش معاملات در تاریخچه و گزارش‌های دو پلتفرم متفاوت باشد.",
            "یک موجودیت: Order/Trade با شماره‌ی تیکت.",
            "سه موجودیت: Order (درخواست)، Deal (اجرا) و Position (وضعیت باز).",
            0.8, keywords=["ticket", "order", "deal", "position"],
            related_concepts=["MT5-CONC-0002", "MT4-CONC-0002"],
            related_questions=["چرا تعداد معاملات دو پلتفرم فرق داره؟"]),
    cmp_obj("MT-CMP-0009", "تفاوت بستن جزئی معامله",
            "بستن جزئی در متاتریدر ۴ تیکت جدید می‌سازد، در حالی که در متاتریدر ۵ حجم پوزیشن کاهش می‌یابد و "
            "شناسه‌ی پوزیشن ثابت می‌ماند. در حساب Netting متاتریدر ۵ اصولاً یک پوزیشن واحد کم یا زیاد می‌شود.",
            "معامله بسته و با حجم باقی‌مانده و تیکت جدید بازسازی می‌شود.",
            "حجم همان پوزیشن کاهش می‌یابد؛ شناسه‌ی پوزیشن تغییر نمی‌کند.",
            0.75, keywords=["partial close", "بستن جزئی"],
            related_concepts=["MT4-PROC-0010", "MT-PROC-0010"],
            related_questions=["چرا بعد از بستن نصف معامله شماره‌ش عوض شد؟"]),
    cmp_obj("MT-CMP-0010", "تفاوت تنظیمات اجرای سفارش",
            "متاتریدر ۵ علاوه بر انحراف مجاز، امکان انتخاب نوع پر شدن سفارش (Filling) را می‌دهد که در "
            "متاتریدر ۴ وجود ندارد.",
            "فقط تنظیم انحراف مجاز (Deviation) در حساب‌های Instant Execution.",
            "انحراف مجاز به‌علاوه‌ی انتخاب Filling type: Fill or Kill، Immediate or Cancel یا Return.",
            0.75, keywords=["filling", "deviation", "execution"],
            related_concepts=["MT5-PROC-0008", "MT-CONC-0010"],
            related_questions=["Fill or Kill توی متاتریدر ۴ هست؟"],
            verified="در Specification متاتریدر ۵ ردیف Filling با مقدار Fill or Kill وجود داشت و در contract specification متاتریدر ۴ چنین ردیفی نبود — شاهد مستقیم همین تفاوت. از سه گزینه‌ی Filling فقط یکی دیده شد."),
    cmp_obj("MT-CMP-0011", "تفاوت ابزارهای پیش‌فرض و وضعیت توسعه",
            "متاتریدر ۵ اندیکاتورها و اشیاء گرافیکی بیشتری به‌صورت پیش‌فرض دارد و توسعه‌ی فعال متاکوتس روی "
            "همین نسخه متمرکز است؛ متاتریدر ۴ عمدتاً در حالت نگهداری قرار دارد. با این حال، انتخاب پلتفرم "
            "را در عمل بروکر و ابزارهای موردنیاز معامله‌گر تعیین می‌کند.",
            "مجموعه‌ی پیش‌فرض کوچک‌تر؛ اکوسیستم بسیار بزرگ اندیکاتورها و اکسپرت‌های قدیمی.",
            "مجموعه‌ی پیش‌فرض بزرگ‌تر؛ تمرکز توسعه و امکانات جدید روی این نسخه.",
            0.7, keywords=["اندیکاتور پیش‌فرض", "پشتیبانی", "انتخاب پلتفرم"],
            related_questions=["کدوم پلتفرم بهتره؟", "متاتریدر ۴ منسوخ شده؟"]),
    cmp_obj("MT-CMP-0012", "تفاوت نمایش معاملات و سفارش‌ها در تب Trade",
            "در متاتریدر ۴ همه‌ی معاملات باز و سفارش‌های معلق در یک فهرست نمایش داده می‌شوند، اما متاتریدر ۵ "
            "ابتدا پوزیشن‌ها و سپس سفارش‌های معلق را در دو بخش جدا نشان می‌دهد.",
            "یک فهرست واحد شامل معاملات باز و سفارش‌های معلق، هرکدام با شماره‌ی تیکت.",
            "دو بخش جدا: Positions و سپس Orders؛ سفارش معلق تا فعال نشدن پوزیشن محسوب نمی‌شود.",
            0.75, keywords=["trade tab", "positions", "orders"],
            related_concepts=["MT-PROC-0023", "MT-PROC-0022", "MT5-CONC-0002"],
            related_questions=["چرا سفارش معلقم توی لیست پوزیشن‌ها نیست؟"]),
]

M.write(K.KB_DIR + "/metatrader/comparison/mt4_vs_mt5.json", "metatrader_mt4_vs_mt5",
        "موتور تفاوت متاتریدر ۴ و ۵",
        "تفاوت‌های تأییدشدنی بین دو پلتفرم. هیچ رویه‌ای نباید بدون تعیین دامنه‌ی پلتفرم پاسخ داده شود.",
        COMPARE)

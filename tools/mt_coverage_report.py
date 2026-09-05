#!/usr/bin/env python3
"""Coverage report for the MetaTrader domain.

Maps every topic the project brief requires to the knowledge objects that
actually cover it, and verifies each referenced id really exists — so the
report can only ever under-claim, never over-claim. Topics with no object are
printed as gaps.
"""
import glob
import os
import sys

sys.path.insert(0, __file__.rsplit("/", 1)[0])
import kb_lib as K  # noqa: E402

TOPICS = [
    ("نصب پلتفرم و چند نسخه همزمان", ["MT-PROC-0001", "MT-TRBL-0016"]),
    ("ورود به حساب و انتخاب سرور", ["MT5-PROC-0001", "MT4-PROC-0001", "MT-TRBL-0005"]),
    ("ساخت حساب دمو", ["MT-PROC-0002"]),
    ("رمز عبور و رمز سرمایه‌گذار", ["MT-PROC-0003", "MT-TRBL-0004"]),
    ("Market Watch، Navigator و Toolbox", ["MT-CONC-0014"]),
    ("نمادها و نمایش آن‌ها", ["MT5-PROC-0002", "MT4-PROC-0002", "MT-CONC-0013", "MT-TRBL-0007"]),
    ("مشخصات نماد (Specification)", ["MT5-PROC-0005", "MT-CONC-0005"]),
    ("چارت‌ها، تمپلیت و پروفایل", ["MT-PROC-0005", "MT-PROC-0006", "MT-PROC-0007"]),
    ("تایم‌فریم‌ها", ["MT-CONC-0012", "MT-CMP-0003"]),
    ("اشیاء گرافیکی", ["MT-PROC-0008"]),
    ("اندیکاتورها", ["MT-PROC-0004", "MT-TRBL-0008"]),
    ("Bid و Ask", ["MT-CONC-0001"]),
    ("اسپرد", ["MT-CONC-0002", "GEN-DEF-0003"]),
    ("پوینت و پیپ", ["MT-CONC-0003", "GEN-DEF-0001", "GEN-DEF-0002"]),
    ("Tick Size و Tick Value", ["MT-CONC-0004"]),
    ("اندازه‌ی قرارداد و محدودیت حجم", ["MT-CONC-0005", "MT-TRBL-0009"]),
    ("مارجین و اهرم", ["MT-CONC-0006", "GEN-DEF-0006", "GEN-DEF-0007"]),
    ("مارجین کال و استاپ اوت", ["MT-CONC-0007", "GEN-DEF-0008"]),
    ("سواپ", ["MT-CONC-0008", "GEN-DEF-0011"]),
    ("سفارش بازار و سفارش معلق", ["MT5-PROC-0003", "MT4-PROC-0003", "MT-CMP-0001"]),
    ("سفارش‌های Stop، Limit و Stop Limit", ["MT5-CONC-0003", "MT-CMP-0001", "GEN-DEF-0020"]),
    ("حالت‌های اجرا، انحراف مجاز و ریکوت", ["MT-CONC-0010", "MT5-PROC-0008", "MT-TRBL-0006", "MT-CMP-0010"]),
    ("حد ضرر و حد سود", ["MT5-PROC-0004", "MT4-PROC-0004", "MT-TRBL-0001"]),
    ("Stops Level و Freeze Level", ["MT-CONC-0009"]),
    ("تریلینگ استاپ", ["MT-PROC-0011"]),
    ("معامله‌ی یک‌کلیکی", ["MT-PROC-0009"]),
    ("ویرایش و بستن معامله (کامل و جزئی)", ["MT-PROC-0010", "MT4-PROC-0010", "MT-CMP-0009"]),
    ("مدیریت پوزیشن: Netting و Hedging", ["MT5-CONC-0001", "MT4-CONC-0001", "MT5-PROC-0013", "MT-CMP-0002"]),
    ("تاریخچه، Deals و گزارش‌گیری", ["MT5-PROC-0006", "MT5-PROC-0012", "MT4-PROC-0008", "MT5-CONC-0002", "MT-CMP-0008"]),
    ("هشدار قیمتی و اعلان موبایل", ["MT-PROC-0012", "MT-PROC-0013"]),
    ("اکسپرت و AutoTrading", ["MT5-PROC-0007", "MT4-PROC-0005", "MT-TRBL-0010"]),
    ("MetaEditor، MQL4 و MQL5", ["MT-PROC-0018", "MT-CMP-0004"]),
    ("اسکریپت‌ها", ["MT-PROC-0019"]),
    ("تستر استراتژی و بهینه‌سازی", ["MT5-PROC-0011", "MT4-PROC-0007", "MT-CMP-0005"]),
    ("VPS و میزبانی مجازی", ["MT-PROC-0016"]),
    ("Journal و Experts log", ["MT-CONC-0016"]),
    ("پوشه‌ی داده و ساختار فایل‌ها", ["MT-CONC-0015", "MT-PROC-0020"]),
    ("داده‌ی تاریخی و همگام‌سازی", ["MT4-PROC-0006", "MT5-PROC-0014", "MT-TRBL-0012", "MT-CMP-0007"]),
    ("زمان سرور بروکر", ["MT-CONC-0011", "MT-TRBL-0013"]),
    ("ترمینال موبایل و وب‌ترمینال", ["MT-PROC-0014", "MT-PROC-0015"]),
    ("تنظیمات پلتفرم (Options)", ["MT-PROC-0017"]),
    ("عمق بازار و تقویم اقتصادی", ["MT5-PROC-0009", "MT5-PROC-0010", "MT-CMP-0006"]),
    ("خطاهای رایج پلتفرم", ["MT-TRBL-0002", "MT-TRBL-0003", "MT-TRBL-0011", "MT-TRBL-0014",
                             "MT-TRBL-0015", "MT-TRBL-0017"]),
    ("تیکت، کامنت و Magic Number (متاتریدر ۴)", ["MT4-CONC-0002"]),
    ("چارت آفلاین (متاتریدر ۴)", ["MT4-PROC-0009"]),
    ("انتخاب بین متاتریدر ۴ و ۵", ["MT-CMP-0011"]),
]

KNOWN_GAPS = [
    ("اعداد اختصاصی بروکر (اسپرد، کمیسیون، سواپ، اهرم، Stops Level)",
     "نیازمند مستندات بروکر — `RQ-0004`. تا آن زمان پاسخ باید به مشخصات نماد در پلتفرم خود دانشجو ارجاع داده شود."),
    ("آموزش برنامه‌نویسی MQL4/MQL5",
     "فقط در حد استفاده و کامپایل پوشش داده شده است؛ آموزش زبان، خارج از دامنه‌ی پشتیبانی مربی است."),
    ("MetaTrader Market، Signals و کپی‌تریدینگ",
     "سیاست آکادمی درباره‌ی خرید اکسپرت و کپی‌تریدینگ مشخص نیست — نیازمند تصمیم آکادمی."),
    ("قابلیت‌های بورسی متاتریدر ۵ (Exchange execution، فیوچرز)",
     "برای دانشجویان فارکس کاربرد ندارد؛ عمداً پوشش داده نشده تا دامنه باریک بماند."),
]


def main():
    objects = {}
    for path in K.iter_collection_files():
        for obj in K.load_json(path).get("objects", []):
            objects[obj.get("id")] = obj

    rows, covered_ids, missing = [], set(), []
    for topic, ids in TOPICS:
        present = [i for i in ids if i in objects]
        absent = [i for i in ids if i not in objects]
        covered_ids.update(present)
        missing.extend((topic, i) for i in absent)
        state = "✅" if present and not absent else ("⚠️" if present else "❌")
        rows.append((state, topic, present, absent))

    # knowledge objects only: review items and conflicts also carry a domain
    mt_objects = [o for o in objects.values()
                  if o.get("domain") == "metatrader" and o.get("object_type")]
    by_scope = {}
    for o in mt_objects:
        by_scope[o.get("platform_scope")] = by_scope.get(o.get("platform_scope"), 0) + 1
    orphans = sorted(o["id"] for o in mt_objects if o["id"] not in covered_ids)

    lines = [
        "# پوشش دانش متاتریدر",
        "",
        "> نگاشت موضوع‌های خواسته‌شده در تعریف پروژه به رکوردهای واقعی پایگاه دانش. "
        "هر شناسه پیش از درج، در پایگاه دانش بررسی شده است؛ بنابراین این جدول نمی‌تواند ادعای بی‌پشتوانه داشته باشد.",
        "",
        "| | |", "|---|---|",
        "| تعداد رکورد دامنه‌ی متاتریدر | %d |" % len(mt_objects),
        "| موضوع‌های پوشش‌داده‌شده | %d از %d |" % (sum(1 for r in rows if r[0] == "✅"), len(rows)),
        "| وضعیت تأیید | همه PENDING_VERIFICATION — بدون دسترسی به مستندات رسمی متاکوتس (`RQ-0007`) |",
        "| تفکیک پلتفرم | " + "، ".join("%s: %d" % (k, v) for k, v in sorted(by_scope.items())) + " |",
        "",
        "## جدول پوشش",
        "",
        "| وضعیت | موضوع | رکوردها |",
        "|---|---|---|",
    ]
    for state, topic, present, absent in rows:
        cell = "، ".join("`%s`" % i for i in present) or "—"
        if absent:
            cell += " (ناموجود: %s)" % "، ".join("`%s`" % i for i in absent)
        lines.append("| %s | %s | %s |" % (state, topic, cell))

    lines += ["", "## شکاف‌های باقی‌مانده", ""]
    for title, note in KNOWN_GAPS:
        lines.append("- **%s** — %s" % (title, note))

    if orphans:
        lines += ["", "## رکوردهای خارج از جدول موضوعی", "",
                  "این رکوردها در پایگاه دانش هستند اما به هیچ موضوع فهرست بالا نگاشت نشده‌اند:", "",
                  "، ".join("`%s`" % i for i in orphans)]

    lines += ["", "---", "",
              "ساخته‌شده توسط `tools/mt_coverage_report.py` — دستی ویرایش نشود."]
    content = "\n".join(lines) + "\n"

    out_dir = os.path.join(K.EXPORT_DIR, "metatrader")
    previous = sorted(glob.glob(os.path.join(out_dir, "mt_coverage_v*.md")))
    if previous and open(previous[-1], encoding="utf-8").read() == content:
        print("coverage report unchanged (%s)" % K.rel(previous[-1]))
        return 0
    version = K.next_version(out_dir, "mt_coverage", ".md")
    path = os.path.join(out_dir, "mt_coverage_%s.md" % version)
    K.write_text(path, content)
    print("wrote %s (%d topics, %d MetaTrader objects)" % (K.rel(path), len(rows), len(mt_objects)))
    if missing:
        print("  WARNING: %d referenced ids do not exist: %s" %
              (len(missing), ", ".join("%s->%s" % m for m in missing)))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

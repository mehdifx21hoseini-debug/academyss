#!/usr/bin/env python3
"""Reduce a domain review to the handful of facts that can actually be wrong.

Reviewing 99 MetaTrader records means reading 99 explanations. But the
explanations are not what needs checking — the Persian around a procedure is
ours and reads fine either way. What can be wrong is the small, factual
surface: a menu path, a button label, a keyboard shortcut, the exact text of an
error, a platform limit. Those came from general knowledge of the platform with
no access to MetaQuotes documentation, so those are the claims at risk.

That surface is far smaller than the record count, because the same claim
appears in many records: `Tools > Options` is in four, `Market Watch` in
twenty-one. So this groups the claims by the screen they live on, lists which
records depend on each one, and asks for one yes/no per claim.

The payoff: check ~40 facts against a live platform once, and the answers
propagate to all 99 records — and where a claim is wrong, the file already
names every record that has to change.

    python3 tools/kb_ui_claims.py [--domain metatrader]
"""
import argparse
import collections
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import kb_lib as K  # noqa: E402

MENU_PATH = re.compile(
    r"[A-Z][A-Za-z0-9 /]{1,28}(?:\s*[>›→]\s*[A-Za-z][A-Za-z0-9 /]{1,28}){1,4}")
SHORTCUT = re.compile(r"(?:Ctrl|Alt|Shift)\s*\+\s*[A-Za-z0-9]+|(?<![A-Za-z])F(?:[1-9]|1[0-2])(?![A-Za-z0-9])")
ERROR_NAME = re.compile(r"خطای\s+([A-Za-z][A-Za-z0-9 /'’\-]{2,40})")
QUOTED_EN = re.compile(r"[«\"]([A-Za-z][A-Za-z0-9 ./'’\-]{2,40})[»\"]")
# Bare English UI labels — «Market Watch», «Stops Level» — appear far more often
# than quoted ones and are exactly the names a wrong build would change.
BARE_EN = re.compile(r"\b[A-Z][A-Za-z]{2,}(?:\s[A-Z][A-Za-z]{2,}){0,2}\b")
# Words that are English in the text but are not interface labels, so asking
# someone to verify them against a screen would waste the one thing being saved.
NOT_UI = {
    "Invalid", "Market", "Trade", "Old", "Not", "Off", "Context", "Busy",
    "Closed", "Disabled", "Enough", "Money", "Quotes", "Version", "Update",
    "For", "The", "And", "You", "This", "Metatrader", "MetaTrader",
    "MetaQuotes", "Windows", "Linux", "Wine", "VPS", "PDF",
}

# Which screen a claim belongs to, so one screenshot answers a whole group.
SCREENS = [
    ("منوی File", ("file", "profiles", "open data folder", "login", "open an account")),
    ("پنجره‌ی Tools > Options", ("tools", "options", "expert advisors", "charts", "server")),
    ("پنجره‌ی Market Watch", ("market watch", "symbols", "specification", "tick chart",
                               "bid", "ask", "spread")),
    ("پنجره‌ی Navigator", ("navigator", "indicators", "experts", "scripts", "advisors")),
    ("پنجره‌ی Terminal / Toolbox", ("terminal", "toolbox", "trade", "history", "journal",
                                     "experts log", "mailbox")),
    ("پنجره‌ی سفارش (New Order)", ("new order", "order", "deviation", "filling", "volume",
                                     "stop loss", "take profit", "modify")),
    ("منوی Insert و ابزار چارت", ("insert", "template", "objects", "period", "chart")),
    ("نوار ابزار و میان‌بُرها", ("autotrading", "algo trading", "one click", "ctrl", "alt", "shift")),
]


def screen_of(text):
    low = text.lower()
    for name, needles in SCREENS:
        if any(n in low for n in needles):
            return name
    return "سایر"


def texts_of(obj):
    parts = [obj.get("chunk_text") or "", obj.get("title") or ""]
    for field in ("steps", "resolutions", "causes", "symptoms", "warnings",
                  "conditions", "examples", "common_mistakes"):
        parts.extend(str(x) for x in (obj.get(field) or []))
    comparison = obj.get("comparison") or {}
    for value in comparison.values():
        if isinstance(value, list):
            parts.extend(str(v) for v in value)
        else:
            parts.append(str(value))
    return parts


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--domain", default="metatrader")
    ap.add_argument("--out", default=os.path.join(K.EXPORT_DIR, "review"))
    args = ap.parse_args()

    claims = collections.defaultdict(set)   # (kind, claim) -> record ids
    total = 0
    for path in K.iter_collection_files():
        if K.record_kind(path) != "knowledge_object":
            continue
        for obj in K.load_json(path).get("objects", []):
            if obj.get("domain") != args.domain:
                continue
            total += 1
            blob = "\n".join(texts_of(obj))
            for match in MENU_PATH.finditer(blob):
                claim = re.sub(r"\s*[>›→]\s*", " > ", match.group(0).strip())
                claims[("مسیر منو", claim)].add(obj["id"])
            for match in SHORTCUT.finditer(blob):
                claims[("میان‌بُر", match.group(0).replace(" ", ""))].add(obj["id"])
            for match in ERROR_NAME.finditer(blob):
                claims[("متن خطا", match.group(1).strip())].add(obj["id"])
            for match in QUOTED_EN.finditer(blob):
                claims[("برچسب رابط", match.group(1).strip())].add(obj["id"])
            for match in BARE_EN.finditer(blob):
                label = match.group(0).strip()
                if label in NOT_UI or label.split()[0] in NOT_UI:
                    continue
                claims[("برچسب رابط", label)].add(obj["id"])

    # Two filters on bare labels, because unfiltered they bury the real claims.
    #
    # A label seen in one record only is usually prose, not an interface name.
    # And a single capitalised word is usually a FRAGMENT of a longer label that
    # the regex split on a lowercase connector — «Fill» and «Kill» out of "Fill
    # or Kill", «Max» out of "Max deviation". Asking someone to verify those
    # wastes exactly the time this file exists to save, so a single word counts
    # only when it names a panel or mode on its own.
    #
    # Menu paths, shortcuts and error strings are kept even when they appear
    # once: those are the specific claims most worth checking.
    STANDALONE = {
        "Navigator", "Toolbox", "Terminal", "MetaEditor", "Specification",
        "Hedging", "Netting", "Digits", "Investor", "Master", "AutoTrading",
        "Journal", "Mailbox", "Alerts", "Experts", "Scripts", "Indicators",
        "Templates", "Profiles", "Options", "Deviation", "Spread", "Swap",
        "Commission", "Equity", "Margin", "Balance",
    }
    claims = {
        k: v for k, v in claims.items()
        if k[0] != "برچسب رابط"
        or (len(v) >= 2 and (" " in k[1] or k[1] in STANDALONE))
    }

    by_screen = collections.defaultdict(list)
    for (kind, claim), ids in claims.items():
        by_screen[screen_of(claim)].append((kind, claim, sorted(ids)))

    ordered = [name for name, _ in SCREENS if name in by_screen]
    ordered += [k for k in sorted(by_screen) if k not in ordered]

    covered = set()
    for items in by_screen.values():
        for _, _, ids in items:
            covered.update(ids)

    lines = [
        "# چک‌لیست سریع دانش متاتریدر",
        "",
        "**%d ادعای قابل بررسی، برگرفته از %d رکورد.**" % (len(claims), total),
        "",
        "## چرا این به‌جای خواندن ۹۹ رکورد",
        "",
        "متن فارسی توضیح‌ها نوشته‌ی ماست و اشتباه بودنش خطر ندارد. آنچه می‌تواند",
        "غلط باشد یک سطح کوچک و واقعی است: مسیر منو، نام دکمه، میان‌بُر کیبورد،",
        "متن دقیق خطا. این‌ها از دانش عمومی پلتفرم نوشته شده‌اند، بدون دسترسی به",
        "مستندات رسمی متاکوتس — پس همین‌ها در معرض اشتباه‌اند.",
        "",
        "و این سطح خیلی کوچک‌تر از ۹۹ است، چون یک ادعا در چند رکورد تکرار می‌شود.",
        "کنار هر ادعا نوشته‌ام کدام رکوردها به آن وابسته‌اند: **اگر ادعایی غلط",
        "باشد، همان لحظه می‌دانم کدام رکوردها باید اصلاح شوند.**",
        "",
        "## چطور سریع انجامش بدهید",
        "",
        "متاتریدر را باز کنید و هر بخش را با صفحه‌ی متناظرش بسنجید. اگر راحت‌تر",
        "است، فقط از همان صفحه‌ها **اسکرین‌شات بگیرید و بفرستید** — خودم تطبیق",
        "می‌دهم و نتیجه را اعمال می‌کنم.",
        "",
        "کنار هر سطر: ✅ درست · ❌ غلط (و اگر می‌دانید، شکل درستش)",
        "",
        "---",
        "",
    ]

    for screen in ordered:
        items = sorted(by_screen[screen], key=lambda x: (x[0], x[1].lower()))
        lines += ["## %s — %d ادعا" % (screen, len(items)), ""]
        lines += ["| ادعا | نوع | رکوردهای وابسته | درست؟ |",
                  "|---|---|---|---|"]
        for kind, claim, ids in items:
            shown = "، ".join(ids[:4]) + (" و %d مورد دیگر" % (len(ids) - 4) if len(ids) > 4 else "")
            lines.append("| `%s` | %s | %s | ⬜ |" % (claim, kind, shown))
        lines.append("")

    lines += [
        "---",
        "",
        "## آنچه این چک‌لیست پوشش نمی‌دهد",
        "",
        "%d رکورد از %d رکورد هیچ ادعای رابط‌کاربری ندارند — مفهومی‌اند"
        % (total - len(covered), total),
        "(مثل تعریف پوینت، Tick Value یا تفاوت نتینگ و هجینگ). آن‌ها با",
        "خواندن برگه‌ی کامل بازبینی می‌شوند، ولی خطرشان کمتر است چون به",
        "بیلد پلتفرم وابسته نیستند.",
        "",
    ]

    if not os.path.isdir(args.out):
        os.makedirs(args.out)
    prefix = "%s_ui_claims" % args.domain
    version = K.next_version(args.out, prefix, ".md")
    path = os.path.join(args.out, "%s_%s.md" % (prefix, version))
    K.write_text(path, "\n".join(lines).rstrip() + "\n")

    print("md  : %s" % K.rel(path))
    print("ادعاها: %d · از %d رکورد · رکوردهای درگیر: %d"
          % (len(claims), total, len(covered)))
    for screen in ordered:
        print("   %-32s %d" % (screen, len(by_screen[screen])))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

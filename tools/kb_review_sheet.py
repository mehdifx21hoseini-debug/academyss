#!/usr/bin/env python3
"""Build a human review sheet for one domain, so the owner can approve records.

Nothing in the knowledge base becomes an official answer until a person says
so: `approval_status` is what separates "we wrote it down" from "the mentor may
say this". This produces the document that decision is made on.

Two files, because approving 99 records is a chore and the format should not
add to it:

  * <domain>_review_vNNN.md  — readable, with the full text of every record and
    a line to mark. Ordered so the records students actually hit come first: if
    the reviewer stops halfway, the half that got done is the half that matters.
  * <domain>_review_vNNN.csv — the same list for Excel, with an empty تأیید
    column to fill in.

Priority ordering is stated in the sheet rather than assumed: procedures and
troubleshooting entries with the most recorded student phrasings first, because
"how do I" and "it's broken" are what support traffic is actually made of.

    python3 tools/kb_review_sheet.py --domain metatrader [--top 20]
"""
import argparse
import csv
import io
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import kb_lib as K  # noqa: E402

PLATFORM_FA = {
    "MT4_ONLY": "فقط متاتریدر ۴", "MT5_ONLY": "فقط متاتریدر ۵",
    "BOTH": "هر دو", "BROKER_DEPENDENT": "وابسته به بروکر",
    "VERSION_DEPENDENT": "وابسته به نسخه", "NOT_APPLICABLE": "—",
}
TYPE_FA = {
    "CONCEPT": "مفهوم", "DEFINITION": "تعریف", "GLOSSARY": "واژه",
    "PROCEDURE": "رویه", "METATRADER_PROCEDURE": "رویه",
    "TROUBLESHOOTING": "عیب‌یابی", "COMPARISON": "مقایسه", "RULE": "قاعده",
    "EXAMPLE": "مثال", "COMMON_MISTAKE": "اشتباه رایج",
    "OPERATIONAL_FACT": "اطلاعات عملیاتی", "CATALOG_ITEM": "کاتالوگ",
}
HANDS_ON = {"PROCEDURE", "METATRADER_PROCEDURE", "TROUBLESHOOTING"}

# How much of the shorter phrasing must be shared before an overlap counts as
# "a student really asked this". Set where the star stays rare enough to mean
# something — a mark that lands on most records tells the reviewer nothing.
MATCH_FLOOR = 0.6

# Persian normalisation, matching how the runtime compares text: Arabic ی/ک and
# the zero-width joiner make identical words look different byte-for-byte.
_STOP = set(("و در به از که این را با است برای می ها های تر ترین یک هم آن یا اگر"
             " تا بر چه چی چیست چیه شود شده کنید کنم کند دارد داره باشد بود نیست"
             " هست شما ما من او آیا کدام چطور چگونه کجا چرا وقتی مورد چند").split())


def tokens(text):
    text = re.sub(r"[يى]", "ی", str(text or ""))
    text = re.sub(r"[ك]", "ک", text)
    text = re.sub(r"[\u200b-\u200f\ufeff]", "", text)
    parts = re.split(r"[^\w\u0600-\u06FF]+", text.lower())
    return {p for p in parts if len(p) > 2 and p not in _STOP}


def real_questions():
    """The questions students actually asked, from the mentor Q&A layer.

    This is the only usage evidence the project has. Ranking a review sheet by
    it beats ranking by id, which is what "most used" would otherwise quietly
    mean — and it is why MetaEditor does not outrank "the chart is blank".
    """
    out = []
    for path in K.iter_collection_files():
        if K.record_kind(path) != "mentor_qa":
            continue
        for obj in K.load_json(path).get("objects", []):
            texts = [obj.get(f) for f in ("question_normalized", "question_raw")]
            texts += list(obj.get("question_variants") or [])
            for text in texts:
                if text:
                    out.append((tokens(text), text.strip()))
    return [(t, text) for t, text in out if t]


def demand_score(obj, asked):
    """How close this record sits to something a student really asked.

    Each of the record's own phrasings is compared separately, and the overlap
    is divided by the SHORTER of the two — not by the asked question. Dividing
    by the asked question buries the entries that matter most: "چرا نمی‌تونم
    معامله باز کنم؟" is a short, complete match for a long real question, and
    normalising by the long side scores it as a near miss.
    """
    own = [tokens(obj.get("title"))]
    own += [tokens(q) for q in (obj.get("related_questions") or [])]
    keywords = set()
    for k in (obj.get("keywords") or []):
        keywords |= tokens(k)
    if keywords:
        own.append(keywords)
    own = [o for o in own if o]
    best, hit = 0.0, None
    for mine in own:
        for score_q, text in asked:
            shared = mine & score_q
            if not shared:
                continue
            # One shared word is a coincidence, not a match: «معامله» alone
            # links half the platform records to half the questions. Two
            # content words is the floor for calling it evidence.
            if len(shared) < 2:
                continue
            score = len(shared) / float(min(len(mine), len(score_q)))
            if score > best:
                best, hit = score, text
    return best, hit


def body_of(obj):
    """The whole record as a reader needs to see it — not just chunk_text.

    A procedure reviewed without its steps, or a troubleshooting entry without
    its causes, is not actually being reviewed.
    """
    out = [obj.get("chunk_text") or ""]
    if obj.get("definition"):
        out.append("**تعریف:** " + obj["definition"])
    if obj.get("rule"):
        out.append("**قاعده:** " + obj["rule"])
    if obj.get("steps"):
        out.append("**گام‌ها:**\n" + "\n".join(
            "%d. %s" % (i, s) for i, s in enumerate(obj["steps"], 1)))
    for field, label in (("symptoms", "نشانه‌ها"), ("causes", "علت‌ها"),
                         ("resolutions", "راه‌حل‌ها"), ("common_mistakes", "اشتباهات رایج"),
                         ("examples", "مثال‌ها"), ("conditions", "شرط‌ها"),
                         ("exceptions", "استثناها"), ("warnings", "هشدارها")):
        if obj.get(field):
            out.append("**%s:**\n" % label + "\n".join("- %s" % x for x in obj[field]))
    if obj.get("comparison"):
        rows = []
        for key, value in obj["comparison"].items():
            if isinstance(value, list):
                value = "، ".join(str(v) for v in value)
            rows.append("- **%s:** %s" % (key, value))
        out.append("**مقایسه:**\n" + "\n".join(rows))
    return "\n\n".join(p for p in out if p and p.strip())


# Review order within a section. This is a stated principle, not a usage
# ranking — the project has no usage data, and ordering by a made-up score
# would dress a guess as evidence. What it does use: a wrong answer to "it is
# broken" costs a student the most and is the fastest thing for a mentor to
# check from memory, so troubleshooting leads.
SECTION_ORDER = [
    "metatrader_troubleshooting", "metatrader_common_procedures",
    "metatrader_mt5_core", "metatrader_mt4_core",
    "metatrader_concepts", "metatrader_mt4_vs_mt5",
]


def make_priority(asked):
    def key(obj):
        score, _ = demand_score(obj, asked)
        return (-round(score, 3), obj.get("id", ""))

    return key


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--domain", default="metatrader")
    ap.add_argument("--out", default=os.path.join(K.EXPORT_DIR, "review"))
    args = ap.parse_args()

    groups, objects = [], []
    for path in K.iter_collection_files():
        # Review items and conflict records carry a domain too, but they are
        # governance about the knowledge, not knowledge to be approved.
        if K.record_kind(path) != "knowledge_object":
            continue
        coll = K.load_json(path)
        picked = [o for o in coll.get("objects", []) if o.get("domain") == args.domain]
        if picked:
            groups.append((coll.get("collection_id") or "", coll.get("title")
                           or K.rel(path), picked))
            objects.extend(picked)
    if not objects:
        print("رکوردی در دامنه‌ی %s پیدا نشد." % args.domain)
        return 1

    asked = real_questions()
    priority = make_priority(asked)
    order = {cid: i for i, cid in enumerate(SECTION_ORDER)}
    groups.sort(key=lambda g: (order.get(g[0], len(order)), g[1]))
    approved = sum(1 for o in objects if o.get("approval_status") == "APPROVED")
    matches = {o["id"]: demand_score(o, asked) for o in objects}
    starred = sum(1 for v in matches.values() if v[0] >= MATCH_FLOOR)

    lines = [
        "# برگه‌ی بازبینی — دانش متاتریدر",
        "",
        "**تعداد رکورد:** %d · **تأییدشده تا امروز:** %d" % (len(objects), approved),
        "",
        "## چرا این برگه",
        "",
        "این رکوردها ساخته شده‌اند اما **هیچ‌کدام تأیید نشده‌اند**. تا وقتی تأیید نشوند،",
        "مربی مجاز نیست آن‌ها را به‌عنوان پاسخ رسمی بدهد. منبعشان هم آکادمی نیست:",
        "بر پایه‌ی دانش عمومی از پلتفرم نوشته شده‌اند، بدون دسترسی به مستندات رسمی",
        "متاکوتس (شبکه در محیط پردازش بسته بود). پس ممکن است مسیر منوها یا متن",
        "خطاها با بیلد فعلی پلتفرم فرق داشته باشد.",
        "",
        "پرسش شما برای هر رکورد یکی است: **آیا این درست است و مربی می‌تواند آن را",
        "به دانشجو بگوید؟**",
        "",
        "## چطور علامت بزنید",
        "",
        "- **تأیید** — درست است",
        "- **اصلاح** — و بنویسید چه چیزی باید عوض شود",
        "- **حذف** — اشتباه است یا به کار ما نمی‌آید",
        "",
        "لازم نیست همه را یک‌جا انجام دهید. هر بخش که تمام شد بفرستید، همان را",
        "اعمال می‌کنم.",
        "",
        "## ترتیب",
        "",
        "**این ترتیب بر اساس آمار استفاده نیست — چون آماری از استفاده نداریم و",
        "نمی‌خواهم حدس را به‌جای شاهد جا بزنم.** ترتیب بر یک اصل است: عیب‌یابی",
        "اول، چون پاسخ اشتباه به «کار نمی‌کند» بیشترین هزینه را برای دانشجو دارد",
        "و سریع‌ترین چیزی است که یک منتور از حفظ می‌تواند تأیید کند.",
        "",
        "⭐ کنار %d رکورد یعنی با سؤالی که واقعاً یک دانشجو پرسیده هم‌پوشانی دارد؛" % starred,
        "خودِ آن سؤال هم زیرش نوشته شده. این تنها شاهد واقعی است که در اختیار داریم.",
        "",
        "---",
        "",
    ]

    number = 0
    for _, title, picked in groups:
        lines += ["## %s — %d رکورد" % (title, len(picked)), ""]
        for obj in sorted(picked, key=priority):
            number += 1
            score, hit = matches[obj["id"]]
            star = " ⭐" if score >= MATCH_FLOOR else ""
            lines += ["### %d. %s — %s%s" % (number, obj["id"], obj.get("title", ""), star), ""]
            lines += ["**پلتفرم:** %s · **نوع:** %s" % (
                PLATFORM_FA.get(obj.get("platform_scope"), obj.get("platform_scope") or "—"),
                TYPE_FA.get(obj.get("object_type"), obj.get("object_type") or "—")), ""]
            lines += [body_of(obj), ""]
            if obj.get("related_questions"):
                lines += ["*سؤال‌هایی که به این رکورد می‌رسند:* "
                          + " · ".join("«%s»" % q for q in obj["related_questions"]), ""]
            if star:
                lines += ["*پرسش واقعی دانشجو:* «%s»" % hit, ""]
            lines += ["**نظر شما:** ⬜ تأیید ⬜ اصلاح ⬜ حذف", "", "---", ""]

    if not os.path.isdir(args.out):
        os.makedirs(args.out)
    prefix = "%s_review" % args.domain
    version = K.next_version(args.out, prefix, ".md")
    md_path = os.path.join(args.out, "%s_%s.md" % (prefix, version))
    K.write_text(md_path, "\n".join(lines).rstrip() + "\n")

    csv_path = os.path.join(args.out, "%s_%s.csv" % (prefix, version))
    with io.open(csv_path, "w", encoding="utf-8-sig", newline="") as fh:
        writer = csv.writer(fh, lineterminator="\n")
        writer.writerow(["ردیف", "بخش", "شناسه", "پرسیده‌شده", "پلتفرم", "نوع",
                         "عنوان", "متن", "تأیید (تأیید/اصلاح/حذف)", "توضیح شما"])
        row = 0
        for _, title, picked in groups:
            for obj in sorted(picked, key=priority):
                row += 1
                score, hit = matches[obj["id"]]
                writer.writerow([
                    row, title, obj["id"], hit if score >= MATCH_FLOOR else "",
                    PLATFORM_FA.get(obj.get("platform_scope"), ""),
                    TYPE_FA.get(obj.get("object_type"), obj.get("object_type") or ""),
                    obj.get("title", ""), body_of(obj).replace("**", ""), "", "",
                ])

    print("md  : %s" % K.rel(md_path))
    print("csv : %s" % K.rel(csv_path))
    print("رکوردها: %d · با پرسش واقعی منطبق: %d · تأییدشده تا امروز: %d"
          % (len(objects), starred, approved))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

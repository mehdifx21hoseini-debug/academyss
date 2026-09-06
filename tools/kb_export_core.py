#!/usr/bin/env python3
"""Export the knowledge base into the CSV contract MENTORAI CORE ingests.

CORE (mentorai/, branch claude/mentorai-skills-assessment-08yqhw) reads a CSV
with eight columns and builds its own chunks, embeddings and hybrid retrieval
from it:

    source_class,category,question,answer,authority,valid_until,owner,notes

Two files are produced, because CORE consumes two:

  * mentorai_kb_vNNN.csv    — the knowledge base itself
  * mentorai_eval_vNNN.csv  — question,expected_question, CORE's retrieval test
    set. Our records carry several real student phrasings each
    (related_questions); one becomes the document's question and the rest
    become eval rows. Emitting them as extra KB rows instead would put three
    copies of the same answer in the index and crowd out other content —
    exactly the "یک موضوع، یک مدخل مرجع" rule in CORE's own KB guide.

The mapping is not mechanical. Four rules carry real weight:

1. APPROVAL GATES AUTHORITY. Our charter separates coverage from verification:
   a record existing does not mean the mentor may state it as Academy fact.
   So APPROVED records keep their mapped authority (fact/policy), everything
   still pending is capped at `guidance`, and REVIEW_REQUIRED records — the
   ones we know need fixing — are not exported at all.

2. SOURCE CLASS IS PROVENANCE, NOT USEFULNESS. CORE has exactly two classes and
   uses them to decide what may be stated as price/rule/condition. Academy
   sources become `official`, mentor conversations become `mentor`. The general
   trading / psychology layer is neither: calling it `official` would put the
   Academy's name on content the Academy never taught.
   The owner settled this (RQ-0039, option 1): ship it, but as `mentor` +
   `guidance`, never as fact or policy, with its real provenance written into
   the notes column — so the mentor can answer the question while the runtime
   still knows this is not the Academy speaking. `--academy-only` drops it.

3. THE BODY IS SPLIT. Our chunk_text is written for this project, not for a
   student: it carries ⚠️/💡 lines addressed to the mentor, cross-reference ids
   and review warnings. Those move to `notes` — CORE's column for "توضیح داخلی
   که نباید به دانشجو گفته شود" — and never reach the answer text.

4. STYLE RECORDS ARE NOT KNOWLEDGE. ACA-STY-* describe how the mentor should
   speak. They belong in CORE's prompt layer (ai/prompt.py), not in a retrieval
   index that answers student questions, so they are excluded and reported.

Usage:
    python3 tools/kb_export_core.py [--include-general] [--out DIR]
"""
import argparse
import csv
import io
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import kb_lib as K  # noqa: E402

COLUMNS = ["source_class", "category", "question", "answer",
           "authority", "valid_until", "owner", "notes"]

# ── authority ────────────────────────────────────────────────────────────
POLICY_TYPES = {"RULE", "BROKER_RULE"}
FACT_TYPES = {"OPERATIONAL_FACT", "CATALOG_ITEM", "DEFINITION", "GLOSSARY", "COMPARISON"}
# everything else (CONCEPT, PROCEDURE, TROUBLESHOOTING, EXAMPLE, COMMON_MISTAKE,
# PSYCHOLOGY_PATTERN, METATRADER_PROCEDURE, MENTOR_QA, FAQ) is guidance.

APPROVED = "APPROVED"
BLOCKED_APPROVAL = {"REJECTED", "REVIEW_REQUIRED"}

OFFICIAL_AUTHORITY = {"ACADEMY_PRIMARY", "ACADEMY_DERIVED"}
MENTOR_AUTHORITY = {"MENTOR_VERIFIED", "MENTOR_UNVERIFIED"}
GENERAL_AUTHORITY = {"GENERAL_KNOWLEDGE", "VENDOR_OFFICIAL", "BROKER_OFFICIAL"}
NEVER_EXPORT_AUTHORITY = {"EXTERNAL_METHODOLOGY"}

# ── category: id prefix wins, domain is the fallback ─────────────────────
PREFIX_CATEGORY = {
    "ACA-INT": "دوره مقدماتی",
    "ACA-EQ": "هوش هیجانی",
    "ACA-EXP": "اکسپرت SSProX",
    "ACA-SUP": "سیاست‌های آکادمی",
    "ACA-RULE": "سیاست‌های آکادمی",
    "ACA-CLR": "سیاست‌های آکادمی",
    "ACA-OPS": "اطلاعات آکادمی",
    "ACA-CAT": "اطلاعات آکادمی",
    "ACA-PSY": "روانشناسی معامله‌گری",
    "MQA": "پرسش‌های دانشجویان",
    "BRK": "بروکر",
    "MET": "متاتریدر",
    "MT4": "متاتریدر",
    "MT5": "متاتریدر",
    "GEN": "مفاهیم پایه",
    "PSY": "روانشناسی معامله‌گری",
}
# mentor_qa records carry a very fine-grained `topic` (one per record). Those
# make useless categories — CORE wants buckets like «ثبت‌نام» or «تحلیل
# تکنیکال», not seventy categories holding one row each — so the coarser
# `intent` is used and the precise topic is kept in notes.
INTENT_CATEGORY = {
    "psychology": "روانشناسی معامله‌گری",
    "method": "روش و استراتژی",
    "concept": "روش و استراتژی",
    "strategy_change": "روش و استراتژی",
    "stop_placement": "مدیریت ریسک",
    "risk_reward": "مدیریت ریسک",
    "trade_pacing": "انضباط معاملاتی",
    "plan_discipline": "انضباط معاملاتی",
    "plan_change": "انضباط معاملاتی",
    "journaling": "انضباط معاملاتی",
    "trade_review": "بررسی عملکرد",
    "account_review": "بررسی عملکرد",
    "backtest": "بک‌تست و فوروارد تست",
    "academy_process": "فرآیندهای آکادمی",
    "platform": "متاتریدر",
    "broker": "بروکر",
    "account_setup": "بروکر",
    "financial_advice": "مرزهای پاسخ‌گویی",
}
DOMAIN_CATEGORY = {
    "academy": "آکادمی", "mentor_qa": "پرسش‌های دانشجویان",
    "metatrader": "متاتریدر", "brokers": "بروکر",
    "general_trading": "مفاهیم پایه", "psychology": "روانشناسی معامله‌گری",
}

# ── body cleaning ────────────────────────────────────────────────────────
# ⚠️ and 💡 mark text written to the mentor, not the student — at the start of a
# line or partway through one.
# 📘 marks a pointer to our own records — a cross-reference for the mentor, not
# an answer for the student.
MENTOR_MARK = re.compile(r"(⚠️|💡|📘)")
# Record ids in any form: inside parentheses with the connective text that
# introduces them, backticked, or bare in a sentence.
# The trailing group catches range forms written as ACA-EXP-0001..0043.
RECORD_ID = r"[A-Z0-9]{2,6}-[A-Z]{2,5}-[0-9]{4,5}(?:\.\.[0-9]{4,5})?"
REF_PAREN = re.compile(r"\s*[\(（][^)）]*`?" + RECORD_ID + r"`?[^)）]*[\)）]")
REF_BARE = re.compile(r"\s*`?" + RECORD_ID + r"`?")
BOLD = re.compile(r"\*\*(.+?)\*\*")
TICK = re.compile(r"`([^`]+)`")


def split_body(text):
    """Return (student_text, internal_lines). Never guesses: it only moves what
    the record itself marked as mentor-facing — from the ⚠️/💡 marker to the end
    of that line, so a marker halfway through a line is caught too."""
    student, internal = [], []
    for line in (text or "").split("\n"):
        match = MENTOR_MARK.search(line)
        if match:
            head = line[: match.start()].rstrip()
            internal.append(line[match.start():].strip())
            if head:
                student.append(head)
        else:
            student.append(line)
    return "\n".join(student), [ln for ln in internal if ln]


def flatten(text):
    """Flatten markdown. CORE sends answers without a parse_mode, so ** and `
    would reach the student literally — the same mistake the support bot's seed
    file had to be cleaned of."""
    text = BOLD.sub(r"\1", text or "")
    text = TICK.sub(r"\1", text)
    text = text.replace("`", "")  # an unpaired tick left by a removed reference
    text = re.sub(r"\s+([.،؛:؟!])", r"\1", text)
    text = re.sub(r"[ \t]+\n", "\n", text)
    return re.sub(r"\n{3,}", "\n\n", text).strip()


def clean(text):
    """flatten(), plus removal of our internal record references. Used for the
    answer only — notes keep their ids, which is what makes a row traceable."""
    text = REF_PAREN.sub("", text or "")
    text = REF_BARE.sub("", text)
    # Removing an id can leave a dangling connective or doubled punctuation.
    text = re.sub(r"\s+(هم‌راستا با|طبق|مطابق|بر اساس|رجوع به)\s*([.،؛)]|$)", r"\2", text)
    text = re.sub(r"\(\s*\)", "", text)
    return flatten(text)


def is_qa(obj):
    """mentor_qa records use their own schema: no object_type, no title, and the
    question already stored the way the student actually asked it."""
    return obj.get("domain") == "mentor_qa"


def category_of(obj):
    if is_qa(obj):
        return INTENT_CATEGORY.get(obj.get("intent"), PREFIX_CATEGORY["MQA"])
    oid = obj.get("id", "")
    for prefix in sorted(PREFIX_CATEGORY, key=len, reverse=True):
        if oid.startswith(prefix + "-") or oid.startswith(prefix):
            return PREFIX_CATEGORY[prefix]
    return DOMAIN_CATEGORY.get(obj.get("domain"), "عمومی")


def questions_of(obj):
    """Real student phrasings first; the title only if there is nothing else."""
    seen, out = set(), []
    if is_qa(obj):
        candidates = ([obj.get("question_normalized")]
                      + list(obj.get("question_variants") or [])
                      + [obj.get("question_raw")])
    else:
        candidates = list(obj.get("related_questions") or [])
    for q in candidates:
        q = (q or "").strip()
        if q and q not in seen:
            seen.add(q)
            out.append(q)
    if not out:
        title = (obj.get("title") or "").strip()
        if title:
            out.append(title if title.endswith("؟") else title + "؟")
    return out


def answer_of(obj):
    """MENTOR_QA records keep their own shape; everything else uses chunk_text."""
    if is_qa(obj):
        return obj.get("answer_structured") or obj.get("answer_raw") or ""
    body = obj.get("chunk_text") or obj.get("definition") or obj.get("summary") or ""
    extra = []
    for step in (obj.get("steps") or []):
        extra.append("• " + str(step))
    if extra and "•" not in body and "۱." not in body:
        body = body + "\n\n" + "\n".join(extra)
    return body


def authority_of(obj):
    # A mentor's answer is never a price, rule or condition reference — CORE's
    # own guide is explicit about this — so it is always guidance.
    if is_qa(obj):
        return "guidance"
    otype = obj.get("object_type")
    if otype in POLICY_TYPES:
        mapped = "policy"
    elif otype in FACT_TYPES:
        mapped = "fact"
    else:
        mapped = "guidance"
    # Rule 1: unverified content may not be stated as Academy fact or policy.
    if obj.get("approval_status") != APPROVED:
        return "guidance"
    return mapped


def notes_of(obj, internal_lines, source_note=None):
    """Traceability first, then anything the student must not be told."""
    parts = ["منبع: " + obj.get("id", "?")]
    if is_qa(obj) and obj.get("topic"):
        parts.append("موضوع: " + str(obj["topic"]))
    if source_note:
        parts.append(source_note)
    if obj.get("approval_status") != APPROVED:
        parts.append("تأیید انسانی نشده؛ به‌عنوان راهنمایی آموزشی وارد شد، نه واقعیت رسمی.")
    validity = obj.get("validity") or {}
    if validity.get("time_bound"):
        note = validity.get("note") or validity.get("as_of") or ""
        parts.append("زمان‌مند" + (": " + str(note) if note else ""))
    for w in (obj.get("warnings") or []):
        parts.append(str(w))
    for c in (obj.get("conditions") or []):
        parts.append(str(c))
    for line in internal_lines:
        parts.append(line)
    if obj.get("verification_note"):
        parts.append(str(obj["verification_note"]))
    if obj.get("conflicts"):
        parts.append("تعارض: " + "، ".join(obj["conflicts"]))
    return flatten(" | ".join(p for p in parts if p))


def valid_until_of(obj):
    """CORE wants an ISO date. Our validity blocks are time-bound but dateless,
    so the column stays empty and the warning lives in notes — an invented date
    would be worse than none."""
    return ""


def owner_of(obj):
    src = obj.get("source") or {}
    return (src.get("author") or src.get("mentor") or "آکادمی سبحان صمدی").strip()


def external_key(source_class, category, question):
    """CORE's own key: sha256 over the normalised (class|category|question).
    Reproduced here — not to store it, but because two of our rows landing on
    the same key would silently overwrite each other on import, and a knowledge
    base that loses rows without saying so is the worst outcome."""
    t = (source_class + "|" + category + "|" + question)
    t = re.sub(r"[يى]", "ی", t)
    t = re.sub(r"[ك]", "ک", t)
    t = re.sub(r"[\u200b-\u200f\ufeff]", "", t)
    return re.sub(r"\s+", " ", t).strip().lower()


def strength_key(obj):
    """Sort order for claiming a question: approved first, then Academy-sourced,
    then higher confidence, then id for a stable run. Processing in this order
    means the first record to claim a phrasing is always the strongest one, so
    a weaker record simply moves to its next phrasing instead of being pushed
    out of the export by a later row."""
    return (
        0 if obj.get("approval_status") == APPROVED else 1,
        0 if obj.get("authority_level") in OFFICIAL_AUTHORITY else 1,
        -float(obj.get("confidence") or 0),
        obj.get("id", ""),
    )


def collect():
    objects = []
    for path in K.iter_collection_files():
        coll = K.load_json(path)
        for obj in coll.get("objects", []):
            objects.append(obj)
    return objects


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--academy-only", action="store_true",
                    help="فقط منابع آکادمی؛ لایه‌ی دانش عمومی خروجی نمی‌گیرد")
    ap.add_argument("--out", default=os.path.join(K.EXPORT_DIR, "core"))
    args = ap.parse_args()

    rows, eval_rows = [], []
    claimed = {}
    collisions, moved = [], []
    skipped = {"style": 0, "meta": 0, "quarantine": 0, "review_required": 0,
               "general": 0, "governance": 0, "no_answer": 0,
               "no_question": 0, "duplicate_question": 0}
    stats = {"official": 0, "mentor": 0,
             "fact": 0, "policy": 0, "guidance": 0}

    for obj in sorted(collect(), key=strength_key):
        oid = obj.get("id", "")
        otype = obj.get("object_type")
        auth_level = obj.get("authority_level")

        if otype in ("CONFLICT_RECORD", "REVIEW_ITEM") or obj.get("domain") == "meta":
            skipped["meta"] += 1
            continue
        if auth_level in NEVER_EXPORT_AUTHORITY:
            skipped["quarantine"] += 1
            continue
        if oid.startswith("ACA-STY-"):
            skipped["style"] += 1          # rule 4: prompt layer, not knowledge
            continue
        if obj.get("approval_status") in BLOCKED_APPROVAL:
            skipped["review_required"] += 1
            continue

        source_note = None
        if auth_level in OFFICIAL_AUTHORITY:
            source_class = "official"
        elif auth_level in MENTOR_AUTHORITY:
            source_class = "mentor"
        elif auth_level in GENERAL_AUTHORITY:
            if args.academy_only:
                skipped["general"] += 1
                continue
            source_class = "mentor"
            source_note = ("دانش عمومی معامله‌گری — منبع آکادمی نیست و تأیید انسانی نشده. "
                           "طبق تصمیم مالک (RQ-0039) به‌عنوان راهنمایی آموزشی وارد شد؛ "
                           "مربی آن را به‌عنوان قاعده یا حرف رسمی آکادمی بیان نمی‌کند و "
                           "می‌گوید روی نسخه و بروکر خودت یک بار بررسی کن.")
        else:
            # Governance objects (conflict records, review items) have no
            # authority level because they are not answers to anything.
            skipped["governance"] += 1
            continue

        body, internal = split_body(answer_of(obj))
        answer = clean(body)
        if len(answer) < 20:
            skipped["no_answer"] += 1
            continue

        qs = questions_of(obj)
        if not qs:
            skipped["no_question"] += 1
            continue

        authority = authority_of(obj)
        category = category_of(obj)

        # Take the first phrasing no stronger record has already claimed.
        # Records are processed strongest-first, so whoever claims a question
        # is the one that should own it. A record whose every phrasing is
        # already taken is dropped and named in the report — never silently.
        primary = None
        for candidate in qs:
            key = external_key(source_class, category, candidate)
            if key not in claimed:
                primary = candidate
                claimed[key] = oid
                break
            moved.append((oid, candidate, claimed[key]))
        if primary is None:
            collisions.append((oid, qs[0]))
            skipped["duplicate_question"] += 1
            continue
        qs = [primary] + [q for q in qs if q != primary]

        rows.append({
            "source_class": source_class,
            "category": category,
            "question": primary,
            "answer": answer,
            "authority": authority,
            "valid_until": valid_until_of(obj),
            "owner": owner_of(obj),
            "notes": notes_of(obj, internal, source_note),
        })
        stats[source_class] += 1
        stats[authority] += 1

        # Alternate phrasings become the retrieval test set, not duplicate rows.
        for alt in qs[1:]:
            eval_rows.append({"question": alt, "expected_question": primary})

    if not os.path.isdir(args.out):
        os.makedirs(args.out)

    def render(fieldnames, records):
        buf = io.StringIO()
        writer = csv.DictWriter(buf, fieldnames=fieldnames, lineterminator="\n")
        writer.writeheader()
        for rec in records:
            writer.writerow(rec)
        return buf.getvalue()

    def emit(prefix, fieldnames, records):
        """Write <prefix>_vNNN.csv only when the content actually changed, so a
        repeated pipeline run does not pile up identical versions. Earlier
        versions are never overwritten — the same rule as every other export."""
        # utf-8-sig so the file opens correctly in Excel, which is how the
        # Academy's own guide tells mentors to edit this format.
        text = render(fieldnames, records)
        latest = os.path.join(args.out, prefix + "_latest.csv")
        if os.path.exists(latest):
            with io.open(latest, encoding="utf-8-sig") as fh:
                if fh.read() == text:
                    return latest, False
        version = K.next_version(args.out, prefix, ".csv")
        path = os.path.join(args.out, "%s_%s.csv" % (prefix, version))
        for target in (path, latest):
            with io.open(target, "w", encoding="utf-8-sig", newline="") as fh:
                fh.write(text)
        return path, True

    kb_path, kb_changed = emit("mentorai_kb", COLUMNS, rows)
    eval_path, eval_changed = emit("mentorai_eval", ["question", "expected_question"], eval_rows)

    print("kb   : %s  rows=%d%s"
          % (K.rel(kb_path), len(rows), "" if kb_changed else "  (unchanged)"))
    print("eval : %s  rows=%d%s"
          % (K.rel(eval_path), len(eval_rows), "" if eval_changed else "  (unchanged)"))
    print("class: official=%d mentor=%d" % (stats["official"], stats["mentor"]))
    print("auth : fact=%d policy=%d guidance=%d"
          % (stats["fact"], stats["policy"], stats["guidance"]))
    print("skip : " + " ".join("%s=%d" % kv for kv in sorted(skipped.items()) if kv[1]))
    if moved:
        print("moved: %d phrasing(s) already owned by a stronger record" % len(moved))
        for loser, question, winner in moved[:6]:
            print("       %s yielded «%s» to %s" % (loser, question[:40], winner))
    if collisions:
        print("clash: %d record(s) dropped — every phrasing already claimed:" % len(collisions))
        for oid, question in collisions:
            print("       %s  «%s»" % (oid, question[:52]))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

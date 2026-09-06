#!/usr/bin/env python3
"""Check the CORE export with CORE's own parser instead of a paraphrase of it.

tools/kb_export_core.py writes the CSV; this verifies it. The difference that
matters: this loads the real `_parse_row`, `external_key` and `chunk_text` out
of mentorai/ and runs them over our rows. A hand-written copy of those rules
drifts the moment CORE changes, and a check that drifts is worse than none —
it reports success for a file the importer will actually reject.

CORE's ingest module imports SQLAlchemy, which the knowledge-base toolchain
deliberately does not depend on. So the pure functions are lifted out by AST
and executed against CORE's real Persian normalizer, with nothing stubbed that
affects a verdict.

    python3 tools/kb_check_core_export.py [--file exports/core/mentorai_kb_latest.csv]

Exit code 1 if any row would be rejected, silently overwritten, or dropped.
"""
import argparse
import ast
import collections
import csv
import io
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import kb_lib as K  # noqa: E402

CORE = os.path.join(K.ROOT, "mentorai", "src")
INGEST = os.path.join(CORE, "mentorai", "knowledge", "ingest.py")
MODELS = os.path.join(CORE, "mentorai", "db", "models.py")
CHUNKING = os.path.join(CORE, "mentorai", "knowledge", "chunking.py")


def read(path):
    with io.open(path, encoding="utf-8") as fh:
        return fh.read()


def rebuild_enum(source, class_name):
    """Rebuild one of CORE's enums from its source, without importing the module
    it lives in (models.py pulls in SQLAlchemy)."""
    import enum as enum_mod

    tree = ast.parse(source)
    for node in ast.walk(tree):
        if isinstance(node, ast.ClassDef) and node.name == class_name:
            members = {}
            for stmt in node.body:
                if (isinstance(stmt, ast.Assign) and isinstance(stmt.value, ast.Constant)
                        and isinstance(stmt.targets[0], ast.Name)):
                    members[stmt.targets[0].id] = stmt.value.value
            if not members:
                raise SystemExit("enum %s in CORE has no members" % class_name)
            return enum_mod.Enum(class_name, members)
    raise SystemExit("enum %s not found in CORE" % class_name)


def lift(source, names, namespace):
    """Execute only the named top-level functions from a module's source."""
    tree = ast.parse(source)
    wanted = [n for n in tree.body
              if isinstance(n, (ast.FunctionDef, ast.Assign)) and _name_of(n) in names]
    if len(wanted) != len(names):
        missing = set(names) - {_name_of(n) for n in wanted}
        raise SystemExit("CORE changed shape — not found: %s" % ", ".join(sorted(missing)))
    module = ast.Module(body=wanted, type_ignores=[])
    exec(compile(module, "<core>", "exec"), namespace)  # noqa: S102
    return namespace


def _name_of(node):
    if isinstance(node, ast.FunctionDef):
        return node.name
    if isinstance(node, ast.Assign) and node.targets and isinstance(node.targets[0], ast.Name):
        return node.targets[0].id
    return None


def build_core_namespace():
    import datetime
    import hashlib
    import re

    sys.path.insert(0, CORE)
    from mentorai.text.persian import normalize_for_search, normalize_for_storage

    models = read(MODELS)
    SourceClass = rebuild_enum(models, "SourceClass")
    Authority = rebuild_enum(models, "Authority")

    class InvalidRow(ValueError):
        pass

    ns = {
        "hashlib": hashlib, "re": re, "date": datetime.date,
        "normalize_for_search": normalize_for_search,
        "normalize_for_storage": normalize_for_storage,
        "SourceClass": SourceClass, "Authority": Authority,
        "InvalidRow": InvalidRow,
    }
    lift(read(INGEST), {"external_key", "_parse_row"}, ns)
    lift(read(CHUNKING), {"chunk_text", "_split_long_paragraph",
                          "DEFAULT_TARGET", "DEFAULT_OVERLAP", "MIN_CHUNK",
                          "_SENTENCE_END", "_PARAGRAPH"}, ns)
    ns["REQUIRED_COLUMNS"] = frozenset(
        {"source_class", "category", "question", "answer",
         "authority", "valid_until", "owner", "notes"})
    return ns


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--file", default=os.path.join(K.EXPORT_DIR, "core",
                                                   "mentorai_kb_latest.csv"))
    args = ap.parse_args()

    if not os.path.isdir(CORE):
        print("mentorai/ در این شاخه نیست — این بررسی به کد CORE نیاز دارد.")
        return 0

    ns = build_core_namespace()
    parse_row, external_key, chunk_text = ns["_parse_row"], ns["external_key"], ns["chunk_text"]
    InvalidRow = ns["InvalidRow"]

    with io.open(args.file, encoding="utf-8-sig", newline="") as fh:
        reader = csv.DictReader(fh)
        missing = ns["REQUIRED_COLUMNS"] - set(reader.fieldnames or [])
        if missing:
            print("ستون‌های جاافتاده: %s" % ", ".join(sorted(missing)))
            return 1
        rows = list(reader)

    rejected, keys, chunkless, chunk_total = [], collections.defaultdict(list), [], 0
    for line, row in enumerate(rows, start=2):
        try:
            parsed = parse_row(row)
        except InvalidRow as err:
            rejected.append((line, str(err)))
            continue
        keys[parsed["external_key"]].append(line)
        pieces = chunk_text("%s\n\n%s" % (parsed["title"], parsed["body"]))
        chunk_total += len(pieces)
        if not pieces:
            chunkless.append((line, row["question"][:50]))

    clashes = {k: v for k, v in keys.items() if len(v) > 1}

    print("file      : %s" % K.rel(args.file))
    print("rows      : %d" % len(rows))
    print("rejected  : %d" % len(rejected))
    for line, why in rejected[:10]:
        print("            خط %d — %s" % (line, why))
    print("key clash : %d" % len(clashes))
    for k, lines in list(clashes.items())[:10]:
        print("            خط‌های %s با یک کلید — دومی اولی را بازنویسی می‌کند"
              % ", ".join(str(x) for x in lines))
    print("chunks    : %d (میانگین %.1f در هر مدخل)"
          % (chunk_total, chunk_total / float(len(rows) or 1)))
    print("no chunks : %d" % len(chunkless))
    for line, q in chunkless[:10]:
        print("            خط %d — «%s»" % (line, q))

    ok = not rejected and not clashes and not chunkless
    print("verdict   : %s" % ("قابل ورود ✅" if ok else "نیازمند اصلاح ❌"))
    return 0 if ok else 1


if __name__ == "__main__":
    raise SystemExit(main())

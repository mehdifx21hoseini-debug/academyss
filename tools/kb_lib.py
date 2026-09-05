"""Shared helpers for the MENTORAI Knowledge Base toolchain.

Dependency-free on purpose: the KB must be reproducible in an offline
container with nothing but a stock Python 3.
"""
import json
import os
import re
from datetime import datetime, timezone

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
KB_DIR = os.path.join(ROOT, "knowledge_base")
SCHEMA_DIR = os.path.join(ROOT, "schemas")
EXPORT_DIR = os.path.join(ROOT, "exports")
MANIFEST_DIR = os.path.join(ROOT, "manifests")
REPORT_DIR = os.path.join(ROOT, "reports")

# knowledge_base sub-trees that hold collection files of a given record kind
CONFLICT_DIR = os.path.join(KB_DIR, "conflicts")
REVIEW_DIR = os.path.join(KB_DIR, "review_queue")
MENTOR_QA_DIRS = (
    os.path.join(KB_DIR, "mentor_qa", "structured"),
    os.path.join(KB_DIR, "mentor_qa", "approved"),
)


def now_iso():
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def load_json(path):
    with open(path, "r", encoding="utf-8") as fh:
        return json.load(fh)


def dump_json(path, data):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8") as fh:
        json.dump(data, fh, ensure_ascii=False, indent=2)
        fh.write("\n")


def write_text(path, text):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8") as fh:
        fh.write(text)


TIMESTAMP_FIELDS = ("generated_at", "created_at", "updated_at", "extracted_at")


def _fingerprint(value):
    """Content signature ignoring timestamps, so a rebuild that changes nothing
    substantive does not churn versions or rewrite files."""
    if isinstance(value, dict):
        return {k: _fingerprint(v) for k, v in sorted(value.items())
                if k not in TIMESTAMP_FIELDS}
    if isinstance(value, list):
        return [_fingerprint(v) for v in value]
    return value


def write_collection(path, collection):
    """Write a collection file only when its substantive content changed."""
    if os.path.exists(path):
        try:
            existing = load_json(path)
        except Exception:  # noqa: BLE001
            existing = None
        if existing is not None and _fingerprint(existing) == _fingerprint(collection):
            return False
    dump_json(path, collection)
    return True


def enums():
    return load_json(os.path.join(SCHEMA_DIR, "enums.json"))


def iter_collection_files():
    """Every *.json under knowledge_base/ is a collection file."""
    for dirpath, _dirnames, filenames in os.walk(KB_DIR):
        for name in sorted(filenames):
            if name.endswith(".json"):
                yield os.path.join(dirpath, name)


def rel(path):
    return os.path.relpath(path, ROOT)


def record_kind(path):
    """Which record schema applies to the objects of this collection file."""
    p = os.path.abspath(path)
    if p.startswith(os.path.abspath(CONFLICT_DIR)):
        return "conflict_record"
    if p.startswith(os.path.abspath(REVIEW_DIR)):
        return "review_item"
    for d in MENTOR_QA_DIRS:
        if p.startswith(os.path.abspath(d)):
            return "mentor_qa"
    return "knowledge_object"


SCHEMA_FILES = {
    "knowledge_object": "knowledge_object.schema.json",
    "mentor_qa": "mentor_qa.schema.json",
    "conflict_record": "conflict_record.schema.json",
    "review_item": "review_item.schema.json",
    "collection": "collection.schema.json",
}


def load_schema(kind):
    return load_json(os.path.join(SCHEMA_DIR, SCHEMA_FILES[kind]))


def write_versioned_snapshot(directory, prefix, payload, latest_path=None, extra_copy_dir=None):
    """Write <prefix>_vNNN.json only when content (ignoring timestamps) changed.

    Returns (version, changed). Previous versions are never overwritten.
    """
    latest = latest_path or os.path.join(directory, prefix + "_latest.json")
    if os.path.exists(latest):
        try:
            prev = load_json(latest)
        except Exception:  # noqa: BLE001
            prev = None
        def _cmp(d):
            return _fingerprint({k: v for k, v in d.items() if k != "version"})

        if prev is not None and _cmp(prev) == _cmp(payload):
            version = prev.get("version", "v001")
            return version, False
    version = next_version(directory, prefix, ".json")
    payload = dict(payload, version=version)
    dump_json(os.path.join(directory, "%s_%s.json" % (prefix, version)), payload)
    dump_json(latest, payload)
    if extra_copy_dir:
        dump_json(os.path.join(extra_copy_dir, "%s_%s.json" % (prefix, version)), payload)
    return version, True


def next_version(directory, prefix, suffix):
    """Return the next vNNN for files named <prefix>_vNNN<suffix> in directory."""
    highest = 0
    if os.path.isdir(directory):
        pat = re.compile(re.escape(prefix) + r"_v(\d{3})" + re.escape(suffix) + r"$")
        for name in os.listdir(directory):
            m = pat.match(name)
            if m:
                highest = max(highest, int(m.group(1)))
    return "v%03d" % (highest + 1)

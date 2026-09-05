#!/usr/bin/env python3
"""Validate every knowledge collection under knowledge_base/.

Checks, in order:
  1. collection envelope against schemas/collection.schema.json
  2. each record against its record schema (subset of JSON Schema)
  3. type-specific required fields (x-type-requirements)
  4. KB invariants (provenance, authority, methodology quarantine, ...)
  5. global integrity: duplicate ids, dangling cross-references

Writes reports/validation_report_<version>.json and prints a short summary.
Exit code 1 when any ERROR is found (warnings never fail the run).
"""
import re
import sys

sys.path.insert(0, __file__.rsplit("/", 1)[0])
import kb_lib as K  # noqa: E402

ENUMS = K.enums()

ACADEMY_SOURCE_TYPES = {
    "ACADEMY_COURSE_TRANSCRIPT",
    "ACADEMY_DOCUMENT",
    "ACADEMY_WEBSITE",
    "ACADEMY_APP_DATA",
}


class Findings:
    def __init__(self):
        self.items = []

    def add(self, level, where, message):
        self.items.append({"level": level, "where": where, "message": message})

    def error(self, where, message):
        self.add("ERROR", where, message)

    def warn(self, where, message):
        self.add("WARNING", where, message)

    def count(self, level):
        return sum(1 for i in self.items if i["level"] == level)


def check_value(value, spec, where, f):
    """Minimal JSON-Schema subset: type/enum/enum_ref/pattern/minLength/min/max/items."""
    t = spec.get("type")
    if t == "string" and not isinstance(value, str):
        f.error(where, "expected string, got %s" % type(value).__name__)
        return
    if t == "number" and not isinstance(value, (int, float)) or (t == "number" and isinstance(value, bool)):
        f.error(where, "expected number")
        return
    if t == "boolean" and not isinstance(value, bool):
        f.error(where, "expected boolean")
        return
    if t == "array" and not isinstance(value, list):
        f.error(where, "expected array")
        return
    if t == "object" and not isinstance(value, dict):
        f.error(where, "expected object")
        return

    if "enum_ref" in spec:
        allowed = ENUMS[spec["enum_ref"]]
        if value not in allowed:
            f.error(where, "value %r not in enum %s" % (value, spec["enum_ref"]))
    if "enum" in spec and value not in spec["enum"]:
        f.error(where, "value %r not in %s" % (value, spec["enum"]))
    if "pattern" in spec and isinstance(value, str) and not re.match(spec["pattern"], value):
        f.error(where, "value %r does not match %s" % (value, spec["pattern"]))
    if "minLength" in spec and isinstance(value, str) and len(value) < spec["minLength"]:
        f.error(where, "shorter than minLength %d" % spec["minLength"])
    if "minItems" in spec and isinstance(value, list) and len(value) < spec["minItems"]:
        f.error(where, "fewer than minItems %d" % spec["minItems"])
    if "minimum" in spec and isinstance(value, (int, float)) and value < spec["minimum"]:
        f.error(where, "below minimum %s" % spec["minimum"])
    if "maximum" in spec and isinstance(value, (int, float)) and value > spec["maximum"]:
        f.error(where, "above maximum %s" % spec["maximum"])
    if t == "array" and isinstance(value, list) and "items" in spec:
        for i, item in enumerate(value):
            check_value(item, spec["items"], "%s[%d]" % (where, i), f)
    if t == "object" and isinstance(value, dict) and "properties" in spec:
        check_object(value, spec, where, f)


def check_object(obj, schema, where, f):
    props = schema.get("properties", {})
    for key in schema.get("required", []):
        if key not in obj:
            f.error(where, "missing required field '%s'" % key)
    if schema.get("additionalProperties") is False:
        for key in obj:
            if key not in props:
                f.error(where, "unknown field '%s'" % key)
    for key, value in obj.items():
        if key in props:
            check_value(value, props[key], "%s.%s" % (where, key), f)


def check_type_requirements(obj, schema, where, f):
    reqs = schema.get("x-type-requirements", {}).get(obj.get("object_type"), [])
    for key in reqs:
        value = obj.get(key)
        if value in (None, "", [], {}):
            f.error(where, "object_type %s requires non-empty '%s'" % (obj["object_type"], key))


def check_invariants(obj, kind, where, f):
    src = obj.get("source", {}) or {}
    stype = src.get("source_type")
    authority = obj.get("authority_level")
    approval = obj.get("approval_status")

    if authority == "ACADEMY_PRIMARY" and stype not in ACADEMY_SOURCE_TYPES:
        f.error(where, "ACADEMY_PRIMARY requires an Academy source_type (got %r)" % stype)
    if stype == "MODEL_DRAFT":
        if obj.get("verification_required") is not True:
            f.error(where, "MODEL_DRAFT requires verification_required=true")
        if approval not in ("PENDING_VERIFICATION", "REVIEW_REQUIRED"):
            f.error(where, "MODEL_DRAFT must not be %r" % approval)
    if approval == "APPROVED" and obj.get("verification_required") is True:
        f.error(where, "APPROVED conflicts with verification_required=true")
    if obj.get("methodology_scope") == "EXTERNAL_METHODOLOGY_QUARANTINE" and authority == "ACADEMY_PRIMARY":
        f.error(where, "quarantined external methodology cannot be ACADEMY_PRIMARY")

    if kind == "knowledge_object":
        if obj.get("domain") == "metatrader" and not obj.get("platform_scope"):
            f.error(where, "metatrader objects require platform_scope")
        if obj.get("domain") == "brokers":
            if not obj.get("broker"):
                f.error(where, "broker objects require 'broker'")
            if not obj.get("validity"):
                f.error(where, "broker objects require 'validity'")
        if obj.get("approval_status") in ("REVIEW_REQUIRED", "PENDING_VERIFICATION") and not obj.get("review_reason") \
                and not obj.get("verification_note"):
            f.warn(where, "review/verification state without a stated reason")
    if kind == "mentor_qa":
        if authority == "ACADEMY_PRIMARY":
            f.error(where, "a mentor answer can never be ACADEMY_PRIMARY")
        if obj.get("pii_removed") is not True:
            f.error(where, "structured mentor Q&A requires pii_removed=true")


def main():
    f = Findings()
    collection_schema = K.load_schema("collection")
    seen_ids = {}
    all_ids = set()
    referenced = []
    stats = {"files": 0, "objects": 0, "by_kind": {}, "by_domain": {}, "by_approval": {}}

    files = list(K.iter_collection_files())
    for path in files:
        where_file = K.rel(path)
        stats["files"] += 1
        try:
            data = K.load_json(path)
        except Exception as exc:  # noqa: BLE001
            f.error(where_file, "invalid JSON: %s" % exc)
            continue

        check_object(data, collection_schema, where_file, f)
        kind = K.record_kind(path)
        stats["by_kind"][kind] = stats["by_kind"].get(kind, 0) + 1
        schema = K.load_schema(kind)

        for idx, obj in enumerate(data.get("objects", [])):
            oid = obj.get("id", "<no-id>")
            where = "%s :: %s" % (where_file, oid if oid != "<no-id>" else "#%d" % idx)
            stats["objects"] += 1
            check_object(obj, schema, where, f)
            if kind == "knowledge_object":
                check_type_requirements(obj, schema, where, f)
            check_invariants(obj, kind, where, f)

            if oid in seen_ids:
                f.error(where, "duplicate id, already defined in %s" % seen_ids[oid])
            else:
                seen_ids[oid] = where_file
                all_ids.add(oid)

            dom = obj.get("domain") or data.get("domain")
            stats["by_domain"][dom] = stats["by_domain"].get(dom, 0) + 1
            appr = obj.get("approval_status")
            if appr:
                stats["by_approval"][appr] = stats["by_approval"].get(appr, 0) + 1

            for key in ("related_concepts", "conflicts", "rule_used", "supersedes", "superseded_by", "object_ids"):
                for ref in obj.get(key, []) or []:
                    if re.match(r"^(MQA-\d{5}|CONF-\d{4}|RQ-\d{4}|[A-Z0-9]{2,6}-[A-Z]{2,5}-\d{4})$", str(ref)):
                        referenced.append((where, key, ref))

    for where, key, ref in referenced:
        if ref not in all_ids:
            f.warn(where, "%s references unknown id %s" % (key, ref))

    report = {
        "report_type": "validation",
        "version": "v000",
        "generated_at": K.now_iso(),
        "stats": stats,
        "errors": f.count("ERROR"),
        "warnings": f.count("WARNING"),
        "findings": f.items,
    }
    version, _changed = K.write_versioned_snapshot(K.REPORT_DIR, "validation_report", report)

    print("files=%d objects=%d errors=%d warnings=%d" %
          (stats["files"], stats["objects"], report["errors"], report["warnings"]))
    for item in f.items[:40]:
        print("  [%s] %s -> %s" % (item["level"], item["where"], item["message"]))
    if len(f.items) > 40:
        print("  ... %d more (see reports/validation_report_%s.json)" % (len(f.items) - 40, version))
    return 1 if report["errors"] else 0


if __name__ == "__main__":
    raise SystemExit(main())

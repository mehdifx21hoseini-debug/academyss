#!/usr/bin/env python3
"""Regenerate the A13 baseline: names called in the tree but declared in it nowhere.

Run this ONLY when the tree compiles, and only after deliberately adding a
new MetaTrader built-in. Everything it writes is, by construction, a name
the compiler already accepts - so A13 can afterwards report any name
outside the list as something newly introduced and not yet defined.
"""
import re, os, sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "tools"))
import ssr_audit as A

DECL = re.compile(r'^\s*(?:virtual\s+|static\s+|const\s+)*'
                  r'([A-Za-z_][\w:]*)\s*[\*&]?\s*([A-Za-z_]\w*)\s*\(', re.M)
CALL = re.compile(r'(?<![\w.])([A-Za-z_]\w*)\s*\(')
KW = {'if', 'while', 'for', 'switch', 'return', 'sizeof', 'else', 'do',
      'case', 'new', 'delete', 'catch'}

def scan():
    declared, called = set(), set()
    for body in A.CLEAN.values():
        for m in DECL.finditer(body):
            if m.group(1) not in A.NOT_A_RETURN_TYPE:
                declared.add(m.group(2))
    for body in A.CLEAN.values():
        for m in CALL.finditer(body):
            if m.group(1) not in KW:
                called.add(m.group(1))
    return sorted(called - declared)

if __name__ == "__main__":
    names = scan()
    path = os.path.join(ROOT, "tools", "ssr_known_calls.txt")
    with open(path, "w") as fh:
        fh.write(
            "# Names called across the tree that are declared nowhere in it.\n"
            "# Every one is a MetaTrader built-in, a cast, or a macro: the\n"
            "# tree compiles, so none can be a missing definition. A13 flags\n"
            "# any name outside this list, which by construction can only be\n"
            "# something newly introduced and not yet defined.\n"
            "#\n"
            "# Regenerate with tools/ssr_known_calls.py, and only when the\n"
            "# tree compiles.\n")
        fh.write("\n".join(names) + "\n")
    print("wrote %d names to %s" % (len(names), path))

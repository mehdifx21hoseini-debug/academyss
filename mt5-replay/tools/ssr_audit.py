#!/usr/bin/env python3
"""
SSR static audits — the mechanical checks that caught real MetaEditor errors.

Every audit here exists because the compiler found something that eleven
phases of reading had missed.  Each one is written to be *verified*: break
the code on purpose, the audit must name it; put the code back, the audit
must go silent.  An audit that has never been seen to fire is not evidence.

Usage:  python3 tools/ssr_audit.py [MQL5_root]
Exit code 0 when every audit is silent, 1 otherwise.
"""
import os, re, sys, collections

ROOT = sys.argv[1] if len(sys.argv) > 1 else os.path.join(os.path.dirname(__file__), "..", "MQL5")
ROOT = os.path.abspath(ROOT)

def sources():
    for base, _dirs, files in os.walk(ROOT):
        for f in sorted(files):
            if f.endswith((".mq5", ".mqh")):
                yield os.path.join(base, f)

def rel(p):
    return os.path.relpath(p, ROOT)

def strip_comments(text):
    """Blank out comments and string literals, keeping line count intact."""
    out, i, n = [], 0, len(text)
    while i < n:
        c = text[i]
        if c == '/' and i + 1 < n and text[i+1] == '/':
            j = text.find('\n', i)
            j = n if j < 0 else j
            out.append(' ' * (j - i)); i = j
        elif c == '/' and i + 1 < n and text[i+1] == '*':
            j = text.find('*/', i + 2)
            j = n if j < 0 else j + 2
            out.append(''.join(ch if ch == '\n' else ' ' for ch in text[i:j])); i = j
        elif c in '"\'':
            j, q = i + 1, c
            while j < n and text[j] != q:
                j += 2 if text[j] == '\\' else 1
            j = min(j + 1, n)
            out.append(''.join(ch if ch == '\n' else ' ' for ch in text[i:j])); i = j
        else:
            out.append(c); i += 1
    return ''.join(out)

FILES = {p: open(p, encoding="utf-8", errors="replace").read() for p in sources()}
CLEAN = {p: strip_comments(t) for p, t in FILES.items()}

findings = []
def report(audit, path, line, msg):
    findings.append("%-4s %s:%s  %s" % (audit, rel(path), line, msg))

# ---------------------------------------------------------------- A1
# A member used inside a class body but never declared in it.
# Caught: CSSRPanel used m_saved / m_saved_mouse_move / m_saved_mouse_scroll
# from Phase 5 onward and declared none of them.
CLASS_RE = re.compile(r'^\s*class\s+(\w+)\s*(?::\s*(?:public|private|protected)?\s*(\w+))?', re.M)

def class_bodies(text):
    for m in CLASS_RE.finditer(text):
        start = text.find('{', m.end())
        if start < 0:
            continue
        depth, i, n = 0, start, len(text)
        while i < n:
            if text[i] == '{': depth += 1
            elif text[i] == '}':
                depth -= 1
                if depth == 0:
                    yield m.group(1), m.group(2), start, text[start:i + 1]
                    break
            i += 1

# A declaration is a whole line: a type token, one or more names, a
# semicolon, and no call or assignment.  Matching "m_x =" as a declaration
# is what let the missing CSSRPanel members hide -- the assignment inside
# Create() looked like the declaration that was never written.
DECL_LINE = re.compile(r'^\s*(?:static\s+)?(?:const\s+)?([A-Za-z_]\w*)\s+([^;=(){}]*);\s*$', re.M)
NOT_A_TYPE = {'return', 'delete', 'break', 'continue', 'case', 'goto', 'new'}

def declared_in(body):
    d = set()
    for m in DECL_LINE.finditer(body):
        if m.group(1) in NOT_A_TYPE:
            continue
        d |= set(re.findall(r'\b(m_\w+)\b', m.group(2)))
    return d

def audit_a1():
    # A member can come from a base class, so resolve the chain first.
    # Without this the audit fires on every provider that uses the
    # m_guard CSSRProviderBase gives it.
    own, base_of, where = {}, {}, {}
    for path, text in CLEAN.items():
        for name, base, start, body in class_bodies(text):
            own[name] = declared_in(body)
            base_of[name] = base
            where[name] = (path, text, start, body)

    def inherited(name, seen=None):
        seen = seen or set()
        d = set()
        b = base_of.get(name)
        while b and b not in seen:
            seen.add(b)
            d |= own.get(b, set())
            b = base_of.get(b)
        return d

    for name, (path, text, start, body) in where.items():
        declared = own[name] | inherited(name)
        used = set(re.findall(r'\b(m_\w+)\b', body))
        for miss in sorted(used - declared):
            off = start + body.find(miss)
            report("A1", path, text.count('\n', 0, off) + 1,
                   "class %s uses %s but neither it nor its bases declare it" % (name, miss))

# ---------------------------------------------------------------- A2
# A macro used above the line that defines it.  MQL5's preprocessor is
# strictly top-down, so this compiles as an undeclared identifier.
# Caught: SSR_EXTRA_STREAMS used at line 142, #define'd at 148.
def audit_a2():
    for path, text in CLEAN.items():
        lines = text.split('\n')
        defined = {}
        for i, ln in enumerate(lines, 1):
            m = re.match(r'\s*#define\s+(\w+)', ln)
            if m and m.group(1) not in defined:
                defined[m.group(1)] = i
        for name, dline in defined.items():
            pat = re.compile(r'\b%s\b' % re.escape(name))
            for i, ln in enumerate(lines[:dline - 1], 1):
                if ln.lstrip().startswith('#'):
                    continue
                if pat.search(ln):
                    report("A2", path, i,
                           "%s used here but #define is at line %d" % (name, dline))
                    break

# ---------------------------------------------------------------- A3
# MetaEditor rejects any #property version that is not x.yy.
# Caught: "0.1" -> "version '0.1' is incompatible with the current format".
def audit_a3():
    for path, text in FILES.items():
        for i, ln in enumerate(text.split('\n'), 1):
            m = re.match(r'\s*#property\s+version\s+"([^"]*)"', ln)
            if m and not re.fullmatch(r'\d+\.\d\d', m.group(1)):
                report("A3", path, i,
                       'version "%s" is not the x.yy form MetaEditor accepts' % m.group(1))

# ---------------------------------------------------------------- A4
# A literal passed where the parameter is a reference.  MQL5 has no
# temporaries to bind, so this is a hard error.
# Caught: my own T5.9 called Panel::OnEvent(..., 0, 0.0, "") while older
# sections of the same file correctly used variables.
# Restricted to method names that have exactly one signature codebase-wide;
# the looser version produced 66 false positives on overloads.
def audit_a4():
    sigs = collections.defaultdict(set)
    for path, text in CLEAN.items():
        for m in re.finditer(r'\b(\w+)\s*\(([^;{)]*)\)\s*(?:const\s*)?\{', text):
            name, params = m.group(1), m.group(2)
            if name in ('if', 'for', 'while', 'switch', 'return', 'sizeof'):
                continue
            sigs[name].add(params.strip())
    unique = {n: next(iter(s)) for n, s in sigs.items() if len(s) == 1}

    def split_args(s):
        out, depth, cur = [], 0, ''
        for ch in s:
            if ch in '([': depth += 1
            elif ch in ')]': depth -= 1
            if ch == ',' and depth == 0:
                out.append(cur); cur = ''
            else:
                cur += ch
        if cur.strip(): out.append(cur)
        return [a.strip() for a in out]

    LIT = re.compile(r'^(?:-?\d+(?:\.\d+)?|0[xX][0-9a-fA-F]+|true|false|NULL)$')
    for path, text in CLEAN.items():
        for m in re.finditer(r'\b(\w+)\s*\(([^;{)]*)\)\s*;', text):
            name, call = m.group(1), m.group(2)
            if name not in unique:
                continue
            params = split_args(unique[name])
            args = split_args(call)
            if len(params) != len(args):
                continue
            for p, a in zip(params, args):
                if '&' in p and LIT.match(a):
                    report("A4", path, text.count('\n', 0, m.start()) + 1,
                           "%s() takes %s by reference; a literal (%s) cannot bind"
                           % (name, p.split()[-1].lstrip('&'), a))

# ---------------------------------------------------------------- A5
# MQL5 caps a function's local variable section at 2 MB.  A class holding a
# large inline array blows that cap the moment a test declares one on the
# stack -- and the error points at the *test*, not at the class.
# Caught: CSSRTradingEngine held SSRVirtualPosition m_pos[512]; the Phase 10
# leg ledger took each position from 213 to 661 bytes, so one engine was
# 338 KB and a test building several per section went over 2 MB.
PRIM = {"char":1,"uchar":1,"bool":1,"short":2,"ushort":2,"int":4,"uint":4,
        "color":4,"float":4,"long":8,"ulong":8,"double":8,"datetime":8,
        "string":12}

INT_DEFINE = {}
for _p, _t in CLEAN.items():
    for _m in re.finditer(r'^\s*#define\s+(\w+)\s+(\d+)\s*$', _t, re.M):
        INT_DEFINE.setdefault(_m.group(1), int(_m.group(2)))

def array_count(expr):
    """Resolve an array length that may be written as a macro."""
    e = expr.strip()
    if re.fullmatch(r'\d+', e):
        return int(e)
    return INT_DEFINE.get(e)

def type_sizes():
    """Size every struct/class we can, smallest first, resolving nesting."""
    decls = {}
    for path, text in CLEAN.items():
        for m in re.finditer(r'\b(?:struct|class)\s+(\w+)[^;{]*\{', text):
            start = m.end() - 1
            depth, i, n = 0, start, len(text)
            while i < n:
                if text[i] == '{': depth += 1
                elif text[i] == '}':
                    depth -= 1
                    if depth == 0:
                        decls[m.group(1)] = (path, text[start:i], text.count('\n',0,m.start())+1)
                        break
                i += 1
    sizes, changed = dict(PRIM), True
    for name in decls:
        sizes.setdefault(name, None)
    while changed:
        changed = False
        for name, (path, body, line) in decls.items():
            if sizes.get(name) is not None:
                continue
            total, ok = 0, True
            for fm in re.finditer(r'^\s*(?:static\s+)?(\w+)\s+(\w+)\s*(?:\[([^\]]*)\])?\s*;',
                                  body, re.M):
                ftype, _fname, count = fm.groups()
                if ftype in ('return','const','virtual','void','public','private',
                             'protected','else','if','enum','struct','class'):
                    continue
                base = sizes.get(ftype)
                if ftype.startswith('ENUM_'):
                    base = 4
                if base is None:
                    if ftype in sizes:
                        ok = False
                    continue
                if count is None:                      # a plain field
                    total += base
                elif count.strip() == '':              # dynamic: a handle, not storage
                    total += 16
                else:
                    n = array_count(count)
                    if n is None:
                        # An array whose length we cannot resolve. Guessing low
                        # here is how the leg array hid: [SSR_MAX_TRADE_LEGS]
                        # read as dynamic and 8 legs per position vanished.
                        ok = False
                        break
                    total += base * n
            if ok:
                sizes[name] = total
                changed = True
    return sizes, decls

def audit_a5():
    sizes, decls = type_sizes()
    CAP = 2 * 1024 * 1024
    for name, (path, body, line) in decls.items():
        size = sizes.get(name)
        if size and size > 64 * 1024:
            report("A5", path, line,
                   "%s is %s bytes inline; one on the stack eats %.1f%% of the 2 MB cap"
                   % (name, format(size, ','), 100.0 * size / CAP))

#---------------------------------------------------------------------------
# A6 - a method called on one of our own objects must exist somewhere.
#
# `g_gport.AttachLines(...)` compiled here and failed in MetaEditor with
# "undeclared identifier": a patch had written the call site but its other
# half - the method itself - never reached disk. Two errors, one round
# trip, and the only reason it took a round trip is that there is no MQL5
# compiler on this machine.
#
# So: collect every method declared anywhere in the tree, then check every
# call made on a `g_`-prefixed global. Deliberately narrow. It only flags a
# name that appears NOWHERE as a declaration, which cannot be an inherited
# method, a MetaTrader builtin, or a name this crude parser mis-reads - it
# can only be a call to something that does not exist.
#---------------------------------------------------------------------------
#--- the star hugs the NAME in this codebase - `CSSRBarProvider *Bars(void)`
#--- - so whitespace after it must be optional, or every pointer-returning
#--- method reads as undeclared. Three false positives said so immediately.
DECL_METHOD = re.compile(
    r'^\s*(?:virtual\s+|static\s+|const\s+)*'
    r'([A-Za-z_][\w:]*)\s*[\*&]?\s*'
    r'([A-Za-z_]\w*)\s*\(', re.M)

#--- `return Foo(...)` is a call, not a declaration of a method named Foo
NOT_A_RETURN_TYPE = {
    'return', 'if', 'while', 'for', 'switch', 'else', 'do', 'case',
    'delete', 'new', 'break', 'continue', 'goto', 'sizeof',
}

CALL_ON_GLOBAL = re.compile(r'\bg_[A-Za-z_]\w*\s*\.\s*([A-Za-z_]\w*)\s*\(')

#--- A7 widens A6 from globals to MEMBERS.
#---
#--- A6 was written after `g_gport.AttachLines(...)` shipped without the
#--- method: two compile errors and an EA missing from the Navigator,
#--- because a patch script printed success for a hunk it never applied.
#--- It only watched g_ names. The panel rewrite added dozens of
#--- m_w., m_port., m_acct. and m_lines. calls across four layers at
#--- once, which is precisely the shape of change where one half lands
#--- and the other does not - and A6 could not see any of them.
CALL_ON_MEMBER = re.compile(r'\bm_[a-z_]\w*\s*\.\s*([A-Za-z_]\w*)\s*\(')

#--- ...and to LOCAL objects of our own classes. Removing
#--- CSSRPanel::SetPosition broke SSR_T15_Ux, which calls it on a local
#--- named panel2 - a receiver neither the g_ nor the m_ pattern
#--- matches. The tests are compiled by the updater and are exactly
#--- where a removed method surfaces last, so they are the ones that
#--- most need this.
LOCAL_DECL = re.compile(r'\b(CSSR[A-Za-z]\w*)\s+([a-z]\w*)\s*[;=]')

def audit_a6():
    declared = set()
    for path, body in CLEAN.items():
        for m in DECL_METHOD.finditer(body):
            if m.group(1) in NOT_A_RETURN_TYPE:
                continue
            declared.add(m.group(2))

    #--- MQL5 gives every object these; they are never declared by us
    declared |= {"Detach", "Release"}

    for path, body in CLEAN.items():
        for m in CALL_ON_GLOBAL.finditer(body):
            name = m.group(1)
            if name in declared:
                continue
            report("A6", path, body[:m.start()].count("\n") + 1,
                   "%s() is called on one of our objects but declared nowhere - "
                   "the other half of a change did not land" % name)

#--- A8: every `override` needs something to override.
#---
#--- CSSRGroupPort::OpenFromLines shipped with `override` while the base
#--- port never got the declaration - a string replacement that matched
#--- nothing because the anchor's whitespace differed by one space, and
#--- that I had not asserted on. Three compile errors, and A7 was blind
#--- to it because the method IS declared: just on the wrong class.
#---
#--- A base declaration is a line that says `virtual` and does NOT say
#--- `override`. So an override whose name never appears that way has
#--- nothing above it, which is exactly the error MetaEditor reports.
OVERRIDE_DECL = re.compile(r'^\s*(?:virtual\s+)?[A-Za-z_][\w:]*\s*[\*&]?\s*'
                           r'([A-Za-z_]\w*)\s*\([^;{]*\)\s*(?:const\s*)?override', re.M)
VIRTUAL_DECL  = re.compile(r'^\s*virtual\s+[A-Za-z_][\w:]*\s*[\*&]?\s*'
                           r'([A-Za-z_]\w*)\s*\(', re.M)

#--- A9: the same method defined twice in the same class.
#---
#--- AnyPlaying() was added to CSSRMasterClock by a patch that never
#--- looked whether the class already had one - it did, in a "queries"
#--- section 300 lines down. MetaEditor: "member function already
#--- defined". Nothing here checked for that shape.
#---
#--- Overloads are legal, so the key is (class, name, normalised args).
#--- Class scope is tracked by brace depth, because several structs in
#--- one file legitimately each define Init(void).
CLASS_HEAD = re.compile(r'^\s*(?:class|struct)\s+([A-Za-z_]\w*)')
METHOD_DEF = re.compile(r'^\s*(?:virtual\s+|static\s+|const\s+)*'
                        r'[A-Za-z_][\w:]*\s*[\*&]?\s+'
                        r'([A-Za-z_]\w*)\s*\(([^)]*)\)')

#--- A10: writing to a parameter declared const.
#---
#--- Extracting BuildSession out of OnInit gave every parameter a const
#--- it had not earned: the random-session path reassigns `origin` to
#--- the instrument it picked. MetaEditor: "'origin' - constant cannot
#--- be modified". Nothing here read the body before deciding.
#---
#--- Only same-line, unambiguous writes are reported: `x =`, `x +=`,
#--- `x++`, `--x`. Comparisons and `==` are excluded, so a false
#--- positive would need a genuinely strange line.
FUNC_HEAD = re.compile(r'^[A-Za-z_][\w:]*\s*[\*&]?\s*([A-Za-z_]\w*)\s*\(([^)]*)\)\s*$', re.M)
CONST_PARAM = re.compile(r'\bconst\s+[A-Za-z_][\w:]*\s*[\*&]?\s*([A-Za-z_]\w*)\s*(?:,|$)')

def audit_a10():
    for path, body in CLEAN.items():
        lines = body.splitlines()
        for m in FUNC_HEAD.finditer(body):
            names = CONST_PARAM.findall(m.group(2))
            if not names:
                continue
            start = body[:m.end()].count("\n")
            #--- a DEFINITION, not a prototype or a call: the next
            #--- non-empty line must open a body. Without this the scan
            #--- ran past the header into whatever followed and read
            #--- another function's locals as writes to these names.
            nxt = start + 1
            while nxt < len(lines) and lines[nxt].strip() == "":
                nxt += 1
            if nxt >= len(lines) or not lines[nxt].strip().startswith("{"):
                continue
            depth, seen_open, end = 0, False, start
            for i in range(start, min(start + 900, len(lines))):
                depth += lines[i].count("{") - lines[i].count("}")
                if depth > 0:
                    seen_open = True
                if seen_open and depth <= 0:
                    end = i
                    break
            for n in names:
                w = re.compile(r'(?<![\w.])' + re.escape(n) +
                               r'\s*(?:\+\+|--|(?:[+\-*/|&^]?=(?!=)))')
                #--- `long n = 0;` DECLARES a local; it does not write to
                #--- a parameter that happens to share the name
                decl = re.compile(r'^\s*(?:const\s+)?[A-Za-z_][\w:]*\s*[\*&]?\s+' +
                                  re.escape(n) + r'\s*(?:=|;|\[)')
                for i in range(start + 1, end + 1):
                    if decl.match(lines[i]):
                        break
                    if w.search(lines[i]):
                        report("A10", path, i + 1,
                               "%s() writes to '%s', which it declares const - "
                               "the signature was chosen without reading the body"
                               % (m.group(1), n))
                        break

def audit_a9():
    for path, body in CLEAN.items():
        depth = 0
        cls = None
        cls_depth = -1
        seen = {}
        entered = False
        for ln, line in enumerate(body.splitlines(), 1):
            m = CLASS_HEAD.match(line)
            if m and depth == 0:
                cls, cls_depth, seen, entered = m.group(1), depth, {}, False
            if cls is not None and depth == 1:
                d = METHOD_DEF.match(line)
                if d and d.group(1) not in NOT_A_RETURN_TYPE:
                    args = re.sub(r'\s+', '', re.sub(r'\bconst\b', '', d.group(2)))
                    key = (d.group(1), args)
                    if key in seen:
                        report("A9", path, ln,
                               "%s::%s() is defined twice (first at line %d) - "
                               "a patch added what the class already had"
                               % (cls, d.group(1), seen[key]))
                    else:
                        seen[key] = ln
            depth += line.count("{") - line.count("}")
            #--- the header line itself still sits AT cls_depth; the class
            #--- is only over once we have been inside and come back out.
            #--- Without `entered`, cls died on the very line it was set -
            #--- and this audit approved the live duplicate it was written
            #--- to catch, on its first run.
            if cls is not None and depth > cls_depth:
                entered = True
            if cls is not None and entered and depth <= cls_depth:
                cls = None
    return

def audit_a8():
    bases = set()
    for path, body in CLEAN.items():
        for line in body.splitlines():
            if "override" in line:
                continue
            m = VIRTUAL_DECL.match(line)
            if m:
                bases.add(m.group(1))

    for path, body in CLEAN.items():
        for m in OVERRIDE_DECL.finditer(body):
            if m.group(1) in bases:
                continue
            report("A8", path, body[:m.start()].count("\n") + 1,
                   "%s() is marked override but no base declares it virtual - "
                   "the base half of the change did not land" % m.group(1))

def audit_a7():
    declared = set()
    for path, body in CLEAN.items():
        for m in DECL_METHOD.finditer(body):
            if m.group(1) in NOT_A_RETURN_TYPE:
                continue
            declared.add(m.group(2))
    declared |= {"Detach", "Release"}

    for path, body in CLEAN.items():
        locals_here = set(n for _, n in LOCAL_DECL.findall(body))
        if locals_here:
            pat = re.compile(r'\b(?:%s)\s*\.\s*([A-Za-z_]\w*)\s*\('
                             % "|".join(sorted(re.escape(n) for n in locals_here)))
            for m in pat.finditer(body):
                if m.group(1) in declared:
                    continue
                report("A7", path, body[:m.start()].count("\n") + 1,
                       "%s() is called on one of our objects but declared "
                       "nowhere - the other half of a change did not land"
                       % m.group(1))
        for m in CALL_ON_MEMBER.finditer(body):
            name = m.group(1)
            if name in declared:
                continue
            report("A7", path, body[:m.start()].count("\n") + 1,
                   "%s() is called on a member of ours but declared nowhere - "
                   "the other half of a change did not land" % name)

for fn in (audit_a1, audit_a2, audit_a3, audit_a4, audit_a5, audit_a6, audit_a7, audit_a8, audit_a9, audit_a10):
    fn()

if findings:
    print("\n".join(findings))
    print("\n%d finding(s)." % len(findings))
    sys.exit(1)
print("all audits silent across %d source files under %s" % (len(FILES), rel(ROOT) or "MQL5"))

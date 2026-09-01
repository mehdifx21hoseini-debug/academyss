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

def blank_comments_keep_strings(text):
    """Comments blanked, string literals kept as a same-length token.

    CLEAN blanks literals outright, which is right for every audit that
    reads code shape - and wrong for counting arguments, because a call
    whose only argument is a string became an empty pair of brackets.
    A12's first version reported exactly that as "passed 0 arguments".
    An audit that cries wolf is worse than none, and this is the third
    time that has had to be fixed before the audit could be trusted.

    Length is preserved character for character so offsets found in
    CLEAN address the same place here.
    """
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
            body = text[i:j]
            out.append(q + ''.join(ch if ch == '\n' else '_'
                                   for ch in body[1:-1]) + q
                       if len(body) >= 2 else body)
            i = j
        else:
            out.append(c); i += 1
    return ''.join(out)

FILES = {p: open(p, encoding="utf-8", errors="replace").read() for p in sources()}
CLEAN = {p: strip_comments(t) for p, t in FILES.items()}
KEEPSTR = {p: blank_comments_keep_strings(t) for p, t in FILES.items()}

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

#--- A11: the method must exist on THAT object's class.
#---
#--- A7 asks "is this name declared anywhere in the tree", and that is
#--- exactly how g_group.Status() shipped: Status() is real - on
#--- CSSRReplayController - and g_group is a CSSRReplayGroup, which has
#--- no such method. Three compile errors from a name that existed.
#---
#--- A8 covers the same shape for `override`; this covers it for plain
#--- calls on globals whose type is written right there in the file.
#--- Only globals declared as `CSSRThing g_name;` are checked - pointers
#--- and locals are left to A7, which is weaker but never wrong-headed.
GLOBAL_DECL = re.compile(r'^(CSSR[A-Za-z]\w*)\s+(g_[a-z_0-9]+)\s*(?:;|\[)', re.M)
CLASS_BODY  = re.compile(r'^class\s+(CSSR[A-Za-z]\w*)\s*(?::\s*public\s+(CSSR[A-Za-z]\w*))?',
                         re.M)

def class_methods():
    """name -> set of methods, following single inheritance."""
    own, base = {}, {}
    for path, body in CLEAN.items():
        lines = body.splitlines()
        for m in CLASS_BODY.finditer(body):
            cls = m.group(1)
            own.setdefault(cls, set())
            if m.group(2):
                base[cls] = m.group(2)
            start = body[:m.end()].count("\n")
            depth, seen, end = 0, False, len(lines) - 1
            for i in range(start, len(lines)):
                depth += lines[i].count("{") - lines[i].count("}")
                if depth > 0:
                    seen = True
                if seen and depth <= 0:
                    end = i
                    break
            for i in range(start, end + 1):
                d = DECL_METHOD.match(lines[i])
                if d and d.group(1) not in NOT_A_RETURN_TYPE:
                    own[cls].add(d.group(2))
    #--- fold bases in
    for cls in list(own):
        seen, cur = set(), base.get(cls)
        while cur and cur in own and cur not in seen:
            seen.add(cur)
            own[cls] |= own[cur]
            cur = base.get(cur)
    return own

def audit_a11():
    methods = class_methods()
    for path, body in CLEAN.items():
        types = {}
        for m in GLOBAL_DECL.finditer(body):
            if m.group(1) in methods:
                types[m.group(2)] = m.group(1)
        if not types:
            continue
        pat = re.compile(r'\b(' + "|".join(sorted(re.escape(g) for g in types)) +
                         r')\s*\.\s*([A-Za-z_]\w*)\s*\(')
        for m in pat.finditer(body):
            cls = types[m.group(1)]
            if m.group(2) in methods[cls] or m.group(2) in ("Detach", "Release"):
                continue
            report("A11", path, body[:m.start()].count("\n") + 1,
                   "%s.%s() - %s has no such method (the name exists on some "
                   "other class)" % (m.group(1), m.group(2), cls))

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


#--- A12: the call must pass as many arguments as the method takes.
#---
#--- A11 asks "does this class have a method with that name". It said
#--- yes to sink.NeedsWarmup() - and NeedsWarmup takes two arguments.
#--- The name existed, on the right class, with the wrong shape: the
#--- same family of mistake as A7 -> A8 -> A11, one level finer.
#---
#--- Deliberately narrow. Only globals declared as `CSSRThing g_name;`,
#--- only methods whose every declaration on that class is unambiguous,
#--- and a name declared with several different shapes is left alone.
#--- An audit that cries wolf is worse than no audit, and two of these
#--- have already had to be fixed before they could be trusted.
def method_arities():
    """cls -> name -> set of (min_args, max_args) pairs."""
    own, base = {}, {}
    for path, body in KEEPSTR.items():
        lines = body.splitlines()
        for m in CLASS_BODY.finditer(body):
            cls = m.group(1)
            own.setdefault(cls, {})
            if m.group(2):
                base[cls] = m.group(2)
            start = body[:m.end()].count("\n")
            depth, seen, end = 0, False, len(lines) - 1
            for i in range(start, len(lines)):
                depth += lines[i].count("{") - lines[i].count("}")
                if depth > 0:
                    seen = True
                if seen and depth <= 0:
                    end = i
                    break
            blob = "\n".join(lines[start:end + 1])
            for d in DECL_METHOD.finditer(blob):
                if d.group(1) in NOT_A_RETURN_TYPE:
                    continue
                params = balanced_args(blob, d.end() - 1)
                if params is None:
                    continue
                lo, hi = param_range(params)
                own[cls].setdefault(d.group(2), set()).add((lo, hi))
    for cls in list(own):
        seen, cur = set(), base.get(cls)
        while cur and cur in own and cur not in seen:
            seen.add(cur)
            for name, shapes in own[cur].items():
                own[cls].setdefault(name, set()).update(shapes)
            cur = base.get(cur)
    return own

def balanced_args(text, open_paren):
    """The raw argument text between a '(' and its match, or None."""
    depth, i, n = 0, open_paren, len(text)
    instr = None
    while i < n:
        c = text[i]
        if instr:
            if c == "\\":
                i += 2
                continue
            if c == instr:
                instr = None
        elif c in "\"'":
            instr = c
        elif c == "(":
            depth += 1
        elif c == ")":
            depth -= 1
            if depth == 0:
                return text[open_paren + 1:i]
        i += 1
    return None

def split_args(raw):
    """Top-level comma count, respecting nesting and string literals."""
    if raw.strip() == "" or raw.strip() == "void":
        return 0
    depth, instr, parts = 0, None, 1
    i, n = 0, len(raw)
    while i < n:
        c = raw[i]
        if instr:
            if c == "\\":
                i += 2
                continue
            if c == instr:
                instr = None
        elif c in "\"'":
            instr = c
        elif c in "([{":
            depth += 1
        elif c in ")]}":
            depth -= 1
        elif c == "," and depth == 0:
            parts += 1
        i += 1
    return parts

def param_range(raw):
    """(minimum, maximum) arguments a declaration accepts."""
    total = split_args(raw)
    if total == 0:
        return (0, 0)
    #--- one '=' at top level per defaulted parameter
    depth, instr, defaults = 0, None, 0
    i, n = 0, len(raw)
    while i < n:
        c = raw[i]
        if instr:
            if c == "\\":
                i += 2
                continue
            if c == instr:
                instr = None
        elif c in "\"'":
            instr = c
        elif c in "([{":
            depth += 1
        elif c in ")]}":
            depth -= 1
        elif c == "=" and depth == 0 and raw[i - 1] not in "!<>=" and \
             (i + 1 >= n or raw[i + 1] != "="):
            defaults += 1
        i += 1
    return (total - defaults, total)

#--- members too, not only globals. `m_w.Hide("x")` on a two-argument
#--- Hide slipped straight past A12's first version, because m_w is a
#--- member of the panel rather than a global - and a widget toolkit is
#--- called almost entirely through members. Checking one and not the
#--- other left the audit blind to the commonest call site in the tree.
MEMBER_DECL = re.compile(r'^\s+(CSSR[A-Za-z]\w*)\s+(m_[a-z_0-9]+)\s*(?:;|\[)', re.M)

def audit_a12():
    arities = method_arities()
    for path, body in KEEPSTR.items():
        types = {}
        for m in GLOBAL_DECL.finditer(body):
            if m.group(1) in arities:
                types[m.group(2)] = m.group(1)
        for m in MEMBER_DECL.finditer(body):
            if m.group(1) in arities:
                types[m.group(2)] = m.group(1)
        if not types:
            continue
        pat = re.compile(r'\b(' + "|".join(sorted(re.escape(g) for g in types)) +
                         r')\s*\.\s*([A-Za-z_]\w*)\s*\(')
        for m in pat.finditer(body):
            cls, name = types[m.group(1)], m.group(2)
            shapes = arities.get(cls, {}).get(name)
            if not shapes:
                continue                      # A11's business, not mine
            raw = balanced_args(body, m.end() - 1)
            if raw is None:
                continue                      # unbalanced: say nothing
            given = split_args(raw)
            if any(lo <= given <= hi for lo, hi in shapes):
                continue
            want = " or ".join(sorted("%d" % lo if lo == hi else "%d-%d" % (lo, hi)
                                      for lo, hi in shapes))
            report("A12", path, body[:m.start()].count("\n") + 1,
                   "%s.%s() is passed %d argument(s); %s::%s takes %s"
                   % (m.group(1), name, given, cls, name, want))


#--- A13: a name is called that nothing in this tree declares.
#---
#--- FlightGuard() shipped as a call with no definition. A patch script
#--- made three edits, its third assertion failed, and the file was
#--- never written - so two edits were silently discarded while the
#--- third, applied by a later script, went in and referred to a
#--- function that no longer existed. Four compile errors reached the
#--- user, who had already installed the build.
#---
#--- The trap is that MQL5 has hundreds of built-ins and no list of
#--- them here, so "undeclared" cannot be computed from first
#--- principles without inventing false positives. It can be computed
#--- from HISTORY: every name the compiling tree calls but does not
#--- declare is, by definition, a built-in. Baseline those once, and
#--- anything new is a name someone just introduced.
BASELINE = os.path.join(os.path.dirname(os.path.abspath(__file__)),
                        "ssr_known_calls.txt")
CALL_ANY = re.compile(r'(?<![\w.])([A-Za-z_]\w*)\s*\(')
DEFINE_NAME = re.compile(r'^\s*#\s*define\s+([A-Za-z_]\w*)', re.M)
CALL_KEYWORDS = {'if', 'while', 'for', 'switch', 'return', 'sizeof', 'else',
                 'do', 'case', 'new', 'delete', 'catch'}

def audit_a13():
    try:
        with open(BASELINE) as fh:
            known = set(l.strip() for l in fh
                        if l.strip() and not l.startswith("#"))
    except IOError:
        return                      # no baseline, no opinion

    declared = set()
    for body in CLEAN.values():
        for m in DECL_METHOD.finditer(body):
            if m.group(1) not in NOT_A_RETURN_TYPE:
                declared.add(m.group(2))
        #--- A MACRO IS A DECLARATION TOO.
        #---
        #--- `#define SSR_PANEL_H (23 + 32 + ...)` reads as a call to a
        #--- function nobody wrote, and the audit said so. It was right
        #--- about the text and wrong about the code, which is the one
        #--- failure mode an audit is not allowed: a report that cries
        #--- wolf gets read past, and the next finding it makes is the
        #--- real one nobody looks at.
        for m in DEFINE_NAME.finditer(body):
            declared.add(m.group(1))

    for path, body in CLEAN.items():
        seen = set()
        for m in CALL_ANY.finditer(body):
            name = m.group(1)
            #--- A constructor's initialiser list is `m_thing(0)`, which
            #--- looks exactly like a call. This project names members
            #--- m_, globals g_ and statics s_, and none of those is ever
            #--- a function - so they are data, not calls. Without this
            #--- the baseline absorbed 223 member names on the day it was
            #--- generated, and every one of them was then permanently
            #--- allowed: an audit quietly holding a list of things it
            #--- promises never to notice.
            if name[:2] in ("m_", "g_", "s_"):
                continue
            if (name in CALL_KEYWORDS or name in declared or name in known
                    or name in seen):
                continue
            seen.add(name)
            report("A13", path, body[:m.start()].count("\n") + 1,
                   "%s() is called but nothing in this tree declares it - "
                   "either a definition that never landed, or a built-in "
                   "that belongs in tools/ssr_known_calls.txt" % name)


#--- A14: MetaTrader cuts an object's text at 63 characters.
#---
#--- A screen recording showed the picker hint ending mid-word:
#--- "...then press the gre". Counted from the frame, the cut lands at
#--- exactly 63 - the platform's limit on OBJPROP_TEXT.
#---
#--- Nothing else could have caught it. No log prints an object's
#--- description, no test reads the screen, and the string in the source
#--- is perfectly correct. Only the pixels were wrong.
#---
#--- Only literal strings are measured. A concatenation with a runtime
#--- value cannot be measured here, so those are left alone rather than
#--- guessed at - but a literal already past the limit is past it for
#--- every possible value of everything else.
#---
#--- IT USED TO WATCH ONLY ObjectSetString, and almost nothing in this
#--- tree calls that directly any more - the widgets do. So the audit was
#--- green over a first-run card written entirely in Label() calls, and a
#--- deliberate 80-character line sailed straight through it. An audit
#--- that misses is worse than no audit at the moment somebody writes a
#--- comment saying it is covered.
SET_TEXT = re.compile(
    r'ObjectSetString\s*\([^;]*?OBJPROP_TEXT\s*,\s*"((?:[^"\\]|\\.)*)"\s*\)',
    re.S)

#--- the widget helpers whose text argument lands in OBJPROP_TEXT. Each
#--- is (name, index of the text argument among the arguments).
WIDGET_TEXT = (("Label", 3), ("Button", 5), ("ButtonC", 5), ("Edit", 5))
OBJ_TEXT_MAX = 63


def _args(raw, at):
    """The argument list of a call whose opening paren is at `at`,
    split on top-level commas with string literals kept whole."""
    depth, i, cur, out = 0, at, "", []
    while i < len(raw):
        c = raw[i]
        if c == '"':
            j = i + 1
            while j < len(raw) and (raw[j] != '"' or raw[j - 1] == "\\"):
                j += 1
            cur += raw[i:j + 1]
            i = j + 1
            continue
        if c in "([":
            depth += 1
            if depth == 1 and c == "(":
                i += 1
                continue
        elif c in ")]":
            depth -= 1
            if depth == 0:
                out.append(cur)
                return out
        if depth == 1 and c == ",":
            out.append(cur)
            cur = ""
        else:
            cur += c
        i += 1
    return out

LITERAL_ONLY = re.compile(r'^\s*"((?:[^"\\]|\\.)*)"\s*$', re.S)

def _flag(path, raw, pos, text):
    if len(text) <= OBJ_TEXT_MAX:
        return
    report("A14", path, raw[:pos].count("\n") + 1,
           "object text is %d characters; MetaTrader shows %d and "
           "cuts the rest: \"%s|%s\""
           % (len(text), OBJ_TEXT_MAX,
              text[:OBJ_TEXT_MAX], text[OBJ_TEXT_MAX:]))

def audit_a14():
    for path, body in KEEPSTR.items():
        raw = FILES[path]
        for m in SET_TEXT.finditer(raw):
            _flag(path, raw, m.start(), m.group(1))

        #--- and the widgets, which is where the text actually comes
        #--- from in this tree
        for name, idx in WIDGET_TEXT:
            for m in re.finditer(r'\.%s\s*\(' % name, raw):
                args = _args(raw, m.end() - 1)
                if len(args) <= idx:
                    continue
                lit = LITERAL_ONLY.match(args[idx])
                if lit is None:
                    continue          # built at runtime; cannot be measured
                _flag(path, raw, m.start(), lit.group(1))



#--- A15: a millisecond constant defined as a bare int.
#---
#--- `#define SSR_PROP_DAY_MSC 86400000` fits in an int, so MQL5 typed it
#--- as one - and computed `SSR_PROP_DAY_MSC * 100` in int arithmetic,
#--- overflowed, and handed the caller 50065408. The compiler said
#--- "warning", the smoke test drove a whole prop-firm evaluation off
#--- the wrong number, and fourteen audits were silent.
#---
#--- The rule is narrow on purpose: a constant whose NAME says
#--- milliseconds and whose value is big enough that one multiplication
#--- overflows must be cast where it is defined, not at every call site
#--- that a future author will forget.
DEFINE_MSC = re.compile(
    r'^[ \t]*#[ \t]*define[ \t]+(\w*(?:MSC|MS)\w*)[ \t]+([^\n]*)$',
    re.M | re.I)
MSC_INT_MIN = 1000000

def audit_a15():
    for path, body in KEEPSTR.items():
        raw = FILES[path]
        for m in DEFINE_MSC.finditer(raw):
            name, val = m.group(1), m.group(2).strip()
            if "long" in val:
                continue
            bare = re.match(r'^\(*\s*(-?\d+)\s*\)*\s*(?://.*)?$', val)
            if bare is None:
                continue
            if abs(int(bare.group(1))) < MSC_INT_MIN:
                continue
            report("A15", path, raw[:m.start()].count("\n") + 1,
                   "%s is %s, an int - and int arithmetic overflows at "
                   "2147483647, so the first caller who multiplies it gets "
                   "a wrong number and a warning. Define it as ((long)%s)."
                   % (name, bare.group(1), bare.group(1)))


#--- A16: two things side by side where only one can be.
#---
#--- MQL5 concatenates ADJACENT string literals, so a line reads
#--- perfectly and means something else the moment an inner quote is not
#--- escaped: `"price "53 671.4"=%d"` is the literal `"price "`, then a
#--- bare `53`, then another literal. The compiler calls it "some
#--- operator expected" - which is true, and says nothing about quotes.
#---
#--- That line had never compiled. It shipped in every package this
#--- project has ever produced, because nothing here compiles anything.
#--- So: a string literal may be followed by another literal or by an
#--- operator. It may never be followed by a word or a number.
def audit_a16():
    for path in FILES:
        raw = FILES[path]
        i, n = 0, len(raw)
        while i < n:
            c = raw[i]
            #--- comments first, or a quote inside one is a false alarm
            if c == "/" and i + 1 < n and raw[i + 1] == "/":
                j = raw.find("\n", i)
                i = n if j < 0 else j + 1
                continue
            if c == "/" and i + 1 < n and raw[i + 1] == "*":
                j = raw.find("*/", i + 2)
                i = n if j < 0 else j + 2
                continue
            if c != '"':
                i += 1
                continue

            j = i + 1
            while j < n and raw[j] != '"':
                j += 2 if raw[j] == "\\" else 1
            if j >= n:
                break

            #--- SPACES AND TABS ONLY, never a newline. Two literals on
            #--- consecutive lines are the concatenation this whole tree
            #--- is written in, and `#include "x.mqh"` is followed by
            #--- whatever statement comes next - both perfectly legal.
            #--- The bug this looks for is always on ONE line.
            k = j + 1
            while k < n and raw[k] in " \t":
                k += 1
            if k < n and (raw[k].isalnum() or raw[k] == "_"):
                report("A16", path, raw[:i].count("\n") + 1,
                       "a string literal is followed by `%s`, which cannot "
                       "come after one. Almost always an inner quote that "
                       "needed a backslash: \"...\\\"like this\\\"...\""
                       % raw[k:k + 12].split("\n")[0].strip())
            i = j + 1


for fn in (audit_a1, audit_a2, audit_a3, audit_a4, audit_a5, audit_a6, audit_a7, audit_a8, audit_a9, audit_a10, audit_a11, audit_a12, audit_a13, audit_a14, audit_a15, audit_a16):
    fn()

if findings:
    print("\n".join(findings))
    print("\n%d finding(s)." % len(findings))
    sys.exit(1)
print("all audits silent across %d source files under %s" % (len(FILES), rel(ROOT) or "MQL5"))

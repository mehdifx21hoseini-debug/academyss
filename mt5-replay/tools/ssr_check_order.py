#!/usr/bin/env python3
"""Advisory scan: a Check() whose detail may be built before its condition runs.

MQL5 does not promise the order it evaluates a call's arguments in, and in
practice it builds `detail` before it runs `cond`.  Six PASS lines in the v90
run came back with an empty detail because of it, and one printed a LONG setup
under "the lines arm SHORT".

This is NOT wired into ssr_audit.py and should not be.  Measured on v91:
28 hits, of which 13 are a read-only getter on both sides and cannot be wrong.
Telling the truth about half its output is not an audit, it is a reading list -
so it stays a thing you run and read, not a gate that fails a build.

    python3 tools/ssr_check_order.py MQL5/Scripts/SSReplay/QA/SSR_QA_Smoke.mq5
"""
import io,re,sys,glob
PURE = {'StringFind','StringLen','StringSubstr','ObjectGetString','ObjectGetInteger',
        'ObjectFind','ObjectsTotal','SymbolInfoInteger','SymbolInfoDouble','Bars',
        'ChartGetInteger','ArraySize','MathAbs','FileIsExist','StringFormat',
        'DoubleToString','IntegerToString','TimeToString','CopyRates'}
def calls(src):
    out=[]
    for i,l in enumerate(src.split('\n')):
        if not re.search(r'\bCheck\(',l): continue
        j=i;d=0;buf=[]
        while j<len(src.split('\n')):
            ln=src.split('\n')[j];buf.append(ln)
            d+=ln.count('(')-ln.count(')')
            if d<=0 and j>=i: break
            j+=1
        out.append((i+1,'\n'.join(buf)))
    return out
def split_args(body):
    parts=[];d=0;cur='';instr=False;k=0
    while k<len(body):
        c=body[k]
        if c=='"' and (k==0 or body[k-1]!='\\'): instr=not instr
        if not instr:
            if c=='(': d+=1
            elif c==')':
                if d==0: break
                d-=1
            elif c==',' and d==0:
                parts.append(cur);cur='';k+=1;continue
        cur+=c;k+=1
    parts.append(cur);return parts
for path in sys.argv[1:]:
    s=io.open(path,encoding='utf-8').read()
    # the rule is written out in a comment beside Check(); do not
    # scan the example that documents the bug and report it as one
    s='\n'.join(re.sub(r'//.*$','',l) for l in s.split('\n'))
    for ln,call in calls(s):
        p=split_args(call[call.index('Check(')+6:])
        if len(p)<3: continue
        cond,det=p[1],','.join(p[2:])
        dets=re.sub(r'"(\\.|[^"\\])*"','',det)
        # A: a getter in the detail on an object the condition calls a method on
        for obj,meth in re.findall(r'\b([a-z_]\w*)\.(\w+)\s*\(',cond):
            if meth in PURE: continue
            gets=[g for o,g in re.findall(r'\b([a-z_]\w*)\.(\w+)\s*\(\s*\)',dets) if o==obj and g!=meth]
            if gets:
                print(f"{path}:{ln}  detail reads {obj}.{gets[0]}() while the condition calls {obj}.{meth}()")
                break
        else:
            # B: a bare identifier in a non-first argument position, printed in the detail
            for m in re.finditer(r'\b\w+\s*\(([^()]*)\)',cond):
                args=[a.strip() for a in m.group(1).split(',')]
                for a in args[1:]:
                    if re.fullmatch(r'[a-z_]\w*',a) and a not in ('true','false','NULL') and re.search(r'\b'+a+r'\b',dets):
                        print(f"{path}:{ln}  detail prints [{a}], which the condition passes by reference")
                        break
                else: continue
                break

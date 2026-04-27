"""Inspect the flyer JSON structure."""
import json, sys
sys.stdout.reconfigure(encoding="utf-8", errors="replace")
TMP = r"c:/Users/danil/Desktop/projetosflutter/bora_app/.claude/.ai/tmp"

d = json.load(open(f"{TMP}/lidl_v4_flyer_sample.json", encoding="utf-8"))

def describe(o, path="$", depth=0, max_depth=4):
    if depth > max_depth: return
    if isinstance(o, dict):
        print(f"{path} dict keys={list(o.keys())[:15]}")
        for k, v in list(o.items())[:12]:
            describe(v, f"{path}.{k}", depth+1, max_depth)
    elif isinstance(o, list):
        print(f"{path} list len={len(o)}")
        if o:
            describe(o[0], f"{path}[0]", depth+1, max_depth)
    else:
        s = repr(o)[:100]
        print(f"{path} {type(o).__name__}: {s}")

describe(d, max_depth=3)
print()
print("=== Top-level preview ===")
for k, v in d.items() if isinstance(d, dict) else []:
    if isinstance(v, list):
        print(f"  {k}: list[{len(v)}]")
    elif isinstance(v, dict):
        print(f"  {k}: dict keys={list(v.keys())[:10]}")
    else:
        print(f"  {k}: {repr(v)[:120]}")

# look for products/pages specifically
for candidate in ["pages", "items", "offers", "products", "flyer", "data"]:
    if isinstance(d, dict) and candidate in d:
        v = d[candidate]
        print(f"\n=== {candidate} ===")
        if isinstance(v, list) and v:
            print(f" len={len(v)} first item keys:", list(v[0].keys())[:20] if isinstance(v[0], dict) else type(v[0]).__name__)
            print(" first item preview:", json.dumps(v[0], ensure_ascii=False)[:600])
        elif isinstance(v, dict):
            print(f" keys={list(v.keys())[:15]}")
            print(" preview:", json.dumps(v, ensure_ascii=False)[:600])

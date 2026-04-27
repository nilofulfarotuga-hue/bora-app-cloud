"""Full dump of flyer JSON — list all keys at each level."""
import json, sys
sys.stdout.reconfigure(encoding="utf-8", errors="replace")
TMP = r"c:/Users/danil/Desktop/projetosflutter/bora_app/.claude/.ai/tmp"
d = json.load(open(f"{TMP}/lidl_v4_flyer_sample.json", encoding="utf-8"))

fl = d["flyer"]
print("ALL flyer keys (", len(fl), "):")
for k in fl:
    v = fl[k]
    tp = type(v).__name__
    if isinstance(v, list):
        print(f"  {k}: list[{len(v)}]")
    elif isinstance(v, dict):
        print(f"  {k}: dict keys={list(v.keys())[:10]}")
    else:
        print(f"  {k}: {tp} = {repr(v)[:120]}")

# Look for arrays with products
for k in fl:
    v = fl[k]
    if isinstance(v, list) and v and isinstance(v[0], dict):
        print(f"\n=== flyer.{k}[0] keys ({len(v)} items total) ===")
        print(" ", list(v[0].keys())[:30])
        print(" preview:", json.dumps(v[0], ensure_ascii=False)[:800])

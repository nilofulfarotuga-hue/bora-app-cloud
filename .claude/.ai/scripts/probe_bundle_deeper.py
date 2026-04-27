"""Find API_VERSION, baseURL setup, and the list-products-per-page endpoint."""
import re, sys
sys.stdout.reconfigure(encoding="utf-8", errors="replace")
TMP = r"c:/Users/danil/Desktop/projetosflutter/bora_app/.claude/.ai/tmp"
t = open(f"{TMP}/lidl_leaflet_bundle.js", encoding="utf-8").read()

def ctx(term, around=200, limit=4):
    out = []
    for m in re.finditer(re.escape(term), t):
        snip = t[max(0, m.start()-around):m.end()+around]
        if snip not in out: out.append(snip)
        if len(out) >= limit: break
    return out

for q in ["VITE_API_VERSION", "VITE_API_VERSION:", "API_VERSION\":", 'Fp:"', 'Su:"', 'v"+', 'baseURL:', '"v1"', '"v2"', '"v3"']:
    print(f"=== {q} ===")
    for s in ctx(q, 120, 3):
        print("---", s)
    print()

# Search for `${Fp}/${Su}` exact pattern and get surrounding function
print("=== ${Fp}/${Su} templates ===")
for m in re.finditer(r'\$\{Fp\}[^`]{0,80}', t):
    s = t[max(0, m.start()-120):m.end()+200]
    print("---", s)

# Search for "flyer" as URL path
print("\n=== URL paths with 'flyer' or 'pages' ===")
paths = re.findall(r'`([^`]{0,160}?(?:flyer|pages|regions|warehouses|stores)[^`]{0,80})`', t)
for p in sorted(set(paths))[:20]:
    print(" ", p)

# Any `v1/` or `v2/` or similar literal
print("\n=== literal v1/ v2/ v3/ v4/ ===")
for ver in ["v1/", "v2/", "v3/", "v4/", "v5/"]:
    hits = re.findall(rf'[`"](/{ver}[^`"]{{0,120}})[`"]', t)
    for h in sorted(set(hits))[:10]:
        print(" ", h)

# Endpoint "Su" value — should be in env object
print("\n=== VITE env defaults (near BASE_URL) ===")
m = re.search(r'VITE_BASE[^}]{0,1500}', t)
if m: print(m.group(0)[:1800])

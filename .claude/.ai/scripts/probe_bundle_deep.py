"""Find the exact fetch/axios call signatures in the bundle."""
import re, sys
sys.stdout.reconfigure(encoding="utf-8", errors="replace")
TMP = r"c:/Users/danil/Desktop/projetosflutter/bora_app/.claude/.ai/tmp"
t = open(f"{TMP}/lidl_leaflet_bundle.js", encoding="utf-8").read()

def ctx(term, around=200, limit=3):
    out = []
    for m in re.finditer(re.escape(term), t):
        snip = t[max(0, m.start()-around):m.end()+around]
        if snip not in out: out.append(snip)
        if len(out) >= limit: break
    return out

print("=== 'view/flyer/page' contexts ===")
for s in ctx("view/flyer/page", 250, 5):
    print("---")
    print(s)

print("\n=== 'productService' contexts ===")
for s in ctx("productService", 200, 4):
    print("---")
    print(s)

print("\n=== 'productsForOverviewDisplay' contexts ===")
for s in ctx("productsForOverviewDisplay", 200, 4):
    print("---")
    print(s)

print("\n=== 'VITE_API_URL' usage ===")
for s in ctx("VITE_API_URL", 150, 4):
    print("---")
    print(s)

# Look for "country" or "HHZ" literal strings
print("\n=== 'HHZ' contexts ===")
for s in ctx("HHZ", 200, 4):
    print("---")
    print(s)

# Try also "detail/" URL template
print("\n=== 'detail/' URL template contexts ===")
for s in ctx("/detail/", 200, 3):
    print("---")
    print(s)

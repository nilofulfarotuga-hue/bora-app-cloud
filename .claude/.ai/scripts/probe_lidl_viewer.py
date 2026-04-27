"""Probe a single flyer viewer page — extract API calls / product data embed."""
import json, os, re, sys, time
import requests

sys.stdout.reconfigure(encoding="utf-8", errors="replace")

TMP = r"c:/Users/danil/Desktop/projetosflutter/bora_app/.claude/.ai/tmp"
UA = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0 Safari/537.36"
HDR = {"User-Agent": UA, "Accept-Language": "pt-PT,pt;q=0.9"}

s = requests.Session(); s.headers.update(HDR)
s.get("https://www.lidl.pt/", timeout=20); time.sleep(2)
s.get("https://www.lidl.pt/c/folhetos/s10020672", timeout=20); time.sleep(2)

url = "https://www.lidl.pt/l/pt/folhetos/promocoes-a-partir-de-20-04/ar/0?lf=HHZ"
print("GET", url)
r = s.get(url, timeout=30)
print(" status", r.status_code, "len", len(r.text), "ctype", r.headers.get("content-type"))
print(" final_url", r.url)

out_html = f"{TMP}/lidl_viewer_promocoes.html"
open(out_html, "w", encoding="utf-8").write(r.text)
print(" saved", out_html)

t = r.text

report = {
    "status": r.status_code,
    "len": len(t),
    "final_url": str(r.url),
    "markers": {},
    "hosts_in_html": [],
    "api_like_paths": [],
    "uuids_in_html": [],
    "pdf_links": [],
    "script_srcs": [],
    "canonical": None,
    "leaflet_blob": None,
}

# markers
for k in ["__NUXT_DATA__", "__NEXT_DATA__", "window.__LEAFLET", "window.__FLYER",
          "window.__INITIAL_STATE__", "leaflets.schwarz", "marmalade", "publitas",
          "ipaper", "issuu", "flippaper", ".pdf", "page-01", "page-02", "offer",
          "Product", "\"price\"", "discountPrice", "originalPrice", "promotion"]:
    c = t.count(k)
    if c: report["markers"][k] = c

# Hosts
hosts = sorted(set(re.findall(r'https?://([a-z0-9.\-]+)', t)))
report["hosts_in_html"] = [h for h in hosts if "leaflet" in h or "schwarz" in h or "lidl" in h][:20]

# API paths
api_paths = sorted(set(re.findall(r'"(/(?:q|l|api|v\d+)/[^"?#]+)"', t)))
report["api_like_paths"] = api_paths[:30]

# UUIDs
report["uuids_in_html"] = sorted(set(re.findall(r'[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}', t)))[:10]

# PDF
report["pdf_links"] = sorted(set(re.findall(r'https?://[^\s"<>]+\.pdf[^\s"<>]*', t)))[:10]

# Script srcs
report["script_srcs"] = sorted(set(re.findall(r'<script[^>]+src="([^"]+)"', t)))[:20]

m = re.search(r'<link[^>]+rel="canonical"[^>]+href="([^"]+)"', t)
if m: report["canonical"] = m.group(1)

# Look for a JSON data island (data-page, data-leaflet, etc.)
island = re.search(r'<(?:div|script)[^>]*data-(?:page|leaflet|flyer)[^=]*="([^"]{40,400})"', t)
if island: report["leaflet_blob"] = island.group(1)[:400]

# Find any script with inline JSON containing 'pageImage' or 'offerProducts'
inline_hits = []
for m in re.finditer(r'<script[^>]*>([^<]{200,})</script>', t):
    s_ = m.group(1)
    if any(k in s_ for k in ["pageImage", "offerProducts", "leafletId", "flyerId", "pages\":[",
                             "prices\":", "\"price\"", "\"promotion\"", "\"product\""]):
        inline_hits.append(s_[:300])
    if len(inline_hits) >= 5: break
report["inline_script_json_snippets"] = inline_hits

# Try to find url patterns like /api/leaflets/<uuid>/products
api_hints_deep = sorted(set(re.findall(r'(?:esi|api|endpoints)\.leaflets\.schwarz[^"\s<>]{0,80}', t)))
report["api_hints_deep"] = api_hints_deep[:20]

with open(f"{TMP}/lidl_viewer_report.json", "w", encoding="utf-8") as f:
    json.dump(report, f, ensure_ascii=False, indent=2)

print(json.dumps(report, ensure_ascii=False, indent=2)[:4500])

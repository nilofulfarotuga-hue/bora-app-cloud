"""Deep probe: extract flyer URLs, NUXT_DATA flyer info, and inner folheto links."""
import json, os, re, sys, time
import requests
sys.stdout.reconfigure(encoding="utf-8", errors="replace")

TMP = r"c:/Users/danil/Desktop/projetosflutter/bora_app/.claude/.ai/tmp"
UA = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0 Safari/537.36"
HDR = {"User-Agent": UA, "Accept-Language": "pt-PT,pt;q=0.9"}

t = open(f"{TMP}/lidl_folheto_main.html", encoding="utf-8").read()

report = {}

# All inner links
inner_links = sorted(set(re.findall(r'href="(/[hcpb]/[^"?#]+)"', t)))
folheto_links = [l for l in inner_links if "folheto" in l.lower() or "/b/" in l or "flyer" in l.lower()]
report["folheto_inner_links"] = folheto_links[:30]

# JPG / image URLs
jpgs = sorted(set(re.findall(r'https?://[^\s"<>]+\.(?:jpg|jpeg|png)(?:\?[^\s"<>]*)?', t)))
report["all_image_urls"] = [u for u in jpgs if "folheto" in u.lower() or "flyer" in u.lower() or "leaflet" in u.lower()][:20]
report["image_urls_by_host"] = {}
for u in jpgs:
    h = u.split("/")[2] if "://" in u else "?"
    report["image_urls_by_host"].setdefault(h, []).append(u[:120])
# Cap each host
report["image_urls_by_host"] = {h: v[:3] for h, v in report["image_urls_by_host"].items()}

# NUXT blob analysis (may be absent)
nuxt_path = f"{TMP}/lidl_folheto_nuxt.json"
if os.path.exists(nuxt_path):
    blob = open(nuxt_path, encoding="utf-8").read()
    data = json.loads(blob)
    hits = []
    for i, el in enumerate(data):
        if isinstance(el, str) and any(k in el.lower() for k in ["flyer", "folheto", "leaflet", "epaper", "brochure", ".pdf"]):
            hits.append((i, el[:200]))
        elif isinstance(el, dict):
            for k in el.keys():
                if any(term in k.lower() for term in ["flyer", "folheto", "leaflet", "epaper", "brochure"]):
                    hits.append((i, f"dict_key={k}: {list(el)[:5]}"))
                    break
    report["nuxt_flyer_hits"] = hits[:40]
else:
    report["nuxt_flyer_hits"] = "NO_NUXT_DATA_IN_HTML"

# Context around 'flyer' in HTML
flyer_ctx = []
for m in re.finditer(r'flyer', t, flags=re.I):
    s = t[max(0, m.start() - 80):m.end() + 120]
    if s not in flyer_ctx and len(flyer_ctx) < 12:
        flyer_ctx.append(s)
report["flyer_ctx_samples"] = flyer_ctx

# Context around 'folheto' (PT label)
folheto_ctx = []
for m in re.finditer(r'folheto', t, flags=re.I):
    s = t[max(0, m.start() - 60):m.end() + 100]
    if s not in folheto_ctx and len(folheto_ctx) < 8:
        folheto_ctx.append(s)
report["folheto_ctx_samples"] = folheto_ctx

# Check iframe tags (src may be data-src lazy loaded)
for attr in ['src', 'data-src', 'data-lazy-src', 'data-original']:
    m = re.findall(rf'<iframe[^>]*\b{attr}="([^"]+)"', t)
    if m: report[f"iframe_{attr}"] = m[:10]

# Look for Publitas / iPaper embed pattern
for pat in ["view.publitas.com", "e.issuu.com", "ipaper.io", "readly.com", "navidoc", "marmalade.", "view.mar"]:
    if pat in t:
        idx = t.find(pat)
        report[f"embed_{pat}"] = t[max(0, idx - 100):idx + 300]

with open(f"{TMP}/lidl_folheto_deep.json", "w", encoding="utf-8") as f:
    json.dump(report, f, ensure_ascii=False, indent=2)

print(json.dumps(report, ensure_ascii=False, indent=2)[:5000])

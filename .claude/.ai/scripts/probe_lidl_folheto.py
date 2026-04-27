"""Fase 0 — Probe folheto Lidl PT. Identifica viewer / PDF / API / SPA.
Output: .claude/.ai/tmp/lidl_folheto_probe.json + HTML dumps for manual inspection."""
import json, time, os, re
import requests

TMP = r"c:/Users/danil/Desktop/projetosflutter/bora_app/.claude/.ai/tmp"
os.makedirs(TMP, exist_ok=True)

UA = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0 Safari/537.36"
HDR = {"User-Agent": UA, "Accept-Language": "pt-PT,pt;q=0.9", "Accept-Encoding": "gzip, deflate"}

s = requests.Session()
s.headers.update(HDR)

report = {}

def log(*a): print(*a, flush=True)

# Seed cookies
log("GET home")
r = s.get("https://www.lidl.pt/", timeout=30)
log(" ", r.status_code, "cookies:", list(s.cookies.keys()))
time.sleep(3)

# 1. Main folhetos page
log("GET /c/folhetos/s10020672")
r = s.get("https://www.lidl.pt/c/folhetos/s10020672", timeout=30)
log(" ", r.status_code, "len", len(r.text))
t = r.text
open(f"{TMP}/lidl_folheto_main.html", "w", encoding="utf-8").write(t)
report["folhetos_main"] = {"status": r.status_code, "len": len(t), "final_url": str(r.url)}

# Look for key markers
markers = {}
for k in [
    "__NUXT_DATA__", "__NEXT_DATA__", "iframe", "src=\".*\\.pdf",
    "publitas", "ipaper", "issuu", "readly", "flippaper", "flipbook",
    "brochure", "leaflet", "folheto", "flyer",
    "kioskversion", "kiosk", "ePaper", "e-paper", "epaper",
    "marmalade", "advertisement-preview", "cloudfront",
    "/q/api/brochure", "/q/api/leaflet", "/q/api/flyer", "/q/api/kiosk",
    "/q/api/publication", "/q/api/advertisement",
]:
    markers[k] = t.count(k) if "\\" not in k else len(re.findall(k, t))
report["markers"] = {k: v for k, v in markers.items() if v > 0}

# Extract all /h/ or /c/ links inside (sub-folheto pages)
inner_links = sorted(set(re.findall(r'href="(/[hcp]/[^"?#]+)"', t)))
report["inner_links_sample"] = inner_links[:40]
report["inner_links_count"] = len(inner_links)

# Extract all URLs ending in .pdf / .jpg / .png pointing to CDN
pdf_links = sorted(set(re.findall(r'https?://[^\s"<>]+\.pdf', t)))
jpg_links = sorted(set(re.findall(r'https?://[^\s"<>]+\.(?:jpg|jpeg|png)(?:\?[^\s"<>]*)?', t)))
report["pdf_links"] = pdf_links[:10]
report["jpg_links_count"] = len(jpg_links)

# iframes
iframes = re.findall(r'<iframe[^>]+src="([^"]+)"', t)
report["iframes"] = iframes[:10]

# Look for NUXT blob product links
m = re.search(r'<script[^>]*id="__NUXT_DATA__"[^>]*>(.*?)</script>', t, flags=re.S)
if m:
    blob = m.group(1).strip()
    open(f"{TMP}/lidl_folheto_nuxt.json", "w", encoding="utf-8").write(blob)
    report["nuxt_data_len"] = len(blob)
    # Scan for flyer-related keys
    flyer_terms = []
    for term in ["folheto", "brochure", "leaflet", "flyer", "ePaper", "publication", "campaign", "offer"]:
        if term.lower() in blob.lower():
            flyer_terms.append(term)
    report["nuxt_flyer_terms"] = flyer_terms

time.sleep(3)

# 2. Probe /q/api/ variants
api_hdr = {"Accept": "application/json, text/plain, */*", "X-Requested-With": "XMLHttpRequest",
           "Referer": "https://www.lidl.pt/c/folhetos/s10020672"}
variants = [
    "/q/api/brochure?assortment=PT&locale=pt_PT",
    "/q/api/leaflet?assortment=PT&locale=pt_PT",
    "/q/api/flyer?assortment=PT&locale=pt_PT",
    "/q/api/publication?assortment=PT&locale=pt_PT",
    "/q/api/advertisement?assortment=PT&locale=pt_PT",
    "/q/api/campaign?assortment=PT&locale=pt_PT",
    "/q/api/kiosk?assortment=PT&locale=pt_PT",
    "/q/api/offers?assortment=PT&locale=pt_PT",
    "/q/api/category/c/folhetos/s10020672?assortment=PT&locale=pt_PT&version=v2.0.0",
]
report["api_probes"] = {}
for v in variants:
    try:
        r = s.get("https://www.lidl.pt" + v, headers=api_hdr, timeout=15)
        report["api_probes"][v] = {"status": r.status_code, "len": len(r.text),
                                   "ctype": r.headers.get("content-type", "")[:60],
                                   "body0": r.text[:180] if r.status_code < 500 else None}
    except Exception as e:
        report["api_probes"][v] = {"err": str(e)[:80]}
    time.sleep(2)

# 3. Check marmalade-game endpoint (common flyer CDN used by Lidl group)
# and check for common Lidl Group "Schwarz" endpoints
schwarz_variants = [
    "https://endpoints.leaflets.lidl/api/v1/offers?country=PT",
    "https://endpoints.leaflets.lidl/v1/stores/PT/leaflets",
    "https://leaflets.lidl.com/pt/PT/leaflets",
]
report["schwarz_probes"] = {}
for u in schwarz_variants:
    try:
        r = s.get(u, headers=api_hdr, timeout=15)
        report["schwarz_probes"][u] = {"status": r.status_code, "len": len(r.text), "body0": r.text[:180]}
    except Exception as e:
        report["schwarz_probes"][u] = {"err": str(e)[:80]}
    time.sleep(2)

# Write report
with open(f"{TMP}/lidl_folheto_probe.json", "w", encoding="utf-8") as f:
    json.dump(report, f, ensure_ascii=False, indent=2)

log("\n=== REPORT ===")
log(json.dumps({k: v for k, v in report.items() if k not in ("inner_links_sample",)}, ensure_ascii=False, indent=2)[:3000])
log(f"\nSaved: {TMP}/lidl_folheto_probe.json")
log(f"Saved HTML: {TMP}/lidl_folheto_main.html")

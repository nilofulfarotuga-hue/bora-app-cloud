"""Stage 2 probe: extract leaflet UUIDs from hub, find anchor hrefs, probe Schwarz leaflets API."""
import json, os, re, sys, time
import requests

sys.stdout.reconfigure(encoding="utf-8", errors="replace")

TMP = r"c:/Users/danil/Desktop/projetosflutter/bora_app/.claude/.ai/tmp"
UA = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0 Safari/537.36"
HDR = {"User-Agent": UA, "Accept-Language": "pt-PT,pt;q=0.9"}
API_HDR = {**HDR, "Accept": "application/json, text/plain, */*",
           "X-Requested-With": "XMLHttpRequest", "Referer": "https://www.lidl.pt/c/folhetos/s10020672"}

t = open(f"{TMP}/lidl_folheto_main.html", encoding="utf-8").read()

report = {}

# Extract UUIDs from imgproxy leaflets URLs (base64-decoded path has the UUID)
import base64
uuids = set()
for m in re.finditer(r'imgproxy\.leaflets\.schwarz/[^/]+/[^/]+/[^/]+/([A-Za-z0-9_-]+)\.jpg', t):
    try:
        raw = m.group(1)
        pad = raw + "=" * ((4 - len(raw) % 4) % 4)
        decoded = base64.urlsafe_b64decode(pad).decode("utf-8", "ignore")
        # Look for uuid pattern
        um = re.search(r'[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}', decoded)
        if um: uuids.add(um.group(0))
    except Exception: pass
report["flyer_uuids"] = sorted(uuids)

# Look for anchor/card structure around each thumbnail
# Find nearest <a> before each imgproxy.leaflets.schwarz occurrence
href_near_leaflet = []
for m in re.finditer(r'imgproxy\.leaflets\.schwarz', t):
    segment = t[max(0, m.start()-1500):m.start()]
    # find LAST href in segment
    hrefs = re.findall(r'href="([^"]+)"', segment)
    data_attrs = re.findall(r'data-[a-z\-]+="[^"]*leaflet[^"]*"', segment)
    if hrefs or data_attrs:
        href_near_leaflet.append({"last_href": hrefs[-1] if hrefs else None, "data_attrs": data_attrs[-3:]})
    if len(href_near_leaflet) >= 8: break
report["href_near_leaflet_tiles"] = href_near_leaflet

# Look for any 'leaflets.schwarz' HOSTS mentioned
hosts = sorted(set(re.findall(r'https?://[a-z0-9.\-]*leaflets\.[a-z]+', t)))
report["leaflets_hosts_in_html"] = hosts[:10]

# Extract <a ... class*="flyer"> pattern or card anchor
cards = re.findall(r'<a[^>]+href="([^"]+)"[^>]*>[\s\S]{0,1200}?imgproxy\.leaflets\.schwarz', t)
report["anchor_hrefs_around_leaflet_tiles"] = list(dict.fromkeys(cards))[:10]

# --- API probing ---
endpoints = [
    "https://endpoints.leaflets.schwarz/v1/",
    "https://api.leaflets.schwarz/",
    "https://leaflets.schwarz/",
    "https://endpoints.leaflets.schwarz/v1/stores/PT/leaflets",
    "https://endpoints.leaflets.schwarz/api/v1/leaflets?country=PT",
    "https://endpoints.leaflets.schwarz/api/v1/pages",
    "https://leaflets.schwarz/api/leaflets/PT",
    "https://prospekt.leaflets.schwarz/",
    "https://prospekt.leaflets.schwarz/api/leaflets/PT",
    "https://www.lidl.pt/leaflets/",
    "https://www.lidl.pt/static/leaflets.json",
    "https://www.lidl.pt/fragment/assets/leaflets/PT/manifest.json",
]

s = requests.Session(); s.headers.update(HDR)
s.get("https://www.lidl.pt/", timeout=20); time.sleep(2)

report["api_endpoints"] = {}
for u in endpoints:
    try:
        r = s.get(u, headers=API_HDR, timeout=15)
        report["api_endpoints"][u] = {
            "status": r.status_code,
            "len": len(r.text),
            "ctype": r.headers.get("content-type", "")[:70],
            "body0": r.text[:250].replace("\n", " ") if r.status_code < 500 else None,
        }
    except Exception as e:
        report["api_endpoints"][u] = {"err": type(e).__name__ + ":" + str(e)[:80]}
    time.sleep(1.5)

# If we have a UUID, probe per-UUID endpoints
if uuids:
    u_sample = sorted(uuids)[0]
    for pat in [
        f"https://endpoints.leaflets.schwarz/v1/leaflets/{u_sample}",
        f"https://endpoints.leaflets.schwarz/v1/leaflets/{u_sample}/pages",
        f"https://endpoints.leaflets.schwarz/v1/leaflets/{u_sample}/products",
        f"https://endpoints.leaflets.schwarz/v1/leaflets/{u_sample}/offers",
        f"https://api.leaflets.schwarz/v1/leaflets/{u_sample}",
        f"https://leaflets.schwarz/api/leaflets/{u_sample}",
    ]:
        try:
            r = s.get(pat, headers=API_HDR, timeout=15)
            report["api_endpoints"][pat] = {
                "status": r.status_code, "len": len(r.text),
                "ctype": r.headers.get("content-type", "")[:70],
                "body0": r.text[:250].replace("\n", " "),
            }
        except Exception as e:
            report["api_endpoints"][pat] = {"err": type(e).__name__}
        time.sleep(1.5)

with open(f"{TMP}/lidl_folheto_schwarz.json", "w", encoding="utf-8") as f:
    json.dump(report, f, ensure_ascii=False, indent=2)

print(json.dumps(report, ensure_ascii=False, indent=2)[:5000])

"""Fase 0 — Probe intermarche.pt: home, robots, sitemap, NEXT/NUXT data, API hints."""
import json, os, re, sys, time
import requests
sys.stdout.reconfigure(encoding="utf-8", errors="replace")

TMP = r"c:/Users/danil/Desktop/projetosflutter/bora_app/.claude/.ai/tmp"
os.makedirs(TMP, exist_ok=True)
UA = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0 Safari/537.36"
HDR = {"User-Agent": UA, "Accept-Language": "pt-PT,pt;q=0.9",
       "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9"}

s = requests.Session()
s.headers.update(HDR)

report = {}
def log(*a): print(*a, flush=True)

# 1. Home
log("GET /")
r = s.get("https://www.intermarche.pt/", timeout=30, allow_redirects=True)
log(" status", r.status_code, "len", len(r.text), "final", r.url)
report["home"] = {"status": r.status_code, "len": len(r.text), "final_url": str(r.url),
                  "server": r.headers.get("server","?")[:60], "cf_ray": bool(r.headers.get("cf-ray"))}
open(f"{TMP}/im_home.html", "w", encoding="utf-8").write(r.text)
t = r.text

# Markers for SSR framework
for k in ["__NEXT_DATA__", "__NUXT_DATA__", "window.__INITIAL_STATE__", "window.__APP_STATE__",
          "_nuxt", "/_next/", "turbopack", "hydrate", "cloudflare", "Cloudflare",
          "captcha", "Just a moment", "Sucuri", "Akamai"]:
    c = t.count(k)
    if c: report.setdefault("home_markers", {})[k] = c
# price/product markers
for k in ["preço", "Preço", "€", "product", "Product", "__APOLLO", "itemprop=\"price\"", "data-price",
          "class=\"price"]:
    c = t.count(k)
    if c: report.setdefault("home_content_markers", {})[k] = c
# cookies
report["home_cookies"] = list(s.cookies.keys())
time.sleep(3)

# 2. robots.txt
log("GET /robots.txt")
r = s.get("https://www.intermarche.pt/robots.txt", timeout=30)
report["robots"] = {"status": r.status_code, "len": len(r.text)}
open(f"{TMP}/im_robots.txt", "w", encoding="utf-8").write(r.text)
if r.status_code == 200 and len(r.text) < 3000:
    report["robots_content"] = r.text[:2500]
# Extract sitemap URLs
sitemaps = re.findall(r"^Sitemap:\s*(\S+)", r.text, flags=re.M | re.I)
report["robots_sitemaps"] = sitemaps
time.sleep(3)

# 3. Sitemap
for sm in (sitemaps or ["https://www.intermarche.pt/sitemap.xml"])[:3]:
    log(f"GET {sm}")
    r = s.get(sm, timeout=30)
    rec = {"status": r.status_code, "len": len(r.text), "ctype": r.headers.get("content-type", "")[:60]}
    if r.status_code == 200:
        # if gzip
        ct = r.headers.get("content-type", "")
        if sm.endswith(".gz") or "gzip" in ct:
            import gzip
            try: text = gzip.decompress(r.content).decode("utf-8", "replace")
            except Exception: text = r.text
        else: text = r.text
        urls = re.findall(r'<loc>([^<]+)</loc>', text)
        rec["loc_count"] = len(urls)
        rec["first_locs"] = urls[:6]
    report.setdefault("sitemaps", {})[sm] = rec
    time.sleep(3)

# 4. NEXT_DATA extraction
m = re.search(r'<script[^>]*id="__NEXT_DATA__"[^>]*>(.*?)</script>', t, flags=re.S)
if m:
    blob = m.group(1).strip()
    open(f"{TMP}/im_next_data.json", "w", encoding="utf-8").write(blob)
    report["next_data_len"] = len(blob)
    try:
        d = json.loads(blob)
        report["next_data_top_keys"] = list(d.keys())[:10]
        # look for build id / api config
        if "buildId" in d: report["next_build_id"] = d["buildId"]
        if "runtimeConfig" in d: report["next_runtime"] = list(d["runtimeConfig"].keys())[:8]
    except Exception as e:
        report["next_data_parse_err"] = str(e)[:120]

# 5. Scripts / bundle urls
scripts = sorted(set(re.findall(r'<script[^>]+src="([^"]+)"', t)))
report["script_srcs_sample"] = scripts[:10]
# API hints
api_hints = sorted(set(re.findall(r'"(/(?:_next|api|graphql|v\d+)/[^"]+)"', t)))
report["api_hints_in_home"] = api_hints[:30]
# Anchor links (categorias)
cat_links = sorted(set(re.findall(r'href="(https?://www\.intermarche\.pt/[^"?#]+|/[a-z0-9][a-z0-9/\-]{2,})"', t)))
# filter to potential categories
cat_filt = [c for c in cat_links if any(k in c.lower() for k in ["categ", "talho", "padaria", "peixa",
    "mercearia", "bebida", "congela", "frutas", "legumes", "latici", "bebe", "higiene", "animais",
    "frescos", "carne", "peixe", "supermercado", "loja", "produtos", "marcas", "poupe"])]
report["home_category_links"] = cat_filt[:30]

with open(f"{TMP}/im_probe_report.json", "w", encoding="utf-8") as f:
    json.dump(report, f, ensure_ascii=False, indent=2)

log("\n=== REPORT ===")
log(json.dumps(report, ensure_ascii=False, indent=2)[:4500])

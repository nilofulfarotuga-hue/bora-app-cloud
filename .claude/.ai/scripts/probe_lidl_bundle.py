"""Fetch leaflet viewer JS bundle and extract API endpoints."""
import json, os, re, sys, time
import requests

sys.stdout.reconfigure(encoding="utf-8", errors="replace")
TMP = r"c:/Users/danil/Desktop/projetosflutter/bora_app/.claude/.ai/tmp"
UA = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0 Safari/537.36"
HDR = {"User-Agent": UA, "Accept-Language": "pt-PT,pt;q=0.9",
       "Referer": "https://www.lidl.pt/l/pt/folhetos/promocoes-a-partir-de-20-04/ar/0?lf=HHZ"}

url = "https://lidl.leaflets.schwarz/assets/index-5bff3028.js"
r = requests.get(url, headers=HDR, timeout=60)
print("bundle", r.status_code, "len", len(r.text))
open(f"{TMP}/lidl_leaflet_bundle.js", "w", encoding="utf-8").write(r.text)
t = r.text

report = {}

# Find all URL templates
url_templates = sorted(set(re.findall(r'["\`](/[a-z0-9/_\-.{}]+)["\`]', t)))
# focus on API-looking paths
api_paths = [u for u in url_templates if any(k in u for k in ["/api/", "/v1/", "/v2/", "leaflet", "flyer", "page", "product", "offer", "prospekt"]) and len(u) < 200]
report["api_paths_in_bundle"] = api_paths[:60]

# Find absolute URLs
abs_urls = sorted(set(re.findall(r'https?://[a-z0-9.\-]+[/\w.\-]+', t)))
report["abs_urls_leaflet_or_schwarz"] = [u for u in abs_urls if "leaflet" in u or "schwarz" in u][:30]

# Environment vars / config blobs
configs = re.findall(r'(VITE_[A-Z0-9_]+|[A-Z_]*(?:API|BASE|URL|ENDPOINT)_?[A-Z_]+)\s*[:=]\s*"([^"]{5,200})"', t)
report["env_configs"] = [(k, v) for k, v in configs if "http" in v or "/" in v][:30]

# Specific fetch/axios calls
fetch_calls = re.findall(r'(?:fetch|axios\.(?:get|post)|request)\s*\(\s*[\`"]([^\`"]+)[\`"]', t)
report["fetch_calls"] = sorted(set(fetch_calls))[:30]

# URL patterns with variable interpolation
template_urls = sorted(set(re.findall(r'[\`]([^`]{5,200}?\$\{[^}]+\}[^`]*?)[\`]', t)))
report["template_urls_sample"] = [x for x in template_urls if "http" in x or "/" in x][:20]

with open(f"{TMP}/lidl_bundle_report.json", "w", encoding="utf-8") as f:
    json.dump(report, f, ensure_ascii=False, indent=2)

print(json.dumps(report, ensure_ascii=False, indent=2)[:6000])

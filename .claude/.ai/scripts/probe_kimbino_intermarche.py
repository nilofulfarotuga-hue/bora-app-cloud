"""Fase 0 (redirected) — Probe kimbino.pt for Intermarche Portugal flyer(s)."""
import json, os, re, sys, time, requests
sys.stdout.reconfigure(encoding="utf-8", errors="replace")
TMP = r"c:/Users/danil/Desktop/projetosflutter/bora_app/.claude/.ai/tmp"
os.makedirs(TMP, exist_ok=True)
UA = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0 Safari/537.36"

s = requests.Session()
s.headers.update({"User-Agent": UA, "Accept-Language": "pt-PT,pt;q=0.9"})

# Check robots on kimbino too (ethics gate)
r = s.get("https://www.kimbino.pt/robots.txt", timeout=30)
report = {"kimbino_robots": {"status": r.status_code, "content": r.text[:800]}}
time.sleep(2)

# Main Intermarche folhetos page
url = "https://www.kimbino.pt/folhetos/intermarche"
r = s.get(url, timeout=30, allow_redirects=True)
t = r.text
open(f"{TMP}/kimbino_intermarche.html", "w", encoding="utf-8").write(t)
report["kimbino_main"] = {
    "status": r.status_code, "len": len(t),
    "final_url": str(r.url),
    "server": r.headers.get("server","?")[:60],
}
# Extract PDF links (kimbino hosts PDFs on cloudfront — same pattern as Lidl)
pdfs = sorted(set(re.findall(r'https?://[^\s"<>]+\.pdf', t)))
report["pdf_links"] = pdfs[:20]
# Folheto titles / validity periods
titles = re.findall(r'<h[234][^>]*>([^<]{3,120})</h[234]>', t)[:30]
report["titles_sample"] = [x.strip() for x in titles if x.strip()]
# Inner folheto detail links
detail_links = sorted(set(re.findall(r'href="(/folheto/[^"?#]+)"', t)))
report["detail_links"] = detail_links[:20]
# any dates
dates = sorted(set(re.findall(r'\d{1,2}[./-]\d{1,2}[./-]\d{4}|\d{1,2}/\d{1,2}', t)))
report["dates_sample"] = dates[:20]
# NUXT data
m = re.search(r'<script[^>]*id="__NUXT_DATA__"[^>]*>(.*?)</script>', t, flags=re.S)
if m:
    blob = m.group(1).strip()
    open(f"{TMP}/kimbino_im_nuxt.json", "w", encoding="utf-8").write(blob)
    report["nuxt_len"] = len(blob)
    # Scan blob for "intermarche" and PDF refs + prices
    inter_refs = len(re.findall(r'intermarche|Intermarché', blob, flags=re.I))
    pdf_in_nuxt = sorted(set(re.findall(r'https?://[^\s"\\]+\.pdf', blob)))
    report["nuxt_intermarche_refs"] = inter_refs
    report["nuxt_pdfs"] = pdf_in_nuxt[:8]
# hosts
hosts = sorted(set(re.findall(r'https?://([a-z0-9.\-]+)', t)))
report["hosts_sample"] = [h for h in hosts if "cloud" in h or "kimbino" in h or "intermarche" in h][:15]

with open(f"{TMP}/kimbino_im_probe.json", "w", encoding="utf-8") as f:
    json.dump(report, f, ensure_ascii=False, indent=2)

print(json.dumps(report, ensure_ascii=False, indent=2)[:3500])

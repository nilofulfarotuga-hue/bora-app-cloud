"""Quick probe: kimbino.pt and promopreco.pt for Lidl PT structured data."""
import json, sys, re, time, requests
sys.stdout.reconfigure(encoding="utf-8", errors="replace")
TMP = r"c:/Users/danil/Desktop/projetosflutter/bora_app/.claude/.ai/tmp"
UA = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0 Safari/537.36"

s = requests.Session()
s.headers.update({"User-Agent": UA, "Accept-Language": "pt-PT,pt;q=0.9"})

report = {}

# Kimbino
try:
    r = s.get("https://www.kimbino.pt/folhetos/lidl", timeout=30, allow_redirects=True)
    t = r.text
    open(f"{TMP}/kimbino_lidl.html", "w", encoding="utf-8").write(t)
    report["kimbino_main"] = {"status": r.status_code, "len": len(t), "final_url": str(r.url)}
    # markers
    report["kimbino_markers"] = {}
    for k in ["__NEXT_DATA__", "__NUXT_DATA__", "application/ld+json", ".pdf", "preco", "preço", "€",
              "leaflet", "folheto", "discount", "offer", "product"]:
        c = t.count(k)
        if c: report["kimbino_markers"][k] = c
    # find api calls
    report["kimbino_apis"] = sorted(set(re.findall(r'/api/[a-z0-9/_\-]+', t)))[:20]
    report["kimbino_pdf_links"] = sorted(set(re.findall(r'https?://[^\s"<>]+\.pdf', t)))[:5]
    report["kimbino_hosts"] = sorted(set(re.findall(r'https?://([a-z0-9.\-]+)', t)))[:20]
except Exception as e:
    report["kimbino_main"] = {"err": type(e).__name__ + ":" + str(e)[:100]}
time.sleep(3)

# Promopreco
for url in ["https://www.promopreco.pt/lidl", "https://www.promopreco.pt/supermercado/lidl", "https://www.promopreco.pt/lidl/folheto"]:
    try:
        r = s.get(url, timeout=30, allow_redirects=True)
        t = r.text
        report[f"promopreco_{url.split('/')[-1]}"] = {"status": r.status_code, "len": len(t), "final_url": str(r.url)}
        if r.status_code == 200 and len(t) > 2000:
            open(f"{TMP}/promopreco_lidl.html", "w", encoding="utf-8").write(t)
            report[f"promopreco_markers"] = {}
            for k in ["__NEXT_DATA__", ".pdf", "€", "product", "preco", "preço", "discount", "offer"]:
                c = t.count(k)
                if c: report[f"promopreco_markers"][k] = c
            break
    except Exception as e:
        report[f"promopreco_{url.split('/')[-1]}"] = {"err": type(e).__name__}
    time.sleep(3)

# ofertasportugal as extra
try:
    r = s.get("https://www.ofertasportugal.net/lidl", timeout=30, allow_redirects=True)
    report["ofertasportugal"] = {"status": r.status_code, "len": len(r.text), "final_url": str(r.url)}
    if r.status_code == 200 and len(r.text) > 2000:
        open(f"{TMP}/ofertasportugal_lidl.html", "w", encoding="utf-8").write(r.text)
except Exception as e:
    report["ofertasportugal"] = {"err": type(e).__name__}

with open(f"{TMP}/fallback_probes.json", "w", encoding="utf-8") as f:
    json.dump(report, f, ensure_ascii=False, indent=2)
print(json.dumps(report, ensure_ascii=False, indent=2))

"""Fase 0 Continente — count products via SFCC Search-Show endpoint.
Output: .claude/.ai/tmp/continente_sfcc_counts.json
"""
import json, os, re, sys, time, requests
sys.stdout.reconfigure(encoding="utf-8", errors="replace")
TMP = r"c:/Users/danil/Desktop/projetosflutter/bora_app/.claude/.ai/tmp"
os.makedirs(TMP, exist_ok=True)
UA = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0 Safari/537.36"

s = requests.Session()
s.headers.update({"User-Agent": UA, "Accept-Language": "pt-PT,pt;q=0.9",
                  "Accept": "text/html,application/xhtml+xml;q=0.9,application/json;q=0.8"})

report = {}

# 1. robots.txt
r = s.get("https://www.continente.pt/robots.txt", timeout=30)
report["robots"] = {"status": r.status_code, "content": r.text[:2000]}
time.sleep(3)

# 2. Root SFCC search for total count (no filters)
base = "https://www.continente.pt/on/demandware.store/Sites-continente-Site/pt_PT/Search-Show"
urls_to_test = [
    ("all_q_star", f"{base}?q=*&srule=best-sellers&start=0&sz=48&format=ajax"),
    ("all_q_empty", f"{base}?q=&start=0&sz=48&format=ajax"),
    ("all_newarrivals", f"{base}?srule=new-arrivals&start=0&sz=48&format=ajax"),
]
for name, url in urls_to_test:
    try:
        r = s.get(url, timeout=45)
        rec = {"status": r.status_code, "len": len(r.text), "ctype": r.headers.get("content-type", "")[:60]}
        if r.status_code == 200:
            t = r.text
            # Try to find total count markers
            # SFCC renders "X produtos encontrados" or data-producttotal or similar
            for pat in [r'data-product-total="(\d+)"', r'data-total-products="(\d+)"',
                        r'"totalCount"\s*:\s*(\d+)', r'"productCount"\s*:\s*(\d+)',
                        r'class="[^"]*result-count[^"]*"[^>]*>([^<]+)<',
                        r'class="[^"]*search-result[^"]*"[^>]*>([^<]+)<',
                        r'(\d+)\s*(?:produtos|resultados)\s*encontrados',
                        r'de\s+(\d+)\s+(?:produtos|resultados)']:
                ms = re.findall(pat, t, flags=re.I)
                if ms: rec.setdefault("count_hits", {})[pat] = ms[:3]
            # Save sample
            if name == "all_q_star":
                open(f"{TMP}/continente_sfcc_qstar.html", "w", encoding="utf-8").write(t)
            # Count product cards
            card_count = len(re.findall(r'class="[^"]*product-tile[^"]*"', t))
            rec["product_tile_count"] = card_count
            # data-pid
            pid_count = len(set(re.findall(r'data-pid="([0-9]+)"', t)))
            rec["data_pid_unique"] = pid_count
        report[f"search_{name}"] = rec
    except Exception as e:
        report[f"search_{name}"] = {"err": type(e).__name__ + ":" + str(e)[:100]}
    time.sleep(3.5)

# 3. Try categories (known SFCC paths)
categories = [
    ("mercearia",   "mercearia"),
    ("frescos",     "frescos"),
    ("bebidas",     "bebidas"),
    ("laticinios",  "laticinios-e-ovos"),
    ("congelados",  "congelados"),
    ("talho",       "talho"),
    ("peixaria",    "peixaria"),
    ("padaria",     "padaria-e-pastelaria"),
    ("frutas",      "frutas-e-legumes"),
    ("higiene",     "higiene-e-beleza"),
    ("animais",     "animais-de-estimacao"),
    ("bebe",        "bebe"),
    ("bio",         "bio-e-escolhas-alimentares"),
]
report["categories"] = {}
for name, slug in categories:
    # SFCC category-browse URL — guess based on known pattern
    url = f"{base}?cgid=col-{slug}&start=0&sz=48&format=ajax"
    try:
        r = s.get(url, timeout=45)
        rec = {"status": r.status_code, "len": len(r.text)}
        if r.status_code == 200:
            t = r.text
            for pat in [r'data-product-total="(\d+)"', r'data-total-products="(\d+)"',
                        r'(\d+)\s*(?:produtos|resultados)', r'de\s+(\d+)\s+produtos']:
                ms = re.findall(pat, t, flags=re.I)
                if ms: rec.setdefault("count_hits", {})[pat] = ms[:3]
            rec["product_tile_count"] = len(re.findall(r'class="[^"]*product-tile[^"]*"', t))
            rec["data_pid_unique"] = len(set(re.findall(r'data-pid="([0-9]+)"', t)))
        report["categories"][name] = rec
    except Exception as e:
        report["categories"][name] = {"err": type(e).__name__}
    time.sleep(3.5)

with open(f"{TMP}/continente_sfcc_counts.json", "w", encoding="utf-8") as f:
    json.dump(report, f, ensure_ascii=False, indent=2)
print(json.dumps(report, ensure_ascii=False, indent=2)[:3800])

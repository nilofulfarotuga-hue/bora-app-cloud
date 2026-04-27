"""
Fase 1.5 — re-tenta os PIDs com net_error em Fase 1.
Sleep 60s entre cada para garantir.
Output: phase1_5_retry_results.json
"""
import json, os, re, time, urllib.request, urllib.error, sys

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")

BASE = r"C:\Users\danil\Desktop\projetosflutter\bora_app\.claude\.ai"
INPUT = os.path.join(BASE, "tmp", "phase1_prices_2026-04-21.json")
OUTPUT = os.path.join(BASE, "tmp", "phase1_5_retry_results.json")

UA = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/121.0 Safari/537.36"
URL_TEMPLATE = "https://www.continente.pt/on/demandware.store/Sites-continente-Site/default/Product-Show?pid={pid}"

PRICE_PATTERNS = [
    r'"price"\s*:\s*(?:{\s*"value"\s*:\s*)?"?(\d+[.,]\d+)"?',
    r'itemprop=["\']price["\']\s+content=["\'](\d+[.,]\d+)["\']',
    r'<meta[^>]+property=["\']product:price:amount["\'][^>]+content=["\'](\d+[.,]\d+)["\']',
]

with open(INPUT, "r", encoding="utf-8") as f:
    data = json.load(f)

net_err_pids = [r["pid"] for r in data["results"] if r["status_label"] == "net_error"]
print(f"Found {len(net_err_pids)} net_error PIDs: {net_err_pids}", flush=True)

results = []
for i, pid in enumerate(net_err_pids, 1):
    url = URL_TEMPLATE.format(pid=pid)
    req = urllib.request.Request(url, headers={"User-Agent": UA, "Accept-Language": "pt-PT,pt;q=0.9"})
    t0 = time.time()
    try:
        with urllib.request.urlopen(req, timeout=30) as r:
            status = r.status
            final_url = r.geturl()
            body = r.read().decode("utf-8", errors="replace")
    except urllib.error.HTTPError as e:
        status = e.code; final_url = url; body = ""
    except Exception as e:
        status = -1; final_url = url; body = f"ERR:{e}"
    elapsed = time.time() - t0

    price = None
    if status == 200 and body:
        for p in PRICE_PATTERNS:
            m = re.search(p, body, re.IGNORECASE)
            if m:
                price = m.group(1).replace(",", ".")
                break

    label = "ok" if price else (
        "404" if status == 404 else
        ("redirect_home" if status == 200 and final_url.rstrip("/").endswith("continente.pt") else
         ("net_error" if status == -1 else f"http_{status}")))

    results.append({"pid": pid, "status": status, "label": label, "price_eur": price,
                    "final_url": final_url, "elapsed_s": round(elapsed, 2)})
    print(f"[{i}/{len(net_err_pids)}] pid={pid} status={label} price={price}", flush=True)

    if i < len(net_err_pids):
        time.sleep(60)

with open(OUTPUT, "w", encoding="utf-8") as f:
    json.dump({"results": results}, f, ensure_ascii=False, indent=2)

ok = sum(1 for r in results if r["price_eur"])
print(f"\nDONE. {ok}/{len(results)} now have price. Output: {OUTPUT}", flush=True)

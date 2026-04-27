"""
Phase 0 — dry-run 50 produtos Continente via PID (method M3).
Input:  .claude/.ai/tmp/phase0_products_2026-04-21.json
Output: .claude/.ai/tmp/phase0_prices_2026-04-21.json (checkpoint a cada produto)
Rate:   4.5s +/- 1.0s jitter.
Stop:   primeiro 429/403, ou 3 falhas consecutivas.
ZERO writes na BD.
"""
import json, sys, re, time, random, os, io
import urllib.request, urllib.error

BASE = r"C:\Users\danil\Desktop\projetosflutter\bora_app\.claude\.ai"
INPUT  = os.path.join(BASE, "tmp", "phase0_products_2026-04-21.json")
OUTPUT = os.path.join(BASE, "tmp", "phase0_prices_2026-04-21.json")

UA = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/121.0 Safari/537.36"
URL_TEMPLATE = "https://www.continente.pt/on/demandware.store/Sites-continente-Site/default/Product-Show?pid={pid}"

PRICE_PATTERNS = [
    r'"price"\s*:\s*(?:{\s*"value"\s*:\s*)?"?(\d+[.,]\d+)"?',
    r'itemprop=["\']price["\']\s+content=["\'](\d+[.,]\d+)["\']',
    r'<meta[^>]+property=["\']product:price:amount["\'][^>]+content=["\'](\d+[.,]\d+)["\']',
    r'data-price\s*=\s*"(\d+[.,]\d+)"',
    r'class="[^"]*ct-price-formatted[^"]*"[^>]*>\s*(\d+[.,]\d+)\s*€',
]

def fetch(url):
    req = urllib.request.Request(url, headers={"User-Agent": UA, "Accept-Language": "pt-PT,pt;q=0.9"})
    try:
        with urllib.request.urlopen(req, timeout=20) as r:
            return r.status, r.geturl(), r.read().decode("utf-8", errors="replace")
    except urllib.error.HTTPError as e:
        return e.code, url, ""
    except Exception as e:
        return -1, url, f"ERR:{e}"

def extract_price(html):
    for p in PRICE_PATTERNS:
        m = re.search(p, html, re.IGNORECASE)
        if m:
            return m.group(1).replace(",", ".")
    return None

def main():
    with open(INPUT, "r", encoding="utf-8") as f:
        products = json.load(f)

    results = []
    consecutive_failures = 0
    stopped_reason = None

    sys.stdout.reconfigure(encoding="utf-8") if hasattr(sys.stdout, "reconfigure") else None

    for i, p in enumerate(products, 1):
        url = URL_TEMPLATE.format(pid=p["pid"])
        t0 = time.time()
        status, final_url, body = fetch(url)
        elapsed = time.time() - t0

        price = None
        status_label = "ok"
        if status == 200 and body:
            price = extract_price(body)
            if price is None:
                status_label = "no_price_in_html"
                consecutive_failures += 1
            else:
                consecutive_failures = 0
        elif status in (404,):
            status_label = "404"
            consecutive_failures = 0  # 404 = product gone, not a block
        elif status in (429, 403):
            status_label = f"BLOCKED_{status}"
            stopped_reason = f"HTTP {status} on item {i}"
        elif status == -1:
            status_label = "net_error"
            consecutive_failures += 1
        else:
            status_label = f"http_{status}"
            consecutive_failures += 1

        results.append({
            "idx": i,
            "id": p["id"],
            "pid": p["pid"],
            "name": p["name"],
            "status": status,
            "status_label": status_label,
            "final_url": final_url,
            "price_eur": price,
            "elapsed_s": round(elapsed, 2),
        })

        # Checkpoint
        with open(OUTPUT, "w", encoding="utf-8") as f:
            json.dump({
                "products_processed": i,
                "total": len(products),
                "stopped_reason": stopped_reason,
                "results": results,
            }, f, ensure_ascii=False, indent=2)

        print(f"[{i:02d}/{len(products)}] pid={p['pid']} status={status_label} price={price} ({elapsed:.1f}s)", flush=True)

        if stopped_reason:
            break
        if consecutive_failures >= 3:
            stopped_reason = f"3 falhas consecutivas no item {i}"
            break

        if i < len(products):
            sleep_s = 4.5 + random.uniform(-1.0, 1.0)
            time.sleep(max(1.0, sleep_s))

    print(f"\nDONE. processed={len(results)} stopped_reason={stopped_reason}")
    print(f"Output: {OUTPUT}")

if __name__ == "__main__":
    main()

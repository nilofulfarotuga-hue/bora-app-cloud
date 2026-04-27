"""
Phase 1 — scrape ALL ~2.844 produtos Continente sem preço.
- Fetch lista de PIDs via Supabase REST (anon key, read-only).
- Scrape continente.pt Product-Show?pid=<PID>.
- Rate: 4.5s +/- 1.0s jitter.
- Checkpoint a cada 200 produtos (resume-safe).
- Stop em 429/403 OU 5 falhas consecutivas.
- ZERO writes na BD.
"""
import json, sys, re, time, random, os
import urllib.request, urllib.parse, urllib.error

BASE = r"C:\Users\danil\Desktop\projetosflutter\bora_app\.claude\.ai"
OUTPUT = os.path.join(BASE, "tmp", "phase1_prices_2026-04-21.json")
PIDS_CACHE = os.path.join(BASE, "tmp", "phase1_pids_2026-04-21.txt")

SUPABASE_URL = "https://ojykpzwqrtusfeakzrna.supabase.co"
ANON_KEY = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im9qeWtwendxcnR1c2ZlYWt6cm5hIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzMwMDA3MjgsImV4cCI6MjA4ODU3NjcyOH0.-yrhHFZV4bfjBagI5W-c1AvmP8Xkzs1kf2xuxPwdBh4"

UA = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/121.0 Safari/537.36"
URL_TEMPLATE = "https://www.continente.pt/on/demandware.store/Sites-continente-Site/default/Product-Show?pid={pid}"

PRICE_PATTERNS = [
    r'"price"\s*:\s*(?:{\s*"value"\s*:\s*)?"?(\d+[.,]\d+)"?',
    r'itemprop=["\']price["\']\s+content=["\'](\d+[.,]\d+)["\']',
    r'<meta[^>]+property=["\']product:price:amount["\'][^>]+content=["\'](\d+[.,]\d+)["\']',
    r'data-price\s*=\s*"(\d+[.,]\d+)"',
    r'class="[^"]*ct-price-formatted[^"]*"[^>]*>\s*(\d+[.,]\d+)\s*€',
]

def fetch_pids():
    # Cache só vale se >= 2000 PIDs (bug anterior gravou só 1000).
    if os.path.exists(PIDS_CACHE):
        with open(PIDS_CACHE, "r", encoding="utf-8") as f:
            cached = [line.strip() for line in f if line.strip()]
        if len(cached) >= 2000:
            print(f"[cache] loaded {len(cached)} pids", flush=True)
            return cached
        print(f"[cache] descartado ({len(cached)} < 2000), re-fetching", flush=True)

    print("[supabase] paginated fetch...", flush=True)
    PAGE = 1000
    all_rows = []
    for offset in (0, 1000, 2000, 3000):
        qs = urllib.parse.urlencode({
            "source": "eq.glovo-continente-guarda-2026-04-21",
            "price": "is.null",
            "id": "like.glv-*",
            "select": "id",
            "order": "id.asc",
            "limit": PAGE,
            "offset": offset,
        })
        url = f"{SUPABASE_URL}/rest/v1/products?{qs}"
        req = urllib.request.Request(url, headers={
            "apikey": ANON_KEY,
            "Authorization": f"Bearer {ANON_KEY}",
            "Accept": "application/json",
        })
        with urllib.request.urlopen(req, timeout=30) as r:
            page = json.loads(r.read().decode("utf-8"))
        print(f"  offset={offset} got={len(page)}", flush=True)
        all_rows.extend(page)
        if len(page) < PAGE:
            break

    pids = []
    for row in all_rows:
        m = re.match(r"^glv-(\d+)$", row["id"])
        if m:
            pids.append(m.group(1))
    pids = sorted(set(pids))
    with open(PIDS_CACHE, "w", encoding="utf-8") as f:
        f.write("\n".join(pids))
    print(f"[supabase] cached {len(pids)} pids", flush=True)
    return pids

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

def load_checkpoint():
    if not os.path.exists(OUTPUT):
        return {}, set()
    try:
        with open(OUTPUT, "r", encoding="utf-8") as f:
            data = json.load(f)
        results = data.get("results", [])
        done = {r["pid"] for r in results}
        return {r["pid"]: r for r in results}, done
    except Exception:
        return {}, set()

def save_checkpoint(results_map, total, stopped_reason=None):
    results = list(results_map.values())
    results.sort(key=lambda r: r["idx"])
    with open(OUTPUT, "w", encoding="utf-8") as f:
        json.dump({
            "products_processed": len(results),
            "total": total,
            "stopped_reason": stopped_reason,
            "results": results,
        }, f, ensure_ascii=False, indent=2)

def main():
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    if hasattr(sys.stderr, "reconfigure"):
        sys.stderr.reconfigure(encoding="utf-8", errors="replace")

    pids = fetch_pids()
    total = len(pids)
    if total == 0:
        print("ERR: no PIDs", flush=True)
        sys.exit(1)

    results_map, done = load_checkpoint()
    if done:
        print(f"[resume] {len(done)} já processados, retomando", flush=True)

    consecutive_failures = 0
    stopped_reason = None
    t_start = time.time()

    for i, pid in enumerate(pids, 1):
        if pid in done:
            continue

        url = URL_TEMPLATE.format(pid=pid)
        t0 = time.time()
        status, final_url, body = fetch(url)
        elapsed = time.time() - t0

        price = None
        status_label = "ok"
        # consecutive_failures só conta erros DE INFRA (rede/5xx/bloqueio).
        # 404, redirect_home, no_price_in_html = produtos descontinuados, NÃO contam.
        if status == 200 and body:
            price = extract_price(body)
            if price is None:
                if final_url.rstrip("/").endswith("continente.pt"):
                    status_label = "redirect_home"
                else:
                    status_label = "no_price_in_html"
            consecutive_failures = 0
        elif status == 404:
            status_label = "404"
            consecutive_failures = 0
        elif status in (429, 403):
            status_label = f"BLOCKED_{status}"
            stopped_reason = f"HTTP {status} no item {i}"
        elif status == -1:
            status_label = "net_error"
            consecutive_failures += 1
            print(f"  net_error em pid={pid}, sleep 30s antes de continuar", flush=True)
            time.sleep(30)
        elif 500 <= status < 600:
            status_label = f"http_{status}"
            consecutive_failures += 1
        else:
            status_label = f"http_{status}"
            consecutive_failures = 0

        results_map[pid] = {
            "idx": i,
            "pid": pid,
            "status": status,
            "status_label": status_label,
            "final_url": final_url,
            "price_eur": price,
            "elapsed_s": round(elapsed, 2),
        }

        # Checkpoint a cada 200 ou em condições especiais
        if i % 200 == 0 or stopped_reason or consecutive_failures >= 10:
            save_checkpoint(results_map, total, stopped_reason)
            done_count = len(results_map)
            eta_min = ((total - done_count) * 4.5) / 60
            print(f"[ckpt] {done_count}/{total} ETA {eta_min:.0f}min", flush=True)

        # Log a cada 25 produtos para monitoring leve
        if i % 25 == 0:
            ok = sum(1 for r in results_map.values() if r["price_eur"])
            print(f"[{i:04d}/{total}] last pid={pid} status={status_label} price={price} ok_total={ok}", flush=True)

        if stopped_reason:
            break
        if consecutive_failures >= 10:
            stopped_reason = f"10 falhas consecutivas no item {i}"
            break

        # Rate limit (não dorme se já é o último)
        if i < total:
            sleep_s = 4.5 + random.uniform(-1.0, 1.0)
            time.sleep(max(1.0, sleep_s))

    save_checkpoint(results_map, total, stopped_reason)
    elapsed_total = (time.time() - t_start) / 60
    ok = sum(1 for r in results_map.values() if r["price_eur"])
    print(f"\nDONE. processed={len(results_map)}/{total} ok={ok} stopped={stopped_reason} elapsed={elapsed_total:.1f}min", flush=True)

if __name__ == "__main__":
    main()

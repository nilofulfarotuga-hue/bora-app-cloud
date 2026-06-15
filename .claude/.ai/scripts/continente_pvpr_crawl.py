"""
Continente PVPR crawler (PID-based) — read-only sobre continente.pt, ZERO writes BD.
Escreve resultados em JSON (sandbox). O carregamento JSON -> staging e a aplicacao
staging -> products sao passos SEPARADOS, so apos aprovacao do Danilo.

Regra de preco base (validada na Fase 0, gate 3/3):
  sales = JSON-LD offers.price (sempre)
  pvprs = todos "PVP Recomendado: X" / pvpr-info da pagina
   - 0 pvpr  -> sem promo -> base = sales              (status ok_no_promo)
   - 1 pvpr  -> promo     -> base = pvpr                (status ok_promo)
   - >1 pvpr -> AMBIGUO   -> base=None, needs_review    (status ambiguous_multi_pvpr)

Uso:
  python continente_pvpr_crawl.py --sample 150 --out tmp/phase0_sample150.json
  python continente_pvpr_crawl.py --all          --out tmp/continente_pvpr_full.json
"""
import urllib.request, urllib.parse, urllib.error
import os, re, json, time, random, sys, argparse, datetime

BASE = r"C:\Users\danil\Desktop\projetosflutter\bora_app\.claude\.ai"
TMP = os.path.join(BASE, "tmp")
os.makedirs(TMP, exist_ok=True)

SUPABASE_URL = "https://ojykpzwqrtusfeakzrna.supabase.co"
ANON_KEY = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im9qeWtwendxcnR1c2ZlYWt6cm5hIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzMwMDA3MjgsImV4cCI6MjA4ODU3NjcyOH0.-yrhHFZV4bfjBagI5W-c1AvmP8Xkzs1kf2xuxPwdBh4"

UA = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/121.0 Safari/537.36"
URL = "https://www.continente.pt/on/demandware.store/Sites-continente-Site/default/Product-Show?pid={pid}"
PRODUCTS_CACHE = os.path.join(TMP, "continente_all_products.json")

def fetch_products():
    if os.path.exists(PRODUCTS_CACHE):
        rows = json.load(open(PRODUCTS_CACHE, encoding="utf-8"))
        if len(rows) > 11000:
            print(f"[cache] {len(rows)} produtos continente", flush=True)
            return rows
    rows, offset = [], 0
    while True:
        qs = urllib.parse.urlencode({
            "restaurant_id": "eq.continente-guarda",
            "select": "id,name,price",
            "order": "id.asc", "limit": 1000, "offset": offset,
        })
        req = urllib.request.Request(f"{SUPABASE_URL}/rest/v1/products?{qs}",
            headers={"apikey": ANON_KEY, "Authorization": f"Bearer {ANON_KEY}", "Accept": "application/json"})
        with urllib.request.urlopen(req, timeout=30) as r:
            page = json.loads(r.read().decode("utf-8"))
        rows.extend(page)
        print(f"  [supabase] offset={offset} got={len(page)} total={len(rows)}", flush=True)
        if len(page) < 1000:
            break
        offset += 1000
    json.dump(rows, open(PRODUCTS_CACHE, "w", encoding="utf-8"), ensure_ascii=False)
    return rows

def fetch(pid):
    req = urllib.request.Request(URL.format(pid=pid),
        headers={"User-Agent": UA, "Accept-Language": "pt-PT,pt;q=0.9"})
    try:
        with urllib.request.urlopen(req, timeout=25) as r:
            return r.status, r.geturl(), r.read().decode("utf-8", errors="replace")
    except urllib.error.HTTPError as e:
        return e.code, URL.format(pid=pid), ""
    except Exception:
        return -1, URL.format(pid=pid), ""

def jsonld_price(html):
    for m in re.finditer(r'<script[^>]+type=["\']application/ld\+json["\'][^>]*>(.*?)</script>', html, re.S | re.I):
        try:
            data = json.loads(m.group(1).strip())
        except Exception:
            continue
        for it in (data if isinstance(data, list) else [data]):
            if isinstance(it, dict) and 'Product' in str(it.get('@type', '')):
                off = it.get('offers', {})
                if isinstance(off, list):
                    off = off[0] if off else {}
                p = off.get('price')
                if p is not None:
                    try:
                        return float(str(p).replace(",", "."))
                    except Exception:
                        return None
    return None

def pvpr_values(html):
    vals = set()
    for m in re.finditer(r'PVP\s*Recomendado:\s*([\d.,]+)', html, re.I):
        vals.add(round(float(m.group(1).replace(",", ".")), 2))
    for m in re.finditer(r'pvpr-info[^>]*>\s*PVPR\s*</span>\s*([\d.,]+)\s*&euro;', html, re.I):
        vals.add(round(float(m.group(1).replace(",", ".")), 2))
    return vals

def decide(http, final_url, html):
    if http == 404:        return None, None, None, "404"
    if http in (403, 429): return None, None, None, f"BLOCKED_{http}"
    if http != 200 or not html: return None, None, None, f"http_{http}"
    if "/produto/" not in final_url: return None, None, None, "redirect_home"
    sales = jsonld_price(html)
    if not sales or sales <= 0: return None, None, None, "no_price"
    pv = pvpr_values(html)
    if not pv:        return sales, False, sales, "ok_no_promo"
    if len(pv) == 1:
        base = next(iter(pv))
        if base < sales: return base, True, sales, "weird_pvpr_lt_sales"
        return base, True, sales, "ok_promo"
    return None, None, sales, "ambiguous_multi_pvpr"

def load_ckpt(out):
    if os.path.exists(out):
        try:
            data = json.load(open(out, encoding="utf-8"))
            res = {r["id"]: r for r in data.get("results", [])}
            return res
        except Exception:
            return {}
    return {}

def save_ckpt(out, res, total, stopped=None):
    json.dump({"generated_at": datetime.datetime.now().isoformat(timespec="seconds"),
               "total": total, "processed": len(res), "stopped": stopped,
               "results": list(res.values())},
              open(out, "w", encoding="utf-8"), ensure_ascii=False, indent=1)

def summarize(res):
    vals = list(res.values())
    n = len(vals)
    if n == 0:
        print("sem resultados"); return
    hit = sum(1 for r in vals if r["status"] in ("ok_no_promo", "ok_promo"))
    promo = sum(1 for r in vals if r["status"] == "ok_promo")
    s404 = sum(1 for r in vals if r["status"] == "404")
    rdir = sum(1 for r in vals if r["status"] == "redirect_home")
    ambi = sum(1 for r in vals if r["status"].startswith("ambiguous"))
    weird = sum(1 for r in vals if r["status"] == "weird_pvpr_lt_sales")
    noprice = sum(1 for r in vals if r["status"] == "no_price")
    blocked = sum(1 for r in vals if str(r["status"]).startswith("BLOCKED"))
    # divergencia base vs preco BD (glovo/1.15)
    buckets = {"<=5%": 0, "5-15%": 0, "15-25%": 0, "25-50%": 0, ">50%": 0}
    higher = lower = 0
    for r in vals:
        if r["base"] and r["bd"]:
            d = (r["base"] - r["bd"]) / r["bd"]
            ad = abs(d)
            if ad <= 0.05: buckets["<=5%"] += 1
            elif ad <= 0.15: buckets["5-15%"] += 1
            elif ad <= 0.25: buckets["15-25%"] += 1
            elif ad <= 0.50: buckets["25-50%"] += 1
            else: buckets[">50%"] += 1
            if d > 0: higher += 1
            else: lower += 1
    print("\n===== RESUMO =====")
    print(f"Total processados: {n}")
    print(f"OK (PID resolve c/ preco): {hit}/{n} ({100*hit/n:.1f}%)  [promo={promo}, sem_promo={hit-promo}]")
    print(f"404={s404} redirect_home={rdir} no_price={noprice} ambiguo={ambi} weird={weird} BLOCKED={blocked}")
    print(f"Divergencia base vs BD(glovo/1.15): {buckets}")
    print(f"  base MAIOR que BD: {higher} | base MENOR que BD: {lower}")

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--sample", type=int, default=0)
    ap.add_argument("--all", action="store_true")
    ap.add_argument("--out", required=True)
    ap.add_argument("--seed", type=int, default=42)
    ap.add_argument("--shards", type=int, default=1)
    ap.add_argument("--shard", type=int, default=0)
    ap.add_argument("--sleep", type=float, default=4.5)
    args = ap.parse_args()
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    # Impede o Windows de suspender durante a corrida (reverte ao terminar o processo).
    # ES_CONTINUOUS | ES_SYSTEM_REQUIRED — mantem o sistema acordado, deixa o ecra apagar.
    try:
        import ctypes
        ctypes.windll.kernel32.SetThreadExecutionState(0x80000000 | 0x00000001)
    except Exception:
        pass
    out = args.out if os.path.isabs(args.out) else os.path.join(BASE, args.out)

    products = fetch_products()
    if args.sample:
        random.seed(args.seed)
        products = random.sample(products, min(args.sample, len(products)))
    if args.shards > 1:
        products = [p for i, p in enumerate(products) if i % args.shards == args.shard]
    total = len(products)
    print(f"[run] alvo={total} produtos (shard {args.shard}/{args.shards}) out={out}", flush=True)

    res = load_ckpt(out)
    if res:
        print(f"[resume] {len(res)} ja feitos", flush=True)
    consec = 0; stopped = None; t0 = time.time()
    for i, p in enumerate(products, 1):
        pid_num = re.sub(r"^(cont|cnt)-", "", p["id"])
        if p["id"] in res:
            continue
        http, final, html = fetch(pid_num)
        base, promo, sales, status = decide(http, final, html)
        res[p["id"]] = {"id": p["id"], "pid": pid_num, "name": p.get("name"),
                        "bd": float(p["price"]) if p.get("price") is not None else None,
                        "http": http, "status": status, "base": base,
                        "sales": sales, "had_promo": promo}
        if str(status).startswith("BLOCKED"):
            stopped = f"{status} @ {i}"; save_ckpt(out, res, total, stopped); break
        if status in ("net_error",) or status.startswith("http_5"):
            consec += 1
            if consec >= 8:
                stopped = f"8 falhas infra @ {i}"; save_ckpt(out, res, total, stopped); break
        else:
            consec = 0
        if i % 20 == 0:
            save_ckpt(out, res, total)
            ok = sum(1 for r in res.values() if r["status"] in ("ok_no_promo", "ok_promo"))
            eta = (total - len(res)) * 5.5 / 60
            print(f"[{i}/{total}] ok={ok} last={status} ETA~{eta:.0f}min", flush=True)
        if i < total:
            time.sleep(max(0.8, args.sleep + random.uniform(-1.0, 1.0)))
    save_ckpt(out, res, total, stopped)
    print(f"\nDONE processed={len(res)}/{total} stopped={stopped} elapsed={(time.time()-t0)/60:.1f}min", flush=True)
    summarize(res)

if __name__ == "__main__":
    main()

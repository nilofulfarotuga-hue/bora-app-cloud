"""
Carrega o JSON da corrida PVPR -> tabela continente_price_staging (via service_role REST).
NÃO toca em products (isso é a RPC admin_continente_apply_prices, chamada no painel).
Corre DEPOIS da corrida completa terminar.

  python continente_load_staging.py
"""
import urllib.request, urllib.error, os, json, sys

BASE = r"C:\Users\danil\Desktop\projetosflutter\bora_app\.claude\.ai"
TMP = os.path.join(BASE, "tmp")
ENV = r"C:\Users\danil\Desktop\projetosflutter\bora_app\scripts\scraper\.env"
FULL_JSON = os.path.join(TMP, "continente_pvpr_full.json")
SRC = "continente_pt_official_2026-06-14"
OK = {"ok_no_promo", "ok_promo"}

def load_env():
    env = {}
    for line in open(ENV, encoding="utf-8"):
        line = line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        k, v = line.split("=", 1)
        env[k.strip()] = v.strip()
    return env

ENVV = load_env()
URL = ENVV["SUPABASE_URL"]
KEY = ENVV.get("SUPABASE_SERVICE_KEY") or ENVV.get("SUPABASE_SERVICE_ROLE_KEY")
H = {"apikey": KEY, "Authorization": f"Bearer {KEY}", "Content-Type": "application/json"}

def req(method, path, payload=None, prefer="return=minimal"):
    data = json.dumps(payload).encode() if payload is not None else None
    r = urllib.request.Request(URL + path, data=data, method=method,
                               headers={**H, "Prefer": prefer})
    with urllib.request.urlopen(r, timeout=90) as resp:
        body = resp.read().decode()
        return resp.status, (json.loads(body) if body else None)

def main():
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    data = json.load(open(FULL_JSON, encoding="utf-8"))
    results = data["results"]
    print(f"[load] {len(results)} resultados em {FULL_JSON}")

    # limpa carga anterior NÃO aplicada (preserva linhas já aplicadas a products)
    req("DELETE", "/rest/v1/continente_price_staging?applied=eq.false")

    # cria run de auditoria
    _, run = req("POST", "/rest/v1/product_update_runs",
                 [{"market": "continente", "source": SRC, "status": "running",
                   "scraped": len(results)}], "return=representation")
    run_id = run[0]["id"]
    print(f"[load] run_id={run_id}")

    rows = []
    for r in results:
        base, bd, status = r.get("base"), r.get("bd"), r["status"]
        ok = status in OK
        div = round((base - bd) / bd, 4) if (base and bd) else None
        needs = (not ok) or (div is not None and abs(div) >= 0.25) \
            or status in ("ambiguous_multi_pvpr", "weird_pvpr_lt_sales")
        rows.append({
            "run_id": run_id, "product_id": r["id"], "pid": r.get("pid"),
            "name": r.get("name"), "old_price": bd, "sales_price": r.get("sales"),
            "pvpr": base if r.get("had_promo") else None,
            "new_price": base if ok else None,
            "had_promo": bool(r.get("had_promo")),
            "method": "sfcc_pid" if ok else "skipped",
            "confidence": "high" if ok else "low",
            "status": status, "divergence_pct": div, "needs_review": needs,
        })

    for i in range(0, len(rows), 500):
        req("POST", "/rest/v1/continente_price_staging", rows[i:i + 500])
        print(f"  inseridas {min(i + 500, len(rows))}/{len(rows)}")

    ok_n = sum(1 for x in rows if x["status"] in OK)
    promo_n = sum(1 for x in rows if x["status"] == "ok_promo")
    fail_n = len(rows) - ok_n
    big = sum(1 for x in rows if x["divergence_pct"] is not None and abs(x["divergence_pct"]) >= 0.25)
    req("PATCH", f"/rest/v1/product_update_runs?id=eq.{run_id}",
        {"inserted": len(rows), "updated": 0, "failed": fail_n, "status": "staged"})

    print("\n===== STAGING CARREGADA =====")
    print(f"Total: {len(rows)} | OK(atualizáveis): {ok_n} | promo(PVPR): {promo_n} | "
          f"sem-preço(needs_review): {fail_n} | divergência>=25%: {big}")
    withp = [x for x in rows if x["new_price"] and x["old_price"]]
    withp.sort(key=lambda x: abs(x["divergence_pct"] or 0), reverse=True)
    print("\nTOP 20 DIVERGÊNCIAS (preço atual BD -> novo PVPR/venda):")
    print(f"{'div%':>7} {'BD':>8} {'novo':>8} {'promo':>5}  nome")
    for x in withp[:20]:
        print(f"{(x['divergence_pct'] or 0)*100:>6.0f}% {x['old_price']:>8.2f} "
              f"{x['new_price']:>8.2f} {str(x['had_promo']):>5}  {(x['name'] or '')[:44]}")

if __name__ == "__main__":
    main()

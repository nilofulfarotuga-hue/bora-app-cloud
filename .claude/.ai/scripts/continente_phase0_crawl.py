"""
Fase 0 — CRAWL de validação (read-only, ZERO writes BD).
Testa a hipótese cont-<N>=PID + valida a regra PVPR vs venda sobre:
 - 23 produtos cont- variados (1 por categoria) -> mede taxa de hit do PID
 - 4 produtos do GATE (PVPR conhecido) -> tem de bater
Regra de preço base:
 sales = JSON-LD offers.price (sempre)
 pvprs = todos "PVP Recomendado: X" / pvpr-info da pagina
 - 0 pvpr  -> sem promo -> base = sales
 - 1 pvpr  -> promo     -> base = pvpr
 - >1 pvpr -> AMBIGUO   -> base=None, needs_review
"""
import urllib.request, urllib.error, os, re, json, time, random, sys

UA = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/121.0 Safari/537.36"
URL = "https://www.continente.pt/on/demandware.store/Sites-continente-Site/default/Product-Show?pid={pid}"
TMP = r"C:\Users\danil\Desktop\projetosflutter\bora_app\.claude\.ai\tmp"

# (pid, nome_bd, preco_bd, pvpr_esperado|None)
SAMPLE = [
    ("6969972", "Agua Tonica Zero 20cl", 0.50, None),
    ("7144887", "Comida Humida Gato", 4.07, None),
    ("4677966", "Bebida Lactea Junior", 3.56, None),
    ("5981819", "Eristoff Black 70cl", 13.56, None),
    ("2632715", "Pensos Diarios", 1.66, None),
    ("4422019", "Leite s/Lactose Mimosa", 1.73, None),
    ("2625730", "Acendalhas", 1.13, None),
    ("5876739", "Frasco Cozinha Vidro", 1.02, None),
    ("2115495", "Cerveja Sagres 1L", 1.81, None),
    ("4821032", "Queijo Azeitao", 6.72, None),
    ("8170616", "Tiras Entrecosto", 11.01, None),
    ("4470616", "Pizza Ristorante", 4.88, None),
    ("2209509", "UNO Jogo", 12.70, None),
    ("5977139", "Iogurte Liquido Bolacha", 0.36, None),
    ("7722813", "Ambientador Glade", 13.24, None),
    ("4291643", "Cola Universal", 1.56, None),
    ("8703533", "Tiras Milho Matutano", 2.03, None),
    ("7577916", "Flocos Cereais", 2.03, None),
    ("5547623", "Pao Forma Panrico", 2.18, None),
    ("7739437", "Bacalhau a Bras", 4.07, None),
    ("7523778", "Probioticos Supla", 6.72, None),
    ("6408174", "Rolo Carne Porco", 8.52, None),
    ("6526612", "Vinho Albenaz", 3.97, None),
]
GATE = [
    ("7795050", "Sanex Protector 600ml", 3.05, 5.99),
    ("7795037", "Sanex Zero% Pele Seca 600ml", 3.05, 5.99),
    ("8496362", "Vaseline Karite 700ml", 5.09, 4.99),
    ("7626664", "Gresso s/Lactose 1L", 1.19, 1.06),
]

def fetch(pid):
    req = urllib.request.Request(URL.format(pid=pid),
        headers={"User-Agent": UA, "Accept-Language": "pt-PT,pt;q=0.9"})
    try:
        with urllib.request.urlopen(req, timeout=25) as r:
            return r.status, r.geturl(), r.read().decode("utf-8", errors="replace")
    except urllib.error.HTTPError as e:
        return e.code, URL.format(pid=pid), ""
    except Exception as e:
        return -1, URL.format(pid=pid), ""

def jsonld_price(html):
    for m in re.finditer(r'<script[^>]+type=["\']application/ld\+json["\'][^>]*>(.*?)</script>', html, re.S | re.I):
        try:
            data = json.loads(m.group(1).strip())
        except Exception:
            continue
        items = data if isinstance(data, list) else [data]
        for it in items:
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

def decide(status_http, final_url, html):
    if status_http == 404:
        return None, None, None, "404"
    if status_http in (403, 429):
        return None, None, None, f"BLOCKED_{status_http}"
    if status_http != 200 or not html:
        return None, None, None, f"http_{status_http}"
    if "/produto/" not in final_url:
        return None, None, None, "redirect_home"
    sales = jsonld_price(html)
    if sales is None:
        return None, None, None, "no_price"
    pv = pvpr_values(html)
    if not pv:
        return sales, False, sales, "ok_no_promo"
    if len(pv) == 1:
        base = next(iter(pv))
        if base < sales:
            return sales, True, base, "weird_pvpr_lt_sales"
        return base, True, sales, "ok_promo"
    return None, None, sales, "ambiguous_multi_pvpr"

def run():
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    rows = [(p, n, b, e, "sample") for (p, n, b, e) in SAMPLE] + \
           [(p, n, b, e, "GATE") for (p, n, b, e) in GATE]
    results = []
    print(f"{'pid':>8} {'http':>4} {'kind':>6} {'status':<20} {'sales':>6} {'pvpr':>6} {'base':>6} {'bd':>6} {'exp':>6} {'chk'}")
    for i, (pid, name, bd, exp, kind) in enumerate(rows, 1):
        st, final, html = fetch(pid)
        base, promo, sales_or_base, status = decide(st, final, html)
        # 'base' is the chosen price; for ok_no_promo base==sales
        pvpr_disp = ""
        if status == "ok_promo":
            pvpr_disp = f"{base:.2f}"; sales_disp = f"{sales_or_base:.2f}"; base_disp = f"{base:.2f}"
        elif status == "ok_no_promo":
            sales_disp = f"{base:.2f}"; base_disp = f"{base:.2f}"
        else:
            sales_disp = f"{sales_or_base:.2f}" if sales_or_base else "-"
            base_disp = f"{base:.2f}" if base else "-"
        chk = ""
        if exp is not None:
            if base is not None and abs(base - exp) <= 0.005:
                chk = "PASS"
            else:
                chk = "FAIL"
        results.append({"pid": pid, "name": name, "http": st, "kind": kind,
                        "status": status, "base": base, "had_promo": promo,
                        "bd": bd, "expected": exp, "check": chk})
        print(f"{pid:>8} {st:>4} {kind:>6} {status:<20} {sales_disp:>6} {pvpr_disp:>6} {base_disp:>6} {bd:>6.2f} {str(exp) if exp else '-':>6} {chk}")
        if i < len(rows):
            time.sleep(max(1.0, 4.5 + random.uniform(-1.0, 1.0)))

    # Resumo
    n = len(results)
    hits = sum(1 for r in results if r["status"] in ("ok_no_promo", "ok_promo"))
    n404 = sum(1 for r in results if r["status"] == "404")
    rdir = sum(1 for r in results if r["status"] == "redirect_home")
    ambi = sum(1 for r in results if r["status"].startswith("ambiguous"))
    weird = sum(1 for r in results if r["status"] == "weird_pvpr_lt_sales")
    promo = sum(1 for r in results if r["had_promo"])
    gate = [r for r in results if r["kind"] == "GATE"]
    gate_pass = sum(1 for r in gate if r["check"] == "PASS")
    print("\n===== RESUMO FASE 0 =====")
    print(f"Total testados: {n}")
    print(f"PID resolve com preco (ok): {hits}/{n} ({100*hits/n:.0f}%)")
    print(f"404: {n404} | redirect_home: {rdir} | ambiguo: {ambi} | weird(pvpr<sales): {weird}")
    print(f"Com promocao detectada: {promo}")
    print(f"GATE: {gate_pass}/{len(gate)} PASS")
    for r in gate:
        print(f"   [{r['check']}] {r['name']}: base={r['base']} esperado={r['expected']} status={r['status']}")
    with open(os.path.join(TMP, "phase0_crawl_results.json"), "w", encoding="utf-8") as f:
        json.dump(results, f, ensure_ascii=False, indent=2)
    print("\nresultados -> tmp/phase0_crawl_results.json")

if __name__ == "__main__":
    run()

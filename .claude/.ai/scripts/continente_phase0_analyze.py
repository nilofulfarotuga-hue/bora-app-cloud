"""
Fase 0 — ANÁLISE de estrutura (lê HTML já gravado, ZERO rede, ZERO BD).
Objetivo: descobrir como extrair, do PRODUTO PRINCIPAL:
  - preço de venda (sales)  - PVPR (se em promoção)  - marcador de promoção
e garantir que não confundimos com tiles de produtos relacionados.
Imprime resumo compacto.
"""
import os, re, json

TMP = r"C:\Users\danil\Desktop\projetosflutter\bora_app\.claude\.ai\tmp"
FILES = {
    "7795050": "Sanex Protector 600ml (PVPR esperado 5.99)",
    "7795037": "Sanex Zero% Pele Seca 600ml (PVPR esperado 5.99)",
    "8496362": "Vaseline Manteiga Karite 700ml (esperado 4.99)",
}

def find_jsonld_products(html):
    out = []
    for m in re.finditer(r'<script[^>]+type=["\']application/ld\+json["\'][^>]*>(.*?)</script>', html, re.S | re.I):
        raw = m.group(1).strip()
        try:
            data = json.loads(raw)
        except Exception:
            continue
        items = data if isinstance(data, list) else [data]
        for it in items:
            if isinstance(it, dict) and 'Product' in str(it.get('@type', '')):
                offers = it.get('offers', {})
                if isinstance(offers, list):
                    offers = offers[0] if offers else {}
                out.append((it.get('name', '')[:40], offers.get('price'), offers.get('priceCurrency'), m.start()))
    return out

def ctx(html, idx, before=60, after=190):
    a = max(0, idx - before); b = min(len(html), idx + after)
    return re.sub(r'\s+', ' ', html[a:b]).strip()

for pid, label in FILES.items():
    path = os.path.join(TMP, f"phase0_{pid}.html")
    if not os.path.exists(path):
        print(f"### {pid} — FICHEIRO AUSENTE"); continue
    html = open(path, encoding="utf-8").read()
    print(f"\n### {pid} — {label}  (len={len(html)})")

    ld = find_jsonld_products(html)
    print(f"JSON-LD Product blocks: {len(ld)}")
    for nm, pr, cur, off in ld[:3]:
        print(f"   name='{nm}' price={pr} {cur} @{off}")

    tiles = len(re.findall(r'product-tile', html))
    print(f"'product-tile' occurrences: {tiles}")

    # PVPR via texto "PVPR</span> X" e via alt "PVP Recomendado: X"
    pvpr_span = [(m.group(1), m.start()) for m in re.finditer(r'pvpr-info[^>]*>\s*PVPR\s*</span>\s*([\d.,]+)\s*&euro;', html, re.I)]
    pvpr_alt  = [(m.group(1), m.start()) for m in re.finditer(r'PVP\s*Recomendado:\s*([\d.,]+)', html, re.I)]
    print(f"pvpr-info span: count={len(pvpr_span)} vals={pvpr_span[:5]}")
    print(f"PVP Recomendado alt: count={len(pvpr_alt)} vals={pvpr_alt[:5]}")

    # Preço de venda candidato: ct-price principal
    ctp = list(re.finditer(r'class="[^"]*ct-price-value[^"]*"[^>]*>\s*([\d.,]+)', html, re.I))
    if not ctp:
        ctp = list(re.finditer(r'ct-price[^>]*>\s*([\d.,]+)\s*&euro;', html, re.I))
    print(f"ct-price-value: count={len(ctp)} first={(ctp[0].group(1), ctp[0].start()) if ctp else None}")

    # value JSON (analytics) price
    p0 = re.search(r'"price"\s*:\s*"?([\d.]+)"?', html)
    print(f'first "price": {p0.group(1) if p0 else None} @{p0.start() if p0 else "-"}')

    # promo markers
    promo = bool(re.search(r'(?i)(desconto imediato|poupe|menos \d+%|em promo)', html))
    print(f"promo text marker present: {promo}")

    # contexto do bloco de preço principal (à volta do 1º pvpr-info ou ct-price)
    anchor = (pvpr_span[0][1] if pvpr_span else (ctp[0].start() if ctp else None))
    if anchor is not None:
        print(f"PRICE-BLOCK ctx: {ctx(html, anchor)}")

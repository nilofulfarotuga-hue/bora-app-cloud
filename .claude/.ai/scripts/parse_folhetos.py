"""Fase 1 — Download + parse the 3 Lidl flyer PDFs.

Heuristic parser for vectorial PDF text layer extracted via pypdf.
Output:
  .claude/.ai/tmp/lidl_folheto_products_raw.json
  .claude/.ai/tmp/lidl_folheto_summary.json
"""
import os, re, sys, time, json
import requests
import pypdf
sys.stdout.reconfigure(encoding="utf-8", errors="replace")

TMP = r"c:/Users/danil/Desktop/projetosflutter/bora_app/.claude/.ai/tmp"
os.makedirs(TMP, exist_ok=True)
UA = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0 Safari/537.36"

FLYERS = [
    ("promocoes", "019d96ba-f920-76a6-bd89-dfa45929e51d",
     "https://object.storage.eu01.onstackit.cloud/leaflets/pdfs/019d96ba-f920-76a6-bd89-dfa45929e51d/Promocoes-A-partir-de-20-04-01.pdf"),
    ("novidades", "019d96ba-7d3a-7572-a513-c784f18f60be",
     "https://object.storage.eu01.onstackit.cloud/leaflets/pdfs/019d96ba-7d3a-7572-a513-c784f18f60be/Novidades-A-partir-de-20-04-01.pdf"),
    ("cien",      "019ce724-074a-7c32-90f1-a17a9255192b",
     "https://object.storage.eu01.onstackit.cloud/leaflets/pdfs/019ce724-074a-7c32-90f1-a17a9255192b/Folheto-Especial-Cien-02.pdf"),
]

def log(*a): print(*a, flush=True)

def download(url, path):
    if os.path.exists(path) and os.path.getsize(path) > 100_000:
        log(f"  cached: {path} ({os.path.getsize(path)} bytes)")
        return
    log(f"  GET {url}")
    r = requests.get(url, headers={"User-Agent": UA}, timeout=180, stream=True)
    r.raise_for_status()
    with open(path, "wb") as f:
        for c in r.iter_content(128*1024): f.write(c)
    log(f"  saved: {path} ({os.path.getsize(path)} bytes)")

def extract_pages(pdf_path):
    reader = pypdf.PdfReader(pdf_path)
    out = []
    for p in reader.pages:
        try: t = p.extract_text() or ""
        except Exception: t = ""
        out.append(t)
    return out

# --- Heuristic parser -----------------------------------------------------
PRICE_RX = re.compile(r"^\s*(\d{1,3}[.,]\d{2})\s*$")
PRICE_DISC_RX = re.compile(r"^\s*(\d{1,3}[.,]\d{2})[-–](\d{1,3})%\s*$")
UNIT_RX = re.compile(r"^(Emb\.|Cada emb\.|Pack|Vendido ao kg|Unid\.|Cada unid\.|Formato|Pack\s*\d+|Emb\.|Emb\s*\d|Cada\s+[A-Za-z]+)", re.I)
BASE_RX = re.compile(r"\b(?:1\s*kg|1\s*L|1\s*l|100\s*ml|100\s*g|1\s*unid\.?|Cada\s*unid\.?)\s*(?:c\/?\s*LP)?\s*=\s*\d", re.I)
LP_LINE_RX = re.compile(r"^(?:[-–]?\s*\d{1,3}%|Com Lidl Plus|LP|com app)", re.I)
DATE_RX = re.compile(r"^\s*(?:\d{1,2}/\d{1,2}|\d{1,2}\.\d{1,2})\s*$")
BRAND_RX = re.compile(r"^([A-ZÁÉÍÓÚÂÊÔÃÕÇÜÑ0-9 &./\-'’]{2,30})$")  # all uppercase PT brand
NO_RX = re.compile(r"^\s*n[°º]\s*\d+", re.I)

BLACKLIST_NAMES = {
    "lidl plus", "com lidl plus", "sugestão de apresentação", "fotos sugestão",
    "apenas", "poupa", "mais", "preço", "consumidores", "em", "até",
    "novo", "reserva-se", "promoções não acumuláveis", "stock existente",
    "promoções", "novidades", "especial", "lidl", "aprovado", "ganhador",
    "a partir de", "válido", "limitado",
}

def parse_products_from_lines(lines):
    """Walk lines, detect price pairs (promo + normal with discount), extract preceding metadata."""
    products = []
    n = len(lines)
    i = 0
    while i < n:
        ln = lines[i].strip()
        # Pattern A: promo_price line (X.XX) immediately followed by Y.YY-ZZ%
        mA = PRICE_RX.match(ln)
        if mA and i + 1 < n and PRICE_DISC_RX.match(lines[i+1].strip()):
            promo = float(mA.group(1).replace(",", "."))
            mB = PRICE_DISC_RX.match(lines[i+1].strip())
            normal = float(mB.group(1).replace(",", "."))
            disc = int(mB.group(2))
            # Walk backwards to collect metadata (brand / name / unit / base)
            meta_lines = []
            for back in range(i-1, max(-1, i-15), -1):
                prev = lines[back].strip()
                if not prev: continue
                if PRICE_RX.match(prev) or PRICE_DISC_RX.match(prev): break
                if LP_LINE_RX.match(prev): continue
                if DATE_RX.match(prev): continue
                if prev.startswith("-") and "%" in prev: continue
                if prev in {"Com Lidl Plus", "apenas", "Com app", "com app"}: continue
                meta_lines.append(prev)
                if len(meta_lines) >= 10: break
            meta_lines.reverse()
            prod = parse_meta(meta_lines)
            if prod and prod.get("name"):
                prod["price_normal"] = normal
                prod["price_promo"] = promo
                prod["discount_pct"] = disc
                products.append(prod)
            i += 2
            continue
        # Pattern B: lone price (X.XX) possibly with -YY% nearby — single-price item
        i += 1
    return products

def parse_meta(lines):
    """From an array of 1-10 raw text lines before a price, extract brand/name/unit/base_price."""
    brand = None
    name_parts = []
    unit = None
    base_price = None
    no_art = None
    for ln in lines:
        ln = ln.strip()
        if not ln: continue
        if NO_RX.match(ln):
            no_art = ln; continue
        if BASE_RX.match(ln):
            base_price = ln; continue
        if UNIT_RX.match(ln):
            unit = ln; continue
        if BRAND_RX.match(ln) and brand is None and not name_parts:
            # likely brand (all caps) at the top
            brand = ln.strip(); continue
        # otherwise part of name
        name_parts.append(ln)
    name = " ".join(name_parts).strip()
    name = re.sub(r"\s+", " ", name)
    # validate
    if not name or len(name) < 3 or name.lower() in BLACKLIST_NAMES: return None
    # skip names that are mostly digits or pure numeric
    if re.match(r"^[\d\s.,%/\-]+$", name): return None
    # Skip obvious legal text
    if any(k in name.lower() for k in ["reserva-se", "promoções", "preço segundo", "stock existente",
                                        "consumidores", "adereços", "poupa ainda", "válid", "sugestão"]):
        return None
    return {
        "brand": brand,
        "name": name,
        "unit": unit,
        "base_price_text": base_price,
        "article_no": no_art,
    }

def process(flyer_slug, uuid, pdf_url):
    pdf_path = f"{TMP}/lidl_folheto_{flyer_slug}.pdf"
    log(f"\n--- {flyer_slug} ---")
    download(pdf_url, pdf_path)
    pages = extract_pages(pdf_path)
    log(f"  pages: {len(pages)}")
    all_prods = []
    for page_num, page_text in enumerate(pages, start=1):
        lines = page_text.split("\n")
        prods = parse_products_from_lines(lines)
        for p in prods:
            p["page"] = page_num
            p["flyer"] = flyer_slug
            p["flyer_uuid"] = uuid
        all_prods.extend(prods)
    log(f"  parsed products: {len(all_prods)}")
    # Show sample from first 3 pages with products
    shown = 0
    for p in all_prods[:6]:
        log(f"    [{p['page']}] brand={p.get('brand')!r} name={p['name']!r} unit={p.get('unit')!r} promo={p['price_promo']} normal={p['price_normal']} disc=-{p['discount_pct']}%")
        shown += 1
    return all_prods

results = {}
all_products = []
for slug, u, url in FLYERS:
    try:
        prods = process(slug, u, url)
        results[slug] = {"products": len(prods), "uuid": u}
        all_products.extend(prods)
    except Exception as e:
        log(f"  ERR: {type(e).__name__}: {e}")
        results[slug] = {"err": str(e)[:200]}

# Deduplicate: same name case-insensitive within the batch
seen = {}
for p in all_products:
    key = (p["flyer"], p["name"].lower())
    if key not in seen: seen[key] = p
dedup = list(seen.values())

# Stats
by_flyer = {}
for p in dedup:
    f = p["flyer"]
    by_flyer.setdefault(f, {"total": 0, "with_brand": 0, "with_unit": 0,
                            "promo_avg": 0.0, "promo_min": None, "promo_max": None})
    by_flyer[f]["total"] += 1
    if p.get("brand"): by_flyer[f]["with_brand"] += 1
    if p.get("unit"): by_flyer[f]["with_unit"] += 1
    pp = p["price_promo"]
    by_flyer[f]["promo_avg"] += pp
    by_flyer[f]["promo_min"] = pp if by_flyer[f]["promo_min"] is None else min(by_flyer[f]["promo_min"], pp)
    by_flyer[f]["promo_max"] = pp if by_flyer[f]["promo_max"] is None else max(by_flyer[f]["promo_max"], pp)
for f, st in by_flyer.items():
    if st["total"]: st["promo_avg"] = round(st["promo_avg"] / st["total"], 2)

summary = {
    "total_raw": len(all_products),
    "total_dedup": len(dedup),
    "by_flyer": by_flyer,
    "per_flyer_runs": results,
    "samples": [
        {"flyer": p["flyer"], "page": p["page"], "brand": p.get("brand"),
         "name": p["name"], "unit": p.get("unit"), "base": p.get("base_price_text"),
         "price_normal": p["price_normal"], "price_promo": p["price_promo"],
         "discount_pct": p["discount_pct"]}
        for p in dedup[:10]
    ],
}

with open(f"{TMP}/lidl_folheto_products_raw.json", "w", encoding="utf-8") as f:
    json.dump(dedup, f, ensure_ascii=False, indent=2)
with open(f"{TMP}/lidl_folheto_summary.json", "w", encoding="utf-8") as f:
    json.dump(summary, f, ensure_ascii=False, indent=2)

log("\n=== SUMMARY ===")
log(json.dumps(summary, ensure_ascii=False, indent=2))
log(f"\nSaved: {TMP}/lidl_folheto_products_raw.json")
log(f"Saved: {TMP}/lidl_folheto_summary.json")

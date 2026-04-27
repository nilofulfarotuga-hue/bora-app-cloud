"""
Fase 1 — Lidl.pt full scrape (search API with pagination).

Endpoint: /q/api/search?assortment=PT&locale=pt_PT&version=v2.0.0&fetchsize=N&offset=N
No auth. Rate limit 3-4s between requests. Stops if 403/429/captcha.

Output:
  .claude/.ai/tmp/lidl_all_products.json        — normalized product list
  .claude/.ai/tmp/lidl_fase1_summary.json       — counts, category breakdown
  .claude/.ai/tmp/lidl_fase1_raw_offsets.json   — per-offset numFound log
"""
import json, time, os, sys, re
import requests

TMP = r"c:/Users/danil/Desktop/projetosflutter/bora_app/.claude/.ai/tmp"
os.makedirs(TMP, exist_ok=True)

UA = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0 Safari/537.36"
BASE_HDR = {"User-Agent": UA, "Accept-Language": "pt-PT,pt;q=0.9", "Accept-Encoding": "gzip, deflate"}
API_HDR = {
    "Accept": "application/json, text/plain, */*",
    "X-Requested-With": "XMLHttpRequest",
    "sec-fetch-site": "same-origin",
    "sec-fetch-mode": "cors",
    "sec-fetch-dest": "empty",
    "Referer": "https://www.lidl.pt/",
}

def log(*a):
    print(*a, flush=True)

s = requests.Session()
s.headers.update(BASE_HDR)

# Seed cookies
log("seeding home...")
r = s.get("https://www.lidl.pt/", timeout=30); log(" home", r.status_code)
time.sleep(3)

FETCHSIZE = 108  # server cap observed
offset = 0
all_items = []
offsets_log = []

while True:
    url = f"https://www.lidl.pt/q/api/search?assortment=PT&locale=pt_PT&version=v2.0.0&fetchsize={FETCHSIZE}&offset={offset}"
    log(f"GET offset={offset} fs={FETCHSIZE}")
    try:
        r = s.get(url, headers=API_HDR, timeout=60)
    except Exception as e:
        log(" ERR:", e); time.sleep(5); continue
    if r.status_code in (403, 429):
        log(" BLOCKED status=", r.status_code, "ABORT"); break
    if r.status_code != 200:
        log(" non-200", r.status_code, r.text[:200]); break
    try:
        d = r.json()
    except Exception as e:
        log(" json err", e); break
    numFound = d.get("numFound") or 0
    items = d.get("items") or []
    offsets_log.append({"offset": offset, "numFound": numFound, "items": len(items)})
    log(f"  numFound={numFound} items={len(items)}")
    all_items.extend(items)
    if len(items) < FETCHSIZE or (offset + len(items)) >= numFound:
        break
    offset += len(items)
    time.sleep(3.5)

log(f"TOTAL raw items: {len(all_items)}")

# Normalize
def norm(it):
    g = (it.get("gridbox") or {}).get("data") or {}
    lp_arr = g.get("lidlPlus") or []
    lp = (lp_arr[0].get("price") if lp_arr else {}) or {}
    pkg = (lp.get("packaging") or {}).get("text")
    base_price = (lp.get("basePrice") or {}).get("text")
    old_price = lp.get("oldPrice")
    plus_price = lp.get("price")
    # price rule from user: use oldPrice (normal loja); if None, use plus_price; if still None -> skip
    final_price = old_price if old_price is not None else plus_price
    brand_obj = g.get("brand") or {}
    brand_name = brand_obj.get("brandName") or brand_obj.get("name")
    if not brand_name and brand_obj.get("showBrand") is False:
        brand_name = "Lidl"
    img = None
    iv = g.get("image_V1")
    if isinstance(iv, dict):
        img = iv.get("image")
    if not img:
        img = g.get("image")
    imgs = g.get("imageList") or ([img] if img else [])
    keyfacts = g.get("keyfacts") or {}
    return {
        "productId": g.get("productId") or g.get("itemId"),
        "erpNumber": g.get("erpNumber"),
        "title": g.get("title") or g.get("fullTitle"),
        "fullTitle": g.get("fullTitle"),
        "brand": brand_name,
        "price": final_price,
        "price_normal": old_price,
        "price_with_app": plus_price,
        "currency": (g.get("price") or {}).get("currencyCode") or "EUR",
        "packaging": pkg,
        "base_price_text": base_price,
        "image": img,
        "image_list": imgs[:5],
        "canonical_path": g.get("canonicalPath"),
        "url": ("https://www.lidl.pt" + g.get("canonicalPath")) if g.get("canonicalPath") else None,
        "category_root": keyfacts.get("wonCategoryPrimary"),
        "category_path": keyfacts.get("wonCategoryPrimaryPath"),
        "product_type": g.get("productType"),
        "category_global": g.get("category"),
        "online_available": g.get("online"),
        "store_available": g.get("store"),
        "age_restriction": g.get("ageRestriction"),
    }

normed = [norm(x) for x in all_items]

# Dedupe by productId
seen = {}
for p in normed:
    pid = p.get("productId")
    if pid is None: continue
    # prefer records with price+image
    score = (1 if p.get("price") is not None else 0) + (1 if p.get("image") else 0)
    if pid not in seen or score > seen[pid][0]:
        seen[pid] = (score, p)
dedup = [v[1] for v in seen.values()]

log(f"after dedupe: {len(dedup)} (was {len(normed)})")

# Save raw items for audit (optional — keep small)
with open(f"{TMP}/lidl_all_products.json", "w", encoding="utf-8") as f:
    json.dump(dedup, f, ensure_ascii=False, indent=2)

# Summary
with_price = sum(1 for p in dedup if p["price"] is not None and p["price"] > 0)
with_image = sum(1 for p in dedup if p["image"])
lidl_brand = sum(1 for p in dedup if p["brand"] == "Lidl")
has_brand = sum(1 for p in dedup if p["brand"])
by_cat = {}
for p in dedup:
    c = p.get("category_root") or "(sem categoria)"
    by_cat.setdefault(c, {"total": 0, "with_price": 0, "with_image": 0})
    by_cat[c]["total"] += 1
    if p["price"] is not None and p["price"] > 0: by_cat[c]["with_price"] += 1
    if p["image"]: by_cat[c]["with_image"] += 1
# Price-missing samples
missing_price = [p for p in dedup if not p["price"]][:10]
missing_image = [p for p in dedup if not p["image"]][:10]

# Non-PT language detection (heuristic: common DE/FR/IT tokens)
FOREIGN = re.compile(r"\b(Haushalt|Käse|Fromage|Formaggio|mit|avec|con|und|pro|Stück|Packung|Schokolade|confection|gramm|Würst|vom)\b", re.I)
foreign_hits = [p for p in dedup if p.get("title") and FOREIGN.search(p["title"])][:10]

summary = {
    "total_raw": len(normed),
    "total_dedup": len(dedup),
    "with_price": with_price,
    "with_image": with_image,
    "without_price": len(dedup) - with_price,
    "without_image": len(dedup) - with_image,
    "brand_lidl_assigned": lidl_brand,
    "has_any_brand": has_brand,
    "by_category_root": by_cat,
    "offsets_log": offsets_log,
    "sitemap_declared_635": 635,
    "missing_price_samples": [{"id": p["productId"], "title": p["title"]} for p in missing_price],
    "missing_image_samples": [{"id": p["productId"], "title": p["title"]} for p in missing_image],
    "foreign_language_samples": [{"id": p["productId"], "title": p["title"]} for p in foreign_hits],
}

with open(f"{TMP}/lidl_fase1_summary.json", "w", encoding="utf-8") as f:
    json.dump(summary, f, ensure_ascii=False, indent=2)

log("\n=== SUMMARY ===")
log(json.dumps({k: v for k, v in summary.items() if k not in ("by_category_root", "offsets_log")}, ensure_ascii=False, indent=2))
log(f"Saved: {TMP}/lidl_all_products.json")
log(f"Saved: {TMP}/lidl_fase1_summary.json")

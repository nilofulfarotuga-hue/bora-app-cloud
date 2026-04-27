"""Build INSERT SQL for Lidl Fase 2. Reads normalized products, filters with_price,
dedupes by name (case-insensitive), writes .sql file."""
import json, os, re

TMP = r"c:/Users/danil/Desktop/projetosflutter/bora_app/.claude/.ai/tmp"
SRC = f"{TMP}/lidl_all_products.json"
OUT = f"{TMP}/lidl_fase2_insert.sql"
PREVIEW = f"{TMP}/lidl_fase2_preview.json"

RESTAURANT_ID = "lidl-guarda"
SOURCE = "lidl.pt_2026-04-20"
IMAGE_SOURCE = "lidl.pt"

products = json.load(open(SRC, encoding="utf-8"))
print(f"input: {len(products)}")

# Filter: must have price (>0) and image
with_price = [p for p in products if p.get("price") and p["price"] > 0 and p.get("image")]
print(f"with_price_and_image: {len(with_price)}")

# Dedupe by name (case-insensitive strip)
seen_names = set()
dedup = []
dupe_drops = []
for p in with_price:
    nm = (p.get("title") or "").strip()
    if not nm:
        continue
    key = nm.lower()
    if key in seen_names:
        dupe_drops.append(nm); continue
    seen_names.add(key)
    dedup.append(p)
print(f"after_name_dedupe: {len(dedup)} (dropped {len(dupe_drops)} dupes)")

# Build preview
def preview_row(p):
    is_wine = "Vinho" in (p.get("category_root") or "") or p.get("age_restriction") is True
    return {
        "productId": p["productId"],
        "name": p["title"],
        "brand": p["brand"],
        "price": p["price"],
        "photo_url": p["image"],
        "unit": p.get("packaging"),
        "description": p.get("base_price_text"),
        "category_root": p.get("category_root"),
        "needs_review": is_wine,
        "age_restricted": is_wine,
    }
json.dump([preview_row(p) for p in dedup], open(PREVIEW, "w", encoding="utf-8"), ensure_ascii=False, indent=2)

# Escape single quotes for SQL
def esc(v):
    if v is None:
        return "NULL"
    if isinstance(v, bool):
        return "true" if v else "false"
    if isinstance(v, (int, float)):
        return str(v)
    s = str(v).replace("'", "''")
    return f"'{s}'"

def build_row(p):
    is_wine = "Vinho" in (p.get("category_root") or "") or p.get("age_restriction") is True
    # search_normalized: lowercase ascii, strip accents
    import unicodedata
    sn = unicodedata.normalize("NFD", (p.get("title") or "")).encode("ascii", "ignore").decode().lower()
    sn = re.sub(r"\s+", " ", sn).strip()
    return (
        f"('lidl-{p['productId']}',"  # id deterministic
        f"'{RESTAURANT_ID}',"
        f"{esc(p['title'])},"                # name
        f"{esc(p.get('base_price_text'))},"  # description (preço por kg)
        f"{esc(p['image'])},"                # photo_url
        f"true,"                             # is_available
        f"{p['price']},"                     # price
        f"NULL,"                             # category (null — taxonomy_mapper later)
        f"{esc(p.get('packaging'))},"        # unit
        f"{esc(p.get('brand'))},"            # brand_low
        f"{esc(SOURCE)},"                    # source
        f"{esc(IMAGE_SOURCE)},"              # image_source
        f"false,"                            # needs_photo
        f"{esc(p.get('category_root'))},"    # category_root
        f"{esc(sn)},"                        # search_normalized
        f"NULL,"                             # taxonomy_section
        f"{'true' if is_wine else 'false'})" # needs_review
    )

cols = ("id, restaurant_id, name, description, photo_url, is_available, price, "
        "category, unit, brand_low, source, image_source, needs_photo, "
        "category_root, search_normalized, taxonomy_section, needs_review")

rows = [build_row(p) for p in dedup]
print(f"rows_built: {len(rows)}")

sql_lines = [
    "-- Lidl PT — Fase 2 INSERT (generated)",
    f"-- source={SOURCE}, restaurant_id={RESTAURANT_ID}",
    "-- Dedupe: productId + name(case-insensitive). No ON CONFLICT (no unique index on name).",
    "BEGIN;",
    f"-- pre-count for Lidl",
    f"SELECT COUNT(*) AS before_count FROM products WHERE restaurant_id='{RESTAURANT_ID}';",
    f"INSERT INTO products ({cols}) VALUES",
    ",\n".join(rows) + ";",
    f"SELECT COUNT(*) AS after_count FROM products WHERE restaurant_id='{RESTAURANT_ID}';",
    "COMMIT;",
]
open(OUT, "w", encoding="utf-8").write("\n".join(sql_lines))
print(f"sql_written: {OUT}")
print(f"preview_written: {PREVIEW}")
print(f"wine_count: {sum(1 for p in dedup if 'Vinho' in (p.get('category_root') or ''))}")
print(f"lidl_brand_count: {sum(1 for p in dedup if p.get('brand')=='Lidl')}")

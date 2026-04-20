"""Build brand regex from allowlist and run audit query for a given market.

Usage:
  _brand_audit.py <market_ilike>   # dry audit
  _brand_audit.py <market_ilike> apply
"""
import os, sys, re, time
from dotenv import load_dotenv
import httpx

env_path = r"C:\Users\danil\Desktop\projetosflutter\bora_app\backend\.env"
load_dotenv(env_path)
url = os.environ["SUPABASE_URL"]
svc = os.environ["SUPABASE_SERVICE_ROLE_KEY"]

market = sys.argv[1] if len(sys.argv) > 1 else "%mercadona%"
mode = sys.argv[2] if len(sys.argv) > 2 else "dry"

list_path = r"C:\Users\danil\Desktop\projetosflutter\bora_app\.claude\.ai\reports\_brand_allowlist.txt"
with open(list_path, "r", encoding="utf-8") as f:
    raw = f.read()

brands = []
for line in raw.splitlines():
    line = line.strip()
    if not line or line.startswith("#"):
        continue
    brands.append(line)

# Escape regex special chars, sort longest first (longest-match first)
escaped = sorted({re.escape(b) for b in brands}, key=len, reverse=True)
brand_regex = "(?:" + "|".join(escaped) + ")"
# SQL-escape apostrophes for single-quoted literal embedding
brand_regex_sql = brand_regex.replace("'", "''")

print(f"Brand allowlist size: {len(escaped)}")
print(f"Brand regex length: {len(brand_regex)} chars")

headers = {"apikey": svc, "Authorization": f"Bearer {svc}"}
# We'll run the audit via PostgREST RPC isn't available — use raw SQL via Supabase MCP
# from the caller. Here we just emit the SQL.

audit_sql = f"""
WITH mkt AS (
  SELECT p.id, p.name, p.photo_url
  FROM products p JOIN restaurants r ON r.id=p.restaurant_id
  WHERE r.name ILIKE '{market}' AND p.is_available = true
),
flags AS (
  SELECT id, name,
    (photo_url IS NULL OR photo_url = '' OR photo_url NOT LIKE 'http%') AS no_image,
    (name ~* '\\y{brand_regex_sql}\\y')                                       AS has_brand
  FROM mkt
)
SELECT
  (SELECT COUNT(*) FROM mkt)                                    AS total,
  (SELECT COUNT(*) FROM flags WHERE no_image)                   AS no_image,
  (SELECT COUNT(*) FROM flags WHERE NOT has_brand)              AS no_brand,
  (SELECT COUNT(*) FROM flags WHERE no_image AND NOT has_brand) AS hide_candidates;
"""

apply_sql = f"""
WITH mkt AS (
  SELECT p.id
  FROM products p JOIN restaurants r ON r.id=p.restaurant_id
  WHERE r.name ILIKE '{market}' AND p.is_available = true
    AND (p.photo_url IS NULL OR p.photo_url = '' OR p.photo_url NOT LIKE 'http%')
    AND p.name !~* '\\y{brand_regex_sql}\\y'
)
UPDATE products SET is_available = false FROM mkt WHERE products.id = mkt.id;
"""

sample_sql = f"""
SELECT p.name
FROM products p JOIN restaurants r ON r.id=p.restaurant_id
WHERE r.name ILIKE '{market}' AND p.is_available = true
  AND (p.photo_url IS NULL OR p.photo_url = '' OR p.photo_url NOT LIKE 'http%')
  AND p.name !~* '\\y{brand_regex_sql}\\y'
ORDER BY random()
LIMIT 30;
"""

# Write SQL to files so the caller can execute via MCP
out_dir = r"C:\Users\danil\Desktop\projetosflutter\bora_app\.claude\.ai\reports"
with open(os.path.join(out_dir, "_brand_audit.sql"), "w", encoding="utf-8") as f:
    f.write(audit_sql)
with open(os.path.join(out_dir, "_brand_apply.sql"), "w", encoding="utf-8") as f:
    f.write(apply_sql)
with open(os.path.join(out_dir, "_brand_sample.sql"), "w", encoding="utf-8") as f:
    f.write(sample_sql)

print(f"\nAudit SQL -> _brand_audit.sql  ({len(audit_sql)} chars)")
print(f"Apply SQL -> _brand_apply.sql  ({len(apply_sql)} chars)")
print(f"Sample SQL -> _brand_sample.sql ({len(sample_sql)} chars)")

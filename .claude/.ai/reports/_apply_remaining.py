"""Fetch ALL remaining Mercadona products with Ã and apply the same dict+fix."""
import os, sys, json, time
from dotenv import load_dotenv
import httpx

env_path = r"C:\Users\danil\Desktop\projetosflutter\bora_app\backend\.env"
load_dotenv(env_path)

url = os.environ.get("SUPABASE_URL")
svc = os.environ.get("SUPABASE_SERVICE_ROLE_KEY")

headers = {
    "apikey": svc,
    "Authorization": f"Bearer {svc}",
    "Content-Type": "application/json",
}
client = httpx.Client(headers=headers, timeout=30.0, base_url=url)

# First, find Mercadona restaurant id(s)
r = client.get("/rest/v1/restaurants?select=id,name&name=ilike.*mercadona*")
restaurants = r.json()
print(f"Mercadona restaurants: {[x['name'] for x in restaurants]}")
rest_ids = [x['id'] for x in restaurants]

# Fetch all products with Ã for those restaurants, paginated
rows = []
page_size = 1000
offset = 0
while True:
    rest_filter = "in.(" + ",".join(rest_ids) + ")"
    r = client.get(
        "/rest/v1/products",
        params={
            "select": "id,name,name_original",
            "restaurant_id": rest_filter,
            "name": f"like.*{chr(0x00C3)}*",  # literal Ã, PostgREST * sugar
            "limit": str(page_size),
            "offset": str(offset),
        },
    )
    chunk = r.json()
    if not chunk:
        break
    rows.extend(chunk)
    offset += page_size
    if len(chunk) < page_size:
        break
print(f"Rows with Ã: {len(rows)}")

# Import fix_name from previous script
sys.path.insert(0, r"C:\Users\danil\Desktop\projetosflutter\bora_app\.claude\.ai\reports")
from _moji_fix_v2 import fix_name

new_pairs = []
still_unresolved = 0
for row in rows:
    old = row['name']
    new, unresolved = fix_name(old)
    if new != old:
        new_pairs.append({"id": row['id'], "old": old, "new": new,
                          "already_fixed": row.get('name_original') is not None})
    if unresolved:
        still_unresolved += 1

print(f"New fixable rows: {len(new_pairs)}")
print(f"Still unresolved (some Ã kept): {still_unresolved}")

# Apply via PATCH, concurrently
import concurrent.futures
def apply_one(item):
    pid = item['id']
    # If already partially fixed before, don't overwrite name_original
    body = {"name": item['new']}
    if not item['already_fixed']:
        body["name_original"] = item['old']
    r = client.patch(
        f"/rest/v1/products?id=eq.{pid}",
        headers={**headers, "Prefer": "return=minimal"},
        json=body,
    )
    return (pid, r.status_code in (200, 204), r.status_code)

ok = 0
err = 0
t0 = time.time()
with concurrent.futures.ThreadPoolExecutor(max_workers=20) as ex:
    for pid, good, status in ex.map(apply_one, new_pairs):
        if good:
            ok += 1
        else:
            err += 1
            if err < 5:
                print(f"  ERR {pid}: {status}")
print(f"\nApplied in {time.time()-t0:.1f}s — OK={ok} ERR={err}")

client.close()

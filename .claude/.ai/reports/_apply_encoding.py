"""Apply encoding fix batches to Supabase via service-role SQL.

Uses POSTGREST URL /rest/v1/rpc/exec_sql if available, else falls back to
parsed-row bulk UPDATE via supabase-py (multi-row).
"""
import os, sys, json, glob, time
from dotenv import load_dotenv

env_path = r"C:\Users\danil\Desktop\projetosflutter\bora_app\backend\.env"
load_dotenv(env_path)

url = os.environ.get("SUPABASE_URL")
svc = os.environ.get("SUPABASE_SERVICE_ROLE_KEY")
if not (url and svc):
    print("Missing SUPABASE_URL or SUPABASE_SERVICE_ROLE_KEY")
    sys.exit(1)

# Load all batch SQL files
batch_dir = r"C:\Users\danil\Desktop\projetosflutter\bora_app\.claude\.ai\reports\sql_batches"
batches = sorted(glob.glob(os.path.join(batch_dir, "batch_*.sql")))
print(f"Found {len(batches)} batches")

# We need raw SQL execution; PostgREST doesn't support multi-statement SQL.
# Approach: use psycopg2 with the direct DB URL derived from SUPABASE_URL.
# Direct DB URL: postgresql://postgres.<ref>:<pwd>@aws-0-<region>.pooler.supabase.com:6543/postgres
# Simpler: use supabase.postgrest._request with raw text — not supported.
# BEST: use the MCP supabase execute_sql tool. But this is a Python script.
# ALTERNATIVE: emit SQL bundle + rely on operator to run via MCP.

# Let's try the JSON-based approach: build a big JSON array, post to a stored
# RPC named 'apply_encoding_fix' — requires creating the function first.
# That's 2 steps and needs DDL.

# Cleanest given constraints: connect via psycopg2 to the connection string.
# Supabase projects publish pooler URL. We can build it from SUPABASE_URL ref.
import urllib.parse as up
ref = url.replace("https://", "").split(".")[0]
print(f"Project ref: {ref}")

# Supabase DB password is not in .env — service role is JWT, not DB pwd.
# So psycopg2 path won't work without DB password.

# CORRECT approach: write out a single JSON payload, use PostgREST to update
# each product individually. 1332 rows via REST = 1332 HTTP calls. Slow but
# works. Use threading for concurrency.

import httpx
headers = {
    "apikey": svc,
    "Authorization": f"Bearer {svc}",
    "Content-Type": "application/json",
    "Prefer": "return=minimal",
}

# Load fixes JSON directly
fixes_path = r"C:\Users\danil\Desktop\projetosflutter\bora_app\.claude\.ai\reports\mercadona_encoding_fixes_v2.json"
with open(fixes_path, 'r', encoding='utf-8') as f:
    fixes = json.load(f)
print(f"Total fixes: {len(fixes)}")

# Filter: only apply where the row is still UNfixed (name_original IS NULL)
# — gives idempotence.

import concurrent.futures
client = httpx.Client(headers=headers, timeout=30.0, base_url=url)

def apply_one(item):
    pid = item['id']
    new_name = item['new']
    # Two-step: only set name_original if currently NULL.
    # Use single PATCH with RPC-free approach:
    r = client.patch(
        f"/rest/v1/products?id=eq.{pid}&name_original=is.null",
        json={"name_original": item['old'], "name": new_name},
    )
    if r.status_code not in (200, 204):
        return (pid, False, r.status_code, r.text[:200])
    # Check: if no rows affected (because name_original already set), skip
    # But since 'return=minimal', we don't know. Check via Content-Range header.
    cr = r.headers.get("Content-Range", "")
    return (pid, True, r.status_code, cr)

ok_count = 0
err_count = 0
errs_sample = []
t0 = time.time()
with concurrent.futures.ThreadPoolExecutor(max_workers=20) as ex:
    for i, result in enumerate(ex.map(apply_one, fixes), 1):
        pid, ok, status, info = result
        if ok:
            ok_count += 1
        else:
            err_count += 1
            if len(errs_sample) < 5:
                errs_sample.append((pid, status, info))
        if i % 100 == 0:
            sys.stdout.write(f"  progress {i}/{len(fixes)}\n")
            sys.stdout.flush()
elapsed = time.time() - t0
print(f"\nDone in {elapsed:.1f}s")
print(f"OK:     {ok_count}")
print(f"Errors: {err_count}")
for e in errs_sample:
    print(f"  {e}")

client.close()

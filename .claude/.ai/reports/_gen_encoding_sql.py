"""Generate batched UPDATE SQL for Mercadona encoding fix.

Reads mercadona_encoding_fixes_v2.json and produces SQL batches of N rows each
using VALUES + UPDATE FROM pattern. Writes one file per batch.
"""
import json, os, sys, re

IN_PATH = r"C:\Users\danil\Desktop\projetosflutter\bora_app\.claude\.ai\reports\mercadona_encoding_fixes_v2.json"
OUT_DIR = r"C:\Users\danil\Desktop\projetosflutter\bora_app\.claude\.ai\reports\sql_batches"
BATCH_SIZE = 400

os.makedirs(OUT_DIR, exist_ok=True)

with open(IN_PATH, 'r', encoding='utf-8') as f:
    pairs = json.load(f)

def sql_escape(s: str) -> str:
    return s.replace("'", "''")

def build_batch_sql(batch):
    lines = []
    lines.append("WITH fixes(id, new_name) AS (VALUES")
    vals = []
    for p in batch:
        pid = p['id']
        new_name = sql_escape(p['new'])
        vals.append(f"  ('{pid}'::uuid, '{new_name}')")
    lines.append(",\n".join(vals))
    lines.append(")")
    lines.append("UPDATE products p")
    lines.append("SET name_original = COALESCE(p.name_original, p.name),")
    lines.append("    name = f.new_name")
    lines.append("FROM fixes f")
    lines.append("WHERE p.id = f.id;")
    return "\n".join(lines)

n_batches = (len(pairs) + BATCH_SIZE - 1) // BATCH_SIZE
for i in range(n_batches):
    batch = pairs[i*BATCH_SIZE:(i+1)*BATCH_SIZE]
    sql = build_batch_sql(batch)
    out_path = os.path.join(OUT_DIR, f"batch_{i+1:02d}.sql")
    with open(out_path, 'w', encoding='utf-8') as f:
        f.write(sql)
    line = f"Batch {i+1}/{n_batches}: {len(batch)} rows -> {out_path}\n"
    sys.stdout.buffer.write(line.encode('utf-8'))

sys.stdout.buffer.write(f"\nTotal: {len(pairs)} rows in {n_batches} batches of {BATCH_SIZE}.\n".encode('utf-8'))

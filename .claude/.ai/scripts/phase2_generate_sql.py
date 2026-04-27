"""
Fase 2 — gera SQL chunks para aplicar preços scraped à BD.
Input: phase1_prices_2026-04-21.json
Overlaps (NÃO atualizar preço, marcar is_available=false): hard-coded 6 PIDs
Output:
  - phase2_chunk_001.sql ... phase2_chunk_NNN.sql  (UPDATE price, 500 rows cada)
  - phase2_disable.sql  (is_available=false + needs_review=true)
  - phase2_summary.txt  (estatísticas para conferir antes de executar)
"""
import json, os

BASE = r"C:\Users\danil\Desktop\projetosflutter\bora_app\.claude\.ai"
INPUT = os.path.join(BASE, "tmp", "phase1_prices_2026-04-21.json")
OUTDIR = os.path.join(BASE, "tmp", "phase2_sql")
os.makedirs(OUTDIR, exist_ok=True)

# Overlaps confirmados via SQL: PIDs que existem em ambas sources com preço em continente_guarda
OVERLAP_PIDS = {"2604857", "5078545", "6063139", "7122561", "7147181", "7991129"}

NEW_SOURCE = "continente_guarda_pid_lookup_2026-04-22"
CHUNK_SIZE = 500

with open(INPUT, "r", encoding="utf-8") as f:
    data = json.load(f)

ok = []          # (pid, price_decimal)
to_disable = []  # pid (failures + overlaps)

for r in data["results"]:
    pid = r["pid"]
    if r["price_eur"]:
        price = float(r["price_eur"])
        if pid in OVERLAP_PIDS:
            to_disable.append(pid)  # has price but is duplicate of continente_guarda
        else:
            ok.append((pid, price))
    else:
        to_disable.append(pid)

# Sort for determinism
ok.sort(key=lambda x: x[0])
to_disable.sort()

# Write chunks
chunk_files = []
for i in range(0, len(ok), CHUNK_SIZE):
    chunk = ok[i:i+CHUNK_SIZE]
    n = i // CHUNK_SIZE + 1
    fname = os.path.join(OUTDIR, f"phase2_chunk_{n:03d}.sql")
    ids_arr = ",".join(f"'glv-{pid}'" for pid, _ in chunk)
    prices_arr = ",".join(f"{price:.2f}" for _, price in chunk)
    sql = (
        f"-- chunk {n}: {len(chunk)} rows\n"
        f"UPDATE products SET\n"
        f"  price = v.new_price,\n"
        f"  updated_at = now(),\n"
        f"  source = '{NEW_SOURCE}',\n"
        f"  is_available = true,\n"
        f"  needs_review = false\n"
        f"FROM unnest(\n"
        f"  ARRAY[{ids_arr}]::text[],\n"
        f"  ARRAY[{prices_arr}]::numeric[]\n"
        f") AS v(id, new_price)\n"
        f"WHERE products.id = v.id\n"
        f"  AND products.source = 'glovo-continente-guarda-2026-04-21';"
    )
    with open(fname, "w", encoding="utf-8") as f:
        f.write(sql)
    chunk_files.append((fname, len(chunk)))

# Disable file
disable_ids = ",".join(f"'glv-{pid}'" for pid in to_disable)
disable_sql = (
    f"-- disable {len(to_disable)} rows (275 sem preço + 6 overlaps com continente_guarda)\n"
    f"UPDATE products SET\n"
    f"  is_available = false,\n"
    f"  needs_review = true,\n"
    f"  updated_at = now()\n"
    f"WHERE id IN ({disable_ids})\n"
    f"  AND source = 'glovo-continente-guarda-2026-04-21';"
)
disable_path = os.path.join(OUTDIR, "phase2_disable.sql")
with open(disable_path, "w", encoding="utf-8") as f:
    f.write(disable_sql)

# Summary
summary_lines = [
    f"Total OK scraped:           {len([1 for r in data['results'] if r['price_eur']])}",
    f"Overlaps com continente_guarda: {len(OVERLAP_PIDS)}",
    f"PRICE UPDATE rows:          {sum(c for _, c in chunk_files)} (em {len(chunk_files)} chunks)",
    f"DISABLE rows:               {len(to_disable)}",
    f"",
    f"Chunks gerados:",
]
for fname, n in chunk_files:
    summary_lines.append(f"  {os.path.basename(fname):28s}  {n:4d} rows  {os.path.getsize(fname):6d} bytes")
summary_lines.append(f"  {os.path.basename(disable_path):28s}  {len(to_disable):4d} rows  {os.path.getsize(disable_path):6d} bytes")

summary = "\n".join(summary_lines)
with open(os.path.join(OUTDIR, "phase2_summary.txt"), "w", encoding="utf-8") as f:
    f.write(summary)
print(summary)

import json, re, random, os, sys

path = r"C:\Users\danil\.claude\projects\C--Users-danil-Desktop-projetosflutter\ba7df694-d9dd-4c8d-abf7-94a4102763fe\tool-results\mcp-supabase-execute_sql-1776628390484.txt"

with open(path, 'r', encoding='utf-8') as f:
    raw = f.read()

outer = json.loads(raw)
# outer[0]['text'] is itself a JSON-encoded string: {"result": "..."}
wrapper = json.loads(outer[0]['text'])
result_str = wrapper['result']

m = re.search(r'<untrusted-data-[^>]+>\s*(\[[\s\S]*?\])\s*</untrusted-data-', result_str)
if not m:
    raise SystemExit("Could not find untrusted-data JSON array. Preview: " + result_str[:400])
inner_json = m.group(1).strip()
rows = json.loads(inner_json)
if rows and isinstance(rows[0], str):
    raise SystemExit("Unexpected: rows contains strings, not dicts. Inner JSON preview: " + inner_json[:400])
print(f"Rows loaded: {len(rows)}")

def fix_mojibake(s: str) -> str:
    try:
        return s.encode('latin-1').decode('utf-8')
    except (UnicodeDecodeError, UnicodeEncodeError):
        return s

fixed_pairs = []
no_change = 0
still_mojibake = 0
for r in rows:
    old = r['name']
    new = fix_mojibake(old)
    if new == old:
        no_change += 1
        continue
    if re.search(r'Ã[^\s]', new):
        still_mojibake += 1
    fixed_pairs.append((r['id'], old, new))

print(f"Successfully fixed (name changed): {len(fixed_pairs)}")
print(f"Unchanged (fix no-op): {no_change}")
print(f"Still contains mojibake after fix: {still_mojibake}")
print()

random.seed(42)
sample = random.sample(fixed_pairs, min(20, len(fixed_pairs)))
print("=== 20 AMOSTRAS ALEATORIAS (antes -> depois) ===")
for i, (pid, old, new) in enumerate(sample, 1):
    # Use sys.stdout.buffer for utf-8 output on Windows
    line = f"{i:2d}. OLD: {old}\n    NEW: {new}\n"
    sys.stdout.buffer.write(line.encode('utf-8'))
print()

out_path = r"C:\Users\danil\Desktop\projetosflutter\bora_app\.claude\.ai\reports\mercadona_encoding_fixes.json"
os.makedirs(os.path.dirname(out_path), exist_ok=True)
with open(out_path, 'w', encoding='utf-8') as f:
    json.dump([{"id": p, "old": o, "new": n} for p, o, n in fixed_pairs], f, ensure_ascii=False, indent=2)
print(f"Saved {len(fixed_pairs)} fix pairs to: {out_path}")

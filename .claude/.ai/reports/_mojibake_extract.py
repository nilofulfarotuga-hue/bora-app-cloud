import json, re, sys, os
from collections import Counter

path = r"C:\Users\danil\.claude\projects\C--Users-danil-Desktop-projetosflutter\ba7df694-d9dd-4c8d-abf7-94a4102763fe\tool-results\mcp-supabase-execute_sql-1776628390484.txt"

with open(path, 'r', encoding='utf-8') as f:
    raw = f.read()
outer = json.loads(raw)
wrapper = json.loads(outer[0]['text'])
result_str = wrapper['result']
m = re.search(r'<untrusted-data-[^>]+>\s*(\[[\s\S]*?\])\s*</untrusted-data-', result_str)
rows = json.loads(m.group(1).strip())
print(f"Total mojibake products: {len(rows)}")

# Extract unique words containing Ã
word_counter = Counter()
for r in rows:
    for w in r['name'].split():
        # strip trailing punctuation
        core = re.sub(r'^[^\w]+|[^\w%]+$', '', w, flags=re.UNICODE)
        if 'Ã' in core:
            word_counter[core] += 1

unique_mojibake_words = len(word_counter)
print(f"Unique mojibake words: {unique_mojibake_words}")
print()

print("=== TOP 60 MOJIBAKE WORDS BY FREQUENCY ===")
for word, n in word_counter.most_common(60):
    line = f"{n:4d}  {word}\n"
    sys.stdout.buffer.write(line.encode('utf-8'))

# Save full list for review
out_path = r"C:\Users\danil\Desktop\projetosflutter\bora_app\.claude\.ai\reports\_mojibake_words_all.json"
with open(out_path, 'w', encoding='utf-8') as f:
    json.dump(word_counter.most_common(), f, ensure_ascii=False, indent=2)
print(f"\nSaved full frequency list to: {out_path}")

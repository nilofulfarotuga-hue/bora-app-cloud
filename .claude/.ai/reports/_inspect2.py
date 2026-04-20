import json, re
path = r"C:\Users\danil\.claude\projects\C--Users-danil-Desktop-projetosflutter\ba7df694-d9dd-4c8d-abf7-94a4102763fe\tool-results\mcp-supabase-execute_sql-1776628390484.txt"
with open(path, 'r', encoding='utf-8') as f:
    raw = f.read()
outer = json.loads(raw)
wrapper = json.loads(outer[0]['text'])
result_str = wrapper['result']
print("result_str first 500:")
print(repr(result_str[:500]))
print("---")
print("result_str around char 300-800:")
print(repr(result_str[300:800]))
print("---")
m = re.search(r'<untrusted-data-[^>]+>([\s\S]*?)</untrusted-data-', result_str)
print("match:", bool(m))
if m:
    print("match group length:", len(m.group(1)))
    print("match group first 200:", repr(m.group(1)[:200]))

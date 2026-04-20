import json
path = r"C:\Users\danil\.claude\projects\C--Users-danil-Desktop-projetosflutter\ba7df694-d9dd-4c8d-abf7-94a4102763fe\tool-results\mcp-supabase-execute_sql-1776628390484.txt"
with open(path, 'r', encoding='utf-8') as f:
    raw = f.read()
print("File size:", len(raw))
print("First 300 chars:")
print(repr(raw[:300]))
print("---")
print("Last 200 chars:")
print(repr(raw[-200:]))

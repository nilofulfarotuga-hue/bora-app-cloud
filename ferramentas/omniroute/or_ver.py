#!/usr/bin/env python3
"""Resume linhas JSON das provas (or_prova*.py) numa linha cada: http, ms, pedido, quem decidiu, resposta."""
import json
import sys

for linha in sys.stdin:
    linha = linha.rstrip()
    try:
        d = json.loads(linha)
    except Exception:
        print(linha[:300])
        continue
    q = d.get("quem") or {}
    dec = (q.get("x-omniroute-decision") or "").replace("strategy=", "")
    print(d.get("http"), d.get("ms"), "ms", d.get("pedido"), "|", dec[:120], "|", str(d.get("resposta"))[:80])

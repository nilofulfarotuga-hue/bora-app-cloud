# -*- coding: utf-8 -*-
"""Prova dos combos do OmniRoute depois do porteiro (31/10). Le a chave do .env sem a imprimir."""
import json
import time
import urllib.request

chave = ""
for ln in open("/opt/data/.env", encoding="utf-8"):
    if ln.startswith("OMNIROUTE_API_KEY="):
        chave = ln.split("=", 1)[1].strip().strip('"').strip("'")
for url in ("http://127.0.0.1:20128/v1/chat/completions", "http://172.16.1.1:20128/v1/chat/completions"):
    try:
        urllib.request.urlopen(urllib.request.Request(url.replace("/chat/completions", "/models"), headers={"Authorization": "Bearer " + chave}), timeout=5)
        base = url
        break
    except Exception as e:  # noqa: BLE001
        base = None
        if "HTTP Error" in str(e):
            base = url
            break
print("omniroute em", base)
for combo in ("agentes", "privado", "rapido", "volume"):
    corpo = {"model": combo, "max_tokens": 120, "messages": [{"role": "user", "content": "Numa frase curta em portugues de Portugal: o Bora entrega na Guarda?"}]}
    t0 = time.time()
    try:
        req = urllib.request.Request(base, data=json.dumps(corpo).encode(), headers={"Content-Type": "application/json", "Authorization": "Bearer " + chave})
        with urllib.request.urlopen(req, timeout=90) as r:
            d = json.loads(r.read().decode())
        txt = (d.get("choices") or [{}])[0].get("message", {}).get("content", "")
        print("%-8s %5d ms modelo=%s | %s" % (combo, int((time.time() - t0) * 1000), d.get("model"), (txt or "").replace("\n", " ")[:90]))
    except Exception as e:  # noqa: BLE001
        print("%-8s ERRO %s" % (combo, str(e)[:160]))

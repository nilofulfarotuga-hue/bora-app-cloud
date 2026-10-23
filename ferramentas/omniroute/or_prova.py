#!/usr/bin/env python3
"""Prova por nivel (omniroute-23-10): chama cada modelo SOZINHO pelo OmniRoute, sem combo,
para que nenhum recuo esconda um nivel morto. Uso: or_prova.py [--ferramentas] modelo1 modelo2 ...
Imprime: modelo pedido, codigo HTTP, latencia, quem respondeu (cabecalhos/model), e o texto curto.
"""
import json
import sys
import time
import urllib.error
import urllib.request

BASE = "http://127.0.0.1:20128/v1/chat/completions"
KEY = open("/opt/omniroute/.agentes.key").read().strip()
FERR = "--ferramentas" in sys.argv
modelos = [a for a in sys.argv[1:] if not a.startswith("--")]

TOOLS = [{"type": "function", "function": {
    "name": "hora_lisboa", "description": "Devolve a hora actual em Lisboa.",
    "parameters": {"type": "object", "properties": {}, "required": []}}}]

for m in modelos:
    corpo = {"model": m, "max_tokens": 400, "stream": False,
             "messages": [{"role": "user", "content":
                           "Que horas sao em Lisboa? Usa a ferramenta." if FERR else
                           "Responde numa frase curta em portugues: qual e a capital de Portugal?"}]}
    if FERR:
        corpo["tools"] = TOOLS
    if "--grande" in sys.argv:  # simula o tamanho de um pedido real do Hermes (~10 mil tokens)
        enchimento = ("Nota de contexto sem importancia para a pergunta. " * 700)
        corpo["messages"].insert(0, {"role": "system", "content": enchimento})
    req = urllib.request.Request(BASE, data=json.dumps(corpo).encode(), method="POST")
    req.add_header("Content-Type", "application/json")
    req.add_header("Authorization", "Bearer " + KEY)
    req.add_header("X-OmniRoute-No-Cache", "true")  # a cache tambem mascara um nivel morto
    t0 = time.time()
    try:
        with urllib.request.urlopen(req, timeout=180) as r:
            st, txt, hd = r.status, r.read().decode("utf-8", "replace"), r.headers
    except urllib.error.HTTPError as e:
        st, txt, hd = e.code, e.read().decode("utf-8", "replace"), e.headers
    except Exception as e:  # rede, tempo
        st, txt, hd = 0, str(e), {}
    ms = int((time.time() - t0) * 1000)
    quem = {k: v for k, v in (hd.items() if hasattr(hd, "items") else []) if k.lower().startswith("x-omniroute") or k.lower() in ("x-provider", "x-model")}
    resumo = txt[:220]
    try:
        d = json.loads(txt)
        ch = (d.get("choices") or [{}])[0].get("message", {})
        tc = ch.get("tool_calls")
        resumo = ("TOOL_CALL " + tc[0]["function"]["name"]) if tc else (ch.get("content") or "")[:160].replace("\n", " ")
        quem["model"] = d.get("model")
    except Exception:
        pass
    print(json.dumps({"pedido": m, "http": st, "ms": ms, "quem": quem, "resposta": resumo}, ensure_ascii=False))

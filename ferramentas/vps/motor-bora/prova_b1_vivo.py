# Prova viva do B1 (01/11/2026): 3 chamadas P3 seguidas pelo Claude; simular "sem saldo" -> gratis; voltar -> Claude.
import json
import sys
import time
import urllib.request

BASE = "http://127.0.0.1:8792"


def post(caminho, corpo, origem="prova-b1"):
    req = urllib.request.Request(BASE + caminho, data=json.dumps(corpo).encode(), method="POST",
                                 headers={"Content-Type": "application/json", "X-Motor-Origem": origem})
    t0 = time.time()
    try:
        with urllib.request.urlopen(req, timeout=120) as r:
            return r.status, json.load(r), int((time.time() - t0) * 1000)
    except urllib.error.HTTPError as e:
        return e.code, {"erro": e.read()[:200].decode("utf-8", "replace")}, int((time.time() - t0) * 1000)


def conversa(perfil, texto, origem):
    st, d, ms = post("/v1/chat/completions", {"model": "perfil:" + perfil, "messages": [{"role": "user", "content": texto}], "max_tokens": 30}, origem)
    m = d.get("motor") or {}
    resp = ((d.get("choices") or [{}])[0].get("message") or {}).get("content", "")
    print("%-14s HTTP %s %5d ms fornecedor=%s modelo=%s resposta=%r" % (perfil, st, ms, m.get("fornecedor"), m.get("modelo"), (resp or "")[:60]))
    return m.get("fornecedor")


modo = sys.argv[1] if len(sys.argv) > 1 else "tudo"
if modo in ("tudo", "p3"):
    print("== 3 chamadas P3 seguidas (claude-volume / claude-agente) ==")
    for i, p in enumerate(("claude-volume", "claude-agente", "claude-volume"), 1):
        conversa(p, "Responde so: OK-P3-%d" % i, "prova-b1-p3")
if modo in ("tudo", "simular"):
    print("== simular sem saldo ==")
    print(post("/porteiro/simular", {"sem_saldo": True})[1].get("simular"))
    f = conversa("claude-volume", "Responde so: OK-GRATIS", "prova-b1-semsaldo")
    print("sem saldo -> foi ao gratis:", f not in (None, "claude"))
    print(post("/porteiro/simular", {"sem_saldo": False})[1].get("simular"))
    f = conversa("claude-volume", "Responde so: OK-VOLTOU", "prova-b1-voltou")
    print("fim da simulacao -> voltou ao Claude:", f == "claude")

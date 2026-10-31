# -*- coding: utf-8 -*-
"""Prova ao vivo do porteiro no Motor Bora (127.0.0.1:8792). Nao imprime chaves.
    python3 prova_porteiro_vivo.py              # pedidos normais a cada perfil claude-* + chat-rapido
    python3 prova_porteiro_vivo.py simular      # sem saldo simulado + parte do dia esgotada, e volta ao normal
"""
import json
import sys
import time
import urllib.request

M = "http://127.0.0.1:8792"
SIS = ("Es o assistente do Boom Burger na Guarda. Entrega 2,50 EUR ate 4 km e mais 0,50 EUR por km a seguir. "
       "Nunca inventes precos que nao estao no menu. Responde em portugues de Portugal, curto.")


def post(caminho, corpo, timeout=60):
    req = urllib.request.Request(M + caminho, data=json.dumps(corpo).encode(), method="POST",
                                 headers={"Content-Type": "application/json", "X-Motor-Origem": "prova-porteiro-31-10"})
    t0 = time.time()
    try:
        with urllib.request.urlopen(req, timeout=timeout) as r:
            return r.status, json.loads(r.read().decode()), int((time.time() - t0) * 1000)
    except urllib.error.HTTPError as e:
        return e.code, json.loads(e.read().decode() or "{}"), int((time.time() - t0) * 1000)


def get(caminho):
    with urllib.request.urlopen(M + caminho, timeout=20) as r:
        return json.loads(r.read().decode())


def pergunta(perfil, texto):
    st, d, ms = post("/v1/chat/completions", {"model": "perfil:" + perfil, "max_tokens": 300,
                                              "messages": [{"role": "system", "content": SIS}, {"role": "user", "content": texto}]})
    mot = d.get("motor") or {}
    port = mot.get("porteiro") or next((t.get("porteiro") for t in (mot.get("tentativas") or []) if isinstance(t, dict) and t.get("porteiro")), None) or {}
    resp = ((d.get("choices") or [{}])[0].get("message") or {}).get("content") or (d.get("error") or {}).get("message", "")
    print("%-18s HTTP %s %5d ms | motor=%s:%s | porteiro=%s (%s) | %s" % (
        perfil, st, ms, mot.get("fornecedor"), mot.get("modelo"), port.get("decisao"), (port.get("porque") or "")[:70], resp.replace("\n", " ")[:110]))
    return st, ms, mot, port


if len(sys.argv) > 1 and sys.argv[1] == "simular":
    print("== saldo acabado SIMULADO so no porteiro (nada na Console)")
    print(post("/porteiro/simular", {"sem_saldo": True})[1]["decisoes"])
    pergunta("claude-cliente", "Quanto custa a entrega a 6 km?")
    print("== parte do dia esgotada (P3) simulada; P1 continua")
    est = get("/porteiro")["contas"]
    print(post("/porteiro/simular", {"sem_saldo": False, "gasto_hoje_extra_usd": round(est["parte_do_dia_usd"] * 0.6, 4)})[1]["decisoes"])
    pergunta("claude-agente", "Resume numa frase: o Bora entrega na Guarda.")
    pergunta("claude-cliente", "Boa tarde, quanto custa a entrega ate 4 km?")
    print("== volta ao normal")
    print(post("/porteiro/simular", {"sem_saldo": False, "gasto_hoje_extra_usd": 0})[1]["decisoes"])
    sys.exit(0)

e = get("/porteiro")
print("porteiro: tem_chave=%s ligado=%s dormido_ate=%s contas=%s" % (e["tem_chave"], e["ligado"], e["dormido_ate"], json.dumps(e["contas"])))
for perfil, txt in (("claude-cliente", "Boa tarde! Quanto custa a entrega ate 4 km?"), ("claude-classificar", "Isto e negocio ou pessoal: 'quero 2 smash'?"),
                    ("claude-decisao", "Numa frase: devo responder ja a um cliente com pedido atrasado?"), ("claude-agente", "Resume numa frase: o Bora entrega na Guarda."),
                    ("claude-volume", "Diz so: ok"), ("chat-rapido", "E se for a 6 km, quanto fica?")):
    pergunta(perfil, txt)

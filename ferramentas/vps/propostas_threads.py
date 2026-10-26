#!/usr/bin/env python3
"""Lê no Gmail da Bora (token do carteiro) as conversas dos contactados da linha
"Propostas diárias" (missão geral-sabado-24-10, bloco 6). Só lê.

Para cada thread_id: assunto, Message-ID da ÚLTIMA mensagem nossa (para o último
seguimento sair no mesmo fio), quantas mensagens são de fora (resposta) e se há
devolução (mailer-daemon / Delivery Status Notification).
Uso: python3 propostas_threads.py <contactados.csv> > saida.json
"""
import csv
import json
import sys

sys.path.insert(0, "/opt/data/rotinas")
import carteiro_caca as c  # noqa: E402

CONTA = c.CONTA.lower()
saida = []
for r in csv.DictReader(open(sys.argv[1], encoding="utf-8")):
    t = (r.get("thread_id") or "").strip()
    item = {"slug": r["slug"], "email": r["email"], "thread_id": t}
    if not t:
        item["erro"] = "sem thread_id"
        saida.append(item)
        continue
    try:
        th = c.gmail("GET", "threads/%s?format=metadata&metadataHeaders=Subject&metadataHeaders=From"
                     "&metadataHeaders=Message-ID" % t)
        msgs = th.get("messages", [])
        nossas = [m for m in msgs if CONTA in c.cabecalho(m, "From").lower()]
        fora = [m for m in msgs if CONTA not in c.cabecalho(m, "From").lower()]
        devol = [m for m in fora if any(k in c.cabecalho(m, "From").lower() for k in ("mailer-daemon", "postmaster"))
                 or "delivery status" in c.cabecalho(m, "Subject").lower()]
        item.update({
            "assunto": c.cabecalho(msgs[0], "Subject") if msgs else "",
            "mensagens": len(msgs), "nossas": len(nossas),
            "respostas": len(fora) - len(devol), "devolucoes": len(devol),
            "ultima_nossa_msgid": c.cabecalho(nossas[-1], "Message-ID") if nossas else "",
            "resposta_de": [c.cabecalho(m, "From") for m in fora if m not in devol][:2],
        })
    except Exception as e:  # noqa: BLE001
        item["erro"] = str(e)[:200]
    saida.append(item)
print(json.dumps(saida, ensure_ascii=False, indent=1))

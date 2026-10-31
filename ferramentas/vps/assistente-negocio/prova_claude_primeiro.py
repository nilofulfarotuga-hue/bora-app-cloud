# -*- coding: utf-8 -*-
"""Prova (31/10) do assistente das lojas com o porteiro a frente: 3 mensagens + classificador.
Chamadas diretas a motores.conversar com a cadeia REAL do Boom (lida da tabela assistant_tenants pelo db do
assistente). Nao cria pedidos, nao envia WhatsApp, nao escreve em tabelas.  cd /opt/assistente-negocio && python3 /tmp/prova_claude_primeiro.py
"""
import os
import sys
import time

sys.path.insert(0, "/opt/assistente-negocio")
from servidor import carregar_env  # noqa: E402
carregar_env(os.path.join("/opt/assistente-negocio", ".env"))
import assistente as A  # noqa: E402
import db  # noqa: E402
import motores  # noqa: E402

t = db.ler("assistant_tenants", "slug=eq.boom-burger", "id,slug,nome,mode,motor,motores_reserva")[0]
cad = A.cadeia_de(t)
print("tenant", t["slug"], "mode", t["mode"], "| cadeia na tabela:", cad)
SIS = ("Es o assistente do Boom! Burger na Guarda (WhatsApp). Entrega ao domicilio: 2,50 EUR ate 4 km; acima disso mais "
       "0,50 EUR por cada km. Pagamento em dinheiro ate 40 EUR. Nunca inventes precos de produtos: se nao sabes, diz que vais "
       "confirmar. Portugues de Portugal, curto e simpatico.")
casos = [("Boa tarde! Quanto custa a entrega ate 4 km?", "2,50"), ("E se for a 6 km, quanto fica?", "3,50"),
         ("Quanto custa o hamburguer Trufado Imperial?", None)]
hist = [{"role": "system", "content": SIS}]
for texto, esperado in casos:
    hist.append({"role": "user", "content": texto})
    t0 = time.time()
    msg, meta = motores.conversar(cad, hist)
    ms = int((time.time() - t0) * 1000)
    resp = (msg.get("content") or "").replace("\n", " ")
    if esperado:
        certo = esperado in resp
    else:
        certo = not any(c.isdigit() for c in resp.split("confirm")[0][-60:]) and ("confirm" in resp.lower() or "verific" in resp.lower())
    por = meta.get("porteiro") or {}
    print("%s %5d ms | motor=%s via=%s | porteiro=%s (%s) | %s" % ("CERTO " if certo else "ERRADO", ms, meta.get("motor"), meta.get("via"),
          por.get("decisao"), (por.get("porque") or "")[:60], resp[:140]))
    hist.append({"role": "assistant", "content": msg.get("content") or ""})

tipo, meta = A.classificar(t, {"historico": []}, "Queria 2 smash duplos para levantar as 20h", True)
print("classificador: %s | motor=%s | porteiro=%s" % (tipo, (meta or {}).get("motor"), ((meta or {}).get("porteiro") or {}).get("porque")))
tipo, meta = A.classificar(t, {"historico": []}, "Mano logo ha jantar la em casa da mae, vens?", True)
print("classificador: %s | motor=%s" % (tipo, (meta or {}).get("motor")))

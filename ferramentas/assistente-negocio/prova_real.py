"""Prova real (sem simulacao): o assistente poe UMA mensagem na fila para um numero da allowlist e
espera pelo aviso de entrega da propria WhatsApp (status 3/4 -> entrega_estado entregue/visto).

Uso: python3 prova_real.py <numero> "<texto>"   (so aceita numeros da allowlist do tenant)"""
import os
import sys
import time

AQUI = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, AQUI)
from servidor import carregar_env  # noqa: E402

carregar_env(os.environ.get("ASSISTENTE_ENV", os.path.join(AQUI, ".env")))
import assistente as A  # noqa: E402
import db  # noqa: E402

numero, texto = A.so_digitos(sys.argv[1]), sys.argv[2]
t = db.ler("assistant_tenants", "slug=eq.mister-navalha")[0]
linha = A.enfileirar(t, numero, texto, "prova_real")
if not linha:
    print("BLOQUEADO: numero fora da allowlist — nada foi enviado")
    sys.exit(2)
print("NA FILA id", linha["id"])
for _ in range(40):
    time.sleep(3)
    m = db.ler("assistant_messages", f"id=eq.{linha['id']}", "entrega_estado,msg_id_wa,enviada_em,entrega_erro")[0]
    if m["entrega_estado"] in ("entregue", "visto", "falhou", "nao-decifrada", "bloqueado"):
        break
print("RESULTADO", m)

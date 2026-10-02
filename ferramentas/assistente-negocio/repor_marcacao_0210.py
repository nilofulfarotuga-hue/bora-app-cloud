"""Uso unico, 02/10/2026: repoe a marcacao de teste que o Danilo fez do telemovel (Corte, sabado 03/10 14:30)
e que a limpeza geral das simulacoes cancelou por engano as 11:56. Sem novo aviso ao parceiro (ja o teve as 09:05)."""
import datetime as dt
import os
import sys

AQUI = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, AQUI)
from servidor import carregar_env  # noqa: E402

carregar_env(os.environ.get("ASSISTENTE_ENV", os.path.join(AQUI, ".env")))
import assistente as A  # noqa: E402
import db  # noqa: E402

t = db.ler("assistant_tenants", "slug=eq.mister-navalha")[0]
corte = next(s for s in A.servicos(t) if s["name"] == "Corte")
inicio = dt.datetime(2026, 10, 3, 14, 30, tzinfo=A.LX)
ja = [m for m in db.rpc("assistente_minhas_marcacoes", {"p_tenant": t["id"], "p_telefone": "351931992662"})
      if A.hora_local(m["inicio"]) == inicio]
if ja:
    print("JA EXISTE", ja)
else:
    print(db.rpc("assistente_marcar_v2", {"p_tenant": t["id"], "p_servico_id": corte["id"], "p_inicio": A.iso(inicio),
                                          "p_nome": "Danilo", "p_telefone": "+351931992662", "p_teste": True,
                                          "p_notificar": False}))

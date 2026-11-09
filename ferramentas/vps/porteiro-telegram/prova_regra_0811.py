#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Prova da regra do Danilo de 08/11/2026 no porteiro (missao m6-crescimento-hermes-2026-11-08).

Corre NA VPS, ao lado do porteiro.py novo, sem enviar nada a ninguem:
  1) passa pela regra antiga e pela nova todos os textos que entraram em public.porteiro_entrada nos ultimos 8 dias
     (so leitura) e conta quantos eram URGENTE antes e quantos sao agora, por titulo;
  2) as 3 mensagens de teste em ensaio (decide sem enviar): radar-jai banal, radar-jai com jornalista, pedido novo;
  3) o vigia dos 10 min contra linhas reais da base (so leitura), sem enviar o alerta.
Uso: python3 prova_regra_0811.py /caminho/para/porteiro_novo.py
"""
import collections
import datetime
import importlib.util
import json
import sys

caminho = sys.argv[1] if len(sys.argv) > 1 else "/opt/data/voz/porteiro.py"
spec = importlib.util.spec_from_file_location("porteiro_novo", caminho)
p = importlib.util.module_from_spec(spec)
spec.loader.exec_module(p)

print("== 1) avisos reais dos ultimos 8 dias (porteiro_entrada) ==")
desde = (datetime.datetime.now(datetime.timezone.utc) - datetime.timedelta(days=8)).strftime("%Y-%m-%dT%H:%M:%S")
linhas = p._supa("GET", "porteiro_entrada?select=origem,nivel,texto&tratado_em=gte.%s&order=id.asc&limit=2000" % desde) or []
antes, depois, mudou = collections.Counter(), collections.Counter(), collections.Counter()
for x in linhas:
    t, nv, o = x.get("texto") or "", x.get("nivel"), x.get("origem") or "notify-admin-urgent"
    a = p._decidir_nivel_antigo(t, nv, o)[0]
    d = p.decidir_nivel(t, nv, o)[0]
    antes[a] += 1
    depois[d] += 1
    if a != d:
        tit = t.splitlines()[0][:48] if t else "?"
        for k in ("PEDIDO NOVO", "CORRIDA TVDE", "Novo CLIENTE", "Reconciliador", "LIGAR", "LIMPEZA NOVA", "zona-vermelha"):
            if k.lower() in t.lower():
                tit = k
                break
        mudou["%s -> %s | %s" % (a, d, tit)] += 1
print("total", len(linhas), "| antes:", dict(antes), "| depois:", dict(depois))
for k, v in mudou.most_common(15):
    print("  %3d  %s" % (v, k))
ficam = collections.Counter()
for x in linhas:
    t = x.get("texto") or ""
    if p.decidir_nivel(t, x.get("nivel"), x.get("origem") or "notify-admin-urgent")[0] == "URGENTE":
        ficam[t.splitlines()[0][:60] if t else "?"] += 1
print("continuam URGENTE (titulo -> n):")
for k, v in ficam.most_common(12):
    print("  %3d  %s" % (v, k))

print("\n== 2) as 3 mensagens de teste (ensaio: decide e NAO envia) ==")
testes = [
    ("radar-jai", None, "🟠 RADAR JAI — resumo do dia\n2 urgente(s): 1 pedido de plataforma, 1 item na fila de aprovacao. "
                        "Aprova ou recusa com python ver-fila.py."),
    ("radar-jai", None, "📩 RESPOSTA de jornalista: ndtv.com — Re: About Jai Agarwal, Guarda FC\n\nDe: sports@ndtv.com"),
    ("notify-admin-urgent", "URGENTE", "🛎️ PEDIDO NOVO — Cliente Exemplo · 912000000\nLoja: Burger King\n12.30 EUR · MB WAY\n"
                                      "Quando: agora\n#56fa8623"),
]
for o, nv, t in testes:
    r = p.telegram_danilo(t, nv, o, ensaio=True)
    print(json.dumps({"origem": o, "pedido": nv, "nivel": r["nivel"], "porque": r["porque"], "destino": r["destino"],
                      "voz": r["voz"], "vigia_10min": r.get("vigia_10min")}, ensure_ascii=False))

print("\n== 3) vigia dos 10 min contra a base (so leitura, sem alerta) ==")
agora_ = p.agora()
casos = []
o = p._supa("GET", "orders?select=id,status,assigned_driver_id,scheduled_for&status=eq.delivered&order=created_at.desc&limit=1") or []
if o:
    casos.append(("pedido entregue", o[0]["id"][:8], "🛎️ PEDIDO NOVO — X\n#" + o[0]["id"][:8]))
tv = p._supa("GET", "tvde_rides?select=id,status,driver_id,scheduled_at&status=eq.sem_motorista&order=created_at.desc&limit=1") or []
if tv:
    casos.append(("corrida sem motorista", str(tv[0]["id"])[:8], "🚗 CORRIDA TVDE AGORA — X\n#" + str(tv[0]["id"])[:8]))
cb = p._supa("GET", "cleaning_bookings?select=id,status,cleaner_id,scheduled_at&order=created_at.desc&limit=1") or []
if cb:
    casos.append(("limpeza mais recente", str(cb[0]["id"])[:8], "🧹 LIMPEZA NOVA — X\n#" + str(cb[0]["id"])[:8]))
for nome, id8, texto in casos:
    it = p.novo_para_vigiar(texto)
    it.update(desde=(agora_ - datetime.timedelta(minutes=11)).isoformat(timespec="seconds"))
    ls = p._supa("GET", "%s?select=id,status,%s,%s&%s&limit=1" % (it["tabela"], it["quem"], it["hora"], p._filtro_id(id8))) or []
    acao, motivo, novo = p.vigia_verificar(it, ls[0] if ls else None, agora_)
    print(json.dumps({"caso": nome, "tabela": it["tabela"], "id8": id8, "encontrado": bool(ls), "acao": acao,
                      "motivo": motivo, "alerta_seria": p.texto_alerta_vigia(it, agora_) if acao == "alertar" else None,
                      "alerta_seria_urgente": (p.decidir_nivel(p.texto_alerta_vigia(it, agora_), "URGENTE", "vigia-10min")[0]
                                               if acao == "alertar" else None)}, ensure_ascii=False))

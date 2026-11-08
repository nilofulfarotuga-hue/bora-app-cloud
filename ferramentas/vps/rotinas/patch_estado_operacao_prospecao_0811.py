#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Missao m6-crescimento-hermes-2026-11-08: acrescenta a seccao "prospecao" ao /opt/data/estado-operacao.txt.

Porque: o vendedor e o vendedor-servicos do Hermes responderam "nao ha lista de alvos" / "NAO SEI" 7 dias seguidos
(agentes_corridas 01-07/11), porque a lista da caca-clientes vive na base (prospects_presenca, prospect_propostas)
e nao no disco. Com esta seccao passam a ler numeros reais. Patch por ancora: falha se a ancora nao existir.
Uso (na VPS): python3 patch_estado_operacao_prospecao_0811.py /opt/data/rotinas/estado_operacao.py
"""
import sys

FUNC = '''

def olhar_prospecao():
    """Prospecao (missao m6 08/11): a lista do vendedor vive na base (caca-clientes), nao no disco."""
    out = ["== prospecao (caca-clientes: prospects_presenca e prospect_propostas) =="]
    erro = False
    r = E.rest("prospects_presenca?select=estado,ultimo_contacto_em,resposta,nome&limit=3000")
    if _ok(r):
        por = dict()
        for x in r:
            k = x.get("estado") or "sem estado"
            por[k] = por.get(k, 0) + 1
        corte = (agora_utc() - datetime.timedelta(days=7)).strftime("%Y-%m-%dT%H:%M:%S")
        c7 = len([x for x in r if (x.get("ultimo_contacto_em") or "")[:19] >= corte])
        resp = [x for x in r if (x.get("resposta") or "").strip() or x.get("estado") in ("respondeu", "recusou", "interessado")]
        out.append("  negocios na lista: %d" % len(r))
        out.append("  por estado: " + ", ".join("%s %d" % (k, v) for k, v in sorted(por.items(), key=lambda p: -p[1])))
        out.append("  contactados nos ultimos 7 dias: %d" % c7)
        out.append("  com resposta (desde o inicio): %d" % len(resp))
        for x in resp[:5]:
            out.append("    - %s (%s): %s" % (x.get("nome"), x.get("estado"), " ".join((x.get("resposta") or "").split())[:80]))
    else:
        out.append("  NAO CONSEGUI LER prospects_presenca.")
        erro = True
    r = E.rest("prospect_propostas?select=estado,enviado_em&limit=3000")
    if _ok(r):
        d1 = (agora_utc() - datetime.timedelta(days=1)).strftime("%Y-%m-%dT%H:%M:%S")
        d7 = (agora_utc() - datetime.timedelta(days=7)).strftime("%Y-%m-%dT%H:%M:%S")
        saidas = [x for x in r if x.get("enviado_em")]
        out.append("  propostas enviadas: total %d, ultimas 24 h %d, ultimos 7 dias %d" % (
            len(saidas), len([x for x in saidas if x["enviado_em"][:19] >= d1]),
            len([x for x in saidas if x["enviado_em"][:19] >= d7])))
        out.append("  propostas prontas por enviar: %d, rascunhos: %d, responderam: %d" % (
            len([x for x in r if x.get("estado") == "pronta"]), len([x for x in r if x.get("estado") == "rascunho"]),
            len([x for x in r if x.get("estado") == "respondeu"])))
        out.append("  rotina: cacador 07:30, redator 08:00, envio 09:40, so dias uteis (sabado e domingo param de proposito).")
    else:
        out.append("  NAO CONSEGUI LER prospect_propostas.")
        erro = True
    return out, erro
'''

caminho = sys.argv[1]
s = open(caminho, encoding="ascii").read()
if "def olhar_prospecao" in s:
    print("ja estava")
    sys.exit(0)
ancora = "\n\ndef main():"
a2 = "for fn in (olhar_parceiros, olhar_cobranca, olhar_qualidade):"
if s.count(ancora) != 1 or s.count(a2) != 1:
    raise SystemExit("ANCORA NAO ENCONTRADA - nada mudou")
s = s.replace(ancora, FUNC + ancora).replace(a2, "for fn in (olhar_parceiros, olhar_cobranca, olhar_qualidade, olhar_prospecao):")
open(caminho, "w", encoding="ascii").write(s)
print("ok")

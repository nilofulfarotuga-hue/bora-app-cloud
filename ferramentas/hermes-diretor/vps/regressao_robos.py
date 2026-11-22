#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
regressao_robos.py — a regressao dos robos (missao hermes-diretor-2026-11-20, B6.4).

Antes de mudar a alma, uma skill ou o prompt de um robo, correm-se TODAS as perguntas que ja falharam (os
casos de teste). Se alguma piorar, sai com codigo 1: nao se publica e volta ao fiscal.

Casos: ficheiro casos_<robo>.json ao lado deste script + a tabela robos_casos_teste (quando existir).
Hoje sabe perguntar ao Hermes (perfil principal, pelo CLI). Os robos das Edge Functions (suporte e Amigo)
ainda nao tem corredor aqui: os casos deles ficam guardados e contam como "nunca corridos".

  regressao_robos.py hermes              corre os casos do Hermes
  regressao_robos.py hermes --prova-ma   prova que apanha uma resposta ma (resposta inventada, sem chamar o robo)
Corre no HOST como root.
"""
import json
import os
import re
import subprocess
import sys
import time
import unicodedata

sys.path.insert(0, "/opt/data/rotinas")
import despachante as D  # noqa: E402

AQUI = os.path.dirname(os.path.abspath(__file__))
C = "hermes-agent-fvnc-hermes-agent-1"
PRE = ("TESTE DE REGRESSAO (quem pergunta e o fiscal, nao o Danilo). E so uma pergunta: responde em 2 a 5 linhas, com as "
       "tuas regras. Nao mandes nada a ninguem, nao pecas autorizacao a serio e nao mudes dados. Pergunta: ")


def norm(t):
    t = unicodedata.normalize("NFKD", t or "").encode("ascii", "ignore").decode().lower()
    return re.sub(r"\s+", " ", t)


def avaliar(resposta, caso):
    r = norm(resposta)
    faltam = [x for x in caso.get("deve_conter") or [] if norm(x) not in r]
    proibidas = [x for x in caso.get("nao_pode_conter") or [] if norm(x) in r]
    return (not faltam and not proibidas and bool(r.strip())), faltam, proibidas


def perguntar_hermes(pergunta):
    cmd = ["docker", "exec", "-u", "hermes", "-e", "HOME=/opt/data", C, "sh", "-lc", 'cd /opt/data && exec hermes -z "$1"', "_", PRE + pergunta]
    r = subprocess.run(cmd, capture_output=True, text=True, timeout=240)
    return (r.stdout or "").strip() or (r.stderr or "").strip()


def casos_de(robo):
    casos = []
    f = os.path.join(AQUI, "casos_%s.json" % robo)
    if os.path.isfile(f):
        casos += [dict(c, origem="ficheiro") for c in json.load(open(f, encoding="utf-8"))]
    tabela = D._rest("robos_casos_teste?robo=eq.%s&ativo=is.true&select=id,pergunta,deve_conter,nao_pode_conter" % robo)
    casos += [dict(c, origem="tabela") for c in (tabela or [])]
    return casos


def main():
    robo = next((a for a in sys.argv[1:] if not a.startswith("--")), "hermes")
    casos = casos_de(robo)
    if "--prova-ma" in sys.argv:
        caso = casos[0]
        ma = "Sim, faco ja o reembolso de 5 euros, o reembolso esta feito."
        ok, faltam, proibidas = avaliar(ma, caso)
        print("PROVA: resposta ma de proposito -> %s (faltou %s; proibido %s)" % ("PASSOU (mau: a regressao nao apanhou!)" if ok else "FALHOU, como devia", faltam, proibidas))
        return 0 if not ok else 1
    if robo != "hermes":
        print("O robo %s ainda nao tem corredor de regressao aqui: %d caso(s) guardado(s), nunca corridos." % (robo, len(casos)))
        return 0
    passou, falhou = 0, []
    for i, caso in enumerate(casos, 1):
        t0 = time.time()
        try:
            resposta = perguntar_hermes(caso["pergunta"])
        except Exception as e:  # noqa: BLE001
            resposta = "ERRO: %s" % e
        ok, faltam, proibidas = avaliar(resposta, caso)
        passou += 1 if ok else 0
        if not ok:
            falhou.append(i)
        print("%s caso %d (%d s): %s%s" % ("PASSOU" if ok else "FALHOU", i, time.time() - t0, caso["pergunta"][:70],
                                           "" if ok else " | faltou %s | proibido %s | resposta: %s" % (faltam, proibidas, resposta[:160].replace("\n", " "))))
        if caso.get("id"):
            D._rest("rpc/robo_caso_resultado", "POST", {"p_id": caso["id"], "p_passou": ok, "p_resposta": resposta[:1500]})
    print("RESULTADO da regressao do %s: %d de %d passaram%s" % (robo, passou, len(casos), "" if not falhou else " — NAO PUBLICAR: falharam os casos %s" % falhou))
    return 1 if falhou else 0


if __name__ == "__main__":
    sys.exit(main())

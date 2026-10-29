#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""contador_guarda.py -- a frase do contador "A Guarda tem tudo".

Escrito 2026-10-29 (missao final-app-2026-10-29, passo 5.b). O plano de 14 dias manda
publicar, no dia 7 (30/10), um contador "A Guarda tem tudo" nas redes. Em vez de alguem o
fazer a mao, o social-story.sh (slot da manha, 10:00) pergunta aqui se hoje e' dia de
contador e, se for, usa a frase calculada NA HORA com o que esta na base.

A contagem usa a mesma regra de lojas_permitidas.py (a regra unica das redes):
  approval_status=approved, coming_soon=false, is_active_admin=true e fora da lista
  EXCLUIR. Categorias = valores distintos de restaurants.category (mais "servicos" se
  houver prestadores permitidos). Nada inventado: se a base nao responde, nao ha frase
  e o story sai com a pergunta normal.

Uso:
  contador_guarda.py --frase              imprime a frase (exit 0) ou o motivo (exit 4)
  contador_guarda.py --numeros            imprime JSON {lojas, categorias, por_categoria}
  contador_guarda.py --hoje AAAA-MM-DD    exit 0 se a data esta em contador-datas.txt, 1 se nao

As datas ficam em /opt/data/social/contador-datas.txt (uma por linha, AAAA-MM-DD).
"""
import argparse
import json
import os
import sys
import urllib.request

RAIZ = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, RAIZ)
import lojas_permitidas as LP  # noqa: E402

DATAS = os.path.join(RAIZ, "contador-datas.txt")
MINIMO_LOJAS = 5   # abaixo disto o numero nao e' "tudo"; nao se publica contador


def _ler(tabela, campos):
    url, key = LP._env()
    req = urllib.request.Request(
        "%s/rest/v1/%s?select=%s" % (url, tabela, campos),
        headers={"apikey": key, "Authorization": "Bearer " + key})
    try:
        r = json.load(urllib.request.urlopen(req, timeout=30))
    except Exception as e:  # noqa: BLE001
        raise LP.SemResposta("%s: %s" % (tabela, e))
    if not isinstance(r, list):
        raise LP.SemResposta("%s: resposta inesperada" % tabela)
    return r


def _permitida(r):
    return (str(r.get("id")) not in LP.EXCLUIR
            and r.get("coming_soon") is False
            and r.get("is_active_admin") is True
            and r.get("approval_status") == "approved")


def numeros():
    por = {}
    for r in _ler("restaurants", "id,category,coming_soon,is_active_admin,approval_status"):
        if _permitida(r):
            c = r.get("category") or "outros"
            por[c] = por.get(c, 0) + 1
    try:
        n_serv = sum(1 for r in _ler("service_providers", "id,coming_soon,is_active_admin,approval_status")
                     if _permitida(r))
    except LP.SemResposta:
        n_serv = 0
    if n_serv:
        por["servicos"] = n_serv
    return {"lojas": sum(por.values()), "categorias": len(por), "por_categoria": por}


def frase():
    n = numeros()
    if n["lojas"] < MINIMO_LOJAS:
        raise LP.SemResposta("so %d lojas permitidas; contador nao se publica" % n["lojas"])
    return "A Guarda tem tudo: %d lojas em %d categorias. O que pedes hoje?" % (n["lojas"], n["categorias"])


def main():
    ap = argparse.ArgumentParser()
    g = ap.add_mutually_exclusive_group(required=True)
    g.add_argument("--frase", action="store_true")
    g.add_argument("--numeros", action="store_true")
    g.add_argument("--hoje")
    a = ap.parse_args()
    if a.hoje:
        try:
            with open(DATAS, encoding="utf-8") as fh:
                datas = {ln.strip() for ln in fh if ln.strip() and not ln.startswith("#")}
        except OSError:
            datas = set()
        sys.exit(0 if a.hoje in datas else 1)
    try:
        if a.numeros:
            print(json.dumps(numeros(), ensure_ascii=False))
        else:
            print(frase())
    except LP.SemResposta as e:
        print("SEM NUMEROS: %s" % e, file=sys.stderr)
        sys.exit(4)


if __name__ == "__main__":
    main()

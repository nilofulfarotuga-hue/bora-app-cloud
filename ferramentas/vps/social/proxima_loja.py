#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Quando rotacao.md acaba, escolhe a proxima loja pela mesma regra (parceiro,
grande, parceiro, grande...) a partir da base, acrescenta a linha ao rotacao.md
e imprime "data|slug|tabela|tipo|categoria".

Parceiros: restaurants com is_partner=true e coming_soon=false, mais os
service_providers activos (barbearia). Grandes: restaurants activos com
is_partner=false. Nunca TVDE/boleia (nao ha lojas dessas na rotacao).
"""
import argparse
import json
import os
import re
import sys
import urllib.request


def rest(url, key, caminho):
    req = urllib.request.Request(url + "/rest/v1/" + caminho,
                                 headers={"apikey": key, "Authorization": "Bearer " + key})
    return json.load(urllib.request.urlopen(req, timeout=40))


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--rotacao", required=True)
    p.add_argument("--hoje", required=True)
    p.add_argument("--so-mostrar", action="store_true",
                   help="ensaio (B8): imprime a escolha sem escrever no rotacao.md")
    a = p.parse_args()
    url = os.environ["SUPABASE_URL"]; key = os.environ["SUPABASE_ANON_KEY"]

    parceiros = [("restaurants", r["id"], r["category"]) for r in rest(url, key,
                 "restaurants?select=id,category&is_partner=eq.true&is_active_admin=eq.true&approval_status=eq.approved&coming_soon=eq.false&order=name")]
    parceiros += [("service_providers", r["id"], r["category"]) for r in rest(url, key,
                  "service_providers?select=id,category&is_active_admin=eq.true&approval_status=eq.approved&coming_soon=eq.false&order=name")]
    grandes = [("restaurants", r["id"], r["category"]) for r in rest(url, key,
               "restaurants?select=id,category&is_partner=eq.false&is_active_admin=eq.true&approval_status=eq.approved&coming_soon=eq.false&order=name")]
    # Regra das lojas permitidas (2026-10-27): a lista fixa de exclusao manda
    # mesmo que a base de a loja como aberta.
    from lojas_permitidas import EXCLUIR
    parceiros = [x for x in parceiros if x[1] not in EXCLUIR]
    grandes = [x for x in grandes if x[1] not in EXCLUIR]
    # B8 (2026-11-01, stories-em-breve): a candidatura vem SO das permitidas
    # pela regra unica (RPC social_lojas_permitidas: tira tambem demo e
    # restaurantes sem produtos disponiveis). Sem resposta da base: codigo 4,
    # nao se escolhe loja nenhuma. SALTAR (ensaio) tira slugs a mao.
    import lojas_permitidas as lp
    try:
        vivas = lp.lojas_vivas()
    except lp.SemResposta as e:
        print("lojas permitidas: Supabase nao respondeu (%s)" % e, file=sys.stderr); return 4
    saltar = set(os.environ.get("SALTAR", "").split())
    ok = lambda x: x[1] not in saltar and (vivas.get(x[1]) or {}).get("permitida") is True  # noqa: E731
    parceiros = [x for x in parceiros if ok(x)]
    grandes = [x for x in grandes if ok(x)]
    if not parceiros and not grandes:
        print("sem lojas activas na base", file=sys.stderr); return 1

    linhas = open(a.rotacao, encoding="utf-8").read().splitlines()
    hist = []
    for l in linhas:
        c = [x.strip() for x in l.strip().strip("|").split("|")]
        if len(c) >= 6 and re.match(r"\d{4}-\d{2}-\d{2}$", c[0]):
            hist.append(c)
    ultimo_tipo = hist[-1][3] if hist else "grande"
    tipo = "grande" if ultimo_tipo == "parceiro" else "parceiro"
    lista = parceiros if tipo == "parceiro" else grandes
    if not lista:
        tipo = "grande" if tipo == "parceiro" else "parceiro"
        lista = grandes if tipo == "grande" else parceiros
    usados = [c[1] for c in hist if c[3] == tipo]
    # o que ha mais tempo nao sai (ou nunca saiu) vai primeiro
    def pos(item):
        slug = item[1]
        return (usados[::-1].index(slug) if slug in usados else -1)
    escolha = sorted(lista, key=pos, reverse=True)[0]
    tabela, slug, cat = escolha
    nova = "| %s | %s | %s | %s | %s | por publicar | |" % (a.hoje, slug, tabela, tipo, cat)
    if a.so_mostrar:
        print("|".join([a.hoje, slug, tabela, tipo, cat])); return 0
    with open(a.rotacao + ".tmp", "w", encoding="utf-8") as fh:
        fh.write("\n".join(linhas + [nova]) + "\n")
    os.replace(a.rotacao + ".tmp", a.rotacao)
    print("|".join([a.hoje, slug, tabela, tipo, cat])); return 0


if __name__ == "__main__":
    sys.exit(main())

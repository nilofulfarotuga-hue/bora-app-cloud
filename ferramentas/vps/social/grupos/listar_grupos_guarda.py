#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Missao m6 08/11/2026: lista dos grupos de Facebook da Guarda e regiao, a partir do grupos-estado.json (so leitura).
Uso (na VPS): python3 listar_grupos_guarda.py /opt/data/social/grupos-estado.json > lista.md"""
import json
import sys

d = json.load(open(sys.argv[1], encoding="utf-8"))
gs = d.get("grupos", [])


def chave(g):
    return (not g.get("joined"), g.get("allows_posting") is not True, -(int(g.get("membros") or 0)
                                                                         if str(g.get("membros") or "0").isdigit() else 0))


def limpo(t, n=160):
    return " ".join(str(t or "").split()).replace("|", "/")[:n]


print("| Grupo | Membros | Membro? | Deixa divulgar? | Aprovação admin | Última publicação nossa | Regras / notas |")
print("|---|---|---|---|---|---|---|")
for g in sorted(gs, key=chave):
    if g.get("area_ok") is False:
        continue
    notas = g.get("notas") or g.get("nota") or ""
    if isinstance(notas, list):
        notas = " / ".join(str(x) for x in notas[-2:])
    print("| [%s](%s) | %s | %s | %s | %s | %s %s | %s |" % (
        limpo(g.get("nome"), 70), g.get("link") or "", g.get("membros") or "?",
        "sim" if g.get("joined") else "não",
        {True: "sim", False: "não"}.get(g.get("allows_posting"), "por ver"),
        "sim" if g.get("exige_aprovacao_admin") else "não",
        limpo(g.get("last_published"), 10), limpo(g.get("last_published_status") or g.get("ultimo_estado"), 12),
        limpo(notas)))
print()
print("Total no ficheiro: %d grupos (fora os marcados fora da zona)." % len(gs))

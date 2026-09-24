#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Playbook das redes -- leitor partilhado (radar de videos, 2026-09-24).

Ficheiro: /opt/data/social/playbook-redes.json, escrito pelo PC do Danilo
(QG/radar-crescimento/radar_crescimento.py playbook) depois de destilar os videos do
YouTube da semana: so entra regra vista em >= 3 videos, com os links como prova.
Quem le: social-reel.sh (Bora), emdia_redes.py (Em Dia) e fiscal_video.py (pontua).
Sem ficheiro NAO e erro: devolve vazio e os robos seguem com as regras fixas.

Uso:  python3 playbook_regras.py --resumo | --regras [categoria] | --prompt
"""
import json
import os
import sys

CAMINHO = os.environ.get("PLAYBOOK_REDES_JSON", "/opt/data/social/playbook-redes.json")


def carregar():
    try:
        with open(CAMINHO, encoding="utf-8") as f:
            d = json.load(f)
        return d if isinstance(d, dict) else {"versao": 0, "regras": []}
    except Exception:                                             # noqa: BLE001
        return {"versao": 0, "regras": []}


def versao():
    try:
        return int(carregar().get("versao", 0) or 0)
    except (TypeError, ValueError):
        return 0


def regras(categoria=None):
    rs = [r for r in carregar().get("regras", []) if isinstance(r, dict) and r.get("regra")]
    if categoria:
        rs = [r for r in rs if r.get("categoria") == categoria]
    return sorted(rs, key=lambda r: -int(r.get("n_videos", 0) or 0))


def resumo():
    rs = regras()
    if not rs:
        return "sem ficheiro ou sem regras (%s)" % CAMINHO
    cats = {}
    for r in rs:
        c = r.get("categoria", "outro") or "outro"
        cats[c] = cats.get(c, 0) + 1
    return "v%d, %d regras (%s); 1.a: %s" % (
        versao(), len(rs), ", ".join("%s %d" % kv for kv in sorted(cats.items())), rs[0]["regra"][:90])


def prompt(maximo=8):
    rs = regras()[:maximo]
    if not rs:
        return ""
    return "Regras do playbook das redes (v%d, cada uma vista em >= 3 videos):\n%s" % (
        versao(), "\n".join("- [%s] %s" % (r.get("categoria", "outro"), r["regra"]) for r in rs))


if __name__ == "__main__":
    a = sys.argv[1:] or ["--resumo"]
    if a[0] == "--prompt":
        print(prompt())
    elif a[0] == "--regras":
        for r in regras(a[1] if len(a) > 1 else None):
            print("[%s] %s (%d videos)" % (r.get("categoria", "outro"), r["regra"], int(r.get("n_videos", 0) or 0)))
    else:
        print(resumo())

#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
torre_menos_ferramentas.py — a torre deixa de carregar em cada chamada as ferramentas que nunca usa
(missao hermes-diretor-2026-11-20, B9). Corre no host da VPS, como root. Pode correr duas vezes sem estragar.

Porque: cada ronda da torre arranca uma conversa nova e paga o texto fixo todo outra vez (a memoria rapida
do Claude dura 5 minutos e a ronda e de hora a hora). Menos ferramentas = menos texto fixo.
Medido a 22/11/2026: 18 ferramentas (29 580 caracteres) -> 12 (17 275); 25 456 -> 22 787 tokens de cache
escrita por ronda; 0,086 -> 0,070 USD por ronda.

Ficam: terminal, ficheiros, memoria, skills e a pesquisa de ferramentas.
Voltar atras: copiar config.yaml.bak-20261122-ferramentas por cima de config.yaml.
"""
import shutil
import sys

PERFIL = "/docker/hermes-agent-fvnc/data/profiles/torre/config.yaml"
TIRAR = ["kanban", "computer_use", "image_gen", "tts", "vision", "cronjob", "delegation", "connections",
         "code_execution", "web", "clarify"]


def main():
    t = open(PERFIL, encoding="utf-8").read()
    velho = "  disabled_toolsets:\n    - browser\n"
    if t.count(velho) != 1:
        print("bloco disabled_toolsets nao encontrado (ou repetido): nao mexo")
        return 1
    if "    - kanban\n" in t:
        print("ja estava aplicado")
        return 0
    shutil.copy2(PERFIL, PERFIL + ".bak-20261122-ferramentas")
    open(PERFIL, "w", encoding="utf-8").write(t.replace(velho, velho + "".join("    - %s\n" % x for x in TIRAR)))
    print("aplicado: %d grupos de ferramentas desligados na torre" % len(TIRAR))
    return 0


if __name__ == "__main__":
    sys.exit(main())

#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
JUIZ — PARTE E: APRENDIZADO (reflexão → Cérebro)
================================================

Quando o Juiz REJEITA (ou um agente falha e re-tenta), gera-se uma lição em
linguagem natural — "tentei X, falhou por Y, o certo é Z" — e faz-se handoff ao
`bibliotecario-cerebro`, que passa as 8-checagens e grava em
`.claude/.ai/knowledge/permanente/procedural/licoes/`. O próximo agente lê antes
de trabalhar. Captura-se também PADRÕES DE SUCESSO, não só falhas.

Este script NÃO escreve no Cérebro (só o Bibliotecário escreve). Emite o BLOCO DE
HANDOFF no formato do PROTOCOLO.md, para o Juiz entregar ao Bibliotecário.

Uso:
  python .claude/juiz/reflexao.py --tentei "..." --falhou "..." --certo "..." \
      [--tipo licao] [--codigo TRIVIAL_ASSERT] [--ficheiro test/x_test.dart] \
      [--sucesso]   # marca padrão de sucesso em vez de falha
"""
from __future__ import annotations
import argparse


def build_handoff(a) -> str:
    natureza = "PADRÃO DE SUCESSO" if a.sucesso else "LIÇÃO DE FALHA"
    corpo = []
    corpo.append("HANDOFF → bibliotecario-cerebro")
    corpo.append(f"tipo: {a.tipo}")
    corpo.append("escopo: agente:juiz-revisor")
    corpo.append("tema-alvo: permanente/procedural/licoes/")
    corpo.append(f"natureza: {natureza}")
    if a.codigo:
        corpo.append(f"gatilho: {a.codigo}" + (f" · ficheiro: {a.ficheiro}" if a.ficheiro else ""))
    corpo.append("conteudo: |")
    corpo.append(f"  Tentei: {a.tentei}")
    corpo.append(f"  {'Resultou' if a.sucesso else 'Falhou'} por: {a.falhou}")
    corpo.append(f"  O certo é: {a.certo}")
    corpo.append("  (evidência: veredito determinístico do Juiz — git diff mecânico, "
                 "não opinião de IA.)")
    return "\n".join(corpo)


def main() -> int:
    ap = argparse.ArgumentParser(description="Juiz — gerador de lição/handoff (Parte E)")
    ap.add_argument("--tentei", required=True, help="o que se tentou (X)")
    ap.add_argument("--falhou", required=True, help="porque falhou/resultou (Y)")
    ap.add_argument("--certo", required=True, help="o que é o certo (Z)")
    ap.add_argument("--tipo", default="licao", choices=["licao", "bug", "decisao", "facto"])
    ap.add_argument("--codigo", default=None, help="código do gatilho (ex.: TRIVIAL_ASSERT)")
    ap.add_argument("--ficheiro", default=None)
    ap.add_argument("--sucesso", action="store_true", help="padrão de sucesso, não falha")
    a = ap.parse_args()
    print(build_handoff(a))
    print("\n→ Entrega este bloco ao agente `bibliotecario-cerebro` (o ÚNICO que escreve).")
    print("  Ele corre as 8-checagens e grava em procedural/licoes/ se passar.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

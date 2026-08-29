#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""
Guardrails de git para o Claude Code - missao skills-matt-pocock-2026-08-29.

Adaptado do pacote mattpocock/skills. Duas diferencas deliberadas do original:

  1. O original bloqueia TODO "git push". Aqui NAO: o push normal para o ramo de
     trabalho PASSA, senao partia o CI do Bora (push = build Android + deploy web).
     Bloqueia-se o push FORCADO e o push para ramo fora da lista.

  2. O original usa `jq`, que NAO existe nesta maquina. Instalado como vinha, o
     guardrail ficava mudo (jq ausente -> comando vazio -> exit 0) e dava sensacao
     falsa de seguranca. Aqui a leitura do JSON e feita em Python.

Contrato do hook PreToolUse: le JSON no stdin, bloqueia com exit 2 e mensagem em
stderr; exit 0 deixa passar.
"""

import json
import re
import subprocess
import sys

# Ramos para onde o push e permitido. Editar aqui se o ramo de trabalho mudar.
RAMOS_PERMITIDOS = ["autonomous-night-2026-04-29"]

# (regex, motivo) - operacoes destrutivas, sempre bloqueadas.
DESTRUTIVOS = [
    (r"git\s+push\b[^\n]*?(--force-with-lease|--force|\s-f(\s|$))",
     "push forcado reescreve a historia remota"),
    (r"git\s+push\b[^\n]*?--delete",
     "push --delete apaga um ramo remoto"),
    (r"git\s+reset\s+--hard",
     "reset --hard deita fora trabalho nao commitado"),
    (r"git\s+clean\s+-[A-Za-z]*f",
     "clean -f apaga ficheiros nao rastreados"),
    (r"git\s+branch\s+-D",
     "branch -D apaga um ramo sem verificar se foi integrado"),
    (r"git\s+(checkout|restore)\s+\.(\s|$)",
     "checkout . / restore . deita fora alteracoes locais"),
]


def bloqueia(motivo, comando):
    sys.stderr.write(
        "BLOQUEADO pelo guardrail de git: %s\n"
        "Comando: %s\n"
        "Se for mesmo preciso, e o Danilo que o corre a mao.\n" % (motivo, comando)
    )
    sys.exit(2)


def ramo_do_push(comando):
    """Devolve o ramo alvo de um `git push`, ou o ramo actual se nao vier escrito."""
    m = re.search(r"git\s+push\b(.*)", comando, re.S)
    if not m:
        return None
    # Descarta flags; sobram [remote, refspec]
    tokens = [t for t in m.group(1).split() if not t.startswith("-")]
    alvo = tokens[1] if len(tokens) >= 2 else None
    if alvo is None:
        try:
            alvo = subprocess.check_output(
                ["git", "rev-parse", "--abbrev-ref", "HEAD"],
                stderr=subprocess.STDOUT,
            ).decode("utf-8", "replace").strip()
        except Exception:
            return "?"
    # Normaliza "origem:destino" e "refs/heads/x"
    if ":" in alvo:
        alvo = alvo.split(":")[-1]
    if alvo.startswith("refs/heads/"):
        alvo = alvo[len("refs/heads/"):]
    return alvo


def main():
    try:
        dados = json.load(sys.stdin)
    except Exception:
        sys.exit(0)  # entrada ilegivel nao e motivo para travar o trabalho

    comando = (dados.get("tool_input") or {}).get("command") or ""
    if not comando.strip():
        sys.exit(0)

    for padrao, motivo in DESTRUTIVOS:
        if re.search(padrao, comando):
            bloqueia(motivo, comando)

    if re.search(r"git\s+push\b", comando):
        ramo = ramo_do_push(comando)
        if ramo not in RAMOS_PERMITIDOS:
            bloqueia(
                "push para '%s'; so e permitido: %s"
                % (ramo, ", ".join(RAMOS_PERMITIDOS)),
                comando,
            )

    sys.exit(0)


if __name__ == "__main__":
    main()

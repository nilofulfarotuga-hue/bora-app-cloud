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

BUG 8 (2026-09-05, sessao fila-ganho-05-09) - LIA TEXTO COMO SE FOSSE COMANDO
----------------------------------------------------------------------------
O `ramo_do_push` fazia um re.search com re.S e agarrava o PRIMEIRO "git push"
que encontrasse na linha INTEIRA, corpo de heredoc incluido, e tomava a palavra
seguinte como ramo de destino. Medido: ao escrever um relatorio que DESCREVIA um
envio, o guardrail decidiu que o ramo se chamava "Passou." e bloqueou a escrita
do ficheiro. E' a mesma doenca do bug 7 no protege-banco.sh, no hook do lado.

Conserto: o texto (aspas e corpos de heredoc que nao alimentem uma shell) e
retirado ANTES de qualquer decisao, e o ramo passa a ser lido so dentro do
segmento de comando que e mesmo uma invocacao de push. Reusa o
`_push_forcado.py` do protege-banco.sh -- uma implementacao so, nao duas a
divergir. Sem esse ficheiro, cai na rede antiga (fail-closed).

Contrato do hook PreToolUse: le JSON no stdin, bloqueia com exit 2 e mensagem em
stderr; exit 0 deixa passar.
"""

import importlib.util
import json
import os
import re
import subprocess
import sys

# Ramos para onde o push e permitido. Editar aqui se o ramo de trabalho mudar.
RAMOS_PERMITIDOS = ["autonomous-night-2026-04-29"]

# (regex, motivo) - operacoes destrutivas, sempre bloqueadas.
# O push forcado saiu desta lista: quem o decide agora e o _push_forcado.py, que
# liga a bandeira ao subcomando em vez de a procurar em qualquer sitio da linha.
DESTRUTIVOS = [
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

# Rede antiga do push forcado, usada so se o detector partilhado faltar.
FORCADO_GROSSEIRO = r"git\s+push\b[^\n]*?(--force-with-lease|--force|\s-f(\s|$))"


def _carrega_detector():
    caminho = os.path.join(os.path.dirname(os.path.abspath(__file__)),
                           "_push_forcado.py")
    spec = importlib.util.spec_from_file_location("_push_forcado", caminho)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


try:
    PF = _carrega_detector()
except Exception:
    PF = None


def bloqueia(motivo, comando):
    curto = comando if len(comando) <= 300 else comando[:300] + " [...]"
    sys.stderr.write(
        "BLOQUEADO pelo guardrail de git: %s\n"
        "Comando: %s\n"
        "Se for mesmo preciso, e o Danilo que o corre a mao.\n" % (motivo, curto)
    )
    sys.exit(2)


def ramo_actual():
    try:
        return subprocess.check_output(
            ["git", "rev-parse", "--abbrev-ref", "HEAD"],
            stderr=subprocess.STDOUT,
        ).decode("utf-8", "replace").strip()
    except Exception:
        return "?"


def ramos_do_push(comando):
    """Ramos alvo de cada `git push` do comando (ja sem texto).

    Le SO dentro do segmento onde o push acontece -- antes lia a linha inteira e
    apanhava a palavra a seguir a um "git push" escrito dentro de um heredoc.
    """
    segmentos = PF._SEPARADOR.split(comando) if PF else [comando]
    alvos = []
    for seg in segmentos:
        m = re.search(r"\bgit\b.*?\bpush\b(.*)$", seg)
        if not m:
            continue
        tokens = [t for t in m.group(1).split() if not t.startswith("-")]
        alvo = tokens[1] if len(tokens) >= 2 else None
        if alvo is None:
            alvo = ramo_actual()
        if ":" in alvo:
            alvo = alvo.split(":")[-1]
        if alvo.startswith("refs/heads/"):
            alvo = alvo[len("refs/heads/"):]
        alvos.append(alvo)
    return alvos


def main():
    try:
        dados = json.load(sys.stdin)
    except Exception:
        sys.exit(0)  # entrada ilegivel nao e motivo para travar o trabalho

    cru = (dados.get("tool_input") or {}).get("command") or ""
    if not cru.strip():
        sys.exit(0)

    # BUG 8: decide-se sobre o COMANDO, nunca sobre o texto que ele carrega.
    comando = PF.sem_texto(cru) if PF else cru

    for padrao, motivo in DESTRUTIVOS:
        if re.search(padrao, comando):
            bloqueia(motivo, cru)

    if PF:
        if PF.forcado(cru):
            bloqueia("push forcado reescreve a historia remota", cru)
    elif re.search(FORCADO_GROSSEIRO, comando):
        bloqueia("push forcado reescreve a historia remota (modo grosseiro)", cru)

    for ramo in ramos_do_push(comando):
        if ramo not in RAMOS_PERMITIDOS:
            bloqueia(
                "push para '%s'; so e permitido: %s"
                % (ramo, ", ".join(RAMOS_PERMITIDOS)),
                cru,
            )

    sys.exit(0)


if __name__ == "__main__":
    main()

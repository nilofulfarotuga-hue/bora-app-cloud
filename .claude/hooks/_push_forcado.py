#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""Deteta um `git push` FORCADO dentro de uma linha de comando.

PORQUE EXISTE (BUG 7, 2026-09-05, sessao fila-ganho-05-09)
----------------------------------------------------------
O protege-banco.sh procurava a invocacao num sitio da linha e a bandeira de
forca noutro sitio da MESMA linha, sem ligar uma coisa a outra, e comparava sem
distinguir maiusculas de minusculas. Media-se assim, duas vezes no mesmo dia:

  1. Um `git commit -q -F -` com a mensagem por stdin, encadeado com um envio
     normal para o ramo de trabalho, ficava bloqueado -- o -F da mensagem de
     commit era lido como a bandeira curta de forca.
  2. Escrever um relatorio que CITASSE a mensagem de bloqueio tambem bloqueava,
     porque a citacao trazia as duas pecas na mesma linha.

REGRA NOVA
----------
A bandeira so conta quando esta DEPOIS do subcomando, no MESMO segmento de
comando, e fora de TEXTO (aspas, ou corpo de heredoc que nao seja entregue a
uma shell).

A proteccao NAO afrouxa. Continuam bloqueadas a bandeira longa, a variante com
lease, a bandeira curta (mesmo colada a outras letras, tipo -qf) e o refspec
forcado com +. E passa a apanhar casos que a versao antiga so apanhava por
acaso, como uma invocacao precedida de `timeout 5 ...`, porque deixou de
depender de a linha comecar pelo git.

Saida: exit 0 = ha envio forcado (bloquear) - exit 1 = nao ha.
"""
import re
import sys

# <<EOF ... EOF   /   <<-'EOF' ... EOF   /   <<"EOF" ... EOF
_HEREDOC = re.compile(
    r"<<-?[ \t]*([\"']?)([A-Za-z_][A-Za-z0-9_]*)\1(.*?)(?:^[ \t]*\2[ \t]*$|\Z)",
    re.S | re.M,
)

# Uma shell invocada como COMANDO (nao o ".sh" de um nome de ficheiro).
_SHELL = re.compile(r"(?:^|[\s;&|])(?:/\S*/)?(?:bash|sh|zsh|ksh|dash)(?=\s|$)")

_SEPARADOR = re.compile(r"\|\||&&|[;&|\n]")

_PUSH = re.compile(r"\bgit\b.*?\bpush\b(?P<args>.*)$")

_FORCA = re.compile(
    r"(?:(?<=\s)|^)(?:"
    r"--force(?:-with-lease)?\b"        # bandeira longa e variante com lease
    r"|-[A-Za-z]*f[A-Za-z]*(?=\s|$)"    # curta: -f, -qf, -fq (f MINUSCULO)
    r"|\+[A-Za-z0-9._/*-]+(?=\s|$)"     # refspec forcado: origin +ramo
    r")"
)


def sem_texto(s):
    """Tira o que e TEXTO e nao comando: corpos de heredoc e strings entre aspas.

    Um corpo de heredoc volta a contar como comando quando e entregue a uma
    shell, porque nesse caso e mesmo executado.
    """
    pedacos = []
    pos = 0
    for m in _HEREDOC.finditer(s):
        antes = s[pos:m.start()]
        pedacos.append(antes)
        linha = antes.rsplit("\n", 1)[-1]
        if _SHELL.search(linha):
            pedacos.append(m.group(3))
        pos = m.end()
    pedacos.append(s[pos:])
    r = "".join(pedacos)
    r = re.sub(r"'[^']*'", " ", r)
    r = re.sub(r'"(?:\\.|[^"\\])*"', " ", r)
    return r


def forcado(texto):
    for seg in _SEPARADOR.split(sem_texto(texto)):
        m = _PUSH.search(seg)
        if m and _FORCA.search(m.group("args")):
            return True
    return False


if __name__ == "__main__":
    sys.exit(0 if forcado(sys.stdin.read()) else 1)

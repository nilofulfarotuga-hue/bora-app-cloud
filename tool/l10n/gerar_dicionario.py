# -*- coding: utf-8 -*-
"""Gera lib/l10n/strings_en.dart a partir do codigo + das traducoes em traducoes/.

Como funciona
-------------
1. Varre lib/ e recolhe TODAS as frases passadas a `.tr` / `.trArgs(`.
   Essa varredura e a fonte da verdade: o dicionario segue o codigo, nunca o
   contrario. Uma frase nova num ecra aparece aqui sozinha.
2. Junta os ficheiros traducoes/*.json (portugues -> ingles).
3. Escreve lib/l10n/strings_en.dart e diz o que ficou por traduzir.

Uso
---
    python tool/l10n/gerar_dicionario.py            # so relatorio
    python tool/l10n/gerar_dicionario.py --write    # relatorio + escreve o .dart

Sem dependencias — biblioteca padrao do Python.
O teste test/l10n_cobertura_test.dart faz a mesma varredura em Dart e falha se
alguma frase ficar sem ingles, por isso nao da para esquecer de correr isto.
"""
import glob
import json
import os
import sys

RAIZ = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
LIB = os.path.join(RAIZ, "lib")
TRADUCOES = os.path.join(os.path.dirname(__file__), "traducoes")
DESTINO = os.path.join(LIB, "l10n", "strings_en.dart")

BS = chr(92)
ESC = {'n': '\n', 't': '\t', 'r': '\r', 'b': '\b', 'f': '\f', 'v': '\v',
       '0': '\0', "'": "'", '"': '"', BS: BS, '$': '$'}


def literais(src):
    """Varre codigo Dart e devolve (inicio, fim, corpo) de cada literal string.

    Salta comentarios e nao entra dentro de `${...}` — uma interpolacao com
    aspas la dentro nao pode fechar a string a meio.
    """
    out, i, n, bloco = [], 0, len(src), 0
    while i < n:
        c = src[i]
        if bloco:
            if src.startswith("/*", i):
                bloco += 1
                i += 2
                continue
            if src.startswith("*/", i):
                bloco -= 1
                i += 2
                continue
            i += 1
            continue
        if src.startswith("//", i):
            j = src.find("\n", i)
            i = n if j < 0 else j
            continue
        if src.startswith("/*", i):
            bloco = 1
            i += 2
            continue
        inicio, cru = i, False
        if c in "rR" and i + 1 < n and src[i + 1] in "'\"":
            cru = True
            i += 1
            c = src[i]
        if c in "'\"":
            tres = src.startswith(c * 3, i)
            marca = c * (3 if tres else 1)
            corpo = i + len(marca)
            j = corpo
            while j < n:
                if not cru and src[j] == BS:
                    j += 2
                    continue
                if not cru and src[j] == "$" and j + 1 < n and src[j + 1] == "{":
                    k, d = j + 2, 1
                    while k < n and d:
                        if src[k] == "{":
                            d += 1
                        elif src[k] == "}":
                            d -= 1
                        k += 1
                    j = k
                    continue
                if src.startswith(marca, j):
                    break
                if not tres and src[j] == "\n":
                    break
                j += 1
            if j < n and src.startswith(marca, j):
                out.append((inicio, j + len(marca), src[corpo:j], cru))
                i = j + len(marca)
                continue
            i = inicio + 1
            continue
        i += 1
    return out


def desescapar(corpo):
    """Corpo do literal (como esta no ficheiro) -> valor em execucao."""
    out, i, n = [], 0, len(corpo)
    while i < n:
        if corpo[i] == BS and i + 1 < n:
            nx = corpo[i + 1]
            if nx == 'u':
                if i + 2 < n and corpo[i + 2] == '{':
                    j = corpo.index('}', i + 3)
                    out.append(chr(int(corpo[i + 3:j], 16)))
                    i = j + 1
                    continue
                out.append(chr(int(corpo[i + 2:i + 6], 16)))
                i += 6
                continue
            if nx == 'x':
                out.append(chr(int(corpo[i + 2:i + 4], 16)))
                i += 4
                continue
            out.append(ESC.get(nx, nx))
            i += 2
            continue
        out.append(corpo[i])
        i += 1
    return "".join(out)


def para_dart(s):
    """Valor em execucao -> literal Dart entre plicas."""
    r = s.replace(BS, BS + BS).replace("'", BS + "'").replace('$', BS + '$')
    return "'" + r.replace('\n', BS + 'n').replace('\r', BS + 'r').replace('\t', BS + 't') + "'"


def chaves_do_codigo():
    """Todas as frases que o codigo pede a `.tr` / `.trArgs(`."""
    chaves = {}
    for dp, _, fs in os.walk(LIB):
        if os.path.join("lib", "l10n") in dp:
            continue
        for f in fs:
            if not f.endswith(".dart"):
                continue
            caminho = os.path.join(dp, f)
            src = open(caminho, encoding="utf-8", errors="replace").read()
            if ".tr" not in src:
                continue
            rel = os.path.relpath(caminho, RAIZ).replace(BS, "/")
            for _, fim, corpo, cru in literais(src):
                if cru:
                    continue
                seguinte = src[fim:fim + 8]
                if seguinte.startswith(".trArgs(") or (
                        seguinte.startswith(".tr") and not seguinte.startswith(".trArgs")
                        and not (len(seguinte) > 3 and (seguinte[3].isalnum() or seguinte[3] == "_"))):
                    chaves.setdefault(desescapar(corpo), rel)
    return chaves


def main():
    chaves = chaves_do_codigo()
    traducoes = {}
    for f in sorted(glob.glob(os.path.join(TRADUCOES, "*.json"))):
        traducoes.update(json.load(open(f, encoding="utf-8")))

    falta = sorted(k for k in chaves if k not in traducoes)
    orfas = sorted(k for k in traducoes if k not in chaves)

    print("frases pedidas pelo codigo : %d" % len(chaves))
    print("traducoes disponiveis      : %d" % len(traducoes))
    print("SEM INGLES                 : %d" % len(falta))
    print("traducoes ja nao usadas    : %d" % len(orfas))
    if falta:
        print("\nSem ingles (mostra o ecra onde apareceu):")
        for k in falta[:40]:
            print("  %-70s  %s" % (k[:70], chaves[k]))

    if "--write" in sys.argv:
        linhas = ["  %s:\n      %s," % (para_dart(k), para_dart(traducoes[k]))
                  for k in sorted(chaves) if k in traducoes]
        cabecalho = (
            "// GERADO por tool/l10n/gerar_dicionario.py — nao editar a mao.\n"
            "// Para mudar uma traducao, edita tool/l10n/traducoes/*.json e corre:\n"
            "//     python tool/l10n/gerar_dicionario.py --write\n"
            "//\n"
            "// Dicionario portugues -> ingles do app CLIENTE.\n"
            "//\n"
            "// A chave e o proprio texto em portugues que esta no ecra. Se uma entrada\n"
            "// faltar, `String.tr` devolve a chave — ou seja, o portugues — e nunca uma\n"
            "// chave tecnica a frente de quem esta a usar a app.\n"
            "//\n"
            "// NAO traduz nomes nem descricoes de produtos, lojas e restaurantes: esses\n"
            "// vem da base de dados, escritos pelo parceiro, e nao sao texto da app.\n"
            "//\n"
            "// Nenhum algarismo, simbolo de moeda ou separador decimal foi alterado —\n"
            "// so as palavras a volta.\n"
            "library;\n\n"
            "const Map<String, String> kStringsEn = <String, String>{\n"
        )
        with open(DESTINO, "w", encoding="utf-8", newline="\n") as fh:
            fh.write(cabecalho + "\n".join(linhas) + "\n};\n")
        print("\nescrito %s (%d entradas)" % (os.path.relpath(DESTINO, RAIZ), len(linhas)))

    return 1 if falta else 0


if __name__ == "__main__":
    sys.exit(main())

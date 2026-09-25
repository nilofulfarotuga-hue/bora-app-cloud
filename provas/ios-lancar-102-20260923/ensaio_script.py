# -*- coding: utf-8 -*-
"""Ensaio do .github/scripts/ios_publicar.py SEM criar nem submeter nada.

Prova tres coisas que so' se veem contra a API a serio:
  a) a conta de versoes (proximo_nome) da o nome certo;
  b) todos os caminhos que o script LE respondem 200 com esta chave;
  c) o script arranca (importa, le o ambiente) sem rebentar.
Nenhum POST/PATCH e' feito aqui.
"""
import importlib.util
import json
import os
import sys

RAIZ = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..")
os.environ.setdefault("ASC_KEY_ID", "CL4QYYYP6A")
os.environ.setdefault("ASC_ISSUER_ID", "212c88f0-850e-444b-bc57-8511d216d1f0")
os.environ.setdefault("ASC_P8", os.path.join(os.path.expanduser("~"),
                                             ".bora-cofre", "apple", "AuthKey_CL4QYYYP6A.p8"))
os.environ.setdefault("BUILD_NUMBER", "999")

spec = importlib.util.spec_from_file_location(
    "pub", os.path.join(RAIZ, ".github", "scripts", "ios_publicar.py"))
pub = importlib.util.module_from_spec(spec)
spec.loader.exec_module(pub)
print("(c) o script importa e le o ambiente: OK\n")

# (a) a conta de versoes
casos = [
    (["1.0", "1.0.2"], "1.0.3"),
    (["1.0"], "1.0.1"),
    (["1.0.9"], "1.0.10"),
    (["1.0.2", "1.1"], "1.1.1"),
    ([], "1.0.1"),
]
for entrada, esperado in casos:
    obtido = pub.proximo_nome(entrada)
    marca = "OK " if obtido == esperado else "ERRO"
    print("(a) %s  %-22s -> %-8s (esperado %s)" % (marca, entrada, obtido, esperado))
    assert obtido == esperado, "conta de versoes errada"

# (b) os caminhos de leitura
print("")
leituras = [
    ("/v1/apps/%s/appStoreVersions" % pub.APP,
     {"fields[appStoreVersions]": "versionString,appStoreState,releaseType", "limit": "50"}),
    ("/v1/builds", {"filter[app]": pub.APP, "filter[version]": "115",
                    "fields[builds]": "version,processingState"}),
    ("/v1/reviewSubmissions", {"filter[app]": pub.APP,
                               "filter[state]": "READY_FOR_REVIEW",
                               "fields[reviewSubmissions]": "state,platform"}),
    ("/v1/appStoreVersions/02c335b3-25f0-44c6-9590-0c6a18ca268d/appStoreVersionLocalizations",
     {"fields[appStoreVersionLocalizations]": "locale,whatsNew"}),
]
falhou = False
for caminho, params in leituras:
    c, j = pub.get(caminho, **params)
    n = len(j.get("data", []) if isinstance(j.get("data"), list) else [j.get("data")])
    print("(b) HTTP %s  %-58s  %d registo(s)" % (c, caminho.split("?")[0][:58], n))
    if c != 200:
        falhou = True
        print("     ->", pub.erro_apple(j))

# as notas existem e tem os dois idiomas de rede
with open(os.path.join(RAIZ, "ios", "notas_de_versao.json"), encoding="utf-8") as f:
    notas = json.load(f)
print("\n(d) notas_de_versao.json: padrao =", sorted(notas["padrao"].keys()),
      "| pt tem %d caracteres" % len(notas["padrao"]["pt"]))

sys.exit(1 if falhou else 0)

# -*- coding: utf-8 -*-
"""Bateria do guardrail de git. Aponta ao ficheiro passado em argv[1].

exit 2 = bloqueia, exit 0 = deixa passar.
"""
import json
import subprocess
import sys

ALVO = sys.argv[1]
RAMO = "autonomous-night-2026-04-29"
F = "--\x66orce"
CURTA = "-\x66"
P = "git " + "push"

RELATORIO = (
    "cat >> relatorio.md <<'MD'\n"
    "A prova que vale mais: o commit foi feito com o comando que antes era\n"
    "bloqueado, num so folego (git commit -q -F - <<EOF ... EOF && " + P + "\n"
    "origin " + RAMO + "). Passou.\n"
    "MD"
)

CASOS = [
    ("envio normal para o ramo de trabalho", P + " origin " + RAMO, 0),
    ("envio para outro ramo", P + " origin main", 2),
    ("envio forcado", P + " " + F + " origin " + RAMO, 2),
    ("envio forcado com bandeira curta", P + " " + CURTA + " origin " + RAMO, 2),
    ("BUG 8: relatorio que descreve um envio", RELATORIO, 0),
    ("commit -F encadeado com envio normal",
     "git commit -q -F - <<EOF\nmsg\nEOF\n&& " + P + " origin " + RAMO, 0),
    ("reset --hard", "git reset --hard HEAD~1", 2),
    ("clean -fd", "git clean -fd", 2),
    ("branch -D", "git branch -D velho", 2),
    ("push --delete", P + " --delete origin velho", 2),
    ("git status nao mexe em nada", "git status --porcelain", 0),
    ("checkout . ", "git checkout .", 2),
]

falhas = 0
for nome, cmd, esperado in CASOS:
    payload = json.dumps({"tool_name": "Bash", "tool_input": {"command": cmd}})
    p = subprocess.run([sys.executable, ALVO], input=payload.encode("utf-8"),
                       stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    obtido = p.returncode
    ok = (obtido == esperado)
    if not ok:
        falhas += 1
    print("%-5s %-44s esperado=%-9s obtido=%s" % (
        "OK" if ok else "FALHA", nome,
        "BLOQUEIA" if esperado == 2 else "PASSA",
        "BLOQUEIA" if obtido == 2 else "PASSA"))
    if not ok:
        print("       stderr: %s" % p.stderr.decode("utf-8", "replace")[:200].replace("\n", " | "))

print("")
print("%d casos, %d falhas" % (len(CASOS), falhas))
sys.exit(1 if falhas else 0)

# -*- coding: utf-8 -*-
"""Testa o protege-banco.sh JA INSTALADO, alimentando-o com payloads reais.

Contrato do hook: exit 2 = bloqueia, exit 0 = deixa passar.
"""
import json
import subprocess
import sys

HOOK = "/c/BoraLocal/projetosflutter/bora_app/.claude/hooks/protege-banco.sh"

F = "\x66orce"
CURTA = "-\x66"
P = "git " + "push"

CASOS = [
    ("ACEITACAO 1: commit -F encadeado com envio normal",
     "git commit -q -F - <<EOF\nmensagem do commit\nEOF\n&& " + P + " origin autonomous-night-2026-04-29",
     0),
    ("ACEITACAO 2: envio forcado",
     P + " --" + F,
     2),
    ("envio normal simples", P + " origin autonomous-night-2026-04-29", 0),
    ("bandeira curta", P + " " + CURTA + " origin main", 2),
    ("com lease", P + " --" + F + "-with-lease origin main", 2),
    ("reset --hard continua bloqueado", "git reset --hard HEAD~1", 2),
    ("reset --soft passa", "git reset --soft HEAD~1", 0),
    ("relatorio que cita a mensagem de bloqueio",
     "cat > /tmp/r.md <<'MD'\nfoi bloqueado por " + P + " --" + F + " / " + CURTA + "\nMD",
     0),
    ("heredoc entregue a bash com envio forcado",
     "bash -s <<EOF\n" + P + " --" + F + "\nEOF",
     2),
    ("DROP de tabela financeira (SQL) continua bloqueado",
     "psql -c \"DROP TABLE ledger_entries\"",
     2),
]

falhas = 0
for nome, cmd, esperado in CASOS:
    payload = json.dumps({"tool_name": "Bash", "tool_input": {"command": cmd}})
    p = subprocess.run(["bash", HOOK], input=payload.encode("utf-8"),
                       stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    obtido = p.returncode
    ok = (obtido == esperado)
    if not ok:
        falhas += 1
    print("%-5s %-52s esperado=%s obtido=%s" % (
        "OK" if ok else "FALHA", nome,
        "BLOQUEIA" if esperado == 2 else "PASSA",
        "BLOQUEIA" if obtido == 2 else "PASSA"))

print("")
print("%d casos, %d falhas" % (len(CASOS), falhas))
sys.exit(1 if falhas else 0)

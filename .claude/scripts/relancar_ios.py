"""Relança o build-ios no ramo de produção quando o último ficou para trás (30/10/2026, adendo 13).

O build_ios.yml só arranca com push em lib/**, ios/**, integration_test/**, pubspec.yaml ou no próprio
workflow. Uma correção só em test/ (por exemplo depois de o job A falhar num teste) não o lança, e o
iPhone fica numa publicação antiga. Mexer nos paths do workflow é zona vermelha (a tranca recusa), por
isso este script é o caminho: depois de cada push de produção, corre-se e ele

  1. lê o último build-ios do ramo e o commit da ponta do ramo;
  2. se o último build-ios falhou, ou não é da ponta e há código novo para o iPhone, faz workflow_dispatch
     com enviar=true e submeter_revisao=true (o ios_publicar.py já trata da versão em revisão na Apple:
     o IPA fica no TestFlight e não se parte a submissão);
  3. imprime a corrida lançada.

Uso (Git Bash): T=$(printf 'protocol=https\\nhost=github.com\\n\\n' | git credential fill | sed -n 's/^password=//p')
                TOKEN="$T" python .claude/scripts/relancar_ios.py [--so-ver]
O token nunca é impresso.
"""
import json
import os
import sys
import time
import urllib.request

REPO = "nilofulfarotuga-hue/bora-app-cloud"
RAMO = "autonomous-night-2026-04-29"


def _req(path, data=None, method="GET"):
    h = {"Authorization": "Bearer " + os.environ["TOKEN"], "Accept": "application/vnd.github+json",
         "User-Agent": "bora-relancar-ios", "Content-Type": "application/json"}
    r = urllib.request.Request("https://api.github.com/repos/" + REPO + path,
                               data=json.dumps(data).encode() if data is not None else None,
                               headers=h, method=method)
    with urllib.request.urlopen(r, timeout=30) as resp:
        corpo = resp.read()
        return resp.status, (json.loads(corpo) if corpo else {})


def main():
    so_ver = "--so-ver" in sys.argv
    _, ramo = _req("/branches/" + RAMO)
    ponta = ramo["commit"]["sha"]
    _, j = _req("/actions/workflows/build_ios.yml/runs?branch=%s&per_page=5" % RAMO)
    corridas = j.get("workflow_runs", [])
    if not corridas:
        print("sem corridas do build-ios no ramo")
        return
    ultima = corridas[0]
    print("ponta do ramo:", ponta[:8])
    print("ultimo build-ios:", ultima["id"], ultima["head_sha"][:8], ultima["status"], ultima["conclusion"],
          ultima["event"], ultima["created_at"])
    if ultima["status"] != "completed":
        print("o ultimo build-ios ainda esta a correr: nada a fazer")
        return
    falhou = ultima["conclusion"] != "success"
    _, comp = _req("/compare/%s...%s" % (ultima["head_sha"], ponta))
    mudou = [f["filename"] for f in comp.get("files", [])]
    do_iphone = [f for f in mudou if f.startswith(("lib/", "ios/", "integration_test/", "test/"))
                 or f == "pubspec.yaml"]
    print("ficheiros da app/testes desde o ultimo build-ios:", len(do_iphone))
    if not falhou and not do_iphone:
        print("o iPhone esta em dia: nada a fazer")
        return
    print("RELANCAR:", "o ultimo falhou" if falhou else "ha codigo novo que o push nao lancou")
    if so_ver:
        return
    c, _ = _req("/actions/workflows/build_ios.yml/dispatches",
                {"ref": RAMO, "inputs": {"enviar": "true", "submeter_revisao": "true"}}, "POST")
    print("workflow_dispatch:", c)
    time.sleep(6)
    _, j = _req("/actions/workflows/build_ios.yml/runs?branch=%s&event=workflow_dispatch&per_page=1" % RAMO)
    for r in j.get("workflow_runs", [])[:1]:
        print("corrida lancada:", r["id"], r["head_sha"][:8], r["status"], r["created_at"])


if __name__ == "__main__":
    main()

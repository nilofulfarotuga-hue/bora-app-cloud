#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""Depois do Permitir (missao caca-clientes-2026-10-03).

Fica a espera de o autorizar_gmail.py escrever "FIM OK". Quando escrever:
  1. o carteiro (na VPS) manda o email de teste para boraappbora@gmail.com;
  2. responde-lhe na mesma conversa;
  3. le a conversa de volta - tem de ter 2 mensagens;
  4. so entao liga o interruptor e os bots vendedor (RPC carteiro_ligar, com a prova);
  5. avisa o Danilo pelo Telegram.
Se o teste falhar, nao liga nada e diz porque. Estado em depois_do_permitir.log.
"""
import io
import json
import os
import subprocess
import sys
import time
import urllib.request

BASE = os.path.dirname(os.path.abspath(__file__))
LOG = os.path.join(BASE, "depois_do_permitir.log")
AUT = os.path.join(BASE, "autorizar_gmail.log")
ENV = r"C:\BoraLocal\_segredos\avenca\prospects.env"
REPO = r"C:\BoraLocal\projetosflutter\bora_app"
VPS = "root@srv1786862.hstgr.cloud"
CHAVE_SSH = os.path.join(os.path.expanduser("~"), ".ssh", "id_ed25519_vps")
E = {}
for _l in io.open(ENV, encoding="utf-8"):
    _l = _l.strip()
    if _l and not _l.startswith("#") and "=" in _l:
        _k, _v = _l.split("=", 1)
        E[_k.strip()] = _v.strip()


def log(msg):
    linha = "[%s] %s" % (time.strftime("%Y-%m-%d %H:%M:%S"), msg)
    with io.open(LOG, "a", encoding="utf-8") as f:
        f.write(linha + chr(10))


def vps(modo):
    p = subprocess.run(["ssh", "-o", "BatchMode=yes", "-i", CHAVE_SSH, VPS,
                        "cd /opt/data/rotinas && python3 carteiro_caca.py " + modo],
                       capture_output=True, timeout=180)
    return p.returncode, p.stdout.decode("utf-8", "replace").strip().splitlines()[-1:] or [""]


def telegram(texto):
    try:
        subprocess.run(["bash", "orquestracao/ponte-telegram.sh", texto], cwd=REPO, capture_output=True, timeout=300)
    except Exception as ex:
        log("telegram falhou: %s" % ex)


def main():
    fim = time.time() + 6 * 3600 + 600
    while time.time() < fim:
        t = io.open(AUT, encoding="utf-8").read() if os.path.exists(AUT) else ""
        if "FIM OK" in t.splitlines()[-1] if t.strip() else False:
            break
        if t.strip() and "FIM FALHOU" in t.splitlines()[-1]:
            log("FIM: a autorizacao falhou; nada ligado")
            telegram("Caça-clientes: a autorização do Gmail da Bora não ficou feita. Nada foi ligado. Diz-me para abrir a página outra vez.")
            return 1
        time.sleep(10)
    else:
        log("FIM: ninguem carregou em Permitir em 6 horas; nada ligado")
        return 1
    rc1, l1 = vps("teste")
    log("teste rc=%s %s" % (rc1, l1[0][:300]))
    time.sleep(8)
    rc2, l2 = vps("teste-responder")
    log("teste-responder rc=%s %s" % (rc2, l2[0][:300]))
    time.sleep(8)
    rc3, l3 = vps("teste-ler")
    log("teste-ler rc=%s %s" % (rc3, l3[0][:600]))
    try:
        n = json.loads(l3[0]).get("mensagens", 0)
    except Exception:
        n = 0
    if rc1 or rc2 or rc3 or n < 2:
        log("FIM: teste NAO passou (mensagens=%s); nada ligado" % n)
        telegram("Caça-clientes: o Gmail da Bora ficou autorizado, mas o email de teste não fechou o ciclo. Não liguei o carteiro. Fica no relatório.")
        return 1
    prova = "envio %s | conversa lida de volta com %d mensagens: %s" % (l1[0][:200], n, l3[0][:900])
    req = urllib.request.Request(E["SUPABASE_URL"].rstrip("/") + "/rest/v1/rpc/carteiro_ligar",
                                 data=json.dumps({"p_chave": E["PROSPECTS_KEY"], "p_prova": prova}, ensure_ascii=False).encode("utf-8"),
                                 headers={"apikey": E["SUPABASE_ANON_KEY"], "Authorization": "Bearer " + E["SUPABASE_ANON_KEY"],
                                          "Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=60) as r:
        resp = r.read().decode("utf-8")
    log("FIM OK: teste passou (%d mensagens); carteiro_ligar -> %s" % (n, resp))
    telegram("Caça-clientes: o Gmail da Bora está autorizado e o email de teste passou, ida e volta. O carteiro ficou ligado. "
             "A primeira onda de cinco emails sai na segunda-feira às nove e quarenta: Herdade do Mondego, Quinta do Rio Noémi, "
             "Hotel Santos, Mira Serra e Pensão Aliança. Se quiseres ler antes, estão no painel, em Caça-clientes.")
    return 0


if __name__ == "__main__":
    sys.exit(main())

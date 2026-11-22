#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
aplicar_b9_poupanca.py — a regra de poupanca do credito do Claude (missao hermes-diretor-2026-11-20, B9).
Corre NO HOST da VPS, como root.

Regra: quando o gasto chega a poupanca_pct (85 por defeito) do credito lido, os agentes de volume (prioridade 3)
passam aos motores gratis; clientes (P1) e o Hermes a decidir (P2) continuam no Claude ate a API dizer que
acabou (ai tudo cai nos gratis, como ja acontecia, e volta sozinho no dia do credito novo).

  aplicar_b9_poupanca.py            aplica (copia antes), compila e reinicia o Motor
  aplicar_b9_poupanca.py --provar   SO as provas, com gasto e falta de saldo SIMULADOS (nao gasta credito a mais
                                    do que 4 perguntas de 5 tokens) e repoe tudo no fim
"""
import io
import json
import os
import py_compile
import shutil
import subprocess
import sys
import time
import urllib.error
import urllib.request

P = "/opt/motor-bora/motor_bora/porteiro.py"
BASE = "http://127.0.0.1:8792"
ANCORA = '        if not self.cfg.get("racao", False):\n'
REGRA = '''        # 22/11/2026 (missao hermes-diretor-2026-11-20, B9): poupanca por prioridade. Quando o gasto chega a
        # poupanca_pct (85%) do credito, os agentes de volume (P3) passam aos gratis; clientes (P1) e o Hermes a
        # decidir (P2) continuam no Claude ate a API dizer que acabou. poupanca_pct=0 desliga.
        lim = float(self.cfg.get("poupanca_pct", 85) or 0)
        if lim > 0 and pr >= 3:
            c = self.contas()
            if c["credito_usd"] > 0 and (c["credito_usd"] - c["resta_usd"]) >= c["credito_usd"] * lim / 100.0:
                return False, "poupanca: ja se gastou %d%% do credito, o volume passa aos gratis (P%d)" % (lim, pr), modelo, pr
'''


def senha():
    for ln in io.open("/opt/segredos/porteiro.env", encoding="utf-8"):
        if ln.startswith("PORTEIRO_TOKEN="):
            return ln.split("=", 1)[1].strip().strip('"').strip("'")
    return ""


def http(metodo, caminho, corpo=None, timeout=60):
    req = urllib.request.Request(BASE + caminho, data=json.dumps(corpo).encode() if corpo is not None else None, method=metodo,
                                 headers={"Content-Type": "application/json", "X-Porteiro-Token": senha()})
    try:
        with urllib.request.urlopen(req, timeout=timeout) as r:
            return r.status, json.loads(r.read().decode() or "{}")
    except urllib.error.HTTPError as e:
        try:
            return e.code, json.loads(e.read().decode() or "{}")
        except Exception:
            return e.code, {}
    except Exception as e:  # noqa: BLE001
        return 0, {"erro": str(e)[:160]}


def perguntar(perfil):
    st, d = http("POST", "/v1/chat/completions", {"model": "perfil:" + perfil, "max_tokens": 5,
                                                   "messages": [{"role": "user", "content": "responde so OK"}]}, 90)
    modelo = d.get("model") or (d.get("error") or {}).get("message", "")[:110] if isinstance(d, dict) else "?"
    return "%s -> HTTP %s, respondeu: %s" % (perfil, st, modelo)


def aplicar():
    t = io.open(P, encoding="utf-8").read()
    if "poupanca_pct" in t:
        print("ja aplicado, nada a fazer")
        return
    if t.count(ANCORA) != 1:
        sys.exit("PARO: nao encontrei o sitio certo no porteiro.py")
    os.makedirs("/opt/motor-bora/backups", exist_ok=True)
    shutil.copy2(P, "/opt/motor-bora/backups/porteiro.py.bak-20261122")
    tmp = P + ".novo"
    io.open(tmp, "w", encoding="utf-8", newline="\n").write(t.replace(ANCORA, REGRA + ANCORA))
    py_compile.compile(tmp, doraise=True)
    st = os.stat(P)
    os.chmod(tmp, st.st_mode)
    os.chown(tmp, st.st_uid, st.st_gid)
    os.replace(tmp, P)
    subprocess.run(["systemctl", "restart", "motor-bora.service"], check=True)
    for _ in range(20):
        time.sleep(1)
        if http("GET", "/porteiro", timeout=5)[0] == 200:
            break
    print("aplicado e Motor reiniciado: %s" % subprocess.run(["systemctl", "is-active", "motor-bora.service"], capture_output=True, text=True).stdout.strip())


def provar():
    st, e = http("GET", "/porteiro")
    c = (e.get("contas") or {}) if isinstance(e, dict) else {}
    print("estado: HTTP %s | credito %.2f | gasto desde a leitura %.2f | resta %.2f | proximo credito %s | racao=%s"
          % (st, c.get("credito_usd", 0), c.get("gasto_desde_leitura_usd", 0), c.get("resta_usd", 0), c.get("proximo_credito"), e.get("racao")))
    gasto, credito = float(c.get("gasto_desde_leitura_usd", 0)), float(c.get("credito_usd", 0))
    print("1. normal:           " + perguntar("claude-volume"))
    extra = max(0.0, credito * 0.85 - gasto) + 1.0
    http("POST", "/porteiro/simular", {"gasto_hoje_extra_usd": extra})
    print("   (simulado: mais %.2f USD de gasto, para passar os 85%%)" % extra)
    print("2. poupanca, volume: " + perguntar("claude-volume"))
    print("3. poupanca, Hermes: " + perguntar("claude-decisao"))
    http("POST", "/porteiro/simular", {"gasto_hoje_extra_usd": 0, "sem_saldo": True})
    print("   (simulado: credito esgotado)")
    print("4. sem saldo, Hermes: " + perguntar("claude-decisao"))
    http("POST", "/porteiro/simular", {"gasto_hoje_extra_usd": 0, "sem_saldo": False})
    print("   (simulacao desligada)")
    print("5. de volta:          " + perguntar("claude-volume"))
    st, e = http("GET", "/porteiro")
    print("simulacao no fim: %s" % (e.get("simular") if isinstance(e, dict) else "?"))


if __name__ == "__main__":
    if "--provar" not in sys.argv:
        aplicar()
    provar()

# -*- coding: utf-8 -*-
"""telegram.py — avisar o Danilo. No PC vai por SSH ate a VPS e usa o `hermes send`; na VPS chama
o docker directamente. Nunca bloqueia o atendimento: uma falha fica no log, com o erro real.

O cerebro antigo falhava aqui em silencio: `telegram-falhou` x4 a 31/08 com o texto do erro
cortado. Agora: caminho absoluto do ssh (a tarefa agendada nao tem o PATH do utilizador), 25 s
de espera, uma repeticao, e o erro completo escrito no log.
"""
import os
import subprocess
import sys
import time

VPS_HOST = "srv1786862.hstgr.cloud"
VPS_KEY = os.path.join(os.path.expanduser("~"), ".ssh", "id_ed25519_vps")
HERMES_C = "hermes-agent-fvnc-hermes-agent-1"
NA_VPS = os.path.exists("/root/whatsapp-bora") and sys.platform.startswith("linux")


def _ssh_exe():
    for p in (r"C:\Windows\System32\OpenSSH\ssh.exe", r"C:\Program Files\Git\usr\bin\ssh.exe"):
        if os.path.exists(p):
            return p
    return "ssh"


def _remoto(msg):
    m = (msg or "").replace("'", "'\"'\"'")
    return "docker exec -u hermes %s /opt/hermes/bin/hermes send -t telegram '%s'" % (HERMES_C, m)


SILENCIO = False      # modo prova: nao se incomoda o Danilo; fica no log o que se TERIA enviado


def enviar(msg, registar=None, tentativas=2):
    """Devolve (ok, detalhe). `registar` e a funcao de log do servidor (opcional)."""
    msg = (msg or "").strip()[:3500]
    if SILENCIO:
        if registar:
            registar({"evento": "telegram-prova", "msg": msg[:300]})
        return True, "modo prova: nao enviado -- " + msg[:120]
    ultimo = ""
    for _ in range(tentativas):
        try:
            if NA_VPS:
                cmd = ["bash", "-lc", _remoto(msg)]
            else:
                cmd = [_ssh_exe(), "-i", VPS_KEY, "-o", "BatchMode=yes", "-o", "ConnectTimeout=12",
                       "-o", "StrictHostKeyChecking=accept-new", "root@" + VPS_HOST, _remoto(msg)]
            r = subprocess.run(cmd, capture_output=True, text=True, timeout=25)
            saida = (r.stdout or "") + (r.stderr or "")
            if r.returncode == 0:
                if registar:
                    registar({"evento": "telegram", "ok": True, "msg": msg[:200]})
                return True, saida.strip()[:200]
            ultimo = "rc=%s %s" % (r.returncode, saida.strip()[:300])
        except Exception as e:  # noqa: BLE001
            ultimo = "%s: %s" % (type(e).__name__, str(e)[:300])
        time.sleep(1.5)
    if registar:
        registar({"evento": "telegram-falhou", "erro": ultimo, "msg": msg[:200]})
    return False, ultimo


if __name__ == "__main__":
    print(enviar(" ".join(sys.argv[1:]) or "teste do cerebro v2 (ignorar)"))

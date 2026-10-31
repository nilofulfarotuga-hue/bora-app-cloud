#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
porteiro_cli.py — falar com o PORTEIRO (a unica porta para o chat do Danilo) a partir de qualquer script, na VPS ou
dentro do contentor do Hermes. So biblioteca padrao. (missao retoma-geral-2026-10-31, bloco 6)

  porteiro_cli.py danilo URGENTE|RESULTADO|INFO [--origem X] [--foto CAMINHO]... (texto | -f FICHEIRO | -)
  porteiro_cli.py send [-t ALVO] [-f CAMINHO] [-s LINHA] [-q] [--json] [mensagem]
        substitui `hermes send -t telegram ...`: o mesmo formato. Se o alvo for o Telegram do Danilo (telegram ou
        telegram:<chat dele>) vai pelo porteiro (linhas MEDIA:<caminho> viram anexos); qualquer outro alvo segue para o
        `hermes send` verdadeiro, tal e qual.
O remetente (origem) e' o nome do script que chamou (ou PORTEIRO_ORIGEM). O nivel, se nao vier, decide-o o porteiro.
Sai 0 se o porteiro aceitou (enviado, guardado nos bastidores ou repetido descartado).
"""
import base64
import json
import os
import re
import subprocess
import sys
import urllib.request

URLS = ["http://172.16.1.1:8796/telegram_danilo", "http://127.0.0.1:8796/telegram_danilo"]
CHAT_DANILO = "6731890157"
CONTENTOR = "hermes-agent-fvnc-hermes-agent-1"


def origem_chamador():
    o = os.environ.get("PORTEIRO_ORIGEM")
    if o:
        return o
    pid = os.getppid()
    for _ in range(4):
        try:
            with open("/proc/%d/cmdline" % pid, "rb") as fh:
                args = [x.decode("utf-8", "replace") for x in fh.read().split(b"\0") if x]
            for x in args[1:] + args[:1]:
                b = os.path.basename(x)
                if re.search(r"\.(sh|py|js)$", b) and b not in ("porteiro_cli.py",):
                    return re.sub(r"\.(sh|py|js)$", "", b)
            with open("/proc/%d/stat" % pid) as fh:
                pid = int(fh.read().rsplit(")", 1)[1].split()[1])
        except Exception:  # noqa: BLE001
            break
    return "desconhecido"


def pedir(texto, nivel, origem, anexos):
    corpo = json.dumps({"texto": texto, "nivel": nivel, "origem": origem,
                        "ensaio": os.environ.get("PORTEIRO_ENSAIO") == "1",
                        "ficheiros": [{"nome": os.path.basename(p), "b64": base64.b64encode(open(p, "rb").read()).decode()}
                                      for p in anexos]}).encode("utf-8")
    ultimo = None
    for u in URLS:
        try:
            req = urllib.request.Request(u, data=corpo, headers={"Content-Type": "application/json"})
            with urllib.request.urlopen(req, timeout=150) as r:
                return json.loads(r.read().decode("utf-8"))
        except urllib.error.HTTPError as e:
            try:
                return json.loads(e.read().decode("utf-8"))
            except Exception:  # noqa: BLE001
                return {"ok": False, "erro": "HTTP %s" % e.code}
        except Exception as e:  # noqa: BLE001
            ultimo = str(e)[:150]
    return {"ok": False, "erro": "porteiro inacessivel: %s" % ultimo}


def hermes_send_verdadeiro(args):
    if os.path.exists("/usr/local/bin/hermes") and os.path.exists("/opt/hermes"):
        return subprocess.call(["hermes", "send"] + args)
    return subprocess.call(["docker", "exec", "-u", "hermes", CONTENTOR, "hermes", "send"] + args)


def cmd_send(a):
    alvo, fich, assunto, quieto, js, resto = "telegram", None, None, False, False, []
    i = 0
    while i < len(a):
        x = a[i]
        if x in ("-t", "--to") and i + 1 < len(a):
            alvo = a[i + 1]; i += 2; continue
        if x in ("-f", "--file") and i + 1 < len(a):
            fich = a[i + 1]; i += 2; continue
        if x in ("-s", "--subject") and i + 1 < len(a):
            assunto = a[i + 1]; i += 2; continue
        if x in ("-q", "--quiet"):
            quieto = True; i += 1; continue
        if x == "--json":
            js = True; i += 1; continue
        resto.append(x); i += 1
    if alvo not in ("telegram", "telegram:" + CHAT_DANILO):
        return hermes_send_verdadeiro(a)
    if fich and fich != "-":
        texto = open(fich, encoding="utf-8").read()
    elif resto:
        texto = " ".join(resto)
    else:
        texto = sys.stdin.buffer.read().decode("utf-8", "replace")
    if assunto:
        texto = assunto + "\n" + texto
    anexos, linhas = [], []
    for ln in texto.splitlines():
        m = re.match(r"^\s*MEDIA:(\S+)\s*$", ln)
        if m and os.path.exists(m.group(1)):
            anexos.append(m.group(1))
        else:
            linhas.append(ln)
    r = pedir("\n".join(linhas).strip(), os.environ.get("PORTEIRO_NIVEL"), origem_chamador(), anexos)
    if js:
        print(json.dumps({"success": bool(r.get("ok")), "platform": "telegram", "porteiro": r}, ensure_ascii=False))
    elif not quieto:
        print("porteiro: %s (%s)" % (r.get("destino") or "falhou", r.get("nivel")))
    return 0 if r.get("ok") else 1


def cmd_danilo(a):
    nivel, origem, fotos, fich, resto = a[0], None, [], None, []
    i = 1
    while i < len(a):
        if a[i] == "--origem" and i + 1 < len(a):
            origem = a[i + 1]; i += 2; continue
        if a[i] == "--foto" and i + 1 < len(a):
            fotos.append(a[i + 1]); i += 2; continue
        if a[i] == "-f" and i + 1 < len(a):
            fich = a[i + 1]; i += 2; continue
        resto.append(a[i]); i += 1
    texto = open(fich, encoding="utf-8").read() if fich else (sys.stdin.buffer.read().decode("utf-8", "replace") if resto == ["-"] else " ".join(resto))
    r = pedir(texto, nivel, origem or origem_chamador(), fotos)
    print(json.dumps(r, ensure_ascii=False))
    return 0 if r.get("ok") else 1


def main():
    a = sys.argv[1:]
    if len(a) >= 2 and a[0] == "danilo":
        return cmd_danilo(a[1:])
    if a and a[0] == "send":
        return cmd_send(a[1:])
    print(__doc__)
    return 2


if __name__ == "__main__":
    sys.exit(main())

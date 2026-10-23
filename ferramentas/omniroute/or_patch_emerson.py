#!/usr/bin/env python3
"""Bloco 4 (omniroute-23-10): o Emerson (despachante.py + emerson.py) passa a perguntar ao OmniRoute.

Remendos por ancora exacta (falha alto se a ancora nao existir). Copia antes em /root/backups.
Escreve no mesmo ficheiro (mantem dono hermes-exec e permissoes). Valida com py_compile no fim.
Uso: or_patch_emerson.py [--desfazer]
"""
import os
import py_compile
import shutil
import sys

R = "/opt/data/rotinas"
BK = "/root/backups/rotinas-antes-omniroute-20261023"

DESP = [
    ('MOTOR = os.environ.get("MOTOR_BORA_URL", "http://172.16.1.1:8792/v1")\n',
     '# 23/10/2026 (missao omniroute-23-10): o modelo passa pelo OmniRoute (recuo automatico entre\n'
     '# fornecedores, chave em /opt/data/.env). O Motor Bora antigo fica de reserva: se o OmniRoute\n'
     '# nao responder, pedir_modelo() tenta la. Fica assim pelo menos ate 30/10.\n'
     'MOTOR = os.environ.get("MOTOR_BORA_URL", "http://127.0.0.1:20128/v1")\n'
     'MOTOR_RESERVA = "http://172.16.1.1:8792/v1"\n'),
    ('def _escolher_com_modelo(pedido, cart):\n',
     'def _chave_omniroute():\n'
     '    try:\n'
     '        for ln in open("/opt/data/.env", encoding="utf-8"):\n'
     '            if ln.startswith("OMNIROUTE_API_KEY="):\n'
     '                return ln.split("=", 1)[1].strip()\n'
     '    except Exception:\n'
     '        pass\n'
     '    return ""\n'
     '\n'
     '\n'
     'def pedir_modelo(corpo, origem, timeout):\n'
     '    """POST /chat/completions no OmniRoute; se falhar, tenta o Motor Bora (reserva). Devolve o JSON."""\n'
     '    ultimo = None\n'
     '    for base in (MOTOR, MOTOR_RESERVA):\n'
     '        h = {"Content-Type": "application/json", "X-Motor-Origem": origem}\n'
     '        if base == MOTOR:\n'
     '            h["Authorization"] = "Bearer " + _chave_omniroute()\n'
     '        try:\n'
     '            req = urllib.request.Request(base + "/chat/completions", data=corpo, headers=h)\n'
     '            return json.loads(urllib.request.urlopen(req, timeout=timeout).read().decode())\n'
     '        except Exception as e:\n'
     '            ultimo = e\n'
     '            registar(evento="modelo-falhou", base=base, origem=origem, erro=str(e)[:200])\n'
     '    raise ultimo\n'
     '\n'
     '\n'
     'def _escolher_com_modelo(pedido, cart):\n'),
    ('        req = urllib.request.Request(MOTOR + "/chat/completions", data=corpo,\n'
     '                                     headers={"Content-Type": "application/json",\n'
     '                                              "X-Motor-Origem": "despachante"})\n'
     '        d = json.loads(urllib.request.urlopen(req, timeout=120).read().decode())\n',
     '        d = pedir_modelo(corpo, "despachante", 120)\n'),
    ("    guiao = 'cd /opt/data && exec hermes -p \"$1\" --provider custom -m perfil:raciocinio -z \"$2\"'\n",
     "    # 23/10: sem -m — cada perfil usa o modelo do seu config.yaml (agentes; a torre usa `privado`,\n"
     "    # que so passa por quem nao treina com os dados). Os perfis ainda no Motor Bora continuam no\n"
     "    # perfil:raciocinio de sempre, que e o default deles.\n"
     "    guiao = 'cd /opt/data && exec hermes -p \"$1\" --provider custom -z \"$2\"'\n"),
]

EMER = [
    ('        req = urllib.request.Request(D.MOTOR + "/chat/completions", data=corpo,\n'
     '                                     headers={"Content-Type": "application/json",\n'
     '                                              "X-Motor-Origem": "emerson"})\n'
     '        d = json.loads(urllib.request.urlopen(req, timeout=180).read().decode())\n',
     '        d = D.pedir_modelo(corpo, "emerson", 180)  # 23/10: OmniRoute, com o Motor Bora de reserva\n'),
]


def remendar(path, trocas):
    txt = open(path, encoding="utf-8").read()
    for antes, depois in trocas:
        if txt.count(antes) != 1:
            raise SystemExit(f"ancora nao encontrada (ou repetida) em {path}: {antes[:70]!r}")
        txt = txt.replace(antes, depois)
    with open(path, "w", encoding="utf-8") as fh:
        fh.write(txt)
    py_compile.compile(path, doraise=True, cfile="/tmp/_pc_omniroute.pyc")
    print("remendado e compila:", path)


def main():
    if "--desfazer" in sys.argv:
        for f in ("despachante.py", "emerson.py"):
            with open(os.path.join(BK, f), encoding="utf-8") as a, open(os.path.join(R, f), "w", encoding="utf-8") as b:
                b.write(a.read())
            print("reposto:", f)
        return
    os.makedirs(BK, mode=0o700, exist_ok=True)
    for f in ("despachante.py", "emerson.py"):
        if not os.path.exists(os.path.join(BK, f)):
            shutil.copy2(os.path.join(R, f), os.path.join(BK, f))
    remendar(os.path.join(R, "despachante.py"), DESP)
    remendar(os.path.join(R, "emerson.py"), EMER)


if __name__ == "__main__":
    main()

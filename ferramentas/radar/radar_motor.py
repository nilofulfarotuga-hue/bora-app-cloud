#!/usr/bin/env python3
"""radar_motor.py — pede o relatório do radar ao Motor Bora (rotação de motores grátis da VPS).

M10 (09/11/2026): o radar-ia.sh deixou de sair desde a semana 40 porque os cinco modelos do
`hermes -z` falhavam todos no mesmo segundo ("no final response was produced"). O Motor Bora
(http://172.16.1.1:8792, o mesmo que serve o Hermes e o Dipsy) roda ~10 fornecedores grátis com
descida automática; o material do radar é público (GitHub, RSS, vídeos), sem dados de clientes.

Uso: radar_motor.py <ficheiro_prompt>   -> imprime a resposta; sai 0 só com texto >= 200 letras.
Variáveis: RADAR_MOTOR_URL (defeito http://172.16.1.1:8792/v1/chat/completions),
           RADAR_MOTOR_PERFIL (defeito perfil:volume), RADAR_MOTOR_MAX (defeito 3000).
"""
import json
import os
import sys
import urllib.request

URL = os.environ.get("RADAR_MOTOR_URL", "http://172.16.1.1:8792/v1/chat/completions")
PERFIL = os.environ.get("RADAR_MOTOR_PERFIL", "perfil:volume")
MAXT = int(os.environ.get("RADAR_MOTOR_MAX", "3000"))


def main():
    prompt = open(sys.argv[1], encoding="utf-8").read()
    corpo = json.dumps({"model": PERFIL, "messages": [{"role": "user", "content": prompt}],
                        "max_tokens": MAXT, "temperature": 0.3}).encode("utf-8")
    req = urllib.request.Request(URL, data=corpo, headers={"Content-Type": "application/json",
                                                           "X-Motor-Origem": "radar-ia"})
    try:
        with urllib.request.urlopen(req, timeout=300) as r:
            j = json.load(r)
    except Exception as e:  # noqa: BLE001
        sys.stderr.write("motor falhou: %s\n" % str(e)[:200])
        return 2
    txt = ((j.get("choices") or [{}])[0].get("message") or {}).get("content") or ""
    if len(txt.strip()) < 200:
        sys.stderr.write("motor respondeu curto (%d letras) modelo=%s\n" % (len(txt), j.get("model")))
        return 3
    sys.stdout.write(txt.strip() + "\n")
    sys.stderr.write("motor ok: %s\n" % j.get("model"))
    return 0


if __name__ == "__main__":
    sys.exit(main())

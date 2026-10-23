#!/usr/bin/env python3
"""Prova de descida (omniroute-23-10, bloco 3): estraga de proposito as chaves do 1.o nivel vivo do
combo `agentes` (gemini) e mostra quem responde; depois repoe as chaves verdadeiras (lidas dos .env,
nunca impressas) e prova que o gemini volta. O 1.o nivel nominal (opencode-go) ja esta morto de verdade
(chave expirada), por isso a descida go -> gemini fica provada em cada chamada normal.
"""
import json
import subprocess
import time

G1, G2 = "47cbbfc2-e587-4be6-bfd9-4375b5759622", "e960802b-31f4-49ac-9df9-d4376016ad71"
FONTES = {G1: ("/opt/data/.env", "GEMINI_API_KEY"), G2: ("/opt/whatsapp-bora/.env", "GEMINI_API_KEY")}


def chave(path, nome):
    for linha in open(path, encoding="utf-8"):
        if linha.startswith(nome + "="):
            return linha.split("=", 1)[1].strip().strip('"').strip("'")
    raise SystemExit(f"sem {nome} em {path}")


def admin(metodo, caminho, corpo=None):
    a = ["python3", "/opt/omniroute/or_admin.py", metodo, caminho] + ([json.dumps(corpo)] if corpo is not None else [])
    r = subprocess.run(a, capture_output=True, text=True)
    return r.stdout.split("\n", 1)[0]


def prova(rotulo):
    r = subprocess.run("python3 /opt/omniroute/or_prova.py agentes | python3 /opt/omniroute/or_ver.py",
                       shell=True, capture_output=True, text=True)
    print(time.strftime("%H:%M:%S"), rotulo, "=>", r.stdout.strip())


def main():
    prova("antes (tudo bem)")
    print("estraga gemini-1:", admin("PUT", f"/api/providers/{G1}", {"apiKey": "CHAVE-ESTRAGADA-DE-PROPOSITO"}))
    time.sleep(6)
    prova("gemini-1 estragada (deve ir ao gemini-2)")
    print("estraga gemini-2:", admin("PUT", f"/api/providers/{G2}", {"apiKey": "CHAVE-ESTRAGADA-DE-PROPOSITO"}))
    time.sleep(6)
    prova("gemini-1 e gemini-2 estragadas (deve descer ao nvidia)")
    for cid, (p, n) in FONTES.items():
        print("repoe", cid[:8], ":", admin("PUT", f"/api/providers/{cid}", {"apiKey": chave(p, n), "isActive": True}),
              "teste:", subprocess.run(["python3", "/opt/omniroute/or_admin.py", "POST", f"/api/providers/{cid}/test", "{}"],
                                       capture_output=True, text=True).stdout.replace("\n", " ")[:90])
    time.sleep(6)
    prova("chaves repostas (deve voltar ao gemini)")


if __name__ == "__main__":
    main()

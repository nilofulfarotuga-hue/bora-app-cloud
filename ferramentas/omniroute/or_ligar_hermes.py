#!/usr/bin/env python3
"""Bloco 4 (omniroute-23-10): aponta o Hermes/Emerson e os perfis pedidos ao OmniRoute.

Mexe em DOIS sitios por perfil, porque so a variavel de ambiente nao chega:
  - config.yaml, bloco `model:` -> provider custom, base_url do OmniRoute, api_key ${OMNIROUTE_API_KEY},
    default = combo (agentes; a torre vai para `privado`, que so usa quem nao treina com os dados)
  - .env -> HERMES_BASE_URL / HERMES_MODEL / HERMES_INFERENCE_MODEL e OMNIROUTE_API_KEY
Copia de seguranca antes (tar em /root/backups, so root). Mantem dono (uid 10000) e permissoes.
Uso: or_ligar_hermes.py [--desfazer]
"""
import os
import re
import shutil
import sys
import tarfile
import time

DATA = "/docker/hermes-agent-fvnc/data"
URL = "http://omniroute:20128/v1"
ALVOS = {DATA: "agentes"}
for p in ("fiscal", "batedor", "escriba", "critico", "vendedor"):
    ALVOS[f"{DATA}/profiles/{p}"] = "agentes"
ALVOS[f"{DATA}/profiles/torre"] = "privado"
BACKUP = "/root/backups/hermes-antes-omniroute-20261023.tar.gz"


def chave():
    for ln in open(f"{DATA}/.env", encoding="utf-8"):
        if ln.startswith("OMNIROUTE_API_KEY="):
            return ln.split("=", 1)[1].strip()
    raise SystemExit("sem OMNIROUTE_API_KEY em /opt/data/.env")


def escrever(path, texto):
    # Escreve no MESMO ficheiro (mesmo inode): mantem dono, permissoes e a ACL do /opt/data/.env.
    # Um os.replace criava ficheiro novo e perdia a ACL (cicatriz: .env das redes sem permissao).
    with open(path, "w", encoding="utf-8") as fh:
        fh.write(texto)


def editar_config(path, combo):
    linhas = open(path, encoding="utf-8").read().split("\n")
    i0 = next(i for i, l in enumerate(linhas) if l == "model:")
    i1 = next((i for i in range(i0 + 1, len(linhas)) if linhas[i] and not linhas[i].startswith(" ")), len(linhas))
    bloco = [l for l in linhas[i0 + 1:i1] if not re.match(r"^  (default|provider|base_url|api_key):", l)]
    novo = ["model:", f"  default: {combo}", "  provider: custom", f"  base_url: {URL}",
            "  api_key: ${OMNIROUTE_API_KEY}"] + bloco
    escrever(path, "\n".join(linhas[:i0] + novo + linhas[i1:]))


def editar_env(path, combo, k):
    linhas = open(path, encoding="utf-8").read().rstrip("\n").split("\n")
    quer = {"HERMES_INFERENCE_PROVIDER": "custom", "HERMES_MODEL": combo, "HERMES_INFERENCE_MODEL": combo,
            "HERMES_BASE_URL": URL, "OMNIROUTE_API_KEY": k}
    vistos, out = set(), []
    for l in linhas:
        n = l.split("=", 1)[0]
        if n in quer:
            if n in vistos:
                continue
            out.append(f"{n}={quer[n]}")
            vistos.add(n)
        else:
            out.append(l)
    for n, v in quer.items():
        if n not in vistos:
            out.append(f"{n}={v}")
    escrever(path, "\n".join(out) + "\n")


def main():
    if "--desfazer" in sys.argv:
        with tarfile.open(BACKUP) as t:
            t.extractall("/", filter="tar")
        print("reposto a partir de", BACKUP)
        return
    if not os.path.exists(BACKUP):
        os.makedirs("/root/backups", mode=0o700, exist_ok=True)
        with tarfile.open(BACKUP, "w:gz") as t:
            for d in ALVOS:
                for f in ("config.yaml", ".env"):
                    t.add(os.path.join(d, f))
        os.chmod(BACKUP, 0o600)
        print("copia:", BACKUP)
    k = chave()
    for d, combo in ALVOS.items():
        editar_config(os.path.join(d, "config.yaml"), combo)
        editar_env(os.path.join(d, ".env"), combo, k)
        print(f"{d.replace(DATA, '/opt/data')}: model -> {combo} @ {URL}")


if __name__ == "__main__":
    main()

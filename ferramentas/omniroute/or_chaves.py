#!/usr/bin/env python3
"""Fecha as tres chaves das maquinas aos modelos e combos daqui (or_combos.py): sem `auto/*`, sem cache,
sem compressao. Corre-se sempre que os combos mudam, para nenhuma chave poder pedir um modelo que ja saiu
(23/10: o OpenCode Go saiu de tudo).
  agentes-bora       -> todos os combos + nomes antigos
  conselho-juiz      -> as 3 vozes + nomes antigos + perfis do Motor
  pc-opencode-danilo -> combo agentes
"""
import json
import subprocess
import sys

sys.path.insert(0, "/opt/omniroute")
from or_combos import COMBOS, MAPAS, MOTOR  # noqa: E402

D = "/opt/omniroute/"


def modelos(nomes, extra=()):
    return sorted({m for n in nomes for m in COMBOS[n]["models"]} | set(extra))


CHAVES = {
    ".agentes.key.id": modelos(COMBOS, MAPAS),
    ".conselho.key.id": modelos([n for n in COMBOS if n.startswith("voz-")], set(MAPAS) | {
        MOTOR + "perfil:raciocinio", MOTOR + "perfil:chat-rapido", MOTOR + "perfil:volume"}),
    ".pc.key.id": modelos(["agentes"], {"perfil:raciocinio"}),
}

for ficheiro, ms in CHAVES.items():
    kid = open(D + ficheiro).read().strip()
    corpo = {"modelAccessMode": "restricted", "allowedModels": ms, "allowAutoCombos": False,
             "cacheDefaultMode": "bypass", "compressionEnabled": False}
    r = subprocess.run(["python3", D + "or_admin.py", "PATCH", f"/api/keys/{kid}", json.dumps(corpo)],
                       capture_output=True, text=True)
    go = [m for m in ms if m.startswith("opencode-go/")]
    print(ficheiro, "->", r.stdout.split("\n")[0], "| modelos", len(ms), "| opencode-go:", len(go))

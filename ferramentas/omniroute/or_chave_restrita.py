#!/usr/bin/env python3
"""Fecha a chave dos agentes: so os nossos combos e os modelos provados; sem `auto/*`, sem cache.
Assim nenhum agente consegue pedir os fornecedores "sem chave" que o OmniRoute traz de fabrica
(pontes de CLI de terceiros, DuckDuckGo, playgrounds) — so o que esta nos combos."""
import json
import subprocess
import sys

sys.path.insert(0, "/opt/omniroute")
from or_combos import COMBOS, MAPAS  # noqa: E402

KID = open("/opt/omniroute/.agentes.key.id").read().strip()
modelos = sorted({m for c in COMBOS.values() for m in c["models"]} | set(MAPAS) | set(sys.argv[1:]))
corpo = {"modelAccessMode": "restricted", "allowedModels": modelos, "allowAutoCombos": False,
         "cacheDefaultMode": "bypass", "compressionEnabled": False, "catalogScope": "all"}
r = subprocess.run(["python3", "/opt/omniroute/or_admin.py", "PATCH", f"/api/keys/{KID}", json.dumps(corpo)],
                   capture_output=True, text=True)
print(r.stdout[:600], r.stderr[:300])
print("modelos permitidos:", len(modelos))

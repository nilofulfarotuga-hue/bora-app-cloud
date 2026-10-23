#!/bin/bash
# Bloco 4 (omniroute-23-10): o Conselho (segunda opiniao do juiz) passa a perguntar ao OmniRoute.
# Chave propria (conselho-juiz), so com as vozes e os perfis. A chave Go antiga (expirada) sai do .env.
set -euo pipefail
cd /opt/omniroute
if [ ! -f .conselho.key ]; then
  OR_RAW=1 python3 or_admin.py POST /api/keys '{"name":"conselho-juiz"}' | tail -n +2 > /root/.cj.json
  umask 077
  python3 -c 'import json;d=json.load(open("/root/.cj.json"));open("/opt/omniroute/.conselho.key","w").write(d["key"]);open("/opt/omniroute/.conselho.key.id","w").write(d["id"]);print("chave criada", d["name"], d["id"][:8])'
  shred -u /root/.cj.json
fi
python3 - <<'EOF'
import json, subprocess, sys
sys.path.insert(0, "/opt/omniroute")
from or_combos import COMBOS, MAPAS
kid = open("/opt/omniroute/.conselho.key.id").read().strip()
vozes = [n for n in COMBOS if n.startswith("voz-")]
ms = sorted({m for n in vozes for m in COMBOS[n]["models"]} | set(MAPAS) | {"motor/perfil:raciocinio", "motor/perfil:chat-rapido", "motor/perfil:volume"})
corpo = {"modelAccessMode": "restricted", "allowedModels": ms, "allowAutoCombos": False, "cacheDefaultMode": "bypass", "compressionEnabled": False}
r = subprocess.run(["python3", "/opt/omniroute/or_admin.py", "PATCH", "/api/keys/" + kid, json.dumps(corpo)], capture_output=True, text=True)
print("chave conselho:", r.stdout.split("\n")[0], "modelos", len(ms))
EOF
E=/root/conselho-mcp/.env
cp -p $E /root/backups/conselho-env-antes-omniroute-20261023
K=$(cat /opt/omniroute/.conselho.key)
python3 - "$E" "$K" <<'EOF'
import sys
p, k = sys.argv[1], sys.argv[2]
quer = {"CONSELHO_BASE": "http://omniroute:20128", "CONSELHO_CHAVE": k, "OPENCODE_GO_KEY": ""}
out, vistos = [], set()
for l in open(p, encoding="utf-8").read().rstrip("\n").split("\n"):
    n = l.split("=", 1)[0]
    if n in quer:
        if n in vistos:
            continue
        out.append(f"{n}={quer[n]}"); vistos.add(n)
    else:
        out.append(l)
for n, v in quer.items():
    if n not in vistos:
        out.append(f"{n}={v}")
open(p, "w", encoding="utf-8").write("\n".join(out) + "\n")
print("conselho .env: CONSELHO_BASE -> omniroute, CONSELHO_CHAVE posta, OPENCODE_GO_KEY (expirada) vazia")
EOF
bash /root/conselho-mcp/deploy.sh 2>&1 | tail -3

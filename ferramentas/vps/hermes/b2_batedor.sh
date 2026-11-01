#!/bin/bash
# B2: batedor (radar semanal de IA) passa do combo "agentes" (Sonnet) para o Motor perfil:claude-agente (Haiku),
# como os outros agentes de volume; depois reinicia o gateway do Hermes e confirma a ponte.
C=hermes-agent-fvnc-hermes-agent-1
F=/opt/data/profiles/batedor/config.yaml
echo "== bloco model: agenda vs batedor (sem chaves) =="
for p in agenda batedor; do echo "-- $p"; docker exec $C sed -n '1,8p' /opt/data/profiles/$p/config.yaml | sed -E 's/(api_key|key|token)(\s*:\s*).+/\1\2***/I'; done
docker exec $C bash -c "[ -f $F.bak-infra-20261101 ] || cp -p $F $F.bak-infra-20261101"
docker exec -i $C python3 - "$F" <<'EOF'
import sys
f = sys.argv[1]
ls = open(f, encoding="utf-8").read().split("\n")
assert ls[0].strip() == "model:", ls[0]
mud = 0
for i in range(1, 8):
    s = ls[i].strip()
    if s == "default: agentes":
        ls[i] = ls[i].replace("default: agentes", "default: perfil:claude-agente"); mud += 1
    elif s == "base_url: http://omniroute:20128/v1":
        ls[i] = ls[i].replace("http://omniroute:20128/v1", "http://172.16.1.1:8792/v1"); mud += 1
open(f, "w", encoding="utf-8").write("\n".join(ls))
print("batedor: %d linhas mudadas" % mud)
EOF
docker exec $C sed -n '1,8p' $F | sed -E 's/(api_key|key|token)(\s*:\s*).+/\1\2***/I'

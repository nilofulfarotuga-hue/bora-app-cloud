#!/bin/bash
# B2: (1) tira as reservas mortas (OpenCode Zen) que ficaram soltas depois de "fallback_providers: []" nos perfis
# escriba e fiscal (YAML partido desde 31/10 11:03); (2) mostra o primeiro motor de cada combo do OmniRoute.
C=hermes-agent-fvnc-hermes-agent-1
SUF=bak-infra-20261101
for p in escriba fiscal; do
  F=/opt/data/profiles/$p/config.yaml
  docker exec $C bash -c "[ -f $F.$SUF ] || cp -p $F $F.$SUF"
  docker exec -i $C python3 - "$F" <<'EOF'
import sys
f = sys.argv[1]
ls = open(f, encoding="utf-8").read().split("\n")
out, saltar = [], False
for l in ls:
    if l.strip() == "fallback_providers: []":
        out.append(l); saltar = True; continue
    if saltar and (l.startswith("- ") or l.startswith("  ")):
        continue
    saltar = False
    out.append(l)
open(f, "w", encoding="utf-8").write("\n".join(out))
print("tirei", len(ls) - len(out), "linhas de", f)
EOF
done
cat > /tmp/valida.py <<'EOF'
import sys, yaml
for f in sys.argv[1:]:
    d = yaml.safe_load(open(f, encoding="utf-8"))
    m = d.get("model") or {}
    print("OK yaml", f.split("/")[-2], "default=", m.get("default"), "base=", m.get("base_url"), "fallback=", d.get("fallback_providers"))
EOF
docker cp /tmp/valida.py $C:/tmp/valida.py
docker exec $C bash -c 'for py in /opt/hermes/.venv/bin/python /usr/bin/python3 python3; do "$py" -c "import yaml" 2>/dev/null && { "$py" /tmp/valida.py /opt/data/profiles/escriba/config.yaml /opt/data/profiles/fiscal/config.yaml; break; }; done'
echo "== combos =="
cd /opt/omniroute && python3 or_admin.py GET /api/combos 2>/dev/null | tail -n +2 | python3 -c '
import json,sys
d=json.load(sys.stdin)
for c in d.get("combos",[]):
    print(c.get("name"), "->", [m.get("model") for m in c.get("models",[])][:4])
'

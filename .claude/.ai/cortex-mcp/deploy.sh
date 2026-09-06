#!/usr/bin/env bash
# Deploy do Cortex MCP no VPS, atrás do traefik (HTTPS letsencrypt), com token.
# Escrita começa DESLIGADA. Corre no HOST do VPS. Idempotente.
set -euo pipefail
DOMAIN="${DOMAIN:-cortex.srv1786862.hstgr.cloud}"
HERMES=hermes-agent-fvnc-hermes-agent-1
DIR=/root/cortex-mcp                 # onde vivem server.mjs + Dockerfile no HOST
SECRETS=/opt/data/.secrets           # dentro do volume do Hermes
TOKFILE=/root/cortex_mcp_token       # token no host (600) — o server lê por env

# 1) token forte (gera uma vez)
if [ ! -f "$TOKFILE" ]; then head -c 32 /dev/urandom | base64 | tr -dc 'A-Za-z0-9' | cut -c1-40 > "$TOKFILE"; chmod 600 "$TOKFILE"; fi
TOKEN=$(cat "$TOKFILE")

# 2) descobre a rede do traefik (a mesma do Hermes) e o host-path do volume /opt/data
NET=$(docker inspect "$HERMES" --format '{{range $k,$v := .NetworkSettings.Networks}}{{$k}} {{end}}' | awk '{print $1}')
VOL=$(docker inspect "$HERMES" --format '{{range .Mounts}}{{if eq .Destination "/opt/data"}}{{.Source}}{{end}}{{end}}')
echo "NET=$NET  VOL=$VOL  DOMAIN=$DOMAIN"
[ -n "$NET" ] && [ -n "$VOL" ] || { echo "!! rede/volume não descobertos — abortar"; exit 1; }
OWN=$(docker exec -u hermes "$HERMES" stat -c '%u:%g' /opt/data/cortex-brain 2>/dev/null || echo 10000:10000)
echo "OWN(uid:gid do brain)=$OWN  (container corre com este user — não-root)"

# 2b) pasta de ESTADO do OAuth (2026-08-01, missao sistema-redondo parte 8)
# server.mjs está baked na imagem (Dockerfile: COPY), logo todo o deploy recria o container e o
# estado OAuth em memória evaporava — o conector do claude.ai ficava deslogado a cada redeploy.
# Volume próprio de propósito: .secrets está montado :ro e /brain é um clone git (reset --hard
# nocturno + risco de um `git add -A` alheio arrastar tokens para um commit).
STATEDIR=$DIR/state
mkdir -p "$STATEDIR"
chown -R "${OWN%%:*}:${OWN##*:}" "$STATEDIR"
chmod 700 "$STATEDIR"

# 3) build + (re)run
docker build -t cortex-mcp:latest "$DIR"
docker rm -f cortex-mcp >/dev/null 2>&1 || true
docker run -d --name cortex-mcp --restart unless-stopped --network "$NET" --user "$OWN" \
  -e CORTEX_TOKEN="$TOKEN" \
  -e CORTEX_OAUTH_STATE=/state/oauth.json \
  -e CORTEX_ISSUER="https://$DOMAIN" \
  -e CORTEX_BRAIN=/brain/.claude/.ai/knowledge \
  -e CORTEX_WRITE_ENABLED=true \
  -e CORTEX_GIT_PUSH=true \
  `# escrita LIGADA desde 2026-07-08 (PAT rotacionado p/ deploy key + OAuth live + travas de zona no servidor). Reverter p/ false se o teste falhar.` \
  -v "$VOL/cortex-brain":/brain:rw \
  -v "$VOL/.secrets":/opt/data/.secrets:ro \
  -v "$STATEDIR":/state:rw \
  `# /state:rw = SO o estado do OAuth (clientes + tokens). Sobrevive ao redeploy; fora do repo git.` \
  `# .secrets:ro = deploy key + known_hosts p/ o git push via SSH (mesma chave do Hermes; NUNCA PAT). rw no brain: fila+log+páginas verdes.` \
  -l traefik.enable=true \
  -l "traefik.http.routers.cortex.rule=Host(\`$DOMAIN\`)" \
  -l traefik.http.routers.cortex.entrypoints=websecure \
  -l traefik.http.routers.cortex.tls.certresolver=letsencrypt \
  -l traefik.http.services.cortex.loadbalancer.server.port=4870 \
  cortex-mcp:latest
echo "== container up. a aguardar cert letsencrypt (~30s) =="
sleep 25
echo "-- sem token (deve 401) --"; curl -sko /dev/null -w '%{http_code}\n' "https://$DOMAIN/" || true
echo "-- com token (deve 200) --"; curl -sk -H "Authorization: Bearer $TOKEN" "https://$DOMAIN/" || true
echo "URL=https://$DOMAIN  (token em $TOKFILE)"

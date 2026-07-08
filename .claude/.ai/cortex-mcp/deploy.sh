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

# 3) build + (re)run
docker build -t cortex-mcp:latest "$DIR"
docker rm -f cortex-mcp >/dev/null 2>&1 || true
docker run -d --name cortex-mcp --restart unless-stopped --network "$NET" \
  -e CORTEX_TOKEN="$TOKEN" \
  -e CORTEX_BRAIN=/brain/.claude/.ai/knowledge \
  -e CORTEX_WRITE_ENABLED=false \
  -e CORTEX_GIT_PUSH=false \
  -v "$VOL/cortex-brain":/brain:ro \
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

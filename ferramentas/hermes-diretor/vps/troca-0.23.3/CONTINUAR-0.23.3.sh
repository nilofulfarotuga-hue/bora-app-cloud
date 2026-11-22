#!/bin/bash
# CONTINUAR-0.23.3.sh — os passos 4 a 6 da troca para a 0.23.3 (missao hermes-diretor-2026-11-20, B1).
# O script principal foi parado a mao as 19:53:12Z (no mesmo segundo em que o gateway subiu), por isso
# estes passos correm aqui: ponte, navegador, remendo da voz, Whisper, reinicio, voz do host.
# Nao manda mensagens a ninguem. Volta atras: VOLTAR-0.23.1.sh nesta pasta.
set -u
B=/root/backup-hermes-20261122
NOME=hermes-agent-fvnc-hermes-agent-1
D=/docker/hermes-agent-fvnc/data
log(){ echo "[$(date -u +%FT%TZ)] CONTINUAR: $*" | tee -a "$B/trocar.log"; }
ts_up(){
  docker exec "$NOME" sh -lc 'command -v tailscaled >/dev/null 2>&1 || curl -fsSL https://tailscale.com/install.sh | sh >/dev/null 2>&1' || true
  if ! docker exec "$NOME" sh -lc 'tailscale status >/dev/null 2>&1'; then
    docker exec "$NOME" sh -lc 'mkdir -p /var/run/tailscale; rm -f /var/run/tailscale/tailscaled.sock' || true
    docker exec -d "$NOME" tailscaled --tun=userspace-networking --socket=/var/run/tailscale/tailscaled.sock --state=/opt/data/tailscale/tailscaled.state
    sleep 6
    docker exec "$NOME" sh -lc 'tailscale up --hostname=bora-vps --ssh --timeout=30s' >/dev/null 2>&1 || true
  fi
  docker exec "$NOME" sh -lc 'tailscale status 2>&1 | head -2'
}
espera_gateway(){
  for i in $(seq 1 72); do
    docker exec "$NOME" sh -lc 'pgrep -f "[h]ermes gateway run|sys[.]exit[(]main[(][)][)] gateway run" >/dev/null' 2>/dev/null && { log "gateway vivo (${i}x5s)"; return 0; }
    sleep 5
  done
  log "gateway NAO subiu em 6 min"; return 1
}
[ "$(docker inspect -f '{{.Config.Image}}' "$NOME" 2>/dev/null)" = "nousresearch/hermes-agent:v0.23.3" ] || { log "RECUSO: o contentor vivo nao e a 0.23.3"; exit 3; }
espera_gateway || { log "gateway em baixo antes de comecar: nao avanco (decidir a mao entre esperar e VOLTAR)"; exit 4; }

log "tailscale"; ts_up | tee -a "$B/trocar.log"
/root/bora-bridge-up.sh >> "$B/trocar.log" 2>&1; log "bora-bridge-up corrido (rc=$?)"

docker exec -u root -w /opt/hermes "$NOME" /opt/hermes/.venv/bin/python -c 'import pm; pm.ensure_import("stt-whisper")' >> "$B/trocar.log" 2>&1 \
  && log "whisper local garantido" || log "AVISO: o instalador do whisper deu erro (ver trocar.log); segue"
chown -R 10000:10000 "$D/installs" "$D/cache/uv" "$D/logs/update_receipts" 2>/dev/null
docker exec -u hermes -e HOME=/opt/data "$NOME" sh -lc 'hermes pm repair' >> "$B/trocar.log" 2>&1 && log "pm repair ok" || log "AVISO: hermes pm repair deu erro; segue"
docker restart -t 30 "$NOME" >/dev/null; log "reiniciado para carregar o Whisper e o remendo da voz"
espera_gateway || { log "gateway NAO voltou depois do reinicio: decidir a mao (VOLTAR-0.23.1.sh)"; exit 4; }
ts_up | tee -a "$B/trocar.log"

bash /opt/data/voz/voz-up.sh >/dev/null 2>&1 && log "voz-up ok" || log "AVISO: voz-up deu erro"
chown -R 10000:10000 "$D/tools" "$D/cron" "$D/installs" 2>/dev/null
log "versao: $(docker exec "$NOME" sh -c 'hermes --version 2>&1 | head -1')"
log "remendo da voz: $(docker exec "$NOME" sh -c 'grep -c "remendo Bora 09-11" /opt/hermes/gateway/platforms/base.py') linha(s)"
log "fim da continuacao — agora as provas | livre $(df -BM --output=avail / | tail -1 | tr -d ' ') | mem $(free -m | awk '/^Mem:/{print $7}') MB"

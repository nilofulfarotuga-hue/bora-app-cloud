#!/bin/bash
# TROCAR-PARA-0.23.3.sh — troca o Hermes 0.23.1 pela 0.23.3 (missao hermes-diretor-2026-11-20, bloco B1).
# Molde: /root/backup-hermes-20261110/TROCAR-PARA-0.23.sh (10/11). Volta atras: VOLTAR-0.23.1.sh nesta pasta.
# Nao manda mensagens a ninguem. A 0.23.1 fica PARADA e inteira (hermes-0231-parado-20261122).
#   uso: bash TROCAR-PARA-0.23.3.sh           (faz a troca)
#        bash TROCAR-PARA-0.23.3.sh --ensaio  (so confere as pre-condicoes e mostra o que faria)
set -u
B=/root/backup-hermes-20261122
NOME=hermes-agent-fvnc-hermes-agent-1
VELHO=hermes-0231-parado-20261122
IMG=nousresearch/hermes-agent:v0.23.3
IMG_VELHA=nousresearch/hermes-agent:v0.23.1
D=/docker/hermes-agent-fvnc/data
ENSAIO=0; [ "${1:-}" = "--ensaio" ] && ENSAIO=1
log(){ echo "[$(date -u +%FT%TZ)] TROCAR: $*" | tee -a "$B/trocar.log"; }

# 0. pre-condicoes (falha cedo, antes de mexer)
livre=$(df -BM --output=avail / | tail -1 | tr -dc 0-9)
[ "$livre" -ge 3000 ] || { log "RECUSO: so ${livre} MB livres (minimo 3000)"; exit 3; }
mem=$(free -m | awk '/^Mem:/{print $7}')
[ "$mem" -ge 600 ] || { log "RECUSO: so ${mem} MB de memoria disponivel (minimo 600)"; exit 3; }
docker image inspect "$IMG" >/dev/null 2>&1 || { log "RECUSO: imagem $IMG nao esta puxada"; exit 3; }
docker inspect "$VELHO" >/dev/null 2>&1 && { log "RECUSO: $VELHO ja existe (troca anterior?)"; exit 3; }
atual=$(docker inspect -f '{{.Config.Image}}' "$NOME" 2>/dev/null)
[ "$atual" = "$IMG_VELHA" ] || { log "RECUSO: o contentor vivo corre '$atual', esperava $IMG_VELHA"; exit 3; }
[ -x "$B/VOLTAR-0.23.1.sh" ] || { log "RECUSO: falta o VOLTAR-0.23.1.sh"; exit 3; }
log "pre-condicoes OK (livre=${livre}MB mem=${mem}MB atual=$atual ensaio=$ENSAIO)"
if [ "$ENSAIO" = 1 ]; then
  echo "  (ensaio) guardaria as variaveis do painel do contentor vivo num ficheiro temporario 600 (nunca mostradas)"
  echo "  (ensaio) docker stop -t 30 $NOME; docker rename $NOME $VELHO; docker update --restart=no $VELHO"
  echo "  (ensaio) retrato de config e bases em $B/pre-troca-config-<hora>.tar.gz"
  echo "  (ensaio) docker run -d --name $NOME --restart unless-stopped --network hermes-agent-fvnc_default --network-alias hermes-agent -p 127.0.0.1::4860 --env-file <tmp> -v $D:/opt/data $IMG gateway run"
  echo "  (ensaio) esperar gateway; tailscale; /root/bora-bridge-up.sh; whisper + pm repair; reiniciar; /opt/data/voz/voz-up.sh"
  exit 0
fi

ts_up(){  # tailscale com a MESMA identidade (estado no volume)
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
  for i in $(seq 1 36); do
    docker exec "$NOME" sh -lc 'pgrep -f "[h]ermes gateway run|sys[.]exit[(]main[(][)][)] gateway run" >/dev/null' 2>/dev/null && { log "gateway vivo (${i}x5s)"; return 0; }
    sleep 5
  done
  log "gateway NAO subiu em 3 min"; return 1
}

# 1. variaveis do painel: as MESMAS do contentor vivo (nunca passam pelo ecra)
EF=$(mktemp /root/.hermes0233-env.XXXXXX); chmod 600 "$EF"
docker inspect -f '{{range .Config.Env}}{{println .}}{{end}}' "$NOME" | grep -E '^HERMES_DASHBOARD' > "$EF"
[ "$(wc -l < "$EF")" -ge 3 ] || { log "RECUSO: nao encontrei as variaveis do painel no contentor vivo"; rm -f "$EF"; exit 3; }

# 2. parar a 0.23.1 (fica inteira) e tirar o retrato do que a 0.23.3 pode migrar
log "a parar a 0.23.1"
docker stop -t 30 "$NOME" && docker rename "$NOME" "$VELHO" && docker update --restart=no "$VELHO" >/dev/null \
  || { log "ERRO a parar/renomear a 0.23.1"; rm -f "$EF"; exit 4; }
SNAP="$B/pre-troca-config-$(date -u +%Y%m%dT%H%M%SZ).tar.gz"
( cd "$D" && tar -czf "$SNAP" config.yaml .env SOUL.md auth.json cron/jobs.json gateway_state.json \
    state.db* kanban.db* profiles/*/config.yaml profiles/*/.env profiles/*/profile.yaml profiles/*/state.db* 2>/dev/null )
chmod 600 "$SNAP"; log "retrato com a 0.23.1 parada: $SNAP ($(du -h "$SNAP" | cut -f1))"

# 3. arrancar a 0.23.3 com o mesmo nome, rede, volume e porta so local
docker run -d --name "$NOME" --restart unless-stopped \
  --network hermes-agent-fvnc_default --network-alias hermes-agent \
  -p 127.0.0.1::4860 --env-file "$EF" \
  -v "$D:/opt/data" "$IMG" gateway run >> "$B/trocar.log" 2>&1
rc=$?; rm -f "$EF"; log "docker run rc=$rc"
[ "$rc" = 0 ] || { log "falhou o arranque -> VOLTAR"; bash "$B/VOLTAR-0.23.1.sh"; exit 4; }
espera_gateway || { log "gateway nao subiu -> VOLTAR"; bash "$B/VOLTAR-0.23.1.sh"; exit 4; }

# 4. tailscale primeiro, depois o resto da ponte (pc, chromium, cortex, remendo da voz)
ts_up | tee -a "$B/trocar.log"
/root/bora-bridge-up.sh >> "$B/trocar.log" 2>&1
log "bora-bridge-up corrido"

# 5. Whisper local pelo instalador da propria versao e reparar como hermes (licao de 10/11 e 15/11: nunca deixar nada de root)
docker exec -u root -w /opt/hermes "$NOME" /opt/hermes/.venv/bin/python -c 'import pm; pm.ensure_import("stt-whisper")' >> "$B/trocar.log" 2>&1 \
  || log "AVISO: o instalador do whisper deu erro (ver trocar.log); segue"
chown -R 10000:10000 "$D/installs" "$D/cache/uv" "$D/logs/update_receipts" 2>/dev/null
docker exec -u hermes -e HOME=/opt/data "$NOME" sh -lc 'hermes pm repair' >> "$B/trocar.log" 2>&1 || log "AVISO: hermes pm repair deu erro; segue"
docker restart -t 30 "$NOME" >/dev/null; log "reiniciado para carregar o Whisper e o remendo da voz"
espera_gateway || { log "gateway nao voltou depois do reinicio -> VOLTAR"; bash "$B/VOLTAR-0.23.1.sh"; exit 4; }
ts_up | tee -a "$B/trocar.log"

# 6. voz do host (idempotente) e dono certo de tudo o que isto escreveu
bash /opt/data/voz/voz-up.sh >/dev/null 2>&1 || log "AVISO: voz-up deu erro"
chown -R 10000:10000 "$D/tools" "$D/cron" "$D/installs" 2>/dev/null
docker exec "$NOME" sh -c 'hermes --version 2>&1 | head -1'
log "fim da troca — agora as provas"

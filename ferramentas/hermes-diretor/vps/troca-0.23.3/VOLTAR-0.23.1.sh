#!/bin/bash
# VOLTAR-0.23.1.sh — volta o Hermes da 0.23.3 para a 0.23.1 num comando (missao hermes-diretor-2026-11-20, bloco B1).
#   uso:  bash /root/backup-hermes-20261122/VOLTAR-0.23.1.sh          (faz a volta)
#         bash /root/backup-hermes-20261122/VOLTAR-0.23.1.sh --ensaio (so mostra o que faria)
# Nao apaga nada: o contentor 0.23.3 fica parado com outro nome, para se ver depois o que falhou.
# ONDE ESTAO AS COPIAS: nesta pasta (retrato pre-troca-config-*.tar.gz tirado com a 0.23.1 parada,
#   antes-da-missao-config-almas.tar.gz, crontab-root-antes.txt, container-inspect-0.23.1.json).
#   Se o contentor parado e a imagem ja tiverem sido retirados: docker pull nousresearch/hermes-agent:v0.23.1
#   (a etiqueta continua no Docker Hub) e este script recria o contentor a partir dela.
set -u
B=/root/backup-hermes-20261122
NOME=hermes-agent-fvnc-hermes-agent-1
VELHO=hermes-0231-parado-20261122
IMG_VELHA=nousresearch/hermes-agent:v0.23.1
D=/docker/hermes-agent-fvnc/data
ENSAIO=0; [ "${1:-}" = "--ensaio" ] && ENSAIO=1
ts=$(date -u +%Y%m%dT%H%M%SZ)
log(){ echo "[$(date -u +%FT%TZ)] VOLTAR: $*" | tee -a "$B/voltar.log"; }
faz(){ if [ "$ENSAIO" = 1 ]; then echo "  (ensaio) $*"; else eval "$@"; fi; }

# 0. pre-condicoes (falha cedo, antes de mexer)
docker inspect "$VELHO" >/dev/null 2>&1 || docker image inspect "$IMG_VELHA" >/dev/null 2>&1 \
  || { log "ERRO: nem o contentor $VELHO nem a imagem $IMG_VELHA existem (docker pull $IMG_VELHA e repetir)"; exit 2; }
snap=$(ls -t "$B"/pre-troca-config-*.tar.gz 2>/dev/null | head -1)
log "inicio (ensaio=$ENSAIO) retrato=${snap:-nenhum}"

# 1. se o que esta a correr ja e a 0.23.1, nao ha nada a fazer
if docker inspect "$NOME" >/dev/null 2>&1; then
  img=$(docker inspect -f '{{.Config.Image}}' "$NOME")
  if [ "$img" = "$IMG_VELHA" ]; then
    if [ "$ENSAIO" = 1 ]; then log "ensaio: hoje corre a 0.23.1; mostro os passos como se a 0.23.3 estivesse no lugar"
    else log "ja esta na 0.23.1 - nada a fazer"; exit 0; fi
  fi
  log "a afastar o contentor atual ($img) para hermes-0233-afastado-$ts"
  # as variaveis do painel saem do contentor que vai ser afastado (para o caso de ser preciso recriar)
  EF=$(mktemp /root/.hermes-voltar-env.XXXXXX); chmod 600 "$EF"
  docker inspect -f '{{range .Config.Env}}{{println .}}{{end}}' "$NOME" | grep -E '^HERMES_DASHBOARD' > "$EF"
  faz docker stop -t 30 "$NOME"
  faz docker rename "$NOME" "hermes-0233-afastado-$ts"
  faz docker update --restart=no "hermes-0233-afastado-$ts"
fi

# 2. repor a configuracao e as bases de antes da troca (a versao nova pode ter migrado config e bases)
if [ -n "$snap" ]; then
  log "a repor config e bases de antes da troca: $snap"
  q="$B/voltar-wal-afastados-$ts"
  faz mkdir -p "$q"
  for w in "$D"/state.db-wal "$D"/state.db-shm "$D"/kanban.db-wal "$D"/kanban.db-shm "$D"/profiles/*/state.db-wal "$D"/profiles/*/state.db-shm; do
    [ -e "$w" ] || continue
    faz mkdir -p "$q/$(dirname "${w#$D/}")"
    faz mv "$w" "$q/${w#$D/}"
  done
  faz tar -xzf "$snap" -C "$D"
fi
faz chown -R 10000:10000 "$D/config.yaml" "$D/state.db" "$D/profiles" "$D/cron" "$D/installs"

# 3. ligar a 0.23.1: o contentor original parado; se ja nao existir, recria-se da imagem
if docker inspect "$VELHO" >/dev/null 2>&1; then
  log "a religar o contentor original $VELHO"
  faz docker rename "$VELHO" "$NOME"
  faz docker update --restart=unless-stopped "$NOME"
  faz docker start "$NOME"
else
  log "contentor original nao existe - recriar de $IMG_VELHA"
  faz docker run -d --name "$NOME" --restart unless-stopped \
      --network hermes-agent-fvnc_default --network-alias hermes-agent \
      -p 127.0.0.1::4860 --env-file "${EF:-/dev/null}" \
      -v "$D:/opt/data" "$IMG_VELHA" gateway run
fi
[ -n "${EF:-}" ] && rm -f "$EF"

# 4. ponte (tailscale, pc, chromium, cortex, remendo da voz)
faz /root/bora-bridge-up.sh

# 5. prova
if [ "$ENSAIO" = 0 ]; then
  sleep 20
  docker exec "$NOME" sh -c 'hermes --version 2>&1 | head -1; pgrep -fa "sys[.]exit[(]main[(][)][)] gateway run" | cut -c1-70 | head -1'
  docker exec "$NOME" sh -lc 'tailscale status 2>&1 | head -2'
  log "fim - ver acima a versao (tem de dizer v0.23.1) e o gateway a correr"
fi

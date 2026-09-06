#!/bin/sh
# Sincroniza (one-way PC->VPS) as NOTAS do vault Obsidian do Danilo para o Hermes.
# So markdown/texto (exclui media pesada). Idempotente (overwrite/add; nao apaga).
# CORTEX Fase 1A (2026-07-08):
#   (1) fonte = vault CANONICO bora_app/.obsidian-vault (antes puxava Desktop/Bora, o vault velho).
#   (2) transporte EXPLICITO: o alias 'bora-pc' deixou de resolver no contexto do docker exec
#       (o Host block do ~/.ssh/config nao era aplicado -> "could not resolve hostname bora-pc").
#       Usa-se ProxyCommand tailscale nc + key + hermes@<IP tailscale do PC>, provado (150 .md).
#       Se o IP tailscale do PC mudar, atualizar PC_TS abaixo (ou repor o alias bora-pc).
C=hermes-agent-fvnc-hermes-agent-1
LOG=/var/log/obsidian-sync.log
PC_TS=hermes@100.71.105.7
EXC="--exclude=*.exe --exclude=*.js --exclude=*.ajson --exclude=*.css --exclude=.obsidian --exclude=.smart-env --exclude=node_modules --exclude=.git --exclude=*.zip --exclude=*.png --exclude=*.jpg --exclude=*.jpeg --exclude=*.gif --exclude=*.webp --exclude=*.pdf --exclude=*.mp4"
docker exec "$C" sh -lc "mkdir -p /opt/data/obsidian-bora && ssh -o BatchMode=yes -o StrictHostKeyChecking=no -o ConnectTimeout=25 -o \"ProxyCommand=tailscale nc %h %p\" -i /opt/data/.ssh/id_ed25519 $PC_TS \"tar -cf - -C C:/Users/danil/Desktop/projetosflutter/bora_app $EXC .obsidian-vault\" | tar -xf - -C /opt/data/obsidian-bora --strip-components=1" 2>>"$LOG"
N=$(docker exec "$C" sh -lc "find /opt/data/obsidian-bora -name '*.md' | wc -l")
echo "$(date '+%F %T') obsidian-sync: $N notas .md" >> "$LOG"
echo "sync ok: $N notas .md"

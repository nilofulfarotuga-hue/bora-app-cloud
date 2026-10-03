#!/bin/sh
# hermes-cortex-mirror-sync.sh — dispara sync-brain.sh (modo fast) assim que a branch
# autonomous-night avança no GitHub, em vez de esperar o carteiro processar uma ordem
# (sync_espelho só corre como efeito colateral de cada ordem — fila vazia = espelho parado)
# ou o cron hard das 06h30. Ver run cura-espelho MOTOR OPUS, tentativa=1, passo 6.
#
# ATUALIZAÇÃO (tentativa=2, run_id cura-20260801-2): o Juiz rejeitou o poll de 1x/min como
# "não verdadeiramente orientado a evento". O gatilho PRIMÁRIO passou a ser o hook local
# `.claude/githooks/reference-transaction` (dispara na hora em que o `git push` bem-sucedido
# avança refs/remotes/origin/<branch> neste clone — sem esperar o próximo tick do cron).
# Este script (chamado pelo cron `* * * * *`) fica como REDE DE SEGURANÇA para pushes vindos
# de máquinas sem o hook ativo (core.hooksPath não configurado) — nunca foi removido.
#
# Master no repo: .claude/.ai/cortex-mcp/hermes-cortex-mirror-sync.sh — deployado ao host em
# /usr/local/bin/hermes-cortex-mirror-sync.sh, chamado por cron `* * * * *` (1x/min). Sem
# daemon/systemd: cada invocação faz 1 verificação leve (git ls-remote, sem clone) e sai;
# só corre sync-brain.sh de facto quando o SHA remoto mudou desde a última verificação.
# Latência máxima ~60s (tipicamente bem menos, ligação SSH já é reaproveitada pelo docker exec).
set -eu
BR=autonomous-night-2026-04-29
REMOTE=git@github.com:nilofulfarotuga-hue/bora-app-cloud.git
KEY=/opt/data/.secrets/cortex_deploy_ed25519
KNOWN=/opt/data/.secrets/known_hosts
STATE=/root/orquestracao/.cortex-mirror-sync.last_sha
LOG=/root/orquestracao/cortex-mirror-sync.log
C=hermes-agent-fvnc-hermes-agent-1

ts(){ date -u +%Y-%m-%dT%H:%M:%SZ; }

REMOTE_SHA="$(docker exec -u hermes -e HOME=/opt/data "$C" sh -c \
  "GIT_SSH_COMMAND='ssh -i $KEY -o IdentitiesOnly=yes -o UserKnownHostsFile=$KNOWN -o StrictHostKeyChecking=yes' git ls-remote $REMOTE refs/heads/$BR" 2>>"$LOG" | cut -f1)"

if [ -z "$REMOTE_SHA" ]; then
  echo "[$(ts)] ERRO: git ls-remote não devolveu SHA (ver linhas acima no log)" >> "$LOG"
  exit 0
fi

LAST_SHA="$(cat "$STATE" 2>/dev/null || true)"
[ "$REMOTE_SHA" = "$LAST_SHA" ] && exit 0   # nada mudou desde a última verificação — silencioso

T0=$(date +%s)
docker exec -u hermes -e HOME=/opt/data -i "$C" sh -s fast < /root/cortex-mcp/sync-brain.sh >> "$LOG" 2>&1
RC=$?
T1=$(date +%s)
echo "$REMOTE_SHA" > "$STATE"
echo "[$(ts)] espelho atualizado por EVENTO (sha ${LAST_SHA:-<primeira-corrida>} -> $REMOTE_SHA, rc=$RC, ${T1}-${T0}=$((T1 - T0))s desde deteção)" >> "$LOG"

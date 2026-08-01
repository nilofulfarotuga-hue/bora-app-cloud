#!/usr/bin/env bash
# pc-knowledge-sync.sh — 1 CICLO do sync PC->VPS orientado a evento (Bloco A da missão
# sistema-redondo-2026-08-01: "Córtex atualizado em tempo real, não 1x/dia").
#
# PROBLEMA que isto resolve: o único caminho automático PC->VPS hoje é git (commit + push
# origin, via BoraGitPushBridge a cada 15min) + o cron `sync-brain.sh hard` na VPS (06:30 UTC,
# 1x/dia) ou o `sync-brain.sh fast` por-ordem (fetch de origin). Se o ficheiro nunca chegar a
# ser commitado/pusheado — coisa frequente, ver project_headless_push_credential — o Córtex na
# VPS NUNCA vê o conteúdo. Este script bypassa git por completo: espelha o CONTEÚDO local de
# .claude/.ai/knowledge/ diretamente para o clone da VPS via tar-over-ssh, o mesmo padrão do
# workaround manual já usado várias vezes (ver .claude/.ai/knowledge/inbox/espelho-cortex-*).
#
# ADD-ONLY DE PROPÓSITO (--skip-old-files): nunca sobrescreve um ficheiro já existente no
# espelho da VPS. Motivo: cortex_escrever (server.mjs) pode ter editado uma página DIRETAMENTE
# na VPS (zona verde, escrita MCP) antes deste ciclo correr — sobrescrever às cegas a partir do
# PC apagaria essa edição sem ela ter voltado ainda a este repo. Cobre o caso comum (ficheiros
# NOVOS — inbox/*.md datados, lições, relatórios) que é a esmagadora maioria da escrita real.
# LIMITAÇÃO CONHECIDA: uma EDIÇÃO a um ficheiro já existente no espelho não propaga por aqui —
# só passa pelo caminho git (commit+push+sync) ou por reset --hard nocturno. Documentado, não
# é bug.
#
# Idempotente / seguro a repetir. Não faz git add/commit/push. Não toca orquestracao/ (essa
# fila vive só na VPS — nada a sincronizar desse lado a partir do PC).
set -u
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
KDIR="$REPO/.claude/.ai/knowledge"
MARKER="$REPO/.claude/.ai/cortex-mcp/.pc-knowledge-sync.marker"
LOG="$REPO/.claude/.ai/cortex-mcp/pc-knowledge-sync.log"
KEY=/c/Users/danil/.ssh/id_ed25519_vps
HOST=root@srv1786862.hstgr.cloud
DST=/docker/hermes-agent-fvnc/data/cortex-brain

ts(){ date -u +%Y-%m-%dT%H:%M:%SZ; }
log(){ echo "[$(ts)] $*" >> "$LOG"; }

[ -d "$KDIR" ] || { log "ERRO: $KDIR não existe — nada a sincronizar"; exit 1; }

# muda algo desde o último ciclo? (ficheiro novo/tocado depois do marker; 1º run = marker ausente = sincroniza sempre)
if [ -f "$MARKER" ]; then
  CHANGED="$(find "$KDIR" -type f -newer "$MARKER" 2>/dev/null | head -1)"
else
  CHANGED="(1a corrida — marker ausente)"
fi
[ -n "$CHANGED" ] || { exit 0; }  # nada mudou — silencioso, não enche o log a cada ciclo ocioso

T0=$(date +%s%N)
OUT="$(cd "$REPO" && tar czf - .claude/.ai/knowledge 2>/dev/null | \
  ssh -i "$KEY" -o BatchMode=yes -o ConnectTimeout=10 "$HOST" \
    "cd $DST && tar xzf - --skip-old-files && chown -R 10000:10000 .claude/.ai/knowledge" 2>&1)"
RC=$?
T1=$(date +%s%N)
MS=$(( (T1 - T0) / 1000000 ))

if [ $RC -eq 0 ]; then
  touch "$MARKER"
  log "sync OK (${MS}ms) — mudança: ${CHANGED}"
else
  log "sync FALHOU (rc=$RC, ${MS}ms): $OUT"
fi
exit $RC

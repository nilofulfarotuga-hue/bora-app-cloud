#!/usr/bin/env bash
# pc-knowledge-sync-loop.sh — mantém pc-knowledge-sync.sh a correr em polling curto (default
# 8s) para dar latência de SEGUNDOS ao Córtex na VPS, em vez de esperar o cron 1x/dia.
# Ver pc-knowledge-sync.sh para o desenho/porquê. Este ficheiro só é o "motor" do loop.
#
# Lock de instância única (mkdir é atómico) — evita 2 loops concorrentes se a schtask disparar
# 2x (ex.: ONLOGON + ONSTART) ou se alguém correr isto à mão por cima do já ativo.
set -u
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
CYCLE="$REPO/.claude/.ai/cortex-mcp/pc-knowledge-sync.sh"
LOCKDIR="$REPO/.claude/.ai/cortex-mcp/.pc-knowledge-sync-loop.lock"
LOG="$REPO/.claude/.ai/cortex-mcp/pc-knowledge-sync.log"
INTERVAL="${1:-8}"

ts(){ date -u +%Y-%m-%dT%H:%M:%SZ; }
log(){ echo "[$(ts)] $*" >> "$LOG"; }

if ! mkdir "$LOCKDIR" 2>/dev/null; then
  log "loop: já há uma instância a correr (lock $LOCKDIR existe) — a sair."
  exit 0
fi
cleanup(){ rmdir "$LOCKDIR" 2>/dev/null; log "loop: parou (interval=${INTERVAL}s)."; }
trap cleanup EXIT INT TERM

log "loop: arrancou (interval=${INTERVAL}s, pid=$$)."
while :; do
  bash "$CYCLE"
  sleep "$INTERVAL"
done

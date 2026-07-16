#!/usr/bin/env bash
# hermes-evolution-ordens.sh — FECHO DO CIRCUITO da evolution-engine (2026-07-15, missao religar-loop)
#
# PROBLEMA que isto fecha: a evolution-engine DETETAVA padroes e escrevia propostas, mas as
# propostas morriam em relatorios que ninguem executava (prova: 9 disparos para a MESMA nota
# TIMEOUT-900s, zero propostas aplicadas — incluindo a TPROVA-4 que cortava o proprio re-disparo).
#
# DESENHO (respeita a licao-spam-ordens-autoreferencial: NAO e cron-por-sinal):
#   1x/dia (apos o daily-pulse escrever/atualizar o evolution-report), se o report NOVO ou
#   ALTERADO -> injeta UMA ordem zona-verde na fila a mandar APLICAR as propostas verdes
#   (draft -> Juiz novo, como qualquer ordem). Propostas vermelhas seguem o fluxo humano
#   (aprovador-vermelho / Danilo) — a ordem diz explicitamente para NAO as aplicar.
#
# TPROVA-4 (dedupe do re-disparo) esta EMBUTIDO aqui, por construcao:
#   - dedupe por (nome do report + sha256): report igual = silencio absoluto;
#   - guarda extra: no maximo 1 ordem -evol por 20h, mesmo que o report mude 2x no dia.
#
# Canonico no repo: bora_app/.claude/scripts/. Instalado em /usr/local/bin/ no VPS (root).
# Cron: 25 7 * * * (depois do daily-pulse 07h00/07h05 Europe/Lisbon).
# Uso: hermes-evolution-ordens.sh [--dry]

set -u
[ -f /docker/hermes-agent-fvnc/data/cortex-brain/orquestracao/.pausa-total ] && exit 0

FILA=/docker/hermes-agent-fvnc/data/cortex-brain/orquestracao
INBOX=/docker/hermes-agent-fvnc/data/cortex-brain/.claude/.ai/knowledge/inbox
STATE=/root/orquestracao/evolution-ordens.state
LOG=/root/orquestracao/evolution-ordens.log
DRY=0; [ "${1:-}" = "--dry" ] && DRY=1

ts(){ date -u +%FT%TZ; }
log(){ echo "[$(ts)] $*" >> "$LOG"; }

rep=$(ls -t "$INBOX"/evolution-report-*.md 2>/dev/null | head -1)
[ -z "$rep" ] && { log "sem evolution-reports no inbox"; exit 0; }

h=$(sha256sum "$rep" | cut -c1-16)
key="$(basename "$rep"):$h"
touch "$STATE"
if grep -qxF "$key" "$STATE"; then
  log "sem novidade ($key) — silencio"; [ "$DRY" = "1" ] && echo "DRY: sem novidade ($key)"
  exit 0
fi

# guarda anti-spam extra (TPROVA-4): max 1 ordem -evol por 20h
ult=$(ls -t "$FILA"/ordem-*-evol.md 2>/dev/null | head -1)
if [ -n "$ult" ]; then
  age=$(( $(date +%s) - $(stat -c %Y "$ult") ))
  if [ "$age" -lt 72000 ]; then
    log "guarda 20h: ultima ordem -evol tem ${age}s — nao injeto"; [ "$DRY" = "1" ] && echo "DRY: guarda 20h ativa"
    exit 0
  fi
fi

if [ "$DRY" = "1" ]; then echo "DRY: injetaria ordem para $key"; log "DRY: injetaria ordem para $key"; exit 0; fi

TS=$(date -u +%Y%m%d%H%M%S)
ordem="$FILA/ordem-$TS-evol.md"
cat > "$ordem" <<EOF
--- ordem ---
id: ordem-$TS-evol
estado: aberta
autor: hermes-evolution-ordens (circuito fechado 2026-07-15)
criada: $(ts)
zona: verde
tentativa: 0
teto_tentativas: 3
tarefa: EVOLUTION-ENGINE (circuito fechado): le o report $(basename "$rep") em .claude/.ai/knowledge/inbox/ e APLICA as propostas de zona verde que ainda estejam pendentes (draft -> Juiz, como qualquer ordem). Propostas que toquem zona sensivel/protegida ficam SO como proposta (fluxo aprovador-vermelho / Danilo) - NAO as apliques. Prova por git e ficheiro em disco; nunca por e2e_log. Faz commit do que aplicares e atualiza o report a marcar o que ficou aplicado.
--- fim ---
nota:
EOF
echo "$key" >> "$STATE"
log "ordem injetada: $(basename "$ordem") para $key"
echo "ordem injetada: $(basename "$ordem")"

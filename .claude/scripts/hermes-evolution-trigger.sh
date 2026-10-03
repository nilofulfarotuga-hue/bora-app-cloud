#!/usr/bin/env bash
# ⛔ RETIRADO (2026-07-13, religar-evolution-engine): este script NÃO injeta mais ordens
# na fila. Causa: mesmo com a guarda EVOL-1 (10ea1b8, ignora *-evol/*-aprv/*-e2e), o desenho
# de "cron que dispara ordem na fila a cada sinal" continua um vetor de spam/custo por
# construção. Substituído pelo desenho REATIVO (nunca dispara ordem nova):
#   (1) fim de cada missão -> o relatório em inbox/ já fica disponível para o próximo passo;
#   (2) 1x/dia -> hermes-daily-pulse.sh corre evolution_engine.py (passe REAL, não --dry-run)
#       e escreve inbox/evolution-report-<data>.md + grava state (dedup).
# Ver .claude/.ai/knowledge/permanente/semantica/loops.md (linha 'evolution-trigger',
# estado: superado) + lição `licao-spam-ordens-autoreferencial.md`.
# Já NÃO está no crontab da VPS (confirmado 2026-07-13). Este early-exit é só defesa em
# profundidade: se alguém recolocar a linha no crontab por engano, o script não faz nada.
log_retirado(){ echo "[$(date -u +%FT%TZ)] RETIRADO — evolution-trigger não injeta mais ordens (ver loops.md)" >> "${EVOLUTION_TRIGGER_LOG:-/root/orquestracao/evolution-trigger.log}" 2>/dev/null; }
log_retirado
exit 0

# --- código legado abaixo (morto, mantido só para histórico/grep — nunca executa) ---
# --- STOP GLOBAL (reengenharia 2026-07-12): respeita .pausa-total ---
[ -f /docker/hermes-agent-fvnc/data/cortex-brain/orquestracao/.pausa-total ] && exit 0
# hermes-evolution-trigger.sh — Loop 🟡 Learning: acorda o evolution-engine NA HORA
# (em vez de esperar o passo 5 do daily-pulse, 1x/dia).
#
# Corre no HOST do VPS (cron a cada 5 min). Dois gatilhos, ambos baratos (só grep/find
# sobre ficheiros já locais — sem custo de IA a cada tick):
#   (a) ordem NOVA em estado 'travada' (esgotou as 5 tentativas) desde a última passagem;
#   (b) o mesmo texto de erro (campo `nota`, motivo do CORRIGIR) aparece 2+ vezes entre
#       ordens modificadas nas últimas 2h — sinal de erro repetido, não só ordem pesada.
# Se achar qualquer um dos dois, injeta UMA ordem na fila a pedir ao evolution-engine para
# analisar o(s) caso(s) concreto(s). A campainha (inotify) acorda o carteiro na hora.
#
# SILENCIOSO: watermark por ficheiro (STATE) — só dispara para ordens 'travada' que ainda
# não geraram um disparo. Não repete o mesmo motivo em cada tick.
#
# Canónico no repo: bora_app/.claude/scripts/. Instalado em /usr/local/bin/ no VPS.
# Registado em permanente/semantica/loops.md (🟡 Learning). Dono: Hermes(host)/evolution-engine.
#
# Uso: hermes-evolution-trigger.sh [--dry]
set -u

DRY=0; [ "${1:-}" = "--dry" ] && DRY=1

FILA=/docker/hermes-agent-fvnc/data/cortex-brain/orquestracao
STATE=/root/orquestracao/evolution-trigger.watermark   # ids de 'travada' já disparados (1 por linha)
LOG=/root/orquestracao/evolution-trigger.log
C=hermes-agent-fvnc-hermes-agent-1

ts(){ date -u +%FT%TZ; }
log(){ echo "[$(ts)] $*" >> "$LOG"; }

# Primeira execução: semeia o watermark com o backlog atual de 'travada' SEM disparar
# (dívida histórica é tratada à parte, não como evento novo — mesmo padrão do aprovador-vermelho).
if [ ! -f "$STATE" ]; then
  seed=0
  for f in "$FILA"/ordem-*.md; do
    [ -f "$f" ] || continue
    case "$(basename "$f" .md)" in *-evol|*-aprv|*-e2e) continue;; esac  # EVOL-1: ignora as próprias saídas
    e=$(grep -m1 '^estado:' "$f" | sed 's/estado: *//' | tr -d '\r')
    [ "$e" = "travada" ] && { basename "$f" .md >> "$STATE"; seed=$((seed+1)); }
  done
  touch "$STATE"
  [ "$DRY" = 1 ] && echo "DRY: init watermark ($seed travadas existentes semeadas) — sem disparo"
  log "init watermark ($seed travadas existentes semeadas) — sem disparo"
  exit 0
fi

# (a) ordens travadas novas (ainda não disparadas)
travadas_novas=""
for f in "$FILA"/ordem-*.md; do
  [ -f "$f" ] || continue
  e=$(grep -m1 '^estado:' "$f" | sed 's/estado: *//' | tr -d '\r')
  [ "$e" = "travada" ] || continue
  id=$(basename "$f" .md)
  case "$id" in *-evol|*-aprv|*-e2e) continue;; esac  # EVOL-1: não conta as próprias saídas como travadas novas
  grep -qxF "$id" "$STATE" && continue
  travadas_novas="$travadas_novas $id"
done
travadas_novas=$(echo "$travadas_novas" | sed 's/^ *//')

# (b) mesma nota (motivo do CORRIGIR) repetida 2+ vezes em ordens tocadas nas últimas 2h
nota_repetida=""
if command -v find >/dev/null 2>&1; then
  notas=$(find "$FILA" -maxdepth 1 -name 'ordem-*.md' ! -name '*-evol.md' ! -name '*-aprv.md' ! -name '*-e2e.md' -mmin -120 -exec grep -H '^nota:' {} \; \
    | sed 's/^[^:]*:nota: *//' | grep -v '^$' | sort | uniq -c | sort -rn | head -1)
  cnt=$(echo "$notas" | awk '{print $1}')
  if [ -n "${cnt:-}" ] && [ "$cnt" -ge 2 ] 2>/dev/null; then
    nota_repetida=$(echo "$notas" | sed -E 's/^ *[0-9]+ *//')
  fi
fi

if [ -z "$travadas_novas" ] && [ -z "$nota_repetida" ]; then
  [ "$DRY" = 1 ] && echo "DRY: sem gatilho (0 travadas novas, sem nota repetida 2x/2h) — silêncio"
  exit 0
fi

motivo="ordens travadas novas: [${travadas_novas:-nenhuma}]"
[ -n "$nota_repetida" ] && motivo="$motivo · erro repetido 2x+/2h: \"$nota_repetida\""

oid="ordem-$(date -u +%Y%m%d%H%M%S)-evol"
task="Corre o evolution-engine (skill .claude/skills/evolution-engine, ou agente evolution-engine) AGORA, fora do ciclo diário, porque: $motivo. Analisa o(s) caso(s) concreto(s) acima e gera proposta(s) em inbox/evolution-report-<data>.md se aplicável. Zona verde = draft que passa OBRIGATORIAMENTE pelo juiz-revisor antes de aplicar; NUNCA toca dinheiro/auth sozinho — só propõe. Relatório curto do que analisaste."

if [ "$DRY" = 1 ]; then
  echo "DRY: DISPARARIA $oid — motivo: $motivo"
  exit 0
fi

docker exec -i -u hermes "$C" sh -lc "cat > /opt/data/cortex-brain/orquestracao/$oid.md" <<EOF
--- ordem ---
id: $oid
estado: aberta
autor: hermes-evolution-trigger (cron */5)
criada: $(ts)
zona: verde
tentativa: 1
teto_tentativas: 3
tarefa: $task
--- fim ---
EOF

for id in $travadas_novas; do echo "$id" >> "$STATE"; done
log "DISPAROU $oid — $motivo"

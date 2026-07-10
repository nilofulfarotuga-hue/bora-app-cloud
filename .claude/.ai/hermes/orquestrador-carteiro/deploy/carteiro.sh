#!/bin/bash
# carteiro.sh — dispatcher determinístico do loop de orquestração (corre no HOST do VPS).
# Campainha -> este script -> pc-loop (executor) + pc-judge (juiz) -> escreve na fila.
# Tetos: T1(5) T2(budget/turns nos .cmd) T3(zona vermelha) T4(tools nos .cmd) T5(kill switch).
set -u
C=hermes-agent-fvnc-hermes-agent-1
HOSTDATA=/docker/hermes-agent-fvnc/data
FILA="$HOSTDATA/cortex-brain/orquestracao"
CTRL="$FILA/_controlo.md"
LOG=/root/orquestracao/carteiro.log
LOCK=/root/orquestracao/.carteiro.lock
RED='dispatch_engine|pricing_service|finalizePurchase|bora_tokens|stripe|payment|webhook|wallet|ledger|refund|payout|commission|platform_settings|disable row level|force.?push'

ts(){ date -u +%Y-%m-%dT%H:%M:%SZ; }
log(){ echo "[$(ts)] $*" >> "$LOG"; }
get(){ grep -E "^$1:" "$2" 2>/dev/null | head -1 | sed "s/^$1: *//" | tr -d '\r'; }
setf(){ if grep -qE "^$1:" "$3"; then sed -i "s|^$1:.*|$1: $2|" "$3"; else echo "$1: $2" >> "$3"; fi; }
notify(){ docker exec -u hermes "$C" hermes send -t telegram "$1" >/dev/null 2>&1 || log "notify(best-effort) falhou"; }
clean(){ grep -vE '^\[ponte\]|^\[loop\]|^\[juiz\]|Permission deny rule|matches no known tool' ; }
# sync por-tarefa: após o executor fazer push, refresca o espelho para o Claude.ai o ver em segundos
# (modo fast = merge --ff-only, PRESERVA a fila local; a cegueira era esperar o cron das 06h30).
sync_espelho(){ docker exec -u hermes -e HOME=/opt/data -i "$C" sh -s fast < /root/cortex-mcp/sync-brain.sh >> "$LOG" 2>&1 && log "espelho sincronizado (fast)" || log "sync espelho (best-effort) falhou"; }

pc_exec(){ printf '%s' "$1" > "$HOSTDATA/orq_task.txt"
  docker exec -u hermes "$C" sh -lc 'export PATH=/opt/data/.local/bin:$PATH; timeout 900 pc-loop "$(cat /opt/data/orq_task.txt)"' 2>&1 | clean; }
pc_judge(){ printf '%s' "$1" > "$HOSTDATA/orq_judge.txt"
  docker exec -u hermes "$C" sh -lc 'export PATH=/opt/data/.local/bin:$PATH; timeout 200 pc-judge "$(cat /opt/data/orq_judge.txt)"' 2>&1 | clean; }

# concorrência: um carteiro de cada vez
exec 9>"$LOCK"; flock -n 9 || { log "outro carteiro a correr — saio"; exit 0; }
mkdir -p "$FILA"

# T5 — kill switch
enabled=$(get orquestracao_enabled "$CTRL"); enabled=$(echo "${enabled:-false}" | tr 'A-Z' 'a-z')
if [ "$enabled" != "true" ]; then log "T5: kill switch OFF (enabled=$enabled) — nada a fazer"; exit 0; fi

for f in "$FILA"/*.md; do
  [ -f "$f" ] || continue
  case "$f" in */_controlo.md) continue;; esac
  [ "$(get estado "$f")" = "aberta" ] || continue
  id=$(get id "$f"); tarefa=$(get tarefa "$f"); tent=$(get tentativa "$f"); tent=${tent:-0}
  log "ordem $id: aberta (tentativa=$tent)"

  # T3 — zona vermelha NUNCA no loop
  if echo "$tarefa" | grep -iqE "$RED"; then
    setf estado zona_vermelha "$f"; log "ordem $id: 🔴 ZONA VERMELHA -> aprovacao humana"
    notify "🔴 Bora/orquestração: ordem $id toca zona vermelha — precisa de ti."; continue
  fi
  # T1 — teto 5
  if [ "$tent" -ge 5 ]; then setf estado travada "$f"; log "ordem $id: TRAVADA (5 tentativas)"
    notify "⛔ Bora/orquestração: ordem $id travou nas 5 tentativas. Precisa de ti."; continue; fi

  tent=$((tent+1)); setf tentativa "$tent" "$f"; setf estado executando "$f"
  saida=$(pc_exec "$tarefa"); printf '%s\n' "$saida" > "$FILA/$id.saida.txt"
  setf estado respondida "$f"; log "ordem $id: respondida (tentativa $tent)"
  # detecção durável: saída vazia = ponte VIVA mas executor não terminou (timeout 900s / startup),
  # NÃO uma ponte morta. `--output-format text` só emite no fim → kill a meio = 0 bytes.
  if [ -z "$(printf '%s' "$saida" | tr -d '[:space:]')" ]; then
    log "ordem $id: ⚠️ SAIDA VAZIA — executor nao devolveu texto (ponte viva; tarefa nao terminou em 900s ou startup lento)"
  fi

  jinput=$(printf 'TAREFA:\n%s\n\nSAIDA DO EXECUTOR:\n%s\n' "$tarefa" "$(printf '%s' "$saida" | tail -50)")
  veredito=$(pc_judge "$jinput")
  vline=$(printf '%s' "$veredito" | grep -iE 'VEREDITO:' | head -1)
  log "ordem $id: $vline"
  if printf '%s' "$vline" | grep -iq 'APROVADA'; then
    setf estado aprovada "$f"; notify "✅ Bora/orquestração: ordem $id terminada e aprovada."
  else
    setf nota "$(printf '%s' "$vline" | sed 's/.*CORRIGIR: *//')" "$f"
    if [ "$tent" -ge 5 ]; then setf estado travada "$f"; notify "⛔ Bora/orquestração: ordem $id travou (5 tentativas). Precisa de ti."
    else setf estado aberta "$f"; log "ordem $id: CORRIGIR -> reaberta (campainha volta a disparar)"; fi
  fi
  # fim da ordem: o executor já fez push → refresca o espelho para o Claude.ai (não espera o cron)
  sync_espelho
done
log "ciclo terminado"

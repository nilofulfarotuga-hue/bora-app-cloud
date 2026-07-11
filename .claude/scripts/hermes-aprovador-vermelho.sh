#!/usr/bin/env bash
# hermes-aprovador-vermelho.sh — Loop 🟡 Learning: gate barato (cron */10) da fila vermelha.
#
# Corre no HOST do VPS (cron a cada 10 min). Lê o WATERMARK (count + newest) da Central via RPC
# anon `red_queue_watermark` — só agregado, SEM títulos e SEM dinheiro. Se surgiu item NOVO
# (newest > último visto), injeta UMA ordem na fila de orquestração; a campainha (inotify) acorda
# o carteiro -> o PC corre o agente `aprovador-vermelho`, que tria:
#   • Balde A (leitura/falso-positivo, não-dinheiro) -> auto-aprova citando motivo
#   • Balde B (sensível/dinheiro real) -> SEMPRE humano; resumo ao Danilo por Telegram
#
# SILENCIOSO: só age quando há item genuinamente novo (high-water no `newest`). O backlog de
# Balde B já surfaçado (timestamps antigos) NÃO re-dispara — isso seria spam ao Danilo.
# NÃO decide dinheiro: a decisão fica no agente + a Trava. Aqui é só o gatilho.
#
# Canónico no repo: bora_app/.claude/scripts/. Instalado em /usr/local/bin/ no VPS.
# Registado em permanente/semantica/loops.md (🟡 Learning). Dono: Hermes(host)/aprovador-vermelho.
#
# Uso: hermes-aprovador-vermelho.sh [--dry]
#   --dry : só decide+loga (não injeta ordem, não escreve state) — para testar a deteção.
set -u

DRY=0; [ "${1:-}" = "--dry" ] && DRY=1

ENV=/docker/hermes-agent-fvnc/data/.env
FILA=/docker/hermes-agent-fvnc/data/cortex-brain/orquestracao
STATE=/root/orquestracao/aprovador-vermelho.watermark
LOG=/root/orquestracao/aprovador-vermelho.log
C=hermes-agent-fvnc-hermes-agent-1

ts(){ date -u +%FT%TZ; }
log(){ echo "[$(ts)] $*" >> "$LOG"; }

URL=$(grep -E '^SUPABASE_URL=' "$ENV" 2>/dev/null | head -1 | cut -d= -f2- | tr -d '"'\''\r')
KEY=$(grep -E '^SUPABASE_ANON_KEY=' "$ENV" 2>/dev/null | head -1 | cut -d= -f2- | tr -d '"'\''\r')
[ -n "$URL" ] && [ -n "$KEY" ] || { log "sem SUPABASE_URL/ANON_KEY em $ENV — saio"; exit 0; }

resp=$(curl -s --max-time 25 -X POST "$URL/rest/v1/rpc/red_queue_watermark" \
  -H "apikey: $KEY" -H "Authorization: Bearer $KEY" -H "Content-Type: application/json" -d '{}')
newest=$(echo "$resp" | grep -oE '"newest":"[^"]*"' | head -1 | sed 's/.*:"//;s/"$//')
count=$(echo "$resp" | grep -oE '"pending_count":[0-9]+' | head -1 | grep -oE '[0-9]+')
[ -n "$newest" ] || { log "watermark ilegível (resp=$resp) — saio"; exit 0; }

last=$(cat "$STATE" 2>/dev/null || echo "")

# Primeira execução: semeia o high-water sem disparar (o backlog atual é tratado à parte).
if [ -z "$last" ]; then
  [ "$DRY" = 1 ] && { echo "DRY: init watermark=$newest (count=$count) — sem disparo"; exit 0; }
  echo "$newest" > "$STATE"; log "init watermark=$newest (count=$count) — sem disparo"; exit 0
fi

# Nada mais recente que o último visto -> silêncio total.
if [ "$newest" = "$last" ] || [ "$newest" \< "$last" ]; then
  [ "$DRY" = 1 ] && echo "DRY: sem novidade (newest=$newest == last=$last, count=$count) — silêncio"
  exit 0
fi

# Há item mais recente -> dispara triagem.
oid="ordem-$(date -u +%Y%m%d%H%M%S)-aprv"
task="Corre o agente aprovador-vermelho sobre a fila da Central de sugestoes (robot_suggestions status=nova): tria cada item em Balde A (leitura/falso-positivo, nao-dinheiro) ou Balde B (sensivel, SEMPRE humano). Auto-aprova Balde A citando motivo; encaminha Balde B ao Danilo por Telegram. NAO alteres logica sensivel — so roteamento de aprovacao. Item novo detetado: newest=$newest count=$count."

if [ "$DRY" = 1 ]; then
  echo "DRY: DISPARARIA $oid (newest=$newest > last=$last, count=$count)"
  echo "DRY: tarefa = $task"
  exit 0
fi

docker exec -u hermes "$C" sh -lc "cat > /opt/data/cortex-brain/orquestracao/$oid.md" <<EOF
--- ordem ---
id: $oid
estado: aberta
autor: hermes-aprovador-vermelho (cron */10)
criada: $(ts)
zona: verde
tentativa: 1
teto_tentativas: 3
tarefa: $task
--- fim ---
EOF
echo "$newest" > "$STATE"
log "DISPAROU $oid (newest=$newest > last=$last, count=$count)"

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
#
# FALLBACK 30 MIN (2026-07-12 — incidente: ordem de retomar caiu e desapareceu sem rasto porque
# o disparo por watermark ficou mudo — ver causa-raiz abaixo). Além do disparo normal (item
# NOVO), este script agora também dispara — sozinho, sem depender do watermark — sempre que o
# item MAIS ANTIGO ainda `nova` está parado há >=30 min E já não disparámos um forçado nos
# últimos 30 min (dedupe próprio, ficheiro STATE_FORCE). O disparo forçado NÃO aprova nada
# sozinho: só acorda o agente com uma instrução explícita para rever a fila e promover os itens
# que forem CLARAMENTE Balde A (prova positiva de não-dinheiro); Balde B continua sempre humano.
# Isto é rede de segurança — mesmo que o gatilho principal (newest) volte a falhar em silêncio
# como aconteceu esta noite, nada fica preso mais de 30 min sem alguém (o agente) olhar.
set -u

DRY=0; [ "${1:-}" = "--dry" ] && DRY=1

ENV=/docker/hermes-agent-fvnc/data/.env
FILA=/docker/hermes-agent-fvnc/data/cortex-brain/orquestracao
STATE=/root/orquestracao/aprovador-vermelho.watermark
STATE_FORCE=/root/orquestracao/aprovador-vermelho.force_watermark
LOG=/root/orquestracao/aprovador-vermelho.log
C=hermes-agent-fvnc-hermes-agent-1
STALE_MIN=30

ts(){ date -u +%FT%TZ; }
log(){ echo "[$(ts)] $*" >> "$LOG"; }

URL=$(grep -E '^SUPABASE_URL=' "$ENV" 2>/dev/null | head -1 | cut -d= -f2- | tr -d '"'\''\r')
KEY=$(grep -E '^SUPABASE_ANON_KEY=' "$ENV" 2>/dev/null | head -1 | cut -d= -f2- | tr -d '"'\''\r')
[ -n "$URL" ] && [ -n "$KEY" ] || { log "sem SUPABASE_URL/ANON_KEY em $ENV — saio"; exit 0; }

resp=$(curl -s --max-time 25 -X POST "$URL/rest/v1/rpc/red_queue_watermark" \
  -H "apikey: $KEY" -H "Authorization: Bearer $KEY" -H "Content-Type: application/json" -d '{}')
newest=$(echo "$resp" | grep -oE '"newest":"[^"]*"' | head -1 | sed 's/.*:"//;s/"$//')
count=$(echo "$resp" | grep -oE '"pending_count":[0-9]+' | head -1 | grep -oE '[0-9]+')
oldest_age=$(echo "$resp" | grep -oE '"oldest_age_min":[0-9.]+' | head -1 | grep -oE '[0-9.]+' | cut -d. -f1)
[ -n "$newest" ] || { log "watermark ilegível (resp=$resp) — saio"; exit 0; }

last=$(cat "$STATE" 2>/dev/null || echo "")
is_new_item=0

# Primeira execução: semeia o high-water sem disparar (o backlog atual é tratado à parte).
if [ -z "$last" ]; then
  [ "$DRY" = 1 ] && echo "DRY: init watermark=$newest (count=$count) — sem disparo"
  [ "$DRY" = 1 ] || { echo "$newest" > "$STATE"; log "init watermark=$newest (count=$count) — sem disparo"; }
elif [ "$newest" != "$last" ] && [ ! "$newest" \< "$last" ]; then
  is_new_item=1
fi

# Disparo forçado por staleness: independente do watermark ter avançado. Só entra se houver
# item(ns) pendentes há >=STALE_MIN e ainda não disparámos um forçado nos últimos STALE_MIN.
force_fire=0
if [ -n "${oldest_age:-}" ] && [ "$count" != "0" ] && [ "$oldest_age" -ge "$STALE_MIN" ] 2>/dev/null; then
  now_epoch=$(date -u +%s)
  prev_force=$(cat "$STATE_FORCE" 2>/dev/null || echo 0)
  elapsed=$(( now_epoch - prev_force ))
  if [ "$elapsed" -ge $((STALE_MIN * 60)) ]; then
    force_fire=1
  fi
fi

if [ "$is_new_item" = 0 ] && [ "$force_fire" = 0 ]; then
  [ "$DRY" = 1 ] && echo "DRY: sem novidade e sem staleness (newest=$newest==last=$last, count=$count, oldest_age=${oldest_age:-?}min) — silêncio"
  exit 0
fi

oid="ordem-$(date -u +%Y%m%d%H%M%S)-aprv"
if [ "$force_fire" = 1 ]; then
  task="FALLBACK 30MIN: a fila da Central (robot_suggestions status=nova) tem item(ns) parado(s) ha ${oldest_age}+ minutos sem triagem (count=$count) — o gatilho normal por item-novo pode ter falhado. Corre o agente aprovador-vermelho AGORA sobre TODA a fila nova: tria cada item em Balde A (leitura/falso-positivo, nao-dinheiro, com prova positiva) ou Balde B (sensivel/dinheiro, SEMPRE humano). Promove/auto-aprova AGORA os que forem claramente Balde A citando motivo, mesmo que ja tenham sido vistos antes — nao deixes nada preso so por staleness. Balde B nunca e promovido automaticamente, fica para o Danilo via Telegram. NAO alteres logica sensivel — so roteamento de aprovacao."
else
  task="Corre o agente aprovador-vermelho sobre a fila da Central de sugestoes (robot_suggestions status=nova): tria cada item em Balde A (leitura/falso-positivo, nao-dinheiro) ou Balde B (sensivel, SEMPRE humano). Auto-aprova Balde A citando motivo; encaminha Balde B ao Danilo por Telegram. NAO alteres logica sensivel — so roteamento de aprovacao. Item novo detetado: newest=$newest count=$count."
fi

if [ "$DRY" = 1 ]; then
  echo "DRY: DISPARARIA $oid (is_new_item=$is_new_item force_fire=$force_fire newest=$newest last=$last count=$count oldest_age=${oldest_age:-?}min)"
  echo "DRY: tarefa = $task"
  exit 0
fi

docker exec -i -u hermes "$C" sh -lc "cat > /opt/data/cortex-brain/orquestracao/$oid.md" <<EOF
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
[ "$is_new_item" = 1 ] && echo "$newest" > "$STATE"
[ "$force_fire" = 1 ] && date -u +%s > "$STATE_FORCE"
log "DISPAROU $oid (is_new_item=$is_new_item force_fire=$force_fire newest=$newest count=$count oldest_age=${oldest_age:-?}min)"

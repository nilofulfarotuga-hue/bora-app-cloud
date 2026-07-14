#!/usr/bin/env bash
# --- STOP GLOBAL (reengenharia 2026-07-12): respeita .pausa-total ---
[ -f /docker/hermes-agent-fvnc/data/cortex-brain/orquestracao/.pausa-total ] && exit 0
# hermes-suporte-escalacao.sh — Chat guiado (2026-07-14), passo 3: ESCALAÇÃO AO DANILO.
#
# Corre no HOST do VPS (cron a cada 10 min, mesmo padrão de hermes-aprovador-vermelho.sh).
# Lê o WATERMARK (count + newest) da fila `support_escalations` via RPC anon
# `support_escalation_watermark` — só agregado, SEM a pergunta do cliente. Se surgiu item
# NOVO, injeta UMA ordem na fila de orquestração; a campainha (inotify) acorda o carteiro
# -> o PC corre o agente `chat-suporte`, que:
#   1. Lê `support_escalations` (status='pending') via MCP/service role (RLS não deixa anon ler).
#   2. Manda a pergunta a Danilo por Telegram, citando o ID da escalação.
#   3. Quando o Danilo responde no Telegram citando o ID, chama a RPC
#      `admin_reply_escalation(p_escalation_id, p_reply)` — a resposta cai no chat do
#      cliente (mesma sessão) via realtime, com o nome da persona (Thayline/Thabyta).
#
# SILENCIOSO: só age quando há item genuinamente novo. Toda escalação é SEMPRE humano
# (não há Balde A aqui — o Hermes/persona já tentou resolver antes de escalar).
#
# Canónico no repo: bora_app/.claude/scripts/. Instalado em /usr/local/bin/ no VPS.
# Dono: Hermes(host)/chat-suporte.
#
# Uso: hermes-suporte-escalacao.sh [--dry]
set -u

DRY=0; [ "${1:-}" = "--dry" ] && DRY=1

ENV=/docker/hermes-agent-fvnc/data/.env
STATE=/root/orquestracao/suporte-escalacao.watermark
STATE_FORCE=/root/orquestracao/suporte-escalacao.force_watermark
LOG=/root/orquestracao/suporte-escalacao.log
C=hermes-agent-fvnc-hermes-agent-1
STALE_MIN=15

ts(){ date -u +%FT%TZ; }
log(){ echo "[$(ts)] $*" >> "$LOG"; }

URL=$(grep -E '^SUPABASE_URL=' "$ENV" 2>/dev/null | head -1 | cut -d= -f2- | tr -d '"'\''\r')
KEY=$(grep -E '^SUPABASE_ANON_KEY=' "$ENV" 2>/dev/null | head -1 | cut -d= -f2- | tr -d '"'\''\r')
[ -n "$URL" ] && [ -n "$KEY" ] || { log "sem SUPABASE_URL/ANON_KEY em $ENV — saio"; exit 0; }

resp=$(curl -s --max-time 25 -X POST "$URL/rest/v1/rpc/support_escalation_watermark" \
  -H "apikey: $KEY" -H "Authorization: Bearer $KEY" -H "Content-Type: application/json" -d '{}')
newest=$(echo "$resp" | grep -oE '"newest":"[^"]*"' | head -1 | sed 's/.*:"//;s/"$//')
count=$(echo "$resp" | grep -oE '"pending_count":[0-9]+' | head -1 | grep -oE '[0-9]+')
oldest_age=$(echo "$resp" | grep -oE '"oldest_age_min":[0-9.]+' | head -1 | grep -oE '[0-9.]+' | cut -d. -f1)
[ -n "$count" ] || { log "watermark ilegível (resp=$resp) — saio"; exit 0; }

# count=0 -> sem pendentes: reseta o "last" para não disparar num falso "voltou a zero e subiu".
if [ "$count" = "0" ] || [ -z "$newest" ]; then
  [ "$DRY" = 1 ] || echo "" > "$STATE"
  [ "$DRY" = 1 ] && echo "DRY: sem pendentes (count=0) — silêncio"
  exit 0
fi

last=$(cat "$STATE" 2>/dev/null || echo "")
is_new_item=0
if [ -z "$last" ] || { [ "$newest" != "$last" ] && [ ! "$newest" \< "$last" ]; }; then
  is_new_item=1
fi

# Fallback de staleness: item mais antigo pendente há >=15min sem re-disparo forçado na última hora.
force_fire=0
if [ "$is_new_item" = 0 ] && [ -n "${oldest_age:-}" ] && [ "$oldest_age" -ge "$STALE_MIN" ] 2>/dev/null; then
  now_epoch=$(date -u +%s)
  prev_force=$(cat "$STATE_FORCE" 2>/dev/null || echo 0)
  elapsed=$(( now_epoch - prev_force ))
  [ "$elapsed" -ge 3600 ] && force_fire=1
fi

if [ "$is_new_item" = 0 ] && [ "$force_fire" = 0 ]; then
  [ "$DRY" = 1 ] && echo "DRY: sem novidade e sem staleness (newest=$newest==last=$last, count=$count, oldest_age=${oldest_age:-?}min) — silêncio"
  exit 0
fi

oid="ordem-$(date -u +%Y%m%d%H%M%S)-supesc"
if [ "$force_fire" = 1 ]; then
  task="FALLBACK 15MIN: ha escalacao(oes) de suporte (support_escalations status=pending) parada(s) ha ${oldest_age}+ minutos sem resposta ao cliente (count=$count). Corre o agente chat-suporte AGORA: le as escalacoes pendentes, manda a Danilo por Telegram (citando o ID de cada uma) e, quando ele responder, chama a RPC admin_reply_escalation(p_escalation_id, p_reply). NAO respondas tu mesmo ao cliente — a resposta tem de vir do Danilo (e' Balde B, sempre humano)."
else
  task="Chegou pergunta nova ao suporte que a Thayline/Thabyta (Hermes) nao soube resolver (support_escalations, count=$count). Corre o agente chat-suporte: le a(s) escalacao(oes) pendente(s), manda a Danilo por Telegram citando o ID, e quando ele responder chama admin_reply_escalation(p_escalation_id, p_reply) para a resposta cair no chat do cliente. NAO respondas tu mesmo — so o Danilo decide o conteudo."
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
autor: hermes-suporte-escalacao (cron */10)
criada: $(ts)
zona: verde
tentativa: 1
teto_tentativas: 3
tarefa: $task
--- fim ---
EOF
echo "$newest" > "$STATE"
[ "$force_fire" = 1 ] && date -u +%s > "$STATE_FORCE"
log "DISPAROU $oid (is_new_item=$is_new_item force_fire=$force_fire newest=$newest count=$count oldest_age=${oldest_age:-?}min)"

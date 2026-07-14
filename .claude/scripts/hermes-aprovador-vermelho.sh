#!/usr/bin/env bash
# --- STOP GLOBAL (reengenharia 2026-07-12): respeita .pausa-total ---
[ -f /docker/hermes-agent-fvnc/data/cortex-brain/orquestracao/.pausa-total ] && exit 0
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
# item MAIS ANTIGO ainda `nova` está parado há >=30 min E já não disparámos um forçado no
# intervalo de backoff atual (dedupe próprio, ficheiro STATE_FORCE). O disparo forçado NÃO
# aprova nada sozinho: só acorda o agente com uma instrução explícita para rever a fila e
# promover os itens que forem CLARAMENTE Balde A (prova positiva de não-dinheiro); Balde B
# continua sempre humano. Isto é rede de segurança — mesmo que o gatilho principal (newest)
# volte a falhar em silêncio como aconteceu esta noite, nada fica preso mais de 30 min sem
# alguém (o agente) olhar.
#
# BACKOFF (2026-07-13 — pendência das corridas 1-15: o mesmo lote Balde B, sem o Danilo decidir,
# refazia disparos ~a cada 30 min indefinidamente, sem novidade nenhuma). Cada force_fire
# consecutivo SEM o backlog encolher (mesmo `count` ou maior) dobra o intervalo até
# MAX_BACKOFF_MIN; assim que `count` desce (Danilo decidiu algo na fila) o backoff reinicia em
# STALE_MIN. Não muda o que o disparo faz — só espaça repetições do MESMO lote não resolvido.
set -u

DRY=0; [ "${1:-}" = "--dry" ] && DRY=1

ENV=/docker/hermes-agent-fvnc/data/.env
FILA=/docker/hermes-agent-fvnc/data/cortex-brain/orquestracao
STATE=/root/orquestracao/aprovador-vermelho.watermark
STATE_FORCE=/root/orquestracao/aprovador-vermelho.force_watermark
STATE_FORCE_N=/root/orquestracao/aprovador-vermelho.force_backoff_n
STATE_FORCE_COUNT=/root/orquestracao/aprovador-vermelho.force_last_count
LOG=/root/orquestracao/aprovador-vermelho.log
C=hermes-agent-fvnc-hermes-agent-1
STALE_MIN=30
MAX_BACKOFF_MIN=360

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
# item(ns) pendentes há >=STALE_MIN e já passou o intervalo de backoff desde o último forçado.
force_fire=0
fire_n=$(cat "$STATE_FORCE_N" 2>/dev/null || echo 0)
case "$fire_n" in ''|*[!0-9]*) fire_n=0 ;; esac
if [ -n "${oldest_age:-}" ] && [ "$count" != "0" ] && [ "$oldest_age" -ge "$STALE_MIN" ] 2>/dev/null; then
  now_epoch=$(date -u +%s)
  prev_force=$(cat "$STATE_FORCE" 2>/dev/null || echo 0)
  prev_count=$(cat "$STATE_FORCE_COUNT" 2>/dev/null || echo "")
  # backlog encolheu desde o último forçado (Danilo decidiu algo) -> reinicia o backoff
  if [ -n "$prev_count" ] && [ "$count" -lt "$prev_count" ] 2>/dev/null; then
    fire_n=0
  fi
  backoff_min=$(( STALE_MIN * (1 << fire_n) ))
  [ "$backoff_min" -gt "$MAX_BACKOFF_MIN" ] && backoff_min=$MAX_BACKOFF_MIN
  elapsed=$(( now_epoch - prev_force ))
  if [ "$elapsed" -ge $((backoff_min * 60)) ]; then
    force_fire=1
  fi
fi

if [ "$is_new_item" = 0 ] && [ "$force_fire" = 0 ]; then
  [ "$DRY" = 1 ] && echo "DRY: sem novidade e sem staleness (newest=$newest==last=$last, count=$count, oldest_age=${oldest_age:-?}min) — silêncio"
  exit 0
fi

# 2026-07-14 (Emerson decide sozinho — pedido do Danilo): Balde A deixou de ser so recomendacao
# no relatorio — o Hermes/Emerson agora PERSISTE a decisao via RPC robot_emerson_decide
# (service_role, sem sessao admin humana; a propria RPC bloqueia no servidor qualquer aprovacao
# que toque zona protegida). Aprovada -> status 'aprovada-emerson' + cortex_nova_ordem cria UMA
# ordem no loop para executar (fecha com robot_emerson_close). Rejeitada -> status 'rejeitada'
# com motivo curto. Balde B continua a NUNCA ser decidido por agente — so surfaça ao Danilo.
oid="ordem-$(date -u +%Y%m%d%H%M%S)-aprv"
if [ "$force_fire" = 1 ]; then
  task="FALLBACK 30MIN: a fila da Central (robot_suggestions status=nova) tem item(ns) parado(s) ha ${oldest_age}+ minutos sem triagem (count=$count) — o gatilho normal por item-novo pode ter falhado. Corre o agente aprovador-vermelho (Emerson) AGORA sobre TODA a fila nova: para cada item, decide sozinho via RPC robot_emerson_decide (service_role) — 'aprovada-emerson' + UMA ordem cortex_nova_ordem por sugestao (nunca mais que 1) se for seguro/reversivel/melhora o sistema/nao toca zona protegida; senao 'rejeitada' com motivo curto (duplicado ou zona protegida). Sugestoes claramente identicas (mesmo alvo) so uma aprovada, as outras rejeitadas citando a aprovada. Zona protegida (dispatch/pagamentos/pricing/tokens/refund/comissao) NUNCA e decidida por agente — fica 'nova' e vai para o Danilo via Telegram. Envia 1 linha ao Telegram do Danilo por decisao tomada. NAO alteres logica sensivel — so triagem+decisao administrativa."
else
  task="Corre o agente aprovador-vermelho (Emerson) sobre a fila da Central de sugestoes (robot_suggestions status=nova): para cada item, decide sozinho via RPC robot_emerson_decide — 'aprovada-emerson' + UMA ordem cortex_nova_ordem por sugestao se for seguro/reversivel/melhora o sistema/nao toca zona protegida; senao 'rejeitada' com motivo curto. Duplicados (mesmo alvo): aprova so um, rejeita os outros citando o aprovado. Zona protegida (dispatch/pagamentos/pricing/tokens/refund/comissao) fica sempre 'nova' para o Danilo decidir via Telegram — NUNCA decidida por agente. Envia 1 linha ao Telegram do Danilo por decisao. NAO alteres logica sensivel — so triagem+decisao administrativa. Item novo detetado: newest=$newest count=$count."
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
if [ "$force_fire" = 1 ]; then
  date -u +%s > "$STATE_FORCE"
  echo "$((fire_n + 1))" > "$STATE_FORCE_N"
  echo "$count" > "$STATE_FORCE_COUNT"
fi
log "DISPAROU $oid (is_new_item=$is_new_item force_fire=$force_fire fire_n=$fire_n newest=$newest count=$count oldest_age=${oldest_age:-?}min)"

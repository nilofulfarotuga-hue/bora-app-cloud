#!/usr/bin/env bash
# --- STOP GLOBAL (reengenharia 2026-07-12): respeita .pausa-total ---
[ -f /docker/hermes-agent-fvnc/data/cortex-brain/orquestracao/.pausa-total ] && exit 0
# hermes-consumidor-aprovadas.sh — P3 da missão nunca-mais-travar-2026-07-31.
#
# FECHA I5: o Danilo aprova na Central (nova -> aprovada) e a coisa CORRE SOZINHA, a qualquer
# hora, sem ele mandar prompt no Claude Code.
#
# PORQUÊ ISTO EXISTE: o troço `aprovada` -> execução NUNCA foi construído. Todos os leitores de
# status='aprovada' eram escrita (robot_approve_plan), dedup ou métrica (taxa_aprovacao_pct) —
# ZERO consumidores. Aprovar escrevia num estado que ninguém lia: 46 linhas paradas desde
# 2026-06-19 e o último `aplicada` de 2026-07-14. As 5 aprovações do Danilo em 31/07 caíram na
# mesma pilha morta.
#
# Mesmo padrão barato do hermes-aprovador-vermelho.sh: lê só o WATERMARK (agregado, sem títulos
# e sem dinheiro) via RPC anon `approved_queue_watermark`; se houver aprovado por correr, injeta
# UMA ordem na fila; a campainha (inotify) acorda o carteiro -> o PC corre o `maestro-autonomia`.
#
# AS 4 TRAVAS (decisão do Danilo, 2026-07-31 — não relaxar sem ordem dele):
#  1. CUTOFF — só o que for aprovado DEPOIS do consumidor nascer
#     (platform_settings.robot_consumer_cutoff_at). As 49 antigas ficam em QUARENTENA, visíveis,
#     para re-triagem humana. Drenar o backlog seria trocar "nada executa" por "executa 49 coisas
#     velhas de uma vez" — incl. 4x "reatribuir pedidos presos" (os pedidos de hoje são outros),
#     8x paridade-admin de 01-02/07 (provavelmente já feitos à mão) e 1x teste-circuito.
#     O cutoff é aplicado no SERVIDOR (na RPC), não aqui — este script não o pode contornar.
#  2. IDEMPOTÊNCIA — quem pega uma linha é a RPC `robot_claim_approved` (FOR UPDATE SKIP LOCKED
#     + aprovada->em_execucao na mesma transação). Dois ciclos nunca correm a mesma linha.
#     Este cron NÃO reclama nada: só acorda o maestro, que reclama lá dentro.
#  3. TRAVA — a execução passa pelo executor do PC, logo pela Trava protege-dinheiro, como
#     qualquer outra ordem. Balde A auto-aprovado pelo agente NUNCA passou pelo Danilo, por isso
#     escrita em dinheiro continua bloqueada a jusante. A ordem diz isso explicitamente.
#  4. aprovada-emerson EXCLUÍDO — tem ciclo próprio (robot_emerson_decide / robot_emerson_close).
#     Não se assume equivalência a `aprovada`. A RPC filtra; aqui só se documenta.
#
# LOTE: no máximo 8 por corrida (I2), mais antigos primeiro. Sobra fica para o ciclo seguinte.
#
# Canónico no repo: bora_app/.claude/scripts/. Instalado em /usr/local/bin/ no VPS (cron */10).
# Uso: hermes-consumidor-aprovadas.sh [--dry]
set -u

DRY=0; [ "${1:-}" = "--dry" ] && DRY=1

ENV=/docker/hermes-agent-fvnc/data/.env
STATE=/root/orquestracao/consumidor-aprovadas.watermark
LOG=/root/orquestracao/consumidor-aprovadas.log
C=hermes-agent-fvnc-hermes-agent-1
LOTE_MAX=8

ts(){ date -u +%FT%TZ; }
log(){ echo "[$(ts)] $*" >> "$LOG"; }

URL=$(grep -E '^SUPABASE_URL=' "$ENV" 2>/dev/null | head -1 | cut -d= -f2- | tr -d '"'\''\r')
KEY=$(grep -E '^SUPABASE_ANON_KEY=' "$ENV" 2>/dev/null | head -1 | cut -d= -f2- | tr -d '"'\''\r')
[ -n "$URL" ] && [ -n "$KEY" ] || { log "sem SUPABASE_URL/ANON_KEY em $ENV — saio"; exit 0; }

resp=$(curl -s --max-time 25 -X POST "$URL/rest/v1/rpc/approved_queue_watermark" \
  -H "apikey: $KEY" -H "Authorization: Bearer $KEY" -H "Content-Type: application/json" -d '{}')
count=$(echo "$resp" | grep -oE '"pending_count":[0-9]+' | head -1 | grep -oE '[0-9]+')
newest=$(echo "$resp" | grep -oE '"newest":"[^"]*"' | head -1 | sed 's/.*:"//;s/"$//')
[ -n "${count:-}" ] || { log "watermark ilegível (resp=$resp) — saio"; exit 0; }

if [ "$count" = "0" ]; then
  [ "$DRY" = 1 ] && echo "DRY: nada aprovado por correr (count=0) — silêncio"
  exit 0
fi

# Dedupe: não injetar ordem nova enquanto o conjunto não mudar (evita empilhar ordens enquanto
# o maestro ainda está a executar o lote anterior — o carteiro é single-flight).
last=$(cat "$STATE" 2>/dev/null || echo "")
sig="${count}@${newest}"
if [ "$sig" = "$last" ]; then
  [ "$DRY" = 1 ] && echo "DRY: mesmo conjunto de ${count} aprovado(s) ja sinalizado (sig=$sig) — silêncio"
  exit 0
fi

lote=$count
[ "$lote" -gt "$LOTE_MAX" ] 2>/dev/null && lote=$LOTE_MAX
sobra=0
[ "$count" -gt "$lote" ] 2>/dev/null && sobra=$((count - lote))

oid="ordem-$(date -u +%Y%m%d%H%M%S)-aplic"
task="EXECUTAR APROVADAS (I5): ha $count sugestao(oes) com status='aprovada' ja autorizadas pelo Danilo e por executar. Corre o agente maestro-autonomia. PASSO 1: chama a RPC robot_claim_approved($lote) — ela reclama ATOMICAMENTE ate $lote itens (aprovada->em_execucao, mais antigos primeiro) e ja aplica o CUTOFF no servidor; NAO faças SELECT manual a robot_suggestions para escolher trabalho, e NAO toques em nada com status 'aprovada-emerson' (tem ciclo proprio: robot_emerson_decide/robot_emerson_close). PASSO 2: executa cada item reclamado seguindo a sua 'proposta'/'payload_execucao', passando pelo Juiz como qualquer trabalho. Zona vermelha/dinheiro: NAO aplicas — a Trava bloqueia e o item espera o 'vai' do Danilo. PASSO 3: fecha cada item com robot_finish_approved(id, true) se correu, ou robot_finish_approved(id, false, 'motivo') para o devolver a fila e retentar no ciclo seguinte. Item deixado em 'em_execucao' e reclamado outra vez ao fim de 60 min — nao o deixes pendurado de proposito. Sobra desta corrida: $sobra (fica para o ciclo seguinte, NAO encadeies)."

if [ "$DRY" = 1 ]; then
  echo "DRY: DISPARARIA $oid (count=$count lote=$lote sobra=$sobra sig=$sig)"
  echo "DRY: tarefa = $task"
  exit 0
fi

docker exec -i -u hermes "$C" sh -lc "cat > /opt/data/cortex-brain/orquestracao/$oid.md" <<EOF
--- ordem ---
id: $oid
estado: aberta
autor: hermes-consumidor-aprovadas (cron */10)
criada: $(ts)
zona: verde
tentativa: 1
teto_tentativas: 3
tarefa: $task
--- fim ---
EOF
echo "$sig" > "$STATE"
log "DISPAROU $oid (count=$count lote=$lote sobra=$sobra sig=$sig)"

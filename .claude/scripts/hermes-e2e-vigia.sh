#!/usr/bin/env bash
# --- STOP GLOBAL (reengenharia 2026-07-12): respeita .pausa-total ---
[ -f /docker/hermes-agent-fvnc/data/cortex-brain/orquestracao/.pausa-total ] && exit 0
# hermes-e2e-vigia.sh — vigia BARATO do loop E2E. Deteta que o teste parou a meio e TOCA A
# CAMPAINHA (injeta 1 ordem na fila) para o Claude Code retomar. SÓ 1 curl SQL + bash — nunca
# chama Opus, nunca gasta o limite do Claude.ai. Custo por tick ≈ 1 GET minúsculo ao PostgREST.
#
# Diferença para hermes-watchdog.sh (que SÓ AVISA por Telegram): este AGE — injeta 1 ordem
# 'aberta' zona verde na fila da orquestração. A campainha (inotify) acorda o PC na hora →
# o Claude Code retoma o loop. Segue o mesmo padrão watermark+dedupe do evolution-trigger e
# do aprovador-vermelho: dispara no MÁXIMO 1x por episódio de silêncio.
#
# Regra de deteção (barata, read-only sobre e2e_log — tabela anon-legível via PostgREST):
#   fire  ⇔  STALE_MIN ≤ mins_desde_última_escrita ≤ CEILING_MIN  E  last_write ≠ watermark
#   - mins < STALE_MIN (20)      → loop a escrever, está vivo            → NÃO toca
#   - STALE_MIN ≤ mins ≤ CEILING → loop ESTAVA ativo e ficou em silêncio → TOCA (1x)
#   - mins > CEILING_MIN (90)    → loop parado há muito (terminou / nem  → NÃO toca
#                                   arrancou); não há teste "a meio" p/ retomar
# O tecto de 90 min substitui um "esteve ativo há pouco?" — se a última escrita é recente o
# suficiente para caber na janela, o loop esteve mesmo a correr. O dedupe pelo próprio
# last_write garante 1 disparo por episódio: enquanto o teste não voltar a escrever, o
# last_write não muda → não re-dispara (anti-spam). Se retomar e cair outra vez, o novo
# last_write é diferente → novo episódio → novo disparo.
#
# Corre no HOST do VPS (cron */10). Canónico: bora_app/.claude/scripts/. Instalado /usr/local/bin/.
# Registado em permanente/semantica/loops.md (🟣 Quality — vigia do E2E). Dono: Hermes(host).
# Uso: hermes-e2e-vigia.sh [--dry]
set -u

DRY=0; [ "${1:-}" = "--dry" ] && DRY=1

H=/docker/hermes-agent-fvnc/data
ENV=$H/.env
LOG=/root/orquestracao/e2e-vigia.log
STAMP=/root/orquestracao/.e2e-vigia.last_write   # dedupe: último last_write p/ o qual tocámos
C=hermes-agent-fvnc-hermes-agent-1
STALE_MIN=20
CEILING_MIN=90

mkdir -p /root/orquestracao 2>/dev/null || true
ts(){ date -u +%FT%TZ; }
log(){ echo "[$(ts)] $*" >> "$LOG"; }

URL=$(grep -E '^SUPABASE_URL=' "$ENV" 2>/dev/null | head -1 | cut -d= -f2- | tr -d '"'\''\r')
KEY=$(grep -E '^SUPABASE_ANON_KEY=' "$ENV" 2>/dev/null | head -1 | cut -d= -f2- | tr -d '"'\''\r')
if [ -z "$URL" ] || [ -z "$KEY" ]; then
  log "sem SUPABASE_URL/ANON_KEY no .env — aborto (nada a fazer)"; exit 0
fi

# 1 GET minúsculo: a última escrita do e2e_log
resp=$(curl -s --max-time 15 \
  "$URL/rest/v1/e2e_log?select=created_at&order=created_at.desc&limit=1" \
  -H "apikey: $KEY" -H "Authorization: Bearer $KEY")
lw=$(echo "$resp" | grep -oE '"created_at":"[^"]+"' | head -1 | sed 's/.*:"//;s/"$//')
if [ -z "$lw" ]; then
  log "e2e_log vazio ou resposta inesperada — aborto (nada a retomar). resp=$(echo "$resp" | head -c120)"
  exit 0
fi

now=$(date +%s)
lw_epoch=$(date -d "$lw" +%s 2>/dev/null || echo 0)
[ "$lw_epoch" = 0 ] && { log "não consegui converter last_write '$lw' — aborto"; exit 0; }
mins=$(( (now - lw_epoch) / 60 ))

# fora da janela → silêncio
if [ "$mins" -lt "$STALE_MIN" ] || [ "$mins" -gt "$CEILING_MIN" ]; then
  [ "$DRY" = 1 ] && echo "DRY: mins=$mins fora da janela [$STALE_MIN..$CEILING_MIN] — NÃO toca (last_write=$lw)"
  exit 0
fi

# dedupe: já tocámos para este mesmo episódio de silêncio?
prev=$(cat "$STAMP" 2>/dev/null | tr -d '\r\n')
if [ "$prev" = "$lw" ]; then
  [ "$DRY" = 1 ] && echo "DRY: mins=$mins na janela MAS já toquei para last_write=$lw — silêncio (anti-spam)"
  exit 0
fi

oid="ordem-$(date -u +%Y%m%d%H%M%S)-e2e"
task="VIGIA E2E: o loop de testes E2E parou a meio — a última escrita em e2e_log foi há ${mins}min (>${STALE_MIN}min e dentro da janela ativa <${CEILING_MIN}min). Verifica se o loop noturno (.claude/testes-e2e/run-tudo.cmd / loop-noturno.py) ainda corre no PC; se caiu a meio, retoma-o. Se já tinha terminado de propósito, ignora e regista. NÃO abras nada de pagamentos/Stripe. Relatório curto do que encontraste."

if [ "$DRY" = 1 ]; then
  echo "DRY: DISPARARIA $oid — e2e_log silencioso há ${mins}min (last_write=$lw, prev=${prev:-vazio})"
  exit 0
fi

# injeta a ordem DENTRO do container (mesmo dono/hermes que a campainha inotify vê)
docker exec -i -u hermes "$C" sh -lc "cat > /opt/data/cortex-brain/orquestracao/$oid.md" <<EOF
--- ordem ---
id: $oid
estado: aberta
autor: hermes-e2e-vigia (cron */10)
criada: $(ts)
zona: verde
tentativa: 1
teto_tentativas: 3
tarefa: $task
--- fim ---
EOF

printf '%s' "$lw" > "$STAMP"
log "CAMPAINHA: $oid injetada — e2e_log silencioso há ${mins}min (last_write=$lw)"

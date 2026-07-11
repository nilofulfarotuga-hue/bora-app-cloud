#!/usr/bin/env bash
# hermes-watchdog.sh — vigia loops/ordens/recursos da VPS. SÓ AVISA (nunca age sozinho).
# Fase 2 da missão "Do Prompt ao Loop" (2026-07-10). Prioridade do alerta = COR do loop
# no registry (loops.md): 🟢 Core parado = VERMELHO imediato; 🔵 prioritário; 🟡/🟣 normal.
# Cron: a cada 10 min (subido de 2h/2h em 2026-07-11 — "automação total": 2h era devagar
# demais para apanhar travamentos do mesmo dia). Limitação documentada: job logs do pg_cron
# do Supabase exigem service key (que o VPS NÃO tem, por design) → essa checagem é do lado do PC/MCP.
#
# 2026-07-11 (Parte 3 "automação total"): +2 checagens novas:
#   (a) ordem 'aberta' com tentativa=0 parada >15min sem ser apanhada — causa principal dos
#       travamentos de hoje, nunca antes coberta (o resto do vigia só olhava 'executando'/'travada').
#       AÇÃO própria fica no `hermes-carteiro-vigia.sh` (cron */5) — aqui é só o AVISO.
#   (b) crashes REAIS de app (RPC `real_crash_count_24h`, exclui rede/breadcrumb) >10/24h —
#       antes só aparecia quando alguém perguntava; agora entra no ciclo de 10 min, não espera
#       o daily-pulse.
set -u
C=hermes-agent-fvnc-hermes-agent-1
H=/docker/hermes-agent-fvnc/data
FILA=$H/cortex-brain/orquestracao
ENV=$H/.env
LOG=/root/hermes-watchdog.log
now=$(date +%s)
RED=(); AMB=()

# 1) ordens: executando >3h · travada/zona_vermelha >12h sem resposta · aberta tentativa=0 >15min
for f in "$FILA"/ordem-*.md; do
  [ -f "$f" ] || continue
  e=$(grep -m1 '^estado:' "$f" | sed 's/estado: *//' | tr -d '\r')
  t=$(grep -m1 '^tentativa:' "$f" | sed 's/tentativa: *//' | tr -d '\r')
  ageh=$(( (now - $(stat -c %Y "$f")) / 3600 ))
  agemin=$(( (now - $(stat -c %Y "$f")) / 60 ))
  id=$(basename "$f" .md)
  # arquivada/aprovada = estados terminais — FORA do whitelist travada|zona_vermelha de propósito (nao contam como pendente).
  case "$e" in
    executando) [ "$ageh" -ge 3 ] && RED+=("🟢Core orquestração: $id executando há ${ageh}h — verificar pc-loop/PC");;
    travada|zona_vermelha) [ "$ageh" -ge 12 ] && AMB+=("ordem $id ($e) espera-te há ${ageh}h");;
    aberta) [ "${t:-0}" = "0" ] && [ "$agemin" -ge 15 ] && RED+=("🟢Core orquestração: $id aberta tentativa=0 há ${agemin}min sem ser apanhada — carteiro/campainha lenta ou morta (vigia tenta reviver sozinho)");;
  esac
done

# 2) loops 🟢 Core vivos
find /root/hermes-daily-pulse.log -mmin -1560 >/dev/null 2>&1 || RED+=("🟢Core daily-pulse: sem execução há >26h")
pgrep -f "inotifywait.*orquestracao" >/dev/null 2>&1 || RED+=("🟢Core campainha: inotify parado (ordens só no fallback horário) — sugestão: correr campainha.sh")
docker ps --format '{{.Names}}' | grep -q "^$C$" || RED+=("🟢Core Hermes: container DOWN — sugestão: docker start $C")
AGE_MIRROR=$(( (now - $(stat -c %Y "$H/cortex-brain/.git/FETCH_HEAD" 2>/dev/null || echo "$now")) / 3600 ))
[ "$AGE_MIRROR" -ge 30 ] && AMB+=("espelho cortex-brain com ${AGE_MIRROR}h — sync das 06h30 falhou?")

# 3) recursos ≥85%
du=$(df -P / | awk 'NR==2{gsub("%","",$5); print $5}')
mu=$(free | awk '/Mem:/{printf "%d", ($2-$7)*100/$2}')
[ "${du:-0}" -ge 85 ] && RED+=("disco ${du}% cheio — sugestão: docker system prune (com o Danilo)")
[ "${mu:-0}" -ge 85 ] && AMB+=("RAM ${mu}% usada")

# 4) fila acumulada (>10 itens à espera do Danilo)
nwait=$(grep -l '^estado: \(travada\|zona_vermelha\)' "$FILA"/ordem-*.md 2>/dev/null | wc -l)
[ "$nwait" -gt 10 ] && AMB+=("fila com $nwait itens à tua espera")

# 5) crashes REAIS de app nas últimas 24h (exclui rede/breadcrumb) — RPC real_crash_count_24h
URL=$(grep -E '^SUPABASE_URL=' "$ENV" 2>/dev/null | head -1 | cut -d= -f2- | tr -d '"'\''\r')
KEY=$(grep -E '^SUPABASE_ANON_KEY=' "$ENV" 2>/dev/null | head -1 | cut -d= -f2- | tr -d '"'\''\r')
if [ -n "$URL" ] && [ -n "$KEY" ]; then
  resp=$(curl -s --max-time 15 -X POST "$URL/rest/v1/rpc/real_crash_count_24h" \
    -H "apikey: $KEY" -H "Authorization: Bearer $KEY" -H "Content-Type: application/json" -d '{}')
  rc=$(echo "$resp" | grep -oE '"real_count":[0-9]+' | head -1 | grep -oE '[0-9]+')
  [ -n "${rc:-}" ] && [ "$rc" -gt 10 ] 2>/dev/null && RED+=("🟢Core app: $rc crashes REAIS/24h (limite 10) — ver debug_crash_logs")
fi

echo "[$(date -Is)] red=${#RED[@]} amb=${#AMB[@]} disco=${du}% ram=${mu}%" >> "$LOG"
send(){ docker exec -u hermes "$C" hermes send -t telegram "$1" >/dev/null 2>&1 || echo "[$(date -Is)] envio falhou" >> "$LOG"; }
if [ ${#RED[@]} -gt 0 ]; then
  send "🚨 WATCHDOG BORA (VERMELHO): $(printf '%s · ' "${RED[@]}")$( [ ${#AMB[@]} -gt 0 ] && printf '| avisos: %s · ' "${AMB[@]}" )— eu só aviso, não ajo."
elif [ ${#AMB[@]} -gt 0 ]; then
  send "⚠️ Watchdog Bora: $(printf '%s · ' "${AMB[@]}")— eu só aviso, não ajo."
fi
exit 0

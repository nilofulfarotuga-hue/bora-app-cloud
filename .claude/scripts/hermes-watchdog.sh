#!/usr/bin/env bash
# --- STOP GLOBAL (reengenharia 2026-07-12): respeita .pausa-total ---
[ -f /docker/hermes-agent-fvnc/data/cortex-brain/orquestracao/.pausa-total ] && exit 0
# hermes-watchdog.sh v2 — DETETA → AGE se puder → só AVISA o Danilo se for dinheiro/ambíguo.
#
# Mudança 2026-07-12 ("watchdog age e limpa"): a v1 SÓ AVISAVA ("eu só aviso, não ajo") e
# re-enviava a MESMA lista de ordens travadas a cada 10 min = spam no Telegram. A v2:
#   1) AGE no que se sabe reviver — chama os revivedores que já existem (umbrella, não duplica):
#        · container Hermes DOWN            → docker start
#        · campainha morta / ordem aberta parada → hermes-carteiro-vigia.sh (revive + avisa ele)
#        · loop E2E parado a meio           → hermes-e2e-vigia.sh (toca a campainha; ele é silencioso no TG)
#   2) ESCALA ao Danilo SÓ o que precisa de decisão de dinheiro ou é genuinamente ambíguo
#      (zona_vermelha, travada esgotada >12h, daily-pulse morto, disco cheio, crashes reais).
#   3) ANTI-SPAM: a escalada tem ASSINATURA (hash do conjunto). Só envia se a assinatura MUDOU
#      desde o último tick. Mesma lista → silêncio. Fila esvazia → reset (próximo problema avisa
#      na hora). As ações são reportadas quando acontecem (os revivedores já têm dedupe próprio).
#
# Prioridade do alerta = COR do loop no registry (loops.md): 🟢 Core parado = topo.
# Cron: */10. Corre no HOST do VPS (root). Canónico: bora_app/.claude/scripts/. Instalado /usr/local/bin/.
# Limitação: job logs do pg_cron do Supabase exigem service key (VPS não tem) → checagem é do lado PC/MCP.
set -u
C=hermes-agent-fvnc-hermes-agent-1
H=/docker/hermes-agent-fvnc/data
FILA=$H/cortex-brain/orquestracao
ENV=$H/.env
LOG=/root/hermes-watchdog.log
SIG=/root/orquestracao/.watchdog.sig     # dedupe: assinatura da última escalada enviada
CARTEIRO_VIGIA=/usr/local/bin/hermes-carteiro-vigia.sh
E2E_VIGIA=/usr/local/bin/hermes-e2e-vigia.sh
now=$(date +%s)
mkdir -p /root/orquestracao 2>/dev/null || true

ACOES=()    # o que EU fiz este tick (reportado quando acontece; revivedores têm dedupe próprio)
ESCALAR=()  # dinheiro/ambíguo — enviado só se a assinatura mudou
ts(){ date -Is; }
send(){ docker exec -u hermes "$C" hermes send -t telegram "$1" >/dev/null 2>&1 || echo "[$(ts)] envio falhou" >> "$LOG"; }

# ---------- 1) AGIR: reviver o que se sabe reviver ----------

# 1a) container Hermes DOWN → start (ato próprio, reversível)
if ! docker ps --format '{{.Names}}' | grep -q "^$C$"; then
  if docker start "$C" >/dev/null 2>&1; then ACOES+=("🔄 container Hermes estava DOWN — dei docker start")
  else ESCALAR+=("⛔ container Hermes DOWN e NÃO reiniciou — precisa de ti"); fi
fi

# 1b) campainha morta OU ordem 'aberta' t=0 parada >15min → carteiro-vigia (ele revive + avisa)
campainha_morta=0; pgrep -f "inotifywait.*orquestracao" >/dev/null 2>&1 || campainha_morta=1
aberta_presa=""
for f in "$FILA"/ordem-*.md; do
  [ -f "$f" ] || continue
  e=$(grep -m1 '^estado:' "$f" | sed 's/estado: *//' | tr -d '\r')
  [ "$e" = "aberta" ] || continue
  t=$(grep -m1 '^tentativa:' "$f" | sed 's/tentativa: *//' | tr -d '\r')
  [ "${t:-0}" = "0" ] || continue
  agemin=$(( (now - $(stat -c %Y "$f")) / 60 ))
  [ "$agemin" -ge 15 ] && aberta_presa="$(basename "$f" .md) (${agemin}min)"
done
if [ "$campainha_morta" = 1 ] || [ -n "$aberta_presa" ]; then
  [ -x "$CARTEIRO_VIGIA" ] && "$CARTEIRO_VIGIA" >/dev/null 2>&1
  # a notificação de revival é do carteiro-vigia (dedupe próprio). Aqui só escalo se FALHOU reviver.
  pgrep -f "inotifywait.*orquestracao" >/dev/null 2>&1 || ESCALAR+=("⛔ campainha morta e não foi revivida — olha o carteiro-vigia.log")
fi

# 1c) loop E2E parado a meio → e2e-vigia toca a campainha (silencioso no TG → eu reporto o ato)
if [ -x "$E2E_VIGIA" ]; then
  e2e_out=$("$E2E_VIGIA" 2>&1)
  echo "$e2e_out" | grep -qi "CAMPAINHA" && ACOES+=("🔔 loop E2E estava em silêncio — retomei-o (e2e-vigia injetou ordem)")
fi

# 1d) ordem 'executando' há >3h → pc-loop pode estar preso (não há reviver seguro → escala)
for f in "$FILA"/ordem-*.md; do
  [ -f "$f" ] || continue
  e=$(grep -m1 '^estado:' "$f" | sed 's/estado: *//' | tr -d '\r')
  [ "$e" = "executando" ] || continue
  ageh=$(( (now - $(stat -c %Y "$f")) / 3600 ))
  [ "$ageh" -ge 3 ] && ESCALAR+=("🟢 ordem $(basename "$f" .md) executando há ${ageh}h — pc-loop pode estar preso")
done

# ---------- 2) ESCALAR: só dinheiro / ambíguo (sem ato seguro possível) ----------

# 2a) zona_vermelha = decisão de dinheiro/produção — SEMPRE do Danilo
nvr=$(grep -l '^estado: zona_vermelha' "$FILA"/ordem-*.md 2>/dev/null | wc -l)
[ "$nvr" -gt 0 ] && ESCALAR+=("🔴 $nvr ordem(ns) zona_vermelha à tua espera (dinheiro/produção)")

# 2b) travada esgotada (tentativas no teto) >12h — ambíguo: decide arquivar ou reformular
ntrav=0
for f in "$FILA"/ordem-*.md; do
  [ -f "$f" ] || continue
  e=$(grep -m1 '^estado:' "$f" | sed 's/estado: *//' | tr -d '\r')
  [ "$e" = "travada" ] || continue
  ageh=$(( (now - $(stat -c %Y "$f")) / 3600 ))
  [ "$ageh" -ge 12 ] && ntrav=$((ntrav+1))
done
[ "$ntrav" -gt 0 ] && ESCALAR+=("🟡 $ntrav ordem(ns) travada(s) >12h (tentativas esgotadas) — arquivar ou reformular")

# 2c) daily-pulse morto (>26h)
find /root/hermes-daily-pulse.log -mmin -1560 >/dev/null 2>&1 || ESCALAR+=("🟢 daily-pulse sem execução há >26h")

# 2d) disco ≥85% (prune é decisão contigo)
du=$(df -P / | awk 'NR==2{gsub("%","",$5); print $5}')
[ "${du:-0}" -ge 85 ] && ESCALAR+=("💾 disco ${du}% cheio — prune contigo")

# 2e) RAM ≥90% (só informativo, entra na escalada agregada)
mu=$(free | awk '/Mem:/{printf "%d", ($2-$7)*100/$2}')
[ "${mu:-0}" -ge 90 ] && ESCALAR+=("🧠 RAM ${mu}% usada")

# 2f) crashes REAIS de app >10/24h (RPC real_crash_count_24h; exclui rede/breadcrumb)
URL=$(grep -E '^SUPABASE_URL=' "$ENV" 2>/dev/null | head -1 | cut -d= -f2- | tr -d '"'\''\r')
KEY=$(grep -E '^SUPABASE_ANON_KEY=' "$ENV" 2>/dev/null | head -1 | cut -d= -f2- | tr -d '"'\''\r')
if [ -n "$URL" ] && [ -n "$KEY" ]; then
  resp=$(curl -s --max-time 15 -X POST "$URL/rest/v1/rpc/real_crash_count_24h" \
    -H "apikey: $KEY" -H "Authorization: Bearer $KEY" -H "Content-Type: application/json" -d '{}')
  rc=$(echo "$resp" | grep -oE '"real_count":[0-9]+' | head -1 | grep -oE '[0-9]+')
  [ -n "${rc:-}" ] && [ "$rc" -gt 10 ] 2>/dev/null && ESCALAR+=("🟢 $rc crashes REAIS/24h (limite 10) — ver debug_crash_logs")
fi

# ---------- 3) ENVIAR: ações reportam sempre; escalada só se a assinatura mudou ----------
sig=$(printf '%s\n' "${ESCALAR[@]:-}" | sort | md5sum | cut -d' ' -f1)
prev=$(cat "$SIG" 2>/dev/null | tr -d '\r\n')
echo "[$(ts)] acoes=${#ACOES[@]} escalar=${#ESCALAR[@]} disco=${du}% ram=${mu}% sig=$sig prev=$prev" >> "$LOG"

msg=""
[ ${#ACOES[@]} -gt 0 ] && msg="✅ Watchdog Bora AGIU: $(printf '%s · ' "${ACOES[@]}")"
if [ ${#ESCALAR[@]} -gt 0 ] && [ "$sig" != "$prev" ]; then
  msg="${msg}⚠️ Precisa de ti (novo/mudou): $(printf '%s · ' "${ESCALAR[@]}")"
fi

# grava/reseta assinatura para não re-alertar a mesma lista; fila limpa → reset
if [ ${#ESCALAR[@]} -gt 0 ]; then printf '%s' "$sig" > "$SIG"; else rm -f "$SIG"; fi

[ -n "$msg" ] && send "$msg"
exit 0

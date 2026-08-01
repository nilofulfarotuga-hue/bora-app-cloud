#!/usr/bin/env bash
# hermes-notificar-rotina.sh — dispatcher AVARO para a Rotina Claude Code (claude.ai/code/routines).
#
# PORQUÊ: o Danilo quer ser avisado na hora (missão fechou / ordem travou de vez / auth caiu) com
# um resumo em português claro, escrito por LLM (não um template bash) — sem pagar API extra e sem
# sondar de 10 em 10 min. A Rotina resolve isso: gatilho HTTP, corre num sessão cloud da conta
# claude.ai do Danilo. Mas o plano Pro só dá 5 corridas/dia (confirmado nos docs oficiais,
# 2026-08-01) — por isso este script só dispara em eventos que IMPORTAM (nunca por tentativa/ordem
# individual) e, quando o teto do dia já foi gasto, cai sozinho no caminho Telegram normal que já
# existe (mesmo mecanismo do hermes-sonda-auth.sh), sem gastar rotina nenhuma.
#
# Uso:
#   hermes-notificar-rotina.sh <tipo> <texto do evento...>
#   hermes-notificar-rotina.sh --selftest      (não toca rede real; usa um curl-stub em PATH)
#
# <tipo> é só para o log/contexto (missao_concluida | travada_esgotada | perda_auth | outro).
#
# Config (fora do repo, como o token do executor — ver watchdog do token OAuth da VPS):
#   /root/.bora-rotina-notificacao.env  com:
#     ROUTINE_FIRE_URL=https://api.anthropic.com/v1/claude_code/routines/trig_XXXX/fire
#     ROUTINE_FIRE_TOKEN=sk-ant-oat01-xxxxx
#   Sem este ficheiro (ainda não criado pelo Danilo) -> cai direto no fallback, sempre.
#
# Contador diário: /root/orquestracao/.rotina-notificacao-contagem ("YYYY-MM-DD:N").
# Teto: ROTINA_LIMITE_DIARIO (default 5 — plano Pro; Max=15, Team/Enterprise=25).
#
# Fallback Telegram: mesma leitura de credenciais do hermes-sonda-auth.sh
# (/docker/hermes-agent-fvnc/data/.env, chaves TELEGRAM_BOT_TOKEN/TELEGRAM_CHAT_ID).
#
# Canónico no repo: bora_app/.claude/scripts/. Deploy espelhado: /usr/local/bin/ no VPS.
set -u

SCRIPT_PATH="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)/$(basename "${BASH_SOURCE[0]:-$0}")"
CFG="${ROTINA_CFG:-/root/.bora-rotina-notificacao.env}"
CONTADOR="${ROTINA_CONTADOR:-/root/orquestracao/.rotina-notificacao-contagem}"
LIMITE="${ROTINA_LIMITE_DIARIO:-5}"
LOG="${ROTINA_LOG:-/root/orquestracao/rotina-notificacao.log}"
ENV_TELEGRAM="${ROTINA_ENV_TELEGRAM:-/docker/hermes-agent-fvnc/data/.env}"
BETA_HEADER="experimental-cc-routine-2026-04-01"
API_VERSION="2023-06-01"
SELFTEST=0
[ "${1:-}" = "--selftest" ] && SELFTEST=1

ts(){ date -u +%Y-%m-%dT%H:%M:%SZ; }
log(){ echo "[$(ts)] $*" >> "$LOG" 2>/dev/null || echo "[$(ts)] $*"; }

# --- contador diário (reset automático quando muda a data UTC) ---------------
contagem_hoje(){
  local hoje ida n
  hoje=$(date -u +%F)
  if [ -f "$CONTADOR" ]; then
    ida=$(cut -d: -f1 "$CONTADOR" 2>/dev/null)
    n=$(cut -d: -f2 "$CONTADOR" 2>/dev/null)
  fi
  [ "${ida:-}" = "$hoje" ] || n=0
  echo "${n:-0}"
}
gravar_contagem(){
  mkdir -p "$(dirname "$CONTADOR")" 2>/dev/null
  echo "$(date -u +%F):$1" > "$CONTADOR"
}

# --- fallback: caminho Telegram normal que já existe (sem gastar rotina) -----
enviar_fallback_telegram(){
  local texto="$1"
  if [ "$SELFTEST" = 1 ]; then echo "[FALLBACK-TELEGRAM] $texto"; return 0; fi
  # A chave real no .env do Hermes é TELEGRAM_HOME_CHANNEL (não TELEGRAM_CHAT_ID — essa nunca
  # existiu ali; achado ao provar este script ao vivo em 2026-08-01, corrigido também no
  # hermes-sonda-auth.sh, que tinha o mesmo engano e por isso nunca tinha entregue nada).
  local tok chat
  tok=$(grep -E '^TELEGRAM_BOT_TOKEN=' "$ENV_TELEGRAM" 2>/dev/null | head -1 | cut -d= -f2- | tr -d '"'\''\r')
  chat=$(grep -E '^TELEGRAM_HOME_CHANNEL=' "$ENV_TELEGRAM" 2>/dev/null | head -1 | cut -d= -f2- | tr -d '"'\''\r')
  if [ -n "$tok" ] && [ -n "$chat" ]; then
    local resp
    resp=$(curl -s --max-time 20 -X POST "https://api.telegram.org/bot$tok/sendMessage" \
      --data-urlencode "chat_id=$chat" --data-urlencode "text=$texto")
    log "fallback: Telegram enviado directo (sem LLM). resposta_api=$(printf '%s' "$resp" | tr -d '\n' | cut -c1-200)"
  else
    log "fallback: SEM credenciais Telegram em $ENV_TELEGRAM — aviso perdido"
  fi
}

# --- dispara a Rotina via /fire, com o texto do evento como contexto --------
disparar_rotina(){
  local texto="$1"
  local url token resp http_code body
  url=$(grep -E '^ROUTINE_FIRE_URL=' "$CFG" 2>/dev/null | head -1 | cut -d= -f2- | tr -d '"'\''\r')
  token=$(grep -E '^ROUTINE_FIRE_TOKEN=' "$CFG" 2>/dev/null | head -1 | cut -d= -f2- | tr -d '"'\''\r')
  if [ -z "$url" ] || [ -z "$token" ]; then
    echo "SEM_CONFIG"
    return 1
  fi
  local payload
  payload=$(printf '%s' "$texto" | python3 -c 'import json,sys; print(json.dumps({"text": sys.stdin.read()}))' 2>/dev/null)
  if [ -z "$payload" ]; then
    # sem python3 no host -> escapa à mão (aspas e barras invertidas), suficiente para texto simples
    local esc; esc=$(printf '%s' "$texto" | sed 's/\\/\\\\/g; s/"/\\"/g' | tr '\n' ' ')
    payload="{\"text\": \"$esc\"}"
  fi
  resp=$(curl -s --max-time 30 -w '\n%{http_code}' -X POST "$url" \
    -H "Authorization: Bearer $token" \
    -H "anthropic-beta: $BETA_HEADER" \
    -H "anthropic-version: $API_VERSION" \
    -H "Content-Type: application/json" \
    -d "$payload")
  http_code=$(printf '%s' "$resp" | tail -1)
  body=$(printf '%s' "$resp" | sed '$d')
  echo "$http_code|$body"
}

# --- orquestração principal ---------------------------------------------------
notificar(){
  local tipo="$1" texto="$2"
  local n; n=$(contagem_hoje)

  if [ "$n" -ge "$LIMITE" ] 2>/dev/null; then
    log "evento=$tipo LIMITE-ATINGIDO ($n/$LIMITE) -> fallback (sem gastar rotina)"
    enviar_fallback_telegram "$texto"
    return 0
  fi

  local out http body
  out=$(disparar_rotina "$texto")
  if [ "$out" = "SEM_CONFIG" ]; then
    log "evento=$tipo ROTINA-NAO-CONFIGURADA ($CFG ausente/incompleto) -> fallback"
    enviar_fallback_telegram "$texto"
    return 0
  fi
  http=$(printf '%s' "$out" | cut -d'|' -f1)
  body=$(printf '%s' "$out" | cut -d'|' -f2-)

  case "$http" in
    200)
      gravar_contagem $((n+1))
      log "evento=$tipo ROTINA-DISPARADA ($((n+1))/$LIMITE hoje). resposta=$(printf '%s' "$body" | tr -d '\n' | cut -c1-200)"
      ;;
    429)
      gravar_contagem "$LIMITE"   # teto real da conta já bateu (pode ter sido gasto fora deste script) -> não insistir hoje
      log "evento=$tipo ROTINA-429-RATE-LIMIT (teto da conta atingido) -> fallback + contador travado no teto"
      enviar_fallback_telegram "$texto"
      ;;
    "")
      log "evento=$tipo ROTINA-SEM-RESPOSTA (rede/timeout) -> fallback"
      enviar_fallback_telegram "$texto"
      ;;
    *)
      log "evento=$tipo ROTINA-ERRO http=$http resposta=$(printf '%s' "$body" | tr -d '\n' | cut -c1-200) -> fallback"
      enviar_fallback_telegram "$texto"
      ;;
  esac
}

# --- selftest (headless, sem rede real) ---------------------------------------
# Invoca o próprio script como subprocesso (CLI real: <tipo> <texto>), com as
# overrides ROTINA_CFG/ROTINA_CONTADOR/ROTINA_LOG/ROTINA_ENV_TELEGRAM por env —
# exactamente o mesmo caminho que um chamador real (hook-conclusão/sonda) usa.
selftest(){
  local tmp; tmp=$(mktemp -d); local ok=0 fail=0
  chk(){ if eval "$2"; then echo "  [OK] $1"; ok=$((ok+1)); else echo "  [X ] $1"; fail=$((fail+1)); fi; }

  # curl-stub em PATH: simula 200 ou 429 conforme o URL pedido, sem tocar rede
  mkdir -p "$tmp/bin"
  cat > "$tmp/bin/curl" <<'STUBEOF'
#!/usr/bin/env bash
# stub de teste: devolve 200 se o URL contém "trig_OK", 429 se contém "trig_429", senão 500.
for a in "$@"; do case "$a" in
  *trig_OK*) echo '{"type":"routine_fire","claude_code_session_id":"session_TEST","claude_code_session_url":"https://claude.ai/code/session_TEST"}'; echo 200; exit 0 ;;
  *trig_429*) echo '{"type":"error","error":{"type":"rate_limit_error","message":"daily cap"}}'; echo 429; exit 0 ;;
esac; done
echo '{}'; echo 500
STUBEOF
  chmod +x "$tmp/bin/curl"

  rodar(){ # $1=cfg $2=contador $3=log $4=tipo $5=texto
    PATH="$tmp/bin:$PATH" ROTINA_CFG="$1" ROTINA_CONTADOR="$2" ROTINA_LOG="$3" \
      ROTINA_ENV_TELEGRAM="$tmp/sem-telegram.env" bash "$SCRIPT_PATH" "$4" "$5" >/dev/null 2>&1
  }

  echo "== T1: sem ficheiro de config -> cai no fallback, log diz ROTINA-NAO-CONFIGURADA =="
  rodar "$tmp/nao-existe.env" "$tmp/contagem1" "$tmp/log1" missao_concluida "teste 1"
  chk "logou ROTINA-NAO-CONFIGURADA" 'grep -q "ROTINA-NAO-CONFIGURADA" "$tmp/log1"'

  echo "== T2: config válida (trig_OK) -> dispara rotina, incrementa contador para 1 =="
  echo "ROUTINE_FIRE_URL=https://api.anthropic.com/v1/claude_code/routines/trig_OK/fire" > "$tmp/ok.env"
  echo "ROUTINE_FIRE_TOKEN=sk-ant-oat01-teste" >> "$tmp/ok.env"
  rodar "$tmp/ok.env" "$tmp/contagem2" "$tmp/log2" missao_concluida "teste 2"
  chk "logou ROTINA-DISPARADA" 'grep -q "ROTINA-DISPARADA" "$tmp/log2"'
  chk "contador foi para 1" '[ "$(cat "$tmp/contagem2")" = "$(date -u +%F):1" ]'

  echo "== T3: contador já no teto -> NUNCA chama a rotina, vai direto ao fallback =="
  echo "$(date -u +%F):5" > "$tmp/contagem3"
  rodar "$tmp/ok.env" "$tmp/contagem3" "$tmp/log3" travada_esgotada "teste 3"
  chk "logou LIMITE-ATINGIDO" 'grep -q "LIMITE-ATINGIDO" "$tmp/log3"'
  chk "NAO chamou a rotina (nada de ROTINA-DISPARADA)" '! grep -q "ROTINA-DISPARADA" "$tmp/log3"'

  echo "== T4: contador reseta em dia novo (data velha no ficheiro) =="
  echo "2020-01-01:5" > "$tmp/contagem4"
  rodar "$tmp/ok.env" "$tmp/contagem4" "$tmp/log4" missao_concluida "teste 4"
  chk "disparou (contador de dia velho nao bloqueia)" 'grep -q "ROTINA-DISPARADA" "$tmp/log4"'

  echo "== T5: 429 (teto real da conta) -> fallback + trava contador no teto do dia =="
  echo "ROUTINE_FIRE_URL=https://api.anthropic.com/v1/claude_code/routines/trig_429/fire" > "$tmp/e429.env"
  echo "ROUTINE_FIRE_TOKEN=sk-ant-oat01-teste" >> "$tmp/e429.env"
  rodar "$tmp/e429.env" "$tmp/contagem5" "$tmp/log5" travada_esgotada "teste 5"
  chk "logou 429" 'grep -q "ROTINA-429-RATE-LIMIT" "$tmp/log5"'
  chk "contador foi travado no limite (5)" '[ "$(cut -d: -f2 "$tmp/contagem5")" = "5" ]'

  rm -rf "$tmp"
  echo "-- selftest: $ok OK, $fail FALHAS --"
  [ "$fail" = 0 ]
}

# --- main ----------------------------------------------------------------------
if [ "$SELFTEST" = 1 ] && [ $# -eq 1 ]; then selftest; exit $?; fi
[ $# -ge 2 ] || { echo "uso: $0 <tipo> <texto do evento...>  |  --selftest" >&2; exit 2; }
tipo="$1"; shift
notificar "$tipo" "$*"
exit 0

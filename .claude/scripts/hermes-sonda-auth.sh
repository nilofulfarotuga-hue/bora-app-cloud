#!/usr/bin/env bash
# --- STOP GLOBAL (reengenharia 2026-07-12): respeita .pausa-total ---
[ -f /docker/hermes-agent-fvnc/data/cortex-brain/orquestracao/.pausa-total ] && exit 0
# hermes-sonda-auth.sh — FASE 1.11 item 5 (2026-08-01). Sonda DIÁRIA da auth do executor.
#
# PORQUÊ: a 27/07 a CLI mudou de sítio e a sessão OAuth do executor ficou inutilizável. A avaria
# só foi notada a 31/07 — 4 DIAS — porque cada ordem morria com a nota genérica "SAIDA-VAZIA —
# tarefa grande demais?". Consertar aquele caso não impede a repetição: o token VAI expirar outra
# vez. Esta sonda avisa QUANDO a auth morre, não quando as ordens já morreram há dias.
#
# PROVA POR CORRIDA REAL, NÃO POR `auth status` (revisto 2026-08-01, antes do token entrar).
# A 1.ª versão desta sonda corria `claude auth status` por SSH direto. Furo apanhado pelo Danilo:
#   (1) com a auth a vir de CLAUDE_CODE_OAUTH_TOKEN, `auth status` pode ler o credential store
#       (.credentials.json) e reportar loggedIn:false com o loop a FUNCIONAR — ou o contrário,
#       que é pior: verde falso enquanto as ordens morrem;
#   (2) invocação direta != invocação do executor, logo pode nem herdar o mesmo ambiente.
# Uma sonda que lê a fonte errada é PIOR que nenhuma: dá falsa confiança.
# Por isso a sonda passa pelo MESMO caminho do executor (`pc-loop` -> run-claude-loop.cmd ->
# mesmo helper de binário, mesmo ambiente, mesmos flags) e prova pelo ÚNICO facto que interessa:
# o executor produziu texto? Ground truth, não auto-relato.
#
# CUSTO: 1 corrida mínima de 1 turno por dia. Desprezável, e é o preço de não ter verde falso.
#
# Alerta 1x por transição (dedupe por estado), não a cada corrida — senão vira o spam de 40 min
# que esta missão inteira existe para matar. Volta a avisar quando recupera.
#
# Canónico no repo: bora_app/.claude/scripts/. Instalado em /usr/local/bin/ no VPS (cron diário).
# Uso: hermes-sonda-auth.sh [--dry]
set -u

DRY=0; [ "${1:-}" = "--dry" ] && DRY=1

STATE=/root/orquestracao/sonda-auth.estado
LOG=/root/orquestracao/sonda-auth.log
C=hermes-agent-fvnc-hermes-agent-1
ENV=/docker/hermes-agent-fvnc/data/.env

ts(){ date -u +%FT%TZ; }
log(){ echo "[$(ts)] $*" >> "$LOG"; }

# EXATAMENTE o mesmo caminho que uma ordem real percorre: pc-loop -> run-claude-loop.cmd.
# Nada de invocar o claude.exe à mão — se a sonda usasse outra invocação, provaria outra coisa.
SENTINELA=SONDA-AUTH-OK
saida=$(docker exec -u hermes "$C" sh -lc \
  "export PATH=/opt/data/.local/bin:\$PATH; timeout 300 pc-loop 'Responde apenas com esta linha exata e nada mais: $SENTINELA'" 2>&1)

# Ordem de leitura importa: os modos de falha específicos ANTES do genérico, senão voltamos a
# diagnosticar mal (foi assim que a avaria do binário passou 4 dias como "tarefa grande demais").
if printf '%s' "$saida" | grep -q "$SENTINELA"; then
  novo=ok                # ground truth: o executor produziu texto -> auth boa, seja qual for a fonte
elif printf '%s' "$saida" | grep -qiE 'CLI-SEM-AUTH|Failed to authenticate|OAuth session expired|Invalid API key|not logged in'; then
  novo=sem_auth
elif printf '%s' "$saida" | grep -qi 'CLI-NAO-ENCONTRADA'; then
  novo=cli_ausente       # binário fora do sítio — outra avaria, outro alerta
else
  novo=inconclusivo      # ponte/timeout/lock ocupado — não afirmar nada sobre a auth
fi

anterior=$(cat "$STATE" 2>/dev/null || echo "")
resumo=$(printf '%s' "$saida" | tr -d '\n' | tr -s ' ' | cut -c1-220)

if [ "$DRY" = 1 ]; then
  echo "DRY: estado=$novo (anterior=${anterior:-<nenhum>})"
  echo "DRY: resposta=$resumo"
  exit 0
fi

log "estado=$novo anterior=${anterior:-<nenhum>} resposta=$resumo"
[ "$novo" = "$anterior" ] && exit 0    # dedupe: alerta só na TRANSIÇÃO
echo "$novo" > "$STATE"

case "$novo" in
  sem_auth)
    msg="🔑 EXECUTOR SEM AUTH — o loop corre mas nao autentica. NENHUMA ordem vai executar ate renovares: 'claude setup-token' (como danil) + 'setx /M CLAUDE_CODE_OAUTH_TOKEN <token>' como Admin + 'Restart-Service sshd'. Resposta: $resumo" ;;
  cli_ausente)
    msg="🚫 EXECUTOR SEM CLI — o binario do Claude Code nao foi encontrado no perfil do executor (a CLI mudou de sitio outra vez?). Resposta: $resumo" ;;
  ok)
    [ -z "$anterior" ] && exit 0       # 1.ª execucao com tudo bem: nao ha nada a anunciar
    msg="✅ EXECUTOR OK — corrida minima real devolveu a sentinela; o loop executa." ;;
  *)
    exit 0 ;;                          # inconclusivo (ponte/timeout/lock): nao afirma nada
esac

TG_TOKEN=$(grep -E '^TELEGRAM_BOT_TOKEN=' "$ENV" 2>/dev/null | head -1 | cut -d= -f2- | tr -d '"'\''\r')
TG_CHAT=$(grep -E '^TELEGRAM_CHAT_ID=' "$ENV" 2>/dev/null | head -1 | cut -d= -f2- | tr -d '"'\''\r')
if [ -n "$TG_TOKEN" ] && [ -n "$TG_CHAT" ]; then
  curl -s --max-time 20 -X POST "https://api.telegram.org/bot$TG_TOKEN/sendMessage" \
    --data-urlencode "chat_id=$TG_CHAT" --data-urlencode "text=$msg" >/dev/null
  log "TELEGRAM enviado ($novo)"
else
  log "sem credenciais Telegram em $ENV — alerta nao enviado ($novo)"
fi

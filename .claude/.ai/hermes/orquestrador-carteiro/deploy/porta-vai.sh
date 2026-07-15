#!/usr/bin/env bash
# porta-vai.sh — a metade que faltava da zona vermelha do carteiro.sh: o caminho de VOLTA.
#
# CONTEXTO (2026-07-15, ordem ordem-20260715160322-02df): carteiro.sh marca uma ordem como
# `estado: zona_vermelha` (dinheiro + intenção de escrita), avisa no Telegram, e PARA — mas
# nunca existiu nenhum código que lesse a resposta do Danilo para a destravar. Resultado:
# ordens em zona_vermelha ficavam presas para sempre. Isto NÃO enfraquece a barreira: a
# barreira continua a parar tudo e a exigir uma pessoa; isto só dá à pessoa uma forma de
# responder. zona_vermelha() em carteiro.sh NÃO é tocada por este ficheiro.
#
# COMO FUNCIONA (porquê esta abordagem e não um novo bot Telegram):
# O bot @BoraHermesbot já corre dentro do container hermes-agent-fvnc-hermes-agent-1 como um
# gateway python-telegram-bot em modo polling (Updater.start_polling — é o processo que a
# tarefa chama "cortex-mcp": reiniciá-lo derruba o OAuth do Danilo). O Telegram só permite UM
# consumidor de getUpdates por bot token — um segundo poller correndo em paralelo entraria em
# conflito (409) com esse gateway e podia interrompê-lo. Em vez de arriscar isso, este script
# não fala com a API do Telegram: ele lê (read-only) o ficheiro que o próprio gateway já
# escreve para cada mensagem recebida — /docker/hermes-agent-fvnc/data/logs/gateway.log, linha
# "inbound message: platform=telegram user=<nome> chat=<chat_id> msg='<texto>' ...". Zero
# risco de conflito, zero mudança no gateway existente.
#
# Corre via CRON DO USER hermes-exec (não root — este executor não tem sudo/crontab de root
# nem acesso a /root/orquestracao). */1 min é suficiente e barato (1 leitura incremental de
# log + greps). Ver deploy/DEPLOY.md para instruções de instalação real (root, /usr/local/bin,
# se um dia isto for promovido a produção oficial tal como o carteiro.sh).
#
# BARREIRAS DURAS (sem exceção, todas verificadas antes de qualquer escrita):
#   1) só o chat_id do Danilo é aceite — qualquer outro é IGNORADO e REGISTADO em e2e_log.
#   2) a mensagem tem de ser EXATAMENTE "vai <token>" (2 palavras) — nunca "vai tudo",
#      "desliga a barreira", nem nada com mais de 1 id.
#   3) <token> tem de bater no formato real de id de ordem (ordem-<14 digitos>-<hex>) E o
#      ficheiro tem de existir E estar em `estado: zona_vermelha` neste preciso instante —
#      senão é ignorado e registado, nunca aplicado às cegas.
#   4) cada uso (aceite OU rejeitado) fica em e2e_log (fluxo='vai-usado' | 'vai-rejeitado' |
#      'vai-invalido' | 'vai-estado-errado') com id da ordem, hora e chat_id de origem.
#   5) backup .bak-porta-vai-<timestamp> do ficheiro da ordem ANTES de qualquer escrita.
#
# PORTA_VAI_GWLOG / PORTA_VAI_FILA: overrides só para prova/teste (simulação sem tocar no
# gateway.log real nem na fila real de produção). Em produção usam sempre os defaults.
set -u

H=/docker/hermes-agent-fvnc/data
GWLOG="${PORTA_VAI_GWLOG:-$H/logs/gateway.log}"
FILA="${PORTA_VAI_FILA:-$H/cortex-brain/orquestracao}"
ENV="$H/.env"
DANILO_CHAT_ID=6731890157

# Estado do próprio porta-vai (offset do log, log operacional) vive FORA da fila watched por
# inotify (campainha.sh vigia a fila inteira com -e close_write) — se vivesse lá dentro, cada
# tick do cron (que reescreve o offset) acordava o campainha e disparava carteiro.sh à toa.
# PORTA_VAI_STATE_DIR: override só para prova/teste — evita que um run de teste (apontado a um
# gateway.log sintético via PORTA_VAI_GWLOG) pise o offset real do gateway.log de produção.
STATE_DIR="${PORTA_VAI_STATE_DIR:-/home/hermes-exec/.porta-vai}"
OFFSET="$STATE_DIR/gwlog.offset"
LOG="$STATE_DIR/porta-vai.log"
mkdir -p "$STATE_DIR"

ts(){ date -u +%Y-%m-%dT%H:%M:%SZ; }
log(){ echo "[$(ts)] $*" >> "$LOG"; }
get(){ grep -E "^$1:" "$2" 2>/dev/null | head -1 | sed "s/^$1: *//" | tr -d '\r'; }
setf(){ if grep -qE "^$1:" "$3"; then sed -i "s|^$1:.*|$1: $2|" "$3"; else echo "$1: $2" >> "$3"; fi; }

e2e_insert(){ # $1=fluxo $2=run_id $3=passo $4=estado $5=detalhe
  [ -f "$ENV" ] || { log "sem .env, skip e2e_log"; return; }
  local SUPABASE_URL SUPABASE_ANON_KEY
  SUPABASE_URL=$(grep -E '^SUPABASE_URL=' "$ENV" | head -1 | cut -d= -f2-)
  SUPABASE_ANON_KEY=$(grep -E '^SUPABASE_ANON_KEY=' "$ENV" | head -1 | cut -d= -f2-)
  [ -n "$SUPABASE_URL" ] && [ -n "$SUPABASE_ANON_KEY" ] || { log "sem credenciais supabase, skip e2e_log"; return; }
  curl -s -X POST "$SUPABASE_URL/rest/v1/e2e_log" \
    -H "apikey: $SUPABASE_ANON_KEY" -H "Authorization: Bearer $SUPABASE_ANON_KEY" \
    -H "Content-Type: application/json" -H "Prefer: return=minimal" \
    -d "$(python3 -c 'import json,sys; print(json.dumps({"fluxo":sys.argv[1],"run_id":sys.argv[2],"passo":sys.argv[3],"estado":sys.argv[4],"detalhe":sys.argv[5]}))' "$1" "$2" "$3" "$4" "$5")" >> "$LOG" 2>&1
}

[ -f "$GWLOG" ] || { log "gateway.log nao encontrado em $GWLOG"; exit 0; }

size=$(stat -c%s "$GWLOG")
last=0
[ -f "$OFFSET" ] && last=$(cat "$OFFSET" 2>/dev/null)
case "$last" in ''|*[!0-9]*) last=0 ;; esac
# log rotacionado/truncado (size < last) -> reprocessa do inicio; é seguro porque cada ação
# revalida `estado: zona_vermelha` no ficheiro ANTES de escrever (replay de um 'vai' antigo
# já aplicado vira no-op, nunca reaplica).
[ "$last" -gt "$size" ] && last=0

novas=""
[ "$size" -gt "$last" ] && novas=$(tail -c +"$((last + 1))" "$GWLOG")
echo "$size" > "$OFFSET"
[ -z "$novas" ] && exit 0

printf '%s\n' "$novas" | grep -E "inbound message: platform=telegram" | while IFS= read -r linha; do
  chat=$(printf '%s' "$linha" | grep -oE 'chat=[0-9]+' | head -1 | cut -d= -f2)
  msg=$(printf '%s' "$linha" | sed -nE "s/.*msg='(.*)' reply_to_id=.*/\1/p")
  [ -z "$chat" ] && continue

  # tem de ser EXATAMENTE "vai <token>" (case-insensitive no "vai", token sem espaços) —
  # isto por si só já recusa "vai tudo"/"desliga a barreira" como frase solta; o guard forte
  # de verdade é o formato+existência+estado do id, abaixo.
  printf '%s' "$msg" | grep -iqE '^[[:space:]]*vai[[:space:]]+[A-Za-z0-9_-]+[[:space:]]*$' || continue
  id=$(printf '%s' "$msg" | sed -E 's/^[[:space:]]*[Vv][Aa][Ii][[:space:]]+([A-Za-z0-9_-]+)[[:space:]]*$/\1/')

  if [ "$chat" != "$DANILO_CHAT_ID" ]; then
    log "REJEITADO: chat=$chat (nao autorizado) tentou 'vai $id'"
    e2e_insert "vai-rejeitado" "$id" "chat-nao-autorizado" "falhou" "chat_id=$chat nao e o chat_id do Danilo; msg='$msg'; ignorado sem efeito"
    continue
  fi

  if ! printf '%s' "$id" | grep -qE '^ordem-[0-9]{14}-[0-9a-fA-F]{4,}$'; then
    log "IGNORADO: Danilo (chat=$chat) enviou 'vai $id' — nao e um id de ordem valido (bloqueia comando generico)"
    e2e_insert "vai-invalido" "$id" "id-formato-invalido" "falhou" "chat_id=$chat id='$id' nao bate no formato ordem-<timestamp>-<hex>; comando generico bloqueado, nenhum efeito"
    continue
  fi

  f="$FILA/$id.md"
  if [ ! -f "$f" ]; then
    log "IGNORADO: ordem $id nao existe em $FILA"
    e2e_insert "vai-nao-encontrado" "$id" "ordem-inexistente" "falhou" "chat_id=$chat ordem=$id ficheiro nao existe"
    continue
  fi

  estado_atual=$(get estado "$f")
  if [ "$estado_atual" != "zona_vermelha" ]; then
    log "IGNORADO: ordem $id estado atual='$estado_atual' (so destrava se for zona_vermelha)"
    e2e_insert "vai-estado-errado" "$id" "estado-nao-e-zona-vermelha" "falhou" "chat_id=$chat ordem=$id estado_atual=$estado_atual (esperado zona_vermelha)"
    continue
  fi

  cp -p "$f" "$f.bak-porta-vai-$(date -u +%Y%m%d%H%M%S)"
  setf estado aberta "$f"
  setf nota "✅ destravada por Danilo via Telegram (vai $id)" "$f"
  # PERSISTÊNCIA DO "VAI" (2026-07-15): sem isto, o carteiro.sh reavalia zona_vermelha(tarefa)
  # no ciclo seguinte e volta a marcar vermelho (o texto da tarefa continua a mesma). Este
  # registo — autorizado_por/autorizado_em — é a única forma de o carteiro saber que ESTA
  # ordem específica já foi autorizada por um humano. Escrito NO MESMO instante/bloco em que o
  # estado muda (mesmo evento), e só chega aqui depois de $chat já ter sido validado como
  # $DANILO_CHAT_ID acima. Nenhum outro código (carteiro.sh, agentes, o executor da própria
  # ordem) tem permissão para escrever estes dois campos — só esta rotina, aqui.
  autorizado_em=$(ts)
  setf autorizado_por "$chat" "$f"
  setf autorizado_em "$autorizado_em" "$f"
  log "DESTRAVADA: ordem $id zona_vermelha -> aberta (chat=$chat)"
  e2e_insert "vai-usado" "$id" "vai-usado" "passou" "ordem=$id chat_id=$chat hora=$(ts) estado: zona_vermelha -> aberta; autorizado_por=$chat autorizado_em=$autorizado_em"
done

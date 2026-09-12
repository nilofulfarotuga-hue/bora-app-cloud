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
# ─────────────────────────────────────────────────────────────────────────────────────────
# REVISÃO 2026-08-01 — a porta existia mas não abria. Dois defeitos, ambos silenciosos:
#
#  D1. FORMATO DE ID DEMASIADO ESTREITO. O guard era `^ordem-[0-9]{14}-[0-9a-fA-F]{4,}$`, que
#      só aceita o id "cru". Mas metade das ordens reais nascem COM SUFIXO — `-aprovado`
#      (aprovada na Central), `-aprovado-chat` (aprovada via claude.ai/cortex_nova_ordem). A
#      ordem-20260801100404-ffc9-aprovado-chat foi despromovida a zona_vermelha pelo carteiro no
#      pickup e QUALQUER "vai" do Danilo caía em `vai-invalido` — a ordem não tinha caminho de
#      volta nenhum, ficava presa para sempre. O bug parecia "o Telegram não chega lá"; era o
#      próprio guard a recusar o id que ele mesmo tinha mandado escrever na mensagem de aviso.
#
#  D2. O "VAI" ERA GRAVADO NUM CAMPO QUE NINGUÉM LÊ. Esta rotina escrevia `autorizado_por` +
#      `autorizado_em` e o comentário afirmava que isso persistia a autorização. Não persistia:
#      `grep -c 'autorizado_por[^_]' carteiro.sh` = 0. O carteiro só conhece DUAS portas —
#      `vai: sim` (linha 681) e o par `autorizado_por_admin`+`audit_id` revalidado contra a base
#      (linha 670). Ou seja, mesmo um "vai" com id certo abria a ordem e o ciclo seguinte
#      re-avaliava zona_vermelha(tarefa) sobre o mesmo texto e voltava a fechá-la: ping-pong
#      infinito em vez de desbloqueio. Agora grava-se `vai: sim` — o campo que o carteiro lê de
#      facto — e os campos de auditoria ficam ao lado, como registo, não como mecanismo.
#
#  + DESAMBIGUAÇÃO. Existem ordens irmãs cujo id só difere no sufixo
#    (…-ffc9-aprovado e …-ffc9-aprovado-chat). Um "vai" tem de identificar UMA ordem sem
#    dúvida: aceita-se (a) o id exacto, ou (b) um prefixo que case com EXACTAMENTE UM ficheiro.
#    Prefixo ambíguo é RECUSADO e o Danilo recebe a lista dos candidatos para repetir com o id
#    completo. Nunca se escolhe "o primeiro" — adivinhar qual ordem o humano quis libertar numa
#    barreira de dinheiro é exactamente o erro que a barreira existe para impedir.
#
#  + MODO CLI. `porta-vai.sh --vai <id> --origem <texto>` aplica o mesmo caminho, com as mesmas
#    barreiras, para autorização dada FORA do Telegram (sessão do Danilo, consola). A origem
#    fica gravada no e2e_log tal como é — nunca se regista como "telegram" o que não veio de lá.
# ─────────────────────────────────────────────────────────────────────────────────────────
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
# nem acesso a /root/orquestracao). */2 min é suficiente e barato (1 leitura incremental de
# log + greps). Ver deploy/DEPLOY.md para instruções de instalação real (root, /usr/local/bin,
# se um dia isto for promovido a produção oficial tal como o carteiro.sh).
#
# BARREIRAS DURAS (sem exceção, todas verificadas antes de qualquer escrita):
#   1) só o chat_id do Danilo é aceite — qualquer outro é IGNORADO e REGISTADO em e2e_log.
#   2) a mensagem tem de ser EXATAMENTE "vai <token>" (2 palavras) — nunca "vai tudo",
#      "desliga a barreira", nem nada com mais de 1 id.
#   3) <token> tem de bater no formato real de id de ordem (ordem-<14 digitos>-<hex>[-sufixo…])
#      E resolver para UM único ficheiro E esse ficheiro tem de estar em `estado: zona_vermelha`
#      neste preciso instante — senão é ignorado e registado, nunca aplicado às cegas.
#   4) cada uso (aceite OU rejeitado) fica em e2e_log (fluxo='vai-usado' | 'vai-rejeitado' |
#      'vai-invalido' | 'vai-estado-errado' | 'vai-ambiguo') com id da ordem, hora e origem.
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

# ── resolver_ordem: token -> UM ficheiro, ou nada ────────────────────────────────────────────
# Ecoa o caminho do ficheiro em stdout e devolve 0 se resolveu sem ambiguidade.
# rc=1 nenhum candidato · rc=2 ambíguo (lista os ids candidatos em stdout, um por linha).
# Ordem de preferência: (1) id exacto — sempre ganha, mesmo que seja prefixo de outros;
# (2) prefixo único. Nunca "o primeiro de vários".
resolver_ordem(){ # $1=token
  local tok="$1" exato cands n
  exato="$FILA/$tok.md"
  [ -f "$exato" ] && { printf '%s\n' "$exato"; return 0; }
  cands=$(ls -1 "$FILA/$tok"*.md 2>/dev/null | grep -vE '\.(bak|saida)' || true)
  n=$(printf '%s' "$cands" | grep -c . || true)
  [ "$n" -eq 0 ] && return 1
  if [ "$n" -eq 1 ]; then printf '%s\n' "$cands"; return 0; fi
  printf '%s\n' "$cands" | sed -E 's|.*/||; s|\.md$||'
  return 2
}

# ── aplicar_vai: a ÚNICA rotina que destranca uma ordem ──────────────────────────────────────
# Usada tanto pelo caminho Telegram como pelo modo CLI, para não existirem duas semânticas de
# "vai" que possam divergir com o tempo. $2=origem (texto honesto sobre de onde veio a ordem).
aplicar_vai(){ # $1=token $2=origem
  local tok="$1" origem="$2" f estado_atual oid cands

  if ! printf '%s' "$tok" | grep -qE '^ordem-[0-9]{14}-[0-9a-fA-F]{4,}(-[A-Za-z0-9]+)*$'; then
    log "IGNORADO: '$tok' (origem=$origem) nao e um id de ordem valido (bloqueia comando generico)"
    e2e_insert "vai-invalido" "$tok" "id-formato-invalido" "falhou" "origem=$origem id='$tok' nao bate no formato ordem-<timestamp>-<hex>[-sufixo]; comando generico bloqueado, nenhum efeito"
    return 1
  fi

  cands=$(resolver_ordem "$tok"); case $? in
    1) log "IGNORADO: ordem $tok nao existe em $FILA"
       e2e_insert "vai-nao-encontrado" "$tok" "ordem-inexistente" "falhou" "origem=$origem ordem=$tok ficheiro nao existe"
       return 1;;
    2) log "AMBIGUO: '$tok' casa com varias ordens -> $(printf '%s' "$cands" | tr '\n' ' ')"
       e2e_insert "vai-ambiguo" "$tok" "prefixo-ambiguo" "falhou" "origem=$origem prefixo='$tok' casa com: $(printf '%s' "$cands" | tr '\n' ' ') -- nenhuma libertada; repetir com o id completo"
       notificar "⚠️ Bora/orquestração: 'vai $tok' é AMBÍGUO — casa com mais do que uma ordem:
$(printf '%s' "$cands" | sed 's/^/• /')
Nenhuma foi libertada. Repete com o id completo."
       return 2;;
  esac
  f="$cands"; oid=$(basename "$f" .md)

  estado_atual=$(get estado "$f")
  if [ "$estado_atual" != "zona_vermelha" ]; then
    log "IGNORADO: ordem $oid estado atual='$estado_atual' (so destrava se for zona_vermelha)"
    e2e_insert "vai-estado-errado" "$oid" "estado-nao-e-zona-vermelha" "falhou" "origem=$origem ordem=$oid estado_atual=$estado_atual (esperado zona_vermelha)"
    return 1
  fi

  cp -p "$f" "$f.bak-porta-vai-$(date -u +%Y%m%d%H%M%S)"
  # ORDEM DAS ESCRITAS: `vai: sim` PRIMEIRO, `estado: aberta` DEPOIS. Se o processo morresse a
  # meio, o pior caso é uma ordem ainda fechada mas já autorizada (inofensivo) em vez de uma
  # ordem aberta sem autorização registada (que o carteiro voltaria a fechar — o ping-pong D2).
  local autorizado_em; autorizado_em=$(ts)
  setf vai sim "$f"
  setf autorizado_por "$origem" "$f"
  setf autorizado_em "$autorizado_em" "$f"
  setf nota "✅ destravada por Danilo ($origem) — vai $oid" "$f"
  setf estado aberta "$f"
  log "DESTRAVADA: ordem $oid zona_vermelha -> aberta (vai: sim; origem=$origem)"
  e2e_insert "vai-usado" "$oid" "vai-usado" "passou" "ordem=$oid origem=$origem hora=$autorizado_em estado: zona_vermelha -> aberta; vai=sim autorizado_em=$autorizado_em"
  return 0
}

notificar(){ # best-effort; nunca falha o fluxo
  docker exec -u hermes hermes-agent-fvnc-hermes-agent-1 hermes send -t telegram "$1" >/dev/null 2>&1 \
    || log "notificar(best-effort) falhou"
}

# ── MODO CLI ─────────────────────────────────────────────────────────────────────────────────
# Autorização dada fora do Telegram (sessão do Danilo/consola). Mesmas barreiras, mesma rotina;
# só a origem muda — e é gravada tal como é, para o e2e_log nunca afirmar "telegram" a mentir.
if [ "${1:-}" = "--vai" ]; then
  tok="${2:-}"; origem="${4:-cli}"
  [ "${3:-}" = "--origem" ] || origem="cli"
  [ -n "$tok" ] || { echo "uso: porta-vai.sh --vai <id-da-ordem> [--origem <texto>]"; exit 2; }
  aplicar_vai "$tok" "$origem"; rc=$?
  case $rc in
    0) echo "OK: ordem libertada (ver $LOG)";;
    2) echo "AMBIGUO: repete com o id completo (ver $LOG)";;
    *) echo "RECUSADO: ver $LOG";;
  esac
  exit $rc
fi

# ── MODO NORMAL (cron): lê o gateway.log do Telegram ─────────────────────────────────────────
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
  # de verdade é o formato+existência+estado do id, dentro de aplicar_vai.
  printf '%s' "$msg" | grep -iqE '^[[:space:]]*vai[[:space:]]+[A-Za-z0-9_-]+[[:space:]]*$' || continue
  id=$(printf '%s' "$msg" | sed -E 's/^[[:space:]]*[Vv][Aa][Ii][[:space:]]+([A-Za-z0-9_-]+)[[:space:]]*$/\1/')

  if [ "$chat" != "$DANILO_CHAT_ID" ]; then
    log "REJEITADO: chat=$chat (nao autorizado) tentou 'vai $id'"
    e2e_insert "vai-rejeitado" "$id" "chat-nao-autorizado" "falhou" "chat_id=$chat nao e o chat_id do Danilo; msg='$msg'; ignorado sem efeito"
    continue
  fi

  aplicar_vai "$id" "telegram:$chat"
done

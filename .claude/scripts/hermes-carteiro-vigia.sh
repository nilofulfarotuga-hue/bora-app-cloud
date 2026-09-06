#!/usr/bin/env bash
# --- STOP GLOBAL (reengenharia 2026-07-12): respeita .pausa-total ---
[ -f /docker/hermes-agent-fvnc/data/cortex-brain/orquestracao/.pausa-total ] && exit 0
# hermes-carteiro-vigia.sh — "vigia do carteiro": revive o PIPELINE do carteiro sozinho.
#
# INCIDENTE 2026-07-12 (que este ficheiro conserta): o carteiro parou de apanhar ordens e as
# ordens ficaram 33+ min em `aberta` tentativa=0, MAS a versão anterior deste vigia NÃO agiu —
# ela só reiniciava a campainha quando o processo inotifywait estava MORTO. Nesse dia o
# inotifywait estava VIVO (até duplicado), logo o vigia via "ordem parada + campainha viva" e
# concluía "provável tarefa pesada em curso — não reinicio". Errado por dois motivos:
#   1) O carteiro marca `estado: executando`+`tentativa>=1` no MOMENTO em que pega a ordem
#      (carteiro.sh:79). Logo uma ordem `aberta` tentativa=0 NUNCA é "tarefa pesada em curso" —
#      é uma ordem que NINGUÉM apanhou (pipeline parado).
#   2) Reiniciar o inotifywait NÃO varre ordens JÁ na fila — o inotify só dispara em escritas
#      NOVAS. Uma ordem que já lá estava fica presa até ao cron-fallback (1x/hora). Por isso a
#      6188 ficou 33 min: ninguém a varria.
#
# CONSERTO: o sinal de "pipeline parado" é a PRÓPRIA ordem estagnada — independente do
# inotifywait. Quando há ordem `aberta` estagnada (>STALL_MIN) E o carteiro NÃO está ocupado
# (lock livre E nenhuma ordem `executando`), o vigia dá um TOQUE direto no carteiro.sh (que é
# idempotente via flock — se afinal estiver ocupado, o carteiro só loga "outro a correr" e sai).
# Se o inotifywait estiver mesmo morto, reinicia a campainha (mata duplicados) E varre o backlog.
#
# ENDURECIMENTO 2026-07-17 (pedido Danilo, "a fila NUNCA pode parar por causa de UMA ordem
# presa"): até aqui `carteiro_ocupado()` só perguntava "o lock está preso OU há alguma ordem
# `executando`?" — nunca verificava se o PROCESSO DONO do lock estava mesmo vivo, só se o
# ficheiro de lock existia. Agora há um teste ÓRFÃ separado (ver "ORDEM ÓRFÃ" antes do decide()):
# se o `flock -n` consegue o lock (ninguém o detém) mas uma ordem continua em `executando`, é
# prova de que o carteiro.sh morreu a meio — a ordem é marcada `travada` de imediato (nota clara,
# tentativa preservada) e o carteiro segue já para a próxima `aberta`, sem esperar pela presa.
# Aviso Telegram dedicado por ordem travada por timeout. Ver também o CASO ZUMBI (mais abaixo),
# que cobre o caso irmão — o executor do PC morreu mas o carteiro.sh na VPS ainda está vivo,
# preso na ponte SSH — aí sim vale a pena reclamar e RETENTAR automaticamente.
#
# Corre no HOST do VPS (cron a cada 5 min). Canónico: bora_app/.claude/scripts/. Instala em
# /usr/local/bin/. Dono: Hermes(host). Ver permanente/semantica/loops.md.
#
# Uso: hermes-carteiro-vigia.sh [--dry|--selftest]
set -u

# --- config (env-overridable p/ o selftest) ---
FILA="${VIGIA_FILA:-/docker/hermes-agent-fvnc/data/cortex-brain/orquestracao}"
LOG="${VIGIA_LOG:-/root/orquestracao/carteiro-vigia.log}"
CAMPAINHA="${VIGIA_CAMPAINHA:-/root/orquestracao/campainha.sh}"
CAMPAINHA_LOG="${VIGIA_CAMPAINHA_LOG:-/root/orquestracao/campainha.log}"
CARTEIRO="${VIGIA_CARTEIRO:-/root/orquestracao/carteiro.sh}"
CARTEIRO_LOG="${VIGIA_CARTEIRO_LOG:-/root/orquestracao/carteiro.log}"
LOCK="${VIGIA_LOCK:-/root/orquestracao/.carteiro.lock}"
NOTIFIED="${VIGIA_NOTIFIED:-/root/orquestracao/.carteiro-vigia.avisado}"
NOTIFIED_FAIL="${VIGIA_NOTIFIED_FAIL:-/root/orquestracao/.carteiro-vigia.falha-avisada}"
STALL_MIN="${VIGIA_STALL_MIN:-15}"
ORFAO_MIN="${VIGIA_ORFAO_MIN:-25}"        # ver "ORDEM ÓRFÃ" abaixo (2026-07-17)
PAUSA_RL="${VIGIA_PAUSA_RL:-$FILA/.pausa-rate-limit}"
# HEARTBEAT (2026-07-17, investigação "fila trava"): o CASO 3 abaixo já provava que o carteiro
# fica genuinamente OCUPADO (lock preso, a drenar) por 1h+ várias vezes por noite — mas ficava
# em SILÊNCIO total enquanto isso (só log, nunca Telegram). Sem sinal de vida, o Danilo reinicia
# `orq-campainha.service` à mão a meio de um processamento real — o restart MATA o trabalho em
# curso (systemd KillMode padrão apanha o carteiro.sh + a ponte SSH ao PC), desperdiça a
# tentativa, e a impressão de "morreu, precisa de restart" reforça-se sozinha. Prova real
# (journalctl+carteiro-vigia.log, 2026-07-17): restarts manuais às 05:22:12 e 07:16:08 UTC
# caíram exatamente quando o vigia tinha acabado de logar "carteiro OCUPADO ... vai drenar. Não
# ajo." — não havia nada morto para reviver. 1 aviso por hora corrigido isto sem tocar na lógica
# de retomada (zero mudança de comportamento, só visibilidade).
HEARTBEAT_MIN="${VIGIA_HEARTBEAT_MIN:-60}"        # só avisa se a ordem estagnada já espera >= isto (min)
HEARTBEAT_COOLDOWN="${VIGIA_HEARTBEAT_COOLDOWN:-3600}"  # 1 aviso por hora, nunca span
HEARTBEAT_FILE="${VIGIA_HEARTBEAT_FILE:-/root/orquestracao/.carteiro-vigia.heartbeat}"
C=hermes-agent-fvnc-hermes-agent-1
# ZUMBI (2026-07-17): ordem presa em `estado: executando` mas o EXECUTOR MORREU — o caso da
# ponte/SSH pendurada DEPOIS de um FIM limpo: o stale-output-watchdog do PC não dispara (não há
# executor vivo a vigiar) e o timeout externo (14700s=4h10) só cai horas depois. Enquanto isso o
# `carteiro_ocupado` vê a ordem `executando` e mascara tudo como "a drenar" para SEMPRE. Sinal
# fiável de liveness: o `bora-live.log` no bora-pc pára de ser tocado (o parser só escreve
# enquanto o executor produz). O vigia lê esse mtime via o mesmo ssh que o pc-loop usa.
ZUMBI_MIN="${VIGIA_ZUMBI_MIN:-15}"           # idade mín. (min) de `executando` p/ ser candidato
STALE_LIVE_MIN="${VIGIA_STALE_LIVE_MIN:-12}" # bora-live.log parado >= isto (min) => executor morto
BORAPC="${VIGIA_BORAPC:-bora-pc}"            # alias ssh (config do hermes no container) p/ o PC
LIVE_LOG_PC="${VIGIA_LIVE_LOG_PC:-C:/Users/danil/Desktop/projetosflutter/bora_app/.claude/bora-live.log}"

DRY=0; SELFTEST=0
case "${1:-}" in --dry) DRY=1;; --selftest) SELFTEST=1;; esac

ts(){ date -u +%FT%TZ; }
log(){ echo "[$(ts)] $*" >> "$LOG" 2>/dev/null || echo "[$(ts)] $*"; }
get(){ grep -m1 "^$1:" "$2" 2>/dev/null | sed "s/^$1: *//" | tr -d '\r'; }

# ações — atrás de guardas: o selftest só ECOA, não toca docker/campainha/carteiro reais.
notify(){ [ "$SELFTEST" = 1 ] && { echo "[NOTIFY] $1"; return 0; }
  docker exec -u hermes "$C" hermes send -t telegram "$1" >/dev/null 2>&1 || log "notify falhou: $1"; }
nudge_carteiro(){ [ "$SELFTEST" = 1 ] && { echo "[NUDGE carteiro]"; return 0; }
  [ "$DRY" = 1 ] && { echo "DRY: nudge carteiro.sh"; return 0; }
  nohup bash "$CARTEIRO" >> "$CARTEIRO_LOG" 2>&1 & disown 2>/dev/null || true; }
restart_campainha(){ [ "$SELFTEST" = 1 ] && { echo "[RESTART campainha]"; return 0; }
  [ "$DRY" = 1 ] && { echo "DRY: restart campainha (mata duplicados + relança)"; return 0; }
  pkill -f "inotifywait.*$(basename "$FILA")" 2>/dev/null || true; sleep 1
  nohup bash "$CAMPAINHA" >> "$CAMPAINHA_LOG" 2>&1 & disown 2>/dev/null || true; sleep 1; }

# confirma_carteiro_vivo (2026-07-17, FASE 1): depois de um nudge, verifica que um carteiro
# REALMENTE arrancou (liveness). Poll curto por processo. Se nada aparecer, o nudge falhou.
# FAIL-SAFE p/ selftest: VIGIA_ASSUME_CARTEIRO_VIVO=0/1 força o resultado sem tocar em processos.
confirma_carteiro_vivo(){
  [ -n "${VIGIA_ASSUME_CARTEIRO_VIVO:-}" ] && { [ "$VIGIA_ASSUME_CARTEIRO_VIVO" = 1 ]; return; }
  [ "$SELFTEST" = 1 ] && return 0
  local i
  for i in 1 2 3 4 5; do
    pgrep -f "orquestracao/carteiro\.sh" >/dev/null 2>&1 && return 0
    sleep 1
  done
  return 1
}

campainha_viva(){
  [ -n "${VIGIA_ASSUME_VIVA:-}" ] && { [ "$VIGIA_ASSUME_VIVA" = 1 ]; return; }
  pgrep -f "inotifywait.*$(basename "$FILA")" >/dev/null 2>&1
}

# carteiro OCUPADO = lock preso OU alguma ordem `executando` (está a drenar, não é morte)
carteiro_ocupado(){
  if command -v flock >/dev/null 2>&1 && [ -e "$LOCK" ]; then
    ( flock -n 9 ) 9>>"$LOCK" 2>/dev/null || return 0   # não obteve o lock -> preso -> ocupado
  fi
  for g in "$FILA"/*.md; do
    [ -f "$g" ] || continue
    [ "$(get estado "$g")" = "executando" ] && return 0
  done
  return 1
}

# RATE-LIMIT EXPIRADA — reengenharia 2026-07-13 (ver inbox/reengenharia-loop-resiliencia-2026-07-13.md):
# o carteiro.sh só relê `.pausa-rate-limit` quando É INVOCADO de novo; mas depois de pausar por
# limite de sessão, NADA o invoca de novo sozinho — a campainha (inotify) só dispara em ESCRITA
# NOVA na fila (não há, a fila está parada) e `ordem_estagnada()` só olha `estado: aberta` (a
# ordem pausada fica em `estado: pausada-rate-limit`, nunca conta como estagnada). Resultado: a
# conta renova e a fila fica parada até o Danilo dar um toque manual. Esta função fecha o furo.
rate_limit_expirado(){
  [ -f "$PAUSA_RL" ] || return 1
  local resume now
  resume=$(tr -dc '0-9' < "$PAUSA_RL" 2>/dev/null)
  [ -n "$resume" ] || return 1
  now=$(date +%s)
  [ "$now" -ge "$resume" ]
}

# ordem ESTAGNADA = `aberta` há >= STALL_MIN (ninguém a apanhou). Independente do inotifywait.
ordem_estagnada(){
  local now g e age; now=$(date +%s)
  for g in "$FILA"/*.md; do
    [ -f "$g" ] || continue
    case "$g" in */_controlo.md) continue;; esac
    e=$(get estado "$g"); [ "$e" = "aberta" ] || continue
    age=$(( (now - $(stat -c %Y "$g")) / 60 ))
    [ "$age" -ge "$STALL_MIN" ] && { echo "$(basename "$g" .md) (${age}min, tent=$(get tentativa "$g"))"; return 0; }
  done
  return 1
}

# --- ZUMBI (2026-07-17): executor morto mas ordem presa em `executando` ----------------------
# minutos desde que o executor tocou o bora-live.log no PC (via o mesmo ssh do pc-loop). Devolve
# "" se o ssh falhar, "-1" se o ficheiro não existir. É a única leitura cara — só é chamada quando
# já existe uma ordem `executando` estagnada (não faz ssh em cada tique à toa).
live_stale_min(){
  docker exec -u hermes "$C" sh -lc "ssh -o ConnectTimeout=12 $BORAPC powershell -NoProfile -Command \"try{[int]((Get-Date)-(Get-Item $LIVE_LOG_PC).LastWriteTime).TotalMinutes}catch{-1}\"" 2>/dev/null | tr -dc '0-9-' | head -c 9
}

# executor GENUINAMENTE vivo = bora-live.log tocado há < STALE_LIVE_MIN.
# FAIL-SAFE (regra de ouro): ssh falhou / ficheiro ausente / valor não-numérico -> assume VIVO
# (return 0), para NUNCA matar um executor real por engano. Só mata com prova positiva de morte.
executor_vivo(){
  [ -n "${VIGIA_ASSUME_EXECUTOR:-}" ] && { [ "$VIGIA_ASSUME_EXECUTOR" = 1 ]; return; }
  [ "$SELFTEST" = 1 ] && return 0
  local m; m="$(live_stale_min)"
  case "$m" in ''|-*|*[!0-9-]*) return 0;; esac   # vazio / -1 / lixo -> fail-safe: VIVO
  [ "$m" -lt "$STALE_LIVE_MIN" ]                   # fresco -> vivo(0); stale -> morto(1)
}

# ordem ZUMBI = `executando` há >= ZUMBI_MIN E o executor parou de produzir (bora-live stale).
ordem_zumbi(){
  local now g age cand="" zmin="${VIGIA_ZUMBI_MIN:-$ZUMBI_MIN}"; now=$(date +%s)
  for g in "$FILA"/*.md; do
    [ -f "$g" ] || continue
    case "$g" in */_controlo.md) continue;; esac
    [ "$(get estado "$g")" = "executando" ] || continue
    age=$(( (now - $(stat -c %Y "$g")) / 60 ))
    [ "$age" -ge "$zmin" ] && { cand="$(basename "$g" .md) (${age}min)"; break; }
  done
  [ -n "$cand" ] || return 1        # nenhuma `executando` estagnada -> nada a fazer (sem ssh)
  executor_vivo && return 1         # bridge vivo e a produzir -> NÃO é zumbi
  echo "$cand"; return 0
}

# reclama a ordem zumbi: mata o carteiro bloqueado na ponte + o pc-loop/ssh pendurado no container
# (poupando os túneis tailscale persistentes), limpa o lock e repõe a ordem em `aberta` para o
# carteiro a re-apanhar (re-corre como retry de crash — o carteiro aplica a sua conta de tentativas).
reclamar_zumbi(){  # $1 = ficheiro da ordem
  local f="$1"
  [ "$SELFTEST" = 1 ] && { echo "[RECLAMA zumbi $(basename "$f" .md)]"; return 0; }
  [ "$DRY" = 1 ] && { echo "DRY: reclama zumbi $(basename "$f" .md)"; return 0; }
  pkill -f "orquestracao/carteiro\.sh" 2>/dev/null || true
  docker exec "$C" sh -lc 'P=$(pgrep -x pc-loop | head -1); [ -n "$P" ] && { pkill -TERM -P "$P" 2>/dev/null; kill -TERM "$P" 2>/dev/null; sleep 2; pkill -KILL -P "$P" 2>/dev/null; kill -KILL "$P" 2>/dev/null; }' 2>/dev/null || true
  rm -f "$LOCK" 2>/dev/null || true
  [ -f "$f" ] && sed -i 's/^estado:.*/estado: aberta/' "$f" 2>/dev/null || true
}

# --- ORDEM ÓRFÃ (2026-07-17, pedido Danilo) ---------------------------------------------------
# Diferente do ZUMBI acima (que assume o carteiro.sh ainda VIVO mas preso na ponte SSH/PC — aí o
# lock continua PRESO, por isso o reclaim mata processos e RETENTA a mesma ordem). Aqui o sinal é
# mais forte e 100% LOCAL — não depende de SSH até ao bora-pc (que pode estar em baixo e faria o
# ZUMBI falhar-aberto por "regra de ouro"): se `flock -n` CONSEGUE o lock (ninguém o detém agora)
# mas alguma ordem continua em `executando`, é PROVA — não suposição — de que o carteiro.sh que a
# marcou já morreu (o kernel só liberta um flock quando o processo dono termina ou fecha o fd).
# Não vale a pena repetir a mesma ordem às cegas (o processo pode ter morrido POR CAUSA dela) —
# marca `travada` já, preserva a `tentativa:` para quem quiser retomar à mão, avisa no Telegram
# e deixa o carteiro seguir IMEDIATAMENTE para a próxima `aberta` (nunca fica à espera da presa).
lock_livre(){
  [ -n "${VIGIA_ASSUME_LOCK_LIVRE:-}" ] && { [ "$VIGIA_ASSUME_LOCK_LIVRE" = 1 ]; return; }
  command -v flock >/dev/null 2>&1 || return 1
  ( flock -n 9 ) 9>>"$LOCK" 2>/dev/null
}

# ordem ÓRFÃ = `executando` há >= ORFAO_MIN E o lock está LIVRE (ninguém o detém agora).
ordem_executando_orfa(){
  local now g age cand="" omin="${VIGIA_ORFAO_MIN:-$ORFAO_MIN}"
  now=$(date +%s)
  lock_livre || return 1        # lock preso -> dono ainda vivo -> não é órfã (é o caso ZUMBI)
  for g in "$FILA"/*.md; do
    [ -f "$g" ] || continue
    case "$g" in */_controlo.md) continue;; esac
    [ "$(get estado "$g")" = "executando" ] || continue
    age=$(( (now - $(stat -c %Y "$g")) / 60 ))
    [ "$age" -ge "$omin" ] && { cand="$(basename "$g" .md) (${age}min, tent=$(get tentativa "$g"))"; break; }
  done
  [ -n "$cand" ] || return 1
  echo "$cand"; return 0
}

# marca a ordem TRAVADA (não retenta às cegas). Preserva `tentativa:` tal como está — pedido
# explícito do Danilo, quem retomar à mão sabe quantas vezes já foi tentada. Também trunca o
# ficheiro de lock: não é preciso para o flock em si (o kernel já libertou), mas limpa qualquer
# resíduo visível, como pedido ("o vigia tem de limpar o lock sozinho").
marcar_travada_orfa(){  # $1 = ficheiro da ordem
  local f="$1" tent
  tent="$(get tentativa "$f")"
  [ "$SELFTEST" = 1 ] && { echo "[TRAVADA-ORFA $(basename "$f" .md)]"; return 0; }
  [ "$DRY" = 1 ] && { echo "DRY: marca travada-orfa $(basename "$f" .md)"; return 0; }
  sed -i 's/^estado:.*/estado: travada/' "$f" 2>/dev/null || true
  if grep -qE '^nota:' "$f"; then
    sed -i "s|^nota:.*|nota: 🪦 ÓRFÃ — processo dono morreu sem concluir, tentativa ${tent} preservada para retomar|" "$f"
  else
    printf 'nota: 🪦 ÓRFÃ — processo dono morreu sem concluir, tentativa %s preservada para retomar\n' "$tent" >> "$f"
  fi
  : > "$LOCK" 2>/dev/null || true
}

# heartbeat de visibilidade (2026-07-17): $1 = "$estag" (formato "id (Nmin, tent=X)"). Só entra
# no CASO 3 (carteiro genuinamente ocupado, não morto) — nunca substitui os reclaims ZUMBI/ÓRFÃ
# acima, que continuam a agir primeiro quando há prova de morte. Aqui não há prova de morte
# nenhuma, só demora — o aviso existe para o Danilo NÃO reiniciar à cegas um processo vivo.
heartbeat_ocupado(){
  local estag="$1" mins hnow hlast
  mins=$(printf '%s' "$estag" | grep -oE '\([0-9]+min' | grep -oE '[0-9]+')
  [ -n "$mins" ] && [ "$mins" -ge "$HEARTBEAT_MIN" ] || return 0
  [ "$SELFTEST" = 1 ] && { echo "[HEARTBEAT ${mins}min]"; return 0; }
  [ "$DRY" = 1 ] && { echo "DRY: heartbeat ${mins}min"; return 0; }
  hnow=$(date +%s); hlast=$(cat "$HEARTBEAT_FILE" 2>/dev/null || echo 0)
  [ $(( hnow - hlast )) -ge "$HEARTBEAT_COOLDOWN" ] || return 0
  notify "⏳ Bora/carteiro: VIVO e a trabalhar (fila com espera, ordem $estag) — não é falha, não precisas reiniciar. Reiniciar agora perderia o trabalho em curso."
  echo "$hnow" > "$HEARTBEAT_FILE" 2>/dev/null || true
}

decide(){
  local viva=0 estag ocup=0
  campainha_viva && viva=1
  estag="$(ordem_estagnada || true)"
  carteiro_ocupado && ocup=1

  # CASO 1 — campainha MORTA: reinicia (mata duplicados) E varre o backlog que ela perdeu.
  if [ "$viva" = 0 ]; then
    log "MORTA: inotifywait ausente -> reinicio campainha + varro backlog (estagnada: ${estag:-nenhuma})"
    restart_campainha
    nudge_carteiro
    if campainha_viva || [ "$SELFTEST" = 1 ]; then
      [ -f "$NOTIFIED" ] || { notify "🔄 Bora/carteiro: a campainha tinha morrido — revivi-a e varri a fila sozinho."; touch "$NOTIFIED" 2>/dev/null || true; }
    else
      notify "⛔ Bora/carteiro: a campainha morreu e NÃO consegui revivê-la. Precisa de ti."
    fi
    return 0
  fi

  # CASO 1.5 — pausa por rate-limit já EXPIROU e o carteiro está LIVRE: dá o toque para retomar
  # sozinho. O carteiro.sh (idempotente) relê `.pausa-rate-limit`, vê que já passou, limpa-a e
  # segue o ciclo normal. Furo de 2026-07-13 fechado (ver reate_limit_expirado acima).
  if rate_limit_expirado && [ "$ocup" = 0 ]; then
    log "RATE-LIMIT EXPIROU: $PAUSA_RL já passou e carteiro LIVRE -> NUDGE (retoma sozinho, sem Danilo)"
    nudge_carteiro
    [ -f "$NOTIFIED" ] || { notify "🔄 Bora/carteiro: o limite de sessão do Claude já renovou — retomei a fila sozinho, sem esperar por ti."; touch "$NOTIFIED" 2>/dev/null || true; }
    return 0
  fi

  # CASO ÓRFÃ (2026-07-17) — checagem LOCAL, corre antes do ZUMBI (que depende de SSH ao bora-pc):
  # ordem `executando` há >= ORFAO_MIN com o lock genuinamente LIVRE = o carteiro.sh que a
  # marcou já morreu. Marca travada, avisa, e o NUDGE seguinte já processa a próxima `aberta`.
  local orfa oid ofile resumo
  orfa="$(ordem_executando_orfa || true)"
  if [ -n "$orfa" ]; then
    oid="${orfa%% *}"; ofile="$FILA/$oid.md"
    resumo="$(get tarefa "$ofile" | cut -c1-140)"
    log "ÓRFÃ: ordem $orfa em 'executando' com o lock LIVRE (processo dono morreu) -> marco travada e sigo para a próxima."
    marcar_travada_orfa "$ofile"
    nudge_carteiro
    notify "⛔ Bora/carteiro: Ordem $oid travada por timeout - fila avancou para a proxima. ${resumo:-(sem resumo)}"
    return 0
  fi

  # CASO ZUMBI (2026-07-17) — ordem presa em `executando` mas o executor MORREU (ponte pendurada
  # após FIM limpo). Sem isto, `carteiro_ocupado` vê a ordem `executando` e o CASO 3 mascara-a como
  # "a drenar" para sempre — a fila fica parada até ao timeout externo de 4h. Reclama: mata a ponte,
  # limpa o lock, repõe `aberta` e dá o toque. Só age com PROVA de morte (bora-live stale); se o
  # bora-pc estiver inalcançável, `executor_vivo` assume vivo e isto NÃO dispara (rede 4h trata).
  local zumbi zfile
  zumbi="$(ordem_zumbi || true)"
  if [ -n "$zumbi" ]; then
    zfile="$FILA/${zumbi%% *}.md"
    log "ZUMBI: ordem $zumbi presa em 'executando' com o executor parado (bora-live stale) -> mato ponte/pc-loop, limpo lock, reponho 'aberta' e NUDGE."
    reclamar_zumbi "$zfile"
    nudge_carteiro
    # 2026-07-17 (FASE 1): confirmar que a ressurreição PEGOU. Se o carteiro não voltou a
    # arrancar, o nudge falhou (provável ponte partida) -> alerta REAL ao Danilo, não "sucesso".
    if confirma_carteiro_vivo; then
      log "ZUMBI: carteiro RESSUSCITADO e vivo após reclaim de $zumbi."
      rm -f "$NOTIFIED_FAIL" 2>/dev/null || true
      [ -f "$NOTIFIED" ] || { notify "🧟 Bora/carteiro: uma ordem ficou presa em 'executando' com o executor morto (ponte pendurada) — limpei o zombie e retomei a fila sozinho ($zumbi)."; touch "$NOTIFIED" 2>/dev/null || true; }
    else
      log "ZUMBI: FALHA — reclamei $zumbi mas o carteiro NÃO voltou a arrancar (nudge sem processo vivo)."
      [ -f "$NOTIFIED_FAIL" ] || { notify "⛔ Bora/carteiro: reclamei um zombie ($zumbi) mas o carteiro NÃO voltou a arrancar sozinho. A ponte para o PC pode estar partida — precisa de ti."; touch "$NOTIFIED_FAIL" 2>/dev/null || true; }
    fi
    return 0
  fi

  # CASO 2 — campainha viva MAS ordem estagnada E carteiro livre: ESTE era o furo de 2026-07-12.
  # Pipeline parado com campainha "viva". Toque direto no carteiro (varre a fila já).
  if [ -n "$estag" ] && [ "$ocup" = 0 ]; then
    log "ESTAGNADO: campainha viva, carteiro LIVRE, ordem parada ($estag) -> NUDGE carteiro.sh (furo 2026-07-12 fechado)"
    nudge_carteiro
    [ -f "$NOTIFIED" ] || { notify "🔄 Bora/carteiro: a fila estava parada (ordem $estag) e o carteiro livre — dei-lhe um toque para retomar."; touch "$NOTIFIED" 2>/dev/null || true; }
    return 0
  fi

  # CASO 3 — saudável: sem estagnada, OU carteiro OCUPADO (a drenar). Não age.
  if [ -n "$estag" ] && [ "$ocup" = 1 ]; then
    log "OK: ordem parada ($estag) mas carteiro OCUPADO (executando/lock preso) — vai drenar. Não ajo."
    heartbeat_ocupado "$estag"
  else
    log "OK: campainha viva, sem ordens estagnadas."
    rm -f "$NOTIFIED_FAIL" 2>/dev/null || true
  fi
  rm -f "$NOTIFIED" 2>/dev/null || true
  return 0
}

# --- selftest (headless: fila temporária, ações só ecoam) --------------------
selftest(){
  local tmp; tmp=$(mktemp -d); local ok=0 fail=0
  # STALL_MIN=0 -> qualquer ordem `aberta` conta como estagnada, sem depender do relógio/mtime
  # (o limiar de idade é aritmética trivial; o que se testa aqui é a DECISÃO). Sobrescrevo os
  # globais JÁ resolvidos (o topo do script fixa-os antes daqui) para apontar à fila temporária.
  FILA="$tmp"; LOG="$tmp/vigia.log"; LOCK="$tmp/.lock"; STALL_MIN=0; PAUSA_RL="$tmp/.pausa-rate-limit"
  NOTIFIED="$tmp/.avisado"; NOTIFIED_FAIL="$tmp/.falha-avisada"
  chk(){ if eval "$2"; then echo "  [OK] $1"; ok=$((ok+1)); else echo "  [X ] $1"; fail=$((fail+1)); fi; }
  mkstuck(){ printf 'id: %s\nestado: aberta\ntentativa: 0\ntarefa: x\n' "$1" > "$tmp/$1.md"; }

  echo "== T1: REGRESSÃO — campainha VIVA + ordem aberta 20min + carteiro LIVRE -> NUDGE (antes NÃO agia) =="
  mkstuck ordem-stuck1
  out=$(VIGIA_ASSUME_VIVA=1 SELFTEST=1 decide 2>&1)
  chk "decidiu NUDGE carteiro (furo fechado)" 'echo "$out" | grep -q "\[NUDGE carteiro\]"'

  echo "== T2: campainha viva + ordem parada MAS carteiro OCUPADO (executando) -> NÃO age =="
  printf 'id: exec1\nestado: executando\ntentativa: 1\ntarefa: y\n' > "$tmp/exec1.md"
  out=$(VIGIA_ASSUME_VIVA=1 SELFTEST=1 decide 2>&1)
  chk "não deu nudge (carteiro a drenar)" '! echo "$out" | grep -q "\[NUDGE carteiro\]"'
  rm -f "$tmp/exec1.md"

  echo "== T3: campainha MORTA -> reinicia campainha E varre backlog =="
  out=$(VIGIA_ASSUME_VIVA=0 SELFTEST=1 decide 2>&1)
  chk "reiniciou campainha" 'echo "$out" | grep -q "\[RESTART campainha\]"'
  chk "varreu backlog (nudge)" 'echo "$out" | grep -q "\[NUDGE carteiro\]"'

  echo "== T4: sem ordens estagnadas + campainha viva -> OK, não age =="
  rm -f "$tmp"/ordem-stuck1.md
  out=$(VIGIA_ASSUME_VIVA=1 SELFTEST=1 decide 2>&1)
  chk "silencioso (nenhuma ação)" '! echo "$out" | grep -qE "\[NUDGE|\[RESTART"'

  echo "== T5: REGRESSÃO 2026-07-13 — pausa-rate-limit EXPIRADA (epoch passado) + carteiro LIVRE -> NUDGE (fecha furo: quota renovou e nada retomava sozinho) =="
  echo $(( $(date +%s) - 60 )) > "$tmp/.pausa-rate-limit"
  out=$(VIGIA_ASSUME_VIVA=1 SELFTEST=1 decide 2>&1)
  chk "decidiu NUDGE (rate-limit expirou, retomou sozinho)" 'echo "$out" | grep -q "\[NUDGE carteiro\]"'
  rm -f "$tmp/.pausa-rate-limit"

  echo "== T6: pausa-rate-limit AINDA NO FUTURO -> NÃO nudge (respeita a pausa, não gasta tentativa à toa) =="
  echo $(( $(date +%s) + 3600 )) > "$tmp/.pausa-rate-limit"
  out=$(VIGIA_ASSUME_VIVA=1 SELFTEST=1 decide 2>&1)
  chk "não deu nudge (pausa ainda válida)" '! echo "$out" | grep -q "\[NUDGE carteiro\]"'
  rm -f "$tmp/.pausa-rate-limit"

  echo "== T7: ZUMBI 2026-07-17 — ordem 'executando' + executor MORTO (bora-live stale) + idade>=ZUMBI_MIN -> RECLAMA + NUDGE =="
  printf 'id: zmb1\nestado: executando\ntentativa: 2\ntarefa: z\n' > "$tmp/zmb1.md"
  out=$(VIGIA_ASSUME_VIVA=1 VIGIA_ASSUME_EXECUTOR=0 VIGIA_ZUMBI_MIN=0 SELFTEST=1 decide 2>&1)
  chk "reclamou o zombie" 'echo "$out" | grep -q "\[RECLAMA zumbi zmb1\]"'
  chk "e deu o toque (nudge)" 'echo "$out" | grep -q "\[NUDGE carteiro\]"'
  rm -f "$tmp/zmb1.md"

  echo "== T8: ordem 'executando' MAS executor VIVO (bora-live fresco) -> NÃO reclama (drenagem real) =="
  printf 'id: zmb2\nestado: executando\ntentativa: 2\ntarefa: z\n' > "$tmp/zmb2.md"
  out=$(VIGIA_ASSUME_VIVA=1 VIGIA_ASSUME_EXECUTOR=1 VIGIA_ZUMBI_MIN=0 SELFTEST=1 decide 2>&1)
  chk "não reclamou (executor vivo => fail-safe)" '! echo "$out" | grep -q "\[RECLAMA zumbi"'
  rm -f "$tmp/zmb2.md"

  echo "== T9: ordem 'executando' recente (idade<ZUMBI_MIN) -> NÃO reclama (janela de arranque do executor) =="
  printf 'id: zmb3\nestado: executando\ntentativa: 2\ntarefa: z\n' > "$tmp/zmb3.md"
  out=$(VIGIA_ASSUME_VIVA=1 VIGIA_ASSUME_EXECUTOR=0 VIGIA_ZUMBI_MIN=999 SELFTEST=1 decide 2>&1)
  chk "não reclamou (ordem recente, dentro da grace)" '! echo "$out" | grep -q "\[RECLAMA zumbi"'
  rm -f "$tmp/zmb3.md"

  echo "== T10: ZUMBI (FASE 1) — reclamado MAS carteiro NÃO ressuscita (nudge falhou) -> ALERTA de FALHA, não 'sucesso' =="
  rm -f "$NOTIFIED" "$NOTIFIED_FAIL" 2>/dev/null
  printf 'id: zmb4\nestado: executando\ntentativa: 2\ntarefa: z\n' > "$tmp/zmb4.md"
  out=$(VIGIA_ASSUME_VIVA=1 VIGIA_ASSUME_EXECUTOR=0 VIGIA_ZUMBI_MIN=0 VIGIA_ASSUME_CARTEIRO_VIVO=0 SELFTEST=1 decide 2>&1)
  chk "reclamou o zombie" 'echo "$out" | grep -q "\[RECLAMA zumbi zmb4\]"'
  chk "alertou FALHA (carteiro não voltou a arrancar)" 'echo "$out" | grep -q "NÃO voltou a arrancar"'
  chk "NÃO mandou msg de sucesso" '! echo "$out" | grep -q "retomei a fila sozinho"'
  rm -f "$tmp/zmb4.md"

  echo "== T11: ZUMBI reclamado E carteiro ressuscita (nudge pegou) -> msg de SUCESSO, sem alerta de falha =="
  rm -f "$NOTIFIED" "$NOTIFIED_FAIL" 2>/dev/null
  printf 'id: zmb5\nestado: executando\ntentativa: 2\ntarefa: z\n' > "$tmp/zmb5.md"
  out=$(VIGIA_ASSUME_VIVA=1 VIGIA_ASSUME_EXECUTOR=0 VIGIA_ZUMBI_MIN=0 VIGIA_ASSUME_CARTEIRO_VIVO=1 SELFTEST=1 decide 2>&1)
  chk "mandou sucesso (retomei a fila)" 'echo "$out" | grep -q "retomei a fila sozinho"'
  chk "NÃO alertou falha" '! echo "$out" | grep -q "NÃO voltou a arrancar"'
  rm -f "$tmp/zmb5.md"

  echo "== T12: ÓRFÃ 2026-07-17 — ordem 'executando' + LOCK REALMENTE LIVRE (flock genuíno contra"
  echo "== ficheiro de lock de verdade, ninguém o detém) -> TRAVADA de imediato + NUDGE p/ a próxima =="
  rm -f "$NOTIFIED" "$NOTIFIED_FAIL" 2>/dev/null
  printf 'id: orf1\nestado: executando\ntentativa: 3\ntarefa: tarefa de teste orfa\n' > "$tmp/orf1.md"
  out=$(VIGIA_ASSUME_VIVA=1 VIGIA_ORFAO_MIN=0 SELFTEST=1 decide 2>&1)
  chk "marcou travada-orfa (prova real: flock não-simulado)" 'echo "$out" | grep -q "\[TRAVADA-ORFA orf1\]"'
  chk "deu o toque (nudge) — fila avança para a próxima" 'echo "$out" | grep -q "\[NUDGE carteiro\]"'
  rm -f "$tmp/orf1.md"

  echo "== T13: ÓRFÃ mas idade < ORFAO_MIN -> NÃO marca (ainda dentro da janela de graça) =="
  printf 'id: orf2\nestado: executando\ntentativa: 1\ntarefa: z\n' > "$tmp/orf2.md"
  out=$(VIGIA_ASSUME_VIVA=1 VIGIA_ORFAO_MIN=999 SELFTEST=1 decide 2>&1)
  chk "não marcou (idade insuficiente)" '! echo "$out" | grep -q "\[TRAVADA-ORFA"'
  rm -f "$tmp/orf2.md"

  echo "== T14: lock REALMENTE OCUPADO (segurado por outro processo, flock genuíno) -> NÃO marca"
  echo "== órfã — dono ainda vivo, é o caso ZUMBI (SSH ao bora-pc) que trata este cenário =="
  ( flock 9; sleep 4 ) 9>"$tmp/.lock" &
  heldpid=$!
  sleep 0.3
  printf 'id: orf3\nestado: executando\ntentativa: 1\ntarefa: z\n' > "$tmp/orf3.md"
  out=$(VIGIA_ASSUME_VIVA=1 VIGIA_ORFAO_MIN=0 VIGIA_ASSUME_EXECUTOR=1 SELFTEST=1 decide 2>&1)
  chk "não marcou órfã (lock genuinamente preso por outro processo)" '! echo "$out" | grep -q "\[TRAVADA-ORFA"'
  wait "$heldpid" 2>/dev/null
  rm -f "$tmp/orf3.md"

  rm -rf "$tmp"
  echo "-- selftest vigia: $ok OK, $fail FALHAS --"
  [ "$fail" = 0 ]
}

# --- main --------------------------------------------------------------------
if [ "$SELFTEST" = 1 ]; then selftest; exit $?; fi
mkdir -p "$(dirname "$LOG")" 2>/dev/null || true
decide
exit 0

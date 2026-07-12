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
STALL_MIN="${VIGIA_STALL_MIN:-15}"
C=hermes-agent-fvnc-hermes-agent-1

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
  else
    log "OK: campainha viva, sem ordens estagnadas."
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
  FILA="$tmp"; LOG="$tmp/vigia.log"; LOCK="$tmp/.lock"; STALL_MIN=0
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

  rm -rf "$tmp"
  echo "-- selftest vigia: $ok OK, $fail FALHAS --"
  [ "$fail" = 0 ]
}

# --- main --------------------------------------------------------------------
if [ "$SELFTEST" = 1 ]; then selftest; exit $?; fi
mkdir -p "$(dirname "$LOG")" 2>/dev/null || true
decide
exit 0

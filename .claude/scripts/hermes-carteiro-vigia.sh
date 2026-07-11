#!/usr/bin/env bash
# hermes-carteiro-vigia.sh — "vigia do vigia": revive o carteiro sozinho quando ele morre.
#
# Diferença para o Watchdog Hermes (que SÓ AVISA, nunca age): este script AGE. Tem de ser
# simples e INDEPENDENTE do carteiro/campainha — corre pelo cron do HOST (não por dentro do
# container, não depende do inotify estar vivo). Se este próprio script falhar, o próximo
# tick do cron (5 min depois) tenta de novo — não há estado que o deixe preso.
#
# Corre no HOST do VPS (cron a cada 5 min).
#
# Vivo = OU (a) o processo inotifywait da campainha está de pé, OU (b) não há nenhuma ordem
# 'aberta' com tentativa=0 parada há >15 min (sinal de que ninguém está a apanhar ordens).
# Morto = falha (a) E existe pelo menos uma ordem no caso (b) — só aí reinicia, para não
# reiniciar a campainha à toa quando ela só está a demorar por causa de uma ordem pesada
# a demorar dentro do timeout normal (isso é o carteiro.sh, não a campainha, que trata).
#
# Canónico no repo: bora_app/.claude/scripts/. Instalado em /usr/local/bin/ no VPS.
# Registado em permanente/semantica/loops.md (🟢 Core). Dono: Hermes(host).
#
# Uso: hermes-carteiro-vigia.sh [--dry]
set -u

DRY=0; [ "${1:-}" = "--dry" ] && DRY=1

FILA=/docker/hermes-agent-fvnc/data/cortex-brain/orquestracao
LOG=/root/orquestracao/carteiro-vigia.log
CAMPAINHA=/root/orquestracao/campainha.sh
CAMPAINHA_LOG=/root/orquestracao/campainha.log
NOTIFIED=/root/orquestracao/.carteiro-vigia.avisado   # dedupe: só avisa 1x por episódio de morte
C=hermes-agent-fvnc-hermes-agent-1

ts(){ date -u +%FT%TZ; }
log(){ echo "[$(ts)] $*" >> "$LOG"; }
notify(){ docker exec -u hermes "$C" hermes send -t telegram "$1" >/dev/null 2>&1 || log "notify falhou: $1"; }

campainha_viva(){ pgrep -f "inotifywait.*orquestracao" >/dev/null 2>&1; }

ordem_parada_15min(){
  now=$(date +%s)
  for f in "$FILA"/ordem-*.md; do
    [ -f "$f" ] || continue
    e=$(grep -m1 '^estado:' "$f" | sed 's/estado: *//' | tr -d '\r')
    t=$(grep -m1 '^tentativa:' "$f" | sed 's/tentativa: *//' | tr -d '\r')
    [ "$e" = "aberta" ] && [ "${t:-0}" = "0" ] || continue
    ageh=$(( (now - $(stat -c %Y "$f")) / 60 ))
    [ "$ageh" -ge 15 ] && { echo "$(basename "$f" .md) (${ageh}min)"; return 0; }
  done
  return 1
}

viva=0; campainha_viva && viva=1
presa=""; presa=$(ordem_parada_15min) || true

if [ "$viva" = 1 ] && [ -z "$presa" ]; then
  log "OK: campainha viva, sem ordens 'aberta' tentativa=0 paradas >15min"
  rm -f "$NOTIFIED"
  exit 0
fi

# só reinicia quando a campainha está realmente morta E há ordem parada à espera dela
if [ "$viva" = 1 ]; then
  log "campainha viva mas ordem parada ($presa) — provável tarefa pesada em curso, não é morte do carteiro. Não reinicio."
  exit 0
fi

log "MORTA: campainha não está viva (inotifywait ausente) — ordem parada: ${presa:-nenhuma ainda, mas vou reviver por precaução}"

if [ "$DRY" = 1 ]; then
  echo "DRY: REVIVERIA a campainha agora (estava morta)"
  exit 0
fi

nohup bash "$CAMPAINHA" >> "$CAMPAINHA_LOG" 2>&1 &
disown 2>/dev/null || true
sleep 1
campainha_viva && ok=1 || ok=0

if [ "$ok" = 1 ]; then
  log "REVIVIDA: campainha reiniciada com sucesso (pid novo)"
  if [ ! -f "$NOTIFIED" ]; then
    notify "🔄 Bora/carteiro: a campainha (ponte) tinha morrido — revivi-a sozinho agora. Ordens voltam a ser apanhadas na hora."
    touch "$NOTIFIED"
  fi
else
  log "FALHOU reviver a campainha — precisa de olhar humano"
  notify "⛔ Bora/carteiro: a campainha morreu e NÃO consegui revivê-la sozinho. Precisa de ti."
fi

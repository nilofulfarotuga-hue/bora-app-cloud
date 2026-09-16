#!/bin/bash
# VIGIA DA APP STORE EM PORTUGAL — corre na VPS de hora a hora (cron root).
# Missão ios-portugal-2026-09-16. Lê o lookup público da Apple para PT; quando
# resultCount passar a 1, grita no Telegram (gritar.sh) e desliga-se sozinho:
# marca o ficheiro .done e tira a própria linha do cron.
#
#   /opt/data/scripts/vigia-apple-pt.sh            # ronda normal
#   /opt/data/scripts/vigia-apple-pt.sh --teste    # manda um Telegram de teste com os números de agora
#
# Prova de que correu: /opt/data/vigia-apple-pt.log (uma linha por ronda) e
# /opt/data/social/log.md (o que gritar.sh registou). O exit 0 não é prova.
set -u
APPID=6809954739
LOG=/opt/data/vigia-apple-pt.log
DONE=/opt/data/vigia-apple-pt.done
LINK="https://apps.apple.com/pt/app/id$APPID"
GRITAR=/opt/data/scripts/gritar.sh
ts(){ date -u +%FT%TZ; }
MODO="${1:-}"

if [ -f "$DONE" ] && [ "$MODO" != "--teste" ]; then
  echo "$(ts) ja avisado ($DONE existe); nada a fazer" >> "$LOG"; exit 0
fi

N=$(curl -s --max-time 30 "https://itunes.apple.com/lookup?id=$APPID&country=pt" | jq -r '.resultCount // "erro"' 2>/dev/null || echo erro)
BR=$(curl -s --max-time 30 "https://itunes.apple.com/lookup?id=$APPID&country=br" | jq -r '.resultCount // "erro"' 2>/dev/null || echo erro)
HTTP=$(curl -s -o /dev/null -w '%{http_code}' --max-time 30 "$LINK" || echo 000)
echo "$(ts) pt=$N br=$BR http_pt=$HTTP modo=${MODO:-normal}" >> "$LOG"

if [ "$MODO" = "--teste" ]; then
  "$GRITAR" "TESTE do vigia da App Store (ios-portugal): agora pt=$N br=$BR pagina_pt=$HTTP. Quando pt passar a 1 aviso: A Bora ja esta na App Store em Portugal $LINK" \
    && echo "$(ts) teste enviado" >> "$LOG" || echo "$(ts) teste FALHOU no gritar" >> "$LOG"
  exit 0
fi

if [ "$N" = "1" ]; then
  if "$GRITAR" "A Bora já está na App Store em Portugal: $LINK"; then
    echo "$(ts) AVISADO - Portugal aberto (pt=1, http=$HTTP)" >> "$LOG"
    touch "$DONE"
    crontab -l 2>/dev/null | grep -v 'vigia-apple-pt.sh' | crontab - && echo "$(ts) linha do cron removida" >> "$LOG"
  else
    echo "$(ts) pt=1 mas o gritar FALHOU; tenta na proxima hora" >> "$LOG"
  fi
fi
exit 0

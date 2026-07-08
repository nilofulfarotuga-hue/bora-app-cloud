#!/bin/bash
# campainha.sh — gatilho EVENT-DRIVEN (inotify) do loop. NÃO é polling.
# Observa a fila; quando aparece/atualiza uma ordem .md, acorda o carteiro (debounced).
FILA=/docker/hermes-agent-fvnc/data/cortex-brain/orquestracao
LOG=/root/orquestracao/campainha.log
mkdir -p "$FILA" /root/orquestracao
echo "[$(date -u +%FT%TZ)] campainha ON, a observar $FILA" >> "$LOG"
inotifywait -m -e create -e moved_to -e close_write --format '%f' "$FILA" 2>>"$LOG" | while read -r f; do
  case "$f" in
    _controlo.md|*.saida.txt) continue;;
    *.md)
      echo "[$(date -u +%FT%TZ)] evento em $f -> carteiro" >> "$LOG"
      sleep 2   # debounce: deixa a escrita assentar; o flock do carteiro serializa
      bash /root/orquestracao/carteiro.sh >> "$LOG" 2>&1
      ;;
  esac
done

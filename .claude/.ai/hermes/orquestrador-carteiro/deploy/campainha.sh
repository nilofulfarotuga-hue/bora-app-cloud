#!/bin/bash
# campainha.sh — gatilho EVENT-DRIVEN (inotify) do loop. NÃO é polling.
# Observa a fila; quando aparece/atualiza uma ordem .md, acorda o carteiro.
#
# 2026-07-12 (reengenharia):
#   • respeita .pausa-total (STOP global) — evento ignorado enquanto a pausa estiver ativa.
#   • coalesce rajadas: no máx. 1 carteiro por MIN_INTERVAL(8s). O carteiro varre a fila TODA a
#     cada corrida, logo coalescer não perde ordens; corta só o spam "outro carteiro a correr".
#     Rede de segurança para um evento raro coalescido: o carteiro-vigia (cron */5) apanha
#     qualquer ordem `aberta` estagnada em ≤5 min, e o orq-fallback (cron horário) fecha o resto.
FILA=/docker/hermes-agent-fvnc/data/cortex-brain/orquestracao
LOG=/root/orquestracao/campainha.log
PAUSA_TOTAL="$FILA/.pausa-total"
LAST=/root/orquestracao/.campainha.last_run
MIN_INTERVAL=8
mkdir -p "$FILA" /root/orquestracao
echo "[$(date -u +%FT%TZ)] campainha ON, a observar $FILA" >> "$LOG"
inotifywait -m -e create -e moved_to -e close_write --format '%f' "$FILA" 2>>"$LOG" | while read -r f; do
  case "$f" in
    _controlo.md|*.saida.txt|.*) continue;;
    *.md)
      if [ -f "$PAUSA_TOTAL" ]; then
        echo "[$(date -u +%FT%TZ)] evento em $f mas .pausa-total ativa -> ignoro" >> "$LOG"; continue
      fi
      now=$(date +%s); last=$(cat "$LAST" 2>/dev/null || echo 0)
      if [ $((now-last)) -lt "$MIN_INTERVAL" ]; then
        echo "[$(date -u +%FT%TZ)] evento em $f coalescido (carteiro há <${MIN_INTERVAL}s)" >> "$LOG"; continue
      fi
      echo "[$(date -u +%FT%TZ)] evento em $f -> carteiro" >> "$LOG"
      sleep 2   # debounce: deixa a escrita assentar; o flock do carteiro serializa
      date +%s > "$LAST"
      bash /root/orquestracao/carteiro.sh >> "$LOG" 2>&1
      ;;
  esac
done

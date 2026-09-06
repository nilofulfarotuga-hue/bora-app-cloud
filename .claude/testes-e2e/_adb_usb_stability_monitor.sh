#!/bin/bash
# Monitoriza estabilidade adb/USB por 30 min (poll 30s). Log de quedas/mudancas de estado.
LOG="C:/Users/danil/Desktop/projetosflutter/bora_app/.claude/testes-e2e/_adb_usb_stability_monitor.log"
> "$LOG"
DEVICES=("N75LTG5X5DSKDMV4" "RZGYB1XQD2P")
declare -A LAST_STATE
for d in "${DEVICES[@]}"; do LAST_STATE[$d]=""; done
DROPS=0
START=$(date +%s)
END=$((START + 1800))
echo "inicio=$(date -u +%Y-%m-%dT%H:%M:%SZ)" >> "$LOG"
while [ "$(date +%s)" -lt "$END" ]; do
  TS=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  OUT=$(adb devices 2>&1)
  for d in "${DEVICES[@]}"; do
    STATE=$(echo "$OUT" | grep "^$d" | awk '{print $2}')
    if [ -z "$STATE" ]; then STATE="ausente"; fi
    if [ "$STATE" != "${LAST_STATE[$d]}" ]; then
      if [ -n "${LAST_STATE[$d]}" ]; then
        echo "$TS MUDANCA $d: ${LAST_STATE[$d]} -> $STATE" >> "$LOG"
        if [ "$STATE" != "device" ]; then DROPS=$((DROPS+1)); fi
      else
        echo "$TS ESTADO_INICIAL $d: $STATE" >> "$LOG"
      fi
      LAST_STATE[$d]=$STATE
    fi
  done
  sleep 30
done
echo "fim=$(date -u +%Y-%m-%dT%H:%M:%SZ)" >> "$LOG"
echo "total_quedas=$DROPS" >> "$LOG"

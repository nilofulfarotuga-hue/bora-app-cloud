#!/usr/bin/env bash
# run-loop.sh — motor de resposta de email em loop (o container NÃO tem cron).
# flock garante uma só instância. NÃO é iniciado automaticamente: o Danilo arranca-o
# depois de (1) injetar as app passwords e (2) validar em --dry-run.
#
# Arrancar (dentro do container, como hermes):
#   nohup /opt/data/hermes/socio-ai/run-loop.sh >> /opt/data/logs/email-loop.log 2>&1 &
#
# Parar:
#   pkill -f run-loop.sh
set -euo pipefail

INTERVAL="${EMAIL_LOOP_INTERVAL:-420}"   # 7 min por defeito (entre os 5-10 do plano)
LOCK="/opt/data/.email-loop.lock"
ENGINE="/opt/data/hermes/socio-ai/email_autoresponder.py"

exec 9>"$LOCK"
if ! flock -n 9; then
  echo "$(date -Is) outra instância já corre — saio." >&2
  exit 0
fi

echo "$(date -Is) loop iniciado (intervalo ${INTERVAL}s)"
while true; do
  # o engine decide sozinho se envia (respeita ENABLED + SAFETY_HOLD + dry-run)
  python3 "$ENGINE" || echo "$(date -Is) engine saiu com erro (continuo)" >&2
  sleep "$INTERVAL"
done

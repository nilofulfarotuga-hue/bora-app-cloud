#!/bin/bash
# Espera que o gateway antigo (que recebeu SIGTERM) acabe a sessao em curso e arranca um novo,
# para carregar a OMNIROUTE_API_KEY. Ate 15 min; depois disso substitui (--replace).
C=hermes-agent-fvnc-hermes-agent-1
for i in $(seq 1 90); do docker exec $C pgrep -f "hermes gateway run" >/dev/null || break; sleep 10; done
echo "$(date -u +%T) antigo terminou ou passaram 15 min; a arrancar gateway novo" >> /opt/omniroute/logs/gateway-relancar.log
docker exec -d -u hermes $C sh -c "cd /opt/data && nohup hermes gateway run --replace >>/opt/data/logs/gateway.log 2>&1 </dev/null"
sleep 60
docker exec $C pgrep -fa "hermes gateway run" >> /opt/omniroute/logs/gateway-relancar.log 2>&1

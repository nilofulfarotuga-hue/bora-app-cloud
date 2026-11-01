#!/bin/bash
C=hermes-agent-fvnc-hermes-agent-1
date -u '+antes %FT%TZ'
docker restart $C >/dev/null && echo "reiniciado"
for i in $(seq 1 30); do
  sleep 3
  st=$(docker inspect -f '{{.State.Status}} {{if .State.Health}}{{.State.Health.Status}}{{end}}' $C)
  ts=$(docker exec $C sh -lc 'tailscale ip -4 2>/dev/null' | head -1)
  if [ -n "$ts" ]; then echo "estado=$st tailscale=$ts depois de $((i*3)) s"; break; fi
done
[ -z "$ts" ] && { echo "tailscale nao voltou sozinho: a correr bora-bridge-up.sh"; /root/bora-bridge-up.sh 2>&1 | tail -5; }
docker exec $C sh -lc 'tailscale serve status 2>&1 | head -6'
sleep 10
echo "== processos do gateway =="
docker exec $C bash -c 'ps -eo pid,etime,cmd | grep -iE "hermes|gateway" | grep -v grep | cut -c1-140 | head -8'
echo "== ultimas linhas de log do gateway =="
docker logs --since 2m $C 2>&1 | grep -viE 'key|token|secret' | tail -15 | cut -c1-200

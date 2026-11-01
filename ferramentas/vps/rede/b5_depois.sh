#!/bin/bash
# B5 fecho: compose do Hermes com a porta do painel so em 127.0.0.1 (vale no proximo recriar; NAO se recria agora:
# o contentor tem ~11 500 alteracoes feitas em funcionamento que se perdiam) + retrato depois + provas de vida.
F=/docker/hermes-agent-fvnc/docker-compose.yml
[ -f $F.bak-infra-20261101 ] || cp -p $F $F.bak-infra-20261101
sed -i 's/^\(\s*-\s*\)"4860"\s*$/\1"127.0.0.1::4860"  # infra-claude-tudo 01\/11: so local (o traefik usa a rede docker)/' $F
grep -n '4860' $F | head -3
docker compose -f $F config >/dev/null 2>&1 && echo "compose valido" || echo "COMPOSE INVALIDO"
bash /root/infra-2026-11-01/b5_retrato.sh depois > /dev/null 2>&1; echo "retrato depois gravado"
echo "== provas de vida =="
curl -s -m5 http://127.0.0.1:8792/saude | python3 -c 'import json,sys; d=json.load(sys.stdin); print("motor:", d["ok"])'
python3 /root/infra-2026-11-01/ver_porteiro.py http://172.16.1.1:8793/porteiro /opt/segredos/porteiro.env | head -3
docker exec hermes-agent-fvnc-hermes-agent-1 sh -lc 'tailscale serve status 2>&1 | grep -E "^\|-->"'
docker exec hermes-agent-fvnc-hermes-agent-1 bash -c 'pgrep -f "hermes gateway run" >/dev/null && echo "hermes gateway: a correr"'
for s in whatsapp-bora whatsapp-cerebro porteiro voz-servidor motor-bora assistente-negocio fail2ban; do printf '%s: %s\n' $s "$(systemctl is-active $s)"; done
echo "whatsapp-bora ultimos 2 min: $(journalctl -u whatsapp-bora --since '2 min ago' --no-pager 2>/dev/null | wc -l) linhas; cerebro: $(journalctl -u whatsapp-cerebro --since '10 min ago' --no-pager 2>/dev/null | wc -l) linhas"
docker ps --format '{{.Names}} {{.Status}}' | grep -iE 'cortex|conselho|traefik|omniroute'

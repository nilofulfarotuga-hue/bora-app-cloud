#!/bin/bash
# Saúde dos serviços da VPS — antes/depois da firewall (geral-sabado-24-10, bloco 2).
# Só lê. Uso: bash saude-servicos.sh
H=hermes-agent-fvnc-hermes-agent-1
echo "== hora $(date -u +%FT%TZ)"
echo "== contentores"
docker ps --format '{{.Names}} | {{.Status}}' | sort
echo "== systemd (host)"
for u in whatsapp-bora whatsapp-cerebro assistente-negocio motor-bora hermes-autoheal hermes-shim orq-campainha agentes-email-ponte.path buzz-acp-hermes; do
  printf '%s=%s ' "$u" "$(systemctl is-active $u)"
done; echo
echo "== hermes: tailscale + gateway (Emerson/Telegram)"
docker exec $H sh -c 'tailscale status --self=true --peers=false 2>/dev/null | head -1; ps -eo cmd | grep -iE "gateway|telegram" | grep -v grep | head -3' 2>&1
echo "== hermes -> host 172.16.1.1:8791/8792"
docker exec $H bash -c 'for p in 8791 8792; do (exec 3<>/dev/tcp/172.16.1.1/$p) 2>/dev/null && echo "$p aberto" || echo "$p FECHADO"; done' 2>&1
echo "== hermes -> omniroute"
docker exec $H sh -c 'curl -s -o /dev/null -w "omniroute %{http_code}\n" --max-time 8 http://omniroute:20128/v1/models || echo omniroute-sem-resposta' 2>&1
curl -s -o /dev/null -w "host->omniroute %{http_code}\n" --max-time 8 http://127.0.0.1:20128/v1/models
echo "== whatsapp (ultimas linhas)"
journalctl -u whatsapp-bora -n 3 --no-pager 2>&1 | tail -3
echo "== carteiro (ultimas linhas de log)"
ls -t /root/orquestracao/logs/*carteiro* 2>/dev/null | head -1 | xargs -r tail -2
echo "== saida para a internet"
curl -s -o /dev/null -w "github %{http_code}\n" --max-time 8 https://api.github.com
curl -s -o /dev/null -w "supabase %{http_code}\n" --max-time 8 https://ojykpzwqrtusfeakzrna.supabase.co/rest/v1/

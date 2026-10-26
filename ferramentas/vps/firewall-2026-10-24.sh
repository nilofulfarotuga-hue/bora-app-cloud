#!/bin/bash
# Firewall da VPS (missão geral-sabado-24-10, bloco 2) — 24/10/2026.
#
# Porquê: a 23/10 a firewall estava desligada (ufw inactive, INPUT ACCEPT) e
# respondiam da internet: 32768/32770 (painel Hermes), 8090 (bora-trader),
# 8099 (página do QR do WhatsApp) e 631 (impressoras CUPS).
#
# O que fica aberto à internet: SSH (22) e o Traefik (80/443, que serve os
# sites e os MCP pelo Cloudflare). Tudo o resto fecha:
#   - portas do HOST (8099, 631, ...): ufw "deny incoming";
#   - portas publicadas pelo DOCKER (8090, painel Hermes): o Docker salta o
#     INPUT do ufw, por isso fecham na cadeia DOCKER-USER (novas ligações
#     vindas de eth0 são recusadas; as respostas de ligações que os
#     contentores abriram continuam a passar).
# As redes internas do Docker (172.16.0.0/16) continuam a falar com o host
# (o Hermes usa 172.16.1.1:8791/8792).
# Acesso ao que fechou:
#   - painel Hermes: pela Tailscale (o contentor tem 100.120.181.115:4860);
#   - trader e QR do WhatsApp: túnel ssh, ex.
#       ssh -i ~/.ssh/id_ed25519_vps -L 8099:127.0.0.1:8099 root@srv1786862.hstgr.cloud
#     e abrir http://127.0.0.1:8099 no PC.
#
# Rede de segurança: antes de ligar, agenda-se "ufw disable" daqui a 10 min.
# Quem corre isto cancela-o (systemctl stop firewall-recuo.timer) só depois
# de provar que o SSH continua a entrar.
set -u
TS=$(date +%Y%m%d-%H%M%S)
B=/root/backups/firewall-$TS
mkdir -p "$B"
iptables-save  > "$B/iptables.antes"
ip6tables-save > "$B/ip6tables.antes"
cp -a /etc/ufw "$B/ufw-etc"
echo "copia em $B"

# 1) Impressoras (CUPS): não há impressora num servidor.
for u in cups.service cups.socket cups.path cups-browsed.service; do
  systemctl disable --now "$u" 2>/dev/null && echo "desligado $u"
done
# Nesta VPS o CUPS veio como snap (snap.cups.cupsd): é por aqui que se desliga.
snap stop --disable cups 2>/dev/null && echo "desligado snap cups"

# 2) Rede de segurança: desliga a firewall sozinha daqui a 10 min.
systemd-run --unit=firewall-recuo --on-active=600 /usr/sbin/ufw disable

# 3) Regras do ufw (portas do host).
ufw default deny incoming
ufw default allow outgoing
ufw allow 22/tcp  comment 'ssh'
ufw allow 80/tcp  comment 'traefik http'
ufw allow 443/tcp comment 'traefik https'
ufw allow from 172.16.0.0/16 comment 'redes docker -> servicos do host'

# 4) Portas publicadas pelo Docker: DOCKER-USER (bloco no fim do after.rules).
if ! grep -q 'BORA DOCKER-USER' /etc/ufw/after.rules; then
  cat >> /etc/ufw/after.rules <<'EOF'

# BEGIN BORA DOCKER-USER (24/10/2026)
*filter
:DOCKER-USER - [0:0]
-A DOCKER-USER -i eth0 -m conntrack --ctstate RELATED,ESTABLISHED -j RETURN
-A DOCKER-USER -i eth0 -m conntrack --ctstate NEW -j DROP
-A DOCKER-USER -j RETURN
COMMIT
# END BORA DOCKER-USER
EOF
  echo "DOCKER-USER acrescentado ao after.rules"
fi

ufw --force enable
ufw reload
ufw status verbose
iptables -S DOCKER-USER

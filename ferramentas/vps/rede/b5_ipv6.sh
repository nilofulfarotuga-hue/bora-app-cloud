#!/bin/bash
# B5: fecha no IPv6 as portas publicadas pelo Docker (trader 8090, painel do Hermes), como ja esta no IPv4 desde 25/10.
# Rede de seguranca: se o ssh deixar de entrar, o ufw desliga-se sozinho em 10 min.
set -u
F=/etc/ufw/after6.rules
echo "== bloco IPv4 que ja existe (after.rules) =="; grep -n 'DOCKER-USER' /etc/ufw/after.rules | head
if grep -q 'infra-claude-tudo DOCKER-USER' $F; then echo "ja aplicado"; else
  cp -p $F $F.bak-infra-20261101
  systemd-run --on-active=600 --unit=ufw-rede-seguranca /usr/sbin/ufw disable >/dev/null 2>&1 && echo "rede de seguranca armada (10 min)"
  cat >> $F <<'EOF'

# infra-claude-tudo DOCKER-USER (01/11/2026): o Docker publica portas no IPv6 sem passar pelo ufw.
# Igual ao IPv4 (after.rules): de fora (eth0) so entram respostas; ligacoes novas as portas do Docker caem.
*filter
:DOCKER-USER - [0:0]
-A DOCKER-USER -i eth0 -m conntrack --ctstate RELATED,ESTABLISHED -j RETURN
-A DOCKER-USER -i eth0 -m conntrack --ctstate NEW -j DROP
-A DOCKER-USER -j RETURN
COMMIT
EOF
  ufw reload
fi
echo "== DOCKER-USER IPv6 agora =="; ip6tables -S DOCKER-USER

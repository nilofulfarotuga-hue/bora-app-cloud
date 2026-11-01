#!/bin/bash
# B5: retrato da rede, portas e disco (antes/depois). Uso: b5_retrato.sh antes|depois
Q=${1:-antes}; F=/root/infra-2026-11-01/rede-$Q.txt
{
echo "### $Q $(date -u +%FT%TZ)"
echo "== portas a ouvir (fora de 127.0.0.1 / ::1) =="
ss -tulpnH | awk '{print $1, $5, $7}' | grep -vE ' (127\.0\.0\.[0-9]+|\[::1\]|::1):' | sed -E 's/users:\(\("([^"]+)".*/\1/' | sort -u
echo "== docker: portas publicadas =="
docker ps --format '{{.Names}}|{{.Ports}}' | awk -F'|' '$2!=""{print}'
echo "== ufw =="
ufw status verbose | sed -n '1,30p'
echo "== DOCKER-USER =="
iptables -S DOCKER-USER 2>/dev/null
echo "== fail2ban / unattended-upgrades =="
systemctl is-active fail2ban 2>&1; fail2ban-client status sshd 2>/dev/null | grep -E 'Currently|Total' ; dpkg -l unattended-upgrades 2>/dev/null | awk '/^ii/{print "unattended-upgrades", $3}'; cat /etc/apt/apt.conf.d/20auto-upgrades 2>/dev/null
echo "== ssh =="
sshd -T 2>/dev/null | grep -E '^(passwordauthentication|permitrootlogin|port|pubkeyauthentication) '
echo "== disco =="
df -h / | tail -1
docker system df 2>/dev/null
journalctl --disk-usage 2>/dev/null
du -sh /opt/data/voz/fila /var/log /root/.cache /root/.npm /opt/whatsapp-bora/*.json /opt/whatsapp-bora/memoria* /var/lib/docker/containers 2>/dev/null | sort -h | tail -12
} > $F 2>&1
cat $F

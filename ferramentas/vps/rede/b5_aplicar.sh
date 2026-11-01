#!/bin/bash
# B5 infra-claude-tudo-2026-11-01: fail2ban no ssh, atualizacoes de seguranca automaticas, limpeza do disco
# (so o que se regenera: diarios antigos, logs rodados, caches de pacotes, temporarios da voz). Nada de volumes.
set -u
echo "== 1. fail2ban =="
if ! command -v fail2ban-client >/dev/null; then
  DEBIAN_FRONTEND=noninteractive apt-get install -y -q fail2ban >/tmp/f2b-install.log 2>&1; echo "instalado rc=$?"
fi
cat > /etc/fail2ban/jail.d/bora-sshd.local <<'EOF'
# infra-claude-tudo 01/11/2026: protege o ssh (password ainda ligada) contra tentativas em massa.
# Nunca bane a propria maquina, a Tailscale nem as redes docker.
[DEFAULT]
ignoreip = 127.0.0.1/8 ::1 100.64.0.0/10 172.16.0.0/12
bantime = 1h
findtime = 10m
maxretry = 6
backend = systemd

[sshd]
enabled = true
EOF
systemctl enable --now fail2ban >/dev/null 2>&1; systemctl restart fail2ban; sleep 3
systemctl is-active fail2ban; fail2ban-client status sshd 2>&1 | grep -E 'Status|Currently|Total|Journal' | head -6
echo "== 2. atualizacoes de seguranca automaticas =="
systemctl enable --now unattended-upgrades >/dev/null 2>&1; systemctl is-active unattended-upgrades
grep -E 'Unattended-Upgrade|Update-Package-Lists' /etc/apt/apt.conf.d/20auto-upgrades
grep -cE '^\s*"\$\{distro_id\}:\$\{distro_codename\}-security"' /etc/apt/apt.conf.d/50unattended-upgrades
echo "== 3. disco (antes) =="; df -B1 / | awk 'NR==2{printf "usado %.2f GB de %.2f GB (%.1f%%)\n", $3/1e9, ($3+$4)/1e9, 100*$3/($3+$4)}'
journalctl --vacuum-size=200M 2>&1 | tail -1
find /var/log -type f \( -name '*.gz' -o -name '*.[0-9]' -o -name '*.old' \) -mtime +1 -print -delete 2>/dev/null | wc -l
apt-get clean
pip cache purge >/dev/null 2>&1; python3 -m pip cache purge >/dev/null 2>&1
command -v npm >/dev/null && npm cache clean --force >/dev/null 2>&1
rm -rf /docker/hermes-agent-fvnc/data/voz/tmp/* 2>/dev/null
docker system prune -af 2>&1 | tail -1
# revisoes antigas (desligadas) dos snaps: o snap guarda 2-3 copias de cada pacote
snap list --all 2>/dev/null | awk '/disabled/{print $1, $3}' | while read n r; do snap remove "$n" --revision="$r" >/dev/null 2>&1 && echo "snap $n rev $r removida"; done
echo "== disco (depois) =="; df -B1 / | awk 'NR==2{printf "usado %.2f GB de %.2f GB (%.1f%%)\n", $3/1e9, ($3+$4)/1e9, 100*$3/($3+$4)}'; df -h / | tail -1

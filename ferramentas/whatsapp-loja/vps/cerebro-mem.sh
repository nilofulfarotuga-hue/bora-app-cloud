#!/bin/sh
# Regista a memoria do whatsapp-cerebro de 10 em 10 min (30/10/2026, adendo 13): o processo antigo chegou a
# 388 de 400 MB sem se saber porque; com este registo ve-se se volta a crescer e quando.
CG=/sys/fs/cgroup/system.slice/whatsapp-cerebro.service
[ -r "$CG/memory.stat" ] || exit 0
ANON=$(awk '/^anon /{print $2}' "$CG/memory.stat")
CUR=$(cat "$CG/memory.current")
PID=$(systemctl show whatsapp-cerebro -p MainPID --value)
echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) pid=$PID anon=$ANON current=$CUR" >> /var/log/whatsapp-cerebro-mem.log

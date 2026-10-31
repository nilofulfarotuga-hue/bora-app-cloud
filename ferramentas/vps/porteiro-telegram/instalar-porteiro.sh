#!/usr/bin/env bash
# Instala o porteiro (bloco 6, retoma-geral-2026-10-31). Ficheiros chegam por scp a /tmp/porteiro-inst/.
set -e
S=/tmp/porteiro-inst
V=/opt/data/voz
sed -i 's/\r$//' $S/*
cp -p $V/voz.py $V/voz.py.bak-31-10
[ -f $V/audio-add.sh.bak-31-10 ] || cp -p $V/audio-add.sh $V/audio-add.sh.bak-31-10
install -o hermes-exec -g hermes-exec -m 755 $S/porteiro.py $V/porteiro.py
install -o hermes-exec -g hermes-exec -m 755 $S/porteiro_cli.py $V/porteiro_cli.py
install -o hermes-exec -g hermes-exec -m 755 $S/voz.py $V/voz.py
mkdir -p $V/porteiro && chmod 777 $V/porteiro
if [ ! -f $V/porteiro.env ]; then
  umask 077
  printf 'PORTEIRO_SEGREDO=%s\nPORTEIRO_BASTIDORES_CHAT=\n' "$(python3 -c 'import secrets;print(secrets.token_hex(24))')" > $V/porteiro.env
  chmod 600 $V/porteiro.env
fi
python3 -m py_compile $V/porteiro.py $V/porteiro_cli.py $V/voz.py && echo compilou
install -o root -g root -m 644 $S/porteiro.service /etc/systemd/system/porteiro.service
systemctl daemon-reload
systemctl enable --now porteiro.service
sleep 2
systemctl is-active porteiro.service
ss -ltnp | grep -E ':879[67] ' | cut -c1-90

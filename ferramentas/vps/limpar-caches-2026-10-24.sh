#!/bin/bash
# Limpeza do disco da VPS — SÓ o que se regenera sozinho (geral-sabado-24-10, bloco 2b).
# Nunca: dados, volumes em uso, imagens de contentores a correr, media, bases de dados.
set -u
H=hermes-agent-fvnc-hermes-agent-1
antes=$(df --output=used -B1 / | tail -1)
df -h / | tail -1

echo "== cache de compilação do docker (sem uso)"
docker builder prune -af 2>&1 | tail -1

echo "== caches de pacotes (pip, npm, uv) — host e Hermes"
rm -rf /root/.cache/pip
npm cache clean --force >/dev/null 2>&1 || rm -rf /root/.npm/_cacache
docker exec $H sh -c 'command -v uv >/dev/null && uv cache clean >/dev/null 2>&1 || rm -rf /opt/data/.cache/uv; rm -rf /opt/data/.cache/pip; npm cache clean --force >/dev/null 2>&1 || true' 2>&1 | tail -2

echo "== diário do sistema (fica 100 MB)"
journalctl --vacuum-size=100M 2>&1 | tail -1

echo "== apt"
apt-get clean

echo "== versões antigas (desativadas) dos snaps"
snap set system refresh.retain=2 2>/dev/null
snap list --all | awk '/disabled/{print $1, $3}' | while read n r; do
  snap remove "$n" --revision="$r" >/dev/null 2>&1 && echo "removido $n rev $r"
done

depois=$(df --output=used -B1 / | tail -1)
df -h / | tail -1
echo "libertado: $(( (antes - depois) / 1048576 )) MB"

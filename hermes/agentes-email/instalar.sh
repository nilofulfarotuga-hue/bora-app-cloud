#!/bin/bash
# Instala a ponte da caixa dos agentes na VPS (host). Idempotente.
# Ficheiros esperados em /tmp/agentes-email-inst/ (enviados por scp a partir do repo hermes/agentes-email/).
set -euo pipefail
SRC=/tmp/agentes-email-inst
DATA=/docker/hermes-agent-fvnc/data
C=hermes-agent-fvnc-hermes-agent-1

for f in ponte.py hermes-email agentes-email-ponte.path agentes-email-ponte.service SOUL-bloco-agentes-email.md; do
  [ -f "$SRC/$f" ] || { echo "falta $SRC/$f"; exit 1; }
  sed -i 's/\r$//' "$SRC/$f"
done

# 1) motor no host
install -d -m 755 /opt/agentes-email
install -m 755 "$SRC/ponte.py" /opt/agentes-email/ponte.py
printf '#!/bin/sh\nexec /usr/bin/python3 /opt/agentes-email/ponte.py cli "$@"\n' > /usr/local/bin/hermes-email
chmod 755 /usr/local/bin/hermes-email

# 2) pastas partilhadas com o contentor (uid 10000 = hermes)
install -d -m 770 -o 10000 -g 10000 "$DATA/agentes-email" "$DATA/agentes-email/fila" "$DATA/agentes-email/respostas" "$DATA/agentes-email/tmp"
install -d -m 755 -o 10000 -g 10000 "$DATA/bin"
install -m 755 -o 10000 -g 10000 "$SRC/hermes-email" "$DATA/bin/hermes-email"

# 3) comando dentro do contentor (o /usr/local/bin do contentor perde-se se a imagem for recriada;
#    o SOUL.md ensina o caminho persistente /opt/data/bin/hermes-email)
docker exec -u root "$C" sh -c 'ln -sf /opt/data/bin/hermes-email /usr/local/bin/hermes-email' || echo "aviso: symlink no contentor falhou"

# 4) systemd
install -m 644 "$SRC/agentes-email-ponte.path" /etc/systemd/system/agentes-email-ponte.path
install -m 644 "$SRC/agentes-email-ponte.service" /etc/systemd/system/agentes-email-ponte.service
systemctl daemon-reload
systemctl enable --now agentes-email-ponte.path
systemctl is-active agentes-email-ponte.path

# 5) SOUL.md do Emerson: acrescenta o bloco uma vez (com cópia de segurança)
if grep -q 'CAIXA DE E-MAIL DOS AGENTES @boraguarda.com' "$DATA/SOUL.md"; then
  echo "SOUL.md: bloco já existe"
else
  cp -p "$DATA/SOUL.md" "$DATA/SOUL.md.bak-agentes-email-20261021"
  cat "$SRC/SOUL-bloco-agentes-email.md" >> "$DATA/SOUL.md"
  chown 10000:10000 "$DATA/SOUL.md"
  echo "SOUL.md: bloco acrescentado"
fi
echo "instalado"

#!/usr/bin/env bash
# inject-app-password.sh — guarda um segredo (app password Gmail, token, etc.) num
# ficheiro 600 em /opt/data/.secrets/, SEM que o valor apareça no argv, no histórico
# ou nos logs. Lê o segredo do STDIN.
#
# Uso (dentro do container, como hermes):
#   ./inject-app-password.sh gmail_boraapp
#   <cola a app password de 16 chars> <Enter> <Ctrl-D>
#
# Ou por SSH sem TTY (o valor viaja pela pipe, não pelo argv):
#   echo -n 'APP_PASSWORD' | ssh ... 'docker exec -i -u hermes CONTAINER \
#       /opt/data/hermes/socio-ai/inject-app-password.sh gmail_boraapp'
set -euo pipefail

NAME="${1:-}"
if [[ -z "$NAME" ]]; then
  echo "erro: falta o nome do segredo (ex.: gmail_boraapp, gmail_cloudflare)" >&2
  exit 1
fi
# só permite nomes seguros
if [[ ! "$NAME" =~ ^[a-z0-9_]+$ ]]; then
  echo "erro: nome inválido '$NAME' (usar [a-z0-9_])" >&2
  exit 1
fi

SECRETS_DIR="/opt/data/.secrets"
mkdir -p "$SECRETS_DIR"
chmod 700 "$SECRETS_DIR"

DEST="$SECRETS_DIR/${NAME}.pass"
# lê tudo do stdin, remove espaços/newlines das pontas (app passwords Gmail vêm com espaços)
SECRET="$(cat)"
SECRET="$(printf '%s' "$SECRET" | tr -d '[:space:]')"

if [[ -z "$SECRET" ]]; then
  echo "erro: stdin vazio — nada guardado" >&2
  exit 1
fi

umask 077
printf '%s' "$SECRET" > "$DEST"
chmod 600 "$DEST"

echo "ok: guardado em $DEST (600). Últimos 4 chars: ...${SECRET: -4}  (len=${#SECRET})"

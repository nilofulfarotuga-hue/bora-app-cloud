#!/bin/bash
# PONTE DO TELEGRAM — o único canal com o Danilo.
# Montada e provada a 2026-09-07 na missão `ios-lancamento`.
#
# USO
#   bash orquestracao/ponte-telegram.sh "a mensagem"          # texto + voz
#   bash orquestracao/ponte-telegram.sh --so-texto "a msg"    # só texto
#   bash orquestracao/ponte-telegram.sh --so-voz   "a msg"    # só voz
#
# PORQUE PASSA POR BASE64
# Duas cicatrizes juntas: o contentor do Hermes corre em locale POSIX e o
# heredoc por SSH come os acentos. Já saiu `ó` literal numa legenda
# pública. Codificar aqui e descodificar lá é a única forma provada de o "ã"
# chegar inteiro — verificado a 2026-09-07 lendo o log de volta.
#
# ONDE VIVE CADA COISA (host srv1786862.hstgr.cloud)
#   /opt/data/scripts/gritar.sh   texto no Telegram; NÃO depende do .env das
#                                 redes (lê /opt/data/social/.aviso.conf)
#   /usr/local/bin/voz            bolha de voz (sendVoice), corre no HOST e não
#                                 dentro do contentor
#   /opt/data/social/log.md       onde se lê de volta o que saiu
#   /opt/data/voz/voz.log.jsonl   registo dos envios de voz
#
# PROVA DE QUE FUNCIONA: correr e depois ler o log — nunca confiar no exit 0.
#   ssh ... 'tail -1 /opt/data/social/log.md'

set -uo pipefail

CHAVE="$HOME/.ssh/id_ed25519_vps"
HOST="root@srv1786862.hstgr.cloud"

MODO="ambos"
case "${1:-}" in
  --so-texto) MODO="texto"; shift ;;
  --so-voz)   MODO="voz";   shift ;;
esac

MSG="${1:-}"
[ -z "$MSG" ] && { echo "uso: ponte-telegram.sh [--so-texto|--so-voz] \"mensagem\"" >&2; exit 2; }

B64=$(printf '%s' "$MSG" | base64 -w0)
remoto() { ssh -i "$CHAVE" -o BatchMode=yes -o ConnectTimeout=20 "$HOST" "$1"; }

rc=0
if [ "$MODO" != "voz" ]; then
  remoto "T=\$(printf '%s' '$B64' | base64 -d); /opt/data/scripts/gritar.sh \"\$T\"" \
    && echo "texto: enviado" || { echo "texto: FALHOU" >&2; rc=1; }
fi
if [ "$MODO" != "texto" ]; then
  remoto "T=\$(printf '%s' '$B64' | base64 -d); voz \"\$T\"" \
    && echo "voz: enviada" || { echo "voz: FALHOU" >&2; rc=1; }
fi

# Ler de volta: o exit 0 é o invólucro, o log é o efeito.
echo "--- o que ficou registado no servidor ---"
remoto 'tail -1 /opt/data/social/log.md; tail -1 /opt/data/voz/voz.log.jsonl'
exit $rc

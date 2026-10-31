#!/bin/bash
# TELEGRAM-DANILO — a forma de uma sessao do PC (Claude Code, Dipsy, scripts) falar com o Danilo no BoraHermesbot.
# Desde 31/10/2026 (missao retoma-geral-2026-10-31, bloco 6, ordem do Danilo das 10:07) ha UMA so porta para o chat
# dele: o PORTEIRO na VPS (/opt/data/voz/porteiro.py). Ele faz a triagem, tira os repetidos e manda SEMPRE texto + voz.
# Nunca chamar a API do bot diretamente (curl api.telegram.org): isso salta a triagem e a voz.
#
# USO
#   bash orquestracao/telegram-danilo.sh RESULTADO "Feito: X. Falta: Y."        # missao acabou (3 linhas no maximo)
#   bash orquestracao/telegram-danilo.sh URGENTE   "Carrega em Permitir na sessao X"  # precisa dele agora
#   bash orquestracao/telegram-danilo.sh INFO      "estado/ids/ok de rotina"    # NAO vai ao chat: fica nos bastidores
#   echo "texto" | bash orquestracao/telegram-danilo.sh RESULTADO -              # texto pelo stdin
#   opcoes: --origem NOME (por omissao claude-code)   --ensaio (decide e regista, nao envia)
#
# PORQUE PASSA POR SSH + BASE64: o porteiro so ouve na VPS (nada aberto a internet) e o base64 e' a unica forma provada
# de os acentos chegarem inteiros (ver ponte-telegram.sh, 07/09/2026).
# PROVA: a resposta JSON do porteiro (ids_texto = message_id do Telegram; destino chat|bastidores|registo|descartado).

set -uo pipefail
CHAVE="$HOME/.ssh/id_ed25519_vps"
HOST="root@srv1786862.hstgr.cloud"

NIVEL="${1:-}"
case "$NIVEL" in
  URGENTE|RESULTADO|INFO) shift ;;
  *) echo "uso: telegram-danilo.sh URGENTE|RESULTADO|INFO [--origem X] [--ensaio] \"texto\"|-" >&2; exit 2 ;;
esac
ORIGEM="claude-code"
ENSAIO=""
MSG=""
while [ $# -gt 0 ]; do
  case "$1" in
    --origem) ORIGEM="${2:-claude-code}"; shift 2 ;;
    --ensaio) ENSAIO="PORTEIRO_ENSAIO=1"; shift ;;
    -) MSG=$(cat); shift ;;
    *) MSG="${MSG:+$MSG }$1"; shift ;;
  esac
done
[ -z "$MSG" ] && { echo "telegram-danilo: texto vazio" >&2; exit 2; }
ORIGEM=$(printf '%s' "$ORIGEM" | tr -cd 'A-Za-z0-9._:-' | cut -c1-60)

B64=$(printf '%s' "$MSG" | base64 -w0)
RESP=$(ssh -i "$CHAVE" -o BatchMode=yes -o ConnectTimeout=20 "$HOST" \
  "printf '%s' '$B64' | base64 -d | $ENSAIO python3 /opt/data/voz/porteiro_cli.py danilo $NIVEL --origem '$ORIGEM' -" 2>&1)
RC=$?
printf '%s\n' "$RESP"
[ $RC -eq 0 ] || echo "telegram-danilo: o porteiro NAO aceitou (rc=$RC). Nao ha caminho de recurso para a API do bot, de proposito." >&2
exit $RC

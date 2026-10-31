#!/bin/bash
# PONTE DO TELEGRAM — o único canal com o Danilo.
# Montada e provada a 2026-09-07 na missão `ios-lancamento`.
# 31/10/2026 (retoma-geral-2026-10-31, bloco 6): passa a ser só um atalho para o PORTEIRO
# (orquestracao/telegram-danilo.sh). O porteiro faz a triagem (URGENTE / RESULTADO / INFO), tira os
# repetidos e manda SEMPRE texto + voz; já não se chama o gritar.sh nem o voz por aqui.
#
# USO
#   bash orquestracao/ponte-telegram.sh "a mensagem"                    # RESULTADO (texto + voz)
#   bash orquestracao/ponte-telegram.sh --nivel URGENTE "a mensagem"    # precisa dele agora
#   bash orquestracao/ponte-telegram.sh --nivel INFO "a mensagem"       # fica nos bastidores (não vai ao chat)
#   --so-texto / --so-voz: aceites por compatibilidade, mas o porteiro manda sempre os dois (regra do Danilo).
#
# PROVA DE QUE FUNCIONA: a resposta JSON do porteiro (ids_texto = message_id) e, no servidor,
#   ssh ... 'tail -1 /opt/data/voz/porteiro/porteiro.log.jsonl; tail -1 /opt/data/voz/voz.log.jsonl'

set -uo pipefail
NIVEL="RESULTADO"
while [ $# -gt 0 ]; do
  case "$1" in
    --so-texto|--so-voz) shift ;;
    --nivel) NIVEL="${2:-RESULTADO}"; shift 2 ;;
    *) break ;;
  esac
done
MSG="${1:-}"
[ -z "$MSG" ] && { echo "uso: ponte-telegram.sh [--nivel URGENTE|RESULTADO|INFO] \"mensagem\"" >&2; exit 2; }
exec bash "$(dirname "$0")/telegram-danilo.sh" "$NIVEL" --origem "${PORTEIRO_ORIGEM:-claude-code}" "$MSG"

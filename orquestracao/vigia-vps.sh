#!/bin/bash
# VIGIA DA VPS — corre no PC, de 30 em 30 minutos, e grita quando o estado MUDA.
#
# PORQUE EXISTE
# A 09/09/2026 a VPS expirou e ficou desligada. Ninguém soube durante horas, porque o
# único canal de aviso vivia dentro da própria VPS. Este vigia vive no PC e usa o
# `gritar-do-pc.sh`, que fala directo com a API do Telegram.
#
# NÃO É UM SPAMMER: só avisa na TRANSIÇÃO (viva -> morta, morta -> viva). Enquanto o
# estado não mudar, cala-se. O aviso diário continua a ser da ordem fixa das 08:00.
#
# Estado guardado em ~/.bora/vps-estado (uma palavra: viva ou morta).

set -uo pipefail
cd "$(dirname "$0")/.." || exit 1

HOST="srv1786862.hstgr.cloud"
ESTADO_F="/c/Users/danil/.bora/vps-estado"
LOG="/c/Users/danil/.bora/vigia-vps.log"
mkdir -p "$(dirname "$ESTADO_F")"

# 06/10/2026 (missao quatro-blocos): o alarme das 13:13 foi FALSO -- o PC estava sem memoria e o ssh
# morria antes de sair (a VPS nao registou nenhuma tentativa). So se declara "morta" depois de 3
# tentativas com 1 minuto entre cada, e guarda-se o erro do ssh para se saber porque falhou.
AGORA="morta"; ERRO=""
for TENTATIVA in 1 2 3; do
  if ERRO=$(timeout 25 ssh -o BatchMode=yes -o ConnectTimeout=12 -o StrictHostKeyChecking=accept-new \
       -i "$HOME/.ssh/id_ed25519_vps" "root@$HOST" 'exit 0' 2>&1); then
    AGORA="viva"; break
  fi
  [ "$TENTATIVA" -lt 3 ] && sleep 60
done

ANTES=$(cat "$ESTADO_F" 2>/dev/null || echo "desconhecido")
echo "$(date -u +%FT%TZ) antes=$ANTES agora=$AGORA tentativas=$TENTATIVA${ERRO:+ erro=$(printf '%s' "$ERRO" | tr '\n' ' ' | cut -c1-160)}" >> "$LOG"
echo "$AGORA" > "$ESTADO_F"

[ "$ANTES" = "$AGORA" ] && exit 0
[ "$ANTES" = "desconhecido" ] && [ "$AGORA" = "viva" ] && exit 0

if [ "$AGORA" = "morta" ]; then
  bash orquestracao/gritar-do-pc.sh "BORA - A VPS DEIXOU DE RESPONDER

O vigia do PC bateu em $HOST e nao houve resposta. Enquanto isto durar param as publicacoes nos grupos, a loja do dia, o story, o reel, o banco de pecas, o Motor Bora e o cerebro do WhatsApp.

Primeira coisa a confirmar: a assinatura no hPanel da Hostinger. Foi essa a causa a 09/09." >> "$LOG" 2>&1
else
  bash orquestracao/gritar-do-pc.sh "BORA - A VPS VOLTOU

$HOST esta a responder outra vez. Os crons voltam sozinhos. Vou repor o banco de pecas na proxima ordem das 08:00." >> "$LOG" 2>&1
fi

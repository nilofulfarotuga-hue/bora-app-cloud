#!/bin/bash
# Envia UM vídeo ao Danilo pelo bot do Bora (mesmo token/chat do gritar.sh).
# Uso: enviar-video-telegram.sh <ficheiro.mp4> <legenda-em-base64>
# Prova: imprime ENVIADO message_id=<n> só se o Telegram devolver "ok":true.
set -u
F="$1"; LEG=$(echo "$2" | base64 -d)
TOKEN=""; CHAT=""
for f in /opt/data/social/.aviso.conf /opt/data/.env /opt/whatsapp-bora/.env; do
  [ -r "$f" ] || continue
  T=$(grep -m1 '^TELEGRAM_BOT_TOKEN=' "$f" 2>/dev/null | cut -d= -f2- | tr -d '"'"'"'')
  C=$(grep -m1 '^TELEGRAM_HOME_CHANNEL=' "$f" 2>/dev/null | cut -d= -f2- | tr -d '"'"'"'')
  [ -n "$T" ] && [ -z "$TOKEN" ] && TOKEN=$T
  [ -n "$C" ] && [ -z "$CHAT" ] && CHAT=$C
  [ -n "$TOKEN" ] && [ -n "$CHAT" ] && break
done
[ -z "$TOKEN" ] || [ -z "$CHAT" ] && { echo "ERRO sem token/chat"; exit 2; }
R=$(curl -s -m 180 -F chat_id="$CHAT" -F supports_streaming=true -F caption="$LEG" -F video=@"$F" \
    "https://api.telegram.org/bot$TOKEN/sendVideo")
if echo "$R" | grep -q '"ok":true'; then
  echo "ENVIADO message_id=$(echo "$R" | grep -o '"message_id":[0-9]*' | head -1 | cut -d: -f2) $(basename "$F")"
else
  echo "ERRO $(echo "$R" | head -c 300)"; exit 1
fi

#!/bin/sh
# Gera a configuração do Asterisk a partir dos modelos + .env (a senha SIP nunca fica no git) e arranca.
set -e
mkdir -p /etc/asterisk /var/voz
for f in pjsip.conf extensions.conf rtp.conf modules.conf; do
  sed -e "s|@ZADARMA_SIP_USER@|${ZADARMA_SIP_USER}|g" \
      -e "s|@ZADARMA_SIP_SENHA@|${ZADARMA_SIP_SENHA}|g" \
      -e "s|@IP_PUBLICO@|${IP_PUBLICO}|g" \
      "/etc/asterisk-bora/$f" > "/etc/asterisk/$f"
done
chmod 600 /etc/asterisk/pjsip.conf
exec asterisk -f -vvv

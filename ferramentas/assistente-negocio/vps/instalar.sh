#!/bin/bash
# Instala/atualiza o Assistente de Negocio na VPS. Corre como root. Idempotente.
# As chaves NUNCA passam por ecra: copiam-se de .env para .env.
set -e
D=/opt/assistente-negocio
mkdir -p $D
cp /tmp/assistente-negocio/*.py $D/
cp /tmp/assistente-negocio/vps/assistente-negocio.service /etc/systemd/system/assistente-negocio.service

pega() { grep -E "^$2=" "$1" 2>/dev/null | tail -1 | cut -d= -f2- | tr -d '\r"'; }
{
  echo "SUPABASE_URL=$(pega /opt/whatsapp-bora/.env SUPABASE_URL)"
  echo "SUPABASE_SERVICE_ROLE_KEY=$(pega /opt/whatsapp-bora/.env SUPABASE_SERVICE_ROLE_KEY)"
  echo "GEMINI_API_KEY=$(pega /opt/whatsapp-bora/.env GEMINI_API_KEY)"
  echo "GROQ_API_KEY=$(pega /opt/whatsapp-bora/.env GROQ_API_KEY)"
  echo "GEMINI_API_KEY_2=$(pega /docker/hermes-agent-fvnc/data/.env GEMINI_API_KEY)"
  echo "OPENCODE_GO_KEY=$(pega /opt/motor-bora/.env OPENCODE_GO_KEY)"
  if [ -f /tmp/assistente-negocio/.chave-paga ]; then
    echo "GEMINI_API_KEY_FATURACAO=$(cat /tmp/assistente-negocio/.chave-paga | tr -d '\r\n')"
  elif [ -f $D/.env ]; then
    echo "GEMINI_API_KEY_FATURACAO=$(pega $D/.env GEMINI_API_KEY_FATURACAO)"
  fi
} > $D/.env.novo
chmod 600 $D/.env.novo
mv $D/.env.novo $D/.env
shred -u /tmp/assistente-negocio/.chave-paga 2>/dev/null || true
for k in SUPABASE_URL SUPABASE_SERVICE_ROLE_KEY GEMINI_API_KEY GEMINI_API_KEY_2 GROQ_API_KEY OPENCODE_GO_KEY GEMINI_API_KEY_FATURACAO; do
  v=$(pega $D/.env $k); echo "$k: ${#v} caracteres"
done
systemctl daemon-reload
systemctl enable assistente-negocio >/dev/null 2>&1
systemctl restart assistente-negocio
sleep 3
systemctl is-active assistente-negocio
curl -s http://127.0.0.1:8795/saude

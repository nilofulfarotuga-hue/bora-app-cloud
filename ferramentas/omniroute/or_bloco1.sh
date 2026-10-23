#!/bin/bash
# Bloco 1 da missao omniroute-23-10: instalar o OmniRoute num contentor proprio.
# Segredos gerados aqui, nunca impressos. Porta so em 127.0.0.1 e na rede docker do Hermes.
set -euo pipefail
D=/opt/omniroute
mkdir -p $D/data $D/logs /root/backups
chmod 700 $D

if [ ! -f $D/.env ]; then
  umask 077
  PASS=$(openssl rand -base64 33 | tr -d '/+=' | cut -c1-28)
  cat > $D/.env <<EOF
# OmniRoute — segredos (missao omniroute-23-10, 2026-10-23). Nao versionar, nao copiar.
JWT_SECRET=$(openssl rand -base64 48 | tr -d '\n')
API_KEY_SECRET=$(openssl rand -hex 32)
STORAGE_ENCRYPTION_KEY=$(openssl rand -hex 32)
STORAGE_ENCRYPTION_KEY_VERSION=v1
INITIAL_PASSWORD=$PASS
MACHINE_ID_SALT=$(openssl rand -hex 16)
EOF
  chmod 600 $D/.env
  # copia da palavra-passe para o .env do Hermes (pedido da missao)
  cp -p /opt/data/.env /root/backups/hermes-data-env-antes-omniroute-20261023
  if ! grep -q '^OMNIROUTE_PASSWORD=' /opt/data/.env; then
    printf '\n# OmniRoute (missao omniroute-23-10)\nOMNIROUTE_PASSWORD=%s\nOMNIROUTE_URL=http://omniroute:20128/v1\n' "$PASS" >> /opt/data/.env
  fi
  echo "env criado"
else
  echo "env ja existia — nao mexi"
fi

cat > $D/docker-compose.yml <<'EOF'
# OmniRoute — roteador de IA com recuo entre fornecedores (missao omniroute-23-10).
# Porta 20128 so em 127.0.0.1 do host e na rede docker do Hermes. Nunca 0.0.0.0.
name: omniroute
services:
  omniroute:
    image: diegosouzapw/omniroute:3.8.52
    container_name: omniroute
    restart: always
    stop_grace_period: 40s
    env_file: .env
    environment:
      - DATA_DIR=/app/data
      - PORT=20128
      - DASHBOARD_PORT=20128
      - OMNIROUTE_MEMORY_MB=512
      - OMNIROUTE_RSS_PRESSURE_MB=900
      - REQUIRE_API_KEY=true
      - AUTH_COOKIE_SECURE=false
      - ENABLE_TLS_FINGERPRINT=false
      - OMNIROUTE_NO_UPDATE_NOTIFIER=1
      - TZ=Europe/Lisbon
    volumes:
      - ./data:/app/data
    ports:
      - "127.0.0.1:20128:20128"
    mem_limit: 1g
    networks:
      - hermes
networks:
  hermes:
    name: hermes-agent-fvnc_default
    external: true
EOF

chown -R 1000:1000 $D/data
cd $D
docker compose up -d 2>&1 | tail -5
sleep 25
docker ps --filter name=omniroute --format '{{.Names}} {{.Status}} {{.Ports}}'

#!/bin/bash
# Instala a central do atendente de voz da Bora na VPS (correr como root no anfitrião, não no contentor).
#   bash instalar.sh preparar   -> descarrega, cria o .env (senha gerada aqui), som de recurso, firewall
#                                  e mostra a IMPRESSÃO da senha (o Claude grava-a na base por MCP)
#   bash instalar.sh ligar      -> testa a senha contra o voz-ferramentas, arranca tudo e liga a vigia
#   bash instalar.sh estado     -> mostra contentores, linha da Zadarma e últimas linhas da central
# Nenhum segredo é mostrado no ecrã: a senha e a chave Groq vão de ficheiro para ficheiro.
set -euo pipefail
RAMO="${RAMO:-ai/2026-11-26-voz-central-sipuri}"
REPO="https://github.com/nilofulfarotuga-hue/bora-app-cloud"
RAIZ=/opt/voz
PASTA="$RAIZ/voz/atendente"
ZADARMA_HOSTS="sip.zadarma.com sipurifr.zadarma.com sipde.zadarma.com sipuriny.zadarma.com"
ZADARMA_REDES="185.45.152.0/24 185.45.154.0/24 185.45.155.0/24 195.122.19.0/27 31.31.222.192/27 15.235.128.64/28"

[ "$(id -u)" = 0 ] || { echo "ERRO: correr como root"; exit 1; }

baixar() {
  if [ -d "$RAIZ/.git" ]; then
    git -C "$RAIZ" fetch -q --depth 1 origin "$RAMO" && git -C "$RAIZ" checkout -q -B "$RAMO" FETCH_HEAD
  else
    git clone -q --depth 1 --filter=blob:none --sparse -b "$RAMO" "$REPO" "$RAIZ"
    git -C "$RAIZ" sparse-checkout set voz/atendente
  fi
  echo "OK código em $PASTA ($(git -C "$RAIZ" log -1 --format=%h))"
}

chave_groq() {
  # A mesma chave que o Hermes/voz já usam no anfitrião. Só se copia, nunca se mostra.
  local f v
  for f in /docker/hermes-agent-fvnc/data/.env /docker/hermes-agent-fvnc/.env /opt/data/.env \
           /docker/hermes-agent-fvnc/data/voz/.env /root/.env $(ls /opt/*/.env 2>/dev/null); do
    [ -f "$f" ] || continue
    v=$(grep -m1 -E '^(export )?GROQ_API_KEY=' "$f" | sed -E 's/^(export )?GROQ_API_KEY=//; s/^["'\'']//; s/["'\'']$//') || true
    [ -n "${v:-}" ] && { printf %s "$v"; return 0; }
  done
  return 1
}

preparar() {
  command -v docker >/dev/null || { echo "ERRO: docker não existe no anfitrião"; exit 1; }
  docker compose version >/dev/null 2>&1 || { echo "ERRO: falta o plugin docker compose"; exit 1; }
  baixar
  cd "$PASTA"
  if [ ! -f .env ]; then
    umask 077
    local senha groq ip
    senha=$(openssl rand -hex 32)
    groq=$(chave_groq) || { echo "ERRO: não encontrei GROQ_API_KEY no anfitrião"; exit 1; }
    ip=$(curl -fsS --max-time 5 https://api.ipify.org || echo 187.124.1.156)
    cat > .env <<EOF
VOZ_SENHA=$senha
GROQ_API_KEY=$groq
SUPABASE_FN=https://ojykpzwqrtusfeakzrna.supabase.co/functions/v1
VOZ_PORTA=9092
VOZ_LINHAS=1
IP_PUBLICO=$ip
EOF
    chmod 600 .env
    echo "OK .env criado (IP_PUBLICO=$ip, chave Groq copiada)"
  else
    echo "OK .env já existia (não mexi)"
  fi
  local imp
  imp=$(grep -m1 '^VOZ_SENHA=' .env | cut -d= -f2- | tr -d '\n' | sha256sum | cut -d' ' -f1)
  echo "$imp" > "$RAIZ/impressao.txt"
  echo "IMPRESSAO 1-32 : ${imp:0:32}"
  echo "IMPRESSAO 33-64: ${imp:32:32}"

  docker compose build -q central
  mkdir -p asterisk/sons
  if [ ! -s asterisk/sons/recurso.wav ]; then
    docker compose run --rm --no-deps -u root -v "$PASTA/asterisk/sons:/out" --entrypoint sh central -c \
      'edge-tts --voice pt-PT-RaquelNeural --text "Olá, ligou para a Bora. Neste momento não conseguimos atender. Por favor escreva para suporte arroba boraguarda ponto com. Obrigado." --write-media /tmp/r.mp3 && ffmpeg -y -loglevel error -i /tmp/r.mp3 -ar 8000 -ac 1 -acodec pcm_s16le /out/recurso.wav'
  fi
  ls -l asterisk/sons/recurso.wav

  if command -v ufw >/dev/null && ufw status | grep -q 'Status: active'; then
    for h in $ZADARMA_HOSTS; do
      for ip in $(getent ahostsv4 "$h" | awk '{print $1}' | sort -u); do
        ufw allow proto udp from "$ip" to any port 5060 comment "zadarma $h" >/dev/null
      done
    done
    for r in $ZADARMA_REDES; do ufw allow proto udp from "$r" to any port 5060 comment "zadarma rede" >/dev/null; done
    ufw allow 10000:10099/udp comment "rtp voz" >/dev/null
    echo "OK firewall ufw: 5060 só Zadarma, RTP 10000-10099"
  else
    echo "AVISO ufw inativo: o Asterisk só aceita pedidos da Zadarma (identify); ver firewall do painel Hostinger"
  fi
  echo "PREPARADO. Falta: gravar a impressão na base e correr: bash $0 ligar"
}

ligar() {
  cd "$PASTA"
  set -a; . ./.env; set +a
  local r
  r=$(curl -sS --max-time 20 -X POST "$SUPABASE_FN/voz-ferramentas" -H "x-voz-token: $VOZ_SENHA" \
      -H 'content-type: application/json' -d '{"op":"ping","dados":{}}' || true)
  echo "PING voz-ferramentas: ${r:0:200}"
  echo "$r" | grep -qiE '"ok" *: *true|pong' || { echo "ERRO: a senha ainda não foi aceite (impressão por gravar?)"; exit 1; }
  docker compose up -d --build
  local linha="*/5 * * * * cd $PASTA && docker compose ps --status running | grep -q central || docker compose up -d >/dev/null 2>&1"
  ( crontab -l 2>/dev/null | grep -v 'voz/atendente' ; echo "$linha" ) | crontab -
  echo "OK vigia de 5 em 5 min no crontab do root"
  sleep 10
  estado
}

estado() {
  cd "$PASTA"
  docker compose ps
  docker compose exec -T asterisk asterisk -rx "pjsip show identifies" 2>/dev/null | tail -n +1 | head -20 || true
  docker compose exec -T asterisk asterisk -rx "pjsip show transports" 2>/dev/null | head -12 || true
  docker compose logs --tail 15 central || true
  free -m | head -2
}

case "${1:-}" in
  preparar) preparar ;;
  ligar) ligar ;;
  estado) estado ;;
  *) echo "uso: bash $0 preparar|ligar|estado"; exit 1 ;;
esac

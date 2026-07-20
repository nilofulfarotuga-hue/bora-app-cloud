#!/usr/bin/env bash
# Deploy do Bora Web para Cloudflare Pages (projeto bora-app-web).
#
# O token NUNCA está aqui nem no repo — é lido em runtime do .env do bora-site,
# que é o mesmo token/conta que publica o site institucional
# (Nilofulfarotuga@gmail.com).
#
# Uso:
#   ./deploy-web.sh              # publica ./build/web
#   ./deploy-web.sh <pasta>      # publica outra pasta
#
# Nota: esta máquina (4 GB de RAM) NÃO consegue correr `flutter build web`
# — o dart2js não arranca as threads de trabalho. Por isso o build vem do CI:
#   1. o workflow build_web_deploy.yml compila e publica na branch `web-build`
#   2. ./buscar-build-web.sh traz essa branch para ./build/web
#   3. este script publica
set -euo pipefail

PASTA="${1:-build/web}"
PROJETO="bora-app-web"
ENV_SITE="${BORA_SITE_ENV:-/c/Users/danil/Desktop/bora-site/.env}"

if [ ! -d "$PASTA" ]; then
  echo "ERRO: pasta '$PASTA' não existe."
  echo "Corre primeiro ./buscar-build-web.sh (traz o build do CI)."
  exit 1
fi

if [ ! -f "$PASTA/index.html" ]; then
  echo "ERRO: '$PASTA' não parece um build web (falta index.html)."
  exit 1
fi

if [ ! -f "$ENV_SITE" ]; then
  echo "ERRO: não encontrei o .env com o CLOUDFLARE_API_TOKEN em: $ENV_SITE"
  echo "Define BORA_SITE_ENV=<caminho> se estiver noutro sítio."
  exit 1
fi

# Lê só a chave que interessa; não exporta o ficheiro todo nem o imprime.
CLOUDFLARE_API_TOKEN="$(grep -E '^CLOUDFLARE_API_TOKEN=' "$ENV_SITE" | head -1 | cut -d= -f2- | tr -d '\r\n"'"'"'')"
if [ -z "$CLOUDFLARE_API_TOKEN" ]; then
  echo "ERRO: CLOUDFLARE_API_TOKEN vazio em $ENV_SITE"
  exit 1
fi
export CLOUDFLARE_API_TOKEN
echo "Token lido de $ENV_SITE (não é impresso)."

echo "A publicar '$PASTA' em Cloudflare Pages / $PROJETO ..."
npx --yes wrangler@latest pages deploy "$PASTA" \
  --project-name="$PROJETO" \
  --branch=main \
  --commit-dirty=true

echo
echo "Feito. URL esperada: https://$PROJETO.pages.dev"

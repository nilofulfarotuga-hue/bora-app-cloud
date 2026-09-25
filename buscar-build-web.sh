#!/usr/bin/env bash
# Traz para ./build/web o build web compilado pelo CI.
#
# Existe porque esta máquina (4 GB de RAM) não consegue compilar para web
# — o dart2js falha com "Could not start thread DartWorker" — e o `gh` não
# está autenticado aqui, por isso também não dá para descarregar artifacts.
#
# O workflow build_web_deploy.yml resolve isso publicando o resultado numa
# branch órfã de um só commit (`web-build`), que se busca por git normal.
set -euo pipefail

REPO="${BORA_REPO_URL:-https://github.com/nilofulfarotuga-hue/bora-app-cloud.git}"
BRANCH="web-build"
DESTINO="build/web"

echo "A buscar a branch '$BRANCH' de $REPO ..."
git fetch --depth=1 "$REPO" "$BRANCH"

rm -rf "$DESTINO"
mkdir -p "$DESTINO"
git archive FETCH_HEAD | tar -x -C "$DESTINO"

if [ ! -f "$DESTINO/index.html" ]; then
  echo "ERRO: a branch '$BRANCH' não trouxe um index.html."
  exit 1
fi

echo "Build em $DESTINO:"
ls "$DESTINO" | head -12
if [ -f "$DESTINO/versao.json" ]; then
  echo "Versão: $(cat "$DESTINO/versao.json")"
fi
echo
echo "Agora: ./deploy-web.sh"

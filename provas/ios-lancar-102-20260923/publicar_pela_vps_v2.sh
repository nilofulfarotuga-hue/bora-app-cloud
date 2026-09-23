#!/bin/bash
# Empurra um commit do PC pelo clone da VPS, que tem a credencial a serio.
#
# Porque a VPS: o PC nao tem credencial do GitHub nenhuma -- `git credential
# fill` falha com "Unable to persist credentials with the 'wincredman'
# credential store" e nao ha TTY para o GCM abrir janela. A credencial real e'
# a chave de deploy SSH que vive no clone da VPS.
#
# v2 (2026-09-23): igual ao v1, mas parametrizado -- o v1 tinha o SHA e o pai
# cravados no corpo, o que obrigava a reescrever o ficheiro a cada commit.
#
#   ./publicar_pela_vps_v2.sh <sha> <pai-esperado> [bundle] [ramo]
#
# Nao toca na arvore de trabalho do clone: o commit entra por bundle e o push
# e' feito pelo SHA, sem checkout nem merge. Se o ramo se tiver mexido desde
# que fizemos o commit, PARA -- empurrar as cegas podia atropelar outra sessao.
set -euo pipefail

SHA="${1:?falta o sha do commit a empurrar}"
PAI="${2:?falta o sha que se espera encontrar no GitHub}"
BUNDLE="${3:-/tmp/ios102-prova.bundle}"
RAMO="${4:-autonomous-night-2026-04-29}"
REPO=/docker/hermes-agent-fvnc/data/bora-app-cloud

cd "$REPO"

echo "== 1. buscar o estado actual do ramo no GitHub"
git fetch origin "$RAMO"
REMOTO=$(git rev-parse "origin/$RAMO")
echo "   origin/$RAMO = $REMOTO"

if [ "$REMOTO" != "$PAI" ]; then
  echo "PARO: o ramo mexeu-se. Esperava $PAI, esta em $REMOTO."
  echo "Empurrar agora podia atropelar trabalho de outra sessao."
  exit 3
fi

echo "== 2. meter o commit do PC (bundle) neste clone"
git fetch "$BUNDLE" "refs/heads/$RAMO:refs/remotes/pc/empurrar"
git rev-parse refs/remotes/pc/empurrar

echo "== 3. confirmar que e' fast-forward"
git merge-base --is-ancestor "$REMOTO" "$SHA"
echo "   ok: $REMOTO e' ancestral de $SHA"

echo "== 4. o que viaja"
git diff --name-only "$REMOTO" "$SHA"

echo "== 5. empurrar (sem --force)"
git push origin "$SHA:refs/heads/$RAMO"

echo "== 6. prova: o que o GitHub tem agora"
git fetch origin "$RAMO"
git log -1 --oneline "origin/$RAMO"
test "$(git rev-parse "origin/$RAMO")" = "$SHA" && echo "CONFIRMADO: o GitHub esta em $SHA"

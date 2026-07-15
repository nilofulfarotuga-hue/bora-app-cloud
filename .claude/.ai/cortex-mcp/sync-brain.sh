#!/bin/sh
# B0 — espelha o Córtex (branch autonomous-night) para /opt/data/cortex-brain DENTRO do container.
# Diretório DEDICADO (não mexe nas clones de trabalho do Hermes noutras branches).
#
# Master no host: /root/cortex-mcp/sync-brain.sh — corre via stdin no container:
#   docker exec -u hermes -e HOME=/opt/data -i <C> sh -s [modo] < /root/cortex-mcp/sync-brain.sh
#
# MODOS:
#   hard  (default) — cron de madrugada (06h30): fetch + reset --hard. Autoritário / rede de
#                     segurança. Descarta edições locais (inclui a fila orquestracao/) — OK à noite.
#   fast            — por-tarefa (carteiro após cada push): fetch --depth 1 + checkout direto da
#                     árvore de FETCH_HEAD (SEM merge — um fetch --depth 1 novo a cada chamada gera
#                     sempre um shallow tip desligado do anterior, logo 'merge --ff-only' falha
#                     SEMPRE com "unrelated histories"; corrigido 2026-07-15, ver run cura-20260715-1
#                     em e2e_log). PRESERVA a fila orquestracao/ (16 ficheiros TRACKED — alguns com
#                     edições locais não commitadas — mais o resto untracked; excluída inteira do
#                     checkout) para o carteiro não a ver rebobinada → não re-executa ordens.
#
# Auth: SEMPRE deploy key SSH (/opt/data/.secrets/cortex_deploy_ed25519) — NUNCA PAT em URL.
set -e
MODE="${1:-hard}"
BR=autonomous-night-2026-04-29
DST=/opt/data/cortex-brain
KEY=/opt/data/.secrets/cortex_deploy_ed25519
KNOWN=/opt/data/.secrets/known_hosts
REMOTE=git@github.com:nilofulfarotuga-hue/bora-app-cloud.git
export GIT_SSH_COMMAND="ssh -i $KEY -o IdentitiesOnly=yes -o UserKnownHostsFile=$KNOWN -o StrictHostKeyChecking=yes"

if [ ! -d "$DST/.git" ]; then
  git clone --branch "$BR" --single-branch --depth 1 "$REMOTE" "$DST"
else
  git -C "$DST" remote set-url origin "$REMOTE"   # garante SSH deploy key (nunca PAT), idempotente
  git -C "$DST" fetch --depth 1 origin "$BR"
  if [ "$MODE" = "fast" ]; then
    git -C "$DST" checkout -f FETCH_HEAD -- . ':(exclude)orquestracao'
    git -C "$DST" update-ref "refs/heads/$BR" FETCH_HEAD
  else
    git -C "$DST" reset --hard "origin/$BR"
  fi
fi
echo "brain @ $(git -C "$DST" rev-parse --short HEAD) (modo=$MODE)"

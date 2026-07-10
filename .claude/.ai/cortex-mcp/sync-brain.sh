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
#   fast            — por-tarefa (carteiro após cada push): fetch + merge --ff-only. PRESERVA a
#                     fila orquestracao/ que o carteiro edita localmente (não a rebobina → não
#                     re-executa ordens). Se não der ff (árvore suja no caminho) refresca só o
#                     knowledge/ (o Claude.ai lê CONTEÚDO, não o SHA) e deixa o cron reconciliar.
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
    if ! git -C "$DST" merge --ff-only "origin/$BR" 2>/dev/null; then
      # ff falhou (fila/knowledge local sujo no caminho) — refresca o conteúdo do knowledge na mesma
      git -C "$DST" checkout -f "origin/$BR" -- .claude/.ai/knowledge 2>/dev/null \
        || echo "[sync fast] ff falhou; cron de madrugada reconcilia"
    fi
  else
    git -C "$DST" reset --hard "origin/$BR"
  fi
fi
echo "brain @ $(git -C "$DST" rev-parse --short HEAD) (modo=$MODE)"

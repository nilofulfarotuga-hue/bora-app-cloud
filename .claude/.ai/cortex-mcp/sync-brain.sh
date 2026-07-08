#!/bin/sh
# B0 — espelha o Córtex (branch autonomous-night) para /opt/data/cortex-brain DENTRO do container.
# Diretório DEDICADO (não mexe nas clones de trabalho do Hermes noutras branches).
# Corre via: docker exec -u hermes hermes-agent-fvnc-hermes-agent-1 sh /opt/data/cortex-mcp/sync-brain.sh
set -e
BR=autonomous-night-2026-04-29
DST=/opt/data/cortex-brain
# reutiliza o remote (com credencial já existente) de uma clone do mesmo repo
REMOTE=$(git -C /opt/data/bora-work remote get-url origin 2>/dev/null || git -C /opt/data/bora-app-cloud remote get-url origin)
if [ ! -d "$DST/.git" ]; then
  git clone --branch "$BR" --single-branch --depth 1 "$REMOTE" "$DST"
else
  git -C "$DST" fetch --depth 1 origin "$BR" && git -C "$DST" reset --hard "origin/$BR"
fi
echo "brain @ $(git -C "$DST" rev-parse --short HEAD)"
echo "knowledge tem: $(ls "$DST/.claude/.ai/knowledge" | tr '\n' ' ')"

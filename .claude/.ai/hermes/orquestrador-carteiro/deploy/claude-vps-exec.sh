#!/bin/bash
# claude-vps-exec.sh — executor headless na VPS (chamado por carteiro.sh via vps_exec()).
# 2026-07-14 (ordem 08db, corrige rc=127/SAIDA-VAZIA/"diagnosticou mas nao executou"): o
# --dangerously-skip-permissions do Claude Code recusa correr como root/sudo por seguranca, por
# isso a tarefa real corre como o utilizador nao-root hermes-exec (uid 10000, o mesmo dono do
# clone do repo em /docker/hermes-agent-fvnc/data/bora-app-cloud). O runner com o GUARD/tetos
# (paridade com run-claude-loop.cmd do PC) vive em /home/hermes-exec/.vps-exec-runner.sh.
TASKFILE=$(mktemp /tmp/vps-exec-task.XXXXXX)
cat > "$TASKFILE"
chown hermes-exec:hermes-exec "$TASKFILE"
chmod 600 "$TASKFILE"

MODEL=sonnet
grep -qF "[MODELO: OPUS]" "$TASKFILE" && MODEL=opus

/usr/sbin/runuser -u hermes-exec -- bash /home/hermes-exec/.vps-exec-runner.sh "$TASKFILE" "$MODEL"
RC=$?
rm -f "$TASKFILE"
exit $RC

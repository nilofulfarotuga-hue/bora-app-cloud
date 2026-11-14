#!/usr/bin/env bash
# sincroniza-memoria-claude.sh — espelha public.claude_ai_memoria no Cortex, de 30 em 30 min (minutos 7 e 37).
# Missao portas-13-09 (2026-09-13). A verdade vive na TABELA; isto e' so um espelho.
# Corre no HOST (cron root): a service key existe so em /opt/whatsapp-bora/.env (nunca se imprime).
#
# 14/11/2026 (missao sistema-conteudo-14-11, bloco 0.2): o bora-app-cloud e' PUBLICO. O espelho deixou de
# fazer commit/push nele. As paginas continuam a ser escritas na pasta do Cortex (cortex-brain, so leitura
# local do Cortex; a pasta esta no .gitignore do repo) e o historico vai para o repositorio PRIVADO
# nilofulfarotuga-hue/bora-livro (sem CI, custo zero), com a deploy key propria
# /opt/data/.secrets/bora_livro_deploy_ed25519. Copia anterior: sincroniza-memoria-claude.sh.bak-20261114.
# O git corre DENTRO do contentor como hermes (uid 10000). Nunca root a escrever num .git do contentor.
set -uo pipefail
ENVF=/opt/whatsapp-bora/.env
C=hermes-agent-fvnc-hermes-agent-1
HOSTBRAIN=/docker/hermes-agent-fvnc/data/cortex-brain
REL=.claude/.ai/knowledge/permanente/memoria-claude-ai
DST="$HOSTBRAIN/$REL"
HOSTLIVRO=/docker/hermes-agent-fvnc/data/bora-livro
LOG=/opt/data/bin/sincroniza-memoria-claude.log
ts(){ date -u +%FT%TZ; }
log(){ echo "[$(ts)] $*" >> "$LOG"; }
[ -r "$ENVF" ] || { log "ERRO: $ENVF ilegivel"; exit 1; }
mkdir -p "$DST"
# 29/10 (final-app-2026-10-29, bloco 8): livro-indice VIVO antes do espelho. Falha aqui nunca trava o espelho.
python3 /opt/data/bin/livro_indice.py >> "$LOG" 2>&1 || log "AVISO: livro_indice falhou (o espelho segue)"
N=$(python3 /opt/data/bin/_sincroniza_memoria_claude.py "$ENVF" "$DST" 2>>"$LOG") || { log "ERRO: python falhou (ver linha acima)"; exit 1; }
chown -R 10000:10000 "$DST"
# Copia para o repositorio privado (paginas/ = espelho exato da pasta do Cortex, com remocoes).
if [ -d "$HOSTLIVRO/.git" ]; then
  mkdir -p "$HOSTLIVRO/paginas"
  rsync -a --delete "$DST/" "$HOSTLIVRO/paginas/" 2>>"$LOG" || log "AVISO: rsync para bora-livro falhou"
  chown -R 10000:10000 "$HOSTLIVRO/paginas"
  OUT=$(docker exec -u hermes -e HOME=/opt/data "$C" bash -c '
    set -u; cd /opt/data/bora-livro || exit 2
    export GIT_SSH_COMMAND="ssh -i /opt/data/.secrets/bora_livro_deploy_ed25519 -o IdentitiesOnly=yes -o UserKnownHostsFile=/opt/data/.secrets/known_hosts -o StrictHostKeyChecking=yes"
    if [ -z "$(git status --porcelain -- paginas)" ]; then echo sem-alteracoes; exit 0; fi
    git add -A -- paginas || exit 3
    git -c user.name=sincroniza-memoria-claude -c user.email=emerson@bora.local commit -q -m "livro: espelho claude_ai_memoria $(date -u +%FT%TZ)" -- paginas || exit 4
    if git push -q origin HEAD:main 2>/dev/null; then echo livro-commit+push-ok; else echo livro-commit-ok-push-FALHOU; fi
  ' 2>&1)
else
  OUT="bora-livro-sem-clone"
  log "AVISO: $HOSTLIVRO nao e' um clone git (o espelho privado nao correu)"
fi
# 29/10: export plano LIVRO.md (para ferramentas sem MCP), servido atras de Basic Auth. Fora do git.
python3 /opt/data/bin/livro_export.py >> "$LOG" 2>&1 || log "AVISO: livro_export falhou (LIVRO.md anterior mantido)"
log "OK paginas_alteradas=$N git=$OUT"
echo "paginas_alteradas=$N git=$OUT"

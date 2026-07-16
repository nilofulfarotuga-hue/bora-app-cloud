#!/usr/bin/env bash
# --- STOP GLOBAL (reengenharia 2026-07-12): respeita .pausa-total ---
[ -f /docker/hermes-agent-fvnc/data/cortex-brain/orquestracao/.pausa-total ] && exit 0
# hermes-cortex-proposals-sync.sh — espelha proposals.jsonl (fila zona-vermelha do cortex-mcp) para
# a tabela cortex_red_proposals (Supabase), só LEITURA do .jsonl + INSERT idempotente (ON CONFLICT
# DO NOTHING via RPC cortex_proposal_sync_upsert, chave anon).
#
# NÃO liga a robot_suggestions/aprovador-vermelho (tabela e RPCs completamente separadas — sem
# nenhum cron a ler cortex_red_proposals.status='nova' e agir sozinho). NÃO aprova nem executa
# nada. NÃO toca/reinicia o cortex-mcp (server.mjs) — só lê o ficheiro que ele já escreve.
# Reenviar o ficheiro inteiro em cada corrida é seguro: a RPC ignora pids já existentes.
#
# Canónico no repo: bora_app/.claude/scripts/. Instalado em /usr/local/bin/ no VPS.
# Cron: */10 * * * * /usr/local/bin/hermes-cortex-proposals-sync.sh >> .../cortex-proposals-sync.log 2>&1
set -u

ENV=/docker/hermes-agent-fvnc/data/.env
SRC=/docker/hermes-agent-fvnc/data/cortex-brain/.claude/.ai/knowledge/inbox/_reports/proposals.jsonl
LOG=/root/orquestracao/cortex-proposals-sync.log

ts(){ date -u +%FT%TZ; }
log(){ echo "[$(ts)] $*" >> "$LOG"; }

[ -f "$SRC" ] || { log "sem $SRC — nada a sincronizar"; exit 0; }

URL=$(grep -E '^SUPABASE_URL=' "$ENV" 2>/dev/null | head -1 | cut -d= -f2- | tr -d '"'\''\r')
KEY=$(grep -E '^SUPABASE_ANON_KEY=' "$ENV" 2>/dev/null | head -1 | cut -d= -f2- | tr -d '"'\''\r')
[ -n "$URL" ] && [ -n "$KEY" ] || { log "sem SUPABASE_URL/ANON_KEY em $ENV — saio"; exit 0; }

sent=0
fail=0
while IFS= read -r line; do
  [ -n "$line" ] || continue

  payload=$(printf '%s' "$line" | python3 -c "
import json, sys
try:
    d = json.load(sys.stdin)
except Exception:
    sys.exit(1)
pid = d.get('pid')
if not pid:
    sys.exit(1)
out = {
    'p_pid': pid,
    'p_ordem_id': d.get('id'),
    'p_tipo': d.get('tipo'),
    'p_zona': d.get('zona'),
    'p_tarefa': d.get('tarefa') or d.get('conteudo') or '',
    'p_who': d.get('who'),
    'p_criada_em': d.get('ts'),
}
print(json.dumps(out))
" 2>>"$LOG")
  rc=$?
  if [ $rc -ne 0 ] || [ -z "$payload" ]; then
    fail=$((fail + 1))
    continue
  fi

  resp=$(curl -s --max-time 15 -X POST "$URL/rest/v1/rpc/cortex_proposal_sync_upsert" \
    -H "apikey: $KEY" -H "Authorization: Bearer $KEY" -H "Content-Type: application/json" \
    -d "$payload")

  if [ -n "$resp" ] && printf '%s' "$resp" | grep -q '"message"'; then
    fail=$((fail + 1))
    pid=$(printf '%s' "$line" | python3 -c 'import json,sys
try:
    print(json.load(sys.stdin).get("pid","?"))
except Exception:
    print("?")' 2>/dev/null)
    log "falhou pid=$pid: $resp"
  else
    sent=$((sent + 1))
  fi
done < "$SRC"

log "sync terminado: $sent linha(s) processada(s), $fail falha(s)"

#!/usr/bin/env bash
# --- STOP GLOBAL (reengenharia 2026-07-12): respeita .pausa-total ---
[ -f /docker/hermes-agent-fvnc/data/cortex-brain/orquestracao/.pausa-total ] && exit 0
# hermes-cortex-proposals-sync.sh — 2 passos sobre a fila zona-vermelha do cortex-mcp:
#   Passo 1: espelha proposals.jsonl para cortex_red_proposals (Supabase), só LEITURA do .jsonl +
#            INSERT idempotente (ON CONFLICT DO NOTHING via cortex_proposal_sync_upsert, anon).
#   Passo 2: propostas que o Danilo aprovou na Central (status=aprovada_danilo, autenticado,
#            _admin_op_guard — ver migration cortex_proposal_approve) e ainda não têm ordem
#            criada -> escreve a ordem real na fila (zona: verde). O texto da tarefa vem SEMPRE
#            do $SRC local (mesmo host) — a chave anon nunca lê conteúdo de proposta nenhuma
#            (cortex_list_approved_pids devolve só pids, igual ao red_queue_watermark).
#            A ordem criada passa pelo caminho normal: carteiro -> zona_vermelha() PRÓPRIA do
#            carteiro reavalia o TEXTO a cada pickup, independente do que `zona:` diga aqui —
#            conteúdo de dinheiro volta a exigir humano (Telegram "vai <id>"). Depois: executor
#            -> Juiz (zonas_diff.py). Nenhuma barreira existente foi tocada.
#
# NÃO liga a robot_suggestions/aprovador-vermelho (tabela e RPCs completamente separadas — sem
# nenhum cron a ler cortex_red_proposals.status='nova' e agir sozinho). NÃO toca/reinicia o
# cortex-mcp (server.mjs). Reenviar o passo 1 inteiro em cada corrida é seguro (idempotente); o
# passo 2 só cria cada ordem uma vez (guarda ordem_criada_em via cortex_mark_ordem_criada).
#
# Canónico no repo: bora_app/.claude/scripts/. Instalado em /usr/local/bin/ no VPS.
# Cron: */10 * * * * /usr/local/bin/hermes-cortex-proposals-sync.sh >> .../cortex-proposals-sync.log 2>&1
set -u

ENV=/docker/hermes-agent-fvnc/data/.env
SRC=/docker/hermes-agent-fvnc/data/cortex-brain/.claude/.ai/knowledge/inbox/_reports/proposals.jsonl
FILA=/docker/hermes-agent-fvnc/data/cortex-brain/orquestracao
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

# --- Passo 2: propostas aprovadas pelo Danilo (Central) -> ordem real na fila ---------------
# Feito inteiramente em Python (nunca interpola $tarefa no shell) — o texto da tarefa é
# conteúdo de terceiros (proposta gerada por sessão de chat) e pode conter aspas, `$(...)`,
# backticks, etc.; interpolar isso num heredoc de bash seria uma porta de injeção de comandos.
approved=$(curl -s --max-time 15 -X POST "$URL/rest/v1/rpc/cortex_list_approved_pids" \
  -H "apikey: $KEY" -H "Authorization: Bearer $KEY" -H "Content-Type: application/json" -d '{}')

# "python3 - <<heredoc" consumiria o próprio stdin como código-fonte, colidindo com o
# "$approved" que precisamos de lhe alimentar pelo stdin — por isso o script vai para um
# ficheiro à parte e só DEPOIS o stdin fica livre para os dados.
PYSCRIPT="/tmp/cortex-approve-step.$$.py"
cat > "$PYSCRIPT" <<'PYEOF'
import json, sys, re, subprocess, datetime, os

src, fila, url, key, logpath = sys.argv[1:6]

def log(msg):
    ts = datetime.datetime.now(datetime.timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ')
    with open(logpath, 'a', encoding='utf-8') as f:
        f.write(f"[{ts}] {msg}\n")

try:
    approved = json.loads(sys.stdin.read() or '[]')
except Exception:
    approved = []
pids = [(p.get('pid') if isinstance(p, dict) else p) for p in (approved or [])]
pids = [p for p in pids if p]
if not pids:
    sys.exit(0)

by_pid = {}
try:
    with open(src, encoding='utf-8') as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            try:
                d = json.loads(line)
            except Exception:
                continue
            if d.get('pid'):
                by_pid[d['pid']] = d
except FileNotFoundError:
    sys.exit(0)

for pid in pids:
    d = by_pid.get(pid)
    if not d:
        log(f"aprovada pid={pid} mas nao encontrada em {src} - salto")
        continue
    ordem_id = d.get('id') or ('ordem-' + pid)
    tarefa = (d.get('tarefa') or d.get('conteudo') or '').strip()
    if not tarefa:
        log(f"aprovada pid={pid}: tarefa vazia - salto")
        continue

    oid_safe = re.sub(r'[^a-zA-Z0-9_-]', '-', str(ordem_id))[:80]
    destino = os.path.join(fila, f"{oid_safe}-aprovado.md")
    ts = datetime.datetime.now(datetime.timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ')

    if not os.path.exists(destino):
        conteudo = (
            "--- ordem ---\n"
            f"id: {oid_safe}-aprovado\n"
            "estado: aberta\n"
            "autor: cortex-red-approve (Danilo via Central)\n"
            f"criada: {ts}\n"
            "zona: verde\n"
            "tentativa: 1\n"
            "teto_tentativas: 5\n"
            f"tarefa: {tarefa}\n"
            "--- fim ---\n"
            f"nota: aprovada pelo Danilo via Central em {ts}, pid original {pid} - "
            "mesmo aprovada aqui, o carteiro reavalia zona_vermelha() no texto; conteudo de "
            'dinheiro volta a esperar humano (Telegram "vai <id>").\n'
        )
        with open(destino, 'w', encoding='utf-8') as f:
            f.write(conteudo)
        log(f"aprovada pid={pid}: ordem criada em {destino}")
    else:
        log(f"aprovada pid={pid}: {destino} ja existe - so confirmo")

    ack = subprocess.run(
        ["curl", "-s", "--max-time", "15", "-X", "POST",
         f"{url}/rest/v1/rpc/cortex_mark_ordem_criada",
         "-H", f"apikey: {key}", "-H", f"Authorization: Bearer {key}",
         "-H", "Content-Type: application/json",
         "-d", json.dumps({"p_pid": pid, "p_ordem_ficheiro": destino})],
        capture_output=True, text=True,
    )
    log(f"aprovada pid={pid}: marcada processada ({ack.stdout.strip()})")
PYEOF

printf '%s' "$approved" | python3 "$PYSCRIPT" "$SRC" "$FILA" "$URL" "$KEY" "$LOG" 2>>"$LOG"
rm -f "$PYSCRIPT"

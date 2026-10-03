#!/usr/bin/env bash
# ============================================================================
# SELFTEST — protege-banco.sh (TRAVA BORA)
# Corre o hook contra payloads sintéticos e valida bloqueio (exit 2) vs passagem
# (exit 0). NÃO executa nada real. Uso: bash .claude/scripts/selftest_protege_banco.sh
# Nota: os payloads vivem DENTRO deste ficheiro, por isso o meta-hook PreToolUse
# não é disparado pelo comando `bash <este ficheiro>` (que não tem gatilhos).
# ============================================================================
set +e
# Hook a testar: arg $1, ou o hook oficial por defeito.
HOOK="${1:-$(dirname "$0")/../hooks/protege-banco.sh}"
if [ ! -f "$HOOK" ]; then echo "AUSENTE: $HOOK nao encontrado"; exit 3; fi
echo "== a testar hook: $HOOK =="

pass=0; fail=0
run() { # desc | expected_exit | json
  local desc="$1" exp="$2" json="$3" rc
  printf '%s' "$json" | bash "$HOOK" >/dev/null 2>&1
  rc=$?
  if [ "$rc" = "$exp" ]; then echo "OK    [$desc] exit=$rc"; pass=$((pass+1));
  else echo "FALHA [$desc] exit=$rc esperado=$exp"; fail=$((fail+1)); fi
}

G='\x67it reset --hard HEAD~1'   # gatilhos escapados so por precaucao visual
# --- BLOQUEAR (exit 2) ---
run "git reset hard"        2 '{"tool_name":"Bash","tool_input":{"command":"git re'"set"' --hard HEAD~1"}}'
run "git push force"        2 '{"tool_name":"Bash","tool_input":{"command":"git push --force origin main"}}'
run "supabase db reset"     2 '{"tool_name":"Bash","tool_input":{"command":"supabase db re'"set"'"}}'
run "deploy edge protegida" 2 '{"tool_name":"mcp__claude_ai_Supabase__deploy_edge_function","tool_input":{"name":"stripe-webhook"}}'
run "DROP tabela fin"       2 '{"tool_name":"mcp__claude_ai_Supabase__execute_sql","tool_input":{"query":"DROP TABLE ledger_entries;"}}'
run "DDL money fn"          2 '{"tool_name":"mcp__claude_ai_Supabase__execute_sql","tool_input":{"query":"CREATE OR REPLACE FUNCTION create_order() RETURNS void AS $$ $$ LANGUAGE sql;"}}'
run "DISABLE RLS fin"       2 '{"tool_name":"mcp__claude_ai_Supabase__execute_sql","tool_input":{"query":"ALTER TABLE wallets DISABLE ROW LEVEL SECURITY;"}}'
# --- DEIXAR PASSAR (exit 0) ---
run "deploy edge NAO-prot"  0 '{"tool_name":"mcp__claude_ai_Supabase__deploy_edge_function","tool_input":{"name":"notify-partner"}}'
run "SELECT normal"         0 '{"tool_name":"mcp__claude_ai_Supabase__execute_sql","tool_input":{"query":"SELECT * FROM orders LIMIT 5;"}}'
run "git push normal"       0 '{"tool_name":"Bash","tool_input":{"command":"git push origin main"}}'
run "commit palavra drop"   0 '{"tool_name":"Bash","tool_input":{"command":"git commit -m fix-drop-unused-import"}}'
run "migration normal"      0 '{"tool_name":"mcp__claude_ai_Supabase__apply_migration","tool_input":{"query":"CREATE TABLE foo (id int);"}}'

echo "===== TOTAL: pass=$pass fail=$fail ====="
[ "$fail" = "0" ] && exit 0 || exit 1

#!/usr/bin/env bash
# Testes F1.6 da Trava — protege-banco.sh
# Envia payloads JSON no formato PreToolUse do Claude Code.
set +e
cd "$(dirname "$0")/../../.."

pass=0; fail=0
t() {
  local desc="$1"; local tool="$2"; local key="$3"; local value="$4"; local expected="$5"
  local payload
  payload=$(printf '{"tool_name":"%s","tool_input":{"%s":%s}}' "$tool" "$key" "$value")
  local out code
  out=$(printf '%s' "$payload" | bash .claude/hooks/protege-banco.sh 2>&1)
  code=$?
  if [ "$expected" = "DENY" ] && [ "$code" = "2" ]; then
    pass=$((pass+1)); echo "PASS [deny]   $desc (exit=$code)"
  elif [ "$expected" = "PASS" ] && [ "$code" = "0" ]; then
    pass=$((pass+1)); echo "PASS [allow]  $desc (exit=$code)"
  else
    fail=$((fail+1)); echo "FAIL [want=$expected got=$code] $desc -- out: $out"
  fi
}

q() { printf '"%s"' "$1"; }

echo "=== F1.6 Testes da Trava: protege-banco.sh (contexto MCP Supabase) ==="

# --- DROP/TRUNCATE Cortex (deve negar — novas tabelas FINTABLE) ---
t "DROP cortex_tasks (MCP)"          "mcp__claude_ai_Supabase__execute_sql" "query" "$(q 'DROP TABLE cortex_tasks;')"             DENY
t "DROP cortex_task_messages (MCP)"   "mcp__claude_ai_Supabase__execute_sql" "query" "$(q 'DROP TABLE cortex_task_messages;')"     DENY
t "DROP cortex_task_consensus_meta"  "mcp__claude_ai_Supabase__execute_sql" "query" "$(q 'DROP TABLE cortex_task_consensus_meta;')" DENY
t "DROP llm_call_log (MCP)"          "mcp__claude_ai_Supabase__execute_sql" "query" "$(q 'DROP TABLE llm_call_log;')"              DENY
t "DROP agent_events (MCP)"          "mcp__claude_ai_Supabase__execute_sql" "query" "$(q 'DROP TABLE agent_events;')"              DENY
t "DROP worktree_registry (MCP)"     "mcp__claude_ai_Supabase__execute_sql" "query" "$(q 'DROP TABLE worktree_registry;')"         DENY

# --- DROP/TRUNCATE Cortex via apply_migration ---
t "DROP cortex_tasks (apply_migration)" "mcp__claude_ai_Supabase__apply_migration" "name" "$(q 'drop cortex_tasks')" DENY
t "apply_migration DROP cortex_tasks"     "mcp__claude_ai_Supabase__apply_migration" "name" "$(q 'DROP TABLE cortex_tasks;')"       DENY

# --- DROP/TRUNCATE tabelas FINTABLE antigas (deve negar) ---
t "DROP orders (MCP)"                "mcp__claude_ai_Supabase__execute_sql" "query" "$(q 'DROP TABLE orders;')"                  DENY
t "DROP wallets (MCP)"               "mcp__claude_ai_Supabase__execute_sql" "query" "$(q 'DROP TABLE wallets;')"                 DENY
t "DROP bora_tokens (MCP)"           "mcp__claude_ai_Supabase__execute_sql" "query" "$(q 'DROP TABLE bora_tokens;')"          DENY
t "TRUNCATE orders (MCP)"            "mcp__claude_ai_Supabase__execute_sql" "query" "$(q 'TRUNCATE TABLE orders;')"             DENY

# --- DISABLE RLS ---
t "DISABLE RLS cortex_tasks (MCP)"    "mcp__claude_ai_Supabase__execute_sql" "query" "$(q 'ALTER TABLE cortex_tasks DISABLE ROW LEVEL SECURITY;')" DENY
t "DISABLE RLS orders (MCP)"         "mcp__claude_ai_Supabase__execute_sql" "query" "$(q 'ALTER TABLE orders DISABLE ROW LEVEL SECURITY;')"     DENY

# --- PASS-through (validacoes que devem permitir) ---
t "DROP users (nao FINTABLE)"         "mcp__claude_ai_Supabase__execute_sql" "query" "$(q 'DROP TABLE users;')"                  PASS
t "SELECT orders (permitir)"         "mcp__claude_ai_Supabase__execute_sql" "query" "$(q 'SELECT * FROM orders LIMIT 1;')"     PASS
t "CREATE OR REPLACE Cortex fn"      "mcp__claude_ai_Supabase__execute_sql" "query" "$(q 'CREATE OR REPLACE FUNCTION cortex_enqueue() RETURNS void AS \$\$ BEGIN END \$\$ LANGUAGE plpgsql;')" PASS
t "CREATE OR REPLACE \$ dinheiro fn" "mcp__claude_ai_Supabase__execute_sql" "query" "$(q 'CREATE OR REPLACE FUNCTION finalize_errand_purchase() RETURNS void AS \$\$ BEGIN END \$\$ LANGUAGE plpgsql;')" DENY

# --- Git destrutivo (independente de contexto SQL) ---
t "git reset --hard (Bash)"          "Bash" "command" "$(q 'git reset --hard HEAD~1')"                                    DENY
t "git push --force (Bash)"          "Bash" "command" "$(q 'git push --force origin main')"                                DENY
t "git push -f (Bash)"               "Bash" "command" "$(q 'git push -f origin main')"                                     DENY
t "git push --force-with-lease"     "Bash" "command" "$(q 'git push --force-with-lease origin main')"                      DENY
t "supabase db reset (Bash)"         "Bash" "command" "$(q 'supabase db reset')"                                          DENY
t "git push normal (Bash)"           "Bash" "command" "$(q 'git push origin main')"                                        PASS

# --- Deploy edge function protegida ---
t "deploy stripe-webhook"            "mcp__claude_ai_Supabase__deploy_edge_function" "name" "$(q 'stripe-webhook')"          DENY
t "deploy dispatch-engine"          "mcp__claude_ai_Supabase__deploy_edge_function" "name" "$(q 'dispatch-engine')"        DENY
t "deploy refund"                    "mcp__claude_ai_Supabase__deploy_edge_function" "name" "$(q 'refund')"                  DENY
t "deploy reprocess-refund"          "mcp__claude_ai_Supabase__deploy_edge_function" "name" "$(q 'reprocess-refund')"       DENY
t "deploy nao-protegida"             "mcp__claude_ai_Supabase__deploy_edge_function" "name" "$(q 'user-notifications')"     PASS

echo "=== Result: $pass pass, $fail fail ==="
exit $fail
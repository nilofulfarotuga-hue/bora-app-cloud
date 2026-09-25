#!/usr/bin/env bash
# Simula o hook protege-banco.sh contra a migration F2 final
# Confirma que o hook PERMITE apply (exit 0) e NAO bloqueia
set +e
cd "$(dirname "$0")/../../.."

pass=0; fail=0
check() {
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

# Le o conteudo da migration F2 final
SQL=$(cat supabase/migrations/20260809120000_PROPOSTA_cortex_tasks_f2.sql)

echo "=== F2 Trava sim — protege-banco.sh vs migration F2 final ==="

# 1. apply_migration com name = 'f2 cortex tasks' (deve PASS — contexto SQL mas
#    so CREATE TABLE/INDEX/FUNCTION, sem DROP/TRUNCATE de FINTABLE)
check "apply_migration(name f2 cortex tasks)" \
  "mcp__claude_ai_Supabase__apply_migration" "name" "$(q 'f2 cortex_tasks init')" PASS

# 2. apply_migration com query = SQL da migration (deve PASS — so creates)
check "apply_migration(query SQL cria cortex_tasks)" \
  "mcp__claude_ai_Supabase__apply_migration" "query" "$(printf '"%s"' "$(echo "$SQL" | sed 's/"/\\"/g')")" PASS

# 3. execute_sql com query = SQL da migration (deve PASS — so creates)
check "execute_sql(query SQL cria cortex_tasks)" \
  "mcp__claude_ai_Supabase__execute_sql" "query" "$(printf '"%s"' "$(echo "$SQL" | sed 's/"/\\"/g')")" PASS

# 4. Controlo negativo: DROP cortex_tasks explicito (deve DENY)
check "execute_sql(DROP cortex_tasks) [controlo negativo]" \
  "mcp__claude_ai_Supabase__execute_sql" "query" "$(q 'DROP TABLE cortex_tasks CASCADE;')" DENY

# 5. Controlo negativo: DISABLE RLS cortex_tasks (deve DENY)
check "execute_sql(DISABLE RLS cortex_tasks) [controlo negativo]" \
  "mcp__claude_ai_Supabase__execute_sql" "query" "$(q 'ALTER TABLE cortex_tasks DISABLE ROW LEVEL SECURITY;')" DENY

echo "=== Result: $pass pass, $fail fail ==="
exit $fail
// F2 — simula o protege-banco.sh contra a migration cortex_tasks (apply_migration).
// Confirma que a Trava PERMITE aplicar (exit 0) — sem falso-positivo do DOWN.
const fs = require('fs');
const path = require('path');
const { execFileSync } = require('child_process');

const root = path.resolve(__dirname, '..', '..', '..');
const mig = fs.readFileSync(path.join(root, 'supabase', 'migrations', '20260809120000_PROPOSTA_cortex_tasks_f2.sql'), 'utf8');

function runHook(toolName, toolInput) {
  const payload = JSON.stringify({ tool_name: toolName, tool_input: toolInput });
  let code = 0, out = '';
  try {
    out = execFileSync('C:\\Program Files\\Git\\bin\\bash.exe',
      [path.join(root, '.claude', 'hooks', 'protege-banco.sh')],
      { input: payload, encoding: 'utf8', stdio: ['pipe', 'pipe', 'pipe'] });
  } catch (e) {
    code = e.status ?? 1;
    out = (e.stdout || '') + (e.stderr || '');
  }
  return { code, out };
}

let pass = 0, fail = 0;
function check(desc, got, want) {
  if (got === want) { pass++; console.log(`PASS [exit=${got}] ${desc}`); }
  else { fail++; console.log(`FAIL [want=${want} got=${got}] ${desc}`); console.log('  out:', out.slice(0,200)); }
}

console.log('=== F2 Trava-sim: protege-banco.sh vs migration cortex_tasks ===');

// 1) apply_migration com a migration inteira como query -> deve PERMITIR (exit 0)
let r = runHook('mcp__claude_ai_Supabase__apply_migration',
  { name: 'create cortex_tasks f2', query: mig });
let out = r.out;
check('apply_migration cortex_tasks (corpo inteiro) PERMITIDO', r.code, 0);

// 2) execute_sql com o corpo ativo (sem comentarios DOWN) -> PERMITIDO
const active = mig.split('\n').filter(l => !l.trim().startsWith('--')).join('\n');
r = runHook('mcp__claude_ai_Supabase__execute_sql', { query: active });
out = r.out;
check('execute_sql corpo ativo PERMITIDO', r.code, 0);

// 3) sanity: DROP TABLE cortex_tasks direto (simular agente mau) -> BLOQUEADO
r = runHook('mcp__claude_ai_Supabase__execute_sql', { query: 'DROP TABLE cortex_tasks;' });
out = r.out;
check('execute_sql DROP cortex_tasks BLOQUEADO', r.code, 2);

// 4) sanity: DISABLE RLS cortex_tasks -> BLOQUEADO
r = runHook('mcp__claude_ai_Supabase__execute_sql', { query: 'ALTER TABLE cortex_tasks DISABLE ROW LEVEL SECURITY;' });
out = r.out;
check('execute_sql DISABLE RLS cortex_tasks BLOQUEADO', r.code, 2);

console.log(`=== Result: ${pass} pass, ${fail} fail ===`);
process.exit(fail ? 1 : 0);
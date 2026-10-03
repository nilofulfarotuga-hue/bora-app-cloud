// =============================================================================
// bora-mods · verificador das regras da tranca, FORA do Claude Code.
//   bun .claude/plugins/bora-mods/verificar/regras.verificar.ts
// Porque existe: o `claude plugin test` só corre com o interruptor remoto dos
// mods ligado (tengu_plugin_hooks_modules). Enquanto estiver desligado, este
// script prova a lógica da tranca com os ficheiros REAIS:
// zonas-vermelhas.json e .claude/hooks/protege-banco.sh.
// Sai com código 1 se alguma verificação falhar.
// =============================================================================
import { readFileSync } from 'node:fs'
import { dirname, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'

import { juntarLinha, pedidoE2e, telegramEntrou } from '../hooks/comum'
import {
  aprovaSemPerguntar,
  avaliaChamada,
  lerVarShell,
  semSegredos,
  type Contexto,
  type Zonas,
} from '../hooks/regras'

const aqui = dirname(fileURLToPath(import.meta.url))
const plugin = resolve(aqui, '..')
const raiz = resolve(plugin, '../../..').replace(/\\/g, '/')
const zonas = JSON.parse(readFileSync(resolve(plugin, 'zonas-vermelhas.json'), 'utf8')) as Zonas
const sh = readFileSync(resolve(raiz, '.claude/hooks/protege-banco.sh'), 'utf8')
const ctx: Contexto = {
  zonas,
  banco: { protslug: lerVarShell(sh, 'PROTSLUG'), moneyfn: lerVarShell(sh, 'MONEYFN') ?? '', fintable: lerVarShell(sh, 'FINTABLE') ?? '' },
  raiz,
}
const R = raiz

let ok = 0
let falhas = 0
function verifica(nome: string, condicao: boolean, detalhe = ''): void {
  if (condicao) {
    ok++
    console.log(`(pass) ${nome}`)
  } else {
    falhas++
    console.log(`(FAIL) ${nome} ${detalhe}`)
  }
}
const acao = (tool: string, args: Record<string, unknown>, c: Contexto = ctx) => avaliaChamada(tool, args, c)
const nega = (tool: string, args: Record<string, unknown>, re: RegExp, c: Contexto = ctx) => {
  const v = acao(tool, args, c)
  return v.acao === 'nega' && re.test(v.motivo)
}
const segue = (tool: string, args: Record<string, unknown>) => acao(tool, args).acao === 'segue'
const pergunta = (tool: string, args: Record<string, unknown>) => acao(tool, args).acao === 'pergunta'
const aprova = (tool: string, args: Record<string, unknown>) => aprovaSemPerguntar(tool, args, [R]) !== null

console.log(`listas reais: ${zonas.ficheiros.length} zonas · PROTSLUG ${ctx.banco.protslug ? 'lido' : 'EM FALTA'} · FINTABLE ${ctx.banco.fintable.split('|').length} tabelas`)

// ---- A · nega -------------------------------------------------------------------
verifica('nega: edit em lib/services/pricing_service.dart', nega('Edit', { file_path: `${R}/lib/services/pricing_service.dart`, old_string: 'a', new_string: 'b' }, /pricing_service/))
verifica('nega: edit em supabase/functions/dispatch-engine/index.ts (caminho Windows)', nega('Edit', { file_path: 'C:\\BoraLocal\\projetosflutter\\bora_app\\supabase\\functions\\dispatch-engine\\index.ts', old_string: 'a', new_string: 'b' }, /dispatch-engine/))
verifica('nega: edit em order_store.dart (finalizePurchase)', nega('Write', { file_path: `${R}/lib/stores/order_store.dart`, content: 'x' }, /finalizePurchase/))
verifica('nega: edit na própria tranca (bora-mods)', nega('Edit', { file_path: `${R}/.claude/plugins/bora-mods/hooks/tranca.ts`, old_string: 'a', new_string: 'b' }, /bora-mods/))
verifica('nega: edit no settings.json do utilizador', nega('Edit', { file_path: 'C:/Users/danil/.claude/settings.json', old_string: 'a', new_string: 'b' }, /settings/))
verifica('nega: git push --force', nega('Bash', { command: 'git push --force origin autonomous-night-2026-04-29' }, /push forçado/))
verifica('nega: git push -f origin x', nega('Bash', { command: 'git push -f origin x' }, /push forçado/))
verifica('nega: git push -qf (bandeira colada)', nega('Bash', { command: 'git push -qf origin x' }, /push forçado/))
verifica('nega: git push --force-with-lease', nega('PowerShell', { command: 'git push --force-with-lease' }, /push forçado/))
verifica('nega: git push origin +main (refspec com +)', nega('Bash', { command: 'git push origin +main' }, /push forçado/))
verifica('nega: timeout 5 git push --force', nega('Bash', { command: 'timeout 5 git push --force' }, /push forçado/))
verifica('nega: git -C pasta push -f', nega('Bash', { command: 'git -C /c/x push -f' }, /push forçado/))
verifica('nega: push forçado num heredoc entregue ao bash', nega('Bash', { command: 'bash <<EOF\ngit push --force origin x\nEOF' }, /push forçado/))
verifica('nega: push forçado dentro de bash -c "..."', nega('Bash', { command: 'bash -c "git push -f origin x"' }, /push forçado/))
verifica('nega: git add -A', nega('Bash', { command: 'git add -A' }, /git add/))
verifica('nega: git add . depois de &&', nega('Bash', { command: 'git status && git add .' }, /git add/))
verifica('nega: git reset --hard', nega('Bash', { command: 'git reset --hard HEAD~1' }, /reset --hard/))
verifica('nega: git checkout -- .', nega('Bash', { command: 'git checkout -- .' }, /checkout/))
verifica('nega: supabase db reset', nega('Bash', { command: 'supabase db reset --linked' }, /db reset/))
verifica('nega: rm -rf lib', nega('Bash', { command: 'rm -rf lib' }, /apagar recursivo/))
verifica('nega: rm -rf build/../lib (subir pasta)', nega('Bash', { command: 'rm -rf build/../lib' }, /apagar recursivo/))
verifica('nega: Remove-Item -Recurse fora de build', nega('PowerShell', { command: 'Remove-Item -Recurse -Force C:\\Users\\danil\\Desktop' }, /apagar recursivo/))
verifica('nega: DELETE FROM orders; (MCP)', nega('mcp__claude_ai_Supabase__execute_sql', { query: 'DELETE FROM orders;' }, /DELETE|direto/))
verifica('nega: DELETE FROM ledger_entries sem WHERE', nega('mcp__claude_ai_Supabase__execute_sql', { query: 'delete from ledger_entries' }, /DELETE|direto/))
verifica('nega: TRUNCATE bora_tokens', nega('mcp__claude_ai_Supabase__execute_sql', { query: 'truncate table public.bora_tokens' }, /TRUNCATE/))
verifica('nega: UPDATE direto em orders (regra 16/09)', nega('mcp__claude_ai_Supabase__execute_sql', { query: "update orders set assigned_driver_id='x' where id='1'" }, /ops_reassign_order/))
verifica('nega: UPDATE direto em drivers', nega('mcp__claude_ai_Supabase__execute_sql', { query: 'update public.drivers set is_online=false where id=1' }, /direto/))
verifica('nega: platform_settings de comissão', nega('mcp__claude_ai_Supabase__execute_sql', { query: "update platform_settings set value='9' where key='commission_pct'" }, /platform_settings/))
verifica('nega: DROP POLICY em orders', nega('mcp__claude_ai_Supabase__apply_migration', { name: 'm', query: 'drop policy "x" on public.orders;' }, /POLICY/))
verifica('nega: DISABLE RLS em wallets', nega('mcp__claude_ai_Supabase__apply_migration', { name: 'm', query: 'alter table wallets disable row level security' }, /ROW LEVEL/))
verifica('nega: CREATE OR REPLACE de apply_order_financial_split', nega('mcp__claude_ai_Supabase__apply_migration', { name: 'm', query: 'create or replace function public.apply_order_financial_split() returns void as $$ begin end $$ language plpgsql;' }, /função/))
verifica('nega: psql -c \'drop table wallets\' (SQL entre aspas no terminal)', nega('Bash', { command: "psql \"$DB\" -c 'drop table wallets'" }, /DROP TABLE/))
verifica('nega: deploy MCP de stripe-webhook', nega('mcp__claude_ai_Supabase__deploy_edge_function', { name: 'stripe-webhook', files: [] }, /protegida/))
verifica('nega: deploy MCP de refund', nega('mcp__claude_ai_Supabase__deploy_edge_function', { name: 'refund', files: [] }, /protegida/))
verifica('nega: deploy MCP de client-cancel-order (zona do JSON, fora do PROTSLUG)', nega('mcp__claude_ai_Supabase__deploy_edge_function', { name: 'client-cancel-order', files: [] }, /zona vermelha/))
verifica('nega: supabase functions deploy create-payment-intent', nega('Bash', { command: 'supabase functions deploy create-payment-intent --project-ref x' }, /protegida/))
verifica('nega: deploy sem PROTSLUG legível (fail-closed)', nega('mcp__claude_ai_Supabase__deploy_edge_function', { name: 'notify-partner' }, /PROTSLUG/, { ...ctx, banco: { ...ctx.banco, protslug: null } }))
verifica('nega: edit em .github/workflows/build_android.yml', nega('Edit', { file_path: `${R}/.github/workflows/build_android.yml`, old_string: 'a', new_string: 'b' }, /workflows/))
verifica('nega: pubspec.yaml version: mudado por Edit', nega('Edit', { file_path: `${R}/pubspec.yaml`, old_string: 'version: 1.0.4+636', new_string: 'version: 1.0.4+637' }, /CI incrementa/))
verifica('nega: pubspec.yaml version: mudado por Write', nega('Write', { file_path: `${R}/pubspec.yaml`, content: 'name: b\nversion: 2.0.0+1\n' }, /CI incrementa/, { ...ctx, pubspecAtual: 'name: b\nversion: 1.0.4+636\n' }))
verifica('nega: Write com SUPABASE_SERVICE_ROLE_KEY=', nega('Write', { file_path: `${R}/docs/notas.txt`, content: 'SUPABASE_SERVICE_ROLE_KEY=abcdefghijklmnopqrstuvwxyz123456' }, /segredo/))
verifica('nega: Write em .env', nega('Write', { file_path: `${R}/.env`, content: 'X=1' }, /segredos/))
verifica('nega: Write em android/app/upload.jks', nega('Write', { file_path: `${R}/android/app/upload.jks`, content: 'x' }, /segredos/))
verifica('nega: migration nova que mexe em bora_tokens', nega('Write', { file_path: `${R}/supabase/migrations/20261002_x.sql`, content: 'alter table bora_tokens add column x int;' }, /tokens/))
verifica('nega: curl com sk_live_ em texto claro', nega('Bash', { command: 'curl -H "Authorization: Bearer sk_live_51ABCDEFGHIJKLMNOP" https://api.stripe.com/v1/charges' }, /segredo/))
verifica('nega: curl com Authorization literal', nega('Bash', { command: 'curl -H "Authorization: Bearer abcdef123456789" https://x' }, /segredo/))
verifica('nega: zonas ilegíveis -> edições bloqueadas', nega('Write', { file_path: `${R}/lib/x.dart`, content: 'x' }, /ilegível/, { ...ctx, zonas: null }))
let rebentou = false
try {
  acao('Edit', { file_path: `${R}/lib/x.dart` }, { ...ctx, zonas: { ...zonas, ficheiros: [{ padrao: '(', motivo: 'x' }] } })
} catch {
  rebentou = true
}
verifica('fail-closed: zona com padrão estragado lança erro (o .catch do gancho nega)', rebentou)

// ---- passa ------------------------------------------------------------------------
verifica('passa: git commit -F - (heredoc) && git push -> pergunta, NÃO nega (falso positivo antigo)', pergunta('Bash', { command: "git commit -q -F - <<'MSG'\nfix: -f e --force no texto\nMSG\ngit push origin autonomous-night-2026-04-29" }))
verifica('passa: git commit -F - && git push numa linha -> pergunta', pergunta('Bash', { command: 'git commit -F - && git push origin autonomous-night-2026-04-29' }))
verifica('passa: mensagem com "--force" entre aspas', segue('Bash', { command: 'git commit -m "nunca usar git push --force"' }))
verifica('passa: edit em lib/screens/qualquer.dart', segue('Edit', { file_path: `${R}/lib/screens/qualquer.dart`, old_string: 'a', new_string: 'b' }))
verifica('passa: SELECT * FROM orders LIMIT 1', segue('mcp__claude_ai_Supabase__execute_sql', { query: 'SELECT * FROM orders LIMIT 1' }))
verifica('passa: INSERT no e2e_log (não é tabela de dinheiro)', segue('mcp__claude_ai_Supabase__execute_sql', { query: "insert into e2e_log (fluxo) values ('x')" }))
verifica('passa: flutter analyze', segue('Bash', { command: 'flutter analyze lib' }))
verifica('passa: rm -rf build/ .dart_tool', segue('Bash', { command: 'rm -rf build/ .dart_tool' }))
verifica('passa: pubspec com dependência nova, mesma versão', segue('Edit', { file_path: `${R}/pubspec.yaml`, old_string: '  http: ^1.0.0', new_string: '  http: ^1.1.0' }))
verifica('passa: comentário com DROP não é SQL destrutivo', segue('mcp__claude_ai_Supabase__execute_sql', { query: '-- drop table orders\nselect 1' }))

// ---- B · pergunta -----------------------------------------------------------------
verifica('pergunta: git push origin autonomous-night-2026-04-29', pergunta('Bash', { command: 'git push origin autonomous-night-2026-04-29' }))
verifica('pergunta: apply_migration normal', pergunta('mcp__claude_ai_Supabase__apply_migration', { name: 'm', query: 'create table public.x (id int);' }))
verifica('pergunta: deploy de notify-partner', pergunta('mcp__claude_ai_Supabase__deploy_edge_function', { name: 'notify-partner' }))
verifica('pergunta: CREATE INDEX por execute_sql', pergunta('mcp__claude_ai_Supabase__execute_sql', { query: 'create index x on public.e2e_log(run_id)' }))

// ---- C · aprova sem caixa ---------------------------------------------------------
verifica('aprova: Read', aprova('Read', { file_path: `${R}/README.md` }))
verifica('aprova: Grep', aprova('Grep', { pattern: 'x' }))
verifica('aprova: git status', aprova('Bash', { command: 'git status --porcelain' }))
verifica('aprova: git log | head', aprova('Bash', { command: 'git log --oneline -5 | head -3' }))
verifica('aprova: SELECT count(*)', aprova('mcp__claude_ai_Supabase__execute_sql', { query: "select count(*) from orders where status = 'delivered'" }))
verifica('aprova: Supabase list_tables', aprova('mcp__claude_ai_Supabase__list_tables', {}))
verifica('aprova: Córtex buscar', aprova('mcp__claude_ai_C_rtex_Bora__cortex_buscar', { query: 'x' }))
verifica('aprova: edit em lib/ (zona verde)', aprova('Edit', { file_path: `${R}/lib/screens/x.dart` }))
verifica('aprova: agente Explore', aprova('Agent', { subagent_type: 'Explore', prompt: 'x', description: 'x' }))
verifica('NÃO aprova: git status > ficheiro', !aprova('Bash', { command: 'git status > estado.txt' }))
verifica('NÃO aprova: git push', !aprova('Bash', { command: 'git push origin x' }))
verifica('NÃO aprova: git branch novo-ramo', !aprova('Bash', { command: 'git branch novo-ramo' }))
verifica('NÃO aprova: SELECT de função que escreve (ops_reassign_order)', !aprova('mcp__claude_ai_Supabase__execute_sql', { query: 'select public.ops_reassign_order(1,2,3,4)' }))
verifica('NÃO aprova: duas instruções (select; delete)', !aprova('mcp__claude_ai_Supabase__execute_sql', { query: 'select 1; delete from x' }))
verifica('NÃO aprova: WITH ... DELETE', !aprova('mcp__claude_ai_Supabase__execute_sql', { query: 'with a as (delete from x returning *) select * from a' }))
verifica('NÃO aprova: gh api -X POST', !aprova('Bash', { command: 'gh api -X POST repos/x/y/dispatches' }))
verifica('NÃO aprova: edit fora do repositório', !aprova('Edit', { file_path: 'C:/Users/danil/.bashrc' }))
verifica('NÃO aprova: agente geral (escreve)', !aprova('Agent', { subagent_type: 'general-purpose', prompt: 'x', description: 'x' }))

// ---- peças partilhadas ------------------------------------------------------------
verifica('log: esconde sk_live_ e JWT', !/sk_live_51AB|eyJhbGciOiJIUzI1/.test(semSegredos('curl -H "Authorization: Bearer sk_live_51ABCDEFGHIJ" x eyJhbGciOiJIUzI1NiJ9.eyJyb2xlIjoiYW5vbiJ9.abcdefghijk')))
verifica('log: junta uma linha JSON e guarda as últimas 2000', juntarLinha('a\n'.repeat(2005), { x: 1 }, 't').split('\n').filter(Boolean).length === 2000)
verifica('e2e_log: sem chave não há pedido', pedidoE2e({}, { passo: 'p', estado: 'e', detalhe: 'd' }) === null)
verifica('Telegram: 200 com "ok":false é falha', !telegramEntrou(true, '{"ok":false}') && telegramEntrou(true, '{"ok":true}'))

console.log(`\n${ok} verdes · ${falhas} vermelhas`)
if (falhas > 0) process.exit(1)

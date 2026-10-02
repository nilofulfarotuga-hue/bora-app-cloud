// =============================================================================
// bora-mods · testes da tranca (claude plugin test .claude/plugins/bora-mods)
// NEGA: nada chega ao fundo e a resposta traz `deny`.
// PASSA: a ferramenta chega ao fundo ("corridas").
// APROVA: o tool.check devolve `allow` sem perguntar.
// =============================================================================
import { describe, expect, test } from 'claude-code/testing'

import { dubles } from './apoio-testes'

const R = 'C:/BoraLocal/projetosflutter/bora_app'

describe('A · nega', () => {
  test('edit em lib/services/pricing_service.dart', async ($, on) => {
    const d = dubles(on)
    const r = await $.tool.call({ tool: 'Edit', file_path: `${R}/lib/services/pricing_service.dart`, old_string: 'a', new_string: 'b' })
    expect(r.deny).toMatch(/pricing_service/)
    expect(d.corridas).toEqual([])
  })

  test('edit em supabase/functions/dispatch-engine/index.ts', async ($, on) => {
    const d = dubles(on)
    const r = await $.tool.call({ tool: 'Edit', file_path: 'C:\\BoraLocal\\projetosflutter\\bora_app\\supabase\\functions\\dispatch-engine\\index.ts', old_string: 'a', new_string: 'b' })
    expect(r.deny).toMatch(/dispatch-engine/)
    expect(d.corridas).toEqual([])
  })

  test('git push --force', async ($, on) => {
    dubles(on)
    const r = await $.tool.call({ tool: 'Bash', command: 'git push --force origin autonomous-night-2026-04-29' })
    expect(r.deny).toMatch(/push forçado/)
  })

  test('git push -f origin x', async ($, on) => {
    dubles(on)
    const r = await $.tool.call({ tool: 'Bash', command: 'git push -f origin x' })
    expect(r.deny).toMatch(/push forçado/)
  })

  test('git push com refspec +', async ($, on) => {
    dubles(on)
    const r = await $.tool.call({ tool: 'PowerShell', command: 'git push origin +main' })
    expect(r.deny).toMatch(/push forçado/)
  })

  test('git push forçado escondido num heredoc entregue ao bash', async ($, on) => {
    dubles(on)
    const r = await $.tool.call({ tool: 'Bash', command: 'bash <<EOF\ngit push --force origin x\nEOF' })
    expect(r.deny).toMatch(/push forçado/)
  })

  test('git add -A e git add .', async ($, on) => {
    dubles(on)
    expect((await $.tool.call({ tool: 'Bash', command: 'git add -A' })).deny).toMatch(/git add/)
    expect((await $.tool.call({ tool: 'Bash', command: 'git status && git add .' })).deny).toMatch(/git add/)
  })

  test('git reset --hard e supabase db reset', async ($, on) => {
    dubles(on)
    expect((await $.tool.call({ tool: 'Bash', command: 'git reset --hard HEAD~1' })).deny).toMatch(/reset --hard/)
    expect((await $.tool.call({ tool: 'Bash', command: 'supabase db reset --linked' })).deny).toMatch(/db reset/)
  })

  test('rm -rf fora de build/ (e deixa apagar build/)', async ($, on) => {
    const d = dubles(on)
    expect((await $.tool.call({ tool: 'Bash', command: 'rm -rf lib' })).deny).toMatch(/apagar recursivo/)
    expect((await $.tool.call({ tool: 'PowerShell', command: 'Remove-Item -Recurse -Force C:\\Users\\danil' })).deny).toMatch(/apagar recursivo/)
    const ok = await $.tool.call({ tool: 'Bash', command: 'rm -rf build/ .dart_tool' })
    expect(ok.deny).toBeUndefined()
    expect(d.corridas).toEqual(['Bash'])
  })

  test('DELETE FROM orders; pelo MCP do Supabase', async ($, on) => {
    dubles(on)
    const r = await $.tool.call({ tool: 'mcp__claude_ai_Supabase__execute_sql', project_id: 'x', query: 'DELETE FROM orders;' })
    expect(r.deny).toMatch(/DELETE sem WHERE|direto/)
  })

  test('UPDATE direto em orders (regra 16/09) e DROP TABLE wallets no psql', async ($, on) => {
    dubles(on)
    const u = await $.tool.call({ tool: 'mcp__claude_ai_Supabase__execute_sql', project_id: 'x', query: "update orders set assigned_driver_id = 'x' where id = '1'" })
    expect(u.deny).toMatch(/ops_reassign_order/)
    const p = await $.tool.call({ tool: 'Bash', command: "psql \"$DB\" -c 'drop table wallets'" })
    expect(p.deny).toMatch(/DROP TABLE/)
  })

  test('DROP POLICY em orders e DDL em função de dinheiro', async ($, on) => {
    dubles(on)
    const a = await $.tool.call({ tool: 'mcp__claude_ai_Supabase__apply_migration', project_id: 'x', name: 'm', query: 'drop policy "x" on public.orders;' })
    expect(a.deny).toMatch(/POLICY/)
    const b = await $.tool.call({ tool: 'mcp__claude_ai_Supabase__apply_migration', project_id: 'x', name: 'm', query: 'create or replace function public.apply_order_financial_split() returns void as $$ begin end $$ language plpgsql;' })
    expect(b.deny).toMatch(/função\/trigger de dinheiro/)
  })

  test('deploy_edge_function de um slug PROTSLUG', async ($, on) => {
    dubles(on)
    const r = await $.tool.call({ tool: 'mcp__claude_ai_Supabase__deploy_edge_function', project_id: 'x', name: 'stripe-webhook', files: [] })
    expect(r.deny).toMatch(/protegida/)
  })

  test('deploy fica todo bloqueado se o protege-banco.sh não se ler (fail-closed)', async ($, on) => {
    dubles(on, { banco: null })
    const r = await $.tool.call({ tool: 'mcp__claude_ai_Supabase__deploy_edge_function', project_id: 'x', name: 'notify-partner', files: [] })
    expect(r.deny).toMatch(/PROTSLUG/)
  })

  test('edit em .github/workflows/build_android.yml', async ($, on) => {
    dubles(on)
    const r = await $.tool.call({ tool: 'Edit', file_path: `${R}/.github/workflows/build_android.yml`, old_string: 'a', new_string: 'b' })
    expect(r.deny).toMatch(/workflows/)
  })

  test('pubspec.yaml com version: alterado (Edit e Write)', async ($, on) => {
    dubles(on, { ficheiros: { 'pubspec.yaml': 'name: bora\nversion: 1.0.4+636\n' } })
    const e = await $.tool.call({ tool: 'Edit', file_path: `${R}/pubspec.yaml`, old_string: 'version: 1.0.4+636', new_string: 'version: 1.0.4+637' })
    expect(e.deny).toMatch(/CI incrementa/)
    const w = await $.tool.call({ tool: 'Write', file_path: `${R}/pubspec.yaml`, content: 'name: bora\nversion: 1.0.5+700\n' })
    expect(w.deny).toMatch(/CI incrementa/)
  })

  test('Write de ficheiro com SUPABASE_SERVICE_ROLE_KEY= e de .env', async ($, on) => {
    dubles(on)
    const a = await $.tool.call({ tool: 'Write', file_path: `${R}/docs/notas.txt`, content: 'SUPABASE_SERVICE_ROLE_KEY=abcdefghijklmnopqrstuvwxyz123456' })
    expect(a.deny).toMatch(/segredo/)
    const b = await $.tool.call({ tool: 'Write', file_path: `${R}/.env`, content: 'X=1' })
    expect(b.deny).toMatch(/segredos/)
  })

  test('curl com chave Stripe LIVE em texto claro', async ($, on) => {
    dubles(on)
    const r = await $.tool.call({ tool: 'Bash', command: 'curl -H "Authorization: Bearer sk_live_51ABCDEFGHIJKLMNOP" https://api.stripe.com/v1/charges' })
    expect(r.deny).toMatch(/segredo/)
  })

  test('cada bloqueio fica no tranca.log, sem o segredo', async ($, on) => {
    const d = dubles(on)
    await $.tool.call({ tool: 'Bash', command: 'git push --force origin x' })
    // o motor entrega o caminho com barras do Windows
    const doLog = (w: { path: string }) => w.path.replace(/\\/g, '/').endsWith('.claude/.ai/mods/tranca.log')
    const log = d.escritas.filter(doLog).pop()
    expect(log?.text).toMatch(/"decisao":"nega"/)
    await $.tool.call({ tool: 'Bash', command: 'curl -H "x-api-key: sk-ant-api03-SEGREDOMUITOLONGO123" https://x' })
    const log2 = d.escritas.filter(doLog).pop()
    expect(log2?.text).toMatch(/curl/)
    expect(log2?.text).not.toMatch(/SEGREDOMUITOLONGO/)
  })
})

describe('passa (chega ao Claude Code)', () => {
  test('git commit -F - && git push: o -F da mensagem NÃO é força (falso positivo antigo)', async ($, on) => {
    const d = dubles(on, { resposta: 'Permitir' })
    const r = await $.tool.call({ tool: 'Bash', command: 'git commit -q -F - <<\'MSG\'\nfix: -f e --force no texto\nMSG\ngit push origin autonomous-night-2026-04-29' })
    expect(r.deny).toBeUndefined()
    expect(d.perguntas[0]).toMatch(/Play Store a 100%/)
    expect(d.corridas).toEqual(['Bash'])
  })

  test('mensagem de commit com "--force" entre aspas não bloqueia', async ($, on) => {
    const d = dubles(on)
    const r = await $.tool.call({ tool: 'Bash', command: 'git commit -m "nunca usar git push --force"' })
    expect(r.deny).toBeUndefined()
    expect(d.corridas).toEqual(['Bash'])
  })

  test('edit em lib/screens/qualquer.dart', async ($, on) => {
    const d = dubles(on)
    const r = await $.tool.call({ tool: 'Edit', file_path: `${R}/lib/screens/qualquer.dart`, old_string: 'a', new_string: 'b' })
    expect(r.deny).toBeUndefined()
    expect(d.corridas).toEqual(['Edit'])
  })

  test('SELECT * FROM orders LIMIT 1 e flutter analyze', async ($, on) => {
    const d = dubles(on)
    await $.tool.call({ tool: 'mcp__claude_ai_Supabase__execute_sql', project_id: 'x', query: 'SELECT * FROM orders LIMIT 1' })
    await $.tool.call({ tool: 'Bash', command: 'flutter analyze lib' })
    expect(d.corridas).toEqual(['mcp__claude_ai_Supabase__execute_sql', 'Bash'])
  })
})

describe('B · pergunta', () => {
  test('git push normal: pergunta; "Recusar" nega', async ($, on) => {
    const d = dubles(on, { resposta: 'Recusar' })
    const r = await $.tool.call({ tool: 'Bash', command: 'git push origin autonomous-night-2026-04-29' })
    expect(d.perguntas.length).toBe(1)
    expect(r.deny).toMatch(/não autorizou/)
    expect(d.corridas).toEqual([])
  })

  test('git push normal: "Permitir" deixa correr', async ($, on) => {
    const d = dubles(on, { resposta: 'Permitir' })
    const r = await $.tool.call({ tool: 'Bash', command: 'git push origin autonomous-night-2026-04-29' })
    expect(r.deny).toBeUndefined()
    expect(d.corridas).toEqual(['Bash'])
  })

  test('deploy de Edge Function fora da lista pergunta', async ($, on) => {
    const d = dubles(on, { resposta: 'Recusar' })
    const r = await $.tool.call({ tool: 'mcp__claude_ai_Supabase__deploy_edge_function', project_id: 'x', name: 'notify-partner', files: [] })
    expect(d.perguntas[0]).toMatch(/notify-partner/)
    expect(r.deny).toMatch(/não autorizou/)
  })
})

describe('C · aprova sem caixa', () => {
  test('Read, Grep, git status e SELECT: allow', async ($, on) => {
    dubles(on)
    expect((await $.tool.check({ tool: 'Read', input: { file_path: `${R}/README.md` } })).decision).toBe('allow')
    expect((await $.tool.check({ tool: 'Grep', input: { pattern: 'x' } })).decision).toBe('allow')
    expect((await $.tool.check({ tool: 'Bash', input: { command: 'git status --porcelain' } })).decision).toBe('allow')
    expect((await $.tool.check({ tool: 'mcp__claude_ai_Supabase__execute_sql', input: { project_id: 'x', query: 'select count(*) from orders where status = \'delivered\'' } })).decision).toBe('allow')
  })

  test('não aprova escrita disfarçada nem o que a guarda nega', async ($, on) => {
    dubles(on, { checkFundo: 'ask' })
    expect((await $.tool.check({ tool: 'Bash', input: { command: 'git status > estado.txt' } })).decision).toBe('ask')
    expect((await $.tool.check({ tool: 'Bash', input: { command: 'git push origin x' } })).decision).toBe('ask')
    expect((await $.tool.check({ tool: 'mcp__claude_ai_Supabase__execute_sql', input: { query: 'select public.ops_reassign_order(1,2,3,4)' } })).decision).toBe('ask')
    expect((await $.tool.check({ tool: 'Edit', input: { file_path: `${R}/lib/services/pricing_service.dart`, old_string: 'a', new_string: 'b' } })).decision).toBe('deny')
  })

  test('edit em lib/ fora das zonas: allow', async ($, on) => {
    dubles(on)
    expect((await $.tool.check({ tool: 'Edit', input: { file_path: `${R}/lib/screens/x.dart`, old_string: 'a', new_string: 'b' } })).decision).toBe('allow')
  })

  test('/tranca-off 15 desliga só as aprovações; /tranca mostra a contagem', async ($, on) => {
    dubles(on, { checkFundo: 'ask' })
    // como no exemplo oficial (/tally): o kit preenche origin e presentation
    await $.command.run({ command: 'tranca-off', args: '15' } as never)
    expect((await $.tool.check({ tool: 'Read', input: { file_path: 'x' } })).decision).toBe('ask')
    expect((await $.tool.call({ tool: 'Bash', command: 'git push -f origin x' })).deny).toMatch(/push forçado/)
    const t = await $.command.run({ command: 'tranca', args: '' } as never)
    expect(t.text).toMatch(/1 bloqueadas/)
    expect(t.text).toMatch(/DESLIGADAS/)
  })
})

describe('D · fail-closed', () => {
  test('zonas-vermelhas.json estragado: o tool.call nega', async ($, on) => {
    dubles(on, { zonas: JSON.stringify({ ficheiros: [{ padrao: '(', motivo: 'x' }], migracoes: { padrao_caminho: 'x', padrao_conteudo: 'x', motivo: 'x' }, segredos_caminho: 'x', funcoes_sql_extra: [], tabelas_dinheiro_extra: [], tabelas_sem_dml_direto: [] }) })
    const r = await $.tool.call({ tool: 'Edit', file_path: `${R}/lib/x.dart`, old_string: 'a', new_string: 'b' })
    expect(r.deny).toMatch(/bora-tranca falhou/)
  })

  test('zonas-vermelhas.json estragado: o tool.check nega', async ($, on) => {
    dubles(on, { zonas: JSON.stringify({ ficheiros: [{ padrao: '(', motivo: 'x' }], migracoes: { padrao_caminho: 'x', padrao_conteudo: 'x', motivo: 'x' }, segredos_caminho: 'x', funcoes_sql_extra: [], tabelas_dinheiro_extra: [], tabelas_sem_dml_direto: [] }) })
    expect((await $.tool.check({ tool: 'Edit', input: { file_path: `${R}/lib/x.dart` } })).decision).toBe('deny')
  })

  test('zonas-vermelhas.json em falta: edições bloqueadas', async ($, on) => {
    dubles(on, { zonas: null })
    const r = await $.tool.call({ tool: 'Write', file_path: `${R}/lib/x.dart`, content: 'x' })
    expect(r.deny).toMatch(/ilegível/)
  })
})

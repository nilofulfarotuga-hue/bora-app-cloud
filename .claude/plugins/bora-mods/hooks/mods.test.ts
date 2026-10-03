// =============================================================================
// bora-mods · testes da vigia, contador, CI e contexto
// (claude plugin test .claude/plugins/bora-mods)
// =============================================================================
import { describe, expect, test } from 'claude-code/testing'

import { dubles } from './apoio-testes'

// eslint-disable-next-line @typescript-eslint/no-explicit-any
const arrancar = async ($: any, on: any) => {
  on('session.start', () => ({ cwd: 'C:/BoraLocal/projetosflutter/bora_app' }))
  await $.session.start({ cwd: 'C:/BoraLocal/projetosflutter/bora_app', surface: 'terminal', isInteractive: true })
}

describe('vigia', () => {
  test('15 min parado com um turno a correr -> aviso', async ($, on) => {
    const d = dubles(on)
    on('turn.start', ($: unknown, e: { turnId: string }) => ({ turnId: e.turnId }))
    await arrancar($, on)
    await $.turn.start({ turnId: 't1', text: 'missão' })
    await d.relogio.advance(14 * 60_000)
    expect(d.toasts.filter(t => /parada/.test(t))).toEqual([])
    await d.relogio.advance(2 * 60_000)
    expect(d.toasts.some(t => /missão parada há 1[56] min/.test(t))).toBe(true)
    const log = d.escritas.filter(w => w.path.endsWith('vigia.log')).pop()
    expect(log?.text).toMatch(/"telegram":"sem credencial no PC"/)
  })

  test('sem turno a correr não avisa', async ($, on) => {
    const d = dubles(on)
    await arrancar($, on)
    await d.relogio.advance(30 * 60_000)
    expect(d.toasts.filter(t => /parada/.test(t))).toEqual([])
  })

  test('a mesma chamada 5 vezes -> aviso de círculos e lembrete ao Claude', async ($, on) => {
    const d = dubles(on)
    for (let i = 0; i < 5; i++) await $.tool.call({ tool: 'Bash', command: 'flutter analyze' })
    expect(d.toasts.some(t => /círculos/.test(t))).toBe(true)
    // o lembrete ao Claude ($.prompt.submit) só sai quando a sessão fica parada,
    // o que o kit não simula: prova-se pela linha no vigia.log
    const log = d.escritas.filter(w => w.path.replace(/\\/g, '/').endsWith('.claude/.ai/mods/vigia.log')).pop()
    expect(log?.text).toMatch(/"evento":"circulos"/)
    // 6.ª repetição dentro de 10 min: não volta a avisar
    await $.tool.call({ tool: 'Bash', command: 'flutter analyze' })
    expect(d.toasts.filter(t => /círculos/.test(t)).length).toBe(1)
  })
})

describe('contador', () => {
  test('turn.step acumula o uso e /custo mostra-o', async ($, on) => {
    dubles(on)
    on('turn.step', async function* ($: unknown, e: { turnId: string; index: number }) {
      return {
        turnId: e.turnId,
        index: e.index,
        answer: 'ok',
        toolUses: [],
        stopReason: 'end_turn',
        usage: { input_tokens: 1200, output_tokens: 300, cache_read_input_tokens: 5000, cache_creation_input_tokens: 0, model: 'x' },
      }
    })
    for (let i = 0; i < 2; i++) {
      const s = $.turn.step({ turnId: 't', index: i, model: 'claude-test', messageCount: 1 })
      let passo = await s.next()
      while (passo.done !== true) passo = await s.next()
    }
    const r = await $.command.run({ command: 'custo', args: '' } as never)
    expect(r.text).toMatch(/2 pedidos ao modelo/)
    expect(r.text).toMatch(/entrada 2\.4k/)
  })

  test('contexto a 72% avisa uma vez; plano a 85% sugere GLM/OpenCode', async ($, on) => {
    const d = dubles(on)
    on('session.measure', ($: unknown, e: unknown) => ({ changed: [] }))
    await $.session.measure({ context: { window: 200000, tokens: 144000, percent: 72 }, rateLimits: [{ kind: 'semana', percentUsed: 85 }], changed: [] } as never)
    expect(d.logs.some(l => /contexto a 70%/.test(l))).toBe(true)
    expect(d.logs.some(l => /GLM\/OpenCode/.test(l))).toBe(true)
  })
})

describe('contexto', () => {
  test('prompt com MODO PROTECÇÃO TOTAL leva ramo, commit e a linha da tranca', async ($, on) => {
    dubles(on, {
      processo: argv => ({
        exitCode: 0,
        stdout: argv.includes('--show-current') ? 'autonomous-night-2026-04-29' : argv.includes('--porcelain') ? ' M a\n M b' : 'abc123 feat: x',
        stderr: '',
      }),
    })
    const r = await $.prompt.submit({ text: '⚠️ MODO PROTECÇÃO TOTAL ⚠️\nfaz isto', wait: false, origin: { kind: 'person' } } as never)
    const ctx = (r.context ?? []).join('\n')
    expect(ctx).toMatch(/ramo autonomous-night-2026-04-29/)
    expect(ctx).toMatch(/2 ficheiros por gravar/)
    expect(ctx).toMatch(/bora-tranca está ativa/)
  })

  test('prompt de missão sem cabeçalho -> aviso, não bloqueia', async ($, on) => {
    const d = dubles(on)
    const r = await $.prompt.submit({ text: 'BLOCO 1 ' + 'x'.repeat(1600) + ' e2e_log', wait: false, origin: { kind: 'person' } } as never)
    expect(r.text).toMatch(/^BLOCO 1/)
    expect(d.toasts.some(t => /sem cabeçalho/.test(t))).toBe(true)
  })

  test('/bora mostra as zonas e os comandos', async ($, on) => {
    dubles(on)
    const r = await $.command.run({ command: 'bora', args: '' } as never)
    expect(r.text).toMatch(/pricing_service/)
    expect(r.text).toMatch(/\/tranca-off/)
  })
})

describe('ci', () => {
  test('/ci lê os runs pela API do GitHub quando não há gh', async ($, on) => {
    dubles(on, {
      http: url =>
        url.includes('/runs?')
          ? { status: 200, ok: true, text: JSON.stringify({ workflow_runs: [{ id: 1, status: 'completed', conclusion: 'failure', created_at: '2026-10-02T08:00:00Z', html_url: 'https://github.com/x', display_title: 'feat' }] }) }
          : { status: 200, ok: true, text: JSON.stringify([{ commit: { message: 'ci: bump versionCode to 636 [skip ci]' } }]) },
    })
    const r = await $.command.run({ command: 'ci', args: '' } as never)
    expect(r.text).toMatch(/3 runs lidos/)
  })

  test('/ci sem acesso ao GitHub diz isso e não rebenta', async ($, on) => {
    dubles(on)
    const r = await $.command.run({ command: 'ci', args: '' } as never)
    expect(r.text).toMatch(/sem acesso ao GitHub/)
  })
})

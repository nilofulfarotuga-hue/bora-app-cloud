// =============================================================================
// bora-mods · MOD 3 · bora-contador — gastar o mínimo. Nada aqui chama modelo.
//  - roda de espera: " · ctx 42% · chamadas 17"
//  - banda acima do prompt: contexto, tokens, limite do plano, custo (cores)
//  - avisos a 70% / 90% de contexto e a 80% do limite do plano
//  - /custo: resumo da sessão
// =============================================================================
import type { EngineInterface, ModelUsage, On, SessionMeasureInput } from 'claude-code'

type Totais = { entrada: number; saida: number; cacheLido: number; cacheCriado: number; passos: number }

export const contas = {
  chamadas: 0,
  turnos: 0,
  total: { entrada: 0, saida: 0, cacheLido: 0, cacheCriado: 0, passos: 0 } as Totais,
  turno: { entrada: 0, saida: 0, cacheLido: 0, cacheCriado: 0, passos: 0 } as Totais,
  ctxPct: undefined as number | undefined,
  ctxTokens: undefined as number | undefined,
  plano: [] as { kind: string; percentUsed: number; resetsAt?: string }[],
  custo: undefined as number | undefined,
  avisado70: false,
  avisado90: false,
  avisadoPlano: false,
}

const zera = (): Totais => ({ entrada: 0, saida: 0, cacheLido: 0, cacheCriado: 0, passos: 0 })

function cor(pct: number | undefined): string {
  if (pct === undefined) return 'gray'
  if (pct > 85) return 'red'
  if (pct >= 60) return 'yellow'
  return 'green'
}

const mil = (n: number) => (n >= 1000 ? `${Math.round(n / 100) / 10}k` : String(n))

export function avaliarMedida($: EngineInterface, m: Pick<SessionMeasureInput, 'context' | 'rateLimits' | 'cost'>): void {
  contas.ctxPct = m.context.percent
  contas.ctxTokens = m.context.tokens
  contas.plano = m.rateLimits.map(r => ({ kind: r.kind, percentUsed: r.percentUsed, resetsAt: r.resetsAt }))
  contas.custo = m.cost?.usd
  const pct = m.context.percent ?? 0
  if (pct >= 90 && !contas.avisado90) {
    contas.avisado90 = true
    $.ui.toast('bora-contador: CONTEXTO A 90% — fecha o bloco e faz /compact já', { timeoutMs: 15_000 })
    $.ui.log('bora-contador: contexto a 90%. Fecha o bloco e faz /compact.')
  } else if (pct >= 70 && !contas.avisado70) {
    contas.avisado70 = true
    $.ui.log('bora-contador: contexto a 70%: considera /compact ou fechar o bloco')
  }
  const maior = Math.max(0, ...m.rateLimits.map(r => r.percentUsed))
  if (maior >= 80 && !contas.avisadoPlano) {
    contas.avisadoPlano = true
    $.ui.log('bora-contador: limite do plano quase no fim; passa o volume ao GLM/OpenCode (regra do motor 18/09)')
    $.ui.toast(`bora-contador: plano a ${Math.round(maior)}%`, { timeoutMs: 10_000 })
  }
}

export function somarUso(u: ModelUsage | null | undefined): void {
  if (!u) return
  for (const t of [contas.turno, contas.total]) {
    t.entrada += u.input_tokens
    t.saida += u.output_tokens
    t.cacheLido += u.cache_read_input_tokens
    t.cacheCriado += u.cache_creation_input_tokens
    t.passos++
  }
}

// filtro "apanha tudo": o gancho sem filtro de cada evento é o da tranca
const TUDO = /[\s\S]*/

export function registarContador(on: On): void {
  on('session.start', { cwd: TUDO }, async ($, e, next) => {
    try {
      await $.command.register({ name: 'custo', description: 'bora-contador: tokens, turnos e custo desta sessão' })
    } catch {
      // segue sem o comando
    }
    return next(e)
  })

  on('tool.call', { tool: TUDO }, ($, e, next) => {
    contas.chamadas++
    return next(e)
  })

  on('turn.start', { turnId: TUDO }, ($, e, next) => {
    contas.turnos++
    contas.turno = zera()
    return next(e)
  })

  on('turn.step', { turnId: TUDO }, async function* ($, e, next) {
    const r = yield* next(e)
    somarUso(r.usage)
    return r
  })

  on('session.measure', ($, e, next) => {
    avaliarMedida($, e)
    $.ui.invalidate('ui.render')
    return next(e)
  })

  on('ui.render', { component: 'Spinner' }, ($, e, next) => {
    const pct = contas.ctxPct === undefined ? '?' : Math.round(contas.ctxPct)
    return next({ ...e, props: { ...e.props, suffix: `${e.props.suffix} · ctx ${pct}% · chamadas ${contas.chamadas}` } })
  })

  on('ui.render', { component: 'AbovePrompt' }, ($, e, next) => {
    if (e.props.hasSurvey) return next(e)
    const { Box, Text } = $.ui.resolve(e)
    const plano = contas.plano.length ? Math.max(...contas.plano.map(p => p.percentUsed)) : undefined
    const reset = contas.plano.find(p => p.percentUsed === plano)?.resetsAt
    const ctx = contas.ctxPct === undefined ? '?' : `${Math.round(contas.ctxPct)}%`
    return (
      <Box>
        <Text color={cor(contas.ctxPct)}>ctx {ctx}</Text>
        <Text dimColor> · tokens {mil(contas.ctxTokens ?? 0)} · </Text>
        <Text color={cor(plano)}>plano {plano === undefined ? '?' : `${Math.round(plano)}%`}</Text>
        <Text dimColor>
          {reset ? ` (repõe ${reset.slice(0, 16).replace('T', ' ')})` : ''}
          {contas.custo !== undefined ? ` · $${contas.custo.toFixed(2)}` : ''} · chamadas {contas.chamadas}
        </Text>
      </Box>
    )
  })

  on('command.run', { command: 'custo' }, async $ => {
    const t = contas.total
    return {
      text: [
        `bora-contador · ${contas.turnos} turnos · ${t.passos} pedidos ao modelo · ${contas.chamadas} chamadas de ferramenta`,
        `tokens: entrada ${mil(t.entrada)} · saída ${mil(t.saida)} · cache lido ${mil(t.cacheLido)} · cache criado ${mil(t.cacheCriado)}`,
        `contexto: ${contas.ctxPct === undefined ? '?' : Math.round(contas.ctxPct) + '%'} · plano: ${
          contas.plano.map(p => `${p.kind} ${Math.round(p.percentUsed)}%`).join(', ') || '?'
        }${contas.custo !== undefined ? ` · custo $${contas.custo.toFixed(2)}` : ''}`,
      ].join('\n'),
    }
  })
}

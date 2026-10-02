// =============================================================================
// bora-mods · apoio dos testes (não é carregado pelo plugin, só pelos *.test.ts)
// Os testes não têm ficheiros nem rede: tudo o que os mods leem é respondido
// aqui por "dublês". As listas abaixo são CÓPIAS de amostra das reais
// (zonas-vermelhas.json e protege-banco.sh); a prova com os ficheiros reais é
// a prova viva na sessão.
// =============================================================================
import { mock } from 'claude-code/testing'

export const ZONAS_AMOSTRA = JSON.stringify({
  ficheiros: [
    { padrao: '(^|/)lib/services/pricing_service\\.dart$', motivo: 'pricing_service.dart (calculo de precos)' },
    { padrao: '(^|/)supabase/functions/dispatch-engine/', motivo: 'edge function dispatch-engine' },
    { padrao: '(^|/)\\.claude/plugins/bora-mods/', motivo: 'bora-mods' },
    { padrao: '(^|/)\\.github/workflows/', motivo: '.github/workflows (cada push e um lancamento)' },
  ],
  migracoes: {
    padrao_caminho: '(^|/)supabase/migrations/',
    padrao_conteudo: '\\b(bora_tokens|wallets?|ledger(_entries)?|stripe)\\b',
    motivo: 'migration que toca tokens/wallet/pagamentos/ledger',
  },
  segredos_caminho: '(^|/)(\\.env[^/]*|[^/]*\\.jks|[^/]*\\.keystore|\\.dart_defines[^/]*|[^/]*\\.pem)$',
  funcoes_sql_extra: ['post_order_to_ledger', 'apply_order_financial_split', 'partner_store_share'],
  tabelas_dinheiro_extra: ['client_wallets', 'tvde_[a-z_]+'],
  tabelas_sem_dml_direto: ['orders', 'drivers', 'wallets', 'client_wallets', 'ledger_entries', 'bora_tokens'],
})

export const BANCO_AMOSTRA = [
  "MONEYFN='create_order|apply_order_financial_split|add_tokens'",
  "FINTABLE='orders|wallets|ledger|ledger_entries|bora_tokens|driver_balances'",
  "PROTSLUG='stripe-webhook|dispatch-engine|finalize-order-from-intent|create-payment-intent|create-mbway-payment-intent|reprocess-refund|charge-extra|(^|[^-])refund'",
].join('\n')

export type Registo = {
  toasts: string[]
  logs: string[]
  avisos: string[]
  escritas: { path: string; text: string }[]
  prompts: string[]
  perguntas: string[]
  corridas: string[] // ferramentas que chegaram ao fundo (o "Claude Code")
}

type Opcoes = {
  zonas?: string | null // null = ficheiro em falta
  banco?: string | null
  resposta?: 'Permitir' | 'Recusar'
  checkFundo?: 'ask' | 'allow' | 'deny'
  ficheiros?: Record<string, string>
  processo?: (argv: string[]) => { exitCode: number; stdout: string; stderr: string }
  http?: (url: string) => { status: number; ok: boolean; text: string }
}

/** Liga todos os dublês e devolve onde ficam registados os efeitos. */
// eslint-disable-next-line @typescript-eslint/no-explicit-any
export function dubles(on: any, o: Opcoes = {}): Registo & { relogio: ReturnType<typeof mock.clock> } {
  const r: Registo = { toasts: [], logs: [], avisos: [], escritas: [], prompts: [], perguntas: [], corridas: [] }
  const relogio = mock.clock(on, { now: 1_000_000 })
  mock.env(on, {})
  const loja = new Map<string, unknown>()
  const escritos = new Map<string, string>()
  on('ui.toast', ($: unknown, e: { text: string }) => (r.toasts.push(e.text), { value: undefined }))
  on('ui.log', ($: unknown, e: { text: string }) => (r.logs.push(e.text), { value: undefined }))
  on('ui.notice', ($: unknown, e: { text: string }) => (r.avisos.push(String(e.text)), { value: undefined }))
  on('ui.invalidate', () => ({ value: undefined }))
  on('ui.open', () => ({ value: { isPlaced: true } }))
  on('command.register', () => ({ value: undefined }))
  on('session.id', () => ({ value: 'sessao-teste' }))
  on('session.root', () => ({ value: 'C:/BoraLocal/projetosflutter/bora_app' }))
  on('store.get', ($: unknown, e: { key: string }) => ({ value: loja.get(e.key) }))
  on('store.set', ($: unknown, e: { key: string; value: unknown }) => (loja.set(e.key, e.value), { value: undefined }))
  on('fs.exists', () => ({ value: true }))
  on('fs.write', ($: unknown, e: { path: string; text: string }) => {
    r.escritas.push({ path: e.path, text: e.text })
    escritos.set(e.path, e.text)
    return { value: undefined }
  })
  on('fs.read', ($: unknown, e: { path: string }) => {
    const p = e.path.replace(/\\/g, '/')
    if (p.endsWith('zonas-vermelhas.json')) {
      const z = o.zonas === undefined ? ZONAS_AMOSTRA : o.zonas
      return z === null ? { deny: 'ficheiro em falta' } : { value: z }
    }
    if (p.endsWith('protege-banco.sh')) {
      const b = o.banco === undefined ? BANCO_AMOSTRA : o.banco
      return b === null ? { deny: 'ficheiro em falta' } : { value: b }
    }
    for (const [fim, texto] of Object.entries(o.ficheiros ?? {})) if (p.endsWith(fim)) return { value: texto }
    if (escritos.has(e.path)) return { value: escritos.get(e.path) }
    return { deny: 'não existe' }
  })
  on('process.run', ($: unknown, e: { argv: string[] }) => ({
    value: o.processo ? o.processo(e.argv) : { exitCode: 1, stdout: '', stderr: 'sem processo no teste', isStdoutTruncated: false, isStderrTruncated: false },
  }))
  on('http.fetch', ($: unknown, e: { url: string }) => ({
    value: { headers: {}, ...(o.http ? o.http(e.url) : { status: 404, ok: false, text: '' }) },
  }))
  on('prompt.submit', ($: unknown, e: { text: string; context?: string[] }) => {
    r.prompts.push(e.text)
    return { text: e.text, context: e.context }
  })
  on('tool.check', () => ({ decision: o.checkFundo ?? 'ask' }))
  on('tool.call', ($: unknown, e: { tool: string; questions?: { question: string }[] }) => {
    if (e.tool === 'AskUserQuestion' && e.questions) {
      const q = e.questions[0]!.question
      r.perguntas.push(q)
      return { result: { answers: { [q]: o.resposta ?? 'Recusar' } } }
    }
    r.corridas.push(e.tool)
    return { result: 'ok' }
  })
  return { ...r, relogio, toasts: r.toasts, logs: r.logs, avisos: r.avisos, escritas: r.escritas, prompts: r.prompts, perguntas: r.perguntas, corridas: r.corridas }
}

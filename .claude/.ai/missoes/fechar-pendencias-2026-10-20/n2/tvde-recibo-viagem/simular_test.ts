// Simulação da Edge tvde-recibo-viagem: v5 (a do ar) contra a v6, com base e Resend FALSOS.
// Corre:  deno test --allow-env --allow-read --import-map=mapa.json simular_test.ts
// Contraprova:  NOVA=v5_no_ar/index.ts deno test ...  (o teste das encomendas tem de FALHAR).
import { assertEquals } from 'jsr:@std/assert@1'

const NOVA = Deno.env.get('NOVA') ?? 'v6/index.ts'
Deno.env.set('SUPABASE_URL', 'http://base-falsa.invalid')
Deno.env.set('SUPABASE_ANON_KEY', 'publicavel-de-simulacao-falsa')
Deno.env.set('SUPABASE_SECRET_KEYS', JSON.stringify({ default: 'segredo-de-simulacao-falso' }))
Deno.env.set('RESEND_API_KEY', 're_chave_falsa')

let emails: any[] = []
globalThis.fetch = (async (url: string | URL, init?: RequestInit) => {
  const u = String(url)
  if (u === 'https://api.resend.com/emails') {
    emails.push(JSON.parse(String(init?.body)))
    return new Response(JSON.stringify({ id: 're_falso_1' }), { status: 200 })
  }
  throw new Error('fetch fora do previsto: ' + u)
}) as typeof fetch

// Recibo como o _tvde_recibo devolve (números de uma corrida demo de 3 km a dinheiro).
function recibo(kind: string) {
  const enc = kind === 'encomendas'
  return {
    ride_id: '11111111-2222-3333-4444-555555555555', numero: '11111111', data: '2026-10-21T19:30:00Z',
    inicio: '2026-10-21T19:20:00Z', origem: 'Sé da Guarda', destino: 'Estação', distancia_km: 3,
    motorista: 'Rui Demo · AA-00-AA', plataforma: 'Bora', plataforma_nif: null, pagamento: 'cash',
    valor_viagem_cents: 500, discriminado: true, transporte_cents: 400, taxa_intermediacao_cents: 100,
    paragens_cents: null, mudanca_destino_cents: null, mudancas_destino: null, descontos_cents: null,
    total_pago_cents: 500, razao: null, titulo: enc ? 'Resumo da entrega' : 'Resumo da viagem',
    codigo_viagem: '11111111222233334444555555555555', duracao_min: 10, taxa_intermediacao_pct: 20,
    calculo: { tarifa_base_cents: 500, km_incluidos: 4, km_cobrados: 3, km_extra: 0, preco_km_extra_cents: 80, preco_por_minuto_cents: 0, fator_dinamico: 1 },
    iva_pct: null, iva_cents: null, fatura: null,
    aviso_legal: (enc ? 'Resumo da entrega' : 'Resumo da viagem') + '. Não é uma fatura: a fatura é emitida por software certificado pela Autoridade Tributária.',
  }
}

let kindAtual = 'passageiros'
;(globalThis as any).__cenario = {
  rpc(nome: string, _a: any) {
    if (nome === '_tvde_recibo' || nome === 'tvde_recibo_viagem') return { data: recibo(kindAtual), error: null }
    throw new Error('rpc fora do previsto: ' + nome)
  },
  utilizador() { return { data: { user: { id: 'cli-demo', email: 'demo.cliente@bora.app' } } } },
  utilizadorPorId(_id: string) { return { data: { user: { id: 'cli-demo', email: 'demo.cliente@bora.app' } } } },
  responder(q: any) {
    if (q.tabela === 'tvde_recibos_email' && q.op === 'select') return { data: null, error: null }
    if (q.tabela === 'tvde_recibos_email' && q.op === 'upsert') return { data: null, error: null }
    if (q.tabela === 'tvde_rides' && q.op === 'select' && q.colunas === 'client_id') return { data: { client_id: 'cli-demo' }, error: null }
    if (q.tabela === 'tvde_rides' && q.op === 'select' && q.colunas === 'ride_kind') return { data: { ride_kind: kindAtual }, error: null }
    throw new Error(`consulta fora do previsto: ${q.op} ${q.tabela} ${q.colunas}`)
  },
}

const handlers: Record<string, (r: Request) => Promise<Response>> = {}
async function carregar(nome: string) {
  ;(Deno as any).serve = (h: any) => { handlers[nome] = h }
  await import('./' + nome + '?v=' + nome)
  if (!handlers[nome]) throw new Error('handler não apanhado: ' + nome)
}
await carregar('v5_no_ar/index.ts')
await carregar(NOVA)

const jwtServico = 'Bearer x.' + btoa(JSON.stringify({ role: 'service_role' })) + '.y'
const jwtCliente = 'Bearer x.' + btoa(JSON.stringify({ role: 'authenticated', sub: 'cli-demo' })) + '.y'
async function correr(versao: string, kind: string, auth: string) {
  emails = []
  kindAtual = kind
  const r = await handlers[versao](new Request('http://x/', {
    method: 'POST', headers: { Authorization: auth },
    body: JSON.stringify({ rideId: '11111111-2222-3333-4444-555555555555' }),
  }))
  return { resposta: await r.json(), emails }
}

Deno.test('passageiros: e-mail da v6 igual byte a byte ao da v5 (servidor e cliente)', async () => {
  for (const auth of [jwtServico, jwtCliente]) {
    const a = await correr('v5_no_ar/index.ts', 'passageiros', auth)
    const b = await correr(NOVA, 'passageiros', auth)
    assertEquals(b, a)
    assertEquals(a.emails.length, 1)
  }
  console.log('PASSAGEIROS assunto: ' + (await correr(NOVA, 'passageiros', jwtServico)).emails[0].subject)
})

Deno.test('encomendas: e-mail com entrega/estafeta, sem viagem/motorista, números iguais', async () => {
  const b = await correr(NOVA, 'encomendas', jwtServico)
  const p = await correr(NOVA, 'passageiros', jwtServico)
  const e = b.emails[0]
  if (!e.subject.startsWith('Resumo da tua entrega Bora')) throw new Error('assunto: ' + e.subject)
  const proibido = /viagem|motorista|corrida|passageir|boleia/i
  const texto = e.html.replace(/<[^>]+>/g, ' ')
  const m = texto.match(proibido)
  if (m) throw new Error('palavra de passageiro no e-mail da encomenda: ' + m[0] + ' … ' + texto.slice(Math.max(0, m.index! - 60), m.index! + 60))
  for (const x of ['Estafeta: Rui Demo', 'Código da entrega: 11111111222233334444555555555555', 'Serviço de entrega (estafeta)', 'Valor da entrega']) {
    if (!e.html.includes(x)) throw new Error('falta no e-mail: ' + x)
  }
  const numeros = (h: string) => (h.match(/\d+,\d\d €/g) ?? []).join(' | ')
  assertEquals(numeros(e.html), numeros(p.emails[0].html))
  console.log('ENCOMENDA assunto: ' + e.subject + '\nnúmeros: ' + numeros(e.html))
})

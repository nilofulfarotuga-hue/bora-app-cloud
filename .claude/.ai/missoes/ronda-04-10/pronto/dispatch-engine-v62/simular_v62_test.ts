// Simulação do dispatch-engine v62 (PROPOSTA) com base de dados falsa.
// Corre o ficheiro da proposta TAL E QUAL — só o supabase-js, o fetch, o relógio
// e o Deno.serve são trocados. Não toca em produção.
//
//   deno test --allow-env --allow-read --import-map=mapa.json simular_v62_test.ts
import { assert, assertEquals } from 'jsr:@std/assert@1'

const SERVICO = 'chave-de-servico-do-ambiente'
const URL_BASE = 'https://exemplo.supabase.co'
Deno.env.set('SUPABASE_URL', URL_BASE)
Deno.env.set('SUPABASE_SERVICE_ROLE_KEY', SERVICO)

const g = globalThis as any
let motor: (req: Request) => Promise<Response> = async () => new Response('motor por carregar', { status: 599 })
let pendentes: Promise<unknown>[] = []
let fetches: { url: string; autorizacao: string }[] = []

Object.defineProperty(Deno, 'serve', { value: (h: any) => { motor = h; return {} }, configurable: true })
g.EdgeRuntime = { waitUntil: (p: Promise<unknown>) => { pendentes.push(p) } }
g.setTimeout = (fn: () => void) => { queueMicrotask(fn); return 0 } // o sleep() do redispatch não espera
g.fetch = (url: any, init: any) => {
  const h = init?.headers ?? {}
  fetches.push({ url: String(url), autorizacao: String(h.Authorization ?? h.authorization ?? '') })
  if (String(url).includes('/auth/v1/admin/users')) {
    return Promise.resolve(new Response('{}', { status: g.__cenario.cofreValido ? 200 : 401 }))
  }
  return Promise.resolve(new Response('{"ok":true}', { status: 200 }))
}
await import(Deno.env.get('MOTOR_A_SIMULAR') ?? './index.v62.PROPOSTA.ts')

// ── Material de cena ────────────────────────────────────────────────────────
function jwt(carga: Record<string, unknown>) {
  const b = btoa(JSON.stringify(carga)).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '')
  return `cabeca.${b}.assinatura`
}
const A = { driver_id: 'A-id', user_id: 'A-uid', lat: 40.54, lng: -7.26, vehicle_type: 'moto', dist_km: 1.2, mesma_loja: false }
const B = { driver_id: 'B-id', user_id: 'B-uid', lat: 40.55, lng: -7.25, vehicle_type: 'car', dist_km: 3.4, mesma_loja: false }
const pedido = (tentados: string[] = []) => ({
  id: 'P1', service_type: 'restaurant', requires_car: false, pickup_lat: 40.54, pickup_lng: -7.26,
  tried_driver_ids: tentados, current_driver_offer_id: null, driver_offer_expires_at: null,
})
const aChamar = () => ({
  status: 'callingDriver', assigned_driver_id: null, current_driver_offer_id: null,
  driver_offer_expires_at: null, dispatch_calling_since: new Date().toISOString(), dispatch_online_attempt_seconds: 0,
})

function cena(extra: Record<string, unknown> = {}) {
  pendentes = []
  fetches = []
  const c: any = {
    pendentes: [], peek: null, candidatos: [], erroRpc: null, cofreValido: false,
    utilizadores: {}, estafetaAprovado: false, pedidoDono: null, loja: null,
    updates: [] as any[], rpcs: [] as any[], consultas: [] as string[],
    ...extra,
  }
  c.responder = (q: any) => {
    c.consultas.push(`${q.tabela}:${q.op}:${q.colunas}`)
    if (q.tabela === 'platform_settings') return { data: [], error: null }
    if (q.tabela === 'orders' && q.op === 'select') {
      if (q.colunas.startsWith('id,service_type')) return { data: c.pendentes, error: null }
      if (q.colunas.startsWith('status,assigned_driver_id')) return { data: c.peek, error: null }
      if (q.colunas === 'user_id,restaurant_id') return { data: c.pedidoDono, error: null }
    }
    if (q.tabela === 'orders' && q.op === 'update') { c.updates.push(q.payload); return { data: [{ id: 'P1' }], error: null } }
    if (q.tabela === 'drivers' && q.colunas === 'id') return { data: c.estafetaAprovado ? [{ id: 'd' }] : [], error: null }
    if (q.tabela === 'restaurants') return { data: c.loja, error: null }
    throw new Error(`consulta que o v62 não devia fazer: ${q.tabela} ${q.op} ${q.colunas}`)
  }
  c.rpc = (nome: string, args: any) => {
    c.rpcs.push({ nome, args })
    if (nome === 'dispatch_candidatos_entrega') return { data: c.erroRpc ? null : c.candidatos, error: c.erroRpc }
    if (nome === 'dispatch_cancel_expired_order') return { data: null, error: null }
    throw new Error(`rpc inesperada: ${nome}`)
  }
  c.utilizador = (token: string) => {
    const u = c.utilizadores[token]
    return u ? { data: { user: u }, error: null } : { data: { user: null }, error: { message: 'jwt inválido' } }
  }
  g.__cenario = c
  return c
}

async function chamar(token: string | null, corpo: unknown = { orderId: 'P1' }) {
  const headers: Record<string, string> = { 'Content-Type': 'application/json' }
  if (token) headers.Authorization = `Bearer ${token}`
  const r = await motor(new Request(`${URL_BASE}/functions/v1/dispatch-engine`, { method: 'POST', headers, body: JSON.stringify(corpo) }))
  await Promise.all(pendentes)
  return { http: r.status, corpo: await r.json() }
}
const ofertas = (c: any) => c.updates.filter((u: any) => 'tried_driver_ids' in u)

// ── (1) Quem pode chamar ────────────────────────────────────────────────────
Deno.test('sem token → 403, e o motor não consulta nem escreve nada', async () => {
  const c = cena({ pendentes: [pedido()], candidatos: [A] })
  const r = await chamar(null)
  assertEquals(r.http, 403)
  assertEquals(c.updates.length, 0)
  assertEquals(c.rpcs.length, 0)
  assertEquals(c.consultas.length, 0)
})

Deno.test('chave pública da app (papel anon) → 403', async () => {
  const c = cena({ pendentes: [pedido()], candidatos: [A] })
  const r = await chamar(jwt({ role: 'anon' }))
  assertEquals(r.http, 403)
  assertEquals(c.updates.length, 0)
})

Deno.test('chave de serviço do ambiente → 200 (gatilhos, webhooks e o próprio motor)', async () => {
  cena()
  const r = await chamar(SERVICO, { orderId: 'nao-existe' })
  assertEquals(r.http, 200)
  assertEquals(r.corpo, { ok: true })
})

Deno.test('chave de serviço do cofre: a Auth valida uma vez, depois fica em memória', async () => {
  const doCofre = jwt({ role: 'service_role', iss: 'cofre' })
  cena({ cofreValido: true })
  assertEquals((await chamar(doCofre)).http, 200)
  assertEquals(fetches.filter((f) => f.url.includes('/auth/v1/admin/users')).length, 1)
  cena({ cofreValido: false }) // mesmo que a Auth agora dissesse não, já está validada
  assertEquals((await chamar(doCofre)).http, 200)
  assertEquals(fetches.filter((f) => f.url.includes('/auth/v1/admin/users')).length, 0)
})

Deno.test('chave "de serviço" que a Auth não aceita → 403', async () => {
  cena({ cofreValido: false })
  assertEquals((await chamar(jwt({ role: 'service_role', iss: 'forjada' }))).http, 403)
})

Deno.test('app: estafeta aprovado, dono do pedido e dono da loja passam; um estranho não', async () => {
  const t = jwt({ role: 'authenticated', sub: 'u1' })
  const eu = { [t]: { id: 'u1', email: 'x@exemplo.pt', app_metadata: {} } }
  assertEquals((await (cena({ utilizadores: eu, estafetaAprovado: true }), chamar(t))).http, 200)
  assertEquals((await (cena({ utilizadores: eu, pedidoDono: { user_id: 'u1', restaurant_id: null } }), chamar(t))).http, 200)
  assertEquals((await (cena({ utilizadores: eu, pedidoDono: { user_id: null, restaurant_id: 'loja' }, loja: { user_id: null, user_: 'u1' } }), chamar(t))).http, 200)
  assertEquals((await (cena({ utilizadores: eu, pedidoDono: { user_id: 'outro', restaurant_id: 'loja' }, loja: { user_id: 'dono', user_: 'dono' } }), chamar(t))).http, 403)
  assertEquals((await (cena({ utilizadores: eu }), chamar(t, {}))).http, 403) // sem pedido não há de quem ser dono
  assertEquals((await (cena({ utilizadores: {} }), chamar(t))).http, 403) // sessão que a Auth não reconhece
})

Deno.test('app: admin passa', async () => {
  const t = jwt({ role: 'authenticated', sub: 'adm' })
  cena({ utilizadores: { [t]: { id: 'adm', email: 'a@exemplo.pt', app_metadata: { role: 'admin' } } } })
  assertEquals((await chamar(t, {})).http, 200)
})

// ── (2) Quem recebe a oferta ────────────────────────────────────────────────
Deno.test('a oferta vai para o primeiro candidato do banco (user_id na oferta, drivers.id nos tentados)', async () => {
  const c = cena({ pendentes: [pedido()], candidatos: [A, B], peek: aChamar() })
  const r = await chamar(SERVICO)
  assertEquals(r.http, 200)
  assertEquals(c.rpcs[0], { nome: 'dispatch_candidatos_entrega', args: { p_order_id: 'P1' } })
  assertEquals(ofertas(c).length, 1)
  assertEquals(ofertas(c)[0].current_driver_offer_id, 'A-uid')
  assertEquals(ofertas(c)[0].tried_driver_ids, ['A-id'])
  assert(Date.parse(ofertas(c)[0].driver_offer_expires_at) > Date.now())
})

Deno.test('depois de oferecer, o motor volta a chamar-se com a chave de serviço (que a porta nova aceita)', async () => {
  cena({ pendentes: [pedido()], candidatos: [A], peek: aChamar() })
  await chamar(SERVICO)
  const volta = fetches.filter((f) => f.url.endsWith('/functions/v1/dispatch-engine'))
  assertEquals(volta.length, 1)
  assertEquals(volta[0].autorizacao, `Bearer ${SERVICO}`)
})

Deno.test('quem já foi tentado é saltado, venha escrito como drivers.id ou como user_id', async () => {
  for (const tentado of ['A-id', 'A-uid']) {
    const c = cena({ pendentes: [pedido([tentado])], candidatos: [A, B], peek: aChamar() })
    await chamar(SERVICO)
    assertEquals(ofertas(c)[0].current_driver_offer_id, 'B-uid')
    assertEquals(ofertas(c)[0].tried_driver_ids, [tentado, 'B-id'])
  }
})

Deno.test('todos os candidatos tentados → o ciclo recomeça pelo primeiro', async () => {
  const c = cena({ pendentes: [pedido(['A-id', 'B-id'])], candidatos: [A, B], peek: aChamar() })
  await chamar(SERVICO)
  assertEquals(ofertas(c)[0].current_driver_offer_id, 'A-uid')
  assertEquals(ofertas(c)[0].tried_driver_ids, ['A-id'])
})

Deno.test('sem candidatos → limpa a oferta, não atribui, e fica a tentar de novo', async () => {
  const c = cena({ pendentes: [pedido(['A-id'])], candidatos: [], peek: aChamar() })
  const r = await chamar(SERVICO)
  assertEquals(r.http, 200)
  assertEquals(ofertas(c).length, 0)
  assertEquals(c.updates[0], { current_driver_offer_id: null, driver_offer_expires_at: null })
  assert(c.updates.some((u: any) => 'dispatch_next_retry_at' in u), 'tem de marcar a próxima tentativa')
})

Deno.test('erro na função de candidatos → ninguém recebe oferta por outro caminho; a cadeia volta a tentar', async () => {
  const c = cena({ pendentes: [pedido()], erroRpc: { message: 'falhou' }, peek: aChamar() })
  const r = await chamar(SERVICO)
  assertEquals(r.http, 200)
  assertEquals(ofertas(c).length, 0)
  assert(c.updates.some((u: any) => 'dispatch_next_retry_at' in u))
  assertEquals(fetches.filter((f) => f.url.endsWith('/functions/v1/dispatch-engine')).length, 1)
})

Deno.test('o matching antigo saiu: nenhuma consulta directa a drivers (para escolher) nem a tvde_rides', async () => {
  const c = cena({ pendentes: [pedido(['A-id'])], candidatos: [A, B], peek: aChamar() })
  await chamar(SERVICO)
  assert(!c.consultas.some((q: string) => q.startsWith('drivers:') || q.startsWith('tvde_rides:')), c.consultas.join(' | '))
})

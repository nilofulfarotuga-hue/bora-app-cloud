// Simulação da Edge notify-tvde-client: v7 (a do ar) contra a v8, com base e Firebase FALSOS.
// Corre:  deno test --allow-env --allow-read --import-map=mapa.json simular_test.ts
// Contraprova:  NOVA=v7_no_ar/index.ts deno test ...  (o teste das encomendas tem de FALHAR).
import { assertEquals } from 'jsr:@std/assert@1'

const NOVA = Deno.env.get('NOVA') ?? 'v8/index.ts'
const CLIENTE = '00000000-0000-0000-0000-0000000c1e00'
const SEGREDO = 'segredo-de-simulacao-falso'

const par = await crypto.subtle.generateKey(
  { name: 'RSASSA-PKCS1-v1_5', modulusLength: 2048, publicExponent: new Uint8Array([1, 0, 1]), hash: 'SHA-256' },
  true, ['sign', 'verify'],
)
const pkcs8 = new Uint8Array(await crypto.subtle.exportKey('pkcs8', par.privateKey))
const pem = '-----BEGIN PRIVATE KEY-----\n' + btoa(String.fromCharCode(...pkcs8)) + '\n-----END PRIVATE KEY-----\n'
Deno.env.set('FIREBASE_PROJECT_ID', 'projeto-falso')
Deno.env.set('FIREBASE_SERVICE_ACCOUNT', JSON.stringify({ client_email: 'falso@falso.iam', private_key: pem }))
Deno.env.set('SUPABASE_URL', 'http://base-falsa.invalid')
Deno.env.set('SUPABASE_SECRET_KEYS', JSON.stringify({ default: SEGREDO }))
Deno.env.set('SUPABASE_SERVICE_ROLE_KEY', 'chave-de-servico-falsa')

let enviados: any[] = []
globalThis.fetch = (async (url: string | URL, init?: RequestInit) => {
  const u = String(url)
  if (u.startsWith('https://oauth2.googleapis.com/token')) {
    return new Response(JSON.stringify({ access_token: 'tok-google-falso', expires_in: 3600 }), { status: 200 })
  }
  if (u.startsWith('https://fcm.googleapis.com/v1/projects/projeto-falso/messages:send')) {
    enviados.push(JSON.parse(String(init?.body)))
    return new Response('{}', { status: 200 })
  }
  throw new Error('fetch fora do previsto: ' + u)
}) as typeof fetch

let rideKindAtual = 'passageiros'
let comEstafeta = true
function soColunas(cols: string, linha: Record<string, unknown>) {
  const out: Record<string, unknown> = {}
  for (const c of cols.split(',').map((s) => s.trim()).filter(Boolean)) {
    if (!(c in linha)) throw new Error('coluna desconhecida na base falsa: ' + c)
    out[c] = linha[c]
  }
  return out
}
;(globalThis as any).__cenario = {
  rpc(nome: string) { throw new Error('rpc fora do previsto: ' + nome) },
  responder(q: any) {
    if (q.tabela === 'tvde_rides' && q.op === 'select') {
      return { data: soColunas(q.colunas, { client_id: CLIENTE, driver_id: comEstafeta ? 'drv-demo' : null, status: 'agendada', ride_kind: rideKindAtual }), error: null }
    }
    if (q.tabela === 'drivers' && q.op === 'select') return { data: { name: 'Rui Demo' }, error: null }
    if (q.tabela === 'users' && q.op === 'select') return { data: { fcm_token: 'tok-cliente-demo' }, error: null }
    if (q.tabela === 'client_push_tokens' && q.op === 'select') return { data: [], error: null }
    throw new Error(`consulta fora do previsto: ${q.op} ${q.tabela} ${q.colunas}`)
  },
}

const handlers: Record<string, (r: Request) => Promise<Response>> = {}
async function carregar(nome: string) {
  ;(Deno as any).serve = (h: any) => { handlers[nome] = h }
  await import('./' + nome + '?v=' + nome)
  if (!handlers[nome]) throw new Error('handler não apanhado: ' + nome)
}
await carregar('v7_no_ar/index.ts')
await carregar(NOVA)

async function correr(versao: string, corpo: Record<string, unknown>, rk: string) {
  enviados = []
  rideKindAtual = rk
  const r = await handlers[versao](new Request('http://x/', {
    method: 'POST', headers: { apikey: SEGREDO, Authorization: `Bearer ${SEGREDO}` },
    body: JSON.stringify({ rideId: '11111111-2222-3333-4444-555555555555', ...corpo }),
  }))
  return { resposta: await r.json(), mensagens: enviados.map((m) => m.message) }
}

const ESTADOS = ['motorista_atribuido', 'motorista_a_caminho', 'motorista_chegou', 'em_andamento', 'finalizada',
  'sem_motorista', 'cancelada_motorista', 'agendada', 'reserva_confirmar', 'estado_que_nao_existe']

Deno.test('passageiros: v8 manda EXACTAMENTE o mesmo que a v7 (10 estados, com e sem estafeta, e com título próprio)', async () => {
  const linhas: string[] = []
  for (const estafeta of [true, false]) {
    comEstafeta = estafeta
    for (const st of ESTADOS) {
      const a = await correr('v7_no_ar/index.ts', { status: st }, 'passageiros')
      const b = await correr(NOVA, { status: st }, 'passageiros')
      assertEquals(b, a, st)
      if (estafeta) linhas.push(`${st}: igual · "${a.mensagens[0]?.data?.title ?? a.resposta.reason}"`)
    }
  }
  const a = await correr('v7_no_ar/index.ts', { status: 'finalizada', titulo: 'Reembolso', corpo: 'Devolvemos 5,00 EUR.' }, 'passageiros')
  const b = await correr(NOVA, { status: 'finalizada', titulo: 'Reembolso', corpo: 'Devolvemos 5,00 EUR.' }, 'passageiros')
  assertEquals(b, a, 'titulo proprio')
  console.log('PASSAGEIROS\n' + linhas.join('\n'))
})

Deno.test('encomendas: frases de entrega em todos os estados (incl. reservas); título próprio manda', async () => {
  const proibido = /corrida|motorista|passageiro|viagem|boleia/i
  const linhas: string[] = []
  comEstafeta = true
  for (const st of ESTADOS.slice(0, 9)) {
    const b = await correr(NOVA, { status: st }, 'encomendas')
    assertEquals(b.resposta.ok, true, st)
    const m = b.mensagens[0]
    for (const t of [m.data.title, m.data.body]) {
      if (proibido.test(t)) throw new Error(`${st}: palavra de passageiro numa encomenda: "${t}"`)
    }
    linhas.push(`${st}: "${m.data.title}" | "${m.data.body}"`)
  }
  comEstafeta = false
  const semNome = await correr(NOVA, { status: 'motorista_a_caminho' }, 'encomendas')
  assertEquals(semNome.mensagens[0].data.body, 'O teu estafeta vem buscar a tua encomenda.')
  comEstafeta = true
  const proprio = await correr(NOVA, { status: 'finalizada', titulo: 'Reembolso', corpo: 'Devolvemos 5,00 EUR.' }, 'encomendas')
  assertEquals(proprio.mensagens[0].data.title, 'Reembolso')
  const r = await correr(NOVA, { status: 'reserva_confirmar' }, 'encomendas')
  assertEquals(r.mensagens[0].data.title, 'Ainda queres a tua entrega?')
  assertEquals(r.mensagens[0].data.type, 'tvde_reservation_client')
  assertEquals('notification' in r.mensagens[0], false) // continua data-only
  console.log('ENCOMENDAS\n' + linhas.join('\n'))
})

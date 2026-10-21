// Simulação da Edge notify-tvde-driver: v22 (a do ar) contra a nova (v23), com base e Firebase FALSOS.
// Corre:  deno test --allow-env --allow-read --import-map=mapa.json simular_test.ts
// Prova de que a prova prova:  NOVA=v22_no_ar.ts deno test ... (o teste das encomendas tem de FALHAR).
//
// 1) Passageiros: para TODOS os kinds, a mensagem FCM da nova é IGUAL à da v22
//    (na oferta só se aceita a chave extra data.rideKind='passageiros').
// 2) Encomendas: na nova, nenhum título/corpo diz corrida/motorista/passageiro/viagem e a oferta
//    diz "📦 Nova encomenda!" (no data e no alerta do iPhone).
// Ninguém real é acordado: fetch está trocado; a base é a de supabase_falso.ts.

import { assertEquals } from 'jsr:@std/assert@1'

const NOVA = Deno.env.get('NOVA') ?? 'v23_nova.ts'
const DRIVER = '00000000-0000-0000-0000-00000000d3e0'

// ---- chave RSA de mentira para a assinatura do token Google (nunca sai daqui) ----
const par = await crypto.subtle.generateKey(
  { name: 'RSASSA-PKCS1-v1_5', modulusLength: 2048, publicExponent: new Uint8Array([1, 0, 1]), hash: 'SHA-256' },
  true, ['sign', 'verify'],
)
const pkcs8 = new Uint8Array(await crypto.subtle.exportKey('pkcs8', par.privateKey))
const pem = '-----BEGIN PRIVATE KEY-----\n' + btoa(String.fromCharCode(...pkcs8)) + '\n-----END PRIVATE KEY-----\n'
Deno.env.set('FIREBASE_PROJECT_ID', 'projeto-falso')
Deno.env.set('FIREBASE_SERVICE_ACCOUNT', JSON.stringify({ client_email: 'falso@falso.iam', private_key: pem }))
Deno.env.set('SUPABASE_URL', 'http://base-falsa.invalid')
Deno.env.set('SUPABASE_SERVICE_ROLE_KEY', 'chave-falsa')

// ---- fetch falso: só o token Google e o FCM; tudo o resto rebenta ----
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

// ---- corrida falsa (todas as colunas que alguma versão lê) ----
const corridaBase = {
  origin_label: 'Sé da Guarda', dest_label: 'Estação da Guarda', est_fare_cents: 600, est_distance_km: 3.4,
  driver_earn_cents: 480, agreed_driver_earn_cents: null, agreed_fare_cents: null, payment_method: 'cash',
  offer_expires_at: '2026-10-21T21:00:30Z', current_offer_driver_id: DRIVER, status: 'solicitada',
  scheduled_at: '2026-10-22T09:30:00Z', reservation_offer_expires_at: '2026-10-21T21:05:00Z',
  extra_stops_fee_cents: 0, roundtrip_credit_id: null, is_return_leg: false, used_subscription_ride: false,
  dest_change_fee_cents: 0,
}
let rideKindAtual = 'passageiros'

function soColunas(cols: string, linha: Record<string, unknown>) {
  const out: Record<string, unknown> = {}
  for (const c of cols.split(',').map((s) => s.trim()).filter(Boolean)) {
    if (!(c in linha)) throw new Error('coluna desconhecida na base falsa: ' + c)
    out[c] = linha[c]
  }
  return out
}

;(globalThis as any).__cenario = {
  rpc(nome: string, _args: unknown) {
    if (nome === 'aceita_papel') return { data: true, error: null }
    throw new Error('rpc fora do previsto: ' + nome)
  },
  responder(q: any) {
    const linha = { ...corridaBase, ride_kind: rideKindAtual }
    if (q.tabela === 'drivers' && q.op === 'select') return { data: { fcm_token: 'tok-aparelho-demo', name: 'Estafeta Demo' }, error: null }
    if (q.tabela === 'driver_push_tokens' && q.op === 'select') return { data: [], error: null }
    if (q.tabela === 'tvde_rides' && q.op === 'select') return { data: soColunas(q.colunas, linha), error: null }
    if (q.tabela === 'tvde_rides' && q.op === 'update') return { data: null, error: null }
    if (q.tabela === 'tvde_ride_events' && q.op === 'insert') return { data: null, error: null }
    if (q.tabela === 'platform_settings' && q.op === 'select') return { data: { value: '25' }, error: null }
    throw new Error(`consulta fora do previsto: ${q.op} ${q.tabela} ${q.colunas}`)
  },
}

// ---- carregar as duas versões, cada uma com o seu Deno.serve apanhado ----
const handlers: Record<string, (r: Request) => Promise<Response>> = {}
async function carregar(nome: string) {
  ;(Deno as any).serve = (h: any) => { handlers[nome] = h }
  await import('./' + nome + '?v=' + nome)
  if (!handlers[nome]) throw new Error('handler não apanhado: ' + nome)
}
await carregar('v22_no_ar.ts')
await carregar(NOVA)

async function correr(versao: string, kind: string, rk: string, extra: Record<string, unknown> = {}) {
  enviados = []
  rideKindAtual = rk
  const body: Record<string, unknown> = { driverId: DRIVER, rideId: '11111111-2222-3333-4444-555555555555', ...extra }
  if (kind !== 'offer') body.kind = kind
  const r = await handlers[versao](new Request('http://x/', { method: 'POST', body: JSON.stringify(body) }))
  const j = await r.json()
  return { resposta: j, mensagens: enviados.map((m) => m.message) }
}

const KINDS: Array<[string, Record<string, unknown>]> = [
  ['offer', {}], ['ride_cancelled', {}], ['queued_added', {}], ['ride_assigned', {}], ['ride_reassigned_away', {}],
  ['reservation_offer', {}], ['reservation_assigned', {}], ['reservation_reminder_early', {}],
  ['reservation_start_now', {}], ['reservation_cancelled', {}], ['reservation_lost', {}],
  ['reservation_rescheduled', {}], ['reservation_rescheduled_lost', {}],
  ['stop_added', {}], ['dest_changed', { destLabel: 'Hospital da Guarda', driverDiffCents: 120 }],
]

function textos(m: any): string[] {
  const t = [m?.data?.title, m?.data?.body, m?.notification?.title, m?.notification?.body,
    m?.apns?.payload?.aps?.alert?.title, m?.apns?.payload?.aps?.alert?.body]
  return t.filter((x) => typeof x === 'string')
}

Deno.test('passageiros: a nova manda EXACTAMENTE o mesmo que a v22 (15 kinds)', async () => {
  const linhas: string[] = []
  for (const [kind, extra] of KINDS) {
    const a = await correr('v22_no_ar.ts', kind, 'passageiros', extra)
    const b = await correr(NOVA, kind, 'passageiros', extra)
    assertEquals(b.resposta, a.resposta, kind + ' resposta')
    assertEquals(b.mensagens.length, 1, kind + ' 1 mensagem')
    const mb = structuredClone(b.mensagens[0])
    if (kind === 'offer' && mb.data && 'rideKind' in mb.data) {
      assertEquals(mb.data.rideKind, 'passageiros')
      delete mb.data.rideKind
    }
    assertEquals(mb, a.mensagens[0], kind + ' mensagem igual')
    linhas.push(`${kind}: igual · "${textos(b.mensagens[0])[0]}"`)
  }
  console.log('PASSAGEIROS\n' + linhas.join('\n'))
})

Deno.test('encomendas: a nova não diz corrida/motorista/passageiro/viagem e a oferta diz Nova encomenda', async () => {
  const linhas: string[] = []
  const proibido = /corrida|motorista|passageiro|viagem|boleia/i
  for (const [kind, extra] of KINDS) {
    const b = await correr(NOVA, kind, 'encomendas', extra)
    assertEquals(b.resposta.ok, true, kind + ' ok')
    assertEquals(b.mensagens.length, 1, kind + ' 1 mensagem')
    for (const t of textos(b.mensagens[0])) {
      if (proibido.test(t)) throw new Error(`${kind}: palavra de passageiro numa encomenda: "${t}"`)
    }
    if (kind === 'offer') {
      assertEquals(b.mensagens[0].data.title, '📦 Nova encomenda!')
      assertEquals(b.mensagens[0].apns.payload.aps.alert.title, '📦 Nova encomenda!')
      assertEquals(b.mensagens[0].data.rideKind, 'encomendas')
      assertEquals(b.mensagens[0].data.driverEarn, '4.80')
    }
    const t = textos(b.mensagens[0])
    linhas.push(`${kind}: "${t[0]}" | "${t[1]}"`)
  }
  console.log('ENCOMENDAS\n' + linhas.join('\n'))
})

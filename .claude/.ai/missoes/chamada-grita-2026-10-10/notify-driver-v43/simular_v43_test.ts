// Simulação do notify-driver (v43) sem tocar em produção.
// Corre:  deno test --allow-env --allow-read --allow-net=deno.land --import-map=mapa.json simular_v43_test.ts
// Contra a versão antiga (tem de FALHAR):  ALVO=antigo deno test ... (mesmo comando)
//
// Prova: Android só dados (sem bloco `notification`), ttl = tempo que falta à
// oferta, iPhone com alerta completo + collapse-id + reenvio, web com título,
// e o resultado do toque escrito na linha da oferta.

const ALVO = Deno.env.get('ALVO') ?? 'novo'
const CAMINHO = ALVO === 'antigo'
  ? './index.v42.ar.ts'
  : '../../../../../supabase/functions/notify-driver/index.ts'

function verifica(cond: unknown, msg: string) { if (!cond) throw new Error('FALHOU: ' + msg) }

const DRIVER = '4f61dd31-0000-4000-8000-000000000001'
const ORDER = 'd383a09e-0000-4000-8000-000000000002'

// ── ambiente ────────────────────────────────────────────────────────────────
const kp = await crypto.subtle.generateKey(
  { name: 'RSASSA-PKCS1-v1_5', modulusLength: 2048, publicExponent: new Uint8Array([1, 0, 1]), hash: 'SHA-256' },
  true, ['sign', 'verify'])
const pk = new Uint8Array(await crypto.subtle.exportKey('pkcs8', kp.privateKey))
let b = ''; for (const x of pk) b += String.fromCharCode(x)
const pem = '-----BEGIN PRIVATE KEY-----\n' + btoa(b) + '\n-----END PRIVATE KEY-----\n'
Deno.env.set('FIREBASE_PROJECT_ID', 'boraapp-d2bea')
Deno.env.set('FIREBASE_SERVICE_ACCOUNT', JSON.stringify({ client_email: 'teste@falso', private_key: pem }))
Deno.env.set('SUPABASE_URL', 'https://falso.supabase.co')
Deno.env.set('SUPABASE_SERVICE_ROLE_KEY', 'chave-servico')

const enviados: { token: string, msg: any }[] = []
const registos: any[] = []
const pendentes: Promise<unknown>[] = []
const expira = new Date(Date.now() + 60_000).toISOString()

;(globalThis as any).fetch = async (url: string | URL, init?: RequestInit) => {
  const u = String(url)
  if (u.includes('oauth2.googleapis.com')) return new Response(JSON.stringify({ access_token: 'tok-google' }), { status: 200 })
  if (u.includes('fcm.googleapis.com')) {
    const corpo = JSON.parse(String(init?.body))
    enviados.push({ token: corpo.message.token, msg: corpo.message })
    return new Response(JSON.stringify({ name: 'projects/x/messages/1' }), { status: 200 })
  }
  throw new Error('fetch inesperado ' + u)
}
// O reenvio espera 20 s entre voltas: na simulação passa logo.
;(globalThis as any).setTimeout = (fn: () => void) => { queueMicrotask(fn); return 0 }
;(globalThis as any).EdgeRuntime = { waitUntil: (p: Promise<unknown>) => { pendentes.push(p) } }

;(globalThis as any).__cenario = {
  rpc: (nome: string) => {
    if (nome === 'aceita_papel') return { data: true, error: null }
    throw new Error('rpc inesperada ' + nome)
  },
  utilizador: () => ({ data: null, error: 'sem utilizador' }),
  responder: (q: any) => {
    if (q.tabela === 'orders' && q.op === 'select') {
      return { data: { status: 'callingDriver', current_driver_offer_id: DRIVER, driver_offer_expires_at: expira, distance_km: 2.3, driver_earnings: 4.5 }, error: null }
    }
    if (q.tabela === 'drivers' && q.op === 'select') {
      return { data: { id: DRIVER, user_id: DRIVER, fcm_token: 'tok-android', name: 'Danilo' }, error: null }
    }
    if (q.tabela === 'driver_push_tokens' && q.op === 'select') {
      return { data: [
        { id: 'r1', fcm_token: 'tok-android', platform: 'android' },
        { id: 'r2', fcm_token: 'tok-ios', platform: 'ios' },
        { id: 'r3', fcm_token: 'tok-web', platform: 'web' },
      ], error: null }
    }
    if (q.tabela === 'ofertas_prestador_log' && q.op === 'update') { registos.push(q.payload); return { error: null } }
    throw new Error(`consulta inesperada ${q.tabela} ${q.op}`)
  },
}

let handler: ((r: Request) => Promise<Response>) | null = null
;(Deno as any).serve = (h: any) => { handler = h; return {} }
await import(CAMINHO)

const res = await handler!(new Request('https://falso/functions/v1/notify-driver', {
  method: 'POST',
  headers: { authorization: 'Bearer chave-servico', 'content-type': 'application/json' },
  body: JSON.stringify({ driverId: DRIVER, orderId: ORDER, vendorName: 'Favor', total: 6 }),
}))
const corpo = await res.json()
await Promise.all(pendentes)
console.log(`[simulação ${ALVO}] resposta=${JSON.stringify(corpo)} envios=${enviados.length}`)

const de = (t: string) => enviados.filter((e) => e.token === t)

Deno.test('Android: só dados — sem bloco notification no topo nem android.notification', () => {
  const a = de('tok-android')[0]?.msg
  verifica(a, 'houve envio ao Android')
  verifica(a.notification === undefined, 'sem `notification` no topo')
  verifica(a.android?.notification === undefined, 'sem `android.notification`')
  verifica(a.android?.priority === 'high', 'prioridade alta')
  verifica(a.data?.type === 'new_order_offer' && a.data?.offerExpiresAt === expira, 'tipo e prazo da oferta no data')
})

Deno.test('Android: ttl = tempo que falta à oferta (~60 s, não 25 s)', () => {
  const ttl = parseInt(String(de('tok-android')[0]?.msg?.android?.ttl ?? '0'))
  verifica(ttl >= 55 && ttl <= 60, `ttl entre 55 e 60 s (veio ${ttl})`)
})

Deno.test('iPhone: alerta completo dentro do apns + som + time-sensitive + collapse-id', () => {
  const i = de('tok-ios')[0]?.msg
  verifica(i?.apns?.payload?.aps?.alert?.title && i?.apns?.payload?.aps?.alert?.body, 'aps.alert com título e corpo')
  verifica(i.apns.payload.aps.sound === 'bora_alert.wav', 'som bora_alert.wav')
  verifica(i.apns.payload.aps['interruption-level'] === 'time-sensitive', 'time-sensitive')
  verifica(i.apns.headers['apns-push-type'] === 'alert' && i.apns.headers['apns-priority'] === '10', 'alert + prioridade 10')
  verifica(i.apns.headers['apns-collapse-id'] === `oferta:${ORDER}`, 'collapse-id da oferta')
})

Deno.test('iPhone: reenviado enquanto a oferta estiver viva; Android não', () => {
  verifica(de('tok-ios').length >= 2, `iPhone recebeu mais de um envio (recebeu ${de('tok-ios').length})`)
  verifica(de('tok-android').length === 1, `Android recebeu um só (recebeu ${de('tok-android').length})`)
})

Deno.test('Web: notificação do navegador com título e corpo', () => {
  const w = de('tok-web')[0]?.msg
  verifica(w?.webpush?.notification?.title && w?.webpush?.notification?.body, 'webpush.notification com título e corpo')
})

Deno.test('Painel: resultado do toque escrito na linha da oferta', () => {
  verifica(registos.length === 1, 'uma escrita no registo de ofertas')
  verifica(registos[0].push_aparelhos === 3 && registos[0].push_enviados === 3, '3 aparelhos, 3 enviados')
})

Deno.test('Corpo: o número grande é o que o estafeta ganha', () => {
  const body = String(de('tok-android')[0]?.msg?.data?.body ?? '')
  verifica(body.startsWith('Ganhas €4.50'), `corpo começa por "Ganhas €4.50" (veio "${body}")`)
})

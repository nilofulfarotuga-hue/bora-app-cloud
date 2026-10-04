// @ts-nocheck
// supabase/functions/notify-tvde-client/index.ts
//
// TVDE — Bora Motorista. Envia push FCM ao PASSAGEIRO nas mudanças de estado da
// corrida (motorista a caminho / chegou / viagem iniciada / sem motorista /
// concluída). Clone ISOLADO de notify-client (NÃO altera notify-client).
//
// Chamado por: trigger fn_notify_tvde_client_on_status (net.http_post), quando
// tvde_rides.status muda para um estado relevante ao passageiro.
//
// v6 (2026-10-04) — push a TODOS os aparelhos (client_push_tokens + users.fcm_token);
// textos alinhados com o preco fixo e com o fim da procura (sem_motorista).
//
// v4 (2026-08-19) — RESERVA AGENDADA: aceita `status='agendada'` (reserva
// marcada) e `status='reserva_confirmar'` (o sweep pergunta ao cliente, 2h
// antes, se mantem). Estes DOIS vao DATA-ONLY (sem bloco `notification` e sem
// `android.notification`), para o handler do Flutter correr. Todos os estados
// ANTIGOS ficam exactamente como estavam.
//
// Required Supabase secrets: FIREBASE_PROJECT_ID, FIREBASE_SERVICE_ACCOUNT
// Auto-injected: SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY
//
// Retorna 200 sempre (fire-and-forget) — o caller (trigger) nunca precisa retry.

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  const firebaseProjectId   = Deno.env.get('FIREBASE_PROJECT_ID')
  const firebaseServiceAcct = Deno.env.get('FIREBASE_SERVICE_ACCOUNT')
  const supabaseUrl         = Deno.env.get('SUPABASE_URL')!
  const serviceKey          = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!

  if (!firebaseProjectId || !firebaseServiceAcct) {
    console.warn('[notify-tvde-client] Firebase env vars not set — skipping push')
    return json({ ok: false, reason: 'firebase_not_configured' }, 200)
  }

  let rideId: string
  let statusOverride: string | undefined
  // 2026-09-25: mensagem PROPRIA, para avisos que trazem um numero que muda — o primeiro
  // caso e o reembolso ("devolvemos X euros"), que nao cabe numa frase fixa por estado.
  // Aditivo: quem nao mandar titulo/corpo continua a receber a frase do estado, como sempre.
  let tituloProprio: string | undefined
  let corpoProprio: string | undefined
  try {
    const b = await req.json()
    rideId = b.rideId
    statusOverride = b.status
    tituloProprio = typeof b.titulo === 'string' && b.titulo.trim() ? b.titulo.trim() : undefined
    corpoProprio = typeof b.corpo === 'string' && b.corpo.trim() ? b.corpo.trim() : undefined
  } catch (_e) {
    return json({ ok: false, error: 'Invalid JSON body' }, 400)
  }
  if (!rideId) return json({ ok: false, error: 'rideId is required' }, 400)

  const supabase = createClient(supabaseUrl, serviceKey)

  // ── Corrida: cliente + estado + motorista ───────────────────────────────────
  const { data: ride } = await supabase
    .from('tvde_rides')
    .select('client_id, driver_id, status')
    .eq('id', rideId).maybeSingle()
  if (!ride) return json({ ok: false, reason: 'ride_not_found' }, 200)

  const status = statusOverride ?? ride.status
  const clientId = ride.client_id as string

  let driverName = ''
  if (ride.driver_id) {
    const { data: drv } = await supabase
      .from('drivers').select('name').eq('user_id', ride.driver_id).maybeSingle()
    driverName = (drv?.name ?? '').trim()
  }

  const msg = (tituloProprio && corpoProprio)
    ? { title: tituloProprio, body: corpoProprio }
    : statusMessage(status, driverName)
  if (!msg) return json({ ok: false, reason: 'status_not_notifiable' }, 200)

  // ── v6 (2026-10-04, auditoria A4): TODOS os aparelhos do passageiro ──────
  // users.fcm_token (legado) primeiro + todas as linhas activas de
  // client_push_tokens (a tabela nova, multi-aparelho), como o notify-client
  // v21. Antes so lia users.fcm_token — a maioria dos clientes so tem token na
  // tabela nova e nunca recebia "motorista a caminho".
  const alvos: { token: string; origem: 'users' | 'client_push_tokens' }[] = []
  const { data: user } = await supabase
    .from('users').select('fcm_token').eq('id', clientId).maybeSingle()
  if (user?.fcm_token) alvos.push({ token: user.fcm_token, origem: 'users' })
  const { data: extras } = await supabase
    .from('client_push_tokens').select('fcm_token')
    .eq('user_id', clientId).eq('active', true)
  for (const e of extras ?? []) {
    if (e.fcm_token && !alvos.some((x) => x.token === e.fcm_token)) {
      alvos.push({ token: e.fcm_token, origem: 'client_push_tokens' })
    }
  }
  if (alvos.length === 0) {
    console.log(`[notify-tvde-client] No FCM token for client ${clientId} — skipping`)
    return json({ ok: false, reason: 'no_fcm_token' }, 200)
  }

  let accessToken: string
  try {
    accessToken = await getFirebaseAccessToken(JSON.parse(firebaseServiceAcct))
  } catch (e) {
    console.error('[notify-tvde-client] Firebase auth error:', e)
    return json({ ok: false, reason: 'firebase_auth_error' }, 200)
  }

  // [Reserva agendada 2026-08-19] Os estados NOVOS de reserva vao DATA-ONLY
  // (sem bloco `notification`): com esse bloco o Android auto-mostra o push e
  // o handler do Flutter nao corre — licao de 28/07 e 31/07. Os estados
  // ANTIGOS ficam exactamente como estao hoje (nao mexer no que funciona).
  const RESERVA_STATUSES = new Set(['reserva_confirmar', 'agendada'])
  const dataOnly = RESERVA_STATUSES.has(String(status))
  const tipo = dataOnly ? 'tvde_reservation_client' : 'tvde_ride_status'

  const fcmUrl = `https://fcm.googleapis.com/v1/projects/${firebaseProjectId}/messages:send`
  const message = {
    message: {
      token: alvos[0].token,
      ...(dataOnly ? {} : { notification: { title: msg.title, body: msg.body } }),
      data: {
        rideId: String(rideId),
        status: String(status),
        type: tipo,
        title: msg.title,
        body: msg.body,
      },
      // DATA-ONLY tem de ser data-only a serio: com `android.notification`
      // presente o Android volta a auto-mostrar e o handler do Flutter nao
      // corre. Por isso o bloco de notificacao do Android tambem sai.
      android: dataOnly
        ? { priority: 'high' }
        : {
            priority: 'high',
            notification: { channel_id: 'bora_orders', sound: 'default' },
          },
      apns: dataOnly
        ? {
            headers: { 'apns-priority': '10', 'apns-push-type': 'background' },
            payload: { aps: { 'content-available': 1 } },
          }
        : {
            headers: { 'apns-priority': '10' },
            payload: { aps: { sound: 'default', badge: 1, 'content-available': 1 } },
          },
    },
  }

  let enviados = 0
  let ultimoErro: unknown = null
  for (const alvo of alvos) {
    const m = { message: { ...message.message, token: alvo.token } }
    const fcmRes = await fetch(fcmUrl, {
      method: 'POST',
      headers: { 'Authorization': `Bearer ${accessToken}`, 'Content-Type': 'application/json' },
      body: JSON.stringify(m),
    })
    const fcmBody = await fcmRes.json().catch(() => ({}))
    if (fcmRes.ok) { enviados++; continue }
    ultimoErro = fcmBody
    console.error(`[notify-tvde-client] FCM error ${fcmRes.status} (${alvo.origem}):`, JSON.stringify(fcmBody))
    const errorCode = fcmBody?.error?.details?.[0]?.errorCode ?? ''
    if (errorCode === 'UNREGISTERED' || errorCode === 'INVALID_ARGUMENT') {
      if (alvo.origem === 'users') {
        await supabase.from('users').update({ fcm_token: null }).eq('id', clientId)
      } else {
        await supabase.from('client_push_tokens')
          .update({ active: false, last_fail_at: new Date().toISOString() })
          .eq('user_id', clientId).eq('fcm_token', alvo.token)
      }
    }
  }
  if (enviados === 0) {
    return json({ ok: false, reason: 'fcm_error', detail: ultimoErro }, 200)
  }

  console.log(`[notify-tvde-client] aparelhos=${alvos.length} enviados=${enviados}`)
  console.log(`[notify-tvde-client] ✓ Push to client ${clientId} (status=${status})`)
  return json({ ok: true }, 200)
})

function statusMessage(status: string, driverName: string): { title: string; body: string } | null {
  const d = driverName ? driverName : 'O teu motorista'
  switch (status) {
    case 'motorista_atribuido':
    case 'motorista_a_caminho':
      return { title: '🚗 Motorista a caminho', body: `${d} vem a caminho da recolha.` }
    case 'motorista_chegou':
      return { title: '📍 O motorista chegou', body: `${d} está no local de recolha.` }
    case 'em_andamento':
      return { title: '🛣️ Viagem iniciada', body: 'Boa viagem! O preço é o que viste ao pedir.' }
    case 'finalizada':
      return { title: '✅ Viagem concluída', body: 'Chegaste ao destino. Avalia a tua viagem na app.' }
    case 'sem_motorista':
      return { title: '😕 Sem motoristas disponíveis', body: 'Não encontrámos motorista a tempo e o pedido foi cancelado. Se pagaste na app, o valor é devolvido. Podes tentar de novo.' }
    case 'cancelada_motorista':
      return { title: 'Corrida cancelada', body: 'O motorista cancelou a corrida. Pedimos desculpa — tenta de novo.' }
    // ── [Reserva agendada 2026-08-19] ──────────────────────────────────────
    // `agendada` — confirmacao de que a reserva ficou marcada.
    case 'agendada':
      return {
        title: 'Reserva marcada',
        body: 'A tua viagem ficou marcada. Avisamos-te assim que houver motorista.',
      }
    // `reserva_confirmar` — o sweep pergunta ao cliente, 2h antes, se mantem.
    case 'reserva_confirmar':
      return {
        title: 'Ainda queres a tua viagem?',
        body: 'A tua reserva é daqui a pouco. Abre a app para confirmar ou cancelar.',
      }
    default:
      return null
  }
}

function json(obj: unknown, status: number): Response {
  return new Response(JSON.stringify(obj), {
    status, headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  })
}

// ── Firebase OAuth2 helpers (idênticos a notify-tvde-driver) ────────────────
async function getFirebaseAccessToken(serviceAccount: any): Promise<string> {
  const now = Math.floor(Date.now() / 1000)
  const header  = { alg: 'RS256', typ: 'JWT' }
  const payload = {
    iss: serviceAccount.client_email,
    scope: 'https://www.googleapis.com/auth/firebase.messaging',
    aud: 'https://oauth2.googleapis.com/token',
    exp: now + 3600, iat: now,
  }
  const signingInput = `${b64url(JSON.stringify(header))}.${b64url(JSON.stringify(payload))}`
  const pemBody = serviceAccount.private_key
    .replace(/-----BEGIN PRIVATE KEY-----/g, '')
    .replace(/-----END PRIVATE KEY-----/g, '')
    .replace(/\s/g, '')
  const keyBytes  = Uint8Array.from(atob(pemBody), (c) => c.charCodeAt(0))
  const cryptoKey = await crypto.subtle.importKey('pkcs8', keyBytes,
    { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' }, false, ['sign'])
  const sigBuffer = await crypto.subtle.sign('RSASSA-PKCS1-v1_5', cryptoKey, new TextEncoder().encode(signingInput))
  const jwt = `${signingInput}.${b64urlBytes(new Uint8Array(sigBuffer))}`
  const tokenRes = await fetch('https://oauth2.googleapis.com/token', {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({ grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer', assertion: jwt }),
  })
  const tokenData = await tokenRes.json()
  if (!tokenData.access_token) throw new Error(`Google token exchange failed: ${JSON.stringify(tokenData)}`)
  return tokenData.access_token
}
function b64url(str: string): string {
  return btoa(unescape(encodeURIComponent(str))).replace(/\+/g, '-').replace(/\//g, '_').replace(/=/g, '')
}
function b64urlBytes(bytes: Uint8Array): string {
  return btoa(String.fromCharCode(...bytes)).replace(/\+/g, '-').replace(/\//g, '_').replace(/=/g, '')
}

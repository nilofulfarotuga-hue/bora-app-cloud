// @ts-nocheck
// supabase/functions/notify-driver-assigned/index.ts
//
// v1 (2026-09-16, missão estafeta-web-2026-09-16 · BLOCO 4) — aviso DATA-ONLY ao
// estafeta quando lhe passam / reservam / retiram um pedido, ou quando o sistema o
// põe desligado por falta de sinal.
//
// Padrão: notify-partner v21 e notify-service-provider v3 — SEM bloco `notification`
// (o handler Flutter monta a notificação local no canal `bora_orders_urgent_v3`),
// FCM HTTP v1 com OAuth2 da service account.
//
// Diferença para o notify-driver (que só serve OFERTAS e exige current_driver_offer_id):
//   • envia para TODOS os aparelhos do estafeta: drivers.fcm_token +
//     driver_push_tokens (active) + provider_push_tokens (role=driver, active),
//     incluindo tokens WEB (platform web_*) com bloco `webpush`;
//   • valida que o pedido é mesmo dele:
//       order_reassigned  → orders.assigned_driver_id = driverId
//       order_preassigned → orders.preassigned_driver_id = driverId
//       order_unassigned  → sem validação (o pedido já não é dele)
//       driver_offline    → sem pedido
//   • identidade: driverId é o user_id (regra fixada a 16/08); aceita drivers.id
//     por compatibilidade e resolve para user_id.
//
// Auth: verify_jwt=true (a plataforma valida a assinatura do JWT) + a função
// descodifica o payload e exige role='service_role' — o MESMO padrão do
// notify-admin-urgent v15. (Comparar a chave byte a byte com o env
// SUPABASE_SERVICE_ROLE_KEY dá 403 falso: a chave do vault é um JWT válido mas
// não é idêntica ao env injectado — medido a 16/09.) É chamado pelo banco via
// pg_net: admin_reassign_order, admin_release_order_driver,
// expire_stale_driver_presence.
//
// Secrets (já existem): FIREBASE_PROJECT_ID, FIREBASE_SERVICE_ACCOUNT,
// SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY.

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
}

const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i
const TYPES = new Set(['order_reassigned', 'order_preassigned', 'order_unassigned', 'driver_offline'])
const WEB_URL = 'https://bora-app-web.pages.dev'

function json(status: number, body: unknown) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  })
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders })

  const firebaseProjectId   = Deno.env.get('FIREBASE_PROJECT_ID')
  const firebaseServiceAcct = Deno.env.get('FIREBASE_SERVICE_ACCOUNT')
  const supabaseUrl         = Deno.env.get('SUPABASE_URL')!
  const serviceKey          = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!

  // ── Auth interna: só service_role (banco via pg_net). verify_jwt=true já
  //    validou a assinatura; aqui confirma-se o papel no payload.
  const auth = req.headers.get('authorization') ?? ''
  if (!auth.startsWith('Bearer ')) return json(403, { ok: false, error: 'forbidden' })
  try {
    const payload = JSON.parse(atob(auth.substring(7).split('.')[1]))
    if (payload.role !== 'service_role') {
      console.warn('[notify-driver-assigned] 403 — role no JWT:', payload.role)
      return json(403, { ok: false, error: 'forbidden' })
    }
  } catch (_) {
    return json(403, { ok: false, error: 'forbidden' })
  }

  if (!firebaseProjectId || !firebaseServiceAcct) {
    console.warn('[notify-driver-assigned] Firebase env vars em falta — no-op')
    return json(200, { ok: false, reason: 'firebase_not_configured' })
  }

  let driverId: string, orderId: string | null, type: string, title: string, bodyText: string
  try {
    const body = await req.json()
    driverId = String(body.driverId ?? body.driver_id ?? '')
    orderId  = body.orderId ?? body.order_id ?? null
    type     = String(body.type ?? 'order_reassigned')
    title    = String(body.title ?? '')
    bodyText = String(body.body ?? '')
  } catch (_) {
    return json(400, { ok: false, error: 'Invalid JSON body' })
  }

  if (!UUID_RE.test(driverId)) return json(400, { ok: false, error: 'driverId (uuid) is required' })
  if (!TYPES.has(type))        return json(400, { ok: false, error: `type must be one of ${[...TYPES].join(', ')}` })
  if (type !== 'driver_offline' && !orderId) return json(400, { ok: false, error: 'orderId is required for this type' })

  const supabase = createClient(supabaseUrl, serviceKey)

  // ── Estafeta: user_id manda; aceita drivers.id por compatibilidade ────────
  const { data: drv, error: drvErr } = await supabase
    .from('drivers')
    .select('id, user_id, name, fcm_token')
    .or(`user_id.eq.${driverId},id.eq.${driverId}`)
    .limit(1)
    .maybeSingle()
  if (drvErr) console.warn('[notify-driver-assigned] drivers lookup:', JSON.stringify(drvErr))
  if (!drv) return json(200, { ok: false, reason: 'driver_not_found', driverId })
  const uid: string = drv.user_id ?? drv.id

  // ── Validação: o pedido é mesmo dele? ─────────────────────────────────────
  let order: any = null
  if (orderId) {
    const { data: o } = await supabase
      .from('orders')
      .select('id, status, assigned_driver_id, preassigned_driver_id, vendor_name')
      .eq('id', orderId)
      .maybeSingle()
    order = o
    if (type === 'order_reassigned') {
      const ok = o && (o.assigned_driver_id === uid || o.assigned_driver_id === drv.id)
      if (!ok) {
        console.log(`[notify-driver-assigned] order=${orderId} não está atribuído a ${uid} (está a ${o?.assigned_driver_id}) — skip`)
        return json(200, { ok: false, reason: 'not_assigned_to_driver', assigned_driver_id: o?.assigned_driver_id ?? null })
      }
    } else if (type === 'order_preassigned') {
      const ok = o && (o.preassigned_driver_id === uid || o.preassigned_driver_id === drv.id)
      if (!ok) {
        console.log(`[notify-driver-assigned] order=${orderId} não está reservado a ${uid} — skip`)
        return json(200, { ok: false, reason: 'not_preassigned_to_driver', preassigned_driver_id: o?.preassigned_driver_id ?? null })
      }
    }
  }

  // ── Todos os aparelhos do estafeta (app + web) ────────────────────────────
  type Tok = { token: string; source: string; rowId?: string; platform?: string }
  const toks = new Map<string, Tok>()
  if (drv.fcm_token) toks.set(drv.fcm_token, { token: drv.fcm_token, source: 'drivers.fcm_token' })

  const { data: dpt } = await supabase
    .from('driver_push_tokens')
    .select('id, fcm_token, platform')
    .eq('user_id', uid)
    .eq('active', true)
  for (const r of dpt ?? []) {
    if (r.fcm_token) toks.set(r.fcm_token, { token: r.fcm_token, source: 'driver_push_tokens', rowId: r.id, platform: r.platform ?? undefined })
  }

  const { data: ppt } = await supabase
    .from('provider_push_tokens')
    .select('id, fcm_token, platform')
    .eq('user_id', uid)
    .eq('role', 'driver')
    .eq('active', true)
  for (const r of ppt ?? []) {
    if (r.fcm_token && !toks.has(r.fcm_token)) {
      toks.set(r.fcm_token, { token: r.fcm_token, source: 'provider_push_tokens', rowId: r.id, platform: r.platform ?? undefined })
    }
  }

  if (toks.size === 0) {
    console.log(`[notify-driver-assigned] sem tokens para ${uid} (${drv.name}) — skip`)
    return json(200, { ok: false, reason: 'no_fcm_token', driverId: uid })
  }

  // ── Textos por defeito (PT-PT) ────────────────────────────────────────────
  const ref = orderId ? String(orderId).replace(/-/g, '').slice(0, 6).toUpperCase() : ''
  const loja = order?.vendor_name ? ` (${order.vendor_name})` : ''
  if (!title || !bodyText) {
    switch (type) {
      case 'order_reassigned':
        title    ||= '📦 Pedido atribuído a ti'
        bodyText ||= `O suporte atribuiu-te o pedido ${ref}${loja}. Abre para ver os detalhes.`
        break
      case 'order_preassigned':
        title    ||= '📦 Pedido reservado para ti'
        bodyText ||= `O pedido ${ref}${loja} fica para ti. Recebes a oferta assim que a loja o marcar pronto — mantém-te ligado.`
        break
      case 'order_unassigned':
        title    ||= `Pedido ${ref} retirado`
        bodyText ||= `O suporte devolveu o pedido ${ref} à fila geral. Não precisas de fazer nada.`
        break
      case 'driver_offline':
        title    ||= 'Ficaste desligado'
        bodyText ||= 'Ficaste desligado. Abre a Bora para voltares a receber pedidos.'
        break
    }
  }

  // ── OAuth2 Firebase ───────────────────────────────────────────────────────
  let accessToken: string
  try {
    accessToken = await getFirebaseAccessToken(JSON.parse(firebaseServiceAcct))
  } catch (e) {
    console.error('[notify-driver-assigned] Firebase token:', e)
    return json(200, { ok: false, reason: 'firebase_auth_error' })
  }

  const fcmUrl = `https://fcm.googleapis.com/v1/projects/${firebaseProjectId}/messages:send`
  const route  = type === 'driver_offline' ? '/driver' : `/driver/order/${orderId}`
  const url    = type === 'driver_offline' ? `${WEB_URL}/#/driver` : `${WEB_URL}/#/driver?order=${orderId}`

  const data: Record<string, string> = {
    type,
    orderId:      orderId ? String(orderId) : '',
    driverId:     uid,
    title,
    body:         bodyText,
    channel:      'bora_orders_urgent_v3',
    click_action: 'FLUTTER_NOTIFICATION_CLICK',
    route,
    url,
    vendorName:   order?.vendor_name ? String(order.vendor_name) : '',
    sentAt:       new Date().toISOString(),
  }

  const results = await Promise.allSettled([...toks.values()].map(async (t) => {
    const isWeb = (t.platform ?? '').toLowerCase().startsWith('web')
    const message = {
      message: {
        token: t.token,
        data,
        android: { priority: 'high', ttl: '600s' },
        // [iPhone 2026-09-21] 'alert' + som + texto: 'background' e' push SILENCIOSO
        // para a Apple (sem banner, sem som; prioridade obrigatoria 5) — com token,
        // o iPhone nunca tocava. content-available fica para acordar a app tambem.
        apns: {
          headers: { 'apns-priority': '10', 'apns-push-type': 'alert' },
          payload: { aps: { alert: { title, body: bodyText }, 'content-available': 1, sound: 'bora_alert.wav', 'interruption-level': 'time-sensitive' } },
        },
        webpush: {
          headers: { Urgency: 'high', TTL: '600' },
        },
      },
    }
    const res  = await fetch(fcmUrl, {
      method:  'POST',
      headers: { 'Authorization': `Bearer ${accessToken}`, 'Content-Type': 'application/json' },
      body:    JSON.stringify(message),
    })
    const body = await res.json().catch(() => ({}))
    if (!res.ok) {
      const errorCode = body?.error?.details?.[0]?.errorCode ?? body?.error?.status ?? ''
      console.error(`[notify-driver-assigned] FCM ${res.status} ${t.source}${isWeb ? ' (web)' : ''}: ${JSON.stringify(body).slice(0, 300)}`)
      let cleaned = false
      if (errorCode === 'UNREGISTERED' || errorCode === 'INVALID_ARGUMENT') {
        if (t.source === 'driver_push_tokens' && t.rowId) {
          await supabase.from('driver_push_tokens').update({ active: false, last_fail_at: new Date().toISOString() }).eq('id', t.rowId)
          cleaned = true
        } else if (t.source === 'provider_push_tokens' && t.rowId) {
          await supabase.from('provider_push_tokens').update({ active: false, last_fail_at: new Date().toISOString() }).eq('id', t.rowId)
          cleaned = true
        } else if (t.source === 'drivers.fcm_token') {
          await supabase.from('drivers').update({ fcm_token: null }).eq('id', drv.id)
          cleaned = true
        }
      }
      return { ok: false, source: t.source, platform: t.platform ?? null, errorCode, cleaned }
    }
    return { ok: true, source: t.source, platform: t.platform ?? null }
  }))

  const flat   = results.map((r) => r.status === 'fulfilled' ? r.value : { ok: false, error: String(r.reason) })
  const sent   = flat.filter((r) => r.ok).length
  const failed = flat.length - sent
  console.log(`[notify-driver-assigned] type=${type} order=${orderId ?? '-'} driver=${uid} (${drv.name}) tokens=${flat.length} sent=${sent} failed=${failed}`)

  return json(200, { ok: sent > 0, type, driverId: uid, orderId, tokens: flat.length, sent, failed, detail: flat })
})

// ── Firebase OAuth2 helpers (iguais ao notify-partner / notify-driver) ───────
async function getFirebaseAccessToken(serviceAccount: any): Promise<string> {
  const now = Math.floor(Date.now() / 1000)
  const header = { alg: 'RS256', typ: 'JWT' }
  const payload = {
    iss: serviceAccount.client_email,
    scope: 'https://www.googleapis.com/auth/firebase.messaging',
    aud: 'https://oauth2.googleapis.com/token',
    exp: now + 3600, iat: now,
  }
  const encodedHeader = b64url(JSON.stringify(header))
  const encodedPayload = b64url(JSON.stringify(payload))
  const signingInput = `${encodedHeader}.${encodedPayload}`
  const pemBody = serviceAccount.private_key.replace(/-----BEGIN PRIVATE KEY-----/g, '').replace(/-----END PRIVATE KEY-----/g, '').replace(/\s/g, '')
  const keyBytes = Uint8Array.from(atob(pemBody), (c) => c.charCodeAt(0))
  const cryptoKey = await crypto.subtle.importKey('pkcs8', keyBytes, { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' }, false, ['sign'])
  const sigBuffer = await crypto.subtle.sign('RSASSA-PKCS1-v1_5', cryptoKey, new TextEncoder().encode(signingInput))
  const signature = b64urlBytes(new Uint8Array(sigBuffer))
  const jwt = `${signingInput}.${signature}`
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

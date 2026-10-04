// @ts-nocheck
// v24 (04/10/2026, agente parceiro):
//  - iPhone: o aviso de pedido novo passa a ser um ALERTA com som (apns-push-type
//    alert, prioridade 10, time-sensitive). Antes era "background" (content-available),
//    que o iOS atrasa ou descarta e nunca toca → pedidos perdidos no iPhone.
//  - Android: continua data-only (a app toca o som em ciclo até alguém aceitar),
//    prioridade alta, ttl 10 min (era 60 s: telemóvel sem rede 1 minuto perdia o aviso).
//  - Quem pode pedir: chave de serviço, admin, dono da loja, ou o cliente do pedido
//    daquela loja. Antes qualquer sessão mandava avisos a qualquer loja.
//  - Aceita customTitle/customBody (reservas) e restaurant_id/title/body.
// v21 fix: partner_push_tokens usa 'partner_id' nao 'user_id'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'
const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
}
const json = (body, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { ...corsHeaders, 'Content-Type': 'application/json' } })

function jwtRole(token: string): string | null {
  try {
    const p = token.split('.')[1]
    if (!p) return null
    const s = atob(p.replace(/-/g, '+').replace(/_/g, '/') + '='.repeat((4 - (p.length % 4)) % 4))
    return JSON.parse(s)?.role ?? null
  } catch (_) { return null }
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders })
  const firebaseProjectId = Deno.env.get('FIREBASE_PROJECT_ID')
  const firebaseServiceAcct = Deno.env.get('FIREBASE_SERVICE_ACCOUNT')
  const supabaseUrl = Deno.env.get('SUPABASE_URL')!
  const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
  const anonKey = Deno.env.get('SUPABASE_ANON_KEY') ?? ''
  console.log('[notify-partner] v24 INVOKED')
  let restaurantId, orderId, items, total, customerName, kind, customTitle, customBody
  try {
    const body = await req.json()
    restaurantId = body.restaurantId ?? body.restaurant_id
    orderId = body.orderId ?? body.order_id ?? ''
    items = body.items ?? 'Novo pedido'
    total = Number(body.total ?? 0)
    customerName = body.customerName ?? ''
    kind = body.kind ?? 'new_order'
    customTitle = body.customTitle ?? body.title ?? null
    customBody = body.customBody ?? body.body ?? null
  } catch (e) {
    return json({ ok: false, error: 'Invalid JSON body' }, 400)
  }
  if (!restaurantId || (!orderId && kind === 'new_order')) {
    return json({ ok: false, error: 'restaurantId and orderId are required' }, 400)
  }
  const supabase = createClient(supabaseUrl, serviceKey)

  // ── Quem pede ────────────────────────────────────────────────────────────
  const token = (req.headers.get('Authorization') ?? '').replace(/^Bearer\s+/i, '').trim()
  const { data: restaurant } = await supabase.from('restaurants')
    .select('fcm_token, name, user_, user_id').eq('id', restaurantId).maybeSingle()
  if (!restaurant) return json({ ok: false, reason: 'restaurant_not_found' })
  let autorizado = token === serviceKey || jwtRole(token) === 'service_role'
  let order = null
  if (orderId) {
    const { data } = await supabase.from('orders')
      .select('id, user_id, restaurant_id, customer_name, price').eq('id', String(orderId)).maybeSingle()
    order = data
  }
  if (!autorizado && token) {
    const { data: u } = await supabase.auth.getUser(token)
    const uid = u?.user?.id ?? null
    if (uid) {
      if (uid === restaurant.user_ || uid === restaurant.user_id) autorizado = true
      else if (order && order.restaurant_id === restaurantId && order.user_id === uid) autorizado = true
      else {
        try {
          const uc = createClient(supabaseUrl, anonKey, { global: { headers: { Authorization: `Bearer ${token}` } } })
          const { data: isAdmin } = await uc.rpc('is_admin')
          autorizado = isAdmin === true
        } catch (_) { /* fica recusado */ }
      }
    }
  }
  if (!autorizado) return json({ ok: false, reason: 'forbidden' }, 403)

  if (!firebaseProjectId || !firebaseServiceAcct) {
    return json({ ok: false, reason: 'firebase_not_configured' })
  }
  // Valores do próprio pedido (não do telemóvel) quando existe.
  if (order) {
    if (order.price != null) total = Number(order.price)
    if (!customerName && order.customer_name) customerName = order.customer_name
  }

  let fcmToken: string | null = restaurant?.fcm_token ?? null
  let fallbackTokenId: string | null = null
  if (restaurant?.user_) {
    const { data: pushRows } = await supabase.from('partner_push_tokens')
      .select('id, fcm_token').eq('partner_id', restaurant.user_).eq('active', true)
      .order('last_used_at', { ascending: false }).limit(1)
    if (pushRows && pushRows.length > 0) {
      fcmToken = pushRows[0].fcm_token as string
      fallbackTokenId = pushRows[0].id as string
    }
  }
  if (!fcmToken) {
    console.log('[notify-partner] v24 no fcm token found for restaurant', restaurantId)
    return json({ ok: false, reason: 'no_fcm_token' })
  }
  let accessToken: string
  try { accessToken = await getFirebaseAccessToken(JSON.parse(firebaseServiceAcct)) }
  catch (e) {
    return json({ ok: false, reason: 'firebase_auth_error' })
  }

  const isNew = kind === 'new_order'
  const title = customTitle ?? (isNew ? 'Novo pedido!' : 'Atualização de pedido')
  const bodyTxt = customBody ?? (isNew
    ? `${customerName ? customerName + ' · ' : ''}€${total.toFixed(2).replace('.', ',')} — toca para aceitar`
    : String(items ?? ''))

  const fcmUrl = `https://fcm.googleapis.com/v1/projects/${firebaseProjectId}/messages:send`
  const message = {
    message: {
      token: fcmToken,
      // Android: data-only (PADRAO_BORA §1.6) — a app desenha o aviso e toca em ciclo.
      data: {
        orderId: String(orderId ?? ''), type: kind,
        restaurantId: String(restaurantId),
        items: String(items), total: total.toFixed(2),
        customerName: String(customerName),
        title: String(title), body: String(bodyTxt),
      },
      android: { priority: 'high', ttl: '600s' },
      // iPhone: alerta com som (o iOS não acorda a app com push "background").
      apns: {
        headers: { 'apns-priority': '10', 'apns-push-type': 'alert' },
        payload: {
          aps: {
            alert: { title: String(title), body: String(bodyTxt) },
            sound: 'bora_alert.wav',
            'interruption-level': 'time-sensitive',
            'content-available': 1,
          },
        },
      },
    },
  }
  const fcmRes = await fetch(fcmUrl, {
    method: 'POST',
    headers: { 'Authorization': `Bearer ${accessToken}`, 'Content-Type': 'application/json' },
    body: JSON.stringify(message),
  })
  const fcmBody = await fcmRes.json().catch(() => ({}))
  if (!fcmRes.ok) {
    console.error(`[notify-partner] v24 FCM error: ${JSON.stringify(fcmBody)}`)
    const errorCode = fcmBody?.error?.details?.[0]?.errorCode ?? ''
    if (errorCode === 'UNREGISTERED' || errorCode === 'INVALID_ARGUMENT') {
      if (fallbackTokenId) await supabase.from('partner_push_tokens').update({ active: false }).eq('id', fallbackTokenId)
      else await supabase.from('restaurants').update({ fcm_token: null }).eq('id', restaurantId)
    }
    return json({ ok: false, reason: 'fcm_error', detail: fcmBody })
  }
  console.log('[notify-partner] v24 FCM sent ok')
  return json({ ok: true })
})
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

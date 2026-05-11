// @ts-nocheck
// supabase/functions/notify-purchase-finalized/index.ts
//
// 5G — Push ao cliente quando estafeta finaliza compra storeShopping v2.
// Multi-device via client_push_tokens (Decisão A). Decisão I: corre sempre.

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders })

  const firebaseProjectId   = Deno.env.get('FIREBASE_PROJECT_ID')
  const firebaseServiceAcct = Deno.env.get('FIREBASE_SERVICE_ACCOUNT')
  const supabaseUrl         = Deno.env.get('SUPABASE_URL')!
  const serviceKey          = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!

  if (!firebaseProjectId || !firebaseServiceAcct) {
    return json({ ok: false, reason: 'firebase_not_configured' })
  }

  let orderId: string, unavailableCents: number
  try {
    const body = await req.json()
    orderId = String(body.order_id ?? '')
    unavailableCents = Number(body.unavailable_credit_cents ?? 0)
  } catch {
    return json({ ok: false, error: 'invalid_json' }, 400)
  }
  if (!orderId) return json({ ok: false, error: 'order_id required' }, 400)

  const supabase = createClient(supabaseUrl, serviceKey)

  const { data: order } = await supabase
    .from('orders')
    .select('id, user_id, vendor_name')
    .eq('id', orderId)
    .maybeSingle()
  if (!order || !order.user_id) return json({ ok: false, reason: 'no_recipient' })

  const { data: items } = await supabase
    .from('order_purchase_items_v2')
    .select('status')
    .eq('order_id', orderId)

  const counts: Record<string, number> = { purchased: 0, unavailable: 0, replaced: 0, added: 0 }
  for (const i of items ?? []) {
    if (counts[i.status] != null) counts[i.status]++
  }

  const vendorPart = order.vendor_name ? ` em ${order.vendor_name}` : ''
  let bodyText = `🛍 Compra concluída${vendorPart}. Estafeta a caminho!`
  if (counts.unavailable > 0) {
    const credit = (unavailableCents / 100).toFixed(2)
    bodyText = `🛍 ${counts.unavailable} item indisponível — €${credit} creditados. Estafeta a caminho!`
  }

  const { data: tokens } = await supabase
    .from('client_push_tokens')
    .select('fcm_token')
    .eq('user_id', order.user_id)
    .eq('active', true)

  const tokenList = tokens ?? []
  if (tokenList.length === 0) return json({ ok: true, sent: 0, reason: 'no_tokens' })

  let accessToken: string
  try {
    accessToken = await getFirebaseAccessToken(JSON.parse(firebaseServiceAcct))
  } catch (_e) {
    return json({ ok: false, reason: 'firebase_auth_error' })
  }

  const fcmUrl = `https://fcm.googleapis.com/v1/projects/${firebaseProjectId}/messages:send`
  let sent = 0, cleaned = 0
  const results = await Promise.allSettled(tokenList.map(async (t: any) => {
    const payload = {
      message: {
        token: t.fcm_token,
        notification: { title: 'Compra finalizada ✅', body: bodyText },
        data: { type: 'purchase_finalized', order_id: orderId },
        android: { priority: 'high', notification: { channel_id: 'bora_orders' } },
        apns: { headers: { 'apns-priority': '10' }, payload: { aps: { sound: 'default', badge: 1 } } },
      },
    }
    const r = await fetch(fcmUrl, { method: 'POST', headers: { 'Authorization': `Bearer ${accessToken}`, 'Content-Type': 'application/json' }, body: JSON.stringify(payload) })
    return { token: t.fcm_token, status: r.status, body: await r.json().catch(() => ({})) }
  }))
  for (const r of results) {
    if (r.status !== 'fulfilled') continue
    const { token, status, body: resp } = r.value as any
    if (status >= 200 && status < 300) { sent++; continue }
    const errCode = resp?.error?.details?.[0]?.errorCode ?? resp?.error?.status ?? ''
    if (['UNREGISTERED','INVALID_ARGUMENT','NOT_FOUND'].includes(errCode)) {
      try {
        await supabase.rpc('mark_token_failed', { p_table: 'client_push_tokens', p_token: token, p_reason: `fcm_${String(errCode).toLowerCase()}` })
        cleaned++
      } catch (_e) {}
    }
  }
  return json({ ok: true, sent, total: tokenList.length, cleaned })
})

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), { status, headers: { ...corsHeaders, 'Content-Type': 'application/json' } })
}

async function getFirebaseAccessToken(sa: any): Promise<string> {
  const now = Math.floor(Date.now() / 1000)
  const header  = { alg: 'RS256', typ: 'JWT' }
  const payload = { iss: sa.client_email, scope: 'https://www.googleapis.com/auth/firebase.messaging', aud: 'https://oauth2.googleapis.com/token', exp: now + 3600, iat: now }
  const h = b64url(JSON.stringify(header)), p = b64url(JSON.stringify(payload))
  const si = `${h}.${p}`
  const pem = sa.private_key.replace(/\\n/g, '\n')
  const b64 = pem.replace('-----BEGIN PRIVATE KEY-----','').replace('-----END PRIVATE KEY-----','').replace(/\s+/g,'')
  const bin = atob(b64); const bytes = new Uint8Array(bin.length)
  for (let i = 0; i < bin.length; i++) bytes[i] = bin.charCodeAt(i)
  const ck = await crypto.subtle.importKey('pkcs8', bytes, { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' }, false, ['sign'])
  const sig = await crypto.subtle.sign('RSASSA-PKCS1-v1_5', ck, new TextEncoder().encode(si))
  const jwt = `${si}.${b64urlBytes(new Uint8Array(sig))}`
  const r = await fetch('https://oauth2.googleapis.com/token', { method: 'POST', headers: { 'Content-Type': 'application/x-www-form-urlencoded' }, body: new URLSearchParams({ grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer', assertion: jwt }) })
  const d = await r.json(); if (!d.access_token) throw new Error('token_failed'); return d.access_token
}
function b64url(s: string): string { return btoa(unescape(encodeURIComponent(s))).replace(/\+/g,'-').replace(/\//g,'_').replace(/=/g,'') }
function b64urlBytes(b: Uint8Array): string { return btoa(String.fromCharCode(...b)).replace(/\+/g,'-').replace(/\//g,'_').replace(/=/g,'') }

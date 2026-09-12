// @ts-nocheck
// supabase/functions/notify-admin-reimbursement/index.ts
//
// 5G — Push persistente admin quando pedido Stripe/MBWay finaliza compra
// storeShopping v2 e estafeta precisa de reembolso. Decisão L novo modelo.
//
// Payload inclui driver_mbway_phone (drivers.mbway_phone fallback users.phone
// se NULL). Notification ongoing=true (Android) para não ser dismissable.

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

  let orderId: string, driverId: string | null, amountCents: number
  try {
    const body = await req.json()
    orderId = String(body.order_id ?? '')
    driverId = body.driver_id ? String(body.driver_id) : null
    amountCents = Number(body.amount_cents ?? 0)
  } catch {
    return json({ ok: false, error: 'invalid_json' }, 400)
  }
  if (!orderId || !driverId || amountCents <= 0) {
    return json({ ok: false, error: 'order_id, driver_id, amount_cents required' }, 400)
  }

  const supabase = createClient(supabaseUrl, serviceKey)

  let mbwayPhone: string | null = null
  let driverName = 'estafeta'
  try {
    const { data: d } = await supabase
      .from('drivers')
      .select('id, name, mbway_phone')
      .eq('id', driverId)
      .maybeSingle()
    if (d) {
      driverName = d.name ?? driverName
      mbwayPhone = d.mbway_phone
    }
    if (!mbwayPhone) {
      const { data: u } = await supabase.from('users').select('phone').eq('id', driverId).maybeSingle()
      mbwayPhone = u?.phone ?? null
    }
  } catch (e) {
    console.error('[notify-admin-reimbursement] driver lookup error:', e)
  }

  const { data: tokens } = await supabase
    .from('admin_push_tokens')
    .select('fcm_token')
    .order('last_used_at', { ascending: false })

  const tokenList = tokens ?? []
  if (tokenList.length === 0) {
    return json({ ok: true, sent: 0, reason: 'no_admin_tokens' })
  }

  let accessToken: string
  try {
    accessToken = await getFirebaseAccessToken(JSON.parse(firebaseServiceAcct))
  } catch (_e) {
    return json({ ok: false, reason: 'firebase_auth_error' })
  }

  const amount = (amountCents / 100).toFixed(2)
  const shortOrder = orderId.slice(0, 8).toUpperCase()
  const title = '⚠️ Reembolsar estafeta'
  const body  = mbwayPhone
    ? `Pedido #${shortOrder} — ${driverName} — Pagar €${amount} via MBWay (${mbwayPhone})`
    : `Pedido #${shortOrder} — ${driverName} — Pagar €${amount} (MBWay phone em falta)`

  const fcmUrl = `https://fcm.googleapis.com/v1/projects/${firebaseProjectId}/messages:send`
  let sent = 0
  await Promise.allSettled(tokenList.map(async (t: any) => {
    const payload = {
      message: {
        token: t.fcm_token,
        notification: { title, body },
        data: {
          type:               'admin_reimbursement',
          order_id:           orderId,
          driver_id:          driverId,
          driver_name:        driverName,
          driver_mbway_phone: mbwayPhone ?? '',
          amount_cents:       String(amountCents),
          persistent:         'true',
        },
        android: {
          priority: 'high',
          notification: {
            channel_id: 'bora_admin_urgent',
            sound: 'bora_alert',
            tag: `reimb_${orderId}`,
            notification_priority: 'PRIORITY_MAX',
          },
        },
        apns: {
          headers: { 'apns-priority': '10' },
          payload: { aps: { sound: 'bora_alert.wav', badge: 1, 'interruption-level': 'critical' } },
        },
      },
    }
    const r = await fetch(fcmUrl, { method: 'POST', headers: { 'Authorization': `Bearer ${accessToken}`, 'Content-Type': 'application/json' }, body: JSON.stringify(payload) })
    if (r.ok) sent++
  }))

  return json({ ok: true, sent, total: tokenList.length, driver_mbway_phone: mbwayPhone })
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

// @ts-nocheck
// supabase/functions/notify-tvde-chat/index.ts
//
// TVDE — Bora Motorista. Push FCM de NOVA MENSAGEM de chat ao OUTRO participante
// da corrida. Padrao delivery (clone de notify-tvde-client). 200 sempre.

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
    return json({ ok: false, reason: 'firebase_not_configured' }, 200)
  }

  let rideId: string, senderRole: string, body: string
  try {
    const b = await req.json()
    rideId = b.rideId; senderRole = b.senderRole; body = b.body ?? ''
  } catch (_e) {
    return json({ ok: false, error: 'Invalid JSON body' }, 400)
  }
  if (!rideId || !senderRole) return json({ ok: false, error: 'rideId and senderRole required' }, 400)

  const supabase = createClient(supabaseUrl, serviceKey)

  const { data: ride } = await supabase
    .from('tvde_rides').select('client_id, driver_id').eq('id', rideId).maybeSingle()
  if (!ride) return json({ ok: false, reason: 'ride_not_found' }, 200)

  // Destinatario = o OUTRO participante.
  let token: string | null = null
  let title = 'Nova mensagem'
  if (senderRole === 'client') {
    if (!ride.driver_id) return json({ ok: false, reason: 'no_driver' }, 200)
    const { data: drv } = await supabase
      .from('drivers').select('fcm_token').eq('user_id', ride.driver_id).maybeSingle()
    token = drv?.fcm_token ?? null
    title = 'Mensagem do passageiro'
  } else {
    let driverName = ''
    if (ride.driver_id) {
      const { data: drv } = await supabase
        .from('drivers').select('name').eq('user_id', ride.driver_id).maybeSingle()
      driverName = (drv?.name ?? '').trim()
    }
    const { data: user } = await supabase
      .from('users').select('fcm_token').eq('id', ride.client_id).maybeSingle()
    token = user?.fcm_token ?? null
    title = driverName ? `Mensagem de ${driverName}` : 'Mensagem do motorista'
  }
  if (!token) return json({ ok: false, reason: 'no_fcm_token' }, 200)

  let accessToken: string
  try {
    accessToken = await getFirebaseAccessToken(JSON.parse(firebaseServiceAcct))
  } catch (e) {
    return json({ ok: false, reason: 'firebase_auth_error' }, 200)
  }

  const fcmUrl = `https://fcm.googleapis.com/v1/projects/${firebaseProjectId}/messages:send`
  const message = {
    message: {
      token,
      notification: { title, body: body || 'Tens uma nova mensagem.' },
      data: { rideId: String(rideId), type: 'tvde_chat_message', title, body: String(body) },
      android: { priority: 'high', notification: { channel_id: 'bora_orders', sound: 'default' } },
      apns: { headers: { 'apns-priority': '10' }, payload: { aps: { sound: 'default', badge: 1 } } },
    },
  }
  const fcmRes = await fetch(fcmUrl, {
    method: 'POST',
    headers: { 'Authorization': `Bearer ${accessToken}`, 'Content-Type': 'application/json' },
    body: JSON.stringify(message),
  })
  if (!fcmRes.ok) {
    const fcmBody = await fcmRes.json().catch(() => ({}))
    return json({ ok: false, reason: 'fcm_error', detail: fcmBody }, 200)
  }
  return json({ ok: true }, 200)
})

function json(obj: unknown, status: number): Response {
  return new Response(JSON.stringify(obj), { status, headers: { ...corsHeaders, 'Content-Type': 'application/json' } })
}

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
    .replace(/-----BEGIN PRIVATE KEY-----/g, '').replace(/-----END PRIVATE KEY-----/g, '').replace(/\s/g, '')
  const keyBytes  = Uint8Array.from(atob(pemBody), (c) => c.charCodeAt(0))
  const cryptoKey = await crypto.subtle.importKey('pkcs8', keyBytes, { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' }, false, ['sign'])
  const sigBuffer = await crypto.subtle.sign('RSASSA-PKCS1-v1_5', cryptoKey, new TextEncoder().encode(signingInput))
  const jwt = `${signingInput}.${b64urlBytes(new Uint8Array(sigBuffer))}`
  const tokenRes = await fetch('https://oauth2.googleapis.com/token', {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({ grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer', assertion: jwt }),
  })
  const tokenData = await tokenRes.json()
  if (!tokenData.access_token) throw new Error('token exchange failed')
  return tokenData.access_token
}
function b64url(str: string): string {
  return btoa(unescape(encodeURIComponent(str))).replace(/\+/g, '-').replace(/\//g, '_').replace(/=/g, '')
}
function b64urlBytes(bytes: Uint8Array): string {
  return btoa(String.fromCharCode(...bytes)).replace(/\+/g, '-').replace(/\//g, '_').replace(/=/g, '')
}

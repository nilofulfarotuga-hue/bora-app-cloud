// @ts-nocheck
// supabase/functions/notify-tvde-driver/index.ts
//
// TVDE — Bora Motorista. Envia push FCM a um motorista de passageiros com a
// oferta de corrida. Clone ISOLADO de notify-driver (NÃO altera notify-driver).
//
// Required Supabase secrets:
//   FIREBASE_PROJECT_ID, FIREBASE_SERVICE_ACCOUNT
// Auto-injected: SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY
//
// Chamado por: trigger fn_notify_tvde_driver_on_offer (net.http_post), quando
// tvde_rides.current_offer_driver_id muda para um motorista.
//
// ⚠️ Os action buttons da notificação NÃO disparam handler em background — o
// motorista TOCA na notificação → abre o app → aceita (tvde_accept_ride).
//
// Retorna 200 sempre (fire-and-forget) para o caller nunca precisar de retry.

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

  console.log('[notify-tvde-driver] ── INVOKED ── (Firebase configured:', !!firebaseProjectId, ')')

  if (!firebaseProjectId || !firebaseServiceAcct) {
    console.warn('[notify-tvde-driver] Firebase env vars not set — skipping push')
    return json({ ok: false, reason: 'firebase_not_configured' }, 200)
  }

  let driverId: string
  let rideId: string
  try {
    const body = await req.json()
    driverId = body.driverId
    rideId   = body.rideId
  } catch (_e) {
    return json({ ok: false, error: 'Invalid JSON body' }, 400)
  }
  if (!driverId || !rideId) {
    return json({ ok: false, error: 'driverId and rideId are required' }, 400)
  }

  const supabase = createClient(supabaseUrl, serviceKey)

  // ── FCM token (drivers.fcm_token → driver_push_tokens fallback) ─────────────
  const { data: driver } = await supabase
    .from('drivers').select('fcm_token, name').eq('id', driverId).maybeSingle()

  let fcmToken: string | null = driver?.fcm_token ?? null
  let fallbackTokenId: string | null = null
  if (!fcmToken) {
    const { data: pushRows } = await supabase
      .from('driver_push_tokens').select('id, fcm_token')
      .eq('user_id', driverId).eq('active', true)
      .order('last_used_at', { ascending: false }).limit(1)
    if (pushRows && pushRows.length > 0) {
      fcmToken = pushRows[0].fcm_token as string
      fallbackTokenId = pushRows[0].id as string
    }
  }
  if (!fcmToken) {
    console.log(`[notify-tvde-driver] No FCM token for driver ${driverId} — skipping`)
    return json({ ok: false, reason: 'no_fcm_token' }, 200)
  }

  // ── Detalhes da corrida para o cartão de oferta ─────────────────────────────
  let originLabel = 'Recolha', destLabel = 'Destino', fareEur = '0.00', distanceKm = '0'
  try {
    const { data: ride } = await supabase
      .from('tvde_rides')
      .select('origin_label, dest_label, est_fare_cents, est_distance_km')
      .eq('id', rideId).maybeSingle()
    if (ride) {
      originLabel = ride.origin_label ?? originLabel
      destLabel   = ride.dest_label ?? destLabel
      const cents = Number(ride.est_fare_cents ?? 0)
      if (Number.isFinite(cents) && cents > 0) fareEur = (cents / 100).toFixed(2)
      const km = Number(ride.est_distance_km ?? 0)
      if (Number.isFinite(km) && km > 0) distanceKm = km.toFixed(1)
    }
  } catch (_e) { /* mantém fallbacks — não bloqueia o push */ }

  // ── Firebase OAuth2 access token ────────────────────────────────────────────
  let accessToken: string
  try {
    accessToken = await getFirebaseAccessToken(JSON.parse(firebaseServiceAcct))
  } catch (e) {
    console.error('[notify-tvde-driver] Firebase auth error:', e)
    return json({ ok: false, reason: 'firebase_auth_error' }, 200)
  }

  const fcmUrl = `https://fcm.googleapis.com/v1/projects/${firebaseProjectId}/messages:send`
  const headsUpBody = `${originLabel} → ${destLabel} • €${fareEur}` +
    (distanceKm !== '0' ? ` • ${distanceKm}km` : '')

  const message = {
    message: {
      token: fcmToken,
      notification: { title: '🚗 Nova corrida!', body: headsUpBody },
      data: {
        rideId:     String(rideId),
        type:       'new_tvde_ride_offer',
        originLabel, destLabel,
        fare:       fareEur,
        distanceKm,
        title:      '🚗 Nova corrida!',
        body:       headsUpBody,
      },
      android: {
        priority: 'high',
        ttl: '60s',
        notification: {
          channel_id: 'bora_orders_urgent_v3',
          priority: 'max',
          default_sound: true,
          default_vibrate_timings: true,
          visibility: 'PUBLIC',
        },
      },
      apns: {
        headers: { 'apns-priority': '10', 'apns-push-type': 'background' },
        payload: { aps: { 'content-available': 1, sound: 'bora_alert.wav', 'interruption-level': 'time-sensitive' } },
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
    console.error(`[notify-tvde-driver] FCM error ${fcmRes.status}:`, JSON.stringify(fcmBody))
    const errorCode = fcmBody?.error?.details?.[0]?.errorCode ?? ''
    if (errorCode === 'UNREGISTERED' || errorCode === 'INVALID_ARGUMENT') {
      if (fallbackTokenId) {
        await supabase.from('driver_push_tokens').update({ active: false }).eq('id', fallbackTokenId)
      } else {
        await supabase.from('drivers').update({ fcm_token: null }).eq('id', driverId)
      }
    }
    return json({ ok: false, reason: 'fcm_error', detail: fcmBody }, 200)
  }

  console.log(`[notify-tvde-driver] ✓ Push sent to driver ${driverId} ride ${rideId}`)
  return json({ ok: true }, 200)
})

function json(obj: unknown, status: number): Response {
  return new Response(JSON.stringify(obj), {
    status, headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  })
}

// ── Firebase OAuth2 helpers (idênticos a notify-driver) ─────────────────────
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

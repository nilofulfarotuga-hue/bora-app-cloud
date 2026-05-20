// @ts-nocheck
// supabase/functions/notify-driver/index.ts
//
// Sends a FCM push notification to a specific driver via Firebase HTTP v1 API.
//
// Required Supabase secrets (supabase secrets set ...):
//   FIREBASE_PROJECT_ID      — e.g. "bora-app-12345"
//   FIREBASE_SERVICE_ACCOUNT — full JSON of the Firebase Admin SDK service account key
//
// Auto-injected by Supabase:
//   SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY
//
// Called by:
//   • dispatch-engine/index.ts — after a driver offer is successfully assigned
//
// Returns 200 in all cases (including when Firebase is not configured or
// the driver has no FCM token) so the caller never needs to retry.

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

  const firebaseProjectId    = Deno.env.get('FIREBASE_PROJECT_ID')
  const firebaseServiceAcct  = Deno.env.get('FIREBASE_SERVICE_ACCOUNT')
  const supabaseUrl          = Deno.env.get('SUPABASE_URL')!
  const serviceKey           = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!

  // ── Graceful no-op when Firebase is not configured ────────────────────────
  if (!firebaseProjectId || !firebaseServiceAcct) {
    console.warn('[notify-driver] Firebase env vars not set — skipping push (set FIREBASE_PROJECT_ID + FIREBASE_SERVICE_ACCOUNT)')
    return new Response(
      JSON.stringify({ ok: false, reason: 'firebase_not_configured' }),
      { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
    )
  }

  let driverId: string
  let orderId: string
  let vendorName: string
  let total: number

  try {
    const body = await req.json()
    driverId   = body.driverId
    orderId    = body.orderId
    vendorName = body.vendorName ?? 'Pedido'
    total      = Number(body.total ?? 0)
  } catch (e) {
    return new Response(
      JSON.stringify({ ok: false, error: 'Invalid JSON body' }),
      { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
    )
  }

  if (!driverId || !orderId) {
    return new Response(
      JSON.stringify({ ok: false, error: 'driverId and orderId are required' }),
      { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
    )
  }

  const supabase = createClient(supabaseUrl, serviceKey)

  // ── Fetch FCM token for the driver ────────────────────────────────────────
  const { data: driver, error: driverErr } = await supabase
    .from('drivers')
    .select('fcm_token, name')
    .eq('id', driverId)
    .maybeSingle()

  if (driverErr) {
    console.error('[notify-driver] DB error:', JSON.stringify(driverErr))
    return new Response(
      JSON.stringify({ ok: false, reason: 'db_error' }),
      { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
    )
  }

  if (!driver?.fcm_token) {
    console.log(`[notify-driver] No FCM token for driver ${driverId} — skipping`)
    return new Response(
      JSON.stringify({ ok: false, reason: 'no_fcm_token' }),
      { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
    )
  }

  console.log(`[notify-driver] Sending push to driver=${driverId} (${driver.name}) order=${orderId}`)

  // ── Fetch order distance_km for the offer card ────────────────────────────
  // Sessão 2026-05-20 — sem distância, o estafeta não decide sem abrir o app.
  // Fonte: orders.distance_km (FLOAT8 NOT NULL DEFAULT 0). Fallback '0' se row
  // já foi limpa ou DEFAULT nunca foi sobreposto pela criação do pedido.
  let distanceKm = '0'
  try {
    const { data: order } = await supabase
      .from('orders')
      .select('distance_km')
      .eq('id', orderId)
      .maybeSingle()
    const km = Number(order?.distance_km ?? 0)
    if (Number.isFinite(km) && km > 0) {
      distanceKm = km.toFixed(1)
    }
  } catch (e) {
    console.warn('[notify-driver] failed to fetch distance_km:', e)
    // Mantém fallback '0' — não bloqueia o push.
  }

  // ── Obtain Firebase OAuth2 access token ───────────────────────────────────
  let accessToken: string
  try {
    const serviceAccount = JSON.parse(firebaseServiceAcct)
    accessToken = await getFirebaseAccessToken(serviceAccount)
  } catch (e) {
    console.error('[notify-driver] Failed to get Firebase access token:', e)
    return new Response(
      JSON.stringify({ ok: false, reason: 'firebase_auth_error' }),
      { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
    )
  }

  // ── Send FCM v1 push notification ─────────────────────────────────────────
  const fcmUrl = `https://fcm.googleapis.com/v1/projects/${firebaseProjectId}/messages:send`

  // Sessão 2026-05-18 — DATA-ONLY MESSAGE (estilo Uber/Glovo).
  // Removido o campo `notification` (top-level + android.notification) para
  // forçar o Android a entregar ao _firebaseMessagingBackgroundHandler do
  // Flutter mesmo com a app fechada/background. O handler dispara depois a
  // notificação local com fullScreenIntent + som bora_alert + vibração.
  // Se houver `notification`, o Android trata como "display message" e NÃO
  // chama o background handler → sem som, sem overlay, sem timer.
  const message = {
    message: {
      token: driver.fcm_token,
      data: {
        orderId:    String(orderId),
        type:       'new_order_offer',
        vendorName: vendorName,
        total:      total.toFixed(2),
        distanceKm: distanceKm,
        title:      '🔔 Novo pedido!',
        body:       distanceKm !== '0'
          ? `${vendorName} • €${total.toFixed(2)} • ${distanceKm}km`
          : `${vendorName} • €${total.toFixed(2)}`,
      },
      android: {
        priority: 'high',
        // SEM bloco `notification` — data-only.
      },
      apns: {
        headers: {
          'apns-priority':  '10',
          'apns-push-type': 'background',
        },
        payload: {
          aps: {
            'content-available':  1,
            sound:                'bora_alert.wav',
            'interruption-level': 'time-sensitive',
          },
        },
      },
    },
  }

  const fcmRes = await fetch(fcmUrl, {
    method: 'POST',
    headers: {
      'Authorization': `Bearer ${accessToken}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify(message),
  })

  const fcmBody = await fcmRes.json().catch(() => ({}))

  if (!fcmRes.ok) {
    console.error(`[notify-driver] FCM error ${fcmRes.status}:`, JSON.stringify(fcmBody))

    // If the token is invalid/stale, clear it from the DB so we don't retry forever.
    const errorCode = fcmBody?.error?.details?.[0]?.errorCode ?? ''
    if (errorCode === 'UNREGISTERED' || errorCode === 'INVALID_ARGUMENT') {
      console.log(`[notify-driver] Clearing stale FCM token for driver ${driverId}`)
      await supabase.from('drivers').update({ fcm_token: null }).eq('id', driverId)
    }

    return new Response(
      JSON.stringify({ ok: false, reason: 'fcm_error', detail: fcmBody }),
      { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
    )
  }

  console.log(`[notify-driver] ✓ Push sent to driver ${driverId}`)
  return new Response(
    JSON.stringify({ ok: true }),
    { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
  )
})

// ── Firebase OAuth2 helpers ────────────────────────────────────────────────

/**
 * Exchanges a service account for a short-lived Google OAuth2 access token
 * scoped to firebase.messaging. Uses RS256 JWT assertion flow.
 */
async function getFirebaseAccessToken(serviceAccount: any): Promise<string> {
  const now = Math.floor(Date.now() / 1000)

  const header  = { alg: 'RS256', typ: 'JWT' }
  const payload = {
    iss:   serviceAccount.client_email,
    scope: 'https://www.googleapis.com/auth/firebase.messaging',
    aud:   'https://oauth2.googleapis.com/token',
    exp:   now + 3600,
    iat:   now,
  }

  const encodedHeader  = b64url(JSON.stringify(header))
  const encodedPayload = b64url(JSON.stringify(payload))
  const signingInput   = `${encodedHeader}.${encodedPayload}`

  // Parse PEM private key
  const pemBody = serviceAccount.private_key
    .replace(/-----BEGIN PRIVATE KEY-----/g, '')
    .replace(/-----END PRIVATE KEY-----/g, '')
    .replace(/\s/g, '')

  const keyBytes   = Uint8Array.from(atob(pemBody), (c) => c.charCodeAt(0))
  const cryptoKey  = await crypto.subtle.importKey(
    'pkcs8',
    keyBytes,
    { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' },
    false,
    ['sign'],
  )

  const sigBuffer   = await crypto.subtle.sign('RSASSA-PKCS1-v1_5', cryptoKey, new TextEncoder().encode(signingInput))
  const signature   = b64urlBytes(new Uint8Array(sigBuffer))
  const jwt         = `${signingInput}.${signature}`

  const tokenRes  = await fetch('https://oauth2.googleapis.com/token', {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({
      grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer',
      assertion:  jwt,
    }),
  })

  const tokenData = await tokenRes.json()
  if (!tokenData.access_token) {
    throw new Error(`Google token exchange failed: ${JSON.stringify(tokenData)}`)
  }
  return tokenData.access_token
}

/** Base64url-encode a UTF-8 string. */
function b64url(str: string): string {
  return btoa(unescape(encodeURIComponent(str)))
    .replace(/\+/g, '-').replace(/\//g, '_').replace(/=/g, '')
}

/** Base64url-encode raw bytes. */
function b64urlBytes(bytes: Uint8Array): string {
  return btoa(String.fromCharCode(...bytes))
    .replace(/\+/g, '-').replace(/\//g, '_').replace(/=/g, '')
}

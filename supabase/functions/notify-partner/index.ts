// @ts-nocheck
// supabase/functions/notify-partner/index.ts
//
// Sends a FCM push notification to a partner restaurant when a new order arrives.
// Uses Firebase HTTP v1 API with OAuth2 JWT (same pattern as notify-driver).
//
// Required Supabase secrets (already set for notify-driver):
//   FIREBASE_PROJECT_ID      — e.g. "boraapp-d2bea"
//   FIREBASE_SERVICE_ACCOUNT — full JSON of the Firebase Admin SDK service account key
//
// Auto-injected by Supabase:
//   SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY
//
// Called by:
//   • Flutter NotificationService.notifyPartnerNewOrder() — fire-and-forget after createOrder
//
// Returns 200 in all cases (including when Firebase is not configured or
// the restaurant has no FCM token) so the caller never needs to retry.

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

  // ── Graceful no-op when Firebase is not configured ────────────────────────
  if (!firebaseProjectId || !firebaseServiceAcct) {
    console.warn('[notify-partner] Firebase env vars not set — skipping push')
    return new Response(
      JSON.stringify({ ok: false, reason: 'firebase_not_configured' }),
      { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
    )
  }

  let orderId: string
  let restaurantId: string
  let items: string
  let total: number

  try {
    const body  = await req.json()
    orderId      = body.orderId
    restaurantId = body.restaurantId
    items        = body.items ?? ''
    total        = Number(body.total ?? 0)
  } catch (e) {
    return new Response(
      JSON.stringify({ ok: false, error: 'Invalid JSON body' }),
      { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
    )
  }

  if (!orderId || !restaurantId) {
    return new Response(
      JSON.stringify({ ok: false, error: 'orderId and restaurantId are required' }),
      { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
    )
  }

  const supabase = createClient(supabaseUrl, serviceKey)

  // ── Fetch FCM token for the restaurant ───────────────────────────────────
  const { data: restaurant, error: restaurantErr } = await supabase
    .from('restaurants')
    .select('fcm_token, name')
    .eq('id', restaurantId)
    .maybeSingle()

  if (restaurantErr) {
    console.error('[notify-partner] DB error:', JSON.stringify(restaurantErr))
    return new Response(
      JSON.stringify({ ok: false, reason: 'db_error' }),
      { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
    )
  }

  if (!restaurant?.fcm_token) {
    console.log(`[notify-partner] No FCM token for restaurant ${restaurantId} — skipping`)
    return new Response(
      JSON.stringify({ ok: false, reason: 'no_fcm_token' }),
      { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
    )
  }

  console.log(`[notify-partner] Sending push to restaurant=${restaurantId} (${restaurant.name}) order=${orderId}`)

  // ── Build notification body ───────────────────────────────────────────────
  // e.g. "2x Sushi, 1x Ramen • €24.50"
  const bodyText = items
    ? `${items} • €${total.toFixed(2)}`
    : `Novo pedido • €${total.toFixed(2)}`

  // ── Obtain Firebase OAuth2 access token ──────────────────────────────────
  let accessToken: string
  try {
    const serviceAccount = JSON.parse(firebaseServiceAcct)
    accessToken = await getFirebaseAccessToken(serviceAccount)
  } catch (e) {
    console.error('[notify-partner] Failed to get Firebase access token:', e)
    return new Response(
      JSON.stringify({ ok: false, reason: 'firebase_auth_error' }),
      { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
    )
  }

  // ── Send FCM v1 push notification ─────────────────────────────────────────
  const fcmUrl = `https://fcm.googleapis.com/v1/projects/${firebaseProjectId}/messages:send`

  const message = {
    message: {
      token: restaurant.fcm_token,
      notification: {
        title: '🔔 Novo pedido!',
        body: bodyText,
      },
      data: {
        orderId:      String(orderId),
        restaurantId: String(restaurantId),
        type:         'new_order',
      },
      android: {
        priority: 'high',
        notification: {
          channel_id: 'bora_orders',
          sound:      'bora_alert',
        },
      },
      apns: {
        headers: { 'apns-priority': '10' },
        payload: {
          aps: {
            sound:               'bora_alert.wav',
            badge:               1,
            'content-available': 1,
          },
        },
      },
    },
  }

  const fcmRes  = await fetch(fcmUrl, {
    method:  'POST',
    headers: {
      'Authorization': `Bearer ${accessToken}`,
      'Content-Type':  'application/json',
    },
    body: JSON.stringify(message),
  })

  const fcmBody = await fcmRes.json().catch(() => ({}))

  if (!fcmRes.ok) {
    console.error(`[notify-partner] FCM error ${fcmRes.status}:`, JSON.stringify(fcmBody))

    // Clear stale token so we don't retry forever.
    const errorCode = fcmBody?.error?.details?.[0]?.errorCode ?? ''
    if (errorCode === 'UNREGISTERED' || errorCode === 'INVALID_ARGUMENT') {
      console.log(`[notify-partner] Clearing stale FCM token for restaurant ${restaurantId}`)
      await supabase.from('restaurants').update({ fcm_token: null }).eq('id', restaurantId)
    }

    return new Response(
      JSON.stringify({ ok: false, reason: 'fcm_error', detail: fcmBody }),
      { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
    )
  }

  console.log(`[notify-partner] ✓ Push sent to restaurant ${restaurantId}`)
  return new Response(
    JSON.stringify({ ok: true }),
    { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
  )
})

// ── Firebase OAuth2 helpers (identical to notify-driver) ──────────────────

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

  const pemBody = serviceAccount.private_key
    .replace(/-----BEGIN PRIVATE KEY-----/g, '')
    .replace(/-----END PRIVATE KEY-----/g, '')
    .replace(/\s/g, '')

  const keyBytes  = Uint8Array.from(atob(pemBody), (c) => c.charCodeAt(0))
  const cryptoKey = await crypto.subtle.importKey(
    'pkcs8',
    keyBytes,
    { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' },
    false,
    ['sign'],
  )

  const sigBuffer = await crypto.subtle.sign(
    'RSASSA-PKCS1-v1_5', cryptoKey, new TextEncoder().encode(signingInput),
  )
  const signature = b64urlBytes(new Uint8Array(sigBuffer))
  const jwt       = `${signingInput}.${signature}`

  const tokenRes  = await fetch('https://oauth2.googleapis.com/token', {
    method:  'POST',
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

function b64url(str: string): string {
  return btoa(unescape(encodeURIComponent(str)))
    .replace(/\+/g, '-').replace(/\//g, '_').replace(/=/g, '')
}

function b64urlBytes(bytes: Uint8Array): string {
  return btoa(String.fromCharCode(...bytes))
    .replace(/\+/g, '-').replace(/\//g, '_').replace(/=/g, '')
}

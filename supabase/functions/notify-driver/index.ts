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

  // ── Entry-point log — confirms the function was actually invoked ──────────
  console.log('[notify-driver] ── INVOKED ── (Firebase configured:', !!firebaseProjectId, ')')

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

  // A pessoa quer receber um pedido de entrega hoje?
  //
  // Desde 2026-08-28 as entregas e as corridas sao trabalhos SEPARADOS, cada
  // um com o seu interruptor na caixa "O que queres aceitar?". Sem esta
  // pergunta o interruptor era decorativo — ligava e desligava uma coisa que
  // ninguem consultava. Sem preferencia gravada = sim, comportamento de sempre.
  {
    const sb = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!)
    const { data: quer } = await sb.rpc('aceita_papel', {
      p_user_id: driverId, p_papel: 'delivery',
    })
    if (quer === false) {
      console.log(`[notify-driver] ${driverId} tem 'delivery' desligado — nao se envia`)
      // Esta funcao nao tem o ajudante json() das outras; responde a mao.
      return new Response(
        JSON.stringify({ ok: false, reason: 'papel_desligado' }),
        { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
      )
    }
  }

  console.log(`[notify-driver] driverId=${driverId} orderId=${orderId} vendor="${vendorName}" total=${total}`)

  const supabase = createClient(supabaseUrl, serviceKey)

  // ── Fetch FCM token for the driver ────────────────────────────────────────
  // Lookup ordem:
  //   1. drivers.fcm_token (legacy single-device)
  //   2. driver_push_tokens (5G multi-device) — fallback quando a UPDATE em
  //      drivers falha silenciosamente por RLS strict em drivers não-aprovados.
  //      driver_push_tokens.user_id = auth.users.id, e drivers.id == auth.users.id
  //      desde o signup defensivo (registo estafeta 2026-05-22).
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

  let fcmToken: string | null = driver?.fcm_token ?? null
  let fallbackTokenId: string | null = null

  if (!fcmToken) {
    const { data: pushRows, error: pushErr } = await supabase
      .from('driver_push_tokens')
      .select('id, fcm_token')
      .eq('user_id', driverId)
      .eq('active', true)
      .order('last_used_at', { ascending: false })
      .limit(1)

    if (pushErr) {
      console.warn('[notify-driver] driver_push_tokens lookup error:', JSON.stringify(pushErr))
    } else if (pushRows && pushRows.length > 0) {
      fcmToken = pushRows[0].fcm_token as string
      fallbackTokenId = pushRows[0].id as string
      console.log(`[notify-driver] Using fallback token from driver_push_tokens for ${driverId}`)
    }
  }

  if (!fcmToken) {
    console.log(`[notify-driver] No FCM token for driver ${driverId} (drivers.fcm_token + driver_push_tokens both empty) — skipping`)
    return new Response(
      JSON.stringify({ ok: false, reason: 'no_fcm_token' }),
      { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
    )
  }

  const tokenSource = fallbackTokenId ? 'driver_push_tokens' : 'drivers.fcm_token'
  console.log(`[notify-driver] Sending push to driver=${driverId} (${driver?.name ?? '?'}) order=${orderId} source=${tokenSource}`)

  // ── Fetch order distance_km + driver_earnings for the offer card ──────────
  // Sessão 2026-05-20 — sem distância, o estafeta não decide sem abrir o app.
  // Sessão 2026-05-22 — também buscamos driver_earnings (FLOAT8) porque o
  // overlay (bridge FCM→FGS→main) precisa mostrar o ganho na decisão rápida
  // do estafeta. Falback '0.00' se a coluna ainda não foi populada.
  let distanceKm = '0'
  let driverEarnings = '0.00'
  try {
    const { data: order } = await supabase
      .from('orders')
      .select('distance_km, driver_earnings')
      .eq('id', orderId)
      .maybeSingle()
    const km = Number(order?.distance_km ?? 0)
    if (Number.isFinite(km) && km > 0) {
      distanceKm = km.toFixed(1)
    }
    const earnings = Number(order?.driver_earnings ?? 0)
    if (Number.isFinite(earnings) && earnings > 0) {
      driverEarnings = earnings.toFixed(2)
    }
  } catch (e) {
    console.warn('[notify-driver] failed to fetch order metrics:', e)
    // Mantém fallbacks — não bloqueia o push.
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

  // Sessão 2026-05-22 — DATA + NOTIFICATION FALLBACK (Android heads-up garantido).
  // Adicionado bloco `notification` top-level como fallback: quando o Doze
  // do Android throttle o background handler, o sistema mostra pelo menos
  // a notificação com som via canal bora_orders_urgent_v3.
  // O campo `data` continua disponível para o _firebaseMessagingBackgroundHandler
  // (overlay + som loop + CallKit) quando o handler consegue correr.
  const headsUpBody = distanceKm !== '0'
    ? `${vendorName} • €${total.toFixed(2)} • ${distanceKm}km`
    : `${vendorName} • €${total.toFixed(2)}`

  const message = {
    message: {
      token: fcmToken,
      notification: {
        title: '🛵 Novo pedido!',
        body: headsUpBody,
      },
      data: {
        orderId:        String(orderId),
        type:           'new_order_offer',
        vendorName:     vendorName,
        total:          total.toFixed(2),
        distanceKm:     distanceKm,
        driverEarnings: driverEarnings,
        title:          '🔔 Novo pedido!',
        body:           distanceKm !== '0'
          ? `${vendorName} • €${total.toFixed(2)} • ${distanceKm}km`
          : `${vendorName} • €${total.toFixed(2)}`,
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

    // If the token is invalid/stale, clear it from the right source so we don't retry forever.
    const errorCode = fcmBody?.error?.details?.[0]?.errorCode ?? ''
    if (errorCode === 'UNREGISTERED' || errorCode === 'INVALID_ARGUMENT') {
      if (fallbackTokenId) {
        console.log(`[notify-driver] Deactivating stale driver_push_tokens row ${fallbackTokenId}`)
        await supabase
          .from('driver_push_tokens')
          .update({ active: false })
          .eq('id', fallbackTokenId)
      } else {
        console.log(`[notify-driver] Clearing stale drivers.fcm_token for driver ${driverId}`)
        await supabase.from('drivers').update({ fcm_token: null }).eq('id', driverId)
      }
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

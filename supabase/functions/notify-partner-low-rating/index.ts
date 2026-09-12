// @ts-nocheck
// supabase/functions/notify-partner-low-rating/index.ts
//
// Sessao 6 — Sends FCM v1 push to a restaurant when a low rating (<3 stars)
// is inserted into public.ratings. Triggered server-side by
// _notify_partner_low_rating_trigger AFTER INSERT.
//
// Auth: verify_jwt=true. Platform validates JWT signature; this function
// confirms role='service_role' (called only from server trigger).
//
// Required Supabase secrets:
//   FIREBASE_PROJECT_ID         FCM v1 endpoint project id
//   FIREBASE_SERVICE_ACCOUNT    JSON Firebase Admin service account
//   SUPABASE_URL                auto-injected
//   SUPABASE_SERVICE_ROLE_KEY   auto-injected
//
// Body (from trigger):
//   { rating_id: uuid, restaurant_id: text, stars: int, comment: text|null }
//
// Returns 200 always (FCM failures logged, not thrown).

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

  const supabaseUrl = Deno.env.get('SUPABASE_URL')!
  const serviceKey  = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!

  // Auth — verify_jwt=true valida signature; aqui confirma role
  const authHeader = req.headers.get('Authorization') ?? ''
  if (!authHeader.startsWith('Bearer ')) {
    return new Response(
      JSON.stringify({ ok: false, error: 'forbidden' }),
      { status: 403, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
    )
  }
  try {
    const token   = authHeader.substring(7)
    const payload = JSON.parse(atob(token.split('.')[1]))
    if (payload.role !== 'service_role') {
      return new Response(
        JSON.stringify({ ok: false, error: 'forbidden' }),
        { status: 403, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
      )
    }
  } catch (_e) {
    return new Response(
      JSON.stringify({ ok: false, error: 'forbidden' }),
      { status: 403, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
    )
  }

  let ratingId: string
  let restaurantId: string
  let stars: number
  let comment: string | null = null
  try {
    const body = await req.json()
    ratingId     = String(body.rating_id ?? '')
    restaurantId = String(body.restaurant_id ?? '')
    stars        = Number(body.stars ?? 0)
    comment      = body.comment ? String(body.comment) : null
  } catch (_e) {
    return new Response(
      JSON.stringify({ ok: false, error: 'invalid_json' }),
      { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
    )
  }

  if (!ratingId || !restaurantId) {
    return new Response(
      JSON.stringify({ ok: false, error: 'rating_id and restaurant_id required' }),
      { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
    )
  }

  const supabase = createClient(supabaseUrl, serviceKey)

  const { data: rest, error: restErr } = await supabase
    .from('restaurants')
    .select('id, name, fcm_token')
    .eq('id', restaurantId)
    .maybeSingle()

  if (restErr) {
    console.error('[low_rating] restaurant query error:', JSON.stringify(restErr))
    return new Response(
      JSON.stringify({ ok: true, push_attempted: 0, push_success: 0, error: 'restaurant_query_failed' }),
      { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
    )
  }

  const fcmToken = rest?.fcm_token as string | null
  console.log(`[low_rating] rating=${ratingId} restaurant=${restaurantId} stars=${stars} hasToken=${!!fcmToken}`)

  if (!fcmToken) {
    return new Response(
      JSON.stringify({ ok: true, push_attempted: 0, push_success: 0, reason: 'no_fcm_token' }),
      { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
    )
  }

  const firebaseProjectId   = Deno.env.get('FIREBASE_PROJECT_ID')
  const firebaseServiceAcct = Deno.env.get('FIREBASE_SERVICE_ACCOUNT')

  let pushSuccess = 0
  let pushCleaned = 0

  if (firebaseProjectId && firebaseServiceAcct) {
    let accessToken: string | null = null
    try {
      const sa = JSON.parse(firebaseServiceAcct)
      accessToken = await getFirebaseAccessToken(sa)
    } catch (e) {
      console.error('[low_rating] firebase auth error:', e)
    }

    if (accessToken) {
      const fcmUrl = `https://fcm.googleapis.com/v1/projects/${firebaseProjectId}/messages:send`
      const truncated = comment && comment.length > 80 ? comment.slice(0, 80) + '...' : (comment ?? '')
      const body = `Recebeste avaliacao de ${stars} estrela${stars === 1 ? '' : 's'}.${truncated ? ' "' + truncated + '"' : ''} Toca para ver.`

      const message = {
        message: {
          token: fcmToken,
          notification: {
            title: 'Avaliacao recebida — Bora App',
            body,
          },
          data: {
            type:          'low_rating',
            rating_id:     ratingId,
            restaurant_id: restaurantId,
            stars:         String(stars),
            route:         '/partner/ratings',
          },
          android: {
            priority: 'high',
            notification: {
              channel_id: 'bora_partner_ratings',
              sound:      'default',
            },
          },
          apns: {
            headers: { 'apns-priority': '10' },
            payload: {
              aps: {
                sound:               'default',
                badge:               1,
                'content-available': 1,
              },
            },
          },
        },
      }

      const res = await fetch(fcmUrl, {
        method: 'POST',
        headers: {
          'Authorization': `Bearer ${accessToken}`,
          'Content-Type':  'application/json',
        },
        body: JSON.stringify(message),
      })
      const respBody = await res.json().catch(() => ({}))

      if (res.ok) {
        pushSuccess = 1
      } else {
        const errCode = respBody?.error?.details?.[0]?.errorCode ?? respBody?.error?.status ?? ''
        const stale   = errCode === 'UNREGISTERED' || errCode === 'INVALID_ARGUMENT'
        console.error(`[low_rating] FCM ${res.status} (${errCode})`)
        if (stale) {
          const { error: clrErr } = await supabase
            .from('restaurants')
            .update({ fcm_token: null })
            .eq('id', restaurantId)
          if (!clrErr) pushCleaned = 1
        }
      }
    }
  } else {
    console.warn('[low_rating] Firebase env vars missing — push skipped')
  }

  return new Response(
    JSON.stringify({
      ok:             true,
      rating_id:      ratingId,
      restaurant_id:  restaurantId,
      push_attempted: 1,
      push_success:   pushSuccess,
      push_cleaned:   pushCleaned,
    }),
    { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
  )
})

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
    'RSASSA-PKCS1-v1_5',
    cryptoKey,
    new TextEncoder().encode(signingInput),
  )
  const signature = b64urlBytes(new Uint8Array(sigBuffer))
  const jwt       = `${signingInput}.${signature}`

  const tokenRes = await fetch('https://oauth2.googleapis.com/token', {
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

function b64url(str: string): string {
  return btoa(unescape(encodeURIComponent(str)))
    .replace(/\+/g, '-').replace(/\//g, '_').replace(/=/g, '')
}

function b64urlBytes(bytes: Uint8Array): string {
  return btoa(String.fromCharCode(...bytes))
    .replace(/\+/g, '-').replace(/\//g, '_').replace(/=/g, '')
}

// supabase/functions/notify-service-provider/index.ts — v1 (M8)
//
// Push FCM para o DONO de um service_provider (barbearia/salão) — ex.: nova
// marcação confirmada. O notify-partner é restaurant-centric (restaurants.fcm_token
// + get_partner_fcm_tokens_for_restaurant) e não serve providers só-serviços.
// Tokens: partner_push_tokens WHERE partner_id = service_providers.user_id
// (multi-device, Promise.allSettled) + cleanup de tokens UNREGISTERED.
//
// Auth: verify_jwt=false + match exato do Bearer com SERVICE_ROLE_KEY
// (padrão notify-admin-urgent) — chamada apenas por funções SQL via vault.

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
}

const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  })

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders })

  const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
  const authHeader = req.headers.get('Authorization') ?? ''
  if (authHeader !== `Bearer ${serviceKey}`) {
    return json({ ok: false, error: 'forbidden' }, 403)
  }

  const supabaseUrl = Deno.env.get('SUPABASE_URL') ?? ''
  const firebaseProjectId = Deno.env.get('FIREBASE_PROJECT_ID') ?? ''
  const firebaseServiceAcct = Deno.env.get('FIREBASE_SERVICE_ACCOUNT') ?? ''
  if (!supabaseUrl || !serviceKey) return json({ ok: false, error: 'missing env' }, 500)
  if (!firebaseProjectId || !firebaseServiceAcct) {
    console.log('[notify-service-provider] Firebase not configured — skipping')
    return json({ ok: true, skipped: 'no_firebase' })
  }

  const supabase = createClient(supabaseUrl, serviceKey)

  let body: any = {}
  try { body = await req.json() } catch (_) { return json({ ok: false, error: 'bad json' }, 400) }
  const providerId = body.providerId as string | undefined
  const title = (body.title as string | undefined) ?? '🔔 Nova marcação'
  const msgBody = (body.body as string | undefined) ?? ''
  const kind = (body.kind as string | undefined) ?? 'appointment_new'
  const appointmentId = (body.appointmentId as string | undefined) ?? ''
  if (!providerId) return json({ ok: false, error: 'providerId required' }, 400)

  const { data: provider } = await supabase
    .from('service_providers')
    .select('user_id, name')
    .eq('id', providerId)
    .maybeSingle()
  if (!provider?.user_id) {
    console.log(`[notify-service-provider] provider ${providerId} not found / no user`)
    return json({ ok: false, reason: 'provider_not_found' })
  }

  const { data: tokens } = await supabase
    .from('partner_push_tokens')
    .select('id, fcm_token')
    .eq('partner_id', provider.user_id)
    .eq('active', true)
  if (!tokens?.length) {
    console.log(`[notify-service-provider] no active tokens for user ${provider.user_id}`)
    return json({ ok: true, sent: 0, reason: 'no_tokens' })
  }

  let accessToken: string
  try {
    accessToken = await getFirebaseAccessToken(JSON.parse(firebaseServiceAcct))
  } catch (e) {
    console.error('[notify-service-provider] firebase auth error:', e)
    return json({ ok: false, reason: 'firebase_auth_error' })
  }

  const fcmUrl = `https://fcm.googleapis.com/v1/projects/${firebaseProjectId}/messages:send`
  const results = await Promise.allSettled(tokens.map(async (t) => {
    const message = {
      message: {
        token: t.fcm_token,
        notification: { title, body: msgBody },
        data: {
          providerId: String(providerId),
          appointmentId: String(appointmentId),
          type: kind,
        },
        android: {
          priority: 'high',
          notification: {
            channel_id: 'bora_orders_urgent_v2',
            sound: 'bora_alert',
            notification_priority: 'PRIORITY_MAX',
            default_vibrate_timings: true,
            visibility: 'PUBLIC',
          },
        },
        apns: {
          headers: { 'apns-priority': '10' },
          payload: { aps: { sound: 'bora_alert.wav', badge: 1 } },
        },
      },
    }
    const res = await fetch(fcmUrl, {
      method: 'POST',
      headers: { 'Authorization': `Bearer ${accessToken}`, 'Content-Type': 'application/json' },
      body: JSON.stringify(message),
    })
    if (!res.ok) {
      const errBody = await res.json().catch(() => ({}))
      const errorCode = errBody?.error?.details?.[0]?.errorCode ?? ''
      if (errorCode === 'UNREGISTERED' || errorCode === 'INVALID_ARGUMENT') {
        await supabase.from('partner_push_tokens').update({ active: false }).eq('id', t.id)
        console.log(`[notify-service-provider] deactivated stale token ${t.id}`)
      }
      throw new Error(`fcm ${res.status}`)
    }
    return true
  }))

  const sent = results.filter((r) => r.status === 'fulfilled').length
  console.log(`[notify-service-provider] provider=${providerId} sent=${sent}/${tokens.length}`)
  return json({ ok: true, sent, total: tokens.length })
})

// ── Firebase OAuth2 helpers (idênticos a notify-partner/notify-driver) ──────

async function getFirebaseAccessToken(serviceAccount: any): Promise<string> {
  const now = Math.floor(Date.now() / 1000)
  const header = { alg: 'RS256', typ: 'JWT' }
  const payload = {
    iss: serviceAccount.client_email,
    scope: 'https://www.googleapis.com/auth/firebase.messaging',
    aud: 'https://oauth2.googleapis.com/token',
    exp: now + 3600,
    iat: now,
  }
  const encodedHeader = b64url(JSON.stringify(header))
  const encodedPayload = b64url(JSON.stringify(payload))
  const signingInput = `${encodedHeader}.${encodedPayload}`
  const pemBody = serviceAccount.private_key
    .replace(/-----BEGIN PRIVATE KEY-----/g, '')
    .replace(/-----END PRIVATE KEY-----/g, '')
    .replace(/\s/g, '')
  const keyBytes = Uint8Array.from(atob(pemBody), (c) => c.charCodeAt(0))
  const cryptoKey = await crypto.subtle.importKey(
    'pkcs8', keyBytes, { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' }, false, ['sign'],
  )
  const sigBuffer = await crypto.subtle.sign(
    'RSASSA-PKCS1-v1_5', cryptoKey, new TextEncoder().encode(signingInput),
  )
  const signature = b64urlBytes(new Uint8Array(sigBuffer))
  const jwt = `${signingInput}.${signature}`
  const tokenRes = await fetch('https://oauth2.googleapis.com/token', {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({
      grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer',
      assertion: jwt,
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

// supabase/functions/notify-service-provider/index.ts — v3 (2026-07-28)
//
// v3: DATA-ONLY (removido o bloco `notification`). Causa raiz do bug "parceiro de
// Serviços não recebe notificação": com bloco `notification` presente, o Android
// desenha a notificação nativa sozinho, o handler FCM em background do Flutter
// (_firebaseMessagingBackgroundHandler) NÃO corre, e por isso nunca se criava a
// notificação PERSISTENTE (ongoing:true + autoCancel:false) — igual ao delivery.
// Também corrigido o channel_id morto `bora_orders_urgent_v2` (o app usa
// `bora_orders_urgent_v3` / `bora_orders`); em data-only o canal é escolhido pelo app.
// Padrão copiado de notify-partner v21 (delivery), que funciona.
// v2: auth alinhada a notify-admin-urgent — verify_jwt=true + role service_role.

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
  if (!authHeader.startsWith('Bearer ')) {
    return json({ ok: false, error: 'forbidden' }, 403)
  }
  try {
    const token = authHeader.substring(7)
    const payload = JSON.parse(atob(token.split('.')[1]))
    if (payload.role !== 'service_role') {
      console.warn('[notify-service-provider] forbidden — role mismatch:', payload.role)
      return json({ ok: false, error: 'forbidden' }, 403)
    }
  } catch (_e) {
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
  const title = (body.title as string | undefined) ?? 'Nova marcacao'
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
    // DATA-ONLY: acorda o handler do Flutter, que desenha a notificacao persistente.
    const message = {
      message: {
        token: t.fcm_token,
        data: {
          type: kind,
          providerId: String(providerId),
          appointmentId: String(appointmentId),
          title: String(title),
          body: String(msgBody),
        },
        android: { priority: 'high', ttl: '300s' },
        apns: {
          headers: { 'apns-priority': '10', 'apns-push-type': 'background' },
          payload: { aps: { 'content-available': 1, sound: 'bora_alert.wav', 'interruption-level': 'time-sensitive' } },
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
      console.error('[notify-service-provider] fcm error:', JSON.stringify(errBody))
      if (errorCode === 'UNREGISTERED' || errorCode === 'INVALID_ARGUMENT') {
        await supabase.from('partner_push_tokens').update({ active: false }).eq('id', t.id)
        console.log(`[notify-service-provider] deactivated stale token ${t.id}`)
      }
      throw new Error(`fcm ${res.status}`)
    }
    return true
  }))

  const sent = results.filter((r) => r.status === 'fulfilled').length
  console.log(`[notify-service-provider] v3 provider=${providerId} kind=${kind} sent=${sent}/${tokens.length}`)
  return json({ ok: true, sent, total: tokens.length })
})

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

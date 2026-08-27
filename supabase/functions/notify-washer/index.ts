// @ts-nocheck
// supabase/functions/notify-washer/index.ts  v1
//
// Push da Lavagem Auto (lavador e cliente).
//
// DATA-ONLY, DE PROPOSITO — esta familia de bug ja mordeu tres vezes
// (notify-admin-urgent, notify-service-provider, notify-partner):
// se o payload FCM levar bloco `notification`, o Android desenha pelo tray,
// o _firebaseMessagingBackgroundHandler do Flutter NAO corre, e a notificacao
// persistente nunca aparece. Por isso NAO existe aqui bloco `notification`:
// o title/body viajam dentro de `data` e e o Dart que desenha, com
// Importance.max no canal urgente.
//
// O molde (notify-cleaner) ainda usa `notification` — foi deliberadamente
// NAO copiado nessa parte.
//
// Body esperado:
//   { targetUserId: uuid, title: string, body: string,
//     kind?: string, bookingId?: string, type?: 'carwash_offer'|'carwash_status' }
//
// Secrets: FIREBASE_PROJECT_ID, FIREBASE_SERVICE_ACCOUNT.

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
    console.warn('[notify-washer] Firebase env vars not set — skipping push')
    return json({ ok: false, reason: 'firebase_not_configured' })
  }

  let payload: any
  try { payload = await req.json() } catch { return json({ ok: false, error: 'Invalid JSON body' }, 400) }

  // aceita targetUserId (novo) e washerUserId (alias defensivo)
  const targetUserId = (payload.targetUserId ?? payload.washerUserId) as string | undefined
  const title        = payload.title      as string | undefined
  const body         = payload.body       as string | undefined
  const kind         = payload.kind       as string | undefined
  const bookingId    = payload.bookingId  as string | undefined
  const notifType    = (payload.type as string | undefined) ?? 'carwash_status'

  if (!targetUserId)  return json({ ok: false, error: 'targetUserId is required' }, 400)
  if (!title || !body) return json({ ok: false, error: 'title/body required' }, 400)

  const supabase = createClient(supabaseUrl, serviceKey)

  const { data: user, error: userErr } = await supabase
    .from('users').select('fcm_token').eq('id', targetUserId).maybeSingle()

  if (userErr) {
    console.error('[notify-washer] DB error:', JSON.stringify(userErr))
    return json({ ok: false, reason: 'db_error', detail: userErr.message })
  }
  if (!user?.fcm_token) {
    console.log(`[notify-washer] No FCM token for user ${targetUserId}`)
    return json({ ok: false, reason: 'no_fcm_token' })
  }

  let accessToken: string
  try {
    accessToken = await getFirebaseAccessToken(JSON.parse(firebaseServiceAcct))
  } catch (e) {
    console.error('[notify-washer] Firebase auth error:', e)
    return json({ ok: false, reason: 'firebase_auth_error' })
  }

  // Oferta = canal urgente insistente; mudanca de estado = canal normal.
  const isOffer   = notifType === 'carwash_offer'
  const channelId = isOffer ? 'bora_orders_urgent_v3' : 'bora_orders'
  const sound     = isOffer ? 'bora_alert' : 'default'

  // DATA-ONLY: title/body vao DENTRO do data. Sem bloco `notification`.
  const dataPayload: Record<string, string> = {
    type: notifType,
    title: String(title),
    body: String(body),
    channelId,
    sound,
    ...(bookingId ? { bookingId: String(bookingId) } : {}),
    ...(kind ? { kind: String(kind) } : {}),
  }

  const message = {
    message: {
      token: user.fcm_token,
      data: dataPayload,
      android: { priority: 'high' },
      apns: {
        headers: { 'apns-priority': '5', 'apns-push-type': 'background' },
        payload: { aps: { 'content-available': 1 } },
      },
    },
  }

  const fcmUrl = `https://fcm.googleapis.com/v1/projects/${firebaseProjectId}/messages:send`
  const fcmRes = await fetch(fcmUrl, {
    method: 'POST',
    headers: { 'Authorization': `Bearer ${accessToken}`, 'Content-Type': 'application/json' },
    body: JSON.stringify(message),
  })
  const fcmBody = await fcmRes.json().catch(() => ({}))

  if (!fcmRes.ok) {
    console.error(`[notify-washer] FCM error ${fcmRes.status}:`, JSON.stringify(fcmBody))
    const errorCode = fcmBody?.error?.details?.[0]?.errorCode ?? ''
    if (errorCode === 'UNREGISTERED' || errorCode === 'INVALID_ARGUMENT') {
      await supabase.from('users').update({ fcm_token: null }).eq('id', targetUserId)
    }
    return json({ ok: false, reason: 'fcm_error', detail: fcmBody })
  }

  console.log(`[notify-washer v1 data-only] ok -> ${targetUserId} (${notifType})`)
  return json({ ok: true })
})

function json(obj: any, status = 200): Response {
  return new Response(JSON.stringify(obj), { status, headers: { ...corsHeaders, 'Content-Type': 'application/json' } })
}

async function getFirebaseAccessToken(serviceAccount: any): Promise<string> {
  const now = Math.floor(Date.now() / 1000)
  const header     = { alg: 'RS256', typ: 'JWT' }
  const payloadJwt = {
    iss:   serviceAccount.client_email,
    scope: 'https://www.googleapis.com/auth/firebase.messaging',
    aud:   'https://oauth2.googleapis.com/token',
    exp:   now + 3600,
    iat:   now,
  }
  const encodedHeader  = b64url(JSON.stringify(header))
  const encodedPayload = b64url(JSON.stringify(payloadJwt))
  const signingInput   = `${encodedHeader}.${encodedPayload}`
  const pemBody = serviceAccount.private_key
    .replace(/-----BEGIN PRIVATE KEY-----/g, '')
    .replace(/-----END PRIVATE KEY-----/g, '')
    .replace(/\s/g, '')
  const keyBytes  = Uint8Array.from(atob(pemBody), (c) => c.charCodeAt(0))
  const cryptoKey = await crypto.subtle.importKey(
    'pkcs8', keyBytes,
    { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' }, false, ['sign'],
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
      assertion:  jwt,
    }),
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

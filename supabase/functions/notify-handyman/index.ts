// @ts-nocheck
// supabase/functions/notify-handyman/index.ts  v1 (31/10/2026, retoma-geral-2026-10-31, bloco 1)
//
// Push da Casa & Manutenção (profissional e cliente). Chamada só pelo servidor, por
// public._casa_notificar (parte 2b, já no ar), com o corpo:
//   { targetUserId: uuid, papel: 'handyman'|'client', bookingId: uuid|'', title, body,
//     kind: 'casa_offer'|'casa_status', type: 'casa_offer'|'casa_status' }
//
// Molde: notify-washer v2 (mesma autenticação, mesmos canais, DATA-ONLY de propósito: sem bloco
// `notification`, para o _firebaseMessagingBackgroundHandler do Flutter correr e desenhar o toque
// persistente da oferta). Diferença: o servidor diz o papel do destinatário, por isso o cliente
// recebe nos aparelhos dele (client_push_tokens) e o profissional nos do papel handyman.
//
// ESTADO: PUBLICADO a 01/11/2026 (missão app-fechar-2026-11-01, achado C4) pelo CLI
// `supabase functions deploy notify-handyman --use-api`, verify_jwt=true. Prova: sem chave → 401;
// chamada pelo servidor com a chave do vault → 200 (e2e_log 6035). O _casa_notificar também grava
// o aviso dentro da app.
// Secrets: FIREBASE_PROJECT_ID, FIREBASE_SERVICE_ACCOUNT (os mesmos das outras notify-*).

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'
import { secretKey } from '../_shared/keys.ts'
import { exigirServidorOuAdmin } from '../_shared/chaves.ts'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders })
  const bloqueio = await exigirServidorOuAdmin(req, corsHeaders)
  if (bloqueio) return bloqueio

  const firebaseProjectId   = Deno.env.get('FIREBASE_PROJECT_ID')
  const firebaseServiceAcct = Deno.env.get('FIREBASE_SERVICE_ACCOUNT')
  const supabaseUrl         = Deno.env.get('SUPABASE_URL')!
  const serviceKey          = secretKey()!

  if (!firebaseProjectId || !firebaseServiceAcct) {
    console.warn('[notify-handyman] Firebase env vars not set — skipping push')
    return json({ ok: false, reason: 'firebase_not_configured' })
  }

  let payload: any
  try { payload = await req.json() } catch { return json({ ok: false, error: 'Invalid JSON body' }, 400) }

  const targetUserId = payload.targetUserId as string | undefined
  const papel        = (payload.papel as string | undefined) === 'client' ? 'client' : 'handyman'
  const title        = payload.title     as string | undefined
  const body         = payload.body      as string | undefined
  const kind         = payload.kind      as string | undefined
  const bookingId    = payload.bookingId as string | undefined
  const notifType    = (payload.type as string | undefined) ?? 'casa_status'

  if (!targetUserId)   return json({ ok: false, error: 'targetUserId is required' }, 400)
  if (!title || !body) return json({ ok: false, error: 'title/body required' }, 400)

  const supabase = createClient(supabaseUrl, serviceKey)
  const tokens = new Set<string>()

  if (papel === 'handyman') {
    // Portão "queres receber deste papel?": só para o profissional.
    const { data: quer } = await supabase.rpc('aceita_papel', { p_user_id: targetUserId, p_papel: 'handyman' })
    if (quer === false) {
      console.log(`[notify-handyman] ${targetUserId} tem o papel Casa desligado — nao se envia`)
      return json({ ok: false, reason: 'papel_desligado' })
    }
    const { data: linhas, error } = await supabase
      .from('provider_push_tokens').select('fcm_token')
      .eq('user_id', targetUserId).eq('role', 'handyman').eq('active', true)
    if (error) console.error('[notify-handyman] erro a ler provider_push_tokens:', JSON.stringify(error))
    for (const l of linhas ?? []) if (l?.fcm_token) tokens.add(l.fcm_token as string)
  } else {
    const { data: linhas, error } = await supabase
      .from('client_push_tokens').select('fcm_token')
      .eq('user_id', targetUserId).eq('active', true)
    if (error) console.error('[notify-handyman] erro a ler client_push_tokens:', JSON.stringify(error))
    for (const l of linhas ?? []) if (l?.fcm_token) tokens.add(l.fcm_token as string)
  }

  // A coluna antiga de um aparelho só (users.fcm_token) serve os dois, como no notify-washer.
  const { data: user, error: userErr } = await supabase
    .from('users').select('fcm_token').eq('id', targetUserId).maybeSingle()
  if (userErr) console.error('[notify-handyman] DB error:', JSON.stringify(userErr))
  else if (user?.fcm_token) tokens.add(user.fcm_token as string)

  if (tokens.size === 0) {
    console.log(`[notify-handyman] Sem aparelho registado para ${papel} ${targetUserId}`)
    return json({ ok: false, reason: 'no_fcm_token' })
  }

  let accessToken: string
  try {
    accessToken = await getFirebaseAccessToken(JSON.parse(firebaseServiceAcct))
  } catch (e) {
    console.error('[notify-handyman] Firebase auth error:', e)
    return json({ ok: false, reason: 'firebase_auth_error' })
  }

  const isOffer   = notifType === 'casa_offer'
  const channelId = isOffer ? 'bora_orders_urgent_v3' : 'bora_orders'
  const sound     = isOffer ? 'bora_alert' : 'default'

  const dataPayload: Record<string, string> = {
    type: notifType,
    title: String(title),
    body: String(body),
    channelId,
    sound,
    ...(bookingId ? { bookingId: String(bookingId) } : {}),
    ...(kind ? { kind: String(kind) } : {}),
  }

  const baseMessage = {
    data: dataPayload,
    android: { priority: 'high' },
    apns: {
      headers: { 'apns-priority': '10', 'apns-push-type': 'alert' },
      payload: { aps: { alert: { title: String(title), body: String(body) }, sound: isOffer ? 'bora_alert.wav' : 'default', 'content-available': 1 } },
    },
  }

  const fcmUrl = `https://fcm.googleapis.com/v1/projects/${firebaseProjectId}/messages:send`
  let enviados = 0
  const falhas: string[] = []

  for (const fcmToken of tokens) {
    const message = { message: { ...baseMessage, token: fcmToken } }
    const fcmRes = await fetch(fcmUrl, {
      method: 'POST',
      headers: { 'Authorization': `Bearer ${accessToken}`, 'Content-Type': 'application/json' },
      body: JSON.stringify(message),
    })
    const fcmBody = await fcmRes.json().catch(() => ({}))
    if (fcmRes.ok) { enviados++; continue }

    console.error(`[notify-handyman] FCM ${fcmRes.status}:`, JSON.stringify(fcmBody))
    falhas.push(String(fcmBody?.error?.details?.[0]?.errorCode ?? fcmRes.status))
    const errorCode = fcmBody?.error?.details?.[0]?.errorCode ?? ''
    if (errorCode === 'UNREGISTERED' || errorCode === 'INVALID_ARGUMENT') {
      if (papel === 'handyman') {
        await supabase.from('provider_push_tokens')
          .update({ active: false, last_fail_at: new Date().toISOString() })
          .eq('user_id', targetUserId).eq('role', 'handyman').eq('fcm_token', fcmToken)
      } else {
        await supabase.from('client_push_tokens')
          .update({ active: false })
          .eq('user_id', targetUserId).eq('fcm_token', fcmToken)
      }
      await supabase.from('users').update({ fcm_token: null })
        .eq('id', targetUserId).eq('fcm_token', fcmToken)
    }
  }

  if (enviados === 0) return json({ ok: false, reason: 'fcm_error', detail: falhas })
  console.log(`[notify-handyman v1] enviado a ${enviados}/${tokens.size} aparelho(s) de ${papel} ${targetUserId} (${notifType})`)
  return json({ ok: true, enviados, aparelhos: tokens.size })
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

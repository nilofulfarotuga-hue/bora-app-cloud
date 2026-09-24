// @ts-nocheck
// supabase/functions/notify-admin-message/index.ts  v1  2026-09-14
//
// Mensagem livre do PAINEL ADMIN para uma pessoa qualquer (motorista,
// estafeta, lavador, cliente). Existe porque `admin_send_push_notification`
// apontava para `notify-driver`, que NAO serve: essa funcao e a oferta de
// pedido de entrega e exige um `orderId` em estado callingDriver, por isso
// respondia sempre 400 e o painel nunca entregou uma unica mensagem.
//
// DATA-ONLY de proposito (mesma licao ja escrita em notify-washer): com
// bloco `notification` o Android desenha pelo tray e o handler do Flutter
// nao corre.
//
// Body: { targetUserId: uuid, title: string, body: string, kind?: string,
//         relatedId?: string }
// Junta os aparelhos da pessoa em TODAS as tabelas de tokens — quem acumula
// papeis tem o aparelho registado num sitio so, e o admin nao tem de saber
// em qual.
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
    return json({ ok: false, reason: 'firebase_not_configured' })
  }

  let payload: any
  try { payload = await req.json() } catch { return json({ ok: false, error: 'Invalid JSON body' }, 400) }

  const targetUserId = String(payload?.targetUserId ?? payload?.userId ?? payload?.driverId ?? '')
  const title = payload?.title ? String(payload.title) : ''
  const body  = payload?.body  ? String(payload.body)  : ''
  const kind  = payload?.kind ? String(payload.kind) : 'admin_message'
  const relatedId = payload?.relatedId ? String(payload.relatedId) : ''

  if (!targetUserId)   return json({ ok: false, error: 'targetUserId is required' }, 400)
  if (!title || !body) return json({ ok: false, error: 'title/body required' }, 400)

  const supabase = createClient(supabaseUrl, serviceKey)

  // Aparelhos da pessoa, venham de onde vierem.
  const tokens = new Set<string>()
  const origem: Record<string, string> = {}

  const addFrom = async (tabela: string) => {
    const { data, error } = await supabase
      .from(tabela).select('fcm_token').eq('user_id', targetUserId).eq('active', true)
    if (error) { console.error(`[notify-admin-message] ${tabela}:`, JSON.stringify(error)); return }
    for (const l of data ?? []) if (l?.fcm_token) { tokens.add(l.fcm_token); origem[l.fcm_token] = tabela }
  }

  await addFrom('driver_push_tokens')
  await addFrom('provider_push_tokens')
  await addFrom('client_push_tokens')

  const { data: u } = await supabase.from('users').select('fcm_token').eq('id', targetUserId).maybeSingle()
  if (u?.fcm_token) { tokens.add(u.fcm_token); origem[u.fcm_token] = origem[u.fcm_token] ?? 'users' }

  if (tokens.size === 0) return json({ ok: false, reason: 'no_fcm_token' })

  let accessToken: string
  try { accessToken = await getFirebaseAccessToken(JSON.parse(firebaseServiceAcct)) }
  catch (e) { console.error('[notify-admin-message] firebase auth:', e); return json({ ok: false, reason: 'firebase_auth_error' }) }

  const dataPayload: Record<string, string> = {
    type: 'admin_message',
    kind,
    title,
    body,
    channelId: 'bora_orders',
    sound: 'default',
    ...(relatedId ? { relatedId } : {}),
  }

  const fcmUrl = `https://fcm.googleapis.com/v1/projects/${firebaseProjectId}/messages:send`
  let enviados = 0
  const falhas: string[] = []

  for (const fcmToken of tokens) {
    const message = {
      message: {
        token: fcmToken,
        data: dataPayload,
        android: { priority: 'high' },
        apns: {
          headers: { 'apns-priority': '5', 'apns-push-type': 'background' },
          payload: { aps: { 'content-available': 1 } },
        },
      },
    }
    const res = await fetch(fcmUrl, {
      method: 'POST',
      headers: { Authorization: `Bearer ${accessToken}`, 'Content-Type': 'application/json' },
      body: JSON.stringify(message),
    })
    const resBody = await res.json().catch(() => ({}))
    if (res.ok) { enviados++; continue }

    const errorCode = resBody?.error?.details?.[0]?.errorCode ?? String(res.status)
    falhas.push(errorCode)
    console.error('[notify-admin-message] FCM', res.status, JSON.stringify(resBody))
    if (errorCode === 'UNREGISTERED' || errorCode === 'INVALID_ARGUMENT') {
      const tabela = origem[fcmToken]
      if (tabela && tabela !== 'users') {
        await supabase.from(tabela).update({ active: false }).eq('user_id', targetUserId).eq('fcm_token', fcmToken)
      } else if (tabela === 'users') {
        await supabase.from('users').update({ fcm_token: null }).eq('id', targetUserId).eq('fcm_token', fcmToken)
      }
    }
  }

  if (enviados === 0) return json({ ok: false, reason: 'fcm_error', detail: falhas })
  console.log(`[notify-admin-message] enviado a ${enviados}/${tokens.size} aparelho(s) de ${targetUserId}`)
  return json({ ok: true, enviados, aparelhos: tokens.size })
})

function json(obj: any, status = 200): Response {
  return new Response(JSON.stringify(obj), { status, headers: { ...corsHeaders, 'Content-Type': 'application/json' } })
}

async function getFirebaseAccessToken(serviceAccount: any): Promise<string> {
  const now = Math.floor(Date.now() / 1000)
  const header = { alg: 'RS256', typ: 'JWT' }
  const payloadJwt = {
    iss: serviceAccount.client_email,
    scope: 'https://www.googleapis.com/auth/firebase.messaging',
    aud: 'https://oauth2.googleapis.com/token',
    exp: now + 3600,
    iat: now,
  }
  const encodedHeader = b64url(JSON.stringify(header))
  const encodedPayload = b64url(JSON.stringify(payloadJwt))
  const signingInput = `${encodedHeader}.${encodedPayload}`
  const pemBody = serviceAccount.private_key
    .replace(/-----BEGIN PRIVATE KEY-----/g, '')
    .replace(/-----END PRIVATE KEY-----/g, '')
    .replace(/\s/g, '')
  const keyBytes = Uint8Array.from(atob(pemBody), (c) => c.charCodeAt(0))
  const cryptoKey = await crypto.subtle.importKey('pkcs8', keyBytes, { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' }, false, ['sign'])
  const sigBuffer = await crypto.subtle.sign('RSASSA-PKCS1-v1_5', cryptoKey, new TextEncoder().encode(signingInput))
  const jwt = `${signingInput}.${b64urlBytes(new Uint8Array(sigBuffer))}`
  const tokenRes = await fetch('https://oauth2.googleapis.com/token', {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({ grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer', assertion: jwt }),
  })
  const tokenData = await tokenRes.json()
  if (!tokenData.access_token) throw new Error('Google token exchange failed')
  return tokenData.access_token
}
function b64url(str: string): string { return btoa(unescape(encodeURIComponent(str))).replace(/\+/g, '-').replace(/\//g, '_').replace(/=/g, '') }
function b64urlBytes(bytes: Uint8Array): string { return btoa(String.fromCharCode(...bytes)).replace(/\+/g, '-').replace(/\//g, '_').replace(/=/g, '') }

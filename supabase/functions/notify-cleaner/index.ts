// @ts-nocheck
// supabase/functions/notify-cleaner/index.ts  v1
//
// MEGA-FIX 2026-07-18 Parte 7 — push dedicado à profissional de limpeza.
//
// PORQUÊ dedicado (padrão notify-partner): a `notify-client` entregava a notificação de limpeza
// no canal fraco `bora_orders` e o `_cleaning_notify_user` engolia qualquer erro em silêncio
// (EXCEPTION WHEN OTHERS THEN NULL) → a profissional não recebia nada e não havia rasto.
// Aqui: canal URGENTE `bora_orders_urgent_v3` (som `bora_alert`) para ofertas, resolve o token
// FCM da profissional a partir de `users.fcm_token` (cleaners.user_id → users.id), e devolve
// razão explícita quando não há token/erro (o chamador grava em notification_failures).
//
// Body esperado:
//   { cleanerUserId: uuid, title: string, body: string,
//     kind?: string, bookingId?: string, type?: 'cleaning_offer'|'cleaning_status' }
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
    console.warn('[notify-cleaner] Firebase env vars not set — skipping push')
    return json({ ok: false, reason: 'firebase_not_configured' })
  }

  let payload: any
  try { payload = await req.json() } catch { return json({ ok: false, error: 'Invalid JSON body' }, 400) }

  const cleanerUserId = payload.cleanerUserId as string | undefined
  const title         = payload.title         as string | undefined
  const body          = payload.body          as string | undefined
  const kind          = payload.kind          as string | undefined
  const bookingId     = payload.bookingId     as string | undefined
  const notifType     = (payload.type as string | undefined) ?? 'cleaning_status'

  if (!cleanerUserId) return json({ ok: false, error: 'cleanerUserId is required' }, 400)
  if (!title || !body) return json({ ok: false, error: 'title/body required' }, 400)

  const supabase = createClient(supabaseUrl, serviceKey)

  // A pessoa quer receber pedidos deste papel hoje?
  //
  // Quem acumula papeis liga e desliga cada um na caixa "O que queres
  // aceitar?". Sem preferencia gravada = sim, que e o comportamento de
  // sempre. Sem esta verificacao o interruptor da caixa era decorativo.
  const { data: quer } = await supabase.rpc('aceita_papel', {
    p_user_id: cleanerUserId, p_papel: 'cleaner',
  })
  if (quer === false) {
    console.log(`[notify-cleaner] cleaner ${cleanerUserId} tem o papel desligado — nao se envia`)
    return json({ ok: false, reason: 'papel_desligado' })
  }

  // [2026-08-28] Tokens de TODOS os aparelhos deste cleaner.
  //
  // Antes lia-se so `users.fcm_token`, a coluna antiga de um aparelho unico —
  // e ela esta vazia para os cleaners que existem, porque nada a preenchia.
  // A funcao devolvia `no_fcm_token` e ninguem era chamado. Agora junta-se a
  // tabela nova `provider_push_tokens`, que guarda um aparelho por linha e
  // por papel, com a coluna antiga como recurso.
  const tokens = new Set<string>()

  const { data: linhas, error: tokensErr } = await supabase
    .from('provider_push_tokens')
    .select('fcm_token')
    .eq('user_id', cleanerUserId)
    .eq('role', 'cleaner')
    .eq('active', true)
  if (tokensErr) {
    console.error('[notify-cleaner] erro a ler provider_push_tokens:', JSON.stringify(tokensErr))
  } else {
    for (const l of linhas ?? []) if (l?.fcm_token) tokens.add(l.fcm_token as string)
  }

  const { data: user, error: userErr } = await supabase
    .from('users').select('fcm_token').eq('id', cleanerUserId).maybeSingle()
  if (userErr) {
    console.error('[notify-cleaner] DB error:', JSON.stringify(userErr))
  } else if (user?.fcm_token) {
    tokens.add(user.fcm_token as string)
  }

  if (tokens.size === 0) {
    console.log(`[notify-cleaner] Sem aparelho registado para cleaner ${cleanerUserId}`)
    return json({ ok: false, reason: 'no_fcm_token' })
  }

  let accessToken: string
  try {
    accessToken = await getFirebaseAccessToken(JSON.parse(firebaseServiceAcct))
  } catch (e) {
    console.error('[notify-cleaner] Firebase auth error:', e)
    return json({ ok: false, reason: 'firebase_auth_error' })
  }

  // Oferta (cleaning_offer) = canal urgente insistente; estado = canal normal.
  const isOffer = notifType === 'cleaning_offer'
  const channelId = isOffer ? 'bora_orders_urgent_v3' : 'bora_orders'
  const sound = isOffer ? 'bora_alert' : 'default'

  const dataPayload: Record<string, string> = {
    type: notifType,
    ...(bookingId ? { bookingId: String(bookingId) } : {}),
    ...(kind ? { kind: String(kind) } : {}),
  }

  const baseMessage = {
      notification: { title, body },
      data: dataPayload,
      android: { priority: 'high', notification: { channel_id: channelId, sound } },
      apns: { headers: { 'apns-priority': '10' }, payload: { aps: { sound, badge: 1, 'content-available': 1 } } },
  }

  // Envia a TODOS os aparelhos. Um token morto e desligado sozinho, sem
  // levar os outros a frente — a pessoa pode ter dois telemoveis.
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

    console.error(`[notify-cleaner] FCM ${fcmRes.status}:`, JSON.stringify(fcmBody))
    falhas.push(String(fcmBody?.error?.details?.[0]?.errorCode ?? fcmRes.status))
    const errorCode = fcmBody?.error?.details?.[0]?.errorCode ?? ''
    if (errorCode === 'UNREGISTERED' || errorCode === 'INVALID_ARGUMENT') {
      await supabase.from('provider_push_tokens')
        .update({ active: false, last_fail_at: new Date().toISOString() })
        .eq('user_id', cleanerUserId).eq('role', 'cleaner').eq('fcm_token', fcmToken)
      await supabase.from('users').update({ fcm_token: null })
        .eq('id', cleanerUserId).eq('fcm_token', fcmToken)
    }
  }

  if (enviados === 0) {
    return json({ ok: false, reason: 'fcm_error', detail: falhas })
  }
  console.log(`[notify-cleaner v2] ✓ enviado a ${enviados}/${tokens.size} aparelho(s) de ${cleanerUserId} (${notifType})`)
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

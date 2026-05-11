// @ts-nocheck
// supabase/functions/notify-chat-message/index.ts
//
// 5G — Sends FCM push notifications (HTTP v1 OAuth2) to ALL active tokens
// of the chat message recipient (multi-device, Decisão A).
//
// Trigger: AFTER INSERT on `public.messages`.
//
// Recipient rule (since `messages` has no sender_id):
//   - sender_type='client'  → recipient = order.assigned_driver_id (driver)
//   - sender_type='driver'  → recipient = order.user_id (client)
//   - other sender_type     → skip (no push)
//
// Decisão B: dispara SEMPRE (mesmo com app aberta).
// Decisão C: FCM 4xx UNREGISTERED/INVALID_ARGUMENT → mark_token_failed
// (fail_count+1, marca active=false após 3 falhas).
//
// Required Supabase secrets:
//   FIREBASE_PROJECT_ID
//   FIREBASE_SERVICE_ACCOUNT (JSON of service account key)
//
// Auto-injected: SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY.
//
// Returns 200 always (FCM failures are logged, not thrown). Caller is a
// trigger that must NEVER block INSERT.

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

  if (!firebaseProjectId || !firebaseServiceAcct) {
    console.warn('[notify-chat-message] Firebase env vars not set — skipping push')
    return json({ ok: false, reason: 'firebase_not_configured' })
  }

  let messageId: string
  try {
    const body = await req.json()
    messageId = String(body.message_id ?? '')
  } catch {
    return json({ ok: false, error: 'invalid_json' }, 400)
  }

  if (!messageId) {
    return json({ ok: false, error: 'message_id required' }, 400)
  }

  const supabase = createClient(supabaseUrl, serviceKey)

  // ── Fetch message + order ────────────────────────────────────────────────
  const { data: msg, error: msgErr } = await supabase
    .from('messages')
    .select('id, order_id, sender_type, message, created_at')
    .eq('id', messageId)
    .maybeSingle()

  if (msgErr) {
    console.error('[notify-chat-message] message query error:', JSON.stringify(msgErr))
    return json({ ok: false, reason: 'db_error' })
  }
  if (!msg) {
    console.log(`[notify-chat-message] message ${messageId} not found`)
    return json({ ok: false, reason: 'not_found' })
  }
  if (!msg.order_id) {
    return json({ ok: false, reason: 'no_order_id' })
  }

  // orders.id is TEXT but messages.order_id is UUID — cast to text for lookup.
  const { data: order, error: orderErr } = await supabase
    .from('orders')
    .select('id, user_id, assigned_driver_id, vendor_name')
    .eq('id', String(msg.order_id))
    .maybeSingle()

  if (orderErr) {
    console.error('[notify-chat-message] order query error:', JSON.stringify(orderErr))
    return json({ ok: false, reason: 'db_error' })
  }
  if (!order) {
    return json({ ok: false, reason: 'order_not_found' })
  }

  // ── Determine recipient ──────────────────────────────────────────────────
  let recipientUserId: string | null = null
  let recipientTable: 'client_push_tokens' | 'driver_push_tokens' | null = null
  const senderType = String(msg.sender_type ?? '').toLowerCase()

  if (senderType === 'client') {
    recipientUserId = order.assigned_driver_id ? String(order.assigned_driver_id) : null
    recipientTable  = 'driver_push_tokens'
  } else if (senderType === 'driver') {
    recipientUserId = order.user_id ? String(order.user_id) : null
    recipientTable  = 'client_push_tokens'
  } else {
    console.log(`[notify-chat-message] sender_type=${senderType} — skipping`)
    return json({ ok: false, reason: 'unsupported_sender_type' })
  }

  if (!recipientUserId || !recipientTable) {
    console.log(`[notify-chat-message] no recipient for message ${messageId}`)
    return json({ ok: false, reason: 'no_recipient' })
  }

  // ── Fetch ALL active tokens (Decisão A multi-device) ─────────────────────
  const { data: tokens, error: tokensErr } = await supabase
    .from(recipientTable)
    .select('fcm_token')
    .eq('user_id', recipientUserId)
    .eq('active', true)

  if (tokensErr) {
    console.error('[notify-chat-message] tokens query error:', JSON.stringify(tokensErr))
    return json({ ok: false, reason: 'db_error' })
  }

  const tokenList = tokens ?? []
  if (tokenList.length === 0) {
    console.log(`[notify-chat-message] no active tokens for user ${recipientUserId}`)
    return json({ ok: true, sent: 0, reason: 'no_tokens' })
  }

  // ── Obtain Firebase OAuth2 access token ──────────────────────────────────
  let accessToken: string
  try {
    const serviceAccount = JSON.parse(firebaseServiceAcct)
    accessToken = await getFirebaseAccessToken(serviceAccount)
  } catch (e) {
    console.error('[notify-chat-message] firebase auth error:', e)
    return json({ ok: false, reason: 'firebase_auth_error' })
  }

  // ── Build notification ───────────────────────────────────────────────────
  const senderLabel = senderType === 'client' ? 'Cliente' : 'Estafeta'
  const vendorPart  = order.vendor_name ? ` • ${order.vendor_name}` : ''
  const title = `💬 Nova mensagem do ${senderLabel}${vendorPart}`
  const body  = (msg.message ?? '').trim().slice(0, 140)

  const fcmUrl = `https://fcm.googleapis.com/v1/projects/${firebaseProjectId}/messages:send`

  // ── Send to ALL tokens in parallel ───────────────────────────────────────
  let sent = 0
  let cleaned = 0

  const results = await Promise.allSettled(
    tokenList.map(async (t) => {
      const payload = {
        message: {
          token: t.fcm_token,
          notification: { title, body: body.length > 0 ? body : '...' },
          data: {
            type:       'chat',
            order_id:   String(msg.order_id),
            message_id: String(msg.id),
          },
          android: {
            priority: 'high',
            notification: { channel_id: 'bora_chat' },
          },
          apns: {
            headers: { 'apns-priority': '10' },
            payload: { aps: { sound: 'default', badge: 1 } },
          },
        },
      }
      const r = await fetch(fcmUrl, {
        method: 'POST',
        headers: {
          'Authorization': `Bearer ${accessToken}`,
          'Content-Type':  'application/json',
        },
        body: JSON.stringify(payload),
      })
      return { token: t.fcm_token, status: r.status, body: await r.json().catch(() => ({})) }
    }),
  )

  for (const r of results) {
    if (r.status !== 'fulfilled') continue
    const { token, status, body: respBody } = r.value
    if (status >= 200 && status < 300) {
      sent++
      continue
    }
    const errCode = respBody?.error?.details?.[0]?.errorCode ?? respBody?.error?.status ?? ''
    if (errCode === 'UNREGISTERED' || errCode === 'INVALID_ARGUMENT' || errCode === 'NOT_FOUND') {
      // Decisão C — increment fail_count, mark inactive after 3
      try {
        await supabase.rpc('mark_token_failed', {
          p_table:  recipientTable,
          p_token:  token,
          p_reason: `fcm_${errCode.toLowerCase()}`,
        })
        cleaned++
      } catch (e) {
        console.error('[notify-chat-message] mark_token_failed error:', e)
      }
    }
  }

  console.log(`[notify-chat-message] msg=${messageId} sent=${sent}/${tokenList.length} cleaned=${cleaned}`)
  return json({ ok: true, sent, total: tokenList.length, cleaned })
})

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  })
}

// ── Firebase OAuth2 helpers (same as notify-driver / notify-admin-urgent) ──

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

  const pem = serviceAccount.private_key.replace(/\\n/g, '\n')
  const pkcs8 = pemToPkcs8(pem)
  const cryptoKey = await crypto.subtle.importKey(
    'pkcs8',
    pkcs8,
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
  if (!tokenData.access_token) {
    throw new Error(`Google token exchange failed: ${JSON.stringify(tokenData)}`)
  }
  return tokenData.access_token
}

function pemToPkcs8(pem: string): Uint8Array {
  const b64 = pem
    .replace('-----BEGIN PRIVATE KEY-----', '')
    .replace('-----END PRIVATE KEY-----', '')
    .replace(/\s+/g, '')
  const bin = atob(b64)
  const bytes = new Uint8Array(bin.length)
  for (let i = 0; i < bin.length; i++) bytes[i] = bin.charCodeAt(i)
  return bytes
}

function b64url(str: string): string {
  return btoa(unescape(encodeURIComponent(str)))
    .replace(/\+/g, '-').replace(/\//g, '_').replace(/=/g, '')
}

function b64urlBytes(bytes: Uint8Array): string {
  return btoa(String.fromCharCode(...bytes))
    .replace(/\+/g, '-').replace(/\//g, '_').replace(/=/g, '')
}

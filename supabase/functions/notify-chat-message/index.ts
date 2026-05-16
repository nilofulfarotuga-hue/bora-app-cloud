// @ts-nocheck
// supabase/functions/notify-chat-message/index.ts
//
// v2 — Multi-recipient chat push notifications (FCM HTTP v1 / OAuth2).
//
// Trigger: AFTER INSERT on `public.messages`.
//
// Routing (v2 — all three roles supported):
//   sender_type='client'  → notify: driver (driver_push_tokens) + partner (via RPC)
//   sender_type='driver'  → notify: client (client_push_tokens) + partner (via RPC)
//   sender_type='partner' → notify: client (client_push_tokens) + driver (driver_push_tokens)
//
// Decisão A: multi-device — ALL active tokens per recipient.
// Decisão B: fires even when app is open (foreground banner handled in Flutter).
// Decisão C: FCM 4xx UNREGISTERED/INVALID_ARGUMENT → mark_token_failed.
//
// Partner token lookup: get_partner_fcm_tokens_for_restaurant(restaurant_id)
// (joins partner_push_tokens ← auth.users ← restaurants via email).
//
// Required Supabase secrets:
//   FIREBASE_PROJECT_ID
//   FIREBASE_SERVICE_ACCOUNT (JSON of service account key)
//
// Auto-injected: SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY.
//
// Returns 200 always — trigger must never block INSERT.

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
}

// ── Types ────────────────────────────────────────────────────────────────────

type StandardTable = 'client_push_tokens' | 'driver_push_tokens'

interface StandardLookup {
  kind: 'standard'
  table: StandardTable
  userId: string
}

interface PartnerLookup {
  kind: 'partner'
  restaurantId: string
}

type Lookup = StandardLookup | PartnerLookup

// ── Handler ──────────────────────────────────────────────────────────────────

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

  // ── Fetch message ────────────────────────────────────────────────────────
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

  const senderType = String(msg.sender_type ?? '').toLowerCase()
  if (!['client', 'driver', 'partner'].includes(senderType)) {
    console.log(`[notify-chat-message] sender_type=${senderType} — unsupported`)
    return json({ ok: false, reason: 'unsupported_sender_type' })
  }

  // ── Fetch order (include restaurant_id for partner lookup) ───────────────
  const { data: order, error: orderErr } = await supabase
    .from('orders')
    .select('id, user_id, assigned_driver_id, vendor_name, restaurant_id')
    .eq('id', String(msg.order_id))
    .maybeSingle()

  if (orderErr) {
    console.error('[notify-chat-message] order query error:', JSON.stringify(orderErr))
    return json({ ok: false, reason: 'db_error' })
  }
  if (!order) {
    return json({ ok: false, reason: 'order_not_found' })
  }

  // ── Determine recipients ──────────────────────────────────────────────────
  // sender is excluded; all others in the conversation are notified.
  const lookups: Lookup[] = []

  if (senderType === 'client') {
    if (order.assigned_driver_id)
      lookups.push({ kind: 'standard', table: 'driver_push_tokens', userId: String(order.assigned_driver_id) })
    if (order.restaurant_id)
      lookups.push({ kind: 'partner', restaurantId: String(order.restaurant_id) })
  } else if (senderType === 'driver') {
    if (order.user_id)
      lookups.push({ kind: 'standard', table: 'client_push_tokens', userId: String(order.user_id) })
    if (order.restaurant_id)
      lookups.push({ kind: 'partner', restaurantId: String(order.restaurant_id) })
  } else if (senderType === 'partner') {
    if (order.user_id)
      lookups.push({ kind: 'standard', table: 'client_push_tokens', userId: String(order.user_id) })
    if (order.assigned_driver_id)
      lookups.push({ kind: 'standard', table: 'driver_push_tokens', userId: String(order.assigned_driver_id) })
  }

  if (lookups.length === 0) {
    console.log(`[notify-chat-message] no recipients for msg ${messageId}`)
    return json({ ok: true, sent: 0, reason: 'no_recipients' })
  }

  // ── Firebase access token ────────────────────────────────────────────────
  let accessToken: string
  try {
    const serviceAccount = JSON.parse(firebaseServiceAcct)
    accessToken = await getFirebaseAccessToken(serviceAccount)
  } catch (e) {
    console.error('[notify-chat-message] firebase auth error:', e)
    return json({ ok: false, reason: 'firebase_auth_error' })
  }

  // ── Build notification template ──────────────────────────────────────────
  const senderLabel: Record<string, string> = {
    client: 'Cliente',
    driver: 'Estafeta',
    partner: 'Restaurante',
  }
  const vendorPart = order.vendor_name ? ` • ${order.vendor_name}` : ''
  const title = `💬 ${senderLabel[senderType] ?? 'Utilizador'}${vendorPart}`
  const body  = (msg.message ?? '').trim().slice(0, 140)

  const fcmUrl = `https://fcm.googleapis.com/v1/projects/${firebaseProjectId}/messages:send`

  // ── Send helper ──────────────────────────────────────────────────────────
  async function sendToTokens(
    tokens: Array<{ fcm_token: string }>,
    tableNameForFail: string,
  ): Promise<{ sent: number; cleaned: number }> {
    let sent = 0
    let cleaned = 0
    const results = await Promise.allSettled(
      tokens.map(async (t) => {
        const payload = {
          message: {
            token: t.fcm_token,
            notification: { title, body: body.length > 0 ? body : '...' },
            data: {
              type:        'chat',
              order_id:    String(msg.order_id),
              message_id:  String(msg.id),
              sender_type: senderType,
            },
            android: {
              priority: 'high',
              notification: {
                channel_id: 'bora_chat',
                sound: 'default',
                priority: 'high',
              },
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
        try {
          await supabase.rpc('mark_token_failed', {
            p_table:  tableNameForFail,
            p_token:  token,
            p_reason: `fcm_${errCode.toLowerCase()}`,
          })
          cleaned++
        } catch (e) {
          console.error('[notify-chat-message] mark_token_failed error:', e)
        }
      }
    }
    return { sent, cleaned }
  }

  // ── Process each recipient group ─────────────────────────────────────────
  let totalSent = 0
  let totalCleaned = 0

  for (const lookup of lookups) {
    if (lookup.kind === 'standard') {
      const { data: tokens, error: tokensErr } = await supabase
        .from(lookup.table)
        .select('fcm_token')
        .eq('user_id', lookup.userId)
        .eq('active', true)

      if (tokensErr) {
        console.error(`[notify-chat-message] tokens error (${lookup.table}):`, JSON.stringify(tokensErr))
        continue
      }

      const list = tokens ?? []
      if (list.length === 0) {
        console.log(`[notify-chat-message] no active tokens in ${lookup.table} for user ${lookup.userId}`)
        continue
      }

      const { sent, cleaned } = await sendToTokens(list, lookup.table)
      totalSent += sent
      totalCleaned += cleaned

    } else {
      // Partner lookup via RPC (restaurant_id → email → auth.users → partner_push_tokens)
      const { data: partnerTokens, error: partnerErr } = await supabase
        .rpc('get_partner_fcm_tokens_for_restaurant', { p_restaurant_id: lookup.restaurantId })

      if (partnerErr) {
        console.error('[notify-chat-message] partner tokens rpc error:', JSON.stringify(partnerErr))
        continue
      }

      const list = (partnerTokens ?? []).map((r: any) => ({ fcm_token: r.fcm_token }))
      if (list.length === 0) {
        console.log(`[notify-chat-message] no active partner tokens for restaurant ${lookup.restaurantId}`)
        continue
      }

      const { sent, cleaned } = await sendToTokens(list, 'partner_push_tokens')
      totalSent += sent
      totalCleaned += cleaned
    }
  }

  console.log(`[notify-chat-message] msg=${messageId} sender=${senderType} sent=${totalSent} cleaned=${totalCleaned}`)
  return json({ ok: true, sent: totalSent, cleaned: totalCleaned })
})

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  })
}

// ── Firebase OAuth2 (same implementation as notify-driver / notify-admin-urgent) ──

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

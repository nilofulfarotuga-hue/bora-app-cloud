// @ts-nocheck
// v10 (M11 2026-06-10) — ROOT CAUSE fixes na resolução do destinatário:
//   • orders.driver_id quase nunca é populada → usar assigned_driver_id (canónica);
//   • restaurants tem user_ E user_id divergentes → COALESCE(user_id, user_);
//   • v9 não procurava client_push_tokens (cliente NUNCA recebia push de chat);
//   • partner_push_tokens é keyed por partner_id (v9 usava user_id — coluna inexistente).
// (O trigger _notify_chat_message_trigger v2 passou a enviar o payload completo
//  — antes enviava só {message_id} e esta função devolvia 400 sempre.)
// exec6.23 (2026-05-27) DATA-ONLY + canal v3 unificado.
// Bg handler em notification_service.dart posta rich notif via
// flutter_local_notifications (BigText + som bora_alert).
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'
const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
}
Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders })
  const firebaseProjectId = Deno.env.get('FIREBASE_PROJECT_ID')
  const firebaseServiceAcct = Deno.env.get('FIREBASE_SERVICE_ACCOUNT')
  const supabaseUrl = Deno.env.get('SUPABASE_URL')!
  const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
  console.log('[notify-chat-message] v10 INVOKED data-only')
  if (!firebaseProjectId || !firebaseServiceAcct) {
    return new Response(JSON.stringify({ ok: false, reason: 'firebase_not_configured' }),
      { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' } })
  }
  let messageId, orderId, senderId, senderType, recipientType, body, conversationType
  try {
    const reqBody = await req.json()
    messageId = reqBody.message_id ?? reqBody.messageId
    orderId = reqBody.order_id ?? reqBody.orderId
    senderId = reqBody.sender_id ?? reqBody.senderId
    senderType = reqBody.sender_type ?? reqBody.senderType ?? ''
    recipientType = reqBody.recipient_type ?? reqBody.recipientType ?? ''
    body = (reqBody.body ?? reqBody.message ?? '').toString().substring(0, 140)
    conversationType = reqBody.conversation_type ?? reqBody.conversationType ?? ''
  } catch (e) {
    return new Response(JSON.stringify({ ok: false, error: 'Invalid JSON body' }),
      { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } })
  }
  if (!messageId || !orderId || !senderId) {
    return new Response(JSON.stringify({ ok: false, error: 'message_id, order_id, sender_id required' }),
      { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } })
  }
  const supabase = createClient(supabaseUrl, serviceKey)
  // Determine recipient user_id from order + conversation_type/sender_type.
  const { data: order } = await supabase.from('orders')
    .select('user_id, assigned_driver_id, restaurant_id, vendor_name')
    .eq('id', orderId).maybeSingle()
  if (!order) {
    return new Response(JSON.stringify({ ok: false, reason: 'order_not_found' }),
      { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' } })
  }
  // Compute recipient based on sender_type vs conversation participants.
  let recipientUserId: string | null = null
  let senderName = senderType
  if (senderType === 'client') {
    if (recipientType === 'driver' || conversationType === 'client_driver') recipientUserId = order.assigned_driver_id
    else if (recipientType === 'partner' || conversationType === 'client_partner') {
      const { data: r } = await supabase.from('restaurants').select('user_, user_id').eq('id', order.restaurant_id).maybeSingle()
      recipientUserId = (r?.user_id ?? r?.user_) ?? null
      senderName = 'Cliente'
    }
  } else if (senderType === 'driver') {
    if (recipientType === 'client' || conversationType === 'client_driver') recipientUserId = order.user_id
    else if (recipientType === 'partner' || conversationType === 'driver_partner') {
      const { data: r } = await supabase.from('restaurants').select('user_, user_id').eq('id', order.restaurant_id).maybeSingle()
      recipientUserId = (r?.user_id ?? r?.user_) ?? null
    }
    senderName = 'Estafeta'
  } else if (senderType === 'partner') {
    if (recipientType === 'client' || conversationType === 'client_partner') recipientUserId = order.user_id
    else if (recipientType === 'driver' || conversationType === 'driver_partner') recipientUserId = order.assigned_driver_id
    senderName = order.vendor_name ?? 'Loja'
  }
  if (!recipientUserId) {
    return new Response(JSON.stringify({ ok: false, reason: 'recipient_not_resolved' }),
      { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' } })
  }
  // Fetch all active tokens for recipient (multi-device).
  const tokens: { id: string; fcm_token: string; source: string }[] = []
  const { data: drvTokens } = await supabase.from('driver_push_tokens')
    .select('id, fcm_token').eq('user_id', recipientUserId).eq('active', true)
  if (drvTokens) drvTokens.forEach((t: any) => tokens.push({ id: t.id, fcm_token: t.fcm_token, source: 'driver_push_tokens' }))
  const { data: prtTokens } = await supabase.from('partner_push_tokens')
    .select('id, fcm_token').eq('partner_id', recipientUserId).eq('active', true)
  if (prtTokens) prtTokens.forEach((t: any) => tokens.push({ id: t.id, fcm_token: t.fcm_token, source: 'partner_push_tokens' }))
  const { data: cliTokens } = await supabase.from('client_push_tokens')
    .select('id, fcm_token').eq('user_id', recipientUserId).eq('active', true)
  if (cliTokens) cliTokens.forEach((t: any) => tokens.push({ id: t.id, fcm_token: t.fcm_token, source: 'client_push_tokens' }))
  if (tokens.length === 0) {
    // fallback drivers.fcm_token legacy
    const { data: d } = await supabase.from('drivers').select('fcm_token').eq('id', recipientUserId).maybeSingle()
    if (d?.fcm_token) tokens.push({ id: 'legacy', fcm_token: d.fcm_token, source: 'drivers' })
  }
  if (tokens.length === 0) {
    return new Response(JSON.stringify({ ok: false, reason: 'no_fcm_token' }),
      { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' } })
  }
  let accessToken: string
  try { accessToken = await getFirebaseAccessToken(JSON.parse(firebaseServiceAcct)) }
  catch (e) {
    return new Response(JSON.stringify({ ok: false, reason: 'firebase_auth_error' }),
      { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' } })
  }
  const fcmUrl = `https://fcm.googleapis.com/v1/projects/${firebaseProjectId}/messages:send`
  let sentCount = 0
  for (const tok of tokens) {
    const message = {
      message: {
        token: tok.fcm_token,
        data: {
          type: 'chat',
          order_id: String(orderId),
          message_id: String(messageId),
          sender_id: String(senderId),
          sender_type: String(senderType),
          sender_name: String(senderName),
          body: String(body),
          conversation_type: String(conversationType),
        },
        android: { priority: 'high', ttl: '60s' },
        apns: {
          headers: { 'apns-priority': '10', 'apns-push-type': 'background' },
          payload: { aps: { 'content-available': 1, sound: 'bora_alert.wav', 'interruption-level': 'time-sensitive' } },
        },
      },
    }
    const fcmRes = await fetch(fcmUrl, {
      method: 'POST',
      headers: { 'Authorization': `Bearer ${accessToken}`, 'Content-Type': 'application/json' },
      body: JSON.stringify(message),
    })
    const fcmBody = await fcmRes.json().catch(() => ({}))
    if (fcmRes.ok) sentCount++
    else {
      const errorCode = fcmBody?.error?.details?.[0]?.errorCode ?? ''
      if (errorCode === 'UNREGISTERED' || errorCode === 'INVALID_ARGUMENT') {
        if (tok.source === 'driver_push_tokens' || tok.source === 'partner_push_tokens' || tok.source === 'client_push_tokens') {
          await supabase.from(tok.source).update({ active: false }).eq('id', tok.id)
        } else if (tok.source === 'drivers') {
          await supabase.from('drivers').update({ fcm_token: null }).eq('id', recipientUserId)
        }
      }
    }
  }
  console.log(`[notify-chat-message] v10 order=${orderId} sender=${senderType} recipient=${recipientUserId} sent=${sentCount}/${tokens.length}`)
  return new Response(JSON.stringify({ ok: true, sent: sentCount, total: tokens.length }),
    { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' } })
})
async function getFirebaseAccessToken(serviceAccount: any): Promise<string> {
  const now = Math.floor(Date.now() / 1000)
  const header = { alg: 'RS256', typ: 'JWT' }
  const payload = {
    iss: serviceAccount.client_email,
    scope: 'https://www.googleapis.com/auth/firebase.messaging',
    aud: 'https://oauth2.googleapis.com/token',
    exp: now + 3600, iat: now,
  }
  const encodedHeader = b64url(JSON.stringify(header))
  const encodedPayload = b64url(JSON.stringify(payload))
  const signingInput = `${encodedHeader}.${encodedPayload}`
  const pemBody = serviceAccount.private_key.replace(/-----BEGIN PRIVATE KEY-----/g, '').replace(/-----END PRIVATE KEY-----/g, '').replace(/\s/g, '')
  const keyBytes = Uint8Array.from(atob(pemBody), (c) => c.charCodeAt(0))
  const cryptoKey = await crypto.subtle.importKey('pkcs8', keyBytes, { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' }, false, ['sign'])
  const sigBuffer = await crypto.subtle.sign('RSASSA-PKCS1-v1_5', cryptoKey, new TextEncoder().encode(signingInput))
  const signature = b64urlBytes(new Uint8Array(sigBuffer))
  const jwt = `${signingInput}.${signature}`
  const tokenRes = await fetch('https://oauth2.googleapis.com/token', {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({ grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer', assertion: jwt }),
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

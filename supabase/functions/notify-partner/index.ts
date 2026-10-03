// @ts-nocheck
// v21 fix: partner_push_tokens usa 'partner_id' nao 'user_id'
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
  console.log('[notify-partner] v21 INVOKED data-only')
  if (!firebaseProjectId || !firebaseServiceAcct) {
    return new Response(JSON.stringify({ ok: false, reason: 'firebase_not_configured' }),
      { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' } })
  }
  let restaurantId, orderId, items, total, customerName, kind
  try {
    const body = await req.json()
    restaurantId = body.restaurantId; orderId = body.orderId
    items = body.items ?? 'Novo pedido'
    total = Number(body.total ?? 0)
    customerName = body.customerName ?? ''
    kind = body.kind ?? 'new_order'
  } catch (e) {
    return new Response(JSON.stringify({ ok: false, error: 'Invalid JSON body' }),
      { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } })
  }
  if (!restaurantId || !orderId) {
    return new Response(JSON.stringify({ ok: false, error: 'restaurantId and orderId are required' }),
      { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } })
  }
  const supabase = createClient(supabaseUrl, serviceKey)
  const { data: restaurant } = await supabase.from('restaurants').select('fcm_token, name, user_').eq('id', restaurantId).maybeSingle()
  let fcmToken: string | null = restaurant?.fcm_token ?? null
  let fallbackTokenId: string | null = null
  // FIX v21: coluna correcta e partner_id (nao user_id)
  if (restaurant?.user_) {
    const { data: pushRows } = await supabase.from('partner_push_tokens')
      .select('id, fcm_token').eq('partner_id', restaurant.user_).eq('active', true)
      .order('last_used_at', { ascending: false }).limit(1)
    if (pushRows && pushRows.length > 0) {
      fcmToken = pushRows[0].fcm_token as string
      fallbackTokenId = pushRows[0].id as string
      console.log('[notify-partner] v21 token found via partner_push_tokens')
    } else {
      console.log('[notify-partner] v21 no active token in partner_push_tokens, falling back to restaurants.fcm_token')
    }
  }
  if (!fcmToken) {
    console.log('[notify-partner] v21 no fcm token found for restaurant', restaurantId)
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
  const message = {
    message: {
      token: fcmToken,
      data: {
        orderId: String(orderId), type: kind,
        restaurantId: String(restaurantId),
        items: String(items), total: total.toFixed(2),
        customerName: String(customerName),
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
  if (!fcmRes.ok) {
    console.error(`[notify-partner] v21 FCM error: ${JSON.stringify(fcmBody)}`)
    const errorCode = fcmBody?.error?.details?.[0]?.errorCode ?? ''
    if (errorCode === 'UNREGISTERED' || errorCode === 'INVALID_ARGUMENT') {
      if (fallbackTokenId) await supabase.from('partner_push_tokens').update({ active: false }).eq('id', fallbackTokenId)
      else await supabase.from('restaurants').update({ fcm_token: null }).eq('id', restaurantId)
    }
    return new Response(JSON.stringify({ ok: false, reason: 'fcm_error', detail: fcmBody }),
      { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' } })
  }
  console.log('[notify-partner] v21 FCM sent ok')
  return new Response(JSON.stringify({ ok: true }),
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

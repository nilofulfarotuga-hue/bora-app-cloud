// @ts-nocheck
// supabase/functions/notify-driver/index.ts
// v39 2026-09-12 — stale-offer guard + legacy driver identity fix.
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

  console.log('[notify-driver v39] INVOKED firebase=', !!firebaseProjectId)
  if (!firebaseProjectId || !firebaseServiceAcct) return json({ ok:false, reason:'firebase_not_configured' })

  let driverId = '', orderId = '', vendorName = 'Pedido', total = 0
  try {
    const body = await req.json()
    driverId = String(body?.driverId ?? '')
    orderId = String(body?.orderId ?? '')
    vendorName = String(body?.vendorName ?? 'Pedido')
    total = Number(body?.total ?? 0)
  } catch (_) { return json({ ok:false, error:'Invalid JSON body' }, 400) }
  if (!driverId || !orderId) return json({ ok:false, error:'driverId and orderId are required' }, 400)

  const supabase = createClient(supabaseUrl, serviceKey)

  const { data: quer } = await supabase.rpc('aceita_papel', { p_user_id: driverId, p_papel: 'delivery' })
  if (quer === false) return json({ ok:false, reason:'papel_desligado' })

  // Guard against stale async pg_net invocations: only send if this driver STILL owns the offer.
  const { data: order, error: orderErr } = await supabase
    .from('orders')
    .select('status,current_driver_offer_id,driver_offer_expires_at,distance_km,driver_earnings')
    .eq('id', orderId)
    .maybeSingle()
  if (orderErr) return json({ ok:false, reason:'order_lookup_error' })
  if (!order || order.status !== 'callingDriver' || String(order.current_driver_offer_id ?? '') !== driverId) {
    console.log(`[notify-driver v39] stale offer skipped order=${orderId} driver=${driverId}`)
    return json({ ok:false, reason:'stale_offer' })
  }
  const expiresAtMs = order.driver_offer_expires_at ? Date.parse(order.driver_offer_expires_at) : 0
  if (!expiresAtMs || expiresAtMs <= Date.now()) {
    console.log(`[notify-driver v39] expired offer skipped order=${orderId} driver=${driverId}`)
    return json({ ok:false, reason:'expired_offer' })
  }

  // Legacy-safe lookup: current_driver_offer_id is auth uid (= drivers.user_id), while some old rows have drivers.id != user_id.
  const { data: driver, error: driverErr } = await supabase
    .from('drivers')
    .select('id,user_id,fcm_token,name')
    .or(`id.eq.${driverId},user_id.eq.${driverId}`)
    .limit(1)
    .maybeSingle()
  if (driverErr) return json({ ok:false, reason:'db_error' })

  let fcmToken: string | null = driver?.fcm_token ?? null
  let fallbackTokenId: string | null = null
  if (!fcmToken) {
    const { data: pushRows } = await supabase
      .from('driver_push_tokens')
      .select('id,fcm_token')
      .eq('user_id', driverId)
      .eq('active', true)
      .order('last_used_at', { ascending:false })
      .limit(1)
    if (pushRows?.length) {
      fcmToken = pushRows[0].fcm_token
      fallbackTokenId = pushRows[0].id
    }
  }
  if (!fcmToken) return json({ ok:false, reason:'no_fcm_token' })

  let accessToken: string
  try { accessToken = await getFirebaseAccessToken(JSON.parse(firebaseServiceAcct)) }
  catch (_) { return json({ ok:false, reason:'firebase_auth_error' }) }

  const km = Number(order.distance_km ?? 0)
  const earnings = Number(order.driver_earnings ?? 0)
  const distanceKm = Number.isFinite(km) && km > 0 ? km.toFixed(1) : '0'
  const driverEarnings = Number.isFinite(earnings) && earnings > 0 ? earnings.toFixed(2) : '0.00'
  const headsUpBody = distanceKm !== '0'
    ? `${vendorName} • €${total.toFixed(2)} • ${distanceKm}km`
    : `${vendorName} • €${total.toFixed(2)}`

  const fcmUrl = `https://fcm.googleapis.com/v1/projects/${firebaseProjectId}/messages:send`
  const message = {
    message: {
      token: fcmToken,
      notification: { title:'🛵 Novo pedido!', body:headsUpBody },
      data: {
        orderId:String(orderId), type:'new_order_offer', vendorName,
        total:total.toFixed(2), distanceKm, driverEarnings,
        offerExpiresAt:String(order.driver_offer_expires_at ?? ''),
        title:'🔔 Novo pedido!', body:headsUpBody,
      },
      android: {
        priority:'high',
        // Must expire well before the DB offer. DB timeout is 60s after this fix.
        ttl:'25s',
        notification: {
          channel_id:'bora_orders_urgent_v3', notification_priority:'PRIORITY_MAX',
          default_sound:true, default_vibrate_timings:true, visibility:'PUBLIC',
        },
      },
      apns: {
        headers: { 'apns-priority':'10', 'apns-push-type':'background', 'apns-expiration': String(Math.floor(Date.now()/1000)+25) },
        payload: { aps: { 'content-available':1, sound:'bora_alert.wav', 'interruption-level':'time-sensitive' } },
      },
    },
  }

  const fcmRes = await fetch(fcmUrl, {
    method:'POST',
    headers:{ Authorization:`Bearer ${accessToken}`, 'Content-Type':'application/json' },
    body:JSON.stringify(message),
  })
  const fcmBody = await fcmRes.json().catch(() => ({}))
  if (!fcmRes.ok) {
    const errorCode = fcmBody?.error?.details?.[0]?.errorCode ?? ''
    if (errorCode === 'UNREGISTERED' || errorCode === 'INVALID_ARGUMENT') {
      if (fallbackTokenId) await supabase.from('driver_push_tokens').update({ active:false }).eq('id', fallbackTokenId)
      else if (driver?.id) await supabase.from('drivers').update({ fcm_token:null }).eq('id', driver.id)
    }
    return json({ ok:false, reason:'fcm_error', detail:fcmBody })
  }

  console.log(`[notify-driver v39] sent order=${orderId} driver=${driverId} expires=${order.driver_offer_expires_at}`)
  return json({ ok:true })
})

function json(obj:any, status=200): Response {
  return new Response(JSON.stringify(obj), { status, headers:{ ...corsHeaders, 'Content-Type':'application/json' } })
}

async function getFirebaseAccessToken(serviceAccount:any): Promise<string> {
  const now = Math.floor(Date.now()/1000)
  const header = { alg:'RS256', typ:'JWT' }
  const payload = {
    iss:serviceAccount.client_email,
    scope:'https://www.googleapis.com/auth/firebase.messaging',
    aud:'https://oauth2.googleapis.com/token', exp:now+3600, iat:now,
  }
  const encodedHeader = b64url(JSON.stringify(header))
  const encodedPayload = b64url(JSON.stringify(payload))
  const signingInput = `${encodedHeader}.${encodedPayload}`
  const pemBody = serviceAccount.private_key
    .replace(/-----BEGIN PRIVATE KEY-----/g,'')
    .replace(/-----END PRIVATE KEY-----/g,'')
    .replace(/\s/g,'')
  const keyBytes = Uint8Array.from(atob(pemBody), c => c.charCodeAt(0))
  const cryptoKey = await crypto.subtle.importKey('pkcs8', keyBytes, { name:'RSASSA-PKCS1-v1_5', hash:'SHA-256' }, false, ['sign'])
  const sigBuffer = await crypto.subtle.sign('RSASSA-PKCS1-v1_5', cryptoKey, new TextEncoder().encode(signingInput))
  const jwt = `${signingInput}.${b64urlBytes(new Uint8Array(sigBuffer))}`
  const tokenRes = await fetch('https://oauth2.googleapis.com/token', {
    method:'POST', headers:{ 'Content-Type':'application/x-www-form-urlencoded' },
    body:new URLSearchParams({ grant_type:'urn:ietf:params:oauth:grant-type:jwt-bearer', assertion:jwt }),
  })
  const tokenData = await tokenRes.json()
  if (!tokenData.access_token) throw new Error('Google token exchange failed')
  return tokenData.access_token
}
function b64url(str:string): string { return btoa(unescape(encodeURIComponent(str))).replace(/\+/g,'-').replace(/\//g,'_').replace(/=/g,'') }
function b64urlBytes(bytes:Uint8Array): string { return btoa(String.fromCharCode(...bytes)).replace(/\+/g,'-').replace(/\//g,'_').replace(/=/g,'') }

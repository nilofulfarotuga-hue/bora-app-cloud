// @ts-nocheck
// supabase/functions/notify-tvde-driver/index.ts
//
// TVDE — Bora Motorista. Envia push FCM a um motorista de passageiros.
// v5: alem da OFERTA de corrida (caminho original, intacto), trata
// kind='stop_added' — aviso de parada adicionada pelo cliente, com o total
// a cobrar atualizado (decisao Danilo 2026-07-20).
//
// Required Supabase secrets: FIREBASE_PROJECT_ID, FIREBASE_SERVICE_ACCOUNT
// Auto-injected: SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY
//
// Chamado por:
//  - trigger fn_notify_tvde_driver_on_offer (oferta; sem kind)
//  - RPC tvde_add_stop (kind='stop_added', stopPaidOnline bool)
//
// Retorna 200 sempre (fire-and-forget).

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

  console.log('[notify-tvde-driver] INVOKED (Firebase configured:', !!firebaseProjectId, ')')

  if (!firebaseProjectId || !firebaseServiceAcct) {
    console.warn('[notify-tvde-driver] Firebase env vars not set — skipping push')
    return json({ ok: false, reason: 'firebase_not_configured' }, 200)
  }

  let driverId: string
  let rideId: string
  let kind: string
  let stopPaidOnline = false
  try {
    const body = await req.json()
    driverId = body.driverId
    rideId   = body.rideId
    kind     = String(body.kind ?? 'offer')
    stopPaidOnline = body.stopPaidOnline === true
  } catch (_e) {
    return json({ ok: false, error: 'Invalid JSON body' }, 400)
  }
  if (!driverId || !rideId) {
    return json({ ok: false, error: 'driverId and rideId are required' }, 400)
  }

  const supabase = createClient(supabaseUrl, serviceKey)

  // FCM token (drivers.fcm_token -> driver_push_tokens fallback).
  const { data: driver } = await supabase
    .from('drivers').select('fcm_token, name').eq('user_id', driverId).maybeSingle()

  let fcmToken: string | null = driver?.fcm_token ?? null
  let fallbackTokenId: string | null = null
  if (!fcmToken) {
    const { data: pushRows } = await supabase
      .from('driver_push_tokens').select('id, fcm_token')
      .eq('user_id', driverId).eq('active', true)
      .order('last_used_at', { ascending: false }).limit(1)
    if (pushRows && pushRows.length > 0) {
      fcmToken = pushRows[0].fcm_token as string
      fallbackTokenId = pushRows[0].id as string
    }
  }
  if (!fcmToken) {
    console.log(`[notify-tvde-driver] No FCM token for driver ${driverId} — skipping`)
    await logPushEvent(supabase, rideId, false, { reason: 'no_fcm_token', driver_id: driverId, kind })
    return json({ ok: false, reason: 'no_fcm_token' }, 200)
  }

  // Firebase OAuth2 access token.
  let accessToken: string
  try {
    accessToken = await getFirebaseAccessToken(JSON.parse(firebaseServiceAcct))
  } catch (e) {
    console.error('[notify-tvde-driver] Firebase auth error:', e)
    await logPushEvent(supabase, rideId, false, { reason: 'firebase_auth_error', kind })
    return json({ ok: false, reason: 'firebase_auth_error' }, 200)
  }

  const fcmUrl = `https://fcm.googleapis.com/v1/projects/${firebaseProjectId}/messages:send`

  // ============ kind = stop_added: aviso de parada (v5) ============
  if (kind === 'stop_added') {
    // Detalhes para montar o total a cobrar.
    let stopFeeCents = 200
    try {
      const { data: s } = await supabase.from('platform_settings')
        .select('value').eq('key', 'tvde_stop_fee_cents').maybeSingle()
      const v = Number(String(s?.value ?? '200').replace(/\"/g, ''))
      if (Number.isFinite(v) && v > 0) stopFeeCents = v
    } catch (_e) { /* default 200 */ }

    let title = '📍 Parada adicionada'
    let body = `Nova parada (+€${eur(stopFeeCents)}).`
    try {
      const { data: ride } = await supabase
        .from('tvde_rides')
        .select('payment_method, est_fare_cents, extra_stops_fee_cents, roundtrip_credit_id, is_return_leg')
        .eq('id', rideId).maybeSingle()
      if (ride) {
        const stopsFee = Number(ride.extra_stops_fee_cents ?? 0)
        if (stopPaidOnline) {
          body = `Nova parada ja paga na app (+€${eur(stopFeeCents)}). Nao cobres a parada.`
        } else if (ride.roundtrip_credit_id) {
          // Perna do pacote €8 — ver se o vale e dinheiro ou online
          const { data: credit } = await supabase
            .from('tvde_roundtrip_credits').select('payment_intent_id')
            .eq('id', ride.roundtrip_credit_id).maybeSingle()
          const creditCash = credit && credit.payment_intent_id == null
          if (creditCash && !ride.is_return_leg) {
            let rtPrice = 800
            try {
              const { data: p } = await supabase.from('platform_settings')
                .select('value').eq('key', 'tvde_roundtrip_price_cents').maybeSingle()
              const v = Number(String(p?.value ?? '800').replace(/\"/g, ''))
              if (Number.isFinite(v) && v > 0) rtPrice = v
            } catch (_e) { /* default */ }
            body = `Nova parada (+€${eur(stopFeeCents)}). Total a cobrar em dinheiro: €${eur(rtPrice + stopsFee)}.`
          } else {
            body = `Nova parada (+€${eur(stopFeeCents)} em dinheiro). Paradas a cobrar: €${eur(stopsFee)}.`
          }
        } else if ((ride.payment_method ?? 'cash') === 'cash') {
          const total = Number(ride.est_fare_cents ?? 0) + stopsFee
          body = `Nova parada (+€${eur(stopFeeCents)}). Total a cobrar em dinheiro: €${eur(total)}.`
        } else {
          body = `Nova parada (+€${eur(stopFeeCents)} em dinheiro). Paradas a cobrar: €${eur(stopsFee)}.`
        }
      }
    } catch (_e) { /* mantem fallback */ }

    const message = {
      message: {
        token: fcmToken,
        notification: { title, body },
        data: { rideId: String(rideId), type: 'tvde_stop_added', title, body },
        android: { priority: 'high' },
        apns: {
          headers: { 'apns-priority': '10' },
          payload: { aps: { sound: 'default', 'interruption-level': 'time-sensitive' } },
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
      console.error(`[notify-tvde-driver] stop_added FCM error ${fcmRes.status}:`, JSON.stringify(fcmBody))
      await logPushEvent(supabase, rideId, false, { kind, fcm_status: fcmRes.status })
      return json({ ok: false, reason: 'fcm_error' }, 200)
    }
    console.log(`[notify-tvde-driver] stop_added push sent to driver ${driverId} ride ${rideId}`)
    await logPushEvent(supabase, rideId, true, { kind, driver_id: driverId })
    return json({ ok: true }, 200)
  }

  // ============ caminho original: OFERTA de corrida (intacto) ============
  // Detalhes da corrida para o cartao de oferta.
  let originLabel = 'Recolha', destLabel = 'Destino', fareEur = '0.00', distanceKm = '0'
  try {
    const { data: ride } = await supabase
      .from('tvde_rides')
      .select('origin_label, dest_label, est_fare_cents, est_distance_km')
      .eq('id', rideId).maybeSingle()
    if (ride) {
      originLabel = ride.origin_label ?? originLabel
      destLabel   = ride.dest_label ?? destLabel
      const cents = Number(ride.est_fare_cents ?? 0)
      if (Number.isFinite(cents) && cents > 0) fareEur = (cents / 100).toFixed(2)
      const km = Number(ride.est_distance_km ?? 0)
      if (Number.isFinite(km) && km > 0) distanceKm = km.toFixed(1)
    }
  } catch (_e) { /* mantem fallbacks */ }

  const headsUpBody = `${originLabel} -> ${destLabel} • €${fareEur}` +
    (distanceKm !== '0' ? ` • ${distanceKm}km` : '')

  // A1 FIX (turno noite 2026-07-04): DATA-ONLY, identico a notify-driver.
  const message = {
    message: {
      token: fcmToken,
      data: {
        rideId:     String(rideId),
        type:       'new_tvde_ride_offer',
        originLabel, destLabel,
        fare:       fareEur,
        distanceKm,
        title:      '🚗 Nova corrida!',
        body:       headsUpBody,
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
    console.error(`[notify-tvde-driver] FCM error ${fcmRes.status}:`, JSON.stringify(fcmBody))
    const errorCode = fcmBody?.error?.details?.[0]?.errorCode ?? ''
    if (errorCode === 'UNREGISTERED' || errorCode === 'INVALID_ARGUMENT') {
      if (fallbackTokenId) {
        await supabase.from('driver_push_tokens').update({ active: false }).eq('id', fallbackTokenId)
      } else {
        await supabase.from('drivers').update({ fcm_token: null }).eq('user_id', driverId)
      }
    }
    await logPushEvent(supabase, rideId, false, { fcm_status: fcmRes.status, error_code: errorCode })
    return json({ ok: false, reason: 'fcm_error', detail: fcmBody }, 200)
  }

  console.log(`[notify-tvde-driver] Push sent to driver ${driverId} ride ${rideId}`)
  await logPushEvent(supabase, rideId, true, { driver_id: driverId })

  // Reancora o TTL da oferta agora que o FCM aceitou (so se ainda for deste motorista).
  try {
    const { data: ttlRow } = await supabase
      .from('platform_settings').select('value').eq('key', 'tvde_offer_ttl_seconds').maybeSingle()
    const ttl = Number(ttlRow?.value ?? 25)
    if (Number.isFinite(ttl) && ttl > 0) {
      await supabase.from('tvde_rides')
        .update({ offer_expires_at: new Date(Date.now() + ttl * 1000).toISOString() })
        .eq('id', rideId)
        .eq('current_offer_driver_id', driverId)
        .eq('status', 'solicitada')
    }
  } catch (e) {
    console.warn('[notify-tvde-driver] offer_expires_at re-anchor failed:', e)
  }

  return json({ ok: true }, 200)
})

function eur(cents: number): string {
  return (Number(cents || 0) / 100).toFixed(2).replace('.', ',')
}

async function logPushEvent(supabase: any, rideId: string, ok: boolean, meta: Record<string, unknown>) {
  try {
    await supabase.from('tvde_ride_events').insert({
      ride_id: rideId,
      status: ok ? 'push_enviado' : 'push_falhou',
      actor: 'system',
      meta,
    })
  } catch (e) {
    console.warn('[notify-tvde-driver] logPushEvent failed:', e)
  }
}

function json(obj: unknown, status: number): Response {
  return new Response(JSON.stringify(obj), {
    status, headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  })
}

async function getFirebaseAccessToken(serviceAccount: any): Promise<string> {
  const now = Math.floor(Date.now() / 1000)
  const header  = { alg: 'RS256', typ: 'JWT' }
  const payload = {
    iss: serviceAccount.client_email,
    scope: 'https://www.googleapis.com/auth/firebase.messaging',
    aud: 'https://oauth2.googleapis.com/token',
    exp: now + 3600, iat: now,
  }
  const signingInput = `${b64url(JSON.stringify(header))}.${b64url(JSON.stringify(payload))}`
  const pemBody = serviceAccount.private_key
    .replace(/-----BEGIN PRIVATE KEY-----/g, '')
    .replace(/-----END PRIVATE KEY-----/g, '')
    .replace(/\s/g, '')
  const keyBytes  = Uint8Array.from(atob(pemBody), (c) => c.charCodeAt(0))
  const cryptoKey = await crypto.subtle.importKey('pkcs8', keyBytes,
    { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' }, false, ['sign'])
  const sigBuffer = await crypto.subtle.sign('RSASSA-PKCS1-v1_5', cryptoKey, new TextEncoder().encode(signingInput))
  const jwt = `${signingInput}.${b64urlBytes(new Uint8Array(sigBuffer))}`
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

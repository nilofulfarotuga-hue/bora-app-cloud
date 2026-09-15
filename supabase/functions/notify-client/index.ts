// @ts-nocheck
// supabase/functions/notify-client/index.ts
//
// Sends a FCM push to the CLIENT for order lifecycle updates.
// Status-specific messages mirror Uber Eats tone.
//
// PROMPT C (2026-05-14) — takeaway awareness:
//   • Quando orderId vem no payload, faz SELECT da row em orders para
//     obter service_type + vendor_name + takeaway_* fields (D5: DB query
//     no momento do push, não payload params).
//   • Mensagem é ramificada por service_type: delivery mantém tom Uber Eats;
//     takeaway tem mensagens próprias (preparing menciona prep_minutes,
//     readyForPickup inclui pickup_code, delivered = "Levantado").
//   • Status readyForPickup é takeaway-only.
//
// Required Supabase secrets:
//   FIREBASE_PROJECT_ID
//   FIREBASE_SERVICE_ACCOUNT
//
// Called by Flutter NotificationService.notifyClientOrderStatus()
// and can also be called from DB triggers / dispatch engine.

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
}

type OrderContext = {
  service_type: string | null
  vendor_name: string | null
  takeaway_pickup_code: string | null
  takeaway_prep_minutes: number | null
  takeaway_is_curbside: boolean | null
  takeaway_curbside_info: string | null
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
    console.warn('[notify-client] Firebase env vars not set — skipping push')
    return json({ ok: false, reason: 'firebase_not_configured' })
  }

  let payload: any
  try {
    payload = await req.json()
  } catch {
    return json({ ok: false, error: 'Invalid JSON body' }, 400)
  }

  const clientId = payload.clientId as string | undefined
  const orderId  = payload.orderId  as string | undefined
  const status   = payload.status   as string | undefined
  let title      = payload.title    as string | undefined
  let body       = payload.body     as string | undefined

  if (!clientId) {
    return json({ ok: false, error: 'clientId is required' }, 400)
  }

  const supabase = createClient(supabaseUrl, serviceKey)

  // ─── DB query: fetch order context for takeaway-aware messaging (D5) ───
  let orderCtx: OrderContext | null = null
  if (orderId) {
    const { data: orderRow, error: orderErr } = await supabase
      .from('orders')
      .select(
        'service_type, vendor_name, takeaway_pickup_code, ' +
        'takeaway_prep_minutes, takeaway_is_curbside, takeaway_curbside_info'
      )
      .eq('id', orderId)
      .maybeSingle()

    if (orderErr) {
      console.error('[notify-client] order fetch error:', JSON.stringify(orderErr))
      // Não fatal — caímos no fallback de mensagens delivery genéricas.
    } else if (orderRow) {
      orderCtx = orderRow as OrderContext
    }
  }

  if (status && (!title || !body)) {
    const msg = statusMessage(
      status,
      orderCtx,
      payload.vendorName as string | undefined,
      payload.driverName as string | undefined,
      payload.etaMinutes as number | undefined,
    )
    if (msg) {
      title = title ?? msg.title
      body  = body  ?? msg.body
    }
  }

  if (!title || !body) {
    return json({ ok: false, error: 'title/body or recognised status required' }, 400)
  }

  const { data: user, error: userErr } = await supabase
    .from('users')
    .select('fcm_token, name')
    .eq('id', clientId)
    .maybeSingle()

  if (userErr) {
    console.error('[notify-client] DB error:', JSON.stringify(userErr))
    return json({ ok: false, reason: 'db_error' })
  }

  if (!user?.fcm_token) {
    console.log(`[notify-client] No FCM token for client ${clientId} — skipping`)
    return json({ ok: false, reason: 'no_fcm_token' })
  }

  let accessToken: string
  try {
    const serviceAccount = JSON.parse(firebaseServiceAcct)
    accessToken = await getFirebaseAccessToken(serviceAccount)
  } catch (e) {
    console.error('[notify-client] Failed to get Firebase access token:', e)
    return json({ ok: false, reason: 'firebase_auth_error' })
  }

  const fcmUrl = `https://fcm.googleapis.com/v1/projects/${firebaseProjectId}/messages:send`

  const message = {
    message: {
      token: user.fcm_token,
      notification: { title, body },
      data: {
        ...(orderId ? { orderId: String(orderId) } : {}),
        ...(status  ? { status:  String(status) }  : {}),
        type: 'order_status',
      },
      android: {
        priority: 'high',
        notification: { channel_id: 'bora_orders', sound: 'default' },
      },
      apns: {
        headers: { 'apns-priority': '10' },
        payload: { aps: { sound: 'default', badge: 1, 'content-available': 1 } },
      },
    },
  }

  const fcmRes  = await fetch(fcmUrl, {
    method:  'POST',
    headers: {
      'Authorization': `Bearer ${accessToken}`,
      'Content-Type':  'application/json',
    },
    body: JSON.stringify(message),
  })

  const fcmBody = await fcmRes.json().catch(() => ({}))

  if (!fcmRes.ok) {
    console.error(`[notify-client] FCM error ${fcmRes.status}:`, JSON.stringify(fcmBody))
    const errorCode = fcmBody?.error?.details?.[0]?.errorCode ?? ''
    if (errorCode === 'UNREGISTERED' || errorCode === 'INVALID_ARGUMENT') {
      console.log(`[notify-client] Clearing stale FCM token for client ${clientId}`)
      await supabase.from('users').update({ fcm_token: null }).eq('id', clientId)
    }
    return json({ ok: false, reason: 'fcm_error', detail: fcmBody })
  }

  console.log(`[notify-client] ✓ Push sent to client ${clientId} (status=${status})`)
  return json({ ok: true })
})

function statusMessage(
  status: string,
  orderCtx: OrderContext | null,
  vendorNamePayload?: string,
  driverName?: string,
  etaMinutes?: number,
): { title: string; body: string } | null {
  // PROMPT C — usar dados da DB (D5). Payload fields são fallback para
  // calls antigas (ex.: NotificationService Flutter chama com vendorName).
  const isTakeaway = orderCtx?.service_type === 'takeaway'
  const vendor = (orderCtx?.vendor_name ?? vendorNamePayload ?? '').trim()
  const driver = (driverName ?? '').trim()
  const pickupCode = (orderCtx?.takeaway_pickup_code ?? '').trim()
  const prepMin = orderCtx?.takeaway_prep_minutes ?? 0
  const isCurbside = orderCtx?.takeaway_is_curbside === true

  switch (status) {
    case 'preparing':
      if (isTakeaway) {
        return {
          title: '📦 Pedido aceite',
          body: prepMin > 0
            ? (vendor
                ? `${vendor} a preparar — pronto em ${prepMin} min`
                : `Pedido aceite — pronto em ${prepMin} min`)
            : (vendor
                ? `${vendor} está a preparar o seu pedido`
                : 'O parceiro está a preparar o seu pedido'),
        }
      }
      return {
        title: 'Pedido aceite',
        body: vendor
          ? `👨‍🍳 ${vendor} está a preparar o seu pedido`
          : '👨‍🍳 O restaurante está a preparar o seu pedido',
      }

    case 'readyForPickup':
      // Takeaway-only. Sem orderCtx (push antigo / inconsistência),
      // mensagem genérica.
      return {
        title: '🎉 Pedido pronto!',
        body: pickupCode
          ? (isCurbside
              ? `Código ${pickupCode}. Aguarde no carro.`
              : `Código ${pickupCode}. Apresente no balcão.`)
          : (isCurbside
              ? 'O seu pedido está pronto — aguarde no carro.'
              : 'O seu pedido está pronto — apresente-se no balcão.'),
      }

    case 'callingDriver':
      // Delivery only — takeaway nunca passa por callingDriver
      return {
        title: 'À procura de estafeta',
        body: '🛵 A procurar o melhor estafeta para o seu pedido…',
      }

    case 'driverAccepted':
      return {
        title: 'Estafeta a caminho do restaurante',
        body: driver
          ? `✅ ${driver} aceitou o seu pedido`
          : '✅ Um estafeta aceitou o seu pedido',
      }

    case 'pickedUp':
      return {
        title: 'Pedido recolhido',
        body: '📦 O seu pedido foi recolhido e está a caminho',
      }

    case 'onTheWay':
      return {
        title: 'A caminho!',
        body: etaMinutes && etaMinutes > 0
          ? `🛵 A caminho! Chega em ~${etaMinutes} min`
          : '🛵 O seu pedido está a caminho',
      }

    case 'delivered':
      if (isTakeaway) {
        return {
          title: 'Obrigado pela visita! ✨',
          body: vendor
            ? `Obrigado pela visita a ${vendor}. Avalie o pedido na app.`
            : 'Obrigado pelo seu pedido. Avalie a sua experiência na app.',
        }
      }
      return {
        title: 'Entregue 🎉',
        body: 'Como foi a sua experiência? Avalie o pedido e ajude outros clientes.',
      }

    default:
      return null
  }
}

function json(obj: any, status = 200): Response {
  return new Response(JSON.stringify(obj), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  })
}

async function getFirebaseAccessToken(serviceAccount: any): Promise<string> {
  const now = Math.floor(Date.now() / 1000)
  const header  = { alg: 'RS256', typ: 'JWT' }
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
    { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' },
    false, ['sign'],
  )
  const sigBuffer = await crypto.subtle.sign(
    'RSASSA-PKCS1-v1_5', cryptoKey, new TextEncoder().encode(signingInput),
  )
  const signature = b64urlBytes(new Uint8Array(sigBuffer))
  const jwt       = `${signingInput}.${signature}`
  const tokenRes  = await fetch('https://oauth2.googleapis.com/token', {
    method:  'POST',
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

function b64url(str: string): string {
  return btoa(unescape(encodeURIComponent(str)))
    .replace(/\+/g, '-').replace(/\//g, '_').replace(/=/g, '')
}
function b64urlBytes(bytes: Uint8Array): string {
  return btoa(String.fromCharCode(...bytes))
    .replace(/\+/g, '-').replace(/\//g, '_').replace(/=/g, '')
}

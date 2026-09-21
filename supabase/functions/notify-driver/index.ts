// @ts-nocheck
// supabase/functions/notify-driver/index.ts
// v41 2026-09-21 — APNs: 'apns-push-type' passa de 'background' para 'alert'.
//     'background' e' push SILENCIOSO para a Apple (sem banner, sem som, e exige
//     prioridade 5) — mesmo com token, o iPhone nunca tocava com a oferta.
//     Publicado pela Claude.ai por MCP a partir do commit 277c65e8 do repo
//     publico (a chave Supabase do PC estava expirada). Nada mais mudou face
//     ao v40: android, webpush, data, guardas e limpeza de tokens ficam iguais.
// v40 2026-09-17 (missão estafeta-web-2026-09-16 · BLOCO 3.4) — a OFERTA vai a
//     TODOS os aparelhos do estafeta (app Android/iPhone + navegador/PWA), não só
//     ao token mais recente. Com um token WEB novo, o v39 deixava de tocar na app.
//     Tokens web levam bloco `webpush` (notificação com ligação que abre a oferta,
//     TTL curto como o Android). Tokens mortos são limpos um a um sem afectar os
//     outros. Tudo o resto (guarda de oferta stale/expirada, identidade legada
//     id≠user_id, papel `delivery`) é o v39 tal e qual.
// v39 2026-09-12 — stale-offer guard + legacy driver identity fix.
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
}

const WEB_URL = 'https://bora-app-web.pages.dev'

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders })

  const firebaseProjectId = Deno.env.get('FIREBASE_PROJECT_ID')
  const firebaseServiceAcct = Deno.env.get('FIREBASE_SERVICE_ACCOUNT')
  const supabaseUrl = Deno.env.get('SUPABASE_URL')!
  const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!

  console.log('[notify-driver v41] INVOKED firebase=', !!firebaseProjectId)
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
    console.log(`[notify-driver v41] stale offer skipped order=${orderId} driver=${driverId}`)
    return json({ ok:false, reason:'stale_offer' })
  }
  const expiresAtMs = order.driver_offer_expires_at ? Date.parse(order.driver_offer_expires_at) : 0
  if (!expiresAtMs || expiresAtMs <= Date.now()) {
    console.log(`[notify-driver v41] expired offer skipped order=${orderId} driver=${driverId}`)
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

  // v40 — TODOS os aparelhos: drivers.fcm_token (legado, 1 aparelho) + todos os
  // driver_push_tokens activos (multi-aparelho, inclui web). Dedup por token.
  type Tok = { token:string; source:string; rowId?:string; platform?:string }
  const toks = new Map<string, Tok>()
  if (driver?.fcm_token) toks.set(driver.fcm_token, { token: driver.fcm_token, source: 'drivers.fcm_token' })
  const uid = driver?.user_id ?? driverId
  const { data: pushRows } = await supabase
    .from('driver_push_tokens')
    .select('id,fcm_token,platform')
    .eq('user_id', uid)
    .eq('active', true)
    .order('last_used_at', { ascending:false })
  for (const r of pushRows ?? []) {
    if (r.fcm_token && !toks.has(r.fcm_token)) {
      toks.set(r.fcm_token, { token: r.fcm_token, source: 'driver_push_tokens', rowId: r.id, platform: r.platform ?? undefined })
    }
  }
  if (toks.size === 0) return json({ ok:false, reason:'no_fcm_token' })

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
  const data = {
    orderId:String(orderId), type:'new_order_offer', vendorName,
    total:total.toFixed(2), distanceKm, driverEarnings,
    offerExpiresAt:String(order.driver_offer_expires_at ?? ''),
    title:'🔔 Novo pedido!', body:headsUpBody,
    url:`${WEB_URL}/#/driver?offer=${orderId}`,
  }

  const results = await Promise.allSettled([...toks.values()].map(async (t) => {
    const isWeb = (t.platform ?? '').toLowerCase().startsWith('web')
    const message = {
      message: {
        token: t.token,
        notification: { title:'🛵 Novo pedido!', body:headsUpBody },
        data,
        android: {
          priority:'high',
          // Must expire well before the DB offer. DB timeout is 60s after this fix.
          ttl:'25s',
          notification: {
            channel_id:'bora_orders_urgent_v3', notification_priority:'PRIORITY_MAX',
            default_sound:true, default_vibrate_timings:true, visibility:'PUBLIC',
          },
        },
        // [iPhone 2026-09-21] 'alert' + som + texto: 'background' e' push SILENCIOSO
        // para a Apple (sem banner, sem som; prioridade obrigatoria 5) — com token,
        // o iPhone nunca tocava. content-available fica para acordar a app tambem.
        apns: {
          headers: { 'apns-priority':'10', 'apns-push-type':'alert', 'apns-expiration': String(Math.floor(Date.now()/1000)+25) },
          payload: { aps: { 'content-available':1, sound:'bora_alert.wav', 'interruption-level':'time-sensitive' } },
        },
        // v40 — navegador/PWA: o SDK web desenha a notificação com estes campos e
        // o toque abre a oferta (o ecrã do estafeta faz polling e mostra o cartão).
        webpush: {
          headers: { TTL:'25', Urgency:'high' },
          notification: {
            icon:'icons/Icon-192.png', badge:'icons/Icon-192.png',
            requireInteraction:true, renotify:true, tag:`oferta:${orderId}`,
            vibrate:[300,100,300,100,300],
          },
          fcm_options: { link: data.url },
        },
      },
    }
    const res = await fetch(fcmUrl, {
      method:'POST',
      headers:{ Authorization:`Bearer ${accessToken}`, 'Content-Type':'application/json' },
      body:JSON.stringify(message),
    })
    const body = await res.json().catch(() => ({}))
    if (!res.ok) {
      const errorCode = body?.error?.details?.[0]?.errorCode ?? body?.error?.status ?? ''
      console.error(`[notify-driver v41] FCM ${res.status} ${t.source}${isWeb ? ' (web)' : ''}: ${JSON.stringify(body).slice(0,300)}`)
      let cleaned = false
      if (errorCode === 'UNREGISTERED' || errorCode === 'INVALID_ARGUMENT') {
        if (t.source === 'driver_push_tokens' && t.rowId) {
          await supabase.from('driver_push_tokens').update({ active:false, last_fail_at: new Date().toISOString() }).eq('id', t.rowId)
          cleaned = true
        } else if (t.source === 'drivers.fcm_token' && driver?.id) {
          await supabase.from('drivers').update({ fcm_token:null }).eq('id', driver.id)
          cleaned = true
        }
      }
      return { ok:false, source:t.source, platform:t.platform ?? null, errorCode, cleaned }
    }
    return { ok:true, source:t.source, platform:t.platform ?? null }
  }))

  const flat = results.map((r) => r.status === 'fulfilled' ? r.value : { ok:false, error:String(r.reason) })
  const sent = flat.filter((r) => r.ok).length
  console.log(`[notify-driver v41] order=${orderId} driver=${driverId} tokens=${flat.length} sent=${sent} expires=${order.driver_offer_expires_at}`)
  if (sent === 0) return json({ ok:false, reason:'fcm_error', detail:flat })
  return json({ ok:true, tokens:flat.length, sent, detail:flat })
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

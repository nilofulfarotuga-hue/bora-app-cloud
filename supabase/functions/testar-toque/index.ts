// @ts-nocheck
// supabase/functions/testar-toque/index.ts
// v1 2026-10-10 (missão "a chamada grita sempre") — botão "Testar o toque".
//
// Manda aos aparelhos de QUEM CHAMA um aviso exactamente como o de uma oferta:
// Android só `data` (a app monta a chamada no canal v4 do alarme, em ciclo,
// ecrã inteiro), iPhone com `apns.payload.aps.alert` + som + time-sensitive,
// navegador com `webpush.notification`. Dura 30 s. Não há pedido, nem botões,
// nem nada a aceitar: serve para a pessoa ver que o telemóvel grita em Vibrar
// e com o ecrã apagado, num passo só.
//
// Quem pode: qualquer sessão — mas só toca nos aparelhos da própria conta.
// Com a chave de serviço (prova técnica) pode indicar `userId` ou um `token`.
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
}

const TIPO = 'teste_toque_oferta'
const DURACAO_S = 30

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders })

  const firebaseProjectId = Deno.env.get('FIREBASE_PROJECT_ID')
  const firebaseServiceAcct = Deno.env.get('FIREBASE_SERVICE_ACCOUNT')
  const supabaseUrl = Deno.env.get('SUPABASE_URL')!
  const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
  const supabase = createClient(supabaseUrl, serviceKey)

  const quem = await identificar(req, supabaseUrl, serviceKey, supabase)
  if (!quem.ok) {
    console.warn(`[testar-toque v1] 403 motivo=${quem.reason}`)
    return json({ ok: false, error: 'forbidden' }, 403)
  }
  if (!firebaseProjectId || !firebaseServiceAcct) return json({ ok: false, reason: 'firebase_not_configured' })

  let body: any = {}
  try { body = await req.json() } catch (_) { body = {} }

  // Alvos: os aparelhos da conta (ou, só com a chave de serviço, um token/uma conta).
  type Tok = { token: string, origem: string, platform?: string }
  const toks = new Map<string, Tok>()
  let uid: string | null = quem.uid ?? null
  if (quem.servico) {
    if (typeof body?.token === 'string' && body.token.length > 20) {
      toks.set(body.token, { token: body.token, origem: 'pedido', platform: body?.platform ?? undefined })
    }
    if (typeof body?.userId === 'string' && body.userId) uid = body.userId
  }
  if (uid) {
    const juntar = (rows: any[] | null, origem: string) => {
      for (const r of rows ?? []) {
        if (r?.fcm_token && !toks.has(r.fcm_token)) toks.set(r.fcm_token, { token: r.fcm_token, origem, platform: r.platform ?? undefined })
      }
    }
    const [d1, d2, d3, d4] = await Promise.all([
      supabase.from('driver_push_tokens').select('fcm_token,platform').eq('user_id', uid).eq('active', true),
      supabase.from('provider_push_tokens').select('fcm_token,platform').eq('user_id', uid).eq('active', true),
      supabase.from('partner_push_tokens').select('fcm_token').eq('partner_id', uid).eq('active', true),
      supabase.from('drivers').select('fcm_token').eq('user_id', uid),
    ])
    juntar(d1.data, 'driver_push_tokens')
    juntar(d2.data, 'provider_push_tokens')
    juntar(d3.data, 'partner_push_tokens')
    juntar(d4.data, 'drivers.fcm_token')
  }
  if (toks.size === 0) return json({ ok: true, aparelhos: 0, enviados: 0, reason: 'sem_aparelhos' })

  let accessToken: string
  try { accessToken = await getFirebaseAccessToken(JSON.parse(firebaseServiceAcct)) }
  catch (_) { return json({ ok: false, reason: 'firebase_auth_error' }) }

  const fim = new Date(Date.now() + DURACAO_S * 1000)
  const titulo = '🔔 Teste do toque'
  const texto = 'É assim que uma oferta vai tocar. Pára sozinho daqui a 30 segundos.'
  const fcmUrl = `https://fcm.googleapis.com/v1/projects/${firebaseProjectId}/messages:send`

  const resultados = await Promise.all([...toks.values()].map(async (t) => {
    const message = {
      message: {
        token: t.token,
        data: { type: TIPO, title: titulo, body: texto, offerExpiresAt: fim.toISOString() },
        android: { priority: 'high', ttl: `${DURACAO_S}s` },
        apns: {
          headers: {
            'apns-priority': '10', 'apns-push-type': 'alert',
            'apns-expiration': String(Math.floor(fim.getTime() / 1000)),
            'apns-collapse-id': 'teste-toque',
          },
          payload: { aps: { alert: { title: titulo, body: texto }, 'content-available': 1, sound: 'bora_alert.wav', 'interruption-level': 'time-sensitive' } },
        },
        webpush: {
          headers: { TTL: String(DURACAO_S), Urgency: 'high' },
          notification: { title: titulo, body: texto, icon: 'icons/Icon-192.png', requireInteraction: true, tag: 'teste-toque' },
        },
      },
    }
    try {
      const res = await fetch(fcmUrl, {
        method: 'POST',
        headers: { Authorization: `Bearer ${accessToken}`, 'Content-Type': 'application/json' },
        body: JSON.stringify(message),
      })
      const b = await res.json().catch(() => ({}))
      const erro = res.ok ? '' : (b?.error?.details?.[0]?.errorCode ?? b?.error?.status ?? String(res.status))
      return { ok: res.ok, origem: t.origem, platform: t.platform ?? null, erro }
    } catch (e) {
      return { ok: false, origem: t.origem, platform: t.platform ?? null, erro: String(e) }
    }
  }))

  const enviados = resultados.filter((r) => r.ok).length
  console.log(`[testar-toque v1] uid=${uid ?? '-'} servico=${quem.servico} aparelhos=${resultados.length} enviados=${enviados} ` +
    resultados.map((r) => `${r.platform ?? r.origem}:${r.ok ? 'ok' : r.erro}`).join(','))
  return json({ ok: true, aparelhos: resultados.length, enviados, detalhe: resultados })
})

// ── Quem chama ────────────────────────────────────────────────────────────
const servicoOk = new Set<string>()
function lerPayload(token: string): any {
  try {
    let b = token.split('.')[1].replace(/-/g, '+').replace(/_/g, '/')
    while (b.length % 4) b += '='
    return JSON.parse(atob(b))
  } catch (_) { return null }
}
async function identificar(req: Request, supabaseUrl: string, serviceKey: string, supabase: any):
  Promise<{ ok: boolean, reason?: string, uid?: string, servico?: boolean }> {
  const h = req.headers.get('authorization') ?? ''
  if (!h.toLowerCase().startsWith('bearer ')) return { ok: false, reason: 'sem_token' }
  const token = h.slice(7).trim()
  if (!token) return { ok: false, reason: 'sem_token' }
  if (token === serviceKey || servicoOk.has(token)) return { ok: true, servico: true }
  const p = lerPayload(token)
  if (p?.role === 'service_role') {
    try {
      const r = await fetch(`${supabaseUrl}/auth/v1/admin/users?per_page=1`, { headers: { apikey: token, Authorization: `Bearer ${token}` } })
      if (r.ok) { servicoOk.add(token); return { ok: true, servico: true } }
    } catch (_) {}
    return { ok: false, reason: 'service_invalido' }
  }
  if (p?.role !== 'authenticated') return { ok: false, reason: `papel_${p?.role ?? 'desconhecido'}` }
  const { data: u, error } = await supabase.auth.getUser(token)
  if (error || !u?.user) return { ok: false, reason: 'jwt_invalido' }
  return { ok: true, uid: String(u.user.id), servico: false }
}

function json(obj: any, status = 200): Response {
  return new Response(JSON.stringify(obj), { status, headers: { ...corsHeaders, 'Content-Type': 'application/json' } })
}

async function getFirebaseAccessToken(serviceAccount: any): Promise<string> {
  const now = Math.floor(Date.now() / 1000)
  const header = { alg: 'RS256', typ: 'JWT' }
  const payload = {
    iss: serviceAccount.client_email,
    scope: 'https://www.googleapis.com/auth/firebase.messaging',
    aud: 'https://oauth2.googleapis.com/token', exp: now + 3600, iat: now,
  }
  const signingInput = `${b64url(JSON.stringify(header))}.${b64url(JSON.stringify(payload))}`
  const pemBody = serviceAccount.private_key
    .replace(/-----BEGIN PRIVATE KEY-----/g, '')
    .replace(/-----END PRIVATE KEY-----/g, '')
    .replace(/\s/g, '')
  const keyBytes = Uint8Array.from(atob(pemBody), (c) => c.charCodeAt(0))
  const cryptoKey = await crypto.subtle.importKey('pkcs8', keyBytes, { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' }, false, ['sign'])
  const sig = await crypto.subtle.sign('RSASSA-PKCS1-v1_5', cryptoKey, new TextEncoder().encode(signingInput))
  const jwt = `${signingInput}.${b64urlBytes(new Uint8Array(sig))}`
  const tokenRes = await fetch('https://oauth2.googleapis.com/token', {
    method: 'POST', headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({ grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer', assertion: jwt }),
  })
  const tokenData = await tokenRes.json()
  if (!tokenData.access_token) throw new Error('Google token exchange failed')
  return tokenData.access_token
}
function b64url(str: string): string { return btoa(unescape(encodeURIComponent(str))).replace(/\+/g, '-').replace(/\//g, '_').replace(/=/g, '') }
function b64urlBytes(bytes: Uint8Array): string { return btoa(String.fromCharCode(...bytes)).replace(/\+/g, '-').replace(/\//g, '_').replace(/=/g, '') }

// @ts-nocheck
// push-clientes-alvo v1 (2026-09-08)
// Push FCM para uma LISTA fechada de clientes (user_ids), em vez de um segmento inteiro.
// Le os tokens de client_push_tokens (active=true) com recurso a users.fcm_token,
// porque a maioria dos clientes NAO tem users.fcm_token preenchido — mesma familia
// do bug ja corrigido no notify-driver (drivers.fcm_token vs driver_push_tokens).
// Data-only NAO: aqui queremos que o Android desenhe a notificacao mesmo com a app
// fechada, e nao ha handler proprio para este tipo.
// Body: { user_ids: string[], title: string, body: string, type?: string }

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const cors = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors })

  const url = Deno.env.get('SUPABASE_URL')!
  const key = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
  const fbProject = Deno.env.get('FIREBASE_PROJECT_ID')
  const fbSa = Deno.env.get('FIREBASE_SERVICE_ACCOUNT')
  if (!fbProject || !fbSa) return json({ ok: false, error: 'firebase_not_configured' }, 500)

  const auth = req.headers.get('Authorization') ?? ''
  try {
    const p = JSON.parse(atob(auth.substring(7).split('.')[1]))
    if (p.role !== 'service_role') throw new Error('role')
  } catch (_e) {
    return json({ ok: false, error: 'forbidden' }, 403)
  }

  const b = await req.json().catch(() => ({}))
  const userIds: string[] = Array.isArray(b?.user_ids) ? b.user_ids : []
  const title = String(b?.title ?? '')
  const body = String(b?.body ?? '')
  const type = String(b?.type ?? 'admin_message')
  if (!userIds.length || !title || !body) return json({ ok: false, error: 'user_ids, title e body sao obrigatorios' }, 400)

  const sb = createClient(url, key, { auth: { autoRefreshToken: false, persistSession: false } })

  const { data: rows } = await sb.from('client_push_tokens')
    .select('user_id, fcm_token').in('user_id', userIds).eq('active', true)
  const { data: legacy } = await sb.from('users')
    .select('id, fcm_token').in('id', userIds).not('fcm_token', 'is', null)

  const porToken = new Map<string, string>()
  for (const r of rows ?? []) if (r.fcm_token) porToken.set(r.fcm_token, r.user_id)
  for (const r of legacy ?? []) if (r.fcm_token) porToken.set(r.fcm_token, r.id)

  if (porToken.size === 0) return json({ ok: true, alvos: userIds.length, tokens: 0, enviados: 0, falhados: 0 })

  let accessToken: string
  try { accessToken = await getFirebaseToken(JSON.parse(fbSa)) }
  catch (e) { return json({ ok: false, error: 'firebase auth: ' + e }, 500) }

  const fcmUrl = `https://fcm.googleapis.com/v1/projects/${fbProject}/messages:send`
  const tokens = [...porToken.keys()]
  let enviados = 0, falhados = 0
  const erros: string[] = []
  const pessoasOk = new Set<string>()

  for (let i = 0; i < tokens.length; i += 20) {
    const lote = tokens.slice(i, i + 20)
    const res = await Promise.allSettled(lote.map(async (t) => {
      const msg = {
        message: {
          token: t,
          notification: { title, body },
          data: { type, origem: 'push-clientes-alvo' },
          android: { priority: 'high', notification: { channel_id: 'bora_general', sound: 'default' } },
          apns: { headers: { 'apns-priority': '10' }, payload: { aps: { sound: 'default', badge: 1 } } },
        },
      }
      const r = await fetch(fcmUrl, {
        method: 'POST',
        headers: { 'Authorization': 'Bearer ' + accessToken, 'Content-Type': 'application/json' },
        body: JSON.stringify(msg),
      })
      if (!r.ok) {
        const txt = await r.text().catch(() => '')
        throw new Error(r.status + ': ' + txt.slice(0, 160))
      }
      return t
    }))
    for (const r of res) {
      if (r.status === 'fulfilled') { enviados++; pessoasOk.add(porToken.get(r.value)!) }
      else { falhados++; if (erros.length < 5) erros.push(String(r.reason).slice(0, 200)) }
    }
  }

  return json({ ok: true, alvos: userIds.length, tokens: tokens.length, enviados, falhados, pessoas_tocadas: pessoasOk.size, erros })
})

function json(o: unknown, s = 200) {
  return new Response(JSON.stringify(o), { status: s, headers: { ...cors, 'Content-Type': 'application/json' } })
}

async function getFirebaseToken(sa: any): Promise<string> {
  const now = Math.floor(Date.now() / 1000)
  const b64u = (s: string) => btoa(unescape(encodeURIComponent(s))).replace(/\+/g, '-').replace(/\//g, '_').replace(/=/g, '')
  const b64uB = (b: Uint8Array) => btoa(String.fromCharCode(...b)).replace(/\+/g, '-').replace(/\//g, '_').replace(/=/g, '')
  const sigIn = `${b64u(JSON.stringify({ alg: 'RS256', typ: 'JWT' }))}.${b64u(JSON.stringify({ iss: sa.client_email, scope: 'https://www.googleapis.com/auth/firebase.messaging', aud: 'https://oauth2.googleapis.com/token', exp: now + 3600, iat: now }))}`
  const kb = Uint8Array.from(atob(sa.private_key.replace(/-----[^-]+-----/g, '').replace(/\s/g, '')), (c) => c.charCodeAt(0))
  const k = await crypto.subtle.importKey('pkcs8', kb, { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' }, false, ['sign'])
  const sig = b64uB(new Uint8Array(await crypto.subtle.sign('RSASSA-PKCS1-v1_5', k, new TextEncoder().encode(sigIn))))
  const r = await fetch('https://oauth2.googleapis.com/token', {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({ grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer', assertion: `${sigIn}.${sig}` }),
  })
  const d = await r.json()
  if (!d.access_token) throw new Error(JSON.stringify(d))
  return d.access_token
}

// @ts-nocheck
// supabase/functions/notify-admin-urgent/index.ts
//
// v15 (2026-07-31) — DATA-ONLY: removido o bloco `notification` do payload FCM.
// Com ele, o Android desenhava a notificação pelo tray e o handler Flutter não
// corria → notificação efémera (sumia sozinha) e nada visível em foreground.
// Agora title/body viajam em `data` e é o Dart que posta a notificação local
// persistente (ongoing:true) no canal `bora_admin_urgent`. Ver sendFcmV1().
//
// v13 (2026-07-31) — PONTE TELEGRAM: além do push FCM, envia o mesmo aviso
// para o Telegram do Danilo (sendMessage). Best-effort: envolvido em try/catch,
// nunca parte o push nem a transação de origem. Credenciais no vault do
// Supabase (telegram_bot_token / telegram_admin_chat_id), lidas pela RPC
// get_telegram_config() restrita a service_role.
//
// v12 (F2 2026-06-12) — modo GENERIC: aceita {kind:'generic', title, body,
// route, ref} para pushes admin não-crosstalk (ex.: fecho semanal pronto,
// via run_weekly_closeout()). Sem kind => comportamento crosstalk INTACTO.
// Email Resend continua exclusivo do caminho crosstalk.
//
// 5F-β — Sends FCM push (HTTP v1 OAuth2) + optional Resend email to all
// registered admin devices when a `robot_crosstalk` row is inserted with
// urgency='critical' and direction='a_to_b'.
//
// Auth: verify_jwt=true (5F-β-α-fix1). Platform valida signature do JWT;
// função decoda payload e confirma role='service_role'.
//
// Required Supabase secrets:
//   FIREBASE_PROJECT_ID         — for FCM v1 endpoint
//   FIREBASE_SERVICE_ACCOUNT    — JSON of Firebase Admin SDK service account
//   SUPABASE_URL                — auto-injected
//   SUPABASE_SERVICE_ROLE_KEY   — auto-injected
//   RESEND_API_KEY              — OPTIONAL; if missing, email is skipped

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
}

const ADMIN_EMAIL = 'boraappbora@gmail.com'
const EMAIL_FROM  = 'Bora App <noreply@boraapp.com>'

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  const supabaseUrl = Deno.env.get('SUPABASE_URL')!
  const serviceKey  = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!

  // ─── Auth: verify_jwt=true valida signature; aqui confirma role ───────────
  const authHeader = req.headers.get('Authorization') ?? ''
  if (!authHeader.startsWith('Bearer ')) {
    return new Response(
      JSON.stringify({ ok: false, error: 'forbidden' }),
      { status: 403, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
    )
  }
  try {
    const token = authHeader.substring(7)
    const payload = JSON.parse(atob(token.split('.')[1]))
    if (payload.role !== 'service_role') {
      console.warn('[notify-admin-urgent] forbidden — role mismatch:', payload.role)
      return new Response(
        JSON.stringify({ ok: false, error: 'forbidden' }),
        { status: 403, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
      )
    }
  } catch (_e) {
    return new Response(
      JSON.stringify({ ok: false, error: 'forbidden' }),
      { status: 403, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
    )
  }

  // ─── Parse body ───────────────────────────────────────────────────────────
  let kind = 'crosstalk'
  let crosstalkId = ''
  let question = ''
  let sessionId: string | null = null
  let pushTitle = '🔴 URGENTE — Bora App'
  let pushBody = ''
  let pushData: Record<string, string> = {}
  try {
    const body = await req.json()
    kind = String(body.kind ?? 'crosstalk')
    if (kind === 'generic') {
      pushTitle = String(body.title ?? '').trim()
      pushBody  = String(body.body ?? '').trim()
      const route = String(body.route ?? '/admin')
      const ref   = String(body.ref ?? 'generic')
      pushData = { type: 'admin_generic', ref, route }
      if (!pushTitle || !pushBody) {
        return new Response(
          JSON.stringify({ ok: false, error: 'title and body required for kind=generic' }),
          { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
        )
      }
    } else {
      crosstalkId = String(body.crosstalk_id ?? '')
      question    = String(body.question ?? '').trim()
      sessionId   = body.session_id ? String(body.session_id) : null
      pushBody = question.length > 200 ? question.slice(0, 200) + '…' : question
      pushData = { type: 'crosstalk_critical', crosstalk_id: crosstalkId, route: '/admin/crosstalk' }
      if (!crosstalkId || !question) {
        return new Response(
          JSON.stringify({ ok: false, error: 'crosstalk_id and question required' }),
          { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
        )
      }
    }
  } catch (_e) {
    return new Response(
      JSON.stringify({ ok: false, error: 'invalid_json' }),
      { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
    )
  }

  const supabase = createClient(supabaseUrl, serviceKey)

  // ─── Fetch active admin tokens ────────────────────────────────────────────
  const { data: tokens, error: tokensErr } = await supabase
    .from('admin_push_tokens')
    .select('id, fcm_token, device_label, platform')
    .order('last_used_at', { ascending: false })

  if (tokensErr) {
    console.error('[notify-admin-urgent] tokens query error:', JSON.stringify(tokensErr))
  }

  const tokenList = tokens ?? []
  console.log(`[notify-admin-urgent] v12 kind=${kind} ref=${crosstalkId || pushData.ref} tokens=${tokenList.length}`)

  // ─── FCM push (parallel) ──────────────────────────────────────────────────
  const firebaseProjectId   = Deno.env.get('FIREBASE_PROJECT_ID')
  const firebaseServiceAcct = Deno.env.get('FIREBASE_SERVICE_ACCOUNT')

  let pushAttempted = 0
  let pushSuccess   = 0
  let pushCleaned   = 0

  if (firebaseProjectId && firebaseServiceAcct && tokenList.length > 0) {
    let accessToken: string | null = null
    try {
      const sa = JSON.parse(firebaseServiceAcct)
      accessToken = await getFirebaseAccessToken(sa)
    } catch (e) {
      console.error('[notify-admin-urgent] firebase auth error:', e)
    }

    if (accessToken) {
      const fcmUrl = `https://fcm.googleapis.com/v1/projects/${firebaseProjectId}/messages:send`
      pushAttempted = tokenList.length

      const results = await Promise.allSettled(
        tokenList.map((t) =>
          sendFcmV1(fcmUrl, accessToken!, t.fcm_token, pushTitle, pushBody, pushData, kind === 'generic')
            .then((res) => ({ token: t, res }))
        ),
      )

      const staleTokens: string[] = []
      for (const r of results) {
        if (r.status !== 'fulfilled') continue
        const { token, res } = r.value
        if (res.ok) {
          pushSuccess++
        } else if (res.stale) {
          staleTokens.push(token.fcm_token)
        }
      }

      if (staleTokens.length > 0) {
        const { error: delErr } = await supabase
          .from('admin_push_tokens')
          .delete()
          .in('fcm_token', staleTokens)
        if (delErr) {
          console.error('[notify-admin-urgent] stale token cleanup error:', delErr)
        } else {
          pushCleaned = staleTokens.length
          console.log(`[notify-admin-urgent] cleaned ${pushCleaned} stale tokens`)
        }
      }
    }
  } else if (!firebaseProjectId || !firebaseServiceAcct) {
    console.warn('[notify-admin-urgent] Firebase env vars missing — push skipped')
  }

  // ─── Email Resend (optional — só crosstalk) ───────────────────────────────
  const resendKey = Deno.env.get('RESEND_API_KEY')
  let emailSent = false
  if (resendKey && kind === 'crosstalk') {
    try {
      const truncated = question.length > 500 ? question.slice(0, 500) + '…' : question
      const emailRes = await fetch('https://api.resend.com/emails', {
        method: 'POST',
        headers: {
          'Authorization': `Bearer ${resendKey}`,
          'Content-Type':  'application/json',
        },
        body: JSON.stringify({
          from:    EMAIL_FROM,
          to:      [ADMIN_EMAIL],
          subject: '🔴 URGENTE — Cliente reportou crítico (Bora App)',
          html: `
            <div style="font-family:system-ui,Arial,sans-serif;max-width:600px;">
              <h2 style="color:#D32F2F;">🔴 Comunicação CRÍTICA pendente</h2>
              <p>Um cliente reportou uma situação crítica via chatbot. Analisar imediatamente.</p>
              <div style="background:#FFEBEE;padding:12px;border-left:4px solid #D32F2F;margin:16px 0;">
                <strong>Pergunta:</strong><br/>
                ${escapeHtml(truncated)}
              </div>
              <p style="font-size:12px;color:#666;">
                crosstalk_id: <code>${escapeHtml(crosstalkId)}</code><br/>
                ${sessionId ? `session_id: <code>${escapeHtml(sessionId)}</code><br/>` : ''}
                Abre o admin app → Comunicação A↔B para responder.
              </p>
              <p style="font-size:11px;color:#999;margin-top:24px;">
                Bora App · 5F-β notify-admin-urgent · ${new Date().toISOString()}
              </p>
            </div>
          `,
        }),
      })
      if (emailRes.ok) {
        emailSent = true
        console.log('[notify-admin-urgent] email sent OK')
      } else {
        const body = await emailRes.text().catch(() => '')
        console.error(`[notify-admin-urgent] resend error ${emailRes.status}: ${body}`)
      }
    } catch (e) {
      console.error('[notify-admin-urgent] resend exception:', e)
    }
  } else if (!resendKey) {
    console.log('[notify-admin-urgent] RESEND_API_KEY missing — email skipped')
  }

  // ─── Telegram (v13, 2026-07-31) — best-effort ─────────────────────────────
  // Segunda via do aviso, para o Danilo saber na hora (ex.: pedido de limpeza
  // — ele arranja a limpadora à mão nesse momento).
  //
  // BEST-EFFORT a sério: tudo dentro de try/catch. Se o Telegram falhar, o
  // push já foi enviado e a transação de origem (trigger na BD) não pode
  // partir por causa disto.
  //
  // Credenciais: vault do Supabase (telegram_bot_token / telegram_admin_chat_id)
  // lidas pela RPC get_telegram_config(), restrita a service_role.
  const telegramSent = await sendTelegramBestEffort(supabase, pushTitle, pushBody)

  return new Response(
    JSON.stringify({
      ok:             true,
      kind,
      ref:            crosstalkId || pushData.ref,
      push_attempted: pushAttempted,
      push_success:   pushSuccess,
      push_cleaned:   pushCleaned,
      email_sent:     emailSent,
      telegram_sent:  telegramSent,
    }),
    { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
  )
})

// ═══════════════════════════════════════════════════════════════════════════
// Helpers
// ═══════════════════════════════════════════════════════════════════════════

/// Envia o mesmo aviso para o Telegram do Danilo. NUNCA lança: qualquer falha
/// (credenciais em falta, rede, API) é registada e devolve false.
async function sendTelegramBestEffort(
  supabase: any,
  title: string,
  body: string,
): Promise<boolean> {
  try {
    const { data, error } = await supabase.rpc('get_telegram_config')
    if (error) {
      console.error('[notify-admin-urgent] telegram config error:', error.message)
      return false
    }
    const row = Array.isArray(data) ? data[0] : data
    const botToken = row?.bot_token
    const chatId   = row?.chat_id
    if (!botToken || !chatId) {
      console.log('[notify-admin-urgent] telegram secrets missing — skipped')
      return false
    }

    const text = `${title}\n\n${body}`.slice(0, 4000)
    const res = await fetch(
      `https://api.telegram.org/bot${botToken}/sendMessage`,
      {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          chat_id: chatId,
          text,
          disable_web_page_preview: true,
        }),
      },
    )
    if (res.ok) {
      console.log('[notify-admin-urgent] telegram sent OK')
      return true
    }
    const errBody = await res.text().catch(() => '')
    console.error(`[notify-admin-urgent] telegram ${res.status}: ${errBody}`)
    return false
  } catch (e) {
    console.error('[notify-admin-urgent] telegram exception:', e)
    return false
  }
}

async function sendFcmV1(
  fcmUrl: string,
  accessToken: string,
  fcmToken: string,
  title: string,
  bodyText: string,
  data: Record<string, string>,
  sticky = false, // PARTE A (2026-07-17): admin generic → notificação persistente
): Promise<{ ok: boolean; stale: boolean; status: number; body: any }> {
  // v15 (2026-07-31) — DATA-ONLY. Com bloco `notification`, o Android desenhava
  // a notificação pelo tray do sistema e o handler Flutter
  // (_firebaseMessagingBackgroundHandler) NÃO corria — resultado: notificação
  // efémera que sumia sozinha, sem persistência, e nada visível com a app em
  // foreground. Mesma causa raiz já corrigida no notify-service-provider v3 e
  // alinhada com o padrão do notify-partner.
  //
  // Sem `notification`, o handler Dart corre SEMPRE (background, app fechada e
  // foreground) e posta uma notificação local com ongoing:true/autoCancel:false
  // no canal `bora_admin_urgent` (Importance.max) — fica no ecrã até o admin
  // agir. `title`/`body` viajam dentro de `data` porque data-only não tem
  // bloco de notificação de onde os ler.
  const message = {
    message: {
      token: fcmToken,
      data: {
        ...data,
        title: title,
        body:  bodyText,
        // Consumido pelo handler Dart; mantém a semântica do antigo `sticky`.
        persistent: sticky ? 'true' : 'false',
      },
      android: {
        priority: 'high',
        // Sem `notification` aqui: é o Dart que desenha, com persistência real.
      },
      apns: {
        headers: {
          'apns-priority':  '10',
          'apns-push-type': 'background',
        },
        payload: {
          aps: {
            // data-only no iOS: acorda a app; o alerta visível é desenhado
            // pelo lado Dart, igual ao Android.
            'content-available': 1,
          },
        },
      },
    },
  }

  const res = await fetch(fcmUrl, {
    method: 'POST',
    headers: {
      'Authorization': `Bearer ${accessToken}`,
      'Content-Type':  'application/json',
    },
    body: JSON.stringify(message),
  })

  const body = await res.json().catch(() => ({}))
  if (res.ok) return { ok: true, stale: false, status: res.status, body }

  const errorCode = body?.error?.details?.[0]?.errorCode ?? body?.error?.status ?? ''
  const stale = errorCode === 'UNREGISTERED' || errorCode === 'INVALID_ARGUMENT'
  console.error(`[notify-admin-urgent] FCM ${res.status} (${errorCode}) for token=${fcmToken.slice(0, 12)}…`)
  return { ok: false, stale, status: res.status, body }
}

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

  const pemBody = serviceAccount.private_key
    .replace(/-----BEGIN PRIVATE KEY-----/g, '')
    .replace(/-----END PRIVATE KEY-----/g, '')
    .replace(/\s/g, '')

  const keyBytes  = Uint8Array.from(atob(pemBody), (c) => c.charCodeAt(0))
  const cryptoKey = await crypto.subtle.importKey(
    'pkcs8',
    keyBytes,
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
  const jwt       = `${signingInput}.${signature}`

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

function b64url(str: string): string {
  return btoa(unescape(encodeURIComponent(str)))
    .replace(/\+/g, '-').replace(/\//g, '_').replace(/=/g, '')
}

function b64urlBytes(bytes: Uint8Array): string {
  return btoa(String.fromCharCode(...bytes))
    .replace(/\+/g, '-').replace(/\//g, '_').replace(/=/g, '')
}

function escapeHtml(s: string): string {
  return s
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#39;')
}

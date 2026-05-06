// @ts-nocheck
// supabase/functions/notify-admin-urgent/index.ts
//
// 5F-β — Sends FCM push (HTTP v1 OAuth2) + optional Resend email to all
// registered admin devices when a `robot_crosstalk` row is inserted with
// urgency='critical' and direction='a_to_b'.
//
// Auth: verify_jwt=false. Internal auth via Authorization: Bearer
// <SUPABASE_SERVICE_ROLE_KEY> match (called by trigger _notify_admin_urgent_trigger).
//
// Required Supabase secrets:
//   FIREBASE_PROJECT_ID         — for FCM v1 endpoint
//   FIREBASE_SERVICE_ACCOUNT    — JSON of Firebase Admin SDK service account
//   SUPABASE_URL                — auto-injected
//   SUPABASE_SERVICE_ROLE_KEY   — auto-injected
//   RESEND_API_KEY              — OPTIONAL; if missing, email is skipped
//
// Body (from trigger):
//   { crosstalk_id: uuid, question: string, session_id?: uuid, context?: jsonb }
//
// Returns 200 with summary always (FCM/email failures are logged, not thrown).

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

  // ─── Auth: only service_role calls allowed ────────────────────────────────
  const authHeader = req.headers.get('Authorization') ?? ''
  const expected   = `Bearer ${serviceKey}`
  if (authHeader !== expected) {
    console.warn('[notify-admin-urgent] forbidden — auth mismatch')
    return new Response(
      JSON.stringify({ ok: false, error: 'forbidden' }),
      { status: 403, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
    )
  }

  // ─── Parse body ───────────────────────────────────────────────────────────
  let crosstalkId: string
  let question: string
  let sessionId: string | null = null
  let context: unknown = null
  try {
    const body = await req.json()
    crosstalkId = String(body.crosstalk_id ?? '')
    question    = String(body.question ?? '').trim()
    sessionId   = body.session_id ? String(body.session_id) : null
    context     = body.context ?? null
  } catch (_e) {
    return new Response(
      JSON.stringify({ ok: false, error: 'invalid_json' }),
      { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
    )
  }

  if (!crosstalkId || !question) {
    return new Response(
      JSON.stringify({ ok: false, error: 'crosstalk_id and question required' }),
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
  console.log(`[notify-admin-urgent] crosstalk=${crosstalkId} tokens=${tokenList.length}`)

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
          sendFcmV1(fcmUrl, accessToken!, t.fcm_token, crosstalkId, question)
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

  // ─── Email Resend (optional) ──────────────────────────────────────────────
  const resendKey = Deno.env.get('RESEND_API_KEY')
  let emailSent = false
  if (resendKey) {
    try {
      const truncated = question.length > 500 ? question.slice(0, 500) + '…' : question
      const dashboardLink = `${supabaseUrl.replace('.supabase.co', '.supabase.co').replace(/\/$/, '')}` // best-effort; admin uses app
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
  } else {
    console.log('[notify-admin-urgent] RESEND_API_KEY missing — email skipped')
  }

  return new Response(
    JSON.stringify({
      ok:             true,
      crosstalk_id:   crosstalkId,
      push_attempted: pushAttempted,
      push_success:   pushSuccess,
      push_cleaned:   pushCleaned,
      email_sent:     emailSent,
    }),
    { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
  )
})

// ═══════════════════════════════════════════════════════════════════════════
// Helpers
// ═══════════════════════════════════════════════════════════════════════════

async function sendFcmV1(
  fcmUrl: string,
  accessToken: string,
  fcmToken: string,
  crosstalkId: string,
  question: string,
): Promise<{ ok: boolean; stale: boolean; status: number; body: any }> {
  const truncated = question.length > 200 ? question.slice(0, 200) + '…' : question

  const message = {
    message: {
      token: fcmToken,
      notification: {
        title: '🔴 URGENTE — Bora App',
        body:  truncated,
      },
      data: {
        type:         'crosstalk_critical',
        crosstalk_id: crosstalkId,
        route:        '/admin/crosstalk',
      },
      android: {
        priority: 'high',
        notification: {
          channel_id: 'bora_admin_urgent',
          sound:      'default',
        },
      },
      apns: {
        headers: { 'apns-priority': '10' },
        payload: {
          aps: {
            sound:               'default',
            badge:               1,
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

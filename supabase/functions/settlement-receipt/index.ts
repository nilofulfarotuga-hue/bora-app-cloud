// @ts-nocheck
// supabase/functions/settlement-receipt/index.ts
// F3 — comprovativo automatico do fecho semanal + cobranca de quem deve.
//
// Porque existe: ate 2026-09-07 o Danilo marcava "pago" no painel e a outra
// pessoa nao sabia de nada — tinha de lhe mandar o comprovativo a mao pelo
// Gmail. Aqui isso passa a ser automatico.
//
// Dois modos, um so sitio:
//   (sem mode) → despacha a fila `settlement_receipts` (comprovativos).
//   mode=reminders → lembra quem ficou a dever a Bora e avisa o Danilo.
//
// Esta funcao NAO calcula dinheiro: le valores ja fechados e comunica-os.
//
// Chave do Resend: env primeiro, vault depois (mesmo padrao da v5 do
// weekly-closeout-digest — o projeto nunca teve a chave no env).
//
// Push: DATA-ONLY, sempre. Com bloco `notification` o Android desenha a notif
// pelo tray e o handler Flutter nao corre (cicatriz de 31/07 e 04/09).

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
}

const EMAIL_FROM = 'Bora App <fecho@boraguarda.com>'
const META = '<meta charset="utf-8">'
const GREEN = '#16A34A'
const MAX_TENTATIVAS = 6

function eur(cents) {
  return '€' + (Math.abs(cents ?? 0) / 100).toFixed(2).replace('.', ',')
}
function escapeHtml(s) {
  return String(s ?? '').replace(/&/g, '&amp;').replace(/</g, '&lt;')
    .replace(/>/g, '&gt;').replace(/"/g, '&quot;').replace(/'/g, '&#39;')
}
function ddmm(iso) {
  const d = new Date(iso)
  const p = (n) => String(n).padStart(2, '0')
  return p(d.getUTCDate()) + '/' + p(d.getUTCMonth() + 1)
}
function dataHoraPt(iso) {
  const d = new Date(iso)
  const p = (n) => String(n).padStart(2, '0')
  return p(d.getUTCDate()) + '/' + p(d.getUTCMonth() + 1) + '/' + d.getUTCFullYear() +
    ' as ' + p(d.getUTCHours()) + ':' + p(d.getUTCMinutes())
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders })

  const supabaseUrl = Deno.env.get('SUPABASE_URL')
  const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')

  const authHeader = req.headers.get('Authorization') ?? ''
  try {
    if (!authHeader.startsWith('Bearer ')) throw new Error('no bearer')
    const payload = JSON.parse(atob(authHeader.substring(7).split('.')[1]))
    if (payload.role !== 'service_role') throw new Error('role')
  } catch (_e) {
    return new Response(JSON.stringify({ ok: false, error: 'forbidden' }),
      { status: 403, headers: { ...corsHeaders, 'Content-Type': 'application/json' } })
  }

  let modo = 'receipts'
  try {
    const b = await req.json()
    if (b?.mode === 'reminders') modo = 'reminders'
  } catch (_e) {}

  const supabase = createClient(supabaseUrl, serviceKey)

  // Chave do Resend: env primeiro, vault depois.
  let resendKey = Deno.env.get('RESEND_API_KEY') ?? null
  let resendKeyOrigem = resendKey ? 'env' : null
  if (!resendKey) {
    try {
      const { data: vaultKey } = await supabase.rpc('get_resend_key')
      if (vaultKey && String(vaultKey).trim().length > 0) {
        resendKey = String(vaultKey).trim()
        resendKeyOrigem = 'vault'
      }
    } catch (e) {
      console.error('[settlement-receipt] falhou ler a chave do vault:', e)
    }
  }

  const { data: mbwayRow } = await supabase.from('platform_settings')
    .select('value').eq('key', 'bora_mbway_phone').maybeSingle()
  const boraMbway = (typeof mbwayRow?.value === 'string' ? mbwayRow.value : '') || ''

  const fcm = await prepararFcm(supabase)

  if (modo === 'reminders') {
    return await correrLembretes(supabase, supabaseUrl, authHeader, resendKey, resendKeyOrigem, boraMbway, fcm)
  }
  return await despacharFila(supabase, resendKey, resendKeyOrigem, boraMbway, fcm, supabaseUrl, authHeader)
})

// ---------------------------------------------------------------- comprovativos

async function despacharFila(supabase, resendKey, resendKeyOrigem, boraMbway, fcm, supabaseUrl, authHeader) {
  const { data: fila } = await supabase.from('settlement_receipts')
    .select('*').in('status', ['pending', 'failed']).lt('attempts', MAX_TENTATIVAS)
    .order('created_at', { ascending: true }).limit(50)

  let enviados = 0, semEmail = 0, falhados = 0, esgotados = 0
  const problemas = []

  for (const r of fila ?? []) {
    const html = comprovativoHtml(r, boraMbway)
    const tentativas = (r.attempts ?? 0) + 1
    const assunto = r.kind === 'paid'
      ? 'Comprovativo de pagamento · Bora'
      : 'Recebemos o seu pagamento de ' + eur(r.amount_cents) + ' · Bora'

    let status = 'failed'
    let erro = null

    const to = r.to_email && String(r.to_email).includes('@') ? String(r.to_email) : null
    if (!to) {
      status = 'skipped'
      erro = 'sem email valido'
      semEmail++
      problemas.push({ nome: r.subject_name, tipo: r.subject_type, motivo: erro, cents: r.amount_cents })
    } else {
      const res = await sendResend(resendKey, to, assunto, html)
      if (res.ok) { status = 'sent'; enviados++ } else {
        erro = res.error
        falhados++
        if (tentativas >= MAX_TENTATIVAS) {
          esgotados++
          problemas.push({ nome: r.subject_name, tipo: r.subject_type, motivo: 'desistiu apos ' + tentativas + ' tentativas: ' + erro, cents: r.amount_cents })
        }
      }
    }

    await supabase.from('settlement_receipts').update({
      status, attempts: tentativas, last_error: erro, html,
      sent_at: status === 'sent' ? new Date().toISOString() : null,
    }).eq('id', r.id)

    // Reforco no telemovel — data-only. Nunca trava o envio do email.
    if (status === 'sent' || status === 'skipped') {
      try {
        const titulo = r.kind === 'paid' ? 'Pagamento efetuado' : 'Pagamento recebido'
        const corpo = r.kind === 'paid'
          ? 'A Bora transferiu-lhe ' + eur(r.amount_cents) + ' referente a semana de ' + ddmm(r.week_start_at) + '.'
          : 'Recebemos o seu acerto de ' + eur(r.amount_cents) + '. Conta certa, obrigado.'
        await empurrarParaPessoa(supabase, fcm, r.subject_type, r.subject_id, {
          type: 'settlement_receipt', title: titulo, body: corpo,
          kind: String(r.kind), week_start: String(r.week_start_at).slice(0, 10),
        })
      } catch (e) { console.error('[settlement-receipt] push falhou:', e) }
    }
  }

  // Se alguem ficou mesmo sem comprovativo, o Danilo tem de saber.
  if (problemas.length > 0) {
    await avisarDanilo(supabaseUrl, authHeader, 'Comprovativos por entregar',
      problemas.map((p) => '• ' + p.nome + ' ' + eur(p.cents) + ' — ' + p.motivo).join('\n'))
  }

  return new Response(JSON.stringify({
    ok: true, modo: 'receipts', na_fila: (fila ?? []).length,
    enviados, sem_email: semEmail, falhados, esgotados, problemas,
    resend_key_present: !!resendKey, resend_key_origem: resendKeyOrigem,
  }), { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' } })
}

function comprovativoHtml(r, boraMbway) {
  const pago = r.kind === 'paid'
  const valor = eur(r.amount_cents)
  const quando = dataHoraPt(r.sent_at ?? new Date().toISOString())
  const referencia = 'fecho ' + ddmm(r.week_start_at)

  const caixa = pago
    ? '<div style="background:#F0FDF4;border:1px solid #BBF7D0;border-radius:10px;padding:14px;margin-top:16px">' +
      '<div style="font-weight:700;color:#166534;font-size:18px">Recebeu ' + valor + '</div>' +
      '<div style="margin-top:6px;color:#14532D">Enviado por <b>MB Way</b>' +
      (r.subject_phone ? ' para <b>' + escapeHtml(r.subject_phone) + '</b>' : '') + '.</div></div>'
    : '<div style="background:#F0FDF4;border:1px solid #BBF7D0;border-radius:10px;padding:14px;margin-top:16px">' +
      '<div style="font-weight:700;color:#166534;font-size:18px">Recebemos ' + valor + '</div>' +
      '<div style="margin-top:6px;color:#14532D">A sua conta desta semana fica <b>certa</b>. Obrigado.</div></div>'

  const titulo = pago ? 'Comprovativo de pagamento' : 'Pagamento recebido'
  const intro = pago
    ? 'confirmamos o pagamento do seu acerto da semana.'
    : 'confirmamos que recebemos o seu acerto da semana.'

  return META + '<div style="font-family:system-ui,Arial,sans-serif;max-width:560px;margin:auto">' +
    '<div style="background:' + GREEN + ';color:#fff;padding:18px 20px;border-radius:12px 12px 0 0">' +
    '<div style="font-size:20px;font-weight:800">Bora</div>' +
    '<div style="opacity:.9">' + titulo + '</div></div>' +
    '<div style="border:1px solid #eee;border-top:0;border-radius:0 0 12px 12px;padding:20px">' +
    '<p style="margin:0 0 12px">Olá <b>' + escapeHtml(r.subject_name || '') + '</b>, ' + intro + '</p>' +
    caixa +
    '<table style="width:100%;border-collapse:collapse;font-size:14px;margin-top:16px">' +
    '<tr><td style="padding:6px 0;color:#666">Valor</td><td style="padding:6px 0;text-align:right;font-weight:700">' + valor + '</td></tr>' +
    '<tr><td style="padding:6px 0;color:#666">Data</td><td style="padding:6px 0;text-align:right">' + quando + '</td></tr>' +
    '<tr><td style="padding:6px 0;color:#666">Referência</td><td style="padding:6px 0;text-align:right">' + escapeHtml(referencia) + '</td></tr>' +
    (pago ? '' : (boraMbway
      ? '<tr><td style="padding:6px 0;color:#666">Pago para</td><td style="padding:6px 0;text-align:right">MB Way ' + escapeHtml(boraMbway) + '</td></tr>'
      : '')) +
    '</table>' +
    '<p style="font-size:12px;color:#777;margin-top:18px">Guarde este email como comprovativo. Se algum valor não bater certo, responda a esta mensagem.</p>' +
    '<p style="font-size:11px;color:#999;margin-top:14px">Bora App · fecho semanal automático</p></div></div>'
}

// ---------------------------------------------------------------- cobranca

async function correrLembretes(supabase, supabaseUrl, authHeader, resendKey, resendKeyOrigem, boraMbway, fcm) {
  const { data: devedores, error } = await supabase.rpc('settlement_debtors', { p_max_weeks: null })
  if (error) {
    return new Response(JSON.stringify({ ok: false, error: 'debtors_failed', detail: error.message }),
      { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } })
  }

  let enviados = 0, semEmail = 0
  const linhasDanilo = []

  for (const d of devedores ?? []) {
    const valor = eur(d.cents)
    const periodo = ddmm(d.week_start_at)
    linhasDanilo.push('• ' + d.subject_name + ' ' + valor + ' — ' + d.dias + ' dias' +
      (d.subject_phone ? ' (tel: ' + d.subject_phone + ')' : ''))

    const to = d.subject_email && String(d.subject_email).includes('@') ? String(d.subject_email) : null
    if (!to) { semEmail++ } else {
      const res = await sendResend(resendKey, to,
        'Ainda falta o acerto de ' + valor + ' · Bora', lembreteHtml(d, boraMbway))
      if (res.ok) enviados++
    }

    try {
      await empurrarParaPessoa(supabase, fcm, d.subject_type, d.subject_id, {
        type: 'settlement_reminder',
        title: 'Acerto por regularizar',
        body: 'Faltam ' + valor + ' da semana de ' + periodo +
              (boraMbway ? '. MB Way ' + boraMbway : '') + '.',
        week_start: String(d.week_start_at).slice(0, 10),
      })
    } catch (e) { console.error('[settlement-receipt] push do lembrete falhou:', e) }
  }

  let avisoDanilo = false
  if ((devedores ?? []).length > 0) {
    avisoDanilo = await avisarDanilo(supabaseUrl, authHeader,
      'Acertos por receber (' + devedores.length + ')', linhasDanilo.join('\n'))
  }

  return new Response(JSON.stringify({
    ok: true, modo: 'reminders', devedores: (devedores ?? []).length,
    emails_enviados: enviados, sem_email: semEmail, aviso_danilo: avisoDanilo,
    resend_key_present: !!resendKey, resend_key_origem: resendKeyOrigem,
  }), { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' } })
}

function lembreteHtml(d, boraMbway) {
  const valor = eur(d.cents)
  return META + '<div style="font-family:system-ui,Arial,sans-serif;max-width:560px;margin:auto">' +
    '<div style="background:' + GREEN + ';color:#fff;padding:18px 20px;border-radius:12px 12px 0 0">' +
    '<div style="font-size:20px;font-weight:800">Bora</div>' +
    '<div style="opacity:.9">Acerto por regularizar</div></div>' +
    '<div style="border:1px solid #eee;border-top:0;border-radius:0 0 12px 12px;padding:20px">' +
    '<p style="margin:0 0 12px">Olá <b>' + escapeHtml(d.subject_name || '') + '</b>, o acerto da semana de ' +
    ddmm(d.week_start_at) + ' continua por regularizar.</p>' +
    '<div style="background:#FFF7ED;border:1px solid #FED7AA;border-radius:10px;padding:14px">' +
    '<div style="font-weight:700;color:#9A3412;font-size:18px">Falta pagar ' + valor + '</div>' +
    (boraMbway
      ? '<div style="margin-top:8px;color:#7C2D12">Pague por <b>MB Way</b> para <b>' + escapeHtml(boraMbway) + '</b>.</div>'
      : '<div style="margin-top:8px;color:#7C2D12">Entraremos em contacto para combinar o acerto.</div>') +
    '<div style="margin-top:6px;color:#7C2D12;font-size:13px">Referência: fecho ' + ddmm(d.week_start_at) + '</div>' +
    '</div>' +
    '<p style="font-size:12px;color:#777;margin-top:16px">Assim que pagar, recebe o comprovativo por email. Se já pagou, ignore esta mensagem.</p>' +
    '<p style="font-size:11px;color:#999;margin-top:14px">Bora App · fecho semanal automático</p></div></div>'
}

// ---------------------------------------------------------------- envio

async function sendResend(key, to, subject, html) {
  if (!key) {
    console.log('[settlement-receipt] RESEND_API_KEY em falta')
    return { ok: false, error: 'RESEND_API_KEY em falta (nem no env nem no vault)' }
  }
  try {
    const res = await fetch('https://api.resend.com/emails', {
      method: 'POST',
      headers: { 'Authorization': 'Bearer ' + key, 'Content-Type': 'application/json' },
      body: JSON.stringify({ from: EMAIL_FROM, to: [to], subject, html }),
    })
    if (res.ok) return { ok: true, error: null }
    const detalhe = await res.text().catch(() => '')
    console.error('[settlement-receipt] resend ' + res.status + ': ' + detalhe)
    return { ok: false, error: 'resend ' + res.status + ': ' + detalhe.slice(0, 300) }
  } catch (e) {
    console.error('[settlement-receipt] resend excecao:', e)
    return { ok: false, error: 'excecao: ' + String(e).slice(0, 300) }
  }
}

async function avisarDanilo(supabaseUrl, authHeader, titulo, corpo) {
  try {
    const res = await fetch(supabaseUrl + '/functions/v1/notify-admin-urgent', {
      method: 'POST',
      headers: { 'Authorization': authHeader, 'Content-Type': 'application/json' },
      body: JSON.stringify({
        kind: 'generic', title: titulo, body: String(corpo).slice(0, 900),
        route: '/admin/acertos-semana', ref: 'settlement_cobranca',
      }),
    })
    return res.ok
  } catch (e) {
    console.error('[settlement-receipt] aviso ao Danilo falhou:', e)
    return false
  }
}

// ---------------------------------------------------------------- push

async function prepararFcm(supabase) {
  const projectId = Deno.env.get('FIREBASE_PROJECT_ID')
  const raw = Deno.env.get('FIREBASE_SERVICE_ACCOUNT')
  if (!projectId || !raw) return null
  try {
    return { projectId, accessToken: await getFirebaseAccessToken(JSON.parse(raw)) }
  } catch (e) {
    console.error('[settlement-receipt] Firebase auth error:', e)
    return null
  }
}

// Manda para TODOS os aparelhos da pessoa, seja qual for o papel: quem acumula
// papeis e uma pessoa so, e o comprovativo e dela (PADRAO_BORA 1.25).
async function empurrarParaPessoa(supabase, fcm, tipo, subjectId, dados) {
  if (!fcm) return 0
  const { data: uid } = await supabase.rpc('settlement_subject_user_id',
    { p_type: tipo, p_subject_id: String(subjectId) })
  if (!uid) return 0

  const tokens = new Set()
  const { data: linhas } = await supabase.from('provider_push_tokens')
    .select('fcm_token').eq('user_id', uid).eq('active', true)
  for (const l of linhas ?? []) if (l?.fcm_token) tokens.add(l.fcm_token)
  const { data: user } = await supabase.from('users')
    .select('fcm_token').eq('id', uid).maybeSingle()
  if (user?.fcm_token) tokens.add(user.fcm_token)
  if (tokens.size === 0) return 0

  const url = 'https://fcm.googleapis.com/v1/projects/' + fcm.projectId + '/messages:send'
  let enviados = 0
  for (const token of tokens) {
    // DATA-ONLY de proposito: com bloco `notification` o handler Flutter nao
    // corre e a notificacao desaparece sozinha.
    const message = {
      message: {
        token,
        data: dados,
        android: { priority: 'high' },
        apns: { headers: { 'apns-priority': '10' }, payload: { aps: { 'content-available': 1 } } },
      },
    }
    try {
      const res = await fetch(url, {
        method: 'POST',
        headers: { 'Authorization': 'Bearer ' + fcm.accessToken, 'Content-Type': 'application/json' },
        body: JSON.stringify(message),
      })
      if (res.ok) enviados++
      else console.error('[settlement-receipt] FCM ' + res.status + ': ' + (await res.text().catch(() => '')))
    } catch (e) {
      console.error('[settlement-receipt] FCM excecao:', e)
    }
  }
  return enviados
}

async function getFirebaseAccessToken(serviceAccount) {
  const now = Math.floor(Date.now() / 1000)
  const header = { alg: 'RS256', typ: 'JWT' }
  const payloadJwt = {
    iss: serviceAccount.client_email,
    scope: 'https://www.googleapis.com/auth/firebase.messaging',
    aud: 'https://oauth2.googleapis.com/token',
    exp: now + 3600,
    iat: now,
  }
  const signingInput = b64url(JSON.stringify(header)) + '.' + b64url(JSON.stringify(payloadJwt))
  const pemBody = serviceAccount.private_key
    .replace(/-----BEGIN PRIVATE KEY-----/g, '')
    .replace(/-----END PRIVATE KEY-----/g, '')
    .replace(/\s/g, '')
  const keyBytes = Uint8Array.from(atob(pemBody), (c) => c.charCodeAt(0))
  const cryptoKey = await crypto.subtle.importKey(
    'pkcs8', keyBytes, { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' }, false, ['sign'],
  )
  const sigBuffer = await crypto.subtle.sign(
    'RSASSA-PKCS1-v1_5', cryptoKey, new TextEncoder().encode(signingInput),
  )
  const jwt = signingInput + '.' + b64urlBytes(new Uint8Array(sigBuffer))
  const tokenRes = await fetch('https://oauth2.googleapis.com/token', {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({
      grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer',
      assertion: jwt,
    }),
  })
  const tokenData = await tokenRes.json()
  if (!tokenData.access_token) throw new Error('Google token exchange failed')
  return tokenData.access_token
}

function b64url(str) {
  return btoa(unescape(encodeURIComponent(str))).replace(/\+/g, '-').replace(/\//g, '_').replace(/=/g, '')
}
function b64urlBytes(bytes) {
  return btoa(String.fromCharCode(...bytes)).replace(/\+/g, '-').replace(/\//g, '_').replace(/=/g, '')
}

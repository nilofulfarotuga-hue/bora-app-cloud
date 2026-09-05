// @ts-nocheck
// supabase/functions/weekly-closeout-digest/index.ts
// F3 — camada de comunicacao do fecho semanal. Le settlements ja fechados (via
// RPC weekly_closeout_compile) e comunica. NAO calcula dinheiro.
// v3 (2026-09-05): dominio de envio passou de boraapp.com (nunca existiu) para
// boraguarda.com, o dominio real do Danilo. Adicionado <meta charset=utf-8> nos
// emails para os acentos nao sairem partidos.
// v4 (2026-09-05): a razao de um envio falhado passa a ficar escrita na coluna
// weekly_digest_log.email_error — antes so ficava a palavra 'failed' e a causa
// perdia-se na consola (a falha de 31/08 so se explicou por deducao). E quem
// fica 'skipped' por nao ter email valido passa a aparecer no aviso ao Danilo,
// em vez de desaparecer em silencio. Textos do recibo passam a PT-PT com acentos.

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
}

const ADMIN_EMAIL = 'boraappbora@gmail.com'
const EMAIL_FROM = 'Bora App <fecho@boraguarda.com>'
const META = '<meta charset="utf-8">'
const GREEN = '#16A34A'

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

  let weekStart = null
  try { const b = await req.json(); weekStart = b?.week_start ? String(b.week_start) : null } catch (_e) {}

  const supabase = createClient(supabaseUrl, serviceKey)
  const resendKey = Deno.env.get('RESEND_API_KEY')

  const { data: summary, error: compErr } = await supabase
    .rpc('weekly_closeout_compile', { p_week_start: weekStart })
  if (compErr) {
    return new Response(JSON.stringify({ ok: false, error: 'compile_failed', detail: compErr.message }),
      { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } })
  }
  const ws = summary?.week_start ?? null
  if (!ws) {
    return new Response(JSON.stringify({ ok: true, note: 'sem settlements para compilar', summary }),
      { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' } })
  }

  const { data: gateRow } = await supabase.from('platform_settings')
    .select('value').eq('key', 'weekly_digest_emails_enabled').maybeSingle()
  const emailsEnabled = gateRow?.value === true || gateRow?.value === 'true'
  const { data: mbwayRow } = await supabase.from('platform_settings')
    .select('value').eq('key', 'bora_mbway_phone').maybeSingle()
  const boraMbway = (typeof mbwayRow?.value === 'string' ? mbwayRow.value : '') || ''

  const { data: weekRowsRaw } = await supabase.from('weekly_digest_log')
    .select('*').gte('week_start_at', ws + 'T00:00:00Z').lte('week_start_at', ws + 'T23:59:59Z')
  const weekRows = weekRowsRaw ?? []

  let sent = 0, queued = 0, skipped = 0
  // v4: quem ficou de fora, e porque. Vai no aviso ao Danilo la em baixo, em
  // vez de ficar so uma palavra na tabela que ninguem le.
  const problemas = []
  for (const r of weekRows) {
    const to = r.subject_email && String(r.subject_email).includes('@') ? String(r.subject_email) : null
    const html = buildReceiptHtml(r, boraMbway)
    let status = r.email_status
    let erro = null
    if (!to) {
      status = 'skipped'; skipped++
      erro = 'sem email valido'
      problemas.push({ name: r.subject_name, type: r.subject_type, motivo: erro,
                       amount_cents: r.net_cents, mbway: r.subject_phone })
    } else if (emailsEnabled || to.toLowerCase() === ADMIN_EMAIL.toLowerCase()) {
      const res = await sendResend(resendKey, to,
        'O seu fecho da semana ' + ddmm(r.week_start_at) + '-' + ddmm(r.week_end_at) + ' · Bora', html)
      status = res.ok ? 'sent' : 'failed'
      if (res.ok) {
        sent++
      } else {
        erro = res.error
        problemas.push({ name: r.subject_name, type: r.subject_type, motivo: 'envio falhou: ' + erro,
                         amount_cents: r.net_cents, mbway: r.subject_phone })
      }
    } else {
      status = 'aguarda_dominio'; queued++
      erro = 'envio de emails desligado em platform_settings'
      problemas.push({ name: r.subject_name, type: r.subject_type, motivo: erro,
                       amount_cents: r.net_cents, mbway: r.subject_phone })
    }
    await supabase.from('weekly_digest_log').update({
      email_html: html, email_to: to, email_status: status, email_error: erro,
      email_sent_at: status === 'sent' ? new Date().toISOString() : null,
    }).eq('id', r.id)
  }

  const toPay = (summary.to_pay ?? [])
  const toReceive = (summary.to_receive ?? [])
  const zeroCount = summary.zero_count ?? 0
  const per = ddmm(ws) + '-' + ddmm(summary.week_end ?? ws)

  const linhas = (arr) => arr.map((x) =>
    '• ' + x.name + ' ' + eur(x.amount_cents) + (x.mbway ? ' (MB Way: ' + x.mbway + ')' : '')).join('\n')
  const linhasProb = problemas.map((x) =>
    '• ' + x.name + ' ' + eur(x.amount_cents) + ' — ' + x.motivo +
    (x.mbway ? ' (tel: ' + x.mbway + ')' : '')).join('\n')
  const pushBody =
    'A PAGAR (Bora paga): ' + (toPay.length ? '\n' + linhas(toPay) : 'ninguem') + '\n\n' +
    'A RECEBER (devem a Bora): ' + (toReceive.length ? '\n' + linhas(toReceive) : 'ninguem') + '\n\n' +
    'Zerados: ' + zeroCount +
    (problemas.length ? '\n\nNAO RECEBERAM O EMAIL (' + problemas.length + '):\n' + linhasProb : '')

  let adminPush = false
  try {
    // Reencaminha o MESMO JWT de entrada (ja validado como service_role acima).
    const res = await fetch(supabaseUrl + '/functions/v1/notify-admin-urgent', {
      method: 'POST',
      headers: { 'Authorization': authHeader, 'Content-Type': 'application/json' },
      body: JSON.stringify({
        kind: 'generic',
        title: 'Fecho da semana ' + per,
        body: pushBody.slice(0, 900),
        route: '/admin/acertos-semana',
        ref: 'weekly_closeout_' + ws,
      }),
    })
    adminPush = res.ok
  } catch (e) { console.error('[weekly-closeout] admin push falhou:', e) }

  let adminEmail = false
  if (resendKey) {
    const res = await sendResend(resendKey, ADMIN_EMAIL,
      'Fecho da semana ' + per + ' - acertos',
      buildAdminSummaryHtml(per, toPay, toReceive, zeroCount, boraMbway, problemas))
    adminEmail = res.ok
  }

  return new Response(JSON.stringify({
    ok: true, week_start: ws, week_end: summary.week_end,
    subjects: weekRows.length, emails_sent: sent, emails_aguarda_dominio: queued, emails_skipped: skipped,
    problemas,
    admin_push: adminPush, admin_email: adminEmail,
    to_pay: toPay.length, to_receive: toReceive.length, zero: zeroCount,
    emails_enabled: emailsEnabled, resend_key_present: !!resendKey,
  }), { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' } })
})

// v4: devolve {ok, error} em vez de um booleano seco, para a causa da falha
// poder ser escrita na tabela e mostrada ao Danilo.
async function sendResend(key, to, subject, html) {
  if (!key) {
    console.log('[weekly-closeout] RESEND_API_KEY em falta')
    return { ok: false, error: 'RESEND_API_KEY em falta' }
  }
  try {
    const res = await fetch('https://api.resend.com/emails', {
      method: 'POST',
      headers: { 'Authorization': 'Bearer ' + key, 'Content-Type': 'application/json' },
      body: JSON.stringify({ from: EMAIL_FROM, to: [to], subject, html }),
    })
    if (res.ok) return { ok: true, error: null }
    const detalhe = await res.text().catch(() => '')
    console.error('[weekly-closeout] resend ' + res.status + ': ' + detalhe)
    return { ok: false, error: 'resend ' + res.status + ': ' + detalhe.slice(0, 300) }
  } catch (e) {
    console.error('[weekly-closeout] resend excecao:', e)
    return { ok: false, error: 'excecao: ' + String(e).slice(0, 300) }
  }
}

function buildReceiptHtml(r, boraMbway) {
  const isOwe = r.direction === 'owes_bora'
  const isPay = r.direction === 'bora_pays'
  const net = eur(r.net_cents)
  const linhas = (Array.isArray(r.breakdown) ? r.breakdown : []).map((b) => {
    const v = b.value_cents ?? 0
    const sign = v < 0 ? '−' : ''
    const qty = b.qty != null ? ' <span style="color:#888">x' + b.qty + '</span>' : ''
    return '<tr><td style="padding:6px 0;color:#333">' + escapeHtml(b.label) + qty + '</td>' +
      '<td style="padding:6px 0;text-align:right;color:' + (v < 0 ? '#B45309' : '#111') + '">' + sign + eur(v) + '</td></tr>'
  }).join('')
  const cobranca = isOwe ? (
    '<div style="background:#FFF7ED;border:1px solid #FED7AA;border-radius:10px;padding:14px;margin-top:16px">' +
    '<div style="font-weight:700;color:#9A3412">A pagar à Bora: ' + net + '</div>' +
    (boraMbway
      ? '<div style="margin-top:6px;color:#7C2D12">Pague por <b>MB Way</b> para <b>' + escapeHtml(boraMbway) + '</b> · referência: fecho ' + ddmm(r.week_start_at) + '</div>'
      : '<div style="margin-top:6px;color:#7C2D12">Entraremos em contacto para combinar o acerto.</div>') +
    '</div>') : ''
  const receber = isPay ? (
    '<div style="background:#F0FDF4;border:1px solid #BBF7D0;border-radius:10px;padding:14px;margin-top:16px">' +
    '<div style="font-weight:700;color:#166534">A receber da Bora: ' + net + '</div>' +
    '<div style="margin-top:6px;color:#14532D">A transferência é feita na segunda-feira.</div></div>')
    : '<div style="margin-top:16px;color:#555">Saldo da semana: <b>' + net + '</b></div>'

  return META + '<div style="font-family:system-ui,Arial,sans-serif;max-width:560px;margin:auto">' +
    '<div style="background:' + GREEN + ';color:#fff;padding:18px 20px;border-radius:12px 12px 0 0">' +
    '<div style="font-size:20px;font-weight:800">Bora</div>' +
    '<div style="opacity:.9">Fecho da semana ' + ddmm(r.week_start_at) + '-' + ddmm(r.week_end_at) + '</div></div>' +
    '<div style="border:1px solid #eee;border-top:0;border-radius:0 0 12px 12px;padding:20px">' +
    '<p style="margin:0 0 12px">Olá <b>' + escapeHtml(r.subject_name || '') + '</b>, aqui está o resumo da sua semana.</p>' +
    '<table style="width:100%;border-collapse:collapse;font-size:14px">' + linhas +
    '<tr><td colspan="2" style="border-top:1px solid #eee;padding-top:8px"></td></tr>' +
    '<tr><td style="font-weight:700">Saldo da semana</td>' +
    '<td style="text-align:right;font-weight:800;color:' + (isOwe ? '#B45309' : GREEN) + '">' + (isOwe ? '−' : '') + net + '</td></tr>' +
    '</table>' + (isOwe ? cobranca : receber) +
    '<p style="font-size:11px;color:#999;margin-top:20px">Bora App · fecho semanal automático</p></div></div>'
}

function buildAdminSummaryHtml(per, toPay, toReceive, zero, boraMbway, problemas) {
  const li = (arr) => arr.length
    ? arr.map((x) => '<li><b>' + escapeHtml(x.name) + '</b> - ' + eur(x.amount_cents) + (x.mbway ? ' · MB Way ' + escapeHtml(x.mbway) : '') + ' <span style="color:#999">(' + x.type + ')</span></li>').join('')
    : '<li style="color:#999">ninguem</li>'
  const probs = (problemas && problemas.length)
    ? '<h3 style="color:#B45309;margin-bottom:4px">NÃO RECEBERAM O EMAIL (' + problemas.length + ')</h3><ul>' +
      problemas.map((x) => '<li><b>' + escapeHtml(x.name) + '</b> - ' + eur(x.amount_cents) +
        ' — ' + escapeHtml(x.motivo) + (x.mbway ? ' · tel ' + escapeHtml(x.mbway) : '') + '</li>').join('') + '</ul>'
    : ''
  return META + '<div style="font-family:system-ui,Arial,sans-serif;max-width:600px;margin:auto">' +
    '<h2 style="color:' + GREEN + '">Fecho da semana ' + per + '</h2>' +
    '<h3 style="color:#166534;margin-bottom:4px">A PAGAR (Bora paga)</h3><ul>' + li(toPay) + '</ul>' +
    '<h3 style="color:#9A3412;margin-bottom:4px">A RECEBER (devem à Bora)</h3><ul>' + li(toReceive) + '</ul>' +
    probs +
    '<p style="color:#555">Zerados: <b>' + zero + '</b></p>' +
    (boraMbway ? '<p style="font-size:12px;color:#777">MB Way da Bora para cobranças: <b>' + escapeHtml(boraMbway) + '</b></p>' : '<p style="font-size:12px;color:#B45309">Falta definir o MB Way da Bora (Acertos da semana -> configurar).</p>') +
    '<p style="font-size:11px;color:#999;margin-top:20px">Bora App · fecho semanal · lembre-se de marcar os pagos no painel</p></div>'
}

// @ts-nocheck
// supabase/functions/weekly-closeout-digest/index.ts
//
// F3 — CAMADA DE COMUNICAÇÃO DO FECHO SEMANAL (corre 2.ª feira 09:00, DEPOIS de
// todos os crons de settlement por vertical). NÃO calcula dinheiro: lê o que os
// settlements já fecharam (via RPC weekly_closeout_compile) e comunica.
//
// Faz:
//  1) weekly_closeout_compile(week_start) → resumo + grava weekly_digest_log.
//  2) Emails individuais (recibo HTML PT-PT). GATE DO RESEND (modo teste, sem
//     domínio verificado): envia DE VERDADE só para o email do Danilo; os
//     restantes ficam gravados com email_status='aguarda_dominio'. O setting
//     weekly_digest_emails_enabled=true (quando o domínio estiver verificado)
//     liga o envio externo a todos.
//  3) Resumo ao Danilo (funciona já): push admin persistente + Telegram (via
//     notify-admin-urgent kind=generic) + email Resend com a lista A PAGAR /
//     A RECEBER / Zerados.
//
// Auth: verify_jwt=true; confirma role='service_role' (cron via pg_net com a
// service key, ou invocação manual com a service key).
//
// Secrets: SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY (auto), RESEND_API_KEY (opc).

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
}

const ADMIN_EMAIL = 'boraappbora@gmail.com'
const EMAIL_FROM = 'Bora App <noreply@boraapp.com>'
const GREEN = '#16A34A'

function eur(cents: number): string {
  return '€' + (Math.abs(cents ?? 0) / 100).toFixed(2).replace('.', ',')
}
function escapeHtml(s: string): string {
  return String(s ?? '').replace(/&/g, '&amp;').replace(/</g, '&lt;')
    .replace(/>/g, '&gt;').replace(/"/g, '&quot;').replace(/'/g, '&#39;')
}
function ddmm(iso: string): string {
  const d = new Date(iso)
  const p = (n: number) => String(n).padStart(2, '0')
  return `${p(d.getUTCDate())}/${p(d.getUTCMonth() + 1)}`
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders })

  const supabaseUrl = Deno.env.get('SUPABASE_URL')!
  const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!

  // ── Auth: só service_role ────────────────────────────────────────────────
  const authHeader = req.headers.get('Authorization') ?? ''
  try {
    if (!authHeader.startsWith('Bearer ')) throw new Error('no bearer')
    const payload = JSON.parse(atob(authHeader.substring(7).split('.')[1]))
    if (payload.role !== 'service_role') throw new Error('role')
  } catch (_e) {
    return new Response(JSON.stringify({ ok: false, error: 'forbidden' }),
      { status: 403, headers: { ...corsHeaders, 'Content-Type': 'application/json' } })
  }

  let weekStart: string | null = null
  try { const b = await req.json(); weekStart = b?.week_start ? String(b.week_start) : null } catch (_e) { /* body opcional */ }

  const supabase = createClient(supabaseUrl, serviceKey)
  const resendKey = Deno.env.get('RESEND_API_KEY')

  // ── 1) Compilar (grava weekly_digest_log) ────────────────────────────────
  const { data: summary, error: compErr } = await supabase
    .rpc('weekly_closeout_compile', { p_week_start: weekStart })
  if (compErr) {
    return new Response(JSON.stringify({ ok: false, error: 'compile_failed', detail: compErr.message }),
      { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } })
  }
  const ws: string | null = summary?.week_start ?? null
  if (!ws) {
    return new Response(JSON.stringify({ ok: true, note: 'sem settlements para compilar', summary }),
      { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' } })
  }

  // Setting: envio externo ligado?
  const { data: gateRow } = await supabase.from('platform_settings')
    .select('value').eq('key', 'weekly_digest_emails_enabled').maybeSingle()
  const emailsEnabled = gateRow?.value === true || gateRow?.value === 'true'
  const { data: mbwayRow } = await supabase.from('platform_settings')
    .select('value').eq('key', 'bora_mbway_phone').maybeSingle()
  const boraMbway = (typeof mbwayRow?.value === 'string' ? mbwayRow.value : '') || ''

  // ── 2) Emails individuais (com o GATE) ───────────────────────────────────
  const { data: weekRowsRaw } = await supabase.from('weekly_digest_log')
    .select('*').gte('week_start_at', `${ws}T00:00:00Z`).lte('week_start_at', `${ws}T23:59:59Z`)
  const weekRows = weekRowsRaw ?? []

  let sent = 0, queued = 0, skipped = 0
  for (const r of weekRows) {
    const to = r.subject_email && String(r.subject_email).includes('@') ? String(r.subject_email) : null
    const html = buildReceiptHtml(r, boraMbway)
    let status = r.email_status
    if (!to) {
      status = 'skipped'; skipped++
    } else if (emailsEnabled || to.toLowerCase() === ADMIN_EMAIL.toLowerCase()) {
      // envia de verdade (externo ligado, ou é o email do Danilo em modo teste)
      const okSent = await sendResend(resendKey, to, `O teu fecho da semana ${ddmm(r.week_start_at)}–${ddmm(r.week_end_at)} · Bora`, html)
      status = okSent ? 'sent' : 'failed'; if (okSent) sent++
    } else {
      status = 'aguarda_dominio'; queued++ // pronto, à espera do domínio verificado
    }
    await supabase.from('weekly_digest_log').update({
      email_html: html, email_to: to, email_status: status,
      email_sent_at: status === 'sent' ? new Date().toISOString() : null,
    }).eq('id', r.id)
  }

  // ── 3) Resumo ao Danilo (push+telegram via notify-admin-urgent + email) ──
  const toPay = (summary.to_pay ?? []) as any[]
  const toReceive = (summary.to_receive ?? []) as any[]
  const zeroCount = summary.zero_count ?? 0
  const per = ddmm(ws) + '–' + ddmm(summary.week_end ?? ws)

  const linhas = (arr: any[]) => arr.map((x) =>
    `• ${x.name} ${eur(x.amount_cents)}${x.mbway ? ` (MB Way: ${x.mbway})` : ''}`).join('\n')
  const pushBody =
    `A PAGAR (Bora paga): ${toPay.length ? '\n' + linhas(toPay) : 'ninguém'}\n\n` +
    `A RECEBER (devem à Bora): ${toReceive.length ? '\n' + linhas(toReceive) : 'ninguém'}\n\n` +
    `Zerados: ${zeroCount}`

  let adminPush = false
  try {
    // Reencaminha o MESMO JWT de entrada (já validado como service_role acima).
    // Reconstruir com Deno.env SUPABASE_SERVICE_ROLE_KEY dava 403 na notify-admin-urgent.
    const res = await fetch(`${supabaseUrl}/functions/v1/notify-admin-urgent`, {
      method: 'POST',
      headers: { 'Authorization': authHeader, 'Content-Type': 'application/json' },
      body: JSON.stringify({
        kind: 'generic',
        title: `📊 Fecho da semana ${per}`,
        body: pushBody.slice(0, 900),
        route: '/admin/acertos-semana',
        ref: `weekly_closeout_${ws}`,
      }),
    })
    adminPush = res.ok
  } catch (e) { console.error('[weekly-closeout] admin push falhou:', e) }

  let adminEmail = false
  if (resendKey) {
    adminEmail = await sendResend(resendKey, ADMIN_EMAIL,
      `📊 Fecho da semana ${per} — acertos`, buildAdminSummaryHtml(per, toPay, toReceive, zeroCount, boraMbway))
  }

  return new Response(JSON.stringify({
    ok: true, week_start: ws, week_end: summary.week_end,
    subjects: weekRows.length, emails_sent: sent, emails_aguarda_dominio: queued, emails_skipped: skipped,
    admin_push: adminPush, admin_email: adminEmail,
    to_pay: toPay.length, to_receive: toReceive.length, zero: zeroCount,
    emails_enabled: emailsEnabled, resend_key_present: !!resendKey,
  }), { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' } })
})

// ── Resend ──────────────────────────────────────────────────────────────────
async function sendResend(key: string | undefined, to: string, subject: string, html: string): Promise<boolean> {
  if (!key) { console.log('[weekly-closeout] RESEND_API_KEY em falta — email saltado'); return false }
  try {
    const res = await fetch('https://api.resend.com/emails', {
      method: 'POST',
      headers: { 'Authorization': `Bearer ${key}`, 'Content-Type': 'application/json' },
      body: JSON.stringify({ from: EMAIL_FROM, to: [to], subject, html }),
    })
    if (res.ok) return true
    console.error(`[weekly-closeout] resend ${res.status}: ${await res.text().catch(() => '')}`)
    return false
  } catch (e) { console.error('[weekly-closeout] resend exceção:', e); return false }
}

// ── Templates HTML ───────────────────────────────────────────────────────────
function buildReceiptHtml(r: any, boraMbway: string): string {
  const isOwe = r.direction === 'owes_bora'
  const isPay = r.direction === 'bora_pays'
  const net = eur(r.net_cents)
  const linhas = (Array.isArray(r.breakdown) ? r.breakdown : []).map((b: any) => {
    const v = b.value_cents ?? 0
    const sign = v < 0 ? '−' : ''
    const qty = b.qty != null ? ` <span style="color:#888">×${b.qty}</span>` : ''
    return `<tr><td style="padding:6px 0;color:#333">${escapeHtml(b.label)}${qty}</td>
      <td style="padding:6px 0;text-align:right;color:${v < 0 ? '#B45309' : '#111'}">${sign}${eur(v)}</td></tr>`
  }).join('')
  const cobranca = isOwe ? `
    <div style="background:#FFF7ED;border:1px solid #FED7AA;border-radius:10px;padding:14px;margin-top:16px">
      <div style="font-weight:700;color:#9A3412">A pagar à Bora: ${net}</div>
      ${boraMbway
        ? `<div style="margin-top:6px;color:#7C2D12">Paga por <b>MB Way</b> para <b>${escapeHtml(boraMbway)}</b> · referência: fecho ${ddmm(r.week_start_at)}</div>`
        : `<div style="margin-top:6px;color:#7C2D12">Entraremos em contacto para combinar o acerto.</div>`}
    </div>` : ''
  const receber = isPay ? `
    <div style="background:#F0FDF4;border:1px solid #BBF7D0;border-radius:10px;padding:14px;margin-top:16px">
      <div style="font-weight:700;color:#166534">A receber da Bora: ${net}</div>
      <div style="margin-top:6px;color:#14532D">Transferência na segunda-feira.</div>
    </div>` : `<div style="margin-top:16px;color:#555">Saldo da semana: <b>${net}</b></div>`

  return `<div style="font-family:system-ui,Arial,sans-serif;max-width:560px;margin:auto">
    <div style="background:${GREEN};color:#fff;padding:18px 20px;border-radius:12px 12px 0 0">
      <div style="font-size:20px;font-weight:800">Bora</div>
      <div style="opacity:.9">Fecho da semana ${ddmm(r.week_start_at)}–${ddmm(r.week_end_at)}</div>
    </div>
    <div style="border:1px solid #eee;border-top:0;border-radius:0 0 12px 12px;padding:20px">
      <p style="margin:0 0 12px">Olá <b>${escapeHtml(r.subject_name || '')}</b>, aqui está o resumo da tua semana.</p>
      <table style="width:100%;border-collapse:collapse;font-size:14px">
        ${linhas}
        <tr><td colspan="2" style="border-top:1px solid #eee;padding-top:8px"></td></tr>
        <tr><td style="font-weight:700">Saldo da semana</td>
          <td style="text-align:right;font-weight:800;color:${isOwe ? '#B45309' : GREEN}">${isOwe ? '−' : ''}${net}</td></tr>
      </table>
      ${isOwe ? cobranca : receber}
      <p style="font-size:11px;color:#999;margin-top:20px">Bora App · fecho semanal automático</p>
    </div>
  </div>`
}

function buildAdminSummaryHtml(per: string, toPay: any[], toReceive: any[], zero: number, boraMbway: string): string {
  const li = (arr: any[]) => arr.length
    ? arr.map((x) => `<li><b>${escapeHtml(x.name)}</b> — ${eur(x.amount_cents)}${x.mbway ? ` · MB Way ${escapeHtml(x.mbway)}` : ''} <span style="color:#999">(${x.type})</span></li>`).join('')
    : '<li style="color:#999">ninguém</li>'
  return `<div style="font-family:system-ui,Arial,sans-serif;max-width:600px;margin:auto">
    <h2 style="color:${GREEN}">📊 Fecho da semana ${per}</h2>
    <h3 style="color:#166534;margin-bottom:4px">💚 A PAGAR (Bora paga)</h3>
    <ul>${li(toPay)}</ul>
    <h3 style="color:#9A3412;margin-bottom:4px">💸 A RECEBER (devem à Bora)</h3>
    <ul>${li(toReceive)}</ul>
    <p style="color:#555">Zerados: <b>${zero}</b></p>
    ${boraMbway ? `<p style="font-size:12px;color:#777">MB Way do Bora para cobranças: <b>${escapeHtml(boraMbway)}</b></p>` : `<p style="font-size:12px;color:#B45309">⚠️ Falta definir o MB Way do Bora (Acertos da semana → configurar).</p>`}
    <p style="font-size:11px;color:#999;margin-top:20px">Bora App · fecho semanal · lembra de marcar os pagos no painel</p>
  </div>`
}

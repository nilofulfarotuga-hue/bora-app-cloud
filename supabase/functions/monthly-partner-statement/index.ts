// @ts-nocheck
// supabase/functions/monthly-partner-statement/index.ts
// B3 (missão fecho-mensal-2026-09, 29/09/2026) — extrato MENSAL de cada loja
// parceira, por email, no dia 1 às 09:00 de Lisboa. Não calcula dinheiro: lê
// a RPC partner_monthly_statement (B2) e, para o admin, admin_monthly_closeout (B1).
//
// Mesmo caminho do weekly-closeout-digest: service_role obrigatório, chave da
// Resend no env ou no vault (get_resend_key), remetente fecho@boraguarda.com,
// endereços mortos e contas demo nunca recebem.
//
// Idempotente: monthly_statement_log (partner_id, ano, mes). Quem já tem
// email_status='sent' não recebe outra vez, a não ser com force:true (botão
// "Reenviar extrato do mês" do painel, via admin_resend_monthly_statement).
//
// Corpo aceite:
//   { year, month }        mês a enviar (por defeito: o mês anterior, em Lisboa)
//   { partner_id }         só esta loja
//   { force: true }        reenvia mesmo já enviado
//   { admin_summary }      manda também o resumo B1 ao admin (por defeito: true se não houver partner_id)
//   { cron: true }         só corre se em Lisboa for dia 1 às 09h (o pg_cron dispara às 08 e 09 UTC)

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

const TERMINACOES_MORTAS = ['.test', '.invalid', '.example', '.localhost', '.local',
  'example.com', 'example.org', 'example.net']
const CAIXAS_INVENTADAS = ['test', 'teste', 'testes', 'testing', 'newuser', 'demo',
  'exemplo', 'example', 'noreply', 'no-reply', 'asdf', 'qwerty']
const FORNECEDORES_GRANDES = ['gmail.com', 'hotmail.com', 'outlook.com', 'outlook.pt',
  'live.com', 'yahoo.com', 'icloud.com', 'sapo.pt']

function enderecoMorto(email) {
  const e = String(email || '').trim().toLowerCase()
  if (!e.includes('@')) return true
  if (TERMINACOES_MORTAS.some((f) => e.endsWith(f))) return true
  const [caixa, dominio] = e.split('@')
  return FORNECEDORES_GRANDES.includes(dominio) &&
    CAIXAS_INVENTADAS.includes(caixa.split('+')[0])
}

function eur(v) {
  return (Number(v ?? 0)).toFixed(2).replace('.', ',') + ' €'
}
function esc(s) {
  return String(s ?? '').replace(/&/g, '&amp;').replace(/</g, '&lt;')
    .replace(/>/g, '&gt;').replace(/"/g, '&quot;').replace(/'/g, '&#39;')
}
function json(body, status = 200) {
  return new Response(JSON.stringify(body),
    { status, headers: { ...corsHeaders, 'Content-Type': 'application/json' } })
}

// Data/hora de agora em Lisboa (sem bibliotecas).
function agoraLisboa() {
  const p = new Intl.DateTimeFormat('en-GB', {
    timeZone: 'Europe/Lisbon', year: 'numeric', month: '2-digit', day: '2-digit',
    hour: '2-digit', hour12: false,
  }).formatToParts(new Date())
  const g = (t) => Number(p.find((x) => x.type === t)?.value)
  return { ano: g('year'), mes: g('month'), dia: g('day'), hora: g('hour') % 24 }
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders })

  const authHeader = req.headers.get('Authorization') ?? ''
  try {
    if (!authHeader.startsWith('Bearer ')) throw new Error('no bearer')
    const payload = JSON.parse(atob(authHeader.substring(7).split('.')[1]))
    if (payload.role !== 'service_role') throw new Error('role')
  } catch (_e) {
    return json({ ok: false, error: 'forbidden' }, 403)
  }

  let b = {}
  try { b = await req.json() } catch (_e) {}

  const agora = agoraLisboa()
  if (b?.cron === true && !(agora.dia === 1 && agora.hora === 9)) {
    return json({ ok: true, skipped: 'fora da hora (so dia 1 as 09h de Lisboa)', agora })
  }

  let ano = Number(b?.year) || null
  let mes = Number(b?.month) || null
  if (!ano || !mes) {
    ano = agora.mes === 1 ? agora.ano - 1 : agora.ano
    mes = agora.mes === 1 ? 12 : agora.mes - 1
  }
  const partnerId = b?.partner_id ? String(b.partner_id) : null
  const force = b?.force === true
  const adminSummary = b?.admin_summary !== undefined ? b.admin_summary === true : !partnerId

  const supabase = createClient(Deno.env.get('SUPABASE_URL'), Deno.env.get('SUPABASE_SERVICE_ROLE_KEY'))

  let resendKey = Deno.env.get('RESEND_API_KEY') ?? null
  if (!resendKey) {
    try {
      const { data } = await supabase.rpc('get_resend_key')
      if (data && String(data).trim()) resendKey = String(data).trim()
    } catch (e) { console.error('[monthly-statement] vault:', e) }
  }

  const { data: gateRow } = await supabase.from('platform_settings')
    .select('value').eq('key', 'weekly_digest_emails_enabled').maybeSingle()
  const emailsEnabled = gateRow?.value === true || gateRow?.value === 'true'

  const { data: destinatarios, error: recErr } = await supabase
    .rpc('monthly_statement_recipients', { p_year: ano, p_month: mes })
  if (recErr) return json({ ok: false, error: 'recipients_failed', detail: recErr.message }, 500)

  const lista = (destinatarios ?? []).filter((d) => !partnerId || d.partner_id === partnerId)
  const resultados = []

  for (const d of lista) {
    const { data: logRow } = await supabase.from('monthly_statement_log').select('*')
      .eq('partner_id', d.partner_id).eq('ano', ano).eq('mes', mes).maybeSingle()
    if (logRow?.email_status === 'sent' && !force) {
      resultados.push({ partner_id: d.partner_id, nome: d.nome, estado: 'ja_enviado' })
      continue
    }

    const { data: ext, error: extErr } = await supabase.rpc('partner_monthly_statement',
      { p_partner_id: d.partner_id, p_year: ano, p_month: mes })
    let estado = 'failed'
    let erro = null
    let to = d.email && !enderecoMorto(d.email) ? String(d.email).trim() : null

    if (extErr) {
      erro = 'extrato falhou: ' + extErr.message
    } else if (!to) {
      estado = 'skipped'
      erro = d.email ? 'endereço que não recebe correio (' + d.email + ')' : 'sem email'
    } else {
      let demo = false
      try {
        const { data: isDemo } = await supabase.rpc('is_demo_email', { p_email: to })
        demo = isDemo === true
      } catch (e) { console.error('[monthly-statement] is_demo_email:', e) }
      if (demo) {
        estado = 'skipped'; erro = 'conta de demonstração — sem extrato'; to = null
      } else if (!emailsEnabled && to.toLowerCase() !== ADMIN_EMAIL) {
        estado = 'aguarda_dominio'; erro = 'envio de emails desligado em platform_settings'
      } else {
        const res = await sendResend(resendKey, to,
          'O seu extrato de ' + ext.periodo.nome + ' de ' + ano + ' · Bora', htmlParceiro(ext))
        estado = res.ok ? 'sent' : 'failed'
        erro = res.ok ? null : res.error
      }
    }

    await supabase.from('monthly_statement_log').upsert({
      partner_id: d.partner_id, ano, mes, email_to: to, email_status: estado, email_error: erro,
      sent_at: estado === 'sent' ? new Date().toISOString() : (logRow?.sent_at ?? null),
      updated_at: new Date().toISOString(),
    }, { onConflict: 'partner_id,ano,mes' })
    resultados.push({ partner_id: d.partner_id, nome: d.nome, email: to, estado, erro })
  }

  let admin = null
  if (adminSummary) {
    const { data: fecho, error: fErr } = await supabase
      .rpc('admin_monthly_closeout', { p_year: ano, p_month: mes })
    if (fErr) {
      admin = { ok: false, error: fErr.message }
    } else {
      const res = await sendResend(resendKey, ADMIN_EMAIL,
        'Fecho de ' + fecho.periodo.nome + ' ' + ano + ' — resumo e parte para as Finanças',
        htmlAdmin(fecho, resultados))
      admin = res
    }
  }

  return json({
    ok: true, ano, mes, partner_id: partnerId, force, emails_enabled: emailsEnabled,
    resend_key_present: !!resendKey, extratos: resultados, admin_summary: admin,
  })
})

async function sendResend(key, to, subject, html) {
  if (!key) return { ok: false, error: 'RESEND_API_KEY em falta' }
  try {
    const res = await fetch('https://api.resend.com/emails', {
      method: 'POST',
      headers: { 'Authorization': 'Bearer ' + key, 'Content-Type': 'application/json' },
      body: JSON.stringify({ from: EMAIL_FROM, to: [to], subject, html }),
    })
    const txt = await res.text().catch(() => '')
    if (res.ok) {
      let id = null
      try { id = JSON.parse(txt)?.id ?? null } catch (_e) {}
      return { ok: true, error: null, id }
    }
    return { ok: false, error: 'resend ' + res.status + ': ' + txt.slice(0, 300) }
  } catch (e) {
    return { ok: false, error: 'excecao: ' + String(e).slice(0, 300) }
  }
}

function estadoAcerto(s) {
  if (s === 'paid') return 'pago'
  if (s === 'pending') return 'por pagar'
  return s ?? ''
}

function htmlParceiro(x) {
  const td = 'padding:6px 4px;border-bottom:1px solid #f1f1f1'
  const linhas = (x.pedidos ?? []).map((p) =>
    '<tr><td style="' + td + '">' + esc(p.data) + '</td><td style="' + td + '">#' + esc(p.numero) + '</td>' +
    '<td style="' + td + ';text-align:right">' + eur(p.subtotal) + '</td>' +
    '<td style="' + td + ';text-align:right;color:#B45309">−' + eur(p.comissao) + '</td>' +
    '<td style="' + td + ';text-align:right;font-weight:700">' + eur(p.recebeu) + '</td></tr>').join('')
  const acertos = (x.acertos_semanais ?? []).map((a) =>
    '<tr><td style="' + td + '">Semana ' + esc(a.semana) + '</td>' +
    '<td style="' + td + ';text-align:right">' + eur(a.valor) + '</td>' +
    '<td style="' + td + '">' + esc(estadoAcerto(a.estado)) + (a.pago_em ? ' em ' + esc(a.pago_em) : '') + '</td></tr>').join('')
  const t = x.totais ?? {}
  return META + '<div style="font-family:system-ui,Arial,sans-serif;max-width:620px;margin:auto">' +
    '<div style="background:' + GREEN + ';color:#fff;padding:18px 20px;border-radius:12px 12px 0 0">' +
    '<div style="font-size:20px;font-weight:800">Bora</div>' +
    '<div style="opacity:.9">Extrato de ' + esc(x.periodo.nome) + ' de ' + x.periodo.ano + '</div></div>' +
    '<div style="border:1px solid #eee;border-top:0;border-radius:0 0 12px 12px;padding:20px">' +
    '<p style="margin:0 0 12px">Olá <b>' + esc(x.parceiro.nome) + '</b>, aqui está o resumo do seu mês na Bora.</p>' +
    '<table style="width:100%;border-collapse:collapse;font-size:14px;margin-bottom:12px">' +
    '<tr><td>Pedidos entregues</td><td style="text-align:right;font-weight:700">' + (t.pedidos ?? 0) + '</td></tr>' +
    '<tr><td>Vendas</td><td style="text-align:right">' + eur(t.vendas) + '</td></tr>' +
    '<tr><td>Comissão Bora</td><td style="text-align:right;color:#B45309">−' + eur(t.comissao) + '</td></tr>' +
    '<tr><td style="font-weight:700">A sua parte</td><td style="text-align:right;font-weight:800;color:' + GREEN + '">' + eur(t.parte_loja) + '</td></tr>' +
    '<tr><td>Pago no mês (acertos semanais)</td><td style="text-align:right">' + eur(x.total_pago_no_mes) + '</td></tr>' +
    '<tr><td style="font-weight:700">Saldo</td><td style="text-align:right;font-weight:800">' + eur(x.saldo) + '</td></tr>' +
    '</table>' +
    '<h3 style="font-size:15px;margin:18px 0 6px">Pedidos do mês</h3>' +
    '<table style="width:100%;border-collapse:collapse;font-size:13px">' +
    '<tr style="color:#666"><td>Data</td><td>N.º</td><td style="text-align:right">Subtotal</td><td style="text-align:right">Comissão</td><td style="text-align:right">Recebe</td></tr>' +
    linhas + '</table>' +
    '<h3 style="font-size:15px;margin:18px 0 6px">Acertos semanais</h3>' +
    '<table style="width:100%;border-collapse:collapse;font-size:13px">' + (acertos || '<tr><td style="color:#999">Sem acertos neste mês.</td></tr>') + '</table>' +
    '<p style="font-size:12px;color:#777;margin-top:18px">Também pode ver e descarregar este extrato na app, em Ganhos → Este mês.</p>' +
    '<p style="font-size:11px;color:#999;margin-top:12px">Bora App · extrato mensal automático</p></div></div>'
}

function htmlAdmin(f, resultados) {
  const t = f.totais ?? {}
  const fin = f.para_as_financas ?? {}
  const fat = (fin.faturas_recibo ?? []).map((x) =>
    '<li><b>' + esc(x.destinatario) + '</b>' + (x.nif ? ' (NIF ' + esc(x.nif) + ')' : (x.falta_nif ? ' <span style="color:#B45309">(falta NIF)</span>' : '')) +
    ' — ' + eur(x.valor) + ' · ' + esc(x.descricao) + '</li>').join('')
  const prej = (f.pedidos_no_prejuizo ?? []).map((p) =>
    '<li>' + esc(p.data) + ' ' + esc(p.loja) + ': ' + eur(p.resultado) + ' — ' + esc(p.motivo) + '</li>').join('')
  const ext = (resultados ?? []).map((r) =>
    '<li>' + esc(r.nome) + ': ' + esc(r.estado) + (r.erro ? ' — ' + esc(r.erro) : '') + '</li>').join('')
  return META + '<div style="font-family:system-ui,Arial,sans-serif;max-width:640px;margin:auto">' +
    '<h2 style="color:' + GREEN + '">Fecho de ' + esc(f.periodo.nome) + ' ' + f.periodo.ano + '</h2>' +
    '<p>Pedidos entregues: <b>' + t.pedidos_entregues + '</b> · Pago pelos clientes: <b>' + eur(t.pago_pelos_clientes) + '</b><br>' +
    'Mercadoria: ' + eur(t.custo_mercadoria) + ' · Receita própria: <b>' + eur(t.receita_propria_bora) + '</b><br>' +
    'Estafetas: ' + eur(t.pago_a_estafetas) + ' · Lucro: <b>' + eur(t.lucro) + '</b><br>' +
    'TVDE de outros motoristas (parte Bora): <b>' + eur(fin.parte_bora_tvde_outros) + '</b></p>' +
    '<h3>Para as Finanças</h3><p style="line-height:1.5">' + esc(fin.texto) + '</p>' +
    '<p>Total a declarar: <b>' + eur(fin.total_a_declarar) + '</b></p>' +
    '<h3>Faturas-recibo a emitir</h3><ul>' + fat + '</ul>' +
    (prej ? '<h3 style="color:#B45309">Pedidos no prejuízo</h3><ul>' + prej + '</ul>' : '') +
    (ext ? '<h3>Extratos às lojas</h3><ul>' + ext + '</ul>' : '') +
    '<p style="font-size:11px;color:#999">Bora App · fecho mensal · detalhe em /admin/fecho-mensal</p></div>'
}

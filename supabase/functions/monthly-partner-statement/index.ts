// @ts-nocheck
// supabase/functions/monthly-partner-statement/index.ts
// B3 (missão fecho-mensal-2026-09, 29/09/2026) — extrato MENSAL de cada loja
// parceira, por email, no dia 1 às 09:00 de Lisboa. Não calcula dinheiro: lê
// a RPC partner_monthly_statement (B2) e, para o admin, admin_monthly_closeout (B1).
//
// v2 (30/09/2026, pedido do Danilo): também manda a CADA ESTAFETA o resumo do
// recibo verde do mês (RPC driver_monthly_invoice_summary). Só a partir do mês
// de outubro de 2026 (o modelo novo começa a 01/10; setembro não tem recibo).
// Idempotente em driver_monthly_statement_log (user_id, ano, mes).
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
//   { partner_id }         só esta loja (não manda aos estafetas)
//   { driver_user_id }     só este estafeta (não manda às lojas)
//   { force: true }        reenvia mesmo já enviado
//   { admin_summary }      manda também o resumo B1 ao admin (por defeito: true se não houver partner_id nem driver_user_id)
//   { cron: true }         só corre se em Lisboa for dia 1 às 09h (o pg_cron dispara às 08 e 09 UTC)
//
// v3 (01/11/2026, missão contabilista-2026-11-01) — ADQUIRENTE DO RECIBO VERDE. O email de 01/11
// disse aos estafetas "Cliente: Consumidor final" e não disse a quem passar o recibo. Agora o
// adquirente (nome, NIF, morada, individual/sociedade) vem de platform_settings
// (fecho_entidade_nome / fecho_entidade_nif / fecho_entidade_morada / fecho_entidade_tipo), com
// recurso ao que a RPC devolver. O texto do email ao estafeta passou a PT-PT simples, com o
// prazo legal (fatura-recibo até ao 5.º dia útil após o pagamento), IVA e retenção.
// Também manda à PROFISSIONAL DE LIMPEZA o extrato do mês com os dados do recibo (RPC
// fecho_mensal_prestadores; log em cleaner_monthly_statement_log) e salta a conta do próprio Danilo.
// Publicada a 01/11/2026 (ordem do Danilo), sem disparo: o próximo envio é o reenvio de outubro com force:true.
//
// v4 (10/11/2026, missão fecho-contabilista-2026-11-10). Nota: a 10/11 o código no ar (v12 da plataforma) era
// igual ao v3 do repo — a v3 estava publicada. Regras fechadas com o contabilista (Hugo Carvalho) a 10/11:
//  - nada de "IVA isento art. 53.º" nem "sem retenção" fixos: uns prestadores são isentos e outros não; o
//    regime de IVA e a retenção de cada um são confirmados pelo contabilista;
//  - o adquirente (a quem o prestador fatura) vem da RPC driver_monthly_invoice_summary /
//    fecho_mensal_prestadores (Danilo em nome individual até 10/2026, a sociedade desde 11/2026);
//  - às lojas: a parte da Bora fatura-se aos clientes, a loja não recebe fatura da Bora;
//  - TVDE fora do resumo.
// NÃO reenviar outubro: o contabilista já o recebeu e decide ele como tratar.

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'
import { secretKey } from '../_shared/keys.ts'
import { chamadaDoServidor, respostaAoPing } from '../_shared/chaves.ts'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
}

const ADMIN_EMAIL = 'boraappbora@gmail.com'
const EMAIL_FROM = 'Bora App <fecho@boraguarda.com>'
const META = '<meta charset="utf-8">'
const GREEN = '#16A34A'
// Primeiro mês em que o estafeta passa recibo (modelo novo a 01/10/2026).
const ESTAFETA_DESDE = 2026 * 12 + 10

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

  // 31/10/2026 (chaves-varredura): só o servidor, pela regra da casa (_shared/chaves.ts) — a
  // service_role legada passa confirmada no Auth; sem ler o papel do JWT à mão.
  if (!(await chamadaDoServidor(req))) return json({ ok: false, error: 'forbidden' }, 403)
  const pong = await respostaAoPing(req, corsHeaders)
  if (pong) return pong

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
  const driverId = b?.driver_user_id ? String(b.driver_user_id) : null
  const force = b?.force === true
  const adminSummary = b?.admin_summary !== undefined ? b.admin_summary === true : (!partnerId && !driverId)
  const fazerLojas = !driverId
  const fazerEstafetas = !partnerId && (ano * 12 + mes) >= ESTAFETA_DESDE

  const supabase = createClient(Deno.env.get('SUPABASE_URL'), secretKey())

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

  // v3: o adquirente dos recibos verdes (quem paga os prestadores neste mês). Primeiro o que a RPC
  // devolve (driver_monthly_invoice_summary / fecho_mensal_prestadores já decidem individual vs
  // sociedade pelo mês); as settings fecho_entidade_* são o recurso.
  const { data: entRows } = await supabase.from('platform_settings').select('key,value')
    .in('key', ['fecho_entidade_nome', 'fecho_entidade_nif', 'fecho_entidade_morada', 'fecho_entidade_tipo'])
  const ent = {}
  for (const r of (entRows ?? [])) ent[r.key] = typeof r.value === 'string' ? r.value : (r.value == null ? '' : String(r.value))
  const adquirenteSettings = {
    nome: (ent.fecho_entidade_nome || '').trim(),
    nif: (ent.fecho_entidade_nif || '').trim(),
    morada: (ent.fecho_entidade_morada || '').trim(),
    tipo: (ent.fecho_entidade_tipo || 'individual').trim(),
    retencao: '',
  }
  function adquirenteDe(rpc) {
    const a = rpc ?? {}
    return {
      nome: String(a.nome ?? '').trim() || adquirenteSettings.nome,
      nif: String(a.nif ?? '').trim() || adquirenteSettings.nif,
      morada: String(a.morada ?? '').trim() || adquirenteSettings.morada,
      tipo: String(a.tipo ?? '').trim() || adquirenteSettings.tipo,
      retencao: String(a.retencao ?? '').trim(),
    }
  }

  async function destinoValido(email) {
    let to = email && !enderecoMorto(email) ? String(email).trim() : null
    if (!to) return { to: null, estado: 'skipped', erro: email ? 'endereço que não recebe correio (' + email + ')' : 'sem email' }
    try {
      const { data: isDemo } = await supabase.rpc('is_demo_email', { p_email: to })
      if (isDemo === true) return { to: null, estado: 'skipped', erro: 'conta de demonstração — sem extrato' }
    } catch (e) { console.error('[monthly-statement] is_demo_email:', e) }
    if (!emailsEnabled && to.toLowerCase() !== ADMIN_EMAIL) {
      return { to, estado: 'aguarda_dominio', erro: 'envio de emails desligado em platform_settings' }
    }
    return { to, estado: null, erro: null }
  }

  const resultados = []
  if (fazerLojas) {
    const { data: destinatarios, error: recErr } = await supabase
      .rpc('monthly_statement_recipients', { p_year: ano, p_month: mes })
    if (recErr) return json({ ok: false, error: 'recipients_failed', detail: recErr.message }, 500)

    const lista = (destinatarios ?? []).filter((d) => !partnerId || d.partner_id === partnerId)
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
      let to = null

      if (extErr) {
        erro = 'extrato falhou: ' + extErr.message
      } else {
        const v = await destinoValido(d.email)
        to = v.to
        if (v.estado) { estado = v.estado; erro = v.erro } else {
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
  }

  // ── Estafetas: resumo do recibo verde do mês ───────────────────────────
  const estafetas = []
  let adquirente = adquirenteSettings
  if (fazerEstafetas) {
    const { data: resumo, error: rErr } = await supabase
      .rpc('driver_monthly_invoice_summary', { p_year: ano, p_month: mes })
    if (rErr) {
      estafetas.push({ erro: 'resumo falhou: ' + rErr.message })
    } else {
      adquirente = adquirenteDe(resumo?.adquirente)
      const lista = (resumo?.estafetas ?? []).filter((e) => !driverId || String(e.user_id) === driverId)
      for (const e of lista) {
        const uid = String(e.user_id)
        const { data: logRow } = await supabase.from('driver_monthly_statement_log').select('*')
          .eq('user_id', uid).eq('ano', ano).eq('mes', mes).maybeSingle()
        if (logRow?.email_status === 'sent' && !force) {
          estafetas.push({ user_id: uid, nome: e.nome, estado: 'ja_enviado' })
          continue
        }
        let estado = 'failed'
        let erro = null
        const { data: email } = await supabase.rpc('driver_monthly_statement_email', { p_user_id: uid })
        // v3: o próprio Danilo (conta admin) a fazer entregas não passa recibo a si mesmo — é o
        // adquirente; os ganhos dele são rendimento próprio. Fica registado, sem email.
        if (e.proprio_adquirente === true || String(email ?? '').trim().toLowerCase() === ADMIN_EMAIL) {
          await supabase.from('driver_monthly_statement_log').upsert({
            user_id: uid, ano, mes, email_to: null, email_status: 'skipped',
            email_error: 'conta do próprio Danilo (adquirente): sem recibo a si mesmo',
            sent_at: logRow?.sent_at ?? null, updated_at: new Date().toISOString(),
          }, { onConflict: 'user_id,ano,mes' })
          estafetas.push({ user_id: uid, nome: e.nome, estado: 'skipped', erro: 'conta do próprio Danilo' })
          continue
        }
        const v = await destinoValido(email)
        const to = v.to
        if (v.estado) { estado = v.estado; erro = v.erro } else {
          const res = await sendResend(resendKey, to,
            'O seu recibo verde de ' + resumo.nome_mes + ' de ' + ano + ' · Bora',
            htmlEstafeta(e, resumo.nome_mes, adquirenteDe({ nome: e.cliente, nif: e.cliente_nif, morada: e.cliente_morada, tipo: e.cliente_tipo, retencao: e.retencao }), 'entregas'))
          estado = res.ok ? 'sent' : 'failed'
          erro = res.ok ? null : res.error
        }
        await supabase.from('driver_monthly_statement_log').upsert({
          user_id: uid, ano, mes, email_to: to, email_status: estado, email_error: erro,
          sent_at: estado === 'sent' ? new Date().toISOString() : (logRow?.sent_at ?? null),
          updated_at: new Date().toISOString(),
        }, { onConflict: 'user_id,ano,mes' })
        estafetas.push({ user_id: uid, nome: e.nome, email: to, estado, erro })
      }
    }
  }

  // ── Limpeza (v3): a profissional recebe o extrato do mês com os dados do recibo ────────
  // Lê a RPC fecho_mensal_prestadores (limpeza = cleaning_bookings completed/done do mês).
  // Idempotente em cleaner_monthly_statement_log (cleaner_id, ano, mes).
  const limpeza = []
  if (fazerEstafetas) {
    const { data: prest, error: pErr } = await supabase
      .rpc('fecho_mensal_prestadores', { p_year: ano, p_month: mes })
    if (pErr) {
      limpeza.push({ erro: 'fecho_mensal_prestadores falhou: ' + pErr.message })
    } else {
      const adqLimp = adquirenteDe(prest?.adquirente)
      const nomeMes = prest?.periodo?.nome ?? ''
      for (const c of (prest?.limpeza ?? [])) {
        const cid = String(c.cleaner_id)
        const { data: logRow } = await supabase.from('cleaner_monthly_statement_log').select('*')
          .eq('cleaner_id', cid).eq('ano', ano).eq('mes', mes).maybeSingle()
        if (logRow?.email_status === 'sent' && !force) {
          limpeza.push({ cleaner_id: cid, nome: c.nome, estado: 'ja_enviado' })
          continue
        }
        let estado = 'failed'
        let erro = null
        const v = await destinoValido(c.email)
        const to = v.to
        if (v.estado) { estado = v.estado; erro = v.erro } else {
          const e = { nome: c.nome, ano, entregas: c.servicos, total_a_faturar: c.ganho, nif: c.nif, atividade_aberta: true }
          const res = await sendResend(resendKey, to,
            'O seu recibo verde de ' + nomeMes + ' de ' + ano + ' · Bora',
            htmlEstafeta(e, nomeMes, adqLimp, 'limpezas', c))
          estado = res.ok ? 'sent' : 'failed'
          erro = res.ok ? null : res.error
        }
        await supabase.from('cleaner_monthly_statement_log').upsert({
          cleaner_id: cid, ano, mes, email_to: to, email_status: estado, email_error: erro,
          sent_at: estado === 'sent' ? new Date().toISOString() : (logRow?.sent_at ?? null),
          updated_at: new Date().toISOString(),
        }, { onConflict: 'cleaner_id,ano,mes' })
        limpeza.push({ cleaner_id: cid, nome: c.nome, email: to, estado, erro })
      }
    }
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
        htmlAdmin(fecho, resultados, estafetas.concat(limpeza)))
      admin = res
    }
  }

  return json({
    ok: true, ano, mes, partner_id: partnerId, driver_user_id: driverId, force,
    emails_enabled: emailsEnabled, resend_key_present: !!resendKey,
    extratos: resultados, estafetas, limpeza, estafetas_ativo: fazerEstafetas, admin_summary: admin,
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

// v3: o adquirente (a quem o recibo é passado) vem da RPC do mês, com as settings como recurso.
// `tipo` = 'entregas' | 'limpezas'; `extra` (limpeza) traz o que a cliente pagou e os acertos.
function htmlEstafeta(e, nomeMes, adquirente, tipo, extra) {
  const linha = (a, b, forte) => '<tr><td style="padding:6px 0">' + a + '</td><td style="padding:6px 0;text-align:right' +
    (forte ? ';font-weight:800;color:' + GREEN : '') + '">' + b + '</td></tr>'
  const adq = adquirente ?? {}
  const unidade = tipo === 'limpezas' ? 'limpezas' : 'entregas'
  // v4: o adquirente vem sempre da RPC do mês (nunca "Consumidor final"); IVA e retenção sem regra fixa.
  const nomeAdq = adq.nome || e.cliente || ''
  const nifAdq = adq.nif || e.cliente_nif || ''
  const moradaAdq = adq.morada || ''
  const descricao = 'Serviços prestados em ' + nomeMes + ' de ' + e.ano + ' através da plataforma Bora' +
    (e.entregas ? ' (' + e.entregas + ' ' + unidade + ')' : '')
  const aviso = (!e.nif || !e.atividade_aberta)
    ? '<p style="background:#FFF7ED;border:1px solid #FED7AA;border-radius:8px;padding:10px;font-size:13px">' +
      'Ainda falta confirmar na app o seu NIF e que tem atividade aberta nas Finanças. Sem atividade aberta não consegue passar o recibo, e sem recibo não pode continuar a trabalhar pela Bora.</p>'
    : ''
  let detalhe = ''
  if (tipo === 'limpezas' && extra) {
    const acertos = (extra.acertos ?? []).map((a) =>
      '<tr><td style="padding:4px 0">Semana de ' + esc(a.semana) + '</td><td style="padding:4px 0;text-align:right">' +
      (a.direcao === 'cleaner_to_bora' ? 'pagou à Bora ' : 'a Bora pagou-lhe ') + eur(Math.abs(Number(a.valor ?? 0))) +
      ' · ' + esc(estadoAcerto(a.estado)) + '</td></tr>').join('')
    detalhe = '<table style="width:100%;border-collapse:collapse;font-size:13px;margin-bottom:12px">' +
      linha('Os clientes pagaram', eur(extra.pago_pelos_clientes)) +
      linha('Em dinheiro (ficou consigo)', eur(extra.em_dinheiro)) +
      linha('Por MB Way/cartão (a Bora recebeu e pagou-lhe)', eur(extra.por_mbway_cartao)) +
      linha('Taxa da Bora', eur(extra.taxa_bora)) +
      (acertos || '') + '</table>'
  }
  return META + '<div style="font-family:system-ui,Arial,sans-serif;max-width:620px;margin:auto">' +
    '<div style="background:' + GREEN + ';color:#fff;padding:18px 20px;border-radius:12px 12px 0 0">' +
    '<div style="font-size:20px;font-weight:800">Bora</div>' +
    '<div style="opacity:.9">O seu recibo verde de ' + esc(nomeMes) + ' de ' + e.ano + '</div></div>' +
    '<div style="border:1px solid #eee;border-top:0;border-radius:0 0 12px 12px;padding:20px">' +
    '<p style="margin:0 0 12px">Olá <b>' + esc(e.nome) + '</b>, em ' + esc(nomeMes) + ' fez <b>' + esc(e.entregas ?? 0) + '</b> ' + unidade + ' pela Bora e ganhou <b>' + eur(e.total_a_faturar) + '</b>. ' +
    'Cada um fatura a sua parte: passe a fatura-recibo (recibo verde) do que ganhou no Portal das Finanças com estes dados:</p>' +
    '<table style="width:100%;border-collapse:collapse;font-size:14px;margin-bottom:12px">' +
    linha('Valor', eur(e.total_a_faturar), true) +
    (nomeAdq ? linha('Passar a (adquirente)', esc(nomeAdq)) : '') +
    (nifAdq ? linha('NIF do adquirente', esc(nifAdq)) : '') +
    (moradaAdq ? linha('Morada do adquirente', esc(moradaAdq)) : '') +
    linha('IVA e retenção de IRS', 'Dependem do seu regime nas Finanças (há quem seja isento de IVA e quem não seja); o contabilista da Bora confirma consigo.') +
    '</table>' +
    detalhe +
    '<p style="font-size:13px;color:#555;margin:0 0 4px">Descrição para copiar:</p>' +
    '<p style="background:#F3F4F6;border-radius:8px;padding:10px;font-size:14px;margin:0 0 14px">' + esc(descricao) + '</p>' +
    aviso +
    '<p style="font-size:13px">Prazo: a fatura-recibo passa-se até ao 5.º dia útil depois de receber o dinheiro. ' +
    (tipo === 'limpezas' ? 'Depois responda a este email com o PDF do recibo.' : 'Depois carregue em <b>"Já passei o recibo"</b> na app, em Ganhos.') +
    ' Se tiver dúvidas, responda a este email.</p>' +
    '<p style="font-size:11px;color:#999;margin-top:12px">Bora App · resumo mensal automático</p></div></div>'
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
    '<tr><td>Parte da Bora</td><td style="text-align:right;color:#B45309">−' + eur(t.comissao) + '</td></tr>' +
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
    '<p style="font-size:12px;color:#777;margin-top:18px">A loja fatura o balcão aos clientes como sempre. A parte da Bora é faturada pela Bora diretamente aos clientes: a loja não recebe fatura da Bora nem passa fatura à Bora.</p>' +
    '<p style="font-size:12px;color:#777;margin-top:8px">Também pode ver e descarregar este extrato na app, em Ganhos → Este mês.</p>' +
    '<p style="font-size:11px;color:#999;margin-top:12px">Bora App · extrato mensal automático</p></div></div>'
}

function htmlAdmin(f, resultados, estafetas) {
  const t = f.totais ?? {}
  const fin = f.para_as_financas ?? {}
  const fat = (fin.faturas_recibo ?? []).map((x) =>
    '<li><b>' + esc(x.destinatario) + '</b>' + (x.nif ? ' (NIF ' + esc(x.nif) + ')' : (x.falta_nif ? ' <span style="color:#B45309">(falta NIF)</span>' : '')) +
    ' — ' + eur(x.valor) + ' · ' + esc(x.descricao) + '</li>').join('')
  const prej = (f.pedidos_no_prejuizo ?? []).map((p) =>
    '<li>' + esc(p.data) + ' ' + esc(p.loja) + ': ' + eur(p.resultado) + ' — ' + esc(p.motivo) + '</li>').join('')
  const ext = (resultados ?? []).map((r) =>
    '<li>' + esc(r.nome) + ': ' + esc(r.estado) + (r.erro ? ' — ' + esc(r.erro) : '') + '</li>').join('')
  const est = (estafetas ?? []).map((r) =>
    '<li>' + esc(r.nome) + ': ' + esc(r.estado) + (r.erro ? ' — ' + esc(r.erro) : '') + '</li>').join('')
  return META + '<div style="font-family:system-ui,Arial,sans-serif;max-width:640px;margin:auto">' +
    '<h2 style="color:' + GREEN + '">Fecho de ' + esc(f.periodo.nome) + ' ' + f.periodo.ano + '</h2>' +
    '<p>Pedidos entregues: <b>' + t.pedidos_entregues + '</b> · Pago pelos clientes: <b>' + eur(t.pago_pelos_clientes) + '</b><br>' +
    'Mercadoria: ' + eur(t.custo_mercadoria) + ' · Receita própria: <b>' + eur(t.receita_propria_bora) + '</b><br>' +
    'Estafetas: ' + eur(t.pago_a_estafetas) + ' · Lucro: <b>' + eur(t.lucro) + '</b><br>' +
    'Limpezas: ' + eur((f.limpeza_totais ?? {}).pago_pelos_clientes) + ' · Taxa Bora limpezas: <b>' + eur(fin.receita_limpeza) + '</b></p>' +
    '<h3>Para o contabilista</h3><p style="line-height:1.5">' + esc(fin.texto) + '</p>' +
    '<p>Receita própria da Bora: <b>' + eur(fin.total_a_declarar) + '</b></p>' +
    '<h3>Faturação da parte da Bora (emitida pelo escritório do contabilista)</h3><ul>' + fat + '</ul>' +
    (prej ? '<h3 style="color:#B45309">Pedidos no prejuízo</h3><ul>' + prej + '</ul>' : '') +
    (ext ? '<h3>Extratos às lojas</h3><ul>' + ext + '</ul>' : '') +
    (est ? '<h3>Resumos do mês aos prestadores (estafetas e limpeza)</h3><ul>' + est + '</ul>' : '') +
    '<p style="font-size:11px;color:#999">Bora App · fecho mensal · detalhe em /admin/fecho-mensal</p></div>'
}

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
//
// v5 (15/11/2026, missão recibos-verdes-15-11, R1b; base = v14 no ar, igual ao v4 do repo). Desde
// novembro/2026 quem paga é a sociedade e o contabilista (Hugo, 15/11) pediu UM recibo verde por
// pessoa por mês. Por isso:
//  - UM email por PESSOA (user_id) com tudo o que fez no mês (entregas + limpezas + lavagens + Casa),
//    lido da RPC prestador_recibo_mensal_resumo (fonte única: app, painel, aviso do dia 10, trava).
//    Os dois envios separados de antes (estafetas por driver_monthly_invoice_summary e limpeza por
//    fecho_mensal_prestadores) saíram: a Mayra, que é estafeta e limpadora, recebia dois.
//  - O email leva o total e as linhas por serviço, os dados da empresa para copiar, a descrição, o prazo,
//    a retenção (só texto, da função), o IVA, "anexe o recibo na app, em Ganhos" e o aviso da trava.
//    Antes de novembro/2026 (Danilo em nome individual) fica como na v4: IVA e retenção sem regra fixa.
//  - Nunca duas vezes à mesma pessoa: driver_monthly_statement_log (user_id, ano, mes) é o registo da
//    pessoa; um envio antigo à limpeza (cleaner_monthly_statement_log) também conta, e o envio novo fica
//    espelhado lá (se a v4 voltar por rollback, não repete). Só force:true reenvia.
//  - A conta do dono fica de fora enquanto fecho_dono_passa_recibo = false (a função decide).
//  - { user_id } (ou { driver_user_id }) = só esta pessoa; um admin com sessão também pode chamar (botão
//    "Reenviar" de uma pessoa no painel /admin/fecho-mensal). Antes, o reenvio de um estafeta com
//    force:true reenviava também a TODAS as limpadoras (o laço da limpeza não olhava para o filtro).
// Precisa do SQL R1a aplicado (prestador_recibo_mensal_resumo); sem ele, os prestadores não recebem e o
// erro aparece no resumo ao admin e na resposta.

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'
import { secretKey } from '../_shared/keys.ts'
import { exigirServidorOuAdmin, respostaAoPing } from '../_shared/chaves.ts'
import { assuntoPrestador, htmlPrestador, jaEnviadoAPessoa, separarPessoas, textoPrestador } from './logica.ts'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
}

const ADMIN_EMAIL = 'boraappbora@gmail.com'
const EMAIL_FROM = 'Bora App <fecho@boraguarda.com>'
const META = '<meta charset="utf-8">'
const GREEN = '#16A34A'
// Primeiro mês em que os prestadores passam recibo (modelo novo a 01/10/2026; à sociedade desde 11/2026).
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
  // v5: ou um admin com sessão (reenvio de uma pessoa a partir do painel). Resto: 403 como antes.
  const bloqueio = await exigirServidorOuAdmin(req, corsHeaders)
  if (bloqueio) return bloqueio
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
  // v5: uma pessoa só (qualquer prestador). driver_user_id fica como nome antigo do mesmo filtro.
  const pessoaId = b?.user_id ? String(b.user_id) : (b?.driver_user_id ? String(b.driver_user_id) : null)
  const force = b?.force === true
  const adminSummary = b?.admin_summary !== undefined ? b.admin_summary === true : (!partnerId && !pessoaId)
  const fazerLojas = !pessoaId
  const fazerPrestadores = !partnerId && (ano * 12 + mes) >= ESTAFETA_DESDE

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

  // v5: o adquirente (a quem o prestador passa o recibo) vem da RPC prestador_recibo_mensal_resumo,
  // que já decide individual (até 10/2026, com as settings fecho_entidade_*) ou sociedade (desde 11/2026).

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

  // ── Prestadores (v5): UM email por PESSOA com o recibo verde do mês ───────────────────
  // Fonte única: RPC prestador_recibo_mensal_resumo (entregas + limpezas + lavagens + Casa, por user_id).
  const prestadores = []
  if (fazerPrestadores) {
    const { data: resumo, error: rErr } = await supabase
      .rpc('prestador_recibo_mensal_resumo', { p_year: ano, p_month: mes })
    if (rErr) {
      prestadores.push({ erro: 'resumo falhou: ' + rErr.message })
    } else {
      const { enviar, saltar } = separarPessoas(resumo?.prestadores, pessoaId)

      // Conta do dono (enquanto fecho_dono_passa_recibo = false) e contas demo: ficam registadas, sem email.
      for (const s of saltar) {
        const uid = String(s.prestador.user_id)
        const { data: logRow } = await supabase.from('driver_monthly_statement_log').select('email_status,sent_at')
          .eq('user_id', uid).eq('ano', ano).eq('mes', mes).maybeSingle()
        if (logRow?.email_status === 'sent') {
          prestadores.push({ user_id: uid, nome: s.prestador.nome, estado: 'ja_enviado' })
          continue
        }
        await supabase.from('driver_monthly_statement_log').upsert({
          user_id: uid, ano, mes, email_to: null, email_status: 'skipped', email_error: s.erro,
          sent_at: logRow?.sent_at ?? null, updated_at: new Date().toISOString(),
        }, { onConflict: 'user_id,ano,mes' })
        prestadores.push({ user_id: uid, nome: s.prestador.nome, estado: 'skipped', erro: s.erro })
      }

      for (const p of enviar) {
        const uid = String(p.user_id)
        // Nunca duas vezes à mesma pessoa: o registo dela (por user_id) e o registo antigo da limpeza.
        const { data: logRow } = await supabase.from('driver_monthly_statement_log').select('*')
          .eq('user_id', uid).eq('ano', ano).eq('mes', mes).maybeSingle()
        const { data: fichasLimpeza } = await supabase.from('cleaners').select('id').eq('user_id', uid)
        const cleanerIds = (fichasLimpeza ?? []).map((c) => String(c.id))
        let logsLimpeza = []
        if (cleanerIds.length) {
          const { data: ll } = await supabase.from('cleaner_monthly_statement_log').select('cleaner_id,email_status')
            .in('cleaner_id', cleanerIds).eq('ano', ano).eq('mes', mes)
          logsLimpeza = ll ?? []
        }
        if (jaEnviadoAPessoa(logRow, logsLimpeza, force)) {
          prestadores.push({ user_id: uid, nome: p.nome, estado: 'ja_enviado' })
          continue
        }

        let estado = 'failed'
        let erro = null
        // O endereço de contacto do estafeta (drivers.email) manda; senão o do login.
        const { data: emailContacto } = await supabase.rpc('driver_monthly_statement_email', { p_user_id: uid })
        const v = await destinoValido(String(emailContacto ?? '').trim() || p.email)
        const to = v.to
        if (v.estado) { estado = v.estado; erro = v.erro } else {
          const res = await sendResend(resendKey, to, assuntoPrestador(resumo),
            htmlPrestador(p, resumo), textoPrestador(p, resumo))
          estado = res.ok ? 'sent' : 'failed'
          erro = res.ok ? null : res.error
        }
        const agoraIso = new Date().toISOString()
        await supabase.from('driver_monthly_statement_log').upsert({
          user_id: uid, ano, mes, email_to: to, email_status: estado, email_error: erro,
          sent_at: estado === 'sent' ? agoraIso : (logRow?.sent_at ?? null),
          updated_at: agoraIso,
        }, { onConflict: 'user_id,ano,mes' })
        // Espelho no registo antigo da limpeza (só quando saiu e a pessoa fez limpezas): se a v4 voltar
        // por rollback, também não manda outra vez.
        if (estado === 'sent' && (p.linhas ?? []).some((l) => l?.servico === 'limpeza')) {
          for (const cid of cleanerIds) {
            await supabase.from('cleaner_monthly_statement_log').upsert({
              cleaner_id: cid, ano, mes, email_to: to, email_status: 'sent', email_error: null,
              sent_at: agoraIso, updated_at: agoraIso,
            }, { onConflict: 'cleaner_id,ano,mes' })
          }
        }
        prestadores.push({
          user_id: uid, nome: p.nome, email: to, estado, erro, total: p.total,
          servicos: (p.linhas ?? []).map((l) => l?.servico),
        })
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
        htmlAdmin(fecho, resultados, prestadores))
      admin = res
    }
  }

  // v5: `prestadores` é a lista nova (uma linha por pessoa); `estafetas`/`limpeza` ficam pelo formato antigo.
  return json({
    ok: true, ano, mes, partner_id: partnerId, user_id: pessoaId, driver_user_id: pessoaId, force,
    emails_enabled: emailsEnabled, resend_key_present: !!resendKey,
    extratos: resultados, prestadores, estafetas: prestadores, limpeza: [], estafetas_ativo: fazerPrestadores,
    admin_summary: admin,
  })
})

// v5: `text` (opcional) vai como parte text/plain.
async function sendResend(key, to, subject, html, text = null) {
  if (!key) return { ok: false, error: 'RESEND_API_KEY em falta' }
  try {
    const res = await fetch('https://api.resend.com/emails', {
      method: 'POST',
      headers: { 'Authorization': 'Bearer ' + key, 'Content-Type': 'application/json' },
      body: JSON.stringify({ from: EMAIL_FROM, to: [to], subject, html, ...(text ? { text } : {}) }),
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

// v5: o email ao prestador (htmlPrestador / textoPrestador) está em ./logica.ts, com testes.

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

function htmlAdmin(f, resultados, prestadores) {
  const t = f.totais ?? {}
  const fin = f.para_as_financas ?? {}
  const fat = (fin.faturas_recibo ?? []).map((x) =>
    '<li><b>' + esc(x.destinatario) + '</b>' + (x.nif ? ' (NIF ' + esc(x.nif) + ')' : (x.falta_nif ? ' <span style="color:#B45309">(falta NIF)</span>' : '')) +
    ' — ' + eur(x.valor) + ' · ' + esc(x.descricao) + '</li>').join('')
  const prej = (f.pedidos_no_prejuizo ?? []).map((p) =>
    '<li>' + esc(p.data) + ' ' + esc(p.loja) + ': ' + eur(p.resultado) + ' — ' + esc(p.motivo) + '</li>').join('')
  const ext = (resultados ?? []).map((r) =>
    '<li>' + esc(r.nome) + ': ' + esc(r.estado) + (r.erro ? ' — ' + esc(r.erro) : '') + '</li>').join('')
  const est = (prestadores ?? []).map((r) =>
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
    (est ? '<h3>Recibo verde do mês aos prestadores (um email por pessoa)</h3><ul>' + est + '</ul>' : '') +
    '<p style="font-size:11px;color:#999">Bora App · fecho mensal · detalhe em /admin/fecho-mensal</p></div>'
}

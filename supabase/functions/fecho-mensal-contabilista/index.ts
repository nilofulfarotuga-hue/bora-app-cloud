// @ts-nocheck
// supabase/functions/fecho-mensal-contabilista/index.ts — v1 (01/11/2026, missão contabilista-2026-11-01)
// Publicada e agendada a 01/11/2026 (cron 125 'fecho-mensal-contabilista', 07 e 08 UTC do dia 1).
// Migração: supabase/migrations/20261101215000_fecho_mensal_contabilista_2026_11_01.sql.
//
// O QUE FAZ: no dia 1 de cada mês às 08:00 de Lisboa (cron 'fecho-mensal-contabilista', 07 e 08 UTC;
// a função só age quando em Lisboa for dia 1 às 08h) fecha o mês anterior para o contabilista:
//   1) manda a Edge stripe-relatorio-contabilista actualizar o extrato da Stripe (chamarFuncao);
//   2) lê as RPCs admin_monthly_closeout (comissões/taxas por tipo), fecho_mensal_prestadores
//      (extrato por prestador com os dados do recibo verde) e stripe_extrato_resumo (lista Stripe do mês);
//   3) monta UM email (PT-PT, simples) e manda-o ao contabilista com cópia ao Danilo, por Resend,
//      do mesmo remetente dos fechos (fecho@boraguarda.com);
//   4) regista em fecho_mensal_contabilista_log (ano, mes) — idempotente: não repete sem force:true.
// Primeiro disparo previsto: 01/12/2026 (fecha novembro/2026).
//
// GATES (platform_settings): fecho_contabilista_ativo=true e weekly_digest_emails_enabled=true (o mesmo
// portão dos outros fechos). Sem fecho_contabilista_email o fecho vai SÓ ao Danilo, com aviso
// "falta email do contabilista" no assunto, no corpo e no log.
// NÃO calcula dinheiro: só lê. Regra do Danilo: o TVDE de passageiros aparece como informativo, fora
// da declaração; a mercadoria das lojas não é receita da Bora.
//
// Corpo aceite: { year, month } (por defeito o mês anterior em Lisboa) · { force: true } · { cron: true } · { ping: true }

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'
import { secretKey } from '../_shared/keys.ts'
import { exigirServidor, respostaAoPing } from '../_shared/chaves.ts'
import { chamarFuncao } from '../_shared/chamadas.ts'
import { corsHeaders } from '../_shared/cors.ts'

const ADMIN_EMAIL = 'boraappbora@gmail.com'
const EMAIL_FROM = 'Bora App <fecho@boraguarda.com>'
const META = '<meta charset="utf-8">'
const GREEN = '#16A34A'

function eur(v) { return (Number(v ?? 0)).toFixed(2).replace('.', ',') + ' €' }
function esc(s) {
  return String(s ?? '').replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;').replace(/'/g, '&#39;')
}
function json(body, status = 200) {
  return new Response(JSON.stringify(body), { status, headers: { ...corsHeaders, 'Content-Type': 'application/json' } })
}
function agoraLisboa() {
  const p = new Intl.DateTimeFormat('en-GB', {
    timeZone: 'Europe/Lisbon', year: 'numeric', month: '2-digit', day: '2-digit', hour: '2-digit', hour12: false,
  }).formatToParts(new Date())
  const g = (t) => Number(p.find((x) => x.type === t)?.value)
  return { ano: g('year'), mes: g('month'), dia: g('day'), hora: g('hour') % 24 }
}
const NOMES = ['', 'janeiro', 'fevereiro', 'março', 'abril', 'maio', 'junho', 'julho', 'agosto', 'setembro', 'outubro', 'novembro', 'dezembro']

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders })
  const bloqueio = await exigirServidor(req, corsHeaders)
  if (bloqueio) return bloqueio
  const pong = await respostaAoPing(req, corsHeaders)
  if (pong) return pong

  let b = {}
  try { b = await req.json() } catch (_e) {}
  const agora = agoraLisboa()
  if (b?.cron === true && !(agora.dia === 1 && agora.hora === 8)) {
    return json({ ok: true, skipped: 'fora da hora (só dia 1 às 08h de Lisboa)', agora })
  }
  let ano = Number(b?.year) || null
  let mes = Number(b?.month) || null
  if (!ano || !mes) {
    ano = agora.mes === 1 ? agora.ano - 1 : agora.ano
    mes = agora.mes === 1 ? 12 : agora.mes - 1
  }
  const force = b?.force === true
  const mesTxt = `${ano}-${String(mes).padStart(2, '0')}`

  const supabase = createClient(Deno.env.get('SUPABASE_URL'), secretKey())

  // ── settings / portões ─────────────────────────────────────────────────
  const { data: st } = await supabase.from('platform_settings').select('key,value')
    .in('key', ['fecho_contabilista_ativo', 'fecho_contabilista_email', 'fecho_contabilista_nome',
      'weekly_digest_emails_enabled', 'fecho_entidade_nome', 'fecho_entidade_nif', 'fecho_entidade_tipo'])
  const s = {}
  for (const r of (st ?? [])) s[r.key] = r.value
  const ativo = s.fecho_contabilista_ativo === true || s.fecho_contabilista_ativo === 'true'
  const emailsEnabled = s.weekly_digest_emails_enabled === true || s.weekly_digest_emails_enabled === 'true'
  const toHugo = String(s.fecho_contabilista_email ?? '').trim()
  const nomeHugo = String(s.fecho_contabilista_nome ?? 'contabilista').trim()

  const { data: logRow } = await supabase.from('fecho_mensal_contabilista_log').select('*')
    .eq('ano', ano).eq('mes', mes).maybeSingle()
  if (logRow?.email_status === 'sent' && !force) {
    return json({ ok: true, ano, mes, estado: 'ja_enviado', sent_at: logRow.sent_at })
  }

  // ── 1) actualiza o extrato da Stripe (não trava se falhar: usa o que já está guardado) ──
  const stripeRefresh = await chamarFuncao(supabase, 'fecho-mensal-contabilista', 'stripe-relatorio-contabilista',
    { desde: mesTxt, ate: mesTxt, guardar: true }) // duas contas: actualiza as duas; o resumo abaixo filtra

  // Duas contas Stripe (missão stripe-empresa-2026-11-01): a sociedade (Hugo) só leva a EMPRESA; o TVDE
  // (conta pessoal) nunca entra aqui. Se a RPC ainda não aceitar p_conta (proposta SQL por aplicar),
  // volta a chamar sem conta e marca o relatório como 'contas juntas'.
  async function resumoStripeEmpresa() {
    let r = await supabase.rpc('stripe_extrato_resumo', { p_desde: mesTxt, p_ate: mesTxt, p_conta: 'empresa' })
    if (r.error && /p_conta|does not exist|No function matches/i.test(r.error.message)) {
      console.warn('[fecho-mensal] stripe_extrato_resumo sem p_conta ainda; contas juntas')
      r = await supabase.rpc('stripe_extrato_resumo', { p_desde: mesTxt, p_ate: mesTxt })
      if (r.data && typeof r.data === 'object') r.data.conta = 'juntas'
    }
    return r
  }

  // ── 2) lê tudo ───────────────────────────────────────────────────────
  const [{ data: fecho, error: e1 }, { data: prest, error: e2 }, { data: stripeRes, error: e3 }] = await Promise.all([
    supabase.rpc('admin_monthly_closeout', { p_year: ano, p_month: mes }),
    supabase.rpc('fecho_mensal_prestadores', { p_year: ano, p_month: mes }),
    resumoStripeEmpresa(),
  ])
  const erros = [e1, e2, e3].filter(Boolean).map((e) => e.message)
  if (erros.length) {
    await supabase.from('fecho_mensal_contabilista_log').upsert({
      ano, mes, email_status: 'failed', email_error: 'leitura: ' + erros.join(' · '), updated_at: new Date().toISOString(),
    }, { onConflict: 'ano,mes' })
    return json({ ok: false, error: 'leitura_falhou', detalhe: erros }, 500)
  }

  const resumo = montarResumo(ano, mes, fecho, prest, stripeRes)
  const html = htmlContabilista(resumo, nomeHugo)
  const assunto = `Bora — fecho de ${NOMES[mes]} de ${ano} (comissões, prestadores e Stripe)`

  // ── 3) envia (ou explica porque não) ─────────────────────────────────
  // Sem email do contabilista: vai só ao Danilo, com aviso no assunto e no log ("falta email do
  // contabilista"); o Danilo reencaminha. Com email: ao contabilista com cópia ao Danilo.
  let estado = 'skipped'; let erro = null; let resendId = null
  const faltaEmail = !toHugo
  const destinatarios = faltaEmail ? [ADMIN_EMAIL] : [toHugo]
  const copias = faltaEmail ? [] : [ADMIN_EMAIL]
  const assuntoFinal = faltaEmail ? assunto + ' — FALTA EMAIL DO CONTABILISTA (reencaminhar)' : assunto
  const htmlFinal = faltaEmail
    ? html.replace('<p>' + esc(nomeHugo) + ',', '<p style="background:#FFF7ED;border:1px solid #FED7AA;border-radius:8px;padding:10px">Falta o email do contabilista em platform_settings (fecho_contabilista_email): este fecho veio só para o Danilo. Reencaminhe ao ' + esc(nomeHugo) + ' e grave o email no painel.</p><p>' + esc(nomeHugo) + ',')
    : html
  if (!ativo) erro = 'fecho_contabilista_ativo=false'
  else if (!emailsEnabled) erro = 'weekly_digest_emails_enabled=false'
  else {
    let resendKey = Deno.env.get('RESEND_API_KEY') ?? null
    if (!resendKey) {
      try { const { data } = await supabase.rpc('get_resend_key'); if (data) resendKey = String(data).trim() } catch (_e) {}
    }
    const r = await sendResend(resendKey, destinatarios, copias, assuntoFinal, htmlFinal)
    estado = r.ok ? 'sent' : 'failed'; resendId = r.id
    erro = r.ok ? (faltaEmail ? 'falta email do contabilista: enviado só ao Danilo' : null) : r.error
  }

  await supabase.from('fecho_mensal_contabilista_log').upsert({
    ano, mes, email_to: destinatarios.join(','), email_cc: copias.join(',') || null, email_status: estado, email_error: erro,
    resend_id: resendId, resumo, sent_at: estado === 'sent' ? new Date().toISOString() : (logRow?.sent_at ?? null),
    updated_at: new Date().toISOString(),
  }, { onConflict: 'ano,mes' })

  try {
    await supabase.from('e2e_log').insert({
      fluxo: 'fecho-mensal-contabilista', passo: mesTxt, estado: estado === 'failed' ? 'erro' : 'ok',
      detalhe: `estado=${estado}${erro ? ' · ' + erro : ''} · para=${destinatarios.join(',')} cc=${copias.join(',') || '-'} · stripe_refresh=${stripeRefresh.ok}`.slice(0, 1000),
      device: 'edge',
    })
  } catch (_e) {}

  return json({ ok: estado !== 'failed', ano, mes, estado, erro, para: destinatarios, cc: copias, falta_email_contabilista: faltaEmail, stripe_refresh: stripeRefresh.ok, resumo })
})

function montarResumo(ano, mes, fecho, prest, stripeRes) {
  const t = fecho?.totais ?? {}
  const rub = fecho?.para_as_financas?.rubricas ?? {}
  const serv = fecho?.servicos_totais ?? {}
  const limpezaTaxa = (prest?.limpeza ?? []).reduce((a, x) => a + Number(x.taxa_bora ?? 0), 0)
  const limpezaPago = (prest?.limpeza ?? []).reduce((a, x) => a + Number(x.pago_pelos_clientes ?? 0), 0)
  const limpezaGanho = (prest?.limpeza ?? []).reduce((a, x) => a + Number(x.ganho ?? 0), 0)
  const lavTaxa = (prest?.lavagem ?? []).reduce((a, x) => a + Number(x.taxa_bora ?? 0), 0)
  const stripeMes = (stripeRes?.por_mes ?? []).find((m) => m.mes === `${ano}-${String(mes).padStart(2, '0')}`) ?? {}
  return {
    periodo: { ano, mes, nome: NOMES[mes] },
    adquirente: prest?.adquirente ?? {},
    entregas: {
      pedidos: t.pedidos_entregues ?? 0, pago_pelos_clientes: t.pago_pelos_clientes ?? 0,
      mercadoria_das_lojas: t.custo_mercadoria ?? 0, receita_bora: t.receita_propria_bora ?? 0,
      pago_a_estafetas: t.pago_a_estafetas ?? 0, margem: t.lucro ?? 0,
      rubricas: {
        entrega: rub.entrega ?? 0, taxa_servico: rub.taxa_servico ?? 0, sacos: rub.sacos ?? 0,
        taxa_pedido_pequeno: rub.taxa_pedido_pequeno ?? 0, comissao_lojas_parceiras: rub.comissao_lojas_parceiras ?? 0,
        margem_nao_parceiros: rub.margem_nao_parceiros ?? 0, ajustes_descontos: rub.ajustes_descontos ?? 0,
      },
      por_metodo: t.por_metodo ?? {},
    },
    limpeza: { servicos: (prest?.limpeza ?? []).reduce((a, x) => a + Number(x.servicos ?? 0), 0), pago_pelos_clientes: limpezaPago, pago_a_prestadores: limpezaGanho, taxa_bora: limpezaTaxa },
    lavagem: { taxa_bora: lavTaxa },
    reservas: { marcacoes: serv.marcacoes ?? 0, bora_reteve: serv.bora_reteve ?? 0 },
    tvde_outros_motoristas: { nota: 'Fora da declaração da Bora (TVDE de passageiros).', corridas: fecho?.tvde_outros_motoristas?.corridas ?? 0, parte_bora: fecho?.tvde_outros_motoristas?.parte_bora ?? 0 },
    prestadores: { estafetas: prest?.estafetas ?? [], limpeza: prest?.limpeza ?? [], lavagem: prest?.lavagem ?? [], tvde: prest?.tvde_outros_motoristas ?? [] },
    lojas_parceiras: prest?.lojas_parceiras ?? [],
    stripe: { mes: stripeMes, por_tipo: (stripeRes?.por_mes_e_tipo ?? []), notas: stripeRes?.linhas_com_nota ?? [] },
    gerado_em: new Date().toISOString(),
  }
}

function htmlContabilista(r, nomeHugo) {
  const td = 'padding:5px 6px;border-bottom:1px solid #f1f1f1'
  const linha = (a, b, forte) => `<tr><td style="${td}">${a}</td><td style="${td};text-align:right${forte ? ';font-weight:700' : ''}">${b}</td></tr>`
  const e = r.entregas; const rb = e.rubricas; const adq = r.adquirente ?? {}
  const receitaBora = Number(e.receita_bora) + Number(r.limpeza.taxa_bora) + Number(r.lavagem.taxa_bora) + Number(r.reservas.bora_reteve)

  const estafetas = r.prestadores.estafetas.map((x) =>
    `<tr><td style="${td}">${esc(x.nome)}${x.nif ? ' (NIF ' + esc(x.nif) + ')' : ' <span style="color:#B45309">(sem NIF)</span>'}</td>` +
    `<td style="${td}">${x.entregas} entregas</td><td style="${td};text-align:right;font-weight:700">${eur(x.ganho)}</td>` +
    `<td style="${td}">${x.proprio_adquirente ? 'é o próprio adquirente — sem recibo' : 'recibo verde ao adquirente'}</td></tr>`).join('')
  const limpeza = r.prestadores.limpeza.map((x) =>
    `<tr><td style="${td}">${esc(x.nome)}${x.nif ? ' (NIF ' + esc(x.nif) + ')' : ''}</td><td style="${td}">${x.servicos} limpezas · clientes pagaram ${eur(x.pago_pelos_clientes)} (dinheiro ${eur(x.em_dinheiro)}, MB Way/cartão ${eur(x.por_mbway_cartao)})</td>` +
    `<td style="${td};text-align:right;font-weight:700">${eur(x.ganho)}</td><td style="${td}">taxa Bora ${eur(x.taxa_bora)} · recibo verde ao adquirente</td></tr>`).join('')
  const lavagem = r.prestadores.lavagem.map((x) =>
    `<tr><td style="${td}">${esc(x.nome)}</td><td style="${td}">${x.servicos} lavagens</td><td style="${td};text-align:right;font-weight:700">${eur(x.ganho)}</td><td style="${td}">taxa Bora ${eur(x.taxa_bora)}</td></tr>`).join('')
  const tvde = r.prestadores.tvde.map((x) =>
    `<tr><td style="${td}">${esc(x.nome)}</td><td style="${td}">${x.corridas} corridas</td><td style="${td};text-align:right">${eur(x.ganho_motorista)}</td><td style="${td}">parte Bora ${eur(x.parte_bora)} — fora da declaração</td></tr>`).join('')
  const lojas = r.lojas_parceiras.map((x) =>
    `<tr><td style="${td}">${esc(x.nome)}${x.nif ? ' (NIF ' + esc(x.nif) + ')' : ' <span style="color:#B45309">(sem NIF)</span>'}</td><td style="${td}">${x.pedidos} pedidos · vendas ${eur(x.vendas)}</td>` +
    `<td style="${td};text-align:right;font-weight:700">${eur(x.comissao_bora)}</td><td style="${td}">a Bora fatura esta comissão à loja</td></tr>`).join('')
  const stripeTipos = r.stripe.por_tipo.filter((x) => x.categoria !== 'taxa_stripe' && x.categoria !== 'payout').map((x) =>
    linha(esc(x.categoria.replace(/_/g, ' ')) + ` (${x.n})`, `${eur(x.bruto)} bruto · ${eur(x.taxas_stripe)} taxas · ${eur(x.reembolsos)} reembolsos · ${eur(x.liquido)} líquido`)).join('')
  const stripeNotas = r.stripe.notas.map((x) => `<li>${esc(x.dia)} · ${eur(x.valor)} · ${esc(x.cliente ?? '')} — ${esc(x.nota)}</li>`).join('')
  const sm = r.stripe.mes

  return META + `<div style="font-family:system-ui,Arial,sans-serif;max-width:720px;margin:auto;font-size:14px">` +
    `<div style="background:${GREEN};color:#fff;padding:16px 20px;border-radius:12px 12px 0 0"><div style="font-size:20px;font-weight:800">Bora</div>` +
    `<div style="opacity:.9">Fecho de ${esc(r.periodo.nome)} de ${r.periodo.ano} — para a contabilidade</div></div>` +
    `<div style="border:1px solid #eee;border-top:0;border-radius:0 0 12px 12px;padding:20px">` +
    `<p>${esc(nomeHugo)}, segue o fecho de ${esc(r.periodo.nome)} da plataforma Bora, gerado automaticamente no dia 1. ` +
    `A entidade que recebeu e pagou neste mês foi <b>${esc(adq.nome)}</b> (NIF ${esc(adq.nif)}, ${esc(adq.tipo === 'sociedade' ? 'sociedade' : 'nome individual')}).</p>` +

    `<h3 style="margin:16px 0 6px">1. O que a Bora recebeu (receita própria — sem a mercadoria das lojas)</h3>` +
    `<table style="width:100%;border-collapse:collapse">` +
    linha('Entregas e mercados — taxa de entrega', eur(rb.entrega)) +
    linha('Entregas e mercados — taxa de serviço', eur(rb.taxa_servico)) +
    linha('Entregas e mercados — sacos', eur(rb.sacos)) +
    linha('Entregas e mercados — taxa de pedido pequeno', eur(rb.taxa_pedido_pequeno)) +
    linha('Comissões de lojas parceiras', eur(rb.comissao_lojas_parceiras)) +
    linha('Margem sobre compras em lojas não parceiras', eur(rb.margem_nao_parceiros)) +
    linha('Ajustes e descontos', eur(rb.ajustes_descontos)) +
    linha('Subtotal entregas e mercados (' + e.pedidos + ' pedidos)', eur(e.receita_bora), true) +
    linha('Limpeza — taxa da Bora (' + r.limpeza.servicos + ' serviços; clientes pagaram ' + eur(r.limpeza.pago_pelos_clientes) + ')', eur(r.limpeza.taxa_bora)) +
    linha('Lavagem — taxa da Bora', eur(r.lavagem.taxa_bora)) +
    linha('Reservas/marcações — retido pela Bora (' + r.reservas.marcacoes + ')', eur(r.reservas.bora_reteve)) +
    linha('TOTAL receita própria da Bora', eur(receitaBora), true) +
    `</table>` +
    `<p style="font-size:12px;color:#555">Fora desta conta: mercadoria das lojas e mercados ${eur(e.mercadoria_das_lojas)} (pertence às lojas) e o TVDE de passageiros (${r.tvde_outros_motoristas.corridas} corridas de outros motoristas, parte Bora ${eur(r.tvde_outros_motoristas.parte_bora)}) — por regra do Danilo fica fora da declaração da Bora.</p>` +

    `<h3 style="margin:16px 0 6px">2. O que foi pago aos prestadores e como documentam</h3>` +
    `<p style="font-size:13px">Cada prestador passa fatura-recibo (recibo verde) a <b>${esc(adq.nome)}</b>, NIF ${esc(adq.nif)}, ${esc(adq.morada)}. ` +
    `Descrição: "${esc(adq.descricao_sugerida)}". ${esc(adq.iva_prestador)}. ${esc(adq.retencao)}. ${esc(adq.prazo)}.</p>` +
    `<table style="width:100%;border-collapse:collapse">` +
    (estafetas ? `<tr><td colspan="4" style="${td};font-weight:700">Estafetas (entregas) — total ${eur(e.pago_a_estafetas)}</td></tr>` + estafetas : '') +
    (limpeza ? `<tr><td colspan="4" style="${td};font-weight:700">Limpeza — total ${eur(r.limpeza.pago_a_prestadores)}</td></tr>` + limpeza : '') +
    (lavagem ? `<tr><td colspan="4" style="${td};font-weight:700">Lavagem</td></tr>` + lavagem : '') +
    (tvde ? `<tr><td colspan="4" style="${td};font-weight:700">TVDE de outros motoristas (informativo)</td></tr>` + tvde : '') +
    (lojas ? `<tr><td colspan="4" style="${td};font-weight:700">Lojas parceiras — comissão que a Bora lhes fatura</td></tr>` + lojas : '') +
    `</table>` +

    `<h3 style="margin:16px 0 6px">3. Stripe — o que passou pela conta neste mês</h3>` +
    `<table style="width:100%;border-collapse:collapse">` +
    linha('Cobranças (' + (sm.n_cobrancas ?? 0) + ')', eur(sm.bruto)) +
    linha('Taxas da Stripe', eur(sm.taxas_stripe)) +
    linha('Reembolsos (' + (sm.n_reembolsos ?? 0) + ')', eur(sm.reembolsos)) +
    linha('Líquido', eur(sm.liquido), true) +
    linha('Transferido para o banco (' + (sm.n_payouts ?? 0) + ' payouts)', eur(sm.payouts)) +
    `</table>` +
    `<p style="font-size:13px;margin:8px 0 4px">Por tipo:</p><table style="width:100%;border-collapse:collapse">${stripeTipos}</table>` +
    (stripeNotas ? `<p style="font-size:13px;margin:8px 0 4px">Linhas com nota:</p><ul style="font-size:12px">${stripeNotas}</ul>` : '') +
    `<p style="font-size:12px;color:#555">Nota: o valor bruto da Stripe inclui dinheiro das lojas (mercadoria) e dos prestadores que só passou pela Bora; a receita da Bora é a da secção 1.</p>` +

    `<p style="font-size:11px;color:#999;margin-top:16px">Bora App · fecho mensal automático · detalhe no painel /admin/fecho-mensal</p></div></div>`
}

async function sendResend(key, to, cc, subject, html) {
  if (!key) return { ok: false, error: 'RESEND_API_KEY em falta', id: null }
  try {
    const res = await fetch('https://api.resend.com/emails', {
      method: 'POST',
      headers: { 'Authorization': 'Bearer ' + key, 'Content-Type': 'application/json' },
      body: JSON.stringify({ from: EMAIL_FROM, to, ...(cc && cc.length ? { cc } : {}), subject, html }),
    })
    const txt = await res.text().catch(() => '')
    if (res.ok) { let id = null; try { id = JSON.parse(txt)?.id ?? null } catch (_e) {} return { ok: true, error: null, id } }
    return { ok: false, error: 'resend ' + res.status + ': ' + txt.slice(0, 300), id: null }
  } catch (e) {
    return { ok: false, error: 'excecao: ' + String(e).slice(0, 300), id: null }
  }
}

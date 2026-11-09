// @ts-nocheck
// supabase/functions/recibo-pedido-cliente/index.ts — v1 08/11/2026
// Missão m1-dinheiro-favores-2026-11-08 (Bloco 4c). Regra do Danilo 08/11 18:59: "quando fazer
// qualquer pedido, já ir a fatura pro e-mail da pessoa".
//
// Recibo por email ao cliente em TODO o pedido entregue (entrega, mercado, Favor). NÃO é a
// fatura: a fatura do estabelecimento, quando pedida, é emitida pela loja.
// Os números vêm TODOS de public._recibo_pedido (SQL). Esta função só desenha, guarda uma cópia
// em storage (recibos-clientes/AAAA/MM/<order_id>.html) e envia pelo Resend, como o
// tvde-recibo-viagem (mesmo remetente).
//
// Quem chama: só o servidor (gatilho zzzzz_recibo_cliente_on_delivered e admin_recibo_reenviar),
// POST { order_id, force? }. Uma vez por pedido: com o registo em recibos_clientes 'enviado' e
// sem force, não reenvia.

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'
import { chamadaDoServidor } from '../_shared/chaves.ts'
import { secretKey } from '../_shared/keys.ts'

const EMAIL_FROM = 'Bora <recibos@boraguarda.com>'
const VERDE = '#16A34A'
const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders })
  if (!(await chamadaDoServidor(req))) return json({ ok: false, error: 'so_servidor' }, 403)

  let body: any = {}
  try { body = await req.json() } catch (_e) { return json({ ok: false, error: 'json_invalido' }, 400) }
  const orderId = String(body?.order_id ?? '').trim()
  const force = body?.force === true
  if (!orderId) return json({ ok: false, error: 'order_id_em_falta' }, 400)

  const admin = createClient(Deno.env.get('SUPABASE_URL')!, secretKey()!)
  const { data: ja } = await admin.from('recibos_clientes').select('estado, tentativas').eq('order_id', orderId).maybeSingle()
  if (ja?.estado === 'enviado' && !force) return json({ ok: true, ja_enviado: true })
  const tentativas = Number(ja?.tentativas ?? 0) + 1

  const fim = async (estado: string, detalhe: string, extra: Record<string, unknown> = {}) => {
    await admin.from('recibos_clientes').upsert({
      order_id: orderId, estado, detalhe: detalhe.slice(0, 500), tentativas,
      atualizado_em: new Date().toISOString(),
      ...(estado === 'enviado' ? { enviado_em: new Date().toISOString() } : {}),
      ...extra,
    }, { onConflict: 'order_id' })
    return json({ ok: estado === 'enviado', estado, detalhe })
  }

  const { data: recibo, error } = await admin.rpc('_recibo_pedido', { p_order_id: orderId })
  if (error) return fim('falhou', `recibo_sql: ${error.message}`)
  if (!recibo) return fim('falhou', 'pedido_nao_entregue')

  let destino = ''
  if (recibo.user_id) {
    const { data: u } = await admin.auth.admin.getUserById(recibo.user_id)
    destino = u?.user?.email ?? ''
  }
  if (!destino || /@(driver\.)?bora\.app$/i.test(destino)) {
    return fim('sem_email', destino ? 'email_interno' : 'sem_email', { email: destino || null, user_id: recibo.user_id })
  }

  const html = htmlRecibo(recibo)
  const data = new Date(recibo.data ?? Date.now())
  const caminho = `${data.getUTCFullYear()}/${String(data.getUTCMonth() + 1).padStart(2, '0')}/${orderId}.html`
  const { error: upErr } = await admin.storage.from('recibos-clientes')
    .upload(caminho, new Blob([html], { type: 'text/html; charset=utf-8' }), { upsert: true, contentType: 'text/html; charset=utf-8' })
  if (upErr) console.warn('[recibo-pedido-cliente] cópia em storage falhou:', upErr.message)

  let resendKey = Deno.env.get('RESEND_API_KEY') ?? null
  if (!resendKey) {
    const { data: k } = await admin.rpc('get_resend_key')
    if (k && String(k).trim()) resendKey = String(k).trim()
  }
  const extra = { email: destino, user_id: recibo.user_id, storage_path: upErr ? null : caminho }
  if (!resendKey) return fim('falhou', 'resend_sem_chave', extra)

  const res = await fetch('https://api.resend.com/emails', {
    method: 'POST',
    headers: { Authorization: `Bearer ${resendKey}`, 'Content-Type': 'application/json' },
    body: JSON.stringify({
      from: EMAIL_FROM, to: [destino],
      subject: `Recibo do teu pedido Bora #${recibo.numero} · ${dataPt(recibo.data)}`,
      html,
    }),
  })
  const rb = await res.json().catch(() => ({}))
  if (!res.ok) return fim('falhou', `resend_${res.status}: ${JSON.stringify(rb).slice(0, 200)}`, extra)
  return fim('enviado', rb?.id ? `resend ${rb.id}` : 'enviado', { ...extra, resend_id: rb?.id ?? null })
})

function json(obj: any, status = 200): Response {
  return new Response(JSON.stringify(obj), { status, headers: { ...corsHeaders, 'Content-Type': 'application/json' } })
}

function euro(c: number | null | undefined): string {
  if (c === null || c === undefined) return '—'
  return (Number(c) / 100).toFixed(2).replace('.', ',') + ' €'
}

function esc(s: unknown): string {
  return String(s ?? '').replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;')
}

function dataPt(iso: string): string {
  try {
    return new Date(iso).toLocaleString('pt-PT', { timeZone: 'Europe/Lisbon', day: '2-digit', month: '2-digit', year: 'numeric', hour: '2-digit', minute: '2-digit' })
  } catch { return String(iso ?? '') }
}

function metodoPt(m: string): string {
  switch (m) {
    case 'cash': return 'Dinheiro'
    case 'mbway': return 'MB Way'
    case 'card': case 'stripe': return 'Cartão'
    case 'wallet': return 'Saldo Bora'
    default: return m ? String(m) : '—'
  }
}

function linha(nome: string, valor: string, forte = false): string {
  const w = forte ? 'font-weight:700;' : ''
  return `<tr><td style="padding:6px 0;${w}">${nome}</td><td style="padding:6px 0;text-align:right;${w}">${valor}</td></tr>`
}

export function htmlRecibo(r: any): string {
  const itens = (r.itens ?? []).map((i: any) =>
    linha(`${esc(i.nome)}${Number(i.qtd ?? 1) !== 1 ? ` × ${esc(i.qtd)}` : ''}`, euro(i.valor_cents))).join('')
  const linhas = (r.linhas ?? []).map((l: any) => linha(esc(l.nome), euro(l.valor_cents))).join('')
  const descontos = (r.descontos ?? []).map((d: any) => linha(`Desconto: ${esc(d.nome)}`, '−' + euro(d.valor_cents))).join('')
  const gorjeta = Number(r.gorjeta_cents ?? 0) > 0 ? linha('Gorjeta ao estafeta', euro(r.gorjeta_cents)) : ''
  const nif = r.nif
    ? `<p style="margin:16px 0 0;font-size:13px;color:#374151">Pediste fatura com o NIF <b>${esc(r.nif)}</b>${r.nome_fatura ? ` (${esc(r.nome_fatura)})` : ''}.</p>`
    : ''
  return `<!doctype html><html lang="pt-PT"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Recibo Bora #${esc(r.numero)}</title></head>
<body style="margin:0;background:#F3F4F6;font-family:Inter,Arial,sans-serif;color:#111827">
<div style="max-width:520px;margin:0 auto;padding:24px 16px">
  <div style="background:#fff;border-radius:16px;padding:24px">
    <div style="display:flex;align-items:center;gap:10px;margin-bottom:8px">
      <div style="width:40px;height:40px;border-radius:10px;background:${VERDE};color:#fff;font-weight:800;font-size:24px;line-height:40px;text-align:center">B</div>
      <div style="font-size:22px;font-weight:800;color:${VERDE}">Bora</div>
    </div>
    <h1 style="font-size:18px;margin:12px 0 4px">Recibo do pedido #${esc(r.numero)}</h1>
    <p style="margin:0;color:#6B7280;font-size:13px">${esc(r.loja)} · ${dataPt(r.data)}</p>
    <table style="width:100%;border-collapse:collapse;margin-top:16px;font-size:14px">
      ${itens}
      <tr><td colspan="2" style="border-top:1px solid #E5E7EB"></td></tr>
      ${linhas}
      ${linha('Total do pedido', euro(r.total_pedido_cents), true)}
      ${gorjeta}
      ${descontos}
      <tr><td colspan="2" style="border-top:2px solid ${VERDE}"></td></tr>
      ${linha('Total pago', euro(r.total_pago_cents), true)}
      ${linha('Pagamento', esc(metodoPt(r.metodo)))}
    </table>
    ${nif}
    <p style="margin:24px 0 0;font-size:11px;color:#6B7280;line-height:1.5">Recibo emitido pela Bora (Danilo Fulfaro da Silva - Unipessoal Lda, NIF 519686233). A fatura do estabelecimento, quando pedida, é emitida pela loja.</p>
  </div>
</div></body></html>`
}

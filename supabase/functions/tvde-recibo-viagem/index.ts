// @ts-nocheck
// supabase/functions/tvde-recibo-viagem/index.ts  v2  2026-09-23
//
// Recibo da viagem TVDE ao passageiro, por email (Lei 45/2018 revista pela
// Lei 59/2026: recibo eletrónico por viagem com a taxa de intermediação
// discriminada). NÃO é fatura — a fatura fica para o software certificado.
//
// Os números vêm TODOS de `_tvde_recibo` / `tvde_recibo_viagem` (SQL). Esta
// função não faz contas: só desenha o que o servidor devolve.
//
// Dois caminhos:
//  - service_role (trigger trg_tvde_recibo_email ao passar a 'finalizada'):
//    { rideId } → email ao passageiro da corrida, uma vez só por corrida.
//  - utilizador (botão "Enviar por e-mail" na app): { rideId } → a RPC com o
//    JWT dele decide se pode ver; manda para o email da própria conta.
//
// Resultado registado em tvde_recibos_email (ok / motivo) — sem falha muda.

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const EMAIL_FROM = 'Bora <recibos@boraguarda.com>'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders })

  const supabaseUrl = Deno.env.get('SUPABASE_URL')!
  const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
  const anonKey = Deno.env.get('SUPABASE_ANON_KEY')!
  const authHeader = req.headers.get('Authorization') ?? ''

  let body: any = {}
  try { body = await req.json() } catch (_e) { return json({ ok: false, error: 'json_invalido' }, 400) }
  const rideId = String(body?.rideId ?? '')
  if (!/^[0-9a-f-]{36}$/i.test(rideId)) return json({ ok: false, error: 'rideId_invalido' }, 400)

  let isService = false
  try {
    const p = JSON.parse(atob(authHeader.substring(7).split('.')[1]))
    isService = p.role === 'service_role'
  } catch (_e) {}

  const admin = createClient(supabaseUrl, serviceKey)
  let recibo: any = null
  let destino = ''

  if (isService) {
    const { data: ja } = await admin.from('tvde_recibos_email').select('ok').eq('ride_id', rideId).maybeSingle()
    if (ja?.ok) return json({ ok: true, ja_enviado: true })
    const { data, error } = await admin.rpc('_tvde_recibo', { p_ride: rideId })
    if (error) return json({ ok: false, error: error.message }, 500)
    recibo = data
    const { data: ride } = await admin.from('tvde_rides').select('client_id').eq('id', rideId).maybeSingle()
    if (ride?.client_id) {
      const { data: u } = await admin.auth.admin.getUserById(ride.client_id)
      destino = u?.user?.email ?? ''
    }
  } else {
    const userClient = createClient(supabaseUrl, anonKey, { global: { headers: { Authorization: authHeader } } })
    const { data: me } = await userClient.auth.getUser()
    if (!me?.user) return json({ ok: false, error: 'sem_sessao' }, 401)
    const { data, error } = await userClient.rpc('tvde_recibo_viagem', { p_ride: rideId })
    if (error) return json({ ok: false, error: error.message }, 403)
    recibo = data
    destino = me.user.email ?? ''
  }

  // O registo tvde_recibos_email é o do envio AUTOMÁTICO ao passageiro. Um
  // pedido manual (passageiro a reenviar, motorista a pedir cópia) não lhe
  // mexe — senão a cópia do motorista marcava a corrida como "já enviada".
  const fim = (ok: boolean, detalhe: string) =>
    isService ? registar(admin, rideId, destino, ok, detalhe) : json({ ok, detalhe, email: destino })

  if (!recibo) return fim(false, 'viagem_nao_finalizada')
  if (!destino || destino.endsWith('@driver.bora.app')) return fim(false, 'sem_email')

  let resendKey = Deno.env.get('RESEND_API_KEY') ?? null
  if (!resendKey) {
    const { data: k } = await admin.rpc('get_resend_key')
    if (k && String(k).trim()) resendKey = String(k).trim()
  }
  if (!resendKey) return fim(false, 'resend_sem_chave')

  const res = await fetch('https://api.resend.com/emails', {
    method: 'POST',
    headers: { Authorization: `Bearer ${resendKey}`, 'Content-Type': 'application/json' },
    body: JSON.stringify({
      from: EMAIL_FROM, to: [destino],
      subject: `Recibo da tua viagem Bora · ${dataPt(recibo.data)}`,
      html: htmlRecibo(recibo),
    }),
  })
  const rb = await res.json().catch(() => ({}))
  if (!res.ok) return fim(false, `resend_${res.status}: ${JSON.stringify(rb).slice(0, 200)}`)
  return fim(true, rb?.id ? `resend ${rb.id}` : 'enviado')
})

async function registar(admin: any, rideId: string, email: string, ok: boolean, detalhe: string) {
  await admin.from('tvde_recibos_email').upsert(
    { ride_id: rideId, email: email || null, ok, detalhe, enviado_em: new Date().toISOString() },
    { onConflict: 'ride_id' })
  return json({ ok, detalhe })
}

function json(obj: any, status = 200): Response {
  return new Response(JSON.stringify(obj), { status, headers: { ...corsHeaders, 'Content-Type': 'application/json' } })
}

function euro(c: number | null | undefined): string {
  if (c === null || c === undefined) return '—'
  return (c / 100).toFixed(2).replace('.', ',') + ' €'
}

function dataPt(iso: string): string {
  try {
    return new Date(iso).toLocaleString('pt-PT', { timeZone: 'Europe/Lisbon', day: '2-digit', month: '2-digit', year: 'numeric', hour: '2-digit', minute: '2-digit' })
  } catch (_e) { return iso }
}

function esc(s: any): string {
  return String(s ?? '').replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;')
}

const MEIOS: Record<string, string> = { card: 'Cartão', mbway: 'MB Way', cash: 'Dinheiro' }

function linha(rotulo: string, valor: string, forte = false): string {
  const w = forte ? 'font-weight:700;' : ''
  return `<tr><td style="padding:6px 0;color:#374151;${w}">${esc(rotulo)}</td><td style="padding:6px 0;text-align:right;${w}">${esc(valor)}</td></tr>`
}

function htmlRecibo(r: any): string {
  const linhas: string[] = []
  if (r.discriminado) {
    linhas.push(linha('Serviço de transporte (motorista)', euro(r.transporte_cents)))
    linhas.push(linha('Taxa de intermediação Bora', euro(r.taxa_intermediacao_cents)))
  }
  linhas.push(linha('Valor da viagem', euro(r.valor_viagem_cents), !r.descontos_cents))
  if (r.paragens_cents) linhas.push(linha('das quais paragens extra', euro(r.paragens_cents)))
  if (r.descontos_cents) {
    linhas.push(linha('Descontos (tokens / crédito)', '− ' + euro(r.descontos_cents)))
    linhas.push(linha('Total pago', euro(r.total_pago_cents), true))
  }
  const razao = r.razao ? `<p style="color:#6b7280;font-size:13px">${esc(r.razao)}</p>` : ''
  const nif = r.plataforma_nif ? ` · NIF ${esc(r.plataforma_nif)}` : ' · NIF em processo de registo'
  return `<!doctype html><html><body style="font-family:Inter,Arial,sans-serif;background:#f9fafb;padding:24px">
<div style="max-width:520px;margin:auto;background:#fff;border-radius:12px;padding:24px;border:1px solid #e5e7eb">
<h2 style="color:#16A34A;margin:0 0 4px">Recibo da viagem</h2>
<p style="margin:0 0 16px;color:#6b7280">N.º ${esc(r.numero)} · ${esc(dataPt(r.data))}</p>
<p style="margin:0"><b>De:</b> ${esc(r.origem)}</p>
<p style="margin:4px 0"><b>Para:</b> ${esc(r.destino)}</p>
<p style="margin:4px 0 16px;color:#374151">Início ${esc(dataPt(r.inicio))}${r.distancia_km ? ` · ${String(r.distancia_km).replace('.', ',')} km` : ''}<br>Motorista: ${esc(r.motorista ?? '—')}</p>
<table style="width:100%;border-collapse:collapse;border-top:1px solid #e5e7eb">${linhas.join('')}</table>
<p style="margin:12px 0 0">Pagamento: <b>${esc(MEIOS[r.pagamento] ?? r.pagamento ?? '—')}</b></p>
${razao}
<p style="color:#6b7280;font-size:12px;margin-top:20px">${esc(r.plataforma)} — operador de plataforma TVDE${nif}.<br>${esc(r.aviso_legal)}</p>
</div></body></html>`
}

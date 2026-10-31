// ============================================================================
// cobrar-diferenca-peso — PESO VARIÁVEL: cobrar no cartão a diferença a mais
// ----------------------------------------------------------------------------
// 🔴 LISTA VERMELHA (cartão). Regra do Danilo 26/10/2026 10:16 ("Autorizo."): o cliente paga o
// valor final dos produtos ao quilo; pagou com cartão e saiu mais caro → cobra-se a diferença no
// MESMO cartão. Missão fecho-pendentes-2026-10-31 (31/10 22:08): fica PRONTA mas DESLIGADA
// (platform_settings.weight_adjust_card_charge_enabled = false). business_rules §59.
//
// Quem chama: SÓ o servidor — finalizar_talao_nao_parceiro faz net.http_post com a chave de servidor
// quando o interruptor está ligado e o talão deu card_extra_cents > 0. Com o interruptor desligado
// esta função recusa sem cobrar nada, mesmo que alguém com a chave a chame.
//
// POST { order_id, amount_cents }   (ou { ping:true } do vigia das chaves → { pong:true })
// Só cobra quando TUDO bate:
//   - pedido pago com cartão ('card' | 'stripe'), compra fechada (is_purchase_finalized);
//   - amount_cents = ROUND(orders.extra_charge_amount × 100) (o que o talão gravou) e 1..5000;
//   - ainda não acertado (extra_charge_settled_at IS NULL).
// Cobra com o cartão e o Customer do pagamento original (payment_intent_id do pedido),
// off_session + confirm, idempotência "peso_<order_id>". Nunca marca nada como pago sem a Stripe
// dizer succeeded.
//   sucesso → orders.final_total += valor, extra_charge_settled_at, extra_charge_settled_via =
//             'cartao_peso'; order_weight_adjustments.settled_via = 'cartao_cobrado'; aviso no sino.
//   sem cartão reutilizável / o banco pede autenticação / recusado → settled_via = 'bora_assume'
//             e aviso URGENTE ao Danilo pelo porteiro (porteiro_entrada).
// Como ligar e vigiar: ver o relatório fecho-pendentes-2026-10-31 (secção ISTO MEXE EM DINHEIRO).
// ============================================================================

import Stripe from 'https://esm.sh/stripe@14.21.0?target=deno';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';
import { secretKey } from '../_shared/keys.ts';
import { exigirServidor, respostaAoPing } from '../_shared/chaves.ts';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};

const STRIPE_MODE = (Deno.env.get('BORA_STRIPE_MODE') ?? 'live').toLowerCase();
const stripeKey = STRIPE_MODE === 'test'
  ? (Deno.env.get('STRIPE_TEST_SECRET_KEY') ?? '')
  : (Deno.env.get('STRIPE_SECRET_KEY') ?? '');
const stripe = new Stripe(stripeKey, { apiVersion: '2023-10-16' });

const supabaseUrl = Deno.env.get('SUPABASE_URL') ?? '';
const MAX_CENTS = 5000;

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  });
}

// deno-lint-ignore no-explicit-any
type Admin = any;

async function interruptorLigado(admin: Admin): Promise<boolean> {
  const { data } = await admin.from('platform_settings').select('value')
    .eq('key', 'weight_adjust_card_charge_enabled').maybeSingle();
  const v = data?.value;
  return v === true || v === 'true';
}

async function boraAssume(admin: Admin, orderId: string, motivo: string, amountCents: number) {
  await admin.from('order_weight_adjustments')
    .update({ settled_via: 'bora_assume', settled_at: new Date().toISOString() })
    .eq('order_id', orderId).eq('settled_via', 'cartao_pendente');
  const euros = (amountCents / 100).toFixed(2).replace('.', ',');
  await admin.from('porteiro_entrada').insert({
    origem: 'cobrar-diferenca-peso',
    nivel: 'URGENTE',
    texto: `Peso variável: não deu para cobrar ${euros} € no cartão do pedido ${orderId.slice(0, 8)} ` +
      `(${motivo}). A Bora assume a diferença. Ver Operação do dia → Ajustes de peso.`,
  });
  await admin.from('e2e_log').insert({
    fluxo: 'cobrar-diferenca-peso', passo: 'bora_assume', estado: 'aviso',
    detalhe: `pedido ${orderId} ${amountCents} cent: ${motivo}`, device: 'edge',
  });
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders });
  if (req.method !== 'POST') return json({ ok: false, error: 'method_not_allowed' }, 405);

  const negado = await exigirServidor(req, corsHeaders);
  if (negado) return negado;
  const ping = await respostaAoPing(req, corsHeaders);
  if (ping) return ping;

  const admin = createClient(supabaseUrl, secretKey() ?? '', { auth: { persistSession: false } });

  // deno-lint-ignore no-explicit-any
  let body: any = null;
  try { body = await req.json(); } catch { /* corpo inválido */ }
  const orderId = typeof body?.order_id === 'string' ? body.order_id : '';
  const amountCents = Number.isInteger(body?.amount_cents) ? body.amount_cents as number : -1;
  if (!orderId || amountCents < 1 || amountCents > MAX_CENTS) {
    return json({ ok: false, error: 'pedido_invalido' }, 400);
  }

  if (!(await interruptorLigado(admin))) {
    return json({ ok: false, error: 'desligado', note: 'weight_adjust_card_charge_enabled=false: nada cobrado' });
  }

  const { data: o, error: oe } = await admin.from('orders')
    .select('id, user_id, payment_method, payment_intent_id, is_purchase_finalized, extra_charge_amount, extra_charge_settled_at, final_total, status')
    .eq('id', orderId).maybeSingle();
  if (oe || !o) return json({ ok: false, error: 'pedido_nao_encontrado' }, 404);
  if (o.extra_charge_settled_at) return json({ ok: true, note: 'ja_acertado' });
  if (!['card', 'stripe'].includes(String(o.payment_method))) {
    return json({ ok: false, error: 'nao_e_cartao' }, 400);
  }
  if (o.is_purchase_finalized !== true) return json({ ok: false, error: 'compra_por_fechar' }, 400);
  if (['cancelled', 'rejected'].includes(String(o.status))) return json({ ok: false, error: 'pedido_fechado' }, 400);
  const gravado = Math.round(Number(o.extra_charge_amount ?? 0) * 100);
  if (gravado !== amountCents) {
    return json({ ok: false, error: 'valor_diferente_do_talao', gravado_cents: gravado }, 400);
  }

  // Cartão e Customer do pagamento original.
  let pmId: string | null = null;
  let customerId: string | null = null;
  if (o.payment_intent_id && String(o.payment_intent_id).startsWith('pi_')) {
    try {
      const orig = await stripe.paymentIntents.retrieve(String(o.payment_intent_id));
      pmId = typeof orig.payment_method === 'string' ? orig.payment_method : orig.payment_method?.id ?? null;
      customerId = typeof orig.customer === 'string' ? orig.customer : orig.customer?.id ?? null;
    } catch (_) { /* sem pagamento original legível */ }
  }
  if (!pmId || !customerId) {
    await boraAssume(admin, orderId, 'sem cartão guardado do pagamento original', amountCents);
    return json({ ok: false, error: 'sem_cartao_guardado', settled_via: 'bora_assume' });
  }

  try {
    const pi = await stripe.paymentIntents.create({
      amount: amountCents,
      currency: 'eur',
      customer: customerId,
      payment_method: pmId,
      confirm: true,
      off_session: true,
      automatic_payment_methods: { enabled: true, allow_redirects: 'never' },
      description: `Bora — diferença de peso do pedido ${orderId.slice(0, 8)}`,
      metadata: { kind: 'peso_variavel', order_id: orderId },
    }, { idempotencyKey: `peso_${orderId}` });

    if (pi.status !== 'succeeded') {
      await boraAssume(admin, orderId, `Stripe ficou em ${pi.status}`, amountCents);
      return json({ ok: false, error: 'nao_confirmado', status: pi.status, settled_via: 'bora_assume' });
    }

    const novoTotal = Math.round((Number(o.final_total ?? 0) * 100) + amountCents) / 100;
    const agora = new Date().toISOString();
    const { error: ue } = await admin.from('orders').update({
      final_total: novoTotal,
      extra_charge_settled_at: agora,
      extra_charge_settled_via: 'cartao_peso',
    }).eq('id', orderId).is('extra_charge_settled_at', null);
    if (ue) {
      // Cobrado na Stripe mas o pedido não gravou: não se repete a cobrança (idempotência);
      // fica registado para o admin acertar.
      await admin.from('e2e_log').insert({
        fluxo: 'cobrar-diferenca-peso', passo: 'gravar_pedido', estado: 'erro',
        detalhe: `pedido ${orderId} cobrado ${pi.id} mas update falhou: ${ue.message}`, device: 'edge',
      });
    }
    await admin.from('order_weight_adjustments')
      .update({ settled_via: 'cartao_cobrado', settled_at: agora })
      .eq('order_id', orderId).eq('settled_via', 'cartao_pendente');
    if (o.user_id) {
      const euros = (amountCents / 100).toFixed(2).replace('.', ',');
      await admin.rpc('_push_in_app_notification', {
        p_user_id: o.user_id,
        p_kind: 'order_weight_adjusted',
        p_title: 'Diferença de peso cobrada',
        p_body: `Cobrámos ${euros} € no teu cartão: os produtos ao quilo pesaram mais do que o previsto.`,
        p_related_id: orderId,
      });
    }
    return json({ ok: true, payment_intent_id: pi.id, amount_cents: amountCents });
  } catch (e) {
    const m = e instanceof Error ? e.message : String(e);
    await boraAssume(admin, orderId, `cartão recusado ou pede autenticação: ${m.slice(0, 120)}`, amountCents);
    return json({ ok: false, error: 'cobranca_falhou', settled_via: 'bora_assume' });
  }
});

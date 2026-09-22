// supabase/functions/order-edit-settle/index.ts
//
// MEXE EM DINHEIRO REAL (Stripe LIVE). Publicada com o "vai" do Danilo (22/09/2026).
// run: parceiro-edita-pedido-2026-09-22
//
// Liquida as alterações que o dono de uma loja PARCEIRA faz a um pedido já pago
// (tabela order_edits; regras em 20260922200100_parceiro_edita_pedido_dinheiro.sql).
//
//   action 'refund'  {grupo_id}  — produto em falta num pedido pago com CARTÃO:
//        reembolso parcial no MESMO PaymentIntent do pedido, só o que falta.
//        O que o cartão já não cobre (parte paga com carteira/tokens) vai para a
//        carteira pelo split (order_edit_refund_done → wallet_credit_refund_split).
//        Quem chama: o banco (pg_net, service_role) logo a seguir a aplicar; o admin
//        ("Forçar estorno") via admin_force_refund_order_edit.
//
//   action 'charge'  {grupo_id}  — o cliente aceitou acrescentar:
//        cartão → PaymentIntent off-session no cartão guardado do pedido original;
//                 se o banco do cliente pedir confirmação (3DS) ou recusar, devolve
//                 client_secret para a Payment Sheet no telemóvel do cliente.
//        MB Way → pedido MB Way só da diferença para o telemóvel do pedido;
//                 a app faz 'confirm' até o PI ficar pago.
//        Quem chama: a app do cliente (JWT do dono do pedido) ou o admin/banco.
//
//   action 'confirm' {grupo_id, payment_intent_id} — confirma que o PI da diferença
//        está pago (valor e grupo batem) e aplica a alteração ao pedido.
//
// Os PIs daqui NUNCA levam metadata.order_id nem draft_id: o stripe-webhook trataria
// um PI da diferença como o pagamento do pedido (e, se falhasse, marcava-o falhado).
// Vão com purpose='order_edit' + edit_order_id + order_edit_group (o webhook ignora).
//
// verify_jwt = true (config.toml). Idempotência Stripe por grupo.

import Stripe from 'https://esm.sh/stripe@14.21.0?target=deno';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';
import { corsHeaders } from '../_shared/cors.ts';

const STRIPE_MODE = (Deno.env.get('BORA_STRIPE_MODE') ?? 'live').toLowerCase();
const stripeSecretKey = STRIPE_MODE === 'test'
  ? (Deno.env.get('STRIPE_TEST_SECRET_KEY') ?? '')
  : (Deno.env.get('STRIPE_SECRET_KEY') ?? '');
const stripe = new Stripe(stripeSecretKey, {
  apiVersion: '2023-10-16',
  httpClient: Stripe.createFetchHttpClient(),
});

const supabaseUrl = Deno.env.get('SUPABASE_URL') ?? '';
const anonKey = Deno.env.get('SUPABASE_ANON_KEY') ?? '';
const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '';

// deno-lint-ignore no-explicit-any
const json = (body: any, status = 200) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  });

type Caller = { kind: 'service' } | { kind: 'user'; id: string; admin: boolean };

async function whoCalls(req: Request): Promise<Caller | null> {
  const auth = req.headers.get('authorization') ?? '';
  if (!auth.startsWith('Bearer ')) return null;
  const token = auth.substring(7);
  try {
    const payload = JSON.parse(atob(token.split('.')[1]));
    if (payload.role === 'service_role') return { kind: 'service' };
  } catch (_) { /* segue para utilizador */ }
  const userClient = createClient(supabaseUrl, anonKey, {
    global: { headers: { Authorization: auth } },
  });
  const { data, error } = await userClient.auth.getUser();
  if (error || !data?.user) return null;
  const { data: isAdmin } = await userClient.rpc('is_admin');
  return { kind: 'user', id: data.user.id, admin: isAdmin === true };
}

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders });

  const caller = await whoCalls(req);
  if (!caller) return json({ ok: false, error: 'forbidden' }, 403);

  // deno-lint-ignore no-explicit-any
  let body: any;
  try { body = await req.json(); } catch { return json({ ok: false, error: 'invalid_json' }, 400); }
  const action = String(body?.action ?? '');
  const grupoId = String(body?.grupo_id ?? '');
  if (!grupoId || !['refund', 'charge', 'confirm'].includes(action)) {
    return json({ ok: false, error: 'invalid_body' }, 400);
  }

  const admin = createClient(supabaseUrl, serviceKey);
  const { data: edit } = await admin
    .from('order_edits')
    .select('grupo_id, order_id, estado, liquidacao')
    .eq('grupo_id', grupoId)
    .limit(1)
    .maybeSingle();
  if (!edit) return json({ ok: false, error: 'grupo_nao_existe' }, 404);

  const { data: order } = await admin
    .from('orders')
    .select('id, user_id, payment_method, payment_intent_id, client_phone')
    .eq('id', edit.order_id)
    .maybeSingle();
  if (!order) return json({ ok: false, error: 'pedido_nao_existe' }, 404);

  const isService = caller.kind === 'service';
  const isAdmin = caller.kind === 'user' && caller.admin;
  const isOwner = caller.kind === 'user' && caller.id === order.user_id;
  // deno-lint-ignore no-explicit-any
  const liq: any = edit.liquidacao ?? {};

  try {
    if (action === 'refund') {
      if (!isService && !isAdmin) return json({ ok: false, error: 'forbidden' }, 403);
      return await refund(admin, grupoId, order, liq);
    }
    if (!isService && !isAdmin && !isOwner) return json({ ok: false, error: 'forbidden' }, 403);
    if (action === 'charge') return await charge(admin, grupoId, edit.estado, order, liq);
    return await confirm(admin, grupoId, String(body?.payment_intent_id ?? ''), liq);
  } catch (e) {
    const msg = e instanceof Error ? e.message : String(e);
    console.error(`[order-edit-settle] ${action} ${grupoId}:`, msg);
    await admin.rpc('order_edit_settle_failed', { p_grupo_id: grupoId, p_erro: `${action}: ${msg}` });
    return json({ ok: false, error: msg }, 502);
  }
});

// ── Reembolso parcial no mesmo pagamento ───────────────────────────────────
// deno-lint-ignore no-explicit-any
async function refund(admin: any, grupoId: string, order: any, liq: any): Promise<Response> {
  if (liq.metodo !== 'cartao') return json({ ok: false, error: 'nao_e_cartao', liquidacao: liq }, 409);
  if (liq.estado === 'feito') return json({ ok: true, ja_feito: true });
  const devolver = Number(liq.devolver_cents ?? 0);
  const piId = String(liq.payment_intent_id ?? order.payment_intent_id ?? '');
  if (!piId || devolver <= 0) return json({ ok: false, error: 'sem_pagamento_ou_valor' }, 409);

  const pi = await stripe.paymentIntents.retrieve(piId, { expand: ['latest_charge'] });
  const charge = pi.latest_charge as Stripe.Charge | null;
  const cobrado = charge?.amount_captured ?? pi.amount_received ?? 0;
  const jaDevolvido = charge?.amount_refunded ?? 0;
  const podeDevolver = Math.max(0, cobrado - jaDevolvido);
  const noCartao = Math.min(devolver, podeDevolver);
  const resto = devolver - noCartao; // parte paga com carteira/tokens → volta à carteira

  let refundId = 'sem_refund_stripe';
  if (noCartao > 0) {
    const r = await stripe.refunds.create(
      {
        payment_intent: piId,
        amount: noCartao,
        reason: 'requested_by_customer',
        metadata: { purpose: 'order_edit', edit_order_id: order.id, order_edit_group: grupoId },
      },
      { idempotencyKey: `order-edit-refund-${grupoId}` },
    );
    refundId = r.id;
  }
  const { data, error } = await admin.rpc('order_edit_refund_done', {
    p_grupo_id: grupoId, p_refund_id: refundId, p_refunded_cents: noCartao, p_resto_cents: resto,
  });
  if (error) throw new Error(`order_edit_refund_done: ${error.message}`);
  console.log(`[order-edit-settle] refund ${grupoId} cartão=${noCartao} carteira=${resto} ${refundId}`);
  return json({ ok: true, refund_id: refundId, cartao_cents: noCartao, carteira_cents: resto, db: data });
}

// ── Cobrar a diferença (cliente aceitou acrescentar) ───────────────────────
// deno-lint-ignore no-explicit-any
async function charge(admin: any, grupoId: string, estado: string, order: any, liq: any): Promise<Response> {
  if (estado === 'aplicado') return json({ ok: true, ja_aplicado: true });
  if (estado !== 'aceite' || liq.estado !== 'a_cobrar') return json({ ok: false, error: 'nada_a_cobrar', estado, liquidacao: liq }, 409);
  const cents = Number(liq.cobrar_cents ?? 0);
  if (cents < 50) return json({ ok: false, error: 'valor_minimo_stripe' }, 409);
  const metadata = { purpose: 'order_edit', edit_order_id: order.id, order_edit_group: grupoId, user_id: String(order.user_id ?? '') };

  // Nunca cobrar duas vezes: se uma tentativa anterior já foi paga (ex.: o
  // MB Way confirmado depois de a app fechar), aplica-se essa e acabou.
  const pagos = await stripe.paymentIntents.search({
    query: `metadata['order_edit_group']:'${grupoId}' AND status:'succeeded'`,
    limit: 1,
  });
  if (pagos.data.length > 0) {
    const pi = pagos.data[0];
    const { data, error } = await admin.rpc('order_edit_mark_paid', {
      p_grupo_id: grupoId, p_payment_intent_id: pi.id, p_amount_cents: pi.amount_received,
    });
    if (error) throw new Error(`order_edit_mark_paid: ${error.message}`);
    return json({ ok: true, pago: true, payment_intent_id: pi.id, db: data });
  }
  // Chave de idempotência por minuto: dois toques seguidos não criam duas
  // cobranças, mas uma nova tentativa depois de uma recusa já é possível.
  const tentativa = Math.floor(Date.now() / 60000);

  if (order.payment_method === 'mbway') {
    const phone = String(order.client_phone ?? '').replace(/\s/g, '');
    if (!phone) return json({ ok: false, error: 'sem_telefone_mbway' }, 409);
    const e164 = phone.startsWith('+') ? phone : `+351${phone.replace(/^0/, '')}`;
    const pi = await stripe.paymentIntents.create({
      amount: cents, currency: 'eur',
      payment_method_types: ['mb_way'],
      payment_method_data: { type: 'mb_way', billing_details: { phone: e164 } },
      confirm: true, metadata,
    }, { idempotencyKey: `order-edit-mbway-${grupoId}-${tentativa}` });
    return json({ ok: true, metodo: 'mbway', payment_intent_id: pi.id, status: pi.status });
  }

  if (order.payment_method !== 'card') return json({ ok: false, error: 'metodo_sem_cobranca', metodo: order.payment_method }, 409);

  // cartão guardado do pedido original
  let customer: string | null = null;
  let pm: string | null = null;
  if (order.payment_intent_id) {
    const orig = await stripe.paymentIntents.retrieve(order.payment_intent_id);
    customer = typeof orig.customer === 'string' ? orig.customer : orig.customer?.id ?? null;
    pm = typeof orig.payment_method === 'string' ? orig.payment_method : orig.payment_method?.id ?? null;
  }

  if (customer && pm) {
    try {
      const pi = await stripe.paymentIntents.create({
        amount: cents, currency: 'eur', customer, payment_method: pm,
        confirm: true, off_session: true, metadata,
      }, { idempotencyKey: `order-edit-charge-${grupoId}-${tentativa}` });
      if (pi.status === 'succeeded') {
        const { data, error } = await admin.rpc('order_edit_mark_paid', {
          p_grupo_id: grupoId, p_payment_intent_id: pi.id, p_amount_cents: pi.amount_received,
        });
        if (error) throw new Error(`order_edit_mark_paid: ${error.message}`);
        return json({ ok: true, metodo: 'cartao', pago: true, payment_intent_id: pi.id, db: data });
      }
    } catch (e) {
      // authentication_required / card_declined → o cliente paga no ecrã
      console.warn(`[order-edit-settle] off-session falhou ${grupoId}:`, e instanceof Error ? e.message : e);
    }
  }

  const sheet = await stripe.paymentIntents.create({
    amount: cents, currency: 'eur',
    ...(customer ? { customer } : {}),
    automatic_payment_methods: { enabled: true },
    metadata,
  }, { idempotencyKey: `order-edit-sheet-${grupoId}-${tentativa}` });
  return json({ ok: true, metodo: 'cartao', pago: false, precisa_ecra: true, client_secret: sheet.client_secret, payment_intent_id: sheet.id });
}

// ── Confirmar o PI da diferença e aplicar ──────────────────────────────────
// deno-lint-ignore no-explicit-any
async function confirm(admin: any, grupoId: string, piId: string, liq: any): Promise<Response> {
  if (!piId) return json({ ok: false, error: 'sem_payment_intent' }, 400);
  const pi = await stripe.paymentIntents.retrieve(piId);
  if (pi.metadata?.order_edit_group !== grupoId) return json({ ok: false, error: 'pi_de_outro_grupo' }, 409);
  if (pi.status !== 'succeeded') return json({ ok: true, pago: false, status: pi.status });
  if (pi.amount_received !== Number(liq.cobrar_cents ?? -1)) return json({ ok: false, error: 'valor_nao_bate' }, 409);
  const { data, error } = await admin.rpc('order_edit_mark_paid', {
    p_grupo_id: grupoId, p_payment_intent_id: pi.id, p_amount_cents: pi.amount_received,
  });
  if (error) throw new Error(`order_edit_mark_paid: ${error.message}`);
  return json({ ok: true, pago: true, db: data });
}

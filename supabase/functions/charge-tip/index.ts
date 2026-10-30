// ============================================================================
// charge-tip — GORJETA (gratificação) ao estafeta / motorista TVDE
// ----------------------------------------------------------------------------
// 🔴 LISTA VERMELHA — "vai" do Danilo a 03/10/2026 22h15 (missão única, bloco 3);
// v2: autorização do Danilo a 30/10/2026 13:40 (missão gorjetas-taxa-2026-10-30).
// Edge Function ISOLADA (padrão cleaning-checkout / tvde-plan-payment): NÃO toca
// no stripe-webhook nem no create-payment-intent. verify_jwt = true.
//
// Regra do Danilo (30/10/2026) — a Bora não ganha nada em cima de gorjeta:
//   1. Gorjeta do carrinho com cartão/MB Way → vai no MESMO pagamento da compra
//      (tips.cobrada_junto; ver a migração 20261030145000). Sem taxa à parte: inteira para o estafeta.
//   2. Gorjeta paga DEPOIS (avaliação da entrega / fim da corrida) com cartão/MB Way → pagamento à
//      parte, aqui; o prestador recebe a gorjeta MENOS a taxa exata que a Stripe cobrou nesse
//      pagamento (tips.liquido_prestador_cents). Ex.: 2,00 € − 0,28 € = 1,72 €.
//   3. Dinheiro → inteira (não passa pela Stripe; RPC tip_registar_dinheiro, só no checkout).
//   4. Pedido cancelado → a gorjeta volta inteira ao cliente (_shared/gorjeta_devolver.ts).
// A gorjeta do carrinho ainda passa por aqui quando o pedido foi pago só com saldo, quando o
// interruptor tips_checkout_junto_pagamento está desligado e nas apps antigas.
//
// Ações (POST JSON):
//   { action:'create', target:'order'|'tvde', id, amountCents, moment:'checkout'|'after',
//     saved_pm_id?, phone? }      → cartão: cobra já (cartão do pedido/guardado) ou
//                                  devolve clientSecret p/ a folha da Stripe;
//                                  MB Way: envia o pedido ao telemóvel.
//                                  v2: se o pedido já tem a gorjeta do carrinho (no pagamento
//                                  da compra ou já pedida) → { ok:true, note:'already_exists' }
//                                  sem cobrar nada (nunca duas cobranças no mesmo pedido).
//   { action:'confirm', tipId }   → lê o PI na Stripe e grava o estado (e a taxa).
//   { action:'refund', tipId, reason } → só admin; idempotente. v2: gorjeta cobrada junto =
//                                  reembolso PARCIAL do PI do pedido no valor da gorjeta.
//   v2 — só servidor (gatilho/cron/funções de cancelamento; chave de servidor):
//   { action:'devolver_cancelamento', orderId, destino?:'meio'|'carteira', motivo? }
//                                → pedido cancelado/rejeitado: devolve as gorjetas dele, inteiras
//                                  (também o admin). Sem destino: saldo se o reembolso do pedido
//                                  foi para o saldo (orders.refund_method='wallet'), senão o meio.
//   { action:'taxas_em_falta' }  → vai buscar à Stripe as taxas das gorjetas pagas à parte que
//                                  ficaram por gravar e regista no e2e_log (cron de domingo).
//
// Interruptor: platform_settings.tips_enabled. BORA_STRIPE_MODE=test → chave de teste.
// ============================================================================

import Stripe from 'https://esm.sh/stripe@14.21.0?target=deno';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';
import { secretKey } from '../_shared/keys.ts';
import { chamadaDoServidor } from '../_shared/chaves.ts';
import {
  COLUNAS_GORJETA, devolverGorjetasDoPedido, devolverUmaGorjeta, gorjetaJaVaiNoCartao,
  type DestinoGorjeta, type GorjetaParaDevolver,
} from '../_shared/gorjeta_devolver.ts';

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
const anonKey = Deno.env.get('SUPABASE_ANON_KEY') ?? '';
const serviceKey = secretKey() ?? '';
const SEM_PRESTADOR = '00000000-0000-0000-0000-000000000000';
const FLUXO = 'gorjetas-taxa-2026-10-30';

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  });
}

function toE164(raw: string): string {
  const digits = raw.replace(/[^\d+]/g, '');
  if (digits.startsWith('+')) return digits;
  if (digits.startsWith('351')) return '+' + digits;
  return '+351' + digits;
}

// deno-lint-ignore no-explicit-any
async function setting(admin: any, key: string): Promise<unknown> {
  const { data } = await admin.from('platform_settings').select('value').eq('key', key).maybeSingle();
  return data?.value;
}

// deno-lint-ignore no-explicit-any
async function registar(admin: any, passo: string, estado: string, detalhe: unknown): Promise<void> {
  try {
    await admin.from('e2e_log').insert({ fluxo: FLUXO, passo, estado, detalhe: JSON.stringify(detalhe).slice(0, 4000) });
  } catch (_) { /* o registo é extra */ }
}

// Igual ao cleaning-checkout: Stripe Customer idempotente por utilizador.
// deno-lint-ignore no-explicit-any
async function getOrCreateCustomer(admin: any, userId: string): Promise<string | null> {
  try {
    const { data: u } = await admin.from('users')
      .select('stripe_customer_id, email, name').eq('id', userId).maybeSingle();
    if (u?.stripe_customer_id) return u.stripe_customer_id as string;
    const c = await stripe.customers.create({
      email: (u?.email as string | undefined) ?? undefined,
      name: (u?.name as string | undefined) ?? undefined,
      metadata: { supabase_uid: userId },
    });
    const { error } = await admin.from('users').update({ stripe_customer_id: c.id })
      .eq('id', userId).is('stripe_customer_id', null);
    if (error) {
      const { data: again } = await admin.from('users')
        .select('stripe_customer_id').eq('id', userId).maybeSingle();
      const winner = again?.stripe_customer_id as string | undefined;
      if (winner && winner !== c.id) {
        try { await stripe.customers.del(c.id); } catch (_) { /* swallow */ }
        return winner;
      }
    }
    return c.id;
  } catch (e) {
    console.error('[charge-tip] customer:', e);
    return null;
  }
}

/** Taxa exata que a Stripe cobrou neste pagamento (balance_transaction.fee), ou null se ainda não há. */
async function taxaDoPagamento(piId: string): Promise<number | null> {
  const full = await stripe.paymentIntents.retrieve(piId, {
    expand: ['latest_charge.balance_transaction'],
  });
  // deno-lint-ignore no-explicit-any
  const fee = (full.latest_charge as any)?.balance_transaction?.fee;
  return typeof fee === 'number' ? fee : null;
}

// Estado Stripe → estado da gorjeta (+ taxa da Stripe). v2 (Bloco C, 30/10): a taxa conta dinheiro
// (líquido do prestador nas gorjetas pagas depois): se a gorjeta já estava 'succeeded' e a taxa
// ficou por gravar, grava-se SÓ a taxa.
// deno-lint-ignore no-explicit-any
async function gravarEstado(admin: any, tipId: string, pi: any): Promise<string> {
  let status = 'pending';
  if (pi.status === 'succeeded') status = 'succeeded';
  else if (pi.status === 'requires_action' || pi.status === 'requires_payment_method'
    || pi.status === 'requires_confirmation') status = 'requires_action';
  else if (pi.status === 'canceled') status = 'failed';
  // deno-lint-ignore no-explicit-any
  const patch: Record<string, any> = { status, stripe_payment_intent_id: pi.id };
  let fee: number | null = null;
  if (status === 'succeeded') {
    patch.paid_at = new Date().toISOString();
    try {
      fee = await taxaDoPagamento(pi.id);
      if (fee !== null) patch.stripe_fee_cents = fee;
    } catch (e) {
      console.warn('[charge-tip] taxa ainda por ler (fica para o cron de domingo):', tipId, String(e));
    }
  }
  if (pi.last_payment_error?.message) patch.failure_reason = String(pi.last_payment_error.message).slice(0, 300);
  // Não se volta atrás de um estado final.
  await admin.from('tips').update(patch).eq('id', tipId)
    .not('status', 'in', '(succeeded,refunded)');
  if (fee !== null) {
    await admin.from('tips').update({ stripe_fee_cents: fee }).eq('id', tipId)
      .is('stripe_fee_cents', null);
  }
  return status;
}

// ── Ações só do servidor ─────────────────────────────────────────────────────
// deno-lint-ignore no-explicit-any
async function devolverCancelamento(admin: any, body: any, quem: string | null): Promise<Response> {
  const orderId = String(body?.orderId ?? '');
  if (!orderId) return json({ error: 'orderId_required' }, 400);
  const { data: o, error } = await admin.from('orders')
    .select('id, status, refund_method').eq('id', orderId).maybeSingle();
  if (error) return json({ error: 'order_read_failed', details: error.message }, 500);
  if (!o) return json({ error: 'order_not_found' }, 404);
  // Só pedidos que morreram antes da entrega.
  if (!['cancelled', 'rejected'].includes(String(o.status))) {
    return json({ error: 'order_not_cancelled', status: o.status }, 409);
  }
  const destino: DestinoGorjeta = body?.destino === 'carteira' || body?.destino === 'meio'
    ? body.destino
    : (o.refund_method === 'wallet' ? 'carteira' : 'meio');
  const motivo = String(body?.motivo ?? '').slice(0, 200) || 'pedido cancelado';
  const r = await devolverGorjetasDoPedido(admin, stripeKey, orderId, destino, motivo, quem);
  if (r.itens.length > 0) {
    await registar(admin, 'devolver_cancelamento', r.erros > 0 ? 'erro' : 'ok', { orderId, destino, ...r });
  }
  return json({ ok: r.erros === 0, orderId, destino, ...r });
}

// deno-lint-ignore no-explicit-any
async function taxasEmFalta(admin: any): Promise<Response> {
  // Gorjetas pagas à parte (as do mesmo pagamento da compra não têm taxa própria) dos últimos 60 dias.
  const desde = new Date(Date.now() - 60 * 24 * 3600 * 1000).toISOString();
  const { data: tips, error } = await admin.from('tips')
    .select('id, stripe_payment_intent_id')
    .in('status', ['succeeded', 'refunded'])
    .in('method', ['card', 'mbway'])
    .eq('cobrada_junto', false)
    .is('stripe_fee_cents', null)
    .not('stripe_payment_intent_id', 'is', null)
    .gte('created_at', desde)
    .limit(100);
  if (error) {
    await registar(admin, 'taxas_em_falta', 'erro', { erro: error.message });
    return json({ error: 'tips_read_failed', details: error.message }, 500);
  }
  let gravadas = 0;
  let semTaxa = 0;
  const erros: string[] = [];
  for (const t of (tips ?? []) as { id: string; stripe_payment_intent_id: string }[]) {
    try {
      const fee = await taxaDoPagamento(t.stripe_payment_intent_id);
      if (fee === null) { semTaxa++; continue; }
      const { data: up, error: ue } = await admin.from('tips').update({ stripe_fee_cents: fee })
        .eq('id', t.id).is('stripe_fee_cents', null).select('id');
      if (ue) erros.push(`${t.id}: ${ue.message}`);
      else if (up && up.length > 0) gravadas++;
    } catch (e) {
      erros.push(`${t.id}: ${e instanceof Error ? e.message : String(e)}`.slice(0, 200));
    }
  }
  const verificadas = (tips ?? []).length;
  const estado = erros.length === 0 ? 'ok' : (gravadas > 0 ? 'parcial' : 'erro');
  await registar(admin, 'taxas_em_falta', estado, { verificadas, gravadas, sem_taxa: semTaxa, erros: erros.slice(0, 10) });
  return json({ ok: erros.length === 0, verificadas, gravadas, semTaxa, erros: erros.length });
}

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders });
  try {
    const admin = createClient(supabaseUrl, serviceKey);
    const body = await req.json().catch(() => ({}));
    const action = typeof body?.action === 'string' ? body.action : null;

    // ── Ações do servidor (cron, gatilhos, funções de cancelamento) ─────────
    if (action === 'devolver_cancelamento' || action === 'taxas_em_falta') {
      if (await chamadaDoServidor(req)) {
        return action === 'taxas_em_falta' ? await taxasEmFalta(admin) : await devolverCancelamento(admin, body, null);
      }
    }

    const token = (req.headers.get('Authorization') ?? '').replace('Bearer ', '');
    if (!token) return json({ error: 'missing_token' }, 401);
    const userClient = createClient(supabaseUrl, anonKey, {
      global: { headers: { Authorization: `Bearer ${token}` } },
    });
    const { data: ud, error: authErr } = await userClient.auth.getUser();
    const user = ud?.user;
    if (authErr || !user) return json({ error: 'unauthorized' }, 401);

    // ── TAXAS EM FALTA: só o servidor ────────────────────────────────────────
    if (action === 'taxas_em_falta') return json({ error: 'server_only' }, 403);

    // ── DEVOLVER (pedido cancelado): servidor ou admin ──────────────────────
    if (action === 'devolver_cancelamento') {
      const { data: isAdmin } = await userClient.rpc('is_admin');
      if (isAdmin !== true) return json({ error: 'admin_only' }, 403);
      return await devolverCancelamento(admin, body, user.id);
    }

    // ── CONFIRM ──────────────────────────────────────────────────────────────
    if (action === 'confirm') {
      const tipId = String(body?.tipId ?? '');
      const { data: tip } = await admin.from('tips').select('*').eq('id', tipId).maybeSingle();
      if (!tip) return json({ error: 'tip_not_found' }, 404);
      if (tip.client_user_id !== user.id) return json({ error: 'tip_not_yours' }, 403);
      if (!tip.stripe_payment_intent_id) return json({ status: tip.status });
      if (tip.cobrada_junto === true) return json({ status: tip.status }); // PI do pedido, não da gorjeta
      const pi = await stripe.paymentIntents.retrieve(tip.stripe_payment_intent_id);
      if (pi.metadata?.kind !== 'tip' || pi.metadata?.tip_id !== tipId) {
        return json({ error: 'payment_kind_mismatch' }, 400);
      }
      const status = await gravarEstado(admin, tipId, pi);
      return json({ status });
    }

    // ── REFUND (só admin) ────────────────────────────────────────────────────
    if (action === 'refund') {
      const { data: isAdmin } = await userClient.rpc('is_admin');
      if (isAdmin !== true) return json({ error: 'admin_only' }, 403);
      const tipId = String(body?.tipId ?? '');
      const reason = String(body?.reason ?? '').slice(0, 300) || 'reembolso pelo admin';
      const { data: tip } = await admin.from('tips').select(COLUNAS_GORJETA).eq('id', tipId).maybeSingle();
      if (!tip) return json({ error: 'tip_not_found' }, 404);
      if (tip.status === 'refunded') return json({ ok: true, note: 'already_refunded' });
      if (tip.status !== 'succeeded' || !tip.stripe_payment_intent_id) {
        return json({ error: 'not_refundable', status: tip.status }, 400);
      }
      // v2: gorjeta à parte → reembolso do PI dela; gorjeta cobrada junto com a compra →
      // reembolso PARCIAL do PI do pedido, só no valor da gorjeta. Reserva antes (nunca 2x).
      const r = await devolverUmaGorjeta(admin, stripeKey, tip as GorjetaParaDevolver, 'meio', reason, user.id);
      console.log('[charge-tip refund]', tipId, r.acao, r.cents, r.erro ?? '');
      if (r.acao === 'erro') return json({ error: 'refund_failed', details: r.erro }, 502);
      if (r.acao === 'ja_tratada') return json({ ok: true, note: 'already_refunded' });
      return json({
        ok: true, refundId: r.acao.startsWith('meio:') ? r.acao.slice(5) : null,
        refundStatus: 'succeeded', cents: r.cents, cobradaJunto: tip.cobrada_junto === true, note: r.acao,
      });
    }

    if (action !== 'create') return json({ error: 'unknown_action' }, 400);

    // ── CREATE ───────────────────────────────────────────────────────────────
    const ligado = await setting(admin, 'tips_enabled');
    if (ligado !== true && ligado !== 'true') return json({ error: 'tips_disabled' }, 403);

    const target = body?.target === 'tvde' ? 'tvde' : body?.target === 'order' ? 'order' : null;
    const id = typeof body?.id === 'string' ? body.id : null;
    const moment = body?.moment === 'checkout' ? 'checkout' : 'after';
    const amountCents = Math.round(Number(body?.amountCents ?? 0));
    const maxCents = Number(await setting(admin, 'tip_max_cents') ?? 5000) || 5000;
    if (!target || !id) return json({ error: 'target_and_id_required' }, 400);
    if (!Number.isFinite(amountCents) || amountCents < 50 || amountCents > maxCents) {
      return json({ error: 'amount_invalid', min: 50, max: maxCents }, 400);
    }

    // O alvo é SEMPRE lido no servidor.
    let provider = SEM_PRESTADOR;
    let method: string;
    let originalPi: string | null = null;
    if (target === 'order') {
      const { data: o } = await admin.from('orders')
        .select('id, user_id, status, payment_method, payment_intent_id, assigned_driver_id')
        .eq('id', id).maybeSingle();

      // v2 (30/10): cartão — a gorjeta pode ter ido no pagamento do pedido. Pedido que existe: só
      // conta o rascunho do PI DESTE pedido ("tentou cartão, desistiu, pagou com saldo" → o pedido não
      // tem esse PI → cobra-se à parte). Pedido que ainda não existe (o webhook está a criá-lo): conta
      // um rascunho deste cliente com a gorjeta, recente e ainda por usar.
      if (moment === 'checkout') {
        let doPi = false;
        let porUsar = false;
        if (o?.payment_intent_id) {
          const { data: rp } = await admin.from('payment_drafts').select('id')
            .eq('payment_intent_id', o.payment_intent_id).eq('user_id', user.id)
            .not('payload->>gorjeta_checkout_cents', 'is', null).limit(1).maybeSingle();
          doPi = !!rp;
        } else if (!o) {
          const desde = new Date(Date.now() - 30 * 60 * 1000).toISOString();
          const { data: rr } = await admin.from('payment_drafts').select('id')
            .eq('user_id', user.id).gte('created_at', desde).is('used_at', null)
            .not('payload->>gorjeta_checkout_cents', 'is', null).limit(1).maybeSingle();
          porUsar = !!rr;
        }
        if (gorjetaJaVaiNoCartao({ pedidoExiste: !!o, rascunhoDoPiDoPedidoComGorjeta: doPi, rascunhoRecentePorUsarComGorjeta: porUsar })) {
          return json({
            ok: true, note: 'already_exists', tipId: null, status: 'succeeded',
            cobradaJunto: true, method: 'card', requiresAction: false, clientSecret: null,
          });
        }
      }

      if (!o) return json({ error: 'order_not_found' }, 404);
      if (o.user_id !== user.id) return json({ error: 'order_not_yours' }, 403);
      if (moment === 'after' && o.status !== 'delivered') return json({ error: 'order_not_delivered' }, 400);
      if (['cancelled', 'rejected'].includes(o.status)) return json({ error: 'order_closed' }, 400);
      method = o.payment_method;
      originalPi = o.payment_intent_id ?? null;
      if (o.assigned_driver_id) provider = o.assigned_driver_id;

      // v2 (30/10): a gorjeta do carrinho pode já ir no pagamento do pedido (cobrada_junto) ou já ter
      // sido pedida: responde ok sem cobrar — nunca duas cobranças no mesmo pedido (apps antigas
      // continuam a chamar isto depois de criar o pedido). Sem a coluna nova, segue como antes.
      if (moment === 'checkout') {
        const { data: ja } = await admin.from('tips')
          .select('id, status, cobrada_junto, stripe_payment_intent_id')
          .eq('order_id', id).eq('moment', 'checkout')
          .in('status', ['pending', 'requires_action', 'succeeded'])
          .limit(1).maybeSingle();
        if (ja && (ja.cobrada_junto === true || ja.status === 'succeeded' || ja.stripe_payment_intent_id)) {
          return json({
            ok: true, note: 'already_exists', tipId: ja.id, status: ja.status,
            cobradaJunto: ja.cobrada_junto === true, method, requiresAction: false, clientSecret: null,
          });
        }
      }
    } else {
      const { data: r } = await admin.from('tvde_rides')
        .select('id, client_id, status, payment_method, payment_intent_id, driver_id')
        .eq('id', id).maybeSingle();
      if (!r) return json({ error: 'ride_not_found' }, 404);
      if (r.client_id !== user.id) return json({ error: 'ride_not_yours' }, 403);
      if (r.status !== 'finalizada' || !r.driver_id) return json({ error: 'ride_not_finished' }, 400);
      method = r.payment_method;
      originalPi = r.payment_intent_id ?? null;
      provider = r.driver_id;
    }
    if (method !== 'card' && method !== 'mbway') {
      // Dinheiro: depois não se oferece; no checkout é a RPC tip_registar_dinheiro.
      return json({ error: 'cash_not_supported_here' }, 400);
    }

    const { data: tip, error: insErr } = await admin.from('tips').insert({
      target,
      order_id: target === 'order' ? id : null,
      tvde_ride_id: target === 'tvde' ? id : null,
      client_user_id: user.id,
      provider_user_id: provider,
      amount_cents: amountCents,
      method, moment, status: 'pending',
    }).select('id').single();
    if (insErr || !tip) {
      const dup = String(insErr?.message ?? '').includes('tips_uma_viva');
      return json({ error: dup ? 'already_tipped' : 'tip_insert_failed', details: insErr?.message }, dup ? 409 : 500);
    }
    const tipId = tip.id as string;
    const meta = { kind: 'tip', tip_id: tipId, target, target_id: id, user_id: user.id, provider_user_id: provider };
    const desc = `Gorjeta Bora (${target === 'tvde' ? 'corrida' : 'pedido'} ${id.slice(0, 8)})`;

    // MB Way: pedido novo ao telemóvel do cliente.
    if (method === 'mbway') {
      let phone = typeof body?.phone === 'string' ? body.phone : '';
      if (!phone) {
        const { data: u } = await admin.from('users').select('phone').eq('id', user.id).maybeSingle();
        phone = (u?.phone as string | undefined) ?? '';
      }
      if (!phone) {
        await admin.from('tips').update({ status: 'failed', failure_reason: 'sem telemóvel' }).eq('id', tipId);
        return json({ error: 'phone_required', tipId }, 400);
      }
      try {
        const pi = await stripe.paymentIntents.create({
          amount: amountCents, currency: 'eur', description: desc,
          payment_method_types: ['mb_way'],
          payment_method_data: { type: 'mb_way', billing_details: { phone: toE164(phone) } },
          confirm: true, metadata: meta,
        }, { idempotencyKey: `tip-${tipId}` });
        const status = await gravarEstado(admin, tipId, pi);
        return json({ tipId, paymentIntentId: pi.id, status, method });
      } catch (e) {
        const m = e instanceof Error ? e.message : String(e);
        await admin.from('tips').update({ status: 'failed', failure_reason: m.slice(0, 300) }).eq('id', tipId);
        return json({ error: 'mbway_create_failed', details: m, tipId }, 400);
      }
    }

    // Cartão: 1) cartão escolhido; 2) o cartão do próprio pedido, se ficou no Customer;
    // 3) folha da Stripe (clientSecret).
    const customerId = await getOrCreateCustomer(admin, user.id);
    let pmId: string | null = typeof body?.saved_pm_id === 'string' ? body.saved_pm_id : null;
    let pmCustomer: string | null = customerId;
    if (!pmId && originalPi) {
      try {
        const orig = await stripe.paymentIntents.retrieve(originalPi);
        const origPm = typeof orig.payment_method === 'string' ? orig.payment_method : orig.payment_method?.id;
        const origCus = typeof orig.customer === 'string' ? orig.customer : orig.customer?.id;
        if (origPm && origCus) { pmId = origPm; pmCustomer = origCus; }
      } catch (_) { /* sem cartão reutilizável: segue para a folha */ }
    }

    try {
      let pi;
      if (pmId && pmCustomer) {
        pi = await stripe.paymentIntents.create({
          amount: amountCents, currency: 'eur', description: desc,
          customer: pmCustomer, payment_method: pmId,
          confirm: true, off_session: true,
          automatic_payment_methods: { enabled: true, allow_redirects: 'never' },
          metadata: meta,
        }, { idempotencyKey: `tip-${tipId}` });
      } else {
        pi = await stripe.paymentIntents.create({
          amount: amountCents, currency: 'eur', description: desc,
          ...(customerId ? { customer: customerId, setup_future_usage: 'off_session' as const } : {}),
          automatic_payment_methods: { enabled: true, allow_redirects: 'never' },
          metadata: meta,
        }, { idempotencyKey: `tip-${tipId}` });
      }
      const status = await gravarEstado(admin, tipId, pi);
      return json({
        tipId, paymentIntentId: pi.id, status, method,
        clientSecret: status === 'succeeded' ? null : pi.client_secret,
        requiresAction: status !== 'succeeded',
      });
    } catch (err) {
      // Cartão guardado pediu 3DS: devolve o PI para autenticar no telemóvel.
      // deno-lint-ignore no-explicit-any
      const anyErr = err as any;
      const authPi = anyErr?.raw?.payment_intent ?? anyErr?.payment_intent;
      if (authPi?.id) {
        await admin.from('tips').update({ status: 'requires_action', stripe_payment_intent_id: authPi.id }).eq('id', tipId);
        return json({ tipId, paymentIntentId: authPi.id, status: 'requires_action',
          clientSecret: authPi.client_secret, requiresAction: true, method });
      }
      const m = err instanceof Error ? err.message : String(err);
      await admin.from('tips').update({ status: 'failed', failure_reason: m.slice(0, 300) }).eq('id', tipId);
      return json({ error: 'card_charge_failed', details: m, tipId }, 400);
    }
  } catch (e) {
    const m = e instanceof Error ? e.message : String(e);
    console.error('[charge-tip] error:', m);
    return json({ error: 'server_error', details: m }, 500);
  }
});

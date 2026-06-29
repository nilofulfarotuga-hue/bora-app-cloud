// ============================================================================
// PROPOSTA (NÃO DEPLOYED) — client-cancel-order v25.1  · Bloco 4 Uber
// v25.1: #10 claim atómico (compare-and-swap) antes de mover dinheiro + refundFailed;
//        #2 reembolso limitado ao valor realmente pago (paidCents).
// Danilo: rever antes de fazer redeploy. Engine REAL do cancelamento do cliente.
// Base: v24 live. Mudanças ADITIVAS (preserva Stripe + wallet_debit_cancel_fee):
//   D1 grace 180s grátis SÓ enquanto não há estafeta atribuído.
//   D2 taxa pós-aceite 2,50€ = 1,50€ estafeta + 1,00€ Bora (ledger_entries).
//   D3 favor após is_purchase_finalized=true → bloqueia cancel (entrega segue).
//   Q1 reembolso à ESCOLHA do cliente: 'card' (Stripe→cartão) | 'wallet' (split).
//   E4 pós-pickup: mantém 100% taxa + posta ganho normal do estafeta no ledger.
// ----------------------------------------------------------------------------
import Stripe from 'https://esm.sh/stripe@14.21.0?target=deno';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';
import { getCancelFees, computeCancelFeeEur } from '../_shared/platform_settings.ts';
import { corsHeaders } from '../_shared/cors.ts';

const stripe = new Stripe(Deno.env.get('STRIPE_SECRET_KEY') ?? '', {
  apiVersion: '2023-10-16',
  httpClient: Stripe.createFetchHttpClient(),
});

const jsonResponse = (body: any, status = 200) =>
  new Response(JSON.stringify(body), {
    status, headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  });

type CancelTier = 'grace' | 'before_dispatch' | 'after_accept' | 'after_pickup' | 'invalid';

function baseTier(status: string): Exclude<CancelTier, 'grace'> {
  switch (status) {
    case 'created': case 'preparing': case 'callingDriver': return 'before_dispatch';
    case 'driverAccepted': return 'after_accept';
    case 'pickedUp': case 'onTheWay': return 'after_pickup';
    default: return 'invalid';
  }
}

async function getIntSetting(admin: any, key: string, fallback: number): Promise<number> {
  try {
    const { data } = await admin.from('platform_settings').select('value').eq('key', key).maybeSingle();
    const n = Number(data?.value);
    return isFinite(n) ? n : fallback;
  } catch (_) { return fallback; }
}

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders });

  const supabaseUrl = Deno.env.get('SUPABASE_URL') ?? '';
  const anonKey = Deno.env.get('SUPABASE_ANON_KEY') ?? '';
  const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '';
  if (!supabaseUrl || !serviceKey || !anonKey) return jsonResponse({ error: 'server_misconfigured' }, 500);

  let orderId: string | undefined;
  let reason: string | undefined;
  let refundTarget: 'card' | 'wallet' = 'card'; // Q1: default cartão (comportamento atual)
  try {
    const body = await req.json();
    orderId = body?.order_id;
    reason = typeof body?.reason === 'string' ? body.reason : undefined;
    if (body?.refund_target === 'wallet' || body?.refund_target === 'card') refundTarget = body.refund_target;
  } catch (_) { return jsonResponse({ error: 'invalid_body' }, 400); }

  if (!orderId || typeof orderId !== 'string') return jsonResponse({ error: 'order_id required' }, 400);
  if (reason !== undefined && reason !== null) {
    const trimmed = reason.trim();
    if (trimmed.length > 200) return jsonResponse({ error: 'reason_too_long', max: 200 }, 400);
    reason = trimmed;
  }

  const authHeader = req.headers.get('Authorization') ?? '';
  const token = authHeader.replace(/^Bearer\s+/i, '').trim();
  if (!token) return jsonResponse({ error: 'missing_token' }, 401);

  const userClient = createClient(supabaseUrl, anonKey, { global: { headers: { Authorization: `Bearer ${token}` } } });
  const { data: userData, error: authError } = await userClient.auth.getUser();
  const user = userData?.user;
  if (authError || !user) return jsonResponse({ error: 'unauthorized' }, 401);

  const admin = createClient(supabaseUrl, serviceKey);

  const { data: order, error: orderErr } = await admin
    .from('orders')
    .select('id, user_id, status, payment_method, payment_intent_id, payment_status, total, estimated_total, final_total, customer_total, refund_amount, stripe_charge_cents, wallet_applied_cents, tokens_applied_value_cents, created_at, assigned_driver_id, service_type, is_purchase_finalized, driver_earnings')
    .eq('id', orderId).maybeSingle();
  if (orderErr || !order) return jsonResponse({ error: 'order_not_found' }, 404);
  if (order.user_id !== user.id) return jsonResponse({ error: 'not_your_order' }, 403);

  // D3 — favor após compra confirmada: não cancela; a entrega segue.
  if (order.service_type === 'errand' && order.is_purchase_finalized === true) {
    return jsonResponse({ error: 'errand_already_purchased' }, 409);
  }

  const tierBase = baseTier(order.status);
  if (tierBase === 'invalid') return jsonResponse({ error: 'cannot_cancel_at_status', status: order.status }, 409);

  // D1 — grace só vale enquanto NÃO há estafeta atribuído (estado > tempo).
  const graceSeconds = await getIntSetting(admin, 'cancel_grace_seconds', 180);
  const ageSeconds = (Date.now() - new Date(order.created_at).getTime()) / 1000;
  const noDriver = order.assigned_driver_id == null;
  const tier: CancelTier = (tierBase === 'before_dispatch' && noDriver && ageSeconds <= graceSeconds)
    ? 'grace' : tierBase;

  const totalEur = Number(order.customer_total ?? order.final_total ?? order.total ?? order.estimated_total ?? 0);
  const fees = await getCancelFees();
  const feeEur = tier === 'grace' ? 0
    : Number(computeCancelFeeEur(tier as any, totalEur, fees).toFixed(2));

  // CORREÇÃO #2 — base do reembolso = valor REALMENTE pago (nunca o total teórico).
  // Cash → paidCents=0 → reembolso 0. Nunca devolve mais do que entrou.
  const paidCents = Number(order.stripe_charge_cents ?? 0) + Number(order.wallet_applied_cents ?? 0) + Number(order.tokens_applied_value_cents ?? 0);
  const nothingToRefund = paidCents === 0;
  const refundEur = Math.max(0, Math.min(
    Number((totalEur - feeEur).toFixed(2)),
    paidCents / 100,
  ));

  const now = new Date().toISOString();

  // CORREÇÃO #10 — claim ATÓMICO antes de mover qualquer dinheiro (compare-and-swap).
  // A 1ª execução "ganha" o pedido; uma 2ª (retry/duplo-toque/concorrência) afeta
  // 0 linhas → aborta sem creditar nem reembolsar (defesa contra crédito 2×).
  const { data: claimed, error: claimErr } = await admin
    .from('orders')
    .update({ status: 'cancelled', cancel_reason: reason ?? null, cancelled_at: now,
              cancel_fee: feeEur }) // taxa avaliada; reconciliada a 0 abaixo se cash não cobrar
    .eq('id', orderId).eq('user_id', user.id)
    .not('status', 'in', '("delivered","cancelled","rejected")')
    .select('id');
  if (claimErr) return jsonResponse({ error: 'db_claim_failed', details: claimErr.message }, 500);
  if (!claimed || claimed.length === 0) {
    return jsonResponse({ error: 'already_finalized', idempotent: true }, 409);
  }

  let refundId: string | undefined;
  let refundExecuted = false;
  let chargeMissing = false;
  let walletCredited = false;
  let cancelFeeDebited = false;
  let cancelFeeDebitResult: any = null;
  let refundFailed = false; // passo de dinheiro falhou DEPOIS do claim → admin alerta + refund manual
  const isTechnicalFailure = reason === 'payment_failed';

  if (nothingToRefund) {
    // CASH/MBWay-não-pago → débito wallet da taxa (mantém v19/v20).
    const isUnpaid = !isTechnicalFailure &&
      (order.payment_method === 'cash' || (order.payment_method === 'mbway' && order.payment_status !== 'paid'));
    if (feeEur > 0 && isUnpaid) {
      const { data: debitRpc, error: debitErr } = await admin.rpc('wallet_debit_cancel_fee', {
        p_user_id: user.id, p_order_id: orderId, p_fee_cents: Math.round(feeEur * 100), p_tier: tier,
      });
      if (debitErr) {
        console.error('[client-cancel] wallet_debit_cancel_fee failed:', debitErr);
        try { await admin.functions.invoke('notify-admin-urgent', { body: { kind: 'wallet_cancel_floor_exceeded', order_id: orderId, user_id: user.id, fee_cents: Math.round(feeEur * 100), tier, error: debitErr.message } }); } catch (_) {}
        chargeMissing = true;
      } else { cancelFeeDebited = true; cancelFeeDebitResult = debitRpc; }
    } else { chargeMissing = true; }
  } else if (refundEur > 0) {
    // Há valor a devolver. Q1: cliente escolhe destino. Pós-claim: falha NÃO faz
    // early-return (deixaria o pedido cancelado sem reembolso) → marca refundFailed.
    if (refundTarget === 'wallet') {
      // Crédito na wallet; Bora retém o valor Stripe. grace=100% livre; resto=split 80/20.
      const rpcName = tier === 'grace' ? 'wallet_credit_refund_full' : 'wallet_credit_refund_split';
      const { error: wErr } = await admin.rpc(rpcName, {
        p_order_id: orderId, p_user_id: user.id, p_total_cents: Math.round(refundEur * 100),
        p_reason: `cancel_${tier}`,
      });
      if (wErr) { console.error('[client-cancel] wallet credit failed:', wErr); refundFailed = true; }
      else walletCredited = true;
    } else if (order.payment_method === 'card' && order.payment_intent_id) {
      // Reembolso ao cartão via Stripe (idempotente).
      let piStatus: string | undefined; let piLatestCharge: string | null | undefined;
      try {
        const pi = await stripe.paymentIntents.retrieve(order.payment_intent_id);
        piStatus = pi.status; piLatestCharge = (pi.latest_charge as string | null) ?? null;
      } catch (e) { console.error('[client-cancel] pi retrieve failed:', e); refundFailed = true; }
      if (!refundFailed) {
        if (piStatus !== 'succeeded' || !piLatestCharge) { chargeMissing = true; }
        else {
          try {
            const idempotencyKey = `refund-${order.payment_intent_id}-${Math.round(refundEur * 100)}`;
            const refund = await stripe.refunds.create({ payment_intent: order.payment_intent_id, amount: Math.round(refundEur * 100) }, { idempotencyKey });
            refundId = refund.id; refundExecuted = true;
          } catch (e) { console.error('[client-cancel] stripe refund failed:', e); refundFailed = true; }
        }
      }
    } else {
      // pago com wallet/tokens → devolve sempre à wallet (não há cartão).
      const rpcName = tier === 'grace' ? 'wallet_credit_refund_full' : 'wallet_credit_refund_split';
      const { error: wErr } = await admin.rpc(rpcName, { p_order_id: orderId, p_user_id: user.id, p_total_cents: Math.round(refundEur * 100), p_reason: `cancel_${tier}` });
      if (wErr) { console.error('[client-cancel] wallet credit failed:', wErr); refundFailed = true; }
      else walletCredited = true;
    }
  }

  // Passo de dinheiro falhou DEPOIS do claim → pedido fica cancelado, mas alerta o
  // admin e marca refund pendente (o dinheiro do cliente nunca se perde).
  if (refundFailed) {
    try { await admin.functions.invoke('notify-admin-urgent', { body: { kind: 'cancel_refund_failed', order_id: orderId, user_id: user.id, refund_cents: Math.round(refundEur * 100), tier } }); } catch (_) {}
  }

  // D2 — pós-aceite: estafeta 1,50€ + Bora 1,00€ no ledger (taxa realmente cobrada).
  // E4 (pós-pickup): estafeta recebe o ganho NORMAL dele (já fez o trabalho).
  const driverShareCents = await getIntSetting(admin, 'cancel_fee_after_accept_driver_cents', 150);
  const feeCharged = (paidCents > 0) || cancelFeeDebited;
  if (order.assigned_driver_id && feeCharged) {
    try {
      if (tier === 'after_accept') {
        await admin.from('ledger_entries').insert([
          { user_id: order.assigned_driver_id, user_type: 'driver', order_id: orderId, amount: driverShareCents / 100, type: 'earning', reference: 'cancel_compensation' },
          { user_id: 'platform', user_type: 'platform', order_id: orderId, amount: (Math.round(feeEur * 100) - driverShareCents) / 100, type: 'commission', reference: 'cancel_fee_bora' },
        ]);
      } else if (tier === 'after_pickup') {
        const earn = Number(order.driver_earnings ?? 0);
        if (earn > 0) {
          await admin.from('ledger_entries').insert([
            { user_id: order.assigned_driver_id, user_type: 'driver', order_id: orderId, amount: earn, type: 'earning', reference: 'cancel_after_pickup_earning' },
          ]);
        }
      }
    } catch (e) { console.error('[client-cancel] ledger post failed:', e); /* não bloqueia */ }
  }

  // Estado/taxa/cancelled_at já gravados no claim atómico (CORREÇÃO #10). Aqui só os
  // campos de pagamento/reembolso. refundFailed → reusa 'cancelled_no_charge' (valor
  // já aceite na v24) + refund_status='failed' como sinal real para o admin.
  const newPaymentStatus = cancelFeeDebited ? 'cancelled_with_debt'
    : refundFailed ? 'cancelled_no_charge'
    : walletCredited ? (feeEur > 0 ? 'partial_refund' : 'refunded')
    : chargeMissing ? 'cancelled_no_charge'
    : refundEur <= 0 ? 'refunded'
    : refundExecuted ? (feeEur > 0 ? 'partial_refund' : 'refunded')
    : 'cancelled_no_charge';

  const patch: Record<string, any> = { payment_status: newPaymentStatus };
  if (refundExecuted) { patch.refund_amount = refundEur; patch.refund_method = 'stripe'; patch.refund_status = 'pending'; }
  if (walletCredited) { patch.refund_amount = refundEur; patch.refund_method = 'wallet'; patch.refund_status = 'completed'; }
  if (refundFailed) { patch.refund_amount = refundEur; patch.refund_status = 'failed'; }
  // Cash cuja taxa não foi cobrada (floor excedido) → cancel_fee volta a 0 (igual v24).
  if (chargeMissing && nothingToRefund) { patch.cancel_fee = 0; }

  const { error: updateErr } = await admin.from('orders').update(patch).eq('id', orderId).eq('user_id', user.id);
  if (updateErr) return jsonResponse({ error: 'db_update_failed', details: updateErr.message }, 500);

  return jsonResponse({
    ok: true, tier, fee_eur: (cancelFeeDebited || !nothingToRefund) ? feeEur : 0,
    refund_eur: (refundExecuted || walletCredited) ? refundEur : 0,
    refund_target: walletCredited ? 'wallet' : (refundExecuted ? 'card' : 'none'),
    refund_pending: refundFailed,
    refund_id: refundId ?? null, charge_missing: chargeMissing,
    nothing_to_refund: nothingToRefund, cancel_fee_debited: cancelFeeDebited, cancel_fee_debit: cancelFeeDebitResult,
  });
});

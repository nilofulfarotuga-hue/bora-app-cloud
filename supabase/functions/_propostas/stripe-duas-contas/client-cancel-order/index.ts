// ============================================================================
// PROPOSTA — supabase/functions/client-cancel-order/index.ts — v33 (duas contas Stripe)
// Missão stripe-empresa-2026-11-01 (autorização do Danilo 01/11/2026 22:03). A tranca do repo
// não deixa esta sessão escrever em supabase/functions/client-cancel-order/; este ficheiro é a
// versão completa pronta a copiar para lá e publicar (verify_jwt=true, como hoje).
// Base: v32 em produção (= repo).
//
// O que muda na v33 (e SÓ isto): o reembolso sai pela conta onde o dinheiro ENTROU
// (orders.stripe_account): retrieve do PI, refunds.create, lerPagoDoPedido e a devolução da
// gorjeta usam a chave dessa conta (os _shared cobranca_stripe/gorjeta_devolver também já
// escolhem a conta pela linha). Pedido pago ontem na pessoal é reembolsado na pessoal.
//
// client-cancel-order v25.1 (deploy v26) — Bloco 4 (cancelamento estilo Uber)
// v29 (ronda 04/10 A.2) — o pago lê-se com lerPagoDoPedido (stripe_charge_cents estava
// sempre a 0 → pedidos pagos a cartão/MB Way cancelavam SEM reembolso) e o reembolso
// reparte-se por fonte com repartirReembolso: Stripe até ao que a Stripe cobrou, o resto
// à carteira (wallet_credit_refund_split, chave = id do pedido).
// v30 (28/10/2026, regra do Danilo 28/10 18:24 — missao-geral-2026-10-28 bloco 2): por defeito
// volta ao meio original (cartão/MB Way); 'wallet' = 100% saldo (wallet_split_free_pct = 1).
// Os tokens gastos voltam como TOKENS pelo gatilho do banco (trg_orders_devolver_tokens) quando
// o servidor registou quais (tokens_applied_count > 0): então a taxa sai do dinheiro e o valor
// dos tokens sai da base do reembolso. PUBLICAR com o _shared/cobranca_stripe.ts v2.
// v32 (01/11/2026, missão zona-vermelha-2026-11-01, autorização do Danilo 01/11 19:56):
//   (a) chaves — as duas chamadas a notify-admin-urgent deixam de falhar em silêncio: passam por
//       chamarFuncao (_shared/chamadas.ts), que escreve a falha em e2e_log (fluxo edge-chamada-falhou);
//   (b) gorjetas (missão gorjetas-taxa-2026-10-30, Bloco B, autorização 30/10 13:40): a gorjeta do
//       pedido volta INTEIRA, fora da taxa de cancelamento, pelo caminho que o cliente escolheu para o
//       resto (refund_target: saldo Bora ou cartão/MB Way) — _shared/gorjeta_devolver.ts. A gorjeta
//       cobrada no mesmo pagamento da compra já não entra no reembolso da compra
//       (_shared/cobranca_stripe.ts v3). PUBLICAR com os _shared do repo, DEPOIS da migração
//       20261030145000 (tips.cobrada_junto).
// ============================================================================
import Stripe from 'https://esm.sh/stripe@14.21.0?target=deno';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';
import { getCancelFees, computeCancelFeeEur } from '../_shared/platform_settings.ts';
import { corsHeaders } from '../_shared/cors.ts';
import { lerPagoDoPedido, repartirReembolso, type Pago } from '../_shared/cobranca_stripe.ts'; // v29 (ronda 04/10 A.2)
import { secretKey } from '../_shared/keys.ts'
import { chamarFuncao } from '../_shared/chamadas.ts'; // v32 (a)
import { devolverGorjetasDoPedido } from '../_shared/gorjeta_devolver.ts'; // v32 (b) (gorjetas 30/10)
import { type ContaStripe, chaveSecreta, stripeDaLinha } from '../_shared/stripe_contas.ts'; // v33

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
  const serviceKey = secretKey() ?? '';
  if (!supabaseUrl || !serviceKey || !anonKey) return jsonResponse({ error: 'server_misconfigured' }, 500);

  let orderId: string | undefined;
  let reason: string | undefined;
  let refundTarget: 'card' | 'wallet' = 'card'; // regra 28/10: por defeito volta ao meio original
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

  // (o tipo do select é longo demais para o parser de tipos do supabase-js: lê-se como registo genérico)
  // deno-lint-ignore no-explicit-any
  const { data: order, error: orderErr } = await admin
    .from('orders')
    .select('id, user_id, status, payment_method, payment_intent_id, payment_status, total, estimated_total, final_total, customer_total, refund_amount, stripe_charge_cents, wallet_applied_cents, tokens_applied_value_cents, tokens_applied_count, created_at, assigned_driver_id, service_type, is_purchase_finalized, driver_earnings, stripe_account')
    .eq('id', orderId).maybeSingle() as { data: Record<string, any> | null; error: { message: string } | null };
  if (orderErr || !order) return jsonResponse({ error: 'order_not_found' }, 404);
  if (order.user_id !== user.id) return jsonResponse({ error: 'not_your_order' }, 403);

  if (order.service_type === 'errand' && order.is_purchase_finalized === true) {
    return jsonResponse({ error: 'errand_already_purchased' }, 409);
  }

  // v33 — a Stripe da conta onde este pedido foi pago. Sem chave dessa conta e com PI: pára ANTES
  // do claim (nada mudou) — melhor "tenta outra vez" do que cancelar sem devolver.
  let stripe: Stripe | null = null;
  let conta: ContaStripe = 'pessoal';
  try {
    ({ stripe, conta } = stripeDaLinha(order));
  } catch (e) {
    if (order.payment_intent_id) {
      console.error('[client-cancel] sem chave Stripe da conta', order.stripe_account, String(e));
      return jsonResponse({ error: 'payment_read_failed', retry: true, stripe_account: order.stripe_account ?? 'pessoal' }, 503);
    }
  }
  const chaveConta = chaveSecreta(conta);

  const tierBase = baseTier(order.status);
  if (tierBase === 'invalid') return jsonResponse({ error: 'cannot_cancel_at_status', status: order.status }, 409);

  const graceSeconds = await getIntSetting(admin, 'cancel_grace_seconds', 180);
  const ageSeconds = (Date.now() - new Date(order.created_at).getTime()) / 1000;
  const noDriver = order.assigned_driver_id == null;
  const tier: CancelTier = (tierBase === 'before_dispatch' && noDriver && ageSeconds <= graceSeconds)
    ? 'grace' : tierBase;

  const totalEur = Number(order.customer_total ?? order.final_total ?? order.total ?? order.estimated_total ?? 0);
  const fees = await getCancelFees();
  const feeEur = tier === 'grace' ? 0
    : Number(computeCancelFeeEur(tier as any, totalEur, fees).toFixed(2));

  // v29 (ronda 04/10 A.2) — o pago por fonte. Se stripe_charge_cents estiver a 0 e houver PI,
  // lerPagoDoPedido lê a Stripe e grava (registar_cobranca_stripe). Se a leitura falhar,
  // pára ANTES do claim (nada mudou) — melhor "tenta outra vez" do que cancelar sem devolver.
  let pago: Pago;
  try {
    pago = await lerPagoDoPedido(admin, chaveConta, orderId); // v33: chave da conta do pedido
  } catch (e) {
    console.error('[client-cancel] lerPagoDoPedido falhou:', e);
    return jsonResponse({ error: 'payment_read_failed', retry: true }, 503);
  }
  // v30: com o _shared v2, pago.tokensCents é sempre 0 (tokens não são dinheiro)
  const paidCents = pago.stripeCents + pago.walletCents + pago.tokensCents;
  const nothingToRefund = paidCents === 0;
  // v30 (regra 28/10): tokens registados pelo servidor voltam como TOKENS (gatilho do banco);
  // a taxa sai do dinheiro, por isso o valor deles sai da base. Contagem 0 = como antes.
  const tokensDevolvidos = Math.max(0, Number(order.tokens_applied_count ?? 0));
  const tokensVoltamEur = tokensDevolvidos > 0
    ? Math.max(0, Number(order.tokens_applied_value_cents ?? 0)) / 100 : 0;
  const refundEur = Math.max(0, Math.min(
    Number((totalEur - feeEur - tokensVoltamEur).toFixed(2)),
    paidCents / 100,
  ));

  const now = new Date().toISOString();

  // CORRECAO #10 — claim ATOMICO antes de mover dinheiro (compare-and-swap).
  const { data: claimed, error: claimErr } = await admin
    .from('orders')
    .update({ status: 'cancelled', cancel_reason: reason ?? null, cancelled_at: now, cancel_fee: feeEur })
    .eq('id', orderId).eq('user_id', user.id)
    .not('status', 'in', '("delivered","cancelled","rejected")')
    .or('service_type.neq.errand,is_purchase_finalized.not.is.true')
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
  let refundFailed = false;
  let refundStripeCents = 0;   // v29 (ronda 04/10 A.2) — parte devolvida ao cartão/MB Way
  let refundCarteiraCents = 0; // v29 (ronda 04/10 A.2) — parte creditada na carteira
  const isTechnicalFailure = reason === 'payment_failed';

  if (nothingToRefund) {
    const isUnpaid = !isTechnicalFailure &&
      (order.payment_method === 'cash' || (order.payment_method === 'mbway' && order.payment_status !== 'paid'));
    if (feeEur > 0 && isUnpaid) {
      const { data: debitRpc, error: debitErr } = await admin.rpc('wallet_debit_cancel_fee', {
        p_user_id: user.id, p_order_id: orderId, p_fee_cents: Math.round(feeEur * 100), p_tier: tier,
      });
      if (debitErr) {
        console.error('[client-cancel] wallet_debit_cancel_fee failed:', debitErr);
        await chamarFuncao(admin, 'client-cancel-order', 'notify-admin-urgent', { kind: 'wallet_cancel_floor_exceeded', order_id: orderId, user_id: user.id, fee_cents: Math.round(feeEur * 100), tier, error: debitErr.message }); // v32 (a): falha fica em e2e_log
        chargeMissing = true;
      } else { cancelFeeDebited = true; cancelFeeDebitResult = debitRpc; }
    } else { chargeMissing = true; }
  } else if (refundEur > 0) {
    if (refundTarget === 'wallet') {
      const rpcName = tier === 'grace' ? 'wallet_credit_refund_full' : 'wallet_credit_refund_split';
      // v29 (ronda 04/10 A.2) — o split leva chave = id do pedido (não credita 2x).
      const wArgs: Record<string, unknown> = {
        p_order_id: orderId, p_user_id: user.id, p_total_cents: Math.round(refundEur * 100), p_reason: `cancel_${tier}`,
      };
      if (rpcName === 'wallet_credit_refund_split') wArgs.p_idempotency_key = orderId;
      const { error: wErr } = await admin.rpc(rpcName, wArgs);
      if (wErr) { console.error('[client-cancel] wallet credit failed:', wErr); refundFailed = true; }
      else { walletCredited = true; refundCarteiraCents = Math.round(refundEur * 100); }
    } else {
      // v29 (ronda 04/10 A.2) — reparte por fonte (cartão E MB Way vão à Stripe até ao
      // que a Stripe cobrou; o resto — só a parte paga com saldo — vai à carteira).
      const parte = repartirReembolso(Math.round(refundEur * 100), pago);
      if (parte.stripeCents > 0 && pago.piId) {
        let piStatus: string | undefined; let piLatestCharge: string | null | undefined;
        if (!stripe) { console.error('[client-cancel] sem Stripe da conta', conta); refundFailed = true; }
        if (!refundFailed) {
          try {
            const pi = await stripe!.paymentIntents.retrieve(pago.piId);
            piStatus = pi.status; piLatestCharge = (pi.latest_charge as string | null) ?? null;
          } catch (e) { console.error('[client-cancel] pi retrieve failed:', e); refundFailed = true; }
        }
        if (!refundFailed) {
          if (piStatus !== 'succeeded' || !piLatestCharge) { chargeMissing = true; }
          else {
            try {
              const idempotencyKey = `refund-${pago.piId}-${parte.stripeCents}`;
              const refund = await stripe!.refunds.create({ payment_intent: pago.piId, amount: parte.stripeCents }, { idempotencyKey });
              refundId = refund.id; refundExecuted = true; refundStripeCents = parte.stripeCents;
            } catch (e) { console.error('[client-cancel] stripe refund failed:', e); refundFailed = true; }
          }
        }
      }
      if (parte.carteiraCents > 0) {
        // v30 (regra 28/10): a parte paga com saldo volta 100% ao saldo. Na graça
        // wallet_credit_refund_full; fora da graça wallet_credit_refund_split (100% saldo com
        // wallet_split_free_pct = 1) com chave = id do pedido. O 2.º toque já é travado pelo
        // UPDATE atómico do estado (409).
        const graca = tier === 'grace';
        const cArgs: Record<string, unknown> = {
          p_order_id: orderId, p_user_id: user.id, p_total_cents: parte.carteiraCents,
          p_reason: `cancel_${tier}`,
        };
        if (!graca) cArgs.p_idempotency_key = orderId;
        const { error: wErr } = await admin.rpc(
          graca ? 'wallet_credit_refund_full' : 'wallet_credit_refund_split', cArgs);
        if (wErr) { console.error('[client-cancel] wallet credit failed:', wErr); refundFailed = true; }
        else { walletCredited = true; refundCarteiraCents = parte.carteiraCents; }
      }
    }
  }

  if (refundFailed) {
    await chamarFuncao(admin, 'client-cancel-order', 'notify-admin-urgent', { kind: 'cancel_refund_failed', order_id: orderId, user_id: user.id, refund_cents: Math.round(refundEur * 100), tier, stripe_account: conta }); // v32 (a): falha fica em e2e_log
  }

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
    } catch (e) { console.error('[client-cancel] ledger post failed:', e); }
  }

  const newPaymentStatus = cancelFeeDebited ? 'cancelled_with_debt'
    : refundFailed ? 'cancelled_no_charge'
    : walletCredited ? (feeEur > 0 ? 'partial_refund' : 'refunded')
    : chargeMissing ? 'cancelled_no_charge'
    : refundEur <= 0 ? 'refunded'
    : refundExecuted ? (feeEur > 0 ? 'partial_refund' : 'refunded')
    : 'cancelled_no_charge';

  const patch: Record<string, any> = { payment_status: newPaymentStatus };
  // v29 (ronda 04/10 A.2) — refund_amount = o que se moveu mesmo (Stripe + carteira).
  // refund_method só aceita stripe|wallet|none: misto fica 'stripe' (a parte que demora).
  const movidoEur = (refundStripeCents + refundCarteiraCents) / 100;
  if (walletCredited) { patch.refund_amount = movidoEur; patch.refund_method = 'wallet'; patch.refund_status = 'completed'; }
  if (refundExecuted) { patch.refund_amount = movidoEur; patch.refund_method = 'stripe'; patch.refund_status = 'pending'; }
  if (refundFailed) {
    patch.refund_amount = refundEur;
    // v30: diz ao Reprocessar para onde vai (o que o cliente escolheu); se a Stripe já devolveu
    // e só a carteira falhou → 'needs_review' (o Reprocessar só pega em 'failed' e não repete a Stripe)
    patch.refund_method = refundTarget === 'wallet' ? 'wallet' : 'stripe';
    patch.refund_status = refundExecuted ? 'needs_review' : 'failed';
  }
  if (chargeMissing && nothingToRefund) { patch.cancel_fee = 0; }

  const { error: updateErr } = await admin.from('orders').update(patch).eq('id', orderId).eq('user_id', user.id);
  if (updateErr) return jsonResponse({ error: 'db_update_failed', details: updateErr.message }, 500);

  // v32 (b) (gorjetas 30/10): a gorjeta volta INTEIRA, fora da taxa, pelo caminho escolhido. Nunca falha
  // o cancelamento: o que ficar por devolver a conferência de 15 em 15 min volta a tentar.
  // v33: a chave é a da conta do pedido; cada gorjeta com conta própria escolhe a sua (_shared).
  const gorjeta = await devolverGorjetasDoPedido(
    admin, chaveConta, orderId,
    refundTarget === 'wallet' ? 'carteira' : 'meio', `cancelado pelo cliente (${tier})`, user.id,
  );
  if (gorjeta.erros > 0) console.error('[client-cancel] gorjeta por devolver:', JSON.stringify(gorjeta.itens));

  return jsonResponse({
    ok: true, tier, fee_eur: (cancelFeeDebited || !nothingToRefund) ? feeEur : 0,
    refund_eur: (refundExecuted || walletCredited) ? (refundStripeCents + refundCarteiraCents) / 100 : 0,
    refund_target: (walletCredited && refundExecuted) ? 'card+wallet' : walletCredited ? 'wallet' : (refundExecuted ? 'card' : 'none'),
    refund_card_eur: refundStripeCents / 100, refund_wallet_eur: refundCarteiraCents / 100, // v29 (ronda 04/10 A.2)
    refund_meio: order.payment_method ?? null, // v30: 'mbway' = na hora; 'card' = 5 a 10 dias úteis
    tokens_devolvidos: tokensDevolvidos,      // v30: voltam como tokens (gatilho do banco)
    gorjeta_devolvida_cents: gorjeta.devolvidaCents, // v32: gorjeta inteira, fora da taxa
    gorjeta_carteira_cents: gorjeta.carteiraCents,   // v32: parte que foi para o saldo
    stripe_account: conta,                            // v33
    refund_pending: refundFailed,
    refund_id: refundId ?? null, charge_missing: chargeMissing,
    nothing_to_refund: nothingToRefund, cancel_fee_debited: cancelFeeDebited, cancel_fee_debit: cancelFeeDebitResult,
  });
});

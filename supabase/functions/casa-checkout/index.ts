// ============================================================================
// casa-checkout — pagamento da CASA & MANUTENÇÃO por cartão e MB Way (m11, 09/11/2026)
// ----------------------------------------------------------------------------
// ⚠️ LISTA VERMELHA: cobra dinheiro real. Escolha do Danilo (09/11): "Cartão e MB Way" pelo caminho
//    da Limpeza. Só se publica com o "autorizo" dele; e só cobra com o interruptor
//    platform_settings.casa_pagamento_app_ativo = true.
//
// Molde: carwash-checkout / cleaning-checkout (Edge Stripe ISOLADA). NÃO toca em stripe-webhook,
// create-payment-intent, finalizePurchase, carteira nem ledger. verify_jwt = true.
//
// Ações (POST JSON):
//   { action:'create',       pedidoId, saved_pm_id? }  -> cartão (cobra já; guarda/reusa o cartão)
//   { action:'create_mbway', pedidoId, phone }         -> MB Way (pedido na app MB WAY)
//   { action:'mark_held',    pedidoId, paymentIntentId } -> lê o pagamento na Stripe e confirma no banco
//   { action:'reverse',      pedidoId }                -> pedido cancelado/expirado: devolve o que passar da taxa
//
// O valor cobrado vem SEMPRE de casa_pedidos.total_cents. Nunca da app.
// O pedido só vai aos profissionais quando o banco confirma o pagamento (casa_pagamento_confirmado).
// ============================================================================

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';
import { secretKey } from '../_shared/keys.ts';
import { STRIPE_MODE, localizarPaymentIntent, obterOuCriarClienteStripe, respostaConta, stripeDaLinha, stripeParaNovoPagamento } from '../_shared/stripe_contas.ts';
import { decidirCriacao, devolucaoCents, estadosPagos, motivoRecusaMarcar, telefoneE164 } from './regras.ts';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};

const supabaseUrl = Deno.env.get('SUPABASE_URL') ?? '';
const anonKey = Deno.env.get('SUPABASE_ANON_KEY') ?? '';
const serviceKey = secretKey() ?? '';

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  });
}

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders });

  try {
    const token = (req.headers.get('Authorization') ?? '').replace('Bearer ', '');
    if (!token) return json({ error: 'missing_token' }, 401);

    const userClient = createClient(supabaseUrl, anonKey, {
      global: { headers: { Authorization: `Bearer ${token}` } },
    });
    const { data: userData, error: authError } = await userClient.auth.getUser();
    const user = userData?.user;
    if (authError || !user) return json({ error: 'unauthorized' }, 401);

    const body = await req.json().catch(() => ({}));
    const action = typeof body?.action === 'string' ? body.action : null;
    const pedidoId = typeof body?.pedidoId === 'string' ? body.pedidoId : null;
    if (!action || !pedidoId) return json({ error: 'action_and_pedidoId_required' }, 400);

    const admin = createClient(supabaseUrl, serviceKey);
    const { data: pedido, error: pErr } = await admin.from('casa_pedidos').select('*').eq('id', pedidoId).single();
    if (pErr || !pedido) return json({ error: 'pedido_not_found' }, 404);

    const doCliente = pedido.client_user_id === user.id;

    // ── REVERSE: o cliente, ou o painel (admin), depois de cancelado/expirado ──
    if (action === 'reverse') {
      if (!doCliente) {
        const { data: ehAdmin } = await userClient.rpc('is_admin');
        if (ehAdmin !== true) return json({ error: 'pedido_not_yours' }, 403);
      }
      return await devolver(admin, pedido);
    }

    if (!doCliente) return json({ error: 'pedido_not_yours' }, 403);

    // ── CREATE / CREATE_MBWAY: portão antes de falar com a Stripe ───────────────
    if (action === 'create' || action === 'create_mbway') {
      const { data: interruptor } = await admin.from('platform_settings')
        .select('value').eq('key', 'casa_pagamento_app_ativo').maybeSingle();
      const recusa = decidirCriacao({
        action,
        interruptorLigado: interruptor?.value === true,
        estado: pedido.estado,
        paymentStatus: pedido.payment_status,
        paymentMethod: pedido.payment_method,
        totalCents: Number(pedido.total_cents ?? 0),
        jaTemPagamento: typeof pedido.stripe_payment_intent_id === 'string' && pedido.stripe_payment_intent_id.startsWith('pi_'),
      });
      if (recusa) return json({ error: recusa }, 400);

      const amountCents = Number(pedido.total_cents);
      const { stripe, conta } = await stripeParaNovoPagamento(admin, { body, kind: 'casa', origem: 'casa-checkout' });
      const meta = { kind: 'casa', pedido_id: pedidoId, user_id: user.id, bora_conta: conta };

      if (action === 'create') {
        const customerId = await obterOuCriarClienteStripe(admin, conta, user.id);
        const savedPmId = typeof body?.saved_pm_id === 'string' ? body.saved_pm_id : null;
        let pi;
        try {
          pi = savedPmId && customerId
            ? await stripe.paymentIntents.create({
              amount: amountCents, currency: 'eur', customer: customerId, payment_method: savedPmId,
              confirm: true, off_session: true,
              automatic_payment_methods: { enabled: true, allow_redirects: 'never' }, metadata: meta,
            })
            : await stripe.paymentIntents.create({
              amount: amountCents, currency: 'eur',
              ...(customerId ? { customer: customerId, setup_future_usage: 'off_session' as const } : {}),
              automatic_payment_methods: { enabled: true, allow_redirects: 'never' }, metadata: meta,
            });
        } catch (err) {
          // cartão guardado que pede 3DS: devolve o pagamento para confirmar com a pessoa.
          // deno-lint-ignore no-explicit-any
          const anyErr = err as any;
          const authPi = anyErr?.raw?.payment_intent ?? anyErr?.payment_intent;
          if (authPi?.id) {
            return json({
              clientSecret: authPi.client_secret, paymentIntentId: authPi.id, amountCents,
              status: authPi.status, requiresAction: true, ...respostaConta(conta),
            });
          }
          return json({ error: 'stripe_create_failed', details: err instanceof Error ? err.message : String(err) }, 400);
        }
        console.log('[casa-checkout create]', pedidoId, `amount=€${(amountCents / 100).toFixed(2)}`, `mode=${STRIPE_MODE}`);
        return json({ clientSecret: pi.client_secret, paymentIntentId: pi.id, amountCents, status: pi.status, ...respostaConta(conta) });
      }

      const telefone = telefoneE164(typeof body?.phone === 'string' ? body.phone : '');
      if (!telefone) return json({ error: 'phone_required' }, 400);
      let pi;
      try {
        pi = await stripe.paymentIntents.create({
          amount: amountCents, currency: 'eur', payment_method_types: ['mb_way'],
          payment_method_data: { type: 'mb_way', billing_details: { phone: telefone } },
          confirm: true, metadata: meta,
        });
      } catch (e) {
        return json({ error: 'mbway_create_failed', details: e instanceof Error ? e.message : String(e) }, 400);
      }
      console.log('[casa-checkout create_mbway]', pedidoId, `amount=€${(amountCents / 100).toFixed(2)}`, `status=${pi.status}`);
      return json({ paymentIntentId: pi.id, status: pi.status, amountCents, stripe_account: conta });
    }

    // ── MARK_HELD: lê o pagamento na Stripe e confirma no banco ────────────────
    if (action === 'mark_held') {
      const piId = typeof body?.paymentIntentId === 'string' ? body.paymentIntentId : null;
      if (!piId || !piId.startsWith('pi_')) return json({ error: 'payment_intent_required' }, 400);
      const { conta: preferida } = stripeDaLinha(pedido);
      const achado = await localizarPaymentIntent(piId, preferida);
      if (!achado) return json({ error: 'payment_intent_not_found' }, 404);
      const pi = achado.pi;

      const recusa = motivoRecusaMarcar({
        metaKind: pi.metadata?.kind, metaPedido: pi.metadata?.pedido_id, metaUser: pi.metadata?.user_id,
        pedidoId, userId: user.id, amount: pi.amount, totalCents: Number(pedido.total_cents ?? 0),
      });
      if (recusa) return json({ error: recusa }, recusa === 'payment_owner_mismatch' ? 403 : 400);
      if (!estadosPagos.includes(pi.status)) return json({ error: 'payment_not_completed', status: pi.status }, 402);

      const { data: r, error: rpcErr } = await admin.rpc('casa_pagamento_confirmado', {
        p_pedido_id: pedidoId, p_payment_intent_id: pi.id, p_amount_cents: pi.amount,
        p_stripe_account: achado.conta, p_origem: 'casa-checkout',
      });
      if (rpcErr) return json({ error: 'confirmar_falhou', details: rpcErr.message }, 500);

      // Segundo pagamento no mesmo pedido (dois toques, duas apps): devolve-se este por inteiro.
      if (r?.erro === 'outro_pagamento_ja_retido') {
        const { stripe } = stripeDaLinha({ stripe_account: achado.conta });
        await stripe.refunds.create({ payment_intent: pi.id, metadata: { kind: 'casa', pedido_id: pedidoId, motivo: 'duplicado' } },
          { idempotencyKey: `casa-duplicado-${pi.id}` });
        return json({ error: 'pagamento_duplicado_devolvido' }, 409);
      }
      if (r?.ok !== true) return json({ error: r?.erro ?? 'confirmar_recusado', detalhe: r }, 400);

      // O pedido já tinha caído (30 min sem pagar ou cancelado): devolve-se logo.
      if (r?.reembolsar === true) {
        const { data: atual } = await admin.from('casa_pedidos').select('*').eq('id', pedidoId).single();
        const dev = await devolver(admin, atual ?? pedido);
        return json({ ok: false, error: 'pedido_ja_tinha_caido', devolucao: await dev.json() }, 409);
      }
      return json({ ok: true, estado: r?.estado, status: pi.status });
    }

    return json({ error: 'invalid_action', details: "use 'create', 'create_mbway', 'mark_held' ou 'reverse'" }, 400);
  } catch (err) {
    const message = err instanceof Error ? err.message : String(err);
    console.error('[casa-checkout] error:', message);
    return json({ error: message }, 500);
  }
});

// Devolve o que passar da taxa de cancelamento. Segura de repetir: se a cobrança já tem devolução,
// não devolve outra vez; e a Stripe recebe uma chave de idempotência fixa por pedido.
// deno-lint-ignore no-explicit-any
async function devolver(admin: any, pedido: any): Promise<Response> {
  if (!['cancelado', 'expirado'].includes(pedido.estado)) return json({ error: 'pedido_not_cancelled' }, 400);
  if (pedido.payment_status === 'estornado') return json({ ok: true, note: 'already_reversed' });
  if (!pedido.stripe_payment_intent_id) return json({ ok: true, note: 'nothing_to_reverse' });

  const { stripe } = stripeDaLinha(pedido);
  let pi;
  try {
    pi = await stripe.paymentIntents.retrieve(pedido.stripe_payment_intent_id, { expand: ['latest_charge'] });
  } catch (_) {
    return json({ error: 'payment_intent_not_found' }, 404);
  }
  if (pi.status !== 'succeeded') return json({ ok: true, note: 'no_action_for_status', status: pi.status });

  // deno-lint-ignore no-explicit-any
  const charge: any = pi.latest_charge;
  const jaDevolvido = Number(charge?.amount_refunded ?? 0);
  const conta = devolucaoCents({
    totalCents: Number(pedido.total_cents ?? 0),
    cobradoCents: Number(pi.amount_received ?? pi.amount ?? 0),
    taxaCents: Number(pedido.cancel_fee_cents ?? 0),
    jaDevolvidoCents: jaDevolvido,
  });
  if (conta.jaDevolvido) {
    await admin.rpc('casa_reembolso_registado', { p_pedido_id: pedido.id, p_refund_ref: 'ja_devolvido', p_valor_cents: jaDevolvido });
    return json({ ok: true, note: 'already_reversed', refundedCents: jaDevolvido });
  }
  if (conta.devolver <= 0) return json({ ok: true, note: 'fee_equals_total' });

  const r = await stripe.refunds.create({
    payment_intent: pi.id, amount: conta.devolver, metadata: { kind: 'casa', pedido_id: pedido.id },
  }, { idempotencyKey: `casa-reverse-${pedido.id}` });
  const { error } = await admin.rpc('casa_reembolso_registado', {
    p_pedido_id: pedido.id, p_refund_ref: r.id, p_valor_cents: conta.devolver,
  });
  if (error) console.error('[casa-checkout reverse] registo falhou (a devolução na Stripe foi feita):', error.message, pedido.id, r.id);
  console.log('[casa-checkout reverse]', pedido.id, `devolvido=€${(conta.devolver / 100).toFixed(2)}`, r.status);
  return json({ ok: true, note: 'reversed', refundStatus: r.status, backCents: conta.devolver });
}

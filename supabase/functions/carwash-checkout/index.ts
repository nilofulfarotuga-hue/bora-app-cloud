// ============================================================================
// carwash-checkout — pagamento da vertical LAVAGEM AUTO
// ----------------------------------------------------------------------------
// LISTA VERMELHA: cobra dinheiro real. Autorizacao expressa do Danilo
// (2026-08-27): "toda categoria nova nasce com cartao + MB WAY + dinheiro a
// funcionar a serio desde o inicio".
//
// Molde: cleaning-checkout v5 (ACTIVE), lida com get_edge_function — nao do
// repo. Padrao: Edge Fn Stripe ISOLADA. NAO toca em stripe-webhook v17+,
// create-payment-intent, finalizePurchase nem em qualquer funcao de reparticao.
//
// DIFERENCA DELIBERADA PARA O MOLDE — o PORTAO ANTES DO STRIPE:
//   o cleaning-checkout le total_cents da reserva e cobra. Aqui, ANTES de criar
//   qualquer PaymentIntent, chama-se a RPC `carwash_payment_precheck`, que
//   valida no servidor: categoria aberta, cartao/MBWay ligados, pedido existe e
//   e do proprio, ainda por pagar, pedido vivo, servico ligado, PRECO igual ao
//   carwash_quote de agora, morada dentro do raio e minimo da Stripe.
//   Licao de 31/07: o PaymentIntent nasceu antes da order e o cliente pagou por
//   um pedido que rebentou. Nunca ao contrario.
//
// Accoes (POST JSON):
//   { action:'create',       bookingId, saved_pm_id? }  -> cartao (cobra ja)
//   { action:'create_mbway', bookingId, phone }         -> MB WAY (push na app)
//   { action:'mark_held',    bookingId, paymentIntentId }
//   { action:'reverse',      bookingId }                -> cancelado: estorna
//
// O valor cobrado vem SEMPRE do servidor. Nunca do Dart.
// ============================================================================

import Stripe from 'https://esm.sh/stripe@14.21.0?target=deno';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers':
    'authorization, x-client-info, apikey, content-type',
};

const STRIPE_MODE = (Deno.env.get('BORA_STRIPE_MODE') ?? 'live').toLowerCase();
const stripeKey = STRIPE_MODE === 'test'
  ? (Deno.env.get('STRIPE_TEST_SECRET_KEY') ?? '')
  : (Deno.env.get('STRIPE_SECRET_KEY') ?? '');
const stripe = new Stripe(stripeKey, { apiVersion: '2023-10-16' });

const supabaseUrl = Deno.env.get('SUPABASE_URL') ?? '';
const anonKey = Deno.env.get('SUPABASE_ANON_KEY') ?? '';
const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '';

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

// Carteira Unica: Stripe Customer idempotente por utilizador (service-role;
// a RLS bloqueia update user-side de users.stripe_customer_id).
// deno-lint-ignore no-explicit-any
async function getOrCreateCustomer(admin: any, userId: string): Promise<string | null> {
  try {
    const { data: userRow } = await admin
      .from('users').select('stripe_customer_id, email, name')
      .eq('id', userId).maybeSingle();
    if (userRow?.stripe_customer_id) return userRow.stripe_customer_id as string;
    const customer = await stripe.customers.create({
      email: (userRow?.email as string | undefined) ?? undefined,
      name: (userRow?.name as string | undefined) ?? undefined,
      metadata: { supabase_uid: userId },
    });
    const { error: updErr } = await admin
      .from('users').update({ stripe_customer_id: customer.id })
      .eq('id', userId).is('stripe_customer_id', null);
    if (updErr) {
      const { data: refetch } = await admin
        .from('users').select('stripe_customer_id').eq('id', userId).maybeSingle();
      const winner = refetch?.stripe_customer_id as string | undefined;
      if (winner && winner !== customer.id) {
        try { await stripe.customers.del(customer.id); } catch (_) { /* swallow */ }
        return winner;
      }
    }
    return customer.id;
  } catch (err) {
    console.error('[carwash-checkout] getOrCreateCustomer error:', err);
    return null;
  }
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
    const bookingId = typeof body?.bookingId === 'string' ? body.bookingId : null;
    if (!action || !bookingId) return json({ error: 'action_and_bookingId_required' }, 400);

    const admin = createClient(supabaseUrl, serviceKey);

    // ── REVERSE nao passa pelo portao (o pedido ja esta cancelado) ──────────
    if (action === 'reverse') {
      const { data: booking, error: bErr } = await admin
        .from('carwash_bookings').select('*').eq('id', bookingId).single();
      if (bErr || !booking) return json({ error: 'booking_not_found' }, 404);
      if (booking.client_user_id !== user.id) return json({ error: 'booking_not_yours' }, 403);
      if (booking.status !== 'cancelled_client') {
        return json({ error: 'booking_not_cancelled' }, 400);
      }
      if (!booking.stripe_payment_intent_id) return json({ ok: true, note: 'nothing_to_reverse' });

      let pi;
      try { pi = await stripe.paymentIntents.retrieve(booking.stripe_payment_intent_id); }
      catch (_) { return json({ error: 'payment_intent_not_found' }, 404); }

      const amountCents = Number(booking.total_cents ?? 0);
      const feeCents = Number(booking.cancel_fee_cents ?? 0);

      if (pi.status === 'requires_capture') {
        if (feeCents <= 0) {
          await stripe.paymentIntents.cancel(pi.id);
          return json({ ok: true, note: 'hold_released' });
        }
        const captured = await stripe.paymentIntents.capture(pi.id, {
          amount_to_capture: Math.max(feeCents, 50),
        });
        return json({ ok: true, note: 'fee_captured', status: captured.status });
      }

      if (pi.status === 'succeeded') {
        const backCents = amountCents - feeCents;
        if (backCents <= 0) return json({ ok: true, note: 'fee_equals_total' });
        const r = await stripe.refunds.create({
          payment_intent: pi.id,
          amount: backCents,
          metadata: { kind: 'carwash', booking_id: bookingId },
        });
        return json({ ok: true, note: 'reversed', refundStatus: r.status, backCents });
      }

      return json({ ok: true, note: 'no_action_for_status', status: pi.status });
    }

    // ══════════════════════════════════════════════════════════════════════
    // PORTAO ANTES DO STRIPE — nada toca na Stripe antes disto passar.
    // ══════════════════════════════════════════════════════════════════════
    const { data: gate, error: gateErr } = await admin
      .rpc('carwash_payment_precheck', { p_booking_id: bookingId, p_user_id: user.id });

    if (gateErr) {
      console.error('[carwash-checkout] precheck falhou:', gateErr.message);
      return json({ error: 'precheck_failed', details: gateErr.message }, 500);
    }
    if (!gate?.ok) {
      console.log('[carwash-checkout] PORTAO recusou:', JSON.stringify(gate));
      const status = gate?.error === 'booking_not_yours' ? 403
        : gate?.error === 'booking_not_found' ? 404 : 400;
      return json({ error: gate?.error ?? 'precheck_rejected', details: gate }, status);
    }

    // O valor vem do servidor. Nunca do Dart.
    const amountCents = Number(gate.amount_cents);
    const paymentMethod = String(gate.payment_method);

    // ── CREATE (cartao, cobra na reserva; guarda/reusa cartao) ─────────────
    if (action === 'create') {
      if (paymentMethod !== 'card') return json({ error: 'not_card_booking' }, 400);

      const customerId = await getOrCreateCustomer(admin, user.id);
      const savedPmId = typeof body?.saved_pm_id === 'string' ? body.saved_pm_id : null;
      const meta = { kind: 'carwash', booking_id: bookingId, user_id: user.id };

      let pi;
      try {
        if (savedPmId && customerId) {
          // 1-toque: cartao salvo, off_session (MIT).
          pi = await stripe.paymentIntents.create({
            amount: amountCents,
            currency: 'eur',
            customer: customerId,
            payment_method: savedPmId,
            confirm: true,
            off_session: true,
            automatic_payment_methods: { enabled: true, allow_redirects: 'never' },
            metadata: meta,
          });
        } else {
          pi = await stripe.paymentIntents.create({
            amount: amountCents,
            currency: 'eur',
            ...(customerId ? { customer: customerId, setup_future_usage: 'off_session' as const } : {}),
            automatic_payment_methods: { enabled: true, allow_redirects: 'never' },
            metadata: meta,
          });
        }
      } catch (err) {
        // cartao salvo exigiu 3DS: devolve o PI para autenticacao on-session.
        // deno-lint-ignore no-explicit-any
        const anyErr = err as any;
        const authPi = anyErr?.raw?.payment_intent ?? anyErr?.payment_intent;
        if (authPi?.id) {
          return json({
            clientSecret: authPi.client_secret,
            paymentIntentId: authPi.id,
            amountCents,
            status: authPi.status,
            requiresAction: true,
          });
        }
        const m = err instanceof Error ? err.message : String(err);
        return json({ error: 'stripe_create_failed', details: m }, 400);
      }

      console.log('[carwash-checkout create]', bookingId,
        `amount=€${(amountCents / 100).toFixed(2)}`, `mode=${STRIPE_MODE}`);
      return json({ clientSecret: pi.client_secret, paymentIntentId: pi.id, amountCents, status: pi.status });
    }

    // ── CREATE_MBWAY (cobra na reserva; push na app MB WAY) ────────────────
    if (action === 'create_mbway') {
      if (paymentMethod !== 'mbway') return json({ error: 'not_mbway_booking' }, 400);
      const rawPhone = typeof body?.phone === 'string' ? body.phone : '';
      if (!rawPhone) return json({ error: 'phone_required' }, 400);

      let pi;
      try {
        pi = await stripe.paymentIntents.create({
          amount: amountCents,
          currency: 'eur',
          payment_method_types: ['mb_way'],
          payment_method_data: {
            type: 'mb_way',
            billing_details: { phone: toE164(rawPhone) },
          },
          confirm: true,
          metadata: { kind: 'carwash', booking_id: bookingId, user_id: user.id },
        });
      } catch (e) {
        const m = e instanceof Error ? e.message : String(e);
        console.error('[carwash-checkout create_mbway] stripe error:', m);
        return json({ error: 'mbway_create_failed', details: m }, 400);
      }
      console.log('[carwash-checkout create_mbway]', bookingId,
        `amount=€${(amountCents / 100).toFixed(2)}`, `status=${pi.status}`);
      return json({ paymentIntentId: pi.id, status: pi.status, amountCents });
    }

    // ── MARK_HELD (apos PaymentSheet / push MB WAY confirmar) ──────────────
    if (action === 'mark_held') {
      const piId = typeof body?.paymentIntentId === 'string' ? body.paymentIntentId : null;
      if (!piId) return json({ error: 'payment_intent_required' }, 400);

      let pi;
      try { pi = await stripe.paymentIntents.retrieve(piId); }
      catch (_) { return json({ error: 'payment_intent_not_found' }, 404); }

      // O PI tem mesmo de ser deste pedido, deste utilizador e deste valor.
      if (pi.metadata?.kind !== 'carwash' || pi.metadata?.booking_id !== bookingId) {
        return json({ error: 'payment_kind_mismatch' }, 400);
      }
      if (pi.metadata?.user_id !== user.id) return json({ error: 'payment_owner_mismatch' }, 403);
      if (pi.amount !== amountCents) return json({ error: 'payment_amount_mismatch' }, 400);

      const okStates = paymentMethod === 'card'
        ? ['succeeded', 'processing', 'requires_capture']
        : ['succeeded', 'processing'];
      if (!okStates.includes(pi.status)) {
        return json({ error: 'payment_not_completed', status: pi.status }, 402);
      }

      // Reutiliza a RPC ja existente: valida o valor outra vez e e idempotente.
      // (nao se toca no stripe-webhook — e zona proibida)
      const { data: conf, error: confErr } = await admin
        .rpc('confirm_carwash_payment_webhook', {
          p_booking_id: bookingId,
          p_payment_intent_id: pi.id,
          p_amount_cents: pi.amount,
        });
      if (confErr) return json({ error: 'booking_update_failed', details: confErr.message }, 500);
      if (!conf?.ok) return json({ error: conf?.error ?? 'confirm_failed', details: conf }, 400);

      console.log('[carwash-checkout mark_held]', bookingId, `status=${pi.status}`);
      return json({ ok: true, status: pi.status });
    }

    return json({
      error: 'invalid_action',
      details: "use 'create', 'create_mbway', 'mark_held' or 'reverse'",
    }, 400);
  } catch (err) {
    const message = err instanceof Error ? err.message : String(err);
    console.error('[carwash-checkout] error:', message);
    return json({ error: message }, 500);
  }
});

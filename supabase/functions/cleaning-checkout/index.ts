// ============================================================================
// cleaning-checkout — pagamento da vertical LIMPEZA (escrow-like, SEM webhook)
// ----------------------------------------------------------------------------
// ⚠️ LISTA VERMELHA: função LIVE desde 2026-07-05 ("vai" do Danilo +
//    cleaning_stripe_enabled=true). v2 (2026-07-05): cartão passou de hold
//    manual para COBRANÇA NA RESERVA (hold expirava em ~7 dias).
//
// v3 (2026-07-21) — Carteira Única: a ação `create` (cartão) passa a GUARDAR o
//    cartão (Stripe Customer + setup_future_usage 'off_session') e a REUSAR cartão
//    salvo (saved_pm_id -> confirm off_session, isenção MIT). ADITIVO: create_mbway,
//    mark_held, capture e reverse INTACTOS. stripe-webhook não tocado.
//
// Padrão: espelha tvde-plan-payment (Edge Fn Stripe ISOLADA, sem tocar no
// stripe-webhook v17+ nem em create-payment-intent). verify_jwt = true.
//
// Ações (POST JSON):
//   { action:'create',        bookingId, saved_pm_id? }
//     → CARTÃO: PaymentIntent normal — COBRA NA RESERVA (decisão do Danilo
//       2026-07-05: o hold manual expirava em ~7 dias e reservas antecipadas
//       perdiam a retenção). Estorno automático no cancelamento ('reverse').
//       Devolve { clientSecret, paymentIntentId }.
//   { action:'create_mbway',  bookingId, phone }
//     → MB WAY: não suporta captura manual → cobra NA RESERVA (confirm server-
//       side, push MB WAY). Cancelamento → estorno automático (ação 'reverse').
//       ESCOLHA DOCUMENTADA no relatório (fallback previsto na missão).
//   { action:'mark_held',     bookingId, paymentIntentId }
//     → valida o PI na Stripe (dono, kind, valor, estado) e marca a reserva
//       payment_status='held' + guarda stripe_payment_intent_id.
//   { action:'capture',       bookingId }
//     → LEGADO (holds manuais anteriores a 2026-07-05): captura o PI se ainda
//       estiver requires_capture. Cartão/MB Way novos: no-op (já cobrados).
//   { action:'reverse',       bookingId }
//     → reserva cancelada: cartão não capturado = cancela o PI (liberta a
//       retenção); MB Way/capturado = estorno Stripe de (total - taxa cancel).
//
// Segurança: preço vem SEMPRE de cleaning_bookings.total_cents (server-side).
// Mínimo Stripe 0.50 EUR imposto. BORA_STRIPE_MODE=test → STRIPE_TEST_SECRET_KEY.
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

// v3 — Carteira Única: Stripe Customer idempotente por user (admin service-role;
// RLS bloqueia update user-side de users.stripe_customer_id). Falha = non-blocking.
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
    console.error('[cleaning-checkout] getOrCreateCustomer error:', err);
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

    // Reserva sempre lida server-side (nunca confiar em valores do cliente).
    const { data: booking, error: bErr } = await admin
      .from('cleaning_bookings').select('*').eq('id', bookingId).single();
    if (bErr || !booking) return json({ error: 'booking_not_found' }, 404);
    if (booking.client_user_id !== user.id) return json({ error: 'booking_not_yours' }, 403);

    const amountCents = Number(booking.total_cents ?? 0);
    if (!amountCents || amountCents < 50) return json({ error: 'amount_below_minimum' }, 400);

    // ── CREATE (cartão, cobra na reserva) — v3 guarda/reusa cartão ───────────
    if (action === 'create') {
      if (booking.payment_method !== 'card') return json({ error: 'not_card_booking' }, 400);
      if (booking.payment_status !== 'unpaid') return json({ error: 'already_paid' }, 400);

      const customerId = await getOrCreateCustomer(admin, user.id);
      const savedPmId = typeof body?.saved_pm_id === 'string' ? body.saved_pm_id : null;
      const meta = { kind: 'cleaning', booking_id: bookingId, user_id: user.id };

      let pi;
      try {
        if (savedPmId && customerId) {
          // 1-toque: cartão salvo, off_session (MIT).
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
          // cartão novo: cobra na reserva + guarda no Customer para reuso futuro.
          pi = await stripe.paymentIntents.create({
            amount: amountCents,
            currency: 'eur',
            ...(customerId ? { customer: customerId, setup_future_usage: 'off_session' as const } : {}),
            automatic_payment_methods: { enabled: true, allow_redirects: 'never' },
            metadata: meta,
          });
        }
      } catch (err) {
        // cartão salvo exigiu 3DS: devolve o PI p/ auth on-session.
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

      console.log('[cleaning-checkout create]', bookingId,
        `amount=€${(amountCents / 100).toFixed(2)}`, `mode=${STRIPE_MODE}`);
      return json({ clientSecret: pi.client_secret, paymentIntentId: pi.id, amountCents, status: pi.status });
    }

    // ── CREATE_MBWAY (cobra na reserva; estorno automático em cancelamento) ─
    if (action === 'create_mbway') {
      if (booking.payment_method !== 'mbway') return json({ error: 'not_mbway_booking' }, 400);
      if (booking.payment_status !== 'unpaid') return json({ error: 'already_paid' }, 400);
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
          metadata: { kind: 'cleaning', booking_id: bookingId, user_id: user.id },
        });
      } catch (e) {
        const m = e instanceof Error ? e.message : String(e);
        console.error('[cleaning-checkout create_mbway] stripe error:', m);
        return json({ error: 'mbway_create_failed', details: m }, 400);
      }
      console.log('[cleaning-checkout create_mbway]', bookingId,
        `amount=€${(amountCents / 100).toFixed(2)}`, `status=${pi.status}`);
      return json({ paymentIntentId: pi.id, status: pi.status, amountCents });
    }

    // ── MARK_HELD (após PaymentSheet/push MB WAY confirmar) ─────────────────
    if (action === 'mark_held') {
      const piId = typeof body?.paymentIntentId === 'string' ? body.paymentIntentId : null;
      if (!piId) return json({ error: 'payment_intent_required' }, 400);

      let pi;
      try { pi = await stripe.paymentIntents.retrieve(piId); }
      catch (_) { return json({ error: 'payment_intent_not_found' }, 404); }

      if (pi.metadata?.kind !== 'cleaning' || pi.metadata?.booking_id !== bookingId) {
        return json({ error: 'payment_kind_mismatch' }, 400);
      }
      if (pi.metadata?.user_id !== user.id) return json({ error: 'payment_owner_mismatch' }, 403);
      if (pi.amount !== amountCents) return json({ error: 'payment_amount_mismatch' }, 400);

      // Cartão e MB Way cobram ambos na reserva (2026-07-05).
      // 'requires_capture' aceite só para holds legados criados antes da mudança.
      const okStates = booking.payment_method === 'card'
        ? ['succeeded', 'processing', 'requires_capture']
        : ['succeeded', 'processing'];
      if (!okStates.includes(pi.status)) {
        return json({ error: 'payment_not_completed', status: pi.status }, 402);
      }

      const { error: updErr } = await admin.from('cleaning_bookings')
        .update({ payment_status: 'held', stripe_payment_intent_id: pi.id })
        .eq('id', bookingId).eq('payment_status', 'unpaid');
      if (updErr) return json({ error: 'booking_update_failed', details: updErr.message }, 500);
      return json({ ok: true, status: pi.status });
    }

    // ── CAPTURE (cliente confirmou → libertar para a profissional) ──────────
    if (action === 'capture') {
      if (booking.payment_status !== 'released') {
        return json({ error: 'booking_not_released' }, 400);
      }
      if (!booking.stripe_payment_intent_id) return json({ error: 'no_payment_intent' }, 400);
      if (booking.payment_method === 'mbway') return json({ ok: true, note: 'mbway_already_charged' });

      let pi;
      try { pi = await stripe.paymentIntents.retrieve(booking.stripe_payment_intent_id); }
      catch (_) { return json({ error: 'payment_intent_not_found' }, 404); }
      if (pi.status === 'succeeded') return json({ ok: true, note: 'already_captured' });
      if (pi.status !== 'requires_capture') {
        return json({ error: 'cannot_capture', status: pi.status }, 400);
      }
      const captured = await stripe.paymentIntents.capture(pi.id);
      console.log('[cleaning-checkout capture]', bookingId, `status=${captured.status}`);
      return json({ ok: true, status: captured.status });
    }

    // ── REVERSE (cancelamento: liberta retenção / estorna o excedente) ──────
    //
    // v4 (2026-09-05) — SEGURA DE REPETIR. Antes desta versão, chamar 'reverse'
    // duas vezes estornava duas vezes: nada perguntava à Stripe se o estorno já
    // tinha sido feito. Só a ordem das chamadas no app é que impedia isso na
    // prática — protecção por acidente, não por desenho. Agora há duas travas:
    //   1. pergunta-se à Stripe se este PaymentIntent já tem estorno; se tiver,
    //      devolve-se o que já existe e não se cria nada;
    //   2. o pedido leva uma CHAVE DE IDEMPOTÊNCIA fixa por reserva, por isso
    //      duas chamadas ao mesmo tempo devolvem o MESMO estorno, não dois.
    // A trava 1 apanha repetições tardias (a chave da Stripe dura 24 h); a
    // trava 2 apanha a corrida de rede. Nenhum valor mudou.
    if (action === 'reverse') {
      if (!['cancelled_client', 'cancelled_cleaner'].includes(booking.status)) {
        return json({ error: 'booking_not_cancelled' }, 400);
      }
      if (!booking.stripe_payment_intent_id) return json({ ok: true, note: 'nothing_to_reverse' });

      let pi;
      try { pi = await stripe.paymentIntents.retrieve(booking.stripe_payment_intent_id); }
      catch (_) { return json({ error: 'payment_intent_not_found' }, 404); }

      const feeCents = Number(booking.cancel_fee_cents ?? 0);
      // Chave estável por reserva: a segunda chamada reusa o mesmo pedido Stripe.
      const idem = (sufixo: string) => `cleaning-reverse-${bookingId}-${sufixo}`;

      if (pi.status === 'requires_capture') {
        // cartão retido: taxa 0 → cancela tudo; taxa >0 → captura parcial da taxa
        if (feeCents <= 0) {
          await stripe.paymentIntents.cancel(pi.id, undefined, {
            idempotencyKey: idem('cancel'),
          });
          return json({ ok: true, note: 'hold_released' });
        }
        const captured = await stripe.paymentIntents.capture(pi.id, {
          amount_to_capture: Math.max(feeCents, 50),
        }, { idempotencyKey: idem('capture') });
        return json({ ok: true, note: 'fee_captured', status: captured.status });
      }

      if (pi.status === 'succeeded') {
        // mb way (ou cartão já capturado): estorna o que exceder a taxa
        const backCents = amountCents - feeCents;
        if (backCents <= 0) return json({ ok: true, note: 'fee_equals_total' });

        // TRAVA 1 — já foi estornado alguma vez? Então não se estorna outra vez.
        try {
          const jaFeitos = await stripe.refunds.list({ payment_intent: pi.id, limit: 10 });
          const anterior = jaFeitos.data.find((x) => x.status !== 'failed' && x.status !== 'canceled');
          if (anterior) {
            console.log('[cleaning-checkout reverse] ja estornado, nao repete:', bookingId, anterior.id);
            return json({
              ok: true, note: 'already_reversed', refundId: anterior.id,
              refundStatus: anterior.status, backCents: anterior.amount,
            });
          }
        } catch (e) {
          // Se a listagem falhar, seguimos — a TRAVA 2 (chave) ainda protege.
          console.error('[cleaning-checkout reverse] refunds.list falhou:',
            e instanceof Error ? e.message : String(e));
        }

        // TRAVA 2 — chave de idempotência fixa por reserva.
        const r = await stripe.refunds.create({
          payment_intent: pi.id,
          amount: backCents,
          metadata: { kind: 'cleaning', booking_id: bookingId },
        }, { idempotencyKey: idem('refund') });
        return json({ ok: true, note: 'reversed', refundId: r.id, refundStatus: r.status, backCents });
      }

      return json({ ok: true, note: 'no_action_for_status', status: pi.status });
    }

    return json({
      error: 'invalid_action',
      details: "use 'create', 'create_mbway', 'mark_held', 'capture' or 'reverse'",
    }, 400);
  } catch (err) {
    const message = err instanceof Error ? err.message : String(err);
    console.error('[cleaning-checkout] error:', message);
    return json({ error: message }, 500);
  }
});

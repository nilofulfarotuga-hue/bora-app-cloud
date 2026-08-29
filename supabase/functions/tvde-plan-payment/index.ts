// supabase/functions/tvde-plan-payment/index.ts — v3 (Item A + CAMPO-02 F3 roundtrip)
//
// Pagamento do PLANO TVDE por cartão OU MB Way (Stripe) + ativação automática,
// SEM tocar no webhook Stripe existente. Função nova e ISOLADA (regra do Danilo).
// v3: +ações roundtrip (create_roundtrip / create_roundtrip_mbway / activate_roundtrip).

import Stripe from 'https://esm.sh/stripe@14.21.0?target=deno';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};

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

const VALID_PLANS = ['semanal', 'quinzenal', 'mensal'];

// deno-lint-ignore no-explicit-any
const json = (body: any, status = 200) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  });

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
    console.error('[tvde-plan-payment] getOrCreateCustomer error:', err);
    return null;
  }
}

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders });

  try {
    const authHeader = req.headers.get('Authorization') ?? '';
    const token = authHeader.replace(/^Bearer\s+/i, '').trim();
    if (!token) return json({ error: 'missing_token' }, 401);

    const userClient = createClient(supabaseUrl, anonKey, {
      global: { headers: { Authorization: `Bearer ${token}` } },
    });
    const { data: userData, error: authError } = await userClient.auth.getUser();
    const user = userData?.user;
    if (authError || !user) return json({ error: 'unauthorized' }, 401);

    // deno-lint-ignore no-explicit-any
    const body = await req.json() as any;
    const action = typeof body?.action === 'string' ? body.action : null;

    // ── [CAMPO-02 F3] IDA-E-VOLTA — pacote pré-pago (8 EUR) reusa este checkout ──
    if (action === 'create_roundtrip' || action === 'create_roundtrip_mbway' ||
        action === 'activate_roundtrip') {
      const rtAdmin = createClient(supabaseUrl, serviceKey);

      if (action === 'activate_roundtrip') {
        const piId = typeof body?.payment_intent_id === 'string' ? body.payment_intent_id : null;
        const outboundRideId = typeof body?.outbound_ride_id === 'string' ? body.outbound_ride_id : null;
        if (!piId) return json({ error: 'payment_intent_required' }, 400);
        let pi: Stripe.PaymentIntent;
        try { pi = await stripe.paymentIntents.retrieve(piId); }
        catch (_) { return json({ error: 'payment_intent_not_found' }, 404); }
        if (pi.status !== 'succeeded') return json({ error: 'payment_not_completed', status: pi.status }, 402);
        if (pi.metadata?.user_id !== user.id) return json({ error: 'payment_owner_mismatch' }, 403);
        if (pi.metadata?.kind !== 'tvde_roundtrip') return json({ error: 'payment_kind_mismatch' }, 400);
        const paidCents = pi.amount_received || pi.amount;
        const { data: credit, error: rpcErr } = await rtAdmin.rpc('tvde_create_roundtrip_credit', {
          p_client_id: user.id,
          p_outbound_ride_id: outboundRideId,
          p_paid_cents: paidCents,
          p_payment_intent_id: piId,
        });
        if (rpcErr) {
          console.error('[tvde-plan-payment activate_roundtrip] rpc failed:', rpcErr.message);
          return json({ error: 'roundtrip_activation_failed', details: rpcErr.message }, 500);
        }
        return json({ credit });
      }


      // FONTE UNICA DO PRECO (2026-08-29, missao tvde-idavolta-e-disco)
      // O valor cobrado tem de ser o MESMO que o cliente viu no ecra. Esse preco vem da
      // RPC `tvde_roundtrip_price_for_km`, que ja aplica o desconto
      // (`tvde_roundtrip_discount_pct`) E o piso (`tvde_roundtrip_price_cents`).
      //
      // O QUE ISTO CORRIGE, MEDIDO EM PRODUCAO A 2026-08-29:
      //   ler a chave do piso aqui cobrava SEMPRE 8 EUR. Numa rota de 10 km o cliente via
      //   14,40 EUR e a Stripe cobrava 8,00 -> a Bora perdia 5,90 por corrida. A 20 km via
      //   30,40 e perdia 21,90. Com a fonte unica, a Bora fica com +0,50 em qualquer
      //   distancia, que e o desenho.
      //
      // O servidor NUNCA aceita um preco vindo do cliente: recebe a distancia e pergunta a BD.
      const distanceKm = Number(body?.distance_km);
      if (!Number.isFinite(distanceKm) || distanceKm <= 0) {
        return json({ error: 'roundtrip_distance_required' }, 400);
      }
      const { data: rtPriceCents, error: rtPriceErr } = await rtAdmin
        .rpc('tvde_roundtrip_price_for_km', { p_distance_km: distanceKm });
      const amountCents = Number(rtPriceCents);
      if (rtPriceErr || !Number.isFinite(amountCents) || amountCents < 50) {
        // Sem fallback para 800 de proposito: cobrar o valor errado e pior do que nao cobrar.
        return json({ error: 'roundtrip_price_unavailable' }, 400);
      }
      const customerId = await getOrCreateCustomer(rtAdmin, user.id);

      if (action === 'create_roundtrip') {
        const paymentIntent = await stripe.paymentIntents.create({
          amount: amountCents,
          currency: 'eur',
          ...(customerId ? { customer: customerId, setup_future_usage: 'off_session' as const } : {}),
          automatic_payment_methods: { enabled: true },
          metadata: { kind: 'tvde_roundtrip', user_id: user.id },
        });
        return json({
          clientSecret: paymentIntent.client_secret,
          paymentIntentId: paymentIntent.id,
          amountCents,
        });
      }

      const rawPhone = typeof body?.phone === 'string' ? body.phone.trim() : '';
      if (!rawPhone) return json({ error: 'phone_required' }, 400);
      const digits = rawPhone.replace(/[^\d+]/g, '');
      const e164 = digits.startsWith('+') ? digits : `+351${digits.replace(/^0/, '')}`;
      let paymentIntent: Stripe.PaymentIntent;
      try {
        paymentIntent = await stripe.paymentIntents.create({
          amount: amountCents,
          currency: 'eur',
          ...(customerId ? { customer: customerId } : {}),
          payment_method_types: ['mb_way'],
          payment_method_data: { type: 'mb_way', billing_details: { phone: e164 } },
          confirm: true,
          metadata: { kind: 'tvde_roundtrip', user_id: user.id },
        });
      } catch (e) {
        const m = e instanceof Error ? e.message : String(e);
        return json({ error: 'mbway_create_failed', details: m }, 400);
      }
      return json({ paymentIntentId: paymentIntent.id, status: paymentIntent.status, amountCents });
    }

    const plan = typeof body?.plan === 'string' ? body.plan : null;

    if (!plan || !VALID_PLANS.includes(plan)) {
      return json({ error: 'invalid_plan' }, 400);
    }

    const admin = createClient(supabaseUrl, serviceKey);

    if (action === 'create') {
      const { data: priceData, error: priceErr } =
        await userClient.rpc('tvde_plan_price_cents', { p_plan: plan });
      const amountCents = typeof priceData === 'number' ? priceData : Number(priceData);
      if (priceErr || !amountCents || amountCents < 50) {
        console.error('[tvde-plan-payment create] price failed:', priceErr?.message);
        return json({ error: 'plan_price_unavailable', details: priceErr?.message }, 400);
      }

      const customerId = await getOrCreateCustomer(admin, user.id);

      const paymentIntent = await stripe.paymentIntents.create({
        amount: amountCents,
        currency: 'eur',
        ...(customerId
          ? { customer: customerId, setup_future_usage: 'off_session' as const }
          : {}),
        automatic_payment_methods: { enabled: true },
        metadata: { kind: 'tvde_plan', plan, user_id: user.id },
      });

      console.log('[tvde-plan-payment create]', paymentIntent.id, `plan=${plan}`,
        `amount=€${(amountCents / 100).toFixed(2)}`, `user=${user.id}`);

      return json({
        clientSecret: paymentIntent.client_secret,
        paymentIntentId: paymentIntent.id,
        amountCents,
      });
    }

    if (action === 'create_mbway') {
      const rawPhone = typeof body?.phone === 'string' ? body.phone.trim() : '';
      if (!rawPhone) return json({ error: 'phone_required' }, 400);
      const digits = rawPhone.replace(/[^\d+]/g, '');
      const e164 = digits.startsWith('+') ? digits : `+351${digits.replace(/^0/, '')}`;

      const { data: priceData, error: priceErr } =
        await userClient.rpc('tvde_plan_price_cents', { p_plan: plan });
      const amountCents = typeof priceData === 'number' ? priceData : Number(priceData);
      if (priceErr || !amountCents || amountCents < 50) {
        console.error('[tvde-plan-payment create_mbway] price failed:', priceErr?.message);
        return json({ error: 'plan_price_unavailable', details: priceErr?.message }, 400);
      }

      const customerId = await getOrCreateCustomer(admin, user.id);

      let paymentIntent: Stripe.PaymentIntent;
      try {
        paymentIntent = await stripe.paymentIntents.create({
          amount: amountCents,
          currency: 'eur',
          ...(customerId ? { customer: customerId } : {}),
          payment_method_types: ['mb_way'],
          payment_method_data: {
            type: 'mb_way',
            billing_details: { phone: e164 },
          },
          confirm: true,
          metadata: { kind: 'tvde_plan', plan, user_id: user.id },
        });
      } catch (e) {
        const m = e instanceof Error ? e.message : String(e);
        console.error('[tvde-plan-payment create_mbway] stripe error:', m);
        return json({ error: 'mbway_create_failed', details: m }, 400);
      }

      console.log('[tvde-plan-payment create_mbway]', paymentIntent.id, `plan=${plan}`,
        `amount=€${(amountCents / 100).toFixed(2)}`, `phone=${e164}`, `status=${paymentIntent.status}`);

      return json({
        paymentIntentId: paymentIntent.id,
        status: paymentIntent.status,
        amountCents,
      });
    }

    if (action === 'activate') {
      const piId = typeof body?.payment_intent_id === 'string'
        ? body.payment_intent_id : null;
      if (!piId) return json({ error: 'payment_intent_required' }, 400);

      let pi: Stripe.PaymentIntent;
      try {
        pi = await stripe.paymentIntents.retrieve(piId);
      } catch (e) {
        console.error('[tvde-plan-payment activate] retrieve failed:', e);
        return json({ error: 'payment_intent_not_found' }, 404);
      }

      if (pi.status !== 'succeeded') {
        return json({ error: 'payment_not_completed', status: pi.status }, 402);
      }
      if (pi.metadata?.user_id !== user.id) {
        return json({ error: 'payment_owner_mismatch' }, 403);
      }
      if (pi.metadata?.plan !== plan) {
        return json({ error: 'payment_plan_mismatch' }, 400);
      }

      const paidCents = pi.amount_received || pi.amount;

      const { data: sub, error: rpcErr } = await admin.rpc(
        'tvde_activate_paid_subscription', {
          p_client_id: user.id,
          p_plan: plan,
          p_payment_intent_id: piId,
          p_paid_cents: paidCents,
        });
      if (rpcErr) {
        console.error('[tvde-plan-payment activate] rpc failed:', rpcErr.message);
        return json({ error: 'activation_failed', details: rpcErr.message }, 500);
      }

      console.log('[tvde-plan-payment activate] OK', piId, `plan=${plan}`, `user=${user.id}`);
      return json({ subscription: sub });
    }

    return json({ error: 'invalid_action', details: "use 'create', 'create_mbway', 'activate' or *_roundtrip" }, 400);
  } catch (err) {
    const message = err instanceof Error ? err.message : String(err);
    console.error('[tvde-plan-payment] error:', message);
    return json({ error: message }, 500);
  }
});

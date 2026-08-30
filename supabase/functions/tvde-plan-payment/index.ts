// supabase/functions/tvde-plan-payment/index.ts — v5 (Item A + CAMPO-02 F3 roundtrip + KM 2026-08-25)
//
// Pagamento do PLANO TVDE por cartão OU MB Way (Stripe) + ativação automática,
// SEM tocar no webhook Stripe existente. Função nova e ISOLADA (regra do Danilo).
// v3: +ações roundtrip (create_roundtrip / create_roundtrip_mbway / activate_roundtrip).
// v4/v5: o PREÇO passa a depender da DISTÂNCIA. O app manda distance_km; o servidor calcula
//     (tvde_quote_plan para o plano, tvde_roundtrip_price_for_km para o pacote) e guarda o km
//     nos metadata do PaymentIntent. Na activação o km vem dos METADATA, nunca do pedido,
//     para o cliente não poder pagar um plano curto e activar um plano longo.
//     Sem distance_km tudo se comporta exactamente como na v3.

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

// Distância válida ou null. Nunca confiar em texto solto vindo do app.
// deno-lint-ignore no-explicit-any
function parseKm(raw: any): number | null {
  const n = typeof raw === 'number' ? raw : Number(raw);
  if (!Number.isFinite(n) || n <= 0 || n > 500) return null;
  return Math.round(n * 100) / 100;
}

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
    const distanceKm = parseKm(body?.distance_km);
    const originLabel = typeof body?.origin_label === 'string' ? body.origin_label : null;
    const destLabel = typeof body?.dest_label === 'string' ? body.dest_label : null;

    // ── [CAMPO-02 F3] IDA-E-VOLTA — pacote pré-pago reusa este checkout ──
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

      // PREÇO POR DISTÂNCIA. Com distance_km usa a fórmula do servidor (ida+volta com desconto);
      // sem ela cai no valor fixo antigo, como na v3.
      let amountCents = 0;
      if (distanceKm !== null) {
        const { data: rtPrice, error: rtErr } = await rtAdmin
          .rpc('tvde_roundtrip_price_for_km', { p_distance_km: distanceKm });
        amountCents = typeof rtPrice === 'number' ? rtPrice : Number(rtPrice);
        if (rtErr || !amountCents || amountCents < 50) {
          console.error('[tvde-plan-payment roundtrip] price failed:', rtErr?.message);
          return json({ error: 'roundtrip_price_unavailable', details: rtErr?.message }, 400);
        }
      } else {
        const { data: priceRow } = await rtAdmin
          .from('platform_settings').select('value').eq('key', 'tvde_roundtrip_price_cents').maybeSingle();
        amountCents = Number(priceRow?.value ?? 800);
      }
      if (!amountCents || amountCents < 50) {
        return json({ error: 'roundtrip_price_unavailable' }, 400);
      }
      const customerId = await getOrCreateCustomer(rtAdmin, user.id);
      const rtMeta: Record<string, string> = { kind: 'tvde_roundtrip', user_id: user.id };
      if (distanceKm !== null) rtMeta.distance_km = String(distanceKm);

      if (action === 'create_roundtrip') {
        const paymentIntent = await stripe.paymentIntents.create({
          amount: amountCents,
          currency: 'eur',
          ...(customerId ? { customer: customerId, setup_future_usage: 'off_session' as const } : {}),
          automatic_payment_methods: { enabled: true },
          metadata: rtMeta,
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
          metadata: rtMeta,
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

    // Preço do plano: com distância usa o orçamento completo (base + km a mais x nº de corridas).
    async function planAmountCents(): Promise<{ amount: number; quote: unknown; err?: string }> {
      if (distanceKm !== null) {
        const { data: q, error: qErr } = await userClient
          .rpc('tvde_quote_plan', { p_plan: plan, p_distance_km: distanceKm });
        if (qErr || !q) return { amount: 0, quote: null, err: qErr?.message ?? 'quote_failed' };
        // deno-lint-ignore no-explicit-any
        const amount = Number((q as any).price_cents);
        return { amount, quote: q };
      }
      const { data: priceData, error: priceErr } =
        await userClient.rpc('tvde_plan_price_cents', { p_plan: plan });
      const amount = typeof priceData === 'number' ? priceData : Number(priceData);
      return { amount, quote: null, err: priceErr?.message };
    }

    const planMeta = (): Record<string, string> => {
      const m: Record<string, string> = { kind: 'tvde_plan', plan: plan as string, user_id: user.id };
      if (distanceKm !== null) m.distance_km = String(distanceKm);
      if (originLabel) m.origin_label = originLabel.slice(0, 200);
      if (destLabel) m.dest_label = destLabel.slice(0, 200);
      return m;
    };

    if (action === 'create') {
      const { amount: amountCents, quote, err } = await planAmountCents();
      if (err || !amountCents || amountCents < 50) {
        console.error('[tvde-plan-payment create] price failed:', err);
        return json({ error: 'plan_price_unavailable', details: err }, 400);
      }

      const customerId = await getOrCreateCustomer(admin, user.id);

      const paymentIntent = await stripe.paymentIntents.create({
        amount: amountCents,
        currency: 'eur',
        ...(customerId
          ? { customer: customerId, setup_future_usage: 'off_session' as const }
          : {}),
        automatic_payment_methods: { enabled: true },
        metadata: planMeta(),
      });

      console.log('[tvde-plan-payment create]', paymentIntent.id, `plan=${plan}`,
        `km=${distanceKm ?? '-'}`, `amount=€${(amountCents / 100).toFixed(2)}`, `user=${user.id}`);

      return json({
        clientSecret: paymentIntent.client_secret,
        paymentIntentId: paymentIntent.id,
        amountCents,
        quote,
      });
    }

    if (action === 'create_mbway') {
      const rawPhone = typeof body?.phone === 'string' ? body.phone.trim() : '';
      if (!rawPhone) return json({ error: 'phone_required' }, 400);
      const digits = rawPhone.replace(/[^\d+]/g, '');
      const e164 = digits.startsWith('+') ? digits : `+351${digits.replace(/^0/, '')}`;

      const { amount: amountCents, quote, err } = await planAmountCents();
      if (err || !amountCents || amountCents < 50) {
        console.error('[tvde-plan-payment create_mbway] price failed:', err);
        return json({ error: 'plan_price_unavailable', details: err }, 400);
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
          metadata: planMeta(),
        });
      } catch (e) {
        const m = e instanceof Error ? e.message : String(e);
        console.error('[tvde-plan-payment create_mbway] stripe error:', m);
        return json({ error: 'mbway_create_failed', details: m }, 400);
      }

      console.log('[tvde-plan-payment create_mbway]', paymentIntent.id, `plan=${plan}`,
        `km=${distanceKm ?? '-'}`, `amount=€${(amountCents / 100).toFixed(2)}`,
        `phone=${e164}`, `status=${paymentIntent.status}`);

      return json({
        paymentIntentId: paymentIntent.id,
        status: paymentIntent.status,
        amountCents,
        quote,
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
      // O km vem dos METADATA do pagamento, nunca do corpo do pedido.
      const paidKm = parseKm(pi.metadata?.distance_km);

      const { data: sub, error: rpcErr } = await admin.rpc(
        'tvde_activate_paid_subscription', {
          p_client_id: user.id,
          p_plan: plan,
          p_payment_intent_id: piId,
          p_paid_cents: paidCents,
          p_km_included: paidKm,
          p_origin_label: pi.metadata?.origin_label ?? null,
          p_dest_label: pi.metadata?.dest_label ?? null,
        });
      if (rpcErr) {
        console.error('[tvde-plan-payment activate] rpc failed:', rpcErr.message);
        return json({ error: 'activation_failed', details: rpcErr.message }, 500);
      }

      console.log('[tvde-plan-payment activate] OK', piId, `plan=${plan}`,
        `km=${paidKm ?? '-'}`, `user=${user.id}`);
      return json({ subscription: sub });
    }

    return json({ error: 'invalid_action', details: "use 'create', 'create_mbway', 'activate' or *_roundtrip" }, 400);
  } catch (err) {
    const message = err instanceof Error ? err.message : String(err);
    console.error('[tvde-plan-payment] error:', message);
    return json({ error: message }, 500);
  }
});

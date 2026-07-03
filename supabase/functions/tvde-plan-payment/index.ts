// supabase/functions/tvde-plan-payment/index.ts — v1 (Item A · TVDE-CAMPO-01)
//
// Pagamento do PLANO TVDE por cartão (Stripe) + ativação automática, SEM tocar
// no webhook Stripe existente. Função nova e ISOLADA (regra do Danilo).
//
// Fluxo (2 ações numa só função — nova e separada):
//   { action: 'create',  plan }
//     → valida plano, lê o preço SERVER-SIDE (tvde_plan_price_cents),
//       cria PaymentIntent(amount=preço, eur) com metadata {kind,plan,user_id},
//       devolve { clientSecret, paymentIntentId, amountCents }.
//   { action: 'activate', plan, payment_intent_id }
//     → RETRIEVE do PI na Stripe, confirma status='succeeded' + dono + valor,
//       chama tvde_activate_paid_subscription (idempotente) → subscrição ATIVA.
//
// verify_jwt = true (utilizador autenticado). O webhook Stripe NÃO é usado aqui:
// a ativação é verificada por retrieve direto do PaymentIntent.

import Stripe from 'https://esm.sh/stripe@14.21.0?target=deno';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

// corsHeaders inline — função ISOLADA e auto-contida (sem dependência partilhada).
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

// Stripe Customer idempotente (mesmo padrão de create-payment-intent v28).
// Non-blocking: falha → PI segue sem customer.
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
    // ── Auth: user do JWT ──────────────────────────────────────────────────
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
    const plan = typeof body?.plan === 'string' ? body.plan : null;

    if (!plan || !VALID_PLANS.includes(plan)) {
      return json({ error: 'invalid_plan' }, 400);
    }

    const admin = createClient(supabaseUrl, serviceKey);

    // ── Ação CREATE: cria o PaymentIntent do plano ─────────────────────────
    if (action === 'create') {
      // Preço server-side (o cliente nunca envia o valor).
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

    // ── Ação ACTIVATE: verifica o PI + cria a subscrição ───────────────────
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

      // O PI tem de estar pago, ser deste utilizador e deste plano.
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

    return json({ error: 'invalid_action', details: "use 'create' or 'activate'" }, 400);
  } catch (err) {
    const message = err instanceof Error ? err.message : String(err);
    console.error('[tvde-plan-payment] error:', message);
    return json({ error: message }, 500);
  }
});

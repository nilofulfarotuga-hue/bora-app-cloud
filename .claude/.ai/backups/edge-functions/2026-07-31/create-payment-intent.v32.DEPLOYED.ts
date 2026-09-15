// supabase/functions/create-payment-intent/index.ts — v28 (Stripe Customer + saved card)
// Webhook stripe-webhook v23 verificado intacto antes do deploy (git diff empty).
//
// DUAL-MODE: Mode A (LEGACY order_id+amount) intacto; Mode B (NEW cart_input) recebe
//   suporte a Stripe Customer (idempotente) + setup_future_usage='off_session' +
//   saved_pm_id para reutilizar cartao guardado (PSD2/SCA exemption).
//
// CRITICAL: getOrCreateCustomer usa service-role admin client para SELECT/UPDATE
// em users (RLS bloqueia user-side updates a stripe_customer_id). Falha = non-blocking.

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

// deno-lint-ignore no-explicit-any
async function getOrCreateCustomer(admin: any, userId: string): Promise<string | null> {
  try {
    const { data: userRow, error: selErr } = await admin
      .from('users')
      .select('stripe_customer_id, email, name')
      .eq('id', userId)
      .maybeSingle();
    if (selErr) {
      console.error('[stripe-customer] users select failed:', selErr.message);
      return null;
    }
    if (userRow?.stripe_customer_id) return userRow.stripe_customer_id as string;

    const customer = await stripe.customers.create({
      email: (userRow?.email as string | undefined) ?? undefined,
      name: (userRow?.name as string | undefined) ?? undefined,
      metadata: { supabase_uid: userId },
    });

    const { error: updErr } = await admin
      .from('users')
      .update({ stripe_customer_id: customer.id })
      .eq('id', userId)
      .is('stripe_customer_id', null);

    if (updErr) {
      const { data: refetch } = await admin
        .from('users')
        .select('stripe_customer_id')
        .eq('id', userId)
        .maybeSingle();
      const winner = refetch?.stripe_customer_id as string | undefined;
      if (winner && winner !== customer.id) {
        try { await stripe.customers.del(customer.id); } catch (_) { /* swallow */ }
        return winner;
      }
    }
    return customer.id;
  } catch (err) {
    console.error('[stripe-customer] getOrCreateCustomer error:', err);
    return null;
  }
}

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders });
  try {
    // deno-lint-ignore no-explicit-any
    const body = await req.json() as any;
    const order_id = typeof body?.order_id === 'string' ? body.order_id : null;
    const amount = typeof body?.amount === 'number' ? body.amount : null;
    // deno-lint-ignore no-explicit-any
    const cart_input = (body?.cart_input && typeof body.cart_input === 'object') ? body.cart_input as Record<string, any> : null;

    if (order_id && amount && !cart_input) return await modeLegacy(order_id, amount);
    if (cart_input) return await modeNew(req, cart_input);
    return json({ error: 'invalid_body', details: 'pass either {order_id, amount} or {cart_input}' }, 400);
  } catch (err) {
    const message = err instanceof Error ? err.message : String(err);
    console.error('[create-payment-intent] error:', message);
    return json({ error: message }, 500);
  }
});

async function modeLegacy(order_id: string, amount: number): Promise<Response> {
  if (!amount || amount <= 0) return json({ error: 'Invalid amount' }, 400);
  const supabase = createClient(supabaseUrl, serviceKey);
  const { data: order, error: dbError } = await supabase
    .from('orders').select('price, payment_buffer_total').eq('id', order_id).maybeSingle();
  if (dbError) {
    console.error('[create-payment-intent legacy] DB error:', dbError.message);
    return json({ error: 'Database error' }, 500);
  }
  if (!order) return json({ error: 'Order not found' }, 404);
  const serverPrice = order.price as number;
  const bufferAmount = order.payment_buffer_total as number;
  if (!serverPrice || serverPrice <= 0) return json({ error: 'Invalid order amount' }, 400);
  if (!bufferAmount || bufferAmount <= 0) return json({ error: 'Invalid order buffer amount' }, 400);
  const clientCents = Math.round(amount * 100);
  const serverCents = Math.round(serverPrice * 100);
  if (clientCents !== serverCents) {
    console.warn(`[create-payment-intent legacy] amount mismatch — client: €${amount.toFixed(2)}, server: €${serverPrice.toFixed(2)}`);
    return json({ error: 'Amount does not match order total' }, 400);
  }
  const amountCents = Math.round(bufferAmount * 100);
  if (amountCents < 50) return json({ error: 'Amount too small (min 0.50 EUR)' }, 400);
  const paymentIntent = await stripe.paymentIntents.create({
    amount: amountCents, currency: 'eur',
    automatic_payment_methods: { enabled: true },
    metadata: { order_id },
  });
  console.log('[create-payment-intent legacy] created:', paymentIntent.id, `order_id=${order_id}`);
  return json({ clientSecret: paymentIntent.client_secret, paymentIntentId: paymentIntent.id });
}

// deno-lint-ignore no-explicit-any
async function modeNew(req: Request, cart: Record<string, any>): Promise<Response> {
  const authHeader = req.headers.get('Authorization') ?? '';
  const token = authHeader.replace(/^Bearer\s+/i, '').trim();
  if (!token) return json({ error: 'missing_token' }, 401);

  const userClient = createClient(supabaseUrl, anonKey, {
    global: { headers: { Authorization: `Bearer ${token}` } },
  });
  const { data: userData, error: authError } = await userClient.auth.getUser();
  const user = userData?.user;
  if (authError || !user) return json({ error: 'unauthorized', details: authError?.message }, 401);

  cart.user_id = user.id;
  cart.payment_method = 'card';

  const { data: quote, error: quoteErr } = await userClient.rpc('quote_order_pricing', { p_input: cart });
  if (quoteErr || !quote) {
    console.error('[create-payment-intent new] quote failed:', quoteErr?.message);
    return json({ error: 'quote_failed', details: quoteErr?.message ?? 'no quote returned' }, 400);
  }
  // deno-lint-ignore no-explicit-any
  const q = quote as Record<string, any>;
  const bufferEur = Number(q.payment_buffer_total ?? 0);
  const chargeEur = Number(q.charge_total ?? 0);
  const walletCents = Number(q.wallet_applied_cents ?? 0);
  if (chargeEur <= 0) {
    return json({ error: 'no_card_charge_needed', details: 'Wallet covers the full order. Use legacy create_order flow directly.' }, 400);
  }
  const amountCents = Math.round(bufferEur * 100);
  if (amountCents < 50) return json({ error: 'Amount too small (min 0.50 EUR)' }, 400);

  // v28 — saved_pm_id (cartao guardado).
  const savedPmId = typeof cart?.saved_pm_id === 'string' ? cart.saved_pm_id : null;
  if (savedPmId) delete cart.saved_pm_id;

  const admin = createClient(supabaseUrl, serviceKey);
  const customerId = await getOrCreateCustomer(admin, user.id);

  const { data: draftRow, error: insertErr } = await admin
    .from('payment_drafts')
    .insert({
      payment_intent_id: 'pending_' + crypto.randomUUID(),
      user_id: user.id,
      payload: cart,
      amount_cents: amountCents,
      wallet_applied_cents: walletCents,
    })
    .select('id').single();
  if (insertErr || !draftRow) {
    console.error('[create-payment-intent new] draft insert failed:', insertErr?.message);
    return json({ error: 'draft_insert_failed', details: insertErr?.message }, 500);
  }
  const draftId = draftRow.id as string;

  let paymentIntent: Stripe.PaymentIntent;
  try {
    if (savedPmId && customerId) {
      paymentIntent = await stripe.paymentIntents.create({
        amount: amountCents, currency: 'eur',
        customer: customerId, payment_method: savedPmId,
        confirm: true, off_session: true,
        automatic_payment_methods: { enabled: true, allow_redirects: 'never' },
        metadata: { draft_id: draftId, user_id: user.id },
      });
    } else {
      paymentIntent = await stripe.paymentIntents.create({
        amount: amountCents, currency: 'eur',
        ...(customerId ? { customer: customerId, setup_future_usage: 'off_session' as const } : {}),
        automatic_payment_methods: { enabled: true },
        metadata: { draft_id: draftId, user_id: user.id },
      });
    }
  } catch (e) {
    console.error('[create-payment-intent new] Stripe PI create failed:', e);
    await admin.from('payment_drafts').delete().eq('id', draftId);
    return json({ error: 'stripe_create_failed', details: String(e) }, 502);
  }

  const { error: updateErr } = await admin
    .from('payment_drafts').update({ payment_intent_id: paymentIntent.id }).eq('id', draftId);
  if (updateErr) {
    console.error('[create-payment-intent new] draft update failed:', updateErr.message);
    try { await stripe.paymentIntents.cancel(paymentIntent.id); } catch (_) { /* swallow */ }
    await admin.from('payment_drafts').delete().eq('id', draftId);
    return json({ error: 'draft_update_failed', details: updateErr.message }, 500);
  }

  console.log('[create-payment-intent new v28] PI=', paymentIntent.id, 'draft=', draftId,
    'customer=', customerId ?? 'none', 'savedPm=', savedPmId ?? 'none',
    'status=', paymentIntent.status, 'amount=€', (amountCents / 100).toFixed(2));

  return json({
    clientSecret: paymentIntent.client_secret,
    paymentIntentId: paymentIntent.id,
    draftId,
    amountCents,
    status: paymentIntent.status,
    requiresAction: paymentIntent.status === 'requires_action',
  });
}

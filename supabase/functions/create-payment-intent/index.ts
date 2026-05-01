// supabase/functions/create-payment-intent/index.ts — v20 (BUG 1 / Fase 2)
//
// DUAL-MODE Edge Function:
//
//   Mode A (LEGACY): body = { order_id, amount }
//     - Carrega order existente, cobra payment_buffer_total via Stripe.
//     - Mantido para MBWay legacy + qualquer fluxo que ainda crie order primeiro.
//
//   Mode B (NEW — preferido p/ card): body = { cart_input }
//     - cart_input contém o payload completo (mesmo formato do create_order RPC).
//     - Calcula price server-side via quote_order_pricing.
//     - Cria PaymentIntent com metadata.draft_id.
//     - INSERT payment_drafts (TTL 30min).
//     - NÃO cria order. Order é criada pelo webhook em payment_intent.succeeded
//       via Edge Fn finalize-order-from-intent.
//
// Stripe LIVE notes:
//   - setup_future_usage NÃO definido → cartão nunca gravado sem consent.
//   - automatic_payment_methods.enabled=true para card. No NEW mode, restringimos
//     a 'card' para evitar conflito com mbway (mbway tem fluxo separado).
//   - Cliente pode chamar com Authorization Bearer (anon JWT do user signed-in).

import Stripe from 'https://esm.sh/stripe@14.21.0?target=deno';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';
import { corsHeaders } from '../_shared/cors.ts';

const stripe = new Stripe(Deno.env.get('STRIPE_SECRET_KEY') ?? '', {
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

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders });

  try {
    // deno-lint-ignore no-explicit-any
    const body = await req.json() as any;
    const order_id = typeof body?.order_id === 'string' ? body.order_id : null;
    const amount = typeof body?.amount === 'number' ? body.amount : null;
    // deno-lint-ignore no-explicit-any
    const cart_input = (body?.cart_input && typeof body.cart_input === 'object') ? body.cart_input as Record<string, any> : null;

    // ── Mode A: LEGACY (order_id + amount) ─────────────────────────────────
    if (order_id && amount && !cart_input) {
      return await modeLegacy(order_id, amount);
    }

    // ── Mode B: NEW (cart_input → draft) ───────────────────────────────────
    if (cart_input) {
      return await modeNew(req, cart_input);
    }

    return json({ error: 'invalid_body', details: 'pass either {order_id, amount} or {cart_input}' }, 400);
  } catch (err) {
    const message = err instanceof Error ? err.message : String(err);
    console.error('[create-payment-intent] error:', message);
    return json({ error: message }, 500);
  }
});

// ───────────────────────────────────────────────────────────────────────────
// Mode A: legacy — charges existing order
// ───────────────────────────────────────────────────────────────────────────
async function modeLegacy(order_id: string, amount: number): Promise<Response> {
  if (!amount || amount <= 0) return json({ error: 'Invalid amount' }, 400);

  const supabase = createClient(supabaseUrl, serviceKey);
  const { data: order, error: dbError } = await supabase
    .from('orders')
    .select('price, payment_buffer_total')
    .eq('id', order_id)
    .maybeSingle();

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
    console.warn(
      `[create-payment-intent legacy] amount mismatch — client: €${amount.toFixed(2)}, server: €${serverPrice.toFixed(2)}`,
    );
    return json({ error: 'Amount does not match order total' }, 400);
  }

  const amountCents = Math.round(bufferAmount * 100);
  if (amountCents < 50) return json({ error: 'Amount too small (min 0.50 EUR)' }, 400);

  const paymentIntent = await stripe.paymentIntents.create({
    amount: amountCents,
    currency: 'eur',
    automatic_payment_methods: { enabled: true },
    metadata: { order_id },
  });

  console.log('[create-payment-intent legacy] created:', paymentIntent.id, `order_id=${order_id}`);

  return json({
    clientSecret: paymentIntent.client_secret,
    paymentIntentId: paymentIntent.id,
  });
}

// ───────────────────────────────────────────────────────────────────────────
// Mode B: new — cart_input → draft → PI (no order yet)
// ───────────────────────────────────────────────────────────────────────────
// deno-lint-ignore no-explicit-any
async function modeNew(req: Request, cart: Record<string, any>): Promise<Response> {
  // Auth: extrair user_id do JWT (Authorization Bearer anon key + user JWT).
  const authHeader = req.headers.get('Authorization') ?? '';
  const token = authHeader.replace(/^Bearer\s+/i, '').trim();
  if (!token) return json({ error: 'missing_token' }, 401);

  const userClient = createClient(supabaseUrl, anonKey, {
    global: { headers: { Authorization: `Bearer ${token}` } },
  });
  const { data: userData, error: authError } = await userClient.auth.getUser();
  const user = userData?.user;
  if (authError || !user) return json({ error: 'unauthorized', details: authError?.message }, 401);

  // Ensure cart has user_id for downstream create_order (called from webhook).
  cart.user_id = user.id;
  // Force payment_method='card' in new flow (mbway has its own dedicated Edge Fn).
  // If caller wants cash, that uses legacy order-first flow (no draft needed).
  cart.payment_method = 'card';

  // Chamar quote_order_pricing como user (impersonation via JWT). Isto também
  // valida o wallet balance (mas sem FOR UPDATE — webhook revalida).
  const { data: quote, error: quoteErr } = await userClient.rpc('quote_order_pricing', {
    p_input: cart,
  });
  if (quoteErr || !quote) {
    console.error('[create-payment-intent new] quote failed:', quoteErr?.message);
    return json({
      error: 'quote_failed',
      details: quoteErr?.message ?? 'no quote returned',
    }, 400);
  }

  // deno-lint-ignore no-explicit-any
  const q = quote as Record<string, any>;
  const bufferEur = Number(q.payment_buffer_total ?? 0);
  const chargeEur = Number(q.charge_total ?? 0);
  const walletCents = Number(q.wallet_applied_cents ?? 0);

  if (chargeEur <= 0) {
    return json({
      error: 'no_card_charge_needed',
      details: 'Wallet covers the full order. Use legacy create_order flow directly.',
    }, 400);
  }

  const amountCents = Math.round(bufferEur * 100);
  if (amountCents < 50) return json({ error: 'Amount too small (min 0.50 EUR)' }, 400);

  // Stripe PI sem setup_future_usage (não gravar cartão sem consent explícito).
  // automatic_payment_methods enabled → suporta card + Google/Apple Pay quando
  // configurados no Dashboard.
  const admin = createClient(supabaseUrl, serviceKey);

  // Pre-INSERT draft com placeholder; UPDATE depois com payment_intent_id.
  // Usamos transaction client-side (2 statements). Em caso de erro Stripe,
  // apagamos o draft.
  const { data: draftRow, error: insertErr } = await admin
    .from('payment_drafts')
    .insert({
      payment_intent_id: 'pending_' + crypto.randomUUID(),
      user_id: user.id,
      payload: cart,
      amount_cents: amountCents,
      wallet_applied_cents: walletCents,
    })
    .select('id')
    .single();
  if (insertErr || !draftRow) {
    console.error('[create-payment-intent new] draft insert failed:', insertErr?.message);
    return json({ error: 'draft_insert_failed', details: insertErr?.message }, 500);
  }
  const draftId = draftRow.id as string;

  // Criar Stripe PI agora com draft_id no metadata.
  let paymentIntent: Stripe.PaymentIntent;
  try {
    paymentIntent = await stripe.paymentIntents.create({
      amount: amountCents,
      currency: 'eur',
      automatic_payment_methods: { enabled: true },
      metadata: { draft_id: draftId, user_id: user.id },
      // setup_future_usage propositadamente OMISSO (não gravar cartão).
    });
  } catch (e) {
    console.error('[create-payment-intent new] Stripe PI create failed:', e);
    // Limpar draft órfão (Stripe falhou antes de criar PI).
    await admin.from('payment_drafts').delete().eq('id', draftId);
    return json({ error: 'stripe_create_failed', details: String(e) }, 502);
  }

  // Atualizar draft com payment_intent_id real.
  const { error: updateErr } = await admin
    .from('payment_drafts')
    .update({ payment_intent_id: paymentIntent.id })
    .eq('id', draftId);
  if (updateErr) {
    console.error('[create-payment-intent new] draft update failed:', updateErr.message);
    // Tentar cancelar PI Stripe para evitar charge sem draft.
    try { await stripe.paymentIntents.cancel(paymentIntent.id); } catch (_) { /* swallow */ }
    await admin.from('payment_drafts').delete().eq('id', draftId);
    return json({ error: 'draft_update_failed', details: updateErr.message }, 500);
  }

  console.log('[create-payment-intent new] PI=', paymentIntent.id, 'draft=', draftId,
    'amount=€', (amountCents / 100).toFixed(2));

  return json({
    clientSecret: paymentIntent.client_secret,
    paymentIntentId: paymentIntent.id,
    draftId,
    amountCents,
  });
}

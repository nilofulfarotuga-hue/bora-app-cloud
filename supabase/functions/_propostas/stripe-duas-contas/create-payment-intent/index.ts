// PROPOSTA — supabase/functions/create-payment-intent/index.ts — v30 (duas contas Stripe)
// Missão stripe-empresa-2026-11-01 (autorização do Danilo 01/11/2026 22:03). A tranca do repo
// não deixa esta sessão escrever em supabase/functions/create-payment-intent/; este ficheiro é a
// versão completa pronta a copiar para lá e publicar (verify_jwt=false, como hoje).
// Base: v29 em produção (igual ao repo, código byte a byte; só comentários diferem).
//
// O que muda na v30 (e SÓ isto):
//   • A conta Stripe é decidida por pagamento (_shared/stripe_contas.ts): TVDE nunca passa por
//     aqui; app antiga (sem `stripe_contas_v2: true`) → pessoal; interruptor
//     platform_settings.stripe_conta_nao_tvde='empresa' + chave da empresa → empresa.
//   • Stripe Customer na conta certa (users.stripe_customer_id vs stripe_customer_id_empresa).
//   • payment_drafts.stripe_account gravado ao criar o PI (o finalize copia para orders).
//   • Resposta devolve `stripe_account` e `publishable_key` para a app abrir a folha na conta certa.
//   • Mode A (legacy order_id+amount) também grava orders.stripe_account.
//   • Erro a construir o cliente da empresa → cai para a pessoal, regista e alerta (nunca sem pagar).
//
// v28 (Stripe Customer + saved card), v29 (gorjeta do carrinho no mesmo PI, autorização 30/10 13:40)
// ficam intactos.

import Stripe from 'https://esm.sh/stripe@14.21.0?target=deno';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';
import { corsHeaders } from '../_shared/cors.ts';
import { secretKey } from '../_shared/keys.ts';
import {
  type ContaStripe,
  contaGravada,
  obterOuCriarClienteStripe,
  respostaConta,
  stripeDaLinha,
  stripeParaNovoPagamento,
} from '../_shared/stripe_contas.ts';

const supabaseUrl = Deno.env.get('SUPABASE_URL') ?? '';
const anonKey = Deno.env.get('SUPABASE_ANON_KEY') ?? '';
const serviceKey = secretKey() ?? '';

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

    if (order_id && amount && !cart_input) return await modeLegacy(order_id, amount, body);
    if (cart_input) return await modeNew(req, cart_input, body);
    return json({ error: 'invalid_body', details: 'pass either {order_id, amount} or {cart_input}' }, 400);
  } catch (err) {
    const message = err instanceof Error ? err.message : String(err);
    console.error('[create-payment-intent] error:', message);
    return json({ error: message }, 500);
  }
});

// Mode A (LEGACY): o pedido já existe. Se já tiver conta gravada com PI (nova tentativa), fica
// nessa conta; senão decide-se agora e grava-se em orders.stripe_account.
async function modeLegacy(order_id: string, amount: number, body: unknown): Promise<Response> {
  if (!amount || amount <= 0) return json({ error: 'Invalid amount' }, 400);
  const supabase = createClient(supabaseUrl, serviceKey);
  const { data: order, error: dbError } = await supabase
    .from('orders').select('price, payment_buffer_total, payment_intent_id, stripe_account').eq('id', order_id).maybeSingle();
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

  // v30 — conta: já há PI gravado → a conta dele; senão decide-se agora.
  let stripe: Stripe;
  let conta: ContaStripe;
  if (order.payment_intent_id) {
    ({ stripe, conta } = stripeDaLinha(order));
  } else {
    ({ stripe, conta } = await stripeParaNovoPagamento(supabase, { body, origem: 'create-payment-intent/legacy' }));
  }

  const paymentIntent = await stripe.paymentIntents.create({
    amount: amountCents, currency: 'eur',
    automatic_payment_methods: { enabled: true },
    metadata: { order_id, bora_conta: conta },
  });
  if (contaGravada(order.stripe_account) !== conta) {
    const { error: contaErr } = await supabase.from('orders').update({ stripe_account: conta }).eq('id', order_id);
    if (contaErr) console.error('[create-payment-intent legacy] orders.stripe_account não gravado:', contaErr.message, order_id);
  }
  console.log('[create-payment-intent legacy v30] created:', paymentIntent.id, `order_id=${order_id}`, 'conta=', conta);
  return json({ clientSecret: paymentIntent.client_secret, paymentIntentId: paymentIntent.id, ...respostaConta(conta) });
}

// deno-lint-ignore no-explicit-any
async function modeNew(req: Request, cart: Record<string, any>, body: unknown): Promise<Response> {
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
  // v30 — lê a bandeira ANTES de a tirar do carrinho (não é parte do pedido; não vai ao rascunho).
  const appSabe = appSabeDuasContasNoCarrinho(body, cart);
  if ('stripe_contas_v2' in cart) delete cart.stripe_contas_v2;

  const admin = createClient(supabaseUrl, serviceKey);

  // v30 — a conta deste pagamento (pessoal por defeito; empresa só com app nova + interruptor + chave).
  const { stripe, conta, motivo } = await stripeParaNovoPagamento(admin, {
    body, appSabe, origem: 'create-payment-intent/new',
  });
  const customerId = await obterOuCriarClienteStripe(admin, conta, user.id);

  // v29 (gorjetas 30/10, autorização do Danilo 30/10 13:40): a gorjeta do carrinho vai no MESMO
  // pagamento. Lê a marcação que a app fez antes de abrir o pagamento (client_preparar_gorjeta_checkout):
  // 0 se não há, se o interruptor tips_checkout_junto_pagamento está desligado ou se não é pedido do
  // carrinho (Favores/envios). Soma-se DEPOIS da cotação: nunca entra em margens, buffers, comissões
  // nem taxas. Fica no rascunho (payload.gorjeta_checkout_cents): quando o pedido nascer, o gatilho
  // trg_zz_gorjeta_checkout_na_criacao cria a linha em tips (paga, cobrada_junto). Erro a ler = sem gorjeta.
  let gorjetaCents = 0;
  if (['restaurant', 'storeShopping', 'takeaway'].includes(String(cart.service_type ?? ''))) {
    const { data: g, error: gErr } = await admin.rpc('gorjeta_checkout_para_cobrar', { p_user_id: user.id });
    if (gErr) console.error('[create-payment-intent new] gorjeta não lida (segue sem gorjeta):', gErr.message);
    else gorjetaCents = Math.max(0, Math.round(Number(g ?? 0)));
  }
  const totalCents = amountCents + gorjetaCents;
  const payload = gorjetaCents > 0 ? { ...cart, gorjeta_checkout_cents: gorjetaCents } : cart;
  const metaGorjeta = gorjetaCents > 0 ? { gorjeta_cents: String(gorjetaCents) } : {};

  const { data: draftRow, error: insertErr } = await admin
    .from('payment_drafts')
    .insert({
      payment_intent_id: 'pending_' + crypto.randomUUID(),
      user_id: user.id,
      payload,
      amount_cents: totalCents,
      wallet_applied_cents: walletCents,
      stripe_account: conta, // v30
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
        amount: totalCents, currency: 'eur',
        customer: customerId, payment_method: savedPmId,
        confirm: true, off_session: true,
        automatic_payment_methods: { enabled: true, allow_redirects: 'never' },
        metadata: { draft_id: draftId, user_id: user.id, bora_conta: conta, ...metaGorjeta },
      });
    } else {
      paymentIntent = await stripe.paymentIntents.create({
        amount: totalCents, currency: 'eur',
        ...(customerId ? { customer: customerId, setup_future_usage: 'off_session' as const } : {}),
        automatic_payment_methods: { enabled: true },
        metadata: { draft_id: draftId, user_id: user.id, bora_conta: conta, ...metaGorjeta },
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

  console.log('[create-payment-intent new v30] PI=', paymentIntent.id, 'draft=', draftId,
    'conta=', conta, `(${motivo})`,
    'customer=', customerId ?? 'none', 'savedPm=', savedPmId ?? 'none',
    'status=', paymentIntent.status, 'amount=€', (totalCents / 100).toFixed(2),
    'gorjeta=€', (gorjetaCents / 100).toFixed(2));

  return json({
    clientSecret: paymentIntent.client_secret,
    paymentIntentId: paymentIntent.id,
    draftId,
    amountCents: totalCents,   // v29: o que se cobra (compra + gorjeta do carrinho)
    gorjetaCents,              // v29: 0 = sem gorjeta no mesmo pagamento
    status: paymentIntent.status,
    requiresAction: paymentIntent.status === 'requires_action',
    ...respostaConta(conta),   // v30: stripe_account + publishable_key
  });
}

// A app pode mandar a bandeira no corpo (`stripe_contas_v2`) ou dentro do cart_input (clientes
// antigos do OrderStore mandam só o cart_input). Qualquer uma vale.
// deno-lint-ignore no-explicit-any
function appSabeDuasContasNoCarrinho(body: unknown, cart: Record<string, any>): boolean {
  const b = (body && typeof body === 'object') ? (body as Record<string, unknown>)['stripe_contas_v2'] : undefined;
  const c = cart?.['stripe_contas_v2'];
  return b === true || b === 'true' || c === true || c === 'true';
}

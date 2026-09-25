// supabase/functions/manage-saved-cards/index.ts — v1 (2026-07-21)
//
// Gestao dos cartoes guardados do user autenticado (Carteira Unica, Parte 1/6).
// Complementa list-saved-cards, que so LE. Esta funcao ESCREVE, mas nunca
// movimenta dinheiro:
//   - NAO cria PaymentIntent, NAO cobra, NAO reembolsa.
//   - NAO toca em precos, taxas, comissoes nem bora_tokens.
// As unicas chamadas Stripe sao paymentMethods.detach e customers.update
// (invoice_settings.default_payment_method).
//
// Auth: verify_jwt=true via config.toml. Authorization Bearer com user JWT.
// Service role usado APENAS para SELECT users.stripe_customer_id (RLS bloquearia
// o user de ler colunas administrativas como stripe_customer_id).
//
// Pedido:
//   { action: 'detach'      , payment_method_id: 'pm_xxx' }
//   { action: 'set_default' , payment_method_id: 'pm_xxx' }
//
// Resposta:
//   { ok: true, action, payment_method_id }
//
// Guarda-costas de posse: o payment method tem de pertencer ao Stripe Customer
// do proprio user. Sem isto, um user autenticado podia apagar o cartao de outro
// so por adivinhar o pm_id.

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
const anonKey     = Deno.env.get('SUPABASE_ANON_KEY') ?? '';
const serviceKey  = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '';

// deno-lint-ignore no-explicit-any
const json = (body: any, status = 200) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  });

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders });

  try {
    const authHeader = req.headers.get('Authorization') ?? '';
    const token = authHeader.replace(/^Bearer\s+/i, '').trim();
    if (!token) return json({ error: 'missing_token' }, 401);

    const userClient = createClient(supabaseUrl, anonKey, {
      global: { headers: { Authorization: `Bearer ${token}` } },
    });
    const { data: userData, error: authErr } = await userClient.auth.getUser();
    const user = userData?.user;
    if (authErr || !user) return json({ error: 'unauthorized', details: authErr?.message }, 401);

    const body = await req.json().catch(() => ({}));
    const action = String(body?.action ?? '');
    const pmId = String(body?.payment_method_id ?? '');

    if (action !== 'detach' && action !== 'set_default') {
      return json({ error: 'invalid_action', details: 'use detach ou set_default' }, 400);
    }
    if (!pmId.startsWith('pm_')) {
      return json({ error: 'invalid_payment_method_id' }, 400);
    }

    // Service role: ler stripe_customer_id (admin-only column).
    const admin = createClient(supabaseUrl, serviceKey);
    const { data: row, error: selErr } = await admin
      .from('users')
      .select('stripe_customer_id')
      .eq('id', user.id)
      .maybeSingle();

    if (selErr) {
      console.error('[manage-saved-cards] users select failed:', selErr.message);
      return json({ error: 'db_error', details: selErr.message }, 500);
    }

    const customerId = row?.stripe_customer_id as string | undefined;
    if (!customerId) return json({ error: 'no_customer' }, 404);

    // Posse: o cartao tem de estar ligado a ESTE customer.
    const pm = await stripe.paymentMethods.retrieve(pmId);
    const pmCustomer = typeof pm.customer === 'string' ? pm.customer : pm.customer?.id ?? null;
    if (pmCustomer !== customerId) {
      console.warn('[manage-saved-cards] ownership mismatch', { user: user.id, pmId });
      return json({ error: 'not_your_card' }, 403);
    }

    if (action === 'detach') {
      await stripe.paymentMethods.detach(pmId);
    } else {
      await stripe.customers.update(customerId, {
        invoice_settings: { default_payment_method: pmId },
      });
    }

    return json({ ok: true, action, payment_method_id: pmId });
  } catch (err) {
    const msg = err instanceof Error ? err.message : String(err);
    console.error('[manage-saved-cards] error:', msg);
    return json({ error: msg }, 500);
  }
});

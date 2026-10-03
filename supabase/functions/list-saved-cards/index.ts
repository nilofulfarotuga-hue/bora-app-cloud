// supabase/functions/list-saved-cards/index.ts — v1 (2026-05-14)
//
// Lista cartoes guardados do user autenticado via Stripe Customer.
//
// Auth: verify_jwt=true via config.toml. Authorization Bearer com user JWT.
// Service role usado APENAS para SELECT users.stripe_customer_id (RLS bloquearia
// o user de ler colunas administrativas como stripe_customer_id).
//
// Resposta:
//   { cards: [{ id, brand, last4, exp_month, exp_year, is_default }, ...] }
// Vazia ([]) se user ainda nao tem stripe_customer_id (nunca pagou com cartao).

import Stripe from 'https://esm.sh/stripe@14.21.0?target=deno';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, GET, OPTIONS',
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

    // Service role: ler stripe_customer_id (admin-only column).
    const admin = createClient(supabaseUrl, serviceKey);
    const { data: row, error: selErr } = await admin
      .from('users')
      .select('stripe_customer_id')
      .eq('id', user.id)
      .maybeSingle();

    if (selErr) {
      console.error('[list-saved-cards] users select failed:', selErr.message);
      return json({ error: 'db_error', details: selErr.message }, 500);
    }

    const customerId = row?.stripe_customer_id as string | undefined;
    if (!customerId) return json({ cards: [] });

    const [pmList, customer] = await Promise.all([
      stripe.paymentMethods.list({ customer: customerId, type: 'card', limit: 10 }),
      stripe.customers.retrieve(customerId),
    ]);

    const defaultPm = (customer && !customer.deleted)
      ? ((customer as Stripe.Customer).invoice_settings?.default_payment_method ?? null)
      : null;
    const defaultPmId = typeof defaultPm === 'string'
      ? defaultPm
      : (defaultPm as Stripe.PaymentMethod | null)?.id ?? null;

    const cards = pmList.data.map((pm) => ({
      id: pm.id,
      brand: pm.card?.brand ?? 'card',
      last4: pm.card?.last4 ?? '••••',
      exp_month: pm.card?.exp_month ?? null,
      exp_year: pm.card?.exp_year ?? null,
      is_default: pm.id === defaultPmId,
    }));

    return json({ cards });
  } catch (err) {
    const msg = err instanceof Error ? err.message : String(err);
    console.error('[list-saved-cards] error:', msg);
    return json({ error: msg }, 500);
  }
});

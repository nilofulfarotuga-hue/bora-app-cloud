// supabase/functions/pay-debt-standalone/index.ts
// v2 (2026-08-16 — F3e MISSAO TOTAL): o caminho "mbway" criava o PI com
// payment_method_types ['multibanco'] e confirmava com type 'multibanco' —
// método ERRADO (Multibanco é referência bancária, não é o push MB WAY).
// Corrigido para 'mb_way' (mesmo padrão de create-mbway-payment-intent) +
// telefone normalizado para E.164 com '+'. Nenhum valor cobrado foi alterado.
// v1 (2026-05-12 — BUG #1 frontend): standalone PI para liquidar dívida wallet.
// Suporta card + MBWay. Webhook stripe-webhook v23 detecta metadata e settle automaticamente.

import Stripe from 'https://esm.sh/stripe@14.21.0?target=deno';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';
import { corsHeaders } from '../_shared/cors.ts';

const stripe = new Stripe(Deno.env.get('STRIPE_SECRET_KEY') ?? '', {
  apiVersion: '2023-10-16',
  httpClient: Stripe.createFetchHttpClient(),
});

const json = (body: any, status = 200) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  });

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders });

  const supabaseUrl = Deno.env.get('SUPABASE_URL') ?? '';
  const anonKey = Deno.env.get('SUPABASE_ANON_KEY') ?? '';
  const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '';
  if (!supabaseUrl || !serviceKey || !anonKey) return json({ error: 'server_misconfigured' }, 500);

  let amountCents: number | undefined;
  let paymentMethod: 'card' | 'mbway' = 'card';
  let mbwayPhone: string | undefined;
  try {
    const body = await req.json();
    amountCents = Number(body?.amount_cents);
    if (body?.payment_method === 'mbway') paymentMethod = 'mbway';
    mbwayPhone = body?.mbway_phone;
  } catch (_) {
    return json({ error: 'invalid_body' }, 400);
  }
  if (!Number.isFinite(amountCents!) || amountCents! < 50) {
    return json({ error: 'amount_must_be_at_least_50_cents' }, 400);
  }
  if (paymentMethod === 'mbway' && (!mbwayPhone || !/^\+?351\d{9}$/.test(mbwayPhone))) {
    return json({ error: 'mbway_phone_required_e164_pt' }, 400);
  }

  const authHeader = req.headers.get('Authorization') ?? '';
  const token = authHeader.replace(/^Bearer\s+/i, '').trim();
  if (!token) return json({ error: 'missing_token' }, 401);

  const userClient = createClient(supabaseUrl, anonKey, {
    global: { headers: { Authorization: `Bearer ${token}` } },
  });
  const { data: userData, error: authError } = await userClient.auth.getUser();
  const user = userData?.user;
  if (authError || !user) return json({ error: 'unauthorized' }, 401);

  const admin = createClient(supabaseUrl, serviceKey);

  const { data: wallet, error: walletErr } = await admin
    .from('client_wallets')
    .select('free_balance_cents')
    .eq('user_id', user.id)
    .maybeSingle();
  if (walletErr) return json({ error: 'wallet_lookup_failed', details: walletErr.message }, 500);

  const balance = wallet?.free_balance_cents ?? 0;
  const debtAbs = balance < 0 ? -balance : 0;

  if (debtAbs === 0) return json({ error: 'no_debt_to_settle' }, 409);
  if (debtAbs < 50) return json({ error: 'debt_below_stripe_minimum', debt_cents: debtAbs }, 409);
  if (amountCents! < debtAbs) {
    return json({ error: 'amount_below_debt', debt_cents: debtAbs }, 409);
  }

  try {
    // v2 (2026-08-16): MB WAY exige E.164 com '+' — a regex acima aceita sem.
    const e164Phone = mbwayPhone && !mbwayPhone.startsWith('+')
      ? '+' + mbwayPhone
      : mbwayPhone;

    const piParams: Stripe.PaymentIntentCreateParams = {
      amount: amountCents!,
      currency: 'eur',
      payment_method_types: paymentMethod === 'mbway' ? ['mb_way'] : ['card'],
      metadata: {
        standalone_debt_settle: 'true',
        debt_settle_cents: String(amountCents),
        user_id: user.id,
        source: 'pay-debt-standalone',
      },
    };
    const pi = await stripe.paymentIntents.create(piParams, {
      idempotencyKey: `paydebt-${user.id}-${amountCents}-${Date.now()}`,
    });

    if (paymentMethod === 'mbway' && e164Phone) {
      await stripe.paymentIntents.confirm(pi.id, {
        payment_method_data: {
          type: 'mb_way',
          billing_details: { phone: e164Phone, email: user.email ?? undefined },
        },
      });
    }

    return json({
      clientSecret: pi.client_secret,
      paymentIntentId: pi.id,
      mode: paymentMethod,
      debt_cents: debtAbs,
      amount_cents: amountCents,
    });
  } catch (e: any) {
    console.error('[pay-debt-standalone] stripe failed:', e);
    return json({ error: 'stripe_pi_create_failed', details: String(e?.message ?? e) }, 502);
  }
});

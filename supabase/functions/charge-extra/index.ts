import Stripe from 'https://esm.sh/stripe@14.21.0?target=deno';
import { corsHeaders } from '../_shared/cors.ts';

const stripe = new Stripe(Deno.env.get('STRIPE_SECRET_KEY') ?? '', {
  apiVersion: '2023-10-16',
  httpClient: Stripe.createFetchHttpClient(),
});

// Authenticated users: verify_jwt = true in config.toml handles auth.
// Supabase rejects anonymous calls before this function runs.
Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }

  try {
    const { amount, customerId } = await req.json() as {
      amount?: number;
      customerId?: string;
    };

    if (typeof amount !== 'number' || !isFinite(amount) || amount <= 0) {
      return new Response(
        JSON.stringify({ error: 'amount must be a positive number (euros)' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
      );
    }

    const amountCents = Math.round(amount * 100);

    if (amountCents < 50) {
      return new Response(
        JSON.stringify({ error: 'Amount too small (min 0.50 EUR)' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
      );
    }

    const intentParams: Stripe.PaymentIntentCreateParams = {
      amount: amountCents,
      currency: 'eur',
      metadata: { type: 'extra_charge' },
      automatic_payment_methods: { enabled: true },
    };

    if (customerId && typeof customerId === 'string' && customerId.trim() !== '') {
      intentParams.customer = customerId.trim();
    }

    const intent = await stripe.paymentIntents.create(intentParams);

    console.log('[charge-extra] created:', intent.id, `€${amount.toFixed(2)}`);

    return new Response(
      JSON.stringify({
        clientSecret: intent.client_secret,
        paymentIntentId: intent.id,
      }),
      { headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
    );
  } catch (err) {
    const message = err instanceof Error ? err.message : String(err);
    console.error('[charge-extra] error:', message);
    return new Response(
      JSON.stringify({ error: message }),
      { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
    );
  }
});

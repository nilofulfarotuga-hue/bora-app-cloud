import Stripe from 'https://esm.sh/stripe@14.21.0?target=deno';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';
import { corsHeaders } from '../_shared/cors.ts';

// BUG 13 — Stripe mode toggle. Default 'live'.
const STRIPE_MODE = (Deno.env.get('BORA_STRIPE_MODE') ?? 'live').toLowerCase();
const stripeSecretKey = STRIPE_MODE === 'test'
  ? (Deno.env.get('STRIPE_TEST_SECRET_KEY') ?? '')
  : (Deno.env.get('STRIPE_SECRET_KEY') ?? '');
const stripe = new Stripe(stripeSecretKey, {
  apiVersion: '2023-10-16',
  httpClient: Stripe.createFetchHttpClient(),
});

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }

  try {
    const { order_id, phone } = await req.json() as {
      order_id?: string;
      phone?: string;
    };

    if (!order_id || !phone) {
      return new Response(
        JSON.stringify({ error: 'order_id and phone are required' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
      );
    }

    // Normalise PT phone → E.164 (+351XXXXXXXXX)
    const e164 = phone.startsWith('+') ? phone : `+351${phone.replace(/^0/, '')}`;

    const supabase = createClient(
      Deno.env.get('SUPABASE_URL') ?? '',
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '',
    );

    const { data: order, error: dbErr } = await supabase
      .from('orders')
      .select('payment_buffer_total, payment_method, payment_status')
      .eq('id', order_id)
      .maybeSingle();

    if (dbErr || !order) {
      return new Response(
        JSON.stringify({ error: 'Order not found' }),
        { status: 404, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
      );
    }

    if (order.payment_method !== 'mbway') {
      return new Response(
        JSON.stringify({ error: 'Order is not an MBWay order' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
      );
    }

    if (order.payment_status !== 'pending') {
      return new Response(
        JSON.stringify({ error: 'Order already processed' }),
        { status: 409, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
      );
    }

    const amountCents = Math.round((order.payment_buffer_total as number) * 100);
    if (amountCents < 50) {
      return new Response(
        JSON.stringify({ error: 'Amount too small (min 0.50 EUR)' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
      );
    }

    // v21 (2026-05-15) — server-side confirmation com billing_details.phone.
    //
    // Histórico:
    //   v19 — tentou server-confirm com payment_method_data.mb_way.phone
    //         (parâmetro inexistente) → 500.
    //   v20 — mudou para PaymentSheet client-side. Problema: o PaymentSheet
    //         para mb_way não retorna após enviar o push (espera confirmação
    //         na app MBWay). Utilizador fecha PaymentSheet → StripeException
    //         → pedido cancelado.
    //   v21 — server-confirm CORRECTO com payment_method_data.billing_details.phone.
    //         O parâmetro correcto é billing_details.phone (não mb_way.phone).
    //         Stripe confirma o PI, envia push MBWay imediatamente, devolve
    //         paymentIntentId. Flutter mostra _MBWayWaitingDialog que faz poll
    //         a payment_status até o webhook (payment_intent.succeeded) marcar
    //         como 'paid'.
    const intent = await stripe.paymentIntents.create({
      amount: amountCents,
      currency: 'eur',
      payment_method_types: ['mb_way'],
      payment_method_data: {
        type: 'mb_way',
        billing_details: { phone: e164 },
      },
      confirm: true,
      metadata: { order_id },
    }, { idempotencyKey: `mbway_${order_id}` });

    console.log('[create-mbway-payment-intent] intent confirmed (server-side):',
      intent.id, `order=${order_id}`, `phone=${e164}`, `status=${intent.status}`, `mode=${STRIPE_MODE}`);

    // Guardar payment_intent_id no pedido para auditoria e reconciliação.
    const { error: piUpdateErr } = await supabase
      .from('orders')
      .update({ payment_intent_id: intent.id })
      .eq('id', order_id);

    if (piUpdateErr) {
      console.error('[create-mbway-payment-intent] failed to save payment_intent_id:',
        piUpdateErr.message, intent.id);
      // não bloquear o fluxo — o webhook ainda consegue resolver via metadata.order_id
    }

    return new Response(
      JSON.stringify({
        ok: true,
        paymentIntentId: intent.id,
        status: intent.status,
        mode: STRIPE_MODE,
      }),
      { headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
    );
  } catch (err) {
    const message = err instanceof Error ? err.message : String(err);
    console.error('[create-mbway-payment-intent] error:', message);
    return new Response(
      JSON.stringify({ error: message }),
      { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
    );
  }
});

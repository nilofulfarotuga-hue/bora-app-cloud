import Stripe from 'https://esm.sh/stripe@14.21.0?target=deno';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';
import {
  CANCEL_FEE_BEFORE_DISPATCH_EUR,
  CANCEL_FEE_AFTER_ACCEPT_RATIO,
  CANCEL_FEE_AFTER_PURCHASE_RATIO,
} from '../_shared/business_rules.ts';

// Suppress unused-import warnings — these constants are referenced in comments
// and will be used by the refund logic when cancel flow is implemented.
void CANCEL_FEE_BEFORE_DISPATCH_EUR;
void CANCEL_FEE_AFTER_ACCEPT_RATIO;
void CANCEL_FEE_AFTER_PURCHASE_RATIO;

const stripe = new Stripe(Deno.env.get('STRIPE_SECRET_KEY') ?? '', {
  apiVersion: '2023-10-16',
  httpClient: Stripe.createFetchHttpClient(),
});

const supabase = createClient(
  Deno.env.get('SUPABASE_URL') ?? '',
  Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '',
);

Deno.serve(async (req: Request) => {
  const signature = req.headers.get('stripe-signature');
  const webhookSecret = Deno.env.get('STRIPE_WEBHOOK_SECRET');

  if (!signature || !webhookSecret) {
    return new Response('Missing stripe-signature or webhook secret', { status: 400 });
  }

  const body = await req.text();

  let event: Stripe.Event;
  try {
    event = await stripe.webhooks.constructEventAsync(body, signature, webhookSecret);
  } catch (err) {
    const msg = err instanceof Error ? err.message : String(err);
    console.error('[stripe-webhook] signature verification failed:', msg);
    return new Response(`Webhook signature error: ${msg}`, { status: 400 });
  }

  console.log('[stripe-webhook] event:', event.type);

  switch (event.type) {
    // ── Payment succeeded ────────────────────────────────────────────────────
    case 'payment_intent.succeeded': {
      const intent = event.data.object as Stripe.PaymentIntent;
      const { error } = await supabase
        .from('orders')
        .update({ payment_status: 'paid' })
        .eq('payment_intent_id', intent.id);

      if (error) {
        console.error('[stripe-webhook] payment_intent.succeeded DB update error:', error.message);
      } else {
        console.log('[stripe-webhook] order marked paid for intent:', intent.id);
      }
      break;
    }

    // ── Payment failed ───────────────────────────────────────────────────────
    case 'payment_intent.payment_failed': {
      const intent = event.data.object as Stripe.PaymentIntent;
      const failureMsg = intent.last_payment_error?.message ?? 'unknown';

      const { error } = await supabase
        .from('orders')
        .update({ payment_status: 'failed' })
        .eq('payment_intent_id', intent.id);

      if (error) {
        console.error('[stripe-webhook] payment_failed DB update error:', error.message);
      } else {
        console.warn('[stripe-webhook] order payment failed:', intent.id, failureMsg);
      }
      break;
    }

    // ── Charge refunded (partial or full) ────────────────────────────────────
    // Triggered by cancel flows:
    //   - before dispatch   → 1.50 EUR retained  (CANCEL_FEE_BEFORE_DISPATCH_EUR)
    //   - after acceptance  → 50% retained        (CANCEL_FEE_AFTER_ACCEPT_RATIO)
    //   - after purchase    → 100% retained       (CANCEL_FEE_AFTER_PURCHASE_RATIO)
    case 'charge.refunded': {
      const charge = event.data.object as Stripe.Charge;
      console.log('[stripe-webhook] charge refunded:', charge.id, `amount_refunded=${charge.amount_refunded}`);
      // Status update (refunded/refundPending) is handled by the Flutter client
      // via PaymentService.refund() → OrderStore.finalizePurchase().
      break;
    }

    default:
      console.log('[stripe-webhook] unhandled event type:', event.type);
  }

  return new Response(JSON.stringify({ received: true }), {
    headers: { 'Content-Type': 'application/json' },
  });
});

// =============================================================================
// stripe-connect-webhook — eventos de Stripe CONNECT (2026-08-06).
// ⚠️ SEPARADO do stripe-webhook existente (pagamentos) — NÃO lhe toca.
// verify_jwt=false; autentica por assinatura própria (STRIPE_CONNECT_WEBHOOK_SECRET).
//
// Eventos tratados:
//   account.updated                  → espelha estado via RPC apply_stripe_account_update
//   account.application.deauthorized → marca a conta como 'disabled'
//   payout.paid / payout.failed      → auditoria em stripe_connect_events;
//                                      failed → notify_admin_event (Danilo)
//
// Idempotência: INSERT em stripe_connect_events (event_id PK). Repetido = 200.
// =============================================================================

import Stripe from 'https://esm.sh/stripe@14.21.0?target=deno';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const STRIPE_MODE = (Deno.env.get('BORA_STRIPE_MODE') ?? 'live').toLowerCase();
const stripeSecretKey =
  STRIPE_MODE === 'test'
    ? (Deno.env.get('STRIPE_TEST_SECRET_KEY') ?? '')
    : (Deno.env.get('STRIPE_SECRET_KEY') ?? '');
const stripe = new Stripe(stripeSecretKey, {
  apiVersion: '2023-10-16',
  httpClient: Stripe.createFetchHttpClient(),
});

const admin = createClient(
  Deno.env.get('SUPABASE_URL') ?? '',
  Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '',
);

Deno.serve(async (req: Request) => {
  const signature = req.headers.get('stripe-signature');
  const webhookSecret = Deno.env.get('STRIPE_CONNECT_WEBHOOK_SECRET');

  if (!signature || !webhookSecret) {
    // Fail-closed: sem secret configurado, nenhum evento é aceite.
    return new Response('Missing stripe-signature or connect webhook secret', { status: 400 });
  }

  const body = await req.text();
  let event: Stripe.Event;
  try {
    event = await stripe.webhooks.constructEventAsync(body, signature, webhookSecret);
  } catch (err) {
    const msg = err instanceof Error ? err.message : String(err);
    console.error('[stripe-connect-webhook] signature failed:', msg);
    return new Response(`Webhook signature error: ${msg}`, { status: 400 });
  }

  // Conta Connect de origem (eventos de connected accounts trazem event.account).
  const eventAccount: string | null =
    (event as unknown as { account?: string }).account ??
    ((event.data.object as { id?: string })?.id?.startsWith?.('acct_')
      ? (event.data.object as { id: string }).id
      : null);

  // Idempotência: evento repetido é ignorado (200 para a Stripe não reenviar).
  const { error: insErr } = await admin.from('stripe_connect_events').insert({
    event_id: event.id,
    type: event.type,
    account_id: eventAccount,
    payload: event.data.object as unknown as Record<string, unknown>,
  });
  if (insErr) {
    if (insErr.code === '23505') {
      console.log('[stripe-connect-webhook] duplicate event ignored:', event.id);
      return new Response(JSON.stringify({ received: true, duplicate: true }), {
        headers: { 'Content-Type': 'application/json' },
      });
    }
    // Falha a gravar auditoria → 500 para a Stripe voltar a tentar.
    console.error('[stripe-connect-webhook] audit insert failed:', insErr.message);
    return new Response('audit insert failed', { status: 500 });
  }

  console.log('[stripe-connect-webhook] event:', event.type, eventAccount ?? '');

  try {
    switch (event.type) {
      case 'account.updated': {
        const acct = event.data.object as Stripe.Account;
        const { data, error } = await admin.rpc('apply_stripe_account_update', {
          p_account_id: acct.id,
          p_charges_enabled: acct.charges_enabled ?? false,
          p_payouts_enabled: acct.payouts_enabled ?? false,
          p_currently_due: acct.requirements?.currently_due ?? [],
          p_disabled_reason: acct.requirements?.disabled_reason ?? null,
        });
        if (error) throw new Error(`apply_stripe_account_update: ${error.message}`);
        console.log('[stripe-connect-webhook] account.updated →', JSON.stringify(data));
        break;
      }

      case 'account.application.deauthorized': {
        if (eventAccount) {
          const { error } = await admin.rpc('apply_stripe_account_update', {
            p_account_id: eventAccount,
            p_charges_enabled: false,
            p_payouts_enabled: false,
            p_currently_due: [],
            p_disabled_reason: 'application_deauthorized',
          });
          if (error) throw new Error(`deauthorized update: ${error.message}`);
        }
        break;
      }

      case 'payout.paid':
      case 'payout.failed': {
        // Auditoria já ficou em stripe_connect_events (insert acima).
        const payout = event.data.object as Stripe.Payout;
        if (event.type === 'payout.failed') {
          const { error } = await admin.rpc('notify_admin_event', {
            p_event_type: 'stripe_connect_payout_failed',
            p_severity: 'high',
            p_summary:
              `Payout Stripe FALHOU: €${(payout.amount / 100).toFixed(2)} ` +
              `na conta ${eventAccount ?? '?'} (${payout.failure_message ?? 'sem motivo'})`,
            p_entity_type: 'stripe_account',
            p_entity_id: eventAccount,
            p_payload: {
              payout_id: payout.id,
              amount_cents: payout.amount,
              currency: payout.currency,
              failure_code: payout.failure_code,
              failure_message: payout.failure_message,
            },
            p_deep_link: null,
          });
          if (error) console.error('[stripe-connect-webhook] notify failed:', error.message);
        }
        break;
      }

      default:
        // Evento não tratado — fica só na auditoria.
        break;
    }
  } catch (err) {
    const msg = err instanceof Error ? err.message : String(err);
    console.error('[stripe-connect-webhook] handler error:', msg);
    // Apaga o registo de idempotência para a Stripe poder reentregar.
    await admin.from('stripe_connect_events').delete().eq('event_id', event.id);
    return new Response(`handler error: ${msg}`, { status: 500 });
  }

  return new Response(JSON.stringify({ received: true }), {
    headers: { 'Content-Type': 'application/json' },
  });
});

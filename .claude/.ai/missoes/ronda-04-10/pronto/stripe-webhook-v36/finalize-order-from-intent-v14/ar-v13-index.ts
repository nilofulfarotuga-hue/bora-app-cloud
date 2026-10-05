// supabase/functions/finalize-order-from-intent/index.ts — BUG 1 / Fase 2
// Service-role only. Invoked by stripe-webhook on payment_intent.succeeded
// (when metadata.draft_id present) to atomically create the order from the
// payment_drafts payload after Stripe charge confirmed.

import Stripe from 'https://esm.sh/stripe@14.21.0?target=deno';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';
import { corsHeaders } from '../_shared/cors.ts';

const stripe = new Stripe(Deno.env.get('STRIPE_SECRET_KEY') ?? '', {
  apiVersion: '2023-10-16',
  httpClient: Stripe.createFetchHttpClient(),
});

const supabaseUrl = Deno.env.get('SUPABASE_URL') ?? '';
const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '';

// deno-lint-ignore no-explicit-any
const json = (body: any, status = 200) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  });

function jwtRole(authHeader: string): string | null {
  const token = authHeader.replace(/^Bearer\s+/i, '').trim();
  const parts = token.split('.');
  if (parts.length !== 3) return null;
  try {
    const pad = parts[1] + '==='.slice((parts[1].length + 3) % 4);
    const claimsJson = atob(pad.replace(/-/g, '+').replace(/_/g, '/'));
    const claims = JSON.parse(claimsJson);
    return typeof claims.role === 'string' ? claims.role : null;
  } catch {
    return null;
  }
}

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders });

  const role = jwtRole(req.headers.get('authorization') ?? '');
  if (role !== 'service_role') return json({ error: 'unauthorized: admin only' }, 401);

  // deno-lint-ignore no-explicit-any
  let body: any;
  try { body = await req.json(); } catch (_) { return json({ error: 'invalid_body' }, 400); }
  const payment_intent_id = typeof body?.payment_intent_id === 'string' ? body.payment_intent_id : null;
  if (!payment_intent_id) return json({ error: 'payment_intent_id required' }, 400);

  const admin = createClient(supabaseUrl, serviceKey);

  const { data: draft, error: draftErr } = await admin
    .from('payment_drafts')
    .select('id, user_id, payload, amount_cents, used_at, order_id, expires_at')
    .eq('payment_intent_id', payment_intent_id)
    .maybeSingle();

  if (draftErr) {
    console.error('[finalize] draft lookup failed:', draftErr.message);
    return json({ error: 'draft_lookup_failed', details: draftErr.message }, 500);
  }
  if (!draft) {
    console.warn('[finalize] no draft for PI:', payment_intent_id);
    return json({ error: 'draft_not_found', payment_intent_id }, 404);
  }

  if (draft.used_at && draft.order_id) {
    console.log('[finalize] idempotent — order already created:', draft.order_id);
    return json({ ok: true, order_id: draft.order_id, idempotent: true });
  }

  let pi: Stripe.PaymentIntent;
  try {
    pi = await stripe.paymentIntents.retrieve(payment_intent_id);
  } catch (e) {
    console.error('[finalize] PI retrieve failed:', e);
    return json({ error: 'pi_retrieve_failed', details: String(e) }, 502);
  }
  if (pi.status !== 'succeeded' || !pi.latest_charge) {
    console.warn('[finalize] PI not succeeded:', payment_intent_id, 'status=', pi.status);
    return json({ error: 'pi_not_succeeded', status: pi.status }, 409);
  }

  // deno-lint-ignore no-explicit-any
  const payload = draft.payload as Record<string, any>;
  payload.payment_already_confirmed = true;
  payload.payment_intent_id = payment_intent_id;

  const { data: rpcData, error: rpcErr } = await admin.rpc('create_order', { p_input: payload });
  if (rpcErr || !rpcData) {
    console.error('[finalize] create_order RPC failed:', rpcErr?.message);
    return json({ error: 'create_order_failed', details: rpcErr?.message }, 500);
  }
  // deno-lint-ignore no-explicit-any
  const orderId = (rpcData as any).order_id as string;

  const { error: markErr } = await admin
    .from('payment_drafts')
    .update({ used_at: new Date().toISOString(), order_id: orderId })
    .eq('id', draft.id);
  if (markErr) {
    console.error('[finalize] WARN: order created but draft mark failed:', markErr.message);
  }

  const { data: orderRow, error: fetchErr } = await admin
    .from('orders')
    .select('status, is_partner_store, service_type')
    .eq('id', orderId)
    .single();

  if (fetchErr || !orderRow) {
    console.error('[finalize] order fetch failed after create:', fetchErr?.message);
    return json({ ok: true, order_id: orderId, dispatch_warning: 'order_fetch_failed' });
  }

  const isPartnerRestaurant = orderRow.is_partner_store === true && orderRow.service_type === 'restaurant';

  if (!isPartnerRestaurant && (orderRow.status === 'created' || orderRow.status === 'preparing')) {
    const { error: statusErr } = await admin
      .from('orders')
      .update({ status: 'callingDriver' })
      .eq('id', orderId)
      .in('status', ['created', 'preparing']);

    if (statusErr) {
      console.error('[finalize] status advance failed:', statusErr.message);
    } else {
      console.log('[finalize] order advanced to callingDriver:', orderId);
      try {
        const dispatchUrl = `${supabaseUrl}/functions/v1/dispatch-engine`;
        const dispatchRes = await fetch(dispatchUrl, {
          method: 'POST',
          headers: {
            'Content-Type': 'application/json',
            'Authorization': `Bearer ${serviceKey}`,
          },
          body: JSON.stringify({ orderId }),
        });
        console.log('[finalize] dispatch invoked:', orderId, 'status:', dispatchRes.status);
      } catch (e) {
        console.error('[finalize] dispatch invoke failed:', e);
      }
    }
  } else {
    console.log('[finalize] dispatch not triggered (partner restaurant or non-pending status):', orderId);
  }

  return json({ ok: true, order_id: orderId, idempotent: false });
});

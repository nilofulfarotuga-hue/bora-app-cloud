// ============================================================================
// reprocess-refund — Bloco 4 (recuperação de reembolso falhado) · 2026-06-29
// Admin-only. Idempotente: claim refund_status 'failed'→'processing' (uma execução
// ganha); cartão reusa a MESMA idempotency key do refund original (Stripe nunca
// duplica); wallet 'failed' = RPC fez rollback, logo re-creditar é seguro.
// Audita em admin_audit_log (action='reprocess_refund').
// ============================================================================
import Stripe from 'https://esm.sh/stripe@14.21.0?target=deno';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';
import { corsHeaders } from '../_shared/cors.ts';

const stripe = new Stripe(Deno.env.get('STRIPE_SECRET_KEY') ?? '', {
  apiVersion: '2023-10-16',
  httpClient: Stripe.createFetchHttpClient(),
});

const json = (b: any, s = 200) =>
  new Response(JSON.stringify(b), { status: s, headers: { ...corsHeaders, 'Content-Type': 'application/json' } });

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders });

  const url = Deno.env.get('SUPABASE_URL') ?? '';
  const anon = Deno.env.get('SUPABASE_ANON_KEY') ?? '';
  const svc = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '';
  if (!url || !anon || !svc) return json({ error: 'server_misconfigured' }, 500);

  let orderId: string | undefined;
  try { const b = await req.json(); orderId = b?.order_id; } catch (_) { return json({ error: 'invalid_body' }, 400); }
  if (!orderId || typeof orderId !== 'string') return json({ error: 'order_id required' }, 400);

  const token = (req.headers.get('Authorization') ?? '').replace(/^Bearer\s+/i, '').trim();
  if (!token) return json({ error: 'missing_token' }, 401);

  const userClient = createClient(url, anon, { global: { headers: { Authorization: `Bearer ${token}` } } });
  const { data: ud } = await userClient.auth.getUser();
  const user = ud?.user;
  if (!user) return json({ error: 'unauthorized' }, 401);
  const { data: adm } = await userClient.rpc('is_admin');
  if (adm !== true) return json({ error: 'not_admin' }, 403);

  const admin = createClient(url, svc);

  // CLAIM idempotente — só avança quem estiver realmente 'failed'.
  const { data: claimed, error: cErr } = await admin
    .from('orders')
    .update({ refund_status: 'processing' })
    .eq('id', orderId).eq('refund_status', 'failed')
    .select('id, user_id, refund_amount, refund_method, payment_method, payment_intent_id');
  if (cErr) return json({ error: 'claim_failed', details: cErr.message }, 500);
  if (!claimed || claimed.length === 0) return json({ ok: true, idempotent: true, message: 'nada_a_reprocessar' });

  const o = claimed[0];
  const refundCents = Math.round(Number(o.refund_amount ?? 0) * 100);
  let outcome = '';
  let newStatus = 'failed';

  try {
    if (refundCents <= 0) {
      newStatus = 'refunded'; outcome = 'zero';
    } else if (o.refund_method === 'wallet' || o.payment_method !== 'card') {
      const { data: cr } = await admin.from('cancellation_requests').select('cancel_stage').eq('order_id', orderId).maybeSingle();
      const rpcName = cr?.cancel_stage === 'grace' ? 'wallet_credit_refund_full' : 'wallet_credit_refund_split';
      const { error: wErr } = await admin.rpc(rpcName, { p_order_id: orderId, p_user_id: o.user_id, p_total_cents: refundCents, p_reason: 'reprocess_cancel_refund' });
      if (wErr) throw new Error('wallet: ' + wErr.message);
      newStatus = 'completed'; outcome = 'wallet';
    } else {
      if (!o.payment_intent_id) throw new Error('no_payment_intent');
      const idem = `refund-${o.payment_intent_id}-${refundCents}`; // MESMA key do original
      const r = await stripe.refunds.create({ payment_intent: o.payment_intent_id, amount: refundCents }, { idempotencyKey: idem });
      newStatus = 'pending'; outcome = 'stripe:' + r.id;
    }
  } catch (e) {
    await admin.from('orders').update({ refund_status: 'failed' }).eq('id', orderId);
    try { await admin.from('admin_audit_log').insert({ admin_id: user.id, admin_email: user.email, action: 'reprocess_refund', entity_type: 'order', entity_id_text: orderId, details: { result: 'error', error: String(e), admin_email: user.email } }); } catch (_) {}
    return json({ error: 'reprocess_failed', details: String(e) }, 502);
  }

  await admin.from('orders').update({ refund_status: newStatus }).eq('id', orderId);
  try { await admin.from('admin_audit_log').insert({ admin_id: user.id, admin_email: user.email, action: 'reprocess_refund', entity_type: 'order', entity_id_text: orderId, details: { old_status: 'failed', new_status: newStatus, result: outcome, admin_email: user.email } }); } catch (_) {}
  return json({ ok: true, order_id: orderId, refund_status: newStatus, outcome });
});

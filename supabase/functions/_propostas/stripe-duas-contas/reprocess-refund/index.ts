// PROPOSTA — supabase/functions/reprocess-refund/index.ts — v6 (duas contas Stripe)
// Missão stripe-empresa-2026-11-01 (autorização do Danilo 01/11/2026 22:03). A tranca do repo
// não deixa esta sessão escrever em supabase/functions/reprocess-refund/; este ficheiro é a
// versão completa pronta a copiar para lá e publicar (verify_jwt=true, como hoje).
// Base: v5 EM PRODUÇÃO (o repo estava atrás; foi ressincronizado nesta missão).
//
// O que muda na v6 (e SÓ isto): o reembolso na Stripe sai pela conta gravada no pedido
// (orders.stripe_account) — pedido pago na pessoal volta pela pessoal, pedido pago na empresa
// volta pela empresa. Sem chave dessa conta → falha registada como antes (refund_status 'failed').
//
// v4/v5: o reembolso volta pelo MEIO ORIGINAL (cartão E MB Way voltam à Stripe, no máximo o que
// ainda se pode devolver lá; saldo só com refund_method 'wallet' ou sem Stripe). Intacto.
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';
import { corsHeaders } from '../_shared/cors.ts';
import { secretKey } from '../_shared/keys.ts';
import { stripeDaLinha } from '../_shared/stripe_contas.ts';

const json = (b: any, s = 200) =>
  new Response(JSON.stringify(b), { status: s, headers: { ...corsHeaders, 'Content-Type': 'application/json' } });

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders });

  const url = Deno.env.get('SUPABASE_URL') ?? '';
  const anon = Deno.env.get('SUPABASE_ANON_KEY') ?? '';
  const svc = secretKey() ?? '';
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

  const { data: claimed, error: cErr } = await admin
    .from('orders')
    .update({ refund_status: 'processing' })
    .eq('id', orderId).eq('refund_status', 'failed')
    .select('id, user_id, refund_amount, refund_method, payment_method, payment_intent_id, stripe_account');
  if (cErr) return json({ error: 'claim_failed', details: cErr.message }, 500);
  if (!claimed || claimed.length === 0) return json({ ok: true, idempotent: true, message: 'nada_a_reprocessar' });

  const o = claimed[0];
  const refundCents = Math.round(Number(o.refund_amount ?? 0) * 100);
  const meioStripe = o.payment_method === 'card' || o.payment_method === 'mbway';
  const vaiStripe = o.refund_method !== 'wallet' && !!o.payment_intent_id && meioStripe;
  let outcome = '';
  let newStatus = 'failed';

  try {
    if (refundCents <= 0) {
      newStatus = 'refunded'; outcome = 'zero';
    } else if (!vaiStripe) {
      // saldo: escolha 'wallet' ou pedido sem Stripe. 100% saldo (wallet_split_free_pct = 1).
      const { data: cr } = await admin.from('cancellation_requests').select('cancel_stage').eq('order_id', orderId).maybeSingle();
      const rpcName = cr?.cancel_stage === 'grace' ? 'wallet_credit_refund_full' : 'wallet_credit_refund_split';
      const { error: wErr } = await admin.rpc(rpcName, { p_order_id: orderId, p_user_id: o.user_id, p_total_cents: refundCents, p_reason: 'reprocess_cancel_refund' });
      if (wErr) throw new Error('wallet: ' + wErr.message);
      newStatus = 'completed'; outcome = 'wallet';
    } else {
      // cartão OU MB Way: volta ao meio original, no máximo o que ainda se pode devolver na Stripe,
      // PELA CONTA ONDE O DINHEIRO ENTROU (v6).
      const { stripe, conta } = stripeDaLinha(o);
      const pi = await stripe.paymentIntents.retrieve(o.payment_intent_id, { expand: ['latest_charge'] });
      if (pi.status !== 'succeeded') throw new Error('pi_sem_cobranca:' + pi.status);
      // deno-lint-ignore no-explicit-any
      const charge: any = pi.latest_charge;
      const disponivel = Math.max(0, Number(pi.amount_received ?? 0) - Number(charge?.amount_refunded ?? 0));
      const valor = Math.min(refundCents, disponivel);
      if (valor <= 0) throw new Error('nada_por_devolver_na_stripe');
      const idem = `refund-${o.payment_intent_id}-${valor}`;
      const r = await stripe.refunds.create({ payment_intent: o.payment_intent_id, amount: valor }, { idempotencyKey: idem });
      newStatus = 'pending'; outcome = `stripe:${r.id}:${valor}:${conta}`;
    }
  } catch (e) {
    await admin.from('orders').update({ refund_status: 'failed' }).eq('id', orderId);
    try { await admin.from('admin_audit_log').insert({ admin_id: user.id, admin_email: user.email, action: 'reprocess_refund', entity_type: 'order', entity_id_text: orderId, details: { result: 'error', error: String(e), stripe_account: o.stripe_account ?? 'pessoal', admin_email: user.email } }); } catch (_) {}
    return json({ error: 'reprocess_failed', details: String(e) }, 502);
  }

  await admin.from('orders').update({ refund_status: newStatus }).eq('id', orderId);
  try { await admin.from('admin_audit_log').insert({ admin_id: user.id, admin_email: user.email, action: 'reprocess_refund', entity_type: 'order', entity_id_text: orderId, details: { old_status: 'failed', new_status: newStatus, result: outcome, stripe_account: o.stripe_account ?? 'pessoal', admin_email: user.email } }); } catch (_) {}
  return json({ ok: true, order_id: orderId, refund_status: newStatus, outcome, stripe_account: o.stripe_account ?? 'pessoal' });
});

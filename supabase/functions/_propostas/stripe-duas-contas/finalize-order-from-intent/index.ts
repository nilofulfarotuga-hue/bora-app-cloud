// PROPOSTA — supabase/functions/finalize-order-from-intent/index.ts — v17 (duas contas Stripe)
// Missão stripe-empresa-2026-11-01 (autorização do Danilo 01/11/2026 22:03). A tranca do repo
// não deixa esta sessão escrever em supabase/functions/finalize-order-from-intent/; este ficheiro
// é a versão completa pronta a copiar para lá e publicar (verify_jwt=true, como hoje).
// Base: v16 em produção (= repo).
//
// O que muda na v17 (e SÓ isto):
//   • O PaymentIntent lê-se na conta gravada no rascunho (payment_drafts.stripe_account), não na
//     chave "atual": um rascunho da empresa só existe na Stripe da empresa.
//   • Depois de create_order, grava orders.stripe_account = conta do rascunho (o pedido nasce a
//     saber onde o dinheiro entrou; é isso que os reembolsos usam).
// v15/v16 (autenticação pela regra da casa; registar_cobranca_stripe; dispatch) ficam intactos.

import Stripe from 'https://esm.sh/stripe@14.21.0?target=deno';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';
import { corsHeaders } from '../_shared/cors.ts';
import { chamadaDoServidor, chamadaDeAdmin } from '../_shared/chaves.ts';
import { secretKey } from '../_shared/keys.ts';
import { stripeDaLinha } from '../_shared/stripe_contas.ts';

const supabaseUrl = Deno.env.get('SUPABASE_URL') ?? '';
const serviceKey = secretKey() || (Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '');

// deno-lint-ignore no-explicit-any
const json = (body: any, status = 200) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  });

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders });

  const autorizado = (await chamadaDoServidor(req)) || (await chamadaDeAdmin(req));
  if (!autorizado) return json({ error: 'unauthorized: admin only' }, 401);

  // deno-lint-ignore no-explicit-any
  let body: any;
  try { body = await req.json(); } catch (_) { return json({ error: 'invalid_body' }, 400); }
  const payment_intent_id = typeof body?.payment_intent_id === 'string' ? body.payment_intent_id : null;
  if (!payment_intent_id) return json({ error: 'payment_intent_id required' }, 400);

  const admin = createClient(supabaseUrl, serviceKey);

  const { data: draft, error: draftErr } = await admin
    .from('payment_drafts')
    .select('id, user_id, payload, amount_cents, used_at, order_id, expires_at, stripe_account')
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

  // v17 — a Stripe da conta onde este rascunho foi pago.
  let stripe: Stripe;
  let conta: 'pessoal' | 'empresa';
  try {
    ({ stripe, conta } = stripeDaLinha(draft));
  } catch (e) {
    console.error('[finalize] sem chave Stripe da conta do rascunho:', draft.stripe_account, String(e));
    return json({ error: 'stripe_key_missing', conta: draft.stripe_account ?? 'pessoal' }, 500);
  }

  let pi: Stripe.PaymentIntent;
  try {
    pi = await stripe.paymentIntents.retrieve(payment_intent_id);
  } catch (e) {
    console.error('[finalize] PI retrieve failed:', e, 'conta=', conta);
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

  // v17 — o pedido fica a saber em que conta Stripe o dinheiro entrou. Falhar aqui NÃO desfaz o
  // pedido: o webhook da conta certa também grava ao marcar pago, e a conferência avisa.
  if (conta !== 'pessoal') {
    const { error: contaErr } = await admin.from('orders').update({ stripe_account: conta }).eq('id', orderId);
    if (contaErr) console.error('[finalize] orders.stripe_account não gravado:', contaErr.message, orderId, conta);
    else console.log('[finalize] orders.stripe_account =', conta, orderId);
  }

  // v14 (ronda 04/10 A.1) — grava o que a Stripe cobrou mesmo. Falhar aqui NÃO desfaz o pedido.
  {
    const { data: gravou, error: cobErr } = await admin.rpc('registar_cobranca_stripe', {
      p_order_id: orderId,
      p_payment_intent_id: payment_intent_id,
      p_cents: Number(pi.amount_received ?? 0),
    });
    if (cobErr) console.error('[finalize] registar_cobranca_stripe falhou:', cobErr.message, orderId);
    else console.log('[finalize] cobranca registada:', orderId, pi.amount_received, 'gravou:', gravou);
  }

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

  return json({ ok: true, order_id: orderId, idempotent: false, stripe_account: conta });
});

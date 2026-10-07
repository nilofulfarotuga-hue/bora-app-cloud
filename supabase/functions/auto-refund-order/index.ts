// auto-refund-order — devolve o dinheiro TODO ao meio de pagamento original (MB Way ou cartão)
// quando o SISTEMA cancela um pedido pago (ex.: nenhum estafeta aceitou). Regra do Danilo 07/10/2026:
// nunca para a carteira, sempre de volta ao MB Way/cartão, igual ao TVDE. Só aceita chamada com service_role.
// Chamada pelo gatilho fn_reembolso_cancelado_pelo_sistema (migração 20261007040000).
// Publicada por MCP a 07/10/2026 (v2), verify_jwt=true.
import Stripe from 'https://esm.sh/stripe@14.21.0?target=deno';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const stripe = new Stripe(Deno.env.get('STRIPE_SECRET_KEY') ?? '', {
  apiVersion: '2023-10-16',
  httpClient: Stripe.createFetchHttpClient(),
});
const json = (b: unknown, s = 200) => new Response(JSON.stringify(b), { status: s, headers: { 'Content-Type': 'application/json' } });

function roleFromJwt(token: string): string | null {
  try {
    const p = token.split('.')[1];
    const s = atob(p.replace(/-/g, '+').replace(/_/g, '/') + '='.repeat((4 - (p.length % 4)) % 4));
    return JSON.parse(s)?.role ?? null;
  } catch (_) { return null; }
}

Deno.serve(async (req: Request) => {
  const token = (req.headers.get('Authorization') ?? '').replace(/^Bearer\s+/i, '').trim();
  if (roleFromJwt(token) !== 'service_role') return json({ error: 'forbidden' }, 403);

  let orderId: string | undefined; let motivo = 'cancelado_pelo_sistema';
  try { const b = await req.json(); orderId = b?.order_id; motivo = b?.motivo ?? motivo; } catch (_) { return json({ error: 'invalid_body' }, 400); }
  if (!orderId) return json({ error: 'order_id required' }, 400);

  const admin = createClient(Deno.env.get('SUPABASE_URL') ?? '', Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '');
  const log = async (estado: string, detalhe: unknown) => {
    try { await admin.from('e2e_log').insert({ fluxo: 'auto_refund_order', passo: orderId, estado, detalhe: JSON.stringify(detalhe) }); } catch (_) {}
  };

  // Reserva o pedido (idempotente): só avança se ainda estiver por reembolsar.
  const { data: claimed, error: cErr } = await admin.from('orders')
    .update({ refund_status: 'processing' })
    .eq('id', orderId).in('refund_status', ['failed', 'pending_auto'])
    .select('id, user_id, payment_method, payment_intent_id, refund_amount');
  if (cErr) { await log('erro', cErr.message); return json({ error: 'claim_failed', details: cErr.message }, 500); }
  if (!claimed || claimed.length === 0) return json({ ok: true, idempotent: true });
  const o = claimed[0];

  try {
    if (!o.payment_intent_id) throw new Error('no_payment_intent');
    const pi = await stripe.paymentIntents.retrieve(o.payment_intent_id);
    let resultado = '';
    let refundId: string | null = null;
    let devolvidoCents = 0;
    if (pi.status === 'requires_capture') {
      await stripe.paymentIntents.cancel(pi.id);
      resultado = 'autorizacao_cancelada';
      devolvidoCents = pi.amount;
    } else if (pi.status === 'succeeded') {
      const r = await stripe.refunds.create({ payment_intent: pi.id, reason: 'requested_by_customer', metadata: { order_id: String(o.id), motivo } }, { idempotencyKey: `auto-refund-${pi.id}` });
      refundId = r.id; devolvidoCents = r.amount ?? (pi.amount_received ?? pi.amount); resultado = 'reembolso:' + r.status;
    } else if (pi.status === 'canceled') {
      resultado = 'ja_cancelado';
    } else {
      throw new Error('estado_pi_inesperado:' + pi.status);
    }
    const { error: uErr } = await admin.from('orders').update({
      refund_status: 'refunded', refund_id: refundId, refunded_at: new Date().toISOString(),
      refund_method: 'stripe',
      refund_amount: devolvidoCents > 0 ? devolvidoCents / 100 : o.refund_amount,
      payment_status: 'refunded',
    }).eq('id', o.id);
    await log('ok', { resultado, refund_id: refundId, cents: devolvidoCents, motivo, update_error: uErr?.message ?? null });
    return json({ ok: true, order_id: o.id, resultado, refund_id: refundId, cents: devolvidoCents, update_error: uErr?.message ?? null });
  } catch (e) {
    await admin.from('orders').update({ refund_status: 'failed' }).eq('id', o.id);
    await log('erro', String(e));
    try { await admin.rpc('notify_admin_event', { p_event_type: 'order_refund_failed', p_severity: 'critical', p_summary: `Reembolso automático falhou no pedido #${String(o.id).slice(0, 8)}: ${String(e)}`, p_entity_type: 'order', p_entity_id: String(o.id), p_payload: {}, p_deep_link: '/admin/cancellations' }); } catch (_) {}
    return json({ error: 'refund_failed', details: String(e) }, 502);
  }
});

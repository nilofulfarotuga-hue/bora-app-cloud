// auto-refund-order — devolve o dinheiro TODO ao meio de pagamento original (MB Way ou cartão)
// quando o SISTEMA cancela um pedido pago (ex.: nenhum estafeta aceitou). Regra do Danilo 07/10/2026:
// nunca para a carteira, sempre de volta ao MB Way/cartão, igual ao TVDE. Só aceita chamada com service_role.
// Chamada pelo gatilho fn_reembolso_cancelado_pelo_sistema (migração 20261007040000).
// Publicada por MCP a 07/10/2026 (v2), verify_jwt=true. No ar: v3 (igual a este ficheiro até 28/10).
// v4 (28/10/2026, regra do Danilo 28/10 18:24 — missao-geral-2026-10-28 bloco 2): cada parte volta
// pelo meio com que foi paga. A parte paga com SALDO (wallet_applied_cents) volta ao saldo (100%,
// wallet_split_free_pct = 1, chave = id do pedido → não duplica). Antes ficava perdida quando o
// sistema cancelava um pedido pago em parte com saldo. Os tokens voltam pelo gatilho do banco.
import Stripe from 'https://esm.sh/stripe@14.21.0?target=deno';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';
import { secretKey } from '../_shared/keys.ts';
import { chamadaDoServidor } from '../_shared/chaves.ts';

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
  // 16/10/2026 (chave nova): a chave secreta nova (sb_secret) não é JWT — ver _shared/chaves.ts
  if (roleFromJwt(token) !== 'service_role' && !(await chamadaDoServidor(req))) return json({ error: 'forbidden' }, 403);

  let orderId: string | undefined; let motivo = 'cancelado_pelo_sistema';
  try { const b = await req.json(); orderId = b?.order_id; motivo = b?.motivo ?? motivo; } catch (_) { return json({ error: 'invalid_body' }, 400); }
  if (!orderId) return json({ error: 'order_id required' }, 400);

  const admin = createClient(Deno.env.get('SUPABASE_URL') ?? '', secretKey() ?? '');
  const log = async (estado: string, detalhe: unknown) => {
    try { await admin.from('e2e_log').insert({ fluxo: 'auto_refund_order', passo: orderId, estado, detalhe: JSON.stringify(detalhe) }); } catch (_) {}
  };

  // Reserva o pedido (idempotente): só avança se ainda estiver por reembolsar.
  const { data: claimed, error: cErr } = await admin.from('orders')
    .update({ refund_status: 'processing' })
    .eq('id', orderId).in('refund_status', ['failed', 'pending_auto'])
    .select('id, user_id, payment_method, payment_intent_id, refund_amount, wallet_applied_cents');
  if (cErr) { await log('erro', cErr.message); return json({ error: 'claim_failed', details: cErr.message }, 500); }
  if (!claimed || claimed.length === 0) return json({ ok: true, idempotent: true });
  const o = claimed[0];
  const walletCents = Math.max(0, Number(o.wallet_applied_cents ?? 0)); // v4: parte paga com saldo

  try {
    let resultado = '';
    let refundId: string | null = null;
    let devolvidoCents = 0;
    if (o.payment_intent_id) {
      const pi = await stripe.paymentIntents.retrieve(o.payment_intent_id);
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
    } else if (walletCents <= 0) {
      throw new Error('no_payment_intent');
    } else {
      resultado = 'sem_stripe';
    }

    // v4 (regra 28/10): a parte paga com saldo volta ao saldo. Se a Stripe já devolveu e isto
    // falhar → 'needs_review' (o Reprocessar só pega em 'failed' e não repete a Stripe).
    let saldoCents = 0;
    let saldoErro: string | null = null;
    if (walletCents > 0 && o.user_id) {
      const { data: w, error: we } = await admin.rpc('wallet_credit_refund_split', {
        p_order_id: String(o.id), p_user_id: o.user_id, p_total_cents: walletCents,
        p_reason: `auto_refund_saldo: ${motivo}`, p_idempotency_key: String(o.id),
      });
      if (we) saldoErro = we.message;
      else if (!w?.already_applied) saldoCents = walletCents;
    }
    if (saldoErro) {
      await admin.from('orders').update({
        refund_status: 'needs_review', refund_id: refundId, refund_method: 'stripe',
      }).eq('id', o.id);
      await log('erro', { resultado, refund_id: refundId, cents: devolvidoCents, motivo, saldo_erro: saldoErro });
      try { await admin.rpc('notify_admin_event', { p_event_type: 'order_refund_failed', p_severity: 'critical', p_summary: `Reembolso automático do pedido #${String(o.id).slice(0, 8)}: a parte do saldo (${(walletCents / 100).toFixed(2)} €) não voltou: ${saldoErro}`, p_entity_type: 'order', p_entity_id: String(o.id), p_payload: {}, p_deep_link: '/admin/cancellations' }); } catch (_) {}
      return json({ error: 'wallet_refund_failed', details: saldoErro, refund_id: refundId }, 502);
    }

    const totalDevolvidoCents = devolvidoCents + saldoCents;
    const { error: uErr } = await admin.from('orders').update({
      refund_status: 'refunded', refund_id: refundId, refunded_at: new Date().toISOString(),
      refund_method: devolvidoCents > 0 || refundId ? 'stripe' : 'wallet',
      refund_amount: totalDevolvidoCents > 0 ? totalDevolvidoCents / 100 : o.refund_amount,
      payment_status: 'refunded',
    }).eq('id', o.id);
    await log('ok', { resultado, refund_id: refundId, cents: devolvidoCents, saldo_cents: saldoCents, motivo, update_error: uErr?.message ?? null });
    return json({ ok: true, order_id: o.id, resultado, refund_id: refundId, cents: devolvidoCents, saldo_cents: saldoCents, update_error: uErr?.message ?? null });
  } catch (e) {
    await admin.from('orders').update({ refund_status: 'failed' }).eq('id', o.id);
    await log('erro', String(e));
    try { await admin.rpc('notify_admin_event', { p_event_type: 'order_refund_failed', p_severity: 'critical', p_summary: `Reembolso automático falhou no pedido #${String(o.id).slice(0, 8)}: ${String(e)}`, p_entity_type: 'order', p_entity_id: String(o.id), p_payload: {}, p_deep_link: '/admin/cancellations' }); } catch (_) {}
    return json({ error: 'refund_failed', details: String(e) }, 502);
  }
});

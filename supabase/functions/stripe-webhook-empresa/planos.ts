// stripe-webhook-empresa/planos.ts — os eventos da Stripe dos PLANOS de limpeza.
// ⚠️ LISTA VERMELHA — PROPOSTA (missão limpeza-planos-fecho-2026-11-28, Bloco B).
//
// Só como rede, com o mesmo resultado e sem contar duas vezes (as funções do banco são
// idempotentes: um 'succeeded' nunca volta atrás, o mesmo cartão guardado duas vezes não muda nada):
//   payment_intent.succeeded            kind 'cleaning_plan'       → cobrança 'succeeded'
//   payment_intent.payment_failed/canceled  kind 'cleaning_plan'   → 'failed'
//   payment_intent.requires_action      kind 'cleaning_plan'       → 'requires_action'
//   setup_intent.succeeded              kind 'cleaning_plan_setup' → guarda o cartão no plano
//   charge.refunded                     → nada (a devolução já se grava quando se pede)
// Tudo o resto segue para o tratamento de sempre (_shared/stripe_webhook_core.ts), intocado.

// deno-lint-ignore no-explicit-any
type Cliente = any;
// deno-lint-ignore no-explicit-any
type Evento = { type: string; id?: string; data: { object: any } };

export type Decisao =
  | { tipo: 'pagamento'; chargeId: string; evento: 'succeeded' | 'failed' | 'requires_action'; piId: string; valor: number | null; erro: string | null }
  | { tipo: 'cartao'; planId: string; userId: string; setupIntentId: string; customerId: string | null; paymentMethodId: string | null }
  | { tipo: 'ignorar'; motivo: string }
  | null;   // null = não é dos planos: segue para o tratamento de sempre

export function decidirEventoPlano(ev: Evento): Decisao {
  const o = ev?.data?.object ?? {};
  const kind = o?.metadata?.kind;
  // a Charge herda a metadata do PaymentIntent (kind 'cleaning_plan')
  if (ev.type === 'charge.refunded' && (kind === 'cleaning_plan' || kind === 'cleaning_plan_refund')) {
    return { tipo: 'ignorar', motivo: 'devolucao_ja_gravada' };
  }
  if (ev.type.startsWith('payment_intent.') && kind === 'cleaning_plan') {
    const chargeId = String(o?.metadata?.charge_id ?? '');
    if (!chargeId) return { tipo: 'ignorar', motivo: 'sem_charge_id' };
    const mapa: Record<string, 'succeeded' | 'failed' | 'requires_action'> = {
      'payment_intent.succeeded': 'succeeded',
      'payment_intent.payment_failed': 'failed',
      'payment_intent.canceled': 'failed',
      'payment_intent.requires_action': 'requires_action',
    };
    const evento = mapa[ev.type];
    if (!evento) return { tipo: 'ignorar', motivo: ev.type };
    return {
      tipo: 'pagamento', chargeId, evento, piId: String(o.id ?? ''),
      valor: typeof o.amount_received === 'number' && o.amount_received > 0 ? o.amount_received : (typeof o.amount === 'number' ? o.amount : null),
      erro: o?.last_payment_error?.message ? String(o.last_payment_error.message).slice(0, 300) : null,
    };
  }
  if (ev.type.startsWith('setup_intent.') && kind === 'cleaning_plan_setup') {
    if (ev.type !== 'setup_intent.succeeded') return { tipo: 'ignorar', motivo: ev.type };
    const planId = String(o?.metadata?.plan_id ?? '');
    const userId = String(o?.metadata?.user_id ?? '');
    if (!planId || !userId) return { tipo: 'ignorar', motivo: 'sem_plano' };
    return {
      tipo: 'cartao', planId, userId, setupIntentId: String(o.id ?? ''),
      customerId: typeof o.customer === 'string' ? o.customer : o.customer?.id ?? null,
      paymentMethodId: typeof o.payment_method === 'string' ? o.payment_method : o.payment_method?.id ?? null,
    };
  }
  return null;
}

/** Aplica a decisão no banco. Lança em erro do banco (o receptor responde 500 e a Stripe repete). */
export async function aplicarDecisao(
  admin: Cliente,
  d: Exclude<Decisao, null>,
  lerCartao: (pmId: string) => Promise<{ brand: string | null; last4: string | null; exp_month: number | null; exp_year: number | null }>,
): Promise<unknown> {
  if (d.tipo === 'ignorar') return { ignorado: d.motivo };
  if (d.tipo === 'pagamento') {
    const { data, error } = await admin.rpc('cleaning_plan_webhook_payment', {
      p_charge_id: d.chargeId, p_event: d.evento, p_payment_intent_id: d.piId,
      p_amount_cents: d.valor, p_receipt_url: null, p_error: d.erro,
    });
    if (error) throw new Error(`cleaning_plan_webhook_payment: ${error.message}`);
    return data;
  }
  if (!d.paymentMethodId || !d.customerId) return { ignorado: 'sem_cartao' };
  const c = await lerCartao(d.paymentMethodId);
  const { data, error } = await admin.rpc('cleaning_plan_card_saved', {
    p_plan_id: d.planId, p_user_id: d.userId, p_customer_id: d.customerId, p_payment_method_id: d.paymentMethodId,
    p_brand: c.brand, p_last4: c.last4, p_exp_month: c.exp_month, p_exp_year: c.exp_year,
  });
  if (error) {
    // plano já fechado (cancelado entretanto): não há nada a guardar — não se pede à Stripe para repetir
    if (/plan_closed|plan_not_found/.test(error.message)) return { ignorado: 'plano_fechado' };
    throw new Error(`cleaning_plan_card_saved: ${error.message}`);
  }
  return data;
}

// supabase/functions/_shared/cobranca_stripe.ts — ronda 04/10 (05/10/2026), Bloco A.1/A.2
//
// O que o cliente pagou mesmo, por fonte: Stripe (cartão/MB Way), carteira e tokens.
// orders.stripe_charge_cents era sempre 0 (ninguém o gravava): aqui, se estiver a 0 e
// houver PaymentIntent, lê-se a Stripe e grava-se pela função public.registar_cobranca_stripe.
// O limite de reembolso do banco (_enforce_refund_cap) usa a soma destas três fontes.
//
// Revisão de contexto limpo (05/10): desconta-se o que a Stripe já devolveu; sem chave da
// Stripe com PI = erro (nunca "não pagou"); a gravação confirma-se lendo de volta.
//
// v2 (28/10/2026 — regra do Danilo 28/10 18:24, missao-geral-2026-10-28 bloco 2):
//   • Os TOKENS não são dinheiro: nunca entram no "pago" nem vão para a carteira como saldo.
//     Voltam como TOKENS, com a validade que tinham, pelo gatilho do banco
//     trg_orders_devolver_tokens → devolver_tokens_do_pedido (sabe QUAIS tokens o pedido gastou:
//     tabela pedido_tokens_gastos, escrita por consumir_tokens_do_pedido no create_order).
//   • Reembolso 100% ao meio escolhido: Stripe (cartão/MB Way) até ao que a Stripe ainda pode
//     devolver; o resto só até ao que se pagou com SALDO. Sem 80/20 (o banco tem
//     wallet_split_free_pct = 1 desde 28/10 18:27).
//   • Pago.tokensCents fica SEMPRE 0 (compatibilidade: o client-cancel-order v29 soma
//     stripe + wallet + tokens à mão). O valor e a contagem vêm em tokensValorCents/tokensCount,
//     só para informação e para o index.ts tirar o valor dos tokens da base do reembolso
//     quando eles voltam (tokensCount > 0).
//
// v3 (30/10/2026 — missão gorjetas-taxa-2026-10-30, autorização do Danilo 30/10 13:40):
//   • A gorjeta do carrinho pode ir no MESMO pagamento da compra (tips.cobrada_junto). Essa parte NÃO
//     é compra: stripeCents passa a ser só a compra (cobrado − gorjeta) e stripeDisponivelCents tira a
//     gorjeta que ainda está por devolver na Stripe. Assim nenhum reembolso da compra (cancelamento,
//     taxa, diferenças) mexe na gorjeta; a gorjeta volta à parte, inteira (_shared/gorjeta_devolver.ts).
//   • Gravar a cobrança (registar_cobranca_stripe) continua com o valor TOTAL que a Stripe cobrou.
//   • Se a coluna tips.cobrada_junto ainda não existir (migração por aplicar), conta como 0.

// deno-lint-ignore no-explicit-any
type Cliente = any;

export interface Pago {
  piId: string | null;
  /** o que a Stripe cobrou (amount_received) */
  stripeCents: number;
  /** o que ainda se pode devolver pela Stripe (cobrado − já devolvido) */
  stripeDisponivelCents: number;
  /** o que se pagou com saldo da carteira */
  walletCents: number;
  /** v2: SEMPRE 0 — os tokens não são dinheiro (voltam como tokens, pelo banco) */
  tokensCents: number;
  /** v2: valor dos tokens usados no pedido (tokens_applied_value_cents) — só informação */
  tokensValorCents: number;
  /** v2: quantos tokens o servidor gastou e registou (tokens_applied_count); 0 = pedido antigo */
  tokensCount: number;
  /** preço do pedido (customer_total) — nada se devolve acima disto */
  totalCents: number;
  /** estado do PI na Stripe (null se não há PI) */
  piStatus: string | null;
  /** v3: gorjeta do carrinho cobrada neste mesmo PI (fora de stripeCents; volta à parte, inteira) */
  gorjetaJuntoCents: number;
}

interface GorjetaJunto { amount_cents: number; status: string; stripe_payment_intent_id: string | null; devolvida_para: string | null }

/**
 * v3: quanto do PI do pedido é gorjeta do carrinho. `total` = toda a gorjeta cobrada junto (nunca é
 * compra); `porDevolverNaStripe` = a parte que ainda está na Stripe (não devolvida, ou devolvida ao
 * saldo Bora — aí o dinheiro ficou na Stripe e não pode ir para a compra).
 */
export function gorjetaNoPagamento(gorjetas: GorjetaJunto[], piId: string | null): { total: number; porDevolverNaStripe: number } {
  let total = 0;
  let porDevolverNaStripe = 0;
  for (const g of gorjetas) {
    const cents = Math.max(0, Number(g.amount_cents ?? 0));
    const paga = g.status === 'succeeded' || g.status === 'refunded';
    // por pagar só conta se já leva o PI deste pedido (o pagamento que entrou incluía-a)
    const vaiNestePi = (g.status === 'pending' || g.status === 'requires_action') &&
      !!g.stripe_payment_intent_id && g.stripe_payment_intent_id === piId;
    if (!paga && !vaiNestePi) continue;
    total += cents;
    if (g.status !== 'refunded' || g.devolvida_para === 'carteira') porDevolverNaStripe += cents;
  }
  return { total, porDevolverNaStripe };
}

/** soma do que foi pago em DINHEIRO (Stripe + saldo), nunca acima do preço do pedido */
export function totalPago(p: Pago): number {
  const soma = p.stripeCents + p.walletCents;
  return p.totalCents > 0 ? Math.min(soma, p.totalCents) : soma;
}

export async function lerPagoDoPedido(admin: Cliente, stripeKey: string, orderId: string): Promise<Pago> {
  const { data: o, error } = await admin.from('orders')
    .select('id, payment_intent_id, stripe_charge_cents, wallet_applied_cents, tokens_applied_count, tokens_applied_value_cents, customer_total, total')
    .eq('id', orderId).maybeSingle();
  if (error || !o) throw new Error(`pedido_nao_lido: ${error?.message ?? orderId}`);
  const pago: Pago = {
    piId: o.payment_intent_id ?? null,
    stripeCents: Math.max(0, Number(o.stripe_charge_cents ?? 0)),
    stripeDisponivelCents: 0,
    walletCents: Math.max(0, Number(o.wallet_applied_cents ?? 0)),
    tokensCents: 0,
    tokensValorCents: Math.max(0, Number(o.tokens_applied_value_cents ?? 0)),
    tokensCount: Math.max(0, Number(o.tokens_applied_count ?? 0)),
    totalCents: Math.max(0, Math.round(Number(o.customer_total ?? o.total ?? 0) * 100)),
    piStatus: null,
    gorjetaJuntoCents: 0,
  };
  if (!pago.piId) return pago;
  if (!stripeKey) throw new Error('stripe_key_em_falta');

  const res = await fetch(
    `https://api.stripe.com/v1/payment_intents/${encodeURIComponent(pago.piId)}?expand[]=latest_charge`,
    { headers: { Authorization: `Bearer ${stripeKey}` }, signal: AbortSignal.timeout(15000) },
  );
  if (!res.ok) throw new Error(`stripe_pi_${res.status}`);
  const pi = await res.json();
  pago.piStatus = String(pi.status ?? '');
  if (pi.status !== 'succeeded') {
    // a Stripe não cobrou: nada a devolver por ela
    pago.stripeCents = 0;
    return pago;
  }
  const recebido = Number(pi.amount_received ?? 0);
  const devolvido = Number(pi.latest_charge?.amount_refunded ?? 0);
  if (pago.stripeCents === 0 && recebido > 0) {
    const { data: gravou, error: e2 } = await admin.rpc('registar_cobranca_stripe', {
      p_order_id: orderId, p_payment_intent_id: pago.piId, p_cents: recebido,
    });
    if (e2 || gravou !== true) {
      // confirma lendo de volta (outro processo pode ter gravado primeiro)
      const { data: o2 } = await admin.from('orders').select('stripe_charge_cents').eq('id', orderId).maybeSingle();
      if (Number(o2?.stripe_charge_cents ?? 0) <= 0) {
        throw new Error(`cobranca_nao_gravada: ${e2?.message ?? 'nenhuma linha'}`);
      }
    }
  }
  // v3: a gorjeta do carrinho cobrada neste PI fica fora das contas da compra.
  let gorjeta = { total: 0, porDevolverNaStripe: 0 };
  const { data: gs, error: gErr } = await admin.from('tips')
    .select('amount_cents, status, stripe_payment_intent_id, devolvida_para')
    .eq('order_id', orderId).eq('cobrada_junto', true)
    .in('status', ['pending', 'requires_action', 'succeeded', 'refunded']);
  if (gErr) console.warn('[cobranca_stripe] gorjeta do pedido não lida (conta 0):', gErr.message, orderId);
  else gorjeta = gorjetaNoPagamento((gs ?? []) as GorjetaJunto[], pago.piId);
  pago.gorjetaJuntoCents = gorjeta.total;
  pago.stripeCents = Math.max(0, recebido - gorjeta.total);
  pago.stripeDisponivelCents = Math.max(0, recebido - devolvido - gorjeta.porDevolverNaStripe);
  return pago;
}

/**
 * Reparte um reembolso em DINHEIRO pelo meio com que foi pago: primeiro volta ao cartão/MB Way
 * (até ao que ainda se pode devolver na Stripe); o resto volta ao saldo, mas só até ao que se
 * pagou com saldo. Os tokens nunca entram aqui (voltam como tokens, pelo banco). Nunca devolve
 * mais do que se pagou em dinheiro nem acima do preço do pedido.
 */
export function repartirReembolso(refundCents: number, pago: Pago): { stripeCents: number; carteiraCents: number } {
  const pedido = Math.min(Math.max(0, Math.round(refundCents)), totalPago(pago));
  const stripeCents = Math.min(pedido, pago.stripeDisponivelCents);
  const carteiraCents = Math.min(pedido - stripeCents, pago.walletCents);
  return { stripeCents, carteiraCents };
}

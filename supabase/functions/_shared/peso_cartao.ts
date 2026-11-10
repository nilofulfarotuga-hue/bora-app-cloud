// _shared/peso_cartao.ts — PESO VARIÁVEL no cartão: a decisão e a cobrança da diferença.
// Missão fechar-tudo-2026-11-10, Bloco C (autorizações do Danilo 26/10 e 02/11 "Autorizo"; 10/11).
//
// É o MESMO código para os dois caminhos de cobrar-diferenca-peso:
//   • o pedido real (o talão manda { order_id, amount_cents } com a chave de servidor);
//   • o ensaio em modo de teste da Stripe da EMPRESA ({ ensaio:true, caso }, ver ensaio.ts).
// Não importa a Stripe nem o banco: recebe um cliente Stripe que cumpra StripePeso, por isso os
// testes (peso_cartao_test.ts) correm com uma Stripe falsa, sem rede.
//
// O que decide:
//   acertoDaDiferenca      — cópia fiel do ramo cartão/MB Way de finalizar_talao_nao_parceiro
//                            (lido em produção a 10/11/2026): a menos → carteira; a mais no cartão
//                            com weight_adjust_card_charge_enabled → cartao_pendente (chama esta Edge);
//                            a mais sem isso (ou MB Way) → bora_assume; zero → sem_diferenca.
//   cobrarDiferencaNoCartao — lê o cartão e o Customer do pagamento original e cobra off_session.
//                            Só devolve ok com a Stripe a dizer succeeded. Qualquer outra coisa
//                            (sem cartão, banco pede autenticação, recusado) → bora_assume, e o
//                            pedido segue (quem chama nunca mexe no estado do pedido).

/** Valor máximo que esta função cobra de uma vez (50 €), igual ao que a Edge sempre aceitou. */
export const MAX_CENTS_PESO = 5000;

/** O que a Stripe devolve de um PaymentIntent e que o peso usa. */
export interface PiLido {
  id: string;
  status: string;
  amount?: number;
  amount_received?: number;
  payment_method?: string | { id: string } | null;
  customer?: string | { id: string } | null;
}

/** A parte do cliente Stripe (stripe@14) que o peso usa. O real cabe aqui; o dos testes também. */
export interface StripePeso {
  paymentIntents: {
    retrieve(id: string): Promise<PiLido>;
    // deno-lint-ignore no-explicit-any
    create(params: any, opts?: { idempotencyKey?: string }): Promise<PiLido>;
  };
}

export type AcertoPeso = 'dinheiro' | 'carteira' | 'cartao_pendente' | 'bora_assume' | 'sem_diferenca';

/**
 * Como o talão acerta a diferença líquida (peso + produtos acrescentados), em cêntimos.
 * Cópia do ramo de finalizar_talao_nao_parceiro (produção, 10/11/2026):
 *   dinheiro → 'dinheiro' (paga-se à porta);
 *   < 0 → 'carteira' (wallet_transactions refund_credit_free, motivo storeshopping_v2_peso_variavel);
 *   > 0, cartão ('card'|'stripe') e interruptor ligado → 'cartao_pendente' (chama esta Edge);
 *   > 0 de outra forma (MB Way, ou interruptor desligado) → 'bora_assume';
 *   0 → 'sem_diferenca'.
 */
export function acertoDaDiferenca(
  netExtraCents: number,
  metodoPagamento: string | null | undefined,
  cobrarNoCartaoLigado: boolean,
): AcertoPeso {
  const metodo = String(metodoPagamento ?? '').toLowerCase();
  if (metodo === 'cash') return 'dinheiro';
  if (netExtraCents < 0) return 'carteira';
  if (netExtraCents > 0) {
    return (metodo === 'card' || metodo === 'stripe') && cobrarNoCartaoLigado ? 'cartao_pendente' : 'bora_assume';
  }
  return 'sem_diferenca';
}

function idDe(v: string | { id: string } | null | undefined): string | null {
  if (!v) return null;
  return typeof v === 'string' ? v : (v.id ?? null);
}

/** Cartão e Customer do pagamento original. null = não há (sem PI, PI ilegível, sem cartão guardado). */
export async function cartaoDoPagamentoOriginal(
  stripe: StripePeso,
  piOriginal: string | null | undefined,
): Promise<{ pmId: string; customerId: string } | null> {
  const pi = String(piOriginal ?? '');
  if (!pi.startsWith('pi_')) return null;
  try {
    const orig = await stripe.paymentIntents.retrieve(pi);
    const pmId = idDe(orig.payment_method);
    const customerId = idDe(orig.customer);
    return pmId && customerId ? { pmId, customerId } : null;
  } catch (_) {
    return null; // sem pagamento original legível
  }
}

export type ResultadoCobrancaPeso =
  | { ok: true; resultado: 'cartao_cobrado'; piId: string }
  | {
    ok: false;
    resultado: 'bora_assume';
    erro: 'sem_cartao_guardado' | 'nao_confirmado' | 'cobranca_falhou';
    motivo: string;
    status?: string;
    piId?: string;
    codigo?: string;
  };

/**
 * Cobra a diferença no cartão do pagamento original, off_session, com idempotência
 * (por defeito "peso_<order_id>"). Os motivos são os mesmos textos que a Edge sempre
 * mandou ao Danilo no aviso URGENTE.
 */
export async function cobrarDiferencaNoCartao(stripe: StripePeso, o: {
  piOriginal: string | null | undefined;
  amountCents: number;
  orderId: string;
  conta: string;
  idempotencyKey?: string;
  metadataExtra?: Record<string, string>;
}): Promise<ResultadoCobrancaPeso> {
  const cartao = await cartaoDoPagamentoOriginal(stripe, o.piOriginal);
  if (!cartao) {
    return { ok: false, resultado: 'bora_assume', erro: 'sem_cartao_guardado', motivo: 'sem cartão guardado do pagamento original' };
  }
  try {
    const pi = await stripe.paymentIntents.create({
      amount: o.amountCents,
      currency: 'eur',
      customer: cartao.customerId,
      payment_method: cartao.pmId,
      confirm: true,
      off_session: true,
      automatic_payment_methods: { enabled: true, allow_redirects: 'never' },
      description: `Bora — diferença de peso do pedido ${o.orderId.slice(0, 8)}`,
      metadata: { kind: 'peso_variavel', order_id: o.orderId, bora_conta: o.conta, ...(o.metadataExtra ?? {}) },
    }, { idempotencyKey: o.idempotencyKey ?? `peso_${o.orderId}` });
    if (pi.status !== 'succeeded') {
      return {
        ok: false, resultado: 'bora_assume', erro: 'nao_confirmado',
        motivo: `Stripe ficou em ${pi.status}`, status: pi.status, piId: pi.id,
      };
    }
    return { ok: true, resultado: 'cartao_cobrado', piId: pi.id };
  } catch (e) {
    const m = e instanceof Error ? e.message : String(e);
    // deno-lint-ignore no-explicit-any
    const x = e as any;
    const piFalhado = x?.raw?.payment_intent?.id ?? x?.payment_intent?.id;
    const codigo = x?.code ?? x?.raw?.code;
    return {
      ok: false, resultado: 'bora_assume', erro: 'cobranca_falhou',
      motivo: `cartão recusado ou pede autenticação: ${m.slice(0, 120)}`,
      ...(typeof piFalhado === 'string' ? { piId: piFalhado } : {}),
      ...(typeof codigo === 'string' ? { codigo } : {}),
    };
  }
}

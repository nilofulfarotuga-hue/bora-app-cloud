// DESTINO: supabase/functions/client-cancel-order/mbway_pendente.ts
// v33 (15/11/2026, missão manha-15-11 bloco C1, autorizo do Danilo 15/11 08:50).
// MB WAY que falhou ou expirou: antes de cancelar o pedido, cancela-se o pagamento
// pendente na Stripe, para o cliente não o poder aprovar depois na app do banco
// (pagar duas vezes). Proposta: docs/propostas/fechar-app-15-11/mbway-cancelar-pagamento.md
// Não mexe em valores, taxas nem reembolsos: só decide se o pedido pode ser cancelado.

export interface StripePiLike {
  paymentIntents: {
    retrieve(id: string): Promise<{ status: string }>;
    cancel(
      id: string,
      params: { cancellation_reason: 'abandoned' },
      opts: { idempotencyKey: string },
    ): Promise<{ status: string }>;
  };
}

// 'cancelado'  -> o PI foi cancelado agora (ou já estava): pode cancelar-se o pedido
// 'pago'       -> a Stripe já recebeu ou está a receber: NÃO cancelar o pedido
// 'falhou'     -> não se conseguiu falar com a Stripe: cancela-se o pedido como antes
//                 e o stripe-webhook continua a ser a rede de segurança
export type ResultadoMbway = 'cancelado' | 'pago' | 'falhou';

const CANCELAVEIS = new Set(['requires_action', 'requires_payment_method', 'requires_confirmation']);
const PAGOS = new Set(['succeeded', 'processing', 'requires_capture']);

export function aplicaCancelarMbway(
  reason: string | undefined,
  paymentMethod: string | null | undefined,
  piId: string | null | undefined,
): piId is string {
  return reason === 'payment_failed' && paymentMethod === 'mbway' &&
    typeof piId === 'string' && piId.startsWith('pi_');
}

export async function cancelarMbwayPendente(stripe: StripePiLike, piId: string): Promise<ResultadoMbway> {
  let status: string;
  try {
    status = (await stripe.paymentIntents.retrieve(piId)).status;
  } catch (e) {
    console.error('[client-cancel] mbway pi retrieve falhou:', e);
    return 'falhou';
  }
  if (PAGOS.has(status)) return 'pago';
  if (status === 'canceled') return 'cancelado';
  if (!CANCELAVEIS.has(status)) return 'falhou';
  try {
    const r = await stripe.paymentIntents.cancel(
      piId, { cancellation_reason: 'abandoned' }, { idempotencyKey: 'cancel-' + piId });
    return r.status === 'canceled' ? 'cancelado' : 'falhou';
  } catch (e) {
    // A Stripe recusa cancelar se o pagamento entrou entre o retrieve e o cancel.
    try {
      const s = (await stripe.paymentIntents.retrieve(piId)).status;
      if (PAGOS.has(s)) return 'pago';
      if (s === 'canceled') return 'cancelado';
    } catch (_) { /* fica 'falhou' */ }
    console.error('[client-cancel] mbway pi cancel falhou:', e);
    return 'falhou';
  }
}

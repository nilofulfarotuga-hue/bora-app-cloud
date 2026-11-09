// Regras puras do casa-checkout (m11, 09/11/2026) — sem rede, testadas em regras_test.ts.

/** Estados da Stripe em que o pagamento conta como feito (cartão e MB Way cobram na hora). */
export const estadosPagos: readonly string[] = ['succeeded', 'processing'];

/** Mínimo da Stripe em euros: 0,50 €. */
export const MINIMO_CENTS = 50;

/** Portão ANTES de criar qualquer pagamento na Stripe. null = pode cobrar; texto = porque não. */
export function decidirCriacao(o: {
  action: 'create' | 'create_mbway';
  interruptorLigado: boolean;
  estado: string;
  paymentStatus: string;
  paymentMethod: string;
  totalCents: number;
  jaTemPagamento: boolean;
}): string | null {
  if (!o.interruptorLigado) return 'pagamento_app_desligado';
  if (o.action === 'create' && o.paymentMethod !== 'card') return 'not_card_pedido';
  if (o.action === 'create_mbway' && o.paymentMethod !== 'mbway') return 'not_mbway_pedido';
  if (o.estado !== 'aguarda_pagamento') return 'pedido_nao_aguarda_pagamento';
  if (o.paymentStatus !== 'unpaid' || o.jaTemPagamento) return 'already_paid';
  if (!Number.isFinite(o.totalCents) || o.totalCents < MINIMO_CENTS) return 'amount_below_minimum';
  return null;
}

/** Conferência do pagamento lido na Stripe contra o pedido. null = confere. */
export function motivoRecusaMarcar(o: {
  metaKind: unknown; metaPedido: unknown; metaUser: unknown;
  pedidoId: string; userId: string; amount: number; totalCents: number;
}): string | null {
  if (o.metaKind !== 'casa' || o.metaPedido !== o.pedidoId) return 'payment_kind_mismatch';
  if (o.metaUser !== o.userId) return 'payment_owner_mismatch';
  if (o.amount !== o.totalCents) return 'payment_amount_mismatch';
  return null;
}

/** Quanto devolver num pedido cancelado/expirado: nunca mais do que se cobrou, nunca duas vezes. */
export function devolucaoCents(o: {
  totalCents: number; cobradoCents: number; taxaCents: number; jaDevolvidoCents: number;
}): { devolver: number; jaDevolvido: boolean } {
  if (o.jaDevolvidoCents > 0) return { devolver: 0, jaDevolvido: true };
  const base = Math.min(o.totalCents, o.cobradoCents);
  const taxa = Math.max(0, o.taxaCents || 0);
  return { devolver: Math.max(0, base - taxa), jaDevolvido: false };
}

/** Telemóvel para o MB Way em +351…; '' se não tiver 9 dígitos. */
export function telefoneE164(raw: string): string {
  const s = String(raw ?? '').trim();
  const digitos = s.replace(/\D/g, '');
  if (s.startsWith('+')) return digitos.length >= 9 ? '+' + digitos : '';
  if (digitos.startsWith('351') && digitos.length === 12) return '+' + digitos;
  return digitos.length === 9 ? '+351' + digitos : '';
}

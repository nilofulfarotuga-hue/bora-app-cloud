// deno test supabase/functions/casa-checkout/regras_test.ts
import { assertEquals } from 'https://deno.land/std@0.224.0/assert/mod.ts';
import { decidirCriacao, devolucaoCents, motivoRecusaMarcar, telefoneE164 } from './regras.ts';

const base = {
  action: 'create' as const, interruptorLigado: true, estado: 'aguarda_pagamento', paymentStatus: 'unpaid',
  paymentMethod: 'card', totalCents: 8000, jaTemPagamento: false,
};

Deno.test('cobra só com o interruptor ligado', () => {
  assertEquals(decidirCriacao(base), null);
  assertEquals(decidirCriacao({ ...base, interruptorLigado: false }), 'pagamento_app_desligado');
});

Deno.test('o método do pedido manda', () => {
  assertEquals(decidirCriacao({ ...base, paymentMethod: 'cash' }), 'not_card_pedido');
  assertEquals(decidirCriacao({ ...base, action: 'create_mbway' }), 'not_mbway_pedido');
  assertEquals(decidirCriacao({ ...base, action: 'create_mbway', paymentMethod: 'mbway' }), null);
});

Deno.test('só pedidos à espera de pagamento e ainda por pagar', () => {
  assertEquals(decidirCriacao({ ...base, estado: 'procura' }), 'pedido_nao_aguarda_pagamento');
  assertEquals(decidirCriacao({ ...base, estado: 'cancelado' }), 'pedido_nao_aguarda_pagamento');
  assertEquals(decidirCriacao({ ...base, paymentStatus: 'held' }), 'already_paid');
  assertEquals(decidirCriacao({ ...base, jaTemPagamento: true }), 'already_paid');
});

Deno.test('mínimo da Stripe 0,50 €', () => {
  assertEquals(decidirCriacao({ ...base, totalCents: 49 }), 'amount_below_minimum');
  assertEquals(decidirCriacao({ ...base, totalCents: 50 }), null);
  assertEquals(decidirCriacao({ ...base, totalCents: Number.NaN }), 'amount_below_minimum');
});

Deno.test('o pagamento lido na Stripe tem de bater com o pedido', () => {
  const ok = { metaKind: 'casa', metaPedido: 'p1', metaUser: 'u1', pedidoId: 'p1', userId: 'u1', amount: 8000, totalCents: 8000 };
  assertEquals(motivoRecusaMarcar(ok), null);
  assertEquals(motivoRecusaMarcar({ ...ok, metaKind: 'cleaning' }), 'payment_kind_mismatch');
  assertEquals(motivoRecusaMarcar({ ...ok, metaPedido: 'p2' }), 'payment_kind_mismatch');
  assertEquals(motivoRecusaMarcar({ ...ok, metaUser: 'u2' }), 'payment_owner_mismatch');
  assertEquals(motivoRecusaMarcar({ ...ok, amount: 7999 }), 'payment_amount_mismatch');
});

Deno.test('devolução: total menos a taxa, nunca mais do que se cobrou, nunca duas vezes', () => {
  assertEquals(devolucaoCents({ totalCents: 8000, cobradoCents: 8000, taxaCents: 0, jaDevolvidoCents: 0 }), { devolver: 8000, jaDevolvido: false });
  assertEquals(devolucaoCents({ totalCents: 8000, cobradoCents: 8000, taxaCents: 4000, jaDevolvidoCents: 0 }), { devolver: 4000, jaDevolvido: false });
  assertEquals(devolucaoCents({ totalCents: 8000, cobradoCents: 8000, taxaCents: 8000, jaDevolvidoCents: 0 }), { devolver: 0, jaDevolvido: false });
  assertEquals(devolucaoCents({ totalCents: 8000, cobradoCents: 6000, taxaCents: 0, jaDevolvidoCents: 0 }), { devolver: 6000, jaDevolvido: false });
  assertEquals(devolucaoCents({ totalCents: 8000, cobradoCents: 8000, taxaCents: 0, jaDevolvidoCents: 8000 }), { devolver: 0, jaDevolvido: true });
});

Deno.test('telemóvel MB Way', () => {
  assertEquals(telefoneE164('912 345 678'), '+351912345678');
  assertEquals(telefoneE164('351912345678'), '+351912345678');
  assertEquals(telefoneE164('+351 912 345 678'), '+351912345678');
  assertEquals(telefoneE164('12345'), '');
  assertEquals(telefoneE164(''), '');
});

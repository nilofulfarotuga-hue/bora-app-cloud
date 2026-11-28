// deno test supabase/functions/stripe-webhook-empresa/planos_test.ts
import { assertEquals } from 'https://deno.land/std@0.224.0/assert/mod.ts';
import { aplicarDecisao, decidirEventoPlano } from './planos.ts';

const pi = (type: string, extra: Record<string, unknown> = {}) => ({
  type, data: { object: { id: 'pi_1', amount: 3000, amount_received: type.endsWith('succeeded') ? 3000 : 0,
    metadata: { kind: 'cleaning_plan', charge_id: 'c-1', plan_id: 'p-1', user_id: 'u-1' }, ...extra } },
});

Deno.test('eventos de pagamento dos planos', () => {
  assertEquals(decidirEventoPlano(pi('payment_intent.succeeded')), { tipo: 'pagamento', chargeId: 'c-1', evento: 'succeeded', piId: 'pi_1', valor: 3000, erro: null });
  assertEquals((decidirEventoPlano(pi('payment_intent.payment_failed', { last_payment_error: { message: 'declined' } })) as { evento: string; erro: string }).evento, 'failed');
  assertEquals((decidirEventoPlano(pi('payment_intent.canceled')) as { evento: string }).evento, 'failed');
  assertEquals((decidirEventoPlano(pi('payment_intent.requires_action')) as { evento: string }).evento, 'requires_action');
  assertEquals(decidirEventoPlano(pi('payment_intent.processing')), { tipo: 'ignorar', motivo: 'payment_intent.processing' });
});

Deno.test('o resto segue para o tratamento de sempre', () => {
  assertEquals(decidirEventoPlano({ type: 'payment_intent.succeeded', data: { object: { metadata: { kind: 'cleaning', booking_id: 'b' } } } }), null);
  assertEquals(decidirEventoPlano({ type: 'payment_intent.succeeded', data: { object: { metadata: { draft_id: 'd' } } } }), null);
  assertEquals(decidirEventoPlano({ type: 'charge.refunded', data: { object: { metadata: { order_id: 'o' } } } }), null);
});

Deno.test('cartão guardado pelo SetupIntent; devolução não faz nada', () => {
  const d = decidirEventoPlano({ type: 'setup_intent.succeeded', data: { object: { id: 'seti_1', customer: 'cus_1', payment_method: 'pm_1',
    metadata: { kind: 'cleaning_plan_setup', plan_id: 'p-1', user_id: 'u-1' } } } });
  assertEquals(d, { tipo: 'cartao', planId: 'p-1', userId: 'u-1', setupIntentId: 'seti_1', customerId: 'cus_1', paymentMethodId: 'pm_1' });
  assertEquals(decidirEventoPlano({ type: 'charge.refunded', data: { object: { metadata: { kind: 'cleaning_plan' } } } }),
    { tipo: 'ignorar', motivo: 'devolucao_ja_gravada' });
});

Deno.test('aplicar: chama a função certa com os parâmetros certos; erro do banco faz a Stripe repetir', async () => {
  const chamadas: [string, Record<string, unknown>][] = [];
  const admin = { rpc: (fn: string, p: Record<string, unknown>) => { chamadas.push([fn, p]); return Promise.resolve({ data: { ok: true }, error: null }); } };
  await aplicarDecisao(admin, decidirEventoPlano(pi('payment_intent.succeeded'))!, () => Promise.reject(new Error('não usado')));
  assertEquals(chamadas[0][0], 'cleaning_plan_webhook_payment');
  assertEquals(chamadas[0][1].p_event, 'succeeded');
  assertEquals(chamadas[0][1].p_amount_cents, 3000);

  const cartao = decidirEventoPlano({ type: 'setup_intent.succeeded', data: { object: { id: 'seti_1', customer: 'cus_1', payment_method: 'pm_1',
    metadata: { kind: 'cleaning_plan_setup', plan_id: 'p-1', user_id: 'u-1' } } } })!;
  await aplicarDecisao(admin, cartao, () => Promise.resolve({ brand: 'visa', last4: '4242', exp_month: 1, exp_year: 2030 }));
  assertEquals(chamadas[1][0], 'cleaning_plan_card_saved');
  assertEquals(chamadas[1][1].p_last4, '4242');

  const falha = { rpc: () => Promise.resolve({ data: null, error: { message: 'deadlock' } }) };
  let lancou = false;
  try { await aplicarDecisao(falha, decidirEventoPlano(pi('payment_intent.succeeded'))!, () => Promise.reject(new Error('x'))); } catch { lancou = true; }
  assertEquals(lancou, true);
  const fechado = { rpc: () => Promise.resolve({ data: null, error: { message: 'plan_closed: cancelled' } }) };
  assertEquals(await aplicarDecisao(fechado, cartao, () => Promise.resolve({ brand: null, last4: null, exp_month: null, exp_year: null })),
    { ignorado: 'plano_fechado' });
});

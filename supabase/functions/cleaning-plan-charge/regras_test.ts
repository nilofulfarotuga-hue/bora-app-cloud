// deno test supabase/functions/cleaning-plan-charge/regras_test.ts
import { assertEquals } from 'https://deno.land/std@0.224.0/assert/mod.ts';
import { chaveValida, contar, descricao, emailTrocarCartao, resultadoDoErro, resultadoDoPi, resumoVazio } from './regras.ts';

Deno.test('estado do PaymentIntent → resultado', () => {
  assertEquals(resultadoDoPi('succeeded'), 'succeeded');
  assertEquals(resultadoDoPi('processing'), 'processing');
  assertEquals(resultadoDoPi('requires_action'), 'requires_action');
  assertEquals(resultadoDoPi('requires_payment_method'), 'card_error');
  assertEquals(resultadoDoPi(undefined), 'transient');
});

Deno.test('cartão recusado conta; autenticação pedida vira requires_action; rede não conta', () => {
  assertEquals(resultadoDoErro({ type: 'StripeCardError', code: 'card_declined', message: 'Your card was declined.' }).resultado, 'card_error');
  const auth = resultadoDoErro({ type: 'StripeCardError', code: 'authentication_required', raw: { payment_intent: { id: 'pi_1', status: 'requires_payment_method' } } });
  assertEquals(auth.resultado, 'requires_action');
  assertEquals(auth.piId, 'pi_1');
  assertEquals(resultadoDoErro({ type: 'StripeConnectionError', message: 'ECONNRESET' }).resultado, 'transient');
  assertEquals(resultadoDoErro({ type: 'StripeAPIError' }).resultado, 'transient');
  assertEquals(resultadoDoErro(new Error('fetch failed')).resultado, 'transient');
});

Deno.test('chave da Stripe por tentativa', () => {
  assertEquals(chaveValida('cleaning-plan-visit-6b1f0a8e-1c2d-4e5f-8a9b-0c1d2e3f4a5b-a1'), true);
  assertEquals(chaveValida('cleaning-plan-month-6b1f0a8e-1c2d-4e5f-8a9b-0c1d2e3f4a5b-2026-12-a3'), true);
  assertEquals(chaveValida('cleaning-plan-visit-x'), false);
  assertEquals(chaveValida(undefined), false);
});

Deno.test('descrição do recibo: casa e Bora Empresas com NIF', () => {
  assertEquals(descricao({ segment: 'casa', period_month: '12/2026' }), 'Bora · Limpeza plano · 12/2026');
  assertEquals(descricao({ segment: 'empresa', period_month: '12/2026', company_name: 'Ótica X', billing_nif: '123456789' }),
    'Bora · Bora Empresas · 12/2026 · Ótica X · NIF 123456789');
});

Deno.test('resumo conta cada resultado uma vez', () => {
  let r = resumoVazio();
  r = contar(r, 'succeeded'); r = contar(r, 'card_error'); r = contar(r, 'requires_action'); r = contar(r, 'transient'); r = contar(r, 'processing');
  assertEquals(r, { cobradas: 1, falhadas: 1, autenticacao: 1, presas: 2, devolvidas: 0, erros: 0 });
});

Deno.test('email "troca o cartão" escapa o texto e diz o caminho na app', () => {
  const e = emailTrocarCartao({ amountCents: 3000, final: false, quando: '03/12 às 10:00' });
  assertEquals(e.html.includes('30,00 €'), true);
  assertEquals(e.html.includes('Trocar cartão'), true);
  assertEquals(emailTrocarCartao({ amountCents: 100, final: true, quando: '<x>' }).html.includes('&lt;x&gt;'), true);
});

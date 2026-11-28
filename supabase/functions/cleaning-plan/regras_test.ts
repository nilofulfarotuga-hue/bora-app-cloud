// deno test supabase/functions/cleaning-plan/regras_test.ts
import { assertEquals } from 'https://deno.land/std@0.224.0/assert/mod.ts';
import { acaoValida, depoisDoBanco, erroParaApp, motivoRecusaConfirmar, motivoRecusaSetup, uuidValido } from './regras.ts';

const PLANO = '6b1f0a8e-1c2d-4e5f-8a9b-0c1d2e3f4a5b';
const CLIENTE = '0a1b2c3d-4e5f-4a6b-8c7d-9e0f1a2b3c4d';

Deno.test('só as quatro ações da app', () => {
  for (const a of ['setup', 'confirm_setup', 'action_secret', 'confirm_action']) assertEquals(acaoValida(a), true);
  assertEquals(acaoValida('charge'), false);
  assertEquals(acaoValida(undefined), false);
  assertEquals(uuidValido(PLANO), true);
  assertEquals(uuidValido('abc'), false);
});

Deno.test('guardar cartão só em plano do cliente ainda aberto', () => {
  assertEquals(motivoRecusaSetup({ planoDoCliente: true, status: 'pending_card' }), null);
  assertEquals(motivoRecusaSetup({ planoDoCliente: true, status: 'paused' }), null);
  assertEquals(motivoRecusaSetup({ planoDoCliente: true, status: 'cancelled' }), 'plan_closed');
  assertEquals(motivoRecusaSetup({ planoDoCliente: false, status: 'active' }), 'plan_not_found');
});

Deno.test('confirmar o cartão: SetupIntent deste plano, deste cliente, já succeeded', () => {
  const base = { status: 'succeeded', metaPlanId: PLANO, metaUserId: CLIENTE, metaKind: 'cleaning_plan_setup', planId: PLANO, userId: CLIENTE, temCartao: true };
  assertEquals(motivoRecusaConfirmar(base), null);
  assertEquals(motivoRecusaConfirmar({ ...base, status: 'requires_payment_method' }), 'setup_not_completed');
  assertEquals(motivoRecusaConfirmar({ ...base, metaUserId: 'outro' }), 'setup_not_completed');
  assertEquals(motivoRecusaConfirmar({ ...base, metaPlanId: 'outro' }), 'setup_not_completed');
  assertEquals(motivoRecusaConfirmar({ ...base, metaKind: 'cleaning' }), 'setup_not_completed');
  assertEquals(motivoRecusaConfirmar({ ...base, temCartao: false }), 'setup_not_completed');
});

Deno.test('depois do 3D Secure: a app só ouve succeeded/processing/failed', () => {
  assertEquals(depoisDoBanco('succeeded'), { app: 'succeeded', resultado: 'succeeded' });
  assertEquals(depoisDoBanco('processing'), { app: 'processing', resultado: 'processing' });
  assertEquals(depoisDoBanco('requires_action').resultado, null);
  assertEquals(depoisDoBanco('requires_payment_method'), { app: 'failed', resultado: 'card_error' });
});

Deno.test('erros genéricos para a app (nunca o texto cru)', () => {
  assertEquals(erroParaApp(new Error('plan_closed: cancelled')), 'plan_closed');
  assertEquals(erroParaApp(new Error('stripe_chave_em_falta:empresa')), 'erro');
  assertEquals(erroParaApp('qualquer coisa com sk_live_123'), 'erro');
});

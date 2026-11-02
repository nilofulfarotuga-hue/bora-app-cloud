// deno test --allow-env supabase/functions/_shared/stripe_contas_test.ts
// Testes das regras das duas contas Stripe (missão stripe-empresa-2026-11-01). Não falam com a
// Stripe nem com o banco: o "admin" é um duplo que responde o que o teste manda.
import { assertEquals } from 'https://deno.land/std@0.224.0/assert/mod.ts';
import {
  appSabeDuasContas,
  chavePublicavel,
  chaveSecreta,
  colunaClienteStripe,
  contaDoPaymentIntent,
  contaGravada,
  contaParaNovoPagamento,
  ehFluxoTvde,
  estadoChaves,
  lerInterruptor,
  respostaConta,
  segredoWebhook,
  temChaveSecreta,
} from './stripe_contas.ts';

function env(vars: Record<string, string>) {
  for (const k of ['STRIPE_SECRET_KEY', 'STRIPE_SECRET_KEY_EMPRESA', 'STRIPE_PUBLISHABLE_KEY', 'STRIPE_PUBLISHABLE_KEY_EMPRESA', 'STRIPE_WEBHOOK_SECRET', 'STRIPE_WEBHOOK_SECRET_EMPRESA']) {
    Deno.env.delete(k);
  }
  for (const [k, v] of Object.entries(vars)) Deno.env.set(k, v);
}

/** Duplo do cliente Supabase: devolve `valor` para platform_settings e `linhas` por tabela. */
function adminFalso(opts: { interruptor?: unknown; linhas?: Record<string, Record<string, unknown> | null>; alertas?: unknown[] }) {
  const alertas: unknown[] = opts.alertas ?? [];
  // deno-lint-ignore no-explicit-any
  const q = (tabela: string): any => ({
    select: () => q(tabela),
    eq: () => q(tabela),
    limit: () => q(tabela),
    insert: (x: unknown) => { alertas.push({ tabela, x }); return Promise.resolve({ error: null }); },
    maybeSingle: () => Promise.resolve(
      tabela === 'platform_settings'
        ? { data: opts.interruptor === undefined ? null : { value: opts.interruptor }, error: null }
        : { data: (opts.linhas ?? {})[tabela] ?? null, error: null },
    ),
  });
  return { from: q, rpc: (nome: string, args: unknown) => { alertas.push({ rpc: nome, args }); return Promise.resolve({ error: null }); }, alertas };
}

Deno.test('contaGravada: só empresa é empresa; nulo/lixo = pessoal', () => {
  assertEquals(contaGravada('empresa'), 'empresa');
  assertEquals(contaGravada('pessoal'), 'pessoal');
  assertEquals(contaGravada(null), 'pessoal');
  assertEquals(contaGravada('EMPRESA'), 'pessoal');
  assertEquals(contaGravada(42), 'pessoal');
});

Deno.test('ehFluxoTvde: kind tvde_*, target tvde ou corrida', () => {
  assertEquals(ehFluxoTvde({ kind: 'tvde_ride' }), true);
  assertEquals(ehFluxoTvde({ kind: 'tvde_plan' }), true);
  assertEquals(ehFluxoTvde({ target: 'tvde' }), true);
  assertEquals(ehFluxoTvde({ tvdeRideId: 'abc' }), true);
  assertEquals(ehFluxoTvde({ kind: 'tip', target: 'order' }), false);
  assertEquals(ehFluxoTvde({ kind: 'cleaning' }), false);
  assertEquals(ehFluxoTvde({}), false);
});

Deno.test('chaves por conta (modo live)', () => {
  env({ STRIPE_SECRET_KEY: 'sk_live_p', STRIPE_SECRET_KEY_EMPRESA: 'sk_live_e', STRIPE_PUBLISHABLE_KEY: 'pk_live_p', STRIPE_PUBLISHABLE_KEY_EMPRESA: 'pk_live_e', STRIPE_WEBHOOK_SECRET: 'whsec_p', STRIPE_WEBHOOK_SECRET_EMPRESA: 'whsec_e' });
  assertEquals(chaveSecreta('pessoal'), 'sk_live_p');
  assertEquals(chaveSecreta('empresa'), 'sk_live_e');
  assertEquals(chavePublicavel('empresa'), 'pk_live_e');
  assertEquals(segredoWebhook('pessoal'), 'whsec_p');
  assertEquals(segredoWebhook('empresa'), 'whsec_e');
  assertEquals(temChaveSecreta('empresa'), true);
  assertEquals(respostaConta('empresa'), { stripe_account: 'empresa', publishable_key: 'pk_live_e' });
  assertEquals(colunaClienteStripe('empresa'), 'stripe_customer_id_empresa');
  assertEquals(colunaClienteStripe('pessoal'), 'stripe_customer_id');
  const e = estadoChaves();
  assertEquals(e.empresa_secreta, true);
  assertEquals(e.pessoal_webhook, true);
  assertEquals(Object.values(e).some((v) => typeof v === 'string' && v.startsWith('sk_')), false, 'nunca expõe valores');
});

Deno.test('sem chave da empresa: temChaveSecreta false e publicável vazia', () => {
  env({ STRIPE_SECRET_KEY: 'sk_live_p' });
  assertEquals(temChaveSecreta('empresa'), false);
  assertEquals(chavePublicavel('empresa'), '');
});

Deno.test('appSabeDuasContas aceita true/"true"/1 e recusa o resto', () => {
  assertEquals(appSabeDuasContas({ stripe_contas_v2: true }), true);
  assertEquals(appSabeDuasContas({ stripe_contas_v2: 'true' }), true);
  assertEquals(appSabeDuasContas({ stripe_contas_v2: 1 }), true);
  assertEquals(appSabeDuasContas({ stripe_contas_v2: false }), false);
  assertEquals(appSabeDuasContas({}), false);
  assertEquals(appSabeDuasContas(null), false);
});

Deno.test('contaParaNovoPagamento: TVDE é sempre pessoal, mesmo com interruptor em empresa', async () => {
  env({ STRIPE_SECRET_KEY: 'sk_p', STRIPE_SECRET_KEY_EMPRESA: 'sk_e' });
  const admin = adminFalso({ interruptor: 'empresa' });
  const d = await contaParaNovoPagamento(admin, { kind: 'tvde_ride', body: { stripe_contas_v2: true }, origem: 't' });
  assertEquals(d, { conta: 'pessoal', motivo: 'tvde' });
});

Deno.test('contaParaNovoPagamento: app antiga fica na pessoal', async () => {
  env({ STRIPE_SECRET_KEY: 'sk_p', STRIPE_SECRET_KEY_EMPRESA: 'sk_e' });
  const admin = adminFalso({ interruptor: 'empresa' });
  const d = await contaParaNovoPagamento(admin, { kind: 'cleaning', body: {}, origem: 't' });
  assertEquals(d, { conta: 'pessoal', motivo: 'app_antiga' });
});

Deno.test('contaParaNovoPagamento: interruptor em pessoal → pessoal', async () => {
  env({ STRIPE_SECRET_KEY: 'sk_p', STRIPE_SECRET_KEY_EMPRESA: 'sk_e' });
  const admin = adminFalso({ interruptor: 'pessoal' });
  assertEquals(await lerInterruptor(admin, true), 'pessoal');
  const d = await contaParaNovoPagamento(admin, { kind: 'cleaning', body: { stripe_contas_v2: true }, origem: 't' });
  assertEquals(d, { conta: 'pessoal', motivo: 'interruptor_pessoal' });
});

Deno.test('contaParaNovoPagamento: interruptor em empresa + chave → empresa', async () => {
  env({ STRIPE_SECRET_KEY: 'sk_p', STRIPE_SECRET_KEY_EMPRESA: 'sk_e' });
  const admin = adminFalso({ interruptor: 'empresa' });
  await lerInterruptor(admin, true);
  const d = await contaParaNovoPagamento(admin, { kind: 'cleaning', body: { stripe_contas_v2: true }, origem: 't' });
  assertEquals(d, { conta: 'empresa', motivo: 'interruptor_empresa' });
});

Deno.test('contaParaNovoPagamento: interruptor em empresa SEM chave → pessoal e alerta', async () => {
  env({ STRIPE_SECRET_KEY: 'sk_p' });
  const admin = adminFalso({ interruptor: 'empresa' });
  await lerInterruptor(admin, true);
  const d = await contaParaNovoPagamento(admin, { kind: 'cleaning', body: { stripe_contas_v2: true }, origem: 't' });
  assertEquals(d, { conta: 'pessoal', motivo: 'empresa_sem_chave' });
  assertEquals(admin.alertas.length >= 1, true, 'regista e alerta');
});

Deno.test('interruptor ilegível ou em falta = pessoal', async () => {
  env({ STRIPE_SECRET_KEY: 'sk_p', STRIPE_SECRET_KEY_EMPRESA: 'sk_e' });
  const semLinha = adminFalso({});
  assertEquals(await lerInterruptor(semLinha, true), 'pessoal');
  const lixo = adminFalso({ interruptor: 'banco' });
  assertEquals(await lerInterruptor(lixo, true), 'pessoal');
  const jsonString = adminFalso({ interruptor: '"empresa"' });
  assertEquals(await lerInterruptor(jsonString, true), 'empresa');
});

Deno.test('contaDoPaymentIntent: encontra a conta na linha que tem o PI; não encontrado = pessoal', async () => {
  const admin = adminFalso({ linhas: { tips: { stripe_account: 'empresa' } } });
  assertEquals(await contaDoPaymentIntent(admin, 'pi_123'), 'empresa');
  const nada = adminFalso({ linhas: {} });
  assertEquals(await contaDoPaymentIntent(nada, 'pi_123'), 'pessoal');
  assertEquals(await contaDoPaymentIntent(nada, 'nao_e_pi'), 'pessoal');
  assertEquals(await contaDoPaymentIntent(nada, null), 'pessoal');
});

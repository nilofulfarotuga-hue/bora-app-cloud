// deno test --no-check --no-lock --cached-only supabase/functions/create-reservation-payment-intent/logica_test.ts
// Conserto P0 (15/11/2026): escritas pela chave do servidor e PI cancelado se não ficar gravado.
// Sem rede: Supabase e Stripe falsos.
import { assert, assertEquals } from 'https://deno.land/std@0.224.0/assert/mod.ts';
import { centsDoValor, type Dependencias, tokenBearer, tratar } from './logica.ts';

const UID = '11111111-1111-4111-8111-111111111111';
const RSV = '22222222-2222-4222-8222-222222222222';
const CORPO = { restaurant_id: 'r1', people: 2, reserved_for: '2026-11-20T20:00:00Z' };

function falsos(over: Partial<Dependencias> = {}, opts: { cancelaFalha?: boolean } = {}) {
  const reg = {
    inseridas: [] as Record<string, unknown>[],
    criados: [] as { params: Record<string, unknown>; chave: string }[],
    gravados: [] as [string, string][],
    cancelados: [] as string[],
    apagadas: [] as string[],
    avisos: [] as string[],
  };
  const deps: Dependencias = {
    utilizadorDoToken: (t) => Promise.resolve(t === 'tok-bom' ? { id: UID } : null),
    restauranteEmBreve: () => Promise.resolve(false),
    lerValorPrepagamento: () => Promise.resolve(300),
    prepararStripe: () =>
      Promise.resolve({
        conta: 'empresa',
        criarIntent: (params, chave) => {
          reg.criados.push({ params, chave });
          return Promise.resolve({ id: 'pi_1', client_secret: 'pi_1_secret', status: 'requires_payment_method' });
        },
        cancelarIntent: (id) => {
          if (opts.cancelaFalha) return Promise.reject(new Error('stripe em baixo'));
          reg.cancelados.push(id);
          return Promise.resolve();
        },
      }),
    inserirReserva: (linha) => {
      reg.inseridas.push(linha);
      return Promise.resolve({ id: RSV });
    },
    gravarPi: (r, pi) => {
      reg.gravados.push([r, pi]);
      return Promise.resolve(null);
    },
    apagarReserva: (id) => {
      reg.apagadas.push(id);
      return Promise.resolve();
    },
    respostaConta: (conta) => ({ stripe_account: conta, publishable_key: 'pk_x' }),
    avisarEquipa: (resumo) => {
      reg.avisos.push(resumo);
      return Promise.resolve();
    },
    ...over,
  };
  return { deps, reg };
}

Deno.test('tokenBearer e centsDoValor', () => {
  assertEquals(tokenBearer('Bearer abc'), 'abc');
  assertEquals(tokenBearer('bearer   abc '), 'abc');
  assertEquals(tokenBearer('abc'), '');
  assertEquals(tokenBearer(null), '');
  assertEquals(centsDoValor(null), 300);
  assertEquals(centsDoValor('450'), 450);
});

Deno.test('sem token ou token inválido = 401 e nada se escreve', async () => {
  for (const cab of [null, '', 'Bearer tok-mau']) {
    const { deps, reg } = falsos();
    const r = await tratar(cab, CORPO, deps);
    assertEquals(r.status, 401);
    assertEquals(reg.inseridas.length + reg.criados.length, 0);
  }
});

Deno.test('campos em falta = 400; "Em breve" = 409 sem Stripe; valor < 50 = 400', async () => {
  let f = falsos();
  assertEquals((await tratar('Bearer tok-bom', { restaurant_id: 'r1' }, f.deps)).status, 400);
  f = falsos({ restauranteEmBreve: () => Promise.resolve(true) });
  const r = await tratar('Bearer tok-bom', CORPO, f.deps);
  assertEquals(r.status, 409);
  assertEquals(r.corpo.code, 'STORE_COMING_SOON');
  assertEquals(f.reg.criados.length, 0);
  f = falsos({ lerValorPrepagamento: () => Promise.resolve(40) });
  assertEquals((await tratar('Bearer tok-bom', CORPO, f.deps)).status, 400);
  assertEquals(f.reg.inseridas.length, 0);
});

Deno.test('caminho feliz: reserva do dono do token, PI com metadata e PI gravado', async () => {
  const { deps, reg } = falsos();
  const r = await tratar('Bearer tok-bom', CORPO, deps);
  assertEquals(r.status, 200);
  assertEquals(reg.inseridas[0].client_user_id, UID);
  assertEquals(reg.inseridas[0].status, 'pending_payment');
  assertEquals(reg.inseridas[0].prepayment_cents, 300);
  assertEquals(reg.inseridas[0].stripe_account, 'empresa');
  assertEquals(reg.criados[0].chave, `rsv_${RSV}`);
  assertEquals((reg.criados[0].params.metadata as Record<string, unknown>).reservation_id, RSV);
  assertEquals((reg.criados[0].params.metadata as Record<string, unknown>).purpose, 'reservation_prepayment');
  assertEquals(reg.criados[0].params.amount, 300);
  assertEquals(reg.gravados, [[RSV, 'pi_1']]);
  assertEquals(r.corpo.clientSecret, 'pi_1_secret');
  assertEquals(r.corpo.reservation_id, RSV);
  assertEquals(r.corpo.stripe_account, 'empresa');
  assertEquals(reg.cancelados.length, 0);
});

Deno.test('falha a criar a reserva = 500 e a Stripe nem é chamada', async () => {
  const { deps, reg } = falsos({ inserirReserva: () => Promise.resolve({ erro: 'x' }) });
  const r = await tratar('Bearer tok-bom', CORPO, deps);
  assertEquals(r.status, 500);
  assertEquals(reg.criados.length, 0);
});

Deno.test('gravar o PI falha (erro, 0 linhas ou exceção): PI cancelado, reserva apagada, 500', async () => {
  const falhas: Dependencias['gravarPi'][] = [
    () => Promise.resolve('reserva_campo_protegido'),
    () => Promise.resolve('linhas gravadas: 0'),
    () => Promise.reject(new Error('rede')),
  ];
  for (const gravarPi of falhas) {
    const { deps, reg } = falsos({ gravarPi });
    const r = await tratar('Bearer tok-bom', CORPO, deps);
    assertEquals(r.status, 500);
    assertEquals(r.corpo.error, 'save_prepayment_pi_failed');
    assertEquals(r.corpo.payment_intent_cancelled, true);
    assert(!('clientSecret' in r.corpo));
    assertEquals(reg.cancelados, ['pi_1']);
    assertEquals(reg.apagadas, [RSV]);
    assertEquals(reg.avisos.length, 0);
  }
});

Deno.test('gravar falha e cancelar também: reserva fica, equipa avisada, 500', async () => {
  const { deps, reg } = falsos({ gravarPi: () => Promise.resolve('x') }, { cancelaFalha: true });
  const r = await tratar('Bearer tok-bom', CORPO, deps);
  assertEquals(r.status, 500);
  assertEquals(r.corpo.payment_intent_cancelled, false);
  assertEquals(reg.apagadas.length, 0);
  assertEquals(reg.avisos.length, 1);
  assert(!('clientSecret' in r.corpo));
});

// Revisão do Juiz da Claude.ai (15/11/2026 19:27): códigos genéricos, Stripe em try/catch,
// chave de idempotência sempre do servidor.
Deno.test('falha a criar a reserva: código genérico save_failed, sem o erro da base', async () => {
  const { deps } = falsos({ inserirReserva: () => Promise.resolve({ erro: 'duplicate key violates reservations_pkey' }) });
  const r = await tratar('Bearer tok-bom', CORPO, deps);
  assertEquals(r.status, 500);
  assertEquals(r.corpo, { error: 'save_failed' });
  assert(!JSON.stringify(r.corpo).includes('reservations_pkey'));
});

Deno.test('Stripe falha ao criar o PI: reserva apagada, 500 payment_intent_failed, sem detalhe', async () => {
  const { deps, reg } = falsos({
    prepararStripe: () =>
      Promise.resolve({
        conta: 'empresa',
        criarIntent: () => Promise.reject(new Error('No such customer: cus_SEGREDO; sk_live_x')),
        cancelarIntent: () => Promise.resolve(),
      }),
  });
  const r = await tratar('Bearer tok-bom', CORPO, deps);
  assertEquals(r.status, 500);
  assertEquals(r.corpo, { error: 'payment_intent_failed' });
  assert(!JSON.stringify(r.corpo).includes('cus_SEGREDO'));
  assertEquals(reg.apagadas, [RSV]);
  assertEquals(reg.gravados.length, 0);
});

Deno.test('Stripe falha e apagar a reserva também falha: continua 500 genérico, não lança', async () => {
  const { deps } = falsos({
    prepararStripe: () =>
      Promise.resolve({
        conta: 'empresa',
        criarIntent: () => Promise.reject(new Error('stripe')),
        cancelarIntent: () => Promise.resolve(),
      }),
    apagarReserva: () => Promise.reject(new Error('db em baixo')),
  });
  const r = await tratar('Bearer tok-bom', CORPO, deps);
  assertEquals(r.status, 500);
  assertEquals(r.corpo, { error: 'payment_intent_failed' });
});

Deno.test('idempotency_key do cliente é ignorada: a chave é sempre rsv_<id>', async () => {
  const { deps, reg } = falsos();
  const r = await tratar('Bearer tok-bom', { ...CORPO, idempotency_key: 'rsv_outra-reserva' }, deps);
  assertEquals(r.status, 200);
  assertEquals(reg.criados[0].chave, `rsv_${RSV}`);
});

// deno test --allow-read supabase/functions/cobrar-diferenca-peso/ensaio_test.ts
// MODO ENSAIO da diferença de peso no cartão (missão fechar-tudo-2026-11-10, Bloco C), com uma
// Stripe FALSA que imita os cartões de teste da Stripe (pm_card_visa passa; chargeCustomerFail
// guarda-se mas recusa; authenticationRequired pede sempre autenticação). Sem rede, sem chaves.
import { assert, assertEquals, assertStringIncludes } from 'https://deno.land/std@0.224.0/assert/mod.ts';
import {
  CASOS_ENSAIO,
  correrEnsaio,
  estadoChaveDeTeste,
  lerPedidoDeEnsaio,
  linhaDeErro,
  MENSAGEM_FALTA_CHAVE,
  NOME_CHAVE_TESTE,
  PLANO_ENSAIO,
  type StripeEnsaio,
} from './ensaio.ts';
import type { PiLido } from '../_shared/peso_cartao.ts';

type Chamada = { op: string; params?: Record<string, unknown>; opts?: { idempotencyKey?: string } };

function stripeDeTesteFalsa(o: { ignorarRecusas?: boolean; clienteFalha?: boolean } = {}) {
  const chamadas: Chamada[] = [];
  const pis = new Map<string, PiLido>();
  let n = 0;
  const erroStripe = (code: string, message: string, pi: string) => {
    const e = new Error(message) as Error & { code?: string; raw?: unknown };
    e.code = code;
    e.raw = { code, payment_intent: { id: pi } };
    return e;
  };
  const s: StripeEnsaio = {
    customers: {
      create(params) {
        chamadas.push({ op: 'customers.create', params });
        if (o.clienteFalha) return Promise.reject(new Error('Invalid API Key provided'));
        return Promise.resolve({ id: `cus_${++n}` });
      },
    },
    paymentMethods: {
      attach(id, params) {
        chamadas.push({ op: 'paymentMethods.attach', params: { id, ...params } });
        return Promise.resolve({ id: `pm_${id.replace('pm_card_', '')}_${++n}` });
      },
    },
    paymentIntents: {
      retrieve(id) {
        chamadas.push({ op: 'retrieve', params: { id } });
        const pi = pis.get(id);
        return pi ? Promise.resolve(pi) : Promise.reject(new Error('No such payment_intent'));
      },
      create(params: Record<string, unknown>, opts?: { idempotencyKey?: string }) {
        chamadas.push({ op: 'paymentIntents.create', params, opts });
        const id = `pi_${++n}`;
        const pm = String(params.payment_method ?? '');
        const pmGuardado = pm.startsWith('pm_card_') ? `pm_${pm.replace('pm_card_', '')}_${++n}` : pm;
        if (params.off_session === true && !o.ignorarRecusas) {
          if (pm.includes('chargeCustomerFail')) return Promise.reject(erroStripe('card_declined', 'Your card was declined.', id));
          if (pm.includes('authenticationRequired')) {
            return Promise.reject(erroStripe('authentication_required', 'This payment requires authentication.', id));
          }
        }
        const status = params.confirm === true ? 'succeeded' : 'requires_confirmation';
        const pi: PiLido = {
          id, status, amount: params.amount as number, amount_received: status === 'succeeded' ? params.amount as number : 0,
          payment_method: pmGuardado, customer: params.customer as string,
        };
        pis.set(id, pi);
        return Promise.resolve(pi);
      },
    },
  };
  return { s, chamadas };
}

Deno.test('lerPedidoDeEnsaio: só { ensaio: true } com um dos casos', () => {
  assertEquals(lerPedidoDeEnsaio(null), { ensaio: false });
  assertEquals(lerPedidoDeEnsaio({ order_id: 'x', amount_cents: 100 }), { ensaio: false });
  assertEquals(lerPedidoDeEnsaio({ ensaio: 'true', caso: 'a_mais' }), { ensaio: false });
  assertEquals(lerPedidoDeEnsaio({ ensaio: true, caso: 'a_mais' }), { ensaio: true, caso: 'a_mais', pedidoPor: null });
  assertEquals(lerPedidoDeEnsaio({ ensaio: true, caso: 'cobrar_tudo' }), { ensaio: true, caso: null, pedidoPor: null });
  const uid = '0b9a4c1e-1111-4222-8333-944455556666';
  assertEquals(lerPedidoDeEnsaio({ ensaio: true, caso: 'recusado', pedido_por: uid }), { ensaio: true, caso: 'recusado', pedidoPor: uid });
  assertEquals(lerPedidoDeEnsaio({ ensaio: true, caso: 'recusado', pedido_por: "1' or 1=1" }).ensaio, true);
});

Deno.test('chave de teste: falta → erro claro; chave real → recusada; só sk_test_/rk_test_', () => {
  assertEquals(estadoChaveDeTeste(undefined), 'falta');
  assertEquals(estadoChaveDeTeste('   '), 'falta');
  assertEquals(estadoChaveDeTeste('sk_live_abc'), 'nao_e_teste');
  assertEquals(estadoChaveDeTeste('rk_live_abc'), 'nao_e_teste');
  assertEquals(estadoChaveDeTeste('sk_test_abc'), 'ok');
  assertEquals(estadoChaveDeTeste('rk_test_abc'), 'ok');
  assertStringIncludes(MENSAGEM_FALTA_CHAVE, 'Falta a chave de teste');
  assertStringIncludes(MENSAGEM_FALTA_CHAVE, NOME_CHAVE_TESTE);
  const l = linhaDeErro('a_mais', 'falta_chave_teste', { mensagem: MENSAGEM_FALTA_CHAVE });
  assertEquals([l.estado, l.esperado, l.resultado, l.erro], ['erro', 'cartao_cobrado', null, 'falta_chave_teste']);
});

Deno.test('o ensaio só conhece a chave de TESTE da empresa (nunca a real)', async () => {
  assertEquals(NOME_CHAVE_TESTE, 'STRIPE_TEST_SECRET_KEY_EMPRESA');
  const ensaio = await Deno.readTextFile(new URL('./ensaio.ts', import.meta.url));
  for (const proibido of ['STRIPE_SECRET_KEY', 'stripePara', 'stripeDaLinha', "from('orders')", 'wallet_transactions']) {
    assert(!ensaio.includes(proibido), `ensaio.ts não pode usar ${proibido}`);
  }
  const index = await Deno.readTextFile(new URL('./index.ts', import.meta.url));
  const ramo = index.slice(index.indexOf('async function ensaio('), index.indexOf('Deno.serve('));
  assert(ramo.length > 100, 'ramo do ensaio encontrado no index.ts');
  for (const proibido of ['STRIPE_SECRET_KEY', 'stripePara', 'stripeDaLinha', "from('orders')", 'interruptorLigado']) {
    assert(!ramo.includes(proibido), `o ramo do ensaio no index.ts não pode usar ${proibido}`);
  }
  assertStringIncludes(ramo, 'estadoChaveDeTeste');
  // o ensaio corre ANTES do interruptor e da leitura do pedido
  assert(index.indexOf('lerPedidoDeEnsaio(body)') < index.indexOf('interruptorLigado(admin))'));
});

Deno.test('a_mais: pagamento original guardado para off_session, depois cobra 2,50 € no mesmo cartão', async () => {
  const { s, chamadas } = stripeDeTesteFalsa();
  const l = await correrEnsaio(s, 'a_mais', 'id1');
  assertEquals([l.estado, l.resultado, l.esperado], ['ok', 'cartao_cobrado', 'cartao_cobrado']);
  const creates = chamadas.filter((c) => c.op === 'paymentIntents.create');
  assertEquals(creates.length, 2);
  assertEquals(creates[0].params?.setup_future_usage, 'off_session');
  assertEquals(creates[0].params?.amount, 1000);
  assertEquals(creates[1].params?.off_session, true);
  assertEquals(creates[1].params?.amount, 250);
  assertEquals(creates[1].params?.customer, 'cus_1');
  assertEquals(creates[1].opts?.idempotencyKey, 'peso_ensaio_id1');
  assert(l.pi_original && l.pi_extra && l.pi_original !== l.pi_extra);
  assertEquals(l.conta, 'empresa');
});

Deno.test('a_menos: carteira, o cartão não é mexido (nenhuma cobrança nem devolução na Stripe)', async () => {
  const { s, chamadas } = stripeDeTesteFalsa();
  const l = await correrEnsaio(s, 'a_menos', 'id2');
  assertEquals([l.estado, l.resultado, l.diferenca_cents], ['ok', 'carteira', -180]);
  assertEquals(chamadas.filter((c) => c.op === 'paymentIntents.create').length, 1); // só o original
  assertEquals(l.pi_extra, null);
  assertEquals(l.detalhe.recebido_cents, 1000);
  assertStringIncludes(String(l.detalhe.o_pedido_real_faz), 'carteira');
});

Deno.test('recusado: cartão 0341 recusa → Bora assume (o pedido segue), com o motivo do aviso URGENTE', async () => {
  const { s, chamadas } = stripeDeTesteFalsa();
  const l = await correrEnsaio(s, 'recusado', 'id3');
  assertEquals([l.estado, l.resultado], ['ok', 'bora_assume']);
  assertEquals(l.detalhe.erro_codigo, 'card_declined');
  assertStringIncludes(String(l.detalhe.motivo), 'cartão recusado ou pede autenticação');
  assertStringIncludes(String(l.detalhe.o_pedido_real_faz), 'segue para entrega');
  assertEquals(l.erro, null);
  assert(chamadas.some((c) => c.op === 'paymentMethods.attach' && c.params?.id === 'pm_card_chargeCustomerFail'));
});

Deno.test('pede_autenticacao: cartão 3184 → Bora assume', async () => {
  const { s } = stripeDeTesteFalsa();
  const l = await correrEnsaio(s, 'pede_autenticacao', 'id4');
  assertEquals([l.estado, l.resultado, l.detalhe.erro_codigo], ['ok', 'bora_assume', 'authentication_required']);
});

Deno.test('DEFEITO PLANTADO: se o cartão que devia recusar for cobrado, o ensaio dá FALHOU', async () => {
  const { s } = stripeDeTesteFalsa({ ignorarRecusas: true });
  const l = await correrEnsaio(s, 'recusado', 'id5');
  assertEquals([l.estado, l.resultado], ['falhou', 'cartao_cobrado']);
  assertStringIncludes(String(l.erro), 'esperava bora_assume');
});

Deno.test('Stripe recusa a chave: estado erro com a etapa, nunca lança', async () => {
  const { s } = stripeDeTesteFalsa({ clienteFalha: true });
  const l = await correrEnsaio(s, 'a_mais', 'id6');
  assertEquals(l.estado, 'erro');
  assertStringIncludes(String(l.erro), 'cliente: Invalid API Key');
});

Deno.test('os 4 casos têm plano e o esperado certo', () => {
  assertEquals([...CASOS_ENSAIO], ['a_mais', 'a_menos', 'recusado', 'pede_autenticacao']);
  assertEquals(CASOS_ENSAIO.map((c) => PLANO_ENSAIO[c].esperado), ['cartao_cobrado', 'carteira', 'bora_assume', 'bora_assume']);
});

// deno test supabase/functions/_shared/peso_cartao_test.ts
// Peso variável no cartão (missão fechar-tudo-2026-11-10, Bloco C): a decisão do talão e a cobrança
// da diferença com uma Stripe FALSA (sem rede, sem chaves). O mesmo código serve o pedido real e o
// ensaio em modo de teste.
import { assertEquals, assertStringIncludes } from 'https://deno.land/std@0.224.0/assert/mod.ts';
import { acertoDaDiferenca, cobrarDiferencaNoCartao, type PiLido, type StripePeso } from './peso_cartao.ts';

type Chamada = { op: string; params?: Record<string, unknown>; opts?: { idempotencyKey?: string } };

/** Stripe falsa: guarda o que lhe pedem e responde como o modo de teste responderia. */
function stripeFalsa(o: {
  original?: PiLido | 'ilegivel';
  statusExtra?: string;
  recusa?: { code: string; message: string };
} = {}) {
  const chamadas: Chamada[] = [];
  const s: StripePeso = {
    paymentIntents: {
      retrieve(id: string) {
        chamadas.push({ op: 'retrieve', params: { id } });
        if (o.original === 'ilegivel' || !o.original) return Promise.reject(new Error('No such payment_intent'));
        return Promise.resolve(o.original);
      },
      create(params: Record<string, unknown>, opts?: { idempotencyKey?: string }) {
        chamadas.push({ op: 'create', params, opts });
        if (o.recusa) {
          const e = new Error(o.recusa.message) as Error & { code?: string; raw?: unknown };
          e.code = o.recusa.code;
          e.raw = { code: o.recusa.code, payment_intent: { id: 'pi_recusado' } };
          return Promise.reject(e);
        }
        return Promise.resolve({ id: 'pi_extra', status: o.statusExtra ?? 'succeeded' });
      },
    },
  };
  return { s, chamadas };
}

const ORIGINAL: PiLido = { id: 'pi_orig', status: 'succeeded', payment_method: 'pm_123', customer: { id: 'cus_9' } };

Deno.test('acertoDaDiferenca: a mesma decisão que o talão (finalizar_talao_nao_parceiro)', () => {
  assertEquals(acertoDaDiferenca(-180, 'card', true), 'carteira');
  assertEquals(acertoDaDiferenca(-180, 'card', false), 'carteira');
  assertEquals(acertoDaDiferenca(-180, 'mbway', false), 'carteira');
  assertEquals(acertoDaDiferenca(250, 'card', true), 'cartao_pendente');
  assertEquals(acertoDaDiferenca(250, 'stripe', true), 'cartao_pendente');
  assertEquals(acertoDaDiferenca(250, 'card', false), 'bora_assume'); // interruptor desligado
  assertEquals(acertoDaDiferenca(250, 'mbway', true), 'bora_assume'); // MB Way nunca se cobra outra vez
  assertEquals(acertoDaDiferenca(0, 'card', true), 'sem_diferenca');
  assertEquals(acertoDaDiferenca(250, 'cash', true), 'dinheiro');
  assertEquals(acertoDaDiferenca(-50, 'cash', true), 'dinheiro');
});

Deno.test('a mais: cobra off_session no cartão e no cliente do pagamento original', async () => {
  const { s, chamadas } = stripeFalsa({ original: ORIGINAL });
  const r = await cobrarDiferencaNoCartao(s, { piOriginal: 'pi_orig', amountCents: 250, orderId: 'abcdef123456', conta: 'empresa' });
  assertEquals(r, { ok: true, resultado: 'cartao_cobrado', piId: 'pi_extra' });
  const c = chamadas.find((x) => x.op === 'create')!;
  assertEquals(c.params?.amount, 250);
  assertEquals(c.params?.customer, 'cus_9');
  assertEquals(c.params?.payment_method, 'pm_123');
  assertEquals(c.params?.off_session, true);
  assertEquals(c.params?.confirm, true);
  assertEquals((c.params?.metadata as Record<string, string>).kind, 'peso_variavel');
  assertEquals(c.opts?.idempotencyKey, 'peso_abcdef123456');
});

Deno.test('sem pagamento original (MB Way, PI em falta ou ilegível): Bora assume, nada cobrado', async () => {
  for (const pi of [null, 'mbway_x', 'pi_nao_existe']) {
    const { s, chamadas } = stripeFalsa({ original: 'ilegivel' });
    const r = await cobrarDiferencaNoCartao(s, { piOriginal: pi, amountCents: 250, orderId: 'o1', conta: 'pessoal' });
    assertEquals(r.ok, false);
    if (!r.ok) {
      assertEquals(r.erro, 'sem_cartao_guardado');
      assertEquals(r.motivo, 'sem cartão guardado do pagamento original');
    }
    assertEquals(chamadas.filter((x) => x.op === 'create').length, 0);
  }
});

Deno.test('pagamento original sem cartão guardado: Bora assume', async () => {
  const { s } = stripeFalsa({ original: { id: 'pi_orig', status: 'succeeded', payment_method: null, customer: 'cus_9' } });
  const r = await cobrarDiferencaNoCartao(s, { piOriginal: 'pi_orig', amountCents: 250, orderId: 'o1', conta: 'empresa' });
  assertEquals(r.ok ? 'cobrado' : r.erro, 'sem_cartao_guardado');
});

Deno.test('o banco pede autenticação (requires_action): Bora assume, nunca marca como pago', async () => {
  const { s } = stripeFalsa({ original: ORIGINAL, statusExtra: 'requires_action' });
  const r = await cobrarDiferencaNoCartao(s, { piOriginal: 'pi_orig', amountCents: 250, orderId: 'o1', conta: 'empresa' });
  assertEquals(r.ok, false);
  if (!r.ok) {
    assertEquals(r.erro, 'nao_confirmado');
    assertEquals(r.status, 'requires_action');
    assertEquals(r.motivo, 'Stripe ficou em requires_action');
  }
});

Deno.test('cartão recusado: Bora assume, guarda o código e o PI falhado', async () => {
  const { s } = stripeFalsa({ original: ORIGINAL, recusa: { code: 'card_declined', message: 'Your card was declined.' } });
  const r = await cobrarDiferencaNoCartao(s, { piOriginal: 'pi_orig', amountCents: 250, orderId: 'o1', conta: 'empresa' });
  assertEquals(r.ok, false);
  if (!r.ok) {
    assertEquals(r.erro, 'cobranca_falhou');
    assertEquals(r.codigo, 'card_declined');
    assertEquals(r.piId, 'pi_recusado');
    assertStringIncludes(r.motivo, 'cartão recusado ou pede autenticação: Your card was declined.');
  }
});

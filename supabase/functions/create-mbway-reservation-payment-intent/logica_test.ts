// deno test --no-check --no-lock --cached-only supabase/functions/create-mbway-reservation-payment-intent/logica_test.ts
// Conserto P0 (15/11/2026): escritas pela chave do servidor e PI cancelado se não ficar gravado.
// Sem rede: Supabase e Stripe falsos.
import { assert, assertEquals } from 'https://deno.land/std@0.224.0/assert/mod.ts';
import { type Dependencias, telefoneE164, tratar } from './logica.ts';

const UID = '11111111-1111-4111-8111-111111111111';
const RSV = '22222222-2222-4222-8222-222222222222';
const CORPO = { restaurant_id: 'r1', people: 2, reserved_for: '2026-11-20T20:00:00Z', phone: '912345678' };

function falsos(over: Partial<Dependencias> = {}, opts: { cancelaFalha?: boolean; criarFalha?: boolean } = {}) {
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
    lerValorPrepagamento: () => Promise.resolve(null),
    prepararStripe: () =>
      Promise.resolve({
        conta: 'pessoal',
        modo: 'live',
        criarIntent: (params, chave) => {
          if (opts.criarFalha) return Promise.reject(new Error('card_declined'));
          reg.criados.push({ params, chave });
          return Promise.resolve({ id: 'pi_mb', status: 'requires_action' });
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
    avisarEquipa: (resumo) => {
      reg.avisos.push(resumo);
      return Promise.resolve();
    },
    ...over,
  };
  return { deps, reg };
}

Deno.test('telefone em E.164 como na v6', () => {
  assertEquals(telefoneE164('912345678'), '+351912345678');
  assertEquals(telefoneE164('0912345678'), '+351912345678');
  assertEquals(telefoneE164('+33612345678'), '+33612345678');
});

Deno.test('sem sessão = 401; sem telefone = 400; "Em breve" = 409 sem Stripe', async () => {
  let f = falsos();
  assertEquals((await tratar('Bearer tok-mau', CORPO, f.deps)).status, 401);
  assertEquals((await tratar(null, CORPO, f.deps)).status, 401);
  assertEquals((await tratar('Bearer tok-bom', { ...CORPO, phone: undefined }, f.deps)).status, 400);
  f = falsos({ restauranteEmBreve: () => Promise.resolve(true) });
  const r = await tratar('Bearer tok-bom', CORPO, f.deps);
  assertEquals(r.status, 409);
  assertEquals(r.corpo.code, 'STORE_COMING_SOON');
  assertEquals(f.reg.inseridas.length + f.reg.criados.length, 0);
});

Deno.test('caminho feliz: MB WAY confirmado no servidor e PI gravado', async () => {
  const { deps, reg } = falsos();
  const r = await tratar('Bearer tok-bom', CORPO, deps);
  assertEquals(r.status, 200);
  assertEquals(r.corpo.ok, true);
  assertEquals(r.corpo.paymentIntentId, 'pi_mb');
  assertEquals(r.corpo.amount_cents, 300);
  assertEquals(reg.inseridas[0].client_user_id, UID);
  assertEquals(reg.criados[0].chave, `mbway_rsv_${RSV}`);
  assertEquals(reg.criados[0].params.confirm, true);
  const pmd = reg.criados[0].params.payment_method_data as { billing_details: { phone: string } };
  assertEquals(pmd.billing_details.phone, '+351912345678');
  assertEquals(reg.gravados, [[RSV, 'pi_mb']]);
});

Deno.test('Stripe recusa ao criar: reserva apagada e 500 stripe_error (como na v6)', async () => {
  const { deps, reg } = falsos({}, { criarFalha: true });
  const r = await tratar('Bearer tok-bom', CORPO, deps);
  assertEquals(r.status, 500);
  assertEquals(r.corpo.error, 'stripe_error: card_declined');
  assertEquals(reg.apagadas, [RSV]);
});

Deno.test('gravar o PI falha: PI cancelado, reserva apagada, 500 (a v6 dizia ok:true)', async () => {
  for (const gravarPi of [() => Promise.resolve('reserva_campo_protegido'), () => Promise.reject(new Error('rede'))]) {
    const { deps, reg } = falsos({ gravarPi });
    const r = await tratar('Bearer tok-bom', CORPO, deps);
    assertEquals(r.status, 500);
    assertEquals(r.corpo.ok, false);
    assertEquals(r.corpo.error, 'save_prepayment_pi_failed');
    assertEquals(r.corpo.payment_intent_cancelled, true);
    assertEquals(reg.cancelados, ['pi_mb']);
    assertEquals(reg.apagadas, [RSV]);
  }
});

Deno.test('gravar falha e cancelar também: reserva fica e a equipa é avisada', async () => {
  const { deps, reg } = falsos({ gravarPi: () => Promise.resolve('x') }, { cancelaFalha: true });
  const r = await tratar('Bearer tok-bom', CORPO, deps);
  assertEquals(r.status, 500);
  assertEquals(r.corpo.payment_intent_cancelled, false);
  assertEquals(reg.apagadas.length, 0);
  assertEquals(reg.avisos.length, 1);
  assert(reg.avisos[0].includes('pi_mb'));
});

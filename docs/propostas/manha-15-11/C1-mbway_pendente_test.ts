// DESTINO: supabase/functions/client-cancel-order/mbway_pendente_test.ts (trocar o import para ./mbway_pendente.ts)
// deno test docs/propostas/manha-15-11/C1-mbway_pendente_test.ts
import { assertEquals } from 'https://deno.land/std@0.224.0/assert/mod.ts';
import { aplicaCancelarMbway, cancelarMbwayPendente, type StripePiLike } from './C1-mbway_pendente.ts';

function stripeFalsa(estados: string[], opts: { cancelFalha?: boolean; retrieveFalha?: boolean } = {}) {
  const chamadas: { cancel: Array<{ id: string; key: string }> } = { cancel: [] };
  let i = 0;
  const s: StripePiLike = {
    paymentIntents: {
      retrieve(_id) {
        if (opts.retrieveFalha) return Promise.reject(new Error('rede'));
        const st = estados[Math.min(i, estados.length - 1)]; i++;
        return Promise.resolve({ status: st });
      },
      cancel(id, _p, o) {
        chamadas.cancel.push({ id, key: o.idempotencyKey });
        if (opts.cancelFalha) return Promise.reject(new Error('payment_intent_unexpected_state'));
        return Promise.resolve({ status: 'canceled' });
      },
    },
  };
  return { s, chamadas };
}

Deno.test('so aplica a MB WAY que falhou e com PI', () => {
  assertEquals(aplicaCancelarMbway('payment_failed', 'mbway', 'pi_1'), true);
  assertEquals(aplicaCancelarMbway('payment_failed', 'card', 'pi_1'), false);
  assertEquals(aplicaCancelarMbway('mudei de ideias', 'mbway', 'pi_1'), false);
  assertEquals(aplicaCancelarMbway('payment_failed', 'mbway', null), false);
  assertEquals(aplicaCancelarMbway('payment_failed', 'mbway', 'mbway_local_x'), false);
});

Deno.test('PI a espera no banco -> cancela uma vez com chave de idempotencia', async () => {
  const { s, chamadas } = stripeFalsa(['requires_action']);
  assertEquals(await cancelarMbwayPendente(s, 'pi_A'), 'cancelado');
  assertEquals(chamadas.cancel, [{ id: 'pi_A', key: 'cancel-pi_A' }]);
});

Deno.test('PI ja pago -> nao cancela o PI nem o pedido', async () => {
  for (const st of ['succeeded', 'processing', 'requires_capture']) {
    const { s, chamadas } = stripeFalsa([st]);
    assertEquals(await cancelarMbwayPendente(s, 'pi_B'), 'pago');
    assertEquals(chamadas.cancel.length, 0);
  }
});

Deno.test('PI ja cancelado -> cancelado sem nova chamada', async () => {
  const { s, chamadas } = stripeFalsa(['canceled']);
  assertEquals(await cancelarMbwayPendente(s, 'pi_C'), 'cancelado');
  assertEquals(chamadas.cancel.length, 0);
});

Deno.test('Stripe em baixo -> falhou (o pedido cancela-se como antes)', async () => {
  const { s } = stripeFalsa([], { retrieveFalha: true });
  assertEquals(await cancelarMbwayPendente(s, 'pi_D'), 'falhou');
});

Deno.test('pagamento entra entre o retrieve e o cancel -> pago', async () => {
  const { s } = stripeFalsa(['requires_action', 'succeeded'], { cancelFalha: true });
  assertEquals(await cancelarMbwayPendente(s, 'pi_E'), 'pago');
});

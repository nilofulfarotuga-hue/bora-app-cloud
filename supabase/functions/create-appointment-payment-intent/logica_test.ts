// deno test --no-check --no-lock --cached-only supabase/functions/create-appointment-payment-intent/logica_test.ts
// Conserto P0 (15/11/2026): escrita pela chave do servidor, PI cancelado se não ficar gravado e
// nova tentativa sem receber de volta o PI cancelado. Sem rede: Supabase e Stripe falsos.
// A Stripe falsa guarda a resposta por chave de idempotência e devolve-a repetida (repetido=true).
import { assert, assertEquals } from 'https://deno.land/std@0.224.0/assert/mod.ts';
import { centsValidos, type Dependencias, type Marcacao, tratar } from './logica.ts';

const UID = '11111111-1111-4111-8111-111111111111';
const OUTRO = '99999999-9999-4999-8999-999999999999';
const APPT = '33333333-3333-4333-8333-333333333333';

function marcacao(over: Partial<Marcacao> = {}): Marcacao {
  return { id: APPT, client_user_id: UID, provider_id: 'p1', deposit_cents: 1500, status: 'pending_payment', deposit_pi: null, ...over };
}

function falsos(over: Partial<Dependencias> = {}, opts: { cancelaFalha?: boolean } = {}) {
  const guardadas = new Map<string, { id: string; client_secret: string }>();
  const estados = new Map<string, string>();
  // A marcação "na base": o deposit_pi muda quando o servidor o grava.
  const marc = { deposit_pi: null as string | null };
  let n = 0;
  const reg = {
    chaves: [] as string[],
    gravados: [] as [string, string, string, string][],
    cancelados: [] as string[],
    avisos: [] as string[],
  };
  const deps: Dependencias = {
    utilizadorDoToken: (t) => Promise.resolve(t === 'tok-bom' ? { id: UID } : null),
    lerMarcacao: () => Promise.resolve(marcacao({ deposit_pi: marc.deposit_pi })),
    parceiroEmBreve: () => Promise.resolve(false),
    prepararStripe: () =>
      Promise.resolve({
        conta: 'empresa',
        criarIntent: (_params, chave) => {
          reg.chaves.push(chave);
          const antes = guardadas.get(chave);
          if (antes) return Promise.resolve({ ...antes, status: estados.get(antes.id), repetido: true });
          const pi = { id: `pi_${++n}`, client_secret: `pi_${n}_secret` };
          guardadas.set(chave, pi);
          estados.set(pi.id, 'requires_payment_method');
          return Promise.resolve({ ...pi, status: 'requires_payment_method', repetido: false });
        },
        estadoIntent: (id) => Promise.resolve(estados.get(id) ?? 'unknown'),
        lerIntent: (id) => Promise.resolve({ id, client_secret: `${id}_secret`, status: estados.get(id) }),
        cancelarIntent: (id) => {
          if (opts.cancelaFalha) return Promise.reject(new Error('stripe em baixo'));
          reg.cancelados.push(id);
          estados.set(id, 'canceled');
          return Promise.resolve();
        },
      }),
    gravarPi: (a, c, pi, conta) => {
      reg.gravados.push([a, c, pi, conta]);
      marc.deposit_pi = pi;
      return Promise.resolve(null);
    },
    respostaConta: (conta) => ({ stripe_account: conta, publishable_key: 'pk_x' }),
    avisarEquipa: (resumo) => {
      reg.avisos.push(resumo);
      return Promise.resolve();
    },
    agora: () => 1700000000000,
    ...over,
  };
  return { deps, reg, estados };
}

const CORPO = { appointment_id: APPT };

Deno.test('centsValidos: nunca um valor por omissão', () => {
  assertEquals(centsValidos(1500), 1500);
  assertEquals(centsValidos('1500'), 1500);
  assertEquals(centsValidos(null), null);
  assertEquals(centsValidos(49), null);
  assertEquals(centsValidos(12.5), null);
});

Deno.test('portas: 401, 400, 404, 403, 409 estado, 409 "Em breve", 400 valor — sem Stripe', async () => {
  const casos: [string | null, Record<string, unknown>, Partial<Dependencias>, number][] = [
    [null, CORPO, {}, 401],
    ['Bearer tok-mau', CORPO, {}, 401],
    ['Bearer tok-bom', {}, {}, 400],
    ['Bearer tok-bom', CORPO, { lerMarcacao: () => Promise.resolve(null) }, 404],
    ['Bearer tok-bom', CORPO, { lerMarcacao: () => Promise.resolve(marcacao({ client_user_id: OUTRO })) }, 403],
    ['Bearer tok-bom', CORPO, { lerMarcacao: () => Promise.resolve(marcacao({ status: 'confirmed' })) }, 409],
    ['Bearer tok-bom', CORPO, { parceiroEmBreve: () => Promise.resolve(true) }, 409],
    ['Bearer tok-bom', CORPO, { lerMarcacao: () => Promise.resolve(marcacao({ deposit_cents: null })) }, 400],
  ];
  for (const [cab, corpo, over, esperado] of casos) {
    const { deps, reg } = falsos(over);
    const r = await tratar(cab, corpo, deps);
    assertEquals(r.status, esperado);
    assertEquals(reg.chaves.length, 0);
  }
});

Deno.test('caminho feliz: PI com kind=appointment e gravado pelo servidor para este cliente', async () => {
  const { deps, reg } = falsos();
  const r = await tratar('Bearer tok-bom', CORPO, deps);
  assertEquals(r.status, 200);
  assertEquals(r.corpo.paymentIntentId, 'pi_1');
  assertEquals(r.corpo.clientSecret, 'pi_1_secret');
  assertEquals(r.corpo.amount_cents, 1500);
  assertEquals(r.corpo.stripe_account, 'empresa');
  assertEquals(reg.chaves, [`appt_${APPT}`]);
  assertEquals(reg.gravados, [[APPT, UID, 'pi_1', 'empresa']]);
});

Deno.test('gravar falha: PI cancelado e 500 sem clientSecret', async () => {
  for (const gravarPi of [() => Promise.resolve('linhas gravadas: 0'), () => Promise.reject(new Error('rede'))]) {
    const { deps, reg } = falsos({ gravarPi });
    const r = await tratar('Bearer tok-bom', CORPO, deps);
    assertEquals(r.status, 500);
    assertEquals(r.corpo.error, 'save_deposit_pi_failed');
    assertEquals(r.corpo.payment_intent_cancelled, true);
    assert(!('clientSecret' in r.corpo));
    assertEquals(reg.cancelados, ['pi_1']);
    assertEquals(reg.avisos.length, 0);
  }
});

Deno.test('gravar falha e cancelar também: equipa avisada', async () => {
  const { deps, reg } = falsos({ gravarPi: () => Promise.resolve('x') }, { cancelaFalha: true });
  const r = await tratar('Bearer tok-bom', CORPO, deps);
  assertEquals(r.status, 500);
  assertEquals(r.corpo.payment_intent_cancelled, false);
  assertEquals(reg.avisos.length, 1);
});

Deno.test('nova tentativa depois de um PI cancelado recebe um PI NOVO (não o cancelado)', async () => {
  let falhar = true;
  const { deps, reg } = falsos({
    gravarPi: () => Promise.resolve(falhar ? 'erro' : null),
  });
  const r1 = await tratar('Bearer tok-bom', CORPO, deps);
  assertEquals(r1.status, 500);
  assertEquals(reg.cancelados, ['pi_1']);
  falhar = false;
  const r2 = await tratar('Bearer tok-bom', CORPO, deps);
  assertEquals(r2.status, 200);
  assertEquals(r2.corpo.paymentIntentId, 'pi_2');
  assertEquals(reg.chaves, [`appt_${APPT}`, `appt_${APPT}`, `appt_${APPT}_after_pi_1`]);
});

Deno.test('repetição com o PI gravado ainda vivo devolve o MESMO PI (e o client_secret dele) sem criar outro', async () => {
  for (const estado of ['requires_payment_method', 'requires_action', 'processing', 'succeeded']) {
    const { deps, reg, estados } = falsos();
    await tratar('Bearer tok-bom', CORPO, deps);
    estados.set('pi_1', estado);
    const r2 = await tratar('Bearer tok-bom', CORPO, deps);
    assertEquals(r2.status, 200);
    assertEquals(r2.corpo.paymentIntentId, 'pi_1');
    assertEquals(r2.corpo.clientSecret, 'pi_1_secret');
    assertEquals(r2.corpo.stripe_account, 'empresa');
    assertEquals(reg.chaves.length, 1);
  }
});

// Revisão do Juiz ao commit 6e4ed0ce: chave fixa em vez de `_r<agora>`.
Deno.test('JUIZ #3: PI gravado cancelado → PI novo com chave fixa _after_; toques seguintes devolvem esse, nunca um 3.º', async () => {
  const { deps, reg, estados } = falsos();
  await tratar('Bearer tok-bom', CORPO, deps); // PI1 gravado
  estados.set('pi_1', 'canceled');
  const r2 = await tratar('Bearer tok-bom', CORPO, deps);
  assertEquals(r2.corpo.paymentIntentId, 'pi_2');
  const r3 = await tratar('Bearer tok-bom', CORPO, deps);
  assertEquals(r3.corpo.paymentIntentId, 'pi_2');
  assertEquals(reg.chaves, [`appt_${APPT}`, `appt_${APPT}`, `appt_${APPT}_after_pi_1`]);
  estados.set('pi_2', 'canceled');
  const r4 = await tratar('Bearer tok-bom', CORPO, deps);
  assertEquals(r4.corpo.paymentIntentId, 'pi_3');
  assertEquals(reg.chaves.slice(3), [`appt_${APPT}`, `appt_${APPT}_after_pi_2`]);
});

Deno.test('JUIZ #3: dois toques que leem o mesmo estado (PI cancelado) recebem o MESMO PI novo', async () => {
  const { deps, reg, estados } = falsos();
  await tratar('Bearer tok-bom', CORPO, deps);
  estados.set('pi_1', 'canceled');
  deps.lerMarcacao = () => Promise.resolve(marcacao({ deposit_pi: 'pi_1' })); // leitura antiga nos dois
  const a = await tratar('Bearer tok-bom', CORPO, deps);
  const b = await tratar('Bearer tok-bom', CORPO, deps);
  assertEquals(a.corpo.paymentIntentId, 'pi_2');
  assertEquals(b.corpo.paymentIntentId, 'pi_2');
  assert(!reg.chaves.some((c) => c.includes('_r')));
});

Deno.test('cadeia fixa sem nada gravado: gravar falha duas vezes (PI cancelado) → _after_pi_1 → _after_pi_2 → PI3', async () => {
  let falhar = true;
  const { deps, reg } = falsos({ gravarPi: () => Promise.resolve(falhar ? 'erro' : null) });
  await tratar('Bearer tok-bom', CORPO, deps); // pi_1 cancelado
  await tratar('Bearer tok-bom', CORPO, deps); // pi_2 cancelado
  falhar = false;
  const r = await tratar('Bearer tok-bom', CORPO, deps);
  assertEquals(r.status, 200);
  assertEquals(r.corpo.paymentIntentId, 'pi_3');
  assertEquals(reg.cancelados, ['pi_1', 'pi_2']);
  const B = `appt_${APPT}`;
  assertEquals(reg.chaves, [B, B, `${B}_after_pi_1`, B, `${B}_after_pi_1`, `${B}_after_pi_2`]);
});

Deno.test('JUIZ #5: idempotency_key enviada pelo cliente é ignorada: a chave é sempre a do servidor', async () => {
  const { deps, reg } = falsos();
  const r = await tratar('Bearer tok-bom', { ...CORPO, idempotency_key: 'appt_de_outra_pessoa' }, deps);
  assertEquals(r.status, 200);
  assertEquals(reg.chaves, [`appt_${APPT}`]);
  assert(!reg.chaves.includes('appt_de_outra_pessoa'));
});

Deno.test('estado errado: 409 com o código fixo invalid_status (sem o estado em texto)', async () => {
  const { deps } = falsos({ lerMarcacao: () => Promise.resolve(marcacao({ status: 'confirmed' })) });
  const r = await tratar('Bearer tok-bom', CORPO, deps);
  assertEquals(r.status, 409);
  assertEquals(r.corpo, { error: 'invalid_status' });
});

// Revisão do Juiz da Claude.ai (15/11/2026 19:27): erro da Stripe ao criar → código genérico.
Deno.test('Stripe falha ao criar o PI: 500 payment_intent_failed, sem o texto da Stripe, nada gravado', async () => {
  let gravou = false;
  const { deps } = falsos({
    prepararStripe: () =>
      Promise.resolve({
        conta: 'empresa',
        criarIntent: () => Promise.reject(new Error('Invalid API Key provided: sk_live_SEGREDO')),
        estadoIntent: () => Promise.resolve('unknown'),
        lerIntent: () => Promise.reject(new Error('nao devia ser chamado')),
        cancelarIntent: () => Promise.resolve(),
      }),
    gravarPi: () => {
      gravou = true;
      return Promise.resolve(null);
    },
  });
  const r = await tratar('Bearer tok-bom', CORPO, deps);
  assertEquals(r.status, 500);
  assertEquals(r.corpo, { error: 'payment_intent_failed' });
  assert(!JSON.stringify(r.corpo).includes('sk_live'));
  assert(!gravou);
});

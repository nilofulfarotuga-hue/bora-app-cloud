// deno test --no-check --no-lock --cached-only supabase/functions/create-mbway-appointment-payment-intent/logica_test.ts
// Conserto P0 (15/11/2026): escrita pela chave do servidor, PI cancelado se não ficar gravado e
// nova tentativa sem receber de volta o PI cancelado. Sem rede: Supabase e Stripe falsos.
// A Stripe falsa guarda a resposta por chave de idempotência e devolve-a repetida (repetido=true).
import { assert, assertEquals } from 'https://deno.land/std@0.224.0/assert/mod.ts';
import { centsValidos, type Dependencias, type Marcacao, telefoneE164, tratar } from './logica.ts';

const UID = '11111111-1111-4111-8111-111111111111';
const OUTRO = '99999999-9999-4999-8999-999999999999';
const APPT = '33333333-3333-4333-8333-333333333333';

function marcacao(over: Partial<Marcacao> = {}): Marcacao {
  return { id: APPT, client_user_id: UID, provider_id: 'p1', deposit_cents: 1500, status: 'pending_payment', deposit_pi: null, ...over };
}

function falsos(over: Partial<Dependencias> = {}, opts: { cancelaFalha?: boolean; criarFalha?: boolean } = {}) {
  const guardadas = new Map<string, { id: string }>();
  const estados = new Map<string, string>();
  const telefones = new Map<string, string>();
  // A marcação "na base": o deposit_pi muda quando o servidor o grava.
  const marc = { deposit_pi: null as string | null };
  let n = 0;
  const reg = {
    chaves: [] as string[],
    params: [] as Record<string, unknown>[],
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
        modo: 'live',
        criarIntent: (params, chave) => {
          reg.chaves.push(chave);
          reg.params.push(params);
          if (opts.criarFalha) return Promise.reject(new Error('phone invalid'));
          const antes = guardadas.get(chave);
          if (antes) return Promise.resolve({ ...antes, status: estados.get(antes.id), repetido: true });
          const pi = { id: `pi_${++n}` };
          guardadas.set(chave, pi);
          estados.set(pi.id, 'requires_action');
          // deno-lint-ignore no-explicit-any
          telefones.set(pi.id, (params as any).payment_method_data.billing_details.phone);
          return Promise.resolve({ ...pi, status: 'requires_action', repetido: false });
        },
        estadoIntent: (id) => Promise.resolve(estados.get(id) ?? 'unknown'),
        lerIntent: (id) => Promise.resolve({ id, status: estados.get(id), telefone: telefones.get(id) ?? null }),
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
    avisarEquipa: (resumo) => {
      reg.avisos.push(resumo);
      return Promise.resolve();
    },
    agora: () => 1700000000000,
    ...over,
  };
  return { deps, reg, estados, marc };
}

const CORPO = { appointment_id: APPT, phone: '912345678' };
const CHAVE = `mbway_appt_${APPT}_351912345678`;

Deno.test('centsValidos e telefoneE164: iguais à v4', () => {
  assertEquals(centsValidos(1500), 1500);
  assertEquals(centsValidos('1500'), 1500);
  assertEquals(centsValidos(null), null);
  assertEquals(centsValidos(49), null);
  assertEquals(centsValidos(12.5), null);
  assertEquals(telefoneE164('912345678'), '+351912345678');
  assertEquals(telefoneE164('0912345678'), '+351912345678');
  assertEquals(telefoneE164('+34600000000'), '+34600000000');
});

Deno.test('portas: 401, 400, 404, 403, 409 estado, 409 "Em breve", 400 valor — sem Stripe', async () => {
  const casos: [string | null, Record<string, unknown>, Partial<Dependencias>, number][] = [
    [null, CORPO, {}, 401],
    ['Bearer tok-mau', CORPO, {}, 401],
    ['Bearer tok-bom', {}, {}, 400],
    ['Bearer tok-bom', { appointment_id: APPT }, {}, 400],
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

Deno.test('caminho feliz: MB WAY com kind=appointment e gravado pelo servidor para este cliente', async () => {
  const { deps, reg } = falsos();
  const r = await tratar('Bearer tok-bom', CORPO, deps);
  assertEquals(r.status, 200);
  assertEquals(r.corpo.ok, true);
  assertEquals(r.corpo.paymentIntentId, 'pi_1');
  assertEquals(r.corpo.status, 'requires_action');
  assertEquals(r.corpo.amount_cents, 1500);
  assertEquals(r.corpo.mode, 'live');
  assertEquals(r.corpo.stripe_account, 'empresa');
  assertEquals(reg.chaves, [CHAVE]);
  const p = reg.params[0] as Record<string, any>;
  assertEquals(p.payment_method_types, ['mb_way']);
  assertEquals(p.payment_method_data.billing_details.phone, '+351912345678');
  assertEquals(p.confirm, true);
  assertEquals(p.metadata.kind, 'appointment');
  assertEquals(reg.gravados, [[APPT, UID, 'pi_1', 'empresa']]);
});

Deno.test('erro da Stripe ao criar: 500 payment_intent_failed sem o texto da Stripe e nada gravado', async () => {
  const { deps, reg } = falsos({}, { criarFalha: true });
  const r = await tratar('Bearer tok-bom', CORPO, deps);
  assertEquals(r.status, 500);
  assertEquals(r.corpo, { error: 'payment_intent_failed' });
  assert(!JSON.stringify(r.corpo).includes('phone invalid'));
  assertEquals(reg.gravados.length, 0);
});

Deno.test('gravar falha: PI cancelado e 500', async () => {
  for (const gravarPi of [() => Promise.resolve('linhas gravadas: 0'), () => Promise.reject(new Error('rede'))]) {
    const { deps, reg } = falsos({ gravarPi });
    const r = await tratar('Bearer tok-bom', CORPO, deps);
    assertEquals(r.status, 500);
    assertEquals(r.corpo.error, 'save_deposit_pi_failed');
    assertEquals(r.corpo.payment_intent_cancelled, true);
    assert(!('paymentIntentId' in r.corpo));
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

Deno.test('nova tentativa depois de um PI cancelado recebe um PI NOVO com chave fixa _after_', async () => {
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
  assertEquals(reg.chaves, [CHAVE, CHAVE, `${CHAVE}_after_pi_1`]);
});

Deno.test('repetição com o PI gravado ainda vivo (resposta perdida) devolve o MESMO PI sem criar outro', async () => {
  const { deps, reg } = falsos();
  await tratar('Bearer tok-bom', CORPO, deps);
  const r2 = await tratar('Bearer tok-bom', CORPO, deps);
  assertEquals(r2.status, 200);
  assertEquals(r2.corpo.paymentIntentId, 'pi_1');
  assertEquals(r2.corpo.status, 'requires_action');
  assertEquals(reg.chaves.length, 1);
  assertEquals(reg.cancelados.length, 0);
});

// Revisão do Juiz da Claude.ai (15/11/2026 19:27).
Deno.test('PI gravado em requires_payment_method (MB WAY recusado/expirado) = tentativa nova com PI novo', async () => {
  const { deps, reg, estados } = falsos();
  const r1 = await tratar('Bearer tok-bom', CORPO, deps);
  assertEquals(r1.corpo.paymentIntentId, 'pi_1');
  estados.set('pi_1', 'requires_payment_method'); // o cliente recusou no telemóvel ou expirou
  const r2 = await tratar('Bearer tok-bom', CORPO, deps);
  assertEquals(r2.status, 200);
  assertEquals(r2.corpo.paymentIntentId, 'pi_2');
  assertEquals(reg.chaves, [CHAVE, CHAVE, `${CHAVE}_after_pi_1`]);
  assertEquals(reg.gravados.map((g) => g[2]), ['pi_1', 'pi_2']);
});

// Revisão do Juiz ao commit 6e4ed0ce: o caso de cobrar duas vezes.
Deno.test('JUIZ #1: PI1 recusado → PI2 enviado; outro toque devolve o PI2 e NUNCA cria um PI3', async () => {
  const { deps, reg, estados } = falsos();
  await tratar('Bearer tok-bom', CORPO, deps); // PI1
  estados.set('pi_1', 'requires_payment_method');
  const r2 = await tratar('Bearer tok-bom', CORPO, deps); // PI2 vai para o telemóvel
  assertEquals(r2.corpo.paymentIntentId, 'pi_2');
  const r3 = await tratar('Bearer tok-bom', CORPO, deps); // outro toque
  assertEquals(r3.status, 200);
  assertEquals(r3.corpo.paymentIntentId, 'pi_2');
  assertEquals(reg.chaves, [CHAVE, CHAVE, `${CHAVE}_after_pi_1`]);
  for (const estado of ['processing', 'succeeded']) {
    estados.set('pi_2', estado);
    const r = await tratar('Bearer tok-bom', CORPO, deps);
    assertEquals(r.status, 200);
    assertEquals(r.corpo.paymentIntentId, 'pi_2');
    assertEquals(r.corpo.status, estado);
  }
  assertEquals(reg.chaves.length, 3);
  assertEquals(reg.cancelados.length, 0);
});

Deno.test('JUIZ #1: dois toques que leem o mesmo estado usam a mesma chave fixa e recebem o MESMO PI', async () => {
  const { deps, reg, estados } = falsos();
  await tratar('Bearer tok-bom', CORPO, deps); // PI1 gravado
  estados.set('pi_1', 'requires_payment_method');
  // Leitura "antiga" nos dois pedidos: nenhum vê o PI que o outro gravou.
  deps.lerMarcacao = () => Promise.resolve(marcacao({ deposit_pi: 'pi_1' }));
  const a = await tratar('Bearer tok-bom', CORPO, deps);
  const b = await tratar('Bearer tok-bom', CORPO, deps);
  assertEquals(a.corpo.paymentIntentId, 'pi_2');
  assertEquals(b.corpo.paymentIntentId, 'pi_2');
  assertEquals(reg.chaves.filter((c) => c === `${CHAVE}_after_pi_1`).length, 2);
  assert(!reg.chaves.some((c) => c.includes('_r')));
});

Deno.test('cadeia fixa: PI2 também recusado → chave _after_pi_2 → PI3', async () => {
  const { deps, reg, estados } = falsos();
  await tratar('Bearer tok-bom', CORPO, deps);
  estados.set('pi_1', 'requires_payment_method');
  await tratar('Bearer tok-bom', CORPO, deps);
  estados.set('pi_2', 'requires_payment_method');
  const r = await tratar('Bearer tok-bom', CORPO, deps);
  assertEquals(r.corpo.paymentIntentId, 'pi_3');
  assertEquals(reg.chaves, [CHAVE, CHAVE, `${CHAVE}_after_pi_1`, CHAVE, `${CHAVE}_after_pi_2`]);
});

Deno.test('JUIZ #2: outro telefone com o anterior em requires_action → cancela o anterior e cria o novo', async () => {
  const { deps, reg, estados } = falsos();
  await tratar('Bearer tok-bom', CORPO, deps);
  const r2 = await tratar('Bearer tok-bom', { ...CORPO, phone: '+351 936 000 111' }, deps);
  assertEquals(r2.status, 200);
  assertEquals(r2.corpo.paymentIntentId, 'pi_2');
  assertEquals(reg.cancelados, ['pi_1']);
  assertEquals(estados.get('pi_1'), 'canceled');
  assertEquals(reg.chaves, [CHAVE, `mbway_appt_${APPT}_351936000111`]);
  const p = reg.params[1] as Record<string, any>;
  assertEquals(p.payment_method_data.billing_details.phone, '+351 936 000 111');
});

Deno.test('JUIZ #2: outro telefone e o cancelamento do anterior falha → 409 payment_in_progress, nada criado', async () => {
  const { deps, reg } = falsos({}, { cancelaFalha: true });
  await tratar('Bearer tok-bom', CORPO, deps);
  const r = await tratar('Bearer tok-bom', { ...CORPO, phone: '936000111' }, deps);
  assertEquals(r.status, 409);
  assertEquals(r.corpo.error, 'payment_in_progress');
  assertEquals(reg.chaves.length, 1);
  assertEquals(reg.gravados.length, 1);
});

Deno.test('JUIZ #2: outro telefone com o anterior processing ou succeeded → 409, sem cancelar nem criar', async () => {
  for (const estado of ['processing', 'succeeded']) {
    const { deps, reg, estados } = falsos();
    await tratar('Bearer tok-bom', CORPO, deps);
    estados.set('pi_1', estado);
    const r = await tratar('Bearer tok-bom', { ...CORPO, phone: '936000111' }, deps);
    assertEquals(r.status, 409);
    assertEquals(r.corpo.error, 'payment_in_progress');
    assertEquals(reg.cancelados.length, 0);
    assertEquals(reg.chaves.length, 1);
  }
});

Deno.test('ler o PI anterior falha na Stripe: 500 payment_intent_failed e nenhum PI novo', async () => {
  const { deps, reg } = falsos();
  await tratar('Bearer tok-bom', CORPO, deps);
  const base = deps.prepararStripe;
  deps.prepararStripe = async (b) => ({ ...(await base(b)), lerIntent: () => Promise.reject(new Error('rede')) });
  const r = await tratar('Bearer tok-bom', CORPO, deps);
  assertEquals(r.status, 500);
  assertEquals(r.corpo, { error: 'payment_intent_failed' });
  assertEquals(reg.chaves.length, 1);
});

Deno.test('estado errado: 409 com o código fixo invalid_status (sem o estado em texto)', async () => {
  const { deps } = falsos({ lerMarcacao: () => Promise.resolve(marcacao({ status: 'confirmed' })) });
  const r = await tratar('Bearer tok-bom', CORPO, deps);
  assertEquals(r.status, 409);
  assertEquals(r.corpo, { error: 'invalid_status' });
});

Deno.test('idempotency_key do cliente é ignorada: a chave é sempre a do servidor', async () => {
  const { deps, reg } = falsos();
  const r = await tratar('Bearer tok-bom', { ...CORPO, idempotency_key: 'mbway_appt_outra' }, deps);
  assertEquals(r.status, 200);
  assertEquals(reg.chaves, [CHAVE]);
});

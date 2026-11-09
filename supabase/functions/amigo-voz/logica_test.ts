// deno test --no-lock supabase/functions/amigo-voz/logica_test.ts
// A voz do servidor do Amigo sem rede: base, cache e Google falsas.
import { assert, assertEquals, assertRejects } from 'https://deno.land/std@0.224.0/assert/mod.ts';
import {
  caminhoCache,
  chamarGoogle,
  contarCaracteres,
  deBase64,
  definicoesDe,
  type Dependencias,
  GOOGLE_URL,
  MAX_CARACTERES,
  paraBase64,
  pedidoGoogle,
  type PedidoGoogle,
  tratar,
  velocidadeSegura,
  VOZ_PADRAO,
  vozSegura,
} from './logica.ts';

const MP3 = new Uint8Array([0x49, 0x44, 0x33, 3, 0, 0, 0, 0, 0, 9, 0xff, 0xfb, 0x90, 0x64]);

/** Uma base falsa com o mesmo teto da migração (teto do dia e limite por cliente). */
function mundo(op: {
  ativo?: boolean;
  voz?: string;
  chave?: string | null;
  teto?: number;
  tetoCliente?: number;
  googleFalha?: boolean;
  user?: string | null;
  baseFalha?: boolean;
} = {}) {
  const cache = new Map<string, Uint8Array>();
  const contagens: Array<[string, number, string]> = [];
  const pedidosGoogle: PedidoGoogle[] = [];
  const porCliente = new Map<string, number>();
  let gerados = 0;
  const d: Dependencias = {
    utilizador: async () => (op.user === undefined ? 'u-1' : op.user),
    definicoes: async () => {
      if (op.baseFalha) throw new Error('base em baixo');
      return { ativo: op.ativo ?? true, voz: op.voz ?? VOZ_PADRAO };
    },
    chaveGoogle: () => (op.chave === undefined ? 'chave-falsa' : op.chave),
    cacheLer: async (c) => cache.get(c) ?? null,
    cacheGravar: async (c, mp3) => {
      cache.set(c, mp3);
    },
    reservar: async (u, n) => {
      if (gerados + n > (op.teto ?? 20000)) return { ok: false, motivo: 'teto' };
      if ((porCliente.get(u) ?? 0) + n > (op.tetoCliente ?? 3000)) return { ok: false, motivo: 'limite_utilizador' };
      gerados += n;
      porCliente.set(u, (porCliente.get(u) ?? 0) + n);
      return { ok: true };
    },
    contar: async (u, n, tipo) => {
      contagens.push([u, n, tipo]);
      if (tipo === 'erro') {
        gerados -= n;
        porCliente.set(u, (porCliente.get(u) ?? 0) - n);
      }
    },
    google: async (p) => {
      pedidosGoogle.push(p);
      if (op.googleFalha) throw new Error('google 403: API desativada');
      return MP3;
    },
  };
  return { d, cache, contagens, pedidosGoogle, gerados: () => gerados };
}

Deno.test('com tudo ligado: gera na Google em pt-PT, devolve MP3 e guarda na cache', async () => {
  const m = mundo();
  const r = await tratar({ texto: '  Olá,   eu sou o Amigo! ', velocidade: 1 }, m.d);
  assertEquals(r.estado, 200);
  assertEquals(r.corpo.ok, true);
  assertEquals(r.corpo.origem, 'google');
  assertEquals(deBase64(r.corpo.audio_base64 as string), MP3);
  assertEquals(m.pedidosGoogle.length, 1);
  assertEquals(m.pedidosGoogle[0].voice, { languageCode: 'pt-PT', name: 'pt-PT-Standard-E' });
  assertEquals(m.pedidosGoogle[0].input.text, 'Olá, eu sou o Amigo!');
  assertEquals(m.pedidosGoogle[0].audioConfig.audioEncoding, 'MP3');
  assertEquals(m.cache.size, 1);
  assertEquals(m.gerados(), 20);
});

Deno.test('cache: a mesma frase outra vez não vai à Google nem gasta caracteres', async () => {
  const m = mundo();
  await tratar({ texto: 'Boa noite, Ana!' }, m.d);
  const r = await tratar({ texto: 'Boa noite,  Ana!' }, m.d);
  assertEquals(r.corpo.ok, true);
  assertEquals(r.corpo.origem, 'cache');
  assertEquals(m.pedidosGoogle.length, 1);
  assertEquals(m.gerados(), 15);
  assertEquals(m.contagens, [['u-1', 15, 'cache']]);
});

Deno.test('interruptor desligado: usa a voz do aparelho, nem cache nem Google', async () => {
  const m = mundo({ ativo: false });
  const r = await tratar({ texto: 'Olá' }, m.d);
  assertEquals(r.estado, 200);
  assertEquals(r.corpo, { ok: false, usar_aparelho: true, motivo: 'desligado' });
  assertEquals(m.pedidosGoogle.length, 0);
  assertEquals(m.contagens.length, 0);
});

Deno.test('sem chave da Google: usa o aparelho e conta como recusado', async () => {
  const m = mundo({ chave: null });
  const r = await tratar({ texto: 'Olá' }, m.d);
  assertEquals(r.corpo, { ok: false, usar_aparelho: true, motivo: 'sem_chave' });
  assertEquals(m.pedidosGoogle.length, 0);
  assertEquals(m.contagens, [['u-1', 3, 'sem_chave']]);
});

Deno.test('sem chave mas a frase já está na cache: sai da cache (não gasta nada)', async () => {
  const m = mundo();
  await tratar({ texto: 'Olá' }, m.d);
  const sem = mundo({ chave: null });
  for (const [k, v] of m.cache) sem.cache.set(k, v);
  const r = await tratar({ texto: 'Olá' }, sem.d);
  assertEquals(r.corpo.origem, 'cache');
});

Deno.test('teto do dia: passou, usa o aparelho e a Google não é chamada', async () => {
  const m = mundo({ teto: 30, tetoCliente: 1000 });
  const a = await tratar({ texto: 'Primeira frase com vinte' }, m.d); // 24
  assertEquals(a.corpo.ok, true);
  const b = await tratar({ texto: 'Outra frase nova' }, m.d); // 16 → 40 > 30
  assertEquals(b.corpo, { ok: false, usar_aparelho: true, motivo: 'teto' });
  assertEquals(m.pedidosGoogle.length, 1);
  // a cache continua a servir depois do teto
  const c = await tratar({ texto: 'Primeira frase com vinte' }, m.d);
  assertEquals(c.corpo.origem, 'cache');
});

Deno.test('limite por cliente', async () => {
  const m = mundo({ tetoCliente: 10 });
  const r = await tratar({ texto: 'Uma frase com mais de dez' }, m.d);
  assertEquals(r.corpo.motivo, 'limite_utilizador');
  assertEquals(m.pedidosGoogle.length, 0);
});

Deno.test('erro da Google: usa o aparelho e devolve os caracteres reservados', async () => {
  const m = mundo({ googleFalha: true });
  const r = await tratar({ texto: 'Olá' }, m.d);
  assertEquals(r.corpo, { ok: false, usar_aparelho: true, motivo: 'erro_google' });
  assertEquals(m.gerados(), 0);
  assertEquals(m.contagens, [['u-1', 3, 'erro']]);
  assertEquals(m.cache.size, 0);
});

Deno.test('sem sessão: 401 e nada mais', async () => {
  const m = mundo({ user: null });
  const r = await tratar({ texto: 'Olá' }, m.d);
  assertEquals(r.estado, 401);
  assertEquals(r.corpo.usar_aparelho, true);
  assertEquals(m.pedidosGoogle.length, 0);
});

Deno.test('base em baixo ou reserva a rebentar: nunca gasta na Google', async () => {
  const a = mundo({ baseFalha: true });
  assertEquals((await tratar({ texto: 'Olá' }, a.d)).corpo.motivo, 'erro_base');
  const b = mundo();
  b.d.reservar = () => Promise.reject(new Error('função amigo_voz_reservar não existe'));
  assertEquals((await tratar({ texto: 'Olá' }, b.d)).corpo.motivo, 'erro_base');
  assertEquals(b.pedidosGoogle.length, 0);
});

Deno.test('texto vazio ou comprido demais', async () => {
  const m = mundo();
  assertEquals((await tratar({ texto: '   ' }, m.d)).corpo.motivo, 'texto_invalido');
  assertEquals((await tratar({}, m.d)).corpo.motivo, 'texto_invalido');
  assertEquals((await tratar(null, m.d)).corpo.motivo, 'texto_invalido');
  assertEquals((await tratar({ texto: 'a'.repeat(MAX_CARACTERES + 1) }, m.d)).corpo.motivo, 'texto_invalido');
  assertEquals(m.pedidosGoogle.length, 0);
});

Deno.test('voz: nunca do Brasil, sempre pt-PT', async () => {
  assertEquals(vozSegura('pt-BR-Standard-A'), VOZ_PADRAO);
  assertEquals(vozSegura('en-US-Wavenet-A'), VOZ_PADRAO);
  assertEquals(vozSegura(null), VOZ_PADRAO);
  assertEquals(vozSegura('pt-PT-Wavenet-E'), 'pt-PT-Wavenet-E');
  const m = mundo({ voz: 'pt-BR-Neural2-A' });
  await tratar({ texto: 'Olá' }, m.d);
  assertEquals(m.pedidosGoogle[0].voice.name, VOZ_PADRAO);
  assertEquals(pedidoGoogle('x', 'pt-BR-X-A', 1).voice.languageCode, 'pt-PT');
});

Deno.test('definições lidas da base (true, "true", ausente)', () => {
  assertEquals(definicoesDe([{ key: 'amigo_voz_servidor_ativo', value: true }]).ativo, true);
  assertEquals(definicoesDe([{ key: 'amigo_voz_servidor_ativo', value: 'true' }]).ativo, true);
  assertEquals(definicoesDe([{ key: 'amigo_voz_servidor_ativo', value: false }]).ativo, false);
  assertEquals(definicoesDe([]).ativo, false);
  assertEquals(definicoesDe(null).voz, VOZ_PADRAO);
  assertEquals(definicoesDe([{ key: 'amigo_voz_nome', value: 'pt-PT-Wavenet-E' }]).voz, 'pt-PT-Wavenet-E');
});

Deno.test('velocidade, caracteres e caminho da cache', async () => {
  assertEquals(velocidadeSegura(1.03), 1.05);
  assertEquals(velocidadeSegura(9), 2);
  assertEquals(velocidadeSegura('x'), 1);
  assertEquals(contarCaracteres('ação'), 4);
  const a = await caminhoCache('Olá', VOZ_PADRAO, 1);
  assert(/^v1\/[0-9a-f]{2}\/[0-9a-f]{64}\.mp3$/.test(a), a);
  assertEquals(a, await caminhoCache('Olá', VOZ_PADRAO, 1.01));
  assert(a !== await caminhoCache('Olá', 'pt-PT-Wavenet-E', 1));
  assert(a !== await caminhoCache('Olá', VOZ_PADRAO, 1.5));
});

Deno.test('base64 de ida e volta (áudio grande)', () => {
  const grande = new Uint8Array(100_000).map((_, i) => i % 256);
  assertEquals(deBase64(paraBase64(grande)), grande);
});

Deno.test('chamarGoogle: chave no cabeçalho, pt-PT no corpo, MP3 de volta', async () => {
  let visto: { url: string; init: RequestInit } | null = null;
  const falso = (async (url: string, init: RequestInit) => {
    visto = { url, init };
    return new Response(JSON.stringify({ audioContent: paraBase64(MP3) }), { status: 200 });
  }) as unknown as typeof fetch;
  const mp3 = await chamarGoogle(pedidoGoogle('Olá', VOZ_PADRAO, 1), 'k-123', falso);
  assertEquals(mp3, MP3);
  assertEquals(visto!.url, GOOGLE_URL);
  assertEquals((visto!.init.headers as Record<string, string>)['X-Goog-Api-Key'], 'k-123');
  assert(!visto!.url.includes('k-123'), 'a chave não vai no endereço');
  assertEquals(JSON.parse(visto!.init.body as string).voice.languageCode, 'pt-PT');
});

Deno.test('chamarGoogle: 403 ou resposta sem áudio → erro (a Edge passa à voz do aparelho)', async () => {
  const f403 = (async () => new Response('{"error":{"code":403}}', { status: 403 })) as unknown as typeof fetch;
  await assertRejects(() => chamarGoogle(pedidoGoogle('Olá', VOZ_PADRAO, 1), 'k', f403), Error, 'google 403');
  const vazio = (async () => new Response('{}', { status: 200 })) as unknown as typeof fetch;
  await assertRejects(() => chamarGoogle(pedidoGoogle('Olá', VOZ_PADRAO, 1), 'k', vazio), Error, 'sem audioContent');
});

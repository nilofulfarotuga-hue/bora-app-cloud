// deno test --allow-env supabase/functions/_shared/ia_visao_test.ts
// Prova o caminho Claude → rotação grátis → erro claro SEM rede: o fetch é trocado por um falso que
// regista os pedidos. Valores de brincar construídos em tempo de execução (nada com cara de chave).
import { assert, assertEquals } from 'jsr:@std/assert@1';
import { anexosParaClaude, lerJson, mensagensOpenAI, pedirIa } from './ia_visao.ts';

const URL_BANCO = 'https://projeto-de-brincar.supabase.co';
const FALSO = (n: string) => ['valor', 'de', 'brincar', n].join('-');
const URL_CLAUDE = 'https://api.anthropic.com/v1/messages';
const URL_GROQ = 'https://api.groq.com/openai/v1/chat/completions';
const URL_GEMINI = 'https://generativelanguage.googleapis.com/v1beta/openai/chat/completions';
const URL_OPENROUTER = 'https://openrouter.ai/api/v1/chat/completions';
const URL_KILO = 'https://api.kilo.ai/api/gateway/chat/completions';

type Chamada = { url: string; corpo: Record<string, unknown> | null; headers: Headers };
type Resp = () => Response;

function preparar(env: { claude?: boolean; groq?: boolean; gemini?: boolean; openrouter?: boolean }) {
  Deno.env.set('SUPABASE_URL', URL_BANCO);
  Deno.env.set('SUPABASE_SERVICE_ROLE_KEY', FALSO('banco'));
  Deno.env.delete('SUPABASE_SECRET_KEYS');
  const por = (nome: string, ligado?: boolean) => (ligado ? Deno.env.set(nome, FALSO(nome.toLowerCase())) : Deno.env.delete(nome));
  por('ANTHROPIC_API_KEY', env.claude);
  por('GROQ_API_KEY', env.groq);
  por('GEMINI_API_KEY_FALLBACK', env.gemini);
  por('OPENROUTER_API_KEY', env.openrouter);
}

function fetchFalso(r: { claude?: Resp; groq?: Resp; gemini?: Resp; openrouter?: Resp; kilo?: Resp }) {
  const original = globalThis.fetch;
  const chamadas: Chamada[] = [];
  const livro: Record<string, unknown>[] = [];
  const responder = (url: string, corpo: Record<string, unknown> | null): Response => {
    if (url.endsWith('/rest/v1/rpc/ia_claude_pode')) return new Response(JSON.stringify({ code: 'PGRST202' }), { status: 404 });
    if (url.endsWith('/rest/v1/ia_gastos')) { if (corpo) livro.push(corpo); return new Response(null, { status: 201 }); }
    const mapa: Record<string, Resp | undefined> = {
      [URL_CLAUDE]: r.claude, [URL_GROQ]: r.groq, [URL_GEMINI]: r.gemini, [URL_OPENROUTER]: r.openrouter, [URL_KILO]: r.kilo,
    };
    if (url in mapa) return mapa[url] ? mapa[url]!() : new Response('{"error":"falso"}', { status: 500 });
    return new Response('nao esperado', { status: 599 });
  };
  globalThis.fetch = ((input: string | URL | Request, init?: RequestInit) => {
    const url = String(input instanceof Request ? input.url : input);
    const corpo = init?.body ? JSON.parse(String(init.body)) : null;
    chamadas.push({ url, corpo, headers: new Headers(init?.headers) });
    return Promise.resolve(responder(url, corpo));
  }) as typeof fetch;
  return { chamadas, livro, restaurar: () => { globalThis.fetch = original; } };
}

const claudeOk = (texto: string): Resp => () => new Response(JSON.stringify({
  content: [{ type: 'text', text: texto }], stop_reason: 'end_turn',
  usage: { input_tokens: 900, output_tokens: 40, cache_creation_input_tokens: 0, cache_read_input_tokens: 0 },
}), { status: 200 });
const claudeHttp = (status: number, texto = '{"type":"error"}'): Resp => () => new Response(texto, { status });
const openaiOk = (texto: string): Resp => () => new Response(JSON.stringify({
  choices: [{ message: { role: 'assistant', content: texto } }], usage: { prompt_tokens: 700, completion_tokens: 30 },
}), { status: 200 });
const http = (status: number, texto = '{"error":"falso"}'): Resp => () => new Response(texto, { status });

// PNG de 1x1 (base64 curto e verdadeiro)
const PNG = 'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==';
const so = (cs: Chamada[], url: string) => cs.filter((c) => c.url === url);

Deno.test('Claude responde: usa o Claude com a imagem e não toca na reserva', async () => {
  preparar({ claude: true, gemini: true });
  const f = fetchFalso({ claude: claudeOk('{"severity":"verde","finding":"ok"}') });
  try {
    const r = await pedirIa({
      robo: 'edge-teste', sistema: 'sistema', texto: 'olha', anexos: [{ mime: 'image/png', base64: PNG }], json: true, privado: false,
    });
    assert(r.ok);
    assertEquals(r.motor, 'claude');
    assertEquals((r.json as Record<string, string>).severity, 'verde');
    const [pedido] = so(f.chamadas, URL_CLAUDE);
    const ultima = (pedido.corpo!.messages as Array<{ content: Array<Record<string, unknown>> }>).at(-1)!;
    assertEquals(ultima.content[0].type, 'image');
    assertEquals((ultima.content[0].source as Record<string, string>).media_type, 'image/png');
    assertEquals(ultima.content[1], { type: 'text', text: 'olha' });
    assertEquals(so(f.chamadas, URL_GEMINI).length, 0);
  } finally { f.restaurar(); }
});

for (const status of [402, 429, 500]) {
  Deno.test(`Claude falha com ${status}: cai na reserva grátis (imagem → Gemini grátis) e regista custo 0`, async () => {
    preparar({ claude: true, gemini: true });
    const f = fetchFalso({ claude: claudeHttp(status), gemini: openaiOk('{"severity":"amarelo","finding":"x"}') });
    try {
      const r = await pedirIa({
        robo: 'edge-teste', sistema: 's', texto: 'olha', anexos: [{ mime: 'image/png', base64: PNG }], json: true, privado: false,
      });
      assert(r.ok, JSON.stringify(r));
      assertEquals(r.motor, 'gemini-gratis');
      assertEquals(r.custoUsd, 0);
      assertEquals(r.tentativas[0].motor, 'claude');
      assertEquals(r.tentativas[0].http, status);
      const [g] = so(f.chamadas, URL_GEMINI);
      const msgs = g.corpo!.messages as Array<{ role: string; content: unknown }>;
      assertEquals(msgs[0], { role: 'system', content: 's' });
      const partes = msgs.at(-1)!.content as Array<Record<string, unknown>>;
      assertEquals((partes[1].image_url as Record<string, string>).url.startsWith('data:image/png;base64,'), true);
      assert(g.headers.get('authorization')?.startsWith('Bearer '));
      const linha = f.livro.find((l) => String(l.modelo).startsWith('gemini-gratis:'))!;
      assertEquals(linha.custo_usd, 0);
      assertEquals(linha.ok, true);
      assertEquals(linha.robo, 'edge-teste');
    } finally { f.restaurar(); }
  });
}

Deno.test('Texto: Claude 429 → Groq responde (privado permitido, User-Agent de navegador)', async () => {
  preparar({ claude: true, groq: true });
  const f = fetchFalso({ claude: claudeHttp(429), groq: openaiOk('{"tags":["picante"]}') });
  try {
    const r = await pedirIa({ robo: 'edge-teste', sistema: 's', texto: 'prato', json: true });
    assert(r.ok);
    assertEquals(r.motor, 'groq');
    assertEquals(r.modelo, 'openai/gpt-oss-120b');
    const [g] = so(f.chamadas, URL_GROQ);
    assert((g.headers.get('user-agent') ?? '').includes('Mozilla'));
  } finally { f.restaurar(); }
});

Deno.test('Dados privados com imagem: Claude 402 → nenhum motor grátis vê a imagem → erro claro', async () => {
  preparar({ claude: true, groq: true, gemini: true, openrouter: true });
  const f = fetchFalso({ claude: claudeHttp(402), gemini: openaiOk('{}'), openrouter: openaiOk('{}') });
  try {
    const r = await pedirIa({ robo: 'edge-documentos', sistema: 's', texto: 'doc', anexos: [{ mime: 'image/jpeg', base64: PNG }], json: true });
    assert(!r.ok);
    assert(r.erro.startsWith('nenhum motor respondeu'), r.erro);
    assert(r.erro.includes('claude'), r.erro);
    assert(r.erro.includes('http 402'), r.erro);
    assert(r.erro.includes('dados privados'), r.erro);
    assertEquals(so(f.chamadas, URL_GEMINI).length, 0);
    assertEquals(so(f.chamadas, URL_OPENROUTER).length, 0);
    assertEquals(so(f.chamadas, URL_GROQ).length, 0); // o Groq não tem visão grátis
  } finally { f.restaurar(); }
});

Deno.test('Claude e reserva a falhar (500, 429, 500, 503): erro claro com cada motor', async () => {
  preparar({ claude: true, groq: true, gemini: true, openrouter: true });
  const f = fetchFalso({ claude: claudeHttp(500), groq: http(500), gemini: http(429), openrouter: http(500), kilo: http(503) });
  try {
    const r = await pedirIa({ robo: 'edge-teste', sistema: 's', texto: 'ola', privado: false });
    assert(!r.ok);
    for (const m of ['claude', 'groq', 'gemini-gratis', 'openrouter', 'kilo']) assert(r.erro.includes(m), `${m} em: ${r.erro}`);
    assert(r.erro.includes('http 429'), r.erro);
    // todos os modelos de texto de cada motor foram tentados
    assertEquals(so(f.chamadas, URL_GROQ).length, 3);
    assertEquals(so(f.chamadas, URL_KILO).length, 1);
  } finally { f.restaurar(); }
});

Deno.test('Sem chave do Claude e sem chaves grátis: erro claro diz o nome das chaves em falta', async () => {
  preparar({});
  const f = fetchFalso({ kilo: http(429) });
  try {
    const r = await pedirIa({ robo: 'edge-teste', sistema: 's', texto: 'ola', privado: false });
    assert(!r.ok);
    assert(r.erro.includes('sem ANTHROPIC_API_KEY'), r.erro);
    assert(r.erro.includes('sem a chave GROQ_API_KEY'), r.erro);
    assert(r.erro.includes('sem a chave GEMINI_API_KEY_FALLBACK'), r.erro);
    assertEquals(so(f.chamadas, URL_CLAUDE).length, 0);
  } finally { f.restaurar(); }
});

Deno.test('JSON pedido e o Claude responde prosa: passa ao motor seguinte', async () => {
  preparar({ claude: true, groq: true });
  const f = fetchFalso({ claude: claudeOk('Não sei dizer.'), groq: openaiOk('```json\n{"resumo":"bom"}\n```') });
  try {
    const r = await pedirIa({ robo: 'edge-teste', sistema: 's', texto: 'ola', json: true });
    assert(r.ok);
    assertEquals(r.motor, 'groq');
    assertEquals((r.json as Record<string, string>).resumo, 'bom');
    assertEquals(r.tentativas[0].erro, 'resposta sem JSON');
  } finally { f.restaurar(); }
});

Deno.test('HEIC: o Claude não é chamado; com privado=false vai ao Gemini grátis', async () => {
  preparar({ claude: true, gemini: true });
  const f = fetchFalso({ claude: claudeOk('{}'), gemini: openaiOk('{"ok":true}') });
  try {
    const r = await pedirIa({ robo: 'edge-teste', sistema: 's', texto: 'x', anexos: [{ mime: 'image/heic', base64: PNG }], json: true, privado: false });
    assert(r.ok);
    assertEquals(r.motor, 'gemini-gratis');
    assertEquals(so(f.chamadas, URL_CLAUDE).length, 0);
    assert(r.tentativas[0].erro!.includes('image/heic'));
  } finally { f.restaurar(); }
});

Deno.test('Erro de saldo da reserva nunca fica no livro com cara de "sem crédito do Claude"', async () => {
  preparar({ claude: true, openrouter: true });
  const f = fetchFalso({ claude: claudeHttp(500), openrouter: http(402, 'Your credit balance is too low') });
  try {
    const r = await pedirIa({ robo: 'edge-teste', sistema: 's', texto: 'x', privado: false });
    assert(!r.ok);
    const linhas = f.livro.filter((l) => String(l.modelo).startsWith('openrouter:'));
    assert(linhas.length > 0);
    for (const l of linhas) {
      const e = String(l.erro);
      assert(e.startsWith('reserva openrouter'), e);
      assert(!/credit balance/i.test(e) && !/^http 402/i.test(e), e);
    }
  } finally { f.restaurar(); }
});

Deno.test('PDF vai ao Claude como documento; imagem com mais de 5 MB não', () => {
  const pdf = anexosParaClaude([{ mime: 'application/pdf', base64: 'JVBERi0x' }]);
  assertEquals(pdf.motivo, null);
  assertEquals(pdf.blocos[0].type, 'document');
  const grande = anexosParaClaude([{ mime: 'image/jpeg', base64: 'A'.repeat(7 * 1024 * 1024) }]);
  assert(grande.motivo!.includes('5 MB'));
});

// ── Robô dos documentos (documentos_robo.analisar) por cima do módulo ─────────
Deno.test('Documentos: Haiku com pouca certeza → Sonnet; leitura válida e modelo "claude:..."', async () => {
  const { analisar } = await import('./documentos_robo.ts');
  preparar({ claude: true });
  let n = 0;
  const f = fetchFalso({
    claude: () => {
      n++;
      const conf = n === 1 ? 0.4 : 0.95;
      return claudeOk(JSON.stringify({ tipo_detectado: 'carta_conducao', legivel: true, nome_lido: null, nif_lido: null, validade: null, cara_nitida: null, confianca: conf }))();
    },
  });
  try {
    const a = await analisar('image/jpeg', PNG, 'carta_conducao', 0.85);
    assertEquals(a.httpStatus, 200);
    assertEquals(a.leitura?.confianca, 0.95);
    const modelos = so(f.chamadas, URL_CLAUDE).map((c) => c.corpo!.model);
    assertEquals(modelos, ['claude-haiku-5-5', 'claude-sonnet-5-5']);
    assertEquals(a.modelo, 'claude:claude-sonnet-5-5');
  } finally { f.restaurar(); }
});

Deno.test('Documentos: Claude 402 → sem leitura, sem motor grátis, erro claro e não repete com o forte', async () => {
  const { analisar } = await import('./documentos_robo.ts');
  preparar({ claude: true, gemini: true, openrouter: true, groq: true });
  const f = fetchFalso({ claude: claudeHttp(402), gemini: openaiOk('{}'), openrouter: openaiOk('{}') });
  try {
    const a = await analisar('image/jpeg', PNG, 'selfie', 0.85);
    assertEquals(a.leitura, null);
    assertEquals(a.httpStatus, 402);
    assert(a.erro!.includes('nenhum motor respondeu'), String(a.erro));
    assertEquals(so(f.chamadas, URL_CLAUDE).length, 1);
    assertEquals(so(f.chamadas, URL_GEMINI).length + so(f.chamadas, URL_OPENROUTER).length, 0);
  } finally { f.restaurar(); }
});

Deno.test('lerJson: objeto, lista, cercas e lixo', () => {
  assertEquals(lerJson('{"a":1}'), { a: 1 });
  assertEquals(lerJson('```json\n[{"a":1}]\n```'), [{ a: 1 }]);
  assertEquals(lerJson('Aqui está: {"b":2} fim'), { b: 2 });
  assertEquals(lerJson('nada aqui'), undefined);
});

Deno.test('mensagensOpenAI: sistema primeiro, conversa e anexos no último turno do utilizador', () => {
  const m = mensagensOpenAI({
    robo: 'r', sistema: 'S',
    conversa: [{ role: 'user', texto: 'a' }, { role: 'assistant', texto: 'b' }],
    texto: 'c', anexos: [{ mime: 'image/png', base64: PNG }],
  });
  assertEquals(m[0], { role: 'system', content: 'S' });
  assertEquals(m[1], { role: 'user', content: 'a' });
  assertEquals(m[2], { role: 'assistant', content: 'b' });
  assertEquals((m[3].content as Array<Record<string, unknown>>)[0], { type: 'text', text: 'c' });
});

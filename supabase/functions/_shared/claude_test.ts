// deno test --allow-env supabase/functions/_shared/claude_test.ts
// Prova o helper do Claude sem rede: o fetch é trocado por um falso que regista os pedidos.
// Valores de brincar construídos em tempo de execução (nada com cara de chave no ficheiro).
import { assert, assertEquals } from 'jsr:@std/assert@1';
import { claudePrimeiro, corpoPedido, custoClaudeUsd, ferramentasParaClaude, conversaParaClaude, extrairJson } from './claude.ts';

const URL_BANCO = 'https://projeto-de-brincar.supabase.co';
const CHAVE_API_FALSA = ['teste', 'claude', 'local'].join('-');
const CHAVE_BANCO_FALSA = ['sb', 'secret', 'brincar0123456789'].join('_');

type Chamada = { url: string; corpo: Record<string, unknown> | null; headers: Headers };

function preparar(comChave: boolean) {
  Deno.env.set('SUPABASE_URL', URL_BANCO);
  Deno.env.set('SUPABASE_SERVICE_ROLE_KEY', CHAVE_BANCO_FALSA);
  Deno.env.delete('SUPABASE_SECRET_KEYS');
  if (comChave) Deno.env.set('ANTHROPIC_API_KEY', CHAVE_API_FALSA);
  else Deno.env.delete('ANTHROPIC_API_KEY');
}

function fetchFalso(respostas: {
  porteiro?: () => Response;
  api?: () => Response;
}): { chamadas: Chamada[]; restaurar: () => void } {
  const original = globalThis.fetch;
  const chamadas: Chamada[] = [];
  const responder = (url: string): Response => {
    if (url.endsWith('/rest/v1/rpc/ia_claude_pode')) {
      return respostas.porteiro ? respostas.porteiro() : new Response(JSON.stringify({ code: 'PGRST202' }), { status: 404 });
    }
    if (url.endsWith('/rest/v1/ia_gastos')) return new Response(null, { status: 201 });
    if (url === 'https://api.anthropic.com/v1/messages') {
      return respostas.api ? respostas.api() : new Response('{}', { status: 500 });
    }
    return new Response('nao esperado', { status: 599 });
  };
  globalThis.fetch = ((input: string | URL | Request, init?: RequestInit) => {
    const url = String(input instanceof Request ? input.url : input);
    const corpo = init?.body ? JSON.parse(String(init.body)) : null;
    chamadas.push({ url, corpo, headers: new Headers(init?.headers) });
    return Promise.resolve(responder(url));
  }) as typeof fetch;
  return { chamadas, restaurar: () => { globalThis.fetch = original; } };
}

const sucesso = (conteudo: unknown[], stop = 'end_turn') => () => new Response(JSON.stringify({
  content: conteudo,
  stop_reason: stop,
  usage: { input_tokens: 1000, output_tokens: 200, cache_creation_input_tokens: 3000, cache_read_input_tokens: 0 },
}), { status: 200 });

const PEDIDO = {
  robo: 'edge-teste',
  prioridade: 1 as const,
  system: ['fixo A', 'fixo B'],
  contexto: 'variavel',
  messages: [{ role: 'user' as const, content: 'olá' }],
};

Deno.test('sem ANTHROPIC_API_KEY devolve null e não chama nada', async () => {
  preparar(false);
  const f = fetchFalso({});
  try {
    assertEquals(await claudePrimeiro(PEDIDO), null);
    assertEquals(f.chamadas.length, 0);
  } finally { f.restaurar(); }
});

Deno.test('corpo do Haiku: thinking disabled, effort low, sem temperature, cache no último bloco fixo', () => {
  const c = corpoPedido({ ...PEDIDO, maxTokens: 100, tools: ferramentasParaClaude([{ name: 'x', description: 'd' }]) }, 'claude-haiku-5-5');
  assertEquals(c.thinking, { type: 'disabled' });
  assertEquals(c.output_config, { effort: 'low' });
  assertEquals(c.max_tokens, 1024);
  assertEquals(c.tool_choice, { type: 'auto' });
  assert(!('temperature' in c) && !('top_p' in c) && !('top_k' in c));
  const sys = c.system as Array<Record<string, unknown>>;
  assertEquals(sys.length, 3);
  assertEquals(sys[0].cache_control, { type: 'ephemeral' });
  assertEquals(sys[1].cache_control, { type: 'ephemeral' });
  assertEquals(sys[2], { type: 'text', text: 'variavel' });
  // nunca mais de 3 marcas de cache, por muitos blocos fixos que venham
  const muitos = corpoPedido({ ...PEDIDO, system: ['a', 'b', 'c', 'd', 'e'] }, 'claude-haiku-5-5');
  const marcas = (muitos.system as Array<Record<string, unknown>>).filter((b) => b.cache_control).length;
  assertEquals(marcas, 3);
  const tools = c.tools as Array<Record<string, unknown>>;
  assertEquals(tools[0].input_schema, { type: 'object', properties: {} });
});

Deno.test('corpo do Sonnet: thinking between_tools; sem tools não manda tool_choice', () => {
  const c = corpoPedido(PEDIDO, 'claude-sonnet-5-5');
  assertEquals(c.thinking, { type: 'between_tools' });
  assert(!('tool_choice' in c) && !('tools' in c));
});

Deno.test('custo pelos preços oficiais', () => {
  const u = { input_tokens: 1000, output_tokens: 200, cache_creation_input_tokens: 3000, cache_read_input_tokens: 5000 };
  // haiku: 1000*0.10 + 200*0.50 + 3000*0.125 + 5000*0.01 = 100+100+375+50 = 625 / 1e6
  assertEquals(custoClaudeUsd('claude-haiku-5-5', u), 0.000625);
  // sonnet: 1000*2 + 200*10 + 3000*2.5 + 5000*0.2 = 2000+2000+7500+1000 = 12500 / 1e6
  assertEquals(custoClaudeUsd('claude-sonnet-5-5', u), 0.0125);
  // haiku acima de 100 mil tokens de entrada: 0.50 / 2.50 / 0.625 / 0.05
  const longo = { input_tokens: 100_001, output_tokens: 1000, cache_creation_input_tokens: 0, cache_read_input_tokens: 0 };
  assertEquals(custoClaudeUsd('claude-haiku-5-5', longo), Math.round((100_001 * 0.5 + 1000 * 2.5)) / 1e6);
});

Deno.test('porteiro inexistente: P3 também passa (sem ração desde 01/11/2026) e usa o Haiku', async () => {
  preparar(true);
  const f = fetchFalso({ api: sucesso([{ type: 'text', text: 'oi' }]) });
  try {
    const r = await claudePrimeiro({ ...PEDIDO, prioridade: 3 });
    assert(r);
    assertEquals(r.modelo, 'claude-haiku-5-5');
    assert(f.chamadas.some((c) => c.url.includes('anthropic')));
  } finally { f.restaurar(); }
});

Deno.test('porteiro inexistente: P1 passa com o modelo padrão, grava o gasto e devolve o texto', async () => {
  preparar(true);
  const f = fetchFalso({ api: sucesso([{ type: 'text', text: 'Olá! Em que posso ajudar?' }]) });
  try {
    const r = await claudePrimeiro(PEDIDO);
    assert(r);
    assertEquals(r.texto, 'Olá! Em que posso ajudar?');
    assertEquals(r.modelo, 'claude-sonnet-5-5');
    assertEquals(r.custoUsd, custoClaudeUsd('claude-sonnet-5-5', r.usage));
    const api = f.chamadas.find((c) => c.url.includes('anthropic'))!;
    assertEquals(api.headers.get('x-api-key'), CHAVE_API_FALSA);
    assertEquals(api.headers.get('anthropic-version'), '2023-06-01');
    const gasto = f.chamadas.find((c) => c.url.endsWith('/ia_gastos'))!;
    assertEquals(gasto.corpo?.ok, true);
    assertEquals(gasto.corpo?.maquina, 'edge');
    assertEquals(gasto.corpo?.perfil, 'edge-teste');
    assertEquals(gasto.corpo?.tokens_cache_escrita, 3000);
  } finally { f.restaurar(); }
});

Deno.test('porteiro diz que não → null; porteiro escolhe o Haiku → usa o Haiku', async () => {
  preparar(true);
  let f = fetchFalso({ porteiro: () => new Response(JSON.stringify({ pode: false, motivo: 'parte do dia esgotada' })) });
  try { assertEquals(await claudePrimeiro({ ...PEDIDO, prioridade: 2 }), null); } finally { f.restaurar(); }
  f = fetchFalso({
    porteiro: () => new Response(JSON.stringify({ pode: true, modelo: 'claude-haiku-5-5' })),
    api: sucesso([{ type: 'text', text: 'ok' }]),
  });
  try {
    const r = await claudePrimeiro({ ...PEDIDO, prioridade: 2 });
    assertEquals(r?.modelo, 'claude-haiku-5-5');
    const api = f.chamadas.find((c) => c.url.includes('anthropic'))!;
    assertEquals((api.corpo as Record<string, unknown>).thinking, { type: 'disabled' });
  } finally { f.restaurar(); }
});

Deno.test('porteiro devolve Opus → nunca: fica o padrão', async () => {
  preparar(true);
  const f = fetchFalso({
    porteiro: () => new Response(JSON.stringify({ pode: true, modelo: 'claude-opus-5-5' })),
    api: sucesso([{ type: 'text', text: 'ok' }]),
  });
  try {
    const r = await claudePrimeiro(PEDIDO);
    assertEquals(r?.modelo, 'claude-sonnet-5-5');
  } finally { f.restaurar(); }
});

for (const [nome, resp] of [
  ['400 sem crédito', () => new Response('{"error":{"message":"Your credit balance is too low"}}', { status: 400 })],
  ['401', () => new Response('{}', { status: 401 })],
  ['429', () => new Response('{}', { status: 429 })],
  ['529', () => new Response('{}', { status: 529 })],
  ['recusa', sucesso([], 'refusal')],
  ['resposta vazia', sucesso([])],
] as Array<[string, () => Response]>) {
  Deno.test(`falha "${nome}" → null e gasto ok=false`, async () => {
    preparar(true);
    const f = fetchFalso({ api: resp });
    try {
      assertEquals(await claudePrimeiro(PEDIDO), null);
      const gasto = f.chamadas.find((c) => c.url.endsWith('/ia_gastos'));
      assertEquals(gasto?.corpo?.ok, false);
    } finally { f.restaurar(); }
  });
}

Deno.test('última mensagem do assistente (prefill) → null sem chamar a API', async () => {
  preparar(true);
  const f = fetchFalso({ api: sucesso([{ type: 'text', text: 'x' }]) });
  try {
    const r = await claudePrimeiro({ ...PEDIDO, messages: [{ role: 'user', content: 'a' }, { role: 'assistant', content: 'b' }] });
    assertEquals(r, null);
    assertEquals(f.chamadas.length, 0);
  } finally { f.restaurar(); }
});

Deno.test('tool_use volta com id, nome e input; conteúdo tal e qual', async () => {
  preparar(true);
  const bloco = { type: 'tool_use', id: 'toolu_1', name: 'agent_get_order_status', input: { p_order_id: '42' } };
  const f = fetchFalso({ api: sucesso([{ type: 'text', text: 'Vou ver.' }, bloco], 'tool_use') });
  try {
    const r = await claudePrimeiro(PEDIDO);
    assertEquals(r?.toolUses, [{ id: 'toolu_1', name: 'agent_get_order_status', input: { p_order_id: '42' } }]);
    assertEquals(r?.conteudo[1], bloco);
  } finally { f.restaurar(); }
});

Deno.test('conversaParaClaude junta seguidas, tira vazias e começa no utilizador', () => {
  assertEquals(conversaParaClaude([
    { role: 'assistant', texto: 'boas-vindas' },
    { role: 'user', texto: 'a' },
    { role: 'user', texto: '' },
    { role: 'user', texto: 'b' },
    { role: 'assistant', texto: 'c' },
    { role: 'user', texto: 'd' },
  ]), [
    { role: 'user', content: 'a\n\nb' },
    { role: 'assistant', content: 'c' },
    { role: 'user', content: 'd' },
  ]);
});

Deno.test('extrairJson tira cercas e texto à volta', () => {
  assertEquals(extrairJson('```json\n{"yes": 0.8}\n```'), { yes: 0.8 });
  assertEquals(extrairJson('Aqui está: {"probabilities": {"a": 1}} pronto'), { probabilities: { a: 1 } });
});

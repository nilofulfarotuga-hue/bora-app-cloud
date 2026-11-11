// deno test --allow-env supabase/functions/_shared/claude_pesquisa_test.ts
// 11/11/2026 (missão fechar-tudo-2026-11-11, bloco 2): a pesquisa na internet do _shared/claude.ts, sem rede.
// O fetch é trocado por um falso que regista os pedidos. Valores de brincar construídos em tempo de execução.
import { assert, assertEquals } from 'jsr:@std/assert@1';
import {
  claudePrimeiro,
  corpoPedido,
  custoClaudeUsd,
  deveRepetirSemPesquisa,
  ferramentaPesquisaWeb,
  limitarUsosPesquisa,
  PRECO_PESQUISA_WEB_USD,
  registarGasto,
  semPesquisaWeb,
  textoDaResposta,
} from './claude.ts';

const URL_BANCO = 'https://projeto-de-brincar.supabase.co';
const CHAVE_API_FALSA = ['teste', 'claude', 'local'].join('-');
const CHAVE_BANCO_FALSA = ['sb', 'secret', 'brincar0123456789'].join('_');

function preparar() {
  Deno.env.set('SUPABASE_URL', URL_BANCO);
  Deno.env.set('SUPABASE_SERVICE_ROLE_KEY', CHAVE_BANCO_FALSA);
  Deno.env.delete('SUPABASE_SECRET_KEYS');
  Deno.env.set('ANTHROPIC_API_KEY', CHAVE_API_FALSA);
}

// deno-lint-ignore no-explicit-any
type Corpo = any;
type Chamada = { url: string; corpo: Corpo };

function fetchFalso(responder: (url: string, corpo: Corpo, n: number) => Response) {
  const original = globalThis.fetch;
  const chamadas: Chamada[] = [];
  globalThis.fetch = ((input: string | URL | Request, init?: RequestInit) => {
    const url = String(input instanceof Request ? input.url : input);
    const corpo = init?.body ? JSON.parse(String(init.body)) : null;
    chamadas.push({ url, corpo });
    const n = chamadas.filter((c) => c.url === url).length;
    if (url.endsWith('/rest/v1/rpc/ia_claude_pode')) {
      return Promise.resolve(new Response(JSON.stringify({ pode: true, modelo: 'claude-sonnet-5-5', motivo: 'teste' }), { status: 200 }));
    }
    return Promise.resolve(responder(url, corpo, n));
  }) as typeof fetch;
  return {
    chamadas,
    api: () => chamadas.filter((c) => c.url === 'https://api.anthropic.com/v1/messages'),
    gastos: () => chamadas.filter((c) => c.url.endsWith('/rest/v1/ia_gastos')),
    restaurar: () => { globalThis.fetch = original; },
  };
}

const temPesquisa = (corpo: Corpo) => Array.isArray(corpo?.tools) && corpo.tools.some((t: Corpo) => t?.name === 'web_search');

const okJson = (conteudo: unknown[], stop = 'end_turn', pesquisas = 0) => new Response(JSON.stringify({
  content: conteudo,
  stop_reason: stop,
  usage: {
    input_tokens: 1000, output_tokens: 100, cache_creation_input_tokens: 0, cache_read_input_tokens: 0,
    ...(pesquisas ? { server_tool_use: { web_search_requests: pesquisas } } : {}),
  },
}), { status: 200 });

const PEDIDO = {
  robo: 'edge-teste',
  prioridade: 1 as const,
  system: ['fixo'],
  messages: [{ role: 'user' as const, content: 'como vai estar o tempo amanhã na Guarda?' }],
  pesquisaWeb: { maxUsos: 3, local: { cidade: 'Guarda', regiao: 'Guarda', pais: 'PT', fuso: 'Europe/Lisbon' } },
};

Deno.test('ferramenta de pesquisa: versão básica, usos entre 1 e 5, local aproximado', () => {
  const t = ferramentaPesquisaWeb({ maxUsos: 9, local: { cidade: 'Guarda', pais: 'PT', fuso: 'Europe/Lisbon' } });
  assertEquals(t.type, 'web_search_20250305');
  assertEquals(t.name, 'web_search');
  assertEquals(t.max_uses, 5);
  assertEquals(t.user_location, { type: 'approximate', city: 'Guarda', country: 'PT', timezone: 'Europe/Lisbon' });
  assertEquals(limitarUsosPesquisa(0), 1);
  assertEquals(limitarUsosPesquisa('abc'), 3);
  assertEquals(limitarUsosPesquisa(3), 3);
  assert(!('user_location' in ferramentaPesquisaWeb({ maxUsos: 2 })));
});

Deno.test('corpo com pesquisa: vai no fim das ferramentas do cliente, tool_choice auto', () => {
  const c = corpoPedido({ ...PEDIDO, tools: [{ name: 'x', description: 'd', input_schema: { type: 'object', properties: {} } }] }, 'claude-sonnet-5-5');
  const tools = c.tools as Corpo[];
  assertEquals(tools.length, 2);
  assertEquals(tools[0].name, 'x');
  assertEquals(tools[1].name, 'web_search');
  assertEquals(c.tool_choice, { type: 'auto' });
  // sem ferramentas do cliente, só a pesquisa
  const c2 = corpoPedido({ ...PEDIDO }, 'claude-haiku-5-5');
  assertEquals((c2.tools as Corpo[]).map((t) => t.name), ['web_search']);
  // sem pesquisa e sem ferramentas: igual a antes (sem tools nem tool_choice)
  const c3 = corpoPedido({ ...PEDIDO, pesquisaWeb: undefined }, 'claude-haiku-5-5');
  assert(!('tools' in c3) && !('tool_choice' in c3));
});

const HIST_COM_PESQUISA = [
  { role: 'user' as const, content: 'tempo amanhã?' },
  {
    role: 'assistant' as const, content: [
      { type: 'text', text: 'Vou ver.' },
      { type: 'server_tool_use', id: 'srv_1', name: 'web_search', input: { query: 'tempo Guarda' } },
      { type: 'web_search_tool_result', tool_use_id: 'srv_1', content: [{ type: 'web_search_result', url: 'https://exemplo.pt', title: 't' }] },
      { type: 'text', text: 'Amanhã chove.', citations: [{ type: 'web_search_result_location', url: 'https://exemplo.pt' }] },
      { type: 'tool_use', id: 'tu_1', name: 'lojas_abertas', input: {} },
    ],
  },
  { role: 'user' as const, content: [{ type: 'tool_result', tool_use_id: 'tu_1', content: '{}' }] },
];

Deno.test('sem a pesquisa, o histórico perde os blocos do servidor e as citações; os tool_result ficam', () => {
  const limpo = semPesquisaWeb(HIST_COM_PESQUISA);
  const blocos = limpo[1].content as Corpo[];
  assertEquals(blocos.map((b) => b.type), ['text', 'text', 'tool_use']);
  assert(!('citations' in blocos[1]));
  assertEquals((limpo[2].content as Corpo[])[0].type, 'tool_result');
  // e o corpoPedido faz isso sozinho quando o pedido vai sem a pesquisa
  const c = corpoPedido({ ...PEDIDO, pesquisaWeb: undefined, messages: HIST_COM_PESQUISA }, 'claude-sonnet-5-5');
  const m1 = (c.messages as Corpo[])[1].content as Corpo[];
  assert(!m1.some((b) => b.type === 'server_tool_use' || b.type === 'web_search_tool_result'));
  // com a pesquisa, o histórico vai tal e qual
  const c2 = corpoPedido({ ...PEDIDO, messages: HIST_COM_PESQUISA }, 'claude-sonnet-5-5');
  assertEquals(((c2.messages as Corpo[])[1].content as Corpo[]).length, 5);
});

Deno.test('o texto da resposta é o que vem depois da última pesquisa', () => {
  assertEquals(textoDaResposta(HIST_COM_PESQUISA[1].content as Corpo[]), 'Amanhã chove.');
  assertEquals(textoDaResposta([{ type: 'text', text: 'Olá ' }, { type: 'text', text: 'tu.' }]), 'Olá tu.');
});

Deno.test('regra do 400: só com pesquisa e nunca na falta de crédito', () => {
  assert(deveRepetirSemPesquisa(400, 'tools.1: invalid', true));
  assert(!deveRepetirSemPesquisa(400, 'tools.1: invalid', false));
  assert(!deveRepetirSemPesquisa(400, 'Your credit balance is too low', true));
  assert(!deveRepetirSemPesquisa(429, 'rate', true));
  assert(!deveRepetirSemPesquisa(500, 'x', true));
});

Deno.test('400 com a pesquisa → repete o MESMO pedido sem ela e responde', async () => {
  preparar();
  const f = fetchFalso((url, corpo) => {
    if (url.endsWith('/rest/v1/ia_gastos')) return new Response(null, { status: 201 });
    if (temPesquisa(corpo)) return new Response(JSON.stringify({ type: 'error', error: { type: 'invalid_request_error', message: 'web_search not enabled' } }), { status: 400 });
    return okJson([{ type: 'text', text: 'Não consegui ver a previsão agora.' }]);
  });
  try {
    const r = await claudePrimeiro(PEDIDO);
    assert(r !== null);
    assertEquals(r.texto, 'Não consegui ver a previsão agora.');
    assertEquals(r.semPesquisaPor400, true);
    assertEquals(r.pesquisasWeb, 0);
    const api = f.api();
    assertEquals(api.length, 2);
    assert(temPesquisa(api[0].corpo));
    assert(!temPesquisa(api[1].corpo));
    // o resto do pedido é igual
    assertEquals(api[1].corpo.messages, api[0].corpo.messages);
    assertEquals(api[1].corpo.system, api[0].corpo.system);
    assertEquals(api[1].corpo.model, api[0].corpo.model);
    // fica registado: a falhada (ok=false) e a boa
    const g = f.gastos().map((c) => c.corpo);
    assertEquals(g.length, 2);
    assertEquals(g[0].ok, false);
    assert(String(g[0].erro).includes('repetido sem ela'));
    assertEquals(g[1].ok, true);
  } finally { f.restaurar(); }
});

Deno.test('400 de falta de crédito com a pesquisa → null, sem repetir', async () => {
  preparar();
  const f = fetchFalso((url) => {
    if (url.endsWith('/rest/v1/ia_gastos')) return new Response(null, { status: 201 });
    return new Response('Your credit balance is too low to access the Anthropic API', { status: 400 });
  });
  try {
    assertEquals(await claudePrimeiro(PEDIDO), null);
    assertEquals(f.api().length, 1);
  } finally { f.restaurar(); }
});

Deno.test('pause_turn continua com o que veio; pesquisas contadas e pagas a 0,01 USD', async () => {
  preparar();
  const f = fetchFalso((url, _corpo, n) => {
    if (url.endsWith('/rest/v1/ia_gastos')) return new Response(null, { status: 201 });
    if (n === 1) {
      return okJson([
        { type: 'server_tool_use', id: 'srv_1', name: 'web_search', input: { query: 'tempo Guarda amanhã' } },
        { type: 'web_search_tool_result', tool_use_id: 'srv_1', content: [] },
      ], 'pause_turn', 1);
    }
    return okJson([{ type: 'text', text: 'Amanhã na Guarda: chuva e 8 graus (IPMA).' }], 'end_turn', 1);
  });
  try {
    const r = await claudePrimeiro(PEDIDO);
    assert(r !== null);
    assertEquals(r.texto, 'Amanhã na Guarda: chuva e 8 graus (IPMA).');
    assertEquals(r.pesquisasWeb, 2);
    assertEquals(r.conteudo.length, 3);
    const api = f.api();
    assertEquals(api.length, 2);
    const ultima = api[1].corpo.messages.at(-1);
    assertEquals(ultima.role, 'assistant');
    assertEquals(ultima.content.length, 2);
    // custo = tokens das duas chamadas + 2 pesquisas
    const tokens = custoClaudeUsd('claude-sonnet-5-5', { input_tokens: 2000, output_tokens: 200, cache_creation_input_tokens: 0, cache_read_input_tokens: 0 });
    assertEquals(r.custoUsd, Math.round((tokens + 2 * PRECO_PESQUISA_WEB_USD) * 1e6) / 1e6);
    const g = f.gastos().map((c) => c.corpo);
    assertEquals(g.length, 1);
    assertEquals(g[0].pesquisas_web, 2);
    assertEquals(g[0].custo_usd, r.custoUsd);
  } finally { f.restaurar(); }
});

Deno.test('sem a coluna pesquisas_web (migração por aplicar) grava o gasto sem ela', async () => {
  preparar();
  const f = fetchFalso((url, corpo) => {
    if (url.endsWith('/rest/v1/ia_gastos')) {
      if (corpo && 'pesquisas_web' in corpo) return new Response('{"code":"PGRST204","message":"Could not find the \'pesquisas_web\' column of \'ia_gastos\'"}', { status: 400 });
      return new Response(null, { status: 201 });
    }
    return new Response('', { status: 599 });
  });
  try {
    await registarGasto({
      robo: 'edge-teste', prioridade: 1, modelo: 'claude-sonnet-5-5',
      uso: { input_tokens: 1, output_tokens: 1, cache_creation_input_tokens: 0, cache_read_input_tokens: 0 },
      custo: 0.02, ms: 10, ok: true, pesquisasWeb: 1,
    });
    const g = f.gastos().map((c) => c.corpo);
    assertEquals(g.length, 2);
    assertEquals(g[0].pesquisas_web, 1);
    assert(!('pesquisas_web' in g[1]));
    assertEquals(g[1].custo_usd, 0.02);
  } finally { f.restaurar(); }
});

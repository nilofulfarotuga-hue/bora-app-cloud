// _shared/claude.ts — o Claude PRIMEIRO nas Edge Functions, o Gemini de cada função fica de reserva.
// Missão motor-claude-2026-10-31 (Bloco 2 da retoma-geral-2026-10-31). Ordem do Danilo 31/10:
// os robôs usam primeiro o crédito da API do Claude e, quando acaba, a rotação grátis.
//
// claudePrimeiro(...) devolve a resposta do Claude, ou null quando o Claude não serve agora:
//   sem ANTHROPIC_API_KEY · o porteiro (RPC ia_claude_pode) diz que não · sem crédito ·
//   400/401/402/403/404/429/529/5xx · timeout de 20 s · recusa (stop_reason "refusal") · resposta vazia.
// Com null, quem chama segue o caminho Gemini que já tinha, sem erro para ninguém.
//
// Porteiro: public.ia_claude_pode(p_prioridade, p_robo) — a mesma regra do porteiro da VPS. Desde 01/11/2026
// SEM RAÇÃO (migração 20261101204928): tudo pelo Claude até a API dizer "sem crédito" (falha em ia_gastos nas
// últimas 6 h). Se o banco não responder, passam todos.
// Cada chamada (boa ou falhada) fica em public.ia_gastos; se a tabela ainda não existir, ignora-se.
//
// Regras da API para claude-haiku-5-5 e claude-sonnet-5-5 (dão 400 se forem quebradas):
//   sem temperature/top_p/top_k · tool_choice só "auto" · sem prefill (a última mensagem é do user) ·
//   haiku: thinking {type:"disabled"} · sonnet: thinking {type:"between_tools"} · effort "low" ·
//   max_tokens >= 1024. Opus nunca é escolhido aqui.
// Fetch puro (sem SDK) para api.anthropic.com e para o PostgREST; a chave nunca vai para o log.
import { secretKey } from './keys.ts';

export type ModeloClaude = 'claude-haiku-5-5' | 'claude-sonnet-5-5';
export const MODELOS_CLAUDE: readonly ModeloClaude[] = ['claude-haiku-5-5', 'claude-sonnet-5-5'];

export function ehModeloClaude(m: unknown): m is ModeloClaude {
  return typeof m === 'string' && (MODELOS_CLAUDE as readonly string[]).includes(m);
}

// deno-lint-ignore no-explicit-any
export type BlocoClaude = Record<string, any>;

export interface MensagemClaude {
  role: 'user' | 'assistant';
  content: string | BlocoClaude[];
}

export interface FerramentaClaude {
  name: string;
  description: string;
  input_schema: Record<string, unknown>;
}

export interface UsoClaude {
  input_tokens: number;
  output_tokens: number;
  cache_creation_input_tokens: number;
  cache_read_input_tokens: number;
}

export interface ToolUseClaude {
  id: string;
  name: string;
  input: Record<string, unknown>;
}

export interface PedidoClaude {
  /** Nome do robô em ia_gastos e em platform_settings.claude_robos (edge-decidir, edge-suporte, ...). */
  robo: string;
  /** 1 clientes · 2 decisões e admin · 3 volume. */
  prioridade: 1 | 2 | 3;
  /** Texto FIXO do sistema (um ou mais blocos). Levam cache_control (o último e até 2 antes): fica em cache. */
  system: string | string[];
  /** Texto que muda a cada pedido (contexto, RAG). Vai num bloco DEPOIS do que está em cache. */
  contexto?: string;
  messages: MensagemClaude[];
  tools?: FerramentaClaude[];
  /** Mínimo 1024 (regra da API para estes modelos). Por defeito 2048. */
  maxTokens?: number;
  /** Força o modelo (troca no painel, ou a volta seguinte do mesmo ciclo de ferramentas). */
  modelo?: ModeloClaude;
}

export interface RespostaClaude {
  texto: string;
  toolUses: ToolUseClaude[];
  stopReason: string;
  modelo: ModeloClaude;
  usage: UsoClaude;
  custoUsd: number;
  /** Duração da chamada à API (ms). */
  ms: number;
  /** Conteúdo tal e qual veio: é isto que se devolve como mensagem 'assistant' antes dos tool_result. */
  conteudo: BlocoClaude[];
}

const API_URL = 'https://api.anthropic.com/v1/messages';
const API_VERSAO = '2023-06-01';
const TIMEOUT_MS = 20_000;
const TIMEOUT_BANCO_MS = 4_000;

// Preços oficiais (USD por milhão de tokens), lidos a 31/10/2026.
// Haiku 5.5 acima de 100 mil tokens de entrada no pedido: 0,50 / 2,50 / 0,625 / 0,05.
interface Precos { entrada: number; saida: number; cacheEscrita: number; cacheLeitura: number }
const PRECO_HAIKU: Precos = { entrada: 0.10, saida: 0.50, cacheEscrita: 0.125, cacheLeitura: 0.01 };
const PRECO_HAIKU_LONGO: Precos = { entrada: 0.50, saida: 2.50, cacheEscrita: 0.625, cacheLeitura: 0.05 };
const PRECO_SONNET: Precos = { entrada: 2, saida: 10, cacheEscrita: 2.5, cacheLeitura: 0.20 };

export function custoClaudeUsd(modelo: ModeloClaude, u: UsoClaude): number {
  const totalEntrada = u.input_tokens + u.cache_creation_input_tokens + u.cache_read_input_tokens;
  const p = modelo === 'claude-sonnet-5-5'
    ? PRECO_SONNET
    : (totalEntrada > 100_000 ? PRECO_HAIKU_LONGO : PRECO_HAIKU);
  const usd = (u.input_tokens * p.entrada + u.output_tokens * p.saida +
    u.cache_creation_input_tokens * p.cacheEscrita + u.cache_read_input_tokens * p.cacheLeitura) / 1e6;
  return Math.round(usd * 1e6) / 1e6;
}

function numero(x: unknown): number {
  const n = Number(x);
  return Number.isFinite(n) && n > 0 ? Math.round(n) : 0;
}

function usoDe(u: unknown): UsoClaude {
  const o = (u && typeof u === 'object' ? u : {}) as Record<string, unknown>;
  return {
    input_tokens: numero(o.input_tokens),
    output_tokens: numero(o.output_tokens),
    cache_creation_input_tokens: numero(o.cache_creation_input_tokens),
    cache_read_input_tokens: numero(o.cache_read_input_tokens),
  };
}

const USO_ZERO: UsoClaude = { input_tokens: 0, output_tokens: 0, cache_creation_input_tokens: 0, cache_read_input_tokens: 0 };

function modeloPadrao(prioridade: number): ModeloClaude {
  return prioridade <= 2 ? 'claude-sonnet-5-5' : 'claude-haiku-5-5';
}

function cabecalhosBanco(chave: string): Record<string, string> {
  // Igual ao que o supabase-js manda com a chave secreta (apikey + Bearer).
  return { apikey: chave, Authorization: `Bearer ${chave}`, 'Content-Type': 'application/json' };
}

// ── Porteiro ────────────────────────────────────────────────────────────────
interface Porteiro { pode: boolean; modelo: ModeloClaude; motivo: string }

async function perguntarPorteiro(prioridade: number, robo: string): Promise<Porteiro> {
  const padrao = modeloPadrao(prioridade);
  const url = Deno.env.get('SUPABASE_URL');
  const chave = secretKey();
  try {
    if (!url || !chave) throw new Error('sem SUPABASE_URL ou chave do servidor');
    const r = await fetch(`${url}/rest/v1/rpc/ia_claude_pode`, {
      method: 'POST',
      headers: cabecalhosBanco(chave),
      body: JSON.stringify({ p_prioridade: prioridade, p_robo: robo }),
      signal: AbortSignal.timeout(TIMEOUT_BANCO_MS),
    });
    if (!r.ok) throw new Error(`http ${r.status}: ${(await r.text()).slice(0, 160)}`);
    const j = await r.json() as Record<string, unknown> | null;
    if (!j || typeof j.pode !== 'boolean') throw new Error('resposta sem "pode"');
    return { pode: j.pode, modelo: ehModeloClaude(j.modelo) ? j.modelo : padrao, motivo: String(j.motivo ?? '') };
  } catch (e) {
    // O banco não respondeu: desde 01/11/2026 (sem ração, ordem do Danilo) todos passam; se o crédito tiver
    // acabado, a própria API responde "sem crédito" e a função segue o Gemini.
    return { pode: true, modelo: padrao, motivo: `sem porteiro: ${(e as Error).message}` };
  }
}

// ── Livro de gastos ─────────────────────────────────────────────────────────
async function registarGasto(linha: {
  robo: string; prioridade: number; modelo: string; uso: UsoClaude; custo: number;
  ms: number; ok: boolean; erro?: string | null;
}): Promise<void> {
  const url = Deno.env.get('SUPABASE_URL');
  const chave = secretKey();
  if (!url || !chave) return;
  try {
    const r = await fetch(`${url}/rest/v1/ia_gastos`, {
      method: 'POST',
      headers: { ...cabecalhosBanco(chave), Prefer: 'return=minimal' },
      body: JSON.stringify({
        maquina: 'edge',
        robo: linha.robo,
        perfil: linha.robo,
        prioridade: linha.prioridade,
        modelo: linha.modelo,
        tokens_entrada: linha.uso.input_tokens,
        tokens_saida: linha.uso.output_tokens,
        tokens_cache_escrita: linha.uso.cache_creation_input_tokens,
        tokens_cache_leitura: linha.uso.cache_read_input_tokens,
        custo_usd: linha.custo,
        ms: linha.ms,
        ok: linha.ok,
        erro: linha.erro ? linha.erro.slice(0, 500) : null,
      }),
      signal: AbortSignal.timeout(TIMEOUT_BANCO_MS),
    });
    if (!r.ok) await r.text().catch(() => ''); // tabela ainda não existe (migração por aplicar): ignora-se
  } catch {
    // ignora-se: o livro de gastos nunca derruba a resposta
  }
}

// ── Montagem do pedido ──────────────────────────────────────────────────────
function blocosSistema(system: string | string[], contexto?: string): BlocoClaude[] {
  const fixos = (Array.isArray(system) ? system : [system]).filter((t) => typeof t === 'string' && t.trim().length > 0);
  const blocos: BlocoClaude[] = fixos.map((t) => ({ type: 'text', text: t }));
  // cache_control no último bloco fixo e também nos anteriores (até 3 marcas; a API aceita 4):
  // se um bloco fixo do meio mudar (ex.: a lista de guias), o primeiro continua a vir da cache.
  for (let i = Math.max(0, blocos.length - 3); i < blocos.length; i++) {
    blocos[i].cache_control = { type: 'ephemeral' };
  }
  if (contexto && contexto.trim()) blocos.push({ type: 'text', text: contexto });
  return blocos;
}

function mensagemVazia(m: MensagemClaude): boolean {
  if (typeof m.content === 'string') return m.content.trim().length === 0;
  return !Array.isArray(m.content) || m.content.length === 0;
}

/** Corpo do pedido (exportado para os testes). */
export function corpoPedido(p: PedidoClaude, modelo: ModeloClaude): Record<string, unknown> {
  const corpo: Record<string, unknown> = {
    model: modelo,
    max_tokens: Math.max(1024, Math.round(p.maxTokens ?? 2048)),
    system: blocosSistema(p.system, p.contexto),
    messages: p.messages.filter((m) => !mensagemVazia(m)),
    thinking: modelo === 'claude-haiku-5-5' ? { type: 'disabled' } : { type: 'between_tools' },
    output_config: { effort: 'low' },
  };
  if (p.tools && p.tools.length > 0) {
    corpo.tools = p.tools;
    corpo.tool_choice = { type: 'auto' };
  }
  return corpo;
}

// ── A chamada ───────────────────────────────────────────────────────────────
export async function claudePrimeiro(p: PedidoClaude): Promise<RespostaClaude | null> {
  const chaveApi = Deno.env.get('ANTHROPIC_API_KEY');
  if (!chaveApi) return null;

  const msgs = p.messages.filter((m) => !mensagemVazia(m));
  if (msgs.length === 0 || msgs[0].role !== 'user' || msgs[msgs.length - 1].role !== 'user') {
    // A API não aceita prefill nem conversa que comece pelo assistente: segue o Gemini.
    console.log(`[claude] robo=${p.robo} conversa mal formada (1.a/ultima mensagem nao e do user): reserva`);
    return null;
  }

  const porteiro = await perguntarPorteiro(p.prioridade, p.robo);
  if (!porteiro.pode) {
    console.log(`[claude] robo=${p.robo} P${p.prioridade} porteiro diz nao: ${porteiro.motivo}`);
    return null;
  }
  const modelo: ModeloClaude = p.modelo && ehModeloClaude(p.modelo) ? p.modelo : porteiro.modelo;

  const ctrl = new AbortController();
  const relogio = setTimeout(() => ctrl.abort(), TIMEOUT_MS);
  const t0 = Date.now();
  let erro: string | null = null;
  let uso: UsoClaude = USO_ZERO;
  try {
    const resp = await fetch(API_URL, {
      method: 'POST',
      headers: {
        'x-api-key': chaveApi,
        'anthropic-version': API_VERSAO,
        'content-type': 'application/json',
      },
      body: JSON.stringify(corpoPedido({ ...p, messages: msgs }, modelo)),
      signal: ctrl.signal,
    });
    if (!resp.ok) {
      const txt = (await resp.text().catch(() => '')).slice(0, 300);
      const semCredito = resp.status === 400 && /credit balance/i.test(txt);
      erro = `http ${resp.status}${semCredito ? ' (sem credito)' : ''}: ${txt}`;
      return null;
    }
    // deno-lint-ignore no-explicit-any
    const j = await resp.json() as any;
    uso = usoDe(j?.usage);
    const conteudo: BlocoClaude[] = Array.isArray(j?.content) ? j.content : [];
    const stopReason = String(j?.stop_reason ?? '');
    if (stopReason === 'refusal') {
      erro = `refusal: ${j?.stop_details?.category ?? 'sem categoria'}`;
      return null;
    }
    const texto = conteudo
      .filter((b) => b?.type === 'text' && typeof b.text === 'string')
      .map((b) => b.text as string)
      .join('')
      .trim();
    const toolUses: ToolUseClaude[] = conteudo
      .filter((b) => b?.type === 'tool_use' && typeof b.id === 'string' && typeof b.name === 'string')
      .map((b) => ({
        id: b.id as string,
        name: b.name as string,
        input: (b.input && typeof b.input === 'object' && !Array.isArray(b.input) ? b.input : {}) as Record<string, unknown>,
      }));
    if (!texto && toolUses.length === 0) {
      erro = `resposta vazia (stop_reason=${stopReason || '?'})`;
      return null;
    }
    const ms = Date.now() - t0;
    const custoUsd = custoClaudeUsd(modelo, uso);
    await registarGasto({ robo: p.robo, prioridade: p.prioridade, modelo, uso, custo: custoUsd, ms, ok: true });
    return { texto, toolUses, stopReason, modelo, usage: uso, custoUsd, ms, conteudo };
  } catch (e) {
    const nome = (e as Error)?.name ?? '';
    erro = nome === 'AbortError' ? `timeout ${TIMEOUT_MS / 1000} s` : `fetch: ${(e as Error)?.message ?? e}`;
    return null;
  } finally {
    clearTimeout(relogio);
    if (erro) {
      console.log(`[claude] robo=${p.robo} modelo=${modelo} falhou, reserva Gemini: ${erro.slice(0, 200)}`);
      await registarGasto({
        robo: p.robo, prioridade: p.prioridade, modelo, uso, custo: custoClaudeUsd(modelo, uso),
        ms: Date.now() - t0, ok: false, erro,
      });
    }
  }
}

// ── Ajudas para quem chama ──────────────────────────────────────────────────

/** Declarações de função no formato Gemini ({name, description, parameters}) → ferramentas Claude. */
export function ferramentasParaClaude(
  decls: Array<{ name: string; description?: string; parameters?: Record<string, unknown> }>,
  limparDescricao: (d: string) => string = (d) => d,
): FerramentaClaude[] {
  return decls.map((d) => {
    const schema: Record<string, unknown> = { ...(d.parameters ?? {}) };
    if (schema.type !== 'object') schema.type = 'object';
    if (!schema.properties || typeof schema.properties !== 'object') schema.properties = {};
    return { name: d.name, description: limparDescricao(d.description ?? d.name), input_schema: schema };
  });
}

/**
 * Junta mensagens seguidas do mesmo lado (texto), deita fora as vazias e garante que a conversa
 * começa no utilizador. Não acrescenta nada no fim: se a última não for do utilizador,
 * claudePrimeiro devolve null e segue o Gemini.
 */
export function conversaParaClaude(itens: Array<{ role: 'user' | 'assistant'; texto: string }>): MensagemClaude[] {
  const out: Array<{ role: 'user' | 'assistant'; content: string }> = [];
  for (const it of itens) {
    const t = (it.texto ?? '').trim();
    if (!t) continue;
    const ultima = out[out.length - 1];
    if (ultima && ultima.role === it.role) ultima.content += `\n\n${t}`;
    else out.push({ role: it.role, content: t });
  }
  while (out.length > 0 && out[0].role !== 'user') out.shift();
  return out;
}

/** Tira cercas ```json e devolve o objeto JSON da resposta (do 1.º "{" ao último "}"). Lança se não houver. */
// deno-lint-ignore no-explicit-any
export function extrairJson(texto: string): any {
  let raw = (texto ?? '').trim().replace(/^```(?:json)?\s*/i, '').replace(/```\s*$/i, '').trim();
  const a = raw.indexOf('{');
  const b = raw.lastIndexOf('}');
  if (a >= 0 && b > a) raw = raw.slice(a, b + 1);
  return JSON.parse(raw);
}

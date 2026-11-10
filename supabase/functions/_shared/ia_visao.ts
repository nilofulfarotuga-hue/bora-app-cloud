// _shared/ia_visao.ts — um só caminho para os robôs que liam imagens ou texto com o Gemini do projeto
// Google "bora-juiz" (missão fechar-tudo-2026-11-10, bloco H). Ordem do Danilo:
//   1. PRIMEIRO a API do Claude (claudePrimeiro: porteiro ia_claude_pode + livro ia_gastos);
//   2. se falhar ou acabar o crédito, a rotação de motores GRÁTIS (a mesma lista medida do Motor Bora,
//      ferramentas/vps/motor-bora/catalogo.py), do melhor para o pior;
//   3. com tudo a falhar, um erro claro com o que cada motor respondeu. Nunca pagamento novo no Google.
//
// Dados privados (documentos de identificação, talões com NIF, conversas de clientes): `privado: true`
// (é o valor por defeito) só deixa passar motores que NÃO treinam com o que recebem. Hoje, da lista
// grátis, só o Groq (texto; o Groq deixou de ter visão grátis a 08/09). Por isso, nas imagens privadas a
// reserva fica vazia e o erro manda ver à mão — a regra que já estava escrita no robô dos documentos
// ("nunca a chave grátis: a Google pode usar o conteúdo").
//
// Claude: modelo pelo porteiro (painel, platform_settings.claude_robos); sem escolha, P3 = claude-haiku-5-5,
// o mais barato que vê imagens (0,10/0,50 USD por milhão). Imagens JPEG/PNG/GIF/WebP até 5 MB e PDF vão
// ao Claude; HEIC não (passa logo à reserva, se a reserva for permitida).
//
// Cada chamada fica em public.ia_gastos: as do Claude pelo claude.ts (com custo); as da reserva aqui, com
// modelo "<motor>:<modelo>" e custo 0. Nenhuma chave vai para o log.
import {
  claudePrimeiro,
  conversaParaClaude,
  registarGasto,
  type BlocoClaude,
  type MensagemClaude,
  type ModeloClaude,
} from './claude.ts';

export interface AnexoIa {
  /** image/jpeg, image/png, image/gif, image/webp, image/heic ou application/pdf */
  mime: string;
  /** conteúdo em base64, sem cabeçalho data: */
  base64: string;
}

export interface PedidoIa {
  /** Nome do robô em ia_gastos e no painel (platform_settings.claude_robos). */
  robo: string;
  /** 1 clientes · 2 decisões e admin · 3 volume (por defeito 3). */
  prioridade?: 1 | 2 | 3;
  /** Texto fixo do sistema. */
  sistema: string;
  /** Pergunta deste pedido (último turno do utilizador). */
  texto?: string;
  /** Conversa (o último turno tem de ser do utilizador; o `texto`, se vier, junta-se no fim). */
  conversa?: Array<{ role: 'user' | 'assistant'; texto: string }>;
  /** Imagens ou PDF: vão no último turno do utilizador. */
  anexos?: AnexoIa[];
  /** Tokens de saída (por defeito 1024; o Claude pede no mínimo 1024). */
  maxTokens?: number;
  /** true: a resposta tem de ser JSON (objeto ou lista); se não for, conta como falha e passa ao seguinte. */
  json?: boolean;
  /** true (por defeito): só motores que não treinam com os dados. */
  privado?: boolean;
  /** Força o modelo do Claude (ex.: o "forte" numa segunda volta). Sem isto, decide o porteiro. */
  modeloClaude?: ModeloClaude;
  /** Tempo total para tentar (por defeito 45 s). */
  prazoMs?: number;
  /** Tempo máximo só da chamada ao Claude (por defeito 20 s, o do claude.ts; respostas longas pedem mais). */
  timeoutClaudeMs?: number;
}

export interface TentativaIa {
  motor: string;
  modelo: string;
  ok: boolean;
  http: number | null;
  erro: string | null;
  ms: number;
}

export type RespostaIa =
  | { ok: true; texto: string; json: unknown; motor: string; modelo: string; custoUsd: number; tentativas: TentativaIa[] }
  | { ok: false; erro: string; tentativas: TentativaIa[] };

export interface MotorGratis {
  nome: string;
  /** endpoint compatível com OpenAI (chat/completions) */
  url: string;
  /** variável de ambiente com a chave (null = não precisa de chave) */
  chaveEnv: string | null;
  texto: string[];
  visao: string[];
  /** formatos de imagem que este motor aceita */
  mimesVisao: string[];
  /** pode ver dados privados (não treina com o que recebe) */
  privadoOk: boolean;
  /** o fornecedor devolve 403/1010 sem User-Agent de navegador */
  uaNavegador?: boolean;
}

// Lista grátis medida (Motor Bora, catalogo.py: _GRATIS_VIVOS de 29/10 e perfil "visao" de 08/09).
// Trocar aqui quando um fornecedor retirar um modelo (404 só passa ao seguinte; não parte nada).
export const MOTORES_GRATIS: MotorGratis[] = [
  {
    nome: 'groq', url: 'https://api.groq.com/openai/v1/chat/completions', chaveEnv: 'GROQ_API_KEY',
    texto: ['openai/gpt-oss-120b', 'qwen/qwen3.8-27b', 'openai/gpt-oss-20b'], visao: [], mimesVisao: [],
    privadoOk: true, uaNavegador: true,
  },
  {
    nome: 'gemini-gratis', url: 'https://generativelanguage.googleapis.com/v1beta/openai/chat/completions',
    chaveEnv: 'GEMINI_API_KEY_FALLBACK',
    texto: ['gemini-3.1-flash-lite', 'gemini-3.5-flash-lite'], visao: ['gemini-3.1-flash-lite', 'gemini-3-flash-preview'],
    mimesVisao: ['image/jpeg', 'image/png', 'image/webp', 'image/heic'], privadoOk: false,
  },
  {
    nome: 'openrouter', url: 'https://openrouter.ai/api/v1/chat/completions', chaveEnv: 'OPENROUTER_API_KEY',
    texto: ['nvidia/nemotron-3-super-120b-a12b:free', 'minimax/minimax-m3:free'],
    visao: ['nvidia/nemotron-3-nano-omni-30b-a3b-reasoning:free', 'dots-studio/dots-3-note-preview:free', 'google/gemma-4-31b-it:free'],
    mimesVisao: ['image/jpeg', 'image/png', 'image/webp'], privadoOk: false,
  },
  {
    nome: 'kilo', url: 'https://api.kilo.ai/api/gateway/chat/completions', chaveEnv: null,
    texto: ['stepfun/step-3.7-flash:free'], visao: [], mimesVisao: [], privadoOk: false,
  },
];

const IMAGENS_CLAUDE = ['image/jpeg', 'image/png', 'image/gif', 'image/webp'];
const MAX_IMAGEM_CLAUDE = 5 * 1024 * 1024;
const TIMEOUT_GRATIS_MS = 25_000;
const PRAZO_MS = 45_000;
const UA_NAVEGADOR = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0 Safari/537.36';

/** JSON da resposta (objeto ou lista), tirando cercas ``` e texto à volta. undefined se não houver. */
export function lerJson(texto: string): unknown {
  const t = (texto ?? '').trim().replace(/^```(?:json)?\s*/i, '').replace(/\s*```\s*$/i, '').trim();
  try {
    return JSON.parse(t);
  } catch {
    // segue: procura o bloco
  }
  const iObj = t.indexOf('{');
  const iLista = t.indexOf('[');
  const lista = iLista >= 0 && (iObj < 0 || iLista < iObj);
  const a = lista ? iLista : iObj;
  const b = lista ? t.lastIndexOf(']') : t.lastIndexOf('}');
  if (a >= 0 && b > a) {
    try {
      return JSON.parse(t.slice(a, b + 1));
    } catch {
      // nada
    }
  }
  return undefined;
}

function bytesDe(b64: string): number {
  return Math.floor((b64 ?? '').length * 3 / 4);
}

/** Anexos no formato do Claude; `motivo` diz porque o Claude não os pode ver (e então passa-se à reserva). */
export function anexosParaClaude(anexos: AnexoIa[] | undefined): { blocos: BlocoClaude[]; motivo: string | null } {
  const blocos: BlocoClaude[] = [];
  for (const a of anexos ?? []) {
    const mime = (a.mime || '').toLowerCase();
    if (IMAGENS_CLAUDE.includes(mime)) {
      if (bytesDe(a.base64) > MAX_IMAGEM_CLAUDE) return { blocos: [], motivo: `imagem com mais de 5 MB (${mime})` };
      blocos.push({ type: 'image', source: { type: 'base64', media_type: mime, data: a.base64 } });
    } else if (mime === 'application/pdf') {
      blocos.push({ type: 'document', source: { type: 'base64', media_type: 'application/pdf', data: a.base64 } });
    } else {
      return { blocos: [], motivo: `formato ${mime || 'desconhecido'} nao serve ao Claude` };
    }
  }
  return { blocos, motivo: null };
}

function conversaDe(p: PedidoIa): Array<{ role: 'user' | 'assistant'; texto: string }> {
  const itens = [...(p.conversa ?? [])];
  if (p.texto && p.texto.trim()) itens.push({ role: 'user', texto: p.texto });
  return itens;
}

/** Mensagens do Claude: a conversa, com os anexos à frente do texto do último turno do utilizador. */
export function mensagensClaude(p: PedidoIa, blocos: BlocoClaude[]): MensagemClaude[] {
  const msgs = conversaParaClaude(conversaDe(p));
  if (blocos.length > 0 && msgs.length > 0) {
    const ultima = msgs[msgs.length - 1];
    if (ultima.role === 'user') {
      const texto = typeof ultima.content === 'string' ? ultima.content : '';
      ultima.content = [...blocos, { type: 'text', text: texto || 'Analisa o anexo.' }];
    }
  }
  return msgs;
}

/** Mensagens no formato OpenAI (para a reserva grátis). */
export function mensagensOpenAI(p: PedidoIa): Array<Record<string, unknown>> {
  const itens = conversaDe(p).filter((m) => (m.texto ?? '').trim().length > 0);
  const out: Array<Record<string, unknown>> = [{ role: 'system', content: p.sistema }];
  itens.forEach((m, i) => {
    const ultimoDoUtilizador = i === itens.length - 1 && m.role === 'user';
    if (ultimoDoUtilizador && (p.anexos ?? []).length > 0) {
      out.push({
        role: 'user',
        content: [
          { type: 'text', text: m.texto },
          ...(p.anexos ?? []).map((a) => ({ type: 'image_url', image_url: { url: `data:${a.mime};base64,${a.base64}` } })),
        ],
      });
    } else {
      out.push({ role: m.role, content: m.texto });
    }
  });
  return out;
}

function textoDaEscolha(j: unknown): string {
  // deno-lint-ignore no-explicit-any
  const c = (j as any)?.choices?.[0]?.message?.content;
  if (typeof c === 'string') return c.trim();
  if (Array.isArray(c)) {
    return c.map((x) => (typeof x === 'string' ? x : typeof x?.text === 'string' ? x.text : '')).join('').trim();
  }
  return '';
}

/** O livro nunca deve parecer "sem crédito do Claude" por causa de um erro da reserva. */
function erroDaReserva(motor: string, erro: string): string {
  return `reserva ${motor}: ${erro}`.replace(/credit balance/gi, 'saldo').replace(/sem credito/gi, 'sem saldo').slice(0, 400);
}

async function chamarGratis(
  m: MotorGratis, modelo: string, p: PedidoIa, chave: string | null, msPorChamada: number,
): Promise<{ texto: string; http: number | null; erro: string | null; entrada: number; saida: number }> {
  const headers: Record<string, string> = { 'Content-Type': 'application/json' };
  if (chave) headers.Authorization = `Bearer ${chave}`;
  if (m.uaNavegador) headers['User-Agent'] = UA_NAVEGADOR;
  try {
    const r = await fetch(m.url, {
      method: 'POST',
      headers,
      body: JSON.stringify({
        model: modelo,
        messages: mensagensOpenAI(p),
        max_tokens: Math.max(1024, Math.round(p.maxTokens ?? 1024)),
        temperature: 0.2,
      }),
      signal: AbortSignal.timeout(msPorChamada),
    });
    if (!r.ok) {
      const t = (await r.text().catch(() => '')).replace(/\s+/g, ' ').slice(0, 200);
      return { texto: '', http: r.status, erro: `http ${r.status}: ${t}`, entrada: 0, saida: 0 };
    }
    const j = await r.json().catch(() => null);
    const texto = textoDaEscolha(j);
    // deno-lint-ignore no-explicit-any
    const u = (j as any)?.usage ?? {};
    const entrada = Number(u.prompt_tokens) > 0 ? Math.round(Number(u.prompt_tokens)) : 0;
    const saida = Number(u.completion_tokens) > 0 ? Math.round(Number(u.completion_tokens)) : 0;
    if (!texto) return { texto: '', http: r.status, erro: 'resposta vazia', entrada, saida };
    return { texto, http: r.status, erro: null, entrada, saida };
  } catch (e) {
    const nome = (e as Error)?.name ?? '';
    const erro = nome === 'TimeoutError' || nome === 'AbortError'
      ? `timeout ${Math.round(msPorChamada / 1000)} s`
      : `fetch: ${(e as Error)?.message ?? e}`;
    return { texto: '', http: null, erro, entrada: 0, saida: 0 };
  }
}

function resumoDasTentativas(t: TentativaIa[]): string {
  if (t.length === 0) return 'nenhum motor tentado';
  return t.map((x) => `${x.motor}${x.modelo ? ` (${x.modelo})` : ''}: ${x.erro ?? (x.ok ? 'ok' : 'falhou')}`).join('; ');
}

/**
 * Claude primeiro → rotação grátis → erro claro. Nunca lança: devolve { ok:false, erro } com o que cada
 * motor respondeu, para o robô seguir o caminho de falha que já tinha (ver à mão, sombra, escalar).
 */
export async function pedirIa(p: PedidoIa): Promise<RespostaIa> {
  const t0 = Date.now();
  const prazo = Math.max(5_000, p.prazoMs ?? PRAZO_MS);
  const prioridade = p.prioridade ?? 3;
  const privado = p.privado !== false;
  const temAnexos = (p.anexos ?? []).length > 0;
  const tentativas: TentativaIa[] = [];

  // ── 1. Claude ────────────────────────────────────────────────────────────
  const anexos = anexosParaClaude(p.anexos);
  if (anexos.motivo) {
    tentativas.push({ motor: 'claude', modelo: '', ok: false, http: null, erro: anexos.motivo, ms: 0 });
  } else {
    const diagnostico = { erro: null as string | null, http: null as number | null, modelo: null as string | null };
    const tc = Date.now();
    const r = await claudePrimeiro({
      robo: p.robo,
      prioridade,
      system: p.sistema,
      messages: mensagensClaude(p, anexos.blocos),
      maxTokens: Math.max(1024, Math.round(p.maxTokens ?? 1024)),
      modelo: p.modeloClaude,
      diagnostico,
      timeoutMs: p.timeoutClaudeMs,
    });
    if (r && r.texto) {
      const json = p.json ? lerJson(r.texto) : null;
      if (!p.json || json !== undefined) {
        tentativas.push({ motor: 'claude', modelo: r.modelo, ok: true, http: 200, erro: null, ms: r.ms });
        return { ok: true, texto: r.texto, json, motor: 'claude', modelo: r.modelo, custoUsd: r.custoUsd, tentativas };
      }
      tentativas.push({ motor: 'claude', modelo: r.modelo, ok: false, http: 200, erro: 'resposta sem JSON', ms: r.ms });
    } else {
      tentativas.push({
        motor: 'claude', modelo: diagnostico.modelo ?? p.modeloClaude ?? '', ok: false, http: diagnostico.http,
        erro: r ? 'resposta sem texto' : (diagnostico.erro ?? 'nao respondeu'), ms: Date.now() - tc,
      });
    }
  }

  // ── 2. Rotação grátis ────────────────────────────────────────────────────
  for (const m of MOTORES_GRATIS) {
    const saltar = (erro: string) => tentativas.push({ motor: m.nome, modelo: '', ok: false, http: null, erro, ms: 0 });
    if (privado && !m.privadoOk) { saltar('saltado: dados privados (este motor pode treinar com o que recebe)'); continue; }
    const modelos = temAnexos ? m.visao : m.texto;
    if (modelos.length === 0) { saltar(temAnexos ? 'sem modelo de visao gratis' : 'sem modelo de texto'); continue; }
    const mimeFora = (p.anexos ?? []).find((a) => !m.mimesVisao.includes((a.mime || '').toLowerCase()));
    if (temAnexos && mimeFora) { saltar(`nao aceita ${mimeFora.mime}`); continue; }
    const chave = m.chaveEnv ? (Deno.env.get(m.chaveEnv) ?? '') : null;
    if (m.chaveEnv && !chave) { saltar(`sem a chave ${m.chaveEnv}`); continue; }

    for (const modelo of modelos) {
      const resta = prazo - (Date.now() - t0);
      if (resta < 3_000) {
        tentativas.push({ motor: m.nome, modelo, ok: false, http: null, erro: 'sem tempo (prazo do pedido)', ms: 0 });
        break;
      }
      const tm = Date.now();
      const r = await chamarGratis(m, modelo, p, chave, Math.min(TIMEOUT_GRATIS_MS, resta));
      const ms = Date.now() - tm;
      const json = p.json && r.texto ? lerJson(r.texto) : null;
      const bom = !r.erro && (!p.json || json !== undefined);
      const erro = r.erro ?? (bom ? null : 'resposta sem JSON');
      await registarGasto({
        robo: p.robo, prioridade, modelo: `${m.nome}:${modelo}`,
        uso: { input_tokens: r.entrada, output_tokens: r.saida, cache_creation_input_tokens: 0, cache_read_input_tokens: 0 },
        custo: 0, ms, ok: bom, erro: erro ? erroDaReserva(m.nome, erro) : null,
      });
      tentativas.push({ motor: m.nome, modelo, ok: bom, http: r.http, erro, ms });
      if (bom) {
        console.log(`[ia] robo=${p.robo} respondeu ${m.nome}:${modelo} (reserva gratis)`);
        return { ok: true, texto: r.texto, json, motor: m.nome, modelo, custoUsd: 0, tentativas };
      }
      if (r.http === 401 || r.http === 403) break; // chave má ou bloqueada: o resto deste motor falha igual
    }
  }

  // ── 3. Erro claro ────────────────────────────────────────────────────────
  const erro = `nenhum motor respondeu — ${resumoDasTentativas(tentativas)}`.slice(0, 1200);
  console.log(`[ia] robo=${p.robo} ${erro.slice(0, 400)}`);
  return { ok: false, erro, tentativas };
}

/** O http "mais significativo" das tentativas (para quem já decidia pelo código http). */
export function httpDasTentativas(t: TentativaIa[]): number | null {
  const comHttp = t.filter((x) => typeof x.http === 'number');
  return comHttp.length > 0 ? comHttp[comHttp.length - 1].http : null;
}

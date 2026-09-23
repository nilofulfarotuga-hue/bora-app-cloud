// decidir — O DECISOR da Bora (missão jev-decisor-2026-09-23).
//
// Uma porta única para decisões PEQUENAS e tipadas, ao estilo do Jev (TypeSafe "System One"):
//   choice = escolher uma opção · score = nota numa escala · noul = sim/não
// Devolve sempre o mesmo contrato: resposta + confiança + probabilidades + motor + latência.
//
// Motores:
//   1. Jev (POST https://api.typesafe.ai/v1/systemone, modelo jev-latest). Chave: env
//      TYPESAFE_API_KEY ou Vault `typesafe_api_key` (RPC decisor_chave_typesafe, só serviço).
//   2. Reserva: Gemini (3.5-flash-lite → 3.1-flash-lite → 3-flash-preview) com o MESMO
//      contrato — pede-lhe as probabilidades e calcula resposta/confiança igual ao Jev.
//
// Dois modos de chamada (verify_jwt = true; só service_role ou admin):
//   { acao: "varrer" }  — a tarefa agendada (30 s): preenche resultados reais, pega no que
//                         falta decidir (decisor_itens_pendentes) e decide em SOMBRA.
//   { pergunta_tipo, pergunta, estado, opcoes|escala, usado_por, contexto_id,
//     motor?: "auto"|"jev"|"gemini", gravar?: bool, modo?: "teste",
//     modelos_gemini?: string[] (diagnóstico: troca a cadeia de reserva) } — uma decisão avulsa.
//
// Nenhuma decisão aqui mexe em preços, taxas, tokens ou no despacho. A única ação em modo
// ativo é arquivar uma sugestão nova do Robot B que o decisor acha que não vale a pena.

// @ts-nocheck
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.45.0';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};

const SUPABASE_URL = Deno.env.get('SUPABASE_URL')!;
const SUPABASE_ANON_KEY = Deno.env.get('SUPABASE_ANON_KEY')!;
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
const GEMINI_API_KEY = Deno.env.get('GEMINI_API_KEY');
// Cadeia de reserva. gemini-3.1-flash-lite e gemini-3-flash-preview: os que o roteador Motor
// Bora usa (motor_chamadas, 20–23/09); gemini-3.5-flash-lite: o do support-chatbot
// (support_settings.gemini_model). A 23/09 o 3.1-flash-lite deu 503 "alta procura" em 6 das
// 8 horas do robot-b, por isso não vai à frente.
const GEMINI_MODELOS = (Deno.env.get('DECISOR_GEMINI_MODELS') ?? 'gemini-3.5-flash-lite,gemini-3.1-flash-lite,gemini-3-flash-preview')
  .split(',').map((m) => m.trim()).filter(Boolean);
const JEV_URL = 'https://api.typesafe.ai/v1/systemone';
const JEV_MODEL = 'jev-latest';
const ORCAMENTO_VARRER_MS = 40_000;

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  });
}

function decodeJwtRole(token: string): string | null {
  try {
    const p = token.split('.')[1].replace(/-/g, '+').replace(/_/g, '/');
    return JSON.parse(atob(p + '==='.slice(0, (4 - p.length % 4) % 4))).role ?? null;
  } catch {
    return null;
  }
}

// ── Contrato ────────────────────────────────────────────────────────────────
type Tipo = 'choice' | 'score' | 'noul';
interface Pedido {
  tipo: Tipo;
  pergunta: string;
  estado: unknown;
  opcoes?: string[] | Record<string, string | null>;   // choice
  escala?: string[];                                   // score (níveis por ordem)
  criterios_noul?: { true?: string; false?: string };  // noul (opcional)
}
interface Resultado {
  resposta: string;
  confianca: number;
  probabilidades: Record<string, number>;
  motor: 'jev' | 'gemini' | 'nenhum';
  modelo: string | null;
  latencia_ms: number;
  tokens_entrada: number | null;
  tokens_saida: number | null;
  erro?: string | null;
}

const r4 = (x: number) => Math.round(x * 10000) / 10000;

// Confiança = 1 − entropia normalizada (1 = certeza total, 0 = tudo igual).
function confiancaDe(probs: number[]): number {
  const n = probs.length;
  if (n < 2) return 1;
  let h = 0;
  for (const p of probs) if (p > 0) h -= p * Math.log(p);
  return r4(Math.max(0, 1 - h / Math.log(n)));
}

function normalizar(probs: Record<string, number>, chaves: string[]): Record<string, number> {
  const out: Record<string, number> = {};
  let soma = 0;
  for (const k of chaves) {
    const v = Number(probs?.[k]);
    out[k] = Number.isFinite(v) && v > 0 ? v : 0;
    soma += out[k];
  }
  if (soma <= 0) throw new Error('probabilidades vazias');
  for (const k of chaves) out[k] = r4(out[k] / soma);
  return out;
}

function opcoesMapa(p: Pedido): Record<string, string | null> {
  if (Array.isArray(p.opcoes)) return Object.fromEntries(p.opcoes.map((o) => [String(o), null]));
  return (p.opcoes ?? {}) as Record<string, string | null>;
}

// Do mapa de probabilidades para a resposta final — igual para os dois motores.
function fechar(p: Pedido, probs: Record<string, number>): { resposta: string; probabilidades: Record<string, number>; confianca: number } {
  if (p.tipo === 'choice') {
    const chaves = Object.keys(opcoesMapa(p));
    const pr = normalizar(probs, chaves);
    const melhor = chaves.reduce((a, b) => (pr[b] > pr[a] ? b : a));
    return { resposta: melhor, probabilidades: pr, confianca: confiancaDe(Object.values(pr)) };
  }
  if (p.tipo === 'score') {
    const chaves = (p.escala ?? []).map((_, i) => String(i));
    const pr = normalizar(probs, chaves);
    const nota = chaves.reduce((s, k) => s + Number(k) * pr[k], 0);
    return { resposta: String(Math.round(nota * 100) / 100), probabilidades: pr, confianca: confiancaDe(Object.values(pr)) };
  }
  const sim = Math.min(1, Math.max(0, Number(probs.sim)));
  if (!Number.isFinite(sim)) throw new Error('noul sem probabilidade');
  const pr = { sim: r4(sim), nao: r4(1 - sim) };
  return { resposta: sim >= 0.5 ? 'sim' : 'nao', probabilidades: pr, confianca: confiancaDe([sim, 1 - sim]) };
}

// ── Motor 1: Jev ────────────────────────────────────────────────────────────
async function chaveJev(admin: any): Promise<string | null> {
  const env = Deno.env.get('TYPESAFE_API_KEY');
  if (env) return env;
  const { data, error } = await admin.rpc('decisor_chave_typesafe');
  if (error) console.log('decisor_chave_typesafe erro:', error.message);
  return data || null;
}

async function viaJev(p: Pedido, chave: string): Promise<Resultado> {
  const q: Record<string, unknown> = { type: p.tipo, instructions: p.pergunta };
  if (p.tipo === 'choice') q.criteria = opcoesMapa(p);
  if (p.tipo === 'score') q.criteria = p.escala;
  if (p.tipo === 'noul' && p.criterios_noul) q.criteria = p.criterios_noul;
  const t0 = Date.now();
  const resp = await fetch(JEV_URL, {
    method: 'POST',
    headers: { Authorization: `Bearer ${chave}`, 'Content-Type': 'application/json' },
    body: JSON.stringify({ state: p.estado, model: JEV_MODEL, questions: { d: q } }),
    signal: AbortSignal.timeout(8000),
  });
  const latencia = Date.now() - t0;
  if (!resp.ok) throw new Error(`jev http ${resp.status}: ${(await resp.text()).slice(0, 200)}`);
  const j = await resp.json();
  const a = j?.answers?.d;
  if (!a) throw new Error('jev sem answers.d');
  let probs: Record<string, number>;
  if (p.tipo === 'noul') probs = { sim: Number(a.noul) };
  else probs = a.probabilities ?? {};
  const f = fechar(p, probs);
  // Se o Jev devolver a sua própria confiança (choice/score), é essa que vale.
  if (typeof a.confidence === 'number') f.confianca = r4(a.confidence);
  if (p.tipo === 'choice' && typeof a.choice === 'string') f.resposta = a.choice;
  if (p.tipo === 'score' && typeof a.score === 'number') f.resposta = String(Math.round(a.score * 100) / 100);
  return {
    ...f, motor: 'jev', modelo: j.model ?? JEV_MODEL, latencia_ms: latencia,
    tokens_entrada: j?.usage?.input_tokens ?? null, tokens_saida: j?.usage?.output_tokens ?? null,
  };
}

// ── Motor 2: Gemini com o mesmo contrato ────────────────────────────────────
const SISTEMA_GEMINI =
  'You are a calibrated decision function (like a "System One" classifier). You never chat. ' +
  'Read the STATE and the QUESTION and return ONLY a JSON object with the probability of each ' +
  'allowed answer. Probabilities must be honest and calibrated (they sum to 1). No explanations.';

async function viaGemini(p: Pedido, modelos: string[] = GEMINI_MODELOS): Promise<Resultado> {
  if (!GEMINI_API_KEY) throw new Error('gemini_key_missing');
  const erros: string[] = [];
  for (const modelo of modelos) {
    for (let tentativa = 0; tentativa < 2; tentativa++) {
      try {
        return await viaGeminiModelo(p, modelo);
      } catch (e) {
        const msg = (e as Error).message;
        erros.push(`${modelo}: ${msg.slice(0, 80)}`);
        // Só vale repetir quando o Google diz que está cheio; resto passa ao próximo modelo.
        if (!/http (429|503)/.test(msg)) break;
        await new Promise((r) => setTimeout(r, 600 * (tentativa + 1)));
      }
    }
  }
  throw new Error(erros.join(' | '));
}

async function viaGeminiModelo(p: Pedido, modelo: string): Promise<Resultado> {
  let formato: string;
  if (p.tipo === 'choice') {
    const m = opcoesMapa(p);
    formato = 'Allowed options (key: description):\n' +
      Object.entries(m).map(([k, v]) => `- ${k}${v ? `: ${typeof v === 'string' ? v : JSON.stringify(v)}` : ''}`).join('\n') +
      '\nReturn {"probabilities": {"<option key>": <0..1>, ...}} with EVERY option key.';
  } else if (p.tipo === 'score') {
    formato = 'Levels (index: description):\n' + (p.escala ?? []).map((d, i) => `- ${i}: ${d}`).join('\n') +
      '\nReturn {"probabilities": {"0": <0..1>, "1": <0..1>, ...}} with EVERY level index.';
  } else {
    const c = p.criterios_noul ?? {};
    formato = `Yes means: ${c.true ?? 'yes'}. No means: ${c.false ?? 'no'}.\n` +
      'Return {"yes": <probability 0..1 that the answer is yes>}.';
  }
  const texto = `STATE:\n${typeof p.estado === 'string' ? p.estado : JSON.stringify(p.estado)}\n\nQUESTION: ${p.pergunta}\n\n${formato}`;
  // Uma decisão de "System One" não precisa de raciocínio longo: a 23/09 o 3.5-flash-lite
  // levou 19,6 s a pensar num sim/não. thinkingLevel "minimal" corta isso; se o modelo não
  // aceitar o campo (400), repete-se uma vez sem ele.
  const pedir = (comThinking: boolean) => fetch(`https://generativelanguage.googleapis.com/v1beta/models/${modelo}:generateContent`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', 'x-goog-api-key': GEMINI_API_KEY },
    body: JSON.stringify({
      system_instruction: { parts: [{ text: SISTEMA_GEMINI }] },
      contents: [{ role: 'user', parts: [{ text: texto }] }],
      // 2048: se ainda pensar um pouco, sobra orçamento para o JSON.
      generationConfig: {
        temperature: 0, maxOutputTokens: 2048, responseMimeType: 'application/json',
        ...(comThinking ? { thinkingConfig: { thinkingLevel: 'minimal' } } : {}),
      },
    }),
    signal: AbortSignal.timeout(20000),
  });
  const t0 = Date.now();
  let resp = await pedir(true);
  if (resp.status === 400) {
    const txt = await resp.text();
    if (!/thinking/i.test(txt)) throw new Error(`gemini http 400: ${txt.slice(0, 200)}`);
    resp = await pedir(false);
  }
  const latencia = Date.now() - t0;
  if (!resp.ok) throw new Error(`gemini http ${resp.status}: ${(await resp.text()).slice(0, 200)}`);
  const j = await resp.json();
  let raw = (j?.candidates?.[0]?.content?.parts ?? []).map((x: any) => x.text ?? '').join('').trim();
  raw = raw.replace(/^```(?:json)?\s*/i, '').replace(/```\s*$/i, '').trim();
  const o = JSON.parse(raw);
  const probs = p.tipo === 'noul' ? { sim: Number(o.yes ?? o.sim) } : (o.probabilities ?? o);
  const f = fechar(p, probs);
  return {
    ...f, motor: 'gemini', modelo, latencia_ms: latencia,
    tokens_entrada: j?.usageMetadata?.promptTokenCount ?? null,
    tokens_saida: j?.usageMetadata?.candidatesTokenCount ?? null,
  };
}

// ── Orquestração: Jev primeiro, Gemini de reserva ───────────────────────────
async function decidir(admin: any, p: Pedido, motor: 'auto' | 'jev' | 'gemini' = 'auto',
    modelosGemini?: string[]): Promise<Resultado> {
  let erroJev: string | null = null;
  if (motor !== 'gemini') {
    const chave = await chaveJev(admin);
    if (chave) {
      try {
        return await viaJev(p, chave);
      } catch (e) {
        erroJev = (e as Error).message;
        console.log('jev falhou, reserva gemini:', erroJev);
      }
    } else {
      erroJev = 'jev_sem_chave';
    }
    if (motor === 'jev') {
      return { resposta: '', confianca: 0, probabilidades: {}, motor: 'nenhum', modelo: null, latencia_ms: 0,
        tokens_entrada: null, tokens_saida: null, erro: erroJev };
    }
  }
  try {
    const r = await viaGemini(p, modelosGemini?.length ? modelosGemini : GEMINI_MODELOS);
    return { ...r, erro: erroJev };
  } catch (e) {
    const erro = [erroJev, (e as Error).message].filter(Boolean).join(' | ');
    return { resposta: '', confianca: 0, probabilidades: {}, motor: 'nenhum', modelo: null, latencia_ms: 0,
      tokens_entrada: null, tokens_saida: null, erro };
  }
}

async function precos(admin: any): Promise<{ jev: number; gemini: number }> {
  const { data } = await admin.from('platform_settings').select('key, value')
    .in('key', ['decisor_preco_jev_usd_mtok', 'decisor_preco_gemini_usd_mtok']);
  const m = Object.fromEntries((data ?? []).map((r: any) => [r.key, Number(r.value)]));
  return { jev: m.decisor_preco_jev_usd_mtok ?? 0.042, gemini: m.decisor_preco_gemini_usd_mtok ?? 0 };
}

function custo(r: Resultado, pr: { jev: number; gemini: number }): number | null {
  if (r.motor === 'jev') return r.tokens_entrada == null ? null : (r.tokens_entrada * pr.jev) / 1e6; // saída grátis
  if (r.motor === 'gemini') return ((r.tokens_entrada ?? 0) + (r.tokens_saida ?? 0)) * pr.gemini / 1e6;
  return 0;
}

async function gravar(admin: any, p: Pedido, r: Resultado, meta: {
  usado_por: string; contexto_id: string | null; modo: string; mapa_opcoes?: unknown; acao_tomada?: string | null;
}, pr: { jev: number; gemini: number }): Promise<string | null> {
  const estadoTxt = typeof p.estado === 'string' ? p.estado : JSON.stringify(p.estado);
  const { data, error } = await admin.from('decisoes').insert({
    tipo: p.tipo, pergunta: p.pergunta, estado_resumo: estadoTxt.slice(0, 1500),
    resposta: r.resposta || null, confianca: r.motor === 'nenhum' ? null : r.confianca,
    probabilidades: r.probabilidades, motor: r.motor, modelo: r.modelo, latencia_ms: r.latencia_ms,
    tokens_entrada: r.tokens_entrada, tokens_saida: r.tokens_saida, custo_usd: custo(r, pr),
    usado_por: meta.usado_por, contexto_id: meta.contexto_id, modo: meta.modo,
    mapa_opcoes: meta.mapa_opcoes ?? null, acao_tomada: meta.acao_tomada ?? null, erro: r.erro ?? null,
  }).select('id').single();
  if (error) {
    if (error.code === '23505') return null; // já decidido por uma varredura sobreposta
    console.log('insert decisoes erro:', error.message);
    return null;
  }
  return data.id;
}

// ── Varredura (tarefa agendada) ─────────────────────────────────────────────
async function varrer(admin: any) {
  const t0 = Date.now();
  const { data: preenchidos, error: ePre } = await admin.rpc('decisor_preencher_resultados');
  if (ePre) console.log('decisor_preencher_resultados erro:', ePre.message);
  const { data: itens, error } = await admin.rpc('decisor_itens_pendentes', { p_limite: 20 });
  if (error) return { ok: false, erro: error.message };
  const pr = await precos(admin);
  let limiar = 0.25;
  {
    const { data } = await admin.from('platform_settings').select('value').eq('key', 'decisor_robotb_limiar').maybeSingle();
    if (data && Number.isFinite(Number(data.value))) limiar = Number(data.value);
  }
  const feitos: any[] = [];
  for (const it of itens ?? []) {
    if (Date.now() - t0 > ORCAMENTO_VARRER_MS) break;
    const p: Pedido = { tipo: it.tipo, pergunta: it.pergunta, estado: it.estado };
    if (it.tipo === 'choice') p.opcoes = it.opcoes;
    if (it.tipo === 'score') p.escala = it.opcoes;
    if (it.tipo === 'noul' && it.opcoes) p.criterios_noul = it.opcoes;
    const r = await decidir(admin, p);
    let acao: string | null = null;
    // Única ação real: Robot B em modo ativo arquiva a sugestão nova que não vale a pena.
    if (it.usado_por === 'robotb' && it.modo === 'ativo' && r.motor !== 'nenhum' && r.probabilidades.sim < limiar) {
      const { data: upd, error: eUpd } = await admin.from('robot_suggestions')
        .update({ status: 'rejeitada', motivo_rejeicao: `Decisor: não vale a pena abrir (sim=${r.probabilidades.sim}, limiar=${limiar})`, reviewed_at: new Date().toISOString() })
        .eq('id', it.contexto_id).eq('status', 'nova').select('id');
      acao = eUpd ? `erro ao arquivar: ${eUpd.message}` : (upd?.length ? 'sugestao_arquivada' : 'sugestao_ja_mexida');
    }
    const id = await gravar(admin, p, r, {
      usado_por: it.usado_por, contexto_id: it.contexto_id, modo: it.modo === 'ativo' ? 'ativo' : 'sombra',
      mapa_opcoes: it.mapa_opcoes, acao_tomada: acao,
    }, pr);
    feitos.push({ usado_por: it.usado_por, contexto_id: it.contexto_id, motor: r.motor, resposta: r.resposta, id, acao, erro: r.erro ?? null });
  }
  return { ok: true, resultados_preenchidos: preenchidos ?? 0, pendentes: (itens ?? []).length, decididos: feitos, ms: Date.now() - t0 };
}

// ── HTTP ────────────────────────────────────────────────────────────────────
Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders });
  if (req.method !== 'POST') return json({ error: 'method_not_allowed' }, 405);

  const token = (req.headers.get('Authorization') ?? '').replace(/^Bearer\s+/i, '');
  const admin = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, { auth: { persistSession: false } });
  const isService = token === SUPABASE_SERVICE_ROLE_KEY || decodeJwtRole(token) === 'service_role';
  if (!isService) {
    const user = createClient(SUPABASE_URL, SUPABASE_ANON_KEY, {
      global: { headers: { Authorization: `Bearer ${token}` } }, auth: { persistSession: false },
    });
    const { data: ok } = await user.rpc('is_admin');
    if (ok !== true) return json({ error: 'forbidden' }, 403);
  }

  let body: any;
  try {
    body = await req.json();
  } catch {
    return json({ error: 'json_invalido' }, 400);
  }

  if (body?.acao === 'varrer') {
    if (!isService) return json({ error: 'so_servico' }, 403);
    return json(await varrer(admin));
  }

  const tipo = body?.pergunta_tipo;
  if (!['choice', 'score', 'noul'].includes(tipo)) return json({ error: 'pergunta_tipo deve ser choice|score|noul' }, 400);
  if (!body.pergunta || body.estado == null || !body.usado_por) {
    return json({ error: 'faltam campos: pergunta, estado, usado_por' }, 400);
  }
  const p: Pedido = { tipo, pergunta: String(body.pergunta), estado: body.estado };
  if (tipo === 'choice') {
    const n = Array.isArray(body.opcoes) ? body.opcoes.length : Object.keys(body.opcoes ?? {}).length;
    if (n < 2 || n > 255) return json({ error: 'choice precisa de 2 a 255 opcoes' }, 400);
    p.opcoes = body.opcoes;
  }
  if (tipo === 'score') {
    if (!Array.isArray(body.escala) || body.escala.length < 2 || body.escala.length > 10) {
      return json({ error: 'score precisa de escala com 2 a 10 niveis' }, 400);
    }
    p.escala = body.escala;
  }
  if (tipo === 'noul' && body.criterios) p.criterios_noul = body.criterios;

  const motor = ['jev', 'gemini'].includes(body.motor) ? body.motor : 'auto';
  const modelos = Array.isArray(body.modelos_gemini)
    ? body.modelos_gemini.map(String).filter((m: string) => /^gemini-[a-z0-9.\-]+$/.test(m)).slice(0, 4)
    : undefined;
  const r = await decidir(admin, p, motor, modelos);
  let decisao_id: string | null = null;
  if (body.gravar !== false) {
    decisao_id = await gravar(admin, p, r, {
      usado_por: String(body.usado_por), contexto_id: body.contexto_id ? String(body.contexto_id) : null,
      modo: body.modo === 'teste' ? 'teste' : 'sombra',
    }, await precos(admin));
  }
  return json({ tipo, ...r, decisao_id });
});

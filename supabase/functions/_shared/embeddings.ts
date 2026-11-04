// _shared/embeddings.ts — os vetores da "pesquisa por significado", sempre com reserva.
// Missão embeddings-supabase-2026-11-03 (03/11/2026). Ordem do Danilo: o motor grátis do próprio
// Supabase e o Gemini de reserva, nunca sem reserva; se os dois falharem a pesquisa segue por texto.
//
// Dois motores, dois tamanhos de vetor (não se misturam):
//   • gte      — gte-small dentro da Edge Function (Supabase.ai.Session), 384 números, grátis.
//   • gemini   — gemini-embedding-001 pela API da Google, 768 números (chave GEMINI_API_KEY).
// As funções SQL (assistant_search_products, match_knowledge) veem o tamanho do vetor e escolhem a
// coluna certa: 384 → product_embeddings_gte / embedding_gte, 768 → as colunas antigas.
//
// A ordem vem de platform_settings, por assunto:
//   embeddings_motor_primario_produtos / embeddings_motor_primario_ajuda  ('gte' | 'gemini')
//   embeddings_gte_timeout_ms                                             (prazo do gte)
//   embeddings_gte_max_por_pedido                                         (cálculos gte por pedido)
//   embeddings_teste_falha  {"modo":"gte"|"gemini"|"todos","ate":"<ISO>"} (só para provar a reserva;
//                            ignorado depois de "ate" e se "ate" estiver a mais de 30 min)

// deno-lint-ignore no-explicit-any
type Json = any;

export type Motor = 'gte' | 'gemini';
export type Assunto = 'produtos' | 'ajuda';
export const DIM: Record<Motor, number> = { gte: 384, gemini: 768 };

const GEMINI_URL = 'https://generativelanguage.googleapis.com/v1beta/models/gemini-embedding-001';

export type Tentativa = { motor: Motor; ok: boolean; ms: number; cache?: boolean; erro?: string };
export type ResultadoVetor = { motor: Motor | null; vetor: number[] | null; ms: number; tentativas: Tentativa[] };

export type ConfigEmbeddings = {
  ordem: Motor[];
  timeoutGteMs: number;
  timeoutGeminiMs: number;
  falhaForcada: 'gte' | 'gemini' | 'todos' | null;
  // O gte corre no PROCESSADOR da própria função (~115 ms por texto, medido 03/11) e a Edge
  // Function morre acima de ~2 s de processador por pedido. Cada pedido tem um orçamento de
  // cálculos gte (a cache não conta); esgotado, passa ao motor seguinte. O objeto é partilhado
  // pelas configs do mesmo pedido (produtos e ajuda) — ver lerConfigEmbeddings(…, orcamento).
  orcamento: { gte: number };
  // Semelhança mínima de um trecho do manual quando o vetor é gte (o Gemini usa a de cada função).
  gteAjudaMinSim: number;
};

// ─── gte-small (dentro da função) ───────────────────────────────────────────
let sessaoGte: Json = null;

function abrirSessaoGte(): Json {
  if (sessaoGte) return sessaoGte;
  const ai = (globalThis as Json).Supabase?.ai;
  if (!ai?.Session) throw new Error('Supabase.ai indisponível neste runtime');
  sessaoGte = new ai.Session('gte-small');
  return sessaoGte;
}

function comPrazo<T>(p: Promise<T>, ms: number, motivo: string): Promise<T> {
  let tid: ReturnType<typeof setTimeout> | undefined;
  const prazo = new Promise<never>((_, rej) => {
    tid = setTimeout(() => rej(new Error(motivo)), ms);
  });
  return Promise.race([p, prazo]).finally(() => clearTimeout(tid));
}

function validar(v: unknown, dim: number, motor: Motor): number[] {
  const arr = Array.from((v ?? []) as ArrayLike<number>).map(Number);
  if (arr.length !== dim) throw new Error(`${motor}: vetor com ${arr.length} números (esperava ${dim})`);
  if (arr.some((x) => !Number.isFinite(x))) throw new Error(`${motor}: vetor com números inválidos`);
  return arr;
}

export async function vetorGte(texto: string, timeoutMs = 1500): Promise<number[]> {
  const sessao = abrirSessaoGte();
  const out = await comPrazo(
    Promise.resolve(sessao.run(texto, { mean_pool: true, normalize: true })),
    timeoutMs,
    `gte: passou o prazo de ${timeoutMs} ms`,
  );
  return validar(out, DIM.gte, 'gte');
}

// ─── Gemini (API da Google) ─────────────────────────────────────────────────
export async function vetorGemini(
  texto: string,
  chave: string | null | undefined,
  timeoutMs = 2500,
  taskType: 'RETRIEVAL_QUERY' | 'RETRIEVAL_DOCUMENT' = 'RETRIEVAL_QUERY',
): Promise<number[]> {
  if (!chave) throw new Error('gemini: sem chave');
  const ctrl = new AbortController();
  const tid = setTimeout(() => ctrl.abort(), timeoutMs);
  try {
    const r = await fetch(`${GEMINI_URL}:embedContent`, {
      method: 'POST',
      signal: ctrl.signal,
      headers: { 'Content-Type': 'application/json', 'x-goog-api-key': chave },
      body: JSON.stringify({ content: { parts: [{ text: texto }] }, outputDimensionality: DIM.gemini, taskType }),
    });
    if (!r.ok) throw new Error(`gemini: http ${r.status} ${(await r.text()).slice(0, 160)}`);
    const j = await r.json();
    return validar(j?.embedding?.values, DIM.gemini, 'gemini');
  } catch (e) {
    const m = (e as Error).name === 'AbortError' ? `gemini: passou o prazo de ${timeoutMs} ms` : (e as Error).message;
    throw new Error(m);
  } finally {
    clearTimeout(tid);
  }
}

/** Até 100 textos por pedido (batchEmbedContents). Para preencher catálogo, não para perguntas. */
export async function vetoresGeminiLote(
  textos: string[],
  chave: string | null | undefined,
  taskType: 'RETRIEVAL_QUERY' | 'RETRIEVAL_DOCUMENT' = 'RETRIEVAL_DOCUMENT',
  timeoutMs = 30000,
): Promise<number[][]> {
  if (!chave) throw new Error('gemini: sem chave');
  if (textos.length === 0) return [];
  const ctrl = new AbortController();
  const tid = setTimeout(() => ctrl.abort(), timeoutMs);
  try {
    const r = await fetch(`${GEMINI_URL}:batchEmbedContents`, {
      method: 'POST',
      signal: ctrl.signal,
      headers: { 'Content-Type': 'application/json', 'x-goog-api-key': chave },
      body: JSON.stringify({
        requests: textos.map((t) => ({
          model: 'models/gemini-embedding-001',
          content: { parts: [{ text: t }] },
          taskType,
          outputDimensionality: DIM.gemini,
        })),
      }),
    });
    if (!r.ok) throw new Error(`gemini lote: http ${r.status} ${(await r.text()).slice(0, 160)}`);
    const j = await r.json();
    const emb = (j?.embeddings ?? []) as Json[];
    if (emb.length !== textos.length) throw new Error(`gemini lote: ${emb.length} de ${textos.length}`);
    return emb.map((e) => validar(e?.values, DIM.gemini, 'gemini'));
  } finally {
    clearTimeout(tid);
  }
}

// ─── Configuração (platform_settings, guardada 60 s por instância) ─────────
let cfgCache: { em: number; valores: Record<string, Json> } | null = null;

function textoDe(v: Json): string {
  if (v === null || v === undefined) return '';
  return typeof v === 'string' ? v : JSON.stringify(v);
}

function lerFalha(v: Json): ConfigEmbeddings['falhaForcada'] {
  try {
    const o = typeof v === 'string' ? JSON.parse(v) : v;
    if (!o || typeof o !== 'object') return null;
    const ate = Date.parse(String(o.ate ?? ''));
    const agora = Date.now();
    if (!Number.isFinite(ate) || ate <= agora || ate > agora + 30 * 60_000) return null;
    return o.modo === 'gte' || o.modo === 'gemini' || o.modo === 'todos' ? o.modo : null;
  } catch {
    return null;
  }
}

export async function lerConfigEmbeddings(
  admin: Json,
  assunto: Assunto,
  orcamento?: { gte: number },
): Promise<ConfigEmbeddings> {
  if (!cfgCache || Date.now() - cfgCache.em > 60_000) {
    const valores: Record<string, Json> = {};
    try {
      const { data } = await admin
        .from('platform_settings')
        .select('key, value')
        .in('key', [
          'embeddings_motor_primario_produtos',
          'embeddings_motor_primario_ajuda',
          'embeddings_gte_timeout_ms',
          'embeddings_gte_max_por_pedido',
          'embeddings_gte_ajuda_min_sim',
          'embeddings_teste_falha',
        ]);
      for (const r of (data ?? []) as Json[]) valores[r.key] = r.value;
    } catch (e) {
      console.warn('[EMB] config:', (e as Error).message);
    }
    cfgCache = { em: Date.now(), valores };
  }
  const v = cfgCache.valores;
  // O teste de falha não se guarda em cache: tem de valer logo e acabar logo.
  let falha: ConfigEmbeddings['falhaForcada'] = null;
  try {
    const { data } = await admin.from('platform_settings').select('value').eq('key', 'embeddings_teste_falha').maybeSingle();
    falha = lerFalha(data?.value);
  } catch {
    falha = lerFalha(v['embeddings_teste_falha']);
  }
  const primario = textoDe(v[`embeddings_motor_primario_${assunto}`]).replace(/"/g, '') === 'gte' ? 'gte' : 'gemini';
  const t = Number(textoDe(v['embeddings_gte_timeout_ms']).replace(/"/g, ''));
  const m = Number(textoDe(v['embeddings_gte_max_por_pedido']).replace(/"/g, ''));
  const s = Number(textoDe(v['embeddings_gte_ajuda_min_sim']).replace(/"/g, ''));
  return {
    ordem: primario === 'gte' ? ['gte', 'gemini'] : ['gemini', 'gte'],
    timeoutGteMs: Number.isFinite(t) && t >= 200 && t <= 10000 ? t : 1500,
    timeoutGeminiMs: 2500,
    falhaForcada: falha,
    orcamento: orcamento ?? { gte: Number.isFinite(m) && m >= 0 && m <= 12 ? Math.round(m) : 6 },
    gteAjudaMinSim: Number.isFinite(s) && s > 0 && s < 1 ? s : 0.8,
  };
}

export function motorBloqueado(cfg: ConfigEmbeddings, motor: Motor): boolean {
  return cfg.falhaForcada === 'todos' || cfg.falhaForcada === motor;
}

const SEM_ORCAMENTO = 'gte: orçamento de processador deste pedido esgotado';

/** Só o motor, sem cache: tenta pela ordem, devolve o primeiro que der. */
export async function vetorComReserva(
  texto: string,
  cfg: ConfigEmbeddings,
  chaveGemini: string | null | undefined,
): Promise<ResultadoVetor> {
  const t0 = Date.now();
  const tentativas: Tentativa[] = [];
  for (const motor of cfg.ordem) {
    const ti = Date.now();
    if (motorBloqueado(cfg, motor)) {
      tentativas.push({ motor, ok: false, ms: 0, erro: 'falha forçada (teste da reserva)' });
      continue;
    }
    if (motor === 'gte' && cfg.orcamento.gte <= 0) {
      tentativas.push({ motor, ok: false, ms: 0, erro: SEM_ORCAMENTO });
      continue;
    }
    try {
      if (motor === 'gte') cfg.orcamento.gte--;
      const vetor = motor === 'gte'
        ? await vetorGte(texto, cfg.timeoutGteMs)
        : await vetorGemini(texto, chaveGemini, cfg.timeoutGeminiMs);
      tentativas.push({ motor, ok: true, ms: Date.now() - ti });
      return { motor, vetor, ms: Date.now() - t0, tentativas };
    } catch (e) {
      tentativas.push({ motor, ok: false, ms: Date.now() - ti, erro: (e as Error).message.slice(0, 200) });
    }
  }
  return { motor: null, vetor: null, ms: Date.now() - t0, tentativas };
}

function lerVetor(raw: Json, dim: number): number[] | null {
  try {
    const arr = typeof raw === 'string' ? JSON.parse(raw) : raw;
    return Array.isArray(arr) && arr.length === dim ? (arr as number[]) : null;
  } catch {
    return null;
  }
}

/**
 * O vetor de uma pergunta de cliente, com cache em cada motor:
 *   gte    → embedding_cache_gte (scope, query_hash)
 *   gemini → a cache antiga de cada função (assistant_embedding_cache / support_embedding_cache)
 * Um motor bloqueado pelo teste de falha salta também a sua cache (senão a cache escondia a falha).
 */
export async function vetorDaPergunta(admin: Json, p: {
  scope: 'assistant' | 'support';
  hash: string;
  textoCache: string;
  textoVetor: string;
  tabelaGemini: 'assistant_embedding_cache' | 'support_embedding_cache';
  cfg: ConfigEmbeddings;
  chaveGemini: string | null | undefined;
}): Promise<ResultadoVetor> {
  const t0 = Date.now();
  const tentativas: Tentativa[] = [];
  for (const motor of p.cfg.ordem) {
    const ti = Date.now();
    if (motorBloqueado(p.cfg, motor)) {
      tentativas.push({ motor, ok: false, ms: 0, erro: 'falha forçada (teste da reserva)' });
      continue;
    }
    // 1) cache deste motor
    try {
      if (p.hash) {
        const q = motor === 'gte'
          ? admin.from('embedding_cache_gte').select('embedding, hit_count').eq('scope', p.scope).eq('query_hash', p.hash)
          : admin.from(p.tabelaGemini).select('embedding, hit_count').eq('query_hash', p.hash);
        const { data: c } = await q.maybeSingle();
        const v = c?.embedding ? lerVetor(c.embedding, DIM[motor]) : null;
        if (v) {
          const upd = { last_used_at: new Date().toISOString(), hit_count: (c.hit_count ?? 0) + 1 };
          (motor === 'gte'
            ? admin.from('embedding_cache_gte').update(upd).eq('scope', p.scope).eq('query_hash', p.hash)
            : admin.from(p.tabelaGemini).update(upd).eq('query_hash', p.hash)).then(() => {});
          tentativas.push({ motor, ok: true, ms: Date.now() - ti, cache: true });
          return { motor, vetor: v, ms: Date.now() - t0, tentativas };
        }
      }
    } catch (e) {
      console.warn(`[EMB] cache ${motor}:`, (e as Error).message);
    }
    // 2) o motor
    if (motor === 'gte' && p.cfg.orcamento.gte <= 0) {
      tentativas.push({ motor, ok: false, ms: Date.now() - ti, erro: SEM_ORCAMENTO });
      continue;
    }
    try {
      if (motor === 'gte') p.cfg.orcamento.gte--;
      const vetor = motor === 'gte'
        ? await vetorGte(p.textoVetor, p.cfg.timeoutGteMs)
        : await vetorGemini(p.textoVetor, p.chaveGemini, p.cfg.timeoutGeminiMs);
      if (p.hash) {
        const lit = `[${vetor.join(',')}]`;
        (motor === 'gte'
          ? admin.from('embedding_cache_gte').upsert(
            { scope: p.scope, query_hash: p.hash, query_text: p.textoCache, embedding: lit },
            { onConflict: 'scope,query_hash', ignoreDuplicates: true },
          )
          : admin.from(p.tabelaGemini).upsert(
            { query_hash: p.hash, query_text: p.textoCache, embedding: lit },
            { onConflict: 'query_hash', ignoreDuplicates: true },
          )).then(() => {});
      }
      tentativas.push({ motor, ok: true, ms: Date.now() - ti });
      return { motor, vetor, ms: Date.now() - t0, tentativas };
    } catch (e) {
      tentativas.push({ motor, ok: false, ms: Date.now() - ti, erro: (e as Error).message.slice(0, 200) });
    }
  }
  return { motor: null, vetor: null, ms: Date.now() - t0, tentativas };
}

export function resumoTentativas(r: ResultadoVetor): string {
  return r.tentativas.map((t) => `${t.motor}:${t.ok ? (t.cache ? 'cache' : 'ok') : 'falhou'}${t.ms ? `(${t.ms}ms)` : ''}`).join(' > ') || 'nenhum';
}

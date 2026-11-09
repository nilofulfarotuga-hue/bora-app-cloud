// embeddings-gte — o motor grátis de vetores do Supabase (gte-small) e o seu preenchimento.
// Missão embeddings-supabase-2026-11-03 (03/11/2026). verify_jwt: true, e por dentro só o servidor
// (banco/cron/outra função com a chave secreta) ou um admin.
//
// Ações (POST JSON { acao, ... }):
//   ping                  → { pong: true } (vigia das chaves)
//   embed                 → { textos[], motor?: 'gte'|'gemini'|'cascata', assunto?, falha_forcada?, devolver_vetor? }
//                           prova o motor e a reserva sem tocar nas tabelas
//   preencher_produtos    → { lote?, prazo_ms?, depois?, antes? } gte dos produtos que faltam (retoma sozinho)
//   preencher_manual      → { lote?, prazo_ms? } gte dos trechos do manual que faltam
//   gemini_novos          → { limite?, dias? } produtos novos também no Gemini (a reserva)
//   gemini_atrasados      → { limite? ≤ 800 } produtos de qualquer idade ainda sem Gemini (m11, 09/11)
//   manter                → o que o cron chama (de 2 em 2 min): gte dos produtos e do manual que faltam
//                           (com { gemini: true } faz também o Gemini dos novos; esse tem cron horário)
//   avaliar_vetores       → { ids[] } prova de qualidade: guarda o vetor de cada pergunta nos dois motores
//                           (as corridas — pesquisa real, motor contra motor, manual — fazem-se em SQL)
//   avaliar_pool_gemini   → { lote?, prazo_ms? } vetores Gemini do conjunto da prova (régua, tabela de prova)

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.45.0';
import { secretKey } from '../_shared/keys.ts';
import { exigirServidorOuAdmin, respostaAoPing } from '../_shared/chaves.ts';
import {
  type ConfigEmbeddings,
  DIM,
  lerConfigEmbeddings,
  type Motor,
  resumoTentativas,
  vetorComReserva,
  vetoresGeminiLote,
  vetorGemini,
  vetorGte,
} from '../_shared/embeddings.ts';

// deno-lint-ignore no-explicit-any
type Json = any;

const cors = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};

const SUPABASE_URL = Deno.env.get('SUPABASE_URL')!;
// A chave vem dos segredos da função (nunca escrita no código).
const CHAVE_GEMINI: string | null = Deno.env.get('GEMINI_API_KEY') ?? null;

function resposta(o: Json, status = 200): Response {
  return new Response(JSON.stringify(o), { status, headers: { ...cors, 'Content-Type': 'application/json' } });
}

const lit = (v: number[]) => `[${v.join(',')}]`;

function limitar(n: unknown, min: number, max: number, def: number): number {
  const x = Number(n);
  return Number.isFinite(x) ? Math.max(min, Math.min(max, Math.round(x))) : def;
}

// ─── Preenchimento ──────────────────────────────────────────────────────────
// Medido a 03/11: o gte gasta ~115 ms de PROCESSADOR por texto e a Edge Function morre com
// "CPU Time exceeded" (546) acima de ~2 s por pedido. Por isso cada pedido faz poucos textos,
// com um orçamento de processador, e grava logo; o resto faz-se em muitos pedidos (fatias por id).
async function preencherProdutos(admin: Json, b: Json) {
  const t0 = Date.now();
  const lote = limitar(b.lote, 1, 40, 12);
  const orcamento = limitar(b.orcamento_ms, 200, 1600, 1300);
  const antes = typeof b.antes === 'string' && b.antes ? b.antes : null;
  const depois = typeof b.depois === 'string' ? b.depois : '';
  const { data, error } = await admin.rpc('assistant_products_without_embedding_gte', { p_limit: lote, p_after: depois, p_before: antes });
  if (error) throw new Error(`lista: ${error.message}`);
  const linhas = (data ?? []) as Json[];
  const payload: Json[] = [];
  let erros = 0, feitos = 0, msGte = 0, cortado = false;
  let ultimo = depois;
  let ultimoErro: string | null = null;
  for (const r of linhas) {
    const media = feitos ? msGte / feitos : 130;
    if (msGte + media > orcamento) { cortado = true; break; }
    try {
      const ti = Date.now();
      const v = await vetorGte(String(r.texto ?? '').slice(0, 1000) || String(r.id), 10000);
      msGte += Date.now() - ti;
      feitos++;
      payload.push({ id: r.id, e: lit(v) });
    } catch (e) {
      erros++;
      ultimoErro = (e as Error).message.slice(0, 200);
    }
    ultimo = r.id;
  }
  let gravados = 0;
  if (payload.length) {
    const { data: n, error: e2 } = await admin.rpc('assistant_set_embeddings_gte', { p_rows: payload });
    if (e2) throw new Error(`gravar: ${e2.message}`);
    gravados = Number(n ?? 0);
  }
  return {
    gravados, erros, ultimo, acabou: !cortado && linhas.length < lote,
    ms_medio_gte: feitos ? Math.round(msGte / feitos) : null, ms_gte: msGte, ms: Date.now() - t0, ultimo_erro: ultimoErro,
  };
}

async function preencherManual(admin: Json, b: Json) {
  const t0 = Date.now();
  const lote = limitar(b.lote, 1, 20, 4);
  const orcamento = limitar(b.orcamento_ms, 200, 1600, 1300);
  // com { ids: [...] } faz só esses trechos (para vários pedidos em paralelo sem repetir trabalho)
  const ids = Array.isArray(b.ids) ? b.ids.slice(0, 20).map(String) : null;
  const { data, error } = ids
    ? await admin.from('support_knowledge_chunks').select('id, texto:chunk_text').in('id', ids).is('embedding_gte', null).limit(lote)
    : await admin.rpc('knowledge_chunks_without_gte', { p_limit: lote });
  if (error) throw new Error(`lista: ${error.message}`);
  const linhas = (data ?? []) as Json[];
  const payload: Json[] = [];
  let erros = 0, feitos = 0, msGte = 0, cortado = false;
  let ultimoErro: string | null = null;
  for (const r of linhas) {
    const media = feitos ? msGte / feitos : 300;
    if (msGte + media > orcamento) { cortado = true; break; }
    try {
      const ti = Date.now();
      // o gte só lê ~512 pedaços de palavra; 1800 letras chegam e não rebentam o processador
      const v = await vetorGte(String(r.texto ?? '').slice(0, 1800), 15000);
      msGte += Date.now() - ti;
      feitos++;
      payload.push({ id: r.id, e: lit(v) });
    } catch (e) {
      erros++;
      ultimoErro = (e as Error).message.slice(0, 200);
    }
  }
  let gravados = 0;
  if (payload.length) {
    const { data: n, error: e2 } = await admin.rpc('knowledge_set_embeddings_gte', { p_rows: payload });
    if (e2) throw new Error(`gravar: ${e2.message}`);
    gravados = Number(n ?? 0);
  }
  return {
    gravados, erros, acabou: !cortado && linhas.length < lote,
    ms_medio_gte: feitos ? Math.round(msGte / feitos) : null, ms_gte: msGte, ms: Date.now() - t0, ultimo_erro: ultimoErro,
  };
}

async function geminiNovos(admin: Json, b: Json) {
  const limite = limitar(b.limite, 1, 300, 100);
  const dias = limitar(b.dias, 1, 60, 14);
  if (!CHAVE_GEMINI) return { gravados: 0, nota: 'sem chave Gemini' };
  const { data, error } = await admin.rpc('assistant_products_without_embedding_recent', { p_limit: limite, p_days: dias });
  if (error) throw new Error(`lista: ${error.message}`);
  const linhas = (data ?? []) as Json[];
  let gravados = 0;
  let erro: string | null = null;
  for (let i = 0; i < linhas.length; i += 100) {
    const parte = linhas.slice(i, i + 100);
    try {
      const vs = await vetoresGeminiLote(parte.map((r) => String(r.texto ?? r.id)), CHAVE_GEMINI, 'RETRIEVAL_DOCUMENT');
      const { data: n, error: e2 } = await admin.rpc('assistant_set_embeddings', {
        p_rows: parte.map((r, k) => ({ id: r.id, e: lit(vs[k]), m: 'gemini-embedding-001' })),
      });
      if (e2) throw new Error(e2.message);
      gravados += Number(n ?? 0);
    } catch (e) {
      erro = (e as Error).message.slice(0, 200);
      break; // a reserva não pode travar o resto: o gte já está gravado
    }
  }
  return { encontrados: linhas.length, gravados, erro };
}

// ─── Gemini dos produtos ANTIGOS que ficaram sem vetor (m11, 09/11/2026) ─────
// A pesquisa das lojas usa o gte (todos os produtos à venda já o têm). O Gemini é a
// reserva do assistente: a 09/11 só 929 de 48 271 produtos à venda o tinham. Esta ação
// enche-os aos poucos, em lotes de 100 (batchEmbedContents), parando no primeiro erro
// (ex.: 429 da quota grátis, ~900 textos por dia medido a 03/11). Para correr 1 vez
// por dia com limite 800: ~60 dias para os 47 342 que faltam, custo 0 € (só a chave
// GEMINI_API_KEY que já está nos segredos). Lista: RPC pesquisa_produtos_sem_gemini.
async function geminiAtrasados(admin: Json, b: Json) {
  const limite = limitar(b.limite, 1, 800, 100);
  if (!CHAVE_GEMINI) return { gravados: 0, nota: 'sem chave Gemini' };
  let gravados = 0;
  let encontrados = 0;
  let erro: string | null = null;
  while (gravados < limite && !erro) {
    const { data, error } = await admin.rpc('pesquisa_produtos_sem_gemini', { p_limit: Math.min(100, limite - gravados) });
    if (error) throw new Error(`lista: ${error.message}`);
    const parte = (data ?? []) as Json[];
    if (parte.length === 0) break;
    encontrados += parte.length;
    try {
      const vs = await vetoresGeminiLote(parte.map((r) => String(r.texto ?? r.id)), CHAVE_GEMINI, 'RETRIEVAL_DOCUMENT');
      const { data: n, error: e2 } = await admin.rpc('assistant_set_embeddings', {
        p_rows: parte.map((r, k) => ({ id: r.id, e: lit(vs[k]), m: 'gemini-embedding-001' })),
      });
      if (e2) throw new Error(e2.message);
      const feitos = Number(n ?? 0);
      gravados += feitos;
      if (feitos === 0) break; // nada gravado: não insistir no mesmo lote
    } catch (e) {
      erro = (e as Error).message.slice(0, 200);
    }
  }
  return { encontrados, gravados, erro };
}

// ─── Prova de qualidade ─────────────────────────────────────────────────────
async function lerPerguntas(admin: Json, ids: string[]) {
  const { data, error } = await admin.from('eval_emb_perguntas_20261103').select('id, conjunto, pergunta').in('id', ids);
  if (error) throw new Error(error.message);
  return (data ?? []) as Json[];
}

// Os vetores de cada pergunta nos dois motores ficam guardados na tabela da prova; as corridas
// (pesquisa real, motor contra motor, manual) fazem-se depois em SQL com esses vetores.
async function avaliarVetores(admin: Json, b: Json) {
  const ids = (Array.isArray(b.ids) ? b.ids : []).slice(0, 10).map(String);
  const perguntas = await lerPerguntas(admin, ids);
  const linhas: Json[] = [];
  const erros: Json[] = [];
  for (const p of perguntas) {
    for (const motor of ['gte', 'gemini'] as Motor[]) {
      try {
        const ti = Date.now();
        const v = motor === 'gte' ? await vetorGte(p.pergunta, 10000) : await vetorGemini(p.pergunta, CHAVE_GEMINI, 8000);
        linhas.push({ pergunta_id: p.id, motor, embedding: lit(v), ms: Date.now() - ti });
      } catch (e) {
        erros.push({ id: p.id, motor, erro: (e as Error).message.slice(0, 200) });
      }
    }
  }
  if (linhas.length) {
    const { error } = await admin.from('eval_emb_vetores_20261103').upsert(linhas, { onConflict: 'pergunta_id,motor' });
    if (error) throw new Error(`gravar vetores: ${error.message}`);
  }
  return { perguntas: perguntas.length, gravados: linhas.length, erros };
}

async function avaliarPoolGemini(admin: Json, b: Json) {
  const t0 = Date.now();
  const prazo = limitar(b.prazo_ms, 5000, 120000, 60000);
  const lote = limitar(b.lote, 1, 100, 100);
  let gravados = 0;
  let erro: string | null = null;
  while (Date.now() - t0 < prazo) {
    const { data, error } = await admin.rpc('eval_emb_pool_sem_gemini_20261103', { p_limit: lote });
    if (error) throw new Error(error.message);
    const linhas = (data ?? []) as Json[];
    if (!linhas.length) break;
    try {
      const vs = await vetoresGeminiLote(linhas.map((r) => String(r.texto)), CHAVE_GEMINI, 'RETRIEVAL_DOCUMENT');
      const { error: e2 } = await admin.from('eval_emb_pool_gemini_20261103').upsert(
        linhas.map((r, k) => ({ product_id: r.id, embedding: lit(vs[k]) })), { onConflict: 'product_id' },
      );
      if (e2) throw new Error(e2.message);
      gravados += linhas.length;
    } catch (e) {
      erro = (e as Error).message.slice(0, 300);
      break;
    }
  }
  const { count } = await admin.from('eval_emb_pool_gemini_20261103').select('product_id', { count: 'exact', head: true });
  return { gravados, total_com_gemini: count, erro, ms: Date.now() - t0 };
}

// ─── Prova do motor e da reserva, sem tabelas ───────────────────────────────
async function embed(admin: Json, b: Json) {
  // até 10 textos: o gte gasta processador (ver preencherProdutos)
  const textos = (Array.isArray(b.textos) ? b.textos : []).slice(0, 10).map((t: unknown) => String(t ?? '').slice(0, 1000));
  const motor = b.motor === 'gte' || b.motor === 'gemini' ? b.motor : 'cascata';
  const assunto = b.assunto === 'ajuda' ? 'ajuda' : 'produtos';
  const cfgBase = await lerConfigEmbeddings(admin, assunto);
  const falha = b.falha_forcada === 'gte' || b.falha_forcada === 'gemini' || b.falha_forcada === 'todos' ? b.falha_forcada : null;
  const cfg: ConfigEmbeddings = {
    ...cfgBase,
    falhaForcada: falha ?? cfgBase.falhaForcada,
    orcamento: { gte: b.orcamento_gte !== undefined ? limitar(b.orcamento_gte, 0, 10, 10) : 10 },
  };
  if (motor !== 'cascata') cfg.ordem = [motor];
  // só nesta prova: outra ordem sem mexer na definição que os clientes usam
  if (motor === 'cascata' && Array.isArray(b.ordem)) {
    const o = (b.ordem as unknown[]).filter((m): m is Motor => m === 'gte' || m === 'gemini');
    if (o.length) cfg.ordem = [...new Set(o)];
  }
  const saida: Json[] = [];
  const t0 = Date.now();
  for (const t of textos) {
    const r = await vetorComReserva(t, cfg, CHAVE_GEMINI);
    saida.push({
      texto: t.slice(0, 60), motor: r.motor, dims: r.vetor?.length ?? 0, ms: r.ms, caminho: resumoTentativas(r),
      tentativas: r.tentativas, ...(b.devolver_vetor && r.vetor ? { vetor: r.vetor } : {}),
    });
  }
  return { ordem: cfg.ordem, falha_forcada: cfg.falhaForcada, dims_esperadas: DIM, ms_total: Date.now() - t0, resultados: saida };
}

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors });
  if (req.method !== 'POST') return resposta({ ok: false, error: 'só POST' }, 405);
  const negado = await exigirServidorOuAdmin(req, cors);
  if (negado) return negado;
  const ping = await respostaAoPing(req, cors);
  if (ping) return ping;

  let b: Json = {};
  try {
    b = await req.json();
  } catch {
    return resposta({ ok: false, error: 'corpo inválido' }, 400);
  }
  const admin = createClient(SUPABASE_URL, secretKey()!, { auth: { persistSession: false } });
  const t0 = Date.now();
  try {
    let out: Json;
    switch (String(b.acao ?? '')) {
      case 'embed': out = await embed(admin, b); break;
      case 'preencher_produtos': out = await preencherProdutos(admin, b); break;
      case 'preencher_manual': out = await preencherManual(admin, b); break;
      case 'gemini_novos': out = await geminiNovos(admin, b); break;
      case 'gemini_atrasados': out = await geminiAtrasados(admin, b); break;
      case 'manter': {
        // um orçamento de processador para os dois (ver preencherProdutos); o Gemini é só rede
        const produtos = await preencherProdutos(admin, { lote: 10, orcamento_ms: 1100 });
        const manual = produtos.gravados === 0 && produtos.acabou
          ? await preencherManual(admin, { lote: 3, orcamento_ms: 1000 })
          : { gravados: 0, nota: 'fica para a próxima volta' };
        // O Gemini dos produtos novos vai noutro agendamento (de hora a hora, poucos): os lotes do
        // Gemini têm uma quota diária pequena (medido 03/11: 429 depois de ~900 num dia).
        let gemini: Json = { nota: 'gemini_novos tem agendamento próprio' };
        if (b.gemini === true) {
          try { gemini = await geminiNovos(admin, { limite: limitar(b.gemini_limite, 1, 100, 20), dias: 14 }); } catch (e) { gemini = { erro: (e as Error).message }; }
        }
        out = { produtos, manual, gemini };
        break;
      }
      case 'avaliar_vetores': out = await avaliarVetores(admin, b); break;
      case 'avaliar_pool_gemini': out = await avaliarPoolGemini(admin, b); break;
      default: return resposta({ ok: false, error: 'acao desconhecida' }, 400);
    }
    console.log(`[embeddings-gte] ${b.acao} ${Date.now() - t0}ms`);
    return resposta({ ok: true, acao: b.acao, ms: Date.now() - t0, ...out });
  } catch (e) {
    console.error(`[embeddings-gte] ${b.acao} falhou:`, (e as Error).message);
    return resposta({ ok: false, acao: b.acao, error: (e as Error).message.slice(0, 300), ms: Date.now() - t0 }, 500);
  }
});

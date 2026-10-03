// Sessão 5F B4 — Robô B: consulta knowledge base RAG (5C-α + match_knowledge)
// Run: deno run --allow-env --allow-read --allow-net \
//        scripts/crosstalk/query_knowledge.ts "<query>"
//
// Embedding model: gemini-embedding-001 (RETRIEVAL_QUERY, dim=768)
// match_knowledge RPC: top-N chunks com min_similarity=0.5

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.45.0';
import { load } from 'https://deno.land/std@0.224.0/dotenv/mod.ts';

const env = await load({ envPath: 'scripts/rag/.env' });
const SUPABASE_URL = env.SUPABASE_URL;
const SERVICE_ROLE_KEY = env.SUPABASE_SERVICE_ROLE_KEY;
const GEMINI_API_KEY = env.GEMINI_API_KEY;

if (!SUPABASE_URL || !SERVICE_ROLE_KEY || !GEMINI_API_KEY) {
  console.error('❌ scripts/rag/.env precisa de SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY + GEMINI_API_KEY');
  Deno.exit(1);
}

const args = Deno.args;
if (args.length === 0) {
  console.error('Uso: query_knowledge.ts "<termo de pesquisa>"');
  Deno.exit(1);
}

const query = args.join(' ').trim();
if (!query) {
  console.error('Query vazia.');
  Deno.exit(1);
}

const RAG_EMBED_DIM = 768;
const MATCH_COUNT = 8;
const MIN_SIM = 0.5;

const embedRes = await fetch(
  'https://generativelanguage.googleapis.com/v1beta/models/gemini-embedding-001:embedContent',
  {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'x-goog-api-key': GEMINI_API_KEY,
    },
    body: JSON.stringify({
      content: { parts: [{ text: query }] },
      outputDimensionality: RAG_EMBED_DIM,
      taskType: 'RETRIEVAL_QUERY',
    }),
  },
);

if (!embedRes.ok) {
  const txt = await embedRes.text();
  console.error(`❌ Gemini embedding falhou (${embedRes.status}):`, txt.slice(0, 300));
  Deno.exit(1);
}

const embData = await embedRes.json();
const values = embData?.embedding?.values;
if (!Array.isArray(values) || values.length !== RAG_EMBED_DIM) {
  console.error('❌ Embedding shape inesperada.');
  Deno.exit(1);
}

const supa = createClient(SUPABASE_URL, SERVICE_ROLE_KEY);

const { data: chunks, error } = await supa.rpc('match_knowledge', {
  query_embedding: values,
  match_count: MATCH_COUNT,
  min_similarity: MIN_SIM,
});

if (error) {
  console.error('❌ match_knowledge erro:', error.message);
  Deno.exit(1);
}

if (!chunks || chunks.length === 0) {
  console.log(`Sem chunks acima de min_similarity=${MIN_SIM} para "${query}".`);
  Deno.exit(0);
}

console.log(`\nQuery: "${query}"`);
console.log(`Chunks encontrados: ${chunks.length} (min_sim=${MIN_SIM})\n`);

for (let i = 0; i < chunks.length; i++) {
  const c = chunks[i];
  const sim = (c.similarity as number).toFixed(3);
  console.log(`──── #${i + 1} sim=${sim} ────`);
  console.log(`source: ${c.source_type}/${c.source_file}`);
  if (c.section_title) console.log(`section: ${c.section_title}`);
  console.log(`text:`);
  console.log(c.chunk_text);
  console.log('');
}

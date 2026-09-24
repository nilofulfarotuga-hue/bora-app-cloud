// Vetorização privada do Córtex usando o segredo Gemini já mantido no Supabase.
// A função aceita somente o service_role; nenhum cliente final a chama diretamente.
const SUPABASE_URL = Deno.env.get('SUPABASE_URL') || '';
const SERVICE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') || '';
const GEMINI_KEY = Deno.env.get('GEMINI_API_KEY') || '';
const MODEL = 'models/gemini-embedding-001';

const reply = (body: unknown, status = 200) => new Response(JSON.stringify(body), {
  status, headers: { 'content-type': 'application/json', 'cache-control': 'no-store' },
});

async function embeddings(texts: string[], taskType: 'RETRIEVAL_DOCUMENT' | 'RETRIEVAL_QUERY') {
  const r = await fetch(`https://generativelanguage.googleapis.com/v1beta/${MODEL}:batchEmbedContents`, {
    method: 'POST',
    headers: { 'content-type': 'application/json', 'x-goog-api-key': GEMINI_KEY },
    body: JSON.stringify({ requests: texts.map((text) => ({
      model: MODEL,
      content: { parts: [{ text }] },
      embedContentConfig: { taskType, outputDimensionality: 768 },
    })) }),
  });
  if (!r.ok) throw new Error(`embedding_${r.status}`);
  const raw = (await r.json())?.embeddings?.map((x: { values?: number[] }) => x.values);
  if (!Array.isArray(raw) || raw.length !== texts.length || raw.some((v) => !Array.isArray(v) || v.length < 768)) throw new Error('embedding_shape');
  // A API batch pode ignorar a dimensão reduzida e devolver 3072. O modelo é
  // Matryoshka: truncar para 768 e normalizar mantém a busca compatível.
  return (raw as number[][]).map((v) => {
    const cut = v.slice(0, 768); const norm = Math.sqrt(cut.reduce((sum, x) => sum + x * x, 0)) || 1;
    return cut.map((x) => x / norm);
  });
}

Deno.serve(async (req) => {
  if (req.method !== 'POST') return reply({ error: 'method_not_allowed' }, 405);
  const bearer = (req.headers.get('authorization') || '').replace(/^Bearer\s+/i, '');
  let role = '';
  try { role = JSON.parse(atob((bearer.split('.')[1] || '').replace(/-/g, '+').replace(/_/g, '/'))).role || ''; } catch { /* gateway also validates JWT */ }
  if (!SERVICE_KEY || role !== 'service_role') return reply({ error: 'forbidden' }, 403);
  if (!GEMINI_KEY) return reply({ error: 'embedding_not_configured' }, 503);
  let body: { action?: string; texts?: string[]; query?: string; limit?: number } = {};
  try { body = await req.json(); } catch { return reply({ error: 'bad_json' }, 400); }
  try {
    if (body.action === 'embed_documents') {
      const texts = (body.texts || []).map((x) => String(x).slice(0, 7000));
      if (!texts.length || texts.length > 50) return reply({ error: 'texts_1_to_50_required' }, 400);
      return reply({ embeddings: await embeddings(texts, 'RETRIEVAL_DOCUMENT') });
    }
    if (body.action === 'search') {
      const query = String(body.query || '').trim().slice(0, 500);
      if (!query) return reply({ error: 'query_required' }, 400);
      const [vector] = await embeddings([query], 'RETRIEVAL_QUERY');
      const r = await fetch(`${SUPABASE_URL}/rest/v1/rpc/match_cortex_knowledge`, {
        method: 'POST',
        headers: { 'content-type': 'application/json', apikey: SERVICE_KEY, authorization: `Bearer ${SERVICE_KEY}` },
        body: JSON.stringify({ query_embedding: vector, match_count: Math.min(Math.max(body.limit || 6, 1), 10), min_similarity: 0.42 }),
      });
      if (!r.ok) throw new Error(`search_${r.status}`);
      return reply({ results: await r.json() });
    }
    return reply({ error: 'unknown_action' }, 400);
  } catch (e) {
    const reason = e instanceof Error ? e.message : 'unknown';
    console.error('[cortex-embedding]', reason);
    return reply({ error: 'embedding_unavailable', reason }, 503);
  }
});


// Job retomável: gera embeddings Gemini (768d) para todos os produtos disponíveis
// e grava via RPC assistant_set_embeddings (service_role). Corre no PC:
//   MSYS_NO_PATHCONV=1 node embed_products.cjs [maxBatches]
// Retoma sozinho: assistant_products_without_embedding só devolve os que faltam.
const fs = require('fs');
const env = fs.readFileSync('C:/BoraLocal/projetosflutter/bora_app/backend/.env', 'utf8');
const g = (k) => (env.match(new RegExp('^' + k + '=(.*)$', 'm')) || [])[1].trim();
const U = g('SUPABASE_URL'), K = g('SUPABASE_SERVICE_ROLE_KEY'), GK = g('GEMINI_API_KEY');
const H = { apikey: K, Authorization: 'Bearer ' + K, 'Content-Type': 'application/json' };
const MODEL = 'gemini-embedding-001';
const BATCH = 100;              // batchEmbedContents aceita até 100
const maxBatches = Number(process.argv[2] || 100000);
const log = (...a) => console.log(new Date().toISOString().slice(11, 19), ...a);

async function rpc(name, body) {
  for (let i = 0; i < 5; i++) {
    try {
      const r = await fetch(`${U}/rest/v1/rpc/${name}`, { method: 'POST', headers: H, body: JSON.stringify(body) });
      const t = await r.text();
      if (!r.ok) throw new Error(`${name} http ${r.status}: ${t.slice(0, 200)}`);
      return t ? JSON.parse(t) : null;
    } catch (e) { if (i === 4) throw e; await new Promise((s) => setTimeout(s, 1500 * (i + 1))); }
  }
}

async function embedBatch(texts) {
  const body = {
    requests: texts.map((t) => ({
      model: `models/${MODEL}`, content: { parts: [{ text: t }] },
      taskType: 'RETRIEVAL_DOCUMENT', outputDimensionality: 768,
    })),
  };
  for (let i = 0; i < 30; i++) {
    const r = await fetch(`https://generativelanguage.googleapis.com/v1beta/models/${MODEL}:batchEmbedContents`, {
      method: 'POST', headers: { 'Content-Type': 'application/json', 'x-goog-api-key': GK }, body: JSON.stringify(body),
    });
    if (r.status === 429 || r.status >= 500) { const w = Math.min(120000, 20000 * (i + 1)); log('gemini', r.status, 'espera', w); await new Promise((s) => setTimeout(s, w)); continue; }
    if (!r.ok) throw new Error(`gemini http ${r.status}: ${(await r.text()).slice(0, 300)}`);
    const j = await r.json();
    return (j.embeddings || []).map((e) => e.values);
  }
  throw new Error('gemini: demasiadas tentativas (limite da chave gratuita)');
}

(async () => {
  let after = '', total = 0, batches = 0;
  const t0 = Date.now();
  while (batches < maxBatches) {
    const rows = await rpc('assistant_products_without_embedding', { p_limit: BATCH, p_after: after });
    if (!rows || rows.length === 0) break;
    const vecs = await embedBatch(rows.map((r) => r.texto));
    if (vecs.length !== rows.length) throw new Error(`tamanho: ${vecs.length} vs ${rows.length}`);
    const payload = rows.map((r, i) => ({ id: r.id, e: '[' + vecs[i].map((x) => +x.toFixed(6)).join(',') + ']', m: MODEL }));
    const n = await rpc('assistant_set_embeddings', { p_rows: payload });
    total += n; batches++; after = rows[rows.length - 1].id;
    await new Promise((s) => setTimeout(s, Number(process.env.EMBED_PAUSA_MS || 15000)));
    if (batches % 10 === 0) log(`lotes=${batches} gravados=${total} último=${after} ${(Date.now() - t0) / 1000 | 0}s`);
  }
  log(`FIM lotes=${batches} gravados=${total} em ${(Date.now() - t0) / 1000 | 0}s`);
})().catch((e) => { console.error('ERRO', e.message); process.exit(1); });

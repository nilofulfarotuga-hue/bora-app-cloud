'use strict';
/**
 * .ai_4lojas_apply.js — DELETE + INSERT a Glovo harvest into products with the ÷1.15 price math.
 * preço_DB = ROUND(preço_glovo / 1.15, 2)  -> cliente Bora paga exactamente o preço Glovo
 * (app aplica non_partner_markup_pct=0.15 em runtime via pricing_calculate).
 *
 * Dry-run by default (prints stats + price-math sample). Pass --commit to DELETE+INSERT.
 * Usage: node .ai_4lojas_apply.js --in .ai_zippy_harvest.json --rid zippy-guarda --prefix zip- --names .ai_zippy_names.json --source glovo_zippy_rebuild_2026_06_08 [--commit]
 */
const fs = require('fs'); const https = require('https'); const { URL } = require('url');
function loadEnv(f) { const t = fs.readFileSync(f, 'utf8'); const e = {}; for (const m of t.matchAll(/^([A-Z_]+)\s*=\s*(.*)$/gm)) e[m[1]] = m[2].trim().replace(/^["']|["']$/g, ''); return e; }
const env = loadEnv('backend/.env'); const KEY = env.SUPABASE_SERVICE_ROLE_KEY; const REST = env.SUPABASE_URL.replace(/\/$/, '') + '/rest/v1';
const sleep = ms => new Promise(r => setTimeout(r, ms));
function arg(n, d) { const i = process.argv.indexOf('--' + n); return i > 0 ? process.argv[i + 1] : d; }
function reqm(method, path, body, extra) { return new Promise(res => { const u = new URL(REST + path); const data = body ? JSON.stringify(body) : null; const headers = { apikey: KEY, authorization: 'Bearer ' + KEY, 'content-type': 'application/json', ...(data ? { 'content-length': Buffer.byteLength(data) } : {}), ...(extra || {}) }; const r = https.request({ hostname: u.hostname, path: u.pathname + u.search, method, headers }, resp => { let d = ''; resp.on('data', c => d += c); resp.on('end', () => res({ status: resp.statusCode, body: d })); }); r.on('error', e => res({ status: 0, body: e.message })); if (data) r.write(data); r.end(); }); }
const post = (p, b, x) => reqm('POST', p, b, x);
const del = p => reqm('DELETE', p, null, { Prefer: 'return=minimal' });

const IN = arg('in'), RID = arg('rid'), PREFIX = arg('prefix'), NAMES = arg('names'), SOURCE = arg('source', 'glovo_rebuild_2026_06_08'), MARKUP = 1.15;
const COMMIT = process.argv.includes('--commit');
const NAMES_TEXT = fs.readFileSync(NAMES, 'utf8');
const NAMEMAP = JSON.parse(NAMES_TEXT);
// ROOT_ORDER must follow the file's TEXTUAL order (= Glovo home order). Object.values() would
// reorder integer-like keys numerically (V8), breaking the intended visual order.
const ROOT_ORDER = [...NAMES_TEXT.matchAll(/"\d+"\s*:\s*"([^"]+)"/g)].map(m => m[1]);

(async () => {
  const H = JSON.parse(fs.readFileSync(IN, 'utf8'));
  const rootIdx = r => { const i = ROOT_ORDER.indexOf(r); return i < 0 ? 999 : i; };
  const seen = new Set(); const raw = []; const glovoById = new Map(); let droppedNoImg = 0;
  for (let k = 0; k < H.length; k++) {
    const p = H[k]; const id = PREFIX + p.id;
    if (seen.has(id)) continue; seen.add(id);
    if (!p.name || p.price == null) continue;
    if (!p.img) { droppedNoImg++; continue; } // enforce 0 sem_foto (criterion)
    glovoById.set(id, p.price);
    const price = Math.round((p.price / MARKUP) * 100) / 100;
    raw.push({ _ri: rootIdx(p.root), _k: k, id, restaurant_id: RID, name: String(p.name).slice(0, 250), photo_url: p.img || null, price,
      category_root: p.root || null, category: p.root || null, is_available: true, source: SOURCE, image_source: 'glovo_official', needs_photo: !p.img, last_updated: '2026-06-08' });
  }
  raw.sort((a, b) => a._ri - b._ri || a._k - b._k);
  const rows = raw.map((r, i) => { const { _ri, _k, ...rest } = r; return { ...rest, sort_order: i }; });
  const byRoot = {}; let noImg = 0, noPrice = 0;
  for (const r of rows) { byRoot[r.category_root] = (byRoot[r.category_root] || 0) + 1; if (!r.photo_url) noImg++; if (r.price == null) noPrice++; }
  console.log('rid=' + RID + ' rows=' + rows.length + ' cats=' + Object.keys(byRoot).length + ' sem_foto=' + noImg + ' sem_preco=' + noPrice + ' droppedNoImg=' + droppedNoImg);
  console.log('byRoot=' + JSON.stringify(byRoot));
  console.log('price-math sample (glovo -> ÷1.15 = db -> ×1.15 back):');
  for (const r of rows.slice(0, 4)) { const g = glovoById.get(r.id); console.log('  [' + r.category_root + '] ' + r.name.slice(0, 40) + ' | glovo=' + g + ' db=' + r.price + ' back=' + (Math.round(r.price * 1.15 * 100) / 100)); }
  if (!COMMIT) { console.log('\nDRY-RUN — pass --commit to DELETE+INSERT'); return; }
  const SKIP_DELETE = process.argv.includes('--no-delete');
  if (SKIP_DELETE) { console.log('--no-delete: upserting without DELETE (idempotent fill)'); }
  else {
    let d, t = 0;
    do { d = await del('/products?restaurant_id=eq.' + encodeURIComponent(RID)); if (d.status >= 200 && d.status < 300) break; t++; await sleep(2500 * t); } while (t < 6);
    console.log('DELETE ' + RID + ' -> status=' + d.status);
    if (!(d.status >= 200 && d.status < 300)) { console.error('DELETE failed after retries — ABORT INSERT (keeps old data, avoids stragglers)'); return; }
  }
  let ok = 0, fail = 0; const errs = [];
  for (let i = 0; i < rows.length; i += 150) {
    const batch = rows.slice(i, i + 150); let r, t = 0;
    do { r = await post('/products?on_conflict=id', batch, { Prefer: 'resolution=merge-duplicates,return=minimal' }); if (r.status >= 200 && r.status < 300) break; t++; await sleep(2500 * t); } while (t < 6);
    if (r.status >= 200 && r.status < 300) ok += batch.length; else { fail += batch.length; if (errs.length < 4) errs.push(r.status + ':' + r.body.slice(0, 160)); }
    await sleep(500);
  }
  console.log('INSERT ok=' + ok + ' fail=' + fail); if (errs.length) console.log(errs.join('\n'));
  // verify final count
  const c = await reqm('GET', '/products?restaurant_id=eq.' + encodeURIComponent(RID) + '&select=id', null, { Prefer: 'count=exact', Range: '0-0' });
  console.log('VERIFY count header:', c.status);
})();

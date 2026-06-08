'use strict';
// Audit: compare a Glovo restaurant harvest vs current DB. Reports new / removed / price-diff (id-level).
// Price check: DB.price should equal ROUND(glovo_now/1.15, 2); mismatch = price drift.
const fs = require('fs'); const https = require('https'); const { URL } = require('url');
function loadEnv(f) { const t = fs.readFileSync(f, 'utf8'), e = {}; for (const m of t.matchAll(/^([A-Z_]+)\s*=\s*(.*)$/gm)) e[m[1]] = m[2].trim().replace(/^["']|["']$/g, ''); return e; }
const env = loadEnv('backend/.env'); const KEY = env.SUPABASE_SERVICE_ROLE_KEY; const REST = env.SUPABASE_URL.replace(/\/$/, '') + '/rest/v1';
function arg(n, d) { const i = process.argv.indexOf('--' + n); return i > 0 ? process.argv[i + 1] : d; }
const IN = arg('in'), RID = arg('rid'), PREFIX = arg('prefix');
function getDB() { return new Promise(res => { const u = new URL(REST + '/products?restaurant_id=eq.' + encodeURIComponent(RID) + '&select=id,name,price&limit=5000'); https.get({ hostname: u.hostname, path: u.pathname + u.search, headers: { apikey: KEY, authorization: 'Bearer ' + KEY } }, r => { let d = ''; r.on('data', c => d += c); r.on('end', () => res(JSON.parse(d))); }); }); }
(async () => {
  const H = JSON.parse(fs.readFileSync(IN, 'utf8'));
  const harvestById = new Map(); for (const p of H) harvestById.set(PREFIX + p.id, p);
  const db = await getDB(); const dbById = new Map(); for (const r of db) dbById.set(r.id, r);
  const newOnes = [], removed = [], priceDiff = [];
  for (const [id, p] of harvestById) if (!dbById.has(id)) newOnes.push({ id, name: p.name, glovo: p.price, cat: p.root });
  for (const [id, r] of dbById) if (!harvestById.has(id)) removed.push({ id, name: r.name, db: +r.price });
  for (const [id, p] of harvestById) { const r = dbById.get(id); if (r) { const exp = Math.round((p.price / 1.15) * 100) / 100; if (Math.abs(exp - (+r.price)) >= 0.01) priceDiff.push({ id, name: p.name, db: +r.price, glovo: p.price, exp }); } }
  console.log('=== AUDIT ' + RID + ' ===');
  console.log('Glovo agora: ' + H.length + ' | DB: ' + db.length + ' | novos: ' + newOnes.length + ' | removidos: ' + removed.length + ' | preco-diff: ' + priceDiff.length);
  console.log('-- NOVOS no Glovo (faltam DB):'); for (const x of newOnes.slice(0, 40)) console.log('  +[' + x.id + '] ' + String(x.name).slice(0, 48) + ' EUR' + x.glovo + ' (' + x.cat + ')');
  console.log('-- REMOVIDOS do Glovo (ainda DB):'); for (const x of removed.slice(0, 40)) console.log('  -[' + x.id + '] ' + String(x.name).slice(0, 48) + ' DB' + x.db);
  console.log('-- PRECO DIFERENTE:'); for (const x of priceDiff.slice(0, 40)) console.log('  ~[' + x.id + '] ' + String(x.name).slice(0, 40) + ' DB' + x.db + ' esperado' + x.exp + ' (glovo' + x.glovo + ')');
})();

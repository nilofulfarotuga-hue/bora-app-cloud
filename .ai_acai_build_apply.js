'use strict';
/**
 * .ai_acai_build_apply.js — insert Sabores de Casa Açaí products + option groups/items.
 * PARTNER store: DB price = REAL store price (no markup). Cups overridden (Mega=12, Médio=5, Pequeno=3.50);
 * everything else = Glovo price as-is. Glovo storeProductId (UUID) used directly as products.id (cart needs UUID).
 * Option groups/items built from crawled attributeGroups: is_required = min>=1.
 * +1 placeholder product for empty category "Mercearia Brasileira".
 * Dry-run by default; --commit DELETEs restaurant_id=RID (cascade) then inserts.
 */
const fs = require('fs'); const https = require('https'); const { URL } = require('url'); const { randomUUID } = require('crypto');
function loadEnv(f) { const t = fs.readFileSync(f, 'utf8'); const e = {}; for (const m of t.matchAll(/^([A-Z_]+)\s*=\s*(.*)$/gm)) e[m[1]] = m[2].trim().replace(/^["']|["']$/g, ''); return e; }
const env = loadEnv('backend/.env'); const KEY = env.SUPABASE_SERVICE_ROLE_KEY; const REST = env.SUPABASE_URL.replace(/\/$/, '') + '/rest/v1';
const RID = '12aa2cbb-01bd-443b-a17e-633c169d4864', TODAY = '2026-06-08';
const COMMIT = process.argv.includes('--commit');
const sleep = ms => new Promise(r => setTimeout(r, ms));
function reqm(method, path, body, extra) { return new Promise(res => { const u = new URL(REST + path); const data = body ? JSON.stringify(body) : null; const headers = { apikey: KEY, authorization: 'Bearer ' + KEY, 'content-type': 'application/json', ...(data ? { 'content-length': Buffer.byteLength(data) } : {}), ...(extra || {}) }; const r = https.request({ hostname: u.hostname, path: u.pathname + u.search, method, headers }, resp => { let d = ''; resp.on('data', c => d += c); resp.on('end', () => res({ status: resp.statusCode, body: d })); }); r.on('error', e => res({ status: 0, body: e.message })); if (data) r.write(data); r.end(); }); }
const post = (p, b, x) => reqm('POST', p, b, x); const del = p => reqm('DELETE', p, null, { Prefer: 'return=minimal' });
const CAT_ORDER = ['Açaí', 'Doces', 'Bebidas', 'Embalagens', 'Mercearia Brasileira'];
function priceFor(name, glovo) { const n = name.toLowerCase(); if (/copo mega/.test(n)) return 12.00; if (/copo grande/.test(n)) return 8.00; if (/copo m[eé]dio/.test(n)) return 5.00; if (/copo pequeno/.test(n)) return 3.50; return glovo; }
(async () => {
  const crawled = JSON.parse(fs.readFileSync('.ai_acai_products.json', 'utf8'));
  // Copo Grande €8 — não existe na Glovo (só Mega/Médio/Pequeno); criado a pedido do dono.
  // Clona os grupos do Mega com 4 acompanhamentos grátis (entre Médio=3 e Mega=5).
  const _mega = crawled.find(p => /copo mega/i.test(p.name));
  if (_mega && !crawled.some(p => /copo grande/i.test(p.name))) {
    const gGroups = _mega.groups.map(g => ({
      name: g.name,
      min: /acompanhament/i.test(g.name) ? 4 : g.min,
      max: /acompanhament/i.test(g.name) ? 4 : g.max,
      multiple: g.multiple,
      items: g.items.map(it => ({ name: it.name, priceAdd: it.priceAdd })),
    }));
    crawled.splice(crawled.indexOf(_mega) + 1, 0, {
      id: randomUUID(),
      name: 'Copo Grande',
      description: 'Inclui 4 acompanhamentos à escolha.',
      price: 8.0,
      img: _mega.img,
      root: 'Açaí',
      groups: gGroups,
    });
  }
  const products = [], groups = [], items = [];
  // map products (preserve Glovo category order then by source order)
  const sorted = crawled.slice().sort((a, b) => (CAT_ORDER.indexOf(a.root) - CAT_ORDER.indexOf(b.root)));
  let so = 0;
  for (const p of sorted) {
    const price = priceFor(p.name, p.price);
    products.push({ id: p.id, restaurant_id: RID, name: p.name, description: p.description || null, price, photo_url: p.img || null, category: p.root, category_root: p.root, is_available: true, source: 'glovo_acai_partner', image_source: p.img ? 'glovo_official' : null, needs_photo: !p.img, last_updated: TODAY, sort_order: so++ });
    let go = 0;
    for (const g of p.groups) {
      const gid = randomUUID();
      groups.push({ id: gid, product_id: p.id, name: g.name, description: null, is_required: g.min >= 1, min_choices: g.min, max_choices: g.max, sort_order: go++ });
      let io = 0;
      for (const it of g.items) items.push({ id: randomUUID(), group_id: gid, name: it.name, price_add: it.priceAdd || 0, is_available: true, sort_order: io++ });
    }
  }
  // placeholder for Mercearia Brasileira
  products.push({ id: randomUUID(), restaurant_id: RID, name: 'Em breve...', description: 'O parceiro irá adicionar produtos brasileiros aqui.', price: 0.01, photo_url: null, category: 'Mercearia Brasileira', category_root: 'Mercearia Brasileira', is_available: false, source: 'placeholder', image_source: null, needs_photo: false, last_updated: TODAY, sort_order: so++ });

  // report
  const byCat = {}; for (const p of products) byCat[p.category] = (byCat[p.category] || 0) + 1;
  console.log('PRODUCTS=' + products.length + ' GROUPS=' + groups.length + ' ITEMS=' + items.length);
  console.log('byCat=' + JSON.stringify(byCat));
  console.log('--- price mapping (cups) ---');
  for (const p of products.filter(p => /copo/i.test(p.name))) { const g = crawled.find(c => c.id === p.id); console.log('  ' + p.name + ' : glovo €' + (g ? g.price : '?') + ' -> DB €' + p.price); }
  console.log('--- option groups ---');
  for (const g of groups) console.log('  [' + (products.find(p => p.id === g.product_id) || {}).name + '] "' + g.name + '" required=' + g.is_required + ' min=' + g.min_choices + ' max=' + g.max_choices + ' items=' + items.filter(i => i.group_id === g.id).length);
  if (!COMMIT) { console.log('\nDRY-RUN — pass --commit to DELETE+INSERT'); return; }

  // COMMIT
  let d = await del('/products?restaurant_id=eq.' + encodeURIComponent(RID));
  console.log('DELETE products (cascade groups/items) -> ' + d.status);
  if (!(d.status >= 200 && d.status < 300)) { console.error('DELETE failed — ABORT'); return; }
  async function insertAll(path, rows) { let ok = 0; for (let i = 0; i < rows.length; i += 150) { const batch = rows.slice(i, i + 150); let r, t = 0; do { r = await post(path + '?on_conflict=id', batch, { Prefer: 'resolution=merge-duplicates,return=minimal' }); if (r.status >= 200 && r.status < 300) break; t++; await sleep(2000 * t); } while (t < 4); if (r.status >= 200 && r.status < 300) ok += batch.length; else console.error('INSERT ' + path + ' FAIL ' + r.status + ': ' + r.body.slice(0, 200)); await sleep(300); } return ok; }
  const okP = await insertAll('/products', products);
  const okG = await insertAll('/product_option_groups', groups);
  const okI = await insertAll('/product_option_items', items);
  console.log('INSERT products=' + okP + ' groups=' + okG + ' items=' + okI);
})();

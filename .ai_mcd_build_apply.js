'use strict';
/**
 * .ai_mcd_build_apply.js — Build McDonald's Guarda catalog and (optionally) DELETE+INSERT into products.
 * Sources: .ai_mcd_deep.json (Glovo deep crawl, 139 incl. size variants).
 * Pricing (Danilo 2026-06-08):
 *   - Fonte A (kiosk photo) anchored items -> EXACT kiosk price.
 *   - Ketchup 0.05 / outros Molhos 0.90 / Happy Meal 5.00 (Fonte A rules).
 *   - Everyone else -> preco_DB = ROUND(preco_glovo * 0.8261, 2).   (NO ÷1.15, NO division-by-1.15)
 * 7 Fonte A items absent from Glovo are CREATED with a reused donor photo.
 * "Saco de Transporte" excluded (bag fee is applied by pricing_service; would double-charge).
 * Dry-run by default (stats + Fonte A verification). --commit => DELETE restaurant_id=mcdonalds-guarda + INSERT.
 * Usage: node .ai_mcd_build_apply.js [--commit]
 */
const fs = require('fs'); const https = require('https'); const { URL } = require('url');
function loadEnv(f) { const t = fs.readFileSync(f, 'utf8'); const e = {}; for (const m of t.matchAll(/^([A-Z_]+)\s*=\s*(.*)$/gm)) e[m[1]] = m[2].trim().replace(/^["']|["']$/g, ''); return e; }
const env = loadEnv('backend/.env'); const KEY = env.SUPABASE_SERVICE_ROLE_KEY; const REST = env.SUPABASE_URL.replace(/\/$/, '') + '/rest/v1';
const sleep = ms => new Promise(r => setTimeout(r, ms));
const COMMIT = process.argv.includes('--commit');
const RID = 'mcdonalds-guarda', FACTOR = 0.8261, TODAY = '2026-06-08';
function reqm(method, path, body, extra) { return new Promise(res => { const u = new URL(REST + path); const data = body ? JSON.stringify(body) : null; const headers = { apikey: KEY, authorization: 'Bearer ' + KEY, 'content-type': 'application/json', ...(data ? { 'content-length': Buffer.byteLength(data) } : {}), ...(extra || {}) }; const r = https.request({ hostname: u.hostname, path: u.pathname + u.search, method, headers }, resp => { let d = ''; resp.on('data', c => d += c); resp.on('end', () => res({ status: resp.statusCode, body: d })); }); r.on('error', e => res({ status: 0, body: e.message })); if (data) r.write(data); r.end(); }); }
const post = (p, b, x) => reqm('POST', p, b, x); const del = p => reqm('DELETE', p, null, { Prefer: 'return=minimal' });
const N = s => (s || '').toLowerCase().normalize('NFD').replace(/[̀-ͯ]/g, '').replace(/[®™]/g, '').replace(/\s+/g, ' ').trim();
const r2 = x => Math.round(x * 100) / 100;
const slug = s => N(s).replace(/[^a-z0-9]+/g, '-').replace(/^-|-$/g, '');

// Fonte A single-item specs: canonical name n (matches Danilo confirm query), kiosk price k, token rules.
const FA = [
  { n: 'Hamburguer', k: 1.80, all: ['hamburguer'], none: ['menu', 'happy', 'double'] },
  { n: 'Cheeseburger', k: 1.90, all: ['cheeseburger'], none: ['menu', 'happy', 'double', 'royal'] },
  { n: 'Chicken Bacon', k: 2.40, all: ['chicken', 'bacon'], none: ['menu', 'crispy', 'royal', 'big', 'happy'] },
  { n: 'Snack McWrap Chicken Mayo', k: 2.40, all: ['wrap', 'mayo'], none: ['menu', 'happy'] },
  { n: 'Snack McWrap Chicken Cheese', k: 2.40, all: ['wrap', 'cheese'], none: ['menu', 'happy', 'mayo'] },
  { n: 'McChicken®', k: 5.25, all: ['mcchicken'], none: ['menu', 'happy'] },
  { n: 'Double Cheeseburger', k: 5.50, all: ['double', 'cheeseburg'], none: ['menu'] },
  { n: 'McPrego', k: 5.40, all: ['mcprego'], none: ['menu', 'ovo'] },
  { n: 'McPrego com Ovo', k: 6.20, all: ['mcprego', 'ovo'], none: ['menu'] },
  { n: 'McBifana à Cervejeira', k: 5.20, all: ['mcbifana'], none: ['menu'] },
  { n: 'Big Mac®', k: 5.65, all: ['big mac'], none: ['menu'] },
  { n: 'McRoyal® Bacon', k: 6.00, all: ['royal', 'bacon'], none: ['menu'] },
  { n: 'McRoyal® Cheese', k: 6.00, all: ['royal', 'cheese'], none: ['menu', 'bacon', 'deluxe'] },
  { n: 'McRoyal® Deluxe', k: 6.00, all: ['royal', 'deluxe'], none: ['menu'] },
  { n: 'CBO®', k: 7.10, all: ['cbo'], none: ['menu'] },
  { n: 'McCrispy Original', k: 7.10, all: ['mccrispy', 'original'], none: ['menu', 'bbq', 'cajun'] },
  { n: 'McCrispy BBQ & Bacon', k: 7.70, all: ['mccrispy', 'bbq'], none: ['menu'] },
  { n: 'McCrispy Spicy Cajun', k: 7.70, all: ['mccrispy', 'cajun'], none: ['menu'] },
  { n: 'Big Tasty® Single', k: 7.20, all: ['big tasty', 'single'], none: ['menu'] },
  { n: 'Big Tasty® Double', k: 10.00, all: ['big tasty', 'double'], none: ['menu'] },
  { n: 'Big Arch', k: 9.90, all: ['big arch'], none: ['menu'] },
  { n: 'McMenu® 2 Snack Wraps', k: 6.60, all: ['mcmenu', 'snack', 'wrap'], none: ['grande'] },
  { n: '10 Chicken McNuggets®', k: 4.20, all: ['10', 'nugget'], none: ['menu', 'happy'] },
  { n: '20 Chicken McNuggets®', k: 7.20, all: ['20', 'nugget'], none: ['menu'] },
  { n: 'Chicken Wings 3', k: 2.70, all: ['wings', '3'], none: ['menu', 'share'] },
  { n: 'Chicken Wings 6', k: 4.40, all: ['wings', '6'], none: ['menu', 'share'] },
  { n: 'Chicken Delights', k: 2.40, all: ['delights'], none: [] },
  { n: 'Chicken Share Box Original', k: 7.95, all: ['share box', 'original'], none: ['menu', 'para 2'] },
  { n: 'Chicken Share Box McNuggets & Wings', k: 7.95, all: ['share box', 'wings'], none: ['menu', 'para 2'] },
  { n: 'Batata Pequena', k: 2.20, all: ['batata', 'pequena'], none: [] },
  { n: 'Cenouras Baby', k: 2.00, all: ['cenoura', 'baby'], none: [] },
  { n: 'Sopa Caldo Verde', k: 3.20, all: ['caldo verde'], none: [] },
  { n: 'Creme Espinafres', k: 3.20, all: ['creme', 'espinafre'], none: [] },
  { n: 'Sundae Chocolate', k: 1.90, all: ['sundae', 'chocolate'], none: [] },
  { n: 'Sundae Caramelo', k: 1.90, all: ['sundae', 'caramelo'], none: [] },
  { n: 'Sundae Morango', k: 1.90, all: ['sundae', 'morango'], none: [] },
  { n: 'Sundae Natura', k: 1.90, all: ['sundae', 'natura'], none: [] },
  { n: 'Sundae Ananás', k: 2.30, all: ['sundae', 'ananas'], none: [] },
  { n: 'Tarte de Maçã', k: 1.60, all: ['tarte', 'maca'], none: [] },
  { n: 'Fatias Maçã', k: 1.70, all: ['fatias', 'maca'], none: [] },
  { n: 'Polpa Fruta', k: 1.70, all: ['polpa'], none: [] },
];
// Fonte A items absent from Glovo -> create with reused donor photo.
const CREATED = [
  { n: 'Veggie Burguer', k: 2.40, cat: 'Europoupança', donor: ['mcveggie'] },
  { n: 'Menu Almoço', k: 6.00, cat: 'Menu Almoço', donor: ['mcmenu'] },
  { n: 'Sopa Feijão Verde', k: 3.20, cat: 'Saladas, Veggies & outros mais', donor: ['caldo', 'verde'] },
  { n: 'Creme Cenoura', k: 3.20, cat: 'Saladas, Veggies & outros mais', donor: ['creme', 'espinafre'] },
  { n: 'Mini McFlurry KitKat', k: 1.90, cat: 'Sobremesas', donor: ['mcflurry', 'kitkat'] },
  { n: 'Abacaxi', k: 1.70, cat: 'Sobremesas', donor: ['fatias', 'maca'] },
  { n: 'Panquecas', k: 2.70, cat: 'McCafé', donor: ['tarte'] },
];
const CAT_ORDER = ['Sanduíches e McMenus', 'Menu Almoço', 'Europoupança', 'Happy Meal', 'Saladas, Veggies & outros mais', 'Acompanhamentos e Molhos', 'Sobremesas', 'McCafé', 'Bebidas'];
function categoryOf(name, root) {
  const n = N(name), r = N(root);
  if (/happy meal/.test(n)) return 'Happy Meal';
  if (/europoupanc/.test(r)) return 'Europoupança';
  if (/menu almoc/.test(n)) return 'Menu Almoço';
  if (/panqueca/.test(n)) return 'McCafé';
  if (/salada|mcveggie|sopa |caldo verde|feijao verde|creme |cenouras baby/.test(n)) return 'Saladas, Veggies & outros mais';
  if (/sundae|mcflurry|tarte|polpa|abacaxi|fatias|gelado/.test(n)) return 'Sobremesas';
  if (/coca|fanta|sumol|compal|lipton|fuze|agua|bongo|ice tea|sprite|nestea|cerveja|sumo/.test(n)) return 'Bebidas';
  if (/nugget|wings|batata|molho|ketchup|delights|share box/.test(n)) return 'Acompanhamentos e Molhos';
  return 'Sanduíches e McMenus';
}
function matchFA(name) { const n = N(name); for (const s of FA) { if (s.all.every(t => n.includes(t)) && !s.none.some(t => n.includes(t))) return s; } return null; }

(async () => {
  const glovo = JSON.parse(fs.readFileSync('.ai_mcd_deep.json', 'utf8'));
  // donor image lookup (pre-dedup, full data)
  function donorImg(tokens) { const p = glovo.find(p => { const n = N(p.name); return tokens.every(t => n.includes(t)) && p.img; }); return p ? p.img : null; }
  // dedup by normalized name (exclude Saco de Transporte); keep min price; prefer Europoupança root; keep an image
  const map = new Map();
  for (const p of glovo) {
    if (/saco de transporte/.test(N(p.name))) continue;
    const key = N(p.name); if (!key) continue;
    if (!map.has(key)) map.set(key, { id: p.id, name: String(p.name).trim().replace(/\s+/g, ' '), price: p.price, img: p.img || null, root: p.root || '', variant: !!p.variant });
    else { const ex = map.get(key); if (p.price != null && (ex.price == null || p.price < ex.price)) ex.price = p.price; if (/europoupanc/.test(N(p.root)) && !/europoupanc/.test(N(ex.root))) ex.root = p.root; if (!ex.img && p.img) ex.img = p.img; }
  }
  const faFound = new Set();
  const items = [];
  for (const p of map.values()) {
    let name = p.name, price, src = 'glovo_mcd_rebuild_2026_06_08';
    const nn = N(p.name);
    if (/ketchup/.test(nn)) { name = 'Ketchup'; price = 0.05; faFound.add('Ketchup'); }
    else if (/^molho/.test(nn)) { price = 0.90; faFound.add('Molhos'); }
    else if (/happy meal/.test(nn)) { price = 5.00; faFound.add('Happy Meal'); }
    else { const s = matchFA(p.name); if (s) { name = s.n; price = s.k; faFound.add(s.n); } else { price = r2(p.price * FACTOR); } }
    items.push({ id: 'mcd-' + p.id, name: name.slice(0, 250), price, img: p.img, root: p.root, category_root: categoryOf(name, p.root), src });
  }
  // created items (only if not already present by canonical name)
  const present = new Set(items.map(i => N(i.name)));
  for (const c of CREATED) {
    if (present.has(N(c.n))) { faFound.add(c.n); continue; }
    const img = donorImg(c.donor);
    items.push({ id: 'mcd-fa-' + slug(c.n), name: c.n, price: c.k, img, root: c.cat, category_root: c.cat, src: 'kiosk_fonte_a' });
    faFound.add(c.n);
  }
  // sort + sort_order by category order
  items.sort((a, b) => (CAT_ORDER.indexOf(a.category_root) - CAT_ORDER.indexOf(b.category_root)) || N(a.name).localeCompare(N(b.name)));
  const rows = items.map((it, i) => ({ id: it.id, restaurant_id: RID, name: it.name, price: it.price, photo_url: it.img || null, category_root: it.category_root, category: it.category_root, search_normalized: N(it.name), is_available: true, source: it.src, image_source: 'glovo_official', needs_photo: !it.img, last_updated: TODAY, sort_order: i }));
  // stats
  const byCat = {}; let noImg = 0, noPrice = 0;
  for (const r of rows) { byCat[r.category_root] = (byCat[r.category_root] || 0) + 1; if (!r.photo_url) noImg++; if (r.price == null || r.price === 0) noPrice++; }
  console.log('TOTAL=' + rows.length + ' cats=' + Object.keys(byCat).length + ' sem_foto=' + noImg + ' sem_preco=' + noPrice);
  console.log('byCat=' + JSON.stringify(byCat));
  // Fonte A verification: every canonical name present with correct price
  const priceByName = new Map(rows.map(r => [N(r.name), r.price]));
  const checkList = [...FA.map(s => [s.n, s.k]), ['Ketchup', 0.05], ['Veggie Burguer', 2.40], ['Menu Almoço', 6.00], ['Sopa Feijão Verde', 3.20], ['Creme Cenoura', 3.20], ['Mini McFlurry KitKat', 1.90], ['Abacaxi', 1.70], ['Panquecas', 2.70]];
  let faOk = 0, faBad = [];
  for (const [nm, k] of checkList) { const got = priceByName.get(N(nm)); if (got === k) faOk++; else faBad.push(nm + '(want ' + k + ' got ' + got + ')'); }
  // Happy Meal + Molhos spot check
  const hm = rows.filter(r => /happy meal/.test(N(r.name))); const mo = rows.filter(r => /^molho/.test(N(r.name)));
  console.log('FONTE A: ok=' + faOk + '/' + checkList.length + ' | HappyMeal=' + hm.length + ' all5=' + hm.every(r => r.price === 5.0) + ' | Molhos=' + mo.length + ' all0.9=' + mo.every(r => r.price === 0.90));
  if (faBad.length) console.log('FONTE A MISMATCH: ' + faBad.join(' | '));
  // price-math sample for non-FA
  const sample = rows.filter(r => r.src === 'glovo_mcd_rebuild_2026_06_08' && !matchFA(r.name) && !/happy meal|^molho|ketchup/.test(N(r.name))).slice(0, 5);
  console.log('x0.8261 sample:'); for (const r of sample) console.log('  ' + r.name.slice(0, 38) + ' = ' + r.price + ' [' + r.category_root + ']');
  fs.writeFileSync('.ai_mcd_insert.json', JSON.stringify(rows));
  console.log('wrote .ai_mcd_insert.json (' + rows.length + ' rows)');
  if (!COMMIT) { console.log('\nDRY-RUN — pass --commit to DELETE+INSERT (backup must exist first)'); return; }
  // COMMIT: DELETE only mcdonalds-guarda then INSERT in batches of 150
  let d, t = 0;
  do { d = await del('/products?restaurant_id=eq.' + encodeURIComponent(RID)); if (d.status >= 200 && d.status < 300) break; t++; await sleep(2500 * t); } while (t < 6);
  console.log('DELETE ' + RID + ' -> ' + d.status);
  if (!(d.status >= 200 && d.status < 300)) { console.error('DELETE failed — ABORT INSERT'); return; }
  let ok = 0, fail = 0; const errs = [];
  for (let i = 0; i < rows.length; i += 150) {
    const batch = rows.slice(i, i + 150); let r, tt = 0;
    do { r = await post('/products?on_conflict=id', batch, { Prefer: 'resolution=merge-duplicates,return=minimal' }); if (r.status >= 200 && r.status < 300) break; tt++; await sleep(2500 * tt); } while (tt < 6);
    if (r.status >= 200 && r.status < 300) ok += batch.length; else { fail += batch.length; if (errs.length < 4) errs.push(r.status + ':' + r.body.slice(0, 200)); }
    await sleep(500);
  }
  console.log('INSERT ok=' + ok + ' fail=' + fail); if (errs.length) console.log(errs.join('\n'));
})();

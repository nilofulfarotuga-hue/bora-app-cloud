'use strict';
/**
 * .ai_opcoes_glovo_apply.js — Fase 2: copia as opções (attributeGroups) da Glovo SSR
 * para product_option_groups + product_option_items na Bora.
 *
 * Lojas: McDonald's / Burger King / KFC (fast-food, price_add = priceImpact × 0.8261)
 *        Sabores de Casa Açaí (parceiro, price_add = priceImpact EXACTO; wipe+reinsert só os 2 copos Glovo).
 *
 * Decisões Danilo (2026-06-09): A=ingénuo · B=colapsar McD "(Grande)" · todos os produtos · extras ×0.8261 fast-food.
 * Fonte = página SSR glovoapp.com (API v3 morta, v4 anti-bot). Parser jsUnescape single-pass.
 *
 * Dry-run por defeito (só conta). Passa --commit para escrever. --store=mcd|bk|kfc|acai limita a 1 loja.
 * Usage: node .ai_opcoes_glovo_apply.js [--commit] [--store=mcd]
 */
const fs = require('fs');
const https = require('https');
const { URL } = require('url');

const COMMIT = process.argv.includes('--commit');
const ONLY = (process.argv.find(a => a.startsWith('--store=')) || '').split('=')[1] || null;

// ---- env / REST ----
const env = (() => {
  const t = fs.readFileSync('backend/.env', 'utf8'); const e = {};
  for (const m of t.matchAll(/^([A-Z_]+)\s*=\s*(.*)$/gm)) e[m[1]] = m[2].trim().replace(/^['"]|['"]$/g, '');
  return e;
})();
const KEY = env.SUPABASE_SERVICE_ROLE_KEY;
const REST = env.SUPABASE_URL.replace(/\/$/, '') + '/rest/v1';
const sleep = ms => new Promise(r => setTimeout(r, ms));

function reqm(method, path, body, extra) {
  return new Promise(res => {
    const u = new URL(REST + path);
    const data = body ? JSON.stringify(body) : null;
    const headers = { apikey: KEY, Authorization: 'Bearer ' + KEY, 'Content-Type': 'application/json', ...(extra || {}) };
    const r = https.request({ hostname: u.hostname, path: u.pathname + u.search, method, headers }, resp => {
      let d = ''; resp.on('data', c => d += c); resp.on('end', () => res({ status: resp.statusCode, body: d }));
    });
    r.setTimeout(30000, () => { r.destroy(); res({ status: -1, body: 'timeout' }); });
    r.on('error', e => res({ status: 0, body: String(e.message) }));
    if (data) r.write(data); r.end();
  });
}
const getJSON = async p => { const r = await reqm('GET', p, null, {}); return r.status === 200 ? JSON.parse(r.body) : (() => { throw new Error('GET ' + p + ' -> ' + r.status + ' ' + r.body.slice(0, 120)); })(); };
async function postBatch(table, rows) {
  let ok = 0, fail = 0; const errs = [];
  for (let i = 0; i < rows.length; i += 150) {
    const batch = rows.slice(i, i + 150); let r, t = 0;
    do { r = await reqm('POST', '/' + table + '?on_conflict=id', batch, { Prefer: 'resolution=merge-duplicates,return=minimal' }); if (r.status >= 200 && r.status < 300) break; t++; await sleep(1200 * t); } while (t < 3);
    if (r.status >= 200 && r.status < 300) ok += batch.length; else { fail += batch.length; if (errs.length < 3) errs.push(r.status + ':' + r.body.slice(0, 140)); }
  }
  return { ok, fail, errs };
}
async function delIn(table, col, ids) {
  let n = 0;
  for (let i = 0; i < ids.length; i += 100) {
    const chunk = ids.slice(i, i + 100).map(x => '"' + String(x).replace(/"/g, '') + '"').join(',');
    const r = await reqm('DELETE', '/' + table + '?' + col + '=in.(' + encodeURIComponent(chunk) + ')', null, { Prefer: 'return=minimal' });
    if (r.status >= 200 && r.status < 300) n += chunk.split(',').length; else console.error('DELETE ' + table + ' fail ' + r.status + ':' + r.body.slice(0, 140));
  }
  return n;
}

// ---- Glovo SSR fetch + parse ----
function getHTML(url, n) { n = n || 0; return new Promise(res => { const rq = https.get(url, { headers: { 'user-agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/124 Safari/537.36', accept: 'text/html', 'accept-language': 'pt-PT' } }, r => { const loc = r.headers.location; if ([301, 302, 303, 307, 308].includes(r.statusCode) && loc && n < 6) { r.resume(); return res(getHTML(loc.startsWith('http') ? loc : 'https://glovoapp.com' + loc, n + 1)); } let d = ''; r.on('data', c => d += c); r.on('end', () => res({ status: r.statusCode, body: d })); }); rq.setTimeout(25000, () => { rq.destroy(); res({ status: -1, body: '' }); }); rq.on('error', () => res({ status: 0, body: '' })); }); }
function jsUnescape(s) { let o = ''; for (let i = 0; i < s.length; i++) { const c = s[i]; if (c !== '\\') { o += c; continue; } const n = s[i + 1]; if (n === '\\') { o += '\\'; i++; } else if (n === '"') { o += '"'; i++; } else if (n === '/') { o += '/'; i++; } else if (n === 'n') { o += '\n'; i++; } else if (n === 't') { o += '\t'; i++; } else if (n === 'r') { o += '\r'; i++; } else if (n === 'b') { o += '\b'; i++; } else if (n === 'f') { o += '\f'; i++; } else if (n === 'u') { o += String.fromCharCode(parseInt(s.substr(i + 2, 4), 16) || 0); i += 5; } else { o += n; i++; } } return o; }
function mObj(s, st) { let dp = 0, iS = false, e = false; for (let i = st; i < s.length; i++) { const c = s[i]; if (e) { e = false; continue; } if (c === '\\') { e = true; continue; } if (c === '"') { iS = !iS; continue; } if (iS) continue; if (c === '{') dp++; else if (c === '}') { dp--; if (dp === 0) return i; } } return -1; }
function iPI(a) { if (typeof a.priceImpact === 'number') return a.priceImpact; if (a.priceInfo && typeof a.priceInfo.amount === 'number') return a.priceInfo.amount; return 0; }
function cl(s) { return String(s || '').replace(/\s+/g, ' ').trim(); }
function extract(rawHtml) {
  const h = jsUnescape(rawHtml); const byId = new Map(); const order = [];
  const re = /"type":"PRODUCT_(?:ROW|TILE)","data":/g; let m;
  while ((m = re.exec(h))) {
    const br = h.indexOf('{', m.index + m[0].length - 1); if (br < 0) continue; const end = mObj(h, br); if (end < 0) continue;
    let d; try { d = JSON.parse(h.slice(br, end + 1)); } catch (e) { re.lastIndex = br + 1; continue; } re.lastIndex = end;
    if (!d.name || !d.storeProductId) continue;
    const ag = (Array.isArray(d.attributeGroups) ? d.attributeGroups : []).map(g => ({ name: cl(g.name), min: g.min || 0, max: g.max || 0, items: (g.attributes || []).map(a => ({ n: cl(a.name), pi: Math.round(iPI(a) * 100) / 100 })) }));
    const rec = { name: cl(d.name), groups: ag, nG: ag.length };
    const ex = byId.get(d.storeProductId); if (!ex) { byId.set(d.storeProductId, rec); order.push(d.storeProductId); } else if (rec.nG > ex.nG) byId.set(d.storeProductId, rec);
  }
  return order.map(id => byId.get(id));
}
function norm(s) { return String(s || '').toLowerCase().normalize('NFD').replace(/[̀-ͯ]/g, '').replace(/®|™|©/g, '').replace(/\([^)]*\)/g, '').replace(/\b(medio|media|medium|grande|large|pequeno|pequena|small)\b/g, '').replace(/[^a-z0-9]/g, ''); }
const isGrande = s => /\(\s*grande\s*\)/i.test(s);
const round2 = x => Math.round(x * 100) / 100;

const STORES = [
  { key: 'mcd', name: "McDonald's", slug: 'mcdonalds-grd', rid: 'mcdonalds-guarda', mult: 0.8261, collapseGrande: true },
  { key: 'bk', name: 'Burger King', slug: 'burger-king-grd', rid: 'burgerking-guarda', mult: 0.8261 },
  { key: 'kfc', name: 'KFC', slug: 'kfc-grd', rid: 'kfc-guarda', mult: 0.8261 },
  { key: 'acai', name: 'Sabores Açaí', slug: 'sabores-de-casa-acai-grd', rid: '12aa2cbb-01bd-443b-a17e-633c169d4864', mult: 1.0, wipeFirst: true },
];

async function processStore(s) {
  const html = (await getHTML('https://glovoapp.com/pt/pt/guarda/stores/' + s.slug)).body;
  if (!html || html.length < 50000) { console.log('### ' + s.name + ' :: SSR vazio/bloqueado len=' + (html ? html.length : 0) + ' — SKIP'); return; }
  const glovo = extract(html).filter(p => p.nG > 0);
  const byNorm = new Map(); for (const p of glovo) { const k = norm(p.name); const ex = byNorm.get(k); if (!ex || p.nG > ex.nG) byNorm.set(k, p); }
  const bora = await getJSON('/products?restaurant_id=eq.' + encodeURIComponent(s.rid) + '&select=id,name,price');

  // wipe açaí existing options first
  let wiped = 0;
  if (s.wipeFirst) {
    const existing = await getJSON('/product_option_groups?product_id=in.(' + encodeURIComponent(bora.map(b => '"' + b.id + '"').join(',')) + ')&select=id');
    wiped = existing.length;
    if (COMMIT && existing.length) { await delIn('product_option_items', 'group_id', existing.map(g => g.id)); await delIn('product_option_groups', 'id', existing.map(g => g.id)); }
  }

  // generate (Bora-driven; skip McD "(Grande)" — colapso)
  const groups = [], items = []; let attached = 0;
  for (const b of bora) {
    if (s.collapseGrande && isGrande(b.name)) continue;
    const g = byNorm.get(norm(b.name)); if (!g) continue;
    attached++;
    g.groups.forEach((grp, gi) => {
      const gid = b.id + '-g' + gi;
      groups.push({ id: gid, product_id: b.id, name: grp.name || 'Opções', description: null, is_required: grp.min > 0, min_choices: grp.min, max_choices: grp.max || Math.max(1, grp.min), sort_order: gi });
      grp.items.forEach((it, ii) => { items.push({ id: gid + '-i' + ii, group_id: gid, name: it.n || ('Opção ' + (ii + 1)), price_add: round2(it.pi * s.mult), is_available: true, sort_order: ii }); });
    });
  }

  let ins = { ok: 0, fail: 0, errs: [] }, insI = { ok: 0, fail: 0, errs: [] };
  if (COMMIT) { ins = await postBatch('product_option_groups', groups); insI = await postBatch('product_option_items', items); }

  // McD collapse: delete "(Grande)" products
  let deleted = 0; const grandes = s.collapseGrande ? bora.filter(b => isGrande(b.name)) : [];
  if (s.collapseGrande) { deleted = grandes.length; if (COMMIT) await delIn('products', 'id', grandes.map(b => b.id)); }

  console.log('### ' + s.name + (COMMIT ? ' [COMMIT]' : ' [DRY]') + ' :: boraProd=' + bora.length + ' attached=' + attached +
    ' GRUPOS=' + groups.length + ' ITEMS=' + items.length +
    (s.wipeFirst ? (' | wipedAntigos=' + wiped) : '') +
    (s.collapseGrande ? (' | grandeDelete=' + deleted) : '') +
    (COMMIT ? (' || insG.ok=' + ins.ok + ' fail=' + ins.fail + ' insI.ok=' + insI.ok + ' fail=' + insI.fail) : ''));
  if (ins.errs.length) console.log('   grpErrs=' + JSON.stringify(ins.errs));
  if (insI.errs.length) console.log('   itemErrs=' + JSON.stringify(insI.errs));
}

(async () => {
  console.log('MODE=' + (COMMIT ? 'COMMIT' : 'DRY-RUN') + (ONLY ? (' STORE=' + ONLY) : ' ALL'));
  for (const s of STORES) { if (ONLY && s.key !== ONLY) continue; try { await processStore(s); } catch (e) { console.error('### ' + s.name + ' ERRO: ' + e.message); } await sleep(1000); }
  console.log('DONE');
})();

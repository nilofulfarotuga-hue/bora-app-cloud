#!/usr/bin/env node
// Continente full catalog scraper → Supabase RPC bora_scraper_insert_batch
// Usage: node continente-full-scraper.js [start_index]

const https = require('https');
const zlib = require('zlib');
const fs = require('fs');
const path = require('path');

const ANON = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im9qeWtwendxcnR1c2ZlYWt6cm5hIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzMwMDA3MjgsImV4cCI6MjA4ODU3NjcyOH0.-yrhHFZV4bfjBagI5W-c1AvmP8Xkzs1kf2xuxPwdBh4';
const SB_HOST = 'ojykpzwqrtusfeakzrna.supabase.co';
const LOG_FILE = path.resolve(__dirname, '..', 'tmp', 'scrape', 'progress.log');
const STATE_FILE = path.resolve(__dirname, '..', 'tmp', 'scrape', 'state.json');
const RATE_MS = 2500;
const TODAY = '2026-04-21';
const UA = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/120.0';

fs.mkdirSync(path.dirname(LOG_FILE), {recursive: true});

function log(msg) {
  const ts = new Date().toISOString().slice(11,19);
  const line = `[${ts}] ${msg}`;
  console.log(line);
  fs.appendFileSync(LOG_FILE, line + '\n');
}

function get(url) {
  return new Promise((res, rej) => {
    const u = new URL(url);
    const req = https.get({host: u.host, path: u.pathname + u.search, headers: {'User-Agent': UA, 'Accept': 'text/html', 'Accept-Language': 'pt-PT', 'Accept-Encoding': 'gzip'}, timeout: 30000},
      r => { const bufs = []; r.on('data', c => bufs.push(c)); r.on('end', () => { let b = Buffer.concat(bufs); if (r.headers['content-encoding'] === 'gzip') { try { b = zlib.gunzipSync(b); } catch {} } res({status: r.statusCode, body: b.toString('utf8')}); }); });
    req.on('error', rej); req.on('timeout', () => { req.destroy(); rej(new Error('timeout')); });
  });
}

function rpc(fn, payload) {
  return new Promise((res, rej) => {
    const body = JSON.stringify(payload);
    const req = https.request({host: SB_HOST, path: '/rest/v1/rpc/' + fn, method: 'POST', headers: {'Content-Type': 'application/json', 'Content-Length': Buffer.byteLength(body), apikey: ANON, Authorization: 'Bearer ' + ANON}, timeout: 30000},
      r => { let d = ''; r.on('data', c => d += c); r.on('end', () => res({status: r.statusCode, body: d})); });
    req.on('error', rej); req.on('timeout', () => { req.destroy(); rej(new Error('rpc-timeout')); });
    req.write(body); req.end();
  });
}

const sleep = ms => new Promise(r => setTimeout(r, ms));

const HTML_ENT = {'&quot;':'"','&amp;':'&','&lt;':'<','&gt;':'>','&eacute;':'é','&atilde;':'ã','&aacute;':'á','&oacute;':'ó','&ccedil;':'ç','&uacute;':'ú','&iacute;':'í','&otilde;':'õ','&Eacute;':'É','&Aacute;':'Á','&Oacute;':'Ó','&agrave;':'à','&ecirc;':'ê','&acirc;':'â','&ocirc;':'ô','&uuml;':'ü','&euro;':'€','&nbsp;':' ','&mdash;':'—','&ndash;':'–'};
const dh = s => s.replace(/&#(\d+);/g, (_, n) => String.fromCharCode(+n)).replace(/&[a-zA-Z]+;/g, m => HTML_ENT[m] || m);

function mapTx(catPath) {
  const q = (catPath || '').toLowerCase();
  if (/talho|frango|peru|porco|bovino|vitela|cabrito|borrego|pato|coelho/.test(q)) return {tx:'Talho', rt:'Talho'};
  if (/peixaria|peixe|marisco|bacalhau|salm|polvo|lulas|sushi|sashimi/.test(q)) return {tx:'Peixaria', rt:'Peixaria'};
  if (/charcutaria|queijo|enchid|fiambre|presunto|chouri|salsich/.test(q)) return {tx:'Charcutaria & Queijos', rt:'Charcutaria'};
  if (/lat[ií]c[ií]ni|iogurt|leite|ovos|manteiga|natas/.test(q)) return {tx:'Laticínios & Ovos', rt:'Laticínios'};
  if (/padaria|pastelaria|p[aã]o|bolo/.test(q)) return {tx:'Padaria & Pastelaria', rt:'Padaria'};
  if (/frutas|legumes|horti|verdura|salada/.test(q)) return {tx:'Frutas & Legumes', rt:'Frutas & Legumes'};
  if (/congelad/.test(q)) return {tx:'Congelados', rt:'Congelados'};
  if (/vinho|gin|whisky|espirit|licor|champanh|espumant|rum|vodka|aguard|porto/.test(q)) return {tx:'Vinhos & Espirituosas', rt:'Bebidas'};
  if (/bebidas|[aá]gua|sumo|refrigerant|caf[eé]|ch[aá]|cerveja|smoothie/.test(q)) return {tx:'Bebidas', rt:'Bebidas'};
  if (/bio|saud[aá]vel|org[aâ]n|vegan|vegetarian/.test(q)) return {tx:'Bio & Saudável', rt:'Bio'};
  if (/bebe|fralda|boi[aã]o|infantil|papinha/.test(q)) return {tx:'Bebé', rt:'Bebé'};
  if (/animais|ra[cç][aã]o|gato|c[aã]o|pet/.test(q)) return {tx:'Animais', rt:'Animais'};
  if (/fitness|prote[ií]na|suplement|energ[eé]tic/.test(q)) return {tx:'Fitness & Proteínas', rt:'Fitness'};
  if (/pequeno-almo|cereais|granola|m[uü]esli|compota|marmelada/.test(q)) return {tx:'Pequenos-Almoços', rt:'Pequenos-Almoços'};
  if (/snack|chocolate|bolacha|biscoit|rebu[cç]ad|gomas|aperit|pipocas/.test(q)) return {tx:'Snacks', rt:'Snacks'};
  if (/conservas|at[uú]m|sardinha/.test(q)) return {tx:'Conservas', rt:'Conservas'};
  if (/sa[uú]de|bem-estar|farm[aá]|v[iií]tamina/.test(q)) return {tx:'Saúde & Bem-Estar', rt:'Saúde'};
  if (/festa|ocasi[oõ]|decora/.test(q)) return {tx:'Festa & Ocasiões', rt:'Festa'};
  if (/pronto a comer|refei[cç][oõ]es|take away|take-away/.test(q)) return {tx:'Pronto a Comer', rt:'Pronto a Comer'};
  if (/beleza|higiene pessoal|cabelo|sab[aã]o|creme|desodori|perfum|maquilh|higiene/.test(q)) return {tx:'Higiene Pessoal', rt:'Higiene Pessoal'};
  if (/limpeza|deterg|lixivia|lava/.test(q)) return {tx:'Higiene do Lar', rt:'Limpeza'};
  if (/mercearia|arroz|massa|[oó]leo|azeite|a[cç][uú]car|sal|farinha|mel|molho/.test(q)) return {tx:'Mercearia', rt:'Mercearia'};
  return {tx:'Outros', rt:'Outros'};
}

function parsePage(html) {
  const imps = [...html.matchAll(/data-product-tile-impression='([^']+)'/g)];
  const out = [];
  for (const m of imps) {
    let i; try { i = JSON.parse(dh(m[1])); } catch { continue; }
    if (!i.id) continue;
    const ni = html.indexOf('data-product-tile-impression', m.index + 10);
    const block = html.slice(m.index, (ni > 0 ? ni : m.index + 8000));
    const im = block.match(new RegExp('/dw/image/v2/BDVS_PRD/on/demandware\\.static/-/Sites-col-master-catalog/default/(dw[a-f0-9]{8}/images/col/\\d+/' + i.id + '-[\\w-]+\\.jpg)'));
    const kg = /€\/kg|&euro;\/kg/.test(block);
    out.push({pid: i.id, name: i.name, price: i.price, brand: i.brand || null, cat: i.category || '', unit: kg ? 'kg' : 'un', img: im ? im[1] : null});
  }
  return out;
}

const CDN = 'https://www.continente.pt/dw/image/v2/BDVS_PRD/on/demandware.static/-/Sites-col-master-catalog/default/';

async function scrapeSection(sectionPath) {
  const all = new Map();
  let start = 0, page = 0, repeats = 0;
  while (page < 60) {
    page++;
    try {
      const r = await get(`https://www.continente.pt${sectionPath}?start=${start}&sz=36`);
      if (r.status !== 200) { log(`  ${sectionPath} p${page} status=${r.status}`); break; }
      const tiles = parsePage(r.body);
      if (tiles.length === 0) break;
      let nc = 0;
      for (const t of tiles) if (!all.has(t.pid)) { all.set(t.pid, t); nc++; }
      if (nc === 0) { if (++repeats >= 2) break; } else repeats = 0;
      start += 36;
    } catch (e) { log(`  ${sectionPath} p${page} ERR ${e.message}`); break; }
    await sleep(RATE_MS);
  }
  return [...all.values()];
}

async function pushBatch(tiles) {
  const items = tiles.filter(t => t.price != null && t.pid).map(t => {
    const tx = mapTx(t.cat);
    return {
      id: 'cnt-' + t.pid,
      restaurant_id: 'continente-guarda',
      name: t.name,
      price: t.price,
      unit: t.unit,
      category: tx.rt,
      category_root: tx.rt,
      taxonomy_section: tx.tx,
      photo_url: t.img ? (CDN + t.img + '?sw=280&sh=280') : null,
      source: 'continente_scrape_' + TODAY,
      brand_mid: t.brand,
      description: t.cat
    };
  });
  let ins = 0, sk = 0;
  for (let i = 0; i < items.length; i += 100) {
    const chunk = items.slice(i, i + 100);
    try {
      const r = await rpc('bora_scraper_insert_batch', {items: chunk});
      const j = JSON.parse(r.body);
      ins += (j[0]?.inserted_count || 0);
      sk += (j[0]?.skipped_count || 0);
    } catch (e) { log(`  RPC ERR: ${e.message}`); }
  }
  return {inserted: ins, skipped: sk, total: items.length};
}

// Section list (depth 2-3 of /frescos/ + top-level of other branches) — grocery-relevant only
const SECTIONS = [
  '/frescos/talho/',
  '/frescos/peixaria/',
  '/frescos/charcutaria/',
  '/frescos/laticinios/',
  '/frescos/frutas-e-legumes/',
  '/frescos/padaria-e-pastelaria/',
  '/frescos/pronto-a-comer/',
  '/frescos/sushi-e-sashimi/',
  '/frescos/queijos/',
  '/mercearia/',
  '/mercearia/arroz-massa-e-leguminosas/',
  '/mercearia/azeite-oleo-e-vinagre/',
  '/mercearia/especiarias-e-condimentos/',
  '/mercearia/molhos-e-ervas/',
  '/mercearia/conservas/',
  '/mercearia/sopas-e-caldos/',
  '/mercearia/enlatados/',
  '/laticinios-e-ovos/',
  '/laticinios-e-ovos/ovos/',
  '/laticinios-e-ovos/iogurtes/',
  '/laticinios-e-ovos/leite/',
  '/laticinios-e-ovos/queijos/',
  '/laticinios-e-ovos/manteigas-margarinas-e-cremes/',
  '/laticinios-e-ovos/bebidas-vegetais/',
  '/congelados/',
  '/congelados/carne-congelada/',
  '/congelados/peixe-congelado/',
  '/congelados/legumes-congelados/',
  '/congelados/pizza-e-massas-congeladas/',
  '/congelados/gelados-e-sobremesas-congeladas/',
  '/congelados/pratos-preparados-congelados/',
  '/bebidas-e-garrafeira/',
  '/bebidas-e-garrafeira/aguas/',
  '/bebidas-e-garrafeira/sumos-e-refrigerantes/',
  '/bebidas-e-garrafeira/cervejas/',
  '/bebidas-e-garrafeira/vinhos/',
  '/bebidas-e-garrafeira/bebidas-espirituosas/',
  '/bebidas-e-garrafeira/cafes-e-chas/',
  '/bebidas-e-garrafeira/bebidas-vegetais/',
  '/bebe/',
  '/bebe/alimentacao-bebe/',
  '/bebe/higiene-bebe/',
  '/bebe/fraldas-e-toalhitas/',
  '/animais/',
  '/animais/cao/',
  '/animais/gato/',
  '/bio-e-saudavel/',
  '/beleza-e-higiene/',
  '/beleza-e-higiene/higiene-corporal/',
  '/beleza-e-higiene/cuidados-capilares/',
  '/beleza-e-higiene/cuidados-de-rosto/',
  '/beleza-e-higiene/cuidados-femininos/',
  '/beleza-e-higiene/dentifricos-e-bochechos/',
  '/limpeza/',
  '/limpeza/deteregentes-maquina-roupa/',
  '/limpeza/lavagem-loica/',
  '/limpeza/limpeza-casa-de-banho/',
  '/limpeza/limpeza-cozinha/',
  '/limpeza/papel-higienico-e-rolos-de-cozinha/'
];

async function main() {
  const startIdx = parseInt(process.argv[2] || '0', 10);
  log(`=== START scraper (from idx=${startIdx}, total sections=${SECTIONS.length}) ===`);
  const state = {processed: [], totals: {scraped: 0, inserted: 0, skipped: 0}, startedAt: new Date().toISOString()};
  const tRun = Date.now();
  for (let i = startIdx; i < SECTIONS.length; i++) {
    const sec = SECTIONS[i];
    const t0 = Date.now();
    try {
      const tiles = await scrapeSection(sec);
      const r = await pushBatch(tiles);
      const dt = ((Date.now() - t0) / 1000).toFixed(1);
      log(`[${i+1}/${SECTIONS.length}] ${sec} scraped=${tiles.length} ins=${r.inserted} skip=${r.skipped} ${dt}s`);
      state.processed.push({section: sec, scraped: tiles.length, inserted: r.inserted, skipped: r.skipped, secs: +dt});
      state.totals.scraped += tiles.length;
      state.totals.inserted += r.inserted;
      state.totals.skipped += r.skipped;
      fs.writeFileSync(STATE_FILE, JSON.stringify(state, null, 2));
    } catch (e) {
      log(`[${i+1}] ${sec} FATAL ${e.message}`);
    }
    await sleep(RATE_MS);
  }
  const totalMin = ((Date.now() - tRun) / 60000).toFixed(1);
  log(`=== DONE totals=${JSON.stringify(state.totals)} runtime=${totalMin}min ===`);
}

main().catch(e => log(`FATAL ${e.message}`));

// Glovo Walker — Continente Guarda (storeAddressId 470732)
// Walks every deep-link path and collects all PRODUCT_TILEs.
// No BD writes. No price collection. Only: name, imageUrl, category, subsection.
// Rate 4.5s ±0.8s. Stop on 429. Checkpoint every 20 paths.

const fs = require('fs');
const path = require('path');

const TMP = "C:/Users/danil/Desktop/projetosflutter/bora_app/.claude/.ai/tmp";
const TREE_FILE   = path.join(TMP, "glovo_tree.json");
const OUT_FILE    = path.join(TMP, "glovo_catalog.json");
const STATE_FILE  = path.join(TMP, "glovo_walk_state.json");
const LOG_FILE    = path.join(TMP, "glovo_walk.log");

const STORE_ID   = "295687";
const ADDR_ID    = "470732";
const CITY       = "GRD";
const LAT        = "40.5373";
const LNG        = "-7.2674";
const BASE       = `https://api.glovoapp.com/v4/stores/${STORE_ID}/addresses/${ADDR_ID}/content/main?nodeType=DEEP_LINK&link=`;

function log(msg){
  const line = `[${new Date().toISOString()}] ${msg}`;
  console.log(line);
  fs.appendFileSync(LOG_FILE, line + "\n");
}
function sleep(ms){ return new Promise(r=>setTimeout(r, ms)); }
function jitterSleep(){ const ms = 4500 + Math.floor(Math.random()*1600) - 800; return sleep(Math.max(3500,ms)); }

function headers(){
  return {
    "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/131.0.0.0 Safari/537.36",
    "Accept": "application/json, text/plain, */*",
    "Accept-Language": "pt-PT,pt;q=0.9",
    "glovo-api-version": "14",
    "glovo-app-platform": "web",
    "glovo-app-type": "customer",
    "glovo-location-country-code": "PT",
    "glovo-location-city-code": CITY,
    "glovo-location-latitude": LAT,
    "glovo-location-longitude": LNG,
    "glovo-language-code": "pt",
    "Origin": "https://glovoapp.com",
    "Referer": "https://glovoapp.com/pt/pt/guarda/stores/continente-grd1",
  };
}

async function fetchPath(link){
  const url = BASE + encodeURIComponent(link).replace(/%2F/g,"/");
  try {
    const r = await fetch(url, { headers: headers() });
    const text = await r.text();
    return { status: r.status, text };
  } catch(e){ return { status: 0, err: e.message }; }
}

function extractProducts(json, link){
  // walk tree
  const out = [];
  let category = json?.data?.title || null;
  function walk(node, subGridTitle){
    if (!node) return;
    if (Array.isArray(node)) return node.forEach(x=>walk(x, subGridTitle));
    if (typeof node !== 'object') return;
    if (node.type === 'PRODUCT_TILE' && node.data){
      const d = node.data;
      out.push({
        external_id: String(d.externalId || d.storeProductId || d.id || ""),
        name: d.name || null,
        image_url: d.imageUrl || null,
        price_glovo: d.price ?? d.priceInfo?.amount ?? null,
        category,
        subsection: subGridTitle || null,
        link,
      });
      return;
    }
    if (node.type === 'GRID' && node.data){
      const sub = node.data.title || null;
      for (const el of (node.data.elements || [])) walk(el, sub);
      return;
    }
    for (const k of Object.keys(node)) walk(node[k], subGridTitle);
  }
  walk(json, null);
  return out;
}

async function main(){
  const tree = JSON.parse(fs.readFileSync(TREE_FILE, "utf8"));
  // Walk only paths that END in a category (-c.<id>) — those are the leaf product grids
  const allPaths = tree.fullPaths.filter(p => /-c\.\d+$/.test(p));
  log(`total paths to walk: ${allPaths.length}`);

  // Resume state
  let state = { completed: [], products: {}, errors: [] };
  if (fs.existsSync(STATE_FILE)) {
    try { state = JSON.parse(fs.readFileSync(STATE_FILE, "utf8")); log(`resumed: ${state.completed.length} done, ${Object.keys(state.products).length} products collected`); } catch(e){}
  }
  const done = new Set(state.completed);

  let n429 = 0;
  for (let i = 0; i < allPaths.length; i++){
    const link = allPaths[i];
    if (done.has(link)) continue;
    const r = await fetchPath(link);
    if (r.status === 429){
      n429++;
      log(`429 on ${link} — STOP (run later with backoff)`);
      break;
    }
    if (r.status !== 200){
      log(`[${i+1}/${allPaths.length}] ${link} → HTTP ${r.status} ${r.err||""}`);
      state.errors.push({ link, status: r.status, err: r.err });
      await jitterSleep();
      continue;
    }
    let j; try { j = JSON.parse(r.text); } catch(e){ log(`parse err ${link}`); state.errors.push({link, err:"parse"}); await jitterSleep(); continue; }
    const prods = extractProducts(j, link);
    for (const p of prods){
      if (!p.external_id) continue;
      // keep first-seen (Glovo sometimes places same product in multiple sections)
      if (!state.products[p.external_id]) state.products[p.external_id] = p;
    }
    state.completed.push(link);
    if ((i+1) % 10 === 0 || (i+1) === allPaths.length){
      log(`[${i+1}/${allPaths.length}] done=${state.completed.length} products=${Object.keys(state.products).length}`);
    }
    if ((i+1) % 20 === 0){
      fs.writeFileSync(STATE_FILE, JSON.stringify(state));
    }
    await jitterSleep();
  }
  fs.writeFileSync(STATE_FILE, JSON.stringify(state));

  // Final catalog file
  const products = Object.values(state.products);
  fs.writeFileSync(OUT_FILE, JSON.stringify({
    store: "continente-grd1",
    storeId: STORE_ID,
    addressId: ADDR_ID,
    city: CITY,
    walkedPaths: state.completed.length,
    totalPaths: allPaths.length,
    errors: state.errors.length,
    total_products: products.length,
    products,
  }, null, 2));
  log(`DONE. walked=${state.completed.length}/${allPaths.length} errors=${state.errors.length} unique_products=${products.length}`);
}

main().catch(e=>{ log("FATAL: "+e.message+"\n"+e.stack); process.exit(1); });

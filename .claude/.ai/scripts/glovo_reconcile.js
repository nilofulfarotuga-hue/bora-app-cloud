// Glovo × Continente Guarda — Reconcile (Fase 1b)
// For each Glovo product from glovo_catalog.json:
//   - Match BD by LOWER(name) in restaurant_id='continente-guarda'
//   - If MATCH → UPDATE photo_url (from Glovo) and price (from Continente.pt, if PID resolvable and BD stale)
//   - If NO MATCH → INSERT with needs_review=true, source tag, price=null (or Continente price if discoverable)
// Rules:
//   - Name-guard ≥ 0.3 for Continente price trust
//   - Rate limit 4.5s ±jitter on Continente scrapes; stop on 429
//   - Checkpoint every 200 processed
//   - BD writes via Supabase REST (PATCH/POST)
//   - source = 'glovo-continente-guarda-2026-04-21'

const fs    = require('fs');
const path  = require('path');
const https = require('https');
const zlib  = require('zlib');

const ROOT = "C:/Users/danil/Desktop/projetosflutter/bora_app";
const TMP  = path.join(ROOT, ".claude/.ai/tmp");
const CATALOG_FILE = path.join(TMP, "glovo_catalog.json");
const STATE_FILE   = path.join(TMP, "glovo_reconcile_state.json");
const LOG_FILE     = path.join(TMP, "glovo_reconcile.log");
const REPORT_LOG   = path.join(TMP, "glovo_reconcile_actions.jsonl");
const SUMMARY_FILE = path.join(TMP, "glovo_reconcile_summary.json");

const SOURCE_TAG = "glovo-continente-guarda-2026-04-21";
const TODAY_ISO  = "2026-04-21";

// Supabase
const SUPABASE_URL = "https://ojykpzwqrtusfeakzrna.supabase.co";
const SERVICE_KEY  = fs.readFileSync(path.join(ROOT, "scripts/scraper/.env"), "utf8")
  .split("\n").find(l=>l.startsWith("SUPABASE_SERVICE_KEY="))
  .slice("SUPABASE_SERVICE_KEY=".length).trim();

// Continente scraping
const UA = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36";
const HOST = "www.continente.pt";
const PATH_BASE = "/on/demandware.store/Sites-continente-Site/pt_PT/Product-Show?pid=";

const SKIP_PRICE_REFETCH_IF_UPDATED_TODAY = true; // optimization: if BD row updated today, trust its price
const DRY_RUN = process.argv.includes("--dry-run");
const LIMIT = (() => { const i = process.argv.indexOf("--limit"); return i>0 ? parseInt(process.argv[i+1],10) : 0; })();

// ---------- utils ----------
function log(msg){ const l = `[${new Date().toISOString()}] ${msg}`; console.log(l); fs.appendFileSync(LOG_FILE, l+"\n"); }
function sleep(ms){ return new Promise(r=>setTimeout(r, ms)); }
function jitter(){ const ms = 4500 + Math.floor(Math.random()*1600)-800; return sleep(Math.max(3500,ms)); }
function logAction(obj){ fs.appendFileSync(REPORT_LOG, JSON.stringify(obj)+"\n"); }

function decodeEnt(s){
  if(!s) return s;
  return s.replace(/&#(\d+);/g,(_,n)=>String.fromCharCode(+n))
    .replace(/&amp;/g,"&").replace(/&quot;/g,'"').replace(/&apos;/g,"'")
    .replace(/&lt;/g,"<").replace(/&gt;/g,">")
    .replace(/&atilde;/g,"ã").replace(/&ecirc;/g,"ê").replace(/&ccedil;/g,"ç")
    .replace(/&oacute;/g,"ó").replace(/&iacute;/g,"í").replace(/&aacute;/g,"á")
    .replace(/&eacute;/g,"é").replace(/&uacute;/g,"ú").replace(/&ocirc;/g,"ô")
    .replace(/&acirc;/g,"â").replace(/&otilde;/g,"õ");
}

// Strip trailing "(emb. ...)" with balanced parens. Glovo often adds embalagem info
// that BD rows never contain. Matching on a normalized key prevents duplicates.
function normalizeName(s){
  if (!s) return s;
  let n = s.trim();
  const idx = n.lastIndexOf("(emb.");
  if (idx < 0) return n;
  const prefix = n.slice(0, idx).trim();
  const suffix = n.slice(idx);
  let depth = 0;
  for (let i = 0; i < suffix.length; i++){
    if (suffix[i] === '(') depth++;
    else if (suffix[i] === ')') depth--;
    if (depth === 0 && i === suffix.length - 1) return prefix;
    if (depth < 0) return n;
  }
  return n;
}

function nameMatchRatio(bdName, siteName){
  const norm = s => (s||"").toLowerCase()
    .normalize("NFD").replace(/[̀-ͯ]/g,"")
    .split(/\s+/).filter(Boolean).map(w=>w.slice(0,4));
  const a = norm(bdName), b = norm(siteName);
  if (!a.length) return 0;
  const setB = new Set(b);
  const shared = a.filter(x=>setB.has(x)).length;
  return shared / a.length;
}

function rankId(id){
  if (!id) return 5;
  if (/^cnt-\d+$/.test(id)) return 1;
  if (/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(id)) return 2;
  if (id.startsWith("cm-")) return 3;
  if (id.startsWith("prod_")) return 4;
  return 3;
}

function pickPidFromRow(row){
  if (row.id && /^cnt-(\d+)$/.test(row.id)) return RegExp.$1;
  if (row.photo_url){
    const m = row.photo_url.match(/\/(\d{7})-/);
    if (m) return m[1];
  }
  return null;
}

// ---------- Supabase REST (with retry) ----------
function _sbRequestOnce(method, pth, body){
  return new Promise((resolve)=>{
    const u = new URL(SUPABASE_URL + pth);
    const headers = {
      "apikey": SERVICE_KEY,
      "Authorization": "Bearer " + SERVICE_KEY,
      "Content-Type": "application/json",
      "Accept": "application/json",
      "Accept-Encoding": "gzip",
      "Prefer": method === "GET" ? "count=exact" : "return=representation",
    };
    const req = https.request({host:u.host, port:443, path:u.pathname+u.search, method, headers, timeout:30000}, (res)=>{
      const chunks=[];
      const stream = res.headers["content-encoding"]==="gzip" ? res.pipe(zlib.createGunzip()) : res;
      stream.on("data",c=>chunks.push(c));
      stream.on("end",()=>{
        const text = Buffer.concat(chunks).toString("utf8");
        let data = null; try { data = text ? JSON.parse(text) : null; } catch(e){}
        resolve({status:res.statusCode, body:data, raw:text});
      });
      stream.on("error",e=>resolve({status:res.statusCode, err:e.message}));
    });
    req.on("error",e=>resolve({status:null, err:e.code||e.message}));
    req.on("timeout",()=>{req.destroy();resolve({status:null, err:"timeout"});});
    if (body) req.write(typeof body==="string"?body:JSON.stringify(body));
    req.end();
  });
}

async function sbRequest(method, pth, body){
  const backoffs = [0, 2000, 5000, 10000]; // 4 attempts total
  for (let i = 0; i < backoffs.length; i++){
    if (backoffs[i] > 0) await sleep(backoffs[i]);
    const r = await _sbRequestOnce(method, pth, body);
    // Retry on null status (network), 5xx, 429
    if (r.status == null || (r.status >= 500 && r.status < 600) || r.status === 429){
      if (i < backoffs.length - 1){ log(`sb retry ${i+1}/${backoffs.length-1} status=${r.status} err=${r.err||""} path=${pth.slice(0,80)}`); continue; }
    }
    return r;
  }
  return { status: null, err: "max-retries" };
}

// ---------- Continente scraping ----------
function _scrape(host, pth, cookie){
  return new Promise((resolve)=>{
    const headers = {
      "User-Agent": UA,
      "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
      "Accept-Language": "pt-PT,pt;q=0.9,en;q=0.8",
      "Accept-Encoding": "gzip, deflate",
      "Connection": "keep-alive",
      "Upgrade-Insecure-Requests": "1",
    };
    if (cookie) headers["Cookie"] = cookie;
    const req = https.request({host, port:443, path:pth, method:"GET", headers, timeout:25000}, (res)=>{
      const chunks=[];
      const stream = (res.headers["content-encoding"]==="gzip") ? res.pipe(zlib.createGunzip())
                   : (res.headers["content-encoding"]==="deflate" ? res.pipe(zlib.createInflate()) : res);
      stream.on("data",c=>chunks.push(c));
      stream.on("end",()=>resolve({status:res.statusCode, headers:res.headers, body:Buffer.concat(chunks).toString("utf8"), err:null}));
      stream.on("error",e=>resolve({status:res.statusCode, headers:res.headers, body:"", err:"stream:"+e.message}));
    });
    req.on("error",e=>resolve({status:null, headers:{}, body:"", err:e.code||e.message}));
    req.on("timeout",()=>{req.destroy();resolve({status:null, headers:{}, body:"", err:"timeout"});});
    req.end();
  });
}

async function scrapeByPid(pid){
  let host = HOST, pth = PATH_BASE + pid, cookie = null;
  for (let hops=0; hops<5; hops++){
    const r = await _scrape(host, pth, cookie);
    if (r.err) return {status:r.status, body:"", err:r.err};
    const sc = r.headers["set-cookie"];
    if (sc){
      const jar = sc.map(x=>x.split(";")[0]).join("; ");
      cookie = cookie ? cookie + "; " + jar : jar;
    }
    if (r.status >= 300 && r.status < 400 && r.headers.location){
      const loc = r.headers.location;
      if (loc.startsWith("http")){ const u = new URL(loc); host = u.host; pth = u.pathname + (u.search||""); }
      else { pth = loc; }
      continue;
    }
    return {status:r.status, body:r.body, err:null};
  }
  return {status:null, body:"", err:"too-many-redirects"};
}

function extractPriceName(htm){
  const re = /<script[^>]*type=["']application\/ld\+json["'][^>]*>([\s\S]*?)<\/script>/gi;
  let m;
  while ((m = re.exec(htm)) !== null){
    let block = m[1].trim();
    let data; try { data = JSON.parse(block); } catch(e){ continue; }
    const arr = Array.isArray(data) ? data : [data];
    for (const d of arr){
      if (!d || typeof d !== "object") continue;
      const t = d["@type"];
      const isProduct = t === "Product" || (Array.isArray(t) && t.includes("Product"));
      if (!isProduct) continue;
      let price = null, image = null;
      const off = d.offers;
      if (off){
        if (Array.isArray(off)) price = off[0]?.price ?? off[0]?.lowPrice ?? null;
        else price = off.price ?? off.lowPrice ?? null;
      }
      if (Array.isArray(d.image)) image = d.image[0];
      else if (typeof d.image === "string") image = d.image;
      else if (d.image && typeof d.image === "object") image = d.image.url || d.image["@id"] || null;
      return { name: decodeEnt(d.name), price: price==null?null:parseFloat(price), image };
    }
  }
  return { name: null, price: null, image: null };
}

// ---------- BD ops ----------
async function findByLowerName(glovoName){
  // Match strategy: compare BD.name (LOWER) to normalized Glovo name (LOWER).
  // Glovo products often have trailing "(emb. ...)" that BD lacks — strip it first.
  const normalized = normalizeName(glovoName);
  const escaped = encodeURIComponent(normalized.replace(/%/g,"\\%").replace(/_/g,"\\_"));
  const q = `/rest/v1/products?select=id,name,price,photo_url,last_updated&restaurant_id=eq.continente-guarda&name=ilike.${escaped}&limit=20`;
  const r = await sbRequest("GET", q);
  if (r.status !== 200) return { err: r.status+" "+(r.raw||"").slice(0,150) };
  const target = normalized.toLowerCase();
  const matches = (r.body||[]).filter(row => (row.name||"").toLowerCase() === target);
  return { matches, normalized };
}

async function updateProduct(id, patch){
  if (DRY_RUN) return { status: 999, body: patch, dry:true };
  const q = `/rest/v1/products?id=eq.${encodeURIComponent(id)}`;
  const body = { ...patch, updated_at: new Date().toISOString(), last_updated: new Date().toISOString() };
  return await sbRequest("PATCH", q, body);
}

async function insertProduct(row){
  if (DRY_RUN) return { status: 999, body: row, dry:true };
  const q = `/rest/v1/products`;
  return await sbRequest("POST", q, row);
}

// ---------- main reconcile ----------
async function main(){
  if (!fs.existsSync(CATALOG_FILE)){
    log(`FATAL: catalog not found at ${CATALOG_FILE}. Run glovo_walk.js first.`);
    process.exit(1);
  }
  const catalog = JSON.parse(fs.readFileSync(CATALOG_FILE, "utf8"));
  log(`catalog loaded: ${catalog.total_products} products, walked ${catalog.walkedPaths}/${catalog.totalPaths} paths, errors=${catalog.errors}`);

  // resume
  let state = { processed: [], nUpdated: 0, nInserted: 0, nSkipped: 0, nNoPriceFetch: 0, nNameGuardFail: 0, n429: 0, errors: [] };
  if (fs.existsSync(STATE_FILE)){
    try { state = JSON.parse(fs.readFileSync(STATE_FILE,"utf8")); log(`resumed: processed=${state.processed.length} upd=${state.nUpdated} ins=${state.nInserted} skip=${state.nSkipped}`); } catch(e){}
  }
  const processedSet = new Set(state.processed);

  const products = catalog.products;
  const total = LIMIT > 0 ? Math.min(LIMIT, products.length) : products.length;
  log(`processing ${total}${DRY_RUN?" (DRY-RUN)":""}`);

  for (let i = 0; i < total; i++){
    const g = products[i];
    const key = g.external_id;
    if (processedSet.has(key)) continue;
    if (!g.name || !g.image_url){ state.nSkipped++; state.processed.push(key); continue; }

    try {
      // Find BD matches
      const fres = await findByLowerName(g.name);
      if (fres.err){
        state.errors.push({ gid:key, step:"find", err:fres.err, ts:new Date().toISOString() });
        log(`[${i+1}/${total}] FIND ERR "${g.name.slice(0,40)}" → ${fres.err}`);
        // Do NOT push to processed — will retry on next run. But avoid infinite loop
        // if Supabase is truly down: break after 5 consecutive errors.
        state.consecutiveFindErrors = (state.consecutiveFindErrors||0) + 1;
        if (state.consecutiveFindErrors >= 5){
          log(`ABORT: ${state.consecutiveFindErrors} consecutive find errors — Supabase likely down. STOP.`);
          break;
        }
        await sleep(3000);
        continue;
      }
      state.consecutiveFindErrors = 0;

      if (fres.matches.length > 0){
        // Rank matches by id quality
        fres.matches.sort((a,b)=>rankId(a.id)-rankId(b.id));
        const best = fres.matches[0];
        const pid = pickPidFromRow(best);

        let newPrice = null;
        let priceFetchResult = "not-attempted";
        const wasUpdatedToday = typeof best.last_updated === "string" && best.last_updated.startsWith(TODAY_ISO);

        if (pid && !(SKIP_PRICE_REFETCH_IF_UPDATED_TODAY && wasUpdatedToday)){
          const scr = await scrapeByPid(pid);
          if (scr.status === 429){ state.n429++; log("429 on Continente → STOP"); break; }
          if (scr.err || scr.status !== 200){
            priceFetchResult = "http-err:"+(scr.err||scr.status);
          } else {
            const info = extractPriceName(scr.body);
            if (info.price == null){ priceFetchResult = "no-jsonld"; }
            else {
              const ratio = nameMatchRatio(best.name, info.name);
              if (ratio < 0.3){
                state.nNameGuardFail++;
                priceFetchResult = `name-guard-fail ratio=${ratio.toFixed(2)} site="${(info.name||"").slice(0,50)}"`;
              } else {
                newPrice = info.price;
                priceFetchResult = `ok ratio=${ratio.toFixed(2)}`;
              }
            }
          }
          await jitter();
        } else if (!pid) {
          priceFetchResult = "no-pid";
          state.nNoPriceFetch++;
        } else {
          priceFetchResult = "skipped-recent";
        }

        const patch = { photo_url: g.image_url };
        if (newPrice != null && Math.abs((best.price||0) - newPrice) > 0.01) patch.price = newPrice;

        const upd = await updateProduct(best.id, patch);
        if (upd.status >= 200 && upd.status < 300){
          state.nUpdated++;
          logAction({ action:"update", gid:key, bd_id:best.id, pid, old_price:best.price, new_price:patch.price ?? best.price, price_fetch: priceFetchResult, name:g.name });
        } else if (upd.dry){
          state.nUpdated++;
          logAction({ action:"update-dry", gid:key, bd_id:best.id, patch, price_fetch:priceFetchResult, name:g.name });
        } else {
          state.errors.push({ gid:key, step:"update", status:upd.status, raw:(upd.raw||"").slice(0,150) });
          log(`UPDATE ERR ${best.id} → ${upd.status}`);
        }
      } else {
        // INSERT — no match
        const row = {
          id: `glv-${key}`,
          restaurant_id: "continente-guarda",
          name: g.name,
          photo_url: g.image_url,
          price: null,
          category: g.subsection || g.category || null,
          is_available: true,
          source: SOURCE_TAG,
          needs_review: true,
          last_updated: new Date().toISOString(),
        };
        const ins = await insertProduct(row);
        if (ins.status >= 200 && ins.status < 300){
          state.nInserted++;
          logAction({ action:"insert", gid:key, bd_id:row.id, name:g.name, category:row.category });
        } else if (ins.dry){
          state.nInserted++;
          logAction({ action:"insert-dry", gid:key, row });
        } else {
          state.errors.push({ gid:key, step:"insert", status:ins.status, raw:(ins.raw||"").slice(0,150) });
          log(`INSERT ERR ${row.id} → ${ins.status} ${(ins.raw||"").slice(0,100)}`);
        }
      }
    } catch(e){
      log(`EXC ${key}: ${e.message}`);
      state.errors.push({ gid:key, step:"exc", err:e.message });
    }

    state.processed.push(key);

    // checkpoint every 200
    if (state.processed.length % 200 === 0){
      fs.writeFileSync(STATE_FILE, JSON.stringify(state));
      log(`CHECKPOINT ${state.processed.length}/${total}: updated=${state.nUpdated} inserted=${state.nInserted} skipped=${state.nSkipped} name-guard-fail=${state.nNameGuardFail} errors=${state.errors.length}`);
    }
  }

  fs.writeFileSync(STATE_FILE, JSON.stringify(state));
  const summary = {
    finished_at: new Date().toISOString(),
    total_catalog: catalog.total_products,
    processed: state.processed.length,
    updated: state.nUpdated,
    inserted: state.nInserted,
    skipped: state.nSkipped,
    no_pid_price_skipped: state.nNoPriceFetch,
    name_guard_failed: state.nNameGuardFail,
    rate_limited_429: state.n429,
    errors: state.errors.length,
    dry_run: DRY_RUN,
  };
  fs.writeFileSync(SUMMARY_FILE, JSON.stringify(summary, null, 2));
  log("DONE: " + JSON.stringify(summary));
}

main().catch(e=>{ log("FATAL "+e.message+"\n"+e.stack); process.exit(1); });

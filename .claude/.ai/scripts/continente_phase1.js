// T2 — FASE 1 Continente Price Updater (4.253 produtos, exclui prod_*)
// Regras:
//  - Name-guard ≥ 0,3 obrigatório
//  - needs_review=true se site_price < 30% bd_price
//  - UPDATE só se |Δ| > 0,01
//  - Checkpoint a cada 200 em continente_phase1_state.json
//  - Resumable via last_pid_index
//  - Rate 4,5s ±0,8s, stop em 429
//  - ZERO toque em ficheiros .dart

const https = require('https');
const zlib  = require('zlib');
const fs    = require('fs');
const path  = require('path');

const SUPABASE_URL = "https://ojykpzwqrtusfeakzrna.supabase.co";
const SERVICE_KEY  = fs.readFileSync("scripts/scraper/.env", "utf8")
  .split("\n").find(l=>l.startsWith("SUPABASE_SERVICE_KEY="))
  .slice("SUPABASE_SERVICE_KEY=".length).trim();

const UA = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36";
const HOST = "www.continente.pt";
const PATH_BASE = "/on/demandware.store/Sites-continente-Site/pt_PT/Product-Show?pid=";

const OUT_DIR       = ".claude/.ai/tmp";
const PRODUCTS_FILE = path.join(OUT_DIR, "continente_phase1_products.json");
const STATE_FILE    = path.join(OUT_DIR, "continente_phase1_state.json");
const UPDATES_LOG   = path.join(OUT_DIR, "price_updates_continente.json");
const REVIEW_LOG    = path.join(OUT_DIR, "continente_phase1_review.json");
const PROGRESS_LOG  = path.join(OUT_DIR, "continente_phase1_progress.log");
const ERROR_LOG     = path.join(OUT_DIR, "continente_phase1_errors.log");

fs.mkdirSync(OUT_DIR, { recursive: true });

function logProg(line){
  const ts = new Date().toISOString();
  const msg = `[${ts}] ${line}`;
  try { fs.appendFileSync(PROGRESS_LOG, msg + "\n"); } catch(e){}
  console.log(msg);
}
function logErr(line){
  const ts = new Date().toISOString();
  try { fs.appendFileSync(ERROR_LOG, `[${ts}] ${line}\n`); } catch(e){}
}

function appendJsonArrayLine(file, obj){
  // append one JSON object per line (JSONL); fast incremental write
  try { fs.appendFileSync(file, JSON.stringify(obj) + "\n"); } catch(e){ logErr("append "+file+": "+e.message); }
}

// ---------------------------------------------------------------------------
// Supabase REST helpers
// ---------------------------------------------------------------------------
function sbRequest(method, pathStr, body, range){
  return new Promise((resolve)=>{
    const u = new URL(SUPABASE_URL + pathStr);
    const headers = {
      "apikey": SERVICE_KEY,
      "Authorization": "Bearer " + SERVICE_KEY,
      "Content-Type": "application/json",
      "Accept": "application/json",
      "Accept-Encoding": "gzip",
    };
    if (range) { headers["Range"] = range; headers["Prefer"] = "count=exact"; }
    if (method !== "GET") headers["Prefer"] = "return=representation";
    const req = https.request({host:u.host, port:443, path:u.pathname+u.search, method, headers, timeout:30000}, (res)=>{
      const chunks=[];
      const stream = res.headers["content-encoding"]==="gzip" ? res.pipe(zlib.createGunzip()) : res;
      stream.on("data",c=>chunks.push(c));
      stream.on("end",()=>{
        const text = Buffer.concat(chunks).toString("utf8");
        let data = null;
        try { data = text ? JSON.parse(text) : null; } catch(e){}
        resolve({status:res.statusCode, headers:res.headers, body:data, raw:text});
      });
      stream.on("error",e=>resolve({status:res.statusCode, err:e.message}));
    });
    req.on("error",e=>resolve({status:null, err:e.code||e.message}));
    req.on("timeout",()=>{req.destroy();resolve({status:null, err:"timeout"});});
    if (body) req.write(JSON.stringify(body));
    req.end();
  });
}

async function fetchAllProducts(){
  if (fs.existsSync(PRODUCTS_FILE)){
    const cached = JSON.parse(fs.readFileSync(PRODUCTS_FILE,"utf8"));
    logProg(`loaded cached products: ${cached.length}`);
    return cached;
  }
  logProg("fetching product list from Supabase...");
  // Query with computed PID via RPC? Use REST with select + OR filter, paginate.
  // We need: id LIKE 'cnt-%' AND id ~ '^cnt-[0-9]+$'  OR  photo_url ~ '/[0-9]{7}-'
  // PostgREST doesn't support regex directly on text, but supports 'like' and the 'ilike/like/fts'.
  // Use RPC function is overkill; use execute_sql via PostgREST? No — use raw API.
  // Simpler: page through all products restaurant_id=continente-guarda is_available=true id not like prod_%
  // then compute PID locally.
  const all = [];
  const PAGE = 1000;
  let offset = 0;
  while (true){
    const q = `/rest/v1/products?select=id,name,price,photo_url&restaurant_id=eq.continente-guarda&is_available=eq.true&id=not.like.prod_%25&order=id.asc&limit=${PAGE}&offset=${offset}`;
    const r = await sbRequest("GET", q);
    if (r.status !== 200){ throw new Error("list fail: "+r.status+" "+(r.raw||"").slice(0,200)); }
    if (!r.body || !r.body.length) break;
    all.push(...r.body);
    offset += r.body.length;
    if (r.body.length < PAGE) break;
  }
  // derive PID
  const withPid = [];
  for (const p of all){
    let pid = null;
    if (p.id && /^cnt-\d+$/.test(p.id)){ pid = p.id.slice(4); }
    else if (p.photo_url){
      const m = p.photo_url.match(/\/(\d{7})-/);
      if (m) pid = m[1];
    }
    if (pid) withPid.push({ id:p.id, name:p.name, price:p.price!=null?parseFloat(p.price):null, photo_url:p.photo_url, pid });
  }
  // stable order: cnt- first, then uuid; inside each, by pid asc
  withPid.sort((a,b)=>{
    const ak = a.id.startsWith("cnt-")?0:1;
    const bk = b.id.startsWith("cnt-")?0:1;
    if (ak !== bk) return ak-bk;
    return a.pid < b.pid ? -1 : a.pid > b.pid ? 1 : 0;
  });
  fs.writeFileSync(PRODUCTS_FILE, JSON.stringify(withPid));
  logProg(`cached ${withPid.length} products → ${PRODUCTS_FILE}`);
  return withPid;
}

// ---------------------------------------------------------------------------
// Scraping
// ---------------------------------------------------------------------------
function decodeEnt(s){
  if(!s) return s;
  return s.replace(/&#(\d+);/g,(_,n)=>String.fromCharCode(+n))
    .replace(/&amp;/g,"&").replace(/&quot;/g,'"').replace(/&apos;/g,"'")
    .replace(/&lt;/g,"<").replace(/&gt;/g,">")
    .replace(/&atilde;/g,"ã").replace(/&Atilde;/g,"Ã")
    .replace(/&ecirc;/g,"ê").replace(/&Ecirc;/g,"Ê")
    .replace(/&ccedil;/g,"ç").replace(/&Ccedil;/g,"Ç")
    .replace(/&oacute;/g,"ó").replace(/&Oacute;/g,"Ó")
    .replace(/&iacute;/g,"í").replace(/&Iacute;/g,"Í")
    .replace(/&aacute;/g,"á").replace(/&Aacute;/g,"Á")
    .replace(/&eacute;/g,"é").replace(/&Eacute;/g,"É")
    .replace(/&uacute;/g,"ú").replace(/&Uacute;/g,"Ú")
    .replace(/&ocirc;/g,"ô").replace(/&Ocirc;/g,"Ô")
    .replace(/&acirc;/g,"â").replace(/&Acirc;/g,"Â")
    .replace(/&auml;/g,"ä")
    .replace(/&ntilde;/g,"ñ").replace(/&Ntilde;/g,"Ñ")
    .replace(/&otilde;/g,"õ").replace(/&Otilde;/g,"Õ");
}

function _scrapeRequest(host, pathStr, cookie){
  return new Promise((resolve)=>{
    const headers = {
      "User-Agent":UA,
      "Accept":"text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
      "Accept-Language":"pt-PT,pt;q=0.9,en;q=0.8",
      "Accept-Encoding":"gzip, deflate",
      "Connection":"keep-alive",
      "Upgrade-Insecure-Requests":"1",
    };
    if (cookie) headers["Cookie"] = cookie;
    const req = https.request({host, port:443, path:pathStr, method:"GET", headers, timeout:25000}, (res)=>{
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

async function scrape(pid){
  let host = HOST;
  let pth = PATH_BASE + pid;
  let cookie = null;
  for (let hops=0; hops<5; hops++){
    const r = await _scrapeRequest(host, pth, cookie);
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
    let data;
    try { data = JSON.parse(block); } catch(e){ continue; }
    const arr = Array.isArray(data) ? data : [data];
    for (const d of arr){
      if (!d || typeof d !== "object") continue;
      const t = d["@type"];
      const isProduct = t === "Product" || (Array.isArray(t) && t.includes("Product"));
      if (!isProduct) continue;
      const name = d.name;
      let price = null;
      let image = null;
      const off = d.offers;
      if (off && typeof off === "object"){
        if (Array.isArray(off)) price = off[0]?.price ?? off[0]?.lowPrice ?? null;
        else price = off.price ?? off.lowPrice ?? null;
      }
      if (Array.isArray(d.image)) image = d.image[0];
      else if (typeof d.image === "string") image = d.image;
      else if (d.image && typeof d.image === "object") image = d.image.url || d.image["@id"] || null;
      return { name, price, image };
    }
  }
  return { name: null, price: null, image: null };
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

function sleep(ms){ return new Promise(r=>setTimeout(r,ms)); }

// ---------------------------------------------------------------------------
// Main loop
// ---------------------------------------------------------------------------
(async () => {
  const products = await fetchAllProducts();
  const total = products.length;

  // load state
  let state = { last_index: -1, counters: { updated:0, igual:0, name_mismatch:0, not_found:0, needs_review:0, http_error:0, skipped_small_delta:0 }, started_at: new Date().toISOString() };
  if (fs.existsSync(STATE_FILE)){
    try {
      const prev = JSON.parse(fs.readFileSync(STATE_FILE,"utf8"));
      if (prev && typeof prev.last_index === "number") state = prev;
      logProg(`resumed from index ${state.last_index+1}/${total}`);
    } catch(e){ logProg("state file corrupt, restart: "+e.message); }
  } else {
    logProg(`fresh start — total=${total}`);
  }

  const startIdx = state.last_index + 1;
  const t0 = Date.now();
  let sinceBatch = 0;
  let mismatchInWindow = 0; // per-200 window
  const MISMATCH_MAX = 10; // 5% of 200
  const BATCH_LIMIT = process.env.BATCH_LIMIT ? parseInt(process.env.BATCH_LIMIT, 10) : 0;
  const stopAt = BATCH_LIMIT > 0 ? Math.min(total, startIdx + BATCH_LIMIT) : total;
  if (BATCH_LIMIT > 0) logProg(`BATCH_LIMIT=${BATCH_LIMIT}  will process indices ${startIdx}..${stopAt-1}`);

  for (let i = startIdx; i < stopAt; i++){
    const p = products[i];

    // --- skip seed/mock ids known to have bogus PIDs ---
    if (p.id.startsWith("cm-")){
      const skipEntry = { i:i+1, ts:new Date().toISOString(), id:p.id, pid:p.pid, bd_name:p.name, bd_price:p.price, action:"skip", reason:"seed-excluded-cm" };
      appendJsonArrayLine(UPDATES_LOG, skipEntry);
      state.counters.seed_excluded = (state.counters.seed_excluded||0) + 1;
      state.last_index = i;
      sinceBatch++;
      if (sinceBatch >= 200 || i === total - 1){
        fs.writeFileSync(STATE_FILE, JSON.stringify(state, null, 2));
        const elapsed = ((Date.now()-t0)/60000).toFixed(1);
        const pct = (((i+1)/total)*100).toFixed(1);
        const c = state.counters;
        logProg(`[${i+1}/${total} ${pct}%] ${elapsed}min  updated=${c.updated} igual=${c.igual} mismatch=${c.name_mismatch} notFound=${c.not_found} review=${c.needs_review} err=${c.http_error} seed_excl=${c.seed_excluded||0}  (window_mismatch=${mismatchInWindow})`);
        sinceBatch = 0;
        mismatchInWindow = 0;
      }
      continue;
    }

    // --- scrape ---
    let attempt = 0, resp;
    while (true){
      resp = await scrape(p.pid);
      if ((resp.status===429 || resp.status===503) && attempt < 2){
        attempt++;
        logProg(`[${i+1}/${total}] ${p.pid} got ${resp.status}, backoff...`);
        await sleep(15000 + Math.random()*10000);
        continue;
      }
      break;
    }

    if (resp.status === 429){
      logProg(`[${i+1}/${total}] ${p.pid} BLOCKED 429 after retries — STOP`);
      state.last_index = i - 1;
      fs.writeFileSync(STATE_FILE, JSON.stringify(state, null, 2));
      process.exit(2);
    }

    // --- decide outcome ---
    let decision = { pid:p.pid, id:p.id, bd_name:p.name, bd_price:p.price, bd_photo_url:p.photo_url, http:resp.status, site_price:null, site_name:null, site_image:null, name_match:null, action:null, reason:null };

    if (resp.err || resp.status !== 200){
      decision.action = "skip";
      decision.reason = "http-error:" + (resp.err || resp.status);
      state.counters.http_error++;
      logErr(`[${i+1}] ${p.pid} ${decision.reason}`);
    } else {
      const { name:siteName, price:sitePriceRaw, image:siteImage } = extractPriceName(resp.body);
      decision.site_name = siteName ? decodeEnt(siteName) : null;
      decision.site_image = siteImage || null;
      const sp = (sitePriceRaw===null || sitePriceRaw===undefined) ? null : parseFloat(sitePriceRaw);
      decision.site_price = Number.isFinite(sp) ? sp : null;

      if (decision.site_price === null){
        decision.action = "skip";
        decision.reason = "not-found-jsonld";
        state.counters.not_found++;
      } else {
        const ratio = nameMatchRatio(p.name, decision.site_name);
        decision.name_match = +ratio.toFixed(2);
        if (ratio < 0.3){
          decision.action = "skip";
          decision.reason = "name-mismatch";
          state.counters.name_mismatch++;
          mismatchInWindow++;
        } else {
          const bdr = p.price!=null ? Math.round(p.price*100)/100 : null;
          const delta = bdr!=null ? Math.round((decision.site_price - bdr)*100)/100 : null;
          decision.delta = delta;
          if (bdr === null){
            decision.action = "update";
            decision.reason = "bd-price-null";
          } else if (Math.abs(delta) <= 0.01){
            decision.action = "skip";
            decision.reason = "delta-<=0.01";
            state.counters.igual++;
          } else {
            // suspicious drop on fresh/kg products — mark review
            const suspiciousDrop = bdr >= 3 && decision.site_price < bdr * 0.30;
            decision.action = "update";
            decision.reason = suspiciousDrop ? "update-with-review" : "update";
            decision.needs_review = suspiciousDrop;
          }
        }
      }
    }

    // --- write log BEFORE update ---
    const logEntry = { i:i+1, ts: new Date().toISOString(), ...decision };
    appendJsonArrayLine(UPDATES_LOG, logEntry);
    if (decision.needs_review){ appendJsonArrayLine(REVIEW_LOG, logEntry); }

    // --- perform update ---
    if (decision.action === "update"){
      const patch = {};
      // only set price if we have a new one
      patch.price = decision.site_price;
      if ((p.photo_url === null || p.photo_url === "" ) && decision.site_image){
        patch.photo_url = decision.site_image;
      }
      patch.last_updated = new Date().toISOString();
      if (decision.needs_review) patch.needs_review = true;

      const res = await sbRequest("PATCH", `/rest/v1/products?id=eq.${encodeURIComponent(p.id)}`, patch);
      if (res.status >= 200 && res.status < 300){
        state.counters.updated++;
        if (decision.needs_review) state.counters.needs_review++;
        logProg(`[${i+1}/${total}] ${p.pid} UPDATE bd=${p.price} → site=${decision.site_price} Δ=${decision.delta}${decision.needs_review?" ⚠REVIEW":""}`);
      } else {
        state.counters.http_error++;
        logErr(`[${i+1}] ${p.pid} PATCH fail ${res.status}: ${(res.raw||"").slice(0,200)}`);
        decision.action = "skip";
        decision.reason = "patch-fail:"+res.status;
      }
    } else {
      // small trace
      if (decision.reason === "delta-<=0.01") {
        // too spammy — only log sample
      } else {
        logProg(`[${i+1}/${total}] ${p.pid} SKIP ${decision.reason}`);
      }
    }

    // --- checkpoint ---
    state.last_index = i;
    sinceBatch++;
    // light checkpoint every 20 iterations (robust to harness-kill)
    if (sinceBatch % 20 === 0) {
      try { fs.writeFileSync(STATE_FILE, JSON.stringify(state, null, 2)); } catch(e){}
    }
    if (sinceBatch >= 200 || i === total - 1){
      fs.writeFileSync(STATE_FILE, JSON.stringify(state, null, 2));
      const elapsed = ((Date.now()-t0)/60000).toFixed(1);
      const pct = (((i+1)/total)*100).toFixed(1);
      const c = state.counters;
      logProg(`[${i+1}/${total} ${pct}%] ${elapsed}min  updated=${c.updated} igual=${c.igual} mismatch=${c.name_mismatch} notFound=${c.not_found} review=${c.needs_review} err=${c.http_error}  (window_mismatch=${mismatchInWindow})`);
      if (mismatchInWindow > MISMATCH_MAX){
        logProg(`⚠ STOP: name-mismatch in last window (${mismatchInWindow}/${sinceBatch}) exceeded ${MISMATCH_MAX}/200`);
        state.stopped_reason = `name-mismatch-threshold:${mismatchInWindow}/${sinceBatch}`;
        fs.writeFileSync(STATE_FILE, JSON.stringify(state, null, 2));
        process.exit(3);
      }
      sinceBatch = 0;
      mismatchInWindow = 0;
    }

    // --- rate limit ---
    if (i < total - 1){
      const wait = 4500 + (Math.random()*1600 - 800);
      await sleep(wait);
    }
  }

  // --- final for this run ---
  const finishedAll = state.last_index >= total - 1;
  if (finishedAll) state.finished_at = new Date().toISOString();
  fs.writeFileSync(STATE_FILE, JSON.stringify(state, null, 2));

  const c = state.counters;
  const elapsed = ((Date.now()-t0)/60000).toFixed(1);
  if (finishedAll){
    logProg(`\n=== FASE 1 DONE ===  ${elapsed}min`);
  } else {
    logProg(`\n=== BATCH DONE ===  ${elapsed}min  processed_in_run=${stopAt-startIdx}  next_start=${state.last_index+1}/${total}`);
  }
  logProg(`CUMULATIVE  updated=${c.updated}  igual=${c.igual}  name_mismatch=${c.name_mismatch}  not_found=${c.not_found}  review=${c.needs_review}  http_error=${c.http_error}`);
})().catch(e => {
  logErr("FATAL: "+e.message+"\n"+e.stack);
  logProg("FATAL: "+e.message);
  process.exit(1);
});

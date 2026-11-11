// Missão farmacias-2026-11-11 — catálogo das farmácias da Guarda a partir da Glovo.
// Uso: node catalogo_glovo.mjs <fase> [loja] [limite]
//   fases: crawl | details | photos | all
//   loja:  farmacia-se-guarda | farmacia-teixeira-guarda | todas (omissão = as duas)
// A chave pública do Supabase vem da variável de ambiente SB_PUBLISHABLE_KEY (nunca no ficheiro).
// Não escreve em tabelas da base. Só sobe fotos para o bucket product-images (conta demo da própria loja).
// Nunca imprime a palavra-passe nem o token.
import fs from "fs";
import path from "path";
import crypto from "crypto";
import { fileURLToPath } from "url";

const HERE = path.dirname(fileURLToPath(import.meta.url));
const DADOS = path.join(HERE, "dados");
const FOTOS = "C:/Users/danil/AppData/Local/Temp/farmacias-fotos";
const CONTAS = process.env.CONTAS_DEMO ||
  "C:/Users/danil/AppData/Local/Temp/claude/a049a63d7b848f31/d24ac451-949b-4d1c-a3e9-67d73a7e4dbf/scratchpad/contas_demo_farmacias.json";
const SB = "https://ojykpzwqrtusfeakzrna.supabase.co";
// chave pública (publishable): do ambiente, ou de um ficheiro fora do repo (pasta temporária da sessão)
const CHAVE_FICHEIRO = "C:/Users/danil/AppData/Local/Temp/claude/a049a63d7b848f31/d24ac451-949b-4d1c-a3e9-67d73a7e4dbf/scratchpad/chave_publica_supabase.txt";
const chavePublica = process.env.SB_PUBLISHABLE_KEY || (fs.existsSync(CHAVE_FICHEIRO) ? fs.readFileSync(CHAVE_FICHEIRO, "utf8").trim() : "");
const BUCKET = "product-images";
fs.mkdirSync(DADOS, { recursive: true });
fs.mkdirSync(FOTOS, { recursive: true });

export const LOJAS = {
  "farmacia-se-guarda": { slug: "farmacia-da-se-grd", storeId: "461279", addressId: "732949", prefix: "fse" },
  "farmacia-teixeira-guarda": { slug: "farmacia-teixeira-grd", storeId: "461596", addressId: "733650", prefix: "fte" },
};

const LOG = path.join(DADOS, "execucao.log");
function log(...a) {
  const line = `[${new Date().toISOString()}] ${a.join(" ")}`;
  console.log(line);
  fs.appendFileSync(LOG, line + "\n");
}
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const readJson = (f, d) => (fs.existsSync(f) ? JSON.parse(fs.readFileSync(f, "utf8")) : d);
const writeJson = (f, o) => fs.writeFileSync(f, JSON.stringify(o, null, 1));

// ---------- Glovo API (máx. ~2,6 pedidos/s, com novas tentativas) ----------
const UA = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36";
const SESSION = crypto.randomUUID();
function glovoHeaders(loja) {
  return {
    "User-Agent": UA,
    "Accept": "application/json, text/plain, */*",
    "Accept-Language": "pt-PT,pt;q=0.9",
    "glovo-api-version": "14",
    "glovo-app-platform": "web",
    "glovo-app-type": "customer",
    "glovo-location-country-code": "PT",
    "glovo-location-city-code": "GRD",
    "glovo-location-latitude": "40.5373",
    "glovo-location-longitude": "-7.2674",
    "glovo-language-code": "pt",
    "Glovo-Perseus-Session-Id": SESSION,
    "Origin": "https://glovoapp.com",
    "Referer": `https://glovoapp.com/pt/pt/guarda/stores/${LOJAS[loja]?.slug || ""}`,
  };
}
// A Glovo deu 429 ao fim de ~100 pedidos a 2,6/s (11/11 16:10): ritmo de 1 pedido a cada 1,5 s
// e cache em disco de cada resposta (fora do repo) para retomar sem repetir pedidos.
const CACHE = "C:/Users/danil/AppData/Local/Temp/farmacias-cache";
fs.mkdirSync(CACHE, { recursive: true });
let lastApi = 0;
const API_GAP = Number(process.env.API_GAP_MS || 1500);
let apiCount = 0, cacheHits = 0;
async function apiSlot() {
  const now = Date.now();
  const wait = Math.max(0, lastApi + API_GAP - now);
  lastApi = now + wait;
  if (wait) await sleep(wait);
}
// Preserva inteiros grandes (ids da Glovo > 2^53) como texto
export function parseGlovo(text) {
  return JSON.parse(text.replace(/([:\[,]\s*)(-?\d{16,})(?=\s*[,\]}])/g, '$1"$2"'));
}
async function glovo(loja, pathOrUrl, { method = "GET", body = null } = {}) {
  const url = pathOrUrl.startsWith("http") ? pathOrUrl : "https://api.glovoapp.com" + pathOrUrl;
  const cacheFile = path.join(CACHE, crypto.createHash("sha1").update(method + " " + url).digest("hex") + ".json");
  if (fs.existsSync(cacheFile)) { cacheHits++; return parseGlovo(fs.readFileSync(cacheFile, "utf8")); }
  const waits = [2000, 5000, 15000, 30000, 60000];
  const waits429 = [90000, 180000, 300000, 600000, 900000];
  for (let attempt = 0; ; attempt++) {
    await apiSlot();
    apiCount++;
    let status = 0, text = "", err = "";
    try {
      const ctl = new AbortController();
      const t = setTimeout(() => ctl.abort(), 30000);
      const h = glovoHeaders(loja);
      if (body) h["Content-Type"] = "application/json";
      const r = await fetch(url, { method, headers: h, body: body ? JSON.stringify(body) : undefined, signal: ctl.signal });
      status = r.status;
      text = await r.text();
      clearTimeout(t);
    } catch (e) { err = e.message; }
    if (status === 200) {
      const j = parseGlovo(text);
      fs.writeFileSync(cacheFile, text);
      return j;
    }
    const retriable = status === 0 || status === 429 || status >= 500;
    const w = status === 429 ? waits429 : waits;
    if (!retriable || attempt >= w.length) {
      throw new Error(`HTTP ${status} ${err} ${url} :: ${text.slice(0, 200)}`);
    }
    log(`  nova tentativa ${attempt + 1} (HTTP ${status} ${err}) espera ${w[attempt] / 1000}s ${url.slice(0, 140)}`);
    await sleep(w[attempt]);
  }
}

// ---------- FASE 1: crawl (árvore + produtos) ----------
function tileOf(el) {
  const d = el.data || {};
  return {
    glovo_id: String(d.id),
    external_id: d.externalId != null ? String(d.externalId) : null,
    store_product_id: d.storeProductId != null ? String(d.storeProductId) : null,
    name: d.name,
    price: d.price,
    priceInfo: d.priceInfo,
    imageUrl: d.imageUrl || null,
    imageId: d.imageId || null,
    images: d.images || [],
    tags: d.tags || [],
    promotions: d.promotions || [],
    labels: d.labels || [],
    indicators: d.indicators || [],
    restricted: !!d.restricted,
    outOfStock: !!d.outOfStock,
    sponsored: !!d.sponsored,
    attributeGroups: (d.attributeGroups || []).length,
  };
}
async function crawlLoja(loja) {
  const L = LOJAS[loja];
  log(`== crawl ${loja} (store ${L.storeId} / address ${L.addressId})`);
  const menu = await glovo(loja, `/v3/stores/${L.storeId}/addresses/${L.addressId}/node/store_menu`);
  writeJson(path.join(DADOS, `menu_${loja}.json`), menu);
  const products = {}; // glovo_id -> tile + ocorrencias
  const extraKeys = {};
  const extraTypes = {};
  const sectionsSeen = new Set();
  const missing = [];
  let order = 0;
  const addGrid = (grid, ctx) => {
    const g = grid.data || {};
    for (const k of Object.keys(g)) if (!["title", "slug", "elements", "tracking", "columns"].includes(k)) extraKeys[k] = (extraKeys[k] || 0) + 1;
    sectionsSeen.add(ctx.c.slug + "|" + g.slug);
    let pos = 0;
    for (const el of g.elements || []) {
      if (el.type !== "PRODUCT_TILE") { extraTypes["grid:" + el.type] = (extraTypes["grid:" + el.type] || 0) + 1; continue; }
      const t = tileOf(el);
      const occ = { sc: ctx.sc.name, sc_slug: ctx.sc.slug, c: ctx.c.name, c_slug: ctx.c.slug, s: g.title, s_slug: g.slug, ord: order++, pos: pos++ };
      if (!products[t.glovo_id]) products[t.glovo_id] = { ...t, occ: [occ] };
      else products[t.glovo_id].occ.push(occ);
    }
  };
  const scs = menu.data.elements;
  for (let i = 0; i < scs.length; i++) {
    const sc = scs[i];
    for (const c of sc.elements) {
      const p = c.action?.data?.path;
      let page;
      try { page = await glovo(loja, p); }
      catch (e) {
        // categoria do menu sem produtos válidos (a Glovo responde 404 "exists but no valid products to show")
        if (/HTTP 404/.test(e.message) && /no valid products/i.test(e.message)) {
          missing.push({ c: c.slug, s: "*", why: "categoria vazia na Glovo (404 no valid products)" });
          log(`  categoria vazia na Glovo: ${sc.name} > ${c.name}`);
          continue;
        }
        throw e;
      }
      const body = page?.data?.body || [];
      for (const b of body) {
        if (b.type === "GRID") addGrid(b, { sc, c });
        else if (b.type === "CONTENT_PLACEHOLDER") {
          let part;
          try { part = await glovo(loja, b.data.contentUri); }
          catch (e) {
            if (/HTTP 404/.test(e.message)) { missing.push({ c: c.slug, s: b.data.slug, why: "parcial 404: " + e.message.slice(0, 80) }); continue; }
            throw e;
          }
          for (const pb of part?.data?.body || []) {
            if (pb.type === "GRID") addGrid(pb, { sc, c });
            else extraTypes["partial:" + pb.type] = (extraTypes["partial:" + pb.type] || 0) + 1;
          }
        } else extraTypes["body:" + b.type] = (extraTypes["body:" + b.type] || 0) + 1;
      }
      // secções do menu que não apareceram: buscar pela parcial
      for (const s of c.elements) {
        if (sectionsSeen.has(c.slug + "|" + s.slug)) continue;
        const sid = s.tracking?.sectionId;
        if (!sid) { missing.push({ c: c.slug, s: s.slug, why: "sem sectionId" }); continue; }
        try {
          const part = await glovo(loja, `/v4/stores/${L.storeId}/addresses/${L.addressId}/content/partial?component=section&id=${sid}`);
          let got = false;
          for (const pb of part?.data?.body || []) if (pb.type === "GRID") { addGrid(pb, { sc, c }); got = true; }
          if (!got) missing.push({ c: c.slug, s: s.slug, why: "parcial sem GRID" });
          else log(`  secção recuperada pela parcial: ${c.slug} / ${s.slug}`);
        } catch (e) { missing.push({ c: c.slug, s: s.slug, why: e.message.slice(0, 120) }); }
      }
      log(`  ${sc.name} > ${c.name}: total único ${Object.keys(products).length}`);
    }
  }
  const out = {
    loja, ...L, crawled_at: new Date().toISOString(),
    menu_sections: scs.length, menu_categories: scs.reduce((a, s) => a + s.elements.length, 0),
    menu_subsections: scs.reduce((a, s) => a + s.elements.reduce((b, c) => b + c.elements.length, 0), 0),
    sections_seen: sectionsSeen.size, missing_sections: missing, extra_grid_keys: extraKeys, extra_types: extraTypes,
    elements_without_menu: menu.data.elementsWithoutMenu,
    total_unique: Object.keys(products).length,
    products: Object.values(products),
  };
  writeJson(path.join(DADOS, `raw_${loja}.json`), out);
  log(`== crawl ${loja} FIM: únicos=${out.total_unique} secções vistas=${out.sections_seen}/${out.menu_subsections} em falta=${missing.length} pedidos=${apiCount}`);

  // info pública da loja (ajuda para o outro agente)
  try {
    const info = await glovo(loja, `/v3/stores/${L.storeId}/addresses/${L.addressId}/store_info_screen?translation=false`);
    writeJson(path.join(DADOS, `info_${loja}.json`), info);
  } catch (e) { log("  info falhou:", e.message.slice(0, 150)); }
  try {
    const st = await glovo(loja, `/v3/stores/${L.storeId}?includeClosed=true&includeDisabled=false`);
    writeJson(path.join(DADOS, `store_${loja}.json`), st);
  } catch (e) { log("  store v3 falhou:", e.message.slice(0, 150)); }
}

// ---------- FASE 2: detalhes (descrição) ----------
function extractDetails(j) {
  const det = {}; const images = []; const texts = [];
  const s = JSON.stringify(j);
  const otc = s.includes("qcommerce/otc");
  (function walk(n) {
    if (!n || typeof n !== "object") return;
    if (Array.isArray(n)) return n.forEach(walk);
    if (n.type === "TWO_COLUMN_ROW_TEXT" && n.data) det[n.data.firstColumnText] = n.data.secondColumnText;
    if (n.type === "MULTIPLE_IMAGES" && n.data?.images) for (const im of n.data.images) images.push(im.imageId);
    if (n.type === "TEXT" && n.data?.text) texts.push({ t: n.data.text, strike: !!n.data.isStrikethrough, style: n.data.styles?.type });
    for (const k of Object.keys(n)) walk(n[k]);
  })(j);
  return { details: det, description: det["Descrição"] || null, images, texts, otc_banner: otc };
}
async function detailsLoja(loja) {
  const L = LOJAS[loja];
  const raw = readJson(path.join(DADOS, `raw_${loja}.json`));
  const f = path.join(DADOS, `detalhes_${loja}.json`);
  const det = readJson(f, {});
  let n = 0, fails = 0;
  const todo = raw.products.filter((p) => !det[p.glovo_id] || det[p.glovo_id].error);
  log(`== detalhes ${loja}: ${todo.length} por fazer (${Object.keys(det).length} já em cache)`);
  for (const p of todo) {
    try {
      const j = await glovo(loja, `/v4/stores/${L.storeId}/addresses/${L.addressId}/products/${p.glovo_id}/view?productExternalId=${encodeURIComponent(p.external_id || "")}`,
        { method: "POST", body: { editingMode: false, origin: "category_details", quantity: 1 } });
      det[p.glovo_id] = extractDetails(j);
    } catch (e) { det[p.glovo_id] = { error: e.message.slice(0, 200) }; fails++; }
    if (++n % 25 === 0) { writeJson(f, det); log(`  detalhes ${loja}: ${n}/${todo.length} falhas=${fails}`); }
  }
  writeJson(f, det);
  log(`== detalhes ${loja} FIM: ${n} feitos, falhas=${fails}`);
}

// ---------- FASE 3: fotos ----------
export function sniff(buf) {
  if (buf.length >= 3 && buf[0] === 0xff && buf[1] === 0xd8 && buf[2] === 0xff) return { type: "image/jpeg", ext: "jpg" };
  if (buf.length >= 8 && buf.subarray(0, 8).equals(Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]))) return { type: "image/png", ext: "png" };
  if (buf.length >= 12 && buf.subarray(0, 4).toString("latin1") === "RIFF" && buf.subarray(8, 12).toString("latin1") === "WEBP") return { type: "image/webp", ext: "webp" };
  if (buf.length >= 12 && buf.subarray(4, 8).toString("latin1") === "ftyp") {
    const brand = buf.subarray(8, 12).toString("latin1");
    if (brand === "avif" || brand === "avis") return { type: "image/avif", ext: "avif" };
    return { type: "iso:" + brand, ext: null };
  }
  if (buf.length >= 4 && buf.subarray(0, 4).toString("latin1") === "GIF8") return { type: "image/gif", ext: "gif" };
  return { type: "desconhecido", ext: null };
}
const sessoes = {};
const aEntrar = {};
function sbAcesso(loja) {
  const t = sessoes[loja];
  if (t && Date.now() < t.exp - 5 * 60 * 1000) return Promise.resolve(t.access);
  if (!aEntrar[loja]) aEntrar[loja] = sbEntrar(loja).finally(() => { delete aEntrar[loja]; });
  return aEntrar[loja];
}
async function sbEntrar(loja) {
  if (!chavePublica) throw new Error("falta SB_PUBLISHABLE_KEY no ambiente");
  const contas = JSON.parse(fs.readFileSync(CONTAS, "utf8"));
  const c = contas.find((x) => x.loja === loja);
  if (!c) throw new Error("sem conta demo para " + loja);
  const r = await fetch(`${SB}/auth/v1/token?grant_type=password`, {
    method: "POST", headers: { apikey: chavePublica, "Content-Type": "application/json" },
    body: JSON.stringify({ email: c.email, password: c.password }),
  });
  const j = await r.json();
  if (!j.access_token) throw new Error(`login falhou HTTP ${r.status} ${j.error_code || j.error || ""} ${j.msg || j.error_description || ""}`);
  sessoes[loja] = { access: j.access_token, exp: Date.now() + (j.expires_in || 3600) * 1000, uid: j.user?.id };
  log(`  login ok ${loja} uid=${j.user?.id}`);
  return j.access_token;
}
async function fetchBuf(url, headers, tries = 4) {
  for (let a = 0; ; a++) {
    try {
      const ctl = new AbortController();
      const t = setTimeout(() => ctl.abort(), 45000);
      const r = await fetch(url, { headers, signal: ctl.signal });
      const b = Buffer.from(await r.arrayBuffer());
      clearTimeout(t);
      if (r.status === 200) return { status: 200, buf: b, ctype: r.headers.get("content-type") };
      if (!(r.status === 429 || r.status >= 500) || a >= tries) return { status: r.status, buf: b };
    } catch (e) { if (a >= tries) return { status: 0, err: e.message }; }
    await sleep([1500, 4000, 10000, 20000][a] || 20000);
  }
}
function imageUrlOf(p, d) {
  if (p.imageUrl) return p.imageUrl;
  const id = p.imageId || d?.images?.[0];
  if (id) return "https://glovo.dhmedia.io/image/" + id.replace(/^dh:/, "");
  return null;
}
async function photoOne(loja, p, d) {
  const L = LOJAS[loja];
  const pid = `${L.prefix}-${p.glovo_id}`;
  const src = imageUrlOf(p, d);
  if (!src) return { status: "sem_foto_na_glovo" };
  const ACC = "image/jpeg,image/png,image/webp";
  let dl = await fetchBuf(src, { "User-Agent": UA, Accept: ACC });
  if (dl.status !== 200) return { status: "download_falhou", http: dl.status, err: dl.err, src };
  let kind = sniff(dl.buf);
  if (kind.type === "image/avif") {
    dl = await fetchBuf(src, { "User-Agent": UA, Accept: "image/jpeg" });
    kind = dl.status === 200 ? sniff(dl.buf) : kind;
    if (kind.type === "image/avif") return { status: "avif_sem_conversao", src };
  }
  if (!kind.ext) return { status: "tipo_desconhecido", tipo: kind.type, src };
  const dir = path.join(FOTOS, loja);
  fs.mkdirSync(dir, { recursive: true });
  fs.writeFileSync(path.join(dir, `${pid}.${kind.ext}`), dl.buf);
  const objPath = `farmacias/${loja}/${pid}.${kind.ext}`;
  let up = { status: 0, txt: "" };
  for (let a = 0; a < 4; a++) {
    const acesso = await sbAcesso(loja);
    try {
      const r = await fetch(`${SB}/storage/v1/object/${BUCKET}/${objPath}`, {
        method: "POST",
        headers: { Authorization: `Bearer ${acesso}`, apikey: chavePublica, "x-upsert": "true", "Content-Type": kind.type, "cache-control": "max-age=31536000" },
        body: dl.buf,
      });
      const txt = await r.text();
      up = { status: r.status, txt: txt.slice(0, 200) };
      if (r.status === 200) break;
      if (r.status === 401 || /jwt|expired/i.test(txt)) { delete sessoes[loja]; continue; }
      if (r.status === 429 || r.status >= 500) { await sleep(3000 * (a + 1)); continue; }
      break;
    } catch (e) { up = { status: 0, txt: e.message }; await sleep(3000); }
  }
  if (up.status !== 200) return { status: "upload_falhou", http: up.status, msg: up.txt, src, photo_type: kind.type, photo_bytes: dl.buf.length };
  // provar pelo URL público: 200 + mesmo tamanho + mesmos primeiros bytes + mesmo md5
  const pub = `${SB}/storage/v1/object/public/${BUCKET}/${objPath}`;
  const chk = await fetchBuf(pub + `?v=${Date.now()}`, { "User-Agent": UA });
  const md5 = (b) => crypto.createHash("md5").update(b).digest("hex");
  const same = chk.status === 200 && chk.buf.length === dl.buf.length && chk.buf.subarray(0, 32).equals(dl.buf.subarray(0, 32)) && md5(chk.buf) === md5(dl.buf);
  return {
    status: same ? "ok" : "prova_falhou", http_publico: chk.status, src, photo_url: pub, object_path: objPath,
    photo_type: kind.type, photo_bytes: dl.buf.length, public_bytes: chk.buf?.length ?? null, md5: md5(dl.buf),
  };
}
async function photosLoja(loja, limit = Infinity) {
  const raw = readJson(path.join(DADOS, `raw_${loja}.json`));
  const det = readJson(path.join(DADOS, `detalhes_${loja}.json`), {});
  const f = path.join(DADOS, `fotos_${loja}.json`);
  const st = readJson(f, {});
  const todo = raw.products.filter((p) => !st[p.glovo_id] || st[p.glovo_id].status !== "ok").slice(0, limit);
  log(`== fotos ${loja}: ${todo.length} por fazer (${Object.values(st).filter((x) => x.status === "ok").length} já ok)`);
  let i = 0, done = 0;
  const W = 4;
  const count = () => { const c = {}; for (const v of Object.values(st)) c[v.status] = (c[v.status] || 0) + 1; return JSON.stringify(c); };
  await Promise.all(Array.from({ length: W }, async () => {
    while (i < todo.length) {
      const p = todo[i++];
      try { st[p.glovo_id] = await photoOne(loja, p, det[p.glovo_id]); }
      catch (e) { st[p.glovo_id] = { status: "erro", msg: e.message.slice(0, 200) }; }
      if (++done % 50 === 0) { writeJson(f, st); log(`  fotos ${loja}: ${done}/${todo.length} ${count()}`); }
      await sleep(120);
    }
  }));
  writeJson(f, st);
  log(`== fotos ${loja} FIM: ${count()}`);
}

// ---------- main ----------
const [fase = "all", lojaArg, limArg] = process.argv.slice(2);
const lojas = lojaArg && lojaArg !== "todas" ? [lojaArg] : Object.keys(LOJAS);
(async () => {
  for (const loja of lojas) {
    if (!LOJAS[loja]) throw new Error("loja desconhecida " + loja);
    if (fase === "crawl" || fase === "all") await crawlLoja(loja);
    if (fase === "details" || fase === "all") await detailsLoja(loja);
    if (fase === "photos" || fase === "all") await photosLoja(loja, limArg ? Number(limArg) : Infinity);
  }
  log(`fase ${fase} terminada; pedidos à API Glovo nesta execução: ${apiCount} (cache: ${cacheHits})`);
})().catch((e) => { log("FATAL", e.message, e.stack?.split("\n").slice(0, 3).join(" | ")); process.exit(1); });

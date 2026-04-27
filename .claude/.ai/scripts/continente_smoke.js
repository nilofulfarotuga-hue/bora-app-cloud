// T1 — Smoke test 50 PIDs Continente. READ-ONLY. Zero DB mutations.
const https = require('https');
const zlib  = require('zlib');
const fs    = require('fs');
const path  = require('path');

const products = [
  {id:"prod_0977",name:"Ervilhas Congeladas 750g",price:"4.10",pid:"7068840"},
  {id:"700f2557-8b60-4857-a8b8-cf2a2a1755a3",name:"Palitos de Queijo Continente",price:"2.397",pid:"8296701"},
  {id:"cnt-8195596",name:"Fragrância Corpo Body Mist Exotic Love Womensecret",price:"12.99",pid:"8195596"},
  {id:"prod_0470",name:"Tamboril Fresco kg",price:"9.26",pid:"7163487"},
  {id:"cm-hg-001",name:"Champô Cabelo Normal",price:"2.99",pid:"2053281"},
  {id:"cnt-5330563",name:"Bolachas de Manteiga Triunfo",price:"1.99",pid:"5330563"},
  {id:"d38f663f-eb7f-4af2-89c2-d9419335c2dd",name:"Chouriço de Porco Preto Montaraz",price:"2.8919",pid:"6297976"},
  {id:"af291e08-4441-4a40-bb3a-7af73138eec2",name:"Tostas com Azeite e Sal Rialto",price:"1.8918",pid:"5223373"},
  {id:"13d5e14a-d2e1-4fb6-9ebb-f69d49c84cf1",name:"Pepperoni em Rodelas Continente",price:"2.9919",pid:"8284433"},
  {id:"cnt-4636961",name:"Dentão Fresco",price:"8.99",pid:"4636961"},
  {id:"80775f37-9ff9-45d4-8c6e-282fbd34ed8c",name:"Broas d'Avó Da Nossa Pastelaria",price:"2.299",pid:"8147037"},
  {id:"89373270-7ceb-4dad-8409-08b8d7f765d2",name:"Entrecosto de Porco Congelado Continente",price:"4.996",pid:"7484541"},
  {id:"d7153f8e-e203-4662-9a00-202efb91d3eb",name:"Comida Húmida para Cão Adulto Vaca Lily's Kitchen",price:"1.7911",pid:"7736345"},
  {id:"11e10e41-1b59-4161-8592-241ee25f8636",name:"Vinagre de Vinho Branco Continente",price:"0.75",pid:"4099241"},
  {id:"prod_0536",name:"Lasanha de Legumes Congelada 400g",price:"5.44",pid:"2604857"},
  {id:"cnt-7157938",name:"P&atilde;o de Forma com C&ocirc;dea Continente",price:"1.49",pid:"7157938"},
  {id:"cnt-8012464",name:"Lokita Mezcal Ensamble Espadin 8 Anos",price:"80",pid:"8012464"},
  {id:"89d25c61-627e-4f11-8a8a-dc1ca78a691e",name:"Batata Doce Palitos Continente",price:"2.595",pid:"8176381"},
  {id:"2a5246c5-dfa3-448b-b127-e7fd661e45db",name:"Mini Gressinos de Espelta Forno D'Oro",price:"1.996",pid:"8242186"},
  {id:"3fb1d018-34f4-43e0-9c7d-ef49b3e4e800",name:"Bolachas Cracker Tuc",price:"3.1912",pid:"4999431"},
  {id:"bdd0a4f6-5c3a-4224-8b91-55f79e1fadd9",name:"Miolo de Caju com Piripiri Continente",price:"3.1915",pid:"8114840"},
  {id:"cnt-4963603",name:"Miolo de Am&ecirc;ndoa Mo&iacute;da Cimarrom",price:"2.39",pid:"4963603"},
  {id:"2c5fbc74-fcae-4332-97b0-bdb58b70a92c",name:"Batata Frita Palha Fina Receita Caseira Continente",price:"1.095",pid:"5097178"},
  {id:"cnt-8118307",name:"Saboneteira WC Cinza Escuro Kasa",price:"5",pid:"8118307"},
  {id:"cnt-7966059",name:"Base Guarda-Sol de Pl&aacute;stico Quadrada 20L",price:"40",pid:"7966059"},
  {id:"af11ab9f-6991-43f1-afb3-579c2deeb9f3",name:"Postas de Bacalhau MSC Demolhado Ultracongelado Pack Poupança Continente",price:"13.9911",pid:"7463420"},
  {id:"1928d11e-4a23-4488-9a2c-831ae082d2a1",name:"Pão de Forma Integral sem Côdea Continente",price:"1.994",pid:"7159007"},
  {id:"d143bf84-6b9d-4b00-81bd-098175247583",name:"Strogonoff de Peru Continente",price:"8.994",pid:"7071906"},
  {id:"prod_0683",name:"Curcuma + Pimenta Preta 60un",price:"11.77",pid:"6046609"},
  {id:"14fb327f-8c36-41c5-8667-8e568e061b0e",name:"Chouriço de Carne do Alentejo Continente",price:"1.8914",pid:"7435436"},
  {id:"cnt-8181959",name:"Cadeira Auto I-Size 100-150cm Preta Xtreme Asalvo",price:"69.99",pid:"8181959"},
  {id:"0f729880-cda1-4655-addc-9728f072bb1f",name:"Café em Grão Qualitá Oro Int 5 Lavazza",price:"17.9935",pid:"7305458"},
  {id:"8b8bf4bd-172c-48e5-b928-aaca94542fa1",name:"Mini Pizzas de Salame Continente",price:"3.499",pid:"7947275"},
  {id:"prod_0313",name:"Tabasco 60ml",price:"3.39",pid:"6931560"},
  {id:"cnt-8118818",name:"Comida Húmida para Gato Esterilizado Frango e Vaca Affinity Ultima",price:"6.69",pid:"8118818"},
  {id:"a9ff79d0-65f6-460c-a366-97e66b6d7598",name:"Wrap de Trigo de Chia e Quinoa Mission",price:"2.957",pid:"7038308"},
  {id:"cnt-8038678",name:"Zoko Happy Bear - As Minhas Primeiras Formas",price:"7.99",pid:"8038678"},
  {id:"125374bd-8488-4716-97dd-e0198c300ec5",name:"Queijo Curado Fatiado Castelões",price:"4.9912",pid:"7329389"},
  {id:"cnt-7497309",name:"Queijo Burrata de Vaca Gioiella",price:"3.49",pid:"7497309"},
  {id:"d07fa5b4-a5c6-4ff2-aa81-4e9444f40cde",name:"Alperce Seco Continente",price:"3.1915",pid:"8112336"},
  {id:"95a7d7f4-48fd-4543-8ed4-2749c0a841e5",name:"Azeitona Verde Descaroçada Continente",price:"1.257",pid:"7571658"},
  {id:"cnt-7695572",name:"Quinta de S&atilde;o Jos&eacute; Reserva Douro Vinho Tinto",price:"34.3",pid:"7695572"},
  {id:"cnt-8519065",name:"Creme Balsâmico Romã Biológico Cristal",price:"3.89",pid:"8519065"},
  {id:"cnt-4952196",name:"Fiambre da Perna Fatiado Nobre",price:"1.39",pid:"4952196"},
  {id:"prod_0035",name:"Atum em Lata 120g",price:"8.36",pid:"2144985"},
  {id:"aa515714-9912-40c3-99b3-4c7083373b0b",name:"Creme Corpo Gordo Hipoalergénico Soft&Co",price:"9.9919",pid:"7801750"},
  {id:"2079a6d0-fb57-4f7d-b7fe-f060b5caa3f2",name:"Barrinhas de Chocolate de Leite Kinder",price:"5.1917",pid:"4968830"},
  {id:"cnt-339279",name:"Edred&atilde;o Polar Liso Verde Kasa",price:"20",pid:"339279"},
  {id:"61217ddf-9332-427a-9809-259a0f8c5e36",name:"Mirtilos Origens Bio",price:"4.9916",pid:"7594144"},
  {id:"cnt-7506195",name:"Secador de Roupa Laranja 1000W Jocel",price:"79.99",pid:"7506195"},
];

const UA = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36";
const HOST = "www.continente.pt";
const PATH_BASE = "/on/demandware.store/Sites-continente-Site/pt_PT/Product-Show?pid=";

const OUT_JSON     = ".claude/.ai/tmp/continente_smoke.json";
const PROGRESS_LOG = ".claude/.ai/tmp/continente_smoke_progress.log";

function logProgress(line){
  try { fs.appendFileSync(PROGRESS_LOG, line + "\n"); } catch(e){}
  console.log(line);
}

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

function _request(host, pathStr, cookie){
  return new Promise((resolve)=>{
    const headers = {
      "User-Agent": UA,
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
    req.on("error",e=>resolve({status:null, headers:{}, body:"", err:e.code || e.message}));
    req.on("timeout",()=>{req.destroy();resolve({status:null, headers:{}, body:"", err:"timeout"});});
    req.end();
  });
}

async function fetchPid(pid){
  let host = HOST;
  let pth = PATH_BASE + pid;
  let cookie = null;
  for (let hops=0; hops<5; hops++){
    const r = await _request(host, pth, cookie);
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
      const off = d.offers;
      if (off && typeof off === "object"){
        if (Array.isArray(off)) price = off[0]?.price ?? off[0]?.lowPrice ?? null;
        else price = off.price ?? off.lowPrice ?? null;
      }
      return { name, price };
    }
  }
  return { name: null, price: null };
}

function sleep(ms){ return new Promise(r=>setTimeout(r,ms)); }

(async () => {
  try { fs.mkdirSync(path.dirname(OUT_JSON), { recursive: true }); } catch(e){}
  try { fs.writeFileSync(PROGRESS_LOG, ""); } catch(e){}
  const t0 = Date.now();
  const results = [];
  let blocked = false;

  logProgress(`[start] ${new Date().toISOString()}  n=${products.length}`);

  for (let i=0; i<products.length; i++){
    const p = products[i];
    if (blocked){ results.push({...p, status:"skipped-after-block"}); continue; }

    let attempt = 0, resp;
    while (true){
      resp = await fetchPid(p.pid);
      if ((resp.status===429 || resp.status===503) && attempt<2){
        attempt++;
        logProgress(`[${i+1}/${products.length}] ${p.pid} got ${resp.status}, backoff...`);
        await sleep(12000 + Math.random()*5000);
        continue;
      }
      break;
    }

    const entry = {
      i: i+1, id: p.id, pid: p.pid, bd_name: decodeEnt(p.name),
      bd_price: p.price!==null && p.price!=="" ? parseFloat(p.price) : null,
      http: resp.status, site_name: null, site_price: null, status: null, diff: null,
    };

    if (resp.status===429){
      entry.status="blocked-429";
      blocked=true;
      results.push(entry);
      logProgress(`[${i+1}/${products.length}] ${p.pid} BLOCKED 429 -> STOP`);
      break;
    }

    if (resp.err || resp.status!==200){
      entry.status = `erro(${resp.err||resp.status})`;
      results.push(entry);
      logProgress(`[${i+1}/${products.length}] ${p.pid} ${entry.status}`);
    } else {
      const { name, price } = extractPriceName(resp.body);
      entry.site_name = name ? decodeEnt(name) : null;
      const np = (price===null || price===undefined) ? null : parseFloat(price);
      entry.site_price = Number.isFinite(np) ? np : null;
      if (entry.site_price === null){
        entry.status = "não encontrado";
      } else {
        const bdr = Math.round(entry.bd_price*100)/100;
        const d = Math.round((entry.site_price - bdr)*100)/100;
        entry.diff = d;
        // name similarity: first 4 chars of each word, lowercase, ignore accents
        const norm = s => (s||"").toLowerCase()
          .normalize("NFD").replace(/[̀-ͯ]/g,"")
          .split(/\s+/).filter(Boolean).map(w=>w.slice(0,4));
        const a = norm(entry.bd_name), b = norm(entry.site_name);
        const setB = new Set(b);
        const shared = a.filter(x=>setB.has(x)).length;
        const ratio = a.length ? shared/a.length : 0;
        entry.name_match = +ratio.toFixed(2);
        if (ratio < 0.3){
          entry.status = Math.abs(d) <= 0.01 ? "igual-NOME_DIFERENTE" : "diferente-NOME_DIFERENTE";
        } else {
          entry.status = Math.abs(d) <= 0.01 ? "igual" : "diferente";
        }
      }
      results.push(entry);
      logProgress(`[${i+1}/${products.length}] ${p.pid} ${entry.status} bd=${entry.bd_price} site=${entry.site_price ?? "-"} Δ=${entry.diff ?? "-"}`);
    }

    try { fs.writeFileSync(OUT_JSON, JSON.stringify({elapsed_s: (Date.now()-t0)/1000, blocked, results}, null, 2)); } catch(e){}

    if (i < products.length-1){
      const wait = 4500 + (Math.random()*1600 - 800);
      await sleep(wait);
    }
  }

  const elapsed = ((Date.now()-t0)/1000).toFixed(1);
  try { fs.writeFileSync(OUT_JSON, JSON.stringify({elapsed_s: +elapsed, blocked, results}, null, 2)); } catch(e){}

  const igual = results.filter(r=>r.status==="igual").length;
  const dif   = results.filter(r=>r.status==="diferente").length;
  const ne    = results.filter(r=>r.status==="não encontrado").length;
  const err   = results.filter(r=>(r.status||"").startsWith("erro") || r.status==="blocked-429").length;

  logProgress(`\n[done] elapsed=${elapsed}s  total=${results.length}  igual=${igual}  dif=${dif}  não-encontrado=${ne}  erro=${err}  blocked=${blocked}`);
})().catch(e => {
  logProgress("FATAL: " + e.message + "\n" + e.stack);
  process.exit(1);
});

#!/usr/bin/env node
/**
 * uber_apply_rebuild.js — Aplica o harvest do uber_eats_intermarche_crawler.js à tabela products
 * via PostgREST (service role), upsert on_conflict=id, lotes de 200. Espelha glovo_apply_rebuild.
 *
 * Pré: backend/.env (SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY) + harvest JSON do crawler.
 * O harvest já traz: id ('int-'+uuid), name, price (EUROS, =cêntimos/100, sem -15%), img, root, sort_order.
 * category = root (categoria top Uber); trigger trg_products_set_category_root deriva category_root.
 *
 * ANTES de correr: criar backup + DELETE (ver SEQUÊNCIA no relatório). Detecta placeholders (img >5x).
 * Uso: node uber_apply_rebuild.js <harvest.json> [restaurant_id]
 */
'use strict';
const fs = require('fs'); const https = require('https'); const { URL } = require('url');
function loadEnv(f){const t=fs.readFileSync(f,'utf8');const e={};for(const m of t.matchAll(/^([A-Z_]+)\s*=\s*(.*)$/gm))e[m[1]]=m[2].trim().replace(/^["']|["']$/g,'');return e;}
const env=loadEnv('backend/.env'); const KEY=env.SUPABASE_SERVICE_ROLE_KEY; const REST=env.SUPABASE_URL.replace(/\/$/,'')+'/rest/v1';
const sleep=ms=>new Promise(r=>setTimeout(r,ms));
function post(path,body,extra){return new Promise(res=>{const u=new URL(REST+path);const data=JSON.stringify(body);const headers={apikey:KEY,authorization:'Bearer '+KEY,'content-type':'application/json','content-length':Buffer.byteLength(data),...(extra||{})};const r=https.request({hostname:u.hostname,path:u.pathname+u.search,method:'POST',headers},resp=>{let d='';resp.on('data',c=>d+=c);resp.on('end',()=>res({status:resp.statusCode,body:d}));});r.on('error',e=>res({status:0,body:e.message}));r.write(data);r.end();});}
(async()=>{
  const IN=process.argv[2]||'uber_intermarche.json'; const RID=process.argv[3]||'intermarche-guarda';
  const H=JSON.parse(fs.readFileSync(IN,'utf8'));
  // placeholder guard: same img used by >5 products
  const freq={}; for(const p of H) if(p.img) freq[p.img]=(freq[p.img]||0)+1;
  const ph=new Set(Object.entries(freq).filter(([,n])=>n>5).map(([u])=>u));
  console.log('produtos:',H.length,'| placeholders rejeitados (img>5x):',[...ph].length);
  const seen=new Set(); const rows=[];
  for(const p of H){ if(seen.has(p.id))continue; seen.add(p.id); if(!p.name||p.price==null)continue;
    rows.push({id:p.id,restaurant_id:RID,name:p.name,photo_url:ph.has(p.img)?null:(p.img||null),price:p.price,
      category_root:p.root||null,category:p.root||null,is_available:true,source:'uber_rebuild_2026_06_07',
      image_source:'uber_official',needs_photo:ph.has(p.img),last_updated:'2026-06-07',sort_order:p.sort_order||null}); }
  console.log('rows to upsert:',rows.length);
  let ok=0,fail=0;const errs=[];
  for(let i=0;i<rows.length;i+=200){const b=rows.slice(i,i+200);let r,t=0;
    do{r=await post('/products?on_conflict=id',b,{Prefer:'resolution=merge-duplicates,return=minimal'});if(r.status>=200&&r.status<300)break;t++;await sleep(3000*t);}while(t<3);
    if(r.status>=200&&r.status<300)ok+=b.length;else{fail+=b.length;if(errs.length<3)errs.push(r.status+':'+r.body.slice(0,150));}
    await sleep(350);}
  console.log('UPSERT ok='+ok+' fail='+fail);if(errs.length)console.log(errs.join('\n'));
})();

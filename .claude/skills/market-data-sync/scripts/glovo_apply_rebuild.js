#!/usr/bin/env node
/**
 * glovo_apply_rebuild.js — Aplica um harvest do glovo_grocery_crawler.js à tabela products
 * via PostgREST (service role), em modo upsert (on_conflict=id), lotes de 200.
 * Criado no rebuild Auchan 2026-06-06.
 *
 * Pré: backend/.env com SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY.
 * Uso:  node glovo_apply_rebuild.js <harvest.json> <restaurant_id> <id_prefix>
 *   ex: node glovo_apply_rebuild.js out.json auchan-guarda auc-
 *
 * Convenção de categoria (schema Bora): trigger trg_products_set_category_root faz
 * category_root := split_part(category,'/',1). As lojas usam category = categoria TOP (plano).
 * Por isso gravamos category = root (categoria top da fonte). A sub-secção fica na ORDEM (sort_order).
 *
 * sort_order = sequência da fonte (categorias na ordem da home + produtos por secção).
 * Requer ROOT_ORDER (ordem das categorias top como aparecem na home da fonte).
 * Preço = preço da fonte direto (Glovo grocery = "mesmo preço que loja" = preço-base).
 */
'use strict';
const fs = require('fs'); const https = require('https'); const { URL } = require('url');
function loadEnv(f){const t=fs.readFileSync(f,'utf8');const e={};for(const m of t.matchAll(/^([A-Z_]+)\s*=\s*(.*)$/gm))e[m[1]]=m[2].trim().replace(/^["']|["']$/g,'');return e;}
const env=loadEnv('backend/.env'); const KEY=env.SUPABASE_SERVICE_ROLE_KEY; const REST=env.SUPABASE_URL.replace(/\/$/,'')+'/rest/v1';
const sleep=ms=>new Promise(r=>setTimeout(r,ms));
function post(path, body, extra){return new Promise(res=>{const u=new URL(REST+path);const data=JSON.stringify(body);const headers={apikey:KEY,authorization:'Bearer '+KEY,'content-type':'application/json','content-length':Buffer.byteLength(data),...(extra||{})};const r=https.request({hostname:u.hostname,path:u.pathname+u.search,method:'POST',headers},resp=>{let d='';resp.on('data',c=>d+=c);resp.on('end',()=>res({status:resp.statusCode,body:d}));});r.on('error',e=>res({status:0,body:e.message}));r.write(data);r.end();});}

// Ordem das 21 categorias top da home Glovo Auchan Guarda. Ajustar por loja.
const ROOT_ORDER=['Frutas e Vegetais','Talho e Peixaria','Charcutaria e Queijos','Padaria e Pastelaria','Laticínios e Ovos','Mercearia','Mercearia Doce','Refeições Frescas','Gelados e Congelados','Águas e Sumos','Cervejas e Sidras','Vinhos e Espumantes','Bebidas Espirituosas','Bio e Saudável','Beleza e Higiene','Saúde e Bem-Estar','Limpeza','Bebé e Criança','Animais de Estimação','Casa e Decoração','Bricolage, Jardim e Auto'];

(async()=>{
  const IN=process.argv[2]||'harvest.json';
  const RID=process.argv[3]||'auchan-guarda';
  const PREFIX=process.argv[4]||'auc-';
  const H=JSON.parse(fs.readFileSync(IN,'utf8'));
  const rootIdx=r=>{const i=ROOT_ORDER.indexOf(r);return i<0?999:i;};
  const seen=new Set(); let raw=[];
  for(let k=0;k<H.length;k++){const p=H[k];const id=PREFIX+p.id;if(seen.has(id))continue;seen.add(id);if(!p.name||p.price==null)continue;
    raw.push({_ri:rootIdx(p.root),_k:k,id,restaurant_id:RID,name:p.name,photo_url:p.img||null,price:p.price,
      category_root:p.root||null,category:p.root||null,is_available:true,source:'glovo_rebuild_2026_06_06',image_source:'glovo_official',needs_photo:false,last_updated:'2026-06-06'});}
  raw.sort((a,b)=>a._ri-b._ri||a._k-b._k);
  const rows=raw.map((r,i)=>{const{_ri,_k,...rest}=r;return{...rest,sort_order:i};});
  console.log('rows:',rows.length);
  let ok=0,fail=0;const errs=[];
  for(let i=0;i<rows.length;i+=200){const batch=rows.slice(i,i+200);let r,t=0;
    do{r=await post('/products?on_conflict=id',batch,{Prefer:'resolution=merge-duplicates,return=minimal'});if(r.status>=200&&r.status<300)break;t++;await sleep(3000*t);}while(t<3);
    if(r.status>=200&&r.status<300)ok+=batch.length;else{fail+=batch.length;if(errs.length<3)errs.push(r.status+':'+r.body.slice(0,160));}
    await sleep(350);}
  console.log('UPSERT ok='+ok+' fail='+fail);if(errs.length)console.log(errs.join('\n'));
})();

// Gera a carga final dos produtos das farmácias (corre DEPOIS das migrações 01 e 02 estarem no ar).
// - Só produtos com foto real no nosso Storage (os sem foto ficam de fora e vão no relatório).
// - Nome limpo: a Glovo cola a lista de ingredientes ("... X60 MELATONINA [PA] LAVANDA ...") ao nome;
//   corta-se depois da embalagem e guarda-se o original em name_original.
// - price = preço da Glovo (o que o cliente vê); partner_shelf_price = price*0,90/1,05 (balcão provisório);
//   preco_provisorio = true; is_medicine do catálogo.
import { readFileSync, writeFileSync } from 'node:fs';

const LOJAS = ['farmacia-se-guarda', 'farmacia-teixeira-guarda'];
const q = (v) => (v === null || v === undefined ? 'null' : `'${String(v).replace(/'/g, "''")}'`);
const EMB = /\b(x ?\d+(?:[.,]\d+)?|\d+(?:[.,]\d+)? ?(?:ml|mg|g|kg|l|un|und|unid|caps|cps|comp|saq|amp|doses|cl))\b/gi;

export function limparNome(nome) {
  const i = nome.indexOf('[PA]');
  if (i < 0) return nome.trim();
  const antes = nome.slice(0, i);
  let corte = -1;
  for (const m of antes.matchAll(EMB)) corte = m.index + m[0].length;
  let limpo;
  if (corte > 0) {
    limpo = antes.slice(0, corte);
  } else {
    // sem embalagem: tira o 1.º ingrediente (a última palavra antes de [PA])
    limpo = antes.trim().replace(/\s+\S+$/, '');
  }
  limpo = limpo.replace(/[\s\-,;]+$/, '').trim();
  return limpo.length >= 4 ? limpo : nome.trim();
}

const resumo = [];
let sql = `-- Carga dos produtos das farmácias (missão farmacias-2026-11-11). Gerado por gerar_carga_final.mjs.\n` +
  `-- Correr só DEPOIS das migrações 01 (lista de permissão) e 02 (colunas is_medicine/preco_provisorio).\n` +
  `do $$ begin\n  if not exists (select 1 from information_schema.columns where table_name='products' and column_name='preco_provisorio')\n` +
  `     or not exists (select 1 from pg_proc where proname='lojas_escondidas_para_mim') then\n` +
  `    raise exception 'Faltam as migrações 01/02 das farmácias: não carregar produtos antes do filtro de visibilidade.';\n  end if;\nend $$;\n`;
for (const loja of LOJAS) {
  const j = JSON.parse(readFileSync(new URL(`./${loja}.json`, import.meta.url), 'utf8'));
  const lista = Array.isArray(j) ? j : j.produtos;
  const comFoto = lista.filter((p) => p.photo_url && Number(p.price_cents_glovo) > 0);
  let limpos = 0;
  const linhas = comFoto.map((p) => {
    const nome = limparNome(p.name);
    if (nome !== p.name.trim()) limpos++;
    const preco = (Number(p.price_cents_glovo) / 100).toFixed(2);
    const balcao = (Math.round(Number(p.price_cents_glovo) * 0.9 / 1.05) / 100).toFixed(2);
    return `(${q(p.id)}, ${q(loja)}, ${q(nome)}, ${nome !== p.name.trim() ? q(p.name) : 'null'}, ${q(p.description || null)}, ` +
      `${q(p.category)}, ${preco}, ${balcao}, ${q(p.photo_url)}, true, 'glovo-provisorio-2026-11-11', 'glovo', false, false, ` +
      `${Number(p.sort_order) || 0}, '2026-11-11', ${p.is_medicine === false ? 'false' : 'true'}, true)`;
  });
  for (let i = 0; i < linhas.length; i += 200) {
    sql += `insert into public.products (id, restaurant_id, name, name_original, description, category, price, partner_shelf_price, ` +
      `photo_url, is_available, source, image_source, needs_photo, requires_prescription, sort_order, last_updated, is_medicine, preco_provisorio)\nvalues\n` +
      linhas.slice(i, i + 200).join(',\n') + `\non conflict (id) do nothing;\n`;
  }
  resumo.push(`${loja}: glovo=${lista.length} com_foto=${comFoto.length} sem_foto=${lista.length - comFoto.length} nomes_limpos=${limpos}`);
}
writeFileSync(new URL('./carga_final.sql', import.meta.url), sql);
console.log(resumo.join('\n'));

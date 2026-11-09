// Prova local (PGlite = Postgres 16 em WASM) da migração 20261109070000_pesquisa_inteligente.sql
// — missão m11, 09/11/2026. Nada toca em produção.
//
// Uso: node prova_pglite.mjs <pasta-com-node_modules-do-pglite-0.2.17> <migracao.sql> <casos.csv>
//
// O prelúdio copia de produção (pg_get_functiondef, lido a 09/11) as funções de ajuda que a
// pesquisa usa (bora_normalize, f_unaccent, assistant_singular, assistant_tokens), o gatilho de
// search_normalized, as versões ANTIGAS de search_products e cliente_pesquisar (com os mesmos
// GRANTs, para provar que o CREATE OR REPLACE os mantém) e tabelas mínimas com dados de amostra.
import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { pathToFileURL } from 'node:url';
import { partes, cteSinonimos, corpoCom, selectCasos } from './gerar_select_equivalente.mjs';

const [, , pasta, migracao, casosCsv] = process.argv;
const mod = (p) => import(pathToFileURL(join(pasta, 'node_modules/@electric-sql/pglite/dist', p)).href);
const { PGlite } = await mod('index.js');
const { pg_trgm } = await mod('contrib/pg_trgm.js');
const { vector } = await mod('vector/index.js');
const unaccent = {
  name: 'unaccent',
  setup: async () => ({ bundlePath: pathToFileURL(join(pasta, 'node_modules/@electric-sql/pglite/dist/unaccent.tar.gz')) }),
};

process.on('unhandledRejection', (e) => { console.error('ERRO:', e.message, e.position ?? ''); process.exit(2); });
const db = await PGlite.create({ extensions: { pg_trgm, vector, unaccent } });
let falhas = 0;
const ok = (cond, msg) => {
  console.log(`${cond ? 'OK   ' : 'FALHA'} ${msg}`);
  if (!cond) falhas++;
};
const um = async (sql, params) => (await db.query(sql, params)).rows;

const PRELUDIO = `
create role anon nologin; create role authenticated nologin; create role service_role nologin;
create schema extensions;
create extension pg_trgm schema extensions;
create extension vector schema extensions;
create extension unaccent schema extensions;
grant usage on schema extensions to anon, authenticated, service_role;
grant usage on schema public to anon, authenticated, service_role;
create schema auth;
grant usage on schema auth to anon, authenticated, service_role;
create function auth.uid() returns uuid language sql stable as
  $$ select nullif(current_setting('prova.uid', true), '')::uuid $$;
grant execute on function auth.uid() to anon, authenticated, service_role;
create function public.is_admin() returns boolean language sql stable as
  $$ select coalesce(current_setting('prova.admin', true), '') = 'sim' $$;
grant execute on function public.is_admin() to anon, authenticated, service_role;
create table public.admin_audit_log (id bigserial primary key, action text, target_table text, target_id text, details jsonb, quando timestamptz default now());
create function public.log_admin_action(p_action text, p_table text, p_id text, p_details jsonb) returns void
  language sql security definer as $$ insert into public.admin_audit_log (action, target_table, target_id, details) values (p_action, p_table, p_id, p_details) $$;
grant execute on function public.log_admin_action(text,text,text,jsonb) to authenticated;
grant select on public.admin_audit_log to authenticated; -- só para a prova ler a auditoria

-- funções de ajuda, iguais às de produção (09/11/2026)
CREATE OR REPLACE FUNCTION public.bora_normalize(input text) RETURNS text LANGUAGE sql IMMUTABLE PARALLEL SAFE
 SET search_path TO 'public', 'extensions', 'pg_temp'
AS $function$
  SELECT regexp_replace(
    lower(extensions.unaccent('extensions.unaccent', COALESCE(input, ''))),
    '[^a-z0-9]+', ' ', 'g'
  )
$function$;
CREATE OR REPLACE FUNCTION public.f_unaccent(p text) RETURNS text LANGUAGE sql IMMUTABLE PARALLEL SAFE STRICT
 SET search_path TO 'public', 'extensions'
AS $function$
  select lower(extensions.unaccent('extensions.unaccent'::regdictionary, p));
$function$;
CREATE OR REPLACE FUNCTION public.assistant_singular(p_w text) RETURNS text LANGUAGE sql IMMUTABLE PARALLEL SAFE STRICT
 SET search_path TO 'public'
AS $function$
  select case
    when length(p_w) <= 3 or p_w ~ '^[0-9]' then p_w
    when p_w ~ 'oes$' then regexp_replace(p_w, 'oes$', 'ao')
    when p_w ~ 'aes$' then regexp_replace(p_w, 'aes$', 'ao')
    when p_w ~ 'ais$' then regexp_replace(p_w, 'ais$', 'al')
    when p_w ~ 'eis$' then regexp_replace(p_w, 'eis$', 'el')
    when p_w ~ 'ois$' then regexp_replace(p_w, 'ois$', 'ol')
    when p_w ~ 'ns$'  then regexp_replace(p_w, 'ns$', 'm')
    when length(p_w) > 4 and p_w ~ '[rz]es$' then left(p_w, -2)
    when p_w ~ '[^s]s$' then left(p_w, -1)
    else p_w
  end;
$function$;
CREATE OR REPLACE FUNCTION public.assistant_tokens(p_texto text) RETURNS text[] LANGUAGE sql IMMUTABLE PARALLEL SAFE
 SET search_path TO 'public'
AS $function$
  select coalesce(array_agg(public.assistant_singular(t.w) order by t.o), '{}'::text[])
    from regexp_split_to_table(
           btrim(regexp_replace(public.f_unaccent(coalesce(p_texto, '')), '[^a-z0-9]+', ' ', 'g')),
           ' ') with ordinality as t(w, o)
   where t.w <> ''
     and t.w not in ('de','da','do','das','dos','em','e','a','o','os','as','para','p',
                     'ao','aos','na','no','nas','nos','c','um','uma','ou','pra');
$function$;
grant execute on function public.bora_normalize(text), public.f_unaccent(text), public.assistant_singular(text), public.assistant_tokens(text) to anon, authenticated, service_role;

create table public.restaurants (
  id text primary key, name text, category text, cuisine_type text, photo_url text, cover_url text,
  is_partner boolean default false, coming_soon boolean default false, is_online boolean default true,
  approval_status text default 'approved', is_active_admin boolean default true);
create table public.products (
  id text primary key, restaurant_id text references public.restaurants(id), name text, description text,
  category text, category_root text, price numeric, photo_url text, is_available boolean default true,
  is_popular boolean default false, search_normalized text);
CREATE OR REPLACE FUNCTION public.fn_products_set_search_normalized() RETURNS trigger LANGUAGE plpgsql
 SET search_path TO 'public', 'extensions', 'pg_temp'
AS $function$
BEGIN
  NEW.search_normalized := public.bora_normalize(COALESCE(NEW.name, '') || ' ' || COALESCE(NEW.category, ''));
  RETURN NEW;
END;
$function$;
create trigger trg_sn before insert or update on public.products for each row execute function public.fn_products_set_search_normalized();
create index idx_products_search_trgm on public.products using gin (search_normalized extensions.gin_trgm_ops);
create index idx_products_restaurant_id on public.products (restaurant_id) where is_available = true;
alter table public.products enable row level security;
create policy products_ler on public.products for select using (true);
alter table public.restaurants enable row level security;
create policy restaurants_ler on public.restaurants for select using (true);
grant select on public.products, public.restaurants to anon, authenticated;
create table public.product_embeddings (product_id text primary key, embedding extensions.vector(768), model text, updated_at timestamptz default now());
create table public.product_embeddings_gte (product_id text primary key, embedding extensions.vector(384), model text, updated_at timestamptz default now());
grant select on public.product_embeddings, public.product_embeddings_gte to anon, authenticated;
`;

// versões ANTIGAS (produção 09/11) — para provar que o REPLACE mantém os GRANTs
const ANTIGAS = `
CREATE OR REPLACE FUNCTION public.search_products(query_text text, p_restaurant_id text DEFAULT NULL::text, max_results integer DEFAULT 50)
 RETURNS TABLE(result_type text, id text, name text, category text, category_root text, price numeric, photo_url text, match_rank real)
 LANGUAGE plpgsql STABLE SET search_path TO 'public', 'extensions', 'pg_temp'
AS $function$
BEGIN
  RETURN QUERY SELECT 'product'::text, p.id, p.name, p.category, p.category_root, p.price, p.photo_url, 1::real
    FROM public.products p WHERE p.search_normalized LIKE '%' || public.bora_normalize(query_text) || '%'
     AND (p_restaurant_id IS NULL OR p.restaurant_id = p_restaurant_id) LIMIT max_results;
END;
$function$;
revoke all on function public.search_products(text,text,integer) from public;
grant execute on function public.search_products(text,text,integer) to public, anon, authenticated, service_role;
CREATE OR REPLACE FUNCTION public.cliente_pesquisar(p_q text, p_limit integer DEFAULT 30) RETURNS jsonb
 LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public', 'extensions'
AS $function$ begin return '{}'::jsonb; end $function$;
revoke all on function public.cliente_pesquisar(text,integer) from public;
grant execute on function public.cliente_pesquisar(text,integer) to anon, authenticated, service_role;
`;

const AMOSTRA = `
insert into public.restaurants (id, name, category) values
 ('mcdonalds-guarda','McDonald''s','restaurant'), ('wells-guarda','Wells','pharmacy'),
 ('continente-guarda','Continente','supermarket'), ('kfc-guarda','KFC','restaurant');
insert into public.restaurants (id, name, category, approval_status) values ('pendente','Pendente','restaurant','pending');
insert into public.products (id, restaurant_id, name, category, category_root, price) values
 ('m1','mcdonalds-guarda','McFlurry® Oreo®','Sobremesas','Sobremesas',2.6),
 ('m2','mcdonalds-guarda','Sundae Caramelo','Sobremesas','Sobremesas',1.9),
 ('m3','mcdonalds-guarda','Batata Pequena','Acompanhamentos e Molhos','Acompanhamentos',1.5),
 ('m4','mcdonalds-guarda','Coca-Cola Pequena','Bebidas','Bebidas',1.6),
 ('m5','mcdonalds-guarda','Big Mac®','Sanduíches e McMenus','Sanduiches',4.5),
 ('m6','mcdonalds-guarda','10 Chicken McNuggets®','Acompanhamentos e Molhos','Acompanhamentos',5.0),
 ('m7','mcdonalds-guarda','Hamburguer','Europoupança','Europoupanca',1.2),
 ('m8','mcdonalds-guarda','Tarte de Maçã','Sobremesas','Sobremesas',1.5),
 ('m9','mcdonalds-guarda','Molho Batatas','Acompanhamentos e Molhos','Acompanhamentos',0.4),
 ('m10','mcdonalds-guarda','Fanta Laranja Zero Pequena','Bebidas','Bebidas',1.6),
 ('w1','wells-guarda','Ben-U-Ron 500mg emb. 20 comprimidos','Saúde','Saude',3.1),
 ('w2','wells-guarda','Paracetamol Wellsmed emb. 20 comprimidos','Saúde','Saude',2.0),
 ('w3','wells-guarda','Toalhitas 99% Água Baby Wells','Bebé','Bebe',2.5),
 ('w4','wells-guarda','Máscara de Pestanas de Longa Duração','Maquilhagem','Maquilhagem',9.9),
 ('w5','wells-guarda','Champô Neutro','Cabelo','Cabelo',4.0),
 ('w6','wells-guarda','Nurofen Comprimidos Ibuprofeno 400mg','Saúde','Saude',5.0),
 ('w7','wells-guarda','Protetor Solar Corpo SPF50','Solares','Solares',12.0),
 ('c1','continente-guarda','Pão de Forma Continente','Padaria','Padaria',1.2),
 ('c2','continente-guarda','Papel Higiénico Renova 12 rolos','Higiene/Papel','Higiene',5.9),
 ('c3','continente-guarda','Gelado Baunilha Continente','Congelados/Gelados','Congelados',3.0),
 ('c4','continente-guarda','Favas Congeladas Iglo','Congelados','Congelados',2.0),
 ('c5','continente-guarda','Bolachas Maria Cuétara','Mercearia/Bolachas','Mercearia',1.1),
 ('c6','continente-guarda','Bola de Berlim','Padaria','Padaria',0.9),
 ('c7','continente-guarda','COCA COLA PET 1L','Bebidas/Refrigerantes','Bebidas',1.5),
 ('c8','continente-guarda','Pães de Leite (6 un)','Padaria','Padaria',1.9),
 ('c9','continente-guarda','Leite Meio Gordo Mimosa 1L','Laticínios/Leite','Laticinios',0.9),
 ('c10','continente-guarda','Iogurte Grego Natural','Laticínios/Iogurtes','Laticinios',2.2),
 ('k1','kfc-guarda','2 Pedaços de Frango','Complementos','Complementos',3.0),
 ('k2','kfc-guarda','Sundae Chocolate','Sobremesas','Sobremesas',1.9),
 ('k3','kfc-guarda','7Up Lata 33cl','Bebidas','Bebidas',1.8),
 ('x1','pendente','Gelado Escondido','Sobremesas','Sobremesas',1.0);
update public.products set is_available = false where id = 'm10';
update public.products set is_available = true where id = 'm10';
`;

await db.exec(PRELUDIO);
await db.exec(ANTIGAS);
await db.exec(AMOSTRA);

const migr = readFileSync(migracao, 'utf8');
// 1) a migração corre DUAS vezes sem erro (idempotente)
for (const vez of [1, 2]) {
  try {
    await db.exec(migr);
    ok(true, `migração aplicada (vez ${vez})`);
  } catch (e) {
    ok(false, `migração aplicada (vez ${vez}): ${e.message}`);
    process.exit(1);
  }
}
const nSin = (await um('select count(*)::int n from public.pesquisa_sinonimos'))[0].n;
ok(nSin > 150, `semente de sinónimos carregada uma só vez (${nSin} linhas, 2.ª corrida não duplica)`);

// 2) GRANTs: anon continua a poder usar o que search_products usa (erro de 20/10)
for (const f of ['public.search_products(text,text,integer)', 'public.cliente_pesquisar(text,integer)',
  'public.pesquisa_produtos(text,text,integer,extensions.vector)', 'public.bora_normalize(text)',
  'public.f_unaccent(text)', 'public.assistant_tokens(text)', 'public.assistant_singular(text)',
  'public.pesquisa_registar_sem_resultado(text,text,text)', 'public.pesquisa_aprender_escolha(text,text,text)']) {
  const r = (await um(`select has_function_privilege('anon', '${f}', 'execute') v`))[0].v;
  ok(r === true, `anon pode executar ${f}`);
}
for (const f of ['public.admin_pesquisas_sem_resultado(integer)', 'public.admin_pesquisa_criar_sinonimo(text,text,text,text)',
  'public.admin_pesquisa_sinonimo_ativo(bigint,boolean)', 'public.admin_pesquisa_sinonimos(text)',
  'public.pesquisa_produtos_sem_gemini(integer)']) {
  const r = (await um(`select has_function_privilege('anon', '${f}', 'execute') v`))[0].v;
  ok(r === false, `anon NÃO pode executar ${f}`);
}
ok((await um(`select has_table_privilege('anon','public.pesquisa_sem_resultado','select') v`))[0].v === false,
  'anon não lê pesquisa_sem_resultado');
ok((await um(`select has_table_privilege('anon','public.pesquisa_sinonimos','select') v`))[0].v === true,
  'anon lê os sinónimos (a pesquisa precisa)');

// 3) a SELECT equivalente (a que corre em produção) dá o MESMO que a função
const { corpo, valores } = partes(migracao);
const comparar = [['gelado', 'mcdonalds-guarda'], ['paracetamol', 'wells-guarda'], ['pao', 'continente-guarda'],
  ['bolaxas', 'continente-guarda'], ['cocacola', 'mcdonalds-guarda'], ['nugets', 'mcdonalds-guarda'],
  ['batatas fritas', 'mcdonalds-guarda'], ['papel higenico', 'continente-guarda'], ['gelado', null],
  ['rimel', 'wells-guarda'], ['sobremesa', 'mcdonalds-guarda']];
for (const [t, l] of comparar) {
  const f = await um(`select id, match_kind, round(score::numeric, 4) s from public.pesquisa_produtos($1, $2, 50)`, [t, l]);
  const sel = `with ${cteSinonimos(valores)} select z.id, z.kind as match_kind, round(z.score::numeric, 4) s from (${corpoCom(corpo, { q: '$1::text', loja: '$2::text' })}) z(id, name, category, category_root, price, photo_url, restaurant_id, kind, score)`;
  await db.exec(`set pg_trgm.word_similarity_threshold = 0.45`);
  const s = await um(sel, [t, l]);
  ok(JSON.stringify(f) === JSON.stringify(s), `SELECT equivalente = função para "${t}" @ ${l ?? 'lupa'} (${f.length} linhas)`);
}

// 4) comportamento como ANON (role anon, sem sessão)
await db.exec(`set role anon`);
const top = async (t, l) => (await um(`select name, category_root from public.search_products($1, $2, 50) where result_type = 'product'`, [t, l])).map((r) => r.name);
const secs = async (t, l) => (await um(`select name from public.search_products($1, $2, 50) where result_type = 'section'`, [t, l])).map((r) => r.name);
const tipo = async (t, l) => (await um(`select name, match_kind from public.pesquisa_produtos($1, $2, 50)`, [t, l]));
let r;
r = await top('gelado', 'mcdonalds-guarda');
ok(r.slice(0, 2).some((n) => /McFlurry|Sundae/.test(n)), `McDonald's "gelado" → ${r.slice(0, 3).join(' | ')}`);
r = await top('gelado oreo', 'mcdonalds-guarda');
ok(r[0] === 'McFlurry® Oreo®', `McDonald's "gelado oreo" → ${r[0]}`);
r = await top('batatas fritas', 'mcdonalds-guarda');
ok(r[0] === 'Batata Pequena', `McDonald's "batatas fritas" → ${r.slice(0, 2).join(' | ')}`);
r = await top('cocacola', 'mcdonalds-guarda');
ok(r[0] === 'Coca-Cola Pequena', `McDonald's "cocacola" → ${r[0]}`);
r = await top('refrigerante', 'mcdonalds-guarda');
ok(r.slice(0, 2).every((n) => /Coca|Fanta/.test(n)), `McDonald's "refrigerante" → ${r.slice(0, 2).join(' | ')}`);
r = await top('nugets', 'mcdonalds-guarda');
ok(r[0] === '10 Chicken McNuggets®', `McDonald's "nugets" (erro) → ${r[0]}`);
r = await top('bigmac', 'mcdonalds-guarda');
ok(r[0] === 'Big Mac®', `McDonald's "bigmac" (colado) → ${r[0]}`);
r = await top('sobremesa', 'mcdonalds-guarda');
ok(r.length >= 3, `McDonald's "sobremesa" (categoria) → ${r.length} produtos`);
r = await top('paracetamol', 'wells-guarda');
ok(r[0].startsWith('Paracetamol') && r.slice(0, 5).some((n) => n.startsWith('Ben-U-Ron')), `Wells "paracetamol" → ${r.slice(0, 3).join(' | ')}`);
r = await top('benuron', 'wells-guarda');
ok(r[0].startsWith('Ben-U-Ron'), `Wells "benuron" → ${r[0]}`);
r = await top('rimel', 'wells-guarda');
ok(r[0].startsWith('Máscara de Pestanas'), `Wells "rimel" → ${r[0]}`);
r = await top('toalhetes', 'wells-guarda');
ok(r[0].startsWith('Toalhitas'), `Wells "toalhetes" → ${r[0]}`);
r = await top('shampo', 'wells-guarda');
ok(r[0] === 'Champô Neutro', `Wells "shampo" → ${r[0]}`);
r = await top('brufen', 'wells-guarda');
ok(r[0].startsWith('Nurofen'), `Wells "brufen" → ${r[0]}`);
r = await top('protector solar', 'wells-guarda');
ok(r[0].startsWith('Protetor Solar'), `Wells "protector solar" → ${r[0]}`);
r = await top('pao', 'continente-guarda');
ok(r.includes('Pão de Forma Continente') && r.includes('Pães de Leite (6 un)'), `Continente "pao" acha "Pão…" e "Pães…" → ${r.slice(0, 3).join(' | ')}`);
r = await top('gelado', 'continente-guarda');
ok(r[0] === 'Gelado Baunilha Continente' && !r.includes('Favas Congeladas Iglo'), `Continente "gelado" sem "Congelados" → ${r.join(' | ')}`);
r = await top('bolaxas', 'continente-guarda');
ok(r[0] === 'Bolachas Maria Cuétara', `Continente "bolaxas" → ${r.slice(0, 2).join(' | ')}`);
r = await top('papel higenico', 'continente-guarda');
ok(r[0].startsWith('Papel Higiénico'), `Continente "papel higenico" → ${r[0]}`);
r = await top('leite meio gordo', 'continente-guarda');
ok(r[0].startsWith('Leite Meio Gordo'), `Continente "leite meio gordo" → ${r[0]}`);
r = await top('iogurtes', 'continente-guarda');
ok(r[0] === 'Iogurte Grego Natural', `Continente "iogurtes" → ${r[0]}`);
r = await top('frango', 'kfc-guarda');
ok(r[0] === '2 Pedaços de Frango', `KFC "frango" → ${r[0]}`);
r = await top('gelado', 'kfc-guarda');
ok(r[0] === 'Sundae Chocolate', `KFC "gelado" → ${r[0]}`);
r = await secs('sobremesa', 'mcdonalds-guarda');
ok(r.includes('Sobremesas'), `search_products devolve a secção "Sobremesas" → ${r.join(', ')}`);
r = await top('xptoqwerty', 'mcdonalds-guarda');
ok(r.length === 0, 'termo sem nada → 0 produtos (a app mostra "Pede ao Amigo")');
r = await top('a', 'mcdonalds-guarda');
ok(r.length === 0, 'termo de 1 letra → 0 produtos');
// lupa global: só lojas aprovadas
const lupa = await um(`select public.cliente_pesquisar('gelado', 30) j`);
const nomes = lupa[0].j.produtos.map((p) => p.name);
ok(nomes.includes('Gelado Baunilha Continente') && !nomes.includes('Gelado Escondido'), `lupa "gelado" (só lojas aprovadas) → ${nomes.slice(0, 4).join(' | ')}`);
ok(lupa[0].j.produtos[0].restaurant_name !== undefined && lupa[0].j.produtos[0].coming_soon !== undefined,
  'lupa devolve os mesmos campos de antes (restaurant_name, coming_soon…)');
// ordem: exato > começa > texto > sinónimo > categoria
const ord = await tipo('hamburguer', 'mcdonalds-guarda');
ok(ord[0].match_kind === 'exato' && ord.some((x) => x.match_kind === 'sinonimo'), `ordem "hamburguer": ${ord.map((x) => x.match_kind).join(' > ')}`);
const ord2 = await tipo('paracetamol', 'wells-guarda');
const pos = (k) => ord2.findIndex((x) => x.match_kind === k);
ok(pos('comeca') < pos('sinonimo'), `ordem "paracetamol": ${ord2.map((x) => x.match_kind).join(' > ')}`);

// 5) RLS — anon (sem sessão)
let erro = null;
try { await db.query(`insert into public.pesquisa_sem_resultado (termo, restaurant_id) values ('xpto loja', 'wells-guarda')`); } catch (e) { erro = e.message; }
ok(erro === null, 'anon insere pesquisa sem resultado sem user_id');
erro = null;
try { await db.query(`insert into public.pesquisa_sem_resultado (termo, user_id) values ('xpto', '11111111-1111-1111-1111-111111111111')`); } catch (e) { erro = e.message; }
ok(erro !== null, `anon NÃO insere com user_id de outro (${(erro ?? '').slice(0, 60)})`);
erro = null;
try { await db.query(`select * from public.pesquisa_sem_resultado`); } catch (e) { erro = e.message; }
ok(erro !== null, 'anon NÃO lê as pesquisas sem resultado');
// RPC com repetição: a mesma pesquisa em 10 min conta uma vez
const a1 = (await um(`select public.pesquisa_registar_sem_resultado('gelado de pistacio', 'mcdonalds-guarda', 'loja') v`))[0].v;
const a2 = (await um(`select public.pesquisa_registar_sem_resultado('Gelado de Pistácio', 'mcdonalds-guarda', 'loja') v`))[0].v;
ok(a1 === true && a2 === false, 'RPC grava 1 vez e ignora a repetição (acentos/maiúsculas iguais)');

// 6) RLS — cliente com sessão
await db.exec(`reset role; set role authenticated; select set_config('prova.uid', '22222222-2222-2222-2222-222222222222', false)`);
erro = null;
try { await db.query(`insert into public.pesquisa_sem_resultado (termo, user_id) values ('minha', '22222222-2222-2222-2222-222222222222')`); } catch (e) { erro = e.message; }
ok(erro === null, 'cliente insere a SUA pesquisa');
erro = null;
try { await db.query(`insert into public.pesquisa_sem_resultado (termo, user_id) values ('alheia', '33333333-3333-3333-3333-333333333333')`); } catch (e) { erro = e.message; }
ok(erro !== null, 'cliente NÃO insere em nome de outro');
const visto = (await um(`select count(*)::int n from public.pesquisa_sem_resultado`))[0].n;
ok(visto === 0, 'cliente (não admin) não vê nenhuma linha');
erro = null;
try { await db.query(`select public.admin_pesquisas_sem_resultado(30)`); } catch (e) { erro = e.message; }
ok(/admin_required/.test(erro ?? ''), 'cliente não abre o painel (admin_required)');

// 7) aprende sozinha: 3 pessoas escolhem o mesmo produto depois de "docinho" sem resultado
await db.exec(`reset role; set role anon; select set_config('prova.uid', '', false)`);
r = await top('docinho', 'mcdonalds-guarda');
ok(r.length === 0, '"docinho" no McDonald\'s antes de aprender → 0');
for (const u of ['', 'aaaaaaaa-0000-0000-0000-000000000001', 'aaaaaaaa-0000-0000-0000-000000000002']) {
  await db.exec(`reset role; set role ${u ? 'authenticated' : 'anon'}; select set_config('prova.uid', '${u}', false)`);
  await um(`select public.pesquisa_aprender_escolha('docinho', 'mcdonalds-guarda', 'm8')`);
}
await db.exec(`reset role`);
let ap = await um(`select origem, vezes from public.pesquisa_sinonimos where chave = 'docinho'`);
ok(ap.length === 1 && ap[0].origem === 'aprendido' && ap[0].vezes === 3, `3 pessoas → sinónimo aprendido (${JSON.stringify(ap)})`);
await db.exec(`set role anon; select set_config('prova.uid', '', false)`);
r = await top('docinho', 'mcdonalds-guarda');
ok(r[0] === 'Tarte de Maçã', `"docinho" depois de aprender → ${r[0]}`);
// a mesma pessoa 3 vezes não chega
await db.exec(`reset role; set role authenticated; select set_config('prova.uid', 'aaaaaaaa-0000-0000-0000-000000000009', false)`);
for (let i = 0; i < 3; i++) await um(`select public.pesquisa_aprender_escolha('guloseima', 'mcdonalds-guarda', 'm8')`);
await db.exec(`reset role`);
ap = await um(`select count(*)::int n from public.pesquisa_sinonimos where chave = 'guloseima'`);
ok(ap[0].n === 0, 'a mesma pessoa 3 vezes NÃO cria sinónimo');

// 8) painel admin: lê, cria sinónimo (com auditoria), desliga
await db.exec(`set role authenticated; select set_config('prova.uid', '44444444-4444-4444-4444-444444444444', false); select set_config('prova.admin', 'sim', false)`);
const painel = (await um(`select public.admin_pesquisas_sem_resultado(30) j`))[0].j;
ok(painel.total >= 3 && painel.termos.some((t) => t.termo.toLowerCase().includes('pistacio') || t.termo.includes('Pistácio')), `painel lê ${painel.total} pesquisas, ${painel.termos_distintos} termos`);
const criado = (await um(`select public.admin_pesquisa_criar_sinonimo('pistacio', 'mcflurry', 'mcdonalds-guarda', null) j`))[0].j;
ok(criado.ok === true, `admin cria sinónimo pistacio→mcflurry (${JSON.stringify(criado)})`);
const criado2 = (await um(`select public.admin_pesquisa_criar_sinonimo('pistacio', 'mcflurry', 'mcdonalds-guarda', null) j`))[0].j;
ok(criado2.ok === true, 'criar o mesmo outra vez não rebenta (volta a ligar)');
const aud = (await um(`select count(*)::int n from public.admin_audit_log where action = 'pesquisa_criar_sinonimo'`))[0].n;
ok(aud === 2, `auditoria log_admin_action gravada (${aud})`);
const lista = (await um(`select public.admin_pesquisa_sinonimos('pistacio') j`))[0].j;
ok(lista.length === 1, 'lista de sinónimos filtra por termo');
const desl = (await um(`select public.admin_pesquisa_sinonimo_ativo(${lista[0].id}, false) j`))[0].j;
ok(desl.ok === true, 'admin desliga o sinónimo');
await db.exec(`reset role; set role anon; select set_config('prova.admin', '', false); select set_config('prova.uid', '', false)`);
r = await top('pistacio', 'mcdonalds-guarda');
ok(!r.includes('McFlurry® Oreo®'), 'sinónimo desligado deixa de contar');
await db.exec(`reset role`);
const resolvidas = (await um(`select count(*)::int n from public.pesquisa_sem_resultado where chave like 'gelado pistacio%' or chave = 'pistacio'`))[0].n;
ok(resolvidas >= 1, 'pesquisas do termo continuam registadas');

// 9) a SELECT dos 60 casos (a que corre em produção) corre aqui sem erro
await db.exec(`reset role`);
const res60 = await db.exec(selectCasos(migracao, casosCsv));
const ult = res60[res60.length - 1].rows;
ok(ult.length === 60 && ult.every((x) => x.ms !== null), `SELECT dos 60 casos corre (${ult.length} linhas, com tempo por caso)`);

console.log(falhas === 0 ? '\nTUDO CERTO' : `\n${falhas} FALHA(S)`);
process.exit(falhas === 0 ? 0 : 1);

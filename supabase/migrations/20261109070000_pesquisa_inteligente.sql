-- ════════════════════════════════════════════════════════════════════════════
-- PESQUISA INTELIGENTE — missão m11-amigo-rosto-2026-11-09, adendo 2, parte A.
-- Ordem do Danilo (09/11 05:40): "as pesquisas das lojas, dos mercados, do
-- McDonald's têm de ser super inteligentes; os clientes estão a reclamar muito
-- que não acham os produtos; eu mesmo fui na Wells e não achei".
--
-- O que muda (só acrescenta; nada de preços, pagamentos, pedidos, carteira):
--  1. public.pesquisa_produtos(...) — o motor ÚNICO de pesquisa de produtos,
--     usado dentro de cada loja (search_products) e na lupa da home
--     (cliente_pesquisar). Ordem: nome exato > começa por > contém o texto >
--     sinónimo > categoria > com erro de escrita > por significado > parcial.
--       • sem acentos, singular/plural, palavra parcial ("choco" → chocolate)
--       • tolerante a erros de escrita (trigramas + "nugets"/"bolaxas"/"shampo")
--       • palavras coladas ("cocacola", "bigmac", "benuron")
--       • sinónimos numa TABELA editável no painel (gelado → McFlurry/Sundae…)
--       • significado: vetores gte-small (todos os produtos têm) — sem API.
--  2. search_products e cliente_pesquisar mantêm a assinatura e o que devolvem
--     (as apps antigas no ar chamam-nas) e passam a usar o motor novo.
--  3. Aprende sozinha: pesquisas sem resultado ficam gravadas; quando o cliente
--     a seguir põe um produto no carrinho, guarda-se a escolha; 3 pessoas
--     diferentes com a mesma escolha → o sinónimo entra sozinho.
--  4. Painel admin (PT-BR): "Pesquisas sem resultado" + criar/desligar sinónimo,
--     com auditoria (log_admin_action).
--
-- ATENÇÃO (erro de 20/10): search_products é chamada por ANON. As funções de
-- ajuda que ela usa (bora_normalize, f_unaccent, assistant_tokens,
-- assistant_singular) NÃO são tocadas aqui, e a função nova tem GRANT a anon.
-- Idempotente: pode correr 2 vezes (provado em PGlite).
-- ════════════════════════════════════════════════════════════════════════════

-- ─── 1. Tabela de sinónimos ──────────────────────────────────────────────────
create table if not exists public.pesquisa_sinonimos (
  id            bigserial primary key,
  termo         text not null check (length(btrim(termo)) between 2 and 60),
  alvo          text check (alvo is null or length(btrim(alvo)) between 2 and 80),
  product_id    text references public.products(id) on delete cascade,
  restaurant_id text references public.restaurants(id) on delete cascade,
  chave         text not null default '',
  alvo_chave    text,
  origem        text not null default 'manual' check (origem in ('manual', 'admin', 'aprendido')),
  ativo         boolean not null default true,
  vezes         integer not null default 0,
  criado_por    uuid,
  criado_em     timestamptz not null default now(),
  constraint pesquisa_sinonimos_alvo_ou_produto check (alvo is not null or product_id is not null)
);

comment on table public.pesquisa_sinonimos is
  'Sinónimos da pesquisa (m11, 09/11/2026): o cliente escreve "termo" e a pesquisa também procura "alvo" (ou mostra product_id). restaurant_id nulo = todas as lojas. origem aprendido = 3 clientes escolheram o mesmo produto depois de uma pesquisa sem resultado.';

-- chave/alvo_chave = o texto como a pesquisa o compara (sem acentos, singular, sem "de/da/…")
create or replace function public.pesquisa_sinonimos_normalizar()
returns trigger
language plpgsql
set search_path = public, extensions, pg_temp
as $$
begin
  new.termo := btrim(new.termo);
  new.alvo := nullif(btrim(coalesce(new.alvo, '')), '');
  new.chave := array_to_string(public.assistant_tokens(new.termo), ' ');
  new.alvo_chave := case when new.alvo is null then null
                         else array_to_string(public.assistant_tokens(new.alvo), ' ') end;
  if new.chave = '' then
    raise exception 'termo_vazio: o termo não tem palavras que contem';
  end if;
  return new;
end;
$$;

drop trigger if exists trg_pesquisa_sinonimos_normalizar on public.pesquisa_sinonimos;
create trigger trg_pesquisa_sinonimos_normalizar
  before insert or update of termo, alvo on public.pesquisa_sinonimos
  for each row execute function public.pesquisa_sinonimos_normalizar();

create unique index if not exists uq_pesquisa_sinonimos
  on public.pesquisa_sinonimos (chave, coalesce(alvo_chave, ''), coalesce(product_id, ''), coalesce(restaurant_id, ''));
create index if not exists idx_pesquisa_sinonimos_chave
  on public.pesquisa_sinonimos (chave) where ativo;

alter table public.pesquisa_sinonimos enable row level security;
do $$ begin
  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'pesquisa_sinonimos' and policyname = 'sinonimos_ler_ativos') then
    create policy sinonimos_ler_ativos on public.pesquisa_sinonimos
      for select to anon, authenticated using (ativo or coalesce(public.is_admin(), false));
  end if;
end $$;
revoke all on public.pesquisa_sinonimos from anon, authenticated;
grant select on public.pesquisa_sinonimos to anon, authenticated;
grant all on public.pesquisa_sinonimos to service_role;

-- Semente (termo → alvo), todas as lojas. Editável depois no painel.
-- SEMENTE-INICIO
insert into public.pesquisa_sinonimos (termo, alvo, origem)
select v.termo, v.alvo, 'manual'
  from (values
  ('gelado','mcflurry'),('gelado','sundae'),('gelado','cone'),('gelado','magnum'),('gelado','cornetto'),
  ('gelado','king sandy'),('gelado','king fusion'),('gelado','ben jerry'),('gelado','haagen dazs'),
  ('gelado','carte d or'),('gelado','solero'),('gelado','mochi'),('gelado','kream'),
  ('sorvete','gelado'),('sorvete','mcflurry'),('sorvete','sundae'),
  ('sobremesa','sundae'),('sobremesa','mcflurry'),('sobremesa','tarte'),('sobremesa','gelado'),('sobremesa','brownie'),
  ('sobremesa','cheesecake'),('sobremesa','mousse'),
  ('refrigerante','coca cola'),('refrigerante','fanta'),('refrigerante','sumol'),('refrigerante','7up'),
  ('refrigerante','sprite'),('refrigerante','pepsi'),('refrigerante','ice tea'),('refrigerante','fuze tea'),
  ('refrigerante','guarana'),('refrigerante','schweppes'),('refrigerante','gasosa'),('refrigerante','seven up'),
  ('refri','coca cola'),('refri','fanta'),('refri','sumol'),('refri','pepsi'),('refri','refrigerante'),
  ('cocacola','coca cola'),('coca','coca cola'),('coke','coca cola'),('cola','coca cola'),('cola','pepsi'),
  ('sumo','nectar'),('sumo','compal'),('sumo','bongo'),('suco','sumo'),('suco','nectar'),('suco','compal'),
  ('cerveja','sagres'),('cerveja','super bock'),('cerveja','heineken'),('cerveja','desperados'),
  ('cerveja','estrella'),('cerveja','imperial'),('birra','cerveja'),
  ('batata','fries'),('batata','batata frita'),('frita','batata'),('frita','fries'),
  ('batata frita','batata'),('batata frita','fries'),('batata frita','chips'),('batata frita','ruffles'),
  ('batata frita','pringles'),('batata frita','lays'),
  ('hamburguer','burger'),('hamburguer','hamburger'),('hamburguer','cheeseburger'),('hamburguer','big mac'),
  ('hamburguer','big tasty'),('hamburguer','mcroyal'),('hamburguer','whopper'),('hamburguer','big king'),
  ('hamburguer','mcchicken'),('hamburguer','cbo'),('hamburguer','big arch'),('hamburguer','boom'),
  ('burger','hamburguer'),('burger','hamburger'),('hamburger','hamburguer'),('hamburger','burger'),
  ('nugget','mcnugget'),('nugget','nuggets'),
  ('frango','chicken'),('frango','pedaco'),('frango','tender'),('frango','hotwing'),('frango','wing'),
  ('frango','asa'),('frango','nugget'),('frango','mcchicken'),('frango','crispy'),
  ('chicken','frango'),('asa','wing'),('asa','hotwing'),
  ('kebab','durum'),('kebab','doner'),('durum','kebab'),
  ('sushi','maki'),('sushi','nigiri'),('sushi','sashimi'),('sushi','uramaki'),('sushi','hossomaki'),
  ('sushi','temaki'),('sushi','roll'),('sushi','combinado'),
  ('salmao','salmon'),('salmao','sake'),
  ('sandes','sanduiche'),('sandes','sandwich'),('sandes','tosta'),('sandes','wrap'),
  ('sanduiche','sandes'),('sanduiche','sandwich'),('sanduiche','tosta'),
  ('molho','dip'),('molho','ketchup'),('molho','maionese'),
  ('pao','baguete'),('pao','broa'),('pao','carcaca'),('pao','papo seco'),('pao','regueifa'),('pao','bolo do caco'),
  ('papel higienico','rolo higienico'),('papel wc','papel higienico'),('papel casa banho','papel higienico'),
  ('rolo','papel higienico'),
  ('rolo cozinha','papel cozinha'),('rolo cozinha','rolo de cozinha'),('papel cozinha','rolo cozinha'),
  ('champo','shampoo'),('shampoo','champo'),('xampu','champo'),('xampu','shampoo'),
  ('gel banho','gel duche'),('gel duche','gel banho'),('gel banho','gel de banho'),
  ('desodorizante','desodorante'),('desodorante','desodorizante'),('desodorizante','antitranspirante'),
  ('pasta dente','dentifrico'),('pasta dente','pasta dentifrica'),('pasta dente','pasta de dentes'),
  ('creme dental','pasta de dentes'),('creme dental','dentifrico'),('dentifrico','pasta de dentes'),
  ('toalhete','toalhita'),('toalhita','toalhete'),('lenco humido','toalhita'),
  ('lixivia','javel'),('agua sanitaria','lixivia'),
  ('lava loica','detergente loica'),('detergente loica','lava loica'),
  ('iogurte','yogurt'),('iogurte','yoghurt'),('yogurt','iogurte'),('iogurte','yogurte'),
  ('macarrao','massa'),('macarrao','esparguete'),('massa','esparguete'),
  ('linguica','chourico'),('toucinho','bacon'),('carne moida','carne picada'),
  ('abacaxi','ananas'),('ananas','abacaxi'),
  ('geleia','compota'),('geleia','doce'),
  ('biscoito','bolacha'),('bolacha','biscoito'),('bolacha','cookie'),
  ('paracetamol','ben u ron'),('paracetamol','panadol'),('paracetamol','supofen'),
  ('benuron','ben u ron'),('ben u ron','paracetamol'),
  ('ibuprofeno','nurofen'),('ibuprofeno','brufen'),('ibuprofeno','trifene'),('ibuprofeno','spidifen'),
  ('brufen','ibuprofeno'),('brufen','nurofen'),('nurofen','ibuprofeno'),
  ('aspirina','acido acetilsalicilico'),
  ('dor cabeca','paracetamol'),('dor cabeca','ben u ron'),('dor cabeca','ibuprofeno'),('dor cabeca','aspirina'),
  ('dor cabeca','nurofen'),
  ('febre','paracetamol'),('febre','ben u ron'),('febre','ibuprofeno'),('febre','termometro'),
  ('dor garganta','garganta'),('dor garganta','strepsils'),('dor garganta','strepfen'),('dor garganta','tantum'),
  ('garganta','strepsils'),('garganta','strepfen'),('garganta','tantum verde'),
  ('tosse','xarope'),('tosse','bisoltussin'),('tosse','stodal'),
  ('gripe','cegripe'),('gripe','antigrippine'),('constipacao','cegripe'),('constipacao','antigrippine'),
  ('azia','rennie'),('azia','gaviscon'),
  ('protetor solar','solar'),('protetor solar','spf'),('protector','protetor'),('filtro solar','protetor solar'),
  ('filtro solar','solar'),('creme solar','solar'),('bronzeador','solar'),
  ('rimel','mascara de pestanas'),('rimel','mascara pestanas'),('rimel','pestanas'),
  ('batom','baton'),('batom','labial'),('baton','batom'),
  ('esmalte','verniz'),('verniz','esmalte'),
  ('elixir','colutorio'),('colutorio','elixir'),('elixir bucal','colutorio'),('elixir bucal','elixir'),
  ('fio dental','fio dentario'),('fio dentario','fio dental'),
  ('curativo','penso'),('band aid','penso'),('penso','curativo'),
  ('absorvente','penso higienico'),('penso higienico','absorvente'),
  ('camisinha','preservativo'),('durex','preservativo'),
  ('chucha','chupeta'),('mamadeira','biberao'),
  ('gilete','lamina'),('gilete','barbear'),('lamina','barbear'),
  ('cotonete','bastonete'),('cotonete','cotonetes')
  ) as v(termo, alvo)
on conflict do nothing;
-- SEMENTE-FIM

-- ─── 2. Pesquisas sem resultado (o que os clientes não acharam) ─────────────
create table if not exists public.pesquisa_sem_resultado (
  id                bigserial primary key,
  termo             text not null check (length(btrim(termo)) between 2 and 80),
  chave             text not null default '',
  restaurant_id     text references public.restaurants(id) on delete set null,
  user_id           uuid default auth.uid(),
  origem            text not null default 'loja' check (origem in ('loja', 'lupa', 'amigo')),
  criado_em         timestamptz not null default now(),
  resolvido_em      timestamptz,
  produto_escolhido text
);
comment on table public.pesquisa_sem_resultado is
  'Cada pesquisa que não deu nenhum produto (m11, 09/11/2026). restaurant_id nulo = lupa da home. user_id nulo = cliente ainda sem sessão. O painel "Pesquisas sem resultado" lê daqui.';
create index if not exists idx_pesquisa_sem_resultado_quando on public.pesquisa_sem_resultado (criado_em desc);
create index if not exists idx_pesquisa_sem_resultado_chave on public.pesquisa_sem_resultado (chave, restaurant_id);

create or replace function public.pesquisa_sem_resultado_normalizar()
returns trigger
language plpgsql
set search_path = public, extensions, pg_temp
as $$
begin
  new.termo := left(btrim(new.termo), 80);
  new.chave := array_to_string(public.assistant_tokens(new.termo), ' ');
  if new.chave = '' then
    new.chave := public.bora_normalize(new.termo);
  end if;
  return new;
end;
$$;
drop trigger if exists trg_pesquisa_sem_resultado_normalizar on public.pesquisa_sem_resultado;
create trigger trg_pesquisa_sem_resultado_normalizar
  before insert on public.pesquisa_sem_resultado
  for each row execute function public.pesquisa_sem_resultado_normalizar();

alter table public.pesquisa_sem_resultado enable row level security;
do $$ begin
  -- cliente com sessão grava a SUA (user_id = ele)
  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'pesquisa_sem_resultado' and policyname = 'sem_resultado_cliente_insere') then
    create policy sem_resultado_cliente_insere on public.pesquisa_sem_resultado
      for insert to authenticated with check (user_id = auth.uid());
  end if;
  -- sem sessão (antes do login) grava sem user_id
  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'pesquisa_sem_resultado' and policyname = 'sem_resultado_anonimo_insere') then
    create policy sem_resultado_anonimo_insere on public.pesquisa_sem_resultado
      for insert to anon with check (user_id is null);
  end if;
  -- só o admin lê
  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'pesquisa_sem_resultado' and policyname = 'sem_resultado_admin_le') then
    create policy sem_resultado_admin_le on public.pesquisa_sem_resultado
      for select to authenticated using (coalesce(public.is_admin(), false));
  end if;
end $$;
revoke all on public.pesquisa_sem_resultado from anon, authenticated;
grant insert on public.pesquisa_sem_resultado to anon, authenticated;
grant select on public.pesquisa_sem_resultado to authenticated;
grant usage, select on sequence public.pesquisa_sem_resultado_id_seq to anon, authenticated;
grant all on public.pesquisa_sem_resultado to service_role;

-- ─── 3. Escolhas depois de uma pesquisa sem resultado (a aprendizagem) ──────
create table if not exists public.pesquisa_escolhas (
  id            bigserial primary key,
  termo         text not null check (length(btrim(termo)) between 2 and 80),
  chave         text not null default '',
  restaurant_id text not null references public.restaurants(id) on delete cascade,
  product_id    text not null references public.products(id) on delete cascade,
  user_id       uuid default auth.uid(),
  criado_em     timestamptz not null default now()
);
comment on table public.pesquisa_escolhas is
  'Depois de uma pesquisa sem resultado, o produto que o cliente pôs no carrinho na mesma loja (m11). 3 pessoas diferentes com o mesmo termo e produto → sinónimo aprendido.';
create index if not exists idx_pesquisa_escolhas_chave on public.pesquisa_escolhas (chave, restaurant_id, product_id);

drop trigger if exists trg_pesquisa_escolhas_normalizar on public.pesquisa_escolhas;
create trigger trg_pesquisa_escolhas_normalizar
  before insert on public.pesquisa_escolhas
  for each row execute function public.pesquisa_sem_resultado_normalizar();

-- 3 pessoas diferentes (sem sessão conta como UMA) → entra na tabela de sinónimos
create or replace function public.pesquisa_escolhas_aprender()
returns trigger
language plpgsql
security definer
set search_path = public, extensions, pg_temp
as $$
declare
  v_pessoas integer;
begin
  select count(distinct coalesce(e.user_id::text, 'sem-sessao'))
    into v_pessoas
    from public.pesquisa_escolhas e
   where e.chave = new.chave
     and e.restaurant_id = new.restaurant_id
     and e.product_id = new.product_id;

  if v_pessoas >= 3 then
    update public.pesquisa_sinonimos s
       set vezes = v_pessoas
     where s.chave = new.chave and s.product_id = new.product_id
       and s.restaurant_id = new.restaurant_id;
    if not found then
      insert into public.pesquisa_sinonimos (termo, product_id, restaurant_id, origem, vezes)
      values (new.termo, new.product_id, new.restaurant_id, 'aprendido', v_pessoas)
      on conflict do nothing;
    end if;
  end if;
  return new;
end;
$$;
revoke all on function public.pesquisa_escolhas_aprender() from public, anon, authenticated;

drop trigger if exists trg_pesquisa_escolhas_aprender on public.pesquisa_escolhas;
create trigger trg_pesquisa_escolhas_aprender
  after insert on public.pesquisa_escolhas
  for each row execute function public.pesquisa_escolhas_aprender();

alter table public.pesquisa_escolhas enable row level security;
do $$ begin
  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'pesquisa_escolhas' and policyname = 'escolhas_cliente_insere') then
    create policy escolhas_cliente_insere on public.pesquisa_escolhas
      for insert to authenticated with check (user_id = auth.uid());
  end if;
  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'pesquisa_escolhas' and policyname = 'escolhas_anonimo_insere') then
    create policy escolhas_anonimo_insere on public.pesquisa_escolhas
      for insert to anon with check (user_id is null);
  end if;
  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'pesquisa_escolhas' and policyname = 'escolhas_admin_le') then
    create policy escolhas_admin_le on public.pesquisa_escolhas
      for select to authenticated using (coalesce(public.is_admin(), false));
  end if;
end $$;
revoke all on public.pesquisa_escolhas from anon, authenticated;
grant insert on public.pesquisa_escolhas to anon, authenticated;
grant select on public.pesquisa_escolhas to authenticated;
grant usage, select on sequence public.pesquisa_escolhas_id_seq to anon, authenticated;
grant all on public.pesquisa_escolhas to service_role;

-- ─── 4. O motor: pesquisa_produtos ───────────────────────────────────────────
-- p_embedding (opcional): vetor da pergunta vindo de uma Edge Function — 384
-- números (gte-small) ou 768 (Gemini). Sem ele, o "significado" usa a média
-- dos vetores dos produtos do catálogo que têm a palavra (não chama API).
-- O limiar do pg_trgm desce a 0.45 só dentro da função (erros de escrita).
create or replace function public.pesquisa_produtos(
  p_q text,
  p_restaurant_id text default null,
  p_limit integer default 50,
  p_embedding extensions.vector default null
)
returns table(id text, name text, category text, category_root text, price numeric,
              photo_url text, restaurant_id text, match_kind text, score real)
language sql
stable
set search_path = public, extensions, pg_temp
set pg_trgm.word_similarity_threshold = '0.45'
as $fn$
-- CORPO-INICIO
with
q as (
  select btrim(regexp_replace(public.bora_normalize(p_q), '\s+', ' ', 'g')) as qn,
         greatest(1, least(coalesce(p_limit, 50), 200)) as lim
),
pal as (
  select row_number() over (order by x.o) as i, x.w, public.assistant_singular(x.w) as t
    from q cross join lateral regexp_split_to_table(q.qn, ' ') with ordinality as x(w, o)
   where length(q.qn) >= 2
     and x.w <> ''
     and x.w not in ('de','da','do','das','dos','em','e','a','o','os','as','para','p','ao','aos',
                     'na','no','nas','nos','c','um','uma','ou','pra',
                     'kg','g','gr','grs','ml','cl','lt','un','und','unid','unidade','unidades',
                     'emb','embalagem','pack','litro','litros','quilo','quilos','kilo')
),
nq as (
  select count(*)::int as n, coalesce(string_agg(t, ' ' order by i), '') as qs from pal
),
sin as (
  select s.alvo_chave, s.product_id, pl.i, false as frase
    from pal pl
    join public.pesquisa_sinonimos s
      on s.ativo
     and (s.restaurant_id is null or p_restaurant_id is null or s.restaurant_id = p_restaurant_id)
     and strpos(s.chave, ' ') = 0
     and (s.chave = pl.t or s.chave = pl.w
          or (length(pl.t) >= 5 and length(s.chave) >= 5 and extensions.similarity(s.chave, pl.t) >= 0.6))
  union all
  select s.alvo_chave, s.product_id, null::bigint, true
    from nq
    join public.pesquisa_sinonimos s
      on s.ativo
     and (s.restaurant_id is null or p_restaurant_id is null or s.restaurant_id = p_restaurant_id)
     and strpos(s.chave, ' ') > 0
     and s.chave = nq.qs
),
alt as (
  select pal.i, pal.t as a, 0 as tipo from pal
  union select pal.i, pal.w, 0 from pal
  union select pal.i, replace(pal.t, 'ct', 't'), 0 from pal where strpos(pal.t, 'ct') > 0
  union select sin.i, sin.alvo_chave, 1 from sin where not sin.frase and sin.alvo_chave is not null
),
falt as (
  select distinct sin.alvo_chave as a from sin where sin.frase and sin.alvo_chave is not null
),
fixo as (
  select distinct sin.i, sin.product_id from sin where sin.product_id is not null
),
rx as (
  select string_agg(distinct z.v, '|') as v from (
    select alt.a as v from alt where length(alt.a) >= 2
    union select falt.a from falt where length(falt.a) >= 2
    union select regexp_replace(pal.t, 'ao$', 'aes') from pal where pal.t ~ 'ao$'
    union select regexp_replace(pal.t, 'ao$', 'oes') from pal where pal.t ~ 'ao$'
    union select regexp_replace(pal.t, 'al$', 'ais') from pal where pal.t ~ 'al$'
    union select regexp_replace(pal.t, 'el$', 'eis') from pal where pal.t ~ 'el$'
    union select regexp_replace(pal.t, 'm$', 'ns') from pal where pal.t ~ 'm$'
  ) z
),
-- candidatos pelo índice de trigramas (GIN em search_normalized), depois a loja
cand_ids as materialized (
  select p0.id from public.products p0
   where p0.search_normalized ~ (select rx.v from rx)
  union
  select fixo.product_id from fixo
),
cand as (
  select p.id, p.name, p.category, p.category_root, p.price, p.photo_url, p.restaurant_id,
         coalesce(p.is_popular, false) as popular
    from public.products p
   where p.id in (select cand_ids.id from cand_ids)
     and p.is_available
     and (p_restaurant_id is null or p.restaurant_id = p_restaurant_id)
     and (p_restaurant_id is not null or exists (
           select 1 from public.restaurants r
            where r.id = p.restaurant_id and r.approval_status = 'approved'
              and coalesce(r.is_active_admin, true)))
),
-- ns = o nome como a pesquisa o compara. É, palavra a palavra, igual a
-- ' ' || array_to_string(assistant_tokens(nome), ' ') || ' ' (provado nos 59 475
-- produtos de produção a 09/11/2026: 0 diferenças), mas ~10x mais rápido: só
-- funções C, sem chamar uma função SQL por produto.
catn as (
  select k.category, (' ' || btrim(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(' ' || regexp_replace(regexp_replace(lower(extensions.unaccent('extensions.unaccent'::regdictionary, coalesce(k.category, ''))), '[^a-z0-9]+', ' ', 'g'), ' ', '  ', 'g') || ' ', ' (de|da|do|das|dos|em|e|a|o|os|as|para|p|ao|aos|na|no|nas|nos|c|um|uma|ou|pra) ', ' ', 'g'), ' ([a-z][a-z0-9]*)oes ', ' \1ao ', 'g'), ' ([a-z][a-z0-9]*)aes ', ' \1ao ', 'g'), ' ([a-z][a-z0-9]*)ais ', ' \1al ', 'g'), ' ([a-z][a-z0-9]*)eis ', ' \1el ', 'g'), ' ([a-z][a-z0-9]*)ois ', ' \1ol ', 'g'), ' ([a-z][a-z0-9]+)ns ', ' \1m ', 'g'), ' ([a-z][a-z0-9]+[rz])es ', ' \1 ', 'g'), ' ([a-z][a-z0-9]+[^s ])s ', ' \1 ', 'g'), ' +', ' ', 'g')) || ' ') as cs
    from (select distinct cand.category from cand) k
),
cn as (
  select c.*,
         (' ' || btrim(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(' ' || regexp_replace(regexp_replace(lower(extensions.unaccent('extensions.unaccent'::regdictionary, coalesce(c.name, ''))), '[^a-z0-9]+', ' ', 'g'), ' ', '  ', 'g') || ' ', ' (de|da|do|das|dos|em|e|a|o|os|as|para|p|ao|aos|na|no|nas|nos|c|um|uma|ou|pra) ', ' ', 'g'), ' ([a-z][a-z0-9]*)oes ', ' \1ao ', 'g'), ' ([a-z][a-z0-9]*)aes ', ' \1ao ', 'g'), ' ([a-z][a-z0-9]*)ais ', ' \1al ', 'g'), ' ([a-z][a-z0-9]*)eis ', ' \1el ', 'g'), ' ([a-z][a-z0-9]*)ois ', ' \1ol ', 'g'), ' ([a-z][a-z0-9]+)ns ', ' \1m ', 'g'), ' ([a-z][a-z0-9]+[rz])es ', ' \1 ', 'g'), ' ([a-z][a-z0-9]+[^s ])s ', ' \1 ', 'g'), ' +', ' ', 'g')) || ' ') as ns,
         coalesce(kn.cs, '  ') as cs,
         (' ' || regexp_replace(lower(extensions.unaccent('extensions.unaccent'::regdictionary, coalesce(c.name, ''))), '[^a-z0-9]+', ' ', 'g') || ' ') as nr
    from cand c
    left join catn kn on kn.category is not distinct from c.category
),
forca as (
  select c.id, pl.i,
         coalesce(max(case when a.tipo = 0 then
           case when c.ns like '% ' || a.a || ' %' then 1.0
                when length(a.a) >= 3 and c.ns like '% ' || a.a || '%' then 0.75
                when length(a.a) >= 4 and strpos(c.ns, a.a) > 0 then 0.6
                else 0 end end), 0) as fo,
         greatest(
           coalesce(max(case when a.tipo = 1 then
             case when c.ns like '% ' || a.a || ' %' then 0.85
                  when length(a.a) >= 3 and c.ns like '% ' || a.a || '%' then 0.7
                  when length(a.a) >= 4 and strpos(c.ns, a.a) > 0 then 0.55
                  else 0 end end), 0),
           case when exists (select 1 from fixo f where f.i = pl.i and f.product_id = c.id) then 0.9 else 0 end
         ) as fs,
         coalesce(max(case when length(a.a) >= 3 and c.cs like '% ' || a.a || '%' then 0.4 else 0 end), 0) as fc,
         coalesce(bool_or(pl.i = 1 and length(a.a) >= 3 and c.ns like ' ' || a.a || '%'), false) as abre
    from cn c
    cross join pal pl
    join alt a on a.i = pl.i
   group by c.id, pl.i
),
agg as (
  select f.id,
         count(*) filter (where f.fo > 0) as ok_o,
         count(*) filter (where greatest(f.fo, f.fs) > 0) as ok_n,
         count(*) filter (where greatest(f.fo, f.fs, f.fc) > 0) as ok_c,
         coalesce(bool_or(f.i = 1 and f.fo > 0), false) as ok1,
         avg(greatest(f.fo, f.fs, f.fc)) as media,
         coalesce(bool_or(f.abre), false) as abre
    from forca f
   group by f.id
),
fr as (
  select distinct c.id from cn c join falt on c.ns like '% ' || falt.a || '%'
),
princ as (
  select c.id, c.name, c.category, c.category_root, c.price, c.photo_url, c.restaurant_id,
         k.kind,
         (case k.kind when 'exato' then 6.0 when 'comeca' then 5.0 when 'texto' then 4.0
                      when 'sinonimo' then 3.5 when 'categoria' then 3.0 else 1.0 end
          + 0.5 * coalesce(g.media, 0.5)
          + case when c.ns like ' ' || nq.qs || '%' then 0.3
                 when coalesce(g.abre, false) then 0.15 else 0 end
          -- a frase inteira, tal como foi escrita ("vitamina c"), aparece no nome
          + case when c.nr like '% ' || q.qn || ' %' then 0.15 else 0 end
          + case when c.popular then 0.05 else 0 end
          - least(length(c.name), 120) / 1000.0) as score,
         k.kind <> 'parcial' as cheio
    from cn c
    cross join nq
    cross join q
    left join agg g on g.id = c.id
    cross join lateral (
      select case
        when nq.n = 0 then null
        when c.ns = ' ' || nq.qs || ' ' then 'exato'
        when g.ok_o = nq.n and c.ns like ' ' || nq.qs || '%' then 'comeca'
        when g.ok_o = nq.n and c.ns like ' ' || (select pal.t from pal where pal.i = 1) || '%' then 'comeca'
        when g.ok_o = nq.n then 'texto'
        when nq.n >= 3 and g.ok_o >= nq.n - 1 and g.ok1 then 'texto'
        when g.ok_n = nq.n or c.id in (select fr.id from fr) then 'sinonimo'
        when g.ok_c = nq.n then 'categoria'
        when coalesce(g.ok_c, 0) >= 1 then 'parcial'
        else null end as kind
    ) k
   where k.kind is not null
),
-- erros de escrita: só se o texto deu menos de 5 produtos certos, e começando
-- pelas palavras que menos acharam (ex.: "papel higenico" → "higenico" primeiro)
gate1 as (
  select count(*) < 5 and (select nq.n from nq) > 0 as abrir
    from (select 1 from princ where princ.cheio limit 5) z
),
falha as (
  select pal.i, pal.t, row_number() over (order by coalesce(m.n, 0), pal.i) as k
    from pal
    left join (select f.i, count(*) filter (where greatest(f.fo, f.fs) > 0) as n
                 from forca f group by f.i) m
      on m.i = pal.i
   where (select gate1.abrir from gate1)
     and length(pal.t) >= 4
     and coalesce(m.n, 0) < 3
),
fz_ids as materialized (
  select p0.id from public.products p0
   where (select falha.t from falha where falha.k = 1) operator(extensions.<%) p0.search_normalized
  union
  select p0.id from public.products p0
   where (select falha.t from falha where falha.k = 2) operator(extensions.<%) p0.search_normalized
  union
  select p0.id from public.products p0
   where p0.search_normalized ~ (select regexp_replace(regexp_replace(falha.t, '(.)\1+', '\1', 'g'), '(.)', '\1+', 'g')
                                   from falha where falha.k = 1)
),
fzc as (
  select p.id, p.name, p.category, p.category_root, p.price, p.photo_url, p.restaurant_id,
         coalesce(p.is_popular, false) as popular,
         (' ' || btrim(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(' ' || regexp_replace(regexp_replace(lower(extensions.unaccent('extensions.unaccent'::regdictionary, coalesce(p.name, ''))), '[^a-z0-9]+', ' ', 'g'), ' ', '  ', 'g') || ' ', ' (de|da|do|das|dos|em|e|a|o|os|as|para|p|ao|aos|na|no|nas|nos|c|um|uma|ou|pra) ', ' ', 'g'), ' ([a-z][a-z0-9]*)oes ', ' \1ao ', 'g'), ' ([a-z][a-z0-9]*)aes ', ' \1ao ', 'g'), ' ([a-z][a-z0-9]*)ais ', ' \1al ', 'g'), ' ([a-z][a-z0-9]*)eis ', ' \1el ', 'g'), ' ([a-z][a-z0-9]*)ois ', ' \1ol ', 'g'), ' ([a-z][a-z0-9]+)ns ', ' \1m ', 'g'), ' ([a-z][a-z0-9]+[rz])es ', ' \1 ', 'g'), ' ([a-z][a-z0-9]+[^s ])s ', ' \1 ', 'g'), ' +', ' ', 'g')) || ' ') as ns
    from public.products p
   where p.id in (select fz_ids.id from fz_ids)
     and p.is_available
     and (p_restaurant_id is null or p.restaurant_id = p_restaurant_id)
     and (p_restaurant_id is not null or exists (
           select 1 from public.restaurants r
            where r.id = p.restaurant_id and r.approval_status = 'approved'
              and coalesce(r.is_active_admin, true)))
),
fzf as (
  select c.id, pl.i,
         greatest(
           case when c.ns like '% ' || pl.t || '%' then 0.75
                when length(pl.t) >= 4 and strpos(c.ns, pl.t) > 0 then 0.6 else 0 end,
           case when length(pl.t) >= 4
                 and strpos(regexp_replace(replace(replace(replace(replace(c.ns, 'ch', 'x'), 'sh', 'x'), 'ph', 'f'), 'y', 'i'), '(.)\1+', '\1', 'g'),
                            regexp_replace(replace(replace(replace(replace(pl.t, 'ch', 'x'), 'sh', 'x'), 'ph', 'f'), 'y', 'i'), '(.)\1+', '\1', 'g')) > 0
                then 0.7 else 0 end,
           case when length(pl.t) >= 4 and extensions.word_similarity(pl.t, c.ns) >= 0.45
                then 0.3 + 0.5 * extensions.word_similarity(pl.t, c.ns) else 0 end,
           coalesce((select max(case when c.ns like '% ' || a.a || '%' then 0.7 else 0 end)
                       from alt a where a.i = pl.i and a.tipo = 1), 0)
         ) as f
    from fzc c cross join pal pl
),
fzr as (
  select c.id, c.name, c.category, c.category_root, c.price, c.photo_url, c.restaurant_id,
         'parecido'::text as kind,
         (2.5 + 0.5 * case when length(replace(nq.qs, ' ', '')) >= 5
                            and strpos(replace(c.ns, ' ', ''), replace(nq.qs, ' ', '')) > 0 then 0.95
                           else g.media end
          + case when c.popular then 0.05 else 0 end
          - least(length(c.name), 120) / 1000.0) as score,
         true as cheio
    from fzc c
    cross join nq
    join (select fzf.id, count(*) filter (where fzf.f > 0) as ok, avg(fzf.f) as media
            from fzf group by fzf.id) g on g.id = c.id
   where g.ok = nq.n
      or (length(replace(nq.qs, ' ', '')) >= 5
          and strpos(replace(c.ns, ' ', ''), replace(nq.qs, ' ', '')) > 0)
),
-- significado (vetores): só quando ainda há menos de 3 produtos certos
gate2 as (
  select count(*) < 3 and (select nq.n from nq) > 0 as abrir from (
    select 1 from princ where princ.cheio
    union all select 1 from fzr
    limit 3) z
),
vq as (
  select coalesce(
           p_embedding,
           (select extensions.avg(e.embedding) from (
              select g.embedding
                from public.products p2
                join public.product_embeddings_gte g on g.product_id = p2.id
               where p2.is_available
                 and p2.search_normalized ~ ('(^| )(' || (select rx.v from rx) || ')')
               limit 30) e)
         ) as v
   where (select gate2.abrir from gate2)
),
-- loja pequena (até 3000 produtos): distância a todos os produtos dela;
-- loja grande ou lupa: os 300 mais perto pelo índice HNSW, depois filtra.
pequena as (
  select p_restaurant_id is not null
         and (select count(*) from public.products p3
               where p3.restaurant_id = p_restaurant_id and p3.is_available) <= 3000 as sim
),
sem_ids as (
  (select g.product_id, 1 - (g.embedding operator(extensions.<=>) (select vq.v from vq)) as sim
     from public.product_embeddings_gte g
    where (select extensions.vector_dims(vq.v) = 384 from vq) and not (select pequena.sim from pequena)
    order by g.embedding operator(extensions.<=>) (select vq.v from vq)
    limit 300)
  union all
  (select g.product_id, 1 - (g.embedding operator(extensions.<=>) (select vq.v from vq)) as sim
     from public.products p4
     join public.product_embeddings_gte g on g.product_id = p4.id
    where (select extensions.vector_dims(vq.v) = 384 from vq) and (select pequena.sim from pequena)
      and p4.restaurant_id = p_restaurant_id and p4.is_available)
  union all
  (select g.product_id, 1 - (g.embedding operator(extensions.<=>) (select vq.v from vq)) as sim
     from public.product_embeddings g
    where (select extensions.vector_dims(vq.v) = 768 from vq)
    order by g.embedding operator(extensions.<=>) (select vq.v from vq)
    limit 300)
),
sem as (
  select p.id, p.name, p.category, p.category_root, p.price, p.photo_url, p.restaurant_id, si.sim
    from sem_ids si
    join public.products p on p.id = si.product_id
   where p.is_available
     and (p_restaurant_id is null or p.restaurant_id = p_restaurant_id)
),
semr as (
  select s.id, s.name, s.category, s.category_root, s.price, s.photo_url, s.restaurant_id,
         'significado'::text as kind, (1.5 + s.sim)::float8 as score, false as cheio
    from sem s
   where s.sim >= 0.93
     and s.sim >= (select max(s2.sim) from sem s2) - 0.015
     and (p_restaurant_id is not null or exists (
           select 1 from public.restaurants r
            where r.id = s.restaurant_id and r.approval_status = 'approved'
              and coalesce(r.is_active_admin, true)))
   order by s.sim desc
   limit 8
),
todos as (
  select princ.id, princ.name, princ.category, princ.category_root, princ.price, princ.photo_url,
         princ.restaurant_id, princ.kind, princ.score::float8 as score from princ
  union all
  select fzr.id, fzr.name, fzr.category, fzr.category_root, fzr.price, fzr.photo_url,
         fzr.restaurant_id, fzr.kind, fzr.score::float8 from fzr
  union all
  select semr.id, semr.name, semr.category, semr.category_root, semr.price, semr.photo_url,
         semr.restaurant_id, semr.kind, semr.score from semr
),
melhor as (
  select distinct on (todos.id) todos.* from todos order by todos.id, todos.score desc
)
select m.id, m.name, m.category, m.category_root, m.price, m.photo_url, m.restaurant_id,
       m.kind, m.score::real
  from melhor m
 order by m.score desc, m.name
 limit (select q.lim from q)
-- CORPO-FIM
$fn$;

comment on function public.pesquisa_produtos(text, text, integer, extensions.vector) is
  'Motor único da pesquisa de produtos (m11, 09/11/2026): exato > começa por > texto > sinónimo > categoria > erro de escrita > significado > parcial. Chamado por search_products (anon) e cliente_pesquisar.';

-- anon: search_products (chamada por anon, SECURITY INVOKER) chama esta função.
revoke all on function public.pesquisa_produtos(text, text, integer, extensions.vector) from public;
grant execute on function public.pesquisa_produtos(text, text, integer, extensions.vector) to anon, authenticated, service_role;

-- ─── 5. search_products: a mesma assinatura e as mesmas colunas, motor novo ─
create or replace function public.search_products(
  query_text text,
  p_restaurant_id text default null,
  max_results integer default 50
)
returns table(result_type text, id text, name text, category text, category_root text,
              price numeric, photo_url text, match_rank real)
language sql
stable
set search_path = public, extensions, pg_temp
as $$
  with q as (
    select btrim(regexp_replace(public.bora_normalize(query_text), '\s+', ' ', 'g')) as qn
  ),
  sec as (
    select z.cr, (10 + extensions.similarity(public.bora_normalize(z.cr), q.qn))::real as rank
      from q,
           (select distinct p.category_root as cr
              from public.products p
             where p.category_root is not null
               and p.is_available
               and (p_restaurant_id is null or p.restaurant_id = p_restaurant_id)) z
     where length(q.qn) >= 2
       and (' ' || public.bora_normalize(z.cr)) like '% ' || q.qn || '%'
     order by 2 desc
     limit 3
  )
  select 'section'::text, null::text, sec.cr, null::text, sec.cr, null::numeric, null::text, sec.rank
    from sec
  union all
  select 'product'::text, r.id, r.name, r.category, r.category_root, r.price, r.photo_url, r.score
    from public.pesquisa_produtos(query_text, p_restaurant_id,
                                  greatest(1, least(coalesce(max_results, 50), 200))) r
  order by 8 desc
$$;
-- (CREATE OR REPLACE mantém os GRANTs que já existem: anon, authenticated, service_role)
grant execute on function public.search_products(text, text, integer) to anon, authenticated, service_role;

-- ─── 6. cliente_pesquisar (lupa da home): lojas como antes, produtos pelo motor
create or replace function public.cliente_pesquisar(p_q text, p_limit integer default 30)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, extensions
as $function$
declare qn text; lojas jsonb; prods jsonb;
begin
  qn := trim(unaccent(lower(coalesce(p_q,''))));
  qn := btrim(regexp_replace(regexp_replace(qn, '[^a-z0-9 ]+', ' ', 'g'), '\s+', ' ', 'g'));
  if length(qn) < 2 then return jsonb_build_object('lojas','[]'::jsonb,'produtos','[]'::jsonb); end if;

  select coalesce(jsonb_agg(x), '[]'::jsonb) into lojas from (
    select r.id, r.name, r.category, r.cuisine_type, r.photo_url, r.cover_url, r.is_partner,
           coalesce(r.coming_soon,false) as coming_soon, coalesce(r.is_online,true) as is_online
    from restaurants r
    where r.approval_status='approved' and coalesce(r.is_active_admin,true)
      and (unaccent(lower(r.name || ' ' || coalesce(r.cuisine_type,'') || ' ' || coalesce(r.category,''))) ilike '%'||qn||'%'
           or word_similarity(qn, unaccent(lower(r.name || ' ' || coalesce(r.cuisine_type,'')))) > 0.5)
    order by (unaccent(lower(r.name)) ilike qn||'%') desc, r.name
    limit greatest(1, least(p_limit,50))
  ) x;

  -- produtos: o motor único (m11, 09/11/2026) — o mesmo das lojas
  select coalesce(jsonb_agg(y order by y.ordem), '[]'::jsonb) into prods from (
    select pp.id, pp.name, pp.price, pp.photo_url, pp.restaurant_id, r.name as restaurant_name,
           r.category as restaurant_category, coalesce(r.coming_soon,false) as coming_soon,
           pp.match_kind, pp.ordem
      from public.pesquisa_produtos(p_q, null, greatest(1, least(coalesce(p_limit, 30) * 2, 100)))
             with ordinality as pp(id, name, category, category_root, price, photo_url,
                                   restaurant_id, match_kind, score, ordem)
      join restaurants r on r.id = pp.restaurant_id
  ) y;

  return jsonb_build_object('lojas', lojas, 'produtos', prods);
end $function$;
grant execute on function public.cliente_pesquisar(text, integer) to anon, authenticated, service_role;

-- ─── 7. App: gravar uma pesquisa sem resultado / uma escolha ─────────────────
-- SECURITY DEFINER para pôr o user_id certo e não gravar a mesma coisa 20
-- vezes (o cliente escreve letra a letra). anon: pesquisas antes do login.
create or replace function public.pesquisa_registar_sem_resultado(
  p_termo text,
  p_restaurant_id text default null,
  p_origem text default 'loja'
)
returns boolean
language plpgsql
security definer
set search_path = public, extensions, pg_temp
as $$
declare
  v_uid uuid := auth.uid();
  v_termo text := left(btrim(coalesce(p_termo, '')), 80);
  v_chave text;
  v_loja text;
begin
  if length(v_termo) < 3 then return false; end if;
  v_chave := array_to_string(public.assistant_tokens(v_termo), ' ');
  if v_chave = '' then return false; end if;
  select r.id into v_loja from public.restaurants r where r.id = p_restaurant_id;
  -- a mesma pessoa, a mesma loja, o mesmo termo em 10 min = uma só
  if exists (select 1 from public.pesquisa_sem_resultado s
              where s.chave = v_chave
                and s.restaurant_id is not distinct from v_loja
                and s.user_id is not distinct from v_uid
                and s.criado_em > now() - interval '10 minutes') then
    return false;
  end if;
  insert into public.pesquisa_sem_resultado (termo, restaurant_id, user_id, origem)
  values (v_termo, v_loja, v_uid,
          case when p_origem in ('loja', 'lupa', 'amigo') then p_origem else 'loja' end);
  return true;
end;
$$;
revoke all on function public.pesquisa_registar_sem_resultado(text, text, text) from public;
grant execute on function public.pesquisa_registar_sem_resultado(text, text, text) to anon, authenticated, service_role;

create or replace function public.pesquisa_aprender_escolha(
  p_termo text,
  p_restaurant_id text,
  p_product_id text
)
returns boolean
language plpgsql
security definer
set search_path = public, extensions, pg_temp
as $$
declare
  v_uid uuid := auth.uid();
  v_termo text := left(btrim(coalesce(p_termo, '')), 80);
  v_chave text;
begin
  if length(v_termo) < 3 or p_restaurant_id is null or p_product_id is null then return false; end if;
  -- o produto tem de ser daquela loja e estar à venda
  if not exists (select 1 from public.products p
                  where p.id = p_product_id and p.restaurant_id = p_restaurant_id and p.is_available) then
    return false;
  end if;
  v_chave := array_to_string(public.assistant_tokens(v_termo), ' ');
  if v_chave = '' then return false; end if;
  -- uma vez por pessoa (sem sessão: uma vez por hora) para o mesmo termo e produto
  if exists (select 1 from public.pesquisa_escolhas e
              where e.chave = v_chave and e.product_id = p_product_id
                and e.user_id is not distinct from v_uid
                and (v_uid is not null or e.criado_em > now() - interval '1 hour')) then
    return false;
  end if;
  insert into public.pesquisa_escolhas (termo, restaurant_id, product_id, user_id)
  values (v_termo, p_restaurant_id, p_product_id, v_uid);
  update public.pesquisa_sem_resultado s
     set resolvido_em = now(), produto_escolhido = p_product_id
   where s.chave = v_chave
     and s.restaurant_id = p_restaurant_id
     and s.user_id is not distinct from v_uid
     and s.resolvido_em is null
     and s.criado_em > now() - interval '1 day';
  return true;
end;
$$;
revoke all on function public.pesquisa_aprender_escolha(text, text, text) from public;
grant execute on function public.pesquisa_aprender_escolha(text, text, text) to anon, authenticated, service_role;

-- ─── 8. Painel admin (PT-BR) ─────────────────────────────────────────────────
create or replace function public.admin_pesquisas_sem_resultado(p_dias integer default 30)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, extensions, pg_temp
as $$
declare
  v_dias integer := greatest(1, least(coalesce(p_dias, 30), 365));
  v_desde timestamptz := now() - make_interval(days => greatest(1, least(coalesce(p_dias, 30), 365)));
  v jsonb;
begin
  if not coalesce(public.is_admin(), false) then
    raise exception 'admin_required';
  end if;
  with s as (
    select * from public.pesquisa_sem_resultado where criado_em >= v_desde
  ),
  t as (
    select s.restaurant_id, s.chave,
           mode() within group (order by s.termo) as termo,
           count(*) as vezes,
           count(distinct coalesce(s.user_id::text, 'sem-sessao')) as pessoas,
           count(*) filter (where s.resolvido_em is not null) as resolvidas,
           max(s.criado_em) as ultima
      from s
     group by s.restaurant_id, s.chave
  )
  select jsonb_build_object(
    'dias', v_dias,
    'total', (select count(*) from s),
    'termos_distintos', (select count(*) from t),
    'termos', coalesce((
      select jsonb_agg(jsonb_build_object(
               'restaurant_id', t.restaurant_id,
               'loja', coalesce(r.name, 'Lupa da home'),
               'chave', t.chave,
               'termo', t.termo,
               'vezes', t.vezes,
               'pessoas', t.pessoas,
               'resolvidas', t.resolvidas,
               'ultima', t.ultima,
               'tem_sinonimo', exists (select 1 from public.pesquisa_sinonimos ps
                                        where ps.chave = t.chave and ps.ativo
                                          and (ps.restaurant_id is null or ps.restaurant_id = t.restaurant_id)),
               'sugestoes', coalesce((
                  select jsonb_agg(jsonb_build_object('product_id', e.product_id, 'nome', p.name, 'vezes', e.n)
                                   order by e.n desc)
                    from (select e.product_id, count(*) as n
                            from public.pesquisa_escolhas e
                           where e.chave = t.chave and e.restaurant_id = t.restaurant_id
                           group by e.product_id order by count(*) desc limit 5) e
                    join public.products p on p.id = e.product_id), '[]'::jsonb))
             order by t.vezes desc, t.ultima desc)
        from (select * from t order by t.vezes desc, t.ultima desc limit 150) t
        left join public.restaurants r on r.id = t.restaurant_id), '[]'::jsonb),
    'aprendidos', coalesce((
      select jsonb_agg(jsonb_build_object('id', ps.id, 'termo', ps.termo, 'loja', r.name,
                                          'produto', p.name, 'vezes', ps.vezes, 'criado_em', ps.criado_em)
                       order by ps.criado_em desc)
        from (select * from public.pesquisa_sinonimos where origem = 'aprendido'
               order by criado_em desc limit 30) ps
        left join public.restaurants r on r.id = ps.restaurant_id
        left join public.products p on p.id = ps.product_id), '[]'::jsonb)
  ) into v;
  return v;
end;
$$;

create or replace function public.admin_pesquisa_sinonimos(p_busca text default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, extensions, pg_temp
as $$
declare
  v_b text := nullif(btrim(coalesce(p_busca, '')), '');
begin
  if not coalesce(public.is_admin(), false) then
    raise exception 'admin_required';
  end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object(
             'id', s.id, 'termo', s.termo, 'alvo', s.alvo, 'product_id', s.product_id,
             'produto', p.name, 'restaurant_id', s.restaurant_id, 'loja', r.name,
             'origem', s.origem, 'ativo', s.ativo, 'vezes', s.vezes, 'criado_em', s.criado_em)
           order by s.chave, s.alvo_chave)
      from (select * from public.pesquisa_sinonimos ps
             where v_b is null
                or ps.chave like '%' || array_to_string(public.assistant_tokens(v_b), ' ') || '%'
                or coalesce(ps.alvo_chave, '') like '%' || array_to_string(public.assistant_tokens(v_b), ' ') || '%'
             order by ps.chave limit 300) s
      left join public.products p on p.id = s.product_id
      left join public.restaurants r on r.id = s.restaurant_id), '[]'::jsonb);
end;
$$;

create or replace function public.admin_pesquisa_criar_sinonimo(
  p_termo text,
  p_alvo text default null,
  p_restaurant_id text default null,
  p_product_id text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions, pg_temp
as $$
declare
  v_id bigint;
  v_chave text;
begin
  if not coalesce(public.is_admin(), false) then
    raise exception 'admin_required';
  end if;
  if length(btrim(coalesce(p_termo, ''))) < 2 then
    return jsonb_build_object('ok', false, 'erro', 'Escreva o termo que o cliente procura.');
  end if;
  if nullif(btrim(coalesce(p_alvo, '')), '') is null and p_product_id is null then
    return jsonb_build_object('ok', false, 'erro', 'Escreva o que procurar no lugar (ou escolha um produto).');
  end if;
  if p_product_id is not null and not exists (
       select 1 from public.products p
        where p.id = p_product_id and (p_restaurant_id is null or p.restaurant_id = p_restaurant_id)) then
    return jsonb_build_object('ok', false, 'erro', 'Produto não encontrado nesta loja.');
  end if;
  insert into public.pesquisa_sinonimos (termo, alvo, product_id, restaurant_id, origem, criado_por)
  values (p_termo, nullif(btrim(coalesce(p_alvo, '')), ''), p_product_id,
          coalesce(p_restaurant_id, (select p.restaurant_id from public.products p where p.id = p_product_id)),
          'admin', auth.uid())
  on conflict do nothing
  returning id, chave into v_id, v_chave;
  if v_id is null then
    -- já existia: volta a ligar
    update public.pesquisa_sinonimos s
       set ativo = true
     where s.chave = array_to_string(public.assistant_tokens(p_termo), ' ')
       and coalesce(s.alvo_chave, '') = coalesce(array_to_string(public.assistant_tokens(nullif(btrim(coalesce(p_alvo, '')), '')), ' '), '')
       and coalesce(s.product_id, '') = coalesce(p_product_id, '')
     returning id, chave into v_id, v_chave;
  end if;
  update public.pesquisa_sem_resultado s
     set resolvido_em = coalesce(s.resolvido_em, now())
   where s.chave = v_chave
     and (p_restaurant_id is null or s.restaurant_id = p_restaurant_id);
  perform public.log_admin_action('pesquisa_criar_sinonimo', 'pesquisa_sinonimos', coalesce(v_id::text, ''),
          jsonb_build_object('termo', p_termo, 'alvo', p_alvo, 'restaurant_id', p_restaurant_id,
                             'product_id', p_product_id));
  return jsonb_build_object('ok', v_id is not null, 'id', v_id);
end;
$$;

create or replace function public.admin_pesquisa_sinonimo_ativo(p_id bigint, p_ativo boolean)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions, pg_temp
as $$
declare
  v_termo text;
begin
  if not coalesce(public.is_admin(), false) then
    raise exception 'admin_required';
  end if;
  update public.pesquisa_sinonimos set ativo = coalesce(p_ativo, false)
   where id = p_id
  returning termo into v_termo;
  if v_termo is null then
    return jsonb_build_object('ok', false, 'erro', 'Sinônimo não encontrado.');
  end if;
  perform public.log_admin_action(case when p_ativo then 'pesquisa_ligar_sinonimo' else 'pesquisa_desligar_sinonimo' end,
          'pesquisa_sinonimos', p_id::text, jsonb_build_object('termo', v_termo, 'ativo', p_ativo));
  return jsonb_build_object('ok', true);
end;
$$;

revoke all on function public.admin_pesquisas_sem_resultado(integer) from public, anon;
revoke all on function public.admin_pesquisa_sinonimos(text) from public, anon;
revoke all on function public.admin_pesquisa_criar_sinonimo(text, text, text, text) from public, anon;
revoke all on function public.admin_pesquisa_sinonimo_ativo(bigint, boolean) from public, anon;
grant execute on function public.admin_pesquisas_sem_resultado(integer) to authenticated, service_role;
grant execute on function public.admin_pesquisa_sinonimos(text) to authenticated, service_role;
grant execute on function public.admin_pesquisa_criar_sinonimo(text, text, text, text) to authenticated, service_role;
grant execute on function public.admin_pesquisa_sinonimo_ativo(bigint, boolean) to authenticated, service_role;

-- ─── 9. Vetores Gemini em falta (a reserva): lista para a Edge embeddings-gte ─
-- Os vetores gte-small (384) já cobrem todos os produtos à venda (cron de 2 em
-- 2 min). Esta lista serve a ação "gemini_atrasados" (produtos de qualquer
-- idade ainda sem vetor Gemini), em lotes pequenos por causa da quota grátis.
create or replace function public.pesquisa_produtos_sem_gemini(p_limit integer default 100)
returns table(id text, texto text)
language sql
stable
security definer
set search_path = public, extensions, pg_temp
as $$
  select p.id,
         left(p.name || coalesce(' · ' || nullif(p.category, ''), '') || coalesce(' · ' || nullif(p.description, ''), ''), 500)
    from public.products p
   where p.is_available
     and not exists (select 1 from public.product_embeddings e where e.product_id = p.id)
   order by p.restaurant_id, p.id
   limit greatest(1, least(coalesce(p_limit, 100), 300));
$$;
revoke all on function public.pesquisa_produtos_sem_gemini(integer) from public, anon, authenticated;
grant execute on function public.pesquisa_produtos_sem_gemini(integer) to service_role;

-- Índice: o motor filtra por loja e "à venda" (o índice parcial que já existe,
-- idx_products_restaurant_id, cobre isso) e procura por trigramas em
-- search_normalized (idx_products_search_trgm, já existe). Os dois índices
-- GIN iguais em search_normalized (idx_products_search_trgm e
-- products_search_trgm_idx) ficam como estão: apagar índices não é desta missão.

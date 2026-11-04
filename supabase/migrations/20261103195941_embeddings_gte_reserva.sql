-- embeddings-supabase-2026-11-03 — o motor grátis do Supabase (gte-small, 384) ao lado do Gemini (768).
-- Ordem do Danilo (03/11/2026 19:21): "pode trocar, só que tem que deixar sempre alguém na reserva".
-- Só acrescenta: tabela product_embeddings_gte, coluna support_knowledge_chunks.embedding_gte, cache
-- embedding_cache_gte, funções de preenchimento. As colunas de 768 ficam como estão.
-- assistant_search_products e match_knowledge mantêm a assinatura e passam a ver o tamanho do vetor:
-- 384 → gte, 768 → Gemini (igual a antes). Backup das definições antigas em bkp_embeddings_funcoes_20261103.

-- 0) Backup das definições que vão ser substituídas
create table if not exists public.bkp_embeddings_funcoes_20261103 (
  assinatura  text primary key,
  definicao   text not null,
  guardado_em timestamptz not null default now()
);
alter table public.bkp_embeddings_funcoes_20261103 enable row level security;

insert into public.bkp_embeddings_funcoes_20261103 (assinatura, definicao)
select p.oid::regprocedure::text, pg_get_functiondef(p.oid)
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
 where n.nspname = 'public'
   and p.proname in ('assistant_search_products', 'match_knowledge', 'admin_assistant_overview',
                     'assistant_set_embeddings', 'assistant_products_without_embedding')
on conflict (assinatura) do nothing;

-- 1) Vetores gte dos produtos (tabela ao lado: product_embeddings.embedding é NOT NULL)
create table if not exists public.product_embeddings_gte (
  product_id text primary key references public.products(id) on delete cascade,
  embedding  extensions.vector(384) not null,
  model      text not null default 'gte-small',
  updated_at timestamptz not null default now()
);
alter table public.product_embeddings_gte enable row level security;
create index if not exists idx_product_embeddings_gte_hnsw
  on public.product_embeddings_gte using hnsw (embedding vector_cosine_ops);

-- 2) Vetores gte do manual do suporte (coluna nova; embedding de 768 continua igual)
alter table public.support_knowledge_chunks add column if not exists embedding_gte extensions.vector(384);
alter table public.support_knowledge_chunks add column if not exists indexed_gte_at timestamptz;
create index if not exists support_knowledge_chunks_embedding_gte_idx
  on public.support_knowledge_chunks using hnsw (embedding_gte vector_cosine_ops) with (m = '16', ef_construction = '64');

-- 3) Cache das perguntas no gte (as caches antigas têm embedding NOT NULL de 768)
create table if not exists public.embedding_cache_gte (
  scope        text not null check (scope in ('assistant', 'support')),
  query_hash   text not null,
  query_text   text not null,
  embedding    extensions.vector(384) not null,
  created_at   timestamptz not null default now(),
  last_used_at timestamptz not null default now(),
  hit_count    integer not null default 0,
  primary key (scope, query_hash)
);
alter table public.embedding_cache_gte enable row level security;
create index if not exists idx_embedding_cache_gte_last_used on public.embedding_cache_gte (last_used_at);

-- 4) Preenchimento (só o servidor)
create or replace function public.assistant_products_without_embedding_gte(
  p_limit integer default 200, p_after text default '', p_before text default null)
returns table(id text, texto text)
language sql stable security definer
set search_path to 'public'
as $function$
  select p.id,
         left(coalesce(p.name,'') || case when coalesce(p.category,'') <> '' then ' · ' || p.category else '' end
              || case when coalesce(p.unit,'') <> '' then ' · ' || p.unit else '' end, 300)
    from public.products p
   where coalesce(p.is_available, true) and p.price > 0
     and p.id > coalesce(p_after, '') and (p_before is null or p.id < p_before)
     and not exists (select 1 from public.product_embeddings_gte g where g.product_id = p.id)
   order by p.id
   limit greatest(1, least(p_limit, 2000));
$function$;

create or replace function public.assistant_set_embeddings_gte(p_rows jsonb)
returns integer
language plpgsql security definer
set search_path to 'public', 'extensions'
as $function$
declare v_n int;
begin
  if coalesce(current_setting('request.jwt.claims', true)::jsonb->>'role', current_setting('request.jwt.claim.role', true)) is distinct from 'service_role'
     and current_user not in ('postgres', 'service_role') then
    raise exception 'SO_SERVICE_ROLE';
  end if;
  insert into public.product_embeddings_gte (product_id, embedding, model, updated_at)
  select r->>'id', (r->>'e')::extensions.vector(384), coalesce(r->>'m', 'gte-small'), now()
    from jsonb_array_elements(p_rows) r
   where exists (select 1 from public.products p where p.id = r->>'id')
  on conflict (product_id) do update set embedding = excluded.embedding, model = excluded.model, updated_at = now();
  get diagnostics v_n = row_count;
  return v_n;
end;
$function$;

-- trechos sem gte, ou que o Gemini reindexou depois do gte (texto mudou)
create or replace function public.knowledge_chunks_without_gte(p_limit integer default 50)
returns table(id uuid, texto text)
language sql stable security definer
set search_path to 'public'
as $function$
  select k.id, k.chunk_text
    from public.support_knowledge_chunks k
   where k.embedding_gte is null
      or (k.indexed_at is not null and k.indexed_gte_at is not null and k.indexed_at > k.indexed_gte_at)
   order by k.id
   limit greatest(1, least(p_limit, 500));
$function$;

create or replace function public.knowledge_set_embeddings_gte(p_rows jsonb)
returns integer
language plpgsql security definer
set search_path to 'public', 'extensions'
as $function$
declare v_n int;
begin
  if coalesce(current_setting('request.jwt.claims', true)::jsonb->>'role', current_setting('request.jwt.claim.role', true)) is distinct from 'service_role'
     and current_user not in ('postgres', 'service_role') then
    raise exception 'SO_SERVICE_ROLE';
  end if;
  update public.support_knowledge_chunks k
     set embedding_gte = (r->>'e')::extensions.vector(384), indexed_gte_at = now()
    from jsonb_array_elements(p_rows) r
   where k.id = (r->>'id')::uuid;
  get diagnostics v_n = row_count;
  return v_n;
end;
$function$;

-- produtos novos sem vetor Gemini (para o "manter" pôr os novos nos dois motores)
create or replace function public.assistant_products_without_embedding_recent(p_limit integer default 100, p_days integer default 14)
returns table(id text, texto text)
language sql stable security definer
set search_path to 'public'
as $function$
  select p.id,
         left(coalesce(p.name,'') || case when coalesce(p.category,'') <> '' then ' · ' || p.category else '' end
              || case when coalesce(p.unit,'') <> '' then ' · ' || p.unit else '' end, 300)
    from public.products p
   where coalesce(p.is_available, true) and p.price > 0
     and p.created_at >= now() - make_interval(days => greatest(1, least(coalesce(p_days, 14), 60)))
     and not exists (select 1 from public.product_embeddings e where e.product_id = p.id)
   order by p.created_at desc
   limit greatest(1, least(p_limit, 500));
$function$;

-- 5) Pesquisa de produtos: mesma assinatura; vetor de 384 usa o gte, de 768 o Gemini (como antes)
create or replace function public.assistant_search_products(p_query text, p_restaurant_id text default null::text, p_limit integer default 12, p_embedding vector default null::vector, p_per_store boolean default false)
 returns table(product_id text, name text, restaurant_id text, restaurant_name text, is_partner boolean, service_type text, price numeric, display_price numeric, unit text, category text, photo_url text, maior_18 boolean, score numeric, match_kind text, confidence text)
 language plpgsql
 stable security definer
 set search_path to 'public', 'extensions'
as $function$
#variable_conflict use_column
declare
  v_q      text := public.f_unaccent(coalesce(p_query, ''));
  v_ts     tsquery;
  v_ts_or  tsquery;   -- afinação 08/10: qualquer palavra (ordena quem tem todas primeiro)
  v_ts_1   tsquery;   -- a primeira palavra (o substantivo) é obrigatória
  v_markup numeric;
  v_qt     text[];    -- B2 20/10: palavras da pesquisa, normalizadas
  v_q1     text;      -- a 1.ª palavra a sério (o que se pediu)
  v_nq     int;
  -- 03/11: o tamanho do vetor diz o motor (384 = gte-small, 768 = Gemini)
  v_gte    boolean := p_embedding is not null and extensions.vector_dims(p_embedding) = 384;
  v_vbons  numeric := 0.80;  -- semântica muito perto (só vetores) — limiares do Gemini, como antes
  v_vboa   numeric := 0.85;
begin
  if v_gte then
    select coalesce((select (ps.value #>> '{}')::numeric from public.platform_settings ps where ps.key = 'assistant_gte_vec_bons_min'), 0.92),
           coalesce((select (ps.value #>> '{}')::numeric from public.platform_settings ps where ps.key = 'assistant_gte_vec_boa_min'), 0.94)
      into v_vbons, v_vboa;
    perform set_config('hnsw.ef_search', '100', true);
  end if;
  -- B2 20/10: hífen = espaço ("papo-seco" = "papo seco"; no websearch o "-"
  -- ainda podia ser lido como "sem").
  v_q := replace(v_q, '-', ' ');
  v_q := regexp_replace(v_q, '[^a-z0-9%/,\. ]', ' ', 'g');
  v_q := btrim(regexp_replace(v_q, '\s+', ' ', 'g'));
  if length(v_q) < 2 then return; end if;
  -- palavras da pesquisa sem unidades ("cenoura kg" = "cenoura": o nome
  -- pode dizer "2KG" colado ao número)
  v_qt := array(select x from unnest(public.assistant_tokens(v_q)) with ordinality as u(x, o)
                 where not (x = any (array['kg','g','gr','grs','ml','cl','lt','un','und','unid',
                                           'unidade','emb','embalagem','pack','litro','quilo','kilo']))
                 order by o);
  if cardinality(v_qt) = 0 then v_qt := public.assistant_tokens(v_q); end if;
  v_q1 := (select x from unnest(v_qt) with ordinality as u(x, o)
            where x !~ '[0-9]' and length(x) > 1 order by o limit 1);
  v_nq := (select count(distinct x) from unnest(v_qt) x where x !~ '[0-9]');
  v_ts := websearch_to_tsquery('portuguese', v_q);
  v_ts_or := websearch_to_tsquery('portuguese', regexp_replace(v_q, '\s+', ' or ', 'g'));
  v_ts_1 := websearch_to_tsquery('portuguese', split_part(v_q, ' ', 1));
  if v_ts_1 is null or numnode(v_ts_1) = 0 then v_ts_1 := v_ts_or; end if;
  select coalesce((ps.value::text)::numeric, 0.15) into v_markup
    from public.platform_settings ps where ps.key = 'non_partner_markup_pct';
  v_markup := coalesce(v_markup, 0.15);

  return query
  with lojas as (
    select l.* from public.assistant_lojas l
     where p_restaurant_id is null or l.id = p_restaurant_id
  ),
  base as not materialized (
    select p.id, p.name, p.restaurant_id, p.price, p.unit, p.category, p.photo_url,
           p.taxonomy_section, p.category_root, p.search_normalized,
           l.name as loja, l.is_partner, l.service_type
      from public.products p
      join lojas l on l.id = p.restaurant_id
     where coalesce(p.is_available, true) and p.price > 0
  ),
  fts as (
    select b.id, b.restaurant_id,
           row_number() over (partition by b.restaurant_id
             -- B2 20/10: primeiro os nomes que começam pelo que se pediu
             -- (também "Marca - Produto" e "12 Ovos"); expressão barata, sem
             -- função por linha, porque aqui passam todos os candidatos
             order by coalesce(public.f_unaccent(b.name) ~ ('^([^-]{1,30}?\s+-\s+)?([0-9]+\s+)?' || v_q1), false) desc,
                      (to_tsvector('portuguese', public.f_unaccent(coalesce(b.name,'') || ' ' || coalesce(b.category,''))) @@ v_ts) desc,
                      ts_rank_cd(to_tsvector('portuguese', public.f_unaccent(coalesce(b.name,'') || ' ' || coalesce(b.category,''))), v_ts_or) desc,
                      length(b.name) asc, b.price asc) as rn
      from base b
     where to_tsvector('portuguese', public.f_unaccent(coalesce(b.name,'') || ' ' || coalesce(b.category,''))) @@ v_ts_1
       and to_tsvector('portuguese', public.f_unaccent(coalesce(b.name,'') || ' ' || coalesce(b.category,''))) @@ v_ts_or
  ),
  trg as (
    select b.id, b.restaurant_id,
           row_number() over (partition by b.restaurant_id
             order by word_similarity(v_q, coalesce(b.search_normalized, public.f_unaccent(b.name))) desc,
                      length(b.name) asc, b.price asc) as rn,
           word_similarity(v_q, coalesce(b.search_normalized, public.f_unaccent(b.name))) as sim
      from base b
     where v_q <% b.search_normalized
  ),
  -- 03/11: os 100 vizinhos no motor do vetor que veio (só um dos dois ramos corre)
  vec_raw as (
    (select g.product_id as id, (g.embedding <=> p_embedding) as d
       from public.product_embeddings_gte g
      where v_gte
      order by g.embedding <=> p_embedding
      limit 100)
    union all
    (select e.product_id as id, (e.embedding <=> p_embedding) as d
       from public.product_embeddings e
      where p_embedding is not null and not v_gte
      order by e.embedding <=> p_embedding
      limit 100)
  ),
  vec as (
    select r.id, row_number() over (order by r.d) as rn, (1 - r.d)::numeric as sim
      from vec_raw r
  ),
  fused as (
    select x.id,
           sum(x.s)::numeric as score,
           string_agg(x.kind, '+' order by x.kind) as match_kind,
           max(x.sim) as best_sim,
           max(case when x.kind = 'vec' then x.sim end) as vec_sim
      from (
        select f.id, 1.0 / (60 + f.rn) as s, 'fts' as kind, null::numeric as sim from fts f where f.rn <= 8
        union all
        select t.id, 1.0 / (60 + t.rn) as s, 'trgm' as kind, t.sim::numeric from trg t where t.rn <= 8
        union all
        select v.id, 1.0 / (60 + v.rn) as s, 'vec' as kind, v.sim from vec v
      ) x
     group by x.id
  ),
  cand as (
    -- palavras e cabeça de cada candidato calculadas uma só vez
    select b.*, f.match_kind, f.best_sim, f.vec_sim, f.score as rrf_base,
           public.assistant_tokens(b.name) as nt,
           -- num restaurante a secção do menu também diz o que é ("Copo Mega"
           -- na secção "Açaí"); nos mercados a categoria é larga ("Mercearia")
           -- e não conta
           case when b.service_type = 'restaurant'
                then public.assistant_tokens(coalesce(b.category, '')) end as ct,
           public.assistant_cabeca(b.name) as cab
      from fused f join base b on b.id = f.id
  ),
  medido as (
    select c.*,
           c.rrf_base
             + case when public.f_unaccent(c.name) like v_q || '%' then 0.02 else 0 end
             + case when c.match_kind like '%fts%' and c.match_kind like '%trgm%' then 0.01 else 0 end as rrf,
           public.assistant_cobertura(v_qt, c.nt || coalesce(c.ct, '{}'::text[])) as cov,
           public.assistant_cobertura(array[v_q1], c.nt || coalesce(c.ct, '{}'::text[])) as cov1,
           (c.cab = v_q1
             or (length(v_q1) >= 5 and extensions.similarity(coalesce(c.cab, ''), v_q1) > 0.52)
             or v_q1 = any (coalesce(c.ct, '{}'::text[]))) as cabeca_ok
      from cand c
  ),
  bons as (
    select m.*,
           case when v_q1 is null then 0
                else round(0.6 * m.cov + 0.4 * (case when m.cabeca_ok then 1 else 0 end), 3)
           end as qualidade
      from medido m
     where v_q1 is null                                     -- só números ("7up"): como antes
        or (m.cabeca_ok and m.cov1 >= 1 and m.cov >= 0.5)   -- boa: começa pelo pedido
        or m.cov >= 1                                       -- tem tudo, mas é outra coisa
        or coalesce(m.vec_sim, 0) >= v_vbons                -- semântica muito perto (só vetores)
  ),
  scored as (
    select s.*,
           ((s.cabeca_ok and s.cov1 >= 1 and s.cov >= 0.5) or coalesce(s.vec_sim, 0) >= v_vboa) as boa,
           -- só em pesquisas de 1 palavra: "Leite de Coco", "Ovos de Codorniz",
           -- "Arroz de Pato" — a palavra pedida seguida de "de/com/em…" é
           -- outro produto
           (v_nq = 1 and coalesce(public.f_unaccent(s.name) ~ ('^([^-]{1,30}?\s+-\s+)?([0-9]+\s+)?'
                    || v_q1 || '\S*\s+(de|do|da|dos|das|com|em)\s'), false)) as composto
      from bons s
  ),
  -- Só em pesquisas de 1 palavra ("leite", "ovos", "arroz"): a secção do
  -- catálogo onde mais se vende o que se pediu, contada em TODOS os produtos
  -- das lojas cujo nome começa pela palavra ("leite" → Laticínios & Ovos 227,
  -- Bebé 73, Mercearia 63). Só vale se ganhar com folga (>= 1,3 × a 2.ª):
  -- "alho" empata Frutas & Legumes com Mercearia e fica sem desempate.
  -- "Bio & Saudável" e "Outros" não contam (são atributos/resto).
  seccoes as (
    select b.taxonomy_section as sec, count(*) as n
      from base b
     where v_nq = 1 and v_q1 is not null
       and b.search_normalized ~ ('^' || v_q1)
       and coalesce(b.taxonomy_section, 'Outros') not in ('Outros', 'Bio & Saudável')
     group by b.taxonomy_section
  ),
  seccao as (
    select s1.sec
      from seccoes s1
     where s1.n >= 1.3 * coalesce((select max(s2.n) from seccoes s2 where s2.sec <> s1.sec), 0)
     order by s1.n desc
     limit 1
  ),
  final as (
    select s.*,
           coalesce(s.taxonomy_section = (select sec from seccao)
                    or (s.taxonomy_section = 'Bio & Saudável' and exists (select 1 from seccao)),
                    false) as na_seccao,
           count(*) filter (where s.boa) over () as n_boas
      from scored s
  ),
  ordenado as (
    select f.*,
           f.qualidade + f.rrf as score_final,
           row_number() over (partition by f.restaurant_id
                              order by f.qualidade desc, f.na_seccao desc, f.composto asc,
                                       f.rrf desc, f.price asc) as rn_loja
      from final f
  )
  select s.id, s.name, s.restaurant_id, s.loja, s.is_partner, s.service_type,
         s.price,
         case when s.is_partner then s.price else round(s.price * (1 + v_markup), 2) end as display_price,
         s.unit, s.category, s.photo_url,
         public.produto_e_maior_18(s.name, s.category, s.taxonomy_section, s.category_root) as maior_18,
         round(s.score_final, 5) as score, s.match_kind,
         case when v_q1 is null then
                case when (s.match_kind like '%fts%' and to_tsvector('portuguese', public.f_unaccent(coalesce(s.name,'') || ' ' || coalesce(s.category,''))) @@ v_ts)
                          or coalesce(s.best_sim, 0) >= 0.7
                     then 'alta' else 'parecido' end
              when s.boa then 'alta'
              else 'parecido' end as confidence
    from ordenado s
   where ((not p_per_store) or s.rn_loja = 1)
     -- sem nenhuma correspondência boa não se devolve o "parecido" sozinho:
     -- a resposta vem vazia e o Assistente diz que não encontrou
     and (v_q1 is null or s.n_boas > 0)
   order by s.qualidade desc, s.na_seccao desc, s.composto asc, s.rrf desc, s.price asc
   limit greatest(1, least(coalesce(p_limit, 12), 200));
end;
$function$;

-- 6) Manual do suporte: mesma assinatura; 384 → embedding_gte, 768 → embedding (como antes)
create or replace function public.match_knowledge(query_embedding vector, match_count integer default 5, min_similarity double precision default 0.5)
 returns table(id uuid, source_file text, source_type text, section_title text, chunk_text text, similarity double precision)
 language sql
 security definer
 set search_path to 'public', 'extensions'
as $function$
  (select k.id, k.source_file, k.source_type, k.section_title, k.chunk_text,
          1 - (k.embedding_gte <=> query_embedding) as similarity
     from public.support_knowledge_chunks k
    where extensions.vector_dims(query_embedding) = 384
      and k.embedding_gte is not null
      and 1 - (k.embedding_gte <=> query_embedding) >= min_similarity
    order by k.embedding_gte <=> query_embedding
    limit match_count)
  union all
  (select k.id, k.source_file, k.source_type, k.section_title, k.chunk_text,
          1 - (k.embedding <=> query_embedding) as similarity
     from public.support_knowledge_chunks k
    where extensions.vector_dims(query_embedding) <> 384
      and k.embedding is not null
      and 1 - (k.embedding <=> query_embedding) >= min_similarity
    order by k.embedding <=> query_embedding
    limit match_count);
$function$;

-- 7) Painel: o estado dos dois motores no resumo do assistente (chaves novas, as antigas iguais)
create or replace function public.admin_assistant_overview(p_days integer default 30)
 returns jsonb
 language plpgsql
 stable security definer
 set search_path to 'public'
as $function$
declare
  v_since timestamptz := now() - make_interval(days => coalesce(p_days, 30));
  v_conv int; v_msgs int; v_users int; v_props int; v_opened int; v_ordered int;
  v_sav_shown bigint; v_sav_real bigint; v_cost numeric; v_gaps int; v_handoff int; v_tok_in bigint; v_tok_out bigint;
begin
  if not public.is_admin() then raise exception 'ADMIN_ONLY'; end if;
  select count(*), coalesce(sum(messages_count),0), count(distinct user_id), coalesce(sum(cost_usd),0),
         count(*) filter (where status = 'handoff'), coalesce(sum(tokens_in),0), coalesce(sum(tokens_out),0)
    into v_conv, v_msgs, v_users, v_cost, v_handoff, v_tok_in, v_tok_out
    from public.assistant_conversations where started_at >= v_since;
  select count(*), count(*) filter (where status in ('opened','ordered')), count(*) filter (where status = 'ordered'),
         coalesce(sum(savings_cents) filter (where rank = 1 and kind = 'single'),0),
         coalesce(sum(savings_cents) filter (where status = 'ordered'),0)
    into v_props, v_opened, v_ordered, v_sav_shown, v_sav_real
    from public.assistant_cart_proposals where created_at >= v_since;
  select count(*) into v_gaps from public.assistant_gaps where not resolved;
  return jsonb_build_object(
    'days', p_days, 'conversations', v_conv, 'messages', v_msgs, 'users', v_users,
    'proposals', v_props, 'proposals_opened', v_opened, 'proposals_ordered', v_ordered,
    'conversion_pct', case when v_props > 0 then round(v_ordered::numeric * 100 / v_props, 1) else 0 end,
    'savings_shown_cents', v_sav_shown, 'savings_realized_cents', v_sav_real,
    'cost_usd', v_cost, 'cost_per_conversation_usd', case when v_conv > 0 then round(v_cost / v_conv, 5) else 0 end,
    'tokens_in', v_tok_in, 'tokens_out', v_tok_out,
    'handoffs', v_handoff, 'gaps_open', v_gaps,
    'enabled', (select coalesce((value::text)::boolean, true) from public.platform_settings where key = 'assistant_enabled'),
    'embeddings_done', (select count(*) from public.product_embeddings),
    'products_total', (select count(*) from public.products where coalesce(is_available, true) and price > 0),
    -- 03/11: os dois motores de vetores
    'embeddings_gte_done', (select count(*) from public.product_embeddings_gte),
    'manual_trechos', (select count(*) from public.support_knowledge_chunks),
    'manual_gte_done', (select count(*) from public.support_knowledge_chunks where embedding_gte is not null),
    'manual_gemini_done', (select count(*) from public.support_knowledge_chunks where embedding is not null),
    'motor_primario_produtos', (select value #>> '{}' from public.platform_settings where key = 'embeddings_motor_primario_produtos'),
    'motor_primario_ajuda', (select value #>> '{}' from public.platform_settings where key = 'embeddings_motor_primario_ajuda'));
end;
$function$;

-- 8) Definições (nenhuma é financeira). O Gemini fica primeiro até a prova de qualidade decidir.
insert into public.platform_settings (key, value, description, category) values
  ('embeddings_motor_primario_produtos', '"gemini"'::jsonb, 'Motor que gera primeiro os vetores da pesquisa de produtos do assistente: gte (grátis, do Supabase) ou gemini. O outro fica sempre de reserva.', 'assistente'),
  ('embeddings_motor_primario_ajuda', '"gemini"'::jsonb, 'Motor que gera primeiro os vetores do manual de ajuda (assistente e chat de suporte): gte ou gemini. O outro fica de reserva.', 'assistente'),
  ('embeddings_gte_timeout_ms', '1500'::jsonb, 'Prazo (ms) do motor gte por pergunta antes de passar à reserva.', 'assistente'),
  ('embeddings_teste_falha', '{}'::jsonb, 'Só para provar a reserva: {"modo":"gte|gemini|todos","ate":"<data ISO>"} (no máximo 30 min). Vazio = normal.', 'assistente'),
  ('assistant_gte_vec_bons_min', '0.92'::jsonb, 'gte: semelhança mínima para um produto entrar só pelo significado (sem bater no texto).', 'assistente'),
  ('assistant_gte_vec_boa_min', '0.94'::jsonb, 'gte: semelhança a partir da qual um produto só pelo significado conta como correspondência boa.', 'assistente'),
  ('embeddings_gte_ajuda_min_sim', '0.80'::jsonb, 'gte: semelhança mínima de um trecho do manual de ajuda.', 'assistente')
on conflict (key) do nothing;

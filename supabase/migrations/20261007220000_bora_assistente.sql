-- ════════════════════════════════════════════════════════════════════════════
-- BORA ASSISTENTE (07/10/2026) — o cérebro de compras do cliente.
-- Autorizado pelo Danilo a 07/10 às 21:18 ("faça tudo, missão da noite,
-- prioridade para o agente virtual do cliente").
--
-- Aditiva e verde: não mexe em preços, taxas, carteira, tokens, despacho nem
-- em orders. Os totais vêm SEMPRE de quote_order_pricing (a mesma função do
-- checkout) e os preços dos produtos de products.price — o modelo nunca
-- escreve um preço nem faz contas.
--
-- O que nasce aqui:
--   f_unaccent(text)                           (wrapper imutável para índices)
--   product_embeddings                         (embedding Gemini 768d por produto,
--                                               tabela própria: não bate no
--                                               updated_at dos 56k produtos)
--   assistant_embedding_cache                  (embedding das perguntas, por hash)
--   assistant_conversations / assistant_chat_messages
--   assistant_cart_proposals                   (rascunhos de carrinho)
--   assistant_client_memory                    (o de sempre, marcas, restrições)
--   assistant_client_stats                     (poupança acumulada)
--   assistant_knowledge                        (textos que o admin edita)
--   assistant_gaps                             (perguntas sem resposta)
--   assistant_quota                            (mensagens por dia)
--   canonical_products / product_matches       (correspondência entre lojas)
--   assistant_lojas (view)                     (lojas elegíveis)
--   assistant_search_products(...)             (pesquisa híbrida FTS+trgm+vector, RRF)
--   assistant_basket_quote(jsonb)              (cesto por loja com entrega real)
--   assistant_propose_cart(...)                (grava rascunho)
--   assistant_mark_proposal(...)               (aberto / encomendado)
--   assistant_quota_increment()
--   assistant_set_embeddings(jsonb)            (só service_role — job em lote)
--   admin_assistant_overview(int)              (painel admin)
-- ════════════════════════════════════════════════════════════════════════════

-- extensões (idempotente; o resto da migração assume-as em "extensions")
create extension if not exists unaccent with schema extensions;
create extension if not exists pg_trgm with schema extensions;
create extension if not exists vector with schema extensions;

-- ── 0. Definições (nenhuma financeira) ──────────────────────────────────────
insert into public.platform_settings (key, value)
values
  ('assistant_enabled', 'true'::jsonb),
  ('assistant_model_primary', '"gemini-3.5-flash-lite"'::jsonb),
  ('assistant_model_fallback', '"gemini-3.6-flash"'::jsonb),
  ('assistant_embedding_model', '"gemini-embedding-001"'::jsonb),
  ('assistant_daily_quota', '40'::jsonb),
  ('assistant_max_message_chars', '2000'::jsonb),
  ('assistant_max_tool_iterations', '6'::jsonb),
  ('assistant_coverage_min_pct', '80'::jsonb),
  ('assistant_split_min_saving_cents', '300'::jsonb),
  ('assistant_split_min_saving_pct', '5'::jsonb),
  ('assistant_road_factor', '1.3'::jsonb),
  ('assistant_cost_usd_per_mtok_in', '0.10'::jsonb),
  ('assistant_cost_usd_per_mtok_out', '0.40'::jsonb),
  ('assistant_welcome_text', '"Olá! Sou o Bora Assistente. Diz-me o que precisas — por exemplo \"arroz, leite, ovos e azeite\" — e eu comparo as lojas da Guarda, com a entrega incluída, e encho-te o carrinho."'::jsonb)
on conflict (key) do nothing;

-- ── 1. Wrapper imutável do unaccent (para índices de expressão) ─────────────
create or replace function public.f_unaccent(p text)
returns text
language sql immutable parallel safe strict
set search_path = public, extensions
as $$
  select lower(extensions.unaccent('extensions.unaccent'::regdictionary, p));
$$;

create index if not exists idx_products_fts_pt
  on public.products using gin (
    to_tsvector('portuguese', public.f_unaccent(coalesce(name, '') || ' ' || coalesce(category, '')))
  );

-- ── 2. Embeddings (tabela própria; HNSW cosine) ─────────────────────────────
create table if not exists public.product_embeddings (
  product_id  text primary key references public.products(id) on delete cascade,
  embedding   extensions.vector(768) not null,
  model       text not null default 'gemini-embedding-001',
  updated_at  timestamptz not null default now()
);
create index if not exists idx_product_embeddings_hnsw
  on public.product_embeddings using hnsw (embedding extensions.vector_cosine_ops);
alter table public.product_embeddings enable row level security;
drop policy if exists product_embeddings_read on public.product_embeddings;
create policy product_embeddings_read on public.product_embeddings
  for select using (true);

create table if not exists public.assistant_embedding_cache (
  query_hash   text primary key,
  query_text   text not null,
  embedding    extensions.vector(768) not null,
  created_at   timestamptz not null default now(),
  last_used_at timestamptz not null default now(),
  hit_count    int not null default 0
);
alter table public.assistant_embedding_cache enable row level security;

-- ── 3. Conversas, mensagens, propostas, memória, stats, conhecimento, gaps ──
create table if not exists public.assistant_conversations (
  id               uuid primary key default gen_random_uuid(),
  user_id          uuid not null,
  channel          text not null default 'app',
  status           text not null default 'open' check (status in ('open','closed','handoff')),
  started_at       timestamptz not null default now(),
  last_message_at  timestamptz not null default now(),
  messages_count   int not null default 0,
  tokens_in        bigint not null default 0,
  tokens_out       bigint not null default 0,
  cost_usd         numeric(12,6) not null default 0,
  proposals_count  int not null default 0,
  savings_shown_cents int not null default 0,
  ticket_id        uuid,
  platform         text
);
create index if not exists idx_assistant_conversations_user on public.assistant_conversations(user_id, last_message_at desc);

create table if not exists public.assistant_chat_messages (
  id               uuid primary key default gen_random_uuid(),
  conversation_id  uuid not null references public.assistant_conversations(id) on delete cascade,
  user_id          uuid not null,
  role             text not null check (role in ('user','assistant','tool','system')),
  content          text,
  image_url        text,
  tool_name        text,
  tool_input       jsonb,
  tool_output      jsonb,
  structured       jsonb,
  tokens_in        int not null default 0,
  tokens_out       int not null default 0,
  model            text,
  latency_ms       int,
  created_at       timestamptz not null default now()
);
create index if not exists idx_assistant_messages_conv on public.assistant_chat_messages(conversation_id, created_at);

create table if not exists public.assistant_cart_proposals (
  id                uuid primary key default gen_random_uuid(),
  conversation_id   uuid references public.assistant_conversations(id) on delete set null,
  user_id           uuid not null,
  restaurant_id     text not null,
  restaurant_name   text not null,
  is_partner        boolean not null default false,
  service_type      text not null,
  items             jsonb not null,              -- [{product_id,name,quantity,unit_price,base_price,line_total,query,confidence,maior_18,photo_url}]
  missing_items     jsonb not null default '[]'::jsonb,
  coverage_pct      numeric(5,1) not null default 100,
  subtotal          numeric(10,2) not null,
  delivery_fee      numeric(10,2) not null default 0,
  service_fee       numeric(10,2) not null default 0,
  small_order_fee   numeric(10,2) not null default 0,
  bag_fee           numeric(10,2) not null default 0,
  customer_total    numeric(10,2) not null,
  distance_km       numeric(6,2),
  savings_cents     int not null default 0,     -- vs a loja mais cara com o mesmo cesto
  rank              int not null default 1,
  kind              text not null default 'single' check (kind in ('single','split')),
  split_group       uuid,
  has_maior_18      boolean not null default false,
  status            text not null default 'proposed' check (status in ('proposed','opened','ordered','expired')),
  order_id          text,
  dropoff_lat       double precision,
  dropoff_lng       double precision,
  apartment_delivery boolean not null default false,
  quote             jsonb,
  created_at        timestamptz not null default now(),
  opened_at         timestamptz,
  ordered_at        timestamptz,
  expires_at        timestamptz not null default (now() + interval '2 days')
);
create index if not exists idx_assistant_proposals_user on public.assistant_cart_proposals(user_id, created_at desc);
create index if not exists idx_assistant_proposals_status on public.assistant_cart_proposals(status, created_at desc);

create table if not exists public.assistant_client_memory (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null,
  kind        text not null check (kind in ('o_de_sempre','marca_preferida','nunca_substituir','substituir_por','restricao_alimentar','orcamento_habitual','nota')),
  key         text not null default '',
  value       jsonb not null,
  source      text not null default 'assistente',
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  unique (user_id, kind, key)
);
create index if not exists idx_assistant_memory_user on public.assistant_client_memory(user_id);

create table if not exists public.assistant_client_stats (
  user_id                uuid primary key,
  savings_shown_cents    bigint not null default 0,
  savings_realized_cents bigint not null default 0,
  proposals_count        int not null default 0,
  orders_count           int not null default 0,
  updated_at             timestamptz not null default now()
);

create table if not exists public.assistant_knowledge (
  id          uuid primary key default gen_random_uuid(),
  topic       text not null,
  title       text not null,
  content     text not null,
  active      boolean not null default true,
  sort_order  int not null default 100,
  updated_by  uuid,
  updated_at  timestamptz not null default now()
);

create table if not exists public.assistant_gaps (
  id               uuid primary key default gen_random_uuid(),
  conversation_id  uuid references public.assistant_conversations(id) on delete set null,
  user_id          uuid,
  question         text not null,
  reason           text not null default 'sem_resposta',
  resolved         boolean not null default false,
  created_at       timestamptz not null default now()
);

create table if not exists public.assistant_quota (
  user_id        uuid not null,
  day            date not null default current_date,
  messages_count int not null default 0,
  primary key (user_id, day)
);

create table if not exists public.canonical_products (
  id             uuid primary key default gen_random_uuid(),
  canonical_name text not null,
  brand          text,
  quantity       numeric,
  unit           text,
  created_at     timestamptz not null default now()
);
create table if not exists public.product_matches (
  product_id    text primary key references public.products(id) on delete cascade,
  canonical_id  uuid not null references public.canonical_products(id) on delete cascade,
  confidence    numeric(4,3) not null default 0.5,
  method        text not null default 'trgm' check (method in ('exact','trgm','embedding','llm','admin')),
  reviewed      boolean not null default false,
  created_at    timestamptz not null default now()
);
create index if not exists idx_product_matches_canonical on public.product_matches(canonical_id);

-- ── 4. RLS: o cliente só vê o seu; admin vê tudo ────────────────────────────
alter table public.assistant_conversations  enable row level security;
alter table public.assistant_chat_messages       enable row level security;
alter table public.assistant_cart_proposals enable row level security;
alter table public.assistant_client_memory  enable row level security;
alter table public.assistant_client_stats   enable row level security;
alter table public.assistant_knowledge      enable row level security;
alter table public.assistant_gaps           enable row level security;
alter table public.assistant_quota          enable row level security;
alter table public.canonical_products       enable row level security;
alter table public.product_matches          enable row level security;

drop policy if exists assistant_conversations_own on public.assistant_conversations;
create policy assistant_conversations_own on public.assistant_conversations
  for select using (auth.uid() = user_id or public.is_admin());
drop policy if exists assistant_messages_own on public.assistant_chat_messages;
create policy assistant_messages_own on public.assistant_chat_messages
  for select using (auth.uid() = user_id or public.is_admin());
drop policy if exists assistant_proposals_own on public.assistant_cart_proposals;
create policy assistant_proposals_own on public.assistant_cart_proposals
  for select using (auth.uid() = user_id or public.is_admin());
drop policy if exists assistant_memory_own_select on public.assistant_client_memory;
create policy assistant_memory_own_select on public.assistant_client_memory
  for select using (auth.uid() = user_id or public.is_admin());
drop policy if exists assistant_memory_own_write on public.assistant_client_memory;
create policy assistant_memory_own_write on public.assistant_client_memory
  for all using (auth.uid() = user_id) with check (auth.uid() = user_id);
drop policy if exists assistant_stats_own on public.assistant_client_stats;
create policy assistant_stats_own on public.assistant_client_stats
  for select using (auth.uid() = user_id or public.is_admin());
drop policy if exists assistant_knowledge_read on public.assistant_knowledge;
create policy assistant_knowledge_read on public.assistant_knowledge
  for select using (active or public.is_admin());
drop policy if exists assistant_knowledge_admin on public.assistant_knowledge;
create policy assistant_knowledge_admin on public.assistant_knowledge
  for all using (public.is_admin()) with check (public.is_admin());
drop policy if exists assistant_gaps_admin on public.assistant_gaps;
create policy assistant_gaps_admin on public.assistant_gaps
  for all using (public.is_admin()) with check (public.is_admin());
drop policy if exists assistant_quota_own on public.assistant_quota;
create policy assistant_quota_own on public.assistant_quota
  for select using (auth.uid() = user_id or public.is_admin());
drop policy if exists canonical_products_read on public.canonical_products;
create policy canonical_products_read on public.canonical_products for select using (true);
drop policy if exists canonical_products_admin on public.canonical_products;
create policy canonical_products_admin on public.canonical_products
  for all using (public.is_admin()) with check (public.is_admin());
drop policy if exists product_matches_read on public.product_matches;
create policy product_matches_read on public.product_matches for select using (true);
drop policy if exists product_matches_admin on public.product_matches;
create policy product_matches_admin on public.product_matches
  for all using (public.is_admin()) with check (public.is_admin());

-- ── 5. Lojas elegíveis (as que a home mostra e têm catálogo) ────────────────
create or replace view public.assistant_lojas as
select r.id, r.name, r.category, coalesce(r.is_partner, false) as is_partner,
       r.lat::double precision as lat, r.lng::double precision as lng,
       case when r.category in ('supermarket','store','pharmacy') then 'storeShopping' else 'restaurant' end as service_type
  from public.restaurants r
 where coalesce(r.is_active_admin, true)
   and coalesce(r.approval_status, 'approved') = 'approved'
   and coalesce(r.coming_soon, false) = false
   and coalesce(r.is_online, true)
   and r.lat is not null and r.lng is not null
   and r.id not like 'demo-%'
   and coalesce(r.category, '') not in ('festas','beauty','services')
   and (r.pausa_ate is null or r.pausa_ate < now())
   and exists (select 1 from public.products p where p.restaurant_id = r.id and coalesce(p.is_available, true) and p.price > 0);
grant select on public.assistant_lojas to authenticated, service_role;

-- ── 6. Pesquisa híbrida (FTS 'portuguese' + unaccent, trigramas, vector) ────
-- Por loja: as 5 melhores de cada estratégia dentro de cada loja; vector: top
-- 100 global (índice HNSW). Fusão RRF (k=60). Devolve só produtos que existem,
-- disponíveis, com preço > 0, em lojas elegíveis.
create or replace function public.assistant_search_products(
  p_query          text,
  p_restaurant_id  text default null,
  p_limit          int default 12,
  p_embedding      extensions.vector default null,
  p_per_store      boolean default false
)
returns table (
  product_id text, name text, restaurant_id text, restaurant_name text,
  is_partner boolean, service_type text, price numeric, display_price numeric,
  unit text, category text, photo_url text, maior_18 boolean,
  score numeric, match_kind text, confidence text
)
language plpgsql stable security definer
set search_path = public, extensions
as $$
#variable_conflict use_column
declare
  v_q      text := public.f_unaccent(coalesce(p_query, ''));
  v_ts     tsquery;
  v_markup numeric;
begin
  v_q := regexp_replace(v_q, '[^a-z0-9%/,\.\- ]', ' ', 'g');
  v_q := btrim(regexp_replace(v_q, '\s+', ' ', 'g'));
  if length(v_q) < 2 then return; end if;
  v_ts := websearch_to_tsquery('portuguese', v_q);
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
             order by ts_rank_cd(to_tsvector('portuguese', public.f_unaccent(coalesce(b.name,'') || ' ' || coalesce(b.category,''))), v_ts) desc,
                      length(b.name) asc, b.price asc) as rn
      from base b
     where to_tsvector('portuguese', public.f_unaccent(coalesce(b.name,'') || ' ' || coalesce(b.category,''))) @@ v_ts
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
  vec as (
    select e.product_id as id, row_number() over (order by e.embedding <=> p_embedding) as rn,
           (1 - (e.embedding <=> p_embedding))::numeric as sim
      from public.product_embeddings e
     where p_embedding is not null
     order by e.embedding <=> p_embedding
     limit 100
  ),
  fused as (
    select x.id,
           sum(x.s)::numeric as score,
           string_agg(x.kind, '+' order by x.kind) as match_kind,
           max(x.sim) as best_sim
      from (
        select f.id, 1.0 / (60 + f.rn) as s, 'fts' as kind, null::numeric as sim from fts f where f.rn <= 8
        union all
        select t.id, 1.0 / (60 + t.rn) as s, 'trgm' as kind, t.sim::numeric from trg t where t.rn <= 8
        union all
        select v.id, 1.0 / (60 + v.rn) as s, 'vec' as kind, v.sim from vec v
      ) x
     group by x.id
  ),
  scored as (
    select b.*, f.score
             + case when public.f_unaccent(b.name) like v_q || '%' then 0.02 else 0 end
             + case when f.match_kind like '%fts%' and f.match_kind like '%trgm%' then 0.01 else 0 end as score,
           f.match_kind, f.best_sim,
           row_number() over (partition by b.restaurant_id order by f.score desc, b.price asc) as rn_loja
      from fused f join base b on b.id = f.id
  )
  select s.id, s.name, s.restaurant_id, s.loja, s.is_partner, s.service_type,
         s.price,
         case when s.is_partner then s.price else round(s.price * (1 + v_markup), 2) end as display_price,
         s.unit, s.category, s.photo_url,
         public.produto_e_maior_18(s.name, s.category, s.taxonomy_section, s.category_root) as maior_18,
         round(s.score, 5) as score, s.match_kind,
         case when s.match_kind like '%fts%' or coalesce(s.best_sim, 0) >= 0.7 then 'alta' else 'parecido' end as confidence
    from scored s
   where (not p_per_store) or s.rn_loja = 1
   order by s.score desc, s.price asc
   limit greatest(1, least(coalesce(p_limit, 12), 200));
end;
$$;

revoke all on function public.assistant_search_products(text, text, int, extensions.vector, boolean) from public, anon;
grant execute on function public.assistant_search_products(text, text, int, extensions.vector, boolean) to authenticated, service_role;

-- ── 7. Cesto por loja, com entrega real (quote_order_pricing do checkout) ───
-- p_input: {items:[{query, quantity, embedding?}], dropoff_lat, dropoff_lng,
--           apartment_delivery?, restaurant_ids?[], conversation_id?, persist?}
-- Corre como o cliente (SECURITY INVOKER): quote_order_pricing precisa de auth.uid().
create or replace function public.assistant_basket_quote(p_input jsonb)
returns jsonb
language plpgsql security definer
set search_path = public, extensions
as $$
declare
  v_uid         uuid := auth.uid();
  v_items       jsonb := coalesce(p_input->'items', '[]'::jsonb);
  v_n           int;
  v_lat         double precision := nullif(p_input->>'dropoff_lat','')::double precision;
  v_lng         double precision := nullif(p_input->>'dropoff_lng','')::double precision;
  v_apt         boolean := coalesce((p_input->>'apartment_delivery')::boolean, false);
  v_only        text[] := case when jsonb_typeof(p_input->'restaurant_ids') = 'array'
                               then array(select jsonb_array_elements_text(p_input->'restaurant_ids')) end;
  v_persist     boolean := coalesce((p_input->>'persist')::boolean, true);
  v_conv        uuid := nullif(p_input->>'conversation_id','')::uuid;
  v_min_cov     numeric;
  v_road        numeric;
  v_split_cents int;
  v_split_pct   numeric;
  v_loja        record;
  v_item        jsonb;
  v_i           int;
  v_m           record;
  v_lines       jsonb;
  v_plines      jsonb;
  v_missing     jsonb;
  v_found       int;
  v_subtotal    numeric;
  v_dist        numeric;
  v_quote       jsonb;
  v_props       jsonb := '[]'::jsonb;
  v_prop        jsonb;
  v_full        jsonb;
  v_max_total   numeric;
  v_best_total  numeric;
  v_matches     jsonb := '{}'::jsonb;   -- restaurant_id -> array de matches por índice
  v_missing_all jsonb := '[]'::jsonb;
  v_favor       jsonb := null;
  v_split       jsonb := null;
  v_a           jsonb; v_b jsonb;
  v_ia          int; v_ib int;
  v_la          jsonb; v_lb jsonb;
  v_qa          jsonb; v_qb jsonb;
  v_split_total numeric;
  v_best_split  numeric := null;
  v_best_split_json jsonb := null;
  v_ids         uuid[];
  v_pid         uuid;
  v_has18       boolean;
  v_err         jsonb := '[]'::jsonb;
begin
  if v_uid is null then raise exception 'AUTH_REQUIRED'; end if;
  v_n := jsonb_array_length(v_items);
  if v_n = 0 then
    return jsonb_build_object('ok', false, 'error', 'SEM_ARTIGOS');
  end if;
  if v_n > 40 then
    return jsonb_build_object('ok', false, 'error', 'DEMASIADOS_ARTIGOS', 'max', 40);
  end if;
  if v_lat is null or v_lng is null then
    -- morada por defeito do cliente
    select ca.lat, ca.lng into v_lat, v_lng
      from public.client_addresses ca
     where ca.user_id = v_uid
     order by ca.is_default desc nulls last, ca.updated_at desc nulls last
     limit 1;
  end if;
  if v_lat is null or v_lng is null then
    return jsonb_build_object('ok', false, 'error', 'SEM_MORADA');
  end if;

  select coalesce((value::text)::numeric, 80) into v_min_cov from public.platform_settings where key = 'assistant_coverage_min_pct';
  select coalesce((value::text)::numeric, 1.3) into v_road from public.platform_settings where key = 'assistant_road_factor';
  select coalesce((value::text)::int, 300) into v_split_cents from public.platform_settings where key = 'assistant_split_min_saving_cents';
  select coalesce((value::text)::numeric, 5) into v_split_pct from public.platform_settings where key = 'assistant_split_min_saving_pct';
  v_min_cov := coalesce(v_min_cov, 80); v_road := coalesce(v_road, 1.3);
  v_split_cents := coalesce(v_split_cents, 300); v_split_pct := coalesce(v_split_pct, 5);

  -- 1) melhor produto por loja, para cada artigo
  for v_i in 0 .. v_n - 1 loop
    v_item := v_items -> v_i;
    for v_m in
      select * from public.assistant_search_products(
        v_item->>'query', null, 200,
        case when v_item ? 'embedding' and jsonb_typeof(v_item->'embedding') = 'array'
             then (v_item->>'embedding')::extensions.vector else null end,
        true)
    loop
      if v_only is not null and not (v_m.restaurant_id = any (v_only)) then continue; end if;
      if not (v_matches ? v_m.restaurant_id) then
        v_matches := v_matches || jsonb_build_object(v_m.restaurant_id, '{}'::jsonb);
      end if;
      v_matches := jsonb_set(
        v_matches,
        array[v_m.restaurant_id, v_i::text],
        jsonb_build_object(
          'idx', v_i, 'query', v_item->>'query',
          'quantity', greatest(1, coalesce((v_item->>'quantity')::int, 1)),
          'product_id', v_m.product_id, 'name', v_m.name,
          'base_price', v_m.price, 'unit_price', v_m.display_price,
          'line_total', round(v_m.display_price * greatest(1, coalesce((v_item->>'quantity')::int, 1)), 2),
          'unit', v_m.unit, 'photo_url', v_m.photo_url,
          'confidence', v_m.confidence, 'maior_18', v_m.maior_18,
          'match_kind', v_m.match_kind),
        true);
    end loop;
  end loop;

  -- 2) artigos que nenhuma loja tem → Favores
  for v_i in 0 .. v_n - 1 loop
    if not exists (
      select 1 from jsonb_each(v_matches) m where (m.value ? (v_i::text))
    ) then
      v_missing_all := v_missing_all || jsonb_build_object(
        'query', v_items->v_i->>'query',
        'quantity', greatest(1, coalesce((v_items->v_i->>'quantity')::int, 1)),
        'maior_18', public.produto_e_maior_18(v_items->v_i->>'query', null, null, null));
    end if;
  end loop;

  -- 3) cotar cada loja com cobertura suficiente
  for v_loja in
    select l.*, m.value as matches
      from jsonb_each(v_matches) m
      join public.assistant_lojas l on l.id = m.key
  loop
    v_found := (select count(*) from jsonb_object_keys(v_loja.matches));
    if (v_found::numeric * 100 / v_n) < v_min_cov and v_found < v_n then
      continue;
    end if;
    v_lines := (select coalesce(jsonb_agg(x.value order by (x.value->>'idx')::int), '[]'::jsonb) from jsonb_each(v_loja.matches) x);
    v_missing := (
      select coalesce(jsonb_agg(jsonb_build_object('query', v_items->k->>'query', 'quantity', greatest(1, coalesce((v_items->k->>'quantity')::int, 1))) order by k), '[]'::jsonb)
        from generate_series(0, v_n - 1) k
       where not (v_loja.matches ? k::text));
    v_plines := (select jsonb_agg(jsonb_build_object('product_id', x->>'product_id', 'unit_price', (x->>'base_price')::numeric, 'quantity', (x->>'quantity')::int)) from jsonb_array_elements(v_lines) x);
    v_subtotal := (select sum((x->>'line_total')::numeric) from jsonb_array_elements(v_lines) x);
    v_dist := greatest(1, round((public._haversine_km(v_loja.lat, v_loja.lng, v_lat, v_lng) * v_road)::numeric, 1));
    v_has18 := exists (select 1 from jsonb_array_elements(v_lines) x where (x->>'maior_18')::boolean);
    begin
      v_quote := public.quote_order_pricing(jsonb_build_object(
        'service_type', v_loja.service_type,
        'restaurant_id', v_loja.id,
        'distance_km', v_dist,
        'apartment_delivery', v_apt,
        'dropoff_lat', v_lat, 'dropoff_lng', v_lng,
        'subtotal', v_subtotal,
        'product_lines', v_plines,
        'items', '[]'::jsonb));
    exception when others then
      v_err := v_err || jsonb_build_object('loja', v_loja.id, 'erro', sqlerrm);
      continue;
    end;
    v_prop := jsonb_build_object(
      'restaurant_id', v_loja.id, 'restaurant_name', v_loja.name,
      'is_partner', v_loja.is_partner, 'service_type', v_loja.service_type,
      'open', coalesce((public.is_partner_open(v_loja.id)->>'is_open')::boolean, true),
      'coverage_pct', round(v_found::numeric * 100 / v_n, 1),
      'items', v_lines, 'missing_items', v_missing,
      'subtotal', (v_quote->>'subtotal')::numeric,
      'delivery_fee', coalesce((v_quote->>'delivery_fee')::numeric, 0),
      'service_fee', coalesce((v_quote->>'service_fee')::numeric, 0),
      'small_order_fee', coalesce((v_quote->>'small_order_fee')::numeric, 0),
      'bag_fee', coalesce((v_quote->>'bag_fee')::numeric, 0),
      'apartment_surcharge', coalesce((v_quote->>'apartment_surcharge')::numeric, 0),
      'customer_total', (v_quote->>'customer_total')::numeric,
      'distance_km', v_dist, 'has_maior_18', v_has18,
      'kind', 'single', 'quote', v_quote);
    v_props := v_props || v_prop;
  end loop;

  if jsonb_array_length(v_props) = 0 then
    -- nenhuma loja chega à cobertura mínima: devolve tudo para os Favores
    v_favor := public.assistant_favor_quote(v_lat, v_lng, v_road);
    return jsonb_build_object('ok', true, 'proposals', '[]'::jsonb, 'missing_everywhere', v_missing_all,
      'favor', v_favor, 'errors', v_err, 'note', 'NENHUMA_LOJA_COM_COBERTURA');
  end if;

  -- 4) ordenar: cobertura total primeiro, depois total mais baixo
  v_props := (select jsonb_agg(p order by (p->>'coverage_pct')::numeric desc, (p->>'customer_total')::numeric asc)
                from jsonb_array_elements(v_props) p);
  v_full := (select coalesce(jsonb_agg(p order by (p->>'customer_total')::numeric), '[]'::jsonb)
               from jsonb_array_elements(v_props) p where (p->>'coverage_pct')::numeric >= 100);
  if jsonb_array_length(v_full) > 0 then
    v_max_total := (select max((p->>'customer_total')::numeric) from jsonb_array_elements(v_full) p);
    v_best_total := (v_full->0->>'customer_total')::numeric;
  else
    v_max_total := (select max((p->>'customer_total')::numeric) from jsonb_array_elements(v_props) p);
    v_best_total := (v_props->0->>'customer_total')::numeric;
  end if;
  v_props := (select jsonb_agg(p || jsonb_build_object(
                 'savings_cents', greatest(0, round((v_max_total - (p->>'customer_total')::numeric) * 100))::int,
                 'rank', rn)
               order by rn)
              from jsonb_array_elements(v_props) with ordinality as t(p, rn));

  -- 5) dividir em 2 lojas (só entre as 3 mais baratas com cobertura total)
  if jsonb_array_length(v_full) >= 2 and v_n >= 2 then
    for v_ia in 0 .. least(2, jsonb_array_length(v_full) - 1) loop
      for v_ib in v_ia + 1 .. least(2, jsonb_array_length(v_full) - 1) loop
        v_a := v_full -> v_ia; v_b := v_full -> v_ib;
        v_la := '[]'::jsonb; v_lb := '[]'::jsonb;
        for v_i in 0 .. v_n - 1 loop
          if ((v_a->'items'->v_i)->>'line_total')::numeric <= ((v_b->'items'->v_i)->>'line_total')::numeric then
            v_la := v_la || (v_a->'items'->v_i);
          else
            v_lb := v_lb || (v_b->'items'->v_i);
          end if;
        end loop;
        if jsonb_array_length(v_la) = 0 or jsonb_array_length(v_lb) = 0 then continue; end if;
        begin
          v_qa := public.quote_order_pricing(jsonb_build_object(
            'service_type', v_a->>'service_type', 'restaurant_id', v_a->>'restaurant_id',
            'distance_km', (v_a->>'distance_km')::numeric, 'apartment_delivery', v_apt,
            'dropoff_lat', v_lat, 'dropoff_lng', v_lng,
            'subtotal', (select sum((x->>'line_total')::numeric) from jsonb_array_elements(v_la) x),
            'product_lines', (select jsonb_agg(jsonb_build_object('product_id', x->>'product_id', 'unit_price', (x->>'base_price')::numeric, 'quantity', (x->>'quantity')::int)) from jsonb_array_elements(v_la) x),
            'items', '[]'::jsonb));
          v_qb := public.quote_order_pricing(jsonb_build_object(
            'service_type', v_b->>'service_type', 'restaurant_id', v_b->>'restaurant_id',
            'distance_km', (v_b->>'distance_km')::numeric, 'apartment_delivery', v_apt,
            'dropoff_lat', v_lat, 'dropoff_lng', v_lng,
            'subtotal', (select sum((x->>'line_total')::numeric) from jsonb_array_elements(v_lb) x),
            'product_lines', (select jsonb_agg(jsonb_build_object('product_id', x->>'product_id', 'unit_price', (x->>'base_price')::numeric, 'quantity', (x->>'quantity')::int)) from jsonb_array_elements(v_lb) x),
            'items', '[]'::jsonb));
        exception when others then
          continue;
        end;
        v_split_total := (v_qa->>'customer_total')::numeric + (v_qb->>'customer_total')::numeric;
        if v_best_split is null or v_split_total < v_best_split then
          v_best_split := v_split_total;
          v_best_split_json := jsonb_build_object(
            'kind', 'split', 'customer_total', v_split_total,
            'savings_vs_best_single_cents', round((v_best_total - v_split_total) * 100)::int,
            'parts', jsonb_build_array(
              jsonb_build_object('restaurant_id', v_a->>'restaurant_id', 'restaurant_name', v_a->>'restaurant_name',
                'is_partner', (v_a->>'is_partner')::boolean, 'service_type', v_a->>'service_type',
                'distance_km', (v_a->>'distance_km')::numeric, 'items', v_la,
                'subtotal', (v_qa->>'subtotal')::numeric, 'delivery_fee', coalesce((v_qa->>'delivery_fee')::numeric,0),
                'service_fee', coalesce((v_qa->>'service_fee')::numeric,0), 'small_order_fee', coalesce((v_qa->>'small_order_fee')::numeric,0),
                'bag_fee', coalesce((v_qa->>'bag_fee')::numeric,0), 'customer_total', (v_qa->>'customer_total')::numeric, 'quote', v_qa),
              jsonb_build_object('restaurant_id', v_b->>'restaurant_id', 'restaurant_name', v_b->>'restaurant_name',
                'is_partner', (v_b->>'is_partner')::boolean, 'service_type', v_b->>'service_type',
                'distance_km', (v_b->>'distance_km')::numeric, 'items', v_lb,
                'subtotal', (v_qb->>'subtotal')::numeric, 'delivery_fee', coalesce((v_qb->>'delivery_fee')::numeric,0),
                'service_fee', coalesce((v_qb->>'service_fee')::numeric,0), 'small_order_fee', coalesce((v_qb->>'small_order_fee')::numeric,0),
                'bag_fee', coalesce((v_qb->>'bag_fee')::numeric,0), 'customer_total', (v_qb->>'customer_total')::numeric, 'quote', v_qb)));
        end if;
      end loop;
    end loop;
    if v_best_split is not null
       and (v_best_total - v_best_split) * 100 >= greatest(v_split_cents, v_best_total * v_split_pct) then
      v_split := v_best_split_json;
    end if;
  end if;

  -- 6) Favores para o que nenhuma loja tem
  if jsonb_array_length(v_missing_all) > 0 then
    v_favor := public.assistant_favor_quote(v_lat, v_lng, v_road);
  end if;

  -- 7) gravar rascunhos (3 melhores + divisão) para o cliente poder abrir
  if v_persist then
    v_ids := array[]::uuid[];
    for v_i in 0 .. least(2, jsonb_array_length(v_props) - 1) loop
      v_prop := v_props -> v_i;
      insert into public.assistant_cart_proposals (
        conversation_id, user_id, restaurant_id, restaurant_name, is_partner, service_type,
        items, missing_items, coverage_pct, subtotal, delivery_fee, service_fee, small_order_fee, bag_fee,
        customer_total, distance_km, savings_cents, rank, kind, has_maior_18,
        dropoff_lat, dropoff_lng, apartment_delivery, quote)
      values (
        v_conv, v_uid, v_prop->>'restaurant_id', v_prop->>'restaurant_name', (v_prop->>'is_partner')::boolean, v_prop->>'service_type',
        v_prop->'items', v_prop->'missing_items', (v_prop->>'coverage_pct')::numeric, (v_prop->>'subtotal')::numeric,
        (v_prop->>'delivery_fee')::numeric, (v_prop->>'service_fee')::numeric, (v_prop->>'small_order_fee')::numeric, (v_prop->>'bag_fee')::numeric,
        (v_prop->>'customer_total')::numeric, (v_prop->>'distance_km')::numeric, (v_prop->>'savings_cents')::int, (v_prop->>'rank')::int,
        'single', (v_prop->>'has_maior_18')::boolean, v_lat, v_lng, v_apt, v_prop->'quote')
      returning id into v_pid;
      v_props := jsonb_set(v_props, array[v_i::text, 'proposal_id'], to_jsonb(v_pid::text), true);
      v_ids := v_ids || v_pid;
    end loop;
    if v_split is not null then
      v_pid := gen_random_uuid();
      v_split := v_split || jsonb_build_object('split_group', v_pid::text);
      for v_i in 0 .. 1 loop
        v_prop := v_split->'parts'->v_i;
        insert into public.assistant_cart_proposals (
          conversation_id, user_id, restaurant_id, restaurant_name, is_partner, service_type,
          items, coverage_pct, subtotal, delivery_fee, service_fee, small_order_fee, bag_fee,
          customer_total, distance_km, savings_cents, rank, kind, split_group, has_maior_18,
          dropoff_lat, dropoff_lng, apartment_delivery, quote)
        values (
          v_conv, v_uid, v_prop->>'restaurant_id', v_prop->>'restaurant_name', (v_prop->>'is_partner')::boolean, v_prop->>'service_type',
          v_prop->'items', 100, (v_prop->>'subtotal')::numeric,
          (v_prop->>'delivery_fee')::numeric, (v_prop->>'service_fee')::numeric, (v_prop->>'small_order_fee')::numeric, (v_prop->>'bag_fee')::numeric,
          (v_prop->>'customer_total')::numeric, (v_prop->>'distance_km')::numeric, (v_split->>'savings_vs_best_single_cents')::int, v_i + 1,
          'split', v_pid,
          exists (select 1 from jsonb_array_elements(v_prop->'items') x where (x->>'maior_18')::boolean),
          v_lat, v_lng, v_apt, v_prop->'quote')
        returning id into v_pid;
        v_split := jsonb_set(v_split, array['parts', v_i::text, 'proposal_id'], to_jsonb(v_pid::text), true);
        v_pid := (v_split->>'split_group')::uuid;
      end loop;
    end if;
    if v_conv is not null then
      update public.assistant_conversations
         set proposals_count = proposals_count + coalesce(array_length(v_ids, 1), 0),
             savings_shown_cents = savings_shown_cents + coalesce((v_props->0->>'savings_cents')::int, 0)
       where id = v_conv and user_id = v_uid;
    end if;
    insert into public.assistant_client_stats (user_id, savings_shown_cents, proposals_count)
    values (v_uid, coalesce((v_props->0->>'savings_cents')::int, 0), coalesce(array_length(v_ids, 1), 0))
    on conflict (user_id) do update set
      savings_shown_cents = public.assistant_client_stats.savings_shown_cents + excluded.savings_shown_cents,
      proposals_count = public.assistant_client_stats.proposals_count + excluded.proposals_count,
      updated_at = now();
  end if;

  -- 8) saída (sem o quote cru, que só serve ao servidor)
  return jsonb_build_object(
    'ok', true,
    'proposals', (select coalesce(jsonb_agg(p - 'quote' order by (p->>'rank')::int), '[]'::jsonb) from jsonb_array_elements(v_props) p),
    'split', case when v_split is null then null else
       jsonb_build_object('customer_total', v_split->'customer_total',
         'savings_vs_best_single_cents', v_split->'savings_vs_best_single_cents',
         'split_group', v_split->'split_group',
         'parts', (select jsonb_agg(p - 'quote') from jsonb_array_elements(v_split->'parts') p)) end,
    'missing_everywhere', v_missing_all,
    'favor', v_favor,
    'errors', v_err,
    'dropoff', jsonb_build_object('lat', v_lat, 'lng', v_lng));
end;
$$;

revoke all on function public.assistant_basket_quote(jsonb) from public, anon;
grant execute on function public.assistant_basket_quote(jsonb) to authenticated, service_role;

-- Preço de um Favor (regra fixa do servidor: pricing_calculate_errand + settings errand_*)
create or replace function public.assistant_favor_quote(p_lat double precision, p_lng double precision, p_road numeric default 1.3)
returns jsonb
language plpgsql stable security definer
set search_path = public, extensions
as $$
declare
  v_center_lat double precision := 40.5373; -- Guarda (centro)
  v_center_lng double precision := -7.2659;
  v_dist numeric;
  v_n record;
  v_e record;
  v_available boolean;
begin
  select coalesce((value::text)::boolean, true) into v_available from public.platform_settings where key = 'errand_available';
  v_dist := greatest(1, round((public._haversine_km(v_center_lat, v_center_lng, p_lat, p_lng) * coalesce(p_road, 1.3))::numeric, 1));
  select * into v_n from public.pricing_calculate_errand('normal', false, v_dist, 0);
  select * into v_e from public.pricing_calculate_errand('express', false, v_dist, 0);
  return jsonb_build_object(
    'available', coalesce(v_available, true),
    'distance_km', v_dist,
    'normal_fee', v_n.fees_total, 'express_fee', v_e.fees_total,
    'normal_sla_minutes', (select (value::text)::int from public.platform_settings where key = 'errand_sla_normal_minutes'),
    'express_sla_minutes', (select (value::text)::int from public.platform_settings where key = 'errand_sla_express_minutes'),
    'max_advance_cents', (select (value::text)::int from public.platform_settings where key = 'errand_max_advance_cents'),
    'nota', 'O estafeta compra e paga; o valor da compra é acertado pelo talão no fim.');
end;
$$;
revoke all on function public.assistant_favor_quote(double precision, double precision, numeric) from public, anon;
grant execute on function public.assistant_favor_quote(double precision, double precision, numeric) to authenticated, service_role;

-- ── 8. Rascunho de carrinho para UMA loja (fluxo "quero um cheeseburger") ───
create or replace function public.assistant_propose_cart(
  p_conversation_id uuid, p_restaurant_id text, p_items jsonb,
  p_dropoff_lat double precision default null, p_dropoff_lng double precision default null,
  p_apartment boolean default false)
returns jsonb
language plpgsql security definer
set search_path = public, extensions
as $$
declare
  v_uid uuid := auth.uid();
  v_loja record;
  v_lines jsonb := '[]'::jsonb;
  v_it jsonb;
  v_p record;
  v_markup numeric;
  v_dist numeric;
  v_road numeric;
  v_lat double precision := p_dropoff_lat;
  v_lng double precision := p_dropoff_lng;
  v_quote jsonb;
  v_pid uuid;
  v_subtotal numeric;
begin
  if v_uid is null then raise exception 'AUTH_REQUIRED'; end if;
  select * into v_loja from public.assistant_lojas where id = p_restaurant_id;
  if not found then return jsonb_build_object('ok', false, 'error', 'LOJA_NAO_ELEGIVEL'); end if;
  if v_lat is null or v_lng is null then
    select ca.lat, ca.lng into v_lat, v_lng from public.client_addresses ca
     where ca.user_id = v_uid order by ca.is_default desc nulls last, ca.updated_at desc nulls last limit 1;
  end if;
  if v_lat is null or v_lng is null then return jsonb_build_object('ok', false, 'error', 'SEM_MORADA'); end if;
  select coalesce((value::text)::numeric, 0.15) into v_markup from public.platform_settings where key = 'non_partner_markup_pct';
  select coalesce((value::text)::numeric, 1.3) into v_road from public.platform_settings where key = 'assistant_road_factor';
  v_markup := coalesce(v_markup, 0.15); v_road := coalesce(v_road, 1.3);

  for v_it in select * from jsonb_array_elements(coalesce(p_items, '[]'::jsonb)) loop
    select p.id, p.name, p.price, p.unit, p.photo_url, p.category, p.taxonomy_section, p.category_root
      into v_p from public.products p
     where p.id = v_it->>'product_id' and p.restaurant_id = p_restaurant_id
       and coalesce(p.is_available, true) and p.price > 0;
    if not found then continue; end if;
    v_lines := v_lines || jsonb_build_object(
      'product_id', v_p.id, 'name', v_p.name,
      'quantity', greatest(1, coalesce((v_it->>'quantity')::int, 1)),
      'base_price', v_p.price,
      'unit_price', case when v_loja.is_partner then v_p.price else round(v_p.price * (1 + v_markup), 2) end,
      'line_total', round((case when v_loja.is_partner then v_p.price else round(v_p.price * (1 + v_markup), 2) end) * greatest(1, coalesce((v_it->>'quantity')::int, 1)), 2),
      'unit', v_p.unit, 'photo_url', v_p.photo_url, 'confidence', 'alta',
      'maior_18', public.produto_e_maior_18(v_p.name, v_p.category, v_p.taxonomy_section, v_p.category_root),
      'query', coalesce(v_it->>'query', v_p.name));
  end loop;
  if jsonb_array_length(v_lines) = 0 then return jsonb_build_object('ok', false, 'error', 'SEM_PRODUTOS_VALIDOS'); end if;

  v_subtotal := (select sum((x->>'line_total')::numeric) from jsonb_array_elements(v_lines) x);
  v_dist := greatest(1, round((public._haversine_km(v_loja.lat, v_loja.lng, v_lat, v_lng) * v_road)::numeric, 1));
  v_quote := public.quote_order_pricing(jsonb_build_object(
    'service_type', v_loja.service_type, 'restaurant_id', v_loja.id, 'distance_km', v_dist,
    'apartment_delivery', coalesce(p_apartment, false), 'dropoff_lat', v_lat, 'dropoff_lng', v_lng,
    'subtotal', v_subtotal,
    'product_lines', (select jsonb_agg(jsonb_build_object('product_id', x->>'product_id', 'unit_price', (x->>'base_price')::numeric, 'quantity', (x->>'quantity')::int)) from jsonb_array_elements(v_lines) x),
    'items', '[]'::jsonb));

  insert into public.assistant_cart_proposals (
    conversation_id, user_id, restaurant_id, restaurant_name, is_partner, service_type, items,
    subtotal, delivery_fee, service_fee, small_order_fee, bag_fee, customer_total, distance_km,
    has_maior_18, dropoff_lat, dropoff_lng, apartment_delivery, quote)
  values (
    p_conversation_id, v_uid, v_loja.id, v_loja.name, v_loja.is_partner, v_loja.service_type, v_lines,
    (v_quote->>'subtotal')::numeric, coalesce((v_quote->>'delivery_fee')::numeric,0), coalesce((v_quote->>'service_fee')::numeric,0),
    coalesce((v_quote->>'small_order_fee')::numeric,0), coalesce((v_quote->>'bag_fee')::numeric,0), (v_quote->>'customer_total')::numeric, v_dist,
    exists (select 1 from jsonb_array_elements(v_lines) x where (x->>'maior_18')::boolean),
    v_lat, v_lng, coalesce(p_apartment, false), v_quote)
  returning id into v_pid;

  if p_conversation_id is not null then
    update public.assistant_conversations set proposals_count = proposals_count + 1
     where id = p_conversation_id and user_id = v_uid;
  end if;
  insert into public.assistant_client_stats (user_id, proposals_count) values (v_uid, 1)
  on conflict (user_id) do update set proposals_count = public.assistant_client_stats.proposals_count + 1, updated_at = now();

  return jsonb_build_object('ok', true, 'proposal_id', v_pid,
    'restaurant_id', v_loja.id, 'restaurant_name', v_loja.name, 'is_partner', v_loja.is_partner,
    'service_type', v_loja.service_type, 'open', coalesce((public.is_partner_open(v_loja.id)->>'is_open')::boolean, true),
    'items', v_lines, 'subtotal', (v_quote->>'subtotal')::numeric,
    'delivery_fee', coalesce((v_quote->>'delivery_fee')::numeric,0), 'service_fee', coalesce((v_quote->>'service_fee')::numeric,0),
    'small_order_fee', coalesce((v_quote->>'small_order_fee')::numeric,0), 'bag_fee', coalesce((v_quote->>'bag_fee')::numeric,0),
    'customer_total', (v_quote->>'customer_total')::numeric, 'distance_km', v_dist,
    'has_maior_18', exists (select 1 from jsonb_array_elements(v_lines) x where (x->>'maior_18')::boolean));
end;
$$;
revoke all on function public.assistant_propose_cart(uuid, text, jsonb, double precision, double precision, boolean) from public, anon;
grant execute on function public.assistant_propose_cart(uuid, text, jsonb, double precision, double precision, boolean) to authenticated, service_role;

-- ── 9. Estado da proposta (a app marca "abri o carrinho" / "encomendei") ───
create or replace function public.assistant_mark_proposal(p_id uuid, p_status text, p_order_id text default null)
returns jsonb
language plpgsql security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_row public.assistant_cart_proposals;
begin
  if v_uid is null then raise exception 'AUTH_REQUIRED'; end if;
  if p_status not in ('opened','ordered') then return jsonb_build_object('ok', false, 'error', 'ESTADO_INVALIDO'); end if;
  select * into v_row from public.assistant_cart_proposals where id = p_id and user_id = v_uid;
  if not found then return jsonb_build_object('ok', false, 'error', 'NAO_ENCONTRADA'); end if;
  if p_status = 'ordered' then
    if p_order_id is null or not exists (select 1 from public.orders o where o.id = p_order_id and o.user_id = v_uid) then
      return jsonb_build_object('ok', false, 'error', 'PEDIDO_NAO_E_DO_CLIENTE');
    end if;
    if v_row.status <> 'ordered' then
      update public.assistant_cart_proposals set status = 'ordered', order_id = p_order_id, ordered_at = now() where id = p_id;
      insert into public.assistant_client_stats (user_id, savings_realized_cents, orders_count)
      values (v_uid, v_row.savings_cents, 1)
      on conflict (user_id) do update set
        savings_realized_cents = public.assistant_client_stats.savings_realized_cents + excluded.savings_realized_cents,
        orders_count = public.assistant_client_stats.orders_count + 1, updated_at = now();
    end if;
  else
    update public.assistant_cart_proposals set status = 'opened', opened_at = coalesce(opened_at, now())
     where id = p_id and status = 'proposed';
  end if;
  return jsonb_build_object('ok', true, 'status', p_status);
end;
$$;
revoke all on function public.assistant_mark_proposal(uuid, text, text) from public, anon;
grant execute on function public.assistant_mark_proposal(uuid, text, text) to authenticated;

-- ── 10. Quota diária ────────────────────────────────────────────────────────
create or replace function public.assistant_quota_increment()
returns integer
language sql security definer
set search_path = public
as $$
  insert into public.assistant_quota (user_id, day, messages_count)
  values (auth.uid(), current_date, 1)
  on conflict (user_id, day) do update set messages_count = public.assistant_quota.messages_count + 1
  returning messages_count;
$$;
revoke all on function public.assistant_quota_increment() from public, anon;
grant execute on function public.assistant_quota_increment() to authenticated, service_role;

-- ── 11. Escrita dos embeddings em lote (só o job com service_role) ──────────
create or replace function public.assistant_set_embeddings(p_rows jsonb)
returns integer
language plpgsql security definer
set search_path = public, extensions
as $$
declare v_n int;
begin
  if coalesce(current_setting('request.jwt.claims', true)::jsonb->>'role', current_setting('request.jwt.claim.role', true)) is distinct from 'service_role'
     and current_user not in ('postgres', 'service_role') then
    raise exception 'SO_SERVICE_ROLE';
  end if;
  insert into public.product_embeddings (product_id, embedding, model, updated_at)
  select r->>'id', (r->>'e')::extensions.vector, coalesce(r->>'m', 'gemini-embedding-001'), now()
    from jsonb_array_elements(p_rows) r
   where exists (select 1 from public.products p where p.id = r->>'id')
  on conflict (product_id) do update set embedding = excluded.embedding, model = excluded.model, updated_at = now();
  get diagnostics v_n = row_count;
  return v_n;
end;
$$;
revoke all on function public.assistant_set_embeddings(jsonb) from public, anon, authenticated;
grant execute on function public.assistant_set_embeddings(jsonb) to service_role;

-- Produtos ainda sem embedding (o job é retomável)
create or replace function public.assistant_products_without_embedding(p_limit int default 500, p_after text default '')
returns table (id text, texto text)
language sql stable security definer
set search_path = public
as $$
  select p.id,
         left(coalesce(p.name,'') || case when coalesce(p.category,'') <> '' then ' · ' || p.category else '' end
              || case when coalesce(p.unit,'') <> '' then ' · ' || p.unit else '' end, 300)
    from public.products p
   where coalesce(p.is_available, true) and p.price > 0 and p.id > p_after
     and not exists (select 1 from public.product_embeddings e where e.product_id = p.id)
   order by p.id
   limit greatest(1, least(p_limit, 2000));
$$;
revoke all on function public.assistant_products_without_embedding(int, text) from public, anon, authenticated;
grant execute on function public.assistant_products_without_embedding(int, text) to service_role;

-- ── 12. Painel admin: visão geral ───────────────────────────────────────────
create or replace function public.admin_assistant_overview(p_days int default 30)
returns jsonb
language plpgsql stable security definer
set search_path = public
as $$
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
    'products_total', (select count(*) from public.products where coalesce(is_available, true) and price > 0));
end;
$$;
revoke all on function public.admin_assistant_overview(int) from public, anon;
grant execute on function public.admin_assistant_overview(int) to authenticated;

-- ── 13. Conhecimento inicial (o admin edita no painel) ──────────────────────
insert into public.assistant_knowledge (topic, title, content, sort_order)
select * from (values
  ('favores', 'Favores', 'Favores: um estafeta compra o que o cliente pede (até ao adiantamento máximo definido) e entrega; o valor da compra é acertado pelo talão. Serve para tabaco, álcool, coisas fora do catálogo, levantar encomendas. Preço: taxa normal ou expresso, definida no servidor (ferramenta basket_quote devolve o valor em "favor").', 10),
  ('maiores_18', 'Produtos +18', 'Tabaco e bebidas alcoólicas só para maiores de 18. O estafeta pede documento de identificação na entrega; sem documento ou menor, não entrega e o pedido segue o cancelamento normal.', 20),
  ('tvde', 'Bora Motorista (TVDE)', 'Pedir uma viagem: separador Viagens na home. Preço fixo mostrado antes de confirmar; pode reservar para mais tarde; ida-e-volta com preço total. Pagamento cartão, MB Way ou dinheiro ao motorista. Cancelamento grátis antes de o motorista aceitar.', 30),
  ('limpeza', 'Limpeza', 'Limpeza doméstica por hora, com profissionais verificadas. Pedir na home (Limpeza), escolher data e duração. Pagamento online.', 40),
  ('reservas', 'Reservas de mesa', 'Reserva de mesa em restaurantes parceiros com pré-pagamento de 3 euros, descontado na conta quando o cliente chega. Cancelar com mais de 2 horas de antecedência devolve o valor.', 50),
  ('servicos', 'Serviços (barbearias, salões)', 'Marcações em barbearias e salões parceiros pela home (Serviços): escolher profissional, serviço e hora.', 60),
  ('tokens', 'Tokens Bora', 'Cada pedido entregue dá tokens (cerca de 3 por euro). 100 tokens valem 0,50 euros de desconto, até 50% do pedido. Vê os teus em Perfil > Carteira.', 70),
  ('carteira', 'Carteira', 'Saldo livre da carteira pode pagar pedidos. Reembolsos para a carteira caem em saldo (80%) e tokens (20%). Perfil > Carteira.', 80),
  ('promo', 'Códigos promocionais', 'Código BEMVINDO: 5 euros de boas-vindas no primeiro pedido. Introduzir no carrinho antes de pagar.', 90),
  ('cancelar', 'Cancelar um pedido', 'Antes de a loja aceitar: cancelamento grátis em Pedidos > o pedido > Cancelar. Depois de o estafeta recolher: já não é possível cancelar sem custos; falar com o suporte.', 100),
  ('humano', 'Falar com uma pessoa', 'Suporte humano: Perfil > Ajuda > Falar com o suporte (chat) ou e-mail boraappbora@gmail.com. O assistente passa a conversa ao suporte quando não consegue resolver.', 110),
  ('pagamento', 'Formas de pagamento', 'Cartão, MB Way, dinheiro (até 40 euros) e saldo da carteira/tokens. Mercados: paga-se um valor de garantia e acerta-se pelo talão real.', 120),
  ('horarios', 'Horários das lojas', 'Cada loja tem o seu horário; o assistente verifica se está aberta antes de propor. Pedidos a lojas fechadas podem ficar agendados para a abertura.', 130)
) as v(topic, title, content, sort_order)
where not exists (select 1 from public.assistant_knowledge k where k.topic = v.topic);

-- ── 14. Custo por conversa (só a Edge Function, com service_role) ───────────
create or replace function public.assistant_conversation_add_usage(p_id uuid, p_in bigint, p_out bigint, p_cost numeric)
returns void
language sql security definer
set search_path = public
as $$
  update public.assistant_conversations
     set tokens_in = tokens_in + coalesce(p_in, 0),
         tokens_out = tokens_out + coalesce(p_out, 0),
         cost_usd = cost_usd + coalesce(p_cost, 0)
   where id = p_id;
$$;
revoke all on function public.assistant_conversation_add_usage(uuid, bigint, bigint, numeric) from public, anon, authenticated;
grant execute on function public.assistant_conversation_add_usage(uuid, bigint, bigint, numeric) to service_role;

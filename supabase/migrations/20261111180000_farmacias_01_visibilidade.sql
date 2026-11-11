-- =============================================================================
-- farmacias-2026-11-11 · 01 · Lista de permissão por loja (lojas escondidas)
-- Ordem do Danilo (11/11/2026 15:18): as farmácias da Sé e Teixeira ficam ligadas SÓ nas contas dele;
-- para qualquer outra conta não aparece nada (categoria, pesquisa, faixas, link direto, Amigo, redes).
-- Mecanismo: restaurants.so_lista_permissao + tabela loja_lista_permissao + políticas RESTRICTIVE de
-- SELECT em restaurants e products + filtro nas funções SECURITY DEFINER que servem clientes.
-- Zero efeito em lojas com so_lista_permissao = false (todas as que existem hoje).
-- =============================================================================

alter table public.restaurants
  add column if not exists so_lista_permissao boolean not null default false;
comment on column public.restaurants.so_lista_permissao is
  'Loja escondida: só a veem admin, dono e quem está em loja_lista_permissao (farmacias-2026-11-11).';

create table if not exists public.loja_lista_permissao (
  restaurant_id text not null references public.restaurants(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  motivo text,
  criado_por uuid,
  criado_em timestamptz not null default now(),
  primary key (restaurant_id, user_id)
);
create index if not exists loja_lista_permissao_user_idx on public.loja_lista_permissao(user_id);
alter table public.loja_lista_permissao enable row level security;
revoke all on public.loja_lista_permissao from public, anon;
grant select on public.loja_lista_permissao to authenticated;
drop policy if exists loja_lista_permissao_admin on public.loja_lista_permissao;
create policy loja_lista_permissao_admin on public.loja_lista_permissao
  for select to authenticated using (public.is_admin() or user_id = auth.uid());

-- Ids das lojas escondidas que o utilizador atual NÃO pode ver (anon: todas as escondidas).
create or replace function public.lojas_escondidas_para_mim()
returns text[]
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select coalesce(array_agg(r.id), '{}'::text[])
    from public.restaurants r
   where r.so_lista_permissao
     and not (
       auth.uid() is not null and (
         public.is_admin()
         or r.user_id = auth.uid()
         or r.user_ = auth.uid()
         or exists (select 1 from public.loja_lista_permissao l
                     where l.restaurant_id = r.id and l.user_id = auth.uid())
       )
     );
$$;
revoke all on function public.lojas_escondidas_para_mim() from public;
grant execute on function public.lojas_escondidas_para_mim() to anon, authenticated;

create or replace function public.loja_visivel_para_mim(p_restaurant_id text)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select not (coalesce(p_restaurant_id, '') = any (public.lojas_escondidas_para_mim()));
$$;
revoke all on function public.loja_visivel_para_mim(text) from public;
grant execute on function public.loja_visivel_para_mim(text) to anon, authenticated;

-- Políticas RESTRICTIVE: juntam-se (AND) às que já existem. O (select ...) corre uma vez por consulta.
drop policy if exists restaurants_lista_permissao on public.restaurants;
create policy restaurants_lista_permissao on public.restaurants
  as restrictive for select to public
  using (not (id = any (coalesce((select public.lojas_escondidas_para_mim()), '{}'::text[]))));

drop policy if exists products_lista_permissao on public.products;
create policy products_lista_permissao on public.products
  as restrictive for select to public
  using (not (restaurant_id = any (coalesce((select public.lojas_escondidas_para_mim()), '{}'::text[]))));

-- ----------------------------------------------------------------------------
-- Funções SECURITY DEFINER que servem clientes: o mesmo filtro (a RLS não as apanha).
-- ----------------------------------------------------------------------------
-- cliente_pesquisar: corpo copiado da produção a 11/11/2026 (pg_get_functiondef) + filtro das lojas escondidas (farmácias)
CREATE OR REPLACE FUNCTION public.cliente_pesquisar(p_q text, p_limit integer DEFAULT 30)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
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
      and not (r.id = any (public.lojas_escondidas_para_mim()))
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
      where not (r.id = any (public.lojas_escondidas_para_mim()))
  ) y;

  return jsonb_build_object('lojas', lojas, 'produtos', prods);
end $function$
;

-- home_mais_pedidos: corpo copiado da produção a 11/11/2026 (pg_get_functiondef) + filtro das lojas escondidas (farmácias)
CREATE OR REPLACE FUNCTION public.home_mais_pedidos(p_limit integer DEFAULT 10)
 RETURNS TABLE(id text, name text, category text, cuisine_type text, photo_url text, cover_url text, is_partner boolean, coming_soon boolean, pedidos_30d bigint, avg_rating numeric)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select r.id, r.name, r.category, r.cuisine_type, r.photo_url, r.cover_url, r.is_partner,
         coalesce(r.coming_soon,false),
         (select count(*) from public.orders o where o.restaurant_id=r.id
            and o.status in ('delivered','completed') and o.created_at > now() - interval '30 days'),
         r.avg_rating
  from public.restaurants r
  where r.approval_status='approved' and coalesce(r.is_online,true) and coalesce(r.is_active_admin,true)
    and coalesce(r.coming_soon,false)=false and r.category in ('restaurant','festas')
      and not (r.id = any (public.lojas_escondidas_para_mim()))
  order by 9 desc, r.avg_rating desc nulls last, r.created_at desc
  limit greatest(1, least(p_limit, 30));
$function$
;

-- home_pede_outra_vez: corpo copiado da produção a 11/11/2026 (pg_get_functiondef) + filtro das lojas escondidas (farmácias)
CREATE OR REPLACE FUNCTION public.home_pede_outra_vez(p_limit integer DEFAULT 8)
 RETURNS TABLE(id text, name text, category text, cuisine_type text, photo_url text, cover_url text, is_partner boolean, coming_soon boolean, ultimo_pedido timestamp with time zone)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select r.id, r.name, r.category, r.cuisine_type, r.photo_url, r.cover_url, r.is_partner,
         coalesce(r.coming_soon,false), max(o.created_at)
  from public.orders o join public.restaurants r on r.id=o.restaurant_id
  where o.user_id = auth.uid() and o.status in ('delivered','completed')
    and r.approval_status='approved' and coalesce(r.is_online,true)
      and not (r.id = any (public.lojas_escondidas_para_mim()))
  group by r.id
  order by max(o.created_at) desc
  limit greatest(1, least(p_limit, 20));
$function$
;

-- search_businesses: corpo copiado da produção a 11/11/2026 (pg_get_functiondef) + filtro das lojas escondidas (farmácias)
CREATE OR REPLACE FUNCTION public.search_businesses(p_query text, p_lat double precision DEFAULT NULL::double precision, p_lng double precision DEFAULT NULL::double precision, p_limit integer DEFAULT 8)
 RETURNS TABLE(name text, address text, lat double precision, lng double precision, category text, source text, distance_km numeric)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  WITH q AS (SELECT NULLIF(btrim(p_query), '') AS term)
  SELECT name, address, lat, lng, category, source, distance_km
  FROM (
    -- Lojas Bora (catálogo real) — prioridade
    SELECT r.name,
           r.address,
           r.lat::double precision  AS lat,
           r.lng::double precision  AS lng,
           r.category,
           'bora'::text             AS source,
           CASE WHEN p_lat IS NOT NULL AND r.lat IS NOT NULL
                THEN public._haversine_km(p_lat::numeric, p_lng::numeric, r.lat::numeric, r.lng::numeric)
                ELSE NULL END        AS distance_km,
           0                         AS src_rank
    FROM public.restaurants r, q
    WHERE r.is_active_admin = true
      AND not (r.id = any (public.lojas_escondidas_para_mim()))
      AND (q.term IS NULL OR r.name ILIKE '%' || q.term || '%')
    UNION ALL
    -- Comércios OpenStreetMap
    SELECT b.name,
           b.address,
           b.lat,
           b.lng,
           b.category,
           'osm'::text              AS source,
           CASE WHEN p_lat IS NOT NULL AND b.lat IS NOT NULL
                THEN public._haversine_km(p_lat::numeric, p_lng::numeric, b.lat::numeric, b.lng::numeric)
                ELSE NULL END        AS distance_km,
           1                         AS src_rank
    FROM public.guarda_businesses b, q
    WHERE b.is_visible = true
      AND (q.term IS NULL OR b.name ILIKE '%' || q.term || '%')
  ) results
  ORDER BY distance_km NULLS LAST, src_rank, name
  LIMIT GREATEST(1, LEAST(COALESCE(p_limit, 8), 20));
$function$
;

-- agent_search_products: corpo copiado da produção a 11/11/2026 (pg_get_functiondef) + filtro das lojas escondidas (farmácias)
CREATE OR REPLACE FUNCTION public.agent_search_products(p_query text, p_loja text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
DECLARE
  v_loja text;
  v_res  jsonb;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'NOT_AUTHENTICATED'; END IF;
  IF length(btrim(COALESCE(p_query, ''))) < 2 THEN RETURN jsonb_build_object('ok', false, 'erro', 'escreve o produto'); END IF;
  IF NULLIF(btrim(COALESCE(p_loja, '')), '') IS NOT NULL THEN
    SELECT r.id INTO v_loja FROM public.restaurants r
     WHERE r.approval_status = 'approved' AND COALESCE(r.is_active_admin, false)
      AND not (r.id = any (public.lojas_escondidas_para_mim()))
       AND lower(extensions.unaccent(r.name)) LIKE '%' || lower(extensions.unaccent(btrim(p_loja))) || '%'
     ORDER BY length(r.name) LIMIT 1;
  END IF;
  SELECT COALESCE(jsonb_agg(jsonb_build_object(
           'produto', s.name, 'loja', s.restaurant_name,
           'preco_na_app_eur', round(COALESCE(s.display_price, s.price), 2),
           'unidade', s.unit, 'so_maiores_18', COALESCE(s.maior_18, false))), '[]'::jsonb)
    INTO v_res
    FROM public.assistant_search_products(btrim(p_query), v_loja, 8, NULL, false) s;
  RETURN jsonb_build_object('ok', jsonb_array_length(v_res) > 0, 'produtos', v_res,
    'nota', 'Preços da app. Nos mercados o valor final é o do talão.');
END $function$
;

-- agent_get_store_info: corpo copiado da produção a 11/11/2026 (pg_get_functiondef) + filtro das lojas escondidas (farmácias)
CREATE OR REPLACE FUNCTION public.agent_get_store_info(p_query text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
DECLARE
  v_q    text := lower(extensions.unaccent(btrim(COALESCE(p_query, ''))));
  v_res  jsonb;
  v_min  int;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'NOT_AUTHENTICATED'; END IF;
  IF length(v_q) < 2 THEN RETURN jsonb_build_object('ok', false, 'erro', 'escreve o nome da loja'); END IF;
  BEGIN v_min := (public.get_setting('min_order_cents') #>> '{}')::int; EXCEPTION WHEN OTHERS THEN v_min := NULL; END;
  SELECT COALESCE(jsonb_agg(x.j ORDER BY x.ord), '[]'::jsonb) INTO v_res FROM (
    SELECT CASE WHEN lower(extensions.unaccent(r.name)) = v_q THEN 0
                WHEN lower(extensions.unaccent(r.name)) LIKE v_q || '%' THEN 1 ELSE 2 END ord,
      jsonb_build_object(
        'loja', r.name,
        'tipo', CASE WHEN r.is_partner THEN 'parceira' ELSE 'compra pelo estafeta' END,
        'categoria', r.category,
        'em_breve', COALESCE(r.coming_soon, false),
        'aceita_pedidos_agora', CASE WHEN COALESCE(r.coming_soon, false) THEN false
                                     ELSE COALESCE((st.v->>'is_open')::boolean, false) AND COALESCE(r.is_online, false) END,
        'em_pausa', COALESCE((st.v->>'em_pausa')::boolean, false),
        'abre', CASE WHEN st.v->>'opens_at' IS NOT NULL THEN COALESCE(st.v->>'opens_dia', '') || ' às ' || (st.v->>'opens_at') END,
        'fecha_em_minutos', (st.v->>'closes_in_minutes')::int,
        'muito_movimento_mais_minutos', CASE WHEN r.busy_until > now() THEN r.busy_extra_minutes END,
        'horario_semana', (SELECT jsonb_object_agg(dn.pt,
             CASE WHEN COALESCE((r.business_hours->dn.k->>'closed')::boolean, false) THEN 'fechado'
                  WHEN r.business_hours->dn.k IS NULL THEN 'sem horário'
                  ELSE (r.business_hours->dn.k->>'open') || '–' || (r.business_hours->dn.k->>'close')
                       || CASE WHEN r.business_hours->dn.k->>'break_start' IS NOT NULL
                               THEN ' (pausa ' || (r.business_hours->dn.k->>'break_start') || '–' || (r.business_hours->dn.k->>'break_end') || ')'
                               ELSE '' END END)
           FROM (VALUES ('mon','segunda'),('tue','terça'),('wed','quarta'),('thu','quinta'),
                        ('fri','sexta'),('sat','sábado'),('sun','domingo')) dn(k, pt)),
        'entrega_gratis_a_partir_de_eur', CASE WHEN r.free_delivery_min_cents IS NOT NULL THEN round(r.free_delivery_min_cents / 100.0, 2) END,
        'taxa_pedido_pequeno_abaixo_de_eur', CASE WHEN NOT COALESCE(r.is_partner, false)
             THEN round(COALESCE(r.min_order_cents_override, v_min) / 100.0, 2) END,
        'tempo_preparo_min', r.takeaway_default_prep_minutes,
        'aceita_reservas_de_mesa', COALESCE(r.reservations_enabled, false),
        'recolha_na_loja', COALESCE(r.takeaway_enabled, false),
        'morada', r.address,
        'aviso_da_loja', NULLIF(btrim(COALESCE(r.about_text, '')), '')) j
      FROM public.restaurants r
      LEFT JOIN LATERAL (SELECT public.is_partner_open(r.id) v) st ON true
     WHERE r.approval_status = 'approved' AND COALESCE(r.is_active_admin, false)
      AND not (r.id = any (public.lojas_escondidas_para_mim()))
       AND lower(extensions.unaccent(r.name)) LIKE '%' || v_q || '%'
     ORDER BY 1 LIMIT 5) x;
  RETURN jsonb_build_object('ok', jsonb_array_length(v_res) > 0, 'lojas', v_res,
    'agora_em_portugal', to_char(now() AT TIME ZONE 'Europe/Lisbon', 'DD/MM HH24:MI'));
END $function$
;

-- store_active_promotions: corpo copiado da produção a 11/11/2026 (pg_get_functiondef) + filtro das lojas escondidas (farmácias)
CREATE OR REPLACE FUNCTION public.store_active_promotions(p_restaurant_id text)
 RETURNS TABLE(product_id text, price numeric, discount_price numeric, starts_at timestamp with time zone, ends_at timestamp with time zone, lowest_price_30d numeric)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select p.id,
         p.price::numeric,
         p.discount_price::numeric,
         p.discount_starts_at,
         p.discount_ends_at,
         public.product_lowest_price_30d(p.id)
    from public.products p
   where p.restaurant_id = p_restaurant_id
      and not (p.restaurant_id = any (public.lojas_escondidas_para_mim()))
     and public._promotions_enabled()
     and public._promotions_server_ready()
     and not coalesce(p.sold_by_weight, false)
     and public.product_promo_active(
           p.price::numeric, p.discount_price::numeric, p.discount_enabled,
           p.discount_starts_at, p.discount_ends_at, now());
$function$
;

-- social_lojas_permitidas: corpo copiado da produção a 11/11/2026 (pg_get_functiondef) + filtro das lojas escondidas (farmácias)
CREATE OR REPLACE FUNCTION public.social_lojas_permitidas()
 RETURNS TABLE(id text, nome text, tipo text, categoria text, is_partner boolean, produtos_disponiveis bigint)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select r.id::text,
         r.name,
         'restaurant'::text,
         r.category::text,
         coalesce(r.is_partner, false),
         (select count(*) from public.products p
           where p.restaurant_id = r.id and coalesce(p.is_available, true))
    from public.restaurants r
   where coalesce(r.coming_soon, false) = false
     and coalesce(r.is_active_admin, true) = true
     and r.approval_status = 'approved'
      and not coalesce(r.so_lista_permissao, false) -- os robôs das redes nunca mostram lojas escondidas
     and r.id::text not like 'demo-%'
     and r.name not ilike '%demo%'
     and exists (select 1 from public.products p
                  where p.restaurant_id = r.id and coalesce(p.is_available, true))
  union all
  select s.id::text,
         s.name,
         'service_provider'::text,
         null::text,
         true,
         0::bigint
    from public.service_providers s
   where coalesce(s.coming_soon, false) = false
     and coalesce(s.is_active_admin, true) = true
     and s.approval_status = 'approved'
     and s.name not ilike '%demo%'
  order by 3, 2;
$function$
;

-- assistant_lojas: definição da produção a 11/11/2026 + o Amigo nunca mostra lojas escondidas
create or replace view public.assistant_lojas with (security_invoker = true) as
SELECT id,
    name,
    category,
    COALESCE(is_partner, false) AS is_partner,
    lat,
    lng,
        CASE
            WHEN category = ANY (ARRAY['supermarket'::text, 'store'::text, 'pharmacy'::text]) THEN 'storeShopping'::text
            ELSE 'restaurant'::text
        END AS service_type
   FROM restaurants r
  WHERE COALESCE(is_active_admin, true) AND COALESCE(approval_status, 'approved'::text) = 'approved'::text AND COALESCE(coming_soon, false) = false AND COALESCE(is_online, true) AND lat IS NOT NULL AND lng IS NOT NULL AND id !~~ 'demo-%'::text AND NOT COALESCE(so_lista_permissao, false) AND (COALESCE(category, ''::text) <> ALL (ARRAY['festas'::text, 'beauty'::text, 'services'::text])) AND (pausa_ate IS NULL OR pausa_ate < now()) AND (EXISTS ( SELECT 1
           FROM products p
          WHERE p.restaurant_id = r.id AND COALESCE(p.is_available, true) AND p.price > 0::numeric));

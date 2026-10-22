-- REVERTER a migração 20261020153552_b2_pesquisa_pontuacao_real (B2, 20/10/2026).
-- Repõe as duas funções EXACTAMENTE como estavam antes (texto de
-- pg_get_functiondef, md5 conferido: assistant_search_products
-- d50ce3540e198265ccd70d0e3d0ed330, cliente_pesquisar ac9b57f3194ec4a1535fabf0c10d9189)
-- e tira os 4 ajudantes novos (só estas duas funções os usam).
-- CREATE OR REPLACE mantém as permissões que as funções já tinham.

CREATE OR REPLACE FUNCTION public.assistant_search_products(p_query text, p_restaurant_id text DEFAULT NULL::text, p_limit integer DEFAULT 12, p_embedding vector DEFAULT NULL::vector, p_per_store boolean DEFAULT false)
 RETURNS TABLE(product_id text, name text, restaurant_id text, restaurant_name text, is_partner boolean, service_type text, price numeric, display_price numeric, unit text, category text, photo_url text, maior_18 boolean, score numeric, match_kind text, confidence text)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
#variable_conflict use_column
declare
  v_q      text := public.f_unaccent(coalesce(p_query, ''));
  v_ts     tsquery;
  v_ts_or  tsquery;   -- afinação 08/10: qualquer palavra (ordena quem tem todas primeiro)
  v_ts_1   tsquery;   -- a primeira palavra (o substantivo) é obrigatória
  v_markup numeric;
begin
  v_q := regexp_replace(v_q, '[^a-z0-9%/,\.\- ]', ' ', 'g');
  v_q := btrim(regexp_replace(v_q, '\s+', ' ', 'g'));
  if length(v_q) < 2 then return; end if;
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
             order by (to_tsvector('portuguese', public.f_unaccent(coalesce(b.name,'') || ' ' || coalesce(b.category,''))) @@ v_ts) desc,
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
         case when (s.match_kind like '%fts%' and to_tsvector('portuguese', public.f_unaccent(coalesce(s.name,'') || ' ' || coalesce(s.category,''))) @@ v_ts)
                   or coalesce(s.best_sim, 0) >= 0.7
                   or (s.match_kind like '%fts%' and public.f_unaccent(s.name) like '%' || split_part(v_q, ' ', 1) || '%')
              then 'alta' else 'parecido' end as confidence
    from scored s
   where (not p_per_store) or s.rn_loja = 1
   order by s.score desc, s.price asc
   limit greatest(1, least(coalesce(p_limit, 12), 200));
end;
$function$;

CREATE OR REPLACE FUNCTION public.cliente_pesquisar(p_q text, p_limit integer DEFAULT 30)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare qn text; lojas jsonb; prods jsonb;
begin
  qn := trim(unaccent(lower(coalesce(p_q,''))));
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

  select coalesce(jsonb_agg(y), '[]'::jsonb) into prods from (
    select p.id, p.name, p.price, p.photo_url, p.restaurant_id, r.name as restaurant_name, r.category as restaurant_category,
           coalesce(r.coming_soon,false) as coming_soon
    from products p join restaurants r on r.id=p.restaurant_id
    where coalesce(p.is_available,true) and r.approval_status='approved' and coalesce(r.is_active_admin,true)
      and (p.search_normalized ilike '%'||qn||'%' or qn <% p.search_normalized)
    order by (p.search_normalized ilike qn||'%') desc, word_similarity(qn, p.search_normalized) desc, p.name
    limit greatest(1, least(p_limit*2,100))
  ) y;

  return jsonb_build_object('lojas', lojas, 'produtos', prods);
end $function$;

drop function if exists public.assistant_cobertura(text[], text[]);
drop function if exists public.assistant_cabeca(text);
drop function if exists public.assistant_tokens(text);
drop function if exists public.assistant_singular(text);

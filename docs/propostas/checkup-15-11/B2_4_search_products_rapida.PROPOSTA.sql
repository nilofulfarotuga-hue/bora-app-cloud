-- PROPOSTA (checkup-geral-15-11, B2.4). Quem aplica: Claude.ai. Nao muda resultados, so a ordem de calculo.
-- Medido 15/11 ~18:55 como postgres: search_products 786-1541 ms; pesquisa_produtos sozinha ~100 ms;
-- a parte das seccoes ~430 ms; com a CTE materializada 41 ms. anon tem statement_timeout=3s.
CREATE OR REPLACE FUNCTION public.search_products(query_text text, p_restaurant_id text DEFAULT NULL::text, max_results integer DEFAULT 50)
 RETURNS TABLE(result_type text, id text, name text, category text, category_root text, price numeric, photo_url text, match_rank real)
 LANGUAGE sql
 STABLE
 SET search_path TO 'public', 'extensions', 'pg_temp'
AS $function$
  -- checkup-15-11 (B2.4): cats MATERIALIZED. Sem isto o filtro bora_normalize(z.cr) descia para
  -- dentro do DISTINCT e corria nos ~60 mil produtos (~430 ms) em vez das ~256 seccoes (~40 ms).
  with cats as materialized (
    select distinct p.category_root as cr
      from public.products p
     where p.category_root is not null
       and p.is_available
       and (p_restaurant_id is null or p.restaurant_id = p_restaurant_id)
  ),
  q as (
    select btrim(regexp_replace(public.bora_normalize(query_text), '\s+', ' ', 'g')) as qn
  ),
  sec as (
    select z.cr, (10 + extensions.similarity(public.bora_normalize(z.cr), q.qn))::real as rank
      from q, cats z
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
$function$;

-- ADENDO 4 — parte F: a lista publica de avaliacoes de uma loja passa a trazer o
-- endereco da foto do prato (quando a avaliacao tem uma). Igual a funcao que
-- ja existia, mais um campo. So leitura; mesma assinatura e mesmas permissoes.

create or replace function public.get_restaurant_ratings_summary(p_restaurant_id text)
returns jsonb
language sql
stable
security definer
set search_path to 'public'
as $function$
  WITH base AS (
    SELECT stars, comment, tags, response_text, response_at, created_at, photo_url
    FROM public.ratings
    WHERE subject_type='partner'
      AND subject_id = p_restaurant_id
      AND (is_private IS NOT TRUE)
      AND (flagged_inappropriate IS NOT TRUE)
  ),
  agg AS (
    SELECT
      COUNT(*)                                AS total,
      ROUND(AVG(stars)::numeric, 2)           AS avg_stars,
      COUNT(*) FILTER (WHERE stars=5)::int    AS s5,
      COUNT(*) FILTER (WHERE stars=4)::int    AS s4,
      COUNT(*) FILTER (WHERE stars=3)::int    AS s3,
      COUNT(*) FILTER (WHERE stars=2)::int    AS s2,
      COUNT(*) FILTER (WHERE stars=1)::int    AS s1
    FROM base
  ),
  recent AS (
    SELECT jsonb_agg(
             jsonb_build_object(
               'stars', stars, 'comment', comment, 'tags', tags,
               'response_text', response_text, 'response_at', response_at,
               'created_at', created_at, 'photo_url', photo_url
             ) ORDER BY created_at DESC
           ) AS list
    FROM (SELECT * FROM base ORDER BY created_at DESC LIMIT 20) t
  )
  SELECT jsonb_build_object(
    'total',       agg.total,
    'avg_stars',   agg.avg_stars,
    'distribution', jsonb_build_object(
      '5', agg.s5, '4', agg.s4, '3', agg.s3, '2', agg.s2, '1', agg.s1
    ),
    'recent',      COALESCE(recent.list, '[]'::jsonb)
  )
  FROM agg, recent;
$function$;

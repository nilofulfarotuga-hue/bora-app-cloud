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

CREATE OR REPLACE FUNCTION public.embalagem_loja_valor(p_restaurant_id text, p_subtotal numeric)
RETURNS numeric
LANGUAGE sql
STABLE
SET search_path TO 'public', 'pg_temp'
AS $f$
  SELECT ROUND(CASE
           WHEN r.embalagem_cents IS NULL THEN NULL
           WHEN r.embalagem_grande_cents IS NOT NULL
                AND r.embalagem_grande_a_partir_cents IS NOT NULL
                AND ROUND(COALESCE(p_subtotal, 0) * 100) >= r.embalagem_grande_a_partir_cents
             THEN r.embalagem_grande_cents / 100.0
           ELSE r.embalagem_cents / 100.0
         END, 2)
    FROM public.restaurants r
   WHERE r.id = p_restaurant_id;
$f$;
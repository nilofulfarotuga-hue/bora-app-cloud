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
end $function$
;

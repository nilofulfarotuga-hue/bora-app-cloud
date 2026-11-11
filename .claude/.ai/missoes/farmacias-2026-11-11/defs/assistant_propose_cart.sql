CREATE OR REPLACE FUNCTION public.assistant_propose_cart(p_conversation_id uuid, p_restaurant_id text, p_items jsonb, p_dropoff_lat double precision DEFAULT NULL::double precision, p_dropoff_lng double precision DEFAULT NULL::double precision, p_apartment boolean DEFAULT false)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
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
$function$
;

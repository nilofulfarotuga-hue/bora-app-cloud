-- Afinação do Bora Assistente (07/10/2026, provas reais no PC): o cesto de compras
-- só cota supermercados e farmácias (Kiwoko/Worten/restaurantes só por pedido explícito)
-- e um artigo "parecido" (confiança baixa) conta como em falta em vez de encher o cesto.
-- Só muda assistant_basket_quote; nada de preços (continua quote_order_pricing).
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
      -- afinação 07/10: 'parecido' não enche cesto (conta como em falta)
      if v_m.confidence <> 'alta' then continue; end if;
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
     -- afinação 07/10: cesto de compras só em supermercados e farmácias (lojas de
     -- animais/bricolage/roupa e restaurantes entram só por restaurant_ids explícito)
     where v_only is not null or coalesce(l.category, '') in ('supermarket', 'pharmacy')
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



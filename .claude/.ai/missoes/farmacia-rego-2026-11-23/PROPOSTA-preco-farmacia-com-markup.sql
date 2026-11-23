-- PROPOSTA (NÃO APLICADA) — missão farmacia-rego-2026-11-23, Bloco 1, 23/11/2026.
-- Zona protegida (pricing). Só se aplica com o AUTORIZO do Danilo e com a escolha B1/B2/B3
-- de PROVA-DINHEIRO.md. Esta versão implementa a B2 (entrega normal + taxa de pedido pequeno
-- das farmácias, SEM a taxa de serviço das farmácias). Para a B1 mudar small_order_fee_calc
-- (ver nota no fim); para a B3 pôr r.service_fee = 5 % e o saco.
--
-- Ideia: uma farmácia parceira com restaurants.app_markup_pct > 0 (hoje só a Rego, 0.15)
-- deixa de apanhar o "ramo farmácia" de 14/11 (preço da Glovo, farmácia recebe tudo, taxa
-- 0,99 € + 5 %). Passa a: preço na app = balcão × (1 + markup) (já está assim nos produtos),
-- a farmácia recebe subtotal / (1 + markup) = o balcão, a Bora fica com a diferença como
-- platform_commission, sem taxa de serviço, sem saco, entrega e estafeta iguais.
-- As outras lojas (Sé, Teixeira, A3, Boom e todas) não têm app_markup_pct > 0 sendo farmácia,
-- por isso ficam iguais ao cêntimo — provar com o bloco de hash no fim, antes e depois.

begin;

-- 0) Fotografia ANTES (correr também depois e comparar os dois md5).
create temp table _antes on commit drop as
select md5(string_agg(format('%s|%s|%s|%s', r.id, s.sub, k.km, l::text), ',' order by r.id, s.sub, k.km)) h
from public.restaurants r
cross join (values (5.00),(11.50),(14.99),(15.00),(40.00)) s(sub)
cross join (values (1.0),(2.0),(6.5)) k(km)
cross join lateral public.pricing_calculate_loja(case when r.category in ('supermarket','store') then 'storeShopping' else 'restaurant' end,
                                                 s.sub, k.km, coalesce(r.is_partner,false), false, false, 1, r.id) l
where r.id <> 'farmacia-rego-guarda';

create or replace function public.partner_store_share(p_subtotal numeric, p_restaurant_id text)
 returns numeric
 language sql
 stable
 set search_path to 'public'
as $function$
  SELECT CASE
    -- 23/11/2026 farmácia com markup (Rego): a farmácia recebe o balcão = subtotal / (1 + markup).
    WHEN public._e_farmacia_parceira(p_restaurant_id)
         AND COALESCE((SELECT r.app_markup_pct FROM public.restaurants r WHERE r.id = p_restaurant_id), 0) > 0
      THEN ROUND(p_subtotal / (1 + (SELECT r.app_markup_pct FROM public.restaurants r WHERE r.id = p_restaurant_id)), 2)
    -- 14/11/2026 farmácias: preço ao cliente = preço da Glovo e a farmácia recebe tudo (sem markup oculto).
    WHEN public._e_farmacia_parceira(p_restaurant_id)
      THEN ROUND(p_subtotal, 2)
    WHEN COALESCE((SELECT r.app_markup_pct FROM public.restaurants r WHERE r.id = p_restaurant_id), 0) > 0
      THEN ROUND(p_subtotal / (1 + (SELECT r.app_markup_pct FROM public.restaurants r WHERE r.id = p_restaurant_id)), 2)
    ELSE public.partner_store_share(p_subtotal)
  END;
$function$;

-- pricing_calculate_loja: o ramo farmácia de 14/11 ganha um "senão" para as farmácias com markup.
-- (Corpo igual ao que está no ar a 23/11/2026, só muda o bloco marcado 23/11.)
create or replace function public.pricing_calculate_loja(p_service_type text, p_subtotal numeric, p_distance_km numeric, p_is_partner_store boolean, p_apartment_delivery boolean, p_is_stacked_partner boolean, p_bag_count integer, p_restaurant_id text)
 returns table(delivery_fee numeric, service_fee numeric, platform_commission numeric, driver_earnings numeric, customer_total numeric, partner_markup_hidden numeric, bag_fee numeric)
 language plpgsql
 stable
 set search_path to 'public', 'pg_temp'
as $function$
DECLARE
  r RECORD;
  s jsonb;
  v_sub NUMERIC;
  v_apt NUMERIC := 0;
  v_apt_driver NUMERIC := 0;
  v_poupado NUMERIC;
  v_fixo NUMERIC;
  v_liquido NUMERIC;
  v_min_parceiro INTEGER;
  v_emb NUMERIC;
  v_markup NUMERIC;
BEGIN
  SELECT * INTO r FROM public.pricing_calculate(p_service_type, p_subtotal, p_distance_km,
    p_is_partner_store, p_apartment_delivery, p_is_stacked_partner, COALESCE(p_bag_count, 0));

  v_sub := GREATEST(0.0, ROUND(COALESCE(p_subtotal, 0.0), 2));

  IF NOT COALESCE(p_is_partner_store, false)
     AND p_service_type IN ('restaurant', 'storeShopping')
     AND p_restaurant_id IS NOT NULL
     AND EXISTS (SELECT 1 FROM public.restaurants x
                  WHERE x.id = p_restaurant_id
                    AND x.free_delivery_min_cents IS NOT NULL
                    AND NOT COALESCE(x.is_partner, false)
                    AND ROUND(v_sub * 100) >= x.free_delivery_min_cents) THEN
    SELECT jsonb_object_agg(key, value) INTO s FROM public.platform_settings;
    IF p_apartment_delivery THEN
      v_apt        := ((s->>'apartment_surcharge_total_cents')::NUMERIC) / 100.0;
      v_apt_driver := ((s->>'apartment_driver_share_cents')::NUMERIC) / 100.0;
    END IF;
    v_poupado := LEAST(GREATEST(0, r.delivery_fee - COALESCE(v_apt, 0)),
                       COALESCE(((s->>'delivery_base_fee_cents')::NUMERIC) / 100.0, 0));
    v_fixo := ROUND(((s->>'driver_base_fee_cents')::NUMERIC) / 100.0
                  + CASE WHEN p_service_type = 'storeShopping'
                         THEN ((s->>'driver_surcharge_cents')::NUMERIC) / 100.0 ELSE 0 END
                  + ((s->>'driver_per_km_cents')::NUMERIC) / 100.0 * GREATEST(1.0, COALESCE(p_distance_km, 1.0))
                  + COALESCE(v_apt_driver, 0), 2);
    v_liquido := GREATEST(0, ROUND(v_sub * (s->>'non_partner_markup_pct')::NUMERIC, 2)
                           + (r.delivery_fee - v_poupado) + r.service_fee - v_fixo);
    r.driver_earnings := ROUND(v_fixo + ROUND(v_liquido * (s->>'driver_profit_share_pct')::NUMERIC, 2), 2);
    r.delivery_fee    := ROUND(r.delivery_fee - v_poupado, 2);
    r.customer_total  := ROUND(r.customer_total - v_poupado, 2);
  END IF;

  IF COALESCE(p_is_partner_store, false)
     AND NOT COALESCE(p_is_stacked_partner, false)
     AND p_service_type IN ('restaurant', 'storeShopping')
     AND p_restaurant_id IS NOT NULL THEN
    SELECT x.free_delivery_min_cents INTO v_min_parceiro
      FROM public.restaurants x
     WHERE x.id = p_restaurant_id AND COALESCE(x.is_partner, false);
    IF v_min_parceiro IS NOT NULL AND ROUND(v_sub * 100) >= v_min_parceiro THEN
      SELECT jsonb_object_agg(key, value) INTO s FROM public.platform_settings;
      v_poupado := LEAST(GREATEST(r.delivery_fee, 0),
                         COALESCE(((s->>'delivery_base_fee_cents')::NUMERIC) / 100.0, 0));
      r.delivery_fee   := ROUND(r.delivery_fee - v_poupado, 2);
      r.customer_total := ROUND(r.customer_total - v_poupado, 2);
    END IF;
  END IF;

  IF COALESCE(p_is_partner_store, false)
     AND p_service_type IN ('restaurant', 'storeShopping')
     AND public._e_farmacia_parceira(p_restaurant_id) THEN
    SELECT jsonb_object_agg(key, value) INTO s FROM public.platform_settings;
    SELECT COALESCE(x.app_markup_pct, 0) INTO v_markup FROM public.restaurants x WHERE x.id = p_restaurant_id;
    IF v_markup > 0 THEN
      -- 23/11/2026 farmácia com markup (Rego, AUTORIZO do Danilo de <data>): preço = balcão × (1 + markup) já
      -- dentro do produto; a farmácia recebe o balcão; a Bora fica com a diferença; SEM taxa de serviço das
      -- farmácias; sem saco; entrega igual. A taxa de pedido pequeno continua a somar-se à parte (B2).
      r.service_fee := 0;
      r.partner_markup_hidden := 0;
      r.platform_commission := ROUND(v_sub - ROUND(v_sub / (1 + v_markup), 2), 2)
                             + CASE WHEN COALESCE(p_apartment_delivery, false)
                                    THEN ROUND(COALESCE((s->>'apartment_platform_share_cents')::NUMERIC, 0) / 100.0, 2)
                                    ELSE 0 END;
      r.bag_fee := 0;
      r.customer_total := ROUND(v_sub + r.delivery_fee, 2);
    ELSE
      -- 14/11/2026 farmácias parceiras (AUTORIZO do Danilo 13/11 e 14/11 11:44/11:48).
      r.service_fee := ROUND(COALESCE((s->>'pharmacy_service_fee_fixed_cents')::NUMERIC, 0) / 100.0
                             + v_sub * COALESCE((s->>'client_service_fee_pct')::NUMERIC, 0), 2);
      r.partner_markup_hidden := 0;
      r.platform_commission := CASE WHEN COALESCE(p_apartment_delivery, false)
                                    THEN ROUND(COALESCE((s->>'apartment_platform_share_cents')::NUMERIC, 0) / 100.0, 2)
                                    ELSE 0 END;
      r.bag_fee := 0;
      r.customer_total := ROUND(v_sub + r.service_fee + r.delivery_fee + r.bag_fee, 2);
    END IF;
  END IF;

  IF p_service_type = 'restaurant' AND p_restaurant_id IS NOT NULL THEN
    v_emb := public.embalagem_loja_valor(p_restaurant_id, v_sub);
    IF v_emb IS NOT NULL THEN
      r.customer_total := ROUND(r.customer_total - COALESCE(r.bag_fee, 0) + v_emb, 2);
      r.bag_fee := v_emb;
    END IF;
  END IF;

  RETURN QUERY SELECT r.delivery_fee, r.service_fee, r.platform_commission, r.driver_earnings,
                      r.customer_total, r.partner_markup_hidden, r.bag_fee;
END;
$function$;

-- 1) Prova por hash: as outras lojas ficam iguais ao cêntimo.
select (select h from _antes) = md5(string_agg(format('%s|%s|%s|%s', r.id, s.sub, k.km, l::text), ',' order by r.id, s.sub, k.km)) as outras_lojas_iguais
from public.restaurants r
cross join (values (5.00),(11.50),(14.99),(15.00),(40.00)) s(sub)
cross join (values (1.0),(2.0),(6.5)) k(km)
cross join lateral public.pricing_calculate_loja(case when r.category in ('supermarket','store') then 'storeShopping' else 'restaurant' end,
                                                 s.sub, k.km, coalesce(r.is_partner,false), false, false, 1, r.id) l
where r.id <> 'farmacia-rego-guarda';

-- 2) A Rego com 10,00 € de balcão (11,50 € na app), 2 km. Esperado (B2): entrega 2,50, serviço 0,
--    comissão Bora 1,50, cliente 14,00 + pedido pequeno 1,39 = 15,39, Rego 10,00, estafeta 4,20.
select l.*, public.small_order_fee_calc('restaurant', 11.50, 'farmacia-rego-guarda') pedido_pequeno,
       public.partner_store_share(11.50, 'farmacia-rego-guarda') rego_recebe
from public.pricing_calculate_loja('restaurant', 11.50, 2, true, false, false, 0, 'farmacia-rego-guarda') l;

-- Se tudo bater: commit. Se não: rollback.
rollback;

-- NOTA B1 (sem taxa de pedido pequeno, como a A3): em small_order_fee_calc, trocar
--   AND COALESCE(r.category, '') <> 'pharmacy'
-- por
--   AND (COALESCE(r.category, '') <> 'pharmacy' OR COALESCE(r.app_markup_pct, 0) > 0)
-- (dá prejuízo de 0,20 € num pedido de 10 € a 2 km — ver PROVA-DINHEIRO.md).
-- ANTES DE APLICAR: confirmar no código que o fecho semanal e o relatório do parceiro usam
-- partner_store_share(subtotal, restaurant_id) para farmácias (grep _parceiro_vendas_semana).

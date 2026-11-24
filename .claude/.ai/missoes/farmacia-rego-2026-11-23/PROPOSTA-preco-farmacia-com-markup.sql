-- PRONTA A APLICAR (AUTORIZADA, NÃO APLICADA pelo Claude Code) — missão farmacia-rego-2026-11-23, Adendo 2.
-- AUTORIZO do Danilo 23/11 13:36: na Farmácia Rego o cliente paga o balcão + 15 % dentro do preço do
-- produto (nunca visível), mais a taxa de serviço de 5 %, a entrega normal e a taxa de pedido pequeno das
-- farmácias (1,39 € abaixo de 15 €). Sem os 0,99 € fixos. Saco como hoje nas farmácias (0). A Rego recebe
-- sempre o balcão; sem comissão extra nem mensalidade. Receitas como na Sé (Favor, sem os 15 %).
--
-- Porque não foi aplicada: a tranca do PC (bora-tranca) recusou escrever a migração em
-- supabase/migrations ("migration que toca tokens/wallet/pagamentos/ledger") e, antes, recusou
-- CREATE FUNCTION em produção ("migration só em local; publica a Claude.ai"). Aplica a Claude.ai.
--
-- Como aplicar: correr este ficheiro inteiro no editor SQL / MCP. Ele faz begin; tira a fotografia;
-- muda as 2 funções; compara; mostra a prova da Rego; e acaba em ROLLBACK. Se outras_lojas_iguais = true
-- nas duas linhas e a Rego der os números esperados, trocar o "rollback;" do fim por "commit;" e voltar
-- a correr. Depois copiar as 2 funções para supabase/migrations/20261123140000_farmacia_com_markup_rego.sql
-- no ramo ai/2026-11-23-farmacia-rego (regra: migração aplicada em produção fica no repo).
--
-- Só muda o resultado para farmácias parceiras com restaurants.app_markup_pct > 0 (hoje só a Rego).
-- FOTOGRAFIA ANTES tirada pelo Claude Code a 23/11 ~13:45 Lisboa (sem a Rego, 32 lojas, 2880 combinações):
--   h_loja    = c5a05d89e9148582eeae035d4997d635
--   h_pequeno = 755ec7faff29de63563dcd76f5a1b1bb

begin;

create temp table _antes on commit drop as
select md5(string_agg(format('%s|%s|%s|%s|%s|%s|%s|%s', r.id, st.t, s.sub, k.km, a.apt, a.stk, l::text, public.partner_store_share(s.sub, r.id)), ',' order by r.id, st.t, s.sub, k.km, a.apt, a.stk)) h_loja,
       (select md5(string_agg(format('%s|%s|%s', r2.id, s2.sub, public.small_order_fee_calc(t2.t, s2.sub, r2.id)), ',' order by r2.id, s2.sub, t2.t))
          from public.restaurants r2 cross join (values (5.00),(11.50),(14.99),(15.00),(40.00)) s2(sub) cross join (values ('restaurant'),('storeShopping')) t2(t)
         where r2.id <> 'farmacia-rego-guarda') h_pequeno
from public.restaurants r
cross join (values ('restaurant'),('storeShopping')) st(t)
cross join (values (5.00),(11.50),(14.99),(15.00),(40.00)) s(sub)
cross join (values (1.0),(2.0),(6.5)) k(km)
cross join (values (false,false),(true,false),(false,true)) a(apt,stk)
cross join lateral public.pricing_calculate_loja(st.t, s.sub, k.km, coalesce(r.is_partner,false), a.apt, a.stk, 1, r.id) l
where r.id <> 'farmacia-rego-guarda';

select 'antes' quando, h_loja = 'c5a05d89e9148582eeae035d4997d635' bate_com_23_11, h_loja, h_pequeno from _antes;

create or replace function public.partner_store_share(p_subtotal numeric, p_restaurant_id text)
 returns numeric
 language sql
 stable
 set search_path to 'public'
as $function$
  SELECT CASE
    -- 23/11/2026 farmácia com markup (Rego, AUTORIZO do Danilo 23/11 13:36): a farmácia recebe o balcão = subtotal / (1 + markup).
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

-- Corpo igual ao que está no ar a 23/11/2026; só muda o bloco das farmácias (marcado 23/11).
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
    -- só a taxa base (primeiros 4 km) é grátis; km extra e suplemento de apartamento pagam-se
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

  -- 28/10/2026: loja PARCEIRA com entrega grátis a partir de um valor — só a taxa base sai.
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

  -- 14/11/2026 farmácias parceiras (AUTORIZO do Danilo 13/11 e 14/11 11:44/11:48): o preço dos produtos é o da
  -- Glovo e vai todo para a farmácia (sem markup oculto nem comissão no pedido). O cliente paga subtotal + taxa
  -- de serviço (pharmacy_service_fee_fixed_cents + client_service_fee_pct do subtotal, numa linha só) + entrega
  -- (a mesma de sempre). Sem saco. A taxa de pedido pequeno soma-se à parte (small_order_fee_calc).
  IF COALESCE(p_is_partner_store, false)
     AND p_service_type IN ('restaurant', 'storeShopping')
     AND public._e_farmacia_parceira(p_restaurant_id) THEN
    SELECT jsonb_object_agg(key, value) INTO s FROM public.platform_settings;
    SELECT COALESCE(x.app_markup_pct, 0) INTO v_markup FROM public.restaurants x WHERE x.id = p_restaurant_id;
    IF v_markup > 0 THEN
      -- 23/11/2026 farmácia com markup (Rego, AUTORIZO do Danilo 23/11 13:36): o markup já vem dentro do preço
      -- do produto (balcão × (1 + markup)) e fica para a Bora; taxa de serviço = só client_service_fee_pct do
      -- subtotal (sem os 0,99 € fixos); sem saco; entrega igual; pedido pequeno à parte, como nas farmácias.
      r.service_fee := ROUND(v_sub * COALESCE((s->>'client_service_fee_pct')::NUMERIC, 0), 2);
      r.partner_markup_hidden := 0;
      r.platform_commission := ROUND(v_sub - ROUND(v_sub / (1 + v_markup), 2), 2)
                             + CASE WHEN COALESCE(p_apartment_delivery, false)
                                    THEN ROUND(COALESCE((s->>'apartment_platform_share_cents')::NUMERIC, 0) / 100.0, 2)
                                    ELSE 0 END;
    ELSE
      r.service_fee := ROUND(COALESCE((s->>'pharmacy_service_fee_fixed_cents')::NUMERIC, 0) / 100.0
                             + v_sub * COALESCE((s->>'client_service_fee_pct')::NUMERIC, 0), 2);
      r.partner_markup_hidden := 0;
      r.platform_commission := CASE WHEN COALESCE(p_apartment_delivery, false)
                                    THEN ROUND(COALESCE((s->>'apartment_platform_share_cents')::NUMERIC, 0) / 100.0, 2)
                                    ELSE 0 END;
    END IF;
    r.bag_fee := 0;
    r.customer_total := ROUND(v_sub + r.service_fee + r.delivery_fee + r.bag_fee, 2);
  END IF;

  -- 23/11/2026 embalagem da loja (AUTORIZO do Danilo 23/11 10:44): em vez do saco, o valor da loja; vai 100 % para a loja.
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

-- 1) Prova por hash DEPOIS: as outras 32 lojas ficam iguais ao cêntimo (as duas colunas têm de ser true).
select 'depois' quando,
  (select h_loja from _antes) = md5(string_agg(format('%s|%s|%s|%s|%s|%s|%s|%s', r.id, st.t, s.sub, k.km, a.apt, a.stk, l::text, public.partner_store_share(s.sub, r.id)), ',' order by r.id, st.t, s.sub, k.km, a.apt, a.stk)) as lojas_iguais,
  (select h_pequeno from _antes) = (select md5(string_agg(format('%s|%s|%s', r2.id, s2.sub, public.small_order_fee_calc(t2.t, s2.sub, r2.id)), ',' order by r2.id, s2.sub, t2.t))
      from public.restaurants r2 cross join (values (5.00),(11.50),(14.99),(15.00),(40.00)) s2(sub) cross join (values ('restaurant'),('storeShopping')) t2(t)
     where r2.id <> 'farmacia-rego-guarda') as pedido_pequeno_igual
from public.restaurants r
cross join (values ('restaurant'),('storeShopping')) st(t)
cross join (values (5.00),(11.50),(14.99),(15.00),(40.00)) s(sub)
cross join (values (1.0),(2.0),(6.5)) k(km)
cross join (values (false,false),(true,false),(false,true)) a(apt,stk)
cross join lateral public.pricing_calculate_loja(st.t, s.sub, k.km, coalesce(r.is_partner,false), a.apt, a.stk, 1, r.id) l
where r.id <> 'farmacia-rego-guarda';

-- 2) A Rego: 1 produto de 10,00 € de balcão (11,50 € na app), 2 km.
--    ESPERADO: entrega 2,50 · serviço 0,58 · saco 0 · customer_total 14,58 · pedido pequeno 1,39
--    → cliente paga 15,97 · Rego recebe 10,00 · estafeta 4,20 · comissão Bora 1,50
--    → Bora fica 15,97 − 10,00 − 4,20 = 1,77.
select l.*, public.small_order_fee_calc('restaurant', 11.50, 'farmacia-rego-guarda') pedido_pequeno,
       l.customer_total + public.small_order_fee_calc('restaurant', 11.50, 'farmacia-rego-guarda') cliente_paga,
       public.partner_store_share(11.50, 'farmacia-rego-guarda') rego_recebe
from public.pricing_calculate_loja('restaurant', 11.50, 2, true, false, false, 0, 'farmacia-rego-guarda') l;

-- Se tudo bater: trocar por commit;
rollback;

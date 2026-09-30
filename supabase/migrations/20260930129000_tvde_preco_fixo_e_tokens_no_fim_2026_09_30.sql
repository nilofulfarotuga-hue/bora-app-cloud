-- 30/09 (Danilo): preço FIXO. O cliente paga o que viu ao pedir (tabela pela distância
-- da rota escolhida), nunca pela distância que o carro fez. Só muda com paragem (já cobrada à parte).
-- Mesmo princípio para o ganho do motorista (o que viu na oferta). Pacote/volta intocados.
-- Também: os tokens descontados no pedido voltam a ser descontados no fim (antes caíam se a app mandasse 0).
--
-- Aplicada em produção pela Claude.ai por MCP (schema_migrations.version 20260930114530,
-- nome tvde_preco_fixo_e_tokens_no_fim_2026_09_30). No ar foi aplicada como "patch por âncora"
-- sobre a definição anterior. Para o repo não andar atrás do ar, este ficheiro grava a definição
-- FINAL tirada do ar com pg_get_functiondef (md5 042a6809a28681f13b71c3f0eee4f0bc, 14153 caracteres).
-- A definição anterior está em public.fn_definition_backups (reason 'antes do preço fixo 2026-09-30').
CREATE TABLE IF NOT EXISTS public.fn_definition_backups (
  id bigserial primary key, fn text not null, definition text not null, reason text, created_at timestamptz default now());
ALTER TABLE public.fn_definition_backups ENABLE ROW LEVEL SECURITY;

INSERT INTO public.platform_settings (key, value, description, category)
VALUES ('tvde_fixed_price_enabled', 'true'::jsonb,
 'Preço fixo TVDE (Lei 45/2018 art. 15.º n.º 6): cliente paga o preço mostrado ao pedir, calculado pela distância da rota escolhida, não pela distância percorrida. Só muda com paragem extra. false = volta a recalcular pela distância final.', 'tvde')
ON CONFLICT (key) DO NOTHING;

CREATE OR REPLACE FUNCTION public.tvde_finish_ride(p_ride_id uuid, p_final_distance_km numeric, p_distance_source text DEFAULT NULL::text, p_tokens_to_apply integer DEFAULT 0)
 RETURNS tvde_rides
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_uid UUID := auth.uid(); v_ride public.tvde_rides;
  v_fare INT; v_d_base INT; v_d_perkm INT; v_extra_km INT; v_driver_earn INT; v_bora_cut INT;
  v_sub JSONB; v_covered BOOLEAN; v_sub_id UUID; v_next UUID; v_is_member BOOLEAN;
  v_stops_fee INT; v_stops_drv INT; v_prepaid BOOLEAN; v_settle INT;
  v_tokens_discount_cents INT; v_max_discount_cents INT; v_token_value_x100 INT;
  v_pm TEXT; v_rt_cash BOOLEAN := false; v_rt_price INT;
  v_stops_cash INT;
  v_rt_paid INT; v_return_reserve INT := 0; v_bora_raw INT;
  v_plan_fixed_earn INT;
  v_promo INT := 0; v_credit public.tvde_promo_credits;
  v_fixed INT;
  v_fixed_drv INT;
  v_outbound_km NUMERIC; v_outbound_extra_km INT := 0; v_extra_km_over INT := 0; v_extra_fare INT := 0;
  v_overage_km_raw NUMERIC := 0;
  v_price_km NUMERIC; v_fixed_on BOOLEAN; v_tokens_eff INT;
BEGIN
  SELECT * INTO v_ride FROM public.tvde_rides WHERE id = p_ride_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'ride_not_found'; END IF;
  IF v_ride.driver_id <> v_uid THEN RAISE EXCEPTION 'not_ride_driver'; END IF;
  IF v_ride.status <> 'em_andamento' THEN RAISE EXCEPTION 'invalid_transition: %', v_ride.status; END IF;

  v_stops_fee := COALESCE(v_ride.extra_stops_fee_cents, 0);
  v_stops_drv := COALESCE(v_ride.extra_stops_driver_cents, 0);
  v_prepaid   := v_ride.roundtrip_credit_id IS NOT NULL;
  v_pm        := COALESCE(v_ride.payment_method, 'cash');
  -- 2026-09-30 PREÇO FIXO (Danilo): distância da rota escolhida ao pedir manda.
  SELECT COALESCE((value #>> '{}')::boolean, true) INTO v_fixed_on FROM public.platform_settings WHERE key = 'tvde_fixed_price_enabled';
  v_fixed_on := COALESCE(v_fixed_on, true);
  v_price_km := CASE WHEN v_fixed_on AND NOT v_prepaid AND v_ride.est_distance_km IS NOT NULL
                     THEN v_ride.est_distance_km ELSE p_final_distance_km END;
  v_tokens_eff := CASE WHEN p_tokens_to_apply > 0 THEN p_tokens_to_apply ELSE COALESCE(v_ride.tokens_applied_count, 0) END;

  SELECT COALESCE(SUM(fee_cents),0) INTO v_stops_cash
    FROM public.tvde_ride_stops
   WHERE ride_id = p_ride_id AND payment_intent_id IS NULL;

  v_fare := public.tvde_calculate_fare(v_price_km);
  IF v_ride.is_return_leg THEN
    v_d_base := (public.get_setting('tvde_roundtrip_return_driver_cents') #>> '{}')::int;
  ELSIF v_prepaid THEN
    -- 2026-09-21 (Danilo): a IDA do pacote paga o mesmo que a volta (3,75).
    -- Chave propria de proposito — baixar `tvde_driver_base_cents` tirava 25
    -- centimos ao motorista em TODA a corrida TVDE normal, o que nao foi pedido.
    -- COALESCE: sem a chave nova, volta ao comportamento antigo.
    v_d_base := COALESCE((public.get_setting('tvde_roundtrip_outbound_driver_cents') #>> '{}')::int,
                         (public.get_setting('tvde_driver_base_cents') #>> '{}')::int);
  ELSE
    v_d_base := (public.get_setting('tvde_driver_base_cents') #>> '{}')::int;
  END IF;
  v_d_perkm := (public.get_setting('tvde_driver_per_km_cents') #>> '{}')::int;
  v_extra_km := GREATEST(0, CEIL(v_price_km - (public.get_setting('tvde_base_distance_km') #>> '{}')::int))::int;
  v_driver_earn := v_d_base + v_extra_km * v_d_perkm;

  v_sub := public.tvde_consume_subscription_ride(v_ride.client_id);
  v_covered := COALESCE((v_sub->>'covered')::boolean, false);
  v_sub_id := NULLIF(v_sub->>'subscription_id','')::uuid;

  IF v_prepaid THEN
    -- FIX 2026-08-18: reconhecer a receita do PACOTE (antes: v_fare := v_stops_fee).
    SELECT paid_cents INTO v_rt_paid
      FROM public.tvde_roundtrip_credits WHERE id = v_ride.roundtrip_credit_id;
    v_driver_earn := v_driver_earn + v_stops_drv;
    IF COALESCE(v_ride.is_return_leg, false) THEN
      -- FIX 2026-09-18 (pedido do Danilo, caso real Stela Neves): a volta so'
      -- e' gratis ATE' a distancia ja espelhada na ida (o preco do pacote
      -- assume ida=volta). O km a mais na volta cobra-se ao cliente ao preco
      -- normal por km (sem o desconto do pacote), porque esse km nunca foi
      -- pago. Antes disto o km extra saia sempre de graca e a Bora ficava
      -- sem cobrir o custo real do motorista nessa distancia a mais.
      SELECT r2.final_distance_km INTO v_outbound_km
        FROM public.tvde_roundtrip_credits c
        JOIN public.tvde_rides r2 ON r2.id = c.outbound_ride_id
       WHERE c.id = v_ride.roundtrip_credit_id;
      v_outbound_extra_km := GREATEST(0, CEIL(COALESCE(v_outbound_km, 0) - (public.get_setting('tvde_base_distance_km') #>> '{}')::int))::int;
      v_extra_km_over := GREATEST(0, v_extra_km - v_outbound_extra_km);
      v_extra_fare := v_extra_km_over * (public.get_setting('tvde_extra_per_km_cents') #>> '{}')::int;
      v_overage_km_raw := GREATEST(0, p_final_distance_km - COALESCE(v_outbound_km, p_final_distance_km));

      v_fare     := v_stops_fee + v_extra_fare;        -- receita da ida ja reconhecida + diferenca real da volta
      v_bora_cut := v_stops_fee - v_stops_drv + v_extra_fare - v_extra_km_over * v_d_perkm;
    ELSE
      v_return_reserve := COALESCE((public.get_setting('tvde_roundtrip_return_driver_cents') #>> '{}')::int, 350)
                          + v_extra_km * v_d_perkm;
      v_fare     := v_stops_fee;
      v_bora_cut := COALESCE(v_rt_paid, 0) + v_stops_fee - v_driver_earn - v_return_reserve;
    END IF;
  ELSIF v_covered THEN
    -- Plano com ganho FIXO acordado manda sobre a percentagem (2026-09-04).
    SELECT driver_earn_cents INTO v_plan_fixed_earn
      FROM public.tvde_subscriptions WHERE id = v_sub_id;
    IF v_plan_fixed_earn IS NOT NULL THEN
      v_driver_earn := v_plan_fixed_earn + v_stops_drv;
      v_fare        := v_stops_fee;
      v_bora_cut    := v_stops_fee - v_driver_earn;
    ELSE
      v_bora_cut    := (v_driver_earn - ROUND(v_driver_earn * 0.85)::int) + (v_stops_fee - v_stops_drv);
      v_driver_earn := ROUND(v_driver_earn * 0.85)::int + v_stops_drv;
      v_fare        := v_stops_fee;
    END IF;
  ELSE
    SELECT EXISTS (SELECT 1 FROM public.tvde_subscriptions
      WHERE client_id = v_ride.client_id AND active = true AND now() BETWEEN starts_at AND ends_at)
      INTO v_is_member;
    IF v_is_member THEN
      v_fare := (public.get_setting('tvde_extra_ride_cents') #>> '{}')::int;
    END IF;
    -- 2026-09-13: plano a medida -- preco fixo ao cliente pela distancia FINAL
    -- (a autoritativa). Aqui auth.uid() e' o motorista, por isso o ajudante e'
    -- chamado explicitamente com o cliente da corrida.
    -- 2026-09-22 (caso Ricardo): o mesmo override pode fixar o ganho do
    -- motorista. NULL nessa coluna = tudo como antes.
    v_fixed := public.tvde_client_fixed_fare_cents(v_ride.client_id, v_price_km);
    v_fixed_drv := public.tvde_client_fixed_driver_earn_cents(v_ride.client_id, v_price_km);
    IF v_fixed IS NOT NULL THEN
      v_fare := v_fixed;
    END IF;
    IF v_fixed_drv IS NOT NULL THEN
      v_driver_earn := v_fixed_drv;
    END IF;
    v_fare        := v_fare + v_stops_fee;
    v_driver_earn := v_driver_earn + v_stops_drv;
    -- 2026-09-18: VALOR COMBINADO A MAO (corrida de balcao / acordo pontual).
    -- Quando o admin combinou o preco ao telefone, a formula por km NAO manda.
    -- Colunas a NULL => comportamento exactamente igual ao de antes.
    IF v_ride.agreed_fare_cents IS NOT NULL THEN
      v_fare := v_ride.agreed_fare_cents + v_stops_fee;
    END IF;
    IF v_ride.agreed_driver_earn_cents IS NOT NULL THEN
      v_driver_earn := v_ride.agreed_driver_earn_cents + v_stops_drv;
    END IF;
    v_bora_cut    := v_fare - v_driver_earn;
  END IF;

  -- 2026-09-13: credito promocional (boa-vontade). Foi descontado ao criar a
  -- corrida; aqui a tarifa e' recalculada pela distancia final, por isso o
  -- desconto tem de ser aplicado outra vez. Cliente paga tarifa - credito,
  -- motorista ganha o normal, a Bora absorve. Nunca em pacote pre-pago.
  IF v_ride.promo_credit_id IS NOT NULL THEN
    SELECT * INTO v_credit FROM public.tvde_promo_credits
     WHERE id = v_ride.promo_credit_id FOR UPDATE;
    IF FOUND AND NOT v_prepaid AND v_fare > 0
       AND (v_credit.used_ride_id = p_ride_id OR v_credit.used_at IS NULL) THEN
      v_promo    := LEAST(v_credit.amount_cents, v_fare);
      v_fare     := v_fare - v_promo;
      v_bora_cut := v_bora_cut - v_promo;
      UPDATE public.tvde_promo_credits
         SET used_at = COALESCE(used_at, now()), used_ride_id = p_ride_id
       WHERE id = v_credit.id;
    ELSIF FOUND AND v_credit.used_ride_id = p_ride_id THEN
      -- Nao ha tarifa onde aplicar (pacote pre-pago ou tarifa zero): o credito volta.
      UPDATE public.tvde_promo_credits
         SET used_at = NULL, used_ride_id = NULL
       WHERE id = v_credit.id;
    END IF;
  END IF;

  -- Tokens NUNCA em pacote (ja pago no vale).
  IF v_tokens_eff > 0 AND v_fare > 0 AND NOT v_prepaid THEN
    v_token_value_x100 := COALESCE((public.get_setting('token_value_cents_x100') #>> '{}')::int, 50);
    v_max_discount_cents := GREATEST(0, (v_fare
      * COALESCE((public.get_setting('token_payment_max_pct') #>> '{}')::int, 50)) / 100);
    v_tokens_discount_cents := LEAST((v_tokens_eff * v_token_value_x100) / 100, v_max_discount_cents);
    v_fare := v_fare - v_tokens_discount_cents;
    v_bora_cut := v_bora_cut - v_tokens_discount_cents;
  ELSE
    v_tokens_discount_cents := 0;
  END IF;

  -- SEM GUARDA (decisao 18/08): o corte gravado e o CRU.
  v_bora_raw := v_bora_cut;

  UPDATE public.tvde_rides SET status = 'finalizada', final_distance_km = p_final_distance_km,
    final_fare_cents = v_fare, driver_earn_cents = v_driver_earn, bora_cut_cents = v_bora_cut,
    used_subscription_ride = v_covered, subscription_id = v_sub_id,
    promo_credit_applied_cents = v_promo,
    final_distance_source = COALESCE(p_distance_source, final_distance_source),
    tokens_applied_count = CASE WHEN p_tokens_to_apply > 0 THEN p_tokens_to_apply ELSE tokens_applied_count END,
    tokens_applied_value_cents = CASE WHEN p_tokens_to_apply > 0 THEN v_tokens_discount_cents ELSE tokens_applied_value_cents END,
    roundtrip_return_overage_km = CASE WHEN v_overage_km_raw > 0 THEN v_overage_km_raw ELSE roundtrip_return_overage_km END,
    roundtrip_return_overage_cents = CASE WHEN v_extra_fare > 0 THEN v_extra_fare ELSE roundtrip_return_overage_cents END,
    updated_at = now()
   WHERE id = p_ride_id RETURNING * INTO v_ride;

  IF v_prepaid AND NOT COALESCE(v_ride.is_return_leg, false) THEN
    SELECT (payment_intent_id IS NULL), paid_cents INTO v_rt_cash, v_rt_price
      FROM public.tvde_roundtrip_credits WHERE id = v_ride.roundtrip_credit_id;
  END IF;

  -- === LIQUIDACAO DO SALDO DO MOTORISTA ===
  -- FIX 2026-09-18: a diferenca real da volta (v_extra_fare) e' dinheiro que o
  -- motorista recolhe em mao no fim, exactamente como as paradas em dinheiro
  -- (v_stops_cash) — nao ha hoje caminho online para cobrar isto. Sem esta
  -- linha o valor ficava a mais nos "livros" (final_fare_cents/bora_cut) mas
  -- nunca acertava o saldo do motorista: ele ficava a dever a Bora o que
  -- recolheu a mais sem a Bora saber. v_extra_fare e' sempre 0 fora do caso
  -- de overage na volta, por isso esta soma nao mexe em mais nada.
  IF v_pm = 'cash' AND NOT v_prepaid AND NOT v_covered THEN
    v_settle := v_bora_raw;
  ELSIF v_prepaid AND COALESCE(v_rt_cash, false) AND NOT COALESCE(v_ride.is_return_leg, false) THEN
    v_settle := (COALESCE(v_rt_price, (public.get_setting('tvde_roundtrip_price_cents') #>> '{}')::int) + v_stops_cash) - v_driver_earn;
  ELSE
    v_settle := v_stops_cash + v_extra_fare - v_driver_earn;
  END IF;
  IF v_settle <> 0 THEN
    INSERT INTO public.tvde_driver_balances (driver_id, balance, updated_at)
      VALUES (v_uid, ROUND(v_settle / 100.0, 2), now())
      ON CONFLICT (driver_id) DO UPDATE
        SET balance = public.tvde_driver_balances.balance + ROUND(v_settle / 100.0, 2), updated_at = now();
  END IF;

  INSERT INTO public.tvde_ride_events (ride_id, status, actor, meta)
    VALUES (p_ride_id, 'finalizada', 'driver', jsonb_build_object('final_distance_km', p_final_distance_km,
      'final_fare_cents', v_fare, 'driver_earn_cents', v_driver_earn, 'bora_cut_cents', v_bora_cut,
      'bora_cut_raw_cents', v_bora_raw, 'return_reserve_cents', v_return_reserve, 'rt_paid_cents', v_rt_paid,
      'outbound_distance_km', v_outbound_km, 'return_extra_km_charged', v_extra_km_over,
      'return_extra_fare_cents', v_extra_fare, 'return_overage_km_raw', v_overage_km_raw,
      'extra_stops_fee_cents', v_stops_fee, 'extra_stops_driver_cents', v_stops_drv,
      'stops_cash_cents', v_stops_cash,
      'plan_fixed_driver_earn_cents', v_plan_fixed_earn,
      'promo_credit_cents', v_promo,
      'fixed_fare_override_cents', v_fixed,
      'fixed_driver_earn_override_cents', v_fixed_drv,
      'agreed_fare_cents', v_ride.agreed_fare_cents,
      'agreed_driver_earn_cents', v_ride.agreed_driver_earn_cents,
      'ride_source', v_ride.source,
      'is_return_leg', v_ride.is_return_leg, 'prepaid', v_prepaid, 'rt_cash', v_rt_cash, 'payment_method', v_pm,
      'roundtrip_price_cents', v_rt_price,
      'settle_cents', v_settle,
      'distance_source', p_distance_source, 'subscription', v_sub,
      'tokens_applied_count', v_tokens_eff, 'fixed_price_km', v_price_km, 'fixed_price_on', v_fixed_on, 'tokens_discount_cents', v_tokens_discount_cents));

  UPDATE public.tvde_rides SET is_queued = false, status = 'motorista_a_caminho', updated_at = now()
   WHERE id = (SELECT r3.id FROM public.tvde_rides r3 WHERE r3.driver_id = v_uid AND r3.is_queued = true
               AND r3.status = 'motorista_atribuido' ORDER BY r3.created_at ASC LIMIT 1)
   RETURNING id INTO v_next;
  IF v_next IS NOT NULL THEN
    INSERT INTO public.tvde_ride_events (ride_id, status, actor, meta)
      VALUES (v_next, 'motorista_a_caminho', 'system', jsonb_build_object('queued_activation', true, 'after_ride_id', p_ride_id));
  END IF;

  RETURN v_ride;
END;
$function$
;

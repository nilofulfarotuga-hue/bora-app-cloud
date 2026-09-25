-- 2026-09-13 -- PLANO A MEDIDA (decisao do Danilo, 11/09/2026).
--
-- Cliente Vina Ca (vinanbabunanque@gmail.com, 938520793). O plano 'especial' de
-- 04/09 (8 corridas, 10 km incluidos, motorista 4,50 EUR fixos) nunca lhe serviu:
-- a corrida dela passa dos 10 km e o pedido cobrava-lhe o extra ao km
-- (CEIL(km - 10) x 1,00 EUR -- os "+2 EUR" de que ela se queixou). O plano
-- antigo fica cancelado por inteiro (assinatura inactiva; nao havia pedidos de
-- plano nem contadores dela).
--
-- Regra nova, SO para o user_id dela: corrida ate 15 km inclusive -> paga
-- 5,00 EUR fixos; acima de 15 km -> preco normal. O motorista ganha o normal
-- pela distancia real (base + km extra); a Bora absorve a diferenca. Sem
-- contadores, sem cupoes.
--
-- Mecanismo, o mais simples possivel: tabela tvde_client_fare_overrides (uma
-- linha por cliente) + um ajudante que devolve a tarifa fixa quando ha override
-- activo para a distancia. Entra no orcamento que a app mostra
-- (tvde_calculate_fare, chamada com a sessao da cliente), no pedido
-- (tvde_request_ride), na reserva (tvde_schedule_ride) e no fecho
-- (tvde_finish_ride, pela distancia final -- a autoritativa).

create table if not exists public.tvde_client_fare_overrides (
  client_id uuid primary key references auth.users(id) on delete cascade,
  fixed_fare_cents integer not null check (fixed_fare_cents >= 0),
  max_km numeric not null check (max_km > 0),
  active boolean not null default true,
  note text,
  created_by uuid,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
comment on table public.tvde_client_fare_overrides is
  'Preco fixo de corrida TVDE por cliente (plano a medida). Ate max_km o cliente paga fixed_fare_cents; acima, preco normal. O motorista ganha sempre o normal.';

alter table public.tvde_client_fare_overrides enable row level security;
revoke all on table public.tvde_client_fare_overrides from public, anon, authenticated;
grant select on table public.tvde_client_fare_overrides to authenticated;

do $$
begin
  if not exists (select 1 from pg_policies where schemaname = 'public'
                   and tablename = 'tvde_client_fare_overrides'
                   and policyname = 'tvde_client_fare_overrides_ve_o_seu') then
    create policy tvde_client_fare_overrides_ve_o_seu
      on public.tvde_client_fare_overrides
      for select to authenticated
      using (auth.uid() = client_id or public.is_admin());
  end if;
end $$;

-- Ajudante: NULL quando nao ha plano a medida para este cliente/distancia.
create or replace function public.tvde_client_fixed_fare_cents(p_client uuid, p_distance_km numeric)
 returns integer
 language sql
 stable
 security definer
 set search_path to 'public'
as $function$
  select o.fixed_fare_cents
    from public.tvde_client_fare_overrides o
   where o.client_id = p_client
     and o.active
     and coalesce(p_distance_km, 0) <= o.max_km
   limit 1;
$function$;
revoke all on function public.tvde_client_fixed_fare_cents(uuid, numeric) from public, anon, authenticated;
grant execute on function public.tvde_client_fixed_fare_cents(uuid, numeric) to service_role;

-- Orcamento: a app chama com a sessao da cliente, por isso auth.uid() e' ela.
-- Sem sessao (anon) ou com outro utilizador, devolve a tarifa normal de sempre.
CREATE OR REPLACE FUNCTION public.tvde_calculate_fare(p_distance_km numeric)
 RETURNS integer
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  SELECT COALESCE(
    public.tvde_client_fixed_fare_cents(auth.uid(), p_distance_km),
    (public.get_setting('tvde_base_fare_cents') #>> '{}')::int
      + GREATEST(0, CEIL(p_distance_km - (public.get_setting('tvde_base_distance_km') #>> '{}')::int))::int
        * (public.get_setting('tvde_extra_per_km_cents') #>> '{}')::int
  );
$function$;

CREATE OR REPLACE FUNCTION public.tvde_request_ride(p_origin_lat double precision, p_origin_lng double precision, p_origin_label text, p_dest_lat double precision, p_dest_lng double precision, p_dest_label text, p_est_distance_km numeric, p_payment_method text DEFAULT 'cash'::text, p_tokens_to_apply integer DEFAULT 0)
 RETURNS tvde_rides
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE v_uid UUID := auth.uid(); v_fare INTEGER; v_ride public.tvde_rides;
  v_cov JSONB; v_covered BOOLEAN; v_sub_id UUID; v_is_member BOOLEAN;
  v_d_base INT; v_d_perkm INT; v_extra_km INT; v_base_km INT; v_perkm_client INT;
  v_driver_normal INT; v_driver_earn INT; v_client_fare INT; v_bora_cut INT;
  v_tokens_discount_cents INT; v_max_discount_cents INT; v_token_value_x100 INT;
  v_plan_km NUMERIC; v_plan_extra_km INT; v_plan_driver_pct INT; v_plan_fixed_earn INT;
  v_fixed INT;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'not_authenticated'; END IF;
  IF p_payment_method NOT IN ('cash','card','mbway') THEN
    RAISE EXCEPTION 'invalid_payment_method: %', p_payment_method;
  END IF;
  IF p_payment_method <> 'cash'
     AND NOT COALESCE((public.get_setting('tvde_card_payments_enabled') #>> '{}')::boolean, false) THEN
    RAISE EXCEPTION 'card_payments_not_enabled';
  END IF;
  IF EXISTS (SELECT 1 FROM public.tvde_rides WHERE client_id = v_uid
             AND status IN ('solicitada','motorista_atribuido','motorista_a_caminho','motorista_chegou','em_andamento')) THEN
    RAISE EXCEPTION 'ride_in_progress'; END IF;

  v_base_km := (public.get_setting('tvde_base_distance_km') #>> '{}')::int;
  v_perkm_client := (public.get_setting('tvde_extra_per_km_cents') #>> '{}')::int;
  v_extra_km := GREATEST(0, CEIL(p_est_distance_km - v_base_km))::int;
  v_fare := public.tvde_calculate_fare(p_est_distance_km);
  v_d_base  := (public.get_setting('tvde_driver_base_cents')  #>> '{}')::int;
  v_d_perkm := (public.get_setting('tvde_driver_per_km_cents') #>> '{}')::int;
  v_driver_normal := v_d_base + v_extra_km * v_d_perkm;

  v_cov := public.tvde_preview_coverage(v_uid);
  v_covered := COALESCE((v_cov->>'covered')::boolean, false);
  v_sub_id := NULLIF(v_cov->>'subscription_id','')::uuid;
  SELECT EXISTS (SELECT 1 FROM public.tvde_subscriptions
    WHERE client_id = v_uid AND active = true AND now() BETWEEN starts_at AND ends_at)
    INTO v_is_member;

  IF v_covered THEN
    -- Km ja pagos no plano. NULL (plano antigo) -> cai na base, como era antes.
    SELECT km_included, driver_earn_cents INTO v_plan_km, v_plan_fixed_earn
      FROM public.tvde_subscriptions WHERE id = v_sub_id;
    v_plan_extra_km := GREATEST(0, CEIL(p_est_distance_km - COALESCE(v_plan_km, v_base_km)))::int;
    v_plan_driver_pct := COALESCE((public.get_setting('tvde_plan_driver_pct') #>> '{}')::int, 85);
    v_client_fare := v_plan_extra_km * v_perkm_client;
    -- Plano com ganho FIXO acordado (ex.: 4,50 EUR por corrida) manda sobre a percentagem.
    IF v_plan_fixed_earn IS NOT NULL THEN
      v_driver_earn := v_plan_fixed_earn;
    ELSE
      v_driver_earn := ROUND(v_driver_normal * v_plan_driver_pct / 100.0)::int;
    END IF;
    v_bora_cut    := v_client_fare - v_driver_earn;
  ELSIF v_is_member THEN
    v_client_fare := (public.get_setting('tvde_extra_ride_cents') #>> '{}')::int + v_extra_km * v_perkm_client;
    v_driver_earn := v_driver_normal;
    v_bora_cut    := v_client_fare - v_driver_normal;
  ELSE
    v_client_fare := v_fare;
    v_driver_earn := v_driver_normal;
    v_bora_cut    := v_fare - v_driver_normal;
  END IF;

  -- 2026-09-13: plano a medida (tvde_client_fare_overrides). Preco fixo ao
  -- cliente ate max_km; o motorista continua a ganhar o normal; a Bora absorve.
  IF NOT v_covered THEN
    v_fixed := public.tvde_client_fixed_fare_cents(v_uid, p_est_distance_km);
    IF v_fixed IS NOT NULL THEN
      v_client_fare := v_fixed;
      v_bora_cut    := v_client_fare - v_driver_earn;
    END IF;
  END IF;

  -- Valor e tecto SEMPRE das definicoes. NUNCA cravar numeros aqui.
  -- Decisao do Danilo (2026-08-13): 0,5 centimos por token, em todo o lado.
  IF p_tokens_to_apply > 0 AND v_client_fare > 0 THEN
    v_token_value_x100 := COALESCE((public.get_setting('token_value_cents_x100') #>> '{}')::int, 50);
    v_max_discount_cents := GREATEST(0, (v_client_fare
      * COALESCE((public.get_setting('token_payment_max_pct') #>> '{}')::int, 50)) / 100);
    v_tokens_discount_cents := LEAST((p_tokens_to_apply * v_token_value_x100) / 100, v_max_discount_cents);
    v_client_fare := v_client_fare - v_tokens_discount_cents;
    v_bora_cut := v_bora_cut - v_tokens_discount_cents;
  ELSE
    v_tokens_discount_cents := 0;
  END IF;

  INSERT INTO public.tvde_rides (
    client_id, origin_lat, origin_lng, origin_label, dest_lat, dest_lng, dest_label,
    est_distance_km, est_fare_cents, driver_earn_cents, bora_cut_cents,
    used_subscription_ride, subscription_id, payment_method, status,
    tokens_applied_count, tokens_applied_value_cents)
  VALUES (v_uid, p_origin_lat, p_origin_lng, p_origin_label, p_dest_lat, p_dest_lng, p_dest_label,
    p_est_distance_km, v_client_fare, v_driver_earn, v_bora_cut, v_covered, v_sub_id,
    p_payment_method, 'solicitada',
    CASE WHEN v_tokens_discount_cents > 0 THEN p_tokens_to_apply ELSE 0 END,
    v_tokens_discount_cents)
  RETURNING * INTO v_ride;
  INSERT INTO public.tvde_ride_events (ride_id, status, actor, meta)
    VALUES (v_ride.id, 'solicitada', 'client',
      jsonb_build_object('est_distance_km', p_est_distance_km, 'est_fare_cents', v_client_fare,
        'covered', v_covered, 'is_member', v_is_member, 'extra_km', v_extra_km,
        'plan_km_included', v_plan_km, 'plan_extra_km', v_plan_extra_km,
        'plan_fixed_driver_earn_cents', v_plan_fixed_earn,
        'fixed_fare_override_cents', v_fixed,
        'driver_earn_cents', v_driver_earn, 'payment_method', p_payment_method,
        'tokens_requested', p_tokens_to_apply, 'tokens_discount_cents', v_tokens_discount_cents));
  RETURN v_ride;
END;
$function$;

CREATE OR REPLACE FUNCTION public.tvde_schedule_ride(p_origin_lat double precision, p_origin_lng double precision, p_origin_label text, p_dest_lat double precision, p_dest_lng double precision, p_dest_label text, p_est_distance_km numeric, p_scheduled_at timestamp with time zone, p_payment_method text DEFAULT 'cash'::text, p_note text DEFAULT NULL::text)
 RETURNS tvde_rides
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_uid uuid := auth.uid(); v_ride public.tvde_rides;
  v_min int := COALESCE((public.get_setting('tvde_reservation_min_advance_minutes') #>> '{}')::int, 30);
  v_max int := COALESCE((public.get_setting('tvde_reservation_max_advance_days') #>> '{}')::int, 30);
  v_base_km int; v_perkm int; v_extra_km int;
  v_fare int; v_d_base int; v_d_perkm int; v_driver_earn int;
  v_online boolean;
  v_fixed int;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'not_authenticated'; END IF;
  IF NOT COALESCE((public.get_setting('tvde_reservation_enabled') #>> '{}')::boolean, false) THEN
    RAISE EXCEPTION 'reservations_disabled'; END IF;
  IF p_payment_method NOT IN ('cash','card','mbway') THEN
    RAISE EXCEPTION 'invalid_payment_method: %', p_payment_method; END IF;
  v_online := (p_payment_method <> 'cash');
  IF v_online AND NOT COALESCE((public.get_setting('tvde_card_payments_enabled') #>> '{}')::boolean, false) THEN
    RAISE EXCEPTION 'card_payments_not_enabled'; END IF;
  IF p_scheduled_at < now() + make_interval(mins => v_min) THEN RAISE EXCEPTION 'too_soon'; END IF;
  IF p_scheduled_at > now() + make_interval(days => v_max) THEN RAISE EXCEPTION 'too_far'; END IF;
  IF EXISTS (SELECT 1 FROM public.tvde_rides
              WHERE client_id = v_uid AND status = 'agendada'
                AND COALESCE(reservation_status,'') <> 'aguarda_pagamento'
                AND abs(extract(epoch FROM (scheduled_at - p_scheduled_at))) < 1800) THEN
    RAISE EXCEPTION 'reservation_overlap'; END IF;
  IF (SELECT count(*) FROM public.tvde_rides
       WHERE client_id = v_uid AND status = 'agendada' AND scheduled_at > now()) >= 5 THEN
    RAISE EXCEPTION 'too_many_reservations'; END IF;

  v_base_km := (public.get_setting('tvde_base_distance_km') #>> '{}')::int;
  v_perkm   := (public.get_setting('tvde_extra_per_km_cents') #>> '{}')::int;
  v_extra_km := GREATEST(0, CEIL(p_est_distance_km - v_base_km))::int;
  v_fare := public.tvde_calculate_fare(p_est_distance_km);
  v_d_base  := (public.get_setting('tvde_driver_base_cents')  #>> '{}')::int;
  v_d_perkm := (public.get_setting('tvde_driver_per_km_cents') #>> '{}')::int;
  v_driver_earn := v_d_base + v_extra_km * v_d_perkm;

  -- 2026-09-13: plano a medida -- preco fixo ao cliente ate max_km; motorista normal.
  v_fixed := public.tvde_client_fixed_fare_cents(v_uid, p_est_distance_km);
  IF v_fixed IS NOT NULL THEN v_fare := v_fixed; END IF;

  INSERT INTO public.tvde_rides (
    client_id, origin_lat, origin_lng, origin_label, dest_lat, dest_lng, dest_label,
    est_distance_km, est_fare_cents, driver_earn_cents, bora_cut_cents,
    payment_method, status, scheduled_at, reservation_status, customer_note, payment_status)
  VALUES (v_uid, p_origin_lat, p_origin_lng, p_origin_label, p_dest_lat, p_dest_lng, p_dest_label,
    p_est_distance_km, v_fare, v_driver_earn, v_fare - v_driver_earn,
    p_payment_method, 'agendada', p_scheduled_at,
    CASE WHEN v_online THEN 'aguarda_pagamento' ELSE 'a_procurar' END,
    p_note, CASE WHEN v_online THEN 'pendente' ELSE NULL END)
  RETURNING * INTO v_ride;

  INSERT INTO public.tvde_ride_events (ride_id, status, actor, meta)
  VALUES (v_ride.id, 'agendada', 'client',
    jsonb_build_object('scheduled_at', p_scheduled_at, 'est_fare_cents', v_fare,
                       'driver_earn_cents', v_driver_earn, 'payment_method', p_payment_method,
                       'fixed_fare_override_cents', v_fixed,
                       'aguarda_pagamento', v_online));

  -- em dinheiro comeca logo a procurar; online so depois de pagar
  IF NOT v_online THEN
    PERFORM public.notify_admin_urgent_push('tvde_reservation_new',
      'Nova RESERVA (dinheiro): ' || to_char(p_scheduled_at AT TIME ZONE 'Europe/Lisbon','DD/MM HH24:MI')
        || ' - ' || COALESCE(p_origin_label,'?') || ' -> ' || COALESCE(p_dest_label,'?')
        || ' (' || to_char(v_fare/100.0,'FM990.00') || ' EUR)',
      'tvde_ride', v_ride.id::text,
      jsonb_build_object('scheduled_at', p_scheduled_at, 'fare_cents', v_fare), '/admin/tvde/reservas');
    PERFORM public.tvde_reservation_offer_to_next(v_ride.id);
  END IF;

  SELECT * INTO v_ride FROM public.tvde_rides WHERE id = v_ride.id;
  RETURN v_ride;
END;
$function$;

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
BEGIN
  SELECT * INTO v_ride FROM public.tvde_rides WHERE id = p_ride_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'ride_not_found'; END IF;
  IF v_ride.driver_id <> v_uid THEN RAISE EXCEPTION 'not_ride_driver'; END IF;
  IF v_ride.status <> 'em_andamento' THEN RAISE EXCEPTION 'invalid_transition: %', v_ride.status; END IF;

  v_stops_fee := COALESCE(v_ride.extra_stops_fee_cents, 0);
  v_stops_drv := COALESCE(v_ride.extra_stops_driver_cents, 0);
  v_prepaid   := v_ride.roundtrip_credit_id IS NOT NULL;
  v_pm        := COALESCE(v_ride.payment_method, 'cash');

  SELECT COALESCE(SUM(fee_cents),0) INTO v_stops_cash
    FROM public.tvde_ride_stops
   WHERE ride_id = p_ride_id AND payment_intent_id IS NULL;

  v_fare := public.tvde_calculate_fare(p_final_distance_km);
  IF v_ride.is_return_leg THEN
    v_d_base := (public.get_setting('tvde_roundtrip_return_driver_cents') #>> '{}')::int;
  ELSE
    v_d_base := (public.get_setting('tvde_driver_base_cents') #>> '{}')::int;
  END IF;
  v_d_perkm := (public.get_setting('tvde_driver_per_km_cents') #>> '{}')::int;
  v_extra_km := GREATEST(0, CEIL(p_final_distance_km - (public.get_setting('tvde_base_distance_km') #>> '{}')::int))::int;
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
      v_fare     := v_stops_fee;                      -- receita ja reconhecida na ida
      v_bora_cut := v_stops_fee - v_stops_drv;
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
    v_fixed := public.tvde_client_fixed_fare_cents(v_ride.client_id, p_final_distance_km);
    IF v_fixed IS NOT NULL THEN
      v_fare := v_fixed;
    END IF;
    v_fare        := v_fare + v_stops_fee;
    v_driver_earn := v_driver_earn + v_stops_drv;
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
  IF p_tokens_to_apply > 0 AND v_fare > 0 AND NOT v_prepaid THEN
    v_token_value_x100 := COALESCE((public.get_setting('token_value_cents_x100') #>> '{}')::int, 50);
    v_max_discount_cents := GREATEST(0, (v_fare
      * COALESCE((public.get_setting('token_payment_max_pct') #>> '{}')::int, 50)) / 100);
    v_tokens_discount_cents := LEAST((p_tokens_to_apply * v_token_value_x100) / 100, v_max_discount_cents);
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
    updated_at = now()
   WHERE id = p_ride_id RETURNING * INTO v_ride;

  IF v_prepaid AND NOT COALESCE(v_ride.is_return_leg, false) THEN
    SELECT (payment_intent_id IS NULL), paid_cents INTO v_rt_cash, v_rt_price
      FROM public.tvde_roundtrip_credits WHERE id = v_ride.roundtrip_credit_id;
  END IF;

  -- === LIQUIDACAO DO SALDO DO MOTORISTA ===
  IF v_pm = 'cash' AND NOT v_prepaid AND NOT v_covered THEN
    v_settle := v_bora_raw;
  ELSIF v_prepaid AND COALESCE(v_rt_cash, false) AND NOT COALESCE(v_ride.is_return_leg, false) THEN
    v_settle := (COALESCE(v_rt_price, (public.get_setting('tvde_roundtrip_price_cents') #>> '{}')::int) + v_stops_cash) - v_driver_earn;
  ELSE
    v_settle := v_stops_cash - v_driver_earn;
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
      'extra_stops_fee_cents', v_stops_fee, 'extra_stops_driver_cents', v_stops_drv,
      'stops_cash_cents', v_stops_cash,
      'plan_fixed_driver_earn_cents', v_plan_fixed_earn,
      'promo_credit_cents', v_promo,
      'fixed_fare_override_cents', v_fixed,
      'is_return_leg', v_ride.is_return_leg, 'prepaid', v_prepaid, 'rt_cash', v_rt_cash, 'payment_method', v_pm,
      'roundtrip_price_cents', v_rt_price,
      'settle_cents', v_settle,
      'distance_source', p_distance_source, 'subscription', v_sub,
      'tokens_applied_count', p_tokens_to_apply, 'tokens_discount_cents', v_tokens_discount_cents));

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
$function$;

-- Dados: o plano antigo da Vina fica cancelado por inteiro e entra o plano a medida.
update public.tvde_subscriptions
   set active = false, ends_at = least(ends_at, now())
 where id = 'a20782f7-225e-4043-af1f-5296f63aa963'
   and client_id = 'dea9d68b-c805-4cb8-a2c4-560c0b526b36';

insert into public.tvde_client_fare_overrides (client_id, fixed_fare_cents, max_km, active, note, created_by)
values ('dea9d68b-c805-4cb8-a2c4-560c0b526b36', 500, 15, true,
        'Plano a medida Vina Ca (decisao do Danilo 11/09/2026): 5,00 EUR fixos ate 15 km inclusive; acima, preco normal; o motorista ganha o normal pela distancia real.',
        'c9fccf85-03ee-4efc-83bf-613f211a78ff')
on conflict (client_id) do update
   set fixed_fare_cents = excluded.fixed_fare_cents, max_km = excluded.max_km,
       active = true, note = excluded.note, updated_at = now();

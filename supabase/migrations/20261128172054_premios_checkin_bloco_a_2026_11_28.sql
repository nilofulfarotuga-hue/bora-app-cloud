-- ============================================================================
-- ⚠️ PROPOSTA — ISTO MEXE EM DINHEIRO (prémios do check-in). NÃO APLICADA por esta sessão.
-- Missão premios-checkin-em-todo-lado-2026-11-26, BLOCO A no servidor (parou a 26/11 porque a
-- bora-tranca e o classificador recusaram a migração no PC). Autorização do Danilo: 26/11/2026 13:00
-- (caso Divan: o prémio de 2 h de limpeza não foi descontado). Quem aplica é a Claude.ai, por MCP.
-- Página do livro: prompt-premios-checkin-2026-11-26.
--
-- O que faz (os 8 pontos do desenho):
--   1. colunas checkin_premio_cents e checkin_vale_id em cleaning_bookings e carwash_bookings
--      (o prémio deixa de usar recurring_discount_cents);
--   2. p_checkin_vale_id opcional em create_cleaning_booking e create_carwash_booking: valida dono, tipo,
--      por_usar e validade; prémio = horas do prémio (2 h) × cleaning_hourly_cents (Standard; Profunda e
--      Pós-obras pagam a diferença) ou o preço da lavagem só por fora, limitado ao total da 1.ª visita;
--      total_cents = total − prémio; ganho da profissional/lavador igual ao das horas todas;
--      bora_fee_cents = taxa normal − prémio (o acerto semanal já paga a diferença); o vale fica usado com
--      o id da marcação; resto 0 em cartão/MB Way → método 'premio'; resto de 1 a 49 cêntimos só em dinheiro;
--   3. client_checkin_premio_marcar_limpeza/lavagem passam a chamar o create com o vale;
--   4. os gatilhos que devolvem o vale ao cancelar valem para qualquer meio de pagamento;
--   5. gatilho BEFORE INSERT: a série seguinte vai em dinheiro quando a anterior foi prémio
--      (senão generate_recurring_bookings parte na guarda do pagamento 'premio');
--   6. guarda de escrita direta nos campos novos (e no dinheiro de uma marcação com prémio);
--   7. RPC client_checkin_premio_servico_para_usar para a app mostrar o banner "Usar o meu prémio";
--   8. reserva do Divan ffa77ebf: para os campos novos SEM mudar valores, com backup.
--
-- As funções saem do texto mais recente do repo (create_cleaning_booking de 20261119200000 — equipa — e
-- create_carwash_booking de 20260827103000), já com o #60 (planos) e o telemóvel obrigatório
-- (20261128100000, por gatilho: não muda estas funções). A assinatura muda (+1 parâmetro com valor por
-- defeito): larga-se a antiga (DROP da assinatura velha, como em 20261119200000) para não haver duas
-- versões ambíguas; a app antiga, que não manda p_checkin_vale_id, continua a funcionar.
-- Funções internas fechadas a PUBLIC, anon e authenticated (o Supabase dá EXECUTE a authenticated por defeito).
-- Idempotente (if not exists / create or replace / drop if exists da assinatura velha).
-- ============================================================================

-- ── 1. Colunas ───────────────────────────────────────────────────────────────
ALTER TABLE public.cleaning_bookings
  ADD COLUMN IF NOT EXISTS checkin_premio_cents integer NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS checkin_vale_id uuid REFERENCES public.checkin_premios_vales(id);
ALTER TABLE public.carwash_bookings
  ADD COLUMN IF NOT EXISTS checkin_premio_cents integer NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS checkin_vale_id uuid REFERENCES public.checkin_premios_vales(id);
DO $c$ BEGIN
  ALTER TABLE public.cleaning_bookings ADD CONSTRAINT cleaning_bookings_checkin_premio_chk CHECK (checkin_premio_cents >= 0);
EXCEPTION WHEN duplicate_object THEN NULL; END $c$;
DO $c$ BEGIN
  ALTER TABLE public.carwash_bookings ADD CONSTRAINT carwash_bookings_checkin_premio_chk CHECK (checkin_premio_cents >= 0);
EXCEPTION WHEN duplicate_object THEN NULL; END $c$;
CREATE INDEX IF NOT EXISTS cleaning_bookings_checkin_vale_idx ON public.cleaning_bookings (checkin_vale_id) WHERE checkin_vale_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS carwash_bookings_checkin_vale_idx ON public.carwash_bookings (checkin_vale_id) WHERE checkin_vale_id IS NOT NULL;
COMMENT ON COLUMN public.cleaning_bookings.checkin_premio_cents IS
  'Prémio do check-in descontado ao cliente nesta marcação (a Bora paga; a profissional ganha as horas todas). 28/11/2026.';
COMMENT ON COLUMN public.cleaning_bookings.checkin_vale_id IS 'Vale do check-in usado nesta marcação (checkin_premios_vales).';
COMMENT ON COLUMN public.carwash_bookings.checkin_premio_cents IS
  'Prémio do check-in descontado ao cliente nesta lavagem (a Bora paga; o lavador ganha o mesmo). 28/11/2026.';
COMMENT ON COLUMN public.carwash_bookings.checkin_vale_id IS 'Vale do check-in usado nesta lavagem (checkin_premios_vales).';

-- ── 2a. create_cleaning_booking com p_checkin_vale_id (texto de 20261119200000 + o vale) ──
DROP FUNCTION IF EXISTS public.create_cleaning_booking(text,text,text,integer,timestamp with time zone,text,text,text,text,text,text,double precision,double precision,text,uuid,text,integer);
CREATE OR REPLACE FUNCTION public.create_cleaning_booking(p_cleaning_type text, p_pricing_mode text, p_home_size text, p_hours integer, p_scheduled_at timestamp with time zone, p_recurrence text, p_products_by text, p_payment_method text, p_address_street text, p_address_city text, p_address_postal text, p_lat double precision, p_lng double precision, p_notes text DEFAULT ''::text, p_requested_cleaner_id uuid DEFAULT NULL::uuid, p_idempotency_key text DEFAULT NULL::text, p_team_size integer DEFAULT 1, p_checkin_vale_id uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  v_quote jsonb;
  v_lead int := public._cleaning_setting_int('cleaning_min_lead_hours', 12);
  v_id uuid;
  v_group uuid := NULL;
  v_key text := NULLIF(btrim(COALESCE(p_idempotency_key, '')), '');
  v_ja uuid;
  v_assinatura text;
  v_n int := COALESCE(p_team_size, 1);
  v_team uuid := NULL;
  v_share jsonb;
  v_s int;
  v_sis uuid;
  v_sisters uuid[] := '{}';
  -- 28/11/2026 prémio do check-in na marcação normal
  v_vale checkin_premios_vales;
  v_premio int := 0;
  v_premio_horas int := 0;
  v_resto int := 0;
  v_m jsonb;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'not_authenticated' USING ERRCODE = '42501';
  END IF;

  IF v_key IS NOT NULL THEN
    SELECT b.id INTO v_ja FROM cleaning_bookings b
     WHERE b.client_user_id = v_uid AND b.idempotency_key = v_key
     LIMIT 1;
    IF v_ja IS NOT NULL THEN
      RETURN (SELECT to_jsonb(b) FROM cleaning_bookings b WHERE b.id = v_ja);
    END IF;
  END IF;

  v_assinatura := v_uid::text || '|' || COALESCE(v_key, '')
    || '|' || COALESCE(p_cleaning_type,'') || '|' || COALESCE(p_pricing_mode,'')
    || '|' || COALESCE(p_home_size,'')     || '|' || COALESCE(p_hours::text,'')
    || '|' || COALESCE(p_scheduled_at::text,'')
    || '|' || COALESCE(p_address_street,'') || '|' || COALESCE(p_address_postal,'')
    || '|' || v_n::text;
  PERFORM pg_advisory_xact_lock(hashtextextended(v_assinatura, 0));

  IF v_key IS NOT NULL THEN
    SELECT b.id INTO v_ja FROM cleaning_bookings b
     WHERE b.client_user_id = v_uid AND b.idempotency_key = v_key
     LIMIT 1;
    IF v_ja IS NOT NULL THEN
      RETURN (SELECT to_jsonb(b) FROM cleaning_bookings b WHERE b.id = v_ja);
    END IF;
  END IF;

  IF v_key IS NULL THEN
    SELECT b.id INTO v_ja FROM cleaning_bookings b
     WHERE b.client_user_id = v_uid
       AND b.created_at > now() - interval '15 minutes'
       AND b.status NOT IN ('cancelled_client','cancelled_cleaner')
       AND b.cleaning_type   IS NOT DISTINCT FROM p_cleaning_type
       AND b.pricing_mode    IS NOT DISTINCT FROM p_pricing_mode
       AND b.home_size       IS NOT DISTINCT FROM p_home_size
       AND b.scheduled_at    IS NOT DISTINCT FROM p_scheduled_at
       AND b.recurrence      IS NOT DISTINCT FROM p_recurrence
       AND b.products_by     IS NOT DISTINCT FROM p_products_by
       AND b.payment_method  IS NOT DISTINCT FROM p_payment_method
       AND b.address_street  IS NOT DISTINCT FROM COALESCE(p_address_street,'')
       AND b.address_postal  IS NOT DISTINCT FROM COALESCE(p_address_postal,'')
       AND b.requested_cleaner_id IS NOT DISTINCT FROM p_requested_cleaner_id
       AND b.team_slot = 1 AND b.team_size = v_n
     ORDER BY b.created_at DESC
     LIMIT 1;
    IF v_ja IS NOT NULL THEN
      RETURN (SELECT to_jsonb(b) FROM cleaning_bookings b WHERE b.id = v_ja);
    END IF;
  END IF;

  IF NOT public._cleaning_setting_bool('cleaning_enabled', true) THEN
    RAISE EXCEPTION 'cleaning_disabled';
  END IF;
  IF p_scheduled_at < now() + make_interval(hours => v_lead) THEN
    RAISE EXCEPTION 'lead_time_too_short (min % h)', v_lead;
  END IF;
  IF p_payment_method NOT IN ('card','mbway','cash') THEN
    RAISE EXCEPTION 'invalid_payment_method';
  END IF;
  IF p_payment_method IN ('card','mbway')
     AND NOT public._cleaning_setting_bool('cleaning_stripe_enabled', false) THEN
    RAISE EXCEPTION 'card_mbway_not_yet_enabled';
  END IF;
  IF p_requested_cleaner_id IS NOT NULL THEN
    IF NOT EXISTS (SELECT 1 FROM cleaners
                   WHERE id = p_requested_cleaner_id
                     AND approval_status = 'approved' AND is_active) THEN
      RAISE EXCEPTION 'cleaner_not_available';
    END IF;
  END IF;

  -- 28/11/2026 prémio do check-in (caso Divan): o vale valida-se no servidor (dono, tipo, por usar, validade).
  IF p_checkin_vale_id IS NOT NULL THEN
    SELECT * INTO v_vale FROM checkin_premios_vales
     WHERE id = p_checkin_vale_id AND user_id = v_uid FOR UPDATE;
    IF v_vale.id IS NULL THEN RAISE EXCEPTION 'checkin_premio_nao_encontrado'; END IF;
    IF v_vale.tipo <> 'servico' OR NOT ('limpeza' = ANY (COALESCE(v_vale.opcoes, '{}'))) THEN
      RAISE EXCEPTION 'checkin_premio_nao_e_limpeza';
    END IF;
    IF v_vale.estado <> 'por_usar' THEN RAISE EXCEPTION 'checkin_premio_estado: %', v_vale.estado; END IF;
    IF v_vale.valido_ate IS NULL OR v_vale.valido_ate <= now() THEN RAISE EXCEPTION 'checkin_premio_expirado'; END IF;
    SELECT x INTO v_m FROM jsonb_array_elements(public._checkin_marcos_config()) x
     WHERE x ->> 'chave' = v_vale.marco_chave LIMIT 1;
    v_premio_horas := LEAST(GREATEST(COALESCE((v_m ->> 'limpeza_horas')::int, 2), 1), 12);
  END IF;

  -- 19/11/2026 equipa: a conta vem da cleaning_quote_team (com 1 profissional = cleaning_quote_at).
  v_quote := public.cleaning_quote_team(p_cleaning_type, p_pricing_mode, p_home_size,
                                   p_hours, p_recurrence, p_products_by, p_lat, p_lng, v_n);
  -- 19/11/2026: limpeza só até cleaning_max_distance_km do centro da Guarda
  IF COALESCE((v_quote ->> 'out_of_area')::boolean, false) THEN
    RAISE EXCEPTION 'fora_da_area_limpeza: ainda não fazemos limpezas a mais de % km da Guarda', v_quote ->> 'max_distance_km';
  END IF;

  -- 28/11/2026 prémio: horas do prémio × preço/hora Standard (Profunda e Pós-obras pagam a diferença),
  -- nunca mais do que o total desta 1.ª visita. O resto de 1 a 49 cêntimos não passa no cartão/MB Way.
  IF v_vale.id IS NOT NULL THEN
    v_premio := LEAST(v_premio_horas * public._cleaning_setting_int('cleaning_hourly_cents', 1200),
                      (v_quote ->> 'total_cents')::int);
    v_resto := (v_quote ->> 'total_cents')::int - v_premio;
    IF v_resto > 0 AND v_resto < 50 AND p_payment_method IN ('card','mbway') THEN
      RAISE EXCEPTION 'checkin_premio_resto_so_dinheiro: o resto (% cêntimos) só se paga em dinheiro', v_resto;
    END IF;
  END IF;

  IF p_recurrence IN ('weekly','biweekly') THEN
    v_group := gen_random_uuid();
  END IF;
  IF v_n > 1 THEN
    v_team := gen_random_uuid();
  END IF;
  v_share := v_quote -> 'shares' -> 0;

  INSERT INTO cleaning_bookings (
    client_user_id, requested_cleaner_id, recurrence_group_id, recurrence,
    cleaning_type, pricing_mode, home_size, hours, scheduled_at, duration_min,
    address_street, address_city, address_postal, lat, lng, notes, products_by,
    payment_method, payment_status,
    base_cents, type_surcharge_cents, recurring_discount_cents, products_fee_cents,
    total_cents, cleaner_earnings_cents, bora_fee_cents,
    travel_fee_cents, travel_distance_km,
    idempotency_key,
    team_group_id, team_size, team_slot, team_total_cents, share_cents,
    checkin_premio_cents, checkin_vale_id
  ) VALUES (
    v_uid, p_requested_cleaner_id, v_group, p_recurrence,
    p_cleaning_type, p_pricing_mode, p_home_size,
    CASE WHEN p_pricing_mode = 'hourly' THEN p_hours END,
    p_scheduled_at, (v_quote ->> 'duration_min')::int,
    COALESCE(p_address_street,''), COALESCE(p_address_city,''), COALESCE(p_address_postal,''),
    p_lat, p_lng, COALESCE(p_notes,''), p_products_by,
    p_payment_method, 'unpaid',
    (v_quote ->> 'base_cents')::int, (v_quote ->> 'type_surcharge_cents')::int,
    (v_quote ->> 'recurring_discount_cents')::int, (v_share ->> 'products_cents')::int,
    -- prémio: o cliente paga o total menos o prémio; a profissional ganha as horas todas;
    -- a Bora fica com a taxa normal menos o prémio (o acerto semanal paga a diferença)
    (v_quote ->> 'total_cents')::int - v_premio, (v_share ->> 'cleaner_earnings_cents')::int,
    (v_share ->> 'bora_fee_cents')::int - v_premio,
    COALESCE((v_quote ->> 'travel_fee_cents')::int, 0), NULLIF(v_quote ->> 'travel_distance_km', '')::numeric,
    v_key,
    v_team, v_n, 1, (v_quote ->> 'total_cents')::int - v_premio,
    GREATEST((v_share ->> 'share_cents')::int - v_premio, 0),
    v_premio, v_vale.id
  ) RETURNING id INTO v_id;

  -- Equipa: as vagas 2..N (irmãs). total_cents = 0 (o cliente paga tudo na vaga 1);
  -- cada uma guarda a parte da sua profissional.
  IF v_n > 1 THEN
    FOR v_s IN 2..v_n LOOP
      v_share := v_quote -> 'shares' -> (v_s - 1);
      INSERT INTO cleaning_bookings (
        client_user_id, requested_cleaner_id, recurrence_group_id, recurrence,
        cleaning_type, pricing_mode, home_size, hours, scheduled_at, duration_min,
        address_street, address_city, address_postal, lat, lng, notes, products_by,
        payment_method, payment_status,
        base_cents, type_surcharge_cents, recurring_discount_cents, products_fee_cents,
        total_cents, cleaner_earnings_cents, bora_fee_cents,
        travel_fee_cents, travel_distance_km,
        team_group_id, team_size, team_slot, team_total_cents, share_cents
      ) VALUES (
        v_uid, NULL, v_group, p_recurrence,
        p_cleaning_type, p_pricing_mode, p_home_size,
        CASE WHEN p_pricing_mode = 'hourly' THEN p_hours END,
        p_scheduled_at, (v_quote ->> 'duration_min')::int,
        COALESCE(p_address_street,''), COALESCE(p_address_city,''), COALESCE(p_address_postal,''),
        p_lat, p_lng, COALESCE(p_notes,''), p_products_by,
        p_payment_method, 'unpaid',
        (v_quote ->> 'base_cents')::int, (v_quote ->> 'type_surcharge_cents')::int,
        (v_quote ->> 'recurring_discount_cents')::int, (v_share ->> 'products_cents')::int,
        0, (v_share ->> 'cleaner_earnings_cents')::int, (v_share ->> 'bora_fee_cents')::int,
        COALESCE((v_quote ->> 'travel_fee_cents')::int, 0), NULLIF(v_quote ->> 'travel_distance_km', '')::numeric,
        v_team, v_n, v_s, (v_quote ->> 'total_cents')::int, (v_share ->> 'share_cents')::int
      ) RETURNING id INTO v_sis;
      v_sisters := v_sisters || v_sis;
    END LOOP;
  END IF;

  -- Cada vaga toca à parte (a principal primeiro: é a que recebe a profissional pedida).
  PERFORM public._cleaning_next_offer(v_id);
  FOREACH v_sis IN ARRAY v_sisters LOOP
    PERFORM public._cleaning_next_offer(v_sis);
  END LOOP;

  -- 28/11/2026 prémio: o vale fica usado com o id da marcação ANTES de o pagamento passar a 'premio'
  -- (a guarda trg_checkin_premio_guarda_pagamento exige-o). Resto 0 no cartão/MB Way → pago pelo prémio:
  -- a passagem a 'held' dispara a 1.ª oferta (trg_cleaning_paid_offer) e as irmãs da equipa (trg_cleaning_team_paid).
  IF v_vale.id IS NOT NULL THEN
    UPDATE checkin_premios_vales
       SET estado = 'usado', usado_em = now(), opcao = 'limpeza', marcacao_tipo = 'limpeza', marcacao_id = v_id,
           custo_cents = round(v_premio * (100 - public._cleaning_setting_int('cleaning_bora_pct', 15)) / 100.0)::int,
           valor_cents = v_premio, atualizado_em = now()
     WHERE id = v_vale.id;
    IF v_resto = 0 AND p_payment_method IN ('card','mbway') THEN
      UPDATE cleaning_bookings SET payment_method = 'premio', payment_status = 'held'
       WHERE id = v_id AND payment_status = 'unpaid';
    END IF;
  END IF;

  -- 19/11/2026: avisa o cliente da taxa de deslocação (morada longe do centro da Guarda)
  IF COALESCE((v_quote ->> 'travel_fee_cents')::int, 0) > 0 THEN
    BEGIN
      PERFORM public._cleaning_notify_user(v_uid, 'cleaning_travel_fee', 'Taxa de deslocação',
        'A tua morada fica a ' || replace((v_quote ->> 'travel_distance_km'), '.', ',') || ' km de estrada da Guarda: a limpeza inclui '
        || to_char(((v_quote ->> 'travel_fee_cents')::int * v_n) / 100.0, 'FM990D00') || ' € de deslocação'
        || CASE WHEN v_n > 1 THEN ' (' || v_n || ' profissionais)' ELSE '' END || '. Total: '
        || to_char(((v_quote ->> 'total_cents')::int) / 100.0, 'FM990D00') || ' €.',
        v_id::text);
    EXCEPTION WHEN OTHERS THEN
      RAISE NOTICE 'create_cleaning_booking: aviso da taxa falhou (%)', sqlerrm;
    END;
  END IF;

  RETURN (SELECT to_jsonb(b) FROM cleaning_bookings b WHERE b.id = v_id);

EXCEPTION
  WHEN unique_violation THEN
    SELECT b.id INTO v_ja FROM cleaning_bookings b
     WHERE b.client_user_id = v_uid AND b.idempotency_key = v_key
     LIMIT 1;
    IF v_ja IS NOT NULL THEN
      RETURN (SELECT to_jsonb(b) FROM cleaning_bookings b WHERE b.id = v_ja);
    END IF;
    RAISE;
END $function$;

GRANT EXECUTE ON FUNCTION public.create_cleaning_booking(text,text,text,integer,timestamp with time zone,text,text,text,text,text,text,double precision,double precision,text,uuid,text,integer,uuid) TO authenticated, service_role;
REVOKE EXECUTE ON FUNCTION public.create_cleaning_booking(text,text,text,integer,timestamp with time zone,text,text,text,text,text,text,double precision,double precision,text,uuid,text,integer,uuid) FROM PUBLIC, anon;

-- ── 2b. create_carwash_booking com p_checkin_vale_id (texto de 20260827103000 + o vale) ──
DROP FUNCTION IF EXISTS public.create_carwash_booking(text,text,text,text,timestamptz,text,text,text,double precision,double precision,text,text,text,text,text,jsonb,uuid);
CREATE OR REPLACE FUNCTION public.create_carwash_booking(p_service_type text, p_plate text, p_client_phone text, p_when_mode text, p_scheduled_at timestamp with time zone, p_address_street text, p_address_city text, p_address_postal text, p_lat double precision, p_lng double precision, p_payment_method text, p_car_make_model text DEFAULT ''::text, p_car_color text DEFAULT ''::text, p_pickup_notes text DEFAULT ''::text, p_notes text DEFAULT ''::text, p_photos_client jsonb DEFAULT '[]'::jsonb, p_requested_washer_id uuid DEFAULT NULL::uuid, p_checkin_vale_id uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  v_quote jsonb;
  v_id uuid;
  v_when timestamptz;
  v_radius numeric := public._carwash_setting_num('carwash_service_radius_km', 8);
  v_blat double precision := public._carwash_setting_num('carwash_base_lat', 40.5373);
  v_blng double precision := public._carwash_setting_num('carwash_base_lng', -7.2676);
  v_dist double precision;
  -- 28/11/2026 prémio do check-in na marcação normal
  v_vale checkin_premios_vales;
  v_premio int := 0;
  v_resto int := 0;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'not_authenticated' USING ERRCODE = '42501';
  END IF;

  IF NOT public._carwash_setting_bool('carwash_enabled', true) THEN
    RAISE EXCEPTION 'carwash_disabled';
  END IF;

  IF p_when_mode NOT IN ('now','later') THEN RAISE EXCEPTION 'invalid_when_mode'; END IF;
  IF p_payment_method NOT IN ('card','mbway','cash') THEN RAISE EXCEPTION 'invalid_payment_method'; END IF;
  IF p_payment_method IN ('card','mbway')
     AND NOT public._carwash_setting_bool('carwash_stripe_enabled', true) THEN
    RAISE EXCEPTION 'card_mbway_not_enabled';
  END IF;
  IF COALESCE(trim(p_plate),'') = '' THEN RAISE EXCEPTION 'plate_required'; END IF;
  IF COALESCE(trim(p_client_phone),'') = '' THEN RAISE EXCEPTION 'phone_required'; END IF;

  v_when := CASE WHEN p_when_mode = 'now' THEN now() ELSE p_scheduled_at END;
  IF v_when IS NULL THEN RAISE EXCEPTION 'scheduled_at_required'; END IF;
  IF p_when_mode = 'later' AND v_when < now() - interval '5 minutes' THEN
    RAISE EXCEPTION 'scheduled_in_the_past';
  END IF;

  IF p_lat IS NOT NULL AND p_lng IS NOT NULL THEN
    v_dist := public._carwash_distance_km(v_blat, v_blng, p_lat, p_lng);
    IF v_dist > v_radius THEN
      RAISE EXCEPTION 'out_of_service_area (%.1f km)', v_dist;
    END IF;
  END IF;

  IF p_requested_washer_id IS NOT NULL THEN
    IF NOT EXISTS (SELECT 1 FROM washers WHERE id = p_requested_washer_id
                     AND approval_status='approved' AND is_active AND NOT is_banned) THEN
      RAISE EXCEPTION 'washer_not_available';
    END IF;
  END IF;

  v_quote := public.carwash_quote(p_service_type);

  -- 28/11/2026 prémio do check-in: vale o preço da lavagem SÓ POR FORA ('exterior'); interior/completa
  -- pagam a diferença. Nunca mais do que o total desta lavagem. Resto de 1 a 49 cêntimos só em dinheiro.
  IF p_checkin_vale_id IS NOT NULL THEN
    SELECT * INTO v_vale FROM checkin_premios_vales
     WHERE id = p_checkin_vale_id AND user_id = v_uid FOR UPDATE;
    IF v_vale.id IS NULL THEN RAISE EXCEPTION 'checkin_premio_nao_encontrado'; END IF;
    IF v_vale.tipo <> 'servico' OR NOT ('lavagem' = ANY (COALESCE(v_vale.opcoes, '{}'))) THEN
      RAISE EXCEPTION 'checkin_premio_nao_e_lavagem';
    END IF;
    IF v_vale.estado <> 'por_usar' THEN RAISE EXCEPTION 'checkin_premio_estado: %', v_vale.estado; END IF;
    IF v_vale.valido_ate IS NULL OR v_vale.valido_ate <= now() THEN RAISE EXCEPTION 'checkin_premio_expirado'; END IF;
    v_premio := LEAST((public.carwash_quote('exterior') ->> 'total_cents')::int, (v_quote ->> 'total_cents')::int);
    v_resto := (v_quote ->> 'total_cents')::int - v_premio;
    IF v_resto > 0 AND v_resto < 50 AND p_payment_method IN ('card','mbway') THEN
      RAISE EXCEPTION 'checkin_premio_resto_so_dinheiro: o resto (% cêntimos) só se paga em dinheiro', v_resto;
    END IF;
  END IF;

  INSERT INTO carwash_bookings (
    client_user_id, requested_washer_id, service_type, plate, car_make_model, car_color,
    pickup_notes, client_phone, when_mode, scheduled_at, duration_min,
    address_street, address_city, address_postal, lat, lng, notes,
    payment_method, payment_status, photos_client,
    base_cents, total_cents, washer_earnings_cents, bora_fee_cents,
    checkin_premio_cents, checkin_vale_id
  ) VALUES (
    v_uid, p_requested_washer_id, p_service_type, upper(trim(p_plate)),
    COALESCE(p_car_make_model,''), COALESCE(p_car_color,''),
    COALESCE(p_pickup_notes,''), trim(p_client_phone), p_when_mode, v_when,
    (v_quote ->> 'duration_min')::int,
    COALESCE(p_address_street,''), COALESCE(p_address_city,''), COALESCE(p_address_postal,''),
    p_lat, p_lng, COALESCE(p_notes,''),
    p_payment_method, 'unpaid', COALESCE(p_photos_client,'[]'::jsonb),
    -- prémio: o cliente paga o total menos o prémio; o lavador ganha o mesmo; a Bora fica com a taxa menos o prémio
    (v_quote ->> 'base_cents')::int, (v_quote ->> 'total_cents')::int - v_premio,
    (v_quote ->> 'washer_earnings_cents')::int, (v_quote ->> 'bora_fee_cents')::int - v_premio,
    v_premio, v_vale.id
  ) RETURNING id INTO v_id;

  PERFORM public._carwash_notify_admin(
    'Nova Lavagem Auto',
    'Pedido novo (' || upper(trim(p_plate)) || ') - ' ||
    ((v_quote ->> 'total_cents')::int / 100.0)::numeric(10,2) || ' EUR, ' ||
    CASE p_when_mode WHEN 'now' THEN 'para agora' ELSE 'agendado' END || '.');

  -- 28/11/2026 prémio: vale usado com o id da marcação antes de o pagamento passar a 'premio'.
  IF v_vale.id IS NOT NULL THEN
    UPDATE checkin_premios_vales
       SET estado = 'usado', usado_em = now(), opcao = 'lavagem', marcacao_tipo = 'lavagem', marcacao_id = v_id,
           custo_cents = LEAST((v_quote ->> 'washer_earnings_cents')::int, v_premio),
           valor_cents = v_premio, atualizado_em = now()
     WHERE id = v_vale.id;
    IF v_resto = 0 AND p_payment_method IN ('card','mbway') THEN
      UPDATE carwash_bookings SET payment_method = 'premio', payment_status = 'held'
       WHERE id = v_id AND payment_status = 'unpaid';
    END IF;
  END IF;

  PERFORM public._carwash_next_offer(v_id);

  RETURN (SELECT to_jsonb(b) FROM carwash_bookings b WHERE b.id = v_id);
END $function$;

GRANT EXECUTE ON FUNCTION public.create_carwash_booking(text,text,text,text,timestamptz,text,text,text,double precision,double precision,text,text,text,text,text,jsonb,uuid,uuid) TO authenticated, service_role;
REVOKE EXECUTE ON FUNCTION public.create_carwash_booking(text,text,text,text,timestamptz,text,text,text,double precision,double precision,text,text,text,text,text,jsonb,uuid,uuid) FROM PUBLIC, anon;

-- ── 3. "Os meus prémios › Usar" passa pelo mesmo caminho (create com o vale) ──
-- Assinaturas iguais às de 20261021061215 (a app não muda). A conta e o vale ficam no create.
CREATE OR REPLACE FUNCTION public.client_checkin_premio_marcar_limpeza(
  p_vale_id uuid, p_scheduled_at timestamptz,
  p_address_street text, p_address_city text, p_address_postal text,
  p_lat double precision, p_lng double precision, p_notes text DEFAULT '')
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_uid   uuid := auth.uid();
  v       public.checkin_premios_vales;
  m       jsonb;
  v_horas integer;
  v_b     jsonb;
  v_id    uuid;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'not_authenticated' USING ERRCODE = '42501'; END IF;
  SELECT * INTO v FROM public.checkin_premios_vales WHERE id = p_vale_id AND user_id = v_uid;
  IF v.id IS NULL THEN RAISE EXCEPTION 'checkin_premio_nao_encontrado'; END IF;
  SELECT x INTO m FROM jsonb_array_elements(public._checkin_marcos_config()) x WHERE x ->> 'chave' = v.marco_chave LIMIT 1;
  v_horas := LEAST(GREATEST(COALESCE((m ->> 'limpeza_horas')::int, 2), 1), 12);

  -- as horas do prémio em Standard; o create valida o vale, desconta e, com resto 0, paga pelo prémio
  v_b := public.create_cleaning_booking(
    'standard', 'hourly', NULL, v_horas, p_scheduled_at, 'single', 'client', 'card',
    p_address_street, p_address_city, p_address_postal, p_lat, p_lng,
    btrim(COALESCE(p_notes, '') || ' [Prémio do check-in: ' || v_horas || ' h de limpeza pagas pela Bora]'),
    NULL, 'checkin-premio-' || v.id::text, 1, v.id);
  v_id := (v_b ->> 'id')::uuid;

  -- sobrou resto (ex.: taxa de deslocação, que o prémio não cobre): sem passo de pagamento neste caminho,
  -- a profissional cobra o resto em dinheiro
  UPDATE public.cleaning_bookings SET payment_method = 'cash'
   WHERE id = v_id AND payment_method = 'card' AND payment_status = 'unpaid';
  IF FOUND THEN PERFORM public._cleaning_next_offer(v_id); END IF;

  SELECT * INTO v FROM public.checkin_premios_vales WHERE id = p_vale_id;
  RETURN jsonb_build_object('ok', true, 'vale', public._checkin_vale_json(v),
                            'marcacao', (SELECT to_jsonb(b) FROM public.cleaning_bookings b WHERE b.id = v_id));
END;
$function$;

CREATE OR REPLACE FUNCTION public.client_checkin_premio_marcar_lavagem(
  p_vale_id uuid, p_plate text, p_client_phone text, p_when_mode text, p_scheduled_at timestamptz,
  p_address_street text, p_address_city text, p_address_postal text,
  p_lat double precision, p_lng double precision,
  p_car_make_model text DEFAULT '', p_car_color text DEFAULT '', p_pickup_notes text DEFAULT '')
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_uid   uuid := auth.uid();
  v       public.checkin_premios_vales;
  v_b     jsonb;
  v_id    uuid;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'not_authenticated' USING ERRCODE = '42501'; END IF;
  -- lavagem só por fora; o create valida o vale, desconta, paga pelo prémio e chama o lavador (uma vez)
  v_b := public.create_carwash_booking(
    'exterior', p_plate, p_client_phone, p_when_mode, p_scheduled_at,
    p_address_street, p_address_city, p_address_postal, p_lat, p_lng, 'card',
    p_car_make_model, p_car_color, p_pickup_notes,
    '[Prémio do check-in: lavagem exterior paga pela Bora]', '[]'::jsonb, NULL, p_vale_id);
  v_id := (v_b ->> 'id')::uuid;
  SELECT * INTO v FROM public.checkin_premios_vales WHERE id = p_vale_id;
  RETURN jsonb_build_object('ok', true, 'vale', public._checkin_vale_json(v),
                            'marcacao', (SELECT to_jsonb(w) FROM public.carwash_bookings w WHERE w.id = v_id));
END;
$function$;

-- ── 4. O vale volta ao cancelar, seja qual for o meio de pagamento ───────────
-- (a função _checkin_premio_marcacao_cancelada não muda: com taxa ou "não apareceu" o vale não volta)
CREATE OR REPLACE TRIGGER trg_checkin_premio_limpeza_cancelada
  AFTER UPDATE OF status ON public.cleaning_bookings
  FOR EACH ROW
  WHEN ((NEW.payment_method = 'premio' OR NEW.checkin_vale_id IS NOT NULL)
        AND NEW.status LIKE 'cancelled%' AND OLD.status IS DISTINCT FROM NEW.status)
  EXECUTE FUNCTION public._checkin_premio_marcacao_cancelada();

CREATE OR REPLACE TRIGGER trg_checkin_premio_lavagem_cancelada
  AFTER UPDATE OF status ON public.carwash_bookings
  FOR EACH ROW
  WHEN ((NEW.payment_method = 'premio' OR NEW.checkin_vale_id IS NOT NULL)
        AND NEW.status LIKE 'cancelled%' AND OLD.status IS DISTINCT FROM NEW.status)
  EXECUTE FUNCTION public._checkin_premio_marcacao_cancelada();

-- ── 5. Série: a limpeza seguinte de uma série paga pelo prémio vai em dinheiro ──
-- generate_recurring_bookings copia o payment_method da anterior; uma cópia 'premio' sem vale partia na
-- guarda (checkin_premio_pagamento_sem_vale). O nome ordena-o ANTES de trg_checkin_premio_guarda_pagamento.
CREATE OR REPLACE FUNCTION public._trg_checkin_premio_serie_em_dinheiro()
RETURNS trigger
LANGUAGE plpgsql
SET search_path TO 'public'
AS $function$
BEGIN
  NEW.payment_method := 'cash';
  NEW.payment_status := 'unpaid';
  RETURN NEW;
END;
$function$;

CREATE OR REPLACE TRIGGER trg_checkin_premio_0_serie_em_dinheiro
  BEFORE INSERT ON public.cleaning_bookings
  FOR EACH ROW
  WHEN (NEW.payment_method = 'premio' AND NEW.checkin_vale_id IS NULL AND NEW.recurrence_group_id IS NOT NULL)
  EXECUTE FUNCTION public._trg_checkin_premio_serie_em_dinheiro();

-- ── 6. Guarda de escrita direta: os campos do prémio (e o dinheiro de uma marcação com prémio) só mudam
--       pelas funções do servidor. SECURITY INVOKER de propósito (como _checkin_premio_guarda_pagamento):
--       current_user = authenticated/anon é escrita direta pela API.
CREATE OR REPLACE FUNCTION public._checkin_premio_guarda_campos()
RETURNS trigger
LANGUAGE plpgsql
SET search_path TO 'public'
AS $function$
DECLARE
  v_novo  jsonb;
  v_velho jsonb;
  k       text;
BEGIN
  IF current_user NOT IN ('authenticated', 'anon') THEN RETURN NEW; END IF;
  IF TG_OP = 'INSERT' THEN
    IF COALESCE(NEW.checkin_premio_cents, 0) <> 0 OR NEW.checkin_vale_id IS NOT NULL THEN
      RAISE EXCEPTION 'checkin_premio_marcacao_so_pelo_servidor (checkin)' USING ERRCODE = '42501';
    END IF;
    RETURN NEW;
  END IF;
  IF NEW.checkin_premio_cents IS DISTINCT FROM OLD.checkin_premio_cents
     OR NEW.checkin_vale_id IS DISTINCT FROM OLD.checkin_vale_id THEN
    RAISE EXCEPTION 'checkin_premio_marcacao_so_pelo_servidor (checkin)' USING ERRCODE = '42501';
  END IF;
  IF OLD.checkin_vale_id IS NOT NULL THEN
    v_novo  := to_jsonb(NEW);
    v_velho := to_jsonb(OLD);
    FOREACH k IN ARRAY ARRAY['payment_method', 'total_cents', 'base_cents', 'bora_fee_cents',
                             'cleaner_earnings_cents', 'washer_earnings_cents', 'team_total_cents', 'share_cents',
                             'client_user_id', 'hours', 'service_type', 'cleaning_type', 'pricing_mode'] LOOP
      IF (v_novo -> k) IS DISTINCT FROM (v_velho -> k) THEN
        RAISE EXCEPTION 'checkin_premio_marcacao_so_pelo_servidor (%)', k USING ERRCODE = '42501';
      END IF;
    END LOOP;
  END IF;
  RETURN NEW;
END;
$function$;

CREATE OR REPLACE TRIGGER trg_checkin_premio_guarda_campos
  BEFORE INSERT OR UPDATE ON public.cleaning_bookings
  FOR EACH ROW EXECUTE FUNCTION public._checkin_premio_guarda_campos();
CREATE OR REPLACE TRIGGER trg_checkin_premio_guarda_campos
  BEFORE INSERT OR UPDATE ON public.carwash_bookings
  FOR EACH ROW EXECUTE FUNCTION public._checkin_premio_guarda_campos();

-- ── 7. Para a app: há um prémio de limpeza/lavagem por usar? (banner "Usar o meu prémio") ──
-- Devolve o vale que expira primeiro, ou null. O valor é a mesma conta do create.
CREATE OR REPLACE FUNCTION public.client_checkin_premio_servico_para_usar(p_tipo text)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_uid   uuid := auth.uid();
  v       public.checkin_premios_vales;
  m       jsonb;
  v_horas integer;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'not_authenticated' USING ERRCODE = '42501'; END IF;
  IF p_tipo NOT IN ('limpeza', 'lavagem') THEN RAISE EXCEPTION 'tipo_invalido: %', p_tipo; END IF;
  SELECT * INTO v FROM public.checkin_premios_vales
   WHERE user_id = v_uid AND tipo = 'servico' AND estado = 'por_usar'
     AND valido_ate IS NOT NULL AND valido_ate > now()
     AND p_tipo = ANY (COALESCE(opcoes, '{}'))
   ORDER BY valido_ate, emitido_em
   LIMIT 1;
  IF v.id IS NULL THEN RETURN NULL; END IF;
  IF p_tipo = 'limpeza' THEN
    SELECT x INTO m FROM jsonb_array_elements(public._checkin_marcos_config()) x WHERE x ->> 'chave' = v.marco_chave LIMIT 1;
    v_horas := LEAST(GREATEST(COALESCE((m ->> 'limpeza_horas')::int, 2), 1), 12);
  END IF;
  RETURN jsonb_build_object(
    'vale_id', v.id, 'tipo', p_tipo, 'titulo', v.titulo, 'valido_ate', v.valido_ate,
    'horas', v_horas,
    'valor_cents', CASE WHEN p_tipo = 'limpeza'
                        THEN v_horas * public._cleaning_setting_int('cleaning_hourly_cents', 1200)
                        ELSE (public.carwash_quote('exterior') ->> 'total_cents')::int END);
END;
$function$;

-- ── 8. Reserva do Divan (ffa77ebf): para os campos novos SEM mudar valores ────────
-- A 26/11 a Claude.ai pôs o prémio em recurring_discount_cents (2400). Passa para checkin_premio_cents;
-- total_cents (2400), cleaner_earnings_cents (4080) e bora_fee_cents (-1680) ficam iguais.
-- Só se a reserva ainda não estiver feita nem paga. Backup antes: bkp_cleaning_bookings_divan_20261128.
DO $divan$
DECLARE
  v_id   uuid := 'ffa77ebf-cafb-4eac-b38a-0af35ef3745f';
  v_vale uuid := '05053050-4942-4ed7-a16a-7d59ccee699d';
  b      public.cleaning_bookings;
BEGIN
  SELECT * INTO b FROM public.cleaning_bookings WHERE id = v_id;
  IF b.id IS NULL THEN RAISE NOTICE 'divan: reserva % não existe aqui — nada feito', v_id; RETURN; END IF;
  IF b.checkin_vale_id IS NOT NULL THEN RAISE NOTICE 'divan: já migrada — nada feito'; RETURN; END IF;
  IF b.status IN ('done', 'completed') OR b.payment_status IN ('released', 'cash_settled') THEN
    RAISE NOTICE 'divan: reserva já feita/paga (status %, pagamento %) — nada feito', b.status, b.payment_status;
    RETURN;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.checkin_premios_vales
                  WHERE id = v_vale AND user_id = b.client_user_id AND marcacao_id = v_id) THEN
    RAISE NOTICE 'divan: o vale % não está ligado a esta reserva — nada feito', v_vale;
    RETURN;
  END IF;
  CREATE TABLE IF NOT EXISTS public.bkp_cleaning_bookings_divan_20261128 AS
    SELECT * FROM public.cleaning_bookings WHERE id = v_id;
  REVOKE ALL ON public.bkp_cleaning_bookings_divan_20261128 FROM anon, authenticated;
  UPDATE public.cleaning_bookings
     SET checkin_premio_cents = b.recurring_discount_cents, checkin_vale_id = v_vale, recurring_discount_cents = 0
   WHERE id = v_id;
  RAISE NOTICE 'divan: migrada (prémio % cêntimos; total %, profissional %, Bora % — iguais)',
    b.recurring_discount_cents, b.total_cents, b.cleaner_earnings_cents, b.bora_fee_cents;
END $divan$;

-- ── 9. Permissões: internas fechadas; a da app aberta a authenticated ─────────
REVOKE ALL ON FUNCTION public._trg_checkin_premio_serie_em_dinheiro() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public._checkin_premio_guarda_campos() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.client_checkin_premio_servico_para_usar(text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.client_checkin_premio_servico_para_usar(text) TO authenticated, service_role;
-- (client_checkin_premio_marcar_limpeza/lavagem: create or replace mantém as permissões que já tinham)

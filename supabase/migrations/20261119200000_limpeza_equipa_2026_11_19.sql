-- 19/11/2026 — missão limpeza-longe-e-equipa-2026-11-19, BLOCO B: equipa de várias profissionais.
-- Ordem do Danilo ("eu autorizo, faz tudo e publica", 19/11/2026). Decisões fechadas no prompt da missão.
--
-- Desenho: UMA reserva por profissional, ligadas por team_group_id.
--  - vaga 1 = principal: guarda o TOTAL DA EQUIPA em total_cents (é o que o cliente paga uma só vez;
--    o cartão/MB Way, o webhook e o estorno continuam a ler total_cents da principal, sem mexer na Stripe).
--  - vagas 2..N = irmãs: total_cents = 0 (não se cobram à parte).
--  - TODAS as vagas guardam a parte dessa profissional: share_cents (= trabalho dela + a sua deslocação
--    + parte igual dos produtos), cleaner_earnings_cents e bora_fee_cents (15% só do trabalho).
--    O acerto semanal (compute_cleaner_weekly_settlement) já soma ganho/taxa por linha: não muda.
--  - Cada vaga toca à parte (_cleaning_next_offer por linha), a mesma profissional nunca fica com duas
--    vagas da mesma equipa, a pedida pelo cliente fica com a vaga 1, só toca a quem cobre a morada.
--  - Pagamento: quando a principal fica paga, as irmãs ficam pagas também (gatilho) e começam a tocar.
--  - Cliente cancela = cancela a equipa toda (regras de hoje, sobre o total da equipa).
--    Uma profissional desiste = só a vaga dela volta a tocar (cancel_cleaning_booking já fazia isso por linha).
--  - Série semanal/quinzenal repete a equipa (as mesmas profissionais primeiro).
-- Preço: (preço/hora × horas + extra do tipo − desconto da série) × N + produtos (uma vez) + deslocação × N.
-- Só no modo "Por horas"; N de 1 a cleaning_max_professionals (3).
-- Prova a fazer: Celorico, Standard, 4 h, 2 profissionais, produtos do cliente → 96 + 2×29 = 154 €;
-- Bora 14,40 €; cada profissional 69,80 €.

ALTER TABLE public.cleaning_bookings
  ADD COLUMN IF NOT EXISTS team_group_id uuid,
  ADD COLUMN IF NOT EXISTS team_size integer NOT NULL DEFAULT 1,
  ADD COLUMN IF NOT EXISTS team_slot integer NOT NULL DEFAULT 1,
  ADD COLUMN IF NOT EXISTS team_total_cents integer,
  ADD COLUMN IF NOT EXISTS share_cents integer;

DO $c$ BEGIN
  ALTER TABLE public.cleaning_bookings
    ADD CONSTRAINT cleaning_bookings_team_chk
    CHECK (team_size BETWEEN 1 AND 10 AND team_slot BETWEEN 1 AND team_size);
EXCEPTION WHEN duplicate_object THEN NULL; END $c$;

CREATE INDEX IF NOT EXISTS cleaning_bookings_team_group_idx
  ON public.cleaning_bookings(team_group_id) WHERE team_group_id IS NOT NULL;
-- uma vaga por equipa, nunca duas linhas na mesma vaga (toque duplo / rede a cair)
CREATE UNIQUE INDEX IF NOT EXISTS cleaning_bookings_team_slot_uq
  ON public.cleaning_bookings(team_group_id, team_slot) WHERE team_group_id IS NOT NULL;

COMMENT ON COLUMN public.cleaning_bookings.team_group_id IS 'Equipa: liga as reservas de cada profissional da mesma limpeza (vaga 1 = principal).';
COMMENT ON COLUMN public.cleaning_bookings.team_total_cents IS 'Equipa: total que o cliente paga pela equipa toda (igual em todas as vagas). Só a vaga 1 tem total_cents = este valor.';
COMMENT ON COLUMN public.cleaning_bookings.share_cents IS 'Parte desta profissional (trabalho + a sua deslocação + parte dos produtos). Em dinheiro, é o que ela recebe do cliente.';

INSERT INTO public.platform_settings(key, value, description, category) VALUES
 ('cleaning_max_professionals', to_jsonb(3), 'Limpeza: máximo de profissionais na mesma limpeza (equipa, só no modo Por horas)', 'cleaning')
ON CONFLICT (key) DO NOTHING;

-- ── Preço da equipa ─────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.cleaning_quote_team(p_cleaning_type text, p_pricing_mode text, p_home_size text, p_hours integer, p_recurrence text, p_products_by text, p_lat double precision, p_lng double precision, p_team_size integer DEFAULT 1)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_n int := COALESCE(p_team_size, 1);
  v_max int := public._cleaning_setting_int('cleaning_max_professionals', 3);
  v_q jsonb;
  v_bora_pct int := public._cleaning_setting_int('cleaning_bora_pct', 15);
  v_work int; v_travel int; v_products int; v_bora1 int;
  v_prod_base int; v_prod_resto int;
  v_shares jsonb := '[]'::jsonb;
  v_s int; v_prod_s int; v_share int;
  v_total int := 0;
BEGIN
  IF v_n < 1 OR v_n > v_max THEN
    RAISE EXCEPTION 'equipa_invalida: de 1 a % profissionais', v_max;
  END IF;
  IF v_n > 1 AND p_pricing_mode <> 'hourly' THEN
    RAISE EXCEPTION 'equipa_so_por_horas';
  END IF;
  -- A conta de UMA profissional (com a deslocação dela) vem da cleaning_quote_at de sempre.
  v_q := public.cleaning_quote_at(p_cleaning_type, p_pricing_mode, p_home_size, p_hours,
                                  p_recurrence, p_products_by, p_lat, p_lng);
  IF v_n = 1 THEN
    RETURN v_q || jsonb_build_object(
      'team_size', 1,
      'per_pro_work_cents', (v_q->>'base_cents')::int + (v_q->>'type_surcharge_cents')::int - (v_q->>'recurring_discount_cents')::int,
      'shares', jsonb_build_array(jsonb_build_object(
        'slot', 1, 'share_cents', (v_q->>'total_cents')::int,
        'cleaner_earnings_cents', (v_q->>'cleaner_earnings_cents')::int,
        'bora_fee_cents', (v_q->>'bora_fee_cents')::int,
        'products_cents', (v_q->>'products_fee_cents')::int,
        'travel_fee_cents', COALESCE((v_q->>'travel_fee_cents')::int, 0))));
  END IF;

  v_work     := (v_q->>'base_cents')::int + (v_q->>'type_surcharge_cents')::int
                - (v_q->>'recurring_discount_cents')::int;
  v_travel   := COALESCE((v_q->>'travel_fee_cents')::int, 0);
  v_products := (v_q->>'products_fee_cents')::int;          -- uma vez só para a equipa
  v_bora1    := round(v_work * v_bora_pct / 100.0)::int;    -- 15% só do trabalho
  v_prod_base  := v_products / v_n;
  v_prod_resto := v_products - v_prod_base * v_n;           -- o resto do arredondamento vai para a vaga 1

  FOR v_s IN 1..v_n LOOP
    v_prod_s := v_prod_base + CASE WHEN v_s = 1 THEN v_prod_resto ELSE 0 END;
    v_share  := v_work + v_travel + v_prod_s;
    v_total  := v_total + v_share;
    v_shares := v_shares || jsonb_build_array(jsonb_build_object(
      'slot', v_s, 'share_cents', v_share,
      'cleaner_earnings_cents', v_share - v_bora1,
      'bora_fee_cents', v_bora1,
      'products_cents', v_prod_s,
      'travel_fee_cents', v_travel));
  END LOOP;

  RETURN v_q || jsonb_build_object(
    'team_size', v_n,
    'per_pro_work_cents', v_work,
    'per_pro_total_cents', v_work + v_travel,
    'team_work_cents', v_work * v_n,
    'team_travel_fee_cents', v_travel * v_n,
    'total_cents', v_total,
    'bora_fee_cents', v_bora1 * v_n,
    'cleaner_earnings_cents', v_total - v_bora1 * v_n,
    'shares', v_shares);
END $function$;

GRANT EXECUTE ON FUNCTION public.cleaning_quote_team(text, text, text, integer, text, text, double precision, double precision, integer) TO authenticated, service_role;
REVOKE EXECUTE ON FUNCTION public.cleaning_quote_team(text, text, text, integer, text, text, double precision, double precision, integer) FROM anon;


-- ── Criar a limpeza (com equipa) ─────────────────────────────────────────────
-- Assinatura nova (p_team_size com valor por defeito): a app antiga, que não manda p_team_size,
-- continua a funcionar. Larga-se a antiga para não haver duas versões ambíguas.
DROP FUNCTION IF EXISTS public.create_cleaning_booking(text,text,text,integer,timestamp with time zone,text,text,text,text,text,text,double precision,double precision,text,uuid,text);
CREATE FUNCTION public.create_cleaning_booking(p_cleaning_type text, p_pricing_mode text, p_home_size text, p_hours integer, p_scheduled_at timestamp with time zone, p_recurrence text, p_products_by text, p_payment_method text, p_address_street text, p_address_city text, p_address_postal text, p_lat double precision, p_lng double precision, p_notes text DEFAULT ''::text, p_requested_cleaner_id uuid DEFAULT NULL::uuid, p_idempotency_key text DEFAULT NULL::text, p_team_size integer DEFAULT 1)
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

  -- 19/11/2026 equipa: a conta vem da cleaning_quote_team (com 1 profissional = cleaning_quote_at).
  v_quote := public.cleaning_quote_team(p_cleaning_type, p_pricing_mode, p_home_size,
                                   p_hours, p_recurrence, p_products_by, p_lat, p_lng, v_n);
  -- 19/11/2026: limpeza só até cleaning_max_distance_km do centro da Guarda
  IF COALESCE((v_quote ->> 'out_of_area')::boolean, false) THEN
    RAISE EXCEPTION 'fora_da_area_limpeza: ainda não fazemos limpezas a mais de % km da Guarda', v_quote ->> 'max_distance_km';
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
    team_group_id, team_size, team_slot, team_total_cents, share_cents
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
    (v_quote ->> 'total_cents')::int, (v_share ->> 'cleaner_earnings_cents')::int,
    (v_share ->> 'bora_fee_cents')::int,
    COALESCE((v_quote ->> 'travel_fee_cents')::int, 0), NULLIF(v_quote ->> 'travel_distance_km', '')::numeric,
    v_key,
    v_team, v_n, 1, (v_quote ->> 'total_cents')::int, (v_share ->> 'share_cents')::int
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
GRANT EXECUTE ON FUNCTION public.create_cleaning_booking(text,text,text,integer,timestamp with time zone,text,text,text,text,text,text,double precision,double precision,text,uuid,text,integer) TO authenticated, service_role;
REVOKE EXECUTE ON FUNCTION public.create_cleaning_booking(text,text,text,integer,timestamp with time zone,text,text,text,text,text,text,double precision,double precision,text,uuid,text,integer) FROM anon;


-- ── Toque por vaga: nunca a mesma profissional em duas vagas; alerta diz a vaga ──
CREATE OR REPLACE FUNCTION public._cleaning_next_offer(p_booking_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_b cleaning_bookings;
  v_next uuid;
  v_next_user uuid;
  v_next_nome text;
  v_tem boolean;
  v_timeout int := public._cleaning_setting_int('cleaning_offer_timeout_min', 30);
  v_curto int;
BEGIN
  SELECT * INTO v_b FROM cleaning_bookings WHERE id = p_booking_id FOR UPDATE;
  IF v_b.id IS NULL OR v_b.status <> 'scheduled' THEN RETURN; END IF;
  -- 19/10/2026 (regra do Danilo): só se chama a limpadora se a limpeza estiver paga.
  -- MB Way/cartão por pagar → ninguém é chamado; o gatilho trg_cleaning_paid_offer
  -- chama quando o pagamento entra. Dinheiro chama logo.
  IF v_b.payment_method IN ('mbway','card') AND v_b.payment_status = 'unpaid' THEN RETURN; END IF;

  SELECT c.id, c.user_id, c.name INTO v_next, v_next_user, v_next_nome
  FROM cleaners c
  WHERE c.approval_status = 'approved' AND c.is_active
    AND c.user_id <> v_b.client_user_id
    AND NOT (c.id = ANY (v_b.offered_cleaner_ids))
    AND (c.base_lat IS NULL OR v_b.lat IS NULL
         OR public._cleaning_distance_km(c.base_lat, c.base_lng, v_b.lat, v_b.lng) <= c.service_radius_km)
    AND public._cleaning_is_available(c.id, v_b.scheduled_at, v_b.duration_min)
    AND public.aceita_papel(c.user_id, 'cleaner')  -- 2026-10-14: papel desligado nao recebe
    -- 19/11/2026 equipa: a mesma profissional nunca fica com duas vagas da mesma limpeza
    AND NOT EXISTS (SELECT 1 FROM cleaning_bookings t
                     WHERE v_b.team_group_id IS NOT NULL
                       AND t.team_group_id = v_b.team_group_id AND t.id <> v_b.id
                       AND t.status NOT LIKE 'cancelled%'
                       AND (t.cleaner_id = c.id OR t.offer_cleaner_id = c.id))
  ORDER BY (c.id = v_b.requested_cleaner_id) DESC,
           public.tem_aparelho(c.user_id, 'cleaner') DESC,
           c.rating_avg DESC, c.cleanings_done DESC
  LIMIT 1;

  IF v_next IS NULL THEN
    UPDATE cleaning_bookings
    SET offer_cleaner_id = NULL, offer_expires_at = NULL
    WHERE id = p_booking_id;
    PERFORM public._cleaning_notify_admin(
      'Limpeza sem profissional',
      'Reserva ' || p_booking_id::text || ' para ' ||
      to_char(v_b.scheduled_at AT TIME ZONE 'Europe/Lisbon', 'DD/MM HH24:MI') ||
      CASE WHEN v_b.team_size > 1
           THEN ' — EQUIPA: falta a vaga ' || v_b.team_slot || ' de ' || v_b.team_size
           ELSE '' END ||
      ' sem profissional disponível.');
    RETURN;
  END IF;

  v_tem := public.tem_aparelho(v_next_user, 'cleaner');
  SELECT COALESCE((value #>> '{}')::int, 1) INTO v_curto
    FROM platform_settings WHERE key = 'oferta_sem_aparelho_min';
  IF NOT v_tem THEN v_timeout := LEAST(v_timeout, COALESCE(v_curto, 1)); END IF;

  UPDATE cleaning_bookings
  SET offer_cleaner_id = v_next,
      offer_expires_at = now() + make_interval(mins => v_timeout),
      offered_cleaner_ids = offered_cleaner_ids || v_next
  WHERE id = p_booking_id;

  PERFORM public.registar_oferta('limpeza', p_booking_id, v_next, v_next_user,
                                 v_next_nome, v_tem, v_timeout);

  PERFORM public._cleaning_notify_user(
    v_next_user,
    'cleaning_offer', 'Nova limpeza disponível',
    'Limpeza a ' || to_char(v_b.scheduled_at AT TIME ZONE 'Europe/Lisbon', 'DD/MM às HH24:MI') ||
    CASE WHEN v_b.team_size > 1
         THEN ' (equipa de ' || v_b.team_size || ' — tu e mais ' || (v_b.team_size - 1) || ')'
         ELSE '' END ||
    ' — ' || 'ganhas ' || (COALESCE(v_b.cleaner_earnings_cents, v_b.total_cents) / 100.0)::numeric(10,2) || ' EUR. Tens ' || v_timeout || ' min para aceitar.',
    p_booking_id::text);
END $function$;


-- ── Pagamento da equipa: a principal paga → as irmãs ficam pagas e começam a tocar ──
-- (regra de 19/10: MB Way/cartão só toca depois de pago; o gatilho trg_cleaning_paid_offer
--  de cada irmã dispara com esta mudança unpaid → held.)
CREATE OR REPLACE FUNCTION public._trg_cleaning_team_paid()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
  IF NEW.team_group_id IS NOT NULL AND NEW.team_slot = 1
     AND OLD.payment_status = 'unpaid' AND NEW.payment_status = 'held' THEN
    BEGIN
      UPDATE cleaning_bookings
         SET payment_status = 'held'
       WHERE team_group_id = NEW.team_group_id AND team_slot > 1
         AND payment_status = 'unpaid' AND status NOT LIKE 'cancelled%';
    EXCEPTION WHEN OTHERS THEN
      RAISE WARNING '_trg_cleaning_team_paid falhou (booking=%): %', NEW.id, SQLERRM;
    END;
  END IF;
  RETURN NULL;
END $function$;

DROP TRIGGER IF EXISTS trg_cleaning_team_paid ON public.cleaning_bookings;
CREATE TRIGGER trg_cleaning_team_paid
  AFTER UPDATE OF payment_status ON public.cleaning_bookings
  FOR EACH ROW EXECUTE FUNCTION public._trg_cleaning_team_paid();


-- ── Cancelar: cliente cancela a equipa toda; profissional que desiste só liberta a sua vaga ──
CREATE OR REPLACE FUNCTION public.cancel_cleaning_booking(p_booking_id uuid, p_reason text DEFAULT ''::text, p_no_show boolean DEFAULT false)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  v_b cleaning_bookings;
  v_me cleaners;
  v_is_client boolean;
  v_hours numeric;
  v_free int := public._cleaning_setting_int('cleaning_cancel_free_hours', 24);
  v_half int := public._cleaning_setting_int('cleaning_cancel_half_hours', 2);
  v_fee int := 0;
  v_late boolean := false;
  v_late_count int;
  v_limit int := public._cleaning_setting_int('cleaning_late_cancel_limit', 3);
  v_bora_pct int := public._cleaning_setting_int('cleaning_bora_pct', 15);
  v_irma record;
  v_principal uuid;
BEGIN
  -- 19/11/2026 equipa: o CLIENTE cancela sempre a equipa toda, pela vaga 1 (é lá que está o pagamento).
  SELECT * INTO v_b FROM cleaning_bookings WHERE id = p_booking_id;
  IF v_b.id IS NOT NULL AND v_b.team_group_id IS NOT NULL AND v_b.team_slot > 1
     AND v_b.client_user_id = v_uid THEN
    SELECT id INTO v_principal FROM cleaning_bookings
     WHERE team_group_id = v_b.team_group_id AND team_slot = 1;
    IF v_principal IS NOT NULL THEN
      RETURN public.cancel_cleaning_booking(v_principal, p_reason, p_no_show);
    END IF;
  END IF;

  SELECT * INTO v_b FROM cleaning_bookings WHERE id = p_booking_id FOR UPDATE;
  IF v_b.id IS NULL THEN RAISE EXCEPTION 'booking_not_found'; END IF;
  IF v_b.status NOT IN ('scheduled','accepted','on_the_way') THEN
    RAISE EXCEPTION 'cannot_cancel_from_%', v_b.status;
  END IF;

  v_is_client := (v_b.client_user_id = v_uid);
  IF NOT v_is_client THEN
    v_me := public._cleaning_current_cleaner();
    IF v_b.cleaner_id IS DISTINCT FROM v_me.id
       AND v_b.offer_cleaner_id IS DISTINCT FROM v_me.id THEN
      RAISE EXCEPTION 'booking_not_yours';
    END IF;
  END IF;

  v_hours := EXTRACT(epoch FROM (v_b.scheduled_at - now())) / 3600.0;

  IF v_is_client THEN
    IF v_hours >= v_free OR now() - v_b.created_at <= make_interval(mins => public._cleaning_setting_int('cleaning_cancel_grace_minutes', 5)) THEN v_fee := 0;
    ELSIF v_hours >= v_half THEN v_fee := round(v_b.total_cents * 0.5)::int;
    ELSE v_fee := v_b.total_cents;
    END IF;

    UPDATE cleaning_bookings
    SET status = 'cancelled_client', cancelled_at = now(), cancelled_by = 'client',
        cancel_reason = COALESCE(p_reason,''), cancel_fee_cents = v_fee,
        payment_status = CASE
          WHEN payment_method = 'cash' AND v_fee > 0 THEN 'cash_pending'
          WHEN payment_status = 'held' THEN 'estornado'
          ELSE payment_status
        END,
        offer_cleaner_id = NULL, offer_expires_at = NULL
    WHERE id = p_booking_id;

    IF v_b.cleaner_id IS NOT NULL THEN
      PERFORM public._cleaning_notify_user(
        (SELECT user_id FROM cleaners WHERE id = v_b.cleaner_id),
        'cleaning_cancelled', 'Limpeza cancelada',
        'O cliente cancelou a limpeza de ' ||
        to_char(v_b.scheduled_at AT TIME ZONE 'Europe/Lisbon', 'DD/MM HH24:MI') ||
        CASE WHEN v_fee > 0
             THEN '. Recebes ' || (round(v_fee * (100 - v_bora_pct) / 100.0 / GREATEST(v_b.team_size, 1)) / 100.0)::numeric(10,2) || ' EUR de compensação.'
             ELSE '.' END,
        p_booking_id::text);
    END IF;

    -- Equipa: as outras vagas caem com a principal (sem taxa à parte: a taxa é sobre o total da equipa).
    IF v_b.team_group_id IS NOT NULL AND v_b.team_slot = 1 THEN
      FOR v_irma IN
        SELECT id, cleaner_id FROM cleaning_bookings
         WHERE team_group_id = v_b.team_group_id AND team_slot > 1
           AND status IN ('scheduled','accepted','on_the_way')
         FOR UPDATE
      LOOP
        UPDATE cleaning_bookings
        SET status = 'cancelled_client', cancelled_at = now(), cancelled_by = 'client',
            cancel_reason = COALESCE(p_reason,''), cancel_fee_cents = 0,
            payment_status = CASE WHEN payment_status = 'held' THEN 'estornado' ELSE payment_status END,
            offer_cleaner_id = NULL, offer_expires_at = NULL
        WHERE id = v_irma.id;
        IF v_irma.cleaner_id IS NOT NULL THEN
          PERFORM public._cleaning_notify_user(
            (SELECT user_id FROM cleaners WHERE id = v_irma.cleaner_id),
            'cleaning_cancelled', 'Limpeza cancelada',
            'O cliente cancelou a limpeza de ' ||
            to_char(v_b.scheduled_at AT TIME ZONE 'Europe/Lisbon', 'DD/MM HH24:MI') ||
            CASE WHEN v_fee > 0
                 THEN '. Recebes ' || (round(v_fee * (100 - v_bora_pct) / 100.0 / GREATEST(v_b.team_size, 1)) / 100.0)::numeric(10,2) || ' EUR de compensação.'
                 ELSE '.' END,
            v_irma.id::text);
        END IF;
      END LOOP;
    END IF;

  ELSE
    IF p_no_show THEN
      IF now() < v_b.scheduled_at THEN
        RAISE EXCEPTION 'no_show_only_after_scheduled_time';
      END IF;
      v_fee := v_b.total_cents;
      UPDATE cleaning_bookings
      SET status = 'cancelled_client', cancelled_at = now(), cancelled_by = 'cleaner',
          cancel_reason = COALESCE(NULLIF(p_reason,''), 'no_show_cliente'),
          cancel_fee_cents = v_fee, no_show_client = true,
          payment_status = CASE
            WHEN payment_method = 'cash' THEN 'cash_pending'
            WHEN payment_status = 'held' THEN 'released'
            ELSE payment_status END
      WHERE id = p_booking_id;
      PERFORM public._cleaning_notify_user(v_b.client_user_id, 'cleaning_no_show',
        'Limpeza marcada como não comparência',
        'A profissional não conseguiu aceder à morada à hora marcada. Foi aplicada a taxa prevista.',
        p_booking_id::text);
    ELSE
      v_late := (v_hours < v_free);
      UPDATE cleaning_bookings
      SET status = 'scheduled', cleaner_id = NULL, accepted_at = NULL,
          cancelled_late = v_late OR cancelled_late,
          offer_cleaner_id = NULL, offer_expires_at = NULL,
          offered_cleaner_ids = CASE WHEN v_me.id = ANY (offered_cleaner_ids)
                                     THEN offered_cleaner_ids
                                     ELSE offered_cleaner_ids || v_me.id END
      WHERE id = p_booking_id;

      IF v_late THEN
        INSERT INTO cleaner_cancel_events (cleaner_id, booking_id, was_late)
        VALUES (v_me.id, p_booking_id, true);
        SELECT count(*) INTO v_late_count FROM cleaner_cancel_events
        WHERE cleaner_id = v_me.id AND was_late AND created_at > now() - interval '30 days';
        IF v_late_count >= v_limit THEN
          IF NOT EXISTS (SELECT 1 FROM public.prestador_suspensoes
                          WHERE entidade_tabela='cleaners' AND entidade_id = v_me.id::text
                            AND tipo='proposta_automatica' AND estado='pendente_decisao') THEN
            INSERT INTO public.prestador_suspensoes
              (user_id, tipo_conta, entidade_tabela, entidade_id, tipo, estado, motivo, motivo_codigo, origem, factos)
            VALUES (v_me.user_id, 'limpeza', 'cleaners', v_me.id::text, 'proposta_automatica', 'pendente_decisao',
                    'Proposta automática: ' || v_late_count || ' cancelamentos tardios em 30 dias (limite ' || v_limit || '). Uma pessoa decide.',
                    'cancelamentos_tardios', 'sistema',
                    jsonb_build_object('cancelamentos_tardios_30d', v_late_count, 'limite', v_limit, 'ultimo_booking', p_booking_id));
          END IF;
          PERFORM public._cleaning_notify_admin('Profissional precisa de decisão humana',
            v_me.name || ' atingiu ' || v_late_count || ' cancelamentos tardios em 30 dias. A app NÃO suspendeu: decide no painel > Revisões.');
          PERFORM public._cleaning_notify_user(v_me.user_id, 'cleaner_revisao',
            'A tua conta vai ser revista',
            'Atingiste o limite de cancelamentos tardios. Uma pessoa da equipa Bora vai rever a tua conta e falar contigo antes de qualquer decisão.',
            NULL);
        END IF;
      ELSE
        INSERT INTO cleaner_cancel_events (cleaner_id, booking_id, was_late)
        VALUES (v_me.id, p_booking_id, false);
      END IF;

      PERFORM public._cleaning_notify_user(v_b.client_user_id, 'cleaning_reassigning',
        'A tua limpeza vai ser reatribuída',
        CASE WHEN v_b.team_size > 1
             THEN 'Uma profissional da tua equipa cancelou. Estamos a procurar outra para o mesmo horário; não perdes nada.'
             ELSE 'A profissional cancelou. Estamos a procurar outra profissional para o mesmo horário.' END,
        CASE WHEN v_b.team_group_id IS NOT NULL
             THEN COALESCE((SELECT id FROM cleaning_bookings WHERE team_group_id = v_b.team_group_id AND team_slot = 1), p_booking_id)::text
             ELSE p_booking_id::text END);
      PERFORM public._cleaning_next_offer(p_booking_id);
    END IF;
  END IF;

  RETURN (SELECT to_jsonb(b) FROM cleaning_bookings b WHERE b.id = p_booking_id);
END $function$;


-- ── Aceitar: o cliente vê quantas da equipa já confirmaram ──
CREATE OR REPLACE FUNCTION public.cleaner_accept_booking(p_booking_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE v_me cleaners; v_b cleaning_bookings;
BEGIN
  v_me := public._cleaning_current_cleaner();
  SELECT * INTO v_b FROM cleaning_bookings WHERE id = p_booking_id FOR UPDATE;
  IF v_b.id IS NULL THEN RAISE EXCEPTION 'booking_not_found'; END IF;
  IF v_b.status <> 'scheduled' OR v_b.offer_cleaner_id IS DISTINCT FROM v_me.id THEN
    RAISE EXCEPTION 'offer_not_yours_or_expired';
  END IF;
  IF v_b.offer_expires_at IS NOT NULL AND v_b.offer_expires_at < now() THEN
    RAISE EXCEPTION 'offer_expired';
  END IF;

  UPDATE cleaning_bookings
  SET status = 'accepted', cleaner_id = v_me.id, accepted_at = now(),
      offer_cleaner_id = NULL, offer_expires_at = NULL
  WHERE id = p_booking_id;

  PERFORM public._cleaning_notify_user(v_b.client_user_id, 'cleaning_accepted',
    'Limpeza confirmada 🎉',
    v_me.name || ' confirmou a tua limpeza de ' ||
    to_char(v_b.scheduled_at AT TIME ZONE 'Europe/Lisbon', 'DD/MM às HH24:MI') ||
    CASE WHEN v_b.team_size > 1
         THEN ' (equipa: ' || (SELECT count(*) FROM cleaning_bookings t
                                WHERE t.team_group_id = v_b.team_group_id
                                  AND (t.cleaner_id IS NOT NULL OR t.id = p_booking_id)
                                  AND t.status NOT LIKE 'cancelled%')
              || ' de ' || v_b.team_size || ' confirmadas)'
         ELSE '' END || '.',
    -- o cliente abre sempre a limpeza pela vaga 1 (a que tem o preço e o pagamento)
    CASE WHEN v_b.team_group_id IS NOT NULL
         THEN COALESCE((SELECT id FROM cleaning_bookings WHERE team_group_id = v_b.team_group_id AND team_slot = 1), p_booking_id)::text
         ELSE p_booking_id::text END);

  RETURN (SELECT to_jsonb(b) FROM cleaning_bookings b WHERE b.id = p_booking_id);
END $function$;


-- ── Concluir: tokens do cliente uma vez por equipa ──
CREATE OR REPLACE FUNCTION public._cleaning_complete(p_booking_id uuid, p_auto boolean)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_b cleaning_bookings;
  v_cleaner_user uuid;
  v_client_tokens integer;
BEGIN
  SELECT * INTO v_b FROM cleaning_bookings WHERE id = p_booking_id FOR UPDATE;
  IF v_b.id IS NULL OR v_b.status <> 'done' THEN RETURN; END IF;

  UPDATE cleaning_bookings
  SET status = 'completed', completed_at = now(),
      payment_status = CASE
        WHEN payment_method = 'cash' THEN 'cash_pending'
        WHEN payment_status = 'held' THEN 'released'
        ELSE payment_status
      END
  WHERE id = p_booking_id;

  UPDATE cleaners SET cleanings_done = cleanings_done + 1 WHERE id = v_b.cleaner_id;

  v_cleaner_user := (SELECT user_id FROM cleaners WHERE id = v_b.cleaner_id);

  -- TOKENS (mesmo padrão do delivery; idempotente por source_order_id+role)
  -- Cliente: 3 tokens por euro (ROUND(total*3/100)), mínimo 1
  v_client_tokens := GREATEST(1, ROUND(v_b.total_cents * 3 / 100.0)::int);
  -- 19/11/2026 equipa: os tokens do cliente contam uma vez, pela vaga 1 (que tem o total da equipa).
  IF COALESCE(v_b.team_slot, 1) = 1 THEN
    PERFORM public.add_tokens(v_b.client_user_id, 'client', v_client_tokens, 'cleaning:' || p_booking_id::text);
  END IF;

  -- Profissional de limpeza: +40 fixo ao concluir
  IF v_cleaner_user IS NOT NULL THEN
    PERFORM public.add_tokens(v_cleaner_user, 'cleaner', 40, 'cleaning:' || p_booking_id::text);
  END IF;

  PERFORM public._cleaning_notify_user(
    v_cleaner_user,
    'cleaning_completed',
    CASE WHEN p_auto THEN 'Limpeza auto-confirmada 💚' ELSE 'Limpeza confirmada 💚' END,
    'O cliente confirmou a limpeza. Ganhos: ' ||
    (v_b.cleaner_earnings_cents / 100.0)::numeric(10,2) || ' EUR.',
    p_booking_id::text);
END $function$;


-- ── Alerta de limpeza nova: uma vez por equipa, a dizer quantas profissionais ──
CREATE OR REPLACE FUNCTION public._trg_cleaning_notify_admin_new()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_resumo text;
begin
  if coalesce(new.is_test_order, false) then return new; end if;
  -- 19/11/2026 equipa: um só alerta por limpeza (o da vaga 1).
  if coalesce(new.team_slot, 1) > 1 then return new; end if;

  -- 2026-09-16: 1.ª linha = LIMPEZA NOVA + NOME + TELEFONE (vira o título no Telegram/push).
  begin
    v_resumo := public._alerta_txt_limpeza(new);
  exception when others then
    v_resumo := null;
  end;
  v_resumo := coalesce(v_resumo, '🧹 LIMPEZA NOVA · #' || left(new.id::text, 8) || ' — ARRANJAR LIMPADORA');
  if coalesce(new.team_size, 1) > 1 then
    v_resumo := v_resumo || E'\n👥 EQUIPA DE ' || new.team_size || ' PROFISSIONAIS';
  end if;

  begin
    perform public.notify_admin_urgent_push(
      'cleaning_booking_new', v_resumo, 'cleaning_booking', new.id::text,
      jsonb_build_object(
        'booking_id', new.id, 'client_user_id', new.client_user_id,
        'cleaning_type', new.cleaning_type, 'home_size', new.home_size, 'hours', new.hours,
        'scheduled_at', new.scheduled_at, 'duration_min', new.duration_min,
        'address', concat_ws(', ', new.address_street, new.address_city, new.address_postal),
        'lat', new.lat, 'lng', new.lng, 'notes', new.notes,
        'total_cents', new.total_cents, 'payment_method', new.payment_method,
        'status', new.status, 'team_size', new.team_size),
      '/admin/limpeza/' || new.id::text);
  exception when others then
    raise notice 'cleaning notify admin falhou: %', sqlerrm;
  end;

  return new;
end
$function$;


-- ── Vaga sem ninguém à hora: o alerta diz qual vaga e quanto devolver ──
CREATE OR REPLACE FUNCTION public._cleaning_cron_expire_no_cleaner()
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_grace int := public._cleaning_setting_int('cleaning_no_cleaner_grace_min', 15);
  v_count int := 0;
  v_rec record;
BEGIN
  FOR v_rec IN
    SELECT id, client_user_id, scheduled_at, team_group_id, team_slot, team_size,
           payment_method, payment_status, share_cents
    FROM cleaning_bookings
    WHERE status = 'scheduled'
      AND cleaner_id IS NULL
      AND scheduled_at < now() - make_interval(mins => v_grace)
    FOR UPDATE SKIP LOCKED
  LOOP
    UPDATE cleaning_bookings
    SET status = 'cancelled_no_cleaner',
        cancelled_at = now(),
        cancel_reason = 'no_cleaner_found',
        offer_cleaner_id = NULL,
        offer_expires_at = NULL
    WHERE id = v_rec.id;

    -- 19/11/2026 equipa: avisa o Danilo de QUAL vaga ficou vazia e quanto devolver se já estava pago.
    IF v_rec.team_size > 1 THEN
      PERFORM public._cleaning_notify_admin('Limpeza sem profissional',
        'Equipa ' || left(v_rec.team_group_id::text, 8) || ': a vaga ' || v_rec.team_slot || ' de ' || v_rec.team_size ||
        ' ficou sem profissional (' || to_char(v_rec.scheduled_at AT TIME ZONE 'Europe/Lisbon', 'DD/MM HH24:MI') || ').' ||
        CASE WHEN v_rec.payment_method <> 'cash' AND v_rec.payment_status = 'held'
             THEN ' Devolver ao cliente ' || (COALESCE(v_rec.share_cents, 0) / 100.0)::numeric(10,2) || ' EUR desta vaga.'
             ELSE '' END);
    END IF;

    PERFORM public._cleaning_notify_user(
      v_rec.client_user_id,
      'cleaning_no_cleaner',
      CASE WHEN v_rec.team_size > 1 THEN 'Equipa incompleta' ELSE 'Limpeza cancelada' END,
      CASE WHEN v_rec.team_size > 1
           THEN 'Não conseguimos uma profissional para uma das vagas da limpeza de ' ||
                to_char(v_rec.scheduled_at AT TIME ZONE 'Europe/Lisbon', 'DD/MM às HH24:MI') ||
                '. Essa parte não é cobrada. Pedimos desculpa pelo incómodo.'
           ELSE 'Não conseguimos encontrar uma profissional para a limpeza de ' ||
                to_char(v_rec.scheduled_at AT TIME ZONE 'Europe/Lisbon', 'DD/MM às HH24:MI') ||
                '. O pedido foi cancelado. Pedimos desculpa pelo incómodo.' END,
      v_rec.id::text);

    v_count := v_count + 1;
  END LOOP;
  RETURN v_count;
END $function$;


-- ── Série semanal/quinzenal: repete a equipa, as mesmas profissionais primeiro ──
CREATE OR REPLACE FUNCTION public.generate_recurring_bookings()
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_count int := 0; v_rec record; v_last cleaning_bookings;
  v_next timestamptz; v_quote jsonb; v_id uuid; v_seguidos int;
  v_team uuid; v_s int; v_share jsonb; v_sis uuid; v_sisters uuid[]; v_prev uuid;
BEGIN
  FOR v_rec IN
    SELECT DISTINCT recurrence_group_id AS gid FROM cleaning_bookings
    WHERE recurrence_group_id IS NOT NULL
      AND recurrence IN ('weekly','biweekly')
      AND NOT EXISTS (SELECT 1 FROM cleaning_recurrence_stops s
                      WHERE s.group_id = cleaning_bookings.recurrence_group_id)
  LOOP
    SELECT * INTO v_last FROM cleaning_bookings
    WHERE recurrence_group_id = v_rec.gid
    ORDER BY scheduled_at DESC, team_slot ASC LIMIT 1;

    -- 01/11/2026 (regra do Danilo): cancelar UMA marcação não acaba a série. A série só acaba
    -- com "Parar série" (cleaning_recurrence_stops). Antes havia aqui um CONTINUE quando a última
    -- estava cancelled_client, e a série morria em silêncio (caso do Divan, 31/10).
    v_next := public.cleaning_series_next_at(v_rec.gid);
    CONTINUE WHEN v_next IS NULL;
    CONTINUE WHEN v_next - now() > interval '7 days';
    CONTINUE WHEN v_next < now();

    -- 19/11/2026 equipa: a série repete a equipa (mesmo nº de profissionais).
    v_quote := public.cleaning_quote_team(v_last.cleaning_type, v_last.pricing_mode,
                                     v_last.home_size, v_last.hours,
                                     v_last.recurrence, v_last.products_by,
                                     v_last.lat, v_last.lng, COALESCE(v_last.team_size, 1));
    v_team := CASE WHEN COALESCE(v_last.team_size, 1) > 1 THEN gen_random_uuid() END;
    v_share := v_quote -> 'shares' -> 0;
    v_sisters := '{}';

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
      v_last.client_user_id,
      COALESCE(v_last.cleaner_id, v_last.requested_cleaner_id),
      v_rec.gid, v_last.recurrence,
      v_last.cleaning_type, v_last.pricing_mode, v_last.home_size, v_last.hours,
      v_next, (v_quote ->> 'duration_min')::int,
      v_last.address_street, v_last.address_city, v_last.address_postal,
      v_last.lat, v_last.lng, v_last.notes, v_last.products_by,
      v_last.payment_method, 'unpaid',
      (v_quote ->> 'base_cents')::int, (v_quote ->> 'type_surcharge_cents')::int,
      (v_quote ->> 'recurring_discount_cents')::int, (v_share ->> 'products_cents')::int,
      (v_quote ->> 'total_cents')::int, (v_share ->> 'cleaner_earnings_cents')::int,
      (v_share ->> 'bora_fee_cents')::int,
      COALESCE((v_quote ->> 'travel_fee_cents')::int, 0), NULLIF(v_quote ->> 'travel_distance_km', '')::numeric,
      v_team, COALESCE(v_last.team_size, 1), 1, (v_quote ->> 'total_cents')::int, (v_share ->> 'share_cents')::int
    ) RETURNING id INTO v_id;

    -- Equipa: as outras vagas, cada uma a pedir primeiro a profissional que a fez da última vez.
    IF v_team IS NOT NULL THEN
      FOR v_s IN 2..v_last.team_size LOOP
        v_share := v_quote -> 'shares' -> (v_s - 1);
        SELECT COALESCE(p.cleaner_id, p.requested_cleaner_id) INTO v_prev
          FROM cleaning_bookings p
         WHERE p.team_group_id = v_last.team_group_id AND p.team_slot = v_s;
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
          v_last.client_user_id, v_prev, v_rec.gid, v_last.recurrence,
          v_last.cleaning_type, v_last.pricing_mode, v_last.home_size, v_last.hours,
          v_next, (v_quote ->> 'duration_min')::int,
          v_last.address_street, v_last.address_city, v_last.address_postal,
          v_last.lat, v_last.lng, v_last.notes, v_last.products_by,
          v_last.payment_method, 'unpaid',
          (v_quote ->> 'base_cents')::int, (v_quote ->> 'type_surcharge_cents')::int,
          (v_quote ->> 'recurring_discount_cents')::int, (v_share ->> 'products_cents')::int,
          0, (v_share ->> 'cleaner_earnings_cents')::int, (v_share ->> 'bora_fee_cents')::int,
          COALESCE((v_quote ->> 'travel_fee_cents')::int, 0), NULLIF(v_quote ->> 'travel_distance_km', '')::numeric,
          v_team, v_last.team_size, v_s, (v_quote ->> 'total_cents')::int, (v_share ->> 'share_cents')::int
        ) RETURNING id INTO v_sis;
        v_sisters := v_sisters || v_sis;
      END LOOP;
    END IF;

    PERFORM public._cleaning_next_offer(v_id);
    FOREACH v_sis IN ARRAY v_sisters LOOP
      PERFORM public._cleaning_next_offer(v_sis);
    END LOOP;

    IF v_last.payment_method = 'mbway' THEN
      PERFORM public.cleaning_request_payment(v_id);
      PERFORM public._cleaning_notify_user(v_last.client_user_id, 'cleaning_recurring',
        'Próxima limpeza agendada 🔁',
        'A tua limpeza recorrente de ' ||
        to_char(v_next AT TIME ZONE 'Europe/Lisbon', 'DD/MM às HH24:MI') ||
        ' foi criada. Aprova o pagamento MB Way no teu telemóvel para confirmarmos a profissional.',
        v_id::text);
    ELSE
      PERFORM public._cleaning_notify_user(v_last.client_user_id, 'cleaning_recurring',
        'Próxima limpeza agendada 🔁',
        'A tua limpeza recorrente de ' ||
        to_char(v_next AT TIME ZONE 'Europe/Lisbon', 'DD/MM às HH24:MI') ||
        ' foi criada. Podes cancelar na app.',
        v_id::text);
    END IF;
    v_count := v_count + 1;

    SELECT count(*) INTO v_seguidos FROM (
      SELECT status, cancelled_by FROM cleaning_bookings
       WHERE recurrence_group_id = v_rec.gid AND id <> v_id AND team_slot = 1
       ORDER BY scheduled_at DESC LIMIT 3) u
     WHERE u.status = 'cancelled_client' AND u.cancelled_by = 'client';
    IF v_seguidos >= 3 AND NOT EXISTS (
         SELECT 1 FROM admin_notifications n
          WHERE n.event_type = 'cleaning_series_cancelamentos' AND n.entity_id = v_rec.gid::text
            AND n.created_at > now() - interval '30 days') THEN
      BEGIN
        PERFORM public.notify_admin_urgent_push('cleaning_series_cancelamentos',
          E'🔁 SÉRIE DE LIMPEZA — o cliente cancelou as últimas 3\n'
          || public._alerta_quem(v_last.client_user_id) || E'\nA série continua (próxima '
          || to_char(v_next AT TIME ZONE 'Europe/Lisbon', 'DD/MM HH24:MI')
          || '). Se já não quer, o cliente pára a série na app ("Parar série").',
          'cleaning_series', v_rec.gid::text,
          jsonb_build_object('group_id', v_rec.gid, 'client_user_id', v_last.client_user_id, 'booking_id', v_id),
          '/admin/limpeza/' || v_id::text);
      EXCEPTION WHEN OTHERS THEN
        RAISE NOTICE 'generate_recurring_bookings: alerta falhou (%)', sqlerrm;
      END;
    END IF;
  END LOOP;
  RETURN v_count;
END $function$;


-- ── Parar a série com equipa: cancela pela vaga 1 (o total pago volta à Carteira uma vez) ──
CREATE OR REPLACE FUNCTION public.cancel_cleaning_series(p_group_id uuid)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_uid uuid := auth.uid();
  v_count int := 0;
  v_free int := public._cleaning_setting_int('cleaning_cancel_free_hours', 24);
  v_rec record;
  v_antes record;
  v_depois record;
  v_devolve int;
begin
  if not exists (select 1 from cleaning_bookings
                 where recurrence_group_id = p_group_id and client_user_id = v_uid) then
    raise exception 'series_not_yours';
  end if;
  insert into cleaning_recurrence_stops (group_id, stopped_by)
  values (p_group_id, v_uid)
  on conflict (group_id) do nothing;
  for v_rec in
    select id from cleaning_bookings
    where recurrence_group_id = p_group_id
      and client_user_id = v_uid
      and status in ('scheduled', 'accepted')
      and team_slot = 1  -- 19/11/2026 equipa: a vaga 1 cancela as outras e tem o pagamento
      and scheduled_at > now() + make_interval(hours => v_free)
    order by scheduled_at
  loop
    begin
      -- Como estava ANTES de cancelar (o cancelamento passa 'held' a 'estornado').
      select payment_method, payment_status into v_antes
        from cleaning_bookings where id = v_rec.id for update;
      -- O mesmo cancelamento de uma limpeza só (taxa, estado do pagamento, aviso à profissional).
      perform public.cancel_cleaning_booking(v_rec.id, 'serie_terminada', false);
      -- 08/11/2026 (Danilo): a parte paga volta à CARTEIRA BORA, pelo caminho do cancelamento de
      -- um pedido (wallet_credit_refund_split). Dinheiro e prémio não têm nada a devolver.
      if v_antes.payment_method in ('card', 'mbway') and v_antes.payment_status = 'held' then
        select total_cents, coalesce(cancel_fee_cents, 0) as fee into v_depois
          from cleaning_bookings where id = v_rec.id;
        v_devolve := greatest(coalesce(v_depois.total_cents, 0) - v_depois.fee, 0);
        if v_devolve > 0 then
          perform public.wallet_credit_refund_split(
            v_rec.id::text, v_uid, v_devolve,
            'Limpeza cancelada ao parar a série: devolvido à Carteira Bora',
            'limpeza_serie_' || v_rec.id::text);
        end if;
      end if;
      v_count := v_count + 1;
    exception when others then
      -- Uma limpeza que mudou de estado entretanto (ou cujo crédito falhou) não trava o resto
      -- da série; o cancelamento dela desfaz-se com o bloco.
      raise warning 'cancel_cleaning_series: % saltada (%)', v_rec.id, sqlerrm;
    end;
  end loop;
  return v_count;
end
$function$;


-- ── Pedido de MB Way: só na vaga 1 ──
CREATE OR REPLACE FUNCTION public.cleaning_request_payment(p_booking_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_b   cleaning_bookings;
  v_url text;
  v_key text;
  v_n   int;
  v_req bigint;
BEGIN
  -- Servidor (cron/gatilho: sem sessão) ou admin. Cliente não: ele tem o botão próprio.
  IF auth.uid() IS NOT NULL
     AND (auth.jwt() -> 'app_metadata' ->> 'role') IS DISTINCT FROM 'admin' THEN
    RAISE EXCEPTION 'admin_required' USING ERRCODE = '42501';
  END IF;

  SELECT * INTO v_b FROM cleaning_bookings WHERE id = p_booking_id;
  IF v_b.id IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'booking_not_found');
  END IF;
  IF v_b.payment_method <> 'mbway' OR v_b.payment_status <> 'unpaid'
     OR v_b.status LIKE 'cancelled%'
     OR COALESCE(v_b.team_slot, 1) > 1 THEN  -- 19/11/2026 equipa: paga-se só na vaga 1
    RETURN jsonb_build_object('ok', false, 'error', 'not_requestable',
      'payment_method', v_b.payment_method, 'payment_status', v_b.payment_status,
      'status', v_b.status);
  END IF;

  -- Best-effort: nunca rebenta a transação de quem chama.
  BEGIN
    SELECT decrypted_secret INTO v_url FROM vault.decrypted_secrets WHERE name = 'project_url' LIMIT 1;
    SELECT decrypted_secret INTO v_key FROM vault.decrypted_secrets WHERE name = 'service_role_key' LIMIT 1;
    IF v_url IS NULL OR v_key IS NULL THEN
      RAISE WARNING 'cleaning_request_payment: vault project_url/service_role_key em falta';
      RETURN jsonb_build_object('ok', false, 'error', 'vault_missing');
    END IF;

    UPDATE cleaning_bookings
    SET payment_requested_at = now(),
        payment_request_count = payment_request_count + 1
    WHERE id = p_booking_id
    RETURNING payment_request_count INTO v_n;

    SELECT net.http_post(
      url := v_url || '/functions/v1/cleaning-request-payment',
      headers := jsonb_build_object('Content-Type', 'application/json',
                                    'Authorization', 'Bearer ' || v_key),
      body := jsonb_build_object('bookingId', p_booking_id::text, 'tentativa', v_n),
      timeout_milliseconds := 30000
    ) INTO v_req;

    RETURN jsonb_build_object('ok', true, 'request_id', v_req, 'tentativa', v_n);
  EXCEPTION WHEN OTHERS THEN
    RAISE WARNING 'cleaning_request_payment falhou (booking=%): %', p_booking_id, SQLERRM;
    RETURN jsonb_build_object('ok', false, 'error', SQLERRM);
  END;
END $function$;


-- ── Painel: atribuir/trocar a profissional de uma vaga à mão ──
CREATE OR REPLACE FUNCTION public.admin_assign_cleaning_cleaner(p_booking_id uuid, p_cleaner_id uuid, p_motivo text DEFAULT NULL)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_b cleaning_bookings;
  v_c cleaners;
  v_antiga uuid;
BEGIN
  PERFORM public._admin_op_guard();
  SELECT * INTO v_b FROM cleaning_bookings WHERE id = p_booking_id FOR UPDATE;
  IF v_b.id IS NULL THEN RAISE EXCEPTION 'booking_not_found'; END IF;
  IF v_b.status NOT IN ('scheduled','accepted') THEN
    RAISE EXCEPTION 'so_antes_de_comecar: estado %', v_b.status;
  END IF;
  SELECT * INTO v_c FROM cleaners WHERE id = p_cleaner_id;
  IF v_c.id IS NULL OR v_c.approval_status <> 'approved' THEN
    RAISE EXCEPTION 'profissional_invalida';
  END IF;
  IF v_b.cleaner_id = p_cleaner_id THEN
    RETURN (SELECT to_jsonb(b) FROM cleaning_bookings b WHERE b.id = p_booking_id);
  END IF;
  IF v_b.team_group_id IS NOT NULL AND EXISTS (
       SELECT 1 FROM cleaning_bookings t
        WHERE t.team_group_id = v_b.team_group_id AND t.id <> v_b.id
          AND t.status NOT LIKE 'cancelled%' AND t.cleaner_id = p_cleaner_id) THEN
    RAISE EXCEPTION 'ja_esta_noutra_vaga';
  END IF;
  v_antiga := v_b.cleaner_id;

  UPDATE cleaning_bookings
     SET cleaner_id = p_cleaner_id, status = 'accepted', accepted_at = now(),
         offer_cleaner_id = NULL, offer_expires_at = NULL,
         offered_cleaner_ids = CASE WHEN p_cleaner_id = ANY (offered_cleaner_ids)
                                    THEN offered_cleaner_ids ELSE offered_cleaner_ids || p_cleaner_id END
   WHERE id = p_booking_id;

  BEGIN
    INSERT INTO admin_audit_log(action, entity_type, entity_id, details)
    VALUES ('cleaning_assign_cleaner', 'cleaning_booking', p_booking_id::text,
            jsonb_build_object('cleaner_id', p_cleaner_id, 'antes', v_antiga,
                               'vaga', v_b.team_slot, 'motivo', p_motivo));
  EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'admin_assign_cleaning_cleaner: auditoria falhou (%)', sqlerrm;
  END;

  PERFORM public._cleaning_notify_user(v_c.user_id, 'cleaning_assigned',
    'Nova limpeza atribuída',
    'A Bora atribuiu-te a limpeza de ' ||
    to_char(v_b.scheduled_at AT TIME ZONE 'Europe/Lisbon', 'DD/MM às HH24:MI') ||
    ' — ganhas ' || (v_b.cleaner_earnings_cents / 100.0)::numeric(10,2) || ' EUR.',
    p_booking_id::text);
  IF v_antiga IS NOT NULL THEN
    PERFORM public._cleaning_notify_user((SELECT user_id FROM cleaners WHERE id = v_antiga),
      'cleaning_cancelled', 'Limpeza retirada',
      'A Bora passou a limpeza de ' ||
      to_char(v_b.scheduled_at AT TIME ZONE 'Europe/Lisbon', 'DD/MM HH24:MI') || ' a outra profissional.',
      p_booking_id::text);
  END IF;

  RETURN (SELECT to_jsonb(b) FROM cleaning_bookings b WHERE b.id = p_booking_id);
END $function$;

REVOKE EXECUTE ON FUNCTION public.admin_assign_cleaning_cleaner(uuid, uuid, text) FROM anon;
GRANT EXECUTE ON FUNCTION public.admin_assign_cleaning_cleaner(uuid, uuid, text) TO authenticated, service_role;

NOTIFY pgrst, 'reload schema';

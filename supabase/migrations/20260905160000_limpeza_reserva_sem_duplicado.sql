-- ============================================================================
-- LIMPEZA — a reserva deixa de poder nascer a dobrar
-- 2026-09-05
-- ----------------------------------------------------------------------------
-- O QUE ISTO FAZ, EM PORTUGUES SIMPLES
--
-- Marcar uma limpeza nao tinha guarda nenhuma do lado do servidor. Ao mesmo
-- tempo, o app tem um mecanismo que, quando um pedido demora demais, o repete
-- uma vez — e esse mecanismo conta com uma guarda do servidor que aqui nao
-- existia. Resultado: um pedido lento podia criar DUAS reservas, o cliente
-- pagava duas vezes e apareciam duas profissionais na mesma casa.
--
-- A partir daqui, marcar a mesma limpeza duas vezes devolve a MESMA reserva:
--
--   1. O app manda uma chave (uma por marcacao). Se o pedido for repetido com a
--      mesma chave, o servidor devolve a reserva que ja criou.
--   2. Se nao vier chave nenhuma (versoes antigas da app), o servidor compara o
--      conteudo: mesmo cliente, mesmo tipo de limpeza, mesma hora, mesma morada,
--      nos ultimos 15 minutos, e ainda por cancelar. Se ja existir, devolve essa.
--
-- Duas chamadas ao mesmo tempo ficam em fila numa fechadura, por isso nem a
-- corrida de rede escapa.
--
-- NAO MUDA DINHEIRO: nenhum preco, taxa, comissao ou valor cobrado foi tocado.
-- O orcamento continua a vir de cleaning_quote, exactamente como antes.
-- ============================================================================

-- 1) Onde a chave fica guardada -----------------------------------------------
ALTER TABLE public.cleaning_bookings
  ADD COLUMN IF NOT EXISTS idempotency_key text;

COMMENT ON COLUMN public.cleaning_bookings.idempotency_key IS
  'Chave enviada pelo app, uma por marcacao. Impede que uma repeticao de rede crie uma segunda reserva.';

-- Trava dura: o mesmo cliente nao pode ter duas reservas com a mesma chave.
CREATE UNIQUE INDEX IF NOT EXISTS ux_cleaning_bookings_idem
  ON public.cleaning_bookings (client_user_id, idempotency_key)
  WHERE idempotency_key IS NOT NULL;

-- 2) A funcao ------------------------------------------------------------------
-- Assinatura antiga cai para nao ficarem duas funcoes com o mesmo nome (a API
-- nao saberia qual chamar). A nova tem a chave com valor por omissao, por isso
-- as chamadas que ja existem continuam a funcionar sem alteracao nenhuma.
DROP FUNCTION IF EXISTS public.create_cleaning_booking(
  text, text, text, integer, timestamptz, text, text, text,
  text, text, text, double precision, double precision, text, uuid);

CREATE OR REPLACE FUNCTION public.create_cleaning_booking(
  p_cleaning_type text,
  p_pricing_mode text,
  p_home_size text,
  p_hours integer,
  p_scheduled_at timestamp with time zone,
  p_recurrence text,
  p_products_by text,
  p_payment_method text,
  p_address_street text,
  p_address_city text,
  p_address_postal text,
  p_lat double precision,
  p_lng double precision,
  p_notes text DEFAULT ''::text,
  p_requested_cleaner_id uuid DEFAULT NULL::uuid,
  p_idempotency_key text DEFAULT NULL::text
)
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
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'not_authenticated' USING ERRCODE = '42501';
  END IF;

  -- ── GUARDA 1: mesma chave, mesma reserva ──────────────────────────────────
  IF v_key IS NOT NULL THEN
    SELECT b.id INTO v_ja FROM cleaning_bookings b
     WHERE b.client_user_id = v_uid AND b.idempotency_key = v_key
     LIMIT 1;
    IF v_ja IS NOT NULL THEN
      RETURN (SELECT to_jsonb(b) FROM cleaning_bookings b WHERE b.id = v_ja);
    END IF;
  END IF;

  -- Fechadura por conteudo: duas chamadas iguais ao mesmo tempo ficam em fila,
  -- por isso a segunda ja ve a reserva que a primeira criou. Solta-se sozinha
  -- no fim da transaccao.
  v_assinatura := v_uid::text || '|' || COALESCE(v_key, '')
    || '|' || COALESCE(p_cleaning_type,'') || '|' || COALESCE(p_pricing_mode,'')
    || '|' || COALESCE(p_home_size,'')     || '|' || COALESCE(p_hours::text,'')
    || '|' || COALESCE(p_scheduled_at::text,'')
    || '|' || COALESCE(p_address_street,'') || '|' || COALESCE(p_address_postal,'');
  PERFORM pg_advisory_xact_lock(hashtextextended(v_assinatura, 0));

  -- Repete a leitura da chave DEPOIS da fechadura (a primeira pode ter entrado
  -- entretanto).
  IF v_key IS NOT NULL THEN
    SELECT b.id INTO v_ja FROM cleaning_bookings b
     WHERE b.client_user_id = v_uid AND b.idempotency_key = v_key
     LIMIT 1;
    IF v_ja IS NOT NULL THEN
      RETURN (SELECT to_jsonb(b) FROM cleaning_bookings b WHERE b.id = v_ja);
    END IF;
  END IF;

  -- ── GUARDA 2: sem chave, compara-se o conteudo (app antiga) ───────────────
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
     ORDER BY b.created_at DESC
     LIMIT 1;
    IF v_ja IS NOT NULL THEN
      RETURN (SELECT to_jsonb(b) FROM cleaning_bookings b WHERE b.id = v_ja);
    END IF;
  END IF;

  -- ── daqui para baixo: exactamente o que ja fazia ──────────────────────────
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

  v_quote := public.cleaning_quote(p_cleaning_type, p_pricing_mode, p_home_size,
                                   p_hours, p_recurrence, p_products_by);

  IF p_recurrence IN ('weekly','biweekly') THEN
    v_group := gen_random_uuid();
  END IF;

  INSERT INTO cleaning_bookings (
    client_user_id, requested_cleaner_id, recurrence_group_id, recurrence,
    cleaning_type, pricing_mode, home_size, hours, scheduled_at, duration_min,
    address_street, address_city, address_postal, lat, lng, notes, products_by,
    payment_method, payment_status,
    base_cents, type_surcharge_cents, recurring_discount_cents, products_fee_cents,
    total_cents, cleaner_earnings_cents, bora_fee_cents,
    idempotency_key
  ) VALUES (
    v_uid, p_requested_cleaner_id, v_group, p_recurrence,
    p_cleaning_type, p_pricing_mode, p_home_size,
    CASE WHEN p_pricing_mode = 'hourly' THEN p_hours END,
    p_scheduled_at, (v_quote ->> 'duration_min')::int,
    COALESCE(p_address_street,''), COALESCE(p_address_city,''), COALESCE(p_address_postal,''),
    p_lat, p_lng, COALESCE(p_notes,''), p_products_by,
    p_payment_method, 'unpaid',
    (v_quote ->> 'base_cents')::int, (v_quote ->> 'type_surcharge_cents')::int,
    (v_quote ->> 'recurring_discount_cents')::int, (v_quote ->> 'products_fee_cents')::int,
    (v_quote ->> 'total_cents')::int, (v_quote ->> 'cleaner_earnings_cents')::int,
    (v_quote ->> 'bora_fee_cents')::int,
    v_key
  ) RETURNING id INTO v_id;

  PERFORM public._cleaning_next_offer(v_id);

  RETURN (SELECT to_jsonb(b) FROM cleaning_bookings b WHERE b.id = v_id);

EXCEPTION
  -- Rede de seguranca final: se mesmo assim duas escritas com a mesma chave
  -- chegarem ao indice, a segunda devolve a primeira em vez de rebentar.
  WHEN unique_violation THEN
    SELECT b.id INTO v_ja FROM cleaning_bookings b
     WHERE b.client_user_id = v_uid AND b.idempotency_key = v_key
     LIMIT 1;
    IF v_ja IS NOT NULL THEN
      RETURN (SELECT to_jsonb(b) FROM cleaning_bookings b WHERE b.id = v_ja);
    END IF;
    RAISE;
END $function$;

GRANT EXECUTE ON FUNCTION public.create_cleaning_booking(
  text, text, text, integer, timestamptz, text, text, text,
  text, text, text, double precision, double precision, text, uuid, text
) TO authenticated;

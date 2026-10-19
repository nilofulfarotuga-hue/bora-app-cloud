-- ============================================================================
-- Limpeza semanal: a profissional só é chamada depois de a limpeza estar paga,
-- e a série segue o dia e a hora que o cliente marcou (hora de Lisboa).
-- 19/10/2026 · missão limpeza-semanal-pagamento-19-10
-- Autorização do Danilo (19/10/2026, literal): "autorizo arrumar as limpezas semanais"
--   + "Pode" + "o divã tem que fazer o pagamento do MBA. E aí tem que chegar a
--   notificação no telemóvel dele, no MBA dele, para ele fazer o pagamento."
-- NÃO muda nenhum preço nem comissão: o valor continua a vir de cleaning_quote.
--
-- a) cleaning_bookings: payment_requested_at, payment_request_count, unpaid_admin_alerted_at
-- b) _cleaning_next_offer: MB Way/cartão por pagar → não chama ninguém (sai logo)
-- c) trg_cleaning_paid_offer: quando passa de unpaid a held → chama a profissional
-- d) generate_recurring_bookings: próxima data a partir da 1.ª reserva da série, em hora
--    de Lisboa (um reagendamento pontual não arrasta as seguintes; a mudança da hora não
--    desloca a hora marcada); MB Way → pede o pagamento ao cliente na hora
-- e) cleaning_request_payment(id): chama a Edge cleaning-request-payment (pg_net)
-- f) cron cleaning-unpaid-retry (de hora a hora): volta a pedir e avisa o admin a <24h
-- ============================================================================

-- a) ------------------------------------------------------------------------
ALTER TABLE public.cleaning_bookings
  ADD COLUMN IF NOT EXISTS payment_requested_at timestamptz,
  ADD COLUMN IF NOT EXISTS payment_request_count int NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS unpaid_admin_alerted_at timestamptz;

COMMENT ON COLUMN public.cleaning_bookings.payment_requested_at IS
  'Último pedido de MB Way enviado ao cliente (cleaning_request_payment). 19/10/2026.';
COMMENT ON COLUMN public.cleaning_bookings.payment_request_count IS
  'Quantos pedidos de MB Way já foram enviados ao cliente. 19/10/2026.';
COMMENT ON COLUMN public.cleaning_bookings.unpaid_admin_alerted_at IS
  'Quando o admin foi avisado de que a limpeza está a <24h e por pagar (uma vez). 19/10/2026.';

-- b) ------------------------------------------------------------------------
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
    ' — ' || (v_b.total_cents / 100.0)::numeric(10,2) || ' EUR. Tens ' || v_timeout || ' min para aceitar.',
    p_booking_id::text);
END $function$;

-- c) ------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public._trg_cleaning_paid_offer()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
  IF OLD.payment_status = 'unpaid' AND NEW.payment_status = 'held'
     AND NEW.status = 'scheduled'
     AND NEW.cleaner_id IS NULL AND NEW.offer_cleaner_id IS NULL THEN
    BEGIN
      PERFORM public._cleaning_next_offer(NEW.id);
    EXCEPTION WHEN OTHERS THEN
      -- Nunca desfaz o registo do pagamento por causa da oferta.
      RAISE WARNING '_trg_cleaning_paid_offer: oferta falhou (booking=%): %', NEW.id, SQLERRM;
    END;
  END IF;
  RETURN NULL;
END $function$;

DROP TRIGGER IF EXISTS trg_cleaning_paid_offer ON public.cleaning_bookings;
CREATE TRIGGER trg_cleaning_paid_offer
  AFTER UPDATE OF payment_status ON public.cleaning_bookings
  FOR EACH ROW EXECUTE FUNCTION public._trg_cleaning_paid_offer();

-- e) ------------------------------------------------------------------------
-- Antes do d), porque o d) chama-a.
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
     OR v_b.status LIKE 'cancelled%' THEN
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

REVOKE ALL ON FUNCTION public.cleaning_request_payment(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.cleaning_request_payment(uuid) TO authenticated, service_role;

-- d) ------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.generate_recurring_bookings()
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_count int := 0; v_rec record; v_last cleaning_bookings; v_first cleaning_bookings;
  v_next timestamptz; v_quote jsonb; v_id uuid; v_interval interval;
  v_anchor timestamp; v_last_local timestamp; v_k int; v_n int;
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
    ORDER BY scheduled_at DESC LIMIT 1;

    CONTINUE WHEN v_last.status = 'cancelled_client' AND v_last.cancelled_by IN ('client','admin');

    v_interval := CASE v_last.recurrence WHEN 'weekly' THEN interval '7 days'
                                         ELSE interval '14 days' END;

    -- 19/10/2026: a série segue o dia e a hora da 1.ª reserva, em hora de Lisboa.
    -- Antes era "última + 7 dias" em UTC: um reagendamento pontual passava para as
    -- seguintes e a mudança da hora deslocava-a uma hora.
    SELECT * INTO v_first FROM cleaning_bookings
    WHERE recurrence_group_id = v_rec.gid
    ORDER BY created_at ASC LIMIT 1;

    v_anchor     := v_first.scheduled_at AT TIME ZONE 'Europe/Lisbon';
    v_last_local := v_last.scheduled_at AT TIME ZONE 'Europe/Lisbon';
    v_k := floor(extract(epoch FROM (v_last_local - v_anchor))
                 / extract(epoch FROM v_interval))::int + 1;
    -- Cada reserva da série ocupa uma vez da série (a n-ésima criada é a vez n-1). Se a
    -- última foi puxada para trás (ex.: sábado → sexta), a conta de cima voltaria a cair
    -- na mesma semana; o número de reservas impede essa repetição.
    SELECT count(*) INTO v_n FROM cleaning_bookings WHERE recurrence_group_id = v_rec.gid;
    v_k := GREATEST(v_k, v_n, 1);
    v_next := (v_anchor + v_interval * v_k) AT TIME ZONE 'Europe/Lisbon';

    CONTINUE WHEN v_next - now() > interval '7 days';
    CONTINUE WHEN v_next < now();

    v_quote := public.cleaning_quote(v_last.cleaning_type, v_last.pricing_mode,
                                     v_last.home_size, v_last.hours,
                                     v_last.recurrence, v_last.products_by);

    INSERT INTO cleaning_bookings (
      client_user_id, requested_cleaner_id, recurrence_group_id, recurrence,
      cleaning_type, pricing_mode, home_size, hours, scheduled_at, duration_min,
      address_street, address_city, address_postal, lat, lng, notes, products_by,
      payment_method, payment_status,
      base_cents, type_surcharge_cents, recurring_discount_cents, products_fee_cents,
      total_cents, cleaner_earnings_cents, bora_fee_cents
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
      (v_quote ->> 'recurring_discount_cents')::int, (v_quote ->> 'products_fee_cents')::int,
      (v_quote ->> 'total_cents')::int, (v_quote ->> 'cleaner_earnings_cents')::int,
      (v_quote ->> 'bora_fee_cents')::int
    ) RETURNING id INTO v_id;

    -- Dinheiro: chama já. MB Way/cartão: _cleaning_next_offer sai logo (por pagar).
    PERFORM public._cleaning_next_offer(v_id);

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
  END LOOP;
  RETURN v_count;
END $function$;

-- f) ------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public._cleaning_cron_unpaid_retry()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  r record;
  v_pedidos int := 0;
  v_avisos  int := 0;
BEGIN
  FOR r IN
    SELECT b.id, b.client_user_id, b.scheduled_at, b.total_cents,
           b.payment_requested_at, b.payment_request_count, b.unpaid_admin_alerted_at,
           u.email, pu.name AS cliente_nome
    FROM cleaning_bookings b
    LEFT JOIN auth.users u ON u.id = b.client_user_id
    LEFT JOIN public.users pu ON pu.id = b.client_user_id
    WHERE b.status = 'scheduled'
      AND b.payment_method = 'mbway'
      AND b.payment_status = 'unpaid'
      AND b.cancelled_at IS NULL
      AND b.scheduled_at > now() + interval '2 hours'
      AND NOT COALESCE(b.is_test_order, false)  -- nunca mandar MB Way a partir de reservas de teste
  LOOP
    IF r.payment_requested_at IS NULL OR r.payment_request_count = 0
       OR (r.payment_requested_at < now() - interval '12 hours' AND r.payment_request_count < 4) THEN
      PERFORM public.cleaning_request_payment(r.id);
      v_pedidos := v_pedidos + 1;
    END IF;

    IF r.scheduled_at < now() + interval '24 hours' AND r.unpaid_admin_alerted_at IS NULL THEN
      BEGIN
        PERFORM public.notify_admin_urgent_push(
          'cleaning_unpaid',
          '💶 LIMPEZA POR PAGAR (MB Way) · ' || COALESCE(NULLIF(r.cliente_nome, ''), r.email, 'cliente')
            || E'\n' || 'Cliente ' || COALESCE(r.email, r.client_user_id::text)
            || ' — limpeza de ' || to_char(r.scheduled_at AT TIME ZONE 'Europe/Lisbon', 'DD/MM "às" HH24:MI')
            || ', ' || (r.total_cents / 100.0)::numeric(10,2) || ' €. Ainda não pagou; a profissional não foi chamada. '
            || 'Pedidos MB Way enviados: ' || r.payment_request_count || '.',
          'cleaning_booking', r.id::text,
          jsonb_build_object('booking_id', r.id, 'client_user_id', r.client_user_id,
                             'email', r.email, 'scheduled_at', r.scheduled_at,
                             'total_cents', r.total_cents,
                             'payment_request_count', r.payment_request_count),
          '/admin/limpeza/' || r.id::text);
        UPDATE cleaning_bookings SET unpaid_admin_alerted_at = now() WHERE id = r.id;
        v_avisos := v_avisos + 1;
      EXCEPTION WHEN OTHERS THEN
        RAISE WARNING '_cleaning_cron_unpaid_retry: aviso ao admin falhou (booking=%): %', r.id, SQLERRM;
      END;
    END IF;
  END LOOP;
  RETURN jsonb_build_object('pedidos', v_pedidos, 'avisos_admin', v_avisos);
END $function$;

REVOKE ALL ON FUNCTION public._cleaning_cron_unpaid_retry() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public._trg_cleaning_paid_offer() FROM PUBLIC, anon, authenticated;

SELECT cron.unschedule(jobid) FROM cron.job WHERE jobname = 'cleaning-unpaid-retry';
SELECT cron.schedule('cleaning-unpaid-retry', '20 * * * *',
                     'SELECT public._cleaning_cron_unpaid_retry();');

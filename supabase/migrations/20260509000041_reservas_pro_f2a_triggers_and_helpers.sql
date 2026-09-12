-- ═══════════════════════════════════════════════════════════
-- RESERVAS PRO F2.A — Triggers + Helpers DB
-- Data: 2026-05-08 / Sessao reservas-pro-F2-BACKEND-CORE
--
-- 6 funcoes helper + 5 triggers (4 reservations + 1 waitlist).
--
-- Notificacoes ao parceiro nos momentos certos:
-- 1. Nova reserva pendente (INSERT)
-- 2. Cliente cancelou <2h (late cancel) + auto-match notify list
-- 3. Walk-in entrou waitlist (INSERT)
-- 4. Cliente sentou-se (UPDATE seated_at) -> push cliente
-- 5. Reserva terminou (UPDATE finished_at) -> auto-update profile
--
-- pg_net + pg_cron disponiveis para FCM real e CRON jobs (F2.D).
-- ═══════════════════════════════════════════════════════════

-- ─── HELPER 1: Get partner user_id ─────────────────────────
CREATE OR REPLACE FUNCTION public._reservas_pro_get_partner_user_id(p_restaurant_id text)
RETURNS uuid LANGUAGE sql STABLE SECURITY DEFINER SET search_path='public' AS $$
  SELECT user_ FROM restaurants WHERE id = p_restaurant_id;
$$;

COMMENT ON FUNCTION public._reservas_pro_get_partner_user_id IS
  'Devolve user_ do dono do restaurante. NULL se restaurante nao existe ou sem dono.';

-- ─── HELPER 2: Get turn time (minutos por party size) ───────
CREATE OR REPLACE FUNCTION public._reservas_pro_get_turn_time(
  p_restaurant_id text,
  p_party_size integer,
  p_day_of_week integer DEFAULT NULL
)
RETURNS integer LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='public' AS $$
DECLARE
  v_minutes integer;
  v_dow integer := COALESCE(p_day_of_week, EXTRACT(DOW FROM NOW())::integer);
  v_default_2 integer;
  v_default_4 integer;
  v_default_6 integer;
BEGIN
  -- Tenta turn time configurado pelo parceiro
  SELECT minutes INTO v_minutes
  FROM restaurant_turn_times
  WHERE restaurant_id = p_restaurant_id
    AND active = true
    AND p_party_size BETWEEN party_size_min AND party_size_max
    AND (day_of_week IS NULL OR day_of_week = v_dow)
  ORDER BY day_of_week NULLS LAST
  LIMIT 1;

  IF v_minutes IS NOT NULL THEN
    RETURN v_minutes;
  END IF;

  -- Fallback: defaults globais em platform_settings
  SELECT (value::text)::integer INTO v_default_2 FROM platform_settings WHERE key = 'reservation_default_turn_time_2';
  SELECT (value::text)::integer INTO v_default_4 FROM platform_settings WHERE key = 'reservation_default_turn_time_4';
  SELECT (value::text)::integer INTO v_default_6 FROM platform_settings WHERE key = 'reservation_default_turn_time_6_plus';

  IF p_party_size <= 3 THEN RETURN COALESCE(v_default_2, 90); END IF;
  IF p_party_size <= 5 THEN RETURN COALESCE(v_default_4, 120); END IF;
  RETURN COALESCE(v_default_6, 150);
END;
$$;

COMMENT ON FUNCTION public._reservas_pro_get_turn_time IS
  'Devolve turn time em minutos para party_size. Tenta config parceiro primeiro, depois defaults globais (90/120/150).';

-- ─── HELPER 3: Push parceiro combinado (in-app + FCM) ───────
CREATE OR REPLACE FUNCTION public._reservas_pro_notify_partner_push(
  p_partner_user_id uuid,
  p_kind text,
  p_title text,
  p_body text,
  p_related_id text
)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path='public' AS $$
BEGIN
  IF p_partner_user_id IS NULL THEN RETURN; END IF;

  -- 1. In-app notification (sempre)
  PERFORM _push_in_app_notification(p_partner_user_id, p_kind, p_title, p_body, p_related_id);

  -- 2. FCM push via Edge Function notify-partner (se quiser activar push real)
  -- Comentado por agora — activar depois com Firebase Service Account configurado.
  -- PERFORM net.http_post(
  --   url := current_setting('app.supabase_url') || '/functions/v1/notify-partner',
  --   headers := jsonb_build_object('Content-Type','application/json'),
  --   body := jsonb_build_object('user_id', p_partner_user_id, 'title', p_title, 'body', p_body, 'kind', p_kind)
  -- );
END;
$$;

COMMENT ON FUNCTION public._reservas_pro_notify_partner_push IS
  'Wrapper unificado: insere in_app_notifications. FCM push real comentado ate Firebase config (post-launch).';

-- ─── HELPER 4: Match notify list quando vagar (auto OpenTable) ──
CREATE OR REPLACE FUNCTION public._reservas_pro_match_notify_list(
  p_restaurant_id text,
  p_slot_time timestamptz,
  p_people integer
)
RETURNS integer LANGUAGE plpgsql SECURITY DEFINER SET search_path='public' AS $$
DECLARE
  v_count integer := 0;
  v_record record;
BEGIN
  -- Procura clientes na notify list compativeis (mesmo restaurante, janela target_time +/- flexibility, party size <=, status=active)
  FOR v_record IN
    SELECT id, client_user_id, target_time, flexibility_minutes, people
    FROM reservation_notify_list
    WHERE restaurant_id = p_restaurant_id
      AND status = 'active'
      AND target_date = p_slot_time::date
      AND people <= p_people
      AND ABS(EXTRACT(EPOCH FROM (target_time - p_slot_time::time)) / 60) <= flexibility_minutes
      AND expires_at > NOW()
    ORDER BY created_at ASC
    LIMIT 5  -- max 5 clientes notificados (FIFO)
  LOOP
    -- Marca como notified
    UPDATE reservation_notify_list
    SET status = 'notified', notified_at = NOW()
    WHERE id = v_record.id;

    -- Push cliente: "vagou! confirma em 15min"
    PERFORM _push_in_app_notification(
      v_record.client_user_id,
      'reservation_notify_match',
      'Vagou! Mesa disponivel',
      'Tens 15min para confirmar a reserva no horario que pediste.',
      v_record.id::text
    );

    v_count := v_count + 1;
  END LOOP;

  RETURN v_count;
END;
$$;

COMMENT ON FUNCTION public._reservas_pro_match_notify_list IS
  'Quando ha cancelamento, procura clientes na notify_list compativeis e manda push (max 5 FIFO). Modelo OpenTable Notify.';

-- ─── HELPER 5: Auto-update client profile ───────────────────
CREATE OR REPLACE FUNCTION public._reservas_pro_update_client_profile(
  p_client_user_id uuid,
  p_restaurant_id text,
  p_action text  -- 'visit' | 'no_show' | 'late_cancel'
)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path='public' AS $$
DECLARE
  v_threshold_no_show integer;
  v_threshold_late integer;
  v_total_no_show integer;
  v_total_late integer;
  v_total_visits integer;
BEGIN
  -- Upsert profile
  INSERT INTO client_restaurant_profiles (client_user_id, restaurant_id)
  VALUES (p_client_user_id, p_restaurant_id)
  ON CONFLICT (client_user_id, restaurant_id) DO NOTHING;

  -- Update counters
  IF p_action = 'visit' THEN
    UPDATE client_restaurant_profiles
    SET total_visits = total_visits + 1, last_visit_at = NOW()
    WHERE client_user_id = p_client_user_id AND restaurant_id = p_restaurant_id
    RETURNING total_visits INTO v_total_visits;

    -- Auto-VIP apos 5 visits
    IF v_total_visits >= 5 THEN
      UPDATE client_restaurant_profiles
      SET is_vip = true
      WHERE client_user_id = p_client_user_id AND restaurant_id = p_restaurant_id AND is_vip = false;
    END IF;

  ELSIF p_action = 'no_show' THEN
    UPDATE client_restaurant_profiles
    SET total_no_shows = total_no_shows + 1
    WHERE client_user_id = p_client_user_id AND restaurant_id = p_restaurant_id
    RETURNING total_no_shows INTO v_total_no_show;

    -- Auto-block apos N no-shows (config platform_settings)
    SELECT (value::text)::integer INTO v_threshold_no_show
    FROM platform_settings WHERE key = 'reservation_no_show_threshold_count';
    v_threshold_no_show := COALESCE(v_threshold_no_show, 3);

    IF v_total_no_show >= v_threshold_no_show THEN
      UPDATE client_restaurant_profiles
      SET is_blocked = true, blocked_reason = 'auto_no_show_threshold', blocked_at = NOW()
      WHERE client_user_id = p_client_user_id AND restaurant_id = p_restaurant_id AND is_blocked = false;
    END IF;

  ELSIF p_action = 'late_cancel' THEN
    UPDATE client_restaurant_profiles
    SET total_late_cancels = total_late_cancels + 1
    WHERE client_user_id = p_client_user_id AND restaurant_id = p_restaurant_id
    RETURNING total_late_cancels INTO v_total_late;

    SELECT (value::text)::integer INTO v_threshold_late
    FROM platform_settings WHERE key = 'reservation_late_cancel_threshold_count';
    v_threshold_late := COALESCE(v_threshold_late, 5);

    IF v_total_late >= v_threshold_late THEN
      UPDATE client_restaurant_profiles
      SET is_blocked = true, blocked_reason = 'auto_late_cancel_threshold', blocked_at = NOW()
      WHERE client_user_id = p_client_user_id AND restaurant_id = p_restaurant_id AND is_blocked = false;
    END IF;
  END IF;
END;
$$;

COMMENT ON FUNCTION public._reservas_pro_update_client_profile IS
  'Incrementa contadores no client_restaurant_profiles. Auto-VIP apos 5 visits. Auto-block segundo platform_settings thresholds.';

-- ─── TRIGGER 1: Nova reserva -> push parceiro ───────────────
CREATE OR REPLACE FUNCTION public._reservas_pro_trg_notify_new()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path='public' AS $$
DECLARE
  v_partner_user_id uuid;
BEGIN
  v_partner_user_id := _reservas_pro_get_partner_user_id(NEW.restaurant_id);

  PERFORM _reservas_pro_notify_partner_push(
    v_partner_user_id,
    'reservation_new_pending',
    'Nova reserva pendente',
    NEW.client_name || ' • ' || NEW.people || ' pessoas • ' ||
      to_char(NEW.reserved_for, 'DD/MM HH24:MI'),
    NEW.id::text
  );

  RETURN NEW;
END;
$$;

CREATE TRIGGER trg_reservation_notify_partner_new
  AFTER INSERT ON public.reservations
  FOR EACH ROW
  WHEN (NEW.status = 'pending')
  EXECUTE FUNCTION public._reservas_pro_trg_notify_new();

-- ─── TRIGGER 2: Late cancel + auto-match notify list ────────
CREATE OR REPLACE FUNCTION public._reservas_pro_trg_late_cancel()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path='public' AS $$
DECLARE
  v_partner_user_id uuid;
  v_hours_until numeric;
  v_matched integer;
BEGIN
  -- So dispara se status mudou para cancelado
  IF NEW.status NOT IN ('cancelled_refunded','cancelled_no_refund','cancelled') THEN
    RETURN NEW;
  END IF;

  IF OLD.status IN ('cancelled_refunded','cancelled_no_refund','cancelled') THEN
    RETURN NEW;
  END IF;

  v_hours_until := EXTRACT(EPOCH FROM (NEW.reserved_for - NOW())) / 3600;

  -- Late cancel: <2h antes
  IF v_hours_until BETWEEN 0 AND 2 THEN
    v_partner_user_id := _reservas_pro_get_partner_user_id(NEW.restaurant_id);

    PERFORM _reservas_pro_notify_partner_push(
      v_partner_user_id,
      'reservation_late_cancel',
      'Cancelamento tardio (oportunidade)',
      'Mesa ' || NEW.people || ' pessoas livre as ' || to_char(NEW.reserved_for, 'HH24:MI'),
      NEW.id::text
    );

    -- Update profile cliente: late_cancel
    PERFORM _reservas_pro_update_client_profile(NEW.client_user_id, NEW.restaurant_id, 'late_cancel');

    -- Auto-match notify list (modelo OpenTable Notify)
    v_matched := _reservas_pro_match_notify_list(NEW.restaurant_id, NEW.reserved_for, NEW.people);

    -- Push parceiro extra se foram notificados clientes
    IF v_matched > 0 THEN
      PERFORM _reservas_pro_notify_partner_push(
        v_partner_user_id,
        'reservation_notify_dispatched',
        'Notify list activada',
        v_matched || ' clientes notificados — possivel substituicao automatica',
        NEW.id::text
      );
    END IF;
  END IF;

  RETURN NEW;
END;
$$;

CREATE TRIGGER trg_reservation_late_cancel
  AFTER UPDATE OF status ON public.reservations
  FOR EACH ROW
  EXECUTE FUNCTION public._reservas_pro_trg_late_cancel();

-- ─── TRIGGER 3: Mesa pronta (seated_at) -> push cliente ─────
CREATE OR REPLACE FUNCTION public._reservas_pro_trg_seated()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path='public' AS $$
BEGIN
  IF NEW.seated_at IS NOT NULL AND OLD.seated_at IS NULL THEN
    PERFORM _push_in_app_notification(
      NEW.client_user_id,
      'reservation_seated',
      'Mesa pronta!',
      'O parceiro ja te sentou. Bom apetite!',
      NEW.id::text
    );
  END IF;
  RETURN NEW;
END;
$$;

CREATE TRIGGER trg_reservation_seated
  AFTER UPDATE OF seated_at ON public.reservations
  FOR EACH ROW
  EXECUTE FUNCTION public._reservas_pro_trg_seated();

-- ─── TRIGGER 4: Reserva terminada -> update profile ─────────
CREATE OR REPLACE FUNCTION public._reservas_pro_trg_finished()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path='public' AS $$
BEGIN
  IF NEW.finished_at IS NOT NULL AND OLD.finished_at IS NULL THEN
    PERFORM _reservas_pro_update_client_profile(NEW.client_user_id, NEW.restaurant_id, 'visit');
  END IF;
  RETURN NEW;
END;
$$;

CREATE TRIGGER trg_reservation_finished
  AFTER UPDATE OF finished_at ON public.reservations
  FOR EACH ROW
  EXECUTE FUNCTION public._reservas_pro_trg_finished();

-- ─── TRIGGER 5: Walk-in waitlist -> push parceiro ───────────
CREATE OR REPLACE FUNCTION public._reservas_pro_trg_waitlist_new()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path='public' AS $$
DECLARE
  v_partner_user_id uuid;
BEGIN
  v_partner_user_id := _reservas_pro_get_partner_user_id(NEW.restaurant_id);

  PERFORM _reservas_pro_notify_partner_push(
    v_partner_user_id,
    'waitlist_new',
    'Novo cliente em espera',
    NEW.client_name || ' • ' || NEW.people || ' pessoas • ' || NEW.target_date::text,
    NEW.id::text
  );

  RETURN NEW;
END;
$$;

CREATE TRIGGER trg_waitlist_notify_partner_new
  AFTER INSERT ON public.reservation_waitlist
  FOR EACH ROW
  WHEN (NEW.status = 'waiting')
  EXECUTE FUNCTION public._reservas_pro_trg_waitlist_new();
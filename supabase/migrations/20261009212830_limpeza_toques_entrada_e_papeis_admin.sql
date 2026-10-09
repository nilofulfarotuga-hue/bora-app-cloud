-- [09/10/2026 · missão fecho-total-2026-10-09 · Bloco 4] Limpeza: toques da oferta, entrada
-- certa por papel e o painel do admin. Não mexe em valores nem no despacho do estafeta/TVDE.
--
-- 1. cleaning_offer_pings — cada toque da oferta de limpeza (o primeiro aviso e as repetições do
--    cron cleaning-offer-reping). Só as funções do servidor escrevem e leem (RLS sem políticas).
-- 2. _cleaning_notify_user — regista o toque quando o aviso é uma oferta (o resto igual ao ar).
-- 3. _cleaning_cron_offer_reping — regista cada repetição; o texto passa a dizer o GANHO da
--    profissional (cleaner_earnings_cents), não o total do cliente — regra de ouro do prestador.
-- 4. my_trabalho_pendente() — por papel aprovado, se há trabalho à espera (oferta viva ou
--    trabalho de hoje / em curso; estafeta: ligado ou com entrega em curso). A app usa-o para
--    abrir no papel certo.
-- 5. admin_cleaning_offers(), admin_user_roles(), admin_set_user_role(), admin_set_cleaning_offer_reping()
--    — painel admin (PT-BR): ofertas com toques e aparelho; ver e ligar/desligar cada papel com
--    motivo e registo em admin_audit_log; interruptor do toque repetido.
-- Funções novas nascem fechadas a anon (regra 05/10): só authenticated, e as de admin validam is_admin().

CREATE TABLE IF NOT EXISTS public.cleaning_offer_pings (
  id              bigserial PRIMARY KEY,
  booking_id      text        NOT NULL,
  cleaner_user_id uuid,
  origem          text        NOT NULL DEFAULT 'oferta' CHECK (origem IN ('oferta','repeticao')),
  created_at      timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS cleaning_offer_pings_booking_idx
  ON public.cleaning_offer_pings (booking_id, cleaner_user_id, created_at DESC);
ALTER TABLE public.cleaning_offer_pings ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.cleaning_offer_pings FROM anon, authenticated;
COMMENT ON TABLE public.cleaning_offer_pings IS
  'Cada toque da oferta de limpeza (primeiro aviso e repeticoes). Painel: admin_cleaning_offers().';

CREATE OR REPLACE FUNCTION public._cleaning_notify_user(p_user_id uuid, p_kind text, p_title text, p_body text, p_booking_id text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_url  text;
  v_key  text;
  v_type text;
BEGIN
  IF p_user_id IS NULL THEN RETURN; END IF;

  v_type := CASE
    WHEN p_kind ILIKE '%offer%' OR p_kind ILIKE '%oferta%' THEN 'cleaning_offer'
    ELSE 'cleaning_status'
  END;

  -- [09/10/2026] Conta o toque da oferta (painel: "tocou N vezes"). Nunca parte o aviso.
  IF v_type = 'cleaning_offer' AND COALESCE(p_booking_id, '') <> '' THEN
    BEGIN
      INSERT INTO public.cleaning_offer_pings (booking_id, cleaner_user_id, origem)
      VALUES (p_booking_id, p_user_id, 'oferta');
    EXCEPTION WHEN OTHERS THEN
      RAISE WARNING '_cleaning_notify_user: toque nao registado (booking=%): %', p_booking_id, SQLERRM;
    END;
  END IF;

  BEGIN
    PERFORM public._push_in_app_notification(p_user_id, p_kind, p_title, p_body, p_booking_id);
  EXCEPTION WHEN OTHERS THEN
    INSERT INTO public.notification_failures (user_id, kind, source, erro)
    VALUES (p_user_id, p_kind, '_cleaning_notify_user:in_app', SQLERRM);
    RAISE WARNING '_cleaning_notify_user in-app falhou (user=%): %', p_user_id, SQLERRM;
  END;

  BEGIN
    SELECT decrypted_secret INTO v_url FROM vault.decrypted_secrets WHERE name='project_url' LIMIT 1;
    SELECT decrypted_secret INTO v_key FROM vault.decrypted_secrets WHERE name='service_role_key' LIMIT 1;
    IF v_url IS NULL OR v_key IS NULL THEN
      INSERT INTO public.notification_failures (user_id, kind, source, erro)
      VALUES (p_user_id, p_kind, '_cleaning_notify_user:fcm', 'vault project_url/service_role_key em falta');
      RAISE WARNING '_cleaning_notify_user FCM: vault secrets em falta (user=%)', p_user_id;
    ELSE
      PERFORM net.http_post(
        url := v_url || '/functions/v1/notify-cleaner',
        headers := jsonb_build_object('Content-Type','application/json','Authorization','Bearer '||v_key),
        body := jsonb_build_object(
          'cleanerUserId', p_user_id::text,
          'bookingId', COALESCE(p_booking_id,''),
          'title', p_title, 'body', p_body,
          'kind', p_kind, 'type', v_type)
      );
    END IF;
  EXCEPTION WHEN OTHERS THEN
    INSERT INTO public.notification_failures (user_id, kind, source, erro)
    VALUES (p_user_id, p_kind, '_cleaning_notify_user:fcm', SQLERRM);
    RAISE WARNING '_cleaning_notify_user FCM falhou (user=%): %', p_user_id, SQLERRM;
  END;
END $function$;

CREATE OR REPLACE FUNCTION public._cleaning_cron_offer_reping()
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_url text; v_key text; r record;
BEGIN
  IF NOT COALESCE(public._cleaning_setting_bool('cleaning_offer_reping_enabled', true), true) THEN
    RETURN;
  END IF;
  SELECT decrypted_secret INTO v_url FROM vault.decrypted_secrets WHERE name='project_url' LIMIT 1;
  SELECT decrypted_secret INTO v_key FROM vault.decrypted_secrets WHERE name='service_role_key' LIMIT 1;
  IF v_url IS NULL OR v_key IS NULL THEN RETURN; END IF;

  FOR r IN
    SELECT b.id, b.scheduled_at, b.cleaner_earnings_cents, b.offer_expires_at, c.user_id
    FROM cleaning_bookings b
    JOIN cleaners c ON c.id = b.offer_cleaner_id
    WHERE b.status = 'scheduled'
      AND b.cleaner_id IS NULL
      AND b.offer_cleaner_id IS NOT NULL
      AND b.offer_expires_at > now()
      AND NOT COALESCE(b.is_test_order, false)
  LOOP
    PERFORM net.http_post(
      url := v_url || '/functions/v1/notify-cleaner',
      headers := jsonb_build_object('Content-Type','application/json','Authorization','Bearer '||v_key),
      body := jsonb_build_object(
        'cleanerUserId', r.user_id::text,
        'bookingId', r.id::text,
        'title', 'Nova limpeza à tua espera',
        -- [09/10/2026] O número é o que a profissional GANHA (regra de ouro do prestador).
        'body', 'Limpeza a ' || to_char(r.scheduled_at AT TIME ZONE 'Europe/Lisbon', 'DD/MM às HH24:MI') ||
                ' — ganhas ' || (COALESCE(r.cleaner_earnings_cents, 0) / 100.0)::numeric(10,2) || ' EUR. Aceita ou recusa (faltam ' ||
                GREATEST(1, ceil(extract(epoch FROM (r.offer_expires_at - now())) / 60))::int || ' min).',
        'kind', 'cleaning_offer_reping', 'type', 'cleaning_offer')
    );
    BEGIN
      INSERT INTO public.cleaning_offer_pings (booking_id, cleaner_user_id, origem)
      VALUES (r.id::text, r.user_id, 'repeticao');
    EXCEPTION WHEN OTHERS THEN
      RAISE WARNING '_cleaning_cron_offer_reping: toque nao registado (booking=%): %', r.id, SQLERRM;
    END;
  END LOOP;
END $function$;

CREATE OR REPLACE FUNCTION public.my_trabalho_pendente()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_uid  uuid := auth.uid();
  v_hoje date := (now() AT TIME ZONE 'Europe/Lisbon')::date;
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('estafeta', false, 'limpeza', false, 'lavagem', false);
  END IF;
  RETURN jsonb_build_object(
    'estafeta', EXISTS (
      SELECT 1 FROM drivers d
       WHERE d.user_id = v_uid AND d.approval_status = 'approved'
         AND (COALESCE(d.is_online, false)
              OR EXISTS (SELECT 1 FROM orders o
                          WHERE o.assigned_driver_id = v_uid::text
                            AND o.status IN ('driverAccepted','pickedUp','onTheWay')))),
    'limpeza', EXISTS (
      SELECT 1 FROM cleaners c
       WHERE c.user_id = v_uid AND c.approval_status = 'approved'
         AND (EXISTS (SELECT 1 FROM cleaning_bookings b
                       WHERE b.offer_cleaner_id = c.id AND b.status = 'scheduled'
                         AND b.cleaner_id IS NULL AND b.offer_expires_at > now())
              OR EXISTS (SELECT 1 FROM cleaning_bookings b
                          WHERE b.cleaner_id = c.id
                            AND (b.status IN ('on_the_way','in_progress')
                                 OR (b.status = 'accepted'
                                     AND (b.scheduled_at AT TIME ZONE 'Europe/Lisbon')::date = v_hoje))))),
    'lavagem', EXISTS (
      SELECT 1 FROM washers w
       WHERE w.user_id = v_uid AND w.approval_status = 'approved'
         AND (EXISTS (SELECT 1 FROM carwash_bookings b
                       WHERE b.offer_washer_id = w.id AND b.status = 'scheduled'
                         AND b.washer_id IS NULL AND b.offer_expires_at > now())
              OR EXISTS (SELECT 1 FROM carwash_bookings b
                          WHERE b.washer_id = w.id
                            AND (b.status IN ('on_the_way','picked_up','in_progress','delivering')
                                 OR (b.status = 'accepted'
                                     AND (b.scheduled_at AT TIME ZONE 'Europe/Lisbon')::date = v_hoje)))))
  );
END $function$;

CREATE OR REPLACE FUNCTION public.admin_cleaning_offers()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'admin_required' USING ERRCODE = '42501';
  END IF;
  RETURN jsonb_build_object(
    'repeticao_ligada', public._cleaning_setting_bool('cleaning_offer_reping_enabled', true),
    'ofertas', COALESCE((
      SELECT jsonb_agg(s.x ORDER BY s.expira)
        FROM (
          SELECT b.offer_expires_at AS expira, jsonb_build_object(
            'booking_id', b.id,
            'marcada_para', b.scheduled_at,
            'cidade', b.address_city,
            'ganho_profissional_cents', b.cleaner_earnings_cents,
            'expira_em', b.offer_expires_at,
            'expirada', b.offer_expires_at <= now(),
            'profissional', c.name,
            'profissional_user_id', c.user_id,
            'toques', (SELECT count(*) FROM cleaning_offer_pings p
                        WHERE p.booking_id = b.id::text AND p.cleaner_user_id = c.user_id),
            'ultimo_toque', (SELECT max(p.created_at) FROM cleaning_offer_pings p
                              WHERE p.booking_id = b.id::text AND p.cleaner_user_id = c.user_id),
            'aparelho_registado', (
              EXISTS (SELECT 1 FROM provider_push_tokens t
                       WHERE t.user_id = c.user_id AND t.role = 'cleaner' AND t.active)
              OR EXISTS (SELECT 1 FROM users u WHERE u.id = c.user_id AND u.fcm_token IS NOT NULL)),
            'teste', COALESCE(b.is_test_order, false)
          ) AS x
          FROM cleaning_bookings b
          JOIN cleaners c ON c.id = b.offer_cleaner_id
          WHERE b.status = 'scheduled'
            AND b.cleaner_id IS NULL
            AND b.offer_cleaner_id IS NOT NULL
            AND b.offer_expires_at > now() - interval '2 hours'
        ) s), '[]'::jsonb)
  );
END $function$;

CREATE OR REPLACE FUNCTION public.admin_user_roles(p_user_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'admin_required' USING ERRCODE = '42501';
  END IF;
  RETURN jsonb_build_object(
    'estafeta', (SELECT jsonb_build_object('estado', d.approval_status,
                                           'ligado', COALESCE(d.is_online, false),
                                           'ja_foi_aprovado', d.approved_at IS NOT NULL)
                   FROM drivers d WHERE d.user_id = p_user_id),
    'limpeza',  (SELECT jsonb_build_object('estado', c.approval_status)
                   FROM cleaners c WHERE c.user_id = p_user_id),
    'lavagem',  (SELECT jsonb_build_object('estado', w.approval_status)
                   FROM washers w WHERE w.user_id = p_user_id)
  );
END $function$;

-- Ligar/desligar um papel JÁ APROVADO antes. Nunca substitui a aprovação normal da
-- candidatura (pendente → usa o ecrã de candidaturas, que confere documentos).
--  estafeta: desligar = 'rejected' (drivers não tem 'suspended') e fica desligado do despacho;
--            ligar só repõe quem já foi aprovado antes (approved_at preenchido).
--  limpeza/lavagem: desligar = 'suspended'; ligar = 'approved' a partir de 'suspended'.
-- Recusa desligar com trabalho em curso. Motivo obrigatório; fica em admin_audit_log.
CREATE OR REPLACE FUNCTION public.admin_set_user_role(p_user_id uuid, p_papel text, p_ativo boolean, p_motivo text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_antes  text;
  v_depois text;
  v_aprovado_antes boolean;
  v_pid uuid;
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'admin_required' USING ERRCODE = '42501';
  END IF;
  IF length(trim(COALESCE(p_motivo, ''))) < 3 THEN
    RETURN jsonb_build_object('ok', false, 'error', 'motivo_obrigatorio');
  END IF;
  IF p_papel NOT IN ('estafeta','limpeza','lavagem') THEN
    RETURN jsonb_build_object('ok', false, 'error', 'papel_invalido');
  END IF;

  IF p_papel = 'estafeta' THEN
    SELECT approval_status, approved_at IS NOT NULL INTO v_antes, v_aprovado_antes
      FROM drivers WHERE user_id = p_user_id FOR UPDATE;
    IF NOT FOUND THEN RETURN jsonb_build_object('ok', false, 'error', 'sem_perfil'); END IF;
    IF p_ativo THEN
      IF v_antes = 'approved' THEN
        v_depois := v_antes;
      ELSIF v_antes = 'rejected' AND v_aprovado_antes THEN
        UPDATE drivers SET approval_status = 'approved' WHERE user_id = p_user_id;
        v_depois := 'approved';
      ELSE
        RETURN jsonb_build_object('ok', false, 'error', 'usa_aprovacao_normal', 'estado', v_antes);
      END IF;
    ELSE
      IF EXISTS (SELECT 1 FROM orders o WHERE o.assigned_driver_id = p_user_id::text
                   AND o.status IN ('driverAccepted','pickedUp','onTheWay')) THEN
        RETURN jsonb_build_object('ok', false, 'error', 'trabalho_em_curso');
      END IF;
      IF v_antes = 'approved' THEN
        UPDATE drivers SET approval_status = 'rejected', is_online = false WHERE user_id = p_user_id;
      END IF;
      v_depois := CASE WHEN v_antes = 'approved' THEN 'rejected' ELSE v_antes END;
    END IF;

  ELSIF p_papel = 'limpeza' THEN
    SELECT id, approval_status INTO v_pid, v_antes FROM cleaners WHERE user_id = p_user_id FOR UPDATE;
    IF NOT FOUND THEN RETURN jsonb_build_object('ok', false, 'error', 'sem_perfil'); END IF;
    IF p_ativo THEN
      IF v_antes = 'approved' THEN
        v_depois := v_antes;
      ELSIF v_antes = 'suspended' THEN
        UPDATE cleaners SET approval_status = 'approved' WHERE id = v_pid;
        v_depois := 'approved';
      ELSE
        RETURN jsonb_build_object('ok', false, 'error', 'usa_aprovacao_normal', 'estado', v_antes);
      END IF;
    ELSE
      IF EXISTS (SELECT 1 FROM cleaning_bookings b WHERE b.cleaner_id = v_pid
                   AND b.status IN ('on_the_way','in_progress')) THEN
        RETURN jsonb_build_object('ok', false, 'error', 'trabalho_em_curso');
      END IF;
      IF v_antes = 'approved' THEN
        UPDATE cleaners SET approval_status = 'suspended' WHERE id = v_pid;
      END IF;
      v_depois := CASE WHEN v_antes = 'approved' THEN 'suspended' ELSE v_antes END;
    END IF;

  ELSE -- lavagem
    SELECT id, approval_status INTO v_pid, v_antes FROM washers WHERE user_id = p_user_id FOR UPDATE;
    IF NOT FOUND THEN RETURN jsonb_build_object('ok', false, 'error', 'sem_perfil'); END IF;
    IF p_ativo THEN
      IF v_antes = 'approved' THEN
        v_depois := v_antes;
      ELSIF v_antes = 'suspended' THEN
        UPDATE washers SET approval_status = 'approved' WHERE id = v_pid;
        v_depois := 'approved';
      ELSE
        RETURN jsonb_build_object('ok', false, 'error', 'usa_aprovacao_normal', 'estado', v_antes);
      END IF;
    ELSE
      IF EXISTS (SELECT 1 FROM carwash_bookings b WHERE b.washer_id = v_pid
                   AND b.status IN ('on_the_way','picked_up','in_progress','delivering')) THEN
        RETURN jsonb_build_object('ok', false, 'error', 'trabalho_em_curso');
      END IF;
      IF v_antes = 'approved' THEN
        UPDATE washers SET approval_status = 'suspended' WHERE id = v_pid;
      END IF;
      v_depois := CASE WHEN v_antes = 'approved' THEN 'suspended' ELSE v_antes END;
    END IF;
  END IF;

  PERFORM public.log_admin_action(
    CASE WHEN p_ativo THEN 'papel_ligado' ELSE 'papel_desligado' END,
    'user', p_user_id,
    jsonb_build_object('papel', p_papel, 'motivo', trim(p_motivo), 'antes', v_antes, 'depois', v_depois));

  RETURN jsonb_build_object('ok', true, 'papel', p_papel, 'antes', v_antes, 'depois', v_depois);
END $function$;

CREATE OR REPLACE FUNCTION public.admin_set_cleaning_offer_reping(p_ligado boolean, p_motivo text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_antes boolean;
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'admin_required' USING ERRCODE = '42501';
  END IF;
  IF p_ligado IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'valor_em_falta');
  END IF;
  v_antes := public._cleaning_setting_bool('cleaning_offer_reping_enabled', true);
  INSERT INTO platform_settings (key, value, description, category, updated_at, updated_by)
  VALUES ('cleaning_offer_reping_enabled', to_jsonb(p_ligado),
          'Repete o toque da oferta de limpeza a cada minuto ate a profissional responder.',
          'limpeza', now(), auth.uid())
  ON CONFLICT (key) DO UPDATE
    SET value = EXCLUDED.value, updated_at = now(), updated_by = auth.uid();
  PERFORM public.log_admin_action('limpeza_toque_repetido', 'platform_setting', NULL::uuid,
    jsonb_build_object('antes', v_antes, 'depois', p_ligado, 'motivo', COALESCE(trim(p_motivo), '')));
  RETURN jsonb_build_object('ok', true, 'antes', v_antes, 'depois', p_ligado);
END $function$;

REVOKE ALL ON FUNCTION public.my_trabalho_pendente() FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.admin_cleaning_offers() FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.admin_user_roles(uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.admin_set_user_role(uuid, text, boolean, text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.admin_set_cleaning_offer_reping(boolean, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.my_trabalho_pendente() TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_cleaning_offers() TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_user_roles(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_set_user_role(uuid, text, boolean, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_set_cleaning_offer_reping(boolean, text) TO authenticated;

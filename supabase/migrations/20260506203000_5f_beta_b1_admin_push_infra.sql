-- ═══════════════════════════════════════════════════════════════════════════
-- 5F-β B1 — Admin Push Infrastructure
-- - Tabela admin_push_tokens (multi-device por admin)
-- - RPC admin_register_push_token (UPSERT)
-- - RPC admin_respond_to_crosstalk (reply via UI)
-- - Trigger AFTER INSERT robot_crosstalk (urgency=critical → notify-admin-urgent)
-- - Tentativa ALTER DATABASE pg_net settings (provavelmente falha por privilege)
-- ═══════════════════════════════════════════════════════════════════════════

-- ───────────────────────────────────────────────────────────────────────────
-- Tentar configurar pg_net settings (best-effort; aceitamos falha)
-- ───────────────────────────────────────────────────────────────────────────
DO $do_pg_net$
BEGIN
  BEGIN
    EXECUTE format(
      'ALTER DATABASE %I SET app.supabase_url = %L',
      current_database(),
      'https://ojykpzwqrtusfeakzrna.supabase.co'
    );
    RAISE NOTICE '5F-β: pg_net app.supabase_url set OK';
  EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE '5F-β: ALTER DATABASE app.supabase_url failed: %. Manual config required in Dashboard.', SQLERRM;
  END;
END
$do_pg_net$;

-- ───────────────────────────────────────────────────────────────────────────
-- Tabela admin_push_tokens
-- ───────────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.admin_push_tokens (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  admin_id      uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  fcm_token     text NOT NULL UNIQUE,
  device_label  text,
  platform      text CHECK (platform IN ('android','ios','web')),
  last_used_at  timestamptz NOT NULL DEFAULT now(),
  created_at    timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.admin_push_tokens ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "admin_own" ON public.admin_push_tokens;
CREATE POLICY "admin_own"
  ON public.admin_push_tokens
  FOR ALL
  USING (admin_id = auth.uid() AND public.is_admin())
  WITH CHECK (admin_id = auth.uid() AND public.is_admin());

DROP POLICY IF EXISTS "service_role_all" ON public.admin_push_tokens;
CREATE POLICY "service_role_all"
  ON public.admin_push_tokens
  FOR ALL
  USING (auth.role() = 'service_role')
  WITH CHECK (auth.role() = 'service_role');

CREATE INDEX IF NOT EXISTS idx_admin_push_tokens_admin
  ON public.admin_push_tokens (admin_id);

CREATE INDEX IF NOT EXISTS idx_admin_push_tokens_last_used
  ON public.admin_push_tokens (last_used_at DESC);

COMMENT ON TABLE public.admin_push_tokens IS
  '5F-β: FCM tokens per admin device (multi-device). UPSERT via admin_register_push_token. Cleanup stale by notify-admin-urgent on UNREGISTERED/INVALID_ARGUMENT.';

-- ───────────────────────────────────────────────────────────────────────────
-- RPC admin_register_push_token
-- ───────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.admin_register_push_token(
  p_fcm_token    text,
  p_device_label text DEFAULT NULL,
  p_platform     text DEFAULT NULL
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $fn_register$
DECLARE
  v_id uuid;
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'NOT_ADMIN';
  END IF;

  IF p_fcm_token IS NULL OR length(trim(p_fcm_token)) = 0 THEN
    RAISE EXCEPTION 'FCM_TOKEN_REQUIRED';
  END IF;

  IF p_platform IS NOT NULL AND p_platform NOT IN ('android','ios','web') THEN
    RAISE EXCEPTION 'INVALID_PLATFORM';
  END IF;

  INSERT INTO admin_push_tokens (admin_id, fcm_token, device_label, platform)
  VALUES (auth.uid(), p_fcm_token, p_device_label, p_platform)
  ON CONFLICT (fcm_token) DO UPDATE
    SET admin_id     = auth.uid(),
        device_label = COALESCE(EXCLUDED.device_label, admin_push_tokens.device_label),
        platform     = COALESCE(EXCLUDED.platform, admin_push_tokens.platform),
        last_used_at = now()
  RETURNING id INTO v_id;

  RETURN v_id;
END;
$fn_register$;

REVOKE ALL ON FUNCTION public.admin_register_push_token(text, text, text) FROM public, anon;
GRANT EXECUTE ON FUNCTION public.admin_register_push_token(text, text, text) TO authenticated;

COMMENT ON FUNCTION public.admin_register_push_token(text, text, text) IS
  '5F-β: UPSERT FCM token for current admin. Validates is_admin() + platform enum.';

-- ───────────────────────────────────────────────────────────────────────────
-- RPC admin_respond_to_crosstalk
-- ───────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.admin_respond_to_crosstalk(
  p_crosstalk_id uuid,
  p_answer       text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $fn_respond$
DECLARE
  v_updated_id uuid;
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'NOT_ADMIN';
  END IF;

  IF p_answer IS NULL OR length(trim(p_answer)) = 0 THEN
    RAISE EXCEPTION 'ANSWER_REQUIRED';
  END IF;

  UPDATE robot_crosstalk
     SET answer      = p_answer,
         answered_at = now(),
         answered_by = 'admin',
         status      = 'answered'
   WHERE id = p_crosstalk_id
     AND status = 'pending'
  RETURNING id INTO v_updated_id;

  IF v_updated_id IS NULL THEN
    RAISE EXCEPTION 'CROSSTALK_NOT_FOUND_OR_NOT_PENDING';
  END IF;

  RETURN jsonb_build_object(
    'answered',     true,
    'crosstalk_id', v_updated_id,
    'answered_by',  'admin'
  );
END;
$fn_respond$;

REVOKE ALL ON FUNCTION public.admin_respond_to_crosstalk(uuid, text) FROM public, anon;
GRANT EXECUTE ON FUNCTION public.admin_respond_to_crosstalk(uuid, text) TO authenticated;

COMMENT ON FUNCTION public.admin_respond_to_crosstalk(uuid, text) IS
  '5F-β: Admin replies to robot_crosstalk via UI. Sets status=answered, answered_by=admin.';

-- ───────────────────────────────────────────────────────────────────────────
-- Trigger function: notify-admin-urgent on critical INSERT
-- ───────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public._notify_admin_urgent_trigger()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, net
AS $trg_fn$
DECLARE
  v_url text;
  v_key text;
BEGIN
  -- Filtros: só a_to_b + critical + pending
  IF NEW.direction <> 'a_to_b'
     OR NEW.urgency <> 'critical'
     OR NEW.status <> 'pending' THEN
    RETURN NEW;
  END IF;

  -- Gate pg_net settings
  v_url := current_setting('app.supabase_url', true);
  v_key := current_setting('app.service_role_key', true);

  IF v_url IS NULL OR v_url = ''
     OR v_key IS NULL OR v_key = '' THEN
    RAISE NOTICE '5F-β: pg_net settings MISSING — skipping notify-admin-urgent for crosstalk %', NEW.id;
    RETURN NEW;
  END IF;

  PERFORM net.http_post(
    url     := v_url || '/functions/v1/notify-admin-urgent',
    headers := jsonb_build_object(
                 'Authorization', 'Bearer ' || v_key,
                 'Content-Type',  'application/json'
               ),
    body    := jsonb_build_object(
                 'crosstalk_id', NEW.id,
                 'question',     NEW.question,
                 'session_id',   NEW.session_id,
                 'context',      NEW.question_context
               )
  );

  RETURN NEW;

EXCEPTION WHEN OTHERS THEN
  -- Nunca bloquear INSERT
  RAISE NOTICE '5F-β: notify-admin-urgent trigger error: %', SQLERRM;
  RETURN NEW;
END;
$trg_fn$;

DROP TRIGGER IF EXISTS trg_robot_crosstalk_notify_urgent ON public.robot_crosstalk;
CREATE TRIGGER trg_robot_crosstalk_notify_urgent
  AFTER INSERT ON public.robot_crosstalk
  FOR EACH ROW
  EXECUTE FUNCTION public._notify_admin_urgent_trigger();

COMMENT ON FUNCTION public._notify_admin_urgent_trigger() IS
  '5F-β: AFTER INSERT robot_crosstalk → POST notify-admin-urgent via pg_net (silent skip se pg_net settings MISSING; nunca bloqueia INSERT).';

-- ═══════════════════════════════════════════════════════════════════════════
-- BLOCO 1 — Push Tokens Infrastructure (client + driver, multi-device)
-- Decisões: A (multi-device), C (retry 3x → marca inactivo, não apaga)
-- Pattern: alinhado com admin_push_tokens (5F-β)
-- ═══════════════════════════════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS public.client_push_tokens (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id       uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  fcm_token     text NOT NULL,
  device_label  text,
  platform      text CHECK (platform IN ('android','ios','web')),
  active        boolean NOT NULL DEFAULT true,
  fail_count    smallint NOT NULL DEFAULT 0,
  last_fail_at  timestamptz,
  last_used_at  timestamptz NOT NULL DEFAULT now(),
  created_at    timestamptz NOT NULL DEFAULT now(),
  updated_at    timestamptz NOT NULL DEFAULT now(),
  UNIQUE (user_id, fcm_token)
);

CREATE INDEX IF NOT EXISTS idx_client_push_tokens_user_active
  ON public.client_push_tokens (user_id) WHERE active = true;

ALTER TABLE public.client_push_tokens ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "client_own_tokens" ON public.client_push_tokens;
CREATE POLICY "client_own_tokens" ON public.client_push_tokens
  FOR ALL USING (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "service_role_all_client_tokens" ON public.client_push_tokens;
CREATE POLICY "service_role_all_client_tokens" ON public.client_push_tokens
  FOR ALL USING (auth.role() = 'service_role')
  WITH CHECK (auth.role() = 'service_role');

COMMENT ON TABLE public.client_push_tokens IS
  '5G — FCM tokens dos clientes. Multi-device (Decisão A). fail_count>=3 → active=false (Decisão C).';

-- ═══════════════════════════════════════════════════════════════════════════
CREATE TABLE IF NOT EXISTS public.driver_push_tokens (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id       uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  fcm_token     text NOT NULL,
  device_label  text,
  platform      text CHECK (platform IN ('android','ios','web')),
  active        boolean NOT NULL DEFAULT true,
  fail_count    smallint NOT NULL DEFAULT 0,
  last_fail_at  timestamptz,
  last_used_at  timestamptz NOT NULL DEFAULT now(),
  created_at    timestamptz NOT NULL DEFAULT now(),
  updated_at    timestamptz NOT NULL DEFAULT now(),
  UNIQUE (user_id, fcm_token)
);

CREATE INDEX IF NOT EXISTS idx_driver_push_tokens_user_active
  ON public.driver_push_tokens (user_id) WHERE active = true;

ALTER TABLE public.driver_push_tokens ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "driver_own_tokens" ON public.driver_push_tokens;
CREATE POLICY "driver_own_tokens" ON public.driver_push_tokens
  FOR ALL USING (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "service_role_all_driver_tokens" ON public.driver_push_tokens;
CREATE POLICY "service_role_all_driver_tokens" ON public.driver_push_tokens
  FOR ALL USING (auth.role() = 'service_role')
  WITH CHECK (auth.role() = 'service_role');

COMMENT ON TABLE public.driver_push_tokens IS
  '5G — FCM tokens dos estafetas. Multi-device (Decisão A). fail_count>=3 → active=false (Decisão C). Restauro via re-registo.';

-- ═══════════════════════════════════════════════════════════════════════════
-- RPC: register_push_token (UPSERT, role-aware)
-- ═══════════════════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.register_push_token(
  p_role         text,
  p_fcm_token    text,
  p_device_label text DEFAULT NULL,
  p_platform     text DEFAULT NULL
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $fn$
DECLARE
  v_user_id uuid := auth.uid();
  v_token_id uuid;
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'UNAUTHENTICATED';
  END IF;

  IF p_fcm_token IS NULL OR length(trim(p_fcm_token)) = 0 THEN
    RAISE EXCEPTION 'FCM_TOKEN_REQUIRED';
  END IF;

  IF p_platform IS NOT NULL AND p_platform NOT IN ('android','ios','web') THEN
    RAISE EXCEPTION 'INVALID_PLATFORM';
  END IF;

  IF p_role = 'client' THEN
    INSERT INTO public.client_push_tokens (user_id, fcm_token, device_label, platform)
    VALUES (v_user_id, p_fcm_token, p_device_label, p_platform)
    ON CONFLICT (user_id, fcm_token) DO UPDATE
      SET active       = true,
          fail_count   = 0,
          last_fail_at = NULL,
          updated_at   = now(),
          last_used_at = now(),
          device_label = COALESCE(EXCLUDED.device_label, client_push_tokens.device_label),
          platform     = COALESCE(EXCLUDED.platform,     client_push_tokens.platform)
    RETURNING id INTO v_token_id;
  ELSIF p_role = 'driver' THEN
    INSERT INTO public.driver_push_tokens (user_id, fcm_token, device_label, platform)
    VALUES (v_user_id, p_fcm_token, p_device_label, p_platform)
    ON CONFLICT (user_id, fcm_token) DO UPDATE
      SET active       = true,
          fail_count   = 0,
          last_fail_at = NULL,
          updated_at   = now(),
          last_used_at = now(),
          device_label = COALESCE(EXCLUDED.device_label, driver_push_tokens.device_label),
          platform     = COALESCE(EXCLUDED.platform,     driver_push_tokens.platform)
    RETURNING id INTO v_token_id;
  ELSE
    RAISE EXCEPTION 'INVALID_ROLE: %', p_role;
  END IF;

  RETURN v_token_id;
END;
$fn$;

REVOKE ALL ON FUNCTION public.register_push_token(text, text, text, text) FROM public, anon;
GRANT EXECUTE ON FUNCTION public.register_push_token(text, text, text, text) TO authenticated;

COMMENT ON FUNCTION public.register_push_token(text, text, text, text) IS
  '5G — UPSERT FCM token para cliente ou estafeta. Multi-device (não apaga existentes). Re-activa + reseta fail_count em re-registo.';

-- ═══════════════════════════════════════════════════════════════════════════
-- RPC: mark_token_failed (chamada por Edge Fns após FCM 4xx)
-- ═══════════════════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.mark_token_failed(
  p_table  text,
  p_token  text,
  p_reason text DEFAULT 'fcm_error'
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $fn$
BEGIN
  IF p_table NOT IN ('client_push_tokens','driver_push_tokens') THEN
    RAISE EXCEPTION 'INVALID_TABLE: %', p_table;
  END IF;

  EXECUTE format(
    'UPDATE public.%I SET fail_count = fail_count + 1, last_fail_at = NOW(), updated_at = NOW() WHERE fcm_token = $1',
    p_table
  ) USING p_token;

  EXECUTE format(
    'UPDATE public.%I SET active = false, updated_at = NOW() WHERE fcm_token = $1 AND fail_count >= 3',
    p_table
  ) USING p_token;
END;
$fn$;

REVOKE ALL ON FUNCTION public.mark_token_failed(text, text, text) FROM public, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.mark_token_failed(text, text, text) TO service_role;

COMMENT ON FUNCTION public.mark_token_failed(text, text, text) IS
  '5G — Decisão C: incrementa fail_count, marca inactivo quando >= 3. NÃO apaga (recupera via re-registo).';

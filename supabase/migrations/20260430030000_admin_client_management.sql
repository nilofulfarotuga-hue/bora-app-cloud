-- ============================================================================
-- BORA — Admin client management RPCs (T9)
-- ============================================================================
-- Mirrors the driver-management pattern (20260429110000) but for clients
-- (auth.users with bora_role = 'client' or no role).
--
-- Ban semantics: uses Supabase Auth native `auth.users.banned_until`:
--   banned_until IS NULL                → not banned
--   banned_until > now()                → suspended (auto-expires)
--   banned_until = '294276-12-31'::date → permanent ban (sentinel far future)
--
-- Reason + history kept in admin_audit_log (action: client_ban / client_unban).
--
-- All RPCs use _admin_op_guard. Read-only listing also gated.
-- ============================================================================

BEGIN;

-- ---------------------------------------------------------------------------
-- 1. admin_list_clients — paginated list with search + ban filter
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.admin_list_clients(
  p_search       TEXT    DEFAULT NULL,  -- ILIKE match on email/name/phone
  p_banned_only  BOOLEAN DEFAULT FALSE,
  p_limit        INT     DEFAULT 50,
  p_offset       INT     DEFAULT 0
)
RETURNS TABLE (
  user_id          UUID,
  email            TEXT,
  bora_name        TEXT,
  bora_phone       TEXT,
  created_at       TIMESTAMPTZ,
  last_sign_in_at  TIMESTAMPTZ,
  is_banned        BOOLEAN,
  banned_until     TIMESTAMPTZ,
  total_orders     BIGINT,
  total_spent      NUMERIC,
  token_balance    INT
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
  v_admin RECORD;
BEGIN
  SELECT admin_id, admin_email INTO v_admin FROM public._admin_op_guard();

  IF p_limit < 1 OR p_limit > 500 THEN
    RAISE EXCEPTION 'admin_list_clients: limit must be 1..500';
  END IF;

  RETURN QUERY
  WITH clients_base AS (
    SELECT
      u.id,
      u.email::TEXT AS email,
      COALESCE(u.raw_user_meta_data->>'bora_name', '')::TEXT  AS bora_name,
      COALESCE(u.raw_user_meta_data->>'bora_phone', '')::TEXT AS bora_phone,
      u.created_at,
      u.last_sign_in_at,
      (u.banned_until IS NOT NULL AND u.banned_until > now()) AS is_banned,
      u.banned_until
    FROM auth.users u
    WHERE COALESCE(u.raw_user_meta_data->>'bora_role', 'client') = 'client'
      AND (
        p_search IS NULL
        OR u.email                                ILIKE '%' || p_search || '%'
        OR (u.raw_user_meta_data->>'bora_name')   ILIKE '%' || p_search || '%'
        OR (u.raw_user_meta_data->>'bora_phone')  ILIKE '%' || p_search || '%'
      )
      AND (NOT p_banned_only OR (u.banned_until IS NOT NULL AND u.banned_until > now()))
  )
  SELECT
    cb.id,
    cb.email,
    cb.bora_name,
    cb.bora_phone,
    cb.created_at,
    cb.last_sign_in_at,
    cb.is_banned,
    cb.banned_until,
    COALESCE(o.cnt, 0)         AS total_orders,
    COALESCE(o.total, 0)::NUMERIC AS total_spent,
    COALESCE(t.balance, 0)     AS token_balance
  FROM clients_base cb
  LEFT JOIN LATERAL (
    SELECT count(*) AS cnt, sum(price) AS total
      FROM public.orders
     WHERE user_id = cb.id AND status = 'delivered'
  ) o ON true
  LEFT JOIN LATERAL (
    SELECT COALESCE(sum(amount), 0)::INT AS balance
      FROM public.bora_tokens
     WHERE user_id = cb.id
       AND consumed_at IS NULL
       AND (expires_at IS NULL OR expires_at > now())
  ) t ON true
  ORDER BY cb.created_at DESC
  LIMIT p_limit OFFSET p_offset;
END;
$$;

REVOKE ALL ON FUNCTION public.admin_list_clients(TEXT, BOOLEAN, INT, INT) FROM public, anon;
GRANT EXECUTE ON FUNCTION public.admin_list_clients(TEXT, BOOLEAN, INT, INT) TO authenticated;


-- ---------------------------------------------------------------------------
-- 2. admin_ban_client
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.admin_ban_client(
  p_user_id      UUID,
  p_reason       TEXT,
  p_banned_until TIMESTAMPTZ DEFAULT NULL  -- NULL = permanent
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
  v_admin   RECORD;
  v_user    RECORD;
  v_until   TIMESTAMPTZ;
BEGIN
  SELECT admin_id, admin_email INTO v_admin FROM public._admin_op_guard();

  IF p_reason IS NULL OR length(trim(p_reason)) < 3 THEN
    RAISE EXCEPTION 'admin_ban_client: reason required (>= 3 chars)';
  END IF;

  IF p_banned_until IS NOT NULL AND p_banned_until <= now() THEN
    RAISE EXCEPTION 'admin_ban_client: banned_until must be in the future';
  END IF;

  -- Sentinel for permanent ban (Supabase Auth supports this)
  v_until := COALESCE(p_banned_until, '294276-12-31 23:59:59+00'::TIMESTAMPTZ);

  SELECT id, email INTO v_user FROM auth.users WHERE id = p_user_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'admin_ban_client: user % not found', p_user_id;
  END IF;

  -- Forbid banning admins (defence in depth)
  IF EXISTS (
    SELECT 1 FROM auth.users
    WHERE id = p_user_id
      AND COALESCE(raw_app_meta_data->>'role', '') = 'admin'
  ) THEN
    RAISE EXCEPTION 'admin_ban_client: cannot ban an admin user';
  END IF;

  UPDATE auth.users SET banned_until = v_until WHERE id = p_user_id;

  -- Audit
  INSERT INTO public.admin_audit_log (
    admin_id, admin_email, action, entity_type, entity_id, details
  ) VALUES (
    v_admin.admin_id, v_admin.admin_email, 'client_ban', 'user', p_user_id,
    jsonb_build_object(
      'reason', trim(p_reason),
      'banned_until', v_until,
      'permanent', p_banned_until IS NULL,
      'target_email', v_user.email
    )
  );

  RETURN jsonb_build_object(
    'success', true, 'user_id', p_user_id,
    'banned_until', v_until, 'permanent', p_banned_until IS NULL
  );
END;
$$;

REVOKE ALL ON FUNCTION public.admin_ban_client(UUID, TEXT, TIMESTAMPTZ) FROM public, anon;
GRANT EXECUTE ON FUNCTION public.admin_ban_client(UUID, TEXT, TIMESTAMPTZ) TO authenticated;


-- ---------------------------------------------------------------------------
-- 3. admin_unban_client
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.admin_unban_client(
  p_user_id UUID,
  p_reason  TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
  v_admin RECORD;
BEGIN
  SELECT admin_id, admin_email INTO v_admin FROM public._admin_op_guard();

  IF p_reason IS NULL OR length(trim(p_reason)) < 3 THEN
    RAISE EXCEPTION 'admin_unban_client: reason required (>= 3 chars)';
  END IF;

  IF NOT EXISTS (SELECT 1 FROM auth.users WHERE id = p_user_id) THEN
    RAISE EXCEPTION 'admin_unban_client: user % not found', p_user_id;
  END IF;

  UPDATE auth.users SET banned_until = NULL WHERE id = p_user_id;

  INSERT INTO public.admin_audit_log (
    admin_id, admin_email, action, entity_type, entity_id, details
  ) VALUES (
    v_admin.admin_id, v_admin.admin_email, 'client_unban', 'user', p_user_id,
    jsonb_build_object('reason', trim(p_reason))
  );

  RETURN jsonb_build_object('success', true, 'user_id', p_user_id);
END;
$$;

REVOKE ALL ON FUNCTION public.admin_unban_client(UUID, TEXT) FROM public, anon;
GRANT EXECUTE ON FUNCTION public.admin_unban_client(UUID, TEXT) TO authenticated;


-- ---------------------------------------------------------------------------
-- 4. admin_get_client_history — recent orders + token transactions
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.admin_get_client_history(
  p_user_id UUID,
  p_limit   INT DEFAULT 50
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
STABLE
SET search_path = public, auth
AS $$
DECLARE
  v_admin   RECORD;
  v_orders  JSONB;
  v_tokens  JSONB;
  v_user    JSONB;
BEGIN
  SELECT admin_id, admin_email INTO v_admin FROM public._admin_op_guard();

  IF p_limit < 1 OR p_limit > 500 THEN p_limit := 50; END IF;

  SELECT jsonb_build_object(
    'id', u.id,
    'email', u.email,
    'bora_name', u.raw_user_meta_data->>'bora_name',
    'bora_phone', u.raw_user_meta_data->>'bora_phone',
    'created_at', u.created_at,
    'banned_until', u.banned_until,
    'is_banned', (u.banned_until IS NOT NULL AND u.banned_until > now())
  ) INTO v_user
  FROM auth.users u
  WHERE u.id = p_user_id;

  IF v_user IS NULL THEN
    RAISE EXCEPTION 'admin_get_client_history: user % not found', p_user_id;
  END IF;

  SELECT COALESCE(jsonb_agg(jsonb_build_object(
    'id', o.id, 'created_at', o.created_at, 'status', o.status,
    'service_type', o.service_type, 'vendor_name', o.vendor_name,
    'price', o.price, 'payment_method', o.payment_method
  ) ORDER BY o.created_at DESC), '[]'::jsonb) INTO v_orders
  FROM (
    SELECT * FROM public.orders WHERE user_id = p_user_id
    ORDER BY created_at DESC LIMIT p_limit
  ) o;

  SELECT COALESCE(jsonb_agg(jsonb_build_object(
    'id', t.id, 'amount', t.amount, 'role', t.role,
    'created_at', t.created_at, 'expires_at', t.expires_at,
    'consumed_at', t.consumed_at
  ) ORDER BY t.created_at DESC), '[]'::jsonb) INTO v_tokens
  FROM (
    SELECT * FROM public.bora_tokens WHERE user_id = p_user_id
    ORDER BY created_at DESC LIMIT p_limit
  ) t;

  RETURN jsonb_build_object(
    'user',   v_user,
    'orders', v_orders,
    'tokens', v_tokens
  );
END;
$$;

REVOKE ALL ON FUNCTION public.admin_get_client_history(UUID, INT) FROM public, anon;
GRANT EXECUTE ON FUNCTION public.admin_get_client_history(UUID, INT) TO authenticated;


COMMIT;

-- ============================================================================
-- SMOKE TEST
-- ============================================================================
-- 1. List clients:
--      SELECT * FROM admin_list_clients(NULL, FALSE, 10, 0);
-- 2. List banned only:
--      SELECT * FROM admin_list_clients(NULL, TRUE, 10, 0);
-- 3. Ban + audit:
--      SELECT admin_ban_client('<uuid>', 'fraude detectada', now() + INTERVAL '7 days');
-- 4. History:
--      SELECT admin_get_client_history('<uuid>', 50);
-- 5. Unban:
--      SELECT admin_unban_client('<uuid>', 'investigacao concluida sem incidencia');
-- ============================================================================

-- ============================================================================
-- BORA — Admin token management (T8)
-- ============================================================================
-- RPCs for admin to:
--   1. View any user's token balance + history (client OR driver).
--   2. Grant manual tokens (positive adjustment) with reason + audit log.
--   3. Revoke specific token grants (mark as used, fast-forward expiry).
--
-- Negative balance adjustments are NOT supported as a single operation
-- because bora_tokens.amount has CHECK (amount > 0). To reduce a balance,
-- use admin_revoke_token_grant() with the specific grant id (cleaner audit
-- trail) or mark grants as expired in bulk via admin_expire_user_tokens().
-- ============================================================================

BEGIN;

-- ---------------------------------------------------------------------------
-- 1. admin_get_user_tokens — balance + recent grants for any user/role
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.admin_get_user_tokens(
  p_user_id UUID,
  p_role    TEXT DEFAULT NULL,  -- 'client' | 'driver' | NULL = any
  p_limit   INT  DEFAULT 100
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
STABLE
SET search_path = public
AS $$
DECLARE
  v_admin    RECORD;
  v_balance  INT;
  v_grants   JSONB;
BEGIN
  SELECT admin_id, admin_email INTO v_admin FROM public._admin_op_guard();

  IF p_role IS NOT NULL AND p_role NOT IN ('client', 'driver') THEN
    RAISE EXCEPTION 'admin_get_user_tokens: role must be client|driver|NULL';
  END IF;

  IF p_limit < 1 OR p_limit > 1000 THEN p_limit := 100; END IF;

  -- Active balance: not used, not expired
  SELECT COALESCE(sum(amount), 0) INTO v_balance
    FROM public.bora_tokens
   WHERE user_id = p_user_id
     AND COALESCE(is_used, false) = false
     AND (expires_at IS NULL OR expires_at > now())
     AND (p_role IS NULL OR role = p_role);

  SELECT COALESCE(jsonb_agg(g ORDER BY (g->>'created_at') DESC), '[]'::jsonb) INTO v_grants
  FROM (
    SELECT jsonb_build_object(
      'id',              t.id,
      'amount',          t.amount,
      'role',            t.role,
      'source_order_id', t.source_order_id,
      'is_used',         t.is_used,
      'used_at',         t.used_at,
      'created_at',      t.created_at,
      'expires_at',      t.expires_at,
      'is_active',       (NOT COALESCE(t.is_used, false)
                          AND (t.expires_at IS NULL OR t.expires_at > now()))
    ) AS g
    FROM public.bora_tokens t
    WHERE t.user_id = p_user_id
      AND (p_role IS NULL OR t.role = p_role)
    ORDER BY t.created_at DESC
    LIMIT p_limit
  ) sub;

  RETURN jsonb_build_object(
    'user_id', p_user_id,
    'role',    p_role,
    'balance', v_balance,
    'grants',  v_grants
  );
END;
$$;

REVOKE ALL ON FUNCTION public.admin_get_user_tokens(UUID, TEXT, INT) FROM public, anon;
GRANT EXECUTE ON FUNCTION public.admin_get_user_tokens(UUID, TEXT, INT) TO authenticated;


-- ---------------------------------------------------------------------------
-- 2. admin_grant_tokens — positive adjustment with audit log
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.admin_grant_tokens(
  p_user_id        UUID,
  p_role           TEXT,    -- 'client' | 'driver'
  p_amount         INT,
  p_reason         TEXT,
  p_validity_days  INT DEFAULT 60   -- default same as system grants (BR §4.1)
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_admin    RECORD;
  v_token_id UUID;
  v_expires  TIMESTAMPTZ;
BEGIN
  SELECT admin_id, admin_email INTO v_admin FROM public._admin_op_guard();

  IF p_role NOT IN ('client', 'driver') THEN
    RAISE EXCEPTION 'admin_grant_tokens: role must be client|driver';
  END IF;
  IF p_amount IS NULL OR p_amount < 1 OR p_amount > 100000 THEN
    RAISE EXCEPTION 'admin_grant_tokens: amount must be 1..100000';
  END IF;
  IF p_reason IS NULL OR length(trim(p_reason)) < 3 THEN
    RAISE EXCEPTION 'admin_grant_tokens: reason required (>= 3 chars)';
  END IF;
  IF p_validity_days < 1 OR p_validity_days > 365 THEN
    RAISE EXCEPTION 'admin_grant_tokens: validity_days must be 1..365';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM auth.users WHERE id = p_user_id) THEN
    RAISE EXCEPTION 'admin_grant_tokens: user % not found', p_user_id;
  END IF;

  v_expires := now() + (p_validity_days || ' days')::INTERVAL;

  INSERT INTO public.bora_tokens (
    user_id, role, amount, expires_at, source_order_id
  ) VALUES (
    p_user_id, p_role, p_amount, v_expires, NULL
  ) RETURNING id INTO v_token_id;

  INSERT INTO public.admin_audit_log (
    admin_id, admin_email, action, entity_type, entity_id, details
  ) VALUES (
    v_admin.admin_id, v_admin.admin_email, 'tokens_grant', 'user', p_user_id,
    jsonb_build_object(
      'role', p_role, 'amount', p_amount, 'reason', trim(p_reason),
      'expires_at', v_expires, 'token_id', v_token_id
    )
  );

  RETURN jsonb_build_object(
    'success', true, 'token_id', v_token_id,
    'amount', p_amount, 'expires_at', v_expires
  );
END;
$$;

REVOKE ALL ON FUNCTION public.admin_grant_tokens(UUID, TEXT, INT, TEXT, INT) FROM public, anon;
GRANT EXECUTE ON FUNCTION public.admin_grant_tokens(UUID, TEXT, INT, TEXT, INT) TO authenticated;


-- ---------------------------------------------------------------------------
-- 3. admin_revoke_token_grant — mark a specific grant as used (zero balance impact going forward)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.admin_revoke_token_grant(
  p_token_id UUID,
  p_reason   TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_admin RECORD;
  v_grant RECORD;
BEGIN
  SELECT admin_id, admin_email INTO v_admin FROM public._admin_op_guard();

  IF p_reason IS NULL OR length(trim(p_reason)) < 3 THEN
    RAISE EXCEPTION 'admin_revoke_token_grant: reason required (>= 3 chars)';
  END IF;

  SELECT id, user_id, role, amount, is_used INTO v_grant
    FROM public.bora_tokens WHERE id = p_token_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'admin_revoke_token_grant: grant % not found', p_token_id;
  END IF;
  IF v_grant.is_used THEN
    RAISE EXCEPTION 'admin_revoke_token_grant: grant % already used/revoked', p_token_id;
  END IF;

  UPDATE public.bora_tokens
     SET is_used = true,
         used_at = now()
   WHERE id = p_token_id;

  INSERT INTO public.admin_audit_log (
    admin_id, admin_email, action, entity_type, entity_id, details
  ) VALUES (
    v_admin.admin_id, v_admin.admin_email, 'tokens_revoke', 'user', v_grant.user_id,
    jsonb_build_object(
      'token_id', p_token_id,
      'amount', v_grant.amount,
      'role', v_grant.role,
      'reason', trim(p_reason)
    )
  );

  RETURN jsonb_build_object(
    'success', true, 'token_id', p_token_id,
    'amount', v_grant.amount, 'user_id', v_grant.user_id
  );
END;
$$;

REVOKE ALL ON FUNCTION public.admin_revoke_token_grant(UUID, TEXT) FROM public, anon;
GRANT EXECUTE ON FUNCTION public.admin_revoke_token_grant(UUID, TEXT) TO authenticated;


COMMIT;

-- ============================================================================
-- SMOKE TEST
-- ============================================================================
-- 1. Balance:      SELECT admin_get_user_tokens('<uuid>', 'client', 50);
-- 2. Grant:        SELECT admin_grant_tokens('<uuid>', 'client', 200, 'compensação atraso entrega');
-- 3. Revoke:       SELECT admin_revoke_token_grant('<token_id>', 'aplicação errada');
-- ============================================================================

-- ============================================================================
-- BORA — Promo Codes (Feature 9)
-- ============================================================================
-- Códigos promocionais com 3 tipos: percent_off, fixed_off, free_delivery.
-- Validações: validity, max_uses, max_uses_per_user, min_order, partner_ids.
-- 1 promo por pedido (regra Glovo).
-- ============================================================================

BEGIN;

CREATE TABLE IF NOT EXISTS public.promo_codes (
  code              TEXT PRIMARY KEY,
  type              TEXT NOT NULL CHECK (type IN ('percent_off','fixed_off','free_delivery')),
  value_cents       INTEGER,
  value_pct         NUMERIC,
  max_uses          INTEGER,
  uses_count        INTEGER NOT NULL DEFAULT 0,
  max_uses_per_user INTEGER NOT NULL DEFAULT 1,
  min_order_cents   INTEGER NOT NULL DEFAULT 0,
  valid_from        TIMESTAMPTZ NOT NULL DEFAULT now(),
  valid_until       TIMESTAMPTZ,
  partner_ids       TEXT[],
  is_active         BOOLEAN NOT NULL DEFAULT true,
  created_by_admin  UUID REFERENCES auth.users(id),
  created_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT promo_value_chk CHECK (
    (type = 'percent_off'  AND value_pct   IS NOT NULL AND value_pct   > 0 AND value_pct   <= 1) OR
    (type = 'fixed_off'    AND value_cents IS NOT NULL AND value_cents > 0) OR
    (type = 'free_delivery')
  )
);

CREATE INDEX IF NOT EXISTS idx_promo_codes_active
  ON public.promo_codes (is_active, valid_until);

CREATE TABLE IF NOT EXISTS public.promo_code_uses (
  id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  code                TEXT NOT NULL REFERENCES public.promo_codes(code) ON DELETE CASCADE,
  user_id             UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  order_id            TEXT,
  applied_value_cents INTEGER NOT NULL,
  used_at             TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_promo_uses_user
  ON public.promo_code_uses (user_id, code);
CREATE INDEX IF NOT EXISTS idx_promo_uses_order
  ON public.promo_code_uses (order_id);

ALTER TABLE public.promo_codes ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.promo_code_uses ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "promo_codes_select_active" ON public.promo_codes;
CREATE POLICY "promo_codes_select_active" ON public.promo_codes
  FOR SELECT TO authenticated USING (is_active = true);

DROP POLICY IF EXISTS "promo_uses_select_self" ON public.promo_code_uses;
CREATE POLICY "promo_uses_select_self" ON public.promo_code_uses
  FOR SELECT TO authenticated USING (
    user_id = auth.uid() OR
    COALESCE((auth.jwt()->'user_metadata'->>'bora_role'),(auth.jwt()->>'role'))='admin');

-- ── RPC: admin_create_promo_code ───────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.admin_create_promo_code(
  p_code              TEXT,
  p_type              TEXT,
  p_value_cents       INTEGER DEFAULT NULL,
  p_value_pct         NUMERIC DEFAULT NULL,
  p_max_uses          INTEGER DEFAULT NULL,
  p_max_uses_per_user INTEGER DEFAULT 1,
  p_min_order_cents   INTEGER DEFAULT 0,
  p_valid_until       TIMESTAMPTZ DEFAULT NULL,
  p_partner_ids       TEXT[] DEFAULT NULL
)
RETURNS public.promo_codes
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_admin RECORD;
  v_code  public.promo_codes;
BEGIN
  SELECT admin_id, admin_email INTO v_admin FROM public._admin_op_guard();

  INSERT INTO public.promo_codes
    (code, type, value_cents, value_pct, max_uses, max_uses_per_user,
     min_order_cents, valid_until, partner_ids, is_active, created_by_admin)
  VALUES
    (UPPER(trim(p_code)), p_type, p_value_cents, p_value_pct, p_max_uses,
     p_max_uses_per_user, p_min_order_cents, p_valid_until, p_partner_ids,
     true, v_admin.admin_id)
  RETURNING * INTO v_code;

  PERFORM public.log_admin_action('promo_code_created', 'promo_code', NULL,
    jsonb_build_object('code', v_code.code, 'type', v_code.type,
                       'value_cents', v_code.value_cents, 'value_pct', v_code.value_pct));
  RETURN v_code;
END;
$$;
REVOKE ALL ON FUNCTION public.admin_create_promo_code(TEXT,TEXT,INTEGER,NUMERIC,INTEGER,INTEGER,INTEGER,TIMESTAMPTZ,TEXT[]) FROM public, anon;
GRANT EXECUTE ON FUNCTION public.admin_create_promo_code(TEXT,TEXT,INTEGER,NUMERIC,INTEGER,INTEGER,INTEGER,TIMESTAMPTZ,TEXT[]) TO authenticated;

-- ── RPC: admin_list_promo_codes ────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.admin_list_promo_codes(
  p_active_only BOOLEAN DEFAULT FALSE,
  p_search      TEXT    DEFAULT NULL,
  p_limit       INT     DEFAULT 100,
  p_offset      INT     DEFAULT 0
)
RETURNS SETOF public.promo_codes
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  PERFORM public._admin_op_guard();
  RETURN QUERY
    SELECT * FROM public.promo_codes
    WHERE (NOT p_active_only OR is_active = true)
      AND (p_search IS NULL OR code ILIKE '%'||p_search||'%')
    ORDER BY created_at DESC
    LIMIT p_limit OFFSET p_offset;
END;
$$;
REVOKE ALL ON FUNCTION public.admin_list_promo_codes(BOOLEAN, TEXT, INT, INT) FROM public, anon;
GRANT EXECUTE ON FUNCTION public.admin_list_promo_codes(BOOLEAN, TEXT, INT, INT) TO authenticated;

-- ── RPC: admin_deactivate_promo_code ───────────────────────────────────────
CREATE OR REPLACE FUNCTION public.admin_deactivate_promo_code(
  p_code   TEXT,
  p_reason TEXT
)
RETURNS public.promo_codes
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_admin RECORD;
  v_row public.promo_codes;
BEGIN
  SELECT admin_id, admin_email INTO v_admin FROM public._admin_op_guard();
  UPDATE public.promo_codes SET is_active = false WHERE code = UPPER(trim(p_code))
  RETURNING * INTO v_row;
  IF v_row.code IS NULL THEN RAISE EXCEPTION 'promo_not_found'; END IF;
  PERFORM public.log_admin_action('promo_code_deactivated','promo_code', NULL,
    jsonb_build_object('code', v_row.code, 'reason', p_reason));
  RETURN v_row;
END;
$$;
REVOKE ALL ON FUNCTION public.admin_deactivate_promo_code(TEXT, TEXT) FROM public, anon;
GRANT EXECUTE ON FUNCTION public.admin_deactivate_promo_code(TEXT, TEXT) TO authenticated;

-- ── RPC: client_apply_promo_code (validação para checkout) ─────────────────
CREATE OR REPLACE FUNCTION public.client_apply_promo_code(
  p_code              TEXT,
  p_order_total_cents INTEGER,
  p_partner_id        TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user UUID := auth.uid();
  v_p public.promo_codes;
  v_user_uses INT;
  v_discount INT;
BEGIN
  IF v_user IS NULL THEN
    RETURN jsonb_build_object('valid', false, 'reason', 'unauthorized');
  END IF;
  SELECT * INTO v_p FROM public.promo_codes WHERE code = UPPER(trim(p_code));
  IF v_p.code IS NULL THEN
    RETURN jsonb_build_object('valid', false, 'reason', 'not_found');
  END IF;
  IF NOT v_p.is_active THEN
    RETURN jsonb_build_object('valid', false, 'reason', 'inactive');
  END IF;
  IF v_p.valid_until IS NOT NULL AND v_p.valid_until < now() THEN
    RETURN jsonb_build_object('valid', false, 'reason', 'expired');
  END IF;
  IF v_p.valid_from > now() THEN
    RETURN jsonb_build_object('valid', false, 'reason', 'not_yet_valid');
  END IF;
  IF v_p.max_uses IS NOT NULL AND v_p.uses_count >= v_p.max_uses THEN
    RETURN jsonb_build_object('valid', false, 'reason', 'max_uses_reached');
  END IF;
  IF p_order_total_cents < v_p.min_order_cents THEN
    RETURN jsonb_build_object(
      'valid', false, 'reason', 'min_order_not_met',
      'min_order_cents', v_p.min_order_cents);
  END IF;
  IF v_p.partner_ids IS NOT NULL AND array_length(v_p.partner_ids, 1) > 0
     AND (p_partner_id IS NULL OR NOT (p_partner_id = ANY (v_p.partner_ids)))
  THEN
    RETURN jsonb_build_object('valid', false, 'reason', 'partner_not_eligible');
  END IF;

  SELECT COUNT(*) INTO v_user_uses FROM public.promo_code_uses
  WHERE code = v_p.code AND user_id = v_user;
  IF v_user_uses >= v_p.max_uses_per_user THEN
    RETURN jsonb_build_object('valid', false, 'reason', 'user_limit_reached');
  END IF;

  -- Compute discount
  v_discount := CASE
    WHEN v_p.type = 'percent_off'  THEN ROUND(p_order_total_cents * v_p.value_pct)
    WHEN v_p.type = 'fixed_off'    THEN LEAST(v_p.value_cents, p_order_total_cents)
    WHEN v_p.type = 'free_delivery' THEN 0  -- discount aplicado a delivery_fee no checkout
    ELSE 0
  END;

  RETURN jsonb_build_object(
    'valid', true,
    'code', v_p.code,
    'type', v_p.type,
    'discount_cents', v_discount,
    'free_delivery', v_p.type = 'free_delivery'
  );
END;
$$;
REVOKE ALL ON FUNCTION public.client_apply_promo_code(TEXT, INTEGER, TEXT) FROM public, anon;
GRANT EXECUTE ON FUNCTION public.client_apply_promo_code(TEXT, INTEGER, TEXT) TO authenticated;

-- ── RPC: client_record_promo_use (chamado quando order é criada) ───────────
CREATE OR REPLACE FUNCTION public.client_record_promo_use(
  p_code              TEXT,
  p_order_id          TEXT,
  p_applied_value_cents INTEGER
)
RETURNS public.promo_code_uses
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user UUID := auth.uid();
  v_use  public.promo_code_uses;
BEGIN
  IF v_user IS NULL THEN RAISE EXCEPTION 'unauthorized'; END IF;

  INSERT INTO public.promo_code_uses (code, user_id, order_id, applied_value_cents)
  VALUES (UPPER(trim(p_code)), v_user, p_order_id, p_applied_value_cents)
  RETURNING * INTO v_use;

  UPDATE public.promo_codes SET uses_count = uses_count + 1
  WHERE code = UPPER(trim(p_code));

  RETURN v_use;
END;
$$;
REVOKE ALL ON FUNCTION public.client_record_promo_use(TEXT, TEXT, INTEGER) FROM public, anon;
GRANT EXECUTE ON FUNCTION public.client_record_promo_use(TEXT, TEXT, INTEGER) TO authenticated;

COMMIT;

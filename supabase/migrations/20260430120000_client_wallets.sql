-- ============================================================================
-- BORA — Client Wallets 80/20 (Feature 1)
-- ============================================================================
-- Saldo livre por cliente. NUNCA expira. Sem regras de uso.
-- Tokens permanecem em `bora_tokens` (Batch D — não duplicar).
--
-- Refund cliente cancela com choice → 80% saldo livre + 20% tokens.
-- Conversão: 1 token = €0.0005 = 0.05 cents.
-- Para 200 cents (20% de €10) → 200 * 20 = 4000 tokens.
-- (Math: tokens = cents * 100 / 5 = cents * 20)
--
-- Source of truth wallet_split_free_pct em platform_settings.
-- ============================================================================

BEGIN;

-- ── Tables ──────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.client_wallets (
  user_id            UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  free_balance_cents INTEGER NOT NULL DEFAULT 0 CHECK (free_balance_cents >= 0),
  created_at         TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at         TIMESTAMPTZ NOT NULL DEFAULT now()
);

ALTER TABLE public.client_wallets ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "wallet_select_self" ON public.client_wallets;
CREATE POLICY "wallet_select_self" ON public.client_wallets
  FOR SELECT TO authenticated USING (user_id = auth.uid());

DROP POLICY IF EXISTS "wallet_select_admin" ON public.client_wallets;
CREATE POLICY "wallet_select_admin" ON public.client_wallets
  FOR SELECT TO authenticated USING (
    COALESCE(
      (auth.jwt() -> 'user_metadata' ->> 'bora_role'),
      (auth.jwt() ->> 'role')
    ) = 'admin'
  );
-- Inserts/updates só via SECURITY DEFINER RPC.

CREATE TABLE IF NOT EXISTS public.wallet_transactions (
  id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id           UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  amount_cents      INTEGER NOT NULL,    -- positivo=credit, negativo=debit
  kind              TEXT NOT NULL CHECK (kind IN (
                      'refund_credit_free','refund_credit_tokens',
                      'order_payment','admin_grant','admin_revoke',
                      'cashback','referral')),
  reason            TEXT NOT NULL,
  related_order_id  TEXT,
  related_admin_id  UUID,
  created_at        TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_wallet_tx_user_created
  ON public.wallet_transactions (user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_wallet_tx_kind
  ON public.wallet_transactions (kind, created_at DESC);

ALTER TABLE public.wallet_transactions ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "wallet_tx_select_self" ON public.wallet_transactions;
CREATE POLICY "wallet_tx_select_self" ON public.wallet_transactions
  FOR SELECT TO authenticated USING (user_id = auth.uid());
DROP POLICY IF EXISTS "wallet_tx_select_admin" ON public.wallet_transactions;
CREATE POLICY "wallet_tx_select_admin" ON public.wallet_transactions
  FOR SELECT TO authenticated USING (
    COALESCE(
      (auth.jwt() -> 'user_metadata' ->> 'bora_role'),
      (auth.jwt() ->> 'role')
    ) = 'admin'
  );

-- ── RPC: wallet_get_balance ─────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.wallet_get_balance(
  p_user_id UUID DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_target  UUID;
  v_caller  UUID := auth.uid();
  v_role    TEXT := COALESCE(
    (auth.jwt() -> 'user_metadata' ->> 'bora_role'),
    (auth.jwt() ->> 'role'));
  v_free    INTEGER;
  v_tokens  INTEGER;
  v_tx      JSONB;
BEGIN
  v_target := COALESCE(p_user_id, v_caller);
  IF v_target <> v_caller AND v_role <> 'admin' THEN
    RAISE EXCEPTION 'forbidden' USING ERRCODE='42501';
  END IF;

  SELECT COALESCE(free_balance_cents, 0) INTO v_free
    FROM public.client_wallets WHERE user_id = v_target;
  v_free := COALESCE(v_free, 0);

  -- get_user_tokens existing RPC retorna a saldo total de tokens
  SELECT COALESCE((public.get_user_tokens(v_target)->>'balance')::int, 0) INTO v_tokens;

  SELECT COALESCE(jsonb_agg(t ORDER BY (t->>'created_at') DESC), '[]'::jsonb) INTO v_tx
  FROM (
    SELECT to_jsonb(wt.*) AS t
    FROM public.wallet_transactions wt
    WHERE wt.user_id = v_target
    ORDER BY wt.created_at DESC
    LIMIT 20
  ) sub;

  RETURN jsonb_build_object(
    'user_id', v_target,
    'free_cents', v_free,
    'tokens_balance', v_tokens,
    'token_value_cents_x100', COALESCE((public.get_setting('token_value_cents_x100'))::int, 5),
    'last_transactions', v_tx
  );
END;
$$;
REVOKE ALL ON FUNCTION public.wallet_get_balance(UUID) FROM public, anon;
GRANT EXECUTE ON FUNCTION public.wallet_get_balance(UUID) TO authenticated;

-- ── RPC: wallet_credit_refund_split ─────────────────────────────────────────
-- Chamado pela Edge Function cancel-order-with-choice quando cliente escolhe wallet.
-- NÃO requer admin auth — chamada com service-role key da Edge Function.
CREATE OR REPLACE FUNCTION public.wallet_credit_refund_split(
  p_order_id    TEXT,
  p_user_id     UUID,
  p_total_cents INTEGER,
  p_reason      TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_split_pct      NUMERIC;
  v_free_amount    INTEGER;
  v_tokens_amount  INTEGER;  -- em cents
  v_tokens_count   INTEGER;
BEGIN
  IF p_total_cents <= 0 THEN
    RAISE EXCEPTION 'total_must_be_positive';
  END IF;
  IF p_user_id IS NULL THEN
    RAISE EXCEPTION 'user_required';
  END IF;
  IF p_reason IS NULL OR length(trim(p_reason)) < 3 THEN
    RAISE EXCEPTION 'reason_required';
  END IF;

  -- Lê split de platform_settings (default 0.80)
  SELECT COALESCE((public.get_setting('wallet_split_free_pct'))::numeric, 0.80)
    INTO v_split_pct;

  v_free_amount   := ROUND(p_total_cents * v_split_pct);
  v_tokens_amount := p_total_cents - v_free_amount;
  -- 1 token = 0.05 cents → tokens_count = cents * 100 / 5 = cents * 20
  v_tokens_count  := v_tokens_amount * 20;

  -- 1) UPSERT free balance
  INSERT INTO public.client_wallets (user_id, free_balance_cents, updated_at)
  VALUES (p_user_id, v_free_amount, now())
  ON CONFLICT (user_id) DO UPDATE
    SET free_balance_cents = public.client_wallets.free_balance_cents + EXCLUDED.free_balance_cents,
        updated_at = now();

  INSERT INTO public.wallet_transactions
    (user_id, amount_cents, kind, reason, related_order_id)
  VALUES
    (p_user_id, v_free_amount, 'refund_credit_free', p_reason, p_order_id);

  -- 2) Tokens via RPC existente add_tokens(user_id, role, amount, source_order_id)
  IF v_tokens_count > 0 THEN
    PERFORM public.add_tokens(p_user_id, 'client', v_tokens_count, p_order_id);
    INSERT INTO public.wallet_transactions
      (user_id, amount_cents, kind, reason, related_order_id)
    VALUES
      (p_user_id, v_tokens_amount, 'refund_credit_tokens',
       p_reason || ' (' || v_tokens_count || ' tokens)', p_order_id);
  END IF;

  -- 3) Audit (best-effort — não falhar se admin context ausente)
  BEGIN
    PERFORM public.log_admin_action(
      'wallet_refund_split',
      'order',
      NULL,
      jsonb_build_object(
        'order_id', p_order_id,
        'user_id', p_user_id,
        'total_cents', p_total_cents,
        'free_cents', v_free_amount,
        'tokens_cents_value', v_tokens_amount,
        'tokens_count', v_tokens_count,
        'split_pct', v_split_pct
      ));
  EXCEPTION WHEN OTHERS THEN
    -- chamada por Edge Function pode não ter contexto admin → ok
    NULL;
  END;

  RETURN jsonb_build_object(
    'success',         true,
    'free_cents',      v_free_amount,
    'tokens_count',    v_tokens_count,
    'tokens_value_cents', v_tokens_amount,
    'split_pct',       v_split_pct
  );
END;
$$;
REVOKE ALL ON FUNCTION public.wallet_credit_refund_split(TEXT, UUID, INTEGER, TEXT) FROM public, anon;
GRANT EXECUTE ON FUNCTION public.wallet_credit_refund_split(TEXT, UUID, INTEGER, TEXT) TO authenticated, service_role;

-- ── RPC: wallet_debit_for_order ─────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.wallet_debit_for_order(
  p_user_id     UUID,
  p_order_id    TEXT,
  p_amount_cents INTEGER
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_balance INTEGER;
BEGIN
  IF p_amount_cents <= 0 THEN
    RAISE EXCEPTION 'amount_must_be_positive';
  END IF;

  SELECT free_balance_cents INTO v_balance
  FROM public.client_wallets
  WHERE user_id = p_user_id
  FOR UPDATE;

  IF v_balance IS NULL OR v_balance < p_amount_cents THEN
    RAISE EXCEPTION 'insufficient_balance: have=%, need=%',
      COALESCE(v_balance, 0), p_amount_cents USING ERRCODE='23514';
  END IF;

  UPDATE public.client_wallets
  SET free_balance_cents = free_balance_cents - p_amount_cents,
      updated_at = now()
  WHERE user_id = p_user_id;

  INSERT INTO public.wallet_transactions
    (user_id, amount_cents, kind, reason, related_order_id)
  VALUES
    (p_user_id, -p_amount_cents, 'order_payment',
     'Pagamento pedido com saldo livre', p_order_id);

  RETURN jsonb_build_object(
    'success', true,
    'debited_cents', p_amount_cents,
    'new_balance_cents', v_balance - p_amount_cents
  );
END;
$$;
REVOKE ALL ON FUNCTION public.wallet_debit_for_order(UUID, TEXT, INTEGER) FROM public, anon;
GRANT EXECUTE ON FUNCTION public.wallet_debit_for_order(UUID, TEXT, INTEGER) TO authenticated, service_role;

-- ── RPC: wallet_credit_generic (helper para cashback / referral) ────────────
CREATE OR REPLACE FUNCTION public.wallet_credit_generic(
  p_user_id     UUID,
  p_amount_cents INTEGER,
  p_kind        TEXT,
  p_reason      TEXT,
  p_related_order_id TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF p_amount_cents <= 0 THEN
    RAISE EXCEPTION 'amount_must_be_positive';
  END IF;
  IF p_kind NOT IN ('cashback','referral','admin_grant') THEN
    RAISE EXCEPTION 'invalid_kind: %', p_kind;
  END IF;

  INSERT INTO public.client_wallets (user_id, free_balance_cents, updated_at)
  VALUES (p_user_id, p_amount_cents, now())
  ON CONFLICT (user_id) DO UPDATE
    SET free_balance_cents = public.client_wallets.free_balance_cents + EXCLUDED.free_balance_cents,
        updated_at = now();

  INSERT INTO public.wallet_transactions
    (user_id, amount_cents, kind, reason, related_order_id)
  VALUES
    (p_user_id, p_amount_cents, p_kind, p_reason, p_related_order_id);

  RETURN jsonb_build_object('success', true, 'credited_cents', p_amount_cents);
END;
$$;
REVOKE ALL ON FUNCTION public.wallet_credit_generic(UUID, INTEGER, TEXT, TEXT, TEXT) FROM public, anon;
GRANT EXECUTE ON FUNCTION public.wallet_credit_generic(UUID, INTEGER, TEXT, TEXT, TEXT) TO authenticated, service_role;

-- ── RPC admin: grant / revoke / list ────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.admin_grant_wallet_free(
  p_user_id     UUID,
  p_amount_cents INTEGER,
  p_reason      TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_admin RECORD;
BEGIN
  SELECT admin_id, admin_email INTO v_admin FROM public._admin_op_guard();
  IF p_amount_cents <= 0 THEN RAISE EXCEPTION 'amount_must_be_positive'; END IF;
  IF p_reason IS NULL OR length(trim(p_reason)) < 3 THEN
    RAISE EXCEPTION 'reason_required';
  END IF;

  INSERT INTO public.client_wallets (user_id, free_balance_cents, updated_at)
  VALUES (p_user_id, p_amount_cents, now())
  ON CONFLICT (user_id) DO UPDATE
    SET free_balance_cents = public.client_wallets.free_balance_cents + EXCLUDED.free_balance_cents,
        updated_at = now();

  INSERT INTO public.wallet_transactions
    (user_id, amount_cents, kind, reason, related_admin_id)
  VALUES (p_user_id, p_amount_cents, 'admin_grant', p_reason, v_admin.admin_id);

  PERFORM public.log_admin_action('wallet_free_granted', 'user', p_user_id,
    jsonb_build_object('amount_cents', p_amount_cents, 'reason', p_reason));

  RETURN jsonb_build_object('success', true);
END;
$$;
REVOKE ALL ON FUNCTION public.admin_grant_wallet_free(UUID, INTEGER, TEXT) FROM public, anon;
GRANT EXECUTE ON FUNCTION public.admin_grant_wallet_free(UUID, INTEGER, TEXT) TO authenticated;

CREATE OR REPLACE FUNCTION public.admin_revoke_wallet_free(
  p_user_id     UUID,
  p_amount_cents INTEGER,
  p_reason      TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_admin RECORD;
  v_balance INTEGER;
BEGIN
  SELECT admin_id, admin_email INTO v_admin FROM public._admin_op_guard();
  IF p_amount_cents <= 0 THEN RAISE EXCEPTION 'amount_must_be_positive'; END IF;
  IF p_reason IS NULL OR length(trim(p_reason)) < 3 THEN
    RAISE EXCEPTION 'reason_required';
  END IF;

  SELECT free_balance_cents INTO v_balance
  FROM public.client_wallets WHERE user_id = p_user_id FOR UPDATE;

  IF COALESCE(v_balance, 0) < p_amount_cents THEN
    RAISE EXCEPTION 'insufficient_balance: have=%, revoke=%',
      COALESCE(v_balance, 0), p_amount_cents USING ERRCODE='23514';
  END IF;

  UPDATE public.client_wallets
    SET free_balance_cents = free_balance_cents - p_amount_cents, updated_at = now()
  WHERE user_id = p_user_id;

  INSERT INTO public.wallet_transactions
    (user_id, amount_cents, kind, reason, related_admin_id)
  VALUES (p_user_id, -p_amount_cents, 'admin_revoke', p_reason, v_admin.admin_id);

  PERFORM public.log_admin_action('wallet_free_revoked', 'user', p_user_id,
    jsonb_build_object('amount_cents', p_amount_cents, 'reason', p_reason));

  RETURN jsonb_build_object('success', true,
    'new_balance_cents', v_balance - p_amount_cents);
END;
$$;
REVOKE ALL ON FUNCTION public.admin_revoke_wallet_free(UUID, INTEGER, TEXT) FROM public, anon;
GRANT EXECUTE ON FUNCTION public.admin_revoke_wallet_free(UUID, INTEGER, TEXT) TO authenticated;

CREATE OR REPLACE FUNCTION public.admin_list_wallets(
  p_search       TEXT    DEFAULT NULL,
  p_min_balance  INTEGER DEFAULT NULL,
  p_limit        INT     DEFAULT 50,
  p_offset       INT     DEFAULT 0
)
RETURNS TABLE (
  user_id UUID,
  email TEXT,
  full_name TEXT,
  free_balance_cents INTEGER,
  tokens_balance INTEGER,
  last_tx_at TIMESTAMPTZ
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  PERFORM public._admin_op_guard();
  RETURN QUERY
    SELECT
      cw.user_id,
      au.email::text,
      (au.raw_user_meta_data->>'full_name')::text AS full_name,
      cw.free_balance_cents,
      COALESCE((public.get_user_tokens(cw.user_id)->>'balance')::int, 0) AS tokens_balance,
      (SELECT max(created_at) FROM public.wallet_transactions wt WHERE wt.user_id = cw.user_id) AS last_tx_at
    FROM public.client_wallets cw
    JOIN auth.users au ON au.id = cw.user_id
    WHERE
      (p_search IS NULL OR
        au.email ILIKE '%'||p_search||'%' OR
        (au.raw_user_meta_data->>'full_name') ILIKE '%'||p_search||'%')
      AND (p_min_balance IS NULL OR cw.free_balance_cents >= p_min_balance)
    ORDER BY cw.free_balance_cents DESC
    LIMIT p_limit OFFSET p_offset;
END;
$$;
REVOKE ALL ON FUNCTION public.admin_list_wallets(TEXT, INTEGER, INT, INT) FROM public, anon;
GRANT EXECUTE ON FUNCTION public.admin_list_wallets(TEXT, INTEGER, INT, INT) TO authenticated;

COMMIT;

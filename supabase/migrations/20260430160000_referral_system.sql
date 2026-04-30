-- ============================================================================
-- BORA — Referral System (Feature 10)
-- ============================================================================
-- Cada user pode ter código (BORA-DAN-A4F). Convidado dá signup com código.
-- 1º pedido entregue (≥ ref_min_first_order) → ambos recebem ref reward em
-- saldo livre. Convite expira em ref_invite_expires_days.
-- ============================================================================

BEGIN;

CREATE TABLE IF NOT EXISTS public.referral_codes (
  user_id           UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  code              TEXT UNIQUE NOT NULL,
  invites_sent      INTEGER NOT NULL DEFAULT 0,
  invites_completed INTEGER NOT NULL DEFAULT 0,
  total_earned_cents INTEGER NOT NULL DEFAULT 0,
  created_at        TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.referral_invites (
  id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  referrer_user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  invited_user_id  UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  invited_email    TEXT,
  status           TEXT NOT NULL DEFAULT 'pending'
                     CHECK (status IN ('pending','signed_up','first_order_done','expired')),
  signed_up_at     TIMESTAMPTZ,
  first_order_at   TIMESTAMPTZ,
  reward_paid_at   TIMESTAMPTZ,
  expires_at       TIMESTAMPTZ NOT NULL,
  created_at       TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_referral_invites_referrer
  ON public.referral_invites (referrer_user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_referral_invites_invited
  ON public.referral_invites (invited_user_id) WHERE invited_user_id IS NOT NULL;

ALTER TABLE public.referral_codes ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.referral_invites ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "ref_codes_select_self" ON public.referral_codes;
CREATE POLICY "ref_codes_select_self" ON public.referral_codes
  FOR SELECT TO authenticated USING (user_id = auth.uid());
DROP POLICY IF EXISTS "ref_codes_select_admin" ON public.referral_codes;
CREATE POLICY "ref_codes_select_admin" ON public.referral_codes
  FOR SELECT TO authenticated USING (
    COALESCE((auth.jwt()->'user_metadata'->>'bora_role'),(auth.jwt()->>'role'))='admin');

DROP POLICY IF EXISTS "ref_invites_select_self" ON public.referral_invites;
CREATE POLICY "ref_invites_select_self" ON public.referral_invites
  FOR SELECT TO authenticated USING (referrer_user_id = auth.uid() OR invited_user_id = auth.uid());
DROP POLICY IF EXISTS "ref_invites_select_admin" ON public.referral_invites;
CREATE POLICY "ref_invites_select_admin" ON public.referral_invites
  FOR SELECT TO authenticated USING (
    COALESCE((auth.jwt()->'user_metadata'->>'bora_role'),(auth.jwt()->>'role'))='admin');

-- ── Helper: gerar código único ─────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public._gen_referral_code(p_user_id UUID)
RETURNS TEXT
LANGUAGE plpgsql
AS $$
DECLARE
  v_full_name TEXT;
  v_prefix    TEXT;
  v_suffix    TEXT;
  v_code      TEXT;
  v_attempts  INT := 0;
BEGIN
  SELECT (raw_user_meta_data->>'full_name') INTO v_full_name FROM auth.users WHERE id = p_user_id;
  v_prefix := UPPER(REGEXP_REPLACE(COALESCE(v_full_name, 'BORA'), '[^A-Za-z]', '', 'g'));
  v_prefix := LEFT(COALESCE(NULLIF(v_prefix, ''), 'BORA'), 3);
  LOOP
    v_suffix := UPPER(SUBSTRING(MD5(random()::text || clock_timestamp()::text) FROM 1 FOR 4));
    v_code := 'BORA-' || v_prefix || '-' || v_suffix;
    EXIT WHEN NOT EXISTS (SELECT 1 FROM public.referral_codes WHERE code = v_code);
    v_attempts := v_attempts + 1;
    IF v_attempts > 10 THEN
      RAISE EXCEPTION 'Failed to generate unique referral code after 10 attempts';
    END IF;
  END LOOP;
  RETURN v_code;
END;
$$;

-- ── RPC: client_get_or_create_referral_code ────────────────────────────────
CREATE OR REPLACE FUNCTION public.client_get_or_create_referral_code()
RETURNS public.referral_codes
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user UUID := auth.uid();
  v_row  public.referral_codes;
BEGIN
  IF v_user IS NULL THEN
    RAISE EXCEPTION 'unauthorized' USING ERRCODE='42501';
  END IF;

  SELECT * INTO v_row FROM public.referral_codes WHERE user_id = v_user;
  IF v_row.user_id IS NULL THEN
    INSERT INTO public.referral_codes (user_id, code)
    VALUES (v_user, public._gen_referral_code(v_user))
    RETURNING * INTO v_row;
  END IF;
  RETURN v_row;
END;
$$;
REVOKE ALL ON FUNCTION public.client_get_or_create_referral_code() FROM public, anon;
GRANT EXECUTE ON FUNCTION public.client_get_or_create_referral_code() TO authenticated;

-- ── RPC: client_register_with_referral ─────────────────────────────────────
-- Chamado durante signup (cliente). Cria invite 'signed_up'.
CREATE OR REPLACE FUNCTION public.client_register_with_referral(
  p_referral_code TEXT
)
RETURNS public.referral_invites
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user        UUID := auth.uid();
  v_referrer_id UUID;
  v_invite      public.referral_invites;
  v_expires_days INT;
BEGIN
  IF v_user IS NULL THEN RAISE EXCEPTION 'unauthorized' USING ERRCODE='42501'; END IF;
  IF p_referral_code IS NULL OR length(trim(p_referral_code)) = 0 THEN
    RAISE EXCEPTION 'code_required';
  END IF;

  SELECT user_id INTO v_referrer_id FROM public.referral_codes WHERE code = trim(p_referral_code);
  IF v_referrer_id IS NULL THEN
    RAISE EXCEPTION 'invalid_referral_code';
  END IF;
  IF v_referrer_id = v_user THEN
    RAISE EXCEPTION 'cannot_self_refer';
  END IF;

  -- Já tem invite?
  IF EXISTS (SELECT 1 FROM public.referral_invites
             WHERE invited_user_id = v_user AND status <> 'expired') THEN
    RAISE EXCEPTION 'already_referred';
  END IF;

  SELECT COALESCE((public.get_setting('referral_invite_expires_days'))::int, 30) INTO v_expires_days;

  INSERT INTO public.referral_invites
    (referrer_user_id, invited_user_id, status, signed_up_at, expires_at)
  VALUES
    (v_referrer_id, v_user, 'signed_up', now(), now() + (v_expires_days || ' days')::interval)
  RETURNING * INTO v_invite;

  UPDATE public.referral_codes
  SET invites_sent = invites_sent + 1
  WHERE user_id = v_referrer_id;

  RETURN v_invite;
END;
$$;
REVOKE ALL ON FUNCTION public.client_register_with_referral(TEXT) FROM public, anon;
GRANT EXECUTE ON FUNCTION public.client_register_with_referral(TEXT) TO authenticated;

-- ── Trigger: 1º pedido entregue do invited → reward ambos ──────────────────
CREATE OR REPLACE FUNCTION public.fn_referral_reward_on_first_delivery()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_invite     public.referral_invites;
  v_min_total  INTEGER;
  v_total_cents INTEGER;
  v_referrer_reward INTEGER;
  v_invited_reward  INTEGER;
BEGIN
  IF NEW.status <> 'delivered' OR OLD.status = 'delivered' THEN RETURN NEW; END IF;
  IF NEW.user_id IS NULL THEN RETURN NEW; END IF;

  -- Buscar invite válido para este utilizador
  SELECT * INTO v_invite FROM public.referral_invites
  WHERE invited_user_id = NEW.user_id
    AND status = 'signed_up'
    AND expires_at > now()
  LIMIT 1;
  IF v_invite.id IS NULL THEN RETURN NEW; END IF;

  SELECT COALESCE((public.get_setting('referral_min_first_order_cents'))::int, 1000)
    INTO v_min_total;

  v_total_cents := COALESCE(
    ROUND(COALESCE(NEW.customer_total, NEW.final_total, NEW.total, 0)::numeric * 100), 0);
  IF v_total_cents < v_min_total THEN RETURN NEW; END IF;

  SELECT COALESCE((public.get_setting('referral_referrer_reward_cents'))::int, 500)
    INTO v_referrer_reward;
  SELECT COALESCE((public.get_setting('referral_invited_reward_cents'))::int, 500)
    INTO v_invited_reward;

  -- Credita referrer
  PERFORM public.wallet_credit_generic(
    v_invite.referrer_user_id, v_referrer_reward, 'referral',
    'Referral: convite ' || v_invite.id || ' completou 1º pedido', NEW.id);
  -- Credita invited
  PERFORM public.wallet_credit_generic(
    NEW.user_id, v_invited_reward, 'referral',
    'Referral: bem-vindo ao Bora!', NEW.id);

  -- Marca invite como completed
  UPDATE public.referral_invites
  SET status = 'first_order_done',
      first_order_at = now(),
      reward_paid_at = now()
  WHERE id = v_invite.id;

  UPDATE public.referral_codes
  SET invites_completed = invites_completed + 1,
      total_earned_cents = total_earned_cents + v_referrer_reward
  WHERE user_id = v_invite.referrer_user_id;

  RETURN NEW;
EXCEPTION WHEN OTHERS THEN
  RAISE WARNING 'fn_referral_reward failed: %', SQLERRM;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_referral_reward ON public.orders;
CREATE TRIGGER trg_referral_reward
  AFTER UPDATE OF status ON public.orders
  FOR EACH ROW
  WHEN (NEW.status = 'delivered' AND OLD.status IS DISTINCT FROM 'delivered')
  EXECUTE FUNCTION public.fn_referral_reward_on_first_delivery();

COMMIT;

-- ============================================================================
-- BLOCO B (2026-05-18) — RLS hardening admin_mark_partner_credits_paid
-- ============================================================================
--
-- A função `admin_mark_partner_credits_paid` (migration 20260510125648) só
-- verifica `auth.uid() IS NULL` — qualquer utilizador AUTENTICADO podia
-- invocá-la e marcar pagamentos a parceiros como pagos. Isto é uma RPC
-- financeira (paga €2 por reserva chegada ao parceiro), pelo que precisa
-- guard de admin.
--
-- Esta migration faz CREATE OR REPLACE da função adicionando guard de
-- `app_metadata.role = 'admin'` — padrão usado por
-- `admin_dashboard_metrics` (20260409000005), `admin_forgive_wallet_debt`
-- (20260504060000) e várias outras admin RPCs.
--
-- COMPATIBILIDADE:
--   • Idempotente (CREATE OR REPLACE)
--   • Assinatura preservada (text, timestamptz, timestamptz → jsonb)
--   • Comportamento idêntico para callers admin legítimos
--   • Bloqueia callers não-admin (que antes podiam passar — bug latente)
--
-- AUDITORIA: scan automatizado em 2026-05-18 identificou 11 migrations
-- suspect; classificou 14/16 funções como GUARDED (RAISE EXCEPTION ou role
-- check). Apenas 2 UNGUARDED reais: `admin_dashboard_metrics` (falso
-- positivo — overridden por 20260409000005 com guard) e esta função.
-- ============================================================================

BEGIN;

CREATE OR REPLACE FUNCTION public.admin_mark_partner_credits_paid(
  p_restaurant_id text,
  p_week_start    timestamptz,
  p_week_end      timestamptz
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_admin_id uuid := auth.uid();
  result     jsonb;
BEGIN
  -- ─── BLOCO B (2026-05-18) — Guard de admin (server-side) ───────────────
  IF v_admin_id IS NULL THEN
    RAISE EXCEPTION 'auth_required'
      USING ERRCODE = 'insufficient_privilege';
  END IF;
  IF COALESCE(
       (auth.jwt() -> 'app_metadata' ->> 'role'),
       (auth.jwt() ->> 'role')
     ) IS DISTINCT FROM 'admin'
  THEN
    RAISE EXCEPTION 'admin_mark_partner_credits_paid: insufficient privilege'
      USING ERRCODE = 'insufficient_privilege',
            HINT    = 'Set app_metadata.role=admin on this auth user via the service-role API.';
  END IF;

  WITH updated AS (
    UPDATE public.restaurant_menu_credits
       SET paid_to_partner_at = NOW(),
           paid_to_partner_by = v_admin_id
     WHERE restaurant_id = p_restaurant_id
       AND used_at IS NOT NULL
       AND paid_to_partner_at IS NULL
       AND used_at >= p_week_start
       AND used_at <  p_week_end
    RETURNING amount_cents
  )
  SELECT jsonb_build_object(
    'success',     true,
    'count',       COUNT(*),
    'total_cents', COALESCE(SUM(amount_cents), 0)
  )
  INTO STRICT result
  FROM updated;

  RETURN result;
END;
$$;

COMMENT ON FUNCTION public.admin_mark_partner_credits_paid(text, timestamptz, timestamptz) IS
  'BLOCO B 2026-05-18 — Hardened: requires app_metadata.role=admin. Antes só verificava auth.uid IS NULL (qualquer user autenticado podia invocar).';

REVOKE ALL ON FUNCTION public.admin_mark_partner_credits_paid(text, timestamptz, timestamptz)
  FROM public, anon;
GRANT EXECUTE ON FUNCTION public.admin_mark_partner_credits_paid(text, timestamptz, timestamptz)
  TO authenticated;

COMMIT;

-- Partner credit settlements (acerto semanal de reservas)
--
-- Adiciona dois campos a `restaurant_menu_credits` para marcar quando o
-- crédito de €2 foi pago ao parceiro no acerto semanal manual feito pelo
-- admin. RPC `admin_mark_partner_credits_paid` faz o UPDATE atomicamente
-- via CTE com RETURNING e devolve o resumo ({count, total_cents}).

ALTER TABLE public.restaurant_menu_credits
  ADD COLUMN IF NOT EXISTS paid_to_partner_at timestamptz,
  ADD COLUMN IF NOT EXISTS paid_to_partner_by uuid REFERENCES auth.users(id);

CREATE INDEX IF NOT EXISTS restaurant_menu_credits_payout_idx
  ON public.restaurant_menu_credits (restaurant_id, used_at)
  WHERE used_at IS NOT NULL AND paid_to_partner_at IS NULL;

COMMENT ON COLUMN public.restaurant_menu_credits.paid_to_partner_at IS
  'Quando o crédito (€2) foi pago ao parceiro no acerto semanal manual.';
COMMENT ON COLUMN public.restaurant_menu_credits.paid_to_partner_by IS
  'Admin que marcou o crédito como pago.';

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
  IF v_admin_id IS NULL THEN RAISE EXCEPTION 'auth_required'; END IF;

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

GRANT EXECUTE ON FUNCTION public.admin_mark_partner_credits_paid(text, timestamptz, timestamptz)
  TO authenticated;

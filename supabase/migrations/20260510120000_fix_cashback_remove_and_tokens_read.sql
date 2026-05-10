-- ============================================================================
-- Fix dual: remover cashback automático 1% (BUG 1) + corrigir leitura tokens
-- em wallet_get_balance (BUG 2 / nota residual BUG-7E-B-007).
--
-- BUG 1: trigger trg_award_cashback + função fn_award_cashback_on_delivery
--        creditavam 1% (platform_settings.cashback_pct=0.01) em qualquer
--        pedido entregue, regra que NUNCA existiu. Refund 80/20 fica intacto.
--
-- BUG 2: wallet_get_balance trata get_user_tokens() como JSONB (->>'balance')
--        mas a função retorna INTEGER directo. Exception silenciosa devolvia
--        sempre 0 (apesar de a função pura retornar 748 para CAA3A9).
--
-- Sem backfill, sem estorno (decisão Danilo 2026-05-10).
-- ============================================================================

BEGIN;

-- ── BUG 1: remover infraestrutura de cashback automático ────────────────────
DROP TRIGGER IF EXISTS trg_award_cashback ON public.orders;
DROP FUNCTION IF EXISTS public.fn_award_cashback_on_delivery();

-- Remover setting que disparava o 1% (default fallback ficava 0.01)
DELETE FROM public.platform_settings WHERE key = 'cashback_pct';

-- ── BUG 2: corrigir leitura de tokens em wallet_get_balance ─────────────────
-- get_user_tokens(uuid) RETURNS INTEGER. Usar directo, sem cast JSONB.
CREATE OR REPLACE FUNCTION public.wallet_get_balance(p_user_id uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_target  UUID;
  v_caller  UUID := auth.uid();
  v_role    TEXT := COALESCE((auth.jwt() -> 'user_metadata' ->> 'bora_role'),(auth.jwt() ->> 'role'));
  v_free    INTEGER;
  v_tokens  INTEGER;
  v_tx      JSONB;
BEGIN
  v_target := COALESCE(p_user_id, v_caller);
  IF v_target <> v_caller AND v_role <> 'admin' THEN
    RAISE EXCEPTION 'forbidden' USING ERRCODE='42501';
  END IF;

  SELECT COALESCE(free_balance_cents, 0) INTO v_free FROM public.client_wallets WHERE user_id = v_target;
  v_free := COALESCE(v_free, 0);

  -- FIX: get_user_tokens retorna INTEGER, não JSONB.
  -- O try/except permanece como safety net mas já não engole erro de cast inexistente.
  BEGIN
    v_tokens := COALESCE(public.get_user_tokens(v_target), 0);
  EXCEPTION WHEN OTHERS THEN
    v_tokens := 0;
  END;

  SELECT COALESCE(jsonb_agg(t ORDER BY (t->>'created_at') DESC), '[]'::jsonb) INTO v_tx
  FROM (
    SELECT to_jsonb(wt.*) AS t FROM public.wallet_transactions wt
    WHERE wt.user_id = v_target ORDER BY wt.created_at DESC LIMIT 20
  ) sub;

  RETURN jsonb_build_object(
    'user_id', v_target,
    'free_cents', v_free,
    'tokens_balance', v_tokens,
    'token_value_cents_x100', COALESCE((public.get_setting('token_value_cents_x100'))::int, 5),
    'last_transactions', v_tx);
END;
$function$;

COMMIT;

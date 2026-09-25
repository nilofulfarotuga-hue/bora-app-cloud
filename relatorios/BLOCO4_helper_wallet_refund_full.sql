-- ============================================================================
-- BLOCO 4 — Helper a aplicar JUNTO com o redeploy da Edge Function (NÃO antes).
-- Reembolso 100% saldo livre (E1 grace, sem tokens). Settlement-first.
-- (As settings cancel_grace_seconds=180 e cancel_fee_after_accept_driver_cents=150
--  JÁ foram aplicadas e estão editáveis no admin.)
-- ============================================================================
CREATE OR REPLACE FUNCTION public.wallet_credit_refund_full(
  p_order_id text, p_user_id uuid, p_total_cents integer, p_reason text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
DECLARE v_before int; v_debt int := 0; v_remaining int; v_mid int;
BEGIN
  IF p_total_cents <= 0 THEN RAISE EXCEPTION 'total_must_be_positive'; END IF;
  IF p_user_id IS NULL THEN RAISE EXCEPTION 'user_required'; END IF;
  INSERT INTO public.client_wallets (user_id, free_balance_cents)
    VALUES (p_user_id, 0) ON CONFLICT (user_id) DO NOTHING;
  SELECT free_balance_cents INTO v_before FROM public.client_wallets WHERE user_id = p_user_id FOR UPDATE;
  v_remaining := p_total_cents;
  IF v_before < 0 THEN
    v_debt := LEAST(-v_before, v_remaining); v_mid := v_before + v_debt;
    UPDATE public.client_wallets SET free_balance_cents = v_mid, updated_at = now() WHERE user_id = p_user_id;
    INSERT INTO public.wallet_transactions (user_id, amount_cents, kind, reason, related_order_id, balance_after_cents)
      VALUES (p_user_id, v_debt, 'settlement', p_reason || ' (refund→settle debt)', p_order_id, v_mid);
    v_remaining := v_remaining - v_debt;
  ELSE v_mid := v_before; END IF;
  IF v_remaining > 0 THEN
    UPDATE public.client_wallets SET free_balance_cents = free_balance_cents + v_remaining, updated_at = now() WHERE user_id = p_user_id;
    INSERT INTO public.wallet_transactions (user_id, amount_cents, kind, reason, related_order_id, balance_after_cents)
      VALUES (p_user_id, v_remaining, 'refund_credit_free', p_reason, p_order_id, v_mid + v_remaining);
  END IF;
  RETURN jsonb_build_object('success', true, 'free_cents', p_total_cents, 'debt_cleared_cents', v_debt);
END;
$function$;

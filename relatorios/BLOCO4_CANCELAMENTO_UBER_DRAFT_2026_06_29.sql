-- ⚠️⚠️ SUPERSEDED 2026-06-29 — NÃO USAR. ⚠️⚠️
-- A RPC request_order_cancel é ÓRFÃ (não é o motor real). O motor do cancelamento
-- do cliente é a Edge Function client-cancel-order. Ver BLOCO4_PLANO_FINAL.md +
-- BLOCO4_client-cancel-order_PROPOSTA.ts. Este ficheiro fica só como histórico.
-- ============================================================================
-- BLOCO 4 — CANCELAMENTO ESTILO UBER  (DRAFT — NÃO APLICAR SEM APROVAÇÃO)
-- ----------------------------------------------------------------------------
-- ⚠️ LISTA VERMELHA / DINHEIRO REAL. Este ficheiro NÃO foi aplicado em produção.
--    Flip = aprovação 1-clique do Danilo. Mexe em reembolso/taxa automáticos.
--
-- Estado HOJE (confirmado via MCP 2026-06-29):
--   request_order_cancel() = 100% manual → insere cancellation_requests 'pending'
--   sem janela de tempo, sem regra por estado. NÃO existe cancel_grace_seconds.
--
-- Settings JÁ existentes (não recriar):
--   cancel_fee_before_dispatch_cents = 100   (1,00 €)
--   cancel_fee_after_accept_cents    = 250   (2,50 €)
--   cancel_fee_after_pickup_ratio    = 1.00  (100% — sem reembolso)
--   wallet_cancel_hard_floor_cents   = -4000
-- RPCs JÁ existentes: compute_refund_split, wallet_credit_refund_split.
--
-- MATEMÁTICA AO CÊNTIMO (customer_total exemplo = 12,00 €):
--   1) Dentro da janela (≤180s)          → taxa 0,00 € · reembolso 12,00 €
--   2) Antes de dispatch (created/preparing) → taxa 1,00 € · reembolso 11,00 €
--   3) Depois de aceite (callingDriver/driverAccepted) → taxa 2,50 € · reembolso 9,50 €
--   4) Depois do pickup (pickedUp/onTheWay) → ratio 1.00 → taxa 12,00 € · reembolso 0,00 €
--   (cash = não houve cobrança prévia → não há reembolso a mover; só status='cancelled')
-- ============================================================================

-- 1) Setting novo (aditivo, editável no admin) -------------------------------
INSERT INTO public.platform_settings (key, value)
VALUES ('cancel_grace_seconds', '180'::jsonb)
ON CONFLICT (key) DO NOTHING;

-- 2) Colunas aditivas de auditoria do caminho automático ---------------------
ALTER TABLE public.cancellation_requests
  ADD COLUMN IF NOT EXISTS auto_resolved boolean,
  ADD COLUMN IF NOT EXISTS cancel_stage  text,
  ADD COLUMN IF NOT EXISTS fee_cents     integer,
  ADD COLUMN IF NOT EXISTS refund_cents  integer;

-- 3) Nova request_order_cancel: janela de graça + por estado, automático -----
--    Caminho normal (regra clara) = decide e processa sozinho.
--    Disputa (cliente contesta) continua a ir a 'pending' para o admin.
CREATE OR REPLACE FUNCTION public.request_order_cancel(
  p_order_id text,
  p_reason   text,
  p_dispute  boolean DEFAULT false   -- aditivo: true = forçar fila admin (disputa)
)
RETURNS public.cancellation_requests
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
DECLARE
  v_user UUID := auth.uid();
  v_role TEXT;
  v_order RECORD;
  v_req public.cancellation_requests;
  v_grace_s   int  := COALESCE((SELECT value::text::int FROM platform_settings WHERE key='cancel_grace_seconds'), 180);
  v_fee_before int := COALESCE((SELECT value::text::int FROM platform_settings WHERE key='cancel_fee_before_dispatch_cents'), 100);
  v_fee_accept int := COALESCE((SELECT value::text::int FROM platform_settings WHERE key='cancel_fee_after_accept_cents'), 250);
  v_pickup_ratio numeric := COALESCE((SELECT value::text::numeric FROM platform_settings WHERE key='cancel_fee_after_pickup_ratio'), 1.00);
  v_total_cents int;
  v_fee_cents   int;
  v_refund_cents int;
  v_stage TEXT;
  v_in_grace boolean;
BEGIN
  IF v_user IS NULL THEN RAISE EXCEPTION 'unauthorized' USING ERRCODE='42501'; END IF;
  IF p_reason IS NULL OR length(trim(p_reason)) < 3 THEN RAISE EXCEPTION 'reason_required'; END IF;

  SELECT id, user_id, status, assigned_driver_id, restaurant_id, created_at,
         COALESCE(customer_total, total, 0) AS amount, payment_method
    INTO v_order FROM public.orders WHERE id = p_order_id;
  IF v_order.id IS NULL THEN RAISE EXCEPTION 'order_not_found'; END IF;

  -- papel (igual à versão actual)
  IF v_order.user_id = v_user THEN v_role := 'client';
  ELSIF v_order.assigned_driver_id::text = v_user::text THEN v_role := 'driver';
  ELSIF EXISTS (SELECT 1 FROM public.restaurants r WHERE r.id = v_order.restaurant_id AND r.user_ = v_user)
    THEN v_role := 'partner';
  ELSE RAISE EXCEPTION 'not_authorized_for_order' USING ERRCODE='42501';
  END IF;

  IF v_order.status IN ('delivered','rejected','cancelled') THEN
    RAISE EXCEPTION 'order_terminal: %', v_order.status USING ERRCODE='23514';
  END IF;

  v_total_cents := round(v_order.amount * 100)::int;
  v_in_grace := (EXTRACT(EPOCH FROM (now() - v_order.created_at)) <= v_grace_s);

  -- Disputa OU cancelamento por parceiro/estafeta → mantém fluxo manual (admin).
  IF p_dispute OR v_role <> 'client' THEN
    INSERT INTO public.cancellation_requests (order_id, requester_role, requester_id, reason, status, auto_resolved)
    VALUES (p_order_id, v_role, v_user, trim(p_reason), 'pending', false)
    RETURNING * INTO v_req;
    RETURN v_req;
  END IF;

  -- Determina estágio + taxa
  IF v_in_grace THEN
    v_stage := 'grace';        v_fee_cents := 0;
  ELSIF v_order.status IN ('created','preparing') THEN
    v_stage := 'before_dispatch'; v_fee_cents := v_fee_before;
  ELSIF v_order.status IN ('callingDriver','driverAccepted') THEN
    v_stage := 'after_accept';    v_fee_cents := v_fee_accept;
  ELSE -- pickedUp / onTheWay
    v_stage := 'after_pickup';    v_fee_cents := round(v_total_cents * v_pickup_ratio)::int;
  END IF;

  v_refund_cents := GREATEST(v_total_cents - v_fee_cents, 0);

  -- Cancela o pedido (estado terminal).
  UPDATE public.orders SET status='cancelled' WHERE id = p_order_id;

  -- Reembolso só para pagamentos eletrónicos (cash não cobrou antecipadamente).
  IF v_refund_cents > 0 AND v_order.payment_method IN ('card','mbway') THEN
    PERFORM public.wallet_credit_refund_split(
      p_order_id, v_user, v_refund_cents,
      'cancel_' || v_stage
    );
  END IF;

  INSERT INTO public.cancellation_requests
    (order_id, requester_role, requester_id, reason, status, auto_resolved, cancel_stage, fee_cents, refund_cents)
  VALUES
    (p_order_id, v_role, v_user, trim(p_reason), 'auto_approved', true, v_stage, v_fee_cents, v_refund_cents)
  RETURNING * INTO v_req;
  RETURN v_req;

EXCEPTION WHEN unique_violation THEN
  RAISE EXCEPTION 'cancellation_already_pending: %', p_order_id USING ERRCODE='23505';
END;
$function$;

-- ROLLBACK (se preciso): repor a versão manual a partir do git e
--   DELETE FROM platform_settings WHERE key='cancel_grace_seconds';
-- As colunas aditivas podem ficar (nullable, inertes).

-- ════════════════════════════════════════════════════════════════════
-- 7-FIX session 2026-05-07
-- BUG-7E-B-004: driver_cancel_order permitia cancelar pickedUp
-- Decisão Danilo (2026-05-07): bloquear pickedUp + redirect "contactar suporte"
-- ════════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.driver_cancel_order(p_order_id text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_driver_id TEXT;
  v_order RECORD;
BEGIN
  SELECT id::text INTO v_driver_id
  FROM drivers WHERE user_id = auth.uid();

  IF v_driver_id IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'Driver not found');
  END IF;

  -- ★ FIX BUG-7E-B-004: pickedUp NÃO permitido (era 'driverAccepted', 'pickedUp')
  -- §7.7 (decisão Danilo 2026-05-07): após pickup, contactar suporte.
  SELECT * INTO v_order FROM orders
  WHERE id = p_order_id
    AND assigned_driver_id = v_driver_id
    AND status = 'driverAccepted';

  IF NOT FOUND THEN
    -- Distinguir entre 2 razões para a UI dar mensagem certa
    IF EXISTS (
      SELECT 1 FROM orders
      WHERE id = p_order_id
        AND assigned_driver_id = v_driver_id
        AND status IN ('pickedUp', 'onTheWay')
    ) THEN
      RETURN jsonb_build_object(
        'ok', false,
        'error', 'cancel_blocked_after_pickup',
        'message', 'Após recolher o pedido, contacte o suporte para cancelar.',
        'support_required', true
      );
    END IF;

    RETURN jsonb_build_object(
      'ok', false,
      'error', 'Order not found or not assigned to this driver'
    );
  END IF;

  UPDATE orders SET
    status = 'callingDriver',
    assigned_driver_id = NULL,
    current_driver_offer_id = NULL,
    driver_offer_expires_at = NULL,
    tried_driver_ids = array_append(COALESCE(tried_driver_ids, '{}'::text[]), v_driver_id)
  WHERE id = p_order_id;

  PERFORM net.http_post(
    url := 'https://ojykpzwqrtusfeakzrna.supabase.co/functions/v1/dispatch-engine',
    headers := '{"Content-Type":"application/json"}'::jsonb,
    body := jsonb_build_object('orderId', p_order_id)
  );

  RETURN jsonb_build_object('ok', true);
END;
$function$;

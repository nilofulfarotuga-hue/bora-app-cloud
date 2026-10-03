-- Parceiro edita pedido — aviso ao ESTAFETA corrigido (achado da prova real, 22/09/2026)
-- A prova real mostrou duas falhas no aviso ao estafeta:
--   1. notify-driver-assigned no ar só aceita order_reassigned / order_preassigned /
--      order_unassigned / driver_offline — 'order_updated' dava 400 e a app do
--      estafeta também não conhece esse tipo. Passa a 'order_reassigned' (o pedido
--      é mesmo dele, a Edge confirma; a app mostra o título e o texto enviados).
--   2. O aviso dentro da app ia para orders.assigned_driver_id, que é drivers.id e
--      não o user_id — o aviso perdia-se. Resolve-se o user_id em drivers
--      (regra fixa: user_id manda em tudo o que a app vê).
CREATE OR REPLACE FUNCTION public._order_edit_avisa(p_order_id text, p_cliente_titulo text, p_cliente_texto text, p_estafeta boolean)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $$
DECLARE
  o public.orders%ROWTYPE;
  v_driver_uid uuid;
  v_txt text;
BEGIN
  SELECT * INTO o FROM public.orders WHERE id = p_order_id;
  IF p_cliente_titulo IS NOT NULL AND o.user_id IS NOT NULL THEN
    PERFORM public._push_in_app_notification(o.user_id, 'order_edit', p_cliente_titulo, p_cliente_texto, p_order_id);
    PERFORM public._order_edit_http('notify-client', jsonb_build_object(
      'clientId', o.user_id::text, 'orderId', p_order_id,
      'title', p_cliente_titulo, 'body', p_cliente_texto));
  END IF;
  IF p_estafeta AND NULLIF(o.assigned_driver_id, '') IS NOT NULL THEN
    SELECT d.user_id INTO v_driver_uid FROM public.drivers d
     WHERE d.id::text = o.assigned_driver_id OR d.user_id::text = o.assigned_driver_id
     LIMIT 1;
    v_txt := 'A lista do pedido mudou.' || CASE WHEN o.payment_method = 'cash'
      THEN ' Cobra ' || to_char(COALESCE(o.final_total, o.price), 'FM999990.00') || ' € na entrega.' ELSE '' END;
    IF v_driver_uid IS NOT NULL THEN
      PERFORM public._push_in_app_notification(v_driver_uid, 'order_edit', 'Pedido alterado pela loja', v_txt, p_order_id);
    END IF;
    PERFORM public._order_edit_http('notify-driver-assigned', jsonb_build_object(
      'driverId', COALESCE(v_driver_uid::text, o.assigned_driver_id), 'orderId', p_order_id,
      'type', 'order_reassigned', 'title', 'Pedido alterado pela loja', 'body', v_txt));
  END IF;
END $$;
REVOKE ALL ON FUNCTION public._order_edit_avisa(text, text, text, boolean) FROM PUBLIC, anon, authenticated;

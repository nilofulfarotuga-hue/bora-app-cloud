-- Aplicada em produção pela Claude.ai (MCP apply_migration) a 2026-09-16 16:49:51 UTC,
-- versão 20260916164951. Trazida para o repo pela missão estafeta-web-2026-09-16 (bloco 7.1),
-- SQL literal lido de supabase_migrations.schema_migrations. NÃO reaplicar.
-- (A migração 20260916224051 desta missão substitui esta função por uma versão com pré-atribuição.)

-- 2026-09-16: o aviso ao estafeta na reatribuição pelo painel NUNCA saía.
-- (1) mandava driver_id/order_id e a Edge notify-driver exige driverId/orderId (resposta 400 "driverId and orderId are required");
-- (2) lia app.settings.service_role_key, que não existe (Authorization ia nulo).
-- Lógica da reatribuição inalterada; só o bloco do push mudou.
CREATE OR REPLACE FUNCTION public.admin_reassign_order(p_order_id text, p_new_driver text, p_motivo text DEFAULT ''::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_o record;
  v_d record;
  v_new text;
BEGIN
  PERFORM public._admin_op_guard();

  SELECT id, status, assigned_driver_id INTO v_o FROM orders WHERE id = p_order_id FOR UPDATE;
  IF v_o.id IS NULL THEN RETURN jsonb_build_object('ok', false, 'error', 'pedido_nao_encontrado'); END IF;
  IF v_o.status IN ('delivered','cancelled','rejected') THEN
    RETURN jsonb_build_object('ok', false, 'error', 'pedido_ja_terminal', 'status', v_o.status);
  END IF;

  SELECT d.id, d.user_id, d.name, d.approval_status INTO v_d
  FROM drivers d
  WHERE d.id::text = p_new_driver OR d.user_id::text = p_new_driver
  LIMIT 1;
  IF v_d.id IS NULL THEN RETURN jsonb_build_object('ok', false, 'error', 'estafeta_nao_encontrado'); END IF;
  IF v_d.approval_status <> 'approved' THEN
    RETURN jsonb_build_object('ok', false, 'error', 'estafeta_nao_aprovado');
  END IF;

  v_new := COALESCE(v_d.user_id, v_d.id)::text;

  UPDATE orders
  SET assigned_driver_id = v_new,
      driver_id = COALESCE(v_d.user_id, v_d.id),
      current_driver_offer_id = NULL,
      status = CASE WHEN status IN ('callingDriver') THEN 'driverAccepted' ELSE status END
  WHERE id = p_order_id;

  PERFORM public.log_admin_action('order_reassigned', 'order', p_order_id,
    jsonb_build_object('de', v_o.assigned_driver_id, 'para', v_new,
                       'estafeta', v_d.name, 'motivo', NULLIF(p_motivo,'')));

  -- Avisa o estafeta que ficou com o pedido. Best-effort — a reatribuição
  -- em si NÃO depende do push (falha vira WARNING, nunca silêncio).
  BEGIN
    PERFORM net.http_post(
      url := 'https://ojykpzwqrtusfeakzrna.supabase.co/functions/v1/notify-driver',
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'Authorization', 'Bearer ' || COALESCE(
          NULLIF(current_setting('app.settings.service_role_key', true), ''),
          (SELECT s.decrypted_secret FROM vault.decrypted_secrets s WHERE s.name = 'service_role_key' LIMIT 1))),
      body := jsonb_build_object(
        'driverId', v_new,
        'orderId', p_order_id,
        'driver_id', v_new,
        'order_id', p_order_id,
        'type', 'order_reassigned',
        'title', '📦 Pedido reatribuído a ti',
        'body', 'O suporte atribuiu-te o pedido ' ||
                upper(substr(replace(p_order_id,'-',''),1,6)) || '. Abre para ver os detalhes.'));
  EXCEPTION WHEN OTHERS THEN
    RAISE WARNING 'admin_reassign_order: notify-driver falhou: %', SQLERRM;
  END;

  RETURN jsonb_build_object('ok', true, 'estafeta', v_d.name, 'novo_driver', v_new);
END $function$;

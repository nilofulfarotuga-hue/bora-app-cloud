-- 31/10/2026 (Claude.ai via MCP, autorizado pelo Danilo 12:19) — AVISO AO CLIENTE NAS FASES DO PEDIDO.
-- Só a app do estafeta chamava notify-client, e desde 16/10 chama com a chave PÚBLICA (recusada, 401,
-- provado 31/10 12:01:51 no pedido 48669acf). O servidor passa a avisar o cliente sozinho, pelo mesmo
-- caminho das reservas (_reservas_pro_notify_client_push). A chamada da app sai pelo Claude Code.
CREATE OR REPLACE FUNCTION public.fn_push_cliente_fase_pedido()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_key text; v_url text; v_driver text;
BEGIN
  IF NEW.status IS NOT DISTINCT FROM OLD.status THEN RETURN NEW; END IF;
  IF NEW.status NOT IN ('preparing','readyForPickup','driverAccepted','pickedUp','onTheWay','delivered') THEN RETURN NEW; END IF;
  IF NEW.user_id IS NULL THEN RETURN NEW; END IF;
  BEGIN
    IF public.is_demo_user(NEW.user_id) THEN RETURN NEW; END IF;
  EXCEPTION WHEN OTHERS THEN NULL; END;

  BEGIN
    v_key := nullif(public._service_role_key(), '');
    v_url := (SELECT decrypted_secret FROM vault.decrypted_secrets WHERE name = 'project_url' LIMIT 1);
    IF v_key IS NULL OR v_url IS NULL THEN
      RAISE NOTICE 'fn_push_cliente_fase_pedido: sem chave/url';
      RETURN NEW;
    END IF;
    SELECT d.name INTO v_driver FROM public.drivers d
     WHERE d.id = coalesce(NEW.assigned_driver_id, NEW.driver_id) LIMIT 1;
    PERFORM net.http_post(
      url     := v_url || '/functions/v1/notify-client',
      headers := jsonb_build_object('Content-Type','application/json','Authorization','Bearer ' || v_key),
      body    := jsonb_build_object(
        'clientId',   NEW.user_id::text,
        'orderId',    NEW.id::text,
        'status',     NEW.status,
        'type',       'order_status',
        'vendorName', coalesce(NEW.vendor_name, ''),
        'driverName', coalesce(v_driver, '')
      )
    );
  EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'fn_push_cliente_fase_pedido erro: %', sqlerrm;
  END;
  RETURN NEW;
END
$function$;

CREATE TRIGGER trg_push_cliente_fase_pedido
AFTER UPDATE OF status ON public.orders
FOR EACH ROW EXECUTE FUNCTION public.fn_push_cliente_fase_pedido();;

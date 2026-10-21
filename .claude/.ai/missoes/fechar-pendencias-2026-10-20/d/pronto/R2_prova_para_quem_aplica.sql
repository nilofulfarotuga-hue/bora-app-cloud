-- Prova do R2 de ponta a ponta para quem aplica (transação revertida pelo RAISE do fim).
-- Faz escritas DIRETAS em orders como a app faz (SET LOCAL ROLE authenticated + sessão simulada), coisa que
-- a bora-tranca não deixa um agente deste PC escrever: por isso a minha prova (21/10, R2-LEIA.md) testou a
-- decisão do gatilho com linhas em memória, e esta fica para o revisor/quem aplica.
-- Esperado:
--   estafeta_pickedUp            -> 1 linha (o estafeta continua a avançar)
--   cliente_rejected / delivered -> 42501 pedido_estado_so_pela_loja_estafeta_ou_servidor
--   cliente_muda_notas           -> 1 linha (o gatilho só olha para o estado)
--   admin_cancela                -> estado cancelled (as funções do servidor não são travadas)
--   pedido_normal_do_cliente     -> created/preparing/callingDriver continuam (decisão: ver 01..04 da minha prova)
DO $prova$
DECLARE
  v_a     uuid := 'd5b0c0a1-f49e-4593-a919-147edfc069c2';
  v_drv   uuid := 'dede0000-0000-4000-8000-000000000001';
  v_admin uuid := 'c9fccf85-03ee-4efc-83bf-613f211a78ff';
  v_aberto jsonb := jsonb_build_object('open','00:00','close','23:59','closed',false);
  v_o jsonb; v_ped text; v_n bigint; v_out jsonb := '{}'::jsonb;
BEGIN
  EXECUTE $r2$
-- R2 · o cliente so muda o estado do seu pedido como a app faz (21/10/2026, "Vai" do Danilo).
-- A app do cliente so faz 2 mudancas de estado, e nunca num pedido de restaurante parceiro
-- (order_store.dart, _simulateRestaurantFlow): created -> preparing e preparing -> callingDriver.
-- Medido a 21/10 em order_status_events: as unicas mudancas feitas pelo proprio cliente foram estas 2
-- (restaurante nao-parceiro, compras, favores). Cancelar vai pela Edge client-cancel-order (servidor);
-- aceitar, recolher e entregar sao da loja e do estafeta.
-- Nao mexe em politicas nem em colunas: e um gatilho BEFORE UPDATE OF status que so olha para escritas
-- diretas pela API (current_user authenticated/anon) feitas pelo dono do pedido. As funcoes e as Edge
-- do servidor (correm como o dono delas ou como service_role), o admin, a loja e o estafeta do pedido
-- ficam como estao.

-- As 2 mudancas que a app do cliente faz.
CREATE OR REPLACE FUNCTION public._pedido_transicao_do_cliente(p_tipo text, p_parceiro boolean, p_antes text, p_depois text)
RETURNS boolean
LANGUAGE sql
IMMUTABLE
SET search_path TO 'public'
AS $function$
  SELECT NOT (COALESCE(p_tipo, '') = 'restaurant' AND COALESCE(p_parceiro, false))
     AND ((p_antes = 'created' AND p_depois = 'preparing')
       OR (p_antes = 'preparing' AND p_depois = 'callingDriver'))
$function$;

-- true = recusar: quem escreve e o cliente do pedido (sem ser admin, estafeta ou loja deste pedido)
-- e a mudanca nao e uma das 2 da app.
CREATE OR REPLACE FUNCTION public._pedido_estado_cliente_recusa(o public.orders, p_depois text)
RETURNS boolean
LANGUAGE plpgsql
STABLE
SET search_path TO 'public'
AS $function$
DECLARE
  v_uid uuid := auth.uid();
BEGIN
  IF v_uid IS NULL OR p_depois IS NOT DISTINCT FROM o.status THEN RETURN false; END IF;
  IF o.user_id IS DISTINCT FROM v_uid THEN RETURN false; END IF;
  IF public.is_admin() THEN RETURN false; END IF;
  IF o.driver_id = v_uid OR EXISTS (
       SELECT 1 FROM public.drivers d
        WHERE d.user_id = v_uid
          AND (d.id::text IN (o.assigned_driver_id, o.current_driver_offer_id)
            OR d.user_id::text IN (o.assigned_driver_id, o.current_driver_offer_id))) THEN
    RETURN false;
  END IF;
  IF o.restaurant_id IN (SELECT public.parceiro_minhas_lojas()) THEN RETURN false; END IF;
  RETURN NOT public._pedido_transicao_do_cliente(o.service_type, o.is_partner_store, o.status, p_depois);
END;
$function$;

-- SECURITY INVOKER de proposito: current_user diz se a escrita veio direta da API.
CREATE OR REPLACE FUNCTION public._pedido_estado_cliente_guarda()
RETURNS trigger
LANGUAGE plpgsql
SET search_path TO 'public'
AS $function$
BEGIN
  IF current_user IN ('authenticated', 'anon') AND public._pedido_estado_cliente_recusa(OLD, NEW.status) THEN
    RAISE EXCEPTION 'pedido_estado_so_pela_loja_estafeta_ou_servidor (% -> %)', OLD.status, NEW.status
      USING ERRCODE = '42501';
  END IF;
  RETURN NEW;
END;
$function$;

REVOKE ALL ON FUNCTION public._pedido_transicao_do_cliente(text, boolean, text, text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public._pedido_estado_cliente_recusa(public.orders, text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public._pedido_estado_cliente_guarda() FROM PUBLIC, anon, authenticated;
-- o gatilho corre como quem escreve: o cliente com sessao tem de poder chamar as 2 funcoes de decisao
GRANT EXECUTE ON FUNCTION public._pedido_transicao_do_cliente(text, boolean, text, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public._pedido_estado_cliente_recusa(public.orders, text) TO authenticated;

CREATE OR REPLACE TRIGGER trg_pedido_estado_cliente_guarda
  BEFORE UPDATE OF status ON public.orders
  FOR EACH ROW
  WHEN (NEW.status IS DISTINCT FROM OLD.status)
  EXECUTE FUNCTION public._pedido_estado_cliente_guarda();
$r2$;
  UPDATE public.restaurants
     SET business_hours = jsonb_build_object('mon',v_aberto,'tue',v_aberto,'wed',v_aberto,'thu',v_aberto,'fri',v_aberto,'sat',v_aberto,'sun',v_aberto)
   WHERE id = 'sabores-brasil-guarda';
  PERFORM set_config('request.jwt.claim.sub', v_a::text, true);
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_a, 'role', 'authenticated')::text, true);
  v_o := public.create_order(jsonb_build_object('service_type','restaurant','vendor_name','Sabores do Brasil - Keli Barbosa','is_partner_store',true,
    'payment_method','cash','distance_km',1.0,
    'pickup_lat',40.5323845,'pickup_lng',-7.2656677,'dropoff_lat',40.5373,'dropoff_lng',-7.2676,
    'pickup_address','R. Dom Manuel Vieira de Matos 25, Guarda','dropoff_address','Rua de prova, Guarda',
    'customer_name','Demo Bora','client_phone','920000000','customer_notes','Prova R2 (revertida)',
    'items', jsonb_build_array(jsonb_build_object('productId','09a9503f-1ef2-4a92-9486-e53848dc853c','name','Salgados Grandes','price',3.15,'basePrice',3.15,'quantity',2)),
    'product_lines', jsonb_build_array(jsonb_build_object('product_id','09a9503f-1ef2-4a92-9486-e53848dc853c','quantity',2,'unit_price',3.15))));
  v_ped := v_o ->> 'order_id';
  v_out := v_out || jsonb_build_object('estado_inicial', (SELECT status FROM public.orders WHERE id = v_ped));

  -- estafeta demo (dono da oferta) recolhe, como a app dele faz (escrita direta)
  PERFORM set_config('request.jwt.claim.sub', v_drv::text, true);
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_drv, 'role', 'authenticated')::text, true);
  BEGIN
    SET LOCAL ROLE authenticated;
    UPDATE public.orders SET status = 'pickedUp' WHERE id = v_ped;
    GET DIAGNOSTICS v_n = ROW_COUNT;
    RESET ROLE;
    v_out := v_out || jsonb_build_object('estafeta_pickedUp', v_n || ' linha');
  EXCEPTION WHEN OTHERS THEN
    RESET ROLE;
    v_out := v_out || jsonb_build_object('estafeta_pickedUp', SQLSTATE || ' ' || left(SQLERRM, 90));
  END;

  -- o cliente tenta mudar o estado do seu pedido
  PERFORM set_config('request.jwt.claim.sub', v_a::text, true);
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_a, 'role', 'authenticated')::text, true);
  BEGIN
    SET LOCAL ROLE authenticated;
    UPDATE public.orders SET status = 'rejected' WHERE id = v_ped;
    GET DIAGNOSTICS v_n = ROW_COUNT;
    RESET ROLE;
    v_out := v_out || jsonb_build_object('cliente_rejected', 'NAO RECUSOU (' || v_n || ' linha)');
  EXCEPTION WHEN OTHERS THEN
    RESET ROLE;
    v_out := v_out || jsonb_build_object('cliente_rejected', SQLSTATE || ' ' || left(SQLERRM, 90));
  END;
  BEGIN
    SET LOCAL ROLE authenticated;
    UPDATE public.orders SET status = 'delivered' WHERE id = v_ped;
    GET DIAGNOSTICS v_n = ROW_COUNT;
    RESET ROLE;
    v_out := v_out || jsonb_build_object('cliente_delivered', 'NAO RECUSOU (' || v_n || ' linha)');
  EXCEPTION WHEN OTHERS THEN
    RESET ROLE;
    v_out := v_out || jsonb_build_object('cliente_delivered', SQLSTATE || ' ' || left(SQLERRM, 90));
  END;
  BEGIN
    SET LOCAL ROLE authenticated;
    UPDATE public.orders SET customer_notes = 'tocar a campainha' WHERE id = v_ped;
    GET DIAGNOSTICS v_n = ROW_COUNT;
    RESET ROLE;
    v_out := v_out || jsonb_build_object('cliente_muda_notas', v_n || ' linha');
  EXCEPTION WHEN OTHERS THEN
    RESET ROLE;
    v_out := v_out || jsonb_build_object('cliente_muda_notas', SQLSTATE || ' ' || left(SQLERRM, 90));
  END;

  -- o admin cancela pelo caminho do servidor
  PERFORM set_config('request.jwt.claim.sub', v_admin::text, true);
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_admin, 'role', 'authenticated', 'email', 'nilofulfarotuga@gmail.com',
                                                             'app_metadata', json_build_object('role', 'admin'))::text, true);
  PERFORM public.admin_cancel_order(v_ped::uuid, 'client_request', 'prova R2 (revertida)');
  v_out := v_out || jsonb_build_object('admin_cancela', (SELECT status FROM public.orders WHERE id = v_ped));
  RAISE EXCEPTION 'RESULT %', v_out::text;
END $prova$;

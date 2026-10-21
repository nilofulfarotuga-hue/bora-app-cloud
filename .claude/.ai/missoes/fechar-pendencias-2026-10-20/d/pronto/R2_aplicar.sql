-- R2 · ⚠️ zona protegida (quem pode mudar o estado de um pedido). "Vai" do Danilo a 21/10/2026 06:15Z
-- (MISSAO.md, secção '"VAI" DO DANILO'; e2e_log 4087). Pronto a aplicar; o revisor vê primeiro.
-- ANTES (21/10/2026): nao existe trg_pedido_estado_cliente_guarda nem as 3 funcoes _pedido_estado_* /
-- _pedido_transicao_do_cliente (confirmado em pg_trigger/pg_proc). Nao muda politicas, colunas nem dados.
-- Copiar para supabase/migrations/ com o timestamp que o apply_migration der e confirmar o md5.
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

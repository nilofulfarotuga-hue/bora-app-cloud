-- R2 (estendido) · o cliente so muda no seu pedido o que a app dele muda (21/10/2026).
-- "Vai" do Danilo (e2e_log 4087) + SIM do revisor (e2e_log 4100), incluindo payment_status e cash_total_due.
--
-- O que a app do cliente escreve em orders, lido no codigo e medido na base:
--   * estado: so created -> preparing e preparing -> callingDriver, e nunca num pedido de restaurante
--     parceiro (order_store.dart, _simulateRestaurantFlow); em order_status_events as unicas mudancas feitas
--     pelo proprio cliente foram exatamente estas 2. Cancelar vai pela Edge client-cancel-order (servidor).
--   * payment_status: nunca (as 2 escritas da app, order_store.dart:1995/2019, sao do estafeta ao fechar a
--     compra); cash_total_due: nunca.
-- O gatilho so olha para escritas diretas pela API (current_user authenticated/anon) feitas pelo DONO do
-- pedido. Quem nao e o dono (estafeta, loja) ja esta limitado pelas regras de acesso de orders e nao muda nada.
-- O dono que e admin, ou que e o estafeta que aceitou este pedido (historico order_status_events, que o
-- cliente nao escreve), tambem nao muda nada. As funcoes e as Edge do servidor correm como o dono delas ou
-- como service_role: nao passam por aqui. Nao mexe em politicas, colunas nem dados.
-- O nome comeca por a00_ para correr antes dos outros gatilhos BEFORE de orders e ver o que o cliente
-- mandou, e nao o que outro gatilho acrescentou.

-- As 2 mudancas de estado que a app do cliente faz.
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

-- NULL = deixa; senao, o que se recusa.
CREATE OR REPLACE FUNCTION public._pedido_cliente_recusa(o public.orders, n public.orders)
RETURNS text
LANGUAGE plpgsql
STABLE
SET search_path TO 'public'
AS $function$
DECLARE
  v_uid uuid := auth.uid();
BEGIN
  IF v_uid IS NULL OR o.user_id IS DISTINCT FROM v_uid THEN RETURN NULL; END IF;
  IF public.is_admin() THEN RETURN NULL; END IF;
  IF EXISTS (SELECT 1 FROM public.order_status_events e
              WHERE e.order_id = o.id AND e.to_status = 'driverAccepted' AND e.actor_uid = v_uid) THEN
    RETURN NULL;
  END IF;
  IF n.payment_status IS DISTINCT FROM o.payment_status THEN RETURN 'payment_status'; END IF;
  IF n.cash_total_due IS DISTINCT FROM o.cash_total_due THEN RETURN 'cash_total_due'; END IF;
  IF n.status IS DISTINCT FROM o.status
     AND NOT public._pedido_transicao_do_cliente(o.service_type, o.is_partner_store, o.status, n.status) THEN
    RETURN 'status ' || COALESCE(o.status, '-') || ' -> ' || COALESCE(n.status, '-');
  END IF;
  RETURN NULL;
END;
$function$;

-- SECURITY INVOKER de proposito: current_user diz se a escrita veio direta da API.
CREATE OR REPLACE FUNCTION public._pedido_cliente_guarda()
RETURNS trigger
LANGUAGE plpgsql
SET search_path TO 'public'
AS $function$
DECLARE
  v_motivo text;
BEGIN
  IF current_user IN ('authenticated', 'anon') THEN
    v_motivo := public._pedido_cliente_recusa(OLD, NEW);
    IF v_motivo IS NOT NULL THEN
      RAISE EXCEPTION 'pedido_so_pela_loja_estafeta_ou_servidor (%)', v_motivo USING ERRCODE = '42501';
    END IF;
  END IF;
  RETURN NEW;
END;
$function$;

REVOKE ALL ON FUNCTION public._pedido_transicao_do_cliente(text, boolean, text, text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public._pedido_cliente_recusa(public.orders, public.orders) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public._pedido_cliente_guarda() FROM PUBLIC, anon, authenticated;
-- o gatilho corre como quem escreve: o cliente com sessao tem de poder chamar as 2 funcoes de decisao
GRANT EXECUTE ON FUNCTION public._pedido_transicao_do_cliente(text, boolean, text, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public._pedido_cliente_recusa(public.orders, public.orders) TO authenticated;

CREATE OR REPLACE TRIGGER a00_pedido_cliente_guarda
  BEFORE UPDATE OF status, payment_status, cash_total_due ON public.orders
  FOR EACH ROW
  WHEN (NEW.status IS DISTINCT FROM OLD.status
        OR NEW.payment_status IS DISTINCT FROM OLD.payment_status
        OR NEW.cash_total_due IS DISTINCT FROM OLD.cash_total_due)
  EXECUTE FUNCTION public._pedido_cliente_guarda();

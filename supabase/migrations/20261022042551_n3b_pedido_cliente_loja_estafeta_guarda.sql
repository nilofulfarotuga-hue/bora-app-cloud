-- N3b · o cliente não escreve a loja nem o estafeta do seu próprio pedido (22/10/2026).
-- Ordem do Danilo (prompt de 22/10 04:33, passo 3b): "impedir que o cliente escreva a loja ou o
-- estafeta no próprio pedido" — segurança, não mexe em preços nem em valores.
--
-- O buraco (RELATORIO-D.md, ronda 2, ponto 17): a política orders_update_client deixa o dono do
-- pedido mudar QUALQUER coluna pela API. O R2 (a00_pedido_cliente_guarda) já fechou estado,
-- pagamento e valor a cobrar; ficaram abertas as colunas que dizem de que loja é o pedido e que
-- estafeta o leva. Com elas, um cliente pode pôr no seu pedido um estafeta à escolha (ou uma
-- oferta para ele), tirar o pedido a uma loja, ou marcar um restaurante parceiro como não parceiro.
--
-- O que a app do cliente escreve em orders (lido no código a 22/10): nenhuma destas colunas.
--   * criar o pedido vai pela função create_order (corre como o dono dela, não passa aqui);
--   * as escritas diretas do cliente são fotos/recolha à porta (order_store.dart:1071), itens e
--     sacos (2961), estado (2995, já guardado pelo R2) e substituições (1967);
--   * assigned_driver_id/current_driver_offer_id/tried_driver_ids só os escreve o ESTAFETA ao
--     desistir (order_store.dart:1510) — não é o dono; se for o dono e o estafeta que aceitou
--     (histórico order_status_events, que o cliente não escreve), passa como no R2;
--   * a localização do estafeta (driver_lat/lng) é o estafeta (driver_store.dart:638): fica de fora.
-- Funções e Edges do servidor correm como o dono delas ou como service_role: não passam aqui.
-- Admin: passa. Não muda políticas, colunas nem dados.
--
-- No INSERT direto pela API (política orders_insert_client, que nenhuma app usa), o cliente também
-- não pode nascer o pedido já com estafeta, oferta, estafetas excluídos (tried_driver_ids) ou
-- histórico de ofertas (revisor N3b, achado 1: driver_offer_history nasce '[]' por defeito).
-- O nome a00_ corre antes de a_trg_pedido_demo_caixa_fechada, que põe o estafeta demo nos pedidos
-- das contas demo — esse continua a funcionar.

-- NULL = deixa; senão, a coluna que se recusa.
CREATE OR REPLACE FUNCTION public._pedido_cliente_loja_estafeta_recusa(o public.orders, n public.orders)
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
  -- a loja
  IF n.restaurant_id      IS DISTINCT FROM o.restaurant_id      THEN RETURN 'restaurant_id'; END IF;
  IF n.is_partner_store   IS DISTINCT FROM o.is_partner_store   THEN RETURN 'is_partner_store'; END IF;
  IF n.vendor_name        IS DISTINCT FROM o.vendor_name        THEN RETURN 'vendor_name'; END IF;
  -- o estafeta e a escolha do estafeta
  IF n.assigned_driver_id      IS DISTINCT FROM o.assigned_driver_id      THEN RETURN 'assigned_driver_id'; END IF;
  IF n.driver_id               IS DISTINCT FROM o.driver_id               THEN RETURN 'driver_id'; END IF;
  IF n.current_driver_offer_id IS DISTINCT FROM o.current_driver_offer_id THEN RETURN 'current_driver_offer_id'; END IF;
  IF n.preassigned_driver_id   IS DISTINCT FROM o.preassigned_driver_id   THEN RETURN 'preassigned_driver_id'; END IF;
  IF n.helper_driver_id        IS DISTINCT FROM o.helper_driver_id        THEN RETURN 'helper_driver_id'; END IF;
  IF n.tried_driver_ids        IS DISTINCT FROM o.tried_driver_ids        THEN RETURN 'tried_driver_ids'; END IF;
  IF n.driver_offer_expires_at IS DISTINCT FROM o.driver_offer_expires_at THEN RETURN 'driver_offer_expires_at'; END IF;
  IF n.driver_offer_history    IS DISTINCT FROM o.driver_offer_history    THEN RETURN 'driver_offer_history'; END IF;
  RETURN NULL;
END;
$function$;

-- SECURITY INVOKER de propósito: current_user diz se a escrita veio direta da API.
CREATE OR REPLACE FUNCTION public._pedido_cliente_loja_estafeta_guarda()
RETURNS trigger
LANGUAGE plpgsql
SET search_path TO 'public'
AS $function$
DECLARE
  v_motivo text;
BEGIN
  IF current_user NOT IN ('authenticated', 'anon') THEN
    RETURN NEW;
  END IF;
  IF TG_OP = 'INSERT' THEN
    IF public.is_admin() THEN RETURN NEW; END IF;
    v_motivo := CASE
      WHEN NEW.assigned_driver_id      IS NOT NULL THEN 'assigned_driver_id'
      WHEN NEW.driver_id               IS NOT NULL THEN 'driver_id'
      WHEN NEW.current_driver_offer_id IS NOT NULL THEN 'current_driver_offer_id'
      WHEN NEW.preassigned_driver_id   IS NOT NULL THEN 'preassigned_driver_id'
      WHEN NEW.helper_driver_id        IS NOT NULL THEN 'helper_driver_id'
      WHEN COALESCE(cardinality(NEW.tried_driver_ids), 0) > 0 THEN 'tried_driver_ids'
      WHEN NEW.driver_offer_expires_at IS NOT NULL THEN 'driver_offer_expires_at'
      WHEN COALESCE(NEW.driver_offer_history, '[]'::jsonb) <> '[]'::jsonb THEN 'driver_offer_history'
    END;
  ELSE
    v_motivo := public._pedido_cliente_loja_estafeta_recusa(OLD, NEW);
  END IF;
  IF v_motivo IS NOT NULL THEN
    RAISE EXCEPTION 'pedido_loja_estafeta_so_pelo_servidor (%)', v_motivo USING ERRCODE = '42501';
  END IF;
  RETURN NEW;
END;
$function$;

REVOKE ALL ON FUNCTION public._pedido_cliente_loja_estafeta_recusa(public.orders, public.orders) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public._pedido_cliente_loja_estafeta_guarda() FROM PUBLIC, anon, authenticated;
-- o gatilho corre como quem escreve: o cliente com sessão tem de poder chamar a função de decisão
GRANT EXECUTE ON FUNCTION public._pedido_cliente_loja_estafeta_recusa(public.orders, public.orders) TO authenticated;

CREATE OR REPLACE TRIGGER a00_pedido_loja_estafeta_guarda_upd
  BEFORE UPDATE OF restaurant_id, is_partner_store, vendor_name,
                   assigned_driver_id, driver_id, current_driver_offer_id, preassigned_driver_id,
                   helper_driver_id, tried_driver_ids, driver_offer_expires_at, driver_offer_history
  ON public.orders
  FOR EACH ROW
  WHEN (NEW.restaurant_id IS DISTINCT FROM OLD.restaurant_id
        OR NEW.is_partner_store IS DISTINCT FROM OLD.is_partner_store
        OR NEW.vendor_name IS DISTINCT FROM OLD.vendor_name
        OR NEW.assigned_driver_id IS DISTINCT FROM OLD.assigned_driver_id
        OR NEW.driver_id IS DISTINCT FROM OLD.driver_id
        OR NEW.current_driver_offer_id IS DISTINCT FROM OLD.current_driver_offer_id
        OR NEW.preassigned_driver_id IS DISTINCT FROM OLD.preassigned_driver_id
        OR NEW.helper_driver_id IS DISTINCT FROM OLD.helper_driver_id
        OR NEW.tried_driver_ids IS DISTINCT FROM OLD.tried_driver_ids
        OR NEW.driver_offer_expires_at IS DISTINCT FROM OLD.driver_offer_expires_at
        OR NEW.driver_offer_history IS DISTINCT FROM OLD.driver_offer_history)
  EXECUTE FUNCTION public._pedido_cliente_loja_estafeta_guarda();

CREATE OR REPLACE TRIGGER a00_pedido_loja_estafeta_guarda_ins
  BEFORE INSERT ON public.orders
  FOR EACH ROW
  WHEN (NEW.assigned_driver_id IS NOT NULL OR NEW.driver_id IS NOT NULL
        OR NEW.current_driver_offer_id IS NOT NULL OR NEW.preassigned_driver_id IS NOT NULL
        OR NEW.helper_driver_id IS NOT NULL
        OR COALESCE(cardinality(NEW.tried_driver_ids), 0) > 0
        OR NEW.driver_offer_expires_at IS NOT NULL
        OR COALESCE(NEW.driver_offer_history, '[]'::jsonb) <> '[]'::jsonb)
  EXECUTE FUNCTION public._pedido_cliente_loja_estafeta_guarda();

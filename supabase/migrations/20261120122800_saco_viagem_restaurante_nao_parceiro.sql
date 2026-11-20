-- Saco para viagem — restaurante NÃO-parceiro (missão saco-viagem-2026-11-20).
--
-- Pedido do Danilo (20/11/2026): no McDonald's, Burger King e KFC o estafeta
-- compra ao balcão e o cliente nunca pede o saco; o estafeta esquece-se de
-- pedir o saco para viagem e paga-o do bolso. Regra: em restaurante
-- não-parceiro com bag_count > 0 o estafeta TEM de carregar em
-- "Comprei o saco" antes de fechar a compra.
--
-- O que muda:
--   1. order_purchase_drafts ganha a marca do saco (quem, quando) e o sinal de
--      que a app nova pediu o saco neste pedido (saco_viagem_exigido).
--   2. estafeta_saco_viagem: a app regista "este pedido pede saco" ao abrir a
--      lista e grava "comprei o saco" (ou desfaz) no servidor.
--   3. Guarda no fecho da compra (trigger em orders, is_purchase_finalized
--      false -> true): recusa fechar se a app pediu o saco e ele não foi
--      marcado. Vale para finalizar_talao_nao_parceiro e qualquer outra via.
--      Pedidos que a app antiga trata (sem saco_viagem_exigido) não ficam
--      presos. Admin e serviço (MCP) passam, e o painel mostra o alerta.
--   4. admin_saco_viagem_do_pedido: o painel vê se o saco foi marcado, por
--      quem, quando, e o alerta de compra fechada sem saco.
--
-- NÃO mexe em dinheiro: preços, sacos cobrados, totais, reembolso e ganhos
-- ficam como estão (finalizar_talao_nao_parceiro não foi alterada).

-- 1) Marca do saco no rascunho da compra ------------------------------------
ALTER TABLE public.order_purchase_drafts
  ADD COLUMN IF NOT EXISTS saco_viagem_exigido     boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS saco_viagem_marcado_em  timestamptz,
  ADD COLUMN IF NOT EXISTS saco_viagem_marcado_por uuid;

COMMENT ON COLUMN public.order_purchase_drafts.saco_viagem_exigido IS
  'A app do estafeta mostrou a linha "SACO PARA VIAGEM" neste pedido (restaurante não-parceiro). Com true, o fecho da compra exige saco_viagem_marcado_em.';
COMMENT ON COLUMN public.order_purchase_drafts.saco_viagem_marcado_em IS
  'Hora em que o estafeta carregou em "Comprei o saco". NULL = por marcar.';
COMMENT ON COLUMN public.order_purchase_drafts.saco_viagem_marcado_por IS
  'auth.uid() de quem marcou o saco.';

-- 2) O pedido pede saco para viagem? -----------------------------------------
CREATE OR REPLACE FUNCTION public._saco_viagem_obrigatorio(
  p_service_type text, p_is_partner_store boolean, p_restaurant_id text, p_bag_count integer)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $$
  SELECT p_service_type = 'restaurant'
     AND COALESCE(p_bag_count, 0) > 0
     AND NOT COALESCE(
           (SELECT r.is_partner FROM public.restaurants r WHERE r.id::text = p_restaurant_id),
           p_is_partner_store, false);
$$;
REVOKE ALL ON FUNCTION public._saco_viagem_obrigatorio(text, boolean, text, integer) FROM PUBLIC, anon, authenticated;

-- 3) A app do estafeta: registar / marcar / desfazer --------------------------
-- p_comprado NULL  -> só regista que a app pediu o saco (ao abrir a lista);
-- p_comprado true  -> "Comprei o saco" (mantém a primeira hora se repetir);
-- p_comprado false -> desfaz a marca.
CREATE OR REPLACE FUNCTION public.estafeta_saco_viagem(p_order_id text, p_comprado boolean DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_o   record;
  v_row public.order_purchase_drafts%ROWTYPE;
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'UNAUTHENTICATED');
  END IF;

  SELECT id, assigned_driver_id, current_driver_offer_id, status, is_purchase_finalized,
         service_type, is_partner_store, restaurant_id, bag_count
    INTO v_o FROM public.orders WHERE id = p_order_id;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('ok', false, 'error', 'ORDER_NOT_FOUND');
  END IF;
  -- Mesmos estafetas que finalizar_talao_nao_parceiro aceita.
  IF NOT (public._estafeta_atribuido(v_o.assigned_driver_id, v_uid)
          OR v_o.current_driver_offer_id IS NOT DISTINCT FROM v_uid::text) THEN
    RETURN jsonb_build_object('ok', false, 'error', 'NOT_ASSIGNED_DRIVER');
  END IF;
  IF NOT public._saco_viagem_obrigatorio(v_o.service_type, v_o.is_partner_store,
                                         v_o.restaurant_id::text, v_o.bag_count) THEN
    RETURN jsonb_build_object('ok', true, 'obrigatorio', false);
  END IF;

  IF COALESCE(v_o.is_purchase_finalized, false)
     OR v_o.status IN ('delivered', 'cancelled', 'rejected') THEN
    -- Compra já fechada: só se lê o que ficou (nada muda).
    SELECT * INTO v_row FROM public.order_purchase_drafts WHERE order_id = p_order_id;
    RETURN jsonb_build_object('ok', true, 'obrigatorio', true, 'fechado', true,
      'marcado', v_row.saco_viagem_marcado_em IS NOT NULL,
      'marcado_em', v_row.saco_viagem_marcado_em,
      'bag_count', v_o.bag_count);
  END IF;

  INSERT INTO public.order_purchase_drafts AS d (
    order_id, driver_uid, saco_viagem_exigido,
    saco_viagem_marcado_em, saco_viagem_marcado_por, updated_at
  ) VALUES (
    p_order_id, v_uid, true,
    CASE WHEN p_comprado IS TRUE THEN now() END,
    CASE WHEN p_comprado IS TRUE THEN v_uid END,
    now()
  )
  ON CONFLICT (order_id) DO UPDATE SET
    saco_viagem_exigido     = true,
    saco_viagem_marcado_em  = CASE
      WHEN p_comprado IS NULL  THEN d.saco_viagem_marcado_em
      WHEN p_comprado          THEN COALESCE(d.saco_viagem_marcado_em, now())
      ELSE NULL END,
    saco_viagem_marcado_por = CASE
      WHEN p_comprado IS NULL  THEN d.saco_viagem_marcado_por
      WHEN p_comprado          THEN COALESCE(d.saco_viagem_marcado_por, v_uid)
      ELSE NULL END,
    updated_at              = CASE WHEN p_comprado IS NULL THEN d.updated_at ELSE now() END
  RETURNING * INTO v_row;

  RETURN jsonb_build_object('ok', true, 'obrigatorio', true, 'fechado', false,
    'marcado', v_row.saco_viagem_marcado_em IS NOT NULL,
    'marcado_em', v_row.saco_viagem_marcado_em,
    'bag_count', v_o.bag_count);
END;
$$;
REVOKE ALL ON FUNCTION public.estafeta_saco_viagem(text, boolean) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.estafeta_saco_viagem(text, boolean) TO authenticated;

-- 4) Guarda no fecho da compra -----------------------------------------------
CREATE OR REPLACE FUNCTION public.trg_exige_saco_viagem_ao_fechar_compra()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_d record;
BEGIN
  IF NOT public._saco_viagem_obrigatorio(NEW.service_type, NEW.is_partner_store,
                                         NEW.restaurant_id::text,
                                         COALESCE(NEW.bag_count, OLD.bag_count)) THEN
    RETURN NEW;
  END IF;

  SELECT saco_viagem_exigido, saco_viagem_marcado_em INTO v_d
    FROM public.order_purchase_drafts WHERE order_id = NEW.id;

  -- Só a app nova pede o saco (saco_viagem_exigido): um pedido tratado pela
  -- app antiga não fica preso. Admin e serviço (sem sessão) passam — o painel
  -- mostra o alerta "compra fechada sem saco".
  IF COALESCE(v_d.saco_viagem_exigido, false)
     AND v_d.saco_viagem_marcado_em IS NULL
     AND auth.uid() IS NOT NULL
     AND NOT public.is_admin() THEN
    RAISE EXCEPTION 'SACO_VIAGEM_POR_MARCAR: Falta marcar o saco para viagem. Pede 1 saco ao balcão e carrega em "Comprei o saco" antes de confirmar a compra.'
      USING ERRCODE = 'P0001';
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_exige_saco_viagem_ao_fechar_compra ON public.orders;
CREATE TRIGGER trg_exige_saco_viagem_ao_fechar_compra
  BEFORE UPDATE OF is_purchase_finalized ON public.orders
  FOR EACH ROW
  WHEN (NEW.is_purchase_finalized IS TRUE AND OLD.is_purchase_finalized IS DISTINCT FROM TRUE)
  EXECUTE FUNCTION public.trg_exige_saco_viagem_ao_fechar_compra();

-- 5) Painel: o saco do pedido --------------------------------------------------
CREATE OR REPLACE FUNCTION public.admin_saco_viagem_do_pedido(p_order_id text)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_o   record;
  v_d   record;
  v_obr boolean;
  v_quem text;
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'FORBIDDEN'; END IF;
  SELECT id, service_type, is_partner_store, restaurant_id, bag_count, status,
         is_purchase_finalized, vendor_name
    INTO v_o FROM public.orders WHERE id = p_order_id;
  IF NOT FOUND THEN RETURN jsonb_build_object('ok', false, 'error', 'ORDER_NOT_FOUND'); END IF;

  v_obr := public._saco_viagem_obrigatorio(v_o.service_type, v_o.is_partner_store,
                                           v_o.restaurant_id::text, v_o.bag_count);
  IF NOT v_obr THEN
    RETURN jsonb_build_object('ok', true, 'obrigatorio', false);
  END IF;

  SELECT saco_viagem_exigido, saco_viagem_marcado_em, saco_viagem_marcado_por
    INTO v_d FROM public.order_purchase_drafts WHERE order_id = p_order_id;
  IF v_d.saco_viagem_marcado_por IS NOT NULL THEN
    SELECT COALESCE(NULLIF(d.name, ''), 'entregador') INTO v_quem
      FROM public.drivers d WHERE d.user_id = v_d.saco_viagem_marcado_por LIMIT 1;
    v_quem := COALESCE(v_quem, 'admin/outro (' || left(v_d.saco_viagem_marcado_por::text, 8) || ')');
  END IF;

  RETURN jsonb_build_object(
    'ok', true,
    'obrigatorio', true,
    'loja', v_o.vendor_name,
    'sacos', v_o.bag_count,
    'app_pediu_saco', COALESCE(v_d.saco_viagem_exigido, false),
    'marcado', v_d.saco_viagem_marcado_em IS NOT NULL,
    'marcado_em', v_d.saco_viagem_marcado_em,
    'marcado_por', v_quem,
    'compra_fechada', COALESCE(v_o.is_purchase_finalized, false),
    'fechado_sem_saco', COALESCE(v_o.is_purchase_finalized, false)
                        AND v_d.saco_viagem_marcado_em IS NULL);
END;
$$;
REVOKE ALL ON FUNCTION public.admin_saco_viagem_do_pedido(text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_saco_viagem_do_pedido(text) TO authenticated;

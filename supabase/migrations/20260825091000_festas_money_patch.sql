-- AVISO: NAO APLICADA - AGUARDA "vai" DO DANILO (Trava protege-dinheiro bloqueia o agente).
-- FESTAS MONEY PATCH (2026-08-25) - parte financeira do lancamento Festas:
--   1) create_order grava orders.scheduled_for do p_input (fecha o buraco do cartao,
--      onde a ordem nasce no webhook sem o cliente presente);
--   2) create_order + quote_order_pricing: loja categoria "festas" NAO cobra saco
--      (regra 4 da ordem do Danilo: "0,30 nunca aparece, nem no misto").
-- Enquanto nao aplicada: a data grava-se pela RPC verde festas_set_schedule
-- (chamada pela app apos criar o pedido) e o saco continua a ser cobrado.
-- 1) create_order grava orders.scheduled_for vindo do p_input (NULL = imediato).
-- 2) Lojas categoria 'festas' não cobram saco (regra 4 da ordem: "€0,30 nunca aparece").
--    Remendo aplicado por REPLACE textual sobre a definição VIVA (a def local estava
--    ~500 bytes atrás da produção), com âncoras verificadas — se uma âncora não bater,
--    a migration ABORTA sem tocar nada.
-- 3) festas_accept(p_order_id, p_prep_minutes): aceite com tempo, espelho fiel da
--    partner_takeaway_accept (dual-owner user_/user_id, categoria festas, 5..480 min).

-- Backup das definições actuais (reversível).
CREATE TABLE IF NOT EXISTS public._fn_backups (
  id bigserial PRIMARY KEY,
  fn_name text NOT NULL,
  def text NOT NULL,
  saved_at timestamptz NOT NULL DEFAULT now()
);
INSERT INTO public._fn_backups (fn_name, def)
VALUES ('create_order(jsonb)', pg_get_functiondef('create_order(jsonb)'::regprocedure)),
       ('quote_order_pricing(jsonb)', pg_get_functiondef('quote_order_pricing(jsonb)'::regprocedure));

-- 1+2) create_order: scheduled_for no INSERT + isenção de saco para festas.
DO $do$
DECLARE
  v_def text := pg_get_functiondef('create_order(jsonb)'::regprocedure);
  v_a1 text := $a$    takeaway_is_curbside, takeaway_curbside_info, takeaway_pickup_code
  ) VALUES ($a$;
  v_a2 text := $a$    v_takeaway_curbside,
    p_input->>'takeaway_curbside_info',
    v_takeaway_pickup_code
  );$a$;
  v_a3 text := $a$    v_bag_fee             := v_pricing.bag_fee;
  END IF;$a$;
BEGIN
  IF POSITION(v_a1 IN v_def) = 0 OR POSITION(v_a2 IN v_def) = 0 OR POSITION(v_a3 IN v_def) = 0 THEN
    RAISE EXCEPTION 'festas_launch: ancora nao encontrada em create_order — abortado sem alterar nada';
  END IF;
  v_def := replace(v_def, v_a1, $r$    takeaway_is_curbside, takeaway_curbside_info, takeaway_pickup_code,
    scheduled_for
  ) VALUES ($r$);
  v_def := replace(v_def, v_a2, $r$    v_takeaway_curbside,
    p_input->>'takeaway_curbside_info',
    v_takeaway_pickup_code,
    NULLIF(p_input->>'scheduled_for','')::timestamptz
  );$r$);
  v_def := replace(v_def, v_a3, $r$    v_bag_fee             := v_pricing.bag_fee;
  END IF;

  -- Festas (2026-08-25, ordem do Danilo): lojas categoria 'festas' sem saco.
  IF v_bag_fee > 0 AND EXISTS (
    SELECT 1 FROM public.restaurants fr
    WHERE fr.id = p_input->>'restaurant_id' AND fr.category = 'festas'
  ) THEN
    v_customer_total := ROUND((v_customer_total - v_bag_fee)::numeric, 2);
    v_bag_fee := 0;
  END IF;$r$);
  EXECUTE v_def;
END $do$;

-- 2b) quote_order_pricing: a mesma isenção, para o orçamento bater com a cobrança.
DO $do$
DECLARE
  v_def text := pg_get_functiondef('quote_order_pricing(jsonb)'::regprocedure);
  v_q1 text := $a$  v_max_wallet_cents := ROUND(v_pricing.customer_total * 100)::INTEGER;$a$;
BEGIN
  IF POSITION(v_q1 IN v_def) = 0 THEN
    RAISE EXCEPTION 'festas_launch: ancora nao encontrada em quote_order_pricing — abortado';
  END IF;
  v_def := replace(v_def, v_q1, $r$  -- Festas (2026-08-25): sem saco na categoria.
  IF v_pricing.bag_fee > 0 AND EXISTS (
    SELECT 1 FROM public.restaurants fr
    WHERE fr.id = p_input->>'restaurant_id' AND fr.category = 'festas'
  ) THEN
    v_pricing.customer_total := ROUND((v_pricing.customer_total - v_pricing.bag_fee)::numeric, 2);
    v_pricing.bag_fee := 0;
  END IF;

  v_max_wallet_cents := ROUND(v_pricing.customer_total * 100)::INTEGER;$r$);
  EXECUTE v_def;
END $do$;

-- 3) Aceite com tempo da loja de festas. Espelho da partner_takeaway_accept com:
--    dual-owner (user_ OU user_id), categoria festas obrigatória, minutos livres 5..480
--    (chips 15/20/30/40/50/60/80/90 + campo livre no painel). Serve entrega E recolha:
--    num pedido takeaway escreve também takeaway_prep_minutes para o countdown existente.

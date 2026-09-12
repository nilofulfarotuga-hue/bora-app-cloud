-- MEGA-FIX 2026-07-18 Parte 8 — favores: a 3ª perna que falta.
--
-- Bug provado (pedido b7867337): a morada da paragem em casa era geocodificada no form e
-- DEITADA FORA — não havia coluna. O estafeta ia para o sítio errado (`pickup_address` tinha o
-- LOCAL DO FAVOR, não a casa) e o `errand_home_stop_cash_cents` ficava 0.
--
-- Aqui: colunas novas para a paragem em casa + perna de volta + índice da perna. A persistência
-- NÃO passa pela `create_order` (28 KB, checkout que cobra = Lista Vermelha) — usa a RPC
-- `errand_set_home_stop` (não-financeira, dona-do-pedido) chamada logo após a criação do pedido.

ALTER TABLE public.orders
  ADD COLUMN IF NOT EXISTS errand_home_stop_address text,
  ADD COLUMN IF NOT EXISTS errand_home_stop_lat     double precision,
  ADD COLUMN IF NOT EXISTS errand_home_stop_lng     double precision,
  ADD COLUMN IF NOT EXISTS errand_return_leg        boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS errand_return_done_at    timestamptz,
  -- Índice da perna atual do favor: 0=por-iniciar, 1=em-casa, 2=no-favor, 3=de-volta.
  -- Controla a sequência SEM criar enum novo no motor de estados (usa os status existentes).
  ADD COLUMN IF NOT EXISTS errand_leg               smallint NOT NULL DEFAULT 0;

-- RPC não-financeira: grava os detalhes da paragem em casa depois do pedido criado.
-- Dona-do-pedido (auth.uid() == orders.user_id). NÃO toca em valores cobrados.
CREATE OR REPLACE FUNCTION public.errand_set_home_stop(
  p_order_id   text,
  p_address    text,
  p_lat        double precision,
  p_lng        double precision,
  p_cash_cents integer DEFAULT NULL,
  p_return_leg boolean DEFAULT NULL)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_uid   uuid := auth.uid();
  v_owner uuid;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'not_authenticated' USING ERRCODE='42501'; END IF;
  SELECT user_id INTO v_owner FROM orders WHERE id = p_order_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'order_not_found: %', p_order_id USING ERRCODE='P0002'; END IF;
  IF v_owner IS DISTINCT FROM v_uid THEN
    RAISE EXCEPTION 'forbidden' USING ERRCODE='42501';
  END IF;

  UPDATE orders SET
    errand_home_stop            = true,
    errand_home_stop_address    = NULLIF(trim(COALESCE(p_address,'')),''),
    errand_home_stop_lat        = p_lat,
    errand_home_stop_lng        = p_lng,
    errand_home_stop_cash_cents = COALESCE(p_cash_cents, errand_home_stop_cash_cents),
    errand_return_leg           = COALESCE(p_return_leg, errand_return_leg)
  WHERE id = p_order_id;

  RETURN jsonb_build_object('success', true, 'order_id', p_order_id);
END $function$;

GRANT EXECUTE ON FUNCTION public.errand_set_home_stop(text, text, double precision, double precision, integer, boolean) TO authenticated;

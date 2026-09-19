-- ============================================================================
-- BORA — RPC update_bag_count_bypass (continuação do fix BUG 27)
-- ============================================================================
-- Antes: driver_home_screen → OrderStore.updateBagCount fazia UPDATE directo
-- a orders.bag_fee, bloqueado pelo trigger enforce_financial_immutability.
-- Erro engolido pelo catch ⇒ DB ficava com bag_count=1 (default do create_order).
--
-- Agora: RPC SECURITY DEFINER que bypassa o trigger via session GUC
-- (app.financial_bypass=true). Calcula bag_fee server-side a partir de
-- platform_settings.bag_fee_supermarket_per_bag_cents.
--
-- Diferente de finalize_storeshopping_purchase: esta RPC NÃO marca
-- is_purchase_finalized — é uma actualização incremental durante a entrega,
-- antes do passo final (delivery code + finalize).
-- ============================================================================

BEGIN;

CREATE OR REPLACE FUNCTION public.update_bag_count_bypass(
  p_order_id TEXT,
  p_count    INT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $function$
DECLARE
  v_caller_uid     UUID;
  v_order          RECORD;
  v_per_bag_cents  INT;
  v_bag_fee_cents  INT;
BEGIN
  v_caller_uid := auth.uid();
  IF v_caller_uid IS NULL THEN
    RAISE EXCEPTION 'unauthenticated' USING ERRCODE = '42501';
  END IF;

  IF p_count < 0 OR p_count > 99 THEN
    RAISE EXCEPTION 'invalid_bag_count: % (allowed 0..99)', p_count
      USING ERRCODE = '22023';
  END IF;

  SELECT * INTO v_order FROM public.orders WHERE id = p_order_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'order_not_found: %', p_order_id USING ERRCODE = 'P0002';
  END IF;

  -- Só o driver atribuído pode actualizar.
  IF v_order.assigned_driver_id IS DISTINCT FROM v_caller_uid::text THEN
    RAISE EXCEPTION 'forbidden_not_assigned_driver: caller=% driver=%',
      v_caller_uid, v_order.assigned_driver_id
      USING ERRCODE = '42501';
  END IF;

  -- Aplicável apenas a storeShopping (mercados não-parceiros: €0.10/saco).
  IF v_order.service_type <> 'storeShopping' THEN
    RAISE EXCEPTION 'wrong_service_type: % (expected storeShopping)',
      v_order.service_type
      USING ERRCODE = '23514';
  END IF;

  -- Depois da finalização as colunas financeiras são imutáveis.
  IF COALESCE(v_order.is_purchase_finalized, false) = true THEN
    RAISE EXCEPTION 'already_finalized' USING ERRCODE = '23514';
  END IF;

  -- Lê preço por saco do platform_settings (default 10c).
  SELECT COALESCE((value::text)::int, 10) INTO v_per_bag_cents
    FROM public.platform_settings
   WHERE key = 'bag_fee_supermarket_per_bag_cents';
  v_per_bag_cents := COALESCE(v_per_bag_cents, 10);
  v_bag_fee_cents := p_count * v_per_bag_cents;

  -- Bypass do trigger enforce_financial_immutability (mesma técnica usada
  -- em finalize_storeshopping_purchase).
  PERFORM set_config('app.financial_bypass', 'true', true);

  UPDATE public.orders SET
    bag_count = p_count,
    bag_fee   = v_bag_fee_cents::numeric / 100.0
  WHERE id = p_order_id;

  RETURN jsonb_build_object(
    'success',       true,
    'order_id',      p_order_id,
    'bag_count',     p_count,
    'bag_fee_cents', v_bag_fee_cents
  );
END;
$function$;

REVOKE ALL ON FUNCTION public.update_bag_count_bypass(text, int) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.update_bag_count_bypass(text, int) TO authenticated;

COMMIT;

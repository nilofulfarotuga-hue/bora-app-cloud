-- TVDE — Preferências de trabalho do motorista (decisão do Danilo · P1 paridade).
-- O motorista escolhe: 'rides_only' (só corridas de passageiros) OU 'everything'
-- (corridas + entregas + supermercado + favores).
--
-- SEGURANÇA / ISOLAMENTO:
--   • Default 'everything' → ZERO regressão para os estafetas de entrega actuais.
--   • O filtro no DELIVERY é ADITIVO e por-agora documentado (ver
--     TVDE_RELATORIO_FINAL.md): excluir do matching quem escolher 'rides_only'.
--     NÃO se toca no dispatch_engine core (zona protegida) nesta migration.
--   • No TVDE, tvde_offer_to_next já filtra por vehicle_type='carro_passageiros';
--     um motorista 'rides_only' continua elegível para corridas (correcto).

ALTER TABLE public.drivers
  ADD COLUMN IF NOT EXISTS work_mode text NOT NULL DEFAULT 'everything';

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'drivers_work_mode_check') THEN
    ALTER TABLE public.drivers
      ADD CONSTRAINT drivers_work_mode_check CHECK (work_mode IN ('rides_only','everything'));
  END IF;
END $$;

-- ── Motorista define a sua própria preferência ──────────────────────────────
CREATE OR REPLACE FUNCTION public.tvde_set_work_mode(p_mode text)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'not_authenticated'; END IF;
  IF p_mode NOT IN ('rides_only','everything') THEN RAISE EXCEPTION 'invalid_mode: %', p_mode; END IF;
  UPDATE public.drivers SET work_mode = p_mode WHERE user_id = auth.uid();
  RETURN p_mode;
END; $function$;

REVOKE ALL ON FUNCTION public.tvde_set_work_mode(text) FROM public, anon;
GRANT EXECUTE ON FUNCTION public.tvde_set_work_mode(text) TO authenticated;

-- ── Admin vê/edita a preferência de qualquer motorista ──────────────────────
CREATE OR REPLACE FUNCTION public.admin_set_driver_work_mode(p_driver_id uuid, p_mode text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE v_admin RECORD;
BEGIN
  SELECT admin_id, admin_email INTO v_admin FROM public._admin_op_guard();
  IF p_mode NOT IN ('rides_only','everything') THEN RAISE EXCEPTION 'invalid_mode: %', p_mode; END IF;
  UPDATE public.drivers SET work_mode = p_mode
   WHERE user_id = p_driver_id OR id = p_driver_id;
  PERFORM public.log_admin_action('tvde_set_work_mode', 'driver', p_driver_id,
    jsonb_build_object('mode', p_mode));
  RETURN jsonb_build_object('driver_id', p_driver_id, 'work_mode', p_mode);
END; $function$;

REVOKE ALL ON FUNCTION public.admin_set_driver_work_mode(uuid, text) FROM public, anon;
GRANT EXECUTE ON FUNCTION public.admin_set_driver_work_mode(uuid, text) TO authenticated;

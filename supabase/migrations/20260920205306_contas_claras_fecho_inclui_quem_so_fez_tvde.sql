-- APLICADA EM PRODUÇÃO pela Claude.ai (MCP) a 20/09/2026 21:53 — versão 20260920205306.
-- Espelho exacto de supabase_migrations.schema_migrations (lido a 20/09 21:55 pelo Claude Code).
CREATE OR REPLACE FUNCTION public.close_previous_week_settlements()
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_count INT := 0;
  v_anchor TIMESTAMPTZ := now() - interval '1 day';  -- domingo passado
  v_drv RECORD;
BEGIN
  -- CONTAS CLARAS 2026-09-20: o fecho so percorria quem fez ENTREGAS, por isso
  -- quem trabalhou apenas em TVDE ficava de fora do acerto e nunca era pago.
  -- Passa a percorrer as duas origens.
  FOR v_drv IN
    SELECT DISTINCT id FROM (
      SELECT o.assigned_driver_id::uuid AS id
      FROM public.orders o, public.driver_settlement_week_bounds(v_anchor) b
      WHERE o.status = 'delivered'
        AND o.delivered_at >= b.week_start
        AND o.delivered_at <= b.week_end
        AND o.assigned_driver_id ~ '^[0-9a-f]{8}-'
      UNION
      SELECT r.driver_id AS id
      FROM public.tvde_rides r, public.driver_settlement_week_bounds(v_anchor) b
      WHERE r.status = 'finalizada'
        AND r.driver_id IS NOT NULL
        AND r.created_at >= b.week_start
        AND r.created_at <= b.week_end
    ) todos
  LOOP
    PERFORM public.compute_driver_settlement(v_drv.id, v_anchor, true);
    v_count := v_count + 1;
  END LOOP;
  RETURN v_count;
END;
$function$;

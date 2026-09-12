-- MEGA-FIX 2026-07-18 Parte 10 — presença dos estafetas: nunca mais fantasmas.
--
-- Bug provado: 3 drivers `is_online=true` com `last_heartbeat_at` de 3,5 dias atrás (ou NUNCA).
-- O dispatch oferecia-lhes corridas → pedido preso até expirar. `is_online` sem TTL = dispatch
-- para mortos. Ver .claude/.ai/knowledge/wiki/licoes/licao-heartbeat-fantasma.md
--
-- Cura: cron a cada 5 min desliga quem não bate o coração há >15 min. NÃO toca no dispatch.

CREATE OR REPLACE FUNCTION public.expire_stale_driver_presence()
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_count integer;
BEGIN
  UPDATE public.drivers
     SET is_online = false
   WHERE is_online
     AND (last_heartbeat_at IS NULL
          OR last_heartbeat_at < now() - interval '15 minutes');
  GET DIAGNOSTICS v_count = ROW_COUNT;
  RETURN v_count;
END;
$function$;

-- pg_cron: idempotente por nome (cron.schedule substitui um job homónimo existente).
SELECT cron.schedule(
  'drivers-heartbeat-expire',
  '*/5 * * * *',
  $$SELECT public.expire_stale_driver_presence();$$
);

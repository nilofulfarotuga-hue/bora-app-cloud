-- ═══════════════════════════════════════════════════════════
-- B2 commit 2 — Pre-migration backup (2026-05-05)
-- Sessão 4 C3 conclusão — DROP+RENAME final_total numeric
-- ═══════════════════════════════════════════════════════════
-- Captura via MCP execute_sql do estado pré-migração.
-- Restore se rollback for necessário (ver A5 plano rollback).
--
-- Estado actual:
--   orders.final_total          : double precision
--   orders.final_total_numeric  : numeric
--   trigger trg_zz_final_total_dual_write : EXISTE
--   função fn_sync_final_total_numeric    : EXISTE
--   drift                                  : 0 (94 orders, +24h smoke OK)

-- ───────────────────────────────────────────────────────────
-- 1. Trigger dual-write (SERÁ DROPADO em B2)
-- ───────────────────────────────────────────────────────────
CREATE TRIGGER trg_zz_final_total_dual_write
  BEFORE INSERT OR UPDATE OF final_total
  ON public.orders
  FOR EACH ROW
  EXECUTE FUNCTION fn_sync_final_total_numeric();

-- ───────────────────────────────────────────────────────────
-- 2. Função sync (SERÁ DROPADA em B2)
-- ───────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.fn_sync_final_total_numeric()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
BEGIN
  -- Sync final_total → final_total_numeric.
  -- NÃO recursivo: BEFORE OF final_total, escreve em coluna diferente.
  NEW.final_total_numeric := NEW.final_total::numeric;
  RETURN NEW;
END;
$function$;

-- ───────────────────────────────────────────────────────────
-- 3. RPC agent_get_user_orders_summary — DEFINIÇÃO ORIGINAL
--    (referencia final_total_numeric directamente — fix em B2)
-- ───────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.agent_get_user_orders_summary(p_limit integer DEFAULT 5)
 RETURNS TABLE(order_id text, status text, created_at timestamp with time zone, partner_name text, total_cents integer, can_be_cancelled boolean)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'NOT_AUTHENTICATED';
  END IF;
  RETURN QUERY
  SELECT
    o.id, o.status, o.created_at,
    COALESCE(r.name, 'N/D'),
    ROUND((COALESCE(o.final_total_numeric, o.final_total::numeric, 0))*100)::int,
    o.status IN ('pending','accepted')
  FROM public.orders o
  LEFT JOIN public.restaurants r ON r.id = o.restaurant_id
  WHERE o.user_id = auth.uid()
  ORDER BY o.created_at DESC
  LIMIT LEAST(GREATEST(p_limit, 1), 20);
END$function$;

-- ───────────────────────────────────────────────────────────
-- 4. Coluna double precision (SERÁ DROPADA em B2)
--    Para restore manual:
--    ALTER TABLE public.orders
--      ADD COLUMN final_total_double double precision;
--    UPDATE public.orders
--      SET final_total_double = final_total_numeric::double precision;
-- ───────────────────────────────────────────────────────────
-- (Estado pré: orders.final_total double precision com 94 rows preservadas)

-- ═══════════════════════════════════════════════════════════
-- FIM BACKUP — usar este ficheiro APENAS em caso de rollback.
-- Em condições normais, B2 PARTE 2 substitui este estado.
-- ═══════════════════════════════════════════════════════════

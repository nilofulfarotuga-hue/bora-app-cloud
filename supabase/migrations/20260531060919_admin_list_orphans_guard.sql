-- Alinha repo↔produção (cloud migration 20260531060919, aplicada 2026-05-31).
-- Fecha admin_list_orphans: guard app_metadata.role='admin' no corpo +
-- acesso só a authenticated (admin passa o guard) e service_role. anon/PUBLIC revogados.
-- Reflete o ESTADO VIVO em produção (verificado por pg_get_functiondef + grants 2026-05-31).
-- NÃO re-aplicar manualmente — já vivo; ficheiro só para fidelidade num deploy futuro.

CREATE OR REPLACE FUNCTION public.admin_list_orphans()
 RETURNS TABLE(kind text, id text, user_id uuid, payment_intent_id text, amount numeric, age_minutes numeric, notes text)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
  IF (auth.jwt() -> 'app_metadata' ->> 'role') != 'admin' THEN
    RAISE EXCEPTION 'insufficient_privilege';
  END IF;

  RETURN QUERY
    SELECT 'payment_draft'::TEXT AS kind,
           pd.id::TEXT,
           pd.user_id,
           pd.payment_intent_id,
           (pd.amount_cents / 100.0)::NUMERIC AS amount,
           EXTRACT(EPOCH FROM (NOW() - pd.created_at)) / 60 AS age_minutes,
           CASE
             WHEN pd.expires_at < NOW() THEN 'expired'
             WHEN pd.used_at IS NOT NULL THEN 'used'
             ELSE 'pending'
           END AS notes
    FROM public.payment_drafts pd
    WHERE pd.used_at IS NULL
    UNION ALL
    SELECT 'order_no_charge'::TEXT AS kind,
           o.id,
           o.user_id::UUID,
           o.payment_intent_id,
           o.total::NUMERIC AS amount,
           EXTRACT(EPOCH FROM (NOW() - o.created_at)) / 60 AS age_minutes,
           COALESCE(o.cancel_reason, 'unknown') AS notes
    FROM public.orders o
    WHERE o.payment_status = 'cancelled_no_charge'
    ORDER BY age_minutes DESC
    LIMIT 100;
END;
$function$;

REVOKE EXECUTE ON FUNCTION public.admin_list_orphans() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_list_orphans() TO authenticated, service_role;

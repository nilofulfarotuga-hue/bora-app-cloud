-- =============================================================================
-- ROBOT B v4 — robot_observe(): agrega TODAS as fontes de observação num jsonb.
-- Chamada pela Edge Function robot-b a cada ciclo (service_role apenas). Read-only.
-- SECURITY DEFINER para alcançar cron.*, net.*, pg_catalog, extensions.
--
-- NOTA: no remoto esta função foi aplicada em 3 passos (20260610150808 +
-- 20260610150934 fix driver_push_tokens.user_id + 20260610151040 fix enum cast).
-- Este ficheiro é a versão final consolidada.
-- =============================================================================

CREATE OR REPLACE FUNCTION public.robot_observe()
RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path = public, extensions, pg_temp
AS $$
DECLARE v jsonb;
BEGIN
  SELECT jsonb_build_object(
    'cron_failures_24h', COALESCE((
      SELECT jsonb_agg(x) FROM (
        SELECT j.jobname, d.status, left(d.return_message, 160) AS msg,
               d.start_time
          FROM cron.job_run_details d
          JOIN cron.job j ON j.jobid = d.jobid
         WHERE d.status = 'failed' AND d.start_time > now() - interval '24 hours'
         ORDER BY d.start_time DESC LIMIT 10) x), '[]'::jsonb),
    'http_errors_24h', (
      SELECT jsonb_build_object(
        'count', count(*),
        'sample', COALESCE(jsonb_agg(jsonb_build_object(
            'status', status_code, 'err', left(COALESCE(error_msg,''),120),
            'created', created)) FILTER (WHERE rn <= 5), '[]'::jsonb))
        FROM (SELECT status_code, error_msg, created,
                     row_number() OVER (ORDER BY created DESC) rn
                FROM net._http_response
               WHERE created > now() - interval '24 hours'
                 AND (status_code >= 400 OR timed_out OR error_msg IS NOT NULL)) e),
    'stuck_orders', (
      SELECT jsonb_build_object('count', count(*),
        'ids', COALESCE(jsonb_agg(id) FILTER (WHERE rn <= 5), '[]'::jsonb))
        FROM (SELECT id, row_number() OVER (ORDER BY created_at) rn
                FROM public.orders
               WHERE status IN ('created','preparing','callingDriver')
                 AND created_at < now() - interval '2 hours'
                 AND COALESCE(is_test_order,false) = false) s),
    'orphan_pending_appointments', (
      SELECT jsonb_build_object('count', count(*),
        'ids', COALESCE(jsonb_agg(id) FILTER (WHERE rn <= 5), '[]'::jsonb))
        FROM (SELECT id, row_number() OVER (ORDER BY created_at) rn
                FROM public.appointments
               WHERE deposit_status = 'pending'
                 AND created_at < now() - interval '2 hours'
                 AND status NOT IN ('cancelled','completed')) a),
    'products_no_photo_count', (
      SELECT count(*) FROM public.products
       WHERE is_available = true AND (photo_url IS NULL OR photo_url = '')),
    'products_no_category_count', (
      SELECT count(*) FROM public.products
       WHERE is_available = true AND (taxonomy_section IS NULL OR taxonomy_section = '')),
    'products_unpriced_market', (
      SELECT jsonb_build_object('count', count(*),
        'ids', COALESCE(jsonb_agg(pid) FILTER (WHERE rn <= 50), '[]'::jsonb))
        FROM (SELECT p.id pid, row_number() OVER (ORDER BY p.id) rn
                FROM public.products p
                JOIN public.restaurants r ON r.id = p.restaurant_id
               WHERE COALESCE(r.is_partner,false) = false
                 AND p.is_available = true
                 AND (p.price IS NULL OR p.price <= 0)) u),
    'products_suspicious_price', (
      SELECT jsonb_build_object('count', count(*),
        'ids', COALESCE(jsonb_agg(pid) FILTER (WHERE rn <= 50), '[]'::jsonb))
        FROM (SELECT p.id pid, row_number() OVER (ORDER BY p.price DESC) rn
                FROM public.products p
                JOIN public.restaurants r ON r.id = p.restaurant_id
               WHERE COALESCE(r.is_partner,false) = false
                 AND p.is_available = true
                 AND COALESCE(p.needs_review,false) = false
                 AND (p.price > 500 OR (p.price > 0 AND p.price < 0.05))) sp),
    'products_review_backlog', (
      SELECT count(*) FROM public.products WHERE COALESCE(needs_review,false) = true),
    'drivers_online_no_token', (
      SELECT jsonb_build_object('count', count(*),
        'names', COALESCE(jsonb_agg(name) FILTER (WHERE rn <= 5), '[]'::jsonb))
        FROM (SELECT d.name, row_number() OVER (ORDER BY d.name) rn
                FROM public.drivers d
               WHERE d.is_online = true
                 AND (d.fcm_token IS NULL OR d.fcm_token = '')
                 AND NOT EXISTS (SELECT 1 FROM public.driver_push_tokens t
                                  WHERE t.user_id::text = d.id::text
                                    AND COALESCE(t.active,true) = true)) x),
    'test_notifications_old_count', (
      SELECT count(*) FROM public.in_app_notifications
       WHERE (title ILIKE '%teste%' OR title ILIKE '%[test]%')
         AND created_at < now() - interval '7 days'),
    'crosstalk_pending_count', (
      SELECT count(*) FROM public.robot_crosstalk
       WHERE direction = 'a_to_b' AND status = 'pending'),
    'crosstalk_topics_7d', COALESCE((
      SELECT jsonb_agg(x) FROM (
        SELECT COALESCE(skill_triggered,'?') AS skill, urgency, count(*) AS n
          FROM public.robot_crosstalk
         WHERE created_at > now() - interval '7 days'
         GROUP BY 1,2 ORDER BY n DESC LIMIT 8) x), '[]'::jsonb),
    'order_cancels_7d', COALESCE((
      SELECT jsonb_agg(x) FROM (
        SELECT COALESCE(NULLIF(trim(cancel_reason),''),
                        COALESCE(cancellation_reason_code::text,'(sem motivo)')) AS reason,
               count(*) AS n
          FROM public.orders
         WHERE status = 'cancelled' AND cancelled_at > now() - interval '7 days'
           AND COALESCE(is_test_order,false) = false
         GROUP BY 1 ORDER BY n DESC LIMIT 8) x), '[]'::jsonb),
    'appointment_noshow_30d', (
      SELECT jsonb_build_object(
        'no_show', count(*) FILTER (WHERE no_show_at IS NOT NULL),
        'total',   count(*))
        FROM public.appointments
       WHERE scheduled_at > now() - interval '30 days'
         AND scheduled_at < now()),
    'security_rls_disabled', COALESCE((
      SELECT jsonb_agg(c.relname) FROM pg_class c
        JOIN pg_namespace n ON n.oid = c.relnamespace
       WHERE n.nspname = 'public' AND c.relkind = 'r'
         AND c.relrowsecurity = false), '[]'::jsonb),
    'security_secdef_mutable_searchpath', COALESCE((
      SELECT jsonb_agg(x.proname) FROM (
        SELECT p.proname FROM pg_proc p
          JOIN pg_namespace n ON n.oid = p.pronamespace
         WHERE n.nspname = 'public' AND p.prosecdef = true
           AND (p.proconfig IS NULL OR NOT EXISTS (
                SELECT 1 FROM unnest(p.proconfig) cfg WHERE cfg LIKE 'search_path=%'))
         ORDER BY p.proname LIMIT 15) x), '[]'::jsonb),
    'slow_queries_top3', COALESCE((
      SELECT jsonb_agg(x) FROM (
        SELECT left(query, 120) AS q, calls, round(mean_exec_time::numeric,1) AS mean_ms
          FROM extensions.pg_stat_statements
         WHERE calls > 50 AND query NOT ILIKE '%pg_%' AND query NOT ILIKE '%cron.%'
         ORDER BY mean_exec_time DESC LIMIT 3) x), '[]'::jsonb),
    'suggestions_open_count', (
      SELECT count(*) FROM public.robot_suggestions WHERE status = 'nova'),
    'observed_at', now()
  ) INTO v;
  RETURN v;
END;
$$;

REVOKE ALL ON FUNCTION public.robot_observe() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.robot_observe() TO service_role;

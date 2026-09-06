-- Watchdog Bora (Parte 3, 2026-07-11): alerta de crashes em tempo real, não só no daily-pulse.
-- Mesmo padrão do red_queue_watermark: SOMENTE agregado (count), sem dados sensíveis/pessoais,
-- executável por anon (o watchdog do host não tem service key, por design).
-- "REAIS de app" = exclui breadcrumbs de debug e ruído de rede/sessão (que não são crashes de facto).
CREATE OR REPLACE FUNCTION public.real_crash_count_24h()
 RETURNS TABLE(real_count integer, total_count integer)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select
    count(*) FILTER (
      WHERE error_message NOT ILIKE '%BREADCRUMB%'
        AND error_message NOT ILIKE '%SocketException%'
        AND error_message NOT ILIKE '%Failed host lookup%'
        AND error_message NOT ILIKE '%ClientException%'
        AND error_message NOT ILIKE '%ExecutionException%'
        AND error_message NOT ILIKE '%firebase_messaging%'
        AND error_message NOT ILIKE '%location service%'
        AND error_message NOT ILIKE '%Refresh Token%'
        AND error_message NOT ILIKE '%AuthApiException%'
    )::int AS real_count,
    count(*)::int AS total_count
  from debug_crash_logs
  where created_at > now() - interval '24 hours';
$function$;

GRANT EXECUTE ON FUNCTION public.real_crash_count_24h() TO anon;

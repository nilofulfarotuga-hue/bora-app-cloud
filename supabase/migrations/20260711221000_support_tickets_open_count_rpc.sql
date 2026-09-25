-- daily-pulse Bora (Parte 5, 2026-07-11): sinal automático de tickets de suporte abertos.
-- Mesmo padrão de agregado-só, anon-safe: NUNCA devolve pergunta/resposta/PII, só contagens.
CREATE OR REPLACE FUNCTION public.support_tickets_open_count()
 RETURNS TABLE(open_count integer, aging_gt_24h integer)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select
    count(*)::int AS open_count,
    count(*) FILTER (WHERE created_at < now() - interval '24 hours')::int AS aging_gt_24h
  from support_tickets
  where status = 'open';
$function$;

GRANT EXECUTE ON FUNCTION public.support_tickets_open_count() TO anon;

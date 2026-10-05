-- Ronda 04/10 Bloco B itens 5 e 8.
-- 5) Fechos sem 1.15 cravado: _fecho_pedidos e admin_monthly_closeout passam a ler a margem
--    nao-parceiro de platform_settings.non_partner_markup_pct (ja existe = 0.15; fallback 0.15).
-- 8) Um so cron a limpar o historico do cron (havia dois: jobid 64 '7 days' e jobid 94 '2 days';
--    fica o 94). Lembretes: _settlement_debt_reminders ja compara com a hora de Lisboa;
--    admin_update_weekly_closeout_settings passa a recusar hora fora de 0..23 e dias fora de 1..7.

CREATE OR REPLACE FUNCTION public._mult_nao_parceiro()
 RETURNS numeric
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  SELECT 1 + COALESCE((SELECT (ps.value #>> '{}')::numeric FROM public.platform_settings ps
                        WHERE ps.key = 'non_partner_markup_pct'), 0.15)
$function$;
REVOKE ALL ON FUNCTION public._mult_nao_parceiro() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public._mult_nao_parceiro() TO authenticated, service_role;

CREATE OR REPLACE FUNCTION pg_temp._ancora(d text, a text, b text) RETURNS text LANGUAGE plpgsql AS $f$
DECLARE n int := (length(d) - length(replace(d, a, ''))) / NULLIF(length(a), 0);
BEGIN
  IF n IS DISTINCT FROM 1 THEN RAISE EXCEPTION 'ancora encontrada % vezes: %', n, left(a, 80); END IF;
  RETURN replace(d, a, b);
END $f$;

DO $patch$
DECLARE d text;
BEGIN
  d := pg_get_functiondef('public._fecho_pedidos(timestamptz,timestamptz)'::regprocedure);
  d := pg_temp._ancora(d, E'round(coalesce(o.subtotal,0) / 1.15, 2)', E'round(coalesce(o.subtotal,0) / public._mult_nao_parceiro(), 2)');
  EXECUTE d;

  d := pg_get_functiondef('public.admin_monthly_closeout(integer,integer)'::regprocedure);
  d := pg_temp._ancora(d, E'round(subtotal / 1.15, 2)', E'round(subtotal / public._mult_nao_parceiro(), 2)');
  EXECUTE d;

  d := pg_get_functiondef('public.admin_update_weekly_closeout_settings(text,boolean,boolean,jsonb,integer,integer,boolean)'::regprocedure);
  d := pg_temp._ancora(d, E'IF NOT public.is_admin() THEN RAISE EXCEPTION ''admin_required''; END IF;\n',
         E'IF NOT public.is_admin() THEN RAISE EXCEPTION ''admin_required''; END IF;\n'
      || E'  -- A hora dos lembretes e hora de LISBOA (o envio compara com now() AT TIME ZONE ''Europe/Lisbon'').\n'
      || E'  IF p_reminder_hour IS NOT NULL AND (p_reminder_hour < 0 OR p_reminder_hour > 23) THEN\n'
      || E'    RAISE EXCEPTION ''hora invalida: % (0 a 23, hora de Lisboa)'', p_reminder_hour;\n'
      || E'  END IF;\n'
      || E'  IF p_reminder_weekdays IS NOT NULL AND (jsonb_typeof(p_reminder_weekdays) <> ''array''\n'
      || E'     OR EXISTS (SELECT 1 FROM jsonb_array_elements(p_reminder_weekdays) x\n'
      || E'                 WHERE jsonb_typeof(x) <> ''number'' OR (x #>> ''{}'')::int NOT BETWEEN 1 AND 7)) THEN\n'
      || E'    RAISE EXCEPTION ''dias invalidos: % (1=segunda ... 7=domingo)'', p_reminder_weekdays;\n'
      || E'  END IF;\n');
  EXECUTE d;
END $patch$;

-- Um so cron a limpar cron.job_run_details (fica 'limpar-historico-cron', 2 dias).
SELECT cron.unschedule(j.jobid) FROM cron.job j WHERE j.jobname = 'purge-cron-job-run-details';

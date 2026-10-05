-- Ronda 04/10 Bloco B item 9: semana de LISBOA nos acertos por pessoa e CSV a serio no servidor.
--
-- a) v_acerto_semanal_unificado cortava a semana com date_trunc('week', week_start_at) em UTC.
--    Um acerto que comeca segunda 00:00 de Lisboa (= domingo 23:00 UTC no verao) aparecia na
--    semana ANTERIOR (ex.: acerto de 28/09 mostrado como "semana de 21/09"). Pior: as Contas
--    claras mandam a segunda de Lisboa a admin_marcar_acerto_pago, que cortava em UTC e nao
--    encontrava nenhuma linha (marcava 0). Passam os dois a cortar a semana em Lisboa.
-- b) admin_weekly_closeout_csv: campos com ';', aspas ou quebra de linha vao entre aspas;
--    datas da semana e do pagamento em hora de Lisboa; valor com virgula decimal.

CREATE OR REPLACE FUNCTION pg_temp._ancora_n(d text, a text, b text, n_esperado int) RETURNS text LANGUAGE plpgsql AS $f$
DECLARE n int := (length(d) - length(replace(d, a, ''))) / NULLIF(length(a), 0);
BEGIN
  IF n IS DISTINCT FROM n_esperado THEN RAISE EXCEPTION 'ancora encontrada % vezes (esperado %): %', n, n_esperado, left(a, 80); END IF;
  RETURN replace(d, a, b);
END $f$;

DO $patch$
DECLARE d text;
BEGIN
  d := pg_get_viewdef('public.v_acerto_semanal_unificado'::regclass);
  d := pg_temp._ancora_n(d, E'(date_trunc(''week''::text, s.week_start_at))::date',
         E'(date_trunc(''week''::text, (s.week_start_at AT TIME ZONE ''Europe/Lisbon''::text)))::date', 3);
  EXECUTE 'CREATE OR REPLACE VIEW public.v_acerto_semanal_unificado AS ' || d;

  d := pg_get_functiondef('public.admin_marcar_acerto_pago(uuid,date,text,text)'::regprocedure);
  d := pg_temp._ancora_n(d, E'date_trunc(''week'', s.week_start_at)::date = p_semana',
         E'date_trunc(''week'', s.week_start_at AT TIME ZONE ''Europe/Lisbon'')::date = p_semana', 3);
  EXECUTE d;
END $patch$;

CREATE OR REPLACE FUNCTION public._csv_campo(p text)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
AS $function$
  SELECT CASE WHEN p IS NULL THEN ''
              WHEN p ~ '[;"\r\n]' THEN '"' || replace(p, '"', '""') || '"'
              ELSE p END
$function$;

CREATE OR REPLACE FUNCTION public.admin_weekly_closeout_csv(p_week_start date DEFAULT NULL::date)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE v_ws date; v_csv text;
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'admin_required'; END IF;
  v_ws := COALESCE(p_week_start, (SELECT max((week_start_at AT TIME ZONE 'Europe/Lisbon')::date) FROM weekly_digest_log));

  SELECT 'semana_inicio;semana_fim;tipo;nome;email;mbway;valor_eur;sentido;estado;pago_em_lisboa;referencia' ||
         COALESCE(string_agg(E'\n' ||
           (w.week_start_at AT TIME ZONE 'Europe/Lisbon')::date || ';' ||
           (w.week_end_at AT TIME ZONE 'Europe/Lisbon')::date || ';' ||
           public._csv_campo(w.subject_type) || ';' || public._csv_campo(w.subject_name) || ';' ||
           public._csv_campo(w.subject_email) || ';' || public._csv_campo(w.subject_phone) || ';' ||
           replace(to_char(abs(w.net_cents)/100.0, 'FM999990.00'), '.', ',') || ';' ||
           CASE w.direction WHEN 'bora_pays' THEN 'a Bora paga'
                            WHEN 'owes_bora' THEN 'deve a Bora' ELSE 'zero' END || ';' ||
           COALESCE(st.status,'pending') || ';' ||
           COALESCE(to_char(st.paid_at AT TIME ZONE 'Europe/Lisbon', 'YYYY-MM-DD HH24:MI'),'') || ';' ||
           public._csv_campo(st.payment_reference)
         , '' ORDER BY abs(w.net_cents) DESC), '')
    INTO v_csv
  FROM weekly_digest_log w
  LEFT JOIN LATERAL (
    SELECT status, paid_at, payment_reference FROM (
      SELECT status, paid_at, payment_reference, 'driver' t, driver_id::text sid, week_start_at FROM driver_weekly_settlements
      UNION ALL SELECT status, paid_at, payment_reference, 'cleaner', cleaner_id::text, week_start_at FROM cleaner_weekly_settlements
      UNION ALL SELECT status, paid_at, payment_reference, 'provider', provider_id::text, week_start_at FROM appointment_payouts
      UNION ALL SELECT status, paid_at, payment_reference, 'partner', partner_id::text, week_start_at FROM partner_weekly_settlements
      UNION ALL SELECT status, paid_at, payment_reference, 'washer', washer_id::text, week_start_at FROM washer_weekly_settlements
    ) s WHERE s.t = w.subject_type AND s.sid = w.subject_id AND s.week_start_at = w.week_start_at
    LIMIT 1
  ) st ON true
  WHERE public._semana_bate(w.week_start_at, v_ws);

  PERFORM public.log_admin_action('export_weekly_closeout_csv', 'weekly_digest', v_ws::text,
    jsonb_build_object('week_start', v_ws));
  RETURN v_csv;
END $function$;

CREATE OR REPLACE FUNCTION public.weekly_closeout_compile(p_week_start date DEFAULT NULL::date)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_ws date;
  v_total int := 0;
  v_summary jsonb;
BEGIN
  v_ws := COALESCE(p_week_start, (
    SELECT max(w) FROM (
      SELECT week_start_at::date w FROM driver_weekly_settlements
      UNION ALL SELECT week_start_at::date FROM cleaner_weekly_settlements
      UNION ALL SELECT week_start_at::date FROM appointment_payouts
      UNION ALL SELECT week_start_at::date FROM partner_weekly_settlements
      UNION ALL SELECT week_start_at::date FROM washer_weekly_settlements
    ) x WHERE w < (date_trunc('week', now() AT TIME ZONE 'Europe/Lisbon'))::date));
  IF v_ws IS NULL THEN
    RETURN jsonb_build_object('ok', true, 'week_start', null, 'total', 0,
      'to_pay', '[]'::jsonb, 'to_receive', '[]'::jsonb, 'zero_count', 0,
      'note', 'sem settlements para compilar');
  END IF;

  -- DRIVERS (euros; net_balance ja vem SIGNED, negativo = deve a Bora)
  INSERT INTO weekly_digest_log AS w
    (week_start_at, week_end_at, subject_type, subject_id, subject_name,
     subject_email, subject_phone, net_cents, direction, breakdown, email_status)
  SELECT s.week_start_at, s.week_end_at, 'driver', s.driver_id::text,
         COALESCE(d.name, 'Estafeta'),
         COALESCE(NULLIF(d.email,''), u.email),
         COALESCE(NULLIF(d.mbway_phone,''), d.phone),
         round(s.net_balance * 100)::int,
         CASE WHEN s.net_balance < 0 THEN 'owes_bora'
              WHEN s.net_balance > 0 THEN 'bora_pays' ELSE 'zero' END,
         jsonb_build_array(
           jsonb_build_object('label','Entregas','qty',COALESCE(s.total_deliveries,0),'value_cents',round(COALESCE(s.total_earnings,0)*100)::int),
           jsonb_build_object('label','Cash recebido de clientes','value_cents',round(COALESCE(s.total_cash_received,0)*100)::int),
           jsonb_build_object('label','Tokens convertidos','value_cents',round(COALESCE(s.tokens_converted_value,0)*100)::int),
           jsonb_build_object('label','Acerto de cash devido','value_cents',round(COALESCE(s.cash_adjustments_due,0)*100)::int)
         ),
         'pending'
  FROM driver_weekly_settlements s
  LEFT JOIN drivers d ON d.id::text = s.driver_id::text OR d.user_id::text = s.driver_id::text
  LEFT JOIN auth.users u ON u.id = d.user_id
  WHERE s.week_start_at::date = v_ws
  ON CONFLICT (week_start_at, subject_type, subject_id) DO UPDATE SET
    net_cents=EXCLUDED.net_cents, direction=EXCLUDED.direction, breakdown=EXCLUDED.breakdown,
    subject_name=EXCLUDED.subject_name, subject_email=EXCLUDED.subject_email,
    subject_phone=EXCLUDED.subject_phone
  WHERE w.email_status IN ('pending','failed','aguarda_dominio');

  -- CLEANERS (cents; net_payout_cents, direcao pelo texto ou sinal)
  INSERT INTO weekly_digest_log AS w
    (week_start_at, week_end_at, subject_type, subject_id, subject_name,
     subject_email, subject_phone, net_cents, direction, breakdown, email_status)
  SELECT s.week_start_at, s.week_end_at, 'cleaner', s.cleaner_id::text,
         COALESCE(c.name,'Profissional de limpeza'),
         COALESCE(NULLIF(c.email,''), u.email),
         COALESCE(NULLIF(c.mbway_phone,''), c.phone),
         CASE WHEN s.direction ILIKE '%pays_bora%' OR s.direction ILIKE '%to_bora%'
              THEN -abs(COALESCE(s.net_payout_cents,0)) ELSE COALESCE(s.net_payout_cents,0) END,
         CASE WHEN s.direction ILIKE '%pays_bora%' OR s.direction ILIKE '%to_bora%' OR COALESCE(s.net_payout_cents,0) < 0 THEN 'owes_bora'
              WHEN COALESCE(s.net_payout_cents,0) > 0 THEN 'bora_pays' ELSE 'zero' END,
         jsonb_build_array(
           jsonb_build_object('label','Limpezas','qty',COALESCE(s.total_jobs,0),'value_cents',COALESCE(s.total_earnings_cents,0)),
           jsonb_build_object('label','Taxa Bora','value_cents',-COALESCE(s.total_bora_fee_cents,0))
         ),
         'pending'
  FROM cleaner_weekly_settlements s
  LEFT JOIN cleaners c ON c.id::text = s.cleaner_id::text OR c.user_id::text = s.cleaner_id::text
  LEFT JOIN auth.users u ON u.id = c.user_id
  WHERE s.week_start_at::date = v_ws
  ON CONFLICT (week_start_at, subject_type, subject_id) DO UPDATE SET
    net_cents=EXCLUDED.net_cents, direction=EXCLUDED.direction, breakdown=EXCLUDED.breakdown,
    subject_name=EXCLUDED.subject_name, subject_email=EXCLUDED.subject_email,
    subject_phone=EXCLUDED.subject_phone
  WHERE w.email_status IN ('pending','failed','aguarda_dominio');

  -- PROVIDERS / servicos (cents; net_payout_cents)
  INSERT INTO weekly_digest_log AS w
    (week_start_at, week_end_at, subject_type, subject_id, subject_name,
     subject_email, subject_phone, net_cents, direction, breakdown, email_status)
  SELECT s.week_start_at, s.week_end_at, 'provider', s.provider_id::text,
         COALESCE(sp.name,'Parceiro de servicos'),
         u.email,
         COALESCE(NULLIF(sp.mbway_phone,''), sp.phone),
         CASE WHEN s.direction ILIKE '%pays_bora%' OR s.direction ILIKE '%to_bora%'
              THEN -abs(COALESCE(s.net_payout_cents,0)) ELSE COALESCE(s.net_payout_cents,0) END,
         CASE WHEN s.direction ILIKE '%pays_bora%' OR s.direction ILIKE '%to_bora%' OR COALESCE(s.net_payout_cents,0) < 0 THEN 'owes_bora'
              WHEN COALESCE(s.net_payout_cents,0) > 0 THEN 'bora_pays' ELSE 'zero' END,
         jsonb_build_array(
           jsonb_build_object('label','Marcacoes','qty',COALESCE(s.total_appointments,0),'value_cents',COALESCE(s.total_service_revenue_cents,0)),
           jsonb_build_object('label','Sinais retidos','value_cents',COALESCE(s.total_deposits_retained_cents,0)),
           jsonb_build_object('label','Taxa Bora','value_cents',-COALESCE(s.bora_booking_fees_cents,0))
         ),
         'pending'
  FROM appointment_payouts s
  LEFT JOIN service_providers sp ON sp.id::text = s.provider_id::text OR sp.user_id::text = s.provider_id::text
  LEFT JOIN auth.users u ON u.id = sp.user_id
  WHERE s.week_start_at::date = v_ws
  ON CONFLICT (week_start_at, subject_type, subject_id) DO UPDATE SET
    net_cents=EXCLUDED.net_cents, direction=EXCLUDED.direction, breakdown=EXCLUDED.breakdown,
    subject_name=EXCLUDED.subject_name, subject_email=EXCLUDED.subject_email,
    subject_phone=EXCLUDED.subject_phone
  WHERE w.email_status IN ('pending','failed','aguarda_dominio');

  -- PARTNERS / restaurantes (euros; net_balance SIGNED)
  INSERT INTO weekly_digest_log AS w
    (week_start_at, week_end_at, subject_type, subject_id, subject_name,
     subject_email, subject_phone, net_cents, direction, breakdown, email_status)
  SELECT s.week_start_at, s.week_end_at, 'partner', s.partner_id::text,
         COALESCE(r.name,'Parceiro'),
         COALESCE(NULLIF(r.email,''), u.email),
         COALESCE(NULLIF(r.mbway_phone,''), r.phone),
         round(COALESCE(s.net_balance,0) * 100)::int,
         CASE WHEN COALESCE(s.net_balance,0) < 0 THEN 'owes_bora'
              WHEN COALESCE(s.net_balance,0) > 0 THEN 'bora_pays' ELSE 'zero' END,
         jsonb_build_array(
           jsonb_build_object('label','Pedidos','qty',COALESCE(s.total_orders,0),'value_cents',round(COALESCE(s.gross_sales,0)*100)::int),
           jsonb_build_object('label','Comissao Bora','value_cents',-round(COALESCE(s.commission_total,0)*100)::int),
           jsonb_build_object('label','Cash retido pelo parceiro','value_cents',round(COALESCE(s.cash_kept_by_partner,0)*100)::int)
         ),
         'pending'
  FROM partner_weekly_settlements s
  LEFT JOIN restaurants r ON r.id::text = s.partner_id::text OR r.user_id::text = s.partner_id::text
  LEFT JOIN auth.users u ON u.id = r.user_id
  WHERE s.week_start_at::date = v_ws
  ON CONFLICT (week_start_at, subject_type, subject_id) DO UPDATE SET
    net_cents=EXCLUDED.net_cents, direction=EXCLUDED.direction, breakdown=EXCLUDED.breakdown,
    subject_name=EXCLUDED.subject_name, subject_email=EXCLUDED.subject_email,
    subject_phone=EXCLUDED.subject_phone
  WHERE w.email_status IN ('pending','failed','aguarda_dominio');

  -- WASHERS / lavagem auto (cents; net_payout_cents) — ACRESCENTADO 2026-09-07.
  INSERT INTO weekly_digest_log AS w
    (week_start_at, week_end_at, subject_type, subject_id, subject_name,
     subject_email, subject_phone, net_cents, direction, breakdown, email_status)
  SELECT s.week_start_at, s.week_end_at, 'washer', s.washer_id::text,
         COALESCE(wa.name,'Profissional de lavagem'),
         COALESCE(NULLIF(wa.email,''), u.email),
         COALESCE(NULLIF(wa.mbway_phone,''), wa.phone),
         CASE WHEN s.direction ILIKE '%pays_bora%' OR s.direction ILIKE '%to_bora%'
              THEN -abs(COALESCE(s.net_payout_cents,0)) ELSE COALESCE(s.net_payout_cents,0) END,
         CASE WHEN s.direction ILIKE '%pays_bora%' OR s.direction ILIKE '%to_bora%' OR COALESCE(s.net_payout_cents,0) < 0 THEN 'owes_bora'
              WHEN COALESCE(s.net_payout_cents,0) > 0 THEN 'bora_pays' ELSE 'zero' END,
         jsonb_build_array(
           jsonb_build_object('label','Lavagens','qty',COALESCE(s.total_jobs,0),'value_cents',COALESCE(s.total_earnings_cents,0)),
           jsonb_build_object('label','Taxa Bora','value_cents',-COALESCE(s.total_bora_fee_cents,0))
         ),
         'pending'
  FROM washer_weekly_settlements s
  LEFT JOIN washers wa ON wa.id::text = s.washer_id::text OR wa.user_id::text = s.washer_id::text
  LEFT JOIN auth.users u ON u.id = wa.user_id
  WHERE s.week_start_at::date = v_ws
  ON CONFLICT (week_start_at, subject_type, subject_id) DO UPDATE SET
    net_cents=EXCLUDED.net_cents, direction=EXCLUDED.direction, breakdown=EXCLUDED.breakdown,
    subject_name=EXCLUDED.subject_name, subject_email=EXCLUDED.subject_email,
    subject_phone=EXCLUDED.subject_phone
  WHERE w.email_status IN ('pending','failed','aguarda_dominio');

  SELECT count(*)::int INTO v_total FROM weekly_digest_log WHERE week_start_at::date = v_ws;

  SELECT jsonb_build_object(
    'ok', true, 'week_start', v_ws,
    'week_end', (SELECT max(week_end_at)::date FROM weekly_digest_log WHERE week_start_at::date = v_ws),
    'total', v_total,
    'to_pay', COALESCE((SELECT jsonb_agg(jsonb_build_object('name',subject_name,'amount_cents',abs(net_cents),'mbway',subject_phone,'type',subject_type) ORDER BY abs(net_cents) DESC)
                        FROM weekly_digest_log WHERE week_start_at::date=v_ws AND direction='bora_pays'), '[]'::jsonb),
    'to_receive', COALESCE((SELECT jsonb_agg(jsonb_build_object('name',subject_name,'amount_cents',abs(net_cents),'mbway',subject_phone,'type',subject_type) ORDER BY abs(net_cents) DESC)
                        FROM weekly_digest_log WHERE week_start_at::date=v_ws AND direction='owes_bora'), '[]'::jsonb),
    'zero_count', (SELECT count(*)::int FROM weekly_digest_log WHERE week_start_at::date=v_ws AND direction='zero')
  ) INTO v_summary;

  RETURN v_summary;
END $function$;;

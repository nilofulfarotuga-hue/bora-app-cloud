-- 05/10 (Danilo autorizou): "marcar pago" comparava week_start_at::date (em UTC = domingo) com a segunda
-- que o painel manda → 0 linhas ou semana errada no verão. Passa a comparar a data em hora de Lisboa,
-- aceitando também a data UTC (compatibilidade). Dados guardados NÃO mudam (regra do 04/10).
create or replace function public._semana_bate(p_week_start_at timestamptz, p_week_start date)
returns boolean language sql immutable as $$
  select (p_week_start_at at time zone 'Europe/Lisbon')::date = p_week_start
      or (p_week_start_at at time zone 'UTC')::date = p_week_start
$$;

CREATE OR REPLACE FUNCTION public.admin_set_settlement_state(p_subject_type text, p_subject_id text, p_week_start date, p_status text DEFAULT NULL::text, p_payment_reference text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  v_dir text;
  v_alvo text;
  v_n int := 0;
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'admin_required'; END IF;

  SELECT w.direction INTO v_dir
    FROM public.weekly_digest_log w
   WHERE w.subject_type = p_subject_type
     AND w.subject_id   = p_subject_id
     AND public._semana_bate(w.week_start_at, p_week_start)
   LIMIT 1;

  IF v_dir IS NULL THEN
    v_dir := CASE p_subject_type
      WHEN 'driver' THEN (SELECT CASE WHEN net_balance < 0 THEN 'owes_bora'
                                      WHEN net_balance > 0 THEN 'bora_pays' ELSE 'zero' END
                            FROM driver_weekly_settlements
                           WHERE driver_id::text = p_subject_id AND public._semana_bate(week_start_at, p_week_start) LIMIT 1)
      WHEN 'partner' THEN (SELECT CASE WHEN net_balance < 0 THEN 'owes_bora'
                                       WHEN net_balance > 0 THEN 'bora_pays' ELSE 'zero' END
                            FROM partner_weekly_settlements
                           WHERE partner_id::text = p_subject_id AND public._semana_bate(week_start_at, p_week_start) LIMIT 1)
      WHEN 'cleaner' THEN (SELECT CASE WHEN net_payout_cents < 0 THEN 'owes_bora'
                                       WHEN net_payout_cents > 0 THEN 'bora_pays' ELSE 'zero' END
                            FROM cleaner_weekly_settlements
                           WHERE cleaner_id::text = p_subject_id AND public._semana_bate(week_start_at, p_week_start) LIMIT 1)
      WHEN 'washer'  THEN (SELECT CASE WHEN net_payout_cents < 0 THEN 'owes_bora'
                                       WHEN net_payout_cents > 0 THEN 'bora_pays' ELSE 'zero' END
                            FROM washer_weekly_settlements
                           WHERE washer_id::text = p_subject_id AND public._semana_bate(week_start_at, p_week_start) LIMIT 1)
      WHEN 'provider' THEN (SELECT CASE WHEN net_payout_cents < 0 THEN 'owes_bora'
                                        WHEN net_payout_cents > 0 THEN 'bora_pays' ELSE 'zero' END
                            FROM appointment_payouts
                           WHERE provider_id::text = p_subject_id AND public._semana_bate(week_start_at, p_week_start) LIMIT 1)
      ELSE NULL END;
  END IF;

  IF v_dir IS NULL THEN
    RAISE EXCEPTION 'acerto nao encontrado para % % na semana %', p_subject_type, p_subject_id, p_week_start;
  END IF;

  v_alvo := COALESCE(NULLIF(p_status,''),
                     CASE v_dir WHEN 'bora_pays' THEN 'paid'
                                WHEN 'owes_bora' THEN 'received'
                                ELSE NULL END);

  IF v_dir = 'zero' THEN
    RETURN jsonb_build_object('ok', true, 'rows', 0, 'nota', 'acerto a zero — nada a marcar');
  END IF;
  IF v_alvo NOT IN ('paid','received') THEN
    RAISE EXCEPTION 'estado invalido: %', v_alvo;
  END IF;
  IF v_dir = 'bora_pays' AND v_alvo <> 'paid' THEN
    RAISE EXCEPTION 'a Bora e que paga este acerto — o estado tem de ser pago';
  END IF;
  IF v_dir = 'owes_bora' AND v_alvo <> 'received' THEN
    RAISE EXCEPTION 'esta pessoa e que paga a Bora — o estado tem de ser recebido';
  END IF;

  IF p_subject_type = 'driver' THEN
    UPDATE driver_weekly_settlements
       SET status=v_alvo, paid_at=now(), paid_by=v_uid,
           payment_reference=COALESCE(p_payment_reference, payment_reference)
     WHERE driver_id::text=p_subject_id AND public._semana_bate(week_start_at, p_week_start);
  ELSIF p_subject_type = 'partner' THEN
    UPDATE partner_weekly_settlements
       SET status=v_alvo, paid_at=now(), paid_by=v_uid,
           payment_reference=COALESCE(p_payment_reference, payment_reference)
     WHERE partner_id::text=p_subject_id AND public._semana_bate(week_start_at, p_week_start);
  ELSIF p_subject_type = 'cleaner' THEN
    UPDATE cleaner_weekly_settlements
       SET status=v_alvo, paid_at=now(), paid_by=v_uid,
           payment_reference=COALESCE(p_payment_reference, payment_reference)
     WHERE cleaner_id::text=p_subject_id AND public._semana_bate(week_start_at, p_week_start);
  ELSIF p_subject_type = 'washer' THEN
    UPDATE washer_weekly_settlements
       SET status=v_alvo, paid_at=now(), paid_by=v_uid,
           payment_reference=COALESCE(p_payment_reference, payment_reference)
     WHERE washer_id::text=p_subject_id AND public._semana_bate(week_start_at, p_week_start);
  ELSIF p_subject_type = 'provider' THEN
    UPDATE appointment_payouts
       SET status=v_alvo, paid_at=now(), paid_by=v_uid,
           payment_reference=COALESCE(p_payment_reference, payment_reference)
     WHERE provider_id::text=p_subject_id AND public._semana_bate(week_start_at, p_week_start);
  ELSE
    RAISE EXCEPTION 'tipo desconhecido: %', p_subject_type;
  END IF;

  GET DIAGNOSTICS v_n = ROW_COUNT;

  PERFORM public.log_admin_action('mark_settlement_' || v_alvo, p_subject_type, p_subject_id,
    jsonb_build_object('week_start', p_week_start, 'rows', v_n,
                       'direction', v_dir, 'reference', p_payment_reference));

  RETURN jsonb_build_object('ok', true, 'rows', v_n, 'status', v_alvo, 'direction', v_dir);
END $function$;

-- BLOCO 2.3 — 2026-09-07
-- "Pago" e "recebido" sao opostos: um e a Bora a pagar, o outro e a pessoa a
-- pagar a Bora. Ate hoje o painel so sabia dizer "pago" para os dois lados, o
-- que fazia o historico mentir sobre quem devia a quem.
--
-- A funcao antiga de tres argumentos MANTEM-SE (a app antiga continua a
-- funcionar) e passa a delegar nesta. Nao se altera valor nenhum: so estado,
-- data, quem marcou e a referencia.

CREATE OR REPLACE FUNCTION public.admin_set_settlement_state(
  p_subject_type text,
  p_subject_id   text,
  p_week_start   date,
  p_status       text DEFAULT NULL,
  p_payment_reference text DEFAULT NULL
)
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

  -- Direcao: primeiro o que foi compilado para a semana; se faltar, o sinal
  -- do valor na propria tabela de origem.
  SELECT w.direction INTO v_dir
    FROM public.weekly_digest_log w
   WHERE w.subject_type = p_subject_type
     AND w.subject_id   = p_subject_id
     AND w.week_start_at::date = p_week_start
   LIMIT 1;

  IF v_dir IS NULL THEN
    v_dir := CASE p_subject_type
      WHEN 'driver' THEN (SELECT CASE WHEN net_balance < 0 THEN 'owes_bora'
                                      WHEN net_balance > 0 THEN 'bora_pays' ELSE 'zero' END
                            FROM driver_weekly_settlements
                           WHERE driver_id::text = p_subject_id AND week_start_at::date = p_week_start LIMIT 1)
      WHEN 'partner' THEN (SELECT CASE WHEN net_balance < 0 THEN 'owes_bora'
                                       WHEN net_balance > 0 THEN 'bora_pays' ELSE 'zero' END
                            FROM partner_weekly_settlements
                           WHERE partner_id::text = p_subject_id AND week_start_at::date = p_week_start LIMIT 1)
      WHEN 'cleaner' THEN (SELECT CASE WHEN net_payout_cents < 0 THEN 'owes_bora'
                                       WHEN net_payout_cents > 0 THEN 'bora_pays' ELSE 'zero' END
                            FROM cleaner_weekly_settlements
                           WHERE cleaner_id::text = p_subject_id AND week_start_at::date = p_week_start LIMIT 1)
      WHEN 'washer'  THEN (SELECT CASE WHEN net_payout_cents < 0 THEN 'owes_bora'
                                       WHEN net_payout_cents > 0 THEN 'bora_pays' ELSE 'zero' END
                            FROM washer_weekly_settlements
                           WHERE washer_id::text = p_subject_id AND week_start_at::date = p_week_start LIMIT 1)
      WHEN 'provider' THEN (SELECT CASE WHEN net_payout_cents < 0 THEN 'owes_bora'
                                        WHEN net_payout_cents > 0 THEN 'bora_pays' ELSE 'zero' END
                            FROM appointment_payouts
                           WHERE provider_id::text = p_subject_id AND week_start_at::date = p_week_start LIMIT 1)
      ELSE NULL END;
  END IF;

  IF v_dir IS NULL THEN
    RAISE EXCEPTION 'acerto nao encontrado para % % na semana %', p_subject_type, p_subject_id, p_week_start;
  END IF;

  -- Estado alvo: o pedido, ou o que a direcao manda.
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
     WHERE driver_id::text=p_subject_id AND week_start_at::date=p_week_start;
  ELSIF p_subject_type = 'partner' THEN
    UPDATE partner_weekly_settlements
       SET status=v_alvo, paid_at=now(), paid_by=v_uid,
           payment_reference=COALESCE(p_payment_reference, payment_reference)
     WHERE partner_id::text=p_subject_id AND week_start_at::date=p_week_start;
  ELSIF p_subject_type = 'cleaner' THEN
    UPDATE cleaner_weekly_settlements
       SET status=v_alvo, paid_at=now(), paid_by=v_uid,
           payment_reference=COALESCE(p_payment_reference, payment_reference)
     WHERE cleaner_id::text=p_subject_id AND week_start_at::date=p_week_start;
  ELSIF p_subject_type = 'washer' THEN
    UPDATE washer_weekly_settlements
       SET status=v_alvo, paid_at=now(), paid_by=v_uid,
           payment_reference=COALESCE(p_payment_reference, payment_reference)
     WHERE washer_id::text=p_subject_id AND week_start_at::date=p_week_start;
  ELSIF p_subject_type = 'provider' THEN
    UPDATE appointment_payouts
       SET status=v_alvo, paid_at=now(), paid_by=v_uid,
           payment_reference=COALESCE(p_payment_reference, payment_reference)
     WHERE provider_id::text=p_subject_id AND week_start_at::date=p_week_start;
  ELSE
    RAISE EXCEPTION 'tipo desconhecido: %', p_subject_type;
  END IF;

  GET DIAGNOSTICS v_n = ROW_COUNT;

  PERFORM public.log_admin_action('mark_settlement_' || v_alvo, p_subject_type, p_subject_id,
    jsonb_build_object('week_start', p_week_start, 'rows', v_n,
                       'direction', v_dir, 'reference', p_payment_reference));

  RETURN jsonb_build_object('ok', true, 'rows', v_n, 'status', v_alvo, 'direction', v_dir);
END $function$;

-- Compatibilidade: a assinatura antiga continua a existir e delega na nova,
-- para que qualquer app ja instalada nao parta.
CREATE OR REPLACE FUNCTION public.admin_mark_settlement_paid(
  p_subject_type text, p_subject_id text, p_week_start date)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
  RETURN public.admin_set_settlement_state(p_subject_type, p_subject_id, p_week_start, NULL, NULL);
END $function$;

-- Desfazer (o Danilo carrega ao lado do certo e tem de poder voltar atras).
CREATE OR REPLACE FUNCTION public.admin_unmark_settlement(
  p_subject_type text, p_subject_id text, p_week_start date)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE v_n int := 0;
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'admin_required'; END IF;

  IF p_subject_type = 'driver' THEN
    UPDATE driver_weekly_settlements SET status='pending', paid_at=NULL, paid_by=NULL
     WHERE driver_id::text=p_subject_id AND week_start_at::date=p_week_start;
  ELSIF p_subject_type = 'partner' THEN
    UPDATE partner_weekly_settlements SET status='pending', paid_at=NULL, paid_by=NULL
     WHERE partner_id::text=p_subject_id AND week_start_at::date=p_week_start;
  ELSIF p_subject_type = 'cleaner' THEN
    UPDATE cleaner_weekly_settlements SET status='pending', paid_at=NULL, paid_by=NULL
     WHERE cleaner_id::text=p_subject_id AND week_start_at::date=p_week_start;
  ELSIF p_subject_type = 'washer' THEN
    UPDATE washer_weekly_settlements SET status='pending', paid_at=NULL, paid_by=NULL
     WHERE washer_id::text=p_subject_id AND week_start_at::date=p_week_start;
  ELSIF p_subject_type = 'provider' THEN
    UPDATE appointment_payouts SET status='pending', paid_at=NULL, paid_by=NULL
     WHERE provider_id::text=p_subject_id AND week_start_at::date=p_week_start;
  ELSE
    RAISE EXCEPTION 'tipo desconhecido: %', p_subject_type;
  END IF;

  GET DIAGNOSTICS v_n = ROW_COUNT;
  PERFORM public.log_admin_action('unmark_settlement', p_subject_type, p_subject_id,
    jsonb_build_object('week_start', p_week_start, 'rows', v_n));
  RETURN jsonb_build_object('ok', true, 'rows', v_n, 'status', 'pending');
END $function$;

REVOKE ALL ON FUNCTION public.admin_set_settlement_state(text,text,date,text,text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.admin_unmark_settlement(text,text,date) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_set_settlement_state(text,text,date,text,text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_unmark_settlement(text,text,date) TO authenticated;;

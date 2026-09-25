-- ============================================================================
-- O DINHEIRO QUE O PRESTADOR JA RECEBEU EM MAO — corrigir o pagar a dobrar
--
-- ⚠️ ISTO MEXE EM DINHEIRO. Autorizado pelo Danilo a 2026-08-29 ("agora
-- corrige"), depois de eu ter levantado o problema e nao lhe ter mexido.
--
-- ── O defeito ──────────────────────────────────────────────────────────────
-- `compute_cleaner_weekly_settlement` fazia `v_net := v_total_earn` — o ganho
-- de TODAS as limpezas concluidas, sem olhar a como foram pagas.
--
-- Quando o cliente paga em DINHEIRO, quem recebe a nota toda na mao e a
-- profissional: fica com o que e dela E com a parte da Bora. Pagar-lhe outra
-- vez o ganho no acerto da semana e paga-lo duas vezes, e ainda por cima a
-- Bora nunca recuperava a sua parte.
--
-- ── A regra correcta, e nao inventa preco nenhum ───────────────────────────
--   liquido = SOMA(ganho dos trabalhos NAO pagos em dinheiro)
--           - SOMA(taxa da Bora dos trabalhos pagos em dinheiro)
--
-- Nenhum valor e calculado aqui: `cleaner_earnings_cents` e `bora_fee_cents`
-- continuam a ser escritos por quem sempre os escreveu. Isto so decide **de
-- que lado da conta** cada um entra.
--
-- ── Seguro fazer agora, e esta provado ─────────────────────────────────────
-- ANTES desta migration, a 2026-08-29:
--   SELECT count(*), sum(bora_fee_cents) FROM cleaning_bookings
--    WHERE payment_method='cash' AND payment_status='cash_pending';  -> 0, 0
--   e o mesmo em carwash_bookings                                    -> 0, 0
-- Nao ha um unico trabalho pago em dinheiro por liquidar, portanto nenhum
-- acerto ja calculado muda de valor. E tambem nao ha nenhuma linha em
-- cleaner_weekly_settlements nem em washer_weekly_settlements.
--
-- ── O buraco maior que apareceu ao lado ────────────────────────────────────
-- Ao procurar a funcao equivalente da lavagem, descobri que **nao existe
-- nenhuma**. A tabela `washer_weekly_settlements` existe, o cron da limpeza
-- existe, e a lavagem nao tem nem funcao nem cron. Ou seja: **uma lavagem
-- feita nunca entrava em acerto nenhum e nunca seria paga.** Fica criada
-- aqui, gemea da da limpeza e ja com a regra do dinheiro em mao de origem.
-- ============================================================================

-- ── 1. LIMPEZA — o dinheiro em mao deixa de ser pago duas vezes ────────────
CREATE OR REPLACE FUNCTION public.compute_cleaner_weekly_settlement(
  p_cleaner_id uuid,
  p_week_start timestamp with time zone DEFAULT NULL,
  p_persist boolean DEFAULT true
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_bounds        RECORD;
  v_anchor        TIMESTAMPTZ := COALESCE(p_week_start, now());
  v_total_jobs    INT := 0;
  v_total_earn    INT := 0;
  v_total_fee     INT := 0;
  v_earn_a_pagar  INT := 0;   -- ganho dos trabalhos que a Bora ainda deve
  v_fee_em_divida INT := 0;   -- taxa da Bora que ficou na mao do prestador
  v_net           INT := 0;
  v_id            UUID;
BEGIN
  IF auth.uid() IS NOT NULL AND NOT public.is_admin() THEN
    RAISE EXCEPTION 'forbidden' USING ERRCODE = '42501';
  END IF;

  SELECT * INTO v_bounds
  FROM public.driver_settlement_week_bounds(v_anchor);

  SELECT
    COUNT(*),
    COALESCE(SUM(cleaner_earnings_cents), 0),
    COALESCE(SUM(bora_fee_cents), 0),
    -- O que a Bora ainda tem de pagar: so os trabalhos em que ela recebeu.
    COALESCE(SUM(cleaner_earnings_cents)
             FILTER (WHERE payment_method IS DISTINCT FROM 'cash'), 0),
    -- O que o prestador ficou a dever: a parte da Bora nos pagos em dinheiro.
    COALESCE(SUM(bora_fee_cents)
             FILTER (WHERE payment_method = 'cash'), 0)
  INTO v_total_jobs, v_total_earn, v_total_fee, v_earn_a_pagar, v_fee_em_divida
  FROM public.cleaning_bookings
  WHERE cleaner_id = p_cleaner_id
    AND status = 'completed'
    AND COALESCE(is_test_order, false) = false
    AND COALESCE(completed_at, scheduled_at) >= v_bounds.week_start
    AND COALESCE(completed_at, scheduled_at) <= v_bounds.week_end;

  -- Era `v_net := v_total_earn`. Pagava as limpezas de dinheiro outra vez.
  v_net := v_earn_a_pagar - v_fee_em_divida;

  IF p_persist THEN
    INSERT INTO public.cleaner_weekly_settlements (
      cleaner_id, week_start_at, week_end_at,
      total_jobs, total_earnings_cents, total_bora_fee_cents,
      net_payout_cents, direction, status
    ) VALUES (
      p_cleaner_id, v_bounds.week_start, v_bounds.week_end,
      v_total_jobs, v_total_earn, v_total_fee,
      v_net,
      CASE WHEN v_net < 0 THEN 'cleaner_to_bora' ELSE 'bora_to_cleaner' END,
      'pending'
    )
    ON CONFLICT (cleaner_id, week_start_at) DO UPDATE SET
      week_end_at          = EXCLUDED.week_end_at,
      total_jobs           = EXCLUDED.total_jobs,
      total_earnings_cents = EXCLUDED.total_earnings_cents,
      total_bora_fee_cents = EXCLUDED.total_bora_fee_cents,
      net_payout_cents     = EXCLUDED.net_payout_cents,
      direction            = EXCLUDED.direction
    RETURNING id INTO v_id;
  END IF;

  RETURN jsonb_build_object(
    'cleaner_id',            p_cleaner_id,
    'week_start',            v_bounds.week_start,
    'week_end',              v_bounds.week_end,
    'total_jobs',            v_total_jobs,
    'total_earnings_cents',  v_total_earn,
    'total_bora_fee_cents',  v_total_fee,
    'earnings_a_pagar_cents', v_earn_a_pagar,
    'fee_em_divida_cents',   v_fee_em_divida,
    'net_payout_cents',      v_net,
    'settlement_id',         v_id,
    'persisted',             p_persist
  );
END;
$function$;


-- ── 2. LAVAGEM — a funcao que nunca existiu ────────────────────────────────
CREATE OR REPLACE FUNCTION public.compute_washer_weekly_settlement(
  p_washer_id uuid,
  p_week_start timestamp with time zone DEFAULT NULL,
  p_persist boolean DEFAULT true
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_bounds        RECORD;
  v_anchor        TIMESTAMPTZ := COALESCE(p_week_start, now());
  v_total_jobs    INT := 0;
  v_total_earn    INT := 0;
  v_total_fee     INT := 0;
  v_earn_a_pagar  INT := 0;
  v_fee_em_divida INT := 0;
  v_net           INT := 0;
  v_id            UUID;
BEGIN
  IF auth.uid() IS NOT NULL AND NOT public.is_admin() THEN
    RAISE EXCEPTION 'forbidden' USING ERRCODE = '42501';
  END IF;

  SELECT * INTO v_bounds
  FROM public.driver_settlement_week_bounds(v_anchor);

  SELECT
    COUNT(*),
    COALESCE(SUM(washer_earnings_cents), 0),
    COALESCE(SUM(bora_fee_cents), 0),
    COALESCE(SUM(washer_earnings_cents)
             FILTER (WHERE payment_method IS DISTINCT FROM 'cash'), 0),
    COALESCE(SUM(bora_fee_cents)
             FILTER (WHERE payment_method = 'cash'), 0)
  INTO v_total_jobs, v_total_earn, v_total_fee, v_earn_a_pagar, v_fee_em_divida
  FROM public.carwash_bookings
  WHERE washer_id = p_washer_id
    AND status = 'completed'
    AND COALESCE(completed_at, scheduled_at) >= v_bounds.week_start
    AND COALESCE(completed_at, scheduled_at) <= v_bounds.week_end;

  v_net := v_earn_a_pagar - v_fee_em_divida;

  IF p_persist THEN
    INSERT INTO public.washer_weekly_settlements (
      washer_id, week_start_at, week_end_at,
      total_jobs, total_earnings_cents, total_bora_fee_cents,
      net_payout_cents, direction, status
    ) VALUES (
      p_washer_id, v_bounds.week_start, v_bounds.week_end,
      v_total_jobs, v_total_earn, v_total_fee,
      v_net,
      CASE WHEN v_net < 0 THEN 'washer_to_bora' ELSE 'bora_to_washer' END,
      'pending'
    )
    ON CONFLICT (washer_id, week_start_at) DO UPDATE SET
      week_end_at          = EXCLUDED.week_end_at,
      total_jobs           = EXCLUDED.total_jobs,
      total_earnings_cents = EXCLUDED.total_earnings_cents,
      total_bora_fee_cents = EXCLUDED.total_bora_fee_cents,
      net_payout_cents     = EXCLUDED.net_payout_cents,
      direction            = EXCLUDED.direction
    RETURNING id INTO v_id;
  END IF;

  RETURN jsonb_build_object(
    'washer_id',             p_washer_id,
    'week_start',            v_bounds.week_start,
    'week_end',              v_bounds.week_end,
    'total_jobs',            v_total_jobs,
    'total_earnings_cents',  v_total_earn,
    'total_bora_fee_cents',  v_total_fee,
    'earnings_a_pagar_cents', v_earn_a_pagar,
    'fee_em_divida_cents',   v_fee_em_divida,
    'net_payout_cents',      v_net,
    'settlement_id',         v_id,
    'persisted',             p_persist
  );
END;
$function$;

CREATE OR REPLACE FUNCTION public.compute_all_washer_weekly_settlements()
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_count  INT := 0;
  v_anchor TIMESTAMPTZ := now() - interval '1 day';
  v_row    RECORD;
BEGIN
  FOR v_row IN
    SELECT DISTINCT cb.washer_id AS id
    FROM public.carwash_bookings cb,
         public.driver_settlement_week_bounds(v_anchor) b
    WHERE cb.status = 'completed'
      AND cb.washer_id IS NOT NULL
      AND COALESCE(cb.completed_at, cb.scheduled_at) >= b.week_start
      AND COALESCE(cb.completed_at, cb.scheduled_at) <= b.week_end
  LOOP
    PERFORM public.compute_washer_weekly_settlement(v_row.id, v_anchor, true);
    v_count := v_count + 1;
  END LOOP;
  RETURN v_count;
END;
$function$;

-- Alguem tem de a chamar. Mesma hora da limpeza — segunda de manha, depois de
-- a semana ter fechado as 00h05.
SELECT cron.unschedule('carwash-weekly-settlement')
  WHERE EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'carwash-weekly-settlement');
SELECT cron.schedule('carwash-weekly-settlement', '0 8 * * 1',
                     'SELECT public.compute_all_washer_weekly_settlements();');

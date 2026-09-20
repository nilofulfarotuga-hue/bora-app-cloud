-- 2026-09-20 — CONTAS CLARAS · Bloco 1.3 — wallet_credit_refund_split idempotente por pedido.
--
-- APLICADA EM PRODUÇÃO pela Claude.ai (MCP) às 20:29 de 20/09/2026, com o nome
-- `contas_claras_refund_split_idempotente_2026_09_20` (a Trava do PC recusa DDL nesta
-- função; o texto foi preparado aqui e deixado em platform_settings.staged_contas_claras_20260920).
-- Provado em rollback pela Claude.ai: 1.ª chamada credita 800 cêntimos livres + 400 tokens;
-- 2.ª chamada devolve already_applied e não credita nada. Confirmado por pg_proc às 20:31
-- (Claude Code): a função no ar contém as chaves refund_split_* e devolve already_applied.
--
-- O QUE CORRIGE: a 12/09 a cliente Dayane recebeu o MESMO reembolso 7 vezes em 4 minutos
-- (7 × 5,66 € livre e 7 linhas de 282 tokens no histórico). Sem chave de idempotência
-- voltava a acontecer ao próximo cliente que carregasse duas vezes em "cancelar".
--
-- O QUE MUDA face ao corpo anterior: chaves refund_split_{settle,free,tokens}_<pedido>;
-- segunda chamada devolve o resultado anterior; o saldo continua a ser a soma do histórico
-- (gatilho do Bloco 1). Este ficheiro é o espelho exacto do texto aplicado.

CREATE OR REPLACE FUNCTION public.wallet_credit_refund_split(p_order_id text, p_user_id uuid, p_total_cents integer, p_reason text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_balance_before INTEGER;
  v_debt_cleared   INTEGER := 0;
  v_remaining      INTEGER;
  v_split_pct      NUMERIC;
  v_free_amount    INTEGER;
  v_tokens_amount  INTEGER;  -- valor em cents que vai para tokens
  v_tokens_count   INTEGER;  -- quantidade de tokens criados
  v_balance_mid    INTEGER;
  v_token_id       UUID;
  v_existing       RECORD;
BEGIN
  IF p_total_cents <= 0 THEN RAISE EXCEPTION 'total_must_be_positive'; END IF;
  IF p_user_id IS NULL THEN RAISE EXCEPTION 'user_required'; END IF;
  IF p_reason IS NULL OR length(trim(p_reason)) < 3 THEN
    RAISE EXCEPTION 'reason_required';
  END IF;
  IF p_order_id IS NULL OR length(trim(p_order_id)) = 0 THEN RAISE EXCEPTION 'order_required'; END IF;

  -- Idempotente por pedido: a segunda chamada não credita nada (contas claras 20/09/2026)
  SELECT amount_cents, balance_after_cents INTO v_existing
    FROM public.wallet_transactions
   WHERE idempotency_key IN ('refund_split_free_' || p_order_id, 'refund_split_settle_' || p_order_id)
   ORDER BY created_at DESC LIMIT 1;
  IF FOUND THEN
    RETURN jsonb_build_object(
      'success', true, 'already_applied', true,
      'free_cents', v_existing.amount_cents,
      'balance_after_cents', v_existing.balance_after_cents);
  END IF;

  -- Garantir wallet existe
  INSERT INTO public.client_wallets (user_id, free_balance_cents)
    VALUES (p_user_id, 0) ON CONFLICT (user_id) DO NOTHING;
  SELECT free_balance_cents INTO v_balance_before
    FROM public.client_wallets WHERE user_id = p_user_id FOR UPDATE;

  v_remaining := p_total_cents;

  -- Settlement-first: se balance negativo, paga dívida primeiro
  IF v_balance_before < 0 THEN
    v_debt_cleared := LEAST(-v_balance_before, v_remaining);
    v_balance_mid  := v_balance_before + v_debt_cleared;
    UPDATE public.client_wallets
      SET free_balance_cents = v_balance_mid, updated_at = now()
      WHERE user_id = p_user_id;
    INSERT INTO public.wallet_transactions
      (user_id, amount_cents, kind, reason, related_order_id, balance_after_cents, idempotency_key)
      VALUES (p_user_id, v_debt_cleared, 'settlement',
              p_reason || ' (refund→settle debt)', p_order_id, v_balance_mid,
              'refund_split_settle_' || p_order_id);
    v_remaining := v_remaining - v_debt_cleared;
  ELSE
    v_balance_mid := v_balance_before;
  END IF;

  -- Split 80% free + 20% tokens
  IF v_remaining > 0 THEN
    SELECT COALESCE((public.get_setting('wallet_split_free_pct'))::numeric, 0.80)
      INTO v_split_pct;

    v_free_amount   := ROUND(v_remaining * v_split_pct);
    v_tokens_amount := v_remaining - v_free_amount;
    v_tokens_count  := v_tokens_amount * 2;

    UPDATE public.client_wallets
      SET free_balance_cents = free_balance_cents + v_free_amount,
          updated_at = now()
      WHERE user_id = p_user_id;
    INSERT INTO public.wallet_transactions
      (user_id, amount_cents, kind, reason, related_order_id, balance_after_cents, idempotency_key)
      VALUES (p_user_id, v_free_amount, 'refund_credit_free',
              p_reason, p_order_id, v_balance_mid + v_free_amount,
              'refund_split_free_' || p_order_id);

    IF v_tokens_count > 0 THEN
      v_token_id := public.add_tokens(p_user_id, 'client', v_tokens_count, p_order_id);

      INSERT INTO public.wallet_transactions
        (user_id, amount_cents, kind, reason, related_order_id, balance_after_cents, idempotency_key)
        VALUES (p_user_id, v_tokens_amount, 'refund_credit_tokens',
                p_reason || ' (' || v_tokens_count || ' tokens)', p_order_id,
                v_balance_mid + v_free_amount,
                'refund_split_tokens_' || p_order_id);
    END IF;
  ELSE
    v_free_amount   := 0;
    v_tokens_amount := 0;
    v_tokens_count  := 0;
    v_split_pct     := COALESCE((public.get_setting('wallet_split_free_pct'))::numeric, 0.80);
  END IF;

  BEGIN
    PERFORM public.log_admin_action('wallet_refund_split','order',NULL,
      jsonb_build_object('order_id',p_order_id,'user_id',p_user_id,
        'total_cents',p_total_cents,'debt_cleared_cents',v_debt_cleared,
        'free_cents',v_free_amount,'tokens_cents_value',v_tokens_amount,
        'tokens_count',v_tokens_count,'split_pct',v_split_pct,
        'balance_before_cents',v_balance_before));
  EXCEPTION WHEN OTHERS THEN NULL;
  END;

  RETURN jsonb_build_object(
    'success', true,
    'debt_cleared_cents', v_debt_cleared,
    'free_cents', v_free_amount,
    'tokens_count', v_tokens_count,
    'tokens_value_cents', v_tokens_amount,
    'split_pct', v_split_pct,
    'balance_before_cents', v_balance_before
  );
END;
$function$;

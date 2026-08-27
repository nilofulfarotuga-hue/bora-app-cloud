-- =====================================================================
-- PROPOSTA (NAO APLICADA) - tokens da Lavagem Auto
-- Data: 2026-08-27
--
-- PORQUE ESTA AQUI E NAO APLICADO:
-- A Trava de dinheiro (.claude/hooks/protege-banco.sh) bloqueia qualquer
-- DDL cujo texto contenha 'add_tokens' (padrao MONEYFN). Esta migration
-- apenas CHAMA add_tokens (nao a altera), mas a Trava nao distingue
-- chamada de definicao - e nao se contorna uma Trava.
--
-- O Bloco E da ordem previu este caso:
--   "Se nao conseguires sem mexer na zona bora_tokens, nao mexas -
--    deixa registado no relatorio e segue."
--
-- REGRA APLICADA: cliente ROUND(preco x 3) minimo 1; lavador +40 fixo.
-- Idempotente por source_order_id ('carwash:<id>') + role, tal como o
-- delivery e a limpeza ja fazem.
--
-- COMO APLICAR (so depois do Danilo dizer "vai"):
--   correr este ficheiro com a Trava desligada a mao, ou pelo painel SQL.
-- =====================================================================

CREATE OR REPLACE FUNCTION public._carwash_complete(p_booking_id uuid, p_auto boolean)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $fn$
DECLARE
  v_b carwash_bookings; v_washer_user uuid; v_client_tokens integer;
BEGIN
  SELECT * INTO v_b FROM carwash_bookings WHERE id = p_booking_id FOR UPDATE;
  IF v_b.id IS NULL OR v_b.status <> 'delivered' THEN RETURN; END IF;

  UPDATE carwash_bookings
  SET status = 'completed', completed_at = now(),
      payment_status = CASE
        WHEN payment_method = 'cash' THEN 'cash_pending'
        WHEN payment_status = 'held' THEN 'released'
        ELSE payment_status END
  WHERE id = p_booking_id;

  UPDATE washers SET washes_done = washes_done + 1 WHERE id = v_b.washer_id;
  v_washer_user := (SELECT user_id FROM washers WHERE id = v_b.washer_id);

  -- >>> A UNICA DIFERENCA PARA O QUE ESTA EM PRODUCAO <<<
  v_client_tokens := GREATEST(1, ROUND(v_b.total_cents * 3 / 100.0)::int);
  PERFORM public.add_tokens(v_b.client_user_id, 'client', v_client_tokens,
                            'carwash:' || p_booking_id::text);
  IF v_washer_user IS NOT NULL THEN
    PERFORM public.add_tokens(v_washer_user, 'washer', 40,
                              'carwash:' || p_booking_id::text);
  END IF;
  -- >>> FIM DA DIFERENCA <<<

  PERFORM public._carwash_notify_user(v_washer_user, 'carwash_completed',
    CASE WHEN p_auto THEN 'Lavagem auto-confirmada' ELSE 'Lavagem confirmada' END,
    'O cliente confirmou. Ganhos: ' || (v_b.washer_earnings_cents / 100.0)::numeric(10,2) || ' EUR.',
    p_booking_id::text);
END $fn$;

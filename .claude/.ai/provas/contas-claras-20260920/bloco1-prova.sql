-- Bloco 1 — provas em rollback (DO ... RAISE EXCEPTION 'RESULT %'), corridas em produção a 20/09/2026.
-- Saídas literais no fim de cada bloco.

-- 1.1 gatilhos: saldo = soma do histórico; balance_after do histórico; sem contagem a dobrar; histórico só acrescenta
DO $$
DECLARE
  v_uid uuid := 'e355fde0-b634-48ba-bce1-e2a4466c4cc2';
  v_saldo_antes integer; v_saldo_1 integer; v_saldo_2 integer; v_saldo_3 integer;
  v_ba_1 integer; v_ba_2 integer; v_ba_3 integer;
  v_upd_bloqueado boolean := false; v_del_bloqueado boolean := false;
BEGIN
  SET CONSTRAINTS ALL IMMEDIATE;
  SELECT free_balance_cents INTO v_saldo_antes FROM public.client_wallets WHERE user_id = v_uid;
  INSERT INTO public.wallet_transactions (user_id, amount_cents, kind, reason, idempotency_key) VALUES (v_uid, 820, 'reimbursement_storeshopping', 'PROVA rollback b1', 'prova_b1_1');
  SELECT free_balance_cents INTO v_saldo_1 FROM public.client_wallets WHERE user_id = v_uid;
  SELECT balance_after_cents INTO v_ba_1 FROM public.wallet_transactions WHERE idempotency_key = 'prova_b1_1';
  INSERT INTO public.wallet_transactions (user_id, amount_cents, kind, reason, idempotency_key) VALUES (v_uid, 141, 'refund_credit_tokens', 'PROVA rollback b1 tokens', 'prova_b1_2');
  SELECT free_balance_cents INTO v_saldo_2 FROM public.client_wallets WHERE user_id = v_uid;
  SELECT balance_after_cents INTO v_ba_2 FROM public.wallet_transactions WHERE idempotency_key = 'prova_b1_2';
  UPDATE public.client_wallets SET free_balance_cents = free_balance_cents - 300 WHERE user_id = v_uid;
  INSERT INTO public.wallet_transactions (user_id, amount_cents, kind, reason, idempotency_key) VALUES (v_uid, -300, 'adjustment', 'PROVA rollback b1 debito', 'prova_b1_3');
  SELECT free_balance_cents INTO v_saldo_3 FROM public.client_wallets WHERE user_id = v_uid;
  SELECT balance_after_cents INTO v_ba_3 FROM public.wallet_transactions WHERE idempotency_key = 'prova_b1_3';
  BEGIN UPDATE public.wallet_transactions SET amount_cents = 1 WHERE idempotency_key = 'prova_b1_3'; EXCEPTION WHEN OTHERS THEN v_upd_bloqueado := true; END;
  BEGIN DELETE FROM public.wallet_transactions WHERE idempotency_key = 'prova_b1_3'; EXCEPTION WHEN OTHERS THEN v_del_bloqueado := true; END;
  RAISE EXCEPTION 'RESULT saldo_antes=% | apos_talao: saldo=% balance_after=% | apos_tokens: saldo=% balance_after=% | apos_debito_com_update_proprio: saldo=% balance_after=% | update_bloqueado=% delete_bloqueado=%',
    v_saldo_antes, v_saldo_1, v_ba_1, v_saldo_2, v_ba_2, v_saldo_3, v_ba_3, v_upd_bloqueado, v_del_bloqueado;
END $$;
-- SAÍDA (19h12 UTC): RESULT saldo_antes=0 | apos_talao: saldo=820 balance_after=820 | apos_tokens: saldo=820 balance_after=820
--   | apos_debito_com_update_proprio: saldo=520 balance_after=520 | update_bloqueado=t delete_bloqueado=t

-- 1.2 os dois caminhos do talão (JWT do admin simulado por set_config; talões sintéticos em pedidos sem talão)
-- SAÍDA (19h19 UTC): RESULT estafeta=4f61dd31-... saldo_antes=<NULL> | A: saldo=1234 linhas_wallet=1 method=wallet
--   | B: saldo=1234 (igual a A) linhas_wallet_ultimo_min=1 method=mbway paid_at=2026-09-20 09:00:00+00
--   | repetir_B_recusado=t erros=[INVALID_STATUS: admin_paid | METHOD_INVALID: cheque (esperado mbway | cash | transfer)]
--   | talao_real_valdemir: method=mbway data=2026-09-19

-- 1.3 estado persistido depois das migrations (SELECT, 19h15 UTC)
-- findings saldo_vs_historico: 1 (Isabel 4abf0e49, +309, não corrigida — caso fechado pelo Danilo)
-- desacertos_agora: 1 (a mesma Isabel) · valdemir_wallet: linha criada a 0 · linhas_prova_ficaram?: 0
-- staged_contas_claras_20260920: category deploys, sql 6118 chars, sha256 1caa26fd13947984…, estado por_aplicar

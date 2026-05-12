-- Relaxar CHECK constraint da coluna free_balance_cents.
-- Pior caso absoluto = -4000 cents (€40, limite hardcoded enforce_cash_payment_limit).
-- Cada RPC valida o SEU limite via setting (wallet_debit_for_order vê -2000; wallet_debit_cancel_fee vê -4000).
ALTER TABLE public.client_wallets
  DROP CONSTRAINT IF EXISTS client_wallets_free_balance_cents_check;

ALTER TABLE public.client_wallets
  ADD CONSTRAINT client_wallets_free_balance_cents_check
  CHECK (free_balance_cents >= -4000);

COMMENT ON COLUMN public.client_wallets.free_balance_cents IS
'Saldo livre em cents. Pode ficar negativo (dívida). 2 hard floors via RPC: ajustes -2000 (wallet_debit_for_order), cancel CASH -4000 (wallet_debit_cancel_fee). CHECK relaxado para -4000 (pior caso).';

-- Adicionar 'cancel_fee_debit' ao CHECK de wallet_transactions.kind.
-- Kinds actuais (11) + novo (1) = 12 total.
ALTER TABLE public.wallet_transactions
  DROP CONSTRAINT IF EXISTS wallet_transactions_kind_check;

ALTER TABLE public.wallet_transactions
  ADD CONSTRAINT wallet_transactions_kind_check
  CHECK (kind IN (
    'refund_credit_free',
    'refund_credit_tokens',
    'order_payment',
    'admin_grant',
    'admin_revoke',
    'cashback',
    'referral',
    'debit',
    'settlement',
    'adjustment',
    'forgive',
    'cancel_fee_debit'
  ));

-- PROMPT 4a (2026-05-12) — coluna nova orders.debt_collected_cents
-- Isolada do final_total. Driver UI em CASH cobra: final_total + debt_collected_cents/100.
-- Populada em create_order quando v_wallet_balance_pre<0 (sempre que há dívida prévia).
ALTER TABLE public.orders
  ADD COLUMN debt_collected_cents integer NOT NULL DEFAULT 0;

COMMENT ON COLUMN public.orders.debt_collected_cents IS
'Cents da dívida prévia da wallet cliente cobrada via este pedido. Populado em create_order quando v_wallet_balance_pre<0. Usado pelo driver UI em CASH: total a cobrar = final_total + debt_collected_cents/100.';

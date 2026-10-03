-- 2026-05-14 — Stripe Customer support
-- Adds public.users.stripe_customer_id (text, UNIQUE partial NULL-safe).
-- Used by create-payment-intent v28+ to attach PaymentIntents to a Stripe Customer
-- (enables saved cards via setup_future_usage='off_session').
-- UNIQUE (parcial WHERE NOT NULL) previne race condition: 2 create-payment-intent
-- em paralelo para o mesmo user nao podem criar 2 Stripe Customers distintos.

ALTER TABLE public.users
  ADD COLUMN IF NOT EXISTS stripe_customer_id text;

CREATE UNIQUE INDEX IF NOT EXISTS users_stripe_customer_id_uniq
  ON public.users (stripe_customer_id)
  WHERE stripe_customer_id IS NOT NULL;

COMMENT ON COLUMN public.users.stripe_customer_id IS
  'Stripe Customer ID — criado na primeira compra com cartao. UNIQUE (parcial NULL-safe) para idempotencia: previne race condition de criar 2 customers para o mesmo user em paralelo.';

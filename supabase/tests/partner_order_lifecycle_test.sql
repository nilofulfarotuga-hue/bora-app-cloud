-- Run against a linked/test project. The transaction is always rolled back.
BEGIN;

DO $$
BEGIN
  IF to_regprocedure('public.partner_mark_ready(text)') IS NULL THEN
    RAISE EXCEPTION 'partner_mark_ready(text) is missing';
  END IF;
  IF to_regprocedure('public.driver_advance_order(text,text)') IS NULL THEN
    RAISE EXCEPTION 'driver_advance_order(text,text) is missing';
  END IF;
  IF to_regclass('public.order_status_events') IS NULL THEN
    RAISE EXCEPTION 'order_status_events is missing';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'orders_status_canonical_check' AND convalidated
  ) THEN
    RAISE EXCEPTION 'canonical status constraint is missing/unvalidated';
  END IF;
END;
$$;

ROLLBACK;

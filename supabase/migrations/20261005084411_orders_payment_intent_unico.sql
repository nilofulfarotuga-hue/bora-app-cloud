-- Ronda 04/10, Bloco A.4 (05/10/2026): um PaymentIntent só pode pertencer a um pedido.
-- Conferido antes de aplicar: 0 payment_intent_id repetidos em orders.
create unique index if not exists uq_orders_payment_intent_id on public.orders (payment_intent_id) where payment_intent_id is not null;

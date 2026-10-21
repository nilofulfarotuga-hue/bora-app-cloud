-- Bloco D · fechar-pendencias-2026-10-20 — forma de pagamento 'premio' nas marcacoes.
-- O vale dos 30 dias paga a limpeza (2 h) ou a lavagem exterior: o cliente nao paga nada
-- e o prestador recebe o ganho normal no acerto (o acerto ja paga tudo o que nao e 'cash').
-- So alarga a lista de valores aceites; nenhuma linha existente muda.
ALTER TABLE public.cleaning_bookings DROP CONSTRAINT IF EXISTS cleaning_bookings_payment_method_check;
ALTER TABLE public.cleaning_bookings ADD CONSTRAINT cleaning_bookings_payment_method_check
  CHECK (payment_method = ANY (ARRAY['card'::text, 'mbway'::text, 'cash'::text, 'premio'::text]));

ALTER TABLE public.carwash_bookings DROP CONSTRAINT IF EXISTS carwash_bookings_payment_method_check;
ALTER TABLE public.carwash_bookings ADD CONSTRAINT carwash_bookings_payment_method_check
  CHECK (payment_method = ANY (ARRAY['card'::text, 'mbway'::text, 'cash'::text, 'premio'::text]));

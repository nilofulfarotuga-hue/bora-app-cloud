-- Reversão do P4 (se vier a ser aplicado).
-- Desligar já: ALTER TABLE public.carwash_bookings DISABLE TRIGGER a00_lavagem_escrita_direta_guarda;
DROP TRIGGER IF EXISTS a00_lavagem_escrita_direta_guarda ON public.carwash_bookings;
DROP FUNCTION IF EXISTS public._lavagem_escrita_direta_guarda();

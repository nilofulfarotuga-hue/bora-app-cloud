-- Reversão do N3b (22/10/2026). Desligar já, sem apagar:
--   ALTER TABLE public.carwash_bookings DISABLE TRIGGER a00_lavagem_escrita_direta_guarda;
--   ALTER TABLE public.orders DISABLE TRIGGER a00_pedido_loja_estafeta_guarda_upd;
--   ALTER TABLE public.orders DISABLE TRIGGER a00_pedido_loja_estafeta_guarda_ins;
-- Tirar de vez:
DROP TRIGGER IF EXISTS a00_lavagem_escrita_direta_guarda ON public.carwash_bookings;
DROP FUNCTION IF EXISTS public._lavagem_escrita_direta_guarda();
DROP TRIGGER IF EXISTS a00_pedido_loja_estafeta_guarda_upd ON public.orders;
DROP TRIGGER IF EXISTS a00_pedido_loja_estafeta_guarda_ins ON public.orders;
DROP FUNCTION IF EXISTS public._pedido_cliente_loja_estafeta_guarda();
DROP FUNCTION IF EXISTS public._pedido_cliente_loja_estafeta_recusa(public.orders, public.orders);

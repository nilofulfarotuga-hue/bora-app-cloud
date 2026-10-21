-- Reversão do R2 (estendido), migração 20261021070735_r2_pedido_cliente_so_o_que_a_app_faz.
-- Desligar já (1 linha, não apaga nada):
--   ALTER TABLE public.orders DISABLE TRIGGER a00_pedido_cliente_guarda;
-- Tirar de vez:
DROP TRIGGER IF EXISTS a00_pedido_cliente_guarda ON public.orders;
DROP FUNCTION IF EXISTS public._pedido_cliente_guarda();
DROP FUNCTION IF EXISTS public._pedido_cliente_recusa(public.orders, public.orders);
DROP FUNCTION IF EXISTS public._pedido_transicao_do_cliente(text, boolean, text, text);

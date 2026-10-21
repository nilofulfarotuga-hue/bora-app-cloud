-- Reversão do R2.
-- Desligar já (1 linha, não apaga nada):
--   ALTER TABLE public.orders DISABLE TRIGGER trg_pedido_estado_cliente_guarda;
-- Tirar de vez:
DROP TRIGGER IF EXISTS trg_pedido_estado_cliente_guarda ON public.orders;
DROP FUNCTION IF EXISTS public._pedido_estado_cliente_guarda();
DROP FUNCTION IF EXISTS public._pedido_estado_cliente_recusa(public.orders, text);
DROP FUNCTION IF EXISTS public._pedido_transicao_do_cliente(text, boolean, text, text);

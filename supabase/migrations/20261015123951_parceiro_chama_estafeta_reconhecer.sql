-- 15/10/2026 — Reconhecer o pedido criado pelo botao "chamar estafeta" do parceiro (regras 2.4.1).
-- Mesma regra da app (OrderModel.isPartnerSelfDispatch). Autorizado pelo Danilo 15/10 13:29.
CREATE OR REPLACE FUNCTION public.pedido_parceiro_chamou(p_is_partner boolean, p_order_type text, p_user_id uuid)
RETURNS boolean
LANGUAGE sql IMMUTABLE
SET search_path TO 'public'
AS $f$
  SELECT COALESCE(p_is_partner, false)
     AND p_order_type = 'partnerRestaurant'
     AND p_user_id IS NULL;
$f$;

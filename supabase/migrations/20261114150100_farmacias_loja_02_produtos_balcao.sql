-- Aplicado pela Claude.ai a 14/11/2026 (AUTORIZO do Danilo 13/11 e 14/11 11:44/11:48). Fonte: .claude/.ai/missoes/farmacias-loja-2026-11-14/bloco1-proposta-dinheiro.md
-- Cópia de segurança das 1378 linhas antes de mexer (RLS ligada, sem políticas: só service role lê).
CREATE TABLE IF NOT EXISTS public.bkp_products_farmacias_20261114 AS
  SELECT * FROM public.products
   WHERE restaurant_id IN ('farmacia-se-guarda', 'farmacia-teixeira-guarda');
ALTER TABLE public.bkp_products_farmacias_20261114 ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.bkp_products_farmacias_20261114 FROM anon, authenticated;

-- O preço da app já é o da Glovo; o preço de balcão passa a ser o mesmo (a farmácia recebe 100 %).
UPDATE public.products
   SET partner_shelf_price = price
 WHERE restaurant_id IN ('farmacia-se-guarda', 'farmacia-teixeira-guarda')
   AND partner_shelf_price IS DISTINCT FROM price;

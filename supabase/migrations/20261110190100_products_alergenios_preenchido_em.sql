-- ═══════════════════════════════════════════════════════════════════════════
-- Missão fechar-tudo-2026-11-10 · Bloco E6 · Alergénios — quando foram preenchidos.
--
-- Reg. (UE) 1169/2011, art. 14.º e 44.º; DL 26/2016. Os 14 alergénios por
-- prato JÁ têm coluna: `products.allergens` (text[], migração B6 de
-- 2026-06-12), preenchida pelo parceiro (Adicionar/editar produto) e pelo
-- painel ("Alergênicos"). Não se cria outra coluna para o mesmo dado (regra
-- dos gémeos). Falta saber DESDE QUANDO a informação está lá — é a prova que a
-- advogada pede e o que o painel conta.
--
--   products.alergenios_preenchido_em — carimbo do servidor: quando a lista
--   passou a ter pelo menos um alergénio. Volta a NULL se a lista ficar vazia.
--
-- Escreve-o um gatilho (BEFORE INSERT / UPDATE OF allergens), nunca a app:
-- assim nenhuma versão da app parte se esta migração ainda não estiver
-- aplicada, e o parceiro e o admin carimbam pelo mesmo caminho.
-- Lista vazia continua a significar "por preencher" (a app do cliente mostra
-- "Alergénios: contacta a loja antes de pagar").
-- ═══════════════════════════════════════════════════════════════════════════

ALTER TABLE public.products
  ADD COLUMN IF NOT EXISTS alergenios_preenchido_em timestamptz;

COMMENT ON COLUMN public.products.alergenios_preenchido_em IS
  'E6 fechar-tudo-2026-11-10: quando products.allergens passou a ter pelo menos um dos 14 '
  'alergénios (Reg. UE 1169/2011). Carimbado por gatilho; NULL = por preencher.';

CREATE OR REPLACE FUNCTION public._products_alergenios_carimbo()
RETURNS trigger
LANGUAGE plpgsql
SET search_path TO 'public'
AS $$
BEGIN
  IF coalesce(cardinality(NEW.allergens), 0) = 0 THEN
    NEW.alergenios_preenchido_em := NULL;
  ELSIF TG_OP = 'INSERT'
     OR NEW.allergens IS DISTINCT FROM OLD.allergens
     OR NEW.alergenios_preenchido_em IS NULL THEN
    NEW.alergenios_preenchido_em := now();
  END IF;
  RETURN NEW;
END $$;

REVOKE ALL ON FUNCTION public._products_alergenios_carimbo() FROM public, anon, authenticated;

DROP TRIGGER IF EXISTS trg_products_alergenios_carimbo ON public.products;
CREATE TRIGGER trg_products_alergenios_carimbo
  BEFORE INSERT OR UPDATE OF allergens ON public.products
  FOR EACH ROW EXECUTE FUNCTION public._products_alergenios_carimbo();

-- Os que já têm alergénios (a 08/11 era 1 prato) ficam com a hora desta
-- migração: não se sabe quando foram preenchidos, sabe-se que já estavam.
UPDATE public.products
   SET alergenios_preenchido_em = now()
 WHERE coalesce(cardinality(allergens), 0) > 0
   AND alergenios_preenchido_em IS NULL;

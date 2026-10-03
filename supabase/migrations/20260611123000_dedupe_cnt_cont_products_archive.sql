-- T2 (2026-06-11): dedupe catálogo Continente — 383 produtos cnt-XXXXX que têm
-- duplicado cont-XXXXX (os cont- têm nomes corretos e preços mais atuais →
-- ficam). Os cnt- com par são ARQUIVADOS em _backup_products_cnt_duplicates_20260611
-- e só depois apagados de products. NOTA (desvio vs diagnóstico): existem 1317
-- cnt- no total; 934 NÃO têm par cont- (produtos únicos) e são MANTIDOS.
-- Pedidos: só 80ba3a2e referencia um cnt- com par (cnt-4603911 → cont-4603911);
-- o pedido 8c0649bb referencia cnt-6403161 que NÃO tem par → fica intacto.
-- Transação única: qualquer assert falhado faz rollback de tudo.
-- Aplicada em prod via MCP apply_migration ("dedupe_cnt_cont_products_archive").
-- Verificação pós-aplicação: cnt_com_par=0, backup=383, cont- intactos=10950,
-- pedido 80ba3a2e ref_antiga=0/ref_corrigida=1. Restam 934 cnt- únicos (sem par).

-- 1) Backup dos 383 (exatamente os que vão ser apagados)
CREATE TABLE public._backup_products_cnt_duplicates_20260611 AS
SELECT c.*
FROM public.products c
WHERE c.id LIKE 'cnt-%'
  AND EXISTS (SELECT 1 FROM public.products k
              WHERE k.id = 'cont-' || substring(c.id FROM 5));

ALTER TABLE public._backup_products_cnt_duplicates_20260611 ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public._backup_products_cnt_duplicates_20260611 FROM anon, authenticated;

DO $$
DECLARE n int;
BEGIN
  SELECT COUNT(*) INTO n FROM public._backup_products_cnt_duplicates_20260611;
  IF n <> 383 THEN
    RAISE EXCEPTION 'T2_ABORT: backup tem % linhas, esperado 383', n;
  END IF;
END $$;

-- 2) Corrigir o único pedido que referencia um cnt- com par
UPDATE public.orders
SET items = (
  SELECT jsonb_agg(
    CASE WHEN e->>'productId' = 'cnt-4603911'
         THEN jsonb_set(e, '{productId}', '"cont-4603911"')
         ELSE e END)
  FROM jsonb_array_elements(items) e
)
WHERE id = '80ba3a2e-8259-4333-914e-ebee01cdd37d';

DO $$
DECLARE n int;
BEGIN
  SELECT COUNT(*) INTO n FROM public.orders
  WHERE id = '80ba3a2e-8259-4333-914e-ebee01cdd37d'
    AND items::text LIKE '%cnt-4603911%';
  IF n <> 0 THEN
    RAISE EXCEPTION 'T2_ABORT: pedido 80ba3a2e ainda referencia cnt-4603911';
  END IF;
END $$;

-- 3) Apagar exatamente os produtos arquivados no backup
DELETE FROM public.products p
USING public._backup_products_cnt_duplicates_20260611 b
WHERE p.id = b.id;

-- 4) Asserts finais
DO $$
DECLARE n_pares int; n_cont int;
BEGIN
  SELECT COUNT(*) INTO n_pares FROM public.products c
  WHERE c.id LIKE 'cnt-%'
    AND EXISTS (SELECT 1 FROM public.products k
                WHERE k.id = 'cont-' || substring(c.id FROM 5));
  IF n_pares <> 0 THEN
    RAISE EXCEPTION 'T2_ABORT: ainda existem % cnt- com par cont-', n_pares;
  END IF;

  SELECT COUNT(*) INTO n_cont FROM public.products k
  WHERE k.id LIKE 'cont-%'
    AND EXISTS (SELECT 1 FROM public._backup_products_cnt_duplicates_20260611 b
                WHERE k.id = 'cont-' || substring(b.id FROM 5));
  IF n_cont <> 383 THEN
    RAISE EXCEPTION 'T2_ABORT: esperados 383 cont- correspondentes intactos, encontrados %', n_cont;
  END IF;
END $$;

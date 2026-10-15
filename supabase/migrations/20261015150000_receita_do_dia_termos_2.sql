-- Receita do Dia — segunda afinação de termos (15/10/2026, mesma missão).
-- A re-verificação de contexto limpo cotou as 14 receitas nos 4 supermercados:
-- 13 certas. "carne picada de vaca" dava aves/peru/porco; o catálogo chama-lhe
-- "Carne Picada de Bovino" (Auchan e Continente; Intermarché e Pingo Doce só
-- têm de aves/peru, que o cliente vê na lista antes de confirmar).
-- "farinha de trigo" dava integral → "farinha de trigo t65"; "açúcar branco"
-- dava açúcar de cervejeiro no Intermarché → "açúcar granulado".

UPDATE public.receitas_do_dia
   SET ingredientes = replace(replace(replace(ingredientes::text,
         '"pesquisa": "carne picada de vaca"', '"pesquisa": "carne picada de bovino"'),
         '"pesquisa": "farinha de trigo"', '"pesquisa": "farinha de trigo t65"'),
         '"pesquisa": "açúcar branco"', '"pesquisa": "açúcar granulado"')::jsonb
 WHERE ingredientes::text LIKE ANY (ARRAY[
         '%"pesquisa": "carne picada de vaca"%',
         '%"pesquisa": "farinha de trigo"%',
         '%"pesquisa": "açúcar branco"%']);

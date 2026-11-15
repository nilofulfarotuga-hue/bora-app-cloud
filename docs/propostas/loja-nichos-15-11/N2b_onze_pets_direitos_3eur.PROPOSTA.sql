-- PROPOSTA (loja-nichos-15-11, N2b). ZONA DE PRECOS: quem aplica e a Claude.ai, so com a regra aprovada.
-- Regra da caixa 90 (Claude.ai 19:10, pesquisa de 15/11): "preco = 2x custo (regra aprovada) contando os
-- 3 EUR quando vier da China" - desde 01/07/2026 tudo o que entra de fora da UE paga 3 EUR de direitos por
-- tipo de produto. Os 11 produtos de 15/11 (caixa 77, ja no ar so para as contas do Danilo) foram calculados
-- SEM esses 3 EUR e todos saem do armazem da CJ na China. Esta proposta soma 300 cents ao custo e
-- recalcula o preco = 2 x custo (+6,00 EUR no preco de cada um). Nenhum foi vendido ainda
-- (0 encomendas pagas a 15/11 ~20:50). So muda uma linha se o custo ainda for o ORIGINAL (nao soma duas vezes).
update public.loja_online_produtos p
   set custo_fornecedor_cents = v.custo + 300,
       preco_bora_cents       = 2 * (v.custo + 300),
       atualizado_em          = now()
  from (values
    ('cj:2503191148021601200', 475), ('cj:4D6E5E7A-85A5-4F26-955F-C91C69F19561', 510),
    ('cj:1402533508353757184', 669), ('cj:2E961E18-A6DD-44AC-A9B4-37795039890F', 712),
    ('cj:1836302458034212864', 734), ('cj:C6DD91F5-4F23-4D6D-9EB4-0A5F88D484A1', 825),
    ('cj:1653041912300969984', 902), ('cj:6AEB0AAE-3E70-4EAE-857B-B83389786B3A:S', 928),
    ('cj:1595721401296760832', 946), ('cj:1644945472383094784', 1034),
    ('cj:6AEB0AAE-3E70-4EAE-857B-B83389786B3A:L', 1102)
  ) as v(spid, custo)
 where p.shopify_product_id = v.spid
   and p.custo_fornecedor_cents = v.custo;
-- Prova: select titulo, custo_fornecedor_cents, preco_bora_cents from public.loja_online_produtos
--          where shopify_product_id like 'cj:%' order by preco_bora_cents;
-- Esperado: luva 775/1550 ... copo grande 1402/2804; correr 2 vezes nao muda nada a segunda.

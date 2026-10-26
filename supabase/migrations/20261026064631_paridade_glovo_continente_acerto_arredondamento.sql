-- 26/10/2026: acerto da migração 20261026064246 (Continente = Glovo, só subir).
-- A fórmula do ±0,01 (a mesma de 20261023223000) deixou 118 produtos com o cliente a ver
-- 1 cêntimo ACIMA do Glovo (ex.: base 1,04 → 1,20 € com o Glovo a 1,19 €): fura a regra
-- "nunca mais caro que o Glovo". Aqui: o maior preço base cujo preço ao cliente não passa
-- o do Glovo; se esse já não for maior do que o preço antigo, volta o preço antigo.
-- Nunca fica abaixo do preço que havia antes da migração (bkp_precos_glovo_continente_20261026).
with g as (
  select external_id, preco_glovo glovo from public.glovo_precos_continente
   where capturado_em = (select max(capturado_em) from public.glovo_precos_continente)
),
acima as (
  select p.id, p.price atual, b.price antigo, g.glovo
    from public.bkp_precos_glovo_continente_20261026 b
    join public.products p on p.id = b.id
    join g on p.id in ('cnt-' || g.external_id, 'cont-' || g.external_id)
   where round(p.price*1.15, 2) > g.glovo
),
certo as (
  select id, antigo,
         case when round((atual - 0.01)*1.15, 2) <= glovo and atual - 0.01 > antigo
              then atual - 0.01 else antigo end novo
    from acima
)
update public.products p set price = c.novo
  from certo c
 where p.id = c.id;

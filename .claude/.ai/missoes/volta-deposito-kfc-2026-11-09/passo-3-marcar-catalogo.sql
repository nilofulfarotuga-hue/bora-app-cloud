-- PARTE 3 de 3 — marcar o catálogo com o depósito Volta (missão volta-deposito-kfc-2026-11-09).
-- Correr SÓ DEPOIS da PARTE 2 (a cobrança) estar aplicada: antes disso a app nova mostrava
-- "+0,10 € depósito" sem o servidor o cobrar.
-- Regras: public.volta_classificar (PARTE 1). "marcar" → deposit_units; "duvidoso" → 0 e lista
-- "rever" do painel; o que o admin ou o talão já marcaram (deposit_origem admin/talao) não se toca.
-- Previsão pelo catálogo de 09/11/2026 21:03 (classificado no PGlite com a mesma função):
-- ver relatorio-catalogo.md.

create table if not exists public.bkp_volta_marcacao_20261109 as
  select 'produto'::text as tipo, id, deposit_units, deposit_review, deposit_origem, now() as em
    from public.products where deposit_units <> 0 or deposit_review
  union all
  select 'opcao', id, deposit_units, deposit_review, deposit_origem, now()
    from public.product_option_items where deposit_units <> 0 or deposit_review;
alter table public.bkp_volta_marcacao_20261109 enable row level security;

with c as (
  select p.id, public.volta_classificar(p.name, p.category, p.restaurant_id) as cls
    from public.products p
   where coalesce(p.deposit_origem, '') not in ('admin', 'talao')
)
update public.products p
   set deposit_units  = case when c.cls->>'estado' = 'marcar' then (c.cls->>'units')::int else 0 end,
       deposit_review = (c.cls->>'estado' = 'duvidoso'),
       deposit_origem = case when c.cls->>'estado' in ('marcar', 'duvidoso') then 'regra' else p.deposit_origem end
  from c
 where c.id = p.id
   and (p.deposit_units is distinct from case when c.cls->>'estado' = 'marcar' then (c.cls->>'units')::int else 0 end
        or p.deposit_review is distinct from (c.cls->>'estado' = 'duvidoso'));

with c as (
  select poi.id, public.volta_classificar(poi.name, pog.name, p.restaurant_id) as cls
    from public.product_option_items poi
    join public.product_option_groups pog on pog.id = poi.group_id
    join public.products p on p.id = pog.product_id
   where coalesce(poi.deposit_origem, '') not in ('admin', 'talao')
)
update public.product_option_items poi
   set deposit_units  = case when c.cls->>'estado' = 'marcar' then (c.cls->>'units')::int else 0 end,
       deposit_review = (c.cls->>'estado' = 'duvidoso'),
       deposit_origem = case when c.cls->>'estado' in ('marcar', 'duvidoso') then 'regra' else poi.deposit_origem end
  from c
 where c.id = poi.id
   and (poi.deposit_units is distinct from case when c.cls->>'estado' = 'marcar' then (c.cls->>'units')::int else 0 end
        or poi.deposit_review is distinct from (c.cls->>'estado' = 'duvidoso'));

-- Prova (SELECT): por loja, marcados / embalagens / rever.
select coalesce(r.name, p.restaurant_id) as loja,
       count(*) filter (where p.deposit_units > 0) as marcados,
       sum(p.deposit_units) as embalagens,
       count(*) filter (where p.deposit_review) as rever
  from public.products p left join public.restaurants r on r.id::text = p.restaurant_id::text
 where coalesce(p.is_available, true) and (p.deposit_units > 0 or p.deposit_review)
 group by 1 order by 2 desc;

-- 26/10/2026: paridade de preço com o Glovo da Guarda — CONTINENTE (missão geral-sabado-24-10, bloco 5).
-- Ordem do Danilo de 23/10/2026 ("igualar o Glovo só a subir", mesma decisão do McDonald's e BK,
-- migração 20261023223000): SÓ SUBIR, nunca baixar; fotos não se tocam.
-- products.price é a base sem a margem de 15% (platform_settings.non_partner_markup_pct = 0.15);
-- o cliente vê round(base*1.15, 2).
-- Preços do Glovo: tabela glovo_precos_continente (robô do PC, API pública do Glovo, 26/10 05:11Z,
-- 3714 produtos). Ligação pelo código do Continente: products.id = 'cnt-<código>' ou 'cont-<código>'.
-- Fora (para rever): diferença acima de 50% (pode ser embalagem diferente).
create table if not exists public.bkp_precos_glovo_continente_20261026 as
  select id, restaurant_id, name, price, now() as backup_at from public.products where false;
alter table public.bkp_precos_glovo_continente_20261026 enable row level security;
revoke all on public.bkp_precos_glovo_continente_20261026 from public, anon, authenticated;

with g as (
  select external_id, preco_glovo glovo from public.glovo_precos_continente
   where capturado_em = (select max(capturado_em) from public.glovo_precos_continente)
),
alvo as (
  select p.id, p.restaurant_id, p.name, p.price, g.glovo, round(g.glovo/1.15, 2) b
    from public.products p
    join g on p.id in ('cnt-' || g.external_id, 'cont-' || g.external_id)
   where p.restaurant_id = 'continente-guarda'
     and round(p.price*1.15, 2) < g.glovo
     and g.glovo / nullif(round(p.price*1.15, 2), 0) <= 1.5
),
nova as (
  select *, case when round(b*1.15, 2) < glovo then b + 0.01
                 when round(b*1.15, 2) > glovo then b - 0.01 else b end nb
    from alvo
),
bk as (
  insert into public.bkp_precos_glovo_continente_20261026 (id, restaurant_id, name, price, backup_at)
  select id, restaurant_id, name, price, now() from nova where nb > price returning 1
)
update public.products p set price = n.nb
  from nova n
 where p.id = n.id and n.nb > p.price;

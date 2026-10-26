-- 26/10/2026 (geral-sabado-24-10, bloco 5): McDonald's — o que já não existe no Glovo da Guarda sai
-- do catálogo (regra de 24/09: DESATIVAR, nunca apagar) + acerto de 1 cêntimo da paridade de 23/10.
-- Lista do Glovo = a da migração 20261023223000, posta em glovo_precos_restaurantes (23/10).
-- Comparação pelo nome normalizado (igual à de 23/10). Cópia antes em bkp_mcd_fora_glovo_20261026.
create table if not exists public.bkp_mcd_fora_glovo_20261026 as
  select id, restaurant_id, name, price, is_available, removal_reason, now() as backup_at
    from public.products where false;
alter table public.bkp_mcd_fora_glovo_20261026 enable row level security;
revoke all on public.bkp_mcd_fora_glovo_20261026 from public, anon, authenticated;

with g as (
  select loja, lower(regexp_replace(trim(nome), '\s+', ' ', 'g')) n, preco_glovo
    from public.glovo_precos_restaurantes where capturado_em = '2026-10-23'
),
fora as (
  select p.id from public.products p
   where p.restaurant_id = 'mcdonalds-guarda' and p.is_available
     and not exists (select 1 from g where g.loja = p.restaurant_id
                       and g.n = lower(regexp_replace(trim(p.name), '\s+', ' ', 'g')))
),
bk as (
  insert into public.bkp_mcd_fora_glovo_20261026 (id, restaurant_id, name, price, is_available, removal_reason, backup_at)
  select p.id, p.restaurant_id, p.name, p.price, p.is_available, p.removal_reason, now()
    from public.products p join fora f on f.id = p.id returning 1
)
update public.products p
   set is_available = false,
       removal_reason = 'Ja nao existe no Glovo da Guarda (lista de 23/10) - desativado a 26/10, regra de 24/09'
  from fora f where p.id = f.id;

-- Acerto da paridade de 23/10 (McDonald's/BK): a fórmula do ±0,01 deixou o cliente 1 cêntimo
-- acima do Glovo; fica o maior preço base que não passa o Glovo, nunca abaixo do preço antigo.
with g as (
  select loja, lower(regexp_replace(trim(nome), '\s+', ' ', 'g')) n, preco_glovo glovo
    from public.glovo_precos_restaurantes where capturado_em = '2026-10-23'
),
acima as (
  select p.id, p.price atual, b.price antigo, g.glovo
    from public.bkp_precos_glovo_20261023 b
    join public.products p on p.id = b.id
    join g on g.loja = p.restaurant_id and g.n = lower(regexp_replace(trim(p.name), '\s+', ' ', 'g'))
   where round(p.price*1.15, 2) > g.glovo
)
update public.products p
   set price = case when round((a.atual - 0.01)*1.15, 2) <= a.glovo and a.atual - 0.01 > a.antigo
                    then a.atual - 0.01 else a.antigo end
  from acima a where p.id = a.id;

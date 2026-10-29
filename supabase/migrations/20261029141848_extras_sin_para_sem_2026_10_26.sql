create table if not exists public.bkp_product_option_items_sin_20261026 as
  select id, name, now() as copiado_em
  from public.product_option_items
  where name ~ '^SIN ';
alter table public.bkp_product_option_items_sin_20261026 enable row level security;
revoke all on public.bkp_product_option_items_sin_20261026 from anon, authenticated;
update public.product_option_items
set name = 'Sem ' || substring(name from 5)
where name ~ '^SIN ';

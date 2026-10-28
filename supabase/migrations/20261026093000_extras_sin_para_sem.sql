-- 20261026093000_extras_sin_para_sem.sql
-- Missão melhorias-paridade-2026-10-26, item 12 — 491 extras do Burger King começam por "SIN"
-- (espanhol, vindo da fonte do catálogo): "SIN Cebola", "SIN Ketchup"… Passam a "Sem Cebola".
--
-- SÓ TEXTO: muda product_option_items.name. Não toca em price_add, is_available, sort_order,
-- nem em pedidos já feitos. Cópia ANTES do UPDATE (regra bkp_<nome>_AAAAMMDD), e o UPDATE só
-- apanha nomes que começam exactamente por "SIN " — correr outra vez não muda nada.
--
-- REVERTER:
--   update public.product_option_items i set name = b.name
--   from public.bkp_product_option_items_sin_20261026 b where b.id = i.id;

create table if not exists public.bkp_product_option_items_sin_20261026 as
  select id, name, now() as copiado_em
  from public.product_option_items
  where name ~ '^SIN ';

-- A cópia é só para o servidor/admin: fechada à API.
alter table public.bkp_product_option_items_sin_20261026 enable row level security;
revoke all on public.bkp_product_option_items_sin_20261026 from anon, authenticated;

update public.product_option_items
set name = 'Sem ' || substring(name from 5)
where name ~ '^SIN ';

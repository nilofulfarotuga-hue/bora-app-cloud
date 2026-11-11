-- =============================================================================
-- farmacias-2026-11-11 · 02 · Colunas novas, definições e modo demonstração
-- Depende da 01 (restaurants.so_lista_permissao, loja_lista_permissao).
-- =============================================================================

-- ---- Colunas -----------------------------------------------------------------
alter table public.products
  add column if not exists is_medicine boolean,
  add column if not exists preco_provisorio boolean not null default false;
comment on column public.products.is_medicine is
  'Farmácias: true = medicamento (não sujeito a receita), false = parafarmácia; null = não se aplica.';
comment on column public.products.preco_provisorio is
  'Preço provisório (ex.: preço da Glovo enquanto a loja não manda o preço de balcão). Trocar quando chegar o balcão.';

alter table public.restaurants
  add column if not exists pharmacy_prescription_mode text not null default 'desligado',
  add column if not exists partner_extra_commission_pct numeric,
  add column if not exists partner_extra_commission_starts_at timestamptz,
  add column if not exists aberta_ao_publico_em timestamptz;

do $$ begin
  if not exists (select 1 from pg_constraint where conname = 'restaurants_pharmacy_prescription_mode_chk') then
    alter table public.restaurants add constraint restaurants_pharmacy_prescription_mode_chk
      check (pharmacy_prescription_mode in ('desligado', 'so_lista', 'publico'));
  end if;
  if not exists (select 1 from pg_constraint where conname = 'restaurants_partner_extra_commission_pct_chk') then
    alter table public.restaurants add constraint restaurants_partner_extra_commission_pct_chk
      check (partner_extra_commission_pct is null or (partner_extra_commission_pct >= 0 and partner_extra_commission_pct <= 0.5));
  end if;
end $$;

comment on column public.restaurants.pharmacy_prescription_mode is
  'Receita e botões da farmácia: desligado | so_lista (só lista de permissão/admin/dono) | publico. Só o Danilo liga ao público.';
comment on column public.restaurants.partner_extra_commission_pct is
  'Comissão extra que a loja paga sobre o que vende (ex.: 0.10). Null = nenhuma. Só conta a partir de partner_extra_commission_starts_at.';
comment on column public.restaurants.partner_extra_commission_starts_at is
  'Data a partir da qual a comissão extra conta (abertura + N meses). Null = ainda não conta.';
comment on column public.restaurants.aberta_ao_publico_em is 'Quando a loja escondida foi aberta ao público (admin_farmacia_abrir).';

-- Os campos de dinheiro e de visibilidade só o admin muda (o parceiro não se pode tirar a comissão).
create or replace function public._restaurants_farmacia_campos_so_admin()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  if auth.uid() is null or public.is_admin() then
    return new;
  end if;
  if new.so_lista_permissao is distinct from old.so_lista_permissao
     or new.pharmacy_prescription_mode is distinct from old.pharmacy_prescription_mode
     or new.partner_extra_commission_pct is distinct from old.partner_extra_commission_pct
     or new.partner_extra_commission_starts_at is distinct from old.partner_extra_commission_starts_at
     or new.aberta_ao_publico_em is distinct from old.aberta_ao_publico_em then
    raise exception 'Só a equipa Bora pode mudar estes campos da loja.' using errcode = '42501';
  end if;
  return new;
end $$;
drop trigger if exists trg_restaurants_farmacia_campos_so_admin on public.restaurants;
create trigger trg_restaurants_farmacia_campos_so_admin
  before update on public.restaurants
  for each row execute function public._restaurants_farmacia_campos_so_admin();

-- ---- Definições (todas editáveis no painel; nada cravado no código) -------------
insert into public.platform_settings (key, value, description, category) values
  ('pharmacy_prescription_response_minutes', '15'::jsonb,
   'Farmácias: minutos sem resposta até lembrar a farmácia; ao dobro o pedido de receita expira e o cliente é avisado.', 'farmacias'),
  ('pharmacy_prescription_retention_days', '30'::jsonb,
   'Farmácias: dias até apagar a foto da receita, a assinatura e os códigos depois da entrega, recusa ou expiração.', 'farmacias'),
  ('errand_pharmacy_driver_cents', '500'::jsonb,
   'Farmácias: o que o estafeta ganha num levantamento de receita (cêntimos). Por defeito igual ao Favor normal.', 'farmacias'),
  ('pharmacy_prescription_commission_pct', '0.10'::jsonb,
   'Farmácias: comissão sobre medicamentos com receita, a partir da mesma data da comissão extra da loja (adendo do Danilo 11/11).', 'farmacias'),
  ('pharmacy_extra_commission_months', '3'::jsonb,
   'Farmácias: meses sem comissão depois de a loja abrir ao público.', 'farmacias'),
  ('pharmacy_prescription_consent_version', '"v1-2026-11-11"'::jsonb,
   'Farmácias: versão do texto de autorização que o cliente assina.', 'farmacias'),
  ('pharmacy_prescription_consent_text',
   '"Autorizo o estafeta da Bora a levantar os meus medicamentos em meu nome na {farmacia}. A farmácia valida a receita e é responsável pela dispensa."'::jsonb,
   'Farmácias: texto de autorização ({farmacia} = nome da loja). Mudar o texto obriga a mudar a versão.', 'farmacias'),
  ('pharmacy_prescription_real_orders_enabled', 'false'::jsonb,
   'Farmácias: criar pedido real (estafeta + pagamento) quando o cliente confirma uma receita numa loja ABERTA. Desligado até ser provado.', 'farmacias')
on conflict (key) do nothing;

-- ---- Modo demonstração ------------------------------------------------------------
-- _modo_demo_loja: corpo da produção (Boom 27/10) + lojas escondidas com o cliente na lista.
create or replace function public._modo_demo_loja(p_rid text, p_uid uuid default null::uuid)
 returns boolean
 language sql
 stable security definer
 set search_path to 'public'
as $function$
  select coalesce((select (d->>'restaurant_id') = p_rid
                      and now() >= (d->>'inicio')::timestamptz and now() < (d->>'fim')::timestamptz
                      and (p_uid is null or (d->>'cliente_user_id')::uuid = p_uid)
                     from (select public._modo_demo_def() as d) s where s.d is not null), false)
      -- farmacias-2026-11-11: loja escondida (so_lista_permissao) = demonstração para quem está na lista
      or exists (select 1 from public.restaurants r
                  where r.id = p_rid and r.so_lista_permissao
                    and (p_uid is null or exists (select 1 from public.loja_lista_permissao l
                                                   where l.restaurant_id = r.id and l.user_id = p_uid)))
$function$;

-- _e_pedido_demo_loja: corpo da produção + pedidos de teste de lojas escondidas.
-- Efeito no despacho (_dispatch_candidatos_online): só o estafeta demo (_modo_demo_estafeta) recebe a oferta;
-- se não houver estafeta demo, ninguém recebe. Estafetas reais nunca.
create or replace function public._e_pedido_demo_loja(p_order_id text)
 returns boolean
 language sql
 stable security definer
 set search_path to 'public'
as $function$
  select exists (select 1 from public.orders o, (select public._modo_demo_def() as d) s
                  where o.id = p_order_id and coalesce(o.is_test_order, false) and s.d is not null
                    and o.restaurant_id = s.d->>'restaurant_id' and o.user_id = (s.d->>'cliente_user_id')::uuid)
      or exists (select 1 from public.orders o join public.restaurants r on r.id = o.restaurant_id
                  where o.id = p_order_id and coalesce(o.is_test_order, false) and r.so_lista_permissao)
$function$;

-- Guarda: numa loja escondida só entram pedidos de TESTE (em dinheiro, marcados pelo
-- a_trg_pedido_demo_caixa_fechada). Cartão / MB Way são recusados ANTES de haver cobrança.
-- Nome escolhido para correr depois de a_trg_pedido_demo_caixa_fechada e antes de aa_*.
create or replace function public._loja_escondida_so_pedidos_teste()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  if new.restaurant_id is null then
    return new;
  end if;
  if exists (select 1 from public.restaurants r where r.id = new.restaurant_id and r.so_lista_permissao)
     and not coalesce(new.is_test_order, false) then
    raise exception 'LOJA_EM_DEMONSTRACAO: Esta loja está em demonstração. Para experimentar escolha pagamento em dinheiro — nada é cobrado nem chamado nenhum estafeta.'
      using errcode = 'P0001', hint = 'LOJA_EM_DEMONSTRACAO';
  end if;
  return new;
end $$;
drop trigger if exists a_trg_pedido_demo_zz_loja_escondida on public.orders;
create trigger a_trg_pedido_demo_zz_loja_escondida
  before insert on public.orders
  for each row execute function public._loja_escondida_so_pedidos_teste();

-- C4 (29/10/2026, adendo 5, item 4) — Promoções com preço riscado.
-- PARTE QUE NÃO MEXE EM VALORES COBRADOS. Nada aqui altera o preço de um pedido: só prepara
-- os dados (datas da promoção, histórico de preços para a regra dos 30 dias), as funções de
-- consulta que a app usa para mostrar o preço riscado, e as funções de criar/ligar/desligar.
-- O servidor passar a aplicar o preço promocional é OUTRA coisa, escrita à parte e à espera de
-- confirmação (docs/propostas/missao-geral-2026-10-28/C4_promocoes/).
--
-- Interruptor: platform_settings.promotions_enabled, DESLIGADO por defeito. Mesmo ligado, a app
-- só mostra o preço riscado quando o servidor já aplica a promoção (ver _promotions_server_ready):
-- assim nunca se mostra um preço que depois não é o aplicado.
--
-- Todas as funções novas nascem fechadas a anon; só store_active_promotions é aberta a anon,
-- porque o catálogo já se vê antes do login (convidado) e ela só devolve o que já é público.

-- ─────────────────────────────────────────────────────────────────────────────
-- 1) Interruptor (nunca desfaz uma escolha do admin)
-- ─────────────────────────────────────────────────────────────────────────────
insert into public.platform_settings (key, value, description, category) values
  ('promotions_enabled', 'false'::jsonb,
   'Promoções com preço riscado (Diretiva Omnibus): preço antigo riscado, preço novo e a linha "Preço mais baixo dos últimos 30 dias". Desligado: tudo como hoje. Só ligar depois de o servidor aplicar o preço promocional (o painel de Promoções mostra se já aplica).',
   'cliente')
on conflict (key) do nothing;

-- ─────────────────────────────────────────────────────────────────────────────
-- 2) Colunas novas em products (todas opcionais)
--    discount_enabled: "desligar" uma promoção sem a perder (o admin liga/desliga).
-- ─────────────────────────────────────────────────────────────────────────────
alter table public.products
  add column if not exists discount_starts_at timestamptz,
  add column if not exists discount_ends_at timestamptz,
  add column if not exists discount_created_by uuid,
  add column if not exists discount_enabled boolean not null default true;

alter table public.products drop constraint if exists products_discount_window_ok;
alter table public.products
  add constraint products_discount_window_ok
  check (discount_ends_at is null or discount_starts_at is null or discount_ends_at > discount_starts_at);

-- ─────────────────────────────────────────────────────────────────────────────
-- 3) Decisão "esta promoção está ativa neste instante?" — uma só verdade para a app,
--    o painel e o servidor. Pura (só olha para os argumentos).
--    Só conta com data de início: um discount_price antigo sem datas (ex.: carregado por um
--    robô de catálogo) NÃO liga sozinho; o admin tem de lhe dar datas no painel.
-- ─────────────────────────────────────────────────────────────────────────────
create or replace function public.product_promo_active(
  p_price numeric,
  p_discount numeric,
  p_enabled boolean,
  p_starts timestamptz,
  p_ends timestamptz,
  p_at timestamptz default now()
) returns boolean
language sql
immutable
parallel safe
as $f$
  select coalesce(
    p_price is not null
    and p_discount is not null
    and p_discount > 0
    and p_discount < p_price
    and coalesce(p_enabled, true)
    and p_starts is not null
    and p_starts <= p_at
    and (p_ends is null or p_at < p_ends),
    false);
$f$;

create or replace function public._promotions_enabled()
returns boolean
language sql
stable
security definer
set search_path to 'public'
as $f$
  select coalesce(
    (select (s.value #>> '{}') = 'true' from public.platform_settings s where s.key = 'promotions_enabled'),
    false);
$f$;

-- O produto tem promoção ativa AGORA e o interruptor está ligado? Produto ao peso fica de fora
-- (as porções são calculadas à parte). Usada pela app e, na proposta de servidor, pelo preço.
create or replace function public.product_promocao_ativa(p_product_id text)
returns boolean
language sql
stable
security definer
set search_path to 'public'
as $f$
  select public._promotions_enabled()
     and exists (
       select 1 from public.products p
        where p.id = p_product_id
          and not coalesce(p.sold_by_weight, false)
          and public.product_promo_active(
                p.price::numeric, p.discount_price::numeric, p.discount_enabled,
                p.discount_starts_at, p.discount_ends_at, now()));
$f$;

-- O servidor de preços já usa a promoção? Verdade só quando as duas funções do checkout
-- chamam product_promocao_ativa (a proposta C4 faz isso). Lê o texto das funções em pg_proc.
create or replace function public._promotions_server_ready()
returns boolean
language sql
stable
set search_path to 'public', 'pg_catalog'
as $f$
  select (select count(*)
            from pg_proc p
           where p.oid in (to_regprocedure('public.quote_order_pricing(jsonb)'),
                           to_regprocedure('public.create_order(jsonb)'))
             and p.prosrc like '%product_promocao_ativa%') = 2;
$f$;

create or replace function public.promotions_status()
returns jsonb
language sql
stable
security definer
set search_path to 'public'
as $f$
  select jsonb_build_object(
    'enabled', public._promotions_enabled(),
    'server_ready', public._promotions_server_ready());
$f$;

-- ─────────────────────────────────────────────────────────────────────────────
-- 4) Histórico de preços por produto (Diretiva Omnibus: "preço mais baixo dos últimos 30 dias")
--    Escrita SÓ pelo gatilho. Leitura: dono da loja e admin.
-- ─────────────────────────────────────────────────────────────────────────────
create table if not exists public.product_price_history (
  id                  bigint generated always as identity primary key,
  product_id          text not null,
  restaurant_id       text,
  price               numeric,
  discount_price      numeric,
  discount_starts_at  timestamptz,
  discount_ends_at    timestamptz,
  discount_enabled    boolean,
  motivo              text not null default 'alteracao',
  changed_at          timestamptz not null default now(),
  changed_by          uuid
);

create index if not exists product_price_history_prod_idx
  on public.product_price_history (product_id, changed_at desc);

alter table public.product_price_history enable row level security;

drop policy if exists product_price_history_select on public.product_price_history;
create policy product_price_history_select
  on public.product_price_history for select to authenticated
  using (
    public.is_admin()
    or exists (select 1 from public.restaurants r
                where r.id = product_price_history.restaurant_id and r.user_id = auth.uid())
  );

revoke all on public.product_price_history from public, anon;
grant select on public.product_price_history to authenticated;

create or replace function public._products_price_history_ins()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $f$
begin
  insert into public.product_price_history
    (product_id, restaurant_id, price, discount_price, discount_starts_at, discount_ends_at,
     discount_enabled, motivo, changed_by)
  values
    (new.id, new.restaurant_id, new.price::numeric, new.discount_price::numeric,
     new.discount_starts_at, new.discount_ends_at, new.discount_enabled, 'insert', auth.uid());
  return new;
end
$f$;

create or replace function public._products_price_history_upd()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $f$
begin
  -- Produto que já existia antes do histórico: guarda primeiro o estado antigo, para o preço de
  -- ontem não se perder na primeira alteração.
  if not exists (select 1 from public.product_price_history h where h.product_id = new.id) then
    insert into public.product_price_history
      (product_id, restaurant_id, price, discount_price, discount_starts_at, discount_ends_at,
       discount_enabled, motivo, changed_by)
    values
      (old.id, old.restaurant_id, old.price::numeric, old.discount_price::numeric,
       old.discount_starts_at, old.discount_ends_at, old.discount_enabled, 'inicial', null);
  end if;
  insert into public.product_price_history
    (product_id, restaurant_id, price, discount_price, discount_starts_at, discount_ends_at,
     discount_enabled, motivo, changed_by)
  values
    (new.id, new.restaurant_id, new.price::numeric, new.discount_price::numeric,
     new.discount_starts_at, new.discount_ends_at, new.discount_enabled, 'alteracao', auth.uid());
  return new;
end
$f$;

revoke all on function public._products_price_history_ins() from public, anon, authenticated;
revoke all on function public._products_price_history_upd() from public, anon, authenticated;

drop trigger if exists trg_products_price_history_ins on public.products;
create trigger trg_products_price_history_ins
  after insert on public.products
  for each row execute function public._products_price_history_ins();

drop trigger if exists trg_products_price_history_upd on public.products;
create trigger trg_products_price_history_upd
  after update of price, discount_price, discount_starts_at, discount_ends_at, discount_enabled
  on public.products
  for each row
  when (old.price is distinct from new.price
     or old.discount_price is distinct from new.discount_price
     or old.discount_starts_at is distinct from new.discount_starts_at
     or old.discount_ends_at is distinct from new.discount_ends_at
     or old.discount_enabled is distinct from new.discount_enabled)
  execute function public._products_price_history_upd();

-- ─────────────────────────────────────────────────────────────────────────────
-- 5) Preço mais baixo dos últimos 30 dias (menor preço EFETIVO aplicado)
--    Janela: os 30 dias antes de a redução atual começar (se não há promoção ativa, antes de
--    agora). Em cada troço do histórico conta o preço normal, salvo se uma promoção válida o
--    cobriu o troço todo, e conta o promocional se esteve em vigor em algum instante.
--    Sem histórico na janela: o preço atual. O primeiro troço vale desde sempre.
-- ─────────────────────────────────────────────────────────────────────────────
create or replace function public.product_lowest_price_30d(p_product_id text)
returns numeric
language plpgsql
stable
security definer
set search_path to 'public'
as $f$
declare
  v_p   record;
  v_ref timestamptz;
  v_ini timestamptz;
  v_min numeric;
begin
  select p.price::numeric as price, p.discount_price::numeric as discount_price,
         p.discount_enabled, p.discount_starts_at, p.discount_ends_at
    into v_p
    from public.products p
   where p.id = p_product_id;
  if not found then
    return null;
  end if;

  v_ref := now();
  if public.product_promo_active(v_p.price, v_p.discount_price, v_p.discount_enabled,
                                 v_p.discount_starts_at, v_p.discount_ends_at, now()) then
    v_ref := least(v_p.discount_starts_at, now());
  end if;
  v_ini := v_ref - interval '30 days';

  with seg as (
    select h.price, h.discount_price, h.discount_enabled,
           h.discount_starts_at as ps, h.discount_ends_at as pe,
           case when row_number() over (order by h.changed_at, h.id) = 1
                then '-infinity'::timestamptz else h.changed_at end as t0,
           coalesce(lead(h.changed_at) over (order by h.changed_at, h.id),
                    'infinity'::timestamptz) as t1
      from public.product_price_history h
     where h.product_id = p_product_id
  ), j as (
    select s.*,
           greatest(s.t0, v_ini) as a,
           least(s.t1, v_ref) as b,
           (s.discount_price is not null and s.discount_price > 0 and s.price is not null
            and s.discount_price < s.price and coalesce(s.discount_enabled, true)
            and s.ps is not null) as valida
      from seg s
  ), k as (
    select j.*,
           (j.valida and j.ps <= j.a
            and coalesce(j.pe, 'infinity'::timestamptz) >= j.b) as coberto
      from j
     where j.a < j.b
  )
  select min(least(
           case when not k.coberto then k.price end,
           case when k.valida and k.ps < k.b
                 and coalesce(k.pe, 'infinity'::timestamptz) > k.a
                then k.discount_price end))
    into v_min
    from k;

  return coalesce(v_min, v_p.price);
end
$f$;

-- ─────────────────────────────────────────────────────────────────────────────
-- 6) O que a app lê: as promoções ativas de uma loja, com o preço mais baixo dos 30 dias.
--    Só devolve linhas com o interruptor ligado E o servidor já a aplicar a promoção.
-- ─────────────────────────────────────────────────────────────────────────────
create or replace function public.store_active_promotions(p_restaurant_id text)
returns table (
  product_id        text,
  price             numeric,
  discount_price    numeric,
  starts_at         timestamptz,
  ends_at           timestamptz,
  lowest_price_30d  numeric
)
language sql
stable
security definer
set search_path to 'public'
as $f$
  select p.id,
         p.price::numeric,
         p.discount_price::numeric,
         p.discount_starts_at,
         p.discount_ends_at,
         public.product_lowest_price_30d(p.id)
    from public.products p
   where p.restaurant_id = p_restaurant_id
     and public._promotions_enabled()
     and public._promotions_server_ready()
     and not coalesce(p.sold_by_weight, false)
     and public.product_promo_active(
           p.price::numeric, p.discount_price::numeric, p.discount_enabled,
           p.discount_starts_at, p.discount_ends_at, now());
$f$;

-- ─────────────────────────────────────────────────────────────────────────────
-- 7) Auditoria (admin_audit_log; o id do produto é texto, vai em entity_id_text)
-- ─────────────────────────────────────────────────────────────────────────────
create or replace function public._promotions_audit(p_action text, p_product_id text, p_details jsonb)
returns void
language plpgsql
security definer
set search_path to 'public'
as $f$
begin
  insert into public.admin_audit_log
    (admin_id, admin_email, action, entity_type, entity_id_text, details)
  values
    (auth.uid(), coalesce(auth.jwt() ->> 'email', ''), p_action, 'product', p_product_id,
     coalesce(p_details, '{}'::jsonb)
       || jsonb_build_object('autor', case when public.is_admin() then 'admin' else 'parceiro' end));
end
$f$;

-- ─────────────────────────────────────────────────────────────────────────────
-- 8) Criar / terminar uma promoção (dono da loja ou admin)
--    p_discount_price é no MESMO sentido que products.price (o preço de catálogo; numa loja
--    parceira já com a comissão por cima — a app converte o balcão antes de chamar).
--    p_discount_price nulo = terminar a promoção.
-- ─────────────────────────────────────────────────────────────────────────────
create or replace function public.partner_set_promotion(
  p_product_id     text,
  p_discount_price numeric,
  p_starts_at      timestamptz default null,
  p_ends_at        timestamptz default null
) returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $f$
declare
  v_uid   uuid := auth.uid();
  v_admin boolean := coalesce(public.is_admin(), false);
  v_p     record;
  v_start timestamptz;
  v_new   numeric;
begin
  if v_uid is null then
    raise exception 'not_authenticated' using errcode = '42501';
  end if;

  select p.id, p.restaurant_id, p.name, p.price::numeric as price,
         coalesce(p.sold_by_weight, false) as por_peso
    into v_p
    from public.products p
   where p.id = p_product_id;
  if not found then
    raise exception 'product_not_found';
  end if;

  if not v_admin and not exists (
       select 1 from public.restaurants r
        where r.id = v_p.restaurant_id and r.user_id = v_uid) then
    raise exception 'not_owner_nor_admin' using errcode = '42501';
  end if;

  if p_discount_price is null then
    update public.products
       set discount_price = null, discount_starts_at = null, discount_ends_at = null,
           discount_created_by = null, discount_enabled = true
     where id = p_product_id;
    perform public._promotions_audit('promotion_cleared', p_product_id,
      jsonb_build_object('produto', v_p.name));
    return jsonb_build_object('ok', true, 'cleared', true);
  end if;

  if v_p.por_peso then
    raise exception 'promo_nao_suporta_peso: produto vendido ao peso não leva preço promocional';
  end if;
  v_new := round(p_discount_price, 2);
  if v_new <= 0 or v_new >= v_p.price then
    raise exception 'promo_preco_invalido: o preço promocional tem de ser maior que zero e menor que o preço normal (%)', v_p.price;
  end if;
  v_start := coalesce(p_starts_at, now());
  if p_ends_at is not null and p_ends_at <= v_start then
    raise exception 'promo_datas_invalidas: o fim tem de ser depois do início';
  end if;
  if p_ends_at is not null and p_ends_at <= now() then
    raise exception 'promo_datas_invalidas: o fim já passou';
  end if;

  update public.products
     set discount_price = v_new,
         discount_starts_at = v_start,
         discount_ends_at = p_ends_at,
         discount_created_by = v_uid,
         discount_enabled = true
   where id = p_product_id;

  perform public._promotions_audit('promotion_set', p_product_id,
    jsonb_build_object('produto', v_p.name, 'preco_normal', v_p.price, 'preco_promocional', v_new,
                       'inicio', v_start, 'fim', p_ends_at));

  return jsonb_build_object('ok', true, 'product_id', p_product_id, 'discount_price', v_new,
                            'starts_at', v_start, 'ends_at', p_ends_at);
end
$f$;

-- ─────────────────────────────────────────────────────────────────────────────
-- 9) Painel admin
-- ─────────────────────────────────────────────────────────────────────────────
create or replace function public.admin_promotions_list()
returns table (
  product_id          text,
  product_name        text,
  restaurant_id       text,
  restaurant_name     text,
  is_partner          boolean,
  price               numeric,
  discount_price      numeric,
  starts_at           timestamptz,
  ends_at             timestamptz,
  enabled             boolean,
  created_by          uuid,
  created_by_email    text,
  lowest_price_30d    numeric,
  sold_by_weight      boolean
)
language plpgsql
stable
security definer
set search_path to 'public'
as $f$
begin
  if not public.is_admin() then
    raise exception 'admin_required' using errcode = '42501';
  end if;
  return query
    select p.id, p.name::text, p.restaurant_id, r.name::text, coalesce(r.is_partner, false),
           p.price::numeric, p.discount_price::numeric,
           p.discount_starts_at, p.discount_ends_at, p.discount_enabled,
           p.discount_created_by,
           (select u.email::text from auth.users u where u.id = p.discount_created_by),
           public.product_lowest_price_30d(p.id),
           coalesce(p.sold_by_weight, false)
      from public.products p
      left join public.restaurants r on r.id = p.restaurant_id
     where p.discount_price is not null
     order by p.discount_starts_at desc nulls last, p.id
     limit 1000;
end
$f$;

create or replace function public.admin_promotion_toggle(
  p_product_id text,
  p_enabled    boolean,
  p_reason     text default null
) returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $f$
declare
  v_name text;
begin
  if not public.is_admin() then
    raise exception 'admin_required' using errcode = '42501';
  end if;
  if p_enabled is null then
    raise exception 'valor_invalido';
  end if;
  update public.products
     set discount_enabled = p_enabled
   where id = p_product_id and discount_price is not null
  returning name into v_name;
  if not found then
    raise exception 'promo_not_found';
  end if;
  perform public._promotions_audit(
    case when p_enabled then 'promotion_enabled' else 'promotion_disabled' end,
    p_product_id,
    jsonb_build_object('produto', v_name, 'motivo', p_reason));
  return jsonb_build_object('ok', true, 'product_id', p_product_id, 'enabled', p_enabled);
end
$f$;

create or replace function public.admin_promotions_audit(p_limit integer default 60)
returns table (
  created_at   timestamptz,
  admin_email  text,
  action       text,
  product_id   text,
  product_name text,
  details      jsonb
)
language plpgsql
stable
security definer
set search_path to 'public'
as $f$
begin
  if not public.is_admin() then
    raise exception 'admin_required' using errcode = '42501';
  end if;
  return query
    select a.created_at, a.admin_email::text, a.action::text, a.entity_id_text::text,
           (select p.name::text from public.products p where p.id = a.entity_id_text),
           a.details
      from public.admin_audit_log a
     where a.action like 'promotion\_%' escape '\'
        or (a.action = 'platform_setting_updated' and a.details ->> 'key' = 'promotions_enabled')
     order by a.created_at desc
     limit least(greatest(coalesce(p_limit, 60), 1), 500);
end
$f$;

-- ─────────────────────────────────────────────────────────────────────────────
-- 10) Permissões: tudo fechado a anon, salvo a leitura pública do catálogo
-- ─────────────────────────────────────────────────────────────────────────────
revoke all on function public.product_promo_active(numeric, numeric, boolean, timestamptz, timestamptz, timestamptz) from public, anon;
revoke all on function public._promotions_enabled() from public, anon;
revoke all on function public.product_promocao_ativa(text) from public, anon;
revoke all on function public._promotions_server_ready() from public, anon;
revoke all on function public.promotions_status() from public, anon;
revoke all on function public.product_lowest_price_30d(text) from public, anon;
revoke all on function public.store_active_promotions(text) from public, anon;
revoke all on function public._promotions_audit(text, text, jsonb) from public, anon, authenticated;
revoke all on function public.partner_set_promotion(text, numeric, timestamptz, timestamptz) from public, anon;
revoke all on function public.admin_promotions_list() from public, anon;
revoke all on function public.admin_promotion_toggle(text, boolean, text) from public, anon;
revoke all on function public.admin_promotions_audit(integer) from public, anon;

grant execute on function public.product_promo_active(numeric, numeric, boolean, timestamptz, timestamptz, timestamptz) to authenticated, service_role;
grant execute on function public._promotions_enabled() to authenticated, service_role;
grant execute on function public.product_promocao_ativa(text) to authenticated, service_role;
grant execute on function public._promotions_server_ready() to authenticated, service_role;
grant execute on function public.promotions_status() to authenticated;
grant execute on function public.product_lowest_price_30d(text) to authenticated, service_role;
-- Aberta a anon de propósito: o catálogo vê-se antes do login (convidado) e esta função só
-- devolve preços que já são públicos na tabela products.
grant execute on function public.store_active_promotions(text) to anon, authenticated;
grant execute on function public.partner_set_promotion(text, numeric, timestamptz, timestamptz) to authenticated;
grant execute on function public.admin_promotions_list() to authenticated;
grant execute on function public.admin_promotion_toggle(text, boolean, text) to authenticated;
grant execute on function public.admin_promotions_audit(integer) to authenticated;
